import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/panel_layout.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'inline_edit_field.dart';
import 'profile_controller.dart';
import 'stage_controller.dart';
import '../../l10n/l10n.dart';

/// The top of the left panel (`docs/ux-chat.md` §6.1): an identity line, two
/// editable cards — `Win condition` (vision) and `Stakes` (anti-vision) —,
/// `Main quests` (at most three one-year goals, the first ring of the life
/// tree) and `Rules` (at most five constraints). Everything is edited in
/// place; the profile is saved with `PUT /api/profile`, quests with the goal
/// endpoints.
class CharacterSheet extends StatelessWidget {
  const CharacterSheet({super.key});

  /// What an empty identity line starts with.
  static String get identityStem => l10nNow.identityStem;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final profile = controller.profile;
    final theme = Theme.of(context).textTheme;
    return Column(
      key: const Key('character-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: InlineEditField(
              key: const Key('field-identity'),
              inputKey: const Key('identity-input'),
              value: profile.identity,
              placeholder: context.l10n.identityPlaceholder,
              prefill: context.l10n.identityStem,
              maxLength: Profile.maxTextLength,
              maxLines: 4,
              displayLines: 2,
              // The identity line reads as a quote: the display serif, italic.
              textStyle: AppTheme.serif(theme.headlineSmall)?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
              onSave: (text) => controller.saveText(ProfileField.identity, text),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InlineEditField(
          key: const Key('field-vision'),
          inputKey: const Key('vision-input'),
          variant: InlineEditVariant.card,
          label: context.l10n.winCondition,
          value: profile.vision,
          placeholder: context.l10n.winConditionPlaceholder,
          maxLength: Profile.maxTextLength,
          maxLines: 5,
          displayLines: 2,
          onSave: (text) => controller.saveText(ProfileField.vision, text),
        ),
        const SizedBox(height: AppSpacing.sm),
        InlineEditField(
          key: const Key('field-anti-vision'),
          inputKey: const Key('anti-vision-input'),
          variant: InlineEditVariant.card,
          label: context.l10n.stakes,
          value: profile.antiVision,
          placeholder: context.l10n.stakesPlaceholder,
          maxLength: Profile.maxTextLength,
          maxLines: 5,
          displayLines: 2,
          onSave: (text) => controller.saveText(ProfileField.antiVision, text),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _MainQuestsBlock(),
        _RulesBlock(rules: profile.rules, controller: controller),
      ],
    );
  }
}

/// `Rules`: up to [Profile.maxRules] one-line constraints. Tap a rule to edit
/// it (emptying it removes it), ✕ removes it, `Add a rule` appends one.
class _RulesBlock extends StatefulWidget {
  const _RulesBlock({required this.rules, required this.controller});

  final List<String> rules;
  final ProfileController controller;

  @override
  State<_RulesBlock> createState() => _RulesBlockState();
}

class _RulesBlockState extends State<_RulesBlock> {
  bool _adding = false;
  String? _removeError;

  Future<String?> _replace(int index, String text) {
    final next = [...widget.rules];
    if (text.isEmpty) {
      next.removeAt(index);
    } else {
      next[index] = text;
    }
    return widget.controller.saveRules(next);
  }

  Future<String?> _add(String text) async {
    final error = await widget.controller.saveRules([...widget.rules, text]);
    if (error == null && mounted) setState(() => _adding = false);
    return error;
  }

