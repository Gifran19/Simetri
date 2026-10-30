import 'dart:math';

import 'package:flutter/material.dart';

import '../services/live_status.dart';

class MonitoringCard extends StatefulWidget {
  final double voltage;
  final double power;
  final double current;
  final double frequency;
  final double powerFactor;
  final int powerLimitVa;
  final VoidCallback? onConfigureLimit;
  final bool isConnected;

  /// Status data aktual dari perangkat (live / offline / stale / error / belum ada data / DEMO).
  final LiveStatus status;

  const MonitoringCard({
    super.key,
    required this.voltage,
    required this.power,
    required this.current,
    this.frequency = 50.0,
    this.powerFactor = 0.98,
    this.powerLimitVa = 1300,
    this.onConfigureLimit,
    this.isConnected = true,
    this.status = LiveStatus.noData,
  });

  @override
  State<MonitoringCard> createState() => _MonitoringCardState();
}

class _MonitoringCardState extends State<MonitoringCard> {
  // 0 = Trio View (3 circles enlarged), 1 = Hero Detail View (1 gigantic circle)
  int _viewMode = 0;
  // Selected metric for Hero Detail: 0 = Voltage, 1 = Power, 2 = Current
  int _selectedMetric = 0;

  /// true jika angka pengukuran boleh ditampilkan (data nyata segar atau DEMO eksplisit).
  bool get _showsValues => widget.isConnected && widget.status.showsMeasurements;

  Color get _statusColor {
    if (!widget.isConnected) return Colors.grey.shade600;
    switch (widget.status) {
      case LiveStatus.live:
        return const Color(0xff00D9A6);
      case LiveStatus.demo:
        return Colors.purpleAccent;
      case LiveStatus.sensorStale:
        return Colors.amber;
      case LiveStatus.sensorError:
        return Colors.redAccent;
      case LiveStatus.offline:
        return Colors.orangeAccent;
      case LiveStatus.noData:
        return Colors.white38;
    }
  }

  /// Penjelasan singkat saat nilai tidak ditampilkan.
  String get _noValueNote {
    if (!widget.isConnected) return 'Perangkat belum terhubung • Tidak ada data sensor';
    return '${widget.status.description} Nilai tidak ditampilkan.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title & View Mode Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                        boxShadow: _showsValues
                            ? [
                                BoxShadow(
                                  color: _statusColor,
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Monitoring saat ini',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (context) {
                        Color badgeColor = _statusColor;
                        String badgeText;
                        if (!widget.isConnected) {
                          badgeColor = Colors.white38;
                          badgeText = 'BELUM TERHUBUNG';
                        } else {
                          badgeText = widget.status.badge;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_viewMode == 1)
                InkWell(
                  onTap: () => setState(() => _viewMode = 0),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, size: 12, color: Color(0xff00D9A6)),
                        SizedBox(width: 4),
                        Text(
                          '3 Parameter',
                          style: TextStyle(
                            color: Color(0xff00D9A6),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          // View Switch: Trio (3 circles) or Hero (1 extra large circle)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: _viewMode == 0 ? _buildTrioGauges() : _buildHeroGauge(),
          ),

          const SizedBox(height: 16),

          // Kapasitas Beban Daya vs Batas MCB PLN (Anti-Trip / Overload Alert)
          _buildMcbCapacityBar(),
        ],
      ),
    );
  }

