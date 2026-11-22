# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "pillow", "scipy", "scikit-image"]
# ///
"""Route bends that follow a dungeon's corridors, for the recommended plans.

The plans in Data/Plans/ draw their route as straight lines between numbered stops, and a straight line cuts through
walls. This tool finds a path through walkable space between each pair of consecutive stops and writes the bends of
that path to data-src/routes/<slug>.json; `lua tools/gen_plans.lua` then puts them into the plans. Only coordinates are
written: no picture, mask or other derived image goes into the repository.

How (all local, read-only on the game and its addons):
  1. Floor pictures. Classic floors: the game's old dungeon map tiles (Interface\\WorldMap\\<Dir>\\<Name><floor>_1..12,
     the names Data/GameFiles.lua uses), read from the game's CASC storage and stitched to 1002 x 668. Forever's new
     dungeons: the map pictures the addon draws under the plan at runtime, from the installed ForeverDungeonJournal
     (first, as the addon does) or OpenMap; the same crop as Data/Providers/*.
  2. A walkable mask per floor: on the classic maps only what differs from the blank parchment they are all painted
     on (the per-pixel median of every floor) and what its walls enclose; inside that, floors are lighter and less
     saturated than walls, lava and shadow (Otsu threshold), then opening, closing, small holes filled, and only the
     parts the plan's stops touch. Per-floor fixes (blocked / opened rectangles, polygons and corridors, normalized
     0..1, and the score's weights) live in the "overrides" of data-src/routes/<slug>.json (data-src/routes/README.md).
  3. A cheapest path between consecutive stops (cost grows near walls, so lines run down the middle of corridors),
     simplified to a few bends that stay inside walkable space.
  4. data-src/routes/<slug>.json: every leg (floor, from, to, bends) marked "generated"; legs marked otherwise and the
     overrides are kept as they are. Stops that sit in a wall are listed in "moves" (to the nearest walkable spot).
  5. Preview pictures (map, mask, route) in the work directory, to check every floor by eye.

Usage (from the repository root; the game path is the folder that holds Interface\\AddOns, e.g. ..._forever_):
  uv run --script tools/route_paths.py --game "<World of Warcraft>/_forever_" --work <scratch dir> [--only slug,...]
  then: lua tools/gen_plans.lua && lua tools/gen_spawns.lua
Options: --check (write nothing; exit 1 when a routes file would change).
Keep the work directory outside the repository (or in .route-work/, which is ignored): it holds game art.
"""

from __future__ import annotations

import argparse
import bisect
import io
import json
import math
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

REPO = Path(__file__).resolve().parent.parent
ROUTES_DIR = REPO / "data-src" / "routes"
CLASSIC_SIZE = (1002, 668)

# ---------------------------------------------------------------------------------------------------------------------
# CASC (the game's local storage), read-only. Enough to read a file by name from an installed client: .build.info ->
# build config -> encoding (content key -> encoded key) and root (name hash -> content key), .idx -> data.### -> BLTE.


def _rot(x, k):
    return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF


def _hashlittle2(data: bytes):
    m = 0xFFFFFFFF
    n = len(data)
    a = b = c = (0xDEADBEEF + n) & m
    i = 0
    while n > 12:
        x, y, z = struct.unpack_from("<III", data, i)
        a, b, c = (a + x) & m, (b + y) & m, (c + z) & m
        a = (a - c) & m; a ^= _rot(c, 4); c = (c + b) & m
        b = (b - a) & m; b ^= _rot(a, 6); a = (a + c) & m
        c = (c - b) & m; c ^= _rot(b, 8); b = (b + a) & m
        a = (a - c) & m; a ^= _rot(c, 16); c = (c + b) & m
        b = (b - a) & m; b ^= _rot(a, 19); a = (a + c) & m
        c = (c - b) & m; c ^= _rot(b, 4); b = (b + a) & m
        n -= 12
        i += 12
    if n == 0:
        return c, b
    x, y, z = struct.unpack_from("<III", data[i:] + b"\0" * (12 - n))
    a, b, c = (a + x) & m, (b + y) & m, (c + z) & m
    c ^= b; c = (c - _rot(b, 14)) & m
    a ^= c; a = (a - _rot(c, 11)) & m
    b ^= a; b = (b - _rot(a, 25)) & m
    c ^= b; c = (c - _rot(b, 16)) & m
    a ^= c; a = (a - _rot(c, 4)) & m
    b ^= a; b = (b - _rot(a, 14)) & m
    c ^= b; c = (c - _rot(b, 24)) & m
    return c, b


def _name_hash(path: str) -> int:
    c, b = _hashlittle2(path.upper().replace("/", "\\").encode())
    return (c << 32) | b


def _blte(data: bytes) -> bytes:
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE")
    hsize = struct.unpack_from(">I", data, 4)[0]
    if hsize == 0:
        sizes, pos = [len(data) - 8], 8
    else:
        count = int.from_bytes(data[9:12], "big")
        sizes = [struct.unpack_from(">I", data, 12 + 24 * i)[0] for i in range(count)]
        pos = hsize
    out = []
    for size in sizes:
        chunk = data[pos : pos + size]
        pos += size
        mode = chunk[:1]
        if mode == b"N":
            out.append(chunk[1:])
        elif mode == b"Z":
            out.append(zlib.decompress(chunk[1:]))
        else:
            raise ValueError(f"BLTE chunk mode {mode!r} not supported")
    return b"".join(out)


