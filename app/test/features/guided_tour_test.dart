// The guided tour (ux-chat §7): the real scenes over an example world, one
// part lit at a time — and that part works: the user builds a course, opens
// the tree, takes a node on and clears it by hand (or lets the card's button
// do each part). A new account gets it before the setup; the front page opens
// it without an account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/onboarding/guided_tour.dart';
import 'package:self_infinity/testing/fake_auth.dart';
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

/// The page under the tour answers (120 ms looks), then the tour moves on.
Future<void> does(WidgetTester tester, Future<void> Function() act) async {
  await act();
  await settle(tester);
}

Future<void> answer(WidgetTester tester, String text) => does(tester, () async {
  await tester.enterText(key('stage-input'), text);
  await tester.pump();
  await tester.tap(key('send'));
});

const List<String> script = [
  'Tell me here what you want to learn. Type anything and send it.',
  'Your course is built: a tree of ideas to prove, one node at a time. Open it.',
  'Your next nodes, each tied to its point on your tree. Tap one.',
  'Read what is here first. When you are ready, tap Take it on: you explain it to the Auditor in your own words.',
  'To clear a node, you teach it to the Auditor. Explain it in your own words; in this tour anything you say works.',
  'She asks again where it was thin. Answer once more.',
  'Cleared! Stars for how thoroughly you were asked, and XP toward your level.',
  'Each audit leaves a verdict: your score, the points you held, and what to tighten.',
  'Every node you clear lights up your life tree.',
];

