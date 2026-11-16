# Dungeon data sources (`data-src/dungeons`)

One JSON file per dungeon or raid, UTF-8, LF. These are research sources for ready-made plans; the addon does not load
them: `lua tools/gen_plans.lua` turns them into the recommended plans in `Data/Plans/` (rules, credits and exclusions
in `docs/DATA-SOURCES.md`). Sections below are written by separate research passes: edit your own section only.

## Status: bundled plans

All 43 files are generated into recommended plans (31 low confidence, 12 medium). The generator drops values whose
source is AllTheThings or NeedRoll's own data, anything without a source unless it is marked `approx`, and null
coordinates (those points stay as encounters or lines of text); it also removes researcher remarks about sources and
unsure data from the text that ships. Points that name a source in `sources[]` keep the source id; add new sources to
`sources[]` with an honest `url` and `what`, because the generator classifies them from those two fields.

## Schema (version 1)

```json
{ "schema": 1, "updated": "2026-11-16", "slug": "zulfarrak", "name": "Zul'Farrak", "kind": "dungeon", "origin": "classic", "originSource": 90,
  "levelRange": [42, 46],
  "ejInstanceID": null, "maps": [ { "uiMapID": 219, "floor": 1, "name": "Zul'Farrak" } ],
  "sources": [ { "id": 1, "url": "...", "what": "...", "forever": true } ],
  "confidence": "low|medium|high",
  "points": [ { "id": "p1", "kind": "boss", "name": "...", "npcID": 0, "uiMapID": 219, "x": 0.5, "y": 0.3,
                "approx": false, "source": 1, "note": "..." } ],
  "route":   [ { "step": 1, "uiMapID": 219, "x": 0.1, "y": 0.9, "note": "...", "point": "p0" } ],
  "pulls":   [ { "n": 1, "points": ["p3"], "note": "..." } ],
  "positions": [ { "boss": "p1", "role": "tank", "uiMapID": 219, "x": 0.5, "y": 0.33, "note": "..." } ],
  "strategies": [ { "boss": "p1", "text": "..." } ], "notes": "..." }
```

- `updated` (required): the date the file's research data last changed, `YYYY-MM-DD`. Change it with the data.
  `gen_plans.lua` writes it as the plan's `updated` time (00:00 UTC), and the addon shows it as the plan's data date.
