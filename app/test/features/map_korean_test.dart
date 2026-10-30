// The stat strip and the node sheet speak the app's language: in Korean, none
// of their labels is an English word.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/life_tree.dart';
import 'package:self_infinity/features/map/node_sheet.dart';
import 'package:self_infinity/features/map/stat_strip.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/test_app.dart';

final RegExp _asciiWord = RegExp('[A-Za-z]{2,}');

/// Every string drawn under [root].
List<String> _texts(WidgetTester tester, Finder root) => [
  for (final w in tester.widgetList<Text>(find.descendant(of: root, matching: find.byType(Text))))
    w.data ?? w.textSpan?.toPlainText() ?? '',
  for (final w in tester.widgetList<RichText>(find.descendant(of: root, matching: find.byType(RichText))))
    w.text.toPlainText(),
];

void main() {
  testWidgets('the stat strip and the node sheet have no English in Korean', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = await seededFakeApi();
    final course = (await api.listCourses()).single;
    final map = await api.getCourseMap(course.id);
    final first = map.nodes.firstWhere((n) => n.isAvailable).id;
    await passAudit(api, first);
    final next = (await api.getCourseMap(course.id)).nodes.firstWhere((n) => n.isAvailable).id;
    await failAudit(api, next);
    await api.translateCourses('ko');
    final tree = LifeTree.build(
      goals: await api.listGoals(),
      maps: [await api.getCourseMap(course.id)],
      audits: await api.listAudits(),
      lessons: 2,
    );

    Future<void> pump(Widget child) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        buildTestApp(language: AppLanguage.ko, child: SingleChildScrollView(child: child)),
      );
      await tester.pumpAndSettle();
    }

    await pump(StatStrip(stats: tree.stats));
    final strip = _texts(tester, find.byKey(const Key('stat-strip')));
    expect(strip, isNotEmpty);
    expect(strip.where(_asciiWord.hasMatch), isEmpty);

    // Cleared, failed, ready and locked nodes (and a boss, if the course has one).
    final names = [for (final n in tree.nodes) n.label]..sort((a, b) => b.length - a.length);
    final statuses = <String>{};
    for (final node in tree.nodes) {
      await pump(
        SizedBox(
          width: NodeSheet.width,
          child: NodeSheet(
            node: node,
            tree: tree,
            onClose: () {},
            onOpenSkill: (_) {},
            onOutline: (_) {},
          ),
        ),
      );
      final sheet = find.byKey(Key('node-sheet-${node.key}'));
      // The names of nodes and courses are the user's own data, not the UI.
      final texts = _texts(tester, sheet).map((t) => names.fold(t, (t, name) => t.replaceAll(name, '')));
      expect(texts.where(_asciiWord.hasMatch), isEmpty, reason: 'node ${node.key}');
      final status = find.byKey(const Key('node-sheet-status'));
      if (status.evaluate().isNotEmpty) statuses.addAll(_texts(tester, status));
    }
    expect(statuses, containsAll(['클리어', '미통과', '도전 가능', '잠김']));
  });
}
