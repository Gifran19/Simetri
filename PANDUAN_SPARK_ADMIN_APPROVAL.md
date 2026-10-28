# PANDUAN ARSITEKTUR SIMETRI SPARK (PERSETUJUAN AKSES ADMIN LOKAL)
**Implementasi Bebas Biaya (Firebase Spark Free Tier - Tanpa Blaze / Cloud Functions)**

---

## 1. Ringkasan Arsitektur & Perubahan dari Cloud Functions

Pada paket **Firebase Spark (Gratis)**, deployment Cloud Functions (termasuk callable function `claimDevice`) tidak diizinkan oleh Google Cloud karena membutuhkan aktivasi kartu kredit / paket Blaze.

Untuk menjaga proyek SIMETRI tetap 100% berada pada paket gratis tanpa formulir login/register pengguna, arsitektur diubah menjadi **Model Persetujuan Akses Admin Lokal (Local Admin Approval Flow)**:

```
[Pengguna Ponsel]                           [Admin Lokal]                          [ESP32 Hardware]
       │                                          │                                       │
       ├─ Buka Aplikasi                           │                                       │
       ├─ Dapatkan UID Anonim (misal: "u123")     │                                       │
       │                                          │                                       │
       ├─ Kirim UID & Device ID ("SIMETRI_01") ──>│ (Verifikasi fisik/langsung)           │
       │                                          │                                       │
       │                                          ├─ Jalankan skrip admin lokal:          │
       │                                          │  node admin_manage_access.js grant    │
       │                                          │  SIMETRI_01 u123                      │
       │                                          │                                       │
       │                                          ├─ Tulis permissions/u123/SIMETRI_01    │
       │                                          │  { status: "active", role: "owner" }  │
       │                                          │                                       │
       ├─ Tekan "Periksa & Verifikasi Izin"       │                                       │
       ├─ Baca permissions/u123/SIMETRI_01 ───────┼─> Terverifikasi "active"              │
       ├─ Aplikasi menyatakan TERHUBUNG           │                                       │
       │                                          │                                       │
       ├─ Listen devices/SIMETRI_01/live <────────┴───────────────────────────────────────┼─ Kirim telemetri PZEM
       └─ Kirim kontrol relay (aktif) ───────────────────────────────────────────────────>│  (auth.uid: esp32_SIMETRI_01)
```

### Karakteristik Kunci:
1. **Tidak Ada Login/Register Konvensional**: Aplikasi tetap menggunakan Firebase Anonymous Auth di latar belakang.
2. **Kredensial ESP32 Terpisah Penuh**: ESP32 menggunakan akun Email/Password khusus (`device_<deviceId>@simetri.internal` dengan UID `esp32_<deviceId>`), terpisah dari pengguna anonim.
3. **Bukan Pairing Otomatis**: Hubungan antara ponsel dan alat didasarkan pada persetujuan eksplisit oleh admin lokal, bukan tebakan atau pertukaran kode sementara via cloud functions.
4. **Keamanan Tanpa Server**: Hak akses ditegakkan 100% oleh **Security Rules Realtime Database** tingkat database, bukan logika backend perantara.

---

## 2. Panduan Penggunaan Skrip Admin Lokal (`scripts/admin_manage_access.js`)

Skrip admin lokal berjalan langsung di PC administrator dengan Node.js dan Firebase Admin SDK:

### A. Prasyarat Kredensial Admin
1. Buka **Firebase Console** -> **Project Settings** -> **Service accounts**.
2. Klik **Generate new private key**, simpan berkas dengan nama `serviceAccountKey.json` di root direktori proyek.
3. Pastikan `serviceAccountKey.json` terdaftar di `.gitignore` (jangan pernah di-commit).

### B. Perintah Utama

