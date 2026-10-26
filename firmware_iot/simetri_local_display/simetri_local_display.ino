/*
  ==================================================================================
  PROJECT SIMETRI - TAHAP 1: INTEGRASI DISPLAY LOKAL (TANPA FIREBASE / WIFI / NVS)
  ==================================================================================
  Tujuan:
  Mengintegrasikan pembacaan PZEM-004T V4.0, LCD I2C 20x2, tombol fisik, dan
  buzzer dalam satu sketch yang berdiri sendiri TANPA ketergantungan pada
  jaringan (Wi-Fi), cloud (Firebase), RTC/NTP, maupun penyimpanan persisten (NVS).

  SKEMA KONEKSI PIN LENGKAP:
  -----------------------------------------------------------------------------------
  ESP32 Pin          Komponen                 Keterangan
  -----------------------------------------------------------------------------------
  GPIO 16 (RX2) <--- TX PZEM  (via Divider)  R1=1.0kΩ (TX PZEM → GPIO16)
                                               R2=1.5kΩ (GPIO16 → GND)
                                               V_in GPIO16 = 2.83V–3.33V (AMAN)
  GPIO 17 (TX2) ---> RX PZEM                  Langsung (3.3V diterima PZEM)
  5V (VIN)      ---> VCC PZEM                 Daya optocoupler PZEM
  GND           ---> GND PZEM                 Ground bersama (WAJIB!)
  -----------------------------------------------------------------------------------
  GPIO 21 (SDA) ---> SDA LCD I2C              I2C Data (LiquidCrystal_I2C)
  GPIO 22 (SCL) ---> SCL LCD I2C              I2C Clock
  3.3V / 5V     ---> VCC LCD I2C              Daya modul LCD
  GND           ---> GND LCD I2C              Ground
  -----------------------------------------------------------------------------------
  GPIO 25       ---> Tombol BTN_A             Ganti halaman maju / konfirmasi
  GPIO 26       ---> Tombol BTN_B             Ganti halaman mundur
  GPIO 27       ---> Tombol BTN_C             Halaman maju alternatif
  GND           ---> Kaki tombol lainnya      Pakai INPUT_PULLUP (aktif LOW)
  -----------------------------------------------------------------------------------
  GPIO 19       ---> Buzzer aktif             Satu bunyi pendek = tombol ditekan
  GND           ---> Kaki negatif buzzer
  -----------------------------------------------------------------------------------
  GPIO 14       ---> IN Relay                 DINONAKTIFKAN. Kabel jangan dipasang.
                                               ENABLE_RELAY_CONTROL = false
  -----------------------------------------------------------------------------------

  PERINGATAN KESELAMATAN:
  - Chip PZEM membutuhkan tegangan AC (80V–260V) pada terminal L/N untuk merespons.
  - Jangan sentuh terminal AC saat steker PLN terpasang.
  - Relay GPIO14 dilarang diaktifkan sampai ada persetujuan terpisah.
  - Gunakan isolator non-konduktif dan MCB laboratorium 2A saat pengujian AC.

  LIBRARY YANG WAJIB DI-INSTALL DI ARDUINO IDE:
  1. "PZEM004Tv30" oleh Jakub Mandula
  2. "LiquidCrystal I2C" oleh Frank de Brabander

  BOARD SETTING:
  - Board    : ESP32 Dev Module
  - CPU Freq : 240MHz
  - Flash    : 4MB
  - Partition: Default (No OTA)
  ==================================================================================
*/

#include <PZEM004Tv30.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>

// ==================================================================================
// 1. KONFIGURASI PIN HARDWARE
// ==================================================================================
#define PZEM_RX_PIN      16    // RX2 ESP32 — terhubung ke TX PZEM via voltage divider
#define PZEM_TX_PIN      17    // TX2 ESP32 — terhubung langsung ke RX PZEM

#define LCD_I2C_ADDR     0x27  // Alamat I2C LCD (coba 0x3F jika 0x27 tidak respons)
#define LCD_COLS         20    // Lebar LCD dalam karakter
#define LCD_ROWS         2     // Tinggi LCD dalam baris (20x2)

#define BTN_A_PIN        25    // Tombol maju halaman / konfirmasi
#define BTN_B_PIN        26    // Tombol mundur halaman
#define BTN_C_PIN        27    // Tombol maju halaman alternatif
#define BUZZER_PIN       19    // Buzzer aktif (bunyi saat tombol ditekan)

