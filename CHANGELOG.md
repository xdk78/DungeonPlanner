# Changelog

All notable changes to Dungeon Planner. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

The first public version, for WoW: Forever. Highlights, known limitations and the test checklist:
`docs/RELEASE-NOTES-0.1.0.md` in the source repository.

### Added
- **The war table**: a window in the game's own look (framed window, inset panels, window tabs) with the dungeon map
  filling it, the plan's steps (entrance, pulls, bosses, quest givers, objectives) and your party beside it, and the
  sections (Map, Bosses, Pulls, Party, Gear, Runs, Share, Notes) as tabs under the window. Clicking a step shows it on
  the map. The instance and the plan are picked in the header; the instance picker searches by name or by level.
- **Home**: a table of dungeons and raids with level ranges, your plans and bosses killed, and a large preview;
  My plans and Shared (plans sent to you or imported) in the same place.
- **43 recommended plans** for the classic dungeons and raids and Forever's new dungeons: boss order, routes with
  numbered stops along the corridors, pulls, strategies and party positions. They are read-only; **Make an editable
  copy** to change one. Estimated spots carry a small "~". Sources and credits in docs/DATA-SOURCES.md.
- **Map planning** on the game's dungeon maps (the old dungeon map tiles; another addon's map or a parchment grid
  where the game has none): markers of 17 kinds, pulls in colour, routes with stops and direction chevrons, party
  positions per boss or pull, layers you can hide, labels, icon size, zoom and pan, undo and redo (50 steps).
