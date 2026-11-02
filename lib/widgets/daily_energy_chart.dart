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

  Future<void> _pickDate() async {
    final pickedMonday = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => WeekRangePickerDialog(
        initialDate: _selectedDate,
      ),
    );

    if (pickedMonday == null || !mounted) return;

    setState(() {
      _selectedDate = pickedMonday;
    });
    _loadWeekData(pickedMonday);

    final sunday = pickedMonday.add(const Duration(days: 6));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xff00D9A6), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Menampilkan 7 hari: ${_formatWeekRange(pickedMonday, sunday)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xff10233F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xff00D9A6), width: 1),
        ),
      ),
    );
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

    // Hitung maxY dan interval dinamis dengan rentang standar rumah tangga (0 - 5.0 kWh)
    final double maxY;
    final double interval;
    if (isEmpty || maxVal <= 5.0) {
      maxY = 5.0;
      interval = 1.0;
    } else if (maxVal <= 10.0) {
      maxY = 10.0;
      interval = 2.0;
    } else if (maxVal <= 20.0) {
      maxY = 20.0;
      interval = 5.0;
    } else if (maxVal <= 50.0) {
      maxY = 50.0;
      interval = 10.0;
    } else {
      maxY = ((maxVal * 1.25 / 5).ceil() * 5).toDouble();
      interval = (maxY / 5).ceilToDouble();
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
          // Header Row: Judul, Rentang Tanggal (7 Hari), & Tombol Kalender
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _formatWeekRange(monday, sunday),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xff00D9A6), fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xff00D9A6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '7 Hari',
                            style: TextStyle(color: Color(0xff00D9A6), fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_rounded, color: Color(0xff00D9A6), size: 22),
                tooltip: 'Pilih Rentang 7 Hari (Senin – Minggu)',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xff00D9A6).withValues(alpha: 0.12),
                  padding: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Navigasi Minggu: Minggu Lalu | Chip Status | Minggu Depan (Anti-Overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff0A192F).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                // Tombol Minggu Lalu (Terikat ke sisi kiri)
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: canGoBackward ? _previousWeek : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chevron_left_rounded,
                              color: canGoBackward ? const Color(0xff00D9A6) : Colors.white24,
                              size: 18,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                'Minggu Lalu',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: canGoBackward ? Colors.white70 : Colors.white24,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Indikator / Tombol Reset ke Minggu Ini (Di tengah)
                if (!_isCurrentWeek)
                  InkWell(
                    onTap: _resetToCurrentWeek,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay_rounded, color: Color(0xff00D9A6), size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Minggu Ini',
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xff00D9A6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Minggu Ini',
                      style: TextStyle(color: Color(0xff00D9A6), fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),

                // Tombol Minggu Depan (Terikat ke sisi kanan)
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: canGoForward ? _nextWeek : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Minggu Depan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: canGoForward ? Colors.white70 : Colors.white24,
                                  fontSize: 11,
                                ),
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

/// Dialog khusus pemilihan rentang 7 hari (Senin s/d Minggu).
/// Memastikan grafik histori harian selalu menerima dan menyajikan 7 hari utuh secara konsisten.
class WeekRangePickerDialog extends StatefulWidget {
  final DateTime initialDate;

  const WeekRangePickerDialog({
    super.key,
    required this.initialDate,
  });

  @override
  State<WeekRangePickerDialog> createState() => _WeekRangePickerDialogState();
}