// RELAY GPIO14 — DINONAKTIFKAN sepenuhnya pada tahap ini.
// Ganti menjadi true HANYA setelah verifikasi multimeter & persetujuan terpisah.
#define RELAY_PIN           14
#define ENABLE_RELAY_CONTROL false

// ==================================================================================
// 2. KONFIGURASI WAKTU & HALAMAN
// ==================================================================================
#define SENSOR_READ_INTERVAL_MS   1000  // Baca PZEM setiap 1 detik
#define AUTO_PAGE_INTERVAL_MS     3000  // Pergantian halaman otomatis setiap 3 detik
#define MANUAL_PAGE_HOLD_MS      10000  // Halaman pilihan tombol bertahan 10 detik
#define BTN_DEBOUNCE_MS            50   // Debounce tombol (ms)
#define BUZZER_BEEP_MS             60   // Durasi beep buzzer (ms)

// ==================================================================================
// 3. DEFINISI HALAMAN LCD
// ==================================================================================
enum class LcdPage : uint8_t {
  REALTIME = 0,   // Halaman 0: Tegangan, Arus, Daya real-time
  DAILY    = 1,   // Halaman 1: Energi harian & estimasi biaya
  MONTHLY  = 2,   // Halaman 2: Energi bulanan & estimasi biaya
  PAGE_COUNT = 3  // Total jumlah halaman
};

// ==================================================================================
// 4. INISIALISASI OBJEK HARDWARE
// ==================================================================================
PZEM004Tv30     pzem(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);
LiquidCrystal_I2C lcd(LCD_I2C_ADDR, LCD_COLS, LCD_ROWS);

// ==================================================================================
// 5. VARIABEL STATE GLOBAL
// ==================================================================================

// --- Data Sensor ---
struct SensorData {
  float voltage = 0.0f;
  float current = 0.0f;
  float power   = 0.0f;
  float energy  = 0.0f;   // Register kWh internal PZEM (kumulatif)
  bool  valid   = false;  // true jika bacaan terakhir bukan NaN
};
SensorData sensor;

// --- Akumulasi Energi Lokal ---
// Catatan: nilai ini HILANG saat ESP32 di-reboot karena NVS belum diintegrasikan.
// Integrasi NVS dijadwalkan pada Tahap 2 (menunggu persetujuan).
float lastRawPzem      = -1.0f;  // Pembacaan register PZEM terakhir yang valid (-1 = belum diinisialisasi)
float dailyAccumKwh    = 0.0f;   // Akumulasi energi harian (kWh)
float monthlyAccumKwh  = 0.0f;   // Akumulasi energi bulanan (kWh)

// Tarif placeholder (Rp/kWh) — akan digantikan oleh NVS/Firebase pada tahap berikutnya
const float TARIFF_PER_KWH = 1444.70f;  // Tarif R1/2200VA PLN per Oktober 2026

// --- Navigasi Halaman ---
LcdPage currentPage       = LcdPage::REALTIME;
unsigned long lastPageSwitch = 0;     // Waktu terakhir halaman berpindah
bool manualPageActive     = false;    // true jika user baru saja menekan tombol
unsigned long manualPageAt = 0;       // Waktu user terakhir menekan tombol navigasi

// --- Timer Sensor ---
unsigned long lastSensorRead = 0;

// --- Error Counter ---
uint32_t consecutiveNanCount = 0;  // Jumlah pembacaan NaN berturut-turut
const uint32_t NAN_WARN_THRESHOLD = 3;  // Tampilkan peringatan setelah 3x NaN berturut

// --- Tombol ---
struct ButtonState {
  bool prevRaw = HIGH;  // Status raw terakhir (INPUT_PULLUP: LOW = ditekan)
  bool pressed = false; // Transisi turun (aktif satu frame per penekanan)
};
ButtonState btnA, btnB, btnC;

// --- Buzzer ---
bool     buzzerActive   = false;
unsigned long buzzerEnd = 0;

// ==================================================================================
// 6. KARAKTER KHUSUS LCD (OPSIONAL - SIMBOL KILOWATT)
// ==================================================================================
// Karakter custom: ikon petir (⚡ sederhana 5x8 piksel)
byte charLightning[8] = {
  0b00011,
  0b00110,
  0b01100,
  0b11111,
  0b00110,
  0b01100,
  0b11000,
  0b00000
};

// ==================================================================================
// 7. FUNGSI UTILITAS
// ==================================================================================

