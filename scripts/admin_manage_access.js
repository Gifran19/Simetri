#!/usr/bin/env node

/**
 * ============================================================================
 * SIMETRI Local Admin Access Management Script
 * ============================================================================
 * Mengelola pemberian dan pencabutan hak akses perangkat IoT SIMETRI
 * untuk arsitektur Firebase Spark (tanpa Cloud Functions / Blaze).
 *
 * PENGGUNAAN:
 *   node scripts/admin_manage_access.js --mode=emulator <command> [arguments]
 *   node scripts/admin_manage_access.js --mode=production <command> [arguments]
 *
 * DAFTAR PERINTAH (COMMANDS):
 *   grant <deviceId> <userUid> [role] [deviceLabel]
 *       Memberikan izin akses perangkat ke UID anonim pengguna.
 *       Role bawaan: "owner" (jika belum ada owner) atau "member".
 *
 *   revoke <deviceId> <userUid>
 *       Mencabut izin akses perangkat dari UID pengguna.
 *
 *   list [deviceId]
 *       Menampilkan status izin dan kepemilikan perangkat.
 *
 *   provision-esp32 <deviceId> [deviceLabel]
 *       Membuat identitas autentikasi ESP32 di Firebase Auth dan mendaftarkan meta.
 *
 * KEAMANAN:
 *   - Skrip ini HANYA dijalankan oleh administrator di komputer lokal.
 *   - Memerlukan serviceAccountKey.json untuk mode production (wajib di-.gitignore).
 *   - Kredensial admin tidak pernah dikirim atau dimasukkan ke Flutter / ESP32.
 * ============================================================================
 */

const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// ------------------------------------------------------------
// 1. PARSE & VALIDASI ARGUMEN CLI
// ------------------------------------------------------------
const rawArgs = process.argv.slice(2);
const modeArg = rawArgs.find(arg => arg.startsWith('--mode='));

if (!modeArg) {
  console.error('\n[ERROR] Flag --mode wajib ditentukan secara eksplisit.');
  console.error('Gunakan:');
  console.error('  node scripts/admin_manage_access.js --mode=emulator <command> ...');
  console.error('  node scripts/admin_manage_access.js --mode=production <command> ...');
  console.error('\nCatatan: Pencegahan otomatis agar pengujian lokal tidak menyentuh database produksi.');
  process.exit(1);
}

const mode = modeArg.split('=')[1];
if (mode !== 'emulator' && mode !== 'production') {
  console.error(`\n[ERROR] Mode "${mode}" tidak valid. Pilih "emulator" atau "production".`);
  process.exit(1);
}

const positionalArgs = rawArgs.filter(arg => !arg.startsWith('--'));
const command = positionalArgs[0];

if (!command) {
  console.error('\n[ERROR] Perintah wajib ditentukan.');
  console.error('Perintah yang tersedia: grant, revoke, list, provision-esp32');
  console.error('Contoh: node scripts/admin_manage_access.js --mode=emulator grant SIMETRI_ESP32_001 <userUid>');
  process.exit(1);
}

// ------------------------------------------------------------
// 2. INISIALISASI FIREBASE ADMIN SDK
// ------------------------------------------------------------
let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  try {
    admin = require(path.resolve(__dirname, '../backend/functions/node_modules/firebase-admin'));
  } catch (e) {
    console.error('\n[ERROR] firebase-admin tidak ditemukan. Jalankan "npm install" di backend/functions.');
    process.exit(1);
  }
}

let projectId;
let databaseURL;
let adminInitOptions;

