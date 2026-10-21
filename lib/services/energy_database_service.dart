import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../models/yearly_energy_data.dart';

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

  // -------------------------------------------------------
  // Ambil daftar tahun yang tersedia di database
  // -------------------------------------------------------
  Future<List<int>> fetchAvailableYears() async {
    final db = _db;
    if (db == null) {
      // Firebase belum dikonfigurasi → langsung return data dummy dalam 0 ms
      return [2026, 2025, 2024];
    }

    try {
      final snapshot = await db.ref('available_years').get().timeout(const Duration(seconds: 2));

      if (!snapshot.exists || snapshot.value == null) {
        return [2026, 2025, 2024];
      }

      final raw = snapshot.value;
      if (raw is List) {
        final list = raw.whereType<num>().map((e) => e.toInt()).toList()
          ..sort((a, b) => b.compareTo(a)); // descending
        return list.isNotEmpty ? list : [2026, 2025, 2024];
      } else if (raw is Map) {
        final list = raw.values.whereType<num>().map((e) => e.toInt()).toList()
          ..sort((a, b) => b.compareTo(a));
        return list.isNotEmpty ? list : [2026, 2025, 2024];
      }
      return [2026, 2025, 2024];
    } catch (e) {
      // Fallback ke dummy jika Firebase offline/timeout
      return [2026, 2025, 2024];
    }
  }

  // -------------------------------------------------------
  // Ambil data energi untuk tahun tertentu
  // -------------------------------------------------------
  Future<YearlyEnergyData> fetchYearlyData(int year) async {
    final db = _db;
    if (db == null) {
      // Firebase belum dikonfigurasi → langsung return data dummy dalam 0 ms
      return YearlyEnergyData.dummy(year);
    }

    try {
      // Ambil data tahun ini dengan timeout 2 detik
      final snapshot = await db.ref('energy_data/$year').get().timeout(const Duration(seconds: 2));

      if (!snapshot.exists || snapshot.value == null) {
        return YearlyEnergyData.dummy(year);
      }

      final data = snapshot.value as Map<dynamic, dynamic>;

      // Ambil data tahun sebelumnya untuk perbandingan
      YearlyEnergyData? prevData;
      try {
        final prevSnapshot = await db
            .ref('energy_data/${year - 1}')
            .get()
            .timeout(const Duration(seconds: 1));
        if (prevSnapshot.exists && prevSnapshot.value != null) {
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
      return YearlyEnergyData.dummy(year);
    }
  }

  // -------------------------------------------------------
  // Stream real-time data energi (untuk live monitoring)
  // -------------------------------------------------------
  Stream<YearlyEnergyData> streamYearlyData(int year) {
    final db = _db;
    if (db == null) {
      return Stream.value(YearlyEnergyData.dummy(year));
    }

    return db.ref('energy_data/$year').onValue.asyncMap((event) async {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return YearlyEnergyData.dummy(year);
      }
      final data = event.snapshot.value as Map<dynamic, dynamic>;

      YearlyEnergyData? prevData;
      try {
        final prevSnapshot = await db
            .ref('energy_data/${year - 1}')
            .get()
            .timeout(const Duration(seconds: 1));
        if (prevSnapshot.exists && prevSnapshot.value != null) {
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
  // Tulis data energi dari ESP32 (dipanggil saat IoT kirim data)
  // -------------------------------------------------------
  /// Simpan pembacaan energi bulanan dari ESP32.
  /// [year]        → tahun (misal 2026)
  /// [month]       → bulan 0-11 (0 = Jan)
  /// [energyKwh]   → total pemakaian kWh bulan itu
  /// [costRp]      → total biaya bulan itu dalam Rupiah
  Future<void> writeMonthlyReading({
    required int year,
    required int month,
    required double energyKwh,
    required double costRp,
  }) async {
    final db = _db;
    if (db == null) return;

    final ref = db.ref('energy_data/$year');

    await ref.update({'monthly_energy/$month': energyKwh, 'monthly_cost/$month': costRp});

    // Update summary
    await _updateYearlySummary(year);

    // Pastikan tahun ini ada di daftar available_years
    await _ensureYearRegistered(year);
  }

  // -------------------------------------------------------
  // Helper: hitung ulang summary tahunan
  // -------------------------------------------------------
  Future<void> _updateYearlySummary(int year) async {
    final db = _db;
    if (db == null) return;

    final energySnap = await db.ref('energy_data/$year/monthly_energy').get();
    final costSnap = await db.ref('energy_data/$year/monthly_cost').get();

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

    await db.ref('energy_data/$year/summary').update({
      'total_energy': totalEnergy,
      'total_cost': totalCost,
      'last_updated': ServerValue.timestamp,
    });
  }

  // -------------------------------------------------------
  // Helper: daftarkan tahun ke node available_years
  // -------------------------------------------------------
  Future<void> _ensureYearRegistered(int year) async {
    final db = _db;
    if (db == null) return;

    final snapshot = await db.ref('available_years').get();
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
      await db.ref('available_years').set(years);
    }
  }
}
