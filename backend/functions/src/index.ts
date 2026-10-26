import * as admin from 'firebase-admin';
import { onCall } from 'firebase-functions/v2/https';
import { ClaimDeviceRequest, handleClaimDevice } from './pairing';

// Inisialisasi Firebase Admin jika belum diinisialisasi
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.database();

/**
 * Cloud Function Callable: claimDevice
 * Digunakan oleh aplikasi Flutter (dengan UID Anonim) untuk mengklaim perangkat
 * menggunakan kode pairing sementara yang valid.
 */
export const claimDevice = onCall<ClaimDeviceRequest>(
  {
    cors: true,
    region: 'us-central1', // default region
  },
  async (request) => {
    return handleClaimDevice(request, db);
  }
);
