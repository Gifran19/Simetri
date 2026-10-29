// File: lib/services/live_status.dart
//
// Logika murni (tanpa Firebase) untuk menentukan status data perangkat dan
// konfirmasi perintah relay. Dipisahkan agar dapat diuji tanpa emulator.

import '../models/sensor_reading.dart';

/// Mode DEMO hanya aktif jika dipilih secara eksplisit saat build/run:
///   flutter run --dart-define=SIMETRI_DEMO_MODE=true
/// Default-nya false: aplikasi TIDAK akan menampilkan data simulasi/dummy.
const bool kDemoMode = bool.fromEnvironment('SIMETRI_DEMO_MODE', defaultValue: false);

/// Telemetri dianggap OFFLINE jika `server_timestamp` terakhir lebih tua dari ini.
/// (Firmware mengirim telemetri setiap 5 detik.)
const Duration kOfflineAfter = Duration(seconds: 30);

/// Pembacaan sensor di sisi perangkat dianggap STALE jika `reading_age_ms` melebihi ini.
const int kSensorStaleAfterMs = 20000;

/// Batas waktu menunggu telemetri baru yang mengonfirmasi perintah relay.
const Duration kRelayConfirmTimeout = Duration(seconds: 20);

enum LiveStatus {
  /// Belum ada node `live` atau belum ada data yang diterima.
  noData,

  /// Telemetri terakhir terlalu lama (perangkat tidak mengirim data).
  offline,

  /// Perangkat mengirim data, tetapi pembacaan sensornya sudah usang.
  sensorStale,

  /// Perangkat mengirim data, tetapi PZEM gagal dibaca (`sensor_valid=false`).
  sensorError,

  /// Data nyata dan segar dari perangkat.
  live,

  /// Data SIMULASI (hanya jika mode DEMO dipilih eksplisit).
  demo,
}

extension LiveStatusX on LiveStatus {
  /// Label singkat untuk badge UI.
  String get badge {
    switch (this) {
      case LiveStatus.noData:
        return 'BELUM ADA DATA';
      case LiveStatus.offline:
        return 'OFFLINE';
      case LiveStatus.sensorStale:
        return 'SENSOR STALE';
      case LiveStatus.sensorError:
        return 'SENSOR ERROR';
      case LiveStatus.live:
        return 'LIVE';
      case LiveStatus.demo:
        return 'DEMO';
    }
  }

  /// Penjelasan untuk pengguna.
  String get description {
    switch (this) {
      case LiveStatus.noData:
        return 'Belum ada data dari perangkat.';
      case LiveStatus.offline:
        return 'Perangkat tidak mengirim data (offline).';
      case LiveStatus.sensorStale:
        return 'Pembacaan sensor sudah usang.';
      case LiveStatus.sensorError:
        return 'Sensor PZEM tidak terbaca oleh perangkat.';
      case LiveStatus.live:
        return 'Data nyata dari perangkat.';
      case LiveStatus.demo:
        return 'DEMO: data simulasi, bukan dari perangkat.';
    }
  }

  /// true jika perangkat sendiri sedang mengirim telemetri segar
  /// (termasuk saat sensornya error/stale).
  bool get deviceReachable =>
      this == LiveStatus.live || this == LiveStatus.sensorStale || this == LiveStatus.sensorError;

  /// true jika nilai tegangan/arus/daya boleh ditampilkan sebagai angka.
  bool get showsMeasurements => this == LiveStatus.live || this == LiveStatus.demo;
}

/// Menentukan status berdasarkan pembacaan terakhir dan waktu sekarang.
LiveStatus evaluateLiveStatus(
  SensorReading? reading, {
  required DateTime now,
  bool demo = false,
}) {
  if (demo) return LiveStatus.demo;
  if (reading == null) return LiveStatus.noData;

  final age = now.difference(reading.timestamp).abs();
  if (age >= kOfflineAfter) return LiveStatus.offline;
  if (!reading.isValid) return LiveStatus.sensorError;
  final ageMs = reading.readingAgeMs;
  if (ageMs != null && ageMs > kSensorStaleAfterMs) return LiveStatus.sensorStale;
  return LiveStatus.live;
}

