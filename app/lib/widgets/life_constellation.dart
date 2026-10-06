import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/life_tree.dart';
import '../theme/tokens.dart';
import 'avatar.dart';

/// The life tree as a constellation on the night panel (`docs/DESIGN.md` §4):
/// you in the middle, main quests on the first ring, courses on the next,
/// their nodes beyond. The disc floats inside a faint wire shell and turns
/// slowly in 3D; cleared nodes burn gold and throw sparks.
///
/// * [compact]: the version inside the crystal ball — no labels, no input.
/// * Hover a node: the drift pauses and its name shows. Drag sideways: turn
///   the disc. Tap: [onSelect].
/// * [selected] gets a lime ring and its label; [highlighted] (search hits)
///   get their labels.
///
/// Motion stops (final frame, fixed angle) when [animate] is false, when
/// [Avatar.animationsEnabled] is false, or under reduced motion.
class LifeConstellation extends StatefulWidget {
  const LifeConstellation({
    super.key,
    required this.tree,
    this.compact = false,
    this.boost = false,
    this.animate,
    this.selected,
    this.highlighted = const {},
    this.onSelect,
  });

  final LifeTree tree;

  final bool compact;

  /// Hover on the ball: faster drift, brighter glow.
  final bool boost;
  final bool? animate;
  final String? selected;
  final Set<String> highlighted;
  final ValueChanged<LifeNode>? onSelect;

  @override
  State<LifeConstellation> createState() => LifeConstellationState();
}

/// Public so that tests can find a node's position on screen.
class LifeConstellationState extends State<LifeConstellation> with SingleTickerProviderStateMixin {
  late _Layout _layout = _Layout.of(widget.tree, compact: widget.compact);
  final _clock = _Clock();
  final _projected = _Projection();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  String? _hovered;

  bool _still(BuildContext context) =>
      !(widget.animate ?? Avatar.animationsEnabled) || MediaQuery.of(context).disableAnimations;

  /// Where node [key] was drawn last frame (local coordinates), or null.
  Offset? positionOf(String key) => _projected.at[key];

