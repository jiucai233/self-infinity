import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The main call-to-action: a filled blue stadium button with an optional icon.
///
/// * `onPressed: null` disables it.
/// * [busy] shows a spinner and ignores taps while keeping the enabled look
///   (use it while a request is running).
/// * [expanded] stretches it to the available width.
///
/// For secondary actions use the themed `OutlinedButton` / `TextButton`.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: busy ? () {} : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onAccent),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (busy || icon != null) const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
