# /// script
# requires-python = ">=3.15"
# dependencies = ["resvg-py", "pillow"]
# ///
"""Renders the logo's SVG sources in Media/Logo/ to the PNGs and the in-game icon.

    uv run --script tools/render_logo.py

- Media/Logo/logo.svg          -> Media/Logo/logo-400.png, Media/Logo/logo-1024.png (CurseForge project logo)
- Media/Logo/logo-wordmark.svg -> Media/Logo/logo-wordmark.png (1600 x 400 banner)
- Media/Logo/logo-icon.svg     -> Media/LogoIcon.tga (64 x 64, 32-bit, uncompressed: the TOC icon, minimap button,
                                  Addon Compartment and the window's emblem; UI/Art.lua `launcher`)

The SVGs are the sources: edit them, then run this. Media/Logo/ stays out of the release zip (.pkgmeta); only the TGA
ships. Everything here is part of Dungeon Planner under its MIT licence (docs/LIBRARIES.md, "Logo").
"""

import io
from pathlib import Path

import resvg_py
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Media" / "Logo"


def render(svg: Path, width: int, height: int) -> Image.Image:
    png = resvg_py.svg_to_bytes(svg_string=svg.read_text(encoding="utf-8"), width=width, height=height)
    return Image.open(io.BytesIO(bytes(png))).convert("RGBA")


def main() -> None:
    outputs = [
        (LOGO / "logo.svg", 400, 400, LOGO / "logo-400.png"),
        (LOGO / "logo.svg", 1024, 1024, LOGO / "logo-1024.png"),
        (LOGO / "logo-wordmark.svg", 1600, 400, LOGO / "logo-wordmark.png"),
    ]
    for svg, w, h, out in outputs:
        render(svg, w, h).save(out, optimize=True)
        print(out.relative_to(ROOT))
    icon = ROOT / "Media" / "LogoIcon.tga"
    write_tga(render(LOGO / "logo-icon.svg", 64, 64), icon)
    print(icon.relative_to(ROOT))


def write_tga(im: Image.Image, path: Path) -> None:
    """The same TGA layout as tools/gen_textures.lua: 32-bit BGRA, uncompressed, rows top-down, no footer."""
    w, h = im.size
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 0x28])
    path.write_bytes(header + im.tobytes("raw", "BGRA"))


if __name__ == "__main__":
    main()
