// The guided tour a new account sees before the setup (ux-chat §7): the real
// scenes over an example world, one part lit at a time, then the setup, then
// the tree the setup built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/audit/replay_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/onboarding/guided_tour.dart';
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
    expect(said(tester), startsWith('Tell me here what you want to learn'));
    expect(progress(tester), '1 / 4');
    expect(find.byType(HomeScene), findsOneWidget);
    expect(key('tour-back'), findsNothing);
    // The example is its own world: the account has nothing yet.
    expect(find.text('Teach calculus to a stranger'), findsWidgets);
    expect(await api.listCourses(), isEmpty);
    expect(await api.listGoals(), isEmpty);
  });

  testWidgets('four stops: talk to the Guide, explain to the Auditor, the verdict, the tree', (tester) async {
    await pumpNewAccount(tester);
    final seen = [said(tester)];
    final pages = <Type>[HomeScene];
    expect(lit(tester), isNotNull);
    for (var i = 0; i < 3; i++) {
      await next(tester);
      seen.add(said(tester));
      pages.add(
        [HomeScene, AuditScene, ReplayScene, MapScene].firstWhere((t) => find.byType(t).evaluate().isNotEmpty),
      );
      expect(lit(tester), isNotNull, reason: 'stop ${i + 2} lights its part');
    }

    expect(seen, [
      'Tell me here what you want to learn, typed or spoken.',
      'To clear a node, you teach it to the Auditor.',
      'Then you get a score, what you missed, and a lesson.',
      'Every node you clear lights up your life tree.',
    ]);
    expect(pages, [HomeScene, AuditScene, ReplayScene, MapScene]);
    expect(progress(tester), '4 / 4');
    expect(find.text('Set up my character'), findsOneWidget);
    expect(key('tour-skip'), findsNothing); // the last stop only goes on
  });

  testWidgets('the lit part is the whole input bar, not just its field', (tester) async {
    for (final size in [wideScreen, phoneScreen]) {
      await pumpNewAccount(tester, size: size);

      final bar = tester.getRect(find.byType(Composer));
      final field = tester.getRect(key('stage-input'));
      expect(lit(tester), bar.inflate(4)); // with its 4 px outset
      expect(lit(tester)!.width, greaterThan(field.width + 40));
      // The card stands beside it, not over it.
      expect(tester.getRect(key('tour-card')).overlaps(bar), isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the page under the tour cannot be tapped', (tester) async {
    await pumpNewAccount(tester);

    await tester.tapAt(tester.getCenter(find.textContaining('Linear Functions').first));
    await settle(tester);

    expect(find.byType(HomeScene), findsOneWidget); // the quest did not open
    expect(progress(tester), '1 / 4');
  });

  testWidgets('Back returns to the stop before, and to its page', (tester) async {
    await pumpNewAccount(tester);
    await next(tester);
    expect(find.byType(AuditScene), findsOneWidget);

    await tester.tap(key('tour-back'));
    await settle(tester);

    expect(find.byType(HomeScene), findsOneWidget);
    expect(progress(tester), '1 / 4');
  });

  testWidgets('on a phone every stop fits', (tester) async {
    await pumpNewAccount(tester, size: phoneScreen);
    for (var i = 0; i < 4; i++) {
      expect(lit(tester), isNotNull);
      final card = tester.getRect(key('tour-card'));
      expect(card.left >= 0 && card.right <= phoneScreen.width, isTrue);
      expect(tester.takeException(), isNull);
      if (i < 3) await next(tester);
    }
    expect(progress(tester), '4 / 4');
  });

  testWidgets('Skip the tour goes straight to the first question of the setup', (tester) async {
    await pumpNewAccount(tester);

    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();

    expect(find.byType(GuidedTour), findsNothing);
    expect(key('onboarding-step-stakes'), findsOneWidget);
  });

  testWidgets('after the last stop: the setup, which says what a syllabus does, then the tree it built', (
    tester,
  ) async {
    final api = await pumpNewAccount(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    // The tour ended on "Set up my character": no welcome page again.
    expect(key('onboarding-step-stakes'), findsOneWidget);
    expect(key('onboarding-back'), findsNothing);
    expect(key('onboarding-skip'), findsNothing); // one skip per page: Skip setup
    expect(key('onboarding-skip-all'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(key('onboarding-continue')); // empty: passed over
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Your answer shapes your first tree.'), findsOneWidget);
    expect(find.textContaining('syllabus file (PDF'), findsOneWidget);
    await tester.enterText(key('onboarding-input'), 'math');
    await tester.tap(key('onboarding-continue'));
    await tester.pumpAndSettle();
    expect(key('onboarding-skip-all'), findsNothing); // built: Enter is the way out
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
