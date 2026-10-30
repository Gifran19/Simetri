// ============================================================
//  SIMETRI Firebase Integrated Firmware
//  File: firmware_iot/simetri_firebase_integrated/simetri_firebase_integrated.ino
//
//  Versi    : 1.1.0-staging (ENABLE_RELAY_CONTROL=false)
//  Target   : ESP32 (Espressif ESP32 Arduino Core)
//
//  HARDWARE (identik dengan firmware Blynk asli):
//  - PZEM-004T V4   : RX=GPIO16, TX=GPIO17, HardwareSerial 2
//  - LCD 20x2 I2C   : SDA=GPIO21, SCL=GPIO22, alamat 0x27
//  - Tombol kondisi : GPIO25 (INPUT_PULLUP)
//  - Tombol hari    : GPIO26 (INPUT_PULLUP)
//  - Tombol bulan   : GPIO27 (INPUT_PULLUP)
//  - Buzzer         : GPIO19
//  - Relay          : GPIO14, active LOW
//
//  STATUS IMPLEMENTASI & PENGUJIAN:
//  - Kompilasi Compiler : Belum dikompilasi (tool compiler arduino-cli/pio belum tersedia di environment ini)
//  - Emulator Suite     : Pengujian endpoint Auth & RTDB lokal via mode emulator HTTP
//  - Hardware Fisik     : Pengujian hardware terpisah (pending flashing)
//
//  FITUR KEAMANAN & ARSITEKTUR:
//  1. Mode emulator/cloud eksplisit:
//     - Emulator: HTTP ke IP komputer pengembang (port Auth 9099, port RTDB 9000, namespace eksplisit).
//     - Cloud: HTTPS dengan verifikasi sertifikat Root CA Google Trust Services (tanpa setInsecure).
//     - Kredensial emulator TIDAK dikirimkan ke endpoint Google.
//  2. Timestamp:
//     - Menggunakan Firebase server timestamp {".sv": "timestamp"} untuk RTDB.
//     - millis() disimpan terpisah sebagai uptime_ms, reading_age_ms, dan sent_uptime_ms.
//     - Uptime TIDAK digunakan sebagai Unix timestamp.
//  3. Relay:
//     - ENABLE_RELAY_CONTROL=false secara default.
//     - Status relay_output_state tidak diubah oleh perintah yang diabaikan.
//     - requested_power, relay_output_state, dan relay_control_enabled dipisahkan.
//     - Respons null / non-boolean dari RTDB TIDAK dianggap perintah OFF.
//  4. Validitas Sensor:
//     - Keberhasilan dan usia pembacaan (reading_age_ms) dicatat.
//     - Pembacaan gagal tidak diganti angka nol yang tampak valid (dikirim null & sensor_valid=false).
//     - Nilai lama tidak dikirim sebagai pembacaan baru.
//  5. Koneksi & Timing:
//     - Wi-Fi reconnection non-blocking bertahap (tanpa delay loop 15 detik).
//     - Retry login dengan jeda backoff terjadwal.
//     - Network timeout dibatasi (3000 ms) agar sensor, LCD, dan tombol tidak terblokir.
//     - Penjadwalan refresh token aman terhadap rollover millis().
// ============================================================

#include <WiFi.h>
#include <WiFiClient.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <PZEM004Tv30.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <time.h>
#include <Preferences.h>

#include "secrets.h"
#include "root_ca.h"

// ============================================================
//  VERIFIKASI KONFIGURASI secrets.h
// ============================================================

#ifndef USE_FIREBASE_EMULATOR
  #error "USE_FIREBASE_EMULATOR belum ditentukan di secrets.h. Set true (emulator) atau false (cloud)."
#endif

#ifndef WIFI_SSID
  #error "WIFI_SSID tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef DEVICE_ID
  #error "DEVICE_ID tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef DEVICE_EMAIL
  #error "DEVICE_EMAIL tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef DEVICE_PASSWORD
  #error "DEVICE_PASSWORD tidak didefinisikan. Periksa secrets.h."
#endif

#if USE_FIREBASE_EMULATOR
  #ifndef EMULATOR_HOST
    #error "EMULATOR_HOST wajib didefinisikan untuk mode emulator di secrets.h."
  #endif
  #ifndef EMULATOR_AUTH_PORT
    #define EMULATOR_AUTH_PORT 9099
  #endif
  #ifndef EMULATOR_RTDB_PORT
    #define EMULATOR_RTDB_PORT 9000
  #endif
  #ifndef FIREBASE_RTDB_NAMESPACE
    #define FIREBASE_RTDB_NAMESPACE "simetri-app-default-rtdb"
  #endif
#else
  #ifndef FIREBASE_HOST
    #error "FIREBASE_HOST wajib didefinisikan untuk mode cloud di secrets.h."
  #endif
  #ifndef FIREBASE_API_KEY
    #error "FIREBASE_API_KEY wajib didefinisikan untuk mode cloud di secrets.h."
  #endif
#endif

// ============================================================
//  PIN HARDWARE
// ============================================================

#define PZEM_RX_PIN        16
#define PZEM_TX_PIN        17
#define TOMBOL_KONDISI     25
#define TOMBOL_HARI        26
#define TOMBOL_BULAN       27
#define BUZZER_PIN         19
#define RELAY_PIN          14
#define RELAY_ACTIVE_LOW   true

// ============================================================
//  INISIALISASI OBJEK HARDWARE
// ============================================================

HardwareSerial pzemSerial(2);
PZEM004Tv30 pzem(pzemSerial, PZEM_RX_PIN, PZEM_TX_PIN);
LiquidCrystal_I2C lcd(0x27, 20, 2);

// ============================================================
//  STATUS RELAY
//  Pemisahan status: requested_power vs relay_output_state vs relay_control_enabled
// ============================================================

bool requestedPower        = false; // Perintah daya terakhir dari cloud
bool relayOutputState      = false; // Logika sinyal GPIO output relay saat ini
const bool relayControlEnabled = ENABLE_RELAY_CONTROL; // Konfigurasi compile-time

// ============================================================
//  DATA SENSOR & VALIDITAS PEMBACAAN
// ============================================================

float voltage              = NAN;
float current              = NAN;
float power                = NAN;
float energyKwh            = NAN;
float frequency            = NAN;
float pf                   = NAN;

bool  sensorReadSuccess    = false; // Validitas siklus pembacaan sensor terakhir
unsigned long lastValidReadUptimeMs = 0; // millis() saat pembacaan terakhir sukses
unsigned long totalSensorSuccess    = 0;
unsigned long totalSensorFail       = 0;

// ============================================================
//  KALENDER (NTP WIB UTC+7) & AKUMULASI HISTORI (NVS)
// ============================================================

Preferences energyPrefs;

const long GMT_OFFSET_SEC           = 7 * 3600; // WIB (UTC+7)
const int  DAYLIGHT_OFFSET_SEC      = 0;

int  kalenderTahun                  = 0;
int  kalenderBulan                  = -1; // 0..11
int  kalenderHari                   = 0;  // 1..31
int  kalenderHariMinggu             = 0;  // 0=Senin .. 6=Minggu
char kalenderTanggalStr[16]         = ""; // "YYYY-MM-DD"
bool waktuKalenderValid             = false;

float energyAwalHari                = NAN;
float energyAwalBulan               = NAN;
float energiHari                    = 0.0f;
float energiBulan                   = 0.0f;

// Antrean periode selesai yang menunggu sinkronisasi cloud (Pending Queue NVS)
char  pendingDayDate[16]            = "";
int   pendingDayYear                = 0;
float pendingDayKwh                 = 0.0f;
float pendingDayCost                = 0.0f;
int   pendingDayWday                = 0;
bool  hasPendingDay                 = false;

