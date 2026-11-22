# Architecture

## Layers

```
Bindings.xml, /dp, minimap, compartment  ->  Core/Actions, Core/Slash
                       UI/  (window, panels, map canvas, widgets, style, settings)
                         |  reads/writes plans only through Model/Plan and Config/DB
Model/  (Schema, Validate, Plan, PlanLists, PlanBosses, Drawing, Pages, History, Bundled, Route, Progress, RunLog, RunCompare)
        pure Lua 5.1, no game API
Share/  (Checksum, Inflate, Codec, Transfer, Acks, Sync, Discord)  pure, plus Roster and Comm (game glue)
Config/ (Defaults, DB: AceDB, migrations, quarantine)       LoadGlobal is pure
Data/   (Instances, Journal, Loot, Names, Templates)         runtime game data only, no bundled IDs
        (Providers + Providers/*)                          optional adapters reading other installed addons
Tracker/ (ENCOUNTER_END / BOSS_KILL / DBM / BigWigs; Recorder: the opt-in run recorder)
Core/   (Init, Util, Compat, Integrations, API, Boot)
Libs/   (Ace3, LibSerialize, LibDeflate, LDB, LibDBIcon, LSM)  docs/LIBRARIES.md
```

Rules:
- **Pure core.** Model and Share (except Comm) never call the game; `tests/` run them in plain Lua 5.1.
- **One writer.** Only `Model/Plan.lua` functions (with `Model/PlanLists.lua`, gear and objectives,
  `Model/PlanBosses.lua`, bosses, assignments and groups, `Model/Drawing.lua`, map drawings, and `Model/Pages.lua`, raid
  pages) change a plan; every change ends in `DB.Changed(plan, what)`, which raises the plan's revision
  (`DB.Revision`, for caches), refreshes the UI and fires the public `DUNGEONPLANNER_PLAN_CHANGED` event.
- **Validate at every border.** `Validate.Plan` runs on plans created, loaded from SavedVariables, imported and
  received. Invalid stored plans go to a quarantine list, never deleted.
- **IDs are truth, names are display.** Plans store the client's IDs; `Data/Names.lua` resolves names at display time.
- **Explicit state machines** for phased behaviour: transfers (`Share/Transfer.lua`: state + `Step*(state, event, now)`
  returning effects), group sync for run mode (`Share/Sync.lua`: `Sync.Step(state, event, now)`) and map dragging
  (`MapCanvas` `view.drag`: idle / pan / marker / point / draw). Timers are events.
- **Idle costs nothing.** No OnUpdate unless dragging or hovering the map (throttled to 20 Hz); the comm ticker runs
  only while a transfer is open; the window is built on first open, not at login; the journal is scanned on demand.

## Startup (AceAddon)

1. Files load in TOC order; modules register on the private namespace `ns` (`ns:NewModule`).
2. `OnInitialize` (our SavedVariables loaded): `DB.Init` (AceDB, migrations, validation), language, binding labels.
3. `OnEnable` (`PLAYER_LOGIN`, all addons loaded): language again (WoW Po Polsku is known now), fonts, comm, tracker,
   prompts, integrations (launcher, minimap button, OpenMap, Dungeon Journal), settings panel, slash commands.

## Saved data (AceDB, one SavedVariable `DungeonPlannerDB`)

- `global.plans[id]` - plans, shared by all characters; `global.schema` (6: plan format 5, prep notes; 5: the link store
  below; 4: plan format 4, raid pages; 3 added map drawings and pull marks; migrations 3, 4 and 6 convert nothing and 5
  only starts the link store,
  each marking the data, so an older version opens it read-only instead of dropping the new fields on its next save);
  `global.quarantine`.
- `diagnostics` (top level, outside AceDB's sections) - written only by `/dp scan`: every journal instance with its IDs,
  pictures, map and floors, its bosses, how each recommended plan resolved, and a loot sample; `/dp scan clear` removes
  it. For reading the client's real data offline after a `/reload`. `diagnostics.fontTest` holds the font test
  (`UI/Fonts.lua`): each Polish face probed at its first use this session, at the scan and 2 seconds later, with controls.
  (`fontsAtLogin`, one probe per face at the last full login, was dropped: a single early probe proved nothing.)
- `profiles[name]` - `settings` (theme, font, language, sharing policy, tracker), `ui` (window, selected plan, tab),
  `minimap` (LibDBIcon position and visibility). Profiles via AceDBOptions.
- `char[key].progress` - boss kills per encounter and difficulty, the current run, run history, objective checkmarks.
- `char[key].recorder` - the run recorder's runs (`Model/RunLog.lua`): the run being recorded and, per instance ID,
  the last 20 finished runs. Additive (older versions ignore it), so `DB.SCHEMA` is unchanged; `RunLog.Normalize`
  repairs it on load.
- `char[key].notes` - raid pages received from the group's leader (`received`, the last 10; `Pages.NormalizeReceived`
  repairs it on load). Additive, like the recorder.
- `char[key].shareAcks` - who has which version of the plans this character sent in game (`Share/Acks.lua`,
  `Acks.Normalize` on load). Additive.
- `global.entrances` - instance entrances learned from play (`Model/TravelLive.lua`): `[instance key] = { map, x, y,
  at }` (a spot on the instance's zone map; `at` when it was learned), at most 100, `NormalizeLearned` on load;
  absent while the data is read-only. Additive like `shareAcks`: an older version ignores the field and keeps it.
- `global.shareLinks[local plan id]` - which plan a copy received in game came from: `{ plan = the sender's plan id,
  at }` (`Acks.Link`; `Acks.NormalizeLinks` on load), so group sync matches a leader's plan to the copy (by its steps
  revision, `Sync.Signature`). Pasted strings make none. Schema 5 (migration 5 starts it); a link goes with its plan.

