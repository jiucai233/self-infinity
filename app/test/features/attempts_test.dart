// A fail is her not understanding yet (which attempt, how the score moved); a
// pass shows the node's curve, the first explanation beside this one and the
// user's own identity line; the node card names the main quest it serves.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

String textOf(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

Future<void> answer(WidgetTester tester, String text, {int times = 2}) async {
  for (var i = 0; i < times; i++) {
    await say(tester, text);
  }
}

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi(); // Discriminant (6) is open
  });

  group('a fail', () {
    testWidgets('her line, the attempt on this node and the change from the last score', (tester) async {
      api.debugAddFailedAttempt(6, score: 62, answer: 'A discriminant is a number.');
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, shortAnswer);

      expect(textOf(tester, 'verdict-title'), "I don't get it yet. Explain it once more?");
      expect(textOf(tester, 'verdict-kicker'), 'Attempt 2 · −17 from last time');
      expect(textOf(tester, 'verdict-score'), '45');
      // The title bar says "once more", not a red "Failed".
      expect(find.text('Once more'), findsOneWidget);
      expect(find.text('Failed'), findsNothing);
    });

    testWidgets('a first attempt has no change; a better one shows +N', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, shortAnswer);
      expect(textOf(tester, 'verdict-kicker'), 'Attempt 1');

      api.debugAddFailedAttempt(9, score: 37, answer: 'x');
      api.debugSetStatus(9, SkillStatus.available);
      await pumpScene(tester, const AuditScene(skillId: 9), api: api);
      await answer(tester, shortAnswer);
      expect(textOf(tester, 'verdict-kicker'), 'Attempt 2 · +8 from last time');
    });
  });

  group('a pass', () {
    testWidgets('after two fails: the curve, the first answer beside this one, her line', (tester) async {
      api
        ..debugAddFailedAttempt(6, score: 62, answer: 'A discriminant is a number.')
        ..debugAddFailedAttempt(6, score: 68, answer: 'It is b squared minus 4ac.');
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, longAnswer);

      expect(key('celebration-card'), findsOneWidget);
      expect(textOf(tester, 'celebration-line-text'), 'Oh! Now I get it!');
      expect(key('celebration-curve'), findsOneWidget);
      expect(textOf(tester, 'celebration-attempts'), 'Attempt 3');
      expect(
        find.descendant(of: key('celebration-curve'), matching: find.text('62')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('celebration-first'), matching: find.text('A discriminant is a number.')),
        findsOneWidget,
      );
      expect(find.descendant(of: key('celebration-this'), matching: find.text(longAnswer)), findsOneWidget);
    });

    testWidgets('a first attempt has no curve and no comparison', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, longAnswer);

      expect(key('celebration-card'), findsOneWidget);
      expect(key('celebration-line'), findsOneWidget);
      expect(key('celebration-curve'), findsNothing);
      expect(key('celebration-first'), findsNothing);
      expect(key('celebration-this'), findsNothing);
    });

    testWidgets('she reads back their identity line', (tester) async {
      await api.updateProfile(identity: 'I explain before I memorize.');
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, longAnswer);

      expect(textOf(tester, 'celebration-identity'), '“I explain before I memorize.”');
      expect(textOf(tester, 'celebration-closer'), 'One step closer.');
    });

    testWidgets('without one, the main quest the course serves; with neither, nothing', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      await answer(tester, longAnswer);
      expect(key('celebration-identity'), findsNothing);

      final goal = await api.createGoal('Teach calculus to a stranger');
      await api.updateGoal(goal.id, courseIds: [1]);
      await pumpScene(tester, const AuditScene(skillId: 7), api: api);
      await answer(tester, longAnswer);
      expect(textOf(tester, 'celebration-identity'), '“Teach calculus to a stranger”');
    });
  });

  group('the node card', () {
    testWidgets('names the main quest its course serves', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      expect(key('skill-quest'), findsNothing);

      final goal = await api.createGoal('Teach calculus to a stranger');
      await api.updateGoal(goal.id, courseIds: [1]);
      await pumpScene(tester, const SkillScene(skillId: 6), api: api);
      expect(textOf(tester, 'skill-quest'), 'Main quest · Teach calculus to a stranger');
    });
  });

  test('first_answer is parsed, and only the node history carries it', () async {
    final a = AuditSummary.fromJson({
      'id': 1, 'skill_id': 2, 'skill_title': 'T', 'status': 'failed', 'score': 45,
      'created_at': '2026-10-31T00:00:00Z', 'first_answer': 'My first try',
    });
    expect(a.firstAnswer, 'My first try');
    api.debugAddFailedAttempt(6, score: 60, answer: '  spread   out ${'x' * 300}');
    final history = (await api.getSkillOverview(6)).audits.single.firstAnswer!;
    expect(history, startsWith('spread out x'));
    expect(history.runes.length, 240);
    expect(history, endsWith('…'));
    expect((await api.listAudits()).single.firstAnswer, isNull);
  });

  test('her lines all come from one place, in each language', () {
    for (final lang in AppLanguage.values) {
      final lines = CharacterLines(lookupAppLocalizations(lang.locale));
      for (final s in CharacterSituation.values) {
        expect(lines.say(s), isNotEmpty);
      }
    }
    final ko = CharacterLines(lookupAppLocalizations(const Locale('ko')));
    expect(ko.say(CharacterSituation.notYet), '아직 잘 모르겠어요. 한 번 더 설명해 줄래요?');
    expect(ko.say(CharacterSituation.gotIt), '아! 이제 알겠어요!');
  });
}
