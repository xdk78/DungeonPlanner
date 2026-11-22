# Translating Dungeon Planner

Dungeon Planner ships in English, German, Spanish, French, Polish and Russian. `deDE`, `esES`, `frFR` and `ruRU` are a
**machine-assisted first pass**: written with an AI model, checked by the offline tests, not reviewed by native speakers
yet. Corrections from people who play WoW in those languages are the most useful contribution you can make. `plPL` was
written for the Polish WoW community.

| File | Language | Notes |
|---|---|---|
| `enUS.lua` | English | The English text is the key. This file lists only internal names (`boss`, `slot:HEAD`, ...), plural rules and the language list |
| `deDE.lua` | Deutsch | |
| `esES.lua` | Español | Also used by `esMX` clients (neutral Spanish, no "vosotros") |
| `frFR.lua` | Français | |
| `plPL.lua` | Polski | Chosen by the player, or automatically with WoW Po Polsku (Polish has no client of its own) |
| `ruRU.lua` | Русский | Needs a Cyrillic face: see "Fonts" |

## Fix or improve a translation

1. Fork the repository and open `Locales/<code>.lua`. Each line is `["English text"] = "translation",`. Change only the
   part after the `=`; never the key in brackets.
2. Check your file (needs only a Lua 5.1 interpreter, no game):
   ```sh
   lua tools/locale_keys.lua Locales/deDE.lua
   ```
   It must say `0 missing, 0 unused, 0 with wrong format specifiers`.
3. Open a pull request. Say which language you speak natively and, if you can, what you saw in game (a string cut off,
   a term the official client words differently). A translation fix needs no in-game test.

You can also open a "Translation" issue with the string and your proposed wording; we will apply it.

## Rules for translators

- **Official terms first.** Use the words the WoW client of that language uses: Dungeon, Raid, Tank, Healer, Loot,
  Interrupt, Dispel, Crowd control, Group, Guild, the raid target icons, the equipment slots. Blizzard's own strings are
  in [BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) (`GlobalStrings`). Where the
  client has no word ("pull", "pack"), use what your community says.
- **Format specifiers** (`%s`, `%d`, `%d%%`) stay and keep their order. The check and the tests fail otherwise.
- **Plurals.** A key with `|` lists the forms of the English ("%d plan|%d plans"); your value lists the forms of your
  language, separated by `|`: two for German, Spanish and French (French uses the first for 0 and 1), three for Polish
  and Russian (1 / 2-4 / the rest; Russian also counts 21, 31, ... as 1 and 11-14 as the rest). The rules are in
  `Locales/enUS.lua` (`ns.PLURAL_RULES`, the one source: `tools/locale_keys.lua --all` and `tests/test_db.lua` read the form count from it), tested in `tests/test_journal.lua`. Keys with a bare number and a noun ("%d runs") are plural keys so Russian and Polish can decline them.
- **Keep it short.** The window has fixed-width buttons, tabs and columns. A word or two stays a word or two. The CI
  runs a layout lint for every locale (`lua tests/ui_dump.lua --out <dir> --locale deDE --prefix deDE/`): it fails on
  text that is cut off or overlaps. Prefer a shorter natural word over a smaller font.
- **French spacing.** The space inside « » and before ; : ! ? is a no-break space, written `\194\160` (U+00A0), so a
  guillemet or a colon never starts a line alone. The narrow no-break space U+202F is not used: the game's faces and
  the bundled font lack it.
- **Leave unchanged:** `/dp ...` commands, `Dungeon Planner`, the names of other addons, file names and API names,
  `{tank}`-style keywords. Boss, dungeon and item names are never in these files: they come from the game.
- **Fonts.** German, French and Spanish letters are in the game's own face. Russian uses the game's Cyrillic face
  (`FRIZQT___CYR.TTF`) and falls back to the bundled Alegreya Sans, which has Cyrillic (`UI/Fonts.lua`).

## Add a new language

The client has more languages than we ship (`itIT`, `ptBR`, `koKR`, `zhCN`, `zhTW`); Korean and Chinese also need a font
decision. To add one:

```sh
lua tools/locale_keys.lua --template itIT > Locales/itIT.lua   # every key, English as the value
```

Translate the values, then: list the file in `DungeonPlanner.toc` (after `Locales\ruRU.lua`, and add a
`## Notes-itIT:` line), add `{ "itIT", "Italiano" }` to `ns.LOCALE_LIST` and a rule to `PLURAL_RULES` in
`Locales/enUS.lua`, and run `lua tests/run.lua` and
`lua tools/locale_keys.lua --all`. Automatic language selection then picks the file for clients with that locale.

## When the English text changes

Every new `L["..."]` string needs a line in every file. CI names the keys a locale lacks (`missing: ...`) and fails
until they are there. To get the missing lines, English as the value, ready to translate:

```sh
lua tools/locale_keys.lua --missing-lines Locales/deDE.lua
```

If you cannot translate a language, put the English text in as the value and say so in the pull request; native
speakers fix those later.

## Why GitHub and not CurseForge's localization tool

CurseForge's translation tab and the packager's `@localization@` keywords fill locale files at package time from a
database on the site. That would leave the repository's locale files empty, so `lua tests/run.lua`, the coverage check
and the layout lint, which load the files offline, could not see the translations, and a translation fix would not be
reviewed in a pull request. Translations stay in this repository. The keys are the English texts, so the files can
be imported into CurseForge's tool later if that changes.
