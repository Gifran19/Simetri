import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/services/device_service.dart';
import 'package:my_test_app/services/sensor_stream_service.dart';
import 'package:my_test_app/widgets/connect_device_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Pairing (Without Login) Logic Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('DeviceService defaults to simetri_01 and saves new paired device ID', () async {
      expect(await DeviceService.getPairedDeviceId(), equals('simetri_01'));

      await DeviceService.savePairedDeviceId('esp32_kamar_02');
      expect(await DeviceService.getPairedDeviceId(), equals('esp32_kamar_02'));
      expect(DeviceService.deviceIdNotifier.value, equals('esp32_kamar_02'));

      await DeviceService.clearPairedDevice();
      expect(await DeviceService.getPairedDeviceId(), equals('simetri_01'));
      expect(await DeviceService.isDeviceConnected(), isFalse);
    });

    test('SensorStreamService dynamically updates Firebase RTDB paths when device ID changes', () {
      final streamService = SensorStreamService.instance;
      streamService.setActiveDeviceId('simetri_ruang_tamu');

      expect(streamService.activeDeviceId, equals('simetri_ruang_tamu'));
      expect(streamService.rtdbDevicePath, equals('devices/simetri_ruang_tamu'));
      expect(streamService.rtdbLivePath, equals('devices/simetri_ruang_tamu/live'));
      expect(streamService.rtdbControlPath, equals('devices/simetri_ruang_tamu/control'));
    });
  });

  group('ConnectDeviceSheet Admin Approval UI Tests', () {
    testWidgets('ConnectDeviceSheet renders anonymous UID, device ID input, and verify button', (tester) async {
      SharedPreferences.setMockInitialValues({'simetri_paired_device_id': 'simetri_01'});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectDeviceSheet(
              onConnected: (device) {},
            ),
          ),
        ),
      );

      expect(find.text('Persetujuan Akses Perangkat SIMETRI'), findsOneWidget);
      expect(find.text('Target Device ID:'), findsOneWidget);
      expect(find.text('Periksa & Verifikasi Izin'), findsOneWidget);
    });
  });
}
