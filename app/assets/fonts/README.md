# Bundled fonts

All SIL Open Font License 1.1. Built by `app/tool/build_fonts.py` (sources and steps at its top).

| file | family in the app | from | when it loads |
|---|---|---|---|
| `InstrumentSerif-*.ttf` | `InstrumentSerif` | Instrument Serif, unmodified (`OFL.txt`) | always: display serif |
| `InfinitySans-{Regular,Medium,SemiBold}.ttf` | `InfinitySans` | Pretendard 1.3.9, Latin subset (`OFL-Pretendard.txt`) | always: every other text |
| `cjk/InfinitySansKR-{Regular,SemiBold}.ttf` | `InfinitySansKR` | Pretendard 1.3.9, 2350 common Hangul syllables | Korean picked |
| `cjk/NotoSansSC-Regular.ttf` | `Noto Sans SC` | Noto Sans SC, GB2312 (6763 Hanzi) (`OFL-Noto.txt`) | Chinese picked |
| `cjk/NotoSansSC-SemiBold.ttf` | `Noto Sans SC` | Noto Sans SC, 3755 common Hanzi | Chinese picked |
| `cjk/NotoSerifSC-Medium.ttf` | `Noto Serif SC` | Noto Serif SC, 3755 common Hanzi | Chinese picked: under the display serif |
| `cjk/NotoSerifKR-Medium.ttf` | `Noto Serif KR` | Noto Serif KR, 2350 common Hangul syllables | Korean picked: under the display serif |

Every subset also has every character of the app's own Chinese and Korean strings, so UI text
never falls back; a rarer character in user text falls back to the platform's CJK font.

- **Why Pretendard**: its Latin is Inter-like (clean, made for UI) and its Hangul is the same
  design, so English and Korean read as one typeface.
- **Why renamed**: Pretendard's license reserves the name "Pretendard" for unmodified fonts. A
  subset is a modified version, so these files are called Infinity Sans; the copyright notice
  inside still credits the original.
- **Why `cjk/` is not under `fonts:`** in pubspec.yaml: the web app downloads every `fonts:`
  entry at startup. These are megabytes, so they are plain assets that
  `lib/theme/font_loader.dart` loads when their language is picked.
