import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../auth/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';

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

class _SignInSceneState extends State<SignInScene> with SingleTickerProviderStateMixin {
  /// The entrance: 1.8 s, every part on its own interval of it.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
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
  void initState() {
    super.initState();
    if (Avatar.animationsEnabled) {
      _intro.forward();
    } else {
      _intro.value = 1;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
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
      backgroundColor: AppColors.canvas,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: _Hero(
                  tree: _sample(context.l10n),
                  wide: wide,
                  intro: _intro,
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

/// The [Curve] of every entrance (the reference's `[0.16, 1, 0.3, 1]`).
const Curve _ease = Cubic(0.16, 1, 0.3, 1);

/// 0→1 over [from, to] seconds of the 1.8 s entrance.
Animation<double> _part(AnimationController intro, double from, double to) => CurvedAnimation(
  parent: intro,
  curve: Interval(from / 1.8, to / 1.8, curve: _ease),
);

/// Fades [child] in while it slides from [dy] px to its place.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.dy, required this.child});

  final Animation<double> t;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: t,
    child: child,
    builder: (context, child) => Opacity(
      opacity: t.value.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, dy * (1 - t.value)), child: child),
    ),
  );
}

/// The landing hero.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.tree,
    required this.wide,
    required this.intro,
    required this.onSignIn,
    required this.onCreate,
  });

  final LifeTree tree;
  final bool wide;
  final AnimationController intro;
  final VoidCallback onSignIn;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final night = _part(intro, 0, 1.8);
    return Padding(
      padding: const EdgeInsets.all(AppLayout.panelGap),
      child: ClipRRect(
        borderRadius: AppRadius.panelBorder,
        child: ColoredBox(
          color: AppColors.night,
          child: Stack(
            children: [
              // The tree, like a background film: fades in from a little closer.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: night,
                  builder: (context, child) => Opacity(
                    opacity: night.value.clamp(0.0, 1.0),
                    child: Transform.scale(scale: 1.05 - 0.05 * night.value, child: child),
                  ),
                  child: Padding(
                    // Keep the tree's center above the paper at the bottom.
                    padding: EdgeInsets.only(bottom: wide ? 160 : 260),
                    child: LifeConstellation(tree: tree, compact: true),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Rise(
                  t: _part(intro, 0.5, 1.5),
                  dy: 20,
                  child: _Footer(wide: wide, intro: intro, onSignIn: onSignIn, onCreate: onCreate),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: _Rise(
                    t: _part(intro, 0, 0.8),
                    dy: -16,
                    child: _Nav(wide: wide, onSignIn: onSignIn),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top: the mark and the name on the left, Sign in on the right. Nothing
/// else — the page is about one sentence and one button.
class _Nav extends StatelessWidget {
  const _Nav({required this.wide, required this.onSignIn});

  final bool wide;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: wide
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xl)
          : const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const _Spark(size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Self-Infinity',
              key: const Key('hero-brand'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleMedium?.copyWith(color: AppColors.nightText, letterSpacing: -0.2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _LanguageMenu(),
          const SizedBox(width: AppSpacing.sm),
          _CirclePill(
            key: const Key('hero-sign-in'),
            circle: wide ? 32 : 28,
            label: context.l10n.signIn,
            onTap: onSignIn,
          ),
        ],
      ),
    );
  }
}

/// The language of the page (and of the app after signing in): the current
/// one's name; a tap lists all three.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>();
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.nightText);
    return PopupMenuButton<AppLanguage>(
      key: const Key('hero-language'),
      tooltip: context.l10n.language,
      position: PopupMenuPosition.under,
      onSelected: (language) => unawaited(locale.setLanguage(language)),
      itemBuilder: (_) => [
        for (final language in AppLanguage.values)
          PopupMenuItem(
            key: Key('hero-language-${language.code}'),
            value: language,
            child: Row(
              children: [
                Expanded(child: Text(language.nativeName)),
                if (language == locale.language)
                  const Icon(Icons.check_rounded, size: 18, color: AppColors.textPrimary),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 18, color: AppColors.nightText),
            const SizedBox(width: AppSpacing.xs),
            Text(locale.language.nativeName, style: style),
          ],
        ),
      ),
    );
  }
}

/// A paper pill: an ink circle with an arrow, then [label]. Hovered, the
/// arrow morphs into "sign in" (an arrow going through a door).
class _CirclePill extends StatefulWidget {
  const _CirclePill({super.key, required this.circle, required this.label, required this.onTap});

  final double circle;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CirclePill> createState() => _CirclePillState();
}

class _CirclePillState extends State<_CirclePill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.lg, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: widget.circle,
                    height: widget.circle,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: MorphIcon(
                      from: MorphShapes.arrow,
                      to: MorphShapes.signIn,
                      morphed: _hover,
                      size: 16,
                      strokeWidth: 2.2,
                      color: AppColors.onAccent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.label,
                    style: theme.labelMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom: paper fading up over the tree, the headline and the buttons.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.wide,
    required this.intro,
    required this.onSignIn,
    required this.onCreate,
  });

  final bool wide;
  final AnimationController intro;
  final VoidCallback onSignIn;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Rise(
          t: _part(intro, 0.6, 1.4),
          dy: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.ember, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  context.l10n.heroTagline,
                  style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Rise(
          t: _part(intro, 0.8, 1.6),
          dy: 20,
          child: Text(
            context.l10n.heroHeadline,
            key: const Key('hero-headline'),
            style: (wide ? theme.displayLarge : theme.displaySmall)?.copyWith(height: 1.0),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          t: _part(intro, 1.0, 1.8),
          dy: 16,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: const Key('hero-get-started'),
                onPressed: onCreate,
                child: Text(context.l10n.getStarted),
              ),
              OutlinedButton(
                key: const Key('hero-have-account'),
                onPressed: onSignIn,
                child: Text(context.l10n.haveAnAccountButton),
              ),
            ],
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          // Solid paper under the words, then a short fade: a long one mixes the night and
          // the paper into a muddy grey band.
          colors: [
            AppColors.background,
            AppColors.background,
            AppColors.background.withValues(alpha: 0.6),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.62, 0.84, 1],
        ),
      ),
      child: Padding(
        padding: wide
            ? const EdgeInsets.fromLTRB(AppSpacing.xxl, 160, AppSpacing.xxl, AppSpacing.xxl)
            : const EdgeInsets.fromLTRB(AppSpacing.lg, 120, AppSpacing.lg, AppSpacing.xl),
        child: Align(alignment: Alignment.centerLeft, child: left),
      ),
    );
  }
}

/// The mark: a four-point spark, like "You" at the center of the tree.
class _Spark extends StatelessWidget {
  const _Spark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SparkPainter());
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final w = r * 0.22;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w * 0.4, c.dy - w * 0.4, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w * 0.4, c.dy + w * 0.4, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w * 0.4, c.dy + w * 0.4, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w * 0.4, c.dy - w * 0.4, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.emberHot);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => false;
}
