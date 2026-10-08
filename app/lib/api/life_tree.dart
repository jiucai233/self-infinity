/// The life tree (`docs/ux-chat.md` §6): you in the middle, your courses
/// around you and every node of those courses beyond that. Main quests are
/// not points on it — they live on the character sheet; a course only
/// remembers the quest it serves ([LifeNode.goalId]).
///
/// Pure data, built on the client from endpoints that already exist; no API of
/// its own.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'graph_utils.dart';
import 'models.dart';

enum LifeKind { self, course, skill }

/// One point of the life tree.
@immutable
class LifeNode {
  const LifeNode({
    required this.key,
    required this.kind,
    required this.label,
    this.parent,
    this.goalId,
    this.courseId,
    this.skillId,
    this.status,
    this.failed = false,
    this.boss = false,
    this.unexpanded = false,
  });

  /// `me`, `c{id}` (a course with several roots), `s{id}`.
  final String key;
  final LifeKind kind;
  final String label;

  /// The key of the node it hangs from; null for `me`.
  final String? parent;

  final int? goalId;
  final int? courseId;

  /// Set for skills, and for a course whose single root stands for it.
  final int? skillId;
  final SkillStatus? status;

  /// The newest finished audit failed and the node is not mastered.
  final bool failed;

  /// A root or branch of its course (see [isBoss]).
  final bool boss;

  /// A category not broken down yet ([SkillNode.unexpanded]).
  final bool unexpanded;

  bool get isMastered => status == SkillStatus.mastered;
  bool get isAvailable => status == SkillStatus.available;
  bool get isLocked => status == SkillStatus.locked;
}

/// Progress over all courses.
@immutable
class LifeStats {
  const LifeStats({
    required this.total,
    required this.mastered,
    required this.ready,
    required this.failed,
    required this.audits,
    required this.lessons,
  });

  static const LifeStats empty = LifeStats(
    total: 0,
    mastered: 0,
    ready: 0,
    failed: 0,
    audits: 0,
    lessons: 0,
  );

  /// Skill nodes of every course.
  final int total;
  final int mastered;
  final int ready;
  final int failed;

  /// Finished audits.
  final int audits;

  /// Lesson cards.
  final int lessons;

  /// 0..1.
  double get progress => total == 0 ? 0 : mastered / total;

  /// Whole percent, rounded down (12 of 12 is 100, 11 of 12 is 91).
  int get percent => (progress * 100).floor();
}

@immutable
class LifeTree {
  const LifeTree._(this.nodes, this.stats);

  /// Every node, `me` first, then breadth first (parents before children).
  final List<LifeNode> nodes;
  final LifeStats stats;

  static const String selfKey = 'me';

  LifeNode get self => nodes.first;

  LifeNode? byKey(String key) => nodes.where((n) => n.key == key).firstOrNull;

  LifeNode? bySkill(int skillId) => nodes.where((n) => n.skillId == skillId).firstOrNull;

  List<LifeNode> childrenOf(String key) => [
    for (final n in nodes)
      if (n.parent == key) n,
  ];

  /// The skill nodes of one course (its course node included when it is a
  /// root skill).
  List<LifeNode> skillsOf(int courseId) => [
    for (final n in nodes)
      if (n.courseId == courseId && n.skillId != null) n,
  ];

  /// Whether there is anything besides you.
  bool get isEmpty => nodes.length == 1;