  Future<void> _remove(int index) async {
    final error = await _replace(index, '');
    if (mounted) setState(() => _removeError = error);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<PanelLayout>();
    final theme = Theme.of(context).textTheme;
    final rules = widget.rules;
    return CollapsibleSection(
      compact: true,
      title: context.l10n.rules,
      trailing: '${rules.length}/${Profile.maxRules}',
      toggleKey: const Key('toggle-rules'),
      folded: layout.isSectionFolded('rules'),
      onToggle: () => layout.toggleSection('rules'),
      child: Column(
        key: const Key('rules'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rules.length; i++)
            Row(
              key: ValueKey('rule-$i-${rules[i]}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 11, right: AppSpacing.sm),
                  child: SizedBox.square(
                    dimension: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InlineEditField(
                    key: Key('rule-$i'),
                    inputKey: Key('rule-input-$i'),
                    value: rules[i],
                    placeholder: '',
                    maxLength: Profile.maxRuleLength,
                    maxLines: 3,
                    displayLines: 1,
                    onSave: (text) => _replace(i, text),
                  ),
                ),
                IconButton(
                  key: Key('rule-remove-$i'),
                  tooltip: context.l10n.removeRule,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
          if (_removeError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                context.l10n.saveFailed('$_removeError'),
                key: const Key('rules-error'),
                style: theme.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ),
          if (rules.length < Profile.maxRules)
            _adding
                ? Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md + 5),
                    child: InlineEditField(
                      key: const Key('rule-new'),
                      inputKey: const Key('rule-new-input'),
                      value: '',
                      startEditing: true,
                      placeholder: context.l10n.rulePlaceholder,
                      maxLength: Profile.maxRuleLength,
                      maxLines: 3,
                      onSave: _add,
                      onClosed: () => setState(() => _adding = false),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('rule-add'),
                      onPressed: () => setState(() {
                        _adding = true;
                        _removeError = null;
                      }),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(context.l10n.addRule),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: theme.labelMedium,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}

/// `Main quests`: up to [Goal.maxGoals] one-year goals. Tap one to rename it
/// (emptying it deletes it), ✕ deletes it, `Add a main quest` appends one.
/// Courses are attached on the life tree (scene 2).
class _MainQuestsBlock extends StatefulWidget {
  const _MainQuestsBlock();

  @override
  State<_MainQuestsBlock> createState() => _MainQuestsBlockState();
}

class _MainQuestsBlockState extends State<_MainQuestsBlock> {
  bool _adding = false;
  String? _error;

  /// Runs [call]; on success the stage reloads (the tree changes shape).
  Future<String?> _run(Future<Object?> Function(SelfInfinityApi api) call) async {
    final api = context.read<SelfInfinityApi>();
    final appState = context.read<AppState>();
    try {
      await call(api);
      appState.markDataChanged();
      return null;
    } on ApiException catch (e) {
      return e.userMessage;
    }
  }

  Future<String?> _rename(Goal goal, String text) =>
      _run((api) => text.isEmpty ? api.deleteGoal(goal.id) : api.updateGoal(goal.id, title: text));

  Future<String?> _add(String text) async {
    if (text.isEmpty) {
      setState(() => _adding = false);
      return null;
    }
    final error = await _run((api) => api.createGoal(text));
    if (error == null && mounted) setState(() => _adding = false);
    return error;
  }

  Future<void> _remove(Goal goal) async {
    final error = await _run((api) => api.deleteGoal(goal.id));
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<PanelLayout>();
    final goals = context.select<StageController, List<Goal>>((s) => s.goals);
    final theme = Theme.of(context).textTheme;
    return CollapsibleSection(
      compact: true,
      title: context.l10n.mainQuests,
      trailing: '${goals.length}/${Goal.maxGoals}',
      toggleKey: const Key('toggle-main-quests'),
      folded: layout.isSectionFolded('main-quests'),
      onToggle: () => layout.toggleSection('main-quests'),
      child: Column(
        key: const Key('main-quests'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in goals)
            Row(
              key: ValueKey('goal-${g.id}-${g.title}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: AppSpacing.sm),
                  child: Icon(Icons.flag_outlined, size: 14, color: AppColors.textSecondary),
                ),
                Expanded(
                  child: InlineEditField(
                    key: Key('goal-${g.id}'),
                    inputKey: Key('goal-input-${g.id}'),
                    value: g.title,
                    placeholder: '',
                    maxLength: Goal.maxTitleLength,
                    maxLines: 2,
                    displayLines: 1,
                    textStyle: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    onSave: (text) => _rename(g, text),
                  ),
                ),
                IconButton(
                  key: Key('goal-remove-${g.id}'),
                  tooltip: context.l10n.removeMainQuest,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
                  onPressed: () => _remove(g),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                context.l10n.saveFailed('$_error'),
                key: const Key('main-quests-error'),
                style: theme.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ),
          if (goals.length < Goal.maxGoals)
            _adding
                ? Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md + 10),
                    child: InlineEditField(
                      key: const Key('goal-new'),
                      inputKey: const Key('goal-new-input'),
                      value: '',
                      startEditing: true,
                      placeholder: context.l10n.mainQuestPlaceholder,
                      maxLength: Goal.maxTitleLength,
                      maxLines: 2,
                      onSave: _add,
                      onClosed: () => setState(() => _adding = false),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('goal-add'),
                      onPressed: () => setState(() {
                        _adding = true;
                        _error = null;
                      }),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(context.l10n.addMainQuest),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: theme.labelMedium,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
