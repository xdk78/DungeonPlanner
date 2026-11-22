# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
"""Turns the offline renderer's frame sequences into captioned, optimised GIFs for the README and CurseForge.

    uv run --script tools/make_gifs.py --png <dir with seq-*.png> --out docs/media [--only steps,route]
        [--spec tools/gif_sequences.json] [--width 720] [--max-mb 3]

The frames come from `lua tests/ui_dump.lua` (views named `seq-<name>-NN`, see tests/ui_views.lua) rendered by the
wow-ui-harness `render` command (AGENTS.md, "Seeing the UI"). For each sequence `<name>` the spec file
(tools/gif_sequences.json) gives the crop, the time per frame and one caption per frame; the GIF is written to
`<out>/<name>.gif`: cropped, scaled to --width (600 to 800 px reads well on GitHub and CurseForge), captioned in a band
along the bottom (the bundled Alegreya Sans, OFL), one shared palette for all frames. When a GIF is over --max-mb the
palette shrinks, then the width, until it fits.

This script is part of Dungeon Planner under its MIT licence. The images it makes are not: they are screenshots or renders
of the addon that include Blizzard Entertainment game art (the game's textures and map tiles, (c) Blizzard Entertainment),
and are shown for documentation only. Use the game's own map tiles; do not include Santiago Reyes' maps.
"""

import argparse
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "Media" / "Fonts" / "AlegreyaSans-Medium.ttf"
FRAME = re.compile(r"^seq-(?P<name>.+)-(?P<n>\d+)\.png$")


def find_sequences(png_dir: Path) -> dict[str, list[Path]]:
    """{name: [frame paths in order]} for every seq-<name>-NN.png in the folder."""
    found: dict[str, list[tuple[int, Path]]] = {}
    for path in png_dir.iterdir():
        m = FRAME.match(path.name)
        if m:
            found.setdefault(m["name"], []).append((int(m["n"]), path))
    return {name: [p for _, p in sorted(items)] for name, items in found.items()}


def caption_band(frame: Image.Image, text: str, index: int, total: int) -> Image.Image:
    """The frame with a dark band along the bottom: the caption on the left, "n/total" on the right."""
    width, height = frame.size
    size = max(14, round(width / 34))
    font = ImageFont.truetype(str(FONT), size)
    pad = round(size * 0.6)
    band = size + pad * 2
    out = Image.new("RGB", (width, height + band), (20, 16, 12))
    out.paste(frame, (0, 0))
    draw = ImageDraw.Draw(out)
    draw.line([(0, height), (width, height)], fill=(143, 112, 40), width=2)
    draw.text((pad, height + pad - size * 0.1), text, font=font, fill=(235, 220, 170))
    count = f"{index}/{total}"
    draw.text((width - pad - draw.textlength(count, font=font), height + pad - size * 0.1), count, font=font,
              fill=(150, 130, 90))
    return out


def prepare(paths: list[Path], spec: dict, width: int) -> list[Image.Image]:
    crop = tuple(spec["crop"]) if spec.get("crop") else None
    captions = spec.get("captions", [])
    frames = []
    for i, path in enumerate(paths):
        img = Image.open(path).convert("RGB")
        if crop:
            img = img.crop(crop)
        ratio = width / img.width
        img = img.resize((width, round(img.height * ratio)), Image.LANCZOS)
        frames.append(caption_band(img, captions[i] if i < len(captions) else "", i + 1, len(paths)))
    return frames


def encode(frames: list[Image.Image], delays: list[int], colors: int) -> bytes:
    """One palette for the whole sequence (made from all frames), no dithering: small and steady between frames."""
    sheet = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        sheet.paste(f, (0, i * frames[0].height))
    palette = sheet.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    paletted = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    buf = io.BytesIO()
    paletted[0].save(buf, format="GIF", save_all=True, append_images=paletted[1:], duration=delays, loop=0,
                     optimize=True, disposal=1)
    return buf.getvalue()


def make(name: str, paths: list[Path], spec: dict, width: int, max_bytes: int) -> tuple[bytes, int, int]:
    delay = int(spec.get("delay", 1400))
    delays = [delay] * len(paths)
    delays[-1] = int(spec.get("last_delay", delay * 2)) # the end rests a little longer before it loops
    floor = min(480, width)  # never narrower than 480 px, or than the width asked for when that is smaller
    for colors in (256, 128, 64):
        w = width
        while True:
            data = encode(prepare(paths, spec, w), delays, colors)
            if len(data) <= max_bytes:
                return data, w, colors
            if w <= floor:
                break
            w = max(floor, round(w * 0.9))
    raise SystemExit(f"{name}: no size under {max_bytes} bytes down to {floor} px and 64 colours")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--png", required=True, type=Path, help="folder with the rendered seq-<name>-NN.png frames")
    ap.add_argument("--out", required=True, type=Path, help="where the GIFs go (docs/media)")
    ap.add_argument("--spec", type=Path, default=ROOT / "tools" / "gif_sequences.json")
    ap.add_argument("--only", help="comma-separated sequence names")
    ap.add_argument("--width", type=int, default=720, help="GIF width in px before the caption band (default 720)")
    ap.add_argument("--max-mb", type=float, default=3.0)
    args = ap.parse_args()

    specs = json.loads(args.spec.read_text(encoding="utf-8"))
    sequences = find_sequences(args.png)
    names = args.only.split(",") if args.only else sorted(specs)
    args.out.mkdir(parents=True, exist_ok=True)
    for name in names:
        if name not in sequences:
            sys.exit(f"{name}: no seq-{name}-NN.png frames in {args.png}")
        if name not in specs:
            sys.exit(f"{name}: not in {args.spec}")
        paths = sequences[name]
        captions = specs[name].get("captions", [])
        if len(captions) != len(paths):
            sys.exit(f"{name}: {len(paths)} frames but {len(captions)} captions in {args.spec}")
        data, w, colors = make(name, paths, specs[name], args.width, int(args.max_mb * 1024 * 1024))
        target = args.out / f"{name}.gif"
        target.write_bytes(data)
        print(f"{target}: {len(paths)} frames, {w} px wide, {colors} colours, {len(data) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
