import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/fake_api.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../auth/auth_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../voice/voice_service.dart';
import '../../widgets/widgets.dart';

/// One stop of the [GuidedTour]: the page it is on, the part of it that
/// stays lit, and what the Guide says about it.
@immutable
class TourStop {
  const TourStop({this.route, this.anchor, required this.text, this.optional = false});

  /// The page to be on; null keeps the page of the stop before.
  final String? route;

  /// The widget that stays lit (found by its key); null darkens everything
  /// and puts the Guide in the middle.
  final Key? anchor;
  final String Function(AppLocalizations l) text;

  /// A stop whose [anchor] is not on this screen (a side panel on a phone)
  /// is passed over instead of shown without one.
  final bool optional;
}

/// The guided tour a new account sees before the setup (`docs/ux-chat.md`
/// §7): the real scenes over an example world, everything dark but the part
/// the Guide is talking about. It goes from the left panel to the stage, then
/// to the life tree, a node (its contents, the attempts on its right, the way
/// into an audit) and an audit, and ends on what the setup is about to ask:
/// the topic or syllabus that shapes the first tree.
///
/// The world is a [FakeApiClient] of its own (a character with a main quest,
/// a course built from a syllabus, one node cleared and one failed, today's
/// quests): nothing here reaches the account, and nothing can be tapped but
/// the tour's own buttons.
class GuidedTour extends StatefulWidget {
  const GuidedTour({
    super.key,
    required this.theme,
    required this.locale,
    required this.onDone,
  });

  final ThemeData theme;
  final Locale locale;

  /// The tour was finished or skipped.
  final VoidCallback onDone;

  /// The stops, given the example node (a leaf with knowledge points).
  static List<TourStop> stops(int nodeId) => [
    TourStop(route: AppRoutes.home, text: (l) => l.tourWelcome),
    TourStop(anchor: const Key('left-panel'), text: (l) => l.tourCharacter, optional: true),
    TourStop(anchor: const Key('daily-quests'), text: (l) => l.tourQuests, optional: true),
    TourStop(anchor: const Key('stage-input'), text: (l) => l.tourTalk),
    TourStop(route: AppRoutes.map, anchor: const Key('night-panel'), text: (l) => l.tourTree),
    TourStop(
      route: AppRoutes.skill(nodeId),
      anchor: const Key('skill-contents'),
      text: (l) => l.tourNode,
    ),
    TourStop(anchor: const Key('history-panel'), text: (l) => l.tourAttempts, optional: true),
    TourStop(anchor: const Key('start-audit'), text: (l) => l.tourProve),
    TourStop(
      route: AppRoutes.audit(nodeId),
      anchor: const Key('audit-bubble'),
      text: (l) => l.tourAudit,
    ),
    TourStop(route: AppRoutes.map, text: (l) => l.tourSyllabus),
  ];

  @override
  State<GuidedTour> createState() => _GuidedTourState();
}

class _GuidedTourState extends State<GuidedTour> {
  final FakeApiClient _world = FakeApiClient(latency: Duration.zero);
  final AppState _appState = AppState();
  final GlobalKey _scenes = GlobalKey();
  final GlobalKey _overlay = GlobalKey();
  GoRouter? _router;
  List<TourStop> _stops = const [];

  int _index = 0;

  /// +1 or -1: which way a stop without its anchor is passed over.
  int _direction = 1;

  /// The lit part, in the overlay's coordinates; null while it is looked for
  /// or when the stop has none.
  Rect? _lit;

  /// How often the anchor of this stop was looked for without finding it.
  int _misses = 0;
  Timer? _watch;

  static const Duration _watchEvery = Duration(milliseconds: 120);

  static const String _exampleQuest = 'Teach calculus to a stranger';
  static const String _exampleIdentity =
      'I am the type of person who explains it before I memorize it.';

  /// Long enough for the scripted Auditor to pass it.
  static const String _exampleAnswer =
      'It is a way to find a value under given conditions. It works because the conditions pin '
      'the value down to exactly one answer, and it fails when they contradict each other or are '
      'too loose, so the range has to be stated first.';

  /// After this many looks an anchor counts as not on this screen.
  static const int _patience = 12;

  @override
  void initState() {
    super.initState();
    unawaited(_buildWorld());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _router?.dispose();
    super.dispose();
  }

  /// Plays an audit of [nodeId] in the example world with the same [answer]
  /// until its verdict.
  Future<void> _audit(int nodeId, String answer) async {
    final audit = await _world.startAudit(nodeId);
    for (var i = 0; i < 12; i++) {
      if (await _world.submitTurn(audit.session.id, answer) is VerdictResult) return;
    }
  }

