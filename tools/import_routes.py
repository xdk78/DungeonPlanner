# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "pillow", "scipy", "scikit-image"]
# ///
"""Import the routes of Forever Dungeon Routes (MIT) into the recommended plans' route files.

Forever Dungeon Routes (https://github.com/Checkov23/ForeverDungeonRoutes, MIT, Copyright (c) 2026 Checkov23) draws a
route for every dungeon and raid: dense main paths, side paths and stops. This tool reads a local clone of it (a path
given as an argument, never fixed in the code) and writes, per recommended plan, into data-src/routes/<slug>.json:

  * "import": positions for the research's estimated or unplaced points where one of its stops is the same boss or
    spot (by name, a name the game uses that its note gives, or nearness), stops our research lacks (inserted after
    the step before them), its side paths (optional routes) and a credit line for the plan's notes;
  * legs (marked "import") with its path between our consecutive stops on a floor. On the classic maps, where a
    stretch of its path runs off our walkable mask over bare parchment (close to the blank parchment median of all the
    old dungeon maps) or water (grey-green or blue), only that stretch is re-routed with our pathfinder
    (tools/route_paths.py) and logged; a stretch it cannot mend leaves that whole leg to our computed bends, a side
    path is then left out. The block's "check" counts what was done. Legs its route does not cover are computed by
    tools/route_paths.py as before, in the same run.

Every route it ships is imported. Its classic dungeon routes say they were traced from the aetherflask.com walkthrough
maps (mirrored at eintr.net); the import block of those plans records that ("traced"), as docs/DATA-SOURCES.md does.
Its pictures are read only to check that they are the same pictures our plans are drawn on (Santiago Reyes' maps, not
under its MIT licence): nothing of them is written.

Coordinates: classic floors are the game's dungeon map tiles in both addons, matched by the file ID of the first tile
(the game's own map tables, read from the local storage); Forever floors are matched by name like Data/Providers.lua
does, their pictures compared with ours, and brought into plan space through the same alignment the adapters use.

Usage (from the repository root):
  uv run --script tools/import_routes.py --fdr <clone of ForeverDungeonRoutes> --game "<World of Warcraft>/_forever_" \
      --work <scratch folder> [--only slug,...] [--check]
It runs `lua tools/gen_plans.lua` and `lua tools/gen_spawns.lua` itself (except with --check). The work folder gets a
before/after sheet per imported floor (fdr-preview/) and a log; keep it outside the repository.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import route_paths as rp  # noqa: E402

SOURCE_NAME = "Forever Dungeon Routes"
SOURCE_URL = "https://github.com/Checkov23/ForeverDungeonRoutes"
NOTE = "Route: Forever Dungeon Routes (MIT), by Checkov23."
TRACED = ("aetherflask", "eintr.net")  # its classic routes say they were traced from these walkthrough maps
NEAR = 0.035  # plan units: a stop this close to its path is on it; two stops this close are the same spot
FIX_RUN = 4  # px: a stretch of path at least this long over parchment or water is re-routed

LUA_DUMP = r"""
local root = arg[1]
local DR = {}
for _, f in ipairs({ "Dungeons", "Floors", "DefaultRoutes", "Rooms", "Pictures" }) do
  assert(loadfile(root .. "/ForeverDungeonRoutes/Data/" .. f .. ".lua"))("ForeverDungeonRoutes", DR)
end
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
local version = "?"
local toc = io.open(root .. "/ForeverDungeonRoutes/ForeverDungeonRoutes.toc", "rb")
if toc then version = (toc:read("*a"):match("## Version:%s*([^\r\n]+)") or "?"); toc:close() end
io.write(enc({ dungeons = DR.Dungeons, floors = DR.Floors, routes = DR.DefaultRoutes, version = version }))
"""


def load_fdr(root: Path):
    out = subprocess.run(
        ["lua", "-", str(root)], input=LUA_DUMP, capture_output=True, text=True, encoding="utf-8", check=True
    ).stdout
    data = json.loads(out)
    data["floors"] = {int(k): v for k, v in data["floors"].items()}
    return data


def traced(route):
    """Does its route say it was traced from another site's maps (its classic dungeon routes)? Recorded with the import."""
    src = (route.get("source") or "").lower()
    return any(x in src for x in TRACED)


def pick_route(entry, research=None):
    """One route of a dungeon: a single route; of several the one whose stops name the most of the research's bosses
    (Stratholme's living or undead side, Maraudon's purple or orange), then the full clear, then the first."""
    routes = entry if isinstance(entry, list) else [entry]
    names = [p["name"] for p in (research or {}).get("points", []) if p.get("kind") in ("boss", "rare")]

    def score(r):
        hits = sum(1 for n in names if any(names_match(n, st) for st in stops_of(r)))
        return (hits, str(r.get("id", "")).endswith(":full"))

    return max(routes, key=score) if len(routes) > 1 else routes[0]


def stops_of(route):
    return [
        {"name": s.get("name") or "", "note": s.get("note") or "", "kind": s.get("kind") or "boss"}
        for s in route.get("stops") or []
    ]


def norm_key(instances, name):
    k = rp.strip_article(name)
    spec = instances.get(k)
    return spec["alias"] if spec and spec.get("alias") else k


