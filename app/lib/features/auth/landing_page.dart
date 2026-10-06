import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/life_tree.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'landing_robot.dart';

/// The front page: a robot holding your life tree in its palm. Scrolling, the
/// tree grows — a little sphere above the hand, then big beside four short
/// chapters about the system, then the whole screen — and the page ends on
/// one button.
///
/// The robot and the sphere stay put (the "stage"); the words scroll over
/// them. Below [_wide] the robot stands in the bottom half and the words sit
/// above it.
///
/// The page moves a whole screen at a time: one flick of the wheel, one swipe
/// or one arrow key turns to the next screen, and the robot acts out the turn.
///
/// On the web the robot is a three.js scene ([Robot3d], `web/landing3d/`): it
/// raises the orb while the camera rises to look down. Elsewhere, or when the
/// scene cannot run, a [LandingFilm] (frames of a video in
/// `assets/landing/frames/`) plays the same, the life tree riding on its orb;
/// without one it is the still picture `robot.png`.
class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.tree,
    required this.onSignIn,
    required this.onCreate,
  });

  /// What the sphere shows: a sample life tree.
  final LifeTree tree;
  final VoidCallback onSignIn;
  final VoidCallback onCreate;

  /// The robot picture and where its palm is, as fractions of it.
  static const String robotAsset = 'assets/landing/robot.png';
  static const double robotAspect = 1456 / 1088;
  static const Offset palm = Offset(0.30, 0.71);

  /// Screens of scrolling: the hero, four chapters, the end.
  static const int screens = 6;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();

  /// The screen the page is on or turning to.
  int _screen = 0;
  static const Duration _turn = Duration(milliseconds: 1100);
  DateTime _turnEnds = DateTime(0);
  DateTime _quietUntil = DateTime(0);
  double _wheel = 0;
  double _drag = 0;
  double? _height;

  /// The three.js robot: tried first where there is one, until it fails.
  bool _robot = hasRobot3d;
  bool _robotReady = false;

  /// Where the robot's orb is on screen (its centre and radius), as it says.
  final _orb = ValueNotifier<(Offset, double)?>(null);

  LandingFilm? _film;

  /// Whether the film's track has been looked for: until then the stage is
  /// bare paper, so the still robot never flashes before the film.
  bool _looked = false;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    if (!_robot) _loadFilm();
    FocusManager.instance.addListener(_refocus);
  }

  /// Takes the keys whenever nothing else has them (as when the sign-in card
  /// closes).
  final _keys = FocusNode(debugLabel: 'landing');
  void _refocus() {
    if (mounted && FocusManager.instance.primaryFocus is FocusScopeNode) _keys.requestFocus();
  }

  void _loadFilm() {
    unawaited(
      LandingFilm.load().then((film) {
        if (mounted) {
          setState(() {
            _film = film;
            _looked = true;
          });
        }
      }),
    );
  }

  /// Decodes every frame in the background, in order, so scrolling never waits.
  Future<void> _precache(LandingFilm film, bool wide) async {
    if (_precached) return;
    _precached = true;
    for (var i = 0; i < film.frames && mounted; i++) {
      await precacheImage(AssetImage(film.frame(i, wide: wide)), context);
    }
  }

  /// The pointer, as a fraction of the window (wide screens only): the robot
  /// and the sphere drift against each other a little.
  final _pointer = ValueNotifier(const Offset(0.5, 0.5));
  bool _menuOpen = false;

  @override
  void dispose() {
    _scroll.dispose();
    _pointer.dispose();
    _orb.dispose();
    FocusManager.instance.removeListener(_refocus);
    _keys.dispose();
    super.dispose();
  }

  static bool _wide(Size size) => size.width >= 1024;

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  void _goTo(int screen, double height) {
    final now = DateTime.now();
    setState(() {
      _menuOpen = false;
      _screen = screen;
    });
    _turnEnds = now.add(_turn);
    _quietUntil = _turnEnds.add(const Duration(milliseconds: 200));
    _wheel = 0;
    if (!_scroll.hasClients) return;
    unawaited(_scroll.animateTo(screen * height, duration: _turn, curve: Curves.easeInOutCubic));
  }

  /// To the next screen (+1) or the one before (-1).
  void _step(int direction, double height) {
    final next = (_screen + direction).clamp(0, LandingPage.screens - 1);
    if (next != _screen) _goTo(next, height);
  }

  /// A wheel or trackpad: the first push turns the page; the rest of that
  /// flick (a trackpad keeps sending for a while) is ignored.
  void _onWheel(double dy, double height) {
    final now = DateTime.now();
    if (now.isBefore(_turnEnds)) return;
    if (now.isBefore(_quietUntil)) {
      _quietUntil = now.add(const Duration(milliseconds: 150));
      return;
    }
    _wheel += dy;
    if (_wheel.abs() > 24) _step(_wheel.sign.toInt(), height);
  }

  /// The arrow, page and space keys turn screens.
  bool _onKey(KeyEvent event) {
    final height = _height;
    if (event is! KeyDownEvent || height == null) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _step(1, height);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      _step(-1, height);
    } else if (key == LogicalKeyboardKey.home) {
      _goTo(0, height);
    } else if (key == LogicalKeyboardKey.end) {
      _goTo(LandingPage.screens - 1, height);
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final wide = _wide(size);
        final l = context.l10n;
        // A resized window stays on its screen.
        if (_height != null && _height != size.height) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) _scroll.jumpTo(_screen * size.height);
          });
        }
        _height = size.height;
        final links = [
          (l.navHowItWorks, 1),
          (l.agentAuditor, 2),
          (l.lifeTree, 4),
        ];
        return Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: (_, event) => _onKey(event) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: MouseRegion(
            onHover: wide
                ? (e) => _pointer.value = Offset(
                    e.position.dx / size.width,
                    e.position.dy / size.height,
                  )
                : null,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: AppColors.surface)),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_scroll, _pointer]),
                    builder: (context, _) {
                      if (_robot) {
                        return _RobotStage(
                          tree: widget.tree,
                          size: size,
                          offset: _offset,
                          ready: _robotReady,
                          orb: _orb,
                          onReady: () => setState(() => _robotReady = true),
                          onFailed: () {
                            if (!mounted || !_robot) return;
                            setState(() => _robot = false);
                            _loadFilm();
                          },
                        );
                      }
                      final film = _film;
                      if (!_looked) return const SizedBox.shrink();
                      if (film == null) {
                        return _Stage(
                          tree: widget.tree,
                          size: size,
                          wide: wide,
                          offset: _offset,
                          pointer: _pointer.value,
                        );
                      }
                      unawaited(_precache(film, wide));
                      return _FilmStage(
                        film: film,
                        tree: widget.tree,
                        size: size,
                        wide: wide,
                        offset: _offset,
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    onVerticalDragStart: (_) => _drag = 0,
                    onVerticalDragUpdate: (d) => _drag += d.delta.dy,
                    onVerticalDragEnd: (d) {
                      final velocity = d.primaryVelocity ?? 0;
                      if (_drag < -40 || velocity < -300) {
                        _step(1, size.height);
                      } else if (_drag > 40 || velocity > 300) {
                        _step(-1, size.height);
                      }
                    },
                    child: Listener(
                      onPointerSignal: (e) {
                        if (e is PointerScrollEvent) _onWheel(e.scrollDelta.dy, size.height);
                      },
                      onPointerPanZoomUpdate: (e) => _onWheel(-e.panDelta.dy, size.height),
                      child: SingleChildScrollView(
                        key: const Key('landing-scroll'),
                        controller: _scroll,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _HeroScreen(
                              size: size,
                              wide: wide,
                              scroll: _scroll,
                              onCreate: widget.onCreate,
                              onSignIn: widget.onSignIn,
                            ),
                            for (final (i, chapter) in _chapters(l).indexed)
                              _ChapterScreen(
                                index: i + 1,
                                chapter: chapter,
                                size: size,
                                wide: wide,
                                scroll: _scroll,
                              ),
                            _EndScreen(
                              size: size,
                              wide: wide,
                              scroll: _scroll,
                              onCreate: widget.onCreate,
                              onSignIn: widget.onSignIn,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!wide)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_menuOpen,
                      child: AnimatedOpacity(
                        opacity: _menuOpen ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: _MobileMenu(
                          links: links,
                          onLink: (screen) => _goTo(screen, size.height),
                          onSignIn: () {
                            setState(() => _menuOpen = false);
                            widget.onSignIn();
                          },
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, _) => _Header(
                      wide: wide,
                      // Over the night at the end, the header turns light.
                      dark: !_menuOpen && _growth(_offset, size) > 0.92,
                      links: links,
                      onLink: (screen) => _goTo(screen, size.height),
                      onSignIn: widget.onSignIn,
                      menuOpen: _menuOpen,
                      onMenu: () => setState(() => _menuOpen = !_menuOpen),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One chapter: a kicker, a title, a paragraph.
typedef _Chapter = ({String kicker, String title, String body});

List<_Chapter> _chapters(AppLocalizations l) => [
  (kicker: l.chapterLearnKicker, title: l.chapterLearnTitle, body: l.chapterLearnBody),
  (kicker: l.chapterProveKicker, title: l.tourProveTitle, body: l.chapterProveBody),
  (kicker: l.chapterRememberKicker, title: l.tourLessonsTitle, body: l.chapterRememberBody),
  (kicker: l.chapterGrowKicker, title: l.chapterGrowTitle, body: l.chapterGrowBody),
];

/// How far the sphere has grown, 0–1: through the chapters to its big size
/// (0–0.75), then over the last screen to the whole window (0.75–1).
double _growth(double offset, Size size) {
  final h = size.height;
  final chapters = ((offset - 0.15 * h) / (3.85 * h)).clamp(0.0, 1.0);
  final end = ((offset - 4 * h) / h).clamp(0.0, 1.0);
  return 0.75 * Curves.easeInOutSine.transform(chapters) + 0.25 * Curves.easeInCubic.transform(end);
}

/// How visible a screen's words are at [offset]: 1 when the screen is in
/// place, fading over half a screen either side.
double _presence(double offset, double screen, double height) =>
    (1 - ((offset - screen * height).abs() / (0.55 * height))).clamp(0.0, 1.0);

// ---------------------------------------------------------------- the film

/// The front page's scroll film, made by `app/tool/landing_frames.py`: one
/// picture per scroll step, and where the orb is in each.
@immutable
class LandingFilm {
  const LandingFilm({required this.frames, required this.aspect, required this.orb});

  static const String folder = 'assets/landing/frames';

  final int frames;

  /// Width over height of a frame.
  final double aspect;

  /// The orb per frame: centre x as a fraction of the width, y and radius of
  /// the height; null where it was not found.
  final List<({double x, double y, double r})?> orb;

  /// The film, or null when there is none (no `track.json`). Read once per
  /// page, uncached: a cached future would outlive the test that made it.
  static Future<LandingFilm?> load([AssetBundle? bundle]) async {
    try {
      final json = jsonDecode(
        await (bundle ?? rootBundle).loadString('$folder/track.json', cache: false),
      ) as Map<String, dynamic>;
      return LandingFilm(
        frames: json['frames'] as int,
        aspect: (json['aspect'] as num).toDouble(),
        orb: [
          for (final p in json['orb'] as List<dynamic>)
            p == null
                ? null
                : (
                    x: ((p as List<dynamic>)[0] as num).toDouble(),
                    y: (p[1] as num).toDouble(),
                    r: (p[2] as num).toDouble(),
                  ),
        ],
      );
    } on Object {
      return null;
    }
  }

  String frame(int i, {required bool wide}) =>
      '$folder/${wide ? 'wide' : 'narrow'}_${i.clamp(0, frames - 1).toString().padLeft(3, '0')}.webp';

  /// The orb at fractional frame [f], between the nearest frames where it
  /// was found.
  ({double x, double y, double r})? orbAt(double f) {
    final i = f.floor().clamp(0, frames - 1);
    final j = (i + 1).clamp(0, frames - 1);
    final a = _nearest(i, -1) ?? _nearest(i, 1);
    final b = _nearest(j, 1) ?? a;
    if (a == null || b == null) return null;
    final t = (f - i).clamp(0.0, 1.0);
    double lerp(double p, double q) => p + (q - p) * t;
    return (x: lerp(a.x, b.x), y: lerp(a.y, b.y), r: lerp(a.r, b.r));
  }

  ({double x, double y, double r})? _nearest(int i, int step) {
    for (var k = i; k >= 0 && k < frames; k += step) {
      if (orb[k] != null) return orb[k];
    }
    return null;
  }
}

/// The film for the scroll [offset]: it plays through the hero and the
/// chapters, the tree riding on its orb; over the last screen the orb leaves
/// the film and fills the window.
class _FilmStage extends StatelessWidget {
  const _FilmStage({
    required this.film,
    required this.tree,
    required this.size,
    required this.wide,
    required this.offset,
  });

  final LandingFilm film;
  final LifeTree tree;
  final Size size;
  final bool wide;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final h = size.height;
    // The film, standing on the window's bottom edge: 90 % of a desktop
    // window's height (the head stays clear of the header), 62 % of a phone's.
    final filmH = wide ? math.max(w / film.aspect, h * 0.9) : h * 0.62;
    final filmW = filmH * film.aspect;
    final top = h - filmH;

    final played = (offset / (4.4 * h)).clamp(0.0, 1.0);
    final f = played * (film.frames - 1);
    final orb = film.orbAt(f);
    final away = Curves.easeInCubic.transform(((offset - 4.4 * h) / (0.6 * h)).clamp(0.0, 1.0));
    // Inside the orb's own glow, which stays around it as a halo.
    final r0 = orb == null ? 0.0 : orb.r * filmH * 0.9;

    // The film pans to follow the orb: on a desktop it stays right of the
    // words (kept to the film's right otherwise), on a phone it stays centred.
    // A desktop film may leave a strip of paper on the left, under the scrim.
    final orbX = (orb?.x ?? 0.5) * filmW;
    final wordsRight = 64 + math.min(460, w * 0.34);
    final want = wide ? math.max(w - filmW + orbX, wordsRight + r0 + 48) : w / 2;
    final left = (want - orbX).clamp(w - filmW, wide ? w * 0.2 : 0.0);

    final rEnd = math.sqrt(w * w + h * h) / 2 + 8;
    final from = orb == null ? size.center(Offset.zero) : Offset(left + orbX, top + orb.y * filmH);
    final center = Offset.lerp(from, size.center(Offset.zero), away)!;
    final radius = r0 <= 0 ? rEnd * away : r0 * math.pow(rEnd / r0, away);
    final filmFade = 1 - ((away - 0.2) / 0.6).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (filmFade > 0)
          Positioned(
            left: left,
            top: top,
            width: filmW,
            height: filmH,
            child: Opacity(
              opacity: filmFade,
              child: Semantics(
                label: context.l10n.robotAlt,
                image: true,
                child: Image.asset(
                  film.frame(f.round(), wide: wide),
                  key: const Key('landing-robot'),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        // The film's top edge melts into the paper.
        if (top > -filmH * 0.1)
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: filmH * (wide ? 0.08 : 0.18),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.surface.withValues(alpha: filmFade),
                      AppColors.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Paper behind the words on the left, so they read over the film.
        if (wide)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w * 0.55,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.surface.withValues(alpha: 0.92 * filmFade),
                      AppColors.surface.withValues(alpha: 0),
                    ],
                    stops: const [0.55, 1],
                  ),
                ),
              ),
            ),
          ),
        if (radius > 1)
          Positioned(
            left: center.dx - radius,
            top: center.dy - radius,
            width: radius * 2,
            height: radius * 2,
            // The orb's gold shows through until it leaves the film.
            child: _Sphere(
              tree: tree,
              radius: radius.toDouble(),
              full: away,
              night: 0.3 + 0.7 * away,
            ),
          ),
      ],
    );
  }
}

/// The three.js robot for the scroll [offset]; over the last turn the life
/// tree grows out of its orb until it fills the window.
class _RobotStage extends StatelessWidget {
  const _RobotStage({
    required this.tree,
    required this.size,
    required this.offset,
    required this.ready,
    required this.orb,
    required this.onReady,
    required this.onFailed,
  });

  final LifeTree tree;
  final Size size;
  final double offset;
  final bool ready;
  final ValueNotifier<(Offset, double)?> orb;
  final VoidCallback onReady;
  final VoidCallback onFailed;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final h = size.height;
    final away = Curves.easeInCubic.transform(((offset - 4 * h) / h).clamp(0.0, 1.0));
    final rEnd = math.sqrt(w * w + h * h) / 2 + 8;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: Robot3d(
            progress: offset / h,
            onOrb: (center, radius) => orb.value = (center, radius),
            onReady: onReady,
            onFailed: onFailed,
          ),
        ),
        if (ready && away > 0)
          ValueListenableBuilder(
            valueListenable: orb,
            builder: (context, at, _) {
              final (from, r0) = at ?? (size.center(Offset.zero), 0.0);
              final center = Offset.lerp(from, size.center(Offset.zero), away)!;
              final radius = r0 <= 1 ? rEnd * away : r0 * math.pow(rEnd / r0, away);
              return Stack(
                children: [
                  Positioned(
                    left: center.dx - radius,
                    top: center.dy - radius,
                    width: radius * 2,
                    height: radius * 2,
                    child: _Sphere(tree: tree, radius: radius.toDouble(), full: away, night: away),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- the stage

/// The robot and the sphere in its palm, drawn for the scroll [offset].
class _Stage extends StatelessWidget {
  const _Stage({
    required this.tree,
    required this.size,
    required this.wide,
    required this.offset,
    required this.pointer,
  });

  final LifeTree tree;
  final Size size;
  final bool wide;
  final double offset;
  final Offset pointer;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final h = size.height;
    final g = _growth(offset, size);

    // The robot: tall on a desktop, standing in the bottom half on a phone.
    final robotH = wide ? h * 0.92 : math.min(h * 0.5, w / LandingPage.robotAspect * 1.25);
    final robotW = robotH * LandingPage.robotAspect;
    final palmX = wide ? w * 0.60 : w * 0.42;
    final drift = wide ? (pointer.dx - 0.5) : 0.0;
    final robotLeft = palmX - LandingPage.palm.dx * robotW - drift * 10;
    final robotTop = h - robotH;
    final palm = Offset(
      robotLeft + LandingPage.palm.dx * robotW,
      robotTop + LandingPage.palm.dy * robotH,
    );

    // The sphere: a ball above the palm, a big globe beside the chapters, then the window.
    final r0 = robotH * (wide ? 0.055 : 0.07);
    final rMid = wide ? h * 0.3 : math.min(h * 0.2, w * 0.38);
    final rEnd = math.sqrt(w * w + h * h) / 2 + 8;
    final start = palm.translate(0, -r0 * 1.15);
    // Still resting on the palm, only bigger (and kept clear of the header).
    final mid = Offset(palmX, math.max(palm.dy - rMid * 1.02, rMid + 72));
    final center = g <= 0.75
        ? Offset.lerp(start, mid, g / 0.75)!
        : Offset.lerp(mid, size.center(Offset.zero), (g - 0.75) / 0.25)!;
    final radius = g <= 0.75
        ? r0 * math.pow(rMid / r0, g / 0.75)
        : rMid * math.pow(rEnd / rMid, (g - 0.75) / 0.25);
    final sphereDrift = drift * 8;

    // The robot steps back as the sphere leaves its hand for the whole window.
    final robotFade = 1 - ((g - 0.78) / 0.14).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (robotFade > 0)
          Positioned(
            left: robotLeft,
            top: robotTop,
            width: robotW,
            height: robotH,
            child: Opacity(
              opacity: robotFade,
              child: Semantics(
                label: context.l10n.robotAlt,
                image: true,
                child: Image.asset(
                  LandingPage.robotAsset,
                  key: const Key('landing-robot'),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        Positioned(
          left: center.dx - radius + sphereDrift,
          top: center.dy - radius,
          width: radius * 2,
          height: radius * 2,
          child: _Sphere(tree: tree, radius: radius.toDouble(), full: g),
        ),
      ],
    );
  }
}

/// The night globe with the life tree turning inside, and a warm glow that
/// fades as it fills the window.
class _Sphere extends StatelessWidget {
  const _Sphere({required this.tree, required this.radius, required this.full, this.night = 1});

  final LifeTree tree;
  final double radius;
  final double full;

  /// How opaque the night is, 0–1: below 1 the film's orb shows through.
  final double night;

  @override
  Widget build(BuildContext context) {
    final glow = (1 - full).clamp(0.0, 1.0);
    return DecoratedBox(
      key: const Key('landing-sphere'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.night.withValues(alpha: night.clamp(0.0, 1.0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.35 * glow),
            blurRadius: radius * 0.8,
            spreadRadius: radius * 0.05,
          ),
        ],
      ),
      child: ClipOval(
        child: OverflowBox(
          maxWidth: radius * 2.4,
          maxHeight: radius * 2.4,
          // A small ball shows the tree whole; a big one gets closer to it.
          child: SizedBox.square(
            dimension: radius * (radius < 120 ? 2.4 : 2.1),
            child: LifeConstellation(tree: tree, compact: true),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the screens

/// Screen 0: the headline typing itself, a line about the system, the buttons.
class _HeroScreen extends StatelessWidget {
  const _HeroScreen({
    required this.size,
    required this.wide,
    required this.scroll,
    required this.onCreate,
    required this.onSignIn,
  });

  final Size size;
  final bool wide;
  final ScrollController scroll;
  final VoidCallback onCreate;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final headline = (wide ? theme.displayLarge : theme.displaySmall)?.copyWith(height: 1.04);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Typewriter(text: l.heroHeadline, style: headline),
        SizedBox(height: wide ? AppSpacing.xl : AppSpacing.lg),
        _DropIn(
          delay: const Duration(milliseconds: 100),
          child: Text(
            l.heroLead,
            style: (wide ? theme.titleLarge : theme.bodyLarge)?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
        ),
        SizedBox(height: wide ? AppSpacing.xxl : AppSpacing.xl),
        _DropIn(
          delay: const Duration(milliseconds: 200),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CirclePill(key: const Key('hero-get-started'), label: l.getStarted, onTap: onCreate),
              TextButton(
                key: const Key('hero-have-account'),
                onPressed: onSignIn,
                child: Text(l.haveAnAccountButton),
              ),
            ],
          ),
        ),
      ],
    );
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        return Opacity(opacity: _presence(offset, 0, size.height), child: child);
      },
      child: SizedBox(
        height: size.height,
        width: size.width,
        child: Stack(
          children: [
            Positioned(
              left: wide ? 64 : AppSpacing.xl,
              right: wide ? null : AppSpacing.xl,
              top: wide ? 0 : 96,
              bottom: wide ? 0 : null,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? size.width * 0.42 : 560),
                  child: column,
                ),
              ),
            ),
            if (wide)
              Positioned(
                left: 64,
                bottom: AppSpacing.xxl,
                child: Row(
                  children: [
                    const Icon(Icons.south_rounded, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      l.scrollHint,
                      style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Screens 1–4: one chapter, beside the sphere (above it on a phone).
class _ChapterScreen extends StatelessWidget {
  const _ChapterScreen({
    required this.index,
    required this.chapter,
    required this.size,
    required this.wide,
    required this.scroll,
  });

  final int index;
  final _Chapter chapter;
  final Size size;
  final bool wide;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final text = Column(
      key: Key('landing-chapter-$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          chapter.kicker,
          style: theme.labelLarge?.copyWith(color: AppColors.textTertiary, letterSpacing: 0.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          chapter.title,
          style: (wide ? theme.displaySmall : theme.headlineLarge)?.copyWith(height: 1.1),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          chapter.body,
          style: (wide ? theme.titleMedium : theme.bodyLarge)?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
            height: 1.6,
          ),
        ),
      ],
    );
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        final p = _presence(offset, index.toDouble(), size.height);
        return Opacity(
          opacity: p,
          child: Transform.translate(offset: Offset(0, 24 * (1 - p)), child: child),
        );
      },
      child: SizedBox(
        height: size.height,
        width: size.width,
        child: Padding(
          padding: wide
              ? const EdgeInsets.only(left: 64)
              : const EdgeInsets.fromLTRB(AppSpacing.xl, 104, AppSpacing.xl, 0),
          child: Align(
            alignment: wide ? Alignment.centerLeft : Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? math.min(460, size.width * 0.34) : 560),
              child: text,
            ),
          ),
        ),
      ),
    );
  }
}

/// The last screen: the sphere has become the night; one line, one button.
class _EndScreen extends StatelessWidget {
  const _EndScreen({
    required this.size,
    required this.wide,
    required this.scroll,
    required this.onCreate,
    required this.onSignIn,
  });

  final Size size;
  final bool wide;
  final ScrollController scroll;
  final VoidCallback onCreate;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        final p = ((offset - 4.55 * size.height) / (0.45 * size.height)).clamp(0.0, 1.0);
        return Opacity(opacity: p, child: child);
      },
      child: SizedBox(
        key: const Key('landing-end'),
        height: size.height,
        width: size.width,
        child: DecoratedBox(
          // The tree's brightest star sits right behind the words: shade it.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.55,
              colors: [
                AppColors.night.withValues(alpha: 0.85),
                AppColors.night.withValues(alpha: 0),
              ],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.treeStartsWithYou,
                    textAlign: TextAlign.center,
                    style: (wide ? theme.displayMedium : theme.displaySmall)?.copyWith(
                      color: AppColors.nightText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _CirclePill(
                        key: const Key('landing-end-start'),
                        label: l.getStarted,
                        onTap: onCreate,
                        inverse: true,
                      ),
                      TextButton(
                        onPressed: onSignIn,
                        style: TextButton.styleFrom(foregroundColor: AppColors.nightText),
                        child: Text(l.haveAnAccountButton),
                      ),
                    ],
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

// ---------------------------------------------------------------- the header

/// Fixed at the top: the mark and the name, the chapter links in a line
/// ("How it works, The Auditor, Life tree"), the language and Sign in. On a
/// phone the links go behind a burger.
class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.dark,
    required this.links,
    required this.onLink,
    required this.onSignIn,
    required this.menuOpen,
    required this.onMenu,
  });

  final bool wide;
  final bool dark;
  final List<(String, int)> links;
  final ValueChanged<int> onLink;
  final VoidCallback onSignIn;
  final bool menuOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final ink = dark ? AppColors.nightText : AppColors.textPrimary;
    final linkStyle = theme.titleLarge?.copyWith(color: ink, fontWeight: FontWeight.w400);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? AppSpacing.xxl : AppSpacing.lg,
          vertical: wide ? AppSpacing.lg : AppSpacing.md,
        ),
        child: Row(
          children: [
            const _Spark(size: 20),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              // Loose: on a desktop it takes only its width, so the links can centre.
              flex: wide ? 0 : 1,
              child: Text(
                'Self-Infinity',
                key: const Key('hero-brand'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.headlineSmall?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const Spacer(),
            if (wide) ...[
              for (final (i, (label, screen)) in links.indexed) ...[
                if (i > 0)
                  Text(', ', style: linkStyle?.copyWith(color: ink.withValues(alpha: 0.4))),
                _HoverText(label: label, style: linkStyle, onTap: () => onLink(screen)),
              ],
              const Spacer(),
              _LanguageMenu(color: ink),
              const SizedBox(width: AppSpacing.lg),
              _HoverText(
                key: const Key('hero-sign-in'),
                label: context.l10n.signIn,
                style: linkStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: ink,
                ),
                onTap: onSignIn,
              ),
            ] else ...[
              _LanguageMenu(color: ink, compact: true),
              _Burger(open: menuOpen, color: ink, onTap: onMenu),
            ],
          ],
        ),
      ),
    );
  }
}

/// Text that dims on hover, like a link.
class _HoverText extends StatefulWidget {
  const _HoverText({super.key, required this.label, required this.style, required this.onTap});

  final String label;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  State<_HoverText> createState() => _HoverTextState();
}

class _HoverTextState extends State<_HoverText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _hover ? 0.6 : 1,
          duration: const Duration(milliseconds: 150),
          child: Text(widget.label, style: widget.style),
        ),
      ),
    ),
  );
}

