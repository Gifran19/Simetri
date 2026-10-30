import 'package:flutter_test/flutter_test.dart';

/// Simulasi State Machine Logika Firmware ESP32
/// Merefleksikan implementasi di `firmware_iot/simetri_firebase_integrated/simetri_firebase_integrated.ino`
class Esp32FirmwareHistorySimulator {
  int kalenderTahun = 0;
  int kalenderBulan = -1; // 0..11
  int kalenderHari = 0;   // 1..31
  int kalenderHariMinggu = 0; // 0=Sen .. 6=Min
  String kalenderTanggalStr = '';
  bool waktuKalenderValid = false;

  double energyAwalHari = double.nan;
  double energyAwalBulan = double.nan;
  double energiHari = 0.0;
  double energiBulan = 0.0;
  double tarifPerKwh = 1500.0;

  // NVS Flash storage simulation
  final Map<String, dynamic> nvsStorage = {};

  // Cloud RTDB simulation
  final Map<String, dynamic> cloudRtdb = {};

  // Pending queue
  String pendingDayDate = '';
  int pendingDayYear = 0;
  double pendingDayKwh = 0.0;
  double pendingDayCost = 0.0;
  int pendingDayWday = 0;
  bool hasPendingDay = false;

  int pendingMonthYear = 0;
  int pendingMonthIdx = -1;
  double pendingMonthKwh = 0.0;
  double pendingMonthCost = 0.0;
  bool hasPendingMonth = false;

  // 12-month cache
  final List<double> energiBulanCached = List<double>.filled(12, 0.0);
  final List<double> biayaBulanCached = List<double>.filled(12, 0.0);
  int tahunTerdaftarDiCloud = 0;

  void boot(double pzemEnergy) {
    waktuKalenderValid = false;
    final savedDayStart = nvsStorage['e_start_day'] as double?;
    final savedMonStart = nvsStorage['e_start_mon'] as double?;
    final savedDay = nvsStorage['cal_day'] as int? ?? 0;
    final savedMon = nvsStorage['cal_mon'] as int? ?? -1;
    final savedYear = nvsStorage['cal_year'] as int? ?? 0;

    if (savedDayStart != null && savedDay > 0) {
      energyAwalHari = savedDayStart;
      kalenderHari = savedDay;
    }
    if (savedMonStart != null && savedMon >= 0 && savedYear > 0) {
      energyAwalBulan = savedMonStart;
      kalenderBulan = savedMon;
      kalenderTahun = savedYear;
    }

    if (energyAwalHari.isNaN) energyAwalHari = pzemEnergy;
    if (energyAwalBulan.isNaN) energyAwalBulan = pzemEnergy;

    // Restore pending queue
    hasPendingDay = nvsStorage['p_day_pend'] as bool? ?? false;
    if (hasPendingDay) {
      pendingDayDate = nvsStorage['p_day_date'] as String? ?? '';
      pendingDayYear = nvsStorage['p_day_year'] as int? ?? 0;
      pendingDayKwh = nvsStorage['p_day_kwh'] as double? ?? 0.0;
      pendingDayCost = nvsStorage['p_day_cost'] as double? ?? 0.0;
      pendingDayWday = nvsStorage['p_day_wday'] as int? ?? 0;
    }

    hasPendingMonth = nvsStorage['p_mon_pend'] as bool? ?? false;
    if (hasPendingMonth) {
      pendingMonthYear = nvsStorage['p_mon_year'] as int? ?? 0;
      pendingMonthIdx = nvsStorage['p_mon_idx'] as int? ?? -1;
      pendingMonthKwh = nvsStorage['p_mon_kwh'] as double? ?? 0.0;
      pendingMonthCost = nvsStorage['p_mon_cost'] as double? ?? 0.0;
    }

    for (int m = 0; m < 12; m++) {
      energiBulanCached[m] = (nvsStorage['m_kwh_$m'] as double?) ?? 0.0;
      biayaBulanCached[m] = (nvsStorage['m_cost_$m'] as double?) ?? 0.0;
    }
  }

