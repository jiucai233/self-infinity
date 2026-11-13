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
import 'graph_view.dart';
import 'node_sheet.dart';
import 'stat_strip.dart';
import '../../l10n/l10n.dart';

/// Your **life tree**, the home stage before a chat (scene 2 of
/// `docs/ux-chat.md`, merged into home on 2026-11-04).
///
/// * On top, your progress over every course in big numbers.
/// * Below, the night panel: you in the middle, your courses and their
///   nodes, turning slowly (`LifeConstellation`). Tap a point and its card
///   opens (`NodeSheet`): audit history, lessons, `Take it on`.
/// * `Outline` switches to the layered graph of one course (the old map).
/// * [overlay] is drawn over the night panel (her and the nodes she points
///   to); it hides while a node's card is open.
class LifeBoard extends StatefulWidget {
  const LifeBoard({super.key, this.overlay, this.legendLeft});

  /// Built over the night panel with the sky (for node positions) and the
  /// panel's constraints.
  final Widget Function(
    BuildContext context,
    GlobalKey<LifeConstellationState> sky,
    BoxConstraints box,
  )?
  overlay;

  /// Room kept free at the bottom left of a night panel of a size (where
  /// [overlay] puts her): the legend starts after it.
  final double Function(BoxConstraints box)? legendLeft;

  @override
  State<LifeBoard> createState() => _LifeBoardState();
}

enum _View { constellation, outline }

class _LifeBoardState extends State<LifeBoard> {
  _View _view = _View.constellation;
  final GlobalKey<LifeConstellationState> _sky = GlobalKey();
  String? _selected;
  int? _outlineCourse;
  bool _legendOpen = false;
  bool _nightLegendOpen = false;

  /// Narrower than this, the node card is a bottom sheet.
  static const double phoneWidth = 600;

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<StageController>();
    final tree = stage.lifeTree;
    final maps = stage.courseMaps;
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    final selected = _selected == null ? null : tree.byKey(_selected!);
    return Stack(
      key: const Key('life-board'),
      children: [
        Positioned.fill(child: _content(context, stage, tree, maps)),
        if (phone && selected != null && _view == _View.constellation)
          Positioned.fill(
            child: _PhoneSheet(
              key: ValueKey('phone-sheet-${selected.key}'),
              onClose: _closeSheet,
              builder: (controller) => NodeSheet(
                node: selected,
                tree: tree,
                scrollController: controller,
                onClose: _closeSheet,
                onOpenSkill: (id) => context.go(AppRoutes.skill(id)),
                onOutline: _showOutline,
              ),
            ),
          ),
      ],
    );
  }

  void _closeSheet() {
    if (mounted && _selected != null) setState(() => _selected = null);
  }

  void _showOutline(int courseId) => setState(() {
    _outlineCourse = courseId;
    _view = _View.outline;
  });

  Widget _content(
    BuildContext context,
    StageController stage,
    LifeTree tree,
    List<CourseMap> maps,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.lg : AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.lg,
            compact ? AppSpacing.sm : AppSpacing.lg,
          ),
          child: StatStrip(stats: tree.stats, compact: compact),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.sm : AppSpacing.lg),
            child: !stage.loaded
                ? const LoadingView()
                : _view == _View.constellation
                ? _night(context, tree)
                : _outline(context, tree, maps),
          ),
        ),
      ],
    );
  }

  // -- constellation ----------------------------------------------------------

  Widget _night(BuildContext context, LifeTree tree) {
    final identity = context.select<ProfileController, String>((p) => p.profile.identity);
    final theme = Theme.of(context).textTheme;
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
                    key: _sky,
                    tree: tree,
                    selected: _selected,
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
                if (widget.overlay case final overlay? when selected == null && !tree.isEmpty)
                  Positioned.fill(child: overlay(context, _sky, box)),
                Positioned(
                  left: AppSpacing.lg + (selected == null ? widget.legendLeft?.call(box) ?? 0 : 0),
                  right: narrow ? AppSpacing.lg : null,
                  bottom: AppSpacing.lg,
                  // Folded behind a `?` until asked for: the first screen shows
                  // only what is needed (2026-11-04 review).
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: _LegendButton(
                      toggleKey: const Key('night-legend-toggle'),
                      dark: true,
                      open: _nightLegendOpen,
                      onToggle: () => setState(() => _nightLegendOpen = !_nightLegendOpen),
                      legend: const _NightLegend(),
                    ),
                  ),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: narrow ? AppSpacing.lg + 64 : AppSpacing.lg,
                  child: _ZoomButtons(
                    onZoomIn: () => _sky.currentState?.zoomStep(1.5),
                    onZoomOut: () => _sky.currentState?.zoomStep(1 / 1.5),
                    onReset: () => _sky.currentState?.resetView(),
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
                // A phone: the card is a bottom sheet over the whole stage.
                if (selected != null && MediaQuery.sizeOf(context).width >= phoneWidth)
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
                          onOutline: _showOutline,
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
          Positioned(
            left: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: _LegendButton(
              open: _legendOpen,
              onToggle: () => setState(() => _legendOpen = !_legendOpen),
              legend: GraphLegend(
                unexpanded: map?.nodes.any((n) => n.unexpanded && !n.isMastered) ?? false,
              ),
            ),
          ),
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

/// Zoom in, zoom out and back to the start, on the night panel.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.onZoomIn, required this.onZoomOut, required this.onReset});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget button(String key, IconData icon, String tip, VoidCallback onTap) => IconButton(
      key: Key(key),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: AppColors.nightText,
      icon: Icon(icon),
    );
    return DecoratedBox(
      key: const Key('night-zoom'),
      decoration: BoxDecoration(color: AppColors.nightHigh, borderRadius: AppRadius.pillBorder),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('zoom-out', Icons.remove_rounded, l.zoomOut, onZoomOut),
          button('zoom-reset', Icons.center_focus_strong_rounded, l.resetView, onReset),
          button('zoom-in', Icons.add_rounded, l.zoomIn, onZoomIn),
        ],
      ),
    );
  }
}

