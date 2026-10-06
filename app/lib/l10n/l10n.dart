/// Localized strings: `context.l10n.someKey`. The strings live in
/// `lib/l10n/app_{en,zh,ko}.arb`; `flutter gen-l10n` (run by `flutter pub get`)
/// turns them into [AppLocalizations].
library;

import 'package:flutter/widgets.dart';

import 'app_language.dart';
import 'app_localizations.dart';

export 'app_language.dart';
export 'app_localizations.dart';

extension L10nContext on BuildContext {
  /// The strings of the app's current language — English when there is no
  /// `Localizations` above (a bare `MaterialApp` in a test).
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _english;
}

final AppLocalizations _english = lookupAppLocalizations(const Locale('en'));

/// The strings of the app's current language, for code without a
/// `BuildContext` (services, controllers). Read it when the text is made, not
/// once up front: the language can change while the app runs.
AppLocalizations get l10nNow => lookupAppLocalizations(LocaleController.current.locale);
