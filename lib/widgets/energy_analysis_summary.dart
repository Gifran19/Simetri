import 'package:flutter/material.dart';

class EnergyAnalysisSummary extends StatelessWidget {
  final double yearlyEnergy;
  final double averageEnergy;
  final double yearlyCost;

  const EnergyAnalysisSummary({
    super.key,
    required this.yearlyEnergy,
    required this.averageEnergy,
    required this.yearlyCost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
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
                  value: '${yearlyEnergy.toInt()} kWh',
                  percentText: '6% lebih rendah',
                  subText: 'dari tahun 2025',
                ),
              ),
              const SizedBox(width: 10),
              // Rata - rata / bulan
              Expanded(
                child: _buildMetricBox(
                  icon: Icons.insert_chart_rounded,
                  iconBg: const Color(0xff0B3842),
                  iconColor: const Color(0xff00D9A6),
                  title: 'Rata - rata / bulan',
                  value: '${averageEnergy.toStringAsFixed(2)} kWh',
                  percentText: '12% lebih rendah',
                  subText: 'dari tahun 2025',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Row: Total Biaya / Total Pemakaian
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
                  decoration: const BoxDecoration(
                    color: Color(0xff123A54),
                    shape: BoxShape.circle,
                  ),
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
                      'Total Pemakaian',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Rp ${yearlyCost.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
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
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xff00D9A6),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 11,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '10% lebih rendah',
                          style: TextStyle(
                            color: Color(0xff00D9A6),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'dari tahun 2025',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 8.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
    required String percentText,
    required String subText,
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
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
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
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xff00D9A6),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 8,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            percentText,
                            style: const TextStyle(
                              color: Color(0xff00D9A6),
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            subText,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 7,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}