import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme/tokens.dart';
import '../l10n/l10n.dart';

/// Shows a failed call in plain English — never a stack trace (FT-12).
///
/// * An [ApiException] shows its `userMessage` (see ui-spec Section 5).
/// * Anything else shows `Something went wrong.` (the error is not printed).
/// * [onRetry] adds a `Try again` button.
///
/// ```dart
/// ErrorView(error: snapshot.error!, onRetry: _reload)
/// ```
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  /// The text that is shown for [error].
  static String messageFor(Object error) =>
      error is ApiException ? error.userMessage : ApiException.unknownText;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final isNetwork = e is ApiException && e.isNetworkError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNetwork ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                size: 28,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                messageFor(e),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(context.l10n.tryAgain),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
