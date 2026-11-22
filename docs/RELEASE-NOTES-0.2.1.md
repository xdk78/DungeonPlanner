# Dungeon Planner 0.2.1

A maintenance release of Dungeon Planner for **World of Warcraft: Forever**: the plan's bosses stay on the route on
other addons' maps, sharing and group sync say when the game blocks or refuses addon messages, and recorded runs are
kept per dungeon wing. The full list of changes is in [CHANGELOG.md](../CHANGELOG.md).

## What's new

- **Bosses stay on the route.** Where another addon's map places the bosses differently from the plan (Shaper's
  Terrace with Dungeon Journal 2.1.2 or later), the plan's bosses stay at the route's stops; the other addon's pins
  show only for bosses the plan does not place.
- **No more silent sharing failures.** During a boss fight's lockdown the Share section and run mode's group sync line
  say that the game is holding addon messages; when the game refuses messages they say so, and a refused plan offer
  fails at once instead of waiting. Outside a lockdown messages are no longer held when the game only reports them as
  restricted. `/dp debug` and `/dp report` show the game's answers and how many messages were sent and refused per
  channel.
- **Runs per wing.** In Scarlet Monastery, Dire Maul, Stratholme and Blackrock Spire a run is recorded for its wing
  once the game tells which wing it is (the floor map names it, or you kill a boss only that wing has). Each wing's
  Runs section, best time, splits and "previous run" use that wing's runs; clearing a wing's history keeps the others.
- **Smaller fixes**: "Open in NeedRoll" works for plans saved in another game language, an outdoor boss kill after
  leaving a dungeon no longer joins the dungeon's run, and run history keeps working past 60 instances.
- **Santiago Reyes' map credit** in the game names him and his site only; Blizzard's add-on policy keeps donation
  requests out of the game. The link to support him stays in the [README](../README.md#credits) and on CurseForge.

## Upgrade notes

- **Restart the game after updating**, not just `/reload`: 0.2.1 adds three files to the addon, and WoW reads an
  addon's file list only when the client starts. Until then run mode shows no recorder, drift or prep line, refused
  addon messages are not reported, and `/dp debug` lists the missing files with "restart the game after updating".
- **Your data carries over.** The saved data stays at schema 6; nothing is migrated. Runs recorded before 0.2.1 have
  no wing and show in every wing's Runs section, marked "wing unknown".
- **Going back to 0.2.0** keeps the runs 0.2.1 recorded for a known wing in the saved data, but 0.2.0 does not list
  them.
- **Sharing between 0.2.0 and 0.2.1 works**: the in-game protocol (2) and export strings (`!DP2!`) are unchanged, and
  group sync works across both versions.

## Known limitations on WoW: Forever

- **The game's "restricted" answer is unverified.** WoW: Forever 1.60.1 was reported to answer that outgoing addon
  messages are restricted outside encounters. Dungeon Planner sends anyway and reports refusals; whether party, raid,
  guild and whisper messages then arrive has not been checked in game. The vendored AceComm passes no refusal code, so
  `/dp debug` shows the code as "not given".
- **A wing is not always known at once.** Dire Maul has no floor maps and Stratholme's wings share theirs, so there a
  run takes its wing only at the first boss kill that belongs to one wing; until then it is "wing unknown".
- **Not yet verified in game**: the 0.2.1 changes below, and group sync between two clients. `/dp debug` lists what
  your client provides; please attach its output and `/dp report` to bug reports.
- The other limits listed for 0.2.0 still apply
  ([RELEASE-NOTES-0.2.0.md](RELEASE-NOTES-0.2.0.md#known-limitations-on-wow-forever)), except that recorded runs are
  now kept per wing.

## Test checklist

Out of combat unless the step says otherwise. Each line: what to do, then what to look for.

1. **Restart.** Update, then `/reload` only: `/dp debug` lists `UI/FontTest.lua`, `UI/RunLines.lua` and
   `Share/SendStats.lua` as missing, "restart the game after updating", and nothing errors. After a game restart they
   are present.
2. **Addon message status, in a party.** Share a plan with the party, then type `/dp debug` and `/dp report`: both show
   the game's lockdown and restriction answers and the sent and refused counts per channel (PARTY); no "refused" line
   in the Share section when the other player received the plan.
3. **Group sync, two clients in one party.** The leader clicks "Lead this run" and steps on: the member follows. Pull a
   boss and step on during the fight: the group sync line says "Addon messages are blocked by the game right now", and
   the member catches up when the fight ends. If `/dp debug` shows the restriction answer as true outside a fight,
   check that the member still follows.
4. **Shaper's Terrace with Dungeon Journal 2.1.2 or later.** Open the recommended plan: the boss markers sit at the
   route's stops, and a Dungeon Journal pin shows only for a boss the plan does not place.
5. **Wing runs in Scarlet Monastery.** With "Record my runs" on, run the Library, then the Armory: each wing's Runs
   section lists its own run, older runs show "wing unknown", and the best time and splits are the wing's own. Clear
   history on the Library: the Armory run and the "wing unknown" runs stay unless "Also clear runs without a known
   wing" is ticked.
6. **Wing runs in Dire Maul.** The run shows "wing unknown" until the first boss kill, then the wing of that boss; kill
   a boss of another wing in the same run: it goes back to "wing unknown".
7. **NeedRoll on a non-English client** (German, Spanish, French or Russian), with NeedRoll installed: open a
   dungeon's Gear section and click "Open in NeedRoll": NeedRoll opens once, on that dungeon.
8. **Map credit.** Hall of Thanes on Santiago Reyes' map: the "Map by Santiago Reyes" tooltip names him and his site,
   with no donation link; Settings > Appearance, under "Prefer drawn maps over the game's minimap pictures": the same.
9. **What's new.** Update from 0.2.0, restart and log in outside an instance: the 0.2.1 card shows once, with three
   highlights; `/dp new` shows it again.