/// Three bars that turn into an ×.
class _Burger extends StatelessWidget {
  const _Burger({required this.open, required this.color, required this.onTap});

  final bool open;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget bar({double turns = 0, double dy = 0, double opacity = 1}) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: 24,
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      transformAlignment: Alignment.center,
      transform: Matrix4.translationValues(0, dy, 0)..rotateZ(turns * math.pi * 2),
      color: color.withValues(alpha: opacity),
    );
    return IconButton(
      key: const Key('landing-menu'),
      tooltip: context.l10n.menu,
      onPressed: onTap,
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar(turns: open ? 0.125 : 0, dy: open ? 7 : 0),
          bar(opacity: open ? 0 : 1),
          bar(turns: open ? -0.125 : 0, dy: open ? -7 : 0),
        ],
      ),
    );
  }
}

/// The phone menu: the links, big, on frosted paper.
class _MobileMenu extends StatelessWidget {
  const _MobileMenu({required this.links, required this.onLink, required this.onSignIn});

  final List<(String, int)> links;
  final ValueChanged<int> onLink;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final style = theme.headlineMedium?.copyWith(fontWeight: FontWeight.w400);
    return ColoredBox(
      key: const Key('landing-mobile-menu'),
      color: AppColors.surface.withValues(alpha: 0.96),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 96, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, screen) in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _HoverText(label: label, style: style, onTap: () => onLink(screen)),
                ),
              const SizedBox(height: AppSpacing.lg),
              _HoverText(
                label: context.l10n.signIn,
                style: style?.copyWith(decoration: TextDecoration.underline),
                onTap: onSignIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The language of the page (and of the app after signing in): the current
/// one's name; a tap lists all three.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.color, this.compact = false});

  final Color color;

  /// Just the globe (a phone's header has no room for the name).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>();
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: color);
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
            Icon(Icons.language_rounded, size: compact ? 22 : 18, color: color),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(locale.language.nativeName, style: style),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- small parts