int   pendingMonthYear              = 0;
int   pendingMonthIdx               = -1;
float pendingMonthKwh               = 0.0f;
float pendingMonthCost              = 0.0f;
bool  hasPendingMonth               = false;

// Cache bulanan 0..11 untuk akumulasi summary tahunan nyata
float energiBulanCached[12]         = {0.0f};
float biayaBulanCached[12]          = {0.0f};
bool  monthlyCacheLoaded            = false;
int   tahunTerdaftarDiCloud         = 0;

// ============================================================
//  HALAMAN LCD & NAVIGASI
// ============================================================

int  halaman               = 0;
bool modeTombol            = false;

bool tombolKondisiSebelum  = HIGH;
bool tombolHariSebelum     = HIGH;
bool tombolBulanSebelum    = HIGH;

// ============================================================
//  INTERVAL DAN PENJADWALAN NON-BLOCKING (ROLLOVER-SAFE)
// ============================================================

const unsigned long INTERVAL_HALAMAN        = 3000UL;
const unsigned long WAKTU_TAMPIL_TOMBOL     = 10000UL;
const unsigned long INTERVAL_BACA_PZEM      = 1000UL;
const unsigned long INTERVAL_KIRIM_CLOUD    = 5000UL;
const unsigned long INTERVAL_KIRIM_HISTORI  = 30000UL; // Kirim histori berkala setiap 30 detik
const unsigned long INTERVAL_BACA_CTRL      = 3000UL;
const unsigned long INTERVAL_RETRY_WIFI     = 10000UL; // Reconnect bertahap setiap 10 detik
const unsigned long INTERVAL_RETRY_LOGIN    = 15000UL; // Retry login setiap 15 detik jika gagal
const unsigned long INTERVAL_REFRESH_TOKEN  = 50UL * 60UL * 1000UL; // 50 menit
const unsigned long NETWORK_TIMEOUT_MS      = 3000UL; // Batasi operasi jaringan maks 3 detik

unsigned long waktuHalamanOtomatis  = 0;
unsigned long waktuTombolTerakhir   = 0;
unsigned long waktuBacaPZEMTerakhir = 0;
unsigned long waktuKirimCloudTerakhir = 0;
unsigned long waktuKirimHistoriTerakhir = 0;
unsigned long waktuBacaCtrlTerakhir = 0;
unsigned long waktuCobaWiFiTerakhir = 0;
unsigned long waktuCobaLoginTerakhir = 0;
unsigned long waktuTokenDidapat     = 0; // rollover-safe reference

// ============================================================
//  FIREBASE AUTH & NETWORK STATE
// ============================================================

String firebaseIdToken              = "";
String firebaseRefreshTkn           = "";

bool wifiTerhubung                  = false;
bool firebaseLogin                  = false;
bool wifiConnectingStarted          = false;

// Tarif listrik default (dapat disinkronkan dari control)
float tarifPerKwh                   = 1500.0f;

// Buffer LCD
static char lcdBuf[21];

// ============================================================
//  PROTOTIPE FUNGSI
// ============================================================

void initHardware();
void bacaPZEM();
void hitungEnergi();
void setRelayOutput(bool state);
void tampilKondisi();
void tampilHari();
void tampilBulan();
void tampilPesan(const char* baris1, const char* baris2);
void bunyiBuzzer();
void tanganiTombol();
void rotasiHalamanOtomatis();

void kelolaKoneksiWiFi(unsigned long sekarang);
bool loginFirebase();
bool refreshToken();
bool kirimTelemetriCloud();
bool kirimHistoriCloud();
bool bacaKontrolCloud();
bool periksaWaktuKalender();
bool pastikanTahunTerdaftar();
bool muatRiwayatBulananDariCloud();

String buildAuthUrl();
String buildRefreshUrl();
String buildRtdbLiveUrl();
String buildRtdbControlUrl();
String buildRtdbEnergyUrl();
String buildRtdbAvailableYearsUrl();

// ============================================================
//  SETUP
// ============================================================

void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println();
  Serial.println("==================================================");
  Serial.println("  SIMETRI Firebase Integrated Firmware v1.1.0     ");
#if USE_FIREBASE_EMULATOR
  Serial.println("  Mode Operasi : EMULATOR (HTTP lokal)            ");
  Serial.printf ("  Emulator Host: %s (Auth:%d, RTDB:%d)            \n",
    EMULATOR_HOST, EMULATOR_AUTH_PORT, EMULATOR_RTDB_PORT);
#else
  Serial.println("  Mode Operasi : CLOUD PRODUCTION (HTTPS TLS)     ");
  Serial.println("  Verifikasi   : Root CA GTS Google Trust Services");
#endif
  Serial.printf ("  Relay Control: %s (ENABLE_RELAY_CONTROL=%s)\n",
    relayControlEnabled ? "ENABLED" : "DISABLED (Staging Safe)",
    relayControlEnabled ? "true" : "false");
  Serial.println("==================================================");

  initHardware();

  // Inisialisasi Wi-Fi awal secara non-blocking
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  waktuCobaWiFiTerakhir = millis();
  wifiConnectingStarted = true;
  Serial.printf("[WiFi] Memulai koneksi ke: %s\n", WIFI_SSID);

  // Inisialisasi NVS untuk menjaga akumulasi periode kalender saat ESP32 restart
  energyPrefs.begin("simetri_energy", false);
  int savedYear = energyPrefs.getInt("cal_year", 0);
  int savedMon  = energyPrefs.getInt("cal_mon", -1);
  int savedDay  = energyPrefs.getInt("cal_day", 0);
  float savedDayStart = energyPrefs.getFloat("e_start_day", NAN);
  float savedMonStart = energyPrefs.getFloat("e_start_mon", NAN);
  if (!isnan(savedDayStart) && savedDay > 0) {
    energyAwalHari = savedDayStart;
    kalenderHari   = savedDay;
    Serial.printf("[NVS] Restore baseline harian: %.4f kWh (Hari: %d)\n", energyAwalHari, savedDay);
  }
  if (!isnan(savedMonStart) && savedMon >= 0 && savedYear > 0) {
    energyAwalBulan = savedMonStart;
    kalenderBulan   = savedMon;
    kalenderTahun   = savedYear;
    Serial.printf("[NVS] Restore baseline bulanan: %.4f kWh (Bln: %d, Thn: %d)\n", energyAwalBulan, savedMon + 1, savedYear);
  }

  // Restore antrean pending sync periode selesai jika ada rollover saat offline sebelumnya
  hasPendingDay = energyPrefs.getBool("p_day_pend", false);
  if (hasPendingDay) {
    String sDate = energyPrefs.getString("p_day_date", "");
    strncpy(pendingDayDate, sDate.c_str(), sizeof(pendingDayDate) - 1);
    pendingDayYear = energyPrefs.getInt("p_day_year", 0);
    pendingDayKwh  = energyPrefs.getFloat("p_day_kwh", 0.0f);
    pendingDayCost = energyPrefs.getFloat("p_day_cost", 0.0f);
    pendingDayWday = energyPrefs.getInt("p_day_wday", 0);
    Serial.printf("[NVS] Restore pending completed day: %s (%.3f kWh, Rp %.0f)\n",
      pendingDayDate, pendingDayKwh, pendingDayCost);
  }

  hasPendingMonth = energyPrefs.getBool("p_mon_pend", false);
  if (hasPendingMonth) {
    pendingMonthYear = energyPrefs.getInt("p_mon_year", 0);
    pendingMonthIdx  = energyPrefs.getInt("p_mon_idx", -1);
    pendingMonthKwh  = energyPrefs.getFloat("p_mon_kwh", 0.0f);
    pendingMonthCost = energyPrefs.getFloat("p_mon_cost", 0.0f);
    Serial.printf("[NVS] Restore pending completed month: Thn %d Bln %d (%.3f kWh, Rp %.0f)\n",
      pendingMonthYear, pendingMonthIdx + 1, pendingMonthKwh, pendingMonthCost);
  }

  // Restore cache bulanan 0..11 untuk akumulasi summary tahunan
  for (int m = 0; m < 12; m++) {
    char kE[16], kC[16];
    snprintf(kE, sizeof(kE), "m_kwh_%d", m);
    snprintf(kC, sizeof(kC), "m_cost_%d", m);
    energiBulanCached[m] = energyPrefs.getFloat(kE, 0.0f);
    biayaBulanCached[m]  = energyPrefs.getFloat(kC, 0.0f);
  }

  // Baca energi awal PZEM
  float eAwal = pzem.energy();
  if (!isnan(eAwal)) {
    if (isnan(energyAwalHari))  energyAwalHari  = eAwal;
    if (isnan(energyAwalBulan)) energyAwalBulan = eAwal;
    energyKwh             = eAwal;
    sensorReadSuccess     = true;
    lastValidReadUptimeMs = millis();
    Serial.printf("[PZEM] Energi awal: %.4f kWh\n", eAwal);
  } else {
    Serial.println("[PZEM] Pembacaan awal belum berhasil (sensor standby/belum siap).");
  }

  bacaPZEM();
  tampilKondisi();

  unsigned long now = millis();
  waktuHalamanOtomatis  = now;
  waktuBacaPZEMTerakhir = now;
  waktuKirimCloudTerakhir = now;
  waktuBacaCtrlTerakhir = now;
}

