import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Smooth animated organic top wave for Login Screen
class LoginWaveClipper extends CustomClipper<Path> {
  final double phase;

  const LoginWaveClipper({this.phase = 0.0});

  @override
  Path getClip(Size size) {
    final shift = math.sin(phase * math.pi * 2) * 14.0;
    final path = Path();
    path.lineTo(0, size.height * 0.64 + shift * 0.5);
    path.cubicTo(
      size.width * 0.28,
      size.height * 0.40 - shift,
      size.width * 0.62,
      size.height * 1.04 + shift,
      size.width,
      size.height * 0.70 - shift * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant LoginWaveClipper oldClipper) =>
      oldClipper.phase != phase;
}

/// Circular battery arc gauge with smooth animated sweep
class BatteryRingGauge extends StatelessWidget {
  final int percent;
  final bool hasBattery;
  final bool isCharging;
  final AppPalette palette;

  const BatteryRingGauge({
    super.key,
    required this.percent,
    required this.hasBattery,
    required this.isCharging,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final Color ringColor;
    if (!hasBattery) {
      ringColor = palette.info;
    } else if (isCharging) {
      ringColor = palette.success;
    } else if (percent <= 15) {
      ringColor = palette.danger;
    } else if (percent <= 35) {
      ringColor = palette.warning;
    } else {
      ringColor = palette.success;
    }

    final targetProgress = hasBattery ? (percent.clamp(0, 100) / 100.0) : 1.0;

    return SizedBox(
      width: 102,
      height: 102,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: targetProgress),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (context, animVal, child) {
          return CustomPaint(
            painter: _ArcRingPainter(
              progress: animVal,
              activeColor: ringColor,
              trackColor: palette.bgElevated,
              strokeWidth: 9.5,
            ),
            child: child,
          );
        },
        child: Center(
          child: hasBattery
              ? Text(
                  '$percent%',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                )
              : Icon(Icons.power_rounded, color: palette.info, size: 30),
        ),
      ),
    );
  }
}

class _ArcRingPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;

  _ArcRingPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    const startAngle = math.pi * 0.78;
    const sweepTotal = math.pi * 1.44;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      trackPaint,
    );

    if (progress > 0.005) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * progress.clamp(0.03, 1.0),
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldReclipOrRepaint(_ArcRingPainter old) =>
      old.progress != progress || old.activeColor != activeColor;

  @override
  bool shouldRepaint(covariant _ArcRingPainter oldDelegate) =>
      shouldReclipOrRepaint(oldDelegate);
}

/// Dual-segment circular Data Usage ring (Blue Download + Orange Upload) matching 00:04
class DataUsageRingGauge extends StatelessWidget {
  final int rxBytes;
  final int txBytes;
  final String centerText;
  final AppPalette palette;

  const DataUsageRingGauge({
    super.key,
    required this.rxBytes,
    required this.txBytes,
    required this.centerText,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final total = rxBytes + txBytes;
    final dlRatio = total > 0 ? (rxBytes / total).clamp(0.05, 0.95) : 0.72;

    return SizedBox(
      width: 102,
      height: 102,
      child: CustomPaint(
        painter: _DualSegmentRingPainter(
          downloadRatio: dlRatio,
          hasTraffic: total > 0,
          downloadColor: palette.info,
          uploadColor: palette.warning,
          trackColor: palette.bgElevated,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                centerText,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DualSegmentRingPainter extends CustomPainter {
  final double downloadRatio;
  final bool hasTraffic;
  final Color downloadColor;
  final Color uploadColor;
  final Color trackColor;

  _DualSegmentRingPainter({
    required this.downloadRatio,
    required this.hasTraffic,
    required this.downloadColor,
    required this.uploadColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    if (!hasTraffic) return;

    const gap = 0.12;
    const totalAvailable = (math.pi * 2) - (gap * 2);
    final dlSweep = totalAvailable * downloadRatio;
    final ulSweep = totalAvailable * (1.0 - downloadRatio);

    final dlPaint = Paint()
      ..color = downloadColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final ulPaint = Paint()
      ..color = uploadColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, dlSweep, false, dlPaint);
    canvas.drawArc(rect, -math.pi / 2 + dlSweep + gap, ulSweep, false, ulPaint);
  }

  @override
  bool shouldRepaint(covariant _DualSegmentRingPainter oldDelegate) =>
      oldDelegate.downloadRatio != downloadRatio ||
      oldDelegate.hasTraffic != hasTraffic;
}

/// Semi-circle gauge + 5 signal bars matching Signal Strength card (00:04)
class SignalGaugeAndBars extends StatelessWidget {
  final int signalPercent;
  final int signalBars;
  final AppPalette palette;

  const SignalGaugeAndBars({
    super.key,
    required this.signalPercent,
    required this.signalBars,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final Color sigColor = signalPercent >= 65
        ? palette.success
        : (signalPercent >= 35 ? palette.warning : palette.danger);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 72,
            height: 44,
            child: CustomPaint(
              painter: _SemiGaugePainter(
                progress: (signalPercent.clamp(5, 100)) / 100.0,
                activeColor: sigColor,
                trackColor: palette.bgElevated,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (i) {
              final active = i < signalBars;
              final barHeight = 14.0 + (i * 6.5);
              return Container(
                width: 6.5,
                height: barHeight,
                margin: const EdgeInsets.symmetric(horizontal: 2.2),
                decoration: BoxDecoration(
                  color: active ? sigColor : palette.bgElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SemiGaugePainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color trackColor;

  _SemiGaugePainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = Offset(size.width / 2, size.height - 4);
    final radius = math.min(size.width / 2 - stroke / 2, size.height - stroke);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);
    canvas.drawArc(rect, math.pi, math.pi * progress, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _SemiGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.activeColor != activeColor;
}

/// Floating glassmorphic bottom bar + 4G circular action orb matching 00:03-00:18
class FloatingGlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final String networkBadge;
  final ValueChanged<int> onTabSelected;
  final VoidCallback on4GPressed;
  final AppPalette palette;

  const FloatingGlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.networkBadge,
    required this.onTabSelected,
    required this.on4GPressed,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular 4G quick button on the right (RTL start)
          GestureDetector(
            onTap: on4GPressed,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.bgElevated.withOpacity(0.88),
                    border: Border.all(
                      color: palette.borderSubtle.withOpacity(0.9),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    networkBadge,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Main 3-tab glass pill container
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: palette.bgElevated.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: palette.borderSubtle.withOpacity(0.9),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(
                        index: 0,
                        icon: Icons.home_rounded,
                        label: 'الرئيسية',
                      ),
                      _buildNavItem(
                        index: 1,
                        icon: Icons.router_rounded,
                        label: 'المودم',
                      ),
                      _buildNavItem(
                        index: 2,
                        icon: Icons.network_check_rounded,
                        label: 'التشخيص',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = currentIndex == index;
    final activeColor = palette.accentSecondary;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => onTabSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? activeColor.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? activeColor : palette.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? activeColor : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
