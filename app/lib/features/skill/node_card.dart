import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// The node card at the top of scene 4, the same card the life tree's sheet
/// shows (`docs/DESIGN.md`, node card): a stack of paper with a kicker
/// (`BOSS` / `NODE`) and the `⋯` [menu] → the title (wraps on a phone) →
/// [chips] on their own line → Best / Attempts / Lessons → the audit history
/// (each row opens its replay) → lesson cards → [actions] (the ink
/// `Take it on`, full width).
class SkillNodeCard extends StatelessWidget {
  const SkillNodeCard({
    super.key,
    required this.overview,
    required this.boss,
    required this.chips,
    required this.lessons,
    this.menu,
    this.actions = const [],
  });

  final SkillOverview overview;
  final bool boss;
  final List<Widget> chips;

  /// The lesson cards made from this node's audits.
  final List<Principle> lessons;
  final Widget? menu;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final audits = overview.audits.where((a) => a.status != AuditStatus.active).toList();
    final best = audits
        .map((a) => a.score)
        .whereType<int>()
        .fold<int?>(null, (m, s) => m == null || s > m ? s : m);
    return _PaperStack(
      key: const Key('skill-node-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (boss ? l.boss : l.node).toUpperCase(),
                    key: const Key('skill-kicker'),
                    style: theme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ?menu,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Text(
              keepAll(overview.skill.title),
              key: const Key('skill-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.headlineMedium,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              key: const Key('skill-chips'),
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg, right: AppSpacing.md),
            child: Row(
              children: [
                _Number(key: const Key('skill-best'), label: l.best, value: best == null ? '—' : '$best'),
                _Number(key: const Key('skill-attempts'), label: l.attempts, value: '${audits.length}'),
                _Number(key: const Key('skill-lessons'), label: l.lessons, value: '${lessons.length}'),
              ],
            ),
          ),
          _SectionLabel(l.auditHistory),
          if (audits.isEmpty)
            Text(
              l.noAuditsYet,
              key: const Key('skill-no-audits'),
              style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
            )
          else
            for (final a in audits.take(8)) _AuditRow(audit: a),
          if (lessons.isNotEmpty) ...[
            _SectionLabel(l.lessonCards),
            for (final p in lessons.take(3)) _LessonRow(lesson: p),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two sheets peek out below the card, like a stack of paper.
class _PaperStack extends StatelessWidget {
  const _PaperStack({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    BoxDecoration sheet(Color color) => BoxDecoration(
      color: color,
      borderRadius: AppRadius.cardBorder,
      border: Border.all(color: AppColors.outline),
      boxShadow: AppShadows.paper,
    );
    return Padding(
      // Room for the sheets behind.
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 16,
            bottom: -12,
            left: 14,
            right: 14,
            child: DecoratedBox(decoration: sheet(AppColors.surfaceHigh)),
          ),
          Positioned.fill(
            top: 8,
            bottom: -6,
            left: 7,
            right: 7,
            child: DecoratedBox(decoration: sheet(AppColors.sidebar)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.cardBorder,
              border: Border.all(color: AppColors.glow.withValues(alpha: 0.7)),
              boxShadow: AppShadows.float,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
    ),
  );
}

/// One big number with its label above.
class _Number extends StatelessWidget {
  const _Number({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          Text(value, style: theme.headlineLarge),
        ],
      ),
    );
  }
}

/// One finished audit: date, verdict, score and a bar as long as the score;
/// a fail not reflected on yet says so. The row opens the audit's replay.
class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.audit});

  final AuditSummary audit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final passed = audit.status == AuditStatus.passed;
    final score = audit.score;
    final color = passed ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, right: AppSpacing.md),
      child: InkWell(
        key: Key('audit-row-${audit.id}'),
        borderRadius: AppRadius.chipBorder,
        onTap: () => context.go(AppRoutes.replay(audit.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatLocal(audit.createdAt, style: DateStyle.monthDay),
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                  Text(
                    audit.status.label(context.l10n),
                    style: theme.labelMedium?.copyWith(color: color),
                  ),
                  if (audit.status == AuditStatus.failed && !audit.reflected) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        context.l10n.notReflectedYet,
                        key: const Key('audit-unreflected'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(score == null ? '—' : '$score', key: const Key('audit-score'), style: theme.labelLarge),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.bar),
                child: LinearProgressIndicator(
                  value: (score ?? 0) / 100,
                  minHeight: 3,
                  color: color,
                  backgroundColor: AppColors.surfaceHigh,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final Principle lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, right: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lesson.title, style: theme.labelLarge),
          if (lesson.misconception case final m? when m.isNotEmpty)
            Text(m, style: theme.bodySmall?.copyWith(color: AppColors.danger)),
        ],
      ),
    );
  }
}
