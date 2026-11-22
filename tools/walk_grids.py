# /// script
# requires-python = "==3.12.*"
# dependencies = ["numpy==2.5.5", "pillow==13.0.0", "scipy==1.18.1", "scikit-image==0.26.0", "pycryptodome==4.5.0",
#                 "quicktex==0.3.1"]
# ///
# (Python 3.12 and quicktex: tools/reyes_maps.py, imported for its map list and sources, needs them. The versions are
# the ones Data/WalkData.lua was generated with: a newer resampling or skeleton can move a cell.)
"""Walkability grids for the route tool's "Snap to corridors": the table Data/WalkData.lua.

For each floor picture the addon can draw under a plan, a coarse grid (120 x 80 cells on a 3:2 map) of where one can
walk. Model/Walk.lua finds paths through it at runtime when a player clicks consecutive route stops. Only the grid
ships: two bits per cell (floor, rough), as run lengths; no picture, mask or other image goes into the repository.

Which pictures (docs/DATA-SOURCES.md, "Walkability grids"):
  1. The game's old dungeon map tiles of every classic floor (Data/GameFiles.lua), read from the game's local storage
     (CASC), as tools/route_paths.py reads them. Key "t:<tile name>".
  2. Santiago Reyes' maps of Forever's new dungeons, from his published files (tools/reyes_maps.py's sources, scaled the
     same way). He gave permission to use his World of Warcraft maps in Dungeon Planner; these grids, which only
     record where each map shows floor, are made from his maps under that permission and, like the maps, are not
     under the MIT licence (docs/licenses/SantiagoReyes-maps.md). Key "r:<file>". The Dungeon Journal and Forever Dungeon Routes
     addons draw these same pictures, so their floors use this grid; nothing is derived from those addons' files. His
     open outdoor maps get none (data-src/walkgrids.json says why).
  3. The game's minimap pictures, composed as Data/MinimapArtData.lua places them, for floors that have neither (the
     old Scholomance's four floors). Key "m:<instance key>:<floor>", in the minimap map's own space.

How: the walkable mask of tools/route_paths.py (lighter, less saturated floor; only what is drawn on the blank parchment
the old dungeon maps, and Santiago Reyes' maps, are painted on; the "overrides" of data-src/routes/*.json apply to the
pictures they were made on, data-src/walkgrids.json's settings over them), all its large parts kept; for the minimap
floors, what the pictures draw. A cell is floor when enough of it is floor, or when the floor's middle line (its
skeleton) runs through it, so corridors narrower than a cell stay open. A cell that is not floor but drawn (walls,
doors, outlines inside the dungeon) is rough: a path crosses it only at a high price, where the floor alone does not
connect two stops; the blank parchment is never crossed.

Usage (from the repository root):
  uv run --script tools/walk_grids.py --game "<World of Warcraft>/_forever_" --work <scratch folder> [--reyes <folder>]
  uv run --script tools/walk_grids.py ... --check                   # exit 1 when Data/WalkData.lua would change
                                                                    # (it is not written; the log and previews are)
  uv run --script tools/walk_grids.py ... --measure 80,100,120,140  # path quality and size per grid width
--reyes: the folder whose src/ holds Santiago Reyes' published files (tools/reyes_maps.py --work); default --work.
Keep the work folder outside the repository: it holds game art (masks and previews).
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage.morphology import skeletonize

sys.path.insert(0, str(Path(__file__).resolve().parent))
import minimap_art as mm  # noqa: E402
import reyes_maps  # noqa: E402
import route_paths as rp  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Data" / "WalkData.lua"
CONFIG = REPO / "data-src" / "walkgrids.json"
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"  # Model/Walk.lua
WIDTH = 120  # cells across; chosen with --measure (docs/DATA-SOURCES.md has the numbers)
FRACTION = 0.65  # a cell is floor when at least this share of it is floor (or the skeleton runs through it)
ROUGH_REACH = 3  # rough cells kept: within this many cells of the floor (a way through a wall up to 6 cells thick)

LUA_DUMP = r"""
local root = arg[1]
local ns = {}
function ns:NewModule(name) local m = {}; self[name] = m; return m end
assert(loadfile(root .. "/Data/ReyesMaps.lua"))("DungeonPlanner", ns)
assert(loadfile(root .. "/Data/MinimapArtData.lua"))("DungeonPlanner", ns)
local function enc(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t == "table" then
    local n, parts = #v, {}
    local isArray = n > 0 or next(v) == nil
    for k in pairs(v) do if type(k) ~= "number" or k > n or k < 1 then isArray = false end end
    if isArray then
      for i = 1, n do parts[i] = enc(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, x in pairs(v) do
      if type(x) ~= "function" then parts[#parts + 1] = enc(tostring(k)) .. ":" .. enc(x) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end
io.write(enc({ reyes = ns.ReyesMaps.DUNGEONS, minimap = ns.MinimapArtData }))
"""


def load_tables():
    out = subprocess.run(["lua", "-", str(REPO)], input=LUA_DUMP, capture_output=True, text=True, check=True, cwd=REPO,
                         encoding="utf-8").stdout
    return json.loads(out)


# ---------------------------------------------------------------------------------------------------------------------
# Which picture a plan floor is measured on (Data/Corridors.lua does the same at runtime).


def reyes_pick(reyes, plan, index):
    """ReyesMaps.Pick: the bundled floor for plan floor `index` (1-based), or None."""
    floor = plan["floors"][index - 1]
    if not floor.get("name") and floor.get("uiMapID"):
        return None
    floors = reyes.get(rp.strip_article(plan["instance"]["name"]))
    if not floors:
        return None
    want = rp.strip_article(floor.get("name") or "")
    if want:
        for f in floors:
            if any(rp.strip_article(n) == want for n in f.get("names", [])):
                return f
    i = rp.pick_floor(floor.get("name") or "", index, [(f["label"], f["file"]) for f in floors])
    return floors[i] if i is not None else None


def minimap_floor(minimap, key, index):
    floors = minimap.get(key)
    if isinstance(floors, list):
        return floors[index - 1] if index <= len(floors) else None
    return (floors or {}).get(str(index))


def floor_key(instances, reyes, minimap, plan, index):
    """The grid key of a plan floor: "t:<tiles>", "r:<file>", "m:<instance>:<floor>" or None."""
    floor = plan["floors"][index - 1]
    if not floor.get("name") and floor.get("uiMapID"):
        return None
    bases = rp.tile_bases(instances, plan)
    if index <= len(bases):
        return "t:" + bases[index - 1]
    f = reyes_pick(reyes, plan, index)
    if f:
        return "r:" + f["file"]
    key = rp.strip_article(plan["instance"]["name"])
    return f"m:{key}:{index}" if minimap_floor(minimap, key, index) else None


# ---------------------------------------------------------------------------------------------------------------------
# Pictures and masks.


def reyes_picture(reyes_work: Path, file: str) -> Image.Image:
    """Santiago Reyes' published map at the size the addon draws it (tools/reyes_maps.py strips())."""
    return reyes_maps.source(reyes_work, file).resize((reyes_maps.WIDTH, reyes_maps.HEIGHT), Image.LANCZOS)


def minimap_picture(world, d, px_per_yard):
    """The floor composed from its minimap pictures as Data/MinimapArt.lua draws it (RGBA, transparent outside)."""
    W, H = max(1, round(d["w"] * px_per_yard)), max(1, round(d["h"] * px_per_yard))
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for p in d["pieces"]:
        fid, x, y, w, h = p[:5]
        ulx, uly, llx, lly, urx, ury = p[5:11]
        im = world.image(fid)
        if im is None:
            continue
        tw, th = im.size
        x0, y0 = round(x * px_per_yard), round(y * px_per_yard)
        bw, bh = max(1, round(w * px_per_yard)), max(1, round(h * px_per_yard))
        # Output pixel (i, j) of the box -> texture (u, v) -> picture pixel; outside the picture stays transparent.
        coeffs = ((urx - ulx) * tw / bw, (llx - ulx) * tw / bh, ulx * tw,
                  (ury - uly) * th / bw, (lly - uly) * th / bh, uly * th)
        patch = im.transform((bw, bh), Image.Transform.AFFINE, coeffs, resample=Image.Resampling.BILINEAR,
                             fillcolor=(0, 0, 0, 0))
        canvas.alpha_composite(patch, (max(0, x0), max(0, y0)), (max(0, -x0), max(0, -y0)))
    return canvas


def minimap_mask(img: Image.Image):
    """What a building's minimap pictures draw is its floor: opaque and not black, cleaned like route_paths' masks."""
    a = np.asarray(img).astype(np.float32)
    drawn = (a[..., 3] > 128) & (a[..., :3].max(2) > 24)
    drawn = ndimage.binary_opening(drawn, rp._disk(1))
    drawn = ndimage.binary_closing(drawn, rp._disk(2), border_value=0)
    holes = ndimage.binary_fill_holes(drawn) & ~drawn
    lab, n = ndimage.label(holes)
    if n:
        sizes = ndimage.sum(holes, lab, range(1, n + 1))
        drawn |= np.isin(lab, 1 + np.flatnonzero(sizes <= 200))
    return drawn


def big_parts(mask, part):
    lab, n = ndimage.label(mask)
    if not n:
        return mask
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    return np.isin(lab, 1 + np.flatnonzero(sizes >= part))


def blocked_area(shape, opts):
    """The overrides' blocked rectangles, polygons and lines as a mask (they close the rough area too)."""
    out = np.zeros(shape, bool)
    rp._rects(out, opts.get("block_rects", []), True)
    rp._polys(out, opts.get("block_polys", []), True)
    rp._paths(out, opts.get("block_paths", []), True)
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Grids.


def grid_of(mask, region, width, fraction=FRACTION):
    """Two boolean (h, width) grids of a full-size mask: floor and rough. A cell is floor when `fraction` of it is
    floor, or when the floor's skeleton (thickened by a pixel, so it stays 4-connected across cells) runs through it.
    It is rough when it is not floor but at least half of it is drawn (region): walls, doors and room outlines inside
    the dungeon, which a path may cross at a high price where the floor alone does not connect two stops (as
    tools/route_paths.py does); never the blank parchment around."""
    H, W = mask.shape
    height = max(2, round(width * H / W))
    ys = np.linspace(0, H, height + 1).round().astype(int)
    xs = np.linspace(0, W, width + 1).round().astype(int)
    skel = ndimage.binary_dilation(skeletonize(mask), np.ones((3, 3), bool)) & mask
    floor = np.zeros((height, width), bool)
    rough = np.zeros((height, width), bool)
    for j in range(height):
        for i in range(width):
            cell = mask[ys[j] : ys[j + 1], xs[i] : xs[i + 1]]
            if not cell.size:
                continue
            if cell.mean() >= fraction or skel[ys[j] : ys[j + 1], xs[i] : xs[i + 1]].any():
                floor[j, i] = True
            elif region[ys[j] : ys[j + 1], xs[i] : xs[i + 1]].mean() >= 0.5:
                rough[j, i] = True
    # Rough cells matter only as short ways between floor cells: keep those within ROUGH_REACH cells of the floor.
    rough &= ndimage.binary_dilation(floor, np.ones((3, 3), bool), iterations=ROUGH_REACH)
    return floor, rough


NEXT = {0: (1, 2), 1: (0, 2), 2: (0, 1)}  # Model/Walk.lua: the class after a run of class c, by the run's flag


def encode(floor, rough):
    """Model/Walk.lua's run lengths (Walk.Encode): runs of one class (0 blocked, 1 floor, 2 rough), row by row; the
    first number is the first run's length (blocked, possibly 0), every later one 2 * length + flag, the flag picking
    the run's class among the two that differ from the class before. Little-endian base-32 numbers."""
    out = []

    def put(v):
        while True:
            d, v = v % 32, v // 32
            out.append(ALPHABET[d + (32 if v > 0 else 0)])
            if v == 0:
                break

    classes = np.where(floor, 1, np.where(rough, 2, 0)).reshape(-1)
    run, cls, before, first = 0, 0, 0, True

    def flush():
        nonlocal first
        if first:
            put(run)
            first = False
        else:
            put(run * 2 + (0 if NEXT[before][0] == cls else 1))

    for here in classes:
        here = int(here)
        if here != cls:
            flush()
            before, cls, run = cls, here, 0
        run += 1
    flush()
    return "".join(out)


def write_lua(entries):
    """entries: {key: (floor grid, rough grid)}."""
    lines = [
        "-- Generated by tools/walk_grids.py from the floors' map pictures (docs/DATA-SOURCES.md, \"Walkability grids\").",
        "-- Do not edit. Where one can walk on each floor picture, for the route tool's \"Snap to corridors\"",
        "-- (Model/Walk.lua finds the paths, Data/Corridors.lua picks a plan floor's grid). No picture is shipped: each",
        "-- cell is floor, rough (drawn, not floor: crossed only when needed) or blocked, as run lengths (Model/Walk.lua).",
        "--",
        "-- [key] = { cells across, cells down, run lengths }.",
        "-- Keys: \"t:<old dungeon map tile name>\" (the game's map tiles), \"r:<file>\" (Santiago Reyes' bundled map,",
        "-- Data/ReyesMaps.lua), \"m:<instance key>:<floor>\" (the game's minimap pictures, Data/MinimapArtData.lua).",
        "--",
        "-- The \"r:\" entries are made from Santiago Reyes' maps ((c) Santiago Reyes, https://sreyesmaps.com). He gave",
        "-- permission to use his World of Warcraft maps in Dungeon Planner; these grids, which only record where each map",
        "-- shows floor, are made from his maps under that permission and, like the maps, are not under the MIT licence of",
        "-- this project (docs/licenses/SantiagoReyes-maps.md).",
        "",
        "local _, ns = ...",
        "ns.WalkData = {",
    ]
    for key in sorted(entries):
        floor, rough = entries[key]
        k = key.replace("\\", "\\\\")
        lines.append(f'\t["{k}"] = {{ {floor.shape[1]}, {floor.shape[0]}, "{encode(floor, rough)}" }},')
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------------------------------------------------
# Measuring: the recommended plans' legs through grids of several widths, with the addon's own pathfinder.

LUA_BENCH = r"""
local root, gridsFile, legsFile = arg[1], arg[2], arg[3]
local ns = {}
function ns:NewModule(name) local m = {}; self[name] = m; return m end
assert(loadfile(root .. "/Model/Walk.lua"))("DungeonPlanner", ns)
assert(loadfile(gridsFile))("DungeonPlanner", ns)
local legs = assert(loadfile(legsFile))()
local decoded = {}
for i, leg in ipairs(legs) do
  local e = ns.WalkData[leg[1]]
  local g = decoded[leg[1]]
  if not g then g = assert(ns.Walk.Decode(e[1], e[2], e[3])); decoded[leg[1]] = g; ns.Walk.Prices(g) end
  local t = os.clock()
  local bends, why, st = ns.Walk.Path(g, leg[2], leg[3], leg[4], leg[5])
  local ms = (os.clock() - t) * 1000
  local parts = {}
  for _, b in ipairs(bends or {}) do parts[#parts + 1] = string.format("%.5f %.5f", b[1], b[2]) end
  io.write(string.format("%d %s %d %.3f %s\n", i, why or "ok", st.expanded, ms, table.concat(parts, " ")))
end
"""


def share_on(mask, pts, slack=2):
    """Share of the polyline (picture pixels) that lies on the mask grown by `slack` pixels."""
    room = ndimage.binary_dilation(mask, rp._disk(slack)) if slack else mask
    H, W = mask.shape
    good = total = 0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0)))
        for k in range(n):
            t = k / n
            x, y = int(min(W - 1, max(0, x0 + (x1 - x0) * t))), int(min(H - 1, max(0, y0 + (y1 - y0) * t)))
            total += 1
            good += bool(room[y, x])
    return good / max(1, total)


