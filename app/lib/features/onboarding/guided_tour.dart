import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/fake_api.dart';
import '../../app/app_state.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../auth/auth_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../voice/voice_service.dart';
import '../../widgets/widgets.dart';

/// What the user does at a stop of the [GuidedTour].
enum TourAct {
  /// Only looks; the card's button goes on.
  look,

  /// Taps the lit part, for real.
  tap,

  /// Types into the lit input bar and sends, for real.
  type,
}

/// What a [TourStop] can see and do on the page under the tour.
abstract interface class TourHands {
  AppLocalizations get l;

  /// Whether a widget with [key] is on the page.
  bool has(Key key);

  /// The text of the `Text` with [key], if it is on the page.
  String? textOf(Key key);

  /// The path of the page shown (`/skill/3/audit`).
  String get path;

  /// Presses the first button at or under [key]; false when there is none.
  bool press(Key key);

  /// Puts [text] into the page's input bar and sends it; false without one.
  bool send(String text);

  void go(String location);

  /// Opens the first node of the example course that can be taken on.
  void openFirstNode();

  /// A note a stop keeps for itself while it is shown.
  Object? memo;
}

/// One stop of the [GuidedTour]: the part of the page that stays lit, what
/// the Guide says about it, and what the user does there.
@immutable
class TourStop {
  const TourStop({
    this.route,
    this.anchor,
    this.frame,
    required this.text,
    this.act = TourAct.look,
    this.done,
    this.auto,
    this.leave,
  });

  /// The page to go to; null stays where the stop before (or the user's own
  /// tap) left the app.
  final String? route;

  /// The widget that stays lit (found by its key); null darkens everything
  /// and puts the Guide in the middle.
  final Key? anchor;

  /// Lights the nearest widget of this type around the [anchor] instead of the
  /// anchor alone (the whole input bar, not just its text field); the anchor
  /// itself when there is none.
  final Type? frame;
  final String Function(AppLocalizations l) text;

  /// [TourAct.tap] and [TourAct.type]: the lit part takes the user's taps and
  /// keys, and the tour goes on by itself once [done] holds.
  final TourAct act;
  final bool Function(TourHands h)? done;

  /// What the card's own button does at a tap / type stop: the same thing,
  /// done for the user.
  final void Function(TourHands h)? auto;

  /// Done on the way to the next stop (closing a card the stop showed).
  final void Function(TourHands h)? leave;
}

/// The guided tour (`docs/ux-chat.md` §7): the real scenes over an example
/// world, everything veiled but the part the Guide is talking about — and
/// that part works. The user does the loop of the app once, by hand: says
/// what to learn and gets a course built, opens the tree, taps a next node,
/// takes it on, explains it to the Auditor in two answers, sees the
/// celebration and the verdict, and the tree with its first light.
///
/// The world is a [FakeApiClient] of its own in demo mode: rule-based, in
/// the app's language, nothing reaches the server or the account. A new
/// account sees the tour before the setup; the front page opens it without
/// an account ([guest]).
class GuidedTour extends StatefulWidget {
  const GuidedTour({
    super.key,
    required this.theme,
    required this.locale,
    required this.onDone,
    this.guest = false,
    this.voice,
  });

  final ThemeData theme;
  final Locale locale;

  /// The tour was finished or skipped.
  final VoidCallback onDone;

  /// Opened from the front page, without an account: it ends at `Create my
  /// account` instead of the setup.
  final bool guest;

  /// The microphone of the tour's input bars; the app's own when null.
  final VoiceService? voice;

  /// How long the example world takes to answer, so that her thinking shows.
  /// Tests set it to zero.
  static Duration latency = const Duration(milliseconds: 450);

  static final RegExp _nodePath = RegExp(r'^/skill/\d+$');
  static final RegExp _auditPath = RegExp(r'^/skill/(\d+)/audit$');

  static const Key _input = Key('stage-input');
  static const Key _openTree = Key('action-map');
  static const Key _picks = Key('orb-picks');
  static const Key _takeOn = Key('start-audit');
  static const Key _asked = Key('audit-bubble-text');
  static const Key _celebration = Key('celebration-card');

  /// She said something new since the stop began.
  static bool _answered(TourHands h) {
    final now = h.textOf(_asked);
    h.memo ??= now;
    return now != null && h.memo != null && now != h.memo;
  }

