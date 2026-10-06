import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../auth/auth_service.dart';
import '../../app/panel_layout.dart';
import '../../app/router.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../chat/chat_controller.dart';
import 'character_sheet.dart';
import 'profile_controller.dart';
import 'stage_controller.dart';

/// The content of the left panel “My character” (`docs/ux-chat.md` 1.1, 5.7, 6),
/// the same on every scene. Top to bottom, each block folds by tapping its
/// header (all start open; [PanelLayout] remembers the folded ones):
///
/// 1. `Character sheet` — identity line, `Win condition`, `Stakes`, `Rules`
///    (editable in place, [CharacterSheet]).
/// 2. `Stats` — the three bars (level, cleared, condition).
/// 3. `Daily quests` — the steps of the current study plan; a check when the
///    node is cleared or was audited today. A tap opens the node; with no plan
///    a row asks the Guide for quests.
/// 4. `Today` — sleep, meals, journal.
///
/// The blocks scroll; the ◎ settings button stays at the bottom. Reads
/// [StageController]; the same widget fills the drawer on narrow screens. The
/// title bar belongs to the frame.
class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final today = context.select<StageController, DailyCheckIn?>((s) => s.todayCheckIn);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        key: const Key('left-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('left-panel-scroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PanelSection(
                    id: 'character',
                    title: 'Character sheet',
                    child: CharacterSheet(),
                  ),
                  const _SectionDivider(),
                  const _PanelSection(id: 'stats', title: 'Stats', child: _Stats()),
                  const _SectionDivider(),
                  const _DailyQuestsSection(),
                  const _SectionDivider(),
                  _PanelSection(
                    id: 'today',
                    title: 'Today',
                    child: _TodaySummary(checkIn: today),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _SettingsButton(),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Divider(),
  );
}

/// A foldable block whose state lives in [PanelLayout].
class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.id, required this.title, required this.child, this.trailing});

  final String id;
  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<PanelLayout>();
    return CollapsibleSection(
      key: Key('section-$id'),
      toggleKey: Key('toggle-$id'),
      title: title,
      trailing: trailing,
      folded: layout.isSectionFolded(id),
      onToggle: () => layout.toggleSection(id),
      child: child,
    );
  }
}

/// The three stat bars.
class _Stats extends StatelessWidget {
  const _Stats();

  @override
  Widget build(BuildContext context) {
    final facts = context.select<StageController, ProfileFacts?>((s) => s.facts);
    final xp = facts?.xp ?? const XpFacts();
    final nodes = facts?.nodes;
    final mastered = nodes?.mastered ?? 0;
    final total = nodes?.total ?? 0;
    final flag = facts?.condition.flag ?? ConditionFlag.unknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatBar(
          key: const Key('stat-level'),
          label: 'Lv ${xp.level} · ${mastered % 5}/5',
          value: xp.levelProgress,
        ),
        const SizedBox(height: AppSpacing.md),
        StatBar(
          key: const Key('stat-clear'),
          label: 'Cleared $mastered/$total',
          labelColor: AppColors.success,
          value: total == 0 ? 0 : mastered / total,
          color: AppColors.success,
        ),
        const SizedBox(height: AppSpacing.md),
        StatBar(
          key: const Key('stat-condition'),
          label: 'Condition: ${flag.label}',
          labelColor: flag == ConditionFlag.low ? AppColors.danger : AppColors.textPrimary,
          value: flag.fill,
          color: flag.color,
        ),
      ],
    );
  }
}

/// `Daily quests`: the steps of the current plan.
class _DailyQuestsSection extends StatelessWidget {
  const _DailyQuestsSection();

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<StageController>();
    final steps = stage.plan?.steps ?? const <PlanStep>[];
    final done = steps.where(stage.isQuestDone).length;
    return _PanelSection(
      id: 'quests',
      title: 'Daily quests',
      trailing: steps.isEmpty ? null : '$done/${steps.length}',
      child: steps.isEmpty
          ? const _GetQuestsRow()
          : Column(
              key: const Key('daily-quests'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final step in steps) _QuestRow(step: step, done: stage.isQuestDone(step)),
              ],
            ),
    );
  }
}

/// One quest: a check (filled when done), the node's title; a tap opens the node.
class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.step, required this.done});

  final PlanStep step;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      key: Key('quest-${step.skillId}'),
      borderRadius: AppRadius.chipBorder,
      onTap: () => context.go(AppRoutes.skill(step.skillId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            done
                ? const DecoratedBox(
                    key: Key('quest-done'),
                    decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    child: SizedBox.square(
                      dimension: 20,
                      child: Icon(Icons.check_rounded, size: 14, color: AppColors.onAccent),
                    ),
                  )
                : DecoratedBox(
                    key: const Key('quest-open'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.outlineStrong, width: 2),
                    ),
                    child: const SizedBox.square(dimension: 20),
                  ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                step.skillTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyMedium?.copyWith(
                  color: done ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No plan yet: asks the Guide for today's quests (the line goes to the chat
/// and the stage switches to it).
class _GetQuestsRow extends StatelessWidget {
  const _GetQuestsRow();

  /// What the row says to the Guide.
  static const String message = 'What should I do today?';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('get-quests'),
        onTap: () {
          context.read<ChatController>().queueMessage(message);
          context.go(AppRoutes.home);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Text(
            "Get today's quests →",
            style: theme.labelLarge?.copyWith(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.checkIn});

  final DailyCheckIn? checkIn;

  static const String _none = '—';

  @override
  Widget build(BuildContext context) {
    final c = checkIn;
    final diary = (c?.transcript ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(2)
        .join('\n');
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: AppRadius.cardBorder),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          key: const Key('today-summary'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(
              context,
              'Sleep',
              c?.sleepHours == null ? _none : '${formatNumber(c!.sleepHours!)} h',
            ),
            _row(context, 'Meals', (c?.dietNote ?? '').isEmpty ? _none : c!.dietNote!),
            _row(context, 'Journal', diary.isEmpty ? _none : diary, maxLines: 3, last: true),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    int maxLines = 2,
    bool last = false,
  }) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 56, child: Text(label, style: theme.bodySmall)),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// ◎ at the bottom left: the account menu — who is signed in, `Replay the
/// tutorial`, and `Sign out` (only with accounts).
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        key: const Key('settings-button'),
        tooltip: 'Account',
        position: PopupMenuPosition.over,
        offset: const Offset(0, -8),
        onSelected: (value) async {
          switch (value) {
            case 'tutorial':
              await context.read<ProfileController>().setOnboarded(false);
            case 'sign-out':
              await auth.signOut();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signed in as', style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                Text(
                  auth.enabled ? (auth.email ?? '') : 'Local mode (no account)',
                  key: const Key('settings-account'),
                  style: theme.bodyMedium,
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            key: Key('settings-tutorial'),
            value: 'tutorial',
            child: Text('Replay the tutorial'),
          ),
          if (auth.enabled)
            const PopupMenuItem<String>(
              key: Key('settings-sign-out'),
              value: 'sign-out',
              child: Text('Sign out'),
            )
          else
            // Local mode has no account to leave; this shows the front page, and
            // any email and password there come straight back.
            const PopupMenuItem<String>(
              key: Key('settings-front-page'),
              value: 'sign-out',
              child: Text('View the front page'),
            ),
        ],
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
          child: const Icon(Icons.adjust_rounded, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
