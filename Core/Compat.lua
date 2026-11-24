-- Feature detection. Every API that docs/COMPATIBILITY.md marks "inferred" is checked here, and features degrade when
-- one is missing. `/dp debug` prints this report plus the offline self-tests, so the first in-game run tells us exactly
-- what this client has.

local _, ns = ...
local Compat = ns:NewModule("Compat")

-- A dotted path ("C_Map.GetMapInfo") is set under root (the global table unless given).
local function has(path, root)
	local value = root or _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return false
		end
		value = value[part]
	end
	return value ~= nil
end

-- name, path, what degrades when missing
Compat.CHECKS = {
	{ "Map info", "C_Map.GetMapInfo", "map names" },
	{ "Map art layers", "C_Map.GetMapArtLayers", "map art (grid canvas instead)" },
	{ "Map art textures", "C_Map.GetMapArtLayerTextures", "map art (grid canvas instead)" },
	{ "Map groups (floors)", "C_Map.GetMapGroupID", "multi-floor maps" },
	{ "Map group members", "C_Map.GetMapGroupMembersInfo", "multi-floor maps" },
	{ "Current map", "C_Map.GetBestMapForUnit", "\"current zone\" plans" },
	{ "Journal tiers", "EJ_GetNumTiers", "instance list from the journal" },
	{ "Journal instances", "EJ_GetInstanceByIndex", "instance list from the journal" },
	{ "Journal select", "EJ_SelectInstance", "boss lists" },
	{ "Journal encounters", "EJ_GetEncounterInfoByIndex", "boss lists" },
	{ "Journal for map", "EJ_GetInstanceForMap", "matching the current zone to the journal" },
	{ "Instance info", "GetInstanceInfo", "run tracking" },
	{ "Addon messages", "C_ChatInfo.SendAddonMessage", "in-game sharing (export strings still work)" },
	{ "Addon prefix", "C_ChatInfo.RegisterAddonMessagePrefix", "in-game sharing" },
	{ "Messaging lockdown check", "C_ChatInfo.InChatMessagingLockdown", "lockdown detection (refused sends are still counted)" },
	{ "Outgoing addon message restriction check", "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
		"restriction detection (refused sends are still counted)" },
	{ "Send result codes", "Enum.SendAddonMessageResult", "throttle detection" },
	{ "Settings panel", "Settings.RegisterCanvasLayoutCategory", "options in the game's AddOns settings" },
	{ "Context menus", "MenuUtil.CreateContextMenu", "right-click menus and the plan menu" },
	{ "Timers", "C_Timer.NewTicker", "sharing and deferred work" },
	{ "Addon metadata", "C_AddOns.GetAddOnMetadata", "version string" },
	{ "Secret values", "issecretvalue", "nothing (pre-Midnight client)" },
	{ "Pixel util", "PixelUtil.GetNearestPixelSize", "exact 1 px lines" },
	{ "Item info", "C_Item.GetItemInfo", "item names in gear lists" },
	{ "Item loading", "C_Item.RequestLoadItemDataByID", "item names that are not cached yet (else the item mixin)" },
	{ "Group roles", "UnitGroupRolesAssigned", "roles in the roster" },
	{ "Group leader", "UnitIsGroupLeader", "sending raid pages (nobody counts as leader)" },
	{ "Raid assistant", "UnitIsGroupAssistant", "raid assistants sending pages" },
	-- Player names (Share/Roster.lua): who a message came from, by the whole name.
	{ "Unit name, unmodified", "UnitNameUnmodified", "surnames told from the player's UnitName alone" },
	{ "Surname separator", "Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR",
		"a space between first name and surname" },
	{ "Realm name, normalized", "GetNormalizedRealmName", "the realm from GetRealmName" },
	{ "Realm name", "GetRealmName", "no own realm: every realm suffix on a sender counts as another realm" },
	{ "One-shot timers", "C_Timer.After", "group sync's timed sends (a change waits for the next one)" },
	{ "Unit class", "UnitClass", "names in class colour on raid pages" },
	{ "Class colours", "RAID_CLASS_COLORS", "names in class colour on raid pages" },
	{ "Class icons", "CLASS_ICON_TCOORDS", "class icons on raid pages (class names instead)" },
	{ "Chat pacing", "ChatThrottleLib", "posting raid pages to chat (spaced timers instead)" },
	{ "Class info", "GetClassInfo", "class filter in gear lists" },
	-- The game-native window (version 2): pictures, portraits and positions from the journal, art checks.
	{ "Journal instance art", "EJ_GetInstanceInfo", "instance pictures on the home cards (parchment instead)" },
	{ "Journal boss portraits", "EJ_GetCreatureInfo", "boss portraits (the journal's blank face instead)" },
	{ "Journal map pins", "EJ_GetMapEncounter", "boss positions from the Adventure Guide on plans without bosses" },
	{ "Model portraits", "SetPortraitTextureFromCreatureDisplayID", "portraits for bosses without a journal icon" },
	{ "Dungeon finder levels", "GetLFGDungeonInfo", "level ranges (from recommended plans instead)" },
	{ "Quest difficulty colours", "GetQuestDifficultyColor", "level ranges coloured by difficulty (gold instead)" },
	{ "Atlas lookup", "C_Texture.GetAtlasInfo", "atlas art (the classic texture files instead)" },
	{ "File lookup", "GetFileIDFromPath", "the art check in this report" },
	{ "Backdrops", "BackdropTemplateMixin", "the game's frame borders (flat borders instead)" },
	{ "Item quality", "C_Item.GetItemQualityByID", "quality colours in loot rows" },
	-- Journal loot (Data/Loot.lua) and the plan-to-journal resolver (Data/Journal.lua).
	{ "Journal tier names", "EJ_GetTierInfo", "tier names in /dp scan" },
	{ "Journal current tier", "EJ_GetCurrentTier", "restoring the Adventure Guide's tier after a scan" },
	{ "Journal boss select", "EJ_SelectEncounter", "loot per boss (the whole instance's loot instead)" },
	{ "Journal loot count", "EJ_GetNumLoot", "loot from the Adventure Guide (the plan's own gear list only)" },
	{ "Journal loot items", "C_EncounterJournal.GetLootInfoByIndex", "loot from the Adventure Guide (older call tried)" },
	{ "Journal loot filter", "EJ_SetLootFilter", "loot for one class (everyone's loot instead)" },
	{ "Journal loot filter read", "EJ_GetLootFilter", "putting the Adventure Guide's loot filter back" },
	{ "Spell names", "C_Spell.GetSpellName", "boss ability names (\"Spell <id>\" instead)" },
	{ "Spell icons", "C_Spell.GetSpellTexture", "boss ability icons (a question mark instead)" },
	{ "Item types", "C_Item.GetItemInfoInstant", "the Gear page's class and slot filters (the global GetItemInfoInstant instead)" },
	{ "Item types, older call", "GetItemInfoInstant", "the Gear page's class and slot filters where C_Item lacks it" },
	{ "Specializations of a class", "GetSpecializationInfoForClassID", "the role filter for Adventure Guide loot" },
	{ "Chat links", "ChatEdit_InsertLink", "Shift-click to link an item in chat" },
	{ "Mouse buttons", "IsMouseButtonDown", "route arrows after a lost size-grip release come back when the window hides" },
	-- Sources used because WoW: Forever's Adventure Guide is empty (Data/GameFiles.lua, Data/Diagnostics.lua).
	{ "Dungeon finder order", "GetLFDChoiceOrder", "the dungeon finder's list (a bounded ID scan instead)" },
	{ "Group Finder activities", "C_LFGList.GetAvailableActivities", "level ranges of Forever's new dungeons" },
	{ "Group Finder activity info", "C_LFGList.GetActivityInfoTable", "level ranges of Forever's new dungeons" },
	-- Only that the function is present: whether it answers for an instance ID is an in-game check (docs/UI.md).
	{ "Instance names by ID (present)", "GetRealZoneText",
		"plans saved with a localized instance name and no instance ID (matched by the Group Finder's names only)" },
	{ "Game rules", "C_GameRules.IsGameRuleActive", "/dp scan's journal check" },
	{ "Load on demand", "C_AddOns.LoadAddOn", "/dp scan's journal check" },
	{ "Journal open notice", "C_EncounterJournal.OnOpen", "/dp scan's journal check" },
	-- /dp scan's spawn-recording check (Data/Diagnostics.lua): can a position and a target be read in a dungeon?
	{ "In an instance", "IsInInstance", "/dp scan's position check" },
	{ "World position", "UnitPosition", "/dp scan's position check" },
	{ "Sub-zone name", "GetSubZoneText", "/dp scan's position check" },
	{ "Unit GUID", "UnitGUID", "/dp scan's target check" },
	{ "Unit classification", "UnitClassification", "/dp scan's target check" },
	{ "Unit hostility", "UnitCanAttack", "/dp scan's target check" },
	-- The run recorder (Tracker/Recorder.lua): what it reads inside instances.
	{ "Nameplates", "C_NamePlate.GetNamePlates", "enemy counts in recorded pulls (pulls are only timed)" },
	{ "Unit in combat", "UnitAffectingCombat", "telling pulled enemies from idle ones (every hostile plate counts)" },
	{ "Unit dead", "UnitIsDead", "leaving dead enemies out of a pull's count" },
	{ "Unit dead or ghost", "UnitIsDeadOrGhost", "deaths and wipes in recorded pulls" },
	{ "Unit level", "UnitLevel", "level ranges of recorded pulls" },
	{ "Minimap zone text", "GetMinimapZoneText", "sub-zone names of recorded pulls" },
	{ "Player facing", "GetPlayerFacing", "the live map's arrow turning (it points up), /dp scan's position check" },
	{ "Indoors", "IsIndoors", "/dp scan's position check" },
	-- The kill messages' format strings (Recorder.KILL_TEXTS): each one missing is one message not read.
	{ "Kill message: experience", "COMBATLOG_XPGAIN_FIRSTPERSON", "names of enemies you fought from experience messages" },
	{ "Kill message: experience, group", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "names of enemies you fought from experience messages" },
	{ "Kill message: experience, raid", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "names of enemies you fought from experience messages" },
	{ "Kill message: death", "UNITDIESOTHER", "names of enemies you fought from death messages" },
	-- Bosses already dead when you join, and instance resets (Tracker/Tracker.lua).
	{ "Instance lock", "GetInstanceLockTimeRemaining", "bosses already dead when you join (marked killed in the run)" },
	{ "Instance lock bosses", "GetInstanceLockTimeRemainingEncounter", "bosses already dead when you join (marked killed in the run)" },
	{ "Raid info request", "RequestRaidInfo", "fresh lock data on entering (the game's own update is waited for)" },
	{ "Reset message", "INSTANCE_RESET_SUCCESS", "ending a run when its instance is reset (a boss that starts again after its kill still does)" },
	-- /dp scan's restriction probes (Data/Diagnostics.lua): recorded, nothing is built on them.
	{ "Secrets API", "C_Secrets", "/dp scan's secrets check" },
	{ "Addon restriction state", "C_RestrictedActions.GetAddOnRestrictionState", "/dp scan's secrets check" },
	{ "Unit distance", "UnitDistanceSquared", "/dp scan's secrets check" },
	-- /dp perf (Core/Perf.lua) and the report window (Core/Report.lua).
	{ "Addon profiler", "C_AddOnProfiler.GetAddOnMetric", "the game's own timings in /dp perf" },
	{ "Addon memory", "C_AddOns.GetAddOnMemoryUsage", "memory use in /dp perf" },
	{ "Profile clock", "debugprofilestop", "precise timings in /dp perf (the Lua clock instead)" },
	-- The gamepad interface style (Compat.Gamepad below).
	{ "Interface style", "C_InputInterfaceStyle.GetCurrentStyle", "gamepad detection from the CVar (or the setting)" },
	{ "Interface style values", "Enum.InputInterfaceStyle.Gamepad", "gamepad detection only from the setting" },
	{ "Console variables", "C_CVar.GetCVar", "gamepad detection without the CVar (GetCVar tried)" },
	-- Prep (Data/PrepInfo.lua): quests, keys, the group.
	{ "Quest completed", "C_QuestLog.IsQuestFlaggedCompleted", "Prep's done quests and attunements (shown as unknown)" },
	{ "Quest in log", "C_QuestLog.IsOnQuest", "Prep's \"In your log\" (the log index is tried instead)" },
	{ "Quest log index", "C_QuestLog.GetLogIndexForQuestID", "Prep's \"In your log\"" },
	{ "Quest titles", "C_QuestLog.GetTitleForQuestID", "quest names in your language (the bundled English names instead)" },
	{ "Item counts", "C_Item.GetItemCount", "Prep's keys you carry (GetItemCount is tried instead)" },
	{ "Faction", "UnitFactionGroup", "hiding the other faction's quests" },
	{ "Group size", "GetNumGroupMembers", "Prep's raid members" },
	{ "Unit exists", "UnitExists", "Prep's party members" },
	-- The party strip (Data/PartyInfo.lua): who sits in which seat.
	{ "Unit online", "UnitIsConnected", "offline members are not dimmed in the party strip" },
	{ "Specialization count", "C_SpecializationInfo.GetNumSpecializationsForClassID",
		"role guesses from class in the party strip (GetNumSpecializationsForClassID is tried instead)" },
	{ "Area names", "C_Map.GetAreaInfo",
		"zone names of Questie's quest givers; the map's You are here marker in areas the game's area table names" },
	{ "Zone text", "GetZoneText", "the map's You are here marker where a sub-zone is named like the dungeon" },
	{ "Bit operations", "bit.bxor", "nothing: the room-name hash of the You are here marker is computed without it" },
	-- Getting there (Data/Travel.lua, Data/Navigation.lua): outdoors only.
	{ "World to map", "C_Map.GetMapPosFromWorldPos", "the entrance's coordinates on its zone map" },
	{ "Map to world", "C_Map.GetWorldPosFromMapPos", "distances, flight masters near Forever's new dungeons" },
	{ "Player map position", "C_Map.GetPlayerMapPosition", "distance and direction to the entrance" },
	{ "Map vectors", "CreateVector2D", "the world and map conversions (a plain table instead)" },
	{ "Map pin", "C_Map.SetUserWaypoint", "the game's own waypoint (another navigation addon still works)" },
	{ "Map pin check", "C_Map.CanSetUserWaypointOnMap", "checking a zone takes a pin" },
	{ "Map points", "UiMapPoint.CreateFromCoordinates", "the game's own waypoint" },
	{ "Super-tracking", "C_SuperTrack.SetSuperTrackedUserWaypoint", "the pin's arrow on screen (the pin still shows)" },
	{ "Open world map", "C_Map.OpenWorldMap", "\"Show on world map\" opening the map (the pin is still set)" },
}