def measure(widths, fraction, masks, legs, work: Path, log):
    """masks: {key: (floor mask, drawn region)}; legs: [(key, ax, ay, bx, by)] in the grid's space (0..1)."""
    work.mkdir(parents=True, exist_ok=True)
    legs_file = work / "legs.lua"
    legs_file.write_text("return {\n" + "".join(f'{{ "{k.replace(chr(92), chr(92) * 2)}", {ax!r}, {ay!r}, {bx!r}, {by!r} }},\n'
                                                for k, ax, ay, bx, by in legs) + "}\n", encoding="utf-8")
    rows = []
    for width in widths:
        grids = {k: grid_of(m, r, width, fraction) for k, (m, r) in masks.items()}
        text = write_lua(grids)
        gfile = work / f"grids-{width}.lua"
        gfile.write_text(text, encoding="utf-8")
        out = subprocess.run(["lua", "-", str(REPO), str(gfile), str(legs_file)], input=LUA_BENCH, capture_output=True,
                             text=True, check=True, cwd=REPO, encoding="utf-8").stdout
        found = ok = straight = 0
        why_not = {}
        floor_shares, drawn_shares, times, nodes, bends = [], [], [], [], []
        for line, (k, ax, ay, bx, by) in zip(out.splitlines(), legs):
            parts = line.split()
            why, expanded, ms = parts[1], int(parts[2]), float(parts[3])
            times.append(ms)
            nodes.append(expanded)
            if why != "ok":
                why_not[why] = why_not.get(why, 0) + 1
                continue
            found += 1
            vals = [float(v) for v in parts[4:]]
            pts = [(ax, ay)] + list(zip(vals[0::2], vals[1::2])) + [(bx, by)]
            bends.append(len(pts) - 2)
            straight += len(pts) == 2
            m, r = masks[k]
            px = [(x * m.shape[1], y * m.shape[0]) for x, y in pts]
            floor_shares.append(share_on(m, px))
            drawn_shares.append(share_on(m | r, px))
            ok += floor_shares[-1] >= 0.97
        size = len(text.encode())
        mean = float(np.mean(floor_shares)) if floor_shares else 0.0
        drawn = float(np.min(drawn_shares)) if drawn_shares else 0.0
        rows.append((width, size, found, ok, mean))
        log(f"width {width}: {size / 1024:.1f} KiB; {len(legs)} legs: {found} found ({why_not or 'all'} not), {ok} with "
            f">= 97% on the floor (mean {mean:.3f}, least on drawn space {drawn:.3f}); {straight} straight; "
            f"bends {float(np.mean(bends)) if bends else 0:.1f}/leg; {float(np.median(times)):.2f} ms median, "
            f"{float(np.max(times)):.2f} ms max, {int(np.max(nodes))} cells max (reference Lua 5.1)")
    return rows


