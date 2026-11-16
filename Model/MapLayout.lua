-- Where map labels and crowded pins go, so nothing covers anything else. Pure geometry in screen units (x right,
-- y down) on whatever the canvas drew: the map calls it once per redraw, never per frame.
--   MapLayout.Nudge(items)  pins never cover each other: a pull disc on a boss becomes a badge just right of it, a
--                           numbered route stop on a marker one just left of it (the marker stays put), and other
--                           pins that still overlap are pushed apart (each half the way). Small route bends stay.
--   MapLayout.Labels(items, avoid, bounds) picks a side for each label (below, above, right, left), or hides it when
--                           every side is taken; higher `prio` places first, and labels with prio >= KEEP always show.
--                           avoid: optional rectangles { x1, y1, x2, y2 } no label may cover (the floating legend).
--                           bounds: optional rectangle { x1, y1, x2, y2 } labels stay inside (the visible map): a
--                           label below or above its pin slides sideways to fit, one beside it slides up or down
--                           (it.dx, it.dy), and a side where it cannot fit is not used.
-- items: { x, y, r (pin radius), kind ("boss" | "disc" | "stop" | "pin"), w, h (label size; w = 0: no label), prio }.
--   MapLayout.RouteMarks(pts, o) direction chevrons and bend joints along a route (below).

local _, ns = ...
local MapLayout = ns:NewModule("MapLayout")

MapLayout.KEEP = 3 -- bosses: their names always show
local GAP = 2

-- The area two boxes share (0 when apart).
local function area(a, b)
	local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
	local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
	return (w > 0 and h > 0) and w * h or 0
end

local function pinBox(it)
	return { it.x - it.r, it.y - it.r, it.x + it.r, it.y + it.r }
end

-- The label rectangle of an item on a side.
function MapLayout.LabelBox(it, side)
	local x, y, r, w, h = it.x, it.y, it.r, it.w, it.h
	if side == "below" then
		return { x - w / 2, y + r + 1, x + w / 2, y + r + 1 + h }
	elseif side == "above" then
		return { x - w / 2, y - r - 1 - h, x + w / 2, y - r - 1 }
	elseif side == "right" then
		return { x + r + GAP, y - h / 2, x + r + GAP + w, y + h / 2 }
	else
		return { x - r - GAP - w, y - h / 2, x - r - GAP, y + h / 2 }
	end
end

local MIN_SPREAD_R = 6 -- pins smaller than this (route bends while editing) are never moved
local SPREAD_PASSES = 12

-- Overlap of two pins' boxes along x and y (<= 0: apart on that axis).
local function boxOverlap(a, b)
	return a.r + b.r - math.abs(a.x - b.x), a.r + b.r - math.abs(a.y - b.y)
end

-- Put `item` beside `host` (side 1: right, -1: left), raised by half the host's radius: a badge touching its edge.
local function badge(item, host, side)
	item.x = host.x + side * (host.r + item.r + 1)
	item.y = host.y - host.r * 0.5
	item.moved = true
end

function MapLayout.Nudge(items)
	for _, it in ipairs(items) do
		if it.kind == "disc" or it.kind == "stop" then
			for _, host in ipairs(items) do
				local hostKind = it.kind == "disc" and host.kind == "boss"
					or (it.kind == "stop" and host ~= it and host.kind ~= "stop" and host.r >= MIN_SPREAD_R)
				if hostKind and not it.moved then
					local dx, dy = it.x - host.x, it.y - host.y
					local need = (it.r + host.r) * 0.9
					if dx * dx + dy * dy < need * need then
						badge(it, host, it.kind == "disc" and 1 or -1)
					end
				end
			end
		end
	end
	-- Whatever still overlaps moves apart along the axis where it overlaps least.
	for _ = 1, SPREAD_PASSES do
		local any = false
		for i = 1, #items do
			local a = items[i]
			for j = i + 1, #items do
				local b = items[j]
				if a.r >= MIN_SPREAD_R and b.r >= MIN_SPREAD_R then
					local ox, oy = boxOverlap(a, b)
					if ox > 1 and oy > 1 then
						any = true
						if ox <= oy then
							local d = (ox + 1) / 2 * (a.x <= b.x and 1 or -1)
							a.x, b.x = a.x - d, b.x + d
						else
							local d = (oy + 1) / 2 * (a.y <= b.y and 1 or -1)
							a.y, b.y = a.y - d, b.y + d
						end
						a.moved, b.moved = true, true
					end
				end
			end
		end
		if not any then
			break
		end
	end
	return items
end

local SIDES = { "below", "above", "right", "left" }

-- Slides tried for a label when its plain place is taken, as a share of how far it can slide and still touch its pin:
-- along the pin's side (a label below moves sideways, one beside it up or down).
local SLIDES = { 0.5, -0.5, 1, -1 }

