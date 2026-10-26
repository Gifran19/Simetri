import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

export interface ClaimDeviceRequest {
  pairingCode: string;
  /** Parameter pengujian internal untuk simulasi crash/gangguan setelah secret diklaim */
  _testSimulateCrashAfterSecretClaim?: boolean;
}

export interface ClaimDeviceResponse {
  success: boolean;
  deviceId: string;
  message: string;
}

export interface PairingSecretData {
  deviceId: string;
  expiresAt: number;
  used: boolean;
  usedBy: string | null;
  usedAt: number | null;
  createdAt: number;
  status?: 'available' | 'pending_permission' | 'completed' | 'revoked';
  revokedAt?: number | null;
  revokedReason?: string | null;
}

export interface DeviceMetaData {
  deviceId: string;
  label?: string;
  ownerUid?: string | null;
  claimedAt?: number | null;
  activePairingHash?: string | null;
  registeredAt?: number;
  registeredBy?: string;
  deviceUid?: string | null;
}

const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 menit

/**
 * KETERBATASAN RATE LIMITING BERBASIS UID ANONIM:
 * Rate limiting ini mengandalkan auth.uid dari Firebase Anonymous Authentication.
 * Keterbatasan: Pengguna/penyerang yang menghapus local storage atau menginstal ulang
 * aplikasi dapat memicu pembuatan UID anonim baru sehingga kuota percobaan di-reset.
 * Pada lingkungan produksi skala besar, lapisan pertahanan ini harus dilengkapi dengan:
 * 1. Firebase App Check (DeviceCheck / Play Integrity) untuk memastikan request hanya
 *    berasal dari aplikasi resmi yang belum dimodifikasi.
 * 2. Rate limiting IP Address di reverse proxy / Cloud Armor / Firebase WAF.
 */
