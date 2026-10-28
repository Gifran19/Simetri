import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as admin from 'firebase-admin';

const PROJECT_ID = 'simetri-app';
const DATABASE_NAMESPACE = 'simetri-app-default-rtdb';
const EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
const AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

process.env.FIREBASE_DATABASE_EMULATOR_HOST = EMULATOR_HOST;
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;

let db: admin.database.Database;
let auth: admin.auth.Auth;

async function verifyEmulatorAvailability(): Promise<void> {
  const timeoutMs = 2500;
  try {
    await fetch(`http://${AUTH_EMULATOR_HOST}`, {
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err: any) {
    throw new Error(
      `[EMULATOR_OFFLINE] Firebase Emulator Suite tidak tersedia di ${AUTH_EMULATOR_HOST} / ${EMULATOR_HOST}. ` +
      `Detail: ${err.message}`
    );
  }
}

async function getIdTokenForUid(uid: string): Promise<string> {
  const customToken = await auth.createCustomToken(uid);
  const exchangeUrl = `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-emulator-key`;
  const res = await fetch(exchangeUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    signal: AbortSignal.timeout(5000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gagal menukarkan custom token di Auth Emulator: ${res.status} ${errText}`);
  }

  const json = (await res.json()) as any;
  return json.idToken;
}

async function createAnonymousUserInEmulator(): Promise<{ uid: string; idToken: string }> {
  const signupUrl = `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-emulator-key`;
  const res = await fetch(signupUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
    signal: AbortSignal.timeout(5000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gagal membuat anonymous user di Auth Emulator: ${res.status} ${errText}`);
  }

  const json = (await res.json()) as any;
  return { uid: json.localId, idToken: json.idToken };
}

describe('SIMETRI Local Admin Approval & Closed Security Rules Suite', () => {

  before(async () => {
    await verifyEmulatorAvailability();

    if (admin.apps.length === 0) {
      admin.initializeApp({
        projectId: PROJECT_ID,
        databaseURL: `http://${EMULATOR_HOST}?ns=${DATABASE_NAMESPACE}`,
      });
    }
    db = admin.database();
    auth = admin.auth();

    // Reset database
    await db.ref().set(null);
  });

  after(async () => {
    await db.ref().set(null);
    db.goOffline();
    await db.app.delete();
  });

  const DEV_A = 'SIMETRI_DEV_TEST_01';
  const DEV_B = 'SIMETRI_DEV_TEST_02';

  it('1. Akses tanpa izin: Pengguna anonim tanpa izin DITOLAK membaca devices/DEV_A/live', async () => {
    const userA = await createAnonymousUserInEmulator();

    // Set up perangkat di RTDB via Admin SDK
    await db.ref(`devices/${DEV_A}/meta`).set({
      deviceId: DEV_A,
      deviceUid: `esp32_${DEV_A}`,
      registeredAt: Date.now(),
      ownerUid: null,
    });
    await db.ref(`devices/${DEV_A}/live`).set({
      voltage: 220.0,
      current: 1.5,
      power: 330.0,
      energy_kwh: 12.5,
      relay_state: false,
      timestamp: Date.now(),
    });

    // Pengguna mencoba membaca live tanpa memiliki izin di permissions
    const readUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/live.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const res = await fetch(readUrl);

    assert.strictEqual(
      res.status,
      401,
      `Pengguna tanpa izin harus ditolak membaca live dengan HTTP 401, didapat: ${res.status}`
    );
  });

  it('2. Penolakan modifikasi: Pengguna anonim tanpa izin DITOLAK menulis ke devices/DEV_A/control', async () => {
    const userA = await createAnonymousUserInEmulator();

    const writeUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/control.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const res = await fetch(writeUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ power: true, limit_va: 1300, tariff_per_kwh: 1500 }),
    });

    assert.strictEqual(
      res.status,
      401,
      `Pengguna tanpa izin harus ditolak menulis control dengan HTTP 401, didapat: ${res.status}`
    );
  });

  it('3. Aplikasi tidak dapat memberi izin sendiri: Pengguna anonim DITOLAK menulis ke permissions/uid/deviceId', async () => {
    const userA = await createAnonymousUserInEmulator();

    const permWriteUrl = `http://${EMULATOR_HOST}/permissions/${userA.uid}/${DEV_A}.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const res = await fetch(permWriteUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'active', role: 'owner' }),
    });

    assert.strictEqual(
      res.status,
      401,
      `Aplikasi tidak boleh bisa menulis node permissions sendiri (.write: false), didapat: ${res.status}`
    );
  });

  it('4. Pemberian Izin oleh Admin Lokal: Admin memberikan izin active ke User A dan mengupdate ownerUid', async () => {
    const userA = await createAnonymousUserInEmulator();

    // Simulasi skrip admin lokal menulis via Admin SDK
    const now = Date.now();
    await db.ref(`devices/${DEV_A}/meta`).update({
      ownerUid: userA.uid,
      assignedAt: now,
    });
    await db.ref(`permissions/${userA.uid}/${DEV_A}`).set({
      status: 'active',
      role: 'owner',
      grantedAt: now,
      grantedBy: 'local_admin',
      deviceId: DEV_A,
    });

    // Verifikasi izin tersimpan di RTDB
    const permSnap = await db.ref(`permissions/${userA.uid}/${DEV_A}`).get();
    assert.strictEqual(permSnap.val()?.status, 'active');
    assert.strictEqual(permSnap.val()?.role, 'owner');

    const metaSnap = await db.ref(`devices/${DEV_A}/meta`).get();
    assert.strictEqual(metaSnap.val()?.ownerUid, userA.uid);

    // Pengguna dapat membaca izinnya sendiri
    const userPermUrl = `http://${EMULATOR_HOST}/permissions/${userA.uid}/${DEV_A}.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const userPermRes = await fetch(userPermUrl);
    assert.strictEqual(userPermRes.status, 200);
    const permData = (await userPermRes.json()) as any;
    assert.strictEqual(permData.status, 'active');
  });

  it('5. Akses Sukses Pemilik Aktif: User A membaca live dan menulis kontrol relay pada DEV_A', async () => {
    const userA = await createAnonymousUserInEmulator();

    // Admin memberikan izin
    await db.ref(`permissions/${userA.uid}/${DEV_A}`).set({
      status: 'active',
      role: 'owner',
      grantedAt: Date.now(),
    });

    // 1. Baca live telemetry
    const readUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/live.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const readRes = await fetch(readUrl);
    assert.strictEqual(readRes.status, 200, `Pemilik aktif harus diizinkan membaca live, didapat: ${readRes.status}`);
    const liveData = (await readRes.json()) as any;
    assert.strictEqual(liveData.voltage, 220.0);

    // 2. Tulis control relay
    const controlUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/control.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const controlRes = await fetch(controlUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ power: true, limit_va: 2200, tariff_per_kwh: 1444 }),
    });
    assert.strictEqual(controlRes.status, 200, `Pemilik aktif harus diizinkan menulis control, didapat: ${controlRes.status}`);
  });

  it('6. Isolasi Perangkat: User A dengan izin DEV_A DITOLAK membaca data DEV_B', async () => {
    const userA = await createAnonymousUserInEmulator();

    // Berikan izin hanya untuk DEV_A
    await db.ref(`permissions/${userA.uid}/${DEV_A}`).set({
      status: 'active',
      role: 'owner',
      grantedAt: Date.now(),
    });

    // Siapkan DEV_B
    await db.ref(`devices/${DEV_B}/meta`).set({ deviceId: DEV_B, deviceUid: `esp32_${DEV_B}` });
    await db.ref(`devices/${DEV_B}/live`).set({ voltage: 230.0, timestamp: Date.now() });

    // User A mencoba membaca DEV_B
    const readDevBUrl = `http://${EMULATOR_HOST}/devices/${DEV_B}/live.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const res = await fetch(readDevBUrl);
    assert.strictEqual(res.status, 401, `User A harus DITOLAK membaca DEV_B, didapat: ${res.status}`);
  });

  it('7. Penolakan Tulis Telemetri oleh Aplikasi: User A (aktif) DITOLAK menulis ke live telemetri', async () => {
    const userA = await createAnonymousUserInEmulator();

    await db.ref(`permissions/${userA.uid}/${DEV_A}`).set({
      status: 'active',
      role: 'owner',
      grantedAt: Date.now(),
    });

    // User A mencoba menulis ke live (hanya boleh ditulis ESP32)
    const writeLiveUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/live.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const res = await fetch(writeLiveUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ voltage: 999.0, current: 50.0, power: 50000.0, energy_kwh: 100.0, relay_state: true, timestamp: Date.now() }),
    });

    assert.strictEqual(
      res.status,
      401,
      `Aplikasi pengguna aktif harus DITOLAK menulis ke devices/$deviceId/live (harus 401), didapat: ${res.status}`
    );
  });

  it('8. ESP32 Telemetri Nyata: Akun autentikasi ESP32 BERHASIL menulis ke devices/DEV_A/live', async () => {
    // Akun ESP32 memiliki UID: esp32_SIMETRI_DEV_TEST_01
    const esp32Uid = `esp32_${DEV_A}`;
    const esp32Token = await getIdTokenForUid(esp32Uid);

    const writeLiveUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/live.json?ns=${DATABASE_NAMESPACE}&auth=${esp32Token}`;
    const res = await fetch(writeLiveUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        voltage: 221.4,
        current: 2.1,
        power: 465.0,
        energy_kwh: 15.2,
        relay_state: false,
        timestamp: Date.now(),
      }),
    });

    assert.strictEqual(
      res.status,
      200,
      `Akun ESP32 resmi harus BERHASIL menulis telemetri, didapat: ${res.status}`
    );

    // Verifikasi data masuk
    const checkSnap = await db.ref(`devices/${DEV_A}/live/voltage`).get();
    assert.strictEqual(checkSnap.val(), 221.4);
  });

  it('9. Pencabutan Izin (Revocation): Admin mencabut izin User A -> akses langsung terputus', async () => {
    const userA = await createAnonymousUserInEmulator();

    // 1. Mula-mula aktif
    await db.ref(`permissions/${userA.uid}/${DEV_A}`).set({
      status: 'active',
      role: 'owner',
      grantedAt: Date.now(),
    });
    await db.ref(`devices/${DEV_A}/meta`).update({ ownerUid: userA.uid });

    // Verifikasi awalnya bisa membaca
    const readUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/live.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const initialRes = await fetch(readUrl);
    assert.strictEqual(initialRes.status, 200);

    // 2. Admin lokal mencabut izin (status -> 'revoked' dan ownerUid -> null)
    await db.ref(`permissions/${userA.uid}/${DEV_A}`).update({
      status: 'revoked',
      revokedAt: Date.now(),
    });
    await db.ref(`devices/${DEV_A}/meta`).update({ ownerUid: null });

    // 3. User A mencoba membaca live lagi
    const afterRevokeRead = await fetch(readUrl);
    assert.strictEqual(
      afterRevokeRead.status,
      401,
      `Pengguna berstatus revoked harus LANGSUNG DITOLAK membaca (401), didapat: ${afterRevokeRead.status}`
    );

    // 4. User A mencoba menulis control
    const controlUrl = `http://${EMULATOR_HOST}/devices/${DEV_A}/control.json?ns=${DATABASE_NAMESPACE}&auth=${userA.idToken}`;
    const afterRevokeWrite = await fetch(controlUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ power: false }),
    });
    assert.strictEqual(
      afterRevokeWrite.status,
      401,
      `Pengguna berstatus revoked harus LANGSUNG DITOLAK menulis control (401), didapat: ${afterRevokeWrite.status}`
    );
  });
});
