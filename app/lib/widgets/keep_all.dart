/// Korean line breaking by words, like CSS `word-break: keep-all`.
library;

/// U+2060 WORD JOINER: no line break on either side, and nothing drawn.
///
/// Infinity Sans maps it to a zero-width glyph, and Infinity Sans is in every
/// fallback chain (the serif's too), so it never shows as a box. U+FEFF, the
/// older zero-width no-break space, is in none of the bundled fonts.
const String wordJoiner = '⁠';

/// [s] with a [wordJoiner] between each Hangul letter and the letter next to
/// it, so a line breaks only at spaces (`증명하고,` stays whole). Flutter
/// breaks Korean between any two syllables, and has no `keep-all`.
///
/// Text without Hangul comes back unchanged (the same string), so English and
/// Chinese are untouched. Dashes and slashes stay places to break.
String keepAll(String s) {
  if (!_hangul.hasMatch(s)) return s;
  final out = StringBuffer();
  int? previous;
  for (final rune in s.runes) {
    if (previous != null && _joins(previous, rune)) out.write(wordJoiner);
    out.writeCharCode(rune);
    previous = rune;
  }
  return out.toString();
}

bool _joins(int a, int b) =>
    (_isHangul(a) || _isHangul(b)) && !_isBreak(a) && !_isBreak(b);

final RegExp _hangul = RegExp('[ᄀ-ᇿ㄰-㆏ꥠ-꥿가-힣ힰ-퟿]');

bool _isHangul(int c) =>
    (c >= 0xAC00 && c <= 0xD7A3) || // syllables
    (c >= 0x1100 && c <= 0x11FF) || // jamo
    (c >= 0x3130 && c <= 0x318F) || // compatibility jamo
    (c >= 0xA960 && c <= 0xA97F) || // jamo extended-A
    (c >= 0xD7B0 && c <= 0xD7FF); // jamo extended-B

/// Spaces (where a line should break), joiners already there, and the dashes
/// and slashes a line may break after.
bool _isBreak(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0xA0 ||
    c == 0x3000 ||
    (c >= 0x2000 && c <= 0x200D) || // en/em spaces, ZWSP, ZWNJ, ZWJ
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x2060 ||
    c == 0xFEFF ||
    c == 0x2013 || // –
    c == 0x2014 || // —
    c == 0x2D || // -
    c == 0x2F; // /