/// Keadaan perintah relay dari sudut pandang aplikasi.
enum RelayCommandState {
  /// Tidak ada perintah yang menunggu.
  idle,

  /// Perintah sudah tertulis ke database, menunggu telemetri baru dari perangkat.
  pending,

  /// Perangkat melaporkan telah menerima perintah, TETAPI kontrol relay
  /// dinonaktifkan di firmware (ENABLE_RELAY_CONTROL=false): output tidak digerakkan.
  receivedControlDisabled,

  /// Perangkat melaporkan status output relay (sinyal GPIO) sesuai perintah.
  /// Ini BUKAN bukti bahwa kontak relay atau beban benar-benar berubah.
  outputReported,

  /// Tidak ada telemetri konfirmasi sampai batas waktu.
  timedOut,
}

/// Mengevaluasi apakah telemetri terbaru sudah mengonfirmasi perintah relay.
///
/// [baselineTimestamp] adalah `server_timestamp` telemetri terakhir SEBELUM
/// perintah ditulis. Telemetri yang sama/lebih lama tidak dihitung sebagai
/// konfirmasi (perbandingan memakai timestamp server, bukan jam ponsel).
RelayCommandState evaluateRelayConfirmation({
  required bool desired,
  required DateTime? baselineTimestamp,
  required SensorReading? latest,
}) {
  if (latest == null) return RelayCommandState.pending;
  if (baselineTimestamp != null && !latest.timestamp.isAfter(baselineTimestamp)) {
    return RelayCommandState.pending;
  }
  if (latest.requestedPower != desired) return RelayCommandState.pending;
  if (!latest.relayControlEnabled) return RelayCommandState.receivedControlDisabled;
  if (latest.relayOutputState == desired) return RelayCommandState.outputReported;
  return RelayCommandState.pending;
}

/// Hasil penulisan perintah relay ke Realtime Database.
enum RelayWriteResult {
  written,
  demoNotSent,
  firebaseUnavailable,
  deviceNotReachable,
  permissionDenied,
  timedOut,
  failed,
}

/// Status sinkronisasi tarif listrik antara aplikasi, cloud, dan ESP32.
enum TariffSyncStatus {
  /// Tarif tersinkronisasi: nilai yang dilaporkan perangkat (live) sama dengan nilai di cloud (control).
  synced,

  /// Tarif berhasil ditulis ke cloud (control), tetapi ESP32 belum melaporkan penerapan di (live).
  pendingDevice,

  /// Perangkat offline saat tarif baru diminta (akan diterapkan saat perangkat online kembali).
  deviceOffline,

  /// Data tarif belum tersedia dari perangkat atau cloud.
  noData,
}

extension TariffSyncStatusX on TariffSyncStatus {
  String get label {
    switch (this) {
      case TariffSyncStatus.synced:
        return 'Diterapkan perangkat (Sinkron)';
      case TariffSyncStatus.pendingDevice:
        return 'Tersimpan di Cloud (Menunggu konfirmasi ESP32)';
      case TariffSyncStatus.deviceOffline:
        return 'Tersimpan di Cloud (ESP32 Offline)';
      case TariffSyncStatus.noData:
        return 'Belum tersinkronisasi';
    }
  }

  bool get isConfirmed => this == TariffSyncStatus.synced;
}

/// Hasil penulisan perintah tarif ke Realtime Database.
enum TariffWriteResult {
  written,
  demoNotSent,
  firebaseUnavailable,
  invalidValue,
  permissionDenied,
  timedOut,
  failed,
}

/// Mengevaluasi status sinkronisasi tarif antara nilai di cloud dan nilai yang diterapkan ESP32.
TariffSyncStatus evaluateTariffSync({
  required double? controlTariff,
  required double? appliedTariff,
  required bool isDeviceReachable,
}) {
  if (controlTariff == null && appliedTariff == null) return TariffSyncStatus.noData;
  if (appliedTariff != null && controlTariff != null) {
    if ((appliedTariff - controlTariff).abs() < 0.05) {
      return TariffSyncStatus.synced;
    }
  }
  if (!isDeviceReachable) {
    return TariffSyncStatus.deviceOffline;
  }
  return TariffSyncStatus.pendingDevice;
}

