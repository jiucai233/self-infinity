// Shared widgets: error / empty / loading views, the primary button, the English
// vocabulary, the input bar and the test helpers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:self_infinity/api/api.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/app/router.dart';
import 'package:self_infinity/features/stage/stage_input_bar.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/voice/voice_mode.dart';
import 'package:self_infinity/widgets/widgets.dart';
import 'package:self_infinity/l10n/l10n.dart';

Future<void> pumpApp(WidgetTester tester, Widget child, {SelfInfinityApi? api}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    buildTestApp(
      api: api,
      child: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  group('API errors are readable, never a crash (FT-12)', () {
    testWidgets('ErrorView shows the English text of a 502 and no stack trace', (tester) async {
      await pumpApp(
        tester,
        const ErrorView(
          error: ApiException(502, 'The auditor is temporarily unavailable. Please try again.'),
        ),
      );
      expect(find.text('Something went wrong on our side. Please try again.'), findsOneWidget);
      expect(find.textContaining('temporarily'), findsNothing);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.text('Try again'), findsNothing); // no retry callback → no button
    });

    testWidgets('ErrorView shows the right text for every status', (tester) async {
      const cases = <(ApiException, String)>[
        (ApiException.network(), "Can't reach the server. Check your connection."),
        (ApiException(400, 'skill is locked'), 'This node is locked. Clear its parent first.'),
        (ApiException(400, 'whatever'), "You can't do that right now."),
        (ApiException(404, 'skill not found'), "We couldn't find that."),
        (ApiException(422), 'Please check what you entered.'),
        (ApiException(500), 'Something went wrong.'),
      ];
      for (final (error, text) in cases) {
        await pumpApp(tester, ErrorView(error: error));
        expect(find.text(text), findsOneWidget, reason: '${error.statusCode}');
      }
    });

    testWidgets('arbitrary errors hide behind a generic text', (tester) async {
      await pumpApp(tester, ErrorView(error: StateError('internal detail'), onRetry: () {}));
      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.textContaining('internal detail'), findsNothing);
    });

    testWidgets('ErrorView offers a retry button when asked', (tester) async {
      var retried = 0;
      await pumpApp(tester, ErrorView(error: const ApiException(502), onRetry: () => retried++));
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });
  });

  group('small widgets', () {
    testWidgets('LoadingView and EmptyView', (tester) async {
      await pumpApp(tester, const LoadingView());
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pumpApp(tester, const LoadingView(message: 'Calling the Auditor…'));
      expect(find.text('Calling the Auditor…'), findsOneWidget);

      var taps = 0;
      await pumpApp(
        tester,
        EmptyView(
          message: 'Nothing here yet',
          action: PrimaryButton(label: 'Create', onPressed: () => taps++),
        ),
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.tap(find.text('Create'));
      expect(taps, 1);
    });

    testWidgets('PrimaryButton: blue, tap, disabled and busy', (tester) async {
      var taps = 0;
      await pumpApp(tester, PrimaryButton(label: 'Start', onPressed: () => taps++));
      await tester.tap(find.text('Start'));
      expect(taps, 1);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.primary);

      await pumpApp(tester, const PrimaryButton(label: 'Start', onPressed: null));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await pumpApp(tester, PrimaryButton(label: 'Start', busy: true, onPressed: () => taps++));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1); // a busy button ignores taps
    });
  });

  group('vocabulary', () {
    test('English labels', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(AuditStatus.passed.label(l), 'Passed');
      expect(AuditStatus.failed.label(l), 'Failed');
      expect(AuditStatus.active.label(l), 'In progress');
    });

    test('status and condition colors follow the tokens', () {
      expect(AuditStatus.passed.color, AppColors.success);
      expect(AuditStatus.failed.color, AppColors.danger);
      expect(ConditionFlag.low.color, AppColors.danger);
      expect(ConditionFlag.normal.color, AppColors.primary);
      expect(ConditionFlag.unknown.color, AppColors.primary);
      expect(AuditStatus.passed.fill, AppColors.successSoft);
      expect(AuditStatus.failed.fill, AppColors.dangerSoft);
      final l = lookupAppLocalizations(const Locale('en'));
      expect(ConditionFlag.normal.label(l), 'Good');
      expect(ConditionFlag.low.label(l), 'Low');
      expect(ConditionFlag.unknown.label(l), 'No record');
    });

    test('the condition bar: normal full, low half and red, unknown empty', () {
      expect(ConditionFlag.normal.fill, 1);
      expect(ConditionFlag.low.fill, 0.5);
      expect(ConditionFlag.unknown.fill, 0);
    });

    test('agentLabel names every agent; user messages are You', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(agentLabel(l, null), 'You');
      expect(agentLabel(l, 'front_desk'), 'Guide');
      expect(agentLabel(l, 'auditor'), 'Auditor');
      expect(agentLabel(l, 'recorder'), 'Recorder');
      expect(agentLabel(l, 'unknown'), 'unknown');
    });

    test('formatNumber trims useless zeros', () {
      expect(formatNumber(6.0), '6');
      expect(formatNumber(5.30), '5.3');
      expect(formatNumber(1.2100), '1.21');
      expect(formatNumber(0), '0');
    });
  });

  group('StageInputBar', () {
    Future<TextEditingController> pumpBar(
      WidgetTester tester, {
      VoidCallback? onUpload,
      VoidCallback? onVoice,
      VoiceModeController? mode,
      bool search = false,
      bool enabled = true,
      List<InputAttachment> attachments = const [],
      String? error,
      VoidCallback? onSubmit,
    }) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: StageInputBar(
            controller: controller,
            hint: 'Message…',
            onSubmit: onSubmit ?? () {},
            enabled: enabled,
            search: search,
            onUpload: onUpload,
            onVoiceMode: onVoice,
            voiceMode: mode,
            attachments: attachments,
            error: error,
          ),
        ),
      );
      return controller;
    }

    testWidgets('chat variant: ⊕ upload, the field, send and the ∿ voice button', (tester) async {
      await pumpBar(tester, onUpload: () {}, onVoice: () {});
      expect(find.byKey(const Key('upload')), findsOneWidget);
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
      expect(find.byKey(const Key('send')), findsOneWidget);
      expect(find.byKey(const Key('voice-mode')), findsOneWidget);
      expect(find.text('Message…'), findsOneWidget);
    });

    testWidgets('without callbacks there is no ⊕ and no ∿', (tester) async {
      await pumpBar(tester);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
    });

    testWidgets('search variant: a magnifier, a send, nothing else', (tester) async {
      await pumpBar(tester, search: true);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
      expect(find.byKey(const Key('send')), findsOneWidget);
    });

    testWidgets('the pill: a filled surfaceHigh capsule, no border, no shadow, 52 px high', (
      tester,
    ) async {
      await pumpBar(tester);
      final pillBox = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere(
            (c) => (c.decoration as BoxDecoration?)?.borderRadius == BorderRadius.circular(28),
          );
      final pill = pillBox.decoration! as BoxDecoration;
      expect(tester.getSize(find.byWidget(pillBox)).height, 52);
      expect(pill.color, AppColors.surfaceHigh);
      expect((pill.border! as Border).top.color, Colors.transparent);
      expect(pill.boxShadow, isNull);
      expect(tester.getSize(find.byKey(const Key('send'))), const Size(36, 36));
    });

    testWidgets('focusing the field draws a blue 1 px edge', (tester) async {
      await pumpBar(tester);
      BoxDecoration pill() => tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.borderRadius == BorderRadius.circular(28));
      expect((pill().border! as Border).top.color, Colors.transparent);
      await tester.tap(find.byKey(const Key('stage-input')));
      await tester.pump();
      final border = pill().border! as Border;
      expect(border.top.color, AppColors.primary);
      expect(border.top.width, 1);
    });

    testWidgets('send is grey while empty and a blue circle with text; Enter sends', (
      tester,
    ) async {
      var sent = 0;
      final controller = await pumpBar(tester, onSubmit: () => sent++);
      Color sendColor() =>
          (tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: find.byKey(const Key('send')),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      expect(sendColor(), AppColors.outline);
      await tester.tap(find.byKey(const Key('send')));
      expect(sent, 0);

      await tester.enterText(find.byKey(const Key('stage-input')), 'hi');
      await tester.pump();
      expect(sendColor(), AppColors.primary);
      await tester.tap(find.byKey(const Key('send')));
      expect(sent, 1);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, 2);
      expect(controller.text, 'hi');
    });

    testWidgets('disabled: nothing can be sent or uploaded', (tester) async {
      var uploads = 0;
      await pumpBar(tester, enabled: false, onUpload: () => uploads++, onVoice: () {});
      await tester.tap(find.byKey(const Key('upload')));
      expect(uploads, 0);
      expect(tester.widget<TextField>(find.byKey(const Key('stage-input'))).enabled, isFalse);
      expect(tester.widget<IconButton>(find.byKey(const Key('voice-mode'))).onPressed, isNull);
    });

    testWidgets('file chips sit above the pill; ✕ removes, a busy chip shows a spinner', (
      tester,
    ) async {
      var removed = 0;
      await pumpBar(
        tester,
        onUpload: () {},
        attachments: [
          InputAttachment(id: 3, label: 'course.pdf', onRemove: () => removed++),
          const InputAttachment(id: 'up', label: 'uploading.md', busy: true),
        ],
      );
      expect(find.text('course.pdf'), findsOneWidget);
      expect(find.byKey(const Key('attachment-remove-3')), findsOneWidget);
      expect(find.byKey(const Key('attachment-remove-up')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(const Key('attachment-3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('stage-input'))).dy),
      );
      await tester.tap(find.byKey(const Key('attachment-remove-3')));
      expect(removed, 1);
    });

    testWidgets('an error line appears above the field', (tester) async {
      await pumpBar(tester, error: "Can't reach the server.");
      expect(find.byKey(const Key('input-error')), findsOneWidget);
      expect(find.text("Can't reach the server."), findsOneWidget);
    });

    testWidgets('voice mode replaces the whole bar by a waveform with no buttons', (tester) async {
      final voice = FakeVoiceService();
      final mode = VoiceModeController(
        voice: voice,
        onHeard: (_) async => (speak: null, keepGoing: true),
      );
      addTearDown(mode.dispose);
      await pumpBar(tester, onUpload: () {}, onVoice: () {}, mode: mode);
      expect(find.byKey(const Key('voice-wave-row')), findsNothing);

      await mode.start();
      await tester.pump();
      expect(find.byKey(const Key('voice-wave-row')), findsOneWidget);
      expect(find.byType(VoiceWave), findsOneWidget);
      expect(find.byKey(const Key('stage-input')), findsNothing);
      expect(find.byKey(const Key('send')), findsNothing);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('Listening…'), findsOneWidget);
      expect(StageInputBar.statusOf(VoiceModeState.thinking), 'Thinking…');
      expect(StageInputBar.statusOf(VoiceModeState.speaking), 'Speaking…');

      await tester.tap(find.byKey(const Key('voice-wave-row')));
      await tester.pump();
      expect(mode.active, isFalse);
      expect(find.byKey(const Key('stage-input')), findsOneWidget);
    });
  });

  group('panels', () {
    testWidgets('AppPanel: white, radius 20, a 56 px title bar; the collapse button is optional', (
      tester,
    ) async {
      var folded = 0;
      await pumpApp(
        tester,
        SizedBox(
          width: 300,
          height: 400,
          child: AppPanel(
            title: 'My character',
            collapseKey: const Key('fold'),
            onCollapse: () => folded++,
            child: const Text('Body'),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppPanel), matching: find.byType(DecoratedBox)).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, AppColors.sidebar);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(decoration.border, isNull);
      expect(find.text('My character'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Body')).dy - tester.getTopLeft(find.byType(AppPanel)).dy,
        greaterThanOrEqualTo(56),
      );
      await tester.tap(find.byKey(const Key('fold')));
      expect(folded, 1);

      await pumpApp(
        tester,
        const SizedBox(
          width: 300,
          height: 200,
          child: AppPanel(title: 'Title', child: SizedBox()),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('PanelRail: 56 px wide, the expand button and the title written sideways', (
      tester,
    ) async {
      var opened = 0;
      await pumpApp(
        tester,
        SizedBox(
          height: 400,
          child: PanelRail(title: 'Chat', expandKey: const Key('open'), onExpand: () => opened++),
        ),
      );
      expect(tester.getSize(find.byType(PanelRail)).width, 56);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.byType(RotatedBox), findsOneWidget);
      await tester.tap(find.byKey(const Key('open')));
      expect(opened, 1);
    });

    testWidgets('StatusChip: soft fill, colored text, radius 8', (tester) async {
      await pumpApp(
        tester,
        const Column(
          children: [
            StatusChip.success('Passed'),
            StatusChip.danger('Failed'),
            StatusChip.primary('Ready'),
            StatusChip.neutral('Locked'),
          ],
        ),
      );
      Color textColor(String t) => tester.widget<Text>(find.text(t)).style!.color!;
      Color fill(String t) =>
          (tester
                      .widget<DecoratedBox>(
                        find.ancestor(of: find.text(t), matching: find.byType(DecoratedBox)).first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      expect([textColor('Passed'), fill('Passed')], [AppColors.success, AppColors.successSoft]);
      expect([textColor('Failed'), fill('Failed')], [AppColors.danger, AppColors.dangerSoft]);
      expect([textColor('Ready'), fill('Ready')], [AppColors.primary, AppColors.primarySoft]);
      expect(
        [textColor('Locked'), fill('Locked')],
        [AppColors.textSecondary, AppColors.surfaceHigh],
      );
      final shape =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(of: find.text('Passed'), matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(shape.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('GradientText fills the glyphs with the Gemini gradient', (tester) async {
      await pumpApp(tester, const GradientText('hi'));
      final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mask.blendMode, BlendMode.srcIn);
      expect(mask.shaderCallback(const Rect.fromLTWH(0, 0, 100, 30)), isNotNull);
      expect(find.text('hi'), findsOneWidget);
    });
  });

  group('small helpers', () {
    test('displayDomain drops www. and falls back to the text', () {
      expect(displayDomain('https://www.khanacademy.org/math'), 'khanacademy.org');
      expect(displayDomain('https://ko.wikipedia.org/wiki/x'), 'ko.wikipedia.org');
      expect(displayDomain('  https://youtu.be/abc '), 'youtu.be');
      expect(displayDomain('not a url'), 'not a url');
    });

    test('courseNameOf is the root node\'s title', () async {
      final api = FakeApiClient(latency: Duration.zero);
      final map = await api.generateCourse(const GenerateRequest(topic: 'Math'));
      expect(courseNameOf(map), 'High School Math');
      expect(map.course.title, 'Math');
      expect(
        courseNameOf(CourseMap(course: map.course, nodes: const [], edges: const [])),
        'Math',
      );
    });
  });

  group('test helpers', () {
    test('seededFakeApi has the math course with only the root available', () async {
      final api = await seededFakeApi();
      expect(api.latency, Duration.zero);
      final skills = await api.listSkills();
      expect(skills, hasLength(12));
      expect(skills.where((s) => s.isAvailable).map((s) => s.title), ['High School Math']);
    });

    test('longAnswer is long enough to pass without a challenge', () {
      expect(longAnswer.runes.length, greaterThanOrEqualTo(160));
      expect(longAnswer.contains("don't know"), isFalse);
      expect(shortAnswer.contains('not sure'), isTrue);
    });

    testWidgets('buildTestApp provides the API and AppState', (tester) async {
      final api = await seededFakeApi();
      final state = AppState();
      late BuildContext captured;
      await tester.pumpWidget(
        buildTestApp(
          api: api,
          state: state,
          child: Builder(
            builder: (context) {
              captured = context;
              return const Text('screen under test');
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('screen under test'), findsOneWidget);
      expect(captured.read<SelfInfinityApi>(), same(api));
      expect(captured.read<AppState>(), same(state));
    });

    testWidgets('buildTestApp turns navigation into route placeholders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => context.go(AppRoutes.audit(5)),
                  child: const Text('audit'),
                ),
                TextButton(onPressed: () => context.go(AppRoutes.map), child: const Text('map')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('audit'));
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/5/audit'), findsOneWidget);
    });

    testWidgets('openExternalUrl says so when a link cannot be opened', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        buildTestApp(
          child: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openExternalUrl(captured, 'javascript:alert(1)'); // never launched
      await tester.pump();
      expect(find.text("Couldn't open the link."), findsOneWidget);
    });

    testWidgets('the theme in the test app is the light theme', (tester) async {
      await tester.pumpWidget(buildTestApp(child: const Text('x')));
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.brightness, Brightness.light);
      expect(app.theme!.scaffoldBackgroundColor, AppTheme.light().scaffoldBackgroundColor);
    });
  });
}
