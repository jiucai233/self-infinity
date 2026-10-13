// The knowledge points inside a leaf (contract #7–#8, `Point`): an audit goes
// point by point and records what held and what was missed, the next one asks
// only about what was missed, a leaf with points is not broken down; an
// unfinished audit is picked up again; her feedback comes before her question;
// and what is on the page can be copied.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

/// The points the script gives the leaf “Discriminant” (node 6 of the math course).
final List<String> points = FakeApiClient.fakePointTitles('Discriminant');

Finder key(String k) => find.byKey(Key(k));

String textOf(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

Future<SkillNode> node(FakeApiClient api, int id) async =>
    (await api.getCourseMap(1)).nodes.firstWhere((n) => n.id == id);

/// What the app wrote to the clipboard during the test.
List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'Clipboard.setData') {
      copied.add(((call.arguments as Map)['text'] as String?) ?? '');
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  group('the fake API', () {
    test('a leaf gets its points before its first audit; a branch has none', () async {
      final api = await seededFakeApi();
      expect((await node(api, 6)).points, isEmpty);

      final start = await api.startAudit(6);

      expect(start.session.points.map((p) => p.title), points);
      expect((await node(api, 6)).points, [for (final t in points) SkillPoint(title: t)]);
      api.debugSetStatus(2, SkillStatus.available);
      expect((await api.startAudit(2)).session.points, isEmpty);
    });

    test('a fail records what held and what was missed; the next audit asks only that', () async {
      final api = await seededFakeApi();

      final failed = (await failAudit(api, 6)).verdict;

      final recorded = [
        SkillPoint(title: points[0], ok: false, note: FakeApiClient.failNote),
        SkillPoint(title: points[1], ok: true),
        SkillPoint(title: points[2], ok: true),
      ];
      expect(failed.points, recorded);
      expect(failed.feedback, FakeApiClient.failFeedback);
      expect((await node(api, 6)).points, recorded);

      final again = await api.startAudit(6);
      expect(again.session.points, [SkillPoint(title: points[0], note: FakeApiClient.failNote)]);
      expect(again.openingQuestion, startsWith('What you taught me last time, I still have.'));
      expect(api.debugMaxTurns(again.session.id), 4);
    });

    test('passing what was missed clears the node and every point', () async {
      final api = await seededFakeApi();
      await failAudit(api, 6);

      final passed = await passAudit(api, 6);

      expect(passed.points, [SkillPoint(title: points[0], ok: true)]);
      final after = await node(api, 6);
      expect(after.isMastered, isTrue);
      expect(after.points.map((p) => (p.ok, p.note)), everyElement((true, null)));
    });

    test('a leaf with points is not broken down', () async {
      final api = await seededFakeApi();
      await api.startAudit(6);

      final refused = await api.expandSkill(6).then<Object?>((_) => null, onError: (Object e) => e);

      expect(refused, isA<ApiException>().having((e) => e.statusCode, 'status', 400));
    });

    test('an unfinished audit is picked up; restart begins a new one', () async {
      final api = await seededFakeApi();
      final first = await api.startAudit(6);
      final probe = await api.submitTurn(first.session.id, 'A first try') as ProbeResult;
      expect((probe.feedback, probe.point), (FakeApiClient.probeFeedback, points[0]));

      final again = await api.startAudit(6);

      expect((again.resumed, again.session.id), (true, first.session.id));
      expect(again.session.turns.map((t) => (t.isUser, t.content, t.feedback)), [
        (false, first.openingQuestion, null),
        (true, 'A first try', null),
        (false, probe.question, FakeApiClient.probeFeedback),
      ]);

      final fresh = await api.startAudit(6, restart: true);
      expect((fresh.resumed, fresh.session.turns.length), (false, 1));
      expect(fresh.session.id, isNot(first.session.id));
    });

    test('a closed audit and an old one are not picked up', () async {
      var now = DateTime.utc(2026, 10, 5, 1);
      final api = FakeApiClient(latency: Duration.zero, clock: () => now);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await failAudit(api, 6);
      final open = await api.startAudit(6);
      expect(open.resumed, isFalse); // the failed one is closed

      now = now.add(const Duration(hours: 25));
      expect((await api.startAudit(6)).resumed, isFalse);
    });
  });

  group('the audit', () {
    testWidgets('her line is what she says about the answer, then her question', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: await seededFakeApi());
      expect(key('audit-feedback'), findsNothing); // the opening question has none

      await say(tester, 'Here is how I would explain it');

      expect(textOf(tester, 'audit-feedback'), FakeApiClient.probeFeedback);
      expect(
        tester.getTopLeft(key('audit-feedback')).dy,
        lessThan(tester.getTopLeft(key('audit-bubble-text')).dy),
      );
    });

    testWidgets('an unfinished audit comes back with its dialogue; Start over begins anew', (
      tester,
    ) async {
      final api = await seededFakeApi();
      final first = await api.startAudit(6);
      await api.submitTurn(first.session.id, 'A first try');

      await pumpScene(tester, const AuditScene(skillId: 6), api: api);

      expect(find.text('Picked up where you left off.'), findsOneWidget);
      expect(find.text('A first try'), findsOneWidget);
      expect(textOf(tester, 'audit-bubble-text'), contains('most important term'));

      await tester.tap(key('audit-start-over'));
      await tester.pumpAndSettle();

      expect(key('audit-resumed'), findsNothing);
      expect(find.text('A first try'), findsNothing);
      expect(textOf(tester, 'audit-bubble-text'), first.openingQuestion);
    });

    testWidgets('a first visit says nothing about picking up', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: await seededFakeApi());
      expect(key('audit-resumed'), findsNothing);
    });

    testWidgets('an answer that never got a reply goes back into the input', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: _Unanswered());

      expect(inputText(tester), 'The answer that was lost');
      expect(key('audit-answer'), findsNothing);
      expect(key('audit-bubble-text'), findsOneWidget); // her question is current again
    });

    testWidgets('the verdict lists each point with what was wrong, and can be copied', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      await pumpScene(tester, const AuditScene(skillId: 6), api: await seededFakeApi());
      await say(tester, shortAnswer);
      await say(tester, shortAnswer);

      expect(textOf(tester, 'audit-feedback'), FakeApiClient.failFeedback);
      expect(find.text('Knowledge points'), findsOneWidget);
      for (final (i, title) in points.indexed) {
        expect(
          find.descendant(of: key('verdict-point-$i'), matching: find.text(title)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: key('verdict-point-0'), matching: find.text(FakeApiClient.failNote)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('verdict-point-0'), matching: find.byIcon(Icons.close_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('verdict-point-1'), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );

      await tester.ensureVisible(key('verdict-copy'));
      await tester.tap(key('verdict-copy'));
      await tester.pump();

      expect(copied.single, startsWith('Not yet. · 45\n'));
      expect(copied.single, contains('✗ ${points[0]} — ${FakeApiClient.failNote}'));
      expect(copied.single, contains('✓ ${points[1]}'));
      expect(copied.single, contains("- You didn't cover the exceptions."));
      expect(find.text('Copied.'), findsOneWidget);
    });

    testWidgets('the dialogue can be selected', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: await seededFakeApi());

      expect(
        find.ancestor(of: key('audit-bubble-text'), matching: find.byType(SelectionArea)),
        findsOneWidget,
      );
    });
  });

  group('the node page', () {
    testWidgets('lists the points of a leaf with what held and what was missed', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      expect(find.text('Knowledge points'), findsNothing); // none before its first audit

      await failAudit(api, 6);
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);

      expect(find.text('Knowledge points'), findsOneWidget);
      expect(
        find.descendant(of: key('skill-point-0'), matching: find.text(FakeApiClient.failNote)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('skill-point-0'), matching: find.byIcon(Icons.close_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('skill-point-2'), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('a leaf with points cannot be broken down; it can still get a part by hand', (
      tester,
    ) async {
      final api = await seededFakeApi();
      await failAudit(api, 6);
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);

      await tester.tap(key('skill-menu'));
      await tester.pumpAndSettle();

      expect(key('skill-fill-in'), findsNothing);
      expect(key('skill-add-part'), findsOneWidget);
    });
  });

  group('a failed call', () {
    testWidgets('can be copied with what the server said', (tester) async {
      final copied = watchClipboard(tester);
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestApp(
          child: Scaffold(
            body: ErrorView(
              error: const ApiException(502, 'The auditor is temporarily unavailable.'),
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(key('error-copy'));
      await tester.pump();

      expect(
        copied.single,
        'Something went wrong on our side. Please try again. '
        '(HTTP 502: The auditor is temporarily unavailable.)',
      );
      expect(
        find.ancestor(
          of: find.textContaining('Something went wrong'),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
    });
  });
}

/// The math course with an unfinished audit of node 6 whose last answer never
/// got a reply (the call failed after the server had saved it).
class _Unanswered extends FakeApiClient {
  _Unanswered() : super(latency: Duration.zero) {
    generateCourse(const GenerateRequest(topic: 'math'));
  }

  @override
  Future<AuditStart> startAudit(
    int skillId, {
    String mode = 'day',
    bool testOut = false,
    bool restart = false,
  }) async {
    final start = await super.startAudit(skillId, mode: mode, testOut: testOut, restart: restart);
    final session = start.session;
    return AuditStart(
      session: AuditSession(
        id: session.id,
        skillId: session.skillId,
        nodePosition: session.nodePosition,
        status: session.status,
        turns: [
          ...session.turns,
          const AuditTurn(role: AuditRole.user, content: 'The answer that was lost'),
        ],
        points: session.points,
      ),
      openingQuestion: start.openingQuestion,
      resumed: true,
    );
  }
}
