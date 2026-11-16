# /// script
# requires-python = "==3.12.*"
# dependencies = ["pillow", "numpy", "quicktex==0.3.1"]
# ///
# (Python 3.12: quicktex, the BC1 encoder, publishes wheels up to 3.12.)
"""Santiago Reyes' maps of WoW: Forever's new dungeons, as the textures the addon ships (Media/Maps/Reyes/).

The maps are Santiago Reyes' work, used with his permission and NOT under the project's MIT licence
(docs/licenses/SantiagoReyes-maps.md). This tool only converts his published files; it never changes a picture:
  1. Source: the files he publishes on https://sreyesmaps.com ("Descargar", 3000 x 2000 JPEG, the current version of
     each map, URLs below), fetched once into <work>/src (or taken from there when present).
  2. Scaled to 1024 x 683 (Lanczos), the size and crop of the same pictures in the Dungeon Journal and Forever Dungeon
     Routes addons, so plan coordinates (0..1 over that picture) mean the same place on both. Nothing is recoloured,
     cut away or painted over; his title and signature stay.
  3. Cut into three strips of 1024 x 256 (power-of-two textures the client accepts; the last strip holds rows 512-682
     and repeats row 682 below them, which is never drawn), each written as a BLP2 file with DXT1 (BC1) blocks and no
     mipmaps (the map canvas draws with linear filtering, which uses the top level only).

Data/ReyesMaps.lua lists the floors (the same names as below) and draws the strips as one 1024 x 683 picture.

    uv run --script tools/reyes_maps.py --work <scratch folder>            # writes Media/Maps/Reyes/*.blp
    uv run --script tools/reyes_maps.py --work <scratch folder> --check    # exit 1 when a file would change
"""

from __future__ import annotations

import argparse
import struct
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from quicktex import RawTexture
from quicktex.s3tc.bc1 import BC1Encoder

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Media" / "Maps" / "Reyes"
CDN = "https://cdn.sanity.io/images/uomo7a9a/production/"
WIDTH, HEIGHT, STRIP = 1024, 683, 256

# name -> published file (sreyesmaps.com map page, level), current version on 2026-11-16.
MAPS = {
    "HallOfThanes": "2f84b5f1122715547a7f9290e7da27436a4da8dd",  # salon-de-los-feudales-hall-of-thanes
    "RuinsOfLordaeron": "2905022d7097a9494239d686e79b919dbc942ada",  # las-ruinas-de-lordaeron
    "ExcavationSite": "3f554cf2a1aada5052f241b9660c826777c95bf5",  # sitio-de-excavacion-los-humedales, v2.0
    "DalaranCity": "9ba8b6ebf8a446f8b4faeaf2aeee2c367e297eb2",  # la-ciudad-de-dalaran, Ciudad de Dalaran (11/26)
    "DalaranUnderbelly": "59306714ec76d9bdd2c0a47661782ba05fe357ab",  # la-ciudad-de-dalaran, Cloacas de Dalaran
    "DrownedCity": "54dae4b3bd673a65eb8af548503f630f5ed1da12",  # la-ciudad-ahogada, Ciudad principal (11/26)
    "DrownedCityAtalByzal": "3ce86151f7ab78c323fc1e2c8471c9c3fc1e6f3d",  # la-ciudad-ahogada, Atal'Byzal
    "Kroldok": "8c76db457e5bef41effc364b3cd45fa3c86fb8ec",  # la-fortaleza-krol-dok
    "AlcazPrison": "7a9fa5d64f38cda71216ec3fab454e03726e9860",  # la-prision-de-alcaz, Pabellon Principal
    "AlcazPrisonMaxSecurity": "faddb79c0a9aeb39a738d1068ce8697d31a221fd",  # la-prision-de-alcaz, Maxima Seguridad
    "BlackmawGrove": "fb4ddf717d234cf500d6a2bc1809d6e58a5e0e4a",  # bastion-faucenegra, Arboleda Faucenegra
    "BlackmawFesteringGrotto": "67f609b77b77a11a8976d8fe8dac0bea9aa26f9e",  # Gruta Pestilente
    "BlackmawFallenGrove": "2ba0a3150041284c0c4d71a3915d2b0a0f5a9351",  # Profundidades de la Arboleda Caida
    "BlackmawBurrow": "b5ff9320e043494f734e8603edf6f853a47adc31",  # Profundidades de la Madriguera
    "BlackmawElders": "0a603b09c528fad4b4578693a60ed688130a71dc",  # Profundidades de los Ancianos
    "BlackmawForbiddenMagic": "98ac334759bdf1cdac418aa070cb9e2f244cd529",  # Profundidades de la Magia Prohibida
    "ShapersTerrace": "c43841722371699b3b8a20d35399695b7fe827b3",  # bancal-del-creador-shaper-s-terrace (11/26)
    "ShapersTerracePrismaticTalus": "2a0a3ca0152df6123072a21a992033313dcdbaab",  # Talus prismatico
}


def source(work: Path, name: str) -> Image.Image:
    path = work / "src" / (MAPS[name] + "-3000x2000.jpg")
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(
            CDN + path.name, headers={"User-Agent": "map-converter"}
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            path.write_bytes(r.read())
    return Image.open(path).convert("RGB")


def blp2_dxt1(img: Image.Image) -> bytes:
    """One BLP2 file: DXT1 (BC1) without alpha, one mip level."""
    w, h = img.size
    enc = BC1Encoder(level=18, color_mode=BC1Encoder.ColorMode.FourColor)
    data = enc.encode(
        RawTexture.frombytes(img.convert("RGBA").tobytes(), w, h)
    ).tobytes()
    header = (
        b"BLP2" + struct.pack("<I", 1) + bytes([2, 0, 0, 0]) + struct.pack("<II", w, h)
    )
    offsets = [0] * 16
    sizes = [0] * 16
    offsets[0] = len(header) + 16 * 4 * 2 + 256 * 4
    sizes[0] = len(data)
    return (
        header
        + struct.pack("<16I", *offsets)
        + struct.pack("<16I", *sizes)
        + bytes(256 * 4)
        + data
    )


def strips(img: Image.Image) -> list[Image.Image]:
    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
    a = np.asarray(img)
    rows = -(-HEIGHT // STRIP) * STRIP
    pad = np.concatenate([a, np.repeat(a[-1:], rows - HEIGHT, axis=0)], axis=0)
    return [Image.fromarray(pad[i : i + STRIP]) for i in range(0, rows, STRIP)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--work",
        type=Path,
        required=True,
        help="scratch folder (keeps the downloaded sources)",
    )
    ap.add_argument(
        "--check", action="store_true", help="exit 1 when a written file would differ"
    )
    args = ap.parse_args(argv)
    OUT.mkdir(parents=True, exist_ok=True)
    changed, total = [], 0
    for name in MAPS:
        for i, part in enumerate(strips(source(args.work, name)), 1):
            data = blp2_dxt1(part)
            path = OUT / f"{name}{i}.blp"
            total += len(data)
            if not path.exists() or path.read_bytes() != data:
                changed.append(path.name)
                if not args.check:
                    path.write_bytes(data)
    print(
        f"{len(MAPS)} maps, {3 * len(MAPS)} files, {total / 1024 / 1024:.2f} MiB; changed: {len(changed)}"
    )
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    sys.exit(main())
