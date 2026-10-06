import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A NotebookLM panel (`docs/DESIGN.md` Section 3): a white card with radius
/// 20 and no border, a 56 px title bar and, when [onCollapse] is given, a
/// button at the right of the bar that folds the panel into a [PanelRail].
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.title,
    required this.child,
    this.onCollapse,
    this.collapseIcon = Icons.keyboard_double_arrow_left_rounded,
    this.collapseKey,
    this.leading,
    this.titleChip,
    this.trailing,
  });

  /// The bar's title (`titleMedium`).
  final String title;

  /// A widget in front of the title (a back arrow).
  final Widget? leading;

  /// A small chip right of the title (the node's status).
  final Widget? titleChip;

  /// Buttons at the right end of the bar, before the collapse button.
  final Widget? trailing;

  final Widget child;

  /// Folds the panel; null = the panel cannot be folded.
  final VoidCallback? onCollapse;
  final IconData collapseIcon;
  final Key? collapseKey;

  static const double barHeight = 56;

  /// The decoration every panel shares.
  static BoxDecoration get decoration =>
      BoxDecoration(color: AppColors.sidebar, borderRadius: AppRadius.panelBorder);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: AppRadius.panelBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: barHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  left: leading == null ? AppSpacing.xl : AppSpacing.sm,
                  right: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    ?leading,
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              key: const Key('panel-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.titleMedium,
                            ),
                          ),
                          if (titleChip != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            titleChip!,
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                    if (onCollapse != null)
                      IconButton(
                        key: collapseKey,
                        tooltip: 'Collapse',
                        icon: Icon(collapseIcon, size: 20),
                        onPressed: onCollapse,
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

/// A folded [AppPanel]: a thin white rail with the expand button and the
/// title written sideways.
class PanelRail extends StatelessWidget {
  const PanelRail({
    super.key,
    required this.title,
    required this.onExpand,
    this.expandIcon = Icons.keyboard_double_arrow_right_rounded,
    this.expandKey,
  });

  final String title;
  final VoidCallback onExpand;
  final IconData expandIcon;
  final Key? expandKey;

  static const double width = 56;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: AppPanel.decoration,
        child: Column(
          children: [
            SizedBox(
              height: AppPanel.barHeight,
              child: Center(
                child: IconButton(
                  key: expandKey,
                  tooltip: 'Expand',
                  icon: Icon(expandIcon, size: 20),
                  onPressed: onExpand,
                ),
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      title,
                      key: const Key('rail-title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