/// The legend of the night panel.
class _NightLegend extends StatelessWidget {
  const _NightLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.nightHint);
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
      (dot(ring: AppColors.nightText, fill: AppColors.night), context.l10n.dotReady),
      (dot(fill: AppColors.cleared), context.l10n.dotCleared),
      (dot(fill: AppColors.emberRed), context.l10n.auditFailed),
      // As the tree draws it: a dark disc in a grey ring.
      (dot(fill: AppColors.nightHigh, ring: AppColors.nightLine), context.l10n.dotLocked),
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

/// The node card on a phone: a Material bottom sheet over the stage. It opens
/// at about two thirds, drags up to the full stage (the whole card and its
/// button), and down to close.
class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({super.key, required this.builder, required this.onClose});

  final Widget Function(ScrollController controller) builder;
  final VoidCallback onClose;

  /// How much of the stage the sheet covers when it opens.
  static const double start = 0.66;

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet> {
  bool _closing = false;

  bool _onExtent(DraggableScrollableNotification n) {
    if (!_closing && n.extent <= 0.12) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      child: DraggableScrollableSheet(
        key: const Key('node-bottom-sheet'),
        initialChildSize: _PhoneSheet.start,
        minChildSize: 0,
        maxChildSize: 1,
        snap: true,
        snapSizes: const [_PhoneSheet.start],
        builder: (context, controller) => widget.builder(controller),
      ),
    );
  }
}

/// A small `?` at the bottom left of the outline; it opens the legend above it.
class _LegendButton extends StatelessWidget {
  const _LegendButton({
    required this.open,
    required this.onToggle,
    required this.legend,
    this.dark = false,
    this.toggleKey = const Key('graph-legend-toggle'),
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget legend;

  /// On the night panel: light marks on the dark.
  final bool dark;
  final Key toggleKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (open) ...[legend, const SizedBox(height: AppSpacing.sm)],
        IconButton.outlined(
          key: toggleKey,
          tooltip: context.l10n.legend,
          isSelected: open,
          onPressed: onToggle,
          visualDensity: VisualDensity.compact,
          color: dark ? AppColors.nightText : null,
          style: dark
              ? IconButton.styleFrom(
                  side: const BorderSide(color: AppColors.nightLine),
                  foregroundColor: AppColors.nightText,
                  backgroundColor: AppColors.nightHigh,
                )
              : null,
          icon: const Icon(Icons.question_mark_rounded, size: 18),
          selectedIcon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    );
  }
}
