#!/usr/bin/env node

/**
 * SIMETRI Local Admin Script
 * Mendaftarkan perangkat baru, menerbitkan kode pairing sementara,
 * dan mem-provision identitas Firebase Auth khusus untuk perangkat ESP32.
 *
 * PENGGUNAAN:
 *   node scripts/register_device.js --mode=emulator <deviceId> [expiresInMinutes] [deviceLabel]
 *   node scripts/register_device.js --mode=production <deviceId> [expiresInMinutes] [deviceLabel]
 *
 * FLAG WAJIB:
 *   --mode=emulator    Terhubung ke Firebase Emulator Suite (lokal)
 *   --mode=production  Terhubung ke project Firebase production (perlu serviceAccountKey.json)
 *
 * CONTOH:
 *   node scripts/register_device.js --mode=emulator SIMETRI_ESP32_001 60 "Kwh Meter Ruang Utama"
 *   node scripts/register_device.js --mode=production SIMETRI_ESP32_001 60 "Kwh Meter Ruang Utama"
 *
 * KEAMANAN:
 *   - Jangan commit serviceAccountKey.json ke repository.
 *   - Password perangkat hanya ditampilkan SATU KALI saat pembuatan akun baru.
 *   - Catat dan simpan password dengan aman sebelum menutup terminal.
 */

const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// ============================================================
// PARSE ARGUMEN CLI
// ============================================================

const rawArgs = process.argv.slice(2);

// Ekstrak --mode flag
const modeArg = rawArgs.find(arg => arg.startsWith('--mode='));
if (!modeArg) {
  console.error('');
  console.error('ERROR: Flag --mode wajib ditentukan.');
  console.error('');
  console.error('Gunakan:');
  console.error('  node scripts/register_device.js --mode=emulator <deviceId> ...');
  console.error('  node scripts/register_device.js --mode=production <deviceId> ...');
  console.error('');
  console.error('CATATAN: Skrip ini tidak pernah memilih mode secara otomatis.');
  console.error('         Menentukan mode secara eksplisit mencegah pengujian lokal');
  console.error('         yang tidak sengaja menyentuh database produksi.');
  process.exit(1);
}

const mode = modeArg.split('=')[1];
if (mode !== 'emulator' && mode !== 'production') {
  console.error(`ERROR: Mode tidak valid: "${mode}". Hanya "emulator" atau "production" yang diperbolehkan.`);
  process.exit(1);
}

// Argumen posisional (setelah mengabaikan --mode flag)
const positionalArgs = rawArgs.filter(arg => !arg.startsWith('--'));
const deviceId = positionalArgs[0];
const expiresInMinutes = parseInt(positionalArgs[1], 10) || 60;
const label = positionalArgs[2] || (deviceId ? `Perangkat ${deviceId}` : null);

if (!deviceId) {
  console.error('ERROR: deviceId wajib ditentukan sebagai argumen pertama posisional.');
  console.error('Contoh: node scripts/register_device.js --mode=emulator SIMETRI_ESP32_001 60');
  process.exit(1);
}

// ============================================================
// KONFIGURASI BERDASARKAN MODE
// ============================================================

let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  try {
    admin = require(path.resolve(__dirname, '../backend/functions/node_modules/firebase-admin'));
  } catch (e) {
    console.error('Error: firebase-admin tidak ditemukan. Jalankan "npm install" di folder backend/functions terlebih dahulu.');
    process.exit(1);
  }
}

const EMULATOR_PROJECT_ID = 'simetri-app';
const EMULATOR_DATABASE_NAMESPACE = 'simetri-app-default-rtdb';
const EMULATOR_DB_HOST = '127.0.0.1:9000';
const EMULATOR_AUTH_HOST = '127.0.0.1:9099';

let projectId;
let databaseURL;
let adminInitOptions;

