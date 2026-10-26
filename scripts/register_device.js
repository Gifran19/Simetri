#!/usr/bin/env node

/**
 * SIMETRI Local Admin Script
 * Mendaftarkan perangkat baru dan menerbitkan kode pairing sementara.
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
if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
  process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';
}

const serviceAccountPath = path.resolve(__dirname, '../serviceAccountKey.json');
if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=simetri-app`
  });
} else {
  // Mode Emulator / default application credential
  admin.initializeApp({
    projectId: 'simetri-app',
    databaseURL: `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST}?ns=simetri-app`
  });
}

const db = admin.database();

/**
 * Menghasilkan kode pairing acak kriptografis (8 karakter alfanumerik)
 */
function generateSecurePairingCode() {
  const bytes = crypto.randomBytes(4);
  return bytes.toString('hex').toUpperCase();
}

async function registerDeviceAndIssueCode() {
  console.log('====================================================');
  console.log('       SIMETRI LOCAL ADMIN - DEVICE REGISTRATION    ');
  console.log('====================================================');
  console.log(`Emulator Host      : ${process.env.FIREBASE_DATABASE_EMULATOR_HOST}`);
  console.log(`Device ID          : ${deviceId}`);
  console.log(`Device Label       : ${label}`);
  console.log(`Masa Berlaku       : ${expiresInMinutes} menit`);

  const pairingCode = generateSecurePairingCode();
  const sha256Hash = crypto.createHash('sha256').update(pairingCode).digest('hex');
  const now = Date.now();
  const expiresAt = now + expiresInMinutes * 60 * 1000;

  console.log(`Generated Code     : ${pairingCode} (RAHASIA SEMENTARA)`);
  console.log(`SHA-256 Hash       : ${sha256Hash}`);
  console.log(`Expires At         : ${new Date(expiresAt).toISOString()}`);

  try {
    const multiPathUpdates = {};

    // 1. Periksa apakah perangkat sudah pernah didaftarkan sebelumnya
    const metaRef = db.ref(`devices/${deviceId}/meta`);
    const existingMetaSnap = await metaRef.get();
    const existingMeta = existingMetaSnap.val() || {};

    // 2. Jika ada kode aktif sebelumnya untuk perangkat ini, cabut kode lama
    if (existingMeta.activePairingHash && existingMeta.activePairingHash !== sha256Hash) {
      console.log(`Mencabut kode pairing sebelumnya: ${existingMeta.activePairingHash}`);
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/status`] = 'revoked';
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedAt`] = now;
      multiPathUpdates[`pairing_secrets/${existingMeta.activePairingHash}/revokedReason`] = 'superseded_by_new_code';
    }

    // 3. Simpan atau perbarui metadata perangkat
    // PENTING: Pendaftaran ulang tidak boleh mengosongkan pemilik yang sudah ada!
    multiPathUpdates[`devices/${deviceId}/meta`] = {
      deviceId: deviceId,
      label: label,
      registeredAt: existingMeta.registeredAt || now,
      registeredBy: 'admin_local_script',
      ownerUid: existingMeta.ownerUid || null, // Pertahankan pemilik yang sudah ada!
      claimedAt: existingMeta.claimedAt || null,
      activePairingHash: sha256Hash,
      deviceUid: existingMeta.deviceUid || deviceId,
    };

    // 4. Simpan rahasia pairing baru (hanya hash, BUKAN kode asli)
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
      console.log(`Info: Perangkat ini saat ini dimiliki oleh UID: ${existingMeta.ownerUid}`);
    }
    console.log(`Berikan kode ini kepada pengguna: ${pairingCode}`);
    console.log('Kode hanya dapat digunakan SATU KALI sebelum kedaluwarsa.');
    console.log('====================================================');
    process.exit(0);
  } catch (error) {
    console.error('✗ Gagal mendaftarkan perangkat:', error);
    process.exit(1);
  }
}

registerDeviceAndIssueCode();
