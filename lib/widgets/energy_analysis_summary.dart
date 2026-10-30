import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EnergyAnalysisSummary extends StatelessWidget {
  final int year;
  final double yearlyEnergy;
  final double averageEnergy;
  final double yearlyCost;

  /// Persentase perubahan pemakaian vs tahun lalu (null = tidak ada data tahun lalu)
  final double? energyChangePercent;

  /// Persentase perubahan biaya vs tahun lalu (null = tidak ada data tahun lalu)
  final double? costChangePercent;

  const EnergyAnalysisSummary({
    super.key,
    required this.year,
    required this.yearlyEnergy,
    required this.averageEnergy,
    required this.yearlyCost,
    this.energyChangePercent,
    this.costChangePercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
        children: [
          // Top Row: 2 metrics
          Row(
            children: [
              // Total Pemakaian
              Expanded(
                child: _buildMetricBox(
                  icon: Icons.bolt_rounded,
                  iconBg: const Color(0xff0E3D35),
                  iconColor: const Color(0xff00D9A6),
                  title: 'Total Pemakaian',
                  value: '${yearlyEnergy.toStringAsFixed(3)} kWh',
                  changePercent: energyChangePercent,
                  prevYear: year - 1,
                ),
              ),
              const SizedBox(width: 10),
              // Rata - rata / bulan
              Expanded(
                child: _buildMetricBox(
                  icon: Icons.insert_chart_rounded,
                  iconBg: const Color(0xff0B3842),
                  iconColor: const Color(0xff00D9A6),
                  title: 'Rata-rata / bulan',
                  value: '${averageEnergy.toStringAsFixed(3)} kWh',
                  changePercent: energyChangePercent,
                  prevYear: year - 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Row: Total Biaya
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xff0A192F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Color(0xff123A54), shape: BoxShape.circle),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xff00A3FF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Biaya Listrik',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Rp ${NumberFormat('#,###', 'id_ID').format(yearlyCost.toInt())}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (costChangePercent != null) _buildChangeBadge(costChangePercent!, year - 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    required double? changePercent,
    required int prevYear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xff0A192F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                if (changePercent != null)
                  _buildChangeBadge(changePercent, prevYear)
                else
                  const Text(
                    'Belum ada data pembanding',
                    style: TextStyle(color: Colors.white38, fontSize: 8),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeBadge(double changePercent, int prevYear) {
    final isDown = changePercent <= 0;
    final color = isDown ? const Color(0xff00D9A6) : Colors.redAccent;
    final icon = isDown ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final absPercent = changePercent.abs().toStringAsFixed(1);
    final label = isDown ? '$absPercent% lebih rendah' : '$absPercent% lebih tinggi';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: Icon(icon, size: 8, color: Colors.black)),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              Text(
                'dari tahun $prevYear',
                style: const TextStyle(color: Colors.white38, fontSize: 7, height: 1.0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
