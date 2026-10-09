// Editing a course by hand from the `⋯` menu of a node page (contract
// #41–#45): rename, add a part, fill in, a course inside a course, a syllabus
// applied to the course, delete a node.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/map/graph_layout.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/upload/file_picker_service.dart';

import '../support/scene_helpers.dart';

/// The math course (1 High School Math, 2 Algebra, 3 Functions, 4 Calculus,
/// 5 Quadratic Equations, 6 Discriminant, …, 11 Limits of Sequences, 12
/// Derivatives) and the vision course (13 Computer Vision, 14 Image Features,
/// 15 Harris Corners, 16 SIFT, 17 Geometric Vision, 18 Visual Recognition).
Future<FakeApiClient> twoCourses() async {
  final api = await seededFakeApi();
  await api.generateCourse(const GenerateRequest(topic: 'Computer Vision'));
  return api;
}

Future<ApiException> failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

String bubble(WidgetTester tester) => textsIn(tester, find.byKey(const Key('skill-bubble'))).skip(1).join();

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('skill-menu')));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key) async {
  await openMenu(tester);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('the fake API', () {
    test('deleting a branch takes what is only under it; a shared part stays', () async {
      final api = await seededFakeApi();
      final map = await api.deleteSkill(4); // Calculus
      final ids = {for (final n in map.nodes) n.id};
      expect(ids.containsAll([4, 12]), isFalse);
      // Limits of Sequences also sits under Sequences: its main parent now.
      expect(ids, contains(11));
      expect(
        map.edges.where((e) => e.toId == 11 && e.kind == SkillEdgeKind.contains).single,
        isA<SkillEdge>().having((e) => (e.fromId, e.isPrimary), 'edge', (8, true)),
      );
      expect((await failure(() => api.deleteSkill(1))).statusCode, 400);
    });

    test('a node is linked to another course; nonsense links are refused', () async {
      final api = await twoCourses();
      expect((await failure(() => api.linkSkill(6, 1))).statusCode, 400); // its own course
      expect((await failure(() => api.linkSkill(2, 2))).statusCode, 400); // it has parts
      expect((await failure(() => api.linkSkill(1, 2))).statusCode, 400); // a root
      final map = await api.linkSkill(6, 2);
      expect(map.nodes.firstWhere((n) => n.id == 6).linkedCourseId, 2);
      // Vision inside math: math cannot go inside vision now.
      expect((await failure(() => api.linkSkill(15, 1))).statusCode, 400);
      expect((await failure(() => api.expandSkill(6))).statusCode, 400);
      final unlinked = await api.linkSkill(6, null);
      expect(unlinked.nodes.firstWhere((n) => n.id == 6).isLinked, isFalse);
    });

    test('a course and the node that is it are cleared together', () async {
      final api = await twoCourses();
      await api.linkSkill(6, 2);
      final start = await api.startAudit(13, testOut: true);
      for (var i = 0; i < 12; i++) {
        if (await api.submitTurn(start.session.id, longAnswer) is VerdictResult) break;
      }
      final math = await api.getCourseMap(1);
      expect(math.nodes.firstWhere((n) => n.id == 6).isMastered, isTrue);
    });

    test('a syllabus adds a part per file, or one when searched', () async {
      final api = await seededFakeApi();
      final file = await api.uploadFile(filename: 'Probability.txt', bytes: utf8.encode('Probability'));
      final map = await api.applySyllabus(1, uploadIds: [file.id]);
      expect(map.nodes.last.title, 'Probability');
      expect((await api.applySyllabus(1)).nodes.last.title, 'High School Math in Practice');
    });
  });

  group('the ⋯ menu of a node page', () {
    testWidgets('a branch: every edit; the root: no delete and no link', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 2), api: await seededFakeApi());
      await openMenu(tester);
      for (final key in ['skill-edit', 'skill-add-part', 'skill-fill-in', 'skill-syllabus', 'skill-delete-node']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.text('Fill in what\'s missing'), findsOneWidget);
      expect(find.byKey(const Key('skill-link')), findsNothing); // it has parts

      await pumpScene(tester, const SkillScene(skillId: 1), api: await seededFakeApi());
      await openMenu(tester);
      expect(find.byKey(const Key('skill-delete-node')), findsNothing);
      expect(find.byKey(const Key('skill-link')), findsNothing);
    });

    testWidgets('a leaf is broken down further', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 6), api: await seededFakeApi());
      await openMenu(tester);
      expect(find.text('Break it down further'), findsOneWidget);
      expect(find.byKey(const Key('skill-link')), findsOneWidget);
    });

    testWidgets('renaming changes the title', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      await choose(tester, 'skill-edit');
      await tester.enterText(find.byKey(const Key('node-title')), 'The Discriminant');
      await tester.tap(find.byKey(const Key('node-text-save')));
      await tester.pumpAndSettle();
      expect(find.text('The Discriminant'), findsWidgets);
      expect((await api.getCourseMap(1)).nodes.firstWhere((n) => n.id == 6).title, 'The Discriminant');
    });

    testWidgets('a part is added under the node', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const SkillScene(skillId: 3), api: api);
      await choose(tester, 'skill-add-part');
      expect(find.text('Add a part under “Functions”'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('node-title')), 'Exponential Functions');
      await tester.tap(find.byKey(const Key('node-text-save')));
      await tester.pumpAndSettle();
      expect((await api.getCourseMap(1)).nodes.last.title, 'Exponential Functions');
    });

    testWidgets('deleting the node asks, then goes back to the map', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const SkillScene(skillId: 4), api: api);
      await choose(tester, 'skill-delete-node');
      expect(find.text('Delete “Calculus”?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('node-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('route:/map'), findsOneWidget);
      expect((await api.getCourseMap(1)).nodes.any((n) => n.id == 4), isFalse);
    });

    testWidgets('a node made a course says so and opens it; it is not audited', (tester) async {
      final api = await twoCourses();
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      await choose(tester, 'skill-link');
      await tester.tap(find.byKey(const Key('node-link-course-2')));
      await tester.pumpAndSettle();

      expect(bubble(tester), 'This is your course “Computer Vision”.');
      expect(find.byKey(const Key('start-audit')), findsNothing);
      expect(find.byKey(const Key('test-out')), findsNothing);
      await tester.tap(find.byKey(const Key('open-linked-course')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/13'), findsOneWidget);
    });

    testWidgets('a syllabus searched for: the bubble says what it added', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 2), api: await seededFakeApi());
      await choose(tester, 'skill-syllabus');
      await tester.tap(find.byKey(const Key('node-syllabus-search')));
      await tester.pumpAndSettle();
      expect(bubble(tester), '1 part added.');
    });

    testWidgets('a syllabus uploaded; none found says so', (tester) async {
      final api = await seededFakeApi();
      final picker = FakeFilePicker()..next = PickedFile(name: 'Probability.md', bytes: utf8.encode('# Probability'));
      await pumpScene(tester, const SkillScene(skillId: 2), api: api, picker: picker);
      await choose(tester, 'skill-syllabus');
      await tester.tap(find.byKey(const Key('node-syllabus-upload')));
      await tester.pumpAndSettle();
      expect(bubble(tester), '1 part added.');
      expect((await api.getCourseMap(1)).nodes.last.title, 'Probability');

      api.failNext(method: 'applySyllabus', statusCode: 404);
      await choose(tester, 'skill-syllabus');
      await tester.tap(find.byKey(const Key('node-syllabus-search')));
      await tester.pumpAndSettle();
      expect(bubble(tester), 'No syllabus found. Try uploading one.');
    });
  });

  test('the graph marks a node that is another course with ↗', () {
    const node = SkillNode(
      id: 1,
      courseId: 1,
      slug: 'cv',
      title: 'Computer Vision',
      description: '',
      status: SkillStatus.locked,
      nodeType: NodeType.concept,
      linkedCourseId: 2,
    );
    expect(graphLabel(node), 'Computer Vision ↗');
  });
}