Migrations: `DB.migrations[n]` upgrades `global` from schema n-1 to n. Data from a newer schema puts the addon in
read-only mode instead of being rewritten.

## Visual system (UI/Style.lua, UI/Art.lua, the widget kit)

A war table (docs/UI.md has the direction, layouts, materials and rationale): an own layout in the game's own window
materials. The game's framed window (portrait ring, title bar, rock background, close button), inset panels with the
game's inset bevel, section headers on the quest log's header band, the game's red panel buttons for primary actions
and dark plates with a gold edge for the rest, the game's window tabs under the window for sections, its minimal scroll
bars, list hover and selection and menu panel, its dialog border; Friz Quadrata in the game's gold over warm
off-white body text. Every one of these has a drawn fallback, used where the client lacks the part. One spacing scale
(2/4/8/12/16/24/32/48) and one size set (controls 24, rows 28/34/40); one highlight per list, shared by pointer and
keyboard; inputs show their border; the primary action first.

- The widget kit is the one place for these looks, so a new panel built from it inherits them: `UI/Widgets.lua`
  (text, panels and insets, section headers, buttons, tooltip anchoring), `UI/Fields.lua` (fields, check boxes,
  dropdowns, menus), `UI/Tabs.lua` (tabs), `UI/Containers.lua` (scroll areas, virtual lists with their scroll bars and
  row highlights, portraits, steppers), `UI/Popup.lua` (the dropdown list), `UI/Window.lua` (the window, dialogs and
  Escape).
- Escape closes one of our frames per press, the topmost (`W.CloseOnEscape`): one hidden stand-in is in
  `UISpecialFrames` (the game hides every entry there on one Escape) and closes the topmost of ours, the higher strata
  first, then the one shown last. Registering with the game's own Escape list (`RegisterGameMenuEscHandler`) would
  taint it. Run mode and the Notes window stay open. Hiding the UI (Alt+Z) runs OnHide everywhere while frames stay
  "shown": handlers check `W.Hidden(self)` / `W.UIHidden()` and decline or cancel nothing.
- Buttons (`W.Button`) take left clicks only; right-click menus belong to list rows (`W.List`).
- `UI/Style.lua`: colour tokens (one palette; the old dark/light setting is ignored), font objects, backdrop presets
  (window, panel, thin) applied through `BackdropTemplateMixin`, with a drawn fallback; the materials
  (`Style.NineSlice`, `Style.Inset`, `Style.MenuBackground`, `Style.DialogChrome`, `Style.HeaderStrip`).
- `UI/Art.lua`: every Blizzard texture path and atlas the UI draws, each with a fallback, checked with
  `C_Texture.GetAtlasInfo` / `GetFileIDFromPath`; the frame templates, nine-slice layouts and helper functions it uses
  (`Art.TEMPLATES`, `Art.LAYOUTS`, `Art.HELPERS`, `Art.NativeReport`); round masks; boss portraits; `Art.CreateFrame`
  creates frames from templates inside `pcall`. `/dp debug` prints what this client lacks.
- Boss portraits (`Art.SetBossPortrait`): a creature's model portrait is drawn off screen while the client loads it
  (a portrait drawn on screen before that is a black square), the host shows the skull meanwhile. Every portrait still
  loading waits for one shared timer; when it fires, each ready portrait is drawn again and moved onto its host in
  place (the rows, the boss header, the map pins and the side panel's boss steps change without a rebuild) and
  `PORTRAITS_READY` fires. Later requests in the wait get one more timer; with nothing loading no timer runs.
  Finished portraits are pooled per creature; a creature loads once: a second texture for it shares the first one's
  wait, and one for a creature already loaded is ready at once. `UI/Portraits.lua` starts the wait early
  (`Art.PrefetchPortraits`, the display IDs from `Journal.PlanPortraits`): when a plan is chosen (before its page
  draws), when an instance is selected on the home table, when `/dp shots` starts, and on entering a dungeon or raid
  (the plan that instance opens with).
- Item names: an item the client has not cached has no name; the first lookup (`Names.Item`) asks the client to load it
  (`C_Item.RequestLoadItemDataByID`, else `Item:ContinueOnItemLoad`). The client answers that request with
  `ITEM_DATA_LOAD_RESULT` (`GET_ITEM_INFO_RECEIVED` counts too, but the request alone does not fire it). Arrivals within
  0.2 s go out as one `ITEMS_READY` message; the open window and run mode redraw once with the names. An item still
  nameless 4 s after it was asked for (no answer, a failed one, a name that lands without an event) is checked and asked
  again, at most three times a session; then it keeps "Item 12345" and hovering it asks once more (its tooltip loads it).
  The check timer runs only while an item waits. The Gear page asks for every listed item, not only the rows in view.
- Map content colours (pulls, routes, party roles) are strong enough to read on parchment.

## Window and navigation

`UI/MainFrame.lua` builds the window on first open (`W.Window`: title bar with the title and close, the portrait
ring, the header row with the settings and language menu), the body and the bottom bar. The body shows `UI/Home.lua`
(Dungeons / Raids / My plans / Shared as tabs under the window, over a table of instances or plans, and a preview of
the selected one; data helpers and plan actions in `UI/PlanActions.lua`) or `UI/InstancePage.lua` (the war table:
back, instance and plan pickers, plan menu and Undo in the header row; the side panel `UI/SidePanel.lua` with the
plan's state, steps and party; the section; the sections as tabs under the window and Run mode in the bottom bar).
Sections are the panels in `UI/Panels/` (map, encounters = Bosses, pulls, assignments = Party, gear, share,
plan = Notes with progress), built on first use. Navigation state is saved in the profile (`ui.view`, `ui.homeTab`,
`ui.homeSelected`, `ui.instance`, `ui.tab`, `ui.selectedPlan`, `ui.step`).

Steps (`Model/Steps.lua`, pure): `Steps.Build(plan)` orders a plan as entrance, packs, bosses, notable stops (quest
givers, NPCs) and objectives: route stops first, matched to the markers they stand on (a stop on a boss with a pull is
two steps, the pull then the boss); then pulls and notable markers the route passes, placed by their distance along it
(`Steps.Project`); the rest by pull and boss order. `ctx:Steps()` caches the list
until the plan changes; `UI.FocusStep(i)` makes a step current (saved as `ui.step = { plan, index }`), sets the map's
floor, pull or boss focus and route segment (`Steps.Focus`), and fires `STEP_CHANGED`, which the side panel and run
mode follow. `UI/RunMode.lua` is the compact run window (current step, next pull, next boss's tips, a mini map from
`MapCanvas` in compact mode: no labels, no numbered stops, only the step's party positions, a ring on the step,
framed with its neighbours by `view:FrameSteps`), Prev / Next); the pull key bindings walk the steps while it is open, and the tracker's `BOSS_KILLED`
moves past a killed boss's step (`Steps.AfterKill`). In a group, the leader's run mode can drive the members' (group
sync: `Share/Sync.lua`, `UI/RunSync.lua`; the messages and rules in docs/SHARING-FORMAT.md, "Group sync for run mode").

