# Dungeon Planner 0.2.0

The second version of Dungeon Planner for **World of Warcraft: Forever**: four more interface languages, run mode that
follows the group's leader, a Prep section with directions to the entrance, every floor on the map and routes that
follow the corridors. The full list of changes is in [CHANGELOG.md](../CHANGELOG.md).

## What's new

- **Six interface languages.** German, Spanish, French and Russian join English and Polish. "Automatic" follows your
  game's language; the new languages are a machine-assisted first pass, and corrections from native speakers are
  welcome ([Locales/README.md](../Locales/README.md)).
- **Group sync in run mode.** The leader clicks "Lead this run"; members with the same plan follow the leader's step,
  can step on their own and rejoin, and a member without the plan asks for it in one click.
- **Prep.** Before you go in: the instance's quests and where they stand in your log, the keys and attunements it needs
  and whether you have them, your group's levels and missing roles, and your own prep notes.
- **Getting there.** The entrance's zone, area and coordinates, the nearest flight master and the way from it, boats,
  zeppelins and summoning stones, and outdoors a live map with your position. "Navigate" hands the entrance to
  Polestar, Shortest Path Forever or TomTom, else to the game's map pin. Walking in with the window open opens the
  plan and run mode, and entrances you use are learned. "Show location" in the header pins the entrance in one click.
- **Every floor on the map**, with a floor switcher in the map's corner (Shift + mouse wheel changes floor too), and
  stairs and portals that say where they lead.
- **Routes that read in order**: Snap to corridors in the route tool, a colour that shifts along each route, clearer
  arrows, the leg under the pointer highlighted, two lanes with the way back dashed where a route doubles back, and a
  Routes group in Settings for line and arrow styles.
- **Your group in the plan**: the party seats fill from the people you are grouped with, by role or a guess from the
  class, without saving anything.
- **Gear filters that filter**: a class or slot now narrows the drop list.
- **Map toolbar with icons**, the drawing tools on one line.
- **Report a problem** (`/dp report` or the `!` in the title bar), a **What's new** card after updates (`/dp new`), and
  an opt-in performance probe (`/dp perf`).

## Upgrade notes

- **Restart the game after updating**, not just `/reload`: 0.2.0 adds new files to the addon, and WoW reads an addon's
  file list only when the client starts, so without a restart parts of the addon are missing (the map draws no routes, and `/dp debug` says to restart).
- **Your data carries over.** Plans, settings and recorded runs need nothing from you. On the first login the saved
  data moves to schema 6 (it remembers which plan a received copy came from, for group sync, and keeps prep notes).
- **Going back to 0.1.0** after this update opens the newer data read-only, so the older version cannot lose what it
  does not know. Update again to edit.
- **Sharing between 0.1.0 and 0.2.0 works** (in-game protocol 2, export strings `!DP2!`). Group sync needs 0.2.0 on
  both sides; older versions ignore its messages. Routes drawn with Snap to corridors are ordinary route points and
  open in 0.1.0.

## Known limitations on WoW: Forever

- **No position inside instances.** The client gives addons no player or creature position inside an instance. The
  live map in Getting there works outdoors only; nothing is placed on the dungeon map from what you see in game.
- **Floor detection inside instances is not confirmed.** The map follows you to another floor only where the client
  says which floor you are on; on Forever that is not yet known. `/dp scan` inside a dungeon records what the client
  gives.
- **Class gear rules follow the current client.** The Gear class filter uses today's armour and weapon rules and does
  not model levels (for example mail before level 40, or plate). Whether Forever keeps the classic rules is part of the
  test below.
- **Shortest Path Forever**: the call Dungeon Planner makes is inferred from another addon's integration and not yet
  verified against Shortest Path Forever itself. Polestar and TomTom are read from their installed code; none of the
  three has been tried in game yet.
- **Not yet verified in game**: group sync between two clients, the gamepad interface style, the Russian Cyrillic font,
  the party strip with a real group, the Gear filters on Forever's rules, and the other items in the checklist below.
  The UI was checked offline in all six languages; `/dp debug` lists what your client provides. Please attach its output
  and `/dp report` to bug reports.
- **The plan on OpenMap's dungeon map is experimental** (off by default). It relies on the private parts of OpenMap 0.8.12 and 0.8.13 in its
  dungeon view, not on its public API, so it may stop working after an OpenMap update; `/dp debug` then says why
  ("OpenMap overlay: ...").
