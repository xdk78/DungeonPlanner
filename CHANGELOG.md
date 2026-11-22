# Changelog

All notable changes to Dungeon Planner. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **The interface in German, Spanish, French and Russian**, besides English and Polish. "Automatic" now follows your
  game's language when Dungeon Planner has it (Spanish serves both Spain and Latin America; other languages stay
  English), and the language menu and Settings list all six. German, Spanish, French and Russian are a
  machine-assisted first pass using the official WoW terms; native speakers are invited to correct them
  (`Locales/README.md`, a "Translation" issue, or a pull request).
- Plural rules for German, Spanish, French (0 counts as singular) and Russian (one, few, many).
- A Russian UI uses the game's Cyrillic face, or the bundled Alegreya Sans when the client has none.
- **Group sync for run mode.** The group's leader (in a raid also an assistant) clicks "Lead this run" in run mode;
  members who have the same plan see "Following <leader>", and their run mode shows the leader's step, next pull and
  boss as the leader moves on. Prev or Next steps on your own ("Unfollow" does the same); "Rejoin" snaps back. A member
  without the plan, or with another version of it, sees "Leader is on a plan you don't have: ask for it": one click
  asks, and the leader's Dungeon Planner offers the plan the usual way. The leader sees who follows and who is out of
  sync in run mode and in the Share section's "Has this plan" line. Small messages, sent only on a change; in a boss
  fight they wait until addons may talk again, and a boss kill seen by your own tracker is not undone by the leader's
  older step. Older Dungeon Planners ignore them.
- **Report a problem**: `/dp report`, the `!` button in the window's title bar or Settings (Troubleshooting) opens a
  text to paste into a GitHub issue: versions, language, the plan, other addons, the `/dp debug` summary, recent
  Dungeon Planner errors and blocked actions. Add what happened in your own words; "Short for Discord" fits it in one
  message. Character, realm, guild, group and plan names are replaced with `<name>`, and chat is never included.
- **What's new**: a card with the highlights, shown once after an update at a quiet moment (out of combat and
  instances). A first install shows a short welcome instead. `/dp new` shows it again.
- **`/dp perf`**: an opt-in probe that times the addon's events and redraws and reports its memory. Nothing runs until
  `/dp perf start`; `/dp perf stop` turns it off.

### Changed
- Saved data moves to schema 5 (it remembers which plan each received copy came from, for group sync). An older
  Dungeon Planner opens it read-only instead of losing that on its next save.
- The bug report form on GitHub is now an issue form.

### Fixed
- **Share, Advanced, recorded run**: before the first run of an instance it no longer asks you to turn on "Record my
  runs" when recording is already on.

## [0.1.0] - 2026-11-16

The first public version, for WoW: Forever. Highlights, known limitations and the test checklist:
`docs/RELEASE-NOTES-0.1.0.md` in the source repository.

