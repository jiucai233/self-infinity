import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/widgets/widgets.dart';

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(of: find.byType(EnterIn), matching: find.byType(Opacity)))
    .opacity;

Widget _app({bool reduce = false, bool animate = true}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: EnterIn(animate: animate, child: const Text('hi')),
  ),
);

void main() {
  final was = Avatar.animationsEnabled;
  setUp(() => Avatar.animationsEnabled = true);
  tearDown(() => Avatar.animationsEnabled = was);

  testWidgets('a new line fades in over 220 ms', (tester) async {
    await tester.pumpWidget(_app());
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 110));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 110));
    expect(_opacity(tester), 1);
    expect(EnterIn.defaultDuration.inMilliseconds, inInclusiveRange(200, 250));
  });

  testWidgets('with reduce motion on it is there at once', (tester) async {
    await tester.pumpWidget(_app(reduce: true));
    expect(_opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a line that was already there does not move', (tester) async {
    await tester.pumpWidget(_app(animate: false));
    expect(_opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
