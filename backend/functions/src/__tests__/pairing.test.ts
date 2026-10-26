import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { handleClaimDevice } from '../pairing';
import { claimDevice } from '../index';
import { HttpsError } from 'firebase-functions/v2/https';

// Konfigurasi Emulator yang Konsisten
const EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
process.env.FIREBASE_DATABASE_EMULATOR_HOST = EMULATOR_HOST;
const PROJECT_ID = 'simetri-app';
const DATABASE_NS = 'simetri-app';

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: PROJECT_ID,
    databaseURL: `http://${EMULATOR_HOST}?ns=${DATABASE_NS}`,
  });
}

const db = admin.database();

describe('SIMETRI Backend Pairing, Device Ownership & Security Test Suite', () => {
  const testDeviceId = 'SIMETRI_DEV_SEC_001';
  const ownerUid = 'user_authorized_owner_123';

  before(async () => {
    // Bersihkan database emulator sebelum tes
    await db.ref().set(null);
  });

  after(async () => {
    // Bersihkan dan putus koneksi secara bersih
    await db.ref().set(null);
    db.goOffline();
    await db.app.delete();
  });

  async function getIdTokenForUid(uid: string): Promise<string> {
    const customToken = await admin.auth().createCustomToken(uid);
    const authEmulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
    const res = await fetch(
      `http://${authEmulatorHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: customToken, returnSecureToken: true }),
      }
    );
    const data = (await res.json()) as any;
    if (!data.idToken) {
      throw new Error(`Gagal menukar custom token ke idToken: ${JSON.stringify(data)}`);
    }
    return data.idToken;
  }

  function createSecret(
    code: string,
    deviceId: string,
    expiresInMs: number,
    options: {
      used?: boolean;
      usedBy?: string | null;
      status?: 'available' | 'pending_permission' | 'completed' | 'revoked';
    } = {}
  ) {
    const hash = crypto.createHash('sha256').update(code.trim().toUpperCase()).digest('hex');
    const now = Date.now();
    return db.ref(`pairing_secrets/${hash}`).set({
      deviceId,
      expiresAt: now + expiresInMs,
      used: options.used ?? false,
      usedBy: options.usedBy ?? null,
      usedAt: options.used ? now - 1000 : null,
      status: options.status ?? (options.used ? 'completed' : 'available'),
      createdAt: now,
    });
  }

  // =========================================================================
  // 1. KLAIM VALID & ALUR DASAR
  // =========================================================================
  it('1. Klaim dengan kode valid berhasil dan menetapkan permissions yang benar', async () => {
    const validCode = 'VALID123';
    await createSecret(validCode, testDeviceId, 60 * 1000);

    const mockRequest = {
      auth: { uid: ownerUid },
      data: { pairingCode: validCode },
    } as any;

    const response = await handleClaimDevice(mockRequest, db);

    assert.strictEqual(response.success, true);
    assert.strictEqual(response.deviceId, testDeviceId);

    // Verifikasi database: secret status completed
    const hash = crypto.createHash('sha256').update(validCode).digest('hex');
    const secretSnap = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretSnap.val().used, true);
    assert.strictEqual(secretSnap.val().usedBy, ownerUid);
    assert.strictEqual(secretSnap.val().status, 'completed');

    // Verifikasi permissions terdaftar
    const permSnap = await db.ref(`permissions/${ownerUid}/${testDeviceId}`).get();
    assert.strictEqual(permSnap.val().role, 'owner');

    // Verifikasi device meta ownerUid terdaftar
    const metaSnap = await db.ref(`devices/${testDeviceId}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, ownerUid);
  });

  it('2. Klaim dengan kode yang salah ditolak (not-found)', async () => {
    const invalidCode = 'WRONGCODE';
    const mockRequest = {
      auth: { uid: ownerUid },
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
    await createSecret(usedCode, 'DEV_USED_002', 60 * 1000, {
      used: true,
      usedBy: 'other_user',
      status: 'completed',
    });

    const mockRequest = {
      auth: { uid: ownerUid },
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
    await createSecret(expiredCode, 'DEV_EXP_003', -10 * 1000);

    const mockRequest = {
      auth: { uid: ownerUid },
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

  it('5. Klaim dengan kode yang dicabut/revoked ditolak (permission-denied)', async () => {
    const revokedCode = 'REVOKED88';
    await createSecret(revokedCode, 'DEV_REV_004', 60 * 1000, {
      status: 'revoked',
    });

    const mockRequest = {
      auth: { uid: ownerUid },
      data: { pairingCode: revokedCode },
    } as any;

    await assert.rejects(
      async () => {
        await handleClaimDevice(mockRequest, db);
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'permission-denied');
        return true;
      }
    );
  });

  // =========================================================================
  // 2. KONSISTENSI KLAIM, PARTIAL FAILURE RECOVERY & REVOKED ISOLATION
  // =========================================================================
  it('6. Pemulihan kegagalan parsial (injeksi crash setelah secret used sebelum permission tersimpan)', async () => {
    const crashCode = 'CRASH1234';
    const crashDevice = 'DEV_CRASH_PARTIAL';
    const crashUser = 'user_recovering_uid';
    await createSecret(crashCode, crashDevice, 60 * 1000);

    // Injeksi kegagalan/crash
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          {
            auth: { uid: crashUser },
            data: {
              pairingCode: crashCode,
              _testSimulateCrashAfterSecretClaim: true,
            },
          } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'internal');
        return true;
      }
    );

    // Verifikasi bahwa secret saat ini berada di status 'pending_permission'
    const hash = crypto.createHash('sha256').update(crashCode).digest('hex');
    const secretSnap = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretSnap.val().used, true);
    assert.strictEqual(secretSnap.val().status, 'pending_permission');

    // Verifikasi permissions belum lengkap tersimpan sebelum crash
    const permBefore = await db.ref(`permissions/${crashUser}/${crashDevice}`).get();
    assert.strictEqual(permBefore.exists(), false);

    // RETRY oleh UID yang sama: sistem harus mendeteksi dan memulihkan secara lengkap
    const retryRes = await handleClaimDevice(
      {
        auth: { uid: crashUser },
        data: { pairingCode: crashCode },
      } as any,
      db
    );

    assert.strictEqual(retryRes.success, true);
    assert.strictEqual(retryRes.deviceId, crashDevice);

    // Verifikasi pemulihan tuntas: status completed & permission tersimpan
    const secretAfter = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretAfter.val().status, 'completed');
    const permAfter = await db.ref(`permissions/${crashUser}/${crashDevice}`).get();
    assert.strictEqual(permAfter.val().role, 'owner');
  });

  it('7. Retry TIDAK BOLEH menghidupkan kembali izin yang sudah dicabut secara resmi', async () => {
    const revokedReclaimCode = 'REVOKE_RECLAIM';
    const devRevoke = 'DEV_REVOKED_OWNER';
    const userRevoked = 'user_revoked_former_owner';

    // Buat secret yang awalnya completed
    await createSecret(revokedReclaimCode, devRevoke, 60 * 1000, {
      used: true,
      usedBy: userRevoked,
      status: 'completed',
    });

    // Simulasi izin perangkat dicabut oleh admin (ownerUid direset menjadi null dan permission dihapus)
    await db.ref(`devices/${devRevoke}/meta/ownerUid`).set(null);
    await db.ref(`permissions/${userRevoked}/${devRevoke}`).remove();

    // Mantan pemilik mencoba klaim ulang menggunakan kode pairing lamanya
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          {
            auth: { uid: userRevoked },
            data: { pairingCode: revokedReclaimCode },
          } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        return true;
      }
    );

    // Pastikan permission TIDAK tercipta kembali
    const permSnap = await db.ref(`permissions/${userRevoked}/${devRevoke}`).get();
    assert.strictEqual(permSnap.exists(), false);
  });

  // =========================================================================
  // 3. KEPEMILIKAN PERANGKAT & LOCK PADA DEVICE LEVEL
  // =========================================================================
  it('8. Dua kode berbeda untuk perangkat yang sama tidak boleh memberikan kepemilikan kepada dua UID berbeda', async () => {
    const deviceShared = 'DEV_SHARED_TARGET';
    const codeA = 'CODE_FOR_DEV_A';
    const codeB = 'CODE_FOR_DEV_B';
    const userA = 'user_legitimate_first';
    const userB = 'user_second_intruder';

    // Didaftarkan dua kode untuk perangkat yang sama
    await createSecret(codeA, deviceShared, 60 * 1000);
    await createSecret(codeB, deviceShared, 60 * 1000);

    // User A berhasil mengklaim perangkat lebih dulu dengan kode A
    const resA = await handleClaimDevice(
      { auth: { uid: userA }, data: { pairingCode: codeA } } as any,
      db
    );
    assert.strictEqual(resA.success, true);

    // User B mencoba mengklaim perangkat yang sama dengan kode B yang berbeda
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: userB }, data: { pairingCode: codeB } } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        return true;
      }
    );

    // Verifikasi kepemilikan tetap milik User A, User B tidak memiliki izin
    const metaSnap = await db.ref(`devices/${deviceShared}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, userA);
    const permUserB = await db.ref(`permissions/${userB}/${deviceShared}`).get();
    assert.strictEqual(permUserB.exists(), false);
  });

  it('9. Dua kode berbeda untuk perangkat yang sama yang diklaim secara BERSAMAAN (concurrent) hanya memenangkan satu UID', async () => {
    const devRaceTwoCodes = 'DEV_RACE_TWO_CODES';
    const codeAlpha = 'CODE_ALPHA_RACE';
    const codeBeta = 'CODE_BETA_RACE';
    const racer1 = 'racer_user_alpha';
    const racer2 = 'racer_user_beta';

    await createSecret(codeAlpha, devRaceTwoCodes, 60 * 1000);
    await createSecret(codeBeta, devRaceTwoCodes, 60 * 1000);

    const [res1, res2] = await Promise.allSettled([
      handleClaimDevice({ auth: { uid: racer1 }, data: { pairingCode: codeAlpha } } as any, db),
      handleClaimDevice({ auth: { uid: racer2 }, data: { pairingCode: codeBeta } } as any, db),
    ]);

    const fulfilled = [res1, res2].filter((r) => r.status === 'fulfilled');
    const rejected = [res1, res2].filter((r) => r.status === 'rejected');

    // TEPAT SATU pemenang dan TEPAT SATU yang ditolak
    assert.strictEqual(fulfilled.length, 1);
    assert.strictEqual(rejected.length, 1);

    const winnerRes = (fulfilled[0] as PromiseFulfilledResult<any>).value;
    assert.strictEqual(winnerRes.success, true);

    // Device meta hanya menunjuk satu pemilik
    const finalMeta = await db.ref(`devices/${devRaceTwoCodes}/meta`).get();
    const winningUid = finalMeta.val().ownerUid;
    assert.ok(winningUid === racer1 || winningUid === racer2);

    const loserUid = winningUid === racer1 ? racer2 : racer1;
    const loserPerm = await db.ref(`permissions/${loserUid}/${devRaceTwoCodes}`).get();
    assert.strictEqual(loserPerm.exists(), false);
  });

  // =========================================================================
  // 4. RATE LIMITING ATOMIC TRANSACTION
  // =========================================================================
  it('10. Rate limiting transaksi atomik memblokir setelah 5x kesalahan berturut-turut tanpa kehilangan pembaruan', async () => {
    const bruteUid = 'attacker_bruteforce_atomic';
    const wrongPrefix = 'FAILCODE';

    // 5 percobaan salah secara bersamaan (concurrent)
    await Promise.all(
      [1, 2, 3, 4, 5].map((i) =>
        handleClaimDevice(
          { auth: { uid: bruteUid }, data: { pairingCode: `${wrongPrefix}_${i}` } } as any,
          db
        ).catch((err) => {
          assert.strictEqual(err.code, 'not-found');
        })
      )
    );

    // Verifikasi counter tepat 5 di database
    const rlSnap = await db.ref(`pairing_rate_limits/${bruteUid}`).get();
    assert.strictEqual(rlSnap.val().attempts, 5);

    // Percobaan ke-6 HARUS ditolak oleh rate limiter (resource-exhausted)
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: bruteUid }, data: { pairingCode: 'ANY_CODE_6' } } as any,
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

  // =========================================================================
  // 5. SECURITY RULES: PENGUJIAN HAK AKSES UID BERIZIN & UID TANPA IZIN
  // =========================================================================
  it('11. Security Rules: Menolak akses UID tanpa izin dan mengizinkan UID berizin (tanpa assertion swallowing)', async () => {
    const secDeviceId = 'DEV_SECURITY_TEST_01';
    const validOwner = 'authorized_owner_uid_777';
    const unauthorizedUser = 'unauthorized_stranger_888';

    // Siapkan data perangkat di RTDB melalui Admin SDK
    await db.ref(`devices/${secDeviceId}/live`).set({
      voltage: 220.5,
      current: 1.45,
      power: 320.0,
      energy_kwh: 12.4,
      relay_state: true,
      timestamp: Date.now(),
    });

    // Berikan izin HANYA kepada validOwner
    await db.ref(`permissions/${validOwner}/${secDeviceId}`).set({
      role: 'owner',
      grantedAt: Date.now(),
    });

    // 1. Dapatkan ID Token Asli untuk masing-masing pengguna via Auth Emulator
    const unauthIdToken = await getIdTokenForUid(unauthorizedUser);
    const ownerIdToken = await getIdTokenForUid(validOwner);

    // 2. Uji Akses oleh UID TANPA IZIN (unauthorizedUser)
    const unauthUrl = `http://${EMULATOR_HOST}/devices/${secDeviceId}/live.json?ns=${DATABASE_NS}&auth=${unauthIdToken}`;

    const unauthResponse = await fetch(unauthUrl);
    const unauthBody = await unauthResponse.json() as any;

    // Respon diizinkan adalah kegagalan kritis bagi tes ini!
    if (unauthResponse.status === 200) {
      assert.fail(`Security violation: Akses data live diizinkan untuk UID tanpa izin! Status: ${unauthResponse.status}`);
    }

    assert.strictEqual(
      unauthResponse.status,
      401,
      `Akses tanpa izin harus mengembalikan HTTP 401 Unauthorized`
    );
    assert.ok(
      unauthBody?.error?.includes('Permission denied'),
      `Pesan error harus mengandung 'Permission denied'`
    );

    // 3. Uji Akses oleh UID BERIZIN (validOwner)
    const ownerUrl = `http://${EMULATOR_HOST}/devices/${secDeviceId}/live.json?ns=${DATABASE_NS}&auth=${ownerIdToken}`;

    const ownerResponse = await fetch(ownerUrl);
    assert.strictEqual(
      ownerResponse.status,
      200,
      `Akses oleh UID berizin harus berhasil dengan status HTTP 200`
    );
    const ownerData = await ownerResponse.json() as any;
    assert.strictEqual(ownerData.voltage, 220.5);
    assert.strictEqual(ownerData.energy_kwh, 12.4);

    // 4. Uji Penulisan Kontrol Relay oleh UID TANPA IZIN
    const unauthControlUrl = `http://${EMULATOR_HOST}/devices/${secDeviceId}/control/power.json?ns=${DATABASE_NS}&auth=${unauthIdToken}`;
    const unauthWriteRes = await fetch(unauthControlUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(false),
    });
    assert.strictEqual(
      unauthWriteRes.status,
      401,
      'Penulisan switch relay oleh UID tanpa izin harus ditolak (HTTP 401)'
    );

    // 5. Uji Penulisan Kontrol Relay oleh UID BERIZIN
    const ownerControlUrl = `http://${EMULATOR_HOST}/devices/${secDeviceId}/control/power.json?ns=${DATABASE_NS}&auth=${ownerIdToken}`;
    const ownerWriteRes = await fetch(ownerControlUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(false),
    });
    assert.strictEqual(
      ownerWriteRes.status,
      200,
      'Penulisan switch relay oleh UID berizin harus berhasil (HTTP 200)'
    );
  });

  // =========================================================================
  // 6. CALLABLE CLIENT DENGAN SESI AUTENTIKASI
  // =========================================================================
  it('12. Callable Function claimDevice dieksekusi dengan sesi autentikasi pemanggil', async () => {
    const callCode = 'CALL1234';
    const callDevice = 'DEV_CALLABLE_TEST';
    const callUid = 'user_callable_session_uid';

    await createSecret(callCode, callDevice, 60 * 1000);

    // Panggil callable function wrapper dengan payload dan sesi auth
    const callableResult = await claimDevice.run({
      auth: { uid: callUid },
      data: { pairingCode: callCode },
    } as any);

    assert.strictEqual(callableResult.success, true);
    assert.strictEqual(callableResult.deviceId, callDevice);

    // Verifikasi izin berhasil ditetapkan oleh callable function
    const perm = await db.ref(`permissions/${callUid}/${callDevice}`).get();
    assert.strictEqual(perm.val().role, 'owner');
  });
});
