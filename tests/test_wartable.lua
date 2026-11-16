-- The war-table layout: the plan as ordered steps (Model/Steps.lua), the side panel's steps focusing the map (floor,
-- route segment, pull or boss, centred view), run mode (Prev / Next, key bindings, boss kills), the Enemies layer
-- (Data/Spawns.lua through UI/MapSpawns.lua: decluttered, hidden without data, no doubled pins), and the home screen's
-- instance table with its preview plate.
local T = ...
local ns, mock = T.ns, T.mock
local Steps = ns.Steps

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

-- A plan with a route of numbered stops over an entrance, a pack in pull 1 and a boss in pull 2, and a second boss and
-- pull that no stop covers.
local function stepPlan()
	return ns.Validate.Plan({
		id = "steps-test",
		name = "Steps",
		instance = { name = "Steps Keep", kind = "dungeon" },
		floors = { { name = "Upper" }, { name = "Lower" } },
		pulls = { { id = "u1", name = "Gate pack" }, { id = "u2", name = "Hall pack" }, { id = "u3", name = "Lower pack" } },
		encounters = { { id = "e1", name = "First boss" }, { id = "e2", name = "Second boss" }, { id = "e3", name = "Last boss" } },
		objectives = { { id = "o1", text = "Loot the chest", encounter = "e2" }, { id = "o2", text = "Turn in" } },
		markers = {
			{ id = "m1", floor = 1, x = 0.1, y = 0.9, kind = "entrance", label = "Door" },
			{ id = "m2", floor = 1, x = 0.3, y = 0.5, kind = "pack", pull = "u1" },
			{ id = "m3", floor = 1, x = 0.6, y = 0.4, kind = "boss", encounter = "e1", pull = "u2" },
			{ id = "m4", floor = 2, x = 0.5, y = 0.5, kind = "boss", encounter = "e2", pull = "u3" },
			{ id = "m5", floor = 2, x = 0.4, y = 0.6, kind = "pack", pull = "u3" },
		},
		routes = {
			{ id = "r1", floor = 1, color = 1, points = {
				{ 0.1, 0.9, step = 1, note = "In" },
				{ 0.2, 0.7 },
				{ 0.3, 0.5, step = 2 },
				{ 0.6, 0.4, step = 3, pull = "u2", note = "Boss room" },
			} },
		},
	})
end

