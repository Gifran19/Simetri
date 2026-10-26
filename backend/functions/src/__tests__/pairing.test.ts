import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { handleClaimDevice } from '../pairing';
import { HttpsError } from 'firebase-functions/v2/https';

const PROJECT_ID = 'simetri-app';
const DATABASE_NAMESPACE = 'simetri-app-default-rtdb';
const EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
const AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FUNCTIONS_EMULATOR_HOST = process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001';

process.env.FIREBASE_DATABASE_EMULATOR_HOST = EMULATOR_HOST;
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: PROJECT_ID,
    databaseURL: `http://${EMULATOR_HOST}?ns=${DATABASE_NAMESPACE}`,
  });
}

const db = admin.database();
const auth = admin.auth();

/**
 * Helper: Menghasilkan ID Token JWT asli dari Auth Emulator untuk UID tertentu.
 * Menggunakan createCustomToken lalu ditukarkan ke IdToken via Auth Emulator REST API.
 */
async function getIdTokenForUid(uid: string): Promise<string> {
  const customToken = await auth.createCustomToken(uid);
  const exchangeUrl = `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-emulator-key`;
  
  const res = await fetch(exchangeUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gagal menukarkan custom token di Auth Emulator: ${res.status} ${errText}`);
  }

  const json = (await res.json()) as any;
  return json.idToken;
}

/**
 * Helper: Membuat akun anonim baru di Auth Emulator dan mengembalikan { uid, idToken }
 */
async function createAnonymousUserInEmulator(): Promise<{ uid: string; idToken: string }> {
  const signupUrl = `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-emulator-key`;
  const res = await fetch(signupUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gagal membuat anonymous user di Auth Emulator: ${res.status} ${errText}`);
  }

  const json = (await res.json()) as any;
  return { uid: json.localId, idToken: json.idToken };
}

