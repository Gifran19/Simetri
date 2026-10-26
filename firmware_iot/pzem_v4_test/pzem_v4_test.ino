
/*
  ==================================================================================
  PROJECT SIMETRI - PRE-FLIGHT TEST SKETCH PZEM-004T V4.0 (ESP32)
  ==================================================================================
  Tujuan:
  Verifikasi terisolasi komunikasi UART HardwareSerial2 antara ESP32 dan modul
  sensor Peacefair PZEM-004T V4.0 (100A) sebelum integrasi ke firmware utama.

  SKEMA PENGKABELAN (WIRING DIAGRAM) & PROTEKSI LEVEL TEGANGAN:
  ----------------------------------------------------------------------------------
  ESP32 Pin          PZEM-004T V4.0 Pin       Keterangan & Rangkaian Proteksi
  ----------------------------------------------------------------------------------
  5V (VIN)      ---> VCC                      Daya sisi optocoupler PZEM (5.0V)
  GND           ---> GND                      Ground bersama (Common Ground)
  GPIO 16 (RX2) <--- TX (via Divider)         JALUR TEGANGAN TURUN (VOLTAGE DIVIDER):
                                              TX PZEM (5V) -> R1 (1.0 kOhm) -> GPIO16
                                              GPIO16 -> R2 (1.5 kOhm) -> GND
                                              Tegangan masuk GPIO16 = 3.00V s/d 3.33V (AMAN!)
  GPIO 17 (TX2) ---> RX                       Sinyal TX ESP32 (3.3V) langsung ke RX PZEM
  ----------------------------------------------------------------------------------

  PERINGATAN KESELAMATAN TEGANGAN TINGGI (AC 220V):
  1. Chip metering PZEM dan optocoupler internal MEMBUTUHKAN tegangan AC (80V - 260V)
     pada terminal input tegangan (L & N) agar dapat merespons perintah Modbus.
  2. JANGAN PERNAH menyentuh terminal screw, PCB PZEM, atau kabel AC saat tercolok PLN!
  3. Gunakan alas isolator non-konduktif dan MCB pengaman laboratorium (2A).
  4. RELAY GPIO14 SAMA SEKALI TIDAK DIGUNAKAN PADA SKETCH INI (BEBAN PLN OFF).

  LIBRARY YANG DIGUNAKAN DI ARDUINO IDE:
  - "PZEM004Tv30" oleh Jakub Mandula (Buka: Tools -> Manage Libraries -> cari "PZEM004Tv30")
    Catatan: Jika modul V4.0 Anda mengalami timeout/NaN terus menerus, Anda dapat
    menggunakan library alternatif "MycilaPZEM" oleh Mathieu Carbou.
  ==================================================================================
*/

#include <PZEM004Tv30.h>

// Konfigurasi Pin HardwareSerial 2 ESP32
#define PZEM_RX_PIN 16  // Terhubung ke TX PZEM melalui pembagi tegangan 1k / 1.5k ohm
#define PZEM_TX_PIN 17  // Terhubung langsung ke RX PZEM

// Inisialisasi Objek PZEM pada HardwareSerial2
#if defined(ESP32)
PZEM004Tv30 pzem(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);
#else
#error "Sketch ini dirancang khusus untuk mikrokontroler ESP32!"
#endif

// Statistik Diagnostik
unsigned long totalReads = 0;
unsigned long successfulReads = 0;
unsigned long failedReads = 0;
unsigned long lastReadTime = 0;
const unsigned long readInterval = 2000; // Pembacaan setiap 2 detik

void setup() {
  // Inisialisasi Serial Monitor (USB)
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========================================================");
  Serial.println("   SIMETRI - PRE-FLIGHT TEST: PZEM-004T V4.0 100A      ");
  Serial.println("========================================================");
  Serial.println("[INFO] Inisialisasi HardwareSerial 2...");
  Serial.printf("[INFO] Pin Konfigurasi: ESP32 RX2=GPIO%d, TX2=GPIO%d\n", PZEM_RX_PIN, PZEM_TX_PIN);
  Serial.println("[INFO] Baud Rate UART: 9600 bps (8N1)");
  Serial.println("[WARN] Pastikan input tegangan AC 220V sudah terhubung ke PZEM!");
  Serial.println("[WARN] Relay GPIO14 TIDAK DIAKTIFKAN pada pengujian ini.");
  Serial.println("--------------------------------------------------------\n");
}

void loop() {
  unsigned long currentMillis = millis();

  if (currentMillis - lastReadTime >= readInterval) {
    lastReadTime = currentMillis;
    totalReads++;

    unsigned long startMeasure = millis();

    // Membaca 6 parameter kelistrikan utama dari PZEM
    float voltage   = pzem.voltage();
    float current   = pzem.current();
    float power     = pzem.power();
    float energy    = pzem.energy();
    float frequency = pzem.frequency();
    float pf        = pzem.pf();

    unsigned long duration = millis() - startMeasure;

    Serial.printf("[%04lu] ", totalReads);

    // Validasi apakah sensor merespons dengan nilai valid (bukan NaN)
    if (isnan(voltage) || isnan(current) || isnan(power) || isnan(energy)) {
      failedReads++;
      Serial.printf("GAGAL BACA! (Waktu respons: %lu ms)\n", duration);
      Serial.println("       --> Analisis Masalah:");
      Serial.println("           1. Apakah terminal AC 220V sudah bertegangan? (PZEM mati jika tanpa AC)");
      Serial.println("           2. Apakah kabel RX dan TX terbalik? (ESP32 RX16 -> TX PZEM, TX17 -> RX PZEM)");
      Serial.println("           3. Apakah tegangan logika VCC PZEM mendapatkan 5V stabil?");
      Serial.println("           4. Apakah ground (GND) ESP32 dan PZEM sudah tersambung bersama?");
    } else {
      successfulReads++;
      float successRate = ((float)successfulReads / (float)totalReads) * 100.0;

      Serial.printf("SUKSES (%lu ms) | V: %5.1f V | I: %5.2f A | P: %6.1f W | E: %7.3f kWh | F: %4.1f Hz | PF: %4.2f [Rate: %.1f%%]\n",
                    duration, voltage, current, power, energy, frequency, pf, successRate);

      // Verifikasi kewajaran nilai (Plausibility Check)
      if (voltage < 150.0 || voltage > 260.0) {
        Serial.printf("       [PERINGATAN] Tegangan (%5.1f V) di luar batas normal PLN (198V - 242V)!\n", voltage);
      }
      if (frequency < 45.0 || frequency > 55.0) {
        Serial.printf("       [PERINGATAN] Frekuensi (%4.1f Hz) di luar batas normal PLN (49.5Hz - 50.5Hz)!\n", frequency);
      }
    }
  }
}
