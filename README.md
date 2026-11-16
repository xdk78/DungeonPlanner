# Dungeon Planner

Plan dungeon and raid runs in **World of Warcraft: Forever**: mark bosses, packs and points of interest on the game's
own maps, group them into pulls, draw routes, write boss strategies by phase, assign players, list gear, track boss
kills and objectives, and share plans in game, as text, or on Discord.

> Status: **beta** (0.1.0, the first version), not yet tested broadly in game. Everything below is implemented and
> covered by offline tests; expect rough edges in the client and please report them; see [What is verified](#what-is-verified) and the
> [release notes](docs/RELEASE-NOTES-0.1.0.md) (highlights, known limitations on Forever, the test checklist).

Screenshots: in-game screenshots will be in [docs/screenshots/](docs/screenshots/) after the first in-game test.

## Features

- **A war table**: the map fills the window; the plan's steps (entrance, packs, bosses, objectives) and the party sit
  beside it, and clicking a step shows it on the map. Pick the instance and the plan from the header.
- **Run mode**: a small window to keep open while playing: the current step, the next pull, tips for the next boss and
  a mini map, with Prev / Next (also on the pull key bindings) and automatic progress when a boss dies. With the run
  recorder on, it shows your progress against the plan and warns when you take more pulls than planned before a boss
  or kill bosses out of order.
- **Run recorder** (opt-in): pulls, boss kills and wipes of your runs; a run against the plan (extra and skipped pulls,
  boss order), two runs side by side, splits against your best and previous run, a run summary for Discord.
- **Map planning** on the game's own dungeon maps (the old dungeon map tiles the client still has; multi-floor; for
  Forever's new dungeons Dungeon Journal's or Forever Dungeon Routes' drawn map when installed, else the game's own
  minimap pictures composed per floor in the same parchment colours). Markers of 17 kinds (bosses, rares, packs, patrols, loot,
  chests, quest items and givers, NPCs, objects, entrances, exits, shortcuts, stairs, hazards, party positions, notes);
  raid marks; labels and notes per marker; drag to move; zoom and pan; layers you can hide; an Enemies layer showing
  where the plans' research placed creatures. Undo and redo (50 steps) for every change.
- **Map drawing** on your own plans: pen, line, arrow, circle, box, text, eraser, eight colours and three widths;
  drawings can belong to a boss or a pull.
- **Pulls**: ordered, coloured groups of markers with notes, tags (Interrupt, Crowd control, Line of sight, Pull with
  next, Skip, Careful), planned cooldowns and Bloodlust, and the forces after each pull; a Pull tool to click packs into
  pulls.
- **Routes**: draw paths, build a route through your pulls, or let "Suggest order" find a short path.
- **Encounters**: bosses from the game's Adventure Guide (or your own), strategy text and phases with triggers.
- **Assignments**: per boss and phase, for a player, a role, a raid group or everyone; raid groups 1-8; post them to
  group chat.
- **Raid pages**: free-text assignment pages per boss with keywords (`{star}`, `{tank}`, `{group 2}`, `{mage}`), names
  in class colour; a small Notes window that opens on the boss's pull; the raid leader sends pages to the group.
- **Gear**: recommendations per class, role, slot and boss (item IDs or dragged items, names from the game).
- **Progress**: boss kills per run and lifetime (ENCOUNTER_END, BOSS_KILL, DBM/BigWigs as backup), an objective
  checklist per plan.
- **Many plans per instance** (strategies, difficulties), profiles, a colour-blind setting.
- **Sharing**: send to your group, guild or a player (accept/decline prompt, size and checksum checks); export and
  import strings; instance packs; **Discord** text split into 2000-character messages; a community plan repository;
  who in your group has the plan you sent, and whether their copy is outdated.
- **Polish** interface (automatic with WoW Po Polsku), minimap button, key bindings, Addon Compartment, options in the
  game's Settings panel, a public API for other addons and WeakAuras.
- **Data from other addons** you have installed, read in your game only (nothing is copied) and switchable under
  Settings > Data from other addons; each source is named where its data shows:
  - **Dungeon Journal**: maps of Forever's new dungeons, boss pins, boss portraits and loot per boss (Gear), and a
    button to open it;
  - **Forever Dungeon Routes**: its routes as an extra map layer, and its maps where no other map exists;
  - **OpenMap**: drawn dungeon maps and boss pins (and your plans on its dungeon card);
  - **NeedRoll**: "Open in NeedRoll" in Gear; **Questie**: the dungeon's quests in Runs;
  - **DBM** or **BigWigs**: boss kills as a backup to the game's own events.

