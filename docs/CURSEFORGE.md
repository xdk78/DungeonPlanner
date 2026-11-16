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
- **Hand-drawn maps of Forever's new dungeons** by Santiago Reyes, included with his permission.
- **Works with the addons you already have** (all optional, read in your game only): boss pins, portraits and loot from
  Dungeon Journal, routes from Forever Dungeon Routes, maps from OpenMap, "Open in NeedRoll", quests from
  Questie, boss kills from DBM or BigWigs.
- English and Polish (automatic with WoW Po Polsku), a colour-blind setting, minimap button, key bindings, options in
  the game's Settings panel.

### Recommended companion addons

Dungeon Planner works on its own, but reads extra data from these addons when you have them (in your game only; each
can be switched off in the settings):

- **Dungeon Journal** (recommended): boss pins on the maps of Forever's new dungeons, boss portraits, each
  boss's loot in the Gear tab, boss levels and a button to open it. https://www.curseforge.com/wow/addons/dungeonjournal
- **Forever Dungeon Routes** (recommended): its routes as an extra map layer.
  https://www.curseforge.com/wow/addons/forever-dungeon-routes
- **OpenMap**: further drawn dungeon maps, and your plans listed on its dungeon cards. https://www.curseforge.com/wow/addons/openmap
- **NeedRoll**: "Open in NeedRoll" in Gear. https://www.curseforge.com/wow/addons/needroll
- **QuestieDB** (with Questie): the dungeon's quests in the Runs tab. https://www.curseforge.com/wow/addons/questiedb
- **DBM** or **BigWigs**: a backup boss-kill signal. https://www.curseforge.com/wow/addons/deadly-boss-mods and https://www.curseforge.com/wow/addons/big-wigs
- **WoW Po Polsku Forever**: the Polish interface switches on automatically. https://www.curseforge.com/wow/addons/forever-wowpopolsku-2-0

### Good to know

- WoW: Forever does not tell addons where you or any creature are inside an instance, so nothing is placed on the map
  from what happens in game; the run recorder works from combat, nameplates and boss kills.
- The Adventure Guide is disabled on Forever. Dungeon Planner brings its own boss data (portraits, abilities, loot,
  levels, dungeon quests), draws the classic dungeons from the game's own files and Forever's new dungeons on Santiago
  Reyes' maps, so no other addon is needed. If Dungeon Journal or Forever Dungeon Routes is installed, their boss pins,
  routes and extra details are used too.
- Plans stay on your computer; sharing sends only the plan you choose.

### Commands

`/dp` opens the planner, `/dp run` run mode, `/dp notes` the Notes window, `/dp settings` the options, `/dp debug` a
report of what your client provides (please include it in bug reports).

### Credits

Maps of Forever's new dungeons: **Santiago Reyes** (https://sreyesmaps.com), from his "Atlas de Azeroth: Forever", used
with his permission; the maps are his and are not under the addon's MIT licence. Like his maps? Support the artist:
https://sreyesmaps.com/donaciones

Routes of the recommended plans come from Forever Dungeon Routes by Checkov23 (MIT); boss positions and instance data
from OpenMap (MIT); strategies are paraphrased from community dungeon guides. The Polish UI can use the bundled
Alegreya Sans font (SIL Open Font License). Full credits and licences are in the source repository.

Source, issues and the full changelog: https://github.com/xdk78/DungeonPlanner (MIT licence).