class Casc:
    def __init__(self, game: Path):
        root = game
        while not (root / ".build.info").exists():
            if root.parent == root:
                raise SystemExit(f"no .build.info at or above {game}")
            root = root.parent
        self.data = root / "Data"
        lines = (root / ".build.info").read_text(encoding="utf-8").splitlines()
        head = [h.split("!")[0] for h in lines[0].split("|")]
        rows = [dict(zip(head, line.split("|"))) for line in lines[1:] if line.strip()]
        flavor = game / ".flavor.info"
        product = flavor.read_text(encoding="utf-8").splitlines()[1].strip() if flavor.exists() else None
        row = next((r for r in rows if r.get("Product") == product and r.get("Active") == "1"), rows[0])
        key = row["Build Key"]
        self.cfg = {}
        for line in (self.data / "config" / key[:2] / key[2:4] / key).read_text(encoding="utf-8").splitlines():
            if " = " in line:
                k, v = line.split(" = ", 1)
                self.cfg[k] = v.split()
        self._index()
        self._encoding()
        self._root()

    def _index(self):
        best = {}
        for f in (self.data / "data").glob("*.idx"):
            bucket, version = int(f.name[:2], 16), int(f.name[2:10], 16)
            if bucket not in best or version > best[bucket][0]:
                best[bucket] = (version, f)
        self.index = {}
        for _, f in best.values():
            b = f.read_bytes()
            start = (8 + struct.unpack_from("<I", b, 0)[0] + 15) & ~15
            size = struct.unpack_from("<I", b, start)[0]
            for p in range(start + 8, start + 8 + size - 17, 18):
                k = b[p : p + 9]
                if k not in self.index:
                    off = int.from_bytes(b[p + 9 : p + 14], "big")
                    self.index[k] = (off >> 30, off & 0x3FFFFFFF, struct.unpack_from("<I", b, p + 14)[0])

    def _read_ekey(self, ekey: bytes) -> bytes:
        archive, off, size = self.index[ekey[:9]]
        with open(self.data / "data" / f"data.{archive:03d}", "rb") as f:
            f.seek(off)
            return _blte(f.read(size)[30:])

    def _encoding(self):
        e = self._read_ekey(bytes.fromhex(self.cfg["encoding"][1]))
        if e[:2] != b"EN":
            raise ValueError("encoding file")
        self.ck, self.ek = e[3], e[4]
        self.page = struct.unpack_from(">H", e, 5)[0] * 1024
        count = struct.unpack_from(">I", e, 9)[0]
        p = 22 + struct.unpack_from(">I", e, 18)[0]
        self.firsts = [e[p + i * 32 : p + i * 32 + self.ck] for i in range(count)]
        self.pages = p + count * 32
        self.enc = e

    def _ekey(self, ckey: bytes):
        i = bisect.bisect_right(self.firsts, ckey) - 1
        p = self.pages + i * self.page
        end, e = p + self.page, self.enc
        while i >= 0 and p < end and e[p]:
            if e[p + 6 : p + 6 + self.ck] == ckey:
                return e[p + 6 + self.ck : p + 6 + self.ck + self.ek]
            p += 6 + self.ck + e[p] * self.ek
        return None

    def _root(self):
        r = self._read_ekey(self._ekey(bytes.fromhex(self.cfg["root"][0])))
        if r[:4] != b"TSFM":
            raise ValueError("root format not supported")
        a, b = struct.unpack_from("<II", r, 4)
        version, p = 0, 12
        total, named = a, b
        if a == 0x18 and b in (1, 2):
            version = b
            total, named = struct.unpack_from("<II", r, 12)
            p = 24
        nameless_ok = total != named
        self.by_hash = {}
        self.fid_by_hash = {}
        while p < len(r):
            if version >= 2:
                n, locale, f1, f2 = struct.unpack_from("<IIII", r, p)
                content = f1 | f2 | (r[p + 16] << 17)
                p += 17
            else:
                n, content, locale = struct.unpack_from("<III", r, p)
                p += 12
            deltas = struct.unpack_from(f"<{n}I", r, p)
            p += 4 * n
            ckeys = p
            p += 16 * n
            if nameless_ok and content & 0x10000000:
                continue
            hashes = struct.unpack_from(f"<{n}Q", r, p)
            p += 8 * n
            if locale & 0x2 and not content & 0x80:  # enUS, not the low-violence variant
                fid = -1
                for i, h in enumerate(hashes):
                    fid += 1 + deltas[i]  # file data IDs: the first delta, then each one past the previous
                    self.by_hash.setdefault(h, r[ckeys + 16 * i : ckeys + 16 * i + 16])
                    self.fid_by_hash.setdefault(h, fid)

    def read(self, path: str):
        ck = self.by_hash.get(_name_hash(path))
        ek = ck and self._ekey(ck)
        return self._read_ekey(ek) if ek else None

    def file_id(self, path: str):
        """The file's data ID (what GetFileIDFromPath returns in game), or None."""
        return self.fid_by_hash.get(_name_hash(path))


# ---------------------------------------------------------------------------------------------------------------------
# The repository's own data, read through Lua so nothing is parsed twice: the generated plans and Data/GameFiles.lua.

LUA_DUMP = r"""
local root = arg[1]
local ns = { Bundled = {}, Util = {}, Match = {} }
local plans = {}
function ns.Bundled.Add(p) plans[#plans + 1] = p end
function ns:NewModule(name) local m = {}; self[name] = m; return m end
assert(loadfile(root .. "/Data/GameFiles.lua"))("DungeonPlanner", ns)
for i = 2, #arg do assert(loadfile(arg[i]))("DungeonPlanner", ns) end
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
io.write(enc({ plans = plans, instances = ns.GameFiles.INSTANCES }))
"""