- **Maps for Forever's new dungeons without other addons**: every floor that has no map in the game is drawn from the
  game's own minimap pictures (the ones the minimap shows inside the instance), north up: The Hall of Thanes, Ruins of
  Lordaeron, Excavation Site, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison, all six floors of
  Blackmaw Hold, Shaper's Terrace and Scholomance's old floors. The recommended plans' routes and markers are placed
  on them through a transform per floor, in the same parchment colours as the classic dungeon maps (Settings, "Map
  colours": parchment or the game's minimap colours). With Dungeon Journal or Forever Dungeon Routes installed, their
  drawn maps are used first, as before (Settings, "Prefer drawn maps ..."); `/dp debug` and `/dp scan` say where each
  floor's map comes from.
- **Map drawing** on your own plans: pen, line, arrow, circle, box, text, eraser and move, eight colours, three widths;
  drawings can belong to a boss or a pull and travel with the plan.
- **Enemies layer**: where bosses and some packs stand, from the plans' research.
- **Pulls** with tags (Interrupt, Crowd control, Line of sight, Pull with next, Skip, Careful), planned cooldowns and
  Bloodlust, and planned forces after each pull.
- **Bosses**, **Party** (assignments per boss and phase for a player, role, raid group or everyone; raid groups 1-8)
  and **raid pages**: named pages per boss with keywords for raid icons, roles, groups and classes, shown in a small
  Notes window that opens on the boss's pull. The raid leader can send pages to the group or post them to chat.
- **Gear** recommendations per class, role, slot and boss; with Dungeon Journal installed, its drops per boss.
- **Run mode**: a compact window with the current step, the next pull, the next boss's tips and a mini map; Prev / Next
  and the pull key bindings walk the steps, and a boss kill moves past its step.
- **Run recorder** (opt-in): pulls, boss kills, wipes and deaths of your runs, best and previous splits, a run against
  the plan (extra, skipped and out-of-order pulls), two runs side by side, **Create plan from run**, and progress
  against the plan in run mode.
- **Sharing**: send a plan to your group, guild or a player (accept or decline), see who in your group has it and
  whether their copy is outdated; export and import strings; instance packs; Discord text and a run summary.
- **Data from other addons**, read in your game only and switchable in the settings: Dungeon Journal (maps, boss pins,
  portraits, loot), Forever Dungeon Routes (its routes as a map layer, its maps), OpenMap (maps, boss pins), NeedRoll
  ("Open in NeedRoll"), Questie (the dungeon's quests). DBM or BigWigs as a backup for boss kills.
- **Boss information from Dungeon Journal**: with it installed, a boss marker's details on the map show the boss's
  portrait, name and level, its description and summon item where it has them, and its notable drops (item tooltips,
  Shift-click links the item), then the plan's strategy and note. The Bosses page shows the same under the strategy
  (and the level in its header), and run mode's "Next boss" leads with the level. Each section is credited "Dungeon
  Journal" and hidden when it has no data; the data-from-other-addons setting switches it off.
- **Boss facts built in**: the recommended plans' bosses now show their portrait, level, drops and **abilities** without
  any other addon. Each ability row has the game's spell icon and name, tags (interrupt, dispel, tank, healer, crowd
  control, area damage, ...), a short note where we wrote one, and the game's spell tooltip on hover; the section is
  credited "Sources: Wowhead, warcraft.wiki.gg". Run mode's "Next boss" shows up to three key abilities as icons.
  Dungeon Journal, when installed, only fills what the built-in data lacks and adds its description and summon item.
  Dungeon quest IDs (giver, objective items) are bundled for the instances too. Only IDs and numbers ship; the game
  supplies the names and descriptions. Forever's new dungeons are filled from Wowhead's WoW: Forever journal and guides:
  NPC IDs, portraits (display IDs), abilities with their tags, drops and quests for seven of the nine (Blackmaw Hold and
  Shaper's Terrace have no page there yet); classic bosses gain the drops Forever added. Three recommended plans'
  strategy notes were corrected against those guides.
- Polish interface (automatic with WoW Po Polsku, or chosen in the settings) and English; a colour-blind setting;
  minimap button, Addon Compartment, key bindings (none set for you), options in the game's Settings panel, profiles.
- **Its own logo**: a scroll map with a numbered route to a boss, drawn for the addon. It is the icon in the addon
  list, the Addon Compartment, the minimap button and the window's portrait ring; Settings > Game map icon brings
  back the game's map icon for the minimap button and the window.
- `/dp debug` (what this client provides, self-tests), `/dp scan` (diagnostics for bug reports) and a public API for
  other addons (docs/API.md).

### Changed
- Export strings start with `!DP2!` (format 4: drawings, pull marks, raid pages). Strings from earlier test builds
  (`!DP1!`) still import; older builds import newer strings without the parts they do not know.
- In-game sharing needs both players on this version (protocol 2).

### Fixed
Since the test builds:
- Item names in gear lists, boss drops, run mode and the Discord text no longer stay "Item 12345" while the client has
  not cached the item: it is asked to load it and the open lists update when the names arrive.
- The estimate mark is a plain "~" (the old "≈" drew as "=" in the game's font); it never wraps onto a line alone.
- Settings: the long checkbox label is no longer cut off, and the window scale is a list of steps (the slider's value
  box sat on its track). The `/dp debug` dialog is wide enough that a font's name is not split over two lines.
- Marker details no longer say a name three times: a boss marker's pane has its portrait and name once; any other
  marker's name is its heading, with its kind under it.
- Map and side-panel pictures: loading-screen art, boss portraits that load in place, Polish letters in every font,
  level ranges from the Group Finder (WoW: Forever's Adventure Guide is empty).
- The window: scroll bar thumbs, tabs keeping their size, the close button and size grip above the window's border,
  text typed into a field no longer lost or moved to another item, header tooltips under their control.
- Escape closes the topmost of the planner's windows first (a confirmation before the planner), and hiding the UI
  (Alt+Z) no longer declines a plan offer or half-closes a dropdown. Buttons ignore right-clicks.
- Map: the dungeon's own map tiles before another map of the same name, Shadowfang Keep's floors in the right order,
  the Draw tool letting the map pan in combat, smoother panning, faster steps on large plans.
- The objective field adds only on Enter or its Add button, not when you click elsewhere.
- Sharing and saved data: late accepts still get the plan, damaged saved data is repaired or set aside instead of
  lost, hostile text cannot freeze the game.
- Each instance remembers the plan you last chose there: switching dungeons and back no longer jumps to the newest plan.
- Plan list: no scroll bar when every plan fits.
- Run mode: the title sits inside the title bar, the planner button beside the close button, and the empty row under the
  title is gone. Map tooltips open to the left when there is no room on the right, and wrap.
- Steps list: every step icon, bosses included, has the same gold ring, size and centre; the two text lines are centred
  on the row, clear of the selection's bright lines.
- Step icons, map pins, the Bosses list and the party icons: the gold ring is centred on the picture or number inside
  it (it sat down and to the right of it).
- Maps: one look for every dungeon. Floors drawn from the game's minimap pictures (Forever's new dungeons) show on
  parchment in its colours, with darkened edges, instead of dark 3D art on a grey box or full-colour terrain; Settings,
  "Map colours", switches them back to the game's minimap colours. Dungeon Journal's and Forever Dungeon Routes'
  drawn maps come first again when those addons are installed (the setting is on for everyone after the update).
- Map: route direction chevrons point the way the route goes (they all pointed up). The numbers on route stops are the
  step numbers of the side panel and run mode (they were the stops' own order). Labels stay inside the visible map
  instead of being cut at its edge; a quest item or object no longer covers the boss pin next to it.
- Ragefire Chasm: Oggleflint is one step, not two (a route stop that walks on past a boss no longer becomes that boss
  again). Quest items show their own icon and name; a long name keeps its end ("...Hungerer's Heart").
- `/dp debug`: the font test's text no longer runs under the Close button.
- Instance pictures for Hall of Thanes, Ruins of Lordaeron, Onyxia's Lair, Ruins and Temple of Ahn'Qiraj, Hyjal Summit
  and both Stratholme wings: the game's own loading screens, found under the names the game gives them. Forever's
  dungeons that are not out yet show Dungeon Journal's card picture when it is installed (credited in the preview),
  and their own loading screen once the Group Finder lists them; Forever's wide loading screens no longer show a thin
  empty band at the top and bottom.
- Polish letters: a font that failed to load once is no longer given up on for the whole session; the faces are tried
  again after the first loading screen, and a cleaned copy of the bundled font (DPSans.ttf) is tried too. WoW Po
  Polsku's font is only used while that addon is enabled. Without any Polish font, the interface stays Polish and says
  once (also when you choose Polish) that ą ć ę ń ś ź ż show as boxes. `/dp debug` no longer calls the bundled font
  "missing or damaged"; it reports "WoW Po Polsku is disabled" when that addon is disabled, and it draws a font test
  that it checks again a few seconds later. `/dp scan` saves that test.

### Developer
- Offline tests (`lua tests/run.lua`) load the whole addon against a client mock (wow-ui-harness, vendored in
  `tests/vendor/`), including micro-benchmarks that fail on performance regressions (`tests/test_perf.lua`).
- `lua tests/ui_dump.lua` dumps every view as JSON and lints the layout (truncated, clipped or overlapping text,
  overlapping buttons, things outside the window) in English and Polish; CI fails on new findings.
- `/dp shots` takes an in-game screenshot of every view (LibUIShots-1.0); AGENTS.md, "Seeing the UI".
- Recommended plans, spawn data and boss facts are generated from `data-src/` (`tools/gen_plans.lua`,
  `tools/gen_spawns.lua`, `tools/gen_bosses.lua`, `--check` in CI); route bends come from `tools/route_paths.py` and `tools/import_routes.py`.
- Widget kit split into `UI/Widgets.lua`, `UI/Fields.lua`, `UI/Tabs.lua`, `UI/Containers.lua`, `UI/Popup.lua`,
  `UI/Window.lua` (Escape handling: `W.CloseOnEscape`); plan operations into `Model/Plan.lua`, `Model/PlanLists.lua`,
  `Model/PlanBosses.lua`. `DB.Revision(plan)` for caches; `UI.Batch` for one refresh per change.
- Saved data: `DB.SCHEMA` 4 with migrations; invalid plans go to a quarantine; data from a newer version opens
  read-only.
