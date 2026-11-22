-- Route paths on a map view (UI/MapCanvas.lua draws the pins and calls DrawRoutePaths first, under them, then
-- DrawRouteStops for the numbered stops).
--
-- A route must read on busy map art (parchment, painted names, rocks, the dark minimap pictures) and stay calm where it
-- bends, doubles back or crosses itself, and the order of its legs should show at a glance. Each piece of a route is a
-- thin line over a dark casing (a wider dark line under it); each bend gets a joint (a disc in the line's colour over a
-- dark disc), so a path with many bends turns smoothly. The line's colour runs along the route from the route's own
-- colour to a partner colour (Model/RouteLook.lua, UI/Style.lua ROUTE.ramp; the setting "Colour along the route"),
-- so an earlier corridor reads apart from a later one; the numbered stops' rings and the arrows take the colour at
-- their place. A corridor walked out and back draws as two lanes (Model/RouteLegs.lua): the way there solid, the way
-- back dashed. Direction arrows (Media/RouteArrowEdge.tga, a small solid arrowhead with a thin dark edge baked in;
-- Media/RouteArrow.tga without the edge) in a lighter tone of the local colour sit on it, a little wider than the
-- line: one just before each numbered stop and at the route's end, and others spaced by distance on screen
-- (Model/RouteArrows.lua: clear of stops, sharp bends, pins, labels, each other and other parts of the line, so
-- crossings and paths that double back stay clean). The Routes settings (settings.routes, UI/Settings.lua) choose the
-- lines' width, opacity, casing, colour and ramp and the arrows' density and size. While a step is in focus or a leg
-- is highlighted, that leg is brighter and wider and the rest dims (less opaque and greyer, not paler).
--
-- Everything comes from pools on the view (casings, lines, joints, arrows) and is redrawn only when the map redraws
-- (plan, view, focus or setting changes), never per frame; the pieces, dashes and colours are worked out in that
-- redraw and bounded (ROUTE.ramp.pieces per route; ROUTE.maxDashes in all, only on the visible map and its margin).
-- While the map is busy (a drag or resize) the lines are drawn plain, and the full look comes when that ends. The map
-- places the arrows after its pins and labels (DrawRouteArrows), so they keep clear of them; a draw without them places
-- the arrows at once.

local _, ns = ...
local MapRoutes = ns:NewModule("MapRoutes")
local S, MapPins, RouteLook = ns.Style, ns.MapPins, ns.RouteLook

