import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/life_constellation.dart';

import '../support/scene_helpers.dart';

/// Scene 2 on a phone: big enough touch targets, labels that never overlap,
/// the node card as a bottom sheet, and an outline whose names are not cut.
void main() {
  LifeConstellationState sky(WidgetTester tester) =>
      tester.state<LifeConstellationState>(find.byType(LifeConstellation));

  Offset global(WidgetTester tester, Offset local) =>
      tester.renderObject<RenderBox>(find.byType(LifeConstellation)).localToGlobal(local);

  double contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05, lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }

  group('the tree', () {
    testWidgets('every node is a touch target of at least 44 px; the nearest one wins', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: phoneScreen);
      expect(LifeConstellation.hitRadius * 2, greaterThanOrEqualTo(44));
      final state = sky(tester);
      final tree = tester.widget<LifeConstellation>(find.byType(LifeConstellation)).tree;
      final keys = [
        for (final n in tree.nodes)
          if (state.positionOf(n.key) != null) n.key,
      ];
      expect(keys.length, greaterThan(5));
      for (final k in keys) {
        final p = state.positionOf(k)!;
        // On the node, it is that node.
        expect(state.nodeAt(p), k, reason: k);
        // 21 px away in any direction is still a node (it or a nearer one).
        for (final d in const [Offset(21, 0), Offset(-21, 0), Offset(0, 21), Offset(0, -21)]) {
          final hit = state.nodeAt(p + d);
          expect(hit, isNotNull, reason: '$k $d');
          final others = (state.positionOf(hit!)! - (p + d)).distance;
          expect(others, lessThanOrEqualTo(21.001), reason: '$k $d: the nearest wins');
        }
      }
    });

    testWidgets('a tap next to a node, not on it, opens its card', (tester) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: phoneScreen);
      final state = sky(tester);
      final p = state.positionOf('s5')!;
      // Off by 18 px towards the side with no other node nearer.
      final at = [
        for (final d in const [Offset(18, 0), Offset(-18, 0), Offset(0, 18), Offset(0, -18)]) p + d,
      ].firstWhere((q) => state.nodeAt(q) == 's5');
      await tester.tapAt(global(tester, at));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s5')), findsOneWidget);
    });

    for (final (name, size) in [('phone', phoneScreen), ('desktop', wideScreen)]) {
      testWidgets('while searching ($name), no label lies over another or past the panel', (
        tester,
      ) async {
        await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: size);
        await type(tester, 'Function');
        await tester.pump();
        final state = sky(tester);
        final labels = state.labelRects;
        final panel = Offset.zero & tester.getSize(find.byType(LifeConstellation));
        final rects = labels.values.toList();
        for (var i = 0; i < rects.length; i++) {
          expect(panel.contains(rects[i].topLeft), isTrue);
          expect(rects[i].right, lessThanOrEqualTo(panel.right));
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: '${labels.keys}');
          }
        }
        // The hits are named.
        final hits = tester.widget<LifeConstellation>(find.byType(LifeConstellation)).highlighted;
        expect(hits, isNotEmpty);
        for (final k in hits) {
          expect(labels.containsKey(k), isTrue, reason: k);
        }
      });
    }

    testWidgets('a selected node and its neighbours are named, none over another', (tester) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: phoneScreen);
      final state = sky(tester);
      await tester.tapAt(global(tester, state.positionOf('s5')!));
      await tester.pumpAndSettle();
      final labels = state.labelRects;
      expect(labels.containsKey('s5'), isTrue);
      final rects = labels.values.toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    testWidgets('the hint and the legend are readable on the night panel (4.5:1)', (tester) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: wideScreen);
      final hint = tester.widget<Text>(find.byKey(const Key('night-hint'))).style!.color!;
      expect(contrast(Color.alphaBlend(hint, AppColors.night), AppColors.night), greaterThanOrEqualTo(4.5));
      final legend = find.byKey(const Key('night-legend'));
      for (final text in tester.widgetList<Text>(find.descendant(of: legend, matching: find.byType(Text)))) {
        final c = text.style!.color!;
        expect(contrast(Color.alphaBlend(c, AppColors.night), AppColors.night), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('the node card on a phone', () {
    testWidgets('is a bottom sheet that drags up to the whole stage; its button is reachable', (
      tester,
    ) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: phoneScreen);
      await tester.tapAt(global(tester, sky(tester).positionOf('s5')!));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-bottom-sheet')), findsOneWidget);
      expect(find.byKey(const Key('node-sheet-handle')), findsOneWidget);
      final stage = tester.getRect(find.byKey(const Key('stage-panel')));
      final opened = tester.getRect(find.byKey(const Key('node-sheet-s5')));
      expect(opened.top, greaterThan(stage.top + 100)); // the tree still shows above it

      await tester.drag(find.byKey(const Key('node-sheet-handle')), const Offset(0, -900));
      await tester.pumpAndSettle();
      // Up to the whole stage: over the numbers too.
      final full = tester.getRect(find.byKey(const Key('node-sheet-s5')));
      expect(full.top, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('stat-strip'))).top));
      // Whatever does not fit scrolls into view; the button is then on screen.
      await tester.scrollUntilVisible(
        find.byKey(const Key('node-sheet-open')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('node-sheet-s5')),
          matching: find.byType(Scrollable),
        ),
      );
      final button = tester.getRect(find.byKey(const Key('node-sheet-open')));
      expect(button.bottom, lessThanOrEqualTo(phoneScreen.height));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('node-sheet-open')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/5'), findsOneWidget);
    });

    testWidgets('dragged down, it closes; × closes it too', (tester) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: phoneScreen);
      await tester.tapAt(global(tester, sky(tester).positionOf('s5')!));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('node-sheet-handle')), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s5')), findsNothing);

      await tester.tapAt(global(tester, sky(tester).positionOf('s5')!));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s5')), findsNothing);
    });

    testWidgets('a desktop keeps the card on the panel', (tester) async {
      await pumpScene(tester, const MapScene(), api: await seededFakeApi(), size: wideScreen);
      await tester.tapAt(global(tester, sky(tester).positionOf('s5')!));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-sheet-s5')), findsOneWidget);
      expect(find.byKey(const Key('node-bottom-sheet')), findsNothing);
    });
  });

  group('the outline on a phone', () {
    Finder nodes() => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && RegExp(r'^node-\d+$').hasMatch(k.value);
    });

    void noneCut(WidgetTester tester, Rect viewer) {
      for (final e in nodes().evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.left, greaterThanOrEqualTo(viewer.left - 0.5), reason: '${e.widget.key}');
        expect(r.right, lessThanOrEqualTo(viewer.right + 0.5), reason: '${e.widget.key}');
      }
    }

    testWidgets('a course that fits is shrunk to fit: no name is cut at the edge', (tester) async {
      final api = await seededFakeApi();
      await api.generateCourse(const GenerateRequest(topic: 'writing'));
      // A small phone held sideways, or a big one: the course is a little
      // wider than the panel at full size.
      await pumpOutline(tester, api: api, size: const Size(560, 900));
      expect(nodes(), findsWidgets);
      final viewer = tester.getRect(find.byKey(const Key('graph-viewer')));
      final content = tester.getRect(find.byKey(const Key('graph-content')));
      expect(content.width, lessThanOrEqualTo(viewer.width)); // shrunk to fit
      noneCut(tester, viewer);
      expect(find.byKey(const Key('outline-more-right')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wider one scrolls sideways, with a soft edge where more of it is', (
      tester,
    ) async {
      await pumpOutline(tester, api: await seededFakeApi(), size: phoneScreen);
      final viewer = tester.getRect(find.byKey(const Key('graph-viewer')));
      final content = tester.getRect(find.byKey(const Key('graph-content')));
      expect(content.width, greaterThan(viewer.width)); // the math course is deep
      expect(find.byKey(const Key('outline-more-right')), findsOneWidget);
      expect(find.byKey(const Key('outline-more-left')), findsNothing);
      // Dragged left, its right end comes into view, names whole.
      await tester.drag(find.byKey(const Key('graph-viewer')), Offset(viewer.right - content.right - 40, 0));
      await tester.pumpAndSettle();
      final rightmost = nodes().evaluate().map((e) => tester.getRect(find.byWidget(e.widget)).right).reduce(
        (a, b) => a > b ? a : b,
      );
      expect(rightmost, lessThanOrEqualTo(viewer.right + 0.5));
      expect(find.byKey(const Key('outline-more-right')), findsNothing);
      expect(find.byKey(const Key('outline-more-left')), findsOneWidget);
    });
  });
}