if (mode === 'emulator') {
  // ── MODE EMULATOR ──────────────────────────────────────────
  process.env.FIREBASE_DATABASE_EMULATOR_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || EMULATOR_DB_HOST;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || EMULATOR_AUTH_HOST;

  projectId = EMULATOR_PROJECT_ID;
  databaseURL = `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=${EMULATOR_DATABASE_NAMESPACE}`;

  adminInitOptions = {
    projectId,
    databaseURL,
  };

  console.log('');
  console.log('MODE: EMULATOR (tidak ada akses ke database produksi)');
  console.log(`  Database Host : ${process.env.FIREBASE_DATABASE_EMULATOR_HOST}`);
  console.log(`  Auth Host     : ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`);

} else {
  // ── MODE PRODUCTION ────────────────────────────────────────
  const serviceAccountPath = path.resolve(__dirname, '../serviceAccountKey.json');
  if (!fs.existsSync(serviceAccountPath)) {
    console.error('');
    console.error('ERROR: serviceAccountKey.json tidak ditemukan untuk mode production.');
    console.error(`Path yang dicari: ${serviceAccountPath}`);
    console.error('');
    console.error('Langkah setup:');
    console.error('  1. Buka Firebase Console → Project Settings → Service Accounts');
    console.error('  2. Klik "Generate new private key"');
    console.error('  3. Simpan file sebagai: serviceAccountKey.json (di root proyek)');
    console.error('  4. PASTIKAN serviceAccountKey.json ada di .gitignore!');
    process.exit(1);
  }

  const serviceAccount = require(serviceAccountPath);
  projectId = serviceAccount.project_id;
  const namespace = (process.env.FIREBASE_DATABASE_NAMESPACE || `${projectId}-default-rtdb`);
  databaseURL = process.env.FIREBASE_DATABASE_URL || `https://${namespace}.firebaseio.com`;

  // Validasi: pastikan project ID dan database URL tidak kosong atau masih placeholder
  if (!projectId || projectId.includes('YOUR_') || projectId.length < 4) {
    console.error(`ERROR: project_id tidak valid di serviceAccountKey.json: "${projectId}"`);
    process.exit(1);
  }
  if (!databaseURL || databaseURL.includes('YOUR_') || !databaseURL.startsWith('https://')) {
    console.error(`ERROR: databaseURL tidak valid: "${databaseURL}"`);
    console.error('Setel FIREBASE_DATABASE_URL=https://<namespace>.firebaseio.com atau FIREBASE_DATABASE_NAMESPACE=<namespace>');
    process.exit(1);
  }

  adminInitOptions = {
    credential: admin.credential.cert(serviceAccount),
    databaseURL,
  };

  console.log('');
  console.log('MODE: PRODUCTION');
  console.log(`  Project ID    : ${projectId}`);
  console.log(`  Database URL  : ${databaseURL}`);
  console.log('  ⚠️  Perubahan akan langsung memengaruhi database produksi!');
}

// Validasi final sebelum inisialisasi
if (!projectId || !databaseURL) {
  console.error('ERROR: projectId atau databaseURL tidak dapat ditentukan. Periksa konfigurasi.');
  process.exit(1);
}

admin.initializeApp(adminInitOptions);
const db = admin.database();
const auth = admin.auth();

// ============================================================
// FUNGSI UTAMA
// ============================================================

function generateSecurePairingCode() {
  const bytes = crypto.randomBytes(4);
  return bytes.toString('hex').toUpperCase(); // 8 karakter
}

/**
 * Provision akun Firebase Auth untuk perangkat ESP32.
 * Password hanya ditampilkan saat akun BARU dibuat.
 * Untuk akun yang sudah ada, password tidak ditampilkan.
 */
async function provisionEsp32AuthIdentity(targetDeviceId) {
  const esp32Uid = `esp32_${targetDeviceId}`;
  const esp32Email = `device_${targetDeviceId.toLowerCase()}@simetri.internal`;
  const newPassword = `esp_${crypto.randomBytes(12).toString('hex')}`;

  let userRecord;
  let isNew = false;

  try {
    userRecord = await auth.getUser(esp32Uid);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      userRecord = await auth.createUser({
        uid: esp32Uid,
        email: esp32Email,
        password: newPassword,
        displayName: `ESP32 Device ${targetDeviceId}`,
      });
      isNew = true;
    } else {
      throw err;
    }
  }

  return {
    uid: userRecord.uid,
    email: userRecord.email,
    // Password HANYA dikembalikan untuk akun baru
    password: isNew ? newPassword : null,
    isNew,
  };
}

