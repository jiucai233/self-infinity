import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
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
import '../stage/stage_controller.dart';
import '../stage/stage_scaffold.dart';
import '../../upload/file_picker_service.dart';
import 'edit_node.dart';
import 'node_card.dart';
import '../../l10n/l10n.dart';

/// Scene 4 of `docs/ux-chat.md`: the overview of one node — the node card on
/// top (kicker and `⋯`, the name, its chips, Best / Attempts / Lessons, the
/// audit history and the full-width ink `Take it on`), a contents card
/// (description, one row per material, the course source) and the waving
/// avatar with one line. On a wide screen the right panel “Attempts” lists
/// this node's audits as cards; a phone has only the card. Questions typed in
/// the input bar go to the chat and her answer replaces the line in the
/// bubble; the sent line shows above the input until she has answered.
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

  /// Breaking a node down or reading a syllabus (one Planner call, up to a
  /// minute): the line the bubble shows meanwhile.
  String? _working;
  bool _expandFailed = false;

  /// The course this node is (contract #44): its map, for its name and root.
  CourseMap? _linkedMap;
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
      final linked = overview.skill.linkedCourseId;
      final linkedMap = linked == null ? null : await _api.getCourseMap(linked);
      if (!mounted || token != _token) return;
      setState(() {
        _boss = isBoss(overview.skill, map.edges);
        _courseMap = map;
        _linkedMap = linkedMap;
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

  /// Breaks the node down into its parts (or fills in the ones missing); the
  /// page and the map reload, also when the player left the page while it ran
  /// (it takes up to a minute).
  Future<void> _expand() async {
    final overview = _overview;
    if (overview == null || _working != null) return;
    final l = context.l10n;
    final before = _courseMap;
    final hadParts = before != null && hasParts(overview.skill, before);
    final after = await _edit(
      () => _api.expandSkill(overview.skill.id),
      working: l.breakingDown,
      expand: true,
    );
    // The Planner found nothing to add: say so, or it looks as if nothing happened.
    if (after != null && before != null && after.nodes.length == before.nodes.length && mounted) {
      setState(() {
        _reply = hadParts ? l.nodeNothingMissing : l.nodeAlreadySmallest;
        _replyAgent = 'front_desk';
      });
    }
  }

  /// Runs one edit of the course: the bubble says [working] meanwhile and the
  /// result (or what went wrong) after; the page and the map reload. Returns
  /// the course map, or null when it failed.
  Future<CourseMap?> _edit(
    Future<CourseMap> Function() call, {
    String? working,
    bool expand = false,
    String Function(ApiException e)? failure,
  }) async {
    final app = context.read<AppState>();
    final failed = context.l10n.nodeEditFailed;
    setState(() {
      _working = working;
      _expandFailed = false;
      _reply = null;
    });
    try {
      final map = await call();
      app.markDataChanged();
      if (mounted) {
        setState(() {
          _working = null;
          _courseMap = map;
        });
      }
      return map;
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _working = null;
          _expandFailed = expand;
          if (!expand) {
            _reply = e is ApiException ? (failure?.call(e) ?? e.serverMessage ?? failed) : failed;
            _replyAgent = 'front_desk';
          }
        });
      }
      return null;
    }
  }

  Future<void> _editNode(SkillNode node) async {
    final text = await askNodeText(
      context,
      dialogTitle: context.l10n.nodeEditTitle,
      initial: (title: node.title, description: node.description),
    );
    if (text == null || !mounted) return;
    await _edit(() => _api.editSkill(node.id, title: text.title, description: text.description));
  }

  Future<void> _addPart(SkillNode node) async {
    final text = await askNodeText(context, dialogTitle: context.l10n.nodeAddPartTitle(node.title));
    if (text == null || !mounted) return;
    await _edit(
      () => _api.addSkillPart(
        node.id,
        title: text.title,
        description: text.description.isEmpty ? null : text.description,
      ),
    );
  }

  Future<void> _link(SkillNode node) async {
    final maps = context.read<StageController>().courseMaps;
    final choice = await askLinkedCourse(
      context,
      title: node.title,
      courses: [
        for (final m in maps)
          if (m.course.id != node.courseId) (id: m.course.id, name: courseNameOf(m)),
      ],
      current: node.linkedCourseId,
    );
    if (choice == null || !mounted) return;
    await _edit(
      () => _api.linkSkill(node.id, switch (choice) {
        LinkToCourse(:final courseId) => courseId,
        Unlink() => null,
      }),
    );
  }

  Future<void> _applySyllabus(CourseMap map) async {
    final l = context.l10n;
    final picker = context.read<FilePickerService>();
    final source = await askSyllabusSource(context, course: courseNameOf(map));
    if (source == null || !mounted) return;
    final uploads = <int>[];
    if (source == SyllabusSource.upload) {
      final file = await picker.pick();
      if (file == null || !mounted) return;
      try {
        uploads.add((await _api.uploadFile(filename: file.name, bytes: file.bytes)).id);
      } on ApiException catch (e) {
        if (mounted) setState(() => _reply = e.serverMessage ?? l.nodeEditFailed);
        return;
      }
      if (!mounted) return;
    }
    final before = map.nodes.length;
    final after = await _edit(
      () => _api.applySyllabus(map.course.id, uploadIds: uploads),
      working: l.nodeReadingSyllabus,
      failure: (e) => e.statusCode == 404 && uploads.isEmpty ? l.nodeNoSyllabus : e.serverMessage ?? l.nodeEditFailed,
    );
    if (after != null && mounted) {
      setState(() {
        _reply = l.nodeSyllabusAdded(after.nodes.length - before);
        _replyAgent = 'front_desk';
      });
    }
  }

  Future<void> _deleteNode(SkillNode node) async {
    if (!await confirmDeleteNode(context, title: node.title) || !mounted) return;
    final map = await _edit(() => _api.deleteSkill(node.id));
    if (map != null && mounted) context.go(AppRoutes.map);
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
      // A phone has the node card's audit history instead (no drawer).
      historyTitle: context.l10n.attempts,
      history: overview == null || !AppLayout.isWide(context)
          ? null
          : _AuditHistory(audits: overview.audits),
      stage: Column(
        children: [
          Expanded(child: _body(context, chat)),
          LastSaidBubble(said: _lastSaid),
          // Typing by voice here (no ∿, so the voice key dictates); talking is
          // for the Guide and the audits.
          StageInputBar(
            controller: _input,
            focusNode: _focus,
            hint: context.l10n.askAboutNodeHint,
            enabled: overview != null && !chat.sending,
            onSubmit: () => _ask(_input.text),
            error: _chatError,
          ),
        ],
      ),
    );
  }

  /// The `⋯` menu in the card's kicker row: the edits, then Delete course.
  Widget? _menu(SkillOverview overview) {
    final map = _courseMap;
    if (map == null) return null;
    return PopupMenuButton<void>(
      key: const Key('skill-menu'),
      tooltip: context.l10n.more,
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      itemBuilder: (_) => [
        ..._editItems(overview.skill, map),
        PopupMenuItem(
          key: const Key('skill-delete-course'),
          onTap: () => unawaited(_deleteCourse(map)),
          child: Text(
            context.l10n.deleteCourse,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }

  /// The card's chips: the status, Unexpanded, then the course's name (the
  /// kicker above the title already says Boss).
  List<Widget> _chips(SkillOverview overview) {
    final node = overview.skill;
    final map = _courseMap;
    return [
      _statusChip(overview),
      if (node.unexpanded && !node.isMastered && !node.isLinked)
        StatusChip.neutral(context.l10n.dotUnexpanded, key: const Key('skill-unexpanded')),
      if (map != null)
        Text(
          courseNameOf(map),
          key: const Key('skill-course-name'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
    ];
  }

  /// The card's buttons: the ink `Take it on` (full width) when the node can
  /// be audited, else `Break it down` / `Open the course`; under them the
  /// challenge on the whole branch, with a line saying what it does. None
  /// while the course is being edited.
  List<Widget> _actions(SkillOverview overview) {
    if (_working != null) return const [];
    final node = overview.skill;
    final l = context.l10n;
    final unexpanded = node.unexpanded && !node.isMastered && !node.isLinked;
    final openCourse = node.isLinked ? _linkedRootId : null;
    final canTestOut = !node.isMastered && !node.isLinked && (node.unexpanded || _boss);
    final theme = Theme.of(context).textTheme;
    final buttons = <Widget>[
      if (!node.isLocked && !unexpanded && !node.isLinked)
        FilledButton(
          key: const Key('start-audit'),
          onPressed: () => context.go(AppRoutes.audit(node.id)),
          child: Text(l.takeItOn),
        ),
      if (openCourse != null)
        FilledButton(
          key: const Key('open-linked-course'),
          onPressed: () => context.go(AppRoutes.skill(openCourse)),
          child: Text(l.nodeOpenCourse),
        ),
      if (unexpanded)
        FilledButton(
          key: const Key('expand-node'),
          onPressed: () => unawaited(_expand()),
          child: Text(l.breakDown),
        ),
    ];
    return [
      for (final (i, b) in buttons.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        b,
      ],
      if (canTestOut) ...[
        if (buttons.isNotEmpty) const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('test-out'),
          onPressed: () => context.go(AppRoutes.challenge(node.id)),
          child: Text(l.challengeWhole),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          keepAll(l.challengeWholeHint),
          key: const Key('test-out-hint'),
          textAlign: TextAlign.center,
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    ];
  }

  int? get _linkedRootId => switch (_linkedMap) {
    final linked? => rootNodes(linked.nodes, linked.edges).firstOrNull?.id,
    null => null,
  };

  /// The `⋯` menu's edits of the course (contract #41–#45), above Delete
  /// course. Nothing while an edit runs.
  List<PopupMenuEntry<void>> _editItems(SkillNode node, CourseMap map) {
    if (_working != null) return const [];
    final l = context.l10n;
    final root = isRootOf(node, map);
    final parts = hasParts(node, map);
    PopupMenuItem<void> item(String key, String label, VoidCallback onTap, {bool danger = false}) => PopupMenuItem(
      key: Key(key),
      onTap: onTap,
      child: Text(label, style: danger ? const TextStyle(color: AppColors.danger) : null),
    );
    return [
      item('skill-edit', l.nodeEdit, () => unawaited(_editNode(node))),
      if (!node.isLinked) item('skill-add-part', l.nodeAddPart, () => unawaited(_addPart(node))),
      // A leaf with knowledge points is the smallest node: nothing to break down.
      if (!node.isLinked && !node.unexpanded && (parts || node.points.isEmpty))
        item('skill-fill-in', parts ? l.nodeFillIn : l.nodeBreakDownFurther, () => unawaited(_expand())),
      if (!root && !parts) item('skill-link', l.nodeLink, () => unawaited(_link(node))),
      item('skill-syllabus', l.nodeApplySyllabus, () => unawaited(_applySyllabus(map))),
      if (!root) item('skill-delete-node', l.nodeDelete, () => unawaited(_deleteNode(node)), danger: true),
      const PopupMenuDivider(),
    ];
  }

  /// Where the node stands: cleared, locked, failed last time or open.
  Widget _statusChip(SkillOverview overview) {
    final node = overview.skill;
    final l = context.l10n;
    if (node.isMastered) return StatusChip.success(node.testedOut ? l.testedOut : l.dotCleared);
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
    final node = overview.skill;
    final lessons = context.select<StageController, List<Principle>>(
      (s) => [
        for (final p in s.lessons)
          if (p.skillId == node.id) p,
      ],
    );
    // The main quest this node's course serves, if any.
    final quest = context.select<StageController, String?>(
      (s) => s.goals.where((g) => g.courseIds.contains(overview.course.id)).firstOrNull?.title,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final map = _courseMap;
        final card = SkillNodeCard(
          overview: overview,
          quest: quest,
          boss: _boss,
          chips: _chips(overview),
          lessons: lessons,
          menu: _menu(overview),
          actions: _actions(overview),
        );
        final contents = _ContentsCard(
          overview: overview,
          // Knowledge points belong to a leaf; a node that got parts no longer shows them.
          points: map != null && hasParts(node, map) ? const [] : node.points,
        );
        final chapter = map == null ? null : chapterOf(node.id, map.edges);
        final avatar = _AvatarColumn(
          overview: overview,
          // The open node of this node's chapter (the root waits for them all).
          openNode: map?.nodes
              .where((n) => n.isAvailable && (chapter == null || chapterOf(n.id, map.edges) == chapter))
              .firstOrNull,
          reply: _reply,
          replyAgent: _replyAgent,
          thinking: chat.sending,
          working: _working,
          expandFailed: _expandFailed,
          linkedCourseName: switch (_linkedMap) {
            final linked? when node.isLinked => courseNameOf(linked),
            _ => null,
          },
          size: (box.maxHeight * 0.3).clamp(120.0, 240.0),
        );
        final sideBySide = box.maxWidth >= 680;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            sideBySide ? AppSpacing.xl : AppSpacing.lg,
            AppSpacing.sm,
            sideBySide ? AppSpacing.xl : AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: sideBySide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              card,
                              const SizedBox(height: AppSpacing.xl),
                              contents,
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xl),
                            child: avatar,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        card,
                        const SizedBox(height: AppSpacing.xl),
                        avatar,
                        const SizedBox(height: AppSpacing.xl),
                        contents,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The contents card: the description, the knowledge points of a leaf (what
/// held, what was missed and why), one row per material (a letter badge, the
/// title and the site), the course source. More than [pageSize] rows are
/// paged with `>`.
class _ContentsCard extends StatefulWidget {
  const _ContentsCard({required this.overview, this.points = const []});

  final SkillOverview overview;

  /// The node's knowledge points, when it is a leaf that has them.
  final List<SkillPoint> points;

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
            if (widget.points.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.knowledgePoints, style: theme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.knowledgePointsHint,
                style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (i, point) in widget.points.indexed)
                PointRow(key: Key('skill-point-$i'), point: point),
            ],
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

/// The waving avatar with her one line (the buttons are on the node card).
class _AvatarColumn extends StatelessWidget {
  const _AvatarColumn({
    required this.overview,
    required this.openNode,
    required this.reply,
    required this.replyAgent,
    required this.thinking,
    required this.working,
    required this.expandFailed,
    required this.linkedCourseName,
    required this.size,
  });

  final SkillOverview overview;

  /// The open node of this node's chapter (one per chapter, in the learning
  /// order); null until the course map is read.
  final SkillNode? openNode;
  final String? reply;
  final String replyAgent;
  final bool thinking;

  /// What the bubble says while the course is being edited (breaking down,
  /// reading a syllabus); null when nothing runs.
  final String? working;
  final bool expandFailed;

  /// The name of the course this node is, once read.
  final String? linkedCourseName;
  final double size;

  bool get _unexpanded =>
      overview.skill.unexpanded && !overview.skill.isMastered && !overview.skill.isLinked;

  String _line(AppLocalizations l) {
    final node = overview.skill;
    if (working case final line?) return line;
    if (expandFailed) return l.breakDownFailed;
    if (reply != null) return reply!;
    if (linkedCourseName case final name?) return l.nodeLinkedLine(name);
    if (_unexpanded) return l.unexpandedLine;
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
    final busy = thinking || working != null;
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
              : Text(keepAll(_line(context.l10n)), style: theme.bodyLarge),
        ),
        const SizedBox(height: AppSpacing.sm),
        Live2DFigure(
          mood: AvatarMood.smile,
          state: busy ? AvatarState.thinking : AvatarState.idle,
          wave: !node.isLocked && !_unexpanded && !node.isLinked && reply == null,
          size: size,
          framing: 'upper',
          fallback: Avatar(
            agent: agent,
            mood: AvatarMood.smile,
            state: busy ? AvatarState.thinking : AvatarState.idle,
            wave: !node.isLocked && !_unexpanded && !node.isLinked && reply == null,
            size: size,
          ),
        ),
      ],
    );
  }
}

/// The body of the right panel “Attempts” on a wide screen: one card per
/// audit of this node, newest first — the date, a Passed/Failed chip and the
/// score. A card opens the audit's replay; a fail not reflected on yet says
/// so. (On a phone the node card's audit history stands in for it.)
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
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: Key('audit-open-${a.id}'),
                  borderRadius: AppRadius.cardBorder,
                  onTap: () => context.go(AppRoutes.replay(a.id)),
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
                              if (a.status == AuditStatus.failed && !a.reflected) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  context.l10n.notReflectedYet,
                                  key: const Key('audit-unreflected'),
                                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                                ),
                              ],
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
            ),
          ),
      ],
    );
  }
}
