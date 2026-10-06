// The reflection prompt on scene 1 (docs/ux-chat.md §6.3): a suggestion with
// `reflection: true` makes the Guide ask the prompt in her bubble; the next
// message is the answer, sent with `reflection_prompt`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/chat/chat_controller.dart';
import 'package:self_infinity/features/chat/home_scene.dart';

import '../support/scene_helpers.dart';
import '../support/spy_api.dart';

Finder key(String k) => find.byKey(Key(k));

const String prompt = 'What are you putting off right now?';

Finder inHistory(Finder f) => find.descendant(of: key('chat-history'), matching: f);

/// A spy whose clock says 12:00 KST, checked in today: the reflection prompt of
/// the 11:00-13:29 window is on offer.
Future<SpyApi> checkedIn({bool course = false}) async {
  final api = SpyApi(clock: () => DateTime.utc(2026, 10, 5, 3));
  if (course) await api.generateCourse(const GenerateRequest(topic: 'math'));
  await api.checkInVoice('I slept seven hours.');
  return api;
}

Future<void> pumpHome(WidgetTester tester, SpyApi api) =>
    pumpScene(tester, const HomeScene(), api: api);

ChatController chatOf(WidgetTester tester) =>
    Provider.of<ChatController>(tester.element(find.byType(HomeScene)), listen: false);

bool inputFocused(WidgetTester tester) =>
    tester.widget<TextField>(key('stage-input')).focusNode!.hasFocus;

void main() {
  group('the suggestion', () {
    testWidgets('is the first card, with its own icon, and shows the prompt', (tester) async {
      await pumpHome(tester, await checkedIn(course: true));
      expect(find.text(prompt), findsOneWidget);
      expect(
        find.descendant(
          of: key('suggestion-0'),
          matching: find.byIcon(Icons.psychology_alt_outlined),
        ),
        findsOneWidget,
      );
      // The ordinary card next to it has a different icon.
      expect(
        find.descendant(
          of: key('suggestion-1'),
          matching: find.byIcon(Icons.psychology_alt_outlined),
        ),
        findsNothing,
      );
      expect(find.text('Start with “High School Math”'), findsOneWidget);
    });

    testWidgets('the check-in card keeps its sun icon', (tester) async {
      await pumpHome(tester, SpyApi());
      expect(
        find.descendant(of: key('suggestion-0'), matching: find.byIcon(Icons.wb_sunny_outlined)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.psychology_alt_outlined), findsNothing);
    });
  });

  group('tapping it', () {
    testWidgets('the Guide asks the prompt in her bubble and the cursor goes to the input', (
      tester,
    ) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      expect(inputFocused(tester), isFalse);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      // Her bubble, her name above it.
      expect(tester.widget<Text>(key('bubble-text')).data, prompt);
      expect(
        find.descendant(of: key('reply-bubble'), matching: find.text('Guide')),
        findsOneWidget,
      );
      expect(inputFocused(tester), isTrue);
      expect(find.text('Your answer…'), findsOneWidget);
      // Scene 5 now: the cards are gone.
      expect(key('suggestions'), findsNothing);
      // Nothing was sent yet: client-side only.
      expect(api.chatMessages, isEmpty);
      expect(await api.getChatHistory(), isEmpty);
      expect(await api.listJournal(), isEmpty);
    });

    testWidgets('typing alone does not send either', (tester) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      await type(tester, 'The taxes');
      expect(api.chatMessages, isEmpty);
    });
  });

  group('the answer', () {
    testWidgets('goes out with reflection_prompt; the three messages land in the chat panel', (
      tester,
    ) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      await say(tester, 'The taxes');

      expect(api.chatMessages, ['The taxes']);
      expect(api.chatPrompts, [prompt]);
      // Her bubble now acknowledges.
      expect(tester.widget<Text>(key('bubble-text')).data, "Noted. It's in your journal.");
      // The chat panel has her question, the answer and the acknowledgement, in order.
      final texts = textsIn(tester, key('chat-history')).toList();
      final at = [prompt, 'The taxes', "Noted. It's in your journal."].map(texts.indexOf).toList();
      expect(at.every((i) => i >= 0), isTrue, reason: '$texts');
      expect(at, [...at]..sort());
      // The server stored it.
      expect((await api.listJournal()).single.answer, 'The taxes');
      expect((await api.getChatHistory()).map((m) => m.content), [
        prompt,
        'The taxes',
        "Noted. It's in your journal.",
      ]);
      // The input is back to normal.
      expect(find.text('Message…'), findsOneWidget);
      expect(inputText(tester), '');
    });

    testWidgets('the suggestions are reloaded: the answered prompt is gone', (tester) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      final before = api.suggestionLoads;
      expect(chatOf(tester).suggestions.first.reflection, isTrue);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      expect(api.suggestionLoads, before); // asking reloads nothing
      await say(tester, 'The taxes');
      expect(api.suggestionLoads, before + 1);
      expect(chatOf(tester).suggestions.any((s) => s.reflection), isFalse);
      expect(chatOf(tester).suggestions.map((s) => s.label), ['Tell me what you want to learn']);
    });

    testWidgets('the next message is an ordinary one', (tester) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      await say(tester, 'The taxes');
      await say(tester, 'Hello there');
      expect(api.chatPrompts, [prompt, null]);
      expect(
        tester.widget<Text>(key('bubble-text')).data,
        'Sure. What would you like to do today?',
      );
      expect(await api.listJournal(), hasLength(1));
    });

    testWidgets('a failure keeps her question up and the text in the input; a retry works', (
      tester,
    ) async {
      final api = await checkedIn();
      await pumpHome(tester, api);
      await tester.tap(key('suggestion-0'));
      await tester.pumpAndSettle();
      api.failNext(method: 'sendChat');
      await say(tester, 'The taxes');
      expect(key('input-error'), findsOneWidget);
      expect(inputText(tester), 'The taxes');
      expect(tester.widget<Text>(key('bubble-text')).data, prompt);
      expect(await api.listJournal(), isEmpty);

      await tester.tap(key('send'));
      await tester.pumpAndSettle();
      expect(api.chatPrompts, [prompt, prompt]);
      expect(tester.widget<Text>(key('bubble-text')).data, "Noted. It's in your journal.");
      expect(await api.listJournal(), hasLength(1));
    });
  });

  group('other suggestions are not reflections', () {
    testWidgets('“Tell me what you want to learn” only focuses the input', (tester) async {
      final api = SpyApi();
      await api.checkInVoice('I slept seven hours.');
      await pumpHome(tester, api);
      await tester.tap(find.text('Tell me what you want to learn'));
      await tester.pumpAndSettle();
      expect(inputFocused(tester), isTrue);
      expect(key('reply-bubble'), findsNothing);
      expect(find.text('Message…'), findsOneWidget);
      await say(tester, 'Hello there');
      expect(api.chatPrompts, [null]);
    });

    testWidgets('the check-in card still sends its line', (tester) async {
      final api = SpyApi();
      await pumpHome(tester, api);
      await tester.tap(find.text('How was your day?'));
      await tester.pumpAndSettle();
      expect(api.chatMessages, ['Let me log my day']);
      expect(api.chatPrompts, [null]);
    });
  });

  testWidgets('on a phone the reflection card fits', (tester) async {
    await pumpScene(tester, const HomeScene(), api: await checkedIn(), size: phoneScreen);
    expect(find.text(prompt), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(key('suggestion-0'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('bubble-text')).data, prompt);
    expect(tester.takeException(), isNull);
  });
}
