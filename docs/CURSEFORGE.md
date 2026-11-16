# Dungeon Planner (CurseForge description, draft)

_The text below is the project description for CurseForge. Paste everything under the line._

---

**Plan your dungeon and raid runs in WoW: Forever, follow them while you play, and share them with your group.**

Dungeon Planner opens a war table for every dungeon and raid: the map of the instance fills the window, and the plan's
steps (entrance, pulls, bosses, quest givers, objectives) and your party sit beside it. Click a step and the map shows
it: its floor, its stretch of the route, the pull or boss, and where each role stands.

### Features

- **43 recommended plans** for the classic dungeons and raids and Forever's new dungeons: boss order, routes that follow
  the corridors, pulls, strategies and party positions. Make an editable copy to change one.
- **Your own plans**: markers, pulls with tags (interrupt, crowd control, line of sight, skip...), planned cooldowns
  and Bloodlust, routes with numbered stops, drawings and text on the map, boss strategies by phase, assignments, raid
  groups, raid pages and gear lists. Undo and redo for every change.
- **Run mode**: a small window to keep open in the dungeon with the current step, the next pull, tips for the next boss
  and a mini map. A boss kill moves it along; key bindings walk the steps.
- **Run recorder** (opt-in): your pulls, boss kills and wipes, splits against your best run, a run compared with the plan
  or with another run, and a plan drafted from a run.
- **Raid pages**: assignment pages per boss with raid icons, role icons, groups and class colours, shown in a small Notes
  window when the fight starts. The raid leader can send them to the group or post them to chat.
- **Sharing**: send a plan to your group, guild or a player (they accept or decline) and see who has it; export and import
  strings; Discord text.
- **Works with the addons you already have** (all optional, read in your game only): maps, boss portraits and loot from
  Dungeon Journal, routes and maps from Forever Dungeon Routes, maps from OpenMap, "Open in NeedRoll", quests from
  Questie, boss kills from DBM or BigWigs.
- English and Polish (automatic with WoW Po Polsku), a colour-blind setting, minimap button, key bindings, options in
  the game's Settings panel.

### Good to know

- WoW: Forever does not tell addons where you or any creature are inside an instance, so nothing is placed on the map
  from what happens in game; the run recorder works from combat, nameplates and boss kills.
- The Adventure Guide is disabled on Forever. Dungeon Planner uses the dungeon maps and pictures the client still has;
  Forever's new dungeons get a map, boss portraits and loot lists when Dungeon Journal (or OpenMap / Forever Dungeon
  Routes for maps) is installed.
- Plans stay on your computer; sharing sends only the plan you choose.

### Commands

`/dp` opens the planner, `/dp run` run mode, `/dp notes` the Notes window, `/dp settings` the options, `/dp debug` a
report of what your client provides (please include it in bug reports).

### Credits

Routes of the recommended plans come from Forever Dungeon Routes by Checkov23 (MIT); boss positions and instance data
from OpenMap (MIT); strategies are paraphrased from community dungeon guides. The Polish UI can use the bundled
Alegreya Sans font (SIL Open Font License). Full credits and licences are in the source repository.

Source, issues and the full changelog: https://github.com/xdk78/DungeonPlanner (MIT licence).
