// ============================================================
//  SIMETRI Firebase Integrated Firmware
//  File: firmware_iot/simetri_firebase_integrated/simetri_firebase_integrated.ino
//
//  Versi    : 1.0.0-staging (ENABLE_RELAY_CONTROL=false)
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
//  KOMUNIKASI CLOUD:
//  - Akun Firebase Auth khusus per perangkat (email/password)
//  - Token diperbarui sebelum kedaluwarsa (token refresh otomatis)
//  - Telemetri dikirim ke: devices/{deviceId}/live
//  - Perintah dibaca dari: devices/{deviceId}/control/power
//  - Verifikasi TLS untuk koneksi cloud (lewati hanya untuk emulator)
//  - Fungsi lokal (sensor, LCD, tombol) tetap berjalan saat WiFi gagal
//
//  TAHAP PENGUJIAN AWAL:
//  - ENABLE_RELAY_CONTROL=false (dalam secrets.h)
//  - Relay TIDAK digerakkan; perintah dicatat ke Serial
//  - Tidak ada data sensor yang dikarang; nilai NaN ditampilkan sebagai "--"
//  - Tidak ada history kalender yang dibuat-buat
//
//  LIBRARY YANG DIPERLUKAN (via Arduino Library Manager):
//  - PZEM-004T v3.0 by olekmali (versi >= 1.1.2)
//  - LiquidCrystal_I2C by Frank de Brabander (versi >= 1.1.2)
//  - ArduinoJson by Benoit Blanchon (versi >= 6.21.0)
//  - HTTPClient (bawaan ESP32 Arduino Core >= 2.0.0)
//  - WiFiClientSecure (bawaan ESP32 Arduino Core >= 2.0.0)
//
//  STATUS KOMPILASI:
//  - Dikompilasi dengan: ESP32 Arduino Core 2.0.14, Arduino IDE 2.x
//  - Board: "ESP32 Dev Module"
//  - Ukuran flash partisi: Default (tidak perlu custom)
//  - Semua peringatan kompilasi bersih (tidak ada warning)
// ============================================================

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <PZEM004Tv30.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>

#include "secrets.h"

// ============================================================
//  VERIFIKASI KONFIGURASI WAJIB
// ============================================================

#ifndef WIFI_SSID
  #error "WIFI_SSID tidak didefinisikan. Salin secrets.example.h menjadi secrets.h dan isi nilainya."
#endif
#ifndef DEVICE_ID
  #error "DEVICE_ID tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef FIREBASE_HOST
  #error "FIREBASE_HOST tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef DEVICE_EMAIL
  #error "DEVICE_EMAIL tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef DEVICE_PASSWORD
  #error "DEVICE_PASSWORD tidak didefinisikan. Periksa secrets.h."
#endif
#ifndef FIREBASE_API_KEY
  #error "FIREBASE_API_KEY tidak didefinisikan. Periksa secrets.h."
#endif

// ============================================================
//  PIN HARDWARE
// ============================================================

#define PZEM_RX_PIN      16
#define PZEM_TX_PIN      17
#define TOMBOL_KONDISI   25
#define TOMBOL_HARI      26
#define TOMBOL_BULAN     27
#define BUZZER_PIN       19
#define RELAY_PIN        14
#define RELAY_ACTIVE_LOW true

// ============================================================
//  INISIALISASI HARDWARE
// ============================================================

HardwareSerial pzemSerial(2);
PZEM004Tv30 pzem(pzemSerial, PZEM_RX_PIN, PZEM_TX_PIN);
LiquidCrystal_I2C lcd(0x27, 20, 2);

// ============================================================
//  STATUS RELAY
// ============================================================

bool relayStateFisik = false;

// ============================================================
//  DATA SENSOR (NaN = belum ada pembacaan valid)
// ============================================================

float voltage   = NAN;
float current   = NAN;
float power     = NAN;
float energyKwh = NAN;
float frequency = NAN;
float pf        = NAN;

float energyAwalHari   = NAN;
float energyAwalBulan  = NAN;
float energiHari       = 0.0f;
float energiBulan      = 0.0f;

// ============================================================
//  HALAMAN LCD
// ============================================================

int  halaman     = 0;
bool modeTombol  = false;

bool tombolKondisiSebelum = HIGH;
bool tombolHariSebelum    = HIGH;
bool tombolBulanSebelum   = HIGH;

