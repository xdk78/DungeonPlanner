-- The map's "You are here (approx.)" marker: the anchors (Data/SubzoneData.lua from tools/gen_subzones.lua), matching
-- the game's sub-zone name to an area by ID in any client language (Data/Subzones.lua), and the marker on the map
-- (UI/MapHere.lua).
local T = ...
local ns = T.ns
local mock = T.mock
local Subzones = ns.Subzones

local function bundled(id)
	return assert(ns.Bundled.Get("b:" .. id), "bundled plan " .. id)
end

-- Within `reach` cells of (x, y) on a plan floor's walkability grid, is there floor or drawn ground? nil without a grid.
local function onTheMap(plan, floor, x, y, reach)
	local key, align = ns.Corridors.KeyFor(plan, floor)
	local grid = key and ns.Corridors.Grid(key)
	if not grid then
		return nil
	end
	local gx, gy = ns.MinimapArt.ToMap(align, x, y)
	local cx, cy = math.floor(gx * grid.w), math.floor(gy * grid.h)
	for dy = -reach, reach do
		for dx = -reach, reach do
			if ns.Walk.Open(grid, cx + dx, cy + dy) or ns.Walk.Rough(grid, cx + dx, cy + dy) then
				return true
			end
		end
	end
	return false
end

T.case("Subzones: every anchor lies on its recommended plan's drawn map", function()
	local checked, bad = 0, {}
	for key, data in pairs(ns.SubzoneData) do
		local plan
		for _, p in ipairs(ns.Bundled.All()) do
			if Subzones.For(p) == data then
				plan = p
			end
		end
		T.ok(plan, key .. ": a recommended plan of the instance")
		for _, a in ipairs(data) do
			for _, p in ipairs(a.at) do
				T.ok(p[1] <= #plan.floors and not ns.Floors.IsOutside(plan.floors[p[1]]), key .. ": a dungeon floor")
				local on = onTheMap(plan, p[1], p[2], p[3], 2)
				if on ~= nil then
					checked = checked + 1
					if not on then
						bad[#bad + 1] = string.format("%s %s floor %d (%.3f, %.3f)", key, tostring(a.a or a.w), p[1], p[2], p[3])
					end
				end
			end
		end
	end
	T.ok(checked >= 100, "anchors checked against a grid: " .. checked)
	T.eq(#bad, 0, "anchors off the drawn map: " .. table.concat(bad, "; "))
end)

-- The client inside instance `iid` (or outside with nil), in zone `zone` and sub-zone `sub`, in client language `loc`;
-- `areas` answers C_Map.GetAreaInfo. Returns a function that puts the client back.
local function client(o)
	local saved = { GetInstanceInfo = _G.GetInstanceInfo, GetZoneText = rawget(_G, "GetZoneText"),
		GetAreaInfo = _G.C_Map.GetAreaInfo, subzone = mock.subzone, locale = mock.locale }
	_G.GetInstanceInfo = function()
		return "An instance", o.iid and "party" or "none", 1, "Normal", 5, 0, false, o.iid or 0
	end
	_G.GetZoneText = function()
		return o.zone or ""
	end
	_G.C_Map.GetAreaInfo = function(id)
		return o.areas and o.areas[id] or ("Area " .. id)
	end
	mock.subzone, mock.locale = o.sub, o.loc
	Subzones.Reset()
	return function()
		_G.GetInstanceInfo, _G.GetZoneText, _G.C_Map.GetAreaInfo = saved.GetInstanceInfo, saved.GetZoneText, saved.GetAreaInfo
		mock.subzone, mock.locale = saved.subzone, saved.locale
		Subzones.Reset()
	end
end

-- The data's area with this AreaTable or WMO area ID.
local function area(key, id)
	for _, a in ipairs(ns.SubzoneData[key]) do
		if a.a == id or a.w == id then
			return a
		end
	end
	error(key .. ": no area " .. id)
end

T.case("Subzones: an AreaTable area matches its name in the client's language, by ID (German client)", function()
	local ruins = bundled("ruins-of-lordaeron")
	local kings = area("ruinsoflordaeron", 16612)
	local back = client({ iid = 2999, zone = "Ruinen von Lordaeron", sub = "Königsgasse", loc = "deDE",
		areas = { [16612] = "Königsgasse" } })
	local ok, err = pcall(function()
		local here = Subzones.Here(ruins, kings.at[1][1])
		T.ok(here, "found")
		T.eq(here.name, "Königsgasse")
		T.eq(here.x, kings.at[1][2])
		T.eq(here.y, kings.at[1][3])
		-- A plan of the same instance that is not the recommended one (a copy, a plan made inside) gets it too.
		T.ok(Subzones.Here({ instance = { name = ruins.instance.name }, floors = ruins.floors }, kings.at[1][1]), "own plan")
		mock.subzone = "King's Alley"
		T.eq(Subzones.Here(ruins, kings.at[1][1]), nil, "the English name is not this client's")
	end)
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: a WMO area matches the names the data carries for the client's language", function()
	local hall = bundled("hall-of-thanes")
	local rest = area("hallofthanes", 140756)
	T.eq(rest.a, nil, "a WMO area with no AreaTable row")
	local back = client({ iid = 3065, zone = "Die Halle der Thanen", sub = "Anvilmars Rast", loc = "deDE" })
	local ok, err = pcall(function()
		T.eq(Subzones.Here(hall, 1).x, rest.at[1][2], "German")
		mock.subzone = "Anvilmar's Rest"
		T.eq(Subzones.Here(hall, 1), nil, "English text on a German client")
		mock.locale = "enGB"
		T.ok(Subzones.Here(hall, 1), "a British client reads the English names")
		mock.locale = "xxXX"
		T.eq(Subzones.Here(hall, 1), nil, "a language the data has no names for")
	end)
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: a secret sub-zone, or one named like the zone, places nothing", function()
	local hall = bundled("hall-of-thanes")
	local secret = {}
	local back = client({ iid = 3065, zone = "The Hall of Thanes", sub = "Anvilmar's Rest" })
	local saved, sub, mini = rawget(_G, "issecretvalue"), _G.GetSubZoneText, _G.GetMinimapZoneText
	local ok, err = pcall(function()
		T.ok(Subzones.Here(hall, 1), "plain")
		_G.issecretvalue = function(v)
			return v == secret
		end
		_G.GetSubZoneText = function()
			return secret
		end
		_G.GetMinimapZoneText = _G.GetSubZoneText
		T.eq(Subzones.Where().subzone, nil, "secret dropped")
		T.eq(Subzones.Here(hall, 1), nil, "no marker")
		_G.issecretvalue, _G.GetSubZoneText, _G.GetMinimapZoneText = saved, sub, mini
		mock.subzone = "The Hall of Thanes"
		T.eq(Subzones.Here(hall, 1), nil, "the zone itself")
		mock.subzone = ""
		T.eq(Subzones.Where().subzone, nil, "no sub-zone")
	end)
	_G.issecretvalue, _G.GetSubZoneText, _G.GetMinimapZoneText = saved, sub, mini
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: nothing outside the plan's instance or on a floor without the area", function()
	local hall, maw = bundled("hall-of-thanes"), bundled("blackmaw-hold")
	local back = client({ iid = nil, zone = "Ironforge", sub = "Anvilmar's Rest" })
	T.eq(Subzones.Here(hall, 1), nil, "outside any instance")
	back()
	back = client({ iid = 2974, zone = "Blackmaw Hold", sub = "Anvilmar's Rest" })
	T.eq(Subzones.Here(hall, 1), nil, "inside another instance")
	back()
	local grotto = area("blackmawhold", 17310)
	T.eq(#grotto.at, 1, "only the grotto's own floor")
	back = client({ iid = 2974, zone = "Blackmaw Hold", sub = "Festering Grotto", areas = { [17310] = "Festering Grotto" } })
	local ok, err = pcall(function()
		T.ok(Subzones.Here(maw, grotto.at[1][1]), "its floor")
		T.eq(Subzones.Here(maw, 1), nil, "another floor")
	end)
	back()
	T.ok(ok, tostring(err))
end)

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.UI.Show()
end

local function listening(view)
	for _, e in ipairs(ns.MapHere.EVENTS) do
		for _, h in ipairs(ns.EventTable()[e] or {}) do
			if h == view.hereHandler then
				return true
			end
		end
	end
	return false
end

T.case("Subzones: the map's marker, its events only while the map shows, a zone change moves it", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local back = client({ iid = 3065, zone = "The Hall of Thanes", sub = "Anvilmar's Rest" })
	local ok, err = pcall(function()
		view:DrawContent()
		T.ok(view.here:IsShown(), "shown in its area")
		T.ok(listening(view), "listening while shown")
		local _, _, _, x1, y1 = view.here:GetPoint(1)
		mock.subzone = "Reliquary of Kings"
		mock.FireEvent("ZONE_CHANGED_INDOORS")
		local _, _, _, x2, y2 = view.here:GetPoint(1)
		T.ok(view.here:IsShown() and (x1 ~= x2 or y1 ~= y2), "moved to the new area")
		mock.subzone = ""
		mock.FireEvent("ZONE_CHANGED")
		T.ok(not view.here:IsShown(), "hidden without a sub-zone")
		mock.subzone = "Anvilmar's Rest"
		ns.db.settings.mapHere = false
		view:DrawContent()
		T.ok(not view.here:IsShown(), "the setting turns it off")
		ns.db.settings.mapHere = true
		view:DrawContent()
		T.ok(view.here:IsShown(), "back on")
		_G.DungeonPlannerMainFrame:Hide()
		T.ok(not listening(view), "no zone events while the window is closed")
		ns.UI.Show()
		T.ok(listening(view), "listening again")
	end)
	ns.db.settings.mapHere = true
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: an update that added the marker's files, before a restart: the map draws without it", function()
	boot()
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local real = ns.MapHere
	ns.MapHere = nil
	local ok, err = pcall(function()
		local view = ns.MapCanvas.Create(UIParent, map.canvas.cb)
		view:DrawContent()
		T.eq(view.here, nil, "no marker")
		view:Hide()
	end)
	ns.MapHere = real
	T.ok(ok, tostring(err))
end)

T.case("Subzones: the generator checks its files, applies the hand fixes and is up to date", function()
	local G = dofile("tools/gen_subzones.lua")
	local research = { instanceMapID = 3065 }
	local good = { schema = 1, slug = "x", instanceMapID = 3065, position = "game",
		sources = { { id = "wago", name = "w", licence = "l" }, { id = "game", name = "g", licence = "l" } },
		areas = { { name = "Room", wmo = 5, names = { deDE = { "Raum" } }, at = { { floor = 1, x = 0.5, y = 0.5 } } },
			{ name = "Hall", area = 7, at = { { floor = 1, x = 0.2, y = 0.2 }, { floor = 2, x = 0.3, y = 0.3 } } } },
		overrides = { { name = "Hall", floor = 2, drop = true, why = "a reason" },
			{ name = "Room", floor = 1, x = 0.6, y = 0.4, src = "own", why = "read on the map" } },
		exclude = {} }
	T.eq(#G.Validate(good, "x.json", research, 2), 0, "valid")
	local anchors = G.Anchors(good)
	T.eq(#anchors, 2)
	T.eq(#anchors[1].at, 1, "Hall: floor 2 dropped")
	T.eq(anchors[2].at[1][2], 0.6, "Room: moved by hand")
	good.exclude = { { name = "Room", why = "off the map" } }
	T.eq(#G.Anchors(good), 1, "excluded")
	local bad = { schema = 1, slug = "y", instanceMapID = 1, position = "web", sources = {},
		areas = { { name = "Room", wmo = 5, at = { { floor = 3, x = 1.5, y = 0 } } } },
		overrides = { { name = "Nowhere", floor = 1, why = "x" } }, exclude = { { name = "Room" } } }
	local errs = G.Validate(bad, "x.json", research, 2)
	T.ok(#errs >= 7, "slug, map ID, sources, position, names, anchor, override, exclude: " .. table.concat(errs, "; "))
	local p = assert(io.popen("lua tools/gen_subzones.lua --check 2>&1"))
	local out = p:read("*a")
	p:close()
	T.ok(out:find("up to date", 1, true), "Data/SubzoneData.lua matches data-src/subzones: " .. out)
end)