// ============================================================
//  LOOP UTAMA (SEPARATED CONCERNS, NON-BLOCKING)
// ============================================================

void loop() {
  unsigned long sekarang = millis();

  // --- 1. PELAYANAN SENSOR (Setiap 1 Detik, Prioritas Lokal) ---
  if (sekarang - waktuBacaPZEMTerakhir >= INTERVAL_BACA_PZEM) {
    waktuBacaPZEMTerakhir = sekarang;
    bacaPZEM();
    hitungEnergi();

    // Perbarui halaman LCD jika sedang di halaman utama kondisi
    if (!modeTombol && halaman == 0) {
      tampilKondisi();
    }
  }

  // --- 2. PELAYANAN TOMBOL PENGGUNA (Respon Instan) ---
  tanganiTombol();

  // --- 3. ROTASI HALAMAN LCD OTOMATIS ---
  if (!modeTombol) {
    rotasiHalamanOtomatis();
  }

  // --- 4. MANAJEMEN KONEKSI WI-FI BERTAHAP (NON-BLOCKING) ---
  kelolaKoneksiWiFi(sekarang);

  // --- 5. AUTENTIKASI DAN REFRESH TOKEN FIREBASE ---
  if (wifiTerhubung) {
    if (!firebaseLogin) {
      // Retry login dengan jeda terjadwal
      if (sekarang - waktuCobaLoginTerakhir >= INTERVAL_RETRY_LOGIN) {
        waktuCobaLoginTerakhir = sekarang;
        firebaseLogin = loginFirebase();
      }
    } else {
      // Penjadwalan refresh token rollover-safe
      if (sekarang - waktuTokenDidapat >= INTERVAL_REFRESH_TOKEN) {
        Serial.println("[AUTH] Interval refresh token tercapai. Memperbarui token...");
        if (!refreshToken()) {
          Serial.println("[AUTH] Refresh token gagal. Menjadwalkan login ulang...");
          firebaseLogin = false;
        }
      }
    }
  }

  // --- 6. PENGIRIMAN TELEMETRI CLOUD / EMULATOR (Setiap 5 Detik) ---
  if (wifiTerhubung && firebaseLogin && (sekarang - waktuKirimCloudTerakhir >= INTERVAL_KIRIM_CLOUD)) {
    waktuKirimCloudTerakhir = sekarang;
    kirimTelemetriCloud();
  }

  // --- 7. PEMBACAAN PERINTAH KONTROL DARI RTDB (Setiap 3 Detik) ---
  if (wifiTerhubung && firebaseLogin && (sekarang - waktuBacaCtrlTerakhir >= INTERVAL_BACA_CTRL)) {
    waktuBacaCtrlTerakhir = sekarang;
    bacaKontrolCloud();
  }

  // --- 8. SINKRONISASI HISTORI ENERGI KALENDER KE RTDB (Setiap 30 Detik) ---
  if (wifiTerhubung && firebaseLogin && (sekarang - waktuKirimHistoriTerakhir >= INTERVAL_KIRIM_HISTORI)) {
    waktuKirimHistoriTerakhir = sekarang;
    periksaWaktuKalender();
    kirimHistoriCloud();
  }
}

// ============================================================
//  INISIALISASI HARDWARE
// ============================================================

void initHardware() {
  pzemSerial.begin(9600, SERIAL_8N1, PZEM_RX_PIN, PZEM_TX_PIN);

  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  tampilPesan("SIMETRI Firebase", "Inisialisasi...");

  pinMode(TOMBOL_KONDISI, INPUT_PULLUP);
  pinMode(TOMBOL_HARI,    INPUT_PULLUP);
  pinMode(TOMBOL_BULAN,   INPUT_PULLUP);

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  pinMode(RELAY_PIN, OUTPUT);
  setRelayOutput(false); // Default aman: relay OFF
  delay(300);
}

// ============================================================
//  KONTROL RELAY DENGAN PEMISAHAN PERINTAH VS STATUS OUTPUT
// ============================================================

void setRelayOutput(bool state) {
#if ENABLE_RELAY_CONTROL
  // Relay diizinkan beroperasi
  relayOutputState = state;
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? (state ? LOW : HIGH) : (state ? HIGH : LOW));
  Serial.printf("[RELAY] Output GPIO diubah: %s\n", state ? "ON (Tutup)" : "OFF (Buka)");
#else
  // STAGING GUARD: Relay TIDAK diizinkan bergerak
  // relayOutputState selalu false (OFF), tidak pernah diubah oleh perintah yang diabaikan!
  relayOutputState = false;
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
  Serial.printf("[RELAY] Perintah: %s -> DIABAIKAN. Output GPIO tetap OFF (ENABLE_RELAY_CONTROL=false).\n",
    state ? "ON" : "OFF");
#endif
}

// ============================================================
//  PEMBACAAN PZEM-004T DENGAN PENCATATAN VALIDITAS & USIA
// ============================================================

void bacaPZEM() {
  float v = pzem.voltage();
  float i = pzem.current();
  float p = pzem.power();
  float e = pzem.energy();
  float f = pzem.frequency();
  float q = pzem.pf();

  // Validasi pembacaan: tegangan harus valid numerik (bukan NaN) dan bernilai positif
  if (!isnan(v) && v > 0.0f) {
    voltage            = v;
    current            = (!isnan(i) && i >= 0.005f) ? i : 0.0f;
    power              = (!isnan(p) && p >= 0.1f)   ? p : 0.0f;
    if (!isnan(e)) energyKwh = e;
    frequency          = (!isnan(f)) ? f : 50.0f;
    pf                 = (!isnan(q)) ? q : 1.0f;

    sensorReadSuccess     = true;
    lastValidReadUptimeMs = millis();
    totalSensorSuccess++;
  } else {
    // Pembacaan gagal / sensor tidak merespons
    sensorReadSuccess = false;
    totalSensorFail++;
    // JANGAN mengganti nilai dengan 0.0f yang tampak valid!
    // Nilai voltage/current/power dibiarkan NaN untuk menandai status invalid.
    voltage   = NAN;
    current   = NAN;
    power     = NAN;
    frequency = NAN;
    pf        = NAN;
  }
}

