import '../auth/auth_service.dart';

/// In-memory accounts for widget tests and the offline demo.
///
/// [confirmEmail]: a sign-up must be confirmed (with [confirm]) before
/// signing in, as on Supabase with "Confirm email" on.
class FakeAuthService extends AuthService {
  FakeAuthService({this.confirmEmail = false, Map<String, String>? accounts}) {
    _passwords.addAll(accounts ?? const {});
    _confirmed.addAll(accounts?.keys ?? const <String>[]);
  }

  final bool confirmEmail;
  final Map<String, String> _passwords = {};
  final Set<String> _confirmed = {};
  String? _email;

  /// Emails a reset link was "sent" to.
  final List<String> resets = [];

  @override
  bool get enabled => true;

  @override
  bool get signedIn => _email != null;

  @override
  String? get userId => _email == null ? null : 'user:$_email';

  @override
  String? get email => _email;

  @override
  String? get accessToken => _email == null ? null : 'token:$_email';

  /// Confirms the email of an account (the link in the inbox).
  void confirm(String email) => _confirmed.add(email);

  @override
  Future<AuthResult> signIn(String email, String password) async {
    final e = email.trim();
    if (_passwords[e] != password) return const AuthResult(error: 'Wrong email or password.');
    if (!_confirmed.contains(e)) {
      return const AuthResult(error: 'Confirm your email first — check your inbox.');
    }
    _email = e;
    notifyListeners();
    return AuthResult.ok;
  }

  @override
  Future<AuthResult> signUp(String email, String password) async {
    final e = email.trim();
    if (_passwords.containsKey(e)) {
      return const AuthResult(error: 'That email already has an account. Sign in instead.');
    }
    _passwords[e] = password;
    if (confirmEmail) return const AuthResult(needsConfirmation: true);
    _confirmed.add(e);
    _email = e;
    notifyListeners();
    return AuthResult.ok;
  }

  @override
  Future<AuthResult> sendPasswordReset(String email) async {
    resets.add(email.trim());
    return AuthResult.ok;
  }

  @override
  Future<void> signOut() async {
    _email = null;
    notifyListeners();
  }
}
