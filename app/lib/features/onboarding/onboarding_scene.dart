import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../widgets/widgets.dart';
import '../stage/profile_controller.dart';
import '../../l10n/l10n.dart';

/// The first-run tutorial (`docs/ux-chat.md` §7): the Guide sets up your
/// character with you, one question at a time, then shows you around.
///
/// Welcome → Stakes → Win condition → Identity → Main quest → First course
/// (a topic or a syllabus file; the course is built and put under the quest)
/// → a three-page tour. Every answer is saved as soon as you continue; every
/// step can be skipped, and `Skip setup` ends it. Finishing (or skipping)
/// sets `onboarded` on the profile, and the app opens.
class OnboardingScene extends StatefulWidget {
  const OnboardingScene({super.key});

  @override
  State<OnboardingScene> createState() => _OnboardingSceneState();
}

enum _Step { welcome, stakes, win, identity, quest, course, tour }

/// What the course step is doing: [reading] is the scout looking at the
/// typed topic before anything is built.
enum _Build { idle, reading, building, done }

class _OnboardingSceneState extends State<OnboardingScene> {
  static String get identityStem => l10nNow.identityStem;

  _Step _step = _Step.welcome;
  final _text = {
    _Step.stakes: TextEditingController(),
    _Step.win: TextEditingController(),
    _Step.identity: TextEditingController(),
    _Step.quest: TextEditingController(),
    _Step.course: TextEditingController(),
  };
  bool _busy = false;
  String? _error;

  Goal? _goal;
  PickedFile? _file;
  _Build _build = _Build.idle;