/**
 * Membunyikan buzzer selama BUZZER_BEEP_MS milidetik (non-blocking).
 */
void triggerBeep() {
  digitalWrite(BUZZER_PIN, HIGH);
  buzzerActive = true;
  buzzerEnd = millis() + BUZZER_BEEP_MS;
}

/**
 * Update state buzzer — dipanggil setiap loop agar non-blocking.
 */
void updateBuzzer() {
  if (buzzerActive && millis() >= buzzerEnd) {
    digitalWrite(BUZZER_PIN, LOW);
    buzzerActive = false;
  }
}

/**
 * Membaca dan men-debounce tombol.
 * Mendeteksi transisi HIGH->LOW (tombol baru ditekan, aktif satu frame).
 * @param pin    Nomor pin tombol (INPUT_PULLUP, aktif LOW)
 * @param state  Referensi ke ButtonState tombol
 */
void readButton(uint8_t pin, ButtonState &state) {
  bool raw = digitalRead(pin);

  if (state.prevRaw == HIGH && raw == LOW) {
    // Tunggu durasi debounce lalu konfirmasi tombol masih LOW
    delay(BTN_DEBOUNCE_MS);
    raw = digitalRead(pin);
    state.pressed = (raw == LOW);  // Valid hanya jika setelah debounce masih ditekan
  } else {
    state.pressed = false;
  }

  state.prevRaw = raw;
}

/**
 * Membaca sensor PZEM dan memperbarui struct SensorData.
 * Menerapkan validasi NaN dan proteksi penurunan register.
 */
void readPzem() {
  float v = pzem.voltage();
  float i = pzem.current();
  float p = pzem.power();
  float e = pzem.energy();

  // --- Validasi nilai sensor ---
  // Jika salah satu nilai utama adalah NaN, anggap pembacaan gagal
  if (isnan(v) || isnan(i) || isnan(p) || isnan(e)) {
    sensor.valid = false;
    consecutiveNanCount++;

    if (consecutiveNanCount >= NAN_WARN_THRESHOLD) {
      Serial.printf("[PZEM][WARN] %lu pembacaan NaN berturut-turut! Periksa wiring dan tegangan AC.\n",
                    consecutiveNanCount);
    }
    // Jangan ubah lastRawPzem, dailyAccumKwh, maupun monthlyAccumKwh
    return;
  }

  // Pembacaan valid -- reset penghitung error
  consecutiveNanCount = 0;
  sensor.valid   = true;
  sensor.voltage = v;
  sensor.current = i;
  sensor.power   = p;
  sensor.energy  = e;

  // --- Akumulasi delta energi ---
  if (lastRawPzem < 0.0f) {
    // Inisialisasi awal setelah bacaan valid pertama kali
    lastRawPzem = e;
    Serial.printf("[PZEM] Baseline diinisialisasi: %.3f kWh\n", lastRawPzem);
  } else if (e < lastRawPzem) {
    // Penurunan register PZEM terdeteksi (kemungkinan reset hardware / pergantian modul)
    // Kunci delta = 0; jangan kurangi akumulator. Flag peringatan di serial.
    Serial.printf("[PZEM][ANOMALY] Penurunan register! E_now=%.3f < E_last=%.3f. Delta dikunci 0.\n",
                  e, lastRawPzem);
    // lastRawPzem TIDAK diupdate; akumulator TIDAK dikurangi.
    // Perlu konfirmasi teknisi untuk mengupdate baseline (implementasi pada tahap berikutnya).
  } else {
    // Delta normal — tambahkan ke akumulator
    float delta = e - lastRawPzem;

    // Proteksi lonjakan tidak wajar:
    // Delta > 0.05 kWh dalam 1 detik setara > 180 kW — tidak mungkin untuk instalasi rumah tangga
    if (delta > 0.05f) {
      Serial.printf("[PZEM][ANOMALY] Lonjakan tidak wajar! Delta=%.4f kWh (> 0.05 kWh/detik). Ditahan.\n", delta);
      // Tahan bacaan — jangan tambahkan ke akumulator untuk siklus ini
    } else {
      dailyAccumKwh   += delta;
      monthlyAccumKwh += delta;
      lastRawPzem      = e;
    }
  }

  Serial.printf("[PZEM] V:%.1fV I:%.2fA P:%.1fW E:%.3fkWh | day:%.4f mon:%.4f kWh\n",
                v, i, p, e, dailyAccumKwh, monthlyAccumKwh);
}

