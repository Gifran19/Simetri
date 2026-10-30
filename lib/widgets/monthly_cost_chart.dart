import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class MonthlyCostChart extends StatelessWidget {
  final List<double> data;

  const MonthlyCostChart({super.key, required this.data});

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agt',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = data.isEmpty || data.every((e) => e <= 0.0);
    final double maxCost = isEmpty ? 0.0 : data.reduce((a, b) => a > b ? a : b);

    // Jika biaya tahunan sudah mencapai ribuan (>= 1.000), gunakan skala 'K' (ribu)
    // Jika biaya masih kecil (misal Rp 3), gunakan skala Rupiah langsung tanpa membagi 1000
    final bool useRibuan = maxCost >= 1000.0;
    final normalizedData = data.map((val) => useRibuan ? val / 1000.0 : val).toList();

    // Hitung maxY dan interval dinamis
    final double maxY;
    final double interval;
    if (isEmpty || maxCost <= 0.0) {
      maxY = 100.0;
      interval = 20.0;
    } else if (!useRibuan) {
      if (maxCost <= 5.0) {
        maxY = 5.0;
        interval = 1.0;
      } else if (maxCost <= 10.0) {
        maxY = 10.0;
        interval = 2.0;
      } else if (maxCost <= 50.0) {
        maxY = 50.0;
        interval = 10.0;
      } else if (maxCost <= 100.0) {
        maxY = 100.0;
        interval = 20.0;
      } else if (maxCost <= 500.0) {
        maxY = 500.0;
        interval = 100.0;
      } else {
        maxY = 1000.0;
        interval = 200.0;
      }
    } else {
      final normMax = maxCost / 1000.0;
      maxY = normMax > 150 ? ((normMax / 20).ceil() * 20 + 20).toDouble() : 180.0;
      interval = maxY > 200 ? 50.0 : 20.0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Perbandingan Biaya Bulanan',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Belum ada data',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            useRibuan ? 'Rp (dalam ribuan)' : 'Rupiah (Rp)',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 12),

          // Bar Chart with ClipRect to prevent bar bleeding
          SizedBox(
            height: 240,
            child: ClipRect(
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
                        final monthName = (group.x >= 0 && group.x < _months.length)
                            ? _months[group.x]
                            : '';
                        // Ambil biaya riil dari data asli
                        final actualCost = (group.x >= 0 && group.x < data.length)
                            ? data[group.x].round()
                            : (rod.toY * (useRibuan ? 1000 : 1)).round();
                        final formatted = NumberFormat('#,###', 'id_ID').format(actualCost);
                        return BarTooltipItem(
                          '$monthName\nRp $formatted',
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
                        reservedSize: useRibuan ? 38 : 34,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value > maxY + (interval * 0.1)) {
                            return const SizedBox();
                          }
                          final valInt = value.toInt();
                          final text = useRibuan
                              ? (valInt == 0 ? '0' : '${valInt}K')
                              : valInt.toString();
                          return Text(
                            text,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= _months.length) {
                            return const SizedBox();
                          }
                          return Text(
                            _months[index],
                            style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: normalizedData.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value,
                          width: 11,
                          borderRadius: BorderRadius.circular(4),
                          gradient: !isEmpty && entry.value > 0
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
          ),
        ],
      ),
    );
  }
}
