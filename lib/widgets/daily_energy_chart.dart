import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class DailyEnergyChart extends StatelessWidget {
  final List<double>? data;
  final bool isConnected;

  const DailyEnergyChart({
    super.key,
    this.data,
    this.isConnected = true,
  });

  static const List<String> _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    // Nilai valid jika ada minimal satu hari dengan energi > 0.00001
    final bool isEmpty = data == null || data!.isEmpty || data!.every((e) => e <= 0.00001);
    final chartData = isEmpty ? List<double>.filled(7, 0.0) : data!;
    final maxVal = isEmpty ? 0.0 : chartData.reduce((a, b) => a > b ? a : b);

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pemakaian Energi Harian',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              if (!isConnected)
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
          const Text('kWh', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 14),
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
                            final dayName = (group.x >= 0 && group.x < _days.length)
                                ? _days[group.x]
                                : '';
                            return BarTooltipItem(
                              '$dayName\n${rod.toY.toStringAsFixed(3)} kWh',
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
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= _days.length) return const SizedBox();
                              return Text(
                                _days[idx],
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: chartData.asMap().entries.map((item) {
                        return BarChartGroupData(
                          x: item.key,
                          barRods: [
                            BarChartRodData(
                              toY: item.value,
                              width: 16,
                              borderRadius: BorderRadius.circular(5),
                              gradient: isConnected && item.value > 0
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
                if (!isConnected || isEmpty)
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
                            isConnected ? 'Belum ada rekaman histori' : 'Grafik harian belum tersedia',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? 'Data histori harian akan tercatat otomatis saat tersimpan di database.'
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