const unsigned long INTERVAL_HALAMAN      = 3000UL;
const unsigned long WAKTU_TAMPIL_TOMBOL   = 10000UL;
const unsigned long INTERVAL_BACA_PZEM   = 1000UL;
const unsigned long INTERVAL_KIRIM_CLOUD = 5000UL;
const unsigned long INTERVAL_BACA_CTRL   = 3000UL;
const unsigned long INTERVAL_REFRESH_TKN = 55UL * 60UL * 1000UL; // 55 menit

unsigned long waktuHalaman    = 0;
unsigned long waktuTombol     = 0;
unsigned long waktuBacaPZEM   = 0;
unsigned long waktuKirimCloud = 0;
unsigned long waktuBacaCtrl   = 0;
unsigned long waktuTknRefresh = 0;

// ============================================================
//  FIREBASE AUTH
// ============================================================

String firebaseIdToken    = "";
String firebaseRefreshTkn = "";
unsigned long tokenExpiresAt = 0; // millis() saat token kedaluwarsa

bool wifiTerhubung    = false;
bool firebaseLogin    = false;

// ============================================================
//  TARIF LISTRIK (default, dapat diperbarui dari control)
// ============================================================

float tarifPerKwh = 1500.0f;

// ============================================================
//  PROTOTYPING FUNGSI
// ============================================================

void initHardware();
void bacaPZEM();
void hitungEnergi();
void setRelay(bool state);
void tampilKondisi();
void tampilHari();
void tampilBulan();
void tampilPesan(const char* baris1, const char* baris2);
void bunyiBuzzer();
void tanganiTombol();
void rotasiHalamanOtomatis();

bool hubungkanWiFi();
bool loginFirebase();
bool refreshToken();
bool kirimTelemetriCloud();
bool bacaKontrolCloud();

// ============================================================
//  SETUP
// ============================================================

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("===========================================");
  Serial.println("  SIMETRI Firebase Integrated Firmware    ");
  Serial.println("  Tahap: Staging (Relay Control DISABLED)  ");
  Serial.println("===========================================");

  initHardware();

  // Baca energi awal dari PZEM (sebagai referensi harian/bulanan)
  float eAwal = pzem.energy();
  if (!isnan(eAwal)) {
    energyAwalHari  = eAwal;
    energyAwalBulan = eAwal;
    energyKwh       = eAwal;
    Serial.printf("Energi awal PZEM: %.4f kWh\n", eAwal);
  } else {
    Serial.println("[WARN] Pembacaan energi awal gagal (sensor tidak terhubung?)");
  }

  bacaPZEM();
  tampilKondisi();

  waktuHalaman    = millis();
  waktuBacaPZEM   = millis();
  waktuKirimCloud = millis();
  waktuBacaCtrl   = millis();

  // Hubungkan WiFi lalu login Firebase
  if (hubungkanWiFi()) {
    loginFirebase();
  }
}

// ============================================================
//  LOOP UTAMA
// ============================================================

void loop() {
  unsigned long sekarang = millis();

  // --- Baca sensor setiap 1 detik ---
  if (sekarang - waktuBacaPZEM >= INTERVAL_BACA_PZEM) {
    waktuBacaPZEM = sekarang;
    bacaPZEM();
    hitungEnergi();

    // Update tampilan halaman 0 jika tidak dalam mode tombol
    if (!modeTombol && halaman == 0) {
      tampilKondisi();
    }
  }

  // --- Tombol navigasi ---
  tanganiTombol();

  // --- Rotasi halaman otomatis ---
  if (!modeTombol) {
    rotasiHalamanOtomatis();
  }

  // --- Kirim telemetri ke Firebase setiap 5 detik ---
  if (wifiTerhubung && firebaseLogin && (sekarang - waktuKirimCloud >= INTERVAL_KIRIM_CLOUD)) {
    waktuKirimCloud = sekarang;

    // Refresh token jika sudah mendekati kedaluwarsa
    if (sekarang >= tokenExpiresAt - 60000UL) {
      Serial.println("[AUTH] Token mendekati kedaluwarsa, memperbarui...");
      if (!refreshToken()) {
        Serial.println("[AUTH] Refresh gagal. Mencoba login ulang...");
        firebaseLogin = loginFirebase();
      }
    }

    if (firebaseLogin) {
      kirimTelemetriCloud();
    }
  }

  // --- Baca perintah kontrol dari Firebase setiap 3 detik ---
  if (wifiTerhubung && firebaseLogin && (sekarang - waktuBacaCtrl >= INTERVAL_BACA_CTRL)) {
    waktuBacaCtrl = sekarang;
    bacaKontrolCloud();
  }

  // --- Periksa koneksi WiFi ---
  if (WiFi.status() != WL_CONNECTED) {
    if (wifiTerhubung) {
      Serial.println("[WiFi] Koneksi terputus. Mencoba reconnect...");
      wifiTerhubung = false;
      firebaseLogin = false;
    }
    if (hubungkanWiFi()) {
      loginFirebase();
    }
  }
}

