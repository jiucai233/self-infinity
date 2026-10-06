import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/life_tree.dart';
import '../theme/tokens.dart';
import 'avatar.dart';
import 'ink_sprites.dart';

/// The life tree drawn as a tree, in ink on paper. **Not in use** — an experiment
/// kept for the life tree redesign (2026-10-06); see it with
/// `SHOTS_DIR=… flutter test test/ink_tree_preview_test.dart`.
///
/// The trunk rises from you; each main quest is a limb, each course a branch,
/// each node a twig. What you have mastered blossoms in ember — the only
/// color. Ready nodes are open buds, locked ones closed buds, failed ones a
/// small red leaf. The shape comes from the data alone (a seeded wobble, no
/// randomness between frames), so the same tree always grows the same way.
///
/// * It grows in once (trunk, then limbs, then twigs) unless [animate] is
///   false, [Avatar.animationsEnabled] is false, or motion is reduced.
/// * Hover a point: its name shows. Tap: [onSelect].
/// * [selected] gets a lime ring and its label; [highlighted] get labels.
/// * [compact]: no labels and no input (a thumbnail).
class InkTree extends StatefulWidget {
  const InkTree({
    super.key,
    required this.tree,
    this.compact = false,
    this.animate,
    this.selected,
    this.highlighted = const {},
    this.onSelect,
  });

  final LifeTree tree;
  final bool compact;
  final bool? animate;
  final String? selected;
  final Set<String> highlighted;
  final ValueChanged<LifeNode>? onSelect;

  @override
  State<InkTree> createState() => InkTreeState();
}

