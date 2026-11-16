# Creature spawns (`data-src/spawns`)

Where enemies stand on a dungeon or raid floor: the data behind the map's "Enemies" layer (`Data/Spawns.lua`,
`ns.Spawns.For(plan, floorIndex)`). `lua tools/gen_spawns.lua` turns the inputs below into `Data/Spawns/<instance>.lua`;
the addon never reads this folder. Short version: **no openly licensed database of creature spawns inside dungeons
exists, and the client does not let an addon record them**, so what ships is what the project's own research already
placed.

## What ships

| Kind | Count | Where it comes from | Accuracy |
|---|---|---|---|
| `boss` | 178 | the recommended plans' boss markers (`data-src/dungeons`; OpenMap's boss pins, MIT, for most) | 152 measured pins, 26 estimates read off the map art |
| `mob` | 19 | the plans' trash packs (named after the pack, not one creature) | estimates (`approx`) |
| `npc` | 5 | the plans' quest NPCs inside the dungeon | estimates (`approx`) |
| `rare`, `elite` | 0 | nothing placed yet | |

202 points in 33 of the 43 instances (59 floors); 47 of the bosses carry an NPC ID (checked on Wowhead Classic). No
levels. `elite` is set for bosses only (the research does not say which trash is elite). Points of the zone outside an
instance are left out, as are plan markers without a position.

| Instance key | Spawns per floor (floor:count) |
|---|---|
| blackfathomdeeps | 1:7 2:2 3:1 |
| blackrockdepths | 1:7 2:12 |
| blackwinglair | 1:2 3:3 4:3 |
| cityofdalaran | 1:4 |
| deadmines | 1:3 2:7 |
| diremauleast | 1:1 2:3 |
| diremaulnorth | 1:7 |
| diremaulwest | 1:2 2:1 3:2 |
| excavationsitewetlands | 1:3 |
| gnomeregan | 1:2 2:2 3:2 4:1 |
| hallofthanes | 1:6 |
| lowerblackrockspire | 1:1 2:2 3:1 4:1 5:3 6:1 |
| maraudon | 1:4 2:4 |
| moltencore | 1:10 |
| onyxiaslair | 1:1 |
| ragefirechasm | 1:5 |
| razorfendowns | 1:4 |
| razorfenkraul | 1:7 |
| ruinsofahnqiraj | 1:6 |
| ruinsoflordaeron | 1:2 |
| scarletmonasterygraveyard | 1:2 |
| scarletmonasterylibrary | 1:2 |
| shadowfangkeep | 1:4 2:1 4:1 6:2 7:1 |
| stockade | 1:4 |
| stratholmelivemaingate | 1:4 |
| stratholmeundeadserviceentrance | 1:1 2:5 |
| templeofahnqiraj | 1:6 2:1 3:1 |
| templeofatalhakkar | 1:3 |
| uldaman | 1:7 2:1 |
| upperblackrockspire | 6:1 |
| wailingcaverns | 1:12 |
| zulfarrak | 1:6 |
| zulgurub | 1:2 |

`lua tools/gen_spawns.lua --report` prints this table from the current data.

**Gaps.** Nothing at all for Alcaz Prison, Blackmaw Hold, The Drowned City, Krol'dok Stronghold, The Shaper's Terrace,
Hyjal Summit, Naxxramas, Scholomance and the Scarlet Monastery Armory and Cathedral (their research has no positions).
Everywhere else ordinary trash is missing except the few packs above: the layer is far from the mob-by-mob picture
Questie draws in the open world.

## Coordinates

Everything is in the plans' own space: 0..1 on the floor's classic dungeon map (the `Interface\WorldMap\<Dir>\<Name>
<floor>_1..12` tiles, 1002 x 668), floor `i` being the instance's `i`-th map, exactly as `Data/GameFiles.lua` picks the
tiles. So no transform is applied, and `tests/test_spawns.lua` checks it: every boss marker of every recommended plan
has a boss spawn of the same name at the same spot (largest offset 0, after rounding to 4 decimals).

The game's world coordinates (yards) cannot be used directly: turning them into these maps would need each floor's
world rectangle from the classic clients' dungeon map tables, which no source here provides. A file in this folder
must therefore give floor coordinates.

## Sources looked at, and why they are not used