  Widget _buildMcbCapacityBar() {
    final isLive = _showsValues;
    final powerValue = isLive ? widget.power : 0.0;
    final limitVa = widget.powerLimitVa > 0 ? widget.powerLimitVa : 1300;
    final double percent = (powerValue / limitVa) * 100;
    final double clampedFraction = (percent / 100).clamp(0.0, 1.0);

    Color statusColor = isLive ? const Color(0xff00D9A6) : Colors.white38;
    String statusText = isLive ? 'Beban Listrik Aman' : 'Tidak ada data beban';
    IconData statusIcon = isLive ? Icons.shield_rounded : Icons.help_outline_rounded;

    if (isLive && percent >= 95) {
      statusColor = Colors.redAccent;
      statusText = 'BAHAYA OVERLOAD! Risiko MCB PLN Trip';
      statusIcon = Icons.warning_rounded;
    } else if (isLive && percent >= 80) {
      statusColor = Colors.orangeAccent;
      statusText = 'WASPADA: Beban Mendekati Batas MCB';
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff071426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: percent >= 80 ? statusColor.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (widget.onConfigureLimit != null)
                InkWell(
                  onTap: widget.onConfigureLimit,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Ubah $limitVa VA',
                      style: const TextStyle(
                        color: Color(0xff00D9A6),
                        fontSize: 10.5,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  'Batas: $limitVa VA',
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: clampedFraction,
              minHeight: 7,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terpakai: ${powerValue.toStringAsFixed(1)} W',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                '${percent.toStringAsFixed(1)}% Kapasitas',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  // ==========================================
  // TRIO VIEW: 3 Enlarged Responsive Circles
  // ==========================================
  Widget _buildTrioGauges() {
    return LayoutBuilder(
      key: const ValueKey('trio_view'),
      builder: (context, constraints) {
        // Calculate dynamic diameter based on available width
        // Max space per gauge, clamped comfortably
        final availableWidth = constraints.maxWidth;
        final itemWidth = (availableWidth - 16) / 3;
        final circleDiameter = (itemWidth - 6).clamp(86.0, 130.0);

        final isReadingOk = _showsValues;

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedMetric = 0;
                        _viewMode = 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: GaugeMeter(
                      value: isReadingOk ? widget.voltage / 250 : 0.0,
                      valueText: isReadingOk
                          ? widget.voltage.toStringAsFixed(1)
                          : '--',
                      unitText: 'V',
                      title: 'Tegangan',
                      subtitle: 'Volt (V)',
                      gradientColors: const [
                        Color(0xff00FFA3),
                        Color(0xff00D9A6),
                        Color(0xff00A896),
                      ],
                      size: circleDiameter,
                      icon: Icons.bolt_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedMetric = 1;
                        _viewMode = 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: GaugeMeter(
                      value: isReadingOk ? widget.power / 100 : 0.0,
                      valueText: isReadingOk
                          ? widget.power.toStringAsFixed(1)
                          : '--',
                      unitText: 'W',
                      title: 'Daya',
                      subtitle: 'Watt (W)',
                      gradientColors: const [
                        Color(0xff00D2FF),
                        Color(0xff008CFF),
                        Color(0xff0052D4),
                      ],
                      size: circleDiameter,
                      icon: Icons.power_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedMetric = 2;
                        _viewMode = 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: GaugeMeter(
                      value: isReadingOk ? widget.current / 5 : 0.0,
                      valueText: isReadingOk
                          ? widget.current.toStringAsFixed(2)
                          : '--',
                      unitText: 'A',
                      title: 'Arus',
                      subtitle: 'Ampere (A)',
                      gradientColors: const [
                        Color(0xffF9D423),
                        Color(0xffB7FF00),
                        Color(0xff70E000),
                      ],
                      size: circleDiameter,
                      icon: Icons.waves_rounded,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tap hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _showsValues ? Icons.touch_app_rounded : Icons.info_outline_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _showsValues
                        ? (widget.status == LiveStatus.demo
                            ? 'DEMO • Data simulasi, bukan dari perangkat'
                            : 'Ketuk lingkaran untuk memperbesar detail')
                        : _noValueNote,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // HERO VIEW: Gigantic Glowing Radial Meter
  // ==========================================
  Widget _buildHeroGauge() {
    // Current selected metric data
    late String title;
    late String valueText;
    late String unit;
    late double progress;
    late List<Color> colors;
    late String statusNote;
    late IconData icon;

    final isLive = _showsValues;
    // Keterangan netral: hanya menyatakan status data, tanpa klaim
    // ("normal", "efisien", "aman") yang tidak diukur oleh aplikasi.
    final String note = !widget.isConnected
        ? 'Perangkat belum terhubung • Tidak ada data sensor'
        : (widget.status == LiveStatus.demo
            ? 'DEMO • Data simulasi, bukan dari perangkat'
            : (isLive ? 'Data nyata dari perangkat' : widget.status.description));

    switch (_selectedMetric) {
      case 0:
        title = 'Tegangan Listrik';
        valueText = isLive ? widget.voltage.toStringAsFixed(1) : '--';
        unit = 'Volt';
        progress = isLive ? (widget.voltage / 250).clamp(0.0, 1.0) : 0.0;
        colors = const [Color(0xff00FFA3), Color(0xff00D9A6), Color(0xff00A896)];
        statusNote = note;
        icon = Icons.bolt_rounded;
        break;
      case 1:
        title = 'Daya Aktif';
        valueText = isLive ? widget.power.toStringAsFixed(1) : '--';
        unit = 'Watt';
        progress = isLive ? (widget.power / 100).clamp(0.0, 1.0) : 0.0;
        colors = const [Color(0xff00D2FF), Color(0xff008CFF), Color(0xff0052D4)];
        statusNote = note;
        icon = Icons.power_rounded;
        break;
      case 2:
      default:
        title = 'Kuat Arus';
        valueText = isLive ? widget.current.toStringAsFixed(2) : '--';
        unit = 'Ampere';
        progress = isLive ? (widget.current / 5).clamp(0.0, 1.0) : 0.0;
        colors = const [Color(0xffF9D423), Color(0xffB7FF00), Color(0xff70E000)];
        statusNote = note;
        icon = Icons.waves_rounded;
        break;
    }

    return LayoutBuilder(
      key: const ValueKey('hero_view'),
      builder: (context, constraints) {
        // Enormous circular gauge size: scales responsively up to 210px
        final heroSize = (constraints.maxWidth * 0.52).clamp(170.0, 220.0);

        return Column(
          children: [
            // Metric selector pills
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xff071426),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildMetricTab(0, '⚡ Tegangan', const Color(0xff00D9A6)),
                  _buildMetricTab(1, '💡 Daya', const Color(0xff008CFF)),
                  _buildMetricTab(2, '🔌 Arus', const Color(0xffB7FF00)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Giant Glowing Circular Gauge (Ketuk untuk kembali ke 3 Meter)
            Center(
              child: InkWell(
                onTap: () => setState(() => _viewMode = 0),
                borderRadius: BorderRadius.circular(heroSize / 2),
                child: HeroCircularGauge(
                  size: heroSize,
                  progress: progress,
                  valueText: valueText,
                  unitText: unit,
                  title: title,
                  gradientColors: colors,
                  icon: icon,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tap hint untuk kembali
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  'Ketuk lingkaran untuk kembali ke tampilan 3 meter',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors[1].withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors[1].withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: colors[0]),
                  const SizedBox(width: 6),
                  Text(
                    statusNote,
                    style: TextStyle(color: colors[0], fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricTab(int index, String label, Color accentColor) {
    final isSelected = _selectedMetric == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMetric = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: accentColor.withValues(alpha: 0.4)) : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? accentColor : Colors.white54,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// RESPONSIVE GAUGE METER (Trio View)
// ==========================================
class GaugeMeter extends StatelessWidget {
  final double value;
  final String valueText;
  final String unitText;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final double size;
  final IconData icon;

  const GaugeMeter({
    super.key,
    required this.value,
    required this.valueText,
    required this.unitText,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.size,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final strokeWidth = (size * 0.095).clamp(8.0, 13.0);
    final valueFontSize = (size * 0.17).clamp(13.0, 18.0);
    final unitFontSize = (size * 0.11).clamp(9.0, 12.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, animValue, _) {
              return CustomPaint(
                painter: NeonGaugePainter(
                  progress: animValue,
                  colors: gradientColors,
                  strokeWidth: strokeWidth,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: (size * 0.16).clamp(12.0, 18.0),
                        color: gradientColors[0].withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            valueText,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: valueFontSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            unitText,
                            style: TextStyle(
                              color: gradientColors[0],
                              fontSize: unitFontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
      ],
    );
  }
}

// ==========================================
// HERO CIRCULAR GAUGE (Extra Large Focus Mode)
// ==========================================
class HeroCircularGauge extends StatelessWidget {
  final double size;
  final double progress;
  final String valueText;
  final String unitText;
  final String title;
  final List<Color> gradientColors;
  final IconData icon;

  const HeroCircularGauge({
    super.key,
    required this.size,
    required this.progress,
    required this.valueText,
    required this.unitText,
    required this.title,
    required this.gradientColors,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final strokeWidth = (size * 0.085).clamp(12.0, 18.0);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: progress),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutBack,
        builder: (context, animValue, _) {
          return CustomPaint(
            painter: HeroNeonGaugePainter(
              progress: animValue,
              colors: gradientColors,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: Container(
                width: size * 0.68,
                height: size * 0.68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff071426).withValues(alpha: 0.85),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors[0].withValues(alpha: 0.15),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: gradientColors[0].withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: gradientColors[0], size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      valueText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      unitText,
                      style: TextStyle(
                        color: gradientColors[0],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// PAINTER: Neon Glow Gauge (Trio)
// ==========================================
class NeonGaugePainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double strokeWidth;

  NeonGaugePainter({required this.progress, required this.colors, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2) - 2;
    const startAngle = -pi / 2;
    final sweepAngle = 2 * pi * progress;

    // Track Background
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.08);

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.001) return;

    // Neon Glow blur behind the progress arc
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeCap = StrokeCap.round
      ..color = colors[0].withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      glowPaint,
    );

    // Active Gradient Arc
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + 2 * pi,
        colors: colors,
        transform: GradientRotation(startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );

    // Illuminated Glowing Tip Dot
    final tipAngle = startAngle + sweepAngle;
    final tipOffset = Offset(
      center.dx + radius * cos(tipAngle),
      center.dy + radius * sin(tipAngle),
    );

    // White core inside tip dot
    final tipDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tipOffset, strokeWidth * 0.32, tipDotPaint);
  }

  @override
  bool shouldRepaint(covariant NeonGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors != colors;
  }
}

// ==========================================
// PAINTER: Hero Neon Gauge (Focus Mode)
// ==========================================
class HeroNeonGaugePainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double strokeWidth;

  HeroNeonGaugePainter({required this.progress, required this.colors, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2) - 4;

    // Outer subtle tick marks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.5;

    const totalTicks = 28;
    for (int i = 0; i < totalTicks; i++) {
      final angle = (2 * pi / totalTicks) * i;
      final outerR = radius + (strokeWidth / 2) + 4;
      final innerR = outerR - 4;
      canvas.drawLine(
        Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(center.dx + outerR * cos(angle), center.dy + outerR * sin(angle)),
        tickPaint,
      );
    }

    // Background track ring
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.08);

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.001) return;

    const startAngle = -pi / 2;
    final sweepAngle = 2 * pi * progress;

    // Glowing halo
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8
      ..strokeCap = StrokeCap.round
      ..color = colors[0].withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      glowPaint,
    );

    // Active Gradient Progress Arc
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + 2 * pi,
        colors: colors,
        transform: GradientRotation(startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );

    // Glowing tip dot
    final tipAngle = startAngle + sweepAngle;
    final tipOffset = Offset(
      center.dx + radius * cos(tipAngle),
      center.dy + radius * sin(tipAngle),
    );

    final tipHalo = Paint()
      ..color = colors[0].withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(tipOffset, strokeWidth * 0.55, tipHalo);

    final tipCore = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tipOffset, strokeWidth * 0.35, tipCore);
  }

  @override
  bool shouldRepaint(covariant HeroNeonGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors != colors;
  }
}
