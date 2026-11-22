# Route bends (`data-src/routes`)

One JSON file per recommended plan whose route has two or more stops on a floor. `lua tools/gen_plans.lua` reads them
and puts **bends** (route points `{ x, y }` without `step`, docs/SHARING-FORMAT.md) between consecutive stops, so the
drawn line follows the dungeon's corridors instead of cutting through walls. Only coordinates are stored: no picture,
mask or other image ever goes into the repository.

## How they are made

`tools/route_paths.py` (Python, dependencies declared inline, run with `uv run --script`) works offline on a computer
with the game installed. It reads the game and its addons read-only and writes only these files:

1. **Floor pictures.** Classic floors: the game's old dungeon map tiles (`Interface\WorldMap\<Dir>\<Name><floor>_1..12`,
   the names `Data/GameFiles.lua` uses), read from the game's local storage (CASC) and stitched to 1002 x 668, the
   plans' coordinate space. Forever's new dungeons: the picture the addon draws under the plan at runtime, from the
   installed ForeverDungeonJournal (as `Data/Providers/DungeonJournal.lua`, same crop) or else OpenMap. When the
   provider adapter would draw the plan through a fitted alignment (`Providers.Align`), the bends are computed on the
   picture and turned back into the plan's own space.
2. **Walkable mask.** Classic maps are all painted on one parchment, so the per-pixel median of every floor is the
   blank parchment; what differs from it (and what its walls enclose) is the dungeon. Inside that, floors are lighter
   and less saturated than walls, lava and shadow (a score `light - 60 * saturation`, threshold by Otsu), then opening,
   closing, small holes filled. Only the parts the stops touch are kept.
3. **Path.** The cheapest path between two stops (cost grows near walls, so lines run down the middle of corridors),
   simplified (Douglas-Peucker) to bends that stay inside the floor. Where the floor alone does not connect two stops,
   the path may cross what is drawn but not floor, at a high price; it never crosses the blank parchment.
4. **Moves.** An estimated (`(approx.)`) stop or marker that sits in a wall is moved to the nearest floor within 15 px
   (60 px when it lies on the blank parchment). Measured positions are never moved.

The work folder (`--work`) gets the pictures' previews (map, mask, route, a 0.05 grid) to check every floor by eye,
the masks, and a log. Keep it outside the repository: it holds game art. (`.route-work/` in the repository is ignored
and accepted.)

```sh
uv run --script tools/route_paths.py --game "<World of Warcraft>/_forever_" --work <scratch folder> [--only slug,slug]
lua tools/gen_plans.lua && lua tools/gen_spawns.lua
uv run --script tools/route_paths.py --game ... --work ... --check   # exit 1 when a routes file would change
```

`--game` is the client folder that holds `Interface\AddOns` (`World of Warcraft\_forever_`); the storage is found
next to it. Re-running is stable: the tool undoes its own earlier moves before it starts.

### When to run the `--check`s

CI cannot run this tool (it needs a local game install), so a routes file can fall behind its inputs without a failing
build. Its inputs outside the repository are the client's map tiles and the installed ForeverDungeonJournal and
OpenMap: their floor pictures, and their boss pins, which decide the alignment recorded in `map` (`none` when no pin
matches a plan boss, else `same`, `fit` or `pins` as in `Providers.Align`). `tools/minimap_art.py` records the same
alignment in `Data/MinimapArtData.lua` and also reads the installed Forever Dungeon Routes. Run `--check` here together
with the other checks that need the game (`tools/walk_grids.py`, `tools/minimap_art.py`, `tools/reyes_maps.py`):

- after a client patch, or after updating ForeverDungeonJournal, OpenMap or Forever Dungeon Routes in the install;
- before every release (AGENTS.md, "Changes").

When one reports a change, find which input moved before regenerating, and name in the pull request the provider
versions the files were computed with. Last full run: 2026-11-22, with ForeverDungeonJournal 2.1.3, OpenMap v0.8.13
and Forever Dungeon Routes 1.3.8 installed. It changed only the alignment label of Alcaz Prison and Shaper's Terrace
(`none` before), here and in `Data/MinimapArtData.lua`: ForeverDungeonJournal 2.0.9 and 2.1.2 added boss pins to those
two maps. The alignment stays the identity and every leg there is imported, so no bend, move or transform changed.

## File format (schema 1)

```json
{ "schema": 1, "slug": "hall-of-thanes", "about": "...", "map": { "1": "Dungeon Journal HallOfThanesMap (same)" },
  "overrides": { "1": { "block_rects": [[0.81, 0, 1, 1]], "open_paths": [{ "points": [[0.51, 0.95], [0.51, 0.72]], "width": 7 }] } },
  "moves": [ { "floor": 1, "from": [0.5204, 0.1747], "to": [0.5127, 0.1742], "kind": "position", "generated": true } ],
  "legs":  [ { "floor": 1, "from": [0.51, 0.66], "to": [0.73, 0.47], "bends": [[0.5088, 0.5813]], "generated": true } ] }
```

- `map`: the picture each floor was computed on (and the alignment mode for a provider picture).
- `legs`: `from` and `to` are the plan's stops after the moves (4 decimals, as the plans print them). `gen_plans` puts
  the bends between the two consecutive stops with exactly those positions on that floor; a leg whose stops have since
  moved in the research no longer applies (the generator names it; re-run the tool).
- `moves`: applied by `gen_plans` to every marker and route stop at `from` on that floor.
- `generated: true` marks what the tool redoes on every run. A leg or move without it is kept as written (a hand-made
  leg or a deliberate move).
