import 'dart:math' as math;
import 'dart:ui';

import '../../api/graph_utils.dart';
import '../../api/models.dart';

/// The label of a node on the graph: its title, ` ↗` when it is another of
/// the player's courses, and ` +` while it is a category not broken down yet
/// (there is more inside).
String graphLabel(SkillNode node) {
  if (node.isLinked) return '${node.title} ↗';
  return node.unexpanded && !node.isMastered ? '${node.title} +' : node.title;
}

/// Where the dots and labels of the skill graph go (scene 2).
///
/// A simple, deterministic layered layout: the column of a node is its depth
/// in the tree of main `contains` parents (left → right); leaves are stacked
/// top → bottom in tree order and a parent sits at the middle of its children.
/// Every node appears exactly once; `contains` and `requires` edges are drawn
/// on top of that (see [GraphEdgeGeometry]).
class GraphLayout {
  GraphLayout._({
    required this.size,
    required this.centers,
    required this.labelWidths,
    required this.depths,
  });

  /// Diameter of a dot.
  static const double dot = 14;

  /// Space between a dot and its label.
  static const double labelGap = 6;

  /// Space between two columns (the arrows run here).
  static const double columnGap = 72;

  /// Distance between two rows.
  static const double rowGap = 44;

  /// Space above and below the drawing.
  static const double margin = 24;

  /// Space left and right of it (arrows that bend back need room on the left).
  static const double hMargin = 44;

  /// Labels are cut off at this width.
  static const double maxLabelWidth = 160;

  /// The whole drawing.
  final Size size;

  /// Center of each node's dot.
  final Map<int, Offset> centers;

  /// Width of each node's label.
  final Map<int, double> labelWidths;

  /// Column of each node.
  final Map<int, int> depths;

  /// Lays out [nodes]; [measure] gives the width of a label (it is cut to
  /// [maxLabelWidth]).
  factory GraphLayout.compute({
    required List<SkillNode> nodes,
    required List<SkillEdge> edges,
    required double Function(String label) measure,
  }) {
    final byId = {for (final n in nodes) n.id: n};
    final y = <int, double>{};
    final depth = <int, int>{};
    var rows = 0;
    final placed = <int>{};

    void place(int id, int d, Set<int> path) {
      placed.add(id);
      depth[id] = d;
      final kids = [
        for (final c in primaryChildren(id, edges))
          if (byId.containsKey(c) && !path.contains(c) && !placed.contains(c)) c,
      ];
      if (kids.isEmpty) {
        y[id] = rows.toDouble();
        rows++;
        return;
      }
      for (final c in kids) {
        place(c, d + 1, {...path, c});
      }
      y[id] = (y[kids.first]! + y[kids.last]!) / 2;
    }

    for (final r in rootNodes(nodes, edges)) {
      place(r.id, 0, {r.id});
    }
    // Nodes only reachable through a cycle: their own rows at the end.
    for (final n in nodes) {
      if (!placed.contains(n.id)) place(n.id, 0, {n.id});
    }

    final labelWidths = <int, double>{
      for (final n in nodes) n.id: math.min(measure(graphLabel(n)), maxLabelWidth),
    };
    final columns = depth.values.fold<int>(0, math.max) + 1;
    final columnWidth = List<double>.filled(columns, 0);
    for (final n in nodes) {
      final d = depth[n.id]!;
      columnWidth[d] = math.max(columnWidth[d], dot + labelGap + labelWidths[n.id]!);
    }
    final columnX = <double>[];
    var x = hMargin;
    for (var d = 0; d < columns; d++) {
      columnX.add(x);
      x += columnWidth[d] + columnGap;
    }
    final width = x - columnGap + hMargin;
    final height = margin * 2 + math.max(0, rows - 1) * rowGap + dot;

    final centers = <int, Offset>{
      for (final n in nodes)
        n.id: Offset(columnX[depth[n.id]!] + dot / 2, margin + dot / 2 + y[n.id]! * rowGap),
    };
    return GraphLayout._(
      size: Size(width, height),
      centers: centers,
      labelWidths: labelWidths,
      depths: depth,
    );
  }

  /// The tappable box of a node: its dot and its label.
  Rect boxOf(int id) {
    final c = centers[id]!;
    return Rect.fromLTWH(
      c.dx - dot / 2 - 4,
      c.dy - 14,
      dot + labelGap + labelWidths[id]! + 8,
      28,
    );
  }
}

/// The curve of one arrow between two laid-out nodes.
class GraphEdgeGeometry {
  const GraphEdgeGeometry({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;

  /// An arrow from [from] to [to]. Forward arrows leave the end of the source
  /// label and enter the target dot from the left; arrows that go back (or stay
  /// in the column) bend around the left side of both dots.
  factory GraphEdgeGeometry.between(GraphLayout layout, int from, int to) {
    const r = GraphLayout.dot / 2;
    final a = layout.centers[from]!;
    final b = layout.centers[to]!;
    final backwards = layout.depths[to]! <= layout.depths[from]!;
    if (backwards) {
      final s = Offset(a.dx - r - 3, a.dy);
      final e = Offset(b.dx - r - 3, b.dy);
      const bend = 34.0;
      return GraphEdgeGeometry(
        start: s,
        control1: Offset(s.dx - bend, s.dy),
        control2: Offset(e.dx - bend, e.dy),
        end: e,
      );
    }
    final s = Offset(a.dx + r + GraphLayout.labelGap + layout.labelWidths[from]! + 4, a.dy);
    final e = Offset(b.dx - r - 3, b.dy);
    final reach = math.max(24.0, (e.dx - s.dx) * 0.5);
    return GraphEdgeGeometry(
      start: s,
      control1: Offset(s.dx + reach, s.dy),
      control2: Offset(e.dx - reach, e.dy),
      end: e,
    );
  }
}
