-- Route legs on the map: the stretch of a route between two numbered stops, found under the pointer for the hover
-- highlight, and two-lane drawing for corridors walked out and back. Pure geometry in screen units, used once per
-- redraw (Lanes) or per pointer move while hovering the map (Hit), never per frame otherwise.
--
--   RouteLegs.Lanes(pts, o)            a path with each out-and-back stretch drawn as two lanes, moved apart.
--   RouteLegs.Hit(paths, x, y, tol)    the path and segment nearest a point, within tol.
--   RouteLegs.Leg(pts, seg)            the stop-to-stop leg that holds segment seg: from, to (point indices).
--   RouteLegs.StepOf(list, route, seg) the step (Model/Steps.lua) whose leg holds segment seg of a route, and the
--                                      stop step before it on that route.
--
-- pts: { { x, y, stop = true? }, ... }; the first and last points count as stops. Segment i joins pts[i - 1] and pts[i].

local _, ns = ...
local RouteLegs = ns:NewModule("RouteLegs")

local sqrt, max, min, ceil = math.sqrt, math.max, math.min, math.ceil
local G = ns.RouteArrows -- the grid and the point-to-segment distance

local ANTI = 0.9 -- cosine: two segments whose directions are this close to opposite run out and back
local U_TURN = -0.5 -- cosine between the lane sides of two shifted segments: below it, the path turns back
local COLLINEAR = 0.5 -- two partners less than this apart (screen units) lie on one line

-- The shortest distance between segments a and b ({ ax, ay, bx, by }), when they do not cross.
local function segSegDist(a, b)
	local d = G.SegDist
	return min(d(a.ax, a.ay, b), d(a.bx, a.by, b), d(b.ax, b.ay, a), d(b.bx, b.by, a))
end

-- How far segment b runs alongside segment a: the length of b's projection that falls on a.
local function overlap(a, b)
	local ux, uy = a.ux, a.uy
	local p = (b.ax - a.ax) * ux + (b.ay - a.ay) * uy
	local q = (b.bx - a.ax) * ux + (b.by - a.ay) * uy
	return min(a.len, max(p, q)) - max(0, min(p, q))
end

