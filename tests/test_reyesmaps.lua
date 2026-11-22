-- Santiago Reyes' bundled maps of Forever's new dungeons (Data/ReyesMaps.lua, Media/Maps/Reyes/, made by
-- tools/reyes_maps.py): the files ship and are what the client reads, every Forever plan floor gets its map without any
-- other addon, the map order, the floors matched by name, the credit on the map, another addon's pins and routes on
-- the same picture, and the licence that keeps the pictures out of the MIT licence.
local T = ...
local ns, mock = T.ns, T.mock
local R = ns.ReyesMaps

local FOREVER = { "hall-of-thanes", "ruins-of-lordaeron", "excavation-site-wetlands", "city-of-dalaran",
	"the-drowned-city", "kroldok-stronghold", "alcaz-prison", "blackmaw-hold", "shapers-terrace" }

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function noProviders()
	mock.RemoveProviders()
	_G.ForeverDungeonRoutes = nil
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	ns.MinimapArt.Reset()
	R.Reset()
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function u32(s, at)
	local a, b, c, d = s:byte(at, at + 3)
	return a + b * 256 + c * 65536 + d * 16777216
end

T.case("Reyes maps: every bundled floor ships as three 1024 x 256 DXT1 BLP2 strips", function()
	local total = 0
	for _, f in ipairs(R.All()) do
		for i = 1, 3 do
			local path = "Media/Maps/Reyes/" .. f.file .. i .. ".blp"
			local s = readFile(path)
			T.ok(s, path .. " exists")
			if s then
				total = total + #s
				T.eq(s:sub(1, 4), "BLP2", path .. " is a BLP2 file")
				T.eq(s:byte(9), 2, path .. " DXT encoding")
				T.eq(s:byte(10), 0, path .. " no alpha (DXT1)")
				T.eq(u32(s, 13), 1024, path .. " width")
				T.eq(u32(s, 17), 256, path .. " height")
				T.eq(#s, u32(s, 21) + u32(s, 85), path .. " one level, nothing after it")
			end
		end
	end
	T.eq(#R.All(), 18, "18 floors")
	T.ok(total < 8 * 1024 * 1024, "small: " .. total .. " bytes")
end)

T.case("Reyes maps: every Forever plan floor gets its map with no other addon installed", function()
	boot()
	noProviders()
	for _, slug in ipairs(FOREVER) do
		local plan = ns.Bundled.Get("b:" .. slug)
		for i, floor in ipairs(plan.floors) do
			local art, source = ns.MinimapArt.Choose(plan, i, nil)
			if ns.Floors.IsOutside(floor) then
				T.ok(source ~= "reyes", slug .. " " .. i .. ": the zone outside gets no dungeon map")
			else
				T.eq(source, "reyes", slug .. " floor " .. i)
				T.eq(art.width, 1024, slug .. " width")
				T.eq(art.height, 683, slug .. " height: the crop the other addons draw it with")
				T.eq(#art.textures, 3, slug .. " three strips")
				T.ok(art.textures[1]:find("^Interface\\AddOns\\DungeonPlanner\\Media\\Maps\\Reyes\\"), slug .. " own folder")
				T.eq(art.artist, "Santiago Reyes")
				T.eq(art.align, nil, slug .. ": the plan is drawn as it is (same picture space)")
			end
		end
	end
	-- Classic dungeons keep the game's old map tiles.
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449592
	ns.GameFiles.Reset()
	local _, source = ns.MinimapArt.Choose(ns.Bundled.Get("b:the-deadmines"), 1, nil)
	T.eq(source, "tiles", "the Deadmines: the old tiles")
	mock.files = {}
	ns.GameFiles.Reset()
end)

T.case("Reyes maps: floors are matched by name", function()
	boot()
	local function pick(slug, index, name)
		local plan = ns.Util.DeepCopy(ns.Bundled.Get("b:" .. slug))
		if name then
			plan.floors[index] = { name = name }
		end
		local f = R.Pick(plan, index)
		return f and f.file
	end
	T.eq(pick("city-of-dalaran", 1), "DalaranCity")
	T.eq(pick("city-of-dalaran", 2), "DalaranUnderbelly")
	local blackmaw = { "BlackmawGrove", "BlackmawFesteringGrotto", "BlackmawFallenGrove", "BlackmawBurrow",
		"BlackmawElders", "BlackmawForbiddenMagic" }
	for i, file in ipairs(blackmaw) do
		T.eq(pick("blackmaw-hold", i), file, "Blackmaw Hold floor " .. i)
	end
	T.eq(pick("alcaz-prison", 1), "AlcazPrison")
	T.eq(pick("alcaz-prison", 3, "Maximum Security"), "AlcazPrisonMaxSecurity", "an own floor by its name")
	T.eq(pick("the-drowned-city", 3, "Atal'Byzal"), "DrownedCityAtalByzal")
	T.eq(pick("shapers-terrace", 3, "Prismatic Talus"), "ShapersTerracePrismaticTalus")
	T.eq(pick("the-deadmines", 1), nil, "a classic dungeon has none")
end)

T.case("Reyes maps: map order and the Prefer drawn maps setting", function()
	boot()
	noProviders()
	local plan = ns.Bundled.Get("b:hall-of-thanes")
	T.eq(select(2, ns.MinimapArt.Choose(plan, 1, nil)), "reyes", "by default the bundled map")
	T.eq(select(2, ns.MinimapArt.Choose(plan, 1, nil, false)), "minimap", "not preferred: the minimap pictures first")
	-- With Dungeon Journal installed: still the bundled map, with that addon's boss pins (the same picture).
	mock.InstallProviders()
	_G.ForeverDungeonJournal_NS.DUNGEON_MAPS["Hall of Thanes"].floors[1].texture =
		"Interface\\AddOns\\ForeverDungeonJournal\\Media\\HallOfThanesMap"
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	R.Reset()
	local art, source = ns.MinimapArt.Choose(plan, 1, nil)
	T.eq(source, "reyes", "the bundled map before another addon's")
	T.eq(art.pinsCredit, "Dungeon Journal", "its boss pins, credited")
	T.eq(#art.pins, 4, "four pins")
	T.ok(art.align and art.align.mode, "its alignment")
	-- Another picture (OpenMap's drawing): no pins taken.
	T.eq(R.SamePicture({ dj = "hallofthanesmap" }, { provider = "openMap", textures = { "t1" } }), false)
	-- Forever Dungeon Routes' route layer fits the bundled picture (same picture, same crop).
	local routes = ns.Providers.Routes(plan, 1, art)
	T.ok(routes and #routes.lines > 0, "its routes on the bundled map")
	T.eq(ns.Providers.Routes(plan, 1, { source = "reyes", fdr = "kroldok" }), nil, "not on another picture")
	-- Without the bundled map: the provider's map, as before.
	local saved = R.DUNGEONS.hallofthanes
	R.DUNGEONS.hallofthanes = nil
	R.Reset()
	T.eq(select(2, ns.MinimapArt.Choose(plan, 1, nil)), "provider", "then another addon's")
	R.DUNGEONS.hallofthanes = saved
	noProviders()
end)

T.case("Reyes maps: credited on the map, with his site and where to support him", function()
	boot()
	noProviders()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:ruins-of-lordaeron")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	canvas.loadedKey = nil
	map:Refresh()
	T.eq(canvas.artInfo and canvas.artInfo.source, "reyes", "the bundled map, no provider needed")
	T.eq(canvas.artStyle, "art", "drawn as he drew it (no parchment tint)")
	T.eq(canvas.noArt:IsShown(), false)
	T.ok(canvas.credit:IsShown() and canvas.creditPlate:IsShown(), "the credit chip")
	T.eq(canvas.credit:GetText(), "Map by Santiago Reyes")
	T.ok(canvas.creditHit:IsShown(), "the chip has a tooltip")
	local text = canvas.creditHit.dpTooltipText or ""
	T.ok(text:find("sreyesmaps.com", 1, true), "his site")
	T.ok(text:find("sreyesmaps.com/donaciones", 1, true), "his donation page")
	for i = 1, 3 do
		T.ok(canvas.tiles[i]:IsShown(), "strip " .. i)
		T.eq(canvas.tiles[i]:GetTexture(), "Interface\\AddOns\\DungeonPlanner\\Media\\Maps\\Reyes\\RuinsOfLordaeron" .. i)
	end
	-- Another kind of map hides the hover target again.
	ns.UI.SelectPlan("b:the-deadmines")
	map:Refresh()
	T.eq(canvas.creditHit:IsShown(), false)
end)

-- The packager's ignore list (.pkgmeta) uses shell pattern matching, where "*" also matches "/": the pictures and
-- their licence must not fall under any entry.
local function ignored(path, patterns)
	for _, p in ipairs(patterns) do
		local lua = "^" .. p:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
		local dir = path
		while dir do
			if dir:match(lua) then
				return p
			end
			dir = dir:match("^(.*)/[^/]+$")
		end
	end
	return nil
end

T.case("Reyes maps: the licence ships with the pictures and excludes them from the MIT licence", function()
	local meta = readFile(".pkgmeta") or ""
	local patterns, inIgnore = {}, false
	for line in meta:gmatch("[^\r\n]+") do
		if line:match("^ignore:") then
			inIgnore = true
		elseif line:match("^%S") then
			inIgnore = false
		elseif inIgnore then
			local p = line:match("^%s*%-%s*(%S+)")
			patterns[#patterns + 1] = p
		end
	end
	T.ok(#patterns > 5, "read the ignore list")
	T.eq(ignored("docs/licenses/SantiagoReyes-maps.md", patterns), nil, "the licence ships")
	T.eq(ignored("Media/Maps/Reyes/HallOfThanes1.blp", patterns), nil, "the pictures ship")
	T.eq(ignored("Libs/THIRD-PARTY-NOTICES.md", patterns), nil, "the notices ship")
	T.ok(ignored("docs/UI.md", patterns), "developer docs stay out")
	local licence = readFile("docs/licenses/SantiagoReyes-maps.md") or ""
	T.ok(licence:find("Santiago Reyes", 1, true) and licence:find("2026-11-16", 1, true), "who and when")
	T.ok(licence:find("not covered by", 1, true) and licence:find("MIT", 1, true), "outside the MIT licence")
	T.ok(licence:find("I have no problem with you using my maps. Go ahead, use them!", 1, true), "his words")
	local notices = readFile("Libs/THIRD-PARTY-NOTICES.md") or ""
	T.ok(notices:find("Media/Maps/Reyes", 1, true), "the notices name the pictures")
	local mit = readFile("LICENSE") or ""
	T.ok(mit:find("Media/Maps/Reyes", 1, true), "the MIT licence file names the exclusion")
end)

-- In game (0.1.0): the boss labels covered the map's painted names ("QUARRY OF KINGS", "DARK IRON INGRESS").
T.case("Reyes maps: the map's labels keep off its painted names", function()
	boot()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "hall-of-thanes")
	local art = R.FloorArt(plan, 1)
	T.ok(art.keepOut and #art.keepOut >= 4, "Hall of Thanes names its painted titles")
	for _, r in ipairs(art.keepOut) do
		T.ok(r[1] >= 0 and r[3] <= 1 and r[2] >= 0 and r[4] <= 1 and r[1] < r[3] and r[2] < r[4], "a box in the picture")
	end
	local boxes = ns.MapCanvas.KeepOutRects(art, 1024, 683, 0.5, { { 1, 2, 3, 4 } })
	T.eq(#boxes, #art.keepOut + 1, "added to what is there (the legend)")
	T.eq(boxes[2][1], art.keepOut[1][1] * 512, "in canvas units")
	T.eq(boxes[2][4], art.keepOut[1][4] * 683 * 0.5)
	-- A label that would sit on a painted name goes to a free side.
	local name = boxes[3] -- RELIQUARY OF KINGS
	local items = { { x = name[1] - 20, y = (name[2] + name[4]) / 2, r = 10, w = 80, h = 15, kind = "boss", prio = 3 } }
	ns.MapLayout.Labels(items, boxes, nil)
	T.eq(items[1].side ~= "right" and items[1].side ~= nil, true, "not to the right, over the name: " .. tostring(items[1].side))
end)
