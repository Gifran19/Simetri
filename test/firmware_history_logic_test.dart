import 'package:flutter_test/flutter_test.dart';

/// Catatan antrean harian offline di firmware ESP32
class PendingDayRecord {
  String date;
  int year;
  double kwh;
  double cost;
  int wday;

  PendingDayRecord({
    required this.date,
    required this.year,
    required this.kwh,
    required this.cost,
    required this.wday,
  });
}

/// Simulasi State Machine Logika Firmware ESP32
/// Merefleksikan implementasi aktual di `firmware_iot/simetri_firebase_integrated/simetri_firebase_integrated.ino`
///
/// CATATAN PENTING:
/// Kelas ini adalah MODEL SIMULASI LOGIKA berbasis Dart untuk memverifikasi algoritma,
/// state transitions, dan penanganan edge cases (rollover, restart, offline queue, idempotensi)
/// sebelum firmware C++ di-flash ke hardware fisik ESP32.
class Esp32FirmwareHistorySimulator {
  static const int maxPendingDays = 7;

  int kalenderTahun = 0;
  int kalenderBulan = -1; // 0..11
  int kalenderHari = 0;   // 1..31
  int kalenderHariMinggu = 0; // 0=Sen .. 6=Min
  String kalenderTanggalStr = '';
  bool waktuKalenderValid = false;
  bool perluResetMingguan = false;

  double energyAwalHari = double.nan;
  double energyAwalBulan = double.nan;
  double energiHari = 0.0;
  double energiBulan = 0.0;
  double tarifPerKwh = 1500.0;

  // NVS Flash storage simulation
  final Map<String, dynamic> nvsStorage = {};

  // Cloud RTDB simulation
  final Map<String, dynamic> cloudRtdb = {};

  // Multi-day Pending Queue (maksimal 7 hari)
  final List<PendingDayRecord> pendingDays = [];

  int pendingMonthYear = 0;
  int pendingMonthIdx = -1;
  double pendingMonthKwh = 0.0;
  double pendingMonthCost = 0.0;
  bool hasPendingMonth = false;

  // 12-month cache
  final List<double> energiBulanCached = List<double>.filled(12, 0.0);
  final List<double> biayaBulanCached = List<double>.filled(12, 0.0);
  int cachedYear = 0;
  bool monthlyCacheLoaded = false;
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

    // Restore multi-day pending queue from NVS
    pendingDays.clear();
    final cnt = nvsStorage['p_day_cnt'] as int? ?? 0;
    final safeCnt = cnt.clamp(0, maxPendingDays);
    for (int i = 0; i < safeCnt; i++) {
      final d = nvsStorage['pd_d_$i'] as String? ?? '';
      final y = nvsStorage['pd_y_$i'] as int? ?? 0;
      final k = nvsStorage['pd_k_$i'] as double? ?? 0.0;
      final c = nvsStorage['pd_c_$i'] as double? ?? 0.0;
      final w = nvsStorage['pd_w_$i'] as int? ?? 0;
      if (d.isNotEmpty && k > 0.0) {
        pendingDays.add(PendingDayRecord(date: d, year: y, kwh: k, cost: c, wday: w));
      }
    }

    hasPendingMonth = nvsStorage['p_mon_pend'] as bool? ?? false;
    if (hasPendingMonth) {
      pendingMonthYear = nvsStorage['p_mon_year'] as int? ?? 0;
      pendingMonthIdx = nvsStorage['p_mon_idx'] as int? ?? -1;
      pendingMonthKwh = nvsStorage['p_mon_kwh'] as double? ?? 0.0;
      pendingMonthCost = nvsStorage['p_mon_cost'] as double? ?? 0.0;
    }