void hitungEnergi() {
  periksaWaktuKalender();
  if (!isnan(energyKwh)) {
    if (isnan(energyAwalHari)) {
      energyAwalHari = energyKwh;
      if (waktuKalenderValid) {
        energyPrefs.putFloat("e_start_day", energyAwalHari);
        energyPrefs.putInt("cal_day", kalenderHari);
        energyPrefs.putInt("cal_mon", kalenderBulan);
        energyPrefs.putInt("cal_year", kalenderTahun);
      }
    }
    if (isnan(energyAwalBulan)) {
      energyAwalBulan = energyKwh;
      if (waktuKalenderValid) {
        energyPrefs.putFloat("e_start_mon", energyAwalBulan);
      }
    }
    energiHari = max(0.0f, energyKwh - energyAwalHari);
    energiBulan = max(0.0f, energyKwh - energyAwalBulan);
  }
}

// ============================================================
//  TAMPILAN LCD
// ============================================================

void tampilKondisi() {
  lcd.setCursor(0, 0);
  if (sensorReadSuccess && !isnan(voltage) && !isnan(current)) {
    snprintf(lcdBuf, sizeof(lcdBuf), "V:%.0fV I:%.2fA     ", voltage, current);
  } else {
    snprintf(lcdBuf, sizeof(lcdBuf), "V:-- I:-- [ERR]    ");
  }
  lcd.print(lcdBuf);

  lcd.setCursor(0, 1);
  if (sensorReadSuccess && !isnan(power)) {
    snprintf(lcdBuf, sizeof(lcdBuf), "P:%.0fW              ", power);
  } else {
    snprintf(lcdBuf, sizeof(lcdBuf), "P:-- (Sensor Stale) ");
  }
  lcd.print(lcdBuf);
}

void tampilHari() {
  lcd.setCursor(0, 0);
  snprintf(lcdBuf, sizeof(lcdBuf), "Hari:%.3fkWh      ", energiHari);
  lcd.print(lcdBuf);

  lcd.setCursor(0, 1);
  long biaya = (long)roundf(energiHari * tarifPerKwh);
  snprintf(lcdBuf, sizeof(lcdBuf), "Biaya: Rp%ld       ", biaya);
  lcd.print(lcdBuf);
}

void tampilBulan() {
  lcd.setCursor(0, 0);
  snprintf(lcdBuf, sizeof(lcdBuf), "Bln:%.3fkWh       ", energiBulan);
  lcd.print(lcdBuf);

  lcd.setCursor(0, 1);
  long biaya = (long)roundf(energiBulan * tarifPerKwh);
  snprintf(lcdBuf, sizeof(lcdBuf), "Biaya: Rp%ld       ", biaya);
  lcd.print(lcdBuf);
}

void tampilPesan(const char* baris1, const char* baris2) {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(baris1);
  lcd.setCursor(0, 1);
  lcd.print(baris2);
}

// ============================================================
//  TOMBOL DAN BUZZER
// ============================================================

void bunyiBuzzer() {
  tone(BUZZER_PIN, 1000);
  delay(120);
  noTone(BUZZER_PIN);
}

void tanganiTombol() {
  bool k = digitalRead(TOMBOL_KONDISI);
  bool h = digitalRead(TOMBOL_HARI);
  bool b = digitalRead(TOMBOL_BULAN);

  if (tombolKondisiSebelum == HIGH && k == LOW) {
    halaman = 0; tampilKondisi(); bunyiBuzzer();
    modeTombol = true; waktuTombolTerakhir = millis();
  }
  if (tombolHariSebelum == HIGH && h == LOW) {
    halaman = 1; tampilHari(); bunyiBuzzer();
    modeTombol = true; waktuTombolTerakhir = millis();
  }
  if (tombolBulanSebelum == HIGH && b == LOW) {
    halaman = 2; tampilBulan(); bunyiBuzzer();
    modeTombol = true; waktuTombolTerakhir = millis();
  }

  tombolKondisiSebelum = k;
  tombolHariSebelum    = h;
  tombolBulanSebelum   = b;

  if (modeTombol) {
    if (millis() - waktuTombolTerakhir >= WAKTU_TAMPIL_TOMBOL) {
      modeTombol = false;
      halaman = 0;
      tampilKondisi();
      waktuHalamanOtomatis = millis();
    }
  }
}

void rotasiHalamanOtomatis() {
  if (millis() - waktuHalamanOtomatis >= INTERVAL_HALAMAN) {
    waktuHalamanOtomatis = millis();
    halaman = (halaman + 1) % 3;
    if      (halaman == 0) tampilKondisi();
    else if (halaman == 1) tampilHari();
    else if (halaman == 2) tampilBulan();
  }
}

// ============================================================
//  REKONEKSI WI-FI NON-BLOCKING BERTAHAP
// ============================================================

void kelolaKoneksiWiFi(unsigned long sekarang) {
  wl_status_t status = WiFi.status();

  if (status == WL_CONNECTED) {
    if (!wifiTerhubung) {
      wifiTerhubung = true;
      Serial.printf("[WiFi] Terhubung sukses. IP: %s | RSSI: %d dBm\n",
        WiFi.localIP().toString().c_str(), WiFi.RSSI());
      // Sinkronisasi waktu sistem via SNTP (WIB UTC+7) penting untuk validasi kalender & sertifikat TLS (X.509)
      Serial.println("[NTP] Mengonfigurasi sinkronisasi waktu SNTP (WIB UTC+7)...");
      configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.google.com");
    }
  } else {
    if (wifiTerhubung) {
      Serial.println("[WiFi] Koneksi terputus! Beralih ke offline.");
      wifiTerhubung = false;
      firebaseLogin = false;
    }

    // Reconnect bertahap tanpa memblokir CPU loop
    if (sekarang - waktuCobaWiFiTerakhir >= INTERVAL_RETRY_WIFI) {
      waktuCobaWiFiTerakhir = sekarang;
      Serial.printf("[WiFi] Mencoba menyambung kembali ke %s...\n", WIFI_SSID);
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    }
  }
}

// ============================================================
//  HELPER URL BUILDER (EMULATOR VS CLOUD)
// ============================================================

String buildAuthUrl() {
#if USE_FIREBASE_EMULATOR
  // Auth Emulator lokal via HTTP pada port yang benar
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_AUTH_PORT);
  url += "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=";
  url += FIREBASE_API_KEY;
  return url;
#else
  // Cloud Google Auth via HTTPS
  String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=";
  url += FIREBASE_API_KEY;
  return url;
#endif
}

String buildRefreshUrl() {
#if USE_FIREBASE_EMULATOR
  // Auth Emulator token refresh endpoint via HTTP
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_AUTH_PORT);
  url += "/securetoken.googleapis.com/v1/token?key=";
  url += FIREBASE_API_KEY;
  return url;
#else
  String url = "https://securetoken.googleapis.com/v1/token?key=";
  url += FIREBASE_API_KEY;
  return url;
#endif
}

String buildRtdbLiveUrl() {
#if USE_FIREBASE_EMULATOR
  // RTDB Emulator via HTTP dengan namespace parameter eksplisit
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_RTDB_PORT);
  url += "/devices/";
  url += DEVICE_ID;
  url += "/live.json?ns=";
  url += FIREBASE_RTDB_NAMESPACE;
  url += "&auth=";
  url += firebaseIdToken;
  return url;
#else
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/devices/";
  url += DEVICE_ID;
  url += "/live.json?auth=";
  url += firebaseIdToken;
  return url;
#endif
}

String buildRtdbControlUrl() {
#if USE_FIREBASE_EMULATOR
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_RTDB_PORT);
  url += "/devices/";
  url += DEVICE_ID;
  url += "/control.json?ns=";
  url += FIREBASE_RTDB_NAMESPACE;
  url += "&auth=";
  url += firebaseIdToken;
  return url;
