-- The game's own files and tables, for what the Adventure Guide does not give on WoW: Forever. Forever's journal is
-- empty (EJ_GetNumTiers() returns 0: the client has no JournalInstance or JournalEncounter tables and the game rule
-- EncounterJournalDisabled is on; docs/COMPATIBILITY.md section 9), so instance pictures, dungeon maps and level ranges
-- come from here instead. Nothing is shipped: these are file names of textures that are in the client and are drawn
-- at runtime, each checked with GetFileIDFromPath before use (a missing one is simply skipped).
--
--   Instance pictures: the instance's loading screen (Interface\Glues\LoadingScreens\LoadScreen<Name>), or the Group
--     Finder's background for it (GetLFGDungeonInfo's background texture); where the game has neither, an installed
--     addon's own picture (Providers.InstanceArt, credited, never copied), else the caller's drawn plate.
--   Dungeon maps: the original dungeon map art, still in the client as textures although the client has no dungeon
--     UiMap: Interface\WorldMap\<Dir>\<Name><floor>_1 .. 12, a 4 x 3 grid of 256 px tiles of which the last column uses
--     234 px and the last row 156 px (1002 x 668: the same layout, and so the same 0..1 coordinates, as the dungeon
--     maps' art layer on the classic clients).
--   Level ranges and instance map IDs: the Group Finder (the dungeon finder's GetLFGDungeonInfo list, and the browse
--     list C_LFGList.GetAvailableActivities + GetActivityInfoTable, which also has Forever's new dungeons).
--
-- Where the names come from: the map tile names are ForeverPlusPlus's list (MIT, Lib/DungeonMaps.lua,
-- https://github.com/xIGBClutchIx/ForeverPlusPlus), which checked the Deadmines' first tile in game (file 449591);
-- loading-screen names are the ones the installed Dungeon Journal addon shows on this client, plus the same pattern for
-- the rest, all checked at runtime. `/dp scan` records which of them this client has.
-- The loading screens of the instances whose names do not follow the pattern were found in the client's own tables
-- (build 70938, read offline from a local install): Map.db2 gives each instance map its LoadingScreens row, and that row
-- the file. Hall of Thanes (map 3065) -> row 693 -> 7963781; Ruins of Lordaeron (2999) -> 650 -> 7963782; Onyxia's Lair
-- (249) -> 61 -> LoadScreenRaid; Ruins of Ahn'Qiraj (509) -> 184 -> LoadScreenAhnQiraj20man; Ahn'Qiraj Temple (531) ->
-- 185 -> LoadScreenAhnQiraj40man; Stratholme (329) -> 101 -> LoadScreenStrathome (sic). Hyjal Summit has no map row
-- with a loading screen; LoadScreenHyjal is the game's own Mount Hyjal picture. The file names are the community
-- listfile's (wowdev/wow-listfile); each name's hash and file ID were checked in the client's root.

local _, ns = ...
local GameFiles = ns:NewModule("GameFiles")
local Util, Match = ns.Util, ns.Match

local LOADING = "Interface\\Glues\\LoadingScreens\\"
local WORLDMAP = "Interface\\WorldMap\\"

-- Which part of a picture to show (u0, u1, v0, v1) and that part's width / height, for UI cropping.
GameFiles.AREA = {
	loading = { 0.02, 0.98, 0.2, 0.84, (0.96 * 4) / (0.64 * 3) }, -- a 4:3 loading screen without its logo band
	-- Forever's own 16:9 loading screens: the picture is the opaque band from 0.16 to 0.84 (2992 x 1684 files, rows 268
	-- to 1415 opaque, measured offline on all four); above and below it the file is transparent.
	loadingWide = { 0, 1, 0.16, 0.84, 16 / (9 * 0.68) },
	finder = { 0, 1, 0, 1, 2 }, -- the Group Finder's background
}

-- Per instance, by name (Match.StripArticle): loading screens to try first (paths, or file IDs that the Dungeon
-- Journal addon draws on this client, or that the client's LoadingScreens table names), and the map tile names of each
-- floor, in the order of the classic dungeon maps. `locked`: loading screens of Forever dungeons that are not out yet;
-- the client has the files but encrypted (build 70938) until the dungeon opens, so they are tried only once the Group
-- Finder lists the instance (file IDs from the community listfile, beside Forever's other loading screens).
-- Instances not listed still get "LoadScreen<Name>" tried. The floor order was checked against the game's own map
-- tables: the file ID of each floor's first tile is the one its UiMap's art names (ShadowfangKeep6_ is Lord Godfrey's
-- Chamber, uiMap 315; ShadowfangKeep7_ the Wall Walk, 316), so every floor of every plan gets the map of its name.
local function floors(dir, name, n)
	local out = {}
	for i = 1, n do
		out[i] = dir .. "\\" .. name .. i .. "_"
	end
	return out
end

GameFiles.INSTANCES = {
	ragefirechasm = { tiles = { "Ragefire\\Ragefire1_" } },
	wailingcaverns = { tiles = floors("WailingCaverns", "WailingCaverns", 1) },
	deadmines = { tiles = floors("TheDeadmines", "TheDeadmines", 2) },
	shadowfangkeep = { screens = { "LoadScreenShadowFangKeep" }, tiles = floors("ShadowfangKeep", "ShadowfangKeep", 7) },
	stockade = { screens = { 131870, "LoadScreenStormwindStockade" }, tiles = floors("TheStockade", "TheStockade", 1) },
	stormwindstockade = { alias = "stockade" },
	stormwindstockades = { alias = "stockade" },
	blackfathomdeeps = { tiles = floors("BlackFathomDeeps", "BlackFathomDeeps", 3) },
	gnomeregan = { tiles = floors("Gnomeregan", "Gnomeregan", 4) },
	razorfenkraul = { screens = { 131865 }, tiles = floors("RazorfenKraul", "RazorfenKraul", 1) },
	razorfendowns = { screens = { "LoadScreenRazorfenDowns", "LoadScreenRazorfenDown" },
		tiles = floors("RazorfenDowns", "RazorfenDowns", 1) },
	scarletmonasterygraveyard = { screens = { "LoadScreenScarletMonastery2", "LoadScreenScarletMonastery" },
		tiles = { "ScarletMonastery\\ScarletMonastery1_" } },
	scarletmonasterylibrary = { screens = { "LoadScreenScarletMonastery", "LoadScreenMonastery" },
		tiles = { "ScarletMonastery\\ScarletMonastery2_" } },
	scarletmonasteryarmory = { screens = { "LoadScreenScarletMonastery", "LoadScreenMonastery" },
		tiles = { "ScarletMonastery\\ScarletMonastery3_" } },
	scarletmonasterycathedral = { screens = { "LoadScreenScarletMonastery", "LoadScreenMonastery" },
		tiles = { "ScarletMonastery\\ScarletMonastery4_" } },
	uldaman = { tiles = floors("Uldaman", "Uldaman", 2) },
	zulfarrak = { screens = { "LoadScreenZulFarrak", "LoadScreenZulfarrak" }, tiles = { "ZulFarrak\\ZulFarrak" } },
	maraudon = { tiles = floors("Maraudon", "Maraudon", 2) },
	templeofatalhakkar = { screens = { "LoadScreenSunkenTemple" },
		tiles = floors("TheTempleOfAtalHakkar", "TheTempleOfAtalHakkar", 1) },
	sunkentemple = { alias = "templeofatalhakkar" },
	blackrockdepths = { tiles = floors("BlackrockDepths", "BlackrockDepths", 2) },
	lowerblackrockspire = { screens = { "LoadScreenBlackrockSpire" }, tiles = floors("BlackrockSpire", "BlackrockSpire", 6) },
	upperblackrockspire = { screens = { "LoadScreenBlackrockSpire" }, tiles = floors("BlackrockSpire", "BlackrockSpire", 6) },
	diremauleast = { screens = { "LoadScreenDireMaul" }, tiles = { "DireMaul\\DireMaul5_", "DireMaul\\DireMaul6_" } },
	diremaulwest = { screens = { "LoadScreenDireMaul" },
		tiles = { "DireMaul\\DireMaul2_", "DireMaul\\DireMaul3_", "DireMaul\\DireMaul4_" } },
	diremaulnorth = { screens = { "LoadScreenDireMaul" }, tiles = { "DireMaul\\DireMaul1_" } },
	stratholmelivemaingate = { screens = { "LoadScreenStrathome" }, tiles = floors("Stratholme", "Stratholme", 2) },
	stratholmeundeadserviceentrance = { screens = { "LoadScreenStrathome" }, tiles = floors("Stratholme", "Stratholme", 2) },
	scholomance = {}, -- the client's map art is the later layout: none
	moltencore = { tiles = floors("MoltenCore", "MoltenCore", 1) },
	blackwinglair = { tiles = floors("BlackwingLair", "BlackwingLair", 4) },
	onyxiaslair = { screens = { "LoadScreenRaid" }, tiles = floors("OnyxiasLair", "OnyxiasLair", 1) },
	zulgurub = { tiles = { "ZulGurub\\ZulGurub" } },
	ruinsofahnqiraj = { screens = { "LoadScreenAhnQiraj20man" },
		tiles = { "RuinsofAhnQiraj\\RuinsofAhnQiraj" } },
	templeofahnqiraj = { screens = { "LoadScreenAhnQiraj40man" },
		tiles = floors("AhnQiraj", "AhnQiraj", 3) },
	ahnqirajtemple = { alias = "templeofahnqiraj" },
	naxxramas = { tiles = floors("Naxxramas", "Naxxramas", 6) },
	hyjalsummit = { screens = { "LoadScreenHyjal" } },
	excavationsitewetlands = { screens = { 7963777 }, wide = true },
	cityofdalaran = { screens = { 7963775 }, wide = true },
	hallofthanes = { screens = { 7963781 }, wide = true }, -- loadscreen_camelot_oldironforge
	ruinsoflordaeron = { screens = { 7963782 }, wide = true }, -- loadscreen_camelot_ruinsoflordaeron
	shapersterrace = { locked = { 7963783 }, wide = true },
	kroldokstronghold = { locked = { 7963780 }, wide = true },
	alcazprison = { locked = { 7963734 }, wide = true },
	blackmawhold = { locked = { 7963784 }, wide = true },
	drownedcity = { locked = { 7963741 }, wide = true },
}

-- Other spellings /dp scan checks (recorded only): loading screens of Forever's new dungeons, and Scholomance's
-- floor tiles (the client's Scholomance map is the later layout, which does not fit the plans' coordinates).
GameFiles.PROBES = {
	LOADING .. "LoadScreenHyjal",
	LOADING .. "LoadScreenRaid",
	LOADING .. "LoadScreenStrathome",
	LOADING .. "LoadScreenAhnQiraj20man",
	LOADING .. "LoadScreenAhnQiraj40man",
	LOADING .. "Camelot160\\Main\\loadscreen_camelot_oldironforge",
	LOADING .. "Camelot160\\Main\\loadscreen_camelot_ruinsoflordaeron",
	WORLDMAP .. "Scholomance\\Scholomance1_1",
	WORLDMAP .. "HallOfThanes\\HallOfThanes1_1",
	WORLDMAP .. "RuinsOfLordaeron\\RuinsOfLordaeron1_1",
}

-- Name -> table key. "The Deadmines" -> "deadmines".
local function key(name)
	local k = Match.StripArticle(name)
	return k ~= "" and k or nil
end
GameFiles.Key = key

local function spec(name)
	local k = key(name)
	local s = k and GameFiles.INSTANCES[k]
	if s and s.alias then
		return GameFiles.INSTANCES[s.alias], s.alias
	end
	return s, k
end

-- "Scarlet Monastery: Library" -> "ScarletMonasteryLibrary" (letters and digits of each word, capitalised).
local function camel(name)
	local out = {}
	for word in tostring(name or ""):gsub("'", ""):gmatch("[%w]+") do
		out[#out + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(out)
end
GameFiles.Camel = camel

-- Is a texture in the client? true / false, or nil when the client cannot tell (no GetFileIDFromPath).
local exists = {}
function GameFiles.Exists(file)
	if type(file) == "number" then
		return file > 0
	end
	if type(file) ~= "string" or file == "" then
		return false
	end
	if exists[file] == nil then
		if type(GetFileIDFromPath) ~= "function" then
			return nil
		end
		local ok, id = pcall(GetFileIDFromPath, file)
		id = ok and Util.Plain(id) or nil
		exists[file] = type(id) == "number" and id > 0 or false
	end
	return exists[file]
end

-- The file ID of a texture path, or nil when the client lacks it or cannot tell.
local fileIDs = {}
function GameFiles.FileID(file)
	if type(file) ~= "string" or file == "" or type(GetFileIDFromPath) ~= "function" then
		return nil
	end
	if fileIDs[file] == nil then
		local ok, id = pcall(GetFileIDFromPath, file)
		id = ok and Util.Plain(id) or nil
		fileIDs[file] = Util.IsInteger(id) and id > 0 and id or false
	end
	return fileIDs[file] or nil
end

-- The file ID of a plan floor's first map tile (nil without tiles or without the client's answer).
function GameFiles.FloorTileID(plan, index)
	local tiles = type(plan) == "table" and plan.instance and GameFiles.MapTiles(plan.instance.name)
	local base = tiles and tiles[index]
	return base and GameFiles.FileID(WORLDMAP .. base .. "1") or nil
end

-- The loading screens to try for an instance name, in order (paths or file IDs). A locked one (INSTANCES) comes first
-- once the Group Finder lists the instance.
function GameFiles.LoadingScreenCandidates(name)
	local s = spec(name)
	local list, seen = {}, {}
	local function add(v)
		if v and not seen[v] then
			seen[v] = true
			list[#list + 1] = type(v) == "string" and not v:find("\\", 1, true) and (LOADING .. v) or v
		end
	end
	if s and s.locked and GameFiles.FinderFor(name) then
		for _, v in ipairs(s.locked) do
			add(v)
		end
	end
	for _, v in ipairs(s and s.screens or {}) do
		add(v)
	end
	local stripped = (tostring(name or ""):gsub("^%s*[Tt][Hh][Ee]%s+", ""))
	add("LoadScreen" .. camel(stripped))
	add("LoadScreen" .. camel(name))
	local base = tostring(name or ""):match("^(.-)%s*[:%(]")
	if base and base ~= "" then
		add("LoadScreen" .. camel((base:gsub("^%s*[Tt][Hh][Ee]%s+", ""))))
	end
	return list, s and s.wide
end

-- Pictures for an instance (a home entry or plan instance { name }), best first: { { file, area, source, credit? } }.
-- The game's files first (only files the client has; unknown when it cannot tell: then the loading screens named in the
-- table are tried), then an installed addon's own picture (Providers.InstanceArt). Without any the list is empty and the
-- caller draws its plate.
local pictureCache = {}
local function providerEpoch()
	return ns.Providers and ns.Providers.epoch or 0
end
function GameFiles.InstancePictures(inst)
	local name = type(inst) == "table" and inst.name or nil
	local k = key(name)
	if not k then
		return {}
	end
	local cached = pictureCache[k]
	if cached and cached.epoch == providerEpoch() then
		return cached.list
	end
	local out = {}
	local candidates, wide = GameFiles.LoadingScreenCandidates(name)
	for _, file in ipairs(candidates) do
		local known = GameFiles.Exists(file)
		if known or (known == nil and type(file) == "number") then
			out[#out + 1] = { file = file, area = wide and GameFiles.AREA.loadingWide or GameFiles.AREA.loading,
				source = "loading" }
			break
		end
	end
	local hit = GameFiles.FinderFor(name)
	if hit and hit.texture then
		out[#out + 1] = { file = hit.texture, area = GameFiles.AREA.finder, source = "finder" }
	end
	local provided = ns.Providers and ns.Providers.InstanceArt and ns.Providers.InstanceArt(name)
	if provided then
		out[#out + 1] = provided
	end
	pictureCache[k] = { epoch = providerEpoch(), list = out }
	return out
end

-- Dungeon maps ------------------------------------------------------------------------------------------------------------

local TILE, COLUMNS, ROWS = 256, 4, 3
GameFiles.MAP_WIDTH = TILE * (COLUMNS - 1) + 234
GameFiles.MAP_HEIGHT = TILE * (ROWS - 1) + 156

-- The tile names of an instance's floors (nil without any), by instance name.
function GameFiles.MapTiles(name)
	local s = spec(name)
	return s and s.tiles or nil
end

-- Art for one floor's tile name, in the shape Instances.MapArt returns, or nil when the client lacks the first tile.
local tileArt = {}
function GameFiles.TileArt(base)
	if type(base) ~= "string" then
		return nil
	end
	if tileArt[base] == nil then
		local first = WORLDMAP .. base .. "1"
		if GameFiles.Exists(first) == false then
			tileArt[base] = false
		else
			local textures = {}
			for i = 1, COLUMNS * ROWS do
				textures[i] = WORLDMAP .. base .. i
			end
			tileArt[base] = { width = GameFiles.MAP_WIDTH, height = GameFiles.MAP_HEIGHT, tileWidth = TILE,
				tileHeight = TILE, textures = textures, source = "tiles", base = base }
		end
	end
	return tileArt[base] or nil
end

-- The tile art for floor `index` of a plan, or nil. A named floor at position i gets the instance's i-th map; an
-- unnamed floor (the zone outside, stored with its own map ID) gets none. A floor the map adds (Data/Floors.lua) gets
-- the map at its own position in the instance's art (artIndex).
function GameFiles.FloorArt(plan, index)
	local floor = type(plan) == "table" and plan.floors and plan.floors[index]
	if not floor then
		return nil
	end
	local pos = floor.artIndex or index
	local tiles = GameFiles.MapTiles(plan.instance and plan.instance.name)
	if not tiles or not tiles[pos] then
		return nil
	end
	if (floor.name or "") == "" and floor.uiMapID then
		return nil
	end
	return GameFiles.TileArt(tiles[pos])
end

-- Group Finder ------------------------------------------------------------------------------------------------------------
-- GetLFGDungeonInfo(id) -> name, typeID, subtypeID, minLevel, maxLevel, recLevel, minRecLevel, maxRecLevel,
--   expansionLevel, groupID, backgroundTexture, difficulty, maxPlayers, description, isHoliday, bonusRepAmount,
--   minPlayers, isTimeWalker, name2, minGear, isScalingDungeon, lfgMapID (Retail order; the forever branch's LFGFrame.lua
--   reads the same). The ids come from GetLFDChoiceOrder() when the client has it, else a bounded scan.
-- C_LFGList.GetActivityInfoTable(id) -> { fullName, shortName, categoryID, minLevelSuggestion, maxLevelSuggestion,
--   mapID, ... } for C_LFGList.GetAvailableActivities() (the browse list; Forever's new dungeons are only there).

local finder -- { list = { entry }, byKey = {}, byMap = {} }

-- Does a finder entry give a real range (two different levels)? On Forever the dungeon finder list gives one level per
-- dungeon ("16-16" for the Deadmines, /dp scan 2026-11-15) while the browse list gives the range ("17-26").
local function ranged(e)
	return e ~= nil and e.minLevel ~= nil and e.maxLevel ~= nil and e.maxLevel > e.minLevel
end
GameFiles.HasRange = ranged

-- Keep the first entry per name and map ID, unless a later one gives a range and the kept one does not.
local function keep(map, k, entry)
	local old = map[k]
	if not old or (ranged(entry) and not ranged(old)) then
		map[k] = entry
	end
end

local function addFinder(entry)
	entry.key = key(entry.name)
	if not entry.key then
		return
	end
	finder.list[#finder.list + 1] = entry
	keep(finder.byKey, entry.key, entry)
	-- The finder's own name for an instance ("Sunken Temple") also answers for the name the plans use.
	local known = GameFiles.INSTANCES[entry.key]
	if known and known.alias then
		keep(finder.byKey, known.alias, entry)
	end
	if entry.mapID then
		keep(finder.byMap, entry.mapID, entry)
	end
end

local function int(v)
	v = Util.Plain(v)
	return Util.IsInteger(v) and v > 0 and v or nil
end

GameFiles.rawLfd = {} -- the first few raw GetLFGDungeonInfo returns, for /dp scan (the order differs on Forever)

local function readLfd(id)
	local r = { pcall(GetLFGDungeonInfo, id) }
	if not r[1] then
		return nil
	end
	if #GameFiles.rawLfd < 3 and r[2] ~= nil then
		local parts = {}
		for i = 2, math.min(#r, 26) do
			local x = Util.Plain(r[i])
			parts[#parts + 1] = (i - 1) .. "=" .. tostring(x)
		end
		GameFiles.rawLfd[#GameFiles.rawLfd + 1] = id .. ": " .. table.concat(parts, " ")
	end
	local name = Util.Plain(r[2])
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local lo, hi = int(r[8]), int(r[9])
	if not lo then
		lo, hi = int(r[5]), int(r[6])
	end
	local tex = Util.Plain(r[12])
	if not ((type(tex) == "string" and tex ~= "") or (type(tex) == "number" and tex > 0)) then
		tex = nil
	end
	return { id = id, name = name, typeID = int(r[3]), subtypeID = int(r[4]), minLevel = lo,
		maxLevel = hi and lo and hi >= lo and hi or lo, mapID = int(r[23]), texture = tex, source = "lfd" }
end

function GameFiles.Finder()
	if finder then
		return finder
	end
	finder = { list = {}, byKey = {}, byMap = {} }
	if type(GetLFGDungeonInfo) == "function" then
		local ids
		if type(GetLFDChoiceOrder) == "function" then
			local ok, order = pcall(GetLFDChoiceOrder)
			if ok and type(order) == "table" and #order > 0 then
				ids = order
			end
		end
		if ids then
			for _, raw in ipairs(ids) do
				local id = int(raw)
				local e = id and readLfd(id)
				if e then
					addFinder(e)
				end
			end
		else
			local misses = 0
			for id = 1, 4000 do
				local e = readLfd(id)
				if e then
					misses = 0
					addFinder(e)
				else
					misses = misses + 1
					if misses > 600 and id > 1000 then
						break
					end
				end
			end
		end
	end
	if C_LFGList and type(C_LFGList.GetAvailableActivities) == "function" and type(C_LFGList.GetActivityInfoTable) == "function" then
		local ok, ids = pcall(C_LFGList.GetAvailableActivities)
		if ok and type(ids) == "table" then
			for i = 1, math.min(#ids, 500) do
				local okI, info = pcall(C_LFGList.GetActivityInfoTable, ids[i])
				if okI and type(info) == "table" then
					local name = Util.Plain(info.fullName)
					local lo, hi = int(info.minLevelSuggestion), int(info.maxLevelSuggestion)
					if type(name) == "string" and name ~= "" then
						addFinder({ id = ids[i], name = name, minLevel = lo, maxLevel = hi and lo and hi >= lo and hi or lo,
							mapID = int(info.mapID), categoryID = int(info.categoryID), source = "activity" })
					end
				end
			end
		end
	end
	return finder
end

-- The Group Finder's entry for an instance name: the same name (without "The"), else the one entry whose name
-- contains this one or is contained in it ("The Stockade" / "Stormwind Stockades"). nil when none or ambiguous.
function GameFiles.FinderFor(name, mapID)
	local f = GameFiles.Finder()
	if mapID and f.byMap[mapID] then
		return f.byMap[mapID]
	end
	local k = key(name)
	if not k then
		return nil
	end
	if f.byKey[k] then
		return f.byKey[k]
	end
	local s, sk = spec(name)
	if s and sk ~= k and f.byKey[sk] then
		return f.byKey[sk]
	end
	local stem = k:gsub("s$", "")
	if #stem < 6 then
		return nil
	end
	local hit
	for _, e in ipairs(f.list) do
		local other = e.key:gsub("s$", "")
		if other:find(stem, 1, true) or stem:find(other, 1, true) then
			if hit and hit.key ~= e.key then
				return nil
			end
			hit = hit or f.byKey[e.key] or e
		end
	end
	return hit
end

-- The level range to show for an instance (pure): the Group Finder's when it gives two different levels, else the
-- plan's range, else the finder's single level. hit = a finder entry or nil; entry = { levelMin?, levelMax? }.
-- Returns min, max or nil.
function GameFiles.ResolveRange(hit, entry)
	if ranged(hit) then
		return hit.minLevel, hit.maxLevel
	end
	if entry and entry.levelMin then
		return entry.levelMin, entry.levelMax or entry.levelMin
	end
	if hit and hit.minLevel then
		return hit.minLevel, hit.maxLevel or hit.minLevel
	end
	return nil
end

-- For tests: forget everything read.
function GameFiles.Reset()
	exists, pictureCache, tileArt, finder, fileIDs = {}, {}, {}, nil, {}
	GameFiles.rawLfd = {}
end
