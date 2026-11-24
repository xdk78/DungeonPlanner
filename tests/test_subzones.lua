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
-- `areas` answers C_Map.GetAreaInfo (else the mock's "Area <id>"). Returns a function that puts the client back.
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
		mock.FireEvent("ZONE_CHANGED") -- map views shown now ask again where the player is
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

-- A made-up instance (test data, not the bundled anchors): WMO rooms with the hashes of names in two languages.
local function testInstance(rooms)
	local data = { iid = 9001 }
	for i, r in ipairs(rooms) do
		local h = {}
		for loc, name in pairs(r.names) do
			for n, l in ipairs(ns.SubzoneLocales) do
				if l == loc then
					h[n] = Subzones.Hash(name)
				end
			end
		end
		for n = 1, #ns.SubzoneLocales do
			h[n] = h[n] or false
		end
		data[i] = { w = i, h = h, at = r.at }
	end
	ns.SubzoneData.testinstance = data
	return { instance = { name = "Test Instance" }, floors = { { name = "One" }, { name = "Two" } } }
end

T.case("Subzones: an AreaTable area matches its name in the client's language, by ID", function()
	local ruins = bundled("ruins-of-lordaeron")
	local id = ruins and ns.SubzoneData.ruinsoflordaeron[1].a
	local first = area("ruinsoflordaeron", id)
	local back = client({ iid = 2999, zone = "Zone (de)", sub = "Area name (de)", loc = "deDE",
		areas = { [id] = "Area name (de)" } })
	local ok, err = pcall(function()
		local here = Subzones.Here(ruins, first.at[1][1])
		T.ok(here, "found")
		T.eq(here.name, "Area name (de)")
		T.eq(here.x, first.at[1][2])
		T.eq(here.y, first.at[1][3])
		-- A plan of the same instance that is not the recommended one (a copy, a plan made inside) gets it too.
		T.ok(Subzones.Here({ instance = { name = ruins.instance.name }, floors = ruins.floors }, first.at[1][1]), "own plan")
		mock.subzone = "Area name (en)"
		T.eq(Subzones.Here(ruins, first.at[1][1]), nil, "another language's name")
	end)
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: a WMO area matches the hashes of the client's language", function()
	local plan = testInstance({ { names = { enUS = "Room", deDE = "Raum" }, at = { { 1, 0.4, 0.6 } } } })
	local back = client({ iid = 9001, zone = "Zone", sub = "Raum", loc = "deDE" })
	local ok, err = pcall(function()
		T.eq(Subzones.Here(plan, 1).x, 0.4, "German")
		mock.subzone = "  Raum "
		T.ok(Subzones.Here(plan, 1), "trimmed, as the tool trims")
		mock.subzone = "Room"
		T.eq(Subzones.Here(plan, 1), nil, "English text on a German client")
		mock.locale = "enGB"
		Subzones.Reset()
		T.ok(Subzones.Here(plan, 1), "a British client reads the English names")
		mock.locale = "xxXX"
		Subzones.Reset()
		T.eq(Subzones.Here(plan, 1), nil, "a language the data has no names for")
	end)
	ns.SubzoneData.testinstance = nil
	back()
	T.ok(ok, tostring(err))
end)

-- XOR of two values below 2^32, without a bit library: the `bit.bxor` the game has, for the test of that path.
local function xor32(a, b)
	local out, place = 0, 1
	for _ = 1, 32 do
		local x, y = a % 2, b % 2
		if x ~= y then
			out = out + place
		end
		a, b, place = (a - x) / 2, (b - y) / 2, place * 2
	end
	return out
end

T.case("Subzones: the name hash is 32-bit FNV-1a, with the game's bit library and without", function()
	-- The same vectors tools/subzone_anchors.py checks its own hash with, so the two agree.
	local vectors = dofile("tools/gen_spawns.lua").DecodeJSON(assert(io.open("tests/fnv1a_vectors.json", "rb")):read("*a"))
	T.ok(#vectors >= 8, "vectors")
	local saved = rawget(_G, "bit")
	local ok, err = pcall(function()
		for _, withBit in ipairs({ false, true }) do
			-- The game's BitOp answers signed 32-bit values; the hash must come out the same.
			_G.bit = withBit and { bxor = function(a, b)
				local v = xor32(a % 4294967296, b % 4294967296)
				return v >= 2147483648 and v - 4294967296 or v
			end } or nil
			for _, v in ipairs(vectors) do
				T.eq(Subzones.Hash(v.text), v.hash, (withBit and "bit: " or "plain: ") .. v.text)
			end
		end
	end)
	_G.bit = saved
	T.ok(ok, tostring(err))
end)

T.case("Subzones: only numbers in the data: IDs, positions, hashes, never a name", function()
	local f = assert(io.open("Data/SubzoneData.lua", "rb"))
	local code = f:read("*a"):gsub("%-%-[^\n]*", "")
	f:close()
	local strings = {}
	for s in code:gmatch('"([^"]*)"') do
		strings[#strings + 1] = s
	end
	T.eq(#strings, #ns.SubzoneLocales, "the only strings are the language codes: " .. table.concat(strings, ", "))
	-- data-src too: the tool writes hashes and keeps the names in its work folder.
	local spawns = dofile("tools/gen_spawns.lua")
	local files = dofile("tools/gen_bosses.lua").ListFiles("data-src/subzones", ".json")
	T.ok(#files >= 25, "files: " .. #files)
	for _, file in ipairs(files) do
		local doc = spawns.DecodeJSON(assert(io.open("data-src/subzones/" .. file, "rb")):read("*a"))
		for _, a in ipairs(doc.areas) do
			T.ok(a.name == nil and a.names == nil, file .. ": " .. tostring(a.key) .. " carries no name")
		end
		for _, field in ipairs({ "overrides", "exclude" }) do
			for _, x in ipairs(doc[field] or {}) do
				T.ok(x.name == nil and type(x.key) == "string", file .. ": a hand fix by key")
			end
		end
	end
end)

T.case("Subzones: a name several areas share places the one on the floor shown", function()
	local plan = testInstance({ { names = { enUS = "Hall" }, at = { { 1, 0.1, 0.1 } } },
		{ names = { enUS = "Hall" }, at = { { 2, 0.9, 0.9 } } } })
	local back = client({ iid = 9001, zone = "Zone", sub = "Hall" })
	local ok, err = pcall(function()
		T.eq(#Subzones.Find(Subzones.For(plan), Subzones.Where()), 2, "both match")
		T.eq(Subzones.Here(plan, 1).x, 0.1, "floor 1")
		T.eq(Subzones.Here(plan, 2).x, 0.9, "floor 2")
	end)
	ns.SubzoneData.testinstance = nil
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: a secret sub-zone, or one named like the zone, places nothing", function()
	local ruins = bundled("ruins-of-lordaeron")
	local a = ns.SubzoneData.ruinsoflordaeron[1]
	local secret = {}
	local back = client({ iid = 2999, zone = "Zone", sub = "Area " .. a.a })
	local saved, sub, mini = rawget(_G, "issecretvalue"), _G.GetSubZoneText, _G.GetMinimapZoneText
	local ok, err = pcall(function()
		T.ok(Subzones.Here(ruins, a.at[1][1]), "plain")
		_G.issecretvalue = function(v)
			return v == secret
		end
		_G.GetSubZoneText = function()
			return secret
		end
		_G.GetMinimapZoneText = _G.GetSubZoneText
		T.eq(Subzones.Where().subzone, nil, "secret dropped")
		T.eq(Subzones.Here(ruins, a.at[1][1]), nil, "no marker")
		_G.issecretvalue, _G.GetSubZoneText, _G.GetMinimapZoneText = saved, sub, mini
		mock.subzone = "Zone"
		T.eq(Subzones.Here(ruins, a.at[1][1]), nil, "the zone itself")
		mock.subzone = ""
		T.eq(Subzones.Where().subzone, nil, "no sub-zone")
	end)
	_G.issecretvalue, _G.GetSubZoneText, _G.GetMinimapZoneText = saved, sub, mini
	back()
	T.ok(ok, tostring(err))
end)

T.case("Subzones: nothing outside the plan's instance or on a floor without the area", function()
	local ruins, maw = bundled("ruins-of-lordaeron"), bundled("blackmaw-hold")
	local a = ns.SubzoneData.ruinsoflordaeron[1]
	local back = client({ iid = nil, zone = "Zone", sub = "Area " .. a.a })
	T.eq(Subzones.Here(ruins, a.at[1][1]), nil, "outside any instance")
	back()
	back = client({ iid = 2974, zone = "Zone", sub = "Area " .. a.a })
	T.eq(Subzones.Here(ruins, a.at[1][1]), nil, "inside another instance")
	back()
	-- Blackmaw Hold: an area whose ground on floor 1 is the mountains has its anchor only on its cave floor.
	local grotto = area("blackmawhold", 17310)
	T.eq(#grotto.at, 1, "only its cave floor")
	back = client({ iid = 2974, zone = "Zone", sub = "Area 17310" })
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
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "ruins-of-lordaeron")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local data = ns.SubzoneData.ruinsoflordaeron
	local back = client({ iid = 2999, zone = "Zone", sub = "Area " .. data[1].a })
	local ok, err = pcall(function()
		mock.FireEvent("ZONE_CHANGED_NEW_AREA")
		view:DrawContent()
		T.ok(view.here:IsShown(), "shown in its area")
		T.ok(listening(view), "listening while shown")
		T.ok(not view.here:IsMouseEnabled(), "takes no mouse: the dots, legs and coordinates under it keep theirs")
		-- Where the player is was asked on the zone event; a redraw (a drag, a zoom) does not ask the game again.
		local asked = 0
		local real = _G.GetSubZoneText
		_G.GetSubZoneText = function()
			asked = asked + 1
			return real()
		end
		view:DrawContent()
		_G.GetSubZoneText = real
		T.eq(asked, 0, "no game calls on a redraw")
		-- The tooltip, from the map's hover update: inside the marker, outside it, and a route leg's tooltip first.
		local at = view.hereAt
		local tt = ns.Widgets.Tip()
		local owner
		local setOwner, isOwned = tt.SetOwner, tt.IsOwned
		tt.SetOwner = function(self, o, ...)
			owner = o
			return setOwner(self, o, ...)
		end
		tt.IsOwned = function(_, o)
			return o == owner
		end
		view:HereHover(at.x, at.y)
		T.ok(tt:IsShown() and owner == view and view.hereTip, "tooltip inside the marker")
		view:HereHover(at.x + at.r * 2, at.y)
		T.ok(not view.hereTip and not tt:IsShown(), "gone outside it")
		view.routeTip = true
		view:HereHover(at.x, at.y)
		T.ok(not view.hereTip, "a route leg's tooltip stays")
		view.routeTip = nil
		view:HereHover(nil)
		-- End to end: the pointer over the marker and the map's own hover update (its OnUpdate), then leaving the map.
		-- The mock lays out no anchors: the canvas reports where its anchor puts it (as tests/test_zoom.lua does).
		local routes = ns.db.settings.routes.hover
		ns.db.settings.routes.hover = false -- no route leg under the pointer takes the tooltip
		view.canvas.GetLeft = function()
			return view:GetLeft() + view.ox
		end
		view.canvas.GetTop = function()
			return view:GetTop() - view.oy
		end
		local scale = view.canvas:GetEffectiveScale()
		local function pointAt(x, y)
			mock.SetCursor((view.canvas:GetLeft() + x) * scale, (view.canvas:GetTop() + y) * scale)
		end
		pointAt(at.x, at.y)
		mock.Hover(view)
		mock.Advance(0.1)
		T.ok(view.hereTip and tt:IsShown(), "the map's hover update shows it")
		mock.Leave(view)
		T.ok(not view.hereTip and not tt:IsShown(), "leaving the map hides it")
		-- A drawing tool: no marker tooltip, as no route hover.
		local drawTool = view.cb.drawTool
		view.cb.drawTool = function()
			return "line"
		end
		mock.Hover(view)
		mock.Advance(0.1)
		T.ok(not view.hereTip, "none with a drawing tool")
		view.cb.drawTool = drawTool
		view.hoverAt = nil
		mock.Advance(0.1)
		T.ok(view.hereTip, "back without it")
		-- A pan starting ends it.
		view.drag = { mode = "pan", startX = 0, startY = 0, ox = view.ox, oy = view.oy, moved = false }
		view.OnDragUpdate(view)
		T.ok(not view.hereTip and not tt:IsShown(), "a pan hides it")
		view.drag = { mode = "idle" }
		mock.Leave(view)
		-- The marker appearing under a pointer already over the map, with nothing else wanting the hover (coordinates
		-- and route hover off): the hover update starts for it.
		local coords = ns.db.settings.showCoordinates
		ns.db.settings.showCoordinates = false
		mock.subzone = ""
		mock.FireEvent("ZONE_CHANGED")
		pointAt(view.hereAt and view.hereAt.x or at.x, view.hereAt and view.hereAt.y or at.y)
		mock.Hover(view)
		T.eq(view:GetScript("OnUpdate"), nil, "no hover update for nothing")
		mock.subzone = "Area " .. data[1].a
		mock.FireEvent("ZONE_CHANGED")
		pointAt(view.hereAt.x, view.hereAt.y)
		T.ok(view:GetScript("OnUpdate") ~= nil, "started for the marker")
		mock.Advance(0.1)
		T.ok(view.hereTip, "its tooltip without leaving and coming back")
		-- The marker moving to another area takes its tooltip away.
		mock.subzone = "Area " .. data[2].a
		mock.FireEvent("PLAYER_ENTERING_WORLD")
		T.ok(not view.hereTip and not tt:IsShown(), "gone when the marker moves (here after a loading screen)")
		mock.Leave(view)
		ns.db.settings.showCoordinates = coords
		mock.subzone = "Area " .. data[1].a
		mock.FireEvent("ZONE_CHANGED")
		view.canvas.GetLeft, view.canvas.GetTop = nil, nil
		ns.db.settings.routes.hover = routes
		tt.SetOwner, tt.IsOwned = setOwner, isOwned
		local _, _, _, x1, y1 = view.here:GetPoint(1)
		mock.subzone = "Area " .. data[2].a
		mock.FireEvent("ZONE_CHANGED_INDOORS")
		local _, _, _, x2, y2 = view.here:GetPoint(1)
		T.ok(view.here:IsShown() and (x1 ~= x2 or y1 ~= y2), "moved to the new area")
		mock.subzone = ""
		mock.FireEvent("ZONE_CHANGED")
		T.ok(not view.here:IsShown(), "hidden without a sub-zone")
		mock.subzone = "Area " .. data[1].a
		mock.FireEvent("ZONE_CHANGED")
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
	local h = { 1, 2, false, { 3, 4 }, 5, 6, 7, 8, 9, 10, 11 }
	local good = { schema = 1, slug = "x", instanceMapID = 3065, position = "game",
		sources = { { id = "wago", name = "w", licence = "l" }, { id = "game", name = "g", licence = "l" } },
		areas = { { key = "w5", wmo = 5, hashes = h, at = { { floor = 1, x = 0.5, y = 0.5 } } },
			{ key = "a7", area = 7, at = { { floor = 1, x = 0.2, y = 0.2 }, { floor = 2, x = 0.3, y = 0.3 } } } },
		overrides = { { key = "a7", floor = 2, drop = true, why = "a reason" },
			{ key = "w5", floor = 1, x = 0.6, y = 0.4, src = "own", why = "read on the map" } },
		exclude = {} }
	T.eq(#G.Validate(good, "x.json", research, 2), 0, "valid: " .. table.concat(G.Validate(good, "x.json", research, 2), "; "))
	local anchors = G.Anchors(good)
	T.eq(#anchors, 2)
	T.eq(#anchors[1].at, 1, "a7: floor 2 dropped")
	T.eq(anchors[2].at[1][2], 0.6, "w5: moved by hand")
	good.exclude = { { key = "w5", why = "off the map" } }
	T.eq(#G.Anchors(good), 1, "excluded")
	-- Bad hashes: too few, out of range, a one-element list, a name.
	for _, bad in ipairs({ { 1, 2 }, { 2 ^ 32, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, { { 1 }, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
		{ "Room", 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } }) do
		good.areas[1].hashes = bad
		T.eq(#G.Validate(good, "x.json", research, 2), 1, "bad hashes refused")
	end
	good.areas[1].hashes = h
	good.areas[1].name = "Room"
	T.eq(#G.Validate(good, "x.json", research, 2), 1, "a name refused")
	good.areas[1].name = nil
	local bad = { schema = 1, slug = "y", instanceMapID = 1, position = "web", sources = {},
		areas = { { key = "w6", wmo = 5, at = { { floor = 3, x = 1.5, y = 0 } } } },
		overrides = { { key = "a1", floor = 1, why = "x" } }, exclude = { { key = "w5" } } }
	local errs = G.Validate(bad, "x.json", research, 2)
	T.ok(#errs >= 8, "slug, map ID, sources, position, key, hashes, anchor, override, exclude: " .. table.concat(errs, "; "))
	-- Names that hash alike in one language: an error unless both areas have the same anchors.
	local twins = { areas = {
		{ key = "w1", wmo = 1, hashes = { 9, 100, false, false, false, false, false, false, false, false, false },
			at = { { floor = 1, x = 0.1, y = 0.1 } } },
		{ key = "w2", wmo = 2, hashes = { 8, { 100, 101 }, false, false, false, false, false, false, false, false, false },
			at = { { floor = 1, x = 0.5, y = 0.5 } } } }, overrides = {}, exclude = {} }
	T.eq(#G.Collisions(G.Anchors(twins), "x.json"), 1, "deDE shared, other anchors")
	twins.areas[2].at = { { floor = 1, x = 0.1, y = 0.1 } }
	T.eq(#G.Collisions(G.Anchors(twins), "x.json"), 0, "the same anchors")
	local p = assert(io.popen("lua tools/gen_subzones.lua --check 2>&1"))
	local out = p:read("*a")
	p:close()
	T.ok(out:find("up to date", 1, true), "Data/SubzoneData.lua matches data-src/subzones: " .. out)
end)
