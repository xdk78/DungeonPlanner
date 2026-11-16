# AGENTS.md

Guide for contributors and coding agents. Dungeon Planner is a World of Warcraft addon for **WoW: Forever**
(interface 16001, Mainline 12.1.5 API family, Lua 5.1). Read `docs/COMPATIBILITY.md` before touching any game API.

## Layout

- `DungeonPlanner.toc`, `embeds.xml`, `Bindings.xml` - load order, libraries, key bindings.
- `Core/` lifecycle, utilities, API checks, integrations, public API, actions, slash commands.
- `Model/` pure plan logic (schema, validation, operations, routes, progress).
- `Share/` pure sharing logic (checksum, bounded inflate, export strings, transfer state machines, Discord) and
  `Comm.lua` (AceComm glue).
- `Config/` defaults and AceDB with migrations. `Data/` runtime game data access (no bundled IDs). `Tracker/` kills.
- `UI/` style tokens and materials, art names, widget kit (incl. the window), home table, war-table page (side panel, sections), map canvas and
  layers, run mode, prompts, settings.
  `Locales/` enUS (keys) and plPL.
- `Libs/` vendored libraries (pinned, `docs/LIBRARIES.md`, refresh with `tools/fetch_libs.sh`; never edit them).
- `tests/` offline harness (`run.lua`, mock client `wowmock.lua`). `tools/` dev scripts. `data-src/` research data; `Data/Plans/` plans generated from it. `community-plans/` the
  community database. `docs/` compatibility, architecture, formats, API.

## Commands

```sh
lua tests/run.lua                          # all offline tests; must pass
lua tests/run.lua Discord                  # only tests whose name contains "Discord"
lua tools/locale_keys.lua Locales/plPL.lua # every UI string translated
lua tools/validate_plans.lua               # community plans
lua tools/gen_plans.lua [--check|--report] # regenerate Data/Plans from data-src (docs/DATA-SOURCES.md)
lua tools/gen_spawns.lua [--check|--report] # regenerate Data/Spawns (after gen_plans; data-src/spawns/README.md)
lua tools/gen_bosses.lua [--check|--report] # regenerate Data/Bosses from data-src/bosses (data-src/bosses/README.md)
uv run --script tools/route_paths.py --game <client folder> --work <scratch> # route bends (data-src/routes/README.md)
uv run --script tools/import_routes.py --fdr <clone> --game <client folder> --work <scratch> # imported routes (same README)
uv run --script tools/minimap_art.py --game <client folder> --work <scratch> [--check] # maps from minimap pictures
luacheck .                                 # lint, must be clean (CI)
lua tests/ui_dump.lua --out <work dir>      # UI views as JSON + layout lint (CI; "Seeing the UI" below)
lua tools/gen_textures.lua                 # regenerate Media/*.tga
uv run --script tools/render_logo.py       # logo PNGs and Media/LogoIcon.tga from Media/Logo/*.svg
```

## Changes

- Work on a branch; `main` is protected by CI (lint + tests + locale + plans).
- Every change that players can see gets a line under the newest, unreleased version in `CHANGELOG.md` (until a
  release is tagged, `## [0.1.0] - Unreleased`; then a new `## [Unreleased]` above it).
- Keep files under ~800 lines; split by responsibility before a file passes that (UI panels are separate files).
- New logic goes in pure modules with tests; UI files stay thin and call Model/Share functions.
- New UI strings: write English in `L["..."]`, add the Polish line to `Locales/plPL.lua` (the locale check fails
  otherwise). Format strings must keep the same `%s`/`%d` order (a test checks).
- New saved fields or format changes: bump `DB.SCHEMA` with a migration (+ test), or the export header `!DP1!` and
  `docs/SHARING-FORMAT.md`, or `ns.PROTOCOL_VERSION`.

## State and performance

