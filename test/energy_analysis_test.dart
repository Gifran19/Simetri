import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/models/yearly_energy_data.dart';
import 'package:my_test_app/services/device_service.dart';
import 'package:my_test_app/services/sensor_stream_service.dart';
import 'package:my_test_app/widgets/daily_energy_chart.dart';
import 'package:my_test_app/widgets/energy_analysis_summary.dart';
import 'package:my_test_app/widgets/monthly_cost_chart.dart';
import 'package:my_test_app/widgets/monthly_energy_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Energy Analysis Snapshot Parsing & Fixture Tests', () {
    // Fixture data aktual Firebase: energy_data/SIMETRI_ESP32_001/2026
    final actualFirebaseMapData = {
      'monthly_energy': {
        '9': 0.002, // Oktober
      },
      'monthly_cost': {
        '9': 3, // Rp 3
      },
      'summary': {
        'total_energy': 0.002,
        'total_cost': 3,
      },
      'daily_history': {
        '2026-10-30': {
          'energy_kwh': 0.002,
          'cost_rp': 3,
          'day_of_week': 4,
        },
      },
    };

    final actualFirebaseListData = {
      'monthly_energy': [
        null, null, null, null, null, null, null, null, null, 0.002,
      ],
      'monthly_cost': [
        null, null, null, null, null, null, null, null, null, 3,
      ],
      'summary': {
        'total_energy': 0.002,
        'total_cost': 3,
      },
    };

    test('1. Parsing snapshot berbentuk Map membaca data bulan ke-9 (Oktober) dan summary', () {
      final parsed = YearlyEnergyData.fromFirebase(
        year: 2026,
        data: actualFirebaseMapData,
      );

      expect(parsed.year, equals(2026));
      expect(parsed.totalEnergy, closeTo(0.002, 0.0001));
      expect(parsed.totalCost, equals(3.0));
      expect(parsed.monthlyEnergy[9], closeTo(0.002, 0.0001));
      expect(parsed.monthlyCost[9], equals(3.0));
      expect(parsed.monthlyEnergy[0], equals(0.0));
      expect(parsed.hasValidData, isTrue);
    });

    test('2. Parsing snapshot berbentuk List (key numerik sparse Firebase RTDB) tidak melempar TypeError', () {
      final parsed = YearlyEnergyData.fromFirebase(
        year: 2026,
        data: actualFirebaseListData,
      );

      expect(parsed.year, equals(2026));
      expect(parsed.totalEnergy, closeTo(0.002, 0.0001));
      expect(parsed.totalCost, equals(3.0));
      expect(parsed.monthlyEnergy[9], closeTo(0.002, 0.0001));
      expect(parsed.monthlyCost[9], equals(3.0));
      expect(parsed.hasValidData, isTrue);
    });

    test('3. Data kecil (0.002 kWh) tidak dianggap kosong (hasValidData == true)', () {
      final emptyData = YearlyEnergyData.empty(2026);
      expect(emptyData.hasValidData, isFalse);

      final validData = YearlyEnergyData.fromFirebase(
        year: 2026,
        data: actualFirebaseMapData,
      );
      expect(validData.hasValidData, isTrue);
    });

    test('4. Resolusi deviceId aktif mendeteksi SIMETRI_ESP32_001 dari SensorStreamService / notifier', () async {
      SensorStreamService.instance.setActiveDeviceId('SIMETRI_ESP32_001');
      expect(SensorStreamService.instance.activeDeviceId, equals('SIMETRI_ESP32_001'));

      DeviceService.deviceIdNotifier.value = 'SIMETRI_ESP32_001';
      expect(DeviceService.deviceIdNotifier.value, equals('SIMETRI_ESP32_001'));
    });
  });

  group('UI Rendering & Precision Verification with Fixture', () {
    final parsedData = YearlyEnergyData.fromFirebase(
      year: 2026,
      data: {
        'monthly_energy': {'9': 0.002},
        'monthly_cost': {'9': 3},
        'summary': {'total_energy': 0.002, 'total_cost': 3},
      },
    );

    testWidgets('5. EnergyAnalysisSummary menampilkan 3 desimal (0.002 kWh) dan biaya Rp 3', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnergyAnalysisSummary(
              year: parsedData.year,
              yearlyEnergy: parsedData.totalEnergy,
              averageEnergy: parsedData.averageMonthlyEnergy,
              yearlyCost: parsedData.totalCost,
            ),
          ),
        ),
      );

      // Total Pemakaian harus menampilkan 0.002 kWh, BUKAN 0.0 kWh!
      expect(find.text('0.002 kWh'), findsOneWidget);
      // Rata-rata per bulan
      expect(find.text('${(0.002 / 12).toStringAsFixed(3)} kWh'), findsOneWidget);
      // Total Biaya Listrik: Rp 3
      expect(find.text('Rp 3'), findsOneWidget);
    });

    testWidgets('6. MonthlyEnergyChart TIDAK menampilkan "Belum ada data" saat ada data 0.002 kWh', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlyEnergyChart(
              data: parsedData.monthlyEnergy,
              isConnected: true,
            ),
          ),
        ),
      );

      // Badge 'Belum ada data' TIDAK boleh muncul
      expect(find.text('Belum ada data'), findsNothing);
      expect(find.text('Belum ada rekaman histori'), findsNothing);
      expect(find.text('Pemakaian Energi Bulanan'), findsOneWidget);
    });

    testWidgets('7. MonthlyCostChart menampilkan satuan standar ribuan dan TIDAK menampilkan "Belum ada data"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlyCostChart(
              data: parsedData.monthlyCost,
            ),
          ),
        ),
      );

      // Badge 'Belum ada data' TIDAK boleh muncul
      expect(find.text('Belum ada data'), findsNothing);
      // Subtitle satuan standar rumah tangga 'Rp (dalam ribuan)'
      expect(find.text('Rp (dalam ribuan)'), findsOneWidget);
      expect(find.text('Perbandingan Biaya Bulanan'), findsOneWidget);
    });

    testWidgets('8. DailyEnergyChart TIDAK menampilkan "Belum ada rekaman histori" saat ada data 0.010 kWh di hari Jumat', (tester) async {
      // 7 hari: Sen, Sel, Rab, Kam, Jum (0.010), Sab, Min
      final weeklyData = [0.0, 0.0, 0.0, 0.0, 0.010, 0.0, 0.0];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyEnergyChart(
              data: weeklyData,
              isConnected: true,
            ),
          ),
        ),
      );

      // Badge dan overlay 'Belum ada rekaman histori' TIDAK boleh muncul
      expect(find.text('Belum ada rekaman histori'), findsNothing);
      expect(find.text('Pemakaian Energi Harian'), findsOneWidget);
      expect(find.text('Jum'), findsOneWidget);
    });

    testWidgets('9. DailyEnergyChart menampilkan tombol kalender, tombol navigasi minggu, dan label tanggal', (tester) async {
      final weeklyData = [0.0, 0.0, 0.0, 0.0, 0.010, 0.0, 0.0];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyEnergyChart(
              data: weeklyData,
              isConnected: true,
            ),
          ),
        ),
      );

      // Icon kalender untuk memilih tanggal harus ada
      expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
      // Tombol navigasi minggu lalu harus ada
      expect(find.text('Minggu Lalu'), findsOneWidget);
      // Status 'Minggu Ini' harus ada
      expect(find.text('Minggu Ini'), findsOneWidget);
    });

    testWidgets('10. DailyEnergyChart tidak overflow pada layar sempit (320px) saat berada di minggu lalu', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Past date (bukan minggu ini) agar tombol 'Minggu Ini' aktif
      final pastDate = DateTime.now().subtract(const Duration(days: 14));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyEnergyChart(
              initialDate: pastDate,
              data: const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
              isConnected: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Memastikan kedua tombol navigasi dan reset minggu ini ter-render tanpa RenderFlex overflow
      expect(find.text('Minggu Lalu'), findsOneWidget);
      expect(find.text('Minggu Depan'), findsOneWidget);
      expect(find.text('Minggu Ini'), findsOneWidget);
      expect(find.text('7 Hari'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11. Membuka dialog kalender menampilkan WeekRangePickerDialog dengan keterangan 7 hari', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final weeklyData = [0.0, 0.0, 0.0, 0.0, 0.010, 0.0, 0.0];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyEnergyChart(
              data: weeklyData,
              isConnected: true,
            ),
          ),
        ),
      );

      // Tap icon kalender
      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();

      // Dialog harus muncul dengan judul "Pilih Rentang 7 Hari"
      expect(find.text('Pilih Rentang 7 Hari'), findsOneWidget);
      expect(find.text('Senin sampai Minggu (1 Minggu Penuh)'), findsOneWidget);
      expect(find.text('RENTANG 7 HARI TERPILIH'), findsOneWidget);
      expect(find.text('Terapkan (7 Hari)'), findsOneWidget);

      // Tap tombol Close
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Dialog harus tertutup
      expect(find.text('Pilih Rentang 7 Hari'), findsNothing);
    });
  });
}

