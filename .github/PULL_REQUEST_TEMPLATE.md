## What changes

## Why

## Checklist
- [ ] `lua tests/run.lua` passes; new logic has tests
- [ ] `luacheck .` is clean
- [ ] New UI strings are in every file in `Locales/` (`lua tools/locale_keys.lua --all`; `--missing-lines Locales/xxXX.lua` prints what a file lacks). English as a placeholder is fine if you cannot translate: say so below
- [ ] Any new client API is guarded and listed in `docs/COMPATIBILITY.md` and `Core/Compat.lua`
- [ ] Format or wire changes update `docs/SHARING-FORMAT.md` (and bump the version there)
- [ ] `CHANGELOG.md` has a line under Unreleased
- [ ] Community plans only: `lua tools/validate_plans.lua` passes; no game data copied from other sites without permission

What was tested in game (or "not tested in game"):
