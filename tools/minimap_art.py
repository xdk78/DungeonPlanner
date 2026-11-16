# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "pillow", "scipy", "scikit-image", "pycryptodome"]
# ///
"""Dungeon maps from the game's own minimap pictures: the table Data/MinimapArtData.lua.

WoW: Forever's new dungeons have no dungeon map in the client, but the client has their minimap pictures (the ones the
minimap draws in the corner of the screen): one picture per terrain tile, and for buildings and caves (WMOs) several
per building part. The addon draws a floor from those pictures at runtime, by file ID (`Texture:SetTexture(fileID)`);
nothing of them is shipped. This tool works out, offline and read-only on a local game install, which pictures make up
each floor of each instance and where each one lies, and writes only file IDs and numbers.

How (formats: wowdev.wiki ADT/v18, WDT, WMO, Minimap; the client's own tables):
  1. The instance map's WDT (its file ID is the map's WdtFileDataID in the client's Map table): its MAID chunk names
     each terrain tile's files, the eighth being the tile's minimap picture. Terrain tile (x, y) covers 533.33 yards;
     its north-west corner is (17066.67 - y * 533.33, 17066.67 - x * 533.33) in the game's (north, west) coordinates.
  2. Buildings: each terrain tile's object file (obj0, MODF chunk) places WMOs (position, yaw). The WMO's MOHD gives its
     WMO ID and MOGI each part's (group's) box. The client's table WMOMinimapTexture (DBFilesClient, file 1323241)
     lists every part's minimap pictures: (group, block x, block y) -> file ID; block (bx, by) covers 128 x 128 yards
     of the part's box from its minimum corner, x along the WMO's own x axis. A picture is drawn turned a quarter
     clockwise; local (x, y) maps to the world as (north, west) = position - R(yaw) * (x, y).
  3. A floor (data-src/minimaps.json): the terrain pictures ("adt") or some parts of one WMO ("wmo"), cut to a world
     rectangle: given, the box of what is drawn ("content"), or the rectangle Forever Dungeon Routes gives the floor
     ("fdr"); the plan's own points are always kept inside.
  4. Plan space -> map space. The recommended plans of the new dungeons were placed on Santiago Reyes' maps (the
     providers' pictures; docs/DATA-SOURCES.md). Forever Dungeon Routes (MIT) states for each of those pictures the
     affine "frame" world -> picture, fitted on the game's own encounter and area positions. The chain plan -> the
     provider's picture (Providers.Align, as the adapters draw it) -> world (that frame, inverted) -> our map gives an
     affine transform per floor (6 numbers), stored with the floor; the addon draws the plan through it. Classic floors
     whose plans are in the old dungeon map's space (Scholomance) use the game's map rectangle (UiMapAssignment, as
     Forever Dungeon Routes lists it) instead. The boss positions Forever Dungeon Routes gives are compared with the
     plan's after the transform (the log says how far apart they are, in yards).
  5. Preview pictures (map with the plan's route, stops and markers drawn on it) in the work folder, to check each floor
     by eye. Keep the work folder outside the repository: it holds game art.

Usage (from the repository root):
  uv run --script tools/minimap_art.py --game "<World of Warcraft>/_forever_" --work <scratch folder> \
      [--fdr <folder holding ForeverDungeonRoutes>] [--only slug,...] [--check]
--fdr defaults to the game's Interface/AddOns. --check writes nothing and exits 1 when Data/MinimapArtData.lua would change.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_routes as ir
import route_paths as rp

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "data-src" / "minimaps.json"
OUT = REPO / "Data" / "MinimapArtData.lua"
ADT = 1600.0 / 3.0  # yards per terrain tile
ORIGIN = 32.0 * ADT  # 17066.67: the north-west corner of terrain tile (0, 0)
BLOCK = 128.0  # yards per WMO minimap picture
WMO_MINIMAP_TEXTURE = 1323241  # DBFilesClient\WMOMinimapTexture.db2

# ---------------------------------------------------------------------------------------------------------------------
# Local storage: route_paths' reader, plus file data IDs of files without a name and encrypted parts.
#
# Forever's newest dungeons ship some files (their WDT, some WMOs) with encrypted BLTE chunks (mode "E", Salsa20). The
# client receives the keys as hotfixes of its TactKey table and keeps them in its cache (Cache\ADB\<locale>\DBCache.bin):
# this reader takes the keys from there, tries each on an encrypted chunk and keeps the one whose result
# decompresses. Nothing is fetched from anywhere; without the cache those files are simply missing.


def client_keys(game: Path):
    """The 16-byte keys in the client's hotfix cache (TactKey table, hash 0xDF2F53CF)."""
    keys = []
    for cache in sorted((game / "Cache" / "ADB").glob("*/DBCache.bin")):
        b = cache.read_bytes()
        if b[:4] != b"XFTH":
            continue
        p = 12 + 32
        while p + 32 <= len(b) and b[p : p + 4] == b"XFTH":
            table, _rid, size = struct.unpack_from("<III", b, p + 16)
            if table == 0xDF2F53CF and size == 16 and b[p + 32 : p + 48] not in keys:
                keys.append(b[p + 32 : p + 48])
            p += 32 + size
    return keys


