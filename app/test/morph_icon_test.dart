// MorphIcon: stroke icons that morph on a spring (after Morphicons).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/widgets/widgets.dart';

Widget _host(MorphShape from, MorphShape to, bool morphed) => MaterialApp(
  home: Center(child: MorphIcon(from: from, to: to, morphed: morphed, size: 48)),
);

void main() {
  tearDown(() => Avatar.animationsEnabled = true);

  testWidgets('shapes with different stroke counts morph both ways without errors', (tester) async {
    Avatar.animationsEnabled = true;
    for (final (a, b) in [
      (MorphShapes.arrow, MorphShapes.signIn), // 2 → 3 strokes: the door grows out of the tip
      (MorphShapes.mic, MorphShapes.stop), // 3 → 1: the stand shrinks away
      (MorphShapes.arrow, MorphShapes.ring),
      (MorphShapes.bars, MorphShapes.barsBeat),
    ]) {
      await tester.pumpWidget(_host(a, b, false));
      await tester.pumpWidget(_host(a, b, true));
      await tester.pump(const Duration(milliseconds: 60)); // mid-flight
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(a, b, false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('with animations off it jumps straight to the end', (tester) async {
    Avatar.animationsEnabled = false;
    await tester.pumpWidget(_host(MorphShapes.arrow, MorphShapes.ring, false));
    await tester.pumpWidget(_host(MorphShapes.arrow, MorphShapes.ring, true));
    expect(tester.hasRunningAnimations, isFalse);
  });

  // SHOTS_DIR=… renders each morph: start, mid-flight, end.
  final dir = Platform.environment['SHOTS_DIR'];
  testWidgets(skip: dir == null, 'morph preview', (tester) async {
    Avatar.animationsEnabled = true;
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pairs = [
      (MorphShapes.arrow, MorphShapes.signIn),
      (MorphShapes.mic, MorphShapes.stop),
      (MorphShapes.arrow, MorphShapes.ring),
      (MorphShapes.bars, MorphShapes.barsBeat),
    ];
    final boundary = GlobalKey();
    Widget grid(bool go) => MaterialApp(
      home: RepaintBoundary(
        key: boundary,
        child: ColoredBox(
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (a, b) in pairs)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    MorphIcon(from: a, to: b, morphed: false, size: 72),
                    MorphIcon(from: a, to: b, morphed: go, size: 72),
                    MorphIcon(from: a, to: b, morphed: true, size: 72),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(grid(false));
    await tester.pumpWidget(grid(true));
    await tester.pump(const Duration(milliseconds: 45));
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => render.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('$dir/morphs.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    await tester.pumpAndSettle();
  });
}