#else
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/devices/";
  url += DEVICE_ID;
  url += "/control.json?auth=";
  url += firebaseIdToken;
  return url;
#endif
}

String buildRtdbEnergyUrl() {
#if USE_FIREBASE_EMULATOR
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_RTDB_PORT);
  url += "/energy_data/";
  url += DEVICE_ID;
  url += ".json?ns=";
  url += FIREBASE_RTDB_NAMESPACE;
  url += "&auth=";
  url += firebaseIdToken;
  return url;
#else
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/energy_data/";
  url += DEVICE_ID;
  url += ".json?auth=";
  url += firebaseIdToken;
  return url;
#endif
}

String buildRtdbAvailableYearsUrl() {
#if USE_FIREBASE_EMULATOR
  String url = "http://";
  url += EMULATOR_HOST;
  url += ":";
  url += String(EMULATOR_RTDB_PORT);
  url += "/energy_data/";
  url += DEVICE_ID;
  url += "/available_years.json?ns=";
  url += FIREBASE_RTDB_NAMESPACE;
  url += "&auth=";
  url += firebaseIdToken;
  return url;
#else
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/energy_data/";
  url += DEVICE_ID;
  url += "/available_years.json?auth=";
  url += firebaseIdToken;
  return url;
#endif
}

// ============================================================
//  AUTENTIKASI FIREBASE (LOGIN EMAIL / PASSWORD)
// ============================================================

bool loginFirebase() {
  Serial.println("[AUTH] Memulai autentikasi ke Firebase...");

#if !USE_FIREBASE_EMULATOR
  // Pastikan jam sistem sudah tersinkronisasi via SNTP agar verifikasi sertifikat TLS valid
  time_t nowSec = time(nullptr);
  if (nowSec < 1600000000) {
    Serial.println("[NTP] Menunggu sinkronisasi waktu sebelum autentikasi TLS...");
    int ntpWait = 0;
    while (time(nullptr) < 1600000000 && ntpWait < 15) {
      delay(200);
      ntpWait++;
    }
    nowSec = time(nullptr);
    if (nowSec >= 1600000000) {
      Serial.printf("[NTP] Waktu sistem tersinkronisasi: %ld\n", (long)nowSec);
    } else {
      Serial.println("[NTP] Peringatan: Jam sistem belum sinkron. Handshake TLS mungkin gagal.");
    }
  }
#endif

  String url = buildAuthUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) {
    Serial.println("[AUTH] Gagal inisialisasi HTTPClient emulator.");
    return false;
  }
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA); // Verifikasi CA Root asli, TANPA setInsecure()!
  if (!http.begin(secureClient, url)) {
    Serial.println("[AUTH] Gagal inisialisasi HTTPClient secure.");
    return false;
  }
#endif

  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<256> reqDoc;
  reqDoc["email"]             = DEVICE_EMAIL;
  reqDoc["password"]          = DEVICE_PASSWORD;
  reqDoc["returnSecureToken"] = true;

  String bodyStr;
  serializeJson(reqDoc, bodyStr);

  int httpCode = http.POST(bodyStr);

  if (httpCode != 200) {
    Serial.printf("[AUTH] Login gagal. Kode HTTP: %d\n", httpCode);
    if (httpCode > 0) {
      String resp = http.getString();
      StaticJsonDocument<256> errDoc;
      if (deserializeJson(errDoc, resp) == DeserializationError::Ok) {
        const char* errMsg = errDoc["error"]["message"] | "unknown";
        Serial.printf("[AUTH] Alasan: %s\n", errMsg);
      }
    }
    http.end();
    return false;
  }

  String resp = http.getString();
  http.end();

  // Alokasi kapasitas JSON cukup untuk response Auth token (~800-1000 byte)
  DynamicJsonDocument doc(2048);
  DeserializationError err = deserializeJson(doc, resp);
  if (err != DeserializationError::Ok) {
    Serial.printf("[AUTH] Parse response gagal: %s\n", err.c_str());
    return false;
  }

  // Validasi keberadaan dan non-empty token
  if (!doc.containsKey("idToken") || !doc.containsKey("refreshToken")) {
    Serial.println("[AUTH] Response valid tetapi token tidak ditemukan.");
    return false;
  }

  String idTok  = doc["idToken"].as<String>();
  String refTok = doc["refreshToken"].as<String>();

  if (idTok.isEmpty() || refTok.isEmpty()) {
    Serial.println("[AUTH] Token bernilai string kosong.");
    return false;
  }

  firebaseIdToken    = idTok;
  firebaseRefreshTkn = refTok;
  waktuTokenDidapat  = millis();

  Serial.println("[AUTH] Login berhasil! ID Token dan Refresh Token tersimpan.");
  return true;
}

// ============================================================
//  REFRESH TOKEN OTOMATIS
// ============================================================

bool refreshToken() {
  if (firebaseRefreshTkn.isEmpty()) {
    Serial.println("[AUTH] Refresh token kosong. Wajib login ulang.");
    return false;
  }

  String url = buildRefreshUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  http.addHeader("Content-Type", "application/x-www-form-urlencoded");

  String bodyStr = "grant_type=refresh_token&refresh_token=";
  bodyStr += firebaseRefreshTkn;

  int httpCode = http.POST(bodyStr);
  if (httpCode != 200) {
    Serial.printf("[AUTH] Refresh token gagal. HTTP %d\n", httpCode);
    http.end();
    return false;
  }

  String resp = http.getString();
  http.end();

  DynamicJsonDocument doc(2048);
  if (deserializeJson(doc, resp) != DeserializationError::Ok) {
    Serial.println("[AUTH] Parse respons refresh token gagal.");
    return false;
  }

  // Google token endpoint mengembalikan "id_token" dan "refresh_token"
  String newIdTok  = doc["id_token"].as<String>();
  String newRefTok = doc["refresh_token"].as<String>();

  if (newIdTok.isEmpty()) {
    Serial.println("[AUTH] ID token baru kosong dari refresh.");
    return false;
  }

  firebaseIdToken   = newIdTok;
  if (!newRefTok.isEmpty()) {
    firebaseRefreshTkn = newRefTok;
  }
  waktuTokenDidapat = millis();

  Serial.println("[AUTH] Token berhasil diperbarui secara berkala.");
  return true;
}

// ============================================================
//  KIRIM TELEMETRI KE REALTIME DATABASE
// ============================================================

