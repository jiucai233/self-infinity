// Avatar (大肥鱼, drawn from her sheets) and its head, SpeechBubble, ThinkingShimmer, StatBar,
// VoiceWave and LifeConstellation.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/life_tree.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

const _boundary = Key('boundary');
final ThemeData _theme = AppTheme.light(); // one instance: a new theme would animate

Future<void> pumpWidgetUnderTest(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(key: _boundary, child: child),
        ),
      ),
    ),
  );
}

/// The pixels of the widget under test.
Future<Uint8List> pixels(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}

Future<Uint8List> pixelsOf(
  WidgetTester tester, {
  String agent = 'front_desk',
  AvatarMood mood = AvatarMood.neutral,
  AvatarState state = AvatarState.idle,
  bool wave = false,
}) async {
  await pumpWidgetUnderTest(
    tester,
    Avatar(agent: agent, mood: mood, state: state, wave: wave, size: 140, animate: false),
  );
  return pixels(tester);
}

bool same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How many pixels are not fully transparent.
int inked(Uint8List rgba) {
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) n++;
  }
  return n;
}

void main() {
  const agents = [
    'front_desk',
    'narrator',
    'recommender',
    'planner',
    'clarifier',
    'syllabus_finder',
    'material_finder',
    'auditor',
    'challenger',
    'recorder',
    'linker',
    'checkin_converter',
  ];

  setUp(() => Avatar.animationsEnabled = false);

  group('Avatar', () {
    testWidgets('draws every agent in every mood and state', (tester) async {
      for (final agent in [...agents, 'unknown_agent', '']) {
        for (final mood in AvatarMood.values) {
          for (final state in AvatarState.values) {
            await pumpWidgetUnderTest(
              tester,
              Avatar(agent: agent, mood: mood, state: state, wave: true, size: 100, animate: false),
            );
            expect(tester.takeException(), isNull, reason: '$agent $mood $state');
          }
        }
      }
    });

    testWidgets('is 5/7 as wide as it is high and carries a semantic label', (tester) async {
      await pumpWidgetUnderTest(tester, const Avatar(agent: 'auditor', size: 140));
      expect(tester.getSize(find.byType(Avatar)), const Size(100, 140));
      expect(find.bySemanticsLabel('auditor avatar'), findsOneWidget);
    });

    testWidgets('she is drawn from the sheets: she fills the box, in blue', (tester) async {
      final image = await pixelsOf(tester, mood: AvatarMood.smile);
      final share = inked(image) / (image.length / 4);
      expect(share, greaterThan(0.3));
      var blue = 0;
      for (var i = 0; i < image.length; i += 4) {
        if (image[i + 3] > 200 && image[i + 2] > image[i] + 60) blue++;
      }
      expect(blue / (image.length / 4), greaterThan(0.1), reason: 'her hair');
    });

    testWidgets('every agent is the same character', (tester) async {
      final front = await pixelsOf(tester, agent: 'front_desk');
      for (final agent in ['auditor', 'narrator', 'someone_else']) {
        expect(same(front, await pixelsOf(tester, agent: agent)), isTrue, reason: agent);
      }
    });

    testWidgets('each mood has its own face', (tester) async {
      final faces = <AvatarMood, Uint8List>{
        for (final mood in AvatarMood.values) mood: await pixelsOf(tester, mood: mood),
      };
      for (final a in AvatarMood.values) {
        for (final b in AvatarMood.values) {
          if (a.index >= b.index) continue;
          expect(same(faces[a]!, faces[b]!), isFalse, reason: '$a vs $b');
        }
      }
    });

    testWidgets('waving, listening, thinking and speaking each change the picture', (
      tester,
    ) async {
      final idle = await pixelsOf(tester);
      final others = [
        await pixelsOf(tester, wave: true),
        for (final state in [AvatarState.listening, AvatarState.thinking, AvatarState.speaking])
          await pixelsOf(tester, state: state),
      ];
      for (var i = 0; i < others.length; i++) {
        expect(same(idle, others[i]), isFalse, reason: 'picture $i');
        for (var j = i + 1; j < others.length; j++) {
          expect(same(others[i], others[j]), isFalse, reason: '$i vs $j');
        }
      }
    });

    testWidgets('holding her own ball is its own picture', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', holdOrb: true, size: 140, animate: false),
      );
      final held = await pixels(tester);
      expect(same(held, await pixelsOf(tester, mood: AvatarMood.smile)), isFalse);
    });

    test('a crystal ball floats beside her at chest height, right of her box', () {
      final at = Avatar.orbHandAt('front_desk', 140);
      expect(at.dx, greaterThan(100 + 20), reason: 'clear of her hair');
      expect(at.dy, inInclusiveRange(45, 80));
      expect(Avatar.unit('front_desk', 140), 1);
      expect(Avatar.orbHandAt('front_desk', 280), at * 2);
    });

    testWidgets('a reaction overrides the picture and stops the movement', (tester) async {
      final idle = await pixelsOf(tester);
      final faces = <Uint8List>[];
      for (final reaction in AvatarReaction.values) {
        await pumpWidgetUnderTest(
          tester,
          Avatar(agent: 'front_desk', reaction: reaction, size: 140, animate: true),
        );
        expect(tester.hasRunningAnimations, isFalse, reason: '$reaction');
        faces.add(await pixels(tester));
        expect(same(idle, faces.last), isFalse, reason: '$reaction');
      }
      expect(same(faces[0], faces[1]), isFalse);
      // Without the reaction she moves again.
      await pumpWidgetUnderTest(tester, const Avatar(agent: 'front_desk', size: 140, animate: true));
      expect(tester.hasRunningAnimations, isTrue);
      await pumpWidgetUnderTest(tester, const SizedBox());
    });

    testWidgets('idle she blinks: the eyes close once a loop', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', size: 140, animate: true),
      );
      final open = await pixels(tester);
      final loop = Avatar.idleLoop;
      // The blink is the last frame of the loop.
      await tester.pump(loop - const Duration(milliseconds: 60));
      final closed = await pixels(tester);
      expect(same(open, closed), isFalse);
      await tester.pump(const Duration(milliseconds: 120));
      expect(same(open, await pixels(tester)), isTrue);
      await pumpWidgetUnderTest(tester, const SizedBox());
    });

    testWidgets('the same input always gives the same picture', (tester) async {
      final a = await pixelsOf(tester, agent: 'narrator', mood: AvatarMood.happy);
      final b = await pixelsOf(tester, agent: 'narrator', mood: AvatarMood.happy);
      expect(same(a, b), isTrue);
    });

    testWidgets('waving stops by itself, so the screen can settle', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', wave: true, animate: true),
      );
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the hand really moves while waving', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', wave: true, size: 140, animate: true),
      );
      final frames = <Uint8List>[];
      for (var i = 0; i < 4; i++) {
        frames.add(await pixels(tester));
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(frames.any((f) => !same(f, frames.first)), isTrue);
    });

    testWidgets('speaking and listening move until the state ends', (tester) async {
      for (final state in [AvatarState.speaking, AvatarState.listening]) {
        await pumpWidgetUnderTest(tester, Avatar(agent: 'front_desk', state: state, animate: true));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.hasRunningAnimations, isTrue, reason: '$state');
      }
      // Idle she blinks; with the movement off she is still.
      await pumpWidgetUnderTest(tester, const Avatar(agent: 'front_desk', animate: true));
      expect(tester.hasRunningAnimations, isTrue);
      await pumpWidgetUnderTest(tester, const Avatar(agent: 'front_desk', animate: false));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the mouth really moves while speaking', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', state: AvatarState.speaking, size: 140, animate: true),
      );
      final frames = <Uint8List>[];
      for (var i = 0; i < 4; i++) {
        frames.add(await pixels(tester));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(frames.any((f) => !same(f, frames.first)), isTrue);
    });

    testWidgets('animate: false never moves; the global switch is honoured', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', state: AvatarState.speaking, wave: true, animate: false),
      );
      expect(tester.hasRunningAnimations, isFalse);

      Avatar.animationsEnabled = false;
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', state: AvatarState.speaking),
      );
      expect(tester.hasRunningAnimations, isFalse);
      Avatar.animationsEnabled = true;
      await pumpWidgetUnderTest(
        tester,
        const Avatar(agent: 'front_desk', state: AvatarState.speaking),
      );
      expect(tester.hasRunningAnimations, isTrue);
      Avatar.animationsEnabled = false; // tests keep it off
    });

    test('the default mood of each agent', () {
      expect(defaultMoodOf('front_desk'), AvatarMood.smile);
      expect(defaultMoodOf('recommender'), AvatarMood.smile);
      expect(defaultMoodOf('checkin_converter'), AvatarMood.smile);
      expect(defaultMoodOf('narrator'), AvatarMood.neutral);
      expect(defaultMoodOf('recorder'), AvatarMood.neutral);
      expect(defaultMoodOf('auditor'), AvatarMood.stern);
      expect(defaultMoodOf('challenger'), AvatarMood.stern);
    });
  });

  group('SpeechBubble', () {
    testWidgets('is a soft grey bubble: surfaceHigh fill, radius 20, no border', (tester) async {
      await pumpWidgetUnderTest(tester, const SpeechBubble(child: Text('Hello')));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(SpeechBubble), matching: find.byType(DecoratedBox)).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, AppColors.surfaceHigh);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isNull);
    });

    testWidgets('every tail variant draws; the child is shown', (tester) async {
      for (final tail in BubbleTail.values) {
        await pumpWidgetUnderTest(tester, SpeechBubble(tail: tail, child: const Text('bubble')));
        expect(find.text('bubble'), findsOneWidget, reason: '$tail');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('is tappable and can be round', (tester) async {
      var taps = 0;
      await pumpWidgetUnderTest(
        tester,
        SpeechBubble(circle: true, onTap: () => taps++, child: const Text('tap me')),
      );
      await tester.tap(find.text('tap me'));
      expect(taps, 1);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(SpeechBubble),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('is limited to its maximum width', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        SpeechBubble(maxWidth: 200, child: Text('a' * 200)),
      );
      expect(tester.getSize(find.byType(SpeechBubble)).width, lessThanOrEqualTo(200));
    });

    testWidgets('the speaker\'s display name sits above the bubble', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SpeechBubble(speaker: 'auditor', child: Text('Explain it')),
      );
      expect(find.byKey(const Key('speaker-name')), findsOneWidget);
      expect(find.text('Auditor'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const Key('speaker-name'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Explain it')).dy),
      );
      await pumpWidgetUnderTest(tester, const SpeechBubble(child: Text('No name')));
      expect(find.byKey(const Key('speaker-name')), findsNothing);
    });

    testWidgets('ThinkingShimmer: three skeleton lines, still when animation is off', (
      tester,
    ) async {
      await pumpWidgetUnderTest(tester, const ThinkingShimmer(animate: false));
      expect(find.byKey(const Key('thinking-shimmer')), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ShaderMask), matching: find.byType(FractionallySizedBox)),
        findsNWidgets(3),
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.state<ThinkingShimmerState>(find.byType(ThinkingShimmer)).flowing, isFalse);
    });

    testWidgets('ThinkingShimmer flows with a Gemini gradient when animation is on', (
      tester,
    ) async {
      await pumpWidgetUnderTest(tester, const ThinkingShimmer(animate: true));
      expect(tester.hasRunningAnimations, isTrue);
      expect(tester.state<ThinkingShimmerState>(find.byType(ThinkingShimmer)).flowing, isTrue);
      final before = await pixels(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(same(await pixels(tester), before), isFalse, reason: 'the gradient moved');
      await pumpWidgetUnderTest(tester, const SizedBox());
    });

    testWidgets('ThinkingShimmer follows Avatar.animationsEnabled by default', (tester) async {
      Avatar.animationsEnabled = false;
      await pumpWidgetUnderTest(tester, const ThinkingShimmer());
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('AvatarHead', () {
    testWidgets('a round 28 px badge with the agent\'s head', (tester) async {
      await pumpWidgetUnderTest(tester, const AvatarHead(agent: 'auditor'));
      expect(tester.getSize(find.byType(AvatarHead)), const Size(28, 28));
      final badge = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AvatarHead), matching: find.byType(DecoratedBox)).first,
      );
      expect((badge.decoration as BoxDecoration).shape, BoxShape.circle);
      expect(
        find.descendant(of: find.byType(AvatarHead), matching: find.byType(ClipOval)),
        findsOneWidget,
      );
      expect(inked(await pixels(tester)), greaterThan(0));
    });

    testWidgets('the head follows the mood, not the agent', (tester) async {
      Future<Uint8List> head(String agent, [AvatarMood? mood]) async {
        await pumpWidgetUnderTest(tester, AvatarHead(agent: agent, size: 56, mood: mood));
        return pixels(tester);
      }

      final smiling = await head('front_desk');
      expect(same(smiling, await head('recommender')), isTrue);
      expect(same(smiling, await head('auditor')), isFalse, reason: 'the auditor is stern');
      expect(same(await head('auditor'), await head('nobody', AvatarMood.stern)), isTrue);
      await pumpWidgetUnderTest(tester, const AvatarHead(agent: 'nobody'));
      expect(tester.takeException(), isNull);
    });
  });

  group('StatBar', () {
    testWidgets('a label with its numbers and an 8 px bar (radius 4) filled to the value', (
      tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SizedBox(width: 200, child: StatBar(label: 'Cleared 3/12', value: 0.25)),
      );
      expect(find.text('Cleared 3/12'), findsOneWidget);
      final fill = tester.getSize(find.byKey(const Key('stat-bar-fill')));
      expect(fill.width, 50);
      expect(fill.height, 8);
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.circular(4),
      );
      final color = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const Key('stat-bar-fill')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(color.color, AppColors.primary);
    });

    testWidgets('clamps the value and takes a color', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SizedBox(
          width: 100,
          child: Column(
            children: [
              StatBar(label: 'a', value: 2),
              StatBar(label: 'b', value: -1, color: AppColors.danger),
            ],
          ),
        ),
      );
      final fills = tester.widgetList<FractionallySizedBox>(find.byKey(const Key('stat-bar-fill')));
      expect(fills.map((f) => f.widthFactor), [1, 0]);
    });
  });

  group('VoiceWave', () {
    testWidgets('draws bars from the level; flat when inactive', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SizedBox(width: 300, child: VoiceWave(level: 1, animate: false)),
      );
      final loud = await pixels(tester);
      await pumpWidgetUnderTest(
        tester,
        const SizedBox(width: 300, child: VoiceWave(level: 1, active: false, animate: false)),
      );
      final flat = await pixels(tester);
      expect(inked(loud), greaterThan(inked(flat)));
      expect(inked(flat), greaterThan(0));
    });

    testWidgets('louder is taller', (tester) async {
      Future<int> inkAt(double level) async {
        await pumpWidgetUnderTest(
          tester,
          SizedBox(width: 300, child: VoiceWave(level: level, animate: false)),
        );
        return inked(await pixels(tester));
      }

      final quiet = await inkAt(0.1);
      final medium = await inkAt(0.5);
      final loud = await inkAt(1);
      expect(quiet, lessThan(medium));
      expect(medium, lessThan(loud));
    });

    testWidgets(
      'the bars are filled with the Gemini gradient: blue at the left, red at the right',
      (
        tester,
      ) async {
        await pumpWidgetUnderTest(
          tester,
          const SizedBox(width: 300, child: VoiceWave(level: 1, animate: false)),
        );
        final rgba = await pixels(tester);
        const width = 300;
        double meanRed(int fromX, int toX) {
          var sum = 0, n = 0;
          for (var i = 0; i < rgba.length; i += 4) {
            final x = (i ~/ 4) % width;
            if (rgba[i + 3] > 200 && x >= fromX && x < toX) {
              sum += rgba[i];
              n++;
            }
          }
          return sum / n;
        }

        expect(meanRed(0, 60), lessThan(meanRed(240, 300) - 40));
      },
    );

    testWidgets('moves only when animation is on', (tester) async {
      await pumpWidgetUnderTest(tester, const VoiceWave(level: 1, animate: false));
      expect(tester.hasRunningAnimations, isFalse);
      await pumpWidgetUnderTest(tester, const VoiceWave(level: 1, animate: true));
      expect(tester.hasRunningAnimations, isTrue);
      await pumpWidgetUnderTest(tester, const SizedBox());
    });
  });

  group('LifeConstellation', () {
    CourseMap mapOf(List<SkillStatus> statuses) => CourseMap(
      course: Course(id: 1, topic: 't', createdAt: DateTime.utc(2026)),
      nodes: [
        for (var i = 0; i < statuses.length; i++)
          SkillNode(
            id: i + 1,
            courseId: 1,
            slug: 's$i',
            title: 'n$i',
            description: '',
            status: statuses[i],
            nodeType: NodeType.concept,
          ),
      ],
      edges: [
        for (var i = 1; i < statuses.length; i++)
          SkillEdge(fromId: 1, toId: i + 1, kind: SkillEdgeKind.contains, isPrimary: true),
      ],
    );

    Widget ball(List<SkillStatus> s) => SizedBox.square(
      dimension: 100,
      child: LifeConstellation(tree: LifeTree.build(maps: [mapOf(s)]), compact: true),
    );

    testWidgets('draws your tree; the picture follows the node states', (tester) async {
      Future<Uint8List> shot(List<SkillStatus> s) async {
        await pumpWidgetUnderTest(tester, ball(s));
        return pixels(tester);
      }

      final locked = await shot([SkillStatus.available, SkillStatus.locked, SkillStatus.locked]);
      final cleared = await shot([SkillStatus.mastered, SkillStatus.available, SkillStatus.locked]);
      expect(inked(locked), greaterThan(0));
      expect(same(locked, cleared), isFalse);
    });

    testWidgets('survives a single node and no course at all', (tester) async {
      await pumpWidgetUnderTest(tester, ball([SkillStatus.available]));
      expect(tester.takeException(), isNull);
      await pumpWidgetUnderTest(tester, ball(const []));
      expect(tester.takeException(), isNull);
    });
  });
}
