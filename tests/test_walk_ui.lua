-- Snap to corridors in the map editor, end to end against the mock client: the route tool's switch, a click that
-- snaps its leg at once (one undo step), two clicks in a row, Shift-click for a straight leg, snapping off, dragging a
-- stop with the Route tool (its legs found again in one step; Shift: straight; a straight leg kept or snapped by
-- whether its line was clear, through the drag's real pointer moves) and with Select (moves alone), the floor's
-- corridor data prepared when the route tool is chosen or the floor changes (and not otherwise) and let go when the map
-- hides or the tool changes, a click before that is done, undo and another plan while it runs, nothing running when
-- idle, an extra floor not yet in the plan, and the notices. Mostly on an own copy of the Deadmines, whose floors have
-- the old map tiles' grid.
local T = ...
local ns, mock = T.ns, T.mock
local Walk, Corridors = ns.Walk, ns.Corridors

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

-- An own copy of the Deadmines without routes, its map open on floor 1 with the Route tool.
local function routeMap()
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get("b:the-deadmines"))
	copy.routes = {}
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local ctx = ns.UI.ctx
	ctx.tool, ctx.floor, ctx.activeRoute = "route", 1, nil
	ns.db.ui.snapRoutes = true
	map:RefreshNow()
	return copy, map, map.canvas, ctx
end

local function shift(down)
	mock.SetKeyDown("SHIFT", down)
end

-- Frames until the preparation in progress is done.
local function prepared()
	for _ = 1, 20 do
		if not Corridors.Preparing() then
			return
		end
		mock.Advance(0.016)
	end
	error("still preparing")
end

-- Every piece between consecutive points from index i to j crosses floor (or a drawn wall or door where it must),
-- never the blank parchment; a stop placed off the floor may reach it across the cells within 2 of it (Walk.Path's
-- snap), and that piece is checked too.
local function walkable(plan, route, i, j)
	local g = Corridors.Grid(Corridors.KeyFor(plan, route.floor))
	local allow = setmetatable({}, { __index = g.rough })
	for k = i, j do
		local p = route.points[k]
		local cx, cy = math.floor(p[1] * g.w), math.floor(p[2] * g.h)
		if p.step and not Walk.Open(g, cx, cy) then
			for y = math.max(0, cy - 2), math.min(g.h - 1, cy + 2) do
				for x = math.max(0, cx - 2), math.min(g.w - 1, cx + 2) do
					allow[(y + 1) * g.stride + x + 2] = true
				end
			end
		end
	end
	for k = i + 1, j do
		local p, q = route.points[k - 1], route.points[k]
		if not Walk.Clear(g, p[1] * g.w, p[2] * g.h, q[1] * g.w, q[2] * g.h, allow) then
			return false, string.format("piece %d of %d: %.4f,%.4f -> %.4f,%.4f", k, j, p[1], p[2], q[1], q[2])
		end
	end
	return true
end

-- The index of a route's stop number n.
local function stopIndex(route, n)
	for i, p in ipairs(route.points) do
		if p.step == n then
			return i
		end
	end
	return nil
end

local function walkableOk(msg, ok, why)
	T.ok(ok, msg .. ": " .. tostring(why))
end

