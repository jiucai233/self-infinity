/// Accounts (`docs/api-contract.md` §7): who is signed in, and the token that
/// goes with every API call.
library;

import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';

/// What a sign-in / sign-up / reset call came to: [error] is the English text
/// to show (null on success); [needsConfirmation] means the account exists
/// but its email has to be confirmed before signing in.
@immutable
class AuthResult {
  const AuthResult({this.error, this.needsConfirmation = false});

  static const AuthResult ok = AuthResult();

  final String? error;
  final bool needsConfirmation;

  bool get isOk => error == null;
}

/// Signing in with email and password.
///
/// Three implementations: `SupabaseAuthService` (production), [LocalAuth]
/// (no accounts: local development, the offline demo) and `FakeAuthService`
/// (widget tests).
abstract class AuthService extends ChangeNotifier {
  /// Whether accounts exist at all. When false, [signedIn] is always true and
  /// nothing asks for a password.
  bool get enabled;

  bool get signedIn;

  /// Stable id of the signed-in account; changing it rebuilds every
  /// per-account controller.
  String? get userId;

  String? get email;

  /// The access token for `Authorization: Bearer …`, or null.
  String? get accessToken;

  /// At least this many characters in a new password (Supabase's default).
  static const int minPasswordLength = 6;

  Future<AuthResult> signIn(String email, String password);

  Future<AuthResult> signUp(String email, String password);

  /// Sends a "reset your password" email.
  Future<AuthResult> sendPasswordReset(String email);

  /// Whether "Continue with Google" is offered.
  bool get supportsGoogle => false;

  /// Signs in (or up) with a Google account. On the web the page goes to
  /// Google and comes back signed in; on a phone the browser opens and the
  /// app link brings the session back. The result only says whether the
  /// trip could start — [signedIn] turns true when the session arrives.
  Future<AuthResult> signInWithGoogle() async => AuthResult(error: l10nNow.googleFailed);

  Future<void> signOut();

  /// Checks an email + password pair before calling the server; null if fine.
  static String? validate(String email, String password, {bool newPassword = false}) {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@') || e.startsWith('@') || e.endsWith('@')) {
      return l10nNow.authInvalidEmail;
    }
    if (password.isEmpty) return l10nNow.authEnterPassword;
    if (newPassword && password.length < minPasswordLength) {
      return l10nNow.authPasswordTooShort(minPasswordLength);
    }
    return null;
  }
}

/// No accounts: everyone is the one local user (`AUTH_MODE=dev` on the
/// backend).
///
/// It starts signed in. [signOut] shows the front page (so it can be seen
/// locally); any valid email and password on it signs back in as the same
/// local user — no data changes either way.
class LocalAuth extends AuthService {
  bool _signedIn = true;

  @override
  bool get enabled => false;

  @override
  bool get signedIn => _signedIn;

  @override
  String? get userId => 'local';

  @override
  String? get email => null;

  @override
  String? get accessToken => null;

  @override
  Future<AuthResult> signIn(String email, String password) async => _enter();

  @override
  Future<AuthResult> signUp(String email, String password) async => _enter();

  AuthResult _enter() {
    _signedIn = true;
    notifyListeners();
    return AuthResult.ok;
  }

  @override
  Future<AuthResult> sendPasswordReset(String email) async => AuthResult.ok;

  @override
  Future<void> signOut() async {
    _signedIn = false;
    notifyListeners();
  }
}
