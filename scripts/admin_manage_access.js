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
 *   grant-owner <deviceId> <userUid> [deviceLabel]
 *       Menetapkan pemilik pertama perangkat. Menolak menimpa pemilik yang sudah ada.
 *
 *   add-member <deviceId> <userUid>
 *       Menambahkan akses anggota tanpa mengubah pemilik perangkat.
 *
 *   transfer-owner <deviceId> <newUserUid> <oldUserUid>
 *       Memindahkan kepemilikan perangkat dari pemilik lama ke pemilik baru secara sah.
 *
 *   recover <deviceId> <newUserUid> [oldUserUidToRevoke]
 *       Pemulihan akses darurat (misal ponsel lama hilang/rusak).
 *       Mencabut izin UID lama secara eksplisit jika dicantumkan.
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
 *   - Menolak target produksi yang tidak cocok dengan simentri-b1a4a sebelum penulisan.
 * ============================================================================
 */

const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// ------------------------------------------------------------
// KONSTANTA TARGET RESMI PRODUKSI
// ------------------------------------------------------------
const OFFICIAL_PRODUCTION_PROJECT_ID = 'simentri-b1a4a';
const OFFICIAL_PRODUCTION_RTDB_URL = 'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app';

/**
 * Memvalidasi apakah target project dan database URL sesuai dengan target resmi produksi.
 * Mencegah kesalahan ketik atau salah credential sebelum terjadi penulisan apa pun.
 */
function validateProductionTarget(targetProjectId, targetDatabaseUrl) {
  if (targetProjectId !== OFFICIAL_PRODUCTION_PROJECT_ID) {
    throw new Error(
      `[SECURITY ERROR] Target Project ID "${targetProjectId}" tidak valid untuk mode produksi. ` +
      `Target produksi resmi SIMETRI WAJIB "${OFFICIAL_PRODUCTION_PROJECT_ID}". Operasi dibatalkan sebelum penulisan.`
    );
  }

  const normalizedUrl = (targetDatabaseUrl || '').replace(/\/$/, '');
  if (normalizedUrl !== OFFICIAL_PRODUCTION_RTDB_URL) {
    throw new Error(
      `[SECURITY ERROR] Target Database URL "${targetDatabaseUrl}" tidak valid untuk mode produksi. ` +
      `Target produksi resmi SIMETRI WAJIB "${OFFICIAL_PRODUCTION_RTDB_URL}". Operasi dibatalkan sebelum penulisan.`
    );
  }
}

// ------------------------------------------------------------
// 1. PARSE & VALIDASI ARGUMEN CLI
// ------------------------------------------------------------
const rawArgs = process.argv.slice(2);
const modeArg = rawArgs.find(arg => arg.startsWith('--mode='));

// ------------------------------------------------------------
// FUNGSI INTI LOGIKA IZIN & KEPEMILIKAN (Reusable & Testable)
// ------------------------------------------------------------

/**
 * Menetapkan pemilik awal (initial owner) perangkat.
 * Menolak jika perangkat sudah memiliki owner yang berbeda.
 */
async function applyGrantOwner(db, deviceId, userUid, label) {
  const cleanDeviceId = deviceId.trim();
  const cleanUid = userUid.trim();

  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  const metaData = metaSnap.val() || {};
  const currentOwner = metaData.ownerUid;

  if (currentOwner && currentOwner !== cleanUid) {
    throw new Error(
      `Perangkat "${cleanDeviceId}" sudah memiliki pemilik ("${currentOwner}"). ` +
      `Grant biasa tidak boleh memindahkan pemilik secara diam-diam. ` +
      `Gunakan "transfer-owner" atau "recover".`
    );
  }

  const now = Date.now();
  metaData.deviceId = cleanDeviceId;
  metaData.deviceUid = metaData.deviceUid || `esp32_${cleanDeviceId}`;
  metaData.ownerUid = cleanUid;
  metaData.assignedAt = now;
  if (label) metaData.label = label;
  if (!metaData.registeredAt) metaData.registeredAt = now;

  await metaRef.set(metaData);

  const permRef = db.ref(`permissions/${cleanUid}/${cleanDeviceId}`);
  await permRef.set({
    status: 'active',
    role: 'owner',
    grantedAt: now,
    grantedBy: 'local_admin',
    deviceId: cleanDeviceId,
  });

  return { metaData, ownerUid: cleanUid };
}