  /// The example world: a character with a main quest, a course from a
  /// syllabus under it, one node cleared (lit on the tree) and the next tried
  /// and failed (its knowledge points show what held and what did not), and
  /// today's quests asked for.
  Future<void> _buildWorld() async {
    var nodeId = 1;
    try {
      final course = await _world.generateCourse(const GenerateRequest(topic: 'math'));
      int? open(CourseMap map) => map.nodes.where((n) => n.isAvailable).firstOrNull?.id;
      final first = open(await _world.getCourseMap(course.course.id));
      if (first != null) await _audit(first, _exampleAnswer);
      nodeId = open(await _world.getCourseMap(course.course.id)) ?? first ?? nodeId;
      await _audit(nodeId, "I'm not sure");
      final quest = await _world.createGoal(_exampleQuest);
      await _world.updateGoal(quest.id, courseIds: [course.course.id]);
      await _world.updateProfile(identity: _exampleIdentity);
      await _world.sendChat('What should I do today?');
    } on Object {
      // An emptier example still shows where things are.
    }
    if (!mounted) return;
    setState(() {
      _stops = GuidedTour.stops(nodeId);
      _router = createRouter(initialLocation: _stops.first.route);
    });
    _watch = Timer.periodic(_watchEvery, (_) => _look());
  }

  TourStop get _stop => _stops[_index];

  void _go(int index) {
    final direction = index >= _index ? 1 : -1;
    // A stop on the page already shown whose part is not on this screen (a side
    // panel on a phone) is passed over at once, without showing it first.
    while (index >= 0 &&
        index < _stops.length &&
        _stops[index].optional &&
        _stops[index].route == null &&
        _find(_stops[index].anchor!) == null) {
      index += direction;
    }
    if (index < 0) return;
    if (index >= _stops.length) {
      widget.onDone();
      return;
    }
    final route = _stops[index].route;
    setState(() {
      _direction = direction;
      _index = index;
      _lit = null;
      _misses = 0;
    });
    // Going back needs the page of the nearest stop before that names one.
    final page = route ?? _stops.sublist(0, index).reversed.map((s) => s.route).nonNulls.firstOrNull;
    if (page != null) _router?.go(page);
  }

