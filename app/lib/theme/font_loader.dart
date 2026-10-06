import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import 'tokens.dart';

/// Loads the Chinese and Korean fonts when their language is picked.
///
/// They are megabytes (`assets/fonts/cjk/`, see `assets/fonts/README.md`), so
/// they are plain assets — not under `fonts:` in pubspec.yaml, which the web
/// app would download at startup for everyone. The Latin sans and the display
/// serif are small and always there.
///
/// Until a family is loaded, text that needs it falls back to the platform's
/// fonts (Flutter web fetches Noto on its own), so nothing ever goes missing;
/// the bundled ones just look right and match each other.
abstract final class AppFontLoader {
  static final Map<String, Future<void>> _loading = {};

  /// The families [language] uses, loaded once per app run. Never throws: a
  /// font that fails to load leaves the fallback in place.
  static Future<void> ensure(AppLanguage language) =>
      Future.wait([for (final family in AppFonts.bundledFor(language)) _load(family)]);

  static Future<void> _load(BundledFont family) => _loading[family.name] ??= () async {
    try {
      final loader = FontLoader(family.name);
      for (final file in family.files) {
        loader.addFont(rootBundle.load('assets/fonts/cjk/$file'));
      }
      await loader.load();
    } catch (e) {
      debugPrint('font ${family.name} not loaded: $e');
    }
  }();
}
