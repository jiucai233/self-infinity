import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/graph_utils.dart';
import '../../api/models.dart';
import '../../theme/tokens.dart';
import 'graph_layout.dart';
import '../../l10n/l10n.dart';

/// How a dot of the skill graph is colored (`docs/DESIGN.md` Section 3).
enum DotKind {
  /// Cleared: green.
  mastered,

  /// The newest audit failed and the node is not cleared: red.
  failed,

  /// Can be challenged: white with a blue ring.
  available,

  /// Locked: light grey.
  locked,
}

/// The node-link graph of one course: small circles with the title to the
/// right and thin arrows for `contains` and `requires` edges. Pan and zoom
/// with the mouse, the trackpad or two fingers.
class SkillGraphView extends StatefulWidget {
  const SkillGraphView({
    super.key,
    required this.map,
    required this.failed,
    required this.highlighted,
    required this.onOpen,
  });

  final CourseMap map;

  /// Nodes whose newest audit failed (shown red unless cleared).
  final Set<int> failed;

  /// Nodes that match the search text.
  final Set<int> highlighted;

  /// A node was tapped.
  final ValueChanged<int> onOpen;

  /// The dot color of [node].
  static DotKind kindOf(SkillNode node, Set<int> failed) {
    if (node.isMastered) return DotKind.mastered;
    if (failed.contains(node.id)) return DotKind.failed;
    return node.isLocked ? DotKind.locked : DotKind.available;
  }

  @override
  State<SkillGraphView> createState() => _SkillGraphViewState();
}

