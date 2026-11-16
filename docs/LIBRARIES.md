# Embedded libraries

(Data sources for the recommended plans are listed separately in [DATA-SOURCES.md](DATA-SOURCES.md).)

Vendored in `Libs/` at pinned versions and loaded by `embeds.xml`. The repository runs in game straight from git, the
offline tests load the same files, and the BigWigs packager ships them as they are (`.pkgmeta` has no externals).
`tools/fetch_libs.sh` re-fetches every pin; the versions below must never be lower than the copies other addons ship
on the target client (docs/COMPATIBILITY.md section 4). LibStub keeps the highest minor any addon loads.
The licence of each library, and where its text is, ships with the addon in `Libs/THIRD-PARTY-NOTICES.md`.

| Library | Version (LibStub minor) | Source | Licence | Used for |
|---|---|---|---|---|
| LibStub | 2 | Ace3 | Public domain | Library versioning |
| CallbackHandler-1.0 | 8 | WoWUIDev/Ace3 @ `ac3d122` (master, 2026-10-28) | Ace3 licence (BSD-style, `Libs/Ace3-LICENSE.txt`) | Public API events |
| AceAddon-3.0 | 13 | Ace3 @ `ac3d122` | Ace3 | Addon lifecycle (OnInitialize / OnEnable) |
| AceEvent-3.0 | 4 | Ace3 @ `ac3d122` | Ace3 | Game events |
| AceTimer-3.0 | 17 | Ace3 @ `ac3d122` | Ace3 | Mixed into the addon object |
| AceConsole-3.0 | 7 | Ace3 @ `ac3d122` | Ace3 | `/dp`, `/dplan` |
| AceDB-3.0 | 40 | Ace3 @ `ac3d122` | Ace3 | SavedVariables with profiles |
| AceDBOptions-3.0 | 17 | Ace3 @ `ac3d122` | Ace3 | Profile page in the options |
| AceComm-3.0 + ChatThrottleLib | 14 + 32 | Ace3 @ `ac3d122` | Ace3; ChatThrottleLib public domain | In-game sharing; ChatThrottleLib also paces raid pages posted to chat |
| AceConfig-3.0 (Registry 22, Cmd 14, Dialog 93) | 3 | Ace3 @ `ac3d122` | Ace3 | Options in the game's Settings panel |
| AceGUI-3.0 | 41 | Ace3 @ `ac3d122` | Ace3 | Required by AceConfigDialog (options only; DP's own UI is custom) |
| LibSerialize | 7 (v1.2.3) | rossnichols/LibSerialize tag v1.2.3 | MIT (`Libs/LibSerialize/LICENSE`) | Export-string payload |
| LibDeflate | 3 (1.0.2-release) | SafeteeWoW/LibDeflate main | zlib (`Libs/LibDeflate/LICENSE.txt`) | Compression and print-safe encoding (decoding uses DP's bounded inflater) |
| LibDataBroker-1.1 | 4 | tekkub/libdatabroker-1-1 master | No licence stated upstream (the repository has none; its CurseForge page says "All Rights Reserved"). Published by its author as a library for addons to embed; unmodified | Launcher data object |
| LibDBIcon-1.0 | 57 | repos.wowace.com libdbicon-1-0 trunk r168 | "Ace3 Style BSD" (its CurseForge and WowAce project pages; terms as in `Libs/Ace3-LICENSE.txt`) | Minimap button |
| LibUIShots-1.0 | 1 (wow-ui-harness 0.1.0) | wow-ui-harness, copied by `tools/sync_harness.sh` (commit in `tests/vendor/wow-ui-harness/VERSION`) | MIT (`Libs/LibUIShots-1.0/LICENSE.txt`) | `/dp shots` |
| LibSharedMedia-3.0 | 12000005 | repos.wowace.com libsharedmedia-3-0 trunk r186 | LGPL-2.1 (`Libs/LibSharedMedia-3.0/LICENSE.txt`), unmodified | Font choice (fonts other addons register) |

Why Ace3 master and not the latest tag: the GitHub tag `Release-r1403` carries AceDB 33 and AceConfigDialog 92, older
than the AceDB 40 / AceConfigDialog 93 several installed addons already ship. Pinning master at `ac3d122` matches them.

The map drawings (docs/ARCHITECTURE.md, Drawings) need no new library. They are drawn with the game's own `Line`
regions (`Frame:CreateLine`, already used for routes) and the widget kit; the stroke simplification is
Ramer-Douglas-Peucker, about 40 lines in `Model/Drawing.lua`: no WoW library we found offers it under a permissive
licence, and the offline tests need it in plain Lua. Undo is a snapshot
history (`Model/History.lua`) over the existing deep copy.

Batch two (runs against the plan, raid pages, shared-plan tracking) adds no library either. Pages travel with the
existing codec (LibSerialize + LibDeflate, kind "note") over AceComm; chat posting uses the ChatThrottleLib that AceComm
already vendors; the Notes window is the widget kit's window (`ButtonFrameTemplate`). Keyword expansion is about 100
lines of pattern matching in `Model/Pages.lua`, tested offline; the raid assignment addons that do the same are not
embeddable libraries.

Not used, on purpose: AceLocale-3.0 (picks the language from `GetLocale()` at load; WoW has no Polish client, so DP
chooses Polish at runtime itself), AceSerializer-3.0 (LibSerialize is the modern standard), AceHook-3.0 (DP hooks
nothing), HereBeDragons (no world-map pins).

## Bundled font

| File | Source | Licence | Used for |
|---|---|---|---|
| `Media/Fonts/AlegreyaSans-Medium.ttf` (Alegreya Sans 2.004, static Medium) | [google/fonts `ofl/alegreyasans`](https://github.com/google/fonts/tree/main/ofl/alegreyasans), upstream [huertatipografica/Alegreya-Sans](https://github.com/huertatipografica/Alegreya-Sans) | SIL Open Font License 1.1 (`Media/Fonts/OFL.txt`) | The Polish UI's face when WoW Po Polsku's Friz Quadrata with Polish letters cannot be loaded (the game's own Friz Quadrata has no a/c/e/n/s/z with Polish diacritics). English text keeps the game's font. Checked before bundling: every Polish letter is in the font (fontTools) |
| `Media/Fonts/DPSans.ttf` ("DP Sans Medium") | Made from `AlegreyaSans-Medium.ttf` above with fontTools: Latin subset, no layout tables, no hinting, one format-4 cmap, renamed (`Media/Fonts/FONTLOG.txt`) | SIL Open Font License 1.1, a Modified Version (`Media/Fonts/OFL.txt`) | The same face in plain TrueType, tried after the full file; it tells a problem with the file apart from one with the folder (docs/COMPATIBILITY.md, "Fonts on this client") |
