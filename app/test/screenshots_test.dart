// Renders every scene to a PNG for a visual check. Not a regression test: it
// only runs when SHOTS_DIR is set and never compares anything.
//
//   SHOTS_DIR=/some/dir flutter test test/screenshots_test.dart
//   SHOTS_LANG=zh (or ko) renders them in that language.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/auth/auth_service.dart';
import 'package:self_infinity/testing/fake_auth.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/upload/file_picker_service.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/widgets/avatar.dart';
import 'package:self_infinity/widgets/life_constellation.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/theme/tokens.dart';

const _flutterFonts = '/Users/jiucai/development/flutter/bin/cache/artifacts/material_fonts';

/// The app's own fonts (the bundled sans and serif, and every CJK family), and
/// icons in the Material Icons font.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await loader.load();
  }

  await load(AppFonts.sans, [
    for (final w in ['Regular', 'Medium', 'SemiBold']) 'assets/fonts/InfinitySans-$w.ttf',
  ]);
  await load(AppFonts.display, [
    for (final s in ['Regular', 'Italic']) 'assets/fonts/InstrumentSerif-$s.ttf',
  ]);
  for (final language in AppLanguage.values) {
    for (final font in AppFonts.bundledFor(language)) {
      await load(font.name, [for (final f in font.files) 'assets/fonts/cjk/$f']);
    }
  }
  await load('MaterialIcons', ['$_flutterFonts/MaterialIcons-Regular.otf']);
}

/// `SHOTS_LANG`: the language of the screenshots (English by default).
final AppLanguage _language = AppLanguage.fromCode(Platform.environment['SHOTS_LANG']);

Future<FakeApiClient> _seed() async {
  final api = FakeApiClient(latency: Duration.zero);
  await api.generateCourse(const GenerateRequest(topic: 'math'));
  // Math: pass the root and Algebra, fail Functions, leave the rest.
  await passAudit(api, 1);
  await passAudit(api, 2);
  final failed = await failAudit(api, 3);
  await api.submitReflection(failed.sessionId, 'I just memorized Quadratic Functions');
  await api.createSearchPlan(3, gap: 'the definition of a function');
  await api.createSearchPlan(3, gap: 'reading graphs');
  await api.sendChat('I slept six hours and had ramen for lunch. I am a bit tired.');
  await api.updateProfile(
    identity: 'I am the type of person who explains it before I memorize it.',
    vision: 'Understand calculus well enough to teach it to a stranger.',
    antiVision: 'Another year of nodding along without really knowing.',
    rules: ['No phone before the first audit', 'Explain, never copy', 'Stop at 23:00'],
  );
  await api.sendChat('What should I do today?');
  await passAudit(api, 5); // one of today's quests is done
  // A second course (a side quest) and a main quest the math course serves.
  await api.generateCourse(const GenerateRequest(topic: 'Writing'));
  final goal = await api.createGoal('Teach calculus to a stranger');
  await api.updateGoal(goal.id, courseIds: [1]);
  await api.createGoal('Write every week');
  return api;
}

/// Taps the point [key] of the life tree.
Future<void> tapLifeNode(WidgetTester tester, String key) async {
  final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
  final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
  final at = state.positionOf(key)!;
  await tester.tapAt(box.localToGlobal(at));
  await tester.pumpAndSettle();
}

