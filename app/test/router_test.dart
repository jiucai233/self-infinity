// The route map: four stage scenes, nothing else.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/app/router.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import 'support/scene_helpers.dart';

Future<void> pumpApp(WidgetTester tester, {String? initialLocation, FakeApiClient? api}) async {
  Avatar.animationsEnabled = false;
  tester.view.physicalSize = wideScreen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SelfInfinityApp(
      api: api ?? await seededFakeApi(),
      appState: AppState(),
      voice: FakeVoiceService(),
      filePicker: FakeFilePicker(),
      initialLocation: initialLocation,
    ),
  );
  await tester.pumpAndSettle();
}

/// The router's context (inside the Navigator, below the router widget).
BuildContext routerContext(WidgetTester tester) => tester.element(find.byType(Scaffold).first);

Future<void> go(WidgetTester tester, String location) async {
  routerContext(tester).go(location);
  await tester.pumpAndSettle();
}

void main() {
  group('routes', () {
    testWidgets('the app starts on / — scene 1, no onboarding', (tester) async {
      await pumpApp(tester);
      expect(find.byType(HomeScene), findsOneWidget);
    });

    testWidgets('each route shows its scene', (tester) async {
      await pumpApp(tester);
      await go(tester, AppRoutes.map);
      expect(find.byType(MapScene), findsOneWidget);
      await go(tester, AppRoutes.skill(1));
      expect(find.byType(SkillScene), findsOneWidget);
      await go(tester, AppRoutes.audit(1));
      expect(find.byType(AuditScene), findsOneWidget);
      await go(tester, AppRoutes.home);
      expect(find.byType(HomeScene), findsOneWidget);
    });

    test('path helpers', () {
      expect(AppRoutes.home, '/');
      expect(AppRoutes.map, '/map');
      expect(AppRoutes.skill(5), '/skill/5');
      expect(AppRoutes.audit(5), '/skill/5/audit');
    });

    testWidgets('the scenes that were deleted are gone: they are "not found"', (tester) async {
      await pumpApp(tester);
      for (final path in ['/dex', '/checkin', '/onboarding', '/courses/new', '/settings']) {
        await go(tester, path);
        expect(find.byType(NotFoundScreen), findsOneWidget, reason: path);
      }
    });

    testWidgets('old query parameters are ignored', (tester) async {
      await pumpApp(tester);
      await go(tester, '/?ask=checkin');
      expect(find.byType(HomeScene), findsOneWidget);
      expect(find.byKey(const Key('reply-bubble')), findsNothing);
      await go(tester, '/skill/1/audit?mode=night');
      expect(find.byType(AuditScene), findsOneWidget);
      await go(tester, '/map?course=1&focus=3');
      expect(find.byType(MapScene), findsOneWidget);
    });

    testWidgets('a bad node id is "not found"; the button goes home', (tester) async {
      await pumpApp(tester, initialLocation: '/skill/abc');
      expect(find.byType(NotFoundScreen), findsOneWidget);
      expect(find.text('Page not found'), findsOneWidget);
      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScene), findsOneWidget);
      await go(tester, '/skill/xyz/audit');
      expect(find.byType(NotFoundScreen), findsOneWidget);
    });

    testWidgets('initialLocation starts anywhere', (tester) async {
      await pumpApp(tester, initialLocation: '/map');
      expect(find.byType(MapScene), findsOneWidget);
    });

    testWidgets('with animations off (tests) scenes switch at once', (tester) async {
      await pumpApp(tester);
      routerContext(tester).go(AppRoutes.map);
      await tester.pump();
      expect(find.byType(MapScene), findsOneWidget);
      expect(find.byType(HomeScene), findsNothing);
    });

    group('scene transitions (fade + slight slide, ~220 ms)', () {
      tearDown(() => Avatar.animationsEnabled = false);

      Future<void> pumpAnimated(WidgetTester tester, {String? initialLocation}) async {
        await pumpApp(tester, initialLocation: initialLocation);
        Avatar.animationsEnabled = true;
      }

      double opacityOf(WidgetTester tester, Type scene) => tester
          .widget<FadeTransition>(
            find.ancestor(of: find.byType(scene), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;

      Offset slideOf(WidgetTester tester, Type scene) => tester
          .widget<SlideTransition>(
            find.ancestor(of: find.byType(scene), matching: find.byType(SlideTransition)).first,
          )
          .position
          .value;

      testWidgets('the new scene fades in while it slides up into place', (tester) async {
        await pumpAnimated(tester);
        routerContext(tester).go(AppRoutes.map);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        // Both scenes are there while it runs.
        expect(find.byType(MapScene), findsOneWidget);
        expect(find.byType(HomeScene), findsOneWidget);
        final opacity = opacityOf(tester, MapScene);
        expect(opacity, inExclusiveRange(0, 1));
        expect(slideOf(tester, MapScene).dy, greaterThan(0));
        expect(slideOf(tester, MapScene).dy, lessThanOrEqualTo(0.02));
        await tester.pump(const Duration(milliseconds: 100));
        expect(opacityOf(tester, MapScene), greaterThan(opacity));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300)); // the life tree never settles
        expect(find.byType(HomeScene), findsNothing);
        expect(opacityOf(tester, MapScene), 1);
        expect(slideOf(tester, MapScene), Offset.zero);
      });

      testWidgets('it takes about 220 ms', (tester) async {
        await pumpAnimated(tester);
        expect(kSceneTransition, const Duration(milliseconds: 220));
        routerContext(tester).go(AppRoutes.map);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(HomeScene), findsOneWidget); // not yet
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump();
        expect(find.byType(HomeScene), findsNothing);
      });

      testWidgets('going back slides the other way', (tester) async {
        await pumpAnimated(tester, initialLocation: AppRoutes.skill(1));
        routerContext(tester).go(AppRoutes.map);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(slideOf(tester, MapScene).dy, lessThan(0));
        await tester.pump(const Duration(milliseconds: 300)); // the life tree never settles
        routerContext(tester).go(AppRoutes.audit(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(slideOf(tester, AuditScene).dy, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 300)); // the life tree never settles
      });
    });
  });

  group('walking through the scenes (real router)', () {
    testWidgets('1 → 2 → 4 → 4-1 and back with ←', (tester) async {
      await pumpApp(tester);
      // Scene 1: the mini tree.
      await tester.tap(find.byKey(const Key('mini-tree')));
      await tester.pumpAndSettle();
      expect(find.byType(MapScene), findsOneWidget);
      // Scene 2: a node (in the outline).
      await tester.tap(find.byKey(const Key('view-outline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-1')));
      await tester.pumpAndSettle();
      expect(find.byType(SkillScene), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('stage-title'))).data, 'High School Math');
      // Scene 4: →
      await tester.tap(find.byKey(const Key('start-audit')));
      await tester.pumpAndSettle();
      expect(find.byType(AuditScene), findsOneWidget);
      // ← to scene 4, ← to scene 2, ← to scene 1
      await tester.tap(find.byKey(const Key('audit-back')));
      await tester.pumpAndSettle();
      expect(find.byType(SkillScene), findsOneWidget);
      await tester.tap(find.byKey(const Key('back-map')));
      await tester.pumpAndSettle();
      expect(find.byType(MapScene), findsOneWidget);
      await tester.tap(find.byKey(const Key('back-home')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScene), findsOneWidget);
    });

    testWidgets('the "continue" suggestion goes to scene 4; a search to the node', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Start with “High School Math”'));
      await tester.pumpAndSettle();
      expect(find.byType(SkillScene), findsOneWidget);

      await go(tester, AppRoutes.map);
      await say(tester, 'Calculus');
      expect(find.byType(SkillScene), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('stage-title'))).data, 'Calculus');
    });

    testWidgets('a course made in the chat shows up on the map', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero));
      await say(tester, 'I want to learn math');
      await tester.tap(find.byKey(const Key('action-map')));
      await tester.pumpAndSettle();
      expect(find.byType(MapScene), findsOneWidget);
      await tester.tap(find.byKey(const Key('view-outline')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('node-1')),
          matching: find.text('High School Math'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('node-12')), findsOneWidget);
    });

    testWidgets('an audit passed on the stage opens the next nodes on the map', (tester) async {
      await pumpApp(tester, initialLocation: '/skill/1/audit');
      await say(tester, longAnswer);
      await say(tester, longAnswer);
      expect(find.byKey(const Key('celebration-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('audit-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('view-outline')));
      await tester.pumpAndSettle();
      // The root is a boss: its dot has two containers, the inner one holds the fill.
      final dot = tester
          .widgetList<Container>(
            find.descendant(of: find.byKey(const Key('dot-1')), matching: find.byType(Container)),
          )
          .last;
      expect((dot.decoration! as BoxDecoration).color, AppColors.success);
    });
  });

  testWidgets('MaterialApp is light only', (tester) async {
    await pumpApp(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.light);
    expect(app.themeMode, isNot(ThemeMode.dark));
    expect(app.title, 'Self-Infinity');
  });

  testWidgets('createRouter has exactly the four scene routes', (tester) async {
    final router = createRouter();
    addTearDown(router.dispose);
    final paths = router.configuration.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, ['/', '/map', '/skill/:skillId', '/skill/:skillId/audit']);
  });
}
