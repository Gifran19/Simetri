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
  createdAt: number;
}

const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 menit

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
    await recordFailedAttempt(rateLimitRef, rateLimitSnap.val(), now);
    throw new HttpsError(
      'not-found',
      'Kode pairing tidak ditemukan atau salah. Periksa kembali kode Anda.'
    );
  }

  const existingSecret = secretSnap.val() as PairingSecretData;

  // 4b. Idempotensi: Jika pengguna yang sama mencoba ulang setelah gangguan koneksi,
  // kembalikan keberhasilan tanpa merusak data permissions yang sudah ada.
  if (existingSecret.used && existingSecret.usedBy === callerUid) {
    return {
      success: true,
      deviceId: existingSecret.deviceId,
      message: 'Perangkat sudah berhasil terpasang pada akun Anda.',
    };
  }

  // 5. Transaksi Atomik pada pairing_secrets untuk Menghindari Race Condition
  let failureReason: 'already_used' | 'expired' | null = null;

  try {
    const txResult = await secretRef.transaction((currentData: PairingSecretData | null) => {
      // Pada pass awal lokal Firebase SDK, currentData bisa berupa null sementara data diambil dari server.
      if (currentData === null) {
        return currentData;
      }

      if (currentData.used) {
        failureReason = 'already_used';
        return; // membatalkan transaksi
      }

      if (now > currentData.expiresAt) {
        failureReason = 'expired';
        return; // membatalkan transaksi
      }

      // Valid: tandai terpakai secara atomik
      return {
        ...currentData,
        used: true,
        usedBy: callerUid,
        usedAt: now,
      };
    });

    // Periksa apakah transaksi berhasil di-commit
    if (!txResult.committed || !txResult.snapshot.exists()) {
      await recordFailedAttempt(rateLimitRef, rateLimitSnap.val(), now);

      if (failureReason === 'already_used') {
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
          'Klaim gagal karena konflik konkurensi. Silakan coba lagi.'
        );
      }
    }

    const updatedSecret = txResult.snapshot.val() as PairingSecretData;
    const deviceId = updatedSecret?.deviceId;
    if (!deviceId) {
      throw new HttpsError(
        'not-found',
        'Data perangkat tidak valid dalam sistem.'
      );
    }

    // 5. Backend Menetapkan Izin UID terhadap Perangkat Secara Atomik
    const multiPathUpdates: Record<string, unknown> = {};
    multiPathUpdates[`permissions/${callerUid}/${deviceId}`] = {
      role: 'owner',
      grantedAt: now,
    };
    multiPathUpdates[`devices/${deviceId}/meta/ownerUid`] = callerUid;
    multiPathUpdates[`devices/${deviceId}/meta/claimedAt`] = now;
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
    // Tangani kemungkinan error internal
    console.error('Unhandled pairing error:', error);
    throw new HttpsError(
      'internal',
      'Terjadi kesalahan internal saat memproses pairing.'
    );
  }
}

async function recordFailedAttempt(
  ref: admin.database.Reference,
  currentRl: { attempts?: number; lastAttempt?: number } | null,
  now: number
): Promise<void> {
  const isExpiredWindow =
    currentRl &&
    currentRl.lastAttempt &&
    now - currentRl.lastAttempt > RATE_LIMIT_WINDOW_MS;

  const newAttempts = isExpiredWindow || !currentRl ? 1 : (currentRl.attempts || 0) + 1;

  await ref.set({
    attempts: newAttempts,
    lastAttempt: now,
  });
}
