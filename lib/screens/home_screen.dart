import 'package:flutter/material.dart';
import 'energy_screen.dart';
import '../models/device_data.dart';
import '../services/device_service.dart';
import '../utils/responsive.dart';
import '../widgets/home_header.dart';
import '../widgets/device_status_card.dart';
import '../widgets/tariff_card.dart';
import '../widgets/monitoring_card.dart';
import '../widgets/energy_summary_card.dart';
import '../widgets/daily_energy_chart.dart';
import '../widgets/monthly_energy_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Data dummy — akan digantikan dengan data live dari ESP32
  final DeviceData device = DeviceData(
    isConnected: true,
    connectionType: 'WiFi',
    voltage: 221,
    current: 0.1,
    power: 14.2,
    dailyEnergy: 42.5,
    dailyCost: 64000,
    monthlyEnergy: 125,
    monthlyCost: 180000,
    yearlyEnergy: 825,
    monthlyEnergyHistory: [60, 65, 70, 63, 61, 67, 62, 66, 68, 70, 65, 75],
    monthlyCostHistory: [120, 135, 110, 90, 100, 125, 140, 130, 115, 150, 135, 125],
  );

  bool devicePower = true;

  void togglePower(bool value) {
    setState(() {
      devicePower = value;
    });
    // TODO: kirim perintah ke ESP32
    // sendCommand(value ? 'ON' : 'OFF');
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xff071426),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 1050,
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 14,
            vertical: isWide ? 20 : 12,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: isWide ? _buildTabletLayout() : _buildMobileLayout(),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MOBILE LAYOUT (Android & iPhone)
  // ==========================================
  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeHeader(),
        const SizedBox(height: 14),

        DeviceStatusCard(
          connected: device.isConnected,
          power: devicePower,
          onChanged: togglePower,
        ),
        const SizedBox(height: 14),

        TariffCard(
          tariff: DeviceService.currentTariff,
          activeDate: DeviceService.tariffActiveDate,
          onTariffChanged: (value, date, note) {
            DeviceService.updateTariff(value, date, note);
            setState(() {});
          },
        ),
        const SizedBox(height: 14),

        // ENLARGED MONITORING CARD
        MonitoringCard(
          voltage: device.voltage,
          power: device.power,
          current: device.current,
        ),
        const SizedBox(height: 18),

        // SUMMARY HARIAN
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Hari Ini',
          valueLeft: '${device.dailyEnergy} kWh',
          titleRight: 'Total Biaya Hari Ini',
          valueRight: 'Rp 64.000',
        ),
        const SizedBox(height: 14),

        const DailyEnergyChart(),
        const SizedBox(height: 18),

        // SUMMARY BULANAN
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Bulan Ini',
          valueLeft: '${device.monthlyEnergy} kWh',
          titleRight: 'Total Biaya Bulan Ini',
          valueRight: 'Rp 180.000',
        ),
        const SizedBox(height: 14),

        MonthlyEnergyChart(data: device.monthlyEnergyHistory),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================
  // TABLET LAYOUT (iPad, Android Tablets)
  // ==========================================
  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeHeader(),
        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Controls & Real-time Gauges
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  DeviceStatusCard(
                    connected: device.isConnected,
                    power: devicePower,
                    onChanged: togglePower,
                  ),
                  const SizedBox(height: 16),

                  TariffCard(
                    tariff: DeviceService.currentTariff,
                    activeDate: DeviceService.tariffActiveDate,
                    onTariffChanged: (value, date, note) {
                      DeviceService.updateTariff(value, date, note);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  MonitoringCard(
                    voltage: device.voltage,
                    power: device.power,
                    current: device.current,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),

            // Right Column: Energy Charts & Analytics
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Hari Ini',
                    valueLeft: '${device.dailyEnergy} kWh',
                    titleRight: 'Total Biaya Hari Ini',
                    valueRight: 'Rp 64.000',
                  ),
                  const SizedBox(height: 16),

                  const DailyEnergyChart(),
                  const SizedBox(height: 16),

                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Bulan Ini',
                    valueLeft: '${device.monthlyEnergy} kWh',
                    titleRight: 'Total Biaya Bulan Ini',
                    valueRight: 'Rp 180.000',
                  ),
                  const SizedBox(height: 16),

                  MonthlyEnergyChart(data: device.monthlyEnergyHistory),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff071426),
        border: Border(
          top: BorderSide(color: Color(0xff00D9A6), width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Home Icon (Active)
              IconButton(
                icon: const Icon(
                  Icons.home_rounded,
                  color: Color(0xffffc400),
                  size: 28,
                ),
                onPressed: () {},
              ),
              // Energy Icon
              IconButton(
                icon: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white54,
                  size: 28,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EnergyScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}