/**
 * Menambahkan akses anggota (member) ke perangkat tanpa mengubah ownerUid.
 */
async function applyAddMember(db, deviceId, userUid) {
  const cleanDeviceId = deviceId.trim();
  const cleanUid = userUid.trim();

  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  const metaData = metaSnap.val() || {};

  const now = Date.now();
  metaData.deviceId = cleanDeviceId;
  metaData.deviceUid = metaData.deviceUid || `esp32_${cleanDeviceId}`;
  if (!metaData.registeredAt) metaData.registeredAt = now;
  // ownerUid TIDAK diubah
  await metaRef.set(metaData);

  const permRef = db.ref(`permissions/${cleanUid}/${cleanDeviceId}`);
  await permRef.set({
    status: 'active',
    role: 'member',
    grantedAt: now,
    grantedBy: 'local_admin',
    deviceId: cleanDeviceId,
  });

  return { metaData, ownerUid: metaData.ownerUid || null };
}

/**
 * Memindahkan kepemilikan perangkat secara sah dari oldUserUid ke newUserUid.
 */
async function applyTransferOwner(db, deviceId, newUserUid, oldUserUid) {
  const cleanDeviceId = deviceId.trim();
  const cleanNewUid = newUserUid.trim();
  const cleanOldUid = oldUserUid.trim();

  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  const metaData = metaSnap.val() || {};
  const currentOwner = metaData.ownerUid;

  if (currentOwner !== cleanOldUid) {
    throw new Error(
      `Verifikasi pemilik lama gagal. Pemilik perangkat saat ini adalah "${currentOwner || 'KOSONG'}", bukan "${cleanOldUid}".`
    );
  }

  const now = Date.now();
  metaData.ownerUid = cleanNewUid;
  metaData.assignedAt = now;
  await metaRef.set(metaData);

  // Izin owner baru -> active, owner
  await db.ref(`permissions/${cleanNewUid}/${cleanDeviceId}`).set({
    status: 'active',
    role: 'owner',
    grantedAt: now,
    grantedBy: 'local_admin',
    deviceId: cleanDeviceId,
  });

  // Izin owner lama -> active, member (diturunkan ke anggota biasa)
  await db.ref(`permissions/${cleanOldUid}/${cleanDeviceId}`).update({
    role: 'member',
    updatedAt: now,
    note: `Ownership transferred to ${cleanNewUid}`,
  });

  return { newOwner: cleanNewUid, oldOwner: cleanOldUid };
}

/**
 * Pemulihan akses darurat (misal ponsel lama hilang/rusak).
 * Menetapkan newUserUid sebagai owner, dan mencabut izin oldUserUidToRevoke secara eksplisit jika dicantumkan.
 */
