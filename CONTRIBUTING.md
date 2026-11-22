# Contributing

Thanks for helping. Three kinds of contributions are welcome:

1. **Community plans** - see [docs/COMMUNITY-PLANS.md](docs/COMMUNITY-PLANS.md). No coding needed.
2. **Translations** - German, Spanish, French and Russian are a machine-assisted first pass and want native speakers'
   corrections; Polish is hand-written; more languages are welcome. Edit `Locales/<code>.lua` and send a pull request,
   or open a "Translation" issue. [Locales/README.md](Locales/README.md) has the rules (official WoW terms, plural
   forms, keeping texts short) and the one command that checks a file. No game and no coding needed.
3. **Code** - bug fixes and features. Read [AGENTS.md](AGENTS.md) first (layout, rules for the Forever client, tests).

## Workflow

1. Open an issue for anything larger than a small fix, so we agree on the approach.
2. Fork, branch from `main`, keep commits focused.
3. Before pushing:
   ```sh
   lua tests/run.lua
   lua tools/locale_keys.lua --all   # every locale has every key (new strings: --missing-lines Locales/xxXX.lua)
   luacheck .
   ```
4. Add a line to `CHANGELOG.md` under the newest, unreleased version.
5. Open a pull request with the template filled in, including what you tested in game.

## Bug reports

Use the bug template. Include the output of `/dp debug` and any Lua error (BugSack is the easiest way to copy one).
Remove character, realm and account names from anything you paste. Problems with imported strings or received plans
that could harm other players: see [SECURITY.md](SECURITY.md) first.

## Conduct

This project follows a short [code of conduct](CODE_OF_CONDUCT.md).

## Code style

Tabs for indentation, LF line endings, 120-character lines where practical (`luacheck` allows 160). Comments explain
why, not what. Lua 5.1 only: no `goto`, no integer division, no `utf8` library.

## Licence

By contributing code you agree to license it under the MIT licence of this project. Community plans are submitted
under CC0-1.0 or CC-BY-4.0 as declared in each file.