  void updateCalendarAndCalculate(DateTime wibTime, double currentPzem) {
    final tahun = wibTime.year;
    final bulan = wibTime.month - 1; // 0..11
    final hari = wibTime.day;
    final hariM = (wibTime.weekday - 1); // 0=Sen .. 6=Min

    if (!waktuKalenderValid) {
      waktuKalenderValid = true;
      kalenderTahun = tahun;
      kalenderBulan = bulan;
      kalenderHari = hari;
      kalenderHariMinggu = hariM;
      kalenderTanggalStr = '${tahun.toString().padLeft(4, '0')}-${(bulan + 1).toString().padLeft(2, '0')}-${hari.toString().padLeft(2, '0')}';

      final savedYear = nvsStorage['cal_year'] as int? ?? 0;
      final savedMon = nvsStorage['cal_mon'] as int? ?? -1;
      final savedDay = nvsStorage['cal_day'] as int? ?? 0;

      if (savedYear == 0 || nvsStorage['e_start_day'] == null) {
        nvsStorage['e_start_day'] = energyAwalHari;
        nvsStorage['e_start_mon'] = energyAwalBulan;
        nvsStorage['cal_day'] = hari;
        nvsStorage['cal_mon'] = bulan;
        nvsStorage['cal_year'] = tahun;
      } else if (savedYear > 0 && (savedYear != tahun || savedMon != bulan || savedDay != hari)) {
        // Ganti hari saat offline
        if (!energyAwalHari.isNaN) {
          final lastDayKwh = (currentPzem - energyAwalHari).clamp(0.0, double.infinity);
          final lastDayCost = (lastDayKwh * tarifPerKwh).roundToDouble();

          pendingDayDate = '${savedYear.toString().padLeft(4, '0')}-${(savedMon + 1).toString().padLeft(2, '0')}-${savedDay.toString().padLeft(2, '0')}';
          pendingDayYear = savedYear;
          pendingDayKwh = lastDayKwh;
          pendingDayCost = lastDayCost;
          pendingDayWday = (hariM + 6) % 7;
          hasPendingDay = true;

          nvsStorage['p_day_date'] = pendingDayDate;
          nvsStorage['p_day_year'] = pendingDayYear;
          nvsStorage['p_day_kwh'] = pendingDayKwh;
          nvsStorage['p_day_cost'] = pendingDayCost;
          nvsStorage['p_day_wday'] = pendingDayWday;
          nvsStorage['p_day_pend'] = true;
        }

        energyAwalHari = currentPzem;
        energiHari = 0.0;
        nvsStorage['e_start_day'] = energyAwalHari;
        nvsStorage['cal_day'] = hari;

        if (savedYear != tahun || savedMon != bulan) {
          energyAwalBulan = currentPzem;
          energiBulan = 0.0;
          nvsStorage['e_start_mon'] = energyAwalBulan;
          nvsStorage['cal_mon'] = bulan;
          nvsStorage['cal_year'] = tahun;
        }
      }
    } else if (hari != kalenderHari || bulan != kalenderBulan || tahun != kalenderTahun) {
      // Rollover tengah malam saat menyala
      pendingDayDate = '${kalenderTahun.toString().padLeft(4, '0')}-${(kalenderBulan + 1).toString().padLeft(2, '0')}-${kalenderHari.toString().padLeft(2, '0')}';
      pendingDayYear = kalenderTahun;
      pendingDayKwh = energiHari;
      pendingDayCost = (energiHari * tarifPerKwh).roundToDouble();
      pendingDayWday = kalenderHariMinggu;
      hasPendingDay = true;

      nvsStorage['p_day_date'] = pendingDayDate;
      nvsStorage['p_day_year'] = pendingDayYear;
      nvsStorage['p_day_kwh'] = pendingDayKwh;
      nvsStorage['p_day_cost'] = pendingDayCost;
      nvsStorage['p_day_wday'] = pendingDayWday;
      nvsStorage['p_day_pend'] = true;

      if (bulan != kalenderBulan || tahun != kalenderTahun) {
        pendingMonthYear = kalenderTahun;
        pendingMonthIdx = kalenderBulan;
        pendingMonthKwh = energiBulan;
        pendingMonthCost = (energiBulan * tarifPerKwh).roundToDouble();
        hasPendingMonth = true;

        nvsStorage['p_mon_year'] = pendingMonthYear;
        nvsStorage['p_mon_idx'] = pendingMonthIdx;
        nvsStorage['p_mon_kwh'] = pendingMonthKwh;
        nvsStorage['p_mon_cost'] = pendingMonthCost;
        nvsStorage['p_mon_pend'] = true;

        energiBulanCached[kalenderBulan] = pendingMonthKwh;
        biayaBulanCached[kalenderBulan] = pendingMonthCost;
        nvsStorage['m_kwh_$kalenderBulan'] = pendingMonthKwh;
        nvsStorage['m_cost_$kalenderBulan'] = pendingMonthCost;

        energyAwalBulan = currentPzem;
        energiBulan = 0.0;
        nvsStorage['e_start_mon'] = energyAwalBulan;
        nvsStorage['cal_mon'] = bulan;
        nvsStorage['cal_year'] = tahun;

        if (tahun != kalenderTahun) {
          for (int m = 0; m < 12; m++) {
            energiBulanCached[m] = 0.0;
            biayaBulanCached[m] = 0.0;
            nvsStorage['m_kwh_$m'] = 0.0;
            nvsStorage['m_cost_$m'] = 0.0;
          }
          tahunTerdaftarDiCloud = 0;
        }
      }

      energyAwalHari = currentPzem;
      energiHari = 0.0;
      nvsStorage['e_start_day'] = energyAwalHari;
      nvsStorage['cal_day'] = hari;

      kalenderTahun = tahun;
      kalenderBulan = bulan;
      kalenderHari = hari;
      kalenderHariMinggu = hariM;
      kalenderTanggalStr = '${tahun.toString().padLeft(4, '0')}-${(bulan + 1).toString().padLeft(2, '0')}-${hari.toString().padLeft(2, '0')}';
      nvsStorage['cal_date'] = kalenderTanggalStr;
    }

    energiHari = (currentPzem - energyAwalHari).clamp(0.0, double.infinity);
    energiBulan = (currentPzem - energyAwalBulan).clamp(0.0, double.infinity);
  }

