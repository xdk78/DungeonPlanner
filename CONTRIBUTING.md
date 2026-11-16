# Contributing

Thanks for helping. Three kinds of contributions are welcome:

1. **Community plans** - see [docs/COMMUNITY-PLANS.md](docs/COMMUNITY-PLANS.md). No coding needed.
2. **Translations** - copy `Locales/plPL.lua` to your language, translate the values, add it to the TOC, and check it
   with `lua tools/locale_keys.lua Locales/xxXX.lua`.
3. **Code** - bug fixes and features. Read [AGENTS.md](AGENTS.md) first (layout, rules for the Forever client, tests).

## Workflow

1. Open an issue for anything larger than a small fix, so we agree on the approach.
2. Fork, branch from `main`, keep commits focused.
3. Before pushing:
   ```sh
   lua tests/run.lua
   lua tools/locale_keys.lua Locales/plPL.lua
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