def strip_article(name: str) -> str:
    name = re.sub(r"^\s*the\s+", "", name, flags=re.I).lower()
    return re.sub(r"[^0-9a-z\x80-\U0010ffff]", "", name)


def load_repo():
    files = sorted((REPO / "Data" / "Plans").glob("*.lua"))
    out = subprocess.run(
        ["lua", "-", str(REPO)] + [str(f) for f in files], input=LUA_DUMP, capture_output=True, text=True, check=True,
        cwd=REPO, encoding="utf-8",
    ).stdout
    data = json.loads(out)
    for plan in data["plans"]:
        for r in plan.get("routes", []):
            # A stop { x, y, step = n } arrives as {"1": x, "2": y, "step": n}, a bend { x, y } as [x, y].
            r["points"] = [{"x": p[0], "y": p[1]} if isinstance(p, list) else dict(p, x=p.pop("1"), y=p.pop("2"))
                           for p in r["points"]]
    return data["plans"], data["instances"]


def tile_bases(instances, plan):
    spec = instances.get(strip_article(plan["instance"]["name"]))
    if spec and spec.get("alias"):
        spec = instances.get(spec["alias"])
    return (spec or {}).get("tiles") or []


# ---------------------------------------------------------------------------------------------------------------------
# Floor pictures.


