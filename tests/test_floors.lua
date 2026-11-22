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
	T.ok(merged[3].extra and merged[3].artIndex == 2 and merged[3].name == "Lower", "art floor 2, named")
	T.ok(merged[4].extra and merged[4].artIndex == 3 and merged[4].name == "", "art floor 3, unnamed")
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
	local index = ns.UI.ctx:EditFloor()
	local m = ns.Plan.AddMarker(plan, index, 0.5, 0.5, "note")
	ns.UI.ctx:Changed("markers")
	T.eq(#plan.floors, 3, "the floor joined the plan")
	T.eq(plan.floors[3].name, "Prismatic Talus")
	T.eq(m.floor, 3, "the marker is on it")
	T.eq(#Floors.For(plan), 3, "and is not listed twice")
	ns.DB.DeletePlan(plan.id)
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
