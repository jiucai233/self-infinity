/// The one exception type thrown by every [SelfInfinityApi] implementation.
library;

import '../l10n/l10n.dart';

/// A failed API call.
///
/// * [statusCode] is the HTTP status, or `null` when there was no response at
///   all (server down, DNS, CORS, timeout).
/// * [serverMessage] is the raw English `detail` message from the server
///   (for logs). **Never show it to the user** — show [userMessage].
///
/// [userMessage] implements the error text table of `docs/ui-spec.md`
/// Section 5, including the translations of the known 400 messages.
class ApiException implements Exception {
  const ApiException(this.statusCode, [this.serverMessage]);

  /// No response from the server.
  const ApiException.network([this.serverMessage]) : statusCode = null;

  final int? statusCode;
  final String? serverMessage;

  /// Whether the server could not be reached at all.
  bool get isNetworkError => statusCode == null;

  // -- texts (ui-spec Section 5), in the app's language -----------------------

  static String get networkText => l10nNow.errNetwork;
  static String get badRequestText => l10nNow.errBadRequest;
  static String get notFoundText => l10nNow.errNotFound;
  static String get invalidInputText => l10nNow.errInvalidInput;
  static String get aiFailureText => l10nNow.errAiFailure;
  static String get unknownText => l10nNow.somethingWentWrongShort;

  /// Server message (lower-cased, whitespace-collapsed) → its text, for the
  /// known 400 responses.
  static final Map<String, String Function(AppLocalizations)> known400Messages = {
    'skill is locked': (l) => l.errNodeLocked,
    _auditClosed: (l) => l.errAuditClosed,
    'reflection is only accepted for a failed audit': (l) => l.errLessonOnlyAfterFail,
    'reflection already submitted for this audit': (l) => l.errLessonAlreadyMade,
    'no node is available yet. generate a course or pass an existing node first.': (l) =>
        l.errNoNodeReady,
    'a gap or misconception id is required. search targets a specific gap only.': (l) =>
        l.errPickGap,
    'only pdf, txt or md files up to 4 mb.': (l) => l.uploadBadFile,
    'no text could be read from this file.': (l) => l.errFileUnreadable,
  };

  static const String _auditClosed = 'audit session is already closed';

  /// The audit was already over (a 400 the audit page handles by closing).
  bool get isAuditClosed => statusCode == 400 && _normalize(serverMessage) == _auditClosed;

  /// 401: the session expired or was revoked (the app then shows sign-in).
  static String get signedOutText => l10nNow.errSignedOut;

  /// The message that is safe to show in the UI, in the app's language.
  String get userMessage {
    final code = statusCode;
    if (code == null) return networkText;
    switch (code) {
      case 400:
        final known = known400Messages[_normalize(serverMessage)];
        return known?.call(l10nNow) ?? badRequestText;
      case 401:
        return signedOutText;
      case 404:
        return notFoundText;
      case 409:
        return serverMessage == 'at most 3 main quests' ? l10nNow.errMaxMainQuests : unknownText;
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