def blte(data: bytes, keys, known):
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE")
    hsize = struct.unpack_from(">I", data, 4)[0]
    if hsize == 0:
        infos, pos = [(len(data) - 8, 0)], 8
    else:
        count = int.from_bytes(data[9:12], "big")
        infos = [struct.unpack_from(">II", data, 12 + 24 * i) for i in range(count)]
        pos = hsize
    out = []
    for index, (size, _dsize) in enumerate(infos):
        chunk = data[pos : pos + size]
        pos += size
        mode = chunk[:1]
        if mode == b"N":
            out.append(chunk[1:])
        elif mode == b"Z":
            out.append(zlib.decompress(chunk[1:]))
        elif mode == b"E":
            out.append(decrypt(chunk, index, keys, known))
        else:
            raise ValueError(f"BLTE chunk mode {mode!r}")
    return b"".join(out)


def decrypt(chunk: bytes, index: int, keys, known):
    from Crypto.Cipher import Salsa20

    n = chunk[1]
    name = chunk[2 : 2 + n]
    p = 2 + n
    iv = bytearray(chunk[p + 1 : p + 1 + chunk[p]])
    p += 1 + chunk[p]
    if chunk[p : p + 1] != b"S":
        raise ValueError("encryption type")
    for i in range(min(4, len(iv))):
        iv[i] ^= (index >> (8 * i)) & 0xFF
    nonce = bytes(iv).ljust(8, b"\0")
    for key in ([known[name]] if name in known else keys):
        plain = Salsa20.new(key=key, nonce=nonce).decrypt(chunk[p + 1 :])
        try:
            if plain[:1] == b"Z":
                result = zlib.decompress(plain[1:])
            elif plain[:1] == b"N":
                result = plain[1:]
            else:
                continue
        except zlib.error:
            continue
        known[name] = key
        return result
    raise ValueError(f"no key for {name[::-1].hex()}")


class Casc(rp.Casc):
    def __init__(self, game: Path):
        self.keys, self.known = client_keys(Path(game)), {}
        super().__init__(game)

    def _read_ekey(self, ekey: bytes) -> bytes:
        archive, off, size = self.index[ekey[:9]]
        with open(self.data / "data" / f"data.{archive:03d}", "rb") as f:
            f.seek(off)
            return blte(f.read(size)[30:], self.keys, self.known)

    def _root(self):
        super()._root()
        r = self._read_ekey(self._ekey(bytes.fromhex(self.cfg["root"][0])))
        a, b = struct.unpack_from("<II", r, 4)
        version, p = 0, 12
        total, named = a, b
        if a == 0x18 and b in (1, 2):
            version = b
            total, named = struct.unpack_from("<II", r, 12)
            p = 24
        nameless_ok = total != named
        self.by_fid = {}
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
            if not (nameless_ok and content & 0x10000000):
                p += 8 * n
            if locale & 0x2 and not content & 0x80:
                fid = -1
                for i in range(n):
                    fid += 1 + deltas[i]
                    self.by_fid.setdefault(fid, r[ckeys + 16 * i : ckeys + 16 * i + 16])

    def read_fid(self, fid: int):
        """A file's bytes by file data ID; None when unknown, not downloaded or encrypted with a key we lack."""
        ck = self.by_fid.get(int(fid))
        ek = ck and self._ekey(ck)
        if not ek:
            return None
        try:
            return self._read_ekey(ek)
        except (ValueError, TypeError, KeyError):
            return None