bool kirimTelemetriCloud() {
  if (firebaseIdToken.isEmpty()) {
    return false;
  }

  unsigned long sekarang = millis();
  unsigned long usiaPembacaanMs = (lastValidReadUptimeMs > 0) ? (sekarang - lastValidReadUptimeMs) : 0;

  String url = buildRtdbLiveUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<768> doc;

  // Status validitas sensor eksplisit
  doc["sensor_valid"]         = sensorReadSuccess;
  doc["reading_age_ms"]       = usiaPembacaanMs;
  doc["last_read_uptime_ms"]  = lastValidReadUptimeMs;

  // Hanya isi nilai jika pembacaan sensor berhasil; jika gagal kirim null (jangan angka 0 palsu)
  if (sensorReadSuccess && !isnan(voltage)) {
    doc["voltage"]            = voltage;
    doc["current"]            = current;
    doc["power"]              = power;
    doc["frequency"]          = frequency;
    doc["power_factor"]       = pf;
  } else {
    doc["voltage"]            = nullptr;
    doc["current"]            = nullptr;
    doc["power"]              = nullptr;
    doc["frequency"]          = nullptr;
    doc["power_factor"]       = nullptr;
    doc["sensor_status"]      = "stale_or_disconnected";
  }

  float dailyCost = (float)roundf(energiHari * tarifPerKwh);
  float monthlyCost = (float)roundf(energiBulan * tarifPerKwh);

  doc["energy_kwh"]           = isnan(energyKwh) ? (float)0.0 : energyKwh;
  doc["daily_energy"]         = energiHari;
  doc["monthly_energy"]       = energiBulan;
  doc["daily_cost"]           = dailyCost;
  doc["monthly_cost"]         = monthlyCost;
  doc["tariff_per_kwh"]       = tarifPerKwh;

  // Pemisahan status relay
  doc["requested_power"]      = requestedPower;
  doc["relay_output_state"]   = relayOutputState;
  doc["relay_control_enabled"] = relayControlEnabled;

  // Uptime terpisah dari server timestamp
  doc["uptime_ms"]            = sekarang;
  doc["sent_uptime_ms"]       = sekarang;

  // Firebase Realtime Database Server Timestamp
  JsonObject serverTs = doc.createNestedObject("server_timestamp");
  serverTs[".sv"] = "timestamp";

  String payload;
  serializeJson(doc, payload);

  int httpCode = http.PUT(payload);

  if (httpCode == 200 || httpCode == 204) {
    if (sensorReadSuccess) {
      Serial.printf("[RTDB] Telemetri terkirim: V=%.1fV P=%.1fW kWh=%.4f (age: %lu ms)\n",
        voltage, power, energyKwh, usiaPembacaanMs);
    } else {
      Serial.printf("[RTDB] Status telemetri terkirim: SENSOR ERROR/STALE (age: %lu ms)\n",
        usiaPembacaanMs);
    }
    http.end();
    return true;
  } else {
    Serial.printf("[RTDB] Gagal kirim telemetri. HTTP: %d\n", httpCode);
    if (httpCode == 401) {
      Serial.println("[RTDB] Unauthorized (token expired). Memicu login ulang.");
      firebaseLogin = false;
    }
    http.end();
    return false;
  }
}

// ============================================================
//  BACA PERINTAH KONTROL DARI REALTIME DATABASE
// ============================================================

bool bacaKontrolCloud() {
  if (firebaseIdToken.isEmpty()) {
    return false;
  }

  String url = buildRtdbControlUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  int httpCode = http.GET();

  if (httpCode == 200) {
    String resp = http.getString();
    http.end();
    resp.trim();

    StaticJsonDocument<384> ctrlDoc;
    DeserializationError err = deserializeJson(ctrlDoc, resp);

    if (!err && ctrlDoc.is<JsonObject>()) {
      // 1. Parsing status daya / relay
      if (ctrlDoc.containsKey("power")) {
        bool p = ctrlDoc["power"].as<bool>();
        requestedPower = p;
        setRelayOutput(p);
      }
      // 2. Parsing tarif listrik per kWh (validasi numerik positif dan masuk akal)
      if (ctrlDoc.containsKey("tariff_per_kwh")) {
        float newTariff = ctrlDoc["tariff_per_kwh"].as<float>();
        if (!isnan(newTariff) && newTariff >= 100.0f && newTariff <= 50000.0f) {
          if (fabs(tarifPerKwh - newTariff) > 0.01f) {
            tarifPerKwh = newTariff;
            Serial.printf("[CTRL] Tarif listrik baru diterapkan: Rp %.2f /kWh\n", tarifPerKwh);
          }
        } else {
          Serial.printf("[CTRL] Nilai tarif tidak valid (%.2f) — diabaikan.\n", newTariff);
        }
      }
      return true;
    } else if (resp == "true") {
      requestedPower = true;
      Serial.println("[CTRL] Perintah daya diterima: ON (true)");
      setRelayOutput(true);
      return true;
    } else if (resp == "false") {
      requestedPower = false;
      Serial.println("[CTRL] Perintah daya diterima: OFF (false)");
      setRelayOutput(false);
      return true;
    } else {
      // Nilai adalah null, kosong, atau string lain: JANGAN ubah status relay!
      Serial.printf("[CTRL] Nilai kontrol tidak dikenali ('%s') — diabaikan.\n", resp.c_str());
      return false;
    }
  } else if (httpCode == 401) {
    Serial.println("[CTRL] Unauthorized (token expired). Memicu login ulang.");
    firebaseLogin = false;
    http.end();
    return false;
  } else {
    http.end();
    return false;
  }
}

// ============================================================
//  PEMANTAUAN KALENDER (WIB UTC+7) & ROLLOVER ENERGI HARIAN/BULANAN
// ============================================================

