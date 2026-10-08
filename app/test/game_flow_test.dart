// The life-as-a-game layer end to end with the real router: the left panel's
// `Get today's quests →` row and the reflection prompt of scene 1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/widgets/widgets.dart';

import 'support/scene_helpers.dart';
import 'support/spy_api.dart';

Finder key(String k) => find.byKey(Key(k));

Future<void> pumpApp(WidgetTester tester, FakeApiClient api, {String? initialLocation}) async {
  Avatar.animationsEnabled = false;
  tester.view.physicalSize = wideScreen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SelfInfinityApp(
      api: api,
      appState: AppState(),
      voice: FakeVoiceService(),
      filePicker: FakeFilePicker(),
      initialLocation: initialLocation,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Get today’s quests →', () {
    testWidgets('from the map: the line goes to the chat and scene 5 shows the answer', (
      tester,
    ) async {
      final api = SpyApi();
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await pumpApp(tester, api, initialLocation: '/map');
      expect(find.byType(MapScene), findsOneWidget);
      await tester.tap(key('get-quests'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScene), findsOneWidget);
      expect(api.chatMessages, ['What should I do today?']);
      expect(api.chatPrompts, [null]); // an ordinary message, not a reflection
      // Scene 5: her answer in the bubble, the chat panel open ...
      expect(key('history-panel'), findsOneWidget);
      expect(
        tester.widget<Text>(key('bubble-text')).data,
        startsWith("Today's quests: “Discriminant”"),
      );
      // ... and the left panel lists the quest instead of the row.
      expect(find.text("Get today's quests →"), findsNothing);
      expect(
        find.descendant(of: key('daily-quests'), matching: find.text('Discriminant')),
        findsOneWidget,
      );
    });

    testWidgets('on the home scene itself the same row works', (tester) async {
      final api = SpyApi();
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await pumpApp(tester, api);
      await tester.tap(key('get-quests'));
      await tester.pumpAndSettle();
      expect(api.chatMessages, ['What should I do today?']);
      expect(key('history-panel'), findsOneWidget);
      expect(key('quest-6'), findsOneWidget);
    });

    testWidgets('without a course the Guide says no node is ready and the row stays', (
      tester,
    ) async {
      final api = SpyApi();
      await pumpApp(tester, api, initialLocation: '/map');
      await tester.tap(key('get-quests'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(key('bubble-text')).data,
        'No node is ready yet. Make a world first.',
      );
      expect(find.text("Get today's quests →"), findsOneWidget);
    });

    testWidgets('tapping a quest opens scene 4', (tester) async {
      final api = SpyApi();
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await api.sendChat('What should I do today?');
      await pumpApp(tester, api, initialLocation: '/map');
      await tester.tap(key('quest-6'));
      await tester.pumpAndSettle();
      expect(GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path, '/skill/6');
    });
  });
}
