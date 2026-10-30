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
/// A fail leads with what to do next: `Try again` starts a new audit of the
/// node, and right under the gaps a field to write (or dictate) what the user
/// believed at the time; `Make a lesson card` sends it to the Recorder. The
/// words are the user's own: nothing is suggested. An audit with a card shows
/// it, how often it has held or come back since, and `Find material`, which
/// asks the Material Finder for at most three sources on the gaps (only on a
/// tap: it costs a search). The two things to say about a fail (too hard for
/// now, I didn't say that) sit in the ⋯ menu of the title bar.
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

  // Material for the gaps: null until found; the search in flight; a failed one.
  List<SearchItem>? _materials;
  bool _searching = false;
  bool _searchFailed = false;

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

  /// Tells the backend; the audit it sends back says what is noted now, and
  /// a toast says so.
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
      final l = context.l10n;
      showToast(
        context,
        kind == AuditFeedback.tooHard ? l.feedbackTooHardNoted : l.feedbackMisheardNoted,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _telling = null);
      showToast(context, ErrorView.messageFor(e));
    }
  }

  /// Asks the Material Finder for sources on this audit's gaps (all of them,
  /// as one gap). A failure is said quietly and the button stays.
  Future<void> _findMaterials(AuditSession audit, List<String> gaps) async {
    if (_searching || gaps.isEmpty) return;
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final plan = await _api.createSearchPlan(audit.skillId, gap: gaps.join('; '));
      if (!mounted) return;
      setState(() {
        _materials = plan.items.take(3).toList();
        _searching = false;
      });
      _appState.markDataChanged();
    } on Object {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = _audit;
    return StageScaffold(
      title: audit == null || audit.skillTitle.isEmpty ? null : audit.skillTitle,
      titleChip: audit == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusChip(
                  label: audit.status.label(context.l10n),
                  color: audit.status.color,
                  fill: audit.status.fill,
                ),
                if (audit.status == AuditStatus.failed) _feedbackMenu(context, audit),
              ],
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
    final points = [
      if (audit.points.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xxl),
        Text(l.knowledgePoints, style: theme.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final (i, point) in audit.points.indexed)
          PointRow(key: Key('replay-point-$i'), point: point),
      ],
    ];
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
                if (failed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('replay-retry'),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: Text(l.replayRetry),
                      onPressed: () => context.go(AppRoutes.audit(audit.skillId)),
                    ),
                  ),
                ],
                // A pass reads its points first; a fail leads with its gaps.
                if (!failed) ...points,
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
                  if (failed && gaps.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _materialsSection(context, audit, [for (final g in gaps) g.gap]),
                  ],
                ] else if (failed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _reflectionField(context),
                ],
                if (failed) ...points,
                if (audit.lessons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text(l.pastLessons, style: theme.labelMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (i, lesson) in audit.lessons.indexed)
                    _LessonLine(key: Key('replay-lesson-check-$i'), check: lesson),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The ⋯ of the title bar: two quiet things to say about a fail, it was
  /// too hard for now, or the judge quoted words the user did not say. One
  /// already sent stays in the menu, greyed, saying it was noted.
  Widget _feedbackMenu(BuildContext context, AuditSession audit) {
    final l = context.l10n;
    PopupMenuEntry<AuditFeedback> item(
      AuditFeedback kind,
      bool noted,
      String label,
      String done,
      String name,
    ) => PopupMenuItem<AuditFeedback>(
      key: Key(noted ? 'replay-$name-noted' : 'replay-$name'),
      value: kind,
      enabled: !noted && _telling == null,
      child: Text(noted ? done : label),
    );
    return PopupMenuButton<AuditFeedback>(
      key: const Key('replay-menu'),
      tooltip: l.more,
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelected: (kind) => unawaited(_tell(kind)),
      itemBuilder: (_) => [
        item(
          AuditFeedback.tooHard,
          audit.tooHard,
          l.feedbackTooHard,
          l.feedbackTooHardNoted,
          'too-hard',
        ),
        item(
          AuditFeedback.misheard,
          audit.disputed,
          l.feedbackMisheard,
          l.feedbackMisheardNoted,
          'misheard',
        ),
      ],
    );
  }

  /// After the card: `Find material` for the gaps, then at most three
  /// sources (title, site), a quiet line when nothing came back or the search
  /// failed.
  Widget _materialsSection(BuildContext context, AuditSession audit, List<String> gaps) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final materials = _materials;
    final quiet = theme.bodySmall?.copyWith(color: AppColors.textTertiary);
    return Column(
      key: const Key('replay-materials'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (materials == null || materials.isEmpty)
          OutlinedButton.icon(
            key: const Key('replay-find-materials'),
            icon: _searching
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded, size: 18),
            label: Text(l.findMaterials),
            onPressed: _searching ? null : () => unawaited(_findMaterials(audit, gaps)),
          )
        else ...[
          Text(l.materialsHeading, style: theme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final (i, item) in materials.indexed)
            _MaterialLink(key: Key('replay-material-$i'), item: item),
        ],
        if (_searchFailed || (materials != null && materials.isEmpty)) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _searchFailed ? l.materialsFailed : l.materialsNone,
            key: const Key('replay-materials-note'),
            style: quiet,
          ),
        ],
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

/// A past lesson the audit touched: one that held in amber, one that came
/// back in plain text with a ↻ (it is a lesson to look at again, not an error).
class _LessonLine extends StatelessWidget {
  const _LessonLine({super.key, required this.check});

  final LessonCheck check;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final text = LessonCheckRow.textOf(context, check);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: check.held
          ? Text(text, style: style?.copyWith(color: AppColors.success))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: AppSpacing.xs + 2),
                  child: Icon(Icons.refresh_rounded, size: 15, color: AppColors.textTertiary),
                ),
                Expanded(
                  child: Text(text, style: style?.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
    );
  }
}

/// One source: its title, and under it the site; a tap opens it.
class _MaterialLink extends StatelessWidget {
  const _MaterialLink({super.key, required this.item});

  final SearchItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => unawaited(openExternalUrl(context, item.url)),
      borderRadius: AppRadius.chipBorder,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    displayDomain(item.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
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
