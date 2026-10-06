import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../l10n/l10n.dart';

/// A centered progress indicator with a message.
///
/// ```dart
/// const LoadingView(message: 'Building your world…')
/// ```
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  /// Defaults to “Loading…”.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message ?? context.l10n.loading,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
