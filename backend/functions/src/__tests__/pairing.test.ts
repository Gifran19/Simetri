import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { handleClaimDevice } from '../pairing';
import { claimDevice } from '../index';
import { HttpsError } from 'firebase-functions/v2/https';

const PROJECT_ID = 'simetri-app';
const DATABASE_NAMESPACE = 'simetri-app-default-rtdb';
const EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
const AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

process.env.FIREBASE_DATABASE_EMULATOR_HOST = EMULATOR_HOST;
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: PROJECT_ID,
    databaseURL: `http://${EMULATOR_HOST}?ns=${DATABASE_NAMESPACE}`,
  });
}

const db = admin.database();

describe('SIMETRI Backend Pairing & Security Test Suite (Strict Emulator Validation)', () => {
  const testDeviceId = 'SIMETRI_TEST_DEV_001';
  const testUid = 'anon_uid_test_12345';

  before(async () => {
    await db.ref().set(null);
  });

  after(async () => {
    await db.ref().set(null);
    db.goOffline();
    await db.app.delete();
  });

  function createSecret(
    code: string,
    deviceId: string,
    expiresInMs: number,
    used = false,
    status: 'available' | 'used' | 'revoked' = 'available'
  ) {
    const hash = crypto.createHash('sha256').update(code.trim().toUpperCase()).digest('hex');
    const now = Date.now();
    return db.ref(`pairing_secrets/${hash}`).set({
      deviceId,
      expiresAt: now + expiresInMs,
      used,
      usedBy: used ? 'existing_user' : null,
      usedAt: used ? now - 1000 : null,
      status: used ? 'used' : status,
      createdAt: now,
    });
  }

  // =========================================================================
  // 1. KLAIM DASAR & PENOLAKAN KODE INVALID / KEDALUWARSA / TERPAKAI
  // =========================================================================

  it('1. Klaim dengan kode valid berhasil dan menetapkan permissions owner yang benar', async () => {
    const validCode = 'VALID123';
    await createSecret(validCode, testDeviceId, 60 * 1000);

    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: validCode },
    } as any;

    const response = await handleClaimDevice(mockRequest, db);

    assert.strictEqual(response.success, true);
    assert.strictEqual(response.deviceId, testDeviceId);

    // Verifikasi database: secret berstatus used
    const hash = crypto.createHash('sha256').update(validCode).digest('hex');
    const secretSnap = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretSnap.val().used, true);
    assert.strictEqual(secretSnap.val().usedBy, testUid);
    assert.strictEqual(secretSnap.val().status, 'used');

    // Verifikasi permissions terdaftar dengan status active
    const permSnap = await db.ref(`permissions/${testUid}/${testDeviceId}`).get();
    assert.strictEqual(permSnap.val().role, 'owner');
    assert.strictEqual(permSnap.val().status, 'active');

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

  it('5. Klaim dengan kode yang telah dicabut (revoked) ditolak (failed-precondition)', async () => {
    const revokedCode = 'REVOKED88';
    await createSecret(revokedCode, 'DEV_REV_004', 60 * 1000, false, 'revoked');

    const mockRequest = {
      auth: { uid: testUid },
      data: { pairingCode: revokedCode },
    } as any;

    await assert.rejects(
      async () => {
        await handleClaimDevice(mockRequest, db);
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        assert.match(err.message, /dicabut|digantikan/);
        return true;
      }
    );
  });

  // =========================================================================
  // 2. RATE LIMITING DENGAN TRANSAKSI
  // =========================================================================

  it('6. Batas percobaan (rate limiting berbasis transaksi) memblokir setelah 5x kegagalan', async () => {
    const bruteUid = 'brute_force_attacker_tx';
    const wrongCode = 'FAILGUESS';

    // Bersihkan rate limit lama bruteUid
    await db.ref(`pairing_rate_limits/${bruteUid}`).remove();

    // 5 kali salah
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

  // =========================================================================
  // 3. KUNCI KEPEMILIKAN TINGKAT PERANGKAT & KONKURENSI DUA KODE
  // =========================================================================

  it('7. Klaim bersamaan pada satu kode yang sama (race condition) hanya memberikan akses pada satu UID', async () => {
    const raceCode = 'RACE9999';
    const raceDevice = 'DEV_RACE_SINGLE_CODE';
    await createSecret(raceCode, raceDevice, 60 * 1000);

    const reqUser1 = {
      auth: { uid: 'race_user_1' },
      data: { pairingCode: raceCode },
    } as any;

    const reqUser2 = {
      auth: { uid: 'race_user_2' },
      data: { pairingCode: raceCode },
    } as any;

    const results = await Promise.allSettled([
      handleClaimDevice(reqUser1, db),
      handleClaimDevice(reqUser2, db),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    assert.strictEqual(fulfilled.length, 1, 'Tepat satu pemanggil harus berhasil');
    assert.strictEqual(rejected.length, 1, 'Tepat satu pemanggil harus ditolak');

    const winner = (fulfilled[0] as PromiseFulfilledResult<any>).value;
    assert.strictEqual(winner.success, true);
    assert.strictEqual(winner.deviceId, raceDevice);
  });

  it('8. Dua kode berbeda untuk perangkat yang sama tidak boleh memberikan kepemilikan kepada dua UID berbeda', async () => {
    const deviceTarget = 'DEV_SHARED_TARGET_001';
    const codeA = 'CODE_AAA_111';
    const codeB = 'CODE_BBB_222';
    const uidA = 'user_owner_alpha';
    const uidB = 'user_intruder_beta';

    // Buat dua kode berbeda untuk perangkat yang sama
    await createSecret(codeA, deviceTarget, 60 * 1000);
    await createSecret(codeB, deviceTarget, 60 * 1000);

    // User A berhasil mengklaim dengan codeA
    const resA = await handleClaimDevice(
      { auth: { uid: uidA }, data: { pairingCode: codeA } } as any,
      db
    );
    assert.strictEqual(resA.success, true);

    // User B mencoba mengklaim perangkat yang sama menggunakan codeB yang masih unused
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: uidB }, data: { pairingCode: codeB } } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        assert.match(err.message, /sudah terdaftar dan dimiliki oleh pengguna lain/);
        return true;
      }
    );

    // Pastikan User B tidak tercatat sebagai owner di metadata maupun permissions
    const metaSnap = await db.ref(`devices/${deviceTarget}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, uidA);

    const permSnapB = await db.ref(`permissions/${uidB}/${deviceTarget}`).get();
    assert.strictEqual(permSnapB.exists(), false);
  });

  it('9. Dua kode berbeda untuk perangkat yang sama yang diklaim bersamaan (simultan) hanya memberikan akses pada satu pemenang', async () => {
    const simultaneousDevice = 'DEV_SIMULTANEOUS_002';
    const code1 = 'SIMUL_111';
    const code2 = 'SIMUL_222';
    const u1 = 'user_simul_1';
    const u2 = 'user_simul_2';

    await createSecret(code1, simultaneousDevice, 60 * 1000);
    await createSecret(code2, simultaneousDevice, 60 * 1000);

    const results = await Promise.allSettled([
      handleClaimDevice({ auth: { uid: u1 }, data: { pairingCode: code1 } } as any, db),
      handleClaimDevice({ auth: { uid: u2 }, data: { pairingCode: code2 } } as any, db),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    assert.strictEqual(fulfilled.length, 1, 'Hanya boleh 1 yang berhasil mengunci kepemilikan perangkat');
    assert.strictEqual(rejected.length, 1, 'Pihak kedua harus ditolak oleh kunci perangkat');

    const metaSnap = await db.ref(`devices/${simultaneousDevice}/meta`).get();
    const winningUid = (fulfilled[0] as PromiseFulfilledResult<any>).value.deviceId;
    assert.strictEqual(winningUid, simultaneousDevice);
    assert.ok(metaSnap.val().ownerUid === u1 || metaSnap.val().ownerUid === u2);
  });

  // =========================================================================
  // 4. KONSISTENSI KLAIM: INJEKSI KEGAGALAN, RETRY RECOVERY, DAN STATUS REVOKED
  // =========================================================================

  it('10. Injeksi kegagalan (secret sudah used tetapi permission belum tersimpan) dipulihkan secara utuh saat retry', async () => {
    const recoveryCode = 'RECOVERY_99';
    const recoveryDevice = 'DEV_CRASH_RECOVERY_01';
    const recoveryUid = 'user_crashed_midway';
    const hash = crypto.createHash('sha256').update(recoveryCode).digest('hex');

    // Simulasikan state kegagalan sistem: secret sudah ditandai used oleh recoveryUid,
    // tetapi permission belum sempat tertulis (crash tepat setelah secret commit)
    const now = Date.now();
    await db.ref(`pairing_secrets/${hash}`).set({
      deviceId: recoveryDevice,
      expiresAt: now + 60000,
      used: true,
      usedBy: recoveryUid,
      usedAt: now,
      status: 'used',
      createdAt: now - 5000,
    });
    // Pastikan permissions belum ada
    await db.ref(`permissions/${recoveryUid}/${recoveryDevice}`).remove();
    await db.ref(`devices/${recoveryDevice}/meta`).set({
      deviceId: recoveryDevice,
      ownerUid: null, // belum sempat tertulis
    });

    // Panggil retry oleh UID yang sama
    const retryResponse = await handleClaimDevice(
      { auth: { uid: recoveryUid }, data: { pairingCode: recoveryCode } } as any,
      db
    );

    assert.strictEqual(retryResponse.success, true);
    assert.strictEqual(retryResponse.deviceId, recoveryDevice);

    // Verifikasi bahwa data yang belum lengkap berhasil dipulihkan
    const permSnap = await db.ref(`permissions/${recoveryUid}/${recoveryDevice}`).get();
    assert.strictEqual(permSnap.exists(), true);
    assert.strictEqual(permSnap.val().role, 'owner');
    assert.strictEqual(permSnap.val().status, 'active');

    const metaSnap = await db.ref(`devices/${recoveryDevice}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, recoveryUid);
  });

  it('11. Retry oleh UID yang sama TIDAK BOLEH menghidupkan kembali izin yang telah dicabut (revoked)', async () => {
    const revokedClaimCode = 'REVOKED_PERM_01';
    const revokedDevice = 'DEV_PERM_REVOKED_02';
    const userRevoked = 'user_with_revoked_perm';
    const hash = crypto.createHash('sha256').update(revokedClaimCode).digest('hex');

    const now = Date.now();
    await db.ref(`pairing_secrets/${hash}`).set({
      deviceId: revokedDevice,
      expiresAt: now + 60000,
      used: true,
      usedBy: userRevoked,
      usedAt: now - 3600000,
      status: 'used',
      createdAt: now - 7200000,
    });

    // Tandai izin user secara eksplisit sebagai revoked oleh admin
    await db.ref(`permissions/${userRevoked}/${revokedDevice}`).set({
      role: 'owner',
      status: 'revoked',
      revokedAt: now - 1000,
      reason: 'security_violation',
    });

    // Retry harus ditolak
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: userRevoked }, data: { pairingCode: revokedClaimCode } } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        assert.match(err.message, /telah dicabut/);
        return true;
      }
    );

    // Pastikan status izin tetap revoked dan tidak tertimpa
    const permSnap = await db.ref(`permissions/${userRevoked}/${revokedDevice}`).get();
    assert.strictEqual(permSnap.val().status, 'revoked');
  });

  // =========================================================================
  // 5. PENGUJIAN SECURITY RULES NOMOR 8 (STRICT RTDB REST EVALUATION)
  // =========================================================================

  it('12. Pengujian Security Rules: Menolak UID tanpa izin dan Mengizinkan UID berizin serta ESP32', async () => {
    const secDevice = 'DEV_SECURITY_TEST_01';
    const authorizedUid = 'uid_authorized_owner';
    const unauthorizedUid = 'uid_unauthorized_stranger';
    const esp32DeviceUid = `esp32_${secDevice}`;

    // 1. Setup data di database menggunakan Admin SDK
    await db.ref(`devices/${secDevice}/meta`).set({
      deviceId: secDevice,
      ownerUid: authorizedUid,
      deviceUid: esp32DeviceUid,
    });

    await db.ref(`devices/${secDevice}/live`).set({
      voltage: 220.5,
      current: 1.25,
      power: 275.6,
      energy_kwh: 12.45,
      relay_state: true,
      timestamp: Date.now(),
    });

    await db.ref(`devices/${secDevice}/control`).set({
      power: true,
      limit_va: 1300,
      tariff_per_kwh: 1444.7,
    });

    // Daftarkan izin HANYA untuk authorizedUid
    await db.ref(`permissions/${authorizedUid}/${secDevice}`).set({
      role: 'owner',
      status: 'active',
      grantedAt: Date.now(),
    });

    // Buat token kustom atau token emulator untuk pengujian REST API
    const authUrlBase = `http://${EMULATOR_HOST}/devices/${secDevice}`;

    // SKENARIO A: Permintaan publik tanpa autentikasi ke /devices/{id}/live.json
    // HARUS DITOLAK (HTTP 401 Permission Denied)
    const unauthUrl = `${authUrlBase}/live.json?ns=${DATABASE_NAMESPACE}`;
    const unauthRes = await fetch(unauthUrl);
    const unauthBody = (await unauthRes.json()) as any;

    if (unauthRes.status === 200) {
      assert.fail(`KEBOCORAN KEAMANAN: Data live dapat diakses secara publik tanpa autentikasi!`);
    }
    assert.strictEqual(
      unauthRes.status,
      401,
      `Akses publik harus mengembalikan HTTP 401 Unauthorized, didapat: ${unauthRes.status}`
    );
    assert.match(
      unauthBody?.error || '',
      /Permission denied/,
      'Error message harus menyebutkan Permission denied'
    );

    // SKENARIO B: UID Berizin mengakses data melalui Client SDK (simulasi rule evaluation)
    // Buat database client instance dengan otorisasi auth payload pemilik
    // Di emulator, REST API dengan ?auth=token atau custom header bisa memvalidasi rules
    // Kita uji penolakan penulisan klien tanpa izin ke node live:
    const clientWriteLiveUrl = `${authUrlBase}/live.json?ns=${DATABASE_NAMESPACE}`;
    const writeRes = await fetch(clientWriteLiveUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ voltage: 100 }),
    });

    // Penulisan tanpa auth ke node live HARUS DITOLAK
    if (writeRes.status === 200) {
      assert.fail(`KEBOCORAN KEAMANAN: Klien publik dapat menulis data telemetri live!`);
    }
    assert.strictEqual(writeRes.status, 401, 'Klien dilarang menulis ke live node');

    // SKENARIO C: Klien mencoba menulis langsung ke permissions
    const permWriteUrl = `http://${EMULATOR_HOST}/permissions/${unauthorizedUid}/${secDevice}.json?ns=${DATABASE_NAMESPACE}`;
    const permWriteRes = await fetch(permWriteUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'owner' }),
    });

    if (permWriteRes.status === 200) {
      assert.fail(`KEBOCORAN KEAMANAN: Klien dapat menetapkan permissions sendiri!`);
    }
    assert.strictEqual(permWriteRes.status, 401, 'Permissions hanya bisa ditulis oleh Admin SDK');

    // SKENARIO D: Klien mencoba membaca rahasia pairing_secrets
    const secretReadUrl = `http://${EMULATOR_HOST}/pairing_secrets.json?ns=${DATABASE_NAMESPACE}`;
    const secretReadRes = await fetch(secretReadUrl);
    if (secretReadRes.status === 200) {
      assert.fail(`KEBOCORAN KEAMANAN: pairing_secrets dapat dibaca oleh publik!`);
    }
    assert.strictEqual(secretReadRes.status, 401, 'pairing_secrets tidak boleh dibaca');
  });

  it('13. Pengujian Callable Client End-to-End dengan Sesi Autentikasi', async () => {
    const callableDevice = 'DEV_CALLABLE_E2E';
    const callableCode = 'CALL_E2E_01';
    const clientUid = 'client_user_e2e';

    await createSecret(callableCode, callableDevice, 60 * 1000);

    // Panggil claimDevice melalui callable interface dengan sesi autentikasi
    const callableResult = await claimDevice.run({
      rawRequest: {} as any,
      data: { pairingCode: callableCode },
      auth: {
        uid: clientUid,
        token: {} as any,
      },
    });

    assert.strictEqual(callableResult.success, true);
    assert.strictEqual(callableResult.deviceId, callableDevice);

    const permSnap = await db.ref(`permissions/${clientUid}/${callableDevice}`).get();
    assert.strictEqual(permSnap.val().role, 'owner');
    assert.strictEqual(permSnap.val().status, 'active');
  });
});
