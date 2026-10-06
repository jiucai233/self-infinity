import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../stage/profile_controller.dart';
import '../stage/stage_controller.dart';
import 'stat_strip.dart';
import '../../l10n/l10n.dart';

/// The card that opens when you tap a point of the life tree: a stack of
/// paper (two sheets peek out behind it) with what that point means for you.
///
/// * **Skill** (and a course's root): status, best score, attempts, lessons,
///   the audit history (newest first, a score bar each), lesson cards, and
///   `Take it on` / `Open node`.
/// * **Course**: the same, plus its progress and which main quest it serves.
/// * **Main quest**: progress over its courses, the courses, `Attach a course`.
/// * **You**: your identity, win condition and stakes.
class NodeSheet extends StatelessWidget {
  const NodeSheet({
    super.key,
    required this.node,
    required this.tree,
    required this.onClose,
    required this.onOpenSkill,
    required this.onOutline,
  });

  final LifeNode node;
  final LifeTree tree;
  final VoidCallback onClose;
  final ValueChanged<int> onOpenSkill;

  /// Show this course in the outline view.
  final ValueChanged<int> onOutline;

  static const double width = 360;

  @override
  Widget build(BuildContext context) {
    final body = switch (node.kind) {
      LifeKind.self => _SelfBody(tree: tree),
      LifeKind.goal => _GoalBody(node: node, tree: tree),
      LifeKind.course || LifeKind.skill => _SkillBody(
        key: ValueKey('skill-body-${node.key}'),
        node: node,
        tree: tree,
        onOpenSkill: onOpenSkill,
        onOutline: onOutline,
      ),
    };
    return _PaperStack(
      key: Key('node-sheet-${node.key}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _Kicker(node: node)),
              IconButton(
                key: const Key('node-sheet-close'),
                tooltip: context.l10n.close,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: body,
            ),
          ),
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
    BoxDecoration sheet(Color color, List<BoxShadow> shadow) => BoxDecoration(
      color: color,
      borderRadius: AppRadius.cardBorder,
      border: Border.all(color: AppColors.outline),
      boxShadow: shadow,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: 16,
          bottom: -12,
          left: 14,
          right: 14,
          child: DecoratedBox(decoration: sheet(AppColors.surfaceHigh, AppShadows.paper)),
        ),
        Positioned.fill(
          top: 8,
          bottom: -6,
          left: 7,
          right: 7,
          child: DecoratedBox(decoration: sheet(AppColors.sidebar, AppShadows.paper)),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.cardBorder,
            border: Border.all(color: AppColors.glow.withValues(alpha: 0.7)),
            boxShadow: AppShadows.float,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// `Main quest`, `Course · Boss`, `Node`, `You` over the title.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.node});

  final LifeNode node;

  @override
  Widget build(BuildContext context) {
    final text = switch (node.kind) {
      LifeKind.self => context.l10n.you,
      LifeKind.goal => context.l10n.mainQuest,
      LifeKind.course => node.goalId == null ? context.l10n.sideQuestCourse : context.l10n.course,
      LifeKind.skill => node.boss ? context.l10n.boss : context.l10n.node,
    };
    return Text(
      text.toUpperCase(),
      key: const Key('node-sheet-kicker'),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.md),
    child: Text(
      text,
      key: const Key('node-sheet-title'),
      style: Theme.of(context).textTheme.headlineMedium,
    ),
  );
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

/// Big numbers in a row.
class _Numbers extends StatelessWidget {
  const _Numbers(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Row(
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                  Text(value, style: theme.headlineLarge),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Widget _statusChip(LifeNode n) {
  if (n.status == null) return const SizedBox.shrink();
  if (n.isMastered) return const StatusChip.success('Cleared', key: Key('node-sheet-status'));
  if (n.failed) return const StatusChip.danger('Failed', key: Key('node-sheet-status'));
  if (n.isAvailable) return const StatusChip.primary('Ready', key: Key('node-sheet-status'));
  return const StatusChip.neutral('Locked', key: Key('node-sheet-status'));
}

// ---------------------------------------------------------------------------

class _SkillBody extends StatefulWidget {
  const _SkillBody({
    super.key,
    required this.node,
    required this.tree,
    required this.onOpenSkill,
    required this.onOutline,
  });

  final LifeNode node;
  final LifeTree tree;
  final ValueChanged<int> onOpenSkill;
  final ValueChanged<int> onOutline;

  @override
  State<_SkillBody> createState() => _SkillBodyState();
}

class _SkillBodyState extends State<_SkillBody> {
  late final Future<SkillOverview>? _overview = _load();

  Future<SkillOverview>? _load() {
    final id = widget.node.skillId;
    return id == null ? null : context.read<SelfInfinityApi>().getSkillOverview(id);
  }

  /// The course's name (its root's title), unless this is the course itself.
  String? get _courseName {
    final n = widget.node;
    if (n.kind == LifeKind.course) return null;
    return widget.tree.nodes
        .where((c) => c.kind == LifeKind.course && c.courseId == n.courseId)
        .firstOrNull
        ?.label;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final theme = Theme.of(context).textTheme;
    final lessons = context.select<StageController, List<Principle>>(
      (s) => [
        for (final p in s.lessons)
          if (p.skillId == n.skillId) p,
      ],
    );
    return FutureBuilder<SkillOverview>(
      future: _overview,
      builder: (context, snap) {
        final overview = snap.data;
        final audits = overview?.audits.where((a) => a.status != AuditStatus.active).toList() ?? const [];
        final best = audits.map((a) => a.score).whereType<int>().fold<int?>(
          null,
          (m, s) => m == null || s > m ? s : m,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Title(n.label),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (n.boss && n.status != null) const _BossChip(),
                _statusChip(n),
                if (_courseName != null)
                  Text(_courseName!, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
            if (n.kind == LifeKind.course) _CourseProgress(node: n, tree: widget.tree, onOutline: widget.onOutline),
            if (n.skillId != null)
              _Numbers([
                (context.l10n.best, best == null ? '—' : '$best'),
                (context.l10n.attempts, '${audits.length}'),
                (context.l10n.lessons, '${lessons.length}'),
              ]),
            if (n.skillId != null) ...[
              _SectionLabel(context.l10n.auditHistory),
              if (snap.hasError)
                Text(
                  snap.error is ApiException
                      ? (snap.error! as ApiException).userMessage
                      : context.l10n.somethingWentWrongShort,
                  style: theme.bodySmall?.copyWith(color: AppColors.danger),
                )
              else if (overview == null)
                const LinearProgressIndicator(minHeight: 2)
              else if (audits.isEmpty)
                Text(
                  context.l10n.noAuditsYet,
                  key: const Key('node-sheet-no-audits'),
                  style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                )
              else
                for (final a in audits.take(8)) _AuditRow(audit: a),
            ],
            if (lessons.isNotEmpty) ...[
              _SectionLabel(context.l10n.lessonCards),
              for (final p in lessons.take(3)) _LessonRow(lesson: p),
            ],
            if (n.skillId != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                key: const Key('node-sheet-open'),
                onPressed: () => widget.onOpenSkill(n.skillId!),
                child: Text(n.isLocked ? context.l10n.openNode : context.l10n.takeItOn),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BossChip extends StatelessWidget {
  const _BossChip();

  @override
  Widget build(BuildContext context) =>
      const StatusChip(label: 'Boss', color: AppColors.onAccent, fill: AppColors.primary, key: Key('node-sheet-boss'));
}

/// One finished audit: date, verdict, score, and a bar as long as the score.
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
      key: Key('audit-row-${audit.id}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
              Text(passed ? context.l10n.auditPassed : context.l10n.auditFailed, style: theme.labelMedium?.copyWith(color: color)),
              const Spacer(),
              Text(score == null ? '—' : '$score', style: theme.labelLarge),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lesson.title, style: theme.labelLarge),
          if (lesson.misconception != null && lesson.misconception!.isNotEmpty)
            Text(
              lesson.misconception!,
              style: theme.bodySmall?.copyWith(color: AppColors.danger),
            ),
        ],
      ),
    );
  }
}

/// A course: its progress, the main quest it serves (changeable), and a link
/// to its outline.
class _CourseProgress extends StatelessWidget {
  const _CourseProgress({required this.node, required this.tree, required this.onOutline});

  final LifeNode node;
  final LifeTree tree;
  final ValueChanged<int> onOutline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final skills = tree.skillsOf(node.courseId!);
    final done = skills.where((s) => s.isMastered).length;
    final goals = context.select<StageController, List<Goal>>((s) => s.goals);
    final current = goals.where((g) => g.id == node.goalId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Row(
        children: [
          ProgressRing(
            key: const Key('course-ring'),
            value: skills.isEmpty ? 0 : done / skills.length,
            label: '$done/${skills.length}',
            size: 56,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.serves, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                PopupMenuButton<int>(
                  key: const Key('course-goal-menu'),
                  tooltip: context.l10n.chooseMainQuest,
                  onSelected: (goalId) => unawaited(_attach(context, goals, goalId)),
                  itemBuilder: (_) => [
                    for (final g in goals) PopupMenuItem(value: g.id, child: Text(g.title)),
                    PopupMenuItem(value: -1, child: Text(context.l10n.sideQuestNone)),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          current?.title ?? context.l10n.sideQuest,
                          key: const Key('course-goal'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelLarge,
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('course-outline'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  onPressed: () => onOutline(node.courseId!),
                  child: Text(context.l10n.seeOutline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Moves the course under [goalId] (-1: no main quest).
  Future<void> _attach(BuildContext context, List<Goal> goals, int goalId) async {
    final api = context.read<SelfInfinityApi>();
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final courseId = node.courseId!;
    try {
      if (goalId == -1) {
        final owner = goals.where((g) => g.courseIds.contains(courseId)).firstOrNull;
        if (owner != null) {
          await api.updateGoal(owner.id, courseIds: [for (final c in owner.courseIds) if (c != courseId) c]);
        }
      } else {
        final goal = goals.firstWhere((g) => g.id == goalId);
        await api.updateGoal(goalId, courseIds: [...goal.courseIds.where((c) => c != courseId), courseId]);
      }
      appState.markDataChanged();
    } on ApiException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }
}

// ---------------------------------------------------------------------------

class _GoalBody extends StatelessWidget {
  const _GoalBody({required this.node, required this.tree});

  final LifeNode node;
  final LifeTree tree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final courses = tree.childrenOf(node.key);
    final skills = [for (final c in courses) ...tree.skillsOf(c.courseId!)];
    final done = skills.where((s) => s.isMastered).length;
    final goals = context.select<StageController, List<Goal>>((s) => s.goals);
    final goal = goals.where((g) => g.id == node.goalId).firstOrNull;
    final side = [
      for (final n in tree.childrenOf(LifeTree.selfKey))
        if (n.kind == LifeKind.course) n,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(node.label),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Row(
            children: [
              ProgressRing(
                value: skills.isEmpty ? 0 : done / skills.length,
                label: '$done/${skills.length}',
                size: 56,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  skills.isEmpty
                      ? context.l10n.noCourseServesQuest
                      : context.l10n.questProgress(done, skills.length, courses.length),
                  style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        _SectionLabel(context.l10n.courses),
        if (courses.isEmpty)
          Text('—', style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary)),
        for (final c in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(c.label, style: theme.labelLarge)),
                Text(
                  '${tree.skillsOf(c.courseId!).where((s) => s.isMastered).length}/${tree.skillsOf(c.courseId!).length}',
                  style: theme.labelMedium,
                ),
              ],
            ),
          ),
        if (goal != null && side.isNotEmpty)
          PopupMenuButton<int>(
            key: const Key('goal-attach'),
            tooltip: context.l10n.attachCourse,
            onSelected: (courseId) => unawaited(_attach(context, goal, courseId)),
            itemBuilder: (_) => [
              for (final c in side) PopupMenuItem(value: c.courseId, child: Text(c.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Text(context.l10n.attachCourse, style: theme.labelLarge),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.renameUnderCharacter,
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Future<void> _attach(BuildContext context, Goal goal, int courseId) async {
    final api = context.read<SelfInfinityApi>();
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await api.updateGoal(goal.id, courseIds: [...goal.courseIds, courseId]);
      appState.markDataChanged();
    } on ApiException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }
}

class _SelfBody extends StatelessWidget {
  const _SelfBody({required this.tree});

  final LifeTree tree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final profile = context.select<ProfileController, Profile>((p) => p.profile);
    final goals = context.select<StageController, List<Goal>>((s) => s.goals);
    Widget quote(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(text.isEmpty ? '—' : text, style: theme.bodyMedium),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(profile.identity.isEmpty ? context.l10n.you : profile.identity),
        _Numbers([
          (context.l10n.dotCleared, '${tree.stats.mastered}'),
          (context.l10n.mainQuests, '${goals.length}'),
          (context.l10n.lessons, '${tree.stats.lessons}'),
        ]),
        quote(context.l10n.winCondition, profile.vision),
        quote(context.l10n.stakes, profile.antiVision),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.editUnderCharacter,
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
