// Scenes 1 and 5: the entering scene, the chat with actions, suggestions, the
// ⊕ upload and the voice mode.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/life_tree.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/upload/file_picker_service.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Future<void> pumpHome(
  WidgetTester tester,
  FakeApiClient api, {
  FakeVoiceService? voice,
  FakeFilePicker? picker,
  Size size = wideScreen,
}) => pumpScene(tester, const HomeScene(), api: api, voice: voice, picker: picker, size: size);

Avatar avatar(WidgetTester tester) => tester.widget<Avatar>(find.byType(Avatar).first);

String bubbleText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('bubble-text'))).data!;

Finder inHistory(Finder f) =>
    find.descendant(of: find.byKey(const Key('chat-history')), matching: f);

PickedFile file(String name, [String body = '# Course']) =>
    PickedFile(name: name, bytes: utf8.encode(body));

void main() {
  group('scene 1', () {
    testWidgets('without a course: only you in the crystal ball, the two lines of the mockup', (
      tester,
    ) async {
      await pumpHome(tester, FakeApiClient(latency: Duration.zero));
      expect(avatar(tester).agent, 'front_desk');
      expect(avatar(tester).holdOrb, isTrue);
      expect(avatar(tester).mood, AvatarMood.smile);
      final tree = tester.widget<LifeConstellation>(find.byType(LifeConstellation));
      expect(tree.compact, isTrue);
      expect(tree.tree.isEmpty, isTrue);
      expect(find.text('How was your day?'), findsOneWidget);
      expect(find.text('Tell me what you want to learn'), findsOneWidget);
      expect(find.text('Message…'), findsOneWidget);
    });

    testWidgets('the wizard holds the crystal ball; the avatar is about 30 % of the stage height', (
      tester,
    ) async {
      await pumpHome(tester, await seededFakeApi());
      final ball = tester.getRect(find.byKey(const Key('crystal-ball')));
      expect(ball.width, closeTo(ball.height, 0.01));
      expect(
        find.descendant(
          of: find.byKey(const Key('crystal-ball')),
          matching: find.byType(LifeConstellation),
        ),
        findsOneWidget,
      );
      final avatarHeight = tester.getSize(find.byType(Avatar)).height;
      expect(avatarHeight / 900, inInclusiveRange(0.25, 0.35));
    });

    testWidgets('the life tree in the ball opens scene 2', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.byType(LifeConstellation), findsOneWidget);
      await tester.tap(find.byKey(const Key('mini-tree')));
      await tester.pumpAndSettle();
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('the ball holds every course around you; main quests are not points', (
      tester,
    ) async {
      final api = await seededFakeApi();
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
      final goal = await api.createGoal('Become an RL researcher');
      await api.updateGoal(goal.id, courseIds: [2]);
      await pumpHome(tester, api);
      final tree = tester.widget<LifeConstellation>(find.byType(LifeConstellation)).tree;
      expect({for (final n in tree.nodes) n.courseId}..remove(null), {1, 2});
      final rl = tree.nodes.firstWhere((n) => n.kind == LifeKind.course && n.courseId == 2);
      expect((rl.parent, rl.goalId), (LifeTree.selfKey, goal.id));
      final math = tree.nodes.firstWhere((n) => n.kind == LifeKind.course && n.courseId == 1);
      expect((math.parent, math.goalId), (LifeTree.selfKey, null)); // a side quest
      expect(tree.nodes.where((n) => n.label == goal.title), isEmpty);
    });

    testWidgets('an empty ball also opens scene 2', (tester) async {
      await pumpHome(tester, FakeApiClient(latency: Duration.zero));
      await tester.tap(find.byKey(const Key('mini-tree')));
      await tester.pumpAndSettle();
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('an ink headline above the wizard, with a subtitle', (tester) async {
      await pumpHome(tester, FakeApiClient(latency: Duration.zero));
      expect(find.text('What shall we learn today?'), findsOneWidget);
      expect(find.text('Tell the Guide what you want to learn.'), findsOneWidget);
      final greeting = find.byKey(const Key('greeting'));
      expect(greeting, findsOneWidget);
      // Plain ink, no gradient.
      expect(find.descendant(of: greeting, matching: find.byType(ShaderMask)), findsNothing);
      expect(
        tester.getBottomLeft(greeting).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(OrbAvatar)).dy),
        reason: 'above the wizard',
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('greeting-hint'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(greeting).dy),
      );
      // Wide: displayMedium (48, the display serif).
      expect(tester.widget<Text>(greeting).style!.fontSize, 48);
      expect(tester.widget<Text>(greeting).style!.fontFamily, AppFonts.display);
    });

    testWidgets('with a course the greeting names it', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.text('Continue with “High School Math”?'), findsOneWidget);
      expect(find.text('Tap the crystal ball to open your life tree.'), findsOneWidget);
      expect(find.text('What shall we learn today?'), findsNothing);
    });

    testWidgets('at most two suggestions as Gemini cards, side by side, with an icon', (
      tester,
    ) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.byKey(const Key('suggestion-0')), findsOneWidget);
      expect(find.byKey(const Key('suggestion-1')), findsOneWidget);
      expect(find.byKey(const Key('suggestion-2')), findsNothing);
      expect(find.text('How was your day?'), findsOneWidget);
      expect(find.text('Start with “Discriminant”'), findsOneWidget);
      final first = tester.getRect(find.byKey(const Key('suggestion-0')));
      final second = tester.getRect(find.byKey(const Key('suggestion-1')));
      expect(first.top, second.top, reason: 'side by side');
      expect(first.height, second.height);
      expect(second.left, greaterThan(first.right));
      // surfaceHigh, radius 16, a small icon in front of the text.
      final card = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const Key('suggestion-0')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.color, AppColors.surfaceHigh);
      expect(card.shape, RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)));
      expect(
        find.descendant(of: find.byKey(const Key('suggestion-0')), matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('suggestion-1')), matching: find.byType(Icon)),
        findsOneWidget,
      );
    });

    testWidgets('on a phone the cards are stacked and the greeting is smaller', (tester) async {
      await pumpHome(tester, await seededFakeApi(), size: phoneScreen);
      final first = tester.getRect(find.byKey(const Key('suggestion-0')));
      final second = tester.getRect(find.byKey(const Key('suggestion-1')));
      expect(second.top, greaterThanOrEqualTo(first.bottom));
      expect(first.left, second.left);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(const Key('greeting'))).style!.fontSize, 24);
    });

    testWidgets('the cards hide while typing', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.byKey(const Key('suggestion-0')), findsOneWidget);
      await type(tester, 'm');
      expect(find.byKey(const Key('suggestion-0')), findsNothing);
      expect(find.byKey(const Key('greeting')), findsOneWidget); // the greeting stays
    });

    testWidgets('suggestions are not shown when the server offers none', (tester) async {
      final api = FakeApiClient(latency: Duration.zero)..failNext(method: 'getChatSuggestions');
      await pumpHome(tester, api);
      expect(find.byKey(const Key('suggestion-0')), findsNothing);
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
    });

    testWidgets('a suggestion with a skill_id opens that node (scene 4) and sends nothing', (
      tester,
    ) async {
      final api = await seededFakeApi();
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('suggestion-1')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/6'), findsOneWidget);
      expect(await api.getChatHistory(), isEmpty);
    });

    testWidgets('a suggestion with a message sends it and goes to scene 5', (tester) async {
      final api = await seededFakeApi();
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('suggestion-0')));
      await tester.pumpAndSettle();
      expect((await api.getChatHistory()).first.content, 'Let me log my day');
      expect(find.byKey(const Key('reply-bubble')), findsOneWidget);
      expect(find.byKey(const Key('chat-history')), findsOneWidget);
      expect(find.byKey(const Key('suggestions')), findsNothing);
    });

    testWidgets('a suggestion with an empty message only puts the cursor in the input', (
      tester,
    ) async {
      final api = FakeApiClient(latency: Duration.zero);
      await pumpHome(tester, api);
      final field = tester.widget<TextField>(find.byKey(const Key('stage-input')));
      expect(field.focusNode!.hasFocus, isFalse);
      await tester.tap(find.text('Tell me what you want to learn'));
      await tester.pumpAndSettle();
      expect(field.focusNode!.hasFocus, isTrue);
      expect(await api.getChatHistory(), isEmpty);
      expect(find.byKey(const Key('reply-bubble')), findsNothing);
      expect(find.byKey(const Key('suggestions')), findsOneWidget); // still scene 1
    });

    testWidgets('typing hides the suggestions; clearing the text brings them back', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.byKey(const Key('suggestions')), findsOneWidget);
      await type(tester, 'm');
      expect(find.byKey(const Key('suggestions')), findsNothing);
      await type(tester, '');
      expect(find.byKey(const Key('suggestions')), findsOneWidget);
    });

    testWidgets('no chat panel; ⊕ and ∿ are there', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      expect(find.byKey(const Key('history-panel')), findsNothing);
      expect(find.byKey(const Key('upload')), findsOneWidget);
      expect(find.byKey(const Key('voice-mode')), findsOneWidget);
    });
  });

  group('scene 5 · text', () {
    testWidgets('her latest line in a big bubble; the user’s words in the chat panel', (
      tester,
    ) async {
      await pumpHome(tester, FakeApiClient(latency: Duration.zero));
      await say(tester, 'Hello there');
      expect(bubbleText(tester), 'Sure. What would you like to do today?');
      // The user's line is in the chat panel only (the stage copy has faded away).
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.byKey(const Key('last-said')), findsNothing);
      expect(inHistory(find.text('Hello there')), findsOneWidget);
      expect(find.byKey(const Key('history-panel')), findsOneWidget);
      expect(avatar(tester).mood, AvatarMood.neutral);
      expect(avatar(tester).wave, isFalse);
      expect(find.byKey(const Key('mini-tree')), findsNothing);
      expect(inputText(tester), '');
    });

    testWidgets('the chat panel is one long conversation separated by date', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.sendChat('something said before');
      await pumpHome(tester, api);
      await say(tester, 'Hello there');
      expect(inHistory(find.text('something said before')), findsOneWidget);
      expect(inHistory(find.text('Hello there')), findsOneWidget);
      expect(
        inHistory(find.textContaining(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}$'))),
        findsOneWidget,
      );
      expect(find.text('Chat'), findsOneWidget);
      // Two user bubbles, two answers with the agent's name and the time.
      expect(inHistory(find.byKey(const Key('chat-user-bubble'))), findsNWidgets(2));
      expect(inHistory(find.byKey(const Key('chat-agent-line'))), findsNWidgets(2));
      expect(inHistory(find.text('Guide')), findsNWidgets(2));
      expect(inHistory(find.textContaining(RegExp(r'^\d{2}:\d{2}$'))), findsNWidgets(2));
    });

    testWidgets('user lines are right-aligned bubbles; agent lines left-aligned with a head', (
      tester,
    ) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'I slept six hours last night');
      final panel = tester.getRect(find.byKey(const Key('history-panel')));
      final bubble = find.byKey(const Key('chat-user-bubble'));
      final user = tester.getRect(bubble);
      expect(panel.right - user.right, lessThan(24), reason: 'right-aligned');
      final decoration = tester.widget<DecoratedBox>(bubble).decoration as BoxDecoration;
      expect(decoration.color, AppColors.userBubble);
      expect(decoration.borderRadius, AppRadius.userBubbleBorder);
      // Agent lines: no bubble, left edge near the panel, 28 px round head.
      final lines = find.byKey(const Key('chat-agent-line'));
      expect(lines, findsNWidgets(2)); // front desk + check-in converter
      final agent = tester.getRect(lines.first);
      expect(agent.left - panel.left, lessThan(24));
      expect(
        find
            .descendant(of: lines.first, matching: find.byType(DecoratedBox))
            .evaluate()
            .where(
              (e) =>
                  ((e.widget as DecoratedBox).decoration as BoxDecoration).color ==
                  AppColors.userBubble,
            ),
        isEmpty,
      );
      final heads = tester.widgetList<AvatarHead>(find.byType(AvatarHead)).toList();
      expect(heads.map((h) => h.agent), ['front_desk', 'checkin_converter']);
      expect(tester.getSize(find.byType(AvatarHead).first), const Size(28, 28));
      // The names of the agents, in the vocabulary.
      expect(inHistory(find.text('Guide')), findsOneWidget);
      expect(inHistory(find.text('Check-in')), findsOneWidget);
    });

    testWidgets('the chat panel scrolls to the newest line', (tester) async {
      final api = await seededFakeApi();
      await pumpHome(tester, api);
      for (var i = 0; i < 8; i++) {
        await say(
          tester,
          'Long message number $i. It is written to run a little longer so that it wraps onto a second line.',
        );
      }
      final list = tester.widget<ListView>(find.byKey(const Key('chat-history')));
      final controller = list.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(controller.offset, controller.position.maxScrollExtent);
    });

    testWidgets('the sent line stays above the input until her reply arrives, then fades out', (
      tester,
    ) async {
      final api = FakeApiClient(latency: const Duration(milliseconds: 300));
      await pumpHome(tester, api);
      await type(tester, 'Hello there');
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump(const Duration(milliseconds: 50));
      final said = find.byKey(const Key('last-said'));
      expect(said, findsOneWidget);
      // A small right-aligned userBubble above the input.
      final decoration = tester.widget<DecoratedBox>(said).decoration as BoxDecoration;
      expect(decoration.color, AppColors.userBubble);
      expect(decoration.borderRadius, AppRadius.userBubbleBorder);
      expect(
        tester.getBottomLeft(said).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('stage-input'))).dy),
      );
      expect(
        tester.getTopRight(said).dx,
        greaterThan(tester.getCenter(find.byKey(const Key('stage-input'))).dx),
      );
      expect(find.descendant(of: said, matching: find.text('Hello there')), findsOneWidget);
      // Still there while she thinks.
      await tester.pump(const Duration(milliseconds: 100));
      expect(said, findsOneWidget);
      expect(
        tester
            .widget<FadeTransition>(
              find.ancestor(of: said, matching: find.byType(FadeTransition)).first,
            )
            .opacity
            .value,
        1,
      );
      // Her reply arrives: it fades …
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(said, findsOneWidget);
      expect(
        tester
            .widget<FadeTransition>(
              find.ancestor(of: said, matching: find.byType(FadeTransition)).first,
            )
            .opacity
            .value,
        lessThan(1),
      );
      // … and is gone.
      await tester.pumpAndSettle();
      expect(said, findsNothing);
      expect(inHistory(find.text('Hello there')), findsOneWidget);
    });

    testWidgets('a failed send removes the line from the stage', (tester) async {
      final api = FakeApiClient(latency: Duration.zero)..failNext(method: 'sendChat');
      await pumpHome(tester, api);
      await say(tester, 'Hello there');
      expect(find.byKey(const Key('last-said')), findsNothing);
    });

    testWidgets('the speaker\'s name is written above her bubble', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'I slept six hours last night');
      expect(
        find.descendant(
          of: find.byKey(const Key('reply-bubble')),
          matching: find.byKey(const Key('speaker-name')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('reply-bubble')), matching: find.text('Check-in')),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.byKey(const Key('speaker-name'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('bubble-text'))).dy),
      );
    });

    testWidgets('the avatar is the agent that answered', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'I slept six hours last night');
      expect(avatar(tester).agent, 'checkin_converter');
      expect(bubbleText(tester), startsWith('Logged: sleep 6 h'));
    });

    testWidgets('while she thinks the bubble shows the gradient shimmer, not dots', (
      tester,
    ) async {
      final api = FakeApiClient(latency: const Duration(milliseconds: 200));
      await pumpHome(tester, api);
      await type(tester, 'Hello there');
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump();
      expect(find.byKey(const Key('thinking-shimmer')), findsOneWidget);
      expect(find.byKey(const Key('typing-dots')), findsNothing);
      // Three skeleton lines, filled with a gradient; still in tests (animations are off).
      expect(
        find.descendant(
          of: find.byKey(const Key('thinking-shimmer')),
          matching: find.byType(FractionallySizedBox),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('reply-bubble')),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      expect(tester.state<ThinkingShimmerState>(find.byType(ThinkingShimmer)).flowing, isFalse);
      expect(avatar(tester).state, AvatarState.thinking);
      expect(tester.widget<TextField>(find.byKey(const Key('stage-input'))).enabled, isFalse);
      // The send arrow has morphed into a spinner, and morphs back after.
      MorphIcon sendIcon() => tester.widget<MorphIcon>(find.byKey(const Key('send-icon')));
      expect(sendIcon().morphed, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(sendIcon().morphed, isFalse);
      expect(find.byKey(const Key('thinking-shimmer')), findsNothing);
      expect(bubbleText(tester), isNotEmpty);
    });

    testWidgets('a generated course: Open life tree → opens scene 2', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await pumpHome(tester, api);
      await say(tester, 'I want to learn math');
      expect(bubbleText(tester), 'Your world “High School Math” is ready — 12 nodes.');
      expect(avatar(tester).agent, 'planner');
      expect(find.text('Open life tree'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-map')));
      await tester.pumpAndSettle();
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('a navigate action switches the scene at once', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'Show me the map');
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('opening a node by name goes to scene 4', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'Let me try Quadratic Equations');
      expect(find.text('route:/skill/5'), findsOneWidget);
    });

    testWidgets('an audit cannot start from the chat: no audit button appears', (tester) async {
      await pumpHome(tester, await seededFakeApi());
      await say(tester, 'What should I do today?');
      expect(bubbleText(tester), startsWith("Today's quests:"));
      expect(find.byKey(const Key('start-audit')), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a failing front desk: an error above the input, the text comes back', (
      tester,
    ) async {
      final api = FakeApiClient(latency: Duration.zero)..failNext(method: 'sendChat');
      await pumpHome(tester, api);
      await say(tester, 'Hello there');
      expect(find.byKey(const Key('input-error')), findsOneWidget);
      expect(find.text('Something went wrong on our side. Please try again.'), findsOneWidget);
      expect(inputText(tester), 'Hello there');
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('input-error')), findsNothing);
      expect(bubbleText(tester), 'Sure. What would you like to do today?');
    });

    testWidgets('narrow screen: the same bubble and avatar', (tester) async {
      await pumpHome(tester, await seededFakeApi(), size: phoneScreen);
      await say(tester, 'Hello there');
      expect(bubbleText(tester), 'Sure. What would you like to do today?');
      expect(tester.takeException(), isNull);
    });
  });

  group('⊕ upload', () {
    testWidgets('a picked file becomes a chip above the input', (tester) async {
      final picker = FakeFilePicker()..next = file('Calculus syllabus.md');
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(find.byKey(const Key('attachment-1')), findsOneWidget);
      expect(find.text('Calculus syllabus.md'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const Key('attachment-1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('stage-input'))).dy),
      );
    });

    testWidgets('the chip can be removed', (tester) async {
      final picker = FakeFilePicker()..next = file('a.md');
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('attachment-remove-1')));
      await tester.pump();
      expect(find.byKey(const Key('attachment-1')), findsNothing);
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      final picker = FakeFilePicker();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('attachment-1')), findsNothing);
    });

    testWidgets('the chat message goes out with the upload id and the chip goes away', (
      tester,
    ) async {
      final api = FakeApiClient(latency: Duration.zero);
      final picker = FakeFilePicker()..next = file('Calculus syllabus.md');
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      await say(tester, 'I want to learn this');

      final course = (await api.listCourses()).single;
      expect(course.sourceCourse, 'Calculus syllabus.md');
      expect(course.sourceUrl, isNull);
      expect(find.byKey(const Key('attachment-1')), findsNothing);
      expect(bubbleText(tester), contains('is ready'));
      expect(find.text('Open life tree'), findsOneWidget);
    });

    testWidgets('the next message goes out without the file', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      final picker = FakeFilePicker()..next = file('a.md');
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      await say(tester, 'I want to learn this');
      await say(tester, 'I want to learn this again');
      // Without a file the second message names the topic "this again" → generic course,
      // not one from the file.
      expect((await api.listCourses()).where((c) => c.sourceCourse == 'a.md'), hasLength(1));
    });

    testWidgets('a failed message keeps the chip so that she can try again', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      final picker = FakeFilePicker()..next = file('a.md');
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      api.failNext(method: 'sendChat');
      await say(tester, 'I want to learn this');
      expect(find.byKey(const Key('attachment-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-1')), findsNothing);
      expect((await api.listCourses()).single.sourceCourse, 'a.md');
    });

    testWidgets('a short snackbar for a wrong file type', (tester) async {
      final picker = FakeFilePicker()..next = file('photo.png');
      final api = FakeApiClient(latency: Duration.zero);
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.text('Only PDF, TXT or MD files up to 4 MB.'), findsOneWidget);
      expect(find.byKey(const Key('attachment-1')), findsNothing);
    });

    testWidgets('too big: the same snackbar, nothing is uploaded', (tester) async {
      final picker = FakeFilePicker()
        ..next = PickedFile(name: 'big.pdf', bytes: List.filled(kUploadMaxBytes + 1, 65));
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.text('Only PDF, TXT or MD files up to 4 MB.'), findsOneWidget);
    });

    testWidgets('a server error shows its text in a snackbar', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      final picker = FakeFilePicker()..next = file('empty file.txt', '   ');
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't read any text from this file."), findsOneWidget);

      picker.next = file('b.md');
      api.failNext(method: 'uploadFile', statusCode: null);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(find.byKey(const Key('attachment-2')), findsNothing);
    });

    testWidgets('while it uploads, a chip with a spinner and ⊕ is off', (tester) async {
      final api = FakeApiClient(latency: const Duration(milliseconds: 300));
      final picker = FakeFilePicker()..next = file('a.md');
      await pumpHome(tester, api, picker: picker);
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('attachment-uploading')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('attachment-uploading')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(find.byKey(const Key('upload'))).onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-1')), findsOneWidget);
    });

    testWidgets('at most three files per message', (tester) async {
      final picker = FakeFilePicker();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), picker: picker);
      for (var i = 0; i < 3; i++) {
        picker.next = file('f$i.md');
        await tester.tap(find.byKey(const Key('upload')));
        await tester.pumpAndSettle();
      }
      picker.next = file('f3.md');
      await tester.tap(find.byKey(const Key('upload')));
      await tester.pumpAndSettle();
      expect(find.text('You can attach up to 3 files.'), findsOneWidget);
      expect(find.byKey(const Key('attachment-4')), findsNothing);
    });
  });

  group('voice mode (scene 5)', () {
    testWidgets('∿ starts it: the bar becomes a waveform with no buttons, she listens', (
      tester,
    ) async {
      final voice = FakeVoiceService();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(voice.listenCalls, 1);
      expect(find.byKey(const Key('voice-wave-row')), findsOneWidget);
      expect(find.byType(VoiceWave), findsOneWidget);
      expect(find.text('Listening…'), findsOneWidget);
      expect(find.byKey(const Key('stage-input')), findsNothing);
      expect(find.byKey(const Key('send')), findsNothing);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
      expect(avatar(tester).state, AvatarState.listening);
      expect(find.byKey(const Key('mini-tree')), findsNothing); // scene 5 already
      expect(find.byKey(const Key('history-panel')), findsOneWidget);
    });

    testWidgets('the status line follows the loop: Listening… / Thinking… / Speaking…', (
      tester,
    ) async {
      final voice = FakeVoiceService()..holdSpeech = true;
      final api = FakeApiClient(latency: const Duration(milliseconds: 300));
      await pumpHome(tester, api, voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pump(const Duration(milliseconds: 20));
      String status() => tester.widget<Text>(find.byKey(const Key('voice-status'))).data!;
      expect(status(), 'Listening…');
      voice.hear('Hello there');
      await tester.pump(const Duration(milliseconds: 20));
      expect(status(), 'Thinking…');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(status(), 'Speaking…');
      voice.finishSpeaking();
      await tester.pump(const Duration(milliseconds: 20));
      expect(status(), 'Listening…');
      await tester.pumpAndSettle();
    });

    testWidgets('the live caption shows what is heard, above the status line', (tester) async {
      final voice = FakeVoiceService();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-caption')), findsNothing);
      voice.partial('Quadratic Equations');
      await tester.pump();
      expect(find.text('Quadratic Equations'), findsOneWidget);
      voice.partial('Quadratic Equations and how to find the roots');
      await tester.pump();
      final caption = find.byKey(const Key('voice-caption'));
      expect(tester.widget<Text>(caption).data, 'Quadratic Equations and how to find the roots');
      expect(tester.widget<Text>(caption).style!.color, AppColors.textSecondary);
      expect(
        tester.getBottomLeft(caption).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('voice-status'))).dy),
      );
      expect(
        tester.getBottomLeft(find.byKey(const Key('voice-status'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('voice-wave-row'))).dy),
      );
    });

    testWidgets('the waveform is driven by the sound level', (tester) async {
      final voice = FakeVoiceService();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(tester.widget<VoiceWave>(find.byType(VoiceWave)).level, 0);
      voice.level(0.8);
      await tester.pump();
      final wave = tester.widget<VoiceWave>(find.byType(VoiceWave));
      expect(wave.level, 0.8);
      expect(wave.active, isTrue);
    });

    testWidgets('what is heard is sent, her answer shown and spoken, then she listens again', (
      tester,
    ) async {
      final voice = FakeVoiceService();
      final api = FakeApiClient(latency: Duration.zero);
      await pumpHome(tester, api, voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      voice.hear('Hello there');
      await tester.pumpAndSettle();
      expect((await api.getChatHistory()).first.content, 'Hello there');
      expect(bubbleText(tester), 'Sure. What would you like to do today?');
      expect(voice.spoken, ['Sure. What would you like to do today?']);
      expect(voice.listenCalls, 2);
      expect(find.byKey(const Key('voice-wave-row')), findsOneWidget);
      expect(inHistory(find.text('Hello there')), findsOneWidget);
    });

    testWidgets('Esc leaves voice mode', (tester) async {
      final voice = FakeVoiceService();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-wave-row')), findsNothing);
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
      expect(voice.isListening, isFalse);
    });

    testWidgets('a tap on the waveform leaves voice mode', (tester) async {
      final voice = FakeVoiceService();
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-wave-row')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
    });

    testWidgets('without speech support: a snackbar and the scene stays scene 1', (tester) async {
      final voice = FakeVoiceService(available: false);
      await pumpHome(tester, await seededFakeApi(), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      expect(find.text("Voice mode isn't available on this device."), findsOneWidget);
      expect(find.byKey(const Key('mini-tree')), findsOneWidget);
      expect(find.byKey(const Key('history-panel')), findsNothing);
    });

    testWidgets('a tap on the avatar cuts her speech short', (tester) async {
      final voice = FakeVoiceService()..holdSpeech = true;
      await pumpHome(tester, FakeApiClient(latency: Duration.zero), voice: voice);
      await tester.tap(find.byKey(const Key('voice-mode')));
      await tester.pumpAndSettle();
      voice.hear('Hello there');
      await tester.pump();
      await tester.pump();
      expect(avatar(tester).state, AvatarState.speaking);
      await tester.tap(find.byKey(const Key('avatar-tap')));
      await tester.pumpAndSettle();
      expect(voice.listenCalls, 2);
    });
  });

  testWidgets('the entering scene has the left panel and the stage, no chat panel', (tester) async {
    await pumpHome(tester, await seededFakeApi());
    expect(AppColors.background, const Color(0xFFF5F5F1));
    expect(find.byKey(const Key('left-panel')), findsOneWidget);
    expect(find.byKey(const Key('history-panel')), findsNothing);
  });
}