if (mode === 'emulator') {
  const EMULATOR_DB_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
  const EMULATOR_AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  const EMULATOR_NAMESPACE = process.env.FIREBASE_DATABASE_NAMESPACE || 'simetri-app-default-rtdb';

  process.env.FIREBASE_DATABASE_EMULATOR_HOST = EMULATOR_DB_HOST;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = EMULATOR_AUTH_HOST;

  projectId = 'simetri-app';
  databaseURL = `http://${EMULATOR_DB_HOST}?ns=${EMULATOR_NAMESPACE}`;

  adminInitOptions = {
    projectId,
    databaseURL,
  };

  console.log('\n[MODE: EMULATOR]');
  console.log(`  Database Host : ${EMULATOR_DB_HOST}`);
  console.log(`  Auth Host     : ${EMULATOR_AUTH_HOST}`);
} else {
  // Mode Production
  const serviceAccountPath = path.resolve(__dirname, '../serviceAccountKey.json');
  if (!fs.existsSync(serviceAccountPath)) {
    console.error('\n[ERROR] File serviceAccountKey.json tidak ditemukan.');
    console.error(`Lokasi yang dicari: ${serviceAccountPath}`);
    console.error('Unduh private key dari Firebase Console -> Project Settings -> Service accounts.');
    process.exit(1);
  }

  let serviceAccount;
  try {
    serviceAccount = require(serviceAccountPath);
  } catch (err) {
    console.error(`\n[ERROR] Gagal membaca berkas serviceAccountKey.json: ${err.message}`);
    process.exit(1);
  }

  projectId = serviceAccount.project_id;
  if (!projectId || projectId.includes('YOUR_') || projectId.length < 4) {
    console.error(`\n[ERROR] project_id tidak valid pada serviceAccountKey.json: "${projectId}"`);
    process.exit(1);
  }

  const namespace = process.env.FIREBASE_DATABASE_NAMESPACE || `${projectId}-default-rtdb`;
  databaseURL = process.env.FIREBASE_DATABASE_URL || `https://${namespace}.asia-southeast1.firebasedatabase.app`;

  if (!databaseURL.startsWith('https://') || databaseURL.includes('YOUR_')) {
    console.error(`\n[ERROR] databaseURL tidak valid: "${databaseURL}"`);
    console.error('Setel environment variable FIREBASE_DATABASE_URL secara benar.');
    process.exit(1);
  }

  adminInitOptions = {
    credential: admin.credential.cert(serviceAccount),
    databaseURL,
  };

  console.log('\n[MODE: PRODUCTION]');
  console.log(`  Project ID    : ${projectId}`);
  console.log(`  Database URL  : ${databaseURL}`);
  console.log('  PERINGATAN: Perubahan akan langsung memengaruhi database cloud produksi!');
}

if (admin.apps.length === 0) {
  admin.initializeApp(adminInitOptions);
}

const db = admin.database();
const auth = admin.auth();

// ------------------------------------------------------------
// 3. FUNGSI HANDLER PERINTAH ADMIN
// ------------------------------------------------------------

/**
 * Memberikan izin akses aktif ke perangkat untuk UID pengguna tertentu.
 * Menjaga konsistensi ownerUid pada devices/$deviceId/meta.
 */
async function handleGrant(deviceId, userUid, requestedRole, label) {
  if (!deviceId || !userUid) {
    console.error('\n[ERROR] Format grant: grant <deviceId> <userUid> [role] [deviceLabel]');
    process.exit(1);
  }

  const cleanDeviceId = deviceId.trim();
  const cleanUid = userUid.trim();
  let role = (requestedRole || '').trim().toLowerCase();

  console.log('\n============================================================');
  console.log('     SIMETRI ADMIN - PEMBERIAN IZIN AKSES PERANGKAT');
  console.log('============================================================');
  console.log(`Device ID   : ${cleanDeviceId}`);
  console.log(`User UID    : ${cleanUid}`);

  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();

  let metaData = metaSnap.val() || {};
  const currentOwner = metaData.ownerUid;

  // Jika role belum ditentukan, jadikan owner jika belum ada owner, atau member jika sudah ada
  if (!role || (role !== 'owner' && role !== 'member')) {
    role = currentOwner && currentOwner !== cleanUid ? 'member' : 'owner';
  }

  const now = Date.now();

  // Transaksi update meta untuk menjaga konsistensi kepemilikan
  if (role === 'owner') {
    if (currentOwner && currentOwner !== cleanUid) {
      console.log(`[INFO] Pemilik sebelumnya (${currentOwner}) dialihkan ke pengguna baru (${cleanUid}).`);
      // Update izin pemilik lama menjadi member
      await db.ref(`permissions/${currentOwner}/${cleanDeviceId}`).update({
        role: 'member',
        updatedAt: now,
        note: `Ownership transferred to ${cleanUid}`,
      });
    }

    metaData.ownerUid = cleanUid;
    metaData.assignedAt = now;
  }

  metaData.deviceId = cleanDeviceId;
  metaData.deviceUid = metaData.deviceUid || `esp32_${cleanDeviceId}`;
  if (label) metaData.label = label;
  if (!metaData.registeredAt) metaData.registeredAt = now;

  await metaRef.set(metaData);

  // Tulis izin aktif pada path permissions/$uid/$deviceId
  const permRef = db.ref(`permissions/${cleanUid}/${cleanDeviceId}`);
  const permData = {
    status: 'active',
    role: role,
    grantedAt: now,
    grantedBy: 'local_admin',
    deviceId: cleanDeviceId,
  };

  await permRef.set(permData);

  console.log('\n[HASIL] Izin akses BERHASIL diberikan:');
  console.log(`  Path Izin   : permissions/${cleanUid}/${cleanDeviceId}`);
  console.log(`  Status      : active`);
  console.log(`  Peran (Role): ${role}`);
  console.log(`  Owner Aktif : ${metaData.ownerUid}`);
  console.log('\nAplikasi SIMETRI pada ponsel kini dapat memverifikasi izin dan terhubung.');
}

