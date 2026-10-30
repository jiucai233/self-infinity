import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tokens.dart';
import 'avatar.dart';
import '../l10n/l10n.dart';

/// Scene 1: 大肥鱼 and her crystal ball (`docs/ux-chat.md` Scene 1,
/// `docs/DESIGN.md` §4).
///
/// The ball floats beside her at chest height ([Avatar.orbHandAt]), clear of
/// her hands, and bobs on the period of her idle loop ([Avatar.idleLoop]).
/// The two play together:
/// * **Hover** — the ball glows brighter and she turns to look at it
///   ([AvatarReaction.lookAside]).
/// * **Tap** — she is surprised for [reactFor], the ball pulses, then
///   [onOrbTap] runs (at once when motion is off).
/// * **Speaking** — while [state] is [AvatarState.speaking] the glow breathes
///   with her voice.
///
/// The ball is drawn in layers, back to front:
/// 1. **Glow** — a soft gold halo; hover, speech and a tap brighten it.
/// 2. **Glass body** — a smoky radial gradient, lit from the top left.
/// 3. **Mist** — three soft blobs drifting on slow, out-of-phase loops
///    (references: React Bits "Orb", react-ai-orb).
/// 4. **[orb]** — the content (the course constellation, or a `?`).
/// 5. **Glass highlights** — a fixed specular ellipse, a faint rim shadow,
///    and a light sweep that crosses the ball every 7 s.
/// 6. **Sparkles** around the ball twinkle on their own phases
///    (reference: Aceternity "Sparkles").
///
/// Motion is off when [Avatar.animationsEnabled] is false or the platform
/// asks for reduced motion. Only the ball repaints per frame (it sits behind
/// its own [RepaintBoundary]); she repaints when her frame changes.
class OrbAvatar extends StatefulWidget {
  const OrbAvatar({
    super.key,
    required this.agent,
    required this.orb,
    this.onOrbTap,
    this.mood = AvatarMood.smile,
    this.state = AvatarState.idle,
    this.size = 220,
  });

  final String agent;

  /// Built with the hover state, so the content can react too.
  final Widget orb;
  final VoidCallback? onOrbTap;
  final AvatarMood mood;
  final AvatarState state;

  /// Height of the figure.
  final double size;

  /// How long she reacts to a tap before [onOrbTap] runs.
  static const Duration reactFor = Duration(milliseconds: 600);

  /// Whether the pointer is over a ball below [context] (read by the content).
  static bool hoveredOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OrbHover>()?.hovered ?? false;

  @override
  State<OrbAvatar> createState() => _OrbAvatarState();
}

class _OrbAvatarState extends State<OrbAvatar> with SingleTickerProviderStateMixin {
  final _clock = _GlassClock();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  bool _hover = false;
  bool _down = false;

  /// Her reaction to the ball, if any.
  AvatarReaction? _reaction;

  /// Runs out [OrbAvatar.reactFor] after a tap.
  Timer? _tapped;