# ---------------------------------------------------------------------------------------------------------------------
# Floors and coordinates.


def picture_of(fdr_root: Path, floor):
    image = floor.get("image")
    if not image:
        return None
    path = fdr_root / "ForeverDungeonRoutes" / (image["file"].replace("\\", "/") + ".blp")
    if not path.exists():
        return None
    img = Image.open(path).convert("RGB")
    w, h = img.size
    return img.crop((0, 0, round(w * image.get("right", 1)), round(h * image.get("bottom", 1))))


def same_picture(a: Image.Image, b: Image.Image):
    """Correlation of two pictures at one size: ~1 for the same picture in the same frame."""
    ga = np.asarray(a.resize((300, 200)).convert("L"), np.float32).ravel()
    gb = np.asarray(b.resize((300, 200)).convert("L"), np.float32).ravel()
    return float(np.corrcoef(ga, gb)[0, 1])


def floor_map(fdr, fdr_root, dungeon, plan, pictures, casc, instances, log):
    """{fdr floor id: (plan floor, to_plan)}: to_plan maps its 0..1 coordinates to the plan's."""
    out = {}
    bases = rp.tile_bases(instances, plan)
    fids = {}
    for i, base in enumerate(bases):
        fid = casc.file_id(f"Interface\\WorldMap\\{base}1.blp")
        if fid:
            fids[fid] = i + 1
    picture_floors = [f for f in dungeon["floors"] if fdr["floors"].get(f, {}).get("image")]
    for fid_floor in dungeon["floors"]:
        info = fdr["floors"].get(fid_floor) or {}
        if info.get("tiles"):
            pf = fids.get(info["tiles"][0])
            if pf:
                out[fid_floor] = (pf, lambda x, y: (x, y))
    # Picture floors: the plan floor whose provider picture the adapters pick by name (Providers.PickFloor).
    if picture_floors:
        cands = [(fdr["floors"][f].get("name"), fdr["floors"][f]["image"]["file"]) for f in picture_floors]
        for i, pfl in enumerate(plan["floors"]):
            if not pfl.get("name"):
                continue
            j = rp.pick_floor(pfl["name"], i + 1, cands)
            if j is None:
                continue
            fid_floor = picture_floors[j]
            img, source, xf = pictures.get((plan["id"], i + 1), (None, None, None))
            if img is None:
                img, source, xf = pictures.get(("__any__", plan["id"], i + 1), (None, None, None))
            theirs = picture_of(fdr_root, fdr["floors"][fid_floor])
            if img is None or theirs is None:
                log(f"{plan['id']} floor {i + 1}: no picture to compare with its {cands[j][0]!r}; not imported")
                continue
            c = same_picture(img, theirs)
            if c < 0.9:
                log(
                    f"{plan['id']} floor {i + 1}: its picture of {cands[j][0]!r} is not ours ({source}, r={c:.2f}); "
                    "not imported"
                )
                continue
            sx, tx, sy, ty, mode = xf
            out[fid_floor] = (
                i + 1,
                (lambda sx, tx, sy, ty: lambda x, y: ((x - tx) / sx, (y - ty) / sy))(sx, tx, sy, ty),
            )
            log(
                f"{plan['id']} floor {i + 1}: {cands[j][0]!r} is the same picture as {source} (r={c:.3f}), "
                f"alignment {mode}"
            )
    return out


def pairs(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat) - 1, 2)]


def convert(route, fmap):
    """Its main path pieces, side paths and stops in plan space: ({floor: [polyline]}, [side], [stop])."""
    main, sides, stops = {}, [], []
    for p in route.get("paths") or []:
        hit = fmap.get(p.get("floor"))
        if not hit:
            continue
        pf, f = hit
        pts = [f(x, y) for x, y in pairs(p.get("pts") or [])]
        if len(pts) < 2:
            continue
        if p.get("kind") == "side":
            sides.append({"floor": pf, "name": p.get("title") or "Side path", "points": pts})
        else:
            main.setdefault(pf, []).append(pts)
    for s in route.get("stops") or []:
        hit = fmap.get(s.get("floor"))
        if hit:
            pf, f = hit
            x, y = f(s["x"], s["y"])
            stops.append(
                {
                    "floor": pf,
                    "x": x,
                    "y": y,
                    "name": s.get("name") or "",
                    "kind": s.get("kind") or "boss",
                    "note": s.get("note") or "",
                }
            )
    return main, sides, stops


# ---------------------------------------------------------------------------------------------------------------------
# Matching its stops with the research's steps.


def other_names(stop):
    """Names its note gives the stop: "Called Magmatus in the game" -> Magmatus."""
    return [m.group(1).strip() for m in re.finditer(r"[Cc]alled ([^;,.()]+?) in the game", stop["note"])]


def names_match(ours, stop):
    a = rp.strip_article(ours)
    if not a:
        return False
    for name in [stop["name"]] + other_names(stop):
        b = rp.strip_article(name)
        if a == b or (min(len(a), len(b)) >= 5 and (a in b or b in a)):
            return True
    # Its note names our boss ("Izha'Rel and Tor'Rel, north-east of ..." for its "Ravasaur Hunters").
    return len(a) >= 6 and a in rp.strip_article(stop["note"])


