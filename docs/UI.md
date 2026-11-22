# The window: a war table

Dungeon Planner's window is laid out like a raid leader's briefing table: the map of the instance in the middle, the
plan's order of play beside it, the party at hand, and everything else one click away in the tabs under the window.
The layout is its own; the materials are the game's: its framed window with the portrait ring, inset panels, panel
buttons, window tabs, scroll bars, list highlights and menus, Friz Quadrata in the game's gold and white
(Materials, below).

## Why this direction

Versions 2.0 and earlier copied the look of a popular WoW: Forever journal addon closely: the same rock-and-gold
window, a home grid of picture cards, a breadcrumb, red section buttons under a large header. Players read that as the
same addon, and the layout suited reading about a dungeon more than planning a run through it. A planner is used
differently:

- **The map is the work surface.** Routes, pulls and positions are drawn on it, so it gets the full height and most of
  the width instead of sharing the page with a header panel.
- **The order of play is always visible.** A plan is a sequence (entrance, packs, bosses, objectives); the side panel
  lists it, and picking a step shows that step on the map.
- **Choosing the instance and the plan is a header control**, not a page of its own, so switching costs one click.
- **Native materials, own layout.** Players asked for a window that looks like the game's own (as polished as the
  Adventure Guide or NeedRoll), but not like another addon's layout. So the window is built from the game's window
  parts where the client has them (the same ones the game's Collections, Professions and Settings windows use), in
  the game's dark brown, stone and gold, while the arrangement (map in the middle, steps beside it, pickers in the
  header) stays Dungeon Planner's.

## Layout

```
(O)--------------------- Dungeon Planner ---------------------------X   title bar (portrait ring, title, close)
(O)  < [Deadmines v] <> [Full clear v] [...] [Undo]                 *   header row beside the portrait
+-----------+------------------------------------------------------+
| state     |  [Select][Marker][Pull]...   [Legend][Fit][Focus][Floor]|
| [copy]    |                                                       |
| Steps  9  |                 MAP (full height)          +--------+ |
| 1 Entry   |            o--1--o----2---[B]              | Legend | |
| 2 Pack    |                       \                    | layers | |
|>3 Rhahk'Z |                        3--[B]              | routes | |
| 4 ...     |                                            +--------+ |
|-----------|  [x] Labels                                           |
| Party     |  Icon size - 100% +                                   |
| T H D D D |                                                       |
+-----------+------------------------------------------------------+
|                                               [Run mode]  v1.x   | bottom bar
+------------------------------------------------------------------+
  /Map\/Bosses\/Pulls\/Party\/Gear\/Runs\/Share\/Notes\                the game's window tabs, under the window
```

- **Header** (`UI/Window.lua`, `UI/MainFrame.lua`, `UI/InstancePage.lua`): the game's title bar with the title and
  the close button, the addon's logo in the portrait ring; under the title bar, right of the ring, the header row: on an
  instance page a back button, the **instance picker** (below), **Show location** (the game's waypoint pin,
  `Waypoint-MapPin-Tracked`, else the map icon), the **plan picker** (recommended plans marked with the raid star),
  the plan menu ("...") and Undo; on the right the settings button (options and language). The header's tooltips open
  below their control, never over the next one. Show location is the Getting there card's "Show on world map" one
  click away (`GettingThere.Locate`): a click pins the entrance and opens the world map on its zone (only the pin with
  the gamepad interface style), a right-click or Shift-click opens the Getting there window, as does a click when the
  game can neither pin nor show the entrance. Its tooltip names the zone and says what a click does there; it is off,
  greyed, with the reason in its tooltip, in combat, while dead and for an instance without travel facts.
- **Side panel** (`UI/SidePanel.lua`, 236 px, an inset): the plan's state ("Recommended plan · read-only" with
  **Make an editable copy**, the red panel button), the **steps** (Model/Steps.lua) under a section header, each
  with an icon in a ring by kind: a boss its portrait in the Adventure Guide's ring, a pull its number on a disc in
  the pull's colour in the gold map-pin ring, an entrance, objective or marker its icon in that ring; and under its
  own section header the **party strip**: tank, healer and three damage dealers for a
  dungeon, the eight groups (filled / 5) for a raid. Clicking a step makes it current and focuses the map; clicking the
  party opens the Party section. Each party slot is a dark plate in a bronze ring with the group finder's role glyph
  (`groupfinder-icon-role-micro-tank`, `-heal`, `-dps`, else the classic `LFGRole` sheet, else the round
  `UI-LFG-RoleIcon-*` icons) and the player's name under it, or a muted "Open". The ring is bronze for every role:
  the round damage icon (a slanted sword on a red disc) and ability icons in a red ring both read as a "no entry"
  sign. Where the plan names nobody, the seats show the group as it is (`Model/Party.lua`, `UI/PartySeats.lua`;
  solo, the player alone): each member by the role set in the group finder; without one, a damage-only class in a
  damage seat, and a class that can also tank or heal in the empty tank or healer seat it can fill (the least
  flexible first), else a damage seat, as a guess. Whoever is left (a fourth mage, a class the client cannot tell)
  takes a free seat, which the tooltip says plainly ("Role not set: placed in a free seat."). A member is the short
  name (the first name) in class colour, cut by its letters with "..." when one word is too long, with the level
  small on the plate's lower right; a guess, a free seat or a member in a seat that is not their role reads dimmer,
  an offline or dead member dims the plate too. The tooltip: the whole name (with the surname), the role, level and
  class, and how the seat was chosen ("Role not set: guessed from class."). A name the plan stores keeps its seat
  and is matched to a member by the whole name, or, for a first name stored before plans kept surnames, by the one
  member with that first name (`Party.Match`; two members with it match neither, and the tooltip says so instead of
  "Not in your group."). Members past the five seats show as "+1" on the header, named in the strip's tooltip. A
  raid plan that sets no groups shows the raid's groups as they stand (`GetRaidRosterInfo` only), the counts muted.
  The Party section's card fills its seats the same way, with "Tank • level 18" under the plate and "+1 more in your
  group" at its top right. Both redraw on the group's events while shown (Data/PartyInfo.lua, one redraw 0.3 s after
  a burst); hidden, nothing. The roster is read once per group event, not on every resize or redraw.
  One identity across the plan: Fill from my party (in a raid: the player's own group) and Fill from my raid, the
  assignment targets and the Notes window store and match whole names and show the short name.
- **Section area**: the map by default; Bosses, Pulls, Party (assignments), Gear, Runs (the run recorder), Share and
  Notes (details, notes and progress) in the same place, each in an inset.
- **Gear**: the filters on one line (they shrink alike on a narrow window), and under them a line of its own with the
  hint on the left and "Open in NeedRoll" on the right, so the two never overlap; where loot comes from is named in the
  list's section header ("Drops (Dungeon Journal)", on the header band). An item's tooltip opens beside the item's
  name, top-aligned with it (`W.AnchorBeside`: just right of the name's last letter, not at the row's far edge), so
  the game's comparison tooltips line up next to it over the rows below. The game keeps tooltips on screen; when that
  pushes one up over "Open in NeedRoll", it opens left of the item's icon instead.
  The filters (`Model/GearFilter.lua`): **class** shows the items the class can wear and wield at full level, by the
  current client's class rules (armor up to its heaviest type, the weapons, shields and relics it can use; rings,
  necklaces, trinkets, cloaks and held-in-off-hand items for every class; things that are not equipment stay), by the
  item's class and subclass from `GetItemInfoInstant`. It does not know the level at which mail or plate becomes
  wearable, nor whether Forever keeps the classic rules (see "Needs a look in game"). **Boss** shows one boss's drops
  or the whole instance; **slot** the item's equip location (a one-hand weapon under main hand and off hand). The bundled and provider drop lists are item IDs, so an item the client has no data for yet is
  asked for and joins a filtered list when it arrives ("Loading items..." meanwhile). **Role** filters the plan's own
  entries by their role tag (drops carry no role; the Adventure Guide's loot by specialization where a client has
  it); on a read-only plan without such entries it is disabled with a tooltip saying so.