/**
 * Mencabut izin akses perangkat dari pengguna.
 * Jika pengguna adalah pemilik aktif (owner), ownerUid pada meta dikosongkan.
 */
async function handleRevoke(deviceId, userUid) {
  if (!deviceId || !userUid) {
    console.error('\n[ERROR] Format revoke: revoke <deviceId> <userUid>');
    process.exit(1);
  }

  const cleanDeviceId = deviceId.trim();
  const cleanUid = userUid.trim();

  console.log('\n============================================================');
  console.log('     SIMETRI ADMIN - PENCABUTAN IZIN AKSES PERANGKAT');
  console.log('============================================================');
  console.log(`Device ID   : ${cleanDeviceId}`);
  console.log(`User UID    : ${cleanUid}`);

  const now = Date.now();
  const permRef = db.ref(`permissions/${cleanUid}/${cleanDeviceId}`);
  const permSnap = await permRef.get();

  if (!permSnap.exists() || !permSnap.val()) {
    console.log(`[PERINGATAN] Pengguna ${cleanUid} belum pernah memiliki izin pada ${cleanDeviceId}.`);
  }

  await permRef.update({
    status: 'revoked',
    revokedAt: now,
    revokedBy: 'local_admin',
  });

  // Periksa apakah pengguna adalah owner pada meta
  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  if (metaSnap.exists()) {
    const metaData = metaSnap.val();
    if (metaData.ownerUid === cleanUid) {
      console.log(`[INFO] Pengguna ${cleanUid} adalah owner. Menghapus kepemilikan dari meta perangkat.`);
      await metaRef.update({
        ownerUid: null,
        revokedAt: now,
      });
    }
  }

  console.log('\n[HASIL] Izin akses BERHASIL dicabut:');
  console.log(`  Path Izin   : permissions/${cleanUid}/${cleanDeviceId}`);
  console.log(`  Status      : revoked`);
  console.log('Akses pengguna langsung diputus oleh Security Rules Realtime Database.');
}

/**
 * Menampilkan daftar perangkat dan status izin.
 */
