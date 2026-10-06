// FakeApiClient: the offline script (contract Section 4) and the state rules
// of the real backend, for the endpoints the stage UI uses.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/graph_utils.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/testing/test_app.dart';

FakeApiClient newApi({DateTime Function()? clock}) =>
    FakeApiClient(latency: Duration.zero, clock: clock);

Future<SkillNode> nodeOf(FakeApiClient api, String title) async =>
    (await api.listSkills()).firstWhere((n) => n.title == title);

Future<int> idOf(FakeApiClient api, String title) async => (await nodeOf(api, title)).id;

Future<List<String>> titlesWhere(FakeApiClient api, SkillStatus status) async => [
  for (final n in await api.listSkills())
    if (n.status == status) n.title,
];

Future<ApiException> failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

/// A text of exactly [n] characters that contains neither `don't know` nor `not sure`.
String text(int n) => 'a' * n;

/// Plays the first answer (always a probe) and then [second]; returns the result of the latter.
Future<TurnResult> playTwoAnswers(
  FakeApiClient api,
  int sessionId,
  String first,
  String second,
) async {
  final probe = await api.submitTurn(sessionId, first);
  expect(probe, isA<ProbeResult>(), reason: 'the first answer always gets a probe');
  return api.submitTurn(sessionId, second);
}

