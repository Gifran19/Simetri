// File: lib/services/sensor_stream_service.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../models/sensor_reading.dart';

/// Service untuk streaming data sensor PZEM-004T dari ESP32 secara real-time.
///
/// Fitur:
/// 1. Berlangganan (Subscribe) ke Firebase Realtime Database path `devices/simetri_01/live`.
/// 2. Jika Firebase belum terisi atau ESP32 belum online (karena masih dikerjakan rekan magang),
///    secara cerdas mengaktifkan **Simulator Sensor Real-Time** dengan fluktuasi voltase, arus,
///    dan daya listrik nyata sehingga UI langsung interaktif dan hidup.
/// 3. Menyediakan fungsi `sendTestPacketToFirebase()` untuk menguji koneksi Firebase secara langsung.
/// 4. Menyediakan fungsi `setRelayPower()` untuk mengontrol switch relay daya fisik di ESP32.
class SensorStreamService {
  static final SensorStreamService instance = SensorStreamService._internal();
  SensorStreamService._internal();

  static const String rtdbDevicePath = 'devices/simetri_01';
  static const String rtdbLivePath = '$rtdbDevicePath/live';
  static const String rtdbControlPath = '$rtdbDevicePath/control';

  final StreamController<SensorReading> _controller = StreamController<SensorReading>.broadcast();
  Stream<SensorReading> get readingStream => _controller.stream;

  SensorReading _currentReading = SensorReading.zero();
  SensorReading get currentReading => _currentReading;

  StreamSubscription<DatabaseEvent>? _firebaseSub;
  Timer? _simulationTimer;

  bool _isStreamingActive = false;
  bool _forceSimulation = false;
  bool _hasReceivedFirebaseData = false;
  DateTime? _lastFirebaseReceiveTime;

  // Akumulator energi simulasi (kWh)
  double _simDailyEnergy = 4.25;
  double _simMonthlyEnergy = 125.4;
  final Random _random = Random();

  /// Status apakah saat ini menerima data nyata dari Firebase RTDB
  bool get isReceivingRealFirebase =>
      _hasReceivedFirebaseData &&
      _lastFirebaseReceiveTime != null &&
      DateTime.now().difference(_lastFirebaseReceiveTime!).inSeconds < 10;

  /// Label sumber data saat ini
  String get streamSourceLabel {
    if (isReceivingRealFirebase) {
      return 'Firebase RTDB (Live ESP32)';
    } else if (DefaultFirebaseOptions.isConfigured) {
      return 'Simulasi (Menunggu ESP32 Online)';
    } else {
      return 'Simulasi Live (Firebase Belum Dikonfigurasi)';
    }
  }

