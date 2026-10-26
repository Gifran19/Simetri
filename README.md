# SIMETRI – Smart Electricity Monitoring

Aplikasi Flutter untuk pemantauan energi listrik berbasis ESP32 + PZEM-004T v3.0 melalui Firebase Realtime Database.

---

## Fitur Utama

- **Telemetri real-time** – tegangan, arus, daya, energi, frekuensi, power factor
- **Pairing perangkat** – hubungkan ESP32 menggunakan kode Device ID tanpa akun
- **Histori energi** – konsumsi harian dan bulanan per tahun
- **Kontrol relay** – perintah on/off melalui Firebase _(ENABLE_RELAY_CONTROL = false, tidak aktif)_
- **Keamanan lokal** – PIN 4 digit + biometrik untuk aksi kritis
- **Tarif & estimasi biaya** – konfigurasi tarif per kWh

---

## Struktur Proyek

```
My_test_app - Copy/
├── lib/
│   ├── main.dart                          # Titik masuk aplikasi
│   ├── firebase_options.example.dart      # Template konfigurasi Firebase (salin → firebase_options.dart)
│   ├── models/                            # Model data (SensorData, EnergyRecord, dll.)
│   ├── screens/
│   │   ├── home_screen.dart              # Layar utama telemetri
│   │   ├── energy_screen.dart            # Histori & grafik energi
│   │   ├── settings_screen.dart          # Pengaturan perangkat, tarif, keamanan
│   │   ├── main_navigation_screen.dart   # Bottom navigation
│   │   ├── splash_screen.dart            # Splash screen awal
│   │   ├── tariff_history_screen.dart    # Riwayat perubahan tarif
│   │   └── welcome_screen.dart           # Layar selamat datang / pairing
│   ├── services/
│   │   ├── device_service.dart           # Manajemen Device ID (SharedPreferences)
│   │   ├── sensor_stream_service.dart    # Stream data Firebase RTDB
│   │   ├── energy_database_service.dart  # Baca/tulis histori energi
│   │   └── security_service.dart         # PIN & biometrik
│   ├── widgets/
│   │   ├── connect_device_sheet.dart     # Sheet input kode pairing
│   │   └── device_status_card.dart       # Kartu status perangkat aktif
│   └── utils/                            # Helper (format, konstanta)
├── firmware_iot/
│   ├── simetri_blynk_original/           # Firmware Blynk asli (baseline audit)
│   ├── simetri_esp32_pzem/               # Firmware Firebase aktif (hasil migrasi)
│   ├── simetri_local_display/            # Firmware layar LCD lokal
│   └── pzem_v4_test/                     # Sketch pengujian PZEM
├── database.rules.json                   # Firebase Realtime Database Security Rules
├── pubspec.yaml
└── README.md
```

---

## Bahasa & Framework

| Komponen | Teknologi |
|---|---|
| Mobile App | Flutter (Dart) |
| Backend Data | Firebase Realtime Database |
| Hardware | ESP32 + PZEM-004T v3.0 |
| Firmware | Arduino C++ (ESP32) |

---

## Prasyarat

- Flutter SDK ≥ 3.13.4
- Dart SDK ≥ 3.0
- Android SDK / Xcode (sesuai target platform)
- Akun Firebase dengan project Realtime Database aktif
- Arduino IDE atau PlatformIO untuk kompilasi firmware

---

## Setup Firebase

1. Buka [Firebase Console](https://console.firebase.google.com) dan buat project.
2. Aktifkan **Realtime Database** (mode terkunci / Rules sesuai `database.rules.json`).
3. Salin template konfigurasi:
   ```bash
   cp lib/firebase_options.example.dart lib/firebase_options.dart
   ```
4. Isi `lib/firebase_options.dart` dengan kredensial Firebase Anda.  
   _Atau gunakan FlutterFire CLI (direkomendasikan):_
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

> ⚠️ **JANGAN commit** `lib/firebase_options.dart`. File ini dikecualikan via `.gitignore`.

---

## Menjalankan Aplikasi Flutter

```bash
# Install dependensi
flutter pub get

# Jalankan di emulator / perangkat
flutter run

# Build APK release
flutter build apk --release
```

---

## Struktur Data Firebase Realtime Database

```
/devices/{device_id}/
  live/
    voltage        # Tegangan (V)
    current        # Arus (A)
    power          # Daya (W)
    energy         # Energi kumulatif (kWh)
    frequency      # Frekuensi (Hz)
    power_factor   # Faktor daya
    timestamp      # Unix timestamp terakhir
  control/
    relay_command  # "ON" / "OFF" (perintah dari aplikasi)
    relay_state    # Status fisik relay (dilaporkan ESP32)

/energy_data/{year}/{month}/{day}/
  daily_kwh        # Konsumsi harian (kWh)
  monthly_kwh      # Akumulasi bulanan (kWh)

/available_years/  # Daftar tahun yang memiliki data
```

---

## Firmware ESP32

Sketch ada di folder `firmware_iot/`:

| Folder | Deskripsi |
|---|---|
| `simetri_esp32_pzem/` | **Firmware aktif** – kirim data ke Firebase RTDB |
| `simetri_blynk_original/` | Firmware Blynk asli (baseline audit, jangan dimodifikasi) |
| `simetri_local_display/` | Firmware dengan LCD lokal |
| `pzem_v4_test/` | Sketch pengujian koneksi PZEM-004T |

### Library Arduino yang Diperlukan
- `PZEM004Tv30` by Olexa Prokopenko
- `Firebase ESP32 Client` by Mobizt
- `LiquidCrystal_I2C`

> ⚠️ `ENABLE_RELAY_CONTROL` diset `false`. Jangan ubah ke `true` tanpa validasi hardware lengkap dan pastikan beban PLN tidak terhubung.

---

## Pairing Perangkat

1. ESP32 dikonfigurasi dengan Device ID unik (contoh: `simetri_01`).
2. Di aplikasi → layar Welcome → **Hubungkan Perangkat**.
3. Masukkan Device ID.
4. Aplikasi membaca data dari `devices/{device_id}/live` secara real-time.

---

## Firebase Security Rules

Rules tersimpan di `database.rules.json`. Terapkan via Firebase Console atau Firebase CLI:

```bash
firebase deploy --only database
```

---

## Catatan Keamanan

- `lib/firebase_options.dart` – dikecualikan dari Git (berisi API key)
- `android/app/google-services.json` – dikecualikan dari Git
- PIN & biometrik melindungi perubahan tarif dan kontrol relay
- Relay control **dinonaktifkan** secara default (`ENABLE_RELAY_CONTROL = false`)

---

## Kontribusi

1. Fork repository ini
2. Buat branch fitur: `git checkout -b fitur/nama-fitur`
3. Commit perubahan: `git commit -m 'Tambah fitur X'`
4. Push ke branch: `git push origin fitur/nama-fitur`
5. Buat Pull Request

---

## Lisensi

Proyek ini untuk keperluan penelitian / tugas akhir. Lihat ketentuan penggunaan sebelum mendistribusikan ulang.
