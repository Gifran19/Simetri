// ============================================================
//  SIMETRI Firebase Integrated Firmware
//  File: firmware_iot/simetri_firebase_integrated/secrets.example.h
//
//  PETUNJUK:
//  1. Salin file ini menjadi "secrets.h":
//       cp secrets.example.h secrets.h
//  2. Isi semua nilai YOUR_* dengan data asli.
//  3. JANGAN commit secrets.h ke repository.
//     File tersebut sudah dikecualikan via .gitignore.
//
//  Cara mendapatkan nilai-nilai ini:
//  - WIFI_SSID / WIFI_PASSWORD   : pengaturan WiFi router Anda
//  - DEVICE_ID                   : ID yang digunakan saat mendaftarkan
//                                  perangkat via scripts/register_device.js
//  - FIREBASE_HOST               : format: <project>.firebaseio.com
//  - FIREBASE_PROJECT_ID         : dari Firebase Console > Project Settings
//  - DEVICE_EMAIL / DEVICE_PASS  : dari output scripts/register_device.js
//                                  (ditampilkan SATU KALI saat akun baru dibuat)
//  - FIREBASE_API_KEY            : dari Firebase Console > Project Settings > Web API Key
//
//  UNTUK PENGUJIAN EMULATOR:
//  - Ubah FIREBASE_HOST menjadi IP komputer pengembang, port 9000
//  - Ubah FIREBASE_API_KEY menjadi "fake-emulator-key"
//  - Lihat panduan pengujian di README_FIRMWARE.md
// ============================================================

#pragma once

// ------ WiFi -----------------------------------------------
#define WIFI_SSID        "YOUR_WIFI_SSID"
#define WIFI_PASSWORD    "YOUR_WIFI_PASSWORD"

// ------ Identitas Perangkat --------------------------------
// Device ID harus sama persis dengan yang didaftarkan di backend
#define DEVICE_ID        "YOUR_DEVICE_ID"

// ------ Firebase REST API ----------------------------------
// HTTPS host tanpa "https://" dan tanpa trailing "/"
// Production: <project-id>-default-rtdb.asia-southeast1.firebasedatabase.app
// Emulator  : 192.168.x.x:9000  (IP komputer pengembang di jaringan yang sama)
#define FIREBASE_HOST    "YOUR_FIREBASE_HOST"

// Project ID Firebase (bukan nama tampilan, tapi ID proyek)
#define FIREBASE_PROJECT_ID  "YOUR_FIREBASE_PROJECT_ID"

// Firebase Web API Key (untuk REST Auth)
#define FIREBASE_API_KEY "YOUR_FIREBASE_API_KEY"

// ------ Akun Firebase Auth khusus ESP32 --------------------
// Email dan password diperoleh dari output scripts/register_device.js
// Format email: device_<deviceid_lowercase>@simetri.internal
#define DEVICE_EMAIL     "YOUR_DEVICE_EMAIL"
#define DEVICE_PASSWORD  "YOUR_DEVICE_PASSWORD"

// ------ Mode Relay (pengujian awal) ------------------------
// false = relay tidak digerakkan; perintah dicatat tapi diabaikan
// true  = relay diizinkan bergerak sesuai perintah dari Firebase
#define ENABLE_RELAY_CONTROL false
