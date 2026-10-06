import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/font_loader.dart';

/// The languages of the app. English is the default; the user picks another
/// in the ◎ menu or on the front page, and the choice is remembered.
enum AppLanguage {
  en('en', 'English', 'en_US'),
  zh('zh', '中文', 'zh_CN'),
  ko('ko', '한국어', 'ko_KR');

  const AppLanguage(this.code, this.nativeName, this.speechLocale);

  /// BCP 47 language tag: the app locale, the `Accept-Language` header the
  /// backend writes its replies in, and the `intl` locale of dates.
  final String code;

  /// The name in the language itself, for the language menu.
  final String nativeName;

  /// Speech recognition and text-to-speech locale (`speech_to_text` style).
  final String speechLocale;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => en);
}

/// Which [AppLanguage] the app shows. The root widget listens to it and gives
/// every `MaterialApp` its locale and theme.
class LocaleController extends ChangeNotifier {
  LocaleController([AppLanguage language = AppLanguage.en]) : _language = language {
    _apply(language);
  }

  static const String _prefsKey = 'language';

  /// The language of the running app, for code that has no `BuildContext`:
  /// the request header of the API client and the speech services.
  static AppLanguage current = AppLanguage.en;

  AppLanguage _language;
  AppLanguage get language => _language;

  /// The remembered language (English the first time), with its fonts loaded.
  static Future<LocaleController> load() async {
    await initializeDateFormatting();
    var language = AppLanguage.en;
    try {
      final prefs = await SharedPreferences.getInstance();
      language = AppLanguage.fromCode(prefs.getString(_prefsKey));
    } catch (e) {
      // No storage (private window, blocked site data): English, not remembered.
      debugPrint('language preference unavailable: $e');
    }
    await AppFontLoader.ensure(language);
    return LocaleController(language);
  }

  /// Switches the app to [language] once its fonts are in, so the text does not
  /// flash in a fallback font first; then remembers it.
  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    await AppFontLoader.ensure(language);
    _language = language;
    _apply(language);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, language.code);
    } catch (e) {
      debugPrint('could not remember the language: $e');
    }
  }

  static void _apply(AppLanguage language) {
    current = language;
    Intl.defaultLocale = language.code;
  }
}
