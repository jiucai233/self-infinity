import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../auth/auth_service.dart';
import '../../app/app_state.dart';
import '../../app/panel_layout.dart';
import '../../app/router.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../chat/chat_controller.dart';
import '../dev/dev_panel.dart';
import 'character_sheet.dart';
import 'profile_controller.dart';
import 'stage_controller.dart';
import '../../l10n/l10n.dart';

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
                  _PanelSection(
                    id: 'character',
                    title: context.l10n.characterSheet,
                    child: const CharacterSheet(),
                  ),
                  const _SectionDivider(),
                  _PanelSection(id: 'stats', title: context.l10n.stats, child: const _Stats()),
                  const _SectionDivider(),
                  const _DailyQuestsSection(),
                  const _SectionDivider(),
                  _PanelSection(
                    id: 'today',
                    title: context.l10n.today,
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
          label: context.l10n.levelBar(xp.level, mastered % 5),
          value: xp.levelProgress,
        ),
        const SizedBox(height: AppSpacing.md),
        StatBar(
          key: const Key('stat-clear'),
          label: context.l10n.clearedBar(mastered, total),
          labelColor: AppColors.success,
          value: total == 0 ? 0 : mastered / total,
          color: AppColors.success,
        ),
        const SizedBox(height: AppSpacing.md),
        StatBar(
          key: const Key('stat-condition'),
          label: context.l10n.conditionBar(flag.label(context.l10n)),
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
    final summary = stage.plan?.summary ?? '';
    final done = steps.where(stage.isQuestDone).length;
    return _PanelSection(
      id: 'quests',
      title: context.l10n.dailyQuests,
      trailing: steps.isEmpty ? null : '$done/${steps.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The time of day, the condition, the focus left (the server's line).
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
              child: Text(
                summary,
                key: const Key('quests-summary'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          if (steps.isEmpty && summary.isEmpty)
            const _GetQuestsRow()
          else if (steps.isNotEmpty)
            Column(
              key: const Key('daily-quests'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final step in steps) _QuestRow(step: step, done: stage.isQuestDone(step)),
              ],
            ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.skillTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(
                      color: done ? AppColors.textTertiary : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    [
                      switch (step.kind) {
                        QuestKind.learn => context.l10n.questLearn,
                        QuestKind.challenge => context.l10n.questChallenge,
                        QuestKind.review => context.l10n.questReview,
                      },
                      if (step.minutes > 0) context.l10n.questMinutes(step.minutes),
                    ].join(' · '),
                    key: Key('quest-kind-${step.skillId}'),
                    style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
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
  static String get message => l10nNow.askTodaysQuests;

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
            context.l10n.getTodaysQuests,
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
              context.l10n.sleep,
              c?.sleepHours == null ? _none : context.l10n.hoursShort(formatNumber(c!.sleepHours!)),
            ),
            _row(context, context.l10n.meals, (c?.dietNote ?? '').isEmpty ? _none : c!.dietNote!),
            _row(
              context,
              context.l10n.journal,
              diary.isEmpty ? _none : diary,
              maxLines: 3,
              last: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('open-life'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
                onPressed: () => context.go(AppRoutes.life),
                child: Text(context.l10n.lifeOpen),
              ),
            ),
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
/// tutorial`, `Developer` (developers only, `GET /me`), and `Sign out` (only
/// with accounts).
class _SettingsButton extends StatefulWidget {
  const _SettingsButton();

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _dev = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkDev());
  }

  /// Puts the courses into the language just picked, in the background
  /// (`POST /courses/translate`), and reloads them when it is done. Nothing
  /// waits on it; a failure only says so in a snackbar.
  static Future<void> _translateCourses(
    SelfInfinityApi api,
    AppState appState,
    ScaffoldMessengerState? messenger,
    AppLanguage language,
  ) async {
    try {
      final result = await api.translateCourses(language.code);
      if (result.translated > 0) appState.markDataChanged();
      if (result.skipped > 0) _sayTranslationFailed(messenger);
    } on Object {
      _sayTranslationFailed(messenger);
    }
  }

  static void _sayTranslationFailed(ScaffoldMessengerState? messenger) {
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10nNow.coursesTranslateFailed)));
  }

  Future<void> _checkDev() async {
    try {
      final me = await context.read<SelfInfinityApi>().getMe();
      if (mounted && me.isDev) setState(() => _dev = true);
    } on Object {
      // not a developer, as far as we can tell
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final current = context.watch<LocaleController>().language;
    final theme = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        key: const Key('settings-button'),
        tooltip: context.l10n.account,
        position: PopupMenuPosition.over,
        offset: const Offset(0, -8),
        onSelected: (value) async {
          if (value.startsWith('lang:')) {
            final locale = context.read<LocaleController>();
            final language = AppLanguage.fromCode(value.substring(5));
            final changed = language != locale.language;
            final api = context.read<SelfInfinityApi>();
            final appState = context.read<AppState>();
            final messenger = ScaffoldMessenger.maybeOf(context);
            await locale.setLanguage(language);
            if (changed) unawaited(_translateCourses(api, appState, messenger, language));
            return;
          }
          switch (value) {
            case 'tutorial':
              await context.read<ProfileController>().setOnboarded(false);
            case 'licenses':
              showLicensePage(context: context, applicationName: 'Self-Infinity');
            case 'dev':
              await showDevPanel(context);
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
                Text(
                  context.l10n.signedInAs,
                  style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
                Text(
                  auth.enabled ? (auth.email ?? '') : context.l10n.localModeNoAccount,
                  key: const Key('settings-account'),
                  style: theme.bodyMedium,
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(
              context.l10n.language,
              style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          for (final language in AppLanguage.values)
            PopupMenuItem<String>(
              key: Key('settings-language-${language.code}'),
              value: 'lang:${language.code}',
              child: Row(
                children: [
                  Expanded(child: Text(language.nativeName)),
                  if (language == current)
                    const Icon(Icons.check_rounded, size: 18, color: AppColors.textPrimary),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(
              context.l10n.aiModel,
              style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          // Not an entry to pick: the switch inside it takes the taps.
          const PopupMenuItem<String>(enabled: false, child: _ModelSwitch()),
          const PopupMenuItem<String>(enabled: false, child: _VoiceSwitches()),
          const PopupMenuDivider(),
          // Licenses, with the credit 大肥鱼's license asks for.
          PopupMenuItem<String>(
            key: const Key('settings-licenses'),
            value: 'licenses',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(MaterialLocalizations.of(context).licensesPageTitle),
                Text(
                  dafeiyuCredit,
                  key: const Key('settings-credit'),
                  style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            key: const Key('settings-tutorial'),
            value: 'tutorial',
            child: Text(context.l10n.replayTutorial),
          ),
          if (_dev)
            PopupMenuItem<String>(
              key: const Key('settings-dev'),
              value: 'dev',
              child: Text(context.l10n.devPanel),
            ),
          if (auth.enabled)
            PopupMenuItem<String>(
              key: const Key('settings-sign-out'),
              value: 'sign-out',
              child: Text(context.l10n.signOut),
            )
          else
            // Local mode has no account to leave; this shows the front page, and
            // any email and password there come straight back.
            PopupMenuItem<String>(
              key: const Key('settings-front-page'),
              value: 'sign-out',
              child: Text(context.l10n.viewFrontPage),
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

/// OpenAI | Claude: which provider this account's agents (Planner, Auditor
/// and the rest) run on. A provider the server has no key for cannot be
/// chosen. Voice stays with OpenAI either way.
class _ModelSwitch extends StatefulWidget {
  const _ModelSwitch();

  @override
  State<_ModelSwitch> createState() => _ModelSwitchState();
}

class _ModelSwitchState extends State<_ModelSwitch> {
  static const _names = {'openai': 'OpenAI', 'claude': 'Claude'};

  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  LlmStatus? _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final status = await _api.getLlm();
      if (mounted) setState(() => _status = status);
    } on Object {
      // the switch stays off: the server decides
    }
  }

  Future<void> _choose(String provider) async {
    setState(() => _saving = true);
    try {
      final status = await _api.setLlm(provider);
      if (mounted) setState(() => _status = status);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final choices =
        status?.choices ??
        [for (final id in _names.keys) LlmChoice(id: id, model: '', available: false)];
    return SegmentedButton<String>(
      key: const Key('settings-model'),
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      segments: [
        for (final c in choices)
          ButtonSegment(
            value: c.id,
            enabled: c.available && !_saving,
            tooltip: c.model.isEmpty ? null : c.model,
            label: Text(_names[c.id] ?? c.id, key: Key('settings-model-${c.id}')),
          ),
      ],
      selected: {
        if (status != null && choices.any((c) => c.id == status.provider)) status.provider,
      },
      onSelectionChanged: (s) {
        if (s.isNotEmpty) unawaited(_choose(s.first));
      },
    );
  }
}

/// The voices this account uses, one switch each. The home Guide: Live is
/// GPT-Live, Realtime the Realtime model. The audits: Live is GPT-Live, Turns
/// is live transcription where a pause ends the turn. Off while the server has
/// no speech.
class _VoiceSwitches extends StatefulWidget {
  const _VoiceSwitches();

  @override
  State<_VoiceSwitches> createState() => _VoiceSwitchesState();
}

class _VoiceSwitchesState extends State<_VoiceSwitches> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  VoiceStatus? _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final status = await _api.getVoice();
      if (mounted) setState(() => _status = status);
    } on Object {
      // the switches stay off: the server decides
    }
  }

  Future<void> _save({String? guide, String? audit}) async {
    setState(() => _saving = true);
    try {
      final status = await _api.setVoice(guide: guide, audit: audit);
      if (mounted) setState(() => _status = status);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SegmentedButton<String> _switch({
    required Key key,
    required List<(String, Widget)> options,
    required String? selected,
    required void Function(String) onChosen,
  }) {
    final status = _status;
    final enabled = status != null && status.available && !_saving;
    return SegmentedButton<String>(
      key: key,
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      segments: [
        for (final (value, label) in options) ButtonSegment(value: value, enabled: enabled, label: label),
      ],
      selected: {?selected},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChosen(s.first);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final status = _status;
    final label = theme.labelSmall?.copyWith(color: AppColors.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.voiceGuide, style: label),
        const SizedBox(height: AppSpacing.xs),
        _switch(
          key: const Key('settings-voice-guide'),
          options: const [
            ('live', Text('Live', key: Key('settings-voice-guide-live'))),
            ('realtime', Text('Realtime', key: Key('settings-voice-guide-realtime'))),
          ],
          selected: status?.guide,
          onChosen: (v) => unawaited(_save(guide: v)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(context.l10n.voiceAudit, style: label),
        const SizedBox(height: AppSpacing.xs),
        _switch(
          key: const Key('settings-voice-audit'),
          options: [
            ('live', const Text('Live', key: Key('settings-voice-audit-live'))),
            ('turns', Text(context.l10n.voiceTurns, key: const Key('settings-voice-audit-turns'))),
          ],
          selected: status?.audit,
          onChosen: (v) => unawaited(_save(audit: v)),
        ),
      ],
    );
  }
}