  /// The scout found the typed topic too vague: courses to pick from.
  CourseScout? _scouted;
  CourseMap? _course;
  int _tourPage = 0;
  LifeTree? _tree;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileController>().profile;
    _text[_Step.stakes]!.text = profile.antiVision;
    _text[_Step.win]!.text = profile.vision;
    _text[_Step.identity]!.text = profile.identity.isEmpty ? identityStem : profile.identity;
    unawaited(_loadGoal());
  }

  /// Replaying the tutorial: the first main quest is edited, not duplicated.
  Future<void> _loadGoal() async {
    try {
      final goals = await context.read<SelfInfinityApi>().listGoals();
      if (!mounted || goals.isEmpty) return;
      setState(() {
        _goal = goals.first;
        _text[_Step.quest]!.text = goals.first.title;
      });
    } on Object {
      // no goals yet, or offline: start empty
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static const List<_Step> _counted = [
    _Step.stakes,
    _Step.win,
    _Step.identity,
    _Step.quest,
    _Step.course,
    _Step.tour,
  ];

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  _Step? get _previous => _step.index == 0 ? null : _Step.values[_step.index - 1];

  void _next() {
    if (_step == _Step.course) unawaited(_loadTree());
    _go(_Step.values[_step.index + 1]);
  }

  /// Saves the answer of this step (if any), then moves on.
  Future<void> _continue() async {
    final text = _text[_step]?.text.trim() ?? '';
    final profile = context.read<ProfileController>();
    final api = context.read<SelfInfinityApi>();
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    switch (_step) {
      case _Step.stakes:
        error = await profile.saveText(ProfileField.antiVision, text);
      case _Step.win:
        error = await profile.saveText(ProfileField.vision, text);
      case _Step.identity:
        if (text != identityStem.trim()) {
          error = await profile.saveText(ProfileField.identity, text);
        }
      case _Step.quest:
        if (text.isNotEmpty) error = await _saveGoal(api, text);
      case _Step.course:
        if (_build == _Build.idle) {
          setState(() => _busy = false);
          await _buildCourse();
          return;
        }
      case _Step.welcome:
      case _Step.tour:
        break;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) _next();
  }

  Future<String?> _saveGoal(SelfInfinityApi api, String title) async {
    try {
      final goal = _goal;
      _goal = goal == null
          ? await api.createGoal(title)
          : await api.updateGoal(goal.id, title: title);
      return null;
    } on ApiException catch (e) {
      return e.userMessage;
    }
  }

  /// Builds the first course in the chat (so the conversation starts with
  /// it), then puts it under the main quest. `courseTopic` skips the front
  /// desk, so the build never hangs on how it would read the message.
  ///
  /// A typed topic is read by the scout first, next to the main quest: a
  /// clear one is built under its tidied title, a vague one ("idk") stops
  /// here with courses to [picked] from. A file is its own syllabus and is
  /// built as it is.
  Future<void> _buildCourse({String? picked}) async {
    final typed = _text[_Step.course]!.text.trim();
    if (picked == null && typed.isEmpty && _file == null) {
      setState(() => _error = context.l10n.onbNeedTopic);
      return;
    }
    final api = context.read<SelfInfinityApi>();
    final appState = context.read<AppState>();
    final l = context.l10n;
    var topic = picked ?? typed;
    if (picked == null && _file == null) {
      setState(() {
        _build = _Build.reading;
        _error = null;
      });
      CourseScout scout;
      try {
        scout = await api.scoutCourse(typed);
      } on ApiException {
        // Reading the topic is a help, never a gate: build what was typed.
        scout = CourseScout(isClear: true, topic: typed);
      }
      if (!mounted) return;
      if (!scout.isClear && scout.options.isNotEmpty) {
        setState(() {
          _scouted = scout;
          _build = _Build.idle;
        });
        return;
      }
      if (scout.topic.trim().isNotEmpty) topic = scout.topic.trim();
    }
    setState(() {
      _build = _Build.building;
      _error = null;
    });
    try {
      final uploads = <int>[];
      final file = _file;
      if (file != null) {
        uploads.add((await api.uploadFile(filename: file.name, bytes: file.bytes)).id);
      }
      final messages = await api.sendChat(
        topic.isEmpty ? l.onbWantToLearnThis : l.onbWantToLearn(topic),
        uploadIds: uploads,
        courseTopic: topic,
      );
      // A failed build is explained in a message without a course action.
      final built = messages.map((m) => m.action).whereType<CourseAction>().firstOrNull;
      if (built == null) throw const ApiException(502, 'no course');
      final map = await api.getCourseMap(built.course.id);
      final goal = _goal;
      if (goal != null) {
        _goal = await api.updateGoal(goal.id, courseIds: [...goal.courseIds, map.course.id]);
      }
      appState.markDataChanged();
      if (!mounted) return;
      setState(() {
        _course = map;
        _build = _Build.done;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _build = _Build.idle;
        _error = e.statusCode == 502 || e.statusCode == null ? l.onbBuildFailed : e.userMessage;
      });
    }
  }

  Future<void> _pickFile() async {
    final file = await context.read<FilePickerService>().pick();
    if (file == null || !mounted) return;
    setState(() {
      if (file.bytes.length > kUploadMaxBytes) {
        _error = context.l10n.uploadBadFile;
      } else {
        _file = file;
        _error = null;
      }
    });
  }

  /// The tree for the first tour page.
  Future<void> _loadTree() async {
    final api = context.read<SelfInfinityApi>();
    try {
      final goals = await api.listGoals();
      final courses = await api.listCourses();
      final maps = await Future.wait([for (final c in courses) api.getCourseMap(c.id)]);
      if (mounted) setState(() => _tree = LifeTree.build(goals: goals, maps: maps));
    } on Object {
      if (mounted) setState(() => _tree = LifeTree.build());
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final appState = context.read<AppState>();
    final error = await context.read<ProfileController>().setOnboarded(true);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    appState.markDataChanged();
  }

  // -- build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppLayout.wideBreakpoint;
    return Scaffold(
      key: const Key('onboarding'),
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppLayout.panelGap),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadius.panelBorder,
            ),
            child: Column(
              children: [
                _topBar(context),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? AppSpacing.xxl : AppSpacing.lg,
                        vertical: AppSpacing.xl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.03),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: Key('onboarding-step-${_step.name}-$_tourPage'),
                            child: _body(context, wide),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final index = _counted.indexOf(_step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (index >= 0) ...[
                  // Phones: the bars alone.
                  if (MediaQuery.sizeOf(context).width >= 600)
                    Flexible(
                      child: Text(
                        context.l10n.onbStepOf(index + 1, _counted.length),
                        key: const Key('onboarding-progress'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  if (MediaQuery.sizeOf(context).width >= 600) const SizedBox(width: AppSpacing.md),
                  for (var i = 0; i < _counted.length; i++)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          constraints: const BoxConstraints(maxWidth: 16),
                          height: 3,
                          decoration: BoxDecoration(
                            color: i <= index ? AppColors.primary : AppColors.outline,
                            borderRadius: BorderRadius.circular(AppRadius.bar),
                          ),
                        ),
                      ),
                    ),
                ] else
                  Flexible(
                    child: Text(
                      'SELF-INFINITY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const Key('onboarding-skip-all'),
            onPressed: _busy || _build == _Build.building ? null : _finish,
            style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
            child: Text(context.l10n.onbSkipSetup),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, bool wide) {
    switch (_step) {
      case _Step.welcome:
        return _Page(
          guideLine: context.l10n.onbHiGuide,
          kicker: null,
          title: context.l10n.onbSetUpCharacter,
          body: context.l10n.onbWelcomeBody,
          wide: wide,
          actions: _actions(
            primary: context.l10n.onbBegin,
            onPrimary: () => _next(),
            showSkip: false,
          ),
        );
      case _Step.stakes:
        return _question(
          wide,
          guideLine: context.l10n.onbStakesGuide,
          kicker: context.l10n.onbStakesKicker,
          title: context.l10n.onbStakesTitle,
          helper: context.l10n.onbStakesHelper,
          hint: context.l10n.onbStakesHint,
          maxLength: Profile.maxTextLength,
        );
      case _Step.win:
        return _question(
          wide,
          guideLine: context.l10n.onbFlipGuide,
          kicker: context.l10n.onbWinKicker,
          title: context.l10n.onbWinTitle,
          helper: context.l10n.onbWinHelper,
          hint: context.l10n.onbWinHint,
          maxLength: Profile.maxTextLength,
        );
      case _Step.identity:
        return _question(
          wide,
          guideLine: context.l10n.onbWhoGuide,
          kicker: context.l10n.onbIdentityKicker,
          title: context.l10n.onbIdentityTitle,
          helper: context.l10n.onbIdentityHelper,
          hint: identityStem,
          maxLength: Profile.maxTextLength,
        );
      case _Step.quest:
        return _question(
          wide,
          guideLine: context.l10n.onbQuestGuide,
          kicker: context.l10n.onbQuestKicker,
          title: context.l10n.onbQuestTitle,
          helper: context.l10n.onbQuestHelper,
          hint: context.l10n.mainQuestPlaceholder,
          maxLength: Goal.maxTitleLength,
          lines: 2,
        );
      case _Step.course:
        return _courseStep(context, wide);
      case _Step.tour:
        return _tourStep(context, wide);
    }
  }

  Widget _question(
    bool wide, {
    required String guideLine,
    required String kicker,
    required String title,
    required String helper,
    required String hint,
    required int maxLength,
    int lines = 4,
  }) {
    return _Page(
      guideLine: guideLine,
      kicker: kicker,
      title: title,
      body: helper,
      wide: wide,
      field: TextField(
        key: const Key('onboarding-input'),
        controller: _text[_step],
        autofocus: true,
        minLines: lines == 2 ? 1 : 3,
        maxLines: lines,
        maxLength: maxLength,
        enabled: !_busy,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: DictationButton(
            controller: _text[_step]!,
            maxLength: maxLength,
            enabled: !_busy,
          ),
          border: OutlineInputBorder(
            borderRadius: AppRadius.cardBorder,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.cardBorder,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.cardBorder,
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
      error: _error,
      actions: _actions(primary: context.l10n.continueLabel, onPrimary: _continue),
    );
  }

  Widget _courseStep(BuildContext context, bool wide) {
    final theme = Theme.of(context).textTheme;
    final quest = _goal?.title;
    if (_build == _Build.building || _build == _Build.reading) {
      final reading = _build == _Build.reading;
      return _Page(
        guideLine: context.l10n.onbMomentGuide,
        kicker: context.l10n.onbCourseKicker,
        title: reading ? context.l10n.onbReadingTitle : context.l10n.onbBuildingTitle,
        body: reading ? context.l10n.onbReadingBody : context.l10n.onbBuildingBody,
        wide: wide,
        field: Padding(
          key: Key(reading ? 'onboarding-reading' : 'onboarding-building'),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: const ThinkingShimmer(),
        ),
        actions: const SizedBox.shrink(),
      );
    }
    if (_build == _Build.done && _course != null) {
      final course = _course!;
      return _Page(
        guideLine: context.l10n.onbDoneGuide,
        kicker: context.l10n.onbCourseKicker,
        title: context.l10n.onbWorldReady(courseNameOf(course)),
        body: quest == null
            ? context.l10n.onbNodesToProve(course.nodes.length)
            : context.l10n.onbNodesToProveUnder(course.nodes.length, quest),
        wide: wide,
        actions: _actions(primary: context.l10n.continueLabel, onPrimary: _next, showSkip: false),
      );
    }
    final file = _file;
    final scouted = _scouted;
    return _Page(
      guideLine: context.l10n.onbSkillsGuide,
      kicker: context.l10n.onbCourseKicker,
      title: scouted != null
          ? context.l10n.onbPickTitle
          : quest == null
          ? context.l10n.onbLearnFirst
          : context.l10n.onbLearnFirstFor(quest),
      body: scouted == null
          ? context.l10n.onbTopicBody
          : scouted.question.isNotEmpty
          ? scouted.question
          : context.l10n.onbPickBody,
      wide: wide,
      field: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scouted != null) ...[
            for (final (i, option) in scouted.options.indexed)
              _ScoutOptionTile(
                key: Key('onboarding-option-$i'),
                option: option,
                onTap: () => _buildCourse(picked: option.topic),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            key: const Key('onboarding-input'),
            controller: _text[_Step.course],
            autofocus: true,
            maxLength: 120,
            style: theme.bodyLarge,
            onSubmitted: (_) => _continue(),
            decoration: InputDecoration(
              hintText: context.l10n.onbTopicHint,
              suffixIcon: DictationButton(controller: _text[_Step.course]!, maxLength: 120),
              border: OutlineInputBorder(
                borderRadius: AppRadius.cardBorder,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.cardBorder,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.cardBorder,
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (file == null)
            OutlinedButton.icon(
              key: const Key('onboarding-upload'),
              onPressed: _pickFile,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(context.l10n.onbUseSyllabusFile),
            )
          else
            InputChip(
              key: const Key('onboarding-file'),
              avatar: const Icon(Icons.description_outlined, size: 16),
              label: Text(file.name),
              onDeleted: () => setState(() => _file = null),
            ),
        ],
      ),
      error: _error,
      actions: _actions(primary: context.l10n.onbBuildIt, onPrimary: _continue),
    );
  }

  Widget _tourStep(BuildContext context, bool wide) {
    final l = context.l10n;
    final pages = [
      (l.tourBallKicker, l.tourBallTitle, l.tourBallBody),
      (l.tourProveKicker, l.tourProveTitle, l.tourProveBody),
      (l.tourLessonsKicker, l.tourLessonsTitle, l.tourLessonsBody),
    ];
    final (kicker, title, body) = pages[_tourPage];
    final last = _tourPage == pages.length - 1;
    final Widget visual = switch (_tourPage) {
      0 => ClipOval(
        child: Container(
          key: const Key('onboarding-ball'),
          width: 200,
          height: 200,
          color: AppColors.night,
          child: LifeConstellation(tree: _tree ?? LifeTree.build(), compact: true),
        ),
      ),
      1 => const Avatar(agent: 'auditor', mood: AvatarMood.neutral, size: 160),
      _ => const Avatar(agent: 'recorder', mood: AvatarMood.smile, size: 160),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: visual),
        const SizedBox(height: AppSpacing.xl),
        _Page(
          guideLine: null,
          kicker: kicker,
          title: title,
          body: body,
          wide: wide,
          error: _error,
          actions: Row(
            children: [
              TextButton(
                key: const Key('onboarding-back'),
                onPressed: _busy
                    ? null
                    : () => _tourPage == 0 ? _go(_Step.course) : setState(() => _tourPage--),
                child: Text(context.l10n.back),
              ),
              const Spacer(),
              Text(
                '${_tourPage + 1} / ${pages.length}',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.lg),
              FilledButton(
                key: Key(last ? 'onboarding-finish' : 'onboarding-continue'),
                onPressed: _busy ? null : (last ? _finish : () => setState(() => _tourPage++)),
                child: Text(last ? context.l10n.enterApp : context.l10n.tourNext),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions({
    required String primary,
    required VoidCallback onPrimary,
    bool showSkip = true,
  }) {
    final previous = _previous;
    return Row(
      children: [
        if (previous != null && previous != _Step.welcome || _step == _Step.stakes)
          TextButton(
            key: const Key('onboarding-back'),
            onPressed: _busy ? null : () => _go(previous!),
            child: Text(context.l10n.back),
          ),
        const Spacer(),
        if (showSkip)
          TextButton(
            key: const Key('onboarding-skip'),
            onPressed: _busy ? null : _next,
            style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
            child: Text(context.l10n.skip),
          ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          key: const Key('onboarding-continue'),
          onPressed: _busy ? null : onPrimary,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary),
                )
              : Text(primary),
        ),
      ],
    );
  }
}

/// One page of the tutorial: the Guide with her line, a kicker, the question
/// as a headline, a helper line, the field and the buttons.
class _Page extends StatelessWidget {
  const _Page({
    required this.guideLine,
    required this.kicker,
    required this.title,
    required this.body,
    required this.wide,
    required this.actions,
    this.field,
    this.error,
  });

  final String? guideLine;
  final String? kicker;
  final String title;
  final String body;
  final bool wide;
  final Widget? field;
  final String? error;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (guideLine != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Avatar(agent: 'front_desk', mood: AvatarMood.smile, size: wide ? 112 : 84),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(bottom: wide ? 56 : 40),
                  child: SpeechBubble(
                    key: const Key('onboarding-guide'),
                    speaker: 'front_desk',
                    tail: BubbleTail.left,
                    maxWidth: 320,
                    child: Text(guideLine!, style: theme.bodyLarge),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (kicker != null) ...[
          Text(
            kicker!,
            style: theme.labelSmall?.copyWith(color: AppColors.textTertiary, letterSpacing: 1.6),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          title,
          key: const Key('onboarding-title'),
          style: wide ? theme.displaySmall : theme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(body, style: theme.bodyLarge?.copyWith(color: AppColors.textTertiary)),
        if (field != null) ...[const SizedBox(height: AppSpacing.xl), field!],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error!,
            key: const Key('onboarding-error'),
            style: theme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        actions,
      ],
    );
  }
}

/// One course the scout offers: its title, why it helps, tap to build it.
class _ScoutOptionTile extends StatelessWidget {
  const _ScoutOptionTile({super.key, required this.option, required this.onTap});

  final ScoutOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadius.cardBorder,
        child: InkWell(
          borderRadius: AppRadius.cardBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.topic, style: theme.titleSmall),
                      if (option.why.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          option.why,
                          style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.arrow_forward, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