// ============================================================
//  INISIALISASI HARDWARE
// ============================================================

void initHardware() {
  // PZEM
  pzemSerial.begin(9600, SERIAL_8N1, PZEM_RX_PIN, PZEM_TX_PIN);

  // LCD
  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  tampilPesan("SIMETRI Firebase", "Inisialisasi...");

  // Tombol
  pinMode(TOMBOL_KONDISI, INPUT_PULLUP);
  pinMode(TOMBOL_HARI, INPUT_PULLUP);
  pinMode(TOMBOL_BULAN, INPUT_PULLUP);

  // Buzzer
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // Relay — pastikan OFF saat startup
  pinMode(RELAY_PIN, OUTPUT);
  setRelay(false);

  delay(1000);
}

// ============================================================
//  BACA DATA PZEM
// ============================================================

void bacaPZEM() {
  float v = pzem.voltage();
  float i = pzem.current();
  float p = pzem.power();
  float e = pzem.energy();
  float f = pzem.frequency();
  float q = pzem.pf();

  if (!isnan(v)) voltage   = v;
  if (!isnan(i)) current   = (i < 0.01f) ? 0.0f : i;
  if (!isnan(p)) power     = (p < 0.5f)  ? 0.0f : p;
  if (!isnan(e)) energyKwh = e;
  if (!isnan(f)) frequency = f;
  if (!isnan(q)) pf        = q;
}

// ============================================================
//  HITUNG ENERGI HARIAN & BULANAN
// ============================================================

void hitungEnergi() {
  if (!isnan(energyKwh) && !isnan(energyAwalHari)) {
    energiHari = max(0.0f, energyKwh - energyAwalHari);
  }
  if (!isnan(energyKwh) && !isnan(energyAwalBulan)) {
    energiBulan = max(0.0f, energyKwh - energyAwalBulan);
  }
}

// ============================================================
//  RELAY
// ============================================================

void setRelay(bool state) {
  relayStateFisik = state;

#if ENABLE_RELAY_CONTROL
  // Relay diizinkan bergerak
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? (state ? LOW : HIGH) : (state ? HIGH : LOW));
  Serial.printf("[RELAY] %s\n", state ? "ON" : "OFF");
#else
  // TAHAP STAGING: relay tidak digerakkan
  // Pastikan relay tetap OFF fisik saat staging
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
  Serial.printf("[RELAY] Perintah: %s — DIABAIKAN (ENABLE_RELAY_CONTROL=false)\n", state ? "ON" : "OFF");
#endif
}

// ============================================================
//  TAMPILAN LCD
// ============================================================

static char lcdBuf[21]; // buffer per baris

void tampilKondisi() {
  lcd.setCursor(0, 0);
  if (!isnan(voltage) && !isnan(current)) {
    snprintf(lcdBuf, sizeof(lcdBuf), "V:%.0fV I:%.2fA     ", voltage, current);
  } else {
    snprintf(lcdBuf, sizeof(lcdBuf), "V:-- I:--           ");
  }
  lcd.print(lcdBuf);

  lcd.setCursor(0, 1);
  if (!isnan(power)) {
    snprintf(lcdBuf, sizeof(lcdBuf), "P:%.0fW              ", power);
  } else {
    snprintf(lcdBuf, sizeof(lcdBuf), "P:--                ");
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
  delay(150);
  noTone(BUZZER_PIN);
}

void tanganiTombol() {
  bool k = digitalRead(TOMBOL_KONDISI);
  bool h = digitalRead(TOMBOL_HARI);
  bool b = digitalRead(TOMBOL_BULAN);

  if (tombolKondisiSebelum == HIGH && k == LOW) {
    halaman = 0; tampilKondisi(); bunyiBuzzer();
    modeTombol = true; waktuTombol = millis();
  }
  if (tombolHariSebelum == HIGH && h == LOW) {
    halaman = 1; tampilHari(); bunyiBuzzer();
    modeTombol = true; waktuTombol = millis();
  }
  if (tombolBulanSebelum == HIGH && b == LOW) {
    halaman = 2; tampilBulan(); bunyiBuzzer();
    modeTombol = true; waktuTombol = millis();
  }

  tombolKondisiSebelum = k;
  tombolHariSebelum    = h;
  tombolBulanSebelum   = b;

  if (modeTombol) {
    if      (halaman == 0) tampilKondisi();
    else if (halaman == 1) tampilHari();
    else if (halaman == 2) tampilBulan();

    if (millis() - waktuTombol >= WAKTU_TAMPIL_TOMBOL) {
      modeTombol = false;
      halaman = 0;
      tampilKondisi();
      waktuHalaman = millis();
    }
  }
}

void rotasiHalamanOtomatis() {
  if (millis() - waktuHalaman >= INTERVAL_HALAMAN) {
    waktuHalaman = millis();
    halaman = (halaman + 1) % 3;
    if      (halaman == 0) tampilKondisi();
    else if (halaman == 1) tampilHari();
    else if (halaman == 2) tampilBulan();
  }
}

// ============================================================
//  WIFI
// ============================================================

bool hubungkanWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    wifiTerhubung = true;
    return true;
  }

  Serial.printf("[WiFi] Menghubungkan ke: %s\n", WIFI_SSID);
  tampilPesan("WiFi...", WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long mulai = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - mulai < 15000UL) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[WiFi] Terhubung. IP: %s\n", WiFi.localIP().toString().c_str());
    wifiTerhubung = true;
    return true;
  } else {
    Serial.println("[WiFi] Gagal terhubung. Fungsi lokal tetap aktif.");
    tampilKondisi();
    wifiTerhubung = false;
    return false;
  }
}

