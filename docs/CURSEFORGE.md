# Dungeon Planner (CurseForge description)

_The text below is the project description for CurseForge. Paste everything under the line._

---

**Plan your dungeon and raid runs in WoW: Forever, follow them step by step while you play, and share them with your group.**

Dungeon Planner turns every dungeon and raid into a war table: the instance map fills the window, the plan's steps and
your party sit beside it. Click a step and the map jumps to it: the right floor, that stretch of the route, the pull or
boss, and where each role should stand.

> **Beta.** Everything works offline in tests, but the addon is new. Please report anything odd on GitHub and include
> the output of `/dp debug`.

### Highlights

- **43 ready-made plans** for every classic dungeon and raid and all 9 new Forever dungeons: boss order, routes along
  the corridors, pulls, strategies and party positions. Make an editable copy to tweak one.
- **Run mode**: a small window to keep open while you play. Shows the current step, the next pull and the next boss's
  key abilities, with a mini map. Boss kills move it forward; key bindings walk the steps.
- **Works on its own**: no other addon needed. Maps, boss portraits, abilities, loot, levels and dungeon quests are
  built in.

### Everything else

- **Your own plans**: markers, pulls with tags (interrupt, CC, line of sight, skip…), planned cooldowns and Bloodlust,
  routes with numbered stops, freehand drawing and text on the map, boss strategies by phase, party assignments and raid
  groups, gear lists. Full undo and redo.
- **Raid pages**: assignment notes per boss with raid icons, role and group tokens and class colours. They pop up in a
  small Notes window when the fight starts; the raid leader can send them to the raid or post them to chat.
- **Run recorder** (opt-in): pulls, boss kills and wipes, splits against your best run, a run compared with the plan or
  another run, and a new plan drafted from a run.
- **Sharing**: send a plan to your party, guild or a friend (they accept or decline) and see who has it; import and
  export strings; ready-to-paste Discord text.
- **Comfort**: English and Polish, colour-blind palette, minimap button, key bindings, options in the game's Settings
  panel.

### Good to know

- WoW: Forever does not tell addons where you or any creature are inside an instance. Nothing is placed on the map
  automatically; the run recorder works from combat, nameplates and boss kills.
- The Adventure Guide is disabled on Forever, so Dungeon Planner brings its own boss data and draws every dungeon from
  the game's files and bundled maps.
- Your plans stay on your computer. Sharing sends only the plan you choose.

### Optional companion add-ons

All optional; Dungeon Planner reads them in your game only and each can be switched off in its settings.

- **Dungeon Journal**: extra boss details and its own maps. https://www.curseforge.com/wow/addons/dungeonjournal
- **Forever Dungeon Routes**: its routes as an extra map layer. https://www.curseforge.com/wow/addons/forever-dungeon-routes
- **OpenMap**: another map source; your plans appear on its dungeon cards. https://www.curseforge.com/wow/addons/openmap
- **NeedRoll**: an "Open in NeedRoll" button in the Gear tab. https://www.curseforge.com/wow/addons/needroll
- **Questie / QuestieDB**: dungeon quests in the Runs tab. https://www.curseforge.com/wow/addons/questiedb
- **DBM** or **BigWigs**: a backup boss-kill signal. https://www.curseforge.com/wow/addons/deadly-boss-mods ·
  https://www.curseforge.com/wow/addons/big-wigs
- **WoW Po Polsku Forever**: switches the interface to Polish automatically.
  https://www.curseforge.com/wow/addons/forever-wowpopolsku-2-0

### Commands

`/dp` opens the planner · `/dp run` run mode · `/dp notes` the Notes window · `/dp settings` options · `/dp debug` a
report of what your client supports (please include it in bug reports).

### Credits

- **Forever dungeon maps by Santiago Reyes**, used with his permission. If you enjoy them, please support his work:
  [sreyesmaps.com/donaciones](https://sreyesmaps.com/donaciones).
- Recommended routes from **Forever Dungeon Routes** by Checkov23 (MIT); boss positions and instance data from
  **OpenMap** (MIT); boss facts from Wowhead and warcraft.wiki.gg; strategies written in our own words from community
  guides.
- Bundled font: Alegreya Sans (SIL Open Font License).

Full credits and licences, source code, issues and changelog:
[github.com/xdk78/DungeonPlanner](https://github.com/xdk78/DungeonPlanner) (code under the MIT licence; the bundled
maps keep their own terms).
