import * as admin from 'firebase-admin';
import { onCall } from 'firebase-functions/v2/https';
import { ClaimDeviceRequest, handleClaimDevice } from './pairing';

// Inisialisasi Firebase Admin dengan namespace konsisten
const DATABASE_NAMESPACE = process.env.FIREBASE_DATABASE_NAMESPACE || 'simetri-app-default-rtdb';
const EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';

if (admin.apps.length === 0) {
  if (process.env.FUNCTIONS_EMULATOR || process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
    admin.initializeApp({
      projectId: 'simetri-app',
      databaseURL: `http://${EMULATOR_HOST}?ns=${DATABASE_NAMESPACE}`,
    });
  } else {
    admin.initializeApp();
  }
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