KIND_OK = {"boss": {"boss", "rare"}, "optional": {"boss", "rare", "quest_npc", "interactive"}, "rare": {"rare", "boss"}}


def on_paths(stop, main, sides):
    """Is a stop on its own paths (main or side, same floor)? A rare off them is a detour its route does not take."""
    polys = list(main.get(stop["floor"], [])) + [s["points"] for s in sides if s["floor"] == stop["floor"]]
    return any(c[0] <= NEAR for poly in polys for c in _closest(poly, (stop["x"], stop["y"])))


def match_stops(research, stops, approx, log, slug, main=None, sides=(), void=None):
    """fill, add (the import block's lists) and a log of what matched. Stops our research lacks are added when they lie
    on its paths. void(floor, x, y): a stop there (on the blank parchment off a classic map's art) is not used."""
    points = {p["id"]: p for p in research["points"]}
    # Steps inside the dungeon: on a floor, or on none yet (research that knew the order but not the floor).
    steps = [
        s
        for s in research.get("route") or []
        if s.get("floor") is None or (isinstance(s["floor"], int) and s["floor"] >= 1)
    ]
    used, matched = set(), {}
    # By name first, then by nearness.
    for k, st in enumerate(stops):
        for s in steps:
            p = points.get(s.get("point"))
            if s["step"] in used or not p:
                continue
            if names_match(p["name"], st) and p["kind"] in KIND_OK.get(st["kind"], {"boss"}):
                used.add(s["step"])
                matched[k] = s
                break
    for k, st in enumerate(stops):
        if k in matched:
            continue
        for s in steps:
            p = points.get(s.get("point"))
            if s["step"] in used or not p or s.get("x") is None or s["floor"] != st["floor"]:
                continue
            if math.hypot(s["x"] - st["x"], s["y"] - st["y"]) <= NEAR and p["kind"] in KIND_OK.get(
                st["kind"], {"boss"}
            ):
                used.add(s["step"])
                matched[k] = s
                break
    fill, add = [], []
    last = None
    first = steps[0] if steps else None
    for k, st in enumerate(stops):
        s = matched.get(k)
        at = [rp.rnd(st["x"]), rp.rnd(st["y"])]
        if void and void(st["floor"], st["x"], st["y"]):
            log(f"{slug}: {st['name']} lies on the blank parchment off the map's art; its place is not used")
            if s:
                last = s["step"]
            continue
        if s:
            p = points[s["point"]]
            last = s["step"]
            if p.get("floor") not in (None, st["floor"]):
                log(f"{slug}: {st['name']} is on floor {st['floor']} in its route, {p.get('floor')} in ours; kept ours")
                continue
            if p.get("x") is None or p.get("approx") or s.get("x") is None or s.get("approx"):
                fill.append({"point": p["id"], "floor": st["floor"], "at": at, "approx": approx, "name": p["name"]})
            continue
        if main is not None and not on_paths(st, main, sides):
            log(f"{slug}: {st['name']} ({st['kind']}) is off its paths; not added as a stop")
            continue
        word = {"optional": " (optional)", "rare": " (rare, not in every run)"}.get(st["kind"], "")
        after = (
            last
            if last is not None
            else (first["step"] if first and points.get(first.get("point"), {}).get("kind") == "entrance" else 0)
        )
        add.append({"after": after, "floor": st["floor"], "at": at, "note": st["name"] + word, "approx": True})
    return fill, add


def entrance_fill(research, main, fill):
    """The research's entrance step without a place: the start of its main path on that floor."""
    points = {p["id"]: p for p in research["points"]}
    steps = research.get("route") or []
    if not steps:
        return
    s = steps[0]
    p = points.get(s.get("point"))
    if not p or p["kind"] != "entrance" or not isinstance(s.get("floor"), int) or s["floor"] < 1:
        return
    if s.get("x") is not None and not s.get("approx"):
        return
    pieces = main.get(s["floor"])
    if pieces and all(f["point"] != p["id"] for f in fill):
        x, y = pieces[0][0]
        fill.insert(
            0, {"point": p["id"], "floor": s["floor"], "at": [rp.rnd(x), rp.rnd(y)], "approx": True, "name": p["name"]}
        )


def ways(research, fill, add, main):
    """Its main path on a floor where the plan has fewer than two placed stops (so no line of its own): drawn as an
    optional route, so the way through that floor still shows (Blackmaw Hold's underground floors)."""
    filled = {f["point"]: f for f in fill}
    count = {}
    for s in research.get("route") or []:
        f = filled.get(s.get("point"))
        floor = f["floor"] if f else s.get("floor")
        if isinstance(floor, int) and (f or s.get("x") is not None):
            count[floor] = count.get(floor, 0) + 1
    for a in add:
        count[a["floor"]] = count.get(a["floor"], 0) + 1
    return [
        {"floor": f, "name": "", "way": True, "points": piece}
        for f, pieces in sorted(main.items())
        if count.get(f, 0) < 2
        for piece in pieces
    ]


def side_name(s):
    return "Way through this floor" if s.get("way") else "Side path: " + s["name"]