Recommended plans (`Model/Bundled.lua`, data files call `Bundled.Add`) are read-only: `Plan.*` mutators refuse them,
`ctx:ReadOnly()` hides the edit tools, and "Make an editable copy" duplicates one with `origin` set.

## Map canvas

`UI/MapCanvas.lua` draws art layer 1 of a uiMap as tiles (`C_Map.GetMapArtLayerTextures`), laid out in view units
(no `SetScale`), so pins keep their size while zooming; the gold border frames it as a parchment, and a parchment grid
stands in where a map has no art. Coordinates are normalized 0..1 over the art layer. When a stored map has no art and the
game's old dungeon tiles do not cover the floor either, a same-named map with art is looked up
(`Instances.FindArtMapByName`, the approach ForeverDungeonJournal uses: map names are read once per session into an
index, each name's answer cached).

### Enemy positions (Data/Spawns.lua)

Where creatures stand inside an instance, drawn as the map's "Enemies" layer. The interface, which the UI relies on and
the data side keeps stable:

```lua
ns.Spawns.Available()            -- true when spawn data exists for this client at all
ns.Spawns.For(plan, floorIndex)  -- never nil: an array (empty when nothing is known) of
-- { x, y, name, npcID?, level?, elite?, rare?, kind = "mob" | "elite" | "rare" | "boss" | "npc" }
-- x, y normalized 0..1 on that floor's map, the same space as the plan's markers; entries are shared, read-only
```

The data is generated (`tools/gen_spawns.lua` -> `Data/Spawns/*.lua`, described in `data-src/spawns/README.md`) and
matched by instance, so a player's own plans get it too. `UI/MapSpawns.lua` reads it guarded (a missing module, an
error or an empty list hides the layer and its legend row), leaves out spawns the plan already marks (same name as a
marker's label, or within 0.02 of a marker on the floor), merges dots closer than a few pixels
(`MapLayout.Cluster`), and draws them from a pool under the plan's pins. `MapSpawns.LayerShown(plan)`: the legend
switch (`ui.mapLayers.spawns`) when set, else on for recommended plans.

### The Adventure Guide resolver

Recommended plans ship with names but without journal IDs (docs/DATA-SOURCES.md), so `Data/Journal.lua` matches every
plan to the client's journal at display time, cached for the session: by journal ID when a plan has one, else by name
(case, punctuation and a leading "The" ignored; a wing such as "Dire Maul: East" falls back to its whole instance, a
variant such as "Stratholme (Live)" to its namesake), else by instance or map ID, so other client languages still
match when a plan carries IDs. Plan bosses pair with journal bosses by ID, else by boss or creature name. From the match
come the card and header pictures, the boss portraits (creature display IDs), the encounter IDs used for kill tracking,
the dungeon map (`dungeonAreaMapID`, its floors from `C_Map` map groups, matched to plan floors by ID, name or
position) and the guide's boss pins. "Make an editable copy" stores the IDs found (`Plan.ApplyJournalIds`). A scan
that finds nothing (the journal not ready, the Blizzard guide open) is retried on a later call.

Pins come from pools: boss portraits in the Adventure Guide's ring, round icons in the gold minimap ring, pull-coloured
discs for packs, role icons for positions; routes are outlined lines with joints at bends, direction chevrons spaced by
screen distance (`MapLayout.RouteMarks`, drawn by `MapRoutes` in `UI/MapPins.lua`) and numbered stops. Layers
(`Schema.LAYERS`) can be hidden from the legend; positions tied to a boss or pull show while it is in focus. Without
boss markers, the Adventure Guide's own boss pins (`EJ_GetMapEncounter`) are shown. `UI/MapInput.lua` holds tooltips and
input (state machine `view.drag`: idle / pan / marker / point / draw). Tools (own plans): Select (drag to move markers
and route points), Marker, Position, Pull, Route (click a bend, Shift-click a stop, right-click ends; with "Snap to
corridors", below, a click is a stop and Shift-click a straight leg), Draw, Erase.

### Snap to corridors (Model/Walk.lua, Data/Corridors.lua, UI/RouteSnap.lua)

With the route tool's "Snap to corridors" on (`ui.snapRoutes`, the default) and a walkability grid for the floor, a
click adds a numbered stop and the leg from the route's last point follows the corridors; Shift-click keeps that leg
straight; dropping a dragged stop finds its two legs again (Shift on the drop: straight). The bends go into the route as
plain points, so the plan format and export strings are unchanged.

- `Data/WalkData.lua` (generated by `tools/walk_grids.py`, docs/DATA-SOURCES.md): per floor picture a 120 x 80 grid of
  floor, rough (drawn, not floor: walls, doors) and blocked cells, as run lengths.
- `Data/Corridors.lua` picks a floor's grid by the picture its coordinates are measured on, for the floor as the map
  shows it (`Floors.View`, so an extra floor not yet in the plan counts, and the art at the floor's `art` position):
  the old map tiles, Santiago Reyes' map through the alignment it would be drawn with, the minimap floor through its
  transform. It keeps 4 decoded grids (dropped when the map hides or the tool leaves Route), and finds legs
  synchronously: `Corridors.Leg(plan, floor, ax, ay, bx, by)` returns the bends in
  the same call. The one-time work of a floor (decoding its grid, then the wall distances and prices of
  `Walk.Prices`) is prepared ahead by `Corridors.Prepare`, which the map's corner controls
  (`UI/Panels/MapControls.lua`) call when the route tool is chosen on a floor with a grid, when the map changes floor
  with it and when the switch is turned on: one piece a frame (`C_Timer.After(0)`, four frames), changing no plan.
  Another floor replaces the one in progress; a leg asked for before its floor is ready finishes the preparation in
  the call. Nothing runs once it is done. The measured times are in docs/DATA-SOURCES.md.
- `Model/Walk.lua` (pure): A* over 8 neighbours with a price that rises near walls (paths keep to the middle of
  corridors) and a high price for rough cells (crossed only where the floor alone does not connect the stops),
  12,000 cells at most per leg, then Douglas-Peucker with a line-of-sight check; a search runs to completion.
- `UI/RouteSnap.lua`: the click and the drop. The map panel adds the clicked point (or `UI/MapInput.lua` moves the
  dropped one), `RouteSnap.Stop` / `RouteSnap.Moved` find its legs and put their bends in, and then the panel records
  the change with `ctx:Changed`: one click or drag is one undo step that ends with the snapped route, and no edit can
  come between the search and the record. Only drops made with the Route tool re-snap; with Select a stop moves
  alone. A dragged stop's leg with bends is found again, a straight one only when its line was clear before the drag
  (where the stop was is noted by the drag's first move). A leg that finds no path (or would make the route too long)
  stays as it was and leaves a notice under the map for 4 seconds.

### Drawings (Model/Drawing.lua, UI/MapDraw.lua, UI/Panels/DrawBar.lua)

The Draw tool opens a second toolbar line (`DrawBar`): pen, line, arrow, circle, box, text, eraser and move, the eight
palette colours and three widths, and a menu with Clear floor and Clear all (each behind `W.Confirm`). The data model is pure
(`Model/Drawing.lua`, format in docs/SHARING-FORMAT.md): normalized points per floor, freehand strokes simplified with
Ramer-Douglas-Peucker (the tolerance is 1.5 screen pixels at the zoom the stroke was drawn at, growing until the stroke
fits 40 points) and quantized to 3 decimals; caps of 50 shapes per floor and 150 per plan keep strings small.

```
left press, Draw tool  -> MapDraw.DrawBegin (refused in combat)  view.drag = draw, OnUpdate = OnDrawUpdate
OnDrawUpdate           -> combat: DrawCancel; else DrawMove (pen: a point every 3 px, only the new preview segment
                          is placed; shapes: the preview redrawn; move: the shape's offset; eraser: hit shapes removed)
release                -> DrawEnd: Drawing.Add / Move (one ctx:Changed = one undo step), text opens W.AskText
hidden map             -> DrawCancel
```

Rendering: every shape is pooled `Line` regions on the canvas overlay (sublevel 5, the selection halo 4): over the map
art and the route, under every pin (pins are frames above the overlay). Round joints only at bends sharper than 20
degrees (`Drawing.Joints`), so smooth strokes cost one line per segment; at most 2400 segments per redraw. Text labels
are pooled font strings on a dark plate. While a drawing tool is active, pins stop taking the mouse so strokes can
start anywhere. Selection, the eraser and the right-click menu find shapes by distance (`Drawing.HitTest`, 8 screen
pixels), never by frames under the mouse. Visibility: the legend's Drawings layer; on the full map drawings tied to
another pull or boss than the one in focus dim; run mode's mini map shows the current step's (`Drawing.Visible`
"step": tied to its pull or boss, or to no step), all, or none (`ui.run.drawings`). New drawings made while a boss or
pull is in focus belong to it, like party positions.

Recommended plans stay read-only for drawings too: no Draw tool, `Drawing.*` refuses them; "Make an editable copy" is
the way to draw on one. (A personal overlay layer per recommended plan was considered and left out: it would be a
second store with its own sharing rules for little gain over a copy, which keeps everything in one plan.)

### Undo and redo (Model/History.lua, UI/Undo.lua)

`ctx:Changed` (UI/Undo.lua) takes a deep copy of the selected plan after every change; `History` keeps 50 of them for undo and the
undone ones for redo (a new change clears redo). Every edit (markers, routes, drawings, pulls and their marks, steps,
notes, bosses, party, gear, an import that replaced the plan on the table) goes through it, so one Undo button serves
them all. Each edit is complete when it is recorded (a snapped route leg is found before its click is recorded), so
one action is one step. Selecting another plan starts a new history; it is never saved. Keyboard shortcuts are left out on purpose:
taking keys from the game needs `SetPropagateKeyboardInput`, which is restricted in combat.

## Run recorder (Model/RunLog.lua, Tracker/Recorder.lua)

Opt-in (`settings.recorder.enabled`, off by default; the Runs section, Run mode's recorder line or the settings switch
it). Inside an instance the client gives no position and no creature identity (docs/COMPATIBILITY.md section 10), so
a run is a sequence of **pulls** = combat segments, plus boss kills and wipes:

```
PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA -> RunLog.Enter (same instance within 30 min: the same run) / Leave
PLAYER_REGEN_DISABLED (inside the run's instance) -> RunLog.PullStart; a 0.5 s C_Timer ticker starts
  ticker -> Recorder.ScanPlates (C_NamePlate: hostile, living, in-combat units; level, classification, plain names)
         -> RunLog.Observe (peak counts: the same mob cannot be told apart between looks)
PLAYER_REGEN_ENABLED -> ticker stops; RunLog.PullEnd (group members dead, all dead = wipe); a pull with no enemy seen is dropped
ENCOUNTER_END success 1 / BOSS_KILL -> RunLog.BossKill (deduplicated); success 0 -> RunLog.BossWipe
another instance, "End run", or coming back after 30 min -> RunLog.Finish (kept only with a pull or a kill)
```

Every value read from the game goes through `Util.Plain` (a secret becomes nil and is not stored). `RunLog` is pure:
summaries, best splits per boss (`RunLog.Best`, `Splits`), and `RunLog.PlanFromRun`, a draft plan (pulls in order with
their make-up in the note, bosses in kill order with their encounter IDs, no markers) that goes through
`Validate.Plan` and `DB.AddPlan`. The Runs section (`UI/Panels/RunsPanel.lua`) shows the runs of the plan's instance,
found by the Group Finder's instance map ID for its name (`Recorder.KeyForPlan`); Run mode shows the live pull count.
`RECORDER_CHANGED` refreshes both. Idle cost: nothing (event handlers only; the ticker runs only during combat inside
a recorded run).

### Runs against the plan (Model/RunCompare.lua)

Pure, over a run and the plan's steps. A run cannot say which pack a pull was (no positions, no creature identity), so
everything is paired **by order between boss kills**:

```
plan side   Steps.Build(plan) -> trash entries grouped by the boss that ends them ("skip" pulls left out, a "next"
            pull and the one after it = one entry), then the entries after the last boss  (PlanSequence)
run side    run.p in order; a pull with a kill ends a stretch; a wipe with a boss-level enemy seen is a boss attempt,
            not trash; the open pull is not counted yet                                   (RunSequence)
kills       matched to plan bosses by game ID (Journal.GameIdOf), else by name             (MatchKill)
Overlay     per plan boss: planned entries vs the trash before its kill, paired 1:1 ("pair" / "extra" / "skipped");
            the trash after the last kill goes to the first boss not killed yet; kills the plan lacks get their own
            stretch; divergences: extra, skipped, order (a boss killed before an earlier planned one), unplanned,
            notReached (finished runs)
Pair        two runs: summary rows, boss times, trash per stretch (by boss key), each with A - B
Splits      RunLog.Splits plus the previous run's time per boss (Previous = the run before it by start time)
Drift       live, on the current run: trash pulls done / planned, pulls since the last kill against the pulls planned
            before the boss the run is heading for, the step it is probably at (the next planned pull of that stretch,
            or its boss once they are done), warnings: more pulls than planned before that boss, the latest kill out of
            order
```

What drift cannot know on Forever: where the group is, which pack it pulled, whether two packs came as one. The step is
an estimate that assumes the plan's order; run mode shows it ("On plan · step ~ 6") and goes there on a click, but never
moves the step by itself (only a boss kill does, as before).

The Runs section's "Show" dropdown picks This run (splits against best and previous), Against the plan (the overlay),
or Compare with another run (a four-column table). Share > Advanced > Discord's "Run summary" renders the selected
run (or the latest) with `Discord.RenderRun`.

## Prep (Model/Prep.lua, Data/PrepInfo.lua, Data/Travel.lua, Data/Navigation.lua)

```
Model/Prep.lua        pure: Quests(quests, env) -> rows, counts (status done / log / low / available; the other
                      faction's counted apart), Keys(keys, env) (have: true / false / nil), Group(members, lo, hi, kind)
                      (roles, missing seats, levels below), Bearing / WorldBearing (yards, 8-point direction),
                      NearestNodes(nodes, continent, x, y, faction, n), Crossings(transports, from, to), Summary
                      (one per key group: an item and the quests toward it; a quest key's alternative IDs count)
Data/PrepInfo.lua     the game: faction, level, C_QuestLog, item counts, the group; Questie's givers; PREP_CHANGED
                      to the watchers (PrepInfo.Watch): the Prep section, run mode (its prep line only), the Getting
                      there window, each while shown
Data/BossData.lua     Quests(plan), Keys(plan): bundled (data-src/bosses)
Data/Travel.lua       TravelData (data-src/travel) by instance name; the entrance on its bundled zone map (uiMapID,
                      not the zone's name) and in the world (C_Map world <-> map, cached per session); zone and
                      continent names from the client's maps; the player outdoors (nil inside); Distance
Data/Navigation.lua   the game's pin, the navigation providers (Polestar, Shortest Path Forever, TomTom) best first;
                      nothing in combat or while dead; the world map only through C_Map.OpenWorldMap, never with the
                      gamepad style
UI/GettingThere.lua   the card's lines (pure over the above) and buttons; its small window
UI/Panels/PrepPanel.lua the section; RunMode.PrepText the run window's line
```

Prep notes are a plan field (`prep`, format 5, optional; `DB.SCHEMA` 6 only marks the data). Idle cost: event
handlers that return at once unless a watcher shows prep.

The live map (`UI/TravelMap.lua`) runs on a state machine, `Model/TravelLive.lua`:

```
hidden  --show (outdoors)-->  live     [start ticker, draw]       ticker: C_Timer.NewTicker(0.1) -> tick event
hidden  --show (inside)--->   waiting  [draw]                     inside = the player is in the target already
live    --tick (no position)-> waiting [stop, draw]               a tick carries the position it read; an
                                                                  unchanged position and line draw nothing
waiting --world (outdoors)-->  live    [start, draw]              world: PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA
live or waiting --world (in the target, inside false)--> waiting, inside [stop, arrived: its plan and run mode open,
                                                                  the window closes]
live or waiting --world (in the target, inside true)--> waiting  [no arrival: the player did not come in]
any     --hide-->              hidden  [stop]                     a tick or world event while hidden changes nothing
```

"In the target" comes from the instance ID (`GetInstanceInfo`'s eighth value, `Travel.Here`), never the localized
name: each travel record carries its plan's instance map ID (`iid`) and floor maps (`maps`), and when wings share an
ID (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire) the floor map the client gives picks the wing; without
one, every wing of the instance counts.

Learned entrances: `PLAYER_LEAVING_WORLD` keeps the outdoor position (`Travel.Player`, with world yards). When the next
`PLAYER_ENTERING_WORLD` ends inside an instance (only that event uses the spot; `ZONE_CHANGED_NEW_AREA` updates the
live map alone), `TravelLive.Choose` takes the one record of that instance whose bundled entrance lies within 400
world yards of that spot (or, for an instance with no bundled entrance at all, whose zone map the spot is on; a
bundled entrance the client cannot place in the world learns nothing); none, or several (wings sharing one entrance),
learns nothing. So a summon, a hearthstone or a portal from farther away teaches nothing, while one taken within 400
yards of the entrance can be learned. The spot is put on the map the entrance is drawn on and filed by
`TravelLive.Learn` under the instance in `global.entrances` (per account, at most 100, `NormalizeLearned` on load;
additive, no schema change); an instance's first learned spot is replaced only by one within 100 yards of it
(`RELEARN_RADIUS`), so a later summon nearby does not move it. `Travel.Entrance` prefers it over the bundled one
(`Travel.Bundled`). `/dp entrances reset`, or the Settings panel's "Forget learned entrances" (Troubleshooting; for
gamepad players, who have no slash commands), forgets them all and the bundled entrances are used at once.

## Raid pages (Model/Pages.lua, UI/Panels/PagesEditor.lua, UI/NotesFrame.lua)

Named pages of free text per boss or phase (plan field `pages`, format in docs/SHARING-FORMAT.md), written in the
Party section's Pages (a switch over its left column; the raid groups stay beside it) and shown in the Notes window.
`Model/Pages.lua` is pure: edits (refusing recommended plans), validation, keyword expansion, permissions, the received
store and the Notes window's state machine.

```
Pages.Expand(text, env)   {star}..{skull}, {rt1}..{rt8} -> raid icons; {tank} {healer} {dps} -> role icons; {group N}
                          -> the plan's names; {mage} etc. -> class icons; names whose class the roster knows -> class
                          colour; a line naming the player (or their {group N}) -> marked. Unknown keywords stay.
                          env.chat: {rtN} (the chat draws it), role and class words, plain names (Pages.ChatLines)
Pages.CanSend(rank)       in a raid the leader or an assistant, in a party the leader
Pages.AcceptFrom(policy, sender rank)   "leaders" (default) | "group" | "nobody"
Pages.ViewStep(view, event)   { shown, auto, combat, hideInCombat }: open / close / toggle, encounterStart (a page
                          found and auto-show on -> auto), encounterEnd (auto off), combat, setting
                          visible = (shown or auto) and not (hideInCombat and combat)
```

`UI/NotesFrame.lua` builds the environment from the client (class tokens and names from `GetClassInfo`, colours from
`RAID_CLASS_COLORS`, class icons from `CLASS_ICON_TCOORDS`, the group finder's role sheet, the roster's classes through
`UnitClass`; each guarded), pushes pages with `Comm.SendPage` (`N` messages, through the lockdown outbox) and posts
them to group chat through ChatThrottleLib (out of combat, never in a lockdown, 20 lines of 250 bytes). On
`ENCOUNTER_START` it picks the boss's page: a received page by encounter ID or boss name, else the selected plan's page
tied to that boss (`Pages.ForEncounter`: game ID, else name). The window is built on first show; idle it is only event
handlers.

## Data providers (Data/Providers.lua, Data/Providers/)

Optional adapters that read other addons' data at runtime in the player's client; nothing is copied into the
repository (docs/COMPATIBILITY.md section 6 has the matrix: source, licence, public API or internals, verification).

```lua
Providers.Register(adapter)   -- { id, addon, title, internals, provides, Detect(), Counts(root), capabilities... }
Providers.Get(id)             -- adapter, root when enabled and its data has the expected shape; detected once per session
Providers.Call(id, method, ...) -- pcall; an error deactivates that adapter for the session
Providers.FloorArt(plan, floor) -- a provider's map for a floor without art: art in Instances.MapArt's shape plus
                                --   provider, credit, artist?, pins = { { name, x, y } }, align = Providers.Align(...)
Providers.Routes(plan, floor, art) -- another addon's route on that floor in the drawn art's coordinates (Forever
                                --   Dungeon Routes): { provider, credit, lines = { { points, side, title? } }, stops }
Providers.PickFloor(plan, floor, list, describe) -- a provider's floor for a plan floor, by name (label, words, position)
Providers.Loot(plan, enc)       -- items { itemID, name?, quality?, slot?, slotText? }, credit
Providers.Portrait(plan, enc)   -- { icon } or { displayInfo }, credit (Journal.BossArt falls back to it)
Providers.BossInfo(plan, enc)   -- { level?, rare?, description?, summon = { itemID }?, drops? }, credit (Data/BossInfo.lua)
Providers.LootLinks()           -- adapters with OpenLoot (NeedRoll's public API)
Providers.Report()              -- /dp debug: id, title, active, internals, version, counts, failure
```

Matching is by instance name (`Providers.Key`: `GameFiles.Key` plus its aliases) and boss name (`Match.StripArticle`).
Order of map art for a floor (`MinimapArt.Choose`): the game's own map (`C_Map`), the old dungeon tiles
(`Data/GameFiles.lua`), a same-named map with art, then Santiago Reyes' bundled map of a Forever floor
(`Data/ReyesMaps.lua`, source "reyes"), then the providers in registration order (Dungeon Journal, Forever Dungeon
Routes, OpenMap) while "Prefer drawn maps" is on (the default), then the game's minimap pictures (`Data/MinimapArt.lua`,
drawn in the parchment colours: `MapCanvas.ArtStyle`); with the setting off the minimap pictures come before the drawn
maps; then the parchment grid. A bundled or provider floor is picked by the plan floor's name (`Providers.PickFloor`).
A bundled map is credited on the canvas ("Map by Santiago Reyes", its tooltip naming his site and donation page); when
Dungeon Journal or Forever Dungeon Routes draws the same picture, its boss pins, alignment and routes are used on the
bundled map. A provider map is credited on the canvas ("Map: Dungeon Journal") and its boss pins in their tooltips. **Alignment** (`Providers.Align`): the plan's boss
markers are paired with the provider's pins by name; "same" draws as stored, "fit" draws through a per-axis scale and
offset (`MapCanvas` `ToMap` / `FromMap`, input inverted so edits stay in plan space), "pins" hides the plan's boss
markers and shows the provider's pins. **Provider routes** (`Providers.Routes`): Forever Dungeon Routes' own route on
the floor, in the drawn art's coordinates and only on art they fit, drawn by `MapRoutes` as an extra layer (teal, off
until ticked in the legend, `ui.mapLayers.providerRoutes`). Adapters that read internals (Dungeon Journal, Forever
Dungeon Routes, OpenMap) isolate every table access behind shape checks, so an update of that addon can only switch the
adapter off.

### Bundled boss facts (Data/BossData.lua, Data/Bosses/, Data/BossInfo.lua)

`BossData` holds what ships about each boss of the recommended plans (generated by `tools/gen_bosses.lua`, docs/DATA-SOURCES.md)
and answers with the shape of the Dungeon Journal adapter, matched by instance and boss name like the providers:

```lua
BossData.Boss(plan, enc)             -- { level = "20" | "24-25" | "??", rare?, class?, npcID?, drops?, abilities? }
BossData.Loot(plan, enc)             -- { { itemID, slot?, notable? } }
BossData.Portrait(plan, enc)         -- { displayInfo = id }
BossData.Abilities(plan, enc, max?)  -- { { spellID, tags = { "interrupt" }, note? } }
BossData.Quests(plan)                -- { { questID, name, level?, req?, side?, giver?, items? } }
BossData.Credit                      -- "Wowhead, warcraft.wiki.gg", shown as "Sources: ..."
```

`BossInfo.For(plan, enc)` merges: the bundled facts first, then the provider's (`Providers.BossInfo`) filling what is
missing and adding its description and summon item; `info.dropsCredit` / `info.abilitiesCredit` name the source of a
list. `Providers.Portrait` and `Providers.Loot` try the bundled data first. `BossInfo.Sections` yields an "abilities"
section (rows with the spell icon and name from `C_Spell`, tags, our note, the game's spell tooltip) before "drops";
`BossInfo.KeyAbilities(plan, enc, n)` gives run mode's icons.

## Module map

| File | Responsibility |
|---|---|
| Core/Init.lua | namespace, AceAddon object, multi-handler events, internal bus, combat deferral |
| Core/Util.lua | text cleaning (escapes, UTF-8), secret values, ids, item ids |
| Core/Compat.lua | API checks and in-game self-tests (`/dp debug`) |
| Core/Integrations.lua | WoW Po Polsku detection, Dungeon Journal, OpenMap, launcher + minimap button |
| Core/API.lua | public API and CallbackHandler events |
| Core/Report.lua, UI/ReportFrame.lua | the problem report (`/dp report`, the title bar's `!`): facts about the addon, client, plan and other addons, the `/dp debug` summary and the last Lua errors (`ns.Errors` in Core/Init.lua, filled by `ns.SafeCall`; BugGrabber read only), the new-issue link for `.github/ISSUE_TEMPLATE/bug_report.yml`; never character, realm, guild, group, chat or plan names |
| Core/WhatsNew.lua, UI/NewsFrame.lua | the What's new card and the first-run welcome: highlights per version (kept in step with CHANGELOG.md by a test), shown once when `global.news.seen` differs from the running version, never on a first install |
| Core/Perf.lua | `/dp perf`: opt-in timing. `start` registers a timed event dispatcher and swaps `ns.Fire` and `ns.SafeCall` for timed versions (own against total time with a depth stack, spike ring, frames and hitches, the game profiler sampled every 5 s); `stop` puts them back. Nothing runs or is wrapped while it is off |
| Core/Actions.lua, Core/Slash.lua, Core/Boot.lua | key bindings, slash commands, lifecycle |
| Locales/ | English (keys) and Polish |
| Model/ | plan schema, validation, operations, routes ("suggest order": nearest neighbour + 2-opt), progress, recommended (bundled) plans |
| Share/ | checksum, bounded inflate, export strings, transfer state machines, AceComm glue, Discord text |
| Config/ | defaults, AceDB, migrations |
| Data/Instances.lua | maps (names, floors, art, name search), the player's location, dungeon-finder level ranges |
| Data/Journal.lua | the Adventure Guide resolver: scan (tiers, instances, pictures, maps), bosses with portraits, matching plans to the journal (Model/Match.lua), floor maps, boss pins, IDs for editable copies, `/dp scan` diagnostics |
| Data/Loot.lua | journal loot per boss with class, role and slot filters (guarded; the plan's own list otherwise) |
| Data/BossData.lua, Data/Bosses/ | bundled boss facts: display, level, abilities, drops, dungeon quests (generated by tools/gen_bosses.lua; interface above) |
| Data/Spawns.lua, Data/Spawns/ | enemy positions per instance floor for the Enemies layer (generated by tools/gen_spawns.lua; interface above) |
| Model/Walk.lua, Data/WalkData.lua, Data/Corridors.lua, UI/RouteSnap.lua | Snap to corridors: the path search (pure), the walkability grids (generated by tools/walk_grids.py), which grid a floor has, its preparation over a few frames and synchronous legs, the route tool's click and drop (above) |
| Data/Names.lua, Data/Templates.lua | display names by ID; generic plan templates (no game data) |
| Model/Drawing.lua, Model/History.lua, Model/PlanLists.lua, Model/PlanBosses.lua | map drawings (data, simplification, caps, geometry, hit-testing); undo and redo snapshots; gear and objectives, and bosses, assignments and groups (split from Plan.lua) |
| Model/Match.lua, Model/MapLayout.lua, Model/Steps.lua | pure matching of plans to journal entries (names, wings, map IDs, bosses, floors); map label and pin collision avoidance, dot merging, route chevrons and bend joints; a plan as ordered steps |
| Tracker/ | kill and run tracking; `Recorder.lua`: the opt-in run recorder (events, nameplate scans during combat) |
| Model/RunLog.lua | the run recorder's pure model: pulls, kills, wipes, history caps, best splits, plan from run |
| Model/RunCompare.lua | a run against its plan (pulls paired by order between boss kills, divergences), two runs side by side, live drift |
| Data/Providers.lua, Data/Providers/ | data-provider layer and adapters: Dungeon Journal, Forever Dungeon Routes, OpenMap, NeedRoll, Questie |
| Data/BossInfo.lua, UI/BossSections.lua | what a boss page says beyond the plan: the provider facts (level, description, summon item, drops) per plan boss, cached per plan revision, and a marker's details without repeated names; the sections drawn the same on the map's details pane, the Bosses page and run mode |
| UI/Style.lua, UI/Art.lua | colour tokens, fonts, backdrops; Blizzard art names with fallbacks |
| UI/Widgets.lua, UI/Fields.lua, UI/Tabs.lua, UI/Containers.lua, UI/Popup.lua, UI/Window.lua | widget kit: controls, insets, section headers; fields, dropdowns, menus; tabs; lists with scroll bars, portraits, steppers; the opaque popup list behind every dropdown (virtual rows, one keyboard-and-pointer cursor, closes on an outside click); the window, dialogs and Escape |
| UI/MainFrame.lua, UI/StepText.lua, UI/Undo.lua, UI/Home.lua, UI/PlanActions.lua | window, header and bottom bar, steps context; how a step reads (title, caption, floor, where stairs lead); ctx:Changed, undo and redo; home table and preview; plan actions, instance list data, pictures and the drawn plate |
| Data/Floors.lua, UI/Panels/FloorBar.lua | every floor an instance has map art for, merged with the plan's (no duplicates); the map's floor switcher |
| UI/InstancePage.lua, UI/SidePanel.lua | the war table: header pickers, section bar; steps and party |
| Model/Picker.lua, UI/InstancePicker.lua | the instance picker: sections, level bands, search and cursor (pure); its rows and popup |
| UI/Panels/MapToolbar.lua | the map's edit tools (a picture and a name each) and the toolbar line's layout: what gives way on a narrow table |
| UI/MapDraw.lua, UI/Panels/DrawBar.lua | the drawings on a map view and the drawing tools' input; the Draw tool's toolbar line (picture buttons, their glyphs, the clear menu) and the drawings' menu |
| UI/MapCanvas.lua, UI/MapArt.lua, UI/MapPins.lua, UI/MapInput.lua, UI/MapSpawns.lua | map drawing (the view, its fit and pan, the plan on it; the map art, its colours and credit chip, the grid); pin pool, pin styles and label placement (labels on a dark plate), route paths (outlines, joints, chevrons); map tooltips and input; the Enemies layer, floor loading, step centring and framing |
| UI/RunMode.lua | the run window (with the recorder line, the drift line and the prep line) |
| Model/Prep.lua, Data/PrepInfo.lua, Data/Travel.lua, Data/TravelData.lua, Data/Navigation.lua, Data/Providers/TomTom.lua, Polestar.lua, ShortestPathForever.lua | Prep: quests, keys, group, the way there, navigation hand-off (section above) |
| UI/Panels/PrepPanel.lua, UI/GettingThere.lua | the Prep section; the Getting there card and its window |
| Share/Acks.lua | shared-plan tracking: acks of imported plans, versions per member, the group's status (current, outdated, missing, unknown); links from received copies to their sender's plan |
| Share/Sync.lua, UI/RunSync.lua | group sync for run mode: the state machine (leading, following, free, mismatch), plan matching and the steps revision; the glue (messages, timers, step focus) and run mode's sync line |
| Share/Roster.lua | the group's units and members, a sender's rank by its whole name (surnames on Forever), whisper targets as names arrived |
| Model/Pages.lua, UI/Panels/PagesEditor.lua, UI/NotesFrame.lua | raid pages: data, validation, keywords, permissions, the Notes window's state machine; the Party section's editor; the Notes window, sending and chat posting |
| UI/Panels/ | sections (map + legend, marker editor and menus, plan, bosses, pulls, assignments, gear, runs, notes, progress, share) |
| UI/Prompts.lua, UI/Settings.lua | share prompts, options page |