  /// Sinkronisasi ke RTDB (mensimulasikan PATCH ke Firebase)
  bool syncToCloud({required bool isOnline}) {
    if (!isOnline || !waktuKalenderValid) return false;

    // 1. Pastikan tahun kalender terdaftar di available_years secara non-destruktif
    final existingYears = (cloudRtdb['available_years'] as List<dynamic>?)?.cast<int>() ?? <int>[];
    if (!existingYears.contains(kalenderTahun)) {
      final updated = List<int>.from(existingYears)..add(kalenderTahun);
      updated.sort((a, b) => b.compareTo(a));
      cloudRtdb['available_years'] = updated;
    }
    tahunTerdaftarDiCloud = kalenderTahun;

    // 2. Summary tahunan
    energiBulanCached[kalenderBulan] = energiBulan;
    biayaBulanCached[kalenderBulan] = (energiBulan * tarifPerKwh).roundToDouble();

    double totalTahunEnergi = 0.0;
    double totalTahunBiaya = 0.0;
    for (int m = 0; m < 12; m++) {
      totalTahunEnergi += energiBulanCached[m];
      totalTahunBiaya += biayaBulanCached[m];
    }

    // 3. Tulis payload
    final dailyCost = (energiHari * tarifPerKwh).roundToDouble();
    final monthlyCost = (energiBulan * tarifPerKwh).roundToDouble();

    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/energy_kwh'] = energiHari;
    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/cost_rp'] = dailyCost;
    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/day_of_week'] = kalenderHariMinggu;

    cloudRtdb['$kalenderTahun/weekly_energy/$kalenderHariMinggu'] = energiHari;
    cloudRtdb['$kalenderTahun/weekly_cost/$kalenderHariMinggu'] = dailyCost;

    cloudRtdb['$kalenderTahun/monthly_energy/$kalenderBulan'] = energiBulan;
    cloudRtdb['$kalenderTahun/monthly_cost/$kalenderBulan'] = monthlyCost;

    cloudRtdb['$kalenderTahun/summary/total_energy'] = totalTahunEnergi;
    cloudRtdb['$kalenderTahun/summary/total_cost'] = totalTahunBiaya;

    // 4. Flush pending
    if (hasPendingDay) {
      cloudRtdb['$pendingDayYear/daily_history/$pendingDayDate/energy_kwh'] = pendingDayKwh;
      cloudRtdb['$pendingDayYear/daily_history/$pendingDayDate/cost_rp'] = pendingDayCost;
      cloudRtdb['$pendingDayYear/daily_history/$pendingDayDate/day_of_week'] = pendingDayWday;
      hasPendingDay = false;
      nvsStorage['p_day_pend'] = false;
    }

    if (hasPendingMonth) {
      cloudRtdb['$pendingMonthYear/monthly_energy/$pendingMonthIdx'] = pendingMonthKwh;
      cloudRtdb['$pendingMonthYear/monthly_cost/$pendingMonthIdx'] = pendingMonthCost;
      hasPendingMonth = false;
      nvsStorage['p_mon_pend'] = false;
    }

    return true;
  }
}

