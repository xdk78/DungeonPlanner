# Sharing format

Two ways to move plans: **export strings** (copy and paste: chat, forums, Discord, the community repository) and
**in-game transfers** (addon messages). Both carry the same export string. Format version 2 (plan format 4,
transfer protocol 2); version 1 strings still import. Plan formats 3 and 4 only add optional fields (map drawings, pull
tags, planned cooldowns, Bloodlust and progress; raid assignment pages), so the header stays `!DP2!`: an older Dungeon
Planner still imports a format 3 or 4 string and drops what it does not know (see "Format 3 and older readers").

## Export string

```
!DP2!<print-safe text>

print-safe text = LibDeflate:EncodeForPrint( raw DEFLATE( body ) )      alphabet a-z A-Z 0-9 ( )
body            = kind "\n" checksum "\n" payload
kind            = "plan" | "pack"   ("note": a raid page pushed in game, below; never imported)
checksum        = Adler-32 of payload, 8 lowercase hex digits
payload         = LibSerialize:Serialize(value)                         (LibSerialize v1 format)
```

`!DP2!` is the format version. Readers accept `!DP1!` (plan format 1, upgraded on import, see "Migration from
format 1") and `!DP2!`; a higher number is refused with "made by a newer Dungeon Planner", anything else with "not a
Dungeon Planner string".

Decoding, in order, each step with a limit:

1. Input at most 400 000 characters. Whitespace, quotes, back-ticks, Discord code fences and part markers (`[2/5]`)
   are removed, so several pasted Discord messages join into one string.
2. Everything after the header must be in the print-safe alphabet.
3. **Bounded inflate** (`Share/Inflate.lua`, RFC 1951) stops at 1 MiB of output: no decompression bombs.
4. The header must name a known kind, and the Adler-32 must match.
5. `LibSerialize:Deserialize` inside `pcall` (it never executes code; deep nesting fails with an error, caught).
   A pushed raid page (kind `note`) stops at 32 KiB instead: it arrives without a prompt.
6. `Validate.Plan` / `Validate.Pack` rebuild the plan field by field: unknown fields dropped, text cleaned of UI escape
   codes and control characters and cut to limits (UTF-8 safe), numbers range-checked, coordinates clamped to 0..1 and
   rounded to 4 places, ids checked and made unique, references (marker -> pull, assignment -> boss) repaired, list
   lengths capped. What was dropped is reported to the player. Ids in a string are at most 9 characters (a letter and
   up to 8 digits; saved plans may hold 12): the plan's counter continues after the highest id, and must stay within
   what a saved plan may hold.

Nothing in Dungeon Planner calls `loadstring`. Imported plans are added as new plans. The one exception is the
player's own choice: when a pasted plan has the name of one of their plans for the same instance, the import asks
"Keep both" (the default), "Replace mine" or "Cancel"; replacing overwrites that plan in place (the plan on the table
can be undone). Plans received in game never replace anything.

## Plan (payload of kind "plan"), format 4

Every field is optional on input; `Validate.Plan` fills defaults. IDs (`m12`, `u3`, ...) are a lower-case letter and a
number, unique within their list. Names are a fallback: display names come from the client by ID (each reader sees
their own language). Coordinates are 0..1 over the floor's map art (0,0 top-left), rounded to 4 places.

| Field | Type | Limits |
|---|---|---|
| `v` | int | plan format version: **4** (1 to 3 are read; readers ignore the number and check every field) |
| `id` | string | replaced on import |
| `name`, `author`, `difficulty` | string | 64 / 48 / 32 bytes |
| `description`, `notes` | string | 2000 / 8000 bytes, multi-line |
| `created`, `updated` | int | Unix time |
| `tags` | list of string | 8 x 24 bytes |
| `instance` | `{ name, kind = "dungeon"/"raid"/"other", origin?, ejInstanceID?, uiMapID?, levelMin?, levelMax? }` | IDs are the client's; levels 1-200 (v2), max never below min; `origin` (v2, optional) is `"forever"` for an instance new in WoW: Forever or `"classic"`, anything else is dropped |
| `floors` | list of `{ uiMapID?, name }` | 16 |
| `markers` | list of markers (below) | 500 |
| `routes` | list of `{ id, name, floor, color 1-8, optional?, points }` (below) | 20 routes, 200 points each |
| `pulls` | list of `{ id, name, note, color 1-8, tags?, cd?, lust?, progress? }` (order = pull order; below) | 100 |
| `encounters` | list of `{ id, name, custom?, ejEncounterID?, dungeonEncounterID?, strategy, phases = { { name, trigger, notes } } }` | 40 bosses, 12 phases |
| `assignments` | list of `{ id, target, task, encounter?, phase?, marker? }`; `target` = player name, `role:TANK|HEALER|DAMAGER`, `group:1..8` or `all` | 400 |
| `groups` | 8 lists of player names | 5 each; a dungeon plan's party uses groups 1-3 by role (1 tank, 2 healer, 3 damage) |
| `gear` | list of `{ id, itemID?, label, note, slot?, class?, role?, encounter?, priority 1-5 }` | 300 |
| `objectives` | list of `{ id, text, encounter? }` | 100 |
| `origin` | `{ bundled = "<recommended plan id>", rev? }` (v2) | set on copies and exports of a recommended plan |
| `rev` | int (v2) | data revision of a recommended plan |
| `drawings` | `{ v = 1, shapes = { shape, ... } }` (v3, optional; below) | 150 shapes, 50 per floor, 40 points per stroke |
| `pages` | `{ v = 1, list = { page, ... } }` (v4, optional; below) | 20 pages, 3000 bytes of text each |
| `nextId` | int | next free id number |

A pack (`kind = "pack"` in the header) is `{ name, description, plans = { plan, ... } }` with at most 50 plans.

### Markers

`{ id, floor, x, y, kind, label, note, icon 0-8, pull?, encounter?, role?, npcID?, itemID?, questID?, toFloor? }`

| `kind` | Meaning | Map layer |
|---|---|---|
| `boss` | a boss (link `encounter` to show its journal portrait) | Bosses and rares |
| `rare` | a rare or optional elite | Bosses and rares |
| `pack` | a group of enemies (link `pull`: drawn in the pull's colour with its number) | Packs and patrols |
| `patrol` | a patrolling enemy or group (draw its path as an optional route if needed) | Packs and patrols |
| `loot` | loot on the ground or a notable drop (`itemID` optional) | Loot and chests |
| `chest` | a chest | Loot and chests |
| `quest_item` | a quest item or objective to pick up (`questID`, `itemID` optional) | Quests and NPCs |
| `quest_npc` | a quest giver or quest target (`npcID`, `questID` optional) | Quests and NPCs |
| `npc` | any other NPC: vendor, repair, friendly (`npcID` optional) | Quests and NPCs |
| `interactive` | something to click: lever, door switch, brazier, key item | Quests and NPCs |
| `entrance`, `exit` | the instance's way in / out (`toFloor` optional) | Entrances, exits and shortcuts |
| `shortcut` | a skip, jump-down or one-way path (`toFloor` optional) | Entrances, exits and shortcuts |
| `stairs` | stairs, lift or passage to another floor (`toFloor`) | Entrances, exits and shortcuts |
| `hazard` | a trap, fire, fall or anything to avoid | Hazards |
| `position` | a party position; `role` = `TANK`, `HEALER`, `MELEE` or `RANGED` | Party positions |
| `note` | free text on the map | Notes |

- `role` is kept only on `position` markers. A position with `encounter` shows while that boss is in focus on the map,
  one with `pull` while that pull is in focus; one with neither always shows.
- `toFloor` (1..number of floors) is kept only on `entrance`, `exit`, `shortcut` and `stairs`.
- `npcID`, `itemID`, `questID` are the client's IDs (shape-checked integers; an item link is accepted for `itemID`).
  Names and icons are read from the client at display time; never ship names instead of IDs.
- `icon` is a raid target mark 1-8 (0 = none), drawn in the pin's corner.

### Pull marks (format 3, optional)

| Field | Type | Meaning |
|---|---|---|
| `tags` | list of strings | any of `interrupt`, `cc` (crowd control), `los` (line of sight), `next` (pull with the next), `skip`, `careful`; each once, in that order; unknown tags are dropped |
| `cd` | `true` | the group's big cooldowns are planned on this pull |
| `lust` | `true` | Bloodlust / Heroism is planned on this pull |
| `progress` | int 0-100 | planned enemy forces (or a checkpoint) in percent after this pull; run mode shows it |

Planning only: nothing is detected from combat. Absent fields mean "no".

### Drawings (format 3, optional)

`drawings = { v = 1, shapes = { shape, ... } }`, left out when a plan has none. `v` is the drawing format: a reader that
gets a higher `v` drops the whole field (and says so in the import report) instead of guessing; the rest of the plan
imports.

`shape = { id, floor, kind, color 1-8, width 1-3, pts, text?, author?, pull?, encounter? }`

| Field | Meaning |
|---|---|
| `id` | `d<n>`, from the plan's id counter like every other id |
| `kind` | `pen` (freehand polyline), `line`, `arrow` (head at the second point), `circle` (the ellipse inside the box of its two points), `rect` (two opposite corners), `text` (one point: the label's centre) |
| `pts` | flat list `{ x1, y1, x2, y2, ... }`, normalized 0..1 on the floor's map art like markers, rounded to 3 decimals; `pen` 2-40 points (strokes are simplified with Ramer-Douglas-Peucker before they are stored), `line`/`arrow`/`circle`/`rect` 2, `text` 1 |
| `color` | the pull palette index, so the colour-blind setting recolours drawings too |
| `width` | thin, medium, thick (for text: its size) |
| `text` | the label (`text` only), up to 64 bytes, cleaned like every text |
| `author` | who drew it (a player name), optional |
| `pull` / `encounter` | the pull or boss it belongs to: run mode shows it with that step; one of the two at most |

Validation drops a shape with an unknown kind, a bad or duplicate id, too few points, an empty text or a non-number
coordinate, cuts a stroke at 40 points, and drops shapes beyond 50 on a floor or 150 in all. Links to a pull or boss
that does not exist are cleared.

### Raid assignment pages (format 4, optional)

`pages = { v = 1, list = { page, ... } }`, left out when a plan has none. `page = { id, title, encounter?, text }`:
`id` is `n<number>` from the plan's id counter; `title` up to 64 bytes; `encounter` the plan boss the page belongs to
(a missing one is cleared); `text` up to 3000 bytes, multi-line, cleaned like every text (UI escape codes removed).
Keywords stay in the text as written and are expanded only when a page is shown or posted (docs/ARCHITECTURE.md, Raid
pages): `{star}` ... `{skull}` and `{rt1}`-`{rt8}`, `{tank}` `{healer}` `{dps}`, `{group N}`, class tokens. A reader that
gets a higher `v` drops the whole field and says so in the import report. A page with neither title nor text, a bad or
duplicate id, or one over the cap is dropped.

### Format 3 and older readers

Format 3 adds only optional fields, so:
- a format 3 or 4 string imports in an older Dungeon Planner (same header `!DP2!`): `Validate.Plan` there keeps only
  the fields it knows, so drawings, pull marks and pages are dropped and the rest of the plan arrives;
- every older string (`!DP1!`, `!DP2!` without the new fields) imports unchanged here;
- saved data moves to schema 3 and then 4 (`Config/DB.lua` migrations 3 and 4, nothing converted), so an older version
  opens it read-only instead of loading it and losing the drawings or pages on its next save.

### Routes

`{ id, name, floor, color 1-8, optional?, points = { point, ... } }`. A route is a path drawn in its colour with
direction arrows, in point order. `optional = true` draws it fainter (a skip or an alternative).

A point is `{ x, y }` (a bend of the path) or a numbered **stop**: `{ x, y, step = n, note?, pull? }` with `step`
1-999, `note` up to 120 bytes ("Pull here, wait for the patrol") and `pull` naming the pull taken at that stop. Stops
are drawn as numbered badges; the editor renumbers them 1, 2, 3 ... in path order, so data should do the same. A bend
carries no `note` or `pull` (they are dropped).

### Migration from format 1

| Format 1 | Format 2 |
|---|---|
| kind `mob` | `pack` |
| kind `objective` | `interactive` |
| an unknown kind | `note` (as in format 1) |
| everything else | unchanged |

`Validate.Plan` applies this to every plan it reads (saved, imported `!DP1!` strings, received, bundled), so format 1
data never needs converting by hand. Saved data moves from schema 1 to 2 (`Config/DB.lua` migration 2), after which an
older Dungeon Planner opens it read-only instead of turning the new kinds into notes. Transfers use protocol 2; an
offer between protocol 1 and 2 is refused with a message to use an export string instead.

## Recommended plans (bundled)

Read-only plans that ship with the addon, shown as "Recommended plan" with "Make an editable copy". Data files (for
example `Data/Plans/*.lua`, generated from `data-src/`) are listed in the TOC after `Model/Bundled.lua` and call:

```lua
local _, ns = ...
ns.Bundled.Add({
	id = "example-standard", -- [A-Za-z0-9_-], at most 40 characters, unique among bundled plans
	rev = 1, -- bump when the data changes
	name = "Standard clear",
	author = "Dungeon Planner",
	description = "...",
	instance = { name = "Example Dungeon", kind = "dungeon", ejInstanceID = 1, uiMapID = 1, levelMin = 17, levelMax = 26 },
	floors = { { uiMapID = 1, name = "" } },
	pulls = { { id = "u1", name = "First pack", color = 1 } },
	encounters = { { id = "e1", ejEncounterID = 1, dungeonEncounterID = 1, strategy = "..." } },
	markers = {
		{ id = "m1", floor = 1, x = 0.42, y = 0.31, kind = "pack", pull = "u1", label = "Miners", note = "..." },
		{ id = "m2", floor = 1, x = 0.47, y = 0.28, kind = "position", role = "TANK", encounter = "e1" },
		{ id = "m3", floor = 1, x = 0.50, y = 0.92, kind = "entrance" },
	},
	routes = {
		{ id = "r1", floor = 1, color = 1, points = { { 0.50, 0.90 }, { 0.42, 0.31, step = 1, pull = "u1", note = "..." } } },
	},
})
```

Generated recommended plans also carry `updated`, the date of their research data (`"updated"` in each
`data-src/dungeons` file, written as Unix time at 00:00 UTC); the plan picker's tooltip and the Notes section show it
with the revision and the source.

The IDs in the example only show the shape; real data uses the client's IDs. The table is the plan format above plus
`id` and `rev`. Every field goes through `Validate.Plan` on first use; a plan that fails is skipped and named by
`/dp debug`, together with anything that was dropped. Plans are matched to an instance by `ejInstanceID`, else the
name (case, punctuation and a leading "The" ignored), else `uiMapID`, and in game to the client's Adventure Guide the
same way (docs/ARCHITECTURE.md, "The Adventure Guide resolver"), so data written outside the game may carry only some
of them. A plan's `name` says what it is ("Full clear", "Boss route", "Boss order"); the UI adds "(recommended)".
In game a bundled plan has the id `b:<id>`; copies and exports carry `origin = { bundled = id, rev }`.

The files in `Data/Plans/` are generated from `data-src/dungeons/*.json` by `tools/gen_plans.lua` (see
[DATA-SOURCES.md](DATA-SOURCES.md)). Format 2 has no field for "estimated", so the generator writes "(approx.)" at the
end of the note of every estimated marker and route stop, and the plan's own `notes` begin with a line saying it is
community-researched, positions are approximate, and how confident the research is. Points without coordinates are not
markers: bosses stay as encounters, and other things are lines in `notes`. On the map, the Adventure Guide's boss pins
are shown for every boss a recommended plan (or a copy of one) does not place itself, matched by encounter ID, name or
nearly the same spot.

## In-game transfer (protocol 2)

Prefix `DungeonPlanner`, sent with AceComm-3.0 (which splits long messages and paces them with ChatThrottleLib).
Fields are joined with `^`.

| Message | Meaning |
|---|---|
| `H^<proto>^<version>` | Hello to the group (at most once a minute, never in combat or a lockdown) |
| `h^<proto>^<version>` | Hello reply, whispered |
| `O^<proto>^<tid>^<bytes>^<sum>^<kind>^<name>` | Offer: transfer id (`[a-z0-9]{1,8}`), size of the export string, its Adler-32 |
| `A^<tid>` / `D^<tid>` / `X^<tid>` | Accept / decline / cancel |
| `P^<tid>^<export string>` | The payload, sent only after an accept |
| `N^<proto>^<note string>` | A raid page pushed to the group by its leader or a raid assistant (below) |
| `K^<tid>^<plan id>^<version>` | Ack, whispered to the sender after a received plan was imported (below); `-` for no plan id |
| `R^<proto>^<session>^<seq>^<plan id>^<version>^<step>^<pull>` | Run state of a leader's run mode (group sync, below); plan id `-` ends the lead |
| `F^<proto>^<session>^<status>` | A member's follow status, whispered to the leader (group sync) |
| `Q^<proto>` | Who leads the run? (to the group; group sync) |
| `W^<proto>^<session>` | A member asks the leader for the plan it leads (whispered; group sync) |

Flow: the sender offers (to a player by whisper, or to the group/guild channel). Each receiver whose setting allows the
sender (default: group and guild) gets a prompt, out of combat; Escape or 90 s without an answer declines. A whispered
offer sends the payload on accept; a group offer sends it once to the channel 6 s after the first accept, and only
players who accepted keep it. A member who accepts after that (the prompt waits for the end of combat) is whispered
their own copy, once. The receiver checks length and checksum, then decodes as above.

Limits: payload at most 96 000 characters (larger plans: use Export); at most 3 open prompts; per-sender flood limit
(20 messages per 10 s); offers with another protocol number are refused with a message to export instead. While the
game reports an addon-message lockdown, outgoing messages wait in an outbox. Each transfer is an explicit state machine
(`Share/Transfer.lua`), unit-tested offline.

### Who has the plan (acks)

After importing a plan from an in-game transfer, the receiver whispers `K^<tid>^<plan id>^<version>` to the sender:
the transfer id, the plan's id and its `updated` time as they were in the payload (a recommended plan's id is
`b:<id>`). Once per transfer, never for packs, through the outbox (a lockdown holds it) at ChatThrottleLib's BULK
priority. The sender takes it only for one of its own open transfers, from a player that transfer went to (a
whisper's target; for a group offer a member of the group or someone who accepted), or, for a transfer it no longer
knows (a reload since), for a plan it has, from a member of its group, with a version the plan has reached. Anything
else is ignored; the per-sender flood limit applies. It keeps, per plan and character, each member's newest version (`char.shareAcks`, 30
plans, 40 names each). The Share section shows "Has this plan: N of M group members, outdated: X, unknown: U": an ack
with the plan's current `updated` has it, an older one is outdated, a member whose hello was seen but who sent no ack
has not imported it yet, and everyone else is unknown (trial accounts cannot send addon messages; other clients and
players without the addon never answer). Older Dungeon Planners neither send nor read `K`, so their players show as
unknown or not yet.

### Raid pages pushed to the group

`N^<proto>^<note string>`, to the group channel, no prompt. The note string is an export string of kind `"note"`
(`Codec.EncodeNote`) whose payload is `{ title, text, boss?, enc?, plan? }`: the page's title and text with `{group N}`
written out as the plan's names (the receivers have no plan), the boss's name and encounter ID (the `ENCOUNTER_START` ID,
so the page opens on that pull), and the plan's name. At most 12 000 characters; `Codec.DecodeNote` checks it like any
string and `Pages.ValidatePush` rebuilds it. `Codec.Decode` (imports) refuses kind `"note"`.

- **Sender:** only the group's leader, or in a raid an assistant (`UnitIsGroupLeader`, `UnitIsGroupAssistant`).
- **Receiver:** setting "Accept pages from": the leader and raid assistants (default), anyone in the group, or nobody;
  the sender's rank is read from the receiver's own roster. Kept per character (`char.notes.received`, the last 10; a
  page with the same title from the same sender replaces the older one); the Notes window opens on it.
- During an addon-message lockdown (boss fights) the message waits in the outbox; the per-sender flood limit applies.
- Older Dungeon Planners ignore `N` messages (an unknown tag), so the protocol number stays 2.

### Group sync for run mode

The group's leader (in a raid also an assistant) clicks "Lead this run" in run mode; members who have the same plan
then see "Following <leader>", and their run mode shows the leader's step (and with it the next pull and the boss in
focus). `Share/Sync.lua` is the state machine (`Sync.Step(state, event, now)` -> effects; modes idle, leading,
following, free, mismatch), `UI/RunSync.lua` the glue.

| Message | Fields |
|---|---|
| `R^<proto>^<session>^<seq>^<plan id>^<version>^<step>^<pull>` | `session`: the lead's id (`[a-z0-9]{1,8}`, new each time a lead starts); `seq`: 1 up, per session; `plan id`: the leader's (`b:<id>` for a recommended plan), or `-` when the lead ends (the other numbers are then 0); `version`: the plan's `updated`; `step`: run mode's step, 0 before the first (0-999); `pull`: the next pull's number (0-100, 0 none). To the group; whispered as the answer to `Q` |
| `F^<proto>^<session>^<status>` | `status`: `f` following, `u` stepping on their own, `m` does not have the plan, `o` has another version. Whispered to the leader when it changes, and once for each new session |
| `Q^<proto>` | Sent to the group by a member whose run mode opens (or who joins) while nobody's lead is known; at most every 30 s. The leader whispers its `R` back (at most every 5 s per member) |
| `W^<proto>^<session>` | "Ask for it": whispered to the leader, at most every 20 s. The leader offers its plan by whisper, the normal transfer with its prompt (at most once a minute per member) |

- **Sending:** on change only. A state goes out at once when the last one left at least 1 s ago; changes within that
  second go out as one message when it ends (a timer event). Nothing is sent while the step, pull and plan stay the
  same; there is no heartbeat. All four go through the outbox at ChatThrottleLib's NORMAL priority: during a lockdown
  (a boss fight) a newer `R` replaces the one still waiting, so the fight's end sends one current state.
- **Trust:** every message is taken only from a member of the group (the receiver's own roster). `R` only from the
  group's leader, or in a raid an assistant; while one is followed, another one takes over only when the first is no
  longer trusted, or when the group's leader takes over from an assistant. A roster change that demotes the followed
  leader ends following; a leader who loses the rank ends the lead. `F` and `W` only for the current session. Every
  field is range-checked in `Transfer.Parse`; anything malformed is dropped. The per-sender flood limit applies.
- **Order:** within a session, a state whose `seq` is not above the last one is stale and ignored; a new session
  starts its own count (the leader reloaded or led again).
- **Which plan:** the member's plan with the leader's id at that version (a recommended plan, the same account), else a
  copy received or imported from it (`global.shareLinks`, written by every import: the sender's id and version, and
  the copy's own `updated`; a copy edited since is another version). None: "Leader is on a plan you don't have: ask
  for it"; only other versions: "Leader is on another version of this plan: ask for it". Once the offered plan is
  imported, the member follows.
- **Boss kills:** each client's tracker moves run mode past a killed boss as before. On a follower that move starts a
  10 s hold in which an older step from the leader (its state from before the kill, held in the fight's lockdown) does
  not pull the member back; the leader's state at or past the kill ends the hold, and when the hold ends with the
  leader still behind, the leader's step wins.
- **Free:** Prev / Next, a step clicked or another plan chosen while following means "step on your own": the member
  stays free until "Rejoin", which goes to the leader's current step. Following moves the step only while run mode is
  open; opening it shows the leader's current step.
- **Display:** run mode's line under the plan's name (leading: "Leading: N of M following · out of sync: X", with each
  member in its tooltip; following; free; mismatch with "Ask for it"), and the Share section's "Has this plan" line
  adds "following: N, out of sync: X" while you lead that plan. A member without a report counts as out of sync when
  their ack is for an older version, else as no answer.
- **Older versions:** Dungeon Planner 0.1.0 parses `R`, `F`, `Q` and `W` as nothing (unknown tags) and drops them, so
  the protocol number stays 2. Its players show as "no answer".
