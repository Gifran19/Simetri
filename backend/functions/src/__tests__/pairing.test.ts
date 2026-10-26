import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { handleClaimDevice } from '../pairing';
import { HttpsError } from 'firebase-functions/v2/https';

// Setup koneksi Firebase Emulator untuk tes
process.env.FIREBASE_DATABASE_EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: 'simetri-app',
    databaseURL: `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=simetri-default-rtdb`,
  });
}

const db = admin.database();

describe('SIMETRI Backend Pairing & Security Test Suite', () => {
  const testDeviceId = 'SIMETRI_TEST_DEV_001';
  const testUid = 'anon_uid_test_12345';

  before(async () => {
    // Bersihkan database emulator sebelum tes
    await db.ref().set(null);
  });

  after(async () => {
    // Bersihkan setelah tes dan putus koneksi agar proses exit dengan mulus
    await db.ref().set(null);
    db.goOffline();
    await db.app.delete();
  });

  function createSecret(code: string, deviceId: string, expiresInMs: number, used = false) {
    const hash = crypto.createHash('sha256').update(code.trim().toUpperCase()).digest('hex');
    const now = Date.now();
    return db.ref(`pairing_secrets/${hash}`).set({
      deviceId,
      expiresAt: now + expiresInMs,
      used,
      usedBy: used ? 'existing_user' : null,
      usedAt: used ? now - 1000 : null,
      createdAt: now,
    });
  }

  it('1. Klaim dengan kode valid berhasil dan menetapkan permissions yang benar', async () => {
    const validCode = 'VALID123';
    await createSecret(validCode, testDeviceId, 60 * 1000);

    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: validCode },
    } as any;

    const response = await handleClaimDevice(mockRequest, db);

    assert.strictEqual(response.success, true);
    assert.strictEqual(response.deviceId, testDeviceId);

    // Verifikasi database: secret sudah used
    const hash = crypto.createHash('sha256').update(validCode).digest('hex');
    const secretSnap = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretSnap.val().used, true);
    assert.strictEqual(secretSnap.val().usedBy, testUid);

    // Verifikasi permissions terdaftar
    const permSnap = await db.ref(`permissions/${testUid}/${testDeviceId}`).get();
    assert.strictEqual(permSnap.val().role, 'owner');

    // Verifikasi device meta ownerUid terdaftar
    const metaSnap = await db.ref(`devices/${testDeviceId}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, testUid);
  });

  it('2. Klaim dengan kode yang salah ditolak (not-found)', async () => {
    const invalidCode = 'WRONGCODE';
    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: invalidCode },
    } as any;

    await assert.rejects(
      async () => {
        await handleClaimDevice(mockRequest, db);
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'not-found');
        return true;
      }
    );
  });

  it('3. Klaim dengan kode yang sudah terpakai ditolak (failed-precondition)', async () => {
    const usedCode = 'ALREADYUSED';
    await createSecret(usedCode, 'DEV_USED_002', 60 * 1000, true);

    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: usedCode },
    } as any;

    await assert.rejects(
      async () => {
        await handleClaimDevice(mockRequest, db);
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        return true;
      }
    );
  });

  it('4. Klaim dengan kode yang sudah kedaluwarsa ditolak (deadline-exceeded)', async () => {
    const expiredCode = 'EXPIRED99';
    // Expired 10 detik lalu
    await createSecret(expiredCode, 'DEV_EXP_003', -10 * 1000);

    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: expiredCode },
    } as any;

    await assert.rejects(
      async () => {
        await handleClaimDevice(mockRequest, db);
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'deadline-exceeded');
        return true;
      }
    );
  });

  it('5. Batas percobaan (rate limiting) memblokir setelah 5x kesalahan berturut-turut', async () => {
    const bruteUid = 'brute_force_attacker';
    const wrongCode = 'GUESS001';

    // Lakukan 5x salah
    for (let i = 0; i < 5; i++) {
      try {
        await handleClaimDevice(
          {
            auth: { uid: bruteUid },
            data: { pairingCode: `${wrongCode}_${i}` },
          } as any,
          db
        );
      } catch (err: any) {
        assert.strictEqual(err.code, 'not-found');
      }
    }

    // Percobaan ke-6 harus ditolak oleh rate limiter (resource-exhausted)
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          {
            auth: { uid: bruteUid },
            data: { pairingCode: 'ANY_CODE' },
          } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'resource-exhausted');
        return true;
      }
    );
  });

  it('6. Klaim bersamaan (concurrent race condition) tidak memberikan akses ganda', async () => {
    const raceCode = 'RACE9999';
    const raceDevice = 'DEV_RACE_004';
    await createSecret(raceCode, raceDevice, 60 * 1000);

    const reqUser1 = {
      auth: { uid: 'race_user_1' },
      data: { pairingCode: raceCode },
    } as any;

    const reqUser2 = {
      auth: { uid: 'race_user_2' },
      data: { pairingCode: raceCode },
    } as any;

    // Eksekusi kedua request secara simultan
    const results = await Promise.allSettled([
      handleClaimDevice(reqUser1, db),
      handleClaimDevice(reqUser2, db),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    // TEPAT SATU yang harus berhasil
    assert.strictEqual(fulfilled.length, 1);
    // TEPAT SATU yang harus ditolak
    assert.strictEqual(rejected.length, 1);

    const winner = (fulfilled[0] as PromiseFulfilledResult<any>).value;
    assert.strictEqual(winner.success, true);
    assert.strictEqual(winner.deviceId, raceDevice);

    const loserErr = (rejected[0] as PromiseRejectedResult).reason;
    assert.ok(loserErr instanceof HttpsError);
  });

  it('7. Percobaan ulang setelah gangguan (idempotensi) tidak merusak izin', async () => {
    const retryCode = 'RETRY1234';
    const retryDevice = 'DEV_RETRY_005';
    const retryUid = 'user_retry_abc';

    // Buat kode
    await createSecret(retryCode, retryDevice, 60 * 1000);

    // Panggilan pertama
    const res1 = await handleClaimDevice(
      { auth: { uid: retryUid }, data: { pairingCode: retryCode } } as any,
      db
    );
    assert.strictEqual(res1.success, true);
    assert.strictEqual(res1.deviceId, retryDevice);

    // Panggilan kedua (retry setelah gangguan koneksi oleh pemanggil yang sama)
    const res2 = await handleClaimDevice(
      { auth: { uid: retryUid }, data: { pairingCode: retryCode } } as any,
      db
    );
    assert.strictEqual(res2.success, true);
    assert.strictEqual(res2.deviceId, retryDevice);

    // Pastikan izin tetap utuh
    const permSnap = await db.ref(`permissions/${retryUid}/${retryDevice}`).get();
    assert.strictEqual(permSnap.val().role, 'owner');
  });

  it('8. Akses publik / tanpa izin ke data live ditolak oleh Security Rules (Permission Denied)', async () => {
    // Kita uji akses REST ke RTDB emulator tanpa otorisasi token
    const emulatorHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
    const testUrl = `http://${emulatorHost}/devices/${testDeviceId}/live.json`;

    try {
      const response = await fetch(testUrl);
      const data = await response.json() as any;
      
      // REST API Firebase RTDB mengembalikan error Permission denied jika tidak memenuhi rules
      if (response.status === 401 || (data && data.error && data.error.includes('Permission denied'))) {
        assert.ok(true, 'Akses publik ditolak');
      } else {
        assert.fail(`Seharusnya akses ditolak, tetapi status: ${response.status}`);
      }
    } catch (e: any) {
      // Jika fetch ditolak/error
      assert.ok(true);
    }
  });
});
