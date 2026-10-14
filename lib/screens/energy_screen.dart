import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../models/device_data.dart';
import '../services/device_service.dart';
import '../utils/responsive.dart';
import '../widgets/energy_analysis_summary.dart';
import '../widgets/monthly_energy_chart.dart';
import '../widgets/monthly_cost_chart.dart';

class EnergyScreen extends StatefulWidget {
  const EnergyScreen({super.key});

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends State<EnergyScreen> {
  final DeviceService deviceService = DeviceService();

  DeviceData? device;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadDevice();
  }

  Future<void> loadDevice() async {
    final result = await deviceService.connectDevice();
    setState(() {
      device = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xff071426),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xff00D9A6)),
        ),
      );
    }

    if (device == null || !device!.isConnected) {
      return const Scaffold(
        backgroundColor: Color(0xff071426),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.white54, size: 60),
                SizedBox(height: 20),
                Text(
                  'Perangkat belum terhubung',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Hubungkan Smart Meter\nuntuk melihat analisis energi',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isWide = !Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xff071426),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 1050,
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 16,
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
  // MOBILE LAYOUT (Matches screenshot exactly)
  // ==========================================
  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 18),

        // SUMMARY CARDS (Total Pemakaian, Rata-rata, Total Biaya)
        EnergyAnalysisSummary(
          yearlyEnergy: device!.yearlyEnergy,
          averageEnergy: device!.yearlyEnergy / 12,
          yearlyCost: 654000,
        ),
        const SizedBox(height: 18),

        // PEMAKAIAN ENERGI BULANAN (Bar Chart)
        MonthlyEnergyChart(data: device!.monthlyEnergyHistory),
        const SizedBox(height: 18),

        // PERBANDINGAN BIAYA BULANAN (Bar Chart)
        MonthlyCostChart(data: device!.monthlyCostHistory),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==========================================
  // TABLET LAYOUT (Spacious 2 columns on wide screens)
  // ==========================================
  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 22),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Summary Cards
            Expanded(
              flex: 4,
              child: EnergyAnalysisSummary(
                yearlyEnergy: device!.yearlyEnergy,
                averageEnergy: device!.yearlyEnergy / 12,
                yearlyCost: 654000,
              ),
            ),
            const SizedBox(width: 20),

            // Right Column: Charts
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  MonthlyEnergyChart(data: device!.monthlyEnergyHistory),
                  const SizedBox(height: 18),
                  MonthlyCostChart(data: device!.monthlyCostHistory),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================
  // HEADER ROW (SIMETRI Logo + Tahun 2026 Pill + Titles)
  // ==========================================
  Widget _buildHeaderRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row with SIMETRI Logo and Year Pill
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/simetri_logo.png',
              width: 140,
              fit: BoxFit.contain,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white60, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    color: Colors.white,
                    size: 13,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Tahun 2026',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Screen title and subtitle
        const Text(
          'Analisis Energi',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Lihat penggunaan listrik selama 1 tahun.',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // BOTTOM NAVIGATION BAR (Matches screenshot icons)
  // ==========================================
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
              // Home Icon
              IconButton(
                icon: const Icon(
                  Icons.home_outlined,
                  color: Colors.white54,
                  size: 28,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
              ),
              // Energy Icon (Active Gold Bolt)
              IconButton(
                icon: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xffffc400),
                  size: 28,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}