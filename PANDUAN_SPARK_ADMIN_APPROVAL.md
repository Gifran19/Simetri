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

### B. Perintah Utama Administrator Lokal

Semua perintah di bawah ini dapat disalin dan dijalankan langsung dari terminal root proyek SIMETRI:

#### 1. Menetapkan Pemilik Pertama (`grant-owner`)
Digunakan saat perangkat pertama kali dipasang dan diberikan kepada pemilik utama:
```powershell
# Mode Emulator (Pengujian Lokal)
node scripts/admin_manage_access.js --mode=emulator grant-owner SIMETRI_ESP32_001 <userUid> "Smart Meter Rumah"

# Mode Produksi (Cloud Firebase Spark)
node scripts/admin_manage_access.js --mode=production grant-owner SIMETRI_ESP32_001 <userUid> "Smart Meter Rumah"
```
*Aturan Keamanan*:
- Jika perangkat belum memiliki pemilik, skrip menetapkan `meta.ownerUid = <userUid>` dan memberikan izin `status: 'active'`, `role: 'owner'`.
- Jika perangkat **sudah memiliki pemilik lain**, skrip **MENOLAK** operasi secara tegas untuk mencegah pengambilalihan kepemilikan secara diam-diam. Gunakan `transfer-owner` atau `recover`.

#### 2. Menambahkan Anggota Keluarga / Operator (`add-member`)
Digunakan untuk memberikan hak akses pantau dan kontrol kepada pengguna tambahan tanpa mengubah pemilik perangkat:
```powershell
# Mode Emulator
node scripts/admin_manage_access.js --mode=emulator add-member SIMETRI_ESP32_001 <memberUserUid>

# Mode Produksi
node scripts/admin_manage_access.js --mode=production add-member SIMETRI_ESP32_001 <memberUserUid>
```
*Aturan Keamanan*:
- Memberikan izin `status: 'active'`, `role: 'member'` pada `permissions/<memberUserUid>/SIMETRI_ESP32_001`.
- `ownerUid` pada `devices/SIMETRI_ESP32_001/meta` **TIDAK BERUBAH** sama sekali.

#### 3. Transfer Kepemilikan Resmi (`transfer-owner`)
Digunakan saat pemilik lama secara sah menyerahkan perangkat kepada pemilik baru:
```powershell
# Mode Emulator
node scripts/admin_manage_access.js --mode=emulator transfer-owner SIMETRI_ESP32_001 <newUserUid> <oldUserUid>

# Mode Produksi
node scripts/admin_manage_access.js --mode=production transfer-owner SIMETRI_ESP32_001 <newUserUid> <oldUserUid>
```
*Aturan Keamanan*:
- Skrip memverifikasi bahwa `<oldUserUid>` cocok dengan pemilik perangkat saat ini. Jika tidak cocok, transfer ditolak.
- Mengubah `meta.ownerUid` menjadi `<newUserUid>`.
- Memberikan izin `owner` kepada `<newUserUid>`.
- Menurunkan izin `<oldUserUid>` menjadi `role: 'member'` secara otomatis.

#### 4. Pemulihan Akses Darurat (`recover`)
Digunakan saat ponsel pemilik lama hilang, rusak, atau aplikasi di-uninstall sehingga UID anonim lama hangus:
```powershell
# Mode Emulator (Mencabut UID lama secara eksplisit)
node scripts/admin_manage_access.js --mode=emulator recover SIMETRI_ESP32_001 <newUserUid> <oldUserUidToRevoke>

# Mode Produksi
node scripts/admin_manage_access.js --mode=production recover SIMETRI_ESP32_001 <newUserUid> <oldUserUidToRevoke>
```
*Aturan Keamanan*:
- Menetapkan `<newUserUid>` sebagai pemilik baru (`meta.ownerUid`).
- Memberikan izin `owner` aktif kepada `<newUserUid>`.
- Jika `<oldUserUidToRevoke>` dicantumkan, skrip secara eksplisit menandai izin UID lama menjadi `status: 'revoked'`, sehingga akses ponsel lama langsung diputus seketika.

#### 5. Mencabut Izin Akses (`revoke`)
Digunakan jika pengguna tidak lagi berhak mengakses perangkat:
```powershell
# Mode Emulator
node scripts/admin_manage_access.js --mode=emulator revoke SIMETRI_ESP32_001 <userUid>

# Mode Produksi
node scripts/admin_manage_access.js --mode=production revoke SIMETRI_ESP32_001 <userUid>
```
*Aturan Keamanan*:
- Mengubah status izin pada `permissions/<userUid>/<deviceId>` menjadi `'revoked'`.
- Jika pengguna tersebut adalah pemilik (`ownerUid`), kepemilikan pada `meta.ownerUid` otomatis dikosongkan (`null`).
- Security Rules Realtime Database langsung memutus akses baca/tulis seketika.

#### 6. Menampilkan Daftar Perangkat & Hak Akses (`list`)
```powershell
# Menampilkan ringkasan seluruh perangkat terdaftar
node scripts/admin_manage_access.js --mode=emulator list

# Menampilkan rincian perangkat tertentu beserta seluruh UID yang memiliki izin
node scripts/admin_manage_access.js --mode=emulator list SIMETRI_ESP32_001
```

