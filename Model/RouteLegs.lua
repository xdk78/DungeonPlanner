-- Route legs on the map: the stretch of a route between two numbered stops, found under the pointer for the hover
-- highlight, and two-lane drawing for corridors walked out and back. Pure geometry in screen units, used once per
-- redraw (Lanes) or per pointer move while hovering the map (Hit), never per frame otherwise.
--
--   RouteLegs.Lanes(pts, o)            a path with each out-and-back stretch shifted to its own right (two lanes).
--   RouteLegs.Hit(paths, x, y, tol)    the path and segment nearest a point, within tol.
--   RouteLegs.Leg(pts, seg)            the stop-to-stop leg that holds segment seg: from, to (point indices).
--   RouteLegs.StepOf(list, route, seg) the step (Model/Steps.lua) whose leg holds segment seg of a route, and the
--                                      stop step before it on that route.
--
-- pts: { { x, y, stop = true? }, ... }; the first and last points count as stops. Segment i joins pts[i - 1] and pts[i].

local _, ns = ...
local RouteLegs = ns:NewModule("RouteLegs")

local sqrt, max, min = math.sqrt, math.max, math.min
local G = ns.RouteArrows -- the grid and the point-to-segment distance

local ANTI = 0.9 -- cosine: two segments whose directions are this close to opposite run out and back
local U_TURN = -0.5 -- cosine between the right sides of two shifted segments: below it, the path turns back

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

-- o: { shift (how far each lane moves to its right), near (segments closer than this, running opposite ways, are an
-- out-and-back stretch), yUp (true when y grows upwards, as in canvas offsets: decides which side is right) }.
-- Returns a new list of points { x, y, stop, i (the original point), seg (the original segment ending here) } and
-- whether any segment moved. Where the path turns back on a shifted stretch, the turning point is doubled: once at the
-- end of the way in, once at the start of the way back; the short link between them belongs to the segment arriving.
function RouteLegs.Lanes(pts, o)
	o = o or {}
	local shift, near = o.shift or 3, o.near or 6
	local n = #pts
	local segs = {}
	local grid = G.NewGrid(max(16, near * 2))
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
			G.GridAdd(grid, s, min(a[1], b[1]) - near, min(a[2], b[2]) - near, max(a[1], b[1]) + near,
				max(a[2], b[2]) + near)
		end
	end
	local moved = false
	for i = 2, n do
		local s = segs[i]
		if s then
			s.lane = G.GridAny(grid, min(s.ax, s.bx), min(s.ay, s.by), max(s.ax, s.bx), max(s.ay, s.by), function(t)
				return t ~= s and s.ux * t.ux + s.uy * t.uy < -ANTI and overlap(s, t) > min(near, s.len / 3)
					and segSegDist(s, t) < near
			end) or nil
			moved = moved or s.lane == true
		end
	end
	local out = {}
	local function add(x, y, i, seg)
		out[#out + 1] = { x, y, stop = pts[i].stop, i = i, seg = seg }
	end
	for v = 1, n do
		local p = pts[v]
		local sIn, sOut = segs[v], segs[v + 1]
		local inLane, outLane = sIn and sIn.lane, sOut and sOut.lane
		if inLane and outLane then
			local dot = sIn.rx * sOut.rx + sIn.ry * sOut.ry
			if dot < U_TURN then
				add(p[1] + sIn.rx * shift, p[2] + sIn.ry * shift, v, v)
				add(p[1] + sOut.rx * shift, p[2] + sOut.ry * shift, v, v)
			else
				-- A mitred corner keeps both lanes at the same distance from the middle line.
				local mx, my = sIn.rx + sOut.rx, sIn.ry + sOut.ry
				local m = sqrt(mx * mx + my * my)
				local k = shift / max(0.5, (mx * sIn.rx + my * sIn.ry) / m) / m
				add(p[1] + mx * k, p[2] + my * k, v, v)
			end
		elseif inLane then
			add(p[1] + sIn.rx * shift, p[2] + sIn.ry * shift, v, v)
		elseif outLane then
			add(p[1] + sOut.rx * shift, p[2] + sOut.ry * shift, v, v)
		else
			add(p[1], p[2], v, v)
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
