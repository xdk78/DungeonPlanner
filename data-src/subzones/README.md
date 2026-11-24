# Sub-zone anchors (`data-src/subzones`)

Where each named area of a dungeon lies on its recommended plan's floors: the data behind the map's "You are here
(approx.)" marker (`UI/MapHere.lua`, `Data/Subzones.lua`). Inside an instance the client gives an addon no position,
only the name of the area the player stands in (`GetSubZoneText()`, docs/COMPATIBILITY.md section 10); the marker rings
the middle of that area. `lua tools/gen_subzones.lua` turns these files into `Data/SubzoneData.lua`; the addon never
reads this folder.

## How an area is identified

By ID, never by its English name, so every client language matches:

- `area`: an AreaTable ID. The addon asks the client for its name in the player's language
  (`C_Map.GetAreaInfo(id)`) and compares it with the sub-zone text.
- `wmo`: a WMOAreaTable ID, for a room that the client names in its WMO area table only. No game function returns that
  name for an ID, so `names` carries the names the client's own table gives it in each client language (`enUS` is
  `name`); several spellings where rows of one room are spelled differently in a language. An area that rows of both
  kinds show has both IDs.
- A sub-zone that reads the same as the zone (`GetZoneText()`) is the instance itself and places nothing; the
  instance's own areas are left out here.

## Files

`<plan slug>.json`, written by `tools/subzone_anchors.py` (below); only `overrides` and `exclude` are edited by hand,
and the tool keeps them.

```json
{ "schema": 1, "slug": "hall-of-thanes", "instanceMapID": 3065, "build": "1.60.1.71037",
  "sources": [ { "id": "wago", "name": "...", "url": "...", "licence": "...", "what": "..." } ],
  "position": "game",
  "areas": [ { "name": "Anvilmar's Rest", "wmo": 140756, "names": { "deDE": [ "Anvilmars Rast" ] },
    "at": [ { "floor": 1, "x": 0.5161, "y": 0.6724, "share": 1.0, "samples": 1 } ] } ],
  "overrides": [ { "name": "Festering Grotto", "floor": 1, "drop": true, "why": "..." } ],
  "exclude": [ { "name": "Canals", "why": "..." } ] }
```

- `sources`: `wago` names where the IDs and names come from; `position` names the source of every `at` (`game` or
  `fdr`, below).
- `at`: an anchor per floor of the recommended plan (`floor` is the plan's floor index; `x`, `y` in the plan's 0..1
  space, the space of its markers). `share` is the part of the area's ground on that floor, `samples` how many pieces
  of ground were measured. Every anchor is approximate: the middle of the area's ground.
- `overrides`: per area and floor, `drop` (no anchor on that floor) or `x`, `y` and `src` (a source id, or `own` for a
  spot read on the map by us), each with `why`.
- `exclude`: an area left out entirely, with `why`.

## Sources

| id | Source | Licence | Used for |
|---|---|---|---|
| `wago` | [wago.tools](https://wago.tools/db2) DB2 exports of the WoW: Forever client, build 1.60.1.71037: `AreaTable`, `WMOAreaTable` (every client language), `Map` | facts from the game's tables | Area IDs, WMO area IDs, which WMO and map they belong to, the WMO areas' names |
| `game` | The client's own files on a local install (WDT, terrain tiles, WMOs), read by `tools/subzone_anchors.py` | facts measured by us | Anchors of Forever's new dungeons: each terrain chunk carries its AreaTable ID; each WMO part, placed on the map, has a WMO area row. The floors' plan space comes from `tools/minimap_art.py`'s plan-to-world transform (data-src/minimaps.json) |
| `fdr` | [Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes) `Data/Rooms.lua` | MIT ([copy](../../docs/licenses/ForeverDungeonRoutes-LICENSE.txt)) | Anchors of classic dungeons and raids: its room boxes, which its author generated from the same client tables (WMO area names, WMO part boxes, floors from `UiMapAssignment`), on the old dungeon maps the plans use. Its English room names are matched to the IDs of the instance's own rows |

Nothing comes from AllTheThings, NeedRoll, GPL addons or unlicensed sources.

## Checks

- `tests/test_subzones.lua` checks every anchor against the floor's walkability grid (`Data/WalkData.lua`): it must lie
  on or next to drawn ground. Floors without a grid (open maps: Blackmaw Grove, City of Dalaran, Excavation Site,
  Shaper's Terrace) were checked by eye against the tool's preview pictures, where the anchors sit by the map's own
  painted area names.
- An anchor within 0.03 of the map's edge is not written: such an area is mostly the mountains around the map.
- `lua tools/gen_subzones.lua --check` (CI) fails on invalid JSON and on an out-of-date `Data/SubzoneData.lua`.

## Coverage

30 recommended plans, 229 areas, 251 anchors.

| Plan | Areas | Position |
|---|---|---|
| hall-of-thanes | 3 | game |
| ruins-of-lordaeron | 4 | game |
| blackmaw-hold | 5 | game |
| city-of-dalaran | 43 | game |
| the-drowned-city | 6 | game |
| excavation-site-wetlands | 7 | game |
| shapers-terrace | 11 | game |
| blackfathom-deeps, blackrock-depths, blackwing-lair, dire-maul-west, gnomeregan, lower-blackrock-spire, maraudon, molten-core, naxxramas, razorfen-downs, ruins-of-ahnqiraj, scarlet-monastery-armory, scarlet-monastery-cathedral, scarlet-monastery-graveyard, scarlet-monastery-library, stratholme-live, stratholme-undead, temple-of-atalhakkar, the-deadmines, uldaman, upper-blackrock-spire, wailing-caverns, zulgurub | 1 to 20 each | fdr |

Not covered, and why:

- **Alcaz Prison**: its one named area, Maximum Security, is a floor of its own that the plan does not have.
- **Krol'dok Stronghold**: its named areas lie at the map's edge, outside the drawn stronghold.
- **Ragefire Chasm**, **Dire Maul: East**: their one room lies at the edge of the drawn map or off it.
- **Dire Maul: North**, **Razorfen Kraul**, **Shadowfang Keep**, **The Stockade**, **Zul'Farrak**, **Onyxia's Lair**,
  **Temple of Ahn'Qiraj**, **Hyjal Summit**: no source places their rooms (Forever Dungeon Routes has none for them,
  and their maps are not among the floors `tools/minimap_art.py` reads).
- **Scholomance**: Forever Dungeon Routes' rooms are on its old map floors, which the plan's floors do not match.
- Underground parts of a floor the plan has not got: the old Undercity under the Ruins of Lordaeron, the Underbelly of
  Dalaran, Atal'Byzal under the Drowned City (`exclude` in their files).

## Regenerating

```sh
uv run --script tools/subzone_anchors.py --game "<World of Warcraft>/_forever_" --work <scratch folder>
lua tools/gen_subzones.lua            # writes Data/SubzoneData.lua
lua tools/gen_subzones.lua --check    # exits 1 on invalid JSON or an out-of-date file (CI)
lua tools/gen_subzones.lua --report   # coverage
```

`tools/subzone_anchors.py` downloads the tables of its build from wago.tools into the work folder once, reads the game
install read-only, and writes a preview picture per floor (the samples as dots, the anchors as rings) into the work
folder; keep the work folder outside the repository. Run it after a client patch, then `gen_subzones` and the tests;
change `BUILD` in the tool to the new build first.