void main() {
  final dir = Platform.environment['SHOTS_DIR'];

  Future<void> shot(WidgetTester tester, String name) async {
    if (dir == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Future<void> scene(
    WidgetTester tester, {
    required Size size,
    required String name,
    required String location,
    FakeApiClient? api,
    Future<void> Function(WidgetTester tester)? act,
    bool seeded = true,
    FakeVoiceService? voice,
    AuthService? auth,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Avatar.animationsEnabled = false;
    debugDisableShadows = false; // flutter_test draws shadows hard-edged otherwise
    final fake = api ?? (seeded ? await _seed() : FakeApiClient(latency: Duration.zero));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: SelfInfinityApp(
          api: fake,
          appState: AppState(),
          auth: auth,
          voice: voice ?? FakeVoiceService(),
          filePicker: FakeFilePicker(),
          initialLocation: location,
          locale: LocaleController(_language),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    if (act != null) await act(tester);
    await shot(tester, name);
    debugDisableShadows = true; // the test binding checks that it is back
  }

  const sizes = {'wide': Size(1440, 900), 'narrow': Size(390, 844)};

  setUpAll(() async {
    if (dir != null) await _loadFonts();
  });

  for (final entry in sizes.entries) {
    final tag = entry.key;
    final size = entry.value;

    testWidgets(skip: dir == null, 'scene 1 enter ($tag)', (tester) async {
      await scene(tester, size: size, name: '1-enter-$tag', location: '/');
    });
    testWidgets(skip: dir == null, 'scene 1 no course ($tag)', (tester) async {
      await scene(tester, size: size, name: '1-enter-empty-$tag', location: '/', seeded: false);
    });
    testWidgets(skip: dir == null, 'scene 1 typing ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '1-typing-$tag',
        location: '/',
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), 'Hi');
          await t.pump();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 2 map ($tag)', (tester) async {
      await scene(tester, size: size, name: '2-map-$tag', location: '/map');
    });
    testWidgets(skip: dir == null, 'sign in ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '0-sign-in-$tag',
        location: '/',
        auth: FakeAuthService(),
      );
    });
    testWidgets(skip: dir == null, 'sign in form ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '0-sign-in-form-$tag',
        location: '/',
        auth: FakeAuthService(),
        act: (t) async {
          await t.tap(find.byKey(const Key('hero-have-account')));
          await t.pumpAndSettle();
        },
      );
    });
    for (final screen in [0, 1, 2, 3, 4, 5]) {
      testWidgets(skip: dir == null, 'front page, screen $screen ($tag)', (tester) async {
        await scene(
          tester,
          size: size,
          name: '0-landing-$screen-$tag',
          location: '/',
          auth: FakeAuthService(),
          act: (t) async {
            // The film's track loads, and images decode, for real, outside the fake clock.
            bool filmOn() {
              final robot = find.byKey(const Key('landing-robot'));
              if (robot.evaluate().isEmpty) return false;
              final image = t.widget<Image>(robot).image;
              return image is AssetImage && image.assetName.contains('frames');
            }

            for (var i = 0; i < 30 && !filmOn(); i++) {
              await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
              await t.pump();
            }
            for (var i = 0; i < screen; i++) {
              await t.drag(find.byKey(const Key('landing-scroll')), const Offset(0, -300));
              await t.pumpAndSettle();
            }
            final robot = find.byKey(const Key('landing-robot'));
            if (robot.evaluate().isNotEmpty) {
              final image = t.widget<Image>(robot).image;
              await t.runAsync(() => precacheImage(image, t.element(robot)));
              await t.pump();
            }
          },
        );
      });
    }
    testWidgets(skip: dir == null, 'check your inbox ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '0-check-inbox-$tag',
        location: '/',
        auth: FakeAuthService(confirmEmail: true),
        act: (t) async {
          await t.tap(find.byKey(const Key('hero-get-started')));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('auth-email')), 'you@example.com');
          await t.enterText(find.byKey(const Key('auth-password')), 'secret123');
          await t.tap(find.byKey(const Key('auth-submit')));
          await t.pumpAndSettle();
        },
      );
    });
    Future<void> onboarding(
      WidgetTester tester,
      String name,
      int steps, {
      List<String> answers = const [],
    }) async {
      await scene(
        tester,
        size: size,
        name: '$name-$tag',
        location: '/',
        api: FakeApiClient(latency: Duration.zero, onboarded: false),
        act: (t) async {
          for (var i = 0; i < steps; i++) {
            if (i > 0 && i - 1 < answers.length && answers[i - 1].isNotEmpty) {
              await t.enterText(find.byKey(const Key('onboarding-input')), answers[i - 1]);
            }
            await t.tap(find.byKey(const Key('onboarding-continue')));
            await t.pumpAndSettle();
          }
        },
      );
    }

    testWidgets(skip: dir == null, 'tutorial welcome ($tag)', (tester) async {
      await onboarding(tester, '0-tutorial-welcome', 0);
    });
    testWidgets(skip: dir == null, 'tutorial stakes ($tag)', (tester) async {
      await onboarding(tester, '0-tutorial-stakes', 1);
    });
    testWidgets(skip: dir == null, 'tutorial dictating ($tag)', (tester) async {
      final voice = FakeVoiceService();
      await scene(
        tester,
        size: size,
        name: '0-tutorial-dictating-$tag',
        location: '/',
        voice: voice,
        api: FakeApiClient(latency: Duration.zero, onboarded: false),
        act: (t) async {
          await t.tap(find.byKey(const Key('onboarding-continue')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('dictation-button')));
          await t.pumpAndSettle();
          voice.partial('Another year of nodding along in class');
          voice.level(0.7);
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'tutorial course ($tag)', (tester) async {
      await onboarding(
        tester,
        '0-tutorial-course',
        5,
        answers: [
          'Another year of nodding along.',
          'I can teach it.',
          '',
          'Teach calculus to a stranger',
        ],
      );
    });
    testWidgets(skip: dir == null, 'tutorial course ready ($tag)', (tester) async {
      await onboarding(
        tester,
        '0-tutorial-ready',
        6,
        answers: [
          'Another year of nodding along.',
          'I can teach it.',
          '',
          'Teach calculus to a stranger',
          'math',
        ],
      );
    });
    testWidgets(skip: dir == null, 'tutorial tour ($tag)', (tester) async {
      await onboarding(
        tester,
        '0-tutorial-tour',
        7,
        answers: [
          'Another year of nodding along.',
          'I can teach it.',
          '',
          'Teach calculus to a stranger',
          'math',
        ],
      );
    });
    testWidgets(skip: dir == null, 'scene 2 a node card ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '2-life-node-$tag',
        location: '/map',
        act: (t) => tapLifeNode(t, 's3'),
      );
    });
    testWidgets(skip: dir == null, 'scene 2 outline ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '2-outline-$tag',
        location: '/map',
        act: (t) async {
          await t.tap(find.byKey(const Key('view-outline')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 2 map, a fresh course ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.generateCourse(const GenerateRequest(topic: 'probability'));
      await scene(tester, size: size, name: '2-map-fresh-$tag', location: '/map', api: api);
    });
    testWidgets(skip: dir == null, 'scene 2 searching ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '2-map-search-$tag',
        location: '/map',
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), 'Function');
          await t.pump();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4 node ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-node-$tag', location: '/skill/3');
    });
    testWidgets(skip: dir == null, 'scene 4 locked ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-locked-$tag', location: '/skill/12');
    });
    testWidgets(skip: dir == null, 'scene 4-1 asking ($tag)', (tester) async {
      await scene(tester, size: size, name: '41-asking-$tag', location: '/skill/4/audit');
    });
    testWidgets(skip: dir == null, 'scene 4-1 failed ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '41-failed-$tag',
        location: '/skill/4/audit',
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), shortAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4-1 recorder ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '41-recorder-$tag',
        location: '/skill/4/audit',
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), shortAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('audit-next')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4-1 passed ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '41-passed-$tag',
        location: '/skill/4/audit',
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), longAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 5 chat ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '5-chat-$tag',
        location: '/',
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), 'I want to learn math');
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 5 upload chip ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '5-upload-$tag',
        location: '/',
        act: (t) async {
          final picker =
              t.widget<SelfInfinityApp>(find.byType(SelfInfinityApp)).filePicker! as FakeFilePicker;
          picker.next = PickedFile(name: 'Calculus syllabus.pdf', bytes: [1, 2, 3]);
          await t.tap(find.byKey(const Key('upload')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 1 two cards ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '1-enter-cards-$tag',
        location: '/',
        api: await seededFakeApi(),
      );
    });
    testWidgets(skip: dir == null, 'scene 5 several agents ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '5-chat-agents-$tag',
        location: '/',
        act: (t) async {
          for (final line in [
            'Give me a status report',
            'What should I do today?',
            'I want to learn math',
          ]) {
            await t.enterText(find.byKey(const Key('stage-input')), line);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 5 thinking ($tag)', (tester) async {
      final api = FakeApiClient(latency: const Duration(seconds: 2));
      await scene(
        tester,
        size: size,
        name: '5-thinking-done-$tag',
        location: '/',
        api: api,
        act: (t) async {
          await t.pump(const Duration(seconds: 3)); // the first loads
          await t.enterText(find.byKey(const Key('stage-input')), 'Give me a status report');
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pump(const Duration(milliseconds: 200));
          await shot(t, '5-thinking-$tag');
          await t.pump(const Duration(seconds: 5));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'panels collapsed ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '5-collapsed-$tag',
        location: '/',
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), 'Hello there');
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
          if (find.byKey(const Key('collapse-left')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('collapse-left')));
            await t.tap(find.byKey(const Key('collapse-right')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4-1 celebration with level up ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      for (final id in [1, 2, 3, 4]) {
        await passAudit(api, id);
      }
      await scene(
        tester,
        size: size,
        name: '41-celebration-$tag',
        location: '/skill/5/audit',
        api: api,
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), longAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'left panel, filled ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: 'left-filled-$tag',
        location: '/map',
        act: (t) async {
          if (size.width < 900) {
            await t.tap(find.byKey(const Key('open-left-drawer')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'left panel, empty ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: 'left-empty-$tag',
        location: '/map',
        seeded: false,
        act: (t) async {
          if (size.width < 900) {
            await t.tap(find.byKey(const Key('open-left-drawer')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'left panel, editing a card ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: 'left-editing-$tag',
        location: '/map',
        act: (t) async {
          if (size.width < 900) {
            await t.tap(find.byKey(const Key('open-left-drawer')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('field-vision')));
          await t.pump();
          await t.enterText(
            find.byKey(const Key('vision-input')),
            'Understand calculus well enough to teach it to a stranger, then ship the capstone.',
          );
          await t.pump();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 1 with the reflection card ($tag)', (tester) async {
      await scene(tester, size: size, name: '1-reflection-card-$tag', location: '/');
    });
    testWidgets(skip: dir == null, 'scene 1 reflection asked ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '1-reflection-asked-$tag',
        location: '/',
        act: (t) async {
          await t.tap(find.byKey(const Key('suggestion-0')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 1 reflection answered ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '1-reflection-answered-$tag',
        location: '/',
        act: (t) async {
          await t.tap(find.byKey(const Key('suggestion-0')));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('stage-input')), 'Writing the capstone report.');
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 2 map with bosses ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await passAudit(api, 1);
      await failAudit(api, 2);
      await scene(tester, size: size, name: '2-map-bosses-$tag', location: '/map', api: api);
    });
    testWidgets(skip: dir == null, 'scene 4 a boss node ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-boss-$tag', location: '/skill/2');
    });
    testWidgets(skip: dir == null, 'scene 4-1 boss cleared ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await passAudit(api, 1);
      await scene(
        tester,
        size: size,
        name: '41-boss-cleared-$tag',
        location: '/skill/2/audit',
        api: api,
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), longAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4-1 lesson card ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '41-lesson-$tag',
        location: '/skill/4/audit',
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), shortAnswer);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('audit-next')));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('stage-input')),
            'I thought differentiation and integration were the same thing',
          );
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'voice with a caption ($tag)', (tester) async {
      final voice = FakeVoiceService();
      await scene(
        tester,
        size: size,
        name: '5-voice-caption-$tag',
        location: '/',
        voice: voice,
        act: (t) async {
          await t.tap(find.byKey(const Key('voice-mode')));
          await t.pumpAndSettle();
          voice.level(0.8);
          voice.partial('Let me explain how to find the roots of Quadratic Equations');
          await t.pump();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 5 voice ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '5-voice-$tag',
        location: '/',
        act: (t) async {
          await t.tap(find.byKey(const Key('voice-mode')));
          await t.pumpAndSettle();
        },
      );
    });
  }
}
