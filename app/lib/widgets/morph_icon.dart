import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'avatar.dart';

/// A stroke icon on a 24 × 24 grid: a list of polylines (a closed one repeats
/// its first point at the end). Shapes meant to morph into each other list
/// their strokes in matching order; a missing stroke grows out of (or shrinks
/// into) the last point of the other shape.
@immutable
class MorphShape {
  const MorphShape(this.strokes);

  final List<List<Offset>> strokes;
}

/// The shapes the app morphs between.
abstract final class MorphShapes {
  /// →
  static const MorphShape arrow = MorphShape([
    [Offset(5, 12), Offset(19, 12)],
    [Offset(13, 6), Offset(19, 12), Offset(13, 18)],
  ]);

  /// → into a door: "sign in".
  static const MorphShape signIn = MorphShape([
    [Offset(3, 12), Offset(14, 12)],
    [Offset(10, 8), Offset(14, 12), Offset(10, 16)],
    [Offset(14, 4), Offset(19, 4), Offset(19, 20), Offset(14, 20)],
  ]);

  /// A spinner: two arcs with gaps (it turns while busy). From [arrow] the
  /// head is already nearly the right arc, so only the shaft curls round.
  static final MorphShape ring = MorphShape([
    _arc(110, 250),
    _arc(-80, 70),
  ]);

  /// A microphone.
  static final MorphShape mic = MorphShape([
    [
      const Offset(9, 5),
      ..._arc(-180, 0, cx: 12, cy: 5, r: 3, steps: 8),
      const Offset(15, 12),
      ..._arc(0, 180, cx: 12, cy: 12, r: 3, steps: 8),
      const Offset(9, 5),
    ],
    [const Offset(19, 10), ..._arc(0, 180, cx: 12, cy: 10, r: 7, steps: 12)],
    [const Offset(12, 17), const Offset(12, 21)],
  ]);

  /// A stop square.
  static const MorphShape stop = MorphShape([
    [Offset(7, 7), Offset(17, 7), Offset(17, 17), Offset(7, 17), Offset(7, 7)],
  ]);

  /// An equalizer, and the same bars at other heights (a hover "beat").
  static const MorphShape bars = MorphShape([
    [Offset(4, 10), Offset(4, 14)],
    [Offset(8, 6), Offset(8, 18)],
    [Offset(12, 3), Offset(12, 21)],
    [Offset(16, 8), Offset(16, 16)],
    [Offset(20, 10), Offset(20, 14)],
  ]);
  static const MorphShape barsBeat = MorphShape([
    [Offset(4, 7), Offset(4, 17)],
    [Offset(8, 10), Offset(8, 14)],
    [Offset(12, 6), Offset(12, 18)],
    [Offset(16, 3), Offset(16, 21)],
    [Offset(20, 9), Offset(20, 15)],
  ]);

  /// Points on a circle around ([cx], [cy]), from [a0] to [a1] degrees
  /// (0 = east, clockwise on screen).
  static List<Offset> _arc(
    double a0,
    double a1, {
    double cx = 12,
    double cy = 12,
    double r = 7,
    int steps = 14,
  }) => [
    for (var i = 0; i <= steps; i++)
      Offset(
        cx + r * math.cos((a0 + (a1 - a0) * i / steps) * math.pi / 180),
        cy + r * math.sin((a0 + (a1 - a0) * i / steps) * math.pi / 180),
      ),
  ];
}

/// A stroke icon that morphs from [from] to [to] when [morphed] turns true
/// (and back), on a spring — after Morphicons (morphicons.com, MIT): every
/// stroke is resampled to the same number of points, and the points travel.
///
/// [spin] turns the icon while it shows [to] (a busy spinner). Motion is
/// instant when [Avatar.animationsEnabled] is false or motion is reduced.
class MorphIcon extends StatefulWidget {
  const MorphIcon({
    super.key,
    required this.from,
    required this.to,
    required this.morphed,
    this.size = 20,
    this.color,
    this.strokeWidth = 2,
    this.spin = false,
  });

  final MorphShape from;
  final MorphShape to;
  final bool morphed;
  final double size;

  /// Defaults to the [IconTheme] color.
  final Color? color;

  /// On the 24-unit grid.
  final double strokeWidth;
  final bool spin;

  /// A little overshoot, settling fast (Morphicons' "snappy").
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 30,
  );

  @override
  State<MorphIcon> createState() => _MorphIconState();
}

class _MorphIconState extends State<MorphIcon> with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: widget.morphed ? 1 : 0,
  );
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _still => !Avatar.animationsEnabled || MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(MorphIcon old) {
    super.didUpdateWidget(old);
    if (old.morphed != widget.morphed) {
      final target = widget.morphed ? 1.0 : 0.0;
      if (_still) {
        _t.value = target;
      } else {
        _t.animateWith(SpringSimulation(MorphIcon.spring, _t.value, target, _t.velocity));
      }
    }
    _syncSpin();
  }

  void _syncSpin() {
    final spin = widget.spin && widget.morphed && !_still;
    if (spin && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!spin && _turn.isAnimating) {
      _turn.stop();
      _turn.value = 0;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color!;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_t, _turn]),
        builder: (context, _) => Transform.rotate(
          angle: _turn.value * 2 * math.pi,
          child: CustomPaint(
            painter: _MorphPainter(
              from: widget.from,
              to: widget.to,
              t: _t.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.color,
    required this.strokeWidth,
  });

  final MorphShape from;
  final MorphShape to;
  final double t;
  final Color color;
  final double strokeWidth;

  static const int _points = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final count = math.max(from.strokes.length, to.strokes.length);
    for (var i = 0; i < count; i++) {
      final a = _resample(_strokeOr(from, i, to));
      final b = _resample(_strokeOr(to, i, from));
      final points = [for (var k = 0; k < _points; k++) Offset.lerp(a[k], b[k], t)!];
      var length = 0.0;
      for (var k = 1; k < points.length; k++) {
        length += (points[k] - points[k - 1]).distance;
      }
      if (length < 0.4) continue; // a stroke that has shrunk away leaves no dot
      canvas.drawPath(Path()..addPolygon(points, false), paint);
    }
  }

  /// Stroke [i] of [shape], or — when it has none — a point where the other
  /// shape's stroke starts growing from.
  static List<Offset> _strokeOr(MorphShape shape, int i, MorphShape other) {
    if (i < shape.strokes.length) return shape.strokes[i];
    final anchor = shape.strokes.isEmpty ? const Offset(12, 12) : shape.strokes.last.last;
    return [anchor, anchor];
  }

  /// [_points] points evenly spaced along the polyline.
  static List<Offset> _resample(List<Offset> line) {
    if (line.length < 2) return List.filled(_points, line.isEmpty ? Offset.zero : line.first);
    final lengths = <double>[0];
    for (var k = 1; k < line.length; k++) {
      lengths.add(lengths.last + (line[k] - line[k - 1]).distance);
    }
    final total = lengths.last;
    if (total == 0) return List.filled(_points, line.first);
    final out = <Offset>[];
    var seg = 1;
    for (var k = 0; k < _points; k++) {
      final d = total * k / (_points - 1);
      while (seg < line.length - 1 && lengths[seg] < d) {
        seg++;
      }
      final span = lengths[seg] - lengths[seg - 1];
      final f = span == 0 ? 0.0 : (d - lengths[seg - 1]) / span;
      out.add(Offset.lerp(line[seg - 1], line[seg], f)!);
    }
    return out;
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.t != t || old.color != color || old.from != from || old.to != to;
}
