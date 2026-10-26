#define BLYNK_TEMPLATE_ID "TMPL69hBCS8Wl"
#define BLYNK_TEMPLATE_NAME "Smart Meteran Listrik"
#define BLYNK_AUTH_TOKEN "lhUIB0DbDBzo0W2tDl3JSQEsSpQTMSDc"

#define BLYNK_PRINT Serial

#include <WiFi.h>
#include <BlynkSimpleEsp32.h>
#include <PZEM004Tv30.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>

// =================================================
// WIFI
// =================================================

char ssid[] = "DISKOMINFO";
char pass[] = "diskotikdansa";

// =================================================
// PZEM-004T V4.0
// =================================================

#define PZEM_RX_PIN 16
#define PZEM_TX_PIN 17

HardwareSerial pzemSerial(2);

PZEM004Tv30 pzem(
  pzemSerial,
  PZEM_RX_PIN,
  PZEM_TX_PIN
);

// =================================================
// LCD I2C 20x2
// =================================================

LiquidCrystal_I2C lcd(0x27, 20, 2);

// =================================================
// TOMBOL
// =================================================

const int tombolKondisi = 25;
const int tombolHari    = 26;
const int tombolBulan   = 27;

// =================================================
// BUZZER
// =================================================

const int buzzer = 19;

// =================================================
//  
// =================================  ================

const int RELAY_PIN = 14;

// Banyak modul relay = Active LOW
const bool RELAY_ACTIVE_LOW = true;

bool relayState = false;

// =================================================
// TIMER
// =================================================

unsigned long waktuHalaman = 0;
unsigned long waktuTombol = 0;
unsigned long waktuBacaPZEM = 0;

const unsigned long intervalHalaman = 3000;
const unsigned long waktuTampilTombol = 10000;
const unsigned long intervalBacaPZEM = 1000;

// =================================================
// BLYNK TIMER
// =================================================

BlynkTimer timer;

// =================================================
// HALAMAN LCD
// =================================================

int halaman = 0;
bool modeTombol = false;

// =================================================
// STATUS TOMBOL
// =================================================

bool kondisiSebelumnya = HIGH;
bool hariSebelumnya = HIGH;
bool bulanSebelumnya = HIGH;

// =================================================
// DATA PZEM
// =================================================

float voltage = 0.0;
float current = 0.0;
float power = 0.0;
float energy = 0.0;
float frequency = 0.0;
float pf = 0.0;

// =================================================
// TARIF LISTRIK
// =================================================

const float tarifPerKwh = 1500.0;

// =================================================
// ENERGI AWAL
// Untuk sementara dihitung sejak ESP32 dinyalakan
// =================================================

float energyAwalHari = 0.0;
float energyAwalBulan = 0.0;

// =================================================
// DATA HASIL PERHITUNGAN
// SATU SUMBER UNTUK LCD DAN BLYNK
// =================================================

float energiHari = 0.0;
float energiBulan = 0.0;

float biayaHari = 0.0;
float biayaBulan = 0.0;

// Hasil pembulatan final
long biayaHariBulat = 0;
long biayaBulanBulat = 0;

// =================================================
// RELAY
// =================================================

void setRelay(bool state)
{
  relayState = state;

  if (RELAY_ACTIVE_LOW)
  {
    digitalWrite(RELAY_PIN, state ? LOW : HIGH);
  }
  else
  {
    digitalWrite(RELAY_PIN, state ? HIGH : LOW);
  }

  Serial.print("Relay: ");
  Serial.println(state ? "ON" : "OFF");
}

// =================================================
// BLYNK V3 = RELAY
// =================================================

BLYNK_WRITE(V3)
{
  int value = param.asInt();

  setRelay(value == 1);
}

// =================================================
// SAAT BLYNK TERHUBUNG
// =================================================

BLYNK_CONNECTED()
{
  Serial.println("Blynk terhubung!");

  Blynk.syncVirtual(V3);
}

// =================================================
// HITUNG ENERGI DAN BIAYA
// =================================================

void hitungBiaya()
{
  // ================================
  // HARI INI
  // ================================

  energiHari = energy - energyAwalHari;

  if (energiHari < 0)
  {
    energiHari = 0;
  }

  biayaHari = energiHari * tarifPerKwh;

  // Bulatkan sekali
  biayaHariBulat = (long)round(biayaHari);

  // ================================
  // BULAN INI
  // ================================

  energiBulan = energy - energyAwalBulan;

  if (energiBulan < 0)
  {
    energiBulan = 0;
  }

  biayaBulan = energiBulan * tarifPerKwh;

  // Bulatkan sekali
  biayaBulanBulat = (long)round(biayaBulan);
}

// =================================================
// KIRIM DATA KE BLYNK
// =================================================

