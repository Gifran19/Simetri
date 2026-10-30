import 'dart:async';
import 'package:flutter/material.dart';

import 'home_screen.dart';
import '../models/yearly_energy_data.dart';
import '../services/device_service.dart';
import '../services/energy_database_service.dart';
import '../services/live_status.dart';
import '../utils/responsive.dart';
import '../widgets/energy_analysis_summary.dart';
import '../widgets/monthly_energy_chart.dart';
import '../widgets/monthly_cost_chart.dart';

class EnergyScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateToTab;
  final bool isInsideShell;

  const EnergyScreen({
    super.key,
    this.onNavigateToTab,
    this.isInsideShell = false,
  });

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends State<EnergyScreen> {
  final EnergyDatabaseService _dbService = EnergyDatabaseService();

  List<int> _availableYears = kDemoMode ? [2026, 2025, 2024] : [DateTime.now().year];
  int _selectedYear = DateTime.now().year;
  late YearlyEnergyData _yearData;
  double _monthlyBudget = 300000;
  bool _isConnected = false;

  bool _loadingData = false;
  String? _fetchError;
  StreamSubscription<YearlyEnergyData>? _yearlySub;

  @override
  void initState() {
    super.initState();
    _yearData = YearlyEnergyData.empty(_selectedYear);
    _loadAvailableYears();
    DeviceService.connectionNotifier.addListener(_onConnectionChanged);
    DeviceService.budgetNotifier.addListener(_onBudgetChanged);
    DeviceService.deviceIdNotifier.addListener(_onDeviceIdChanged);
  }

  @override
  void dispose() {
    _yearlySub?.cancel();
    DeviceService.connectionNotifier.removeListener(_onConnectionChanged);
    DeviceService.budgetNotifier.removeListener(_onBudgetChanged);
    DeviceService.deviceIdNotifier.removeListener(_onDeviceIdChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    final connected = DeviceService.connectionNotifier.value;
    if (_isConnected != connected) {
      if (connected) {
        _loadAvailableYears();
      } else {
        _yearlySub?.cancel();
        _yearlySub = null;
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _yearData = YearlyEnergyData.empty(_selectedYear);
          _loadingData = false;
          _fetchError = null;
        });
      }
    }
  }

  void _onDeviceIdChanged() {
    if (!mounted) return;
    _loadAvailableYears();
  }

  void _onBudgetChanged() {
    final newBudget = DeviceService.budgetNotifier.value;
    if (_monthlyBudget != newBudget && mounted) {
      setState(() {
        _monthlyBudget = newBudget;
      });
    }
  }

  // --------------------------------------------------------
  // Muat status koneksi dan daftar tahun dari Firebase
  // --------------------------------------------------------
  Future<void> _loadAvailableYears() async {
    final connected = await DeviceService.isDeviceConnected();
    final budget = await DeviceService.getMonthlyBudget();
    final currentDevId = DeviceService.deviceIdNotifier.value;

    if (!connected) {
      _yearlySub?.cancel();
      _yearlySub = null;
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _monthlyBudget = budget;
        _yearData = YearlyEnergyData.empty(_selectedYear);
        _loadingData = false;
        _fetchError = null;
      });
      return;
    }

    final years = await _dbService.fetchAvailableYears(currentDevId);
    if (!mounted) return;
    setState(() {
      _isConnected = true;
      _availableYears = years;
      _monthlyBudget = budget;
      if (!years.contains(_selectedYear) && years.isNotEmpty) {
        _selectedYear = years.first;
      }
    });
    _loadYearData(_selectedYear);
  }

  // --------------------------------------------------------
  // Muat data energi untuk tahun yang dipilih dan dengarkan stream real-time
  // --------------------------------------------------------
  Future<void> _loadYearData(int year) async {
    final connected = await DeviceService.isDeviceConnected();
    if (!connected) {
      _yearlySub?.cancel();
      _yearlySub = null;
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _yearData = YearlyEnergyData.empty(year);
        _loadingData = false;
        _fetchError = null;
      });
      return;
    }

    _yearlySub?.cancel();
    _yearlySub = null;

    final currentDevId = DeviceService.deviceIdNotifier.value;

    setState(() {
      _loadingData = true;
      _fetchError = null;
    });

    // 1. Initial direct fetch untuk respons instan
    try {
      final initialData = await _dbService.fetchYearlyData(year, currentDevId);
      if (mounted) {
        setState(() {
          _isConnected = true;
          _yearData = initialData;
          _loadingData = false;
          _fetchError = _dbService.lastFetchError;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingData = false;
          _fetchError = e.toString();
        });
      }
    }

    // 2. Real-time stream subscription agar halaman otomatis update saat data masuk
    _yearlySub = _dbService.streamYearlyData(year, currentDevId).listen(
      (streamData) {
        if (!mounted) return;
        setState(() {
          _isConnected = true;
          _yearData = streamData;
          _loadingData = false;
          _fetchError = null;
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _loadingData = false;
          _fetchError = err.toString();
        });
      },
    );
  }

  // --------------------------------------------------------
  // Tampilkan bottom sheet pemilih tahun
  // --------------------------------------------------------
  Future<void> _showYearPicker() async {
    if (_availableYears.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Color(0xff0D1F3C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pilih Tahun',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Data energi tersedia untuk tahun berikut:',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ..._availableYears.map((year) {
                    final isSelected = year == _selectedYear;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        if (year != _selectedYear) {
                          setState(() => _selectedYear = year);
                          _loadYearData(year);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                              : const Color(0xff10233F),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xff00D9A6).withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                              color: isSelected ? const Color(0xff00D9A6) : Colors.white54,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Tahun $year',
                              style: TextStyle(
                                color: isSelected ? const Color(0xff00D9A6) : Colors.white,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xff00D9A6),
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------
  // Dialog ubah target anggaran bulanan
  // --------------------------------------------------------
  Future<void> _showBudgetDialog() async {
    final controller = TextEditingController(text: _monthlyBudget.toInt().toString());

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xff0D1F3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: Color(0xff00D9A6), size: 20),
              SizedBox(width: 8),
              Text('Target Anggaran Bulanan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tentukan batas target pengeluaran listrik per bulan untuk mengontrol konsumsi daya dan memantau proyeksi tagihan.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  prefixText: 'Rp  ',
                  prefixStyle: const TextStyle(color: Color(0xff00D9A6), fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: const Color(0xff071426),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(controller.text);
                if (val != null && val > 0) {
                  await DeviceService.saveMonthlyBudget(val);
                  if (mounted) {
                    setState(() => _monthlyBudget = val);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff00D9A6),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xff071426),
      bottomNavigationBar: widget.isInsideShell ? null : _buildBottomNav(),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 1050,
          padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: isWide ? 20 : 12),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: isWide ? _buildTabletLayout() : _buildMobileLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded, color: Colors.amber, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Meter Belum Terhubung',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Data histori & grafik pemakaian energi tahunan akan mulai terekam setelah perangkat IoT terhubung.',
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              if (widget.onNavigateToTab != null) {
                widget.onNavigateToTab!(0);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff00D9A6),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Hubungkan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    final err = _fetchError ?? '';
    final isPermissionDenied = err.toLowerCase().contains('permission') ||
        err.toLowerCase().contains('denied') ||
        err.toLowerCase().contains('izin');

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff181C32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPermissionDenied ? Colors.redAccent.withValues(alpha: 0.7) : Colors.amber.withValues(alpha: 0.7),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPermissionDenied
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPermissionDenied ? Icons.lock_outline_rounded : Icons.warning_amber_rounded,
              color: isPermissionDenied ? Colors.redAccent : Colors.amber,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPermissionDenied ? 'Izin Akses Ditolak (Permission Denied)' : 'Gagal Memuat Data Histori',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  isPermissionDenied
                      ? 'Akun Anda belum terdaftar sebagai member aktif perangkat ini di Firebase Realtime Database.'
                      : err,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => _loadAvailableYears(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff00D9A6),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Coba Lagi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MOBILE LAYOUT
  // ==========================================
  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 18),

        if (!_isConnected) _buildDisconnectedBanner(),
        if (_isConnected && _fetchError != null) _buildErrorBanner(),

        // SUMMARY CARDS
        if (_loadingData)
          _buildLoadingCard()
        else
          EnergyAnalysisSummary(
            year: _yearData.year,
            yearlyEnergy: _yearData.totalEnergy,
            averageEnergy: _yearData.averageMonthlyEnergy,
            yearlyCost: _yearData.totalCost,
            energyChangePercent: _yearData.energyChangePercent,
            costChangePercent: _yearData.costChangePercent,
          ),

        const SizedBox(height: 18),

        // PROYEKSI AKHIR BULAN & KUOTA ANGGARAN
        _buildProjectionAndBudgetCard(),

        const SizedBox(height: 18),

        // PEMAKAIAN ENERGI BULANAN
        if (_loadingData)
          _buildLoadingCard(height: 300)
        else
          MonthlyEnergyChart(
            data: _yearData.monthlyEnergy,
            isConnected: _isConnected,
          ),

        const SizedBox(height: 18),

        // PERBANDINGAN BIAYA BULANAN
        if (_loadingData)
          _buildLoadingCard(height: 300)
        else
          MonthlyCostChart(data: _yearData.monthlyCost),

        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================
  // TABLET LAYOUT
  // ==========================================
  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 22),

        if (!_isConnected) _buildDisconnectedBanner(),
        if (_isConnected && _fetchError != null) _buildErrorBanner(),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: _loadingData
                  ? _buildLoadingCard(height: 200)
                  : EnergyAnalysisSummary(
                      year: _yearData.year,
                      yearlyEnergy: _yearData.totalEnergy,
                      averageEnergy: _yearData.averageMonthlyEnergy,
                      yearlyCost: _yearData.totalCost,
                      energyChangePercent: _yearData.energyChangePercent,
                      costChangePercent: _yearData.costChangePercent,
                    ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 6,
              child: _loadingData
                  ? Column(
                      children: [
                        _buildLoadingCard(height: 300),
                        const SizedBox(height: 18),
                        _buildLoadingCard(height: 300),
                      ],
                    )
                  : Column(
                      children: [
                        MonthlyEnergyChart(
                          data: _yearData.monthlyEnergy,
                          isConnected: _isConnected,
                        ),
                        const SizedBox(height: 18),
                        MonthlyCostChart(data: _yearData.monthlyCost),
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
  // HEADER ROW — Logo SIMETRI + Year Selector (SATU, di kanan atas)
  // ==========================================
  Widget _buildHeaderRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('assets/simetri_logo.png', width: 140, fit: BoxFit.contain),

            // ── Year Selector tunggal sejajar logo ──
            GestureDetector(
              onTap: _showYearPicker,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xff00D9A6).withValues(alpha: 0.5),
                    width: 1,
                  ),
                  color: const Color(0xff00D9A6).withValues(alpha: 0.08),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined, color: Color(0xff00D9A6), size: 13),
                    const SizedBox(width: 6),
                    Text(
                      'Tahun $_selectedYear',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xff00D9A6),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

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
        Text(
          'Ringkasan penggunaan listrik tahun $_selectedYear.',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }

  // ==========================================
  // LOADING CARD
  // ==========================================
  Widget _buildLoadingCard({double height = 160}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xff00D9A6), strokeWidth: 2),
      ),
    );
  }

  // ==========================================
  // ==========================================
  // KARTU TARGET ANGGARAN BULANAN
  // ==========================================
  Widget _buildProjectionAndBudgetCard() {
    final now = DateTime.now();
    final currentMonthIndex = (now.month - 1).clamp(0, 11);

    double currentMonthCost = 0.0;
    if (_isConnected && _yearData.monthlyCost.length > currentMonthIndex) {
      currentMonthCost = _yearData.monthlyCost[currentMonthIndex];
    }

    final budgetLimit = _monthlyBudget > 0 ? _monthlyBudget : 300000.0;
    final budgetUsedPercent = _isConnected ? (currentMonthCost / budgetLimit) * 100 : 0.0;
    final clampedBudgetRatio = (budgetUsedPercent / 100).clamp(0.0, 1.0);

    Color budgetColor = _isConnected ? const Color(0xff00D9A6) : Colors.white38;
    String budgetStatus = _isConnected ? 'Aman Dalam Target Anggaran' : 'Smart Meter Belum Terhubung';
    if (_isConnected) {
      if (budgetUsedPercent >= 100) {
        budgetColor = Colors.redAccent;
        budgetStatus = 'Melebihi Kuota Anggaran!';
      } else if (budgetUsedPercent >= 75) {
        budgetColor = Colors.orangeAccent;
        budgetStatus = 'Mendekati Batas Anggaran';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xff00D9A6), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Target Anggaran Bulanan',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, color: budgetColor, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  budgetStatus,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: budgetColor, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _showBudgetDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xff00D9A6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rp ${budgetLimit.toInt()}',
                        style: const TextStyle(
                          color: Color(0xff00D9A6),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_rounded, color: Color(0xff00D9A6), size: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: clampedBudgetRatio,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(budgetColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terpakai: Rp ${currentMonthCost.toInt()}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                '${budgetUsedPercent.toStringAsFixed(1)}%',
                style: TextStyle(color: budgetColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff071426),
        border: Border(top: BorderSide(color: Color(0xff00D9A6), width: 1.0)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.home_outlined, color: Colors.white54, size: 28),
                onPressed: () {
                  if (widget.onNavigateToTab != null) {
                    widget.onNavigateToTab!(0);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.bolt_rounded, color: Color(0xffffc400), size: 28),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