# ---------------------------------------------------------------------------------------------------------------------


def preview(img, mask, floor, rough, path: Path):
    """The picture, the full-size mask (blue tint where not floor), the floor cells outlined green and the rough cells
    orange, to check by eye."""
    path.parent.mkdir(parents=True, exist_ok=True)
    base = img.convert("RGB")
    out = Image.composite(Image.new("RGB", base.size, (20, 20, 70)), base,
                          Image.fromarray(np.where(mask, 0, 120).astype(np.uint8)))
    d = ImageDraw.Draw(out)
    H, W = mask.shape
    gh, gw = floor.shape
    for j in range(gh):
        for i in range(gw):
            if floor[j, i] or rough[j, i]:
                x0, y0 = i * W / gw, j * H / gh
                d.rectangle((x0, y0, x0 + W / gw - 1, y0 + H / gh - 1),
                            outline=(80, 230, 120) if floor[j, i] else (230, 140, 40))
    out.save(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game", required=True, type=Path, help="the game folder that holds Interface/AddOns (e.g. _forever_)")
    ap.add_argument("--work", required=True, type=Path, help="scratch folder for masks, previews and measurements")
    ap.add_argument("--reyes", type=Path, help="folder whose src/ holds Santiago Reyes' files (default: --work)")
    ap.add_argument("--check", action="store_true",
                    help="leave Data/WalkData.lua as it is (the log and previews still go to --work); exit 1 when it "
                         "would change")
    ap.add_argument("--measure", default="", help="comma-separated grid widths to compare (writes nothing)")
    ap.add_argument("--width", type=int, default=WIDTH, help=f"cells across (default {WIDTH})")
    ap.add_argument("--fraction", type=float, default=FRACTION, help=f"floor share of a floor cell ({FRACTION})")
    args = ap.parse_args(argv)
    work = args.work.resolve()
    if REPO in work.parents:
        raise SystemExit("keep --work outside the repository: it holds game art")
    reyes_work = (args.reyes or args.work).resolve()
    lines = []

    def log(s):
        lines.append(s)
        print(s)

    plans, instances = rp.load_repo()
    tables = load_tables()
    reyes, minimap = tables["reyes"], tables["minimap"]
    casc = mm.Casc(args.game)
    world = mm.World(casc)

    # Every picture, by key.
    pictures, kinds = {}, {}
    for spec in instances.values():
        for base in (spec.get("tiles") if isinstance(spec, dict) else None) or []:  # an empty entry comes as []
            key = "t:" + base
            if key not in pictures:
                img = rp.classic_floor(casc, base)
                if img is None:
                    log(f"{key}: the tiles are not in the local storage; no grid")
                    continue
                pictures[key], kinds[key] = img, "tiles"
    for floors in reyes.values():
        for f in floors:
            pictures["r:" + f["file"]], kinds["r:" + f["file"]] = reyes_picture(reyes_work, f["file"]), "reyes"
    # Minimap floors only where the instance has neither old map tiles nor a bundled map.
    for key in sorted(minimap):
        spec = instances.get(key)
        if (isinstance(spec, dict) and spec.get("tiles")) or key in reyes:
            continue
        entries = minimap[key]
        items = enumerate(entries, 1) if isinstance(entries, list) else ((int(k), v) for k, v in entries.items())
        for index, d in items:
            if d and d.get("source") == "building":
                scale = 1000.0 / max(d["w"], d["h"])
                pictures[f"m:{key}:{index}"], kinds[f"m:{key}:{index}"] = minimap_picture(world, d, scale), "minimap"
    # The routes files' overrides, on the pictures they were made on; the plans' legs, for --measure.
    overrides, legs = {}, []
    for plan in plans:
        doc = rp.read_routes(plan["id"])
        for index in range(1, len(plan["floors"]) + 1):
            key = floor_key(instances, reyes, minimap, plan, index)
            if not key or key not in pictures:
                continue
            o = (doc.get("overrides") or {}).get(str(index))
            if o:
                if key in overrides and overrides[key] != o:
                    log(f"{key}: {plan['id']} has other overrides than an earlier plan on the same picture; the first kept")
                overrides.setdefault(key, o)
            xf = minimap_floor(minimap, key.split(":")[1], index)["xf"] if key.startswith("m:") else None
            for r in plan.get("routes", []):
                if r["floor"] != index:
                    continue
                stops = [(p["x"], p["y"]) for p in r["points"] if p.get("step")]
                if xf:
                    stops = [(xf[0] * x + xf[1] * y + xf[2], xf[3] * x + xf[4] * y + xf[5]) for x, y in stops]
                for a, b in zip(stops, stops[1:]):
                    if a != b:
                        legs.append((key, a[0], a[1], b[0], b[1]))
    # The blank parchment under the old dungeon maps, and the one under Santiago Reyes' maps: per-pixel medians.
    backgrounds = {kind: np.median(np.stack([np.asarray(img, np.float32) for k, img in pictures.items()
                                             if kinds[k] == kind]), 0) for kind in ("tiles", "reyes")}
    settings = json.loads(CONFIG.read_text(encoding="utf-8"))["pictures"]
    masks = {}
    for key in sorted(pictures):
        img = pictures[key]
        mine = settings.get(key, {})
        if mine.get("skip"):
            log(f"{key}: no grid: {mine['skip']}")
            continue
        if kinds[key] == "minimap":
            mask = minimap_mask(img)
            region = mask
        else:
            opts = dict(overrides.get(key, {}), **mine)
            o = dict(rp.DEFAULTS, **{k: v for k, v in opts.items() if k in rp.DEFAULTS})
            mask, _t, region = rp.walkable(img, [], opts, backgrounds[kinds[key]], keep_all=True)
            mask = big_parts(mask, o["part"])
            region = (region | mask) & ~(blocked_area(mask.shape, opts) & ~mask)
        masks[key] = (mask, region)
    legs = [leg for leg in legs if leg[0] in masks]
    if args.measure:
        widths = [int(w) for w in args.measure.split(",") if w]
        measure(widths, args.fraction, masks, legs, work / f"measure-{args.fraction}", log)
        (work / "walk_grids.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    grids = {}
    for key in sorted(masks):
        mask, region = masks[key]
        floor, rough = grids[key] = grid_of(mask, region, args.width, args.fraction)
        preview(pictures[key], mask, floor, rough, work / "preview" / (key.replace(":", "_").replace("\\", "_") + ".png"))
        log(f"{key}: {floor.shape[1]} x {floor.shape[0]}, {int(floor.sum())} floor and {int(rough.sum())} rough cells, "
            f"{len(encode(floor, rough))} characters")
    text = write_lua(grids)
    log(f"{len(grids)} grids, {len(text.encode()) / 1024:.1f} KiB")
    work.mkdir(parents=True, exist_ok=True)
    (work / "walk_grids.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
    old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    if old != text:
        if args.check:
            print("Data/WalkData.lua would change")
            sys.exit(1)
        OUT.write_text(text, encoding="utf-8", newline="\n")
        print("Data/WalkData.lua written")
    else:
        print("Data/WalkData.lua unchanged")


if __name__ == "__main__":
    t0 = time.time()
    main()
    print(f"{time.time() - t0:.0f} s")
