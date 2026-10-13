// The replay of an audit: each gap with the user's own words next to what
// holds, the past lessons that held or came back, and the reflection the user
// writes themselves.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/router.dart';
import 'package:self_infinity/features/audit/gap_evidence.dart';
import 'package:self_infinity/features/audit/lesson_card.dart';
import 'package:self_infinity/features/audit/replay_scene.dart';
import 'package:self_infinity/features/audit/verdict_card.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Future<void> pumpReplay(
  WidgetTester tester,
  FakeApiClient api,
  int auditId, {
  Size size = wideScreen,
  FakeVoiceService? voice,
}) => pumpScene(
  tester,
  ReplayScene(auditId: auditId),
  api: api,
  size: size,
  voice: voice,
);

Finder key(String k) => find.byKey(Key(k));

Finder get column => key('replay-scene');

String reflectionText(WidgetTester tester) =>
    tester.widget<TextField>(key('replay-reflection')).controller!.text;

Future<void> reflect(WidgetTester tester, String text) async {
  await tester.ensureVisible(key('replay-reflection'));
  await tester.pumpAndSettle();
  await tester.enterText(key('replay-reflection'), text);
  await tester.pump();
  await tester.ensureVisible(key('replay-submit'));
  await tester.pumpAndSettle();
  await tester.tap(key('replay-submit'));
  await tester.pumpAndSettle();
}