- **Wings of one instance** (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire) share one instance ID. A plan
  made inside one of them in another game language cannot tell which wing it is; it keeps the parchment instead of
  showing another wing's map, and `/dp debug` lists it. A plan for a wing made from the instance list, or copied from
  a recommended plan, knows its wing. Recorded runs are stored by instance ID, so a wing's Runs section lists the
  runs of every wing of that instance, and run mode counts a boss kill in any wing unless the client says which wing
  you are in.
- The limits listed for 0.1.0 still apply ([RELEASE-NOTES-0.1.0.md](RELEASE-NOTES-0.1.0.md#known-limitations-on-wow-forever)).

## Test checklist

Do these in order, out of combat unless the step says otherwise; the riskiest come first. Each line: what to do, then
what to look for.

1. **Group sync, two clients in one party, both on the same recommended plan.** The leader opens run mode and clicks
   "Lead this run": the member's run mode says "Following <leader>" and moves with the leader's Next / Prev; the
   leader sees the member as following, in run mode and in Share's "Has this plan" line.
2. **Group sync, stepping away.** The member clicks Next on their own: they show as out of sync for the leader;
   "Rejoin" snaps back to the leader's step.
3. **Group sync, ask for the plan.** The member switches to a plan the leader is not on (or deletes the copy): run mode
   says "Leader is on a plan you don't have: ask for it"; one click makes the leader's client offer the plan, and
   after accepting the member follows.
4. **Group sync, boss lockdown.** Pull a boss while leading and step on during the fight: no Lua error or blocked
   action; the member catches up when the fight ends, and a boss kill the member's tracker saw is not undone.
5. **Gamepad interface style.** Turn on the game's gamepad interface style and `/reload`: `/dp` does nothing, no freeze; the
   minimap button and a key binding open the window; the gamepad menus leave it alone; `/dp debug` from the Settings
   panel says "Gamepad interface style: on". Settings > Troubleshooting > "Gamepad interface style" On / Off overrides it.
6. **Russian.** Choose Русский in the language menu, `/reload`: every view in Cyrillic with no boxes (the separators
   are bullets), tabs and header fit; `/dp debug` lists the Cyrillic font. Repeat on Polski: ą ć ę ł ń ó ś ź ż show.
7. **`/dp scan` inside a dungeon with several floors** (the Deadmines or Blackmaw Hold), on two floors, then `/reload`.
   In the saved diagnostics, `position.bestMap` and `mapGroup`: does the client give a map there? If it does, the map
   switches to your floor.
8. **Snap to corridors.** On an own copy of the Deadmines, choose the route tool and click stops along a corridor: the
   first click on a floor starts the route, each next one draws a line along the corridor, not through walls;
   Shift-click draws a straight line. It should feel immediate on large floors.
9. **Floor switcher.** The Deadmines and Shaper's Terrace: tabs in the map's bottom-right corner; Lower Blackrock Spire
   and Blackmaw Hold: the name between arrows. Tooltips count markers; Shift + wheel changes floor; Scholomance's
   portal says "to <floor>" and a second click on its step goes there.
10. **Prep.** Open Prep on a dungeon with quests (Wailing Caverns) before and after accepting and abandoning one of
    its quests: the states change; keys (Scholomance, Upper Blackrock Spire) show whether you have them, also on the
    key ring or in the bank; in a party and a raid the group's levels and missing roles are right. Run mode shows the
    prep line on step 1, and a click opens Prep.
11. **Getting there and Show location.** From the home table's "Getting there" and the header's Show location: the
    zone and coordinates match the world map; a click on Show location sets the pin and opens the world map; right- or
    Shift-click opens Getting there; it is greyed in combat and while dead. Check one classic and one Forever dungeon,
    and the header at the minimum width in German.
12. **Navigate.** With Polestar installed: its arrow points to the entrance and "About n min" shows. With only TomTom:
    waypoints to the flight master and the entrance. With neither: the game's pin. The "..." menu lists every way;
    switching one off in Settings removes it.
13. **Live map and arrival.** Open Getting there outdoors and walk, ride and turn: the arrow follows your place and
    facing, the distance shrinks; it stops inside an instance. Walk into the instance with the window open: its plan
    and run mode open (in a non-English client too).
14. **Learned entrances.** Zone into a dungeon from its entrance, leave, open Getting there: the entrance is where you
    stood. A hearthstone or summon from far away teaches nothing; "Forget learned entrances" resets it.
15. **Party seats with a real group.** In a party from the group finder and in a hand-made party: members take their
    role's seats, a damage-only class sits in a damage seat, guesses are dimmer with a tooltip saying so; a member
    going offline or dying is dimmed and restored. A plan holding first names matches "First Surname" members.
16. **Gear filters on Wailing Caverns' recommended plan.** Warrior and Mage change the drop list (a mage loses leather
    and mail); a slot shows only that slot; "Loading items..." goes away. Then check Forever's rules: can a level-20
    hunter or shaman wear mail, a warrior or paladin below 40 wear plate, a rogue use one-handed axes, a druid use
    polearms? Report what the game allows.
17. **Map toolbar.** The tools show their pictures beside their names; on a narrow window only the pictures, names in
    the tooltips; the drawing line fits at the minimum width (880). In an own plan with no drawings, the clear menu's
    items are greyed out.
18. **Route look, hover and lanes.** Wailing Caverns: thin lines over a dark casing whose colour shifts from the
    route's colour at the entrance to its partner colour at the end (red through magenta to blue), stop numbers and
    arrows in the colour at their place, the legend swatch matching; where the route doubles back, two lanes with the
    way back dashed. Arrows evenly spaced, none on stops, bends or labels. Pointing at a leg highlights it while the rest
    dims to grey, not pink, with a tooltip naming its two steps; pointing at a step highlights its leg; run mode
    highlights its current leg. Check on parchment and on a dark minimap floor.
19. **Routes settings and the details panel.** Settings > Routes: width, opacity, outline, colour, "Colour along the
    route" (off: one colour) and the arrow options change the map and run mode at once; "Highlight the route under the
    pointer" off stops the hover. Click a marker with a long name: the details title stops before the close button,
    and hovering it shows the whole title.
20. **What's new.** Update from 0.1.0 (or clear `news` in the saved data), restart the game and log in outside an instance: the card shows
    once, after combat if you log in fighting; "Open Settings" goes to Routes; `/dp new` shows it again. A first
    install shows the welcome instead.
21. **`/dp report`** and the title bar's `!`: the text holds versions, plan and recent errors, no character, realm,
    guild or group names; "Short for Discord" fits one message.
22. **`/dp perf start`**, play for a minute, **`/dp perf`**, **`/dp perf stop`**: timings and memory are reported; after
    stop nothing is timed.
23. **Settings panel groups**: Appearance, Routes, Progress tracking, Data from other addons, Sharing, Raid pages and
    Troubleshooting show in all six languages; the Troubleshooting buttons (self-test, Forget learned entrances,
    Report a problem, Show what's new) each work.
24. **The plan on OpenMap's dungeon map (experimental), with OpenMap installed.** Right after a game restart, turn on
    "Show plan on OpenMap's dungeon map (experimental)" in OpenMap's menu, select the Deadmines' recommended plan,
    then click the Deadmines' entrance on OpenMap's world map: the route, numbered stops and markers show on that very
    first dungeon map. Zoom with the wheel and drag: they follow and stay inside the picture. Switch floors with the
    arrows, the floor list under the floor name and the side panel's floor pictures (after opening its Floors tab):
    the plan's other floor shows each time. Open it once inside a dungeon too. In combat, open, zoom and close the map:
    no Lua error or blocked action. `/dp debug` has an "OpenMap overlay:" line. With the gamepad interface style on,
    nothing is drawn and the switch is not in OpenMap's menu.
25. **A plan made in another game language.** On a German (or Spanish, French, Russian) client, stand inside the
    Deadmines and Hall of Thanes and make a New plan from the window: the map, the Enemies layer, the Bosses facts,
    Prep and Getting there are the recommended plan's, and the home table shows one card per instance. In Scarlet
    Monastery the new plan stays on the parchment (the client does not say which wing). `/dp debug` has an "Own plans
    matched" line and lists "Instance names by ID (present)" when `GetRealZoneText` is missing.
26. **Type `/dp shots` and wait about half a minute.** Every view is captured; put the useful screenshots in
    `docs/screenshots/`.