bool periksaWaktuKalender() {
  time_t nowSec = time(nullptr);
  if (nowSec < 1600000000) {
    waktuKalenderValid = false;
    return false;
  }

  struct tm timeinfo;
  if (!localtime_r(&nowSec, &timeinfo)) {
    return false;
  }

  int tahun = timeinfo.tm_year + 1900;
  int bulan = timeinfo.tm_mon;            // 0..11
  int hari  = timeinfo.tm_mday;           // 1..31
  int hariM = (timeinfo.tm_wday + 6) % 7; // 0=Senin .. 6=Minggu

  if (!waktuKalenderValid) {
    waktuKalenderValid = true;
    kalenderTahun = tahun;
    kalenderBulan = bulan;
    kalenderHari  = hari;
    kalenderHariMinggu = hariM;
    snprintf(kalenderTanggalStr, sizeof(kalenderTanggalStr), "%04d-%02d-%02d", tahun, bulan + 1, hari);

    int savedYear = energyPrefs.getInt("cal_year", 0);
    int savedMon  = energyPrefs.getInt("cal_mon", -1);
    int savedDay  = energyPrefs.getInt("cal_day", 0);

    // Cek apakah tanggal saat ini berbeda dari tanggal NVS (restart setelah ganti hari/bulan saat offline)
    if (savedYear > 0 && (savedYear != tahun || savedMon != bulan || savedDay != hari)) {
      Serial.printf("[KALENDER] Tanggal berganti saat restart/offline: %04d-%02d-%02d -> %s\n",
        savedYear, savedMon + 1, savedDay, kalenderTanggalStr);

      if (!isnan(energyAwalHari) && !isnan(energyKwh)) {
        float lastDayKwh = max(0.0f, energyKwh - energyAwalHari);
        float lastDayCost = (float)roundf(lastDayKwh * tarifPerKwh);

        snprintf(pendingDayDate, sizeof(pendingDayDate), "%04d-%02d-%02d", savedYear, savedMon + 1, savedDay);
        pendingDayYear = savedYear;
        pendingDayKwh  = lastDayKwh;
        pendingDayCost = lastDayCost;
        pendingDayWday = (timeinfo.tm_wday + 5) % 7;
        hasPendingDay  = true;

        energyPrefs.putString("p_day_date", pendingDayDate);
        energyPrefs.putInt("p_day_year", pendingDayYear);
        energyPrefs.putFloat("p_day_kwh", pendingDayKwh);
        energyPrefs.putFloat("p_day_cost", pendingDayCost);
        energyPrefs.putInt("p_day_wday", pendingDayWday);
        energyPrefs.putBool("p_day_pend", true);
      }

      if (!isnan(energyKwh)) {
        energyAwalHari = energyKwh;
        energiHari     = 0.0f;
        energyPrefs.putFloat("e_start_day", energyAwalHari);
        energyPrefs.putInt("cal_day", hari);

        if (savedYear != tahun || savedMon != bulan) {
          energyAwalBulan = energyKwh;
          energiBulan     = 0.0f;
          energyPrefs.putFloat("e_start_mon", energyAwalBulan);
          energyPrefs.putInt("cal_mon", bulan);
          energyPrefs.putInt("cal_year", tahun);
        }
      }
    } else {
      Serial.printf("[KALENDER] Tanggal kalender sinkron dengan NVS: %s (Wday %d)\n", kalenderTanggalStr, hariM);
    }
    return true;
  }

  // Cek apakah tanggal kalender berganti (rollover tengah malam 00:00 WIB saat modul aktif)
  if (hari != kalenderHari || bulan != kalenderBulan || tahun != kalenderTahun) {
    Serial.printf("[KALENDER] Rollover hari terdeteksi: %s -> %04d-%02d-%02d\n",
      kalenderTanggalStr, tahun, bulan + 1, hari);

    if (!isnan(energyKwh)) {
      // Simpan hari yang selesai ke antrean pending
      snprintf(pendingDayDate, sizeof(pendingDayDate), "%04d-%02d-%02d", kalenderTahun, kalenderBulan + 1, kalenderHari);
      pendingDayYear = kalenderTahun;
      pendingDayKwh  = energiHari;
      pendingDayCost = (float)roundf(energiHari * tarifPerKwh);
      pendingDayWday = kalenderHariMinggu;
      hasPendingDay  = true;

      energyPrefs.putString("p_day_date", pendingDayDate);
      energyPrefs.putInt("p_day_year", pendingDayYear);
      energyPrefs.putFloat("p_day_kwh", pendingDayKwh);
      energyPrefs.putFloat("p_day_cost", pendingDayCost);
      energyPrefs.putInt("p_day_wday", pendingDayWday);
      energyPrefs.putBool("p_day_pend", true);

      // Jika bulan juga berganti
      if (bulan != kalenderBulan || tahun != kalenderTahun) {
        Serial.printf("[KALENDER] Rollover bulan terdeteksi: %02d -> %02d\n", kalenderBulan + 1, bulan + 1);
        pendingMonthYear = kalenderTahun;
        pendingMonthIdx  = kalenderBulan;
        pendingMonthKwh  = energiBulan;
        pendingMonthCost = (float)roundf(energiBulan * tarifPerKwh);
        hasPendingMonth  = true;

        energyPrefs.putInt("p_mon_year", pendingMonthYear);
        energyPrefs.putInt("p_mon_idx", pendingMonthIdx);
        energyPrefs.putFloat("p_mon_kwh", pendingMonthKwh);
        energyPrefs.putFloat("p_mon_cost", pendingMonthCost);
        energyPrefs.putBool("p_mon_pend", true);

        // Catat ke cache bulanan tahunan
        energiBulanCached[kalenderBulan] = pendingMonthKwh;
        biayaBulanCached[kalenderBulan]  = pendingMonthCost;
        char kE[16], kC[16];
        snprintf(kE, sizeof(kE), "m_kwh_%d", kalenderBulan);
        snprintf(kC, sizeof(kC), "m_cost_%d", kalenderBulan);
        energyPrefs.putFloat(kE, pendingMonthKwh);
        energyPrefs.putFloat(kC, pendingMonthCost);

        // Reset baseline bulan baru
        energyAwalBulan = energyKwh;
        energiBulan     = 0.0f;
        energyPrefs.putFloat("e_start_mon", energyAwalBulan);
        energyPrefs.putInt("cal_mon", bulan);
        energyPrefs.putInt("cal_year", tahun);

        // Jika tahun berganti, reset cache bulanan untuk tahun baru
        if (tahun != kalenderTahun) {
          for (int m = 0; m < 12; m++) {
            energiBulanCached[m] = 0.0f;
            biayaBulanCached[m]  = 0.0f;
            char ckE[16], ckC[16];
            snprintf(ckE, sizeof(ckE), "m_kwh_%d", m);
            snprintf(ckC, sizeof(ckC), "m_cost_%d", m);
            energyPrefs.putFloat(ckE, 0.0f);
            energyPrefs.putFloat(ckC, 0.0f);
          }
          tahunTerdaftarDiCloud = 0;
        }
      }

      // Reset baseline hari baru
      energyAwalHari = energyKwh;
      energiHari     = 0.0f;
      energyPrefs.putFloat("e_start_day", energyAwalHari);
      energyPrefs.putInt("cal_day", hari);
    }

    kalenderTahun = tahun;
    kalenderBulan = bulan;
    kalenderHari  = hari;
    kalenderHariMinggu = hariM;
    snprintf(kalenderTanggalStr, sizeof(kalenderTanggalStr), "%04d-%02d-%02d", tahun, bulan + 1, hari);
    energyPrefs.putString("cal_date", kalenderTanggalStr);
  }

  return true;
}

// ============================================================
//  PENDAFTARAN TAHUN KE AVAILABLE_YEARS SECARA NON-DESTRUKTIF
// ============================================================

bool pastikanTahunTerdaftar() {
  if (tahunTerdaftarDiCloud == kalenderTahun) return true;
  if (firebaseIdToken.isEmpty() || kalenderTahun < 2024) return false;

  String url = buildRtdbAvailableYearsUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  int httpCode = http.GET();
  bool sudahAda = false;
  int daftarTahun[10];
  int countTahun = 0;

  if (httpCode == 200) {
    String resp = http.getString();
    http.end();
    resp.trim();
    DynamicJsonDocument doc(512);
    if (deserializeJson(doc, resp) == DeserializationError::Ok) {
      if (doc.is<JsonArray>()) {
        for (JsonVariant v : doc.as<JsonArray>()) {
          int y = v.as<int>();
          if (y > 2000 && countTahun < 10) {
            daftarTahun[countTahun++] = y;
            if (y == kalenderTahun) sudahAda = true;
          }
        }
      } else if (doc.is<JsonObject>()) {
        for (JsonPair kv : doc.as<JsonObject>()) {
          int y = kv.value().as<int>();
          if (y > 2000 && countTahun < 10) {
            daftarTahun[countTahun++] = y;
            if (y == kalenderTahun) sudahAda = true;
          }
        }
      }
    }
  } else {
    http.end();
  }

  if (sudahAda) {
    tahunTerdaftarDiCloud = kalenderTahun;
    return true;
  }

  if (countTahun < 10) {
    daftarTahun[countTahun++] = kalenderTahun;
  }

  // Urutkan tahun secara descending
  for (int i = 0; i < countTahun - 1; i++) {
    for (int j = i + 1; j < countTahun; j++) {
      if (daftarTahun[i] < daftarTahun[j]) {
        int tmp = daftarTahun[i];
        daftarTahun[i] = daftarTahun[j];
        daftarTahun[j] = tmp;
      }
    }
  }

  DynamicJsonDocument putDoc(512);
  JsonArray arr = putDoc.to<JsonArray>();
  for (int i = 0; i < countTahun; i++) {
    arr.add(daftarTahun[i]);
  }
  String putPayload;
  serializeJson(arr, putPayload);

  HTTPClient putHttp;
  putHttp.setTimeout(NETWORK_TIMEOUT_MS);
#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient2;
  if (!putHttp.begin(plainClient2, url)) return false;
#else
  WiFiClientSecure secureClient2;
  secureClient2.setCACert(GOOGLE_ROOT_CA);
  if (!putHttp.begin(secureClient2, url)) return false;
#endif
  putHttp.addHeader("Content-Type", "application/json");
  int putCode = putHttp.PUT(putPayload);
  putHttp.end();

  if (putCode == 200 || putCode == 204) {
    tahunTerdaftarDiCloud = kalenderTahun;
    Serial.printf("[HISTORI] Tahun %d berhasil digabungkan ke available_years (total %d tahun)\n",
      kalenderTahun, countTahun);
    return true;
  }
  return false;
}

// ============================================================
//  MUAT RIWAYAT BULANAN TAHUN INI DARI CLOUD (SATU KALI DI AWAL)
// ============================================================