// ==================================================================================
// 8. FUNGSI RENDER HALAMAN LCD (20x2)
// ==================================================================================
//
// Setiap fungsi menulis tepat 2 baris x 20 karakter.
// Baris 0 = baris atas, Baris 1 = baris bawah.
// Nomor halaman ditulis di bagian akhir baris terkait.
//
// ==================================================================================

/**
 * Halaman 0: Monitoring real-time (V, I, P)
 *
 * Kondisi normal:
 * +--------------------+
 * |V:220.5V I: 0.45A  |  (baris 0: tegangan & arus, 20 char)
 * |P:   99.1W    [1/3]|  (baris 1: daya & nomor halaman, 20 char)
 * +--------------------+
 *
 * Kondisi sensor error:
 * +--------------------+
 * |-- Sensor Error --- |  (20 char)
 * |Cek kabel/AC  [1/3]|  (20 char)
 * +--------------------+
 *
 * Verifikasi panjang (kondisi normal):
 *   Baris 0: "V:"(2)+%5.1f(5)+"V I:"(4)+%5.2f(5)+"A  "(4) = 20 ok
 *   Baris 1: "P:"(2)+%6.1f(6)+"W"(1)+"    [1/3]"(9)+"  "(2) = 20 ok
 */
void renderPageRealtime() {
  char buf[21];  // Buffer 20 karakter + null terminator

  if (!sensor.valid) {
    lcd.setCursor(0, 0);
    lcd.print(F("-- Sensor Error --- "));  // 20 char
    lcd.setCursor(0, 1);
    lcd.print(F("Cek kabel/AC  [1/3]"));   // 19 char (LCD auto-pad)
    return;
  }

  // Baris 0: Tegangan & Arus
  // "V:"(2) + %5.1f "220.5"(5) + "V I:"(4) + %5.2f " 0.45"(5) + "A  "(4) = 20
  snprintf(buf, sizeof(buf), "V:%5.1fV I:%5.2fA  ", sensor.voltage, sensor.current);
  lcd.setCursor(0, 0);
  lcd.print(buf);

  // Baris 1: Daya & nomor halaman
  // "P:"(2) + %6.1f "  99.1"(6) + "W"(1) + "    [1/3]"(9) + "  "(2) = 20
  snprintf(buf, sizeof(buf), "P:%6.1fW    [1/3]  ", sensor.power);
  lcd.setCursor(0, 1);
  lcd.print(buf);
}

/**
 * Halaman 1: Energi & biaya harian
 *
 * +--------------------+
 * |H:  1.234kWh [2/3] |  (baris 0: energi harian & nomor halaman, 20 char)
 * |Rp       1781      |  (baris 1: biaya harian dalam Rupiah, 20 char)
 * +--------------------+
 *
 * Verifikasi panjang:
 *   Baris 0: "H:"(2)+%7.3f(7)+"kWh "(4)+"[2/3]"(5)+"  "(2) = 20 ok
 *   Baris 1: "Rp"(2)+%11.0f(11)+"       "(7) = 20 ok
 */
void renderPageDaily() {
  char buf[21];
  float dailyCost = dailyAccumKwh * TARIFF_PER_KWH;

  // Baris 0: Energi harian & nomor halaman
  snprintf(buf, sizeof(buf), "H:%7.3fkWh [2/3]  ", dailyAccumKwh);
  lcd.setCursor(0, 0);
  lcd.print(buf);

  // Baris 1: Biaya harian (Rupiah, tanpa desimal)
  snprintf(buf, sizeof(buf), "Rp%11.0f       ", dailyCost);
  lcd.setCursor(0, 1);
  lcd.print(buf);
}

/**
 * Halaman 2: Energi & biaya bulanan
 *
 * +--------------------+
 * |B: 45.67kWh  [3/3] |  (baris 0: energi bulanan & nomor halaman, 20 char)
 * |Rp      65943      |  (baris 1: biaya bulanan dalam Rupiah, 20 char)
 * +--------------------+
 *
 * Catatan: akumulasi sejak boot -- NVS belum aktif (Tahap 2).
 *
 * Verifikasi panjang:
 *   Baris 0: "B:"(2)+%7.2f(7)+"kWh "(4)+"[3/3]"(5)+"  "(2) = 20 ok
 *   Baris 1: "Rp"(2)+%11.0f(11)+"       "(7) = 20 ok
 */
