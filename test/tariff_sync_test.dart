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
      // 1. Device not connected/reachable
      expect(
        evaluateTariffSync(
          hasData: false,
          deviceReachable: false,
          appliedTariff: null,
          targetTariff: null,
        ),
        equals(TariffSyncStatus.deviceOffline),
      );

      // 2. Device reachable but no data received yet
      expect(
        evaluateTariffSync(
          hasData: false,
          deviceReachable: true,
          appliedTariff: null,
          targetTariff: 1444.7,
        ),
        equals(TariffSyncStatus.noData),
      );

      // 3. Device online, live telemetry has no appliedTariffPerKwh (pending firmware/confirmation)
      expect(
        evaluateTariffSync(
          hasData: true,
          deviceReachable: true,
          appliedTariff: null,
          targetTariff: 1444.7,
        ),
        equals(TariffSyncStatus.pendingDevice),
      );

      // 4. Device online, applied tariff matches cloud control target
      expect(
        evaluateTariffSync(
          hasData: true,
          deviceReachable: true,
          appliedTariff: 1444.7,
          targetTariff: 1444.7,
        ),
        equals(TariffSyncStatus.synced),
      );

      // 5. Device online, applied tariff differs from target control (pending sync)
      expect(
        evaluateTariffSync(
          hasData: true,
          deviceReachable: true,
          appliedTariff: 1352.0,
          targetTariff: 1444.7,
        ),
        equals(TariffSyncStatus.pendingDevice),
      );

      // 6. Device online, target control is null but device reported tariff
      expect(
        evaluateTariffSync(
          hasData: true,
          deviceReachable: true,
          appliedTariff: 1444.7,
          targetTariff: null,
        ),
        equals(TariffSyncStatus.synced),
      );
    });

    test('SensorReading parses and formats appliedTariffPerKwh', () {
      final jsonMap = {
        'voltage': 218.6,
        'current': 0.093,
        'power': 10.7,
        'energy_kwh': 0.053,
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
      expect(reading.current, equals(0.093));
      expect(reading.power, equals(10.7));

      final outputMap = reading.toMap();
      expect(outputMap['tariff_per_kwh'], equals(1444.7));
    });

    test('DeviceService updateTariff updates static state and local persistence', () async {
      SharedPreferences.setMockInitialValues({});

      DeviceService.updateTariff(1500.0, '2026-10-29', 'Penyesuaian Oktober');
      expect(DeviceService.currentTariff, equals(1500.0));
      expect(DeviceService.tariffActiveDate, equals('2026-10-29'));
    });
  });
}
