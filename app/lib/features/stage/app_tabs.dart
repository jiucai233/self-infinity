import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../onboarding/guided_tour.dart';

/// The three places a phone can always reach from the bottom bar.
enum AppTab {
  home(AppRoutes.home),
  tree(AppRoutes.map),
  me(AppRoutes.me);

  const AppTab(this.root);

  /// Where the tab goes when tapped.
  final String root;

  /// The tab a [path] belongs to: the node, its audits and replays are under
  /// the life tree; the life overview is under Me.
  static AppTab of(String path) {
    final first = Uri.parse(path).pathSegments.firstOrNull;
    return switch (first) {
      'map' || 'skill' || 'audit' => AppTab.tree,
      'me' || 'life' => AppTab.me,
      _ => AppTab.home,
    };
  }

  /// Whether [path] is a tab's own page (no back arrow on a phone).
  static bool isRoot(String? path) => AppTab.values.any((t) => t.root == path);

  /// Whether the bar belongs on [path]: not in an audit, which needs the whole
  /// screen for the dialogue and the composer.
  static bool barOn(String path) {
    final segments = Uri.parse(path).pathSegments;
    return !(segments.length >= 3 && segments.first == 'skill' && segments[2] == 'audit');
  }
}

/// Wraps every scene of the router: below [AppLayout.wideBreakpoint] it puts
/// the [AppTabBar] under it. The bar is not there on wide screens (the three
/// columns already show everything), in an audit, while the keyboard is up
/// and in the guided tour. The scene keeps its place in the tree either way,
/// so nothing is rebuilt when the bar comes or goes.
class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.location, required this.child});

  /// The current path.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final show =
        !AppLayout.isWide(context) &&
        AppTab.barOn(location) &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        context.findAncestorWidgetOfExactType<GuidedTour>() == null;
    return ColoredBox(
      color: AppColors.canvas,
      child: Column(
        children: [
          Expanded(
            // The bar takes the bottom inset.
            child: MediaQuery.removePadding(context: context, removeBottom: show, child: child),
          ),
          if (show) AppTabBar(location: location),
        ],
      ),
    );
  }
}

/// The phone's bottom navigation (`docs/DESIGN.md`, clean): Home, Life tree,
/// Me. Ink on paper: a hairline on top, no pill and no ripple; the current tab
/// in ink, the others in secondary text. Each tab is at least 56 px tall.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.location});

  /// The current path; its tab is the selected one.
  final String location;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final current = AppTab.of(location);
    Widget tab(AppTab tab, IconData icon, String label, {Key? alias}) => Expanded(
      child: KeyedSubtree(
        key: alias,
        child: _Tab(
          key: Key('tab-${tab.name}'),
          icon: icon,
          label: label,
          selected: tab == current,
          onTap: () {
            if (location != tab.root) context.go(tab.root);
          },
        ),
      ),
    );
    return DecoratedBox(
      key: const Key('tab-bar'),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              tab(AppTab.home, Icons.home_outlined, l.tabHome),
              tab(AppTab.tree, Icons.park_outlined, l.lifeTree),
              // `open-left-drawer`: what used to open My character still does.
              tab(
                AppTab.me,
                Icons.person_outline_rounded,
                l.tabMe,
                alias: const Key('open-left-drawer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
