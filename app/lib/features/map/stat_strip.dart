import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/life_tree.dart';
import '../../theme/tokens.dart';

/// Your progress over every course, as big numbers with small labels:
/// a ring (`3/12`), `Cleared`, `Progress`, `Ready`, `Audits`, `Lessons`.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats, this.compact = false});

  final LifeStats stats;

  /// Phones: the ring, `Cleared` and `Progress` only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('stat-strip'),
      spacing: AppSpacing.xxl,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ProgressRing(
          key: const Key('stat-ring'),
          value: stats.progress,
          label: '${stats.mastered}/${stats.total}',
        ),
        _Stat(key: const Key('stat-cleared'), label: 'Cleared', value: '${stats.mastered}', suffix: ' / ${stats.total}'),
        _Stat(key: const Key('stat-progress'), label: 'Progress', value: '${stats.percent}', suffix: '%'),
        if (!compact) ...[
          _Stat(key: const Key('stat-ready'), label: 'Ready', value: '${stats.ready}'),
          _Stat(key: const Key('stat-audits'), label: 'Audits', value: '${stats.audits}'),
          _Stat(key: const Key('stat-lessons'), label: 'Lessons', value: '${stats.lessons}'),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            text: value,
            style: theme.headlineLarge,
            children: [
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: theme.titleMedium?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin ring with its label in the middle (`5/8`).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.label, this.size = 64});

  /// 0..1.
  final double value;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0.0, 1.0)),
        child: Center(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = AppColors.outline);
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, paint..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