void renderPageMonthly() {
  char buf[21];
  float monthlyCost = monthlyAccumKwh * TARIFF_PER_KWH;

  // Baris 0: Energi bulanan & nomor halaman
  snprintf(buf, sizeof(buf), "B:%7.2fkWh [3/3]  ", monthlyAccumKwh);
  lcd.setCursor(0, 0);
  lcd.print(buf);

  // Baris 1: Biaya bulanan (Rupiah, tanpa desimal)
  snprintf(buf, sizeof(buf), "Rp%11.0f       ", monthlyCost);
  lcd.setCursor(0, 1);
  lcd.print(buf);
}

/**
 * Menampilkan konten halaman yang aktif ke LCD.
 */
void renderCurrentPage() {
  switch (currentPage) {
    case LcdPage::REALTIME: renderPageRealtime(); break;
    case LcdPage::DAILY:    renderPageDaily();    break;
    case LcdPage::MONTHLY:  renderPageMonthly();  break;
    default:                renderPageRealtime(); break;
  }
}

// ==================================================================================
// 9. LOGIKA NAVIGASI HALAMAN
// ==================================================================================

/**
 * Pindah ke halaman berikutnya (maju siklik).
 */
void nextPage() {
  uint8_t idx = (static_cast<uint8_t>(currentPage) + 1)
                % static_cast<uint8_t>(LcdPage::PAGE_COUNT);
  currentPage   = static_cast<LcdPage>(idx);
  lastPageSwitch = millis();
}

/**
 * Pindah ke halaman sebelumnya (mundur siklik).
 */
void prevPage() {
  uint8_t total = static_cast<uint8_t>(LcdPage::PAGE_COUNT);
  uint8_t idx   = (static_cast<uint8_t>(currentPage) + total - 1) % total;
  currentPage   = static_cast<LcdPage>(idx);
  lastPageSwitch = millis();
}

// ==================================================================================
// 10. SETUP
// ==================================================================================
void setup() {
  // --- Serial Monitor ---
  Serial.begin(115200);
  delay(500);
  Serial.println(F("\n=================================================="));
  Serial.println(F("  SIMETRI Local Display - Tahap 1 Integrasi Lokal"));
  Serial.println(F("=================================================="));
  Serial.println(F("[CONFIG] Tanpa Wi-Fi | Tanpa Firebase | Tanpa NVS"));
  Serial.printf( "[CONFIG] PZEM RX=GPIO%d, TX=GPIO%d | Baud UART 9600\n",
                 PZEM_RX_PIN, PZEM_TX_PIN);
  Serial.printf( "[CONFIG] LCD I2C addr=0x%02X, %dx%d\n",
                 LCD_I2C_ADDR, LCD_COLS, LCD_ROWS);
  Serial.printf( "[CONFIG] BTN_A=GPIO%d BTN_B=GPIO%d BTN_C=GPIO%d BUZZ=GPIO%d\n",
                 BTN_A_PIN, BTN_B_PIN, BTN_C_PIN, BUZZER_PIN);
  Serial.printf( "[CONFIG] Relay GPIO%d = %s\n",
                 RELAY_PIN,
                 ENABLE_RELAY_CONTROL ? "AKTIF (BAHAYA!)" : "DINONAKTIFKAN");
  Serial.printf( "[CONFIG] Tarif: Rp%.2f/kWh (placeholder)\n", TARIFF_PER_KWH);
  Serial.println(F("[WARN]  Akumulasi akan HILANG saat reboot (NVS belum aktif)"));

  // --- Pin Relay (dinonaktifkan) ---
  #if ENABLE_RELAY_CONTROL == false
  // Jangan set relay ke OUTPUT agar tidak ada arus tidak sengaja ke pin relay
  Serial.println(F("[RELAY] GPIO14 DINONAKTIFKAN — ENABLE_RELAY_CONTROL = false"));
  #else
  // Ini tidak akan pernah dikompilasi kecuali ENABLE_RELAY_CONTROL diubah ke true
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);  // default: relay off
  #endif

  // --- Pin Tombol (INPUT_PULLUP: LOW = ditekan) ---
  pinMode(BTN_A_PIN, INPUT_PULLUP);
  pinMode(BTN_B_PIN, INPUT_PULLUP);
  pinMode(BTN_C_PIN, INPUT_PULLUP);
  Serial.println(F("[BTN]  Tombol GPIO25/26/27 siap (INPUT_PULLUP, aktif LOW)"));

  // --- Buzzer ---
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  Serial.println(F("[BUZZ] Buzzer GPIO19 siap"));

  // --- LCD I2C ---
  Wire.begin();  // SDA=GPIO21, SCL=GPIO22 (default ESP32)
  lcd.init();
  lcd.backlight();
  lcd.createChar(0, charLightning);  // Daftarkan karakter custom petir di slot 0

  // Tampilan splash screen (2 baris)
  lcd.setCursor(0, 0);
  lcd.print(F(" SIMETRI SmartMeter "));  // 20 char
  lcd.setCursor(0, 1);
  lcd.print(F("  Inisialisasi...   "));  // 20 char
  Serial.println(F("[LCD]  Splash screen ditampilkan (20x2)"));

  // --- PZEM Serial2 ---
  // Library PZEM004Tv30 menginisialisasi Serial2 secara internal.
  // Tidak perlu memanggil Serial2.begin() secara manual.
  Serial.println(F("[PZEM] HardwareSerial2 siap (via PZEM004Tv30)"));
  Serial.println(F("[PZEM] Menunggu bacaan valid pertama..."));

  // Delay splash screen sebelum loop dimulai
  delay(2000);
  lcd.clear();

  // Beep tanda inisialisasi selesai
  triggerBeep();
  delay(BUZZER_BEEP_MS + 10);
  updateBuzzer();

  lastPageSwitch = millis();
  lastSensorRead = millis();

  Serial.println(F("[BOOT] Setup selesai. Memasuki loop utama.\n"));
}

