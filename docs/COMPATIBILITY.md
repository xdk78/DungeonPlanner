# Compatibility: World of Warcraft: Forever

Findings from Phase 0 (2026-11-15), made before any code was written and extended while integrating. Every design
decision in the addon follows from this page. Where something is inferred rather than verified, it says so.
Re-check this page whenever the client patches. `/dp debug` prints the live version of sections 3 and 6 in game.

## 1. Which client this is

| Fact | Value | Evidence |
|---|---|---|
| Product | World of Warcraft: Forever, product code `wowf`, install folder `_forever_` | `.build.info` (`Product` = `wowf`), `_forever_/.flavor.info` (`wowf`) |
| Build | `1.60.1.70938` | `.build.info` `Version` column |
| Interface (TOC) number | **`16001`** | `## Interface: 16001` in every Forever-only addon installed (ForeverCore, ForeverDungeonJournal, ForeverFishing, NeedRoll, GearQuestForever, OpenMap, WoWPoPolskuForever, ...); warcraft.wiki.gg "Patch 1.60.1/API changes" (`TOC: 16001`) |
| Game type / TOC suffix | `camelot`, alias `forever` (`MyAddon_Forever.toc`, `## AllowLoadGameType: camelot`) | Patch 1.60.1 API notes (2026-10-08); installed `Questie_Forever.toc`, `Details_Camelot.toc`; ForeverFishing's `## AllowLoadGameType: camelot` |
| `WOW_PROJECT_ID` | `WOW_PROJECT_CAMELOT` = **18** (added in build 70170) | Patch 1.60.1 API changes; DBM-Core `modules/objects/GameVersion.lua`; LibSpecialization (`wowID == 18`) |
| Code family | **Mainline (Retail) 12.1.5 UI architecture and API**, with Classic-era content plus new Forever dungeons | Patch 1.60.1 API notes, 2026-09-15: Forever and Midnight are game types of the Mainline code family and share "most APIs from 12.1.5" |
| Lua | Lua 5.1 (no `math.type`, no integers, no `goto`) | ForeverCore `Core/APIKit.lua`: "this client's Lua ... has no math.type"; all installed addons are 5.1 code. (1.60.1 added a Lua `import`; Dungeon Planner does not use it.) |
| Locale of the test client | `enUS` | the client's locale setting |

**Consequence:** Dungeon Planner declares `## Interface: 16001` and uses the Retail-style API (C_Map, C_ChatInfo,
Settings, MenuUtil, C_Timer), with every call that is not verified below feature-detected at runtime.

## 2. Restrictions inherited from Midnight (12.x)

