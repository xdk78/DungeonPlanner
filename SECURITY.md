# Security policy

Dungeon Planner runs inside the World of Warcraft client and never goes online by itself. What it does take from other
people is untrusted, and that is where a security problem would be:

- **Import strings** (`!DP1!` / `!DP2!`, instance packs, `.dpplan` files): decoding, the bounded inflater, checksums
  and validation (`Share/Codec.lua`, `Share/Inflate.lua`, `Share/Checksum.lua`, `Model/Validate.lua`).
- **Addon messages** from other players: plan offers and transfers, raid pages, acknowledgements
  (`Share/Comm.lua`, `Share/Transfer.lua`, `Share/Acks.lua`, `Model/Pages.lua`).

The formats and their limits are described in [docs/SHARING-FORMAT.md](docs/SHARING-FORMAT.md).

## What to report

- A string or an addon message that makes the addon raise a Lua error, freeze the client, use unbounded memory or time,
  or fill SavedVariables without limit.
- Anything received that is shown or stored without validation: UI escape codes (`|T`, `|H`, `|c`) reaching the screen,
  text that imitates the game's or another player's messages, values that get past the limits.
- A way to make the addon accept a plan or a raid page the player did not agree to, overwrite a player's own plans,
  or send addon or chat messages the player did not ask for.
- Anything that executes received data as code. The addon never calls `loadstring` on input; a path that does is a bug.

## How to report

- Please report privately: on GitHub, **Security > Report a vulnerability** on this repository (a private security
  advisory). Include the string or the message that triggers the problem, or the steps, the addon version and the
  output of `/dp debug`.
- If private reporting is not available to you, open an issue that says only that you have a security report, without
  the details, and a way to reach you will be arranged there.
- Problems that only show a Lua error to the player who pasted a broken string themselves can go to the normal bug
  tracker.

There is no bounty. Reports are answered as time allows; a fix ships in the next release and is credited in the
changelog unless you prefer otherwise.

## Supported versions

Only the latest release is supported.
