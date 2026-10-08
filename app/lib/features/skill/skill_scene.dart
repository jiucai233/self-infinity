import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/graph_utils.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_navigation.dart';
import '../map/delete_course.dart';
import '../stage/last_said.dart';
import '../stage/stage_input_bar.dart';
import '../stage/stage_scaffold.dart';
import '../../l10n/l10n.dart';

/// Scene 4 of `docs/ux-chat.md`: the overview of one node — the node's name in
/// the stage's title bar (with a status chip), a contents card (description,
/// one row per material, the course source) and the waving avatar asking
/// `Ready to try? →`. The right panel “Attempts” lists this node's audits as
/// cards. Questions typed in the input bar go to the chat and her answer
/// replaces the line in the bubble; the sent line shows above the input until
/// she has answered.
///
/// Route `/skill/:id`.
class SkillScene extends StatefulWidget {
  const SkillScene({super.key, required this.skillId});

  final int skillId;

  @override
  State<SkillScene> createState() => _SkillSceneState();
}

class _SkillSceneState extends State<SkillScene> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  late final ChatController _chat = context.read<ChatController>();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LastSaid _lastSaid = LastSaid();

  SkillOverview? _overview;
  bool _boss = false;

  /// The node's course, for the `⋯` menu's Delete course (name, node count).
  CourseMap? _courseMap;
  Object? _error;
  bool _loading = true;
  int? _revision;
  int _token = 0;

  String? _reply;
  String _replyAgent = 'front_desk';
  String? _chatError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<AppState>().dataRevision;
    if (_revision != null && _revision != revision) unawaited(_load(keepView: true));
    _revision = revision;
  }

  @override
  void dispose() {
    _lastSaid.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepView = false}) async {
    final token = ++_token;
    if (!keepView || _overview == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final overview = await _api.getSkillOverview(widget.skillId);
      if (!mounted || token != _token) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
      unawaited(_findBoss(overview, token));
    } on Object catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// A root or branch node is a boss (`Boss` chip). The overview only lists a
  /// node's parents, so the children come from the course map; a failing call
  /// just leaves the chip out.
  Future<void> _findBoss(SkillOverview overview, int token) async {
    try {
      final map = await _api.getCourseMap(overview.skill.courseId);
      if (!mounted || token != _token) return;
      setState(() {
        _boss = isBoss(overview.skill.id, map.edges);
        _courseMap = map;
      });
    } on Object {
      // no chip
    }
  }

  Future<void> _deleteCourse(CourseMap map) async {
    final deleted = await confirmDeleteCourse(
      context,
      courseId: map.course.id,
      courseName: courseNameOf(map),
      nodeCount: map.nodes.length,
    );
    if (deleted && mounted) context.go(AppRoutes.map);
  }

  // -- chat about the node ------------------------------------------------------

  Future<void> _ask(String text) async {
    final trimmed = text.trim();
    final overview = _overview;
    if (trimmed.isEmpty || _chat.sending || overview == null) return;
    setState(() {
      _chatError = null;
      _reply = null;
    });
    _input.clear();
    _lastSaid.say(trimmed);
    final saved = await _chat.send(context.l10n.aboutNodeMessage(overview.skill.title, trimmed));
    if (!mounted) return;
    if (saved == null) {
      _lastSaid.clear();
      setState(() => _chatError = _chat.error);
      _input.text = trimmed;
      return;
    }
    _lastSaid.fade();
    final assistants = saved.where((m) => !m.isUser).toList();
    setState(() {
      _reply = assistants.isEmpty ? null : assistants.last.content;
      _replyAgent = assistants.isEmpty ? 'front_desk' : (assistants.last.agent ?? 'front_desk');
    });
    followNavigation(context, assistants);
  }

  // -- build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final chat = context.watch<ChatController>();
    return StageScaffold(
      topLeading: IconButton(
        key: const Key('back-map'),
        tooltip: context.l10n.back,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(AppRoutes.map),
      ),
      title: overview?.skill.title ?? '',
      titleChip: overview == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_boss) ...[
                  StatusChip(
                    key: const Key('boss-chip'),
                    label: context.l10n.boss,
                    color: AppColors.onAccent,
                    fill: AppColors.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                _statusChip(overview),
                if (_courseMap case final map?)
                  PopupMenuButton<void>(
                    key: const Key('skill-menu'),
                    tooltip: context.l10n.more,
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const Key('skill-delete-course'),
                        onTap: () => unawaited(_deleteCourse(map)),
                        child: Text(
                          context.l10n.deleteCourse,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
      historyTitle: context.l10n.attempts,
      history: overview == null ? const SizedBox.shrink() : _AuditHistory(audits: overview.audits),
      stage: Column(
        children: [
          Expanded(child: _body(context, chat)),
          LastSaidBubble(said: _lastSaid),
          // Typing by voice here; talking is for the Guide and the audits.
          StageInputBar(
            controller: _input,
            focusNode: _focus,
            hint: context.l10n.askAboutNodeHint,
            enabled: overview != null && !chat.sending,
            onSubmit: () => _ask(_input.text),
            dictation: true,
            error: _chatError,
          ),
        ],
      ),
    );
  }

  /// Where the node stands: cleared, locked, failed last time or open.
  Widget _statusChip(SkillOverview overview) {
    final node = overview.skill;
    final l = context.l10n;
    if (node.isMastered) return StatusChip.success(l.dotCleared);
    if (node.isLocked) return StatusChip.neutral(l.dotLocked);
    final last = overview.audits.firstOrNull;
    if (last != null && last.status == AuditStatus.failed) return StatusChip.danger(l.auditFailed);
    return StatusChip.primary(l.dotReady);
  }

  Widget _body(BuildContext context, ChatController chat) {
    if (_loading && _overview == null) return const LoadingView();
    final overview = _overview;
    if (overview == null) {
      return ErrorView(error: _error ?? 'error', onRetry: () => unawaited(_load()));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final contents = _ContentsCard(overview: overview);
        final avatar = _AvatarColumn(
          overview: overview,
          openNode: _courseMap?.nodes.where((n) => n.isAvailable).firstOrNull,
          reply: _reply,
          replyAgent: _replyAgent,
          thinking: chat.sending,
          size: (box.maxHeight * 0.3).clamp(120.0, 240.0),
          onStart: () => context.go(AppRoutes.audit(overview.skill.id)),
        );
        final sideBySide = box.maxWidth >= 680;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - AppSpacing.sm - AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 5, child: contents),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(flex: 4, child: Center(child: avatar)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          contents,
                          const SizedBox(height: AppSpacing.xl),
                          avatar,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The contents card: the description, one row per material (a letter badge,
/// the title and the site), the course source. More than [pageSize] rows are
/// paged with `>`.
class _ContentsCard extends StatefulWidget {
  const _ContentsCard({required this.overview});

  final SkillOverview overview;

  @override
  State<_ContentsCard> createState() => _ContentsCardState();
}

class _ContentsCardState extends State<_ContentsCard> {
  static const int pageSize = 4;
  int _page = 0;

  List<SearchItem> get _links {
    final seen = <String>{};
    return [
      for (final plan in widget.overview.materials)
        for (final item in plan.items)
          if (seen.add(item.url)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final node = widget.overview.skill;
    final course = widget.overview.course;
    final links = _links;
    final pages = (links.length / pageSize).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final shown = links.skip(page * pageSize).take(pageSize).toList();
    return DecoratedBox(
      key: const Key('skill-contents'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.about, style: theme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              node.description.isEmpty ? context.l10n.noDescriptionYet : node.description,
              key: const Key('skill-description'),
              style: theme.bodyLarge,
            ),
            if (shown.isNotEmpty || course.hasSource) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.resources, style: theme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
            ],
            for (final item in shown)
              _MaterialRow(
                key: ValueKey('link-${item.url}'),
                title: item.title.isEmpty ? displayDomain(item.url) : item.title,
                subtitle: displayDomain(item.url),
                onTap: () => openExternalUrl(context, item.url),
              ),
            if (course.hasSource)
              _MaterialRow(
                key: const Key('course-source'),
                title: context.l10n.sourceLabel(course.sourceCourse!),
                subtitle: course.hasSourceLink
                    ? displayDomain(course.sourceUrl!)
                    : context.l10n.uploadedCourseMaterial,
                icon: Icons.menu_book_outlined,
                onTap: course.hasSourceLink
                    ? () => openExternalUrl(context, course.sourceUrl!)
                    : null,
              ),
            if (pages > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (page > 0)
                      IconButton(
                        key: const Key('links-prev'),
                        tooltip: context.l10n.previous,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: () => setState(() => _page = page - 1),
                      ),
                    Text('${page + 1}/$pages', style: theme.bodySmall),
                    if (page < pages - 1)
                      IconButton(
                        key: const Key('links-next'),
                        tooltip: context.l10n.next,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => setState(() => _page = page + 1),
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

/// The first letter or digit of [title] in capitals (`“Functions” …` -> `F`); the
/// favicon placeholder of a material row.
String firstLetterOf(String title) {
  final match = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(title);
  return match == null ? '·' : match.group(0)!.toUpperCase();
}

/// One material: a round badge with the first letter of the title (the place
/// of the site's favicon), the title and the site; the whole row opens the
/// link. Without [onTap] (a course made from an uploaded file) it is plain.
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;

  /// Shown in the badge instead of the first letter.
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final letter = firstLetterOf(title);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      child: Row(
        children: [
          DecoratedBox(
            key: const Key('material-badge'),
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 18, color: AppColors.primary)
                    : Text(
                        letter,
                        style: theme.labelLarge?.copyWith(color: AppColors.primary),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const Key('material-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  key: const Key('material-domain'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall,
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textTertiary),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: AppRadius.chipBorder, child: row);
  }
}

/// The waving avatar with her line; a → in the bubble starts the audit.
class _AvatarColumn extends StatelessWidget {
  const _AvatarColumn({
    required this.overview,
    required this.openNode,
    required this.reply,
    required this.replyAgent,
    required this.thinking,
    required this.size,
    required this.onStart,
  });

  final SkillOverview overview;

  /// The node of the course that is open now (one at a time, in the learning
  /// order); null until the course map is read.
  final SkillNode? openNode;
  final String? reply;
  final String replyAgent;
  final bool thinking;
  final double size;
  final VoidCallback onStart;

  String _line(AppLocalizations l) {
    final node = overview.skill;
    if (reply != null) return reply!;
    if (node.isLocked) {
      final open = openNode;
      return open == null ? l.lockedClearParent : l.lockedClearNamed(open.title);
    }
    return l.readyToTry;
  }

  @override
  Widget build(BuildContext context) {
    final node = overview.skill;
    final theme = Theme.of(context).textTheme;
    final agent = reply == null ? 'front_desk' : replyAgent;
    final state = thinking ? AvatarState.thinking : AvatarState.idle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpeechBubble(
          key: const Key('skill-bubble'),
          maxWidth: 320,
          speaker: agent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: thinking
              ? const ThinkingShimmer(width: 220)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(_line(context.l10n), style: theme.bodyLarge)),
                    if (!node.isLocked) ...[
                      const SizedBox(width: AppSpacing.md),
                      IconButton(
                        key: const Key('start-audit'),
                        tooltip: context.l10n.startAudit,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onAccent,
                          fixedSize: const Size(36, 36),
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        onPressed: onStart,
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Avatar(
          agent: agent,
          mood: AvatarMood.smile,
          state: state,
          wave: !node.isLocked && reply == null,
          size: size,
        ),
      ],
    );
  }
}

/// The body of the right panel “Attempts” on scene 4: one card per audit of
/// this node, newest first — the date, a Passed/Failed chip and the score.
class _AuditHistory extends StatelessWidget {
  const _AuditHistory({required this.audits});

  final List<AuditSummary> audits;

  @override
  Widget build(BuildContext context) {
    if (audits.isEmpty) return EmptyView(message: context.l10n.noAttemptsYet);
    final theme = Theme.of(context).textTheme;
    return ListView(
      key: const Key('skill-audits'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        for (final a in audits)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: DecoratedBox(
              key: const Key('audit-card'),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.cardBorder,
                border: Border.all(color: AppColors.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatLocal(a.createdAt, style: DateStyle.dateTime),
                            style: theme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            a.score == null ? '—' : context.l10n.points(a.score!),
                            key: const Key('audit-score'),
                            style: theme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      label: a.status.label(context.l10n),
                      color: a.status.color,
                      fill: a.status.fill,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
