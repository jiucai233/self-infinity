import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A short message at the bottom (a floating snackbar). It floats above the
/// input bar, so that it never covers ⊕ or the send button.
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final width = MediaQuery.sizeOf(context).width;
  final side = width > 420 + 2 * AppLayout.gutter ? (width - 420) / 2 : AppLayout.gutter;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        margin: EdgeInsets.fromLTRB(side, 0, side, 96),
        duration: const Duration(seconds: 3),
      ),
    );
}