T.case("Steps: route stops first, matched to what they stand on; the rest placed in order", function()
	local plan = stepPlan()
	local list = Steps.Build(plan)
	local kinds = {}
	for i, s in ipairs(list) do
		kinds[i] = s.kind .. ":" .. tostring(s.kind == "boss" and s.encounter or s.pull or s.objective or s.marker or "")
	end
	T.eq(table.concat(kinds, ","),
		"entrance:m1,pull:u1,pull:u2,boss:e1,pull:u3,boss:e2,objective:o1,boss:e3,objective:o2")
	T.eq(list[3].pull, "u2", "a stop on a boss with a pull: the pull first")
	T.eq(list[4].encounter, "e1", "then the boss")
	T.eq(list[4].from, 3, "segment starts at the previous stop")
	T.eq(list[4].to, 4)
	T.eq(list[2].from, 1, "first segment from the stop before")
	T.eq(list[2].to, 3)
	T.eq(list[5].floor, 2, "a pull without a stop sits where its markers are")
	T.ok(math.abs(list[5].x - 0.45) < 1e-6, "its centre")
	T.eq(list[6].pull, "u3", "a boss in a pull follows that pull")
	T.eq(list[7].floor, 2, "an objective of a boss takes the boss's place")
	T.eq(Steps.Next(list, 1, "pull"), 2, "the next pull is a pull step")
	-- Without stops: the entrance first, then pulls, then bosses after their pulls.
	plan.routes = {}
	list = Steps.Build(plan)
	T.eq(list[1].kind, "entrance")
	T.eq(list[2].pull, "u1")
	T.eq(list[3].pull, "u2")
	T.eq(list[4].encounter, "e1", "boss right after its pull")
	-- Moving and kills.
	T.eq(Steps.Move(list, 1, -1), 1, "clamped at the start")
	T.eq(Steps.Move(list, #list, 1), #list, "clamped at the end")
	local i = Steps.IndexOfEncounter(list, "e1")
	T.eq(Steps.AfterKill(list, 1, "e1"), i + 1, "a kill moves past the boss")
	T.eq(Steps.AfterKill(list, i + 2, "e1"), i + 2, "never backwards")
	T.eq(Steps.Next(list, 1, "boss"), i)
	local focus = Steps.Focus(list[i])
	T.eq(focus.focusEncounter, "e1")
	T.eq(focus.focusPull, nil, "a boss step focuses its boss, not its pull")
	T.eq(#Steps.Build({}), 0)
	T.eq(#Steps.Build(nil), 0)
end)

T.case("Steps: every recommended plan builds, and Ragefire's route reads in order", function()
	for _, plan in ipairs(ns.Bundled.All()) do
		local list = Steps.Build(plan)
		T.ok(#list > 0 or #plan.encounters + #plan.pulls == 0, plan.id .. " has steps")
		local pullSteps = {}
		for _, s in ipairs(list) do
			T.ok(s.kind, plan.id .. " step kind")
			if s.kind == "pull" then
				T.ok(not pullSteps[s.pull], plan.id .. " lists pull " .. tostring(s.pull) .. " once")
				pullSteps[s.pull] = true
			end
		end
		for _, pull in ipairs(plan.pulls) do
			T.ok(pullSteps[pull.id], plan.id .. " has a step for pull " .. pull.id)
		end
	end
	local rfc = Steps.Build(ns.Bundled.Get("b:ragefire-chasm"))
	T.eq(rfc[1].kind, "entrance", "Ragefire starts at the portal")
	local tara = Steps.IndexOfEncounter(rfc, "e2")
	T.ok(tara and rfc[tara].stop == 5, "Taragaman on stop 5 (Oggleflint now placed by the imported route)")
	T.ok(Steps.IndexOfEncounter(rfc, "e1") < tara, "Oggleflint before Taragaman")
	T.eq(rfc[#rfc].encounter, "e4", "Bazzalan last")
end)

-- What a step list reads as: kind and what it is about.
local function describe(list)
	local out = {}
	for i, s in ipairs(list) do
		out[i] = s.kind .. ":" .. tostring(s.kind == "boss" and s.encounter or s.pull or s.objective or s.marker or "")
	end
	return table.concat(out, ",")
end

T.case("Steps: Hall of Thanes interleaves its pulls and the quest giver with the bosses, in route order", function()
	local plan = ns.Bundled.Get("b:hall-of-thanes")
	T.ok(plan, "recommended plan")
	local list = Steps.Build(plan)
	-- Portal, the Ghostly Attendant on the way in, Faldrim, the Summoner patrol then Magmatus (stop 3), Plunder (placed
	-- by the imported route), the final pack then Durgen.
	T.eq(describe(list), "entrance:m5,marker:m6,boss:e1,pull:u1,boss:e2,boss:e3,pull:u2,boss:e4")
	T.eq(list[4].x, 0.7, "the patrol's pull step is where its pack stands")
	T.eq(list[4].stop, 3, "and belongs to stop 3")
	-- "Next pull" from each step: the first pull at or after it.
	local want = { 4, 4, 4, 4, 7, 7, 7, false }
	for i = 1, #list do
		T.eq(Steps.Next(list, i, "pull") or false, want[i], "next pull from step " .. i)
	end
	local _, pull = Steps.Next(list, 1, "pull")
	T.eq(pull.pull, "u1", "step 1's next pull is the Summoner patrol")
	-- The route's projection orders a pull no stop covers.
	local t1 = Steps.Project(plan.routes[1], 0.51, 0.8)
	local t2 = Steps.Project(plan.routes[1], 0.51, 0.66)
	T.ok(t1 < t2, "the Attendant is before Faldrim along the route")
end)

T.case("Steps: a pull no stop covers goes where the route passes it; far from the route, by pull order", function()
	local plan = ns.Validate.Plan({
		id = "steps-along",
		name = "Along",
		instance = { name = "Along Keep", kind = "dungeon" },
		floors = { { name = "Hall" } },
		pulls = { { id = "u1", name = "Far pack" }, { id = "u2", name = "Mid pack" } },
		encounters = { { id = "e1", name = "End boss" } },
		markers = {
			{ id = "m1", floor = 1, x = 0.1, y = 0.5, kind = "entrance" },
			{ id = "m2", floor = 1, x = 0.5, y = 0.52, kind = "pack", pull = "u2" },
			{ id = "m3", floor = 1, x = 0.9, y = 0.5, kind = "boss", encounter = "e1" },
			{ id = "m4", floor = 1, x = 0.5, y = 0.95, kind = "pack", pull = "u1" },
			{ id = "m5", floor = 1, x = 0.3, y = 0.49, kind = "npc", label = "Guide" },
		},
		routes = { { id = "r1", floor = 1, color = 1, points = { { 0.1, 0.5, step = 1 }, { 0.9, 0.5, step = 2 } } } },
	})
	T.eq(describe(Steps.Build(plan)), "entrance:m1,marker:m5,pull:u1,pull:u2,boss:e1", "u1 by pull order: before u2")
end)

T.case("Map layout: dense points merge into groups", function()
	local pts = { { x = 0, y = 0 }, { x = 3, y = 0 }, { x = 50, y = 50 }, { x = 52, y = 49 }, { x = 200, y = 0 } }
	local groups = ns.MapLayout.Cluster(pts, 9)
	T.eq(#groups, 3)
	T.eq(#groups[1].members, 2)
	T.eq(groups[1].x, 1.5)
	T.eq(#ns.MapLayout.Cluster(pts, 9, 2), 2, "limited")
end)

-- Path length along pts up to a mark on segment m.seg.
local function along(pts, m)
	local d = 0
	for i = 2, m.seg - 1 do
		d = d + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
	end
	local a = pts[m.seg - 1]
	return d + math.sqrt((m.x - a[1]) ^ 2 + (m.y - a[2]) ^ 2)
end

T.case("Route marks: chevrons spaced by screen distance, clear of stops, one per leg even through tight bends", function()
	local RM = ns.MapLayout.RouteMarks
	local o = { spacing = 72, size = 18, stopGap = 14, bendGap = 3 }
	-- A long straight leg: marks every 72 units, none within a stop's gap.
	local straight = { { 0, 0, stop = true }, { 300, 0, stop = true } }
	local marks, joints = RM(straight, o)
	T.eq(#marks, 4, "four on 300 units")
	T.eq(#joints, 0)
	for i, m in ipairs(marks) do
		T.ok(m.x >= 14 + 9 and m.x <= 300 - 14 - 9, "clear of the stops: " .. m.x)
		T.eq(m.angle, 0, "pointing along the segment")
		if i > 1 then
			T.eq(m.x - marks[i - 1].x, 72, "regular spacing")
		end
	end
	-- Zoomed in twice as far: twice the screen length, about twice the marks (the spacing is on screen).
	T.ok(#RM({ { 0, 0, stop = true }, { 600, 0, stop = true } }, o) >= 7, "denser path, same on-screen spacing")
	-- Too short for a mark between two stops: none.
	T.eq(#RM({ { 0, 0, stop = true }, { 40, 0, stop = true } }, o), 0, "no clutter on a short leg")
	-- A corridor route: a leg of many 10-unit zigzags, none long enough for a mark of its own, still gets one, in the
	-- middle of the leg; every bend gets a joint.
	local zig = { { 0, 0, stop = true } }
	for i = 1, 19 do
		zig[#zig + 1] = { i * 10, (i % 2) * 6 }
	end
	zig[#zig + 1] = { 200, 0, stop = true }
	marks, joints = RM(zig, o)
	T.eq(#marks, 1, "one mark for the whole leg")
	T.ok(math.abs(along(zig, marks[1]) - along(zig, { seg = #zig, x = 200, y = 0 }) / 2) < 1, "at the leg's middle")
	T.eq(#joints, 19, "a joint at each bend")
	-- A long path of 40-unit bends: marks on many segments, but never closer than half a spacing along the path.
	local bends = { { 0, 0, stop = true } }
	for i = 1, 30 do
		bends[#bends + 1] = { i * 40, (i % 2) * 8, stop = i == 30 }
	end
	marks = RM(bends, o)
	T.ok(#marks >= 15, "marks along the way: " .. #marks)
	for i = 2, #marks do
		T.ok(along(bends, marks[i]) - along(bends, marks[i - 1]) >= 36 - 1e-6, "never denser than half a spacing")
	end
	-- Straight on through a bend point: no joint.
	local _, j2 = RM({ { 0, 0, stop = true }, { 100, 0 }, { 200, 0, stop = true } }, o)
	T.eq(#j2, 0, "no joint where the path runs straight on")
	T.eq(#RM({ { 0, 0 } }, o), 0, "a single point draws nothing")
	T.eq(#RM(straight, { spacing = 10, size = 4, limit = 3 }), 3, "bounded")
end)

T.case("Route paths: outlined lines, joints at bends, chevrons; the focused step's segment brighter, the rest dimmed", function()
	boot()
	ns.UI.SelectPlan("b:ragefire-chasm")
	ns.UI.SelectTab("map")
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local plan = { routes = { { id = "rx", floor = 1, color = 1, points = {
		{ 0.1, 0.5, step = 1 }, { 0.3, 0.5 }, { 0.3, 0.2 }, { 0.6, 0.2, step = 2 }, { 0.9, 0.6, step = 3 } } } } }
	local function px(x)
		return x * 1000
	end
	local function py(y)
		return -y * 600
	end
	local n = canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1 })
	T.eq(n.lines, 4)
	T.eq(n.outlines, 4, "a dark outline under every segment")
	T.eq(n.joints, 2, "a joint at each of the two bends (stops have their own disc)")
	T.ok(n.arrows >= 4, "chevrons along the path: " .. n.arrows)
	local pools = canvas.pools
	T.eq(pools.arrows[1]:GetTexture(), ns.Style.MEDIA .. "Chevron")
	local or1, og1, ob1 = pools.outlines[1]:GetVertexColor()
	T.ok(or1 < 0.1 and og1 < 0.1 and ob1 < 0.1, "the outline is dark")
	-- Focus on the step reached by segments 2..4 (points 1 -> 4): brighter there, dimmed after.
	n = canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1, seg = { route = "rx", from = 1, to = 4 } })
	local _, g1, b1, a1 = pools.lines[1]:GetVertexColor()
	local r4, g4, b4, a4 = pools.lines[4]:GetVertexColor()
	local base = { ns.Style.PaletteColor(1) }
	T.ok(g1 > base[2] and b1 > base[3] and a1 == 1, "focused segment brighter")
	T.ok(r4 == base[1] and g4 == base[2] and b4 == base[3] and a4 < 0.5, "the rest dimmed")
	-- Pooled: a second draw creates nothing new, fewer routes hide the rest.
	local made = #pools.lines
	canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1 })
	T.eq(#pools.lines, made, "lines reused")
	canvas:DrawRoutePaths(nil)
	T.ok(not pools.lines[1]:IsShown() and not pools.arrows[1]:IsShown() and not pools.joints[1]:IsShown(), "all hidden")
	-- The icon-size setting scales the spacing: larger icons, fewer chevrons on the same path.
	local big = canvas:DrawRoutePaths(plan, 1, px, py, { scale = 2 })
	T.ok(big.arrows < n.arrows, "fewer, larger chevrons at 200%")
	-- A chevron file the client cannot open yet (added while the game runs): the older arrow stands in.
	for i = #pools.arrows, 1, -1 do
		pools.arrows[i]:Hide()
		pools.arrows[i] = nil
	end
	mock.missingTextures = { [ns.Style.MEDIA .. "Chevron"] = true }
	canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1 })
	T.eq(pools.arrows[1]:GetTexture(), ns.Style.MEDIA .. "Arrow")
	mock.missingTextures = nil
	for i = #pools.arrows, 1, -1 do
		pools.arrows[i]:Hide()
		pools.arrows[i] = nil
	end
	canvas:DrawContent()
end)

T.case("War table: clicking a step focuses the map on its floor, segment and boss", function()
	boot()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	ns.UI.SelectPlan(plan.id)
	local page = _G.DungeonPlannerMainFrame.instancePage
	T.ok(page.side:IsShown(), "side panel")
	local list = ns.UI.ctx:Steps()
	T.ok(#page.side.list.items == #list and #list > 0, "steps listed")
	ns.UI.SelectTab("pulls")
	local tara = Steps.IndexOfEncounter(list, "e2")
	-- Click the row of that step.
	page.side.list:ScrollTo(tara)
	local clicked
	for _, row in ipairs(page.side.list.rows) do
		if row.index == tara then
			row:GetScript("OnClick")(row, "LeftButton")
			clicked = true
		end
	end
	T.ok(clicked, "row found")
	T.eq(ns.db.ui.tab, "map", "the map opens")
	T.eq(ns.UI.ctx:StepIndex(), tara)
	T.eq(ns.UI.ctx.focusEncounter, "e2", "the boss's party positions show")
	T.ok(ns.UI.ctx.focusSegment and ns.UI.ctx.focusSegment.route == "r1", "route segment in focus")
	local map = page.panels.map
	T.ok(map.canvas.zoom >= 1.5, "zoomed in on the step")
	map.canvas:DrawContent()
	T.ok(map.canvas.counts.pins >= 4, "the boss's positions are drawn")
	local selectedRow
	for _, row in ipairs(page.side.list.rows) do
		if row.index == tara then
			selectedRow = row
		end
	end
	T.ok(selectedRow.dpSelected, "the current step is the list's one highlight")
	-- Party strip: five dungeon slots.
	local shown = 0
	for _, slot in ipairs(page.side.party.slots) do
		if slot:IsShown() then
			shown = shown + 1
		end
	end
	T.eq(shown, 5, "tank, healer, three damage")
end)

T.case("Run mode: steps with Prev / Next and the pull keys; a boss kill moves on", function()
	boot()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	ns.UI.SelectPlan(plan.id)
	ns.db.ui.step = nil
	ns.RunMode.Show()
	local f = _G.DungeonPlannerRunFrame
	T.ok(f and f:IsShown(), "run window")
	T.eq(f.next.label:GetText(), ns.L["Start"])
	f.next:GetScript("OnClick")(f.next, "LeftButton")
	T.eq(ns.UI.ctx:StepIndex(), 1)
	_G.DungeonPlanner_Binding("nextPull")
	T.eq(ns.UI.ctx:StepIndex(), 2, "the next-pull key walks the steps while run mode is open")
	_G.DungeonPlanner_Binding("previousPull")
	T.eq(ns.UI.ctx:StepIndex(), 1)
	T.ok(f.pull.title:GetText():find("Pull 1", 1, true), "next pull shown: " .. tostring(f.pull.title:GetText()))
	T.ok(f.boss.title:GetText() ~= "", "next boss shown")
	T.ok(f.map:IsShown(), "mini map")
	-- A kill of a plan boss (matched by name) moves past its step.
	local list = ns.UI.ctx:Steps()
	local tara = Steps.IndexOfEncounter(list, "e2")
	ns.RunMode.OnKill(999001, "Taragaman the Hungerer")
	T.eq(ns.UI.ctx:StepIndex(), tara + 1)
	-- Through the tracker's event too.
	local jerg = Steps.IndexOfEncounter(list, "e3")
	ns:Fire("BOSS_KILLED", 999002, "Jergosh the Invoker")
	T.eq(ns.UI.ctx:StepIndex(), jerg + 1)
	-- Toggle binding; position saved.
	_G.DungeonPlanner_Binding("runMode")
	T.ok(not f:IsShown(), "toggled off")
	T.eq(ns.db.ui.run.shown, false)
	_G.DungeonPlanner_Binding("runMode")
	T.ok(f:IsShown())
	ns.RunMode.Hide()
	T.ok(_G.BINDING_NAME_DUNGEONPLANNER_RUN_MODE, "binding name")
end)

T.case("Enemies layer: drawn from spawn data, decluttered, without doubling the plan's pins; hidden without data", function()
	boot()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local real = ns.Spawns
	ns.Spawns = {
		Available = function()
			return true
		end,
		For = function(_, floor)
			if floor ~= 1 then
				return {}
			end
			return {
				{ x = 0.41, y = 0.58, name = "Taragaman the Hungerer", kind = "boss" }, -- on the plan's own boss marker
				{ x = 0.2, y = 0.2, name = "Trogg", kind = "mob", level = 13 },
				{ x = 0.2005, y = 0.2005, name = "Trogg", kind = "mob", level = 13 },
				{ x = 0.8, y = 0.3, name = "Shaman", kind = "elite", level = 14 },
				{ x = 0.9, y = 0.9, name = "Rare one", kind = "rare" },
				{ x = 0.95, y = 0.05, name = "Portal in", kind = "npc" }, -- a marker's name
			}
		end,
	}
	ns.db.ui.mapLayers.spawns = nil
	ns.db.ui.legendFolded = false -- the legend open (its rows)
	map:Refresh()
	ns.db.ui.legendFolded = nil
	T.eq(map.canvas.counts.spawns, 3, "two trogs merged, the boss and the named NPC skipped")
	local spawnRow
	for _, row in ipairs(map.legend.rows) do
		if row.layer.id == "spawns" then
			spawnRow = row
		end
	end
	T.ok(spawnRow:IsShown(), "legend row")
	T.ok(spawnRow.check:GetChecked(), "on by default for a recommended plan")
	local dot = map.canvas.pools.spawns[1]
	T.eq(#dot.members, 2, "the merged dot holds both")
	dot:GetScript("OnEnter")(dot)
	spawnRow.check:GetScript("OnClick")(spawnRow.check)
	T.eq(ns.db.ui.mapLayers.spawns, false)
	map.canvas:DrawContent()
	T.eq(map.canvas.counts.spawns, 0, "switched off")
	ns.db.ui.mapLayers.spawns = nil
	-- A failing or empty module: nothing drawn, row hidden.
	ns.Spawns = { Available = function()
		error("broken")
	end, For = function() end }
	map:Refresh()
	T.eq(map.canvas.counts.spawns, 0)
	T.ok(not spawnRow:IsShown(), "row hidden without data")
	ns.Spawns = nil
	map:Refresh()
	T.eq(map.canvas.counts.spawns, 0, "module missing")
	ns.Spawns = real
	map:Refresh()
end)

T.case("Home: an instance table with a preview; a plate where the game has no picture", function()
	boot()
	ns.UI.GoHome("dungeons")
	local home = _G.DungeonPlannerMainFrame.home
	T.ok(home.list:IsShown() and home.preview:IsShown(), "table and preview")
	local thanes
	for i, e in ipairs(home.list.items) do
		if e.name == "Hall of Thanes" then
			thanes = i
		end
	end
	T.ok(thanes, "Hall of Thanes listed")
	local function pick(index)
		home.list:ScrollTo(index)
		for _, row in ipairs(home.list.rows) do
			if row.index == index then
				row:GetScript("OnClick")(row, "LeftButton")
			end
		end
	end
	-- A Forever dungeon that is not out yet (no loading screen it can read, no addon picture): the drawn plate.
	local unopened
	for i, e in ipairs(home.list.items) do
		if e.name == "Blackmaw Hold" then
			unopened = i
		end
	end
	T.ok(unopened, "Blackmaw Hold listed")
	pick(unopened)
	local plate = home.preview.plate
	T.eq(plate.hasArt, false, "no picture for Blackmaw Hold")
	T.ok(plate.emblem:IsShown(), "the drawn plate's emblem")
	pick(thanes)
	T.eq(ns.db.ui.homeSelected, home.list.items[thanes].key)
	T.eq(plate.hasArt, true, "Hall of Thanes: Forever's own loading screen")
	T.ok(not plate.emblem:IsShown(), "a picture, no emblem")
	T.eq(home.preview.facts[1].value:GetText(), "LV 13-20", "levels from the browse list")
	home.preview.open:GetScript("OnClick")(home.preview.open, "LeftButton")
	T.eq(ns.db.ui.view, "instance", "Open plan opens the war table")
	ns.UI.GoHome("dungeons")
end)