void main() {
  testWidgets('a new account gets the tour before the setup, over an empty example world', (
    tester,
  ) async {
    final api = await pumpNewAccount(tester);

    expect(find.byType(GuidedTour), findsOneWidget);
    expect(key('onboarding'), findsNothing);
    expect(said(tester), script.first);
    expect(progress(tester), '1 / 9');
    expect(find.byType(HomeScene), findsOneWidget);
    expect(key('tour-try-hint'), findsOneWidget);
    expect(lit(tester), isNotNull);
    expect(await api.listCourses(), isEmpty);
  });

  testWidgets('by hand: build a course, open the tree, take a node on, clear it', (tester) async {
    final api = await pumpNewAccount(tester);
    final seen = [said(tester)];
    void stop(int n) {
      expect(progress(tester), '$n / 9');
      seen.add(said(tester));
    }

    // Anything typed builds a course of it.
    await answer(tester, 'I want to learn knots');
    stop(2);
    expect(find.textContaining('knots'), findsWidgets);
    expect(lit(tester), tester.getRect(key('action-map')).inflate(1));

    await does(tester, () => tester.tap(key('action-map')));
    stop(3);
    expect(key('life-board'), findsOneWidget);
    expect(lit(tester), tester.getRect(key('orb-picks')).inflate(1));

    final pick = find.descendant(of: key('orb-picks'), matching: find.byType(InkWell)).first;
    await does(tester, () => tester.tap(pick));
    stop(4);
    expect(find.byType(SkillScene), findsOneWidget);

    await does(tester, () => tester.tap(key('start-audit')));
    stop(5);
    expect(find.byType(AuditScene), findsOneWidget);

    // Whatever is said passes in the tour: one question back, then cleared.
    await answer(tester, 'x');
    stop(6);
    expect(key('celebration-card'), findsNothing);
    await answer(tester, 'y');
    stop(7);
    expect(key('celebration-card'), findsOneWidget);
    expect(lit(tester), tester.getRect(key('celebration-card')).inflate(1));
    expect(tester.getRect(key('tour-card')).overlaps(tester.getRect(key('celebration-card'))), isFalse);

    await next(tester);
    stop(8);
    expect(key('celebration-card'), findsNothing);
    expect(key('audit-verdict'), findsOneWidget);
    expect(tester.widget<StarRow>(key('verdict-stars')).stars, greaterThan(0));

    await next(tester);
    stop(9);
    expect(find.byType(HomeScene), findsOneWidget);
    expect(find.text('Set up my character'), findsOneWidget);
    expect(key('tour-skip'), findsNothing); // the last stop only goes on

    expect(seen, script);
    // All of it was the example world's: the account has nothing yet.
    expect(await api.listCourses(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the card's button does each part for the user", (tester) async {
    await pumpNewAccount(tester);
    final pages = <Type>[];
    for (var i = 0; i < 8; i++) {
      expect(said(tester), script[i]);
      pages.add(
        [HomeScene, AuditScene, SkillScene].firstWhere((t) => find.byType(t).evaluate().isNotEmpty),
      );
      await next(tester);
      expect(progress(tester), '${i + 2} / 9', reason: 'after stop ${i + 1}');
    }
    expect(pages, [
      HomeScene, HomeScene, HomeScene, SkillScene, //
      AuditScene, AuditScene, AuditScene, AuditScene,
    ]);
    expect(said(tester), script.last);
    expect(find.byType(HomeScene), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lit part is the whole input bar, not just its field', (tester) async {
    for (final size in [wideScreen, phoneScreen]) {
      await pumpNewAccount(tester, size: size);

      final bar = tester.getRect(find.byType(Composer));
      final field = tester.getRect(key('stage-input'));
      expect(lit(tester), bar.inflate(1)); // with its 1 px frame
      expect(lit(tester)!.width, greaterThan(field.width + 40));
      // The card stands beside it, not over it.
      expect(tester.getRect(key('tour-card')).overlaps(bar), isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('outside the lit part the page cannot be tapped', (tester) async {
    await pumpNewAccount(tester);

    await tester.tapAt(tester.getCenter(key('view-outline')));
    await settle(tester);
    expect(key('outline-panel'), findsNothing); // the board did not switch
    expect(progress(tester), '1 / 9');

    // A look stop lets nothing through, the lit part included.
    for (var i = 0; i < 6; i++) {
      await next(tester);
    }
    expect(progress(tester), '7 / 9');
    await tester.tapAt(tester.getCenter(key('celebration-continue')));
    await settle(tester);
    expect(find.byType(AuditScene), findsOneWidget);
    expect(progress(tester), '7 / 9');
  });

  testWidgets('on a phone every stop fits, by hand or not', (tester) async {
    await pumpNewAccount(tester, size: phoneScreen);
    for (var i = 0; i < 9; i++) {
      expect(progress(tester), '${i + 1} / 9');
      expect(lit(tester), isNotNull, reason: 'stop ${i + 1} lights its part');
      final card = tester.getRect(key('tour-card'));
      expect(card.left >= 0 && card.right <= phoneScreen.width, isTrue);
      expect(card.top >= 0 && card.bottom <= phoneScreen.height, isTrue);
      expect(tester.takeException(), isNull);
      if (i < 8) await next(tester);
    }
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
    for (var i = 0; i < 9; i++) {
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

    expect(find.byType(HomeScene), findsOneWidget); // the user's own tree
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

  group('without an account', () {
    Future<(FakeApiClient, FakeAuthService)> pumpFrontPage(WidgetTester tester) async {
      Avatar.animationsEnabled = false;
      tester.view.physicalSize = wideScreen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      final auth = FakeAuthService();
      await tester.pumpWidget(
        SelfInfinityApp(
          api: api,
          appState: AppState(),
          auth: auth,
          voice: FakeVoiceService(),
          filePicker: FakeFilePicker(),
        ),
      );
      await tester.pumpAndSettle();
      return (api, auth);
    }

    testWidgets('the sign-in form offers the tour; it ends on Create account', (tester) async {
      final (api, auth) = await pumpFrontPage(tester);
      api.failNext(method: 'getProfile'); // the server is not asked for anything

      await tester.tap(key('hero-sign-in'));
      await tester.pumpAndSettle();
      expect(find.text('Try it without an account'), findsOneWidget);
      await tester.tap(key('auth-guest'));
      await settle(tester);

      expect(find.byType(GuidedTour), findsOneWidget);
      expect(said(tester), script.first);
      expect(auth.signedIn, isFalse);
      for (var i = 0; i < 8; i++) {
        await next(tester);
      }
      expect(progress(tester), '9 / 9');
      expect(find.text('Create my account'), findsOneWidget);
      await tester.tap(key('tour-next'));
      await tester.pumpAndSettle();

      expect(find.byType(GuidedTour), findsNothing);
      expect(key('auth-card'), findsOneWidget);
      expect(tester.widget<Text>(key('auth-title')).data, 'Create your account');
      expect(await api.listCourses(), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('skipped, it is back on the front page', (tester) async {
      await pumpFrontPage(tester);
      await tester.tap(key('hero-get-started'));
      await tester.pumpAndSettle();
      await tester.tap(key('auth-guest'));
      await settle(tester);
      await tester.tap(key('tour-skip'));
      await tester.pumpAndSettle();

      expect(key('sign-in'), findsOneWidget);
      expect(key('auth-card'), findsOneWidget);
    });
  });
}