# ---------------------------------------------------------------------------------------------------------------------
# Legs from its path, checked against our mask.


def _closest(poly, q):
    """For each segment of a polyline: (distance, arc length at the closest point, the point)."""
    out, s = [], 0.0
    for (ax, ay), (bx, by) in zip(poly, poly[1:]):
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((q[0] - ax) * dx + (q[1] - ay) * dy) / L2))
        px, py = ax + t * dx, ay + t * dy
        L = math.sqrt(L2)
        out.append((math.hypot(q[0] - px, q[1] - py), s + t * L, (px, py)))
        s += L
    return out


JOIN = 12.0  # px: a path whose end lies this close to another path joins it there (a side path off the main one)


def network_path(polys, a, b, near_px):
    """The shortest way from a to b (px) along a network of polylines (its main path pieces and side paths on one
    floor; a polyline whose end lies on another joins it there), entering and leaving it at its closest points to a
    and b. None when a or b is farther than near_px from every polyline. Returns the points between a and b."""
    import heapq

    nodes, adj, segs = [], [], []

    def node(p):
        nodes.append(p)
        adj.append([])
        return len(nodes) - 1

    def edge(i, j, w=None):
        w = math.dist(nodes[i], nodes[j]) if w is None else w
        adj[i].append((j, w))
        adj[j].append((i, w))

    ends = []
    for k, poly in enumerate(polys):
        ids = [node(p) for p in poly]
        for i, j in zip(ids, ids[1:]):
            edge(i, j)
            segs.append((i, j, k))
        ends += [(ids[0], k), (ids[-1], k)]

    def attach(q, limit, owner=None):
        hits = []
        for i, j, k in segs:
            if k == owner:
                continue
            d, _s, c = _closest([nodes[i], nodes[j]], q)[0]
            if d <= limit:
                hits.append((d, i, j, c))
        return hits

    for e, k in ends:
        hits = attach(nodes[e], JOIN, owner=k)
        if hits:
            d, i, j, c = min(hits)
            n = node(c)
            edge(n, i)
            edge(n, j)
            edge(e, n, d)
    start, goal = node(a), node(b)
    for q, s in ((a, start), (b, goal)):
        hits = attach(q, near_px)
        if not hits:
            return None
        for d, i, j, c in hits:
            n = node(c)
            edge(n, i)
            edge(n, j)
            edge(s, n, 3 * d + 1e-6)
    dist, prev, heap = {start: 0.0}, {}, [(0.0, start)]
    while heap:
        d, u = heapq.heappop(heap)
        if u == goal:
            break
        if d > dist.get(u, math.inf):
            continue
        for v, w in adj[u]:
            nd = d + w
            if nd < dist.get(v, math.inf):
                dist[v], prev[v] = nd, u
                heapq.heappush(heap, (nd, v))
    if goal not in prev:
        return None
    path, u = [], prev[goal]
    while u != start:
        path.append(nodes[u])
        u = prev[u]
    return path[::-1]


def dense(line, step=1.0):
    out = [line[0]]
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        n = max(1, int(math.hypot(bx - ax, by - ay) / step))
        out += [(ax + (bx - ax) * i / n, ay + (by - ay) * i / n) for i in range(1, n + 1)]
    return out


def simplify(pts, tol):
    """Douglas-Peucker without a clearance test: the path is already where it should be."""
    if len(pts) <= 2:
        return list(pts)
    a, b = np.asarray(pts[0]), np.asarray(pts[-1])
    ab = b - a
    norm = float(np.hypot(*ab))
    if norm == 0:
        devs = [math.hypot(p[0] - a[0], p[1] - a[1]) for p in pts[1:-1]]
    else:
        devs = [abs(ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) / norm for p in pts[1:-1]]
    i = int(np.argmax(devs)) + 1
    if devs[i - 1] <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[: i + 1], tol)[:-1] + simplify(pts[i:], tol)


WATER_LIGHT = 100.0  # mean RGB above which a cool pixel can be water
VOID_AREA = 400  # px: the smallest area of parchment or water that counts (not a doorway or a speck in a wall)
WATER = (
    -20.0
)  # (G + B) / 2 - R above which a pixel is water: the maps' water is grey-green or blue, the parchment brown


def bad_mask(ctx):
    """Where its path must not run, on the classic maps: off our walkable mask, and either the bare parchment around
    the dungeon (what does not differ from the per-pixel median of every old dungeon map, the "region" route_paths.py
    computes: parchment-toned floors inside the walls stay in) or water (grey-green or blue, where parchment and rock
    are brown). Only areas of VOID_AREA px or more count. On the Forever pictures nothing is flagged."""
    if "bad" not in ctx:
        if not ctx["classic"]:
            ctx["bad"] = np.zeros_like(ctx["mask"])
        else:
            a = np.asarray(ctx["img"].convert("RGB")).astype(np.float32)
            # Water is light as well as cool; dark slate (a stone terrace, a shadowed floor) is not water.
            cool = (ndimage.gaussian_filter((a[..., 1] + a[..., 2]) / 2 - a[..., 0], 2.0) > WATER) & (
                ndimage.gaussian_filter(a.mean(2), 2.0) > WATER_LIGHT
            )
            bad = ~ctx["mask"] & (cool | ~ctx["region"])
            # Only large areas: a doorway or a light speck in a wall is not the parchment around the dungeon or a lake.
            lab, n = ndimage.label(bad)
            sizes = ndimage.sum(bad, lab, range(1, n + 1)) if n else np.zeros(0)
            ctx["bad"] = np.isin(lab, 1 + np.flatnonzero(sizes >= VOID_AREA))
    return ctx["bad"]


