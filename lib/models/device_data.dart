class DeviceData {

  final bool isConnected;

  final String connectionType;

  final double voltage;

  final double current;

  final double power;

  final double energy;


  DeviceData({

    required this.isConnected,

    required this.connectionType,

    required this.voltage,

    required this.current,

    required this.power,

    required this.energy,

  });


}