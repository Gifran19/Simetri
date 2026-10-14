class DeviceData {
  final bool isConnected;
  final String connectionType;

  // Monitoring
  final double voltage;
  final double current;
  final double power;

  // Energy
  final double dailyEnergy;
  final double dailyCost;
  final double monthlyEnergy;
  final double monthlyCost;
  final double yearlyEnergy;

  // Chart data
  final List<double> monthlyEnergyHistory;
  final List<double> monthlyCostHistory;

  DeviceData({
    required this.isConnected,
    required this.connectionType,
    required this.voltage,
    required this.current,
    required this.power,
    required this.dailyEnergy,
    required this.dailyCost,
    required this.monthlyEnergy,
    required this.monthlyCost,
    required this.yearlyEnergy,
    required this.monthlyEnergyHistory,
    required this.monthlyCostHistory,
  });
}