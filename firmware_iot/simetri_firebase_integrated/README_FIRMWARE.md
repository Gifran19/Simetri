# SIMETRI Firebase Integrated Firmware

## Deskripsi

Firmware ESP32 pengganti firmware Blynk, menggunakan Firebase Realtime Database (RTDB)
sebagai backend. Hardware identik dengan firmware Blynk asli.

---

## Hardware

| Komponen        | GPIO / Konfigurasi                   |
|-----------------|--------------------------------------|
| PZEM-004T V4    | RX=16, TX=17, HardwareSerial 2       |
| LCD 20x2 I2C    | SDA=21, SCL=22, alamat 0x27          |
| Tombol Kondisi  | GPIO 25 (INPUT_PULLUP)               |
| Tombol Hari     | GPIO 26 (INPUT_PULLUP)               |
| Tombol Bulan    | GPIO 27 (INPUT_PULLUP)               |
| Buzzer          | GPIO 19                              |
| Relay           | GPIO 14, active LOW                  |

---

## Library yang Diperlukan

Instal via Arduino Library Manager:

| Library                    | Versi       | Catatan                     |
|----------------------------|-------------|-----------------------------|
| PZEM-004T v3.0 (olekmali)  | >= 1.1.2    | Untuk komunikasi PZEM       |
| LiquidCrystal_I2C          | >= 1.1.2    | Untuk LCD I2C               |
| ArduinoJson (Blanchon)     | >= 6.21.0   | Untuk parse JSON Firebase   |
| HTTPClient                 | Bawaan      | ESP32 Arduino Core >= 2.0.0 |
| WiFiClientSecure           | Bawaan      | ESP32 Arduino Core >= 2.0.0 |

**Board Manager**: `esp32 by Espressif Systems` versi >= 2.0.14

---

## Setup Kredensial

1. Salin file template:
   ```
   cp secrets.example.h secrets.h
   ```

2. Isi nilai di `secrets.h`:
   ```cpp
   #define WIFI_SSID        "nama_wifi_anda"
   #define WIFI_PASSWORD    "password_wifi"
   #define DEVICE_ID        "SIMETRI_ESP32_001"
   #define FIREBASE_HOST    "<project>.asia-southeast1.firebasedatabase.app"
   #define FIREBASE_PROJECT_ID  "<project-id>"
   #define FIREBASE_API_KEY "Web_API_Key_dari_Firebase_Console"
   #define DEVICE_EMAIL     "device_simetri_esp32_001@simetri.internal"
   #define DEVICE_PASSWORD  "<password dari output register_device.js>"
   ```

3. Kredensial `DEVICE_EMAIL` dan `DEVICE_PASSWORD` diperoleh dengan menjalankan:
   ```bash
   # Mode emulator (untuk pengujian lokal)
   node scripts/register_device.js --mode=emulator SIMETRI_ESP32_001 60 "Kwh Meter Utama"

   # Mode production (untuk deployment nyata)
   node scripts/register_device.js --mode=production SIMETRI_ESP32_001 60 "Kwh Meter Utama"
   ```
   Password ditampilkan **satu kali** saat akun baru dibuat. Simpan dengan aman!

---

## Pengujian dengan Firebase Emulator

> Pastikan Firebase Emulator Suite sudah berjalan sebelum mengunggah firmware.

1. Jalankan emulator di komputer pengembang:
   ```bash
   cd backend
   firebase emulators:start
   ```

2. Temukan IP komputer pengembang di jaringan WiFi yang sama dengan ESP32:
   ```bash
   # Windows: ipconfig
   # Linux/Mac: ifconfig
   ```

3. Edit `secrets.h` untuk mode emulator:
   ```cpp
   #define FIREBASE_HOST    "192.168.x.x:9000"   // IP komputer:port emulator DB
   #define FIREBASE_API_KEY "fake-emulator-key"
   ```
   Ubah URL login di firmware dari `https://` menjadi `http://` jika menggunakan emulator lokal.
   *(Alternatif: gunakan WiFiClient biasa untuk emulator, WiFiClientSecure untuk production.)*

4. Daftarkan perangkat di emulator:
   ```bash
   FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 \
   node scripts/register_device.js --mode=emulator SIMETRI_ESP32_001 60
   ```

5. Unggah firmware ke ESP32 dan pantau Serial Monitor (115200 baud).

---

## Pengujian dengan Firebase Production

1. Ganti nilai di `secrets.h` ke URL database production.
2. Pastikan Security Rules di Firebase Console sudah sesuai dengan `database.rules.json`.
3. Unggah firmware (pastikan `ENABLE_RELAY_CONTROL=false` di `secrets.h` untuk tahap awal).
4. Verifikasi data muncul di Firebase Console > Realtime Database > `devices/{deviceId}/live`.

---

## Status ENABLE_RELAY_CONTROL

| Nilai   | Perilaku                                                             |
|---------|----------------------------------------------------------------------|
| `false` | Relay TIDAK digerakkan. Perintah diterima dan dicatat ke Serial.    |
| `true`  | Relay digerakkan sesuai perintah. Aktifkan hanya setelah verifikasi. |

Ubah di `secrets.h`:
```cpp
#define ENABLE_RELAY_CONTROL false  // ganti ke true setelah pengujian lengkap
```

---

## Status Kompilasi

- **Status**: Dikompilasi bersih dengan ESP32 Arduino Core 2.0.14
- **Board**: ESP32 Dev Module
- **Peringatan kompilasi**: Tidak ada (0 warnings)
- **Ukuran flash**: Menggunakan partisi Default (tidak perlu custom)
- **Catatan**: Timestamp menggunakan `millis()` sebagai sementara.
  Untuk produksi, integrasikan NTPClient agar timestamp UNIX akurat.

---

## Daftar Key Telemetri

Data dikirim ke `devices/{deviceId}/live`:

| Key              | Tipe    | Satuan  | Keterangan                              |
|------------------|---------|---------|-----------------------------------------|
| `voltage`        | float   | V       | Tegangan listrik                        |
| `current`        | float   | A       | Arus listrik                            |
| `power`          | float   | W       | Daya aktif                              |
| `energy_kwh`     | float   | kWh     | Total energi kumulatif dari PZEM        |
| `daily_energy`   | float   | kWh     | Energi sejak ESP32 dinyalakan hari ini  |
| `monthly_energy` | float   | kWh     | Energi sejak ESP32 dinyalakan bulan ini |
| `frequency`      | float   | Hz      | Frekuensi jala-jala                     |
| `power_factor`   | float   | -       | Faktor daya (0.0 – 1.0)                 |
| `relay_state`    | boolean | -       | Status relay (true=ON, false=OFF)       |
| `timestamp`      | number  | ms      | millis() saat pengiriman (sementara)    |

---

## Batasan Versi Ini

- Timestamp menggunakan `millis()`, bukan waktu UNIX absolut.
- Histori kalender (energy_data per tanggal) belum diimplementasikan di firmware.
  Data kalender dapat dihitung oleh Cloud Functions berdasarkan telemetri live.
- TLS menggunakan `setInsecure()` untuk kemudahan pengujian awal.
  Ganti dengan `setCACert()` untuk produksi yang sebenarnya.
