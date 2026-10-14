import '../models/device_data.dart';
import '../models/payment_models.dart';

class DeviceService {
  // =========================
  // DATA TARIF GLOBAL
  // =========================

  static double currentTariff = 1352;
  static String tariffActiveDate = '08 Oktober 2026';
  static String tariffNote = 'Penyesuaian tarif listrik PLN';

  // Riwayat Perubahan Tarif
  static List<TariffHistoryItem> tariffHistory = [
    TariffHistoryItem(
      date: 'Mulai 08 Oktober 2026',
      tariff: 1352,
      note: 'Penyesuaian tarif resmi aktif',
      isActive: true,
    ),
    const TariffHistoryItem(
      date: '1 - 7 Oktober 2026',
      tariff: 1200,
      note: 'Tarif periode awal bulan',
      isActive: false,
    ),
    const TariffHistoryItem(
      date: '01 Januari - 30 September 2026',
      tariff: 1150,
      note: 'Tarif dasar 2026',
      isActive: false,
    ),
  ];

  // =========================
  // UPDATE TARIF
  // =========================

  static void updateTariff(double newTariff, String date, String note) {
    currentTariff = newTariff;
    tariffActiveDate = date;
    tariffNote = note;

    // Masukkan ke riwayat paling atas
    tariffHistory.insert(
      0,
      TariffHistoryItem(
        date: 'Mulai $date',
        tariff: newTariff,
        note: note.isEmpty ? 'Pembaruan tarif manual' : note,
        isActive: true,
      ),
    );

    // Tandai yang lama tidak aktif
    for (int i = 1; i < tariffHistory.length; i++) {
      final old = tariffHistory[i];
      tariffHistory[i] = TariffHistoryItem(
        date: old.date,
        tariff: old.tariff,
        note: old.note,
        isActive: false,
      );
    }
  }

  // =========================
  // CONNECT DEVICE
  // =========================

  Future<DeviceData> connectDevice() async {
    await Future.delayed(const Duration(milliseconds: 500));

    return DeviceData(
      isConnected: true,
      connectionType: 'WiFi',
      voltage: 221,
      current: 0.1,
      power: 14.2,
      dailyEnergy: 42.5,
      dailyCost: 64000,
      monthlyEnergy: 125,
      monthlyCost: 54500,
      yearlyEnergy: 825,
      monthlyEnergyHistory: [62, 67, 70, 65, 62, 67, 63, 67, 68, 70, 66, 75],
      monthlyCostHistory: [54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5, 54.5],
    );
  }
}