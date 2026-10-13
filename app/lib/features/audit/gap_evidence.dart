import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

/// One gap of a verdict with what it rests on: the gap, then the user's own
/// words as a quiet inset quote and what holds instead. A gap without either
/// is the plain bullet row.
///
/// Plain text: the dialogue column and the replay wrap it in a
/// `SelectionArea`, so all of it can be selected and copied.
class GapEvidenceView extends StatelessWidget {
  const GapEvidenceView({super.key, required this.evidence, this.color = AppColors.danger});

  final GapEvidence evidence;

  /// The bullet: red on a fail, grey for what is only worth a second look.
  final Color color;

  /// The gap as plain text, for the clipboard.
  static String asText(BuildContext context, GapEvidence evidence) {
    final l = context.l10n;
    final said = evidence.said?.trim() ?? '';
    final right = evidence.right?.trim() ?? '';
    return [
      '- ${evidence.gap}',
      if (said.isNotEmpty) '  ${l.youSaid}: $said',
      if (right.isNotEmpty) '  ${l.whatHolds}: $right',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final said = evidence.said?.trim() ?? '';
    final right = evidence.right?.trim() ?? '';
    final label = theme.labelSmall?.copyWith(color: AppColors.textTertiary, letterSpacing: 0.4);
    return Padding(
      padding: EdgeInsets.only(
        bottom: said.isEmpty && right.isEmpty ? AppSpacing.sm : AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9, right: AppSpacing.md),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(evidence.gap, style: theme.bodyMedium),
                if (said.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l.youSaid, style: label),
                  const SizedBox(height: AppSpacing.xs),
                  // A quote: a hairline down its left, readable on a card and on the stage.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: AppColors.outlineStrong, width: 2)),
                    ),
                    child: Text(
                      said,
                      style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
                if (right.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l.whatHolds, style: label),
                  const SizedBox(height: AppSpacing.xs),
                  Text(right, style: theme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A past lesson an audit touched, as one line: it held, or the same mistake
/// came back.
class LessonCheckRow extends StatelessWidget {
  const LessonCheckRow({super.key, required this.check});

  final LessonCheck check;

  /// The line itself (also what the clipboard gets).
  static String textOf(BuildContext context, LessonCheck check) =>
      check.held ? context.l10n.lessonHeld(check.title) : context.l10n.lessonCameBack(check.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        textOf(context, check),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: check.held ? AppColors.success : AppColors.danger,
        ),
      ),
    );
  }
}
