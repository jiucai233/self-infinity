// Languages: English by default, Chinese and Korean from the ◎ menu or the front page; every
// string in all three; the choice is remembered and sent to the backend.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_infinity/api/http_api.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)[,}]').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => LocaleController.current = AppLanguage.en);

  test('every English string has a Chinese and a Korean one with the same placeholders', () {
    final en = _arb('en');
    final keys = en.keys.where((k) => !k.startsWith('@'));
    for (final lang in ['zh', 'ko']) {
      final other = _arb(lang);
      expect(other.keys.where((k) => !k.startsWith('@')).toSet(), keys.toSet(), reason: lang);
      for (final key in keys) {
        final text = other[key] as String;
        expect(text.trim(), isNotEmpty, reason: '$lang $key');
        expect(_placeholders(text), _placeholders(en[key] as String), reason: '$lang $key');
      }
    }
  });

  test('the languages and what they map to', () {
    expect(AppLanguage.values.map((l) => l.code), ['en', 'zh', 'ko']);
    expect(AppLanguage.fromCode('ko'), AppLanguage.ko);
    expect(AppLanguage.fromCode('fr'), AppLanguage.en);
    expect(AppLanguage.fromCode(null), AppLanguage.en);
    expect(AppLanguage.zh.speechLocale, 'zh_CN');
  });

  test('English the first time; the picked language is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await LocaleController.load()).language, AppLanguage.en);

    await LocaleController().setLanguage(AppLanguage.ko);
    expect((await LocaleController.load()).language, AppLanguage.ko);
    expect(LocaleController.current, AppLanguage.ko);
  });

  test('every request says the app language, so the backend answers in it', () async {
    final seen = <String?>[];
    final client = MockClient((request) async {
      seen.add(request.headers['Accept-Language']);
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });
    var language = 'zh';
    final api = HttpApi(baseUrl: 'http://x/api', client: client, language: () => language);

    await api.listCourses();
    language = 'ko';
    await api.listCourses();

    expect(seen, ['zh', 'ko']);
  });

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the ◎ menu switches the whole app to Chinese', (tester) async {
    SharedPreferences.setMockInitialValues({});
    desktop(tester);
    await tester.pumpWidget(buildTestApp(child: const HomeScene()));
    await tester.pumpAndSettle();
    expect(find.text('My character'), findsWidgets);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-language-zh')));
    // Loading the Chinese fonts is real I/O.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();

    expect(LocaleController.current, AppLanguage.zh);
    expect(find.text('我的角色'), findsWidgets);
    expect(find.text('今天学点什么？'), findsOneWidget);
    expect(find.text('My character'), findsNothing);
  });

  testWidgets('a Korean app shows Korean strings', (tester) async {
    desktop(tester);
    await tester.pumpWidget(buildTestApp(child: const HomeScene(), language: AppLanguage.ko));
    await tester.pumpAndSettle();

    expect(find.text('내 캐릭터'), findsWidgets);
    expect(find.text('오늘은 뭘 배워 볼까요?'), findsOneWidget);
  });
}
