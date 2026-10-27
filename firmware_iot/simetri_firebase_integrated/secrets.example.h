// ============================================================
//  SIMETRI Firebase Integrated Firmware
//  File: firmware_iot/simetri_firebase_integrated/secrets.example.h
//
//  PETUNJUK PENGGUNAAN:
//  1. Salin file ini menjadi "secrets.h":
//       cp secrets.example.h secrets.h
//  2. Konfigurasikan mode operasi:
//       #define USE_FIREBASE_EMULATOR  true   // untuk pengujian lokal dengan emulator
//       #define USE_FIREBASE_EMULATOR  false  // untuk koneksi ke Firebase Cloud asli
//  3. JANGAN PERNAH commit file "secrets.h" ke repository Git.
//     File tersebut sudah dikecualikan melalui .gitignore.
//
//  PANDUAN MODE EMULATOR:
//  - Host adalah IP komputer pengembang di jaringan Wi-Fi lokal yang sama dengan ESP32.
//    (Contoh Windows: jalankan 'ipconfig', lihat IPv4 Wi-Fi, misal 192.168.1.25)
//  - Jangan gunakan "127.0.0.1" atau "localhost" karena ESP32 adalah entitas fisik terpisah.
//  - Port standar Firebase Emulator Suite:
//      * Auth Emulator: 9099
//      * Realtime Database Emulator: 9000
//  - Kredensial mode emulator TIDAK AKAN pernah dikirimkan ke endpoint Google.
//
//  PANDUAN MODE CLOUD:
//  - FIREBASE_HOST: hostname RTDB tanpa https:// (contoh: myproject-default-rtdb.asia-southeast1.firebasedatabase.app)
//  - FIREBASE_API_KEY: Web API Key dari Firebase Console > Project Settings.
//  - Menggunakan koneksi TLS/HTTPS dengan verifikasi sertifikat root CA (tanpa setInsecure).
// ============================================================

#pragma once

// ------ Pilihan Mode Operasi (Wajib Ditentukan) -------------
// Set true  : Menggunakan HTTP ke Firebase Emulator Suite pada IP lokal
// Set false : Menggunakan HTTPS + Verifikasi CA ke Firebase Cloud produksi
#define USE_FIREBASE_EMULATOR    true

// ------ Konfigurasi Wi-Fi -----------------------------------
#define WIFI_SSID                "YOUR_WIFI_SSID"
#define WIFI_PASSWORD            "YOUR_WIFI_PASSWORD"

// ------ Identitas Perangkat ---------------------------------
// Device ID harus sesuai dengan yang didaftarkan pada backend
#define DEVICE_ID                "SIMETRI_ESP32_001"

// ------ Akun Autentikasi ESP32 ------------------------------
// Dibuat khusus untuk ESP32 melalui skrip admin (register_device.js)
// Format standar: device_<deviceid_lowercase>@simetri.internal
#define DEVICE_EMAIL             "device_simetri_esp32_001@simetri.internal"
#define DEVICE_PASSWORD          "YOUR_DEVICE_PASSWORD"

// ============================================================
//  PENGATURAN MODE EMULATOR (digunakan jika USE_FIREBASE_EMULATOR == true)
// ============================================================
#if USE_FIREBASE_EMULATOR
  // IP komputer di jaringan LAN (JANGAN gunakan 127.0.0.1 pada ESP32 fisik!)
  #define EMULATOR_HOST          "192.168.1.100"
  #define EMULATOR_AUTH_PORT     9099
  #define EMULATOR_RTDB_PORT     9000
  #define FIREBASE_PROJECT_ID    "simetri-app"
  #define FIREBASE_RTDB_NAMESPACE "simetri-app-default-rtdb"
  #define FIREBASE_API_KEY       "fake-emulator-key"

// ============================================================
//  PENGATURAN MODE CLOUD (digunakan jika USE_FIREBASE_EMULATOR == false)
// ============================================================
#else
  // Host RTDB Cloud (tanpa https:// dan tanpa trailing /)
  #define FIREBASE_HOST          "simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app"
  #define FIREBASE_PROJECT_ID    "simentri-b1a4a"
  #define FIREBASE_API_KEY       "YOUR_FIREBASE_WEB_API_KEY"
#endif

// ------ Kontrol Relay (Safety Guard) ------------------------
// false = Relay TIDAK digerakkan; perintah dicatat tetapi diabaikan (aman untuk staging).
// true  = Relay diizinkan beroperasi secara fisik.
#define ENABLE_RELAY_CONTROL     false
