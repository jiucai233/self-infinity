// Renders every scene to a PNG for a visual check. Not a regression test: it
// only runs when SHOTS_DIR is set and never compares anything.
//
//   SHOTS_DIR=/some/dir flutter test test/screenshots_test.dart
//   SHOTS_LANG=zh (or ko) renders them in that language: the UI, the world the
//   fake backend builds, and the lines typed into it (the `_Say` table).
import 'dart:convert';
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
import 'package:self_infinity/app/panel_layout.dart';
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

/// The same language as the fake backend knows it (`en`, `zh` or `ko`).
final String _code = switch (Platform.environment['SHOTS_LANG']) {
  'zh' => 'zh',
  'ko' => 'ko',
  _ => 'en',
};

/// What the screenshots' user types, in the language of the shot. The rules of
/// the fake hold in every language: an answer of 80 characters passes (one of
/// 160 or more is not challenged), one saying "not sure" / `모르` / `不确定` fails,
/// and a topic with math / `수학` / `数学` is the math course.
class _Say {
  const _Say({
    required this.math,
    required this.writing,
    required this.probability,
    required this.function,
    required this.short,
    required this.long,
    required this.ate,
    required this.today,
    required this.status,
    required this.learnMath,
    required this.hello,
    required this.identity,
    required this.vision,
    required this.visionLong,
    required this.antiVision,
    required this.rules,
    required this.goalTeach,
    required this.goalWrite,
    required this.gapDiscriminant,
    required this.gapGraphs,
    required this.memorized,
    required this.lesson,
    required this.failedOne,
    required this.failedTwo,
    required this.note,
    required this.capstone,
    required this.fearOnboarding,
    required this.canTeach,
    required this.dictated,
  });

  final String math, writing, probability, function;
  final String short, long;
  final String ate, today, status, learnMath, hello;
  final String identity, vision, visionLong, antiVision;
  final List<String> rules;
  final String goalTeach, goalWrite, gapDiscriminant, gapGraphs;
  final String memorized, lesson, failedOne, failedTwo, note, capstone;
  final String fearOnboarding, canTeach, dictated;

  static _Say of(String code) => switch (code) {
    'zh' => _zh,
    'ko' => _ko,
    _ => _en,
  };

  static const _en = _Say(
    math: 'math',
    writing: 'Writing',
    probability: 'probability',
    function: 'Function',
    short: shortAnswer,
    long: longAnswer,
    ate: 'I slept six hours and had ramen for lunch. I am a bit tired.',
    today: 'What should I do today?',
    status: 'Give me a status report',
    learnMath: 'I want to learn math',
    hello: 'Hello there',
    identity: 'I am the type of person who explains it before I memorize it.',
    vision: 'Understand calculus well enough to teach it to a stranger.',
    visionLong: 'Understand calculus well enough to teach it to a stranger, then ship the capstone.',
    antiVision: 'Another year of nodding along without really knowing.',
    rules: ['No phone before the first audit', 'Explain, never copy', 'Stop at 23:00'],
    goalTeach: 'Teach calculus to a stranger',
    goalWrite: 'Write every week',
    gapDiscriminant: 'what the discriminant tells you',
    gapGraphs: 'reading graphs',
    memorized: 'I just memorized the quadratic formula',
    lesson: 'I thought differentiation and integration were the same thing',
    failedOne: 'A linear function is a straight line. You draw it with a ruler.',
    failedTwo: 'It is y = ax + b, where a is the slope and b is where it starts.',
    note: 'b² − 4ac decides how many real roots there are.',
    capstone: 'Writing the capstone report.',
    fearOnboarding: 'Another year of nodding along.',
    canTeach: 'I can teach it.',
    dictated: 'Another year of nodding along in class',
  );