  bool get _still => !Avatar.animationsEnabled || MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _clock.period = Avatar.idleLoop.inMicroseconds / 1e6;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still) {
      _ticker?.stop();
      _settle();
    } else {
      _ticker ??= createTicker((elapsed) {
        final dt = (elapsed - _last).inMicroseconds / 1e6;
        _last = elapsed;
        _clock.advance(dt, hover: _hover, speaking: widget.state == AvatarState.speaking);
      });
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  @override
  void didUpdateWidget(OrbAvatar old) {
    super.didUpdateWidget(old);
    if (_still && old.state != widget.state) _settle();
  }

  void _settle() =>
      _clock.settle(hover: _hover, speaking: widget.state == AvatarState.speaking);

  void _setHover(bool hover) {
    setState(() {
      _hover = hover;
      if (!hover) _down = false;
      if (_reaction != AvatarReaction.surprised) {
        _reaction = hover ? AvatarReaction.lookAside : null;
      }
    });
    if (_still) _settle();
  }

  void _onTap() {
    if (_tapped?.isActive ?? false) return; // one tap, one trip
    final go = widget.onOrbTap;
    final still = _still;
    setState(() => _reaction = AvatarReaction.surprised);
    _clock.pulse();
    _tapped = Timer(OrbAvatar.reactFor, () {
      if (!mounted) return;
      setState(() => _reaction = _hover ? AvatarReaction.lookAside : null);
      if (!still) go?.call();
    });
    if (still) go?.call();
  }

  @override
  void dispose() {
    _tapped?.cancel();
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final agent = widget.agent;
    final k = Avatar.unit(agent, size);
    final figureWidth = size * Avatar.aspect;
    // Room for her hair on the left; the ball and its sparkles on the right.
    final left = 8 * k;
    final center = Offset(left, 0) + Avatar.orbHandAt(agent, size);
    final d = 52 * k; // ball diameter
    final halo = d + 36 * k;
    final width = center.dx + halo / 2;
    final scale = _down ? 0.97 : (_hover ? 1.04 : 1.0);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            top: 0,
            width: figureWidth,
            height: size,
            child: Avatar(
              agent: agent,
              mood: widget.mood,
              state: widget.state,
              reaction: _reaction,
              size: size,
            ),
          ),
          Positioned(
            left: center.dx - halo / 2,
            top: center.dy - halo / 2,
            width: halo,
            height: halo,
            child: RepaintBoundary(
              child: _Bob(
                clock: _clock,
                amplitude: 3 * k,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _GlowPainter(_clock),
                          foregroundPainter: _SparklePainter(_clock, k),
                        ),
                      ),
                    ),
                    Center(
                      child: SizedBox.square(
                        dimension: d,
                        child: _ball(context, d, scale),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ball(BuildContext context, double d, double scale) {
    final k = Avatar.unit(widget.agent, widget.size);
    return Semantics(
      button: widget.onOrbTap != null,
      label: context.l10n.crystalBall,
      child: MouseRegion(
        cursor: widget.onOrbTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          key: const Key('crystal-ball'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: _onTap,
          child: AnimatedScale(
            scale: scale,
            duration: _still ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: _OrbHover(
              hovered: _hover,
              child: CustomPaint(
                painter: _GlassBackPainter(_clock),
                foregroundPainter: _GlassFrontPainter(_clock, k),
                child: ClipOval(
                  child: Padding(
                    padding: EdgeInsets.all(d * 0.07),
                    child: RepaintBoundary(child: widget.orb),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floats [child] up and down with the clock, and swells it while a tap's
/// pulse runs.
class _Bob extends StatelessWidget {
  const _Bob({required this.clock, required this.amplitude, required this.child});

  final _GlassClock clock;
  final double amplitude;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: clock,
      child: child,
      builder: (context, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.translationValues(0, -amplitude * clock.bob, 0)
          ..scaleByDouble(1 + 0.08 * clock.swell, 1 + 0.08 * clock.swell, 1, 1),
        child: child,
      ),
    );
  }
}

class _OrbHover extends InheritedWidget {
  const _OrbHover({required this.hovered, required super.child});

  final bool hovered;

  @override
  bool updateShouldNotify(_OrbHover old) => old.hovered != hovered;
}

/// Time, hover energy, speech and the tap pulse, shared by the painters.
class _GlassClock extends ChangeNotifier {
  double t = 0;
  double energy = 0;
  bool still = false;

  /// Seconds of one bob (her idle loop).
  double period = 3;

  /// 0..1: how much her speech brightens the glow now.
  double voice = 0;

  /// Seconds left of a tap's pulse.
  double _pulseLeft = 0;
  static const double _pulseTime = 0.6;

  /// -1..1: the ball's height in its bob.
  double get bob => still ? 0 : math.sin(2 * math.pi * t / period);

  /// 0..1..0 over a tap's pulse.
  double get swell =>
      _pulseLeft <= 0 ? 0 : math.sin(math.pi * (1 - _pulseLeft / _pulseTime));

  /// 0..1: how bright the glow is.
  double get glow => (0.25 + 0.45 * energy + 0.3 * voice + 0.6 * swell).clamp(0.0, 1.0);

  void advance(double dt, {required bool hover, required bool speaking}) {
    still = false;
    t += dt;
    energy += ((hover ? 1.0 : 0.0) - energy) * math.min(1, dt * 5);
    // A gentle breath, about one a second, while she speaks.
    final target = speaking ? 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.1) : 0.0;
    voice += (target - voice) * math.min(1, dt * 6);
    if (_pulseLeft > 0) _pulseLeft = math.max(0, _pulseLeft - dt);
    notifyListeners();
  }

  void settle({required bool hover, required bool speaking}) {
    still = true;
    t = 2.2;
    energy = hover ? 1 : 0;
    voice = speaking ? 0.5 : 0;
    notifyListeners();
  }

  /// Starts a tap's pulse (shown only while moving).
  void pulse() {
    if (still) return;
    _pulseLeft = _pulseTime;
  }
}

/// The soft gold halo behind the ball.
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.clock) : super(repaint: clock);

  final _GlassClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = clock.glow;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.magic[2].withValues(alpha: 0.55 * glow),
            AppColors.magic[1].withValues(alpha: 0.22 * glow),
            AppColors.magic[1].withValues(alpha: 0),
          ],
          stops: const [0.45, 0.72, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.clock != clock;
}

/// Glass body + drifting mist (behind the content).
class _GlassBackPainter extends CustomPainter {
  _GlassBackPainter(this.clock) : super(repaint: clock);

  final _GlassClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final ball = Rect.fromCircle(center: c, radius: r);
    canvas
      ..save()
      ..clipPath(Path()..addOval(ball));

    canvas.drawRect(
      ball,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: AppColors.glass,
          stops: [0, 0.6, 1],
        ).createShader(ball),
    );

    // Mist: three blobs on slow Lissajous loops.
    final t = clock.t;
    final boost = 1 + 0.7 * clock.energy;
    final blobs = [
      (AppColors.magic[0], 0.20, 0.62, Offset(math.cos(t * 0.31), math.sin(t * 0.23))),
      (AppColors.magic[1], 0.17, 0.55, Offset(math.cos(t * 0.19 + 2.1), math.sin(t * 0.27 + 1.3))),
      (AppColors.magic[2], 0.10, 0.45, Offset(math.cos(t * 0.24 + 4.0), math.sin(t * 0.17 + 3.1))),
    ];
    for (final (color, alpha, size_, dir) in blobs) {
      final at = c + dir * r * 0.32;
      final rr = r * size_;
      canvas.drawCircle(
        at,
        rr,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (alpha * boost).clamp(0, 0.45)),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: rr)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassBackPainter old) => old.clock != clock;
}

/// Highlights, rim, sweep and the line-art outline (over the content).
class _GlassFrontPainter extends CustomPainter {
  _GlassFrontPainter(this.clock, this.k) : super(repaint: clock);

  final _GlassClock clock;
  final double k;

  static const double _sweepEvery = 7;
  static const double _sweepTime = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final ball = Rect.fromCircle(center: c, radius: r);
    canvas
      ..save()
      ..clipPath(Path()..addOval(ball));

    // Rim: a faint shade towards the lower right edge.
    canvas.drawRect(
      ball,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          radius: 1.05,
          colors: [
            AppColors.textPrimary.withValues(alpha: 0),
            AppColors.textPrimary.withValues(alpha: 0),
            AppColors.textPrimary.withValues(alpha: 0.07),
          ],
          stops: const [0, 0.78, 1],
        ).createShader(ball),
    );

    // Specular highlight, top left.
    canvas
      ..save()
      ..translate(c.dx - r * 0.38, c.dy - r * 0.48)
      ..rotate(-0.55);
    final spec = Rect.fromCenter(center: Offset.zero, width: r * 0.78, height: r * 0.34);
    canvas
      ..drawOval(
        spec,
        Paint()
          ..shader = RadialGradient(
            colors: [AppColors.shine.withValues(alpha: 0.95), AppColors.shine.withValues(alpha: 0)],
          ).createShader(spec),
      )
      ..restore();

    // Sweep: a diagonal band of light crossing the ball every few seconds.
    if (!clock.still) {
      final phase = (clock.t % _sweepEvery) / _sweepTime;
      if (phase < 1) {
        final x = c.dx - r * 1.6 + Curves.easeInOut.transform(phase) * r * 3.2;
        canvas
          ..save()
          ..translate(x, c.dy)
          ..rotate(0.5);
        final band = Rect.fromCenter(center: Offset.zero, width: r * 0.45, height: r * 3);
        canvas
          ..drawRect(
            band,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  AppColors.shine.withValues(alpha: 0),
                  AppColors.shine.withValues(alpha: 0.38),
                  AppColors.shine.withValues(alpha: 0),
                ],
              ).createShader(band),
          )
          ..restore();
      }
    }
    canvas.restore();

    // The outline, in the same line weight as the figure.
    canvas.drawCircle(
      c,
      r - 1.25,
      Paint()
        ..color = AppColors.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_GlassFrontPainter old) => old.clock != clock || old.k != k;
}

/// Four line stars around the ball, each twinkling on its own phase.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.clock, this.k) : super(repaint: clock);

  final _GlassClock clock;
  final double k;

  // (x, y) as fractions of the box, base radius in figure units, phase.
  static const _stars = [
    (0.88, 0.08, 5.0, 0.0),
    (0.52, -0.04, 3.0, 1.7),
    (1.02, 0.58, 3.6, 3.1),
    (0.78, 1.0, 2.6, 4.4), // below right, clear of her tail
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    for (final (fx, fy, base, phase) in _stars) {
      final tw = clock.still ? 1.0 : 0.55 + 0.45 * math.sin(clock.t * 1.8 + phase);
      final grow = 1 + 0.25 * clock.energy;
      final r = base * k * (0.75 + 0.35 * tw) * grow;
      final c = Offset(w * fx, w * fy);
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.textSecondary.withValues(alpha: 0.45 + 0.5 * tw)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.clock != clock || old.k != k;
}
