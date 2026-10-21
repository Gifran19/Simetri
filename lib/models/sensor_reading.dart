// File: lib/models/sensor_reading.dart

/// Model pembacaan telemetri sensor PZEM-004T dari ESP32 (real-time).
class SensorReading {
  final double voltage;          // Tegangan (Volt), misal: 220.4 V
  final double current;          // Arus (Ampere), misal: 1.25 A
  final double power;            // Daya Aktif (Watt), misal: 275.5 W
  final double frequency;        // Frekuensi listrik (Hz), misal: 50.0 Hz
  final double powerFactor;      // Faktor daya (PF), misal: 0.98
  final double energyKwh;        // Akumulasi energi total sensor (kWh)
  final double dailyEnergyKwh;   // Pemakaian kWh hari ini
  final double monthlyEnergyKwh; // Pemakaian kWh bulan ini
  final bool relayState;         // Status relay: true = ON, false = OFF (Trip/Putus)
  final DateTime timestamp;      // Waktu pembacaan data
  final bool isFromFirebase;     // true jika data asli dari Firebase RTDB, false jika simulasi

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
  });

  /// Buat objek pembacaan sensor dalam kondisi offline/mati
  factory SensorReading.zero() {
    return SensorReading(
      voltage: 0.0,
      current: 0.0,
      power: 0.0,
      frequency: 0.0,
      powerFactor: 0.0,
      energyKwh: 42.5,
      dailyEnergyKwh: 42.5,
      monthlyEnergyKwh: 125.0,
      relayState: false,
      timestamp: DateTime.now(),
      isFromFirebase: false,
    );
  }

  /// Parse dari format JSON Firebase Realtime Database
  /// Payload yang dikirim oleh ESP32:
  /// {
  ///   "voltage": 221.4,
  ///   "current": 1.35,
  ///   "power": 298.8,
  ///   "frequency": 50.0,
  ///   "power_factor": 0.97,
  ///   "energy_kwh": 43.12,
  ///   "daily_energy": 4.25,
  ///   "monthly_energy": 125.4,
  ///   "relay_state": true,
  ///   "timestamp": 1729300000000
  /// }
  factory SensorReading.fromMap(Map<dynamic, dynamic> map, {bool isFromFirebase = true}) {
    double parseDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    bool parseBool(dynamic val, bool fallback) {
      if (val == null) return fallback;
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return fallback;
    }

    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is int) {
        // Cek apakah detik atau milidetik
        if (val < 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
        return DateTime.fromMillisecondsSinceEpoch(val);
      }
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return SensorReading(
      voltage: parseDouble(map['voltage'] ?? map['v'] ?? map['tegangan'], 220.0),
      current: parseDouble(map['current'] ?? map['c'] ?? map['i'] ?? map['arus'], 0.0),
      power: parseDouble(map['power'] ?? map['p'] ?? map['w'] ?? map['daya'], 0.0),
      frequency: parseDouble(map['frequency'] ?? map['f'] ?? map['frekuensi'], 50.0),
      powerFactor: parseDouble(map['power_factor'] ?? map['pf'] ?? map['cosphi'], 0.98),
      energyKwh: parseDouble(map['energy_kwh'] ?? map['energy'] ?? map['kwh'], 42.5),
      dailyEnergyKwh: parseDouble(map['daily_energy'] ?? map['daily_kwh'] ?? map['harian'], 4.2),
      monthlyEnergyKwh: parseDouble(map['monthly_energy'] ?? map['monthly_kwh'] ?? map['bulanan'], 125.0),
      relayState: parseBool(map['relay_state'] ?? map['relay'] ?? map['power_state'], true),
      timestamp: parseTime(map['timestamp'] ?? map['updated_at']),
      isFromFirebase: isFromFirebase,
    );
  }

  /// Ekspor ke JSON untuk dikirim ke Firebase
  Map<String, dynamic> toMap() {
    return {
      'voltage': double.parse(voltage.toStringAsFixed(1)),
      'current': double.parse(current.toStringAsFixed(2)),
      'power': double.parse(power.toStringAsFixed(1)),
      'frequency': double.parse(frequency.toStringAsFixed(1)),
      'power_factor': double.parse(powerFactor.toStringAsFixed(2)),
      'energy_kwh': double.parse(energyKwh.toStringAsFixed(3)),
      'daily_energy': double.parse(dailyEnergyKwh.toStringAsFixed(2)),
      'monthly_energy': double.parse(monthlyEnergyKwh.toStringAsFixed(1)),
      'relay_state': relayState,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