def bad_runs(pts, ctx):
    """Stretches (first, last index) of a dense polyline at least FIX_RUN px long over parchment or water."""
    bad = bad_mask(ctx)
    h, w = bad.shape
    flags = [bool(bad[min(h - 1, max(0, int(round(y)))), min(w - 1, max(0, int(round(x))))]) for x, y in pts]
    runs, i = [], 0
    while i < len(flags):
        if flags[i]:
            j = i
            while j + 1 < len(flags) and flags[j + 1]:
                j += 1
            if j - i + 1 >= FIX_RUN:
                runs.append((i, j))
            i = j + 1
        else:
            i += 1
    return runs


def fix_runs(pts, ctx, log, where):
    """Re-route each stretch of a dense polyline that runs over parchment or water with our pathfinder. Returns
    (points, re-routed stretches, stretches left as they were)."""
    runs = bad_runs(pts, ctx)
    if not runs:
        return pts, [], 0
    out, done, fixed, left = [], 0, [], 0
    for i, j in runs:
        i0, j1 = max(done, i - 8), min(len(pts) - 1, j + 8)  # a little way back onto the floor on both sides
        line, off = rp.find_path(ctx["mask"], ctx["dist"], ctx["cost"], ctx["rough"], pts[i0], pts[j1])
        if line is None or bad_runs(dense(list(line)), ctx):
            left += 1
            continue
        out += pts[done:i0] + dense(list(line))
        done = j1 + 1
        fixed.append((len(out) - len(dense(list(line))), len(out) - 1))
        log(f"{where}: {j - i + 1} px of its path over parchment or water re-routed with our pathfinder")
    out += pts[done:]
    return out, fixed, left


class Importer:
    def __init__(self, plan, main, sides, log, tol):
        self.plan, self.main, self.sides, self.log, self.tol = plan, main, sides, log, tol
        self.record = {}  # (floor, a, b) -> {"raw": px, "final": px, "fixed": [(i, j)]}
        self.ctx = {}
        self.fixed, self.fallbacks, self.dropped = 0, 0, 0

    def prefer(self, floor, a, b, ctx):
        self.ctx[floor] = ctx
        to_px = ctx["to_px"]
        near = NEAR * ctx["img"].size[0]
        pa, pb = to_px(*a), to_px(*b)
        polys = [[to_px(x, y) for x, y in piece] for piece in self.main.get(floor, [])]
        polys += [[to_px(x, y) for x, y in s["points"]] for s in self.sides if s["floor"] == floor]
        if polys:
            sub = network_path(polys, pa, pb, near)
            if not sub:
                return None
            raw = [pa] + sub + [pb]
            where = f"{self.plan['id']} floor {floor} {a} -> {b}"
            pts, fixed, left = fix_runs(dense(raw), ctx, self.log, where)
            inner = simplify(pts, self.tol)[1:-1]
            line = [pa]
            for q in inner:  # no two bends on one spot (a stop that lies on the path itself)
                if math.dist(q, line[-1]) > 0.5 and math.dist(q, pb) > 0.5:
                    line.append(q)
            line.append(pb)
            if left or bad_runs(dense(line), ctx):
                # A stretch our pathfinder cannot mend (or that simplifying put back over parchment): the whole leg
                # is ours instead.
                self.log(f"{where}: its path stays over parchment or water; this leg uses our computed bends")
                self.fallbacks += 1
                return None
            self.fixed += len(fixed)
            self.record[(floor, tuple(a), tuple(b))] = {
                "raw": raw,
                "final": line,
                "fixed": [pts[i : j + 1] for i, j in fixed],
            }
            extra = {"import": "fdr"}
            if fixed:
                extra["fixed"] = len(fixed)
            return line, extra
        return None

    def check_side(self, side):
        """A side path in plan space, its over-parchment stretches re-routed; None when one cannot be (left out)."""
        ctx = self.ctx.get(side["floor"])
        if not ctx:
            return [[rp.rnd(c) for c in p] for p in side["points"]]
        to_px, to_plan = ctx["to_px"], ctx["to_plan"]
        where = f"{self.plan['id']} floor {side['floor']} {side_name(side)}"
        pts, fixed, left = fix_runs(dense([to_px(*p) for p in side["points"]]), ctx, self.log, where)
        line = simplify(pts, self.tol)
        if left or bad_runs(dense(line), ctx):
            self.log(f"{where}: stays over parchment or water; left out")
            self.dropped += 1
            return None
        self.fixed += len(fixed)
        return [[rp.rnd(c) for c in to_plan(*q)] for q in line]


# ---------------------------------------------------------------------------------------------------------------------
# Previews: its route as it is (left) and what the plan now draws (right), on our floor picture.


