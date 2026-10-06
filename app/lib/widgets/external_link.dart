import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'toast.dart';

/// Opens [url] in the system browser / a new browser tab.
///
/// Only `http` and `https` URLs are opened. When the link cannot be opened a
/// snackbar says `Couldn't open the link.` — callers need no error handling.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  var opened = false;
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
  }
  if (!opened) {
    if (context.mounted) showToast(context, "Couldn't open the link.");
  }
}

/// The site of [url] without `www.` (`youtube.com`), for the second line of a
/// material row. Falls back to [url] itself when it has no host.
String displayDomain(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return url.trim();
  return host.startsWith('www.') ? host.substring(4) : host;
}
