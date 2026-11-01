import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/energy_database_service.dart';

class DailyEnergyChart extends StatefulWidget {
  final List<double>? data;
  final bool isConnected;
  final String? deviceId;
  final DateTime? initialDate;

  const DailyEnergyChart({
    super.key,
    this.data,
    this.isConnected = true,
    this.deviceId,
    this.initialDate,
  });

  @override
  State<DailyEnergyChart> createState() => _DailyEnergyChartState();
}

class _DailyEnergyChartState extends State<DailyEnergyChart> {
  static const List<String> _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  late DateTime _selectedDate;
  WeeklyHistoryResult? _historyResult;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    // Muat detail histori untuk minggu terpilih jika widget data belum mencakupnya
    if (widget.initialDate != null || widget.data == null || widget.data!.every((e) => e <= 0.00001)) {
      _loadWeekData(_selectedDate);
    }
  }

  @override
  void didUpdateWidget(covariant DailyEnergyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _loadWeekData(_selectedDate);
    }
  }

  bool get _isCurrentWeek {
    return EnergyDatabaseService.isSameWeek(_selectedDate, DateTime.now());
  }

  Future<void> _loadWeekData(DateTime targetDate) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await EnergyDatabaseService().fetchWeeklyHistoryDetails(
        deviceId: widget.deviceId,
        referenceDate: targetDate,
      );
      if (!mounted) return;
      setState(() {
        _historyResult = result;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _previousWeek() {
    final prev = _selectedDate.subtract(const Duration(days: 7));
    setState(() {
      _selectedDate = prev;
    });
    _loadWeekData(prev);
  }

  void _nextWeek() {
    if (_isCurrentWeek) return;
    final next = _selectedDate.add(const Duration(days: 7));
    setState(() {
      _selectedDate = next;
    });
    _loadWeekData(next);
  }

  void _resetToCurrentWeek() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = now;
    });
    _loadWeekData(now);
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _selectedDate.isAfter(now) ? now : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: now,
      helpText: 'PILIH TANGGAL HISTORI',
      cancelText: 'BATAL',
      confirmText: 'PILIH',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xff00D9A6),
              onPrimary: Colors.black,
              surface: Color(0xff0D1F3C),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xff0D1F3C),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadWeekData(picked);
    }
  }

  String _formatWeekRange(DateTime mon, DateTime sun) {
    if (mon.year != sun.year) {
      return '${mon.day} ${_months[mon.month - 1]} ${mon.year} – ${sun.day} ${_months[sun.month - 1]} ${sun.year}';
    } else if (mon.month != sun.month) {
      return '${mon.day} ${_months[mon.month - 1]} – ${sun.day} ${_months[sun.month - 1]} ${sun.year}';
    } else {
      return '${mon.day} – ${sun.day} ${_months[mon.month - 1]} ${sun.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final monday = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
        .subtract(Duration(days: _selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    final sunday = weekDays[6];
    final now = DateTime.now();

    // Tentukan data energi dan biaya yang akan digambar
    final List<double> chartData;
    final List<double> costs;

    if (_historyResult != null && !_historyResult!.isEmpty) {
      chartData = _historyResult!.energy;
      costs = _historyResult!.costs;
    } else if (_isCurrentWeek && widget.data != null && widget.data!.isNotEmpty) {
      chartData = widget.data!;
      costs = _historyResult?.costs ?? List.filled(7, 0.0);
    } else {
      chartData = _historyResult?.energy ?? widget.data ?? List.filled(7, 0.0);
      costs = _historyResult?.costs ?? List.filled(7, 0.0);
    }

    final bool isEmpty = chartData.isEmpty || chartData.every((e) => e <= 0.00001);
    final displayData = isEmpty ? List<double>.filled(7, 0.0) : chartData;
    final maxVal = isEmpty ? 0.0 : displayData.reduce((a, b) => a > b ? a : b);

    // Hitung maxY dan interval dinamis dengan headroom yang cukup agar bar tidak mentok atas
    final double maxY;
    final double interval;
    if (isEmpty || maxVal <= 0.0) {
      maxY = 1.0;
      interval = 0.2;
    } else if (maxVal <= 0.005) {
      maxY = 0.008;
      interval = 0.002;
    } else if (maxVal <= 0.01) {
      maxY = 0.016;
      interval = 0.004;
    } else if (maxVal <= 0.02) {
      maxY = 0.030;
      interval = 0.010;
    } else if (maxVal <= 0.05) {
      maxY = 0.080;
      interval = 0.020;
    } else if (maxVal <= 0.1) {
      maxY = 0.150;
      interval = 0.050;
    } else if (maxVal <= 0.5) {
      maxY = 0.8;
      interval = 0.2;
    } else if (maxVal <= 1.0) {
      maxY = 1.5;
      interval = 0.5;
    } else if (maxVal <= 5.0) {
      maxY = 8.0;
      interval = 2.0;
    } else {
      maxY = ((maxVal * 1.3 / 2).ceil() * 2).toDouble();
      interval = (maxY / 4).ceilToDouble();
    }

    final canGoForward = !_isCurrentWeek;
    final canGoBackward = monday.isAfter(DateTime(2024, 1, 1));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Judul, Rentang Tanggal, & Tombol Kalender
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pemakaian Energi Harian',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatWeekRange(monday, sunday),
                      style: const TextStyle(color: Color(0xff00D9A6), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _pickDate(context),
                icon: const Icon(Icons.calendar_month_rounded, color: Color(0xff00D9A6), size: 22),
                tooltip: 'Pilih Tanggal Kalender',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xff00D9A6).withValues(alpha: 0.12),
                  padding: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Navigasi Minggu: Minggu Lalu | Chip Status | Minggu Depan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff0A192F).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tombol Minggu Lalu
                InkWell(
                  onTap: canGoBackward ? _previousWeek : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_left_rounded,
                          color: canGoBackward ? const Color(0xff00D9A6) : Colors.white24,
                          size: 18,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Minggu Lalu',
                          style: TextStyle(
                            color: canGoBackward ? Colors.white70 : Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Indikator / Tombol Reset ke Minggu Ini
                if (!_isCurrentWeek)
                  InkWell(
                    onTap: _resetToCurrentWeek,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay_rounded, color: Color(0xff00D9A6), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Kembali ke Minggu Ini',
                            style: TextStyle(
                              color: Color(0xff00D9A6),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xff00D9A6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Minggu Ini',
                      style: TextStyle(color: Color(0xff00D9A6), fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),

                // Tombol Minggu Depan
                InkWell(
                  onTap: canGoForward ? _nextWeek : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Minggu Depan',
                          style: TextStyle(
                            color: canGoForward ? Colors.white70 : Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: canGoForward ? const Color(0xff00D9A6) : Colors.white24,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Baris Unit dan Indikator Loading
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('kWh', style: TextStyle(color: Colors.white70, fontSize: 11)),
              if (_isLoading)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff00D9A6)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Chart
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      minY: 0,
                      alignment: BarChartAlignment.spaceAround,
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (value) =>
                            FlLine(color: const Color(0xff2A4365), strokeWidth: 1.0),
                      ),
                      barTouchData: BarTouchData(
                        enabled: !isEmpty,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (group.x < 0 || group.x >= _days.length || group.x >= weekDays.length) {
                              return null;
                            }
                            final dayName = _days[group.x];
                            final d = weekDays[group.x];
                            final dateStr = '$dayName, ${d.day} ${_months[d.month - 1]} ${d.year}';
                            final kwhStr = '${rod.toY.toStringAsFixed(3)} kWh';
                            final cost = (group.x < costs.length) ? costs[group.x] : 0.0;
                            final costStr = cost > 0
                                ? '\nRp ${NumberFormat('#,###', 'id_ID').format(cost.round())}'
                                : '';
                            return BarTooltipItem(
                              '$dateStr\n$kwhStr$costStr',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: interval,
                            reservedSize: maxY < 1.0 ? 44 : 32,
                            getTitlesWidget: (value, meta) {
                              if (value < 0 || value > maxY + (interval * 0.05)) {
                                return const SizedBox();
                              }
                              final String labelText;
                              if (maxY <= 0.01) {
                                labelText = value.toStringAsFixed(3);
                              } else if (maxY <= 0.1) {
                                labelText = value.toStringAsFixed(3);
                              } else if (maxY <= 1.0) {
                                labelText = value.toStringAsFixed(1);
                              } else {
                                labelText = value.toInt().toString();
                              }
                              return Text(
                                labelText,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= _days.length || idx >= weekDays.length) {
                                return const SizedBox();
                              }
                              final d = weekDays[idx];
                              final isToday = _isCurrentWeek &&
                                  d.day == now.day &&
                                  d.month == now.month &&
                                  d.year == now.year;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _days[idx],
                                      style: TextStyle(
                                        color: isToday ? const Color(0xff00D9A6) : Colors.white70,
                                        fontSize: 10,
                                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      '${d.day}',
                                      style: TextStyle(
                                        color: isToday ? const Color(0xff00D9A6) : Colors.white38,
                                        fontSize: 9,
                                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: displayData.asMap().entries.map((item) {
                        return BarChartGroupData(
                          x: item.key,
                          barRods: [
                            BarChartRodData(
                              toY: item.value,
                              width: 16,
                              borderRadius: BorderRadius.circular(5),
                              gradient: widget.isConnected && item.value > 0
                                  ? const LinearGradient(
                                      colors: [Color(0xff00D9A6), Color(0xff007BFF)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    )
                                  : const LinearGradient(
                                      colors: [Colors.white10, Colors.white12],
                                    ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (!widget.isConnected || isEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xff071426).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.query_stats_rounded, color: Colors.white38, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            widget.isConnected ? 'Belum ada rekaman histori' : 'Grafik harian belum tersedia',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isConnected
                                ? (_isCurrentWeek
                                    ? 'Data histori harian akan tercatat otomatis saat tersimpan di database.'
                                    : 'Tidak ada catatan pemakaian energi pada minggu ini.')
                                : 'Hubungkan perangkat IoT untuk memulai pencatatan.',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
