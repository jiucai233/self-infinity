// Courses of any size: categories left to break down later (`unexpanded`),
// breaking one down from its page, and challenging a whole branch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/test_app.dart';

import '../support/scene_helpers.dart';

/// The `vision` course: 1 Computer Vision, 2 Image Features, 3 Harris Corners,
/// 4 SIFT, 5 Geometric Vision (unexpanded), 6 Visual Recognition (unexpanded).
Future<FakeApiClient> visionApi() async {
  final api = FakeApiClient(latency: Duration.zero);
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

String bubble(WidgetTester tester) =>
    textsIn(tester, find.byKey(const Key('skill-bubble'))).skip(1).join();

Future<VerdictResult> passChallenge(SelfInfinityApi api, int skillId) async {
  final start = await api.startAudit(skillId, testOut: true);
  for (var i = 0; i < 12; i++) {
    final result = await api.submitTurn(start.session.id, longAnswer);
    if (result is VerdictResult) return result;
  }
  throw StateError('The challenge on node $skillId did not end');
}

void main() {
  group('the fake API', () {
    test('a vision course comes in layers; each chapter has its open node', () async {
      final api = await visionApi();
      final nodes = await api.listSkills();
      expect(
        [
          for (final n in nodes)
            if (n.unexpanded) n.title,
        ],
        ['Geometric Vision', 'Visual Recognition'],
      );
      expect(
        [
          for (final n in nodes)
            if (n.isAvailable) n.title,
        ],
        [
          'Harris Corners',
          'Geometric Vision',
          'Visual Recognition',
        ],
      );
    });

    test('breaking a node down gives it three parts; the first one opens', () async {
      final api = await visionApi();
      final map = await api.expandSkill(5);
      final parts = [
        for (final n in map.nodes)
          if (n.id > 6) n,
      ];
      expect(parts.map((n) => n.title), [
        'Geometric Vision 1',
        'Geometric Vision 2',
        'Geometric Vision 3',
      ]);
      expect(parts.map((n) => n.status), [
        SkillStatus.available,
        SkillStatus.locked,
        SkillStatus.locked,
      ]);
      final geometry = map.nodes.firstWhere((n) => n.id == 5);
      expect((geometry.unexpanded, geometry.status), (false, SkillStatus.locked));
      // Again: it is filled in with what it misses. A leaf is broken down further.
      final filled = await api.expandSkill(5);
      expect(filled.nodes.last.title, 'More Geometric Vision');
      final harris = await api.expandSkill(3);
      expect(harris.nodes.where((n) => n.title.startsWith('Harris Corners ')), hasLength(3));
      expect((await failure(() => api.expandSkill(99))).statusCode, 404);
    });

    test(
      'an unexpanded node is broken down or challenged, not audited; a leaf is never challenged',
      () async {
        final api = await visionApi();
        expect((await failure(() => api.startAudit(5))).statusCode, 400);
        expect((await failure(() => api.startAudit(3, testOut: true))).statusCode, 400);
        final start = await api.startAudit(5, testOut: true);
        expect(start.session.testOut, isTrue);
        expect(
          start.openingQuestion,
          'So you already know “Geometric Vision”. Prove it: what are its main parts, '
          'and how does the most important one work?',
        );
      },
    );

    test('a pass on a locked branch clears everything under it', () async {
      final api = await seededFakeApi();
      // Algebra (2) is locked: a challenge is how you skip it.
      final start = await api.startAudit(2, testOut: true);
      expect(
        start.openingQuestion,
        startsWith('So you already know “Algebra”. Prove it, one part at a time.'),
      );
      await api.submitTurn(start.session.id, longAnswer);
      final verdict = await api.submitTurn(start.session.id, longAnswer) as VerdictResult;
      expect(verdict.passed, isTrue);
      final nodes = {for (final n in await api.listSkills()) n.id: n};
      // Quadratic Equations, Discriminant, Roots and Coefficients, Sequences, Limits of Sequences.
      for (final id in [5, 6, 7, 8, 11]) {
        expect(
          (nodes[id]!.status, nodes[id]!.testedOut),
          (SkillStatus.mastered, true),
          reason: '$id',
        );
      }
      expect((nodes[2]!.status, nodes[2]!.testedOut), (SkillStatus.mastered, false));
      expect((await api.listAudits()).first.testOut, isTrue);
      expect((await failure(() => api.startAudit(2, testOut: true))).statusCode, 400);
    });
  });

  group('a node’s page', () {
    testWidgets('an unexpanded node: break it down or challenge it, no →', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 5), api: await visionApi());
      expect(bubble(tester), startsWith('Not broken down yet.'));
      expect(find.byKey(const Key('expand-node')), findsOneWidget);
      expect(find.byKey(const Key('test-out')), findsOneWidget);
      expect(find.byKey(const Key('start-audit')), findsNothing);
    });

    testWidgets('breaking it down reloads the page: its first part is the one to clear', (
      tester,
    ) async {
      await pumpScene(tester, const SkillScene(skillId: 5), api: await visionApi());
      await tester.tap(find.byKey(const Key('expand-node')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expand-node')), findsNothing);
      expect(bubble(tester), 'Still locked. Clear “Geometric Vision 1” first.');
      // Still a branch not cleared: it can still be challenged whole.
      expect(find.byKey(const Key('test-out')), findsOneWidget);
    });

    testWidgets('a break-down that ends after the page closed still reloads the map', (
      tester,
    ) async {
      final api = _SlowExpand();
      await api.generateCourse(const GenerateRequest(topic: 'Computer Vision'));
      final state = AppState();
      await pumpScene(tester, const SkillScene(skillId: 5), api: api, state: state);
      await tester.tap(find.byKey(const Key('expand-node')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox()); // the player went elsewhere
      final revision = state.dataRevision;
      api.done.complete();
      await tester.pumpAndSettle();
      expect(state.dataRevision, revision + 1);
    });

    testWidgets('a failed break-down says so and offers it again', (tester) async {
      final api = await visionApi();
      await pumpScene(tester, const SkillScene(skillId: 5), api: api);
      api.failNext(method: 'expandSkill');
      await tester.tap(find.byKey(const Key('expand-node')));
      await tester.pumpAndSettle();
      expect(bubble(tester), "Couldn't break it down. Try again.");
      expect(find.byKey(const Key('expand-node')), findsOneWidget);
    });

    testWidgets('a locked branch can be challenged: it opens the challenge', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 2), api: await seededFakeApi());
      await tester.tap(find.byKey(const Key('test-out')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/2/audit?challenge=1'), findsOneWidget);
    });

    testWidgets('a leaf or a cleared branch has no challenge', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      expect(find.byKey(const Key('test-out')), findsNothing);
      await passChallenge(api, 2);
      await pumpScene(tester, const SkillScene(skillId: 2), api: api);
      expect(find.byKey(const Key('test-out')), findsNothing);
    });

    testWidgets('a node cleared by a challenge says so', (tester) async {
      final api = await seededFakeApi();
      await passChallenge(api, 2);
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      expect(find.text('Cleared by challenge'), findsOneWidget);
    });
  });

  testWidgets('the challenge scene asks for the whole branch', (tester) async {
    await pumpScene(
      tester,
      const AuditScene(skillId: 2, testOut: true),
      api: await seededFakeApi(),
    );
    expect(find.textContaining('So you already know “Algebra”'), findsWidgets);
    expect(find.text('Challenge'), findsOneWidget);
  });

  testWidgets('the outline marks what is not broken down with +, and explains it', (tester) async {
    await pumpOutline(tester, api: await visionApi());
    expect(find.text('Geometric Vision +'), findsOneWidget);
    expect(find.text('Image Features'), findsOneWidget);
    expect(find.byKey(const Key('legend-unexpanded')), findsOneWidget);
    expect(find.text('Not broken down'), findsOneWidget);
  });
}

/// Its break-down waits for [done].
class _SlowExpand extends FakeApiClient {
  _SlowExpand() : super(latency: Duration.zero);

  final Completer<void> done = Completer<void>();

  @override
  Future<CourseMap> expandSkill(int skillId) async {
    await done.future;
    return super.expandSkill(skillId);
  }
}