-- The side segment s moves to, away from its partner t (+1: s's right, -1: its left): measured from the middle of the
-- stretch they share; when they lie on one line, each takes its own right (they run opposite ways, so they part).
local function sideFrom(s, t, lo, hi)
	local m = (lo + hi) / 2
	local px, py = s.ax + s.ux * m, s.ay + s.uy * m
	local c = max(0, min(t.len, (px - t.ax) * t.ux + (py - t.ay) * t.uy))
	local d = (t.ax + t.ux * c - px) * s.rx + (t.ay + t.uy * c - py) * s.ry
	return d > COLLINEAR and -1 or 1
end

-- o: { shift (how far each lane moves aside), near (segments closer than this, running opposite ways, are an
-- out-and-back stretch), yUp (true when y grows upwards, as in canvas offsets: decides which side is right) }.
-- Returns a new list of points { x, y, stop, i (the original point; nil for a point added inside a segment), seg (the
-- original segment ending here), lane (moved onto a lane), back (the drawn segment ending here lies on a lane that
-- runs against the corridor's first pass: the way back; a third pass the first's way is not, and shares its lane) }
-- and whether any segment moved. Each segment of such a stretch moves away from its
-- partner (the opposite segment it runs alongside the longest), to its own right when the two lie on one line. Only
-- the part a segment shares with its partner moves: a long segment with a short way back is split, with a short
-- slant to the lane where the shared part begins and back where it ends. Where the path turns back on a shifted
-- stretch, the turning point is doubled: once at the end of the way in, once at the start of the way back; the short
-- link between them belongs to the segment arriving.
function RouteLegs.Lanes(pts, o)
	o = o or {}
	local shift, near = o.shift or 3, o.near or 6
	local ramp = 2 * shift -- the slant between the middle line and a lane, along the segment
	local n = #pts
	local segs = {}
	-- The grid's cells are as large as an average segment (at least twice `near`), and a segment goes into the grid (and
	-- is looked up) in pieces no longer than a cell, so a long diagonal does not fill its whole bounding box: the work
	-- stays the same at any zoom.
	local total = 0
	for i = 2, n do
		local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
		total = total + sqrt(dx * dx + dy * dy)
	end
	local cell = max(16, near * 2, n > 1 and total / (n - 1) or 0)
	local grid = G.NewGrid(cell)
	local function eachPiece(s, grow, fn)
		local pieces = ceil(s.len / cell)
		local dx, dy = s.bx - s.ax, s.by - s.ay
		for k = 1, pieces do
			local x0, y0 = s.ax + dx * (k - 1) / pieces, s.ay + dy * (k - 1) / pieces
			local x1, y1 = s.ax + dx * k / pieces, s.ay + dy * k / pieces
			fn(min(x0, x1) - grow, min(y0, y1) - grow, max(x0, x1) + grow, max(y0, y1) + grow)
		end
	end
	for i = 2, n do
		local a, b = pts[i - 1], pts[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = sqrt(dx * dx + dy * dy)
		if len > 0 then
			local ux, uy = dx / len, dy / len
			-- The right side of the direction of travel.
			local rx, ry = uy, -ux
			if not o.yUp then
				rx, ry = -uy, ux
			end
			local s = { i = i, ax = a[1], ay = a[2], bx = b[1], by = b[2], len = len, ux = ux, uy = uy, rx = rx, ry = ry }
			segs[i] = s
			eachPiece(s, near, function(x1, y1, x2, y2)
				G.GridAdd(grid, s, x1, y1, x2, y2)
			end)
		end
	end
	local moved = false
	for i = 2, n do
		local s = segs[i]
		if s then
			-- partner: the opposite segment s runs alongside the longest (of two alike, the earlier); first: the earliest
			-- segment before s that runs alongside it either way (the corridor's first pass). Each segment near s is
			-- looked at once, however many cells they share.
			local partner, shared, first = nil, 0, nil
			local function look(t)
				if t.seen == s then
					return false
				end
				t.seen = s
				local dot = s.ux * t.ux + s.uy * t.uy
				if t ~= s and (dot < -ANTI or (dot > ANTI and t.i < s.i)) then
					local ov = overlap(s, t)
					if ov > min(near, s.len / 3) and segSegDist(s, t) < near then
						if dot < -ANTI and (ov > shared or (ov == shared and t.i < partner.i)) then
							partner, shared = t, ov
						end
						if t.i < s.i and (not first or t.i < first.i) then
							first = t
						end
					end
				end
				return false
			end
			eachPiece(s, 0, function(x1, y1, x2, y2)
				G.GridAny(grid, x1, y1, x2, y2, look)
			end)
			if partner then
				-- The part of s alongside its partner, from lo to hi along s; a short rest at either end moves too.
				local p = (partner.ax - s.ax) * s.ux + (partner.ay - s.ay) * s.uy
				local q = (partner.bx - s.ax) * s.ux + (partner.by - s.ay) * s.uy
				local lo, hi = max(0, min(p, q)), min(s.len, max(p, q))
				local side = sideFrom(s, partner, lo, hi)
				s.lo = lo > ramp and lo or 0
				s.hi = s.len - hi > ramp and hi or s.len
				s.sx, s.sy = s.rx * side, s.ry * side -- the unit step towards its lane
				-- The way back: against the direction of the corridor's first pass. A third pass that goes the first's
				-- way is solid again, in the first's lane (the same side of the corridor).
				s.back = first ~= nil and s.ux * first.ux + s.uy * first.uy < 0
				moved = true
			end
		end
	end
	local out = {}
	local function add(x, y, i, seg, lane)
		out[#out + 1] = { x, y, stop = pts[i].stop, i = i, seg = seg, lane = lane }
	end
	-- A point inside segment s, `along` from its start, in its lane (k = shift) or on the middle line (k = 0).
	local function inner(s, along, k)
		out[#out + 1] = { s.ax + s.ux * along + s.sx * k, s.ay + s.uy * along + s.sy * k, seg = s.i, lane = k ~= 0 }
	end
	for v = 1, n do
		local p = pts[v]
		local sIn, sOut = segs[v], segs[v + 1]
		local inLane = sIn and sIn.sx and sIn.hi >= sIn.len
		local outLane = sOut and sOut.sx and sOut.lo <= 0
		if inLane and outLane then
			local dot = sIn.sx * sOut.sx + sIn.sy * sOut.sy
			if dot < U_TURN then
				add(p[1] + sIn.sx * shift, p[2] + sIn.sy * shift, v, v, true)
				add(p[1] + sOut.sx * shift, p[2] + sOut.sy * shift, v, v, true)
			else
				-- A mitred corner keeps both lanes at the same distance from the middle line.
				local mx, my = sIn.sx + sOut.sx, sIn.sy + sOut.sy
				local m = sqrt(mx * mx + my * my)
				local k = shift / max(0.5, (mx * sIn.sx + my * sIn.sy) / m) / m
				add(p[1] + mx * k, p[2] + my * k, v, v, true)
			end
		elseif inLane then
			add(p[1] + sIn.sx * shift, p[2] + sIn.sy * shift, v, v, true)
		elseif outLane then
			add(p[1] + sOut.sx * shift, p[2] + sOut.sy * shift, v, v, true)
		else
			add(p[1], p[2], v, v)
		end
		-- The next segment's own split points: onto its lane where the shared part begins, off it where it ends.
		if sOut and sOut.sx then
			if sOut.lo > 0 then
				inner(sOut, sOut.lo - ramp, 0)
				inner(sOut, sOut.lo, shift)
			end
			if sOut.hi < sOut.len then
				inner(sOut, sOut.hi, shift)
				inner(sOut, sOut.hi + ramp, 0)
			end
		end
	end
	-- A drawn segment on the lane of a corridor's way back (both its ends in that lane) is marked at its end point.
	for k = 2, #out do
		local s = segs[out[k].seg]
		if s and s.back and out[k].lane and out[k - 1].lane then
			out[k].back = true
		end
	end
	return out, moved
end

-- paths: { { pts = { { x, y, seg = original segment? }, ... }, hit = false? (not hoverable) } }. Returns { path, seg (the
-- original segment: pts[k].seg, else k), d } for the segment nearest (x, y) within tol, or nil.
function RouteLegs.Hit(paths, x, y, tol)
	local best
	for pi, path in ipairs(paths or {}) do
		local pts = path.pts
		if path.hit ~= false and pts then
			for k = 2, #pts do
				local a, b = pts[k - 1], pts[k]
				if x >= min(a[1], b[1]) - tol and x <= max(a[1], b[1]) + tol and y >= min(a[2], b[2]) - tol
					and y <= max(a[2], b[2]) + tol and (a[1] ~= b[1] or a[2] ~= b[2]) then
					local d = G.SegDist(x, y, { ax = a[1], ay = a[2], bx = b[1], by = b[2] })
					if d <= tol and (not best or d < best.d) then
						best = { path = pi, seg = b.seg or k, d = d }
					end
				end
			end
		end
	end
	return best
end

function RouteLegs.Leg(pts, seg)
	local n = #pts
	if n < 2 or seg < 2 or seg > n then
		return nil
	end
	local from, to = 1, n
	for i = seg - 1, 1, -1 do
		if i == 1 or pts[i].stop then
			from = i
			break
		end
	end
	for i = seg, n do
		if i == n or pts[i].stop then
			to = i
			break
		end
	end
	return from, to
end

function RouteLegs.StepOf(list, routeId, seg)
	for i, s in ipairs(list or {}) do
		if s.stop and s.route == routeId and s.from and s.to and seg > s.from and seg <= s.to then
			local prev
			for j = i - 1, 1, -1 do
				local p = list[j]
				if p.stop and p.route == routeId and p.to == s.from then
					prev = j
					break
				end
			end
			return i, prev
		end
	end
	return nil
end
