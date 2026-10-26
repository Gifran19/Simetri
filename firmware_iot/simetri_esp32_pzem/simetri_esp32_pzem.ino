/*
  ==================================================================================
  PROJECT SIMETRI - SMART ELECTRICITY METER IOT FIRMWARE (ESP32 + PZEM-004T v3.0)
  ==================================================================================
  
  Kode ini dirancang untuk rekan magang IoT agar perangkat keras dapat langsung
  terhubung ke Firebase Realtime Database dan sinkron 100% dengan aplikasi Flutter SIMETRI.
  
  SKEMA KONEKSI PIN (WIRING DIAGRAM):
  -------------------------------------------------------------
  ESP32 Pin          PZEM-004T v3.0 Pin       Keterangan
  -------------------------------------------------------------
  GPIO 16 (RX2) ---> TX                     Serial RX (ESP32 menerima data sensor)
  GPIO 17 (TX2) ---> RX                     Serial TX (ESP32 mengirim perintah)
  5V (VIN)      ---> 5V                     Daya PZEM
  GND           ---> GND                    Ground
  
  ESP32 Pin          Relay Module Pin         Keterangan
  -------------------------------------------------------------
  GPIO 23       ---> IN                     Sinyal kontrol relay pemutus arus
  5V / 3.3V     ---> VCC                    Daya modul relay
  GND           ---> GND                    Ground
  -------------------------------------------------------------
  
  LIBRARY YANG WAJIB DI-INSTALL DI ARDUINO IDE:
  1. "PZEM004Tv30" oleh Jakub Mandula (Buka: Tools -> Manage Libraries -> cari "PZEM004Tv30")
  2. "Firebase ESP Client" oleh Mobizt (Buka: Tools -> Manage Libraries -> cari "Firebase-ESP-Client")
  
  DATA PATH DI FIREBASE REALTIME DATABASE:
  - Telemetri Sensor:  `devices/simetri_01/live`
  - Kontrol Relay:     `devices/simetri_01/control/power`
  ==================================================================================
*/

#include <WiFi.h>
#include <PZEM004Tv30.h>
#include <Firebase_ESP_Client.h>

// Token helper Firebase
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

// ==================================================================================
// 1. KONFIGURASI WIFI & FIREBASE (ISI SESUAI DATA PROJECT ANDA)
// ==================================================================================
#define WIFI_SSID       "NAMA_WIFI_ANDA"
#define WIFI_PASSWORD   "PASSWORD_WIFI_ANDA"

// Salin dari Firebase Console -> Project Settings -> General -> Web API Key
#define API_KEY         "AIzaSyA1DHNn6czhr4850M7Ai2V2DfdO9zWs4tA"

// URL Firebase Realtime Database
#define DATABASE_URL    "https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app/"

// ID perangkat unik untuk smart meter ini
#define DEVICE_ID       "simetri_01"

// ==================================================================================
// 2. PIN HARDWARE
// ==================================================================================
#define PZEM_RX_PIN     16   // Terhubung ke TX PZEM
#define PZEM_TX_PIN     17   // Terhubung ke RX PZEM
#define RELAY_PIN       23   // Pin relay (Active LOW atau Active HIGH)
#define RELAY_ACTIVE    LOW  // LOW = Relay Nyala/Tertutup, HIGH = Relay Mati/Terbuka

// Inisialisasi Objek Sensor PZEM HardwareSerial 2
PZEM004Tv30 pzem(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);

// Objek Firebase
FirebaseData fbdoStream;
FirebaseData fbdoData;
FirebaseAuth auth;
FirebaseConfig config;

// State status
bool relayState = true;
unsigned long lastSendTime = 0;
const unsigned long sendInterval = 2000; // Kirim data setiap 2 detik

// Akumulasi energi harian (dapat di-reset tiap pukul 00:00 jika memakai RTC/NTP)
float dailyEnergyAccum = 0.0;
float lastPzemEnergy = 0.0;

// ==================================================================================
// 3. CALLBACK STREAM KONTROL RELAY DARI APLIKASI FLUTTER
// ==================================================================================
void streamCallback(FirebaseStream data) {
  Serial.printf("[Stream] Path: %s, Data: %s\n", data.dataPath().c_str(), data.stringData().c_str());

  if (data.dataType() == "boolean") {
    relayState = data.boolData();
    digitalWrite(RELAY_PIN, relayState ? RELAY_ACTIVE : !RELAY_ACTIVE);
    Serial.printf(">>> Status Relay diubah dari Aplikasi SIMETRI: %s\n", relayState ? "ON (MENYALA)" : "OFF (PUTUS)");
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) {
    Serial.println("[Stream] Timeout terjadi, mencoba menyambung kembali...");
  }
}

