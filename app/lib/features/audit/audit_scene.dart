import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/live_voice.dart';
import '../../voice/voice_mode.dart';
import '../../voice/voice_service.dart';
import '../../widgets/widgets.dart';
import '../stage/stage_controller.dart';
import '../stage/stage_input_bar.dart';
import '../stage/stage_scaffold.dart';
import 'celebration_card.dart';
import 'lesson_card.dart';
import 'verdict_card.dart';
import '../../l10n/l10n.dart';

/// Scene 4-1 of `docs/ux-chat.md`: the audit as one dialogue column.
///
/// The speaker (the Auditor, later the Recorder) sits small at the top, with
/// her mood. Below, the whole Q&A reads top to bottom: past turns small and
/// grey, the current question large in the display serif, the user's answers
/// as bubbles on the right. The verdict is a card in the column — outcome,
/// score, comment and every gap. On a fail, "Make a lesson card" brings the
/// Recorder (`What did you misunderstand?`); the answer becomes a lesson card
/// that flips over in the column, and material is searched for the first gap
/// in the background. A pass also floats a [CelebrationCard] up (XP, level up,
/// the nodes it opened). To try again, go back to scene 4.
///
/// Route `/skill/:id/audit`. Starts a session when opened.
class AuditScene extends StatefulWidget {
  const AuditScene({super.key, required this.skillId, this.testOut = false});

  /// The node to challenge.
  final int skillId;

  /// A challenge on the whole branch: pass it and everything under it is
  /// cleared.
  final bool testOut;

  @override
  State<AuditScene> createState() => _AuditSceneState();
}

/// What a line of the dialogue is.
enum _Kind { say, verdict, lesson }

/// One line of the dialogue column.
class _Line {
  _Line({
    required this.fromUser,
    required this.text,
    this.agent = 'auditor',
    this.kind = _Kind.say,
  });

  final bool fromUser;
  final String text;
  final String agent;

  /// A verdict line is drawn as the [VerdictCard], a lesson line also gets the
  /// [LessonCard].
  final _Kind kind;
}

/// What the celebration card shows, collected after a pass.
class _Celebration {
  const _Celebration({
    required this.verdict,
    this.levelBefore,
    this.levelAfter,
    this.unlocked = const [],
  });

  final VerdictResult verdict;
  final int? levelBefore;
  final int? levelAfter;
  final List<UnlockedNode> unlocked;
}

