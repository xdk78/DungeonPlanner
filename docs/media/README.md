# Media

The GIFs the README and the CurseForge description show. They are **offline renders**: `tests/ui_dump.lua` builds each
interaction in the mock client (`wowui.views` sequences: views named `seq-<name>-NN`, one per frame), the
wow-ui-harness `render` command draws them with the game's own textures, and its `gif` command crops, captions and
optimises them (720 px wide, under 3 MB each). They are approximations of the client, not in-game footage. The steps to remake them are in
AGENTS.md, "Seeing the UI"; the captions, crops and timing are in `tools/gif_sequences.json` (the harness's sequence
spec format).

| File | Shows |
|---|---|
| `steps.gif` | clicking steps in the list: the map follows (Scarlet Monastery: Library, on the game's old map tiles) |
| `runmode.gif` | run mode, Next, Next |
| `route.gif` | drawing a route on your own copy |
| `picker.gif` | searching the instance picker |

## Licence

The images in this folder are not covered by the repository's MIT licence. They are screenshots or renders of the
addon that include Blizzard Entertainment game art (the game's textures, map tiles and interface pieces, (c) Blizzard
Entertainment), and they are shown for documentation only. The tooling that makes them (`tests/ui_views.lua`,
`tools/gif_sequences.json`, and wow-ui-harness) is MIT.

They use a classic dungeon on the game's own map tiles, not Santiago Reyes' maps.
