-- Cost checks that fail on regressions: the steps of a plan at the schema's limits, a pan that moves the canvas without
-- redrawing, one refresh of the map per edit, and the per-revision caches of the Enemies layer and the boss portraits.
--
-- Cost is counted in Lua VM instructions (wowui.perf.count), not timed. These checks used to compare
-- os.clock readings and failed now and then: on Windows os.clock is wall time, so any other load on the machine lands
-- in the reading, and a garbage collection step paid for earlier tests' garbage can fall inside one measured call
-- (Steps.Build allocates a lot). An instruction count is the same on every run and every machine.
local T = ...
local ns, mock = T.ns, T.mock
local MAX = ns.Schema.MAX
local Perf = require("wowui.perf")

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.UI.Show()
end

-- A plan at every list limit on one floor: 500 markers (bosses, packs in pulls, quest givers and other notable markers
-- the route passes), 20 routes of 200 points with a numbered stop on every fourth, 100 pulls, 40 bosses, 100
-- objectives. `scatter`: route points anywhere on the map (the worst case for the route index) instead of a walk.
local function limitPlan(scatter)
	local seed = 7
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local p = { id = "perf", floors = { { name = "Floor" } }, markers = {}, routes = {}, pulls = {}, encounters = {},
		objectives = {} }
	for i = 1, MAX.pulls do
		p.pulls[i] = { id = "u" .. i, name = "Pull " .. i }
	end
	for i = 1, MAX.encounters do
		p.encounters[i] = { id = "e" .. i, name = "Boss " .. i }
	end
	for i = 1, MAX.objectives do
		p.objectives[i] = { id = "o" .. i, text = "Objective", encounter = "e" .. (i % MAX.encounters + 1) }
	end
	local kinds = { "quest_npc", "npc", "quest_item", "interactive", "pack" }
	for i = 1, MAX.markers do
		local m = { id = "m" .. i, floor = 1, x = rnd(), y = rnd(), label = "" }
		if i <= MAX.encounters then
			m.kind, m.encounter = "boss", "e" .. i
		else
			m.kind = kinds[i % #kinds + 1]
			if m.kind == "pack" then
				m.pull = "u" .. (i % MAX.pulls + 1)
			end
		end
		p.markers[i] = m
	end
	local step = 0
	for r = 1, MAX.routes do
		local route = { id = "r" .. r, floor = 1, color = 1, points = {} }
		local x, y = rnd(), rnd()
		for k = 1, MAX.routePoints do
			if scatter then
				x, y = rnd(), rnd()
			else
				x = math.max(0, math.min(1, x + (rnd() - 0.5) * 0.08))
				y = math.max(0, math.min(1, y + (rnd() - 0.5) * 0.08))
			end
			local pt = { x, y }
			if k % 4 == 0 and step < ns.Schema.MAX_STEP then
				step = step + 1
				pt.step = step
			end
			route.points[k] = pt
		end
		p.routes[r] = route
	end
	return p
end

-- Thousands of Lua VM instructions that fn runs (wowui.perf; a C function counts as the instruction that calls it).
local function cost(fn)
	return math.floor(Perf.count(fn) / 1000)
end

T.case("Perf: Steps.Build at the schema's limits", function()
	local walk, scatter = limitPlan(false), limitPlan(true)
	local n
	local c = cost(function()
		n = #ns.Steps.Build(walk)
	end)
	T.ok(n > 1000, "every stop, pull, boss, notable marker and objective: " .. n)
	T.eq(cost(function()
		ns.Steps.Build(walk)
	end), c, "the same count on every run")
	-- Counted 4.8 million instructions (about 0.03 s here; 0.45 s before the follow-ups).
	T.ok(c < 7000, string.format("steps of a plan at the limits: %dk instructions", c))
	c = cost(function()
		ns.Steps.Build(scatter)
	end)
	-- Counted 12.7 million.
	T.ok(c < 18000, string.format("with routes scattered over the map: %dk instructions", c))
	-- Half the plan costs about half (near-linear, not quadratic).
	local half = limitPlan(false)
	for _, key in ipairs({ "markers", "routes", "pulls", "objectives" }) do
		for i = #half[key], math.floor(#half[key] / 2) + 1, -1 do
			half[key][i] = nil
		end
	end
	local full = cost(function()
		ns.Steps.Build(walk)
	end)
	local halfCost = cost(function()
		ns.Steps.Build(half)
	end)
	-- Counted 4809k against 2069k (2.3 times); quadratic work would cost about four times as much.
	T.ok(full < 3 * halfCost, string.format("double the plan, %dk against %dk instructions", full, halfCost))
end)

T.case("Perf: a pan moves the canvas only; one layout on release", function()
	boot()
	local entry = ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
	local plan = ns.Home.CreatePlan("dungeon", "Perf pan", entry)
	ns.UI.SelectTab("map")
	local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	for i = 1, 60 do
		ns.Plan.AddMarker(plan, 1, (i % 10) / 10, math.floor(i / 10) / 7, "pack")
	end
	ns.UI.ctx:Changed("markers")
	local cx = 100
	mock.SetCursor(cx, 100)
	mock.SetMouseButtonDown("LeftButton", true)
	local layouts, draws, realLayout, realDraw = 0, 0, view.Layout, view.DrawContent
	view.Layout = function(...)
		layouts = layouts + 1
		return realLayout(...)
	end
	view.DrawContent = function(...)
		draws = draws + 1
		return realDraw(...)
	end
	mock.FireScript(view, "OnMouseDown", "LeftButton")
	local c = cost(function()
		for _ = 1, 100 do
			cx = cx + 2
			mock.SetCursor(cx, 100)
			mock.FireScript(view, "OnUpdate", 0.016)
		end
	end)
	T.eq(draws + layouts, 0, "100 pointer moves, no layout")
	-- Counted 151k: about 1.5k a move, where one layout of this map costs about 740k.
	T.ok(c < 250, string.format("100 pan moves: %dk instructions", c))
	mock.SetMouseButtonDown("LeftButton", false)
	mock.FireScript(view, "OnMouseUp", "LeftButton")
	T.eq(layouts, 1, "one layout on release")
	view.Layout, view.DrawContent = realLayout, realDraw
	mock.ResetInput()
	ns.DB.DeletePlan(plan.id)
end)

T.case("Perf: one edit refreshes the map once", function()
	boot()
	local entry = ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
	local plan = ns.Home.CreatePlan("dungeon", "Perf refresh", entry)
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local count, real = 0, map.RefreshNow
	map.RefreshNow = function(...)
		count = count + 1
		return real(...)
	end
	ns.Plan.AddMarker(plan, 1, 0.5, 0.5, "pack")
	ns.UI.ctx:Changed("markers")
	T.eq(count, 1, "one refresh for one edit")
	count = 0
	ns.UI.SelectTab("pulls")
	ns.UI.SelectTab("map")
	T.eq(count, 1, "one when the section is shown")
	map.RefreshNow = real
	ns.DB.DeletePlan(plan.id)
end)

T.case("Perf: the Enemies layer and boss portraits are computed once per plan revision", function()
	boot()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	local realSpawns, calls = ns.Spawns, 0
	ns.Spawns = {
		Available = function()
			return true
		end,
		For = function()
			calls = calls + 1
			return { { x = 0.2, y = 0.2, name = "Trogg", kind = "mob" } }
		end,
	}
	local a = ns.MapSpawns.Visible(plan, 1)
	local b = ns.MapSpawns.Visible(plan, 1)
	T.eq(a, b, "the same list")
	T.eq(calls, 1, "read once")
	ns.MapSpawns.Visible(plan, 2)
	T.eq(calls, 2, "per floor")
	local own = ns.Util.DeepCopy(plan)
	own.bundled = nil
	ns.MapSpawns.Visible(own, 1)
	ns.DB.Changed(own, "markers")
	ns.MapSpawns.Visible(own, 1)
	T.eq(calls, 4, "again after a change")
	ns.Spawns = realSpawns
	-- Portraits.
	local enc = own.encounters[1]
	local realFor, pairs_ = ns.Journal.EncounterFor, 0
	ns.Journal.EncounterFor = function(...)
		pairs_ = pairs_ + 1
		return realFor(...)
	end
	for _ = 1, 20 do
		ns.Journal.BossArt(own, enc)
	end
	T.ok(pairs_ <= 2, "matched once, not per call: " .. pairs_)
	local before = pairs_
	ns.DB.Changed(own, "encounters")
	ns.Journal.BossArt(own, enc)
	T.ok(pairs_ > before, "and again after a change")
	ns.Journal.EncounterFor = realFor
end)

T.case("Perf: a route point drag redraws Wailing Caverns' routes in their plain look", function()
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns"))
	local route = copy.routes[1]
	ns.UI.ctx.tool, ns.UI.ctx.floor, ns.UI.ctx.activeRoute = "route", route.floor, route.id
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local function paths()
		local a = view.routeArgs
		return view:DrawRoutePaths(a[1], a[2], a[3], a[4], a[5])
	end
	-- One redraw at rest and one while the point is dragged, at a zoom (centred), after a warm-up redraw.
	local function measure(zoom)
		view.zoom = zoom
		view:Layout()
		view.ox = (view:GetWidth() - view.canvas:GetWidth()) / 2
		view.oy = (view:GetHeight() - view.canvas:GetHeight()) / 2
		view:Layout()
		local m = {}
		m.still = cost(function()
			view:DrawContent()
		end)
		m.stillPaths, m.full = cost(paths), view.routeCounts
		view.drag = { mode = "point", routeId = route.id, index = 2 }
		m.dragged = cost(function()
			view:DrawContent()
		end)
		m.draggedPaths = cost(paths)
		m.segments = 0
		for _, path in ipairs(view.routeJobs.paths) do
			m.segments = m.segments + #path.pts - 1
		end
		m.drag = { dashes = view.routeCounts.dashes, lines = view.routeCounts.lines, arrows = view.counts.arrows }
		-- Released: the full look again once the settle timer runs.
		view.drag = { mode = "idle" }
		mock.Advance(0.2)
		m.released = { dashes = view.routeCounts.dashes, arrows = view.counts.arrows }
		return m
	end
	view:DrawContent()
	local whole, close = measure(1), measure(4)
	for _, m in ipairs({ whole, close }) do
		-- While dragging: one piece per drawn segment, no dashes, no arrows; the full look on release.
		T.eq(m.drag.dashes, 0, "no dashes while dragging")
		T.eq(m.drag.lines, m.segments, "one piece per segment")
		T.eq(m.drag.arrows, 0, "no arrows while dragging")
		T.eq(m.released.dashes, m.full.dashes, "dashed again on release")
		T.ok(m.released.arrows > 0, "arrows again on release")
	end
	T.ok(whole.full.dashes > 0 and close.full.dashes > whole.full.dashes, "at rest: the way back dashed")
	-- Counted alone (lua tests/run.lua "Perf: a route point"), whole map / zoom 4: a redraw while dragging 3660k / 2760k
	-- (before the plain look 3706k / 2820k), its route paths 543k / 806k (554k / 830k). Most of a path's cost is the
	-- lane split (RouteLegs.Lanes, about 60%), which the plain look keeps; the rest of the redraw is pins and labels.
	-- Since lanes cost the same at any zoom and label placement passes over boxes that lie apart: a redraw while
	-- dragging 1785k / 1072k; its route paths drawn again with the same points 228k / 290k (the lanes reused).
	for _, m in ipairs({ whole, close }) do
		T.ok(m.draggedPaths < m.stillPaths and m.drag.lines < m.full.lines, string.format(
			"paths while dragging: %dk in %d pieces against %dk in %d", m.draggedPaths, m.drag.lines, m.stillPaths,
			m.full.lines))
	end
	view.zoom = 1
	view:Layout()
	ns.UI.ctx.tool, ns.UI.ctx.activeRoute = "select", nil
	ns.DB.DeletePlan(copy.id)
end)
