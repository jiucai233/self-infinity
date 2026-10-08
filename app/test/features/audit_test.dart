// Scene 4-1: the audit on a stage — the Q&A in the chat panel “Audit log”, her
// bubble with her name, the celebration card on a pass, the lesson card flip.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/audit/celebration_card.dart';
import 'package:self_infinity/features/audit/lesson_card.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Future<void> pumpAudit(
  WidgetTester tester,
  FakeApiClient api,
  int id, {
  Size size = wideScreen,
  FakeVoiceService? voice,
  AppState? state,
}) => pumpScene(
  tester,
  AuditScene(skillId: id),
  api: api,
  size: size,
  voice: voice,
  state: state,
);

Avatar avatar(WidgetTester tester) => tester.widget<Avatar>(find.byType(Avatar));

String bubble(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('audit-bubble-text'))).data!;

Finder get qa => find.byKey(const Key('audit-qa'));

Finder get verdictCard => find.byKey(const Key('audit-verdict'));

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

/// The words of the dialogue column, without the date and the times.
List<String> qaLines(WidgetTester tester) => textsIn(
  tester,
  qa,
).where((t) => !RegExp(r'^([A-Z][a-z]{2} \d{1,2}, \d{4}|\d{2}:\d{2})$').hasMatch(t)).toList();

Finder get celebration => find.byKey(const Key('celebration-card'));

/// The bubble text once the celebration card has been put away.
Future<void> closeCelebration(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('celebration-close')));
  await tester.pumpAndSettle();
}

bool inputVisible(WidgetTester tester) => tester
    .widget<Visibility>(
      find
          .ancestor(of: find.byKey(const Key('stage-input')), matching: find.byType(Visibility))
          .first,
    )
    .visible;

/// Two short answers: a probe, then the failing verdict.
Future<void> failIt(WidgetTester tester) async {
  await say(tester, shortAnswer);
  await say(tester, shortAnswer);
}

