import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small label chip: `Cleared`, `Passed`, `Failed`, `Ready` ... Colors come
/// in pairs (text on a soft fill).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, required this.fill});

  /// Green: passed, cleared.
  const StatusChip.success(this.label, {super.key})
    : color = AppColors.success,
      fill = AppColors.successSoft;

  /// Red: failed.
  const StatusChip.danger(this.label, {super.key})
    : color = AppColors.danger,
      fill = AppColors.dangerSoft;

  /// Blue: can be challenged.
  const StatusChip.primary(this.label, {super.key})
    : color = AppColors.primary,
      fill = AppColors.primarySoft;

  /// Grey: locked, unknown.
  const StatusChip.neutral(this.label, {super.key})
    : color = AppColors.textSecondary,
      fill = AppColors.surfaceHigh;

  final String label;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: AppRadius.chipBorder),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
