// The NotebookLM frame every scene shares: three white panels on a canvas, the
// left panel “My character” with numbers, the chat panel only on scenes 4, 4-1 and
// 5, folding side panels, drawers on narrow screens, the ◎ button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/testing/fake_auth.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/panel_layout.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder get leftPanel => find.byKey(const Key('left-panel'));
Finder get historyPanel => find.byKey(const Key('history-panel'));

double fillOf(WidgetTester tester, int index) => tester
    .widgetList<FractionallySizedBox>(find.byKey(const Key('stat-bar-fill')))
    .elementAt(index)
    .widthFactor!;

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
  });

  group('the left panel is on every scene', () {
    final scenes = <String, Widget Function()>{
      'scene 1': () => const HomeScene(),
      'scene 2': () => const MapScene(),
      'scene 4': () => const SkillScene(skillId: 1),
      'scene 4-1': () => const AuditScene(skillId: 6),
    };
    for (final entry in scenes.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpScene(tester, entry.value(), api: api);
        expect(leftPanel, findsOneWidget);
        expect(find.text('My character'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.byKey(const Key('settings-button')), findsOneWidget);
        expect(find.byType(StatBar), findsNWidgets(3));
      });
    }

    testWidgets('scene 5 (after the first message)', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api);
      await say(tester, 'Hello there');
      expect(leftPanel, findsOneWidget);
      expect(find.byType(StatBar), findsNWidgets(3));
    });

    testWidgets('three white radius-20 panels with 12 px gaps on the canvas', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 1), api: api);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        AppColors.canvas,
      );
      final left = tester.getRect(find.byKey(const Key('collapse-left')).first);
      expect(left, isNotNull);
      final leftPanel = tester.getRect(
        find.ancestor(of: find.byKey(const Key('left-panel')), matching: find.byType(AppPanel)),
      );
      final stage = tester.getRect(find.byKey(const Key('stage-panel')));
      final right = tester.getRect(historyPanel);
      expect(leftPanel.width, 280);
      expect(right.width, 380);
      expect(leftPanel.left, 12);
      expect(stage.left - leftPanel.right, 12);
      expect(right.left - stage.right, 12);
      expect(1440 - right.right, 12);
      expect(leftPanel.top, 12);
      expect(900 - leftPanel.bottom, 12);
      for (final box in [
        ...tester.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(AppPanel), matching: find.byType(DecoratedBox)),
        ),
        tester.widget<DecoratedBox>(find.byKey(const Key('stage-panel'))),
      ].where((b) => (b.decoration as BoxDecoration).color == AppColors.sidebar)) {
        final d = box.decoration as BoxDecoration;
        expect(d.borderRadius, BorderRadius.circular(20));
        expect(d.border, isNull);
        expect(d.boxShadow, isNull);
      }
    });

    testWidgets('panel title bars are English: My character on the left', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('My character'), findsOneWidget);
      expect(find.byKey(const Key('panel-title')), findsOneWidget);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.byKey(const Key('panel-title')),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .height,
        56,
      );
    });
  });

  group('the stat bars', () {
    testWidgets('Lv, Cleared and Condition — labels with their numbers and 8 px bars', (
      tester,
    ) async {
      await passAudit(api, 6); // 1 of 12 mastered; 1 of 5 for the level
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('Lv 1 · 1/5'), findsOneWidget);
      expect(find.text('Cleared 1/12'), findsOneWidget);
      expect(find.text('Condition: No record'), findsOneWidget);
      expect(fillOf(tester, 0), closeTo(0.2, 1e-9));
      expect(fillOf(tester, 1), closeTo(1 / 12, 1e-9));
      expect(fillOf(tester, 2), 0); // no check-in: empty
      for (final bar in tester.widgetList<FractionallySizedBox>(
        find.byKey(const Key('stat-bar-fill')),
      )) {
        expect(bar.heightFactor, 1);
      }
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(find.byKey(const Key('stat-bar-fill')).at(i)).height, 8);
      }
      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('Cleared is green; the level bar is blue', (tester) async {
      await passAudit(api, 6);
      await pumpScene(tester, const MapScene(), api: api);
      Color colorOf(int i) => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(const Key('stat-bar-fill')).at(i),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(colorOf(0), AppColors.primary);
      expect(colorOf(1), AppColors.success);
      final clear = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('stat-clear')),
          matching: find.byKey(const Key('stat-label')),
        ),
      );
      expect(clear.style!.color, AppColors.success);
    });

    testWidgets('five cleared nodes make level 2: Lv 2 · 0/5', (tester) async {
      for (final id in [6, 7, 5, 9, 10]) {
        await passAudit(api, id); // the first five of the learning order
      }
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('Lv 2 · 0/5'), findsOneWidget);
      expect(find.text('Cleared 5/12'), findsOneWidget);
      expect(fillOf(tester, 0), 0);
    });

    testWidgets('condition: Good is full, Low is half and red', (tester) async {
      await api.checkInVoice('I slept eight hours last night.');
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('Condition: Good'), findsOneWidget);
      expect(fillOf(tester, 2), 1);
      Color barColor() => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(const Key('stat-bar-fill')).last,
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      Color labelColor() => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('stat-condition')),
              matching: find.byKey(const Key('stat-label')),
            ),
          )
          .style!
          .color!;
      expect(barColor(), AppColors.primary);
      expect(labelColor(), AppColors.textPrimary);

      await api.checkInVoice('I slept four hours last night.');
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('Condition: Low'), findsOneWidget);
      expect(fillOf(tester, 2), 0.5);
      expect(barColor(), AppColors.danger);
      expect(labelColor(), AppColors.danger);
    });
  });

  group('Today', () {
    testWidgets('without a check-in all three rows show —', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      final summary = find.byKey(const Key('today-summary'));
      expect(textsIn(tester, summary), ['Sleep', '—', 'Meals', '—', 'Journal', '—', 'My life →']);
    });

    testWidgets('My life → opens the life overview', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.ensureVisible(find.byKey(const Key('open-life')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-life')));
      await tester.pumpAndSettle();
      expect(find.text('route:/life'), findsOneWidget);
    });

    testWidgets('with a check-in: sleep, meal and the first two lines of the diary', (
      tester,
    ) async {
      await api.checkInVoice(
        'I slept six hours and had ramen for lunch.\nI am a bit tired.\nThird line',
      );
      await pumpScene(tester, const MapScene(), api: api);
      final texts = textsIn(tester, find.byKey(const Key('today-summary'))).toList();
      expect(texts[1], '6 h');
      expect(texts[3], 'lunch: ramen');
      expect(texts[5], contains('I am a bit tired.'));
      expect(texts[5], isNot(contains('Third line')));
    });

    testWidgets('a check-in sent in the chat refreshes it', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api);
      expect(textsIn(tester, find.byKey(const Key('today-summary'))).toList()[1], '—');
      await say(tester, 'I slept seven hours last night');
      expect(textsIn(tester, find.byKey(const Key('today-summary'))).toList()[1], '7 h');
    });
  });

  group('◎ the account menu', () {
    testWidgets('local mode: says so, offers the tutorial and the front page, no sign out', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.byIcon(Icons.adjust_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      expect(find.text('Local mode (no account)'), findsOneWidget);
      expect(find.byKey(const Key('settings-tutorial')), findsOneWidget);
      expect(find.byKey(const Key('settings-sign-out')), findsNothing);
      expect(find.byKey(const Key('settings-front-page')), findsOneWidget);
      expect(find.textContaining('route:'), findsNothing);
    });

    testWidgets('signed in: the email, and Sign out signs out', (tester) async {
      final auth = FakeAuthService(accounts: {'me@example.com': 'secret1'});
      await auth.signIn('me@example.com', 'secret1');
      await pumpScene(tester, const MapScene(), api: api, auth: auth);
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      expect(find.text('me@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      expect(auth.signedIn, isFalse);
    });

    testWidgets('Replay the tutorial clears the onboarded flag', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      expect((await api.getProfile()).onboarded, isTrue);
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-tutorial')));
      await tester.pumpAndSettle();
      expect((await api.getProfile()).onboarded, isFalse);
    });
  });

  group('the chat panel exists only on scenes 4 and 5', () {
    testWidgets('not on scene 1', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api);
      expect(historyPanel, findsNothing);
      expect(find.text('history'), findsNothing);
    });

    testWidgets('not on scene 2', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      expect(historyPanel, findsNothing);
    });

    testWidgets('scene 4: Attempts', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 1), api: api);
      expect(historyPanel, findsOneWidget);
      expect(find.text('Attempts'), findsOneWidget);
      expect(find.text('history'), findsNothing);
    });

    testWidgets('scene 4-1: none, the dialogue column is the log', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: api);
      expect(historyPanel, findsNothing);
      expect(find.text('Audit log'), findsNothing);
      expect(find.byKey(const Key('audit-qa')), findsOneWidget);
    });

    testWidgets('scene 5: Chat, appearing with the first message', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api);
      expect(historyPanel, findsNothing);
      await say(tester, 'Hello there');
      expect(historyPanel, findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('no English panel or section titles are left', (tester) async {
      for (final scene in [
        const HomeScene(),
        const MapScene(),
        const SkillScene(skillId: 1),
        const AuditScene(skillId: 6),
      ]) {
        await pumpScene(tester, scene, api: api);
        for (final english in ['history', "today's summary", 'node:', 'contents']) {
          expect(find.textContaining(english), findsNothing, reason: '$english in $scene');
        }
      }
    });
  });

  group('the side panels fold into a rail', () {
    Finder rail(String side) => find.byKey(Key('expand-$side'));

    testWidgets('left: fold and unfold; the content goes, the title is written sideways', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.byKey(const Key('collapse-left')), findsOneWidget);
      await tester.tap(find.byKey(const Key('collapse-left')));
      await tester.pumpAndSettle();
      expect(leftPanel, findsNothing);
      expect(rail('left'), findsOneWidget);
      expect(find.byKey(const Key('rail-title')), findsOneWidget);
      expect(tester.getSize(find.byType(PanelRail)).width, 56);
      // The stage took the room.
      expect(tester.getSize(find.byKey(const Key('stage-panel'))).width, greaterThan(1300));
      await tester.tap(rail('left'));
      await tester.pumpAndSettle();
      expect(leftPanel, findsOneWidget);
      expect(rail('left'), findsNothing);
    });

    testWidgets('right: fold and unfold the chat panel', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 1), api: api);
      await tester.tap(find.byKey(const Key('collapse-right')));
      await tester.pumpAndSettle();
      expect(historyPanel, findsNothing);
      expect(rail('right'), findsOneWidget);
      expect(find.text('Attempts'), findsOneWidget); // the rail title
      await tester.tap(rail('right'));
      await tester.pumpAndSettle();
      expect(historyPanel, findsOneWidget);
    });

    testWidgets('the choice is kept in memory across scenes', (tester) async {
      final layout = PanelLayout();
      await pumpScene(tester, const MapScene(), api: api, layout: layout);
      await tester.tap(find.byKey(const Key('collapse-left')));
      await tester.pumpAndSettle();
      expect(layout.leftCollapsed, isTrue);
      // Another scene, same session.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        buildTestApp(child: const SkillScene(skillId: 1), api: api, layout: layout),
      );
      await tester.pumpAndSettle();
      expect(rail('left'), findsOneWidget);
      expect(leftPanel, findsNothing);
      expect(rail('right'), findsNothing);
    });

    testWidgets('a 1000 px window with a chat panel keeps the stage roomy: left is a rail', (
      tester,
    ) async {
      await pumpScene(tester, const SkillScene(skillId: 1), api: api, size: const Size(1000, 800));
      expect(rail('left'), findsOneWidget);
      expect(historyPanel, findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('stage-panel'))).width, greaterThan(400));
      // The rail opens the panel as a drawer.
      await tester.tap(rail('left'));
      await tester.pumpAndSettle();
      expect(leftPanel, findsOneWidget);
    });
  });

  group('narrow screens (< 900 px): the columns become drawers', () {
    testWidgets('scene 1 and 2: only the left drawer', (tester) async {
      for (final scene in [const HomeScene(), const MapScene()]) {
        await pumpScene(tester, scene, api: api, size: phoneScreen);
        expect(leftPanel, findsNothing);
        expect(find.byKey(const Key('open-left-drawer')), findsOneWidget);
        expect(find.byKey(const Key('open-right-drawer')), findsNothing);
      }
    });

    testWidgets('the left drawer holds the same panel', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api, size: phoneScreen);
      await tester.tap(find.byKey(const Key('open-left-drawer')));
      await tester.pumpAndSettle();
      expect(leftPanel, findsOneWidget);
      expect(find.text('My character'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(StatBar), findsNWidgets(3));
    });

    testWidgets('scene 4: a right drawer with the history (4-1 has none)', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 6), api: api, size: phoneScreen);
      expect(find.byKey(const Key('open-right-drawer')), findsNothing);
      for (final scene in [const SkillScene(skillId: 1)]) {
        await pumpScene(tester, scene, api: api, size: phoneScreen);
        expect(historyPanel, findsNothing);
        await tester.tap(find.byKey(const Key('open-right-drawer')));
        await tester.pumpAndSettle();
        expect(historyPanel, findsOneWidget);
        expect(find.text('history'), findsNothing);
      }
    });

    testWidgets('scene 5: the right drawer appears once chatting', (tester) async {
      await pumpScene(tester, const HomeScene(), api: api, size: phoneScreen);
      await say(tester, 'Hello there');
      await tester.tap(find.byKey(const Key('open-right-drawer')));
      await tester.pumpAndSettle();
      expect(historyPanel, findsOneWidget);
      expect(find.text('Hello there'), findsWidgets); // the user's lines are listed there
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('no overflow on a phone, in any scene', (tester) async {
      final scenes = [
        const HomeScene(),
        const MapScene(),
        const SkillScene(skillId: 1),
        const AuditScene(skillId: 6),
      ];
      for (final scene in scenes) {
        await pumpScene(tester, scene, api: api, size: phoneScreen);
        expect(tester.takeException(), isNull, reason: '$scene');
      }
    });
  });

  group('wide screens have no menu buttons', () {
    testWidgets('no ☰ and no history button', (tester) async {
      await pumpScene(tester, const SkillScene(skillId: 1), api: api);
      expect(find.byKey(const Key('open-left-drawer')), findsNothing);
      expect(find.byKey(const Key('open-right-drawer')), findsNothing);
    });
  });

  group('what the mockup does not have', () {
    testWidgets('no proactive line, no dictation mic, no day/night, no turn counter', (
      tester,
    ) async {
      await pumpScene(tester, const HomeScene(), api: api);
      expect(find.byKey(const Key('proactive-bubble')), findsNothing);
      expect(find.byKey(const Key('mic')), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.byIcon(Icons.nightlight_round), findsNothing);
      expect(find.byIcon(Icons.wb_sunny_rounded), findsNothing);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      // (The only menu is the account menu ◎ in the left panel.)
      expect(
        find.descendant(
          of: find.byKey(const Key('stage-panel')),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.byType(Chip), findsNothing);
    });
  });
}
