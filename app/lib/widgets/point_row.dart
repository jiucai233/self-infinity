import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// One knowledge point of a leaf: a mark (held, missed or not asked yet), its
/// title and — when it was missed — what was wrong.
class PointRow extends StatelessWidget {
  const PointRow({super.key, required this.point});

  final SkillPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final (icon, color, label) = switch (point.ok) {
      true => (Icons.check_rounded, AppColors.success, l.pointHeld),
      false => (Icons.close_rounded, AppColors.danger, l.pointMissed),
      null => (Icons.circle_outlined, AppColors.textTertiary, l.pointNotAsked),
    };
    final note = point.note;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: AppSpacing.md),
            child: Icon(icon, size: point.ok == null ? 12 : 16, color: color, semanticLabel: label),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.title, style: theme.bodyMedium),
                if (note != null && note.isNotEmpty)
                  Text(note, style: theme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
