class DeviceData {
  final bool isConnected;
  final String connectionType;

  // Monitoring PZEM-004T
  final double voltage;
  final double current;
  final double power;
  final double frequency;
  final double powerFactor;

  // Energy & PLN Specs
  final double dailyEnergy;
  final double dailyCost;
  final double monthlyEnergy;
  final double monthlyCost;
  final double yearlyEnergy;
  final int powerLimitVa;
  final double monthlyBudgetRp;

  // Status Live Streaming & Sensor Health
  final bool isLiveStream;
  final String streamSource; // e.g. "Firebase RTDB", "Simulasi Real-Time", "Offline"
  final bool isSensorValid;
  final bool isSensorStale;
  final String? sensorStatusMessage;

  // Chart data
  final List<double> dailyHistory; // 7 hari terakhir (Sen - Min)
  final List<double> monthlyEnergyHistory;
  final List<double> monthlyCostHistory;

  DeviceData({
    required this.isConnected,
    required this.connectionType,
    required this.voltage,
    required this.current,
    required this.power,
    this.frequency = 50.0,
    this.powerFactor = 0.98,
    required this.dailyEnergy,
    required this.dailyCost,
    required this.monthlyEnergy,
    required this.monthlyCost,
    required this.yearlyEnergy,
    this.powerLimitVa = 1300,
    this.monthlyBudgetRp = 300000,
    this.isLiveStream = false,
    this.streamSource = 'Dummy',
    this.isSensorValid = true,
    this.isSensorStale = false,
    this.sensorStatusMessage,
    this.dailyHistory = const [2.1, 3.5, 1.8, 4.2, 3.1, 5.0, 4.5],
    required this.monthlyEnergyHistory,
    required this.monthlyCostHistory,
  });

  /// Status data default saat perangkat belum terhubung ke IoT
  factory DeviceData.disconnected() {
    return DeviceData(
      isConnected: false,
      connectionType: 'Belum Terhubung',
      voltage: 0,
      current: 0,
      power: 0,
      frequency: 0,
      powerFactor: 0,
      dailyEnergy: 0,
      dailyCost: 0,
      monthlyEnergy: 0,
      monthlyCost: 0,
      yearlyEnergy: 0,
      powerLimitVa: 1300,
      monthlyBudgetRp: 300000,
      isLiveStream: false,
      streamSource: 'Offline',
      isSensorValid: false,
      isSensorStale: true,
      sensorStatusMessage: 'Perangkat belum terhubung',
      dailyHistory: const [],
      monthlyEnergyHistory: const [],
      monthlyCostHistory: const [],
    );
  }

  DeviceData copyWith({
    bool? isConnected,
    String? connectionType,
    double? voltage,
    double? current,
    double? power,
    double? frequency,
    double? powerFactor,
    double? dailyEnergy,
    double? dailyCost,
    double? monthlyEnergy,
    double? monthlyCost,
    double? yearlyEnergy,
    int? powerLimitVa,
    double? monthlyBudgetRp,
    bool? isLiveStream,
    String? streamSource,
    bool? isSensorValid,
    bool? isSensorStale,
    String? sensorStatusMessage,
    List<double>? dailyHistory,
    List<double>? monthlyEnergyHistory,
    List<double>? monthlyCostHistory,
  }) {
    return DeviceData(
      isConnected: isConnected ?? this.isConnected,
      connectionType: connectionType ?? this.connectionType,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      power: power ?? this.power,
      frequency: frequency ?? this.frequency,
      powerFactor: powerFactor ?? this.powerFactor,
      dailyEnergy: dailyEnergy ?? this.dailyEnergy,
      dailyCost: dailyCost ?? this.dailyCost,
      monthlyEnergy: monthlyEnergy ?? this.monthlyEnergy,
      monthlyCost: monthlyCost ?? this.monthlyCost,
      yearlyEnergy: yearlyEnergy ?? this.yearlyEnergy,
      powerLimitVa: powerLimitVa ?? this.powerLimitVa,
      monthlyBudgetRp: monthlyBudgetRp ?? this.monthlyBudgetRp,
      isLiveStream: isLiveStream ?? this.isLiveStream,
      streamSource: streamSource ?? this.streamSource,
      isSensorValid: isSensorValid ?? this.isSensorValid,
      isSensorStale: isSensorStale ?? this.isSensorStale,
      sensorStatusMessage: sensorStatusMessage ?? this.sensorStatusMessage,
      dailyHistory: dailyHistory ?? this.dailyHistory,
      monthlyEnergyHistory: monthlyEnergyHistory ?? this.monthlyEnergyHistory,
      monthlyCostHistory: monthlyCostHistory ?? this.monthlyCostHistory,
    );
  }
}