void kirimKeBlynk()
{
  // Pastikan data terbaru
  hitungBiaya();

  // -------------------------------
  // REALTIME
  // -------------------------------

  Blynk.virtualWrite(V0, voltage);
  Blynk.virtualWrite(V1, current);
  Blynk.virtualWrite(V2, power);

  // -------------------------------
  // HARI
  // -------------------------------

  Blynk.virtualWrite(V4, energiHari);
  Blynk.virtualWrite(V5, biayaHariBulat);

  // -------------------------------
  // BULAN
  // -------------------------------

  Blynk.virtualWrite(V6, energiBulan);
  Blynk.virtualWrite(V7, biayaBulanBulat);

  Serial.println("Data Blynk terkirim");
}

// =================================================
// SETUP
// =================================================

void setup()
{
  Serial.begin(115200);

  delay(1000);

  // =================================================
  // PZEM
  // =================================================

  pzemSerial.begin(
    9600,
    SERIAL_8N1,
    PZEM_RX_PIN,
    PZEM_TX_PIN
  );

  // =================================================
  // LCD
  // =================================================

  Wire.begin(21, 22);

  lcd.init();
  lcd.backlight();
  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print("SMART METERAN");

  lcd.setCursor(0, 1);
  lcd.print("Menghubungkan...");

  // =================================================
  // TOMBOL
  // =================================================

  pinMode(tombolKondisi, INPUT_PULLUP);
  pinMode(tombolHari, INPUT_PULLUP);
  pinMode(tombolBulan, INPUT_PULLUP);

  // =================================================
  // BUZZER
  // =================================================

  pinMode(buzzer, OUTPUT);
  digitalWrite(buzzer, LOW);

  // =================================================
  // RELAY
  // =================================================

  pinMode(RELAY_PIN, OUTPUT);

  // Relay OFF saat startup
  setRelay(false);

  delay(2000);

  // =================================================
  // ENERGI AWAL
  // =================================================

  float energiAwal = pzem.energy();

  if (!isnan(energiAwal))
  {
    energyAwalHari = energiAwal;
    energyAwalBulan = energiAwal;
    energy = energiAwal;
  }

  // =================================================
  // BACA PZEM PERTAMA
  // =================================================

  bacaPZEM();

  // =================================================
  // HITUNG BIAYA
  // =================================================

  hitungBiaya();

  // =================================================
  // LCD AWAL
  // =================================================

  tampilKondisi();

  waktuHalaman = millis();
  waktuBacaPZEM = millis();

  // =================================================
  // WIFI + BLYNK
  // =================================================

  Serial.println();
  Serial.println("Menghubungkan WiFi + Blynk...");

  Blynk.begin(
    BLYNK_AUTH_TOKEN,
    ssid,
    pass
  );

  // Kirim ke Blynk setiap 2 detik
  timer.setInterval(2000L, kirimKeBlynk);

  Serial.println();
  Serial.println("==============================");
  Serial.println("SISTEM MONITORING AKTIF");
  Serial.println("==============================");
}

// =================================================
// LOOP
// =================================================

void loop()
{
  // =================================================
  // BLYNK
  // =================================================

  Blynk.run();
  timer.run();

  // =================================================
  // BACA PZEM
  // =================================================

  if (millis() - waktuBacaPZEM >= intervalBacaPZEM)
  {
    waktuBacaPZEM = millis();

    bacaPZEM();

    // Hitung biaya sekali dari data terbaru
    hitungBiaya();

    // Update halaman kondisi
    if (!modeTombol && halaman == 0)
    {
      tampilKondisi();
    }
  }

  // =================================================
  // TOMBOL KONDISI
  // =================================================

  bool kondisiSekarang = digitalRead(tombolKondisi);

  if (kondisiSebelumnya == HIGH &&
      kondisiSekarang == LOW)
  {
    halaman = 0;

    tampilKondisi();
    bunyiBuzzer();

    modeTombol = true;
    waktuTombol = millis();
    waktuHalaman = millis();
  }

  kondisiSebelumnya = kondisiSekarang;

  // =================================================
  // TOMBOL HARI
  // =================================================

  bool hariSekarang = digitalRead(tombolHari);

  if (hariSebelumnya == HIGH &&
      hariSekarang == LOW)
  {
    halaman = 1;

    tampilHari();
    bunyiBuzzer();

    modeTombol = true;
    waktuTombol = millis();
    waktuHalaman = millis();
  }

  hariSebelumnya = hariSekarang;

  // =================================================
  // TOMBOL BULAN
  // =================================================

  bool bulanSekarang = digitalRead(tombolBulan);

  if (bulanSebelumnya == HIGH &&
      bulanSekarang == LOW)
  {
    halaman = 2;

    tampilBulan();
    bunyiBuzzer();

    modeTombol = true;
    waktuTombol = millis();
    waktuHalaman = millis();
  }

  bulanSebelumnya = bulanSekarang;

  // =================================================
  // MODE TOMBOL 10 DETIK
  // =================================================

  if (modeTombol)
  {
    if (halaman == 0)
    {
      tampilKondisi();
    }
    else if (halaman == 1)
    {
      tampilHari();
    }
    else if (halaman == 2)
    {
      tampilBulan();
    }

    if (millis() - waktuTombol >= waktuTampilTombol)
    {
      modeTombol = false;

      halaman = 0;

      tampilKondisi();

      waktuHalaman = millis();
    }

    return;
  }

  // =================================================
  // GANTI HALAMAN OTOMATIS
  // =================================================

  if (millis() - waktuHalaman >= intervalHalaman)
  {
    waktuHalaman = millis();

    halaman++;

    if (halaman > 2)
    {
      halaman = 0;
    }

    if (halaman == 0)
    {
      tampilKondisi();
    }
    else if (halaman == 1)
    {
      tampilHari();
    }
    else if (halaman == 2)
    {
      tampilBulan();
    }
  }
}

