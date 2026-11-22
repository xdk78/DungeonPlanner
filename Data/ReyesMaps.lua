-- Santiago Reyes' maps of WoW: Forever's new dungeons ("Atlas de Azeroth: Forever", sreyesmaps.com), bundled with his
-- permission. The pictures are his: (c) Santiago Reyes, NOT under the project's MIT licence (that covers the code
-- only; docs/licenses/SantiagoReyes-maps.md). They are shown unchanged with his title and signature, and credited on
-- the map ("Map by Santiago Reyes", MapCanvas).
--
-- Media/Maps/Reyes/<file>1..3.blp: each map scaled to 1024 x 683 (the crop the Dungeon Journal and Forever Dungeon
-- Routes addons draw the same pictures with) in three strips of 1024 x 256 (tools/reyes_maps.py). Plan coordinates
-- (0..1 over that picture) are the same as on those addons' maps, so routes and markers land in the same places.
--
-- Map order (Data/MinimapArt.lua Choose): the game's map art, the old dungeon map tiles (classic dungeons), these maps,
-- another addon's drawn map, the game's minimap pictures, the grid. With "Prefer drawn maps" off, the minimap pictures
-- come before these maps.

local _, ns = ...
local ReyesMaps = ns:NewModule("ReyesMaps")

ReyesMaps.ARTIST = "Santiago Reyes"
ReyesMaps.SITE = "sreyesmaps.com"
ReyesMaps.DONATE = "sreyesmaps.com/donaciones"
ReyesMaps.FOLDER = "Interface\\AddOns\\DungeonPlanner\\Media\\Maps\\Reyes\\"
ReyesMaps.WIDTH, ReyesMaps.HEIGHT, ReyesMaps.STRIP = 1024, 683, 256