- **Sections**: the game's window tabs hanging under the window's bottom edge (on the home screen the same place holds
  Dungeons, Raids, My plans and Shared). The window stays on screen with them.
- **Bottom bar**: Run mode, version and status.

### Instance picker and dropdown lists

```
[Hall of Thanes v]
+------------------------------------------+
| (search) Search dungeons and raids...    |
| [(D) Dungeons      ][(R) Raids         ] |
|------------------------------------------|
| Levels 10-19 ----------------------------|
| [art] Ragefire Chasm       LV 13-18 *1 ok |  <- every boss killed: a check
|#[art] Hall of Thanes       LV 13-20 *1    #|  <- the cursor (the list hover); the open instance has a gold bar
| [art] The Deadmines        LV 17-26 *1 2/7 |  <- bosses killed
| Levels 20-29 ----------------------------|
| ...                                       |
+------------------------------------------+
```

`UI/InstancePicker.lua` on the popup list of `UI/Popup.lua`; the list logic is `Model/Picker.lua`. An opaque panel
in the game's menu look (`common-dropdown-bg`, whose soft shadow the popup's frame includes, over a fill `menu`, alpha
1, under its panel only) in the `FULLSCREEN_DIALOG` strata,
anchored under the control (above it when the
screen has no room below), 420 x 440. A search field at the top filters as you type, by name (case and punctuation
ignored) or by a level inside the range; the Dungeons and Raids tabs carry the game's `Dungeon` and `Raid` marks and,
while searching, their match counts, and the picker moves to the other section when the open one has no match. The
dungeons are divided into level bands of ten ("Levels 10-19", a bronze rule to the edge); instances without a level
go last under "Other". Each row: a 46 x 24 picture (the loading screen cropped, or the drawn plate's mark on slate),
the name, the level range in the game's difficulty colours (`GetQuestDifficultyColor`, as on the home table), the
plan count with the raid star when a recommended plan exists, and the bosses killed ("2/7", a check when all are).
There is no "Forever" tag: nothing in the client or the data names an instance as new in Forever without a list of
names in the code.

Every dropdown (`W.Dropdown`) opens the same popup as a plain list as wide as its longest option. One highlight per
list, the cursor (the game's list hover), moved by the pointer and the keys alike; the current choice has a gold bar
and bright text. Up /
Down, Page Up / Down, Enter, Escape; Tab switches the picker's section; Home / End in lists without a search field.
A click anywhere else closes it (`GLOBAL_MOUSE_DOWN`, else a full-screen catcher), as does hiding its control; a list
that holds the keyboard (no search field) closes when combat starts, so it never keeps keys it can no longer pass on.
Rows come from pools per list style and only visible rows get a frame (rows of mixed height, laid out by offset).

### Steps and map focus

`Model/Steps.lua` turns a plan into an ordered list: the numbered route stops first, each matched to what it stands
on (a boss marker, a pull, an entrance, a quest giver); a stop on a boss that has a pull gives the pull its own step
before the boss. Pulls no stop covers and notable markers (quest givers, NPCs, quest items, interactive objects) that
the route passes go where the route reaches them. Pulls and bosses still left are placed by their order (a boss whose
marker belongs to a pull right after that pull), then objectives (after their boss). Without a route the steps follow
pull order. Hall of Thanes reads: Portal in, Ghostly Attendant, Faldrim Anvilmar, pull 1, Magmatus, Plunder, pull 2,
Durgen Dirgehammer. A stop that stands near a boss an earlier stop already made a step of (a route walking on past the
boss, or back by it) is a move, not that boss again. Quest items show the item's own icon and name (the client's,
in the player's language); a name too long for the row keeps its end ("...Hungerer's Heart"). Focusing a step
(`UI.FocusStep`) sets the map's floor, its pull or boss focus (which also shows the party positions tied to it), and
the route segment that leads to the step (drawn bold; the rest of the route dims), and centres the map on the step.
The current step is the side panel's one highlight and is saved per profile (`ui.step`).

### Home

```
+--------------------------------------+---------------------------+
| [Dungeons][Raids][My plans][Shared]  |  +---------------------+  |
| [search...............] [x] Only... |  |  loading-screen art |  |
| Instance            Levels Plans Boss|  |  The Deadmines      |  |
| [art] The Deadmines  17-26  1 plan 0/7|  +---------------------+  |
| [art] Wailing Cav.   15-24  1 plan  - |  Levels Plans Bosses Floors|
| ...                                  |  Plans: * Full clear       |
|                                      |  [Open plan] [New plan]    |
+--------------------------------------+---------------------------+
| [New plan] [Current location] [Custom map...]  35 instances  v1.x |
```

A table, not a card grid: name with a small picture, level range (coloured by the game's quest difficulty colours),
plan count and bosses killed; one click selects and fills the preview, a double click or **Open plan** opens the war
table. My plans uses the same table and preview for your plans; Shared lists received and imported plans with the
import box in place of the preview. Selecting an instance starts loading the bosses' portraits of the plan it opens
with (`UI/Portraits.lua`), so its page shows faces sooner.

**Level colours (decided).** Level ranges keep the quest log's difficulty colours for the player's level (grey
trivial, green easy, yellow even, orange hard), but never its red: anything five or more levels above shows in the
orange of "very difficult" (`Style.LevelColor` probes at most four levels above the player). A column of red ranges
read as a warning or an error, when it only means "later"; the orange still says "not yet", and the Levels heading's
tooltip explains the colours. The picker uses the same colours.

Where the game has no picture of an instance (`/dp scan`: Forever's new dungeons, Stratholme, Onyxia's Lair and the
Ahn'Qiraj and Hyjal raids), the preview draws a **plate**: slate stone, the game's dungeon or raid mark in a bronze
ring, and the instance's name.

### Run mode

```
+-----------------------------+
| (o) Run mode          [m] X |
| Ragefire Chasm · Full clear |
| * Recording · 4 pulls · plan: 9 |
| STEP 3                      |
| Taragaman the Hungerer      |
| Boss · Taragaman on his ... ~ |
| +-------------------------+ |
| | mini map: step + neighbours | |
| +-------------------------+ |
|        Map: Dungeon Journal |
| NEXT PULL                   |
| Pull 3: Searing Blade      |
| Enforcers (on two lines)    |
| NEXT BOSS                   |
| Jergosh the Invoker         |
| The strongest of the pair...|
| [Prev]     3 of 9    [Next] |
+-----------------------------+
```

`UI/RunMode.lua`: a compact window to keep open while playing. Prev / Next move through the steps, as do the "Next
pull" / "Previous pull" key bindings while it is open; "Toggle run mode" is a key binding of its own (no default
key). A boss kill the tracker reports moves past that boss's step (matched by encounter ID, else by name; a kill that
matches no boss of the plan, inside its instance, completes the next boss step). The line under the plan's name is the run recorder: a red dot and "Recording" with the live pull count against
  the plan's pulls, or how to start it; a click switches recording (docs/ARCHITECTURE.md, Run recorder). While a run of
  the plan's instance is recorded, a line under it shows the progress against the plan: "On plan · step ~ 6" in muted
  text, or a warning in orange ("! 1 pull more than planned before Magmatus", "Plunder killed before Magmatus"); its
  tooltip has the counts and says what the estimate cannot know, and a click goes to the estimated step. The step
  block moves down under it, and the next boss's tips give up the line. It is a plain, non-secure frame, so it
works in combat; it is movable, and its position and whether it was open are saved (`ui.run`). Escape does not close
it.

The step block is as tall as its lines (at most a label, the title and two lines of text); the mini map under it
takes the rest of that room, so a one-line step leaves no gap above the map and the blocks below keep their place.
The mini map is the map canvas in compact mode: it frames the current step with the steps before and after it on the
same floor (`view:FrameSteps`; neighbours far away are left out, the box has a margin of a tenth of the map around them and
is never smaller than about three tenths of it, so the step, its route and the names painted on the map near it are not
cut at the frame's edge), draws a steel-blue ring on the step, shows only that step's party positions, and draws no
labels and no numbered route stops (the ring already marks the step). The map's source is a caption under the map,
not on the art. The next pull's name wraps onto a second line before it is cut (after a whole word), and that block
takes the height its lines need. Prev and Next have one width and the step counter sits between them; both are the
game's panel buttons, so Prev on the first step has the game's own disabled look.

Under the mini map, on the left, a small caption switch for the plan's drawings: "Drawings: this step" (the default:
those tied to the current pull or boss and those tied to no step), "Drawings: all", "Drawings: hidden"; one click moves
to the next, the choice is saved (`ui.run.drawings`), and it shows only when the plan has drawings. A pull step's caption
carries the pull's marks (tags, CDs, Lust) and the planned forces so far ("Forces 34%": the last pull up to this step
with a planned progress); the next pull's text starts with its marks. Run mode keeps its size: nothing else was added.

Spots a recommended plan only estimates ("(approx.)" in its notes) show a small muted "~" after the text in run mode,
the side panel and the marker details, and a line "~ Approximate: an estimate, check it in game" in map tooltips,
instead of the words.

### Runs

```
[x] Record my runs   Off
Runs ------------------- Best 9:00 | Run ------------------ [Create plan from run]
2025-11-17 15:33  9:00 · 6 pulls  | [Against the plan            v]
2025-11-16 14:33 10:30 · 7 pulls  | 2 pulls, plan 2
                                  | Off plan: 1 pull more than planned before Magmatus
[Clear history]                   | Before Magmatus / 2 pulls, plan 1 (+1) / 1. Pull 1 ... / + extra pull ...
```

The right column's "Show" dropdown: This run (time, splits against the best and the previous run, pulls), Against the
plan (each boss's stretch: planned against actual pulls, paired in order, "+ extra pull", "- skipped", "next:" for the
stretch in progress, and a closing line on what the pairing cannot know), and "Compare with <date>" for each other run:
a table with the columns A (the selected run), B and A - B, differences that are better in green and worse in orange.
Before the instance has a run, the Run column says how to start ("Turn on "Record my runs" and play this instance"),
or, with recording on, "Recording is on. Your next run in this instance will appear here."; the check box and the
Settings panel's switch both redraw it (`RECORDER_CHANGED`).

### Prep and Getting there

```
+ Before you go ------------ [ ] Show all + Getting there --------------- [Pop out] +
| Quests to pick up (3)                    | Westfall · Moonbrook                    |
| To pick up 3 · In your log 1 · Done 1    | Alliance territory                      |
| In your log [17] Red Silk Bandanas       | Entrance: 42.6, 71.8 on the map of ...   |
| To pick up  [18] Collecting Memories     | Levels 17-26 · you are 18 · a party of 5 |
|   Gryan Stoutmantle, Westfall 56.3, 47.5 | How to get there                        |
| Keys and attunements                     | Alliance: fly to Sentinel Hill, ...      |
| Not with you  Seal of Ascension Required | Horde: fly to ... (muted)               |
| Group                                    | You are 390 yd away; it lies south-west. |
| Party: 3 of 5 · Tank 1 · Healer 1 · ...  | [Show on world map] [Navigate: X] [...]  |
| Still needed: 2 Damage                   | Prep notes ----------------------------- |
| Tamsin · level 13 (below 17-26) · Damage | [multi-line field]                      |
+------------------------------------------+-----------------------------------------+
```

`UI/Panels/PrepPanel.lua`, the second tab ("Prep"), two insets like Notes. Left, a document: the instance's quests
(the player's log first, then to pick up; done and too-low ones behind "Show all", their counts on the summary line;
the other faction's never), the giver and zone under each quest with Questie, the objective items with their icons;
keys and attunements (have it in green, missing and required in orange, "(classic fact; not checked on Forever)"
where no Forever source confirms one); the group (roles against the five seats, levels against the range in orange
when below). Right: the Getting there card (`UI/GettingThere.lua`) over the prep notes (a field in an own plan, a
muted line in a recommended one). The card's text is a document too: the zone in the client's language, the area,
the territory (orange "enemy territory for you"), the entrance's coordinates and how it is entered, the research's
hint, a summoning stone, the levels coloured like the home table with the player's level, each faction's nearest
flight master with the direction and distance from it (the player's faction first, the other muted), boats and
zeppelins when the player is on another continent, and outdoors the distance and direction (Polestar's travel time
when installed). Inside an instance it says distances show outdoors: the client gives no position there. Under it
Show on world map (the game's pin, then `C_Map.OpenWorldMap`), Navigate with the best target in its label and "..."
for the others (`Data/Navigation.lua`). "Pop out" and the home preview's "Getting there" (bottom right, no plan needed)
open the same card in a small movable window (`ui.travel`, DIALOG strata). The Prep section, run mode's prep line and
that window each register a watcher and redraw on `PREP_CHANGED` (quest, bag, group, level and zone events; one
message 0.3 s after the first of a burst, sent only while one of them is shown); run mode redraws only its prep line.
The Prep section also redraws on `ITEMS_READY`.

Run mode, before the first step (not started or on step 1), shows a gold line in the drift line's place: "Prep: 3
quests to pick up · 1 key missing"; a click opens the Prep section. It hides once there is nothing left or the run
moves on.

The Getting there window (`UI/GettingThere.lua`, 380 x 560 by default, at least 320 x 460 so the card has room under
the map) has a live map on top (`UI/TravelMap.lua`,
170 px tall, as wide as the window): the entrance's zone map from the game's map art, fitted and centred on the
inset's dark fill, with the entrance (the `Dungeon` mark), the nearest flight masters of both factions on that map,
a summoning stone, and the player as the minimap arrow turned to `GetPlayerFacing` (on a city, cave or other map of
the same area the arrow is placed from world yards). Under it one live line: the distance and direction ("You are 870
yd away; it lies south-west."), "(you are in Elwynn Forest)" when the player is on another map, or the outdoors-only
line. The card below leaves the distance to that line (the Prep section's card keeps its own). A resize lays the art
out again and puts the pins back. The map has no input; the world map and minimap are not touched.

### Raid pages and the Notes window

The Party section (`UI/Panels/AssignmentsPanel.lua`, the people in `UI/Panels/PartyGroups.lua`) has a switch at its
top left, Assignments | Pages, and "Fill from my party / raid" at the top right. A dungeon shows its party as a card
centred under the switch (at most 640 px wide): five seats in a row, each the side panel's role plate larger (40 px)
with the role in gold and the player, or a muted "Open" with "+" while the plan can change, and a line on how the seats
fill; the assignments or pages take the section's width under it. A raid keeps them on the left and its eight groups
on the right, a column of about two fifths (300 to 440 px), two boxes a line whose height fills the column (never less
than five names; the grid scrolls on a short window), each box with its count ("5/5"). The assignment list sits in an
inset that runs to the bottom (the editor of the selected one under it); with nothing in it, its message is centred
in the inset, as is the Pages editor's when there is no page to write (a recommended plan has none: the message says
to make a copy). Pages: Add page (the red button, first) and the page picker with a delete "x"; the title and the boss
the page belongs to; the text in a multi-line field; a two-line keyword help; Send to group, Show and Post to chat at
the bottom. The filter gives up width (down to 110 px) so Add assignment and Post to chat stay on its line.

```
+ Notes ---------------- X +      the run mode window's frame, 380 x 400 by default, resizable (220 x 150 at
| Lucifron                 |      least), movable, position and size saved (ui.notes); not closed by Escape
| From Lead · Lucifron     |      the source: a sender, or the plan and its boss
| (skull) Lucifron: (tank) |      raid icons, role and class icons inline; names in class colour
| > Decurse: Aldra, Tester |      the player's own lines start with a gold ">"
| (<)  1 of 2  (>)         |      the game's page arrows (the spell book's), the count between them; received
|                          |      pages first (newest first), then the plan's
+--------------------------+
```

It opens on a received page, with `/dp notes`, from Show, and on a boss pull when that boss has a page ("Show the
boss's page when its fight starts", on by default); the fight's end closes it unless it was opened by hand. "Hide the
Notes window in combat" (off by default) hides it while in combat.

## Palette

The game's own colours, warm: dark brown and stone surfaces, gold text for headings, warm off-white for the body.

| Token | Value | Use |
|---|---|---|
| `page` | `0.62, 0.56, 0.49` | tint of the window's rock (a tint: the stone keeps its light) |
| `surface`, `insetTint` | `0.075, 0.062, 0.05` / `0.86, 0.78, 0.68` | an inset's fill where its marble is missing; the marble's warm tint |
| `raised` | `0.15, 0.115, 0.08` | rows and plates on a panel (the Adventure Guide's brown rows) |
| `selected` | amber `0.38, 0.24, 0.09` | the selected row under the game's list selection, the drawn cursor |
| `accent` | steel blue `0.42, 0.66, 0.82` | only on the map: the focused step's ring reads against parchment |
| `border`, `borderHover`, `borderSelected`, `hairline` | gold-bronze `0.62, 0.49, 0.29` ... `1, 0.82, 0.38` | drawn edges, rules, the current choice's bar |
| `headerStrip` | `0.80, 0.58, 0.25`, alpha 0.55 | the section headers' band |
| `primary` | red `0.50, 0.09, 0.06` | the drawn primary button, where the game's red panel button is missing |
| `gold`, `goldBright`, `ink`, `muted` | the game's gold `1, 0.82, 0`; `1, 0.91, 0.55`; `0.93, 0.91, 0.86`; `0.71, 0.67, 0.59` | headings and labels; current choices; body; secondary text |

Map content colours (pull and route colours, party roles) are unchanged: strong enough to read on parchment.

## Materials

The window is drawn from the game's own window parts, each through the widget kit (`UI/Window.lua`,
`UI/Widgets.lua`, `UI/Fields.lua`, `UI/Tabs.lua`, `UI/Containers.lua`, `UI/Popup.lua`, `UI/Style.lua` Materials), so a new panel built from the kit
gets them without asking. Each part is checked first (the template's parts by key, a nine-slice layout with
`NineSliceUtil.GetLayout`, an atlas with `C_Texture.GetAtlasInfo`, a file with `GetFileIDFromPath`) and falls back to
a drawn version; `/dp debug` lists the game's parts this client has ("Window parts from the game: n of m") and the
art it lacks. Nothing is copied into the addon: names only, resolved by the client.

"Seen" means the name is used by an installed WoW: Forever addon (read-only, to learn what exists on this client;
their code and art were not copied): that verifies it exists here. "Inferred" means it comes from the game's own UI of
this API family and is guarded.

| Piece | The game's part | Drawn fallback | Status |
|---|---|---|---|
| Window | `ButtonFrameTemplate`: the metal nine-slice frame (`PortraitFrameTemplate` layout) with the portrait ring (the addon's logo, `SetPortraitToAsset`), the title bar, the dark rock `Bg` (tinted `page`), the red close button (our handler); its inset and button bar hidden (`ButtonFrameTemplate_HideButtonBar`) | stone in the metal dialog edge tinted gold-bronze, a dark header strip with the emblem in a gold ring, `UIPanelCloseButton` | Template and helpers seen (NeedRoll, DBM, Baganator; `PortraitFrameTemplate` GearQuest Forever) |
| Run mode window | the same template without the portrait (`ButtonFrameTemplate_HidePortrait`, layout `ButtonFrameTemplateNoPortrait`) | as above | Seen (Baganator, OpenMap, DBM) |
| Inset panels (`W.Panel`) | the `InsetFrameTemplate` nine-slice layout (its dark bevel and inner shadow) on a child at the panel's level (`NineSlicePanelTemplate`, following the panel's level) over the inset's marble `Interface\FrameGeneral\UI-Background-Marble`, tiled and warmed | a dark fill with `Interface\Tooltips\UI-Tooltip-Border` tinted gold-bronze | Layout seen (Auctionator; `InsetFrameTemplate` in WhatsTraining's Forever pages); marble inferred, guarded |
| Section headers (`W.SectionHeader`, `W.Heading(..., band)`, Gear's list headers) | a band of `Interface\QuestFrame\UI-QuestLogTitleHighlight` (the quest log's header glow), added and tinted gold, under a gold heading, with a gold rule | the heading and the rule | File seen (GearQuest Forever, NeedRoll, DBM) |
| Primary buttons | `UIPanelButtonTemplate` (the red panel button; our label in gold, white on hover, grey disabled) | a red plate with the gold edge | Seen (NeedRoll, Dungeon Journal) |
| Other buttons | drawn: a dark brown plate with the tooltip border in gold-bronze and a faint sheen (the Adventure Guide's secondary buttons) | | Drawn |
| Tabs (`W.Tabs`, style "bottom") | `PanelTabButtonTemplate` hanging under the window (`W.HangTabs`: 11 px in, 2 px over the edge), selected with `PanelTemplates_SelectTab` / `DeselectTab`, sized with `PanelTemplates_TabResize`, our tab fonts set again after each | segment plates with the section's icon, a gold bar on the active one | Seen (BugSack, DBM: "Forever shares Mainline's tab helpers") |
| Scroll bars (`W.AttachThumb`, `W.ScrollArea`) | `MinimalScrollBar`: on scroll areas joined by the game's own `ScrollUtil.InitScrollFrameWithScrollBar`; on virtual lists and dropdown lists driven by percentages (`SetVisibleExtentPercentage`, `SetScrollPercentage`, its `OnScroll` callback; our updates never echo back) | a slim gold thumb on a dark track | Seen (WhatsTraining's Forever pages, Dungeon Journal) |
| List rows (`W.List`) | hover `Options_List_Hover`, selection `Options_List_Active` (the game's settings list); boxed rows keep their brown plate | the quest-title glow (added); an amber fill, gold edge and a gold bar on the left | Atlases seen (WhatsTraining's Forever pages, Baganator) |
| Dropdown lists and the instance picker | `common-dropdown-bg` (the game's menu panel, a nine-slice atlas with its shadow, filling the popup's frame; the panel and the content sit `Style.MENU_SHADOW` 10 x 3 px inside), the cursor `Options_List_Hover` | an opaque dark fill with a gold edge, an amber cursor | Seen (ForeverCore, OpenMap, WhatsTraining) |
| Dialogs | the `Dialog` nine-slice layout over `UI-DialogBox-Background-Dark` (atlas, else the file) | the drawn window's stone and edge | Layout seen (Baganator); background seen (WhatsTraining, many) |
| Tooltips | `GameTooltipTemplate` (our own `DungeonPlannerTooltip`; items on `GameTooltip`) | `GameTooltip` | Seen |
| Emblem, plate marks | `INV_Misc_Map_01`; the `Dungeon` atlas (else a portal icon) or the `Raid` atlas (else a dragon head) | | `Dungeon` seen, `Raid` inferred, guarded |
| Step rings, boss portraits | `Interface\Minimap\MiniMap-TrackingBorder` (the map-pin ring; its ring is centred at (20, 19) of the 64 px file, so it is drawn from the 38 px square around that point), the Adventure Guide's boss ring (centred in its crop); both placed by `Art.PlaceRing`, centre on centre | | Seen (Dungeon Journal, NeedRoll) |
| Run mode button | `Ability_Rogue_Sprint` | | Classic icon |
| Page arrows (the Notes window) | `Interface\Buttons\UI-SpellbookIcon-PrevPage-*` / `-NextPage-*` (up, down, disabled), the highlight `UI-Common-MouseHilight` (added), 32 px, as the game's `PagingControlsPrevPageButtonTemplate` and `PagedList.xml` have them; the page label ("1 of 3", "No pages") between them | drawn "<" and ">" buttons | Seen (Dungeon Journal, OpenMap, NeedRoll, Leatrix Plus) |
| Enemies layer | our `Circle`/`Ring` textures tinted, the game's raid skull for bosses | | Drawn |
| Map tools (`tool_*`) | the game's cursors `crosshair_point_32` (Select), `crosshair_mappincursor_32` (Marker), `crosshair_missions_32` (Pull), `crosshair_directions_32` (Route), `crosshair_palette_32` (Draw); `socialqueuing-icon-group` (Position), `common-icon-redx` (Erase); 18 px left of the name | the name alone | In this client's atlas table, guarded |
| Drawing tools (`draw_*`) | `crosshair_broom_32` (Eraser), `crosshair_ui-cursor-move_32` (Move), `128-redbutton-delete` (the clear menu) | glyphs drawn with lines in the text colour: an X, a cross, a bin; Pen, Line, Arrow, Circle, Box, Text and the widths are always glyphs | In this client's atlas table, guarded |

Libraries: the game's own templates and mixins above do the work (nine-slice layouts, `ScrollUtil`, the scroll bar, the
tab helpers); LibSharedMedia (vendored) offers its registered fonts in the font setting. No textures come from a
library: every picture is the game's, by name.

Fonts stay Dungeon Planner's own objects (`DungeonPlannerFont_*`, the game's 1 px shadow; docs/COMPATIBILITY.md
section 8), also on the game's parts (the window's title, the tabs' text), so Polish letters always render. Headings
use Friz Quadrata (or its Polish cut) in the game's gold; body text is warm off-white.

Design rules that hold everywhere: one spacing scale (2/4/8/12/16/24/32/48) and one size set (controls 24, rows
28/34/40); one highlight per list, shared by the pointer and the keyboard; inputs show their border; a view's primary
action comes first, at the start of the line, near the content. One line of text that can be long (names in lists,
steps, dropdowns) goes through `W.FitText`: cut after the last whole word that fits, with "...", and the whole text in a
tooltip (`W.FullTextTooltip`, or the row's own tooltip); never a cut inside a word. A region gets one anchor per edge or
centre: `LEFT` on one frame and `RIGHT` on another at a different height gives it two vertical centres (the UI lint's
`anchor-conflict`); anchor the second edge by a matching point, or set a width.

## The map

The map section's toolbar holds the tools (own plans): Select, Marker, Position, Pull, Route, Draw, Erase, each the
game's picture and its name (`UI/Panels/MapToolbar.lua`), with the kind, role or pull picker of the active tool; on the
right Legend, Fit, Focus and Floor. On a narrow window Focus gives way first, then the tools' names (the pictures stay,
square, the names in their tooltips), then Fit; a tool without its picture keeps its name.
Labels and the icon-size stepper sit in the map's bottom-left corner, inside the gold frame with a margin of their own
(as the legend in the other corner); with the Route tool the "Snap to corridors" switch sits above them, faded on a
floor without corridor data (`UI/Panels/MapControls.lua`). The **legend** floats over the top-right corner:
layer switches with icons and counts, the tool's help while editing, the routes on this floor when there are any, and
the marker editor (`UI/Panels/MapEditor.lua`) whenever a marker is selected. Alone it is compact (204 px wide, as
tall as its content; a recommended plan's single route on a floor is not listed again under the Route row); the editor
takes 248 px and the full height. It shows by itself the first time the map opens and stays off after that until the
Legend button turns it on (the button's choice is saved). Its title is a disclosure (`UI/Panels/MapLegend.lua`):
folded, the legend is that one line, so the art under it shows (Molten Core's painted title is in that corner). Until
the player folds or opens it, it starts folded wherever the open legend would lie over any of the whole map's picture
(a painted title, the plan) or move or shrink the map (`MapLayout.PanelOverMap`), and opens by itself only in an empty
band beside a narrow map; a click on the title is saved (`ui.legendFolded`) and holds on every map. At a usual window
size that means folded on Molten Core, Hall of Thanes and the Deadmines alike. The whole map (zoom 1,
`MapLayout.MapFit`) is as large as the section allows and centred in it (equal bands left and right), with the legend
floating over the map's edge rather than leaving an empty band above and below a map squeezed beside it. With the
legend open over the plan, the map first shrinks about its centre (to 85% at most), then moves sideways within its
own band, and only then takes the size beside the legend. Centring on a step also keeps it clear of the legend.
Where a map's shape leaves bands beside it (a 3:2 map in a wider frame), the table under it is the quest-log parchment,
a shade darker than the map and burnt at the edges, not a black gap. Fit on a map without art frames
the plan's markers and route points (`MapLayout.FitView`) instead of the empty grid. The map's credit ("Map by
Santiago Reyes", or "Map: Dungeon Journal" where another addon provides the map, Data/Providers.lua) is a chip on a
dark plate in the map's own top-left corner, on the picture (in the frame's corner while that corner is scrolled
away), and the provider's boss pins say where they come from.

Map labels sit on a dark plate (a few pixels of margin), so they stay readable over a map's own painted names; label
placement (`MapLayout.Labels`) counts the plate, so labels still avoid each other, the pins and the floating legend,
and stay inside the visible map (within the gold frame): a label below or above its pin slides sideways, one beside
it up or down, and a side where it would be cut is not used. A boss's label, which always shows, takes the place where
it covers least and is moved all the way inside. Pins count their ring: the minimap ring stands out past its art.

**One map family.** The classic dungeons draw on the game's old map tiles: a drawn map on sepia parchment in a scroll
frame. Forever's new dungeons use Santiago Reyes' hand-drawn parchment maps, which ship with the addon by his
permission (`Data/ReyesMaps.lua`; "Map by Santiago Reyes" in the map's corner, its tooltip naming his site and where
to support him), shown exactly as he drew them (Settings, "Prefer drawn maps", on by default). With that setting off,
or on a floor he has not drawn, they are composed from the game's minimap
pictures, which are dark 3D art (on a flat grey where nothing is) or full-colour terrain; by default
(Settings, "Map colours: parchment") they are drawn into the same family (`MapCanvas.ArtStyle`): the quest-log
parchment under them, each picture in grey tinted to the parchment's ochre (`SEPIA`, 90% opaque, so the parchment's
grain shows), the same picture added on top (`LIFT`, ADD blend) so the minimap's mid greys become light parchment
while corridors and walls stay dark brown, and a dark-brown vignette (`Media/Vignette.tga`) for the burnt edge.
"Game minimap colours" draws the pictures as the minimap does. Routes, pins and labels keep their own colours and
plates, readable on both.

Pins never cover each other (`MapLayout.Nudge`, on screen only: the plan keeps its coordinates): a pull's disc on its
boss becomes a badge just right of the boss, a numbered route stop on a marker a badge just left of it, and pins that
still overlap move apart, half the way each. Route bends shown while editing stay where they are.

### Routes

A route has to read on busy map art and stay calm where it bends, doubles back or crosses itself. Each segment is a line
in the route's colour over a dark outline line; each bend gets a joint (a disc in the line's colour over a dark disc),
so routes that follow corridors with many bends turn smoothly. Lines draw under every pin and label.

Direction arrows are small solid arrowheads (`Media/RouteArrowEdge.tga`, with a thin dark edge baked in;
`Media/RouteArrow.tga` without it), tinted a lighter tone of the line and a little wider than the outlined line, so they
sit on it. A larger arrowhead goes just before each numbered stop and at the route's end; the others are spaced by
distance on screen (about 120 pixels at the default density, scaled with the icon-size setting), not per segment, so
they keep the same density at any zoom. `RouteArrows.Place` (`Model/RouteArrows.lua`) keeps them clear of stops, sharp
bends, pins, labels and each other, and leaves none where another part of the route (or another route) crosses the
line; a corridor walked out and back keeps its arrows an arrow's length apart. A leg between two stops that is left
without any arrow gets one near its middle, a little smaller if that is all that fits. The arrows are placed once per
map redraw, after the pins and labels are laid out, only on the visible part of the map and a margin (at most 200 per
route and 400 in all), never per frame. While a marker or route point is dragged or a window is resized the arrows
hide, and they are placed once when that ends (a short timer looks; `ns.sizingWindow` is set by the size grip). Every
part of a route takes its colour from `MapRoutes.Color`: lines, arrows, stop rings and bend discs. While a step
is in focus its leg is brighter and wider and the rest of the path dims. Numbered stops are dark discs with a ring in
the route's colour, drawn above the path. Arrows are turned in their texture coordinates (`MapPins.TurnedCoords`), not
with `SetRotation`, which left every arrow pointing up in game.

**Route settings.** The Routes group in the Settings panel changes the look at once, on the map and in run mode: line
width (thin, medium, thick), line opacity, route colour (each route's own, or one palette colour for every route of a
plan; another addon's routes keep theirs), the dark outline, direction arrows (off, few, normal, many), arrow size,
arrowheads at stops, arrows only on the focused step's leg, and the hover highlight. They are stored in the profile
(`settings.routes`); the arrows' own options are greyed out while arrows are off.

**Two lanes.** A corridor walked out and back (two parts of a route running close together in opposite directions)
draws as two lanes: each direction moves a little to its own right (`RouteLegs.Lanes`, a share of the outlined line's
width), and its arrows follow its lane, so the way in and the way back read apart instead of as one doubled line.

**Hover highlight.** With the pointer over a route line (hit test against the drawn segments, a few pixels of
tolerance), the leg under it, the stretch between the two numbered stops it joins, is drawn above the other lines,
a little brighter and wider, with its arrows at the normal density even where the settings show fewer (but not when
arrows are off), and the rest of the routes dim to 35 %. A tooltip names the two steps as the steps list does
("Step 3 to step 4", "From Lady Anacondra to Lord Cobrahn"). Pointing at a step in the steps list highlights the leg
that leads to it the same way, and run mode draws its current step's leg so. One highlight at a time, shared by the
pointer and the list. It follows the coordinate readout's hover check (at most 20 times a second, only while the
pointer is over the map) and changes only when the leg changes: the lines are restyled and the placed arrows reused.
None while dragging or with a drawing tool, and none over a pin.

Labels at the map's edge keep clear of the coordinate readout in its bottom-right corner.

**Snap to corridors.** With the switch on, a click with the Route tool adds a numbered stop and its leg from the
route's last point follows the corridors; Shift-click keeps the leg straight, and a stop dropped with the Route tool
finds both its legs again (Shift on the drop: straight; with Select it moves alone). The bends appear with the stop, in the same frame as the click: the leg is found
before the change is recorded, so the map never shows a half-made leg and one Undo takes back the stop with its bends.
The floor's corridor data is prepared over a few frames as soon as the Route tool is chosen or the floor changes, so a
click waits only for its own leg (docs/DATA-SOURCES.md has the times). Where no path is found, or the route has no room
for the bends, the leg stays straight and a one-line notice under the map says why for 4 seconds.

**One numbering.** A stop shows the number of the step it makes in the side panel and run mode
(`Steps.StopNumbers`), not its own order in the route: the map and the list always agree. Steps that are not stops
(a pull placed where the route passes, a quest item, an objective) have no number on the map; the focused step's
segment and ring show where they are. A stop that makes two steps (a pull, then the boss it stands on) shows the boss's
number, since it is drawn on the boss; the pull keeps its pull-number disc. Pull discs always show pull numbers. The
stop's tooltip says "Step 6" with "Stop 5" under it, for editing a route.

The side panel's badges follow the same two looks, so a step number never wears a pull's badge: a pull shows its
pull number on a disc in the pull's colour in the gold pin ring; a move step (a stop with nothing on it) shows its
map stop, a smaller dark disc ringed in the route's colour with the step number the stop shows; bosses, entrances,
quest givers and other markers show their icon. A step's caption names its floor only where the plan has several and
the floor is not named as the instance (the Deadmines' first floor is "The Deadmines"; "Ironclad Cove" stays).
A step on stairs or a portal that leads to another floor adds "to <floor>"; a second click on it (the current step)
goes there.

### Floors

The map shows every floor the instance has map art for, not only the plan's (`Data/Floors.lua`): the plan's floors
first, in their order, then the old map tiles, Santiago Reyes' maps and the minimap pictures no plan floor stands for
(Atal'Byzal, the Maximum Security Unit and the Prismatic Talus are in no recommended plan). A recommended plan shows such
a floor as plain map art; in an own plan, putting something on it makes it the plan's (`Floors.Ensure`). The home
table's Floors count is the same list.

The floor switcher (`UI/Panels/FloorBar.lua`) sits in the map's bottom-right corner inside the frame (left of the marker
editor while that takes the map's height; the coordinates move over it), hidden on a one-floor map:

```
two to four floors:   [ The Deadmines ][ Ironclad Cove ]        (tabs; the current one lit)
more:                 [<][ Hall of Blackhand  4/6 ][>]           (and the toolbar's floor list)
```

A tab's tooltip counts the plan's markers on that floor; Shift + mouse wheel over the map goes to the next or previous
floor (round). Tabs too wide for the map's bottom edge (long names, Polish) give way to the arrows. The switcher stays
out of the top-left corner, where many maps have their entrance (the Deadmines). Stairs and portals on the map say
"to <floor>" after their label, labels on or off; in a recommended plan a click on one goes there (an own plan's click
opens the editor; its right-click menu has "Go to"). Run mode's mini map names its floor in its top-left corner when
the instance has several.

### Marker icons

| Kind | Icon | Layer |
|---|---|---|
| boss | portrait in the Adventure Guide ring (a skull where the game has no portrait) | Bosses and rares |
| rare | `INV_Misc_Head_Dragon_01`, silver ring | Bosses and rares |
| pack, patrol | disc in the pull's colour with the pull number; a skull or an arrow without a pull | Packs and patrols |
| loot, chest | `INV_Misc_Bag_10`, `INV_Box_01` | Loot and chests |
| quest_item, quest_npc, npc, interactive | the item's own icon (`C_Item.GetItemIconByID`), else `INV_Misc_Bag_07` (the quest-in-progress atlas is three dots on this client); `QuestNormal` / `AvailableQuestIcon`, `GossipGossipIcon`, `INV_Misc_Key_03` | Quests and NPCs |
| entrance, exit, shortcut, stairs | `Dungeon` atlas / portal icon, `poi-door` / `Spell_Arcane_Blink`, `Ability_Rogue_Sprint`, `poi-door-arrow-up` / `Spell_Magic_FeatherFall` | Entrances, exits and shortcuts |
| hazard | `Spell_Fire_Fire` | Hazards |
| position | role icon: `Ability_Warrior_DefensiveStance`, `Spell_Holy_FlashHeal`, `Ability_MeleeDamage`, `Ability_Marksmanship`; ring in the role's colour | Party positions |
| note | `INV_Misc_Note_01` | Notes |

**Party positions are focus-only, by design.** Positions tied to a boss or a pull show while that boss or pull is in
focus (the Focus picker, the current step, or the legend's hint below); untied positions always show. Every
recommended plan ties its positions to a boss, so at "Focus: everything" the map shows none of them: a tank, a healer
and damage spots around every boss at once would crowd the bosses' pins and labels, and they only mean something for
the fight in focus. The legend says so instead of leaving a count with nothing on the map: while nothing is in focus
and the floor has tied positions, the Party positions row carries a gold line "Focus a boss to show them" ("...a pull"
when only pulls have them), and a click on it focuses the first boss (else pull) with positions on the floor, as the
Focus picker would (`MapLegend.FocusTarget`). The count stays the floor's total.

### Enemies layer

Where creatures stand (`Data/Spawns.lua`, docs/ARCHITECTURE.md), drawn under everything the plan draws
(`UI/MapSpawns.lua`): small red dots for ordinary enemies, a bronze ring for elites, a silver ring for rares, the
game's skull for bosses, gold for friendly NPCs. Dots closer than about 9 px at the current zoom merge into one with a
count (`MapLayout.Cluster`, at most 300 per redraw); hovering lists names and levels. A spawn whose name is a marker's
label, or that stands within 0.02 of a marker on the same floor, is left out, so the plan's own pins are not doubled.
The legend row "Enemies" appears only when the floor has spawns to show; the layer is on by default for recommended
plans and off for your own until you switch it. The dots pass clicks and drags through to the map.

### The "Forever" tag

An instance new in WoW: Forever (its recommended plan's `instance.origin`, docs/DATA-SOURCES.md) carries a small chip,
"Forever", bronze-gold caption text on a dark pill with a bronze edge, in the instance picker's rows (left of the
level) and in the home table (centred on the row at the end of the name column, left of the levels: on the tag line
its edge touched the name above it and read as an underline); hovering it says "New in WoW: Forever". The chip takes the mouse for
hovering only, so a click still opens the row. The picker's search matches "forever" (from three letters on).

### Another addon's route

With Forever Dungeon Routes installed, the legend gets a row "Routes: Forever Dungeon Routes" on floors where it has a
route that fits the drawn map (`Providers.Routes`). Ticked, its main path is drawn like a plan route in teal (palette
6) and its side paths fainter, along with the plan's own route and under its pins, without stops or numbers; it is off
until ticked
and never drawn in run mode's mini map.

### Drawing

```
[(pointer) Select][(pin) Marker][(group) Position][(swords) Pull][(scroll) Route][(palette) Draw][(X) Erase]  [Legend][Fit]
[~][/][/>][o][#][T][(broom)][(arrows)]  [c][c][c][c][c][c][c][c]  [thin][medium][thick]  [(bin)]
```

The Draw tool opens a second line under the toolbar (`UI/Panels/DrawBar.lua`) and the map moves down under it: one
line of square picture buttons (`W.ToolButton`), each named in its tooltip with its hint, which fits the minimum window
(880) in every language and wraps only on a narrower table. Pen, Line, Arrow, Circle, Box and Text show a glyph of what
they draw, the widths a line of each width (drawn with lines in the button's text colour: gold, white when lit, grey
when disabled); Eraser and Move the game's broom and move cursors, with a glyph where the client lacks them. The active
tool, colour and width are lit; swatches are the pull palette (so the colour-blind setting recolours them and every
drawing). With the Move tool a click selects a drawing (a light halo under it) and the swatches and widths restyle it.
Right-click a drawing: change the text, use the chosen colour and width, show it with the boss or pull in focus or on
every step, delete. The bin at the line's end opens a menu, Clear floor and Clear all (greyed out when there is nothing
to clear; the bin itself while the plan has no drawings); each asks first in the game's dialog; Undo brings drawings
back. Drawings sit over the map art and the route and under every pin,
text labels on the same dark plate as map labels; the legend's "Drawings" row switches them. Nothing can be drawn in
combat ("Drawing is not available in combat.").

### Pull marks

The pull list takes nearly half the Pulls section (280 to 440 px), in an inset, and its rows are two lines high with
3 px between the lines, so a pull's name wraps instead of being cut ("Dark Iron Summoner patrol (Magmatus)") and its
second line does not touch the first; a recommended plan's pull shows in a card beside the list, as tall as its text:
the name, the marks, the note, its markers and where it comes in the run ("Step 4 of 8, before Magmatus"), then Show on
map.

The Pulls editor has, under the name and colour, toggles for the tags (Interrupt, Crowd control, Line of sight, Pull
with next, Skip, Careful) and the planned Cooldowns and Bloodlust / Heroism, wrapping to the editor's width, then
"Forces after this pull (%)". The pull list, the steps' captions and run mode show the short forms ("Interrupt · CC ·
CDs · Lust · 34%"): words, not colours or icons, so they read with any colour vision and on any client.

### Colour-blind palette

Settings, "Colour-blind friendly colours": pulls, routes, drawings and party roles switch from the parchment palette to
the Okabe-Ito set (vermillion, blue, bluish green, reddish purple, orange, sky blue, yellow, light grey in the same
slots; black is swapped for light grey to read on parchment). Every map colour is read through `Style.PaletteColor` /
`Style.RoleColor`, so one switch covers the map, the lists, the steps, run mode and the drawing swatches.

### Share and plan sources

Share lists Export, Import and Send in game, each under a section header on the band; the Discord text is folded under
an "Advanced" disclosure at the end of Export (`W.Disclosure`: a caret and a gold label, closed by default, the choice
saved in `ui.shareAdvanced`), and opening it pushes Import and Send down. Under Send in game, while in a group: "Has this plan:
2 of 4 group members, outdated: 1, unknown: 1" (Share/Acks.lua), each member's state in its tooltip. The plan picker's tooltip and the
Notes section name where a plan comes from: a recommended plan's source, data revision and data date (and the route's
credit), a copy's original, a shared plan's sender (`UI.PlanSource`).

## Performance

Pins, route lines and their outlines, joints, chevrons, route points, journal pins, enemy dots and drawing segments,
joints and labels come from pools;
nothing is created per redraw. The map
redraws on a plan change, a zoom, the end of a pan, a step focus, a setting change or a resize, never per frame; while
a pan lasts only the canvas moves (pins, routes and drawings are anchored to it). One change refreshes the map section
once (`UI.Batch`), and the Enemies layer and boss portraits are computed once per plan revision (`DB.Revision`). OnUpdate runs
only while dragging, while a drawing press lasts (only the stroke's preview or the moved drawing is redrawn), or while
the pointer is over the map (coordinates, 20 Hz). The steps are rebuilt only after the
plan changes, in near-linear time (about 0.03 s for a plan at every list limit). Lists are virtual (only visible rows exist). Run mode redraws on a step change or a plan change.

## Needs a look in game

- Prep: quest states after accepting, abandoning and turning in a quest; quest titles in Polish and Russian clients;
  the key icons and names (a key on the key ring, in the bank); the group lines in a party and a raid; the Getting
  there card outdoors (distance and direction match the world map; the entrance coordinates of a classic and a Forever
  dungeon; the zone name in the client's language), inside an instance (the "outdoors" line), Show on world map (the
  pin, super-tracking, the map opening; nothing in combat), Navigate with Polestar, TomTom and none; the Pop out window
  and the home preview's button; run mode's prep line on step 1 and its click.
- The live map in the Getting there window: the zone's art, the arrow's place and turn while walking and riding, the
  flight master and stone pins, the live line; that it stops inside an instance and starts again outside; entering the
  target instance opening its plan and run mode; a learned entrance replacing the bundled one after a loading screen.
- Gear filters on a recommended plan (Wailing Caverns): Warrior and Mage change the drop list (a mage loses Lord
  Cobrahn's leather and mail), a slot shows only that slot, a boss only his drops; items not cached at login join the
  list once loaded (no endless "Loading items..."); the disabled role filter's tooltip; whether
  `C_Item.GetItemInfoInstant` or the global answers (`/dp debug`, "Item types"); an item that never loads leaves
  "Loading items..." after about 13 seconds.
- The class filter's rules on Forever (`Model/GearFilter.lua` follows the current client's rules and does not model
  levels): can a level-20 hunter or shaman wear mail, a warrior or paladin below 40 wear plate, a rogue use one-handed
  axes, a druid use polearms? Adjust the table to what the game allows.
- Show location in the header: the pin's look beside the instance name and greyed when off, its tooltip (zone, hint),
  the click pinning the entrance and opening the world map, right-click and Shift-click opening Getting there, the
  button off in combat and while dead and back after both, off for an instance without travel facts; with the gamepad
  interface style, the pin only; the header at the minimum width (880) in German.
- The party strip filled from the group: what `UnitGroupRolesAssigned` answers on Forever outside the group finder,
  class colours and the role guesses from the client's specializations, a member going offline; a member's death and
  return dimming and restoring their seat (`UNIT_FLAGS`; the player's own through `PLAYER_DEAD` / `PLAYER_ALIVE` /
  `PLAYER_UNGHOST`); a plan holding first names matched to "First Surname" members.

Since 0.1.0:

- Floors: the switcher in the map's bottom-right corner (tabs on the Deadmines and Shaper's Terrace, the name between
  arrows on Lower Blackrock Spire and Blackmaw Hold), left of the marker editor while one is selected, the coordinates
  over it; the Prismatic Talus, Atal'Byzal and the Maximum Security Unit on their own maps; Shift + wheel; "to
  <floor>" on the Scholomance outside portal and its step; run mode's floor plate. Inside a dungeon: `/dp scan`, then
  look at `position.bestMap` / `mapGroup` in the saved diagnostics (does the client give a map there?).
- Gear: items three to a line at the default size, two at the minimum width (880); hover, Shift-click and right-click
  on each cell; the item tooltip beside the name.
- Bosses: an ability with a one-line note (no gap under it); Hall of Thanes' labels beside Reliquary of Kings, Dark
  Iron Ingress and Anvilmar's Rest, the denser plates.
- Notes: the objectives right under the bosses; a raid (Molten Core) side by side. Pulls of a recommended plan: the
  list box as tall as the pulls. Home, My plans: the tip under a short list, the boss order and Open plan under the
  preview's text.
- The bullet separator (•) everywhere, in Russian especially (it was a box with the Cyrillic face).
- With the gamepad interface style on: no `/dp`, the minimap button and key bindings open the window, the gamepad
  menus leave it alone; the Settings panel's debug button reports "Gamepad interface style: on".
- A recommended plan's "may be out of date" line on a client whose build is more than 90 days newer than the plan's
  data.

From 0.1.0:

- The map centred in its frame on every classic and drawn map (equal bands left and right, the table's parchment in
  them); the legend's caret (right when folded, down when open), its folded box, and that it starts folded on Molten
  Core (its painted title shows), Hall of Thanes and the Deadmines. Opened, the Party positions row's gold hint and
  its click (the first boss in focus, its positions on the map).
- The side panel's move steps (the Deadmines' 2, 5, 7): the small route-ringed stop disc beside the pulls' badges;
  no "The Deadmines" after every caption. Bosses: an ability's note starting under its name. The instance picker's
  search placeholder while it has the focus. The Runs section with recording on and no run yet.
- The Party section: the dungeon's party card (seat plates, role glyphs, "+", the right-click menu), the raid groups
  filling their column, the empty messages centred in their boxes, at the minimum width in Polish.
- Pulls: the two-line names' spacing, the pull's card. Run mode: no gap above the mini map on a one-line step. The
  Notes window: the page label between the 32 px arrows. `/dp debug`: one dialog with the font test in it.

- Raid pages: the braces of keywords in the editor's font; the inline raid, role and class icons in the Notes window
  (size, baseline); class colours; the ">" on the player's own lines; the window opening on a boss pull and closing at
  its end; Send to group as leader, assistant and member; pages arriving after a boss fight's lock; Post to chat
  drawing the raid icons; the Party switch and the pages editor at the minimum width in Polish.
- Run mode's drift line while recording, its tooltip and the click; the Runs section's Show dropdown and the compare
  table's colours.

- Drawing: strokes follow the pointer smoothly at several zooms; thick strokes have no gaps at sharp bends and no
  blobs on gentle curves; arrow heads; circles and boxes; text labels on their plates; the Move halo; the eraser
  dragged across several drawings; the right-click menu; the map starting a stroke over a pin; "Drawing is not
  available in combat."; the Drawings row's icon (`INV_Misc_Note_02`).
- Map toolbar: the tools' cursor pictures (size, centring, against the gold names), the names giving way to the
  pictures on a narrow window, the draw line on one line at the minimum width (880); the glyphs' lines (crisp at UI
  scales other than 1, the "T" in the title font), the disabled bin, the clear menu with a greyed-out item, tooltips
  beside the square buttons.
- Header: Undo and Redo after the plan menu at the minimum width.
- Pulls editor: the tag toggles wrapping, their lit state, the progress field; the marks in the steps' captions and
  in run mode (do they fit?).
- The colour-blind setting: map pins, routes, drawings, swatches, party role rings.
- Share: the Advanced caret pointing right when closed and down when open (`SetRotation`).
- Text cut after a whole word ("Dark Iron Summoner patrol...") in the steps, the pull list, run mode, the picker and
  dropdowns, with the whole text in the tooltip (`IsTruncated` decides; the offline lint measures with the bundled
  font).
- Map pins moved apart where they would cover each other (stop badges left of markers, pull discs right of bosses),
  and labels clear of the legend.
- Notes on a narrow window: the objectives under the bosses, the run buttons on two lines; the header bands behind
  Plan, Progress, Bosses, Objectives, Runs, Party and the Share sections, each on its heading's line.

- The window: the game's frame with the addon's logo in the portrait ring, the title in the title bar, the header row
  beside the ring (nothing under the ring), the close button; the rock warmed by the `page` tint; the inset panels'
  bevel and marble (too light or too dark?); the header band behind "Steps", "Party" and the Gear list's sections; the
  red panel buttons (Make an editable copy, dialogs); the minimal scroll bars in lists; the list hover and selection
  (`Options_List_*`); the menu panel behind dropdown lists; dialogs in the game's dialog border.
- The section tabs under the window: their spacing, the selected one, Polish names, and that a window near the bottom
  of the screen keeps them on screen; the home screen's Dungeons / Raids / My plans / Shared in the same place.
- Boss portraits on the first visit to Bosses, the side panel's boss steps and the map pins: the skull for about 2.5 s,
  then the face in place, without leaving the view (and no black squares). The wait starts when the plan is chosen
  (and when an instance is selected on the home table, or on entering it), so a raid's or classic dungeon's pins
  should rarely show the skull at all; a second view of the same boss shows the face at once.
- The Notes window's page arrows (the spell book's) and its default size; the Forever chip on the home table's rows;
  the orange (not red) level ranges and the Levels heading's tooltip; the Pulls list's two-line rows; the Party
  section's columns; the Notes section's boss rows (name over "not tracked").
- Gear: the item tooltip next to the item's name, the comparison tooltip beside it, not over "Open in NeedRoll" near
  the bottom of the screen.
- Header widths: back, instance and plan pickers, plan menu and Undo at the window's minimum width (880).
- The instance picker: opaque over the map (no pins or labels through or over it), the thumbnails' crop, the `Dungeon`
  and `Raid` marks on the tabs, the band dividers, the star and check, the level colours; arrow keys, Page Up / Down,
  Enter, Escape and Tab while the search field has focus; a click elsewhere closes it; header tooltips below their
  control. The plan dropdown and the other dropdowns: the same opaque list, arrow keys and Escape (out of combat).
- Gear with NeedRoll: "Open in NeedRoll" whole and bright; item tooltips beside the row, not over the button.
- The bottom bar at the minimum width: the status text gives way to the sections and Run mode.
- The side panel: step badges and titles, the current-step highlight, the party strip's role rings and names.
- Clicking a step: the map centres on it, keeps it clear of the floating legend, and dims the rest of the route.
- The home table and preview: thumbnails cropped from loading screens, the plate (emblem in the ring) for the
  instances without art, the facts row.
- Run mode: position saved across `/reload`, it reopens if it was open, Prev / Next and the pull key bindings, the
  mini map's art and centring, auto-advance on a boss kill (by encounter ID where known, else by name or instance).
- The Enemies layer with real spawn data: dot sizes, merging, tooltips, that bosses and named NPCs are not doubled.
- `Raid` atlas for the raid plate (falls back to an icon).
- The party strip's role glyphs (`groupfinder-icon-role-micro-*` or the `LFGRole` sheet) on their bronze-ringed
  plates; "Open" under empty seats.
- Run mode on a dungeon with a provider map: the framing at each step, the ring on the step, the step counter between
  Prev and Next, the "~" mark (plain ASCII: every face has it).
- Map labels on their plates over a provider map's painted names; the "Map: ..." chip in the corner. Hall of Thanes:
  the labels beside (not over) the painted room names (`keepOut` in `Data/ReyesMaps.lua`), the denser plates (0.86).
- Routes: the outlined line, the arrows' size, spacing and direction at several zooms and icon sizes, the joints at
  bends, the focused segment brighter than the rest, stop numbers readable over the line, and every option of the
  Routes settings. `Media/RouteArrow.tga` and `Media/RouteArrowEdge.tga` are new files: until the game is restarted
  the older chevron or arrow shape stands in (where the client reports that a texture failed).
- Everything from the previous list still applies: map tiles lining up with markers, boss portraits, Polish letters.

## Sources

Installed Forever addons were read (read-only) only to learn which Blizzard templates, textures, atlases and APIs
exist on this client; their layout, code and art were not copied. Dungeon Journal states no licence (all rights
reserved), NeedRoll is GPL v3, OpenMap is MIT. Feature ideas also came from Adventure Guide Forever and Shortest Path
Forever (GPL v3, CurseForge pages): numbered route stops with notes, a per-icon-type scale, layers that can be hidden.
