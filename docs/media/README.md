# Media

The GIFs the README and the CurseForge description show. They are **offline renders**: `tests/ui_dump.lua` builds each
interaction in the mock client (views named `seq-<name>-NN`, one per frame), the wow-ui-harness `render` command draws
them with the game's own textures, and `tools/make_gifs.py` crops, captions and optimises them (about 720 px wide, well
under 3 MB each). They are approximations of the client, not in-game footage. The steps to remake them are in
AGENTS.md, "Seeing the UI"; the captions and crops are in `tools/gif_sequences.json`.

| File | Shows |
|---|---|
| `steps.gif` | clicking steps in the list: the map follows |
| `runmode.gif` | run mode, Next, Next |
| `route.gif` | drawing a route on your own copy |
| `picker.gif` | searching the instance picker |
