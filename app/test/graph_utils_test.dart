import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/graph_utils.dart';
import 'package:self_infinity/api/models.dart';

SkillEdge containsEdge(int parent, int child, {bool primary = true}) => SkillEdge(
  fromId: parent,
  toId: child,
  kind: SkillEdgeKind.contains,
  isPrimary: primary,
);

SkillEdge requiresEdge(int from, int to, [String? reason]) =>
    SkillEdge(fromId: from, toId: to, kind: SkillEdgeKind.requires, reason: reason);

/// The 12-node math course of contract Section 4.2 (ids 1–12).
final List<SkillEdge> mathEdges = [
  containsEdge(1, 2),
  containsEdge(1, 3),
  containsEdge(1, 4),
  containsEdge(2, 5),
  containsEdge(5, 6),
  containsEdge(5, 7),
  containsEdge(2, 8),
  containsEdge(3, 9),
  containsEdge(3, 10),
  containsEdge(4, 11),
  containsEdge(8, 11, primary: false),
  containsEdge(4, 12),
  requiresEdge(
    5,
    10,
    'The x-intercepts of a quadratic function are the roots of a quadratic equation.',
  ),
  requiresEdge(9, 10, 'You need the graph of a linear function first.'),
  requiresEdge(11, 12, 'The derivative is defined as a limit.'),
];

SkillNode node(int id) => SkillNode(
  id: id,
  courseId: 1,
  slug: 'n$id',
  title: 'node $id',
  description: '',
  status: SkillStatus.locked,
  nodeType: NodeType.concept,
);

void main() {
  test('positionOf: root, branch and leaf as in contract Section 4.2', () {
    expect(positionOf(1, mathEdges), NodePosition.root);
    for (final id in [2, 3, 4, 5, 8]) {
      expect(positionOf(id, mathEdges), NodePosition.branch, reason: 'node $id');
    }
    for (final id in [6, 7, 9, 10, 11, 12]) {
      expect(positionOf(id, mathEdges), NodePosition.leaf, reason: 'node $id');
    }
  });

  test('positionOf: a node without any contains edge is a root', () {
    expect(positionOf(99, mathEdges), NodePosition.root);
    expect(positionOf(1, const []), NodePosition.root);
  });

  test('requires edges do not influence the position', () {
    expect(positionOf(10, [requiresEdge(5, 10), requiresEdge(10, 11)]), NodePosition.root);
  });

  test('mainParentOf and containsParentsOf put the main parent first', () {
    expect(mainParentOf(1, mathEdges), isNull);
    expect(mainParentOf(5, mathEdges), 2);
    expect(mainParentOf(11, mathEdges), 4);
    expect(containsParentsOf(11, mathEdges), [4, 8]);
    expect(otherParentsOf(11, mathEdges), [8]);
    expect(otherParentsOf(5, mathEdges), isEmpty);
  });

  test('the main parent comes first even when it is listed second', () {
    final edges = [containsEdge(8, 11, primary: false), containsEdge(4, 11)];
    expect(containsParentsOf(11, edges), [4, 8]);
    expect(mainParentOf(11, edges), 4);
  });

  test('without a primary flag the first listed parent is the main one', () {
    final edges = [containsEdge(8, 11, primary: false), containsEdge(4, 11, primary: false)];
    expect(mainParentOf(11, edges), 8);
  });

  test('containsChildren lists a multi-parent child under each parent', () {
    expect(containsChildren(1, mathEdges), [2, 3, 4]);
    expect(containsChildren(4, mathEdges), [11, 12]);
    expect(containsChildren(8, mathEdges), [11]);
    expect(containsChildren(12, mathEdges), isEmpty);
  });

  test('primaryChildren draws every node exactly once', () {
    expect(primaryChildren(4, mathEdges), [11, 12]);
    expect(primaryChildren(8, mathEdges), isEmpty); // 11's main parent is 4
    final all = <int>[];
    for (var id = 1; id <= 12; id++) {
      all.addAll(primaryChildren(id, mathEdges));
    }
    expect(all..sort(), [for (var i = 2; i <= 12; i++) i]);
  });

  test('requiresIn / requiresOut', () {
    expect(requiresIn(10, mathEdges).map((e) => e.fromId), [5, 9]);
    expect(requiresIn(10, mathEdges).first.reason, contains('x-intercepts'));
    expect(requiresOut(5, mathEdges).map((e) => e.toId), [10]);
    expect(requiresOut(10, mathEdges), isEmpty);
    expect(requiresIn(1, mathEdges), isEmpty);
  });

  test('rootNodes keeps the order of the nodes', () {
    final nodes = [for (var i = 1; i <= 12; i++) node(i)];
    expect(rootNodes(nodes, mathEdges).map((n) => n.id), [1]);
    expect(rootNodes(nodes.reversed, mathEdges).map((n) => n.id), [1]);
    expect(rootNodes(nodes, const []).length, 12);
  });

  test('descendantsOf is breadth first and lists each node once', () {
    expect(descendantsOf(1, mathEdges), [2, 3, 4, 5, 8, 9, 10, 11, 12, 6, 7]);
    expect(descendantsOf(4, mathEdges), [11, 12]);
    expect(descendantsOf(12, mathEdges), isEmpty);
  });

  test('mainPathTo and depthOf follow the main parents', () {
    expect(mainPathTo(6, mathEdges), [1, 2, 5, 6]);
    expect(mainPathTo(11, mathEdges), [1, 4, 11]);
    expect(mainPathTo(1, mathEdges), [1]);
    expect(depthOf(1, mathEdges), 0);
    expect(depthOf(6, mathEdges), 3);
    expect(depthOf(11, mathEdges), 2);
  });

  test('a cycle in malformed data does not hang', () {
    final edges = [containsEdge(1, 2), containsEdge(2, 1)];
    expect(mainPathTo(1, edges).length, lessThanOrEqualTo(2));
    expect(descendantsOf(1, edges), [2]);
  });
}