export async function handleClaimDevice(
  request: CallableRequest<ClaimDeviceRequest>,
  db: admin.database.Database
): Promise<ClaimDeviceResponse> {
  // 1. Validasi Autentikasi Pemanggil (Anonymous UID)
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      'unauthenticated',
      'Pengguna harus terautentikasi sebelum melakukan pairing perangkat.'
    );
  }

  const callerUid = request.auth.uid;
  const rawCode = request.data?.pairingCode;

  if (!rawCode || typeof rawCode !== 'string') {
    throw new HttpsError(
      'invalid-argument',
      'Kode pairing wajib diisi.'
    );
  }

  const normalizedCode = rawCode.trim().toUpperCase();
  if (normalizedCode.length < 6 || normalizedCode.length > 32) {
    throw new HttpsError(
      'invalid-argument',
      'Format kode pairing tidak valid.'
    );
  }

  // 2. Pemeriksaan Rate Limiting per UID
  const now = Date.now();
  const rateLimitRef = db.ref(`pairing_rate_limits/${callerUid}`);
  const rateLimitSnap = await rateLimitRef.get();
  
  if (rateLimitSnap.exists()) {
    const rlData = rateLimitSnap.val();
    if (
      rlData.attempts >= MAX_FAILED_ATTEMPTS &&
      now - (rlData.lastAttempt || 0) < RATE_LIMIT_WINDOW_MS
    ) {
      const waitMinutes = Math.ceil(
        (RATE_LIMIT_WINDOW_MS - (now - rlData.lastAttempt)) / 60000
      );
      throw new HttpsError(
        'resource-exhausted',
        `Terlalu banyak percobaan gagal. Silakan tunggu ${waitMinutes} menit sebelum mencoba lagi.`
      );
    }
  }

  // 3. Hash Kode Pairing Menggunakan SHA-256
  const hash = crypto.createHash('sha256').update(normalizedCode).digest('hex');
  const secretRef = db.ref(`pairing_secrets/${hash}`);

  // 4. Verifikasi Keberadaan Secret di Database
  const secretSnap = await secretRef.get();
  if (!secretSnap.exists()) {
    await recordFailedAttemptAtomic(rateLimitRef, now);
    throw new HttpsError(
      'not-found',
      'Kode pairing tidak ditemukan atau salah. Periksa kembali kode Anda.'
    );
  }

  const existingSecret = secretSnap.val() as PairingSecretData;

  // 4a. Pencabutan: Jika status kode pairing sudah 'revoked', tolak langsung
  if (existingSecret.status === 'revoked') {
    await recordFailedAttemptAtomic(rateLimitRef, now);
    throw new HttpsError(
      'permission-denied',
      'Kode pairing ini telah dicabut atau digantikan oleh kode baru.'
    );
  }

  const targetDeviceId = existingSecret.deviceId;
  const deviceMetaRef = db.ref(`devices/${targetDeviceId}/meta`);

  // 4b. Idempotensi & Pemulihan Parsial (Recovery):
  // Jika kode sudah terpakai oleh pemanggil yang sama
  if (existingSecret.used && existingSecret.usedBy === callerUid) {
    const metaSnap = await deviceMetaRef.get();
    const metaData = metaSnap.val() as DeviceMetaData | null;

    // Jika kepemilikan perangkat di meta sudah berpindah ke orang lain
    if (metaData?.ownerUid && metaData.ownerUid !== callerUid) {
      throw new HttpsError(
        'failed-precondition',
        'Kepemilikan perangkat ini telah dialihkan ke pengguna lain.'
      );
    }

    // Jika izin perangkat sengaja dicabut (ownerUid telah null) dan status secret sudah 'completed'
    if (existingSecret.status === 'completed' && metaData?.ownerUid !== callerUid) {
      throw new HttpsError(
        'failed-precondition',
        'Izin untuk perangkat ini telah dicabut. Anda memerlukan kode pairing baru.'
      );
    }

    // Jika status secret 'pending_permission' (terjadi kegagalan parsial sebelum izin tersimpan),
    // atau izin belum lengkap, lakukan pemulihan (recovery) secara atomik
    const recoveryUpdates: Record<string, unknown> = {};
    recoveryUpdates[`permissions/${callerUid}/${targetDeviceId}`] = {
      role: 'owner',
      grantedAt: now,
    };
    recoveryUpdates[`devices/${targetDeviceId}/meta/ownerUid`] = callerUid;
    recoveryUpdates[`devices/${targetDeviceId}/meta/claimedAt`] = now;
    recoveryUpdates[`pairing_secrets/${hash}/status`] = 'completed';
    recoveryUpdates[`pairing_rate_limits/${callerUid}`] = null;
    await db.ref().update(recoveryUpdates);

    return {
      success: true,
      deviceId: targetDeviceId,
      message: 'Pemulihan pairing perangkat berhasil diselesaikan.',
    };
  }

  // 4c. Kunci Kepemilikan pada Tingkat Perangkat:
  // Periksa apakah perangkat sudah dimiliki oleh orang lain sebelum klaim
  const currentDeviceMetaSnap = await deviceMetaRef.get();
  if (currentDeviceMetaSnap.exists()) {
    const currentMeta = currentDeviceMetaSnap.val() as DeviceMetaData;
    if (currentMeta.ownerUid && currentMeta.ownerUid !== callerUid) {
      await recordFailedAttemptAtomic(rateLimitRef, now);
      throw new HttpsError(
        'failed-precondition',
        'Perangkat ini sudah terhubung dengan pemilik lain. Lakukan unpair terlebih dahulu.'
      );
    }
  }

  // 5. Transaksi Atomik pada pairing_secrets untuk Menghindari Race Condition
  let failureReason: 'already_used' | 'expired' | 'revoked' | null = null;

  try {
    const txSecretResult = await secretRef.transaction((currentData: PairingSecretData | null) => {
      // Pada pass awal lokal Firebase SDK, currentData bisa berupa null sementara data diambil dari server.
      if (currentData === null) {
        return currentData;
      }

      if (currentData.status === 'revoked') {
        failureReason = 'revoked';
        return; // membatalkan transaksi
      }

      if (currentData.used) {
        failureReason = 'already_used';
        return; // membatalkan transaksi
      }

      if (now > currentData.expiresAt) {
        failureReason = 'expired';
        return; // membatalkan transaksi
      }

      // Valid: tandai terpakai dengan status pending_permission
      return {
        ...currentData,
        used: true,
        usedBy: callerUid,
        usedAt: now,
        status: 'pending_permission',
      };
    });

    // Periksa apakah transaksi secret berhasil di-commit
    if (!txSecretResult.committed || !txSecretResult.snapshot.exists()) {
      await recordFailedAttemptAtomic(rateLimitRef, now);

      if (failureReason === 'revoked') {
        throw new HttpsError(
          'permission-denied',
          'Kode pairing ini telah dicabut atau digantikan oleh kode baru.'
        );
      } else if (failureReason === 'already_used') {
        throw new HttpsError(
          'failed-precondition',
          'Kode pairing ini sudah pernah digunakan sebelumnya.'
        );
      } else if (failureReason === 'expired') {
        throw new HttpsError(
          'deadline-exceeded',
          'Kode pairing telah kedaluwarsa. Mintalah kode baru.'
        );
      } else {
        throw new HttpsError(
          'aborted',
          'Klaim gagal karena konflik konkurensi pada kode pairing. Silakan coba lagi.'
        );
      }
    }

    const claimedSecret = txSecretResult.snapshot.val() as PairingSecretData;
    const deviceId = claimedSecret.deviceId;

    // 6. Transaksi Atomik Penguncian Kepemilikan pada Perangkat (Device-Level Lock):
    // Memastikan dua kode berbeda untuk perangkat yang sama tidak memberikan kepemilikan ganda
    let deviceConflict = false;
    const txDeviceResult = await db.ref(`devices/${deviceId}/meta`).transaction((currentMeta: DeviceMetaData | null) => {
      if (currentMeta === null) {
        // Metadata belum ada di database, inisialisasi dengan owner
        return {
          deviceId,
          ownerUid: callerUid,
          claimedAt: now,
        };
      }

      // Jika perangkat sudah memiliki pemilik lain
      if (currentMeta.ownerUid && currentMeta.ownerUid !== callerUid) {
        deviceConflict = true;
        return; // Batalkan transaksi perangkat
      }

      return {
        ...currentMeta,
        ownerUid: callerUid,
        claimedAt: now,
      };
    });

    if (!txDeviceResult.committed || deviceConflict) {
      // Perangkat sudah diklaim oleh orang lain melalui kode lain
      // Batalkan klaim secret agar tidak terkunci sia-sia
      await secretRef.update({
        used: false,
        usedBy: null,
        usedAt: null,
        status: 'available',
      });
      await recordFailedAttemptAtomic(rateLimitRef, now);
      throw new HttpsError(
        'failed-precondition',
        'Perangkat ini telah diklaim oleh pengguna lain.'
      );
    }

    // Simulasi kegagalan untuk pengujian parsial (jika diaktifkan)
    if (request.data?._testSimulateCrashAfterSecretClaim) {
      throw new Error('SIMULATED_CRASH_AFTER_SECRET_CLAIM');
    }

    // 7. Backend Menetapkan Izin UID terhadap Perangkat Secara Atomik (Finalisasi)
    const multiPathUpdates: Record<string, unknown> = {};
    multiPathUpdates[`permissions/${callerUid}/${deviceId}`] = {
      role: 'owner',
      grantedAt: now,
    };
    multiPathUpdates[`pairing_secrets/${hash}/status`] = 'completed';
    multiPathUpdates[`pairing_rate_limits/${callerUid}`] = null; // Reset rate limit saat berhasil

    await db.ref().update(multiPathUpdates);

    return {
      success: true,
      deviceId,
      message: 'Perangkat berhasil dipasangkan ke akun Anda.',
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    if ((error as Error)?.message === 'SIMULATED_CRASH_AFTER_SECRET_CLAIM') {
      throw new HttpsError('internal', 'Simulasi crash sebelum izin tersimpan.');
    }
    console.error('Unhandled pairing error:', error);
    throw new HttpsError(
      'internal',
      'Terjadi kesalahan internal saat memproses pairing.'
    );
  }
}

/**
 * Mencatat percobaan gagal secara atomik menggunakan transaksi
 * Mencegah lost updates ketika ada banyak request serentak
 */
async function recordFailedAttemptAtomic(
  rateLimitRef: admin.database.Reference,
  now: number
): Promise<void> {
  await rateLimitRef.transaction((currentRl: { attempts?: number; lastAttempt?: number } | null) => {
    const isExpiredWindow =
      currentRl &&
      currentRl.lastAttempt &&
      now - currentRl.lastAttempt > RATE_LIMIT_WINDOW_MS;

    if (!currentRl || isExpiredWindow) {
      return {
        attempts: 1,
        lastAttempt: now,
      };
    }

    return {
      attempts: (currentRl.attempts || 0) + 1,
      lastAttempt: now,
    };
  });
}