def sheet(img, xf_to_px, raw_main, raw_sides, raw_stops, legs, record, sides, stops, path: Path):
    W, H = img.size
    out = Image.new("RGB", (W * 2 + 10, H), (0, 0, 0))
    for k in range(2):
        out.paste(img.convert("RGB"), (k * (W + 10), 0))
    d = ImageDraw.Draw(out)
    for piece in raw_main:
        d.line([xf_to_px(*p) for p in piece], fill=(40, 220, 60), width=2)
    for s in raw_sides:
        d.line([xf_to_px(*p) for p in s["points"]], fill=(40, 200, 230), width=2)
    for s in raw_stops:
        x, y = xf_to_px(s["x"], s["y"])
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(250, 220, 40), outline=(0, 0, 0))
    o = W + 10
    for s in sides:
        d.line([(xf_to_px(*p)[0] + o, xf_to_px(*p)[1]) for p in s["points"]], fill=(40, 200, 230), width=2)
    for leg in legs:
        pts = [leg["from"]] + leg["bends"] + [leg["to"]]
        color = (230, 30, 30) if leg.get("import") else (255, 150, 0)
        d.line([(xf_to_px(*p)[0] + o, xf_to_px(*p)[1]) for p in pts], fill=color, width=3)
        rec = record.get((leg["floor"], tuple(leg["from"]), tuple(leg["to"])))
        for run in (rec or {}).get("fixed", []):
            d.line([(x + o, y) for x, y in run], fill=(255, 0, 255), width=4)
    for x, y in stops:
        x, y = xf_to_px(x, y)
        d.ellipse((x + o - 5, y - 5, x + o + 5, y + 5), fill=(30, 120, 255), outline=(255, 255, 255))
    d.text((6, 6), "Forever Dungeon Routes as is (green main, cyan side, yellow stops)", fill=(255, 255, 255))
    d.text(
        (o + 6, 6), "plan: red = its path, magenta = re-routed stretch, orange = ours (fallback)", fill=(255, 255, 255)
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)


# ---------------------------------------------------------------------------------------------------------------------


def outside_art(pictures):
    """void(plan, floor, x, y): does that spot of a classic floor lie on the bare parchment around the dungeon (what
    does not differ from the per-pixel median of every old dungeon map, holes filled: route_paths.py's "region")?"""
    classic = [
        np.asarray(img, np.float32) for k, (img, src, _) in pictures.items() if img and src.startswith("game map tiles")
    ]
    background = np.median(np.stack(classic), 0) if len(classic) >= 5 else None
    regions = {}

    def void(plan, floor, x, y):
        key = (plan["id"], floor)
        if key not in regions:
            img, src, _ = pictures.get(key) or pictures.get(("__any__",) + key) or (None, None, None)
            region = None
            if img is not None and src.startswith("game map tiles") and background is not None:
                a = np.asarray(img, np.float32)
                diff = ndimage.gaussian_filter(np.abs(a - background).mean(2), 1.5)
                region = ndimage.binary_fill_holes(ndimage.binary_closing(diff > rp.DEFAULTS["drawn"], rp._disk(2)))
            regions[key] = region
        region = regions[key]
        if region is None:
            return False
        h, w = region.shape
        return not region[min(h - 1, max(0, int(y * h))), min(w - 1, max(0, int(x * w)))]

    return void


