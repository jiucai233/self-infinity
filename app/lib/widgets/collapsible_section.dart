import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A titled block of the left panel that folds by tapping its header: the title
/// on the left, an optional [trailing] note (`2/3`), a chevron on the right.
/// The parent owns the state ([folded] / [onToggle]).
///
/// [compact] is the quieter header of a block inside a section (the card
/// labels' size, secondary color).
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.folded,
    required this.onToggle,
    required this.child,
    this.trailing,
    this.compact = false,
    this.toggleKey,
  });

  final String title;
  final bool folded;
  final VoidCallback onToggle;
  final Widget child;

  /// A short note before the chevron (the quest count).
  final String? trailing;
  final bool compact;

  /// The key of the tappable header.
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final titleStyle = compact
        ? theme.labelMedium?.copyWith(color: AppColors.textSecondary)
        : theme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: !folded,
          label: title,
          child: InkWell(
            key: toggleKey,
            onTap: onToggle,
            borderRadius: AppRadius.chipBorder,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  if (trailing != null) ...[
                    Text(
                      trailing!,
                      style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Icon(
                    folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!folded) ...[const SizedBox(height: 2), child],
      ],
    );
  }
}