  static const _ko = _Say(
    math: '수학',
    writing: '글쓰기',
    probability: '확률',
    function: '함수',
    short: '잘 모르겠어요',
    long:
        '정의부터 말할게요. 이 개념은 주어진 조건에서 값을 찾는 방법이에요. 조건이 값을 딱 하나로 정해 주기 때문에 성립해요. '
        '예외도 있어요. 조건끼리 모순되면 해가 아예 없을 수 있고, 조건이 너무 느슨하면 해가 여러 개일 수 있어요. '
        '그래서 쓰기 전에 어느 범위에서 다루는지 항상 먼저 밝혀야 해요. 범위를 정하지 않으면 같은 식도 전혀 다른 답을 낼 수 있어요.',
    ate: '어젯밤에 여섯 시간 잤고 점심으로 라면을 먹었어요. 조금 피곤해요.',
    today: '오늘 뭐 하면 좋을까요?',
    status: '현황 알려 줘',
    learnMath: '수학을 배우고 싶어요',
    hello: '안녕하세요',
    identity: '저는 외우기 전에 먼저 설명해 보는 사람이에요.',
    vision: '미적분을 낯선 사람에게 가르칠 수 있을 만큼 제대로 이해하기.',
    visionLong: '미적분을 낯선 사람에게 가르칠 수 있을 만큼 이해하고, 졸업 프로젝트까지 마치기.',
    antiVision: '제대로 알지 못한 채 고개만 끄덕이며 보내는 또 한 해.',
    rules: ['첫 심사 전에는 휴대폰 안 보기', '복사하지 말고 설명하기', '23시에 멈추기'],
    goalTeach: '낯선 사람에게 미적분 가르치기',
    goalWrite: '매주 글 쓰기',
    gapDiscriminant: '판별식이 알려 주는 것',
    gapGraphs: '그래프 읽기',
    memorized: '근의 공식을 그냥 외우기만 했어요',
    lesson: '미분과 적분이 같은 거라고 생각했어요',
    failedOne: '일차함수는 직선이에요. 자를 대고 그리면 돼요.',
    failedTwo: 'y = ax + b이고, a는 기울기, b는 시작하는 값이에요.',
    note: 'b² − 4ac가 실근이 몇 개인지 결정해요.',
    capstone: '졸업 보고서 쓰기.',
    fearOnboarding: '고개만 끄덕이며 보내는 또 한 해.',
    canTeach: '저는 가르칠 수 있어요.',
    dictated: '수업 시간에 고개만 끄덕이는 또 한 해',
  );

  static const _zh = _Say(
    math: '数学',
    writing: '写作',
    probability: '概率',
    function: '函数',
    short: '我不确定',
    long:
        '先从定义说起：这个想法是在给定条件下求出一个值的方法。它之所以成立，是因为这些条件把这个值唯一地确定了下来。'
        '当然也有例外：如果条件之间互相矛盾，可能根本没有解；如果条件太宽松，又可能有很多个解。'
        '所以在使用它之前，一定要先说明自己是在哪个范围内讨论。如果不先确定这个范围，同一个式子也可能得出完全不同的答案，'
        '这一点必须在一开始就讲清楚，否则后面的推导都没有意义。',
    ate: '我睡了六个小时，午饭吃了拉面。有点累。',
    today: '今天做什么？',
    status: '汇报一下进度',
    learnMath: '我想学数学',
    hello: '你好',
    identity: '我是那种先讲明白、再去记忆的人。',
    vision: '把微积分学到能教给陌生人的程度。',
    visionLong: '把微积分学到能教给陌生人的程度，然后完成毕业项目。',
    antiVision: '又一年只是点头附和，却没有真正弄懂。',
    rules: ['第一次审核前不看手机', '只讲解，不抄写', '23 点停下'],
    goalTeach: '给陌生人讲微积分',
    goalWrite: '每周写作',
    gapDiscriminant: '判别式能告诉你什么',
    gapGraphs: '读图',
    memorized: '我只是背下了求根公式',
    lesson: '我以为微分和积分是同一回事',
    failedOne: '一次函数就是一条直线，用尺子画就行。',
    failedTwo: '它是 y = ax + b，a 是斜率，b 是起点。',
    note: 'b² − 4ac 决定了有几个实根。',
    capstone: '写毕业报告。',
    fearOnboarding: '又一年只是点头附和。',
    canTeach: '我能把它教给别人。',
    dictated: '又一年在课堂上只是点头',
  );
}

final _Say _say = _Say.of(_code);

/// [passAudit] / [failAudit] of the test app, with answers in the shot's language.
Future<void> _passAudit(FakeApiClient api, int skillId) async {
  final start = await api.startAudit(skillId);
  for (var i = 0; i < 12; i++) {
    if (await api.submitTurn(start.session.id, _say.long) is VerdictResult) return;
  }
  throw StateError('The audit on node $skillId did not end');
}