- `overrides` (by floor, all coordinates normalized 0..1 on the floor picture), kept by the tool:
  `block_rects` / `open_rects` (`[x0, y0, x1, y1]`), `block_polys` / `open_polys` (lists of `[x, y]`),
  `block_paths` / `open_paths` (`{ points, width }` in px of the picture, a thick line: a corridor the mask misses);
  blocks apply first, then openings. Mask settings: `threshold` (else Otsu), `light`, `saturation`, `blue` (B - R),
  `yellow` ((R + G) / 2 - B) weights of the score, `smooth`, `open`, `close`, `hole`, `drawn`, `part`, `seed`;
  `seeds` (extra `[x, y]` that keep a part of the mask).

`tests/test_plans.lua` checks that every leg's bends are in its plan, in order, between its two stops, and on the map.

`tools/walk_grids.py` (the route tool's "Snap to corridors", docs/DATA-SOURCES.md) builds its walkability grids with
this tool's mask and applies these `overrides` to the picture they were made on: a fix here improves both (re-run
both tools).

## Imported routes (`import`)

`tools/import_routes.py` (same requirements as `route_paths.py`, plus a local clone of
[Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes), MIT) writes an `import` block into the
files of the plans whose route it imports (41: the classic dungeons except Scholomance, the 7 raids and the 9 new
Forever dungeons; docs/DATA-SOURCES.md has the licence check and the provenance of its classic routes), and legs marked `"import": "fdr"` with its path between our stops. It runs
`route_paths.py`'s pipeline itself, so the legs its route does not cover are computed in the same run, and it runs
`gen_plans.lua` and `gen_spawns.lua` at the end.

```sh
uv run --script tools/import_routes.py --fdr <clone of ForeverDungeonRoutes> --game "<World of Warcraft>/_forever_" --work <scratch folder>
uv run --script tools/import_routes.py ... --check            # exit 1 when a routes file would change
```

```json
"import": { "from": "Forever Dungeon Routes 1.2.4, route 'default' (...)", "url": "...", "licence": "MIT, ...",
  "note": "Route: Forever Dungeon Routes (MIT), by Checkov23.",
  "fill": [ { "point": "p4", "floor": 1, "at": [0.5088, 0.5183], "approx": true, "name": "Plunder" } ],
  "add":  [ { "after": 2, "floor": 1, "at": [0.6016, 0.6164], "note": "Gill (rare, not in every run)", "approx": true } ],
  "side": [ { "floor": 1, "name": "Side path: Highland Horror", "points": [[0.3, 0.6], [0.1, 0.4]] } ] }
```

- `fill`: the research point (and the steps linked to it) gets this position on this floor; only for points the
  research left unplaced or marked as estimates. `approx` is false only for raid bosses whose place comes from the
  game's dungeon journal.
- `add`: a stop the research lacks, inserted after research step `after` (0: first).
- `side`: optional routes (its side paths, and its main path on a floor where the plan has fewer than two stops).
- `note`: the credit line `gen_plans.lua` appends to the plan's notes.
- `traced`: present on the routes it says were traced from another site's walkthrough maps (its classic dungeons).
- `check`: what the parchment and water check did (`rerouted` stretches, `legs_ours` left to the computed bends,
  `sides_left_out`) and `flagged`, the stretches of what ships still over parchment or water after it all (0).

`route_paths.py` keeps the `import` block, never moves the stops it placed, and keeps the legs marked `import` like
hand-made ones; re-run `import_routes.py` after a change to the research or to its route. The work folder gets
`fdr-preview/<slug>-<floor>.png` (its route as it is on the left, what the plan draws on the right: its path red, a
re-routed stretch magenta, our computed legs orange) and `import_routes.log`.

## Status and known gaps (2026-11-16)

Routed and checked by eye: every floor with a route of two or more stops, with overrides on
Hall of Thanes, The Deadmines (Ironclad Cove: the ship's decks and the dock), Dire Maul East and North, Blackrock Depths
(the Ring of Law), Maraudon (its darker cave floors), Ruins of Lordaeron (an open city: grass and roads, not
buildings, canals or walls).

- Fixed: **Shadowfang Keep** floors 6 and 7 had each other's map (`ShadowfangKeep6_` is Lord Godfrey's Chamber, uiMap
  315, by its first tile's file ID; `ShadowfangKeep7_` the Wall Walk, 316); floor 6 is now routed on its own map.
  Every other plan's floor order was checked the same way (the tool reads each tile's file ID from the game's
  storage) and was right.
- Fixed: **City of Dalaran**: the adapters and this tool pick a provider's floor picture by the floor's name
  (`Providers.PickFloor`), so plan floor 1 ("City of Dalaran") gets the City picture, not the Underbelly that the
  Dungeon Journal addon lists first.
- Wailing Caverns, Maraudon, Stratholme (the Scarlet Bastion) and Blackrock Depths cross a few short stretches the mask
  does not count as floor (dark passages, water, a building's halls); the log names each.

Imported (2026-11-16): Forever Dungeon Routes' routes for 41 plans (every classic dungeon but Scholomance, whose
routes are drawn on the client's later map; the 7 raids; the 9 new Forever dungeons): 240 legs follow its paths, 163
points placed, 22 stops added, 42 optional routes. Its classic routes say they were traced from the aetherflask.com
walkthrough maps; the project includes them, and each of those files records it (`"traced"`). Parchment and water
check: 8 stretches re-routed (Wailing Caverns 4, Blackrock Depths 2, Dire Maul East 1, Gnomeregan 1), 3 legs left to
the computed bends, 1 side path and 7 stops off the art left out; 0 stretches flagged after. Known gaps: Alcaz Prison's
lower level (Maximum Security) is not a floor of our plan, so its stops there stay unplaced; Naxxramas' hub has no path
in it; where our step order differs from its route (City of Dalaran, Shaper's Terrace, Wailing Caverns) the legs follow
its paths and double back.
