import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A gauge of the left panel: the [label] with its numbers (`Lv 2 · 3/5`,
/// `Cleared 4/12`) and the bar itself (height 8, radius 4, `outline` track,
/// [color] fill).
///
/// [value] is 0–1.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
    this.labelColor,
  });

  final String label;
  final double value;
  final Color color;

  /// Defaults to the primary text color.
  final Color? labelColor;

  /// Height of the bar.
  static const double barHeight = 8;

  @override
  Widget build(BuildContext context) {
    final fraction = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          key: const Key('stat-label'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: labelColor ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.bar),
          child: SizedBox(
            height: barHeight,
            child: ColoredBox(
              color: AppColors.outline,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  key: const Key('stat-bar-fill'),
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
