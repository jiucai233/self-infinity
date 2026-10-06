/// The one exception type thrown by every [SelfInfinityApi] implementation.
library;

/// A failed API call.
///
/// * [statusCode] is the HTTP status, or `null` when there was no response at
///   all (server down, DNS, CORS, timeout).
/// * [serverMessage] is the raw English `detail` message from the server
///   (for logs). **Never show it to the user** — show [userMessage].
///
/// [userMessage] implements the English error text table of `docs/ui-spec.md`
/// Section 5, including the translations of the known 400 messages.
class ApiException implements Exception {
  const ApiException(this.statusCode, [this.serverMessage]);

  /// No response from the server.
  const ApiException.network([this.serverMessage]) : statusCode = null;

  final int? statusCode;
  final String? serverMessage;

  /// Whether the server could not be reached at all.
  bool get isNetworkError => statusCode == null;

  // -- English texts (ui-spec Section 5) -------------------------------------

  static const String networkText = "Can't reach the server. Check your connection.";
  static const String badRequestText = "You can't do that right now.";
  static const String notFoundText = "We couldn't find that.";
  static const String invalidInputText = 'Please check what you entered.';
  static const String aiFailureText = 'Something went wrong on our side. Please try again.';
  static const String unknownText = 'Something went wrong.';

  /// Server message (lower-cased, whitespace-collapsed) → English text, for the
  /// known 400 responses.
  static const Map<String, String> known400Messages = {
    'skill is locked': 'This node is locked. Clear its parent first.',
    'audit session is already closed': 'This audit has already ended.',
    'reflection is only accepted for a failed audit':
        'Lesson cards can only be made after a failed audit.',
    'reflection already submitted for this audit': 'The lesson card is already made.',
    'no node is available yet. generate a course or pass an existing node first.':
        'No node is ready yet. Make a world first.',
    'a gap or misconception id is required. search targets a specific gap only.':
        'Pick a gap or misconception to search for.',
    'only pdf, txt or md files up to 4 mb.': 'Only PDF, TXT or MD files up to 4 MB.',
    'no text could be read from this file.': "Couldn't read any text from this file.",
  };

  /// 401: the session expired or was revoked (the app then shows sign-in).
  static const String signedOutText = 'Your session ended. Please sign in again.';

  /// The English message that is safe to show in the UI.
  String get userMessage {
    final code = statusCode;
    if (code == null) return networkText;
    switch (code) {
      case 400:
        final known = known400Messages[_normalize(serverMessage)];
        return known ?? badRequestText;
      case 401:
        return signedOutText;
      case 404:
        return notFoundText;
      case 409:
        return serverMessage == 'at most 3 main quests' ? 'You can have at most 3 main quests.' : unknownText;
      case 422:
        return invalidInputText;
      case 502:
        return aiFailureText;
      default:
        return unknownText;
    }
  }

  static String _normalize(String? message) =>
      (message ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  @override
  String toString() {
    final status = statusCode == null ? 'no response' : '$statusCode';
    return serverMessage == null
        ? 'ApiException($status)'
        : 'ApiException($status: $serverMessage)';
  }
}
