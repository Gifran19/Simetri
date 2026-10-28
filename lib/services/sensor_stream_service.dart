// File: lib/services/sensor_stream_service.dart

import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/sensor_reading.dart';
import 'live_status.dart';

/// Service untuk streaming telemetri PZEM-004T dari ESP32 via Firebase RTDB
/// (`devices/{deviceId}/live`).
///
/// Prinsip:
/// 1. Mode pemantauan NYATA tidak pernah memakai simulator atau data dummy.
///    Jika tidak ada data, status = [LiveStatus.noData]; jika data lama,
///    [LiveStatus.offline]; jika PZEM gagal, [LiveStatus.sensorError], dst.
/// 2. Simulator hanya berjalan bila mode DEMO dipilih eksplisit saat build
///    (`--dart-define=SIMETRI_DEMO_MODE=true`) dan selalu berstatus
///    [LiveStatus.demo] (diberi label DEMO di UI).
/// 3. Perintah relay ditulis ke `devices/{deviceId}/control/power`. Keberhasilan
///    menulis TIDAK sama dengan relay berpindah; konfirmasi hanya dari telemetri
///    baru perangkat (lihat [evaluateRelayConfirmation]).
class SensorStreamService {
  static final SensorStreamService instance = SensorStreamService._internal();
  SensorStreamService._internal();

  String _activeDeviceId = 'simetri_01';
  String get activeDeviceId => _activeDeviceId;

  String get rtdbDevicePath => 'devices/$_activeDeviceId';
  String get rtdbLivePath => '$rtdbDevicePath/live';
  String get rtdbControlPath => '$rtdbDevicePath/control';

  /// Ganti target perangkat ESP32 secara dinamis
  void setActiveDeviceId(String deviceId) {
    final clean = deviceId.trim();
    if (clean.isNotEmpty && _activeDeviceId != clean) {
      _activeDeviceId = clean;
      _latest = null;
      streamError = null;
      _recompute();
      if (_isStreamingActive) {
        stopStreaming();
        startStreaming();
      }
    }
  }

  final StreamController<SensorReading> _controller = StreamController<SensorReading>.broadcast();

  /// Setiap telemetri (atau tick simulasi DEMO) yang diterima.
  Stream<SensorReading> get readingStream => _controller.stream;

  /// Status data saat ini. Dihitung ulang tiap 2 detik agar OFFLINE terdeteksi
  /// walaupun tidak ada event baru dari database.
  final ValueNotifier<LiveStatus> statusNotifier = ValueNotifier<LiveStatus>(LiveStatus.noData);
  LiveStatus get status => statusNotifier.value;

  SensorReading? _latest;

  /// Pembacaan terakhir yang diterima (null jika belum pernah ada).
  SensorReading? get latestReading => _latest;

  /// Pesan galat terakhir dari listener Firebase (mis. izin ditolak), atau null.
  String? streamError;

  StreamSubscription<DatabaseEvent>? _firebaseSub;
  Timer? _statusTimer;
  Timer? _simulationTimer;

  bool _isStreamingActive = false;

  // Akumulator energi simulasi DEMO (kWh) - hanya dipakai di mode DEMO
  double _simDailyEnergy = 0.0;
  double _simMonthlyEnergy = 0.0;
  final Random _random = Random();

  /// Label sumber data yang jujur untuk ditampilkan di UI.
  String get sourceLabel {
    switch (status) {
      case LiveStatus.demo:
        return 'DEMO - data simulasi (bukan perangkat nyata)';
      case LiveStatus.live:
      case LiveStatus.sensorStale:
      case LiveStatus.sensorError:
        return 'Firebase RTDB (perangkat: $_activeDeviceId)';
      case LiveStatus.offline:
        return 'Perangkat $_activeDeviceId offline';
      case LiveStatus.noData:
        if (!DefaultFirebaseOptions.isConfigured && !kDemoMode) {
          return 'Firebase belum dikonfigurasi';
        }
        return 'Menunggu data dari $_activeDeviceId';
    }
  }

  /// Cek apakah Firebase sudah siap digunakan
  bool get isFirebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
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

  void _recompute() {
    final next = evaluateLiveStatus(
      _latest,
      now: DateTime.now(),
      demo: kDemoMode && _simulationTimer != null,
    );
    if (statusNotifier.value != next) {
      statusNotifier.value = next;
    }
  }

  // -------------------------------------------------------------
  // START & STOP STREAM
  // -------------------------------------------------------------

  /// Mulai streaming. Mode nyata: dengarkan Firebase. Mode DEMO (eksplisit): simulasi.
  void startStreaming() {
    if (_isStreamingActive) return;
    _isStreamingActive = true;

    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _recompute());

