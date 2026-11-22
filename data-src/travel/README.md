# Travel facts (`data-src/travel`)

What the Prep section's "Getting there" card knows about reaching each recommended plan's instance. The addon does not
load these files: `lua tools/gen_travel.lua` turns them into `Data/TravelData.lua`, which `Data/Travel.lua` reads.
Only facts ship: positions, IDs, names of places, and a short hint of our own per instance.

## `openmap.json` (generated, do not edit)

Written by `lua tools/gen_travel.lua --openmap <OpenMap folder>` from a local install of
[OpenMap](https://github.com/openmap-world/openmap) (MIT, docs/licenses/OpenMap-LICENSE.txt): its
`Data/Forever/Places.lua` and `Data/Forever/FlightData.lua`, which OpenMap generates from the game's own tables. The
tool reads them as data (an empty environment; they only assign tables) and keeps:

- `entrances[slug]`: where the instance is entered outside. Either world yards on a continent
  (`{ continent, x, y }`, the game's frame: x north, y west; the place a ghost returns to) or, for Forever's new
  dungeons, a spot on the zone's map (`{ map = uiMapID, x, y }`, 0..1). Hyjal Summit and Naxxramas have none.
- `nodes`: the flight masters (`id`, `name`, `continent`, `x`, `y`, `factions`: 1 Alliance, 2 Horde, 3 both); class-only
  flight paths are left out.
- `transports`: boats, zeppelins and airships (`kind`, `route`, the dock's `continent`, `x`, `y`, and `toContinent`).

The plan slugs are matched to OpenMap's instance names (the Group Finder's) by the table `OPENMAP_SLUGS` in the tool.

## `places.json` (researched)

```json
{ "schema": 1, "updated": "2026-11-22",
  "sources": [ { "id": 1, "name": "...", "url": "...", "licence": "...", "what": "..." } ],
  "places": { "the-deadmines": { "zone": "Westfall", "subzone": "Moonbrook", "zoneFaction": "alliance",
    "approach": "cave", "stone": { "zone": "Wetlands", "x": 53.4, "y": 65.3 }, "hint": "...", "src": [1, 2] } } }
```

- `zone`: the outside zone (English; the UI shows the client's own name when the client places the entrance on a
  zone map). `subzone`: the named area the entrance lies in or is reached through.
- `zoneFaction`: the zone's control as the wiki's zone page states it: `alliance`, `horde`, `contested`, `neutral`.
  Left out where the page has no faction field (Ashenvale, Alterac Mountains, Badlands, Swamp of Sorrows, Stranglethorn
  Vale, both Plaguelands, Un'Goro Crater).
- `approach`: how it is entered where a page says so: `cave`, `building`, `mountain`, `open`, `underwater`, `ship`,
  `tower`.
- `stone`: a summoning or meeting stone with coordinates (0-100 on that zone's map), only where a Forever page states
  them (City of Dalaran, Excavation Site: Wetlands). Classic stones are listed on the wiki without coordinates, and
  the wiki says Classic meeting stones do not work, so none are recorded.
- `hint`: at most 80 characters, written by us from the page's facts, never copied.
- `src`: ids of `sources`. Sources: warcraft.wiki.gg only (the World of Warcraft: Forever page, instance pages, zone
  pages; CC BY-SA 4.0, facts only). Wowhead refused automated fetches. AllTheThings, Questie, NeedRoll,
  ForeverDungeonJournal and RXPGuides were not read.

Known doubts (kept out or noted): Razorfen Downs is in the Barrens on the Classic page and the Forever table (Thousand
Needles on the retail page); the Stockade's area is the Canals on its infobox (the Mage Quarter on the stone table); The
Drowned City and Blackmaw Hold have no area on their pages; the raids Forever does not have at launch (Molten Core,
Blackwing Lair, Zul'Gurub, both Ahn'Qiraj raids, Naxxramas) carry Classic facts.

## Regenerating

```sh
lua tools/gen_travel.lua --openmap "<World of Warcraft>/_forever_/Interface/AddOns/OpenMap"   # refresh openmap.json
lua tools/gen_travel.lua            # writes Data/TravelData.lua
lua tools/gen_travel.lua --check    # exits 1 on invalid JSON or an out-of-date file (CI)
lua tools/gen_travel.lua --report   # coverage
```
