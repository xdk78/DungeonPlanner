-- Wheel zoom (UI/MapInput.lua ZoomStep, UI/MapRoutes.lua): a burst of ticks redraws the map in its plain look, once
-- per tick, and the full look (dashes, arrows) comes once when the zoom settles; the point under the pointer stays
-- put. The route lanes are worked out again only when the drawn route changed, and stay as cheap at any zoom.
-- Cost is counted in Lua VM instructions (as in tests/test_perf.lua).
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.UI.Show()
end

local function cost(fn)
	local k = 0
	debug.sethook(function()
		k = k + 1
	end, "", 1000)
	local ok, err = pcall(fn)
	debug.sethook()
	assert(ok, err)
	return k
end

-- The map section on a plan, at a usual size, with the pointer near its middle. The mock lays out no anchors, so the
-- canvas reports where its anchor puts it (the zoom's anchor and CursorPosition read it). Returns the view and a
-- function that puts everything back.
local function openMap(planId)
	boot()
	ns.UI.SelectPlan(planId)
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local realGet = _G.GetCursorPosition
	_G.GetCursorPosition = function()
		return 330, 280
	end
	view.canvas.GetLeft = function()
		return view:GetLeft() + view.ox
	end
	view.canvas.GetTop = function()
		return view:GetTop() - view.oy
	end
	view:SetSize(720, 540)
	view.zoom = 1
	view:Layout()
	mock.Advance(0.3)
	return view, function()
		view.canvas.GetLeft, view.canvas.GetTop = nil, nil
		view.zoom = 1
		view:SetSize(400, 300)
		_G.GetCursorPosition = realGet
		mock.Advance(0.3)
	end
end

local function wheel(view, delta)
	view:GetScript("OnMouseWheel")(view, delta)
end

-- What the map shows: every shown route piece, joint, arrow, pin and stop, with its place and look.
local function shown(view)
	local out = {}
	for _, name in ipairs({ "lines", "outlines", "joints", "jointOutlines", "arrows", "pins", "points" }) do
		for i, r in ipairs(view.pools[name] or {}) do
			if r:IsShown() then
				local parts = { name, i }
				for _, key in ipairs({ "_startPoint", "_endPoint", "_vertex", "_coords", "_points" }) do
					for _, v in ipairs(rawget(r, key) or {}) do
						if type(v) == "table" then
							v = v[4] and string.format("%.3f,%.3f", v[4], v[5] or 0) or "rel"
						end
						parts[#parts + 1] = type(v) == "number" and string.format("%.3f", v) or tostring(v)
					end
				end
				parts[#parts + 1] = tostring(rawget(r, "_thickness"))
				out[#out + 1] = table.concat(parts, " ")
			end
		end
	end
	return table.concat(out, "\n")
end

T.case("Zoom: ZoomStep, the wheel zoom's states", function()
	local Z = ns.MapCanvas.ZoomStep
	local SETTLE = ns.MapCanvas.ZOOM_SETTLE
	local d, fx = Z({ mode = "idle" }, "wheel", 10, 1)
	T.eq(d.mode, "zoom")
	T.ok(fx.zoom and fx.wait == SETTLE, "zooms and waits")
	local id = d.id
	T.eq(id, 1, "the id the caller gave")
	local d2, fx2 = Z(d, "wheel", 10.05, 2)
	T.ok(fx2.zoom and not fx2.wait, "another tick: no second timer")
	T.eq(d2.id, id, "the same zoom")
	local d3, fx3 = Z(d2, "timer", 10 + SETTLE, id)
	T.eq(d3.mode, "zoom", "the first tick's timer comes before the zoom ends")
	T.ok(math.abs(fx3.wait - 0.05) < 1e-9 and not fx3.settle, "and waits for the rest")
	local d4, fx4 = Z(d3, "timer", 10.05 + SETTLE, id)
	T.eq(d4.mode, "idle")
	T.ok(fx4.settle, "settles")
	local d5, fx5 = Z(d4, "timer", 11, id)
	T.eq(d5, d4, "a stale timer changes nothing")
	T.ok(not next(fx5))
	local again = Z({ mode = "idle" }, "wheel", 12, 2)
	local _, stale = Z(again, "timer", 13, id)
	T.ok(not next(stale), "an earlier zoom's timer changes nothing in a new zoom")
	local _, ended = Z(again, "press", 12.01)
	T.ok(ended.settle, "a press ends the zoom at once")
	local pan = { mode = "pan" }
	local p2, pfx = Z(pan, "wheel", 14)
	T.ok(p2 == pan and pfx.zoom and not pfx.wait, "a tick during a pan zooms and leaves the pan alone")
	T.ok(not next(select(2, Z(pan, "hide", 14))), "hiding a panning map: not the zoom's business")
end)

T.case("Zoom: a burst of wheel ticks draws plain once per tick, the full look once when it settles", function()
	local view, restore = openMap(ns.Bundled.PREFIX .. "wailing-caverns")
	local rest = view.routeCounts
	T.ok(rest.dashes > 0 and view.counts.arrows > 0, "at rest: dashes and arrows")
	local layouts, draws, places = 0, 0, 0
	local realLayout, realDraw, realPlace = view.Layout, view.DrawContent, ns.RouteArrows.Place
	view.Layout = function(...)
		layouts = layouts + 1
		return realLayout(...)
	end
	view.DrawContent = function(...)
		draws = draws + 1
		return realDraw(...)
	end
	ns.RouteArrows.Place = function(...)
		places = places + 1
		return realPlace(...)
	end
	local function arrowsShown()
		local n = 0
		for _, a in ipairs(view.pools.arrows) do
			n = n + (a:IsShown() and 1 or 0)
		end
		return n
	end
	local x0, y0 = view:CursorPosition()
	T.ok(x0 and y0, "the pointer is over the map")
	for tick = 1, 4 do
		wheel(view, 1)
		mock.Advance(0.05)
		T.eq(layouts, tick, "one layout per tick")
		T.eq(draws, tick, "one redraw per tick")
		T.eq(view.drag.mode, "zoom")
		local x, y = view:CursorPosition()
		T.ok(math.abs(x - x0) < 1e-9 and math.abs(y - y0) < 1e-9, "the point under the pointer stays put")
		local segments = 0
		for _, path in ipairs(view.routeJobs.paths) do
			segments = segments + #path.pts - 1
		end
		T.eq(view.routeCounts.dashes, 0, "no dashes while zooming")
		T.eq(view.routeCounts.lines, segments, "one piece per segment")
		T.eq(view.counts.arrows, 0, "no arrows while zooming")
		T.eq(arrowsShown(), 0, "the arrows placed before are hidden")
	end
	T.eq(places, 0, "no arrow placement during the burst")
	mock.Advance(0.2)
	T.eq(view.drag.mode, "idle", "settled")
	T.eq(places, 1, "the arrows placed once")
	T.eq(layouts, 4, "and no layout more")
	T.ok(view.routeCounts.dashes > 0 and view.counts.arrows > 0 and arrowsShown() == view.counts.arrows,
		"the full look")
	mock.Advance(0.3)
	T.eq(places, 1, "later timer ticks change nothing")
	-- The settled map is what one full redraw at that zoom draws.
	local settled = shown(view)
	view.Layout, view.DrawContent, ns.RouteArrows.Place = realLayout, realDraw, realPlace
	view:Layout()
	T.eq(settled, shown(view), "the same as a full redraw")
	-- A press during a zoom ends it first: the full look, then the press (a pan).
	wheel(view, -1)
	T.eq(view.routeCounts.dashes, 0)
	view:GetScript("OnMouseDown")(view, "LeftButton")
	T.eq(view.drag.mode, "pan", "the press became a pan")
	T.ok(view.routeCounts.dashes > 0 and view.counts.arrows > 0, "the full look at once")
	view:GetScript("OnMouseUp")(view, "LeftButton")
	-- At the deepest zoom a tick changes nothing and starts no zoom.
	view.zoom = 8
	view:Layout()
	mock.Advance(0.3)
	wheel(view, 1)
	T.eq(view.drag.mode, "idle", "no zoom past the limit")
	restore()
end)

T.case("Zoom: the hovered leg through a zoom, leaving the map, a press, hiding; a pan after a tick", function()
	local view, restore = openMap(ns.Bundled.PREFIX .. "wailing-caverns")
	local coords = ns.db.settings.showCoordinates
	ns.db.settings.showCoordinates = true
	view.IsMouseOver = function()
		return true
	end
	-- The pointer on a route point near the middle (the canvas offsets of the drawn route, y up).
	local p = view.routeJobs.raw[1][30]
	local cx, cy = view.canvas:GetLeft() + p[1], view.canvas:GetTop() + p[2]
	_G.GetCursorPosition = function()
		return cx, cy
	end
	local paths, realPaths = 0, view.DrawRoutePaths
	view.DrawRoutePaths = function(...)
		paths = paths + 1
		return realPaths(...)
	end
	local function hoverOn()
		view:GetScript("OnEnter")(view)
		mock.Advance(0.06)
		T.ok(view.routeHover and view.routeJobs.hl, "a leg under the pointer is highlighted")
	end
	local function tipShown()
		local tt = ns.Widgets.Tip()
		return tt and tt:IsShown() and tt:IsOwned(view) or false
	end
	hoverOn()
	local leg = view.routeHover
	-- Kept through a zoom (the zoom keeps the point under the pointer), and the settled map drawn once.
	paths = 0
	wheel(view, 1)
	mock.Advance(0.05)
	wheel(view, 1)
	mock.Advance(0.05)
	T.ok(view.routeHover == leg and view.routeJobs.hl, "kept while zooming")
	mock.Advance(0.2)
	mock.Advance(0.06)
	T.eq(view.drag.mode, "idle")
	T.eq(paths, 3, "two ticks and the settle: the hover check draws nothing more")
	T.eq(view.routeHover.route, leg.route, "still the leg under the pointer")
	-- Leaving the map during a zoom: no highlight, tooltip or coordinates left behind.
	wheel(view, 1)
	view:GetScript("OnLeave")(view)
	mock.Advance(0.3)
	T.eq(view.drag.mode, "idle")
	T.eq(view.routeHover, nil, "no highlight")
	T.ok(not view.routeJobs.hl, "drawn without it")
	T.ok(not tipShown(), "no tooltip")
	T.eq(view.coords:GetText() or "", "", "no coordinates")
	T.eq(view:GetScript("OnUpdate"), nil, "no hover updates")
	-- A press right after a zoom: the paths drawn once, without the highlight.
	hoverOn()
	wheel(view, 1)
	paths = 0
	view:GetScript("OnMouseDown")(view, "LeftButton")
	T.eq(paths, 1, "drawn once")
	T.eq(view.routeHover, nil)
	T.eq(view.drag.mode, "pan")
	-- A tick during that pan: the pan goes on from where the zoom left the map (the point under the pointer follows
	-- it), and leaving the map onto a pin before the release leaves the hover off.
	cx = cx + 20
	view.OnDragUpdate(view)
	wheel(view, 1)
	T.eq(view.drag.mode, "pan", "the pan goes on")
	local x0, y0 = view:CursorPosition()
	cx, cy = cx + 15, cy - 10
	view.OnDragUpdate(view)
	local x1, y1 = view:CursorPosition()
	T.ok(math.abs(x1 - x0) < 1e-9 and math.abs(y1 - y0) < 1e-9, "the map follows the pointer after the tick")
	view:GetScript("OnLeave")(view)
	view:GetScript("OnMouseUp")(view, "LeftButton")
	T.eq(view:GetScript("OnUpdate"), nil, "released over a pin: no hover updates")
	mock.Advance(0.3)
	-- Hiding the map during a zoom ends it; its timer changes nothing later.
	view:GetScript("OnEnter")(view)
	wheel(view, -1)
	T.eq(view.drag.mode, "zoom")
	view:GetScript("OnHide")(view)
	T.eq(view.drag.mode, "idle", "hiding ends the zoom")
	T.eq(view.laneCache, nil, "and drops the route lanes")
	mock.Advance(0.3)
	T.eq(view.drag.mode, "idle")
	view.DrawRoutePaths, view.IsMouseOver = realPaths, nil
	ns.db.settings.showCoordinates = coords
	view:GetScript("OnLeave")(view)
	view:Layout()
	restore()
end)

T.case("Zoom: route lanes are reused while the drawn route stays, worked out again when it changes", function()
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns"))
	local view, restore = openMap(copy.id)
	local RL = ns.RouteLegs
	local real, calls = RL.Lanes, 0
	RL.Lanes = function(...)
		calls = calls + 1
		return real(...)
	end
	-- The lanes drawn are the lanes of the drawn points (yUp canvas offsets, as MapRoutes asks for them).
	local function exact()
		local jobs = view.routeJobs
		local look = jobs.look
		for i, path in ipairs(jobs.paths) do
			local wide = look.width + look.outline
			local want = real(jobs.raw[i], { shift = wide * ns.Style.ROUTE.lane, near = wide * 1.2, yUp = true })
			if #want ~= #path.pts then
				return false
			end
			for k, p in ipairs(want) do
				local q = path.pts[k]
				if math.abs(p[1] - q[1]) > 1e-9 or math.abs(p[2] - q[2]) > 1e-9 or p.back ~= q.back then
					return false
				end
			end
		end
		return true
	end
	local routes = #view.routeJobs.paths
	T.ok(routes >= 1 and exact(), "drawn at rest")
	-- A hover change draws the same paths again: no new lanes.
	view:SetRouteHover({ route = copy.routes[1].id, from = 1, to = 3 }, "map")
	view:SetRouteHover(nil)
	T.eq(calls, 0, "a restyle reuses them")
	-- While zooming the last lanes are scaled; once settled they are worked out for the new zoom.
	wheel(view, 1)
	wheel(view, 1)
	T.eq(calls, 0, "scaled while zooming")
	mock.Advance(0.3)
	T.eq(calls, routes, "worked out once when the zoom settles")
	T.ok(exact(), "exact after the zoom")
	calls = 0
	-- A route edit.
	local route = copy.routes[1]
	ns.Plan.MoveRoutePoint(copy, route.id, 2, route.points[2][1] + 0.01, route.points[2][2])
	ns.UI.ctx:Changed("routes")
	T.ok(calls >= 1 and exact(), "after a route edit")
	-- A setting that changes the line.
	calls = 0
	local s = ns.db.settings.routes
	local width = s.width
	s.width = "thick"
	ns.UI.RefreshPage()
	T.ok(calls >= 1 and exact(), "after the line width changed")
	s.width = width
	ns.UI.RefreshPage()
	-- Another plan: its own routes' lanes.
	calls = 0
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "razorfen-kraul")
	ns.UI.RefreshPage()
	T.ok(calls >= #view.routeJobs.paths and exact(), "another plan")
	-- The cache holds the routes of the last draw only, however many plans and floors were shown.
	local function kept()
		local n = 0
		for _ in pairs(view.laneCache or {}) do
			n = n + 1
		end
		return n
	end
	T.eq(kept(), #view.routeJobs.paths, "only this plan's routes kept")
	-- Another floor with routes of its own (Blackmaw Hold: floors 3 and 4).
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "blackmaw-hold")
	ns.UI.ctx.floor = 3
	ns.UI.RefreshPage()
	T.eq(kept(), #view.routeJobs.paths, "only this floor's routes kept")
	calls = 0
	ns.UI.ctx.floor = 4
	ns.UI.RefreshPage()
	T.ok(calls >= 1 and #view.routeJobs.paths >= 1 and exact(), "another floor")
	T.eq(kept(), #view.routeJobs.paths, "and only its routes kept")
	-- Another addon's route (a new route table on every draw) is found again by its points.
	local points = copy.routes[1].points
	local extra = { { id = "provider1", floor = 4, color = 6, mapSpace = true, points = points } }
	local args = view.routeArgs
	local o = {}
	for key, value in pairs(args[5]) do
		o[key] = value
	end
	o.extra = extra
	view:DrawRoutePaths(args[1], args[2], args[3], args[4], o)
	calls = 0
	o.extra = { { id = "provider1", floor = 4, color = 6, mapSpace = true, points = points } }
	view:DrawRoutePaths(args[1], args[2], args[3], args[4], o)
	T.eq(calls, 0, "another addon's route: lanes reused")
	ns.UI.RefreshPage()
	ns.UI.ctx.floor = 1
	RL.Lanes = real
	restore()
	ns.DB.DeletePlan(copy.id)
end)

T.case("Perf: a wheel tick costs a fraction of a full redraw; lanes cost the same at any zoom", function()
	local view, restore = openMap(ns.Bundled.PREFIX .. "wailing-caverns")
	-- Zoom 2.44 (wheel step 4 to 5) on Wailing Caverns' long route, the pointer near the middle.
	for _ = 1, 3 do
		wheel(view, 1)
		mock.Advance(0.3)
	end
	-- A full redraw as at a new zoom: the lanes worked out too.
	view.laneCache = nil
	local full = cost(function()
		view:Layout()
	end)
	local tick = cost(function()
		wheel(view, 1)
	end)
	-- The settle alone (the zoom's timer event, without the other frames' OnUpdate scripts mock.Advance runs).
	mock.now = mock.now + 0.3
	local id = view.drag.id
	local settle = cost(function()
		view:ZoomEvent("timer", id)
	end)
	T.eq(view.drag.mode, "idle", "settled")
	mock.Advance(0.3)
	-- Counted alone (lua tests/run.lua "Perf: a wheel tick"): a full redraw 1468k, a tick 444k, its settle 1274k (the
	-- full look of the paths and the arrows, once per burst). Before, every tick was a full redraw, with lanes that grew
	-- with the zoom: a full redraw 1979k, a tick 2116k.
	T.ok(tick * 2 < full, string.format("a tick %dk against a full redraw %dk", tick, full))
	T.ok(settle < full, string.format("the settle %dk against a full redraw %dk", settle, full))
	-- RouteLegs.Lanes on the route at the whole map's scale and eight times that: about the same work (the grid's
	-- cells follow the segments' length), where it used to grow about fourfold.
	local route = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns").routes[1]
	local function lanesAt(s)
		local raw = {}
		for i, pt in ipairs(route.points) do
			raw[i] = { pt[1] * s, -pt[2] * s, stop = pt.step ~= nil }
		end
		return cost(function()
			ns.RouteLegs.Lanes(raw, { shift = 3, near = 6, yUp = true })
		end)
	end
	local near, far = lanesAt(700), lanesAt(5600)
	T.ok(far < near * 1.5, string.format("lanes zoomed in %dk against the whole map %dk", far, near))
	restore()
end)
