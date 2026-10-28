# PANDUAN PENGUJIAN KONEKSI NYATA SIMETRI
**Sistem Monitoring Energi Listrik IoT (PZEM-004T -> ESP32 -> Firebase Cloud -> Flutter)**

---

## 1. Verifikasi Integritas Source Firmware & Dependensi

Berdasarkan perbandingan hash kriptografis SHA-256 antara berkas pada commit `264b9e9` di repositori dengan berkas sketch yang berhasil dikompilasi pada toolchain lokal:

| Berkas Firmware | Hash SHA-256 Repositori | Hash SHA-256 Terkompilasi | Status Integritas |
|---|---|---|---|
| `simetri_firebase_integrated.ino` | `58036A4755543E7EEDDAD21DFA5682AB4F863EE462D5B13C0E9864FF475E3AEF` | `58036A4755543E7EEDDAD21DFA5682AB4F863EE462D5B13C0E9864FF475E3AEF` | **100% Identik (Bit-for-bit)** |
| `root_ca.h` | `9C02F4D80C35D4778BC3F014E8E7687953AC839594F55F7E80DEBD689767BD18` | `9C02F4D80C35D4778BC3F014E8E7687953AC839594F55F7E80DEBD689767BD18` | **100% Identik (Bit-for-bit)** |
| `secrets.h` | *Diabaikan Git via .gitignore* | Berisi placeholder lokal | **Aman (Tidak bocor ke Git)** |

### Spesifikasi Board & Versi Seluruh Dependensi:
- **Board Target / FQBN**: `esp32:esp32:esp32` (ESP32 Dev Module)
- **ESP32 Core**: `esp32:esp32@2.0.17` (Rilis resmi stabil Espressif)
- **Compiler**: `xtensa-esp32-elf-gcc (crosstool-NG esp-2021r2-patch5) 8.4.0`
- **Pustaka Eksternal**:
  - `ArduinoJson` : v6.21.4 (Benoit Blanchon)
  - `PZEM004Tv30` : v1.2.1 (Jakub Mandula)
  - `LiquidCrystal I2C` : v1.1.2 (Frank de Brabander)
- **Pustaka Inti ESP32 (Core 2.0.17)**:
  - `WiFi` : v2.0.0
  - `WiFiClientSecure` : v2.0.0
  - `HTTPClient` : v2.0.0
  - `Wire` : v2.0.0

---

## 2. Checklist Firebase Cloud Project `simentri-b1a4a`

| Item Checklist | Status Terbukti dari Kode | Wajib Diperiksa Langsung di Firebase Console |
|---|---|---|
| **A. Konfigurasi Flutter & RTDB** | `lib/firebase_options.dart` mengarah ke project `simentri-b1a4a` dengan URL database `https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app`. | Pastikan instance Realtime Database pada region **asia-southeast1** berstatus **Active** (bukan locked/disabled). |
| **B. Anonymous Authentication** | `lib/services/auth_service.dart` mengeksekusi `signInAnonymously()`. | Menu **Authentication** -> tab **Sign-in method** -> **Anonymous** harus dalam kondisi **Enabled**. |
| **C. Email/Password Authentication (ESP32)** | ESP32 melakukan login REST Identity Toolkit dengan format email `device_<id>@simetri.internal`. | Menu **Authentication** -> tab **Sign-in method** -> **Email/Password** harus **Enabled**. |
| **D. Cloud Function `claimDevice`** | `backend/functions/src/index.ts` mengekspor callable `claimDevice` pada region `us-central1`. | Menu **Functions** -> pastikan fungsi `claimDevice` sudah terdaftar dan URL callable-nya aktif. |
| **E. Security Rules RTDB** | `database.rules.json` membatasi node `pairing_secrets` hanya untuk Admin SDK, dan node `live` hanya untuk akun ESP32. | Menu **Realtime Database** -> tab **Rules** -> pastikan rules di konsol sama persis dengan `database.rules.json`. |
| **F. Prasyarat Billing (GCP Plan)** | `package.json` menggunakan runtime Node.js 20 dan Cloud Functions v2. | **Kritis**: Cloud Functions v2 wajib berada pada **Blaze Plan (Pay-as-you-go)**. Deployment akan ditolak Firebase CLI jika project masih Spark Plan (Gratis). |