/// Types [text] out, a character every 38 ms after 0.6 s, with a blinking
/// cursor until it is done. Instant when motion is off.
class _Typewriter extends StatefulWidget {
  const _Typewriter({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Typewriter> createState() => _TypewriterState();
}

class _TypewriterState extends State<_Typewriter> {
  static const Duration _speed = Duration(milliseconds: 38);
  static const Duration _startDelay = Duration(milliseconds: 600);

  int _shown = 0;
  bool _cursorOn = true;
  Timer? _typing;
  Timer? _blink;

  bool get _done => _shown >= widget.text.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_typing != null || _done) return;
    if (!Avatar.animationsEnabled || MediaQuery.of(context).disableAnimations) {
      _shown = widget.text.length;
      return;
    }
    _blink = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() => _cursorOn = !_cursorOn),
    );
    _typing = Timer(_startDelay, () {
      _typing = Timer.periodic(_speed, (t) {
        setState(() => _shown++);
        if (_done) {
          t.cancel();
          _blink?.cancel();
        }
      });
    });
  }

  @override
  void didUpdateWidget(_Typewriter old) {
    super.didUpdateWidget(old);
    // Another language: show it whole, no retyping.
    if (old.text != widget.text) {
      _typing?.cancel();
      _blink?.cancel();
      _shown = widget.text.length;
    }
  }

  @override
  void dispose() {
    _typing?.cancel();
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _shown.clamp(0, widget.text.length));
    final fontSize = widget.style?.fontSize ?? 48;
    return Semantics(
      label: widget.text,
      header: true,
      child: ExcludeSemantics(
        child: Text.rich(
          key: const Key('hero-headline'),
          TextSpan(
            text: shown,
            children: [
              if (!_done)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Opacity(
                    opacity: _cursorOn ? 1 : 0,
                    child: Container(
                      width: 2,
                      height: fontSize * 1.05,
                      margin: const EdgeInsets.only(left: 2),
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          style: widget.style,
        ),
      ),
    );
  }
}

/// Fades in and drops 20 px into place after [delay] (0.6 s).
class _DropIn extends StatefulWidget {
  const _DropIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_DropIn> createState() => _DropInState();
}

class _DropInState extends State<_DropIn> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (!Avatar.animationsEnabled) {
      _t.value = 1;
    } else {
      _wait = Timer(widget.delay, () => unawaited(_t.forward()));
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = Curves.easeOutCubic.transform(_t.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child),
      );
    },
  );
}

/// An ink circle with an arrow, then [label]. Hovered, the arrow morphs into
/// "sign in" (an arrow going through a door).
class _CirclePill extends StatefulWidget {
  const _CirclePill({super.key, required this.label, required this.onTap, this.inverse = false});

  final String label;
  final VoidCallback onTap;

  /// Paper on ink instead of ink on paper (on the night).
  final bool inverse;

  @override
  State<_CirclePill> createState() => _CirclePillState();
}

class _CirclePillState extends State<_CirclePill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final fill = widget.inverse ? AppColors.onAccent : AppColors.primary;
    final ink = widget.inverse ? AppColors.primary : AppColors.onAccent;
    return Semantics(
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: fill,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, AppSpacing.xl, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: MorphIcon(
                      from: MorphShapes.arrow,
                      to: MorphShapes.signIn,
                      morphed: _hover,
                      size: 18,
                      strokeWidth: 2.2,
                      color: fill,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(widget.label, style: theme.labelLarge?.copyWith(color: ink)),
                ],
              ),
            ),
          ),
        ),
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
      CustomPaint(size: Size.square(size), painter: const _SparkPainter());
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter();

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
    canvas.drawPath(path, Paint()..color = AppColors.ember);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => false;
}