class _SkillGraphViewState extends State<SkillGraphView> {
  final TransformationController _transform = TransformationController();
  GraphLayout? _layout;
  Set<int> _bosses = const {};
  CourseMap? _laidOut;
  TextStyle? _labelStyle;
  Size? _fittedFor;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  double _measure(String text, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  /// Centers the drawing. A small graph is enlarged a little (at most 1.4x), a
  /// large one shrunk, but never below 0.8 (the text stays readable; on a phone
  /// the rest is reached by panning).
  void _fit(Size viewport, Size content) {
    final fit = math.min(viewport.width / content.width, viewport.height / content.height);
    final scale = fit.clamp(0.8, 1.4);
    final dx = math.max(0.0, (viewport.width - content.width * scale) / 2);
    final dy = math.max(0.0, (viewport.height - content.height * scale) / 2);
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    _labelStyle = theme.bodySmall?.copyWith(color: AppColors.textPrimary);
    final scaler = MediaQuery.textScalerOf(context);
    if (_laidOut != widget.map) {
      _laidOut = widget.map;
      _layout = GraphLayout.compute(
        nodes: widget.map.nodes,
        edges: widget.map.edges,
        measure: (t) => _measure(t, scaler),
      );
      _bosses = bossIds(widget.map.nodes, widget.map.edges);
      _fittedFor = null;
    }
    final layout = _layout!;
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = Size(box.maxWidth, box.maxHeight);
        if (_fittedFor != viewport) {
          _fittedFor = viewport;
          _fit(viewport, layout.size);
        }
        return ClipRect(
          child: InteractiveViewer(
            key: const Key('graph-viewer'),
            transformationController: _transform,
            constrained: false,
            minScale: 0.3,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(240),
            child: SizedBox(
              key: const Key('graph-content'),
              width: layout.size.width,
              height: layout.size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EdgePainter(layout: layout, edges: widget.map.edges),
                    ),
                  ),
                  for (final n in widget.map.nodes)
                    Positioned.fromRect(
                      rect: layout.boxOf(n.id),
                      child: _GraphNode(
                        key: Key('node-${n.id}'),
                        node: n,
                        kind: SkillGraphView.kindOf(n, widget.failed),
                        boss: _bosses.contains(n.id),
                        highlighted: widget.highlighted.contains(n.id),
                        labelStyle: _labelStyle,
                        onTap: () => widget.onOpen(n.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphNode extends StatelessWidget {
  const _GraphNode({
    super.key,
    required this.node,
    required this.kind,
    required this.boss,
    required this.highlighted,
    required this.labelStyle,
    required this.onTap,
  });

  final SkillNode node;
  final DotKind kind;
  final bool boss;
  final bool highlighted;
  final TextStyle? labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = kind == DotKind.locked;
    return Semantics(
      button: true,
      label: node.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: highlighted ? AppColors.surfaceHigh : Colors.transparent,
              borderRadius: AppRadius.chipBorder,
            ),
            child: Row(
              children: [
                const SizedBox(width: 4),
                DotMark(key: Key('dot-${node.id}'), kind: kind, boss: boss),
                const SizedBox(width: GraphLayout.labelGap),
                Expanded(
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: labelStyle?.copyWith(
                      color: locked ? AppColors.textTertiary : AppColors.textPrimary,
                      fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin arrows: `contains` (parent → child) solid, `requires` (learned first →
/// after) dashed.
class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.layout, required this.edges});

  final GraphLayout layout;
  final List<SkillEdge> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.requires
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final head = Paint()..color = AppColors.requires;
    for (final e in edges) {
      if (!layout.centers.containsKey(e.fromId) || !layout.centers.containsKey(e.toId)) continue;
      final g = GraphEdgeGeometry.between(layout, e.fromId, e.toId);
      final path = Path()
        ..moveTo(g.start.dx, g.start.dy)
        ..cubicTo(g.control1.dx, g.control1.dy, g.control2.dx, g.control2.dy, g.end.dx, g.end.dy);
      canvas.drawPath(e.isRequires ? _dashed(path) : path, line);
      _arrowHead(canvas, g, head);
    }
  }

  void _arrowHead(Canvas canvas, GraphEdgeGeometry g, Paint paint) {
    final dir = g.end - g.control2;
    final angle = math.atan2(dir.dy, dir.dx);
    const len = 7.0;
    const spread = 0.45;
    final p1 = g.end - Offset(math.cos(angle - spread), math.sin(angle - spread)) * len;
    final p2 = g.end - Offset(math.cos(angle + spread), math.sin(angle + spread)) * len;
    canvas.drawPath(
      Path()
        ..moveTo(g.end.dx, g.end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  Path _dashed(Path source) {
    const dash = 5.0;
    const gap = 4.0;
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        out.addPath(metric.extractPath(at, math.min(at + dash, metric.length)), Offset.zero);
        at += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.layout != layout || old.edges != edges;
}

/// The legend at the bottom left of scene 2: the four kinds of dot with their
/// names (`docs/ux-chat.md` 5.11) and, last, the double ring of a `Boss`
/// (`docs/ux-chat.md` 6.2).
class GraphLegend extends StatelessWidget {
  const GraphLegend({super.key});

  /// The legend's entries, in order.
  static List<(DotKind, String)> entries(AppLocalizations l) => [
    (DotKind.available, l.dotReady),
    (DotKind.mastered, l.dotCleared),
    (DotKind.failed, l.auditFailed),
    (DotKind.locked, l.dotLocked),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final entries = GraphLegend.entries(context.l10n);
    final rows = <Widget>[
      for (final e in entries)
        _legendRow(theme, DotMark(key: Key('legend-dot-${e.$1.name}'), kind: e.$1), e.$2),
      _legendRow(
        theme,
        const DotMark(
          key: Key('legend-dot-boss'),
          kind: DotKind.available,
          boss: true,
          color: AppColors.textSecondary,
        ),
        context.l10n.boss,
      ),
    ];
    return DecoratedBox(
      key: const Key('graph-legend'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
                child: rows[i],
              ),
          ],
        ),
      ),
    );
  }
}

Widget _legendRow(TextTheme theme, Widget dot, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(
      width: GraphLayout.dot + 6,
      child: Center(child: dot),
    ),
    const SizedBox(width: AppSpacing.sm),
    Text(label, style: theme.bodySmall),
  ],
);

/// A node's dot: the fill and ring of [kind]. A [boss] gets a second ring: it
/// is drawn a little larger, outer ring, a gap, then an inner ring (or disc)
/// in the same color. It paints outside its [size] box so that the layout
/// does not move; [color] overrides the colors of [kind] (the legend's
/// neutral boss).
class DotMark extends StatelessWidget {
  const DotMark({
    super.key,
    required this.kind,
    this.size = GraphLayout.dot,
    this.boss = false,
    this.color,
  });

  final DotKind kind;
  final double size;
  final bool boss;
  final Color? color;

  /// How much larger than [size] a boss dot is.
  static const double bossExtra = 6;

  /// Fill and ring colors of a dot kind.
  static (Color, Color) colorsOf(DotKind kind) => switch (kind) {
    DotKind.mastered => (AppColors.success, AppColors.success),
    DotKind.failed => (AppColors.danger, AppColors.danger),
    DotKind.available => (AppColors.surface, AppColors.primary),
    DotKind.locked => (AppColors.locked, AppColors.locked),
  };

  @override
  Widget build(BuildContext context) {
    var (fill, ring) = colorsOf(kind);
    if (color != null) ring = color!;
    if (!boss) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 2),
        ),
      );
    }
    // Double ring: outer ring, a 2 px gap, inner ring around the fill.
    final outer = size + bossExtra;
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        minWidth: outer,
        maxWidth: outer,
        minHeight: outer,
        maxHeight: outer,
        child: Container(
          key: const Key('boss-ring'),
          width: outer,
          height: outer,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.5),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
