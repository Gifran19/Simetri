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
  claimedAt?: number | null;
  registeredAt?: number;
  activePairingHash?: string;
  deviceUid?: string;
}

const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 menit

/**
 * KETERBATASAN KEAMANAN RATE LIMITING BERBASIS UID ANONIM:
 * 
 * Pembatasan laju (rate limiting) di bawah ini dihitung per UID Anonim Firebase Authentication.
 * Keterbatasan Inheren:
 * 1. Jika penyerang membersihkan cache / local storage aplikasi, Firebase Auth akan menghasilkan
 *    UID anonim baru. Hal ini mereset counter rate limit pada UID tersebut.
 * 2. Mitigasi berlapis (Defense-in-Depth) yang direkomendasikan untuk tahap produksi:
 *    a. Menerapkan Firebase App Check (Play Integrity pada Android, DeviceCheck pada iOS)
 *       untuk memastikan request hanya berasal dari aplikasi resmi yang belum dimodifikasi.
 *    b. Rate limiting berbasis IP di tingkat Gateway / Cloud Armor jika callable diakses lewat HTTPS publik.
 *    c. Penggunaan kode pairing kriptografis dengan entropi tinggi (misal SHA-256 dari 8-12 karakter acak),
 *       dan masa berlaku singkat (misal 15-60 menit) sehingga serangan brute force tidak memungkinkan
 *       dalam ruang waktu validitas kode.
 */
