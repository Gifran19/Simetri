/// Model data energi per tahun, mendukung parsing dari Firebase Realtime Database.
///
/// Struktur data di Firebase:
/// energy_data/
///   {year}/               ← misal "2026"
///     monthly_energy/
///       "0": 62.5         ← Jan
///       "1": 67.0         ← Feb
///       ...
///       "11": 75.0        ← Des
///     monthly_cost/
///       "0": 84490        ← Jan (Rp)
///       ...
///     summary/
///       total_energy: 825.0
///       total_cost: 1116300
///       available_years: [2024, 2025, 2026]
class YearlyEnergyData {
  final int year;
  final double totalEnergy;
  final double averageMonthlyEnergy;
  final double totalCost;

  /// Selisih pemakaian energi dibanding tahun sebelumnya (persen, negatif = turun)
  final double? energyChangePercent;

  /// Selisih biaya dibanding tahun sebelumnya (persen, negatif = turun)
  final double? costChangePercent;

  /// Data pemakaian kWh per bulan (index 0 = Jan, 11 = Des)
  final List<double> monthlyEnergy;

  /// Data biaya per bulan dalam Rupiah (index 0 = Jan, 11 = Des)
  final List<double> monthlyCost;

  const YearlyEnergyData({
    required this.year,
    required this.totalEnergy,
    required this.averageMonthlyEnergy,
    required this.totalCost,
    this.energyChangePercent,
    this.costChangePercent,
    required this.monthlyEnergy,
    required this.monthlyCost,
  });

  /// Buat YearlyEnergyData dari snapshot Firebase Realtime Database.
  /// Gunakan [prevData] untuk menghitung persen perubahan dibanding tahun lalu.
  factory YearlyEnergyData.fromFirebase({
    required int year,
    required Map<dynamic, dynamic> data,
    YearlyEnergyData? prevData,
  }) {
    // Parse monthly_energy (12 elemen, fill 0 jika tidak ada)
    final rawEnergy = data['monthly_energy'] as Map<dynamic, dynamic>? ?? {};
    final monthlyEnergy = List<double>.generate(12, (i) {
      final val = rawEnergy[i.toString()] ?? rawEnergy[i] ?? 0;
      return (val as num).toDouble();
    });

    // Parse monthly_cost (12 elemen, fill 0 jika tidak ada)
    final rawCost = data['monthly_cost'] as Map<dynamic, dynamic>? ?? {};
    final monthlyCost = List<double>.generate(12, (i) {
      final val = rawCost[i.toString()] ?? rawCost[i] ?? 0;
      return (val as num).toDouble();
    });

    // Hitung summary dari data bulanan jika tidak tersedia di node summary
    final summary = data['summary'] as Map<dynamic, dynamic>? ?? {};
    final totalEnergy =
        ((summary['total_energy'] as num?)?.toDouble()) ??
        monthlyEnergy.fold<double>(0.0, (a, b) => a + b);
    final totalCost =
        ((summary['total_cost'] as num?)?.toDouble()) ??
        monthlyCost.fold<double>(0.0, (a, b) => a + b);
    final avgEnergy = totalEnergy / 12;

    // Hitung persentase perubahan jika ada data tahun sebelumnya
    double? energyChange;
    double? costChange;
    if (prevData != null && prevData.totalEnergy > 0) {
      energyChange = ((totalEnergy - prevData.totalEnergy) / prevData.totalEnergy) * 100;
    }
    if (prevData != null && prevData.totalCost > 0) {
      costChange = ((totalCost - prevData.totalCost) / prevData.totalCost) * 100;
    }

    return YearlyEnergyData(
      year: year,
      totalEnergy: totalEnergy,
      averageMonthlyEnergy: avgEnergy,
      totalCost: totalCost,
      energyChangePercent: energyChange,
      costChangePercent: costChange,
      monthlyEnergy: monthlyEnergy,
      monthlyCost: monthlyCost,
    );
  }

  /// Data kosong saat perangkat IoT belum terhubung
  static YearlyEnergyData empty(int year) {
    return YearlyEnergyData(
      year: year,
      totalEnergy: 0.0,
      averageMonthlyEnergy: 0.0,
      totalCost: 0.0,
      energyChangePercent: null,
      costChangePercent: null,
      monthlyEnergy: List.filled(12, 0.0),
      monthlyCost: List.filled(12, 0.0),
    );
  }

  /// Data dummy untuk fallback / saat Firebase belum dikonfigurasi
  static YearlyEnergyData dummy(int year) {
    final energyByYear = {
      2024: [58.0, 62.0, 65.0, 60.0, 58.0, 63.0, 60.0, 64.0, 65.0, 67.0, 62.0, 70.0],
      2025: [60.0, 64.0, 68.0, 62.0, 60.0, 65.0, 61.0, 66.0, 67.0, 69.0, 63.0, 72.0],
      2026: [62.0, 67.0, 70.0, 65.0, 62.0, 67.0, 63.0, 67.0, 68.0, 70.0, 66.0, 75.0],
    };
    final costByYear = {
      2024: [
        78480.0,
        83824.0,
        87880.0,
        81120.0,
        78480.0,
        85176.0,
        81120.0,
        86528.0,
        87880.0,
        90584.0,
        83824.0,
        94640.0,
      ],
      2025: [
        81120.0,
        86528.0,
        91936.0,
        83824.0,
        81120.0,
        87880.0,
        82472.0,
        89232.0,
        90584.0,
        93288.0,
        85176.0,
        97344.0,
      ],
      2026: [
        83824.0,
        90584.0,
        94640.0,
        87880.0,
        83824.0,
        90584.0,
        85176.0,
        90584.0,
        91936.0,
        94640.0,
        89232.0,
        101400.0,
      ],
    };

    final energy = energyByYear[year] ?? List.filled(12, 0.0);
    final cost = costByYear[year] ?? List.filled(12, 0.0);
    final totalEnergy = energy.fold(0.0, (a, b) => a + b);
    final totalCost = cost.fold(0.0, (a, b) => a + b);

    // Hitung perubahan terhadap tahun sebelumnya
    double? energyChange;
    double? costChange;
    final prevYear = year - 1;
    if (energyByYear.containsKey(prevYear)) {
      final prevEnergy = energyByYear[prevYear]!.fold(0.0, (a, b) => a + b);
      energyChange = ((totalEnergy - prevEnergy) / prevEnergy) * 100;
      final prevCost = costByYear[prevYear]!.fold(0.0, (a, b) => a + b);
      costChange = ((totalCost - prevCost) / prevCost) * 100;
    }

    return YearlyEnergyData(
      year: year,
      totalEnergy: totalEnergy,
      averageMonthlyEnergy: totalEnergy / 12,
      totalCost: totalCost,
      energyChangePercent: energyChange,
      costChangePercent: costChange,
      monthlyEnergy: energy,
      monthlyCost: cost,
    );
  }
}