#### 1. Memberikan Izin Akses (`grant`)
Digunakan saat pengguna meminta izin akses ke perangkat dengan menyerahkan UID anonimnya:
```powershell
# Mode Emulator (Pengujian Lokal)
node scripts/admin_manage_access.js --mode=emulator grant SIMETRI_ESP32_001 <userUid> [owner|member] [label]

# Mode Produksi (Cloud Firebase Spark)
$env:FIREBASE_DATABASE_URL="https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app"
node scripts/admin_manage_access.js --mode=production grant SIMETRI_ESP32_001 <userUid> owner "Smart Meter Utama"
```
*Tindakan Otomatis Skrip*:
- Memvalidasi bahwa `userUid` dan `deviceId` valid.
- Menjaga konsistensi: jika peran adalah `owner`, memperbarui `devices/<deviceId>/meta/ownerUid = <userUid>`. Jika sebelumnya ada owner lain, owner lama secara otomatis diturunkan menjadi `member`.
- Menulis data izin ke `permissions/<userUid>/<deviceId>` dengan `status: "active"`.

#### 2. Mencabut Izin Akses (`revoke`)
Digunakan jika perangkat dipindahtangankan, disewakan, atau pengguna kehilangan hak:
```powershell
# Mode Emulator
node scripts/admin_manage_access.js --mode=emulator revoke SIMETRI_ESP32_001 <userUid>

# Mode Produksi
node scripts/admin_manage_access.js --mode=production revoke SIMETRI_ESP32_001 <userUid>
```
*Tindakan Otomatis Skrip*:
- Mengubah `status` pada `permissions/<userUid>/<deviceId>` menjadi `"revoked"`.
- Jika pengguna tersebut adalah `ownerUid` pada `devices/<deviceId>/meta`, menghapus kepemilikannya (`ownerUid: null`).
- Security Rules langsung memutus akses baca telemetri dan kontrol relay pengguna seketika.

#### 3. Menampilkan Status Perangkat & Izin (`list`)
```powershell
# Menampilkan seluruh perangkat
node scripts/admin_manage_access.js --mode=emulator list

# Menampilkan rincian perangkat dan seluruh pemegang izin
node scripts/admin_manage_access.js --mode=emulator list SIMETRI_ESP32_001
```

#### 4. Mendaftarkan Akun Autentikasi ESP32 (`provision-esp32`)
```powershell
node scripts/admin_manage_access.js --mode=production provision-esp32 SIMETRI_ESP32_001 "Smart Meter Utama"
```
*Tindakan*:
- Membuat akun Firebase Auth dengan email `device_simetri_esp32_001@simetri.internal` dan UID `esp32_SIMETRI_ESP32_001`.
- Menghasilkan password acak aman 24 karakter heksadesimal yang dicetak satu kali di konsol.
- Menginisialisasi node metadata `devices/SIMETRI_ESP32_001/meta`.

---

## 3. Panduan Penggantian Security Rules Cloud yang Tertutup

Realtime Database pada proyek Firebase baru biasanya dibuat dalam mode *test* (terbuka untuk publik selama 30 hari). Untuk menguncinya secara aman pada Spark tier:

### Langkah Penggantian via Firebase Console (Tanpa Biaya / Tanpa Blaze)
1. Buka peramban ke [Firebase Console](https://console.firebase.google.com).
2. Pilih project `simentri-b1a4a`.
3. Di panel menu kiri, klik **Build** -> **Realtime Database**.
4. Pilih database instance `simentri-b1a4a-default-rtdb` (region `asia-southeast1`).
5. Klik tab **Rules**.
6. Ganti seluruh teks rules yang ada dengan isi berkas `database.rules.json` berikut:

```json
{
  "rules": {
    ".read": false,
    ".write": false,

    "permissions": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        ".write": false
      }
    },

    "devices": {
      "$deviceId": {
        "meta": {
          ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === data.child('deviceUid').val())",
          ".write": false
        },
        "live": {
          ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
          ".write": "auth != null && (auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
          "voltage": { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "current": { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "power": { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "energy_kwh": { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "relay_state": { ".validate": "newData.isBoolean()" },
          "timestamp": { ".validate": "newData.isNumber()" }
        },
        "status": {
          ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
          ".write": "auth != null && (auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())"
        },
        "control": {
          ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
          ".write": "auth != null && root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active'",
          "power": { ".validate": "newData.isBoolean()" },
          "limit_va": { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "tariff_per_kwh": { ".validate": "newData.isNumber() && newData.val() >= 0" }
        }
      }
    },

    "energy_data": {
      "$deviceId": {
        ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
        ".write": "auth != null && (auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())"
      }
    }
  }
}
```
7. Klik tombol **Publish**.

*Atau via Firebase CLI (Jika sudah login CLI)*:
```powershell
firebase deploy --only database --project simentri-b1a4a
```
*(Deploy database rules didukung penuh pada Spark Free tier tanpa memerlukan Blaze plan).*

---

## 4. Hasil Pengujian Emulator Suite (20/20 Test Passed)

Seluruh skenario telah diuji langsung pada Firebase Emulator Suite lokal (`Auth` dan `Database Emulator` aktif):

### Rincian Uji Suite Admin Approval (`admin_approval.test.ts`):
1. **Akses Tanpa Izin Ditolak**: Pengguna anonim tanpa entri izin mencoba membaca `devices/DEV/live` $\to$ Ditolak HTTP 401 (*Permission Denied*).
2. **Penolakan Modifikasi Tanpa Izin**: Pengguna tanpa izin mencoba menulis saklar `control` $\to$ Ditolak HTTP 401.
3. **Aplikasi Dilarang Mengubah Izin Sendiri**: Klien anonim mencoba menulis langsung ke node `permissions` $\to$ Ditolak HTTP 401 (`.write: false`).
4. **Pemberian Izin oleh Admin Lokal**: Admin lokal menulis izin `active` via Admin SDK $\to$ Izin tersimpan, `ownerUid` konsisten, dan pengguna dapat membaca izinnya sendiri.
5. **Akses Pemilik Aktif Berhasil**: Pengguna dengan status `active` membaca telemetri `live` dan menulis perintah `control` $\to$ Berhasil HTTP 200.
6. **Isolasi Antarperangkat**: Pengguna dengan izin pada `DEV_A` mencoba membaca telemetri `DEV_B` $\to$ Ditolak HTTP 401.
7. **Penolakan Tulis Telemetri oleh Aplikasi**: Pengguna (meskipun aktif) mencoba menulis data palsu ke `devices/DEV_A/live` $\to$ Ditolak HTTP 401 (hanya ESP32 yang boleh menulis).
8. **ESP32 Telemetri Sah**: Akun ESP32 resmi (`esp32_DEV_A`) menulis data PZEM ke `devices/DEV_A/live` $\to$ Berhasil HTTP 200.
9. **Pencabutan Izin (Revocation)**: Admin mengubah status izin menjadi `revoked` dan mengosongkan `ownerUid` $\to$ Pengguna seketika ditolak membaca dan menulis ke perangkat.

---

## 5. Keterbatasan Prototipe Spark & Rekomendasi Mitigasi

| Keterbatasan Arsitektur Spark | Dampak Operasional | Solusi / Mitigasi Tanpa Biaya |
|---|---|---|
| **Tidak Ada Kode Pairing Otomatis Mandiri** | Pengguna tidak dapat menghubungkan perangkat sendiri tanpa melibatkan administrator lokal. | Cocok untuk prototipe internal, laboratorium, atau instalasi rumah mandiri di mana admin memegang kendali PC. |
| **Pembersihan Data Aplikasi / Ganti Ponsel** | Jika pengguna melakukan *Clear Data* atau install ulang, UID anonim lama hilang dan UID baru terbentuk. | Pengguna cukup memberikan UID barunya ke admin lokal, admin menjalankan perintah `grant` ulang untuk mengalihkan izin. |
| **Tidak Ada Agregasi Cron Otomatis Cloud** | Node `energy_data` tahunan tidak diagregasi secara otomatis oleh cloud backend setiap tengah malam. | Agregasi dapat dijalankan via skrip cron lokal admin atau firmware ESP32 dapat disesuaikan untuk menulis ringkasan akhir hari. |