class _AuditSceneState extends State<AuditScene> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  late final AppState _appState = context.read<AppState>();
  late final StageController _stats = context.read<StageController>();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final VoiceModeController _voiceMode;

  // Loading of the room.
  bool _starting = true;
  Object? _startError;
  String _title = '';
  AuditSession? _session;

  // Dialogue.
  final List<_Line> _lines = [];
  bool _sending = false;
  String? _problem; // shown in the bubble in place of her line
  bool _closed = false;

  // Result.
  VerdictResult? _verdict;
  bool _recorderAsks = false;
  Principle? _principle;
  _Celebration? _celebration;
  bool _celebrationOpen = false;

  bool get _failed => _verdict != null && !_verdict!.passed;

  /// Whether the input bar takes an answer right now.
  bool get _inputOpen {
    if (_session == null || _closed) return false;
    if (_verdict == null) return true;
    return _failed && _recorderAsks && _principle == null;
  }

  @override
  void initState() {
    super.initState();
    _voiceMode = VoiceModeController(
      // Live transcription and streamed speech where there is live voice.
      voice: context.read<LiveVoice?>()?.conversation ?? context.read<VoiceService>(),
      onHeard: _onHeard,
      onUnavailable: () => showToast(context, context.l10n.voiceModeUnavailable),
    );
    unawaited(_start());
  }

  @override
  void dispose() {
    _voiceMode.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _startError = null;
      _session = null;
      _lines.clear();
      _sending = false;
      _problem = null;
      _closed = false;
      _verdict = null;
      _recorderAsks = false;
      _principle = null;
      _celebration = null;
      _celebrationOpen = false;
      _input.clear();
    });
    try {
      final overview = await _api.getSkillOverview(widget.skillId);
      final start = await _api.startAudit(widget.skillId, testOut: widget.testOut);
      if (!mounted) return;
      setState(() {
        _title = overview.skill.title;
        _session = start.session;
        _lines.addAll([
          for (final t in start.session.turns) _Line(fromUser: t.isUser, text: t.content),
        ]);
        if (_lines.isEmpty) _lines.add(_Line(fromUser: false, text: start.openingQuestion));
        _starting = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _startError = e;
        _starting = false;
      });
    }
  }

  // -- the input bar ---------------------------------------------------------------

  /// Sends the text typed (or spoken) as the answer, or — after the Recorder
  /// asked — as the reflection. Returns what to read aloud in voice mode.
  Future<String?> _handleInput(String raw, {bool restoreOnError = true}) {
    if (!_inputOpen || _sending) return Future.value();
    return _verdict == null
        ? _sendAnswer(raw, restoreOnError: restoreOnError)
        : _submitReflection(raw, restoreOnError: restoreOnError);
  }

  Future<String?> _sendAnswer(String raw, {required bool restoreOnError}) async {
    final session = _session;
    final text = raw.trim();
    if (session == null || text.isEmpty) return null;
    final line = _Line(fromUser: true, text: text);
    setState(() {
      _sending = true;
      _problem = null;
      _lines.add(line);
      _input.clear();
    });
    try {
      final levelBefore = _stats.facts?.xp.level;
      final result = await _api.submitTurn(session.id, text);
      if (!mounted) return null;
      switch (result) {
        case ProbeResult(:final question):
          setState(() {
            _lines.add(_Line(fromUser: false, text: question));
            _sending = false;
          });
          return question;
        case VerdictResult():
          setState(() {
            _verdict = result;
            _lines.add(_Line(fromUser: false, text: _verdictLine(result), kind: _Kind.verdict));
            _sending = false;
          });
          _appState.markDataChanged();
          if (result.passed) unawaited(_celebrate(result, levelBefore));
          return _verdictLine(result);
      }
    } on Object catch (e) {
      if (!mounted) return null;
      _fail(e, text, line: line, restoreOnError: restoreOnError);
    }
    return null;
  }

  /// A pass: refresh the stats (the level may have gone up), look up the titles
  /// of the nodes it opened and float the celebration card up.
  Future<void> _celebrate(VerdictResult verdict, int? levelBefore) async {
    await _stats.refresh();
    var unlocked = <UnlockedNode>[];
    if (verdict.unlockedSkillIds.isNotEmpty) {
      try {
        final all = await _api.listSkills();
        final byId = {for (final n in all) n.id: n};
        unlocked = [
          for (final id in verdict.unlockedSkillIds)
            if (byId[id] != null) UnlockedNode(id: id, title: byId[id]!.title),
        ];
      } on Object {
        // The chips are a nicety.
      }
    }
    if (!mounted) return;
    setState(() {
      _celebration = _Celebration(
        verdict: verdict,
        levelBefore: levelBefore,
        levelAfter: _stats.facts?.xp.level,
        unlocked: unlocked,
      );
      _celebrationOpen = true;
    });
  }

  Future<String?> _submitReflection(String raw, {required bool restoreOnError}) async {
    final session = _session;
    final text = raw.trim();
    if (session == null || text.isEmpty) return null;
    final line = _Line(fromUser: true, text: text);
    setState(() {
      _sending = true;
      _problem = null;
      _lines.add(line);
      _input.clear();
    });
    try {
      final principle = await _api.submitReflection(session.id, text);
      if (!mounted) return null;
      setState(() {
        _principle = principle;
        _lines.add(
          _Line(fromUser: false, agent: 'recorder', text: context.l10n.lessonCardCreated, kind: _Kind.lesson),
        );
        _sending = false;
      });
      _appState.markDataChanged();
      unawaited(_searchFirstGap());
      return context.l10n.lessonCardCreated;
    } on Object catch (e) {
      if (!mounted) return null;
      _fail(e, text, line: line, restoreOnError: restoreOnError);
    }
    return null;
  }

  /// A call failed: her bubble says why and the text goes back to the input
  /// (a closed session cannot go on).
  void _fail(Object e, String text, {_Line? line, required bool restoreOnError}) {
    final closed = e is ApiException && e.isAuditClosed;
    setState(() {
      _sending = false;
      if (line != null) _lines.remove(line);
      _problem = ErrorView.messageFor(e);
      if (closed) _closed = true;
      if (restoreOnError) _input.text = text;
    });
  }

  Future<VoiceReply> _onHeard(String heard) async {
    final spoken = await _handleInput(heard, restoreOnError: false);
    return (speak: spoken, keepGoing: _inputOpen);
  }

  /// In the background: material for the first gap, which shows up in the
  /// contents card of scene 4. Failures are ignored.
  Future<void> _searchFirstGap() async {
    final gaps = _verdict?.gaps ?? const [];
    if (gaps.isEmpty) return;
    try {
      await _api.createSearchPlan(widget.skillId, gap: gaps.first);
      _appState.markDataChanged();
    } on Object {
      // The materials are a nicety.
    }
  }

  // -- her line ------------------------------------------------------------------------

  String _verdictLine(VerdictResult v) {
    if (v.passed) {
      final xp = v.rewardAmount == null ? '' : ' · +${v.rewardAmount} XP';
      return '${context.l10n.clearedWithScore(v.score)}$xp';
    }
    final comment = v.comment ?? '';
    return comment.isEmpty ? context.l10n.notQuite : '${context.l10n.notQuite} $comment';
  }

  /// The chip in the title bar.
  Widget _statusChip() {
    final verdict = _verdict;
    final l = context.l10n;
    if (verdict == null) {
      return StatusChip.primary(_session?.testOut ?? false ? l.challengeInProgress : l.auditInProgress);
    }
    return verdict.passed ? StatusChip.success(l.auditPassed) : StatusChip.danger(l.auditFailed);
  }

  void _askRecorder() => setState(() {
    _recorderAsks = true;
    _lines.add(_Line(fromUser: false, agent: 'recorder', text: context.l10n.recorderAsk));
  });

  /// What was in the column when it last scrolled to the bottom.
  Object? _followed;

  /// Keeps the newest line in view — only when something was added, so that
  /// scrolling back up to read is left alone.
  void _followBottom() {
    final now = (_lines.length, _sending, _problem, _principle?.id);
    if (now == _followed) return;
    _followed = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  // -- build -------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StageScaffold(
      title: _title.isEmpty ? null : _title,
      titleChip: _session == null ? null : _statusChip(),
      topLeading: IconButton(
        key: const Key('audit-back'),
        tooltip: context.l10n.back,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(AppRoutes.skill(widget.skillId)),
      ),
      stage: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _voiceMode.stop()},
        child: Focus(autofocus: true, child: _stage(context)),
      ),
    );
  }

  Widget _stage(BuildContext context) {
    if (_starting) return LoadingView(message: context.l10n.callingAuditor);
    if (_startError != null) {
      return ErrorView(error: _startError!, onRetry: () => unawaited(_start()));
    }
    final celebration = _celebration;
    final open = celebration != null && _celebrationOpen;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _dialogue(context)),
            // Keeps its space when it is not needed, so that nothing jumps.
            Visibility(
              visible: _inputOpen,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: StageInputBar(
                controller: _input,
                focusNode: _focus,
                hint: _verdict == null
                    ? context.l10n.explainHint
                    : context.l10n.whatWentWrongHint,
                enabled: !_sending,
                onSubmit: () => unawaited(_handleInput(_input.text)),
                voiceMode: _voiceMode,
                onVoiceMode: () => unawaited(_voiceMode.start()),
              ),
            ),
          ],
        ),
        if (open) ...[
          // The whole stage steps back behind the card.
          Positioned.fill(child: ColoredBox(color: AppColors.background.withValues(alpha: 0.78))),
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, -0.3),
              child: CelebrationCard(
                key: const Key('celebration'),
                score: celebration.verdict.score,
                xp: celebration.verdict.rewardAmount,
                levelBefore: celebration.levelBefore,
                levelAfter: celebration.levelAfter,
                unlocked: celebration.unlocked,
                boss: _session != null && _session!.nodePosition != NodePosition.leaf,
                onClose: () => setState(() => _celebrationOpen = false),
                onContinue: () => context.go(AppRoutes.skill(widget.skillId)),
                onOpenSkill: (id) => context.go(AppRoutes.skill(id)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Who speaks now, and how she looks.
  ({String agent, AvatarMood mood}) get _speakerNow {
    final verdict = _verdict;
    if (_principle != null || (_failed && _recorderAsks)) {
      return (agent: 'recorder', mood: AvatarMood.neutral);
    }
    if (verdict != null) {
      return (agent: 'auditor', mood: verdict.passed ? AvatarMood.happy : AvatarMood.angry);
    }
    return (agent: 'auditor', mood: AvatarMood.stern);
  }

  /// The index of the line that is "current": the newest agent line, unless
  /// the user has answered it (then nothing is current until she replies).
  int? get _currentIndex {
    if (_lines.isEmpty || _lines.last.fromUser) return null;
    return _lines.length - 1;
  }

  Widget _dialogue(BuildContext context) {
    _followBottom();
    final current = _currentIndex;
    return ListenableBuilder(
      listenable: _voiceMode,
      builder: (context, _) {
        final speaker = _speakerNow;
        final state = _sending
            ? AvatarState.thinking
            : switch (_voiceMode.state) {
                VoiceModeState.listening => AvatarState.listening,
                VoiceModeState.thinking => AvatarState.thinking,
                VoiceModeState.speaking => AvatarState.speaking,
                VoiceModeState.off => AvatarState.idle,
              };
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.chatWidth),
            child: Column(
              children: [
                // Pinned: her face (and mood) stays in view while the dialogue scrolls.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: _SpeakerHeader(
                    agent: speaker.agent,
                    mood: speaker.mood,
                    state: state,
                    onTap: _voiceMode.interrupt,
                  ),
                ),
                const Divider(height: 1, indent: AppSpacing.xl, endIndent: AppSpacing.xl),
                Expanded(
                  child: ListView(
                    key: const Key('audit-qa'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    children: [
                      for (final (i, line) in _lines.indexed) ...[
                        _lineView(context, line, current: i == current && _problem == null),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_sending)
                        const Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.lg),
                          child: Align(alignment: Alignment.centerLeft, child: ThinkingShimmer()),
                        ),
                      if (_problem != null)
                        Text(
                          _problem!,
                          key: const Key('audit-bubble-text'),
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lineView(BuildContext context, _Line line, {required bool current}) {
    if (line.fromUser) return _Answer(text: line.text);
    switch (line.kind) {
      case _Kind.verdict:
        final verdict = _verdict;
        if (verdict == null) return const SizedBox.shrink();
        return VerdictCard(
          verdict: verdict,
          onLesson: verdict.passed || _recorderAsks ? null : _askRecorder,
          onBack: () => context.go(AppRoutes.skill(widget.skillId)),
        );
      case _Kind.lesson:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Question(agent: line.agent, text: line.text, current: current),
            if (_principle != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: LessonCard(
                  key: ValueKey('lesson-${_principle!.id}'),
                  principle: _principle!,
                ),
              ),
            ],
          ],
        );
      case _Kind.say:
        return _Question(agent: line.agent, text: line.text, current: current);
    }
  }
}

/// The speaker at the top of the column: her figure, small, with her name and
/// what she is doing.
class _SpeakerHeader extends StatelessWidget {
  const _SpeakerHeader({
    required this.agent,
    required this.mood,
    required this.state,
    required this.onTap,
  });

  final String agent;
  final AvatarMood mood;
  final AvatarState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final doing = switch (state) {
      AvatarState.thinking => context.l10n.voiceThinking,
      AvatarState.listening => context.l10n.voiceListening,
      AvatarState.speaking => context.l10n.voiceSpeaking,
      AvatarState.idle =>
        agent == 'recorder' ? context.l10n.recorderTagline : context.l10n.auditorTagline,
    };
    return Row(
      key: const Key('audit-speaker'),
      children: [
        GestureDetector(
          onTap: onTap,
          child: Avatar(agent: agent, mood: mood, state: state, size: 76),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(agentLabel(context.l10n, agent), style: theme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(doing, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One of her lines. The current one is the headline of the page; the ones
/// before it step back.
class _Question extends StatelessWidget {
  const _Question({required this.agent, required this.text, required this.current});

  final String agent;
  final String text;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      key: current ? const Key('audit-bubble') : const Key('audit-line'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          agentLabel(context.l10n, agent),
          style: theme.labelSmall?.copyWith(color: AppColors.textTertiary, letterSpacing: 0.4),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          text,
          key: current ? const Key('audit-bubble-text') : null,
          style: current
              ? AppTheme.serif(theme.headlineMedium)?.copyWith(height: 1.25)
              : theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// The user's answer: a bubble on the right.
class _Answer extends StatelessWidget {
  const _Answer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          key: const Key('audit-answer'),
          decoration: BoxDecoration(
            color: AppColors.userBubble,
            borderRadius: AppRadius.userBubbleBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }
}