### Added
- **Santiago Reyes' maps of Forever's new dungeons come with the addon**, with his permission: hand-drawn parchment
  maps of every floor he has drawn (The Hall of Thanes, Ruins of Lordaeron, Excavation Site, City of Dalaran and its
  Underbelly, The Drowned City and Atal'Byzal, Krol'dok Stronghold, both units of Alcaz Prison, all six levels of
  Blackmaw Hold, Shaper's Terrace and the Prismatic Talus), shown as he drew them, signature included. They are the
  first map for those floors, no other addon needed; the recommended routes and markers sit on them exactly as on
  Dungeon Journal's map, and Dungeon Journal's boss pins and Forever Dungeon Routes' route layer show on them when
  installed. Each map says "Map by Santiago Reyes" in its corner; hover it for his site and his donation page. The maps
  are his, not under the MIT licence (docs/licenses/SantiagoReyes-maps.md). "Prefer drawn maps" now chooses between
  drawn maps and the game's minimap pictures, and "Map colours" applies only to the minimap pictures.
- **Settings, "Data from other addons"** lists the supported addons you do not have, with what each would add.
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
  colours": parchment or the game's minimap colours). Drawn maps (Santiago Reyes' bundled maps, above, else another
  addon's) come first unless you switch "Prefer drawn maps" off; `/dp debug` and `/dp scan` say where each floor's map
  comes from.
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
- Map: until you open or fold it yourself, the legend starts folded wherever it would lie over the map, so Molten
  Core's painted title (and Hall of Thanes' and the Deadmines' corners) show; it opens by itself only beside a narrow
  map. Party positions belong to a boss or pull and show while it is in focus: at "Focus: everything" the legend's
  Party positions row now says "Focus a boss to show them", and a click there focuses the first boss with positions.
- Steps: a move step shows its map stop (a small disc ringed in the route's colour, with the step number the stop
  shows) instead of a badge like a pull's, so "2" no longer looks the same for a move and for Pull 2; a floor named
  as the instance ("The Deadmines") no longer follows every step's caption.
- Runs: with "Record my runs" on and no run yet, the Run column says "Recording is on. Your next run in this
  instance will appear here." instead of asking to turn recording on.
- Bosses: an ability's note starts under its name (a hanging indent), not under its icon.
- Instance picker: its search shows "Search dungeons and raids..." while empty, also while it has the focus.
- `/dp debug`: the font test is part of the dialog, under the Polish letters test, instead of a second panel that
  stacked under it over the window.
- Notes window: the page label sits between the page arrows ("1 of 3", "No pages" when there is none, where two dark
  squares stood alone), and the arrows have the game's size (32 px).
- Run mode: no gap between a one-line step and the mini map; the map takes that room.
- Pulls: a name on two lines has room between its lines ("Dirgehammer" touched the line above), the list sits in an
  inset, and a recommended plan's pull (marks, note, markers, where it comes in the run) is a card as tall as its text.
- The Party section no longer leaves its text on the left, a box on the right and an empty half below. A dungeon's party
  is a card of five seats with their role icons, centred at the top, with the assignments under it across the section;
  a raid's eight groups fill their column beside the assignments or pages. Empty lists say so in the middle of their
  box.
- The map is centred in its frame again (Molten Core sat 13 px from the left and 83 px from the right). With the
  legend open over the plan it shrinks a little about its centre before it moves; the legend's title folds it to one
  line (the choice is saved), and it starts folded where it would cover the plan or a map's painted title. The bands
  beside a 3:2 map are the parchment of the table, not a black gap.
- Recommended plans over more than one floor (The Deadmines, Blackrock Depths, Naxxramas and 13 more) listed their
  steps in turns between the floors, so the Deadmines showed "Pull 2" and Gilnid before Rhahk'Zor. The route's stops
  are now numbered once over every floor, and the steps follow the route from the entrance to the last boss.
- Item names in gear lists, boss drops, run mode and the Discord text no longer stay "Item 12345" while the client has
  not cached the item: it is asked to load it and the open lists update when the names arrive.
- Item names now really fill in while the Bosses and Gear pages are open (they listened for the wrong answer from the
  client, so only a later visit showed them); an item that does not arrive is asked again a few times, and hovering it
  asks once more.
- Boss portraits in raids and classic dungeons no longer show skulls for the first seconds: a plan's portraits start
  loading as soon as the plan is chosen (also when an instance is selected on the home table, and when you enter a
  dungeon or raid), the map pins and the steps take them over in place, and a boss seen once shows its face at once
  everywhere else.
- Map: the map fills its section and is centred, the legend floats over its edge instead of squeezing it (it never
  covers the plan's markers); "Map by Santiago Reyes" is a small chip in the map's own corner instead of a dark band
  above it; Labels and Icon size sit inside the frame, clear of its border.
- Home: the "Forever" chip sits beside the levels instead of under the name (it looked like an underline under
  "Wetlands"). Level ranges far above your level are orange, not red, and the Levels heading explains the colours.
- Pulls: a wider list with names on two lines; a recommended plan's pull says where it comes in the run. Party: the
  party box takes half the section, with larger rows and a hint on filling it. Notes: boss names in Progress are no
  longer cut ("Durgen..."), and the notes say spots are marked "~", in Polish too.
- The Notes window opens at a readable size (380 x 400, still resizable and saved) with the game's page arrows.
- Run mode: the mini map keeps a margin around the step (painted names and the route are not cut at its top), the
  next pull's name gets two lines, and Prev on the first step has the game's normal disabled look.
- Estimated steps no longer show a box and "94p" before the "~" mark (in the steps list, run mode and step captions).
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
