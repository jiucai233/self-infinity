/// Pure helpers over the contains/requires edges of a course
/// (`docs/api-contract.md`, "Node position" in Section 2).
///
/// All functions take the full edge list of a course (as returned by
/// `getCourseMap`) and return plain ids or edges. They never mutate their
/// arguments and are cheap enough to call per node for the ≤ 30 nodes of a
/// course.
///
/// Terminology
/// * *contains* edge: `fromId` is the parent group, `toId` the child.
///   A node can have several contains parents; exactly one is the *main*
///   parent (`isPrimary == true`) and the node is drawn inside it.
/// * *requires* edge: `fromId` is learned first, `toId` after.
library;

import 'models.dart';

/// All contains-parents of [nodeId], the main parent first, then the others
/// in edge order. Empty for a root.
///
/// If the server flags no parent as primary, the first listed parent counts as
/// the main one.
List<int> containsParentsOf(int nodeId, List<SkillEdge> edges) {
  final parents = <int>[];
  int? primary;
  for (final e in edges) {
    if (!e.isContains || e.toId != nodeId) continue;
    if (!parents.contains(e.fromId)) parents.add(e.fromId);
    if (e.isPrimary == true) primary ??= e.fromId;
  }
  if (primary != null) {
    parents
      ..remove(primary)
      ..insert(0, primary);
  }
  return parents;
}

/// The main (primary) contains-parent of [nodeId], or null for a root.
int? mainParentOf(int nodeId, List<SkillEdge> edges) {
  final parents = containsParentsOf(nodeId, edges);
  return parents.isEmpty ? null : parents.first;
}

/// The contains-parents of [nodeId] other than the main one — the
/// `Also under` badge of a multi-parent node.
List<int> otherParentsOf(int nodeId, List<SkillEdge> edges) =>
    containsParentsOf(nodeId, edges).skip(1).toList();

/// All contains-children of [nodeId], in edge order. A multi-parent child is
/// listed under each of its parents (use this for the outline).
List<int> containsChildren(int nodeId, List<SkillEdge> edges) {
  final children = <int>[];
  for (final e in edges) {
    if (e.isContains && e.fromId == nodeId && !children.contains(e.toId)) {
      children.add(e.toId);
    }
  }
  return children;
}

/// The children whose **main** parent is [nodeId] — the tree in which every
/// node appears exactly once (use this to draw the learning map).
List<int> primaryChildren(int nodeId, List<SkillEdge> edges) => [
  for (final c in containsChildren(nodeId, edges))
    if (mainParentOf(c, edges) == nodeId) c,
];

/// Position of a node, per the contract: no contains parent → root; a contains
/// parent but no contains child → leaf; otherwise branch. A category not
/// broken down yet ([unexpanded]) has no children but is a branch.
NodePosition positionOf(int nodeId, List<SkillEdge> edges, {bool unexpanded = false}) {
  var hasParent = false;
  var hasChild = false;
  for (final e in edges) {
    if (!e.isContains) continue;
    if (e.toId == nodeId) hasParent = true;
    if (e.fromId == nodeId) hasChild = true;
  }
  if (!hasParent) return NodePosition.root;
  return hasChild || unexpanded ? NodePosition.branch : NodePosition.leaf;
}

/// Whether [node] is a **boss** of the game layer (contract Section 6): a
/// root or a branch, i.e. anything but a leaf.
bool isBoss(SkillNode node, List<SkillEdge> edges) =>
    positionOf(node.id, edges, unexpanded: node.unexpanded) != NodePosition.leaf;

/// The ids of the bosses among [nodes] (see [isBoss]).
Set<int> bossIds(Iterable<SkillNode> nodes, List<SkillEdge> edges) => {
  for (final n in nodes)
    if (isBoss(n, edges)) n.id,
};

/// The chapter [nodeId] belongs to: the root's child above it along main
/// parents (itself for a chapter); null for the root.
int? chapterOf(int nodeId, List<SkillEdge> edges) {
  var current = nodeId;
  final seen = {nodeId};
  while (true) {
    final parent = mainParentOf(current, edges);
    if (parent == null) return current == nodeId ? null : current;
    if (mainParentOf(parent, edges) == null) return current;
    if (!seen.add(parent)) return current;
    current = parent;
  }
}

/// The nodes without a contains-parent, in the order of [nodes].
List<SkillNode> rootNodes(Iterable<SkillNode> nodes, List<SkillEdge> edges) {
  final children = <int>{
    for (final e in edges)
      if (e.isContains) e.toId,
  };
  return [
    for (final n in nodes)
      if (!children.contains(n.id)) n,
  ];
}

/// The course's learning order, the list laid over its tree (the server's
/// `services/tree.py`): what a node contains comes before it, so the root
/// comes last; a requires edge puts its prerequisite first; otherwise the
/// lower id (the planner's order) goes first. Each chapter ([chapterOf]) opens
/// its first node in it that is not mastered; the root comes last.
List<int> learningOrder(Iterable<SkillNode> nodes, List<SkillEdge> edges) {
  final ids = {for (final n in nodes) n.id};
  final before = {for (final id in ids) id: <int>{}};
  for (final e in edges) {
    if (!ids.contains(e.fromId) || !ids.contains(e.toId)) continue;
    if (e.isContains) {
      before[e.fromId]!.add(e.toId);
    } else {
      before[e.toId]!.add(e.fromId);
    }
  }
  final order = <int>[];
  final left = {...ids};
  while (left.isNotEmpty) {
    final ready = [
      for (final id in left)
        if (!before[id]!.any(left.contains)) id,
    ];
    // A requires edge running against the tree can close a loop; the lowest id breaks it.
    final pick = (ready.isEmpty ? left : ready).reduce((a, b) => a < b ? a : b);
    order.add(pick);
    left.remove(pick);
  }
  return order;
}

/// Every node reachable from [nodeId] through contains edges (excluding
/// [nodeId] itself), breadth first, each id once.
List<int> descendantsOf(int nodeId, List<SkillEdge> edges) {
  final seen = <int>{nodeId};
  final order = <int>[];
  final queue = <int>[nodeId];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final child in containsChildren(current, edges)) {
      if (seen.add(child)) {
        order.add(child);
        queue.add(child);
      }
    }
  }
  return order;
}

/// The chain of main parents from the root down to [nodeId], both included.
List<int> mainPathTo(int nodeId, List<SkillEdge> edges) {
  final path = <int>[nodeId];
  var current = nodeId;
  while (true) {
    final parent = mainParentOf(current, edges);
    if (parent == null || path.contains(parent)) break; // root reached (or a cycle)
    path.insert(0, parent);
    current = parent;
  }
  return path;
}

/// Depth of [nodeId] in the main-parent tree. A root has depth 0.
int depthOf(int nodeId, List<SkillEdge> edges) => mainPathTo(nodeId, edges).length - 1;

/// `requires` edges that **point at** [nodeId]: its prerequisites
/// (`fromId` must be learned first).
List<SkillEdge> requiresIn(int nodeId, List<SkillEdge> edges) => [
  for (final e in edges)
    if (e.isRequires && e.toId == nodeId) e,
];

/// `requires` edges that **leave** [nodeId]: the nodes that need it
/// (`toId` is learned after).
List<SkillEdge> requiresOut(int nodeId, List<SkillEdge> edges) => [
  for (final e in edges)
    if (e.isRequires && e.fromId == nodeId) e,
];
