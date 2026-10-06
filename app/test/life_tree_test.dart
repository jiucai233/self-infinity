// The life tree (docs/ux-chat.md §6): you → main quests → courses → nodes.

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

    test('courses hang from their main quest; the others from you', () async {
      final (api, math, writing) = await twoCourses();
      final goal = await api.createGoal('Teach calculus');
      await api.updateGoal(goal.id, courseIds: [math.course.id]);
      final tree = LifeTree.build(goals: await api.listGoals(), maps: [writing, math]);
      final g = tree.byKey('g${goal.id}')!;
      expect(g.parent, LifeTree.selfKey);
      final mathNode = tree.bySkill(math.nodes.first.id)!;
      expect(mathNode.kind, LifeKind.course);
      expect(mathNode.parent, g.key);
      final writingNode = tree.bySkill(writing.nodes.first.id)!;
      expect(writingNode.parent, LifeTree.selfKey);
      // Every node of every course is in the tree, once.
      expect(tree.nodes.where((n) => n.skillId != null).length, math.nodes.length + writing.nodes.length);
      // Parents come before their children.
      final seen = <String>{};
      for (final n in tree.nodes) {
        if (n.parent != null) expect(seen, contains(n.parent));
        seen.add(n.key);
      }
    });

    test('stats over every course; failed means the latest finished audit failed', () async {
      final (api, math, writing) = await twoCourses();
      await passAudit(api, 1);
      await failAudit(api, 2);
      final maps = [await api.getCourseMap(math.course.id), await api.getCourseMap(writing.course.id)];
      final tree = LifeTree.build(maps: maps, audits: await api.listAudits(limit: 100), lessons: 2);
      expect(tree.stats.total, math.nodes.length + writing.nodes.length);
      expect(tree.stats.mastered, 1);
      expect(tree.stats.failed, 1);
      expect(tree.stats.audits, 2);
      expect(tree.stats.lessons, 2);
      expect(tree.bySkill(2)!.failed, isTrue);
      expect(tree.bySkill(1)!.isMastered, isTrue);
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
      await expectLater(api.createGoal('D'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
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

  group('scene 2: the life tree', () {
    testWidgets('numbers on top; tapping a node opens its card with the audit history', (tester) async {
      final (api, _, _) = await twoCourses();
      await passAudit(api, 1); // opens Functions (3)
      await failAudit(api, 3);
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.byKey(const Key('night-panel')), findsOneWidget);
      expect(find.byKey(const Key('stat-strip')), findsOneWidget);
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
      await tester.tapAt(box.localToGlobal(state.positionOf('s3')!));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s3')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('node-sheet-title'))).data, 'Functions');
      expect(find.text('Audit history'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      await tester.tap(find.byKey(const Key('node-sheet-open')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/3'), findsOneWidget);
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
  });
}