-- Two of the recommended plan's stops on floor 1 that no straight line joins.
local function farStops()
	local plan = ns.Bundled.Get("b:the-deadmines")
	local stops = {}
	for _, r in ipairs(plan.routes) do
		if r.floor == 1 then
			for _, p in ipairs(r.points) do
				if p.step then
					stops[#stops + 1] = p
				end
			end
		end
	end
	local a, b = stops[1], stops[#stops]
	T.ok(not Corridors.Clear(plan, 1, a[1], a[2], b[1], b[2]), "the first and last stops are not in sight of each other")
	return a, b
end

local function undoCount()
	return #ns.UI.history.undo
end

-- The map panel's tool button clicked.
local function chooseTool(map, tool)
	local b = map.toolButtons[tool]
	mock.Click(b)
end

-- Route point `index` dragged with the pointer to plan point (x, y) and dropped: the drag a point pin's OnDragStart
-- starts (UI/MapCanvas.lua), a frame of the map's OnUpdate (OnDragUpdate reads GetCursorPosition), then the release.
-- Returns where the drag noted the point was (fromX, fromY), or nil.
local function dragPoint(view, route, index, x, y)
	local c = view.canvas
	local s = c:GetEffectiveScale()
	local cursor = { (c:GetLeft() + x * c:GetWidth()) * s, (c:GetTop() - y * c:GetHeight()) * s }
	local from
	mock.WithInput({ cursor = cursor, buttons = { "LeftButton" } }, function()
		view.drag = { mode = "point", routeId = route.id, index = index }
		view:SetScript("OnUpdate", view.OnDragUpdate)
		mock.Advance(0.016)
		from = view.drag.fromX and { view.drag.fromX, view.drag.fromY }
		view:EndDrag()
	end)
	return from
end

-- Two floor points s and c on the Deadmines' floor 1 in sight of each other, from c no line to plan point b but a
-- path round the walls.
local function inSight(plan, b)
	local g = Corridors.Grid(Corridors.KeyFor(plan, 1))
	for cy = 0, g.h - 1, 3 do
		for cx = 0, g.w - 1, 3 do
			if Walk.Open(g, cx, cy) and Walk.Open(g, cx + 4, cy) then
				local s = { ns.Util.Round((cx + 0.5) / g.w, 4), ns.Util.Round((cy + 0.5) / g.h, 4) }
				local c = { ns.Util.Round((cx + 4.5) / g.w, 4), s[2] }
				if Corridors.Clear(plan, 1, s[1], s[2], c[1], c[2]) and not Corridors.Clear(plan, 1, s[1], s[2], b[1], b[2]) then
					local bends = Corridors.Leg(plan, 1, s[1], s[2], b[1], b[2])
					if bends and #bends > 0 then
						return s, c
					end
				end
			end
		end
	end
	error("no pair of points in sight of each other")
end

T.case("Snap UI: the route tool shows the switch; a click snaps the leg at once, one undo step", function()
	local plan, map, canvas, ctx = routeMap()
	T.ok(map.snapBox:IsShown() and map.snap:IsVisible(), "the switch over the map's corner controls")
	chooseTool(map, "select")
	T.ok(not map.snapBox:IsShown(), "only with the route tool")
	chooseTool(map, "route")
	T.ok(map.snap:GetChecked(), "on by default")
	T.eq(map.snap:GetAlpha(), 1, "the Deadmines has corridor data")
	T.ok(map.help:GetText():find("corridors", 1, true), "the help says what a click does")
	local a, b = farStops()
	shift(false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	local route = plan.routes[1]
	T.eq(#route.points, 1)
	T.eq(route.points[1].step, 1, "a click adds a numbered stop")
	local before = undoCount()
	canvas.cb.onRoutePoint(b[1], b[2], false)
	T.ok(#route.points > 2, "bends between the stops, in the same call: " .. #route.points)
	T.eq(route.points[#route.points].step, 2, "the second stop at the end")
	for i = 2, #route.points - 1 do
		T.eq(route.points[i].step, nil, "the bends are plain points")
	end
	walkableOk("the leg runs through the corridors", walkable(plan, route, 1, #route.points))
	T.eq(undoCount(), before + 1, "one undo step for the stop and its bends")
	T.eq(#ns.UI.history.current.routes[1].points, #route.points, "the step holds the snapped leg")
	ctx:Undo()
	T.eq(#plan.routes[1].points, 1, "undo takes the stop and its bends together")
	ctx:Redo()
	T.eq(plan.routes[1].points[#plan.routes[1].points].step, 2)
	-- The export string carries plain route points: nothing new in the format.
	local kind, back = ns.Codec.Decode(assert(ns.Codec.ExportPlan(plan)))
	T.eq(kind, "plan")
	T.eq(#back.routes[1].points, #plan.routes[1].points, "bends survive an export")
end)

T.case("Snap UI: two clicks in a row give two undo steps, each with its snapped leg", function()
	local plan, _, canvas, ctx = routeMap()
	local a, b = farStops()
	shift(false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	local before = undoCount()
	canvas.cb.onRoutePoint(b[1], b[2], false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	local route = plan.routes[1]
	local second, third = stopIndex(route, 2), stopIndex(route, 3)
	T.ok(second and second > 2 and third and third > second + 1, "both legs snapped: " .. #route.points)
	walkableOk("both legs", walkable(plan, route, 1, #route.points))
	T.eq(undoCount(), before + 2, "one undo step per click")
	ctx:Undo()
	route = plan.routes[1]
	T.eq(route.points[#route.points].step, 2, "undo takes the last stop and its leg")
	T.eq(#route.points, second, "the first leg keeps its bends")
	ctx:Undo()
	T.eq(#plan.routes[1].points, 1, "and then the first")
end)

T.case("Snap UI: Shift-click gives a straight leg; with the switch off a click adds a bend as before", function()
	local plan, map, canvas = routeMap()
	local a, b = farStops()
	shift(false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(b[1], b[2], true)
	local route = plan.routes[1]
	T.eq(#route.points, 2, "Shift: no bends")
	T.eq(route.points[2].step, 2, "but a stop")
	-- Off: the old behaviour (a click is a bend, Shift-click a stop).
	mock.Click(map.snap)
	T.eq(ns.db.ui.snapRoutes, false, "the switch is saved")
	T.ok(not ns.RouteSnap.Active(plan, 1))
	T.ok(not map.help:GetText():find("corridors", 1, true), "the old help")
	canvas.cb.onRoutePoint(a[1], a[2], false)
	T.eq(#route.points, 3)
	T.eq(route.points[3].step, nil, "a bend")
	canvas.cb.onRoutePoint(b[1], b[2], true)
	T.eq(route.points[4].step, 3, "Shift-click: a stop")
	ns.db.ui.snapRoutes = true
end)

T.case("Snap UI: dragging a stop finds both its legs again in one step; Shift on the drop makes them straight", function()
	local plan, _, canvas, ctx = routeMap()
	local a, b = farStops()
	shift(false)
	-- Three stops: a, b, a again; stop 2 has a snapped leg on each side.
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(b[1], b[2], false)
	local route = plan.routes[1]
	local mid = route.points[math.floor(stopIndex(route, 2) / 2) + 1]
	local c = { mid[1], mid[2] }
	canvas.cb.onRoutePoint(a[1], a[2], false)
	local stop2 = stopIndex(route, 2)
	T.ok(stop2 and stop2 > 2 and stop2 < #route.points - 1, "the middle stop, bends on both sides")
	-- Drag stop 2 onto a bend of its first leg and drop it.
	local before = undoCount()
	local pt = route.points[stop2]
	canvas.drag = { mode = "point", routeId = route.id, index = stop2, moved = true, fromX = pt[1], fromY = pt[2] }
	pt[1], pt[2] = c[1], c[2]
	canvas:EndDrag()
	T.eq(undoCount(), before + 1, "one undo step for the drag")
	local moved = stopIndex(route, 2)
	T.eq(route.points[moved], pt, "the same stop")
	T.eq(pt[1], c[1], "where it was dropped")
	walkableOk("both legs found again through the corridors", walkable(plan, route, 1, #route.points))
	T.eq(#ns.UI.history.current.routes[1].points, #route.points, "the step holds both legs")
	-- Shift held on the drop: both legs straight.
	shift(true)
	canvas.drag = { mode = "point", routeId = route.id, index = moved, moved = true, fromX = pt[1], fromY = pt[2] }
	pt[1], pt[2] = b[1], b[2]
	canvas:EndDrag()
	shift(false)
	T.eq(#route.points, 3, "Shift: the stops only")
	T.eq(route.points[2].step, 2)
	-- Undo goes back one drag at a time.
	ctx:Undo()
	T.ok(#plan.routes[1].points > 3, "the snapped legs are back")
	T.eq(plan.routes[1].points[stopIndex(plan.routes[1], 2)][1], c[1], "with the stop where the first drag left it")
	-- A bend dragged is a bend moved: no search.
	route = plan.routes[1]
	local legs = Corridors.stats.legs
	local bend = route.points[2].step and 3 or 2
	local bp = route.points[bend]
	canvas.drag = { mode = "point", routeId = route.id, index = bend, moved = true, fromX = bp[1], fromY = bp[2] }
	canvas:EndDrag()
	T.eq(Corridors.stats.legs, legs, "a bend moves alone")
end)

T.case("Snap UI: choosing the route tool or another floor prepares the floor; other tools and floors do not", function()
	local _, map, _, ctx = routeMap()
	chooseTool(map, "select")
	prepared()
	Corridors.Reset()
	map:RefreshNow()
	T.eq(Corridors.Preparing(), nil, "not with another tool")
	chooseTool(map, "route")
	local key1 = Corridors.KeyFor(ctx:Plan(), 1)
	T.eq(Corridors.Preparing(), key1, "choosing the route tool starts it")
	prepared()
	T.ok(Corridors.Ready(key1), "floor 1 ready")
	map:GoToFloor(2)
	local key2 = Corridors.KeyFor(ctx:Plan(), 2)
	T.ok(key2 and key2 ~= key1)
	T.eq(Corridors.Preparing(), key2, "another floor with the route tool")
	prepared()
	T.ok(Corridors.Ready(key2))
	-- With the switch off, or on a floor without corridor data, nothing is prepared.
	Corridors.Reset()
	ns.db.ui.snapRoutes = false
	map:RefreshNow()
	T.eq(Corridors.Preparing(), nil, "snapping off")
	ns.db.ui.snapRoutes = true
	map:GoToFloor(1)
	T.eq(Corridors.Preparing(), key1, "turned on again: floor 1")
	prepared()
	local outdoor = ns.UI.CopyPlan(ns.Bundled.Get("b:kroldok-stronghold"))
	outdoor.routes = {}
	ns.UI.SelectTab("map")
	ctx.tool = "route"
	Corridors.Reset()
	map:RefreshNow()
	T.eq(Corridors.Preparing(), nil, "no grid, nothing to prepare")
end)

T.case("Snap UI: a click before the floor is prepared finishes it and snaps; idle, nothing runs", function()
	local plan, map, canvas = routeMap()
	local a, b = farStops()
	shift(false)
	Corridors.Reset()
	map:RefreshNow()
	T.ok(Corridors.Preparing(), "preparing")
	canvas.cb.onRoutePoint(a[1], a[2], false)
	mock.Advance(0.016) -- one piece of the preparation
	T.ok(Corridors.Preparing(), "still preparing")
	local before = undoCount()
	canvas.cb.onRoutePoint(b[1], b[2], false)
	local route = plan.routes[1]
	T.ok(#route.points > 2, "snapped in the same call")
	T.eq(Corridors.Preparing(), nil, "the click finished the preparation")
	T.eq(undoCount(), before + 1, "one step")
	-- Idle with the route tool on a prepared floor: no timer is started, no step runs, frame after frame.
	mock.Advance(ns.RouteSnap.NOTICE_SECONDS + 0.1)
	local timer = _G.C_Timer
	local after, ticker = timer.After, timer.NewTicker
	local started = 0
	timer.After = function(...)
		started = started + 1
		return after(...)
	end
	timer.NewTicker = function(...)
		started = started + 1
		return ticker(...)
	end
	local steps = Corridors.stats.steps
	local ok, err = pcall(function()
		for _ = 1, 30 do
			mock.Advance(0.016)
		end
		map:RefreshNow()
		for _ = 1, 30 do
			mock.Advance(0.016)
		end
	end)
	timer.After, timer.NewTicker = after, ticker
	T.ok(ok, tostring(err))
	T.eq(started, 0, "no timer started while idle")
	T.eq(Corridors.stats.steps, steps, "no preparation step")
end)

T.case("Snap UI: undo during a preparation and another plan opened during one: it finishes or moves to the new floor", function()
	local plan, map, canvas, ctx = routeMap()
	local a, b = farStops()
	shift(false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(b[1], b[2], false)
	local snapped = #plan.routes[1].points
	-- Undo and redo while the floor is being prepared again: the preparation carries on to the end.
	Corridors.Reset()
	map:RefreshNow()
	local key = Corridors.Preparing()
	T.ok(key, "preparing")
	ctx:Undo()
	T.eq(#plan.routes[1].points, 1, "undone")
	T.eq(Corridors.Preparing(), key, "the same floor still being prepared")
	ctx:Redo()
	prepared()
	T.ok(Corridors.Ready(key), "prepared")
	T.eq(#plan.routes[1].points, snapped, "redo brings back the snapped leg")
	-- Another plan opened while preparing: its floor is prepared instead, and its clicks snap.
	Corridors.Reset()
	map:RefreshNow()
	T.ok(Corridors.Preparing(), "preparing")
	local hall = ns.UI.CopyPlan(ns.Bundled.Get("b:hall-of-thanes"))
	hall.routes = {}
	ns.UI.SelectTab("map")
	ctx.tool = "route"
	map:RefreshNow()
	T.eq(Corridors.Preparing(), Corridors.KeyFor(hall, 1), "the new plan's floor")
	prepared()
	T.ok(Corridors.Ready(Corridors.KeyFor(hall, 1)))
	local stops = {}
	for _, p in ipairs(ns.Bundled.Get("b:hall-of-thanes").routes[1].points) do
		if p.step then
			stops[#stops + 1] = p
		end
	end
	canvas.cb.onRoutePoint(stops[1][1], stops[1][2], false)
	canvas.cb.onRoutePoint(stops[#stops][1], stops[#stops][2], false)
	local hp = hall.routes[1].points
	T.eq(hp[#hp].step, 2, "a stop on the new plan")
	local s1, s2 = stops[1], stops[#stops]
	T.ok(#hp > 2 or Corridors.Clear(hall, 1, s1[1], s1[2], s2[1], s2[2]), "its leg snapped: " .. #hp)
	T.eq(undoCount(), 2, "one step per click")
end)

T.case("Snap UI: no corridor data, no path or a full route: a straight leg and a notice", function()
	local _, map, canvas = routeMap()
	shift(false)
	-- A copy of an instance whose map has no grid (Krol'dok, open outdoors): the switch fades, clicks add bends as before.
	local outdoor = ns.UI.CopyPlan(ns.Bundled.Get("b:kroldok-stronghold"))
	outdoor.routes = {}
	ns.UI.SelectTab("map")
	ns.UI.ctx.tool, ns.UI.ctx.floor, ns.UI.ctx.activeRoute = "route", 1, nil
	map:RefreshNow()
	T.ok(map.snap:GetAlpha() < 1, "faded: no corridor data here")
	T.ok(not ns.RouteSnap.Active(outdoor, 1))
	canvas.cb.onRoutePoint(0.4, 0.4, false)
	T.eq(outdoor.routes[1].points[1].step, nil, "a bend, as without snapping")
	-- Back on the Deadmines: a stop far off any floor gets a straight leg and the notice.
	local plan = routeMap()
	local a = farStops()
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(0.97, 0.03, false)
	local route = plan.routes[1]
	T.eq(#route.points, 2, "straight")
	T.ok(canvas.snapNotice and canvas.snapNotice:IsShown(), "the notice under the map")
	T.ok(canvas.snapNotice:GetText():find("straight", 1, true))
	mock.Advance(ns.RouteSnap.NOTICE_SECONDS + 0.1)
	T.ok(not canvas.snapNotice:IsShown(), "gone after a few seconds")
	-- A route with almost no room left: the leg stays straight.
	local b = select(2, farStops())
	for _ = 1, ns.Schema.MAX.routePoints - #route.points - 1 do
		ns.Plan.AddRoutePoint(plan, route.id, a[1], a[2])
	end
	canvas.cb.onRoutePoint(b[1], b[2], false)
	T.eq(#route.points, ns.Schema.MAX.routePoints, "full, the last stop added straight")
	T.ok(canvas.snapNotice:GetText():find("full", 1, true), "says the route is full")
	-- One more click: nothing is added, so nothing is recorded.
	local full = undoCount()
	canvas.cb.onRoutePoint(a[1], a[2], false)
	T.eq(#route.points, ns.Schema.MAX.routePoints)
	T.eq(undoCount(), full, "a click on a full route records no undo step")
end)

T.case("Snap UI: a dragged stop keeps a straight leg through a wall; a clear straight leg moved behind one snaps", function()
	local plan, _, canvas = routeMap()
	local a, b = farStops()
	shift(false)
	-- A Shift-click leg through a wall was meant straight: its stop dragged a little keeps it straight.
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(b[1], b[2], true)
	local route = plan.routes[1]
	local before = undoCount()
	local from = dragPoint(canvas, route, 2, b[1] + 0.005, b[2])
	T.ok(from and from[1] == b[1] and from[2] == b[2], "the drag noted where the stop was")
	T.eq(route.points[2][1], ns.Util.Round(b[1] + 0.005, 4), "moved with the pointer")
	T.eq(#route.points, 2, "the leg stays straight")
	T.eq(undoCount(), before + 1, "one step")
	-- A straight leg with a clear line: its stop dragged behind a wall gets its leg found.
	local plan2, map2, canvas2 = routeMap()
	local s, c = inSight(plan2, b)
	canvas2.cb.onRoutePoint(s[1], s[2], false)
	canvas2.cb.onRoutePoint(c[1], c[2], false)
	local route2 = plan2.routes[1]
	T.eq(#route2.points, 2, "in sight: a straight leg")
	dragPoint(map2.canvas, route2, 2, b[1], b[2])
	T.eq(route2.points[#route2.points].step, 2, "the stop at the end")
	T.ok(#route2.points > 2, "bends round the wall: " .. #route2.points)
	walkableOk("the leg found again", walkable(plan2, route2, 1, #route2.points))
end)

T.case("Snap UI: a stop dragged with the Select tool moves alone", function()
	local plan, map, canvas = routeMap()
	local a, b = farStops()
	shift(false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	canvas.cb.onRoutePoint(b[1], b[2], false)
	canvas.cb.onRoutePoint(a[1], a[2], false)
	local route = plan.routes[1]
	local n, stop2 = #route.points, stopIndex(route, 2)
	local bendsBefore = ns.Util.DeepCopy(route.points)
	chooseTool(map, "select")
	local legs, before = Corridors.stats.legs, undoCount()
	local mid = route.points[stop2 - 1]
	dragPoint(canvas, route, stop2, mid[1], mid[2] + 0.002)
	T.eq(Corridors.stats.legs, legs, "no search")
	T.eq(#route.points, n, "the same points")
	for i, p in ipairs(route.points) do
		if i ~= stop2 then
			T.ok(p[1] == bendsBefore[i][1] and p[2] == bendsBefore[i][2], "point " .. i .. " where it was")
		end
	end
	T.eq(route.points[stop2][1], mid[1], "the stop moved")
	T.eq(undoCount(), before + 1, "one step")
end)

T.case("Snap UI: the decoded grids are let go when the map hides or the tool leaves Route", function()
	local _, map, _, ctx = routeMap()
	prepared()
	local key = Corridors.KeyFor(ctx:Plan(), 1)
	T.ok(Corridors.Ready(key), "prepared with the route tool")
	map.canvas:Hide()
	T.ok(not Corridors.Ready(key), "the map hidden: let go")
	map.canvas:Show()
	map:RefreshNow()
	T.eq(Corridors.Preparing(), key, "prepared again when shown with the route tool")
	prepared()
	chooseTool(map, "select")
	T.ok(not Corridors.Ready(key), "another tool: let go")
	T.eq(Corridors.Preparing(), nil)
end)

T.case("Snap UI: an extra floor the plan does not have yet snaps through the grid of the art the map draws", function()
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get("b:alcaz-prison"))
	copy.routes = {}
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local ctx = ns.UI.ctx
	ctx.tool, ctx.activeRoute = "route", nil
	ns.db.ui.snapRoutes = true
	local floors = #copy.floors
	local extra = floors + 1
	local view = ns.Floors.View(copy)
	T.ok(view.floors[extra] and view.floors[extra].extra, "an extra floor after the plan's own")
	local art = view.floors[extra].art
	T.ok(art and art ~= extra, "it shows the art of another position: " .. tostring(art))
	local key = "r:" .. ns.ReyesMaps.Pick(view, extra).file
	Corridors.Reset()
	map:GoToFloor(extra)
	T.eq(Corridors.KeyFor(copy, extra), key, "the grid of the drawn map")
	T.eq(map.snap:GetAlpha(), 1, "not faded")
	T.eq(Corridors.Preparing(), key, "being prepared")
	-- Two floor cells of that grid out of sight of each other, with a path between them.
	local _, align = Corridors.KeyFor(copy, extra)
	local g = Corridors.Grid(key)
	local function plan(cx, cy)
		return { ns.MinimapArt.FromMap(align, (cx + 0.5) / g.w, (cy + 0.5) / g.h) }
	end
	local cells = {}
	for cy = 0, g.h - 1 do
		for cx = 0, g.w - 1 do
			if Walk.Open(g, cx, cy) then
				cells[#cells + 1] = plan(cx, cy)
			end
		end
	end
	local p, q
	for i = 1, #cells, math.ceil(#cells / 16) do
		for k = #cells, i + 1, -math.ceil(#cells / 32) do
			local a, c = cells[i], cells[k]
			if not q and not Corridors.Clear(copy, extra, a[1], a[2], c[1], c[2]) then
				local bends = Corridors.Leg(copy, extra, a[1], a[2], c[1], c[2])
				if bends and #bends > 0 then
					p, q = a, c
				end
			end
		end
	end
	T.ok(q, "a pair of cells to join")
	shift(false)
	local cb = map.canvas.cb
	cb.onRoutePoint(p[1], p[2], false)
	cb.onRoutePoint(q[1], q[2], false)
	T.eq(#copy.floors, extra, "the click made the floor the plan's own")
	T.eq(copy.floors[extra].art, art, "with the art it shows")
	local route = copy.routes[1]
	T.eq(route.floor, extra)
	T.eq(route.points[1].step, 1, "a numbered stop")
	T.ok(#route.points > 2, "the leg snapped: " .. #route.points)
	T.eq(Corridors.KeyFor(copy, extra), key, "the same grid now that the floor is the plan's")
	walkableOk("through the drawn map's corridors", walkable(copy, route, 1, #route.points))
end)