  /// Cek apakah Firebase sudah siap digunakan
  bool get isFirebaseReady {
    try {
      return DefaultFirebaseOptions.isConfigured && Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseDatabase? get _db {
    if (!isFirebaseReady) return null;
    try {
      return FirebaseDatabase.instance;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------
  // START & STOP STREAM
  // -------------------------------------------------------------

  /// Mulai streaming data sensor (Firebase jika tersedia, fallback ke simulasi)
  void startStreaming() {
    if (_isStreamingActive) return;
    _isStreamingActive = true;

    final db = _db;
    if (db != null && !_forceSimulation) {
      _listenToFirebase(db);
    } else {
      _startSimulation();
    }
  }

  /// Hentikan streaming data
  void stopStreaming() {
    _isStreamingActive = false;
    _firebaseSub?.cancel();
    _firebaseSub = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  /// Jeda pembacaan (misal saklar daya OFF, nilai menjadi 0 tapi akumulasi kWh tetap)
  void pauseStreamingToZero() {
    final zeroed = SensorReading(
      voltage: 0.0,
      current: 0.0,
      power: 0.0,
      frequency: 0.0,
      powerFactor: 0.0,
      energyKwh: _currentReading.energyKwh,
      dailyEnergyKwh: _currentReading.dailyEnergyKwh,
      monthlyEnergyKwh: _currentReading.monthlyEnergyKwh,
      relayState: false,
      timestamp: DateTime.now(),
      isFromFirebase: _currentReading.isFromFirebase,
    );
    _currentReading = zeroed;
    if (!_controller.isClosed) {
      _controller.add(zeroed);
    }
  }

  // -------------------------------------------------------------
  // FIREBASE LISTENER
  // -------------------------------------------------------------

  void _listenToFirebase(FirebaseDatabase db) {
    _firebaseSub?.cancel();

    try {
      final ref = db.ref(rtdbLivePath);
      _firebaseSub = ref.onValue.listen(
        (event) {
          if (!_isStreamingActive) return;

          if (event.snapshot.exists && event.snapshot.value != null) {
            try {
              final raw = event.snapshot.value;
              if (raw is Map) {
                final reading = SensorReading.fromMap(raw, isFromFirebase: true);
                _currentReading = reading;
                _hasReceivedFirebaseData = true;
                _lastFirebaseReceiveTime = DateTime.now();

                // Matikan simulator jika Firebase mulai mengirimkan data
                if (_simulationTimer != null && _simulationTimer!.isActive) {
                  _simulationTimer?.cancel();
                  _simulationTimer = null;
                }

                if (!_controller.isClosed) {
                  _controller.add(reading);
                }
                return;
              }
            } catch (e) {
              debugPrint('Error parsing Firebase sensor data: $e');
            }
          }

          // Jika node di Firebase kosong atau belum diisi oleh ESP32
          if (!_hasReceivedFirebaseData) {
            _startSimulation();
          }
        },
        onError: (error) {
          debugPrint('Firebase stream error: $error. Falling back to simulation.');
          _startSimulation();
        },
      );

      // Berikan batas waktu 3 detik: jika Firebase tidak menghasilkan data apapun,
      // jalankan simulator agar pengguna tidak melihat layar blank/statis
      Timer(const Duration(seconds: 3), () {
        if (_isStreamingActive && !_hasReceivedFirebaseData && _simulationTimer == null) {
          _startSimulation();
        }
      });
    } catch (e) {
      debugPrint('Failed to attach Firebase stream: $e');
      _startSimulation();
    }
  }

  // -------------------------------------------------------------
  // SENSOR SIMULATOR (Fallback saat ESP32 / Firebase belum aktif)
  // -------------------------------------------------------------

  void _startSimulation() {
    if (_simulationTimer != null && _simulationTimer!.isActive) return;

    // Tick pertama segera
    _emitSimulatedTick();

    // Loop interval 2 detik (sama seperti interval pembacaan ESP32 + PZEM-004T standar)
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isStreamingActive) {
        timer.cancel();
        return;
      }
      _emitSimulatedTick();
    });
  }

  void _emitSimulatedTick() {
    // Simulasi tegangan PLN: 220V normal dengan fluktuasi ± 2.5V (217.5V - 222.5V)
    final double voltage = 220.0 + (_random.nextDouble() * 5.0 - 2.5);

    // Simulasi beban rumah tangga: fluktuasi dinamis antara 0.8A s/d 2.5A
    final double current = 0.8 + (_random.nextDouble() * 1.7);

    // Power factor khas beban rumah tangga (0.94 - 0.99)
    final double pf = 0.94 + (_random.nextDouble() * 0.05);

    // Daya aktif: P = V * I * PF (Watt)
    final double power = voltage * current * pf;

    // Frekuensi listrik PLN: 50.0 Hz ± 0.08 Hz
    final double frequency = 50.0 + (_random.nextDouble() * 0.16 - 0.08);

    // Akumulasi energi dalam 2 detik: E = (P * 2) / (3600 * 1000) kWh
    final double addedKwh = (power * 2.0) / (3600.0 * 1000.0);
    _simDailyEnergy += addedKwh;
    _simMonthlyEnergy += addedKwh;

    final reading = SensorReading(
      voltage: double.parse(voltage.toStringAsFixed(1)),
      current: double.parse(current.toStringAsFixed(2)),
      power: double.parse(power.toStringAsFixed(1)),
      frequency: double.parse(frequency.toStringAsFixed(1)),
      powerFactor: double.parse(pf.toStringAsFixed(2)),
      energyKwh: double.parse(_simDailyEnergy.toStringAsFixed(3)),
      dailyEnergyKwh: double.parse(_simDailyEnergy.toStringAsFixed(2)),
      monthlyEnergyKwh: double.parse(_simMonthlyEnergy.toStringAsFixed(1)),
      relayState: true,
      timestamp: DateTime.now(),
      isFromFirebase: false,
    );

    _currentReading = reading;
    if (!_controller.isClosed) {
      _controller.add(reading);
    }
  }

  // -------------------------------------------------------------
  // KONTROL RELAY & TESTING TOOLS
  // -------------------------------------------------------------

  /// Kirim perintah kendali saklar daya (Relay) ke ESP32 via Firebase
  Future<bool> setRelayPower(bool powerOn) async {
    final db = _db;
    if (db == null) return false;

    try {
      await db.ref(rtdbControlPath).update({
        'power': powerOn,
        'updated_at': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      debugPrint('Failed to send relay command: $e');
      return false;
    }
  }

  /// Kirim data telemetri tiruan ke Firebase Realtime Database.
  /// Ini sangat berguna agar pengguna bisa memvalidasi bahwa project Firebase mereka
  /// sudah terhubung dan bisa menerima data sebelum ESP32 rekan magang siap.
  Future<bool> sendTestPacketToFirebase({
    double voltage = 221.8,
    double current = 1.45,
    double power = 315.0,
  }) async {
    final db = _db;
    if (db == null) return false;

    try {
      final packet = {
        'voltage': voltage,
        'current': current,
        'power': power,
        'frequency': 50.0,
        'power_factor': 0.98,
        'energy_kwh': 42.8,
        'daily_energy': 4.3,
        'monthly_energy': 125.8,
        'relay_state': true,
        'timestamp': ServerValue.timestamp,
      };

      await db.ref(rtdbLivePath).set(packet);
      return true;
    } catch (e) {
      debugPrint('Failed to send test packet to Firebase: $e');
      return false;
    }
  }

  /// Beralih paksa antara mode simulasi dan mode Firebase
  void setForceSimulation(bool force) {
    _forceSimulation = force;
    stopStreaming();
    startStreaming();
  }
}
