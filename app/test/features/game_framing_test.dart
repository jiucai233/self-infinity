// The game framing of the course (docs/ux-chat.md §6.2): the root and the
// branch nodes are bosses — a double ring on the map, a Boss chip in scene 4,
// “Boss cleared!” on the celebration card — and scene 2 is the main quest.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/graph_utils.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/map/graph_view.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

Finder ringOf(int id) => find.descendant(of: key('dot-$id'), matching: key('boss-ring'));

void main() {
  late FakeApiClient api;
  late CourseMap map;

  setUp(() async {
    api = FakeApiClient(latency: Duration.zero);
    map = await api.generateCourse(const GenerateRequest(topic: 'math'));
  });

  group('scene 2', () {
    testWidgets('the title is “Life tree”, with or without a course', (tester) async {
      await pumpOutline(tester, api: api);
      expect(tester.widget<Text>(key('stage-title')).data, 'Life tree');
      await pumpOutline(tester, api: FakeApiClient(latency: Duration.zero));
      expect(tester.widget<Text>(key('stage-title')).data, 'Life tree');
    });

    testWidgets('root and branches have a double ring, leaves a single one', (tester) async {
      await pumpOutline(tester, api: api);
      final bosses = bossIds(map.nodes, map.edges);
      expect(bosses, isNot(isEmpty));
      expect(bosses.length, lessThan(map.nodes.length));
      for (final n in map.nodes) {
        final dot = tester.widget<DotMark>(key('dot-${n.id}'));
        expect(dot.boss, bosses.contains(n.id), reason: n.title);
        expect(
          ringOf(n.id),
          bosses.contains(n.id) ? findsOneWidget : findsNothing,
          reason: n.title,
        );
      }
      // The root and the five branches of the math course; the six leaves are not.
      expect(bosses, {1, 2, 3, 4, 5, 8});
      for (final leaf in [6, 7, 9, 10, 11, 12]) {
        expect(bosses, isNot(contains(leaf)));
      }
    });

    testWidgets('a boss dot has the same footprint as any other dot', (tester) async {
      await pumpOutline(tester, api: api);
      expect(tester.getSize(key('dot-1')), tester.getSize(key('dot-6')));
      // The outer ring is larger and centred on the dot.
      final ring = tester.getRect(ringOf(1));
      expect(ring.width, greaterThan(tester.getSize(key('dot-1')).width));
      expect(ring.center.dx, closeTo(tester.getCenter(key('dot-1')).dx, 0.01));
      expect(ring.center.dy, closeTo(tester.getCenter(key('dot-1')).dy, 0.01));
    });

    testWidgets('the ring keeps the state color of the dot', (tester) async {
      await passAudit(api, 1); // root cleared: green
      await failAudit(api, 2); // Algebra failed: red
      await pumpOutline(tester, api: api);
      Color ringColor(int id) =>
          ((tester.widget<Container>(ringOf(id)).decoration! as BoxDecoration).border! as Border)
              .top
              .color;
      expect(ringColor(1), AppColors.success);
      expect(ringColor(2), AppColors.danger);
      expect(ringColor(3), AppColors.primary); // Functions: ready, blue
      expect(ringColor(5), AppColors.locked); // Quadratic Equations: a boss, still locked
    });

    testWidgets('the legend ends with a double-ringed Boss entry', (tester) async {
      await pumpOutline(tester, api: api);
      final legend = key('graph-legend');
      expect(textsIn(tester, legend).last, 'Boss');
      final dot = tester.widget<DotMark>(key('legend-dot-boss'));
      expect(dot.boss, isTrue);
      expect(
        find.descendant(of: key('legend-dot-boss'), matching: key('boss-ring')),
        findsOneWidget,
      );
      // The other four stay single.
      expect(tester.widget<DotMark>(key('legend-dot-locked')).boss, isFalse);
    });

    testWidgets('a boss node is still tappable and opens scene 4', (tester) async {
      await pumpOutline(tester, api: api);
      await tester.tap(key('node-1'));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/1'), findsOneWidget);
    });
  });

  group('scene 4: the Boss chip', () {
    Future<void> pumpNode(WidgetTester tester, int id) =>
        pumpScene(tester, SkillScene(skillId: id), api: api);

    testWidgets('the root has one, in the title row before its status', (tester) async {
      await pumpNode(tester, 1);
      expect(key('boss-chip'), findsOneWidget);
      expect(find.descendant(of: key('boss-chip'), matching: find.text('Boss')), findsOneWidget);
      final title = tester.getRect(key('stage-title'));
      final chip = tester.getRect(key('boss-chip'));
      final status = tester.getRect(find.widgetWithText(StatusChip, 'Ready'));
      expect((chip.center.dy - title.center.dy).abs(), lessThan(8));
      expect(chip.left, greaterThanOrEqualTo(title.right));
      expect(status.left, greaterThan(chip.right));
    });

    testWidgets('a branch has one', (tester) async {
      await passAudit(api, 1);
      await pumpNode(tester, 2); // Algebra
      expect(key('boss-chip'), findsOneWidget);
    });

    testWidgets('a locked boss has one too, next to Locked', (tester) async {
      await pumpNode(tester, 5); // Quadratic Equations: a branch, locked
      expect(key('boss-chip'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'Locked'), findsOneWidget);
    });

    testWidgets('a leaf has none', (tester) async {
      for (final id in [1, 2, 5]) {
        await passAudit(api, id);
      }
      await pumpNode(tester, 6); // Discriminant
      expect(find.widgetWithText(StatusChip, 'Ready'), findsOneWidget);
      expect(key('boss-chip'), findsNothing);
    });

    testWidgets('if the course map cannot be read the scene works without the chip', (
      tester,
    ) async {
      api.failNext(method: 'getCourseMap');
      await pumpNode(tester, 1);
      expect(find.widgetWithText(StatusChip, 'Ready'), findsOneWidget);
      expect(key('boss-chip'), findsNothing);
    });

    testWidgets('on a phone the title row still fits', (tester) async {
      await pumpScene(tester, SkillScene(skillId: 1), api: api, size: phoneScreen);
      expect(key('boss-chip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the celebration card', () {
    Future<void> pass(WidgetTester tester, int id) async {
      await pumpScene(tester, AuditScene(skillId: id), api: api);
      await say(tester, longAnswer);
      await say(tester, longAnswer);
    }

    testWidgets('a boss (the root) says Boss cleared!', (tester) async {
      await pass(tester, 1);
      expect(key('celebration-card'), findsOneWidget);
      expect(tester.widget<GradientText>(key('celebration-title')).text, 'Boss cleared!');
      expect(find.text('Boss cleared!'), findsOneWidget);
      expect(find.text('Cleared!'), findsNothing);
    });

    testWidgets('a branch says Boss cleared!', (tester) async {
      await passAudit(api, 1);
      await pass(tester, 2);
      expect(find.text('Boss cleared!'), findsOneWidget);
    });

    testWidgets('a leaf says plain Cleared!', (tester) async {
      for (final id in [1, 2, 5]) {
        await passAudit(api, id);
      }
      await pass(tester, 6);
      expect(key('celebration-card'), findsOneWidget);
      expect(find.text('Cleared!'), findsOneWidget);
      expect(find.text('Boss cleared!'), findsNothing);
    });

    testWidgets('the verdict card keeps the same words for bosses', (tester) async {
      await pass(tester, 1);
      await tester.tap(key('celebration-close'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('verdict-title')).data, 'Cleared.');
      expect(tester.widget<Text>(key('verdict-xp')).data, matches(r'^\+\d+ XP$'));
    });
  });
}