-- The label box of `it` on `side`, slid by `slide` (a SLIDES share) and then moved inside `bounds`: along the pin's
-- side only, so it still touches its pin, unless `force` (a label that must show), which moves it all the way in.
-- Returns the box, its shift dx, dy and whether it fits inside `bounds`.
local function fitBox(it, side, bounds, force, slide)
	local box = MapLayout.LabelBox(it, side)
	local along = side == "below" or side == "above"
	local reachX = math.max(0, (box[3] - box[1]) / 2 - 2)
	local reachY = math.max(0, (box[4] - box[2]) / 2 + it.r - 2)
	local dx, dy = 0, 0
	if slide then
		if along then
			dx = slide * reachX
		else
			dy = slide * reachY
		end
	end
	if bounds then
		local function into(lo, hi, min, max, d, reach)
			local e = 0
			if lo + d < min then
				e = min - lo - d
			elseif hi + d > max then
				e = max - hi - d
			end
			if not force then
				e = math.max(-reach - d, math.min(reach - d, e))
			end
			return d + e
		end
		if along or force then
			dx = into(box[1], box[3], bounds[1], bounds[3], dx, reachX)
		end
		if not along or force then
			dy = into(box[2], box[4], bounds[2], bounds[4], dy, reachY)
		end
	end
	box = { box[1] + dx, box[2] + dy, box[3] + dx, box[4] + dy }
	local inside = not bounds or (box[1] >= bounds[1] - 0.5 and box[3] <= bounds[3] + 0.5 and box[2] >= bounds[2] - 0.5
		and box[4] <= bounds[4] + 0.5)
	return box, dx, dy, inside
end

-- How much of a box lies outside `bounds`.
local function outside(box, bounds)
	if not bounds then
		return 0
	end
	return (box[3] - box[1]) * (box[4] - box[2]) - area(box, bounds)
end

