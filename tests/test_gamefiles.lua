-- WoW: Forever's empty Adventure Guide and what replaces it (Data/GameFiles.lua, Data/Diagnostics.lua): loading-screen
-- pictures, the old dungeon map tiles, Group Finder level ranges, the boss face fallback, the Gear page's message,
-- and the extended /dp scan. The mock's journal is emptied here (EJ_GetNumTiers() = 0, as on Forever) and put back.
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

local savedTiers
local function emptyJournal()
	savedTiers = savedTiers or mock.journal.tiers
	mock.journal.tiers = {}
	ns.Journal.Reset()
	ns.GameFiles.Reset()
end

local function restoreJournal()
	mock.journal.tiers = savedTiers
	ns.Journal.Reset()
	ns.GameFiles.Reset()
	mock.files = {}
	mock.gameRules = nil
end

local LOADING = "Interface\\Glues\\LoadingScreens\\"

T.case("Empty journal (Forever): no instances, no loot, the raw tier count kept", function()
	boot()
	emptyJournal()
	T.eq(#ns.Journal.GetAll().list, 0)
	T.eq(ns.Journal.lastScan.tiers, 0, "EJ_GetNumTiers() = 0 is not counted as one tier")
	T.eq(ns.Journal.lastScan.rawTiers, 0)
	T.eq(ns.Journal.HasData(), false)
	T.eq(ns.Loot.APIAvailable(), true, "the functions exist")
	T.eq(ns.Loot.Available(), false, "but there is nothing to read")
	restoreJournal()
	T.ok(ns.Journal.HasData())
end)

T.case("Instance pictures: the loading screen the client has, else the parchment", function()
	boot()
	emptyJournal()
	mock.files[(LOADING .. "LoadScreenDeadmines"):lower()] = 1
	local pics = ns.GameFiles.InstancePictures({ name = "The Deadmines" })
	T.eq(pics[1] and pics[1].file, LOADING .. "LoadScreenDeadmines", "derived name, checked with GetFileIDFromPath")
	T.eq(pics[1].source, "loading")
	-- A file ID from the table needs no lookup.
	T.eq(ns.GameFiles.InstancePictures({ name = "Razorfen Kraul" })[1].file, 131865)
	-- Shadowfang Keep's file is spelled differently from its name.
	T.eq(ns.GameFiles.LoadingScreenCandidates("Shadowfang Keep")[1], LOADING .. "LoadScreenShadowFangKeep")
	local tex = _G.DungeonPlannerMainFrame:CreateTexture()
	T.eq(ns.Home.SetInstanceArt(tex, { name = "The Deadmines" }, "card", 200, 100), true)
	T.eq(tex:GetTexture(), LOADING .. "LoadScreenDeadmines")
	T.eq(ns.Home.SetInstanceArt(tex, { name = "Nowhere Keep" }, "card", 200, 100), false, "parchment")
	restoreJournal()
end)

T.case("Dungeon maps: the game's old map tiles for a floor without an art layer", function()
	boot()
	emptyJournal()
	local plan = ns.Bundled.Get("b:the-deadmines")
	T.ok(plan, "recommended Deadmines plan")
	T.eq(ns.GameFiles.FloorArt(plan, 1), nil, "no tile in the client: nothing")
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	ns.GameFiles.Reset() -- (the client's files do not change in a session: lookups are cached)
	local art = ns.GameFiles.FloorArt(plan, 1)
	T.ok(art, "tiles found")
	T.eq(#art.textures, 12)
	T.eq(art.width, 1002)
	T.eq(art.height, 668)
	T.eq(art.textures[12], "Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_12")
	-- The map page draws them.
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("map")
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	T.eq(canvas.artInfo and canvas.artInfo.source, "tiles")
	T.eq(canvas.noArt:IsShown(), false, "no 'no map art' note")
	-- The Hall of Thanes has no map in the game: grid.
	T.eq(ns.GameFiles.FloorArt(ns.Bundled.Get("b:hall-of-thanes"), 1), nil)
	restoreJournal()
end)

T.case("Group Finder: levels by name, Forever's browse list, loose names", function()
	boot()
	emptyJournal()
	local lo, hi = ns.Instances.LevelRange({ name = "Hall of Forever Tests" })
	T.eq(lo, 13)
	T.eq(hi, 20)
	T.eq(ns.GameFiles.FinderFor("Hall of Forever Tests").mapID, 3065)
	T.eq(ns.GameFiles.FinderFor("Forever Tests").name, "Hall of Forever Tests", "one name contains the other")
	T.eq(ns.GameFiles.FinderFor("Test"), nil, "too short to guess")
	lo = ns.Instances.LevelRange({ name = "Unknown Place", levelMin = 30, levelMax = 40 })
	T.eq(lo, 30, "the plan's range otherwise")
	restoreJournal()
end)

T.case("A boss without a portrait shows a skull icon, not a question mark", function()
	boot()
	local tex = _G.DungeonPlannerMainFrame:CreateTexture()
	ns.Art.SetBossPortrait(tex, nil)
	T.ok(tostring(tex:GetTexture()):find("HumanSkull", 1, true), "skull icon")
end)

T.case("Gear page says the game has no loot lists when the journal is empty", function()
	boot()
	ns.BossData.enabled = false -- the bundled drops would be listed otherwise
	emptyJournal()
	local plan = ns.Bundled.Get("b:the-deadmines")
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("gear")
	local gear = _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
	gear:Refresh()
	T.ok(gear.status:GetText():find("no loot lists", 1, true), gear.status:GetText())
	restoreJournal()
end)

T.case("/dp scan records the journal checks, Group Finder, maps, game files and fonts", function()
	boot()
	emptyJournal()
	mock.gameRules = { [77] = true }
	mock.files[(LOADING .. "LoadScreenDeadmines"):lower()] = 5
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	if mock.loadedAddons then
		mock.loadedAddons.Blizzard_EncounterJournal = nil
	end
	ns.Slash.Handle("scan")
	local d = _G.DungeonPlannerDB.diagnostics
	T.ok(d, "saved")
	T.eq(#d.errors, 0, "no part failed: " .. table.concat(d.errors, "; "))
	T.ok(d.journal.before:find("tiers 0", 1, true), d.journal.before)
	T.eq(d.journal.encounterJournalDisabled, "true")
	T.ok(d.journal.load and d.journal.load:find("LoadAddOn true", 1, true), "Blizzard_EncounterJournal loaded")
	T.ok(d.journal.afterLoad, "counted again after loading")
	mock.Advance(3.1)
	T.ok(d.journal.after3s, "and 3 seconds later")
	T.ok(d.finder.count >= 2, "dungeon finder and browse list")
	local sawActivity = false
	for _, row in ipairs(d.finder.rows) do
		if row:find("Hall of Forever Tests", 1, true) and row:find("3065", 1, true) then
			sawActivity = true
		end
	end
	T.ok(sawActivity, "browse list row with its instance map ID")
	T.ok(d.maps.byId["291"], "plans' map IDs")
	T.ok(d.tiles["deadmines 1"]:find("449591", 1, true), "tile probe")
	T.ok(d.loadingScreens["The Deadmines"]:find("LoadScreenDeadmines=5", 1, true), "loading-screen probe")
	T.ok(d.portraits.modelPortrait, "portrait APIs")
	T.ok(d.fonts.file, "UI font")
	T.ok(d.plans["b:the-deadmines"]:find("+tiles", 1, true), "plan floors with tiles")
	ns.Slash.Handle("scan clear")
	restoreJournal()
end)

T.case("Level ranges: the finder's range only when it gives two levels, else the plan's", function()
	boot()
	emptyJournal()
	-- Pure rule.
	local GF = ns.GameFiles
	local lo, hi = GF.ResolveRange({ minLevel = 17, maxLevel = 26 }, { levelMin = 16, levelMax = 20 })
	T.eq(lo, 17)
	T.eq(hi, 26)
	lo, hi = GF.ResolveRange({ minLevel = 16, maxLevel = 16 }, { levelMin = 17, levelMax = 26 })
	T.eq(lo, 17, "one finder level loses to the plan's range")
	T.eq(hi, 26)
	lo, hi = GF.ResolveRange({ minLevel = 13, maxLevel = 13 }, nil)
	T.eq(lo, 13, "one level when nothing else is known")
	T.eq(hi, 13)
	T.eq(GF.ResolveRange(nil, nil), nil)
	-- As on Forever (/dp scan 2026-11-15): the dungeon finder gives one level, the browse list the range.
	local lfd, activities, info = _G.GetLFGDungeonInfo, _G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable
	_G.GetLFGDungeonInfo = function(id)
		if id == 5 then
			return "Deadmines", nil, nil, 16, 16
		elseif id == 3 then
			return "Ragefire Chasm", nil, nil, 13, 13
		end
		return nil
	end
	_G.C_LFGList.GetAvailableActivities = function()
		return { 799 }
	end
	_G.C_LFGList.GetActivityInfoTable = function(id)
		if id == 799 then
			return { fullName = "Deadmines", minLevelSuggestion = 17, maxLevelSuggestion = 26, mapID = 36 }
		end
		return nil
	end
	GF.Reset()
	lo, hi = ns.Instances.LevelRange({ name = "The Deadmines", levelMin = 15, levelMax = 25 })
	T.eq(lo, 17, "the browse list's range wins over the dungeon finder's one level")
	T.eq(hi, 26)
	lo, hi = ns.Instances.LevelRange({ name = "Ragefire Chasm", levelMin = 13, levelMax = 18 })
	T.eq(lo, 13, "one finder level: the plan's range")
	T.eq(hi, 18)
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	lo, hi = ns.Instances.LevelRange(plan.instance)
	T.eq(lo, plan.instance.levelMin, "recommended plan keeps its range")
	T.eq(hi, plan.instance.levelMax)
	_G.GetLFGDungeonInfo, _G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable = lfd, activities, info
	restoreJournal()
end)

T.case("Dungeon maps: each floor gets the tiles of its own name (Shadowfang Keep 6 and 7)", function()
	boot()
	local plan = ns.Bundled.Get("b:shadowfang-keep")
	T.ok(plan, "recommended Shadowfang Keep plan")
	T.eq(plan.floors[6].name, "Lord Godfrey's Chamber")
	T.eq(plan.floors[7].name, "The Wall Walk")
	local tiles = ns.GameFiles.MapTiles(plan.instance.name)
	-- The game's map tables: ShadowfangKeep6_ is Lord Godfrey's Chamber (uiMap 315), ShadowfangKeep7_ the Wall Walk (316).
	for i = 1, 7 do
		T.eq(tiles[i], "ShadowfangKeep\\ShadowfangKeep" .. i .. "_", "floor " .. i .. " in the game's order")
	end
	mock.files[("Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep6_1"):lower()] = 448286
	ns.GameFiles.Reset()
	T.eq(ns.GameFiles.FloorArt(plan, 6).base, "ShadowfangKeep\\ShadowfangKeep6_")
	T.eq(ns.GameFiles.FloorTileID(plan, 6), 448286, "the first tile's file ID")
	T.eq(ns.GameFiles.FloorTileID(plan, 7), nil, "a tile the client lacks: no ID")
	-- Another spelling of the Temple of Ahn'Qiraj (Forever Dungeon Routes' name) finds its tiles.
	T.eq(ns.GameFiles.MapTiles("Ahn'Qiraj Temple")[1], "AhnQiraj\\AhnQiraj1_")
	ns.GameFiles.Reset()
end)

T.case("Instance pictures: the game's file first, then an addon's own picture, then the plate", function()
	boot()
	emptyJournal()
	mock.RemoveProviders()
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	local GF = ns.GameFiles
	local function first(name)
		local p = GF.InstancePictures({ name = name })[1]
		return p and p.file, p
	end
	-- Names that do not follow LoadScreen<Name>: the files the client's own LoadingScreens table names.
	local file, pic = first("Hall of Thanes")
	T.eq(file, 7963781, "Hall of Thanes: Forever's loading screen by file ID")
	T.eq(pic.area, GF.AREA.loadingWide, "16:9, cropped to its opaque band")
	T.eq(first("Ruins of Lordaeron"), 7963782)
	for name, screen in pairs({ ["Onyxia's Lair"] = "LoadScreenRaid", ["Ruins of Ahn'Qiraj"] = "LoadScreenAhnQiraj20man",
		["Temple of Ahn'Qiraj"] = "LoadScreenAhnQiraj40man", ["Hyjal Summit"] = "LoadScreenHyjal",
		["Stratholme: Live (Main Gate)"] = "LoadScreenStrathome" }) do
		T.eq(first(name), nil, name .. ": nothing while the client lacks the file")
		mock.files[(LOADING .. screen):lower()] = 131800
		GF.Reset()
		T.eq(first(name), LOADING .. screen, name)
		T.eq(select(2, first(name)).area, GF.AREA.loading, name .. ": a 4:3 loading screen")
	end
	-- A dungeon that is not out yet: its loading screen is encrypted, so not tried; nothing else: the plate.
	T.eq(first("Blackmaw Hold"), nil, "not listed in the Group Finder: no picture")
	local tex = _G.DungeonPlannerMainFrame:CreateTexture()
	T.eq(ns.Home.SetInstanceArt(tex, { name = "Blackmaw Hold" }, "card", 56, 30), false, "the plate")
	-- With the Dungeon Journal installed, its own card picture comes next (credited); its game paths are not taken.
	mock.InstallProviders()
	local fdj = _G.ForeverDungeonJournal_NS
	fdj.DUNGEON_HOME_ART = {
		["Blackmaw Hold"] = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldHome",
		["Hall of Thanes"] = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\HallOfThanes.tga",
		["Ragefire Chasm"] = "Interface\\Glues\\LoadingScreens\\LoadScreenRagefireChasm",
	}
	fdj.DUNGEON_HOME_TEXCOORD = { ["Blackmaw Hold"] = { 0, 1, 0.06, 0.94 } }
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	file, pic = first("Blackmaw Hold")
	T.eq(file, "Interface\\AddOns\\ForeverDungeonJournal\\Media\\BlackmawHoldHome", "the addon's picture")
	T.eq(pic.source, "provider")
	T.eq(pic.credit, "Dungeon Journal")
	T.eq(pic.area[3], 0.06)
	T.ok(math.abs(pic.area[5] - 2 / 0.88) < 1e-9, "a 2:1 file without its top and bottom bands")
	local has, credit = ns.Home.SetInstanceArt(tex, { name = "Blackmaw Hold" }, "card", 56, 30)
	T.eq(has, true)
	T.eq(credit, "Dungeon Journal")
	T.eq(first("Ragefire Chasm"), nil, "a game path in its table is not its own picture")
	local hot = GF.InstancePictures({ name = "Hall of Thanes" })
	T.eq(hot[1].file, 7963781, "the game's file before the addon's")
	T.eq(hot[2] and hot[2].source, "provider", "the addon's picture after it")
	-- The preview plate names the addon whose picture it shows.
	local plate = ns.Home.ArtPlate(_G.DungeonPlannerMainFrame)
	plate:SetSize(300, 150)
	plate:SetEntry({ name = "Blackmaw Hold" })
	T.eq(plate.creditText, "Picture: Dungeon Journal")
	plate:SetEntry({ name = "Hall of Thanes" })
	T.eq(plate.creditText, nil, "the game's own picture needs no credit")
	plate:Hide()
	-- Once the Group Finder lists it (the dungeon is out, its file can be read), its own loading screen comes first.
	local activities, info = _G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable
	_G.C_LFGList.GetAvailableActivities = function()
		return { 1201, 1299 }
	end
	_G.C_LFGList.GetActivityInfoTable = function(id)
		if id == 1299 then
			return { fullName = "Blackmaw Hold", minLevelSuggestion = 40, maxLevelSuggestion = 48, mapID = 3999 }
		end
		return info(id)
	end
	GF.Reset()
	local bmh = GF.InstancePictures({ name = "Blackmaw Hold" })
	T.eq(bmh[1].file, 7963784, "its loading screen, by file ID")
	T.eq(bmh[1].area, GF.AREA.loadingWide)
	T.eq(bmh[2].source, "provider")
	_G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable = activities, info
	GF.Reset()
	-- Switching the provider off drops its picture (the cache follows the providers).
	ns.Providers.SetEnabled("dungeonJournal", false)
	local off = first("Blackmaw Hold")
	ns.Providers.SetEnabled("dungeonJournal", true)
	T.eq(off, nil, "provider off: the plate again")
	mock.RemoveProviders()
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	restoreJournal()
end)
