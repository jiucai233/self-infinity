import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../api/models.dart';
import '../../theme/tokens.dart';

/// The last weeks as a grid of days (a column per week, Monday on top), each
/// as warm as the number of workouts it had; a tap picks the day.
class WorkoutHeatmap extends StatelessWidget {
  const WorkoutHeatmap({
    super.key,
    required this.days,
    required this.selected,
    required this.onPick,
  });

  final List<WorkoutDay> days;
  final String selected;
  final ValueChanged<String> onPick;

  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final top = days.fold<int>(1, (m, d) => d.workouts > m ? d.workouts : m);
    // Pad the front so the first column starts on a Monday.
    final first = DateTime.parse(days.first.date);
    final lead = first.weekday - 1;
    final cells = <WorkoutDay?>[for (var i = 0; i < lead; i++) null, ...days];
    final weeks = (cells.length / 7).ceil();
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - 28 - _gap * (weeks - 1)) / weeks).clamp(8.0, 30.0);
        return Row(
          key: const Key('workout-heatmap'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  for (var r = 0; r < 7; r++)
                    SizedBox(
                      height: size + _gap,
                      child: r.isEven
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                DateFormat.E(locale).format(DateTime(2024, 1, 1 + r)),
                                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            for (var w = 0; w < weeks; w++) ...[
              if (w > 0) const SizedBox(width: _gap),
              Column(
                children: [
                  for (var r = 0; r < 7; r++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: _cell(cells.elementAtOrNull(w * 7 + r), size, top),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _cell(WorkoutDay? d, double size, int top) {
    if (d == null) return SizedBox.square(dimension: size);
    final picked = d.date == selected;
    return InkWell(
      key: Key('workout-day-${d.date}'),
      onTap: () => onPick(d.date),
      borderRadius: AppRadius.chipBorder,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: d.workouts == 0
              ? AppColors.surfaceHigh
              : AppColors.ember.withValues(alpha: 0.35 + 0.65 * d.workouts / top),
          borderRadius: BorderRadius.all(Radius.circular(size / 4)),
          border: picked ? Border.all(color: AppColors.textPrimary, width: 2) : null,
        ),
      ),
    );
  }
}

/// A line through (date, value) points, oldest left; the last value labelled.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.points, this.height = 160});

  final List<(String, double)> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        key: const Key('progress-line'),
        painter: _LinePainter(points, theme.labelSmall ?? const TextStyle()),
        size: Size.infinite,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.label);

  final List<(String, double)> points;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const pad = 24.0;
    final values = [for (final p in points) p.$2];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi - lo == 0 ? 1 : hi - lo;
    Offset at(int i) => Offset(
      points.length == 1 ? size.width / 2 : pad + (size.width - 2 * pad) * i / (points.length - 1),
      size.height - pad - (size.height - 2 * pad) * (values[i] - lo) / span,
    );
    final grid = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(pad, size.height - pad), Offset(size.width - pad, size.height - pad), grid)
      ..drawLine(const Offset(pad, pad), Offset(size.width - pad, pad), grid);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.ember,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(at(i), 3, Paint()..color = AppColors.ember);
    }
    void text(String s, Offset o, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: label.copyWith(color: AppColors.textTertiary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, right ? o - Offset(tp.width, 0) : o);
    }

    String fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    text(fmt(hi), const Offset(0, pad - 16));
    text(fmt(lo), Offset(0, size.height - pad + 4));
    text(points.first.$1.substring(5), Offset(pad, size.height - 14));
    if (points.length > 1) {
      text(points.last.$1.substring(5), Offset(size.width - pad, size.height - 14), right: true);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points != points;
}

/// Horizontal bars with a label and a count each.
class CountBars extends StatelessWidget {
  const CountBars({super.key, required this.rows});

  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final top = rows.fold<int>(1, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(
      children: [
        for (final (label, n) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text(label, style: theme.labelMedium)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 10,
                        width: n == 0 ? 2 : box.maxWidth * n / top,
                        decoration: BoxDecoration(
                          color: n == 0 ? AppColors.outline : AppColors.ember,
                          borderRadius: AppRadius.chipBorder,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$n', textAlign: TextAlign.right, style: theme.labelMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