  @override
  void didUpdateWidget(LifeConstellation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tree != widget.tree || oldWidget.compact != widget.compact) {
      _layout = _Layout.of(widget.tree, compact: widget.compact);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _ticker?.stop();
      _clock.settle();
    } else {
      _ticker ??= createTicker(_tick)..start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock.advance(dt, boost: widget.boost, paused: _hovered != null);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  String? _hit(Offset p) {
    String? best;
    var bestD = 22.0;
    for (final e in _projected.at.entries) {
      final d = (e.value - p).distance;
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_still(context)) _clock.settle();
    final theme = Theme.of(context).textTheme;
    final painter = _NightPainter(
      layout: _layout,
      clock: _clock,
      projection: _projected,
      compact: widget.compact,
      selected: widget.selected,
      hovered: _hovered,
      highlighted: widget.highlighted,
      titleStyle: theme.titleSmall!.copyWith(color: AppColors.nightText),
      labelStyle: theme.labelMedium!.copyWith(color: AppColors.nightText),
    );
    final paint = CustomPaint(painter: painter, size: Size.infinite);
    if (widget.compact || widget.onSelect == null) return paint;
    return MouseRegion(
      cursor: _hovered == null ? SystemMouseCursors.grab : SystemMouseCursors.click,
      onHover: (e) {
        final h = _hit(e.localPosition);
        if (h != _hovered) setState(() => _hovered = h);
      },
      onExit: (_) => setState(() => _hovered = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: (d) => _clock.drag(d.delta.dx / 260),
        onTapUp: (d) {
          final key = _hit(d.localPosition);
          final node = key == null ? null : widget.tree.byKey(key);
          if (node != null) widget.onSelect!(node);
        },
        child: paint,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Time, rotation and glow, shared with the painter.
class _Clock extends ChangeNotifier {
  double t = 0;
  double angle = 0.6;
  double energy = 0;
  bool still = false;

  static const double _turnSeconds = 90;

  void advance(double dt, {required bool boost, required bool paused}) {
    still = false;
    t += dt;
    energy += ((boost ? 1.0 : 0.0) - energy) * math.min(1, dt * 6);
    if (!paused) angle += dt * (2 * math.pi / _turnSeconds) * (1 + 2.5 * energy);
    notifyListeners();
  }

  void drag(double radians) {
    angle += radians;
    notifyListeners();
  }

  void settle() {
    still = true;
    t = 100;
    angle = 0.6;
    energy = 0;
  }
}

/// Screen positions of the last frame, for hit testing.
class _Projection {
  final Map<String, Offset> at = {};
}

class _P3 {
  const _P3(this.x, this.y, this.z);
  final double x, y, z;
}

/// 3D positions in a unit sphere: the tree on a disc (x–z plane) with a little
/// height per node, and the wire shell around it.
class _Layout {
  _Layout(this.tree, this.pos, this.depth, this.maxDepth, this.dust, this.wires, this.faces);

  final LifeTree tree;
  final Map<String, _P3> pos;
  final Map<String, int> depth;
  final int maxDepth;
  final List<_P3> dust;
  final List<(int, int)> wires;
  final List<(int, int, int)> faces;

  static double _hash(String s, int salt) {
    var h = 2166136261 ^ salt;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xffffffff;
    }
    return (h % 10000) / 10000;
  }

  static _Layout of(LifeTree tree, {required bool compact}) {
    final depth = tree.depths;
    final maxDepth = math.max(1, tree.maxDepth);
    final kids = <String, List<String>>{};
    for (final n in tree.nodes.skip(1)) {
      (kids[n.parent!] ??= []).add(n.key);
    }
    final leaves = <String, int>{};
    int count(String k) {
      var n = 0;
      for (final c in kids[k] ?? const <String>[]) {
        n += count(c);
      }
      return leaves[k] = math.max(1, n);
    }

    count(LifeTree.selfKey);

    final pos = <String, _P3>{};
    void place(String key, double from, double span) {
      final d = depth[key]!;
      // Square-root spacing keeps the outer rings (most nodes) roomy.
      final r = d == 0 ? 0.0 : 0.92 * math.sqrt(d / maxDepth);
      final a = from + span / 2;
      final lift = d == 0 ? 0.0 : (_hash(key, 7) - 0.5) * (d == 1 ? 0.18 : 0.42) * r;
      pos[key] = _P3(r * math.cos(a), lift, r * math.sin(a));
      var at = from;
      for (final c in kids[key] ?? const <String>[]) {
        final s = span * leaves[c]! / leaves[key]!;
        place(c, at, s);
        at += s;
      }
    }

    place(LifeTree.selfKey, -math.pi / 2, 2 * math.pi);

    // The wire shell: points on a sphere, joined to their near neighbours.
    final rng = math.Random(11);
    final n = compact ? 46 : 120;
    final dust = <_P3>[];
    for (var i = 0; i < n; i++) {
      final u = rng.nextDouble() * 2 - 1;
      final th = rng.nextDouble() * 2 * math.pi;
      final rr = 1.02 + rng.nextDouble() * (compact ? 0.08 : 0.22);
      final s = math.sqrt(1 - u * u);
      dust.add(_P3(rr * s * math.cos(th), rr * u * 0.82, rr * s * math.sin(th)));
    }
    double dist(_P3 a, _P3 b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2) + math.pow(a.z - b.z, 2));
    final limit = compact ? 0.62 : 0.42;
    final wires = <(int, int)>[];
    final near = <int, Set<int>>{};
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (dist(dust[i], dust[j]) < limit) {
          wires.add((i, j));
          (near[i] ??= {}).add(j);
          (near[j] ??= {}).add(i);
        }
      }
    }
    final faces = <(int, int, int)>[];
    for (final (i, j) in wires) {
      for (final k in near[i]!.intersection(near[j]!)) {
        if (k > j && faces.length < (compact ? 20 : 70)) faces.add((i, j, k));
      }
    }
    return _Layout(tree, pos, depth, maxDepth, dust, wires, faces);
  }
}

class _NightPainter extends CustomPainter {
  _NightPainter({
    required this.layout,
    required this.clock,
    required this.projection,
    required this.compact,
    required this.selected,
    required this.hovered,
    required this.highlighted,
    required this.titleStyle,
    required this.labelStyle,
  }) : super(repaint: clock);

