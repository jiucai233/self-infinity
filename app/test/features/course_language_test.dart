// Switching the app's language from the ◎ menu puts the courses into it in the background
// (POST /courses/translate) and reloads them; a failure only shows a snackbar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TranslateSpy extends FakeApiClient {
  _TranslateSpy() : super(latency: Duration.zero);

  final List<String> languages = [];

  @override
  Future<CourseTranslation> translateCourses(String language) {
    languages.add(language);
    return super.translateCourses(language);
  }
}

Future<void> _pickLanguage(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(const Key('settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settings-language-$code')));
  // Loading the CJK fonts is real I/O.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('switching the language translates the courses and reloads them', (tester) async {
    desktop(tester);
    final api = _TranslateSpy();
    await api.generateCourse(const GenerateRequest(topic: 'Math'));
    final state = AppState();
    await tester.pumpWidget(buildTestApp(child: const HomeScene(), api: api, state: state));
    await tester.pumpAndSettle();
    final before = state.dataRevision;

    await _pickLanguage(tester, 'zh');

    expect(LocaleController.current, AppLanguage.zh);
    expect(api.languages, ['zh']);
    expect(state.dataRevision, greaterThan(before));
    expect(find.byType(SnackBar), findsNothing);

    // Picking the language it already is asks nothing.
    await _pickLanguage(tester, 'zh');
    expect(api.languages, ['zh']);
  });

  testWidgets('a failed translation only says so in a snackbar', (tester) async {
    desktop(tester);
    final api = _TranslateSpy()..failNext(method: 'translateCourses', statusCode: 502);
    await tester.pumpWidget(buildTestApp(child: const HomeScene(), api: api));
    await tester.pumpAndSettle();

    await _pickLanguage(tester, 'ko');

    expect(LocaleController.current, AppLanguage.ko);
    expect(api.languages, ['ko']);
    expect(find.text('코스를 번역하지 못했어요. 지금은 원래 언어로 남아 있어요.'), findsOneWidget);
  });

  tearDown(() => LocaleController.current = AppLanguage.en);
}