void main() {
  group('Firmware Logic State Machine Tests', () {
    test('1. Pergantian Hari (Midnight Rollover) mengarsipkan hari sebelumnya dan mereset energi hari baru', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(100.0);

      // Hari 1: 2026-10-29 (Kamis, Wday 3)
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 29, 22, 0), 102.5);
      expect(sim.energiHari, closeTo(2.5, 0.001));

      // Rollover tengah malam ke 2026-10-30 00:01 (Jumat, Wday 4)
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 0, 1), 102.5);

      // Hari 29 tersimpan di antrean pending
      expect(sim.hasPendingDay, isTrue);
      expect(sim.pendingDayDate, equals('2026-10-29'));
      expect(sim.pendingDayKwh, closeTo(2.5, 0.001));

      // Hari 30 mulai dari 0.0
      expect(sim.energiHari, equals(0.0));

      // Bertambah di siang hari
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 12, 0), 103.2);
      expect(sim.energiHari, closeTo(0.7, 0.001));
    });

    test('2. Pergantian Minggu: weekly_energy menggunakan indeks 0..6 sedangkan daily_history menyimpan tanggal lengkap YYYY-MM-DD', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(200.0);

      // Minggu 1: Minggu (2026-11-01, Wday 6)
      sim.updateCalendarAndCalculate(DateTime(2026, 11, 1, 18, 0), 205.0);
      sim.syncToCloud(isOnline: true);

      expect(sim.cloudRtdb['2026/weekly_energy/6'], closeTo(5.0, 0.001));
      expect(sim.cloudRtdb['2026/daily_history/2026-11-01/energy_kwh'], closeTo(5.0, 0.001));

      // Minggu 2: Senin (2026-11-02, Wday 0) rollover jam 00:01
      sim.updateCalendarAndCalculate(DateTime(2026, 11, 2, 0, 1), 205.0);
      // Di siang hari meter bertambah 1.2 kWh menjadi 206.2
      sim.updateCalendarAndCalculate(DateTime(2026, 11, 2, 12, 0), 206.2);
      sim.syncToCloud(isOnline: true);

      expect(sim.cloudRtdb['2026/weekly_energy/0'], closeTo(1.2, 0.001));
      expect(sim.cloudRtdb['2026/daily_history/2026-11-02/energy_kwh'], closeTo(1.2, 0.001));
      // Arsip tanggal 2026-11-01 tetap utuh di daily_history
      expect(sim.cloudRtdb['2026/daily_history/2026-11-01/energy_kwh'], closeTo(5.0, 0.001));
    });

    test('3. Pergantian Bulan & Ringkasan Tahunan: total_energy menghitung seluruh bulan yang tersedia, bukan hanya bulan aktif', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(300.0);

      // Simulasikan bulan Oktober (bulan ke-9) = 50 kWh
      sim.energiBulanCached[9] = 50.0;
      sim.biayaBulanCached[9] = 75000.0;

      // Masuk bulan November (bulan ke-10): akumulasi 15 kWh
      sim.updateCalendarAndCalculate(DateTime(2026, 11, 10, 10, 0), 315.0);
      sim.syncToCloud(isOnline: true);

      expect(sim.energiBulan, closeTo(15.0, 0.001));
      // Total tahunan harus 50.0 (Okt) + 15.0 (Nov) = 65.0 kWh!
      expect(sim.cloudRtdb['2026/summary/total_energy'], closeTo(65.0, 0.001));
      expect(sim.cloudRtdb['2026/summary/total_cost'], closeTo(75000.0 + 22500.0, 0.001));
    });

    test('4. Pergantian Tahun: mendaftarkan tahun baru ke available_years tanpa menghapus tahun lama', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.cloudRtdb['available_years'] = [2026, 2025, 2024];
      sim.boot(500.0);

      // Tahun baru 2027
      sim.updateCalendarAndCalculate(DateTime(2027, 1, 1, 1, 0), 501.0);
      sim.syncToCloud(isOnline: true);

      final years = sim.cloudRtdb['available_years'] as List<int>;
      expect(years, contains(2027));
      expect(years, contains(2026));
      expect(years, contains(2025));
      expect(years, contains(2024));
      expect(years.first, equals(2027)); // descending
    });

    test('5. Restart ESP32 di hari yang sama mempertahankan baseline dan tidak mereset energi hari berjalan', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(100.0);

      // Modul berjalan di siang hari
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 12, 0), 104.5);
      expect(sim.energiHari, closeTo(4.5, 0.001));

      // Simulasikan restart modul ESP32
      final simAfterReboot = Esp32FirmwareHistorySimulator();
      // NVS masih tersimpan dari sim sebelumnya
      simAfterReboot.nvsStorage.addAll(sim.nvsStorage);
      simAfterReboot.boot(104.6); // PZEM sedikit bertambah

      simAfterReboot.updateCalendarAndCalculate(DateTime(2026, 10, 30, 12, 5), 104.6);
      // Energi hari berjalan TIDAK reset ke 0.0, melainkan 4.6 kWh!
      expect(simAfterReboot.energiHari, closeTo(4.6, 0.001));
    });

    test('6. Pemulihan Koneksi: Rollover saat OFFLINE tersimpan di NVS dan terkirim saat ONLINE', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(100.0);

      // Malam hari online
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 29, 23, 0), 103.0);
      sim.syncToCloud(isOnline: true);

      // Tengah malam internet terputus (OFFLINE)
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 0, 5), 103.0);
      final syncedOffline = sim.syncToCloud(isOnline: false);
      expect(syncedOffline, isFalse);
      expect(sim.hasPendingDay, isTrue);

      // Siang hari 10:00 internet pulih (ONLINE)
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 10, 0), 104.2);
      final syncedOnline = sim.syncToCloud(isOnline: true);
      expect(syncedOnline, isTrue);

      // Verifikasi di cloud: baik tanggal 29 maupun tanggal 30 masuk dengan benar!
      expect(sim.cloudRtdb['2026/daily_history/2026-10-29/energy_kwh'], closeTo(3.0, 0.001));
      expect(sim.cloudRtdb['2026/daily_history/2026-10-30/energy_kwh'], closeTo(1.2, 0.001));
      // Antrean pending telah bersih
      expect(sim.hasPendingDay, isFalse);
    });

    test('7. Pengiriman ulang (Idempotensi): Resend data berkali-kali tidak menggandakan energi atau biaya', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(100.0);

      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 14, 0), 102.0);

      // Kirim 5 kali berturut-turut
      for (int i = 0; i < 5; i++) {
        sim.syncToCloud(isOnline: true);
      }

      // Nilai di database tetap 2.0 kWh, tidak pernah menjadi 10.0 kWh
      expect(sim.cloudRtdb['2026/daily_history/2026-10-30/energy_kwh'], closeTo(2.0, 0.001));
      expect(sim.cloudRtdb['2026/summary/total_energy'], closeTo(2.0, 0.001));
    });
  });
}