-- [instance key (GameFiles.Key)] = its floors in the order of the recommended plan's: file (Media/Maps/Reyes/<file>N),
-- label (the floor's name), names (other names a plan floor may have), and the same picture's file name in the Dungeon
-- Journal (dj) and Forever Dungeon Routes (fdr) addons, so their boss pins and routes can be shown on it.
-- keepOut: where the picture has painted names (its title, room names, the signature), as { x1, y1, x2, y2 } over the
-- picture (0..1, measured on the published file): the map's labels go elsewhere when they can (UI/MapCanvas.lua).
ReyesMaps.DUNGEONS = {
	hallofthanes = {
		{ file = "HallOfThanes", label = "The Hall of Thanes", dj = "hallofthanesmap", fdr = "hallofthanes",
			keepOut = {
				{ 0.374, 0.045, 0.663, 0.112 }, -- HALL OF THANES
				{ 0.550, 0.195, 0.633, 0.246 }, -- RELIQUARY OF KINGS
				{ 0.635, 0.421, 0.716, 0.475 }, -- DARK IRON INGRESS
				{ 0.414, 0.702, 0.501, 0.753 }, -- ANVILMAR'S REST
				{ 0.650, 0.920, 0.990, 0.960 }, -- the signature
			} },
	},
	ruinsoflordaeron = {
		{ file = "RuinsOfLordaeron", label = "Ruins of Lordaeron", dj = "ruinsoflordaeronmap", fdr = "ruinsoflordaeron" },
	},
	excavationsitewetlands = {
		{ file = "ExcavationSite", label = "Excavation Site: Wetlands", dj = "excavationsitemap", fdr = "excavationsite" },
	},
	cityofdalaran = {
		{ file = "DalaranCity", label = "City of Dalaran", dj = "dalarancitymap", fdr = "dalaran" },
		{ file = "DalaranUnderbelly", label = "The Underbelly", dj = "dalaranunderbellymap", fdr = "dalaran_underbelly" },
	},
	drownedcity = {
		{ file = "DrownedCity", label = "The Drowned City", dj = "drownedcitymap", fdr = "drownedcity" },
		{ file = "DrownedCityAtalByzal", label = "Atal'Byzal", dj = "drownedcityatalbyzalmap" },
	},
	kroldokstronghold = {
		{ file = "Kroldok", label = "Krol'dok Stronghold", dj = "kroldokmap", fdr = "kroldok" },
	},
	alcazprison = {
		{ file = "AlcazPrison", label = "Main Unit", names = { "Alcaz Prison" }, dj = "alcazprisonmap", fdr = "alcazprison" },
		{ file = "AlcazPrisonMaxSecurity", label = "Maximum Security Unit", dj = "alcazprisonmap2",
			fdr = "alcazprison_maximumsecurity" },
	},
	blackmawhold = {
		{ file = "BlackmawGrove", label = "Blackmaw Grove", dj = "blackmawholdgrovemap", fdr = "blackmawhold" },
		{ file = "BlackmawFesteringGrotto", label = "Festering Grotto", dj = "blackmawholdfesteringgrottomap",
			fdr = "blackmawhold_festeringgrotto" },
		{ file = "BlackmawFallenGrove", label = "Depths of the Fallen Grove", names = { "Fallen Grove" },
			dj = "blackmawholdfallengrovemap", fdr = "blackmawhold_fallengrove" },
		{ file = "BlackmawBurrow", label = "Depths of the Burrow", names = { "Burrow" }, dj = "blackmawholdburrowmap",
			fdr = "blackmawhold_burrow" },
		{ file = "BlackmawElders", label = "Depths of the Elders", names = { "Elders' Cavern" }, dj = "blackmawholdeldersmap",
			fdr = "blackmawhold_elders" },
		{ file = "BlackmawForbiddenMagic", label = "Depths of Forbidden Magic", names = { "Forbidden Magic" },
			dj = "blackmawholdforbiddenmagicmap", fdr = "blackmawhold_forbiddenmagic" },
	},
	shapersterrace = {
		{ file = "ShapersTerrace", label = "Shaper's Terrace", dj = "shapersterracemap", fdr = "shapersterrace" },
		{ file = "ShapersTerracePrismaticTalus", label = "Prismatic Talus" },
	},
}

-- The floors of an instance name, or nil.
function ReyesMaps.Floors(name)
	local k = type(name) == "string" and ns.GameFiles.Key(name)
	return k and ReyesMaps.DUNGEONS[k] or nil
end

-- Does the instance have a bundled map? (for /dp debug)
function ReyesMaps.Has(name)
	return ReyesMaps.Floors(name) ~= nil
end

-- The bundled floor for floor `index` of a plan: one named like it (label or names), else Providers.PickFloor (the
-- most words of its name, else the same position). nil for the zone outside (an unnamed floor with its own map ID).
function ReyesMaps.Pick(plan, index)
	local floor = type(plan) == "table" and type(plan.floors) == "table" and plan.floors[index]
	if type(floor) ~= "table" or ((floor.name or "") == "" and floor.uiMapID) then
		return nil
	end
	local list = ReyesMaps.Floors(plan.instance and plan.instance.name)
	if not list then
		return nil
	end
	local want = ns.Match.StripArticle(floor.name or "")
	if want ~= "" then
		for _, f in ipairs(list) do
			for _, n in ipairs(f.names or {}) do
				if ns.Match.StripArticle(n) == want then
					return f
				end
			end
		end
	end
	return (ns.Providers.PickFloor(plan, index, list, function(f)
		return f.label, f.file
	end))
end

-- The lower-case file name of a texture path, without folders and extension ("hallofthanesmap").
local function baseName(path)
	if type(path) ~= "string" then
		return nil
	end
	return (path:match("([^\\/]+)$") or path):gsub("%.%w+$", ""):lower()
end
ReyesMaps.BaseName = baseName

-- Another addon's drawing of the same picture (Dungeon Journal, Forever Dungeon Routes): its boss pins and the
-- alignment found with them (Providers.Align) apply to this map unchanged. nil when it draws another picture or none.
function ReyesMaps.SamePicture(f, providerArt)
	if type(f) ~= "table" or type(providerArt) ~= "table" or type(providerArt.textures) ~= "table" then
		return false
	end
	local b = baseName(providerArt.textures[1])
	if providerArt.provider == "dungeonJournal" then
		return f.dj ~= nil and b == f.dj
	elseif providerArt.provider == "foreverDungeonRoutes" then
		return f.fdr ~= nil and b == f.fdr
	end
	return false
end

-- The art of floor `index` of a plan, in the shape the map canvas draws (Instances.MapArt's: width, height, tile size,
-- textures) with source = "reyes", artist, file, and the names of the same picture in the other addons (dj, fdr); when
-- one of those addons is installed with the same picture: its boss pins (pins, pinsCredit) and alignment (align).
-- Cached per plan floor until the plan or the providers change. nil when the floor has no bundled map.
local cache = {}
function ReyesMaps.FloorArt(plan, index)
	local f = ReyesMaps.Pick(plan, index)
	if not f then
		return nil
	end
	local provided = ns.Providers.FloorArt(plan, index)
	if not ReyesMaps.SamePicture(f, provided) then
		provided = nil
	end
	local key = tostring(plan.id) .. ":" .. tostring(index)
	local c = cache[key]
	if c and c.f == f and c.stamp == (plan.updated or 0) and c.provided == provided then
		return c.art
	end
	local textures = {}
	for i = 1, math.ceil(ReyesMaps.HEIGHT / ReyesMaps.STRIP) do
		textures[i] = ReyesMaps.FOLDER .. f.file .. i
	end
	local art = { width = ReyesMaps.WIDTH, height = ReyesMaps.HEIGHT, tileWidth = ReyesMaps.WIDTH,
		tileHeight = ReyesMaps.STRIP, textures = textures, source = "reyes", artist = ReyesMaps.ARTIST, file = f.file,
		label = f.label, dj = f.dj, fdr = f.fdr, pins = {}, keepOut = f.keepOut }
	if provided then
		art.pins, art.align, art.pinsCredit = provided.pins or {}, provided.align, provided.credit
	end
	cache[key] = { f = f, stamp = plan.updated or 0, provided = provided, art = art }
	return art
end

function ReyesMaps.Reset()
	cache = {}
end

-- Every bundled floor, for tests and /dp debug: { { key, file, label } }.
function ReyesMaps.All()
	local out = {}
	for _, k in ipairs(ns.Util.SortedKeys(ReyesMaps.DUNGEONS)) do
		for _, f in ipairs(ReyesMaps.DUNGEONS[k]) do
			out[#out + 1] = { key = k, file = f.file, label = f.label }
		end
	end
	return out
end

function ReyesMaps.Init()
	ns:On("PLAN_CHANGED", ReyesMaps, ReyesMaps.Reset)
	ns:On("PROVIDERS_CHANGED", ReyesMaps, ReyesMaps.Reset)
end