  final _Layout layout;
  final _Clock clock;
  final _Projection projection;
  final bool compact;
  final String? selected;
  final String? hovered;
  final Set<String> highlighted;
  final TextStyle titleStyle;
  final TextStyle labelStyle;

  /// Forming: ring [d] appears after [_ringDelay]·d seconds, over [_ringTime].
  static const double _ringDelay = 0.18;
  static const double _ringTime = 0.5;

  double _appear(int depth) => ((clock.t - 0.2 - depth * _ringDelay) / _ringTime).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    projection.at.clear();
    final center = size.center(Offset.zero);
    // How far we look down onto the disc.
    final sinT = compact ? 0.78 : 0.56;
    final cosT = math.sqrt(1 - sinT * sinT);
    final radius = compact
        ? size.shortestSide * 0.40
        : math.min(size.width * 0.40, size.height * 0.44 / (sinT + 0.22));
    final u = compact ? size.shortestSide / 64 : radius / 64;
    const camera = 3.2;
    final ca = math.cos(clock.angle);
    final sa = math.sin(clock.angle);

    // (screen point, depth 0 = middle, + = far, scale)
    (Offset, double, double) project(_P3 p) {
      final x1 = p.x * ca + p.z * sa;
      final z1 = -p.x * sa + p.z * ca;
      final sy = -z1 * sinT - p.y * cosT;
      final depth = z1 * cosT - p.y * sinT;
      final k = camera / (camera + depth);
      return (center + Offset(x1, sy) * radius * k, depth, k);
    }

    // Far = dim, near = bright.
    double fade(double depth) => (0.78 - 0.5 * depth).clamp(0.2, 1.0);

    // -- the wire shell ------------------------------------------------------
    final dustIn = Curves.easeOut.transform(((clock.t - 0.1) / 1.4).clamp(0.0, 1.0));
    if (dustIn > 0) {
      final pts = [for (final d in layout.dust) project(d)];
      final face = Paint()..style = PaintingStyle.fill;
      for (final (i, j, k) in layout.faces) {
        final a = pts[i], b = pts[j], c = pts[k];
        final f = fade((a.$2 + b.$2 + c.$2) / 3);
        face.color = AppColors.nightLine.withValues(alpha: 0.028 * f * dustIn);
        canvas.drawPath(
          Path()
            ..moveTo(a.$1.dx, a.$1.dy)
            ..lineTo(b.$1.dx, b.$1.dy)
            ..lineTo(c.$1.dx, c.$1.dy)
            ..close(),
          face,
        );
      }
      final wire = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.5 : 0.7;
      for (final (i, j) in layout.wires) {
        final f = fade((pts[i].$2 + pts[j].$2) / 2);
        wire.color = AppColors.nightLine.withValues(alpha: 0.22 * f * dustIn);
        canvas.drawLine(pts[i].$1, pts[j].$1, wire);
      }
      final dot = Paint();
      for (final p in pts) {
        dot.color = AppColors.nightLine.withValues(alpha: 0.55 * fade(p.$2) * dustIn);
        canvas.drawCircle(p.$1, (compact ? 0.6 : 1.1) * p.$3, dot);
      }
    }

