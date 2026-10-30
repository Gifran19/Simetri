import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../models/yearly_energy_data.dart';
import 'device_service.dart';
import 'live_status.dart';
import 'sensor_stream_service.dart';

/// Service untuk mengambil dan menyimpan data energi ke Firebase Realtime Database.
///
/// Struktur data di Firebase:
/// ```
/// energy_data/
///   2024/
///     monthly_energy/
///       0: 58.0    ← Jan
///       1: 62.0    ← Feb
///       ...
///       11: 70.0   ← Des
///     monthly_cost/
///       0: 78480.0
///       ...
///     summary/
///       total_energy: 754.0
///       total_cost: 1020536.0
///   2025/
///     ...
///   2026/
///     ...
/// available_years/
///   0: 2024
///   1: 2025
///   2: 2026
/// ```
class EnergyDatabaseService {
  static final EnergyDatabaseService _instance = EnergyDatabaseService._internal();
  factory EnergyDatabaseService() => _instance;
  EnergyDatabaseService._internal();

  /// Cek apakah Firebase sudah dikonfigurasi dan diinisialisasi
  bool get _isFirebaseReady {
    try {
      return DefaultFirebaseOptions.isConfigured && Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseDatabase? get _db {
    if (!_isFirebaseReady) return null;
    try {
      return FirebaseDatabase.instance;
    } catch (_) {
      return null;
    }
  }

  /// Galat terakhir saat membaca histori energi (mis. izin ditolak / timeout),
  /// atau null jika pembacaan terakhir tidak menimbulkan galat.
  String? lastFetchError;

  /// Hasil kosong untuk mode nyata. Data contoh HANYA dikembalikan bila mode DEMO
  /// dipilih eksplisit (SIMETRI_DEMO_MODE=true) dan UI wajib melabelinya DEMO.
  YearlyEnergyData _emptyOrDemo(int year) {
    return kDemoMode ? YearlyEnergyData.dummy(year) : YearlyEnergyData.empty(year);
  }

  /// Daftar tahun bawaan bila database belum memiliki histori: hanya tahun berjalan
  /// (bukan daftar tahun contoh), kecuali mode DEMO.
  List<int> _defaultYears() {
    return kDemoMode ? [2026, 2025, 2024] : [DateTime.now().year];
  }

  // Helper internal untuk mendapatkan deviceId aktif
  Future<String> _resolveDeviceId([String? deviceId]) async {
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      return deviceId.trim();
    }
    // Prioritaskan ID aktif dari SensorStreamService bila sudah diatur ke ID nyata
    final streamId = SensorStreamService.instance.activeDeviceId;
    if (streamId.isNotEmpty && streamId != DeviceService.defaultDeviceId) {
      return streamId;
    }
    // Cek reactive notifier DeviceService
    final notifierId = DeviceService.deviceIdNotifier.value;
    if (notifierId.isNotEmpty && notifierId != DeviceService.defaultDeviceId) {
      return notifierId;
    }
    return await DeviceService.getPairedDeviceId();
  }

  // -------------------------------------------------------
  // Ambil daftar tahun yang tersedia di database per perangkat
  // -------------------------------------------------------
  Future<List<int>> fetchAvailableYears([String? deviceId]) async {
    final db = _db;
    if (db == null) {
      return _defaultYears();
    }

    try {
      final devId = await _resolveDeviceId(deviceId);
      final snapshot = await db
          .ref('energy_data/$devId/available_years')
          .get()
          .timeout(const Duration(seconds: 2));

      if (snapshot.exists && snapshot.value != null) {
        final raw = snapshot.value;
        if (raw is List) {
          final list = raw.whereType<num>().map((e) => e.toInt()).toList()
            ..sort((a, b) => b.compareTo(a)); // descending
          if (list.isNotEmpty) return list;
        } else if (raw is Map) {
          final list = raw.values.whereType<num>().map((e) => e.toInt()).toList()
            ..sort((a, b) => b.compareTo(a));
          if (list.isNotEmpty) return list;
        }
      }

      // Fallback: Jika node available_years belum ada, cek child keys di energy_data/$devId
      final rootSnap = await db
          .ref('energy_data/$devId')
          .get()
          .timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value is Map) {
        final rootMap = rootSnap.value as Map;
        final detectedYears = <int>[];
        for (final k in rootMap.keys) {
          final y = int.tryParse(k.toString());
          if (y != null && y >= 2020 && y <= 2100) {
            detectedYears.add(y);
          }
        }
        if (detectedYears.isNotEmpty) {
          detectedYears.sort((a, b) => b.compareTo(a));
          return detectedYears;
        }
      }

      return _defaultYears();
    } catch (e) {
      return _defaultYears();
    }
  }