    if (kDemoMode) {
      _startSimulation();
      return;
    }

    final db = _db;
    if (db != null) {
      _listenToFirebase(db);
    } else {
      streamError = 'Firebase belum dikonfigurasi atau belum diinisialisasi.';
      _recompute();
    }
  }

  /// Hentikan streaming data
  void stopStreaming() {
    _isStreamingActive = false;
    _firebaseSub?.cancel();
    _firebaseSub = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  // -------------------------------------------------------------
  // FIREBASE LISTENER (mode nyata; tanpa fallback simulator)
  // -------------------------------------------------------------

  void _listenToFirebase(FirebaseDatabase db) {
    _firebaseSub?.cancel();
    streamError = null;

    try {
      final ref = db.ref(rtdbLivePath);
      _firebaseSub = ref.onValue.listen(
        (event) {
          if (!_isStreamingActive) return;
          streamError = null;

          final raw = event.snapshot.value;
          if (event.snapshot.exists && raw is Map) {
            try {
              final reading = SensorReading.fromMap(raw, isFromFirebase: true);
              _latest = reading;
              if (!_controller.isClosed) _controller.add(reading);
            } catch (e) {
              debugPrint('Error parsing Firebase sensor data: $e');
              _latest = null;
              streamError = 'Format data perangkat tidak dikenali.';
            }
          } else {
            // Node kosong: perangkat belum pernah mengirim data.
            _latest = null;
          }
          _recompute();
        },
        onError: (Object error) {
          debugPrint('Firebase stream error: $error');
          _latest = null;
          streamError = 'Gagal membaca data perangkat: $error';
          _recompute();
        },
      );
    } catch (e) {
      debugPrint('Failed to attach Firebase stream: $e');
      streamError = 'Gagal menghubungkan listener: $e';
      _recompute();
    }
  }

  // -------------------------------------------------------------
  // SIMULATOR DEMO (hanya jika SIMETRI_DEMO_MODE=true)
  // -------------------------------------------------------------

  void _startSimulation() {
    if (!kDemoMode) return; // pengaman: tidak pernah aktif di mode nyata
    if (_simulationTimer != null && _simulationTimer!.isActive) return;

    _emitSimulatedTick();
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isStreamingActive) {
        timer.cancel();
        return;
      }
      _emitSimulatedTick();
    });
    _recompute();
  }

  void _emitSimulatedTick() {
    final double voltage = 220.0 + (_random.nextDouble() * 5.0 - 2.5);
    final double current = 0.8 + (_random.nextDouble() * 1.7);
    final double pf = 0.94 + (_random.nextDouble() * 0.05);
    final double power = voltage * current * pf;
    final double frequency = 50.0 + (_random.nextDouble() * 0.16 - 0.08);

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
      dailyEnergyKwh: double.parse(_simDailyEnergy.toStringAsFixed(3)),
      monthlyEnergyKwh: double.parse(_simMonthlyEnergy.toStringAsFixed(3)),
      relayState: false,
      timestamp: DateTime.now(),
      isFromFirebase: false,
    );

    _latest = reading;
    if (!_controller.isClosed) _controller.add(reading);
    _recompute();
  }

  // -------------------------------------------------------------
  // KONTROL RELAY
  // -------------------------------------------------------------

  /// Menulis perintah daya ke `devices/{id}/control/power`.
  ///
  /// Hasil `written` HANYA berarti server menerima penulisan. Itu bukan bukti
  /// perangkat menerimanya, apalagi bahwa relay/beban berubah. Tolak jika
  /// perangkat tidak terjangkau agar perintah tidak mengantre diam-diam.
  Future<RelayWriteResult> writeRelayCommand(bool powerOn) async {
    if (kDemoMode) return RelayWriteResult.demoNotSent;

    final db = _db;
    if (db == null) return RelayWriteResult.firebaseUnavailable;

    _recompute();
    if (!status.deviceReachable) return RelayWriteResult.deviceNotReachable;

    try {
      await db.ref(rtdbControlPath).update({
        'power': powerOn,
        'updated_at': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 8));
      return RelayWriteResult.written;
    } on TimeoutException {
      return RelayWriteResult.timedOut;
    } on FirebaseException catch (e) {
      debugPrint('Relay command Firebase error: ${e.code}');
      if (e.code == 'permission-denied') return RelayWriteResult.permissionDenied;
      return RelayWriteResult.failed;
    } catch (e) {
      debugPrint('Relay command error: $e');
      return RelayWriteResult.failed;
    }
  }
}
