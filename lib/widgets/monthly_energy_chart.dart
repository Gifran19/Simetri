import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MonthlyEnergyChart extends StatelessWidget {
  final List<double> data;
  final bool isConnected;

  const MonthlyEnergyChart({
    super.key,
    required this.data,
    this.isConnected = true,
  });

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
    // Nilai valid jika ada minimal satu bulan > 0.00001 (tidak menganggap 0.002 sebagai kosong)
    final bool isEmpty = data.isEmpty || data.every((e) => e <= 0.00001);
    final displayData = isEmpty ? List<double>.filled(12, 0.0) : data;
    final maxVal = isEmpty ? 100.0 : displayData.reduce((a, b) => a > b ? a : b);

    // Hitung maxY dan interval dinamis agar data berapapun kecilnya (mis. 0.002 kWh)
    // tetap proporsional dan barnya tampak jelas terlihat
    final double maxY;
    final double interval;
    if (isEmpty || maxVal <= 0.0) {
      maxY = 100.0;
      interval = 20.0;
    } else if (maxVal <= 0.005) {
      maxY = 0.005;
      interval = 0.001;
    } else if (maxVal <= 0.01) {
      maxY = 0.01;
      interval = 0.002;
    } else if (maxVal <= 0.05) {
      maxY = 0.05;
      interval = 0.01;
    } else if (maxVal <= 0.1) {
      maxY = 0.1;
      interval = 0.02;
    } else if (maxVal <= 0.5) {
      maxY = 0.5;
      interval = 0.1;
    } else if (maxVal <= 1.0) {
      maxY = 1.0;
      interval = 0.2;
    } else if (maxVal <= 5.0) {
      maxY = 5.0;
      interval = 1.0;
    } else if (maxVal <= 10.0) {
      maxY = 10.0;
      interval = 2.0;
    } else if (maxVal <= 50.0) {
      maxY = 50.0;
      interval = 10.0;
    } else if (maxVal <= 150.0) {
      maxY = 150.0;
      interval = 30.0;
    } else {
      maxY = ((maxVal / 20).ceil() * 20 + 20).toDouble();
      interval = 20.0;
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
                  'Pemakaian Energi Bulanan',
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
          const Text('kWh', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 12),

          // Chart with ClipRect
          SizedBox(
            height: 240,
            child: Stack(
              children: [
                ClipRect(
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
                            return BarTooltipItem(
                              '$monthName\n${rod.toY.toStringAsFixed(3)} kWh',
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
                              if (value < 0 || value > maxY + (interval * 0.1)) {
                                return const SizedBox();
                              }
                              final String labelText;
                              if (maxY <= 0.01) {
                                labelText = value.toStringAsFixed(3);
                              } else if (maxY <= 0.1) {
                                labelText = value.toStringAsFixed(2);
                              } else if (maxY <= 1.0) {
                                labelText = value.toStringAsFixed(1);
                              } else {
                                labelText = value.toInt().toString();
                              }
                              return Text(
                                labelText,
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
                      barGroups: displayData.asMap().entries.map((entry) {
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
                if (isEmpty)
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
                          const Icon(Icons.bar_chart_rounded, color: Colors.white38, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            isConnected ? 'Belum ada rekaman histori' : 'Grafik bulanan belum tersedia',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? 'Data akumulasi bulanan akan tercatat otomatis saat tersimpan di database.'
                                : 'Hubungkan perangkat IoT untuk mulai menyinkronkan data.',
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
