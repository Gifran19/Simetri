import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

export interface ClaimDeviceRequest {
  pairingCode: string;
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
  status?: 'available' | 'used' | 'revoked';
  revokedAt?: number | null;
  revokedReason?: string | null;
  createdAt: number;
}

export interface DeviceMetaData {
  deviceId: string;
  label?: string;
  ownerUid?: string | null;
  claimOpId?: string | null;
  claimedAt?: number | null;
  registeredAt?: number;
  activePairingHash?: string;
  deviceUid?: string;
}

const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 menit

/**
 * Memeriksa apakah UID pemanggil saat ini sedang dalam status terblokir oleh rate limiter.
 * PENTING: Pemeriksaan ini dijalankan sebelum memproses kode apapun.
 */
export async function assertCallerNotRateLimited(
  rateLimitRef: admin.database.Reference,
  now: number
): Promise<void> {
  const snapshot = await rateLimitRef.get();
  if (!snapshot.exists()) return;

  const data = snapshot.val();
  const attempts = data?.attempts || 0;
  const lastAttempt = data?.lastAttempt || 0;

  if (attempts >= MAX_FAILED_ATTEMPTS && now - lastAttempt < RATE_LIMIT_WINDOW_MS) {
    const remainingMinutes = Math.ceil(
      (RATE_LIMIT_WINDOW_MS - (now - lastAttempt)) / 60000
    );
    throw new HttpsError(
      'resource-exhausted',
      `Terlalu banyak percobaan gagal. Akun Anda sedang dibatasi. Silakan tunggu ${remainingMinutes} menit sebelum mencoba lagi.`
    );
  }
}

/**
 * Mencatat kegagalan percobaan klaim secara transaksional agar aman dari race condition.
 */
export async function recordFailedAttemptTx(
  rateLimitRef: admin.database.Reference,
  now: number
): Promise<void> {
  await rateLimitRef.transaction((current) => {
    if (!current || now - (current.lastAttempt || 0) > RATE_LIMIT_WINDOW_MS) {
      return { attempts: 1, lastAttempt: now };
    }

    return {
      attempts: (current.attempts || 0) + 1,
      lastAttempt: now,
    };
  });
}

