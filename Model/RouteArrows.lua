-- Direction arrows along routes as drawn on screen. Pure geometry in screen units, run once per map redraw (a plan,
-- view, focus or setting change), never per frame.
--
--   RouteArrows.Joints(pts)            inner points where a path turns (each gets a joint disc).
--   RouteArrows.Place(paths, o)        where the direction arrows go (rules below).
--   RouteArrows.Obstacles(items, flip) pins and their shown labels (Model/MapLayout.lua items) as obstacles.
--
-- paths: { { pts = { { x, y, stop = true? }, ... }, half (half the drawn line's width), range = { from, to }? (only
--        between these point indices), arrows = false? (a line other arrows keep clear of, with none of its own) } }.
--        The first and last points of a path count as stops.
-- o:     { spacing (path length between arrows; nil: only arrowheads), size (an arrow's size), headSize (the arrowhead
--        before each stop and at the end; nil or 0: none), stopGap (kept clear around a stop), bendGap (path checked for
--        bends beyond each end of an arrow), gap (clearance from pins and labels), pins = { { x, y, r } },
--        boxes = { { x1, y1, x2, y2 } }, limit (most arrows per path), total (most arrows in all) }
-- Returns { { x, y, angle, seg, path, size, head, t } }: seg i joins pts[i - 1] and pts[i] of paths[path], t is the
-- path length up to the arrow, angle = atan2(dy, dx) of the path's direction across the arrow.
--
-- Rules: arrows are spaced by path length on screen (so more of them when zoomed in, never denser), not per segment;
-- none within stopGap of a stop or the path's ends, where the path turns sharply, over a pin or a label, within an
-- arrow's length of another arrow, or where another part of the same route or another route crosses the line. A part
-- that runs alongside (a corridor walked out and back) does not stop an arrow; the distance between arrows keeps the
-- two directions apart. An arrowhead goes just before each stop first; then arrows every `spacing`; then a leg (stop to
-- stop) still without any arrow gets one near its middle if there is a clear place (a little smaller if need be).

local _, ns = ...
local RouteArrows = ns:NewModule("RouteArrows")

local sqrt, atan2, abs, floor, ceil = math.sqrt, math.atan2, math.abs, math.floor, math.ceil
local max, min, huge = math.max, math.min, math.huge

RouteArrows.LIMIT = 200 -- arrows per route
local WOBBLE = 0.6 -- the path may stray this share of an arrow's radius from the chord across the arrow
local SHARP = 1.2 -- radians (about 70 degrees): no arrow over a corner this sharp, however short its legs
local SMALLER = 0.75 -- a leg with no room for a full-size arrow tries one this much smaller
local PARALLEL = 0.92 -- cosine (about 23 degrees): another part of the line this close to the arrow's direction runs
-- alongside it rather than across
local JOINT_TURN = 0.05 -- a joint disc where the path turns more than about 3 degrees

-- The signed turn at inner point i (0 where a neighbouring segment has no length).
local function turnAt(pts, i)
	local a, b, c = pts[i - 1], pts[i], pts[i + 1]
	local dx, dy, ex, ey = b[1] - a[1], b[2] - a[2], c[1] - b[1], c[2] - b[2]
	if (dx == 0 and dy == 0) or (ex == 0 and ey == 0) then
		return 0
	end
	return atan2(dx * ey - dy * ex, dx * ex + dy * ey)
end

