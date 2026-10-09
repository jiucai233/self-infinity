// The life tree (docs/ux-chat.md §6): you → main quests → courses → nodes.

import 'dart:math' as m;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/life_tree.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/widgets/life_constellation.dart';

import 'support/scene_helpers.dart';

Future<(FakeApiClient, CourseMap, CourseMap)> twoCourses() async {
  final api = FakeApiClient(latency: Duration.zero);
  final math = await api.generateCourse(const GenerateRequest(topic: 'math'));
  final writing = await api.generateCourse(const GenerateRequest(topic: 'Writing'));
  return (api, math, writing);
}

void main() {
  group('LifeTree.build', () {
    test('only you when there is nothing else', () {
      final tree = LifeTree.build();
      expect(tree.isEmpty, isTrue);
      expect(tree.self.kind, LifeKind.self);
      expect(tree.stats.total, 0);
      expect(tree.stats.percent, 0);
    });

    test('every course hangs from you and remembers its main quest', () async {
      final (api, math, writing) = await twoCourses();
      final goal = await api.createGoal('Teach calculus');
      await api.updateGoal(goal.id, courseIds: [math.course.id]);
      final tree = LifeTree.build(goals: await api.listGoals(), maps: [writing, math]);
      // The quest itself is not a point of the tree.
      expect(tree.byKey('g${goal.id}'), isNull);
      final mathNode = tree.bySkill(math.nodes.first.id)!;
      expect(mathNode.kind, LifeKind.course);
      expect((mathNode.parent, mathNode.goalId), (LifeTree.selfKey, goal.id));
      final writingNode = tree.bySkill(writing.nodes.first.id)!;
      expect((writingNode.parent, writingNode.goalId), (LifeTree.selfKey, null));
      // Every node of every course is in the tree, once.
      expect(
        tree.nodes.where((n) => n.skillId != null).length,
        math.nodes.length + writing.nodes.length,
      );
      // Parents come before their children.
      final seen = <String>{};
      for (final n in tree.nodes) {
        if (n.parent != null) expect(seen, contains(n.parent));
        seen.add(n.key);
      }
    });

    test('stats over every course; failed means the latest finished audit failed', () async {
      final (api, math, writing) = await twoCourses();
      await passAudit(api, 6); // Discriminant, the first of the order
      await failAudit(api, 7); // Roots and Coefficients, the next
      final maps = [
        await api.getCourseMap(math.course.id),
        await api.getCourseMap(writing.course.id),
      ];
      final tree = LifeTree.build(maps: maps, audits: await api.listAudits(limit: 100), lessons: 2);
      expect(tree.stats.total, math.nodes.length + writing.nodes.length);
      expect(tree.stats.mastered, 1);
      expect(tree.stats.failed, 1);
      expect(tree.stats.audits, 2);
      expect(tree.stats.lessons, 2);
      expect(tree.bySkill(7)!.failed, isTrue);
      expect(tree.bySkill(6)!.isMastered, isTrue);
      expect(tree.bySkill(6)!.boss, isFalse); // a leaf
      expect(tree.bySkill(1)!.boss, isTrue);
    });
  });

  group('goals (Fake, endpoints 28–31)', () {
    test('at most three; a course belongs to one goal; delete frees it', () async {
      final (api, math, writing) = await twoCourses();
      final a = await api.createGoal('  A  ');
      expect(a.title, 'A');
      final b = await api.createGoal('B');
      await api.createGoal('C');
      await expectLater(
        api.createGoal('D'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      await api.updateGoal(a.id, courseIds: [math.course.id, writing.course.id]);
      await api.updateGoal(b.id, courseIds: [writing.course.id]);
      final goals = {for (final g in await api.listGoals()) g.id: g.courseIds};
      expect(goals[a.id], [math.course.id]);
      expect(goals[b.id], [writing.course.id]);
      await api.deleteGoal(b.id);
      expect((await api.listGoals()).map((g) => g.id), isNot(contains(b.id)));
      await expectLater(api.updateGoal(99, title: 'x'), throwsA(isA<ApiException>()));
      await expectLater(api.createGoal('   '), throwsA(isA<ApiException>()));
    });
  });

  group('a course inside another', () {
    test('grows from the node that is it, not from you', () async {
      final (api, math, writing) = await twoCourses();
      await api.linkSkill(6, writing.course.id); // Discriminant is the writing course
      final tree = LifeTree.build(maps: [await api.getCourseMap(writing.course.id), await api.getCourseMap(1)]);
      final writingRoot = tree.bySkill(writing.nodes.first.id)!;
      expect((writingRoot.kind, writingRoot.parent), (LifeKind.course, 's6'));
      // Parents still come before their children.
      final seen = <String>{};
      for (final n in tree.nodes) {
        if (n.parent != null) expect(seen, contains(n.parent));
        seen.add(n.key);
      }
      expect(tree.depths['s${writing.nodes.first.id}'], tree.depths['s6']! + 1);
      expect(math.nodes, isNotEmpty);
    });
  });

  group('the sphere', () {
    double dist(({double x, double y, double z}) a, [({double x, double y, double z})? b]) {
      final o = b ?? (x: 0.0, y: 0.0, z: 0.0);
      return m.sqrt(m.pow(a.x - o.x, 2) + m.pow(a.y - o.y, 2) + m.pow(a.z - o.z, 2));
    }

    test('each level is a shell further out; a course keeps to its own patch', () async {
      final (_, math, writing) = await twoCourses();
      final tree = LifeTree.build(maps: [math, writing]);
      final at = lifeSphere(tree);
      final depths = tree.depths;
      expect(dist(at[LifeTree.selfKey]!), 0);
      for (final n in tree.nodes.skip(1)) {
        final parent = at[n.parent]!;
        expect(dist(at[n.key]!), greaterThan(dist(parent) - 1e-9), reason: n.label);
        // Same depth, same distance from you.
        final peer = tree.nodes.firstWhere((o) => depths[o.key] == depths[n.key]);
        expect(dist(at[n.key]!), closeTo(dist(at[peer.key]!), 1e-9));
      }
      // Not a flat disc: the nodes spread in all three directions.
      final ys = [for (final p in at.values) p.y];
      expect(ys.reduce(m.max) - ys.reduce(m.min), greaterThan(0.5));
      // The math leaves are nearer each other than the writing ones.
      final mathLeaves = [for (final n in tree.skillsOf(math.course.id)) at[n.key]!];
      final writingLeaves = [for (final n in tree.skillsOf(writing.course.id)) at[n.key]!];
      double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      final inside = mean([for (final a in mathLeaves) for (final b in mathLeaves) dist(a, b)]);
      final across = mean([for (final a in mathLeaves) for (final b in writingLeaves) dist(a, b)]);
      expect(inside, lessThan(across));
    });

    testWidgets('it turns any way, zooms by scroll and buttons, and goes back', (tester) async {
      final (api, _, _) = await twoCourses();
      await pumpScene(tester, const MapScene(), api: api);
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final centre = tester.getCenter(find.byType(LifeConstellation));
      final before = state.positionOf('s6')!;

      await tester.dragFrom(centre, const Offset(0, 120));
      await tester.pump();
      expect((state.positionOf('s6')! - before).distance, greaterThan(5));

      tester.binding.handlePointerEvent(PointerScrollEvent(position: centre, scrollDelta: const Offset(0, -400)));
      await tester.pump();
      expect(state.zoom, closeTo(m.e, 0.01));

      await tester.tap(find.byKey(const Key('zoom-out')));
      await tester.pump();
      expect(state.zoom, closeTo(m.e / 1.5, 0.01));
      await tester.tap(find.byKey(const Key('zoom-reset')));
      await tester.pump();
      expect(state.zoom, 1);
      expect((state.positionOf('s6')! - before).distance, lessThan(0.5));
    });
  });

  group('scene 2: the life tree', () {
    testWidgets('numbers on top; tapping a node opens its card with the audit history', (
      tester,
    ) async {
      final (api, _, _) = await twoCourses();
      await passAudit(api, 6); // opens Roots and Coefficients (7)
      await failAudit(api, 7);
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.byKey(const Key('night-panel')), findsOneWidget);
      expect(find.byKey(const Key('stat-strip')), findsOneWidget);
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
      await tester.tapAt(box.localToGlobal(state.positionOf('s7')!));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s7')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('node-sheet-title'))).data,
        'Roots and Coefficients',
      );
      expect(find.text('Audit history'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      await tester.tap(find.byKey(const Key('node-sheet-open')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/7'), findsOneWidget);
    });

    testWidgets('a course card moves the course under a main quest', (tester) async {
      final (api, math, _) = await twoCourses();
      await api.createGoal('Teach calculus');
      await pumpScene(tester, const MapScene(), api: api);
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
      await tester.tapAt(box.localToGlobal(state.positionOf('s${math.nodes.first.id}')!));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('course-goal'))).data, 'Side quest');
      await tester.tap(find.byKey(const Key('course-goal-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teach calculus').last);
      await tester.pumpAndSettle();
      expect((await api.listGoals()).single.courseIds, [math.course.id]);
      expect(tester.widget<Text>(find.byKey(const Key('course-goal'))).data, 'Teach calculus');
    });

    Future<void> openCourse(WidgetTester tester, CourseMap course) async {
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
      await tester.tapAt(box.localToGlobal(state.positionOf('s${course.nodes.first.id}')!));
      await tester.pumpAndSettle();
    }

    testWidgets('deleting a course asks first; unchecked, its history is kept', (tester) async {
      final (api, math, writing) = await twoCourses();
      await failAudit(api, 6);
      await pumpScene(tester, const MapScene(), api: api);
      await openCourse(tester, math);

      await tester.tap(find.byKey(const Key('course-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete “High School Math”?'), findsOneWidget);
      expect(
        find.text('Also delete its ${math.nodes.length} nodes, their attempts and lesson cards'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await api.listCourses(), hasLength(2));

      await tester.tap(find.byKey(const Key('course-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-delete-confirm')));
      await tester.pumpAndSettle();
      expect((await api.listCourses()).single.id, writing.course.id);
      expect(find.byKey(Key('node-sheet-s${math.nodes.first.id}')), findsNothing);
      expect(await api.listAudits(), hasLength(1)); // kept
    });

    testWidgets('checked, the nodes and their history go too', (tester) async {
      final (api, math, _) = await twoCourses();
      await failAudit(api, 6);
      await pumpScene(tester, const MapScene(), api: api);
      await openCourse(tester, math);

      await tester.tap(find.byKey(const Key('course-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-delete-nodes')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('course-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await api.listCourses(), hasLength(1));
      expect(await api.listAudits(), isEmpty);
    });
  });
}
