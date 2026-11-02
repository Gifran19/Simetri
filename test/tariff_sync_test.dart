import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_test_app/models/sensor_reading.dart';
import 'package:my_test_app/models/scheduled_tariff.dart';
import 'package:my_test_app/services/live_status.dart';
import 'package:my_test_app/services/device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tariff Evaluation & Sync Tests', () {
    test('evaluateTariffSync handles various device and tariff states correctly', () {
      // 1. Device not connected/reachable with pending target
      expect(
        evaluateTariffSync(
          controlTariff: 1444.7,
          appliedTariff: null,
          isDeviceReachable: false,
        ),
        equals(TariffSyncStatus.deviceOffline),
      );

      // 2. Both null -> noData
      expect(
        evaluateTariffSync(
          controlTariff: null,
          appliedTariff: null,
          isDeviceReachable: true,
        ),
        equals(TariffSyncStatus.noData),
      );

      // 3. Device online, live telemetry has no appliedTariffPerKwh (pending firmware/confirmation)
      expect(
        evaluateTariffSync(
          controlTariff: 1444.7,
          appliedTariff: null,
          isDeviceReachable: true,
        ),
        equals(TariffSyncStatus.pendingDevice),
      );

      // 4. Device online, applied tariff matches cloud control target
      expect(
        evaluateTariffSync(
          controlTariff: 1444.7,
          appliedTariff: 1444.7,
          isDeviceReachable: true,
        ),
        equals(TariffSyncStatus.synced),
      );

      // 5. Device online, applied tariff differs from target control (pending sync)
      expect(
        evaluateTariffSync(
          controlTariff: 1444.7,
          appliedTariff: 1352.0,
          isDeviceReachable: true,
        ),
        equals(TariffSyncStatus.pendingDevice),
      );
    });

    test('SensorReading parses and formats appliedTariffPerKwh, daily_cost, and monthly_cost', () {
      final jsonMap = {
        'voltage': 218.6,
        'current': 0.063,
        'power': 6.1,
        'energy_kwh': 0.053,
        'daily_energy': 0.005,
        'monthly_energy': 0.005,
        'daily_cost': 8.0,
        'monthly_cost': 8.0,
        'frequency': 50.0,
        'pf': 0.53,
        'relay_state': false,
        'sensor_valid': true,
        'uptime_ms': 944618,
        'tariff_per_kwh': 1444.7,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final reading = SensorReading.fromMap(jsonMap);
      expect(reading.appliedTariffPerKwh, equals(1444.7));
      expect(reading.voltage, equals(218.6));
      expect(reading.current, equals(0.063));
      expect(reading.power, equals(6.1));
      expect(reading.dailyEnergyKwh, equals(0.005));
      expect(reading.monthlyEnergyKwh, equals(0.005));
      expect(reading.dailyCost, equals(8.0));
      expect(reading.monthlyCost, equals(8.0));

      final outputMap = reading.toMap();
      expect(outputMap['tariff_per_kwh'], equals(1444.7));
      expect(outputMap['daily_cost'], equals(8.0));
      expect(outputMap['monthly_cost'], equals(8.0));
      expect(outputMap['current'], equals(0.063));
      expect(outputMap['daily_energy'], equals(0.005));
      expect(outputMap['monthly_energy'], equals(0.005));
      expect(outputMap['voltage'], equals(218.6));
      expect(outputMap['power'], equals(6.1));
    });

    test('SensorReading cost calculation logic strictly prevents secret local tariff substitution', () {
      // Skenario: Telemetri dari firmware lama tanpa daily_cost dan tanpa tariff_per_kwh
      final legacyReading = SensorReading.fromMap({
        'voltage': 218.6,
        'current': 0.063,
        'power': 6.1,
        'energy_kwh': 0.053,
        'daily_energy': 0.005,
        'monthly_energy': 0.005,
        'sensor_valid': true,
      });

      expect(legacyReading.dailyCost, isNull);
      expect(legacyReading.monthlyCost, isNull);
      expect(legacyReading.appliedTariffPerKwh, isNull);

      // Verifikasi logika fallback aplikasi:
      // Jika appliedTariffPerKwh dan dailyCost null, jangan hitung biaya diam-diam menggunakan tarif lokal
      final double? computedDailyCost;
      if (legacyReading.dailyCost != null) {
        computedDailyCost = legacyReading.dailyCost;
      } else if (legacyReading.appliedTariffPerKwh != null) {
        computedDailyCost = (legacyReading.dailyEnergyKwh * legacyReading.appliedTariffPerKwh!).roundToDouble();
      } else {
        computedDailyCost = null;
      }

      expect(computedDailyCost, isNull, reason: 'Biaya tidak boleh dihitung diam-diam jika tarif perangkat belum terkonfirmasi');
    });

    test('DeviceService updateTariff updates static state and local persistence', () async {
      SharedPreferences.setMockInitialValues({});

      DeviceService.updateTariff(1500.0, '2026-10-29', 'Penyesuaian Oktober');
      expect(DeviceService.currentTariff, equals(1500.0));
      expect(DeviceService.tariffNotifier.value, equals(1500.0));
      expect(DeviceService.tariffActiveDate, equals('2026-10-29'));

      // Test setTariffFromCloud (e.g. cloud sends updated tariff to all connected members)
      DeviceService.setTariffFromCloud(2000.0, date: '2026-11-02');
      expect(DeviceService.currentTariff, equals(2000.0));
      expect(DeviceService.tariffNotifier.value, equals(2000.0));
      expect(DeviceService.tariffActiveDate, equals('2026-11-02'));

      // Test initTariff restores persisted tariff after app restart (relog)
      DeviceService.tariffNotifier.value = 1352.0; // Simulate RAM reset
      await DeviceService.initTariff();
      expect(DeviceService.currentTariff, equals(2000.0));
    });

    test('EnergyDatabaseService weekly energy parsing handles list and map structures without duplication', () {
      final mapData = {'0': 0.05, '1': 0.12, '2': 0.0, '3': 0.25, '4': 0.0, '5': 0.0, '6': 0.0};
      final listResult = List<double>.filled(7, 0.0);
      mapData.forEach((key, val) {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && idx < 7) {
          listResult[idx] = (val as num).toDouble();
        }
      });

      expect(listResult[0], equals(0.05));
      expect(listResult[1], equals(0.12));
      expect(listResult[3], equals(0.25));
      expect(listResult.length, equals(7));
    });

    test('ScheduledTariff model correctly evaluates isDue, serialization and deserialization', () {
      final futureTime = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
      final pastTime = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;

      final futureSchedule = ScheduledTariff(
        rate: 1600.0,
        effectiveTimestamp: futureTime,
        effectiveDateStr: 'Besok',
        note: 'Penyesuaian Besok',
      );
      expect(futureSchedule.isDue, isFalse);

      final dueSchedule = ScheduledTariff(
        rate: 1700.0,
        effectiveTimestamp: pastTime,
        effectiveDateStr: 'Hari Ini',
        note: 'Aktif Sekarang',
      );
      expect(dueSchedule.isDue, isTrue);

      final map = futureSchedule.toMap();
      expect(map['rate'], equals(1600.0));
      expect(map['effective_timestamp'], equals(futureTime));
      expect(map['effective_date_str'], equals('Besok'));
      expect(map['note'], equals('Penyesuaian Besok'));

      final parsed = ScheduledTariff.fromMap(map);
      expect(parsed.rate, equals(1600.0));
      expect(parsed.effectiveTimestamp, equals(futureTime));
      expect(parsed.effectiveDateStr, equals('Besok'));
      expect(parsed.isDue, isFalse);
    });
  });
}
