"""Builds the bundled fonts in app/assets/fonts/ (see its README.md).

    cd <folder with the sources below>
    pip install fonttools brotli
    python <repo>/app/tool/build_fonts.py

Sources (all SIL Open Font License), downloaded into the current folder:
    PretendardVariable.ttf  github.com/orioncactus/pretendard v1.3.9,
                            packages/pretendard/dist/public/variable/
    NotoSansSC-VF.ttf       github.com/google/fonts ofl/notosanssc/NotoSansSC[wght].ttf
    NotoSerifSC-VF.ttf      github.com/google/fonts ofl/notoserifsc/NotoSerifSC[wght].ttf
    NotoSerifKR-VF.ttf      github.com/google/fonts ofl/notoserifkr/NotoSerifKR[wght].ttf

Every file is a static instance (Flutter matches weights by file, not by variation axis), cut
down to common characters plus every character of the app's Chinese and Korean strings
(lib/l10n/app_*.arb and backend/app/i18n.py), so UI text never falls back. Rerun it after
adding translations.
"""

import json
import pathlib

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

APP = pathlib.Path(__file__).resolve().parent.parent
OUT = APP / "assets/fonts"
CJK = OUT / "cjk"
BACKEND_TEXTS = (APP.parent / "backend/app/i18n.py").read_text()


def _decodable(rows: range, codec: str) -> set[int]:
    """Every character of a 94x94 double-byte code set in [rows]."""
    out = set()
    for hi in rows:
        for lo in range(0xA1, 0xFF):
            try:
                out.add(ord(bytes([hi, lo]).decode(codec)))
            except UnicodeDecodeError:
                pass
    return out


GB2312_LEVEL1 = _decodable(range(0xB0, 0xD8), "gb2312")  # 3755 most common Hanzi
GB2312 = _decodable(range(0xB0, 0xF8), "gb2312")  # + level 2: 6763
KSX1001_HANGUL = _decodable(range(0xB0, 0xC9), "euc-kr")  # 2350 common syllables
JAMO = set(range(0x3131, 0x318F))
CJK_PUNCT = set(range(0x3000, 0x3040)) | set(range(0xFF01, 0xFF5F))
LATIN = (
    set(range(0x20, 0x7F))
    | set(range(0xA0, 0x180))
    | set(range(0x2000, 0x2070))  # general punctuation: — “ ” … •
    | set(range(0x2190, 0x2200))  # arrows
    | {0x20AC, 0x2122, 0x2212, 0x2713, 0x2715, 0x25CF, 0x25CB, 0x25CE}
)


def _strings_of(lang: str) -> set[int]:
    arb = json.loads((APP / f"lib/l10n/app_{lang}.arb").read_text())
    text = "".join(v for k, v in arb.items() if not k.startswith("@")) + BACKEND_TEXTS
    return {ord(c) for c in text if ord(c) >= 0x2E80}


def build(src: str, out: pathlib.Path, weight: int, chars: set[int], rename: tuple[str, str] | None = None):
    font = TTFont(src)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": weight}, updateFontNames=True)
    options = subset.Options()
    options.layout_features = ["kern", "liga", "calt", "ccmp", "locl", "mark", "mkmk", "tnum", "case"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.hinting = False
    options.desubroutinize = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=sorted(chars))
    subsetter.subset(font)
    font["OS/2"].usWeightClass = weight  # what Flutter matches weights on within a family
    if rename:
        # OFL: a modified (subsetted) font may not keep the Reserved Font Name. The copyright
        # notice (name ID 0) keeps it, as the license asks.
        old, new = rename
        for record in font["name"].names:
            text = record.toUnicode()
            if record.nameID != 0 and old in text:
                record.string = text.replace(old, new.replace(" ", "") if record.nameID == 6 else new)
    font.save(out)
    print(f"{out.relative_to(APP)}: {out.stat().st_size // 1024} KB")


def main() -> None:
    CJK.mkdir(parents=True, exist_ok=True)
    zh, ko = _strings_of("zh"), _strings_of("ko")
    hangul = KSX1001_HANGUL | JAMO | CJK_PUNCT | {c for c in ko if 0xAC00 <= c <= 0xD7A3}
    han = GB2312 | CJK_PUNCT | zh
    han_common = GB2312_LEVEL1 | CJK_PUNCT | zh

    sans = ("Pretendard", "Infinity Sans")
    sans_kr = ("Pretendard", "Infinity Sans KR")
    for weight, name in ((400, "Regular"), (500, "Medium"), (600, "SemiBold")):
        build("PretendardVariable.ttf", OUT / f"InfinitySans-{name}.ttf", weight, LATIN, sans)
    build("PretendardVariable.ttf", CJK / "InfinitySansKR-Regular.ttf", 400, hangul, sans_kr)
    build("PretendardVariable.ttf", CJK / "InfinitySansKR-SemiBold.ttf", 600, hangul, sans_kr)
    # Body text gets all of GB2312; titles and the display serif the 3755 common characters.
    build("NotoSansSC-VF.ttf", CJK / "NotoSansSC-Regular.ttf", 400, han)
    build("NotoSansSC-VF.ttf", CJK / "NotoSansSC-SemiBold.ttf", 600, han_common)
    build("NotoSerifSC-VF.ttf", CJK / "NotoSerifSC-Medium.ttf", 500, han_common)
    build("NotoSerifKR-VF.ttf", CJK / "NotoSerifKR-Medium.ttf", 500, hangul)


if __name__ == "__main__":
    main()