MapRoutes.MAX_ARROWS = 400 -- bound per redraw, all routes together (each route: RouteArrows.LIMIT)
local ARROW_FILE, ARROW_EDGE_FILE = S.MEDIA .. "RouteArrow", S.MEDIA .. "RouteArrowEdge"
-- A file added while the game runs cannot be opened until a restart (docs/COMPATIBILITY.md section 9): then the older
-- shapes stand in (SetTexture's success flag, where the client gives one).
local FALLBACK_FILES = { S.MEDIA .. "Chevron", S.MEDIA .. "Arrow" }
MapRoutes.ARROW_FILE, MapRoutes.ARROW_EDGE_FILE = ARROW_FILE, ARROW_EDGE_FILE

-- A colour mixed towards white by k (0..1).
local function lighten(r, g, b, k)
	return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end
MapRoutes.Lighten = lighten

-- The Routes settings (settings.routes) as sizes in screen units (UI/Style.lua ROUTE); u: the icon size.
function MapRoutes.Look(u)
	local R = S.ROUTE
	local s = ns.db and ns.db.settings and ns.db.settings.routes
	s = type(s) == "table" and s or {}
	u = u or 1
	local spacing = R.spacing[s.arrows]
	if spacing == nil then
		spacing = R.spacing.normal
	end
	local color = tonumber(s.color) or 0
	return {
		width = (R.width[s.width] or R.width.medium) * u,
		outline = s.outline ~= false and R.outline * u or 0,
		spacing = spacing and spacing * u or nil,
		arrow = R.arrow[s.arrowSize] or R.arrow.medium,
		heads = spacing and s.heads ~= false or false,
		opacity = math.max(0.4, math.min(1, tonumber(s.opacity) or 1)),
		color = color >= 1 and color <= #S.Palette() and math.floor(color) or nil,
		ramp = s.ramp ~= false,
		focusOnly = s.focusArrows == true,
	}
end

-- A route's colour on the map: the Routes setting's one colour for the plan's own routes when it is set, else the
-- route's own. The start of its ramp when the colour runs along the route. own: a route of the plan (not another
-- addon's).
function MapRoutes.Color(route, own)
	local look = MapRoutes.Look(1)
	return S.PaletteColor(own and look.color or route.color)
end

-- Ramps by colour, made once (a handful of palette colours; emptied when it would grow past that).
local ramps, nRamps = {}, 0
function MapRoutes.Ramp(r, g, b)
	local key = string.format("%.4f %.4f %.4f", r, g, b)
	local ramp = ramps[key]
	if not ramp then
		if nRamps >= 32 then
			ramps, nRamps = {}, 0
		end
		ramp = RouteLook.Ramp(r, g, b, S.ROUTE.ramp)
		ramps[key], nRamps = ramp, nRamps + 1
	end
	return ramp
end

-- A route's colours under one Look (worked out once per route and redraw): its colour, and its ramp while the colour
-- runs along the route (nil otherwise).
local function routeColors(route, own, look)
	local r, g, b = S.PaletteColor(own and look.color or route.color)
	return r, g, b, own and look.ramp and MapRoutes.Ramp(r, g, b) or nil
end

-- A route's colour at t (0 = its start, 1 = its end): the ramp's for the plan's own routes while "Colour along the
-- route" is on, else its one colour.
function MapRoutes.ColorAt(route, own, t)
	local r, g, b, ramp = routeColors(route, own, MapRoutes.Look(1))
	if ramp then
		return RouteLook.At(ramp, t)
	end
	return r, g, b
end

-- The colour of the route at its point i (a numbered stop's ring, on the map and in the steps list).
function MapRoutes.StopColor(route, i)
	return MapRoutes.ColorAt(route, true, RouteLook.Along(route.points)[i] or 0)
end

function MapRoutes.Install(view)
	local overlay = view.overlay
	local pools = view.pools
	pools.outlines, pools.joints, pools.jointOutlines = pools.outlines or {}, pools.joints or {}, pools.jointOutlines or {}

	-- Pooled pieces on the overlay; their draw layers are below (OUTLINE .. ARROW).
	local function line(list, i, sublevel)
		local l = list[i]
		if not l and overlay.CreateLine then
			l = overlay:CreateLine(nil, "ARTWORK", nil, sublevel)
			l:SetColorTexture(1, 1, 1, 1)
			list[i] = l
		end
		return l
	end
	local function disc(list, i, sublevel)
		local t = list[i]
		if not t then
			t = overlay:CreateTexture(nil, "ARTWORK", nil, sublevel)
			t:SetTexture(S.MEDIA .. "Circle")
			list[i] = t
		end
		return t
	end
	local function arrow(i, file)
		local a = pools.arrows[i]
		if not a then
			a = overlay:CreateTexture(nil, "ARTWORK", nil, 4) -- above every line, the highlighted one too
			pools.arrows[i] = a
		end
		if a.dpFile ~= file then
			a.dpFile = file
			if a:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") == false then
				for _, f in ipairs(FALLBACK_FILES) do
					if a:SetTexture(f, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") ~= false then
						break
					end
				end
			end
		end
		return a
	end

	local function place(l, x0, y0, x1, y1, canvas)
		l:SetStartPoint("TOPLEFT", canvas, x0, y0)
		l:SetEndPoint("TOPLEFT", canvas, x1, y1)
	end

	-- Draw layers on the overlay (sublevels): casings and joint casings, lines and joints, then the highlighted leg's
	-- casing and line above every other line, and the arrows on top (4, set where they are made). Pins and stops are
	-- frames above all of these.
	local OUTLINE, LINE, TOP_OUTLINE, TOP_LINE = 0, 1, 2, 3

	-- While a marker or route point is dragged, or a window is being resized, the map redraws on every pointer move: the
	-- paths are drawn plain then and the arrows wait (settle, below).
	local function busy(v)
		local mode = v.drag and v.drag.mode
		-- No button held any more: the size grip's release was lost, so the resize is over (UI/Window.lua).
		if ns.sizingWindow and IsMouseButtonDown and not IsMouseButtonDown() then
			ns.sizingWindow = nil
		end
		return mode == "marker" or mode == "point" or ns.sizingWindow ~= nil
	end

	-- Draw every route path on `floor`. px, py: plan coordinates to canvas offsets (py negative downwards). o = { scale
	-- (icon size), seg (the focused step's { route, from, to } or nil), highlight (a leg { route, from, to } drawn as the
	-- hover highlight: run mode's current step), activeRoute, extra (more routes in the map's own coordinates: another
	-- addon's, Data/Providers.lua Routes), mx, my (map coordinates to canvas offsets), deferArrows (the caller places the
	-- arrows with PlaceRouteArrows once its pins are laid out), bounds (where dashes are made, canvas offsets y up: the
	-- visible map and its margin; nil: everywhere), restyle (a hover change: same paths, new looks) }.
	-- view.routeHover, the leg under the pointer or a hovered step (SetRouteHover), wins over o.highlight; either counts
	-- only when its route is among the routes drawn. Returns the counts drawn.
	function view:DrawRoutePaths(plan, floor, px, py, o)
		o = o or {}
		if not o.restyle then
			-- What a hover change draws again (SetRouteHover): only the map's own draw, never a stale one.
			self.routeArgs = o.deferArrows and { plan, floor, px, py, o } or nil
		end
		local R = S.ROUTE
		local canvas = self.canvas
		local n = { lines = 0, outlines = 0, joints = 0, arrows = 0, dashes = 0 }
		local u = math.max(0.75, o.scale or 1)
		local look = MapRoutes.Look(u)
		local seg = o.seg
		local all = {}
		for _, route in ipairs(plan and plan.routes or {}) do
			all[#all + 1] = { route = route, own = true }
		end
		for _, route in ipairs(o.extra or {}) do
			all[#all + 1] = { route = route }
		end
		local function drawn(route)
			return route.floor == floor and #route.points >= 2
		end
		-- A highlight whose route is not drawn here (another floor, a hidden layer) changes nothing.
		local function shown(leg)
			for _, entry in ipairs(leg and all or {}) do
				if entry.route.id == leg.route and drawn(entry.route) then
					return leg
				end
			end
			return nil
		end
		local hl = shown(self.routeHover) or shown(o.highlight)
		local jobs = { paths = {}, styles = {}, routes = {}, raw = {}, ranges = {}, look = look, u = u, counts = n, hl = hl }
		self.routeJobs = jobs
		local casing = R.casing
		-- While a marker or route point is dragged or a window resized (busy), one plain piece per segment and no dashes;
		-- the full look comes when that ends (settle).
		local lite = busy(self)
		self.routesLite = lite or nil
		-- First every route's drawn path, so all routes share the dashes' budget: one scale for every route, from the
		-- length of their ways back inside o.bounds (the visible map and the arrows' margin).
		local need = 0
		for _, entry in ipairs(all) do
			local route = entry.route
			if drawn(route) then
				local fx, fy = px, py
				if route.mapSpace then
					fx, fy = o.mx or px, o.my or py
				end
				local raw = {}
				for i, pt in ipairs(route.points) do
					raw[i] = { fx(pt[1], pt[2]), fy(pt[2], pt[1]), stop = pt.step ~= nil }
				end
				-- A corridor walked out and back draws as two lanes, the two directions moved apart
				-- (Model/RouteLegs.lua); lanes[k].seg is the route's own segment for drawn segment k.
				entry.thickness = look.width + (route.id == o.activeRoute and u or 0)
				entry.wide = entry.thickness + look.outline
				entry.raw = raw
				entry.lanes = ns.RouteLegs.Lanes(raw, { shift = entry.wide * R.lane, near = entry.wide * 1.2, yUp = true })
				if not lite then
					-- A dash and its gap per period, and up to two more per segment of the way back (a dash cut where the
					-- segment or the bounds begin and end): so the scale below keeps the count within maxDashes.
					local len, parts = RouteLook.BackLength(entry.lanes, o.bounds)
					need = need + len / ((R.dash[1] + R.dash[2]) * entry.wide) + 2 * parts
				end
			end
		end
		local dashScale = math.max(1, need / R.maxDashes)
		for _, entry in ipairs(all) do
			local route = entry.route
			if drawn(route) then
				local r, g, b, ramp = routeColors(route, entry.own, look)
				local alpha = (route.optional and 0.55 or 1) * look.opacity
				local thickness, wide, raw, lanes = entry.thickness, entry.wide, entry.raw, entry.lanes
				local along = ramp and RouteLook.Along(route.points)
				local focusHere = seg and seg.route == route.id
				-- Where (x, y) on drawn segment k lies along the route, 0..1: between its own segment's two points.
				local function tAt(k, x, y)
					local s = lanes[k] and lanes[k].seg or k
					if not along or s < 2 or not raw[s] then
						return along and along[1] or 0
					end
					local a, c = raw[s - 1], raw[s]
					local dx, dy = c[1] - a[1], c[2] - a[2]
					local d2 = dx * dx + dy * dy
					local f = d2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / d2)) or 0
					return along[s - 1] + (along[s] - along[s - 1]) * f
				end
				-- The route's own segment i (joining points i - 1 and i) at t along the route: its colour, alpha, width,
				-- whether it is brighter, and whether it draws above the other lines.
				local function segLook(i, t)
					local cr, cg, cb = r, g, b
					if ramp then
						cr, cg, cb = RouteLook.At(ramp, t)
					end
					local lit = (hl and hl.route == route.id and i > hl.from and i <= hl.to)
						or (not hl and focusHere and i > seg.from and i <= seg.to)
					if lit then
						local lr, lg, lb = lighten(cr, cg, cb, hl and 0.12 or 0.25)
						return lr, lg, lb, alpha, thickness + R.focusWidth * u, true, hl ~= nil
					elseif hl or seg then
						local dr, dg, db = RouteLook.Desaturate(cr, cg, cb, R.dimGrey)
						return dr, dg, db, alpha * R.dim, thickness, false, false
					end
					return cr, cg, cb, alpha, thickness, false, false
				end
				-- Drawn segment k's look at (x, y) on it (its middle when not given).
				local function laneLook(k, x, y)
					local a, c = lanes[k - 1] or lanes[k], lanes[k]
					x, y = x or (a[1] + c[1]) / 2, y or (a[2] + c[2]) / 2
					return segLook(lanes[k].seg or k, tAt(k, x, y))
				end
				-- The pieces to draw: a long stretch cut so its colour flows, the way back as dashes (inside o.bounds).
				local dash = not lite and { on = R.dash[1] * wide * dashScale, off = R.dash[2] * wide * dashScale } or nil
				local pieces, dashes = RouteLook.Pieces(lanes, { steps = not lite and ramp and R.ramp.pieces or nil,
					dash = dash, bounds = o.bounds })
				n.dashes = n.dashes + dashes
				-- The dark casing under a piece: x0, y0 .. x1, y1 for a line `th` wide at alpha `ca`.
				local function case(x0, y0, x1, y1, th, ca, top)
					local ol = look.outline > 0 and line(pools.outlines, n.outlines + 1, OUTLINE)
					if ol then
						n.outlines = n.outlines + 1
						place(ol, x0, y0, x1, y1, canvas)
						ol:SetDrawLayer("ARTWORK", top and TOP_OUTLINE or OUTLINE)
						ol:SetThickness(th + look.outline)
						ol:SetVertexColor(casing[1], casing[2], casing[3], ca * casing[4])
						ol:Show()
					end
				end
				for _, p in ipairs(pieces) do
					local cr, cg, cb, ca, th, _, top = laneLook(p[5], (p[1] + p[3]) / 2, (p[2] + p[4]) / 2)
					local l = line(pools.lines, n.lines + 1, LINE)
					if l then
						n.lines = n.lines + 1
						place(l, p[1], p[2], p[3], p[4], canvas)
						l:SetDrawLayer("ARTWORK", top and TOP_LINE or LINE)
						l:SetThickness(th)
						l:SetVertexColor(cr, cg, cb, ca)
						l:Show()
						l.dpDash = p.dash and route.id or nil -- a dash of this route's way back (for the tests)
						if not p.dash then
							case(p[1], p[2], p[3], p[4], th, ca, top)
						end
					end
				end
				-- The way back: its casing runs on under the dashes, so it reads as one dashed line.
				for k = 2, dash and #lanes or 0 do
					if lanes[k].back then
						local a, c = lanes[k - 1], lanes[k]
						local _, _, _, ca, th, _, top = laneLook(k)
						case(a[1], a[2], c[1], c[2], th, ca, top)
					end
				end
				-- A joint takes the look of the segment that arrives at the bend; inside a dashed stretch only its casing.
				for _, k in ipairs(ns.RouteArrows.Joints(lanes)) do
					local p = lanes[k]
					local dashed = dash and p.back and lanes[k + 1] and lanes[k + 1].back
					local cr, cg, cb, ca, th, _, top = laneLook(k, p[1], p[2])
					n.joints = n.joints + 1
					local outer, inner = disc(pools.jointOutlines, n.joints, OUTLINE), disc(pools.joints, n.joints, LINE)
					outer:SetDrawLayer("ARTWORK", top and TOP_OUTLINE or OUTLINE)
					outer:ClearAllPoints()
					outer:SetPoint("CENTER", canvas, "TOPLEFT", p[1], p[2])
					outer:SetSize(th + look.outline, th + look.outline)
					outer:SetVertexColor(casing[1], casing[2], casing[3], ca * casing[4])
					if look.outline > 0 then
						outer:Show()
					else
						outer:Hide()
					end
					inner:SetDrawLayer("ARTWORK", top and TOP_LINE or LINE)
					inner:ClearAllPoints()
					inner:SetPoint("CENTER", canvas, "TOPLEFT", p[1], p[2])
					inner:SetSize(th, th)
					inner:SetVertexColor(cr, cg, cb, ca)
					if dashed then
						inner:Hide()
					else
						inner:Show()
					end
				end
				-- The drawn points from..to of the route's own points: from its last copy of `from` (a doubled turning
				-- point) to its first copy of `to`.
				local function laneRange(from, to)
					local lf, lt
					for k, p in ipairs(lanes) do
						if p.i == from then
							lf = k
						end
						if p.i == to and not lt then
							lt = k
						end
					end
					return { from = lf or 1, to = lt or #lanes }
				end
				-- Arrows keep clear of the whole outlined line, of this route and the others.
				local path = { pts = lanes, half = wide / 2, hit = entry.own and not route.mapSpace or false }
				if look.focusOnly and seg then
					if focusHere then
						path.range = laneRange(seg.from, seg.to)
					else
						path.arrows = false
					end
				end
				local index = #jobs.paths + 1
				jobs.paths[index], jobs.styles[index], jobs.ranges[index] = path, laneLook, laneRange
				jobs.routes[index], jobs.raw[index] = route.id, raw
			end
		end
		for key, list in pairs({ lines = pools.lines, outlines = pools.outlines }) do
			for i = n[key] + 1, #list do
				list[i]:Hide()
			end
		end
		for i = n.joints + 1, #pools.joints do
			pools.joints[i]:Hide()
			pools.jointOutlines[i]:Hide()
		end
		if not o.deferArrows then
			self:DrawRouteArrows()
		end
		return n
	end

	-- The numbered stops of the plan's routes on `floor` (and every point of the route being edited), as point pins
	-- (getPoint(i), UI/MapCanvas.lua) with their rings in the route's colour at their place. c = { getPoint, layout
	-- (Model/MapLayout.lua items, added to), scale, seg, activeRoute, editing (the route tool is on), compact,
	-- stopNumber (route id, point index -> the step's number), drawTool }. Returns how many pins it used.
	function view:DrawRouteStops(plan, floor, px, py, c)
		local count = 0
		local scale, seg = c.scale, c.seg
		local drag = self.drag and self.drag.mode == "point" and self.drag or nil
		local look = MapRoutes.Look(1) -- once per redraw: the colours below need only its colour and ramp
		for _, route in ipairs(plan.routes) do
			if route.floor == floor then
				local r0, g0, b0, ramp = routeColors(route, true, look)
				local along = ramp and RouteLook.Along(route.points)
				local active = route.id == c.activeRoute
				for i, pt in ipairs(route.points) do
					if (pt.step and not c.compact) or active or c.editing then
						local r, g, b = r0, g0, b0
						if ramp then
							r, g, b = RouteLook.At(ramp, along[i])
						end
						count = count + 1
						local p = c.getPoint(count)
						p.routeId, p.pointIndex = route.id, i
						p:EnableMouse(not c.drawTool)
						local size = MapPins.StopSize(scale, pt.step)
						MapPins.Reset(p, size)
						p:ClearAllPoints()
						p:SetPoint("CENTER", self.canvas, "TOPLEFT", px(pt[1], pt[2]), py(pt[2], pt[1]))
						if pt.step then
							-- The number is the step's in the side panel (Steps.StopNumbers), not the stop's own order.
							local number = c.stopNumber and c.stopNumber(route.id, i) or pt.step
							MapPins.StyleStop(p, size, r, g, b, tostring(number))
							if seg and seg.route == route.id and seg.to == i then
								p.select:ClearAllPoints()
								p.select:SetPoint("CENTER")
								p.select:SetSize(size + 10, size + 10)
								p.select:SetVertexColor(S.Color("accent"))
								p.select:Show()
							end
						else
							p.disc:ClearAllPoints()
							p.disc:SetPoint("CENTER")
							p.disc:SetSize(size, size)
							p.disc:SetVertexColor(r, g, b, 1)
							p.disc:Show()
						end
						p:SetAlpha(route.optional and 0.7 or 1)
						p:Show()
						MapPins.LayoutItem(c.layout, p, px(pt[1], pt[2]), -py(pt[2], pt[1]), size, pt.step and "stop" or "pin", 0)
						local item = c.layout[#c.layout]
						item.bend = not pt.step -- on the line itself: arrows need not avoid it
						-- The point being dragged always shows (MapLayout.Nudge leaves out a bend a pin covers).
						item.keep = drag and drag.routeId == route.id and drag.index == i or nil
					end
				end
			end
		end
		return count
	end

	local function placeOptions(jobs, obstacles, spacing, heads)
		local u, R, look = jobs.u, S.ROUTE, jobs.look
		local size = (look.width + R.outline * u) * look.arrow
		return {
			spacing = spacing,
			size = size,
			headSize = heads and size * R.head or nil,
			stopGap = 12 * u, -- a numbered stop's disc is 20 across at icon scale 1
			bendGap = 2 * u,
			gap = 2 * u,
			pins = obstacles and obstacles.pins,
			boxes = obstacles and obstacles.boxes,
			bounds = obstacles and obstacles.bounds,
			total = MapRoutes.MAX_ARROWS,
		}
	end

	-- The highlighted leg's own arrows at the normal density, when the settings show fewer (or only another leg's):
	-- placed once per highlighted leg, on that leg alone. Arrows turned off stay off.
	local function legMarks(v, jobs)
		local hl, look = jobs.hl, jobs.look
		local normal = S.ROUTE.spacing.normal * jobs.u
		if not hl or not look.spacing or (look.spacing <= normal and look.heads and not look.focusOnly) then
			return nil
		end
		local key = hl.route .. ":" .. hl.from .. ":" .. hl.to
		if v.legMarksKey == key and v.legMarksJobs == jobs then
			return v.legMarks
		end
		local paths, index = {}, nil
		for i, path in ipairs(jobs.paths) do
			local copy = { pts = path.pts, half = path.half, arrows = false }
			if jobs.routes[i] == hl.route then
				copy.arrows, copy.range, index = true, jobs.ranges[i](hl.from, hl.to), i
			end
			paths[i] = copy
		end
		local marks = index and ns.RouteArrows.Place(paths, placeOptions(jobs, v.arrowObstacles, normal, true)) or {}
		v.legMarksKey, v.legMarksJobs, v.legMarks = key, jobs, marks
		return marks
	end

	-- Draw arrows (RouteArrows.Place marks on the drawn lanes) in the look their place has now. Returns how many.
	local function drawMarks(v, marks)
		local jobs = v.routeJobs
		local count = 0
		if jobs then
			local extra = legMarks(v, jobs)
			local hl = jobs.hl
			local list = marks or {}
			if extra then
				-- The leg's own arrows replace whatever the settings left on it.
				list = {}
				for _, m in ipairs(marks or {}) do
					local _, _, _, _, _, _, top = jobs.styles[m.path](m.seg, m.x, m.y)
					if not (top and jobs.routes[m.path] == hl.route) then
						list[#list + 1] = m
					end
				end
				for _, m in ipairs(extra) do
					list[#list + 1] = m
				end
			end
			local file = jobs.look.outline > 0 and ARROW_EDGE_FILE or ARROW_FILE
			local canvas = v.canvas
			for _, m in ipairs(list) do
				local cr, cg, cb, ca, _, bright = jobs.styles[m.path](m.seg, m.x, m.y)
				count = count + 1
				local a = arrow(count, file)
				local sz = m.size * (bright and 1.15 or 1)
				a:SetSize(sz, sz)
				a:ClearAllPoints()
				a:SetPoint("CENTER", canvas, "TOPLEFT", m.x, m.y)
				local ar, ag, ab = lighten(cr, cg, cb, S.ROUTE.tone)
				a:SetVertexColor(ar, ag, ab, ca)
				-- m.angle: the path's direction in canvas offsets (y up); the arrow points up unturned.
				local tc = MapPins.TurnedCoords(m.angle - math.pi / 2)
				a:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
				a:Show()
			end
			jobs.counts.arrows = count
		end
		for i = count + 1, #pools.arrows do
			pools.arrows[i]:Hide()
		end
		return count
	end

	-- Place and draw the direction arrows of the paths DrawRoutePaths drew last, clear of `obstacles` (pins and labels
	-- in the paths' canvas offsets: RouteArrows.Obstacles, and the visible bounds). Returns how many it drew.
	function view:DrawRouteArrows(obstacles)
		local jobs = self.routeJobs
		local marks
		self.arrowObstacles = obstacles
		if jobs and jobs.look.spacing and #jobs.paths > 0 then
			marks = ns.RouteArrows.Place(jobs.paths, placeOptions(jobs, obstacles, jobs.look.spacing, jobs.look.heads))
		end
		self.routeMarks = marks
		return drawMarks(self, marks)
	end

	-- The paths DrawRoutePaths drew last, drawn again in a new look (a hover change, or the end of a drag).
	local function redrawPaths(v)
		local args = v.routeArgs
		local o = {}
		for k, value in pairs(args[5]) do
			o[k] = value
		end
		o.restyle = true
		return v:DrawRoutePaths(args[1], args[2], args[3], args[4], o)
	end

	-- While the map is busy (a drag or resize) its arrows hide and are placed once that ends (a short timer checks; a
	-- stale tick does nothing), with the paths' full look when they were drawn plain meanwhile.
	local function settle()
		view.arrowTimer = nil
		if not view.arrowsPending then
			return
		end
		if busy(view) then
			view.arrowTimer = true
			C_Timer.After(0.1, settle)
			return
		end
		view.arrowsPending = nil
		if view:IsVisible() then
			if view.routesLite and view.routeArgs then
				view.routeCounts = redrawPaths(view)
			end
			local n = view:DrawRouteArrows(view.arrowObstacles)
			if view.counts then
				view.counts.arrows = n
			end
		end
	end
	-- The map's way to draw the arrows (UI/MapCanvas.lua DrawContent). Returns how many it drew now.
	function view:PlaceRouteArrows(obstacles)
		self.arrowObstacles = obstacles
		if not busy(self) then
			self.arrowsPending = nil
			return self:DrawRouteArrows(obstacles)
		end
		self.arrowsPending = true
		for i = 1, #pools.arrows do
			pools.arrows[i]:Hide()
		end
		if not self.arrowTimer and C_Timer and C_Timer.After then
			self.arrowTimer = true
			C_Timer.After(0.1, settle)
		end
		return 0
	end

	-- The highlighted leg: { route, from, to } (the route's own point indices) or nil, from the pointer over a line
	-- (source "map", UI/MapInput.lua) or a hovered step in the list (source "list", UI/SidePanel.lua); one at a time.
	-- A change restyles the lines and reuses the placed arrows: nothing is placed again, except the leg's own arrows
	-- when the settings show fewer (once per leg).
	function view:SetRouteHover(leg, source)
		local cur = self.routeHover
		if leg and cur and leg.route == cur.route and leg.from == cur.from and leg.to == cur.to then
			self.routeHoverSource = source
			return false
		end
		if not leg and not cur then
			return false
		end
		self.routeHover, self.routeHoverSource = leg, leg and source or nil
		if self.routeArgs and self:IsVisible() then
			redrawPaths(self)
			local n = drawMarks(self, self.routeMarks)
			if self.counts then
				self.counts.arrows = n
			end
		end
		return true
	end
end
