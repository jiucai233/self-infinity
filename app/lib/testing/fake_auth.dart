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

  /// The Google account "Continue with Google" signs in as.
  static const String googleEmail = 'google.user@gmail.com';

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
    if (!_confirmed.contains(e)) return const AuthResult(needsConfirmation: true);
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

  /// The emails a confirmation link was sent to again.
  final List<String> resent = [];

  @override
  Future<AuthResult> resendConfirmation(String email) async {
    resent.add(email.trim());
    return AuthResult.ok;
  }

  @override
  Future<AuthResult> sendPasswordReset(String email) async {
    resets.add(email.trim());
    return AuthResult.ok;
  }

  String? _linkProblem;
  bool _recovering = false;

  /// The page was "opened" from an email link that failed with [message].
  void failLink(String message) {
    _linkProblem = message;
    notifyListeners();
  }

  /// A password-reset link was opened: signed in as [email], recovering.
  void openResetLink(String email) {
    _email = email;
    _recovering = true;
    notifyListeners();
  }

  @override
  String? get linkProblem => _linkProblem;

  @override
  void clearLinkProblem() => _linkProblem = null;

  @override
  bool get recovering => _recovering && signedIn;

  @override
  Future<AuthResult> updatePassword(String password) async {
    _passwords[_email!] = password;
    _recovering = false;
    notifyListeners();
    return AuthResult.ok;
  }

  @override
  bool get supportsGoogle => true;

  @override
  Future<AuthResult> signInWithGoogle() async {
    _passwords.putIfAbsent(googleEmail, () => '');
    _confirmed.add(googleEmail);
    _email = googleEmail;
    notifyListeners();
    return AuthResult.ok;
  }

  @override
  Future<void> signOut() async {
    _email = null;
    notifyListeners();
  }
}
