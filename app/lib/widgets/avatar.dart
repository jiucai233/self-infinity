import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How the avatar looks (`docs/ux-chat.md` Section 3).
enum AvatarMood { smile, neutral, stern, angry, happy }

/// What the avatar is doing.
enum AvatarState { idle, listening, thinking, speaking }

/// The one small thing that tells the agents apart.
enum _Accessory { none, hair, glasses, hat, bowTie, wizard }

const Map<String, _Accessory> _agentLooks = {
  'front_desk': _Accessory.wizard,
  'narrator': _Accessory.bowTie,
  'recommender': _Accessory.hat,
  'planner': _Accessory.glasses,
  'clarifier': _Accessory.bowTie,
  'syllabus_finder': _Accessory.hat,
  'material_finder': _Accessory.glasses,
  'auditor': _Accessory.glasses,
  'challenger': _Accessory.hat,
  'recorder': _Accessory.hat,
  'linker': _Accessory.bowTie,
  'checkin_converter': _Accessory.hair,
};

/// The agent's mood when nothing else is said.
AvatarMood defaultMoodOf(String agent) => switch (agent) {
  'front_desk' || 'recommender' || 'checkin_converter' => AvatarMood.smile,
  'auditor' || 'challenger' => AvatarMood.stern,
  _ => AvatarMood.neutral,
};

/// A thin dark line stick figure, one per agent (the user's sketch).
///
/// * [agent] picks the accessory (hair / glasses / hat / bow tie); an unknown
///   name gets none.
/// * [mood] shapes the face; [state] adds what she is doing: a moving mouth
///   while speaking, sound marks while listening.
/// * [wave] raises the right arm and waves a few times.
/// * [holdOrb] holds the right hand out, palm up, at about (104, 88) of the
///   100 x 140 figure box — [OrbAvatar] puts the crystal ball there. The hand
///   reaches past the figure's box; the caller must leave room for it.
/// * [animate] turns the movement off (the figure is then static). It defaults
///   to [animationsEnabled], which tests switch off.
///
/// A 3D model will replace it later, picked by the same `agent` name.
class Avatar extends StatefulWidget {
  const Avatar({
    super.key,
    required this.agent,
    this.mood = AvatarMood.neutral,
    this.state = AvatarState.idle,
    this.wave = false,
    this.holdOrb = false,
    this.size = 160,
    this.animate,
  });

  /// Global switch for the movement; `false` in widget tests.
  static bool animationsEnabled = true;

  /// Where the open palm of a [holdOrb] figure is, in the avatar's own
  /// coordinates (the box is `size * aspect` wide and `size` high).
  static Offset orbHandAt(String agent, double size) {
    final (k, origin) = _AvatarPainter.frame(agent, Size(size * aspect, size));
    return origin + _AvatarPainter.orbHand * k;
  }

  /// Scale from figure units to logical pixels.
  static double unit(String agent, double size) =>
      _AvatarPainter.frame(agent, Size(size * aspect, size)).$1;

  /// Width / height of the avatar's box.
  static const double aspect = _AvatarPainter.aspect;

  final String agent;
  final AvatarMood mood;
  final AvatarState state;
  final bool wave;
  final bool holdOrb;

