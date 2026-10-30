import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/panel_layout.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'app_tabs.dart';
import 'left_panel.dart';
import '../../l10n/l10n.dart';

/// The NotebookLM frame (`docs/DESIGN.md` Section 3, `docs/ux-chat.md` 5.1):
/// three white panels with 12 px gaps on the blue-grey canvas — the left
/// panel “My character”, the stage in the middle and, only when a [history] is
/// given (scenes 4, 4-1 and 5), the chat panel on the right.
///
/// Both side panels fold into a thin rail ([PanelLayout] remembers which).
/// Below [AppLayout.wideBreakpoint] the stage fills the screen: the left panel
/// is the Me tab of the bottom bar ([TabShell]) and the right panel a drawer,
/// opened from the history button at the right of the stage's title bar.
/// Between the breakpoint and [threeColumnWidth] the left panel stays a rail
/// when there is a chat panel, so that the stage keeps its room.
///
/// * [title] (and [titleChip]) fill the stage's title bar — the node's name.
/// * [topLeading] sits in front of it (a back arrow); a phone leaves it out
///   on a tab's own page ([AppTab.isRoot]), which the bar already reaches.
/// * [historyTitle] titles the right panel.
class StageScaffold extends StatelessWidget {
  const StageScaffold({
    super.key,
    required this.stage,
    this.history,
    this.historyTitle,
    this.title,
    this.titleChip,
    this.topLeading,
    this.showHistoryPanel = true,
  });

  /// The middle panel's content.
  final Widget stage;

  /// The content of the right panel; null = no right panel.
  final Widget? history;
  /// Defaults to “Chat”.
  final String? historyTitle;
  final String? title;
  final Widget? titleChip;
  final Widget? topLeading;

  /// On wide screens, whether [history] is shown as the right panel. A phone
  /// always has the history button when there is a [history], so that it
  /// does not come and go.
  final bool showHistoryPanel;

  /// With a chat panel the left panel only stays open from this width on.
  static const double threeColumnWidth = 1180;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppLayout.wideBreakpoint;
    final history = wide && !showHistoryPanel ? null : this.history;
    final tabRoot = !wide && AppTab.isRoot(ModalRoute.settingsOf(context)?.name);
    final leftTitle = context.l10n.myCharacter;
    final historyTitle = this.historyTitle ?? context.l10n.chatTitle;
    final layout = context.watch<PanelLayout>();
    final squeezed = wide && history != null && width < threeColumnWidth;
    final leftRail = wide && (layout.leftCollapsed || squeezed);
    final rightRail = layout.rightCollapsed;
    final gap = wide ? AppLayout.panelGap : AppSpacing.sm;

    final stagePanel = _StagePanel(
      title: title,
      titleChip: titleChip,
      topLeading: tabRoot ? null : topLeading,
      wide: wide,
      hasHistory: history != null,
      historyTitle: historyTitle,
      child: stage,
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      drawer: squeezed
          ? Drawer(
              width: 320,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: AppPanel(title: leftTitle, child: const LeftPanel()),
                ),
              ),
            )
          : null,
      endDrawer: wide || history == null
          ? null
          : Drawer(
              width: 360,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: _HistoryPanel(title: historyTitle, child: history),
                ),
              ),
            ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: wide
              ? Row(
                  children: [
                    if (leftRail)
                      Builder(
                        builder: (context) => PanelRail(
                          title: leftTitle,
                          expandKey: const Key('expand-left'),
                          onExpand: squeezed
                              ? () => Scaffold.of(context).openDrawer()
                              : () => layout.leftCollapsed = false,
                        ),
                      )
                    else
                      SizedBox(
                        width: AppLayout.sidePanelWidth,
                        child: AppPanel(
                          title: leftTitle,
                          collapseKey: const Key('collapse-left'),
                          onCollapse: () => layout.leftCollapsed = true,
                          child: const LeftPanel(),
                        ),
                      ),
                    const SizedBox(width: AppLayout.panelGap),
                    Expanded(child: stagePanel),
                    if (history != null) ...[
                      const SizedBox(width: AppLayout.panelGap),
                      if (rightRail)
                        PanelRail(
                          title: historyTitle,
                          expandIcon: Icons.keyboard_double_arrow_left_rounded,
                          expandKey: const Key('expand-right'),
                          onExpand: () => layout.rightCollapsed = false,
                        )
                      else
                        SizedBox(
                          width: _historyWidth(width),
                          child: _HistoryPanel(
                            title: historyTitle,
                            onCollapse: () => layout.rightCollapsed = true,
                            child: history,
                          ),
                        ),
                    ],
                  ],
                )
              : stagePanel,
        ),
      ),
    );
  }

  /// The chat panel is [AppLayout.chatPanelWidth], a bit slimmer on small
  /// desktop windows.
  static double _historyWidth(double screen) =>
      screen >= threeColumnWidth + 100 ? AppLayout.chatPanelWidth : 340;
}

/// The right panel: titled, with the `history-panel` key.
class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.title, required this.child, this.onCollapse});

  final String title;
  final Widget child;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      key: const Key('history-panel'),
      title: title,
      collapseKey: const Key('collapse-right'),
      collapseIcon: Icons.keyboard_double_arrow_right_rounded,
      onCollapse: onCollapse,
      child: child,
    );
  }
}

/// The middle panel: an optional title bar and the scene.
class _StagePanel extends StatelessWidget {
  const _StagePanel({
    required this.title,
    required this.titleChip,
    required this.topLeading,
    required this.wide,
    required this.hasHistory,
    required this.historyTitle,
    required this.child,
  });

  final String? title;
  final Widget? titleChip;
  final Widget? topLeading;
  final bool wide;
  final bool hasHistory;
  /// Defaults to “Chat”.
  final String? historyTitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showBar = !wide || title != null || topLeading != null;
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      key: const Key('stage-panel'),
      decoration: AppPanel.decoration,
      child: ClipRRect(
        borderRadius: AppRadius.panelBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBar)
              SizedBox(
                height: AppPanel.barHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Row(
                    children: [
                      ?topLeading,
                      Expanded(
                        child: Row(
                          children: [
                            if (title != null)
                              Flexible(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: topLeading == null ? AppSpacing.md : AppSpacing.xs,
                                  ),
                                  child: Text(
                                    title!,
                                    key: const Key('stage-title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.headlineSmall,
                                  ),
                                ),
                              ),
                            if (titleChip != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              titleChip!,
                            ],
                          ],
                        ),
                      ),
                      if (!wide && hasHistory)
                        Builder(
                          builder: (context) => IconButton(
                            key: const Key('open-right-drawer'),
                            tooltip: historyTitle,
                            icon: const Icon(Icons.forum_outlined),
                            onPressed: () => Scaffold.of(context).openEndDrawer(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
