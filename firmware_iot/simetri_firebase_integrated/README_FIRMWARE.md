# SIMETRI Firebase Integrated Firmware

## Deskripsi

Firmware ESP32 pengganti firmware Blynk lama, menggunakan Firebase Realtime Database (RTDB) dan Firebase Authentication REST API. Hardware dan pinout identik dengan firmware asli.

---

## Hardware Pinout

| Komponen        | GPIO / Konfigurasi                   | Catatan                        |
|-----------------|--------------------------------------|--------------------------------|
| PZEM-004T V4    | RX=GPIO 16, TX=GPIO 17               | HardwareSerial 2               |
| LCD 20x2 I2C    | SDA=GPIO 21, SCL=GPIO 22             | Alamat I2C 0x27                |
| Tombol Kondisi  | GPIO 25 (INPUT_PULLUP)               | Halaman V, I, P                |
| Tombol Hari     | GPIO 26 (INPUT_PULLUP)               | Halaman kWh & Biaya Hari Ini   |
| Tombol Bulan    | GPIO 27 (INPUT_PULLUP)               | Halaman kWh & Biaya Bulan Ini  |
| Buzzer          | GPIO 19                              | Feedback nada tombol           |
| Relay           | GPIO 14 (Active LOW)                 | Safety guard staging diaktifkan|

---

## Status Pengujian & Kompilasi (Laporan Terpisah)

| Aspek                | Status          | Detail / Keterangan |
|----------------------|-----------------|---------------------|
| **Kompilasi Compiler** | **Belum Dikompilasi** | Toolchain compiler (`arduino-cli` / `platformio`) belum terpasang di environment sistem pengembang. Validasi dilakukan melalui semantic/syntax review dan mock unit tests. |
| **Pengujian Emulator** | **Lulus Unit Test**   | Pengujian logic cloud functions, token claim, dan emulator integration rules berjalan via test suite backend (`npm test`). |
| **Pengujian Hardware** | **Menunggu Flashing** | Belum di-flash ke modul fisik ESP32. Flashing dilakukan setelah verifikasi environment selesai. |

---

## Mode Operasi: Emulator vs Cloud

Mode ditentukan secara eksplisit melalui konstanta `#define USE_FIREBASE_EMULATOR` di `secrets.h`.

### 1. Mode Emulator (`USE_FIREBASE_EMULATOR true`)
- **Protokol**: HTTP biasa (port 9099 untuk Auth, port 9000 untuk RTDB).
- **Endpoint Auth**: `http://<EMULATOR_HOST>:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key`
- **Endpoint Refresh**: `http://<EMULATOR_HOST>:9099/securetoken.googleapis.com/v1/token?key=fake-key`
- **Endpoint RTDB**: `http://<EMULATOR_HOST>:9000/devices/<DEVICE_ID>/live.json?ns=<NAMESPACE>&auth=<TOKEN>`
- **Keamanan**: Kredensial emulator **TIDAK AKAN PERNAH** dikirimkan ke endpoint produksi Google.

### 2. Mode Cloud Production (`USE_FIREBASE_EMULATOR false`)
- **Protokol**: HTTPS murni dengan verifikasi sertifikat Root CA (Google Trust Services GTS Root R1).
- **Keamanan**: **Dilarang memakai `setInsecure()`**. Verifikasi sertifikat TLS aktif penuh (`root_ca.h`).

---

## Panduan IP Host & Jaringan

ESP32 adalah mikrokontroler mandiri di jaringan Wi-Fi, sehingga **tidak dapat menggunakan `127.0.0.1` atau `localhost`**.

| Perangkat Klien | Host Emulator yang Digunakan | Keterangan |
|-----------------|------------------------------|------------|
| **ESP32 Fisik** | IP LAN Komputer (misal: `192.168.1.50`) | Komputer dan ESP32 harus berada di jaringan Wi-Fi lokal yang sama. Port 9000 & 9099 harus diizinkan pada Firewall komputer. |
| **Ponsel Fisik (Flutter)** | IP LAN Komputer (misal: `192.168.1.50`) | Sama seperti ESP32 fisik. |
| **Android Emulator (AVD)** | `10.0.2.2` | Alias bawaan Android Emulator untuk host loopback komputer. |
| **iOS Simulator** | `127.0.0.1` | Berbagi jaringan network stack yang sama dengan macOS host. |

---

## Setup Kredensial

1. Salin template:
   ```bash
   cp firmware_iot/simetri_firebase_integrated/secrets.example.h firmware_iot/simetri_firebase_integrated/secrets.h
   ```

2. Daftarkan perangkat untuk mendapatkan akun auth khusus ESP32:
   ```bash
   # Mode emulator:
   node scripts/register_device.js --mode=emulator SIMETRI_ESP32_001 60 "Kwh Meter Utama"

   # Mode production:
   node scripts/register_device.js --mode=production SIMETRI_ESP32_001 60 "Kwh Meter Utama"
   ```
   *Salin email dan password dari output skrip tersebut ke `secrets.h`.*

---

## Keamanan Relay (`ENABLE_RELAY_CONTROL`)

Nilai default adalah `false` (Staging Guard).

- **`ENABLE_RELAY_CONTROL false`**: Relay secara fisik dipaksa tetap OFF (buka). Perintah dari cloud diterima dan dicatat ke log Serial, tetapi **relay_output_state** tidak diubah menjadi nilai perintah yang diabaikan.
- **Pemisahan State**:
  - `requested_power`: Nilai perintah dari node `devices/{deviceId}/control/power`.
  - `relay_output_state`: Status logika output pin GPIO 14 (bukan status mekanik kontak tanpa sensor umpan balik).
  - `relay_control_enabled`: Boolean flag apakah eksekusi kontrol relay diizinkan.
- **Validasi Nilai Perintah**: Respons RTDB `null` atau non-boolean **diabaikan** dan tidak dianggap sebagai perintah OFF.

---

## Validitas Sensor & Penanganan Error

- Jika pembacaan sensor PZEM gagal atau belum siap, firmware **TIDAK MENGIRIM ANGKA 0.0 PALSU** yang menyerupai tegangan normal.
- Field `voltage`, `current`, `power`, `frequency`, `power_factor` dikirim sebagai `null`.
- Field `sensor_valid` dikirim sebagai `false`, disertai `reading_age_ms` dan `sensor_status: "stale_or_disconnected"`.
- Aplikasi Flutter mendeteksi flag ini untuk menampilkan status `SENSOR ERROR` / `STALE` secara transparan kepada pengguna.

---

## Skema Telemetri RTDB (`devices/{deviceId}/live`)

```json
{
  "sensor_valid": true,
  "reading_age_ms": 250,
  "last_read_uptime_ms": 145000,
  "voltage": 220.4,
  "current": 1.35,
  "power": 297.5,
  "frequency": 50.0,
  "power_factor": 0.98,
  "energy_kwh": 45.210,
  "daily_energy": 3.450,
  "monthly_energy": 112.500,
  "requested_power": false,
  "relay_output_state": false,
  "relay_control_enabled": false,
  "uptime_ms": 145250,
  "sent_uptime_ms": 145250,
  "server_timestamp": 1729300000000
}
```

*Catatan: `server_timestamp` diisi secara otomatis oleh server Firebase melalui token REST `{".sv": "timestamp"}`, membedakan waktu server dengan waktu lokal ESP32 (`uptime_ms`).*