---

## 3. Mekanisme Skrip Provisioning Produksi (`scripts/register_device.js`)

Skrip `scripts/register_device.js` digunakan oleh administrator sistem untuk menerbitkan identitas autentikasi ESP32 dan kode pairing sementara.

### A. Cara Skrip Memuat Kredensial Admin & Memvalidasi Project Produksi
1. **Pemeriksaan File Kunci**: Skrip memeriksa keberadaan berkas `serviceAccountKey.json` pada root direktori proyek (`path.resolve(__dirname, '../serviceAccountKey.json')`). Jika file tidak ada, proses langsung dihentikan sebelum inisialisasi.
2. **Validasi Project ID**: Skrip membaca properti `project_id` dari JSON kunci. Skrip memastikan `project_id` bukan placeholder (tidak memuat kata `YOUR_`) dan memiliki panjang minimal 4 karakter.
3. **Validasi Database URL**: Skrip membaca target URL database dari environment variable `FIREBASE_DATABASE_URL` (atau fallback namespace). Skrip memvalidasi bahwa URL harus diawali dengan protokol aman `https://` dan tidak mengandung kata `YOUR_`.
4. **Inisialisasi Aman**: Menginisialisasi Firebase Admin SDK dengan `admin.credential.cert(serviceAccount)` dan `databaseURL` yang sudah divalidasi.
5. **Pemisahan Kredensial**: Tidak ada kunci rahasia atau token permanen yang dicatat ke berkas log. Kata sandi akun perangkat di-generate secara acak (`crypto.randomBytes(12)`) dan hanya ditampilkan satu kali pada terminal konsol saat akun pertama kali dibuat.

### B. Prasyarat Eksekusi
1. Unduh berkas service account privat dari **Firebase Console** -> **Project Settings** -> **Service accounts** -> klik **Generate new private key**.
2. Simpan sebagai `serviceAccountKey.json` di root folder proyek (sudah terdaftar di `.gitignore`).
3. Setel URL database region `asia-southeast1` via terminal.

### C. Contoh Perintah Eksekusi
```powershell
$env:FIREBASE_DATABASE_URL="https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app"
node scripts/register_device.js --mode=production SIMETRI_ESP32_001 60 "Smart Meter Utama"
```
*Parameter*:
- `--mode=production` : Mengunci target secara eksplisit ke cloud produksi.
- `SIMETRI_ESP32_001` : Identitas publik perangkat (`deviceId`).
- `60` : Masa aktif kode pairing dalam menit.
- `"Smart Meter Utama"` : Label nama perangkat.

*Keluaran yang Dihasilkan*:
- Akun ESP32 terdaftar di Firebase Auth: `device_simetri_esp32_001@simetri.internal` dengan kata sandi acak.
- Metadata tersimpan di `devices/SIMETRI_ESP32_001/meta`.
- Hash kode pairing SHA-256 tersimpan di `pairing_secrets/<hash>`.
- Kode pairing sementara (8 karakter heksadesimal, misal: `A1B2C3D4`) siap diserahkan ke pengguna.

---

## 4. Panduan untuk Rekan Pemegang Hardware ESP32

