// The left panel of the life-as-a-game layer (docs/ux-chat.md §6): the
// character sheet with inline editing, the foldable blocks and the daily
// quests.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/app/panel_layout.dart';
import 'package:self_infinity/features/chat/chat_controller.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/widgets/collapsible_section.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:provider/provider.dart';

import '../support/scene_helpers.dart';
import '../support/spy_api.dart';

Finder key(String k) => find.byKey(Key(k));

/// Taps a field, types [text] and presses Enter.
Future<void> editAndEnter(
  WidgetTester tester,
  String displayKey,
  String inputKey,
  String text,
) async {
  await tester.tap(key(displayKey));
  await tester.pump();
  await tester.enterText(key(inputKey), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String inputKey) =>
    tester.widget<TextField>(key(inputKey)).controller!.text;

/// The `done/total` counter of the Daily quests section (Main quests has its
/// own `n/3`).
Finder questCount(String text) => find.descendant(
  of: find.ancestor(of: find.text('Daily quests'), matching: find.byType(CollapsibleSection)),
  matching: find.text(text),
);

void main() {
  group('character sheet: empty', () {
    testWidgets('identity placeholder, Win condition, Stakes and Rules with muted hints', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: FakeApiClient(latency: Duration.zero));
      expect(find.text('I am the type of person who…'), findsOneWidget);
      expect(find.text('Win condition'), findsOneWidget);
      expect(find.text('Stakes'), findsOneWidget);
      expect(find.text('Rules'), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
      expect(find.text('What does winning look like?'), findsOneWidget);
      expect(find.text('What if nothing changes?'), findsOneWidget);
      expect(find.text('Add a rule'), findsOneWidget);
      // The placeholders are muted.
      for (final t in ['I am the type of person who…', 'What does winning look like?']) {
        expect(tester.widget<Text>(find.text(t)).style!.color, AppColors.textTertiary);
      }
      expect(find.byType(TextField), findsOneWidget); // only the search bar
    });

    testWidgets('top to bottom: sheet, stats, Daily quests, Today', (tester) async {
      await pumpScene(tester, const MapScene(), api: FakeApiClient(latency: Duration.zero));
      final order = [
        find.text('Character sheet'),
        find.text('Stats'),
        find.text('Daily quests'),
        find.text('Today'),
      ].map((f) => tester.getTopLeft(f).dy).toList();
      expect(order, [...order]..sort());
      expect(order.toSet(), hasLength(4));
      // The three bars are still there, unchanged.
      expect(find.byKey(const Key('stat-level')), findsOneWidget);
      expect(find.byKey(const Key('stat-clear')), findsOneWidget);
      expect(find.byKey(const Key('stat-condition')), findsOneWidget);
    });

    testWidgets('1440x900: nothing overflows and the settings button stays visible', (
      tester,
    ) async {
      final api = SpyApi();
      await api.updateProfile(
        identity: 'I am the type of person who ships.',
        vision: 'v' * 280,
        antiVision: 'a' * 280,
        rules: List.generate(5, (i) => 'Rule number $i'),
      );
      await pumpScene(tester, const MapScene(), api: api);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(key('settings-button'));
      expect(button.bottom, lessThanOrEqualTo(900));
      expect(button.top, greaterThan(500));
    });
  });

  group('character sheet: editing in place', () {
    late SpyApi api;

    setUp(() async {
      api = SpyApi();
    });

    testWidgets('saved values from the server are shown', (tester) async {
      await api.updateProfile(
        identity: 'I am the type of person who explains things first.',
        vision: 'A clear mind',
        antiVision: 'Drifting',
        rules: ['No phone in bed', 'Audit before lunch'],
      );
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('I am the type of person who explains things first.'), findsOneWidget);
      expect(find.text('A clear mind'), findsOneWidget);
      expect(find.text('Drifting'), findsOneWidget);
      expect(find.text('No phone in bed'), findsOneWidget);
      expect(find.text('Audit before lunch'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('What does winning look like?'), findsNothing);
      expect(find.text('Add a rule'), findsOneWidget);
    });

    testWidgets('tap → a field; Enter saves via PUT /profile and shows a saved mark', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-vision'));
      await tester.pump();
      expect(key('vision-input'), findsOneWidget);
      await editAndEnter(tester, 'field-vision', 'vision-input', 'A clear mind');
      expect(api.profileSaves, 1);
      expect((await api.getProfile()).vision, 'A clear mind');
      expect(key('vision-input'), findsNothing);
      expect(find.text('A clear mind'), findsOneWidget);
      expect(key('saved-mark'), findsOneWidget);
      // The mark fades after a moment.
      await tester.pump(const Duration(seconds: 3));
      expect(key('saved-mark'), findsNothing);
    });

    testWidgets('Stakes saves anti_vision and keeps the win condition', (tester) async {
      await api.updateProfile(vision: 'A clear mind');
      await pumpScene(tester, const MapScene(), api: api);
      await editAndEnter(tester, 'field-anti-vision', 'anti-vision-input', 'Drifting');
      final p = await api.getProfile();
      expect(p.antiVision, 'Drifting');
      expect(p.vision, 'A clear mind');
    });

    testWidgets('leaving the field (blur) saves as well', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-vision'));
      await tester.pump();
      await tester.enterText(key('vision-input'), 'Ship the capstone');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect((await api.getProfile()).vision, 'Ship the capstone');
      expect(find.text('Ship the capstone'), findsOneWidget);
      expect(api.profileSaves, 1);
    });

    testWidgets('an unchanged text is not saved; Esc cancels what was typed', (tester) async {
      await api.updateProfile(vision: 'A clear mind');
      api.profileSaves = 0;
      await pumpScene(tester, const MapScene(), api: api);
      // Unchanged + Enter.
      await tester.tap(key('field-vision'));
      await tester.pump();
      expect(fieldText(tester, 'vision-input'), 'A clear mind'); // starts from the value
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.profileSaves, 0);
      // Typed + Esc.
      await tester.tap(key('field-vision'));
      await tester.pump();
      await tester.enterText(key('vision-input'), 'Something else');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('vision-input'), findsNothing);
      expect(find.text('A clear mind'), findsOneWidget);
      expect(api.profileSaves, 0);
    });

    testWidgets('emptying a field saves the empty text and brings the placeholder back', (
      tester,
    ) async {
      await api.updateProfile(vision: 'A clear mind');
      await pumpScene(tester, const MapScene(), api: api);
      await editAndEnter(tester, 'field-vision', 'vision-input', '   ');
      expect((await api.getProfile()).vision, '');
      expect(find.text('What does winning look like?'), findsOneWidget);
    });

    testWidgets('the identity line starts from “I am the type of person who ”', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-identity'));
      await tester.pump();
      expect(fieldText(tester, 'identity-input'), 'I am the type of person who ');
      // Leaving it as it is saves nothing.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.profileSaves, 0);
      expect(find.text('I am the type of person who…'), findsOneWidget);
      // Finishing the sentence saves it.
      await editAndEnter(
        tester,
        'field-identity',
        'identity-input',
        'I am the type of person who explains it first.',
      );
      expect((await api.getProfile()).identity, 'I am the type of person who explains it first.');
    });

    testWidgets('limit: at most 280 characters, a counter appears near it', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-vision'));
      await tester.pump();
      await tester.enterText(key('vision-input'), 'x' * 100);
      await tester.pump();
      expect(find.text('100/280'), findsNothing); // quiet while far from the limit
      await tester.enterText(key('vision-input'), 'x' * 400);
      await tester.pump();
      expect(fieldText(tester, 'vision-input'), hasLength(280));
      expect(find.text('280/280'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await api.getProfile()).vision, hasLength(280));
    });

    testWidgets('a failed save keeps the field open with what was typed and says so', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-vision'));
      await tester.pump();
      await tester.enterText(key('vision-input'), 'A clear mind');
      api.failNext(method: 'updateProfile', statusCode: 422);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(key('vision-input'), findsOneWidget);
      expect(fieldText(tester, 'vision-input'), 'A clear mind');
      expect(
        tester.widget<Text>(key('field-error')).data,
        "Couldn't save. Please check what you entered.",
      );
      expect(tester.widget<Text>(key('field-error')).style!.color, AppColors.danger);
      expect(key('saved-mark'), findsNothing);
      expect((await api.getProfile()).vision, '');

      // Enter again: it works and the error goes away.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(key('field-error'), findsNothing);
      expect((await api.getProfile()).vision, 'A clear mind');
    });

    testWidgets('a network failure says the server cannot be reached', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('field-anti-vision'));
      await tester.pump();
      await tester.enterText(key('anti-vision-input'), 'Drifting');
      api.failNext(method: 'updateProfile', statusCode: null);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(key('field-error')).data,
        "Couldn't save. Can't reach the server. Check your connection.",
      );
    });

    testWidgets('a profile that fails to load leaves the sheet empty but editable', (
      tester,
    ) async {
      api.failNext(method: 'getProfile');
      await pumpScene(tester, const MapScene(), api: api);
      expect(find.text('What does winning look like?'), findsOneWidget);
      await editAndEnter(tester, 'field-vision', 'vision-input', 'A clear mind');
      expect((await api.getProfile()).vision, 'A clear mind');
    });
  });

  group('rules', () {
    late SpyApi api;

    setUp(() {
      api = SpyApi();
    });

    testWidgets('Add a rule → type → Enter appends it', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('rule-add'));
      await tester.pump();
      expect(key('rule-new-input'), findsOneWidget);
      expect(find.text('e.g. No phone before the first audit'), findsOneWidget);
      await tester.enterText(key('rule-new-input'), 'No phone in bed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await api.getProfile()).rules, ['No phone in bed']);
      expect(find.text('No phone in bed'), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
      expect(key('rule-new-input'), findsNothing);
      expect(key('rule-add'), findsOneWidget);
    });

    testWidgets('an empty new rule is dropped without a call', (tester) async {
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('rule-add'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.profileSaves, 0);
      expect(key('rule-new-input'), findsNothing);
      expect(key('rule-add'), findsOneWidget);
    });

    testWidgets('at most five: the add button goes away; a rule is at most 120 characters', (
      tester,
    ) async {
      await api.updateProfile(rules: ['a', 'b', 'c', 'd']);
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('rule-add'));
      await tester.pump();
      await tester.enterText(key('rule-new-input'), 'e' * 200);
      await tester.pump();
      expect(fieldText(tester, 'rule-new-input'), hasLength(120));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await api.getProfile()).rules, hasLength(5));
      expect(find.text('5/5'), findsOneWidget);
      expect(key('rule-add'), findsNothing);
    });

    testWidgets('✕ removes a rule', (tester) async {
      await api.updateProfile(rules: ['No phone in bed', 'Audit before lunch']);
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('rule-remove-0'));
      await tester.pumpAndSettle();
      expect((await api.getProfile()).rules, ['Audit before lunch']);
      expect(find.text('No phone in bed'), findsNothing);
      expect(find.text('Audit before lunch'), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
    });

    testWidgets('tap a rule to edit it; emptying it removes it', (tester) async {
      await api.updateProfile(rules: ['No phone in bed', 'Audit before lunch']);
      await pumpScene(tester, const MapScene(), api: api);
      await tester.tap(key('rule-0'));
      await tester.pump();
      expect(fieldText(tester, 'rule-input-0'), 'No phone in bed');
      await tester.enterText(key('rule-input-0'), 'No phone after 10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await api.getProfile()).rules, ['No phone after 10', 'Audit before lunch']);

      await tester.tap(key('rule-1'));
      await tester.pump();
      await tester.enterText(key('rule-input-1'), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await api.getProfile()).rules, ['No phone after 10']);
    });

    testWidgets('a failed removal keeps the rule and shows the error', (tester) async {
      await api.updateProfile(rules: ['No phone in bed']);
      await pumpScene(tester, const MapScene(), api: api);
      api.failNext(method: 'updateProfile');
      await tester.tap(key('rule-remove-0'));
      await tester.pumpAndSettle();
      expect(find.text('No phone in bed'), findsOneWidget);
      expect(
        tester.widget<Text>(key('rules-error')).data,
        "Couldn't save. Something went wrong on our side. Please try again.",
      );
    });
  });

  group('the blocks fold', () {
    testWidgets('all start open; a tap folds one and the state survives a scene change', (
      tester,
    ) async {
      final layout = PanelLayout();
      final api = FakeApiClient(latency: Duration.zero);
      await pumpScene(tester, const MapScene(), api: api, layout: layout);
      expect(key('character-sheet'), findsOneWidget);
      expect(key('stat-level'), findsOneWidget);
      expect(key('today-summary'), findsOneWidget);
      expect(find.text('Get today\'s quests →'), findsOneWidget);

      await tester.tap(key('toggle-character'));
      await tester.tap(key('toggle-today'));
      await tester.pumpAndSettle();
      expect(key('character-sheet'), findsNothing);
      expect(key('today-summary'), findsNothing);
      expect(key('stat-level'), findsOneWidget);
      expect(find.text('Character sheet'), findsOneWidget); // the header stays

      // Another scene, same layout: still folded.
      await pumpScene(tester, const HomeScene(), api: api, layout: layout);
      expect(key('character-sheet'), findsNothing);
      await tester.tap(key('toggle-character'));
      await tester.pumpAndSettle();
      expect(key('character-sheet'), findsOneWidget);
    });

    testWidgets('Rules folds inside the sheet', (tester) async {
      await pumpScene(tester, const MapScene(), api: FakeApiClient(latency: Duration.zero));
      expect(key('rule-add'), findsOneWidget);
      await tester.tap(key('toggle-rules'));
      await tester.pumpAndSettle();
      expect(key('rule-add'), findsNothing);
      expect(key('field-vision'), findsOneWidget);
    });
  });

  group('Daily quests', () {
    testWidgets('no plan: the row “Get today’s quests →” asks the Guide', (tester) async {
      final api = await seededFakeApi();
      await pumpScene(tester, const MapScene(), api: api);
      expect(key('daily-quests'), findsNothing);
      expect(find.text("Get today's quests →"), findsOneWidget);
      await tester.tap(key('get-quests'));
      await tester.pumpAndSettle();
      // The line is queued for the chat and the stage switches to scene 1/5.
      expect(find.text('route:/'), findsOneWidget);
      final chat = Provider.of<ChatController>(
        tester.element(find.text('route:/')),
        listen: false,
      );
      expect(chat.queuedMessage, 'What should I do today?');
    });

    group('with a plan', () {
      late FakeApiClient api;

      // One node per course is open, so three courses make a three-step plan:
      // Discriminant (6), then the first leaf of each generic course (17, 27).
      Future<void> twoMoreCourses(FakeApiClient api) async {
        await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
        await api.generateCourse(const GenerateRequest(topic: 'chess'));
      }

      setUp(() async {
        api = await seededFakeApi();
        await twoMoreCourses(api);
        await api.sendChat('What should I do today?');
      });

      Finder mark(int id, String which) =>
          find.descendant(of: key('quest-$id'), matching: key(which));

      testWidgets('one row per step, in order; a node that is mastered is checked', (
        tester,
      ) async {
        await passAudit(api, 6);
        await pumpScene(tester, const MapScene(), api: api);
        final plan = (await api.getCurrentPlan())!;
        expect(plan.steps.map((s) => s.skillId), [6, 17, 27]);
        expect(mark(6, 'quest-done'), findsOneWidget);
        expect(mark(17, 'quest-open'), findsOneWidget);
        expect(mark(27, 'quest-open'), findsOneWidget);
        expect(questCount('1/3'), findsOneWidget);
        // Mastered titles are muted.
        final done = tester.widget<Text>(
          find.descendant(of: key('quest-6'), matching: find.text('Discriminant')),
        );
        expect(done.style!.color, AppColors.textTertiary);
        expect(
          tester
              .widget<Text>(
                find.descendant(of: key('quest-17'), matching: find.text('Core Concepts 1')),
              )
              .style!
              .color,
          AppColors.textPrimary,
        );
      });

      testWidgets('a node audited today counts, even when the audit failed', (tester) async {
        await failAudit(api, 17);
        await pumpScene(tester, const MapScene(), api: api);
        expect(mark(17, 'quest-done'), findsOneWidget);
        expect(mark(27, 'quest-open'), findsOneWidget);
        expect(questCount('1/3'), findsOneWidget);
      });

      testWidgets('an audit that is still running does not count', (tester) async {
        await api.startAudit(27);
        await pumpScene(tester, const MapScene(), api: api);
        expect(mark(27, 'quest-open'), findsOneWidget);
        expect(questCount('0/3'), findsOneWidget);
      });

      testWidgets('nothing is checked at first', (tester) async {
        await pumpScene(tester, const MapScene(), api: api);
        expect(find.byKey(const Key('quest-done')), findsNothing);
        expect(find.byKey(const Key('quest-open')), findsNWidgets(3));
      });

      testWidgets('an audit from yesterday (KST) does not count', (tester) async {
        final old = FakeApiClient(
          latency: Duration.zero,
          clock: () => DateTime.now().toUtc().subtract(const Duration(days: 2)),
        );
        await old.generateCourse(const GenerateRequest(topic: 'math'));
        await twoMoreCourses(old);
        await old.sendChat('What should I do today?');
        await failAudit(old, 17);
        await pumpScene(tester, const MapScene(), api: old);
        expect(mark(17, 'quest-open'), findsOneWidget);
        expect(questCount('0/3'), findsOneWidget);
      });

      testWidgets('the day is the KST day (injected clock)', (tester) async {
        // The audit was made at 14:30 UTC = 23:30 KST on the 5th; at 15:30 UTC
        // it is already the 6th in Seoul.
        final moment = DateTime.utc(2026, 10, 5, 14, 30);
        final clocked = FakeApiClient(latency: Duration.zero, clock: () => moment);
        await clocked.generateCourse(const GenerateRequest(topic: 'math'));
        await twoMoreCourses(clocked);
        await clocked.sendChat('What should I do today?');
        await failAudit(clocked, 17);
        await pumpScene(
          tester,
          const MapScene(),
          api: clocked,
          clock: () => DateTime.utc(2026, 10, 5, 14, 50), // still the 5th in Seoul
        );
        expect(mark(17, 'quest-done'), findsOneWidget);
        await pumpScene(
          tester,
          const MapScene(),
          api: clocked,
          clock: () => DateTime.utc(2026, 10, 5, 15, 30), // the 6th in Seoul
        );
        expect(mark(17, 'quest-open'), findsOneWidget);
      });

      testWidgets('tapping a quest opens its node (scene 4)', (tester) async {
        await pumpScene(tester, const MapScene(), api: api);
        await tester.tap(key('quest-17'));
        await tester.pumpAndSettle();
        expect(find.text('route:/skill/17'), findsOneWidget);
      });

      testWidgets('finishing an audit refreshes the checks', (tester) async {
        final state = AppState();
        await pumpScene(tester, const MapScene(), api: api, state: state);
        expect(questCount('0/3'), findsOneWidget);
        await failAudit(api, 27);
        state.markDataChanged(); // what the audit scene does when an audit ends
        await tester.pumpAndSettle();
        expect(mark(27, 'quest-done'), findsOneWidget);
        expect(questCount('1/3'), findsOneWidget);
      });
    });
  });
}