async function applyRecover(db, deviceId, newUserUid, oldUserUidToRevoke) {
  const cleanDeviceId = deviceId.trim();
  const cleanNewUid = newUserUid.trim();
  const cleanOldUid = oldUserUidToRevoke ? oldUserUidToRevoke.trim() : null;

  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  const metaData = metaSnap.val() || {};
  const previousOwner = metaData.ownerUid;

  const now = Date.now();
  metaData.deviceId = cleanDeviceId;
  metaData.deviceUid = metaData.deviceUid || `esp32_${cleanDeviceId}`;
  metaData.ownerUid = cleanNewUid;
  metaData.recoveredAt = now;
  if (!metaData.registeredAt) metaData.registeredAt = now;

  await metaRef.set(metaData);

  // Berikan izin owner aktif pada UID baru
  await db.ref(`permissions/${cleanNewUid}/${cleanDeviceId}`).set({
    status: 'active',
    role: 'owner',
    grantedAt: now,
    grantedBy: 'local_admin_recovery',
    deviceId: cleanDeviceId,
  });

  // Jika UID lama dicantumkan, cabut secara eksplisit
  if (cleanOldUid) {
    await db.ref(`permissions/${cleanOldUid}/${cleanDeviceId}`).update({
      status: 'revoked',
      revokedAt: now,
      revokedBy: 'local_admin_recovery',
      note: `Explicitly revoked during access recovery to ${cleanNewUid}`,
    });
  }

  return { newOwner: cleanNewUid, previousOwner, revokedOldUid: cleanOldUid };
}

/**
 * Mencabut izin akses perangkat dari pengguna.
 * Jika pengguna adalah pemilik aktif (owner), ownerUid pada meta dikosongkan.
 */
async function applyRevoke(db, deviceId, userUid) {
  const cleanDeviceId = deviceId.trim();
  const cleanUid = userUid.trim();

  const now = Date.now();
  const permRef = db.ref(`permissions/${cleanUid}/${cleanDeviceId}`);

  await permRef.update({
    status: 'revoked',
    revokedAt: now,
    revokedBy: 'local_admin',
  });

  // Periksa apakah pengguna adalah owner pada meta
  let wasOwner = false;
  const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
  const metaSnap = await metaRef.get();
  if (metaSnap.exists()) {
    const metaData = metaSnap.val();
    if (metaData.ownerUid === cleanUid) {
      wasOwner = true;
      await metaRef.update({
        ownerUid: null,
        revokedAt: now,
      });
    }
  }

  return { revokedUid: cleanUid, wasOwner };
}

// Ekspor untuk keperluan testing terisolasi jika di-require sebagai modul
if (require.main !== module) {
  module.exports = {
    OFFICIAL_PRODUCTION_PROJECT_ID,
    OFFICIAL_PRODUCTION_RTDB_URL,
    validateProductionTarget,
    applyGrantOwner,
    applyAddMember,
    applyTransferOwner,
    applyRecover,
    applyRevoke,
  };
}

