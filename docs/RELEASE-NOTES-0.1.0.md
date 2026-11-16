# Dungeon Planner 0.1.0

The first public version of Dungeon Planner for **World of Warcraft: Forever**: plan dungeon and raid runs on the
game's own maps, follow them while you play, and share them with your group. The full list of changes is in
[CHANGELOG.md](../CHANGELOG.md).

## Highlights

- **A war table for every dungeon and raid.** The map fills the window; the plan's steps and your party sit beside it.
  Click a step and the map shows it: its floor, its stretch of the route, the pull or boss and where each role stands.
- **43 recommended plans** for the classic dungeons and raids and Forever's new dungeons, with boss order, routes that
  follow the corridors, pulls, strategies and party positions. Make an editable copy to change one.
- **Plan your own**: markers, pulls with tags and planned cooldowns, routes with numbered stops, drawings and text on
  the map, boss strategies, assignments, raid groups, raid pages and gear lists. Undo and redo cover every change.
- **Run mode**: a small window to keep open in the dungeon with the current step, the next pull, the next boss's tips
  and a mini map. A boss kill moves it along.
- **Run recorder** (opt-in): your pulls, kills and wipes, splits against your best run, and how a run went against the
  plan.
- **Sharing**: send a plan to your group and see who has it, export strings, Discord text, raid pages for the group.
- **Works with the addons you have**: maps and portraits from Dungeon Journal, routes from Forever Dungeon Routes, maps
  from OpenMap, loot links to NeedRoll, quests from Questie, kills from DBM or BigWigs. All optional.
- **English and Polish**, with WoW Po Polsku detected automatically.

## Known limitations on WoW: Forever

- **No mob positions.** The client does not tell addons where you or any creature are inside an instance. The
  Enemies layer shows only what the plans' research placed (bosses and some packs, approximate); nothing is placed
  from what you see in game, and the run recorder cannot put pulls on the map.
- **The Adventure Guide is disabled on Forever.** There are no journal bosses, portraits, loot tables or dungeon maps
  in the client. Dungeon Planner uses the old dungeon map tiles and loading screens the client still has; Forever's
  new dungeons use Dungeon Journal's or Forever Dungeon Routes' drawn map when installed, else the game's own minimap
  pictures in the classic maps' parchment colours (Dalaran's Underbelly and Hyjal Summit: a parchment grid
  unless Dungeon Journal, Forever Dungeon Routes or OpenMap is installed). Boss
  portraits show a skull, and the Gear section lists only the plan's own gear, unless Dungeon Journal provides them.
- **Run recorder limits.** It sees combat segments, enemy nameplates (counts, levels, elite or rare), boss kills and
  wipes. It cannot tell which pack a pull was or whether two packs came as one, so pulls are compared with the plan by
  order between boss kills, and "step ~ 6" is an estimate. Names the game hides are not stored; deaths may show as
  "not available".
- **What needs other addons.** Maps of Forever's new dungeons, boss portraits and loot lists: Dungeon Journal (or
  OpenMap / Forever Dungeon Routes for maps). Another addon's route layer: Forever Dungeon Routes. "Open in NeedRoll":
  NeedRoll. Quests in the Runs section: Questie. Kill tracking works without any of them.
- **Sharing needs this version on both sides** (in-game sharing protocol 2). Export strings of earlier test builds
  still import.
- **Not tested in game yet** in every combination: the checklist below is the first in-game test. `/dp debug` lists what
  your client provides; please attach its output and `/dp scan` (written on `/reload`) to bug reports.

## Test checklist

Do these in order, out of combat unless the step says otherwise. Each line: what to do, then what to expect.

1. **Log in with only Dungeon Planner enabled and type `/dp debug`.** A dialog lists the client, the APIs and "Window
   parts from the game: n of m"; the self-tests pass and the Polish letters (ą ć ę ł ń ó ś ź ż) are not boxes.
2. **Type `/dp`.** The window opens in the game's framed look with the addon's logo in the portrait ring; the close button
   and the size grip in the corners are fully visible, not under the metal border.
