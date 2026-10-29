import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_data.dart';
import '../models/tariff_history.dart';
import 'live_status.dart';
import 'sensor_stream_service.dart';

/// Preset Golongan Tarif Resmi PLN
class PlnTariffPreset {
  final String label;
  final String category;
  final int powerVa;
  final double ratePerKwh;
  final String description;

  const PlnTariffPreset({
    required this.label,
    required this.category,
    required this.powerVa,
    required this.ratePerKwh,
    required this.description,
  });
}
class DeviceService {
  static const String _keyConnected = 'simetri_is_connected';
  static const String _keyPowerLimit = 'simetri_power_limit_va';
  static const String _keyMonthlyBudget = 'simetri_monthly_budget_rp';
  static const String _keyBiometricEnabled = 'simetri_biometric_enabled';
  static const String _keyHasOnboarded = 'simetri_has_onboarded';
  static const String _keyDeviceId = 'simetri_paired_device_id';
  static const String defaultDeviceId = 'simetri_01';

  // =========================
  // PRESET RESMI PLN INDONESIA
  // =========================
  static const List<PlnTariffPreset> plnPresets = [
    PlnTariffPreset(
      label: 'R-1 / 900 VA',
      category: 'R-1/TR (Rumah Tangga Mampu)',
      powerVa: 900,
      ratePerKwh: 1352.0,
      description: 'Tarif Rumah Tangga Daya 900 VA Non-Subsidi',
    ),
    PlnTariffPreset(
      label: 'R-1 / 1.300 VA',
      category: 'R-1/TR',
      powerVa: 1300,
      ratePerKwh: 1444.70,
      description: 'Tarif Rumah Tangga Menengah 1.300 VA',
    ),
    PlnTariffPreset(
      label: 'R-1 / 2.200 VA',
      category: 'R-1/TR',
      powerVa: 2200,
      ratePerKwh: 1444.70,
      description: 'Tarif Rumah Tangga 2.200 VA',
    ),
    PlnTariffPreset(
      label: 'R-2 / 3.500-5.500 VA',
      category: 'R-2/TR',
      powerVa: 3500,
      ratePerKwh: 1699.53,
      description: 'Tarif Rumah Tangga Besar 3.500 VA - 5.500 VA',
    ),
    PlnTariffPreset(
      label: 'B-1 / Bisnis Kecil',
      category: 'B-1/TR',
      powerVa: 1300,
      ratePerKwh: 1444.70,
      description: 'Tarif Bisnis / Toko / UMKM Skala Kecil',
    ),
  ];

  // =========================
  // DATA TARIF AKTIF
  // =========================

  static double currentTariff = 1352;
  static String tariffActiveDate = "08 Oktober 2026";
  static String tariffNote = "Penyesuaian tarif awal";

  // =========================
  // RIWAYAT PERUBAHAN TARIF
  // =========================

  static List<TariffHistory> tariffHistory = [
    TariffHistory(
      oldTariff: 1200,
      newTariff: 1352,
      date: "08 Oktober 2026",
      note: "Penyesuaian tarif awal",
    ),
  ];

  // =========================
  // UPDATE TARIF
  // =========================

  static void updateTariff(double newTariff, String date, String note) {
    tariffHistory.insert(
      0,
      TariffHistory(
        oldTariff: currentTariff,
        newTariff: newTariff,
        date: date,
        note: note.isEmpty ? "Pembaruan tarif manual" : note,
      ),
    );

    currentTariff = newTariff;
    tariffActiveDate = date;
    tariffNote = note;
  }

  /// Memperbarui tarif secara lokal dan mengirimkannya ke Firebase Cloud control/tariff_per_kwh
  static Future<TariffWriteResult> updateTariffAsync(
    double newTariff,
    String date,
    String note,
  ) async {
    updateTariff(newTariff, date, note);
    return await SensorStreamService.instance.writeTariffCommand(newTariff);
  }

  // =========================
  // PERSISTENSI KONEKSI & POWER (REAKTIF GLOBAL)
  // =========================

  /// Notifier status koneksi reaktif agar seluruh layar (Home, Analisis Energi, dsb.)
  /// selalu 100% sinkron secara instan (0 ms).
  static final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<double> budgetNotifier = ValueNotifier<double>(300000.0);
  static final ValueNotifier<String> deviceIdNotifier = ValueNotifier<String>(defaultDeviceId);