function Compat.Has(path)
	return has(path)
end

-- Texture and frame methods are checked on a real object.
function Compat.Methods()
	local out = {}
	if CreateFrame then
		local f = CreateFrame("Frame")
		local tex = f:CreateTexture()
		out[#out + 1] = { "Lines", f.CreateLine ~= nil, "drawn routes (listed only)" }
		out[#out + 1] = { "Resize bounds", f.SetResizeBounds ~= nil, "window minimum size" }
		out[#out + 1] = { "Clip children", f.SetClipsChildren ~= nil, "map clipping" }
		out[#out + 1] = { "Mask textures", f.CreateMaskTexture ~= nil, "round portraits and icons (square instead)" }
		out[#out + 1] = { "Texture rotation", tex.SetRotation ~= nil, "route arrows pointing along the path" }
		out[#out + 1] = { "Atlases", tex.SetAtlas ~= nil, "atlas art (texture files instead)" }
		-- Dropdown lists and the instance picker (UI/Popup.lua).
		local mouse = pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
		f:UnregisterAllEvents()
		out[#out + 1] = { "Global mouse events", mouse, "closing dropdown lists on an outside click (a screen catcher instead)" }
		out[#out + 1] = { "Keyboard pass-through", f.SetPropagateKeyboardInput ~= nil,
			"arrow keys in dropdown lists without a search field" }
		-- Events only some features listen to (Tracker/Recorder.lua, Tracker/Tracker.lua): the client raises on an event it
		-- does not know.
		local NAMES = "names of enemies you fought in recorded pulls"
		for _, event in ipairs({ { "CHAT_MSG_COMBAT_XP_GAIN", NAMES }, { "CHAT_MSG_COMBAT_HOSTILE_DEATH", NAMES },
			{ "UNIT_SPELLCAST_SENT", NAMES }, { "PARTY_KILL", "the count of enemies the group killed in recorded pulls" },
			{ "UPDATE_INSTANCE_INFO", "bosses already dead when you join (the lock is read on entering and after a kill)" },
			{ "PLAYER_LEAVING_WORLD", "a run resuming after a /reload or a logout inside its instance" },
			{ "PLAYER_LOGOUT", "a run resuming after a logout inside its instance" },
			{ "INSTANCE_LOCK_START","bosses already dead when you join (read again when the game shows the lock prompt)" },
			{ "CHAT_MSG_SYSTEM", "ending a run when its instance is reset (a boss that starts again after its kill still does)" } }) do
			local known = pcall(f.RegisterEvent, f, event[1])
			out[#out + 1] = { "Event " .. event[1], known, event[2] }
		end
		f:UnregisterAllEvents()
		f:Hide()
	end
	return out
end

function Compat.Report()
	local rows = {}
	for _, check in ipairs(Compat.CHECKS) do
		rows[#rows + 1] = { name = check[1], ok = has(check[2]), path = check[2], degrades = check[3] }
	end
	for _, m in ipairs(Compat.Methods()) do
		rows[#rows + 1] = { name = m[1], ok = m[2], path = "(method)", degrades = m[3] }
	end
	-- Files an update added: the client reads an addon's file list only when the game starts (docs/COMPATIBILITY.md
	-- section 7), so after an update without a restart they are missing and their features stay off.
	for _, file in ipairs(Compat.FILES) do
		rows[#rows + 1] = { name = "Addon file " .. file[1], ok = has(file[2], ns), path = "(file)",
			degrades = file[3] .. " - restart the game after updating" }
	end
	return rows
end

-- file, what it defines (a module, or a dotted path in ns for a file that adds functions to one), what is missing
-- without it
Compat.FILES = {
	{ "Model/RouteLook.lua", "RouteLook", "route lines on the map" },
	{ "UI/MapRoutes.lua", "MapRoutes", "route lines on the map" },
	{ "UI/OpenMapOverlay.lua", "OpenMapOverlay", "the experimental plan on OpenMap's dungeon map" },
	{ "UI/FontTest.lua", "Style.RunFontTest", "the font test in /dp debug and /dp scan" },
	{ "UI/RunLines.lua", "RunMode.RecorderText", "run mode's recorder, drift and prep lines" },
	{ "Share/SendStats.lua", "SendStats", "counting refused addon messages (sharing and group sync do not say so)" },
	{ "Data/SubzoneData.lua", "SubzoneData", "the map's You are here marker" },
	{ "Data/Subzones.lua", "Subzones", "the map's You are here marker" },
	{ "UI/MapHere.lua", "MapHere", "the map's You are here marker" },
}

-- The gamepad interface style. With it on, registering a slash command sets off blocked protected calls that end in a
-- client freeze (an empty slash command is enough), and the gamepad menus read and close the frames in UISpecialFrames
-- (seen in another addon's shipped code, docs/COMPATIBILITY.md). Detected once, every call guarded: the setting
-- (settings.gamepad "on" / "off") when the player chose one, else C_InputInterfaceStyle.GetCurrentStyle(), else the
-- CVar InputDeviceInterfaceStyle; both compare with Enum.InputInterfaceStyle.Gamepad, and without that value nothing is
-- guessed (off). While it is on, Dungeon Planner registers no slash command, puts nothing in UISpecialFrames, adds no
-- entries to other addons' menus and opens no world map; the way in is the minimap button, the Addon Compartment and
-- the key bindings. Returns on, how ("setting" | "api" | "cvar" | "none").
local gamepad
function Compat.Gamepad()
	if gamepad then
		return gamepad.on, gamepad.how
	end
	local Plain = ns.Util.Plain
	local on, how = false, "none"
	local choice = ns.db and ns.db.settings.gamepad
	local api, enum = rawget(_G, "C_InputInterfaceStyle"), rawget(_G, "Enum")
	local styles = type(enum) == "table" and type(enum.InputInterfaceStyle) == "table" and enum.InputInterfaceStyle or nil
	local want = styles and Plain(styles.Gamepad) or nil
	if choice == "on" or choice == "off" then
		on, how = choice == "on", "setting"
	elseif want ~= nil and type(api) == "table" and type(api.GetCurrentStyle) == "function" then
		local ok, style = pcall(api.GetCurrentStyle)
		style = ok and Plain(style) or nil
		if style ~= nil then
			on, how = style == want, "api"
		end
	end
	if how == "none" and tonumber(want) then
		local cvars = rawget(_G, "C_CVar")
		local get = type(cvars) == "table" and cvars.GetCVar or rawget(_G, "GetCVar")
		if type(get) == "function" then
			local ok, value = pcall(get, "InputDeviceInterfaceStyle")
			value = ok and tonumber(Plain(value)) or nil
			if value ~= nil then
				on, how = value == tonumber(want), "cvar"
			end
		end
	end
	gamepad = { on = on, how = how }
	return on, how
end

-- Detect again (tests).
function Compat.ResetGamepad()
	gamepad = nil
end

-- Client identity, for bug reports.
function Compat.ClientInfo()
	local version, build, date, toc = "?", "?", "?", 0
	if GetBuildInfo then
		version, build, date, toc = GetBuildInfo()
	end
	return {
		version = version,
		build = build,
		date = date,
		toc = toc,
		project = WOW_PROJECT_ID,
		isForever = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18),
		locale = GetLocale and GetLocale() or "?",
	}
end

-- In-game self-tests of the pure modules (the same checks tests/ run offline). Returns a list of { name, ok, detail }.
function Compat.SelfTest()
	local results = {}
	local function check(name, fn)
		local ok, detail = pcall(fn)
		results[#results + 1] = { name = name, ok = ok and detail ~= false, detail = ok and "" or tostring(detail) }
	end
	check("Libraries present", function()
		for _, name in ipairs({ "LibDeflate", "LibSerialize", "AceComm-3.0", "AceDB-3.0", "CallbackHandler-1.0" }) do
			assert(LibStub and LibStub(name, true), name .. " not registered")
		end
	end)
	check("LibSerialize round trip", function()
		local LibSerialize = LibStub("LibSerialize")
		local value = { a = 1, b = "x^|y", c = { 1.25, true, false }, [3] = "three" }
		local ok, back = LibSerialize:Deserialize(LibSerialize:Serialize(value))
		assert(ok and back.a == 1 and back.b == "x^|y" and back.c[1] == 1.25 and back.c[3] == false and back[3] == "three")
	end)
	check("Export and import a plan", function()
		local plan = ns.Plan.New({ name = "Self-test" })
		ns.Plan.AddMarker(plan, 1, 0.25, 0.5, "boss", "Test boss")
		local pull = ns.Plan.AddPull(plan)
		local m = ns.Plan.AddMarker(plan, 1, 0.3, 0.6, "pack")
		ns.Plan.UpdateMarker(plan, m.id, { pull = pull.id })
		local text = assert(ns.Codec.ExportPlan(plan))
		local kind, back = ns.Codec.Decode(text)
		assert(kind == "plan", back)
		assert(#back.markers == 2 and back.markers[2].pull == pull.id)
	end)
	check("Bounded inflate rejects garbage", function()
		local out = ns.Inflate.Raw("\255\255\255\255", 1000)
		assert(out == nil)
	end)
	check("Validation strips escapes", function()
		local plan = ns.Validate.Plan({ name = "|cffff0000Red|r |TInterface\\Icons\\x:0|t name" })
		assert(plan.name == "Red  name", plan.name)
	end)
	return results
end