def chunks(b: bytes):
    p = 0
    while p + 8 <= len(b):
        tag = b[p : p + 4][::-1].decode("latin1")
        n = struct.unpack_from("<I", b, p + 4)[0]
        yield tag, b[p + 8 : p + 8 + n]
        p += 8 + n


# ---------------------------------------------------------------------------------------------------------------------
# WDC3/4/5 tables: only what WMOMinimapTexture needs (inline fields, pallets, the relationship column).


def wmo_minimap_table(raw: bytes):
    """{wmoID: {(group, bx, by): fileID}} from WMOMinimapTexture.db2."""
    magic = raw[:4]
    p = 4 + (132 if magic == b"WDC5" else 0)
    (_rc, field_count, rec_size, _st, _th, _lh, _mn, _mx, _loc, _fl, _idi, _tfc, _bpo, _lc, storage_size,
     _cs, _ps, section_count) = struct.unpack_from("<9I2H7I", raw, p)
    p += 9 * 4 + 4 + 7 * 4
    sections = []
    for _ in range(section_count):
        s = struct.unpack_from("<Q8I", raw, p)
        p += 40
        sections.append({"offset": s[1], "records": s[2], "strings": s[3], "id_list": s[5], "relationship": s[6], "copies": s[8]})
    p += 4 * field_count
    storage = [struct.unpack_from("<HHIIIII", raw, p + 24 * i) for i in range(storage_size // 24)]
    p += storage_size
    pallets, at = {}, p
    for i, st in enumerate(storage):
        if st[3] in (3, 4):
            pallets[i] = raw[at : at + st[2]]
            at += st[2]

    def bits(rec, off, size):
        start, end = off >> 3, (off + size + 7) >> 3
        return (int.from_bytes(rec[start:end], "little") >> (off & 7)) & ((1 << size) - 1)

    def field(rec, i):
        off, size, _extra, kind = storage[i][:4]
        v = bits(rec, off, size)
        if kind == 3:
            return struct.unpack_from("<I", pallets[i], 4 * v)[0]
        return v

    out = {}
    for s in sections:
        q = s["offset"]
        recs = [raw[q + i * rec_size : q + (i + 1) * rec_size] for i in range(s["records"])]
        q += s["records"] * rec_size + s["strings"] + s["id_list"] + s["copies"] * 8
        rel = {}
        if s["relationship"]:
            n = struct.unpack_from("<I", raw, q)[0]
            for k in range(n):
                fk, idx = struct.unpack_from("<II", raw, q + 12 + 8 * k)
                rel[idx] = fk
        for i, rec in enumerate(recs):
            wmo = rel.get(i)
            if wmo is None:
                continue
            group, bx, by, fid = (field(rec, j) for j in range(4))
            out.setdefault(wmo, {})[(group, bx & 0xFF, by & 0xFF)] = fid
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Terrain and buildings.


class World:
    def __init__(self, casc: Casc):
        self.casc = casc
        self._wmt = None
        self._images = {}

    def wdt(self, wdt_fid: int):
        raw = self.casc.read_fid(wdt_fid)
        if raw is None:
            raise SystemExit(f"WDT {wdt_fid} is not in the local storage")
        tiles = {}
        for tag, d in chunks(raw):
            if tag == "MAID":
                ids = struct.unpack_from(f"<{len(d) // 4}I", d)
                for i in range(len(ids) // 8):
                    if any(ids[8 * i : 8 * i + 8]):
                        tiles[(i % 64, i // 64)] = ids[8 * i : 8 * i + 8]
        return tiles

    def placements(self, wdt_fid: int):
        """Every WMO placement on the map: {uid: (wmo file ID, (north, west), height, yaw)}."""
        out = {}
        for ids in self.wdt(wdt_fid).values():
            raw = ids[1] and self.casc.read_fid(ids[1])
            for tag, d in chunks(raw or b""):
                if tag != "MODF":
                    continue
                for k in range(len(d) // 64):
                    fid, uid = struct.unpack_from("<II", d, 64 * k)
                    x, h, z = struct.unpack_from("<3f", d, 64 * k + 8)
                    yaw = struct.unpack_from("<3f", d, 64 * k + 20)[1]
                    out.setdefault(uid, (fid, (ORIGIN - z, ORIGIN - x), h, yaw))
        return out

    def wmo(self, fid: int):
        raw = self.casc.read_fid(fid)
        if raw is None:
            raise SystemExit(f"WMO {fid} is not in the local storage")
        info = {"groups": [], "names": []}
        names = b""
        for tag, d in chunks(raw):
            if tag == "MOHD":
                v = struct.unpack_from("<7I I I 6f", d)
                info["wmoID"] = v[8]
            elif tag == "MOGN":
                names = d
            elif tag == "MOGI":
                for k in range(len(d) // 32):
                    fl = struct.unpack_from("<I", d, 32 * k)[0]
                    bb = struct.unpack_from("<6f", d, 32 * k + 4)
                    no = struct.unpack_from("<i", d, 32 * k + 28)[0]
                    name = names[no : names.index(b"\0", no)].decode("utf-8", "replace") if 0 <= no < len(names) else ""
                    info["groups"].append({"flags": fl, "box": bb, "name": name})
        return info

    def wmo_minimaps(self, wmo_id: int):
        if self._wmt is None:
            self._wmt = wmo_minimap_table(self.casc.read_fid(WMO_MINIMAP_TEXTURE))
        return self._wmt.get(wmo_id, {})

    def image(self, fid: int):
        if fid not in self._images:
            raw = self.casc.read_fid(fid)
            try:
                self._images[fid] = Image.open(io.BytesIO(raw)).convert("RGBA") if raw else None
            except Exception:  # noqa: BLE001
                self._images[fid] = None
        return self._images[fid]


# A piece: one picture placed in the world: its texture corner (0, 0) at o, its u and v axes (both in (north, west)).


def adt_pieces(world: World, wdt_fid: int):
    out = []
    for (tx, ty), ids in sorted(world.wdt(wdt_fid).items()):
        if ids[7]:
            out.append({"fid": ids[7], "o": (ORIGIN - ty * ADT, ORIGIN - tx * ADT), "u": (0.0, -ADT), "v": (-ADT, 0.0)})
    return out


def wmo_pieces(world: World, wdt_fid: int, wmo_fid: int, groups=None, uid=None):
    places = [p for u, p in world.placements(wdt_fid).items() if p[0] == wmo_fid and (uid is None or u == uid)]
    if not places:
        raise SystemExit(f"WMO {wmo_fid} is not placed on the map of WDT {wdt_fid}")
    _fid, P, _h, yaw = places[0]
    info = world.wmo(wmo_fid)
    t = math.radians(yaw)
    ct, st = math.cos(t), math.sin(t)

    def w(lx, ly):
        return (P[0] - (ct * lx - st * ly), P[1] - (st * lx + ct * ly))

    out = []
    for (g, bx, by), fid in sorted(world.wmo_minimaps(info["wmoID"]).items()):
        if groups is not None and g not in groups:
            continue
        box = info["groups"][g]["box"]
        lx0, ly0 = box[0] + BLOCK * bx, box[1] + BLOCK * by
        o, ou, ov = w(lx0, ly0 + BLOCK), w(lx0 + BLOCK, ly0 + BLOCK), w(lx0, ly0)
        out.append({"fid": fid, "o": o, "u": (ou[0] - o[0], ou[1] - o[1]), "v": (ov[0] - o[0], ov[1] - o[1]),
                    "group": g, "z": box[5]})
    return out


# ---------------------------------------------------------------------------------------------------------------------
# A floor's rectangle (north max, west max, north min, west min) and its pieces in map space.


def corners(p):
    o, u, v = p["o"], p["u"], p["v"]
    return [o, (o[0] + u[0], o[1] + u[1]), (o[0] + v[0], o[1] + v[1]), (o[0] + u[0] + v[0], o[1] + u[1] + v[1])]


def render(world: World, pieces, rect, scale=1.0, bg=(0, 0, 0, 0)):
    """The floor as it will look in the addon, scale px per yard (pieces in order, later ones on top)."""
    nmax, wmax, nmin, wmin = rect
    W, H = max(1, round((wmax - wmin) * scale)), max(1, round((nmax - nmin) * scale))
    canvas = Image.new("RGBA", (W, H), bg)
    for p in pieces:
        im = world.image(p["fid"])
        if im is None:
            continue
        tw, th = im.size

        def cp(nw):
            return ((wmax - nw[1]) * scale, (nmax - nw[0]) * scale)

        c = [cp(q) for q in corners(p)]
        o, ou, ov = c[0], c[1], c[2]
        A = np.array([[(ou[0] - o[0]) / tw, (ov[0] - o[0]) / th], [(ou[1] - o[1]) / tw, (ov[1] - o[1]) / th]])
        inv = np.linalg.inv(A)
        x0, y0 = math.floor(min(q[0] for q in c)), math.floor(min(q[1] for q in c))
        x1, y1 = math.ceil(max(q[0] for q in c)), math.ceil(max(q[1] for q in c))
        if x1 <= 0 or y1 <= 0 or x0 >= W or y0 >= H:
            continue
        a, b = inv[0]
        d, e = inv[1]
        cc = -(a * (o[0] - x0) + b * (o[1] - y0))
        f = -(d * (o[0] - x0) + e * (o[1] - y0))
        patch = im.transform((x1 - x0, y1 - y0), Image.Transform.AFFINE, (a, b, cc, d, e, f),
                             resample=Image.Resampling.BILINEAR, fillcolor=(0, 0, 0, 0))
        canvas.alpha_composite(patch, (max(0, x0), max(0, y0)), (max(0, -x0), max(0, -y0)))
    return canvas


def content_rect(world: World, pieces):
    """The world box of what is drawn: pixels unlike the pictures' plain background (the most common edge colour)."""
    box = [-1e9, -1e9, 1e9, 1e9]
    for p in pieces:
        c = corners(p)
        box = [max(box[0], max(q[0] for q in c)), max(box[1], max(q[1] for q in c)),
               min(box[2], min(q[0] for q in c)), min(box[3], min(q[1] for q in c))]
    scale = 0.25
    img = np.asarray(render(world, pieces, box, scale))
    rgb, alpha = img[:, :, :3].astype(int), img[:, :, 3]
    edge = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    vals, counts = np.unique(edge // 4, axis=0, return_counts=True)
    bg = vals[counts.argmax()] * 4 + 2
    drawn = (alpha > 0) & (np.abs(rgb - bg).sum(2) > 24)
    ys, xs = np.nonzero(drawn)
    if not len(xs):
        return box
    return [box[0] - ys.min() / scale, box[1] - xs.min() / scale, box[0] - (ys.max() + 1) / scale,
            box[1] - (xs.max() + 1) / scale]


def map_pieces(pieces, rect):
    """Pieces in map units (yards from the rectangle's north-west corner): the axis-aligned box each covers, cut to
    the map, and the texture coordinates at that box's corners (upper left, lower left, upper right, lower right)."""
    nmax, wmax, nmin, wmin = rect
    W, H = wmax - wmin, nmax - nmin
    out = []
    for p in pieces:
        c = [((wmax - q[1]), (nmax - q[0])) for q in corners(p)]
        x0, x1 = max(0.0, min(q[0] for q in c)), min(W, max(q[0] for q in c))
        y0, y1 = max(0.0, min(q[1] for q in c)), min(H, max(q[1] for q in c))
        if x1 - x0 < 0.5 or y1 - y0 < 0.5:
            continue
        o = np.array(c[0])
        A = np.array([[c[1][0] - o[0], c[2][0] - o[0]], [c[1][1] - o[1], c[2][1] - o[1]]])
        inv = np.linalg.inv(A)

        def tex(x, y, inv=inv, o=o):
            u, v = inv @ (np.array([x, y]) - o)
            return [round(float(u), 4), round(float(v), 4)]

        out.append({"fid": p["fid"], "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)],
                    "tex": tex(x0, y0) + tex(x0, y1) + tex(x1, y0) + tex(x1, y1)})
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Plan space -> world.


def affine_fit(src, dst):
    """Least-squares affine dst = M @ [x, y, 1]: (a, b, c, d, e, f) with x' = a x + b y + c, y' = d x + e y + f."""
    X = np.array([[x, y, 1.0] for x, y in src])
    Y = np.array(dst, dtype=float)
    sol, *_ = np.linalg.lstsq(X, Y, rcond=None)
    return [float(sol[0, 0]), float(sol[1, 0]), float(sol[2, 0]), float(sol[0, 1]), float(sol[1, 1]), float(sol[2, 1])]


def apply(m, x, y):
    return m[0] * x + m[1] * y + m[2], m[3] * x + m[4] * y + m[5]


def frame_inverse(fr):
    """Forever Dungeon Routes' frame (u = a N + b W + c, v = d N + e W + f) turned around: (u, v) -> (N, W)."""
    a, b, c, d, e, f = fr
    det = a * e - b * d
    return lambda u, v: ((e * (u - c) - b * (v - f)) / det, (-d * (u - c) + a * (v - f)) / det)


def plan_to_world(entry, plan, fdr, fdj, game, log):
    """A function plan (x, y) -> world (north, west) for this floor, and a description, or (None, reason)."""
    fl = entry["floor"]
    src = entry.get("planSpace", "provider")
    info = fdr["floors"].get(entry.get("fdr")) if entry.get("fdr") else None
    if src == "uimap":
        if not info or not info.get("world"):
            return None, "no world rectangle for its old map"
        n0, w0, n1, w1 = info["world"]  # minX (north), minY (west), maxX, maxY
        return (lambda x, y: (n1 - y * (n1 - n0), w1 - x * (w1 - w0))), f"old map rectangle (FDR floor {entry['fdr']})"
    if not info or not info.get("frame"):
        return None, "no frame for its provider picture"
    inv = frame_inverse(info["frame"])
    got = rp.provider_floor(game, fdj, {}, plan, fl)
    if not got:
        return None, "no provider picture to align with"
    img, source, pins = got
    theirs = ir.picture_of(Path(entry["_fdr_root"]), info)
    r = ir.same_picture(img, theirs) if theirs is not None else 0.0
    if r < 0.9:
        return None, f"{source} is not Forever Dungeon Routes' picture (r={r:.2f})"
    sx, tx, sy, ty, mode = rp.align(plan, fl, pins)
    return (lambda x, y: inv(x * sx + tx, y * sy + ty)), f"{source} ({mode}, r={r:.3f}) + its frame"


# ---------------------------------------------------------------------------------------------------------------------
# Previews and output.


def plan_points(plan, floor):
    pts = []
    for m in plan.get("markers", []):
        if m.get("floor") == floor:
            pts.append((m["x"], m["y"], m.get("kind"), m.get("label") or ""))
    for r in plan.get("routes", []):
        if r.get("floor") == floor:
            for p in r["points"]:
                pts.append((p["x"], p["y"], "stop" if p.get("step") else "bend", ""))
    return pts


def preview(world, pieces, rect, plan, floor, xf, fdr_bosses, path: Path):
    scale = min(2.0, 1400.0 / max(rect[1] - rect[3], rect[0] - rect[2]))
    img = render(world, pieces, rect, scale, bg=(24, 22, 20, 255)).convert("RGB")
    d = ImageDraw.Draw(img)
    W, H = img.size

    def px(x, y):
        u, v = apply(xf, x, y)
        return u * W, v * H

    for r in plan.get("routes", []):
        if r.get("floor") == floor:
            line = [px(p["x"], p["y"]) for p in r["points"]]
            if len(line) > 1:
                d.line(line, fill=(255, 210, 60), width=3)
            for p in r["points"]:
                if p.get("step"):
                    x, y = px(p["x"], p["y"])
                    d.ellipse((x - 5, y - 5, x + 5, y + 5), outline=(255, 210, 60), width=2)
    for m in plan.get("markers", []):
        if m.get("floor") == floor:
            x, y = px(m["x"], m["y"])
            col = (230, 60, 60) if m.get("kind") == "boss" else (90, 200, 255)
            d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=col, outline=(0, 0, 0))
            if m.get("label"):
                d.text((x + 9, y - 6), m["label"], fill=(255, 255, 255))
    for b in fdr_bosses:
        x, y = b["px"][0] * W, b["px"][1] * H
        d.rectangle((x - 5, y - 5, x + 5, y + 5), outline=(80, 255, 120), width=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def lua_number(v):
    s = f"{v:.6g}" if abs(v) < 1 else f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def write_lua(floors):
    lines = [
        "-- Generated by tools/minimap_art.py from the game's own files (data-src/minimaps.json says which). Do not edit.",
        "-- Maps of floors that have no map art in the client, composed at runtime from the client's minimap pictures,",
        "-- by file ID: nothing of them is shipped (Data/MinimapArt.lua draws them; docs/COMPATIBILITY.md section 9).",
        "--",
        "-- [instance key] = { [plan floor] = { w, h (map size in yards), source (\"terrain\" or \"building\"),",
        "--   xf = { a, b, c, d, e, f }: plan (x, y) -> map (a x + b y + c, d x + e y + f), both 0..1,",
        "--   pieces = { { fileID, x, y, w, h (yards from the map's top left), ULx, ULy, LLx, LLy, URx, URy, LRx, LRy }, ... } } }",
        "",
        "local _, ns = ...",
        "ns.MinimapArtData = {",
    ]
    by_key = {}
    for f in floors:
        by_key.setdefault(f["key"], []).append(f)
    for key in sorted(by_key):
        lines.append(f"\t{key} = {{")
        for f in sorted(by_key[key], key=lambda f: f["floor"]):
            xf = ", ".join(lua_number(v) for v in f["xf"])
            lines.append(f"\t\t[{f['floor']}] = {{ w = {lua_number(f['w'])}, h = {lua_number(f['h'])}, source = \"{f['source']}\",")
            lines.append(f"\t\t\t-- {f['note']}")
            lines.append(f"\t\t\txf = {{ {xf} }},")
            lines.append("\t\t\tpieces = {")
            for p in f["pieces"]:
                nums = ", ".join(lua_number(v) for v in p["rect"] + p["tex"])
                lines.append(f"\t\t\t\t{{ {p['fid']}, {nums} }},")
            lines.append("\t\t\t},")
            lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game", required=True, type=Path, help="the game folder that holds Interface/AddOns (e.g. _forever_)")
    ap.add_argument("--work", required=True, type=Path, help="scratch folder for the preview pictures")
    ap.add_argument("--fdr", type=Path, help="folder holding ForeverDungeonRoutes (default: the game's Interface/AddOns)")
    ap.add_argument("--only", default="", help="comma-separated plan slugs (others are kept as they are)")
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 when Data/MinimapArtData.lua would change")
    args = ap.parse_args(argv)
    work = args.work.resolve()
    if REPO in work.parents:
        raise SystemExit("keep --work outside the repository: it holds game art")
    fdr_root = (args.fdr or args.game / "Interface" / "AddOns").resolve()
    only = {s for s in args.only.split(",") if s}
    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    plans, _instances = rp.load_repo()
    by_slug = {p["id"]: p for p in plans}
    casc = Casc(args.game)
    world = World(casc)
    fdj = rp.fdj_maps(args.game)
    fdr = ir.load_fdr(fdr_root)
    log_lines = []

    def log(s):
        log_lines.append(s)
        print(s)

    floors = []
    for entry in cfg["floors"]:
        slug, fl = entry["slug"], entry["floor"]
        plan = by_slug.get(slug)
        if plan is None:
            raise SystemExit(f"{slug}: no such plan")
        key = rp.strip_article(plan["instance"]["name"])
        if only and slug not in only:
            continue
        entry["_fdr_root"] = str(fdr_root)
        if entry["source"] == "terrain":
            pieces = adt_pieces(world, entry["wdt"])
        else:
            pieces = wmo_pieces(world, entry["wdt"], entry["wmo"], set(entry["groups"]) if entry.get("groups") else None)
            pieces.sort(key=lambda p: (p["z"], p["group"]))
        to_world, how = plan_to_world(entry, plan, fdr, fdj, args.game, log)
        if to_world is None:
            log(f"{slug} floor {fl}: left out: {how}")
            continue
        pts = plan_points(plan, fl)
        wpts = [to_world(x, y) for x, y, *_ in pts]
        mode = entry.get("rect", "content")
        if isinstance(mode, list):
            rect = list(mode)
        elif mode == "fdr":
            n0, w0, n1, w1 = fdr["floors"][entry["fdr"]]["world"]
            rect = [n1, w1, n0, w0]
        else:
            rect = content_rect(world, pieces)
        for n, w in wpts:
            rect = [max(rect[0], n), max(rect[1], w), min(rect[2], n), min(rect[3], w)]
        pad = entry.get("pad", 0.04) * max(rect[0] - rect[2], rect[1] - rect[3])
        rect = [round(rect[0] + pad, 1), round(rect[1] + pad, 1), round(rect[2] - pad, 1), round(rect[3] - pad, 1)]
        W, H = rect[1] - rect[3], rect[0] - rect[2]

        def to_map(n, w, rect=rect, W=W, H=H):
            return (rect[1] - w) / W, (rect[0] - n) / H

        grid = [(x / 4, y / 4) for x in range(5) for y in range(5)]
        xf = affine_fit(grid, [to_map(*to_world(x, y)) for x, y in grid])
        # Forever Dungeon Routes' own boss positions on this floor, through its frame, against the plan's bosses.
        fdr_bosses = []
        info = fdr["floors"].get(entry.get("fdr")) if entry.get("fdr") else None
        if info and info.get("frame"):
            inv = frame_inverse(info["frame"])
            for stop in ir_stops(fdr, entry["fdr"]):
                n, w = inv(stop["x"], stop["y"])
                fdr_bosses.append({"name": stop["name"], "px": to_map(n, w)})
        dists = []
        for m in plan.get("markers", []):
            if m.get("floor") == fl and m.get("kind") == "boss":
                k = rp.strip_article(m.get("label") or "")
                hit = next((b for b in fdr_bosses if rp.strip_article(b["name"]) == k), None)
                if hit:
                    u, v = apply(xf, m["x"], m["y"])
                    dists.append(math.hypot((u - hit["px"][0]) * W, (v - hit["px"][1]) * H))
        mp = map_pieces(pieces, rect)
        note = f"{entry['source']} {entry['map']}" + (f" WMO {entry['wmo']}" if entry.get("wmo") else "") + f"; plan via {how}"
        dtext = f"; FDR bosses within {max(dists):.1f} yd (mean {sum(dists) / len(dists):.1f})" if dists else ""
        log(f"{slug} floor {fl}: {len(mp)} pictures, {W:.0f} x {H:.0f} yd{dtext}; {note}")
        preview(world, pieces, rect, plan, fl, xf, fdr_bosses, work / f"minimap-{slug}-{fl}.png")
        floors.append({"key": key, "floor": fl, "w": W, "h": H, "xf": xf, "pieces": mp, "note": note,
                       "source": "terrain" if entry["source"] == "terrain" else "building"})
    text = write_lua(floors)
    work.mkdir(parents=True, exist_ok=True)
    (work / "minimap_art.log").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    if only:
        print("--only: Data/MinimapArtData.lua not written (run without --only to write it)")
        return
    old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    if old != text:
        if args.check:
            print("Data/MinimapArtData.lua would change")
            sys.exit(1)
        OUT.write_text(text, encoding="utf-8", newline="\n")
        print("Data/MinimapArtData.lua written")
    else:
        print("Data/MinimapArtData.lua unchanged")


def ir_stops(fdr, floor_id):
    """Boss stops of Forever Dungeon Routes' default routes on one of its floors: [{name, x, y}]."""
    out = []
    routes = fdr.get("routes") or fdr.get("DefaultRoutes") or {}
    items = routes.values() if isinstance(routes, dict) else routes
    for r in items:
        for s in (r.get("stops") or []) if isinstance(r, dict) else []:
            if s.get("floor") == floor_id and s.get("kind", "boss") == "boss" and "x" in s:
                out.append({"name": s.get("name") or "", "x": s["x"], "y": s["y"]})
    return out


if __name__ == "__main__":
    main()