-- Every place a label may take, in the order tried: each side as it is, then each side slid.
local CANDIDATES = {}
for _, side in ipairs(SIDES) do
	CANDIDATES[#CANDIDATES + 1] = { side, nil }
end
for _, slide in ipairs(SLIDES) do
	for _, side in ipairs(SIDES) do
		CANDIDATES[#CANDIDATES + 1] = { side, slide }
	end
end

function MapLayout.Labels(items, avoid, bounds)
	local order = {}
	for i, it in ipairs(items) do
		it.side = nil
		if (it.w or 0) > 0 then
			order[#order + 1] = i
		end
	end
	table.sort(order, function(a, b)
		local pa, pb = items[a].prio or 0, items[b].prio or 0
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	local placed = {}
	-- What a label box covers: other pins, labels already placed, the legend (counted the most) and the outside of the
	-- visible map (a label there would be cut). 0: free.
	local function cost(i, box)
		local c = 8 * outside(box, bounds)
		for j, other in ipairs(items) do
			if j ~= i then
				c = c + area(box, pinBox(other))
			end
		end
		for _, p in ipairs(placed) do
			c = c + area(box, p)
		end
		for _, r in ipairs(avoid or {}) do
			c = c + 4 * area(box, r)
		end
		return c
	end
	for _, i in ipairs(order) do
		local it = items[i]
		local chosen, best, bestBox, bestDx, bestDy, free
		it.dx, it.dy = 0, 0
		for _, cand in ipairs(CANDIDATES) do
			local box, dx, dy, inside = fitBox(it, cand[1], bounds, false, cand[2])
			local c = cost(i, box) + (inside and 0 or 1)
			if c <= 0 then
				chosen, bestBox, bestDx, bestDy, free = cand[1], box, dx, dy, true
				break
			end
			if not best or c < best then
				best, chosen, bestBox, bestDx, bestDy = c, cand[1], box, dx, dy
				if not inside then
					-- A label that must show is moved all the way into the visible map.
					bestBox, bestDx, bestDy = fitBox(it, cand[1], bounds, true, cand[2])
				end
			end
		end
		if not free and (it.prio or 0) < MapLayout.KEEP then
			chosen = nil -- no free place, and it may be left out
		end
		if chosen then
			it.dx, it.dy = bestDx, bestDy
			placed[#placed + 1] = bestBox
		end
		it.side = chosen
	end
	return items
end

-- Declutter dense points (the Enemies layer): points closer than `cell` screen units are merged into one group,
-- greedily in input order, each group placed at the mean of its members. points: { x, y, ... } in screen units.
-- Returns { { x, y, members = { point, ... } } }, at most `limit` groups (the rest are dropped; nil = no limit).
function MapLayout.Cluster(points, cell, limit)
	local groups = {}
	local c2 = cell * cell
	for _, p in ipairs(points) do
		local hit
		for _, g in ipairs(groups) do
			local dx, dy = g.x - p.x, g.y - p.y
			if dx * dx + dy * dy < c2 then
				hit = g
				break
			end
		end
		if hit then
			local n = #hit.members
			hit.x = (hit.x * n + p.x) / (n + 1)
			hit.y = (hit.y * n + p.y) / (n + 1)
			hit.members[n + 1] = p
		elseif not limit or #groups < limit then
			groups[#groups + 1] = { x = p.x, y = p.y, members = { p } }
		end
	end
	return groups
end

-- The whole map in a view (zoom 1): as large as the view allows and centred in it, so no empty band is left above and
-- below a map that a floating panel (the legend, the map's own controls) would otherwise squeeze beside it. Panels
-- float over the map's edges, never over the plan: `avoid` lists their boxes in view pixels { x0, y0, x1, y1 } (top
-- left origin, y down), `points` the plan's points (0..1 of the map, { x, y }). A point level with a panel stays `gap`
-- px clear of it, on its inner side (left of a panel in the right half, right of one in the left half): the map slides
-- sideways as far as the frame's inset allows, and shrinks (a few per cent a step) only when sliding is not enough,
-- down to the size that fits beside the right-hand panel (reserveRight px; without one, a tenth smaller). When even
-- that does not clear every point, the map is centred in the room left of that panel.
-- o = { viewW, viewH, baseW, baseH, inset, reserveRight, avoid, points, gap (default 30 px: a boss pin's reach) }.
-- Returns { scale, ox, oy }, or nil without a size.
function MapLayout.MapFit(o)
	local inset, reserve = o.inset or 0, math.max(0, o.reserveRight or 0)
	local availW, availH = (o.viewW or 0) - 2 * inset, (o.viewH or 0) - 2 * inset
	local w, h = o.baseW or 0, o.baseH or 0
	if availW <= 0 or availH <= 0 or w <= 0 or h <= 0 then
		return nil
	end
	local full = math.min(availW / w, availH / h)
	local beside = math.max(0, math.min((availW - reserve) / w, availH / h))
	local avoid, points, gap = o.avoid or {}, o.points or {}, o.gap or 30
	local mid = (o.viewW or 0) / 2
	-- The offsets that keep every point clear at `scale`, nearest the centred one; nil when none does.
	local function place(scale)
		local cw, ch = w * scale, h * scale
		local centred = inset + (availW - cw) / 2
		local lo, hi = math.min(inset, centred), math.max(inset, inset + availW - cw)
		local oy = inset + (availH - ch) / 2
		for _, p in ipairs(points) do
			local px, py = p[1] * cw, oy + p[2] * ch
			for _, r in ipairs(avoid) do
				if py >= r[2] - gap and py <= r[4] + gap then
					if (r[1] + r[3]) / 2 >= mid then
						hi = math.min(hi, r[1] - gap - px)
					else
						lo = math.max(lo, r[3] + gap - px)
					end
				end
			end
		end
		if lo > hi + 1e-9 then
			return nil
		end
		return { scale = scale, ox = math.max(lo, math.min(hi, centred)), oy = oy }
	end
	-- From the full size down to the size beside the right-hand panel (without one, a tenth smaller at most).
	local floor = math.min(beside, full * 0.9)
	local scale = full
	while true do
		local fit = place(scale)
		if fit then
			return fit
		end
		if scale <= floor + 1e-9 then
			break
		end
		scale = math.max(floor, scale * 0.97)
	end
	-- Beside the right-hand panel: centred in the room it leaves (the old way of fitting).
	local cw, ch = w * beside, h * beside
	return { scale = beside, ox = inset + (availW - reserve - cw) / 2, oy = inset + (availH - ch) / 2 }
end

-- Fit a view around points (normalized 0..1 map coordinates, { x, y } pairs): the zoom and offset that frame them with a
-- margin, inside the part of the view not covered by a floating panel on the right (reserveRight px). o = { viewW,
-- viewH, baseW, baseH (the map's size at scale 1), fitScale (scale at zoom 1), inset, reserveRight, maxZoom, pad (the
-- margin, default a tenth of the map), minSpan (the smallest box framed, default a fifth) }.
-- Returns { zoom, ox, oy } or nil when there is nothing to frame (no points, no size).
function MapLayout.FitView(points, o)
	if type(points) ~= "table" or #points == 0 or not o or (o.viewW or 0) <= 0 or (o.viewH or 0) <= 0 then
		return nil
	end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(points) do
		x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
		y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
	end
	-- A margin of a tenth of the map, so pins and labels at the edge stay inside; never less than a fifth wide.
	local pad, span = o.pad or 0.1, o.minSpan or 0.2
	x0, x1 = math.max(0, x0 - pad), math.min(1, x1 + pad)
	y0, y1 = math.max(0, y0 - pad), math.min(1, y1 + pad)
	if x1 - x0 < span then
		local c = (x0 + x1) / 2
		x0, x1 = c - span / 2, c + span / 2
	end
	if y1 - y0 < span then
		local c = (y0 + y1) / 2
		y0, y1 = c - span / 2, c + span / 2
	end
	local inset, reserve = o.inset or 0, o.reserveRight or 0
	local availW, availH = o.viewW - 2 * inset - reserve, o.viewH - 2 * inset
	if availW <= 0 or availH <= 0 or (o.fitScale or 0) <= 0 then
		return nil
	end
	local boxW, boxH = (x1 - x0) * o.baseW, (y1 - y0) * o.baseH
	local scale = math.min(availW / boxW, availH / boxH)
	local zoom = math.max(1, math.min(o.maxZoom or 8, scale / o.fitScale))
	local s = o.fitScale * zoom
	local cx, cy = (x0 + x1) / 2 * o.baseW * s, (y0 + y1) / 2 * o.baseH * s
	return { zoom = zoom, ox = inset + availW / 2 - cx, oy = inset + availH / 2 - cy }
end

-- Direction marks along a route as drawn on screen, so the route reads at any zoom: chevrons spaced by on-screen
-- distance along the path (more of them when zoomed in, never denser), kept clear of stops and bends, and a joint at
-- each bend so a path with many bends (routes that follow corridors) turns smoothly.
--   pts: { { x, y, stop = true? }, ... } in screen units. The first and last points count as stops.
--   o:   { spacing (path length between marks), size (a mark's size), stopGap and bendGap (kept clear around a stop or a
--        bend, besides half a mark), limit (most marks returned) }
-- Returns arrows { { x, y, angle, seg } } (seg i joins pts[i - 1] and pts[i]; angle = atan2 of that segment's dy, dx)
-- and joints { i, ... } (inner points where the direction changes). Rules: a segment with room gets marks every
-- `spacing` along the path, and at least one at its middle unless the last mark is under half a spacing back; segments
-- too short for a mark get none; a leg (stop to stop) whose bends are all too short for one gets one at its middle.
function MapLayout.RouteMarks(pts, o)
	o = o or {}
	local spacing, size = o.spacing or 72, o.size or 16
	local stopGap, bendGap, limit = o.stopGap or 14, o.bendGap or 4, o.limit or 400
	local arrows, joints = {}, {}
	local n = type(pts) == "table" and #pts or 0
	if n < 2 then
		return arrows, joints
	end
	local function isStop(i)
		return i == 1 or i == n or pts[i].stop == true
	end
	local function add(i, t, len, dx, dy)
		if #arrows < limit then
			local a = pts[i - 1]
			arrows[#arrows + 1] = { x = a[1] + dx * t / len, y = a[2] + dy * t / len, angle = math.atan2(dy, dx), seg = i }
		end
	end
	local since = spacing / 2 -- path length since the last mark: the first comes about half a spacing in
	local legStart, legMarks, legLen = 2, 0, 0
	for i = 2, n do
		local a, b = pts[i - 1], pts[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0 then
			local lo = (isStop(i - 1) and stopGap or bendGap) + size / 2
			local hi = len - (isStop(i) and stopGap or bendGap) - size / 2
			local last
			if hi >= lo then
				local t = math.max(lo, spacing - since)
				while t <= hi do
					add(i, t, len, dx, dy)
					legMarks, last = legMarks + 1, t
					t = t + spacing
				end
				local mid = (lo + hi) / 2
				if not last and since + mid >= spacing / 2 then
					add(i, mid, len, dx, dy)
					legMarks, last = legMarks + 1, mid
				end
			end
			since = last and (len - last) or (since + len)
			legLen = legLen + len
		end
		if i < n and not isStop(i) then
			-- A joint where the path turns (more than about 3 degrees).
			local c = pts[i + 1]
			local ex, ey = c[1] - b[1], c[2] - b[2]
			local cross, dot = dx * ey - dy * ex, dx * ex + dy * ey
			if math.abs(math.atan2(cross, dot)) > 0.05 then
				joints[#joints + 1] = i
			end
		end
		if isStop(i) then
			-- The leg ends here: one with no mark gets one at its middle (on whichever segment holds that point), if the
			-- leg is long enough to show one clear of its two stops.
			if legMarks == 0 and legLen >= 2 * stopGap + 2 * size then
				local want, walked = legLen / 2, 0
				for j = legStart, i do
					local p, q = pts[j - 1], pts[j]
					local ex, ey = q[1] - p[1], q[2] - p[2]
					local l = math.sqrt(ex * ex + ey * ey)
					if l > 0 and walked + l >= want then
						add(j, want - walked, l, ex, ey)
						since = l - (want - walked)
						break
					end
					walked = walked + l
				end
			end
			legStart, legMarks, legLen = i + 1, 0, 0
		end
	end
	return arrows, joints
end
