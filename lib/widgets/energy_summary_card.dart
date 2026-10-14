import 'package:flutter/material.dart';

class EnergySummaryCard extends StatelessWidget {
  final String titleLeft;
  final String valueLeft;
  final String titleRight;
  final String valueRight;

  const EnergySummaryCard({
    super.key,
    required this.titleLeft,
    required this.valueLeft,
    required this.titleRight,
    required this.valueRight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _summaryItem(
            Icons.bolt_rounded,
            const Color(0xff00D9A6),
            titleLeft,
            valueLeft,
            '↓ 12% hemat',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryItem(
            Icons.account_balance_wallet_rounded,
            const Color(0xff00D9FF),
            titleRight,
            valueRight,
            'Sesuai estimasi',
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(
    IconData icon,
    Color color,
    String title,
    String value,
    String badgeText,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}