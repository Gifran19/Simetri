// File: lib/models/sensor_reading.dart

/// Model pembacaan telemetri sensor PZEM-004T dari ESP32 (real-time).
class SensorReading {
  final double voltage;          // Tegangan (Volt)
  final double current;          // Arus (Ampere)
  final double power;            // Daya Aktif (Watt)
  final double frequency;        // Frekuensi listrik (Hz)
  final double powerFactor;      // Faktor daya (PF)
  final double energyKwh;        // Akumulasi energi total sensor (kWh)
  final double dailyEnergyKwh;   // Pemakaian kWh hari ini
  final double monthlyEnergyKwh; // Pemakaian kWh bulan ini
  final bool relayState;         // Status relay daya
  final DateTime timestamp;      // Waktu pembacaan data
  final bool isFromFirebase;     // true jika data asli dari Firebase RTDB, false jika simulasi

  // Metadata validitas & pemisahan status relay
  final bool isValid;            // false jika sensor gagal membaca (PZEM offline / NaN)
  final bool isStale;            // true jika data sudah usang (> 15-30 detik)
  final int? readingAgeMs;       // Usia pembacaan sensor (ms) dari ESP32
  final bool? requestedPower;    // Perintah daya terakhir dari cloud
  final bool? relayOutputState;  // Status output GPIO relay fisik
  final bool relayControlEnabled;// Apakah kontrol relay diizinkan di firmware
  final String? sensorError;     // Pesan error jika pembacaan gagal
  final double? appliedTariffPerKwh; // Tarif listrik aktif yang saat ini diterapkan di perangkat (Rp/kWh)

  const SensorReading({
    required this.voltage,
    required this.current,
    required this.power,
    this.frequency = 50.0,
    this.powerFactor = 0.98,
    required this.energyKwh,
    required this.dailyEnergyKwh,
    required this.monthlyEnergyKwh,
    this.relayState = true,
    required this.timestamp,
    this.isFromFirebase = false,
    this.isValid = true,
    this.isStale = false,
    this.readingAgeMs,
    this.requestedPower,
    this.relayOutputState,
    this.relayControlEnabled = false,
    this.sensorError,
    this.appliedTariffPerKwh,
  });

  /// Placeholder kosong (belum ada data). Semua nilai nol dan ditandai tidak valid;
  /// timestamp epoch 0 sehingga selalu dievaluasi sebagai usang/offline.
  factory SensorReading.zero() {
    return SensorReading(
      voltage: 0.0,
      current: 0.0,
      power: 0.0,
      frequency: 0.0,
      powerFactor: 0.0,
      energyKwh: 0.0,
      dailyEnergyKwh: 0.0,
      monthlyEnergyKwh: 0.0,
      relayState: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      isFromFirebase: false,
      isValid: false,
      isStale: true,
      sensorError: 'Belum ada data dari perangkat',
    );
  }

  /// Parse dari format JSON Firebase Realtime Database
  factory SensorReading.fromMap(Map<dynamic, dynamic> map, {bool isFromFirebase = true}) {
    double? parseNullableDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    double parseDouble(dynamic val, double fallback) {
      final parsed = parseNullableDouble(val);
      return parsed ?? fallback;
    }

    bool parseBool(dynamic val, bool fallback) {
      if (val == null) return fallback;
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return fallback;
    }

    // Timestamp yang hilang/tidak terbaca TIDAK boleh dianggap "sekarang"
    // (itu akan membuat data tak bertanda waktu tampak segar). Gunakan epoch 0
    // agar dievaluasi sebagai usang/offline.
    final DateTime unknownTime = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime parseTime(dynamic val) {
      if (val == null) return unknownTime;
      if (val is int) {
        if (val < 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
        return DateTime.fromMillisecondsSinceEpoch(val);
      }
      if (val is double) {
        return DateTime.fromMillisecondsSinceEpoch(val.toInt());
      }
      if (val is String) {
        return DateTime.tryParse(val) ?? unknownTime;
      }
      return unknownTime;
    }

    // Deteksi validitas sensor eksplisit dari payload firmware
    final rawSensorValid = map['sensor_valid'];
    final rawVoltage = parseNullableDouble(map['voltage'] ?? map['v'] ?? map['tegangan']);
    final rawPower = parseNullableDouble(map['power'] ?? map['p'] ?? map['w'] ?? map['daya']);

    final bool isValid = (rawSensorValid != false) && (rawVoltage != null);

    final int? readingAge = (map['reading_age_ms'] is num)
        ? (map['reading_age_ms'] as num).toInt()
        : null;

    final recordedTime = parseTime(map['server_timestamp'] ?? map['timestamp'] ?? map['updated_at']);
    final int secondsSinceRecord = DateTime.now().difference(recordedTime).inSeconds;

    final bool isStale = (readingAge != null && readingAge > 20000) || (secondsSinceRecord > 30);

    return SensorReading(
      voltage: rawVoltage ?? 0.0,
      current: parseDouble(map['current'] ?? map['c'] ?? map['i'] ?? map['arus'], 0.0),
      power: rawPower ?? 0.0,
      frequency: parseDouble(map['frequency'] ?? map['f'] ?? map['frekuensi'], 0.0),
      powerFactor: parseDouble(map['power_factor'] ?? map['pf'] ?? map['cosphi'], 0.0),
      energyKwh: parseDouble(map['energy_kwh'] ?? map['energy'] ?? map['kwh'], 0.0),
      dailyEnergyKwh: parseDouble(map['daily_energy'] ?? map['daily_kwh'] ?? map['harian'], 0.0),
      monthlyEnergyKwh: parseDouble(map['monthly_energy'] ?? map['monthly_kwh'] ?? map['bulanan'], 0.0),
      relayState: parseBool(map['relay_state'] ?? map['relay_output_state'] ?? map['relay'], false),
      timestamp: recordedTime,
      isFromFirebase: isFromFirebase,
      isValid: isValid,
      isStale: isStale,
      readingAgeMs: readingAge,
      requestedPower: (map['requested_power'] is bool) ? map['requested_power'] as bool : null,
      relayOutputState: (map['relay_output_state'] is bool) ? map['relay_output_state'] as bool : null,
      relayControlEnabled: parseBool(map['relay_control_enabled'], false),
      sensorError: map['sensor_error']?.toString() ?? (isValid ? null : 'Sensor tidak merespons'),
      appliedTariffPerKwh: parseNullableDouble(map['tariff_per_kwh'] ?? map['applied_tariff']),
    );
  }

  /// Ekspor ke JSON untuk dikirim ke Firebase
  Map<String, dynamic> toMap() {
    return {
      'sensor_valid': isValid,
      'voltage': isValid ? double.parse(voltage.toStringAsFixed(1)) : null,
      'current': isValid ? double.parse(current.toStringAsFixed(2)) : null,
      'power': isValid ? double.parse(power.toStringAsFixed(1)) : null,
      'frequency': isValid ? double.parse(frequency.toStringAsFixed(1)) : null,
      'power_factor': isValid ? double.parse(powerFactor.toStringAsFixed(2)) : null,
      'energy_kwh': double.parse(energyKwh.toStringAsFixed(3)),
      'daily_energy': double.parse(dailyEnergyKwh.toStringAsFixed(2)),
      'monthly_energy': double.parse(monthlyEnergyKwh.toStringAsFixed(1)),
      if (appliedTariffPerKwh != null) 'tariff_per_kwh': appliedTariffPerKwh,
      'relay_output_state': relayState,
      'relay_control_enabled': relayControlEnabled,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
