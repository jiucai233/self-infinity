import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import '../l10n/l10n.dart';

/// Accounts on Supabase Auth (email + password). Supabase keeps the session
/// in the browser and refreshes the token by itself; [accessToken] always
/// reads the current one.
///
/// `Supabase.initialize` must have run (see `main.dart`).
class SupabaseAuthService extends AuthService {
  SupabaseAuthService({GoTrueClient? client}) : _auth = client ?? Supabase.instance.client.auth {
    _sub = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final GoTrueClient _auth;
  late final StreamSubscription<AuthState> _sub;

  /// Where the links in Supabase's emails lead: the site on the web, the app
  /// itself on a phone (the `selfinfinity://` scheme of AndroidManifest.xml
  /// and Info.plist). Both must be in Supabase's Redirect URLs.
  static String get redirectUrl => kIsWeb ? Uri.base.origin : 'selfinfinity://login-callback';

  @override
  bool get enabled => true;

  @override
  bool get signedIn => _auth.currentSession != null;

  @override
  String? get userId => _auth.currentUser?.id;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  Future<AuthResult> signIn(String email, String password) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<AuthResult> signUp(String email, String password) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectUrl,
      );
      // With "Confirm email" on, Supabase returns the user but no session.
      return response.session == null ? const AuthResult(needsConfirmation: true) : AuthResult.ok;
    } on AuthException catch (e) {
      return AuthResult(error: messageFor(e));
    } on Object {
      return AuthResult(error: l10nNow.authOffline);
    }
  }

  @override
  Future<AuthResult> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email.trim(), redirectTo: redirectUrl));

  @override
  bool get supportsGoogle => true;

  /// Google must be on under Authentication → Providers in Supabase, with the
  /// OAuth client of a Google Cloud project (docs/deploy.md).
  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      final started = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      return started ? AuthResult.ok : AuthResult(error: l10nNow.googleFailed);
    } on AuthException catch (e) {
      return AuthResult(error: messageFor(e));
    } on Object {
      return AuthResult(error: l10nNow.googleFailed);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<AuthResult> _guard(Future<Object?> Function() call) async {
    try {
      await call();
      return AuthResult.ok;
    } on AuthException catch (e) {
      return AuthResult(error: messageFor(e));
    } on Object {
      return AuthResult(error: l10nNow.authOffline);
    }
  }

  /// Supabase's error, in the app's voice.
  static String messageFor(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) return l10nNow.authWrongCredentials;
    if (m.contains('email not confirmed')) return l10nNow.authConfirmEmailFirst;
    if (m.contains('already registered') || m.contains('already been registered')) {
      return l10nNow.authAlreadyRegistered;
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return l10nNow.authRateLimited;
    }
    if (m.contains('password')) return e.message;
    return l10nNow.somethingWentWrong;
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
