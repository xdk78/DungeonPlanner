# Santiago Reyes' dungeon maps

The map pictures in `Media/Maps/Reyes/` are **(c) Santiago Reyes**, all rights reserved, and are used in Dungeon
Planner **with his permission**. They are **not covered by the MIT licence** of this project: that licence covers the
code only. Do not reuse these pictures outside Dungeon Planner without his permission. The same applies to the
walkability grids made from them (see "Walkability grids made from the maps" below).

- Artist: Santiago Reyes (WoWMaps), <https://sreyesmaps.com>, on X as SR433_20 (<https://x.com/SR433_20>).
- Work: his World of Warcraft maps. The ones used are from his "Atlas de Azeroth: Forever", maps of the new dungeons
  of World of Warcraft: Forever.
- Credit in the addon: "Map by Santiago Reyes" on the map itself (with his site in its tooltip) and in the map
  settings; outside the game, in the README and on the addon's page. His donation page is linked only in the README,
  on the addon's CurseForge page and in this file, never in the game: Blizzard's UI Add-On Development Policy does not
  allow add-ons to ask for donations in game.

## Permission

| | |
|---|---|
| Date | 2026-11-16 |
| Channel | Direct message, in reply to the project's request |
| His words | "I have no problem with you using my maps. Go ahead, use them!" |

He also asked people who like his maps to consider a donation. He did not ask for a particular credit format.

## Support the artist

If you like these maps, please consider supporting him: <https://sreyesmaps.com/donaciones> (his donation page:
PayPal, Ko-fi and Patreon).

## What was done to the pictures

Only a change of format, so the game client can draw them (`tools/reyes_maps.py`):

1. Source: the files he publishes on his site (3000 x 2000 JPEG, the current version of each map on 2026-11-16).
2. Scaled to 1024 x 683, the size and crop the Dungeon Journal and Forever Dungeon Routes addons use for the same
   pictures, so a plan's coordinates mean the same place on both.
3. Cut into three strips of 1024 x 256 and stored as BLP2 textures with DXT1 compression (the last strip is padded by
   repeating its last row; the padding is never drawn).

Nothing was recoloured, cropped away or painted over; his titles, watermarks and signature are kept.

## Walkability grids made from the maps

The walkability grids under the `r:` keys of `Data/WalkData.lua` (the route tool's "Snap to corridors") are made from
his maps by `tools/walk_grids.py`, from the same published files at the size the addon draws them. They only record
where each map shows floor (and where it shows a wall or nothing); the file holds no picture. He gave permission to use
his World of Warcraft maps in Dungeon Planner (see Permission). The `r:` grids are made from his maps under that
permission and, like the maps, are not under the MIT licence.

## Files

| Files (`Media/Maps/Reyes/`, strips 1-3) | Map on his site |
|---|---|
| `HallOfThanes` | Salon de los Senores Feudales (Hall of Thanes) |
| `RuinsOfLordaeron` | Las Ruinas de Lordaeron |
| `ExcavationSite` | Sitio de Excavacion: Los Humedales (version 2.0) |
| `DalaranCity`, `DalaranUnderbelly` | La Ciudad de Dalaran: the city, and its sewers (the Underbelly) |
| `DrownedCity`, `DrownedCityAtalByzal` | La Ciudad Ahogada: the main city, and Atal'Byzal |
| `Kroldok` | La Fortaleza Krol'dok |
| `AlcazPrison`, `AlcazPrisonMaxSecurity` | La Prision de Alcaz: the main unit, and the maximum security unit |
| `BlackmawGrove`, `BlackmawFesteringGrotto`, `BlackmawFallenGrove`, `BlackmawBurrow`, `BlackmawElders`, `BlackmawForbiddenMagic` | Bastion Faucenegra: its six levels |
| `ShapersTerrace`, `ShapersTerracePrismaticTalus` | Bancal del Creador (Shaper's Terrace), and the Prismatic Talus |

World of Warcraft and the places these maps show are Blizzard Entertainment's; the maps are fan-made art.
