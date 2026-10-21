import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_data.dart';
import '../models/tariff_history.dart';

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
  static const String _keyPower = 'simetri_device_power';
  static const String _keyPowerLimit = 'simetri_power_limit_va';
  static const String _keyMonthlyBudget = 'simetri_monthly_budget_rp';
  static const String _keyBiometricEnabled = 'simetri_biometric_enabled';
  static const String _keyHasOnboarded = 'simetri_has_onboarded';

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

  // =========================
  // PERSISTENSI KONEKSI & POWER (REAKTIF GLOBAL)
  // =========================

  /// Notifier status koneksi reaktif agar seluruh layar (Home, Analisis Energi, dsb.)
  /// selalu 100% sinkron secara instan (0 ms).
  static final ValueNotifier<bool> connectionNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> powerNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<double> budgetNotifier = ValueNotifier<double>(300000.0);

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

  /// Cek status saklar daya terakhir kali
  static Future<bool> getDevicePower() async {
    final prefs = await SharedPreferences.getInstance();
    final power = prefs.getBool(_keyPower) ?? true;
    if (powerNotifier.value != power) {
      powerNotifier.value = power;
    }
    return power;
  }

  /// Simpan status saklar daya & picu notifier reaktif
  static Future<void> saveDevicePower(bool power) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPower, power);
    powerNotifier.value = power;
  }

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
    await Future.delayed(const Duration(milliseconds: 500));
    await saveConnectionState(true);
    await saveDevicePower(true);

    return getDeviceData(
      isConnected: true,
      isPowerOn: true,
      powerLimitVa: powerLimitVa,
      monthlyBudgetRp: monthlyBudgetRp,
    );
  }

  /// Menghasilkan data device sesuai kondisi koneksi dan status saklar daya.
  /// Jika perangkat OFF, data pembacaan real-time (tegangan, arus, daya, frekuensi, PF) menjadi 0,
  /// sedangkan data akumulasi pemakaian energi tetap tersimpan.
  static DeviceData getDeviceData({
    required bool isConnected,
    required bool isPowerOn,
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
      connectionType: "WiFi",
      // Saat perangkat OFF, pembacaan sensor real-time berhenti (0)
      voltage: isPowerOn ? 221.0 : 0.0,
      current: isPowerOn ? 0.1 : 0.0,
      power: isPowerOn ? 14.2 : 0.0,
      frequency: isPowerOn ? 50.0 : 0.0,
      powerFactor: isPowerOn ? 0.98 : 0.0,
      powerLimitVa: powerLimitVa,
      monthlyBudgetRp: monthlyBudgetRp,
      // Data akumulasi tetap tersimpan sampai titik dimatikan
      dailyEnergy: 42.5,
      dailyCost: 64000,
      monthlyEnergy: 125,
      monthlyCost: 54500,
      yearlyEnergy: 825,
      monthlyEnergyHistory: const [62, 67, 70, 65, 62, 67, 63, 67, 68, 70, 66, 75],
      monthlyCostHistory: const [
        54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5
      ],
    );
  }
}
