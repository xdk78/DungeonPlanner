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
- `transports`: boats, zeppelins and airships (`kind`, `route`, the dock's `continent`, `x`, `y`, `toContinent`, and
  the other dock's `toX`, `toY`).

The plan slugs are matched to OpenMap's instance names (the Group Finder's) by the table `OPENMAP_SLUGS` in the tool.

A transport leg's faction is derived when `Data/TravelData.lua` is written: a dock serves the factions of the flight
masters within `DOCK_RADIUS` (1000) yards of it, and a leg is Alliance or Horde only when both its docks serve only
that faction (Grom'gol, Orgrimmar and Undercity: Horde; Menethil, Theramore, Auberdine, Rut'theran, Feathermoon,
Southshore, Stormwind: Alliance). Booty Bay and Ratchet serve both; a dock with no flight master that near (Forever's
goblin ports, Zephras Isle's airships) leaves the leg open to both. Getting there offers a player only the legs of
their faction or open to both.

## `places.json` (researched)

```json
{ "schema": 1, "updated": "YYYY-MM-DD",
  "sources": [ { "id": 1, "name": "...", "url": "...", "licence": "...", "what": "..." } ],
  "places": { "the-deadmines": { "zone": "Westfall", "zoneMap": 1436, "subzone": "Moonbrook",
    "zoneFaction": "alliance", "approach": "cave", "stone": { "zone": "Wetlands", "map": 1437, "x": 53.4, "y": 65.3 },
    "hint": "...", "src": [1, 2, 4] } } }
```

- Every plan with an entrance in `openmap.json` needs a place (the generator checks).
- `zone`: the outside zone in English (shown only when the client has no name for `zoneMap`). `zoneMap`: that zone's
  uiMapID (OpenMap's map tables, source 4): the entrance is placed on this map and the card shows the map's name in
  the client's language. Blackrock Mountain lies between Searing Gorge and Burning Steppes; its entrances use Burning
  Steppes' map. `subzone`: the named area the entrance lies in or is reached through.
- `zoneFaction`: the zone's control as the wiki's zone page states it: `alliance`, `horde`, `contested`, `neutral`.
  Left out where the page has no faction field (Ashenvale, Alterac Mountains, Badlands, Swamp of Sorrows, Stranglethorn
  Vale, both Plaguelands, Un'Goro Crater).
- `approach`: how it is entered where a page says so: `cave`, `building`, `mountain`, `open`, `underwater`, `ship`,
  `tower`.
- `stone`: a summoning or meeting stone with its zone, that zone's `map` (uiMapID) and coordinates (0-100 on that
  map), only where a Forever page states
  them (City of Dalaran, Excavation Site: Wetlands). Classic stones are listed on the wiki without coordinates, and
  the wiki says Classic meeting stones do not work, so none are recorded.
- `hint`: at most 80 characters, written by us from the page's facts, never copied.
- `src`: ids of `sources`: warcraft.wiki.gg (the World of Warcraft: Forever page, instance pages, zone pages; CC BY-SA
  4.0, facts only) and OpenMap's map tables (MIT) for the uiMapIDs.

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