- Phased behaviour is an explicit state machine: a state table and `Step(state, event, now) -> effects`
  (`Share/Transfer.lua`, the map's `view.drag`). Timers are events; a stale tick changes nothing.
- An idle addon costs nothing: no OnUpdate except while dragging or hovering the map; tickers stop when work ends;
  the window builds on first open; the journal is scanned on demand and cached.
- Bound everything that grows: list limits in `Model/Schema.lua`, decode limits in `Share/Codec.lua`, run history.

## Game API rules (Forever)

- Feature-detect every API not marked "Verified" in `docs/COMPATIBILITY.md`; add it to `Core/Compat.lua` so
  `/dp debug` reports it; degrade, never error.
- Secret values: pass anything read from the game through `Util.Plain` before comparing or storing it.
- The combat log is closed: never use `COMBAT_LOG_EVENT_*`.
- Never: hook Blizzard functions, use secure templates, call protected functions, `SetCVar`, `SetBinding`, change the
  game's font objects, read or write other addons' SavedVariables (exception: reading WoW Po Polsku's language choice,
  guarded), add globals beyond those in `docs/API.md`.
- Combat: sharing, prompts and the Settings panel wait for `PLAYER_REGEN_ENABLED` (`ns:RunOutOfCombat`).
- Addon messages go through `Share/Comm.lua` only (AceComm + lockdown outbox).
- Untrusted input (imports, received plans, community files) goes through `Codec.Decode` and `Validate.*`. Never
  `loadstring`.

## Data honesty

- The addon's own code ships no hard-coded game data: instances, bosses, maps and IDs are read from the client at
  runtime, or authored by players. Templates in `Data/Templates.lua` contain generic text only.
- The one exception is the recommended plans in `Data/Plans/` (docs/DATA-SOURCES.md): generated by
  `tools/gen_plans.lua` from `data-src/dungeons/*.json`, never edited by hand. Only research with a licence-compatible
  source goes in (OpenMap is MIT; web guides are paraphrased); nothing from AllTheThings or NeedRoll; estimates say
  "(approx.)". `lua tools/gen_plans.lua --check` must pass.
- The second generated exception is `Data/Bosses/` (boss facts: IDs, levels, spell and item IDs, dungeon quest IDs), generated
  by `tools/gen_bosses.lua` from `data-src/bosses/*.json`: facts only, every value names its source, never text from a
  source, nothing from GPL or unlicensed addons. `lua tools/gen_bosses.lua --check` must pass.
- The recommended plans' enemies also feed `Data/Spawns/` (the map's Enemies layer), generated by `tools/gen_spawns.lua`
  together with `data-src/spawns/*.json`, whose files must name a permissive licence or the contributor's own in-game
  observation (`data-src/spawns/README.md`). `lua tools/gen_spawns.lua --check` must pass.
- The recommended plans' route bends come from `data-src/routes/*.json`, written by `tools/route_paths.py` from the
  game's map tiles and the installed providers' map pictures (read locally, never copied): only coordinates ship.
  The tool needs a local game install (its path is an argument); keep its work folder (pictures, masks, previews)
  outside the repository. Fix a wrong mask with that file's `overrides`, then re-run it and `gen_plans`.
  The routes of 41 plans are imported from Forever Dungeon Routes (MIT) by `tools/import_routes.py` (the `import`
  block of those files); its pictures stay out, and its classic routes' provenance is in docs/DATA-SOURCES.md.
- The second exception is `Data/GameFiles.lua`: file names of the game's own textures (loading screens, the old
  dungeon map tiles), because WoW: Forever's Adventure Guide is empty (docs/COMPATIBILITY.md section 9). Only names
  of files that are in the client, each checked with `GetFileIDFromPath` before use; never the pictures themselves.
- The third exception is `Data/MinimapArtData.lua`: file IDs of the game's minimap pictures and numbers (where each
  lies, a transform per floor), generated by `tools/minimap_art.py` from `data-src/minimaps.json` on a local install
  (docs/DATA-SOURCES.md); never the pictures. Its `--check` must pass after a change to that file or the plans.
- Store IDs in plans; resolve names at display time (`Data/Names.lua`).

## UI

The window is a war table (`docs/UI.md`): its own layout in the game's own window materials (the framed window with the
portrait ring, inset panels, the red panel button, window tabs, minimal scroll bars, list highlights, the menu panel,
the dialog border; Friz Quadrata in the game's gold), each with a drawn fallback, in the game's dark brown, stone and
gold. Do not imitate other addons' layouts. Design rules: one spacing scale and one size set, one highlight per list
(shared by pointer and keyboard), inputs show their border, the primary action first at the start of the line near the
content. Build from the widget kit (`UI/Widgets.lua`, `UI/Fields.lua`, `UI/Tabs.lua`, `UI/Containers.lua`, `UI/Popup.lua`,
`UI/Window.lua`), so new
panels get the materials; colours, sizes and materials from `UI/Style.lua`; every Blizzard texture, atlas, template and
nine-slice layout through `UI/Art.lua` (with a fallback, reported by `/dp debug`). Templates only through
`Art.CreateFrame` (pcall, parts checked with `W.HasParts`), never secure ones. Do not copy art files into the repo.

## Seeing the UI

Two tools show the window without clicking through it. Both come from wow-ui-harness, a separate repository: its Lua
part is vendored in `tests/vendor/wow-ui-harness/` (the mock the tests run on, plus layout, dump and lint) and its
screenshot library in `Libs/LibUIShots-1.0/`; `tools/sync_harness.sh <harness checkout> [ref]` refreshes both and
records the commit in `tests/vendor/wow-ui-harness/VERSION`. Our own parts: `tests/wowmock.lua` (this addon's stubs on
top of the harness mock), `tests/ui_views.lua` (the views), `tests/ui_dump.lua`, `UI/Shots.lua` (the in-game steps).