3. **Click the Dungeons, Raids, My plans and Shared tabs under the window, then hide and show the window twice.** Each
   tab keeps its width and padding; the table shows level ranges, plan counts and loading-screen pictures (a drawn
   plate where the game has none).
4. **Open the instance picker in the header, type "dead", use the arrow keys and Enter.** The list filters, one highlight
   moves with keys and pointer, Enter opens the Deadmines; a click outside closes the list.
5. **On the Deadmines' recommended plan, look at the map.** The old dungeon map tiles line up with the markers, labels
   sit on dark plates, the route has chevrons and numbered stops.
6. **Click three steps in the side panel.** The map moves to each step's floor, brightens its route segment and shows
   the party positions for it.
7. **Drag the map around for a few seconds, then zoom with the wheel.** Panning is smooth; when you let go, labels
   rearrange clear of the legend.
8. **Click Make an editable copy, choose the Marker tool and click the map; then Undo and Redo.** A marker appears,
   Undo removes it, Redo brings it back.
9. **Right-click "Delete pull" in the Pulls section and right-click a dialog's button.** Nothing happens; only left
   clicks act.
10. **Choose the Draw tool and draw a pen stroke, a circle and a text label; then enter combat (attack a training
    dummy) and drag on the map.** Drawings appear over the map art and under the pins; in combat the drag pans the map
    and chat says once that drawing is not available.
11. **Out of combat, click Clear floor in the drawing tools; with the confirmation open press Escape once, then
    again.** The first Escape closes only the confirmation (nothing is cleared); the second closes the planner.
12. **Open the planner, open a dropdown (the plan picker or Focus) and press Alt+Z twice.** The UI hides and returns
    with the list still open and working; nothing else changed.
13. **In Notes, type an objective, click somewhere else, then press Enter; type another and click Add.** Clicking away
    adds nothing and keeps the text; Enter and Add each add one objective.
14. **Open Gear on a dungeon with Dungeon Journal installed.** Its drops show per boss with quality colours; an item's
    tooltip opens next to its name and the comparison tooltip beside it, not over "Open in NeedRoll".
15. **Open Bosses, the side panel and the map of Hall of Thanes.** Boss portraits show a skull for about 2.5 s, then the
    face in place (with Dungeon Journal), never a black square.
16. **Switch the language to Polski in the settings button's menu and `/reload`.** Every view is Polish with all
    letters; the tabs under the window fit; Settings > Language back to Automatic follows WoW Po Polsku.
17. **Turn on "Colour-blind friendly colours" in the settings.** Pulls, routes, drawings and party role rings change to
    the new palette everywhere at once.
18. **Open Run mode (`/dp run`), use Prev / Next and the Next pull key binding, `/reload`.** It shows the current
    step, the next pull and boss, a mini map framing the step; after `/reload` it is where you left it. Escape does not
    close it.
19. **Switch on Record my runs, enter a dungeon and kill a pack and a boss.** Run mode shows "Recording" with the pull
    count and "On plan · step ~ n"; the boss kill moves past the boss's step; the Runs section lists the run.
20. **With a second player in the group, Share > Send in game; the other player accepts.** They get a prompt (it waits
    for the end of combat), the plan arrives as a new plan, and Share shows "Has this plan: 1 of 1".
21. **On the receiving side, press Alt+Z while the prompt is open, then Alt+Z again, then Escape.** The prompt survives
    hiding the UI; Escape declines it and the sender sees the decline.
22. **As raid or party leader, write a raid page for a boss in Party > Pages and click Send to group, then Post to
    chat.** Members' Notes windows show the page with raid icons, role icons and names in class colour; chat shows the
    page with its raid icons.
23. **Pull a boss that has a page.** The Notes window opens on the pull and closes when the fight ends.
24. **Type `/dp shots` and wait about half a minute.** The window walks through every view and takes a screenshot of
    each; chat lists the files' order. Put the useful ones in `docs/screenshots/`.