Future<({int sessionId, VerdictResult verdict})> _failAudit(FakeApiClient api, int skillId) async {
  final start = await api.startAudit(skillId);
  for (var i = 0; i < 12; i++) {
    final result = await api.submitTurn(start.session.id, _say.short);
    if (result is VerdictResult) return (sessionId: start.session.id, verdict: result);
  }
  throw StateError('The audit on node $skillId did not end');
}

Future<FakeApiClient> _seed() async {
  final api = FakeApiClient(latency: Duration.zero, language: _code);
  await api.generateCourse(GenerateRequest(topic: _say.math));
  // Math, in its learning order: pass Discriminant (6) and Roots and
  // Coefficients (7), fail Quadratic Equations (5), leave the rest.
  await _passAudit(api, 6);
  await _passAudit(api, 7);
  final failed = await _failAudit(api, 5);
  await api.submitReflection(failed.sessionId, _say.memorized);
  await api.createSearchPlan(5, gap: _say.gapDiscriminant);
  await api.createSearchPlan(5, gap: _say.gapGraphs);
  await api.sendChat(_say.ate);
  await api.updateProfile(
    identity: _say.identity,
    vision: _say.vision,
    antiVision: _say.antiVision,
    rules: _say.rules,
  );
  await api.sendChat(_say.today);
  await _passAudit(api, 5); // one of today's quests is done
  // A second course (a side quest) and a main quest the math course serves.
  await api.generateCourse(GenerateRequest(topic: _say.writing));
  final goal = await api.createGoal(_say.goalTeach);
  await api.updateGoal(goal.id, courseIds: [1]);
  await api.createGoal(_say.goalWrite);
  return api;
}

