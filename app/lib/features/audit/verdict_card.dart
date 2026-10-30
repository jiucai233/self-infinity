import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';
import 'gap_evidence.dart';

/// What the "⋯" menu of the card can do.
enum _Action { copy, tooHard, misheard }

/// The Auditor's verdict, in the dialogue column of the audit (scene 4-1),
/// short enough to sit on one phone screen: the outcome in the display serif
/// with the score on its baseline, her comment in a line, each knowledge
/// point held or missed, the titles of the gaps (two, then "+N") and the past
/// lessons it touched, one line each. What each gap rests on — the user's own
/// words next to what holds — is on the replay, behind [onDetails].
///
/// The "⋯" menu at the top right copies all of it as text and, on a fail,
/// holds "Too hard for now" / "I didn't say that". A pass gets an ember edge
/// and the XP; a fail offers [onLesson] (the Recorder turns the miss into a
/// lesson card) until that has started.
class VerdictCard extends StatelessWidget {
  const VerdictCard({
    super.key,
    required this.verdict,
    this.onLesson,
    this.onTooHard,
    this.onMisheard,
    this.tooHardNoted = false,
    this.misheardNoted = false,
    this.onDetails,
    required this.onBack,
  });

  final VerdictResult verdict;

  /// "Make a lesson card" (a fail only); null hides it.
  final VoidCallback? onLesson;

  /// "Too hard for now" / "I didn't say that" in the menu (a fail only);
  /// null hides each.
  final VoidCallback? onTooHard;
  final VoidCallback? onMisheard;

  /// Already said: the menu item gives way to a line saying it was noted.
  final bool tooHardNoted;
  final bool misheardNoted;

  /// "See details →": the replay of this audit; null hides it.
  final VoidCallback? onDetails;

  /// Back to the node (scene 4).
  final VoidCallback onBack;

  /// Gap titles shown on the card; the rest is "+N".
  static const maxGaps = 2;

  /// One per gap: what the verdict says it rests on, or the gap alone
  /// (an older verdict).
  List<GapEvidence> get _gaps => verdict.evidence.isNotEmpty
      ? verdict.evidence
      : [for (final gap in verdict.gaps) GapEvidence(gap: gap)];

  /// The verdict as plain text, for the clipboard (with the evidence the card
  /// leaves to the replay).
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

  /// "⋯": copy, and on a fail the two things the user can say about it.
  Widget _menu(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final fail = !verdict.passed;
    PopupMenuEntry<_Action> feedback(
      String name,
      _Action action,
      bool noted,
      String label,
      String done,
    ) => noted
        ? PopupMenuItem<_Action>(
            key: Key('verdict-$name-noted'),
            enabled: false,
            child: Text(done, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          )
        : PopupMenuItem<_Action>(key: Key('verdict-$name'), value: action, child: Text(label));
    return PopupMenuButton<_Action>(
      key: const Key('verdict-more'),
      tooltip: l.more,
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      iconColor: AppColors.textTertiary,
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _Action.copy:
            unawaited(Clipboard.setData(ClipboardData(text: _asText(context))));
            showToast(context, l.copied);
          case _Action.tooHard:
            onTooHard?.call();
          case _Action.misheard:
            onMisheard?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_Action>(key: const Key('verdict-copy'), value: _Action.copy, child: Text(l.copy)),
        if (fail && (onTooHard != null || tooHardNoted))
          feedback('too-hard', _Action.tooHard, tooHardNoted, l.feedbackTooHard, l.feedbackTooHardNoted),
        if (fail && (onMisheard != null || misheardNoted))
          feedback('misheard', _Action.misheard, misheardNoted, l.feedbackMisheard, l.feedbackMisheardNoted),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final passed = verdict.passed;
    final comment = verdict.comment?.trim() ?? '';
    final xp = verdict.rewardAmount;
    final gaps = _gaps;
    final section = theme.labelMedium;
    return Container(
      key: const Key('audit-verdict'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
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
                child: Text(l.verdict, style: theme.labelSmall?.copyWith(letterSpacing: 1.6)),
              ),
              _menu(context),
            ],
          ),
          // The rest keeps the card's inner edge on the right, clear of the menu's touch target.
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        passed ? l.verdictCleared : l.verdictNotYet,
                        key: const Key('verdict-title'),
                        style: theme.displaySmall?.copyWith(
                          color: passed ? AppColors.success : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Text('${verdict.score}', key: const Key('verdict-score'), style: theme.headlineLarge),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l.pointsUnit, style: theme.labelMedium),
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    comment,
                    key: const Key('verdict-comment'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyLarge,
                  ),
                ],
                if (verdict.points.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Text(l.knowledgePoints, style: section),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, point) in verdict.points.indexed)
                    _PointLine(key: Key('verdict-point-$i'), point: point),
                ],
                if (gaps.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(passed ? l.worthSecondLook : l.whatWasMissing, style: section),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, gap) in gaps.take(maxGaps).indexed)
                    _GapLine(
                      key: Key('verdict-gap-$i'),
                      gap: gap.gap,
                      color: passed ? AppColors.textTertiary : AppColors.danger,
                    ),
                  if (gaps.length > maxGaps)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.lg, top: 2),
                      child: Text(
                        '+${gaps.length - maxGaps}',
                        key: const Key('verdict-gaps-more'),
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                ],
                if (verdict.lessons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l.pastLessons, style: section),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, lesson) in verdict.lessons.indexed)
                    Padding(
                      key: Key('verdict-lesson-$i'),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        LessonCheckRow.textOf(context, lesson),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium?.copyWith(
                          color: lesson.held ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                ],
                if (onDetails != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: TextButton(
                      key: const Key('verdict-details'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.textSecondary,
                        textStyle: theme.labelLarge,
                      ),
                      onPressed: onDetails,
                      child: Text(l.verdictDetails),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onLesson != null)
                      FilledButton(
                        key: const Key('audit-next'),
                        onPressed: onLesson,
                        child: Text(l.makeLessonCard),
                      ),
                    TextButton(
                      key: const Key('audit-done'),
                      // Alone, it lines up with the text above it.
                      style: onLesson == null
                          ? TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40))
                          : null,
                      onPressed: onBack,
                      child: Text(l.backToNode),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A knowledge point in one line: ✓ held, ✗ missed, ○ not asked, and its
/// title. Why it was missed is on the replay.
class _PointLine extends StatelessWidget {
  const _PointLine({super.key, required this.point});

  final SkillPoint point;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (icon, color, label) = switch (point.ok) {
      true => (Icons.check_rounded, AppColors.success, l.pointHeld),
      false => (Icons.close_rounded, AppColors.danger, l.pointMissed),
      null => (Icons.circle_outlined, AppColors.textTertiary, l.pointNotAsked),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Icon(icon, size: point.ok == null ? 11 : 15, color: color, semanticLabel: label),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              point.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The title of a gap behind a dot: red on a fail, grey for what is only
/// worth a second look.
class _GapLine extends StatelessWidget {
  const _GapLine({super.key, required this.gap, required this.color});

  final String gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            height: 20,
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              gap,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