def classic_floor(casc: Casc, base: str):
    img = Image.new("RGB", (1024, 768))
    for i in range(12):
        raw = casc.read(f"Interface\\WorldMap\\{base}{i + 1}.blp")
        if raw is None:
            return None
        img.paste(Image.open(io.BytesIO(raw)).convert("RGB"), ((i % 4) * 256, (i // 4) * 256))
    return img.crop((0, 0) + CLASSIC_SIZE)


def _num(expr: str) -> float:
    m = re.fullmatch(r"\s*([\d.]+)\s*(?:/\s*([\d.]+))?\s*", expr)
    return float(m.group(1)) / float(m.group(2) or 1)


def fdj_maps(game: Path):
    """ForeverDungeonJournal's DUNGEON_MAPS: {name: {floors: [{texture, right, bottom, label}], bosses: [...]}}."""
    src = game / "Interface" / "AddOns" / "ForeverDungeonJournal" / "Core" / "Journal.lua"
    if not src.exists():
        return {}
    text = src.read_text(encoding="utf-8", errors="replace")
    start = text.find("FDJ.DUNGEON_MAPS = {")
    if start < 0:
        return {}
    out = {}
    blocks = list(re.finditer(r'^    \["([^"]+)"\] = \{', text[start:], re.M))
    for i, m in enumerate(blocks):
        body = text[start + m.end() : start + (blocks[i + 1].start() if i + 1 < len(blocks) else m.end() + 20000)]
        floors = []
        for f in re.finditer(r"\{\s*texture\s*=\s*\"([^\"]+)\"([^}]*)\}", body):
            rest = f.group(2)
            def field(name, rest=rest):
                g = re.search(name + r"\s*=\s*([\d./ ]+)", rest)
                return _num(g.group(1)) if g else 1.0
            label = re.search(r'label\s*=\s*"([^"]+)"', rest)
            floors.append({"texture": f.group(1), "right": field("texRight"), "bottom": field("texBottom"),
                           "label": label.group(1) if label else None})
        bosses = []
        bm = re.search(r"bosses\s*=\s*\{(.*?)\n        \}", body, re.S)
        for b in re.finditer(r'name\s*=\s*"([^"]+)"[^}]*?(?:floor\s*=\s*(\d+),)?\s*x\s*=\s*([\d.]+),\s*y\s*=\s*([\d.]+)',
                             bm.group(1) if bm else ""):
            bosses.append({"name": b.group(1), "floor": int(b.group(2) or 1), "x": float(b.group(3)), "y": float(b.group(4))})
        if floors:
            out[strip_article(m.group(1))] = {"floors": floors, "bosses": bosses}
    return out


def openmap_maps(game: Path):
    """OpenMap's drawn maps: {key: [{name, tiles: [12 paths]}]} by the instance name in each entry's comment."""
    root = game / "Interface" / "AddOns" / "OpenMap"
    src = root / "Data" / "Forever" / "DungeonDrawn.lua"
    if not src.exists():
        return {}
    out, key = {}, None
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r'\s*\[(?:\d+|"([^"]+)")\] = \{(?:\s*--\s*(.+))?', line)
        if m and "tiles" not in line:
            key = strip_article(m.group(1) or m.group(2) or "")
            out.setdefault(key, [])
            continue
        if key and "tiles = {" in line:
            name = re.search(r'name = "([^"]+)"', line)
            tiles = re.findall(r'P \.\. "([^"]+)"', line)
            out[key].append({"name": name.group(1) if name else None,
                             "tiles": [root / "Media" / "Textures" / "Forever" / "MapDungeonDrawn" / (t + ".tga") for t in tiles]})
    return out


STOP_WORDS = {"the", "of", "and", "map"}


def name_words(name):
    """Providers.NameWords: lower case runs of letters and digits, at least 3 long, without the stop words."""
    return [w for w in re.findall(r"[0-9a-z]+", (name or "").lower()) if len(w) >= 3 and w not in STOP_WORDS]


def pick_floor(want, index, candidates):
    """Providers.PickFloor: candidates are (label, file) pairs; the plan floor's name `want`, its 1-based `index`.
    The floor labelled with that name; else the one whose label (unlabelled: file name) holds the most of its words,
    when one alone does; else the one at the same position. Returns a 0-based index or None."""
    key = strip_article(want or "")
    if key:
        for i, (label, _file) in enumerate(candidates):
            if label and strip_article(label) == key:
                return i
        words = name_words(want)
        scores = []
        for label, file in candidates:
            # The label when there is one (a file name repeats the instance's name), else the file name.
            text = re.sub(r"[^0-9a-z]", "", (label or (file or "").replace("/", "\\").rsplit("\\", 1)[-1]).lower())
            scores.append(sum(1 for w in words if w in text))
        best = max(scores, default=0)
        if best > 0 and scores.count(best) == 1:
            return scores.index(best)
    return index - 1 if 1 <= index <= len(candidates) else None


def provider_floor(game: Path, fdj, openmap, plan, floor_index):
    """(image, provider, pins) for a floor of a Forever dungeon, as Data/Providers/* would pick it, or None."""
    key = strip_article(plan["instance"]["name"])
    want = plan["floors"][floor_index - 1].get("name") or ""
    entry = fdj.get(key)
    if entry:
        floors = entry["floors"]
        i = pick_floor(want, floor_index, [(c["label"], c["texture"]) for c in floors])
        f = floors[i] if i is not None else None
        if f:
            path = game / (f["texture"].replace("\\", "/") + ".tga")
            if path.exists():
                img = Image.open(path).convert("RGB")
                w, h = img.size
                img = img.crop((0, 0, round(w * f["right"]), round(h * f["bottom"])))
                n = floors.index(f) + 1
                pins = [b for b in entry["bosses"] if b["floor"] == n]
                return img, "Dungeon Journal " + f["texture"].rsplit("\\", 1)[-1], pins
    drawn = openmap.get(key) or []
    i = pick_floor(want, floor_index, [(f["name"], str(f["tiles"][0]) if f["tiles"] else None) for f in drawn])
    for f in drawn[i : i + 1] if i is not None else []:
        if len(f["tiles"]) == 12 and all(t.exists() for t in f["tiles"]):
            img = Image.new("RGB", (1024, 768))
            for i, t in enumerate(f["tiles"]):
                img.paste(Image.open(t).convert("RGB").resize((256, 256)), ((i % 4) * 256, (i // 4) * 256))
            return img.crop((0, 0) + CLASSIC_SIZE), "OpenMap " + f["tiles"][0].stem.rsplit("_", 1)[0], []
    return None


def align(plan, floor_index, pins):
    """Providers.Align: plan boss markers vs provider pins of the same name -> (sx, tx, sy, ty) or identity."""
    by = {strip_article(p["name"]): p for p in pins}
    pairs = []
    for m in plan.get("markers", []):
        if m.get("floor") == floor_index and m.get("kind") == "boss":
            p = by.get(strip_article(m.get("label") or ""))
            if p:
                pairs.append((m["x"], m["y"], p["x"], p["y"]))
    ident = (1.0, 0.0, 1.0, 0.0, "same" if pairs else "none")
    if not pairs:
        return ident
    rms = lambda sx, tx, sy, ty: math.sqrt(sum((a * sx + tx - c) ** 2 + (b * sy + ty - d) ** 2 for a, b, c, d in pairs) / len(pairs))
    if rms(1, 0, 1, 0) <= 0.035:
        return ident
    if len(pairs) >= 3:
        def fit(i, j):
            n = len(pairs)
            sa = sum(p[i] for p in pairs); sb = sum(p[j] for p in pairs)
            saa = sum(p[i] * p[i] for p in pairs); sab = sum(p[i] * p[j] for p in pairs)
            d = n * saa - sa * sa
            if abs(d) < 1e-9:
                return 1.0, (sb - sa) / n
            s = (n * sab - sa * sb) / d
            return s, (sb - s * sa) / n
        sx, tx = fit(0, 2)
        sy, ty = fit(1, 3)
        if rms(sx, tx, sy, ty) <= 0.035 and 0.5 < sx < 2 and 0.5 < sy < 2:
            return sx, tx, sy, ty, "fit"
    return 1.0, 0.0, 1.0, 0.0, "pins"


# ---------------------------------------------------------------------------------------------------------------------
# Which floors need a picture: every plan floor with a route of two or more stops.


def route_floors(plan):
    floors = {}
    for r in plan.get("routes", []):
        stops = [p for p in r["points"] if p.get("step")]
        if len(stops) >= 2:
            floors.setdefault(r["floor"], []).append(r)
    return floors


def floor_picture(game, casc, instances, fdj, openmap, plan, floor_index):
    """(image, source, transform) for a plan floor; transform maps plan space to picture space (Providers.Align)."""
    floor = plan["floors"][floor_index - 1]
    bases = tile_bases(instances, plan)
    if floor_index <= len(bases) and not (not floor.get("name") and floor.get("uiMapID")):
        img = classic_floor(casc, bases[floor_index - 1])
        if img is not None:
            return img, "game map tiles " + bases[floor_index - 1], (1.0, 0.0, 1.0, 0.0, "none")
    got = provider_floor(game, fdj, openmap, plan, floor_index)
    if got:
        img, source, pins = got
        xf = align(plan, floor_index, pins)
        return img, f"{source} ({xf[4]})", xf
    return None, None, None


# ---------------------------------------------------------------------------------------------------------------------
# Walkable mask.

DEFAULTS = {"threshold": None, "light": 1.0, "saturation": 60.0, "blue": 0.0, "yellow": 0.0, "smooth": 2.0, "close": 2, "open": 1, "hole": 400, "seed": 12,
            "drawn": 10.0, "part": 300}


def _otsu(values):
    hist, edges = np.histogram(values, bins=256)
    p = hist / max(1, hist.sum())
    centers = (edges[:-1] + edges[1:]) / 2
    w0 = np.cumsum(p)
    m0 = np.cumsum(p * centers)
    between = (m0[-1] * w0 - m0) ** 2 / np.maximum(w0 * (1 - w0), 1e-9)
    return float(centers[int(np.argmax(between))])


def _disk(r):
    y, x = np.ogrid[-r : r + 1, -r : r + 1]
    return x * x + y * y <= r * r


def _rects(mask, rects, value):
    h, w = mask.shape
    for r in rects:
        x0, y0, x1, y1 = r[:4]
        mask[max(0, round(y0 * h)) : round(y1 * h) + 1, max(0, round(x0 * w)) : round(x1 * w) + 1] = value


def _polys(mask, polys, value):
    if not polys:
        return
    h, w = mask.shape
    canvas = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(canvas)
    for poly in polys:
        draw.polygon([(x * w, y * h) for x, y in poly], fill=255)
    mask[np.asarray(canvas) > 0] = value


def _paths(mask, paths, value):
    """Thick lines: {"points": [[x, y], ...], "width": px}."""
    if not paths:
        return
    h, w = mask.shape
    canvas = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(canvas)
    for p in paths:
        pts = [(x * w, y * h) for x, y in p["points"]]
        width = int(p.get("width", 8))
        draw.line(pts, fill=255, width=width)
        for x, y in pts:
            draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=255)
    mask[np.asarray(canvas) > 0] = value


def walkable(img: Image.Image, seeds, opts, background=None, keep_all=False):
    """Boolean mask of walkable floor, and the threshold used. seeds: picture pixels (x, y) of the route stops; only
    the parts of the mask they touch (or lie next to) are kept, unless keep_all (tools/walk_grids.py keeps every part).
    background: the blank parchment all the game's old dungeon maps are painted on (their per-pixel median); where
    given, only what is drawn on it can be floor."""
    o = dict(DEFAULTS, **{k: v for k, v in opts.items() if k in DEFAULTS})
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    light = ndimage.gaussian_filter(a.mean(2), o["smooth"])
    mx, mn = a.max(2), a.min(2)
    sat = ndimage.gaussian_filter((mx - mn) / np.maximum(mx, 1), o["smooth"])
    blue = ndimage.gaussian_filter(a[..., 2] - a[..., 0], o["smooth"])
    yellow = ndimage.gaussian_filter((a[..., 0] + a[..., 1]) / 2 - a[..., 2], o["smooth"])
    score = o["light"] * light - o["saturation"] * sat + o["blue"] * blue + o["yellow"] * yellow
    region = np.ones(score.shape, bool)
    if background is not None and background.shape == a.shape:
        diff = ndimage.gaussian_filter(np.abs(a - background).mean(2), 1.5)
        # What is painted, and what its walls enclose (some maps draw rooms as outlines on the bare parchment).
        region = ndimage.binary_fill_holes(ndimage.binary_closing(diff > o["drawn"], _disk(2)))
    t = o["threshold"] if o["threshold"] is not None else _otsu(score[region])
    mask = (score > t) & region
    if o["open"]:
        mask = ndimage.binary_opening(mask, _disk(o["open"]))
    if o["close"]:
        mask = ndimage.binary_closing(mask, _disk(o["close"]), border_value=0)
    # Small holes (icons, labels, texture) are floor; big ones (pits, pillars, courtyards) stay out.
    holes = ndimage.binary_fill_holes(mask) & ~mask
    lab, n = ndimage.label(holes)
    if n:
        sizes = ndimage.sum(holes, lab, range(1, n + 1))
        mask |= np.isin(lab, 1 + np.flatnonzero(sizes <= o["hole"]))
    # Fixes by hand: blocks first, then openings (so a path can be opened through a blocked area).
    _rects(mask, opts.get("block_rects", []), False)
    _polys(mask, opts.get("block_polys", []), False)
    _paths(mask, opts.get("block_paths", []), False)
    _rects(mask, opts.get("open_rects", []), True)
    _polys(mask, opts.get("open_polys", []), True)
    _paths(mask, opts.get("open_paths", []), True)
    if keep_all:
        return mask, t, region
    # Keep the parts a stop touches or lies next to; specks (a portal swirl, an icon) do not count as parts.
    lab, n = ndimage.label(mask)
    sizes = np.concatenate([[0], ndimage.sum(mask, lab, range(1, n + 1))]) if n else np.zeros(1)
    big = sizes >= o["part"]
    keep = set()
    h, w = mask.shape
    r = o["seed"]
    for x, y in seeds:
        xi, yi = int(round(x)), int(round(y))
        if 0 <= yi < h and 0 <= xi < w and big[lab[yi, xi]]:
            keep.add(int(lab[yi, xi]))
            continue
        win = lab[max(0, yi - r) : yi + r + 1, max(0, xi - r) : xi + r + 1]
        vals = win[big[win]] if win.size else win
        if vals.size:
            keep.add(int(np.bincount(vals).argmax()))
    return np.isin(lab, sorted(keep)), t, region


# ---------------------------------------------------------------------------------------------------------------------
# Paths.


def _nearest_walkable(mask, dist, x, y, clearance=3.0, limit=40):
    """The walkable pixel nearest to (x, y) with some clearance (else any walkable one) within `limit` px."""
    h, w = mask.shape
    xi, yi = min(w - 1, max(0, int(round(x)))), min(h - 1, max(0, int(round(y))))
    y0, y1, x0, x1 = max(0, yi - limit), min(h, yi + limit + 1), max(0, xi - limit), min(w, xi + limit + 1)
    win = dist[y0:y1, x0:x1]
    for need in (clearance, 0.5):
        ys, xs = np.nonzero(win >= need)
        if ys.size:
            d = (xs + x0 - x) ** 2 + (ys + y0 - y) ** 2
            i = int(np.argmin(d))
            if math.sqrt(d[i]) <= limit:
                return float(xs[i] + x0), float(ys[i] + y0)
    return None


def _clear(dist, a, b, need):
    n = max(2, int(math.hypot(b[0] - a[0], b[1] - a[1])))
    h, w = dist.shape
    for i in range(1, n):
        t = i / n
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if dist[min(h - 1, int(round(y))), min(w - 1, int(round(x)))] < need:
            return False
    return True


def _simplify(pts, dist, tol, need):
    if len(pts) <= 2:
        return pts
    a, b = np.asarray(pts[0]), np.asarray(pts[-1])
    ab = b - a
    norm = np.hypot(*ab) or 1.0
    devs = [abs(ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) / norm for p in pts[1:-1]]
    i = int(np.argmax(devs)) + 1
    if devs[i - 1] <= tol and _clear(dist, pts[0], pts[-1], need):
        return [pts[0], pts[-1]]
    left = _simplify(pts[: i + 1], dist, tol, need)
    return left[:-1] + _simplify(pts[i:], dist, tol, need)


OFF_FLOOR = 40.0  # cost per px of crossing what is drawn but is not floor, when no floor-only path exists


def find_path(mask, dist, cost, rough, a, b, tol=5.0):
    """Picture-space polyline from a to b through walkable space, and how many px of it are off the floor (0 normally;
    more when the floor alone does not connect a and b and the path had to cross something drawn). None: no path."""
    from skimage.graph import MCP_Geometric

    h, w = mask.shape
    sa = _nearest_walkable(mask, dist, *a) or (min(w - 1, max(0, a[0])), min(h - 1, max(0, a[1])))
    sb = _nearest_walkable(mask, dist, *b) or (min(w - 1, max(0, b[0])), min(h - 1, max(0, b[1])))
    start, end = (int(round(sa[1])), int(round(sa[0]))), (int(round(sb[1])), int(round(sb[0])))
    off = 0
    for grid in (cost, rough):
        if not np.isfinite(grid[start]) or not np.isfinite(grid[end]):
            continue
        mcp = MCP_Geometric(grid)
        costs, _ = mcp.find_costs([start], [end])
        if np.isfinite(costs[end]):
            cells = mcp.traceback(end)
            break
    else:
        return None, 0
    off = sum(1 for r, c in cells if not mask[r, c])
    room = dist
    if off:
        passable = mask.copy()
        rr, cc = zip(*cells)
        passable[list(rr), list(cc)] = True
        room = ndimage.distance_transform_edt(ndimage.binary_dilation(passable, _disk(1)) | mask)
    pts = _simplify([(float(c), float(r)) for r, c in cells], room, tol, need=1.0)
    out = [tuple(a)]
    if math.hypot(sa[0] - a[0], sa[1] - a[1]) > 2:
        out.append(tuple(sa))
    out += pts[1:-1]
    if math.hypot(sb[0] - b[0], sb[1] - b[1]) > 2:
        out.append(tuple(sb))
    out.append(tuple(b))
    return out, off


def cost_image(mask, region):
    dist = ndimage.distance_transform_edt(mask)
    cost = np.where(mask, 1.0 + 6.0 * np.exp(-dist / 3.0), np.inf)
    rough = np.where(region & ~mask, OFF_FLOOR, cost)
    return dist, cost, rough


# ---------------------------------------------------------------------------------------------------------------------
# The routes files (data-src/routes/<slug>.json).

ROUND = 4
MOVE_LIMIT = 15  # px: an estimate farther than this from the floor is taken as meant (a portal outside a cave) ...
MOVE_LIMIT_BLANK = 60  # ... unless it lies on the blank parchment, where nothing can be


def rnd(v):
    return round(float(v), ROUND)


def pkey(floor, x, y):
    return (int(floor), rnd(x), rnd(y))


def read_routes(slug):
    path = ROUTES_DIR / f"{slug}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def format_routes(doc):
    """Stable JSON: one move or leg per line (and one imported fill, stop or side path per line)."""
    lines = ["{"]
    for k in ("schema", "slug", "about", "map"):
        lines.append(f"  {json.dumps(k)}: {json.dumps(doc[k], ensure_ascii=False)},")
    lines.append(f'  "overrides": {json.dumps(doc.get("overrides", {}), ensure_ascii=False, sort_keys=True)},')
    imp = doc.get("import")
    if imp:
        lines.append('  "import": {')
        heads = [k for k in imp if k not in ("fill", "add", "side")]
        for k in heads:
            lines.append(f"    {json.dumps(k)}: {json.dumps(imp[k], ensure_ascii=False)},")
        for n, name in enumerate(("fill", "add", "side")):
            items = imp.get(name, [])
            lines.append(f'    "{name}": [')
            for i, it in enumerate(items):
                lines.append("      " + json.dumps(it, ensure_ascii=False) + ("," if i < len(items) - 1 else ""))
            lines.append("    ]" + ("," if n < 2 else ""))
        lines.append("  },")
    for name in ("moves", "legs"):
        items = doc.get(name, [])
        lines.append(f'  "{name}": [')
        for i, it in enumerate(items):
            lines.append("    " + json.dumps(it, ensure_ascii=False) + ("," if i < len(items) - 1 else ""))
        lines.append("  ]" + ("," if name == "moves" else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def process_plan(plan, pictures, work: Path, log, background=None, prefer=None, keep=frozenset()):
    """Legs and moves for one plan. pictures: {floor: (img, source, transform)}. Returns the routes document.
    prefer(floor, a, b, ctx) -> (picture-space polyline from a to b, extra leg fields) or None: a leg from elsewhere
    (an imported route, tools/import_routes.py) that wins over the computed one; ctx holds the floor's picture, mask
    and transforms. Without `prefer`, legs an import wrote (marked "import") are kept like hand-made ones.
    keep: points (pkey) that are never moved off a wall (an imported route's own stops)."""
    slug = plan["id"]
    old = read_routes(slug)
    overrides = old.get("overrides", {})
    manual_legs = [leg for leg in old.get("legs", []) if not leg.get("generated")
                   and not (prefer is not None and leg.get("import"))]
    manual_moves = [m for m in old.get("moves", []) if not m.get("generated")]
    # An imported route's own stops stay where it puts them (its legs are keyed by them).
    imp = old.get("import") or {}
    keep = set(keep) | {pkey(e["floor"], *e["at"]) for e in imp.get("fill", []) + imp.get("add", [])}
    manual_keys = {(leg["floor"], tuple(leg["from"]), tuple(leg["to"])) for leg in manual_legs}
    # The plans on disk already carry the last run's moves: undo them, so every run starts from the research positions.
    undo = {pkey(m["floor"], *m["to"]): tuple(m["from"]) for m in old.get("moves", []) if m.get("generated")}

    def original(floor, x, y):
        return undo.get(pkey(floor, x, y), (rnd(x), rnd(y)))

    moves, legs, maps, preferred = [], [], {}, []
    floors = route_floors(plan)
    for floor in sorted(floors):
        img, source, xf = pictures.get(floor, (None, None, None))
        if img is None:
            log(f"{slug} floor {floor}: no picture, legs stay straight")
            continue
        maps[str(floor)] = source
        sx, tx, sy, ty, _mode = xf
        W, H = img.size

        def to_px(x, y):
            return ((x * sx + tx) * W, (y * sy + ty) * H)

        def to_plan(px, py):
            return ((px / W - tx) / sx, (py / H - ty) / sy)

        opts = overrides.get(str(floor), {})
        stops = [[original(floor, p["x"], p["y"]) for p in r["points"] if p.get("step")] for r in floors[floor]]
        seeds = [to_px(*s) for run in stops for s in run] + [to_px(*s) for s in opts.get("seeds", [])]
        bg = background if source.startswith("game map tiles") else None
        mask, threshold, region = walkable(img, seeds, opts, bg)
        dist, cost, rough = cost_image(mask, region)
        # Stops and markers in a wall: estimated ones move to the nearest walkable spot; measured ones stay.
        moved = {}
        for mm in manual_moves:
            if mm["floor"] == floor:
                moved[pkey(floor, *mm["from"])] = tuple(mm["to"])
        things = [(p["x"], p["y"], p.get("note"), "stop") for r in floors[floor] for p in r["points"] if p.get("step")]
        things += [(m["x"], m["y"], m.get("note"), m.get("kind")) for m in plan.get("markers", []) if m.get("floor") == floor]
        for x, y, note, kind in things:
            ox, oy = original(floor, x, y)
            k = pkey(floor, ox, oy)
            if k in moved or k in keep:
                continue
            px, py = to_px(ox, oy)
            xi, yi = min(W - 1, max(0, int(round(px)))), min(H - 1, max(0, int(round(py))))
            if dist[yi, xi] >= 1:
                continue
            if "(approx.)" not in (note or ""):
                log(f"{slug} floor {floor}: measured {kind} at {ox},{oy} is not on walkable space; left as is")
                continue
            limit = MOVE_LIMIT if region[yi, xi] else MOVE_LIMIT_BLANK
            # Never onto a spot another point holds (two points on one spot could not be told apart next run).
            room = dist.copy()
            taken = {(p[0], p[1]) for p in moved.values()} | {original(floor, t[0], t[1]) for t in things}
            for tx_, ty_ in taken:
                qx, qy = to_px(tx_, ty_)
                room[max(0, int(qy) - 2) : int(qy) + 3, max(0, int(qx) - 2) : int(qx) + 3] = 0
            near = _nearest_walkable(mask, room, px, py, clearance=3.0, limit=limit)
            if not near:
                log(f"{slug} floor {floor}: {kind} at {ox},{oy} is off walkable space by more than {limit} px; left as is")
                continue
            to = [rnd(c) for c in to_plan(*near)]
            moved[k] = tuple(to)
            moves.append({"floor": floor, "from": [ox, oy], "to": to, "kind": kind, "generated": True})
            log(f"{slug} floor {floor}: moved {kind} {ox},{oy} -> {to[0]},{to[1]} (it was in a wall)")
        # Legs between consecutive stops.
        drawn = []
        ctx = {"img": img, "mask": mask, "dist": dist, "cost": cost, "rough": rough, "region": region,
               "to_px": to_px, "to_plan": to_plan, "source": source, "classic": bg is not None, "background": bg}
        for run in stops:
            pts = [moved.get(pkey(floor, *s), s) for s in run]
            for a, b in zip(pts, pts[1:]):
                if (floor, tuple(a), tuple(b)) in manual_keys or a == b:
                    continue
                got = prefer(floor, a, b, ctx) if prefer else None
                if got:
                    line, extra = got
                    bends = [[rnd(c) for c in to_plan(*q)] for q in line[1:-1]]
                    preferred.append(dict({"floor": floor, "from": list(a), "to": list(b), "bends": bends}, **extra))
                    drawn.append((a, b, line))
                    continue
                line, off = find_path(mask, dist, cost, rough, to_px(*a), to_px(*b))
                if line is None:
                    log(f"{slug} floor {floor}: no path {a} -> {b}; the leg stays straight")
                    drawn.append((a, b, None))
                    continue
                if off:
                    log(f"{slug} floor {floor}: the floor does not connect {a} -> {b}; the path crosses {off} px off it")
                bends = [[rnd(c) for c in to_plan(*q)] for q in line[1:-1]]
                legs.append({"floor": floor, "from": list(a), "to": list(b), "bends": bends, "generated": True})
                drawn.append((a, b, line))
        preview(img, mask, drawn, to_px, work / "preview" / f"{slug}-{floor}.png")
        (work / "masks").mkdir(parents=True, exist_ok=True)
        Image.fromarray((mask * 255).astype(np.uint8)).save(work / "masks" / f"{slug}-{floor}.png")
    # Computed legs, then kept ones, then a caller's (in the order a later run without `prefer` reads them back).
    legs += manual_legs + preferred
    legs.sort(key=lambda leg: leg["floor"])
    doc = {
        "schema": 1,
        "slug": slug,
        "about": "Route bends through walkable space between consecutive stops (tools/route_paths.py). Moves and legs "
        "marked generated are redone by the tool; the others and the overrides are kept.",
        "map": maps,
        "overrides": overrides,
        "moves": manual_moves + moves,
        "legs": legs,
    }
    if old.get("import"):
        doc["about"] += (" The import block and the legs marked import come from an imported route "
                         "(tools/import_routes.py); this tool computes only the legs that route does not cover.")
        doc["import"] = old["import"]
    return doc


def preview(img, mask, drawn, to_px, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    base = img.convert("RGB")
    out = Image.composite(Image.new("RGB", base.size, (20, 20, 70)), base,
                          Image.fromarray(np.where(mask, 0, 140).astype(np.uint8)))
    d = ImageDraw.Draw(out)
    W, H = out.size
    for i in range(1, 20):  # a grid every 0.05 (labelled every 0.1), to write overrides from
        c = (90, 200, 255) if i % 2 == 0 else (60, 110, 140)
        d.line([(W * i / 20, 0), (W * i / 20, H)], fill=c, width=1)
        d.line([(0, H * i / 20), (W, H * i / 20)], fill=c, width=1)
        if i % 2 == 0:
            d.text((W * i / 20 + 2, 2), f"{i / 20:.1f}", fill=(255, 255, 255))
            d.text((2, H * i / 20 + 2), f"{i / 20:.1f}", fill=(255, 255, 255))
    for a, b, line in drawn:
        d.line([to_px(*a), to_px(*b)], fill=(160, 160, 160), width=1)
        if line:
            d.line(line, fill=(230, 30, 30), width=3)
            for q in line[1:-1]:
                d.ellipse((q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3), outline=(255, 255, 0))
    for a, b, _ in drawn:
        for q in (to_px(*a), to_px(*b)):
            d.ellipse((q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5), fill=(30, 120, 255), outline=(255, 255, 255))
    out.save(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game", required=True, type=Path, help="the game folder that holds Interface/AddOns (e.g. _forever_)")
    ap.add_argument("--work", required=True, type=Path, help="scratch folder for pictures, masks and previews")
    ap.add_argument("--only", default="", help="comma-separated plan slugs")
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 when a routes file would change")
    args = ap.parse_args(argv)
    work = args.work.resolve()
    if REPO in work.parents and REPO / ".route-work" not in [work, *work.parents]:
        raise SystemExit("keep --work outside the repository (or in .route-work/): it holds game art")
    only = {s for s in args.only.split(",") if s}
    plans, instances = load_repo()
    casc = Casc(args.game)
    fdj, openmap = fdj_maps(args.game), openmap_maps(args.game)
    lines, changed = [], []

    def log(s):
        lines.append(s)
        print(s)

    pictures = {}
    for plan in plans:
        for f in route_floors(plan):
            pictures[plan["id"], f] = floor_picture(args.game, casc, instances, fdj, openmap, plan, f)
    # The blank parchment under every old dungeon map: the per-pixel median of all of them.
    classic = [np.asarray(img, np.float32) for img, src, _ in pictures.values() if img and src.startswith("game map tiles")]
    background = np.median(np.stack(classic), 0) if len(classic) >= 5 else None
    for plan in plans:
        if (only and plan["id"] not in only) or not route_floors(plan):
            continue
        mine = {f: pictures[plan["id"], f] for f in route_floors(plan)}
        text = format_routes(process_plan(plan, mine, work, log, background))
        path = ROUTES_DIR / f"{plan['id']}.json"
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            changed.append(path.name)
            if not args.check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8", newline="\n")
    work.mkdir(parents=True, exist_ok=True)
    (work / "route_paths.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(changed)} routes file(s) {'would change' if args.check else 'written'}: {', '.join(changed) or '-'}")
    if args.check and changed:
        sys.exit(1)


if __name__ == "__main__":
    main()
