// Accounts and the first-run tutorial (docs/ux-chat.md §7), through the real app shell.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/auth/auth_service.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/testing/fake_auth.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/upload/file_picker_service.dart';
import 'package:self_infinity/widgets/widgets.dart';

import 'support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeApiClient api,
  AuthService? auth,
  FakeFilePicker? picker,
  FakeVoiceService? voice,
  Size size = wideScreen,
}) async {
  Avatar.animationsEnabled = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SelfInfinityApp(
      api: api,
      appState: AppState(),
      auth: auth,
      voice: voice ?? FakeVoiceService(),
      filePicker: picker ?? FakeFilePicker(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String k, String text) async {
  await tester.enterText(key(k), text);
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

/// Answers the current question and continues.
Future<void> answer(WidgetTester tester, String text) async {
  await enter(tester, 'onboarding-input', text);
  await tapKey(tester, 'onboarding-continue');
}

void main() {
  group('sign in', () {
    testWidgets('signed out: the landing hero; Sign in opens the form over it', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: FakeAuthService());
      expect(key('sign-in'), findsOneWidget);
      expect(find.byType(HomeScene), findsNothing);
      expect(key('hero-headline'), findsOneWidget);
      expect(key('auth-card'), findsNothing);
      await tapKey(tester, 'hero-sign-in');
      expect(key('auth-card'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('Get started opens the sign-up form, I have an account the sign-in one', (
      tester,
    ) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: FakeAuthService());
      await tapKey(tester, 'hero-get-started');
      expect(find.text('Create your account'), findsOneWidget);
      await tapKey(tester, 'auth-close');
      expect(key('auth-card'), findsNothing);
      await tapKey(tester, 'hero-have-account');
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('the form closes with ×, a tap outside it, or Esc', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: FakeAuthService());
      await tapKey(tester, 'hero-sign-in');
      await tester.tapAt(const Offset(8, 8)); // the scrim
      await tester.pumpAndSettle();
      expect(key('auth-card'), findsNothing);
      await tapKey(tester, 'hero-sign-in');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('auth-card'), findsNothing);
    });

    testWidgets('clean: the name, Sign in, one sentence, two buttons; a phone fits it all', (
      tester,
    ) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: FakeAuthService());
      expect(key('hero-brand'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await pumpApp(
        tester,
        api: FakeApiClient(latency: Duration.zero),
        auth: FakeAuthService(),
        size: phoneScreen,
      );
      expect(key('hero-brand'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'hero-get-started');
      expect(key('auth-card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('checks the fields before calling the server', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: FakeAuthService());
      await tapKey(tester, 'hero-sign-in');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tapKey(tester, 'auth-switch'); // create account
      await enter(tester, 'auth-email', 'a@b.co');
      await enter(tester, 'auth-password', '123');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Use at least 6 characters for your password.'), findsOneWidget);
    });

    testWidgets('wrong password: an error, still on the page', (tester) async {
      final auth = FakeAuthService(accounts: {'me@x.io': 'right-one'});
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: auth);
      await tapKey(tester, 'hero-sign-in');
      await enter(tester, 'auth-email', 'me@x.io');
      await enter(tester, 'auth-password', 'wrong-one');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(auth.signedIn, isFalse);
    });

    testWidgets('sign up → check your inbox → confirm → sign in → the tutorial', (tester) async {
      final auth = FakeAuthService(confirmEmail: true);
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false), auth: auth);
      await tapKey(tester, 'hero-sign-in');
      await tapKey(tester, 'auth-switch');
      expect(find.text('Create your account'), findsOneWidget);
      await enter(tester, 'auth-email', 'new@x.io');
      await enter(tester, 'auth-password', 'secret1');
      await tapKey(tester, 'auth-submit');
      expect(key('check-inbox'), findsOneWidget);
      expect(find.textContaining('new@x.io'), findsOneWidget);
      // Signing in before confirming fails.
      await tapKey(tester, 'back-to-sign-in');
      await enter(tester, 'auth-email', 'new@x.io');
      await enter(tester, 'auth-password', 'secret1');
      await tapKey(tester, 'auth-submit');
      expect(find.text('Confirm your email first — check your inbox.'), findsOneWidget);
      auth.confirm('new@x.io');
      await tapKey(tester, 'auth-submit');
      expect(key('onboarding'), findsOneWidget);
    });

    testWidgets('forgot password sends the reset email', (tester) async {
      final auth = FakeAuthService(accounts: {'me@x.io': 'secret1'});
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: auth);
      await tapKey(tester, 'hero-sign-in');
      await tapKey(tester, 'auth-forgot');
      expect(find.text('Enter your email above first.'), findsOneWidget);
      await enter(tester, 'auth-email', 'me@x.io');
      await tapKey(tester, 'auth-forgot');
      expect(key('reset-sent'), findsOneWidget);
      expect(auth.resets, ['me@x.io']);
    });

    testWidgets('an onboarded account goes straight home; signing out returns to sign-in', (tester) async {
      final auth = FakeAuthService(accounts: {'me@x.io': 'secret1'});
      await auth.signIn('me@x.io', 'secret1');
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero), auth: auth);
      expect(find.byType(HomeScene), findsOneWidget);
      await tapKey(tester, 'settings-button');
      await tapKey(tester, 'settings-sign-out');
      expect(key('sign-in'), findsOneWidget);
    });
  });

  group('local mode', () {
    testWidgets('View the front page shows the landing; any login comes back to the same data', (
      tester,
    ) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.createGoal('Keep this quest');
      await pumpApp(tester, api: api);
      expect(find.byType(HomeScene), findsOneWidget);
      await tapKey(tester, 'settings-button');
      await tapKey(tester, 'settings-front-page');
      expect(key('hero-headline'), findsOneWidget);
      await tapKey(tester, 'hero-have-account');
      await enter(tester, 'auth-email', 'me@local.test');
      await enter(tester, 'auth-password', 'whatever');
      await tapKey(tester, 'auth-submit');
      expect(find.byType(HomeScene), findsOneWidget);
      expect((await api.listGoals()).single.title, 'Keep this quest');
    });
  });

  group('the tutorial', () {
    testWidgets('local mode, not onboarded: the tutorial comes first, no sign-in', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false));
      expect(key('sign-in'), findsNothing);
      expect(key('onboarding'), findsOneWidget);
      expect(find.text("Let's set up your character."), findsOneWidget);
    });

    testWidgets('the whole way: answers are saved, the course lands under the quest', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await pumpApp(tester, api: api);
      await tapKey(tester, 'onboarding-continue'); // Begin
      expect(find.text('Step 1 of 6'), findsOneWidget);
      await answer(tester, 'Another year of nodding along.');
      await answer(tester, 'I can teach calculus.');
      // The identity line starts with the stem.
      expect(tester.widget<TextField>(key('onboarding-input')).controller!.text, 'I am the type of person who ');
      await answer(tester, 'I am the type of person who explains first.');
      await answer(tester, 'Teach calculus to a stranger');
      expect(find.text('What do you need to learn first for “Teach calculus to a stranger”?'), findsOneWidget);
      await answer(tester, 'math');
      expect(find.text('Your world “High School Math” is ready.'), findsOneWidget);
      await tapKey(tester, 'onboarding-continue');
      expect(key('onboarding-ball'), findsOneWidget);
      await tapKey(tester, 'onboarding-continue');
      await tapKey(tester, 'onboarding-continue');
      await tapKey(tester, 'onboarding-finish');
      expect(find.byType(HomeScene), findsOneWidget);

      final profile = await api.getProfile();
      expect(profile.onboarded, isTrue);
      expect(profile.antiVision, 'Another year of nodding along.');
      expect(profile.vision, 'I can teach calculus.');
      expect(profile.identity, 'I am the type of person who explains first.');
      final goal = (await api.listGoals()).single;
      expect(goal.title, 'Teach calculus to a stranger');
      expect(goal.courseIds, [1]);
      // The course was made in the chat, so the conversation starts with it.
      expect((await api.getChatHistory()).first.content, 'I want to learn math');
    });

    testWidgets('a syllabus file instead of a topic', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      final picker = FakeFilePicker()..next = PickedFile(name: 'Linear Algebra.txt', bytes: 'Vectors and matrices'.codeUnits);
      await pumpApp(tester, api: api, picker: picker);
      await tapKey(tester, 'onboarding-continue');
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'onboarding-skip');
      }
      await tapKey(tester, 'onboarding-upload');
      expect(find.text('Linear Algebra.txt'), findsOneWidget);
      await tapKey(tester, 'onboarding-continue');
      expect(find.textContaining('is ready.'), findsOneWidget);
      expect(await api.listCourses(), hasLength(1));
      expect(await api.listGoals(), isEmpty); // the quest was skipped
    });

    testWidgets('building needs a topic or a file', (tester) async {
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false));
      await tapKey(tester, 'onboarding-continue');
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'onboarding-skip');
      }
      await tapKey(tester, 'onboarding-continue');
      expect(find.text('Tell me a topic, or pick a syllabus file.'), findsOneWidget);
    });

    testWidgets('a failing build says so and can be retried', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await pumpApp(tester, api: api);
      await tapKey(tester, 'onboarding-continue');
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'onboarding-skip');
      }
      api.failNext(method: 'sendChat');
      await answer(tester, 'math');
      expect(find.text("I couldn't build that world. Try again, or skip for now."), findsOneWidget);
      await tapKey(tester, 'onboarding-continue');
      expect(find.text('Your world “High School Math” is ready.'), findsOneWidget);
    });

    testWidgets('the course is built whatever the front desk would make of the topic', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await pumpApp(tester, api: api);
      await tapKey(tester, 'onboarding-continue');
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'onboarding-skip');
      }
      // "I want to learn Sleep science" reads as a check-in to the front desk
      // (check-in words win); with courseTopic it is not asked.
      await answer(tester, 'Sleep science');
      expect(find.text('Your world “Sleep science” is ready.'), findsOneWidget);
      expect((await api.listCourses()).single.topic, 'Sleep science');
    });

    testWidgets('the mic types what you say into the answer', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      final voice = FakeVoiceService();
      await pumpApp(tester, api: api, voice: voice);
      await tapKey(tester, 'onboarding-continue'); // Begin
      await tapKey(tester, 'dictation-button');
      expect(voice.listenCalls, 1);
      expect(key('dictation-stop'), findsOneWidget);
      voice.partial('Another year');
      await tester.pump();
      expect(tester.widget<TextField>(key('onboarding-input')).controller!.text, 'Another year');
      voice.hear('Another year of nodding along.');
      await tester.pumpAndSettle();
      expect(key('dictation-button'), findsOneWidget);
      await tapKey(tester, 'onboarding-continue');
      expect((await api.getProfile()).antiVision, 'Another year of nodding along.');
    });

    testWidgets('dictation goes after what is already written (the identity stem)', (tester) async {
      final voice = FakeVoiceService();
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false), voice: voice);
      await tapKey(tester, 'onboarding-continue');
      await answer(tester, 'x');
      await answer(tester, 'y');
      await tapKey(tester, 'dictation-button');
      voice.hear('explains first.');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('onboarding-input')).controller!.text,
        'I am the type of person who explains first.',
      );
      // Typed text without a trailing space gets one before the next words.
      await enter(tester, 'onboarding-input', 'I am the type of person who explains');
      await tapKey(tester, 'dictation-button');
      voice.hear('first.');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('onboarding-input')).controller!.text,
        'I am the type of person who explains first.',
      );
    });

    testWidgets('stop, or Continue, ends the listening; late words are dropped', (tester) async {
      final voice = FakeVoiceService();
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false), voice: voice);
      await tapKey(tester, 'onboarding-continue');
      await tapKey(tester, 'dictation-button');
      await tapKey(tester, 'dictation-stop');
      expect(voice.isListening, isFalse);
      expect(key('dictation-button'), findsOneWidget);

      await tapKey(tester, 'dictation-button');
      voice.partial('Half a thought');
      await tester.pump();
      await tapKey(tester, 'onboarding-continue'); // next question, mic off
      expect(voice.isListening, isFalse);
      expect(find.text("A year from now, you've won. What does that look like?"), findsOneWidget);
      voice.partial('Half a thought, later');
      await tester.pump();
      expect(tester.widget<TextField>(key('onboarding-input')).controller!.text, isEmpty);
    });

    testWidgets('no speech recognition here: a toast, the field still works', (tester) async {
      final voice = FakeVoiceService(available: false);
      await pumpApp(tester, api: FakeApiClient(latency: Duration.zero, onboarded: false), voice: voice);
      await tapKey(tester, 'onboarding-continue');
      await tester.tap(key('dictation-button'));
      await tester.pump();
      expect(find.text(DictationButton.unavailableText), findsOneWidget);
      expect(voice.listenCalls, 0);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Skip setup ends it at once', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await pumpApp(tester, api: api);
      await tapKey(tester, 'onboarding-skip-all');
      expect(find.byType(HomeScene), findsOneWidget);
      expect((await api.getProfile()).onboarded, isTrue);
    });

    testWidgets('on a phone nothing overflows', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await pumpApp(tester, api: api, size: phoneScreen);
      await tapKey(tester, 'onboarding-continue');
      await answer(tester, 'x');
      await tapKey(tester, 'dictation-button'); // the listening state is wider
      expect(tester.takeException(), isNull);
    });

    testWidgets('Replay the tutorial edits the first quest instead of adding one', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, onboarded: false);
      await api.createGoal('Old quest');
      await pumpApp(tester, api: api);
      await tapKey(tester, 'onboarding-continue');
      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'onboarding-skip');
      }
      expect(find.text('Old quest'), findsOneWidget);
      await answer(tester, 'New quest');
      expect((await api.listGoals()).map((g) => g.title), ['New quest']);
    });
  });
}