| Restriction | Effect on Dungeon Planner | Evidence |
|---|---|---|
| **Secret values**: some API returns are opaque; comparing them or doing arithmetic raises | Every value read from the game that we compare or store passes `Util.Plain()` (`issecretvalue` guard). We never read auras, tooltips, unit health or nameplates. | Patch 1.60.1 notes 2026-09-15; errors captured on a test client (Details, ForeverDungeonJournal hit exactly this) |
| **Combat log closed** to addons | Kills come from `ENCOUNTER_END` / `BOSS_KILL` (plus DBM/BigWigs callbacks as an optional second signal). No combat-log parsing. | ForeverDungeonJournal `Systems/RunLog.lua` header |
| **Addon-message lockdown** in encounters and restricted states | The comm layer checks `C_ChatInfo.InChatMessagingLockdown` / `AreOutgoingAddonChatMessagesRestricted` and holds messages until the lockdown ends; what waited goes out first, in order, before anything newer. The outbox holds at most 40 messages without a key (acks and hellos go first when it is full; a transfer that would lose a part is aborted instead); keyed ones (group sync's state) replace each other. Chat posting refuses during a lockdown. | NeedRoll `Core/Init.lua`; DBM `AddonComms.lua` |
| **Per-prefix send budget** (10 messages, refilled 1/s, then "throttled") | ChatThrottleLib v32 (via AceComm) paces messages and retries `AddonMessageThrottle` results. Group sync relies on it: a leader sends at most one run state a second (changes within the second go as one), answers "who leads?" once a second (one group message for several askers), and members ask after a random 0-2 s wait; a raid of 40 opening run mode at once therefore spreads its questions instead of meeting the leader's budget in one burst. | The budget numbers: **inferred** (NeedRoll `Core/Init.lua` comment, not measured here). The retry of a throttled send and CTL's pacing (`MAX_CPS` 800, `BURST` 4000 bytes, per-priority queues sent in order): **verified** in the vendored ChatThrottleLib v32 source |
| Trial accounts cannot send addon messages | Sharing falls back to export strings. | Patch 1.60.1 notes 2026-10-08 |
| Creature GUIDs obfuscated; **secret inside dungeons** | We never parse GUIDs (`/dp scan` keeps only a GUID's type and NPC ID, to check). | Patch 1.60.1 notes 2026-10-16; Fellowship Ledger (MIT) in game 2026-11-09: `UnitGUID("target")` secret for every creature in a dungeon |
| **Player names carry a surname** | Identity is the whole name (`Share/Roster.lua`): where names carry surnames (the player's `UnitNameUnmodified` or `UnitName` has a second return, or the separator in the name), "First Surname", rebuilt from `UnitName`'s two returns with the client's separator (a space when the constant is missing; `/dp debug` says so). A sender's realm suffix is left off only when it is empty or our own realm; any other suffix is kept, so "Ana Smith-X" never matches the member "Ana Smith" (a member from another realm on Forever, where a unit's realm cannot be read, is therefore untrusted until the in-game test shows how such senders arrive). Elsewhere "Name", and "Name-Realm" from another realm (spaces and hyphens taken out). A sender is matched to a group unit by that identity only, never by a first name and never by asking the client to resolve a bare name (`UnitIsUnit` would map a same-realm stranger "Bob" onto the member "Bob-OtherRealm"); zero or two matching units make it untrusted. Replies to group members are whispered to their name exactly as it arrived. Display and saved names elsewhere still go through `Ambiguate(name, "none")`. | **Seen in another addon's shipped code, not yet verified by us** (the two-client test in game will): Polestar `Core/Compat.lua` (`UnitFullName` near l.141, `SenderName` near l.157, `SenderIsUnit` near l.168; its issue #1018): `UnitName(unit)` returns the first name and, as its second value, the surname instead of a realm; addon-message senders read "Ana Smith" or "Ana Smith-Realm"; the separator is `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` (a space); it falls back to `UnitIsUnit(sender, unit)` (we do not: see the left column). Also ForeverCore `Core/Character.lua`, BuffRadar and Pawn (the surname as the second return). Facts only: no code taken (Polestar is GPL) |
| **Realm names are gone** | Nothing is keyed by realm. Normalising a name with an empty realm appends nothing (no trailing "-"), and an empty suffix on a sender is dropped; with no realm name of our own, any non-empty suffix counts as another realm's. `/dp debug` reports `GetRealmName`, `GetNormalizedRealmName`, `UnitNameUnmodified`, the separator constant and `C_Timer.After`. | **Seen in another addon's shipped code, not yet verified by us**: since a November 2026 hotfix `GetRealmName` and `GetNormalizedRealmName` return `""` and `GetRealmID` returns 0 (ForeverCore `Core/Character.lua`, Polestar); DBM `AddonComms.lua`: "Realm names not used in forever" |
| Player position not exposed inside instances | The map shows plans; it never tracks live positions in instances, and there is no spawn recorder (`data-src/spawns/README.md`). The opt-in run recorder records pulls, bosses and wipes without positions (section 10). `/dp scan` records what `C_Map.GetPlayerMapPosition` and `UnitPosition` return where it runs | Retail 12.x rule; `C_Map.GetPlayerMapPosition` returns nil there; the client has no dungeon UiMap (ForeverPlusPlus); OpenMap shows the instance entrance while you are inside. **Checked in game** (Hall of Thanes, 2026-11-15): no best map, `UnitPosition` x/y nil, target GUID and name secret; only hostility, level and classification readable |
| Opening the Settings panel is restricted in combat | `/dp settings` waits until combat ends. | Retail 12.x behaviour (inferred) |
| **Gamepad interface style**: registering a slash command sets off blocked protected calls that end in a client freeze (an empty slash command is enough); the gamepad menus read and close the frames in `UISpecialFrames` | Detected once at login (`Compat.Gamepad`, every call guarded): `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputInterfaceStyle.Gamepad`, else the CVar `InputDeviceInterfaceStyle` compared with the same enum value. Without `Enum.InputInterfaceStyle.Gamepad` nothing is guessed and the style counts as off. If detection is wrong, Settings > AddOns > Dungeon Planner > Troubleshooting > "Gamepad interface style" sets it to On or Off (`settings.gamepad`, default Automatic; takes effect after `/reload`). With it on: no `/dp` or `/dplan` (`Slash.Init`, the one place that registers commands), nothing in `UISpecialFrames` (`W.AddSpecialFrame`; the window closes with its close button), no entry in OpenMap's menu, and no world map is opened (Dungeon Planner opens none anyway). The way in is the minimap button, the Addon Compartment and the key bindings. `/dp debug` (or its dialog) reports the state | Seen in another addon's shipped code, not yet verified by us. Test: `tests/test_gamepad.lua` |

## 3. API availability matrix

"Verified" = at least one Forever-only addon installed on this client calls it (often unguarded), so it exists on
build 70938. "Inferred" = in Retail 12.1.5 and not listed as removed in the 1.60.1 diff, not seen in a Forever-only
addon. **Every inferred API is guarded and reported by `/dp debug`.**

| API | Status | Evidence (installed addon, file) | Use / fallback |
|---|---|---|---|
| `C_Map.GetMapInfo`, `GetBestMapForUnit`, `GetMapChildrenInfo` | Verified | ForeverDungeonJournal `Systems/MapArtFinder.lua`; OpenMap | Map names, current map |
| `C_Map.GetMapArtLayers`, `GetMapArtLayerTextures` | Verified | ForeverDungeonJournal `Systems/MapArtFinder.lua` | The map canvas draws the game's own tiles. **Fallback:** a grid canvas when a map has no art (many new Forever dungeons) |
| `C_Map.GetMapGroupID`, `GetMapGroupMembersInfo` | Verified | Forever addons | Multi-floor dungeons; fallback one floor |
| `EJ_GetNumTiers`, `EJ_SelectTier`, `EJ_GetInstanceByIndex`, `EJ_SelectInstance`, `EJ_GetEncounterInfoByIndex`, `EJ_GetCurrentTier` | Verified to exist, guarded; **the journal is empty** (section 9) | ForeverDungeonJournal `Core/Journal.lua`; `/dp scan` on build 70938: 0 instances | Instance and boss lists where a client has them; on Forever the plans' own data, `Data/GameFiles.lua` and the Group Finder |
| `debugprofilestop`, `C_AddOnProfiler.GetAddOnMetric` with `Enum.AddOnProfilerMetric`, `C_AddOns.GetAddOnMemoryUsage` / `UpdateAddOnMemoryUsage` (or the old globals), the `BugGrabber` global's `GetDB()`, `debugstack`, the events `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`, `C_InputInterfaceStyle.GetCurrentStyle` (or the CVar `InputDeviceInterfaceStyle`), `IsInInstance`, `InCinematic` | Inferred (retail 11.x/12.x), guarded; **not yet checked in game** | Retail API; `/dp debug` lists the three checkable ones | `/dp perf` (timings, memory), the report window's Lua errors, blocked actions and input style, and the What's new card's quiet-moment check; each missing call leaves its line out and says so. BugGrabber is only read |
| `EJ_GetEncounterInfo`, `EJ_GetInstanceInfo`, `EJ_GetInstanceForMap` | Inferred, guarded | DBM uses `EJ_GetEncounterInfo` in shared code | Display names by ID (section 8) |
| `ENCOUNTER_START`, `ENCOUNTER_END`, `BOSS_KILL` | Verified | ForeverDungeonJournal `Systems/RunLog.lua`; NeedRoll `Core/Drops.lua` | Kill tracking; the ID equals the journal's `dungeonEncounterID` |
| `GetInstanceInfo` | Verified | 20 uses in Forever-only addons | Runs, difficulty; its eighth value (the instance ID) tells the Getting there window which instance the player entered, in any client language |
| `C_ChatInfo.RegisterAddonMessagePrefix`, `SendAddonMessage`, `CHAT_MSG_ADDON` | Verified | ForeverDungeonJournal `Systems/VersionCheck.lua`; NeedRoll | Sharing (through AceComm) |
| `C_ChatInfo.InChatMessagingLockdown`, `AreOutgoingAddonChatMessagesRestricted`, `Enum.SendAddonMessageResult` | Verified (pcall-guarded there too) | NeedRoll `Core/Init.lua` | Lockdown handling |
| `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory` | Verified | ForeverCore `UI/ForeverFamily.lua`; AceConfigDialog uses them | Options page |
| `MenuUtil.CreateContextMenu` | Verified | ForeverCore `UI/ContextMenu.lua` | Right-click menus and the plan menu (dropdowns use our own popup list) |
| Menu element `SetEnabled(predicate)` | Seen, guarded; not yet verified in game | Questie `QuestieMenuBuilder.lua`, RareScanner `RSWorldMapButtonMixin.lua` (a function); DBM-GUI (a boolean) | Greyed-out items in `W.Menu` (the draw line's clear menu); without it the item stays enabled and clearing nothing does nothing. Without `MenuUtil` the clear menu opens in our own popup list (enabled items only) |
| `GLOBAL_MOUSE_DOWN` event | Inferred (Mainline since 8.x), registered in `pcall` | Retail `UIDropDownMenu` / `Menu` close on it | Closing a dropdown list or the instance picker on a click elsewhere; fallback: a full-screen click catcher under the list. `/dp debug` reports it |
| `Frame:SetPropagateKeyboardInput`, `EnableKeyboard`; EditBox `OnArrowPressed`, `OnTabPressed` | Inferred, guarded (never called in combat) | Retail API | Arrow keys, Enter and Escape in dropdown lists; a list that holds the keyboard closes when combat starts |
| `C_AddOns.*` | Verified (unguarded) | ForeverCore `UI/Report.lua` | Version, addon detection |
| `C_Timer.After`, `C_Timer.NewTicker` | Verified | 434 uses in Forever-only addons | Timers (no idle OnUpdate) |
| `C_UIFileAsset.IsKnownFile` | Verified indirectly | LibSharedMedia-3.0 r186 calls it unguarded at load; the identical file runs inside DBM-Core on this client without errors | Required by LibSharedMedia |
| `AddonCompartmentFunc` TOC field | Verified | NeedRoll, Altoholic, ForeverDungeonJournal, OpenMap | Compartment entry |
| `issecretvalue`, `canaccessvalue` | Verified (guarded) | ForeverCore `Core/SafeCall.lua`; NeedRoll | `Util.Plain` |
| `UnitGroupRolesAssigned`, `GetRaidRosterInfo` | Verified via DBM's Forever path | DBM-Core | Roster |
| `UnitIsGroupLeader`, `UnitIsGroupAssistant` | Inferred, guarded (looked up with `rawget`, each answer through `Util.Plain`; a missing or secret answer counts as "no") | Retail 12.1.5 API | Who may send raid pages, and whose pages are taken; without them nobody can send (export strings still work) |
| `UnitClass`, `GetClassInfo`, `GetNumClasses`, `RAID_CLASS_COLORS`, `CLASS_ICON_TCOORDS`, `LOCALIZED_CLASS_NAMES_MALE` | Inferred, guarded | Retail 12.1.5 API | Class keywords, names in class colour and class icons on raid pages; without them the class name in plain text |
| `ENCOUNTER_START` | Verified (see above) | | Opens a raid page's Notes window on that boss's pull (by encounter ID, else by name) |
| `ChatThrottleLib:SendChatMessage` (vendored with AceComm) | Library | Ace3 | Posting raid pages to group chat, paced; spaced timers without it. Never during a lockdown or in combat |
| `C_Item.GetItemNameByID`, `GetItemIconByID`, `GameTooltip:SetItemByID` | Inferred, guarded | `C_Item.GetItemInfo` verified (52 Forever uses) | Gear list names/icons |
| `Texture:SetTextureSliceMargins` (9-slice) | Inferred | — | 4 pt rounded corners; fallback square |
| `Frame:CreateLine` | Inferred | — | Route lines and map drawings; fallback: routes listed only, drawings not drawn |
| `PixelUtil` | Inferred | — | Exact hairlines; fallback 1 unit |
| `C_EncodingUtil` | Inferred, **not used** | — | DP uses LibDeflate + LibSerialize for a byte-stable format that also decodes offline |
| `EJ_GetInstanceInfo` art returns (bgImage, buttonImage1, loreImage, mapID) | Inferred, guarded | no Forever-only addon calls it (Dungeon Journal hard-codes loading-screen paths and ships its own pictures instead) | Instance pictures on the home cards and page header; fallback parchment |
| `EJ_GetInstanceByIndex` returns after the name (description, bgImage, buttonImage1, loreImage, buttonImage2, dungeonAreaMapID, link, shouldDisplayDifficulty, mapID) | Inferred, guarded | Forever addons read only the first two (instanceID, name) | Pictures, the journal's dungeon map, the instance map ID; `EJ_GetInstanceInfo` fills gaps |
| `EJ_SelectEncounter`, `EJ_GetNumLoot`, `EJ_SetLootFilter`, `EJ_GetLootFilter`, `C_EncounterJournal.GetLootInfoByIndex` (or `EJ_GetLootInfoByIndex`) | Inferred, guarded | no Forever-only addon reads journal loot (Dungeon Journal ships its own loot tables) | The Gear page's and boss page's drops; fallback: the plan's own gear list |
| `C_Spell.GetSpellName`, `C_Spell.GetSpellTexture`, `GameTooltip:SetSpellByID` | Inferred, guarded (looked up with `rawget`, `pcall`) | the 12.x spell API (Retail) | The name, icon and tooltip of a boss ability from its bundled spell ID (`UI/BossSections.lua`, run mode's ability icons); without them "Spell <id>" and a question mark |
| `C_Item.GetItemInfoInstant`, else `GetItemInfoInstant` | Inferred, guarded | GearQuestForever (the global), Baganator and AllTheThings (`C_Item`) | An item's slot and armor or weapon type (any client language) for the Gear page's class and slot filters; an item the client has no data for yet is loaded first (`C_Item.RequestLoadItemDataByID`, `ITEM_DATA_LOAD_RESULT`) |
| `GetSpecializationInfoForClassID` | Inferred, guarded (looked up with `rawget`) | — | The role filter for journal loot; without it the role does not narrow drops. Also what a class can do (tank, heal, damage) for the party strip's guesses (`C_SpecializationInfo.GetNumSpecializationsForClassID`, else `GetNumSpecializationsForClassID`, for the count); without them a member with no role set takes a free seat, and the tooltip says it was placed, not guessed. A secret or missing name leaves the member out (no identity); a secret class, role or level shows the member plainly |
| `UnitIsConnected`, `UnitIsDeadOrGhost`, `UnitLevel`, `UnitClass` on group units | Inferred, guarded (looked up with `rawget`, each answer through `Util.Plain`) | Retail 12.1.5 API | The party strip (`Data/PartyInfo.lua`): offline and dead members dimmed, levels, class colours; a missing or secret answer shows the member plainly. Redrawn on `GROUP_ROSTER_UPDATE`, `PLAYER_ROLES_ASSIGNED`, `UNIT_NAME_UPDATE`, `UNIT_LEVEL`, `PLAYER_LEVEL_UP`, `UNIT_CONNECTION` and `UNIT_FLAGS` (group units only; a member's death and return), `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` (the player's own) and `PLAYER_ENTERING_WORLD`, coalesced to one redraw 0.3 s after a burst, only while the strip or the Party section is shown; an event the client does not know is skipped. On Forever `UnitGroupRolesAssigned` may answer "NONE" outside the group finder: the strip then guesses from the class and says so |
| `ChatEdit_InsertLink` | Inferred, guarded (looked up with `rawget`) | — | Shift-click links a drop in chat |
| `IsMouseButtonDown` | Inferred, guarded | — | After a resize whose release the size grip missed, the map's route arrows come back once no button is held (otherwise when the window hides) |
| `EJ_GetCreatureInfo(1, journalEncounterID)` | Verified, guarded | ForeverDungeonJournal `Core/Journal.lua` (pcall) | Boss portraits (iconImage, else display ID); fallback `UI-EJ-BOSS-Default` |
| `SetPortraitTextureFromCreatureDisplayID` | Verified, guarded | NeedRoll `UI/LootGrid.lua` (unguarded), ForeverDungeonJournal (pcall; a portrait drawn before its model loads shows as a black square painted over every window, so it renders them off screen first) | Boss portraits from the journal's display ID: drawn on a texture parked off screen; one timer for every portrait still loading draws each again after 2.5 s and moves it onto its row, header or pin in place; pooled (`UI/Art.lua`); the journal icon, then the skull, otherwise |
| `EJ_GetMapEncounter` | Inferred, guarded | — | The Adventure Guide's boss pins; asked again with the instance selected (`fromJournal`) when the first call returns none |
| `GetLFGDungeonInfo`, `GetLFDChoiceOrder` | Inferred, guarded | the `forever` branch of Blizzard's UI source calls both (`LFDFrame.lua`, `LFGFrame.lua`) | Level ranges, instance map IDs and the finder's background picture; fallback a plan's `levelMin/levelMax` |
| `C_LFGList.GetAvailableActivities`, `C_LFGList.GetActivityInfoTable` | Verified, guarded | ForeverDungeonJournal `Systems/LFGButton.lua` (pcall) | Level ranges and instance map IDs, also of Forever's new dungeons (only in this browse list) |
| `C_GameRules.IsGameRuleActive(Enum.GameRule.EncounterJournalDisabled)` | Inferred, guarded, `/dp scan` only | ForeverPlusPlus `docs/forever-api.md` (the rule is reported active) | Recorded by `/dp scan` |
| `C_AddOns.LoadAddOn("Blizzard_EncounterJournal")`, `C_EncounterJournal.OnOpen` | Inferred, guarded, `/dp scan` only | AdventureGuideClassic's `Probe.lua` (GPL, read for the idea only) | `/dp scan` checks whether the journal fills after loading and "opening" it |
| `Font:SetFont` / `FontString:SetFont` return values | Verified (API docs) | `Blizzard_APIDocumentationGenerated` on the `forever` branch: `SimpleFontAPI` SetFont returns nothing, `SimpleFontStringAPI` SetFont returns `success` | A hidden FontString tests each face before our font objects use it (section 8) |
| `GetQuestDifficultyColor` | Verified, guarded | OpenMap `Extras.lua` | Level range colours; fallback gold |
| `C_Texture.GetAtlasInfo` | Verified, guarded | NeedRoll `UI/Theme.lua`, OpenMap `Map/Panel.lua` | Atlas check before `SetAtlas` (which fails silently); fallback texture files |
| `IsInInstance`, `UnitPosition`, `GetSubZoneText`, `UnitGUID`, `UnitClassification`, `UnitCanAttack` | Inferred, guarded, `/dp scan` only | Retail 12.1.5 API | `/dp scan`'s `position` row: can the player's position and a target be read here (inside a dungeon: could spawns be recorded) |
| `GetFileIDFromPath` | Verified, guarded | ForeverDungeonJournal `UI/ThemeData.lua` (pcall); ForeverPlusPlus (in game: the Deadmines' first map tile is file 449591) | Which loading screens and old dungeon map tiles the client has (`Data/GameFiles.lua`); `/dp debug` art check. `Texture:SetTexture(path)` returns true even for a missing file on this client (ForeverPlusPlus), so it cannot tell |
| `BackdropTemplateMixin` / `BackdropTemplate` | Verified | ForeverDungeonJournal `Core/Journal.lua`; OpenMap | Window and panel borders; fallback flat textures |
| `UIPanelButtonTemplate`, `UIPanelCloseButton`, `PanelTopTabButtonTemplate` + `PanelTemplates_*` | Verified (templates), helpers guarded | NeedRoll `UI/MainFrame.lua`, ForeverDungeonJournal | Red panel buttons for primary actions, close button; created in `pcall`, parts checked, drawn fallbacks |
| `ButtonFrameTemplate` (`PortraitFrameTemplate`), `ButtonFrameTemplate_HidePortrait`, `ButtonFrameTemplate_HideButtonBar`, `SetTitle`, `SetPortraitToAsset` | Verified (template and helpers), guarded | NeedRoll `UI/MainFrame.lua`, Baganator, DBM-GUI; GearQuest Forever `Log.lua` (`PortraitFrameTemplate`, pcall) | The window (`UI/Window.lua`): frame, portrait ring, title bar, close button; parts checked by key, else the drawn window |
| `NineSliceUtil.GetLayout`, `NineSliceUtil.ApplyLayoutByName`, `NineSlicePanelTemplate`; layouts `InsetFrameTemplate`, `Dialog`, `ButtonFrameTemplateNoPortrait`, `PortraitFrameTemplate` | Verified, guarded | OpenMap `Core.lua` (`GetLayout` check, `NineSlicePanelTemplate`), DBM-GUI, Baganator (`Dialog`), Auctionator (`InsetFrameTemplate`) | Inset panels and dialogs (`Style.Inset`, `Style.DialogChrome`); the drawn border without the layout |
| `Frame:SetUsingParentLevel` | Inferred, guarded | Retail 12.1.5 API | An inset's bevel follows its panel's level; else our `SetFrameLevel` passes it on |
| `PanelTabButtonTemplate` + `PanelTemplates_SelectTab` / `DeselectTab` / `TabResize` | Verified, guarded | BugSack (modern clients), DBM-Core `RaidChecks.lua` ("Forever shares Mainline's tab helpers") | Sections and home lists as window tabs under the window (`W.Tabs` style "bottom"); segment plates without |
| `Frame:SetClampRectInsets` | Inferred, guarded | Retail API (the game's chat frames) | Keeps the tabs under the window on screen with it |
| `MinimalScrollBar` (`SetScrollPercentage`, `SetVisibleExtentPercentage`, `SetPanExtentPercentage`, `RegisterCallback(BaseScrollBoxEvents.OnScroll)`) | Verified (template), guarded | WhatsTraining's `Forever/Ignored.lua`, ForeverDungeonJournal `Systems/SettingsPanel.lua` | Scroll bars of lists, scroll areas and dropdown lists (`W.AttachThumb`); a drawn thumb without |
| `ScrollUtil.InitScrollFrameWithScrollBar` | Verified, guarded | ForeverDungeonJournal `Systems/SettingsPanel.lua` (pcall) | Joins a scroll area (`W.ScrollArea`) to its MinimalScrollBar; else our percentage wiring |
| Atlases `Options_List_Hover`, `Options_List_Active`, `common-dropdown-bg`, `UI-DialogBox-Background-Dark` | Verified, checked with `C_Texture.GetAtlasInfo` | WhatsTraining's `Forever/Settings.lua` and `Forever/Menu.lua`, ForeverCore `UI/ContextMenu.lua`, OpenMap `Core.lua` | List hover and selection, the dropdown list's panel, the dialog's background; drawn fills without |
| Atlases `crosshair_point_32`, `crosshair_mappincursor_32`, `crosshair_missions_32`, `crosshair_directions_32`, `crosshair_palette_32`, `crosshair_broom_32`, `crosshair_ui-cursor-move_32`, `socialqueuing-icon-group`, `common-icon-redx`, `128-redbutton-delete` | In the client's atlas table (read offline), checked with `C_Texture.GetAtlasInfo`; not yet seen in game | Offline renders from the client's files | The map toolbar's and draw line's pictures, drawn at the atlas's aspect ratio (its width and height from `GetAtlasInfo`); the tool's name or a drawn glyph without |
| `C_XMLUtil.GetTemplateInfo` | Inferred, guarded, `/dp debug` only | Retail API | Whether a template the window has not used yet exists |
| `CreateMaskTexture` / `AddMaskTexture` | Verified | NeedRoll `UI/Theme.lua`, ForeverDungeonJournal `LFGButton.lua` | Round portraits and icons; square without |
| `Texture:SetRotation` | Inferred, guarded | — | Route direction arrows, the Share section's Advanced caret; without it arrows point up and the caret down |
| `C_NamePlate.GetNamePlates`, `UnitAffectingCombat`, `UnitIsDead`, `UnitIsDeadOrGhost`, `UnitLevel`, `UnitClassification`, `UnitCanAttack` | Inferred, guarded (each value through `Util.Plain`) | Retail 12.1.5 API; hostility, level and classification **checked in game** inside Hall of Thanes | The run recorder's enemy counts (`Tracker/Recorder.lua`); without nameplates pulls are only timed |
| `GetMinimapZoneText`, `GetSubZoneText` | Inferred, guarded | Retail 12.1.5 API | Sub-zone names of recorded pulls |
| `GetPlayerFacing` | Inferred, guarded | Retail 12.1.5 API | The live Getting there map's arrow, outdoors (`/dp scan` records it too); the arrow points up without it |
| `PLAYER_LEAVING_WORLD` | Inferred | Retail event | The last outdoor spot before a loading screen, for learned entrances |
| `Minimap:IsProtected`, `GetZoom`, `GetZoomLevels`, `GetPingPosition` | Inferred, guarded, `/dp scan` only | Retail 12.1.5 API | Recorded by `/dp scan` (section 10); nothing is built on them |
| `COMBAT_LOG_EVENT_UNFILTERED` | **Not available** | ForeverDungeonJournal RunLog | Not used |
| `C_QuestLog.IsQuestFlaggedCompleted`, `IsOnQuest`, `GetLogIndexForQuestID`, `GetTitleForQuestID` | Verified, guarded | DataStore_Quests, GearQuestForever, Attune, ForeverDungeonJournal | Prep's quest states and attunement quests; titles in the player's language when cached, else the bundled English name |
| `C_Item.GetItemCount` (bank included), `GetItemCount` | Verified, guarded | Attune, BuffRadar, Altoholic | Prep's keys: carried or not; "Unknown" without |
| `UnitFactionGroup`, `GetNumGroupMembers`, `IsInRaid`, `UnitExists`, `UnitIsUnit`, `UnitGroupRolesAssigned` | Verified, guarded | Altoholic, Attune, DBM | The other faction's quests hidden; the group's levels and roles |
| `C_Map.GetMapPosFromWorldPos`, `C_Map.GetWorldPosFromMapPos`, `CreateVector2D` | Verified, guarded | GearQuestForever `Guide.lua`, `Pins.lua` (pcall; "GetMapPosFromWorldPos leads with the map id, then the position"), ForeverFishing | The entrance from world yards to its zone map and back, distances, flight masters near Forever's new dungeons |
| `C_Map.GetPlayerMapPosition` + `GetBestMapForUnit` | Verified, guarded; **outdoors only** (section 10) | GearQuestForever, ForeverFishing, TomTom | Getting there: distance and direction to the entrance; inside an instance the card says where distances show |
| `C_Map.SetUserWaypoint`, `C_Map.CanSetUserWaypointOnMap`, `UiMapPoint.CreateFromCoordinates`, `C_SuperTrack.SetSuperTrackedUserWaypoint` | Verified, guarded | Attune `Attune.lua`, GearQuestForever `Map.lua`, AllTheThings | The game's own map pin on the entrance (the baseline of "Navigate") |
| `C_Map.OpenWorldMap` | Verified, guarded | GearQuestForever `Map.lua`, Polestar `Core/Compat.lua` | "Show on world map". The global `OpenWorldMap` is never called (below) |
| `C_Map.GetAreaInfo` | Verified, guarded | WhatsTraining, OpenMap | Zone names of Questie's quest givers |

### Navigation and the world map (rules from Polestar's shipped code)

- The world map opens only through `C_Map.OpenWorldMap(uiMapID)`. The global `OpenWorldMap` called from addon code
  leaves the map frame tainted (later opens in combat are blocked, quest pins lost until a reload); `QuestMapFrame_*`
  is never called. Never in combat, never under the gamepad interface style (`Compat.Gamepad`, section 1: the map
  joins the gamepad's focus in the calling addon's name and its close is blocked).
- Nothing is sent to a navigator (Polestar, Shortest Path Forever, TomTom, the game's pin) in combat or while dead.
- Dungeon Planner draws nothing on the world map or the minimap and writes nothing into `WorldMapFrame`, its data
  providers or pin pools. Forever's gamepad navigation hooks `CreateFrame`: a frame created with a parent inside an
  open Blizzard panel taints it, so Dungeon Planner's frames are parented to its own frames or `UIParent` only.
- Polestar can install a stand-in global `TomTom`; the TomTom adapter checks that the TomTom addon itself is loaded.
- Four Forever zone maps use map-percent frames different from Classic Era's (Mulgore, Eastern Plaguelands, Redridge,
  Stormwind City): the bundled entrances are world yards from the game's tables or Forever map percent, never Classic
  percent.

## 4. Installed addons and libraries (inventory, 2026-11-15)

76 addon folders: DBM (Core, GUI, Party-*, Raids-*, Party-Forever), Details (+ plugins), DataStore + Altoholic,
Questie (+ DB, Trace), RXPGuides, AllTheThings, Attune, Auctionator, Baganator / Syndicator, BlizzMove,
BugGrabber / BugSack, GTFO, HandyNotes, TomTom, Leatrix_Plus, MiniAuras, MiniCC, **MinimapButtonButton** (a minimap
button collector), NeedRoll, **OpenMap**, Pawn, Platynator, Plumber, RareScanner, WhatsThatFor, WhatsTraining,
AutoSpellRanks, the Forever family (ForeverCore, **ForeverDungeonJournal** "DungeonJournal", ForeverFishing,
ForeverLootSparkles, GearQuestForever + class modules, MacroAssistForever) and **WoWPoPolskuForever**. Not installed:
BigWigs, WeakAuras, ElvUI, AddOnSkins, Masque, SexyMap, MinimapButtonBag.

### Library versions (LibStub minor) - ours never lower than any copy on this client

| Library | Newest copy already installed | Dungeon Planner ships | Source of our copy |
|---|---|---|---|
| LibStub | 2 | 2 | Ace3 |
| CallbackHandler-1.0 | 8 | 8 | Ace3 `ac3d122` |
| AceAddon-3.0 | 13 (WhatsThatFor) | 13 | Ace3 `ac3d122` |
| AceEvent-3.0 | 4 | 4 | Ace3 |
| AceTimer-3.0 | 17 | 17 | Ace3 |
| AceConsole-3.0 | 7 | 7 | Ace3 |
| AceDB-3.0 | 40 (HandyNotes) | 40 | Ace3 (the latest tag r1403 has 33, so we pin master `ac3d122`) |
| AceDBOptions-3.0 | 17 | 17 | Ace3 |
| AceComm-3.0 / ChatThrottleLib | 14 / 32 | 14 / 32 | Ace3 |
| AceConfig-3.0 (+Registry 22, Cmd 14, Dialog 93) | 3 / 22 / 14 / 93 | same | Ace3 |
| AceGUI-3.0 | 41 | 41 | Ace3 |
| LibSerialize | 4 (Altoholic, DataStore) | **7** (v1.2.3) | rossnichols/LibSerialize |
| LibDeflate | 3 (1.0.2) | 3 (1.0.2) | SafeteeWoW/LibDeflate |
| LibDataBroker-1.1 | 4 | 4 | tekkub/libdatabroker-1-1 |
| LibDBIcon-1.0 | 57 | 57 | wowace trunk r168 |
| LibSharedMedia-3.0 | 12000005 (DBM-Core) | 12000005 | wowace trunk r186 (identical to DBM's copy) |

LibStub keeps the highest minor any addon loads, so equal or newer copies cannot break anyone. Not used: AceLocale
(cannot pick Polish at runtime, see section 8), AceSerializer (LibSerialize is smaller and faster), AceHook (no hooks),
HereBeDragons (no world-map pins), LibUIDropDownMenu (MenuUtil).

### Names Dungeon Planner must not collide with

| Kind | Taken by installed addons (relevant ones) | Dungeon Planner uses |
|---|---|---|
| Slash commands | 80+ incl. `/dj`, `/note`, `/notes`, `/dbm`, `/pull`, `/way`, `/nr`, `/gq`, `/openmap`, `/wtr` (WoW Po Polsku) | **`/dp`**, **`/dplan`** (registered by no installed addon; full scan of `SLASH_*` and `RegisterChatCommand`) |
| Addon-message prefixes | `ForeverDJ_`, `DJournalVer`, `NeedRoll`, `NR1`, `NRT2`, `AltoShare`, `DataStore`, `TOMTOM4`, `OpenMap`, `OpenMapLoc`, `GTFO`, `ATTC`, `BigWigs`, `LibSpec`, `RXPGComms`, `Attune_*`, `QuestieV1`, ... | **`DungeonPlanner`** (14 bytes) |
| SavedVariables | `ForeverDungeonJournalDB`, `NeedRollDB`, `OpenMapDB`, `WoWPoPolskuForeverDB`, ... | **`DungeonPlannerDB`** (AceDB: global / profiles / char) |
| Globals | none starting with `DungeonPlanner` | `DungeonPlanner` (holds only `API`), `DungeonPlannerMainFrame`, `DungeonPlannerDialog`, the window's named parts (`DungeonPlannerHome`, `DungeonPlannerInstancePage`, `DungeonPlannerInstanceHeader`, `DungeonPlannerSearchBox`, `DungeonPlannerMapSection`, `DungeonPlannerPlanSection`), `DungeonPlanner_Binding`, `DungeonPlanner_OnAddonCompartmentClick`, `BINDING_HEADER_DUNGEONPLANNER`, `BINDING_NAME_DUNGEONPLANNER_*`, font objects `DungeonPlannerFont_*`, `DungeonPlannerTooltip` |
| Key bindings | — | six actions, **no default keys** |

## 5. Dungeon Journal and OpenMap: look, API approach, integration

Both are popular addons on this client; both were read from an installed copy (read-only).

| | Dungeon Journal (ForeverDungeonJournal 2.0.7, by Exehn) | OpenMap (v0.8.9, MIT) |
|---|---|---|
| Look | Dark panels tinted per dungeon (`UI/ThemeData.lua`), parchment quest pages, the game's fonts copied into its own font objects per alphabet (`Core/Fonts.lua`) so other addons' font replacement cannot break it | Plain dark panel with a 1 px border (`Look:Panel`, `0.06/0.06/0.07` at 90 %), the game's metal window frame when available (`Look:Window`), `STANDARD_TEXT_FONT` with a 1 px shadow |
| Maps | `C_Map` art layers, with a name search when a stored uiMapID has no art ("map IDs can differ between client builds") and its own TGA parchments for new Forever dungeons | Blizzard's dungeon maps in the world map; its own pictures from the game's minimap art where there are none |
| Encounters | `EJ_*` scan over every tier, explicit `EJ_SelectInstance` first, instanceID passed and not passed to `EJ_GetEncounterInfoByIndex` | The game's boss list per dungeon |

What Dungeon Planner took (approaches, not code - no file was copied from either):
- **Fonts:** our own font objects (`DungeonPlannerFont_*`) with the game's face per alphabet (Friz Quadrata, its
  Cyrillic cut, the Korean and Chinese faces), so DP reads like both addons and no font replacer breaks it.
- **Maps:** the same `C_Map` art-layer approach, the same name-based fallback when a uiMapID has no art
  (`Instances.FindArtMapByName`, our implementation), and a grid canvas where no art exists.
- **Journal scanning:** every tier; select the instance first; try both call shapes; never while the Blizzard journal
  is open; restore the selected tier.
- **Look (version 2, replacing the flat monochrome window of version 1):** game-native like Dungeon Journal and
  NeedRoll - the rock-and-gold window, red Blizzard buttons, the game's top tabs, tooltip-bordered panels, the journal's
  round boss portraits, instance pictures from the journal, the dungeon map as a framed parchment with boss pins. Only
  Blizzard template, texture and atlas names were taken (facts about the client); no code or art. Full notes:
  `docs/UI.md`.

Integration (optional, guarded, public entry points only):

| Addon | What DP does | Entry point | Decided against |
|---|---|---|---|
| Dungeon Journal | "Dungeon Journal" button on the Encounters tab opens it | the global `ForeverDungeonJournal_Toggle()` (its binding/compartment entry) | Calling `FDJ.OpenBossFromWorldMap` and other functions on its private namespace `ForeverDungeonJournal_NS`: internal, may change any release |
| OpenMap | A "Dungeon Planner" section on OpenMap's dungeon map card listing your plans for that dungeon; a "Dungeon Planner" switch in OpenMap's menu that opens/closes our window; its drawn maps of Forever's new dungeons and their boss pins through the data-provider adapter (section 6) | `OpenMapAPI` (major 1): `RegisterDungeonSection`, `RegisterMenuToggle`; the maps from its internal tables, guarded | Its classic dungeon tiles: the same game tiles `Data/GameFiles.lua` draws |
| `## OptionalDeps` | `ForeverDungeonJournal, OpenMap, NeedRoll, QuestieDB, DBM-Core, BigWigs, LibSharedMedia-3.0` so their APIs and data exist when we enable | | |

## 6. Compatibility matrix (other addons)

| Addon | Installed here | What DP does | Status |
|---|---|---|---|
| DBM | yes | Kill fallback: `DBM:RegisterCallback("DBM_Kill", fn(event, mod))`, `mod.encounterId` / `mod.combatInfo.eId`; deduplicated with ENCOUNTER_END | Code path verified against DBM-Core source; in-game untested |
| BigWigs | no | Kill fallback: `BigWigsLoader.RegisterMessage(owner, "BigWigs_OnBossWin", fn(event, module))`, `module.engageId` | Untested (not installed) |
| Details | yes | Nothing; no conflict (no shared names) | — |
| WeakAuras | no | Can read plans via `DungeonPlanner.API` and its callbacks (docs/API.md) | Untested |
| ElvUI / AddOnSkins / Masque | no | Stable frame names (`DungeonPlannerMainFrame`, `DungeonPlannerDialog`), `API.GetFrames()`; DP never touches the game's font objects, so ElvUI's "Replace Blizzard Fonts" cannot break it; no Masque groups (DP has no action buttons) | Untested |
| Questie / RXPGuides / AllTheThings | yes | Nothing; no conflict | — |
| TomTom, Polestar, Shortest Path Forever | TomTom and Polestar yes; Shortest Path Forever no | Prep's "Navigate" sends the instance entrance through their public calls (data providers below); DP never draws on the world map | Offline tests with fake APIs; in game untested |
| HandyNotes | yes | Nothing: a pin collection, no destination API worth a hand-off | — |
| MinimapButtonButton | yes | DP's minimap button is a LibDBIcon button, which collectors pick up | In-game untested |
| WoW Po Polsku Forever | yes | Section 8 | Code path verified offline; in-game untested |
| NeedRoll, GearQuestForever, Pawn | yes | Overlap only in topic (loot/gear); DP stores your own gear lists, no item database. NeedRoll: "Open in NeedRoll" (data providers below) | — |

### Data providers (runtime adapters, `Data/Providers/`)

Optional adapters that read another addon's data in the player's client while both run. Nothing from these addons is
copied into this repository or into Dungeon Planner's shipped data; the licences below matter only because of that.
Each adapter checks existence and shapes, runs every call in `pcall`, deactivates itself for the session on the first
error, can be switched off in the settings ("Data from other addons"), and is credited where its data shows. `/dp
debug` lists each one as active or inactive with counts.

| Adapter | Addon (licence) | Provides | Reads | Public API? | Verified |
|---|---|---|---|---|---|
| `dungeonJournal` | ForeverDungeonJournal 2.0.7 (no licence stated) | Maps of Forever's new dungeons (one 1024 px picture per floor, cropped with its `texBottom`), boss pins on them, loot per boss, boss portraits (its baked pictures by display ID, else the display ID), what it states about a boss: level, description, summon item and drops (shown credited in the marker details, the Bosses page and run mode; it has no abilities or lore for bosses), and its own card pictures of instances where the game has none (only files in its own `Media` folder; credited "Picture: Dungeon Journal" in the home preview) | `_G.ForeverDungeonJournal_NS`: `DUNGEON_MAPS`, `DB[name].bosses` (also `rare`, `description`, `summonItem`), `BOSS_LEVELS`, `SHARED_BY_BOSS`, `STATIC_DISPLAY_IDS`, `BAKED_PORTRAITS`, `DUNGEON_HOME_ART`, `DUNGEON_HOME_TEXCOORD` | **No**: internal tables (its only public entry point is `ForeverDungeonJournal_Toggle`) | Shapes read from its installed code; offline tests with fake data; in game untested |
| `foreverDungeonRoutes` | Forever Dungeon Routes 1.2.4 (MIT code; its map pictures are Santiago Reyes', used with his permission, not MIT) | Its routes as an extra map layer, "Routes: Forever Dungeon Routes" (main path teal, side paths fainter; off until ticked in the legend, never in run mode), drawn only on a map its coordinates fit: the game's map art for a classic floor (floors matched by the first tile's file ID, `GameFiles.FloorTileID`), Dungeon Journal's or its own picture for a Forever floor (the same pictures, same crop, checked offline). Its maps of Forever's new dungeons where neither the game nor Dungeon Journal has one, with its boss stops as pins | `_G.ForeverDungeonRoutes` (its namespace, `Core.lua`): `Dungeons`, `Floors` (map tables; the picture floors that `Pictures.lua` adds carry `image`), `DefaultRoutes` (of several, the variant named like the plan, else the full clear), `Rooms` (counted only). Lines with an odd count or a value outside 0..1 are skipped; at most 20 lines a floor | **No**: internal tables (it has no data API) | Shapes read from its source (1.2.4); offline tests with fake data; in game untested |
| `openMap` | OpenMap 0.8.9 (MIT code; the drawn maps credit their artists) | Players' drawn maps of Forever's new dungeons (4 x 3 tiles), boss pins per floor, the instance list | `_G.OpenMap` (its namespace): `MapPlaces.instances`, `MapDungeonDrawn`, `MapDungeonBosses` | **No**: `OpenMapAPI` has no data calls; internal tables | Same |
| `needRoll` | NeedRoll 1.7.0 (GPL-3.0) | "Open in NeedRoll" for a boss's loot | `NeedRoll_ShowLoot(instance, boss)` (documented in its `docs/API.md`) | **Yes** | Same. Its spots and loot tables live on a private namespace it does not publish, so they cannot be read; nothing feeds the Enemies layer from it |
| `questie` | QuestieDB 1.1.1 (GPL-3.0) | Quests filed under the dungeon's area, with level and quest giver (Runs section) | `LibQuestieDB` contract 4: `RequireContract`, `Enum.zoneIDs`, `Quest.GetAllIds/zoneOrSort/name/questLevel/startedBy`, `Npc.name`, `Npc.spawns` | **Yes** (its data contract) | Same. Scans all quest IDs once per dungeon in slices of 400 per frame, on demand. Its instance NPCs have no coordinates inside dungeons, so nothing goes on the map. Prep asks `Givers(questIDs)`: each quest's first starting NPC, its name and its first spawn (area ID and 0-100 position; the zone's name from `C_Map.GetAreaInfo`), a few lookups per quest. Its Forever data is taken as Forever coordinates (its `EraToForever` is for Era points only) |
| `tomtom` | TomTom (all rights reserved) | Navigate: the nearest flight master, then the entrance, as waypoints | `TomTom:AddWaypoint(uiMapID, x, y, { title, from, persistent = false })`, only when `C_AddOns` says TomTom is loaded (Polestar can install a stand-in `TomTom`) | **Yes** | Signature read from its installed `core/waypoints.lua`; offline tests with a fake; in game untested |
| `polestar` | Polestar (GPL-3.0) | Navigate: the entrance as its arrow's target (it plans flights and boats itself); "About 6 min with Polestar" from its estimate | `Polestar.Nav.API` version 1: `Navigate(owner, uiMapID, x, y, title)`, `Estimate(nil, nil, nil, toMap, x, y)` (nil on "busy" or "unknown"), `Cancel(owner)`; it refuses instance maps, so only the outdoor entrance goes | **Yes** (its documented API) | API read from its installed `Nav/Journey.lua`; offline tests with a fake; in game untested |
| `shortestPath` | Shortest Path Forever (GPL-3.0-or-later) | Navigate: the entrance as its route's target | `ShortestPathForever.API` version 1 or 2: `Navigate(owner, uiMapID, x, y, title)`, `Cancel` checked present | **Yes** | **Inferred** from Polestar's integration (how its `Nav/Handoff.lua` calls it); not yet verified against Shortest Path Forever itself. Polestar includes its walking router |

**Navigate** picks the first active of Polestar, Shortest Path Forever and TomTom, else the game's own map pin
(`Data/Navigation.lua`); its "..." menu lists every available way. Each adapter can be switched off in Settings.

**Map priority** for a plan floor: the game's own map art (a UiMap's art, else the old dungeon map tiles, Data/GameFiles.lua),
then Santiago Reyes' bundled map of a Forever floor (`Data/ReyesMaps.lua`, with his permission), then the first adapter
that has a picture, in the order they load: Dungeon Journal, Forever Dungeon Routes, OpenMap; then the game's minimap
pictures (section 9); else the parchment grid. The bundled maps are the same pictures as Dungeon Journal's and Forever
Dungeon Routes' (same crop), so when one of them is installed its boss pins, alignment and routes are drawn on the
bundled map. A picture floor is picked by the plan floor's name (`Providers.PickFloor`: the label, else the
most words of the name in the label or, unlabelled, the file name, else the position).

Other installed addons with dungeon data were looked at and are not read: DBM-Party-Forever (encounter IDs of the
Forever bosses, but its mods load on demand and DBM is all rights reserved; kills already arrive through
`ENCOUNTER_END`), RareScanner (private namespace, all rights reserved), Attune (attunement quests only), AllTheThings
(excluded, docs/DATA-SOURCES.md).

**Alignment.** The recommended plans of Forever's new dungeons were placed without a map in the client. Under a
provider's map, the plan's boss markers are paired by name with the provider's boss pins (`Providers.Align`): if they
agree within 0.035 of the map they are drawn as they are (the Hall of Thanes plan matches Dungeon Journal's pins
within about 0.02); if a per-axis scale and offset fitted over three or more bosses brings them within that, the plan
is drawn through it (and input goes through its inverse, so edits stay in the plan's space); otherwise the provider's
boss pins are shown for every boss and the plan's boss markers are hidden, while its other markers and steps stay.
A provider map without boss pins (OpenMap has none for Hall of Thanes) cannot be checked: the plan is drawn as it is.

Hygiene: one global table, binding strings and frame names only; no hooks of Blizzard functions; no SetCVar /
SetBinding; no secure frames; nothing protected in combat; every integration behind an existence check and `pcall`.

## 7. Rules that follow

1. `## Interface: 16001` only for now (Mainline 120105/120107 is plausible later, untested).
2. No bundled game data. Instances, bosses and maps come from the client at runtime. Plans and gear lists are
   user-authored or come from the community repository.
3. Every API not "Verified" above is feature-detected (`Core/Compat.lua`) and reported by `/dp debug`.
4. Never touch secure frames, hook Blizzard functions, act in combat lockdown, parse the combat log, or compare a value
   that could be secret without `Util.Plain`.
5. Sharing must survive lockdowns and throttling and treat every received byte as hostile.

## 8. Polish translation (WoW Po Polsku)

Read locally, read-only: `Interface/AddOns/WoWPoPolskuForever` v0.4.0, by Loe'Aner. **Proprietary** (`LICENCJA.txt`:
code and translation database all rights reserved; only `Media/` is excluded, its fonts under OFL). Nothing was
copied from it; DP only detects it and reads its saved language setting.

How it works (from its code):

| Aspect | Finding | File |
|---|---|---|
| Client locale | Runs on an **English client**: `GetLocale()` stays `enUS` (its own checks: `KLIENT_ANGIELSKI = { enUS, enGB }`) | `Postac.lua`, `Zbieracz.lua` |
| Languages | Polish (`plPL`), Czech (`csCZ`), Hungarian (`huHU`), Vietnamese (`viVN`); chosen language in `WoWPoPolskuForeverDB.jezyk`, honoured only when `.wyborJezyka >= 1` (set by its first-run chooser); on/off in `.wlaczony` | `Rdzen.lua` |
| Fonts | At its `ADDON_LOADED` and again at `PLAYER_LOGIN`, walks **every named font object** (`GetFonts()`) and swaps Friz Quadrata for `Media/frizquadratatt_pl.ttf`, Morpheus for `morpheus_pl.ttf` (Polish), or Alegreya for the other languages (also Arial Narrow in chat) | `Rdzen.lua` (`podmienFonty`) |
| Text | Hooks quest, gossip, bubbles, tooltips, map coordinates and other Blizzard frames by replacing their FontString text | `Interfejs.lua`, `Mapa.lua`, `Misje*.lua` ... |
| Public API | None found (all state on its private namespace) | — |

What Dungeon Planner does:

| Requirement | How | Verified |
|---|---|---|
| Language setting: Auto / English / Polski | Auto = Polski when WoW Po Polsku is loaded or enabled (`C_AddOns.IsAddOnLoaded` / `GetAddOnEnableState`, guarded; folder `WoWPoPolskuForever`, or any folder containing "polsku") **and** it has Polish chosen (`jezyk == "plPL"` with `wyborJezyka >= 1`, the same test it applies itself). Installed but never configured means English: it translates nothing then (seen in game on 2026-11-15, where an unconfigured copy made DP Polish with missing glyphs). Otherwise the client's language. A player without it gets pure English, no side effects. | Offline tests (`tests/test_db.lua`, `test_ui.lua`) |
| Real plPL locale | `Locales/plPL.lua`, every key (338) translated, format specifiers checked by tests; terms from WoW Po Polsku's player glossary (rajd, loch, pull, obrońca, uzdrowiciel, zadający obrażenia, łup, ekwipunek). Key-binding names translated too. | `tools/locale_keys.lua Locales/plPL.lua`: 0 missing |
| Fonts with ąćęłńóśźż (fixed 2026-11-15: before, every Polish face was rejected because a Font object's `SetFont` returns nothing on this client, so all text used the game face and showed boxes) | Whenever DP's UI is Polish (Auto or forced) with the game/follow font, DP tries WoW Po Polsku's `Media/frizquadratatt_pl.ttf` (the game's look; only while that addon is enabled), then the bundled Alegreya Sans and its cleaned copy `DPSans.ttf` (`Media/Fonts/`, OFL), each tested first (a FontString's `SetFont`, or Polish letters drawn through our Font object; see "Fonts on this client"), else the game face; the game's tabs, menus and tooltips in our window get our font objects too (`SetNormalFontObject`, menu initializers, our own `DungeonPlannerTooltip`), never by changing the game's font objects: the client's `FRIZQT__.TTF` has no ą ę ś ż (seen in game), and the translation restyles the game's fonts on its own `PLAYER_LOGIN`, possibly after ours. Without that file `SetFont` fails and DP falls back to the game face. Otherwise font setting "Auto" = **follow** the game's font objects when WoW Po Polsku is loaded: our fonts take the face of `GameFontHighlight` at the moment the window is built (after `PLAYER_LOGIN`), which is its `frizquadratatt_pl.ttf`. Our own font objects are named, so its `GetFonts()` pass also converts them if they already exist. Never a conflicting override: DP does not touch the game's font objects. LibSharedMedia fonts can be chosen too. | Offline (`test_ui.lua`); **glyph rendering needs an in-game look** (`/dp debug` prints "ąćęłńóśźż" for that) |
| No early caching of English strings | DP reads no GlobalStrings at load; class names (`GetClassInfo`), map and boss names are read when a panel is drawn. | By construction |
| Names translated | Plans store IDs (journal encounter ID, encounter ID, journal instance ID, uiMapID); names are resolved at display time from the game (`Data/Names.lua`); the stored name is only a fallback. A plan shared between Polish and English players shows each client's names. WoW Po Polsku rewrites Blizzard frames' text, not API return values, so on an English client the journal API still returns English names; DP's own UI is Polish via `plPL`. | Offline; in-game check whether WoW Po Polsku also rewrites DP's FontStrings (it hooks specific Blizzard frames, so it should not) |
| Load order | No `OptionalDeps` on it: DP reads fonts and its setting after `PLAYER_LOGIN`, when both addons have loaded. | By construction |

Needs in-game testing: glyphs in DP's window with WoW Po Polsku active; that it leaves DP's frames alone; that its
language selection wizard (`/wtr`) switching languages is picked up after `/reload`.

### Client languages and the UI languages (checked 2026-11-22)

Blizzard publishes no list of WoW: Forever's client languages. Evidence that the standard set exists:

| Evidence | Finding |
|---|---|
| warcraft.wiki.gg `API_GetLocale` | `GetLocale()` returns enUS (also for enGB), deDE, frFR, esES, esMX, ruRU, ptBR, itIT, koKR, zhCN, zhTW; the page lists WoW Forever (1.60.1) among the game types, without a difference |
| The installed Forever client | `Wow.exe` carries the locale table (enUS, deDE, frFR, esES, esMX, ruRU, itIT, ptBR, koKR, zhCN, zhTW), as do the same-named locale files of the installed ForeverDungeonJournal (frFR, esES, ruRU, itIT, ptBR, koKR, zhCN, zhTW) and DBM-Core (`localization.de/es/fr/ru/...`) |
| Community reports | A French site reports a French Forever client and French servers; RestedXP ships Forever guides in German, French, Spanish, Portuguese and Chinese |
| Not confirmed | No Blizzard page says that Forever's launcher offers every one of these; the Russian client in particular is region-restricted on EU servers in retail, and nothing says whether Forever lifts that. |

DP ships enUS, deDE, esES (also for esMX), frFR, plPL (chosen, or with WoW Po Polsku) and ruRU. A locale is picked
automatically only when `GetLocale()` returns it (`ns.SetLocale`); a player can pick any shipped language by hand on
any client, so the translations are useful even where a client language turns out not to exist. Fonts: the client's
`FRIZQT__.TTF` covers Latin-1 (German, French, Spanish accents, `ß`, `ñ`, `¿`, `¡`); `œ` is avoided in French. A
Russian UI uses `FRIZQT___CYR.TTF` (the file ForeverDungeonJournal's `Core/Fonts.lua` names for Russian) when this client
has it, else the bundled Alegreya Sans (`UI/Fonts.lua`, `tests/test_ui.lua`). Alegreya Sans Medium has every Russian
letter, checked with fontTools on 2026-11-22 (`Media/Fonts/FONTLOG.txt`); `tests/test_fonts.lua` reads its cmap
(`tools/ttf_cmap.lua`) and fails if a shipped locale uses a character it lacks. A face the client cannot vouch for yet
is taken and looked at again after the first loading screen (`Style.RecheckFonts`, as for Polish); `/dp debug` lists
`FRIZQT___CYR.TTF`, and the language dialog and one chat line say when no Cyrillic face loads, or when the font setting
is Arial Narrow or a SharedMedia face.

Needs in-game testing:
- that `FRIZQT___CYR.TTF` opens on a non-Russian client;
- that the layout (checked offline with a widened Alegreya Sans, `tests/ui_dump.lua --locale`) holds with the game's
  real fonts;
- the parts the game draws with its own fonts, which an addon cannot change and which may show boxes for Russian on a
  client without Cyrillic: the key binding labels (Options > Key Bindings, the `BINDING_*` strings), the TOC `Notes`
  line in the AddOns list, the Settings panel entry for DP (its category name and our option labels are drawn by
  Blizzard's controls), the game's own menus and tooltips on Blizzard frames, and the Addon Compartment entry;
- that German, French and Spanish show no boxes in the same places (Latin-1 is in the game's face, so none should).

## 9. The Adventure Guide is empty on WoW: Forever

The first in-game `/dp scan` (build 70938, enUS) found no journal instance at all: 0 instances, and every recommended
plan resolved to none. Why, from several independent sources:

| Finding | Evidence |
|---|---|
| `EJ_GetNumTiers()` returns **0** and `EJ_GetInstanceByIndex(1, false)` returns nothing | Our scan (it reported "1 tier" only because a count of 0 fell back to one pass: fixed, the raw count is now recorded); the in-game probes documented by ryna_agent (`docs/forever-client-api.md`, MIT) and Fellowship Ledger's verify report (`journal: 0 instances`, MIT) |
| The client has **no `JournalInstance` / `JournalEncounter` tables** | wago.tools serves none for build 70790 (ryna_agent's notes) |
| The game rule **`EncounterJournalDisabled`** is active | ForeverPlusPlus `docs/forever-api.md` (MIT) |
| `Blizzard_EncounterJournal` is loadable (its TOC lists `standard, classic`) but loading it does not fill the journal | ryna_agent's notes; `/dp scan` now tries it and records the counts before, after loading, after `C_EncounterJournal.OnOpen()` and 3 s later |
| No boss loot or ability data in the client | ryna_agent's notes; the Dungeon Journal addon ships its own loot tables, art and portraits for this reason |
| No dungeon-type UiMap; the old dungeon map art is still there as textures | ForeverPlusPlus (in game, enUS); see `Data/GameFiles.lua` |

So of the four hypotheses: loading `Blizzard_EncounterJournal` first, selecting tiers before both `isRaid` values,
and "it only fills once opened" do not help (the scan still records each, to be sure); **the journal is simply empty
on Forever**. What Dungeon Planner uses instead:

| Need | Source now | Status |
|---|---|---|
| Card and header pictures | The instance's loading screen (`Interface\Glues\LoadingScreens\LoadScreen<Name>`, names and file IDs as the Dungeon Journal addon shows them on this client, others by the same pattern, and the files the client's own `LoadingScreens` table gives the instance maps whose names differ, below), checked with `GetFileIDFromPath`; else the Group Finder's background (`GetLFGDungeonInfo`); else an installed addon's own picture (Dungeon Journal's card art, credited); else a drawn plate (slate stone, the game's dungeon or raid mark in a bronze ring, the name) | Verified by `/dp scan` (below): 30 of the 43 recommended plans' instances have one; 8 more found offline in the client's tables (2026-11-16), to confirm in game |
| Dungeon maps | The original dungeon map tiles (`Interface\WorldMap\<Dir>\<Name><floor>_1..12`, 4 x 3 tiles, 1002 x 668, the classic art layer's layout), per plan floor; for Forever's new dungeons, Santiago Reyes' maps bundled with his permission (`Data/ReyesMaps.lua`, below); for Scholomance's old layout and floors he has not drawn, the game's own minimap pictures composed per floor (`Data/MinimapArt.lua`, below); the parchment grid where none exists | Tile names verified by ForeverPlusPlus in game (enUS); some languages lack the textures (OpenMap and Leatrix Maps ship copies for esMX, ruRU, itIT): then the grid |
| Boss portraits | None in the client without the journal: a skull icon in the journal's ring instead of its "?" face. The Dungeon Journal addon uses its own table of creature display IDs and pictures it took in game; we ship neither | Fallback only |
| Loot | None in the client: the Gear page says so and shows the plan's own gear list | Verified by the empty scan |
| Level ranges | The Group Finder's browse list (`C_LFGList`) when it gives two different levels; the dungeon finder list gives one level per dungeon on Forever, so a plan's own range comes before it (`GameFiles.ResolveRange`) | Verified by `/dp scan` (below) |

Everything stays guarded: a client that does have a journal (or a later Forever patch that fills it) is used first.

### What the extended `/dp scan` confirmed (build 70938, enUS, 2026-11-15)

| Area | Result | What changed |
|---|---|---|
| Journal | 0 tiers, 0 dungeons, 0 raids before and after loading `Blizzard_EncounterJournal`, after `C_EncounterJournal.OnOpen()` and 3 s later. `LoadAddOn` refuses it with `WRONG_GAME_TYPE`; the game rule `EncounterJournalDisabled` is `true` | Nothing to fix: the journal stays a guarded first choice |
| Dungeon finder (`GetLFGDungeonInfo`) | `GetLFDChoiceOrder()` returns an empty list, so the bounded ID scan finds the entries: 66 of them on odd IDs 1-131 (26 dungeons and raids, 3 battlegrounds, 37 zones). Each gives **one level** (min = max: "Deadmines 16-16", "Ragefire Chasm 13-13"), an empty type for dungeons (4 for zones, 5 for battlegrounds), no background picture and no instance map ID | This list used to win over everything, so cards showed one level ("LV 16"). Now a finder entry counts only when it gives two different levels; otherwise the plan's range is shown. `/dp scan` now also records the first three raw returns, to learn the field order |
| Browse list (`C_LFGList`) | 77 activities with real ranges and instance map IDs: dungeons (Deadmines 17-26 map 36, Wailing Caverns 15-24, Hall of Thanes 13-20 map 3065, Ruins of Lordaeron 15-22 map 2999, ...), zones and Warsong Gulch. Ragefire Chasm is not listed for the scanning character (faction-filtered, inferred) | Preferred whenever it has the instance |
| Loading screens | Found (file IDs): Ragefire Chasm, Wailing Caverns, The Deadmines, Shadowfang Keep, Blackfathom Deeps, The Stockade, Gnomeregan, Razorfen Kraul and Downs, the four Scarlet Monastery wings, Uldaman, Zul'Farrak, Maraudon, the Temple of Atal'Hakkar, Blackrock Depths, both Blackrock Spires, the three Dire Maul wings, Scholomance, Zul'Gurub, Molten Core, Blackwing Lair, Naxxramas, and the Forever pictures of Excavation Site: Wetlands (7963777) and City of Dalaran (7963775). **None** under any tried name for: Hall of Thanes, Ruins of Lordaeron, Stratholme (both), Onyxia's Lair, Ruins and Temple of Ahn'Qiraj, Hyjal Summit, Shaper's Terrace, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, The Drowned City | Those thirteen show the drawn plate instead of the parchment. `/dp scan` now also checks a few more spellings (`GameFiles.PROBES`). **Found afterwards, offline** (below) |
| Maps | The classic dungeon uiMapIDs the plans carry (213, 221-229, 279, 291-292, 301-303, 310-316) have no map info at all; zone maps (1413, 1434, 1445-1451, 1422, 2548) have 12 tiles of 1002 x 668. Every one of the 77 old dungeon map tiles named in `Data/GameFiles.lua` exists | Per plan: the tiles for every classic floor; the grid for Hall of Thanes, Ruins of Lordaeron, Excavation Site, City of Dalaran, Hyjal Summit, Scholomance (its client map is the later layout, not used; a probe now records whether its old tiles exist), the first floors of Krol'dok, The Drowned City, Alcaz Prison and Shaper's Terrace, Blackmaw Hold's six inner floors and Upper Blackrock Spire's seventh |
| Fonts | English UI (`enUS`, setting Automatic): the game's `FRIZQT__.TTF`, as intended. WoW Po Polsku's `frizquadratatt_pl.ttf` opens (`true`). The bundled Alegreya Sans reported `false`. The first explanation (the file was added while the game ran) was wrong: it still read `false` after a full restart of the game. See "Fonts on this client" below | Superseded on 2026-11-16 by the font test (`UI/Fonts.lua`) |

### Fonts on this client (2026-11-16)

What was found, offline and in game:

- **Slug.** The client draws text with Slug (GPU outlines). At start it compiles the game's faces into
  `<game>\Fonts\<fileID>.slug`. An addon's `.ttf` is compiled the first time it is used and cached as
  `<game>\Fonts\override_<n>.slugo`, where `n` is the FNV-1a (32 bit) hash of the file's bytes. Two such files were
  present: one is `frizquadratatt_pl.ttf` ("My Font" in its name table, hash 2650015419), the other an installed
  nameplate addon's Roboto Condensed Bold (415871643). So the client reads the file's bytes to find the cache.
- **Alegreya Sans was never compiled.** No `override_3313091490.slugo` exists (that is the hash of
  `AlegreyaSans-Medium.ttf`). The file itself is fine: a static `glyf` TrueType font, all table checksums correct, every
  Polish letter present, and FreeType 2.13 opens it. Its tables are of the same kinds as Roboto Condensed's, which the
  client did compile (GSUB, GPOS, hinting).
- **Disabled addons.** With WoW Po Polsku enabled, its face read `true`, also at the login probe. Once WoW Po Polsku was
  disabled, it read `false`, although its compiled `.slugo` was still on disk. So the client does not open the files of a
  disabled addon. Dungeon Planner no longer tries that face then, and `/dp debug` says "WoW Po Polsku is disabled".
- **The probe pinned its first answer.** `Style.CanLoadFont` kept the first `false` for the whole session, and the
  Polish chain then never used the face, so nothing could change it. `/dp debug` also called a face that failed at the
  login probe "missing or damaged". The file did not support that claim.
- **The folder.** On the test machine, the addon folder is a directory junction to a development checkout. Lua files and
  the TGA textures load through it. Whether the font loader reads through it is the open question.

What changed: a failed probe is tried again on every call, and a face that works is kept. A face counts as usable when
a FontString's `SetFont` returns `true`, or when our own Font object draws Polish letters as wide as their plain twins
and at a width different from the game face's boxes. After the first loading screen, a Polish UI that has no face looks
again 3 seconds later and switches to a face that loads. `DPSans.ttf` is a cleaned copy of the same face (Latin subset,
no layout tables, no hinting, one format-4 cmap; `Media/Fonts/FONTLOG.txt`). It sits beside the original, so a problem
with the file can be told apart from a problem with the folder.

`/dp debug` shows a font test in its dialog, under the Polish letters test (one dialog, not a second panel over the
first). The test draws every face of the chain twice: set on the line
itself, and through our Font object. A few seconds later, it prints a second look and a verdict to chat. `/dp scan`
saves the same data in `diagnostics.fontTest`: the session's first probe, the probe now and the probe 2 seconds later.
For each probe it records SetFont's return, `GetFont()`, and the Polish and plain widths, both directly and through
the Font object. It also records controls: the game face, up to four other addons' fonts from LibSharedMedia, and
`Media/Chevron.tga`.

| Verdict in chat | Meaning | Next step |
|---|---|---|
| "The bundled fonts load." | The pinned probe was the cause (or a face loads only once it is drawn) | None |
| "DPSans.ttf loads but AlegreyaSans-Medium.ttf does not" | The client refuses the full file | The copy is used; the full file can go |
| "Other addons' fonts load, Dungeon Planner's do not" | The folder: on a junction install, the font loader does not read through the link | Install a real copy; players are not affected |
| "No addon font loads on this client" | No addon font loads, other addons' included | Look at `GetFont()` and the widths in the scan |

After the test, `<game>\Fonts\override_3313091490.slugo` (Alegreya Sans) or `override_1624575846.slugo` (`DPSans.ttf`)
shows whether the client compiled a face.

A Polish UI with no loadable Polish face stays Polish: the player chose it, and most letters render (ó and ł do).
The language dialog, and one chat line after login, say that ą ć ę ń ś ź ż will show as boxes. They point to
`/dp debug` and to English.
| Portraits | `EJ_GetCreatureInfo` and `SetPortraitTextureFromCreatureDisplayID` exist; the plans name 47 creatures by NPC ID but carry no display IDs | No change (skull fallback) |
| Errors | None of the scan's parts failed | - |

### The thirteen missing loading screens, found offline (build 70938, 2026-11-16)

Read from a local install with a CASC reader (read only) and the community listfile (wowdev/wow-listfile): `Map.db2`
gives each instance map a `LoadingScreens` row, and that row the picture's file ID. The names the scan tried were
simply not the game's:

| Instance | Map -> LoadingScreens row | File | In the client |
|---|---|---|---|
| Hall of Thanes | 3065 -> 693 | 7963781 (`camelot160\main\loadscreen_camelot_oldironforge`, 16:9) | Yes (local, same picture Dungeon Journal bundles) |
| Ruins of Lordaeron | 2999 -> 650 | 7963782 (`loadscreen_camelot_ruinsoflordaeron`, 16:9) | Yes (local) |
| Onyxia's Lair | 249 -> 61 | 131863 `LoadScreenRaid` | Yes (streamed on first use, like the Stockade's 131870) |
| Ruins of Ahn'Qiraj | 509 -> 184 | 131818 `LoadScreenAhnQiraj20man` | Yes (streamed) |
| Temple of Ahn'Qiraj | 531 -> 185 | 131819 `LoadScreenAhnQiraj40man` | Yes (streamed) |
| Stratholme (both wings) | 329 -> 101 | 131871 `LoadScreenStrathome` (the game's spelling) | Yes (streamed) |
| Hyjal Summit | no row with a picture (Hyjal Crater, 2995) | 131847 `LoadScreenHyjal` | Yes (streamed) |
| Shaper's Terrace, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, The Drowned City | rows in encrypted sections | 7963783, 7963780, 7963734, 7963784, 7963741 (listfile) | **Encrypted** until the dungeon opens: tried only once the Group Finder lists the instance; until then Dungeon Journal's card picture when installed, else the plate |

Forever's 16:9 loading screens are transparent above 0.16 and below 0.84 of their height; `GameFiles.AREA.loadingWide`
crops to that band. Group Finder backgrounds and Adventure Guide buttons for Onyxia, Ahn'Qiraj and Stratholme are in
the client too (`UI-EJ-DUNGEONBUTTON-*`, `UI-LFG-BACKGROUND-*`), but the loading screens come first, so they are not used.

### Maps from the minimap pictures (2026-11-16)

The client has the pictures its minimap draws inside every instance: per terrain tile (`MAID` in the map's WDT, 512 x
512, 533.33 yards) and per building part (the `WMOMinimapTexture` table: group, block x, block y -> file ID; 256 x 256,
128 yards, turned a quarter). Checked offline on build 70938 for all nine new dungeons: every one has its terrain
pictures (Hall of Thanes 81, Ruins of Lordaeron 9, Excavation Site 39, City of Dalaran 25, The Drowned City 24,
Krol'dok 12, Alcaz Prison 1, Blackmaw Hold 25, Shaper's Terrace 12), and the indoor floors have building pictures
(Blackmaw Hold's five caves, Alcaz Prison, Scholomance's 21, Dalaran's 95). Composed and drawn under the plans, the
routes run down the corridors on every floor checked (`tools/minimap_art.py`'s previews).

| Floor | Map now, without other addons |
|---|---|
| The Hall of Thanes, Ruins of Lordaeron, Excavation Site, City of Dalaran (city), The Drowned City, Krol'dok, Alcaz Prison, Shaper's Terrace, Blackmaw Grove | Terrain minimap pictures, north up |
| Blackmaw Hold's Festering Grotto, Fallen Grove, Burrow, Elders' Cavern, Forbidden Magic; Scholomance's four floors | Building minimap pictures of that floor's parts |
| City of Dalaran's Underbelly | Grid (its parts are mixed with the city's buildings in one WMO and the composition was not clean); another addon's map when installed |
| Hyjal Summit | Grid (not open yet; the client's "Hyjal Crater" map 2995 is not an instance) |

Drawn with `Texture:SetTexture(fileID)` and the eight-value `SetTexCoord`; a building turned by an angle that is not a
quarter (Dalaran 75 degrees, Blackmaw's Festering Grotto 5.5, Scholomance 1) uses `"CLAMPTOBLACKADDITIVE"` wrapping so
the corners of each piece's box stay empty. **In game untested**: the clamp mode, and that the client streams these
pictures to the UI like other textures. Since 2026-11-16 Santiago Reyes' maps ship with the addon and a drawn map (his,
else another addon's) comes first ("Prefer drawn maps over the game's minimap pictures", on by default; profiles saved
while it was off by default are set on once, `DB.ProviderMapsFirst`). `/dp debug` counts each source, `/dp scan` records every plan
floor's (`mapSources`).

Map order per plan floor (`MinimapArt.Choose`): the game's own map art (`C_Map`), the old dungeon map tiles
(classic dungeons), Santiago Reyes' bundled map, another addon's drawn map (Dungeon Journal, Forever Dungeon Routes,
OpenMap), the minimap pictures, then the parchment grid; with "Prefer drawn maps" off, the minimap pictures come before
the drawn maps. The bundled maps are BLP2 files with DXT1 blocks, three 1024 x 256 strips per map, no mipmaps (the
canvas draws with linear filtering). **In game untested**: that the client draws these files from the addon folder. The minimap pictures are drawn in the
parchment colours by default (`MapCanvas.ArtStyle`: `SetDesaturated`, a warm vertex colour, the same picture added on
top with `SetBlendMode("ADD")` to lift its mid greys, the parchment under it and a darkened edge,
`Media/Vignette.tga`); "Map colours: game minimap colours" draws them untouched. **In game untested**: `SetDesaturated`
and the ADD blend on these pictures.

Route chevrons are turned with the eight-value `SetTexCoord`, not `Texture:SetRotation`: with `SetRotation` every
chevron pointed up in game, whatever the path's direction (2026-11-16 screenshot of Ragefire Chasm).

## 10. What the client allows inside instances

Checked in game on build 70938 (Hall of Thanes, instance 3065, in a party, a hostile elite targeted) and from the
Retail 12.x rules Forever inherits. `/dp scan` records each row where it runs (`position`, `minimap` and `namePlates`
in the diagnostics).

| Reading | Inside an instance | Evidence | Used for |
|---|---|---|---|
| Player map position (`C_Map.GetBestMapForUnit`, `GetPlayerMapPosition`) | nil | In game, 2026-11-15 | Nothing |
| The player's floor (`GetBestMapForUnit`, its `C_Map.GetMapGroupID` and the group members' `relativeHeightIndex`, `GetInstanceInfo`'s 8th value, `IsIndoors`) | **Unverified.** Our 2026-11-15 scan in Hall of Thanes found no best map; another addon's shipped recorder expects a uiMap inside Forever's new dungeons and logs the map group and height index as they change | `/dp scan` records all of them inside any instance (`position`: `bestMap`, `mapGroup`, `mapGroupMembers`, `instanceMapID`, `indoors`) | When a map comes back: the map section switches to the player's floor (on a change of floor only, inside an instance; `Floors.PlayerFloor`, `UI/Panels/FloorBar.lua`), and run mode's mini map says which floor the player is on. Until a scan shows one, nothing switches |
| World position (`UnitPosition`) | x and y nil, only the instance ID | In game | Nothing |
| Creature GUID and name (`UnitGUID`, `UnitName` on an enemy) | secret | In game; Fellowship Ledger's check | Names are stored only when plain |
| Hostility, level, classification (`UnitCanAttack`, `UnitLevel`, `UnitClassification`) | readable | In game | The run recorder's pull make-up |
| Nameplates (`C_NamePlate.GetNamePlates`) | the plates of nearby enemies, each with its unit token (inferred) | Retail API; `/dp scan` records the count and which fields read | The run recorder's enemy counts, every 0.5 s during combat only |
| Combat start and end, encounters (`PLAYER_REGEN_*`, `ENCOUNTER_END`, `BOSS_KILL`) | available | Verified (section 3) | Pull segments, boss kills, wipes |
| Facing (`GetPlayerFacing`) | nil in instances on Retail since 7.1 (inferred for Forever) | `/dp scan` records it | Nothing inside; outdoors it turns the live Getting there map's arrow |
| Minimap ping offset (`Minimap:GetPingPosition`) | an offset from the player in minimap units (inferred) | `/dp scan` records it | Nothing |
| The minimap's dungeon layout | drawn by the game inside the `Minimap` frame; its pixels cannot be read, but the pictures it is drawn from are ordinary textures | Seen in game; the files checked offline (section 9) | The maps of floors without map art (section 9) |

What follows from it:

| Idea | Verdict | Why |
|---|---|---|
| Record pulls, their size and make-up, bosses, wipes, timing | **Feasible, built** (opt-in run recorder) | Everything it needs is readable; nothing secret is stored |
| Place recorded pulls on the map | Not feasible | No position of the player or of any creature can be read |
| Turn nameplate screen positions into map positions | Not feasible | A screen position is the world seen through the camera; without the player's position and the camera's position, rotation and zoom it cannot be turned back into a place on the floor |
| Minimap pings relative to a known spot (stand on a step, ping a pack) | Not feasible as a feature | The offset comes in minimap units that depend on the zoom and the indoor scale and turn with a rotating minimap; without facing and the floor's size in yards it cannot be put on our map, and without the player's position two pings cannot be related to each other. `/dp scan` records `GetPlayerFacing` and `GetPingPosition` so a later client that changes this would show it |
| Show the game's minimap in our window as a live map of floors without art | Not built | The `Minimap` frame belongs to the Edit Mode layout (`MinimapCluster`); moving or reparenting it fights Edit Mode and the addons that re-anchor it (Leatrix Plus hooks `MinimapCluster` and moves `Minimap`), carries every LibDBIcon minimap button and the minimap pins of HereBeDragons-based addons (HandyNotes, TomTom, Questie) along into our window, and would have to be restored exactly on close, combat, `/reload` and logout. Changing another system's frame risks tainting Edit Mode. The risk to other addons outweighs a picture the player already has on screen; with the data providers, Hall of Thanes and the other new dungeons now get a real map anyway |

## Sources

- Local install (read-only): `.build.info`, `_forever_/.flavor.info`, `Interface/AddOns/*/*.toc` and the Lua files named
  above, `Logs/FrameXML.log`, BugGrabber's captured error messages.
- warcraft.wiki.gg, Patch 1.60.1/API changes: https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes
- warcraft.wiki.gg, Patch 1.60.1/API changes/notes: https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes
- Kami Labs, WoW Forever addons restricted like Midnight: https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/
- Icy Veins, Addons in WoW Forever: https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/
- WoW Po Polsku on CurseForge: https://www.curseforge.com/wow/addons/forever-wowpopolsku-2-0 ; glossary: https://wowpopolsku.pl/o-grze/slowniczek/
- OpenMap: https://github.com/openmap-world/openmap ; Dungeon Journal: https://www.curseforge.com/wow/addons/dungeonjournal
- Libraries: docs/LIBRARIES.md
- ForeverPlusPlus (MIT): https://github.com/xIGBClutchIx/ForeverPlusPlus (`docs/forever-api.md`, `Lib/DungeonMaps.lua`)
- ryna_agent (MIT), Forever client API notes: https://github.com/MaddisonM79/ryna_agent (`docs/forever-client-api.md`)
- Fellowship Ledger (MIT), verify report: https://github.com/TankerALane/fellowship-ledger
- AdventureGuideClassic (GPL-3.0, read for facts only): https://github.com/fooxytv/AdventureGuideClassic
- Blizzard UI source, `forever` branch: https://github.com/Gethe/wow-ui-source/tree/forever
