#!/usr/bin/env node

/**
 * SIMETRI Local Admin Script
 * Mendaftarkan perangkat baru, menerbitkan kode pairing sementara,
 * dan mem-provision identitas Firebase Auth khusus untuk perangkat ESP32.
 * 
 * Penggunaan:
 *   node scripts/register_device.js <deviceId> [expiresInMinutes] [deviceLabel]
 * 
 * Contoh:
 *   node scripts/register_device.js SIMETRI_ESP32_001 60 "Kwh Meter Ruang Utama"
 */

const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

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

// Cek argumen CLI
const args = process.argv.slice(2);
const deviceId = args[0] || 'SIMETRI_ESP32_001';
const expiresInMinutes = parseInt(args[1], 10) || 60; // default 60 menit
const label = args[2] || `Perangkat ${deviceId}`;

// Inisialisasi Firebase Admin
const databaseNamespace = process.env.FIREBASE_DATABASE_NAMESPACE || 'simetri-app-default-rtdb';
if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
  process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';
}
if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
}

const serviceAccountPath = path.resolve(__dirname, '../serviceAccountKey.json');
if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=${databaseNamespace}`
  });
} else {
  // Mode Emulator / default application credential
  admin.initializeApp({
    projectId: 'simetri-app',
    databaseURL: `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=${databaseNamespace}`
  });
}

const db = admin.database();
const auth = admin.auth();

function generateSecurePairingCode() {
  const bytes = crypto.randomBytes(4);
  return bytes.toString('hex').toUpperCase(); // 8 karakter alfanumerik
}

async function provisionEsp32AuthIdentity(targetDeviceId) {
  const esp32Uid = `esp32_${targetDeviceId}`;
  const esp32Email = `device_${targetDeviceId.toLowerCase()}@simetri.internal`;
  const defaultPassword = `esp_${crypto.randomBytes(12).toString('hex')}`;

  let userRecord;
  let isNew = false;
  try {
    userRecord = await auth.getUser(esp32Uid);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      userRecord = await auth.createUser({
        uid: esp32Uid,
        email: esp32Email,
        password: defaultPassword,
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
    password: isNew ? defaultPassword : '(tetap seperti konfigurasi sebelumnya)',
    isNew,
  };
}

async function registerDeviceAndIssueCode() {
  console.log('====================================================');
  console.log('       SIMETRI LOCAL ADMIN - DEVICE REGISTRATION    ');
  console.log('====================================================');
  console.log(`Database Host      : ${process.env.FIREBASE_DATABASE_EMULATOR_HOST}`);
  console.log(`Auth Host          : ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`);
  console.log(`Database Namespace : ${databaseNamespace}`);
  console.log(`Device ID          : ${deviceId}`);
  console.log(`Device Label       : ${label}`);
  console.log(`Masa Berlaku       : ${expiresInMinutes} menit`);

  try {
    // 1. Provisioning Identitas Firebase Auth Asli untuk ESP32
    const deviceAuth = await provisionEsp32AuthIdentity(deviceId);
    console.log('----------------------------------------------------');
    console.log('Identitas Kredensial Firebase Auth ESP32:');
    console.log(`- Device UID   : ${deviceAuth.uid}`);
    console.log(`- Device Email : ${deviceAuth.email}`);
    console.log(`- Password     : ${deviceAuth.password}`);
    console.log('Catatan: Firmware ESP32 login via Firebase Auth REST API.');
    console.log('TIDAK MEMERLUKAN database secret atau service account!');
    console.log('----------------------------------------------------');

    const pairingCode = generateSecurePairingCode();
    const sha256Hash = crypto.createHash('sha256').update(pairingCode).digest('hex');
    const now = Date.now();
    const expiresAt = now + expiresInMinutes * 60 * 1000;

    console.log(`Generated Code     : ${pairingCode} (RAHASIA SEMENTARA)`);
    console.log(`SHA-256 Hash       : ${sha256Hash}`);
    console.log(`Expires At         : ${new Date(expiresAt).toISOString()}`);

    const multiPathUpdates = {};

    // 2. Baca metadata perangkat yang sudah ada
    const metaRef = db.ref(`devices/${deviceId}/meta`);
    const existingMetaSnap = await metaRef.get();
    const existingMeta = existingMetaSnap.val() || {};

    // 3. Cabut kode lama jika ada
    if (existingMeta.activePairingHash && existingMeta.activePairingHash !== sha256Hash) {
      console.log(`Mencabut kode pairing lama (Hash: ${existingMeta.activePairingHash.substring(0, 10)}...)`);
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/status`] = 'revoked';
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedAt`] = now;
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedReason`] = 'superseded_by_new_code';
    }

    // 4. Pendaftaran ulang: PERTAHANKAN PEMILIK YANG SUDAH ADA!
    multiPathUpdates[`devices/${deviceId}/meta`] = {
      deviceId: deviceId,
      label: label,
      registeredAt: existingMeta.registeredAt || now,
      registeredBy: 'admin_local_script',
      ownerUid: existingMeta.ownerUid || null, // Jangan kosongkan pemilik!
      claimOpId: existingMeta.claimOpId || null,
      claimedAt: existingMeta.claimedAt || null,
      activePairingHash: sha256Hash,
      deviceUid: deviceAuth.uid,
    };

    // 5. Simpan rahasia pairing baru
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
      console.log(`[INFO] Perangkat ini saat ini dimiliki oleh UID: ${existingMeta.ownerUid}`);
    }
    console.log(`Berikan kode ini kepada pengguna: ${pairingCode}`);
    console.log('====================================================');
    process.exit(0);
  } catch (error) {
    console.error('✗ Gagal mendaftarkan perangkat:', error);
    process.exit(1);
  }
}

registerDeviceAndIssueCode();