    cachedYear = nvsStorage['c_year'] as int? ?? 0;
    for (int m = 0; m < 12; m++) {
      energiBulanCached[m] = (nvsStorage['m_kwh_$m'] as double?) ?? 0.0;
      biayaBulanCached[m] = (nvsStorage['m_cost_$m'] as double?) ?? 0.0;
    }
  }

  void _simpanPendingKeNvs() {
    nvsStorage['p_day_cnt'] = pendingDays.length;
    for (int i = 0; i < pendingDays.length; i++) {
      nvsStorage['pd_d_$i'] = pendingDays[i].date;
      nvsStorage['pd_y_$i'] = pendingDays[i].year;
      nvsStorage['pd_k_$i'] = pendingDays[i].kwh;
      nvsStorage['pd_c_$i'] = pendingDays[i].cost;
      nvsStorage['pd_w_$i'] = pendingDays[i].wday;
    }
  }

  void antrekanHariSelesai(String dateStr, int yr, double kwh, double cost, int wd) {
    if (kwh <= 0.0001 && cost <= 0.1) return;

    // Idempotensi dalam antrean lokal
    for (int i = 0; i < pendingDays.length; i++) {
      if (pendingDays[i].date == dateStr) {
        pendingDays[i].kwh = kwh;
        pendingDays[i].cost = cost;
        pendingDays[i].wday = wd;
        _simpanPendingKeNvs();
        return;
      }
    }

    if (pendingDays.length < maxPendingDays) {
      pendingDays.add(PendingDayRecord(date: dateStr, year: yr, kwh: kwh, cost: cost, wday: wd));
    } else {
      // FIFO ring buffer jika penuh (kapasitas maksimal 7 hari)
      pendingDays.removeAt(0);
      pendingDays.add(PendingDayRecord(date: dateStr, year: yr, kwh: kwh, cost: cost, wday: wd));
    }
    _simpanPendingKeNvs();
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
        // Ganti hari saat modul offline / mati
        if (!energyAwalHari.isNaN) {
          final lastDayKwh = (currentPzem - energyAwalHari).clamp(0.0, double.infinity);
          final lastDayCost = (lastDayKwh * tarifPerKwh).roundToDouble();
          final lastDateStr = '${savedYear.toString().padLeft(4, '0')}-${(savedMon + 1).toString().padLeft(2, '0')}-${savedDay.toString().padLeft(2, '0')}';
          final lastWday = (hariM + 6) % 7;

          antrekanHariSelesai(lastDateStr, savedYear, lastDayKwh, lastDayCost, lastWday);
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

      // Validasi cache tahunan
      if (cachedYear != kalenderTahun && kalenderTahun > 0) {
        for (int m = 0; m < 12; m++) {
          energiBulanCached[m] = 0.0;
          biayaBulanCached[m] = 0.0;
          nvsStorage['m_kwh_$m'] = 0.0;
          nvsStorage['m_cost_$m'] = 0.0;
        }
        cachedYear = kalenderTahun;
        nvsStorage['c_year'] = cachedYear;
        monthlyCacheLoaded = false;
      }
    } else if (hari != kalenderHari || bulan != kalenderBulan || tahun != kalenderTahun) {
      // Rollover tengah malam saat modul menyala aktif
      final prevDateStr = '${kalenderTahun.toString().padLeft(4, '0')}-${(kalenderBulan + 1).toString().padLeft(2, '0')}-${kalenderHari.toString().padLeft(2, '0')}';
      final prevDayCost = (energiHari * tarifPerKwh).roundToDouble();

      antrekanHariSelesai(prevDateStr, kalenderTahun, energiHari, prevDayCost, kalenderHariMinggu);

      // Cek apakah masuk hari Senin (reset mingguan)
      if (hariM == 0 && kalenderHariMinggu != 0) {
        perluResetMingguan = true;
      }

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
          cachedYear = tahun;
          nvsStorage['c_year'] = cachedYear;
          monthlyCacheLoaded = false;
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

    // 1. Daftarkan tahun ke available_years tanpa menghapus tahun lama
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

    // A. Daily history per tanggal kalender lengkap
    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/energy_kwh'] = energiHari;
    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/cost_rp'] = dailyCost;
    cloudRtdb['$kalenderTahun/daily_history/$kalenderTanggalStr/day_of_week'] = kalenderHariMinggu;

    // B. Weekly energy (0..6)
    cloudRtdb['$kalenderTahun/weekly_energy/$kalenderHariMinggu'] = energiHari;
    cloudRtdb['$kalenderTahun/weekly_cost/$kalenderHariMinggu'] = dailyCost;

    if (perluResetMingguan) {
      for (int d = 1; d < 7; d++) {
        cloudRtdb['$kalenderTahun/weekly_energy/$d'] = 0.0;
        cloudRtdb['$kalenderTahun/weekly_cost/$d'] = 0.0;
      }
      perluResetMingguan = false;
    }

    // C. Monthly energy
    cloudRtdb['$kalenderTahun/monthly_energy/$kalenderBulan'] = energiBulan;
    cloudRtdb['$kalenderTahun/monthly_cost/$kalenderBulan'] = monthlyCost;

    // D. Summary Tahunan: HANYA ditulis jika riwayat bulanan terkonfirmasi (tidak menimpa parsial/nol)
    if (monthlyCacheLoaded || kalenderBulan == 0) {
      cloudRtdb['$kalenderTahun/summary/total_energy'] = totalTahunEnergi;
      cloudRtdb['$kalenderTahun/summary/total_cost'] = totalTahunBiaya;
    }

    // E. Flush multi-day pending queue
    for (final p in pendingDays) {
      cloudRtdb['${p.year}/daily_history/${p.date}/energy_kwh'] = p.kwh;
      cloudRtdb['${p.year}/daily_history/${p.date}/cost_rp'] = p.cost;
      cloudRtdb['${p.year}/daily_history/${p.date}/day_of_week'] = p.wday;
    }
    pendingDays.clear();
    nvsStorage['p_day_cnt'] = 0;

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
      expect(sim.pendingDays.length, equals(1));
      expect(sim.pendingDays.first.date, equals('2026-10-29'));
      expect(sim.pendingDays.first.kwh, closeTo(2.5, 0.001));

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

    test('3. Pergantian Bulan & Ringkasan Tahunan: total_energy menghitung seluruh bulan yang tersedia saat cache valid', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.nvsStorage['c_year'] = 2026;
      sim.boot(300.0);
      sim.monthlyCacheLoaded = true; // Cache bulanan telah terkonfirmasi
      sim.cachedYear = 2026;

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
      expect(sim.pendingDays.length, equals(1));

      // Siang hari 10:00 internet pulih (ONLINE)
      sim.updateCalendarAndCalculate(DateTime(2026, 10, 30, 10, 0), 104.2);
      final syncedOnline = sim.syncToCloud(isOnline: true);
      expect(syncedOnline, isTrue);

      // Verifikasi di cloud: baik tanggal 29 maupun tanggal 30 masuk dengan benar!
      expect(sim.cloudRtdb['2026/daily_history/2026-10-29/energy_kwh'], closeTo(3.0, 0.001));
      expect(sim.cloudRtdb['2026/daily_history/2026-10-30/energy_kwh'], closeTo(1.2, 0.001));
      // Antrean pending telah bersih
      expect(sim.pendingDays.isEmpty, isTrue);
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
    });

    test('8. Offline selama 3 hari berturut-turut dengan restart di setiap hari (antrean multi-day NVS tidak tertimpa)', () {
      final sharedNvs = <String, dynamic>{};

      // --- HARI 1: 2026-10-20 ---
      final day1 = Esp32FirmwareHistorySimulator();
      day1.nvsStorage.addAll(sharedNvs);
      day1.boot(100.0);
      day1.updateCalendarAndCalculate(DateTime(2026, 10, 20, 10, 0), 100.0);
      day1.updateCalendarAndCalculate(DateTime(2026, 10, 20, 23, 50), 102.5); // 2.5 kWh dipakai
      sharedNvs.addAll(day1.nvsStorage);

      // Rollover ke HARI 2 saat OFFLINE dengan RESTART modul
      // --- HARI 2: 2026-10-21 ---
      final day2 = Esp32FirmwareHistorySimulator();
      day2.nvsStorage.addAll(sharedNvs);
      day2.boot(102.5);
      day2.updateCalendarAndCalculate(DateTime(2026, 10, 21, 8, 0), 102.5); // Mendeteksi kemarin selesai
      expect(day2.pendingDays.length, equals(1));
      expect(day2.pendingDays[0].date, equals('2026-10-20'));
      expect(day2.pendingDays[0].kwh, closeTo(2.5, 0.001));

      day2.updateCalendarAndCalculate(DateTime(2026, 10, 21, 23, 55), 105.8); // 3.3 kWh dipakai di hari 2
      sharedNvs.addAll(day2.nvsStorage);

      // Rollover ke HARI 3 saat OFFLINE dengan RESTART modul
      // --- HARI 3: 2026-10-22 ---
      final day3 = Esp32FirmwareHistorySimulator();
      day3.nvsStorage.addAll(sharedNvs);
      day3.boot(105.8);
      day3.updateCalendarAndCalculate(DateTime(2026, 10, 22, 9, 0), 105.8);
      expect(day3.pendingDays.length, equals(2));
      expect(day3.pendingDays[0].date, equals('2026-10-20'));
      expect(day3.pendingDays[1].date, equals('2026-10-21'));
      expect(day3.pendingDays[1].kwh, closeTo(3.3, 0.001));

      day3.updateCalendarAndCalculate(DateTime(2026, 10, 22, 23, 50), 107.0); // 1.2 kWh dipakai di hari 3
      sharedNvs.addAll(day3.nvsStorage);

      // Rollover ke HARI 4 saat OFFLINE dengan RESTART modul
      // --- HARI 4: 2026-10-23 ---
      final day4 = Esp32FirmwareHistorySimulator();
      day4.nvsStorage.addAll(sharedNvs);
      day4.boot(107.0);
      day4.updateCalendarAndCalculate(DateTime(2026, 10, 23, 10, 0), 107.0);
      expect(day4.pendingDays.length, equals(3), reason: 'Semua 3 hari offline harus tersimpan di antrean NVS');
      expect(day4.pendingDays[0].date, equals('2026-10-20'));
      expect(day4.pendingDays[1].date, equals('2026-10-21'));
      expect(day4.pendingDays[2].date, equals('2026-10-22'));
      expect(day4.pendingDays[2].kwh, closeTo(1.2, 0.001));

      // Pakai sedikit energi di hari 4
      day4.updateCalendarAndCalculate(DateTime(2026, 10, 23, 12, 0), 107.8); // 0.8 kWh di hari 4

      // Sekarang KONEKSI PULIH (ONLINE)
      final success = day4.syncToCloud(isOnline: true);
      expect(success, isTrue);

      // Verifikasi seluruh 3 hari pending + hari 4 masuk utuh ke Cloud RTDB!
      expect(day4.cloudRtdb['2026/daily_history/2026-10-20/energy_kwh'], closeTo(2.5, 0.001));
      expect(day4.cloudRtdb['2026/daily_history/2026-10-21/energy_kwh'], closeTo(3.3, 0.001));
      expect(day4.cloudRtdb['2026/daily_history/2026-10-22/energy_kwh'], closeTo(1.2, 0.001));
      expect(day4.cloudRtdb['2026/daily_history/2026-10-23/energy_kwh'], closeTo(0.8, 0.001));

      // Pastikan antrean di NVS sudah kosong setelah flush
      expect(day4.pendingDays.isEmpty, isTrue);
      expect(day4.nvsStorage['p_day_cnt'], equals(0));
    });

    test('9. Batas Kapasitas Antrean Offline (MAX_PENDING_DAYS=7) dan penanganan FIFO Overflow', () {
      final sim = Esp32FirmwareHistorySimulator();
      sim.boot(100.0);

      // Simulasikan 9 hari berturut-turut offline rollover
      for (int d = 1; d <= 9; d++) {
        final dateStr = '2026-10-${d.toString().padLeft(2, '0')}';
        sim.antrekanHariSelesai(dateStr, 2026, d * 1.0, d * 1500.0, d % 7);
      }

      // Kapasitas tidak boleh melebihi 7 hari
      expect(sim.pendingDays.length, equals(7));

      // Record tertua (hari ke-1 dan ke-2) tergeser oleh buffer FIFO, tersisa hari 3..9
      expect(sim.pendingDays.first.date, equals('2026-10-03'));
      expect(sim.pendingDays.last.date, equals('2026-10-09'));
      expect(sim.pendingDays.last.kwh, closeTo(9.0, 0.001));
    });

    test('10. Gagal membaca histori bulanan cloud tidak menimpa ringkasan tahunan lama dengan parsial/nol', () {
      final sim = Esp32FirmwareHistorySimulator();
      // Misalkan di cloud sudah ada total energi tahunan 500 kWh dari bulan-bulan sebelumnya
      sim.cloudRtdb['2026/summary/total_energy'] = 500.0;
      sim.cloudRtdb['2026/summary/total_cost'] = 750000.0;

      sim.boot(200.0);
      // Simulasikan berada di bulan Maret (bulan ke-2, index 2) dan membaca cloud gagal (monthlyCacheLoaded = false)
      sim.monthlyCacheLoaded = false;
      sim.updateCalendarAndCalculate(DateTime(2026, 3, 15, 12, 0), 205.0); // 5 kWh di bulan Maret

      sim.syncToCloud(isOnline: true);

      // Ringkasan tahunan di RTDB TIDAK ditimpa dengan nilai parsial 5.0 kWh! Nilai 500.0 kWh tetap terlindungi!
      expect(sim.cloudRtdb['2026/summary/total_energy'], closeTo(500.0, 0.001));
      expect(sim.cloudRtdb['2026/summary/total_cost'], closeTo(750000.0, 0.001));

      // Namun data harian dan bulanan bulan Maret tetap tersimpan
      expect(sim.cloudRtdb['2026/daily_history/2026-03-15/energy_kwh'], closeTo(5.0, 0.001));
      expect(sim.cloudRtdb['2026/monthly_energy/2'], closeTo(5.0, 0.001));
    });
  });
}