The addon's code ships **no game data**: instances, bosses and maps come from your client. It does include
**recommended plans** for 43 Classic and Forever dungeons and raids, researched by the community (boss order, routes,
pulls, strategies and party positions; positions are approximate, and each plan states its confidence). Sources and
credits: [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md).

## Install

- From CurseForge (when published), or
- download a release zip and extract the `DungeonPlanner` folder to `World of Warcraft\_forever_\Interface\AddOns\`.

## Use

| | |
|---|---|
| `/dp` or `/dplan` | open or close |
| `/dp map`, `/dp next`, `/dp prev` | the plan's map; next / previous pull (the next / previous step in run mode) |
| `/dp run` | open or close run mode |
| `/dp notes` | open or close the Notes window (raid pages) |
| `/dp share` | offer the selected plan to your group |
| `/dp import` | the Share page of the selected plan |
| `/dp settings`, `/dp minimap`, `/dp reset` | options; show/hide the minimap button; reset the window |
| `/dp debug` | client and API report, self-tests, Polish letter test |
| `/dp scan`, `/dp scan clear` | save diagnostics (journal, Group Finder, maps, game files) for bug reports, written on `/reload`; remove them |
| `/dp mapid` | print the current map ID |
| `/dp shots`, `/dp shots stop` | take a screenshot of every view of the window (Escape stops) |
| Key bindings | Options > Keybindings > AddOns > Dungeon Planner (no keys are set for you) |

1. Pick a dungeon or raid in the home table (or **Current location**) and **Open plan**. A recommended plan opens if
   one ships for it; **Make an editable copy** (side panel) to change it.
2. Or **Create a plan**, choose a template, name it.
3. Map: place markers (packs, patrols, loot, quests, doors, hazards, party positions), group packs into pulls, draw the
   route with numbered stops (they become the plan's steps). Hide layers and resize icons in the map's corner and
   legend.
4. Fill in Bosses, Pulls, Party, Gear and Notes from the bottom bar.
5. In the dungeon: **Run mode** (bottom bar, `/dp run` or its key binding) and follow the steps.
6. Share: send it, export it, or create Discord text.

Escape closes the planner's topmost window first (a confirmation before the planner); run mode and the Notes window
stay open until you close them.

## Settings

Options are in the game's Settings panel (`/dp settings`) and the settings button in the window's header:

- **Appearance**: language (Automatic, English, Polski), font, window scale, minimap button, map coordinates,
  colour-blind friendly colours, confirm before deleting plans, reset window position.
- **Progress tracking**: track boss kills and runs, a chat line when a planned boss dies (only you see it), record my
  runs, clear all recorded runs.
- **Data from other addons**: each provider on or off.
- **Sharing**: whose plan offers to accept, whether to tell your group you use Dungeon Planner.
- **Raid pages**: show the boss's page when its fight starts, hide the Notes window in combat, whose pages to accept.
- **Troubleshooting**: debug messages, the self-test.
- **Profiles** (per character or shared).

## What is verified

Verified offline (no game client): plan model, validation of hostile input, migrations, export strings (LibSerialize +
LibDeflate, bounded inflate, checksums), transfer state machines, Discord rendering, Polish locale coverage, and a
smoke test that loads the whole addon with its libraries against a mock client and builds every panel. `luacheck`
and `luac -p` are clean.

Needs the first in-game test: real map tiles, fonts and Polish letters, dropdown menus, drag and drop, addon messages
between two players (and during a boss lockdown), Settings panel, minimap button, the other addons' data. The
ordered checklist is in the [release notes](docs/RELEASE-NOTES-0.1.0.md#test-checklist). `/dp debug` reports what the
client provides. Details: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

Known limitations on WoW: Forever: the client gives no positions inside instances (no live mob or player positions on
the map), and the Adventure Guide is disabled (no journal bosses, portraits, loot or dungeon maps in the client; the
optional addons above fill some of that in). Details in the release notes.

## Development

Requirements: Lua 5.1 (`lua`, `luac`); optional `luacheck` (CI runs it).

```sh
lua tests/run.lua                          # offline tests (whole addon against a mock client)
lua tools/locale_keys.lua Locales/plPL.lua # translation coverage
lua tools/validate_plans.lua               # community plans
lua tools/gen_plans.lua --check            # recommended plans are up to date with data-src/
lua tools/gen_spawns.lua --check           # enemy spawn points are up to date with the plans and data-src/spawns
lua tools/gen_bosses.lua --check           # bundled boss facts are valid, cover every plan boss and are up to date
lua tests/ui_dump.lua --out <work dir>     # UI views as JSON + layout lint (CI)
luacheck .                                 # lint (CI)
```

Run the repository in game with a directory link (Developer Mode or an elevated prompt; adjust both paths):

```powershell
# PowerShell
New-Item -ItemType Junction -Path "<World of Warcraft folder>\_forever_\Interface\AddOns\DungeonPlanner" -Target "C:\path\to\DungeonPlanner"
```

```bat
:: cmd
mklink /J "<World of Warcraft folder>\_forever_\Interface\AddOns\DungeonPlanner" "C:\path\to\DungeonPlanner"
```

The repository is the addon folder (libraries are vendored in `Libs/`); `/reload` after changes. Contributor guide:
[CONTRIBUTING.md](CONTRIBUTING.md) ([code of conduct](CODE_OF_CONDUCT.md), [security policy](SECURITY.md)); agent guide: [AGENTS.md](AGENTS.md); internals: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/SHARING-FORMAT.md](docs/SHARING-FORMAT.md), [docs/API.md](docs/API.md).

## Licence

MIT ([LICENSE](LICENSE)). Embedded libraries keep their licences ([docs/LIBRARIES.md](docs/LIBRARIES.md),
[Libs/THIRD-PARTY-NOTICES.md](Libs/THIRD-PARTY-NOTICES.md): Ace3 and LibDBIcon BSD-style, LibSerialize MIT, LibDeflate
zlib, LibSharedMedia LGPL-2.1, LibStub/ChatThrottleLib public domain, LibDataBroker without a stated licence). The bundled font Alegreya Sans and DP Sans, a cut-down copy of it, are under the SIL Open Font License
(`Media/Fonts/OFL.txt`, changes in `Media/Fonts/FONTLOG.txt`). The logo (`Media/Logo/`, drawn for the project) is
under the project's MIT licence ([docs/LIBRARIES.md](docs/LIBRARIES.md#logo)). Community plans
are CC0-1.0 or CC-BY-4.0. The recommended plans' imported routes come from Forever Dungeon Routes under its MIT licence; its notice and those of OpenMap and ForeverPlusPlus (MIT,
data used by the recommended plans and the map tile names) are in [docs/licenses/](docs/licenses/). World of Warcraft
art is never shipped; maps are drawn by your client.

## Credits

Boss positions, level ranges and instance data come from OpenMap (MIT). The routes of the classic dungeons, the raids
and Forever's new dungeons (paths, side paths and stops) come from
[Forever Dungeon Routes](https://github.com/Checkov23/ForeverDungeonRoutes) by Checkov23 (MIT), which states that its
classic routes were traced from the aetherflask.com walkthrough maps; its pictures by Santiago Reyes are not used. Dungeon order and strategies are paraphrased from the
Warcraft Tavern and Method Forever dungeon guides; NPC and item IDs were checked on Wowhead
Classic. The bundled boss facts (creature displays, levels, ability and drop IDs, dungeon quest IDs) are IDs and numbers
taken from Wowhead Classic and the Warcraft Wiki (CC BY-SA); every ability note is written by us. The map's enemy positions are the same research (bosses from OpenMap, estimated trash packs); no openly
licensed database of dungeon mob spawns exists, see [data-src/spawns/README.md](data-src/spawns/README.md). Dungeon map
tile names and Forever client facts come from ForeverPlusPlus (MIT). The Polish UI can use the
bundled Alegreya Sans font (SIL Open Font License). Full list, and what is deliberately left out for licence reasons:
[docs/DATA-SOURCES.md](docs/DATA-SOURCES.md), [docs/LIBRARIES.md](docs/LIBRARIES.md).