void main() {
  group('courses', () {
    test(
      'the settings do not change the math course; no syllabus without searchSyllabus',
      () async {
        final api = newApi();
        final map = await api.generateCourse(
          const GenerateRequest(
            topic: 'math',
            nodeCount: 4,
            maxDepth: 2,
            difficulty: Difficulty.intro,
            searchSyllabus: false,
          ),
        );
        expect(map.nodes, hasLength(12));
        expect(map.course.sourceCourse, isNull);
        expect(map.course.sourceUrl, isNull);
      },
    );

    test('any other topic gets the generic course without a syllabus', () async {
      final api = newApi();
      final map = await api.generateCourse(const GenerateRequest(topic: 'Python Programming'));
      expect(map.nodes.map((n) => n.title).toList(), [
        'Python Programming', 'Core Concepts', 'Key Methods', 'Applications', //
        'Core Concepts 1',
        'Core Concepts 2',
        'Key Methods 1',
        'Key Methods 2',
        'Applications 1',
        'Applications 2',
      ]);
      expect(map.course.sourceCourse, isNull);
      expect(map.course.sourceUrl, isNull);
      expect(map.nodes.first.status, SkillStatus.available);
      expect(map.nodes.skip(1).every((n) => n.status == SkillStatus.locked), isTrue);
      final byTitle = {for (final n in map.nodes) n.title: n.id};
      expect(
        map.edges.where((e) => e.isRequires).map((e) => (e.fromId, e.toId)).toList(),
        [
          (byTitle['Core Concepts 1'], byTitle['Key Methods 1']),
          (byTitle['Key Methods 1'], byTitle['Applications 1']),
        ],
      );
      expect(positionOf(byTitle['Core Concepts']!, map.edges), NodePosition.branch);
      expect(positionOf(byTitle['Core Concepts 1']!, map.edges), NodePosition.leaf);
    });

    test('the generic root is the first line of the topic, cut at a word boundary', () async {
      final api = newApi();
      final map = await api.generateCourse(
        const GenerateRequest(
          topic: 'A very long topic name that is well over twenty-four characters\n\nQ: Which?\nA: This one',
        ),
      );
      // At most 48 characters, never mid-word ("…well over twenty-four" is 52).
      expect(map.nodes.first.title, 'A very long topic name that is well over');
      expect(map.course.topic, contains('Q: Which?'));
      expect(map.course.title, startsWith('A very long topic'));
    });

    test('a second course continues the ids; courses are listed newest first', () async {
      final api = newApi();
      final first = await api.generateCourse(const GenerateRequest(topic: 'math'));
      final second = await api.generateCourse(const GenerateRequest(topic: 'statistics'));
      expect(second.course.id, first.course.id + 1);
      expect(second.nodes.first.id, 13);
      expect((await api.listCourses()).map((c) => c.id), [second.course.id, first.course.id]);
      expect(await api.listSkills(), hasLength(22));
      expect(await api.listSkills(courseId: first.course.id), hasLength(12));
      expect(await api.listSkills(courseId: second.course.id), hasLength(10));
      expect(await api.listSkills(courseId: 99), isEmpty);

      final map = await api.getCourseMap(second.course.id);
      expect(map.course.id, second.course.id);
      expect(map.nodes, hasLength(10));
      expect(map.edges.every((e) => e.fromId >= 13 && e.toId >= 13), isTrue);
      final e = await failure(() => api.getCourseMap(99));
      expect(e.statusCode, 404);
      expect(e.serverMessage, 'course not found');
    });

    test('a second math course gets its own ids and wires its edges to them', () async {
      final api = await seededFakeApi();
      final second = await api.generateCourse(const GenerateRequest(topic: 'University math'));
      expect(second.nodes.map((n) => n.id).toList(), [for (var i = 13; i <= 24; i++) i]);
      expect(second.nodes.first.status, SkillStatus.available);
      expect(second.edges.every((e) => e.fromId >= 13 && e.toId >= 13), isTrue);
      expect(containsParentsOf(23, second.edges), [
        16,
        20,
      ]); // Limits of Sequences: Calculus, Sequences
      expect(requiresIn(22, second.edges).map((e) => e.fromId), [
        17,
        21,
      ]); // Quadratic Functions needs Quadratic Equations, Linear Functions
      // Both courses are independent: passing the first root opens nothing in the second.
      await passAudit(api, 1);
      expect(
        (await api.listSkills(courseId: second.course.id)).where((n) => n.isAvailable),
        hasLength(1),
      );
    });

    test('settings are validated like the server does (422)', () async {
      final api = newApi();
      for (final bad in const [
        GenerateRequest(topic: '   '),
        GenerateRequest(topic: 'x', nodeCount: 3),
        GenerateRequest(topic: 'x', nodeCount: 31),
        GenerateRequest(topic: 'x', maxDepth: 1),
        GenerateRequest(topic: 'x', maxDepth: 7),
      ]) {
        expect((await failure(() => api.generateCourse(bad))).statusCode, 422);
      }
      expect(await api.listCourses(), isEmpty);
      // The boundaries are fine.
      await api.generateCourse(const GenerateRequest(topic: 'x', nodeCount: 4, maxDepth: 2));
      await api.generateCourse(const GenerateRequest(topic: 'x', nodeCount: 30, maxDepth: 6));
    });
  });

  group('audits', () {
    test('opening questions by position and node type', () async {
      final api = await seededFakeApi();
      final root = await api.startAudit(1);
      expect(
        root.openingQuestion,
        'Which problems call for “High School Math”, and which don\'t? How do you decide?',
      );
      expect(root.session.nodePosition, NodePosition.root);
      expect(root.session.status, AuditStatus.active);
      expect(root.session.score, isNull);
      expect(root.session.gaps, isEmpty);
      expect(root.session.comment, isNull);
      expect(root.session.turns, hasLength(1));
      expect(root.session.turns.single.role, AuditRole.auditor);
      expect(root.session.turns.single.content, root.openingQuestion);

      await passAudit(api, 1);
      await passAudit(api, 2);
      final branch = await api.startAudit(2);
      expect(branch.session.nodePosition, NodePosition.branch);
      expect(
        branch.openingQuestion,
        '“Algebra” covers Quadratic Equations, Sequences. Why do these belong together, and when do you use which?',
      );

      await passAudit(api, 5);
      final leaf = await api.startAudit(6);
      expect(leaf.session.nodePosition, NodePosition.leaf);
      expect(
        leaf.openingQuestion,
        'Explain “Discriminant” from scratch to someone who has never heard of it.',
      );

      api.debugSetNodeType(6, NodeType.task);
      final task = await api.startAudit(6);
      expect(task.openingQuestion, 'How exactly will you do “Discriminant”?');
    });

    test('audits are allowed on available and mastered nodes, not on locked ones', () async {
      final api = await seededFakeApi();
      final locked = await failure(() => api.startAudit(2));
      expect(locked.statusCode, 400);
      expect(locked.serverMessage, 'skill is locked');
      expect((await failure(() => api.startAudit(99))).statusCode, 404);
      expect((await failure(() => api.startAudit(99))).serverMessage, 'skill not found');
      expect((await failure(() => api.startAudit(1, mode: 'dusk'))).statusCode, 422);

      await api.startAudit(1); // available
      await passAudit(api, 1);
      await api.startAudit(1, mode: 'night'); // mastered again: still allowed
    });

    test('turn limits: concept 8, task 4, night doubles', () async {
      final api = await seededFakeApi();
      final day = await api.startAudit(1);
      final night = await api.startAudit(1, mode: 'night');
      expect(api.debugMaxTurns(day.session.id), 8);
      expect(api.debugMaxTurns(night.session.id), 16);
      api.debugSetNodeType(1, NodeType.task);
      final taskDay = await api.startAudit(1);
      final taskNight = await api.startAudit(1, mode: 'night');
      expect(api.debugMaxTurns(taskDay.session.id), 4);
      expect(api.debugMaxTurns(taskNight.session.id), 8);
    });

    test('the first answer always gets a probe, even a long one', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      final r = await api.submitTurn(s.session.id, longAnswer) as ProbeResult;
      expect(
        r.question,
        'Pick the most important term in your explanation and tell me what it means and why it matters.',
      );
    });

    test('a short answer fails with the scripted gaps and comment', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      final r = await playTwoAnswers(api, s.session.id, text(10), text(20)) as VerdictResult;
      expect(r.passed, isFalse);
      expect(r.score, 45);
      expect(r.gaps, [
        'You stated the definition but not why it works.',
        "You didn't cover the exceptions.",
      ]);
      expect(r.comment, 'The answer stops at the conclusion and lacks reasons.');
      expect((await nodeOf(api, 'High School Math')).status, SkillStatus.available);
      expect((await nodeOf(api, 'High School Math')).masteryScore, isNull);
    });

    test('"don\'t know" in the latest answer fails even a long answer', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      final r = await playTwoAnswers(
        api,
        s.session.id,
        longAnswer,
        "$longAnswer But honestly I don't know this one",
      ) as VerdictResult;
      expect(r.passed, isFalse);
    });

    test('a long answer passes at once: score = min(95, 70 + n ~/ 10)', () async {
      final api = await seededFakeApi();
      // n = 100 + 1 (joiner) + 100 = 201 → 70 + 20
      final s = await api.startAudit(1);
      final r = await playTwoAnswers(api, s.session.id, text(100), text(100)) as VerdictResult;
      expect(r.passed, isTrue);
      expect(r.score, 90);
      expect(r.gaps, isEmpty);
      expect(r.comment, 'You explained the core idea and why it holds.');
      final node = await nodeOf(api, 'High School Math');
      expect(node.status, SkillStatus.mastered);
      expect(node.masteryScore, 90);

      // The score is capped at 95.
      final capped = await passAudit(api, 1);
      expect(capped.score, 95);
    });

    test('a medium answer is challenged once and then passes', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      // n = 50 + 1 + 50 = 101: passes the Auditor (≥ 80) but is below 160.
      final challenge = await playTwoAnswers(api, s.session.id, text(50), text(50)) as ProbeResult;
      expect(
        challenge.question,
        'Before I pass this: give one case where this idea does not hold, and explain why.',
      );
      expect((await nodeOf(api, 'High School Math')).status, SkillStatus.available);

      // n = 101 + 1 + 30 = 132 → still < 160, but the Challenger acts at most once.
      final verdict = await api.submitTurn(s.session.id, text(30)) as VerdictResult;
      expect(verdict.passed, isTrue);
      expect(verdict.score, 70 + 132 ~/ 10);
      expect((await nodeOf(api, 'High School Math')).status, SkillStatus.mastered);
    });

    test('after a Challenger probe the final answer can still fail', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      await playTwoAnswers(api, s.session.id, text(50), text(50));
      final verdict = await api.submitTurn(s.session.id, "I'm not sure") as VerdictResult;
      expect(verdict.passed, isFalse);
      expect(verdict.score, 45);
    });

    test('a pass that is not challenged also happens when the total reaches 160', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      // n = 79 → fail
      final fail1 = await playTwoAnswers(api, s.session.id, text(39), text(39)) as VerdictResult;
      expect(fail1.passed, isFalse);
      // n = 80 → pass candidate, but < 160 → Challenger.
      final s2 = await api.startAudit(1);
      expect(await playTwoAnswers(api, s2.session.id, text(39), text(40)), isA<ProbeResult>());
      // n = 160 → passes at once.
      final s3 = await api.startAudit(1);
      final pass = await playTwoAnswers(api, s3.session.id, text(80), text(79)) as VerdictResult;
      expect(pass.passed, isTrue);
      expect(pass.score, 86);
    });

    test('the turn limit turns a probe into a failing verdict with score 0', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      api.debugSetMaxTurns(s.session.id, 2);
      // Second answer would be challenged (n = 101) but the limit of 2 is reached.
      final verdict = await playTwoAnswers(api, s.session.id, text(50), text(50)) as VerdictResult;
      expect(verdict.passed, isFalse);
      expect(verdict.score, 0);
      expect(verdict.gaps, isNotEmpty);
      expect((await nodeOf(api, 'High School Math')).status, SkillStatus.available);
      // A reflection is accepted for it.
      final p = await api.submitReflection(s.session.id, 'I ran out of turns');
      expect(p.misconception, 'I ran out of turns');
    });

    test('closed or unknown sessions and blank answers are rejected', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      await playTwoAnswers(api, s.session.id, text(10), text(10)); // fails → closed
      final closed = await failure(() => api.submitTurn(s.session.id, 'again'));
      expect(closed.statusCode, 400);
      expect(closed.serverMessage, 'audit session is already closed');

      final missing = await failure(() => api.submitTurn(999, 'x'));
      expect(missing.statusCode, 404);
      expect(missing.serverMessage, 'audit session not found');

      final s2 = await api.startAudit(1);
      expect((await failure(() => api.submitTurn(s2.session.id, '   '))).statusCode, 422);
      // The blank answer left no trace: the first real answer still gets the probe.
      expect(await api.submitTurn(s2.session.id, text(10)), isA<ProbeResult>());
    });

    test('unlocking: any mastered contains parent opens a locked child', () async {
      final api = await seededFakeApi();
      await passAudit(api, 1);
      await passAudit(api, 2); // Algebra → Quadratic Equations (5), Sequences (8)
      // Limits of Sequences (11) has the parents Calculus (4) and Sequences (8).
      expect((await nodeOf(api, 'Limits of Sequences')).status, SkillStatus.locked);
      final viaSequences = await passAudit(api, 8);
      expect(viaSequences.unlockedSkillIds, [11]);
      expect((await nodeOf(api, 'Limits of Sequences')).status, SkillStatus.available);
      // Passing the other parent later unlocks only what is still locked.
      final viaCalculus = await passAudit(api, 4);
      expect(viaCalculus.unlockedSkillIds, [12]);
      // requires edges never block: Quadratic Functions (10) needs Quadratic Equations but opens with Functions.
      final viaFunctions = await passAudit(api, 3);
      expect(viaFunctions.unlockedSkillIds, [9, 10]);
      // Passing a leaf unlocks nothing; passing a mastered node again unlocks nothing.
      expect((await passAudit(api, 9)).unlockedSkillIds, isEmpty);
      expect((await passAudit(api, 1)).unlockedSkillIds, isEmpty);
    });

    test('reward: base 10 × difficulty × level multiplier, only on a pass', () async {
      final api = await seededFakeApi();
      final root = await passAudit(api, 1);
      // concept (2.0) × depth 0 (1.0) × 1.1^1 × 10
      expect(root.rewardMultiplier, 1.1);
      expect(root.rewardAmount, 22);
      final algebra = await passAudit(api, 2);
      // concept × (1 + 0.5 × 1) × 1.1^1 × 10 = 33
      expect(algebra.rewardAmount, 33);
      final failed = await failAudit(api, 3);
      expect(failed.verdict.rewardAmount, isNull);
      expect(failed.verdict.rewardMultiplier, isNull);
      // The multiplier grows with the number of mastered nodes (level = mastered ~/ 5 + 1).
      await passAudit(api, 3);
      await passAudit(api, 4);
      final fifth = await passAudit(api, 5);
      expect(fifth.rewardMultiplier, 1.21);
    });
  });

  group('reflection', () {
    test('only for a failed audit and only once', () async {
      final api = await seededFakeApi();
      final active = await api.startAudit(1);
      final notFailed = await failure(() => api.submitReflection(active.session.id, 'x'));
      expect(notFailed.statusCode, 400);
      expect(notFailed.serverMessage, 'reflection is only accepted for a failed audit');

      final passed = await api.startAudit(1);
      await playTwoAnswers(api, passed.session.id, longAnswer, longAnswer);
      final afterPass = await failure(() => api.submitReflection(passed.session.id, 'x'));
      expect(afterPass.serverMessage, 'reflection is only accepted for a failed audit');

      final failed = await failAudit(api, 1);
      await api.submitReflection(failed.sessionId, 'I could not give the reason');
      final twice = await failure(() => api.submitReflection(failed.sessionId, 'again'));
      expect(twice.statusCode, 400);
      expect(twice.serverMessage, 'reflection already submitted for this audit');

      expect((await failure(() => api.submitReflection(999, 'x'))).statusCode, 404);
      final failed2 = await failAudit(api, 1);
      expect((await failure(() => api.submitReflection(failed2.sessionId, '  '))).statusCode, 422);
      await api.submitReflection(
        failed2.sessionId,
        'I will write it this time',
      ); // still possible after the 422
    });

    test('the Recorder cuts title to 40, body to 120 and misconception to 60 characters', () async {
      final api = newApi();
      await api.generateCourse(
        const GenerateRequest(
          topic: 'An introductory course in a really quite remarkably complicated and difficult field of study',
        ),
      );
      // The root title is cut at a word boundary (40 here); the “Revisit …” wrapper is longer than 40.
      final root = (await api.listSkills()).first;
      expect(root.title, 'An introductory course in a really quite');
      final failed = await failAudit(api, root.id);
      final p = await api.submitReflection(failed.sessionId, 'b' * 80);
      expect(p.title.runes.length, lessThanOrEqualTo(40));
      expect('Revisit “${root.title}”', startsWith(p.title)); // cut, not reworded
      expect(p.body.runes.length, lessThanOrEqualTo(120));
      expect(p.misconception, 'b' * 60);
    });
  });

  group('Memory Retriever', () {
    Future<FakeApiClient> mathWithOpenNodes() async {
      final api = await seededFakeApi();
      for (final id in [1, 2, 4]) {
        await passAudit(api, id); // opens 2,3,4 / 5,8 / 11,12
      }
      return api;
    }

    Future<Principle> lesson(FakeApiClient api, int skillId, String misconception) async {
      final failed = await failAudit(api, skillId);
      return api.submitReflection(failed.sessionId, misconception);
    }

    Future<String> firstProbe(FakeApiClient api, int skillId) async {
      final s = await api.startAudit(skillId);
      return (await api.submitTurn(s.session.id, longAnswer) as ProbeResult).question;
    }

    test('names the most recent lesson of the node itself', () async {
      final api = await mathWithOpenNodes();
      await lesson(api, 5, 'an old misconception');
      await lesson(api, 5, 'a recent misconception');
      final probe = await firstProbe(api, 5);
      expect(probe, contains('a recent misconception'));
      expect(probe, isNot(contains('an old')));
    });

    test('takes at most three lessons, most recent first', () async {
      final api = await mathWithOpenNodes();
      for (final m in [
        'alpha misconception',
        'bravo misconception',
        'charlie misconception',
        'delta misconception',
      ]) {
        await lesson(api, 5, m);
      }
      // The newest of the four is named; the retriever never needs more than 3.
      expect(await firstProbe(api, 5), contains('delta misconception'));
    });

    test('a lesson from a direct contains neighbour is found', () async {
      final api = await mathWithOpenNodes();
      await lesson(api, 5, 'a misconception from the parent node');
      // Quadratic Equations (5) is the contains parent of Discriminant (6) — which is still locked,
      // so audit Sequences (8) whose neighbours are Algebra (2) and Limits of Sequences (11) instead.
      await passAudit(api, 5);
      expect(await firstProbe(api, 6), contains('a misconception from the parent node'));
    });

    test('a lesson from an unrelated node is not found', () async {
      final api = await mathWithOpenNodes();
      await lesson(api, 12, 'a misconception only in Derivatives');
      final probe = await firstProbe(api, 8);
      expect(probe, startsWith('Pick the most important term'));
      expect(probe, isNot(contains('only in Derivatives')));
    });

    test('a lesson linked by the Linker to a nearby lesson is found', () async {
      final api = await mathWithOpenNodes();
      await passAudit(api, 5);
      await lesson(
        api,
        5,
        'the first misconception in Quadratic Equations',
      ); // near Discriminant (6)
      await lesson(
        api,
        12,
        'a far-away misconception in Derivatives',
      ); // Linker: related to the previous lesson
      // Discriminant (6) is next to Quadratic Equations (5); the later lesson on Derivatives (12) is linked to it.
      expect(await firstProbe(api, 6), contains('a far-away misconception in Derivatives'));
    });
  });

  group('check-ins', () {
    test('the contract example is parsed as specified (4.5)', () async {
      final api = newApi();
      const transcript =
          "I slept six hours last night and didn't exercise. I had ramen for lunch and I'm a bit tired.";
      final r = await api.checkInVoice(transcript);
      expect(r.checkin.sleepHours, 6);
      expect(r.checkin.exercised, isFalse);
      expect(r.checkin.dietNote, 'lunch: ramen');
      expect(r.checkin.focus, isNull); // "tired" sets nothing
      expect(r.checkin.stress, isNull);
      expect(r.checkin.transcript, transcript);
      expect(r.checkin.source, CheckInSource.voice);
      expect(r.missingFields, [CheckInField.focus, CheckInField.stress]);
      expect(r.checkin.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('sleep hours: digits, decimals and number words followed by hours / h', () async {
      final api = newApi();
      Future<double?> sleep(String t) async => (await api.checkInVoice(t)).checkin.sleepHours;
      expect(await sleep('I slept 7 hours'), 7);
      expect(await sleep('I slept 6.5 hours'), 6.5);
      expect(await sleep('I slept 8h'), 8);
      expect(await sleep('Got 5 hrs of sleep'), 5);
      expect(await sleep('I slept one hour'), 1);
      expect(await sleep('I slept for seven hours'), 7);
      expect(await sleep('Twelve hours of sleep'), 12);
      expect(await sleep('I slept 20 hours'), isNull); // out of range
      expect(await sleep('I slept well'), isNull);
      expect(await sleep('I studied 3 hours'), isNull); // no sleep nearby
    });

    test('exercise: negative forms win, positive forms need a verb', () async {
      final api = newApi();
      Future<bool?> exercised(String t) async => (await api.checkInVoice(t)).checkin.exercised;
      expect(await exercised("I didn't exercise"), isFalse);
      expect(await exercised('No exercise today'), isFalse);
      expect(await exercised('I skipped the gym'), isFalse);
      expect(await exercised("I didn't work out"), isFalse);
      expect(await exercised('I exercised'), isTrue);
      expect(await exercised('I worked out this morning'), isTrue);
      expect(await exercised('I went to the gym'), isTrue);
      expect(await exercised('I went for a run'), isTrue);
      expect(await exercised('I studied at lunch'), isNull);
      expect(await exercised('Exercise is fun'), isNull);
    });

    test('diet: the meal plus the food after had / ate', () async {
      final api = newApi();
      Future<String?> diet(String t) async => (await api.checkInVoice(t)).checkin.dietNote;
      expect(await diet('I had ramen for lunch'), 'lunch: ramen');
      expect(await diet('I ate a sandwich for breakfast'), 'breakfast: sandwich');
      expect(await diet('For dinner I had pizza with friends'), 'dinner: pizza with friends');
      expect(await diet('I skipped lunch'), isNull);
      expect(await diet("I'm hungry"), isNull);
    });

    test(
      'focus: "focused well" → 4, "couldn\'t focus" → 2; stress: stressed → 4, relaxed → 2',
      () async {
        final api = newApi();
        Future<int?> focus(String t) async => (await api.checkInVoice(t)).checkin.focus;
        Future<int?> stress(String t) async => (await api.checkInVoice(t)).checkin.stress;
        expect(await focus('I focused well today'), 4);
        expect(await focus("I couldn't focus"), 2);
        expect(await focus('Focus was average'), isNull);
        expect(await focus('I slept well'), isNull);

        expect(await stress('I was stressed'), 4);
        expect(await stress('I have a lot of stress'), 4);
        expect(await stress('I felt relaxed'), 2);
        expect(await stress('No stress today'), 2);
        expect(await stress('I was not stressed'), 2);
        expect(await stress('I worked on stress tests'), isNull);
      },
    );

    test('Korean sentences still parse (fallback rules)', () async {
      final api = newApi();
      final r = await api.checkInVoice('어제 여섯 시간 잤고 운동은 안 했어요. 점심은 라면 먹었어요.');
      expect(r.checkin.sleepHours, 6);
      expect(r.checkin.exercised, isFalse);
      expect(r.checkin.dietNote, '점심 라면');
    });

    test('other topics in the same transcript do not bleed into each other', () async {
      final api = newApi();
      final r = await api.checkInVoice("I didn't exercise. I focused well and felt relaxed.");
      expect(r.checkin.exercised, isFalse);
      expect(r.checkin.focus, 4);
      expect(r.checkin.stress, 2);
      expect(r.missingFields, [CheckInField.sleepHours, CheckInField.dietNote]);
    });

    test('nothing recognised: all five fields are missing, in order', () async {
      final api = newApi();
      final r = await api.checkInVoice("I'm just tired");
      expect(r.checkin.sleepHours, isNull);
      expect(r.checkin.transcript, "I'm just tired");
      expect(r.missingFields, CheckInField.values);
    });

    test('the follow-up flow re-posts the combined transcript', () async {
      final api = newApi();
      final first = await api.checkInVoice("I slept six hours and didn't exercise");
      expect(first.missingFields, [CheckInField.dietNote, CheckInField.focus, CheckInField.stress]);
      final combined =
          '${first.checkin.transcript}\nI focused well and felt relaxed. I had kimbap for dinner.';
      final second = await api.checkInVoice(combined);
      expect(second.checkin.sleepHours, 6);
      expect(second.checkin.exercised, isFalse);
      expect(second.checkin.focus, 4);
      expect(second.checkin.stress, 2);
      expect(second.checkin.dietNote, 'dinner: kimbap');
      expect(second.missingFields, isEmpty);
    });

    test('a second check-in on the same KST day replaces the first', () async {
      var now = DateTime.utc(2026, 10, 5, 3);
      final api = newApi(clock: () => now);
      await api.checkInVoice('I slept five hours');
      now = DateTime.utc(2026, 10, 5, 8); // same KST day
      final replaced = await api.checkInVoice('I slept nine hours');
      expect(replaced.checkin.date, '2026-10-05');
      final facts = (await api.getBriefing()).facts.condition;
      expect(facts.days, 1);
      expect(facts.avgSleepHours, 9);
      // The fields of the replaced record are not merged: exercised was never said.
      expect(replaced.checkin.exercised, isNull);
    });

    test('the day changes at midnight KST (15:00 UTC)', () async {
      var now = DateTime.utc(2026, 10, 5, 14, 0); // 23:00 KST on the 5th
      final api = newApi(clock: () => now);
      expect((await api.checkInVoice('I slept five hours')).checkin.date, '2026-10-05');
      now = DateTime.utc(2026, 10, 5, 15, 30); // 00:30 KST on the 6th
      expect((await api.checkInVoice('I slept six hours')).checkin.date, '2026-10-06');
      now = DateTime.utc(2026, 10, 5, 16, 0); // 01:00 KST on the 6th: replaces
      expect((await api.checkInVoice('I slept seven hours')).checkin.date, '2026-10-06');
      expect((await api.getBriefing()).facts.condition.days, 2);
    });

    test('fields are never copied from earlier days', () async {
      var now = DateTime.utc(2026, 10, 5, 3);
      final api = newApi(clock: () => now);
      await api.checkInVoice("I slept six hours and didn't exercise. I focused well.");
      now = DateTime.utc(2026, 10, 6, 3);
      final next = await api.checkInVoice('I slept seven hours');
      expect(next.checkin.sleepHours, 7);
      expect(next.checkin.exercised, isNull);
      expect(next.checkin.focus, isNull);
      expect(next.missingFields, [
        CheckInField.exercised, CheckInField.dietNote, CheckInField.focus, CheckInField.stress, //
      ]);
    });
  });

  group('briefing facts and the narrator', () {
    test('a fresh briefing: node counts, no audits, no narrative, condition unknown', () async {
      final api = await seededFakeApi();
      final b = await api.getBriefing();
      expect(b.narrative, isNull);
      expect(b.narrativeGeneratedAt, isNull);
      expect(b.facts.nodes.total, 12);
      expect(b.facts.nodes.mastered, 0);
      expect(b.facts.nodes.available, 1);
      expect(b.facts.nodes.locked, 11);
      expect(b.facts.audits.total, 0);
      expect(b.facts.misconceptionClusters, isEmpty);
      expect(b.facts.condition.flag, ConditionFlag.unknown);
      expect(b.facts.condition.days, 0);
      expect(b.facts.condition.avgSleepHours, isNull);
    });

    test('facts are computed from the state', () async {
      final api = await seededFakeApi();
      await passAudit(api, 1);
      await failAudit(api, 2);
      await api.startAudit(2); // an abandoned session is not counted
      final f = (await api.getBriefing()).facts;
      expect(f.nodes.mastered, 1);
      expect(f.nodes.available, 3);
      expect(f.nodes.locked, 8);
      expect(f.audits.passed, 1);
      expect(f.audits.failed, 1);
      expect(f.audits.total, 2);
    });

    test('misconceptions that overlap form one cluster; cross-skill ones come first', () async {
      final api = await seededFakeApi();
      await passAudit(api, 1);
      await passAudit(api, 3);
      Future<void> lesson(int skillId, String m) async {
        final f = await failAudit(api, skillId);
        await api.submitReflection(f.sessionId, m);
      }

      await lesson(2, 'a completely different kind of mistake, lol');
      await lesson(2, 'thought no real roots means no solution');
      await lesson(3, 'saw no real roots as no solution'); // Functions (3): same idea, other skill
      final clusters = (await api.getBriefing()).facts.misconceptionClusters;
      expect(clusters, hasLength(2));
      final cross = clusters.first;
      expect(cross.crossSkill, isTrue);
      expect(cross.occurrences, 2);
      expect(cross.label, 'thought no real roots means no solution');
      expect(cross.skills, ['Algebra', 'Functions']);
      expect(cross.principleIds, hasLength(2));
      final single = clusters.last;
      expect(single.crossSkill, isFalse);
      expect(single.occurrences, 1);
      expect(single.skills, ['Algebra']);
    });

    test('the narrative is cut to 400 characters', () async {
      final api = await seededFakeApi();
      for (var i = 0; i < 9; i++) {
        final label = String.fromCharCodes([for (var j = 0; j < 40; j++) 0x100 + i * 100 + j * 2]);
        final f = await failAudit(api, 1);
        await api.submitReflection(f.sessionId, label);
      }
      final b = await api.narrate();
      expect(b.facts.misconceptionClusters, hasLength(9));
      expect(b.narrative!.runes.length, 400);
    });
  });

  group('condition and pipelines behind the chat', () {
    test('condition: under 6 h of sleep (last three check-ins) is low, else normal', () async {
      final api = newApi(clock: () => DateTime.utc(2026, 10, 5, 3));
      expect((await api.getBriefing()).facts.condition.flag, ConditionFlag.unknown);
      await api.checkInVoice('Last night I slept four hours.');
      var c = (await api.getBriefing()).facts.condition;
      expect(c.flag, ConditionFlag.low);
      expect(c.avgSleepHours, 4);
      expect(c.days, 1);
      await api.checkInVoice('Last night I slept eight hours.'); // same KST day: replaces
      c = (await api.getBriefing()).facts.condition;
      expect(c.flag, ConditionFlag.normal);
      expect(c.days, 1);
    });

    test('stress ≥ 4 alone makes the condition low', () async {
      final api = newApi();
      await api.checkInVoice('Last night I slept eight hours and I am stressed.');
      expect((await api.getBriefing()).facts.condition.flag, ConditionFlag.low);
    });

    test('the narrator builds a narrative of at most 400 characters', () async {
      final api = await seededFakeApi();
      await passAudit(api, 1);
      final b = await api.narrate();
      expect(b.narrative, startsWith("You've cleared 1 of 12 nodes."));
      expect(b.narrativeGeneratedAt, isNotNull);
    });

    test('the narrator pluralizes: 1 time / n times, 1 day / n days', () async {
      final api = await seededFakeApi();
      await api.checkInVoice('Last night I slept eight hours.');
      final f = await failAudit(api, 1);
      await api.submitReflection(f.sessionId, 'thought the rule always holds');
      final one = (await api.narrate()).narrative!;
      expect(one, contains('showed up 1 time in High School Math.'));
      expect(one, contains('Average sleep over the last day: 8 h.'));
    });

    test('a topic that starts with a blank line gets the root title New Topic', () async {
      final api = newApi();
      final map = await api.generateCourse(const GenerateRequest(topic: '\nQ: Which?\nA: This'));
      expect(map.nodes.first.title, 'New Topic');
    });

    test('the planner needs an available node; a fresh course offers the root only', () async {
      final api = newApi();
      expect((await failure(api.generatePlan)).statusCode, 400);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      final plan = await api.generatePlan();
      expect(plan.steps.map((s) => s.skillTitle), ['High School Math']);
      expect(plan.suggestedTier, Tier.medium);
    });
  });

  group('uploads', () {
    test('a text file is stored with its name and size', () async {
      final api = newApi(clock: () => DateTime.utc(2026, 10, 5, 3));
      final up = await api.uploadFile(
        filename: 'course.md',
        bytes: utf8.encode('# Calculus\nlimits'),
      );
      expect(up.id, 1);
      expect(up.filename, 'course.md');
      expect(up.chars, 17);
      expect(up.createdAt, DateTime.utc(2026, 10, 5, 3));
      expect((await api.uploadFile(filename: 'a.TXT', bytes: [65])).id, 2);
    });

    test('only pdf, txt and md up to 4 MB; an empty file has no text (400)', () async {
      final api = newApi();
      for (final name in ['x.docx', 'x.exe', 'x']) {
        final e = await failure(() => api.uploadFile(filename: name, bytes: [65]));
        expect(e.statusCode, 400, reason: name);
        expect(e.serverMessage, 'Only PDF, TXT or MD files up to 4 MB.');
      }
      final big = await failure(
        () => api.uploadFile(filename: 'x.pdf', bytes: List.filled(4 * 1024 * 1024 + 1, 65)),
      );
      expect(big.statusCode, 400);
      final empty = await failure(
        () => api.uploadFile(filename: 'x.txt', bytes: utf8.encode('  \n')),
      );
      expect(empty.serverMessage, 'No text could be read from this file.');
      expect(empty.userMessage, "Couldn't read any text from this file.");
    });

    test('failNext can target uploadFile', () async {
      final api = newApi();
      api.failNext(method: 'uploadFile', statusCode: null);
      expect(
        (await failure(() => api.uploadFile(filename: 'a.txt', bytes: [65]))).isNetworkError,
        isTrue,
      );
    });
  });

  group('material search', () {
    test('by gap: queries and the first three mock results', () async {
      final api = await seededFakeApi();
      final plan = await api.createSearchPlan(
        1,
        gap: 'could not explain the Discriminant when it is negative',
      );
      expect(plan.skillId, 1);
      expect(plan.gap, 'could not explain the Discriminant when it is negative');
      expect(plan.queries, [
        'High School Math could not explain the Discriminant when it is negative'.substring(
          0,
          'High School Math '.length + 30,
        ),
        'High School Math explained',
      ]);
      expect(plan.items, hasLength(3));
      for (final (i, item) in plan.items.indexed) {
        expect(item.url, 'https://example.org/${i + 1}');
        expect(item.reason, 'Covers this gap directly.');
        expect(item.title, isNotEmpty);
        expect(item.snippet, isNotEmpty);
      }
    });

    test('by misconception id: searches for that lesson card misconception', () async {
      final api = await seededFakeApi();
      final failed = await failAudit(api, 1);
      final p = await api.submitReflection(
        failed.sessionId,
        'I thought no real roots means no solution',
      );
      final plan = await api.createSearchPlan(1, misconceptionId: p.id);
      expect(plan.gap, p.misconception);
      expect(plan.queries.last, 'High School Math explained');
      expect(plan.id, 1);
      expect((await api.createSearchPlan(1, gap: 'another')).id, 2);
    });

    test('errors', () async {
      final api = await seededFakeApi();
      final none = await failure(() => api.createSearchPlan(1));
      expect(none.statusCode, 400);
      expect(
        none.serverMessage,
        'A gap or misconception id is required. Search targets a specific gap only.',
      );
      expect((await failure(() => api.createSearchPlan(1, gap: '  '))).statusCode, 400);
      final noSkill = await failure(() => api.createSearchPlan(99, gap: 'g'));
      expect(noSkill.statusCode, 404);
      expect(noSkill.serverMessage, 'skill not found');
      final noLesson = await failure(() => api.createSearchPlan(1, misconceptionId: 42));
      expect(noLesson.statusCode, 404);
      expect(noLesson.serverMessage, 'misconception not found');
    });
  });

  group('failure injection', () {
    test('failNext makes the next call fail with 502 and the contract message', () async {
      final api = await seededFakeApi();
      api.failNext(statusCode: 502);
      final e = await failure(() => api.listCourses());
      expect(e.statusCode, 502);
      expect(e.userMessage, ApiException.aiFailureText);
      // One-shot: the following call works.
      expect(await api.listCourses(), hasLength(1));
    });

    test('the default message is the one of the endpoint', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      api.failNext();
      expect(
        (await failure(() => api.submitTurn(s.session.id, 'x'))).serverMessage,
        'The auditor is temporarily unavailable. Please try again.',
      );
      api.failNext();
      expect(
        (await failure(() => api.narrate())).serverMessage,
        'Briefing generation failed. Please try again.',
      );
      api.failNext();
      expect(
        (await failure(() => api.generatePlan())).serverMessage,
        'Plan generation failed. Please try again.',
      );
      api.failNext();
      expect(
        (await failure(() => api.createSearchPlan(1, gap: 'g'))).serverMessage,
        'Material search failed. Please try again.',
      );
      api.failNext();
      expect(
        (await failure(() => api.generateCourse(const GenerateRequest(topic: 'x')))).serverMessage,
        'Course generation failed. Please try again.',
      );
      api.failNext();
      expect(
        (await failure(() => api.submitReflection(s.session.id, 'x'))).serverMessage,
        'Principle extraction failed. Please try again.',
      );
    });

    test('a failed call has no effect on the state', () async {
      final api = await seededFakeApi();
      final s = await api.startAudit(1);
      api.failNext(method: 'submitTurn');
      await failure(() => api.submitTurn(s.session.id, longAnswer));
      // The failed answer was not stored: this is still the first answer → a probe.
      expect(await api.submitTurn(s.session.id, longAnswer), isA<ProbeResult>());

      api.failNext(method: 'generateCourse');
      await failure(() => api.generateCourse(const GenerateRequest(topic: 'math')));
      expect(await api.listCourses(), hasLength(1));
    });

    test('method restricts the failure; other calls pass through and keep it queued', () async {
      final api = await seededFakeApi();
      api.failNext(statusCode: 404, message: 'skill not found', method: 'startAudit');
      expect(await api.listCourses(), hasLength(1)); // passes
      expect(await api.getBriefing(), isA<Briefing>()); // passes
      final e = await failure(() => api.startAudit(1));
      expect(e.statusCode, 404);
      expect(e.serverMessage, 'skill not found');
      await api.startAudit(1); // consumed
    });

    test('times, a custom message, network failures and clearFailures', () async {
      final api = await seededFakeApi();
      api.failNext(statusCode: 400, message: 'skill is locked', times: 2);
      final first = await failure(() => api.listCourses());
      expect(first.statusCode, 400);
      expect(first.userMessage, 'This node is locked. Clear its parent first.');
      expect((await failure(() => api.listCourses())).statusCode, 400);
      expect(await api.listCourses(), isNotEmpty);

      api.failNext(statusCode: null);
      final network = await failure(() => api.listCourses());
      expect(network.isNetworkError, isTrue);
      expect(network.userMessage, ApiException.networkText);

      api.failNext(times: 3);
      api.clearFailures();
      expect(await api.listCourses(), isNotEmpty);
    });

    test('every API method can be targeted', () {
      final api = newApi();
      for (final name in FakeApiClient.methodNames) {
        api.failNext(method: name); // asserts on unknown names
      }
      expect(FakeApiClient.methodNames, hasLength(28));
      expect(() => api.failNext(method: 'nope'), throwsA(isA<AssertionError>()));
    });
  });

  group('timing and determinism', () {
    test('the default latency is 300 ms; it can be changed', () async {
      expect(FakeApiClient().latency, const Duration(milliseconds: 300));
      final slow = FakeApiClient(latency: const Duration(milliseconds: 60));
      final watch = Stopwatch()..start();
      await slow.listCourses();
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(50));
    });
  });
}