/// Two long answers: a probe, then the passing verdict.
Future<void> passIt(WidgetTester tester) async {
  await say(tester, longAnswer);
  await say(tester, longAnswer);
}

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
    // The course opens at Discriminant (6); these tests take the root (1) on
    // too, whose question names the whole field.
    api.debugSetStatus(1, SkillStatus.available);
  });

  group('opening', () {
    testWidgets(
      'the title bar names the node (with an In progress chip); the auditor (stern) asks',
      (
        tester,
      ) async {
        await pumpAudit(tester, api, 1);
        expect(tester.widget<Text>(find.byKey(const Key('stage-title'))).data, 'High School Math');
        expect(find.text('In progress'), findsOneWidget);
        expect(find.textContaining('node:'), findsNothing);
        // One column: no right panel; the speaker is pinned on top.
        expect(find.text('Audit log'), findsNothing);
        expect(find.byKey(const Key('history-panel')), findsNothing);
        expect(find.byKey(const Key('audit-speaker')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('audit-bubble')),
            matching: find.text('Auditor'),
          ),
          findsOneWidget,
        );
        expect(bubble(tester), contains('Which problems call for “High School Math”'));
        expect(avatar(tester).agent, 'auditor');
        expect(avatar(tester).mood, AvatarMood.stern);
        expect(avatar(tester).wave, isFalse);
      },
    );

    testWidgets('a branch node gets its branch question', (tester) async {
      api.debugSetStatus(2, SkillStatus.available);
      await pumpAudit(tester, api, 2);
      expect(bubble(tester), contains('“Algebra” covers Quadratic Equations, Sequences.'));
    });

    testWidgets('the audit has no modes: it is the day audit (8 turns for a concept)', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      expect(api.debugMaxTurns(1), 8);
    });

    testWidgets('the input: Explain it in your own words…, no ⊕, ∿ is there', (tester) async {
      await pumpAudit(tester, api, 1);
      expect(find.text('Explain it in your own words…'), findsOneWidget);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsOneWidget);
      expect(inputVisible(tester), isTrue);
    });

    testWidgets('while it starts: a loading line', (tester) async {
      final slow = _SlowStartApi();
      await slow.generateCourse(const GenerateRequest(topic: 'math'));
      await tester.binding.setSurfaceSize(wideScreen);
      tester.view.physicalSize = wideScreen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(child: const AuditScene(skillId: 1), api: slow));
      await tester.pump();
      expect(find.text('Calling the Auditor…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Calling the Auditor…'), findsNothing);
    });

    testWidgets('a locked node cannot be audited: the error with a retry', (tester) async {
      await pumpAudit(tester, api, 5);
      expect(find.text('This node is locked. Clear the nodes before it first.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('← goes back to scene 4 (the node) from the stage', (tester) async {
      await pumpAudit(tester, api, 1);
      await tester.tap(find.byKey(const Key('audit-back')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/1'), findsOneWidget);
    });
  });

  group('the dialogue', () {
    testWidgets('one column: the current question is the headline, earlier turns step back', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      final opening = bubble(tester);
      await say(tester, 'Here is how I would explain it');
      expect(bubble(tester), isNot(opening));
      expect(bubble(tester), contains('most important term'));
      expect(find.text('Here is how I would explain it'), findsOneWidget); // once, in the column
      expect(qaLines(tester), [
        'Auditor',
        opening,
        'Here is how I would explain it',
        'Auditor',
        bubble(tester),
      ]);
      // The answer is a bubble on the right; the earlier question is a plain line,
      // the current one the headline in the display serif.
      expect(find.byKey(const Key('audit-answer')), findsOneWidget);
      expect(find.byKey(const Key('audit-line')), findsOneWidget);
      expect(find.byKey(const Key('audit-bubble')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('audit-bubble-text'))).style?.fontFamily,
        AppFonts.display,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('audit-answer'))).dx,
        greaterThan(tester.getTopLeft(find.byKey(const Key('audit-bubble'))).dx),
      );
      expect(inputText(tester), '');
    });

    testWidgets(
      'while she thinks: the answer is already in the column, the shimmer waits below it',
      (
        tester,
      ) async {
        final slow = _SlowTurnApi();
        await slow.generateCourse(const GenerateRequest(topic: 'math'));
        await pumpAudit(tester, slow, 6);
        await type(tester, 'ans');
        await tester.tap(find.byKey(const Key('send')));
        await tester.pump();
        expect(find.byKey(const Key('thinking-shimmer')), findsOneWidget);
        expect(find.byKey(const Key('typing-dots')), findsNothing);
        expect(find.byKey(const Key('audit-bubble-text')), findsNothing);
        expect(find.descendant(of: qa, matching: find.text('ans')), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const Key('thinking-shimmer'))).dy,
          greaterThan(tester.getTopLeft(find.text('ans')).dy),
        );
        // The field stays open for the next answer; only sending waits.
        expect(tester.widget<TextField>(find.byKey(const Key('stage-input'))).enabled, isNot(isFalse));
        expect(avatar(tester).state, AvatarState.thinking);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('thinking-shimmer')), findsNothing);
        expect(find.text('ans'), findsOneWidget); // still once, in the column
      },
    );

    testWidgets('a long answer can be typed over several lines', (tester) async {
      await pumpAudit(tester, api, 1);
      final field = tester.widget<TextField>(find.byKey(const Key('stage-input')));
      expect(field.maxLines, greaterThan(1));
      expect(field.textInputAction, TextInputAction.send);
    });

    testWidgets('no turn counter, no mode pill, no panels', (tester) async {
      await pumpAudit(tester, api, 1);
      await say(tester, 'ans');
      expect(find.byKey(const Key('audit-turns')), findsNothing);
      expect(find.textContaining('/8'), findsNothing);
      expect(find.text('Day'), findsNothing);
      expect(find.text('Night'), findsNothing);
    });
  });

  group('a pass', () {
    testWidgets(
      'happy face and Cleared! {score} pts · +{xp} XP in her bubble; the input goes away',
      (
        tester,
      ) async {
        await pumpAudit(tester, api, 6);
        await passIt(tester);
        await closeCelebration(tester); // the card floats over the column
        final v = (await api.listAudits()).first;
        expect(textOf(tester, 'verdict-title'), 'Cleared.');
        expect(textOf(tester, 'verdict-score'), '${v.score}');
        expect(textOf(tester, 'verdict-xp'), matches(r'^\+\d+ XP$'));
        expect(avatar(tester).mood, AvatarMood.happy);
        expect(avatar(tester).agent, 'auditor');
        expect(inputVisible(tester), isFalse);
        // The next node of the learning order opened.
        expect((await api.getSkillOverview(7)).skill.status, SkillStatus.available);
        expect(find.text('Passed'), findsOneWidget); // the chip in the title bar
        expect(find.byKey(const Key('audit-next')), findsNothing); // no lesson card for a pass
      },
    );

    testWidgets('the XP is the reward of the server', (tester) async {
      await pumpAudit(tester, api, 1);
      await passIt(tester);
      final xp = (await api.getBriefing()).facts.xp.total;
      expect(find.descendant(of: celebration, matching: find.text('+$xp XP')), findsOneWidget);
      await closeCelebration(tester);
      expect(textOf(tester, 'verdict-xp'), '+$xp XP');
    });

    testWidgets('no retry button, no map button; the data is refreshed', (tester) async {
      await pumpAudit(tester, api, 1);
      await passIt(tester);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byKey(const Key('audit-next')), findsNothing);
      expect(find.byKey(const Key('audit-retry')), findsNothing);
    });

    testWidgets('the left panel and the data are refreshed', (tester) async {
      final state = AppState();
      await pumpAudit(tester, api, 1, state: state);
      final before = state.dataRevision;
      await passIt(tester);
      expect(state.dataRevision, greaterThan(before));
      expect(find.text('Lv 1 · 1/5'), findsOneWidget);
      expect(find.text('Cleared 1/12'), findsOneWidget);
      expect(
        tester
            .widgetList<FractionallySizedBox>(find.byKey(const Key('stat-bar-fill')))
            .elementAt(1)
            .widthFactor,
        closeTo(1 / 12, 1e-9),
      );
    });
  });

  group('the celebration card', () {
    testWidgets(
      'floats in the middle of the stage with Boss cleared!, the score and +N XP in green',
      (
        tester,
      ) async {
        await pumpAudit(tester, api, 1);
        expect(celebration, findsNothing);
        await passIt(tester);
        expect(celebration, findsOneWidget);
        final verdict = (await api.listAudits()).first;
        expect(find.text('Boss cleared!'), findsOneWidget); // the root node is a boss
        expect(find.text('${verdict.score} pts'), findsOneWidget);
        final xp = (await api.getBriefing()).facts.xp.total;
        final xpText = tester.widget<Text>(find.byKey(const Key('celebration-xp')));
        expect(xpText.data, '+$xp XP');
        expect(xpText.style!.color, AppColors.success);
        // Gradient title and sparkles.
        expect(find.descendant(of: celebration, matching: find.byType(ShaderMask)), findsOneWidget);
        expect(find.byKey(const Key('celebration-sparkles')), findsOneWidget);
        // A white floating card, radius 20, with the float shadow.
        final decoration = tester.widget<DecoratedBox>(celebration).decoration as BoxDecoration;
        expect(decoration.color, AppColors.surface);
        expect(decoration.borderRadius, BorderRadius.circular(20));
        expect(decoration.boxShadow, AppShadows.float);
        // In the middle of the stage panel, horizontally.
        final stage = tester.getRect(find.byKey(const Key('stage-panel')));
        expect(tester.getCenter(celebration).dx, closeTo(stage.center.dx, 2));
        expect(tester.getTopLeft(celebration).dy, greaterThan(stage.top));
        expect(tester.getBottomLeft(celebration).dy, lessThan(stage.bottom));
        // She is happy behind it.
        expect(avatar(tester).mood, AvatarMood.happy);
      },
    );

    testWidgets('a level up shows Lv N → N+1 (the stage data was refreshed)', (tester) async {
      // The first four of the learning order; Quadratic Functions (10) is next.
      for (final id in [6, 7, 5, 9]) {
        await passAudit(api, id);
      }
      await pumpAudit(tester, api, 10);
      expect(find.text('Lv 1 · 4/5'), findsOneWidget);
      await passIt(tester);
      expect(find.byKey(const Key('celebration-level')), findsOneWidget);
      expect(find.text('Lv 1 → 2'), findsOneWidget);
      expect(find.text('Lv 2 · 0/5'), findsOneWidget); // the left panel agrees
    });

    testWidgets('no level up, no Lv chip', (tester) async {
      await pumpAudit(tester, api, 1);
      await passIt(tester);
      expect(find.byKey(const Key('celebration-level')), findsNothing);
      expect(find.descendant(of: celebration, matching: find.textContaining('→')), findsNothing);
    });

    testWidgets('the newly unlocked nodes are blue chips; a tap opens that node (scene 4)', (
      tester,
    ) async {
      await pumpAudit(tester, api, 6);
      await passIt(tester);
      // Discriminant opens the next node of the order, Roots and Coefficients.
      expect(find.text('New nodes unlocked'), findsOneWidget);
      expect(find.byKey(const Key('unlocked-7')), findsOneWidget);
      expect(textsIn(tester, celebration), contains('Roots and Coefficients'));
      final chip = tester.widget<Material>(
        find
            .descendant(of: find.byKey(const Key('unlocked-7')), matching: find.byType(Material))
            .first,
      );
      expect(chip.color, AppColors.primarySoft);
      await tester.tap(find.byKey(const Key('unlocked-7')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/7'), findsOneWidget);
    });

    testWidgets('a pass that opens nothing has no chips', (tester) async {
      // The root, opened by hand: the next node (6) is open already.
      await pumpAudit(tester, api, 1);
      await passIt(tester);
      expect(celebration, findsOneWidget);
      expect(find.text('New nodes unlocked'), findsNothing);
    });

    testWidgets('Close puts it away and stays on the result; Back to node goes to scene 4', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      await passIt(tester);
      await tester.tap(find.byKey(const Key('celebration-close')));
      await tester.pumpAndSettle();
      expect(celebration, findsNothing);
      expect(textOf(tester, 'verdict-title'), 'Cleared.');
      expect(avatar(tester).mood, AvatarMood.happy);
      // A fresh pass in a new scene, then Back to node.
      await pumpAudit(tester, api, 6);
      await passIt(tester);
      await tester.tap(find.byKey(const Key('celebration-continue')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/6'), findsOneWidget);
    });

    testWidgets('a failing unlock lookup only leaves the chips out', (tester) async {
      await pumpAudit(tester, api, 1);
      await say(tester, longAnswer);
      // The left panel's quests read the skills as well: fail every lookup.
      api.failNext(method: 'listSkills', times: 4);
      await say(tester, longAnswer);
      expect(celebration, findsOneWidget);
      expect(find.text('New nodes unlocked'), findsNothing);
    });

    testWidgets('a fail has no celebration', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      expect(celebration, findsNothing);
    });

    testWidgets('on a phone it fits and nothing overflows', (tester) async {
      await pumpAudit(tester, api, 1, size: phoneScreen);
      await passIt(tester);
      expect(celebration, findsOneWidget);
      expect(tester.getSize(celebration).width, lessThanOrEqualTo(phoneScreen.width));
      expect(tester.takeException(), isNull);
    });
  });

  group('CelebrationCard on its own', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

    CelebrationCard card({bool? animate, int? before, int? after}) => CelebrationCard(
      score: 88,
      xp: 20,
      levelBefore: before,
      levelAfter: after,
      unlocked: const [UnlockedNode(id: 3, title: 'Discriminant')],
      animate: animate,
      onClose: () {},
      onContinue: () {},
      onOpenSkill: (_) {},
    );

    testWidgets('leveledUp needs both levels and a rise', (tester) async {
      expect(card().leveledUp, isFalse);
      expect(card(before: 2, after: 2).leveledUp, isFalse);
      expect(card(before: 2).leveledUp, isFalse);
      expect(card(before: 2, after: 3).leveledUp, isTrue);
    });

    testWidgets('it pops in and the sparkles burst when animated, and are still otherwise', (
      tester,
    ) async {
      Avatar.animationsEnabled = true;
      await tester.pumpWidget(host(card(animate: true)));
      expect(tester.hasRunningAnimations, isTrue);
      final start = tester
          .widget<Opacity>(
            find.descendant(of: find.byType(CelebrationCard), matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(start, lessThan(1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(of: find.byType(CelebrationCard), matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        1,
      );
      await tester.pumpWidget(host(card(animate: false)));
      expect(tester.hasRunningAnimations, isFalse);
      Avatar.animationsEnabled = false;
    });
  });

  group('a fail', () {
    testWidgets('angry face and the verdict card: Not yet., the score, the comment', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      expect(textOf(tester, 'verdict-title'), 'Not yet.');
      expect(textOf(tester, 'verdict-score'), '${(await api.listAudits()).first.score}');
      expect(
        textOf(tester, 'verdict-comment'),
        'The answer stops at the conclusion and lacks reasons.',
      );
      expect(find.byKey(const Key('audit-bubble-text')), findsNothing); // the card is the line
      expect(avatar(tester).mood, AvatarMood.angry);
      expect(avatar(tester).agent, 'auditor');
      expect(inputVisible(tester), isFalse);
      expect(find.byKey(const Key('audit-next')), findsOneWidget);
    });

    testWidgets('the card lists every gap; there are no search buttons', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      final gaps = (await api.listAudits()).first;
      expect(find.text('What was missing'), findsOneWidget);
      expect(
        find.descendant(
          of: verdictCard,
          matching: find.textContaining('You stated the definition'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('verdict-gap-1')), findsOneWidget);
      expect(find.text('Find materials'), findsNothing);
      expect(gaps.status, AuditStatus.failed);
    });

    testWidgets('Make a lesson card goes away once the Recorder asks', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audit-next')), findsNothing);
      expect(find.byKey(const Key('audit-done')), findsOneWidget);
    });

    testWidgets('→ brings the Recorder, who asks What did you misunderstand?', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      expect(bubble(tester), 'What did you misunderstand?');
      expect(avatar(tester).agent, 'recorder');
      expect(avatar(tester).mood, AvatarMood.neutral);
      expect(inputVisible(tester), isTrue);
      expect(tester.widget<TextField>(find.byKey(const Key('stage-input'))).enabled, isNot(isFalse));
      expect(find.text('What did you get wrong?…'), findsOneWidget);
    });

    testWidgets(
      'the answer in the input bar becomes a lesson card, which flips over in the stage',
      (
        tester,
      ) async {
        await pumpAudit(tester, api, 1);
        await failIt(tester);
        await tester.tap(find.byKey(const Key('audit-next')));
        await tester.pumpAndSettle();
        await say(tester, 'I thought memorizing the definition was enough');
        expect(bubble(tester), 'Lesson card created.');
        expect(avatar(tester).agent, 'recorder');
        expect(inputVisible(tester), isFalse);
        // The lesson card exists on the server, with what she wrote.
        final session = (await api.listAudits()).first;
        expect(session.status, AuditStatus.failed);
        await expectLater(
          api.submitReflection(session.id, 'again'),
          throwsA(isA<ApiException>()), // already has a card
        );
      },
    );

    testWidgets('the Recorder\'s question, the reflection and the card are in Audit log', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      await say(tester, 'I thought memorizing the definition was enough');
      final lines = qaLines(tester);
      final asked = lines.indexOf('What did you misunderstand?') - 1;
      expect(lines.sublist(asked, asked + 5), [
        'Recorder',
        'What did you misunderstand?',
        'I thought memorizing the definition was enough',
        'Recorder',
        'Lesson card created.',
      ]);
    });

    testWidgets('the lesson card flips to its front: title, body, the misconception in red', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      expect(find.byKey(const Key('lesson-card-front')), findsNothing);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      await say(tester, 'I thought memorizing the definition was enough');
      expect(find.byType(LessonCard), findsOneWidget);
      expect(find.byKey(const Key('lesson-card-front')), findsOneWidget);
      expect(find.byKey(const Key('lesson-card-back')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('lesson-title'))).data,
        'Revisit “High School Math”',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('lesson-body'))).data,
        'When I explain “High School Math”, I give the reason before the conclusion.',
      );
      final misconception = tester.widget<Text>(find.byKey(const Key('lesson-misconception')));
      expect(misconception.data, 'I thought memorizing the definition was enough');
      expect(misconception.style!.color, AppColors.danger);
      expect(misconception.style!.fontSize, 12);
      // The card is right below the Recorder's line.
      expect(
        tester.getTopLeft(find.byType(LessonCard)).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('audit-bubble'))).dy),
      );
    });

    testWidgets('in the background: material for the first gap shows up in scene 4', (
      tester,
    ) async {
      final state = AppState();
      await pumpAudit(tester, api, 1, state: state);
      await failIt(tester);
      expect((await api.getSkillOverview(1)).materials, isEmpty);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      final before = state.dataRevision;
      await say(tester, 'I thought memorizing the definition was enough');
      final materials = (await api.getSkillOverview(1)).materials;
      expect(materials, hasLength(1));
      expect(materials.single.gap, 'You stated the definition but not why it works.');
      expect(state.dataRevision, greaterThan(before));
    });

    testWidgets('a failing background search is ignored', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      api.failNext(method: 'createSearchPlan');
      await say(tester, 'I thought memorizing the definition was enough');
      expect(bubble(tester), 'Lesson card created.');
      expect(find.byKey(const Key('input-error')), findsNothing);
      expect(tester.takeException(), isNull);
      expect((await api.getSkillOverview(1)).materials, isEmpty);
    });

    testWidgets('a failing reflection: the bubble says so and the text goes back', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await tester.tap(find.byKey(const Key('audit-next')));
      await tester.pumpAndSettle();
      api.failNext(method: 'submitReflection');
      await say(tester, 'I thought memorizing the definition was enough');
      expect(bubble(tester), 'Something went wrong on our side. Please try again.');
      expect(avatar(tester).agent, 'recorder');
      expect(inputText(tester), 'I thought memorizing the definition was enough');
      expect(inputVisible(tester), isTrue);
      // Retry.
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(bubble(tester), 'Lesson card created.');
      expect(find.byKey(const Key('lesson-card-front')), findsOneWidget);
    });

    testWidgets('a retry is a new audit from scene 4', (tester) async {
      await pumpAudit(tester, api, 1);
      await failIt(tester);
      await pumpAudit(tester, api, 1); // back from scene 4, → again
      expect(bubble(tester), contains('Which problems call for “High School Math”'));
      expect(find.byKey(const Key('chat-user-bubble')), findsNothing);
      expect(avatar(tester).mood, AvatarMood.stern);
      expect((await api.listAudits()), hasLength(2));
    });
  });

  group('errors on the way', () {
    testWidgets('502: her bubble says so, the text goes back to the input, the Q&A is unchanged', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      final opening = bubble(tester);
      api.failNext(method: 'submitTurn');
      await say(tester, 'My explanation');
      expect(bubble(tester), 'Something went wrong on our side. Please try again.');
      expect(
        tester.widget<Text>(find.byKey(const Key('audit-bubble-text'))).style!.color,
        AppColors.danger,
      );
      expect(inputText(tester), 'My explanation');
      expect(qaLines(tester), [
        'Auditor',
        opening,
        'Something went wrong on our side. Please try again.',
      ]);
      expect(avatar(tester).mood, AvatarMood.stern);

      // Retry with the same text.
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(bubble(tester), contains('most important term'));
      expect(
        tester.widget<Text>(find.byKey(const Key('audit-bubble-text'))).style!.color,
        isNot(AppColors.danger),
      );
      expect(qaLines(tester).where((t) => t == 'My explanation'), hasLength(1));
    });

    testWidgets('a closed session: the bubble says so, the text comes back, the input is off', (
      tester,
    ) async {
      await pumpAudit(tester, api, 1);
      api.failNext(
        method: 'submitTurn',
        statusCode: 400,
        message: 'audit session is already closed',
      );
      await say(tester, 'My explanation');
      expect(bubble(tester), 'This audit has already ended.');
      expect(inputText(tester), 'My explanation');
      expect(inputVisible(tester), isFalse);
      expect(find.byKey(const Key('input-error')), findsNothing);
    });

    testWidgets('a network failure is shown in the bubble too', (tester) async {
      await pumpAudit(tester, api, 1);
      api.failNext(method: 'submitTurn', statusCode: null);
      await say(tester, 'My explanation');
      expect(bubble(tester), ApiException.networkText);
      expect(inputText(tester), 'My explanation');
    });
  });

  group('voice', () {
    testWidgets('what is heard is the answer; the question is read aloud; a verdict ends it', (
      tester,
    ) async {
      final voice = FakeVoiceService();
      await pumpAudit(tester, api, 1, voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-wave-row')), findsOneWidget);

      voice.hear("I'm not sure");
      await tester.pumpAndSettle();
      expect(voice.spoken.single, contains('most important term'));
      expect(voice.listenCalls, 2);
      expect(find.byKey(const Key('voice-wave-row')), findsOneWidget);

      voice.hear("I'm not sure");
      await tester.pumpAndSettle();
      expect(voice.spoken.last, startsWith('Not quite.'));
      expect(textOf(tester, 'verdict-title'), 'Not yet.');
      expect(find.byKey(const Key('voice-wave-row')), findsNothing); // the loop ended
    });

    testWidgets('Esc leaves voice mode', (tester) async {
      final voice = FakeVoiceService();
      await pumpAudit(tester, api, 1, voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-wave-row')), findsNothing);
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
    });

    testWidgets('without speech support: a short message', (tester) async {
      await pumpAudit(tester, api, 1, voice: FakeVoiceService(available: false));
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(find.text("Voice mode isn't available on this device."), findsOneWidget);
    });
  });

  testWidgets('a phone: nothing overflows through a whole failed audit', (tester) async {
    await pumpAudit(tester, api, 1, size: phoneScreen);
    await failIt(tester);
    await tester.tap(find.byKey(const Key('audit-next')));
    await tester.pumpAndSettle();
    await say(tester, 'I thought memorizing the definition was enough');
    expect(tester.takeException(), isNull);
    expect(bubble(tester), 'Lesson card created.');
  });
}

/// Starting an audit takes 200 ms.
class _SlowStartApi extends FakeApiClient {
  _SlowStartApi() : super(latency: Duration.zero);

  @override
  Future<AuditStart> startAudit(int skillId, {String mode = 'day', bool testOut = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return super.startAudit(skillId, mode: mode, testOut: testOut);
  }
}

/// The auditor answers after 200 ms.
class _SlowTurnApi extends FakeApiClient {
  _SlowTurnApi() : super(latency: Duration.zero);

  @override
  Future<TurnResult> submitTurn(int sessionId, String content) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return super.submitTurn(sessionId, content);
  }
}
