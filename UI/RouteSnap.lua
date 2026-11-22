-- "Snap to corridors", the route tool's switch (UI/Panels/MapControls.lua). With it on (ui.snapRoutes, the default) and
-- a walkability grid for the floor (Data/Corridors.lua), a click adds a numbered stop and the leg from the route's last
-- point follows the corridors; Shift-click adds the stop with a straight leg. Dragging a stop with the Route tool finds
-- its two legs again (Shift held when it is dropped: both straight); with Select it moves alone. The bends go into
-- the route as plain points, so plans and export strings look as if they were placed by hand. Where no path is found
-- the leg stays straight and the map says so for a few seconds.
--
-- The legs are found in the same call as the click or the drop (Corridors.Leg), before the map panel records the change
-- with ctx:Changed, so one click or drag is one undo step that ends with the snapped route. Nothing is left running.
--
-- Which legs a dragged stop takes along: a leg with bends (snapped or hand-made) is found again; a straight leg only
-- when its line was clear before the drag (a straight leg through a wall was meant: Shift-click or snapping off).

local _, ns = ...
local RouteSnap = ns:NewModule("RouteSnap")
local Plan, Util, Corridors = ns.Plan, ns.Util, ns.Corridors

RouteSnap.NOTICE_SECONDS = 4

function RouteSnap.Enabled()
	return ns.db.ui.snapRoutes ~= false
end

-- Does a click with the route tool snap on this floor?
function RouteSnap.Active(plan, floor)
	return RouteSnap.Enabled() and Corridors.Has(plan, floor)
end

local function indexOf(list, item)
	for i, v in ipairs(list) do
		if v == item then
			return i
		end
	end
	return nil
end

-- The notice under the map ("No walkable path found: a straight leg."): one line, gone after a few seconds.
function RouteSnap.Notice(canvas, text)
	if not canvas or not canvas.edge then
		return
	end
	local fs = canvas.snapNotice
	if not fs then
		fs = ns.Widgets.Text(canvas.edge, "caption", "white")
		fs:SetPoint("BOTTOM", 0, ns.MapCanvas.FRAME_INSET + ns.Style.SPACE.sm)
		canvas.snapNotice = fs
	end
	fs:SetText(text)
	fs:Show()
	local token = {}
	fs.token = token
	C_Timer.After(RouteSnap.NOTICE_SECONDS, function()
		if fs.token == token then
			fs:Hide()
		end
	end)
end

local function why(reason)
	local L = ns.L
	if reason == "limit" then
		return L["The path is too long to find: a straight leg."]
	elseif reason == "full" then
		return L["The route is full: a straight leg."]
	end
	return L["No walkable path found: a straight leg."]
end

-- Finds the legs ({ a = point, b = point }, a before b in `route`) and puts their bends in; a leg without a path keeps
-- what it has (a new stop's leg stays straight, a dragged stop's its old bends). The map says why when one failed.
local function snap(plan, route, legs, canvas)
	local failed
	for _, leg in ipairs(legs) do
		local a, b = leg.a, leg.b
		local bends, reason = Corridors.Leg(plan, route.floor, a[1], a[2], b[1], b[2])
		if bends then
			local ok, err = Plan.SetLegBends(plan, route.id, indexOf(route.points, a), indexOf(route.points, b), bends)
			if not ok then
				failed = failed or (err == "limit" and "full" or err)
			end
		else
			failed = failed or reason
		end
	end
	if failed then
		RouteSnap.Notice(canvas, why(failed))
	end
end

-- A click with the route tool on a snapping floor, after its point was added at the end of route `routeId`: the point
-- becomes a numbered stop and its leg from the point before is snapped unless `straight`. The caller records the change.
function RouteSnap.Stop(plan, routeId, straight, canvas)
	local route = Util.FindById(plan.routes, routeId)
	local n = route and #route.points or 0
	if n == 0 then
		return
	end
	Plan.SetRouteStop(plan, routeId, n, true)
	if not straight and n > 1 then
		snap(plan, route, { { a = route.points[n - 1], b = route.points[n] } }, canvas)
	end
end

-- The points a stop's legs run between: the nearest stop before and after it (or the route's ends).
local function anchors(route, index)
	local before, after
	for i = index - 1, 1, -1 do
		if route.points[i].step or i == 1 then
			before = i
			break
		end
	end
	for i = index + 1, #route.points do
		if route.points[i].step or i == #route.points then
			after = i
			break
		end
	end
	return before, after
end

-- Point `index` of route `routeId` dropped at its new place (it was at fromX, fromY): a stop on a snapping floor gets its
-- legs found again (`straight`: made straight). A bend moves alone. The caller records the change.
function RouteSnap.Moved(plan, routeId, index, fromX, fromY, straight, canvas)
	local route = Util.FindById(plan.routes, routeId)
	local point = route and route.points[index]
	if not point or not point.step or not RouteSnap.Active(plan, route.floor) then
		return
	end
	local before, after = anchors(route, index)
	local legs = {}
	local function consider(a, b, oldA, oldB)
		if not a then
			return
		end
		local bent = b - a > 1
		if bent or (not straight and fromX and Corridors.Clear(plan, route.floor, oldA[1], oldA[2], oldB[1], oldB[2])) then
			legs[#legs + 1] = { a = route.points[a], b = route.points[b] }
		end
	end
	local old = { fromX or point[1], fromY or point[2] }
	consider(before, index, before and route.points[before], old)
	consider(after and index, after, old, after and route.points[after])
	if straight then
		for _, leg in ipairs(legs) do
			Plan.SetLegBends(plan, route.id, indexOf(route.points, leg.a), indexOf(route.points, leg.b), {})
		end
	else
		snap(plan, route, legs, canvas)
	end
end