if (require.main === module) {
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

  const AVAILABLE_COMMANDS = [
    'grant-owner',
    'add-member',
    'transfer-owner',
    'recover',
    'revoke',
    'list',
    'provision-esp32',
    'grant', // Backward compatibility
  ];

  if (!command || !AVAILABLE_COMMANDS.includes(command)) {
    console.error('\n[ERROR] Perintah tidak valid atau belum ditentukan.');
    console.error(`Perintah yang tersedia: ${AVAILABLE_COMMANDS.join(', ')}`);
    console.error('\nContoh:');
    console.error('  node scripts/admin_manage_access.js --mode=emulator grant-owner SIMETRI_ESP32_001 <userUid>');
    console.error('  node scripts/admin_manage_access.js --mode=emulator add-member SIMETRI_ESP32_001 <userUid>');
    console.error('  node scripts/admin_manage_access.js --mode=emulator transfer-owner SIMETRI_ESP32_001 <newUserUid> <oldUserUid>');
    console.error('  node scripts/admin_manage_access.js --mode=emulator recover SIMETRI_ESP32_001 <newUserUid> [oldUserUidToRevoke]');
    console.error('  node scripts/admin_manage_access.js --mode=emulator revoke SIMETRI_ESP32_001 <userUid>');
    console.error('  node scripts/admin_manage_access.js --mode=emulator list [deviceId]');
    console.error('  node scripts/admin_manage_access.js --mode=emulator provision-esp32 SIMETRI_ESP32_001 [label]');
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
    // Mode Production: Validasi ketat target produksi sebelum inisialisasi
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
    const namespace = process.env.FIREBASE_DATABASE_NAMESPACE || `${projectId}-default-rtdb`;
    databaseURL = process.env.FIREBASE_DATABASE_URL || `https://${namespace}.asia-southeast1.firebasedatabase.app`;

    try {
      validateProductionTarget(projectId, databaseURL);
    } catch (validationErr) {
      console.error(`\n${validationErr.message}`);
      process.exit(1);
    }

    adminInitOptions = {
      credential: admin.credential.cert(serviceAccount),
      databaseURL,
    };

    console.log('\n[MODE: PRODUCTION]');
    console.log(`  Project ID    : ${projectId} (VALIDATED)`);
    console.log(`  Database URL  : ${databaseURL} (VALIDATED)`);
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

  async function handleGrantOwner(deviceId, userUid, label) {
    if (!deviceId || !userUid) {
      console.error('\n[ERROR] Format grant-owner: grant-owner <deviceId> <userUid> [deviceLabel]');
      process.exit(1);
    }
    const cleanDeviceId = deviceId.trim();
    const cleanUid = userUid.trim();

    console.log('\n============================================================');
    console.log('     SIMETRI ADMIN - PENETAPAN PEMILIK (GRANT OWNER)');
    console.log('============================================================');
    console.log(`Device ID   : ${cleanDeviceId}`);
    console.log(`User UID    : ${cleanUid}`);

    try {
      const res = await applyGrantOwner(db, cleanDeviceId, cleanUid, label);
      console.log('\n[HASIL] Pemilik berhasil ditetapkan:');
      console.log(`  Path Izin   : permissions/${cleanUid}/${cleanDeviceId}`);
      console.log(`  Status      : active`);
      console.log(`  Peran (Role): owner`);
      console.log(`  Owner Aktif : ${res.ownerUid}`);
    } catch (err) {
      console.error(`\n[PENOLAKAN] ${err.message}`);
      process.exit(1);
    }
  }

  async function handleAddMember(deviceId, userUid) {
    if (!deviceId || !userUid) {
      console.error('\n[ERROR] Format add-member: add-member <deviceId> <userUid>');
      process.exit(1);
    }
    const cleanDeviceId = deviceId.trim();
    const cleanUid = userUid.trim();

    console.log('\n============================================================');
    console.log('     SIMETRI ADMIN - TAMBAH ANGGOTA (ADD MEMBER)');
    console.log('============================================================');
    console.log(`Device ID   : ${cleanDeviceId}`);
    console.log(`User UID    : ${cleanUid}`);

    try {
      const res = await applyAddMember(db, cleanDeviceId, cleanUid);
      console.log('\n[HASIL] Anggota berhasil ditambahkan:');
      console.log(`  Path Izin   : permissions/${cleanUid}/${cleanDeviceId}`);
      console.log(`  Status      : active`);
      console.log(`  Peran (Role): member`);
      console.log(`  Owner Tetap : ${res.ownerUid || '(Belum ada owner)'}`);
    } catch (err) {
      console.error(`\n[PENOLAKAN] ${err.message}`);
      process.exit(1);
    }
  }

  async function handleTransferOwner(deviceId, newUserUid, oldUserUid) {
    if (!deviceId || !newUserUid || !oldUserUid) {
      console.error('\n[ERROR] Format transfer-owner: transfer-owner <deviceId> <newUserUid> <oldUserUid>');
      process.exit(1);
    }
    const cleanDeviceId = deviceId.trim();
    const cleanNewUid = newUserUid.trim();
    const cleanOldUid = oldUserUid.trim();

    console.log('\n============================================================');
    console.log('     SIMETRI ADMIN - TRANSFER KEPEMILIKAN (TRANSFER OWNER)');
    console.log('============================================================');
    console.log(`Device ID   : ${cleanDeviceId}`);
    console.log(`Owner Baru  : ${cleanNewUid}`);
    console.log(`Owner Lama  : ${cleanOldUid}`);

    try {
      const res = await applyTransferOwner(db, cleanDeviceId, cleanNewUid, cleanOldUid);
      console.log('\n[HASIL] Kepemilikan berhasil ditransfer:');
      console.log(`  Owner Baru  : ${res.newOwner} (role: owner)`);
      console.log(`  Owner Lama  : ${res.oldOwner} (role: member)`);
    } catch (err) {
      console.error(`\n[PENOLAKAN] ${err.message}`);
      process.exit(1);
    }
  }

  async function handleRecover(deviceId, newUserUid, oldUserUidToRevoke) {
    if (!deviceId || !newUserUid) {
      console.error('\n[ERROR] Format recover: recover <deviceId> <newUserUid> [oldUserUidToRevoke]');
      process.exit(1);
    }
    const cleanDeviceId = deviceId.trim();
    const cleanNewUid = newUserUid.trim();
    const cleanOldUid = oldUserUidToRevoke ? oldUserUidToRevoke.trim() : null;

    console.log('\n============================================================');
    console.log('     SIMETRI ADMIN - PEMULIHAN AKSES (RECOVERY)');
    console.log('============================================================');
    console.log(`Device ID      : ${cleanDeviceId}`);
    console.log(`UID Pemulihan  : ${cleanNewUid}`);
    if (cleanOldUid) {
      console.log(`UID Dicabut    : ${cleanOldUid}`);
    }

    try {
      const res = await applyRecover(db, cleanDeviceId, cleanNewUid, cleanOldUid);
      console.log('\n[HASIL] Pemulihan akses berhasil:');
      console.log(`  Owner Aktif : ${res.newOwner} (status: active, role: owner)`);
      if (res.revokedOldUid) {
        console.log(`  UID Dicabut : ${res.revokedOldUid} (status: revoked)`);
      } else if (res.previousOwner && res.previousOwner !== cleanNewUid) {
        console.log(`  [CATATAN] Pemilik sebelumnya (${res.previousOwner}) belum dicabut izinnya karena oldUserUidToRevoke tidak diisi.`);
        console.log(`  Jalankan "revoke ${cleanDeviceId} ${res.previousOwner}" jika ingin mencabutnya sepenuhnya.`);
      }
    } catch (err) {
      console.error(`\n[PENOLAKAN] ${err.message}`);
      process.exit(1);
    }
  }

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

    try {
      const res = await applyRevoke(db, cleanDeviceId, cleanUid);
      console.log('\n[HASIL] Izin akses BERHASIL dicabut:');
      console.log(`  Path Izin   : permissions/${cleanUid}/${cleanDeviceId}`);
      console.log(`  Status      : revoked`);
      if (res.wasOwner) {
        console.log(`  Meta Owner  : ownerUid dikosongkan (null)`);
      }
      console.log('Akses pengguna langsung diputus oleh Security Rules Realtime Database.');
    } catch (err) {
      console.error(`\n[PENOLAKAN] ${err.message}`);
      process.exit(1);
    }
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
   * Kredensial disimpan langsung ke file lokal yang diabaikan Git (.env.* & secrets.h),
   * tanpa mengekspos kata sandi secara sembarangan di konsol.
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
    if (label) {
      console.log(`Label       : ${label}`);
    }

    let isNewAccount = false;
    try {
      await auth.getUser(esp32Uid);
      console.log('\n[INFO] Akun Firebase Auth untuk ESP32 ini sudah terdaftar sebelumnya.');
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        await auth.createUser({
          uid: esp32Uid,
          email: esp32Email,
          password: generatedPassword,
          displayName: `ESP32 Device ${cleanDeviceId}`,
        });
        isNewAccount = true;
        console.log('\n[SUKSES] Akun Firebase Auth baru berhasil dibuat!');
      } else {
        throw err;
      }
    }

    const now = Date.now();
    const metaRef = db.ref(`devices/${cleanDeviceId}/meta`);
    const metaSnap = await metaRef.get();
    const existingMeta = metaSnap.val() || {};

    const updatedMeta = {
      ...existingMeta,
      deviceId: cleanDeviceId,
      deviceUid: esp32Uid,
      registeredAt: existingMeta.registeredAt || now,
      label: label || existingMeta.label || `Perangkat ${cleanDeviceId}`,
    };

    await metaRef.set(updatedMeta);
    console.log(`[SUKSES] Metadata RTDB tersimpan pada: devices/${cleanDeviceId}/meta`);

    // Simpan kredensial ke file lokal yang diabaikan Git jika akun baru dibuat
    if (isNewAccount) {
      const localEnvPath = path.resolve(__dirname, `../.env.${cleanDeviceId.toLowerCase()}.local`);
      const envContent = [
        `# Kredensial Perangkat SIMETRI (DIABAIKAN OLEH GIT VIA .gitignore)`,
        `DEVICE_ID="${cleanDeviceId}"`,
        `DEVICE_UID="${esp32Uid}"`,
        `DEVICE_EMAIL="${esp32Email}"`,
        `DEVICE_PASSWORD="${generatedPassword}"`,
        `PROVISIONED_AT="${new Date(now).toISOString()}"`,
        `LABEL="${updatedMeta.label}"`,
        ``,
      ].join('\n');
      fs.writeFileSync(localEnvPath, envContent, { mode: 0o600 });

      // Perbarui firmware secrets.h lokal jika berkas ada
      const secretsHPath = path.resolve(__dirname, '../firmware_iot/simetri_firebase_integrated/secrets.h');
      if (fs.existsSync(secretsHPath)) {
        let secretsContent = fs.readFileSync(secretsHPath, 'utf8');
        secretsContent = secretsContent.replace(/#define DEVICE_ID\s+".*"/, `#define DEVICE_ID                "${cleanDeviceId}"`);
        secretsContent = secretsContent.replace(/#define DEVICE_EMAIL\s+".*"/, `#define DEVICE_EMAIL             "${esp32Email}"`);
        secretsContent = secretsContent.replace(/#define DEVICE_PASSWORD\s+".*"/, `#define DEVICE_PASSWORD          "${generatedPassword}"`);
        fs.writeFileSync(secretsHPath, secretsContent);
      }

      console.log(`[KEAMANAN] Kredensial perangkat tersimpan ke berkas lokal yang diabaikan Git:`);
      console.log(`  - ${localEnvPath}`);
      console.log(`  - ${secretsHPath}`);
      console.log('Nilai rahasia (password/token) tidak ditampilkan di layar konsol demi keamanan.');
    }
  }

  /**
   * Wrapper kompatibilitas mundur untuk 'grant'
   */
  async function handleGrantCompat(deviceId, userUid, requestedRole, label) {
    const role = (requestedRole || '').trim().toLowerCase();
    if (role === 'member') {
      await handleAddMember(deviceId, userUid);
    } else {
      await handleGrantOwner(deviceId, userUid, label);
    }
  }

  // ------------------------------------------------------------
  // 4. ROUTER UTAMA EKSEKUSI
  // ------------------------------------------------------------
  async function main() {
    try {
      switch (command) {
        case 'grant-owner':
          await handleGrantOwner(positionalArgs[1], positionalArgs[2], positionalArgs[3]);
          break;
        case 'add-member':
          await handleAddMember(positionalArgs[1], positionalArgs[2]);
          break;
        case 'transfer-owner':
          await handleTransferOwner(positionalArgs[1], positionalArgs[2], positionalArgs[3]);
          break;
        case 'recover':
          await handleRecover(positionalArgs[1], positionalArgs[2], positionalArgs[3]);
          break;
        case 'grant':
          await handleGrantCompat(positionalArgs[1], positionalArgs[2], positionalArgs[3], positionalArgs[4]);
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
          process.exit(1);
      }
      process.exit(0);
    } catch (err) {
      console.error('\n[FATAL ERROR] Eksekusi admin gagal:', err);
      process.exit(1);
    }
  }

  main();
}

