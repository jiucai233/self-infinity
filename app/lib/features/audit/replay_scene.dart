import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../stage/stage_scaffold.dart';
import 'gap_evidence.dart';
import 'lesson_card.dart';
import '../../l10n/l10n.dart';

/// The replay of one audit, as one reading column: when it was and the score,
/// her comment, each knowledge point, every gap with the user's own words
/// next to what holds, the past lessons that held or came back, and the whole
/// dialogue folded away.
///
/// A fail without a lesson card ends in a field to write (or dictate) what
/// the user believed at the time; `Make a lesson card` sends it to the
/// Recorder. The words are the user's own: nothing is suggested. An audit
/// with a card shows it, and how often it has held or come back since.
///
/// Route `/audit/:auditId`.
class ReplayScene extends StatefulWidget {
  const ReplayScene({super.key, required this.auditId});

  final int auditId;

  @override
  State<ReplayScene> createState() => _ReplaySceneState();
}

class _ReplaySceneState extends State<ReplayScene> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  late final AppState _appState = context.read<AppState>();
  final TextEditingController _reflection = TextEditingController();

  AuditSession? _audit;
  Object? _error;
  bool _loading = true;
  bool _dialogueFolded = true;

  // The two things to say about a fail; the one in flight, if any.
  AuditFeedback? _telling;

  // The reflection.
  bool _sending = false;
  String? _problem;

  /// The card made here, just now (it flips over); null for one that was
  /// already there.
  Principle? _made;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final audit = await _api.getAudit(widget.auditId);
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Sends the reflection to the Recorder. On a failure the text stays in
  /// the field and the reason shows under it.
  Future<void> _submit() async {
    final audit = _audit;
    final text = _reflection.text.trim();
    if (audit == null || text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      final principle = await _api.submitReflection(audit.id, text);
      if (!mounted) return;
      setState(() {
        _made = principle;
        _sending = false;
      });
      _appState.markDataChanged();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _problem = ErrorView.messageFor(e);
      });
    }
  }

  /// Tells the backend; the audit it sends back says what is noted now.
  Future<void> _tell(AuditFeedback kind) async {
    if (_telling != null) return;
    setState(() => _telling = kind);
    try {
      final audit = await _api.auditFeedback(widget.auditId, kind);
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _telling = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _telling = null);
      showToast(context, ErrorView.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = _audit;
    return StageScaffold(
      title: audit == null || audit.skillTitle.isEmpty ? null : audit.skillTitle,
      titleChip: audit == null
          ? null
          : StatusChip(
              label: audit.status.label(context.l10n),
              color: audit.status.color,
              fill: audit.status.fill,
            ),
      topLeading: audit == null
          ? null
          : IconButton(
              key: const Key('replay-back'),
              tooltip: context.l10n.back,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go(AppRoutes.skill(audit.skillId)),
            ),
      stage: _stage(context),
    );
  }

  Widget _stage(BuildContext context) {
    if (_loading) return const LoadingView();
    final audit = _audit;
    if (audit == null) {
      return ErrorView(error: _error ?? 'error', onRetry: () => unawaited(_load()));
    }
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final failed = audit.status == AuditStatus.failed;
    final comment = audit.comment?.trim() ?? '';
    final created = audit.createdAt;
    final gaps = audit.evidence.isNotEmpty
        ? audit.evidence
        : [for (final gap in audit.gaps) GapEvidence(gap: gap)];
    final principle = _made ?? audit.principle;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.chatWidth),
        // Everything here can be selected and copied.
        child: SelectionArea(
          // Not a lazy list: the field at the end keeps its state while the page scrolls.
          child: SingleChildScrollView(
            key: const Key('replay-scene'),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        created == null ? '' : formatLocal(created, style: DateStyle.dateTime),
                        key: const Key('replay-date'),
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                    if (audit.score != null) ...[
                      Text(
                        '${audit.score}',
                        key: const Key('replay-score'),
                        style: theme.headlineLarge,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(l.pointsUnit, style: theme.labelMedium),
                    ],
                  ],
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(comment, key: const Key('replay-comment'), style: theme.bodyLarge),
                ],
                if (audit.points.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text(l.knowledgePoints, style: theme.labelMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (i, point) in audit.points.indexed)
                    PointRow(key: Key('replay-point-$i'), point: point),
                ],
                if (gaps.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text(failed ? l.whatWasMissing : l.worthSecondLook, style: theme.labelMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (i, gap) in gaps.indexed)
                    GapEvidenceView(
                      key: Key('replay-gap-$i'),
                      evidence: gap,
                      color: failed ? AppColors.danger : AppColors.textTertiary,
                    ),
                ],
                if (audit.lessons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text(l.pastLessons, style: theme.labelMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (i, lesson) in audit.lessons.indexed)
                    LessonCheckRow(key: Key('replay-lesson-check-$i'), check: lesson),
                ],
                if (failed) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _feedbackRow(context, audit),
                ],
                if (audit.turns.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  CollapsibleSection(
                    title: l.replayDialogue,
                    folded: _dialogueFolded,
                    onToggle: () => setState(() => _dialogueFolded = !_dialogueFolded),
                    compact: true,
                    toggleKey: const Key('replay-dialogue'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final turn in audit.turns) _Turn(turn: turn)],
                    ),
                  ),
                ],
                if (principle != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Center(
                    child: LessonCard(
                      key: const Key('replay-lesson'),
                      principle: principle,
                      // One made just now flips over; one that was there is just there.
                      animate: _made == null ? false : null,
                    ),
                  ),
                  if (principle.held + principle.relapsed > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: Text(
                        l.lessonCounts(principle.held, principle.relapsed),
                        key: const Key('replay-lesson-counts'),
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                ] else if (failed) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  _reflectionField(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Two quiet things to say about a fail: it was too hard for now, or the
  /// judge quoted words the user did not say. Once sent, a line says so.
  Widget _feedbackRow(BuildContext context, AuditSession audit) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    Widget one(AuditFeedback kind, bool noted, String label, String done, String name) => noted
        ? Text(
            done,
            key: Key('replay-$name-noted'),
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          )
        : TextButton(
            key: Key('replay-$name'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
            onPressed: _telling == null ? () => unawaited(_tell(kind)) : null,
            child: Text(label),
          );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        one(
          AuditFeedback.tooHard,
          audit.tooHard,
          l.feedbackTooHard,
          l.feedbackTooHardNoted,
          'too-hard',
        ),
        one(
          AuditFeedback.misheard,
          audit.disputed,
          l.feedbackMisheard,
          l.feedbackMisheardNoted,
          'misheard',
        ),
      ],
    );
  }

  /// The user's own account of the miss: typed or dictated, never suggested.
  Widget _reflectionField(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: AppRadius.cardBorder,
      borderSide: color == Colors.transparent ? BorderSide.none : BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('replay-reflection'),
          controller: _reflection,
          minLines: 3,
          maxLines: 8,
          enabled: !_sending,
          style: theme.bodyLarge,
          decoration: InputDecoration(
            hintText: context.l10n.replayReflectHint,
            suffixIcon: DictationButton(controller: _reflection, enabled: !_sending),
            border: border(Colors.transparent),
            enabledBorder: border(Colors.transparent),
            disabledBorder: border(Colors.transparent),
            focusedBorder: border(AppColors.primary),
          ),
        ),
        if (_problem != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _problem!,
            key: const Key('replay-problem'),
            style: theme.bodyMedium?.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        // Follows the field: nothing to send while it is empty.
        ListenableBuilder(
          listenable: _reflection,
          builder: (context, _) => FilledButton(
            key: const Key('replay-submit'),
            onPressed: _sending || _reflection.text.trim().isEmpty
                ? null
                : () => unawaited(_submit()),
            child: Text(context.l10n.makeLessonCard),
          ),
        ),
      ],
    );
  }
}

/// One turn of the dialogue: who spoke, then the words. On her turns what she
/// said about the answer before comes ahead of her question.
class _Turn extends StatelessWidget {
  const _Turn({required this.turn});

  final AuditTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final feedback = turn.feedback?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            turn.isUser ? l.you : agentLabel(l, turn.role.value),
            style: theme.labelSmall?.copyWith(color: AppColors.textTertiary, letterSpacing: 0.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (feedback.isNotEmpty) ...[
            Text(feedback, style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            turn.content,
            style: theme.bodyMedium?.copyWith(
              color: turn.isUser ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