// ==================================================================================
// 11. LOOP UTAMA
// ==================================================================================
void loop() {
  unsigned long now = millis();

  // -----------------------------------------------------------------------
  // 11.1. Baca tombol
  // -----------------------------------------------------------------------
  readButton(BTN_A_PIN, btnA);
  readButton(BTN_B_PIN, btnB);
  readButton(BTN_C_PIN, btnC);

  // --- Aksi BTN_A: halaman maju ---
  if (btnA.pressed) {
    triggerBeep();
    nextPage();
    manualPageActive = true;
    manualPageAt     = now;
    Serial.printf("[BTN_A] Halaman maju → %d\n", static_cast<int>(currentPage));
  }

  // --- Aksi BTN_B: halaman mundur ---
  if (btnB.pressed) {
    triggerBeep();
    prevPage();
    manualPageActive = true;
    manualPageAt     = now;
    Serial.printf("[BTN_B] Halaman mundur → %d\n", static_cast<int>(currentPage));
  }

  // --- Aksi BTN_C: halaman maju (alternatif BTN_A) ---
  if (btnC.pressed) {
    triggerBeep();
    nextPage();
    manualPageActive = true;
    manualPageAt     = now;
    Serial.printf("[BTN_C] Halaman maju -> %d\n", static_cast<int>(currentPage));
  }

  // -----------------------------------------------------------------------
  // 11.2. Update buzzer (non-blocking)
  // -----------------------------------------------------------------------
  updateBuzzer();

  // -----------------------------------------------------------------------
  // 11.3. Baca sensor PZEM setiap SENSOR_READ_INTERVAL_MS (1 detik)
  // -----------------------------------------------------------------------
  if (now - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
    lastSensorRead = now;
    readPzem();
  }

  // -----------------------------------------------------------------------
  // 11.4. Pergantian halaman otomatis
  // -----------------------------------------------------------------------
  if (manualPageActive) {
    // Halaman manual: bertahan MANUAL_PAGE_HOLD_MS (10 detik)
    if (now - manualPageAt >= MANUAL_PAGE_HOLD_MS) {
      // Setelah hold habis, kembali ke mode auto-rotate
      manualPageActive = false;
      lastPageSwitch   = now;
    }
  } else {
    // Mode auto-rotate: ganti setiap AUTO_PAGE_INTERVAL_MS (3 detik)
    if (now - lastPageSwitch >= AUTO_PAGE_INTERVAL_MS) {
      nextPage();
      // nextPage() sudah mengupdate lastPageSwitch
    }
  }

  // -----------------------------------------------------------------------
  // 11.5. Render halaman ke LCD
  //        (dipanggil setiap loop agar nilai sensor selalu terbaru)
  // -----------------------------------------------------------------------
  renderCurrentPage();

  // Delay singkat untuk mencegah CPU 100% — tidak memblokir komunikasi PZEM
  delay(50);
}