async function registerDeviceAndIssueCode() {
  console.log('');
  console.log('====================================================');
  console.log('       SIMETRI ADMIN - PENDAFTARAN PERANGKAT        ');
  console.log('====================================================');
  console.log(`Device ID   : ${deviceId}`);
  console.log(`Label       : ${label}`);
  console.log(`Masa Berlaku: ${expiresInMinutes} menit`);

  try {
    // 1. Provisioning Identitas Firebase Auth untuk ESP32
    const deviceAuth = await provisionEsp32AuthIdentity(deviceId);

    console.log('----------------------------------------------------');
    console.log('Identitas Firebase Auth ESP32:');
    console.log(`  Device UID   : ${deviceAuth.uid}`);
    console.log(`  Device Email : ${deviceAuth.email}`);

    if (deviceAuth.isNew) {
      // Password HANYA ditampilkan saat akun baru dibuat
      // CATATAN: Password ini tidak dicatat ke file log manapun
      console.log(`  Password     : ${deviceAuth.password}`);
      console.log('  ⚠️  Catat password ini sekarang! Tidak akan ditampilkan lagi.');
    } else {
      console.log('  Password     : (akun sudah ada, gunakan password yang sudah dicatat)');
    }

    console.log('  Catatan: Firmware ESP32 login via Firebase Auth REST API.');
    console.log('           TIDAK memerlukan database secret atau service account!');
    console.log('----------------------------------------------------');

    // 2. Generate kode pairing
    const pairingCode = generateSecurePairingCode();
    const sha256Hash = crypto.createHash('sha256').update(pairingCode).digest('hex');
    const now = Date.now();
    const expiresAt = now + expiresInMinutes * 60 * 1000;

    console.log(`Kode Pairing : ${pairingCode}  ← Berikan ke pengguna`);
    console.log(`Kedaluwarsa  : ${new Date(expiresAt).toLocaleString('id-ID')}`);

    const multiPathUpdates = {};

    // 3. Baca metadata perangkat yang sudah ada
    const metaRef = db.ref(`devices/${deviceId}/meta`);
    const existingMetaSnap = await metaRef.get();
    const existingMeta = existingMetaSnap.val() || {};

    // 4. Cabut kode lama jika ada
    if (existingMeta.activePairingHash && existingMeta.activePairingHash !== sha256Hash) {
      console.log(`Mencabut kode pairing lama (Hash prefix: ${existingMeta.activePairingHash.substring(0, 10)}...)`);
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/status`] = 'revoked';
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedAt`] = now;
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedReason`] = 'superseded_by_new_code';
    }

    // 5. Pendaftaran: PERTAHANKAN PEMILIK YANG SUDAH ADA
    multiPathUpdates[`devices/${deviceId}/meta`] = {
      deviceId: deviceId,
      label: label,
      registeredAt: existingMeta.registeredAt || now,
      registeredBy: `admin_${mode}_script`,
      ownerUid: existingMeta.ownerUid || null,
      claimOpId: existingMeta.claimOpId || null,
      claimedAt: existingMeta.claimedAt || null,
      activePairingHash: sha256Hash,
      deviceUid: deviceAuth.uid,
    };

    // 6. Simpan rahasia pairing baru
    multiPathUpdates[`pairing_secrets/${sha256Hash}`] = {
      deviceId: deviceId,
      expiresAt: expiresAt,
      used: false,
      usedBy: null,
      usedAt: null,
      status: 'available',
      createdAt: now,
    };

    await db.ref().update(multiPathUpdates);

    console.log('----------------------------------------------------');
    console.log('✓ Perangkat dan kode pairing berhasil didaftarkan!');
    if (existingMeta.ownerUid) {
      console.log(`  [INFO] Perangkat ini dimiliki oleh UID: ${existingMeta.ownerUid}`);
    }
    console.log('====================================================');
    process.exit(0);
  } catch (error) {
    console.error('');
    console.error('✗ Gagal mendaftarkan perangkat:', error.message || error);
    process.exit(1);
  }
}

registerDeviceAndIssueCode();
