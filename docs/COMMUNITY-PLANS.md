# Community plans: submission guide

Addons cannot go online, so the community database is this repository's `community-plans/` folder. Players submit
plans as pull requests; CI validates them; releases (or anyone) can build "import packs" from them.

## File format (`*.dpplan`)

```
# Dungeon Planner community plan (format: docs/COMMUNITY-PLANS.md)
title: Deadmines - fast route
instance: The Deadmines (Forever)
author: YourName
client: forever 16001
license: CC0-1.0
tags: dungeon, speed
description: One line about what the plan is for.
---
!DP2!...the export string from Share > Export (older !DP1! strings work too)...
```

| Field | Required | Notes |
|---|---|---|
| `title` | yes | Should match the plan's name (CI warns otherwise) |
| `instance` | yes | The instance, as players know it |
| `author` | yes | Your name or handle; no e-mail addresses |
| `client` | yes | `forever 16001` today |
| `license` | yes | `CC0-1.0` (public domain) or `CC-BY-4.0` (credit the author) |
| `tags`, `description` | no | Free text |

## Where files go

`community-plans/<client>/<instance-slug>/<plan-slug>.dpplan`, e.g.
`community-plans/forever/the-deadmines/fast-route.dpplan`. Templates and examples live in `community-plans/examples/`.

## How to submit

1. In game: build the plan, then Share > Export this plan, click the box, Ctrl+C.
2. Create the file as above and paste the string after `---`.
3. Run `lua tools/validate_plans.lua path/to/your.dpplan` (needs Lua 5.1 from the repo root).
4. Open a pull request. CI runs the same validator.

## Rules

- **Only your own work.** Write the strategy yourself. Do not paste guides, maps or text from other sites, videos or
  addons (their authors own them). Boss and instance names come from the game by ID, so you need not type them.
- **No made-up game data.** Item IDs in gear lists must be real items you checked in game (drag the item into the
  Gear tab instead of typing IDs).
- **One plan per strategy.** Variants (difficulty, speed vs. safe) are separate files.
- A plan that the validator would trim (invalid parts) is rejected: export it again from the current version.

## Packs

`lua tools/build_pack.lua "Pack name" community-plans/forever/the-deadmines/*.dpplan > pack.txt` makes one string
players import in one go (Share > Import). `lua tools/discord_render.lua file.dpplan` previews the Discord text.