  /// Ambil Kode / ID Perangkat ESP32 yang terhubung
  static Future<String> getPairedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_keyDeviceId) ?? defaultDeviceId;
    if (deviceIdNotifier.value != deviceId) {
      deviceIdNotifier.value = deviceId;
    }
    return deviceId;
  }

  /// Simpan Kode / ID Perangkat ESP32 hasil pairing
  static Future<void> savePairedDeviceId(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceId, cleanId);
    deviceIdNotifier.value = cleanId;
  }

  /// Putuskan dan bersihkan data pairing perangkat
  static Future<void> clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceId);
    await saveConnectionState(false);
    deviceIdNotifier.value = defaultDeviceId;
  }

  /// Cek apakah pengguna sebelumnya sudah pernah menghubungkan perangkat
  static Future<bool> isDeviceConnected() async {
    final prefs = await SharedPreferences.getInstance();
    final connected = prefs.getBool(_keyConnected) ?? false;
    if (connectionNotifier.value != connected) {
      connectionNotifier.value = connected;
    }
    return connected;
  }

  /// Simpan status koneksi perangkat ke memori lokal & picu notifier reaktif
  static Future<void> saveConnectionState(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyConnected, connected);
    connectionNotifier.value = connected;
  }

  // CATATAN: status saklar/relay TIDAK disimpan secara lokal. Status relay hanya
  // berasal dari telemetri perangkat (`relay_output_state`), bukan dari preferensi.

  // =========================
  // PERSISTENSI DAYA KONTRAK PLN & BUDGET
  // =========================

  static Future<int> getPowerLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPowerLimit) ?? 1300;
  }

  static Future<void> savePowerLimit(int limitVa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPowerLimit, limitVa);
  }

  static Future<double> getMonthlyBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final budget = prefs.getDouble(_keyMonthlyBudget) ?? 300000.0;
    if (budgetNotifier.value != budget) {
      budgetNotifier.value = budget;
    }
    return budget;
  }

  static Future<void> saveMonthlyBudget(double budgetRp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMonthlyBudget, budgetRp);
    budgetNotifier.value = budgetRp;
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? true;
  }

  static Future<void> saveBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
  }

  static Future<bool> hasOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasOnboarded) ?? false;
  }

  static Future<void> setOnboarded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasOnboarded, value);
  }

  // =========================
  // CONNECT DEVICE
  // =========================

  Future<DeviceData> connectDevice({int powerLimitVa = 1300, double monthlyBudgetRp = 300000}) async {
    await saveConnectionState(true);

    return getDeviceData(
      isConnected: true,
      powerLimitVa: powerLimitVa,
      monthlyBudgetRp: monthlyBudgetRp,
    );
  }

  /// Menghasilkan kerangka data device. TIDAK memuat angka contoh/dummy:
  /// semua pengukuran 0 dan histori kosong sampai telemetri nyata diterima.
  /// Status (offline/stale/error/live) ditentukan terpisah oleh `LiveStatus`.
  static DeviceData getDeviceData({
    required bool isConnected,
    int powerLimitVa = 1300,
    double monthlyBudgetRp = 300000,
  }) {
    if (!isConnected) {
      return DeviceData.disconnected().copyWith(
        powerLimitVa: powerLimitVa,
        monthlyBudgetRp: monthlyBudgetRp,
      );
    }

    return DeviceData(
      isConnected: true,
      connectionType: 'WiFi',
      voltage: 0.0,
      current: 0.0,
      power: 0.0,
      frequency: 0.0,
      powerFactor: 0.0,
      powerLimitVa: powerLimitVa,
      monthlyBudgetRp: monthlyBudgetRp,
      dailyEnergy: 0.0,
      dailyCost: null,
      monthlyEnergy: 0.0,
      monthlyCost: null,
      yearlyEnergy: 0.0,
      isLiveStream: false,
      streamSource: 'Menunggu data perangkat',
      isSensorValid: false,
      isSensorStale: true,
      sensorStatusMessage: 'Belum ada data dari perangkat',
      dailyHistory: const [],
      monthlyEnergyHistory: const [],
      monthlyCostHistory: const [],
    );
  }
}