#### 7. Mendaftarkan Akun Autentikasi ESP32 (`provision-esp32`)
```powershell
# Mode Produksi
node scripts/admin_manage_access.js --mode=production provision-esp32 SIMETRI_ESP32_001 "Smart Meter Rumah"
```
*Tindakan*:
- Membuat akun Firebase Auth: email `device_simetri_esp32_001@simetri.internal` dengan UID `esp32_SIMETRI_ESP32_001`.
- Menghasilkan password acak aman 24 karakter heksadesimal untuk dicatat ke `secrets.h` firmware ESP32.
- Menginisialisasi node metadata `devices/SIMETRI_ESP32_001/meta`.

### C. Validasi Target Produksi Otomatis (Mencegah Salah Proyek / Salah Database)
Skrip `admin_manage_access.js` mengimplementasikan pengaman otomatis sebelum penulisan apa pun dilakukan pada mode produksi:
1. **Validasi Project ID**: Memastikan `serviceAccountKey.json` berasal dari proyek resmi `simentri-b1a4a`. Jika bukan, skrip berhenti seketika dengan pesan `[SECURITY ERROR]`.
2. **Validasi Database URL**: Memastikan URL Realtime Database mengarah ke endpoint resmi Asia Tenggara:
   `https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app`
3. Target pengujian emulator sepenuhnya terisolasi dan tidak akan pernah menyentuh cloud produksi.

---

## 3. Panduan Security Rules Realtime Database yang Tertutup

Security Rules SIMETRI dirancang dengan prinsip hak akses terkecil (*least privilege*):
> [!IMPORTANT]
> **Pencegahan Kebocoran Akses Parent Cascade**:
> Realtime Database memiliki sifat bawaan bahwa izin `.read` atau `.write` pada node induk (*parent*) tidak dapat dibatalkan oleh node anak (*child*). Oleh karena itu, path parent `devices` dan `devices/$deviceId` **TIDAK MEMILIKI `.read` MAUPUN `.write`**. Akses didelegasikan secara terisolasi hanya pada child node di bawahnya (`meta`, `live`, `status`, `control`, `energy_data`).

### Isi Aturan Resmi (`database.rules.json`)
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
          ".read": "auth != null && (root.child('permissions').child(auth.uid).child($deviceId).child('status').val() === 'active' || auth.uid === 'esp32_' + $deviceId || auth.uid === root.child('devices').child($deviceId).child('meta').child('deviceUid').val())",
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

### Langkah Penggantian via Firebase Console (Tanpa Biaya / Tanpa Blaze)
1. Buka peramban ke [Firebase Console](https://console.firebase.google.com).
2. Pilih project `simentri-b1a4a`.
3. Di panel menu kiri, klik **Build** -> **Realtime Database**.
4. Pilih database instance `simentri-b1a4a-default-rtdb` (region `asia-southeast1`).
5. Klik tab **Rules**.
6. Ganti seluruh teks rules dengan isi `database.rules.json` di atas.
7. Klik tombol **Publish**.

---

## 4. Hasil Verifikasi Pengujian Otomatis

Seluruh logika izin dan isolasi aturan keamanan telah diverifikasi lulus pengujian:

### Rincian Unit Tests (`admin_approval_unit.test.ts` - 14/14 Tests Passed):
1. **Validasi Target Produksi**: Menyetujui `simentri-b1a4a` dan URL Asia Tenggara resmi.
2. **Penolakan Target Produksi Salah**: Menolak `projectId` atau Database URL yang tidak cocok sebelum ada operasi penulisan.
3. **Pemisahan Operasi `grant-owner`**: Berhasil menetapkan pemilik pertama; percobaan kedua dengan UID berbeda ditolak (mencegah silent hijacking).
4. **Pemisahan Operasi `add-member`**: Menambahkan izin role member tanpa mengubah `meta.ownerUid`.
5. **Pemisahan Operasi `transfer-owner`**: Memvalidasi pemilik lama, memindahkan `ownerUid` ke pemilik baru, dan menurunkan pemilik lama ke member.
6. **Pemisahan Operasi `recover`**: Memindahkan kepemilikan dan mencabut izin UID lama secara eksplisit (`status: 'revoked'`).
7. **Pencabutan Izin `revoke`**: Mengubah izin menjadi `revoked` dan mengosongkan `meta.ownerUid` jika yang dicabut adalah pemilik.
8. **Audit Parent Cascade Security Rules**: Memverifikasi bahwa `database.rules.json` tidak memiliki `.read` atau `.write` pada level parent `devices` maupun `devices/$deviceId`, sehingga child node terlindungi secara ketat.

---

## 5. Keterbatasan Prototipe Spark & Rekomendasi Mitigasi

| Keterbatasan Arsitektur Spark | Dampak Operasional | Solusi / Mitigasi Tanpa Biaya |
|---|---|---|
| **Tidak Ada Kode Pairing Otomatis Mandiri** | Pengguna tidak dapat menghubungkan perangkat sendiri tanpa melibatkan administrator lokal. | Cocok untuk prototipe internal, laboratorium, atau instalasi rumah mandiri di mana admin memegang kendali PC. |
| **Pembersihan Data Aplikasi / Ganti Ponsel** | Jika pengguna melakukan *Clear Data* atau install ulang, UID anonim lama hilang dan UID baru terbentuk. | Pengguna cukup memberikan UID barunya ke admin lokal, admin menjalankan perintah `grant` ulang untuk mengalihkan izin. |
| **Tidak Ada Agregasi Cron Otomatis Cloud** | Node `energy_data` tahunan tidak diagregasi secara otomatis oleh cloud backend setiap tengah malam. | Agregasi dapat dijalankan via skrip cron lokal admin atau firmware ESP32 dapat disesuaikan untuk menulis ringkasan akhir hari. |