  /// Finds the anchor of this stop on the page and follows it (the page
  /// loads, scrolls and resizes under the tour).
  void _look() {
    if (!mounted || _stops.isEmpty) return;
    final anchor = _stop.anchor;
    if (anchor == null) return;
    final found = _find(anchor);
    final overlay = _overlay.currentContext?.findRenderObject();
    final box = found?.findRenderObject();
    if (found == null || box is! RenderBox || !box.hasSize || overlay is! RenderBox) {
      if (++_misses == _patience && _stop.optional) _go(_index + _direction);
      return;
    }
    if (_lit == null) {
      // Bring it into view once (the quests sit low in the left panel).
      unawaited(Scrollable.ensureVisible(found, alignment: 0.5, duration: Duration.zero));
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final lit = rect.intersect(Offset.zero & overlay.size);
    if (lit.width <= 0 || lit.height <= 0) return;
    if (_lit == null || (lit.topLeft - _lit!.topLeft).distance > 0.5 || lit.size != _lit!.size) {
      setState(() => _lit = lit);
    }
  }

  Element? _find(Key key) {
    final root = _scenes.currentContext;
    if (root == null) return null;
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: widget.theme,
        locale: widget.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(key: Key('tour-loading'), body: LoadingView()),
      );
    }
    // The example world's own controllers; the device (voice, files, account) is the app's.
    return AppProviders(
      api: _world,
      appState: _appState,
      voice: context.read<VoiceService>(),
      filePicker: context.read<FilePickerService>(),
      auth: context.read<AuthService>(),
      child: MaterialApp.router(
        title: 'Self-Infinity',
        debugShowCheckedModeBanner: false,
        theme: widget.theme,
        locale: widget.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => Stack(
          key: const Key('guided-tour'),
          children: [
            // Looked at, never touched: only the tour's buttons take input.
            IgnorePointer(
              child: KeyedSubtree(key: _scenes, child: child ?? const SizedBox.shrink()),
            ),
            Positioned.fill(
              child: _TourOverlay(
                key: _overlay,
                lit: _stop.anchor == null ? null : _lit,
                text: _stop.text(context.l10n),
                index: _index,
                count: _stops.length,
                onBack: _index == 0 ? null : () => _go(_index - 1),
                onNext: () => _go(_index + 1),
                onSkip: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark sheet over the page with one part left lit, and the Guide's card
/// next to it.
class _TourOverlay extends StatelessWidget {
  const _TourOverlay({
    super.key,
    required this.lit,
    required this.text,
    required this.index,
    required this.count,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final Rect? lit;
  final String text;
  final int index;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// Air between the lit part and its edge, and between it and the card.
  static const double _halo = 6;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final lit = this.lit?.inflate(_halo);
    return Stack(
      children: [
        // Takes every tap that is not on the card.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            // The lit part glides from one stop to the next.
            child: lit == null
                ? const CustomPaint(key: Key('tour-scrim'), painter: _ScrimPainter(null))
                : TweenAnimationBuilder<Rect?>(
                    tween: RectTween(end: lit),
                    duration: Avatar.animationsEnabled
                        ? const Duration(milliseconds: 260)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    builder: (context, rect, _) => CustomPaint(
                      key: const Key('tour-scrim'),
                      painter: _ScrimPainter(rect),
                    ),
                  ),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _CardPlace(lit: lit, gap: _gap),
            child: _TourCard(
              text: text,
              index: index,
              count: count,
              onBack: onBack,
              onNext: onNext,
              onSkip: onSkip,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.lit);

  final Rect? lit;

  static const Radius _corner = Radius.circular(16);

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = Path()..addRect(Offset.zero & size);
    final lit = this.lit;
    final dark = Paint()..color = AppColors.night.withValues(alpha: 0.74);
    if (lit == null) {
      canvas.drawPath(sheet, dark);
      return;
    }
    final hole = RRect.fromRectAndRadius(lit, _corner);
    canvas
      ..drawPath(Path.combine(PathOperation.difference, sheet, Path()..addRRect(hole)), dark)
      ..drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.ember,
      );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.lit != lit;
}

/// Puts the card beside the lit part — where there is room, in this order:
/// to its right, to its left, below, above — and in the middle of the screen
/// when nothing is lit or the lit part takes the whole page.
class _CardPlace extends SingleChildLayoutDelegate {
  const _CardPlace({required this.lit, required this.gap});

  final Rect? lit;
  final double gap;

  static const double _margin = 16;
  static const double _maxWidth = 400;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: (constraints.maxWidth - 2 * _margin).clamp(0, _maxWidth),
    maxHeight: (constraints.maxHeight - 2 * _margin).clamp(0, double.infinity),
  );

  @override
  Offset getPositionForChild(Size size, Size card) {
    final lit = this.lit;
    final centre = Offset((size.width - card.width) / 2, (size.height - card.height) / 2);
    if (lit == null) return centre;
    double within(double value, double extent, double room) =>
        value.clamp(_margin, (room - extent - _margin).clamp(_margin, double.infinity));
    final top = within(lit.center.dy - card.height / 2, card.height, size.height);
    final left = within(lit.center.dx - card.width / 2, card.width, size.width);
    if (size.width - lit.right >= card.width + gap + _margin) return Offset(lit.right + gap, top);
    if (lit.left >= card.width + gap + _margin) return Offset(lit.left - gap - card.width, top);
    if (size.height - lit.bottom >= card.height + gap + _margin) return Offset(left, lit.bottom + gap);
    if (lit.top >= card.height + gap + _margin) return Offset(left, lit.top - gap - card.height);
    return centre;
  }

  @override
  bool shouldRelayout(_CardPlace old) => old.lit != lit || old.gap != gap;
}

/// The Guide and what she says, with the tour's buttons.
class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.text,
    required this.index,
    required this.count,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final String text;
  final int index;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final last = index == count - 1;
    return Material(
      key: const Key('tour-card'),
      color: AppColors.surface,
      borderRadius: AppRadius.cardBorder,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: AppRadius.cardBorder, boxShadow: AppShadows.paper),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Avatar(
                      agent: 'front_desk',
                      mood: AvatarMood.smile,
                      wave: index == 0,
                      size: 76,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agentLabel(l, 'front_desk'),
                            style: theme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            text,
                            key: const Key('tour-text'),
                            style: theme.bodyLarge?.copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    if (!last)
                      TextButton(
                        key: const Key('tour-skip'),
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        ),
                        child: Text(l.tourSkip),
                      ),
                    // Wraps under itself when a label is long, instead of overflowing.
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          Text(
                            '${index + 1} / $count',
                            key: const Key('tour-progress'),
                            style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                          ),
                          if (onBack != null)
                            TextButton(
                              key: const Key('tour-back'),
                              onPressed: onBack,
                              child: Text(l.back),
                            ),
                          FilledButton(
                            key: const Key('tour-next'),
                            onPressed: onNext,
                            child: Text(last ? l.tourBegin : l.tourNext),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