async function handleList(targetDeviceId) {
  console.log('\n============================================================');
  console.log('     SIMETRI ADMIN - DAFTAR PERANGKAT & HAK AKSES');
  console.log('============================================================');

  if (targetDeviceId) {
    const cleanDeviceId = targetDeviceId.trim();
    const metaSnap = await db.ref(`devices/${cleanDeviceId}/meta`).get();
    console.log(`\nPerangkat: ${cleanDeviceId}`);
    console.log('Metadata:', JSON.stringify(metaSnap.val() || {}, null, 2));

    // Cari permission untuk deviceId ini di permissions node
    const permRootSnap = await db.ref('permissions').get();
    const permRoot = permRootSnap.val() || {};
    console.log('\nDaftar Izin Pengguna:');
    let count = 0;
    for (const [uid, devMap] of Object.entries(permRoot)) {
      if (devMap && devMap[cleanDeviceId]) {
        count++;
        console.log(`  - UID: ${uid} -> Status: ${devMap[cleanDeviceId].status}, Role: ${devMap[cleanDeviceId].role}`);
      }
    }
    if (count === 0) console.log('  (Belum ada pengguna yang memiliki izin)');
  } else {
    const devicesSnap = await db.ref('devices').get();
    const devices = devicesSnap.val() || {};
    const deviceIds = Object.keys(devices);

    console.log(`Total Perangkat Terdaftar: ${deviceIds.length}`);
    for (const devId of deviceIds) {
      const meta = (devices[devId] && devices[devId].meta) || {};
      console.log(`\n- [${devId}]`);
      console.log(`    Owner UID   : ${meta.ownerUid || '(Belum ada owner)'}`);
      console.log(`    Device UID  : ${meta.deviceUid || 'esp32_' + devId}`);
      console.log(`    Label       : ${meta.label || '-'}`);
    }
  }
}

/**
 * Provision akun autentikasi Firebase Auth khusus ESP32.
 */
async function handleProvisionEsp32(deviceId, label) {
  if (!deviceId) {
    console.error('\n[ERROR] Format: provision-esp32 <deviceId> [label]');
    process.exit(1);
  }

  const cleanDeviceId = deviceId.trim();
  const esp32Uid = `esp32_${cleanDeviceId}`;
  const esp32Email = `device_${cleanDeviceId.toLowerCase()}@simetri.internal`;
  const generatedPassword = `esp_${crypto.randomBytes(12).toString('hex')}`;

  console.log('\n============================================================');
  console.log('     SIMETRI ADMIN - PROVISIONING AKUN ESP32');
  console.log('============================================================');
  console.log(`Device ID   : ${cleanDeviceId}`);
  console.log(`ESP32 UID   : ${esp32Uid}`);
  console.log(`ESP32 Email : ${esp32Email}`);

  let isNew = false;
  try {
    await auth.getUser(esp32Uid);
    console.log('\n[INFO] Akun Firebase Auth untuk ESP32 ini sudah ada sebelumnya.');
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      await auth.createUser({
        uid: esp32Uid,
        email: esp32Email,
        password: generatedPassword,
        displayName: `ESP32 Device ${cleanDeviceId}`,
      });
      isNew = true;
      console.log('\n[SUKSES] Akun Firebase Auth baru berhasil dibuat!');
      console.log(`  Password Sementara : ${generatedPassword}`);
      console.log('  CATATAN: Masukkan email dan password ini ke secrets.h firmware ESP32.');
    } else {
      throw err;
    }
  }

  // Daftarkan metadata di RTDB
  const now = Date.now();
  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  const existingMeta = metaSnap.val() || {};

  await metaRef.set({
    ...existingMeta,
    deviceId: cleanDeviceId,
    deviceUid: esp32Uid,
    registeredAt: existingMeta.registeredAt || now,
    label: label || existingMeta.label || `Perangkat ${cleanDeviceId}`,
  });

  console.log(`  Metadata RTDB      : devices/${cleanDeviceId}/meta tersimpan.`);
}

// ------------------------------------------------------------
// 4. ROUTER UTAMA EKSEKUSI
// ------------------------------------------------------------
async function main() {
  try {
    switch (command) {
      case 'grant':
        await handleGrant(positionalArgs[1], positionalArgs[2], positionalArgs[3], positionalArgs[4]);
        break;
      case 'revoke':
        await handleRevoke(positionalArgs[1], positionalArgs[2]);
        break;
      case 'list':
        await handleList(positionalArgs[1]);
        break;
      case 'provision-esp32':
        await handleProvisionEsp32(positionalArgs[1], positionalArgs[2]);
        break;
      default:
        console.error(`\n[ERROR] Perintah "${command}" tidak dikenali.`);
        console.error('Gunakan salah satu dari: grant, revoke, list, provision-esp32');
        process.exit(1);
    }
    process.exit(0);
  } catch (err) {
    console.error('\n[FATAL ERROR] Eksekusi admin gagal:', err);
    process.exit(1);
  }
}

main();
