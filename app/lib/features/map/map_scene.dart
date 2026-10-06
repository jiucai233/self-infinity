import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../stage/profile_controller.dart';
import '../stage/stage_controller.dart';
import '../stage/stage_input_bar.dart';
import '../stage/stage_scaffold.dart';
import 'graph_view.dart';
import 'node_sheet.dart';
import 'stat_strip.dart';
import '../../l10n/l10n.dart';

/// Scene 2 of `docs/ux-chat.md`: your **life tree**.
///
/// * On top, your progress over every course in big numbers.
/// * Below, the night panel: you in the middle, your main quests, the courses
///   serving them and their nodes, turning slowly (`LifeConstellation`). Tap a
///   point and its card opens (`NodeSheet`): audit history, lessons, `Take it
///   on`.
/// * `Outline` switches to the layered graph of one course (the old map).
/// * The search bar finds a node in **any** course.
///
/// Route `/map`.
class MapScene extends StatefulWidget {
  const MapScene({super.key});

  @override
  State<MapScene> createState() => _MapSceneState();
}

enum _View { constellation, outline }

class _MapSceneState extends State<MapScene> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _searchError;

  _View _view = _View.constellation;
  String? _selected;
  int? _outlineCourse;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  /// Enter: open the first matching node. Nodes of the newest course come
  /// first, then the other courses, newest first.
  void _submitSearch(List<CourseMap> maps) {
    final q = _query;
    if (q.isEmpty) return;
    for (final map in maps) {
      final hit = map.nodes.where((n) => n.title.toLowerCase().contains(q)).firstOrNull;
      if (hit != null) {
        context.go(AppRoutes.skill(hit.id));
        return;
      }
    }
    setState(() => _searchError = context.l10n.noMatchingNode);
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<StageController>();
    final tree = stage.lifeTree;
    final maps = stage.courseMaps;
    return StageScaffold(
      title: context.l10n.lifeTree,
      topLeading: IconButton(
        key: const Key('back-home'),
        tooltip: context.l10n.back,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(AppRoutes.home),
      ),
      stage: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: StatStrip(
                    stats: tree.stats,
                    compact: MediaQuery.sizeOf(context).width < 600,
                  ),
                ),
                // Phones: no room for her next to the numbers.
                if (MediaQuery.sizeOf(context).width >= 600) _Guide(empty: maps.isEmpty),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: !stage.loaded
                  ? const LoadingView()
                  : _view == _View.constellation
                  ? _night(context, tree)
                  : _outline(context, tree, maps),
            ),
          ),
          StageInputBar(
            controller: _search,
            focusNode: _focus,
            hint: context.l10n.searchNodesHint,
            search: true,
            onSubmit: () => _submitSearch(maps),
            onChanged: (_) => setState(() => _searchError = null),
            error: _searchError,
          ),
        ],
      ),
    );
  }

  // -- constellation ----------------------------------------------------------

  Widget _night(BuildContext context, LifeTree tree) {
    final identity = context.select<ProfileController, String>((p) => p.profile.identity);
    final theme = Theme.of(context).textTheme;
    final q = _query;
    final highlighted = q.isEmpty
        ? const <String>{}
        : {
            for (final n in tree.nodes)
              if (n.label.toLowerCase().contains(q)) n.key,
          };
    final selected = _selected == null ? null : tree.byKey(_selected!);
    return ClipRRect(
      key: const Key('night-panel'),
      borderRadius: AppRadius.panelBorder,
      child: ColoredBox(
        color: AppColors.night,
        child: LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 720;
            return Stack(
              children: [
                Positioned.fill(
                  child: LifeConstellation(
                    key: const Key('life-constellation'),
                    tree: tree,
                    selected: _selected,
                    highlighted: highlighted,
                    onSelect: (n) => setState(() => _selected = n.key),
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  top: AppSpacing.lg,
                  child: _ViewToggle(view: _view, dark: true, onChanged: _setView),
                ),
                if (identity.isNotEmpty && !narrow)
                  Positioned(
                    top: AppSpacing.lg + 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          '“$identity”',
                          key: const Key('life-identity'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.serif(theme.titleLarge)?.copyWith(
                            color: AppColors.nightLine,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: AppSpacing.lg,
                  right: narrow ? AppSpacing.lg : null,
                  bottom: AppSpacing.lg,
                  child: const _NightLegend(),
                ),
                if (!narrow)
                  Positioned(
                    right: AppSpacing.lg,
                    bottom: AppSpacing.lg,
                    child: Text(
                      context.l10n.dragToTurn,
                      style: theme.bodySmall?.copyWith(color: AppColors.nightMuted),
                    ),
                  ),
                if (tree.isEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: box.maxHeight * 0.18,
                    child: Text(
                      context.l10n.treeStartsWithYou,
                      key: const Key('life-empty'),
                      textAlign: TextAlign.center,
                      style: theme.bodyLarge?.copyWith(color: AppColors.nightLine),
                    ),
                  ),
                if (selected != null)
                  Positioned(
                    top: narrow ? null : AppSpacing.lg,
                    right: AppSpacing.lg,
                    left: narrow ? AppSpacing.lg : null,
                    bottom: narrow ? AppSpacing.lg : null,
                    width: narrow ? null : NodeSheet.width,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight * (narrow ? 0.72 : 1) - 2 * AppSpacing.lg - 12,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: NodeSheet(
                          key: ValueKey(selected.key),
                          node: selected,
                          tree: tree,
                          onClose: () => setState(() => _selected = null),
                          onOpenSkill: (id) => context.go(AppRoutes.skill(id)),
                          onOutline: (courseId) => setState(() {
                            _outlineCourse = courseId;
                            _view = _View.outline;
                          }),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _setView(_View v) => setState(() => _view = v);

  /// [child] takes the rest of a row, or stays as wide as it is in a column.
  static Widget _flexIf(bool flex, Widget child) => flex ? Expanded(child: child) : child;

  // -- outline ----------------------------------------------------------------

  Widget _outline(BuildContext context, LifeTree tree, List<CourseMap> maps) {
    final map = maps.where((m) => m.course.id == _outlineCourse).firstOrNull ?? maps.firstOrNull;
    final q = _query;
    final failed = {
      for (final n in tree.nodes)
        if (n.failed && n.skillId != null) n.skillId!,
    };
    // Phones: the course chips go under the toggle.
    final stacked = MediaQuery.sizeOf(context).width < 600;
    return DecoratedBox(
      key: const Key('outline-panel'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Stack(
        children: [
          if (map != null)
            Positioned.fill(
              top: stacked ? 100 : 56,
              child: SkillGraphView(
                key: ValueKey('graph-${map.course.id}'),
                map: map,
                failed: failed,
                highlighted: q.isEmpty
                    ? const {}
                    : {
                        for (final n in map.nodes)
                          if (n.title.toLowerCase().contains(q)) n.id,
                      },
                onOpen: (id) => context.go(AppRoutes.skill(id)),
              ),
            ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.md,
            child: Flex(
              direction: stacked ? Axis.vertical : Axis.horizontal,
              mainAxisSize: stacked ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ViewToggle(view: _view, dark: false, onChanged: _setView),
                const SizedBox(width: AppSpacing.lg, height: AppSpacing.sm),
                _flexIf(
                  !stacked,
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final m in maps)
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm),
                            child: ChoiceChip(
                              key: Key('outline-course-${m.course.id}'),
                              label: Text(courseNameOf(m)),
                              selected: m.course.id == map?.course.id,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _outlineCourse = m.course.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (map == null)
            Center(
              child: Text(
                context.l10n.noQuestLineYet,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          const Positioned(left: AppSpacing.lg, bottom: AppSpacing.lg, child: GraphLegend()),
        ],
      ),
    );
  }
}

/// `Tree | Outline`.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.dark, required this.onChanged});

  final _View view;
  final bool dark;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final track = dark ? AppColors.nightHigh : AppColors.surfaceHigh;
    final thumb = dark ? AppColors.nightText : AppColors.primary;
    final on = dark ? AppColors.night : AppColors.onAccent;
    final off = dark ? AppColors.nightLine : AppColors.textSecondary;
    Widget item(_View v, String label) {
      final active = v == view;
      return GestureDetector(
        key: Key('view-${v.name}'),
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? thumb : track,
            borderRadius: AppRadius.pillBorder,
          ),
          child: Text(label, style: theme.labelMedium?.copyWith(color: active ? on : off)),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: track, borderRadius: AppRadius.pillBorder),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(_View.constellation, context.l10n.viewTree),
            item(_View.outline, context.l10n.viewOutline),
          ],
        ),
      ),
    );
  }
}

/// The legend of the night panel.
class _NightLegend extends StatelessWidget {
  const _NightLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.nightLine);
    Widget dot({Color? fill, Color? ring, bool doubled = false}) => SizedBox.square(
      dimension: 12,
      child: Center(
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: ring == null ? null : Border.all(color: ring, width: doubled ? 2.5 : 1.4),
          ),
        ),
      ),
    );
    final entries = <(Widget, String)>[
      (dot(fill: AppColors.nightText), context.l10n.you),
      (dot(ring: AppColors.nightText), context.l10n.mainQuest),
      (dot(ring: AppColors.nightText, fill: AppColors.night), context.l10n.dotReady),
      (dot(fill: AppColors.ember), context.l10n.dotCleared),
      (dot(fill: AppColors.emberRed), context.l10n.auditFailed),
      (dot(fill: AppColors.nightMuted), context.l10n.dotLocked),
    ];
    return Wrap(
      key: const Key('night-legend'),
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (mark, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: 5),
              Text(label, style: style),
            ],
          ),
      ],
    );
  }
}

/// The small guide at the right of the numbers.
class _Guide extends StatelessWidget {
  const _Guide({required this.empty});

  final bool empty;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < AppLayout.wideBreakpoint;
    final line = empty
        ? context.l10n.mapEmptyLine
        : context.l10n.mapTapNode;
    return Row(
      key: const Key('map-guide'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SpeechBubble(
          key: const Key('map-bubble'),
          tail: BubbleTail.bottomRight,
          speaker: 'front_desk',
          maxWidth: narrow ? 150 : 230,
          child: Text(line, style: Theme.of(context).textTheme.bodySmall),
        ),
        Avatar(agent: 'front_desk', mood: AvatarMood.smile, size: narrow ? 56 : 72),
      ],
    );
  }
}