// ==================================================================================
// 4. SETUP
// ==================================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n==============================================");
  Serial.println("  SIMETRI SMART METER FIRMWARE INITIALIZING   ");
  Serial.println("==============================================");

  // Inisialisasi Pin Relay
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, relayState ? RELAY_ACTIVE : !RELAY_ACTIVE);

  // Inisialisasi Serial PZEM
  Serial2.begin(9600, SERIAL_8N1, PZEM_RX_PIN, PZEM_TX_PIN);
  Serial.println("[PZEM] HardwareSerial 2 diinisialisasi (RX:16, TX:17).");

  // Sambungkan ke WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Menghubungkan ke ");
  Serial.print(WIFI_SSID);
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\n[WiFi] Berhasil terhubung! IP Address: " + WiFi.localIP().toString());

  // Inisialisasi Firebase
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  // Sign up secara anonymous
  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("[Firebase] SignUp Anonim Berhasil.");
  } else {
    Serial.printf("[Firebase] SignUp Gagal: %s\n", config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Pasang listener realtime untuk kontrol relay dari aplikasi Flutter
  String controlPath = "devices/" + String(DEVICE_ID) + "/control/power";
  if (!Firebase.RTDB.beginStream(&fbdoStream, controlPath.c_str())) {
    Serial.printf("[Firebase Stream] Gagal pasang stream: %s\n", fbdoStream.errorReason().c_str());
  } else {
    Firebase.RTDB.setStreamCallback(&fbdoStream, streamCallback, streamTimeoutCallback);
    Serial.println("[Firebase Stream] Siap mendengarkan perintah kontrol relay dari aplikasi!");
  }
}

// ==================================================================================
// 5. MAIN LOOP
// ==================================================================================
void loop() {
  // Biarkan helper token Firebase bekerja
  Firebase.ready();

  unsigned long currentMillis = millis();
  if (currentMillis - lastSendTime >= sendInterval) {
    lastSendTime = currentMillis;

    // Baca sensor PZEM-004T
    float voltage   = pzem.voltage();
    float current   = pzem.current();
    float power     = pzem.power();
    float energy    = pzem.energy();
    float frequency = pzem.frequency();
    float pf        = pzem.pf();

    // Validasi apakah sensor terbaca
    if (isnan(voltage)) {
      Serial.println("[PZEM] Gagal membaca tegangan! Periksa kabel TX/RX dan daya PZEM.");
      voltage = 0.0;
      current = 0.0;
      power = 0.0;
      frequency = 0.0;
      pf = 0.0;
    } else {
      Serial.printf("[Sensor] V: %.1fV | I: %.2fA | P: %.1fW | E: %.3fkWh | F: %.1fHz | PF: %.2f\n",
                    voltage, current, power, energy, frequency, pf);
    }

    // Kalkulasi akumulasi energi
    if (lastPzemEnergy > 0.0 && energy >= lastPzemEnergy) {
      dailyEnergyAccum += (energy - lastPzemEnergy);
    } else if (dailyEnergyAccum == 0.0 && energy > 0.0) {
      dailyEnergyAccum = energy;
    }
    lastPzemEnergy = energy;

    // Kirim data ke Firebase jika Firebase sudah siap
    if (Firebase.ready()) {
      FirebaseJson json;
      json.set("voltage", voltage);
      json.set("current", current);
      json.set("power", power);
      json.set("frequency", frequency);
      json.set("power_factor", pf);
      json.set("energy_kwh", energy);
      json.set("daily_energy", dailyEnergyAccum);
      json.set("monthly_energy", energy); // Dapat disesuaikan dengan akumulasi bulanan
      json.set("relay_state", relayState);
      json.set("timestamp/.sv", "timestamp"); // Server timestamp otomatis Firebase

      String livePath = "devices/" + String(DEVICE_ID) + "/live";
      if (Firebase.RTDB.updateNode(&fbdoData, livePath.c_str(), &json)) {
        Serial.println("[Firebase] Telemetri sensor terkirim ke " + livePath);
      } else {
        Serial.printf("[Firebase] Gagal kirim: %s\n", fbdoData.errorReason().c_str());
      }
    }
  }
}