  /// Height of the figure; it is 5/7 of that wide.
  final double size;
  final bool? animate;

  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> with SingleTickerProviderStateMixin {
  static const int _waveCycles = 3;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  bool get _looping =>
      widget.state == AvatarState.speaking || widget.state == AvatarState.listening;

  @override
  void initState() {
    super.initState();
    _sync(null);
  }

  @override
  void didUpdateWidget(Avatar old) {
    super.didUpdateWidget(old);
    _sync(old);
  }

  void _sync(Avatar? old) {
    if (!_animate) {
      _controller.stop();
      return;
    }
    if (_looping) {
      if (!_controller.isAnimating || old?.state != widget.state) _controller.repeat();
    } else if (widget.wave) {
      // A finished wave is not started again by a rebuild.
      if (old == null || !old.wave) _controller.repeat(count: _waveCycles);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.agent} avatar',
      child: SizedBox(
        width: widget.size * _AvatarPainter.aspect,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _AvatarPainter(
              agent: widget.agent,
              mood: widget.mood,
              state: widget.state,
              wave: widget.wave,
              holdOrb: widget.holdOrb,
              // Static figures hold the raised hand still.
              t: _animate && _controller.isAnimating ? _controller.value : 0,
              stroke: (widget.size / 90).clamp(1.8, 3.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter({
    required this.agent,
    required this.mood,
    required this.state,
    required this.wave,
    this.holdOrb = false,
    this.headOnly = false,
    required this.t,
    required this.stroke,
  });

  /// Width / height of the figure's box.
  static const double aspect = 100 / 140;

  final String agent;
  final AvatarMood mood;
  final AvatarState state;
  final bool wave;
  final bool holdOrb;

  /// Draws only the head (a close-up for the 28 px chat portraits).
  final bool headOnly;

  /// Where the held orb's hand is, in the 100 x 140 figure box.
  static const Offset orbHand = Offset(104, 88);

  /// Animation value 0–1.
  final double t;

  /// Line width in logical pixels.
  final double stroke;

  // The figure is drawn in a 100 x 140 box.
  static const Offset _head = Offset(50, 30);
  static const double _headR = 20;

  /// Extra room above the head (the wizard's hat), in figure units.
  static double topRoom(String agent) => _agentLooks[agent] == _Accessory.wizard ? 20 : 0;

  /// Scale and origin of the 100 x 140 figure box inside [size].
  static (double, Offset) frame(String agent, Size size) {
    final top = topRoom(agent);
    final k = math.min(size.width / 100, size.height / (140 + top));
    return (k, Offset((size.width - 100 * k) / 2, (size.height - (140 + top) * k) / 2 + top * k));
  }

  /// The part of the 100 x 140 figure that a head close-up shows.
  static Rect headBox(String agent) => _agentLooks[agent] == _Accessory.wizard
      ? const Rect.fromLTWH(12, -20, 76, 76)
      : const Rect.fromLTWH(18, -4, 64, 64);

  @override
  void paint(Canvas canvas, Size size) {
    final double k;
    if (headOnly) {
      final box = headBox(agent);
      k = size.width / box.width;
      canvas
        ..scale(k)
        ..translate(-box.left, -box.top);
    } else {
      final (scale, origin) = frame(agent, size);
      k = scale;
      canvas
        ..translate(origin.dx, origin.dy)
        ..scale(k);
    }
    final ink = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke / k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = AppColors.textPrimary;

    final look = _agentLooks[agent] ?? _Accessory.none;

    // Head, body, legs (the wizard wears a robe instead).
    canvas.drawCircle(_head, _headR, ink);
    if (headOnly) {
      _accessory(canvas, look, ink);
      _face(canvas, ink, dot);
      return;
    }
    if (look == _Accessory.wizard) {
      _robe(canvas, ink);
    } else {
      canvas.drawLine(const Offset(50, 50), const Offset(50, 96), ink);
      canvas
        ..drawLine(const Offset(50, 96), const Offset(36, 132), ink)
        ..drawLine(const Offset(36, 132), const Offset(29, 132), ink)
        ..drawLine(const Offset(50, 96), const Offset(64, 132), ink)
        ..drawLine(const Offset(64, 132), const Offset(71, 132), ink);
    }

    // Arms.
    canvas.drawLine(const Offset(50, 62), const Offset(30, 86), ink);
    if (holdOrb) {
      // Elbow down, forearm up to the open palm under the ball.
      canvas
        ..drawPath(
          Path()
            ..moveTo(50, 62)
            ..lineTo(76, 96)
            ..lineTo(orbHand.dx - 2, orbHand.dy + 2),
          ink,
        )
        ..drawPath(
          Path()
            ..moveTo(orbHand.dx - 9, orbHand.dy - 2)
            ..quadraticBezierTo(orbHand.dx, orbHand.dy + 6, orbHand.dx + 9, orbHand.dy - 2),
          ink,
        );
    } else if (wave) {
      final hand = 80 + 7 * math.sin(t * 2 * math.pi * 2);
      canvas.drawPath(
        Path()
          ..moveTo(50, 62)
          ..lineTo(76, 62)
          ..lineTo(hand, 38),
        ink,
      );
    } else {
      canvas.drawLine(const Offset(50, 62), const Offset(70, 86), ink);
    }

    _accessory(canvas, look, ink);
    _face(canvas, ink, dot);
    if (state == AvatarState.listening) _listening(canvas, ink);
  }

  void _face(Canvas canvas, Paint ink, Paint dot) {
    const left = Offset(42, 27);
    const right = Offset(58, 27);
    final speakingOpen = state == AvatarState.speaking && (t * 4).floor().isEven;

    // Eyes (and brows).
    switch (mood) {
      case AvatarMood.angry:
        for (final c in [left, right]) {
          canvas.drawPath(_scribble(c), ink);
        }
        canvas
          ..drawLine(const Offset(37, 20), const Offset(47, 24), ink)
          ..drawLine(const Offset(63, 20), const Offset(53, 24), ink);
      case AvatarMood.happy:
        for (final c in [left, right]) {
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - 4, c.dy + 2)
              ..quadraticBezierTo(c.dx, c.dy - 5, c.dx + 4, c.dy + 2),
            ink,
          );
        }
      case AvatarMood.stern:
        canvas
          ..drawCircle(left, 2, dot)
          ..drawCircle(right, 2, dot)
          ..drawLine(const Offset(37, 21), const Offset(47, 21), ink)
          ..drawLine(const Offset(53, 21), const Offset(63, 21), ink);
      case AvatarMood.smile:
      case AvatarMood.neutral:
        canvas
          ..drawCircle(left, 2, dot)
          ..drawCircle(right, 2, dot);
    }

    // Mouth.
    if (speakingOpen) {
      canvas.drawOval(Rect.fromCenter(center: const Offset(50, 39), width: 9, height: 7), ink);
      return;
    }
    switch (mood) {
      case AvatarMood.smile:
        canvas.drawPath(
          Path()
            ..moveTo(43, 36)
            ..quadraticBezierTo(50, 43, 57, 36),
          ink,
        );
      case AvatarMood.happy:
        canvas.drawPath(
          Path()
            ..moveTo(40, 35)
            ..quadraticBezierTo(50, 48, 60, 35),
          ink,
        );
      case AvatarMood.angry:
        canvas.drawPath(
          Path()
            ..moveTo(43, 41)
            ..quadraticBezierTo(50, 34, 57, 41),
          ink,
        );
      case AvatarMood.neutral:
        canvas.drawLine(const Offset(45, 38), const Offset(55, 38), ink);
      case AvatarMood.stern:
        canvas.drawLine(const Offset(44, 39), const Offset(56, 39), ink);
    }
  }

  /// A scribbled-out eye: a zigzag inside a small box around [c].
  Path _scribble(Offset c) {
    final p = Path()..moveTo(c.dx - 4, c.dy - 3);
    const steps = [
      Offset(4, 3),
      Offset(-4, 1),
      Offset(4, -3),
      Offset(-4, 3),
      Offset(4, 1),
    ];
    var at = Offset(c.dx - 4, c.dy - 3);
    for (final s in steps) {
      at += s;
      p.lineTo(at.dx, at.dy);
    }
    return p;
  }

  void _listening(Canvas canvas, Paint ink) {
    final grey = Paint()
      ..color = AppColors.textTertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink.strokeWidth
      ..strokeCap = StrokeCap.round;
    final big = (t * 2).floor().isEven;
    for (final r in big ? [26.0, 33.0] : [26.0]) {
      canvas.drawArc(Rect.fromCircle(center: _head, radius: r), -0.5, 1.0, false, grey);
    }
  }

  /// A long robe from the shoulders to the feet, with the feet peeking out.
  void _robe(Canvas canvas, Paint ink) {
    canvas
      ..drawPath(
        Path()
          ..moveTo(44, 52)
          ..quadraticBezierTo(38, 90, 30, 128)
          ..quadraticBezierTo(50, 133, 70, 128)
          ..quadraticBezierTo(62, 90, 56, 52),
        ink,
      )
      ..drawLine(const Offset(42, 130), const Offset(36, 134), ink)
      ..drawLine(const Offset(58, 130), const Offset(64, 134), ink);
  }

  /// A small four-point star centred on [c].
  static Path star(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);

  void _accessory(Canvas canvas, _Accessory accessory, Paint ink) {
    switch (accessory) {
      case _Accessory.none:
        break;
      case _Accessory.wizard:
        // Long hair falling from under the hat.
        canvas
          ..drawPath(
            Path()
              ..moveTo(32, 20)
              ..quadraticBezierTo(26, 36, 30, 50),
            ink,
          )
          ..drawPath(
            Path()
              ..moveTo(68, 20)
              ..quadraticBezierTo(74, 36, 70, 50),
            ink,
          );
        // Pointed hat with a bent tip and a star.
        canvas
          ..drawPath(
            Path()
              ..moveTo(24, 15)
              ..quadraticBezierTo(50, 9, 76, 15),
            ink,
          )
          ..drawPath(
            Path()
              ..moveTo(33, 13)
              ..quadraticBezierTo(44, -2, 52, -14)
              ..quadraticBezierTo(58, -18, 64, -12)
              ..moveTo(52, -14)
              ..quadraticBezierTo(58, 0, 67, 13),
            ink,
          )
          ..drawPath(star(const Offset(50, 4), 3.5), ink);
      case _Accessory.hair:
        canvas
          ..drawLine(const Offset(50, 9), const Offset(50, 1), ink)
          ..drawLine(const Offset(41, 12), const Offset(36, 5), ink)
          ..drawLine(const Offset(59, 12), const Offset(64, 5), ink);
      case _Accessory.glasses:
        canvas
          ..drawCircle(const Offset(42, 27), 6.5, ink)
          ..drawCircle(const Offset(58, 27), 6.5, ink)
          ..drawLine(const Offset(48.5, 27), const Offset(51.5, 27), ink);
      case _Accessory.hat:
        canvas
          ..drawLine(const Offset(29, 17), const Offset(71, 17), ink)
          ..drawPath(
            Path()
              ..moveTo(36, 17)
              ..cubicTo(36, -3, 64, -3, 64, 17),
            ink,
          );
      case _Accessory.bowTie:
        canvas.drawPath(
          Path()
            ..moveTo(50, 55)
            ..lineTo(40, 50)
            ..lineTo(40, 60)
            ..close()
            ..moveTo(50, 55)
            ..lineTo(60, 50)
            ..lineTo(60, 60)
            ..close(),
          ink,
        );
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.agent != agent ||
      old.mood != mood ||
      old.state != state ||
      old.wave != wave ||
      old.holdOrb != holdOrb ||
      old.headOnly != headOnly ||
      old.t != t ||
      old.stroke != stroke;
}

/// The head of [agent] in a round, light-grey badge — the portrait next to a
/// message in the chat panel (`docs/DESIGN.md` Section 4). Always still.
class AvatarHead extends StatelessWidget {
  const AvatarHead({super.key, required this.agent, this.size = 28, this.mood});

  final String agent;

  /// Diameter of the badge.
  final double size;

  /// Defaults to [defaultMoodOf] the agent.
  final AvatarMood? mood;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$agent avatar',
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
          child: ClipOval(
            child: CustomPaint(
              painter: _AvatarPainter(
                agent: agent,
                mood: mood ?? defaultMoodOf(agent),
                state: AvatarState.idle,
                wave: false,
                headOnly: true,
                t: 0,
                stroke: size / 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
