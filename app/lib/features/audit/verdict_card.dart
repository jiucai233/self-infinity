import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';

/// The Auditor's verdict, in the dialogue column of the audit (scene 4-1):
/// the outcome in the display serif, the score, her comment and — the part
/// to learn from — every gap she found.
///
/// A pass gets an ember edge and the XP; a fail offers [onLesson] (the
/// Recorder turns the miss into a lesson card) until that has started.
class VerdictCard extends StatelessWidget {
  const VerdictCard({super.key, required this.verdict, this.onLesson, required this.onBack});

  final VerdictResult verdict;

  /// "Make a lesson card" (a fail only); null hides it.
  final VoidCallback? onLesson;

  /// Back to the node (scene 4).
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final passed = verdict.passed;
    final comment = verdict.comment?.trim() ?? '';
    final xp = verdict.rewardAmount;
    return Container(
      key: const Key('audit-verdict'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: passed ? AppColors.ember : AppColors.outline),
        boxShadow: AppShadows.paper,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VERDICT', style: theme.labelSmall?.copyWith(letterSpacing: 1.6)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  passed ? 'Cleared.' : 'Not yet.',
                  key: const Key('verdict-title'),
                  style: theme.displaySmall?.copyWith(
                    color: passed ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ),
              Text('${verdict.score}', key: const Key('verdict-score'), style: theme.headlineLarge),
              const SizedBox(width: AppSpacing.xs),
              Text('pts', style: theme.labelMedium),
            ],
          ),
          if (passed && xp != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '+$xp XP',
              key: const Key('verdict-xp'),
              style: theme.labelLarge?.copyWith(color: AppColors.xp),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(comment, key: const Key('verdict-comment'), style: theme.bodyLarge),
          ],
          if (verdict.gaps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Text(passed ? 'Worth a second look' : 'What was missing', style: theme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, gap) in verdict.gaps.indexed)
              Padding(
                key: Key('verdict-gap-$i'),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9, right: AppSpacing.md),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: passed ? AppColors.textTertiary : AppColors.danger,
                        ),
                      ),
                    ),
                    Expanded(child: Text(gap, style: theme.bodyMedium)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (onLesson != null)
                FilledButton(
                  key: const Key('audit-next'),
                  onPressed: onLesson,
                  child: const Text('Make a lesson card'),
                ),
              TextButton(
                key: const Key('audit-done'),
                onPressed: onBack,
                child: const Text('Back to node'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
