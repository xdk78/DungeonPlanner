# Boss facts (`data-src/bosses`)

One JSON file per recommended plan (43: 35 dungeons, 8 raids), UTF-8, LF, named like the plan's file in
`data-src/dungeons/`. They hold the facts the addon bundles about each boss so the boss pages, portraits and run mode
work without another addon. The addon does not load them: `lua tools/gen_bosses.lua` turns them into compact Lua in
`Data/Bosses/` (and the block in `DungeonPlanner.toc`); `Data/BossData.lua` reads that.

Rules (docs/DATA-SOURCES.md has the credits):

- Facts only: IDs, numbers, names of things. Descriptions and strategies are never copied; the game supplies the text of
  spells (`C_Spell`) and items (`GetItemInfo`), so only the IDs ship. The only prose is a short `note` of our own on an
  ability, and quest titles.
- Every value names its source (`src`, an `id` of `sources[]`). A value that was inferred (a tag guessed from the
  game's ability wording, not stated by a source) says `"inferred": true`. A value no source gave is left out, never
  guessed; a boss with nothing at all carries a `gap` reason.
- Nothing is copied from addons or databases under a licence that forbids it (Questie, AtlasLoot, NeedRoll are GPL;
  ForeverDungeonJournal has no licence): they may be used to cross-check, never as a source.

## Schema (version 1)

```json
{ "schema": 1, "updated": "2026-11-16", "slug": "the-deadmines", "name": "The Deadmines", "kind": "dungeon",
  "origin": "classic",
  "sources": [ { "id": 1, "name": "Wowhead Classic", "url": "https://www.wowhead.com/classic",
                 "licence": "facts only (IDs, levels, drop lists)", "what": "..." } ],
  "bosses": [ { "point": "p6", "name": "Mr. Smite", "npcID": 646, "members": [643], "displayID": 2026,
                "level": [20, 20], "class": "elite",
                "abilities": [ { "spell": 6432, "tags": ["control"], "note": "Stuns the group twice; stay out of range.",
                                 "src": 2, "inferred": true } ],
                "loot": [ { "item": 7230, "notable": true, "forever": true, "src": 1 } ],
                "src": { "npcID": 1, "displayID": 1, "level": 1, "class": 1 },
                "gap": "only when the entry has no data at all" } ],
  "quests": [ { "id": 166, "name": "The Defias Brotherhood", "level": 22, "req": 14, "side": "alliance",
                "giver": 234, "items": [3637], "shared": true, "src": 1 } ],
  "keys": [ { "item": 16309, "name": "Drakefire Amulet", "kind": "attunement", "required": true,
              "quests": [6502, 6602], "note": "Every raid member needs it to enter.", "forever": true, "src": 3 },
            { "quest": 4182, "name": "Dragonkin Menace", "kind": "attunement", "required": true, "side": "alliance",
              "forever": true, "src": 3 } ] }
```

- `keys` (Prep's "Keys and attunements", at most 8): one of `item` (an item to carry; the client counts it) or `quest`
  (a quest to have done), its English `name` (the client's item name is shown when it has one), `kind` (`key` opens a
  door or entrance, `attunement` lets you in, `summon` calls or opens something optional), `required`, `side`,
  `quests` (the quests that give the item), `alt` (a quest key's other IDs, any of which counts: Naxxramas' attunement
  has one per Argent Dawn standing, 9121 Honored, 9122 Revered, 9123 Exalted; Molten Core's page gives 7487 in its
  infobox and 7848 in its links, both neutral), `group` (rows that are one key, such as Onyxia's amulet and the quests
  that start its chain: run mode counts a group once, and carrying its item settles it), a `note` of our own (at most
  160 characters), and `forever`: true only
  where a Forever page confirms it (Onyxia's Drakefire Amulet and Upper Blackrock Spire's Seal of Ascension on the
  wiki's World of Warcraft: Forever page; the Dalaran Sewer Key and Krol'dok Compound Key on their item pages); the
  classic keys are classic facts, shown with "(classic fact; not checked on Forever)". Researched on warcraft.wiki.gg
  item, quest and instance pages; left out: Aqual Quintessence and Alcaz Prison's Overseer's Keyring (no
  ID on an allowed page), the Krol'dok Ogre Key (no known use), the Scarab Coffer keys (loot chests, not doors), the
  Scarlet Key for Stratholme (no longer needed).

- `slug`, `name`, `kind`, `origin` equal the plan's (`data-src/dungeons/<slug>.json`); `updated` is the date the research
  changed. `sources` lists what the values come from (`licence` says what may be taken).
- `bosses` has one entry per boss point (`kind: "boss"`) of the plan, with the point's `id` (`point`) and `name`. A group
  fight (Twin Emperors, The Seven, ...) is one entry: `npcID` is the lead, `members` the others; its drops are merged.
- `npcID`, `displayID`: positive integers (`displayID` feeds `SetPortraitTextureFromCreatureDisplayID`). `level`:
  `[min, max]` or `"??"` (a skull level). `class`: `normal`, `elite`, `rareelite`, `worldboss`, `rare` (the game's
  `UnitClassification` names).
- `abilities`: at most 8, in the order a source lists them. `spell` is a spell ID. `tags` (any of `interrupt`, `dispel`,
  `tank`, `healer`, `enrage`, `deadly`, `bleed`, `control`, `aoe`, `adds`) say what a player should do or watch for;
  the UI shows them localised. `note` (at most 160 characters, plain text) is ours. Tags a source states (the wiki marks
  interruptible, dispellable, tank and healer abilities) are not `inferred`; tags derived from the wording of the
  game's own description are.
- `loot`: at most 16 item IDs, notable (epic) ones flagged `notable`. `forever: true` marks an item the Forever build
  adds to a classic boss.
- `quests` (dungeon quests): `id`, `name`, `level`, `req` (required level), `side` (`both`, `alliance`, `horde`), `giver`
  (NPC ID; the quest's start), `items` (objective items, only where a wiki page lists them: Forever's new dungeons), `shared` (the quest belongs to a zone with several plans, such as
  Scarlet Monastery's wings, and is listed under each). Raids list only attunement and key quests.

## Coverage and known gaps

Counts per field are printed by `lua tools/gen_bosses.lua --report`. The known gaps, by cause:

- **Forever's new dungeons** (9) and **Hyjal Summit**: Wowhead has a WoW: Forever section (`/forever/`) with a Dungeon
  Journal and one guide page per dungeon. The journal pages (30 instances) carry each boss's NPC IDs, ability spell IDs with
  flags (tank, healer, interruptible, magic/curse/poison/disease, enrage, bleed), drop lists, quest IDs, levels and sides,
  and mark what Forever added to or changed on a classic boss; the guide pages carry creature display IDs, quest givers,
  objective items and drop tables. The NPC, spell, item and quest database pages are behind a bot check and were not
  fetched. Not covered by Wowhead yet: Blackmaw Hold, Shaper's Terrace (no guide or journal page), Hyjal Summit, and
  Highland Horror and Zalfan Moonshadow (named in no page). Of the 58 bosses of the nine dungeons: 43 have an NPC ID (25
  before), 39 a display ID (0), 40 abilities (21), 44 drops (41); 19 have a level (unchanged: no Wowhead page states levels,
  the wiki does). No source gave a classification for them. Those still missing come from no source rather than a guess.
- **Wowhead's ability flags** (`flags` of the journal) become the tags `tank`, `healer`, `interrupt`, `deadly`, `enrage`,
  `bleed` and, for the four dispel types, `dispel`; they are stated by the source, so not `inferred`. Spells Wowhead lists
  for a boss come first, in its order; abilities only the wiki had follow.
- **Classic dungeons against Forever**: the journal marks drops and spells as new or updated. Boss-specific new drops (item IDs
  from 270000 up) were added with `forever: true`; the dungeon-wide pool of new items (IDs 251000-254999, listed under
  every boss of an instance) is not a per-boss drop and is not recorded. Changed (not new) drops and spells, and the many
  classic items the journal omits, are not touched: its lists are not complete for classic bosses, so it only adds.
- **Quest objectives**: classic dungeon quests list IDs, levels, sides and the giver (the NPC the quest page names as its
  start; none when it starts from an item or an object); objective items are left out there because the pages do not
  separate them from related items. Forever's new dungeons list the quests of the Wowhead journal and guides (IDs, names, sides,
  givers); objective items only where a guide spells them out.
- **Attunement and key items** are in `keys` (19 instances, 32 entries; `--report` counts them). Whether each classic key
  still works the same on Forever is not confirmed by a source, except the two raid attunements Forever's page names.
- Group fights keep the lead creature's display ID.

## Regenerating

```sh
lua tools/gen_bosses.lua            # writes Data/Bosses/<slug>.lua and the block in DungeonPlanner.toc
lua tools/gen_bosses.lua --check    # exits 1 on invalid JSON, a plan boss without an entry, or an out-of-date file (CI)
lua tools/gen_bosses.lua --report   # coverage per field, size
```
