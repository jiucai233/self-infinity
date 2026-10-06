// Renders the ink life tree to PNG for a look: SHOTS_DIR=… flutter test test/ink_tree_preview_test.dart
// Skipped without SHOTS_DIR.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/life_tree.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/avatar.dart';
import 'package:self_infinity/widgets/ink_tree.dart';

const _flutterFonts = '/Users/jiucai/development/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final f = File(p);
      if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', ['$_flutterFonts/Roboto-Regular.ttf']);
  await load('InstrumentSerif', [
    'assets/fonts/InstrumentSerif-Regular.ttf',
    'assets/fonts/InstrumentSerif-Italic.ttf',
  ]);
}

/// A tree with some shape: two quests, four courses, some of it cleared.
Future<LifeTree> sampleTree() async {
  final api = FakeApiClient(latency: Duration.zero);
  for (final topic in ['math', 'Writing', 'Statistics', 'Cooking']) {
    await api.generateCourse(GenerateRequest(topic: topic));
  }
  for (final id in [1, 2, 4, 13, 14]) {
    await passAudit(api, id);
  }
  await failAudit(api, 3);
  final g1 = await api.createGoal('Teach calculus to a stranger');
  await api.updateGoal(g1.id, courseIds: [1, 3]);
  final g2 = await api.createGoal('Write every week');
  await api.updateGoal(g2.id, courseIds: [2]);
  final courses = await api.listCourses();
  return LifeTree.build(
    goals: await api.listGoals(),
    maps: [for (final c in courses) await api.getCourseMap(c.id)],
    audits: await api.listAudits(),
  );
}

void main() {
  final dir = Platform.environment['SHOTS_DIR'];

  testWidgets(skip: dir == null, 'ink tree preview', (tester) async {
    Avatar.animationsEnabled = false;
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tree = (await tester.runAsync(sampleTree))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: AppColors.background,
            child: InkTree(tree: tree, selected: 's1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => render.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('$dir/ink-tree.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
