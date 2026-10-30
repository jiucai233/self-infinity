import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';

/// The moments she has a line of her own for.
enum CharacterSituation {
  /// A fail: she has not understood yet and asks for the explanation again.
  notYet,

  /// A pass: it clicked.
  gotIt,

  /// After reading back the user's own identity sentence.
  closer,

  /// After reading back their main quest (no identity sentence).
  closerQuest,
}

/// Every line 大肥鱼 says in her own voice, in one place: what she says in
/// each [CharacterSituation], in the app's language. A character with another
/// voice (a later agent profile) swaps this one class.
///
/// The lines are plain text; a widget shows Korean through `keepAll`.
@immutable
class CharacterLines {
  const CharacterLines(this._l);

  factory CharacterLines.of(BuildContext context) => CharacterLines(context.l10n);

  final AppLocalizations _l;

  String say(CharacterSituation situation) => switch (situation) {
    CharacterSituation.notYet => _l.lineNotYet,
    CharacterSituation.gotIt => _l.lineGotIt,
    CharacterSituation.closer => _l.lineCloser,
    CharacterSituation.closerQuest => _l.lineCloserQuest,
  };
}
