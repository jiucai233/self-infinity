import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';

/// The learner's ability audit by audit: a line from 0 (before the first
/// audit) through the ability after each one, over a faint line at zero. A
/// pass is a filled dot, a fail a hollow one.
class LearnerChart extends StatelessWidget {
  const LearnerChart({super.key, required this.history, this.height = 160});

  final List<LearnerStep> history;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _LearnerChartPainter(history)),
  );
}

class _LearnerChartPainter extends CustomPainter {
  _LearnerChartPainter(this.history);

  final List<LearnerStep> history;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final values = [0.0, for (final s in history) s.ability];
    final plot = Rect.fromLTWH(0, 8, size.width, size.height - 16);
    final step = plot.width / values.length;
    double x(int i) => plot.left + step * (i + 0.5);

    // The scale always holds zero; a flat history sits in the middle.
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    if (high - low < 0.1) {
      low -= 0.5;
      high += 0.5;
    }
    double y(double v) => plot.bottom - plot.height * (v - low) / (high - low);

    canvas.drawLine(
      Offset(plot.left, y(0)),
      Offset(plot.right, y(0)),
      Paint()
        ..color = AppColors.outline
        ..strokeWidth = 1,
    );

    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(path, line);

    final radius = math.min(4.0, step * 0.35);
    final filled = Paint()..color = AppColors.primary;
    final hollow = Paint()..color = AppColors.background;
    final ring = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      if (history[i - 1].passed) {
        canvas.drawCircle(p, radius, filled);
      } else {
        canvas.drawCircle(p, radius, hollow);
        canvas.drawCircle(p, radius, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_LearnerChartPainter old) => old.history != history;
}