export async function handleClaimDevice(
  request: CallableRequest<ClaimDeviceRequest>,
  db: admin.database.Database
): Promise<ClaimDeviceResponse> {
  // 1. Validasi Autentikasi Pemanggil
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      'unauthenticated',
      'Pengguna harus terautentikasi sebelum melakukan pairing perangkat.'
    );
  }

  const callerUid = request.auth.uid;
  const rawCode = request.data?.pairingCode;

  if (!rawCode || typeof rawCode !== 'string') {
    throw new HttpsError('invalid-argument', 'Kode pairing wajib diisi.');
  }

  const now = Date.now();
  const rateLimitRef = db.ref(`pairing_rate_limits/${callerUid}`);

  // 2. PRIORITAS 5: Periksa status rate-limit SEBELUM memproses semua kode.
  // Jika pemanggil sedang dalam status terblokir, kode valid sekalipun harus langsung ditolak!
  await assertCallerNotRateLimited(rateLimitRef, now);

  const normalizedCode = rawCode.trim().toUpperCase();
  if (normalizedCode.length < 6 || normalizedCode.length > 32) {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError('invalid-argument', 'Format kode pairing tidak valid.');
  }

  // 3. Hash Kode Pairing Menggunakan SHA-256
  const hash = crypto.createHash('sha256').update(normalizedCode).digest('hex');
  const secretRef = db.ref(`pairing_secrets/${hash}`);

  // 4. Verifikasi Keberadaan Secret di Database
  const secretSnap = await secretRef.get();
  if (!secretSnap.exists()) {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError(
      'not-found',
      'Kode pairing tidak ditemukan atau salah. Periksa kembali kode Anda.'
    );
  }

  const secretData = secretSnap.val() as PairingSecretData;
  const deviceId = secretData.deviceId;

  // 5. Periksa apakah kode telah dicabut (revoked) oleh admin
  if (secretData.status === 'revoked') {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Kode pairing ini telah dicabut atau digantikan oleh kode baru.'
    );
  }

  // 6. PRIORITAS 4: Penanganan Idempotensi, Retry, dan Pemulihan (Recovery) Aman
  if (secretData.used && secretData.usedBy === callerUid) {
    // 6a. Cek apakah izin pengguna sengaja dicabut
    const permSnap = await db.ref(`permissions/${callerUid}/${deviceId}`).get();
    if (permSnap.exists() && permSnap.val()?.status === 'revoked') {
      throw new HttpsError(
        'failed-precondition',
        'Izin akses untuk perangkat ini telah dicabut oleh administrator.'
      );
    }

    // 6b. Cek metadata perangkat: RECOVERY TIDAK BOLEH MENIMPA PEMILIK BARU!
    const metaSnap = await db.ref(`devices/${deviceId}/meta`).get();
    const currentMeta = (metaSnap.val() || {}) as DeviceMetaData;

    if (currentMeta.ownerUid && currentMeta.ownerUid !== callerUid) {
      throw new HttpsError(
        'failed-precondition',
        'Perangkat ini telah dipindahtangankan ke pemilik baru.'
      );
    }

    // 6c. Pulihkan jika belum lengkap (misal akibat crash jaringan sebelum permissions tersimpan)
    if (!permSnap.exists() || currentMeta.ownerUid !== callerUid) {
      const recoveryUpdates: Record<string, unknown> = {};
      recoveryUpdates[`permissions/${callerUid}/${deviceId}`] = {
        role: 'owner',
        status: 'active',
        grantedAt: secretData.usedAt || now,
      };
      recoveryUpdates[`devices/${deviceId}/meta/ownerUid`] = callerUid;
      recoveryUpdates[`devices/${deviceId}/meta/claimedAt`] = secretData.usedAt || now;
      await db.ref().update(recoveryUpdates);
    }

    return {
      success: true,
      deviceId,
      message: 'Perangkat sudah berhasil terpasang pada akun Anda.',
    };
  }

  // Jika sudah terpakai oleh pengguna lain
  if (secretData.used && secretData.usedBy !== callerUid) {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Kode pairing ini sudah pernah digunakan sebelumnya.'
    );
  }

  // Jika kode sudah kedaluwarsa
  if (now > secretData.expiresAt) {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError(
      'deadline-exceeded',
      'Kode pairing telah kedaluwarsa. Mintalah kode baru.'
    );
  }

  // 7. KUNCI KEPEMILIKAN TINGKAT PERANGKAT DENGAN CLAIM OPERATION ID
  // Mencegah dua kode berbeda mengklaim perangkat yang sama
  const metaRef = db.ref(`devices/${deviceId}/meta`);
  const claimOpId = crypto.randomUUID();
  let deviceOwnershipConflict = false;

  const deviceLockResult = await metaRef.transaction((currentMeta: DeviceMetaData | null) => {
    if (currentMeta === null) {
      return {
        deviceId,
        ownerUid: callerUid,
        claimOpId,
        claimedAt: now,
      };
    }

    // Jika perangkat sudah memiliki pemilik aktif dan bukan callerUid
    if (currentMeta.ownerUid && currentMeta.ownerUid !== callerUid) {
      deviceOwnershipConflict = true;
      return; // batalkan
    }

    return {
      ...currentMeta,
      ownerUid: callerUid,
      claimOpId,
      claimedAt: now,
    };
  });

  if (deviceOwnershipConflict || !deviceLockResult.committed) {
    await recordFailedAttemptTx(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Perangkat ini sudah terdaftar dan dimiliki oleh pengguna lain.'
    );
  }

  // 8. TRANSAKSI ATOMIK PADA PAIRING SECRETS
  let secretFailureReason: 'already_used' | 'expired' | 'revoked' | null = null;

  try {
    const txSecretResult = await secretRef.transaction((currentSecret: PairingSecretData | null) => {
      if (currentSecret === null) {
        return currentSecret;
      }

      if (currentSecret.status === 'revoked') {
        secretFailureReason = 'revoked';
        return;
      }

      if (currentSecret.used) {
        secretFailureReason = 'already_used';
        return;
      }

      if (now > currentSecret.expiresAt) {
        secretFailureReason = 'expired';
        return;
      }

      return {
        ...currentSecret,
        used: true,
        usedBy: callerUid,
        usedAt: now,
        status: 'used',
      };
    });

    if (!txSecretResult.committed || !txSecretResult.snapshot.exists()) {
      const currentSecretVal = txSecretResult.snapshot.val() as PairingSecretData | null;
      if (currentSecretVal && currentSecretVal.usedBy === callerUid) {
        // Permintaan paralel dari UID yang sama baru saja menyelesaikan klaim dengan sukses.
        // Kembalikan respons sukses yang konsisten tanpa rollback.
        return {
          success: true,
          deviceId,
          message: 'Perangkat berhasil dipasangkan ke akun Anda.',
        };
      }

      // ROLLBACK AMAN: Hanya rollback jika claimOpId masih milik operasi INI!
      await metaRef.transaction((currentMeta: DeviceMetaData | null) => {
        if (
          currentMeta &&
          currentMeta.claimOpId === claimOpId &&
          currentMeta.ownerUid === callerUid
        ) {
          return {
            ...currentMeta,
            ownerUid: null,
            claimOpId: null,
            claimedAt: null,
          };
        }
        return currentMeta;
      });

      await recordFailedAttemptTx(rateLimitRef, now);

      if (secretFailureReason === 'revoked') {
        throw new HttpsError(
          'failed-precondition',
          'Kode pairing ini telah dicabut atau digantikan oleh kode baru.'
        );
      } else if (secretFailureReason === 'already_used') {
        throw new HttpsError(
          'failed-precondition',
          'Kode pairing ini sudah pernah digunakan sebelumnya.'
        );
      } else if (secretFailureReason === 'expired') {
        throw new HttpsError(
          'deadline-exceeded',
          'Kode pairing telah kedaluwarsa. Mintalah kode baru.'
        );
      } else {
        throw new HttpsError(
          'aborted',
          'Klaim gagal karena adanya konflik konkurensi. Silakan ulangi.'
        );
      }
    }

    // 9. Menetapkan Izin Pengguna Secara Atomik di Database
    const multiPathUpdates: Record<string, unknown> = {};
    multiPathUpdates[`permissions/${callerUid}/${deviceId}`] = {
      role: 'owner',
      status: 'active',
      grantedAt: now,
    };
    multiPathUpdates[`pairing_rate_limits/${callerUid}`] = null; // Reset saat sukses

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
    console.error('Unhandled pairing error:', error);
    throw new HttpsError(
      'internal',
      'Terjadi kesalahan internal saat memproses pairing perangkat.'
    );
  }
}
