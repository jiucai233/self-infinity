// The guided tour a new account sees before the setup (ux-chat §7): the real
// scenes over an example world, one part lit at a time, then the setup, then
// the tree the setup built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/onboarding/guided_tour.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

String said(WidgetTester tester) => tester.widget<Text>(key('tour-text')).data!;

String progress(WidgetTester tester) => tester.widget<Text>(key('tour-progress')).data!;

Future<FakeApiClient> pumpNewAccount(WidgetTester tester, {Size size = wideScreen}) async {
  Avatar.animationsEnabled = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeApiClient(latency: Duration.zero, onboarded: false);
  await tester.pumpWidget(
    SelfInfinityApp(
      api: api,
      appState: AppState(),
      voice: FakeVoiceService(),
      filePicker: FakeFilePicker(),
    ),
  );
  await settle(tester);
  return api;
}

/// The page of a stop loads, then the tour looks for its anchor (every 120 ms,
/// and passes over a stop whose anchor is not on this screen).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(key('tour-next'));
  await settle(tester);
}

/// The part of the page left lit, as the scrim paints it.
Rect? lit(WidgetTester tester) {
  final painter = tester.widget<CustomPaint>(key('tour-scrim')).painter! as dynamic;
  return painter.lit as Rect?;
}

void main() {
  testWidgets('a new account gets the tour before the setup, over an example world', (tester) async {
    final api = await pumpNewAccount(tester);

    expect(find.byType(GuidedTour), findsOneWidget);
    expect(key('onboarding'), findsNothing);
    expect(said(tester), startsWith("Hi, I'm your Guide."));
    expect(progress(tester), '1 / 10');
    expect(lit(tester), isNull); // the welcome lights nothing
    expect(key('tour-back'), findsNothing);
    // The example is its own world: the account has nothing yet.
    expect(find.text('Teach calculus to a stranger'), findsWidgets);
    expect(await api.listCourses(), isEmpty);
    expect(await api.listGoals(), isEmpty);
  });

  testWidgets('it goes from the left panel across the stage to the tree, a node and an audit', (tester) async {
    await pumpNewAccount(tester);
    final seen = <String>[];
    final pages = <Type>[];
    for (var i = 0; i < 9; i++) {
      await next(tester);
      seen.add(said(tester).split(RegExp('[.:]')).first);
      pages.add(
        [HomeScene, MapScene, SkillScene, AuditScene].firstWhere((t) => find.byType(t).evaluate().isNotEmpty),
      );
      if (i < 8) expect(lit(tester), isNotNull, reason: 'stop ${i + 2} lights its part');
    }

    expect(seen, [
      'This side is you',
      'Your daily quests',
      'Talk to me here, typed or spoken',
      'Your life tree',
      'A node is one thing to learn',
      'This side keeps your attempts at this node',
      'To clear a node you explain it',
      'You teach, the Auditor learns',
      'That was an example',
    ]);
    expect(pages, [
      HomeScene, HomeScene, HomeScene, MapScene, SkillScene, SkillScene, SkillScene, AuditScene, MapScene,
    ]);
    expect(progress(tester), '10 / 10');
    expect(find.text('Set up my character'), findsOneWidget);
    expect(key('tour-skip'), findsNothing); // the last stop only goes on
  });

  testWidgets('the lit part is the thing the Guide talks about', (tester) async {
    await pumpNewAccount(tester);
    await next(tester);

    final panel = tester.getRect(key('left-panel'));
    expect(lit(tester)!.contains(panel.center), isTrue);
    expect(lit(tester)!.width, closeTo(panel.width + 12, 1)); // with its halo
    // The card stands beside it, not over it.
    expect(tester.getRect(key('tour-card')).overlaps(panel), isFalse);
  });

  testWidgets('the page under the tour cannot be tapped', (tester) async {
    await pumpNewAccount(tester);
    await next(tester);
    await next(tester);

    await tester.tapAt(tester.getCenter(find.textContaining('Linear Functions').first));
    await settle(tester);

    expect(find.byType(HomeScene), findsOneWidget); // the quest did not open
    expect(progress(tester), '3 / 10');
  });

  testWidgets('Back returns to the stop before, and to its page', (tester) async {
    await pumpNewAccount(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(find.byType(MapScene), findsOneWidget);

    await tester.tap(key('tour-back'));
    await settle(tester);

    expect(find.byType(HomeScene), findsOneWidget);
    expect(progress(tester), '4 / 10');
  });

  testWidgets('on a phone the stops in the side panels are passed over', (tester) async {
    await pumpNewAccount(tester, size: phoneScreen);
    await tester.tap(key('tour-next'));
    await tester.pump(); // at once: the left panel is in a drawer here

    expect(said(tester), startsWith('Talk to me here'));
    expect(progress(tester), '4 / 10');
    await settle(tester);
    expect(lit(tester), isNotNull);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(key('tour-card'));
    expect(card.left >= 0 && card.right <= phoneScreen.width, isTrue);
  });

  testWidgets('Skip the tour goes straight to the setup', (tester) async {
    await pumpNewAccount(tester);

    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();

    expect(find.byType(GuidedTour), findsNothing);
    expect(key('onboarding'), findsOneWidget);
  });

  testWidgets('after the last stop: the setup, which says what a syllabus does, then the tree it built', (
    tester,
  ) async {
    final api = await pumpNewAccount(tester);
    for (var i = 0; i < 10; i++) {
      await next(tester);
    }
    expect(key('onboarding'), findsOneWidget);

    await tester.tap(key('onboarding-continue')); // Begin
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(key('onboarding-skip'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Your answer shapes your first tree.'), findsOneWidget);
    expect(find.textContaining('its items are used as they are'), findsOneWidget);
    await tester.enterText(key('onboarding-input'), 'math');
    await tester.tap(key('onboarding-continue'));
    await tester.pumpAndSettle();
    await tester.tap(key('onboarding-finish'));
    await tester.pumpAndSettle();

    expect(find.byType(MapScene), findsOneWidget); // the user's own tree
    expect((await api.listCourses()).single.id, 1);
    expect((await api.getProfile()).onboarded, isTrue);
  });

  testWidgets('skipping the setup too opens the home page', (tester) async {
    await pumpNewAccount(tester);
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();

    await tester.tap(key('onboarding-skip-all'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScene), findsOneWidget);
  });
}