| Source | Licence | Finding |
|---|---|---|
| [OpenMap](https://github.com/openmap-world/openmap) | MIT | Ships no NPC spawns. Its townsfolk and rare-mob pins are read at runtime from Questie's database (`Map/Townsfolk.lua`); its own notes say Questie knows no places inside dungeons, so inside a dungeon it pins bosses only (`Data/Forever/DungeonBosses.lua`, already used through the plans). While you are inside, it shows you at the instance's entrance. |
| [ForeverPlusPlus](https://github.com/xIGBClutchIx/ForeverPlusPlus) | MIT | No spawn tables; reads QuestieDB at runtime (`Lib/QuestieDB.lua`). Source of the fact that the client has no dungeon-type UiMap. |
| [ryna_agent](https://github.com/MaddisonM79/ryna_agent) | MIT | API notes only. Creature GUIDs keep the NPC ID in field 6 in the open world (`docs/forever-client-api.md`). |
| [Fellowship Ledger](https://github.com/TankerALane/fellowship-ledger) | MIT | No spawn data. Its in-game check of 2026-11-09 found `UnitGUID("target")` to be a secret value for every creature inside a dungeon (`docs/DECISIONS.md`, D-113). |
| Questie / QuestieDB | GPL-3.0; older content "all rights reserved" | Not used (licence). Its instance NPCs have no positions inside dungeons anyway. |
| pfQuest | code MIT, database generated from VMaNGOS / CMaNGOS | Not used: the data's origin is GPL. |
| CMaNGOS, vMaNGOS, TrinityCore, AzerothCore | GPL-2.0 / AGPL-3.0 | Not used, not copied. |
| Wowhead Classic NPC pages | no open licence | Instance creatures carry an empty map (`g_mapperData = []`) on the Classic and Cataclysm sites; not usable, and not licensed for reuse in any case. |
| The game client's tables | Blizzard | Creature spawns are server data; the client has none. |

## The in-game spawn recorder: not built (a run recorder is)

A recorder would note, while you play, where you stand when you target or attack a hostile mob inside a dungeon, and
build spawn points from that. It needs two things the client does not seem to give inside instances:

- **Your position on the floor.** The client has no dungeon UiMap (ForeverPlusPlus; `/dp scan`: `C_Map.GetMapInfo`
  returns nothing for the classic dungeon map IDs 213, 221-223, 225-229, 279, 291, 292, 301-303 and 310-316), so `C_Map.GetPlayerMapPosition`
  has no floor to answer on; and `UnitPosition` and map positions are hidden inside instances on the Retail 12.x API
  that Forever runs (docs/COMPATIBILITY.md, section 2). OpenMap falls back to the instance entrance for the same reason.
- **The creature's identity.** Creature GUIDs are secret inside dungeons (Fellowship Ledger), so no NPC ID; names may
  be readable.

**Checked in game (2026-11-15, client 1.60.1 build 70938):** `/dp scan` inside The Hall of Thanes (instance 3065,
party) with a hostile elite level-14 mob targeted returned no best map (`C_Map.GetBestMapForUnit` nil), `UnitPosition`
nil for x and y (only the instance ID), and both the target's GUID and its name as secret values. Only hostility,
level and classification were readable. A recorder cannot get a position or an identity, so it stays unbuilt. What the client does expose (combat segments,
nameplate counts, levels and classifications, encounters) feeds the opt-in **run recorder** instead, which records
pulls, bosses and wipes without positions and never produces spawn data (docs/ARCHITECTURE.md, Run recorder;
docs/COMPATIBILITY.md section 10). Other addons' spot data is not used here either: NeedRoll does not publish its
tables, and the data providers (Dungeon Journal and OpenMap boss pins) draw at runtime only, never into this folder.

If a later client changes this, the `position` row of `/dp scan` (run inside a dungeon with a hostile mob targeted,
then `/reload`) shows it: numbers in `mapPosition` or `unitPosition` would make an opt-in recorder possible
(`PLAYER_TARGET_CHANGED` / `PLAYER_REGEN_DISABLED` in an instance; merge points within a few yards; export with licence
`own`). `UnitPosition` alone would still need the floor rectangles described under Coordinates.

## Adding spawn points

Further points go in `data-src/spawns/<anything>.json`, one instance per file, UTF-8 (write characters, not `\u`
escapes):

```json
{ "schema": 1, "instance": "The Deadmines",
  "sources": [ { "id": "a", "what": "read off the map in game, March run", "licence": "own" } ],
  "spawns": [ { "floor": 1, "x": 0.512, "y": 0.334, "name": "Defias Pirate", "kind": "elite", "npcID": 657,
                "level": 18, "approx": true, "source": "a" } ] }
```

- `instance` is the instance's name as the plans write it; `floor` is 1-based (the instance's maps in order); `x`, `y`
  are 0..1 on that floor's map; `kind` is `mob`, `elite`, `rare`, `boss` or `npc`; `npcID`, `level` and `approx` are
  optional.
- Every point names a source of the file, and every source a licence: `own` (you saw it in game; given under the
  project's MIT licence), `MIT`, `BSD-2-Clause`, `BSD-3-Clause`, `CC0-1.0` or `CC-BY-4.0` (credit it in
  docs/DATA-SOURCES.md). The generator refuses anything else, so nothing from GPL, AGPL or unlicensed databases
  (Questie, the server emulators, Wowhead) can slip in.
- The generator merges a creature's points closer than 0.01 of the map, keeps at most 300 per floor, and fails on any
  point out of range.
