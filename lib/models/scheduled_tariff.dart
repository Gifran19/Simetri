// File: lib/models/scheduled_tariff.dart

/// Model untuk konfigurasi tarif listrik yang dijadwalkan berlaku di masa mendatang
class ScheduledTariff {
  final double rate;
  final int effectiveTimestamp;
  final String effectiveDateStr;
  final String note;
  final int? createdAt;

  const ScheduledTariff({
    required this.rate,
    required this.effectiveTimestamp,
    required this.effectiveDateStr,
    this.note = '',
    this.createdAt,
  });

  /// Mengecek apakah jadwal tarif sudah tiba saatnya untuk diaktifkan
  bool get isDue => DateTime.now().millisecondsSinceEpoch >= effectiveTimestamp;

  factory ScheduledTariff.fromMap(Map<dynamic, dynamic> map) {
    return ScheduledTariff(
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      effectiveTimestamp: (map['effective_timestamp'] as num?)?.toInt() ?? 0,
      effectiveDateStr: (map['effective_date_str'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      createdAt: (map['created_at'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rate': rate,
      'effective_timestamp': effectiveTimestamp,
      'effective_date_str': effectiveDateStr,
      'note': note,
      'created_at': createdAt ?? DateTime.now().millisecondsSinceEpoch,
    };
  }
}