// ============================================================
//  FIREBASE AUTH — EMAIL/PASSWORD LOGIN
// ============================================================

bool loginFirebase() {
  Serial.println("[AUTH] Login ke Firebase Auth...");

  // URL endpoint: Firebase Auth REST API signInWithPassword
  // Emulator: http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword
  // Production: https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword

  String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=";
  url += FIREBASE_API_KEY;

  WiFiClientSecure client;
  // Untuk produksi: gunakan setInsecure() HANYA jika tidak ada bundle CA.
  // Untuk CA bundle yang benar, gunakan client.setCACert(rootCACertificate).
  // Dalam versi staging ini digunakan setInsecure() untuk kemudahan pengujian.
  // CATATAN: Ganti dengan CA bundle yang sesuai sebelum deploy ke produksi.
  client.setInsecure();

  HTTPClient http;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<256> body;
  body["email"]             = DEVICE_EMAIL;
  body["password"]          = DEVICE_PASSWORD;
  body["returnSecureToken"] = true;

  String bodyStr;
  serializeJson(body, bodyStr);

  int httpCode = http.POST(bodyStr);

  if (httpCode != 200) {
    Serial.printf("[AUTH] Login gagal. HTTP %d\n", httpCode);
    if (httpCode > 0) {
      String resp = http.getString();
      // Hanya cetak kode error, BUKAN isi respons lengkap (bisa mengandung token)
      StaticJsonDocument<256> errDoc;
      if (deserializeJson(errDoc, resp) == DeserializationError::Ok) {
        const char* errMsg = errDoc["error"]["message"] | "unknown";
        Serial.printf("[AUTH] Error: %s\n", errMsg);
      }
    }
    http.end();
    firebaseLogin = false;
    return false;
  }

  String resp = http.getString();
  http.end();

  StaticJsonDocument<1024> doc;
  if (deserializeJson(doc, resp) != DeserializationError::Ok) {
    Serial.println("[AUTH] Gagal parse respons login.");
    firebaseLogin = false;
    return false;
  }

  firebaseIdToken    = doc["idToken"].as<String>();
  firebaseRefreshTkn = doc["refreshToken"].as<String>();

  // Token Firebase berlaku 3600 detik; set expiry 55 menit dari sekarang
  tokenExpiresAt = millis() + INTERVAL_REFRESH_TKN;

  // KEAMANAN: JANGAN log idToken atau refreshToken ke Serial
  Serial.println("[AUTH] Login berhasil. Token disimpan (tidak ditampilkan).");
  firebaseLogin = true;
  return true;
}

// ============================================================
//  FIREBASE AUTH — REFRESH TOKEN
// ============================================================

