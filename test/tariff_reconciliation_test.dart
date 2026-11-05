import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/models/yearly_energy_data.dart';
import 'package:my_test_app/widgets/tariff_card.dart';

void main() {
  group('Rekonsiliasi Biaya Bulanan saat Tarif Berubah di Tengah Bulan', () {
    test('Total biaya bulan berjalan menjumlahkan biaya harian riil, bukan perkalian flat tarif baru', () {
      final now = DateTime.now();
      final year = now.year;
      final month = now.month;
      final monthIdx = month - 1;

      // Fixture: Kemarin 0.464 kWh (Rp 627), Hari ini 0.052 kWh (Rp 104).
      // Total energi: 0.516 kWh.
      // Jika rumus lama flat ESP32: 0.516 * 2000 = 1032.
      // Hasil agregasi riil yang benar: 627 + 104 = 731.
      final mockData = {
        'daily_history': {
          '$year-${month.toString().padLeft(2, '0')}-04': {
            'energy_kwh': 0.464,
            'cost_rp': 627.0,
            'day_of_week': 2,
          },
          '$year-${month.toString().padLeft(2, '0')}-05': {
            'energy_kwh': 0.052,
            'cost_rp': 104.0,
            'day_of_week': 3,
          },
        },
        'monthly_energy': List.generate(12, (i) => i == monthIdx ? 0.516 : 0.0),
        'monthly_cost': List.generate(12, (i) => i == monthIdx ? 1032.0 : 0.0), // Nilai flat lama dari ESP32
        'summary': {
          'total_energy': 0.516,
          'total_cost': 1032.0,
        },
      };

      final parsed = YearlyEnergyData.fromFirebase(year: year, data: mockData);

      // Total energi bulanan tetap 0.516 kWh
      expect(parsed.monthlyEnergy[monthIdx], closeTo(0.516, 0.001));

      // Biaya bulanan HARUS 731.0 (akumulasi riil), BUKAN 1032.0
      expect(parsed.monthlyCost[monthIdx], equals(731.0));

      // Total biaya tahunan juga mencerminkan akumulasi riil
      expect(parsed.totalCost, equals(731.0));
    });
  });

  group('Kalkulasi Dinamis Label Tanggal Aktif Tarif', () {
    test('Label "Besok (tanggal hari ini)" otomatis berubah menjadi "Hari ini (tanggal)"', () {
      final now = DateTime.now();
      final dayStr = now.day.toString().padLeft(2, '0');
      final monthNames = [
        '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
      ];
      final monthName = monthNames[now.month];
      final rawStaleDate = 'Besok ($dayStr $monthName ${now.year})';

      final formatted = TariffCard.formatTariffActiveDate(rawStaleDate);
      expect(formatted, contains('Hari ini'));
      expect(formatted, contains('$dayStr $monthName ${now.year}'));
    });
  });
}