### A. Konfigurasi `secrets.h` Lokal
Salin berkas `firmware_iot/simetri_firebase_integrated/secrets.example.h` menjadi `firmware_iot/simetri_firebase_integrated/secrets.h`. Isi dengan nilai aktual:
```cpp
// 1. Pilih mode Cloud Produksi
#define USE_FIREBASE_EMULATOR    false

// 2. Kredensial Wi-Fi Lokal 2.4 GHz
#define WIFI_SSID                "SSID_WIFI_LOKAL"
#define WIFI_PASSWORD            "PASSWORD_WIFI_LOKAL"

// 3. Identitas Perangkat (Sesuai hasil provisioning langkah 3)
#define DEVICE_ID                "SIMETRI_ESP32_001"
#define DEVICE_EMAIL             "device_simetri_esp32_001@simetri.internal"
#define DEVICE_PASSWORD          "PASSWORD_DARI_LANGKAH_PROVISIONING"

// 4. Konfigurasi Firebase Cloud (Dari lib/firebase_options.dart)
#define FIREBASE_HOST            "simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_PROJECT_ID      "simentri-b1a4a"
#define FIREBASE_API_KEY         "API_KEY_DARI_FIREBASE_OPTIONS"

// 5. Keselamatan Fisik
#define ENABLE_RELAY_CONTROL     false
```

> [!IMPORTANT]
> **Wajib mempertahankan `ENABLE_RELAY_CONTROL = false`**. Flag keselamatan ini memastikan pin relay fisik GPIO 14 tetap terkunci pada posisi aman dan tidak memicu beban fisik selama uji coba meja.

### B. Kompilasi & Flashing (Setelah Persetujuan)
1. Hubungkan modul ESP32 melalui kabel data USB ke komputer.
2. Identifikasi port COM aktif (misal `COM3`).
3. Jalankan perintah kompilasi dan upload:
```powershell
arduino-cli compile --fqbn esp32:esp32:esp32 firmware_iot/simetri_firebase_integrated
arduino-cli upload -p COM3 --fqbn esp32:esp32:esp32 firmware_iot/simetri_firebase_integrated
```

### C. Pemeriksaan Serial Monitor (Baud Rate 115200)
Amati tahapan inisialisasi pada Serial Monitor:
1. `WiFi: Connecting... Connected! IP: 192.168.x.x`
2. `SNTP: Menunggu sinkronisasi waktu... Waktu tersinkronisasi: OK` (Wajib lulus sebelum enkripsi TLS dimulai).
3. `Firebase Auth: Mengautentikasi... Login Berhasil! Token diperoleh.`
4. `PZEM-004T: Inisialisasi HardwareSerial2 (RX:16, TX:17)... OK`
5. `Kirim Telemetri: HTTP 200 / 204` (Terjadwal setiap 5 detik).

### D. Verifikasi Telemetri di Firebase RTDB Console
Buka konsol Firebase Realtime Database pada path `devices/SIMETRI_ESP32_001/live`. Pastikan field terisi data sensor aktual:
- `voltage` (~220V), `current`, `power`, `frequency` (~50 Hz).
- `sensor_valid: true`.
- `relay_control_enabled: false`.
- `server_timestamp`: angka timestamp Epoch milidetik yang terus bertambah setiap 5 detik.

---

## 5. Pengujian Bertahap Lintas Jaringan (E2E Live Verification)

### Tahap 1: Verifikasi Aliran Data ESP32 -> Cloud
1. Nyalakan ESP32 yang terhubung ke modul PZEM-004T dan LCD 20x2.
2. Hubungkan beban listrik nyata (misal lampu 25W).
3. Verifikasi pada LCD dan Serial Monitor bahwa tegangan dan watt terbaca normal.
4. Buka Firebase RTDB Console: pastikan `devices/SIMETRI_ESP32_001/live` mencatat nilai yang sama persis.

### Tahap 2: Proses Pairing pada Aplikasi Flutter
1. Buka aplikasi SIMETRI pada ponsel pintar.
2. Sesi anonim terbentuk secara otomatis di latar belakang.
3. Buka lembar pairing (*Connect Device Sheet*).
4. Masukkan kode pairing sementara 8-karakter yang diterbitkan pada langkah 3.
5. Tekan **"Verifikasi & Hubungkan"**.
6. Cloud Function memverifikasi hash kode, mengunci owner UID, dan memberikan izin aktif. Aplikasi menyimpan `deviceId` ke penyimpanan lokal.

