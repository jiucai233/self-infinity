import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';

/// The window of the life overview drawn day by day: sleep as bars (0–12 h),
/// focus and stress as lines (1–5), and under them one dot per day with
/// audits (cleared when one passed that day, failed otherwise).
class LifeChart extends StatelessWidget {
  const LifeChart({super.key, required this.days, this.height = 180});

  final List<LifeDay> days;
  final double height;

  static const Color sleepColor = AppColors.locked;
  static const Color focusColor = AppColors.primary;
  static const Color stressColor = AppColors.danger;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _LifeChartPainter(days)),
  );
}

class _LifeChartPainter extends CustomPainter {
  _LifeChartPainter(this.days);

  final List<LifeDay> days;

  static const double maxSleep = 12;
  static const double dotRow = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final plot = Rect.fromLTWH(0, 4, size.width, size.height - dotRow - 8);
    final step = plot.width / days.length;
    double x(int i) => plot.left + step * (i + 0.5);

    // Guide lines at 4 and 8 hours.
    final guide = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    for (final h in [4.0, 8.0]) {
      final y = plot.bottom - plot.height * h / maxSleep;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), guide);
    }

    final bar = Paint()..color = LifeChart.sleepColor;
    final barWidth = math.max(2.0, math.min(14.0, step * 0.6));
    for (var i = 0; i < days.length; i++) {
      final hours = days[i].sleepHours;
      if (hours == null) continue;
      final top = plot.bottom - plot.height * (hours.clamp(0, maxSleep) / maxSleep);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(x(i) - barWidth / 2, top, x(i) + barWidth / 2, plot.bottom),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        bar,
      );
    }

    void line(int? Function(LifeDay) value, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final dot = Paint()..color = color;
      Path? path;
      for (var i = 0; i < days.length; i++) {
        final v = value(days[i]);
        if (v == null) {
          path = null; // a day without it breaks the line
          continue;
        }
        final p = Offset(x(i), plot.bottom - plot.height * (v - 0.5) / 5);
        canvas.drawCircle(p, 2.5, dot);
        if (path == null) {
          path = Path()..moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
          canvas.drawPath(path, paint);
        }
      }
    }

    line((d) => d.focus, LifeChart.focusColor);
    line((d) => d.stress, LifeChart.stressColor);

    final dotY = size.height - dotRow / 2;
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      if (d.audits == 0) continue;
      canvas.drawCircle(
        Offset(x(i), dotY),
        math.min(4, step * 0.35),
        Paint()..color = d.passed > 0 ? AppColors.success : AppColors.danger,
      );
    }
  }

  @override
  bool shouldRepaint(_LifeChartPainter old) => old.days != days;
}
