// The one input bar (`Composer`): the same pill on every screen, the voice key
// always outside it on the right.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

void main() {
  late TextEditingController controller;
  late FakeVoiceService voice;

  Future<void> pump(
    WidgetTester tester, {
    ComposerLeading leading = ComposerLeading.none,
    bool multiline = false,
    VoidCallback? onSend,
    bool showSend = true,
    VoidCallback? onVoiceMode,
    VoidCallback? onAttach,
    bool enabled = true,
    bool busy = false,
    int? maxLength,
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestApp(
        voice: voice,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Composer(
                controller: controller,
                hint: 'Say it…',
                fieldKey: const Key('field'),
                leading: leading,
                multiline: multiline,
                onSend: onSend,
                showSend: showSend,
                onVoiceMode: onVoiceMode,
                onAttach: onAttach,
                enabled: enabled,
                busy: busy,
                maxLength: maxLength,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  BoxDecoration pill(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.borderRadius == AppRadius.pillBorder);

  Finder pillFinder(WidgetTester tester) => find.byWidgetPredicate(
    (w) => w is Container && (w.decoration as BoxDecoration?)?.borderRadius == AppRadius.pillBorder,
  );

  setUp(() {
    controller = TextEditingController();
    voice = FakeVoiceService();
  });
  tearDown(() => controller.dispose());

  testWidgets('every variant: a 52 px surfaceHigh pill and a 40 px round key outside it', (
    tester,
  ) async {
    for (final variant in <Future<void> Function()>[
      () => pump(tester, onSend: () {}, onVoiceMode: () {}, leading: ComposerLeading.attach, onAttach: () {}),
      () => pump(tester, onSend: () {}),
      () => pump(tester, onSend: () {}, leading: ComposerLeading.search),
      () => pump(tester, multiline: true),
    ]) {
      await variant();
      final d = pill(tester);
      expect(d.color, AppColors.surfaceHigh);
      expect(d.boxShadow, isNull);
      expect(tester.getSize(pillFinder(tester)).height, Composer.barHeight);
      final voiceKey = find.byWidgetPredicate(
        (w) => w is IconButton && (w.key == const Key('voice-mode') || w.key == const Key('dictation-button')),
      );
      expect(voiceKey, findsOneWidget);
      // 40 px drawn (the tap target around it is 48).
      final drawn = find.descendant(of: voiceKey, matching: find.byType(Material)).first;
      expect(tester.getSize(drawn), const Size.square(40));
      // Outside the pill, on its right, level with it.
      final pillRect = tester.getRect(pillFinder(tester));
      final keyRect = tester.getRect(drawn);
      expect(keyRect.left, greaterThan(pillRect.right));
      expect(keyRect.center.dy, closeTo(pillRect.center.dy, 0.5));
    }
  });

  testWidgets('leading: ⊕ attaches, 🔍 is a magnifier, none is nothing', (tester) async {
    var attached = 0;
    await pump(tester, leading: ComposerLeading.attach, onAttach: () => attached++);
    await tester.tap(find.byKey(const Key('upload')));
    expect(attached, 1);
    expect(find.byIcon(Icons.search_rounded), findsNothing);

    await pump(tester, leading: ComposerLeading.search);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(const Key('upload')), findsNothing);

    await pump(tester);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.byKey(const Key('upload')), findsNothing);
  });

  testWidgets('the voice key is ∿ with onVoiceMode, else a microphone that dictates', (
    tester,
  ) async {
    var talks = 0;
    await pump(tester, onVoiceMode: () => talks++);
    expect(find.byKey(const Key('dictation-button')), findsNothing);
    await tester.tap(find.byKey(const Key('voice-mode')));
    expect(talks, 1);

    await pump(tester);
    expect(find.byKey(const Key('voice-mode')), findsNothing);
    await tester.tap(find.byKey(const Key('dictation-button')));
    await tester.pump();
    expect(find.byKey(const Key('dictation-stop')), findsOneWidget);
    voice.hear('a spoken line');
    await tester.pumpAndSettle();
    expect(controller.text, 'a spoken line');
  });

  testWidgets('send: inside the pill on the right, grey while empty; Enter sends', (
    tester,
  ) async {
    var sent = 0;
    await pump(tester, onSend: () => sent++);
    final send = find.byKey(const Key('send'));
    expect(tester.getRect(send).right, lessThan(tester.getRect(pillFinder(tester)).right));
    await tester.tap(send);
    expect(sent, 0);
    await tester.enterText(find.byKey(const Key('field')), 'hi');
    await tester.pump();
    await tester.tap(send);
    expect(sent, 1);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sent, 2);
  });

  testWidgets('no onSend, or showSend false: no send key', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('send')), findsNothing);
    var sent = 0;
    await pump(tester, onSend: () => sent++, showSend: false);
    expect(find.byKey(const Key('send')), findsNothing);
    await tester.enterText(find.byKey(const Key('field')), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sent, 1);
  });

  testWidgets('busy: the arrow turns into a spinner and nothing is sent; typing goes on', (
    tester,
  ) async {
    var sent = 0;
    await pump(tester, onSend: () => sent++, busy: true);
    await tester.enterText(find.byKey(const Key('field')), 'the next one');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sent, 0);
    expect(controller.text, 'the next one');
    expect(tester.widget<MorphIcon>(find.byKey(const Key('send-icon'))).morphed, isTrue);
  });

  testWidgets('disabled: no send, no attach, no voice', (tester) async {
    var calls = 0;
    await pump(
      tester,
      onSend: () => calls++,
      leading: ComposerLeading.attach,
      onAttach: () => calls++,
      onVoiceMode: () => calls++,
      enabled: false,
    );
    expect(tester.widget<IconButton>(find.byKey(const Key('upload'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const Key('voice-mode'))).onPressed, isNull);
    await pump(tester, enabled: false);
    expect(tester.widget<IconButton>(find.byKey(const Key('dictation-button'))).onPressed, isNull);
  });

  testWidgets('multiline: Enter is a new line and the pill grows; keys stay at the bottom', (
    tester,
  ) async {
    await pump(tester, multiline: true);
    final field = tester.widget<TextField>(find.byKey(const Key('field')));
    expect(field.maxLines, greaterThan(1));
    expect(field.textInputAction, TextInputAction.newline);
    await tester.enterText(find.byKey(const Key('field')), 'one\ntwo\nthree\nfour');
    await tester.pump();
    final pillRect = tester.getRect(pillFinder(tester));
    expect(pillRect.height, greaterThan(Composer.barHeight));
    final mic = tester.getRect(find.byKey(const Key('dictation-button')));
    expect(mic.bottom, greaterThan(pillRect.bottom - Composer.barHeight / 2));
  });

  testWidgets('focus draws a 1 px ink edge', (tester) async {
    await pump(tester);
    expect((pill(tester).border! as Border).top.color, Colors.transparent);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    final edge = (pill(tester).border! as Border).top;
    expect(edge.color, AppColors.primary);
    expect(edge.width, 1);
  });

  testWidgets('maxLength cuts typing and shows no counter', (tester) async {
    await pump(tester, maxLength: 5);
    await tester.enterText(find.byKey(const Key('field')), 'abcdefgh');
    await tester.pump();
    expect(controller.text, 'abcde');
    expect(find.text('5/5'), findsNothing);
  });

  testWidgets('on a phone, dictating does not overflow', (tester) async {
    await pump(tester, size: const Size(360, 640), onSend: () {}, leading: ComposerLeading.search);
    await tester.tap(find.byKey(const Key('dictation-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