Future<void> pumpCard(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

const VerdictResult failedVerdict = VerdictResult(
  passed: false,
  score: 45,
  gaps: ['No reason given', 'No exceptions'],
  evidence: [
    GapEvidence(gap: 'No reason given', said: 'It just works', right: 'The range pins it down'),
    GapEvidence(gap: 'No exceptions'),
  ],
  lessons: [
    LessonCheck(principleId: 7, title: 'State the range first', held: false),
    LessonCheck(principleId: 8, title: 'Reason before conclusion', held: true),
  ],
);

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
  });

  group('a gap and what it rests on', () {
    testWidgets('the gap, You said with the quote set in, What holds with the text', (
      tester,
    ) async {
      await pumpCard(tester, GapEvidenceView(evidence: failedVerdict.evidence.first));
      expect(textsIn(tester, find.byType(GapEvidenceView)), [
        'No reason given',
        'You said',
        'It just works',
        'What holds',
        'The range pins it down',
      ]);
      final inset = tester.widget<Container>(
        find.ancestor(of: find.text('It just works'), matching: find.byType(Container)).first,
      );
      final rule = ((inset.decoration! as BoxDecoration).border! as Border).left;
      expect(rule.color, AppColors.outlineStrong);
    });

    testWidgets('with neither it is just the gap', (tester) async {
      await pumpCard(tester, const GapEvidenceView(evidence: GapEvidence(gap: 'No exceptions')));
      expect(textsIn(tester, find.byType(GapEvidenceView)), ['No exceptions']);
    });
  });

  group('the verdict card', () {
    testWidgets('shows the quote and what holds under the gap it belongs to', (tester) async {
      await pumpCard(tester, VerdictCard(verdict: failedVerdict, onBack: () {}));
      expect(
        textsIn(tester, key('verdict-gap-0')),
        containsAll(['It just works', 'The range pins it down']),
      );
      expect(textsIn(tester, key('verdict-gap-1')), ['No exceptions']);
    });

    testWidgets('a verdict without evidence lists its gaps as before', (tester) async {
      await pumpCard(
        tester,
        VerdictCard(
          verdict: const VerdictResult(passed: false, score: 45, gaps: ['No reason given']),
          onBack: () {},
        ),
      );
      expect(textsIn(tester, key('verdict-gap-0')), ['No reason given']);
      expect(find.text('You said'), findsNothing);
      expect(find.text('Past lessons'), findsNothing);
    });

    testWidgets('a lesson that came back is red, one that held is amber', (tester) async {
      await pumpCard(tester, VerdictCard(verdict: failedVerdict, onBack: () {}));
      Text row(int i) => tester.widget<Text>(
        find.descendant(of: key('verdict-lesson-$i'), matching: find.byType(Text)),
      );
      expect(row(0).data, 'Came back: State the range first');
      expect(row(0).style!.color, AppColors.danger);
      expect(row(1).data, 'Held: Reason before conclusion');
      expect(row(1).style!.color, AppColors.success);
    });

    testWidgets('the feedback buttons show only for a fail with their callbacks', (tester) async {
      await pumpCard(tester, VerdictCard(verdict: failedVerdict, onBack: () {}));
      expect(key('verdict-too-hard'), findsNothing);
      expect(key('verdict-misheard'), findsNothing);

      var told = 0;
      await pumpCard(
        tester,
        VerdictCard(
          verdict: failedVerdict,
          onTooHard: () => told++,
          onMisheard: () => told += 10,
          onBack: () {},
        ),
      );
      expect(find.text('Too hard for now'), findsOneWidget);
      expect(find.text("I didn't say that"), findsOneWidget);
      await tester.tap(key('verdict-too-hard'));
      await tester.tap(key('verdict-misheard'));
      expect(told, 11);

      await pumpCard(
        tester,
        VerdictCard(
          verdict: const VerdictResult(passed: true, score: 90),
          onTooHard: () {},
          onMisheard: () {},
          onBack: () {},
        ),
      );
      expect(key('verdict-too-hard'), findsNothing);
      expect(key('verdict-misheard'), findsNothing);
    });

    testWidgets('a button already used gives way to a line saying it was noted', (tester) async {
      await pumpCard(
        tester,
        VerdictCard(
          verdict: failedVerdict,
          onTooHard: () {},
          onMisheard: () {},
          tooHardNoted: true,
          onBack: () {},
        ),
      );
      expect(key('verdict-too-hard'), findsNothing);
      expect(key('verdict-too-hard-noted'), findsOneWidget);
      expect(find.text('Noted: too hard for now'), findsOneWidget);
      expect(key('verdict-misheard'), findsOneWidget);
      expect(key('verdict-misheard-noted'), findsNothing);
    });

    testWidgets('after a real fail the card quotes the last answer', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpCard(tester, VerdictCard(verdict: failed.verdict, onBack: () {}));
      expect(
        textsIn(tester, key('verdict-gap-0')),
        containsAll(['You said', shortAnswer, 'What holds', FakeApiClient.failRight]),
      );
    });
  });

  group('the replay of a fail', () {
    testWidgets('the node, when it was, Failed and the score, her comment and the points', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      expect(tester.widget<Text>(key('stage-title')).data, 'Discriminant');
      expect(find.text('Failed'), findsOneWidget);
      expect(
        tester.widget<Text>(key('replay-date')).data,
        matches(r'^[A-Z][a-z]{2} \d{1,2}, \d{4} \d{2}:\d{2}$'),
      );
      expect(tester.widget<Text>(key('replay-score')).data, '45');
      expect(
        tester.widget<Text>(key('replay-comment')).data,
        'The answer stops at the conclusion and lacks reasons.',
      );
      expect(
        find.descendant(of: key('replay-point-0'), matching: find.text(FakeApiClient.failNote)),
        findsOneWidget,
      );
    });

    testWidgets('each gap shows the user’s own words next to what holds', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      for (final (i, gap) in failed.verdict.gaps.indexed) {
        expect(textsIn(tester, key('replay-gap-$i')), [
          gap,
          'You said',
          shortAnswer,
          'What holds',
          FakeApiClient.failRight,
        ]);
      }
    });

    testWidgets('the dialogue is folded; open, her feedback comes before her question', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      expect(find.text(FakeApiClient.probeFeedback), findsNothing);
      await tester.ensureVisible(key('replay-dialogue'));
      await tester.pumpAndSettle();
      await tester.tap(key('replay-dialogue'));
      await tester.pumpAndSettle();
      final texts = textsIn(tester, column).toList();
      final audit = await api.getAudit(failed.sessionId);
      final probe = audit.turns[2];
      expect(probe.feedback, FakeApiClient.probeFeedback);
      expect(texts.indexOf(probe.feedback!), lessThan(texts.indexOf(probe.content)));
      expect(texts.where((t) => t == shortAnswer), hasLength(4)); // two gaps, two answers
    });

    testWidgets('the reflection field asks what you believed, and has the mic in it', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      final voice = FakeVoiceService();
      await pumpReplay(tester, api, failed.sessionId, voice: voice);
      final field = tester.widget<TextField>(key('replay-reflection'));
      expect(field.decoration!.hintText, 'What did you believe at the time?…');
      expect(field.decoration!.suffixIcon, isA<DictationButton>());
      expect(field.maxLines, greaterThan(1));
      // Nothing is suggested: the field starts empty, and so nothing can be sent.
      expect(reflectionText(tester), '');
      expect(tester.widget<FilledButton>(key('replay-submit')).onPressed, isNull);

      await tester.ensureVisible(key('dictation-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('dictation-button'));
      await tester.pump();
      voice.hear('I thought the formula was the whole idea');
      await tester.pumpAndSettle();
      expect(reflectionText(tester), 'I thought the formula was the whole idea');
    });

    testWidgets('reflecting makes the lesson card, which takes the field’s place', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      expect(key('replay-lesson'), findsNothing);
      await reflect(tester, 'I thought the formula was the whole idea');
      final lesson = (await api.listPrinciples()).single;
      expect(lesson.sourceSessionId, failed.sessionId);
      expect(lesson.misconception, 'I thought the formula was the whole idea');
      expect(tester.widget<LessonCard>(key('replay-lesson')).principle.id, lesson.id);
      expect(key('replay-reflection'), findsNothing);
      expect(key('replay-submit'), findsNothing);
      expect(key('replay-lesson-counts'), findsNothing); // nothing has happened to it yet
    });

    testWidgets('when the Recorder fails the reason shows and the text stays', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      api.failNext(method: 'submitReflection');
      await reflect(tester, 'I thought the formula was the whole idea');
      expect(key('replay-problem'), findsOneWidget);
      expect(reflectionText(tester), 'I thought the formula was the whole idea');
      expect(await api.listPrinciples(), isEmpty);
      await tester.ensureVisible(key('replay-submit'));
      await tester.pumpAndSettle();
      await tester.tap(key('replay-submit'));
      await tester.pumpAndSettle();
      expect(key('replay-lesson'), findsOneWidget);
      expect(key('replay-problem'), findsNothing);
    });
  });

  group('the replay of an audit with a lesson card', () {
    testWidgets('shows the card, and how often it held and came back since', (tester) async {
      final failed = await failAudit(api, 6);
      final lesson = await api.submitReflection(failed.sessionId, 'I memorized the formula');
      await pumpReplay(tester, api, failed.sessionId);
      expect(tester.widget<LessonCard>(key('replay-lesson')).principle.id, lesson.id);
      expect(key('replay-reflection'), findsNothing);
      expect(key('replay-lesson-counts'), findsNothing);

      await failAudit(api, 6);
      await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      expect(tester.widget<Text>(key('replay-lesson-counts')).data, 'Held 0 · Came back 2');
    });

    testWidgets('the fail after it names the lesson that came back', (tester) async {
      final first = await failAudit(api, 6);
      final lesson = await api.submitReflection(first.sessionId, 'I memorized the formula');
      final second = await failAudit(api, 6);
      await pumpReplay(tester, api, second.sessionId);
      final row = tester.widget<Text>(
        find.descendant(of: key('replay-lesson-check-0'), matching: find.byType(Text)),
      );
      expect(row.data, 'Came back: ${lesson.title}');
      expect(row.style!.color, AppColors.danger);
      expect(key('replay-reflection'), findsOneWidget); // this one has not been reflected on
    });
  });

  group('the feedback on a fail', () {
    testWidgets('a failed audit offers both; tapping one sends it and says it was noted', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      expect(find.text('Too hard for now'), findsOneWidget);
      expect(find.text("I didn't say that"), findsOneWidget);
      await tester.ensureVisible(key('replay-too-hard'));
      await tester.pumpAndSettle();
      await tester.tap(key('replay-too-hard'));
      await tester.pumpAndSettle();
      expect(key('replay-too-hard'), findsNothing);
      expect(find.text('Noted: too hard for now'), findsOneWidget);
      expect(key('replay-misheard'), findsOneWidget);
      expect(key('replay-misheard-noted'), findsNothing);
      final audit = await api.getAudit(failed.sessionId);
      expect([audit.tooHard, audit.disputed], [true, false]);

      await tester.tap(key('replay-misheard'));
      await tester.pumpAndSettle();
      expect(find.text('Noted: you didn\'t say that'), findsOneWidget);
      expect((await api.getAudit(failed.sessionId)).disputed, isTrue);
    });

    testWidgets('a reopened audit shows what was already noted', (tester) async {
      final failed = await failAudit(api, 6);
      await api.auditFeedback(failed.sessionId, AuditFeedback.misheard);
      await pumpReplay(tester, api, failed.sessionId);
      expect(key('replay-misheard-noted'), findsOneWidget);
      expect(key('replay-misheard'), findsNothing);
      expect(key('replay-too-hard'), findsOneWidget);
    });

    testWidgets('a failed call leaves the button to try again', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      api.failNext(method: 'auditFeedback');
      await tester.ensureVisible(key('replay-too-hard'));
      await tester.pumpAndSettle();
      await tester.tap(key('replay-too-hard'));
      await tester.pumpAndSettle();
      expect(key('replay-too-hard-noted'), findsNothing);
      expect(tester.widget<TextButton>(key('replay-too-hard')).onPressed, isNotNull);
      await tester.tap(key('replay-too-hard'));
      await tester.pumpAndSettle();
      expect(key('replay-too-hard-noted'), findsOneWidget);
    });
  });

  group('the replay of a pass', () {
    testWidgets('Passed and the score; no gaps, no reflection box', (tester) async {
      final passed = await passAudit(api, 6);
      final id = (await api.listAudits()).first.id;
      await pumpReplay(tester, api, id);
      expect(find.text('Passed'), findsOneWidget);
      expect(tester.widget<Text>(key('replay-score')).data, '${passed.score}');
      expect(key('replay-gap-0'), findsNothing);
      expect(key('replay-reflection'), findsNothing);
      expect(key('replay-submit'), findsNothing);
      expect(key('replay-lesson'), findsNothing);
      expect(key('replay-too-hard'), findsNothing);
      expect(key('replay-misheard'), findsNothing);
    });
  });

  group('getting there and back', () {
    testWidgets('the back arrow returns to the node', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId);
      await tester.tap(key('replay-back'));
      await tester.pumpAndSettle();
      expect(find.text('route:${AppRoutes.skill(6)}'), findsOneWidget);
    });

    testWidgets('an audit that cannot be loaded says so and can be retried', (tester) async {
      final failed = await failAudit(api, 6);
      api.failNext(method: 'getAudit');
      await pumpReplay(tester, api, failed.sessionId);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(column, findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(column, findsOneWidget);
    });

    testWidgets('on a phone nothing overflows', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpReplay(tester, api, failed.sessionId, size: phoneScreen);
      expect(column, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