bool muatRiwayatBulananDariCloud() {
  if (monthlyCacheLoaded || firebaseIdToken.isEmpty() || kalenderTahun < 2024) return true;

  String url = "https://" + String(FIREBASE_HOST) + "/energy_data/" + String(DEVICE_ID) + "/" + String(kalenderTahun) + "/monthly_energy.json?auth=" + firebaseIdToken;
#if USE_FIREBASE_EMULATOR
  url = "http://" + String(EMULATOR_HOST) + ":" + String(EMULATOR_RTDB_PORT) + "/energy_data/" + String(DEVICE_ID) + "/" + String(kalenderTahun) + "/monthly_energy.json?ns=" + String(FIREBASE_RTDB_NAMESPACE) + "&auth=" + firebaseIdToken;
#endif

  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);
#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  int code = http.GET();
  if (code == 200) {
    String resp = http.getString();
    http.end();
    DynamicJsonDocument doc(512);
    if (deserializeJson(doc, resp) == DeserializationError::Ok) {
      if (doc.is<JsonObject>()) {
        for (JsonPair kv : doc.as<JsonObject>()) {
          int m = atoi(kv.key().c_str());
          if (m >= 0 && m < 12 && m != kalenderBulan) {
            energiBulanCached[m] = kv.value().as<float>();
          }
        }
      }
    }
    monthlyCacheLoaded = true;
    Serial.println("[HISTORI] Riwayat energi bulanan tahunan tersinkronisasi dari RTDB.");
    return true;
  }
  http.end();
  return false;
}

// ============================================================
//  PENGIRIMAN HISTORI ENERGI & BIAYA KE REALTIME DATABASE
// ============================================================

bool kirimHistoriCloud() {
  if (firebaseIdToken.isEmpty() || !waktuKalenderValid || kalenderTahun < 2024 || isnan(energyKwh)) {
    return false;
  }

  // Pastikan tahun terdaftar secara non-destruktif
  pastikanTahunTerdaftar();

  // Muat riwayat bulanan tahun ini dari cloud jika belum ada di cache
  if (!monthlyCacheLoaded) {
    muatRiwayatBulananDariCloud();
  }

  String url = buildRtdbEnergyUrl();
  HTTPClient http;
  http.setTimeout(NETWORK_TIMEOUT_MS);

#if USE_FIREBASE_EMULATOR
  WiFiClient plainClient;
  if (!http.begin(plainClient, url)) return false;
#else
  WiFiClientSecure secureClient;
  secureClient.setCACert(GOOGLE_ROOT_CA);
  if (!http.begin(secureClient, url)) return false;
#endif

  http.addHeader("Content-Type", "application/json");

  float dailyCost   = (float)roundf(energiHari * tarifPerKwh);
  float monthlyCost = (float)roundf(energiBulan * tarifPerKwh);

  energiBulanCached[kalenderBulan] = energiBulan;
  biayaBulanCached[kalenderBulan]  = monthlyCost;

  // Summary tahunan: hitung seluruh bulan yang tersedia di tahun berjalan
  float totalTahunEnergi = 0.0f;
  float totalTahunBiaya  = 0.0f;
  for (int m = 0; m < 12; m++) {
    totalTahunEnergi += energiBulanCached[m];
    totalTahunBiaya  += biayaBulanCached[m];
  }

  DynamicJsonDocument doc(1024);
  char keyBuf[80];

  // A. Arsip Harian Permanen (format tanggal lengkap YYYY-MM-DD)
  snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/energy_kwh", kalenderTahun, kalenderTanggalStr);
  doc[keyBuf] = energiHari;
  snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/cost_rp", kalenderTahun, kalenderTanggalStr);
  doc[keyBuf] = dailyCost;
  snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/day_of_week", kalenderTahun, kalenderTanggalStr);
  doc[keyBuf] = kalenderHariMinggu;
  snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/last_updated", kalenderTahun, kalenderTanggalStr);
  JsonObject tsDaily = doc.createNestedObject(keyBuf);
  tsDaily[".sv"] = "timestamp";

  // B. Ringkasan Mingguan untuk Grafik 7-Hari Aplikasi (Senin=0 .. Minggu=6)
  snprintf(keyBuf, sizeof(keyBuf), "%d/weekly_energy/%d", kalenderTahun, kalenderHariMinggu);
  doc[keyBuf] = energiHari;
  snprintf(keyBuf, sizeof(keyBuf), "%d/weekly_cost/%d", kalenderTahun, kalenderHariMinggu);
  doc[keyBuf] = dailyCost;

  // C. Ringkasan Bulanan (Januari=0 .. Desember=11)
  snprintf(keyBuf, sizeof(keyBuf), "%d/monthly_energy/%d", kalenderTahun, kalenderBulan);
  doc[keyBuf] = energiBulan;
  snprintf(keyBuf, sizeof(keyBuf), "%d/monthly_cost/%d", kalenderTahun, kalenderBulan);
  doc[keyBuf] = monthlyCost;

  // D. Summary Tahunan Nyata (Akumulasi seluruh bulan yang tersedia di tahun ini)
  snprintf(keyBuf, sizeof(keyBuf), "%d/summary/total_energy", kalenderTahun);
  doc[keyBuf] = totalTahunEnergi;
  snprintf(keyBuf, sizeof(keyBuf), "%d/summary/total_cost", kalenderTahun);
  doc[keyBuf] = totalTahunBiaya;
  snprintf(keyBuf, sizeof(keyBuf), "%d/summary/last_updated", kalenderTahun);
  JsonObject tsSummary = doc.createNestedObject(keyBuf);
  tsSummary[".sv"] = "timestamp";

  // E. Sinkronisasi Periode Pending (jika sempat rollover saat offline)
  if (hasPendingDay && strlen(pendingDayDate) > 0) {
    snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/energy_kwh", pendingDayYear, pendingDayDate);
    doc[keyBuf] = pendingDayKwh;
    snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/cost_rp", pendingDayYear, pendingDayDate);
    doc[keyBuf] = pendingDayCost;
    snprintf(keyBuf, sizeof(keyBuf), "%d/daily_history/%s/day_of_week", pendingDayYear, pendingDayDate);
    doc[keyBuf] = pendingDayWday;
  }
  if (hasPendingMonth && pendingMonthIdx >= 0) {
    snprintf(keyBuf, sizeof(keyBuf), "%d/monthly_energy/%d", pendingMonthYear, pendingMonthIdx);
    doc[keyBuf] = pendingMonthKwh;
    snprintf(keyBuf, sizeof(keyBuf), "%d/monthly_cost/%d", pendingMonthYear, pendingMonthIdx);
    doc[keyBuf] = pendingMonthCost;
  }

  String payload;
  serializeJson(doc, payload);

  int httpCode = http.sendRequest("PATCH", payload);

  if (httpCode == 200 || httpCode == 204) {
    Serial.printf("[HISTORI] Sinkronisasi sukses (Tgl: %s | Bln %d=%.3fkWh | Thn %d=%.3fkWh Rp%.0f)\n",
      kalenderTanggalStr, kalenderBulan + 1, energiBulan, kalenderTahun, totalTahunEnergi, totalTahunBiaya);

    if (hasPendingDay) {
      hasPendingDay = false;
      energyPrefs.putBool("p_day_pend", false);
    }
    if (hasPendingMonth) {
      hasPendingMonth = false;
      energyPrefs.putBool("p_mon_pend", false);
    }

    http.end();
    return true;
  } else {
    Serial.printf("[HISTORI] Gagal sinkronisasi histori. HTTP: %d\n", httpCode);
    if (httpCode == 401) {
      Serial.println("[HISTORI] Unauthorized (token expired). Memicu login ulang.");
      firebaseLogin = false;
    }
    http.end();
    return false;
  }
}