def run_lua(*args):
    r = subprocess.run(["lua", *args], cwd=rp.REPO, capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    return r.stdout


def gather_pictures(plans, casc, instances, fdj, openmap, game, every=()):
    """Pictures of every routed floor, and of every floor of the plans in `every` (keyed "__any__")."""
    pictures = {}
    for plan in plans:
        for f in range(1, len(plan["floors"]) + 1):
            if f in rp.route_floors(plan):
                pictures[plan["id"], f] = rp.floor_picture(game, casc, instances, fdj, openmap, plan, f)
            elif plan["id"] in every:
                pictures["__any__", plan["id"], f] = rp.floor_picture(game, casc, instances, fdj, openmap, plan, f)
    return pictures


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--fdr", required=True, type=Path, help="a clone of ForeverDungeonRoutes (holds ForeverDungeonRoutes/Data)"
    )
    ap.add_argument(
        "--game", required=True, type=Path, help="the game folder that holds Interface/AddOns (e.g. _forever_)"
    )
    ap.add_argument("--work", required=True, type=Path, help="scratch folder for previews and the log")
    ap.add_argument("--only", default="", help="comma-separated plan slugs")
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 when a routes file would change")
    args = ap.parse_args(argv)
    work = args.work.resolve()
    if rp.REPO in work.parents and rp.REPO / ".route-work" not in [work, *work.parents]:
        raise SystemExit("keep --work outside the repository (or in .route-work/): it holds game art")
    if not (args.fdr / "ForeverDungeonRoutes" / "Data" / "DefaultRoutes.lua").exists():
        raise SystemExit(f"{args.fdr}: no ForeverDungeonRoutes/Data/DefaultRoutes.lua")
    only = {s for s in args.only.split(",") if s}
    lines = []

    def log(s):
        lines.append(s)
        print(s)

    fdr = load_fdr(args.fdr)
    licence = (
        (args.fdr / "LICENSE").read_text(encoding="utf-8", errors="replace") if (args.fdr / "LICENSE").exists() else ""
    )
    if "MIT License" not in licence:
        raise SystemExit("its LICENSE is not the MIT licence any more: check it before importing")
    casc = rp.Casc(args.game)
    fdj, openmap = rp.fdj_maps(args.game), rp.openmap_maps(args.game)
    plans, instances = rp.load_repo()
    by_key = {norm_key(instances, d["name"]): d for d in fdr["dungeons"]}

    # Which plan takes which route.
    chosen = {}
    for plan in plans:
        if only and plan["id"] not in only:
            continue
        key = norm_key(instances, plan["instance"]["name"])
        # The same name, else its dungeon whose name starts ours (its "Stratholme" for "Stratholme: Live").
        d = by_key.get(key) or next((v for k, v in by_key.items() if len(k) >= 8 and key.startswith(k)), None)
        entry = d and fdr["routes"].get(d["key"])
        if not entry:
            continue
        research = json.loads((rp.REPO / "data-src" / "dungeons" / f"{plan['id']}.json").read_text(encoding="utf-8"))
        route = pick_route(entry, research)
        chosen[plan["id"]] = (d, route)
    log(f"routes to import: {len(chosen)} ({', '.join(sorted(chosen))})")

    changed = []
    imports = {}
    # Pass 1 (repeated while the alignment of a provider picture moves): the import blocks.
    for attempt in range(3):
        pictures = gather_pictures(plans, casc, instances, fdj, openmap, args.game, set(chosen))
        void = outside_art(pictures)
        moved = False
        for plan in plans:
            if plan["id"] not in chosen:
                continue
            d, route = chosen[plan["id"]]
            research = json.loads(
                (rp.REPO / "data-src" / "dungeons" / f"{plan['id']}.json").read_text(encoding="utf-8")
            )
            say = log if attempt == 0 else (lambda s: None)
            fmap = floor_map(fdr, args.fdr, d, plan, pictures, casc, instances, say)
            main_paths, sides, stops = convert(route, fmap)
            if not main_paths and not stops:
                say(f"{plan['id']}: none of its floors matches a plan floor; not imported")
                continue
            approx = "dungeon journal" not in (route.get("source") or "").lower()
            fill, add = match_stops(
                research, stops, approx, say, plan["id"], main_paths, sides, lambda f, x, y, p=plan: void(p, f, x, y)
            )
            entrance_fill(research, main_paths, fill)
            sides = sides + ways(research, fill, add, main_paths)
            imp = {
                "from": f"{SOURCE_NAME} {fdr['version']}, route {route.get('id')!r} ({route.get('source')})",
                "url": SOURCE_URL,
                "licence": "MIT, Copyright (c) 2026 Checkov23 (docs/licenses/ForeverDungeonRoutes-LICENSE.txt)",
                "note": NOTE,
                **(
                    {
                        "traced": "its credits say this route was traced from the aetherflask.com walkthrough maps "
                        "(mirrored at eintr.net)"
                    }
                    if traced(route)
                    else {}
                ),
                "fill": fill,
                "add": add,
                "side": [
                    {"floor": s["floor"], "name": side_name(s), "points": [[rp.rnd(c) for c in p] for p in s["points"]]}
                    for s in sides
                ],
            }
            old = rp.read_routes(plan["id"]).get("import")
            # Side paths are checked against the mask in pass 2 (and stored then): compare the rest here.
            differs = {k: v for k, v in (old or {}).items() if k not in ("side", "check")} != {
                k: v for k, v in imp.items() if k not in ("side", "check")
            }
            if attempt > 0 and differs:
                moved = True
            imports[plan["id"]] = (imp, main_paths, sides, stops, fmap)
            if differs:
                if args.check:
                    changed.append(f"{plan['id']}.json")
                    continue
                doc = rp.read_routes(plan["id"]) or {
                    "schema": 1,
                    "slug": plan["id"],
                    "about": "",
                    "map": {},
                    "overrides": {},
                    "moves": [],
                    "legs": [],
                }
                doc["import"] = imp
                (rp.ROUTES_DIR / f"{plan['id']}.json").write_text(rp.format_routes(doc), encoding="utf-8", newline="\n")
        if args.check:
            break
        run_lua("tools/gen_plans.lua")
        plans, instances = rp.load_repo()
        if attempt > 0 and not moved:
            break
    if args.check and changed:
        print(f"{len(changed)} routes file(s) would change: {', '.join(changed)}")
        sys.exit(1)

    # Pass 2: legs. Every plan with a route of two or more stops; imported paths first, ours for the rest.
    pictures = {
        k: v for k, v in gather_pictures(plans, casc, instances, fdj, openmap, args.game).items() if k[0] != "__any__"
    }
    classic = [
        np.asarray(img, np.float32) for img, src, _ in pictures.values() if img and src.startswith("game map tiles")
    ]
    background = np.median(np.stack(classic), 0) if len(classic) >= 5 else None
    stats = {"legs": 0, "fdr": 0, "fixed": 0, "fallbacks": 0, "dropped": 0}
    per_plan = {}
    for plan in plans:
        if (only and plan["id"] not in only) or not rp.route_floors(plan):
            continue
        mine = {f: pictures[plan["id"], f] for f in rp.route_floors(plan)}
        got = imports.get(plan["id"])
        imp = None
        for tol in (1.5, 2.5, 4.0, 6.0, 9.0):
            said = []  # this attempt's log lines (only the attempt that is kept is logged)
            importer = Importer(plan, got[1], got[2], said.append, tol) if got else None
            keep = (
                frozenset(rp.pkey(e["floor"], *e["at"]) for e in got[0]["fill"] + got[0]["add"]) if got else frozenset()
            )
            doc = rp.process_plan(
                plan,
                mine,
                work,
                said.append,
                background,
                prefer=importer.prefer if importer else None,
                keep=keep,
            )
            if not importer:
                break
            # Stops plus bends per drawn route must stay within the format's 200 points: simplify harder if not.
            worst = 0
            for r in plan.get("routes", []):
                stops_ = [p for p in r["points"] if p.get("step")]
                n = len(stops_)
                for a, b in zip(stops_, stops_[1:]):
                    for leg in doc["legs"]:
                        if (
                            leg["floor"] == r["floor"]
                            and rp.pkey(0, *leg["from"]) == rp.pkey(0, a["x"], a["y"])
                            and rp.pkey(0, *leg["to"]) == rp.pkey(0, b["x"], b["y"])
                        ):
                            n += len(leg["bends"])
                worst = max(worst, n)
            if worst <= 190:
                break
        for line_ in said:
            log(line_)
        if importer:
            importer.log = log
            imp = dict(doc["import"])
            checked = []
            for s in got[2]:
                pts = importer.check_side(s)
                if pts:
                    checked.append({"floor": s["floor"], "name": side_name(s), "points": pts})
            imp["side"] = checked
            # What the parchment and water check did: stretches re-routed, legs left to our bends, side paths left out.
            # The audit after it all: stretches of what ships (its legs and side paths) still over parchment or water.
            flagged = 0
            for f, ctx in importer.ctx.items():
                lines_ = [
                    [leg["from"]] + leg["bends"] + [leg["to"]]
                    for leg in doc["legs"]
                    if leg["floor"] == f and leg.get("import")
                ] + [side["points"] for side in checked if side["floor"] == f]
                for line_ in lines_:
                    flagged += len(bad_runs(dense([ctx["to_px"](*q) for q in line_]), ctx))
            imp["check"] = {
                "rerouted": importer.fixed,
                "legs_ours": importer.fallbacks,
                "sides_left_out": importer.dropped,
                "flagged": flagged,
            }
            doc["import"] = imp
            stats["fixed"] += importer.fixed
            stats["fallbacks"] += importer.fallbacks
            stats["dropped"] += importer.dropped
            per_plan[plan["id"]] = imp["check"]
            for f in sorted({leg["floor"] for leg in doc["legs"]} | set(got[1]) | {s["floor"] for s in got[2]}):
                pic = pictures.get((plan["id"], f)) or rp.floor_picture(
                    args.game, casc, instances, fdj, openmap, plan, f
                )
                if not pic or not pic[0]:
                    continue
                img, _src, xf = pic
                sx, tx, sy, ty, _ = xf
                W, H = img.size
                to_px = (lambda sx, tx, sy, ty, W, H: lambda x, y: ((x * sx + tx) * W, (y * sy + ty) * H))(
                    sx, tx, sy, ty, W, H
                )
                stop_xy = [
                    (p["x"], p["y"])
                    for r in plan.get("routes", [])
                    if r["floor"] == f and not r.get("optional")
                    for p in r["points"]
                    if p.get("step")
                ]
                sheet(
                    img,
                    to_px,
                    got[1].get(f, []),
                    [s for s in got[2] if s["floor"] == f],
                    [s for s in got[3] if s["floor"] == f],
                    [leg for leg in doc["legs"] if leg["floor"] == f],
                    importer.record,
                    [s for s in checked if s["floor"] == f],
                    stop_xy,
                    work / "fdr-preview" / f"{plan['id']}-{f}.png",
                )
        for leg in doc["legs"]:
            stats["legs"] += 1
            if leg.get("import"):
                stats["fdr"] += 1
        text = rp.format_routes(doc)
        path = rp.ROUTES_DIR / f"{plan['id']}.json"
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            changed.append(path.name)
            if not args.check:
                path.write_text(text, encoding="utf-8", newline="\n")
    for slug, c in sorted(per_plan.items()):
        if any(c.values()):
            log(f"check {slug}: {c}")
    log(
        f"legs: {stats['legs']}, from its route: {stats['fdr']}, stretches re-routed over parchment or water: "
        f"{stats['fixed']}, legs left to our bends: {stats['fallbacks']}, side paths left out: {stats['dropped']}"
    )
    work.mkdir(parents=True, exist_ok=True)
    (work / "import_routes.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(changed)} routes file(s) {'would change' if args.check else 'written'}: {', '.join(changed) or '-'}")
    if args.check:
        sys.exit(1 if changed else 0)
    print(run_lua("tools/gen_plans.lua").strip())
    print(run_lua("tools/gen_spawns.lua").strip())


if __name__ == "__main__":
    main()
