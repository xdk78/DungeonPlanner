-- Paths through a floor's walkable space, for the route tool's "Snap to corridors". Pure (no game API).
--
-- A grid covers one map picture, normalized 0..1 on both axes like the plans' coordinates: w x h cells, row by row from
-- the top left. A cell is floor, rough (drawn but not floor: a wall, a door or a room's outline inside the dungeon) or
-- blocked (the blank parchment around it). Data/WalkData.lua keeps every grid as run lengths (generated offline by
-- tools/walk_grids.py from the floor's map picture, docs/DATA-SOURCES.md); Data/Corridors.lua picks a plan floor's
-- grid and turns the plan's coordinates into the grid's.
--
--   grid = Walk.Decode(w, h, runs)          -- nil, err when the runs do not describe exactly w * h cells
--   bends, why, stats = Walk.Path(grid, ax, ay, bx, by, opts)
--     bends: the points between a and b ({ { x, y }, ... }, empty when the straight line is clear), normalized
--     why (when bends is nil): "off" (a or b is far from any floor), "none" (a and b are not connected) or "limit"
--     (the search reached opts.maxNodes); stats: { expanded = cells the search took from its open list, rough = rough
--     cells the path crosses }
--   opts: maxNodes (default Walk.MAX_NODES), tolerance (cells a bend may be left out by, default 0.8),
--         snap (cells a stop may lie off the floor, default 2)
--   price = Walk.Prices(grid, yield)        -- the one-time work a grid's searches share (below); Walk.Path does it
--                                           -- itself when it has not been done yet
--
-- Run lengths (Walk.Encode says how): runs of one class each, row by row. Each number is little-endian base 32 in the
-- 64 characters of Walk.ALPHABET: a character below 32 ends the number, one at 32 or above stands for its value - 32
-- and the number goes on.
--
-- The search is A* over the 8 neighbours (a diagonal step never cuts a blocked corner). A step costs its length times
-- the price of the cells it joins: on the floor 1 + WALL_COST * e^(-(distance to a wall - 1) / WALL_FALLOFF), so the
-- path keeps to the middle of corridors; a rough cell costs ROUGH, so the path crosses a wall or a door only where the
-- floor alone does not connect the stops (as tools/route_paths.py does). Douglas-Peucker then keeps the few bends it
-- needs; a straight piece crosses no blocked cell and no rough cell off the path. Walk.Path runs to completion in the
-- call; its work is bounded by maxNodes cells per leg, once per click or drag, never per frame.
--
-- Inside, a grid is padded with a blocked border (no bounds checks in the search): cell (cx, cy), 0-based, is
-- index (cy + 1) * stride + cx + 2 with stride = w + 2, in pass (floor) and rough.

local _, ns = ...
local Walk = ns:NewModule("Walk")

local floor, ceil, sqrt, exp, abs, max = math.floor, math.ceil, math.sqrt, math.exp, math.abs, math.max
local R2 = sqrt(2)

Walk.ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
Walk.MAX_NODES = 12000 -- per leg: more cells than a 120 x 80 grid has, so the cap only stops a runaway search
Walk.WALL_COST = 5
Walk.WALL_FALLOFF = 1.2
Walk.ROUGH = 40 -- the price of a rough cell (a floor cell costs 1 to 6)
Walk.MIN_GAP = 3 -- cells: a bend nearer than this to its neighbour goes (or moves) when the lines stay clear
Walk.MAX_CELLS = 40000 -- Decode refuses a larger grid

local DIGIT = {}
for i = 1, #Walk.ALPHABET do
	DIGIT[Walk.ALPHABET:byte(i)] = i - 1
end

-- After a run of class c (0 blocked, 1 floor, 2 rough), the next run's class: NEXT[c][t + 1] for the run's flag t.
local NEXT = { [0] = { 1, 2 }, [1] = { 0, 2 }, [2] = { 0, 1 } }

-- The runs string -> grid { w, h, stride, pass = { [padded cell] = floor? }, rough = { [padded cell] = true },
-- open = floor cells, roughCount }.
function Walk.Decode(w, h, runs)
	if type(w) ~= "number" or type(h) ~= "number" or w < 2 or h < 2 or w % 1 ~= 0 or h % 1 ~= 0
		or w * h > Walk.MAX_CELLS or type(runs) ~= "string" then
		return nil, "size"
	end
	local stride, total = w + 2, w * h
	local pass, rough = {}, {}
	for p = 1, stride * (h + 2) do
		pass[p] = false
	end
	local cell, count, roughCount, value, shift, class, first = 0, 0, 0, 0, 1, 0, true
	for i = 1, #runs do
		local d = DIGIT[runs:byte(i)]
		if not d then
			return nil, "character"
		end
		if d >= 32 then
			value, shift = value + (d - 32) * shift, shift * 32
		else
			value = value + d * shift
			local len = value
			if not first then
				class = NEXT[class][value % 2 + 1]
				len = (value - value % 2) / 2
				if len == 0 then
					return nil, "length"
				end
			end
			first = false
			if cell + len > total then
				return nil, "length"
			end
			if class > 0 then
				local out = class == 1 and pass or rough
				for c = cell, cell + len - 1 do
					local cx = c % w
					out[((c - cx) / w + 1) * stride + cx + 2] = true
				end
				if class == 1 then
					count = count + len
				else
					roughCount = roughCount + len
				end
			end
			cell, value, shift = cell + len, 0, 1
		end
	end
	if shift ~= 1 or cell ~= total then
		return nil, "length"
	end
	return { w = w, h = h, stride = stride, pass = pass, rough = rough, open = count, roughCount = roughCount }
end

-- The other way round (tests, and grids built in code): at(cx, cy) for 0-based cells -> 1 or true (floor), 2 (rough),
-- else blocked -> runs string. The first number is the length of the first run, blocked (possibly 0); every later one
-- is 2 * its length + t, its class being NEXT[the class before][t + 1].
function Walk.Encode(w, h, at)
	local out, run, class, first = {}, 0, 0, true
	local function put(v)
		repeat
			local d = v % 32
			v = (v - d) / 32
			local i = d + (v > 0 and 33 or 1)
			out[#out + 1] = Walk.ALPHABET:sub(i, i)
		until v == 0
	end
	local before = 0
	local function flush()
		if first then
			put(run)
			first = false
		else
			put(run * 2 + (NEXT[before][1] == class and 0 or 1))
		end
	end
	for cy = 0, h - 1 do
		for cx = 0, w - 1 do
			local v = at(cx, cy)
			local here = (v == true or v == 1) and 1 or v == 2 and 2 or 0
			if here ~= class then
				flush()
				before, class, run = class, here, 0
			end
			run = run + 1
		end
	end
	flush()
	return table.concat(out)
end

local function index(grid, cx, cy)
	return (cy + 1) * grid.stride + cx + 2
end

-- Is cell (cx, cy) (0-based) floor?
function Walk.Open(grid, cx, cy)
	return cx >= 0 and cy >= 0 and cx < grid.w and cy < grid.h and grid.pass[index(grid, cx, cy)]
end
local open = Walk.Open

-- Is cell (cx, cy) rough?
function Walk.Rough(grid, cx, cy)
	return cx >= 0 and cy >= 0 and cx < grid.w and cy < grid.h and grid.rough[index(grid, cx, cy)] == true
end

-- The price of every padded cell (0: blocked), from a floor cell's distance to the nearest cell that is not floor or
-- to the map's edge (two-pass chamfer, 1 and sqrt 2). Computed once per grid and kept on it, with the search's arrays;
-- yield, when given, is called between the three passes (Data/Corridors.lua prepares a floor over a few frames).
function Walk.Prices(grid, yield)
	if grid.price then
		return grid.price
	end
	local pass, rough, s, h, w = grid.pass, grid.rough, grid.stride, grid.h, grid.w
	local d = {}
	for p = 1, #pass do
		d[p] = pass[p] and 1e9 or 0
	end
	for y = 1, h do
		for x = 1, w do
			local p = y * s + x + 1
			local v = d[p]
			if v > 0 then
				local a = d[p - 1] + 1
				if a < v then v = a end
				a = d[p - s] + 1
				if a < v then v = a end
				a = d[p - s - 1] + R2
				if a < v then v = a end
				a = d[p - s + 1] + R2
				if a < v then v = a end
				d[p] = v
			end
		end
	end
	if yield then
		yield()
	end
	for y = h, 1, -1 do
		for x = w, 1, -1 do
			local p = y * s + x + 1
			local v = d[p]
			if v > 0 then
				local a = d[p + 1] + 1
				if a < v then v = a end
				a = d[p + s] + 1
				if a < v then v = a end
				a = d[p + s + 1] + R2
				if a < v then v = a end
				a = d[p + s - 1] + R2
				if a < v then v = a end
				d[p] = v
			end
		end
	end
	if yield then
		yield()
	end
	local price, cost, fall, roughPrice = {}, Walk.WALL_COST, Walk.WALL_FALLOFF, Walk.ROUGH
	local g, from, seen, closed = {}, {}, {}, {}
	for p = 1, #pass do
		price[p] = pass[p] and 1 + cost * exp(-(d[p] - 1) / fall) or rough[p] and roughPrice or 0
		g[p], from[p], seen[p], closed[p] = 0, 0, 0, 0
	end
	grid.price = price
	grid.g, grid.from, grid.seen, grid.closed, grid.gen = g, from, seen, closed, 0
	return price
end

-- Where a search starts or ends for a stop at cell-space point (px, py): the nearest floor cell within `reach` cells,
-- else the stop's own cell when it is rough (a stop drawn on a wall or a door); nil when neither.
local function startCell(grid, px, py, reach)
	local cx, cy = floor(px), floor(py)
	if open(grid, cx, cy) then
		return cx, cy
	end
	local best, bx, by = nil, nil, nil
	local r = ceil(reach)
	for y = cy - r, cy + r do
		for x = cx - r, cx + r do
			if open(grid, x, y) then
				local dx, dy = x + 0.5 - px, y + 0.5 - py
				local dd = dx * dx + dy * dy
				if dd <= (reach + 0.5) * (reach + 0.5) and (not best or dd < best) then
					best, bx, by = dd, x, y
				end
			end
		end
	end
	if bx then
		return bx, by
	end
	if Walk.Rough(grid, cx, cy) then
		return cx, cy
	end
	return nil
end

-- Can a straight piece from (ax, ay) to (bx, by) (cell space) be walked? Every cell it enters must be floor, or in
-- `allow` (padded indexes: the rough cells a path crosses; grid.rough allows them all). Samples every quarter cell;
-- where a step changes both column and row, one of the two cells beside the corner must be allowed too.
function Walk.Clear(grid, ax, ay, bx, by, allow)
	local pass, w, h, s = grid.pass, grid.w, grid.h, grid.stride
	allow = allow or {}
	local function ok(cx, cy)
		if cx < 0 or cy < 0 or cx >= w or cy >= h then
			return false
		end
		local p = (cy + 1) * s + cx + 2
		return pass[p] or allow[p] == true
	end
	local dx, dy = bx - ax, by - ay
	local n = max(1, ceil(max(abs(dx), abs(dy)) * 4))
	local px, py = floor(ax), floor(ay)
	for i = 1, n do
		local t = i / n
		local cx, cy = floor(ax + dx * t), floor(ay + dy * t)
		if cx ~= px or cy ~= py then
			if not ok(cx, cy) then
				return false
			end
			if cx ~= px and cy ~= py and not ok(cx, py) and not ok(px, cy) then
				return false
			end
			px, py = cx, cy
		end
	end
	return true
end
local clear = Walk.Clear

-- Douglas-Peucker over pts[i..j] (cell space): a piece is kept only when it is clear. Appends the kept points after i.
local function simplify(grid, pts, i, j, tol, allow, out)
	if j <= i + 1 then
		out[#out + 1] = pts[j]
		return
	end
	local a, b = pts[i], pts[j]
	local ex, ey = b[1] - a[1], b[2] - a[2]
	local len = sqrt(ex * ex + ey * ey)
	local worst, at = -1, i + 1
	for k = i + 1, j - 1 do
		local p = pts[k]
		local dev
		if len < 1e-9 then
			dev = sqrt((p[1] - a[1]) ^ 2 + (p[2] - a[2]) ^ 2)
		else
			dev = abs(ex * (p[2] - a[2]) - ey * (p[1] - a[1])) / len
		end
		if dev > worst then
			worst, at = dev, k
		end
	end
	if worst <= tol and clear(grid, a[1], a[2], b[1], b[2], allow) then
		out[#out + 1] = b
		return
	end
	simplify(grid, pts, i, at, tol, allow, out)
	simplify(grid, pts, at, j, tol, allow, out)
end

-- A binary heap of cells by their f value when they were pushed (hf: the values, hc: the cells). A cell found again
-- more cheaply is pushed again; its stale entry is skipped when it comes out.
local function push(hf, hc, n, fv, c)
	n = n + 1
	while n > 1 do
		local p = floor(n / 2)
		local pf = hf[p]
		if pf <= fv then
			break
		end
		hf[n], hc[n] = pf, hc[p]
		n = p
	end
	hf[n], hc[n] = fv, c
end

local function pop(hf, hc, n)
	local top = hc[1]
	local lf, lc = hf[n], hc[n]
	hf[n], hc[n] = nil, nil
	n = n - 1
	if n > 0 then
		local i = 1
		while true do
			local child = 2 * i
			if child > n then
				break
			end
			local cf = hf[child]
			if child < n and hf[child + 1] < cf then
				child = child + 1
				cf = hf[child]
			end
			if cf >= lf then
				break
			end
			hf[i], hc[i] = cf, hc[child]
			i = child
		end
		hf[i], hc[i] = lf, lc
	end
	return top
end

-- A* from padded cell `start` to `goal`. Returns true when found (grid.from holds the way back), or false, "none" |
-- "limit"; and the number of cells expanded. One search per grid at a time: they share its arrays.
local function search(grid, start, goal, maxNodes)
	local price = Walk.Prices(grid)
	local s = grid.stride
	local g, from, seen, closed = grid.g, grid.from, grid.seen, grid.closed
	local gen = grid.gen + 1
	grid.gen = gen
	local tx, ty = (goal - 1) % s, floor((goal - 1) / s)
	local function heuristic(x, y)
		local dx, dy = abs(x - tx), abs(y - ty)
		if dx < dy then
			return dy + (R2 - 1) * dx
		end
		return dx + (R2 - 1) * dy
	end
	local hf, hc, n = {}, {}, 0
	g[start], from[start], seen[start] = 0, 0, gen
	push(hf, hc, n, heuristic((start - 1) % s, floor((start - 1) / s)), start)
	n = 1
	local expanded = 0
	local E, W, S, N = 1, -1, s, -s
	while n > 0 do
		local c = pop(hf, hc, n)
		n = n - 1
		if closed[c] ~= gen then
			closed[c] = gen
			expanded = expanded + 1
			if c == goal then
				return true, nil, expanded
			end
			if expanded >= maxNodes then
				return false, "limit", expanded
			end
			local cx, cy = (c - 1) % s, floor((c - 1) / s)
			local gc, pc = g[c], price[c]
			local pe, pw, ps, pn = price[c + E] > 0, price[c + W] > 0, price[c + S] > 0, price[c + N] > 0
			-- The 8 neighbours: offset, step length, x and y offsets, and whether the step is allowed.
			for k = 1, 8 do
				local off, len, dx, dy, ok
				if k == 1 then off, len, dx, dy, ok = E, 1, 1, 0, pe
				elseif k == 2 then off, len, dx, dy, ok = W, 1, -1, 0, pw
				elseif k == 3 then off, len, dx, dy, ok = S, 1, 0, 1, ps
				elseif k == 4 then off, len, dx, dy, ok = N, 1, 0, -1, pn
				elseif k == 5 then off, len, dx, dy, ok = S + E, R2, 1, 1, pe and ps
				elseif k == 6 then off, len, dx, dy, ok = S + W, R2, -1, 1, pw and ps
				elseif k == 7 then off, len, dx, dy, ok = N + E, R2, 1, -1, pe and pn
				else off, len, dx, dy, ok = N + W, R2, -1, -1, pw and pn
				end
				local nb = c + off
				local pnb = price[nb]
				if ok and pnb > 0 and closed[nb] ~= gen then
					local cost = gc + len * (pc + pnb) * 0.5
					if seen[nb] ~= gen or cost < g[nb] then
						g[nb], from[nb], seen[nb] = cost, c, gen
						push(hf, hc, n, cost + heuristic(cx + dx, cy + dy), nb)
						n = n + 1
					end
				end
			end
		end
	end
	return false, "none", expanded
end

-- Where to try one bend in place of two close ones: their middle, then half a cell around it.
local NUDGE = { { 0, 0 }, { 0.5, 0 }, { -0.5, 0 }, { 0, 0.5 }, { 0, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 }, { 0.5, -0.5 },
	{ -0.5, -0.5 } }

-- Where to try a bend too close to a neighbour: 1, 1.5 and 2 cells off in 8 directions.
local SHIFT = {}
for _, r in ipairs({ 1, 1.5, 2 }) do
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }) do
		SHIFT[#SHIFT + 1] = { d[1] * r, d[2] * r }
	end
end

function Walk.Path(grid, ax, ay, bx, by, opts)
	opts = opts or {}
	local tol, reach = opts.tolerance or 0.8, opts.snap or 2
	local stats = { expanded = 0, rough = 0 }
	local w, h, s = grid.w, grid.h, grid.stride
	-- Cell space: x in 0..w, y in 0..h.
	local pax, pay, pbx, pby = ax * w, ay * h, bx * w, by * h
	local sx, sy = startCell(grid, pax, pay, reach)
	local tx, ty = startCell(grid, pbx, pby, reach)
	if not sx or not tx then
		return nil, "off", stats
	end
	local aOn, bOn = open(grid, floor(pax), floor(pay)), open(grid, floor(pbx), floor(pby))
	if aOn and bOn and clear(grid, pax, pay, pbx, pby) then
		return {}, nil, stats
	end
	local start, goal = (sy + 1) * s + sx + 2, (ty + 1) * s + tx + 2
	local found, why, expanded = search(grid, start, goal, opts.maxNodes or Walk.MAX_NODES)
	stats.expanded = expanded
	if not found then
		return nil, why, stats
	end
	-- The cells' centres from a to b, with the stops themselves at both ends; the rough cells on the way may be crossed.
	local cells, from, allow = {}, grid.from, {}
	local c = goal
	while c ~= 0 do
		cells[#cells + 1] = c
		if not grid.pass[c] then
			allow[c] = true
			stats.rough = stats.rough + 1
		end
		c = c == start and 0 or from[c]
	end
	local pts = { { pax, pay } }
	for i = #cells, 1, -1 do
		local cc = cells[i]
		pts[#pts + 1] = { (cc - 1) % s - 1 + 0.5, floor((cc - 1) / s) - 1 + 0.5 }
	end
	pts[#pts + 1] = { pbx, pby }
	-- A stop placed off the floor (within `reach`): the cells around it may be crossed on the way to the floor.
	for _, stop in ipairs({ { pax, pay, aOn }, { pbx, pby, bOn } }) do
		if not stop[3] then
			local cx, cy, r = floor(stop[1]), floor(stop[2]), ceil(reach)
			for y = math.max(0, cy - r), math.min(h - 1, cy + r) do
				for x = math.max(0, cx - r), math.min(w - 1, cx + r) do
					allow[(y + 1) * s + x + 2] = true
				end
			end
		end
	end
	local kept = { pts[1] }
	simplify(grid, pts, 1, #pts, tol, allow, kept)
	-- Bends closer than MIN_GAP cells to the point before or after go where the line without them is still clear (on
	-- the map, close points' handles would lie on each other).
	local gap2, k = Walk.MIN_GAP * Walk.MIN_GAP, 2
	while k < #kept do
		local p, q, r = kept[k - 1], kept[k], kept[k + 1]
		local near = (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 < gap2 or (r[1] - q[1]) ^ 2 + (r[2] - q[2]) ^ 2 < gap2
		-- Two close bends neither of which can go: one point near their middle that keeps both pieces clear.
		local m
		if near and k + 1 < #kept and (r[1] - q[1]) ^ 2 + (r[2] - q[2]) ^ 2 < gap2 then
			local n, mx, my = kept[k + 2], (q[1] + r[1]) / 2, (q[2] + r[2]) / 2
			for _, d in ipairs(NUDGE) do
				local cx, cy = mx + d[1], my + d[2]
				if not m and clear(grid, p[1], p[2], cx, cy, allow) and clear(grid, cx, cy, n[1], n[2], allow) then
					m = { cx, cy }
				end
			end
		end
		-- Else the bend moved a little, away from both neighbours, where both pieces stay clear.
		local moved
		if near and not m then
			for _, d in ipairs(SHIFT) do
				local cx, cy = q[1] + d[1], q[2] + d[2]
				if not moved and (cx - p[1]) ^ 2 + (cy - p[2]) ^ 2 >= gap2 and (r[1] - cx) ^ 2 + (r[2] - cy) ^ 2 >= gap2
					and clear(grid, p[1], p[2], cx, cy, allow) and clear(grid, cx, cy, r[1], r[2], allow) then
					moved = { cx, cy }
				end
			end
		end
		if near and clear(grid, p[1], p[2], r[1], r[2], allow) then
			table.remove(kept, k)
			k = math.max(2, k - 1)
		elseif m then
			kept[k] = m
			table.remove(kept, k + 1)
		else
			kept[k] = moved or q
			k = k + 1
		end
	end
	local bends = {}
	for i = 2, #kept - 1 do
		bends[#bends + 1] = { kept[i][1] / w, kept[i][2] / h }
	end
	return bends, nil, stats
end