  // -------------------------------------------------------
  // Ambil data energi untuk tahun tertentu per perangkat
  // -------------------------------------------------------
  Future<YearlyEnergyData> fetchYearlyData(int year, [String? deviceId]) async {
    final db = _db;
    if (db == null) {
      return _emptyOrDemo(year);
    }

    try {
      final devId = await _resolveDeviceId(deviceId);
      final snapshot = await db
          .ref('energy_data/$devId/$year')
          .get()
          .timeout(const Duration(seconds: 2));
      lastFetchError = null;

      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return _emptyOrDemo(year);
      }

      final data = snapshot.value as Map<dynamic, dynamic>;

      // Ambil data tahun sebelumnya untuk perbandingan
      YearlyEnergyData? prevData;
      try {
        final prevSnapshot = await db
            .ref('energy_data/$devId/${year - 1}')
            .get()
            .timeout(const Duration(seconds: 1));
        if (prevSnapshot.exists && prevSnapshot.value != null && prevSnapshot.value is Map) {
          prevData = YearlyEnergyData.fromFirebase(
            year: year - 1,
            data: prevSnapshot.value as Map<dynamic, dynamic>,
          );
        }
      } catch (_) {
        // Abaikan jika tidak ada data tahun lalu
      }

      return YearlyEnergyData.fromFirebase(year: year, data: data, prevData: prevData);
    } catch (e) {
      lastFetchError = 'Gagal membaca histori energi: $e';
      return _emptyOrDemo(year);
    }
  }

  // -------------------------------------------------------
  // Stream real-time data energi (untuk live monitoring)
  // -------------------------------------------------------
  Stream<YearlyEnergyData> streamYearlyData(int year, [String? deviceId]) async* {
    final db = _db;
    if (db == null) {
      yield _emptyOrDemo(year);
      return;
    }

    final devId = await _resolveDeviceId(deviceId);

    yield* db.ref('energy_data/$devId/$year').onValue.asyncMap((event) async {
      lastFetchError = null;
      if (!event.snapshot.exists || event.snapshot.value == null || event.snapshot.value is! Map) {
        return _emptyOrDemo(year);
      }
      final data = event.snapshot.value as Map<dynamic, dynamic>;

      YearlyEnergyData? prevData;
      try {
        final prevSnapshot = await db
            .ref('energy_data/$devId/${year - 1}')
            .get()
            .timeout(const Duration(seconds: 1));
        if (prevSnapshot.exists && prevSnapshot.value != null && prevSnapshot.value is Map) {
          prevData = YearlyEnergyData.fromFirebase(
            year: year - 1,
            data: prevSnapshot.value as Map<dynamic, dynamic>,
          );
        }
      } catch (_) {}

      return YearlyEnergyData.fromFirebase(year: year, data: data, prevData: prevData);
    });
  }

  // -------------------------------------------------------
  // Ambil data energi mingguan (Sen - Min: index 0..6)
  // Menjamin HANYA tanggal pada minggu berjalan yang ditampilkan
  // -------------------------------------------------------
  Future<List<double>> fetchWeeklyEnergy([String? deviceId]) async {
    final db = _db;
    if (db == null) return List.filled(7, 0.0);

    try {
      final devId = await _resolveDeviceId(deviceId);
      final now = DateTime.now();
      final year = now.year;

      // Hitung 7 tanggal kalender untuk minggu berjalan (Senin s.d. Minggu)
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final currentWeekDates = List.generate(7, (i) {
        final d = monday.add(Duration(days: i));
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      // 1. Prioritaskan pembacaan dari daily_history (arsip tanggal kalender riil)
      final historySnap = await db
          .ref('energy_data/$devId/$year/daily_history')
          .get()
          .timeout(const Duration(seconds: 2));

      if (historySnap.exists && historySnap.value != null && historySnap.value is Map) {
        final historyMap = historySnap.value as Map;
        final result = List<double>.filled(7, 0.0);
        for (int i = 0; i < 7; i++) {
          final dateKey = currentWeekDates[i];
          final entry = historyMap[dateKey];
          if (entry is Map && entry['energy_kwh'] is num) {
            result[i] = (entry['energy_kwh'] as num).toDouble();
          }
        }
        return result;
      }

      // 2. Fallback pembacaan ke weekly_energy dibatasi hanya hari <= hari ini
      final snapshot = await db
          .ref('energy_data/$devId/$year/weekly_energy')
          .get()
          .timeout(const Duration(seconds: 2));

      if (!snapshot.exists || snapshot.value == null) {
        return List.filled(7, 0.0);
      }

      final raw = snapshot.value;
      final result = List<double>.filled(7, 0.0);
      final activeDayIndex = now.weekday - 1; // 0=Sen .. 6=Min

      if (raw is Map) {
        raw.forEach((key, val) {
          final idx = int.tryParse(key.toString());
          if (idx != null && idx >= 0 && idx <= activeDayIndex && idx < 7 && val is num) {
            result[idx] = val.toDouble();
          }
        });
      } else if (raw is List) {
        for (int i = 0; i <= activeDayIndex && i < raw.length && i < 7; i++) {
          final val = raw[i];
          if (val is num) result[i] = val.toDouble();
        }
      }
      return result;
    } catch (_) {
      return List.filled(7, 0.0);
    }
  }

  // -------------------------------------------------------
  // Stream data energi mingguan (Sen - Min: index 0..6)
  // Menjamin HANYA tanggal pada minggu berjalan yang ditampilkan
  // -------------------------------------------------------
  Stream<List<double>> streamWeeklyEnergy([String? deviceId]) async* {
    final db = _db;
    if (db == null) {
      yield List.filled(7, 0.0);
      return;
    }

    final devId = await _resolveDeviceId(deviceId);
    final now = DateTime.now();
    final year = now.year;

    // Dengarkan aliran daily_history untuk memetakan tanggal minggu berjalan secara presisi
    yield* db.ref('energy_data/$devId/$year/daily_history').onValue.map((event) {
      final nowCurrent = DateTime.now();
      final monday = DateTime(nowCurrent.year, nowCurrent.month, nowCurrent.day).subtract(Duration(days: nowCurrent.weekday - 1));
      final currentWeekDates = List.generate(7, (i) {
        final d = monday.add(Duration(days: i));
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      final result = List<double>.filled(7, 0.0);
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final historyMap = event.snapshot.value as Map;
        for (int i = 0; i < 7; i++) {
          final dateKey = currentWeekDates[i];
          final entry = historyMap[dateKey];
          if (entry is Map && entry['energy_kwh'] is num) {
            result[i] = (entry['energy_kwh'] as num).toDouble();
          }
        }
      }
      return result;
    });
  }

  // -------------------------------------------------------
  // Ambil rekaman arsip harian permanen (YYYY-MM-DD)
  // -------------------------------------------------------
  Future<Map<String, Map<String, dynamic>>> fetchDailyHistory({
    int? year,
    String? deviceId,
  }) async {
    final db = _db;
    if (db == null) return {};

    try {
      final devId = await _resolveDeviceId(deviceId);
      final targetYear = year ?? DateTime.now().year;
      final snapshot = await db
          .ref('energy_data/$devId/$targetYear/daily_history')
          .get()
          .timeout(const Duration(seconds: 2));

      if (!snapshot.exists || snapshot.value == null) {
        return {};
      }

      final raw = snapshot.value;
      final result = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        raw.forEach((key, val) {
          if (val is Map) {
            result[key.toString()] = Map<String, dynamic>.from(val);
          }
        });
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // -------------------------------------------------------
  // Tulis data energi dari ESP32 (dipanggil saat IoT kirim data)
  // -------------------------------------------------------
  Future<void> writeMonthlyReading({
    required int year,
    required int month,
    required double energyKwh,
    required double costRp,
    String? deviceId,
  }) async {
    final db = _db;
    if (db == null) return;

    final devId = await _resolveDeviceId(deviceId);
    final ref = db.ref('energy_data/$devId/$year');

    await ref.update({'monthly_energy/$month': energyKwh, 'monthly_cost/$month': costRp});

    // Update summary
    await _updateYearlySummary(year, devId);

    // Pastikan tahun ini ada di daftar available_years per perangkat
    await _ensureYearRegistered(year, devId);
  }

  // -------------------------------------------------------
  // Helper: hitung ulang summary tahunan
  // -------------------------------------------------------
  Future<void> _updateYearlySummary(int year, String devId) async {
    final db = _db;
    if (db == null) return;

    final energySnap = await db.ref('energy_data/$devId/$year/monthly_energy').get();
    final costSnap = await db.ref('energy_data/$devId/$year/monthly_cost').get();

    double totalEnergy = 0;
    double totalCost = 0;

    if (energySnap.exists && energySnap.value != null) {
      final energyMap = energySnap.value as Map<dynamic, dynamic>;
      totalEnergy = energyMap.values.whereType<num>().fold(0.0, (a, b) => a + b.toDouble());
    }

    if (costSnap.exists && costSnap.value != null) {
      final costMap = costSnap.value as Map<dynamic, dynamic>;
      totalCost = costMap.values.whereType<num>().fold(0.0, (a, b) => a + b.toDouble());
    }

    await db.ref('energy_data/$devId/$year/summary').update({
      'total_energy': totalEnergy,
      'total_cost': totalCost,
      'last_updated': ServerValue.timestamp,
    });
  }

  // -------------------------------------------------------
  // Helper: daftarkan tahun ke node available_years per perangkat
  // -------------------------------------------------------
  Future<void> _ensureYearRegistered(int year, String devId) async {
    final db = _db;
    if (db == null) return;

    final snapshot = await db.ref('energy_data/$devId/available_years').get();
    List<int> years = [];

    if (snapshot.exists && snapshot.value != null) {
      final raw = snapshot.value;
      if (raw is List) {
        years = raw.whereType<num>().map((e) => e.toInt()).toList();
      } else if (raw is Map) {
        years = raw.values.whereType<num>().map((e) => e.toInt()).toList();
      }
    }

    if (!years.contains(year)) {
      years.add(year);
      years.sort();
      await db.ref('energy_data/$devId/available_years').set(years);
    }
  }
}