### Tahap 3: Uji Lintas Jaringan via Paket Data Seluler (4G/5G)
1. Matikan sambungan Wi-Fi pada ponsel, aktifkan **Paket Data Seluler**.
2. Buka aplikasi SIMETRI.
3. Kartu status perangkat menampilkan badge **ONLINE**.
4. Metrik tegangan, arus, dan daya pada antarmuka ponsel mencerminkan angka nyata dari sensor PZEM tanpa penundaan berarti.

### Tahap 4: Uji Pemutusan Daya ESP32 (Graceful Offline Handling)
1. Putuskan daya ESP32 hingga mati total.
2. Tunggu 30 detik (ambang batas evaluasi `server_timestamp`).
3. Periksa tampilan aplikasi ponsel:
   - Badge status perangkat berubah menjadi **OFFLINE**.
   - **Koreksi Semantik**: Ketiadaan telemetri ditandai dengan placeholder pembacaan tidak tersedia (`--` atau `N/A`), **BUKAN menampilkan konsumsi 0 W**.
   - **Verifikasi**: Tidak ada simulator beban acak PLN atau data fiktif yang aktif.

---

## 6. Laporan Status Histori Dummy & Pengisian `energy_data`

### A. Pembedaan Histori Kosong vs Konsumsi Nol
- **Histori Kosong (`empty`)**: Terjadi ketika node `energy_data/$deviceId/$year` belum pernah ditulis di database. Aplikasi mengembalikan status data belum tersedia dengan visualisasi grafik kosong. Hal ini **bukan** berarti pemakaian listrik adalah 0 kWh, melainkan histori agregasi belum tercatat.
- **Konsumsi Nol (0 kWh)**: Terjadi ketika data historis terisi dan mencatat pemakaian 0.00 kWh pada bulan tertentu (misalnya gedung/rumah kosong tanpa ada beban yang menyala).
- **Pembacaan Real-time Tidak Tersedia vs Konsumsi 0 W**: Ketika perangkat offline, pembacaan tidak tersedia (`--`). Nilai 0 W hanya ditampilkan jika sensor online dan mendeteksi ketiadaan beban mengalir secara valid.

### B. Status Fallback Dummy
- Fallback dummy pada `EnergyDatabaseService` **telah dinonaktifkan** untuk mode nyata.
- Fallback dummy hanya aktif bila aplikasi dijalankan secara eksplisit dengan flag `--dart-define=SIMETRI_DEMO_MODE=true` dan diberi label **DEMO**.
- Pada mode nyata, jika database kosong, fungsi `fetchYearlyData` mengembalikan `YearlyEnergyData.empty(year)`.

### C. Siapa yang Mengisi `energy_data`
- Sesuai `database.rules.json` (baris 81–86), hak tulis ke `energy_data/$deviceId` hanya diizinkan untuk akun ESP32 (`esp32_<deviceId>`) atau Firebase Admin SDK. Pengguna aplikasi Flutter ditolak (`write: false`).
- Firmware ESP32 saat ini hanya mengirim data live ke `devices/$deviceId/live` dan belum memiliki rutin penulisan agregasi bulanan.
- **Solusi Arsitektur**: Diperlukan Cloud Functions scheduler (cron tengah malam) atau fungsi trigger `onValueWritten` yang membaca akumulasi kWh harian dari telemetri dan menulisnya secara terstruktur ke `energy_data/$deviceId/$year/monthly_energy`.

---

## 7. Ringkasan Status Sesi
- **File Panduan Tersimpan**: `PANDUAN_PENGUJIAN_KONEKSI_SIMETRI.md`
- **Background Tasks**: Seluruh task latar belakang PowerShell telah dihentikan (0 running tasks).
- **Kondisi Git**: Branch `feature/anonymous-pairing-backend` berada pada commit `264b9e9f20678e89851537ef81df215f07f33814`.
- **Status Deployment**: Tidak ada deployment cloud, provisioning produksi, atau flashing hardware fisik yang dijalankan.