// =================================================
// BACA DATA PZEM
// =================================================

void bacaPZEM()
{
  // ================================
  // VOLTAGE
  // ================================

  float v = pzem.voltage();

  if (!isnan(v))
  {
    voltage = v;
  }

  // ================================
  // CURRENT
  // ================================

  float i = pzem.current();

  if (!isnan(i))
  {
    if (i < 0.01)
    {
      current = 0.0;
    }
    else
    {
      current = i;
    }
  }

  // ================================
  // POWER
  // ================================

  float p = pzem.power();

  if (!isnan(p))
  {
    if (p < 0.5)
    {
      power = 0.0;
    }
    else
    {
      power = p;
    }
  }

  // ================================
  // ENERGY
  // ================================

  float e = pzem.energy();

  if (!isnan(e))
  {
    energy = e;
  }

  // ================================
  // FREQUENCY
  // ================================

  float f = pzem.frequency();

  if (!isnan(f))
  {
    frequency = f;
  }

  // ================================
  // POWER FACTOR
  // ================================

  float faktor = pzem.pf();

  if (!isnan(faktor))
  {
    pf = faktor;
  }

  // ================================
  // SERIAL MONITOR
  // ================================

  Serial.println();
  Serial.println("============================");

  Serial.print("Voltage : ");
  Serial.print(voltage, 2);
  Serial.println(" V");

  Serial.print("Current : ");
  Serial.print(current, 3);
  Serial.println(" A");

  Serial.print("Power   : ");
  Serial.print(power, 2);
  Serial.println(" W");

  Serial.print("Energy  : ");
  Serial.print(energy, 4);
  Serial.println(" kWh");

  Serial.print("Hari    : ");
  Serial.print(energiHari, 4);
  Serial.println(" kWh");

  Serial.print("Biaya Hari : Rp");
  Serial.println(biayaHariBulat);

  Serial.print("Bulan   : ");
  Serial.print(energiBulan, 4);
  Serial.println(" kWh");

  Serial.print("Biaya Bulan : Rp");
  Serial.println(biayaBulanBulat);

  Serial.print("PF      : ");
  Serial.println(pf, 2);

  Serial.print("Freq    : ");
  Serial.print(frequency, 2);
  Serial.println(" Hz");

  Serial.println("============================");
}

// =================================================
// LCD HALAMAN 1
// HANYA V / I / P
// =================================================

void tampilKondisi()
{
  lcd.setCursor(0, 0);

  lcd.print("V:");
  lcd.print(voltage, 0);
  lcd.print("V I:");
  lcd.print(current, 2);
  lcd.print("A");

  lcd.print("     ");

  lcd.setCursor(0, 1);

  lcd.print("P:");
  lcd.print(power, 0);
  lcd.print("W");

  lcd.print("            ");
}

// =================================================
// LCD HALAMAN 2
// HARI INI
// KWH 3 DESIMAL
// =================================================

void tampilHari()
{
  lcd.setCursor(0, 0);

  lcd.print("Hari:");
  lcd.print(energiHari, 3);
  lcd.print("kWh");

  lcd.print("     ");

  lcd.setCursor(0, 1);

  lcd.print("Biaya: Rp");
  lcd.print(biayaHariBulat);

  lcd.print("      ");
}

// =================================================
// LCD HALAMAN 3
// BULAN INI
// KWH 3 DESIMAL
// =================================================

void tampilBulan()
{
  lcd.setCursor(0, 0);

  lcd.print("Bln:");
  lcd.print(energiBulan, 3);
  lcd.print("kWh");

  lcd.print("     ");

  lcd.setCursor(0, 1);

  lcd.print("Biaya: Rp");
  lcd.print(biayaBulanBulat);

  lcd.print("      ");
}

// =================================================
// BUZZER
// =================================================

void bunyiBuzzer()
{
  tone(buzzer, 1000);
  delay(150);
  noTone(buzzer);
}