    // -- warm core behind you ------------------------------------------------
    final core = project(const _P3(0, 0, 0)).$1;
    canvas.drawCircle(
      core,
      radius * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.ember.withValues(alpha: 0.10 + 0.06 * clock.energy),
            AppColors.ember.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: core, radius: radius * 0.55)),
    );

    // -- the tree --------------------------------------------------------------
    final tree = layout.tree;
    final proj = <String, (Offset, double, double)>{
      for (final n in tree.nodes) n.key: project(layout.pos[n.key]!),
    };

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final edges = <(Offset, Offset)>[];
    for (final n in tree.nodes.skip(1)) {
      final a = proj[n.parent!]!;
      final b = proj[n.key]!;
      final p = Curves.easeOutCubic.transform(_appear(layout.depth[n.key]!));
      if (p <= 0) continue;
      final end = Offset.lerp(a.$1, b.$1, p)!;
      final f = fade((a.$2 + b.$2) / 2);
      final hot = n.isMastered;
      edge
        ..strokeWidth = (n.kind == LifeKind.skill ? 0.9 : 1.3) * (compact ? 0.8 : 1)
        ..color = hot
            ? AppColors.ember.withValues(alpha: 0.55 * f)
            : AppColors.nightLine.withValues(alpha: (n.kind == LifeKind.skill ? 0.38 : 0.6) * f);
      canvas.drawLine(a.$1, end, edge);
      edges.add((a.$1, b.$1));
    }

    // A spark running out along one edge every few seconds.
    if (!clock.still && edges.isNotEmpty && clock.t > 1.8) {
      const every = 2.6;
      final run = (clock.t / every).floor();
      final phase = clock.t / every - run;
      if (phase < 0.6) {
        final (a, b) = edges[(run * 7 + 3) % edges.length];
        final q = Curves.easeInOut.transform(phase / 0.6);
        final at = Offset.lerp(a, b, q)!;
        final f = math.sin(q * math.pi);
        _glow(canvas, at, u * 1.6, AppColors.ember, 0.6 * f);
        canvas.drawCircle(at, u * 0.45, Paint()..color = AppColors.emberHot.withValues(alpha: f));
      }
    }

    // Nodes, far ones first.
    final order = tree.nodes.toList()..sort((a, b) => proj[b.key]!.$2.compareTo(proj[a.key]!.$2));
    for (final n in order) {
      final (p, depth, k) = proj[n.key]!;
      final pop = _appear(layout.depth[n.key]!);
      if (pop <= 0) continue;
      final s = Curves.easeOutBack.transform(pop).clamp(0.0, 1.2) * k;
      final f = fade(depth) * pop;
      projection.at[n.key] = p;
      _node(canvas, n, p, u, s, f);
    }

    // Sparks rising from cleared nodes.
    final spark = Paint()..blendMode = BlendMode.plus;
    for (final n in tree.nodes) {
      if (!n.isMastered || _appear(layout.depth[n.key]!) < 1) continue;
      final (p, depth, k) = proj[n.key]!;
      for (var i = 0; i < (compact ? 2 : 4); i++) {
        final seed = _Layout._hash(n.key, i + 3);
        final phase = (clock.t * (0.32 + 0.2 * seed) + seed) % 1.0;
        final rise = phase * u * (compact ? 6 : 9) * k;
        final sway = math.sin(phase * 6 + seed * 12) * u * 0.9;
        final at = p + Offset(sway, -rise - u * 0.8);
        final a = math.sin(phase * math.pi) * fade(depth);
        spark.color = Color.lerp(AppColors.emberHot, AppColors.ember, phase)!.withValues(alpha: 0.9 * a);
        canvas.drawCircle(at, u * (0.22 + 0.18 * (1 - phase)) * k, spark);
      }
    }

    if (compact) return;

    // Labels on top: you, main quests, courses; skills when hovered,
    // selected or found.
    for (final n in order.reversed) {
      final hit = projection.at[n.key];
      if (hit == null) continue;
      final (_, depth, _) = proj[n.key]!;
      final show = n.kind != LifeKind.skill ||
          n.key == hovered ||
          n.key == selected ||
          highlighted.contains(n.key);
      if (!show) continue;
      final f = n.key == hovered || n.key == selected ? 1.0 : fade(depth);
      final style = switch (n.kind) {
        LifeKind.self || LifeKind.goal => titleStyle,
        _ => labelStyle,
      };
      final label = n.kind == LifeKind.self ? 'You' : n.label;
      _text(canvas, label, style.copyWith(color: style.color!.withValues(alpha: f)), hit + Offset(u * 2.4, 0), 200);
    }
  }

  void _node(Canvas canvas, LifeNode n, Offset p, double u, double s, double f) {
    final pulse = clock.still ? 0.5 : 0.5 + 0.5 * math.sin(clock.t * 2.4 + p.dx * 0.05);
    final glowBoost = 1 + 0.6 * clock.energy;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, u * 0.28);
    switch (n.kind) {
      case LifeKind.self:
        _glow(canvas, p, u * 4.2 * s, AppColors.emberHot, 0.35 * f * glowBoost);
        canvas.drawCircle(p, u * 1.25 * s, Paint()..color = AppColors.nightText.withValues(alpha: f));
        _star(canvas, p, u * 3.4 * s, AppColors.nightText.withValues(alpha: 0.75 * f));
      case LifeKind.goal:
        canvas
          ..drawCircle(p, u * 1.6 * s, Paint()..color = AppColors.night)
          ..drawCircle(p, u * 1.6 * s, ring..color = AppColors.nightText.withValues(alpha: f))
          ..drawCircle(p, u * 0.6 * s, Paint()..color = AppColors.nightText.withValues(alpha: f));
      case LifeKind.course || LifeKind.skill:
        final r = u * (n.kind == LifeKind.course ? 1.25 : (n.boss ? 1.0 : 0.82)) * s;
        if (n.isMastered) {
          _glow(canvas, p, r * 3.2, AppColors.ember, 0.5 * f * glowBoost);
          canvas.drawCircle(p, r, Paint()..color = Color.lerp(AppColors.ember, AppColors.emberHot, 0.35)!.withValues(alpha: f));
        } else if (n.failed) {
          _glow(canvas, p, r * 2.4, AppColors.emberRed, 0.3 * f);
          canvas.drawCircle(p, r, Paint()..color = AppColors.emberRed.withValues(alpha: f));
        } else if (n.isAvailable) {
          _glow(canvas, p, r * (2 + pulse), AppColors.nightText, (0.10 + 0.12 * pulse) * f * glowBoost);
          canvas
            ..drawCircle(p, r, Paint()..color = AppColors.night)
            ..drawCircle(p, r, ring..color = AppColors.nightText.withValues(alpha: f));
        } else if (n.status == null) {
          // A course hub with several roots.
          canvas.drawCircle(p, r, ring..color = AppColors.nightLine.withValues(alpha: f));
        } else {
          canvas
            ..drawCircle(p, r * 0.62, Paint()..color = AppColors.nightHigh)
            ..drawCircle(
              p,
              r * 0.62,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(0.8, u * 0.2)
                ..color = AppColors.nightLine.withValues(alpha: 0.8 * f),
            );
        }
        if (n.boss && !n.isLocked) {
          canvas.drawCircle(
            p,
            r + u * 0.75 * s,
            ring
              ..strokeWidth = math.max(0.8, u * 0.18)
              ..color = (n.isMastered ? AppColors.ember : AppColors.nightLine).withValues(alpha: 0.8 * f),
          );
        }
    }
    if (n.key == selected || n.key == hovered) {
      canvas.drawCircle(
        p,
        u * 2.6 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.glow.withValues(alpha: n.key == selected ? 0.95 : 0.6),
      );
    }
  }

  static void _glow(Canvas canvas, Offset p, double r, Color c, double a) {
    if (a <= 0 || r <= 0) return;
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [c.withValues(alpha: a.clamp(0.0, 1.0)), c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
  }

  static void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 0.5, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 0.5, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Paints [text] starting at [at] (vertically centred on it unless
  /// [centered] is false) and returns its height.
  static double _text(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset at,
    double maxWidth, {
    int lines = 1,
    bool centered = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, centered ? at - Offset(0, tp.height / 2) : at);
    return tp.height;
  }

  @override
  bool shouldRepaint(_NightPainter old) =>
      old.layout != layout ||
      old.selected != selected ||
      old.hovered != hovered ||
      old.highlighted != highlighted ||
      old.compact != compact;
}
