import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/life_tree.dart';
import '../theme/tokens.dart';
import 'avatar.dart';
import '../l10n/l10n.dart';

/// The life tree as a constellation on the night panel (`docs/DESIGN.md` §4):
/// a sphere in 3D. You are its centre; each level of the tree is a shell
/// further out (courses, then their chapters, then their parts), and every
/// branch keeps to its own patch of the sky, so a course is one cluster and
/// its chapters are clusters inside it. A faint wire shell holds it; it turns
/// slowly; cleared nodes burn gold and throw sparks.
///
/// * [compact]: the version inside the crystal ball — no labels, no input.
/// * Drag: turn it any way. Scroll or pinch: zoom, around the pointer; zoomed
///   in, the names of the nodes in front show. [LifeConstellationState.resetView]
///   goes back to the start.
/// * Hover a node: the drift pauses and its name shows. Tap: [onSelect].
/// * [selected] gets a lime ring and its label; [highlighted] (search hits)
///   get their labels.
///
/// Motion stops (final frame, fixed angle) when [animate] is false, when
/// [Avatar.animationsEnabled] is false, or under reduced motion.
/// Where every node of [tree] sits in the unit sphere (you at the centre).
@visibleForTesting
Map<String, ({double x, double y, double z})> lifeSphere(LifeTree tree) => {
  for (final e in _Layout.of(tree, compact: false).pos.entries) e.key: (x: e.value.x, y: e.value.y, z: e.value.z),
};

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

  /// Zoom by [factor] keeping the point under [focal] where it is.
  void zoomBy(double factor, Offset focal) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _clock.zoomAt(factor, focal - box.size.center(Offset.zero));
  }

  /// The view's zoom (1 = the whole sphere fits).
  double get zoom => _clock.zoom;

  /// Zoom around the middle (the buttons).
  void zoomStep(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) zoomBy(factor, box.size.center(Offset.zero));
  }

  /// Back to the starting angle, zoom and place.
  void resetView() => _clock.resetView();

  double _lastScale = 1;

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
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(e, (e) {
            final scroll = (e as PointerScrollEvent).scrollDelta.dy;
            zoomBy(math.exp(-scroll / 400), e.localPosition);
          });
        }
      },
      child: MouseRegion(
        cursor: _hovered == null ? SystemMouseCursors.grab : SystemMouseCursors.click,
        onHover: (e) {
          final h = _hit(e.localPosition);
          if (h != _hovered) setState(() => _hovered = h);
        },
        onExit: (_) => setState(() => _hovered = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onScaleStart: (_) => _lastScale = 1,
          onScaleUpdate: (d) {
            if (d.pointerCount > 1) {
              zoomBy(d.scale / _lastScale, d.localFocalPoint);
              _lastScale = d.scale;
              _clock.pan(d.focalPointDelta);
            } else {
              _clock.turn(d.focalPointDelta.dx / 260, d.focalPointDelta.dy / 260);
            }
          },
          onTapUp: (d) {
            final key = _hit(d.localPosition);
            final node = key == null ? null : widget.tree.byKey(key);
            if (node != null) widget.onSelect!(node);
          },
          child: paint,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Time, the view (rotation, zoom, pan) and glow, shared with the painter.
class _Clock extends ChangeNotifier {
  double t = 0;
  double energy = 0;
  bool still = false;

  /// The sphere's rotation (row-major 3×3): a point p is seen at [rotation]·p.
  List<double> rotation = _start();

  /// 1 = the whole sphere fits; more is closer.
  double zoom = 1;

  /// Where the sphere's centre is moved on screen, in pixels.
  Offset offset = Offset.zero;

  static const double _turnSeconds = 90;
  static const double minZoom = 0.6;
  static const double maxZoom = 6;

  /// Tilted towards you a little, turned a little.
  static List<double> _start() => _mul(_rx(-0.42), _ry(0.6));

  void advance(double dt, {required bool boost, required bool paused}) {
    still = false;
    t += dt;
    energy += ((boost ? 1.0 : 0.0) - energy) * math.min(1, dt * 6);
    if (!paused) {
      // The drift turns it about its own axis, whichever way it is tilted.
      rotation = _mul(rotation, _ry(dt * (2 * math.pi / _turnSeconds) * (1 + 2.5 * energy)));
    }
    notifyListeners();
  }

  /// A drag: sideways turns it about the screen's vertical, up and down about
  /// the horizontal.
  void turn(double yaw, double pitch) {
    rotation = _mul(_mul(_rx(-pitch), _ry(yaw)), rotation);
    notifyListeners();
  }

  void zoomAt(double factor, Offset fromCentre) {
    final next = (zoom * factor).clamp(minZoom, maxZoom);
    final k = next / zoom;
    // The point under the pointer stays under it.
    offset = fromCentre - (fromCentre - offset) * k;
    if (next <= 1) offset = offset * ((next - minZoom) / (1 - minZoom)).clamp(0.0, 1.0);
    zoom = next;
    notifyListeners();
  }

  void pan(Offset delta) {
    offset += delta;
    notifyListeners();
  }

  void resetView() {
    rotation = _start();
    zoom = 1;
    offset = Offset.zero;
    notifyListeners();
  }

  /// The final frame, with no motion; the view stays where the player put it.
  void settle() {
    still = true;
    t = 100;
    energy = 0;
  }

  static List<double> _rx(double a) {
    final c = math.cos(a), s = math.sin(a);
    return [1, 0, 0, 0, c, -s, 0, s, c];
  }

  static List<double> _ry(double a) {
    final c = math.cos(a), s = math.sin(a);
    return [c, 0, s, 0, 1, 0, -s, 0, c];
  }

  static List<double> _mul(List<double> a, List<double> b) => [
    for (var i = 0; i < 3; i++)
      for (var j = 0; j < 3; j++) a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
  ];
}

/// Screen positions of the last frame, for hit testing.
class _Projection {
  final Map<String, Offset> at = {};
}

class _P3 {
  const _P3(this.x, this.y, this.z);
  final double x, y, z;
}

/// 3D positions in a unit sphere, and the wire shell around it.
///
/// Every node owns a cap of the sky (a direction and a half angle); its
/// children share the cap by how many leaves each holds, laid out as a
/// sunflower from its middle, each with a cap of its own. A node sits in the
/// middle of its cap, on the shell of its depth, so the depths are distances
/// from you.
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

  static const double _golden = 2.399963229728653; // π (3 − √5)

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

    // Square-root spacing keeps the outer shells (most nodes) roomy.
    double shell(int d) => d == 0 ? 0.0 : 0.95 * math.sqrt(d / maxDepth);

    final pos = <String, _P3>{};
    void place(String key, _P3 dir, double cap) {
      final d = depth[key]!;
      final r = shell(d);
      pos[key] = _P3(dir.x * r, dir.y * r, dir.z * r);
      final children = kids[key] ?? const <String>[];
      if (children.isEmpty) return;
      final (e1, e2) = _basis(dir);
      // The cap's area, 2π(1 − cos cap), shared by leaves; a little kept free.
      final area = 1 - math.cos(cap);
      final start = _hash(key, 5) * 2 * math.pi;
      var before = 0.0;
      for (final (i, c) in children.indexed) {
        final share = leaves[c]! / leaves[key]!;
        // A lone child stays on the line from its parent; others spread out.
        final rho = children.length == 1 ? 0.0 : math.acos(1 - area * (before + share / 2));
        final psi = start + i * _golden;
        final ca = math.cos(rho), sa = math.sin(rho);
        final cp = math.cos(psi), sp = math.sin(psi);
        final child = _P3(
          ca * dir.x + sa * (cp * e1.x + sp * e2.x),
          ca * dir.y + sa * (cp * e1.y + sp * e2.y),
          ca * dir.z + sa * (cp * e1.z + sp * e2.z),
        );
        final childCap = math.acos((1 - area * share * 0.8).clamp(-1.0, 1.0));
        place(c, child, children.length == 1 ? cap * 0.9 : childCap);
        before += share;
      }
    }

    place(LifeTree.selfKey, const _P3(0, 1, 0), math.pi);

    // The wire shell: points on a sphere, joined to their near neighbours.
    final rng = math.Random(11);
    final n = compact ? 46 : 120;
    final dust = <_P3>[];
    for (var i = 0; i < n; i++) {
      final u = rng.nextDouble() * 2 - 1;
      final th = rng.nextDouble() * 2 * math.pi;
      final rr = 1.02 + rng.nextDouble() * (compact ? 0.08 : 0.22);
      final s = math.sqrt(1 - u * u);
      dust.add(_P3(rr * s * math.cos(th), rr * u, rr * s * math.sin(th)));
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

/// Two unit vectors at right angles to [d] and to each other.
(_P3, _P3) _basis(_P3 d) {
  final a = d.y.abs() < 0.9 ? const _P3(0, 1, 0) : const _P3(1, 0, 0);
  var e1 = _P3(a.y * d.z - a.z * d.y, a.z * d.x - a.x * d.z, a.x * d.y - a.y * d.x);
  final l = math.sqrt(e1.x * e1.x + e1.y * e1.y + e1.z * e1.z);
  e1 = _P3(e1.x / l, e1.y / l, e1.z / l);
  final e2 = _P3(d.y * e1.z - d.z * e1.y, d.z * e1.x - d.x * e1.z, d.x * e1.y - d.y * e1.x);
  return (e1, e2);
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
    final center = size.center(Offset.zero) + (compact ? Offset.zero : clock.offset);
    final zoom = compact ? 1.0 : clock.zoom;
    final radius = (compact ? size.shortestSide * 0.40 : size.shortestSide * 0.42) * zoom;
    final u = (compact ? size.shortestSide / 64 : size.shortestSide * 0.42 / 64) * math.sqrt(zoom);
    const camera = 3.2;
    final m = clock.rotation;

    // (screen point, depth 0 = middle, + = far, scale)
    (Offset, double, double) project(_P3 p) {
      final x = m[0] * p.x + m[1] * p.y + m[2] * p.z;
      final y = m[3] * p.x + m[4] * p.y + m[5] * p.z;
      final depth = m[6] * p.x + m[7] * p.y + m[8] * p.z;
      final k = camera / (camera + depth);
      return (center + Offset(x, -y) * radius * k, depth, k);
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

    // Labels on top: you, courses; skills when hovered, selected or found,
    // and, zoomed in, the ones in front (nearest first, none over another).
    // Courses come before the skills in front; one that would cover another
    // label is left out, unless it was asked for.
    final taken = <Rect>[];
    final front = zoom >= 1.6;
    var named = 0;
    final labelled = [
      ...order.reversed.where((n) => n.kind != LifeKind.skill),
      ...order.reversed.where((n) => n.kind == LifeKind.skill),
    ];
    for (final n in labelled) {
      final hit = projection.at[n.key];
      if (hit == null) continue;
      final (_, depth, k) = proj[n.key]!;
      final asked = n.kind == LifeKind.self ||
          n.key == hovered ||
          n.key == selected ||
          highlighted.contains(n.key);
      final course = n.kind == LifeKind.course;
      final near = front && depth < 0.35 && named < 60 && size.contains(hit);
      if (!asked && !course && !near) continue;
      final f = n.key == hovered || n.key == selected ? 1.0 : fade(depth);
      final style = switch (n.kind) {
        LifeKind.self => titleStyle,
        _ => labelStyle,
      };
      final label = n.kind == LifeKind.self ? l10nNow.you : n.label;
      final tp = TextPainter(
        text: TextSpan(text: label, style: style.copyWith(color: style.color!.withValues(alpha: f))),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 200);
      final at = hit + Offset(u * 2.4 * k, -tp.height / 2);
      final box = (at & tp.size).inflate(2);
      if (!asked && taken.any(box.overlaps)) continue;
      taken.add(box);
      if (!asked && !course) named++;
      tp.paint(canvas, at);
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

  @override
  bool shouldRepaint(_NightPainter old) =>
      old.layout != layout ||
      old.selected != selected ||
      old.hovered != hovered ||
      old.highlighted != highlighted ||
      old.compact != compact;
}