- `origin` of a file: `forever` (the instance is new in WoW: Forever) or `classic` (from the original game), with
  `originSource` naming the source in `sources[]` (id 90 in every file: warcraft.wiki.gg's WoW: Forever page, which
  marks each instance new or old; the nine new dungeons confirmed by Warcraft Tavern's announcement and their instance
  map IDs, 2959-3065, by the client's encounter table). New: the nine Forever dungeons and the Hyjal Summit raid. No
  source marks a classic dungeon as reworked, so there is no third value. `gen_plans.lua` puts it on the plan's
  `instance`.
- `kind` of a file: `dungeon` or `raid`. `kind` of a point: boss, pack, patrol, rare, loot, chest, quest_item,
  quest_npc, interactive, entrance, exit, shortcut, hazard, note. `role`: tank, healer, melee, ranged, all.
- Coordinates are normalized 0..1 on the floor picture. Points outside the dungeon (portals, quest givers) have
  `floor` 0 and the zone's uiMapID.
- `approx: true` means estimated , not measured.
- Extensions used by the "above 30 and raids" files: `x` and `y` may be `null` (position unknown, order still
  meaningful); `floor` (1-based index into `maps`) is on every point; `maps[].uiMapIDInferred: true` marks a uiMapID I
  derived as "first floor + n" and did not verify; `instanceMapID` is the game's instance map ID (GetInstanceInfo #8);
  route steps and positions carry `floor` and `approx` too.

## Levels above 30 and raids

Research pass of 2026-11-15 (build 1.60.1, Interface 16001). Scope: 5-player dungeons whose level range starts above 30,
plus all raids at a lower level of detail. Level ranges are the client's Group Finder tables (OpenMap `Places.lua`);
NeedRoll's ranges differ slightly; only the client table is used.

### Dungeons (21 files, ascending level)

| Slug | Levels | Status | Confidence |
|---|---|---|---|
| the-drowned-city | 35-42 | bosses and order only, no coordinates | low |
| scarlet-monastery-armory | 36-44 | Herod only, no coordinates | low |
| razorfen-downs | 37-46 | bosses placed | medium |
| scarlet-monastery-cathedral | 38-46 | 3 bosses, order only, no coordinates | low |
| kroldok-stronghold | 40-47 | order and quests, no coordinates | low |
| uldaman | 41-51 | bosses placed | medium |
| zulfarrak | 44-54 | bosses placed, route estimated | low |
| maraudon | 46-55 | bosses placed, route estimated | low |
| alcaz-prison | 48-55 | order from one guide, no coordinates | low |
| temple-of-atalhakkar | 50-60 | order only; 3 bosses placed | low |
| blackrock-depths | 52-60 | bosses placed, route estimated | medium |
| dire-maul-east | 54-60 | 4 of 6 bosses placed, OpenMap names corrected | low |
| blackmaw-hold | 55-60 | boss list only, order is a guess | low |
| lower-blackrock-spire | 55-60 | positions yes, walking order unsure | low |
| dire-maul-west | 56-60 | bosses placed | low |
| dire-maul-north | 56-60 | bosses placed | medium |
| scholomance | 58-60 | order only, no coordinates | low |
| stratholme-live | 58-60 | order; 4 of 7 bosses placed | low |
| stratholme-undead | 58-60 | bosses placed | medium |
| shapers-terrace | 58-60 | boss spots described in words, no coordinates | low |
| upper-blackrock-spire | 59-60 | order; only Emberseer placed | low |

Left to the other pass because their range starts at 30 or below: Scarlet Monastery Graveyard (30) and Library (33
in the client table, 29 in NeedRoll), Gnomeregan, Razorfen Kraul, City of Dalaran, Excavation Site Wetlands, and so on.
Boundary cases to check: SM Library (33 in the client table) and SM Graveyard (30) were not done here.

### Raids (8 files, boss positions and order only, trash skipped)

onyxias-lair (medium; 1 boss), molten-core (low), blackwing-lair (low), zulgurub (low), ruins-of-ahnqiraj (medium),
temple-of-ahnqiraj (low), naxxramas (low), hyjal-summit (low; not open yet, names only, no positions). Raids have no
role positions.

### Sources and licences

| Source | Used for | Licence and how it was used |
|---|---|---|
| OpenMap `Data/Forever/DungeonBosses.lua`, `Places.lua`, `DungeonMaps.lua` | boss positions (Blizzard journal data), level ranges, instance IDs, floor names, Forever-only dungeon entrance spots | MIT. The only source of boss coordinates. |
| NeedRoll (`Data/Maps.lua`, `Entrances.lua`, `Dungeons/*.lua`, `Raids/*.lua`) | cross-check only: to confirm OpenMap boss pins and the Dire Maul East name fix | GPL-3.0. No coordinates, entrance spots, rare spots or NPC IDs were copied from it, so none of its values are in these files (removed 2026-11-15 because this data is bundled into an MIT addon). Boss names and kill order are plain facts. |
| AllTheThings `db/Camelot/Categories/Instances.lua` | journal instance IDs, first-floor uiMapIDs, object IDs, outdoor entrance spots for some Classic dungeons, a few descriptions (paraphrased) | LICENSE says MIT, `LICENSE.txt` says all rights reserved: cross-check only. |
| ForeverDungeonJournal | opened to look at its data layout; no values used | no licence file (author Exehn): treated as all rights reserved; nothing copied. |
| Warcraft Tavern (Forever guides) for Krol'dok, Drowned City, Alcaz, Blackmaw, Shaper's Terrace | boss order, route, panels, quest NPC names and coordinates, entrances | web, paraphrased in my own words |
| Wowhead | tried; the instance NPC/object pages return no coordinates to a plain fetch, so not used | |

### Estimated or conflicting

- Only OpenMap boss pins (and a few web-guide quest NPC spots) are real coordinates. Where OpenMap has no pin (Scarlet
  Monastery wings, Scholomance, Upper Blackrock Spire except Emberseer, Naxxramas, most of Zul'Gurub, rares, Atal'Hakkar
  dragons, and so on) the point keeps its name, kind and order but `x`/`y` are null.
- Entrances inside dungeons are null everywhere. Outdoor entrance spots remain only where AllTheThings, the client
  tables (OpenMap `Places.lua`) or a web guide give them; the rest are null.
- Role positions (tank, melee, ranged, healer) are generated from a boss position that has coordinates; all `approx`.
  Bosses without coordinates have none.
- All routes are typical clears, not measured. Trash pulls are only boss pulls plus a note.
- Conflicts: Dire Maul East (OpenMap's boss names are rotated against its coordinates; corrected after cross-checking
  against NeedRoll, which only confirmed the name pairing). Other possible OpenMap vs. in-game differences (Stratholme
  Forresten/Timmy, Maraudon Gizlock, Molten Core Geddon, Blackwing Lair floors) are not resolved: the OpenMap value is used.
- uiMapIDs: only first floors are verified (via AllTheThings); later floors are `uiMapIDInferred` (first + n); Dire
  Maul, Blackmaw Hold and all Forever-only dungeons have no uiMapID (null). Use `instanceMapID` plus the floor name.

### Known gaps

- Forever-only dungeons (Drowned City, Krol'dok, Alcaz, Blackmaw, Shaper's Terrace) and Hyjal Summit have no map pins
  in any MIT or web source I could read, so bosses carry null coordinates and only the order is meaningful.
- No NPC IDs at all (the only ones I had came from NeedRoll and were removed).
- Missing: positions of every boss OpenMap does not pin; chests, quest NPCs and trash packs for most dungeons; loot
  beyond a few notes.
- Many strategies are short summaries of Classic behaviour and may differ in Forever's reworked versions.

## Levels up to 30

Research pass of 2026-11-15 (build 1.60.1, Interface 16001). Scope: 5-player dungeons whose level range starts at or
below 30 in the client's Group Finder table (OpenMap `Places.lua`), plus the two Scarlet Monastery wings the first pass
left over. 14 files, ascending by start level. Everything above applies (schema, extensions). Additions used here:
`idSource` on points that carry an `npcID`/`itemID` (the source that confirmed the ID), `x`/`y` null where no position
exists, and `uiMapID` null (with `instanceMapID` and the floor name) for the Forever-only dungeons.

### Dungeons

| Slug | Levels | What is in it | Confidence |
|---|---|---|---|
| ragefire-chasm | 13-18 | 2 of 4 bosses placed (art estimates), order, strategies | low |
| hall-of-thanes | 13-20 | 3 of 4 bosses placed (art estimates), order, strategies | low |
| ruins-of-lordaeron | 15-22 | 2 of 6 bosses placed (estimates), order, events, strategies | low |
| wailing-caverns | 15-24 | 8 of 9 placed (measured), order, quest items, strategies | medium |
| the-deadmines | 17-26 | 7 bosses placed (measured), order, quest items, strategies | medium |
| shadowfang-keep | 20-30 | 2 measured, 5 art estimates, 2 unplaced; order, strategies | low |
| blackfathom-deeps | 24-32 | 6 of 8 placed (measured), floors 1-3, strategies | medium |
| the-stockade | 24-32 | 3 of 6 placed (art estimates), order, quest items | low |
| excavation-site-wetlands | 26-33 | 3 of 4 bosses placed (estimates), Titan panel, strategies | low |
| city-of-dalaran | 28-35 | 4 of 8 bosses placed (estimates), entry and secret boss notes | low |
| gnomeregan | 29-38 | 5 of 6 bosses placed (measured), two entrances, strategies | medium |
| razorfen-kraul | 29-38 | 5 of 8 placed (measured), order, strategies | medium |
| scarlet-monastery-graveyard | 30-38 | 2 bosses (art estimates), order only | low |
| scarlet-monastery-library | 33-41 | 2 bosses (art estimates), order only | low |

Level ranges are the client table; NeedRoll and Method differ in places (Hall of Thanes 13-18, Ruins 15-20, Excavation
24-29, SFK 22-30, WC 17-24, SM Library 29-39) and the notes in each file say so.

### Sources and licences

| Source | Used for | Licence and how it was used |
|---|---|---|
| OpenMap `DungeonBosses.lua`, `Places.lua`, `DungeonMaps.lua` | boss coordinates (`source` "om", `approx: false`), level ranges, instance map IDs, floor names | MIT. The only measured coordinate source. Only Wailing Caverns, Deadmines, Blackfathom Deeps, Gnomeregan, Razorfen Kraul and two Shadowfang bosses have pins. |
| Wowhead Classic NPC and item pages | every `npcID` / `itemID` in these files (`idSource`): each ID was opened and its title matched the name | web; no coordinates (instance NPCs have none). IDs the pages do not confirm (Forever-only NPCs, 26xxxx) are left out. |
| Method.gg WoW Forever dungeon guides (`/wow-forever/dungeons/<slug>`) | boss order, mechanics, trash, quest items, quest NPCs, entrances | web, paraphrased in my own words. Not read for the two Scarlet Monastery wings. |
| warcraft.wiki.gg `UiMapID` table | uiMapIDs of Classic dungeon floors | web; retail numbering, not verified in the Forever client (ATT-checked first floors by the other pass agree for Razorfen Downs 300). |
| Dungeon map pictures in `NeedRoll/Media/Maps` (Blizzard art; Santiago Reyes art for the Forever-only dungeons) | viewed to read portals, tinted boss rooms and room labels | not copied; every point read from a picture is `approx: true`, `source` "art". The Reyes art is his, not NeedRoll's GPL. |
| NeedRoll (`Maps.lua`, `Dungeons/*.lua`, `Bosses.lua`, `Entrances.lua`) | cross-check only | GPL-3.0 and this project is MIT, so no NeedRoll coordinates, NPC IDs or item IDs are in the JSON. Its pins agree with the art estimates where compared; it disagrees with OpenMap on Gnomeregan (swapped names, Viscous Fallout floor) and Mr. Smite, and OpenMap was used. |
| ForeverDungeonJournal, AllTheThings | looked at only; nothing copied | no licence (FDJ) / ambiguous licence (ATT) |

### Estimated or conflicting

- Role positions are generated from the boss and the previous route stop; all `approx: true`. Bosses with null
  coordinates have none.
- Routes are typical clears plus waypoints read off the maps; floor-change points (stairs, doors) are not on the map
  pictures, so some steps carry only an order and a note.
- Trash packs are few and are estimates with a Method description of the pack, not measured spawns.
- Conflicts: Gnomeregan Electrocutioner / Crowd Pummeler / Viscous Fallout (OpenMap used, agrees with room tints);
  Razorfen Kraul Roogug (OpenMap's value equals Jargba's, left unplaced); Deadmines Mr. Smite.
- Gnomeregan has a sixth boss "Mechanical Menagerie" in the client's boss list that no guide covers; it is unplaced.

### Known gaps

- No measured positions for Ragefire Chasm, The Stockade, Hall of Thanes, Ruins of Lordaeron, Excavation Site,
  City of Dalaran, either Scarlet Monastery wing, or most of Shadowfang Keep: only estimates read off the map art,
  or none. Rares (Miner Johnson, Lorgus Jett, Baron Aquanis, Halmgar, Blind Hunter, Deathsworn Captain, SM rares) and
  Highland Horror, Plunder, Razorclaw, Kam Deepfury, Bazil Thredd, Bruegal have no position.
- Forever-only dungeons have no uiMapID; Forever NPC IDs have no open source.
- Quest NPCs inside dungeons (Willix, Heralath, Kerbonee, Emi Shortfuse, Captain Truman, Thaelrid, Dalaran's three)
  have no position; Warden Thelwater, Ghostly Attendant and the Disciple of Naralex are placed as estimates.
- Chests and loot tables are not covered; there are no chests in any of these dungeons per Method.
- The two Scarlet Monastery wings have short strategies from Classic knowledge, not from a Forever guide; Forever may
  have changed them.
