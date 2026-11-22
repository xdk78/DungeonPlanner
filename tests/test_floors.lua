-- Floors (Data/Floors.lua, UI/Panels/FloorBar.lua): every floor an instance has map art for, merged with the plan's
-- floors without duplicates; the switcher on the map (tabs, or a name between arrows), Shift + wheel; floors only the
-- map had joining an own plan when something is put on them; steps and markers that lead to another floor.
local T = ...
local ns, mock = T.ns, T.mock
local Floors = ns.Floors

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

local function names(plan)
	local out = {}
	for i, f in ipairs(Floors.For(plan)) do
		out[i] = ns.Names.Floor(f, i)
	end
	return out
end

T.case("Floors: merging keeps the plan's floors first and adds each art floor once", function()
	local art = { { label = "Upper" }, { label = "Lower" }, { label = nil } }
	-- Floors 1 and 2 stand for art 1 and 2 by position; the zone outside stands for none.
	local merged = Floors.Merge({ { name = "Upper" }, { name = "", uiMapID = 9 } }, art, {})
	T.eq(#merged, 4, "two of the plan's, then art 2 and 3")
	T.eq(merged[1].name, "Upper")
	T.eq(merged[2].uiMapID, 9, "the plan's own floors keep their places (markers keep their numbers)")
	T.ok(merged[3].extra and merged[3].art == 2 and merged[3].name == "Lower", "art floor 2, named")
	T.ok(merged[4].extra and merged[4].art == 3 and merged[4].name == "", "art floor 3, unnamed")
	-- A plan floor that shows a Reyes map elsewhere (picked by name) covers that map.
	local reyes = { label = "Talus" }
	merged = Floors.Merge({ { name = "Talus" } }, { { label = "Main" }, { label = "Talus", reyes = reyes } }, { reyes })
	T.eq(#merged, 1, "position 1 is the plan's; the Talus map is already shown by its floor")
	T.eq(#Floors.Merge({}, {}, {}), 0)
end)

T.case("Floors: every recommended plan shows each of its instance's maps once", function()
	boot()
	for _, plan in ipairs(ns.Bundled.All()) do
		local list = Floors.For(plan)
		local label = ns.Names.Instance(plan.instance)
		T.ok(#list >= #plan.floors, label .. ": at least the plan's floors")
		for i = 1, #plan.floors do
			T.eq(list[i], plan.floors[i], label .. ": the plan's floor " .. i .. " in its place")
		end
		-- No two floors show the same bundled map.
		local view = Floors.View(plan)
		local seen = {}
		for i = 1, #list do
			local f = ns.ReyesMaps.Pick(view, i)
			if f then
				T.ok(not seen[f], label .. ": " .. f.label .. " once")
				seen[f] = true
			end
		end
		for _, f in ipairs(ns.ReyesMaps.Floors(plan.instance.name) or {}) do
			T.ok(seen[f], label .. ": Santiago Reyes' " .. f.label .. " is on the map")
		end
		-- The added floors have art.
		for i = #plan.floors + 1, #list do
			local mapID = ns.Journal.FloorMap(view, i)
			local _, source = ns.MinimapArt.Choose(view, i, mapID)
			T.ok(source ~= "grid", label .. ": floor " .. i .. " has a map")
		end
		T.eq(Floors.Count(plan), #list)
	end
	local function has(id, name)
		for _, n in ipairs(names(ns.Bundled.Get(ns.Bundled.PREFIX .. id))) do
			if n == name then
				return true
			end
		end
		return false
	end
	T.ok(has("the-drowned-city", "Atal'Byzal"), "Atal'Byzal")
	T.ok(has("alcaz-prison", "Maximum Security Unit"), "the Maximum Security Unit")
	T.ok(has("shapers-terrace", "Prismatic Talus"), "the Prismatic Talus")
	T.eq(#Floors.For(ns.Bundled.Get(ns.Bundled.PREFIX .. "the-deadmines")), 2, "the Deadmines: its two, nothing added")
	-- The home table counts the floors the map shows.
	ns.UI.GoHome("dungeons")
	local home = _G.DungeonPlannerMainFrame.home
	for _, e in ipairs(home.list.items) do
		if e.name == "Shaper's Terrace" then
			home.preview:ShowEntry(e, nil)
			T.eq(home.preview.facts[4].value:GetText(), "3", "Shaper's Terrace: 3 floors")
		end
	end
end)

T.case("Floor switcher: hidden on one floor, tabs for a few, the name between arrows for many", function()
	boot()
	local page = _G.DungeonPlannerMainFrame.instancePage
	local function open(id)
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. id)
		ns.UI.SelectTab("map")
		local map = page.panels.map
		map.canvas:SetSize(900, 560) -- the mock lays nothing out: a map of the usual size
		map:RefreshNow()
		return map, map.floorBar
	end
	local map, bar = open("hall-of-thanes")
	T.ok(not bar:IsShown(), "one floor: no switcher")
	T.ok(not map.floor:IsShown(), "and no list")
	map, bar = open("the-deadmines")
	T.ok(bar:IsShown() and bar.tabs[1]:IsShown() and bar.tabs[2]:IsShown(), "two floors: two tabs")
	T.ok(not bar.prev:IsShown(), "no arrows")
	T.ok(not map.floor:IsShown(), "the toolbar's list only for many floors")
	T.eq(bar.tabs[2].label:GetText(), ns.Names.Floor(ns.UI.ctx:Plan().floors[2], 2), "the floor's name")
	bar.tabs[2]:GetScript("OnClick")(bar.tabs[2], "LeftButton")
	T.eq(ns.UI.ctx.floor, 2, "a tab goes to its floor")
	T.ok(bar.tabs[2].dpActive and not bar.tabs[1].dpActive, "the current floor's tab is lit")
	-- Shift + wheel: the next or previous floor, round; the wheel alone zooms.
	mock.shiftDown = true
	map.canvas:GetScript("OnMouseWheel")(map.canvas, -1)
	T.eq(ns.UI.ctx.floor, 1, "past the last floor: the first")
	mock.shiftDown = false
	local zoom = map.canvas.zoom
	map.canvas:GetScript("OnMouseWheel")(map.canvas, 1)
	T.eq(ns.UI.ctx.floor, 1, "the wheel alone stays on the floor")
	T.ok(map.canvas.zoom > zoom, "and zooms")
	map, bar = open("lower-blackrock-spire")
	T.ok(bar.prev:IsShown() and bar.next:IsShown() and bar.name:IsShown(), "six floors: arrows and the name")
	T.ok(map.floor:IsShown(), "and the toolbar's list")
	T.ok(bar.name.label:GetText():find("1/6", 1, true), bar.name.label:GetText())
	bar.prev:GetScript("OnClick")(bar.prev, "LeftButton")
	T.eq(ns.UI.ctx.floor, 6, "back from the first: the last")
	bar.next:GetScript("OnClick")(bar.next, "LeftButton")
	T.eq(ns.UI.ctx.floor, 1)
	T.eq(ns.FloorBar.Step(3, 6, 1), 4)
	T.eq(ns.FloorBar.Step(1, 1, 1), nil, "one floor: nowhere to go")
	-- A floor only the map has: shown on Santiago Reyes' map.
	map, bar = open("shapers-terrace")
	T.ok(bar.tabs[3]:IsShown(), "Shaper's Terrace: three tabs")
	ns.UI.GoToFloor(3)
	T.eq(map.canvas.artInfo and map.canvas.artInfo.file, "ShapersTerracePrismaticTalus", "the Prismatic Talus' map")
	T.eq(ns.FloorBar.MarkerCount(ns.UI.ctx:Plan(), 3), 0, "nothing of the plan on it")
end)

T.case("Floors only the map had join an own plan when something is put on them", function()
	boot()
	local bundled = ns.Bundled.Get(ns.Bundled.PREFIX .. "shapers-terrace")
	local plan = ns.Plan.Duplicate(bundled, "Floors copy")
	ns.DB.AddPlan(plan)
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("map")
	T.eq(#plan.floors, 2)
	ns.UI.GoToFloor(3)
	T.eq(ns.UI.ctx.floor, 3, "viewable")
	T.eq(#plan.floors, 2, "looking changes nothing")
	-- An add that fails leaves the plan as it was.
	local updated = plan.updated
	local none, err = ns.UI.ctx:AddOnFloor(function()
		return nil, "limit"
	end)
	T.eq(none, nil)
	T.eq(err, "limit", "the add's error comes back")
	T.eq(#plan.floors, 2, "a failed add: the floor stays the map's")
	T.eq(plan.updated, updated, "and the plan is not touched")
	local m = ns.UI.ctx:AddOnFloor(function(floor)
		return ns.Plan.AddMarker(plan, floor, 0.5, 0.5, "note")
	end)
	ns.UI.ctx:Changed("markers")
	T.eq(#plan.floors, 3, "the floor joined the plan")
	T.eq(plan.floors[3].name, "Prismatic Talus")
	T.eq(plan.floors[3].art, 2, "with the art it shows (the zone outside stands at 2)")
	T.eq(m.floor, 3, "the marker is on it")
	T.eq(#Floors.For(plan), 3, "and is not listed twice")
	T.eq(ns.ReyesMaps.Pick(plan, 3).file, "ShapersTerracePrismaticTalus", "the Prismatic Talus' map")
	-- Undo takes the floor back with the marker.
	ns.UI.ctx:Undo()
	plan = ns.UI.ctx:Plan()
	T.eq(#plan.floors, 2, "undone: the floor is the map's again")
	T.eq(#Floors.For(plan), 3)
	ns.DB.DeletePlan(plan.id)
end)

T.case("Floors: a floor keeps the art it was added for when the zone outside stands before it", function()
	boot()
	-- Pure: art 2 stands at plan floor 3 (floor 2 is the zone outside); once floor 3 is the plan's, art 2 is not added
	-- again, and art 3 is still added (floor 3 names art 2, so it does not stand for art 3 by its position).
	local art = { { label = "Hall" }, { label = nil }, { label = nil } }
	local floors = { { name = "Hall" }, { name = "", uiMapID = 9 } }
	local merged = Floors.Merge(floors, art, {})
	T.eq(#merged, 4)
	T.eq(merged[3].art, 2, "floor 3 shows art 2")
	T.eq(merged[4].art, 3, "floor 4 shows art 3")
	floors[3] = { name = "", art = 2 }
	merged = Floors.Merge(floors, art, {})
	T.eq(#merged, 4, "art 2 once")
	T.eq(merged[3], floors[3], "the plan's floor in its place")
	T.eq(merged[4].art, 3, "art 3 still added")
	-- The art lookups take the art the floor names (the old map tiles here: the Deadmines has two).
	local plan = ns.Validate.Plan({ name = "Outside first", instance = { name = "The Deadmines", kind = "dungeon" },
		floors = { { name = "Mine" }, { name = "", uiMapID = 9 }, { name = "", art = 2 } } })
	T.eq(plan.floors[3].art, 2, "validation keeps art")
	local tiles = ns.GameFiles.MapTiles("The Deadmines")
	local saved = mock.files[("Interface\\WorldMap\\" .. tiles[2] .. "1"):lower()]
	mock.files[("Interface\\WorldMap\\" .. tiles[2] .. "1"):lower()] = 1
	ns.GameFiles.Reset()
	local ok, e = pcall(function()
		local tileArt = ns.GameFiles.FloorArt(plan, 3)
		T.ok(tileArt, "floor 3 has tiles")
		T.eq(tileArt.base, tiles[2], "the second floor's tiles, not a third")
		T.eq(ns.GameFiles.FloorArt(plan, 2), nil, "the zone outside: none")
	end)
	mock.files[("Interface\\WorldMap\\" .. tiles[2] .. "1"):lower()] = saved
	ns.GameFiles.Reset()
	assert(ok, e)
	-- Out of range or not a number: dropped, the floor shows the art at its own position.
	T.eq(ns.Validate.Plan({ floors = { { name = "A", art = 99 } } }).floors[1].art, nil)
	T.eq(ns.Validate.Plan({ floors = { { name = "A", art = "2" } } }).floors[1].art, nil)
	-- An export string carries it.
	local kind, back = ns.Codec.Decode(ns.Codec.ExportPlan(plan))
	T.eq(kind, "plan")
	T.eq(back.floors[3].art, 2, "export and import keep art")
	-- Every recommended plan whose added floors stand after the zone outside shows each art once with the right map.
	for _, id in ipairs({ "alcaz-prison", "shapers-terrace", "the-drowned-city" }) do
		local copy = ns.Plan.Duplicate(ns.Bundled.Get(ns.Bundled.PREFIX .. id), "Copy")
		local count = #Floors.For(copy)
		local want = ns.ReyesMaps.Pick(Floors.View(copy), 3)
		T.ok(want, id .. ": floor 3 has a map")
		T.ok(Floors.Ensure(copy, 3), id .. ": floor 3 joins")
		T.eq(copy.floors[3].art, 2, id .. ": art 2")
		T.eq(#Floors.For(copy), count, id .. ": no floor added twice")
		T.eq(ns.ReyesMaps.Pick(copy, 3), want, id .. ": the same map")
	end
end)

T.case("Floors: art is an optional field; saved plans keep it, a plan without it shows art by position", function()
	local DB = ns.DB
	local global = { schema = DB.SCHEMA, plans = { p1 = { id = "p1", name = "Old",
		instance = { name = "The Deadmines", kind = "dungeon" }, floors = { { name = "A" }, { name = "", art = 2 } } } } }
	local info = DB.LoadGlobal(global)
	T.ok(not info.readOnly and info.quarantined == 0, "loads as before")
	T.eq(global.plans.p1.floors[2].art, 2, "art kept")
	T.eq(global.plans.p1.floors[1].art, nil)
	-- What an older reader leaves after dropping art: floor 2 stands for art 2 by its position, as before.
	local list = Floors.Merge({ { name = "A" }, { name = "" } }, { {}, {} }, {})
	T.eq(#list, 2, "nothing added twice")
end)

T.case("Floors: stairs and portals say where they lead; a second click on the step goes there", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "scholomance")
	ns.UI.SelectTab("map")
	local plan, ctx = ns.UI.ctx:Plan(), ns.UI.ctx
	local index, step
	for i, s in ipairs(ctx:Steps()) do
		if ns.UI.StepLink(plan, s) then
			index, step = i, s
		end
	end
	T.ok(step, "the portal outside leads in")
	local _, caption = ns.UI.StepText(plan, step)
	local to = ns.Names.Floor(plan.floors[1], 1)
	T.ok(caption:find(string.format(ns.L["to %s"], to), 1, true), caption)
	local list = _G.DungeonPlannerMainFrame.instancePage.side.list
	ns.UI.FocusStep(index)
	T.eq(ctx.floor, step.floor, "the step's own floor first")
	-- The side panel's click on the current step: to the floor it leads to.
	list:ScrollTo(index)
	local row
	for _, r in ipairs(list.rows) do
		if r.index == index then
			row = r
		end
	end
	T.ok(row, "the step's row")
	row:GetScript("OnClick")(row, "LeftButton")
	T.eq(ctx.floor, 1, "a second click goes in")
	local bar = _G.DungeonPlannerMainFrame.instancePage.panels.map.floorBar
	T.ok(bar.name.label:GetText():find("1/" .. #ctx:Floors(), 1, true), "the switcher follows: " .. bar.name.label:GetText())
end)

-- Unverified on Forever (the 2026-11-15 scan found no map inside); built so that a client that gives one is followed.
T.case("Floors: the map follows the player's floor inside an instance when the client names it", function()
	boot()
	local floors = { { name = "The Pool of Ask'Ar" }, { name = "Moonshrine Sanctum", uiMapID = 222 }, { name = "The Forgotten Pool" } }
	T.eq(Floors.Match(floors, { map = 222, members = {} }), 2, "by map ID")
	T.eq(Floors.Match(floors, { map = 9, members = { { uiMapID = 9, name = "Forgotten Pool", relativeHeightIndex = 0 } } }),
		3, "by the group member's name")
	T.eq(Floors.Match(floors, nil), nil, "no map: nothing")
	T.eq(Floors.Match(floors, { map = 5, members = {} }), nil)
	local saved = { C_Map = _G.C_Map, IsInInstance = rawget(_G, "IsInInstance") }
	local best, inside = nil, true
	_G.C_Map = setmetatable({
		GetBestMapForUnit = function()
			return best
		end,
		GetMapGroupID = function()
			return 7
		end,
		GetMapGroupMembersInfo = function()
			return { { mapID = 501, name = "Upper", relativeHeightIndex = 1 }, { mapID = 502, name = "Ironclad Cove", relativeHeightIndex = 0 } }
		end,
	}, { __index = saved.C_Map })
	_G.IsInInstance = function()
		return inside, "party"
	end
	local ok, err = pcall(function()
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "the-deadmines")
		ns.UI.SelectTab("map")
		local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
		map:GoToFloor(1)
		map.floorBar.playerFloor = nil
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 1, "no map: the map stays")
		best = 502
		local where = Floors.PlayerMap()
		T.eq(where.group, 7)
		T.eq(where.members[2].relativeHeightIndex, 0)
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 2, "the player's floor (Ironclad Cove)")
		map:GoToFloor(1)
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 1, "a floor picked by hand stays while the player does not move")
		-- A new instance starts over; a selected marker stays until it is let go.
		local marker = ns.UI.ctx:Plan().markers[1]
		ns.UI.ctx.selectedMarker = marker and marker.id or "m1"
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(ns.UI.ctx.floor, 1, "something selected: the map stays")
		T.eq(ns.UI.ctx.selectedMarker, marker and marker.id or "m1", "and keeps the selection")
		ns.UI.ctx.selectedMarker = nil
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 2, "let go: the map follows")
		-- Another plan starts over too: back on this one, the map follows the same floor again.
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "blackfathom-deeps")
		ns.UI.SelectTab("map")
		map.FollowPlayerFloor()
		T.eq(map.floorBar.playerPlan, ns.Bundled.PREFIX .. "blackfathom-deeps")
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "the-deadmines")
		ns.UI.SelectTab("map")
		map:GoToFloor(1)
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 2, "a plan picked again: followed again")
		-- A route being drawn (the Route tool with a route in hand) holds the map; a route left picked does not.
		local ctx, savedTool = ns.UI.ctx, ns.UI.ctx.tool
		map:GoToFloor(1)
		map.floorBar.playerFloor = nil
		ctx.activeRoute, ctx.tool = "r1", "route"
		map.FollowPlayerFloor()
		T.eq(ctx.floor, 1, "drawing a route: the map stays")
		ctx.tool = "select"
		map.FollowPlayerFloor()
		T.eq(ctx.floor, 2, "a route left picked under another tool: the map follows")
		ctx.activeRoute, ctx.tool = nil, savedTool
		-- Another plan drops a selected drawing too.
		ctx.selectedShape = "s1"
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "blackfathom-deeps")
		T.eq(ctx.selectedShape, nil, "another plan: no drawing selected")
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "the-deadmines")
		ns.UI.SelectTab("map")
		map:GoToFloor(1)
		inside, best = false, 501
		map.floorBar.playerFloor = nil
		map.FollowPlayerFloor()
		T.eq(ns.UI.ctx.floor, 1, "outside an instance: never")
	end)
	_G.C_Map, _G.IsInInstance = saved.C_Map, saved.IsInInstance
	assert(ok, err)
end)

T.case("Run mode: zone events redraw only when the player's floor changed, and never for one floor", function()
	boot()
	local savedMap, best = _G.C_Map, nil
	_G.C_Map = setmetatable({
		GetBestMapForUnit = function()
			return best
		end,
		GetMapGroupID = function()
			return 7
		end,
		GetMapGroupMembersInfo = function()
			return { { mapID = 502, name = "Ironclad Cove", relativeHeightIndex = 0 } }
		end,
	}, { __index = savedMap })
	local realRefresh, count = ns.RunMode.Refresh, 0
	ns.RunMode.Refresh = function(...)
		count = count + 1
		return realRefresh(...)
	end
	local ok, err = pcall(function()
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "the-deadmines")
		ns.db.ui.step = nil
		ns.RunMode.Show()
		local f = _G.DungeonPlannerRunFrame
		realRefresh()
		count = 0
		mock.FireEvent("ZONE_CHANGED")
		T.eq(count, 0, "no map from the client, as before: nothing redrawn")
		best = 502
		mock.FireEvent("ZONE_CHANGED_INDOORS")
		T.eq(count, 1, "the player went to Ironclad Cove: redrawn")
		local plan = ns.UI.ctx:Plan()
		T.ok(f.mapFloor:GetText():find(ns.Names.Floor(plan.floors[2], 2), 1, true), f.mapFloor:GetText())
		mock.FireEvent("ZONE_CHANGED")
		T.eq(count, 1, "the same floor: nothing")
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(count, 1, "entering the world on the same floor: nothing")
		best = nil
		mock.FireEvent("ZONE_CHANGED_NEW_AREA")
		T.eq(count, 2, "a new area without a floor: redrawn")
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		realRefresh()
		count = 0
		best = 501
		mock.FireEvent("ZONE_CHANGED")
		T.eq(count, 0, "one floor: nothing")
		ns.RunMode.Hide()
	end)
	ns.RunMode.Refresh, _G.C_Map = realRefresh, savedMap
	assert(ok, err)
end)
