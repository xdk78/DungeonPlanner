# Community plans

Plans shared by players, as `.dpplan` files: a short header and a Dungeon Planner export string. Import one in game
with `/dp import` (Share > Import): copy everything after the `---` line.

How to add yours, the file format and the rules: [docs/COMMUNITY-PLANS.md](../docs/COMMUNITY-PLANS.md).

| Folder | Contents |
|---|---|
| `examples/` | Templates showing the format (no game data) |
| `forever/<instance>/` | Plans for World of Warcraft: Forever (interface 16001) |

Every file is checked by CI (`lua tools/validate_plans.lua`). Plans are CC0-1.0 or CC-BY-4.0, as each file states.
