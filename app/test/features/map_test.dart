// Scene 2: the node-link skill graph, its layout, the search across courses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/map/graph_layout.dart';
import 'package:self_infinity/features/map/graph_view.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

double measure(String text) => text.runes.length * 8.0;

Future<CourseMap> math() async {
  final api = FakeApiClient(latency: Duration.zero);
  return api.generateCourse(const GenerateRequest(topic: 'math'));
}

int idOf(CourseMap map, String title) => map.nodes.firstWhere((n) => n.title == title).id;

/// The container that holds the fill and the ring of a dot (the inner one of a
/// boss, whose outer container is the extra ring).
Container dotBox(WidgetTester tester, Finder dot) =>
    tester.widgetList<Container>(find.descendant(of: dot, matching: find.byType(Container))).last;

Color dotColor(WidgetTester tester, int id) =>
    (dotBox(tester, find.byKey(Key('dot-$id'))).decoration! as BoxDecoration).color!;

Color dotRing(WidgetTester tester, int id) =>
    ((dotBox(tester, find.byKey(Key('dot-$id'))).decoration! as BoxDecoration).border! as Border)
        .top
        .color;

void main() {
  group('GraphLayout', () {
    test('a column per depth of the main contains tree, left → right', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      int depth(String t) => layout.depths[idOf(map, t)]!;
      expect(depth('High School Math'), 0);
      expect([depth('Algebra'), depth('Functions'), depth('Calculus')], [1, 1, 1]);
      expect(
        [
          depth('Quadratic Equations'),
          depth('Sequences'),
          depth('Linear Functions'),
          depth('Quadratic Functions'),
        ],
        [2, 2, 2, 2],
      );
      expect(depth('Discriminant'), 3);
      // Limits of Sequences has two parents; it is drawn once, under the main one (Calculus).
      expect(depth('Limits of Sequences'), 2);
      final x = {for (final n in map.nodes) n.title: layout.centers[n.id]!.dx};
      expect(x['High School Math']!, lessThan(x['Algebra']!));
      expect(x['Algebra']!, lessThan(x['Quadratic Equations']!));
      expect(x['Quadratic Equations']!, lessThan(x['Discriminant']!));
      expect(x['Algebra'], x['Functions']); // same column, same x
    });

    test('rows: leaves are stacked, a parent sits at the middle of its children', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      Offset at(String t) => layout.centers[idOf(map, t)]!;
      expect(at('Discriminant').dy, lessThan(at('Roots and Coefficients').dy));
      expect(
        at('Quadratic Equations').dy,
        closeTo((at('Discriminant').dy + at('Roots and Coefficients').dy) / 2, 1e-9),
      );
      expect(at('High School Math').dy, greaterThan(at('Discriminant').dy));
      expect(at('High School Math').dy, lessThan(at('Derivatives').dy));
    });

    test('no two nodes overlap and everything is inside the drawing', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      final boxes = [for (final n in map.nodes) layout.boxOf(n.id)];
      for (var i = 0; i < boxes.length; i++) {
        final bounds = Offset.zero & layout.size;
        expect(
          bounds.left <= boxes[i].left &&
              bounds.top <= boxes[i].top &&
              bounds.right >= boxes[i].right &&
              bounds.bottom >= boxes[i].bottom,
          isTrue,
          reason: map.nodes[i].title,
        );
        for (var j = i + 1; j < boxes.length; j++) {
          expect(
            boxes[i].overlaps(boxes[j]),
            isFalse,
            reason: '${map.nodes[i].title} / ${map.nodes[j].title}',
          );
        }
      }
    });

    test('it is deterministic', () async {
      final map = await math();
      final a = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      final b = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      expect(a.size, b.size);
      expect(a.centers, b.centers);
    });

    test('long titles are cut off at the maximum label width', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: (_) => 999);
      expect(layout.labelWidths.values.every((w) => w == GraphLayout.maxLabelWidth), isTrue);
    });

    test('a single node and an empty course', () {
      final one = GraphLayout.compute(
        nodes: [
          const SkillNode(
            id: 1,
            courseId: 1,
            slug: 'a',
            title: 'Alone',
            description: '',
            status: SkillStatus.available,
            nodeType: NodeType.concept,
          ),
        ],
        edges: const [],
        measure: measure,
      );
      expect(one.centers, hasLength(1));
      expect(one.size.width, greaterThan(0));
      final none = GraphLayout.compute(nodes: const [], edges: const [], measure: measure);
      expect(none.centers, isEmpty);
    });

    test('a cycle of contains edges does not hang', () {
      SkillNode n(int id) => SkillNode(
        id: id,
        courseId: 1,
        slug: 's$id',
        title: 'n$id',
        description: '',
        status: SkillStatus.locked,
        nodeType: NodeType.concept,
      );
      SkillEdge e(int a, int b) =>
          SkillEdge(fromId: a, toId: b, kind: SkillEdgeKind.contains, isPrimary: true);
      final layout = GraphLayout.compute(
        nodes: [n(1), n(2)],
        edges: [e(1, 2), e(2, 1)],
        measure: measure,
      );
      expect(layout.centers.keys, containsAll([1, 2]));
    });

    test('arrows: forward ones go from the end of the label to the left of the dot', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      final root = idOf(map, 'High School Math');
      final algebra = idOf(map, 'Algebra');
      final g = GraphEdgeGeometry.between(layout, root, algebra);
      expect(g.start.dx, greaterThan(layout.centers[root]!.dx + GraphLayout.labelGap));
      expect(g.end.dx, lessThan(layout.centers[algebra]!.dx));
      expect(g.start.dy, layout.centers[root]!.dy);
      expect(g.end.dy, layout.centers[algebra]!.dy);
      expect(g.control1.dx, greaterThan(g.start.dx));
      expect(g.control2.dx, lessThan(g.end.dx));
    });

    test('arrows that stay in the column bend around the left of the dots', () async {
      final map = await math();
      final layout = GraphLayout.compute(nodes: map.nodes, edges: map.edges, measure: measure);
      // requires: Linear Functions → Quadratic Functions, both in the third column.
      final g = GraphEdgeGeometry.between(
        layout,
        idOf(map, 'Linear Functions'),
        idOf(map, 'Quadratic Functions'),
      );
      final x = layout.centers[idOf(map, 'Linear Functions')]!.dx;
      expect(g.start.dx, lessThan(x));
      expect(g.end.dx, lessThan(x));
      expect(g.control1.dx, lessThan(g.start.dx));
      expect(g.control2.dx, lessThan(g.end.dx));
      expect(g.start.dx, greaterThan(0)); // room left of the first column is enough
    });
  });

  group('scene 2', () {
    late FakeApiClient api;

    setUp(() async {
      api = await seededFakeApi();
    });

    testWidgets('every node of the newest course is a dot with its title to the right', (
      tester,
    ) async {
      await pumpOutline(tester, api: api);
      final map = await api.getCourseMap(1);
      for (final n in map.nodes) {
        expect(find.byKey(Key('node-${n.id}')), findsOneWidget, reason: n.title);
        final title = find.descendant(
          of: find.byKey(Key('node-${n.id}')),
          matching: find.text(n.title),
        );
        expect(title, findsOneWidget);
        final dot = tester.getCenter(find.byKey(Key('dot-${n.id}')));
        final label = tester.getTopLeft(title);
        expect(label.dx, greaterThan(dot.dx), reason: n.title);
        expect((tester.getCenter(title).dy - dot.dy).abs(), lessThan(4));
      }
      // Small circles, no group boxes, no cards.
      expect(tester.getSize(find.byKey(const Key('dot-1'))), const Size(14, 14));
      expect(find.byType(Card), findsNothing);
      expect(find.byKey(const Key('graph-viewer')), findsOneWidget);
    });

    testWidgets(
      'colors: mastered green, failed red, available white with a blue ring, locked grey',
      (
        tester,
      ) async {
        await passAudit(
          api,
          1,
        ); // High School Math mastered; Algebra (2), Functions (3), Calculus (4) available
        await failAudit(api, 3); // Functions: the newest audit failed
        await passAudit(api, 4); // Calculus mastered
        await failAudit(api, 4); // ...a later failed audit on a mastered node stays green
        await pumpOutline(tester, api: api);

        expect(dotColor(tester, 1), AppColors.success);
        expect(dotColor(tester, 4), AppColors.success);
        expect(dotColor(tester, 3), AppColors.danger);
        expect(dotColor(tester, 2), AppColors.surface); // available: white
        expect(dotRing(tester, 2), AppColors.primary); // ... with a blue ring
        expect(dotColor(tester, 5), AppColors.locked);
      },
    );

    testWidgets('a failed node that is passed later is no longer red', (tester) async {
      await passAudit(api, 1);
      await failAudit(api, 2);
      await passAudit(api, 2);
      await pumpOutline(tester, api: api);
      expect(dotColor(tester, 2), AppColors.success);
    });

    testWidgets('only the latest finished audit of a node counts', (tester) async {
      await passAudit(api, 1);
      await failAudit(api, 2);
      await api.startAudit(2); // an unfinished one on top
      await pumpOutline(tester, api: api);
      expect(dotColor(tester, 2), AppColors.danger);
    });

    testWidgets('tapping a dot or a title opens the node (scene 4)', (tester) async {
      await pumpOutline(tester, api: api);
      await tester.tap(find.byKey(const Key('dot-1')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/1'), findsOneWidget);

      await pumpOutline(tester, api: api);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('node-5')),
          matching: find.text('Quadratic Equations'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/5'), findsOneWidget);
    });

    testWidgets('locked nodes can be opened too (they say they are locked)', (tester) async {
      await pumpOutline(tester, api: api);
      await tester.tap(find.byKey(const Key('node-12')));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/12'), findsOneWidget);
    });

    testWidgets('the title bar is “Life tree”; the outline names the course in a chip', (tester) async {
      await pumpOutline(tester, api: api);
      expect(tester.widget<Text>(find.byKey(const Key('stage-title'))).data, 'Life tree');
      expect(
        find.descendant(
          of: find.byKey(const Key('outline-course-1')),
          matching: find.text('High School Math'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('graph-viewer')),
          matching: find.text('High School Math'),
        ),
        findsOneWidget, // the root node
      );
    });

    testWidgets('a small avatar top-right, next to the numbers, asks you to pick a node', (
      tester,
    ) async {
      await pumpOutline(tester, api: api);
      expect(find.text('Tap a node to take it on.'), findsOneWidget);
      final avatar = tester.widget<Avatar>(find.byType(Avatar));
      expect(avatar.size, lessThan(150));
      expect(avatar.mood, AvatarMood.smile);
      final center = tester.getCenter(find.byType(Avatar));
      expect(center.dx, greaterThan(1000)); // right side of the 1440 px window
      expect(center.dy, lessThan(200)); // beside the numbers, above the tree
      expect(
        find.descendant(of: find.byKey(const Key('map-bubble')), matching: find.text('Guide')),
        findsOneWidget,
      );
    });

    group('the legend', () {
      testWidgets('bottom-left: Ready / Cleared / Failed / Locked, then the Boss ring', (
        tester,
      ) async {
        await pumpOutline(tester, api: api);
        final legend = find.byKey(const Key('graph-legend'));
        expect(legend, findsOneWidget);
        expect(
          textsIn(tester, legend).toList(),
          ['Ready', 'Cleared', 'Failed', 'Locked', 'Boss'],
        );
        final rect = tester.getRect(legend);
        final stage = tester.getRect(find.byKey(const Key('stage-panel')));
        expect(rect.left - stage.left, lessThan(40));
        expect(stage.bottom - rect.bottom, lessThan(120)); // above the search bar
        expect(rect.top, greaterThan(stage.center.dy));
        // The dots use the colors of the graph.
        Color fill(DotKind kind) =>
            (dotBox(tester, find.byKey(Key('legend-dot-${kind.name}'))).decoration!
                    as BoxDecoration)
                .color!;
        Color ring(DotKind kind) =>
            ((dotBox(tester, find.byKey(Key('legend-dot-${kind.name}'))).decoration!
                            as BoxDecoration)
                        .border!
                    as Border)
                .top
                .color;
        expect(fill(DotKind.available), AppColors.surface);
        expect(ring(DotKind.available), AppColors.primary);
        expect(fill(DotKind.mastered), AppColors.success);
        expect(fill(DotKind.failed), AppColors.danger);
        expect(fill(DotKind.locked), AppColors.locked);
      });

      testWidgets('it does not overlap the avatar or the search bar, on a desktop or a phone', (
        tester,
      ) async {
        for (final size in [wideScreen, phoneScreen]) {
          await pumpOutline(tester, api: api, size: size);
          final legend = tester.getRect(find.byKey(const Key('graph-legend')));
          // On a phone she is not shown on this scene.
          if (size == wideScreen) {
            final guide = tester.getRect(find.byKey(const Key('map-guide')));
            expect(legend.overlaps(guide), isFalse, reason: '$size');
          } else {
            expect(find.byKey(const Key('map-guide')), findsNothing);
          }
          expect(legend.overlaps(tester.getRect(find.byKey(const Key('stage-input')))), isFalse);
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('also with no course yet', (tester) async {
        await pumpOutline(tester, api: FakeApiClient(latency: Duration.zero));
        expect(find.byKey(const Key('graph-legend')), findsOneWidget);
      });
    });

    testWidgets('the input is a search bar only: no ⊕, no ∿', (tester) async {
      await pumpOutline(tester, api: api);
      expect(find.text('Search nodes…'), findsOneWidget);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
      expect(find.byKey(const Key('send')), findsOneWidget);
    });

    testWidgets('← goes back to scene 1', (tester) async {
      await pumpOutline(tester, api: api);
      await tester.tap(find.byKey(const Key('back-home')));
      await tester.pumpAndSettle();
      expect(find.text('route:/'), findsOneWidget);
    });

    testWidgets('it shows the newest course; the older one is not drawn', (tester) async {
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
      await pumpOutline(tester, api: api);
      expect(find.byKey(const Key('graph-viewer')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('graph-viewer')),
          matching: find.text('reinforcement learning'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('graph-viewer')), matching: find.text('High School Math')),
        findsNothing,
      );
      expect(find.byKey(const Key('node-13')), findsOneWidget);
      expect(find.byKey(const Key('node-1')), findsNothing);
    });

    testWidgets('typing highlights the matching nodes of the shown course', (tester) async {
      await pumpOutline(tester, api: api);
      await type(tester, 'Function');
      final view = tester.widget<SkillGraphView>(find.byType(SkillGraphView));
      expect(view.highlighted, {3, 9, 10}); // Functions, Linear Functions, Quadratic Functions
      await type(tester, '');
      expect(tester.widget<SkillGraphView>(find.byType(SkillGraphView)).highlighted, isEmpty);
    });

    testWidgets('Enter or → opens the first match', (tester) async {
      await pumpOutline(tester, api: api);
      await say(tester, 'Discrim');
      expect(find.text('route:/skill/6'), findsOneWidget);
    });

    testWidgets('the search spans all courses: a node of an older course is found', (tester) async {
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning')); // shown now
      await pumpOutline(tester, api: api);
      expect(find.text('Discriminant'), findsNothing); // not drawn...
      await say(tester, 'Discrim');
      expect(find.text('route:/skill/6'), findsOneWidget); // ...but found
    });

    testWidgets('a match in the shown course wins over one in an older course', (tester) async {
      await api.generateCourse(
        const GenerateRequest(topic: 'Advanced math'),
      ); // also has Quadratic Equations
      await pumpOutline(tester, api: api);
      await say(tester, 'Quadratic Equations');
      expect(
        find.text('route:/skill/17'),
        findsOneWidget,
      ); // the shown course's Quadratic Equations
    });

    testWidgets('no match: a short message, nothing opens', (tester) async {
      await pumpOutline(tester, api: api);
      await say(tester, 'a node that does not exist');
      expect(find.text('No matching node.'), findsOneWidget);
      expect(find.textContaining('route:'), findsNothing);
      await type(tester, 'Disc');
      expect(find.text('No matching node.'), findsNothing);
    });

    testWidgets('the search is case-insensitive and trims spaces', (tester) async {
      final other = FakeApiClient(latency: Duration.zero);
      await other.generateCourse(const GenerateRequest(topic: 'Python'));
      await pumpOutline(tester, api: other);
      await say(tester, '  python ');
      expect(find.text('route:/skill/1'), findsOneWidget);
    });

    testWidgets('no course yet: the avatar says to tell her what to learn', (tester) async {
      await pumpOutline(tester, api: FakeApiClient(latency: Duration.zero));
      expect(find.byKey(const Key('graph-viewer')), findsNothing);
      expect(find.textContaining('Tell the Guide what you want to learn'), findsOneWidget);
      await say(tester, 'anything');
      expect(find.text('No matching node.'), findsOneWidget);
    });

    testWidgets('a failing load leaves the tree empty until the data changes', (tester) async {
      api.failNext(method: 'listCourses');
      final state = AppState();
      await pumpScene(tester, const MapScene(), api: api, state: state);
      expect(find.byKey(const Key('life-empty')), findsOneWidget);
      state.markDataChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('life-empty')), findsNothing);
      await tester.tap(find.byKey(const Key('view-outline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-1')), findsOneWidget);
    });

    testWidgets('it reloads when data changes (an audit finished)', (tester) async {
      final state = AppState();
      await pumpOutline(tester, api: api, state: state);
      expect(dotColor(tester, 1), AppColors.surface);
      await passAudit(api, 1);
      state.markDataChanged();
      await tester.pumpAndSettle();
      expect(dotColor(tester, 1), AppColors.success);
    });

    testWidgets('the graph can be panned and zoomed', (tester) async {
      await pumpOutline(tester, api: api);
      final viewer = tester.widget<InteractiveViewer>(find.byKey(const Key('graph-viewer')));
      expect(viewer.panEnabled, isTrue);
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.maxScale, greaterThan(viewer.minScale));
      final before = tester.getCenter(find.byKey(const Key('dot-1')));
      final empty =
          tester.getTopLeft(find.byKey(const Key('graph-viewer'))) + const Offset(300, 40);
      await tester.dragFrom(empty, const Offset(-80, 30));
      await tester.pump();
      final after = tester.getCenter(find.byKey(const Key('dot-1')));
      expect(after.dx, closeTo(before.dx - 80, 1));
      expect(after.dy, closeTo(before.dy + 30, 1));
    });

    testWidgets('on a phone the graph keeps readable text and does not overflow', (tester) async {
      await pumpOutline(tester, api: api, size: phoneScreen);
      expect(tester.takeException(), isNull);
      final matrix = tester
          .widget<InteractiveViewer>(find.byKey(const Key('graph-viewer')))
          .transformationController!
          .value;
      expect(matrix.getMaxScaleOnAxis(), greaterThanOrEqualTo(0.8));
      expect(find.byKey(const Key('node-1')), findsOneWidget);
    });
  });

  test('kindOf: mastered beats failed; failed beats available; locked stays locked', () {
    SkillNode node(SkillStatus s) => SkillNode(
      id: 1,
      courseId: 1,
      slug: 's',
      title: 't',
      description: '',
      status: s,
      nodeType: NodeType.concept,
    );
    expect(SkillGraphView.kindOf(node(SkillStatus.mastered), {1}), DotKind.mastered);
    expect(SkillGraphView.kindOf(node(SkillStatus.available), {1}), DotKind.failed);
    expect(SkillGraphView.kindOf(node(SkillStatus.available), {}), DotKind.available);
    expect(SkillGraphView.kindOf(node(SkillStatus.locked), {}), DotKind.locked);
  });
}