**In game, real screenshots: `/dp shots`.** Out of combat, type `/dp shots` and wait about half a minute (no
`/reload` needed). It walks home (Dungeons, Raids, My plans), the instance picker, every section of Hall of Thanes
(on a provider's map), run mode, the maps of the Deadmines and Molten Core, Molten Core's raid pages, the Notes window, the `/dp debug` dialog and last the game's
Settings panel (close that one with Escape afterwards), taking a screenshot of each with a plain backdrop behind the
window. Escape or entering combat stops it; the window goes back to how it was. The files are in the game's
`Screenshots` folder (`<game>\Screenshots`, beside `Interface`), named by time; chat and `DungeonPlannerDB.shots`
(written to disk on the next `/reload` or logout) list the steps in the same order with their times, so the n-th new
file is the n-th step. For the Polish UI: choose Polish in the language menu, `/reload`, `/dp shots` again (the language
cannot switch in place; the manifest records it). `/dp shots stop` stops a walk.

**Offline, approximate pictures: dump, lint, render.**

```sh
lua tests/ui_dump.lua --out <work>/dump                            # English: one JSON per view + lint (CI runs this)
lua tests/ui_dump.lua --out <work>/dump --locale plPL --prefix plPL/   # Polish
lua tests/ui_dump.lua --out <work>/dump --update-baseline          # accept the current findings (review them first)
```

CI runs both and fails on lint findings not in `tests/ui_lint_baseline.txt` (truncated, clipped or overlapping text,
overlapping buttons, things outside the window). Without the game's fonts, text is measured with the bundled Alegreya
Sans widened to Friz Quadrata's average (`tests/ui_views.lua`); the baseline is for that measurement.

For pictures, with a harness checkout and a local game install (read only; keep `<work>` outside the repository or
in the ignored `.ui-work/`, it holds game files):

```sh
H=<harness checkout>; G="<World of Warcraft>/_forever_"; W=<work>
uv run --script $H/python/wowui.py fonts --game "$G" --out $W/fonts
uv run --script $H/python/wowui.py atlases --game "$G" --out $W/atlases.txt
F=(--font-root "Fonts\=$W/fonts" --font-root "Interface\AddOns\=$G/Interface/AddOns" --atlases $W/atlases.txt)
lua tests/ui_dump.lua --out $W/dump "${F[@]}" --all-files
uv run --script $H/python/wowui.py files --game "$G" --dump $W/dump --out $W/files.txt
lua tests/ui_dump.lua --out $W/dump "${F[@]}" --files $W/files.txt
uv run --script $H/python/wowui.py render --game "$G" --dump $W/dump --out $W/png --addon DungeonPlanner=. --lint
```

`render` writes `<view>.png` (and `<view>.lint.png` with the findings outlined) for: `home`, `home-raids`, `home-plans`,
`home-shared`, `picker`, `plan-dropdown`, `gear-dropdown`, `section-<id>` for every section of Hall of Thanes,
`section-share-advanced`, `party-raid`, `boss-detail` (a boss marker's details), `map-classic` (the Deadmines), `map-minimap` (Hall of Thanes on the game's minimap pictures, in the parchment colours), `map-ragefire` (Ragefire Chasm: every kind of step, labels at the map's edge), `map-outdoor` (Ruins of Lordaeron, minimap terrain), `map-building` (Blackmaw Hold floor 2, minimap building pictures), `map-raid` (Molten Core), `map-draw` (an own copy
with drawings and the drawing tools), `map-min` (880 x 560), `map-large`, `notes-min`, `notes-own`, `runmode-first`,
`runmode-middle`, `runmode-last`, `runmode-drift` (recording, off plan), `runs-plan` and `runs-compare` (two recorded
runs), `party-pages` and `party-pages-min` (raid pages), `notes-window`, `share-tracking` (who has the plan), `debug`,
`confirm`; `--only a,b` draws some of them.
Textures, atlases and fonts are the game's; the Settings panel and Blizzard templates are not drawn (use `/dp shots`).
A grey placeholder is a game file this install has not downloaded; magenta, a file the client does not have.

## What is verified where

| Verified offline (tests) | Needs in-game testing |
|---|---|
| model, validation, migrations, export strings, transfers, Discord, locales, whole-addon load + every page and section built against the mock, map tools and layers | rendering (Blizzard templates, backdrops, atlases, icons, journal pictures and portraits, map tiles, fonts, Polish glyphs), real menus, drag and drop, addon messages between clients and during lockdowns, Settings panel, minimap button, DBM/OpenMap/Dungeon Journal hooks |

When you change UI code, say in the PR what you tested in game, or that you could not.

## This repository is public

Do not commit secrets, tokens, webhook URLs, personal paths, e-mail addresses, logs or SavedVariables. Use
generic example paths in docs (`World of Warcraft\_forever_\Interface\AddOns\`), never a home directory or a
machine's drive letters.