  /// The stops, in order.
  static List<TourStop> stops() => [
    TourStop(
      route: AppRoutes.home,
      anchor: _input,
      frame: Composer,
      text: (l) => l.tourAsk,
      act: TourAct.type,
      done: (h) => h.has(_openTree),
      auto: (h) => h.send(h.l.heroExample1),
    ),
    TourStop(
      anchor: _openTree,
      text: (l) => l.tourBuilt,
      act: TourAct.tap,
      done: (h) => !h.has(_openTree) && h.has(const Key('life-board')),
      auto: (h) => h.press(_openTree),
    ),
    TourStop(
      anchor: _picks,
      text: (l) => l.tourPicks,
      act: TourAct.tap,
      done: (h) => _nodePath.hasMatch(h.path),
      auto: (h) {
        if (!h.press(_picks)) h.openFirstNode();
      },
    ),
    TourStop(
      anchor: _takeOn,
      text: (l) => l.tourTakeItOn,
      act: TourAct.tap,
      done: (h) => _auditPath.hasMatch(h.path),
      auto: (h) {
        if (!h.press(_takeOn) && _nodePath.hasMatch(h.path)) h.go('${h.path}/audit');
      },
    ),
    TourStop(
      anchor: _input,
      frame: Composer,
      text: (l) => l.tourExplain,
      act: TourAct.type,
      done: _answered,
      auto: (h) => h.send(h.l.tourSampleAnswer),
    ),
    TourStop(
      anchor: _input,
      frame: Composer,
      text: (l) => l.tourExplainAgain,
      act: TourAct.type,
      done: (h) => h.has(_celebration),
      auto: (h) => h.send(h.l.tourSampleAnswer),
    ),
    TourStop(
      anchor: _celebration,
      text: (l) => l.tourCleared,
      leave: (h) => h.press(const Key('celebration-close')),
    ),
    TourStop(anchor: const Key('audit-verdict'), text: (l) => l.tourVerdict),
    TourStop(route: AppRoutes.home, anchor: const Key('night-panel'), text: (l) => l.tourTree),
  ];

  @override
  State<GuidedTour> createState() => _GuidedTourState();
}

class _GuidedTourState extends State<GuidedTour> implements TourHands {
  late final FakeApiClient _world = FakeApiClient(
    latency: GuidedTour.latency,
    language: widget.locale.languageCode,
    demo: true,
  );
  final AppState _appState = AppState();
  final GlobalKey _scenes = GlobalKey();
  final GlobalKey _overlay = GlobalKey();
  final List<TourStop> _stops = GuidedTour.stops();
  late final GoRouter _router = createRouter(initialLocation: _stops.first.route);

  int _index = 0;

  /// The lit part, in the overlay's coordinates; null while it is looked for
  /// or when the stop has none.
  Rect? _lit;

  /// The card's button did this stop's part for the user; how many looks ago.
  int? _autoLooks;
  Timer? _watch;

  @override
  Object? memo;

  static const Duration _watchEvery = Duration(milliseconds: 120);

  /// After this many looks a part done for the user counts as not working
  /// here, and the tour goes on anyway.
  static const int _patience = 25;

  @override
  void initState() {
    super.initState();
    _watch = Timer.periodic(_watchEvery, (_) => _look());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _router.dispose();
    super.dispose();
  }

  TourStop get _stop => _stops[_index];

  // -- what a stop sees and does ---------------------------------------------

  @override
  AppLocalizations get l => lookupAppLocalizations(widget.locale);

  @override
  bool has(Key key) => _find(key) != null;

  @override
  String? textOf(Key key) {
    final widget = _find(key)?.widget;
    return widget is Text ? widget.data : null;
  }

  @override
  String get path => _router.routerDelegate.currentConfiguration.uri.path;

  @override
  bool press(Key key) {
    final root = _find(key);
    if (root == null) return false;
    VoidCallback? tap;
    void visit(Element element) {
      if (tap != null) return;
      final widget = element.widget;
      tap = switch (widget) {
        ButtonStyleButton() => widget.onPressed,
        InkResponse() => widget.onTap,
        GestureDetector() => widget.onTap,
        _ => null,
      };
      if (tap == null) element.visitChildElements(visit);
    }

    visit(root);
    tap?.call();
    return tap != null;
  }

  @override
  bool send(String text) {
    final bar = _around(_find(GuidedTour._input), Composer)?.widget;
    if (bar is! Composer || bar.onSend == null) return false;
    bar.controller.text = text;
    bar.onSend!();
    return true;
  }

  @override
  void go(String location) => _router.go(location);

  @override
  void openFirstNode() => unawaited(_openFirstNode());

  Future<void> _openFirstNode() async {
    try {
      final course = (await _world.listCourses()).firstOrNull;
      if (course == null) return;
      final map = await _world.getCourseMap(course.id);
      final open = map.nodes.where((n) => n.isAvailable && !n.unexpanded).firstOrNull;
      if (open != null && mounted) _router.go(AppRoutes.skill(open.id));
    } on Object {
      // The tour goes on without it.
    }
  }