export async function checkAndRecordRateLimit(
  rateLimitRef: admin.database.Reference,
  now: number
): Promise<void> {
  let isExceeded = false;
  let remainingMinutes = 0;

  // Gunakan transaksi agar tidak terjadi lost update saat permintaan bersamaan (race condition)
  await rateLimitRef.transaction((current) => {
    if (!current || now - (current.lastAttempt || 0) > RATE_LIMIT_WINDOW_MS) {
      // Jendela baru atau pertama kali
      return { attempts: 1, lastAttempt: now };
    }

    if (current.attempts >= MAX_FAILED_ATTEMPTS) {
      isExceeded = true;
      remainingMinutes = Math.ceil(
        (RATE_LIMIT_WINDOW_MS - (now - current.lastAttempt)) / 60000
      );
      return; // batalkan transaksi tanpa menambah hitungan
    }

    return {
      attempts: (current.attempts || 0) + 1,
      lastAttempt: now,
    };
  });

  if (isExceeded) {
    throw new HttpsError(
      'resource-exhausted',
      `Terlalu banyak percobaan gagal. Silakan tunggu ${remainingMinutes} menit sebelum mencoba lagi.`
    );
  }
}

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
    throw new HttpsError('invalid-argument', 'Kode pairing wajib diisi.');
  }

  const normalizedCode = rawCode.trim().toUpperCase();
  if (normalizedCode.length < 6 || normalizedCode.length > 32) {
    throw new HttpsError('invalid-argument', 'Format kode pairing tidak valid.');
  }

  const now = Date.now();
  const rateLimitRef = db.ref(`pairing_rate_limits/${callerUid}`);

  // 2. Hash Kode Pairing Menggunakan SHA-256
  const hash = crypto.createHash('sha256').update(normalizedCode).digest('hex');
  const secretRef = db.ref(`pairing_secrets/${hash}`);

  // 3. Verifikasi Keberadaan Secret di Database
  const secretSnap = await secretRef.get();
  if (!secretSnap.exists()) {
    await checkAndRecordRateLimit(rateLimitRef, now);
    throw new HttpsError(
      'not-found',
      'Kode pairing tidak ditemukan atau salah. Periksa kembali kode Anda.'
    );
  }

  const secretData = secretSnap.val() as PairingSecretData;
  const deviceId = secretData.deviceId;

  // 4. Periksa apakah kode telah dicabut (revoked) oleh admin / diterbitkan kode baru
  if (secretData.status === 'revoked') {
    await checkAndRecordRateLimit(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Kode pairing ini telah dicabut atau digantikan oleh kode baru.'
    );
  }

  // 5. Penanganan Idempotensi & Pemulihan (Recovery) Klaim yang Belum Lengkap:
  // Jika secret sudah ditandai used oleh callerUid yang sama
  if (secretData.used && secretData.usedBy === callerUid) {
    // Periksa apakah izin untuk UID ini sengaja dicabut
    const permSnap = await db.ref(`permissions/${callerUid}/${deviceId}`).get();
    if (permSnap.exists() && permSnap.val()?.status === 'revoked') {
      throw new HttpsError(
        'failed-precondition',
        'Izin akses untuk perangkat ini telah dicabut oleh administrator.'
      );
    }

    // Jika terjadi kegagalan di tengah jalan (misal permissions belum tersimpan atau ownerUid belum terpasang),
    // kita pulihkan data tersebut secara utuh sekarang.
    const metaSnap = await db.ref(`devices/${deviceId}/meta`).get();
    const currentMeta = (metaSnap.val() || {}) as DeviceMetaData;

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

  // Jika sudah used oleh orang lain
  if (secretData.used && secretData.usedBy !== callerUid) {
    await checkAndRecordRateLimit(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Kode pairing ini sudah pernah digunakan sebelumnya.'
    );
  }

  // Jika kode sudah kedaluwarsa
  if (now > secretData.expiresAt) {
    await checkAndRecordRateLimit(rateLimitRef, now);
    throw new HttpsError(
      'deadline-exceeded',
      'Kode pairing telah kedaluwarsa. Mintalah kode baru.'
    );
  }

  // 6. KUNCI KEPEMILIKAN TINGKAT PERANGKAT:
  // Dua kode berbeda untuk perangkat yang sama tidak boleh memberikan kepemilikan kepada dua UID berbeda.
  // Gunakan transaksi pada node device lock: devices/{deviceId}/meta/ownerUid
  const metaRef = db.ref(`devices/${deviceId}/meta`);
  let deviceOwnershipConflict = false;

  const deviceLockResult = await metaRef.transaction((currentMeta: DeviceMetaData | null) => {
    if (currentMeta === null) {
      // Metadata perangkat belum ada, buat baru
      return {
        deviceId,
        ownerUid: callerUid,
        claimedAt: now,
      };
    }

    // Jika perangkat sudah memiliki pemilik aktif dan bukan callerUid yang sama
    if (currentMeta.ownerUid && currentMeta.ownerUid !== callerUid) {
      deviceOwnershipConflict = true;
      return; // batalkan transaksi
    }

    return {
      ...currentMeta,
      ownerUid: callerUid,
      claimedAt: now,
    };
  });

  if (deviceOwnershipConflict || !deviceLockResult.committed) {
    await checkAndRecordRateLimit(rateLimitRef, now);
    throw new HttpsError(
      'failed-precondition',
      'Perangkat ini sudah terdaftar dan dimiliki oleh pengguna lain.'
    );
  }

  // 7. Transaksi Atomik pada pairing_secrets untuk mengklaim kode
  let secretFailureReason: 'already_used' | 'expired' | 'revoked' | null = null;

  try {
    const txSecretResult = await secretRef.transaction((currentSecret: PairingSecretData | null) => {
      if (currentSecret === null) {
        return currentSecret;
      }

      if (currentSecret.status === 'revoked') {
        secretFailureReason = 'revoked';
        return; // batalkan
      }

      if (currentSecret.used) {
        secretFailureReason = 'already_used';
        return; // batalkan
      }

      if (now > currentSecret.expiresAt) {
        secretFailureReason = 'expired';
        return; // batalkan
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
      // Rollback kepemilikan perangkat jika klaim secret gagal
      await metaRef.child('ownerUid').transaction((currentOwner) => {
        if (currentOwner === callerUid) {
          return null; // kembalikan ke null
        }
        return currentOwner;
      });

      await checkAndRecordRateLimit(rateLimitRef, now);

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

    // 8. Menetapkan Izin Pengguna di database secara atomik
    const multiPathUpdates: Record<string, unknown> = {};
    multiPathUpdates[`permissions/${callerUid}/${deviceId}`] = {
      role: 'owner',
      status: 'active',
      grantedAt: now,
    };
    multiPathUpdates[`pairing_rate_limits/${callerUid}`] = null; // Reset counter rate limit jika berhasil

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
