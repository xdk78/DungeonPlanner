-- Route legs (Model/RouteLegs.lua): two lanes for corridors walked out and back, hit testing, the leg and steps a
-- segment belongs to; and the map's hover highlight (UI/MapInput.lua, UI/MapPins.lua SetRouteHover) from the pointer,
-- from the steps list and in run mode.
local T = ...
local ns, mock = T.ns, T.mock
local RL = ns.RouteLegs

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

T.case("Route lanes: out and back along one corridor becomes two lanes, each on its own right", function()
	-- y up (canvas offsets): east, then back west on the same line.
	local pts = { { 0, 0, stop = true }, { 200, 0, stop = true }, { 0, 0, stop = true } }
	local lanes, moved = RL.Lanes(pts, { shift = 4, near = 8, yUp = true })
	T.ok(moved, "shifted")
	T.eq(#lanes, 4, "the turning point is doubled")
	T.eq(lanes[1][2], -4, "going east: its right is south (y down)")
	T.eq(lanes[2][2], -4)
	T.eq(lanes[3][2], 4, "coming back west: its right is north")
	T.eq(lanes[4][2], 4)
	T.eq(lanes[2][1], 200, "the way in ends at the turning point")
	T.ok(lanes[2].stop and lanes[3].stop, "both copies keep the stop")
	T.eq(lanes[2].seg, 2, "drawn segment 2 is the route's segment 2")
	T.eq(lanes[3].seg, 2, "the short link at the turn belongs to the segment arriving")
	T.eq(lanes[4].seg, 3, "drawn segment 4 is the route's segment 3")
	T.eq(lanes[3].i, 2, "both copies come from point 2")
	-- y down: the sides swap.
	local down = RL.Lanes(pts, { shift = 4, near = 8 })
	T.eq(down[1][2], 4, "y down: going east, its right is +y")
	-- A route that never comes back stays where it is.
	local l = { { 0, 0, stop = true }, { 100, 0 }, { 100, 100, stop = true } }
	local same, moved2 = RL.Lanes(l, { shift = 4, near = 8, yUp = true })
	T.ok(not moved2, "nothing to shift")
	for i, p in ipairs(same) do
		T.ok(p[1] == l[i][1] and p[2] == l[i][2] and p.seg == i, "unchanged")
	end
	-- Two parallel stretches farther apart than `near` stay apart as they are.
	local wide = { { 0, 0, stop = true }, { 200, 0 }, { 200, 30 }, { 0, 30, stop = true } }
	local _, moved3 = RL.Lanes(wide, { shift = 4, near = 8, yUp = true })
	T.ok(not moved3, "far enough apart already")
	-- A corner inside a shifted stretch keeps both sides at the same distance (mitred).
	local bent = { { 0, 0, stop = true }, { 100, 0 }, { 100, 100 }, { 100, 0 }, { 0, 0, stop = true } }
	local b = RL.Lanes(bent, { shift = 4, near = 8, yUp = true })
	T.ok(#b >= 6, "the far end doubled")
	T.ok(math.abs(b[2][1] - 104) < 1e-6 and math.abs(b[2][2] + 4) < 1e-6, "the corner's lane point: " .. b[2][1] .. "," .. b[2][2])
end)

T.case("Route legs: hit testing with a tolerance; the leg and the steps a segment belongs to", function()
	local lanes = RL.Lanes({ { 0, 0, stop = true }, { 100, 0 }, { 100, 100, stop = true }, { 200, 100, stop = true } },
		{ shift = 4, near = 8, yUp = true })
	local paths = { { pts = lanes }, { pts = { { 0, 50 }, { 300, 50 } }, hit = false } }
	local hit = RL.Hit(paths, 50, 3, 5)
	T.ok(hit and hit.path == 1 and hit.seg == 2, "the first segment, within 5")
	T.eq(RL.Hit(paths, 50, 9, 5), nil, "too far")
	T.eq(RL.Hit(paths, 250, 50, 5), nil, "a line that is not hoverable")
	local near = RL.Hit(paths, 101, 50, 5)
	T.ok(near and near.seg == 3, "the nearest segment")
	-- The leg: from the stop before to the stop after (the ends count as stops).
	local pts = { { 0, 0, stop = true }, { 1, 0 }, { 2, 0 }, { 3, 0, stop = true }, { 4, 0 }, { 5, 0 } }
	local f, t = RL.Leg(pts, 3)
	T.ok(f == 1 and t == 4, "first leg: " .. tostring(f) .. ".." .. tostring(t))
	f, t = RL.Leg(pts, 5)
	T.ok(f == 4 and t == 6, "to the route's end")
	T.eq(RL.Leg(pts, 1), nil, "no segment 1")
	-- Steps: the stop step whose leg holds the segment, and the stop step before it on the same route.
	local list = {
		{ kind = "entrance" },
		{ stop = true, route = "r", from = 1, to = 4 },
		{ kind = "pull" },
		{ stop = true, route = "r", from = 4, to = 6 },
		{ stop = true, route = "other", from = 1, to = 3 },
	}
	local index, prev = RL.StepOf(list, "r", 5)
	T.ok(index == 4 and prev == 2, "step 4, after step 2: " .. tostring(index) .. "," .. tostring(prev))
	index, prev = RL.StepOf(list, "r", 2)
	T.ok(index == 2 and prev == nil, "the first leg has no step before it")
	T.eq(RL.StepOf(list, "r", 9), nil, "a segment outside every step")
end)

-- The map, a point on one of its route lines (a drawn segment's middle, in canvas offsets) and the step it leads to.
local function wailingMap()
	boot()
	ns.db.settings.routes.hover = true
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	return _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
end

local function legPoint(canvas, list)
	local jobs = canvas.routeJobs
	local pts = jobs.paths[1].pts
	-- The longest drawn segment of a stop step's leg: away from other lines and pins.
	local best, bestLen
	for k = 2, #pts do
		local index = RL.StepOf(list, jobs.routes[1], pts[k].seg or k)
		local len = math.sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2)
		if index and index > 2 and (not bestLen or len > bestLen) then
			best, bestLen = k, len
		end
	end
	local a, b = pts[best - 1], pts[best]
	return (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, pts[best].seg
end

T.case("Route hover: the leg under the pointer is highlighted with its steps in a tooltip; leaving restores", function()
	local canvas = wailingMap()
	local list = ns.UI.ctx:Steps()
	local x, y, seg = legPoint(canvas, list)
	local index, prev = RL.StepOf(list, canvas.routeJobs.routes[1], seg)
	local s = canvas:GetEffectiveScale()
	local realGet = _G.GetCursorPosition
	_G.GetCursorPosition = function()
		return (canvas.canvas:GetLeft() + x) * s, (canvas.canvas:GetTop() + y) * s
	end
	local tt = ns.Widgets.Tip()
	local shown = {}
	local realSetText, realAdd = tt.SetText, tt.AddLine
	tt.SetText = function(self, text, ...)
		shown = { text }
		return realSetText(self, text, ...)
	end
	tt.AddLine = function(self, text, ...)
		shown[#shown + 1] = text
		return realAdd(self, text, ...)
	end
	local place, calls = ns.RouteArrows.Place, 0
	ns.RouteArrows.Place = function(...)
		calls = calls + 1
		return place(...)
	end
	canvas:GetScript("OnEnter")(canvas)
	canvas:GetScript("OnUpdate")(canvas, 0.06)
	local h = canvas.routeHover
	T.ok(h and h.route == list[index].route and h.from == list[index].from and h.to == list[index].to,
		"the hovered step's leg: " .. (h and (h.from .. ".." .. h.to) or "none") .. " for " .. list[index].from .. ".."
		.. list[index].to)
	T.eq(calls, 0, "no placement for a hover at the normal density")
	T.eq(shown[1], string.format(ns.L["Step %d to step %d"], prev, index), "the steps it joins")
	local plan = ns.UI.ctx:Plan()
	T.eq(shown[2], string.format(ns.L["From %s to %s"], (ns.UI.StepText(plan, list[prev])),
		(ns.UI.StepText(plan, list[index]))), "named as the steps list names them")
	-- The leg's lines above the rest, wider and brighter; the rest dimmed.
	local top, dim = 0, 0
	for i = 1, canvas.routeCounts.lines do
		local l = canvas.pools.lines[i]
		local _, sub = l:GetDrawLayer()
		local _, _, _, a = l:GetVertexColor()
		if sub == 3 then
			top = top + 1
		elseif a < 0.5 then
			dim = dim + 1
		end
	end
	T.ok(top > 0 and dim > 0, "highlighted " .. top .. ", dimmed " .. dim)
	-- Moving along the same leg changes nothing; leaving restores.
	canvas:GetScript("OnUpdate")(canvas, 0.06)
	T.eq(canvas.routeHover, h, "the same leg")
	canvas:GetScript("OnLeave")(canvas)
	T.eq(canvas.routeHover, nil, "restored")
	for i = 1, canvas.routeCounts.lines do
		local _, sub = canvas.pools.lines[i]:GetDrawLayer()
		T.ok(sub ~= 3, "nothing above the rest")
	end
	-- Fewer arrows in the settings: the hovered leg still shows them at the normal density (placed once per leg).
	ns.db.settings.routes.arrows = "few"
	ns.UI.RefreshPage()
	calls = 0
	canvas:GetScript("OnEnter")(canvas)
	canvas:GetScript("OnUpdate")(canvas, 0.06)
	canvas:GetScript("OnUpdate")(canvas, 0.06)
	T.eq(calls, 1, "the leg's arrows placed once")
	canvas:GetScript("OnLeave")(canvas)
	-- Off in the settings, or while a drawing tool or a drag is on: no highlight.
	ns.db.settings.routes.arrows = "normal"
	ns.db.settings.routes.hover = false
	canvas:GetScript("OnEnter")(canvas)
	canvas:GetScript("OnUpdate")(canvas, 0.06)
	T.eq(canvas.routeHover, nil, "the setting is off")
	ns.db.settings.routes.hover = true
	canvas.drag = { mode = "pan" }
	canvas:RouteHoverUpdate()
	T.eq(canvas.routeHover, nil, "while dragging")
	canvas.drag = { mode = "idle" }
	canvas:GetScript("OnLeave")(canvas)
	ns.RouteArrows.Place = place
	tt.SetText, tt.AddLine = realSetText, realAdd
	_G.GetCursorPosition = realGet
	ns.UI.RefreshPage()
end)

T.case("Route hover: pointing at a step in the list highlights the leg that leads to it; run mode its current step", function()
	local canvas = wailingMap()
	local page = _G.DungeonPlannerMainFrame.instancePage
	local row
	for _, r in ipairs(page.side.list.rows) do
		if r.item and r.item.stop and r.item.route and r.index > 2 then
			row = r
			break
		end
	end
	T.ok(row, "a stop step in the list")
	row:GetScript("OnEnter")(row)
	local h = canvas.routeHover
	T.ok(h and h.route == row.item.route and h.from == row.item.from and h.to == row.item.to, "its leg")
	T.eq(canvas.routeHoverSource, "list")
	-- The pointer over empty map does not take the list's highlight away.
	canvas:RouteHoverUpdate()
	T.eq(canvas.routeHover, h, "kept while the list row is hovered")
	row:GetScript("OnLeave")(row)
	T.eq(canvas.routeHover, nil, "restored")
	-- Run mode: the current step's leg drawn as a highlighted one, the rest dimmed.
	ns.UI.FocusStep(row.index, { stay = true })
	ns.RunMode.Show()
	ns.RunMode.Refresh()
	local run = _G.DungeonPlannerRunFrame.map
	local top = 0
	for i = 1, run.routeCounts.lines do
		local _, sub = run.pools.lines[i]:GetDrawLayer()
		if sub == 3 then
			top = top + 1
		end
	end
	T.ok(top > 0, "the current step's leg above the rest: " .. top)
	ns.RunMode.Hide()
end)