/// [_seed] with Linear Functions (9) tried and failed twice before: the
/// verdict counts the attempt, a pass shows the curve and the first answer.
Future<FakeApiClient> _seedTries() async {
  final api = await _seed();
  api
    ..debugAddFailedAttempt(9, score: 62, answer: _say.failedOne)
    ..debugAddFailedAttempt(9, score: 68, answer: _say.failedTwo);
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
    bool tour = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Avatar.animationsEnabled = false;
    debugDisableShadows = false; // flutter_test draws shadows hard-edged otherwise
    final fake = api ?? (seeded ? await _seed() : FakeApiClient(latency: Duration.zero, language: _code));
    // A fresh app each time, so a second scene in one test does not reuse the first one's state.
    await tester.pumpWidget(const SizedBox.shrink());
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
          tour: tour,
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

  const sizes = {'wide': Size(1440, 900), 'tablet': Size(1180, 820), 'narrow': Size(390, 844)};

  setUpAll(() async {
    if (dir != null) await _loadFonts();
    PanelLayout.leftStartsFolded = true; // as the app starts
  });
  tearDownAll(() => PanelLayout.leftStartsFolded = false);

  // Frames for the demo video (docs/video): one sentence grows a tree, then
  // its nodes are cleared one by one, with each node's place on screen.
  group('video', () {
    const size = Size(1440, 900);
    Future<void> positions(WidgetTester tester, String name, CourseMap map) async {
      if (dir == null) return;
      final state = tester.state<LifeConstellationState>(find.byType(LifeConstellation));
      final box = tester.renderObject<RenderBox>(find.byType(LifeConstellation));
      final out = <String, List<double>>{};
      for (final node in map.nodes) {
        final at = state.positionOf('s${node.id}');
        if (at == null) continue;
        final g = box.localToGlobal(at);
        out['${node.id}'] = [g.dx, g.dy];
      }
      File('$dir/$name.json').writeAsStringSync(jsonEncode(out));
    }

    testWidgets(skip: dir == null, 'video: one sentence', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      await scene(tester, size: size, name: 'v-map-empty', location: '/map', api: api);
      await scene(tester, size: size, name: 'v-chat-0', location: '/', api: api);
      await scene(
        tester,
        size: size,
        name: 'v-chat-1',
        location: '/',
        api: api,
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), _say.learnMath);
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets(skip: dir == null, 'video: the tree grows', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      final course = await api.generateCourse(GenerateRequest(topic: _say.math));
      final courseId = course.course.id;
      var map = await api.getCourseMap(courseId);
      final order = <int>[];
      for (var step = 0; ; step++) {
        final name = 'v-grow-${step.toString().padLeft(2, '0')}';
        await scene(tester, size: size, name: name, location: '/map', api: api,
            act: (t) => positions(t, name, map));
        final next = map.nodes.where((n) => n.status == SkillStatus.available).toList();
        if (next.isEmpty || step >= 12) break;
        order.add(next.first.id);
        await _passAudit(api, next.first.id);
        map = await api.getCourseMap(courseId);
      }
      if (dir != null) File('$dir/v-grow-order.json').writeAsStringSync(jsonEncode(order));

      // The audit on the first node, turn by turn, on a fresh copy of the course.
      final fresh = FakeApiClient(latency: Duration.zero, language: _code);
      await fresh.generateCourse(GenerateRequest(topic: _say.math));
      for (var turns = 0; turns < 4; turns++) {
        await scene(
          tester,
          size: size,
          name: 'v-audit-$turns',
          location: '/skill/${order.first}/audit',
          api: turns == 0 ? fresh : null,
          act: (t) async {
            for (var i = 0; i < turns; i++) {
              if (find.byKey(const Key('send')).evaluate().isEmpty) break;
              await t.enterText(find.byKey(const Key('stage-input')), _say.long);
              await t.pump();
              await t.tap(find.byKey(const Key('send')));
              await t.pumpAndSettle();
            }
          },
        );
      }
    });
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
        api: FakeApiClient(latency: Duration.zero, onboarded: false, language: _code),
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
        api: FakeApiClient(latency: Duration.zero, onboarded: false, language: _code),
        act: (t) async {
          await t.tap(find.byKey(const Key('onboarding-continue')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('dictation-button')));
          await t.pumpAndSettle();
          voice.partial(_say.dictated);
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
          _say.fearOnboarding,
          _say.canTeach,
          '',
          _say.goalTeach,
        ],
      );
    });
    testWidgets(skip: dir == null, 'tutorial course ready ($tag)', (tester) async {
      await onboarding(
        tester,
        '0-tutorial-ready',
        6,
        answers: [
          _say.fearOnboarding,
          _say.canTeach,
          '',
          _say.goalTeach,
          _say.math,
        ],
      );
    });
    // The guided tour before the setup: one shot per stop.
    for (var stop = 0; stop < 9; stop++) {
      testWidgets(skip: dir == null, 'guided tour stop $stop ($tag)', (tester) async {
        await scene(
          tester,
          size: size,
          name: '0-tour-${stop.toString().padLeft(2, '0')}-$tag',
          location: '/',
          tour: true,
          api: FakeApiClient(latency: Duration.zero, onboarded: false, language: _code),
          act: (t) async {
            for (var i = 0; i < stop; i++) {
              if (find.byKey(const Key('tour-next')).evaluate().isEmpty) break;
              await t.tap(find.byKey(const Key('tour-next')));
              // The page of the next stop loads, then its anchor is looked for.
              await t.pump(const Duration(milliseconds: 400));
              await t.pumpAndSettle();
              await t.pump(const Duration(milliseconds: 400));
              await t.pumpAndSettle();
            }
          },
        );
      });
    }
    testWidgets(skip: dir == null, 'scene 2 a node card ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '2-life-node-$tag',
        location: '/map',
        act: (t) => tapLifeNode(t, 's5'),
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
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      await api.generateCourse(GenerateRequest(topic: _say.probability));
      await scene(tester, size: size, name: '2-map-fresh-$tag', location: '/map', api: api);
    });
    testWidgets(skip: dir == null, 'scene 2 searching ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '2-map-search-$tag',
        location: '/map',
        act: (t) async {
          await t.enterText(find.byKey(const Key('stage-input')), _say.function);
          await t.pump();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4 node ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-node-$tag', location: '/skill/5');
    });
    testWidgets(skip: dir == null, 'scene 4 learn first ($tag)', (tester) async {
      final api = await _seed();
      await api.createNodeNote(5, _say.note);
      await scene(
        tester,
        size: size,
        name: '4-learn-$tag',
        location: '/skill/5',
        api: api,
        act: (t) async {
          final row = find.byKey(const Key('skill-learn'));
          if (row.evaluate().isEmpty) {
            await t.scrollUntilVisible(find.byKey(const Key('node-notes')), 200, scrollable: find.byType(Scrollable).first);
          } else {
            await t.tap(row);
          }
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4 locked ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-locked-$tag', location: '/skill/12');
    });
    testWidgets(skip: dir == null, 'replay of a fail ($tag)', (tester) async {
      final api = await _seed();
      final failed = await _failAudit(api, 5); // its lesson came back
      await scene(
        tester,
        size: size,
        name: 'replay-failed-$tag',
        location: '/audit/${failed.sessionId}',
        api: api,
      );
    });
    testWidgets(skip: dir == null, 'replay with its lesson card ($tag)', (tester) async {
      final api = await _seed();
      await _failAudit(api, 5);
      await scene(tester, size: size, name: 'replay-lesson-$tag', location: '/audit/3', api: api);
    });
    testWidgets(skip: dir == null, 'replay with material found ($tag)', (tester) async {
      final api = await _seed();
      await _failAudit(api, 5);
      await scene(
        tester,
        size: size,
        name: 'replay-materials-$tag',
        location: '/audit/3',
        api: api,
        act: (t) async {
          final button = find.byKey(const Key('replay-find-materials'));
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          await t.tap(button);
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('replay-materials')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 4-1 asking ($tag)', (tester) async {
      await scene(tester, size: size, name: '41-asking-$tag', location: '/skill/9/audit');
    });
    testWidgets(skip: dir == null, 'scene 4-1 failed ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '41-failed-$tag',
        location: '/skill/9/audit',
        api: await _seedTries(),
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), _say.short);
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
        location: '/skill/9/audit',
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), _say.short);
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
        location: '/skill/9/audit',
        api: await _seedTries(),
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), _say.long);
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
          await t.enterText(find.byKey(const Key('stage-input')), _say.learnMath);
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
          for (final line in [_say.status, _say.today, _say.learnMath]) {
            await t.enterText(find.byKey(const Key('stage-input')), line);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 5 thinking ($tag)', (tester) async {
      final api = FakeApiClient(latency: const Duration(seconds: 2), language: _code);
      await scene(
        tester,
        size: size,
        name: '5-thinking-done-$tag',
        location: '/',
        api: api,
        act: (t) async {
          await t.pump(const Duration(seconds: 3)); // the first loads
          await t.enterText(find.byKey(const Key('stage-input')), _say.status);
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
          await t.enterText(find.byKey(const Key('stage-input')), _say.hello);
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
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      await api.generateCourse(GenerateRequest(topic: _say.math));
      for (final id in [6, 7, 5, 9]) {
        await _passAudit(api, id);
      }
      await scene(
        tester,
        size: size,
        name: '41-celebration-$tag',
        location: '/skill/10/audit',
        api: api,
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), _say.long);
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
            _say.visionLong,
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
          await t.enterText(find.byKey(const Key('stage-input')), _say.capstone);
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        },
      );
    });
    testWidgets(skip: dir == null, 'scene 2 map with bosses ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      await api.generateCourse(GenerateRequest(topic: _say.math));
      await _passAudit(api, 6);
      await _passAudit(api, 7);
      await _failAudit(api, 5); // a boss, failed
      await scene(tester, size: size, name: '2-map-bosses-$tag', location: '/map', api: api);
    });
    testWidgets(skip: dir == null, 'developer panel ($tag)', (tester) async {
      final api = await _seed();
      final audits = (await api.getDevAudits()).audits;
      await api.reviewAudit(audits[0].id, AuditReview.right);
      await api.reviewAudit(audits[1].id, AuditReview.tooStrict, leaked: true);
      await scene(
        tester,
        size: size,
        name: '9-dev-$tag',
        location: '/map',
        api: api,
        act: (t) async {
          if (find.byKey(const Key('open-left-drawer')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('open-left-drawer')));
            await t.pumpAndSettle();
          }
          if (find.byKey(const Key('expand-left')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('expand-left')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('settings-button')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('settings-dev')));
          await t.pumpAndSettle();
          final transcript = find.byKey(Key('dev-transcript-${audits[1].id}'));
          if (transcript.evaluate().isNotEmpty) {
            await t.tap(transcript); // below the fold on a phone
            await t.pumpAndSettle();
          }
        },
      );
    });
    testWidgets(skip: dir == null, 'settings menu ($tag)', (tester) async {
      await scene(
        tester,
        size: size,
        name: '9-settings-$tag',
        location: '/map',
        act: (t) async {
          if (find.byKey(const Key('open-left-drawer')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('open-left-drawer')));
            await t.pumpAndSettle();
          }
          if (find.byKey(const Key('expand-left')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('expand-left')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('settings-button')));
          await t.pumpAndSettle();
        },
      );
    });
    for (final tab in const ['voice', 'llm', 'learner']) {
      testWidgets(skip: dir == null, 'developer panel, $tab ($tag)', (tester) async {
        final api = _ShotCosts();
        await api.generateCourse(GenerateRequest(topic: _say.math));
        await scene(
          tester,
          size: size,
          name: '9-dev-$tab-$tag',
          location: '/map',
          api: api,
          act: (t) async {
            if (find.byKey(const Key('open-left-drawer')).evaluate().isNotEmpty) {
              await t.tap(find.byKey(const Key('open-left-drawer')));
              await t.pumpAndSettle();
            }
            if (find.byKey(const Key('expand-left')).evaluate().isNotEmpty) {
            await t.tap(find.byKey(const Key('expand-left')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('settings-button')));
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('settings-dev')));
            await t.pumpAndSettle();
            await t.ensureVisible(find.byKey(Key('dev-tab-$tab'))); // the last tab is off a phone's edge
            await t.pumpAndSettle();
            await t.tap(find.byKey(Key('dev-tab-$tab')));
            await t.pumpAndSettle();
          },
        );
      });
    }
    testWidgets(skip: dir == null, 'scene 4 a boss node ($tag)', (tester) async {
      await scene(tester, size: size, name: '4-boss-$tag', location: '/skill/2');
    });
    testWidgets(skip: dir == null, 'scene 4-1 boss cleared ($tag)', (tester) async {
      final api = FakeApiClient(latency: Duration.zero, language: _code);
      await api.generateCourse(GenerateRequest(topic: _say.math));
      await _passAudit(api, 6);
      await _passAudit(api, 7);
      await scene(
        tester,
        size: size,
        name: '41-boss-cleared-$tag',
        location: '/skill/5/audit',
        api: api,
        act: (t) async {
          for (var i = 0; i < 3; i++) {
            if (find.byKey(const Key('send')).evaluate().isEmpty) break;
            await t.enterText(find.byKey(const Key('stage-input')), _say.long);
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
        location: '/skill/9/audit',
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.enterText(find.byKey(const Key('stage-input')), _say.short);
            await t.pump();
            await t.tap(find.byKey(const Key('send')));
            await t.pumpAndSettle();
          }
          await t.tap(find.byKey(const Key('audit-next')));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('stage-input')),
            _say.lesson,
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

/// Model calls and voice sessions with costs, for the developer panel's shots.
class _ShotCosts extends FakeApiClient {
  _ShotCosts() : super(latency: Duration.zero, language: _code);

  @override
  Future<LearnerModel> getLearner() async => LearnerModel(
    ability: 0.34,
    targetChance: 0.75,
    judgeFalsePass: 0.05,
    judgeFalseFail: 0.30,
    nodes: const [
      LearnerNode(skillId: 6, title: 'Discriminant', chance: 0.71),
      LearnerNode(skillId: 7, title: 'Roots and Coefficients', chance: 0.58),
    ],
    history: [
      for (final (i, (passed, ability, progress, agreement)) in const [
        (false, -0.12, 0.1, 1.0),
        (false, -0.2, 0.15, 0.667),
        (true, 0.05, 0.6, 1.0),
        (true, 0.26, 0.55, 1.0),
        (false, 0.18, 0.3, 0.667),
        (true, 0.34, 0.5, null),
      ].indexed)
        LearnerStep(
          auditId: i + 1,
          skillId: i.isEven ? 6 : 7,
          skillTitle: i.isEven ? 'Discriminant' : 'Roots and Coefficients',
          passed: passed,
          ability: ability,
          progress: progress,
          agreement: agreement,
          createdAt: DateTime.utc(2026, 10, 8 + i, 3),
        ),
    ],
  );

  @override
  Future<DevLlm> getDevLlm() async => const DevLlm(
    calls: 96,
    failed: 2,
    cost: 0.0431,
    avgCost: 0.00046,
    providers: [
      DevLlmRow(
        provider: 'openai',
        model: 'gpt-6-luna',
        calls: 58,
        failed: 2,
        avgInputTokens: 2140,
        avgOutputTokens: 420,
        avgMs: 3100,
        cost: 0.0246,
        avgCost: 0.00044,
      ),
      DevLlmRow(
        provider: 'claude',
        model: 'claude-haiku-5-5',
        calls: 38,
        avgInputTokens: 2210,
        avgOutputTokens: 510,
        avgMs: 2300,
        cost: 0.0185,
        avgCost: 0.00049,
      ),
    ],
    agents: [
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', agent: 'auditor', calls: 31, avgInputTokens: 2600, avgOutputTokens: 380, avgMs: 2900, avgCost: 0.00045),
      DevLlmRow(provider: 'claude', model: 'claude-haiku-5-5', agent: 'auditor', calls: 22, avgInputTokens: 2650, avgOutputTokens: 460, avgMs: 2100, avgCost: 0.0005),
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', agent: 'planner', calls: 4, avgInputTokens: 3900, avgOutputTokens: 2800, avgMs: 21000, avgCost: 0.0018),
    ],
    audits: [
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', audits: 6, avgCalls: 5.2, avgCost: 0.0023),
      DevLlmRow(provider: 'claude', model: 'claude-haiku-5-5', audits: 4, avgCalls: 5.5, avgCost: 0.0027),
    ],
    allOn: [
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', cost: 0.0409),
      DevLlmRow(provider: 'claude', model: 'claude-haiku-5-5', cost: 0.0472),
    ],
  );

  @override
  Future<DevVoice> getDevVoice({int limit = 50}) async => DevVoice(
    guideSessions: 3,
    guideMinutes: 6.9,
    guideCost: 0.446,
    guideCostPerMinute: 0.065,
    guideAllLive: 0.347,
    guideAllRealtime: 0.562,
    realtimePerMinute: 0.082,
    realtimeRateMeasured: true,
    guideCachedShare: 0.75,
    guideLiveVoiceCost: 0.188,
    guideLiveBackendCost: 0.0036,
    guideCostPerSession: 0.149,
    auditSessions: 15,
    auditMinutes: 59.4,
    auditCost: 1.296,
    auditLiveSessions: 2,
    auditLiveMinutes: 8.4,
    auditLiveVoiceCost: 0.42,
    auditLiveBackendCost: 0.0051,
    auditLiveCostPerSession: 0.213,
    auditTurnsCostPerSession: 0.067,
    auditAllLive: 3.18,
    auditAllTurns: 1.02,
    turnsPerMinute: 0.017,
    turnsRateMeasured: true,
    sessions: [
      DevVoiceSession(id: 18, kind: 'audit', model: 'gpt-live-1', startedAt: DateTime.utc(2026, 10, 12, 4), minutes: 4.6, turns: 6, audioIn: 0, audioOut: 0, cost: 0.233, backendCost: 0.0028, otherCost: 0.078),
      DevVoiceSession(id: 17, kind: 'audit', model: 'gpt-live-1', startedAt: DateTime.utc(2026, 10, 12, 3), minutes: 3.8, turns: 5, audioIn: 0, audioOut: 0, cost: 0.192, backendCost: 0.0023, otherCost: 0.065),
      DevVoiceSession(id: 16, kind: 'transcribe', model: 'gpt-live-transcribe', startedAt: DateTime.utc(2026, 10, 11, 21), minutes: 1.6, turns: 5, audioIn: 0, audioOut: 0, cost: 0.027, otherCost: 0.082),
      DevVoiceSession(id: 7, kind: 'guide', model: 'gpt-live-1', startedAt: DateTime.utc(2026, 10, 9, 15), minutes: 1.1, turns: 2, audioIn: 0, audioOut: 0, cost: 0.053, backendCost: 0.0009, otherCost: 0.086),
    ],
  );
}
