"""Turns screenshots of the app into the real screens the front page shows beside each chapter.

    pip install pillow
    cd app
    for lang in en ko zh; do
      SHOTS_DIR=/tmp/shots/$lang SHOTS_LANG=$lang flutter test test/screenshots_test.dart \
        --name 'scene (2 outline|4-1 asking|4-1 lesson card|2 map) \\('
    done
    python tool/landing_usage.py /tmp/shots

The shots come from test/screenshots_test.dart (the app itself, on the fake demo data), one folder
per language. Each chapter takes one scene, at both sizes:

    learn     2-outline   a course turned into its layered map of ideas
    prove     41-asking   the Auditor asking
    remember  41-lesson   a miss turned into a lesson card
    grow      2-map       the life tree

Writes app/assets/landing/usage_<chapter>_<wide|narrow>_<lang>.webp (flat: pubspec.yaml lists the
folder, and Flutter does not take subfolders). A language without its shots is skipped; the page
then shows the English ones, and an empty frame when there are none at all.
"""

import argparse
import pathlib

from PIL import Image

APP = pathlib.Path(__file__).resolve().parent.parent
OUT = APP / "assets/landing"
CHAPTERS = {"learn": "2-outline", "prove": "41-asking", "remember": "41-lesson", "grow": "2-map"}
# Wide shots (1440x900) are shown about 540 px wide, twice that on a retina screen; phone shots
# (390x844) about 80 px wide, so they stay as they are.
WIDTH = {"wide": 1080, "narrow": 390}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("shots", type=pathlib.Path, help="a folder with one folder of shots per language (en, ko, zh)")
    parser.add_argument("--quality", type=int, default=82)
    args = parser.parse_args()

    written = 0
    for lang in ["en", "ko", "zh"]:
        folder = args.shots / lang
        if not folder.is_dir():
            print(f"{lang}: no {folder}, skipped")
            continue
        for chapter, scene in CHAPTERS.items():
            for layout, width in WIDTH.items():
                source = folder / f"{scene}-{layout}.png"
                if not source.exists():
                    print(f"{lang}: no {source.name}, skipped")
                    continue
                image = Image.open(source).convert("RGB")
                if image.width > width:
                    image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
                target = OUT / f"usage_{chapter}_{layout}_{lang}.webp"
                image.save(target, "WEBP", quality=args.quality, method=6)
                written += 1
                print(f"{target.relative_to(APP)}  {image.width}x{image.height}  {target.stat().st_size // 1024} KB")
    print(f"{written} screens written")


if __name__ == "__main__":
    main()