/// Public so that tests can find where a point was drawn.
class InkTreeState extends State<InkTree> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late _Shape _shape = _Shape.of(widget.tree);
  _Fit? _fit;
  InkSprites? _sprites;

  @override
  void initState() {
    super.initState();
    InkSprites.load().then((sprites) {
      if (mounted) setState(() => _sprites = sprites);
    });
  }

  String? _hovered;

  /// Where point [key] is drawn (local coordinates), or null.
  Offset? positionOf(String key) {
    final fit = _fit;
    final mark = _shape.marks[key];
    return fit == null || mark == null ? null : fit.apply(mark.at);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        !(widget.animate ?? Avatar.animationsEnabled) || MediaQuery.of(context).disableAnimations;
    if (still) {
      _grow.value = 1;
    } else if (_grow.value == 0 && !_grow.isAnimating) {
      _grow.forward();
    }
  }

  @override
  void didUpdateWidget(InkTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tree != widget.tree) _shape = _Shape.of(widget.tree);
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  String? _hit(Offset local) {
    final fit = _fit;
    if (fit == null) return null;
    String? best;
    var bestDistance = 22.0;
    for (final mark in _shape.marks.values) {
      final d = (fit.apply(mark.at) - local).distance;
      if (d < bestDistance) {
        best = mark.node.key;
        bestDistance = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        _fit = _Fit.of(_shape, size, compact: widget.compact);
        final paint = AnimatedBuilder(
          animation: _grow,
          builder: (context, _) => CustomPaint(
            size: size,
            painter: _InkPainter(
              sprites: _sprites,
              shape: _shape,
              fit: _fit!,
              grown: _grow.value,
              compact: widget.compact,
              selected: widget.selected,
              hovered: _hovered,
              highlighted: widget.highlighted,
              labels: (
                goal: theme.labelLarge!.copyWith(color: AppColors.textPrimary),
                course: theme.labelMedium!.copyWith(color: AppColors.textSecondary),
                skill: theme.labelSmall!.copyWith(color: AppColors.textPrimary),
                self: theme.labelMedium!.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        );
        if (widget.compact) return paint;
        return MouseRegion(
          cursor: _hovered == null ? MouseCursor.defer : SystemMouseCursors.click,
          onHover: (e) {
            final hit = _hit(e.localPosition);
            if (hit != _hovered) setState(() => _hovered = hit);
          },
          onExit: (_) => setState(() => _hovered = null),
          child: GestureDetector(
            key: const Key('ink-tree'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              final hit = _hit(e.localPosition);
              final node = hit == null ? null : widget.tree.byKey(hit);
              if (node != null) widget.onSelect?.call(node);
            },
            child: paint,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- shape

/// One limb, branch or twig: a cubic curve, thick at [w0], thin at [w1].
class _Stroke {
  _Stroke(this.a, this.c1, this.c2, this.b, this.w0, this.w1, this.depth, this.start, this.end);

  final Offset a, c1, c2, b;
  final double w0, w1;
  final int depth;

  /// When it grows, as fractions of the whole growth.
  final double start, end;

  Offset at(double t) {
    final u = 1 - t;
    return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t);
  }

  Offset tangent(double t) {
    final u = 1 - t;
    return (c1 - a) * (3 * u * u) + (c2 - c1) * (6 * u * t) + (b - c2) * (3 * t * t);
  }
}

/// A point of the tree: where a node sits, and when it appears.
class _Mark {
  _Mark(this.node, this.at, this.direction, this.depth, this.appear);

  final LifeNode node;
  final Offset at;

  /// The way its branch points (radians from straight up), for its label.
  final double direction;
  final int depth;
  final double appear;
}

/// The tree in its own units: the trunk is 1 long, rising from (0, 0).
class _Shape {
  _Shape(this.strokes, this.marks, this.bounds);

  final List<_Stroke> strokes;
  final Map<String, _Mark> marks;
  final Rect bounds;

  static const double _trunk = 0.72;
  static const double _spread = 1.38; // radians each side of straight up

  static _Shape of(LifeTree tree) {
    final children = <String, List<LifeNode>>{};
    for (final n in tree.nodes.skip(1)) {
      children.putIfAbsent(n.parent ?? LifeTree.selfKey, () => []).add(n);
    }
    final weights = <String, double>{};
    double weigh(LifeNode n) {
      final kids = children[n.key] ?? const [];
      final w = kids.isEmpty ? 1.0 : kids.fold(0.0, (sum, k) => sum + weigh(k));
      return weights[n.key] = w;
    }

    weigh(tree.self);
    final depthOf = <String, int>{};
    final maxDepth = _maxDepth(tree.self.key, children, 0, depthOf);

    final strokes = <_Stroke>[];
    final marks = <String, _Mark>{};
    // Growth timing: depth d grows in its own slice, so the tree rises in order.
    double begin(int depth) => depth == 0 ? 0 : 0.18 + (depth - 1) * (0.62 / math.max(1, maxDepth));
    double finish(int depth) => math.min(1, begin(depth) + 0.3);

    // The trunk, with a slight lean.
    final lean = (_rand(tree.self.key, 1) - 0.5) * 0.08;
    final trunkTop = Offset(math.sin(lean), -math.cos(lean)) * _trunk;
    strokes.add(
      _Stroke(
        Offset.zero,
        Offset(0, -0.35),
        trunkTop + Offset(-math.sin(lean) * 0.3, 0.3),
        trunkTop,
        0.11,
        0.07,
        0,
        begin(0),
        finish(0),
      ),
    );
    marks[tree.self.key] = _Mark(tree.self, Offset.zero, 0, 0, 0);

    void grow(
      LifeNode node,
      _Stroke parent,
      double from, // where along the parent it starts (0–1)
      double angle,
      double length,
      double wedge,
      int depth,
    ) {
      final a = parent.at(from);
      final parentDir = parent.tangent(from);
      final dir = Offset(math.sin(angle), -math.cos(angle));
      final b = a + dir * length;
      final bend = (_rand(node.key, 2) - 0.5) * 0.35 * length;
      final normal = Offset(-dir.dy, dir.dx);
      final out = parentDir.distance == 0 ? dir : parentDir / parentDir.distance;
      final c1 = a + (out * 0.4 + dir * 0.6) * (length * 0.38);
      final c2 = b - dir * (length * 0.32) + normal * bend;
      final w0 = math.max(0.006, parent.w0 * (depth == 1 ? 0.55 : 0.6) * (from > 0.9 ? 0.85 : 1));
      final w1 = math.max(0.004, w0 * 0.5);
      final stroke = _Stroke(a, c1, c2, b, w0, w1, depth, begin(depth), finish(depth));
      strokes.add(stroke);
      marks[node.key] = _Mark(node, b, angle, depth, finish(depth));

      final kids = children[node.key] ?? const [];
      if (kids.isEmpty) return;
      final total = kids.fold(0.0, (sum, k) => sum + math.pow(weights[k.key]!, 0.75));
      var cursor = angle - wedge / 2;
      for (final (i, kid) in kids.indexed) {
        final share = wedge * math.pow(weights[kid.key]!, 0.75) / total;
        final mid = cursor + share / 2;
        cursor += share;
        // Pulled a little back toward straight up, as branches do.
        final childAngle = mid * 0.94 + (_rand(kid.key, 3) - 0.5) * 0.14;
        final leaf = (children[kid.key] ?? const []).isEmpty;
        final childLength =
            length * (leaf ? 0.58 : (depth == 1 ? 0.8 : 0.74)) * (0.88 + _rand(kid.key, 4) * 0.24);
        // Twigs leave along the last part of the branch, not all from its tip.
        final along = kids.length == 1 ? 1.0 : 0.55 + 0.45 * (i + 0.5) / kids.length;
        grow(kid, stroke, along, childAngle, childLength, math.max(share, 0.5) * 0.95, depth + 1);
      }
    }

    final top = children[tree.self.key] ?? const [];
    final trunk = strokes.first;
    if (top.isNotEmpty) {
      final total = top.fold(0.0, (sum, k) => sum + math.pow(weights[k.key]!, 0.75));
      var cursor = -_spread;
      for (final (i, limb) in top.indexed) {
        final share = 2 * _spread * math.pow(weights[limb.key]!, 0.75) / total;
        final mid = cursor + share / 2;
        cursor += share;
        final along = top.length == 1 ? 1.0 : 0.62 + 0.38 * (i + 0.5) / top.length;
        grow(
          limb,
          trunk,
          along,
          mid * 0.92 + lean,
          0.82 * (0.9 + _rand(limb.key, 4) * 0.2),
          share,
          1,
        );
      }
    }

    var bounds = Rect.fromPoints(Offset.zero, trunkTop);
    for (final s in strokes) {
      bounds = bounds.expandToInclude(Rect.fromPoints(s.b, s.b));
      bounds = bounds.expandToInclude(Rect.fromPoints(s.c2, s.c2));
    }
    return _Shape(strokes, marks, bounds);
  }

  static int _maxDepth(
    String key,
    Map<String, List<LifeNode>> children,
    int depth,
    Map<String, int> out,
  ) {
    out[key] = depth;
    var deepest = depth;
    for (final k in children[key] ?? const <LifeNode>[]) {
      deepest = math.max(deepest, _maxDepth(k.key, children, depth + 1, out));
    }
    return deepest;
  }

  /// A stable number in [0, 1) for [key] and [salt] (FNV-1a).
  static double _rand(String key, int salt) {
    var h = 0x811c9dc5 ^ salt;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return (h & 0xffffff) / 0x1000000;
  }
}

/// Unit space → the widget: the trunk's foot centered near the bottom.
class _Fit {
  _Fit(this.scale, this.origin);

  final double scale;
  final Offset origin;

  Offset apply(Offset p) => origin + p * scale;

  static _Fit of(_Shape shape, Size size, {required bool compact}) {
    final pad = compact ? 8.0 : (size.width < 500 ? 16.0 : 48.0);
    final ground = compact ? 8.0 : 56.0; // room under the foot for "You"
    final b = shape.bounds.inflate(0.12);
    final scale = math.min(
      (size.width - 2 * pad) / b.width,
      (size.height - pad - ground) / b.height,
    );
    // Centered in the room left over, so a narrow screen has no empty sky.
    final spare = math.max(0.0, size.height - pad - ground - b.height * scale);
    final origin = Offset(
      size.width / 2 - b.center.dx * scale,
      size.height - ground - spare / 2 - b.bottom * scale,
    );
    return _Fit(math.max(scale, 1), origin);
  }
}

// ---------------------------------------------------------------- paint

typedef _Labels = ({TextStyle goal, TextStyle course, TextStyle skill, TextStyle self});

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.sprites,
    required this.shape,
    required this.fit,
    required this.grown,
    required this.compact,
    required this.selected,
    required this.hovered,
    required this.highlighted,
    required this.labels,
  });

  final _Shape shape;
  final _Fit fit;
  final double grown;
  final bool compact;
  final String? selected;
  final String? hovered;
  final Set<String> highlighted;
  final _Labels labels;

  /// The hand-drawn pieces; until they are loaded, plain marks stand in.
  final InkSprites? sprites;

  static const int _samples = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final s = fit.scale;
    _ground(canvas, s);
    // Thin twigs are pen lines. Thick limbs are outlined as one shape: every
    // body stroked in ink first, then every body filled with paper — the
    // inner seams vanish and only the silhouette stays, like one drawing.
    final thick = <(Path, _Stroke, double)>[];
    for (final stroke in shape.strokes) {
      final p = ((grown - stroke.start) / (stroke.end - stroke.start)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final (body, widest) = _body(stroke, p, s);
      if (compact || widest < 2.4) {
        canvas.drawPath(body, Paint()..color = AppColors.textPrimary.withValues(alpha: 0.86));
      } else {
        thick.add((body, stroke, p));
      }
    }
    final contour = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.6;
    for (final (body, _, _) in thick) {
      canvas.drawPath(body, contour);
    }
    final paper = Paint()..color = AppColors.background;
    for (final (body, _, _) in thick) {
      canvas.drawPath(body, paper);
    }
    for (final (_, stroke, p) in thick) {
      _bark(canvas, stroke, p, s);
    }
    if (!compact) _foliage(canvas);
    for (final mark in shape.marks.values) {
      final p = ((grown - mark.appear) / 0.12).clamp(0.0, 1.0);
      if (p > 0) _mark(canvas, mark, p, s);
    }
    if (!compact) {
      for (final mark in shape.marks.values) {
        if (grown < mark.appear) continue;
        _label(canvas, mark, size);
      }
    }
  }

  /// A few leaves on the limbs and branches — sparse, seeded, in ink.
  void _foliage(Canvas canvas) {
    final leaf = sprites?.leaf;
    if (leaf == null) return;
    for (final (i, stroke) in shape.strokes.indexed) {
      if (stroke.depth < 1 || stroke.depth > 2) continue;
      final t = 0.42 + _Shape._rand('leaf$i', 1) * 0.3;
      if ((grown - stroke.start) / (stroke.end - stroke.start) < t) continue;
      final tan = stroke.tangent(t);
      final heading = math.atan2(tan.dx, -tan.dy);
      final side = i.isEven ? 1 : -1;
      leaf.paint(
        canvas,
        fit.apply(stroke.at(t)),
        size: 22 + _Shape._rand('leaf$i', 2) * 6,
        angle: heading + side * (0.75 + _Shape._rand('leaf$i', 3) * 0.3),
        line: 1,
        tint: AppColors.textPrimary,
      );
    }
  }

  void _ground(Canvas canvas, double s) {
    final foot = fit.apply(Offset.zero);
    final ink = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, s * 0.006);
    final half = s * 0.42 * grown.clamp(0, 0.2) / 0.2;
    canvas.drawLine(foot - Offset(half, 0), foot + Offset(half, 0), ink);
    // A few roots.
    if (grown > 0.05) {
      final r = Paint()
        ..color = AppColors.textPrimary.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, s * 0.012);
      for (final dx in [-0.16, -0.07, 0.09, 0.17]) {
        final path = Path()
          ..moveTo(foot.dx + dx * s * 0.25, foot.dy - 1)
          ..quadraticBezierTo(
            foot.dx + dx * s * 0.7,
            foot.dy + s * 0.01,
            foot.dx + dx * s * 1.1,
            foot.dy + s * 0.035,
          );
        canvas.drawPath(path, r);
      }
    }
  }

  /// The outline of a branch grown to [p], and its widest half-width in px.
  (Path, double) _body(_Stroke stroke, double p, double s) {
    final left = <Offset>[];
    final right = <Offset>[];
    var widest = 0.0;
    for (var i = 0; i <= _samples; i++) {
      final t = p * i / _samples;
      final at = fit.apply(stroke.at(t));
      final tan = stroke.tangent(t);
      final len = tan.distance;
      final n = len == 0 ? const Offset(1, 0) : Offset(-tan.dy / len, tan.dx / len);
      final half = math.max((stroke.w0 + (stroke.w1 - stroke.w0) * t) * s / 2, 0.5);
      widest = math.max(widest, half);
      left.add(at + n * half);
      right.add(at - n * half);
    }
    return (Path()..addPolygon([...left, ...right.reversed], true), widest);
  }

  /// Bark: a few short strokes along the grain, more on the trunk.
  void _bark(Canvas canvas, _Stroke stroke, double p, double s) {
    final bark = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.9;
    final count = stroke.depth == 0 ? 7 : 3;
    for (var k = 0; k < count; k++) {
      final key = '${stroke.a}$k';
      final t0 = 0.08 + _Shape._rand(key, 1) * 0.75;
      if (t0 + 0.1 > p) continue;
      final across = (_Shape._rand(key, 2) - 0.5) * 1.1; // -0.55..0.55 of the width
      final t1 = t0 + 0.06 + _Shape._rand(key, 3) * 0.08;
      Offset point(double t) {
        final tan = stroke.tangent(t);
        final len = tan.distance;
        final n = len == 0 ? const Offset(1, 0) : Offset(-tan.dy / len, tan.dx / len);
        final half = (stroke.w0 + (stroke.w1 - stroke.w0) * t) * s / 2;
        return fit.apply(stroke.at(t)) + n * half * across;
      }

      canvas.drawLine(point(t0), point(t1), bark);
    }
  }

  void _mark(Canvas canvas, _Mark mark, double p, double s) {
    final node = mark.node;
    final at = fit.apply(mark.at);
    final k = Curves.easeOutBack.transform(p);
    final unit = (compact ? 2.2 : 3.2) * k;
    final key = node.key;
    if (key == selected) {
      canvas.drawCircle(at, unit * 4.2, Paint()..color = AppColors.glow.withValues(alpha: 0.55));
    }
    final line = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1 : 1.3;
    switch (node.kind) {
      case LifeKind.self:
        return;
      case LifeKind.goal:
        canvas.drawCircle(at, unit * 1.6, Paint()..color = AppColors.background);
        canvas.drawCircle(at, unit * 1.6, line..strokeWidth = compact ? 1.2 : 1.6);
        canvas.drawCircle(at, unit * 0.55, Paint()..color = AppColors.textPrimary);
      case LifeKind.course:
      case LifeKind.skill:
        final sprites = this.sprites;
        if (sprites != null) {
          final big = node.boss || node.kind == LifeKind.course;
          final z = (compact ? 0.6 : 1.0) * k;
          final line = compact ? 0.9 : 1.2;
          if (node.isMastered) {
            sprites.blossom.paint(
              canvas,
              at,
              size: (big ? 40 : 30) * z,
              angle: mark.direction,
              line: line,
            );
          } else if (node.failed) {
            sprites.leaf.paint(
              canvas,
              at,
              size: 28 * z,
              angle: mark.direction + 0.5,
              line: line,
              tint: AppColors.emberRed,
            );
          } else if (node.isAvailable) {
            sprites.bud.paint(
              canvas,
              at,
              size: (big ? 34 : 28) * z,
              angle: mark.direction,
              line: line,
            );
          } else {
            sprites.closed.paint(canvas, at, size: 22 * z, angle: mark.direction, line: line);
          }
          return;
        }
        if (node.isMastered) {
          _blossom(
            canvas,
            at,
            unit * (node.boss || node.kind == LifeKind.course ? 1.5 : 1.15),
            mark.direction,
          );
        } else if (node.failed) {
          _leaf(canvas, at, unit * 1.3, mark.direction, AppColors.emberRed);
        } else if (node.isAvailable) {
          canvas.drawCircle(at, unit * 1.05, Paint()..color = AppColors.background);
          canvas.drawCircle(at, unit * 1.05, line);
        } else {
          canvas.drawCircle(at, unit * 0.55, Paint()..color = AppColors.textTertiary);
        }
    }
  }

  /// Five line petals around an ember heart.
  void _blossom(Canvas canvas, Offset at, double r, double turn) {
    final petal = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 0.8 : 1.1;
    for (var i = 0; i < 5; i++) {
      final a = turn + i * 2 * math.pi / 5;
      final c = at + Offset(math.sin(a), -math.cos(a)) * r * 0.9;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      final oval = Rect.fromCenter(center: Offset.zero, width: r * 1.05, height: r * 1.6);
      canvas.drawOval(oval, petal);
      canvas.drawOval(oval, edge);
      canvas.restore();
    }
    canvas.drawCircle(at, r * 0.42, Paint()..color = AppColors.ember);
  }

  /// A small pointed leaf.
  void _leaf(Canvas canvas, Offset at, double r, double turn, Color color) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(turn + 0.6);
    final path = Path()
      ..moveTo(0, r * 1.2)
      ..quadraticBezierTo(r * 0.9, 0, 0, -r * 1.2)
      ..quadraticBezierTo(-r * 0.9, 0, 0, r * 1.2)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.8 : 1.1,
    );
    canvas.drawLine(
      Offset(0, r * 1.1),
      Offset(0, -r * 0.9),
      Paint()
        ..color = color
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  void _label(Canvas canvas, _Mark mark, Size size) {
    final node = mark.node;
    final key = node.key;
    final TextStyle style;
    switch (node.kind) {
      case LifeKind.self:
        style = labels.self;
      case LifeKind.goal:
        style = labels.goal;
      case LifeKind.course:
        style = labels.course;
      case LifeKind.skill:
        if (key != hovered && key != selected && !highlighted.contains(key)) return;
        style = labels.skill;
    }
    final text = node.kind == LifeKind.self ? node.label.toUpperCase() : node.label;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 200);
    final at = fit.apply(mark.at);
    final Offset topLeft;
    if (node.kind == LifeKind.self) {
      topLeft = at + Offset(-tp.width / 2, fit.scale * 0.06 + 6);
    } else {
      // Beside the point, on the side its branch leans to.
      final right = math.sin(mark.direction) >= 0;
      final gap = node.kind == LifeKind.goal ? 10.0 : 8.0;
      final x = right ? at.dx + gap : at.dx - gap - tp.width;
      // Never off the edge: a label that would leave the panel comes back in.
      topLeft = Offset(
        x.clamp(4.0, math.max(4.0, size.width - tp.width - 4)),
        at.dy - tp.height / 2,
      );
    }
    // A paper halo keeps the words readable over the lines.
    final halo = Rect.fromLTWH(topLeft.dx - 3, topLeft.dy - 1, tp.width + 6, tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(halo, const Radius.circular(4)),
      Paint()..color = AppColors.background.withValues(alpha: 0.85),
    );
    tp.paint(canvas, topLeft);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      old.grown != grown ||
      old.fit.scale != fit.scale ||
      old.fit.origin != fit.origin ||
      old.shape != shape ||
      old.selected != selected ||
      old.hovered != hovered ||
      old.highlighted != highlighted;
}
