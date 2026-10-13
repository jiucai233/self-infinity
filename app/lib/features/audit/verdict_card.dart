import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';
import 'gap_evidence.dart';

/// The Auditor's verdict, in the dialogue column of the audit (scene 4-1):
/// the outcome in the display serif, the score, her comment and — the part
/// to learn from — each knowledge point (held or missed, and why), every
/// gap she found with the user's own words next to what holds, and the past
/// lessons that held or came back. The copy button takes all of it as text.
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

  /// One per gap: what the verdict says it rests on, or the gap alone
  /// (an older verdict).
  List<GapEvidence> get _gaps => verdict.evidence.isNotEmpty
      ? verdict.evidence
      : [for (final gap in verdict.gaps) GapEvidence(gap: gap)];

  /// The verdict as plain text, for the clipboard.
  String _asText(BuildContext context) {
    final l = context.l10n;
    final comment = verdict.comment?.trim() ?? '';
    return [
      '${verdict.passed ? l.verdictCleared : l.verdictNotYet} · ${verdict.score}',
      if (comment.isNotEmpty) comment,
      for (final p in verdict.points)
        '${p.ok == true
            ? '✓'
            : p.ok == false
            ? '✗'
            : '○'} ${p.title}${p.note == null ? '' : ' — ${p.note}'}',
      for (final gap in _gaps) GapEvidenceView.asText(context, gap),
      for (final lesson in verdict.lessons) LessonCheckRow.textOf(context, lesson),
    ].join('\n');
  }

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
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.verdict,
                  style: theme.labelSmall?.copyWith(letterSpacing: 1.6),
                ),
              ),
              IconButton(
                key: const Key('verdict-copy'),
                tooltip: context.l10n.copy,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: AppColors.textTertiary,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: _asText(context))));
                  showToast(context, context.l10n.copied);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  passed ? context.l10n.verdictCleared : context.l10n.verdictNotYet,
                  key: const Key('verdict-title'),
                  style: theme.displaySmall?.copyWith(
                    color: passed ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ),
              Text('${verdict.score}', key: const Key('verdict-score'), style: theme.headlineLarge),
              const SizedBox(width: AppSpacing.xs),
              Text(context.l10n.pointsUnit, style: theme.labelMedium),
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
          if (verdict.points.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l10n.knowledgePoints, style: theme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, point) in verdict.points.indexed)
              PointRow(key: Key('verdict-point-$i'), point: point),
          ],
          if (_gaps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Text(passed ? context.l10n.worthSecondLook : context.l10n.whatWasMissing, style: theme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, gap) in _gaps.indexed)
              GapEvidenceView(
                key: Key('verdict-gap-$i'),
                evidence: gap,
                color: passed ? AppColors.textTertiary : AppColors.danger,
              ),
          ],
          if (verdict.lessons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l10n.pastLessons, style: theme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, lesson) in verdict.lessons.indexed)
              LessonCheckRow(key: Key('verdict-lesson-$i'), check: lesson),
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
                  child: Text(context.l10n.makeLessonCard),
                ),
              TextButton(
                key: const Key('audit-done'),
                onPressed: onBack,
                child: Text(context.l10n.backToNode),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