describe('SIMETRI Production-Grade Pairing & Security Verification Suite', () => {

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
  // 1. PENGUJIAN JARINGAN NYATA HTTP KE CLOUD FUNCTIONS & AUTH EMULATOR (POIN 2)
  // =========================================================================

  it('1. Jaringan Nyata: Permintaan callable claimDevice TANPA token ditolak dengan HTTP 401', async () => {
    const functionUrl = `http://${FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/us-central1/claimDevice`;
    const res = await fetch(functionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { pairingCode: 'ANY_CODE' } }),
    });

    assert.strictEqual(
      res.status,
      401,
      `Request tanpa token harus mengembalikan HTTP 401 Unauthenticated, didapat: ${res.status}`
    );
  });

  it('2. Jaringan Nyata: Permintaan callable claimDevice dengan token INVALID ditolak dengan HTTP 401', async () => {
    const functionUrl = `http://${FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/us-central1/claimDevice`;
    const res = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer invalid_fake_token_jwt_xyz',
      },
      body: JSON.stringify({ data: { pairingCode: 'ANY_CODE' } }),
    });

    assert.strictEqual(
      res.status,
      401,
      `Request dengan token tidak valid harus ditolak 401, didapat: ${res.status}`
    );
  });

  it('3. Jaringan Nyata: Login anonim ke Auth Emulator lalu panggil claimDevice dengan token VALID berhasil 200 OK', async () => {
    // 1. Buat user anonim aktual di Auth Emulator
    const anonUser = await createAnonymousUserInEmulator();
    const networkDevice = 'DEV_NETWORK_E2E_01';
    const networkCode = 'NET_E2E_99';

    // Daftarkan kode pairing di database emulator
    await createSecret(networkCode, networkDevice, 60 * 1000);

    // 2. Kirim request HTTP nyata ke Functions Emulator dengan header Authorization
    const functionUrl = `http://${FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/us-central1/claimDevice`;
    const res = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${anonUser.idToken}`,
      },
      body: JSON.stringify({ data: { pairingCode: networkCode } }),
    });

    assert.strictEqual(res.status, 200, `Klaim dengan token valid harus mengembalikan HTTP 200`);

    const json = (await res.json()) as any;
    assert.strictEqual(json.result?.success, true);
    assert.strictEqual(json.result?.deviceId, networkDevice);

    // Verifikasi izin di database terdaftar atas anonUser.uid
    const permSnap = await db.ref(`permissions/${anonUser.uid}/${networkDevice}`).get();
    assert.strictEqual(permSnap.val()?.role, 'owner');
    assert.strictEqual(permSnap.val()?.status, 'active');
  });

  // =========================================================================
  // 2. PENGUJIAN SECURITY RULES DENGAN IDENTITAS AUTENTIKASI AKTUAL (POIN 1 & 3)
  // =========================================================================

  it('4. Security Rules: Pemilik aktif, pemilik revoked, orang asing, dan ESP32 diuji dengan ID Token nyata', async () => {
    const secDevice = 'DEV_SEC_STRICT_01';
    const otherDevice = 'DEV_SEC_OTHER_02';
    const activeOwnerUid = 'user_active_owner_real';
    const revokedOwnerUid = 'user_revoked_owner_real';
    const strangerUid = 'user_stranger_real';
    const esp32CorrectUid = `esp32_${secDevice}`;
    const esp32OtherUid = `esp32_${otherDevice}`;

    // Siapkan data perangkat di RTDB via Admin SDK
    await db.ref(`devices/${secDevice}/meta`).set({
      deviceId: secDevice,
      ownerUid: activeOwnerUid,
      deviceUid: esp32CorrectUid,
    });
    await db.ref(`devices/${secDevice}/live`).set({
      voltage: 220.0,
      current: 1.5,
      power: 330.0,
      energy_kwh: 10.0,
      relay_state: true,
      timestamp: Date.now(),
    });
    await db.ref(`devices/${secDevice}/control`).set({
      power: true,
      limit_va: 1300,
      tariff_per_kwh: 1444.7,
    });

    // Daftarkan status permission masing-masing
    await db.ref(`permissions/${activeOwnerUid}/${secDevice}`).set({
      role: 'owner',
      status: 'active',
      grantedAt: Date.now(),
    });
    await db.ref(`permissions/${revokedOwnerUid}/${secDevice}`).set({
      role: 'owner',
      status: 'revoked', // DICABUT!
      revokedAt: Date.now(),
    });

    // Generate ID Token asli dari Auth Emulator untuk kelima identitas
    const tokenActiveOwner = await getIdTokenForUid(activeOwnerUid);
    const tokenRevokedOwner = await getIdTokenForUid(revokedOwnerUid);
    const tokenStranger = await getIdTokenForUid(strangerUid);
    const tokenEsp32Correct = await getIdTokenForUid(esp32CorrectUid);
    const tokenEsp32Other = await getIdTokenForUid(esp32OtherUid);

    const baseUrl = `http://${EMULATOR_HOST}/devices/${secDevice}`;

    // --- UJI PEMILIK AKTIF ---
    // 1. Baca live: HARUS BERHASIL (200 OK)
    const activeReadLive = await fetch(`${baseUrl}/live.json?auth=${tokenActiveOwner}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(activeReadLive.status, 200, 'Pemilik aktif harus bisa membaca live data');

    // 2. Tulis control (power switch): HARUS BERHASIL (200 OK)
    const activeWriteControl = await fetch(`${baseUrl}/control/power.json?auth=${tokenActiveOwner}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(false),
    });
    assert.strictEqual(activeWriteControl.status, 200, 'Pemilik aktif harus bisa mengubah saklar power');

    // --- UJI PEMILIK REVOKED (POIN 1) ---
    // 3. Baca live: HARUS DITOLAK (401)
    const revokedReadLive = await fetch(`${baseUrl}/live.json?auth=${tokenRevokedOwner}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(revokedReadLive.status, 401, 'Pemilik yang statusnya revoked DILARANG membaca live data');

    // 4. Tulis control: HARUS DITOLAK (401)
    const revokedWriteControl = await fetch(`${baseUrl}/control/power.json?auth=${tokenRevokedOwner}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(true),
    });
    assert.strictEqual(revokedWriteControl.status, 401, 'Pemilik yang statusnya revoked DILARANG menulis control');

    // --- UJI PENGGUNA ASING (STRANGER) ---
    // 5. Baca live: HARUS DITOLAK (401)
    const strangerReadLive = await fetch(`${baseUrl}/live.json?auth=${tokenStranger}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(strangerReadLive.status, 401, 'Pengguna asing dilarang membaca live data');

    // 6. Tulis control: HARUS DITOLAK (401)
    const strangerWriteControl = await fetch(`${baseUrl}/control/power.json?auth=${tokenStranger}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(false),
    });
    assert.strictEqual(strangerWriteControl.status, 401, 'Pengguna asing dilarang menulis control');

    // --- UJI ESP32 PERANGKAT TARGET (esp32_DEV_SEC_STRICT_01) ---
    // 7. ESP32 tulis live: HARUS DISETUJUI (200 OK)
    const esp32WriteLive = await fetch(`${baseUrl}/live/power.json?auth=${tokenEsp32Correct}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(450.5),
    });
    assert.strictEqual(esp32WriteLive.status, 200, 'ESP32 sah harus diizinkan menulis telemetri live');

    // 8. ESP32 baca control: HARUS DISETUJUI (200 OK)
    const esp32ReadControl = await fetch(`${baseUrl}/control.json?auth=${tokenEsp32Correct}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(esp32ReadControl.status, 200, 'ESP32 sah harus diizinkan membaca perintah control');

    // 9. ESP32 tulis control: HARUS DITOLAK (401)
    const esp32WriteControl = await fetch(`${baseUrl}/control/power.json?auth=${tokenEsp32Correct}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(false),
    });
    assert.strictEqual(esp32WriteControl.status, 401, 'ESP32 DILARANG mengubah pengaturan control');

    // --- UJI ESP32 PERANGKAT LAIN (esp32_DEV_SEC_OTHER_02) ---
    // 10. ESP32 lain tulis live perangkat ini: HARUS DITOLAK (401)
    const otherEspWriteLive = await fetch(`${baseUrl}/live/power.json?auth=${tokenEsp32Other}&ns=${DATABASE_NAMESPACE}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(999.0),
    });
    assert.strictEqual(otherEspWriteLive.status, 401, 'ESP32 perangkat lain DILARANG menulis live perangkat ini');

    // 11. ESP32 lain baca control perangkat ini: HARUS DITOLAK (401)
    const otherEspReadControl = await fetch(`${baseUrl}/control.json?auth=${tokenEsp32Other}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(otherEspReadControl.status, 401, 'ESP32 perangkat lain DILARANG membaca control perangkat ini');
  });

  // =========================================================================
  // 3. PENGUJIAN ISOLASI DATA HISTORI ENERGI ANTAR PERANGKAT (POIN 6)
  // =========================================================================

  it('5. Isolasi Energy Data: energy_data/{deviceId}/{year} terisolasi penuh antar perangkat', async () => {
    const devA = 'DEV_ENERGY_A';
    const devB = 'DEV_ENERGY_B';
    const userA = 'user_energy_owner_a';
    const userB = 'user_energy_owner_b';

    // Daftarkan permissions untuk A dan B
    await db.ref(`permissions/${userA}/${devA}`).set({ role: 'owner', status: 'active' });
    await db.ref(`permissions/${userB}/${devB}`).set({ role: 'owner', status: 'active' });

    // Tulis histori energi masing-masing
    await db.ref(`energy_data/${devA}/2026/summary`).set({ total_energy: 150.0, total_cost: 200000 });
    await db.ref(`energy_data/${devB}/2026/summary`).set({ total_energy: 300.0, total_cost: 450000 });

    const tokenA = await getIdTokenForUid(userA);
    const tokenB = await getIdTokenForUid(userB);

    // User A membaca data energi miliknya: HARUS BERHASIL (200 OK)
    const resAtoA = await fetch(`http://${EMULATOR_HOST}/energy_data/${devA}/2026/summary.json?auth=${tokenA}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(resAtoA.status, 200, 'User A harus bisa membaca energy_data perangkat A');

    // User A mencoba membaca data energi perangkat B: HARUS DITOLAK (401)
    const resAtoB = await fetch(`http://${EMULATOR_HOST}/energy_data/${devB}/2026/summary.json?auth=${tokenA}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(resAtoB.status, 401, 'User A DILARANG membaca energy_data perangkat B');

    // User B membaca data energi miliknya: HARUS BERHASIL (200 OK)
    const resBtoB = await fetch(`http://${EMULATOR_HOST}/energy_data/${devB}/2026/summary.json?auth=${tokenB}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(resBtoB.status, 200, 'User B harus bisa membaca energy_data perangkat B');

    // User B mencoba membaca data energi perangkat A: HARUS DITOLAK (401)
    const resBtoA = await fetch(`http://${EMULATOR_HOST}/energy_data/${devA}/2026/summary.json?auth=${tokenB}&ns=${DATABASE_NAMESPACE}`);
    assert.strictEqual(resBtoA.status, 401, 'User B DILARANG membaca energy_data perangkat A');
  });

  // =========================================================================
  // 4. RATE LIMITING PRE-CHECK (POIN 5)
  // =========================================================================

  it('6. Rate Limiting Pre-check: Kode valid langsung ditolak jika UID pemanggil sedang terblokir', async () => {
    const blockedUid = 'uid_currently_blocked';
    const validCode = 'VALID_CODE_BLOCKED_TEST';
    const targetDev = 'DEV_BLOCKED_TEST_01';

    // Buat kode valid di database
    await createSecret(validCode, targetDev, 60 * 1000);

    // Pasang counter rate limit blockedUid pada ambang batas pemblokiran (5 kali salah)
    const now = Date.now();
    await db.ref(`pairing_rate_limits/${blockedUid}`).set({
      attempts: 5,
      lastAttempt: now - 30000, // 30 detik lalu (masih dalam jendela 5 menit)
    });

    // Panggil claimDevice dengan KODE VALID
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: blockedUid }, data: { pairingCode: validCode } } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'resource-exhausted');
        assert.match(err.message, /Akun Anda sedang dibatasi/);
        return true;
      }
    );

    // Pastikan kode valid tersebut BELUM digunakan (tetap unused) karena ditolak sebelum membaca secret
    const hash = crypto.createHash('sha256').update(validCode).digest('hex');
    const secretSnap = await db.ref(`pairing_secrets/${hash}`).get();
    assert.strictEqual(secretSnap.val().used, false, 'Kode harus tetap unused');
  });

  // =========================================================================
  // 5. KONSISTENSI KEPEMILIKAN: RECOVERY & PEMINDAHAN KEPEMILIKAN (POIN 4)
  // =========================================================================

  it('7. Recovery tidak boleh menimpa pemilik baru setelah pemindahan kepemilikan', async () => {
    const oldOwnerUid = 'user_former_owner';
    const newOwnerUid = 'user_current_owner';
    const handoverDevice = 'DEV_HANDOVER_01';
    const oldCode = 'OLD_CODE_HANDOVER';
    const hashOld = crypto.createHash('sha256').update(oldCode).digest('hex');

    const now = Date.now();
    // Simulasikan secret lama pernah digunakan oleh oldOwnerUid
    await db.ref(`pairing_secrets/${hashOld}`).set({
      deviceId: handoverDevice,
      expiresAt: now + 60000,
      used: true,
      usedBy: oldOwnerUid,
      usedAt: now - 100000,
      status: 'used',
      createdAt: now - 200000,
    });

    // Metadata perangkat saat ini sudah secara sah dimiliki oleh newOwnerUid
    await db.ref(`devices/${handoverDevice}/meta`).set({
      deviceId: handoverDevice,
      ownerUid: newOwnerUid,
      claimOpId: 'op_new_owner_123',
      claimedAt: now - 50000,
    });

    // oldOwnerUid mencoba retry recovery menggunakan kode lamanya
    await assert.rejects(
      async () => {
        await handleClaimDevice(
          { auth: { uid: oldOwnerUid }, data: { pairingCode: oldCode } } as any,
          db
        );
      },
      (err: any) => {
        assert.ok(err instanceof HttpsError);
        assert.strictEqual(err.code, 'failed-precondition');
        assert.match(err.message, /dipindahtangankan ke pemilik baru/);
        return true;
      }
    );

    // Pastikan newOwnerUid TIDAK TERTEMBUS / TIDAK TERTAPA
    const metaSnap = await db.ref(`devices/${handoverDevice}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, newOwnerUid, 'Pemilik baru harus tetap newOwnerUid');
  });

  it('8. Dua permintaan simultan dari UID yang sama dengan kode yang sama keduanya berhasil konsisten', async () => {
    const sameUserUid = 'user_double_clicker';
    const sameUserDevice = 'DEV_DOUBLE_CLICK_01';
    const sameUserCode = 'DOUBLE_CLICK_99';

    await createSecret(sameUserCode, sameUserDevice, 60 * 1000);

    const req1 = { auth: { uid: sameUserUid }, data: { pairingCode: sameUserCode } } as any;
    const req2 = { auth: { uid: sameUserUid }, data: { pairingCode: sameUserCode } } as any;

    const results = await Promise.allSettled([
      handleClaimDevice(req1, db),
      handleClaimDevice(req2, db),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    assert.strictEqual(
      fulfilled.length,
      2,
      'Kedua permintaan simultan dari UID yang sama harus berakhir fulfilled secara konsisten'
    );

    const res1 = (fulfilled[0] as PromiseFulfilledResult<any>).value;
    const res2 = (fulfilled[1] as PromiseFulfilledResult<any>).value;
    assert.strictEqual(res1.deviceId, sameUserDevice);
    assert.strictEqual(res2.deviceId, sameUserDevice);

    const metaSnap = await db.ref(`devices/${sameUserDevice}/meta`).get();
    assert.strictEqual(metaSnap.val().ownerUid, sameUserUid);
  });
});