function RouteArrows.Joints(pts)
	local out = {}
	for i = 2, #pts - 1 do
		if not pts[i].stop and abs(turnAt(pts, i)) > JOINT_TURN then
			out[#out + 1] = i
		end
	end
	return out
end

-- A uniform grid of buckets, so a check looks only at what is near.
local function newGrid(cell)
	return { cell = cell, cells = {} }
end

local function gridAdd(g, item, x1, y1, x2, y2)
	local c = g.cell
	for cx = floor(x1 / c), floor(x2 / c) do
		for cy = floor(y1 / c), floor(y2 / c) do
			local k = cx * 1000003 + cy
			local list = g.cells[k]
			if not list then
				list = {}
				g.cells[k] = list
			end
			list[#list + 1] = item
		end
	end
end

-- Calls hit(item) for the items in the cells a box touches (an item may come more than once); true when one hit.
local function gridAny(g, x1, y1, x2, y2, hit)
	local c = g.cell
	for cx = floor(x1 / c), floor(x2 / c) do
		for cy = floor(y1 / c), floor(y2 / c) do
			local list = g.cells[cx * 1000003 + cy]
			if list then
				for _, item in ipairs(list) do
					if hit(item) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function segDist(px, py, s)
	local vx, vy = s.bx - s.ax, s.by - s.ay
	local t = ((px - s.ax) * vx + (py - s.ay) * vy) / (vx * vx + vy * vy)
	t = max(0, min(1, t))
	local dx, dy = px - (s.ax + t * vx), py - (s.ay + t * vy)
	return sqrt(dx * dx + dy * dy)
end

local function boxDist(px, py, b)
	local dx = max(b[1] - px, 0, px - b[3])
	local dy = max(b[2] - py, 0, py - b[4])
	return sqrt(dx * dx + dy * dy)
end

-- Cumulative lengths, turns and stop positions of a path; its segments go into `grid`.
local function prepare(index, path, grid, cell)
	local pts = path.pts
	local n = #pts
	local P = { index = index, pts = pts, n = n, cum = { 0 }, turn = {}, stops = {}, half = path.half or 2 }
	for i = 2, n do
		local a, b = pts[i - 1], pts[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = sqrt(dx * dx + dy * dy)
		P.cum[i] = P.cum[i - 1] + len
		if len > 0 then
			local s = { path = index, ax = a[1], ay = a[2], bx = b[1], by = b[2], c0 = P.cum[i - 1], c1 = P.cum[i], half = P.half }
			-- In pieces no longer than a cell, so a long diagonal does not fill its whole bounding box.
			local pieces = ceil(len / cell)
			for k = 1, pieces do
				local x0, y0 = a[1] + dx * (k - 1) / pieces, a[2] + dy * (k - 1) / pieces
				local x1, y1 = a[1] + dx * k / pieces, a[2] + dy * k / pieces
				gridAdd(grid, s, min(x0, x1) - s.half, min(y0, y1) - s.half, max(x0, x1) + s.half, max(y0, y1) + s.half)
			end
		end
	end
	for i = 2, n - 1 do
		P.turn[i] = turnAt(pts, i)
	end
	for i = 1, n do
		if i == 1 or i == n or pts[i].stop then
			P.stops[#P.stops + 1] = P.cum[i]
		end
	end
	P.total = P.cum[n] or 0
	local r = path.range
	P.from = r and P.cum[max(1, min(n, r.from or 1))] or 0
	P.to = r and P.cum[max(1, min(n, r.to or n))] or P.total
	P.arrows = path.arrows ~= false
	P.anchors = {} -- path positions of this path's arrowheads
	P.count = 0
	return P
end

-- The segment holding path position t: its index, the point there and the segment's angle.
local function locate(P, t)
	local cum, pts = P.cum, P.pts
	local lo, hi = 2, P.n
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if cum[mid] < t then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local i = lo
	while i < P.n and cum[i] - cum[i - 1] <= 0 do
		i = i + 1
	end
	local a, b = pts[i - 1], pts[i]
	local len = cum[i] - cum[i - 1]
	local k = len > 0 and (t - cum[i - 1]) / len or 0
	k = max(0, min(1, k))
	return i, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, atan2(b[2] - a[2], b[1] - a[1])
end

function RouteArrows.Place(paths, o)
	o = o or {}
	local arrows = {}
	if type(paths) ~= "table" or #paths == 0 then
		return arrows
	end
	local size = o.size or 12
	local headSize = (o.headSize or 0) > 0 and o.headSize or nil
	local spacing = o.spacing and max(o.spacing, size * 1.5) or nil
	local stopGap, bendGap, gap = o.stopGap or 10, o.bendGap or 2, o.gap or 2
	local limit, total = o.limit or RouteArrows.LIMIT, o.total or huge
	local pins, boxes = o.pins or {}, o.boxes or {}
	local step = max(1, size / 4) -- how far a candidate slides when its place is taken
	local cell = max(16, size * 2)
	local segGrid, arrowGrid = newGrid(cell), newGrid(cell)
	local P = {}
	local maxHalf = 0
	for i, path in ipairs(paths) do
		if type(path) == "table" and type(path.pts) == "table" and #path.pts >= 2 then
			P[#P + 1] = prepare(i, path, segGrid, cell)
			maxHalf = max(maxHalf, P[#P].half)
		end
	end

	-- Whether an arrow of radius r at path position t of path p is clear of everything.
	local function clear(p, t, r)
		if t - r < 0 or t + r > p.total then
			return nil
		end
		for _, s in ipairs(p.stops) do
			if abs(t - s) < stopGap + r - 1e-6 then
				return nil
			end
		end
		local i, x, y = locate(p, t)
		-- The path under the arrow (and bendGap beyond) must stay close to the chord across it, with no sharp corner: a
		-- small zigzag is fine, a corner is not. The arrow points along the chord.
		local w = r + bendGap
		local _, ax, ay = locate(p, max(0, t - w))
		local _, bx, by = locate(p, min(p.total, t + w))
		local cx, cy = bx - ax, by - ay
		local clen = sqrt(cx * cx + cy * cy)
		if clen < w then
			return nil
		end
		local limitDev = r * WOBBLE
		local function bent(j)
			local q = p.pts[j]
			return abs(p.turn[j] or 0) > SHARP or abs((q[1] - ax) * cy - (q[2] - ay) * cx) / clen > limitDev
		end
		if abs((x - ax) * cy - (y - ay) * cx) / clen > limitDev then
			return nil
		end
		for j = i - 1, 2, -1 do
			if p.cum[j] <= t - w then
				break
			end
			if bent(j) then
				return nil
			end
		end
		for j = i, p.n - 1 do
			if p.cum[j] >= t + w then
				break
			end
			if bent(j) then
				return nil
			end
		end
		local angle = atan2(cy, cx)
		for _, pin in ipairs(pins) do
			local dx, dy = x - pin[1], y - pin[2]
			if dx * dx + dy * dy < (pin[3] + r + gap) ^ 2 then
				return nil
			end
		end
		for _, b in ipairs(boxes) do
			if boxDist(x, y, b) < r + gap then
				return nil
			end
		end
		-- Other arrows: a clear arrow's length between them, so a stretch walked both ways shows them one by one.
		local apart = r + max(gap, 2 * r)
		if gridAny(arrowGrid, x - apart - r, y - apart - r, x + apart + r, y + apart + r, function(a)
			local dx, dy = x - a.x, y - a.y
			return dx * dx + dy * dy < (a.size / 2 + apart) ^ 2
		end) then
			return nil
		end
		-- Another part of the line (its own path beyond this stretch, or another route) crossing close by. One that runs
		-- alongside (the same corridor walked back) does not count: its arrows keep their distance above.
		local reach = r + maxHalf
		local own = r * 2 + p.half + bendGap
		local ux, uy = math.cos(angle), math.sin(angle)
		if gridAny(segGrid, x - reach, y - reach, x + reach, y + reach, function(s)
			if s.path == p.index and s.c1 >= t - own and s.c0 <= t + own then
				return false
			end
			if segDist(x, y, s) >= r + s.half then
				return false
			end
			local vx, vy = s.bx - s.ax, s.by - s.ay
			return abs(ux * vx + uy * vy) < PARALLEL * sqrt(vx * vx + vy * vy)
		end) then
			return nil
		end
		return i, x, y, angle
	end

	local function place(p, i, x, y, angle, sz, head, t)
		local a = { x = x, y = y, angle = angle, seg = i, path = p.index, size = sz, head = head or nil, t = t }
		arrows[#arrows + 1] = a
		gridAdd(arrowGrid, a, x - sz / 2, y - sz / 2, x + sz / 2, y + sz / 2)
		p.count = p.count + 1
		if head then
			p.anchors[#p.anchors + 1] = t
		end
	end

	local function room(p)
		return p.arrows and p.count < limit and #arrows < total
	end

	-- Arrowheads just before each stop (and at the end), sliding back along the leg while their place is taken.
	if headSize then
		local rh = headSize / 2
		for _, p in ipairs(P) do
			for k = 2, #p.stops do
				local s, prev = p.stops[k], p.stops[k - 1]
				if room(p) and s > p.from and s <= p.to + 1e-6 then
					local first = s - stopGap - rh
					local last = max(prev + stopGap + rh, first - (spacing or size * 4) / 2)
					local t = first
					while t >= last do
						local i, x, y, angle = clear(p, t, rh)
						if i then
							place(p, i, x, y, angle, headSize, true, t)
							break
						end
						t = t - step
					end
				end
			end
		end
	end

	local r = size / 2
	local function nearAnchor(p, t)
		for _, a in ipairs(p.anchors) do
			if abs(t - a) < (spacing or 0) / 2 then
				return true
			end
		end
		return false
	end

	-- Arrows every `spacing` along each path.
	if spacing then
		for _, p in ipairs(P) do
			local t = p.from + max(stopGap + r, spacing / 2)
			while t <= p.to - stopGap - r and room(p) do
				local i, x, y, angle
				if not nearAnchor(p, t) then
					i, x, y, angle = clear(p, t, r)
				end
				if i then
					place(p, i, x, y, angle, size, false, t)
					t = t + spacing
				else
					t = t + step
				end
			end
		end
	end

	-- A leg with no arrow at all: one as near its middle as it fits.
	for _, p in ipairs(spacing and P or {}) do
		for k = 2, #p.stops do
			local lo, hi = p.stops[k - 1], p.stops[k]
			if room(p) and lo >= p.from - 1e-6 and hi <= p.to + 1e-6 and hi - lo >= 2 * (stopGap + r) then
				local has = false
				for _, a in ipairs(arrows) do
					if a.path == p.index and a.t > lo and a.t < hi then
						has = true
						break
					end
				end
				-- Nearest the middle first, at full size, then a little smaller where pins and labels leave less room.
				for _, sz in ipairs(has and {} or { size, size * SMALLER }) do
					local mid, rr, done = (lo + hi) / 2, sz / 2, false
					for d = 0, (hi - lo) / 2, step do
						for _, t in ipairs(d > 0 and { mid + d, mid - d } or { mid }) do
							local i, x, y, angle = clear(p, t, rr)
							if i then
								place(p, i, x, y, angle, sz, false, t)
								done = true
								break
							end
						end
						if done then
							break
						end
					end
					if done then
						break
					end
				end
			end
		end
	end
	return arrows
end

-- Pins and their shown labels (items laid out by MapLayout.Nudge and MapLayout.Labels: x, y, r, w, h, side, dx, dy;
-- y down) as obstacles for Place. flip: the paths' y runs up (canvas offsets), so y is negated.
function RouteArrows.Obstacles(items, flip)
	local pins, boxes = {}, {}
	local k = flip and -1 or 1
	for _, it in ipairs(items or {}) do
		pins[#pins + 1] = { it.x, it.y * k, it.r or 0 }
		if it.side and (it.w or 0) > 0 then
			local b = ns.MapLayout.LabelBox(it, it.side)
			local dx, dy = it.dx or 0, it.dy or 0
			local y1, y2 = (b[2] + dy) * k, (b[4] + dy) * k
			boxes[#boxes + 1] = { b[1] + dx, min(y1, y2), b[3] + dx, max(y1, y2) }
		end
	end
	return { pins = pins, boxes = boxes }
end