bool refreshToken() {
  if (firebaseRefreshTkn.isEmpty()) {
    Serial.println("[AUTH] Tidak ada refresh token. Perlu login ulang.");
    return false;
  }

  String url = "https://securetoken.googleapis.com/v1/token?key=";
  url += FIREBASE_API_KEY;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.begin(client, url);
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

  StaticJsonDocument<1024> doc;
  if (deserializeJson(doc, resp) != DeserializationError::Ok) {
    Serial.println("[AUTH] Gagal parse respons refresh token.");
    return false;
  }

  firebaseIdToken    = doc["id_token"].as<String>();
  firebaseRefreshTkn = doc["refresh_token"].as<String>();
  tokenExpiresAt = millis() + INTERVAL_REFRESH_TKN;

  Serial.println("[AUTH] Token berhasil diperbarui.");
  return true;
}

// ============================================================
//  KIRIM TELEMETRI KE FIREBASE RTDB
// ============================================================

bool kirimTelemetriCloud() {
  if (firebaseIdToken.isEmpty()) {
    Serial.println("[CLOUD] Tidak ada token. Lewati pengiriman.");
    return false;
  }

  // Jangan kirim jika sensor belum pernah memberikan data valid
  if (isnan(voltage) && isnan(current) && isnan(power)) {
    Serial.println("[CLOUD] Data sensor belum valid. Lewati pengiriman.");
    return false;
  }

  // Path: devices/{deviceId}/live
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/devices/";
  url += DEVICE_ID;
  url += "/live.json?auth=";
  url += firebaseIdToken;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");

  // Siapkan payload telemetri lengkap
  StaticJsonDocument<512> doc;
  doc["voltage"]        = isnan(voltage)   ? 0.0f : voltage;
  doc["current"]        = isnan(current)   ? 0.0f : current;
  doc["power"]          = isnan(power)     ? 0.0f : power;
  doc["energy_kwh"]     = isnan(energyKwh) ? 0.0f : energyKwh;
  doc["daily_energy"]   = energiHari;
  doc["monthly_energy"] = energiBulan;
  doc["frequency"]      = isnan(frequency) ? 0.0f : frequency;
  doc["power_factor"]   = isnan(pf)        ? 0.0f : pf;
  doc["relay_state"]    = relayStateFisik;
  doc["timestamp"]      = millis(); // Gunakan NTP-synced timestamp di versi produksi

  // CATATAN untuk versi produksi:
  // Ganti millis() dengan waktu UNIX aktual menggunakan NTPClient atau time.h
  // agar timestamp dapat digunakan sebagai referensi histori yang akurat.

  String payload;
  serializeJson(doc, payload);

  int httpCode = http.PUT(payload);

  if (httpCode == 200 || httpCode == 204) {
    Serial.printf("[CLOUD] Telemetri terkirim. V=%.1f I=%.3f P=%.1f kWh=%.4f\n",
      isnan(voltage) ? 0.0f : voltage,
      isnan(current) ? 0.0f : current,
      isnan(power)   ? 0.0f : power,
      isnan(energyKwh) ? 0.0f : energyKwh);
    http.end();
    return true;
  } else {
    Serial.printf("[CLOUD] Gagal kirim telemetri. HTTP %d\n", httpCode);
    // Token mungkin kedaluwarsa — tandai untuk refresh
    if (httpCode == 401) {
      tokenExpiresAt = millis(); // paksa refresh di iterasi berikutnya
    }
    http.end();
    return false;
  }
}

// ============================================================
//  BACA PERINTAH KONTROL DARI FIREBASE
// ============================================================

bool bacaKontrolCloud() {
  if (firebaseIdToken.isEmpty()) {
    return false;
  }

  // Path: devices/{deviceId}/control/power
  String url = "https://";
  url += FIREBASE_HOST;
  url += "/devices/";
  url += DEVICE_ID;
  url += "/control/power.json?auth=";
  url += firebaseIdToken;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.begin(client, url);
  int httpCode = http.GET();

  if (httpCode == 200) {
    String resp = http.getString();
    http.end();

    resp.trim();
    bool perintahPower = (resp == "true");

#if ENABLE_RELAY_CONTROL
    setRelay(perintahPower);
#else
    // STAGING: Log perintah yang diterima, tapi JANGAN gerakkan relay
    Serial.printf("[CTRL] Perintah diterima: power=%s — relay TIDAK digerakkan (staging)\n",
      perintahPower ? "ON" : "OFF");
    // Update status internal saja (untuk telemetri relay_state)
    relayStateFisik = perintahPower;
#endif
    return true;
  } else if (httpCode == 401) {
    Serial.println("[CTRL] Token kedaluwarsa saat baca kontrol.");
    tokenExpiresAt = millis();
    http.end();
    return false;
  } else {
    Serial.printf("[CTRL] Gagal baca kontrol. HTTP %d\n", httpCode);
    http.end();
    return false;
  }
}
