// The phone's bottom bar: Home, Life tree, Me. Not on wide screens, not in an
// audit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/app/router.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/life/life_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/features/stage/app_tabs.dart';
import 'package:self_infinity/features/stage/me_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder get bar => find.byKey(const Key('tab-bar'));
Finder tab(String name) => find.byKey(Key('tab-$name'));
Finder get leftPanel => find.byKey(const Key('left-panel'));

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = phoneScreen,
  String? initialLocation,
  FakeApiClient? api,
}) async {
  Avatar.animationsEnabled = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh app, with a fresh router
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

/// Which tab is drawn in ink.
String selectedTab(WidgetTester tester) => AppTab.values
    .firstWhere(
      (t) =>
          tester.widget<Icon>(find.descendant(of: tab(t.name), matching: find.byType(Icon))).color ==
          AppColors.textPrimary,
    )
    .name;

void main() {
  group('on a phone', () {
    testWidgets('three tabs; Home is selected on /', (tester) async {
      await pumpApp(tester);
      expect(bar, findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Home')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Life tree')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Me')), findsOneWidget);
      expect(selectedTab(tester), 'home');
      for (final name in ['home', 'tree', 'me']) {
        expect(tester.getSize(tab(name)).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the tabs switch scenes', (tester) async {
      await pumpApp(tester);
      await tester.tap(tab('tree'));
      await tester.pumpAndSettle();
      expect(find.byType(MapScene), findsOneWidget);
      expect(selectedTab(tester), 'tree');

      await tester.tap(tab('me'));
      await tester.pumpAndSettle();
      expect(find.byType(MeScene), findsOneWidget);
      expect(leftPanel, findsOneWidget);
      expect(find.byKey(const Key('settings-button')), findsOneWidget);
      expect(selectedTab(tester), 'me');

      await tester.tap(tab('home'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScene), findsOneWidget);
      expect(selectedTab(tester), 'home');
    });

    testWidgets('the crystal ball still opens the life tree', (tester) async {
      await pumpApp(tester);
      final orb = find.byKey(const Key('crystal-ball'));
      expect(orb, findsOneWidget);
      await tester.tap(orb);
      await tester.pumpAndSettle();
      expect(find.byType(MapScene), findsOneWidget);
    });

    testWidgets('tab pages have no back arrow and no ☰; a node has its back arrow', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: AppRoutes.map);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.byKey(const Key('stage-title')), findsOneWidget);

      await pumpApp(tester, initialLocation: AppRoutes.skill(1));
      expect(find.byType(SkillScene), findsOneWidget);
      expect(find.byKey(const Key('back-map')), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(selectedTab(tester), 'tree'); // a node belongs to the life tree
    });

    testWidgets('Home has the chat history button at the top right', (tester) async {
      await pumpApp(tester);
      final button = find.byKey(const Key('open-right-drawer'));
      expect(button, findsOneWidget);
      final panel = tester.getRect(find.byKey(const Key('stage-panel')));
      expect(tester.getCenter(button).dx, greaterThan(panel.center.dx));
      expect(tester.getCenter(button).dy, lessThan(panel.top + AppPanel.barHeight));
    });

    testWidgets('the life overview sits under Me and goes back there', (tester) async {
      await pumpApp(tester, initialLocation: AppRoutes.life);
      expect(find.byType(LifeScene), findsOneWidget);
      expect(selectedTab(tester), 'me');
      await tester.tap(find.byKey(const Key('back-home')));
      await tester.pumpAndSettle();
      expect(find.byType(MeScene), findsOneWidget);
    });

    testWidgets('hidden during an audit, back after it', (tester) async {
      await pumpApp(tester, initialLocation: AppRoutes.audit(1));
      expect(find.byType(AuditScene), findsOneWidget);
      expect(bar, findsNothing);
      tester.element(find.byType(AuditScene)).go(AppRoutes.skill(1));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
    });

    testWidgets('hidden while the keyboard is up', (tester) async {
      await pumpApp(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(find.byType(HomeScene), findsOneWidget);
    });
  });

  group('on a wide screen', () {
    testWidgets('no tab bar: the left panel is there instead', (tester) async {
      await pumpApp(tester, size: wideScreen);
      expect(bar, findsNothing);
      expect(leftPanel, findsOneWidget);
      await pumpApp(tester, size: wideScreen, initialLocation: AppRoutes.map);
      expect(bar, findsNothing);
      expect(find.byKey(const Key('back-home')), findsOneWidget); // the map keeps its back arrow
    });

    testWidgets('/me goes home: the panel is already on screen', (tester) async {
      await pumpApp(tester, size: wideScreen, initialLocation: AppRoutes.me);
      expect(find.byType(HomeScene), findsOneWidget);
      expect(find.byType(MeScene), findsNothing);
    });
  });
}
