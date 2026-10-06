"""Turns the front page's robot video into the frames and the orb track the page scrolls through.

    pip install pillow numpy          (and ffmpeg on PATH)
    python app/tool/landing_frames.py robot.mp4 [--frames 120] [--crop iw:ih-88:0:0] [--mirror]

The video: a robot holding a glowing golden orb in its palm, then raising it while the camera
rises to look down, the orb ending big in frame (docs/DESIGN.md, front page). The page shows frame
`round(progress * (frames - 1))` as you scroll, and draws the life tree over the orb, so this
script also finds the orb in every frame: the warm, bright pixels (the background, the robot and
its reflections are cool or dark), their centre and their size.

Writes app/assets/landing/frames/{wide,narrow}_NNN.webp and app/assets/landing/frames/track.json
(flat: pubspec.yaml lists the folder, and Flutter does not take subfolders):
    {"frames": 96, "aspect": 1.777, "background": "#eeecf5", "orb": [[x, y, r] | null, ...]}
x as a fraction of the width, y and r of the height; null where no orb was found.

The page around the picture is AppColors.surface (warm paper), so every frame is tinted until the
video's background (a patch of the first frame's top edge) is exactly that colour: one gain per
channel, which barely touches the dark robot. "background" records it.
"""

import argparse
import json
import pathlib
import subprocess
import tempfile

import numpy as np
from PIL import Image

APP = pathlib.Path(__file__).resolve().parent.parent
OUT = APP / "assets/landing/frames"
SIZES = {"wide": 1920, "narrow": 960}
PAPER = (0xFB, 0xFB, 0xF8)  # AppColors.surface (lib/theme/tokens.dart)


def extract(video: pathlib.Path, frames: int, into: pathlib.Path, crop: str | None, mirror: bool) -> list[pathlib.Path]:
    duration = float(
        subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(video)]
        )
    )
    filters = [f"fps={frames / duration}"]
    if crop:
        filters.append(f"crop={crop}")
    if mirror:
        filters.append("hflip")
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf", ",".join(filters), str(into / "%03d.png")])
    return sorted(into.glob("*.png"))[:frames]


def find_orb(image: Image.Image) -> tuple[float, float, float] | None:
    """Centre and radius (fractions) of the golden glow, or None."""
    small = image.convert("RGB").resize((480, round(480 * image.height / image.width)))
    a = np.asarray(small).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    warm = (r > 170) & (g > 120) & (r - b > 70) & (g - b > 30)
    if warm.sum() < 12:
        return None
    ys, xs = np.nonzero(warm)
    # The core, not the halo: pixels within twice the median distance of the median point.
    cx, cy = np.median(xs), np.median(ys)
    d = np.hypot(xs - cx, ys - cy)
    core = d <= 2 * max(np.median(d), 1)
    cx, cy = xs[core].mean(), ys[core].mean()
    radius = np.sqrt(core.sum() / np.pi)
    h, w = warm.shape
    return (round(cx / w, 4), round(cy / h, 4), round(radius / h, 4))


def smooth(track: list, window: int = 2) -> list:
    out = []
    for i, point in enumerate(track):
        if point is None:
            out.append(None)
            continue
        near = [p for p in track[max(0, i - window) : i + window + 1] if p is not None]
        out.append([round(sum(p[k] for p in near) / len(near), 4) for k in range(3)])
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=pathlib.Path)
    parser.add_argument("--frames", type=int, default=120)
    parser.add_argument("--crop", help="ffmpeg crop=w:h:x:y, e.g. iw:ih-88:0:0 to drop a bottom strip")
    parser.add_argument("--mirror", action="store_true", help="flip left-right (the orb should end away from the words)")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        pngs = extract(args.video, args.frames, pathlib.Path(tmp), args.crop, args.mirror)
        OUT.mkdir(parents=True, exist_ok=True)
        for old in [*OUT.glob("*.webp"), OUT / "track.json"]:
            old.unlink(missing_ok=True)
        track = []
        first = Image.open(pngs[0]).convert("RGB")
        # A patch of the top edge, clear of the corner, where generators put their labels.
        w, h = first.size
        corner = first.crop((w // 12, 0, w // 6, h // 25)).resize((1, 1)).getpixel((0, 0))
        gain = np.array(PAPER) / np.maximum(np.array(corner), 1)
        for i, png in enumerate(pngs):
            image = Image.open(png).convert("RGB")
            track.append(find_orb(image))
            image = Image.fromarray(np.clip(np.asarray(image) * gain, 0, 255).astype(np.uint8))
            for name, width in SIZES.items():
                width = min(width, image.width)  # never upscale
                height = round(width * image.height / image.width)
                image.convert("RGB").resize((width, height), Image.LANCZOS).save(
                    OUT / f"{name}_{i:03d}.webp", quality=80, method=6
                )
        aspect = image.width / image.height
    data = {
        "frames": len(pngs),
        "aspect": round(aspect, 4),
        "background": "#%02x%02x%02x" % PAPER,
        "source_background": "#%02x%02x%02x" % corner,
        "orb": smooth(track),
    }
    (OUT / "track.json").write_text(json.dumps(data))
    found = sum(p is not None for p in track)
    size = sum(f.stat().st_size for f in OUT.rglob("*.webp")) // 1024
    print(f"{len(pngs)} frames, orb found in {found}, {size} KB of frames -> {OUT.relative_to(APP)}")


if __name__ == "__main__":
    main()
