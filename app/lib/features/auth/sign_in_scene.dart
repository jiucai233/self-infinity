import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../auth/auth_service.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../auth/google_mark.dart';
import 'landing_page.dart';

/// The front door (`docs/ux-chat.md` §7): a landing hero, and sign in /
/// create an account (email and password only) in a card over it.
///
/// The hero is a night panel filling the window with a sample life tree
/// turning in it; pill navigation on top (`Sign in`, `Create account`); at the
/// bottom, paper fades up over the tree and carries the headline and the two
/// buttons. Everything eases in once, staggered. The form opens as a card in
/// the middle (a sheet at the bottom on a phone); Esc or × closes it.
class SignInScene extends StatefulWidget {
  const SignInScene({super.key});

  @override
  State<SignInScene> createState() => _SignInSceneState();
}

enum _Mode { signIn, signUp, checkInbox, resetSent }

class _SignInSceneState extends State<SignInScene> {
  bool _formOpen = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  static final Map<String, LifeTree> _samples = {};
  static LifeTree _sample(AppLocalizations l) => _samples[l.localeName] ??= _sampleTree(l);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    final signUp = _mode == _Mode.signUp;
    final problem = AuthService.validate(_email.text, _password.text, newPassword: signUp);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = signUp
        ? await auth.signUp(_email.text, _password.text)
        : await auth.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      if (result.needsConfirmation) _mode = _Mode.checkInbox;
    });
  }

  /// Off to Google; the session arrives with the redirect back (the auth
  /// service then turns signed in and the app replaces this page).
  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await context.read<AuthService>().signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (AuthService.validate(email, 'x') != null) {
      setState(() => _error = context.l10n.enterEmailFirst);
      return;
    }
    setState(() => _busy = true);
    final result = await context.read<AuthService>().sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      if (result.isOk) _mode = _Mode.resetSent;
    });
  }

  void _switch(_Mode mode) => setState(() {
    _mode = mode;
    _error = null;
  });

  void _open(_Mode mode) => setState(() {
    _mode = mode;
    _error = null;
    _formOpen = true;
  });

  void _close() {
    if (_busy) return;
    setState(() => _formOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppLayout.heroBreakpoint;
    return Scaffold(
      key: const Key('sign-in'),
      backgroundColor: AppColors.surface,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        // The front page takes the keys (its arrows turn screens); Escape
        // comes up from it.
        child: Focus(
          child: Stack(
            children: [
              Positioned.fill(
                child: LandingPage(
                  tree: _sample(context.l10n),
                  onSignIn: () => _open(_Mode.signIn),
                  onCreate: () => _open(_Mode.signUp),
                ),
              ),
              if (_formOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('auth-scrim'),
                    onTap: _close,
                    child: ColoredBox(color: AppColors.night.withValues(alpha: 0.45)),
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Align(
                      alignment: wide ? Alignment.center : Alignment.bottomCenter,
                      child: _formCard(context, wide),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The form on a paper card: centered when wide, a bottom sheet on a phone.
  Widget _formCard(BuildContext context, bool wide) {
    return Padding(
      padding: EdgeInsets.all(wide ? AppSpacing.xl : AppLayout.panelGap),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        // The shadow sits outside the clip; inside it, it greys the card's edges.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.panelBorder,
            boxShadow: AppShadows.float,
          ),
          child: Material(
            key: const Key('auth-card'),
            color: AppColors.surface,
            borderRadius: AppRadius.panelBorder,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(key: ValueKey(_mode), child: _body(context)),
                  ),
                ),
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: IconButton(
                    key: const Key('auth-close'),
                    tooltip: context.l10n.close,
                    onPressed: _busy ? null : _close,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final auth = context.watch<AuthService>();
    switch (_mode) {
      case _Mode.checkInbox:
      case _Mode.resetSent:
        final inbox = _mode == _Mode.checkInbox;
        return Column(
          key: Key(inbox ? 'check-inbox' : 'reset-sent'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 28, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l10n.checkInbox, style: theme.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              inbox
                  ? context.l10n.confirmLinkSent(_email.text.trim())
                  : context.l10n.resetLinkSent(_email.text.trim()),
              style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              key: const Key('back-to-sign-in'),
              onPressed: () => _switch(_Mode.signIn),
              child: Text(context.l10n.backToSignIn),
            ),
          ],
        );
      case _Mode.signIn:
      case _Mode.signUp:
        final signUp = _mode == _Mode.signUp;
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                signUp ? context.l10n.createYourAccount : context.l10n.welcomeBack,
                key: const Key('auth-title'),
                style: theme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                signUp
                    ? context.l10n.signUpBlurb
                    : context.l10n.signInBlurb,
                style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: const Key('auth-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                enabled: !_busy,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: InputDecoration(hintText: context.l10n.email),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('auth-password'),
                controller: _password,
                focusNode: _passwordFocus,
                obscureText: !_showPassword,
                autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                textInputAction: TextInputAction.done,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: signUp
                      ? context.l10n.passwordWithMin(AuthService.minPasswordLength)
                      : context.l10n.password,
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? context.l10n.hidePassword : context.l10n.showPassword,
                    icon: Icon(
                      _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  key: const Key('auth-error'),
                  style: theme.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                key: const Key('auth-submit'),
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textTertiary,
                        ),
                      )
                    : Text(signUp ? context.l10n.createAccount : context.l10n.signIn),
              ),
              if (auth.supportsGoogle) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text(
                        context.l10n.orDivider,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  key: const Key('auth-google'),
                  onPressed: _busy ? null : _google,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const GoogleMark(),
                  label: Text(context.l10n.continueWithGoogle),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // A Wrap, not a Row: on a phone the switch drops under its question.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        signUp ? context.l10n.haveAccount : context.l10n.newHere,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                      TextButton(
                        key: const Key('auth-switch'),
                        onPressed: _busy
                            ? null
                            : () => _switch(signUp ? _Mode.signIn : _Mode.signUp),
                        child: Text(signUp ? context.l10n.signIn : context.l10n.createAnAccount),
                      ),
                    ],
                  ),
                  if (!signUp)
                    TextButton(
                      key: const Key('auth-forgot'),
                      onPressed: _busy ? null : _reset,
                      style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
                      child: Text(context.l10n.forgotPassword),
                    ),
                ],
              ),
            ],
          ),
        );
    }
  }

  /// A small sample tree for the night panel: a few courses, some of it
  /// cleared.
  static LifeTree _sampleTree(AppLocalizations l) {
    CourseMap course(int id, String root, List<String> branches, int cleared) {
      final nodes = <SkillNode>[];
      final edges = <SkillEdge>[];
      var next = id * 100;
      SkillNode node(String title, SkillStatus status) => SkillNode(
        id: next++,
        courseId: id,
        slug: 'n$next',
        title: title,
        description: '',
        status: status,
        nodeType: NodeType.concept,
      );
      final r = node(root, SkillStatus.mastered);
      nodes.add(r);
      var done = 1;
      for (final b in branches) {
        final branch = node(b, done < cleared ? SkillStatus.mastered : SkillStatus.available);
        done++;
        nodes.add(branch);
        edges.add(
          SkillEdge(fromId: r.id, toId: branch.id, kind: SkillEdgeKind.contains, isPrimary: true),
        );
        for (var i = 0; i < 3; i++) {
          final leaf = node('$b $i', done < cleared ? SkillStatus.mastered : SkillStatus.locked);
          done++;
          nodes.add(leaf);
          edges.add(
            SkillEdge(
              fromId: branch.id,
              toId: leaf.id,
              kind: SkillEdgeKind.contains,
              isPrimary: true,
            ),
          );
        }
      }
      return CourseMap(
        course: Course(id: id, topic: root, createdAt: DateTime.utc(2026)),
        nodes: nodes,
        edges: edges,
      );
    }

    return LifeTree.build(
      goals: [
        Goal(id: 1, title: l.mainQuest, courseIds: const [1, 2], createdAt: DateTime.utc(2026)),
        Goal(id: 2, title: l.mainQuest, courseIds: const [3], createdAt: DateTime.utc(2026)),
      ],
      maps: [
        course(1, l.sampleCalculus, [l.sampleLimits, l.sampleDerivatives, l.sampleIntegrals], 7),
        course(2, l.sampleStatistics, [l.sampleProbability, l.sampleInference], 3),
        course(3, l.sampleWriting, [l.sampleClarity, l.sampleStructure], 4),
      ],
    );
  }
}
