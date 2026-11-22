# Data sources and credits

The recommended plans that ship with the addon (`Data/Plans/*.lua`) are generated from community research kept in
`data-src/dungeons/*.json`. This page says where that research comes from, what is excluded, and how to regenerate.

## What ships

One recommended plan per instance (see `data-src/dungeons/README.md` for the list and the status of each): the
Group Finder level range, the floors, the bosses in clearing order with short strategies, boss positions where a source
has them, a route with numbered stops, pulls, party positions per boss, and NPC and item IDs where a web source confirms
them. Every plan says in its note that it is community-researched, that positions are approximate, and how confident
the research is (`low` or `medium`). Estimated markers and stops carry "(approx.)" in their note (the UI shows a small "~" instead of the words). Bosses without a
position get the Adventure Guide's own pin at runtime (the map shows those for any boss the plan does not place).

Treat everything as a starting point: check it in game and adjust it in an editable copy.

## Sources and credits

| Source | Licence | Used for |
|---|---|---|
| [OpenMap](https://github.com/openmap-world/openmap), an addon (`Data/Forever/DungeonBosses.lua`, `Places.lua`, `DungeonMaps.lua`) | MIT ([copy](licenses/OpenMap-LICENSE.txt)) | Boss positions (Blizzard Encounter Journal data), Group Finder level ranges, instance IDs and floor names |
| [Warcraft Tavern](https://www.warcrafttavern.com) Forever dungeon guides | web guide | Boss order, routes and notes for the Forever-only dungeons, paraphrased |
| [Method](https://www.method.gg/wow-forever) Forever dungeon guides | web guide | Boss order, mechanics, trash notes, quest items and NPCs, paraphrased |
| [Wowhead Forever](https://www.wowhead.com/forever) dungeon guides (e.g. [Hall of Thanes](https://www.wowhead.com/forever/guide/hall-of-thanes-dungeon-overview-location-rewards)) | web guide | Checked the plans' boss order, routes and strategy notes (corrections in our own words); the boss facts below come from the same site's journal and guide data |
| [Wowhead Classic](https://www.wowhead.com/classic) NPC and item pages | web | NPC and item IDs: each ID was opened and its page title matched the name (they have no coordinates for instance NPCs) |
| [Warcraft Wiki](https://warcraft.wiki.gg/wiki/UiMapID) `UiMapID` table | web | Map IDs of Classic dungeon floors |
| [Warcraft Wiki: World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever) | web | Which instances are new in WoW: Forever (`origin`, shown as the "Forever" tag): the page marks the nine new dungeons (The Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace) and the raids Hyjal Summit and Barrow Deeps as new, the others as old, and describes no reworked classic dungeon. Checked against [Warcraft Tavern's announcement of the nine dungeons](https://www.warcrafttavern.com/news/nine-new-dungeons-coming-to-world-of-warcraft-forever/) and the game's own data: those nine have instance map IDs 2959-3065 in the client's encounter table (as Forever Dungeon Routes exports it) and the Group Finder (`/dp scan`), where every classic instance is 533 or below. Barrow Deeps has no plan here |
| Dungeon map pictures (the game's map art; community-made art for the Forever-only dungeons) | not copied | Viewed to read where rooms and portals are; every position read this way is an estimate marked "(approx.)". No picture or data file of them is shipped (Santiago Reyes' maps ship separately, by his permission: section "Bundled maps" below) |
| The same pictures, analysed by `tools/route_paths.py` on a local install (the game's dungeon map tiles; the Dungeon Journal and OpenMap addons' maps of the Forever-only dungeons) | not copied | Route bends that keep each route on the floor, and estimated spots moved off walls (`data-src/routes/`). Only coordinates ship; no picture, mask or grid derived from them |
| [Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes), an addon by Checkov23 | MIT ([copy](licenses/ForeverDungeonRoutes-LICENSE.txt)) | The routes of 41 plans: the classic dungeons, the 7 raids and the 9 new Forever dungeons. Main paths (route bends), side paths (optional routes), its stops as positions for our unplaced or estimated bosses and as added stops (`tools/import_routes.py`, section below). It states that its classic dungeon routes were traced from the aetherflask.com walkthrough maps; the project includes them. Its pictures are not used |

### Game files used at runtime (not shipped)

WoW: Forever's Adventure Guide is empty, so `Data/GameFiles.lua` names textures that are in the game client and draws
them at runtime, after checking each with `GetFileIDFromPath`: the old dungeon map tiles
(`Interface\WorldMap\<Dungeon>\<Dungeon><floor>_1..12`) and loading screens
(`Interface\Glues\LoadingScreens\LoadScreen<Name>`). No picture is copied into the addon.

| Source | Licence | Used for |
|---|---|---|
| [ForeverPlusPlus](https://github.com/xIGBClutchIx/ForeverPlusPlus) `Lib/DungeonMaps.lua`, `docs/forever-api.md` | MIT ([copy](licenses/ForeverPlusPlus-LICENSE.txt)) | The dungeon map tile names per floor; the facts that the client has no dungeon UiMaps but keeps these textures, that `EncounterJournalDisabled` is an active game rule, and that Forever's new dungeons are only in the Group Finder's browse list |
| The Dungeon Journal addon on the same client (read, not copied) | none stated | Facts only: which loading-screen file names and file IDs exist on this client |
| [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever), branch `forever` | Blizzard UI source | Return orders of `GetLFGDungeonInfo` and `C_LFGList.GetActivityInfoTable`; `Font:SetFont` returns nothing while `FontString:SetFont` returns success |

Strategy and route text is paraphrased in the project's own words; no guide text is reproduced. If you maintain one of
these sources and want something changed or removed, open an issue.

## Creature spawns (the map's Enemies layer)

`Data/Spawns/*.lua` is generated by `tools/gen_spawns.lua` from the recommended plans above (their bosses, rares, trash
packs, patrols and quest NPCs that have a position on a dungeon floor) and from `data-src/spawns/*.json`, where every
file names a source with a permissive licence or the contributor's own in-game observation. Nothing else feeds it.

No openly licensed database of creature spawns inside dungeons was found. OpenMap (MIT) and ForeverPlusPlus (MIT)
ship none and read Questie's database at runtime; Questie and QuestieDB (GPL-3.0, older content all rights reserved),
pfQuest's database (generated from VMaNGOS and CMaNGOS) and the server emulators' creature tables (CMaNGOS, vMaNGOS,
TrinityCore: GPL-2.0; AzerothCore: AGPL-3.0) are excluded for their licences; Wowhead Classic has no positions for
instance creatures. An in-game recorder is not built because the client does not seem to give an addon the player's
position or a creature's GUID inside a dungeon; `/dp scan` checks both. Details, coverage and gaps:
`data-src/spawns/README.md`.

```sh
lua tools/gen_spawns.lua            # writes Data/Spawns/<instance>.lua and the block in DungeonPlanner.toc
lua tools/gen_spawns.lua --check    # exits 1 when a generated file is out of date (CI runs this)
lua tools/gen_spawns.lua --report   # counts per instance and floor, size
```

## Boss facts (boss pages, portraits, run mode)

`Data/Bosses/*.lua` is generated by `tools/gen_bosses.lua` from `data-src/bosses/*.json` (schema and gaps:
`data-src/bosses/README.md`): per boss of the 43 recommended plans the NPC ID, creature display ID (portrait), level,
classification, up to eight abilities (spell IDs with a tag such as interrupt or dispel and sometimes a short note of our
own), drop item IDs, and per instance the dungeon quest IDs (giver NPC, objective items). Only IDs and numbers ship; the
game supplies the names, icons and descriptions of spells and items at runtime (`C_Spell`, `GetItemInfo`), so no
description or strategy text is copied from any source. Every value in the JSON names its source, and values inferred
from the wording of a spell (a tag, not stated by a source) are marked `inferred`; a value no source gave is left out.

| Source | Licence | Used for |
|---|---|---|
| [Wowhead Classic](https://www.wowhead.com/classic) NPC and zone pages | web; facts only | Creature display IDs, levels, classification, drop lists (non-world drops of quality uncommon and up), dungeon quest IDs, levels and sides. Fetched once each, politely rate limited; nothing else was taken from the site |
| [Wowhead Forever](https://www.wowhead.com/forever) Dungeon Journal pages and dungeon guide pages | web; facts only | Boss NPC IDs, ability spell IDs and the flags Wowhead gives them (tags), drop lists, quest IDs, levels, sides, quest givers and objective items, creature display IDs, and which classic drops Forever adds. One request about every 8 seconds, standard pages only; its NPC, item, spell and quest pages sit behind a bot check and were not used. No text, screenshot or map is copied; every `note` is ours |
| [Warcraft Wiki](https://warcraft.wiki.gg) boss, instance, item and quest pages | CC BY-SA 4.0; facts and IDs only | Ability spell IDs and the type tags the pages give them (interruptible, dispellable, tank, healer), NPC IDs of Forever bosses, the items Forever adds to classic bosses, the loot tables and quest lists of Forever's new dungeons, item and quest IDs. No wiki text is copied: every `note` is written by us |
| Questie (GPL), AtlasLoot (GPL), NeedRoll (GPL), ForeverDungeonJournal (no licence) | not used as sources | Not read for these tables; a value that disagreed with them was looked at again on the sources above |

Method and Warcraft Tavern's Forever guides were read for the order and kind of mechanics only; no value of this
dataset comes from them. Wowhead's Forever dungeon guides (Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of
Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison) were also read against the plans' boss order and strategy notes
(2026-11-16); where a note contradicted them it was corrected in our own words, and the journal and guide values are the source
of the IDs above. `lua tools/gen_bosses.lua --check` (CI) fails on invalid JSON, on a boss of a recommended plan
without an entry, and on a generated file that is out of date.

The same files carry each instance's **keys and attunements** (`keys`, Prep's list): item and quest IDs, English names
and a short note of our own, researched on warcraft.wiki.gg item, quest and instance pages and its World of Warcraft:
Forever page (CC BY-SA 4.0, facts only). Only Onyxia's Drakefire Amulet, Upper Blackrock Spire's Seal of
Ascension, the Dalaran Sewer Key and the Krol'dok Compound Key are confirmed for Forever by a source; the classic keys
are shown as classic facts. Details and what was left out: `data-src/bosses/README.md`.

## Travel facts (Prep's "Getting there")

`Data/TravelData.lua` is generated by `tools/gen_travel.lua` from `data-src/travel/` (`data-src/travel/README.md`):

| Source | Licence | Used for |
|---|---|---|
| [OpenMap](https://github.com/openmap-world/openmap) `Data/Forever/Places.lua`, `FlightData.lua` (generated by OpenMap from the game's tables), read from a local install by the tool | MIT ([copy](licenses/OpenMap-LICENSE.txt)) | Instance entrances (world yards, or a spot on the zone map for Forever's new dungeons), flight masters with their factions, boats, zeppelins and airships |
| OpenMap `Data/Forever/Tones.lua`, `Banners.lua` (the game's map table) | MIT | The uiMapID of each zone and city an entrance or a summoning stone is placed on (`zoneMap` in `places.json`) |
| [Warcraft Wiki](https://warcraft.wiki.gg): the World of Warcraft: Forever page, instance pages, zone pages | CC BY-SA 4.0; facts only | The outside zone, the area the entrance lies in, how it is entered, the zone's faction, Forever's summoning stones (City of Dalaran, Excavation Site: Wetlands); each hint is written by us |

The nearest flight master, the direction and the distance from it are computed by the addon (`Model/Prep.lua`) from
these positions, so the "fly to X, then go south-west" lines are ours. A boat or zeppelin leg is marked as one
faction's by the generator when that is the only faction the flight masters within 1000 yards of both its docks
serve (OpenMap's flight data), and named after those flight masters' towns. Only the sources above are used.

## Other addons' data at runtime (not shipped)

The data providers (`Data/Providers/`, docs/COMPATIBILITY.md section 6) read Dungeon Journal, Forever Dungeon Routes,
OpenMap, NeedRoll and Questie in the player's own client while those addons are installed: maps, routes, boss pins,
loot, portraits, quests. The bundled boss facts above are shown first and what a provider
adds (description, summon item, anything the bundle lacks) after them. None of
it is copied into this repository, the generated plans or the spawn data; the exclusions below are about what ships.

## What is excluded, and why

- **AllTheThings** (its licence is unclear: the repository carries two different statements). Nothing from it ships:
  the generator drops every value whose source is AllTheThings (outdoor entrance spots, a few object markers) and, in
  plans whose research relied on it for journal instance IDs and first-floor map IDs, those IDs too. The addon matches a
  plan to the client's Adventure Guide by name instead and takes the floor's map from the journal's dungeon map (or a
  same-named map), which works on an English client (`/dp scan` saves what a client returns). To ship
  those IDs after the licence is cleared, set `ALLOW_ATT_IDS = true` in `tools/gen_plans.lua`.
- **NeedRoll** (GPL-3.0, incompatible with this project's MIT licence). It was consulted only to cross-check boss names
  and order. No coordinate, ID or text of it is included, and the generator drops any value that cites its data.
- **ForeverDungeonJournal** (no licence file): looked at only; nothing used.
- **aetherflask.com** walkthrough maps (offline since 2022, mirrored at eintr.net): not used directly. Forever Dungeon
  Routes states that its classic dungeon routes were traced from them; those routes are included as part of Forever
  Dungeon Routes' MIT data (section "Imported routes" below).
- **Santiago Reyes' maps as other addons ship them** (Forever Dungeon Routes, Dungeon Journal): not taken; read locally
  only to check which picture a route was drawn on. The maps Dungeon Planner bundles come from his own published files
  with his permission ("Bundled maps" below).
- Anything without a source, unless the research marks it as an estimate.
- Points without coordinates never become map markers. They stay in the plan as encounters (boss order), as lines in the
  plan note ("Not on the map"), or in the order list.
- Researcher remarks about sources, licences and unsure data are removed from the text that ships.

## Bundled maps: Santiago Reyes

The maps of WoW: Forever's nine new dungeons in `Media/Maps/Reyes/` (18 floors) are **Santiago Reyes'** artwork, from
his "Atlas de Azeroth: Forever" (<https://sreyesmaps.com>), bundled **with his permission** (given on 2026-11-16 by
direct message). They are (c) Santiago Reyes and **not** under the project's MIT licence:
[licenses/SantiagoReyes-maps.md](licenses/SantiagoReyes-maps.md) records the permission, what was done to the files
and the full list. Like his maps? Support the artist: <https://sreyesmaps.com/donaciones>.

| Source | Terms | Used for |
|---|---|---|
| His published files on sreyesmaps.com (3000 x 2000 JPEG, the current version of each map on 2026-11-16) | (c) Santiago Reyes, used with his permission; not MIT | The map of every Forever floor he has drawn: Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran (city, Underbelly), The Drowned City (city, Atal'Byzal), Krol'dok Stronghold, Alcaz Prison (main and maximum security units), Blackmaw Hold (six levels), Shaper's Terrace (terrace, Prismatic Talus) |

`tools/reyes_maps.py` converts them without changing the pictures: scaled to 1024 x 683 (the size and crop the Dungeon
Journal and Forever Dungeon Routes addons use for the same pictures, checked: the same geometry, no offset), cut into
three 1024 x 256 strips, stored as BLP2 with DXT1 compression (6.8 MiB in all). No recolouring, nothing cut away; his
titles and signature stay. The plans' coordinates are in that picture's space already, so routes and markers land
where they do on those addons' maps. The map credits him in its corner ("Map by Santiago Reyes"); the README, the
addon's page and the settings credit him too.

```sh
uv run --script tools/reyes_maps.py --work <scratch folder>            # Media/Maps/Reyes/*.blp
uv run --script tools/reyes_maps.py --work <scratch folder> --check    # exit 1 when a file would change
```

## Imported routes: Forever Dungeon Routes

The recommended plans of the classic dungeons, the raids and Forever's new dungeons take their routes from
[Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes) (version 1.2.4, CurseForge
"forever-dungeon-routes"), under its MIT licence: Copyright (c) 2026 Checkov23, the notice is in
[licenses/ForeverDungeonRoutes-LICENSE.txt](licenses/ForeverDungeonRoutes-LICENSE.txt), each affected plan's notes end
with "Route: Forever Dungeon Routes (MIT), by Checkov23.", and each routes file names the version and route it came from.

### Licence check (2026-11-16, version 1.2.4)

| File in its repository | What it is | Status here |
|---|---|---|
| `LICENSE` | MIT, "Copyright (c) 2026 Checkov23", for "this software and associated documentation files"; no exclusion in it | Applies to everything below except the pictures |
| `README.md`, "License" and "Credits"; `ForeverDungeonRoutes/maps/CREDITS.txt` | The one exclusion: the 16 map pictures in `ForeverDungeonRoutes/maps/` (`*.blp`) are by Santiago Reyes, used with his permission, not under the MIT licence. The credits also say its standard routes of the classic dungeons were traced from the aetherflask.com walkthrough maps (mirrored at eintr.net) | Pictures: not taken from it (read locally only to check they are the same pictures the Dungeon Journal addon draws; the maps Dungeon Planner bundles come from his own site, with his own permission: "Bundled maps" below). Classic routes: included, see below |
| `ForeverDungeonRoutes/ForeverDungeonRoutes.toc` | `X-License: MIT`, `X-Copyright: Copyright (c) 2026 Checkov23` | Agrees |
| `ForeverDungeonRoutes/Data/DefaultRoutes.lua` | The routes: per dungeon `paths` (main and side, 0..1 on a floor), `stops`, `notes`, `links`, and a `source` per route | MIT. **Imported**, every route: the raids ("WoW dungeon journal (boss positions), paths over the walkable floors in the game's files"; Zul'Gurub "Boss areas of the game (AreaTable) and the skulls of its map"), the 9 new Forever dungeons ("Route from several guides and addons", "Rough route from a video guide"; places only, the paths drawn over the floors), and the 25 classic dungeons, whose `source` is "aetherflask.com (via eintr.net)": the file's header says their geometry was traced from the aetherflask.com walkthrough maps, which state no licence of their own. The project chose to include these routes; each of those plans' routes file records it (`"traced"` in its import block). Of a dungeon with several routes, the one whose stops name the most of the plan's bosses (Stratholme's living and undead sides), else the "Full clear". Scholomance is not imported: its routes are drawn on the client's later Scholomance map, which our plan does not use |
| `ForeverDungeonRoutes/Data/Floors.lua` | The game's map tables (UiMap names, the art's tile file IDs) | Facts of the game; read to match its floors to ours by tile file ID, not copied |
| `ForeverDungeonRoutes/Data/Pictures.lua` | Its picture floors (names, world frame, which picture) | Read to match its Forever floors to ours by name; not copied |
| `ForeverDungeonRoutes/Data/Dungeons.lua` | Dungeon names, instance IDs, floor lists | Read to match dungeons by name; not copied |
| `Data/Encounters.lua`, `Rooms.lua`, `Minimaps.lua`, `Entrances.lua`, the Lua code, `media/`, `docs/screenshots/` | Encounter IDs, room boxes, minimap tiles, entrances, its UI | Not used by the import (the runtime adapter reads `Rooms` only to count them) |

What the import does (`tools/import_routes.py`, run on a local clone; nothing of it is fetched at build time):

- Floors: classic floors are the game's dungeon map tiles in both addons, matched by the file ID of each floor's first
  tile (read from the game's local storage); Forever floors by name, after checking that its picture is the same as the
  one our plan is drawn on (correlation >= 0.9: all 16 of its pictures are the Dungeon Journal's, same crop), through
  the same alignment the map adapters use (`Providers.Align`).
- Stops: matched to our steps by name (also the name the game uses that its note gives, "Called Magmatus in the game")
  or nearness. Our measured positions stay; estimated or unplaced ones take its position ("fill"). Its stops our research
  lacks become added steps when they lie on its paths ("add"; rares off its paths are left out). Our step order, pulls
  and bosses stay as they are.
- Paths: between two consecutive stops of our route on a floor, the shortest way along its main and side paths
  (its paths joined where one ends on another); legs it does not cover keep our computed bends. Its side paths are
  optional routes; on a floor where our plan has fewer than two placed stops, its main path is an optional route too
  ("Way through this floor").
- Parchment and water check (classic maps): a stretch of its path of at least 4 px off our walkable mask and over the
  bare parchment around the dungeon (what does not differ from the per-pixel median of every old dungeon map, the
  region `tools/route_paths.py` uses) or over water (grey-green or blue and light, where parchment and rock are brown;
  areas of 400 px or more) is re-routed with our pathfinder and logged. Where our pathfinder cannot mend it, that leg
  keeps our computed bends and a side path is left out. Its stops on the bare parchment off the map's art are not used.
  Result: 8 stretches re-routed (Wailing Caverns 4, Blackrock Depths 2, Dire Maul East 1, Gnomeregan 1), 3 legs left
  to our bends (Blackrock Depths, Gnomeregan, the Deadmines' entrance), 1 side path left out (Blackrock Depths), 7 stops
  off the art not used (Wailing Caverns: Lord Pythas, Skum, the Deviate Faerie Dragon; Stratholme: Crimson
  Hammersmith, Stonespine, Baron Rivendare; Blackfathom Deeps: Lorgus Jett). A final audit of everything that ships
  counts 0 stretches over parchment or water (`"check"` in each import block).

## Maps from the game's minimap pictures

The floors that have no map art in the client (Forever's nine new dungeons, Scholomance's old layout) are drawn at
runtime from the client's own minimap pictures, the ones the minimap shows in the corner of the screen inside those
instances (`Data/MinimapArt.lua`). `Data/MinimapArtData.lua` holds only file IDs and numbers: which pictures make up
each floor, the box each covers, its texture coordinates, and a transform from the plan's coordinates to the map's.
`tools/minimap_art.py` writes it from `data-src/minimaps.json` (which pictures: the terrain tiles, or some parts of one
building) on a local game install, read-only:

| Source | Licence | Used for |
|---|---|---|
| The game's files: the instance map's WDT and terrain object files, the buildings' WMO files, the client's `WMOMinimapTexture` table, the minimap pictures themselves | Blizzard's, not copied | Which pictures exist and where each lies (file IDs, world positions, rotations). Formats as documented on [wowdev.wiki](https://wowdev.wiki/) (ADT, WDT, WMO, Minimap). Some of the new dungeons' files are encrypted; the tool decrypts them with the keys the client keeps in its own hotfix cache |
| [Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes) `Data/Pictures.lua` (frames), `Data/Floors.lua` (map rectangles), `Data/Minimaps.lua` (cross-check) | MIT | The affine frame world -> picture it states for each Forever floor's picture, which turns our plans' coordinates (placed on the same pictures) into world positions; the classic map rectangles for Scholomance; its own lists of which building parts make up each floor of Blackmaw Hold, Alcaz Prison and Scholomance, used to pick the same parts |

The plans are not regenerated: each floor's transform is stored with the floor and the map draws the plan through it,
so the same plan still fits the providers' pictures (Providers.Align). The work folder of the tool gets one preview per
floor (the composed map with the plan's route, stops and markers drawn on it); keep it outside the repository.

```sh
uv run --script tools/minimap_art.py --game "<World of Warcraft>/_forever_" --work <scratch folder>
uv run --script tools/minimap_art.py --game ... --work ... --check   # exit 1 when Data/MinimapArtData.lua would change
```

## Route bends

`data-src/routes/<slug>.json` holds, per plan floor, the bends between consecutive route stops and the moves of estimated
stops and markers that sat in a wall. `tools/route_paths.py` computes them from the floor pictures (a walkable mask and
a cheapest path down the middle of the corridors), except the legs an imported route covers (above);
`tools/gen_plans.lua` puts them into the plans. How, the file
format, per-floor fixes and the known gaps: `data-src/routes/README.md`.

## Regenerating

```sh
lua tools/gen_plans.lua            # writes Data/Plans/<slug>.lua and the block in DungeonPlanner.toc
lua tools/gen_plans.lua --check    # exits 1 when a generated file is out of date (CI runs this)
lua tools/gen_plans.lua --report   # also prints the licence audit: values used and dropped per source class
```

The output is deterministic. `tests/test_plans.lua` loads every generated plan, validates it, and checks that no source
or licence remark reached the shipped text.
