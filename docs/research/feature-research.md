# Dungeon Planner: feature research

Date: 2026-11-16. Scope: what players want from dungeon and raid planning addons, with emphasis on WoW: Forever (Interface 16001).

## Method and limits

Standard web search plus direct page fetches (GitHub issues, CurseForge listings, Blizzard forum, warcraft.wiki.gg).
Search engine recall for WoW-specific Reddit threads was poor: no r/wow, r/classicwow or r/CompetitiveWoW thread was retrievable, and the CurseForge comment pages for MDT could not be read (the page only reports a comment count of 352).
Evidence below is therefore weighted toward MDT's GitHub tracker, CurseForge listings and Blizzard's own notes. Anything not directly sourced is marked **(inferred)**.

## 1. Findings

### 1.1 What Forever's API allows and forbids
- Midnight's addon restrictions, including secret values, apply in Forever; Forever shares the Retail UI architecture. [Patch 1.60.1 API notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes)
- Combat log events are not available to addons; a Forever forum thread says custom combat-reading helpers and aura trackers are limited to what Blizzard exposes. [Blizzard forum: Forever Addons](https://us.forums.blizzard.com/en/wow/t/forever-addons/2374159)
- Creature GUID server-ID and spawn-ID parts are obfuscated (stable within a session) to prevent layer detection. Addon messages from trial accounts are blocked. [Patch 1.60.1 notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes)
- Blizzard's design intent: addons may display and customise, but not "know" combat state or decide for the player. [Warcraft Tavern on the Midnight addon policy](https://www.warcrafttavern.com/wow/news/ion-hazzikostas-addresses-midnights-addon-apocalypse-again/)
- The patch notes do not mention saved variables, C_Map or instance info as changed. Planning, notes, drawing and sharing are out-of-combat features and are not targeted by the restrictions **(inferred)**.

### 1.2 What exists for Forever
CurseForge Forever listings include several planners and journals: a route/pull planner based on MDT data, quest-per-dungeon helpers, a dungeon atlas/raid planner inside a guild hub addon, a gear planner (pre-BiS/BiS with drop alerts), journal plus BiS addons, and a stats addon with a dungeon tracker and pull planner. Many are marked beta. Sources: [CurseForge search](https://www.curseforge.com/wow/addons/search?search=dungeon+planner&gameVersion=forever), [Forever Stats](https://www.curseforge.com/wow/addons/forever-stats).

Forever Stats records runs pull by pull and gets combat numbers from the built-in damage meter because it cannot use the combat log; it notes some hidden data is simply missing. It also offers an overlay of the plan on the run and optional group sharing via addon messages. This is the closest direct competitor to Dungeon Planner's recorder. Frost Tools: Dungeons (Retail listing) tracks progress by forces delta because per-kill combat log access was removed, and shows a drift warning, Bloodlust detection and planned-Bloodlust marking. [Frost Tools](https://www.curseforge.com/wow/addons/frost-tools-dungeons)

Forum users in the Forever thread name Dungeon Journal (on-demand loot and quest info), Questie (praised for group quest progress, criticised as incomplete on Forever), and Details (preferred over the built-in meter). [Blizzard forum](https://us.forums.blizzard.com/en/wow/t/forever-addons/2374159)

### 1.3 MDT: what it offers and what users asked for
MDT feature set: maps with NPC positions and patrols, enemy forces bar, enemy info (crowd control, spells), drawing and note tools, route management with paste strings, in-game sharing, and Live mode for cooperative editing. [CurseForge](https://www.curseforge.com/wow/addons/mythic-dungeon-tools), [GitHub](https://github.com/Nnoggie/MythicDungeonTools)

Requests visible in the tracker (titles/paraphrase only):
- Show who is editing in live mode (#119, open): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/119).
- Counter/tooltip for how many party members imported a linked route when pugging (#613, open): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/613).
- Text written directly on the map, for example percentage break points, because the author used a second-screen website for at-a-glance guidance (#556, closed as done 2026): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/556).
- Mark Bloodlust on specific pulls, 9 upvotes (#414, closed as done 2026): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/414).
- Notes and role assignments attached to objects (doors, bots, orbs) and pull notes/tags (BL timing, cooldowns, interrupts); delivered by 2026 (#154): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/154).
- Colorblind-friendly colours (#147), automatically colour new pulls (#114), coloured pull numbers (#175), drag-and-drop pull reordering (#36), clear-all-drawings confirmation after a user lost work and undo could not recover it (#100). Closed list: [issues](https://github.com/Nnoggie/MythicDungeonTools/issues?q=is%3Aissue+color+OR+note+OR+undo+OR+performance).
- Frequent bug reports around notes (errors inserting or reordering notes), live sessions breaking the addon (#430), routes deleted by an update (#197), and dungeon data accuracy (non-existing packs, mapping improvements). These are the most-commented issues. [most commented](https://github.com/Nnoggie/MythicDungeonTools/issues?q=is%3Aissue+sort%3Acomments-desc)

### 1.4 Raid tools
- Method Raid Tools: reminders from a timeline/assignments, shared note, raid groups, raid check (food/flask), loot history, timers bridged to BigWigs/DBM; several modules are Classic-only. [CurseForge](https://www.curseforge.com/wow/addons/method-raid-tools)
- Angry Assignments: per-boss assignment pages, multiple editors with conflict notice, permissions (only accept from approved leaders), raid-icon/role/class/spell icons in text, group keyword to highlight your own line, auto-hide in combat. [CurseForge](https://www.curseforge.com/wow/addons/angry-assignments)
- Viserio/Liquid notes, BigWigs/DBM note integrations and Keystone helpers: could not be retrieved in this session; no claims made.

### 1.5 MDT drawing: what is known
- Toolbar with drawing and note tools; the toolbar moved to the side in 5.1.9 and a user asked where it went (#620): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/620).
- Line drawing is made of segments with circles at joints; an optimisation issue about only drawing joint circles above an angle threshold and hit-testing by geometry instead of frame mouseover was closed in 2026 (#113): [issue](https://github.com/Nnoggie/MythicDungeonTools/issues/113). Implication **(inferred)**: freehand strokes built from many frames are costly and hard to select.
- Users lost work by accidental "clear all" (#100); a confirm dialog was added.
- Users wanted real text on the map (#556), now added.
- Exact tool list (freehand, line, arrow, circle, eraser) and storage format were not confirmed from sources; storage is part of the exported preset string (**inferred**).

## 2. Prioritised recommendations

Value / feasibility on Forever / effort. "Feasible" means it uses only static data, UI, saved variables and addon messages.

| # | Feature | Value | Feasibility | Effort |
|---|---|---|---|---|
| 1 | Map drawing (see 3) | High | Feasible | M |
| 2 | Per-pull notes, tags and cooldown/Bloodlust markers | High | Feasible | S |
| 3 | Pull/step notes shown in Run Mode (text on map, percent break points) | High | Feasible | S |
| 4 | Import-status of shared plans (who has it) | Medium | Feasible | S |
| 5 | Live session: editor attribution and conflict notice | Medium | Feasible | M |
| 6 | Progress/drift tracking via forces or kill counts, no combat log | High | Partial | M |
| 7 | Plan overlay on recorded run and run comparison | Medium | Feasible | M |
| 8 | Raid assignment pages with group keywords, permissions | Medium | Feasible | M |
| 9 | Colorblind palette and pull colouring options | Medium | Feasible | S |
| 10 | Undo/redo and confirm on destructive actions | Medium | Feasible | S |
| 11 | Gear list drop alerts and BiS pre-BiS integration | Medium | Partial | M |
| 12 | Raid encounter timeline with reminders | Low | Partial | L |

Details:

1. **Map drawing.** Evidence: MDT ships it, with open usability history (#100, #113, #556). Players use it to mark skips, LoS spots, break points. Feasible: purely client-side canvas on a frame; no restricted API.
2. **Per-pull notes and markers.** Evidence: #154 and #414 (9 upvotes). Bloodlust and cooldown timing are asked for by pug players. Planned-only; do not detect casts on Forever (Frost Tools detects BL on Retail, which may be limited by secrets on Forever; treat as **inferred**, test before promising).
3. **Notes on map and in Run Mode.** Evidence: #556 (second-screen use shows players want guidance in the addon). Run Mode already exists, so this fits.
4. **Import tracking.** Evidence: #613. Feasible by addon messages to the group; trial accounts cannot send addon messages, so show "unknown".
5. **Live editing polish.** Evidence: #119, #430. Sending ops with author id and a last-writer notice is cheap; guard against loops and large payloads.
6. **Combat-log-free progress.** Evidence: Frost Tools and Forever Stats both use workarounds (forces delta, built-in damage meter). Partial: per-kill detail is not available; GUID parts are obfuscated, so do not key data on spawn IDs.
7. **Overlay and comparison.** Evidence: Forever Stats offers plan overlay and compares runs. Dungeon Planner already records pulls and splits.
8. **Raid assignments.** Evidence: Angry Assignments features. Display-only, shared text works within restrictions; the pre-pull note is outside combat. Auto-hide in combat is cheap.
9. **Colorblind palette.** Evidence: #147, #114, #175.
10. **Undo and confirmations.** Evidence: #100 and note-related bug reports (**inferred** that complex editing needs undo).
11. **Gear drop alerts.** Evidence: Forever Gear Planner pitch. Alerts on loot messages are chat-based; partial because Forever may restrict some chat/loot data **(inferred)**.
12. **Encounter timelines with reminders.** Evidence: Method Raid Tools reminders. Impossible to trigger from boss events (no combat log); only manual or pull-timer based. Low value, large effort; prefer linking to the built-in boss warnings.

## 3. Map drawing: concrete design

- **Tools:** freehand pen, straight line, arrow, circle/ellipse, rectangle, text label, eraser, plus select/move. Colour swatch row (8 colours, one colourblind-safe set), 3 line widths.
- **Data model:** per floor, a list of shapes in normalised map coordinates (0-1). Freehand stored as simplified polylines (Ramer-Douglas-Peucker, quantised to 2-3 decimals); circle/line/arrow stored as 2 points; text as point plus string. Per-shape id, colour, width, optional author and optional pull/step link.
- **Rendering:** one pooled `Line` texture per segment from a shared pool; draw arrow heads as two extra segments. Merge collinear points and skip joint circles on shallow angles (the issue #113 lesson). Cap shapes per floor and points per stroke to keep strings small.
- **Editing:** click to select by geometric distance rather than frame mouseover; delete and recolour selected shape; undo/redo stack (50 steps); "clear floor" and "clear all" both ask for confirmation (#100).
- **Sharing:** include drawings in the existing import/export string and in-game share, behind a versioned field so older clients ignore them. Live sessions send shape operations (add, move, delete) with author name.
- **Run Mode and layering:** draw layers toggleable; optional "link to pull" so a drawing only shows on that step; one-click hide in Run Mode to reduce clutter.
- **Restrictions:** none relevant; all inputs are mouse and saved variables.

## 4. Candidates to remove or simplify

These are judgement calls, mostly **inferred** from the evidence rather than directly requested:
- 43 bundled recommended plans: keep, but show source and date; stale routes are a recurring complaint category in MDT (data accuracy was the most-commented issue type).
- Discord export: low evidence of demand in the researched sources; keep only if cheap, hide behind advanced options.
- Features requiring combat data (live damage/DPS in the recorder): not possible on Forever. Competitors fall back to the built-in damage meter. Keep what you can compute from forces, deaths, timers and kill counts, and show "not available" instead of zeros.
- Per-spawn identification: obfuscated GUID parts; avoid features depending on them.
- Run mode: players like a minimal at-a-glance view (#556 shows people already run a second-screen site). Keep it compact; avoid adding every panel to it.

## 5. Open gaps
- Reddit and CurseForge comment text was not accessible; sentiment about MDT's drawing quality is based on the issue tracker only.
- Viserio/Liquid notes, BigWigs/DBM note integrations and Keystone helpers were not researched from sources.
- Forever-specific behaviour (for example whether chat/loot events carry secrets) needs testing on a Forever client.

## Sources
- https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes
- https://us.forums.blizzard.com/en/wow/t/forever-addons/2374159
- https://www.warcrafttavern.com/wow/news/ion-hazzikostas-addresses-midnights-addon-apocalypse-again/
- https://github.com/Nnoggie/MythicDungeonTools (issues 100, 113, 119, 154, 414, 556, 613, 620 and lists)
- https://www.curseforge.com/wow/addons/mythic-dungeon-tools
- https://www.curseforge.com/wow/addons/method-raid-tools
- https://www.curseforge.com/wow/addons/angry-assignments
- https://www.curseforge.com/wow/addons/frost-tools-dungeons
- https://www.curseforge.com/wow/addons/forever-stats
