import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';
import '../theme/tokens.dart';
import '../l10n/l10n.dart';
import 'toast.dart';

/// Shows a failed call in plain English — never a stack trace (FT-12).
///
/// * An [ApiException] shows its `userMessage` (see ui-spec Section 5).
/// * Anything else shows `Something went wrong.` (the error is not printed).
/// * [onRetry] adds a `Try again` button.
/// * The message can be selected, and `Copy` takes it with what the server
///   said ([detailsFor]) — what one sends when reporting the failure.
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

  /// What `Copy` puts on the clipboard: the message, and for a failed call
  /// its status and the server's own words.
  static String detailsFor(Object error) {
    final message = messageFor(error);
    if (error is! ApiException || error.isNetworkError) return message;
    final server = error.serverMessage;
    return '$message (HTTP ${error.statusCode}${server == null || server.isEmpty ? '' : ': $server'})';
  }

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
              SelectionArea(
                child: Text(
                  messageFor(e),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (onRetry != null)
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: Text(context.l10n.tryAgain),
                    ),
                  TextButton.icon(
                    key: const Key('error-copy'),
                    onPressed: () {
                      unawaited(Clipboard.setData(ClipboardData(text: detailsFor(e))));
                      showToast(context, context.l10n.copied);
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(context.l10n.copy),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
