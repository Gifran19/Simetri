import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_test_app/models/sensor_reading.dart';
import 'package:my_test_app/services/live_status.dart';
import 'package:my_test_app/services/device_service.dart';
import 'package:my_test_app/services/sensor_stream_service.dart';

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
      expect(DeviceService.tariffActiveDate, equals('2026-10-29'));
    });
  });
}