  // -- the stops -------------------------------------------------------------

  void _go(int index) {
    if (index >= _stops.length) {
      widget.onDone();
      return;
    }
    if (index > _index) _stop.leave?.call(this);
    setState(() {
      _index = index;
      _lit = null;
      _autoLooks = null;
      memo = null;
    });
    final route = _stops[index].route;
    if (route != null && path != route) _router.go(route);
  }

  /// The card's button: on, or this stop's part done for the user.
  void _next() {
    final auto = _stop.auto;
    if (_stop.act == TourAct.look || auto == null) {
      _go(_index + 1);
      return;
    }
    setState(() => _autoLooks = 0);
    auto(this);
  }

  /// Goes on when the stop's part was done, and finds its lit part on the
  /// page and follows it (the page loads, scrolls and resizes under the tour).
  void _look() {
    if (!mounted) return;
    final stop = _stop;
    if (stop.done?.call(this) ?? false) {
      _go(_index + 1);
      return;
    }
    if (_autoLooks case final looks?) {
      if (looks >= _patience) {
        _go(_index + 1);
        return;
      }
      _autoLooks = looks + 1;
    }
    final anchor = stop.anchor;
    if (anchor == null) return;
    final found = _find(anchor);
    final overlay = _overlay.currentContext?.findRenderObject();
    final box = (_around(found, stop.frame) ?? found)?.findRenderObject();
    if (found == null || box is! RenderBox || !box.hasSize || overlay is! RenderBox) {
      // Gone from the page (her answer is on its way): nothing is lit until it is back.
      if (_lit != null) setState(() => _lit = null);
      return;
    }
    if (_lit == null) {
      // Bring it into view once, and put the cursor in a box to type in.
      unawaited(Scrollable.ensureVisible(found, alignment: 0.5, duration: Duration.zero));
      final field = found.widget;
      if (stop.act == TourAct.type && field is TextField) field.focusNode?.requestFocus();
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final lit = rect.intersect(Offset.zero & overlay.size);
    if (lit.width <= 0 || lit.height <= 0) return;
    if (_lit == null || (lit.topLeft - _lit!.topLeft).distance > 0.5 || lit.size != _lit!.size) {
      setState(() => _lit = lit);
    }
  }

  /// The nearest widget of [type] around [found], if any.
  Element? _around(Element? found, Type? type) {
    if (found == null || type == null) return null;
    Element? frame;
    found.visitAncestorElements((element) {
      if (element.widget.runtimeType != type) return true;
      frame = element;
      return false;
    });
    return frame;
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
    final stop = _stop;
    final lit = stop.anchor == null ? null : _lit;
    final hands = stop.act != TourAct.look && lit != null;
    // The example world's own controllers; the device (files, account) is the app's.
    return AppProviders(
      api: _world,
      appState: _appState,
      voice: widget.voice ?? context.read<VoiceService>(),
      filePicker: context.read<FilePickerService>(),
      auth: context.read<AuthService>(),
      child: MaterialApp.router(
        title: 'Self-Infinity',
        debugShowCheckedModeBanner: false,
        theme: widget.theme,
        locale: widget.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
        builder: (context, child) => Stack(
          key: const Key('guided-tour'),
          children: [
            // Only the lit part of a tap / type stop takes input (the overlay
            // lets it through there); everything else is looked at.
            IgnorePointer(
              ignoring: !hands,
              child: KeyedSubtree(key: _scenes, child: child ?? const SizedBox.shrink()),
            ),
            Positioned.fill(
              child: _TourOverlay(
                key: _overlay,
                lit: lit,
                act: lit == null ? TourAct.look : stop.act,
                canAuto: stop.act != TourAct.look,
                busy: _autoLooks != null,
                guest: widget.guest,
                // Not on the life tree (home): the tree is the picture there.
                showGuide: path != AppRoutes.home,
                text: stop.text(context.l10n),
                index: _index,
                count: _stops.length,
                onNext: _next,
                onSkip: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The veil over the page with one part left lit, and the Guide's card next
/// to it.
class _TourOverlay extends StatelessWidget {
  const _TourOverlay({
    super.key,
    required this.lit,
    required this.act,
    required this.canAuto,
    required this.busy,
    required this.guest,
    required this.showGuide,
    required this.text,
    required this.index,
    required this.count,
    required this.onNext,
    required this.onSkip,
  });

  final Rect? lit;

  /// Whether the card shows her picture beside the text.
  final bool showGuide;

  /// What the user does with [lit]; [TourAct.look] when nothing is lit.
  final TourAct act;

  /// The stop is one the user does: the card's button does it for them.
  final bool canAuto;

  /// That button was pressed and its part is under way.
  final bool busy;
  final bool guest;
  final String text;
  final int index;
  final int count;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// How far the frame stands off the lit part: just its line, so the
  /// part's own shadow stays under the veil and nothing inside the frame
  /// looks shaded. The gap is between the frame and the card.
  static const double _halo = 1;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final lit = this.lit?.inflate(_halo);
    return Stack(
      children: [
        // Takes every tap that is not on the card — except, at a tap / type
        // stop, the ones on the lit part: those reach the page.
        Positioned.fill(
          child: _Gate(
            hole: act == TourAct.look ? null : lit,
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
              act: act,
              canAuto: canAuto,
              busy: busy,
              guest: guest,
              showGuide: showGuide,
              text: text,
              index: index,
              count: count,
              onNext: onNext,
              onSkip: onSkip,
            ),
          ),
        ),
      ],
    );
  }
}

/// Absorbs every pointer on it but those inside [hole].
class _Gate extends SingleChildRenderObjectWidget {
  const _Gate({required this.hole, super.child});

  final Rect? hole;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGate(hole);

  @override
  void updateRenderObject(BuildContext context, _RenderGate renderObject) =>
      renderObject.hole = hole;
}

class _RenderGate extends RenderProxyBox {
  _RenderGate(this.hole);

  Rect? hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position) || (hole?.contains(position) ?? false)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// The veil: a fog over the whole page, light or dark, so that the lit part
/// is the only place in its true colours (a dark sheet would leave the night
/// panel looking shaded inside its frame too).
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.lit);

  final Rect? lit;

  static const Radius _corner = Radius.circular(16);

  @override
  void paint(Canvas canvas, Size size) {
    final lit = this.lit;
    final fog = Paint()..color = AppColors.nightLine.withValues(alpha: 0.82);
    if (lit == null) {
      canvas.drawRect(Offset.zero & size, fog);
      return;
    }
    final hole = RRect.fromRectAndRadius(lit, _corner);
    // Even-odd, not Path.combine: in the browser the combined path came out
    // as the whole sheet, and the lit part stayed under the veil.
    final sheet = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas
      ..drawPath(sheet, fog)
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
/// to its right, to its left, below, above — in the middle of the screen when
/// nothing is lit, and at the top or bottom edge when the lit part leaves no
/// room beside it.
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
    // No room beside it: at the edge of the screen farther from its middle.
    final below = lit.center.dy < size.height / 2;
    return Offset(centre.dx, below ? size.height - card.height - _margin : _margin);
  }

  @override
  bool shouldRelayout(_CardPlace old) => old.lit != lit || old.gap != gap;
}

/// The Guide and what she says, with the tour's buttons.
class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.act,
    required this.canAuto,
    required this.busy,
    required this.guest,
    required this.showGuide,
    required this.text,
    required this.index,
    required this.count,
    required this.onNext,
    required this.onSkip,
  });

  /// The lit part is to be tapped or typed into: the card says so.
  final TourAct act;

  /// The card's button does the stop's part for the user (a quiet button).
  final bool canAuto;
  final bool busy;
  final bool guest;

  /// Her picture beside the text; off on the life tree.
  final bool showGuide;
  final String text;
  final int index;
  final int count;
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
                    if (showGuide) ...[
                      Avatar(
                        agent: 'front_desk',
                        mood: AvatarMood.smile,
                        wave: index == 0,
                        size: 76,
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
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
                            keepAll(text),
                            key: const Key('tour-text'),
                            style: theme.bodyLarge?.copyWith(height: 1.45),
                          ),
                          if (act != TourAct.look) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              key: const Key('tour-try-hint'),
                              children: [
                                Icon(
                                  act == TourAct.type
                                      ? Icons.keyboard_alt_outlined
                                      : Icons.touch_app_outlined,
                                  size: 16,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text(
                                    act == TourAct.type ? l.tourTypeHint : l.tourTryHint,
                                    style: theme.labelMedium?.copyWith(color: AppColors.success),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                          if (canAuto)
                            TextButton(
                              key: const Key('tour-next'),
                              onPressed: busy ? null : onNext,
                              child: Text(act == TourAct.type ? l.tourDoForMe : l.tourNext),
                            )
                          else
                            FilledButton(
                              key: const Key('tour-next'),
                              onPressed: onNext,
                              child: Text(
                                !last
                                    ? l.tourNext
                                    : guest
                                    ? l.tourGuestBegin
                                    : l.tourBegin,
                              ),
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
