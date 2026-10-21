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

  static const List<double> _defaultData = [2.1, 3.5, 1.8, 4.2, 3.1, 5.0, 4.5];
  static const List<String> _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final chartData = isConnected ? (data ?? _defaultData) : List<double>.filled(7, 0.0);

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
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                BarChart(
                  BarChartData(
                    maxY: 6,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) =>
                          FlLine(color: Colors.white12, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
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
                            width: 18,
                            borderRadius: BorderRadius.circular(5),
                            gradient: isConnected && item.value > 0
                                ? const LinearGradient(
                                    colors: [Color(0xff00D9A6), Color(0xff007BFF)],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  )
                                : LinearGradient(
                                    colors: [Colors.white10, Colors.white12],
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                if (!isConnected)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xff071426).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.query_stats_rounded, color: Colors.white38, size: 28),
                          SizedBox(height: 6),
                          Text(
                            'Grafik harian belum tersedia',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Hubungkan perangkat IoT untuk memulai pencatatan.',
                            style: TextStyle(color: Colors.white38, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt, color: isConnected ? const Color(0xff00D9A6) : Colors.white38, size: 14),
              const SizedBox(width: 5),
              Text(
                'kWh',
                style: TextStyle(color: isConnected ? Colors.white54 : Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