class _WeekRangePickerDialogState extends State<WeekRangePickerDialog> {
  static const List<String> _dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const List<String> _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember'
  ];

  late DateTime _viewMonth;
  late DateTime _selectedMonday;
  late final DateTime _today;
  late final DateTime _currentWeekMonday;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _currentWeekMonday = _today.subtract(Duration(days: _today.weekday - 1));

    final initClean = DateTime(widget.initialDate.year, widget.initialDate.month, widget.initialDate.day);
    _selectedMonday = initClean.subtract(Duration(days: initClean.weekday - 1));
    if (_selectedMonday.isAfter(_currentWeekMonday)) {
      _selectedMonday = _currentWeekMonday;
    }
    _viewMonth = DateTime(_selectedMonday.year, _selectedMonday.month, 1);
  }

  DateTime _getSunday(DateTime monday) {
    return monday.add(const Duration(days: 6));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    final next = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    final currentMonthStart = DateTime(_today.year, _today.month, 1);
    if (!next.isAfter(currentMonthStart)) {
      setState(() {
        _viewMonth = next;
      });
    }
  }

  void _selectPresetWeek(int weeksAgo) {
    final target = _currentWeekMonday.subtract(Duration(days: 7 * weeksAgo));
    setState(() {
      _selectedMonday = target;
      _viewMonth = DateTime(target.year, target.month, 1);
    });
  }

  void _selectWeek(DateTime monday) {
    if (monday.isAfter(_currentWeekMonday)) return;
    setState(() {
      _selectedMonday = monday;
    });
  }

  String _formatWeekTitle(DateTime mon, DateTime sun) {
    final monMonth = _monthNames[mon.month - 1];
    final sunMonth = _monthNames[sun.month - 1];
    if (mon.year != sun.year) {
      return '${mon.day} $monMonth ${mon.year} – ${sun.day} $sunMonth ${sun.year}';
    } else if (mon.month != sun.month) {
      return '${mon.day} $monMonth – ${sun.day} $sunMonth ${sun.year}';
    } else {
      return '${mon.day} – ${sun.day} $monMonth ${sun.year}';
    }
  }

  List<List<DateTime>> _buildMonthWeeks() {
    final firstDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final lastDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);

    var currentDay = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
    final lastSunday = lastDayOfMonth.add(Duration(days: 7 - lastDayOfMonth.weekday));

    final List<List<DateTime>> weeks = [];
    while (!currentDay.isAfter(lastSunday)) {
      final List<DateTime> week = [];
      for (int i = 0; i < 7; i++) {
        week.add(currentDay);
        currentDay = currentDay.add(const Duration(days: 1));
      }
      weeks.add(week);
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final sunday = _getSunday(_selectedMonday);
    final weeks = _buildMonthWeeks();
    final currentMonthStart = DateTime(_today.year, _today.month, 1);
    final canGoNextMonth = _viewMonth.isBefore(currentMonthStart);
    final canGoPrevMonth = _viewMonth.isAfter(DateTime(2024, 1, 1));

    return Dialog(
      backgroundColor: const Color(0xff0E203C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Dialog
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.date_range_rounded, color: Color(0xff00D9A6), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilih Rentang 7 Hari',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Senin sampai Minggu (1 Minggu Penuh)',
                          style: TextStyle(color: Color(0xff00D9A6), fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Card Rentang Terpilih
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xff0A192F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available_rounded, color: Color(0xff00D9A6), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RENTANG 7 HARI TERPILIH',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatWeekTitle(_selectedMonday, sunday),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '7 Hari',
                        style: TextStyle(
                          color: Color(0xff00D9A6),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Shortcut Presets
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPresetChip('Minggu Ini', 0),
                    const SizedBox(width: 6),
                    _buildPresetChip('1 Minggu Lalu', 1),
                    const SizedBox(width: 6),
                    _buildPresetChip('2 Minggu Lalu', 2),
                    const SizedBox(width: 6),
                    _buildPresetChip('3 Minggu Lalu', 3),
                    const SizedBox(width: 6),
                    _buildPresetChip('4 Minggu Lalu', 4),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Calendar Month Navigation
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                      onPressed: canGoPrevMonth ? _prevMonth : null,
                      tooltip: 'Bulan Sebelumnya',
                    ),
                    Text(
                      '${_monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        color: canGoNextMonth ? Colors.white70 : Colors.white24,
                      ),
                      onPressed: canGoNextMonth ? _nextMonth : null,
                      tooltip: 'Bulan Berikutnya',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Day of Week Header (Senin s/d Minggu)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: _dayNames.map((day) {
                    final isWeekend = day == 'Sab' || day == 'Min';
                    return Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            color: isWeekend ? const Color(0xff00D9A6).withValues(alpha: 0.8) : Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 6),

              // Month Weeks Grid
              Column(
                children: weeks.map((week) {
                  final weekMonday = week[0];
                  final isSelected = _isSameDay(weekMonday, _selectedMonday);
                  final isFutureWeek = weekMonday.isAfter(_currentWeekMonday);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: InkWell(
                      onTap: isFutureWeek ? null : () => _selectWeek(weekMonday),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xff00D9A6).withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? const Color(0xff00D9A6) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: week.map((date) {
                            final isCurrentMonth = date.month == _viewMonth.month;
                            final isFutureDate = date.isAfter(_today);
                            final isToday = _isSameDay(date, _today);

                            final Color textColor;
                            if (isSelected) {
                              textColor = isCurrentMonth
                                  ? const Color(0xff00D9A6)
                                  : const Color(0xff00D9A6).withValues(alpha: 0.5);
                            } else if (isFutureDate) {
                              textColor = Colors.white24;
                            } else if (isCurrentMonth) {
                              textColor = Colors.white;
                            } else {
                              textColor = Colors.white30;
                            }

                            return Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 12,
                                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (isToday)
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        width: 4,
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          color: Color(0xff00D9A6),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(_selectedMonday),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Terapkan (7 Hari)'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff00D9A6),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int weeksAgo) {
    final targetMonday = _currentWeekMonday.subtract(Duration(days: 7 * weeksAgo));
    final isSelected = _isSameDay(targetMonday, _selectedMonday);

    return InkWell(
      onTap: () => _selectPresetWeek(weeksAgo),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xff00D9A6).withValues(alpha: 0.2)
              : const Color(0xff0A192F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xff00D9A6) : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xff00D9A6) : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