  /// Builds the tree. [maps] in any order (courses are shown oldest first,
  /// so new ones land at the end of the ring); [audits] newest first.
  factory LifeTree.build({
    String selfLabel = 'You',
    List<Goal> goals = const [],
    List<CourseMap> maps = const [],
    List<AuditSummary> audits = const [],
    int lessons = 0,
  }) {
    final nodes = <LifeNode>[
      LifeNode(key: selfKey, kind: LifeKind.self, label: selfLabel.isEmpty ? 'You' : selfLabel),
    ];
    final failed = _failedSkills(maps, audits);
    final sorted = [...maps]..sort((a, b) => a.course.id.compareTo(b.course.id));
    final known = {for (final m in sorted) m.course.id};
    final owner = <int, Goal>{};
    for (final g in goals) {
      for (final c in g.courseIds) {
        if (known.contains(c)) owner.putIfAbsent(c, () => g);
      }
    }

    for (final map in sorted) {
      _addCourse(nodes, map, selfKey, owner[map.course.id]?.id, failed);
    }

    var total = 0;
    var mastered = 0;
    var ready = 0;
    for (final m in sorted) {
      for (final n in m.nodes) {
        total++;
        if (n.isMastered) mastered++;
        if (n.isAvailable) ready++;
      }
    }
    return LifeTree._(
      List.unmodifiable(nodes),
      LifeStats(
        total: total,
        mastered: mastered,
        ready: ready,
        failed: failed.length,
        audits: audits.where((a) => a.status != AuditStatus.active).length,
        lessons: lessons,
      ),
    );
  }

  static void _addCourse(
    List<LifeNode> out,
    CourseMap map,
    String parentKey,
    int? goalId,
    Set<int> failed,
  ) {
    final byId = {for (final n in map.nodes) n.id: n};
    final roots = rootNodes(map.nodes, map.edges);
    if (roots.isEmpty) return;
    final placed = <int>{};

    LifeNode skill(SkillNode n, String parent, LifeKind kind) => LifeNode(
      key: 's${n.id}',
      kind: kind,
      label: n.title,
      parent: parent,
      goalId: goalId,
      courseId: map.course.id,
      skillId: n.id,
      status: n.status,
      failed: failed.contains(n.id),
      boss: isBoss(n, map.edges),
      unexpanded: n.unexpanded && !n.isMastered,
    );

    // Breadth first, along primary contains edges; a node with several
    // parents is placed once, under the first.
    final queue = <(int, String)>[];
    final courseKey = roots.length == 1 ? 's${roots.single.id}' : 'c${map.course.id}';
    if (roots.length == 1) {
      out.add(skill(roots.single, parentKey, LifeKind.course));
      placed.add(roots.single.id);
      queue.add((roots.single.id, 's${roots.single.id}'));
    } else {
      final hub = 'c${map.course.id}';
      out.add(
        LifeNode(
          key: hub,
          kind: LifeKind.course,
          label: map.course.title,
          parent: parentKey,
          goalId: goalId,
          courseId: map.course.id,
          boss: true,
        ),
      );
      for (final r in roots) {
        out.add(skill(r, hub, LifeKind.skill));
        placed.add(r.id);
        queue.add((r.id, 's${r.id}'));
      }
    }
    while (queue.isNotEmpty) {
      final (id, key) = queue.removeAt(0);
      for (final c in primaryChildren(id, map.edges)) {
        final child = byId[c];
        if (child == null || !placed.add(c)) continue;
        out.add(skill(child, key, LifeKind.skill));
        queue.add((c, 's$c'));
      }
    }
    // Nodes no contains edge reaches (should not happen) still count.
    for (final n in map.nodes) {
      if (placed.add(n.id)) out.add(skill(n, courseKey, LifeKind.skill));
    }
  }

  /// Skills whose newest finished audit failed and that are not mastered.
  static Set<int> _failedSkills(List<CourseMap> maps, List<AuditSummary> audits) {
    final byId = {
      for (final m in maps)
        for (final n in m.nodes) n.id: n,
    };
    final seen = <int>{};
    final out = <int>{};
    for (final a in audits) {
      if (a.status == AuditStatus.active || !seen.add(a.skillId)) continue;
      final n = byId[a.skillId];
      if (n != null && !n.isMastered && a.status == AuditStatus.failed) out.add(a.skillId);
    }
    return out;
  }

  /// Depth of every node (`me` = 0).
  Map<String, int> get depths {
    final d = <String, int>{selfKey: 0};
    for (final n in nodes.skip(1)) {
      d[n.key] = (d[n.parent] ?? 0) + 1;
    }
    return d;
  }

  int get maxDepth => depths.values.fold(0, math.max);
}
