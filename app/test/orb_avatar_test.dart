// OrbAvatar: the crystal ball floats beside 大肥鱼 and the two react to each other.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/widgets/widgets.dart';

final ThemeData _theme = AppTheme.light();
const _ball = Key('crystal-ball');

Future<void> pumpOrb(
  WidgetTester tester, {
  VoidCallback? onTap,
  AvatarState state = AvatarState.idle,
}) => tester.pumpWidget(
  MaterialApp(
    theme: _theme,
    home: Scaffold(
      body: Center(
        child: OrbAvatar(
          agent: 'front_desk',
          size: 280,
          state: state,
          onOrbTap: onTap,
          orb: const SizedBox.expand(key: Key('mini-tree')),
        ),
      ),
    ),
  ),
);

Avatar figure(WidgetTester tester) => tester.widget<Avatar>(find.byType(Avatar));

/// The pixels of the ball and its glow (the ball's own repaint boundary).
Future<Uint8List> ballPixels(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: find.byType(OrbAvatar), matching: find.byType(RepaintBoundary)).first,
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}

bool same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<TestGesture> hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byKey(_ball)));
  await tester.pump();
  return mouse;
}

void main() {
  setUp(() => Avatar.animationsEnabled = false);

  testWidgets('the ball floats beside her at chest height, in a normal pose', (tester) async {
    await pumpOrb(tester);
    expect(figure(tester).holdOrb, isFalse);
    expect(figure(tester).reaction, isNull);
    final her = tester.getRect(find.byType(Avatar));
    final ball = tester.getRect(find.byKey(_ball));
    expect(ball.width, closeTo(ball.height, 0.01));
    // Beside her (her hair reaches a little past her box), not over her hands.
    expect(ball.left, greaterThan(her.right - her.width * 0.05));
    expect(ball.center.dy, inInclusiveRange(her.top + her.height * 0.3, her.top + her.height * 0.6));
    expect(tester.getSize(find.byType(OrbAvatar)).width, greaterThanOrEqualTo(ball.right - her.left));
  });

  testWidgets('hovering the ball: it glows brighter and she looks at it', (tester) async {
    await pumpOrb(tester, onTap: () {});
    final calm = await ballPixels(tester);
    final mouse = await hover(tester);
    expect(figure(tester).reaction, AvatarReaction.lookAside);
    expect(same(calm, await ballPixels(tester)), isFalse, reason: 'the glow');
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(figure(tester).reaction, isNull);
    expect(same(calm, await ballPixels(tester)), isTrue);
  });

  testWidgets('tapping with motion off: she is surprised and the ball opens at once', (
    tester,
  ) async {
    var taps = 0;
    await pumpOrb(tester, onTap: () => taps++);
    await tester.tap(find.byKey(_ball));
    await tester.pump();
    expect(taps, 1);
    expect(figure(tester).reaction, AvatarReaction.surprised);
    await tester.pump(OrbAvatar.reactFor);
    expect(figure(tester).reaction, isNull);
    expect(taps, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('tapping with motion on: she reacts first, then the ball opens once', (
    tester,
  ) async {
    Avatar.animationsEnabled = true;
    addTearDown(() => Avatar.animationsEnabled = false);
    var taps = 0;
    await pumpOrb(tester, onTap: () => taps++);
    await tester.tap(find.byKey(_ball));
    await tester.pump(const Duration(milliseconds: 100));
    expect(figure(tester).reaction, AvatarReaction.surprised);
    expect(taps, 0);
    await tester.tap(find.byKey(_ball)); // a second tap does not go twice
    await tester.pump(OrbAvatar.reactFor);
    expect(taps, 1);
    expect(figure(tester).reaction, isNull);
    await tester.pump(OrbAvatar.reactFor);
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while she speaks the glow is up; motion off keeps the ball still', (
    tester,
  ) async {
    await pumpOrb(tester);
    final idle = await ballPixels(tester);
    await pumpOrb(tester, state: AvatarState.speaking);
    expect(figure(tester).state, AvatarState.speaking);
    expect(same(idle, await ballPixels(tester)), isFalse);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with motion on the ball bobs and pulses', (tester) async {
    Avatar.animationsEnabled = true;
    addTearDown(() => Avatar.animationsEnabled = false);
    await pumpOrb(tester, onTap: () {});
    await tester.pump(const Duration(milliseconds: 16));
    final a = tester.getRect(find.byKey(_ball));
    await tester.pump(Avatar.idleLoop ~/ 4);
    final b = tester.getRect(find.byKey(_ball));
    expect(b.center.dy, lessThan(a.center.dy), reason: 'it floats up');
    await tester.pumpWidget(const SizedBox());
  });
}
