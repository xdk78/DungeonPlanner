-- A plan as an ordered list of steps: what the side panel lists, what run mode walks through, and what the map focuses
-- on. Pure: built from the plan's own data (no game API), cached per plan revision by the caller.
--
-- Order: the numbered route stops first (route points with a step number, in number order), each matched to what it
-- stands on: a boss marker (a boss step), a pull (the stop's own pull link, or a pack or patrol marker in a pull
-- under it), an entrance marker, a quest giver or other notable marker, or nothing (a move step with the stop's note).
-- A stop with both a boss and a pull becomes two steps: the pull, then the boss. Then, in route order (where they
-- project onto the route, within ROUTE_NEAR): pulls no stop covers and notable markers (quest givers, NPCs, quest
-- items, interactive objects) the route passes. Pulls and bosses still left are put where their order says: after the
-- step of the nearest earlier one that is placed, else before the step of the nearest later one, else at the end (a
-- boss whose marker belongs to a pull goes right after that pull). A plan without stops starts at its entrance and
-- follows pull order. Objectives come last, or right after their boss.
--
-- step = { kind = "entrance" | "pull" | "boss" | "marker" | "move" | "objective", floor?, x?, y?, pull?, encounter?,
--          objective?, marker?, note?, stop? (the route step number), route?, from?, to? (the route points leading
--          here), path?, t? (the route and the distance along it, for ordering) }

local _, ns = ...
local Steps = ns:NewModule("Steps")

local NEAR = 0.04 -- how close (normalized) a stop must be to a marker to stand on it
local ROUTE_NEAR = 0.06 -- how close a pull or a notable marker must be to a route to be placed along it
local NEAR2 = ROUTE_NEAR * ROUTE_NEAR * 1.0001 -- squared, with room for rounding (a first, cheap test)
local NONE = {}

local function items(t)
	return type(t) == "table" and t or NONE
end

-- Cost: Build is near-linear in the plan's size. Markers are found through a grid of NEAR-sized cells, route segments
-- through a grid of ROUTE_NEAR-sized cells, and the list is a linked list while steps are inserted, with the first and
-- last step of each pull and boss at hand; ties are broken in the plan's order, as a plain scan would.

local BOSS = { boss = true }
local PACK = { pack = true, patrol = true }
local ENTRANCE = { entrance = true }
-- Markers worth a step of their own where the route passes them.
local NOTABLE = { quest_npc = true, npc = true, quest_item = true, interactive = true }
Steps.NOTABLE = NOTABLE

-- Distance along a route to each of its points: { [i] = length from point 1 }.
local function lengths(route)
	local out, total = {}, 0
	local pts = items(route.points)
	for i, pt in ipairs(pts) do
		if i > 1 then
			local prev = pts[i - 1]
			total = total + math.sqrt((pt[1] - prev[1]) ^ 2 + (pt[2] - prev[2]) ^ 2)
		end
		out[i] = total
	end
	return out
end

-- Distance from (x, y) to the segment of points a -> b, and the fraction along it of the nearest point (clamped).
local function toSegment(x, y, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local u = len2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) or 0
	return math.sqrt((x - ax - u * dx) ^ 2 + (y - ay - u * dy) ^ 2), u, len2
end

-- Where (x, y) lies along a route: the distance along the path to its nearest point, and how far off the path it is.
-- nil for a route without points. `cum`: the route's lengths when the caller has them.
function Steps.Project(route, x, y, cum)
	local pts = items(route.points)
	if #pts == 0 then
		return nil
	end
	cum = cum or lengths(route)
	local bestT, bestD = 0, math.sqrt((x - pts[1][1]) ^ 2 + (y - pts[1][2]) ^ 2)
	for i = 2, #pts do
		local d, u, len2 = toSegment(x, y, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
		if d < bestD then
			bestD, bestT = d, cum[i - 1] + u * math.sqrt(len2)
		end
	end
	return bestT, bestD
end

-- A grid of cells `size` wide per floor: grid[floor][cx][cy] = { item, ... } in the order they were added.
local function cellOf(v, size)
	return math.floor(v / size)
end

local function gridAdd(grid, floor, cx, cy, item)
	local f = grid[floor]
	if not f then
		f = {}
		grid[floor] = f
	end
	local col = f[cx]
	if not col then
		col = {}
		f[cx] = col
	end
	local cell = col[cy]
	if not cell then
		cell = {}
		col[cy] = cell
	end
	cell[#cell + 1] = item
end

local function gridCell(grid, floor, cx, cy)
	local f = grid[floor]
	local col = f and f[cx]
	return col and col[cy] or NONE
end

-- Markers by floor and NEAR-sized cell (a hair wider, so rounding never hides a neighbour two cells away).
local MARKER_CELL = NEAR * 1.001

local function markerGrid(plan)
	local grid = {}
	for i, m in ipairs(items(plan.markers)) do
		if type(m.x) == "number" and type(m.y) == "number" then
			gridAdd(grid, m.floor, cellOf(m.x, MARKER_CELL), cellOf(m.y, MARKER_CELL), i)
		end
	end
	return grid
end

-- The marker of `kinds` on `floor` closest to (x, y) within NEAR (on both axes), or nil; of equal distance, the first
-- in the plan.
local function markerAt(plan, grid, floor, x, y, kinds)
	local markers = items(plan.markers)
	local best, bestD, bestI
	local cx, cy = cellOf(x, MARKER_CELL), cellOf(y, MARKER_CELL)
	for gx = cx - 1, cx + 1 do
		for gy = cy - 1, cy + 1 do
			for _, i in ipairs(gridCell(grid, floor, gx, gy)) do
				local m = markers[i]
				if kinds[m.kind] and math.abs(m.x - x) <= NEAR and math.abs(m.y - y) <= NEAR then
					local d = (m.x - x) ^ 2 + (m.y - y) ^ 2
					if not bestD or d < bestD or (d == bestD and i < bestI) then
						best, bestD, bestI = m, d, i
					end
				end
			end
		end
	end
	return best
end

-- The numbered stops of every route, in step order: { route, index, from, point, floor, t }.
local function stops(plan)
	local out = {}
	for order, route in ipairs(items(plan.routes)) do
		local from = 1
		local cum = lengths(route)
		for i, pt in ipairs(items(route.points)) do
			if pt.step then
				out[#out + 1] = { route = route, index = i, from = from, point = pt, floor = route.floor, order = order,
					t = cum[i] }
				from = i
			end
		end
	end
	table.sort(out, function(a, b)
		if a.point.step ~= b.point.step then
			return a.point.step < b.point.step
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.index < b.index
	end)
	return out
end

-- Where each pull is on the map: the centre of its markers on the floor most of them are on (of equal counts, the one
-- that got there first). { [pullId] = { floor, x, y } }, one pass over the markers.
local function pullPlaces(plan)
	local byPull = {}
	for _, m in ipairs(items(plan.markers)) do
		if m.pull ~= nil then
			local p = byPull[m.pull]
			if not p then
				p = { byFloor = {} }
				byPull[m.pull] = p
			end
			local list = p.byFloor[m.floor] or {}
			p.byFloor[m.floor] = list
			list[#list + 1] = m
			if not p.best or #list > #p.byFloor[p.best] then
				p.best = m.floor
			end
		end
	end
	local out = {}
	for id, p in pairs(byPull) do
		local x, y = ns.Route.Centroid(p.byFloor[p.best])
		out[id] = { p.best, x, y }
	end
	return out
end

-- The step a numbered stop makes; a stop on a boss with a pull makes two (the pull, then the boss). A stop near a boss
-- that an earlier stop already made a step of (`stepped[encounter]`) is not that boss again: a route that walks on
-- past the boss, or comes back by it, gets a move (or whatever else stands there).
local function stopSteps(plan, grid, places, s, stepped)
	local pt = s.point
	local x, y = pt[1], pt[2]
	local step = { floor = s.floor, x = x, y = y, note = pt.note, stop = pt.step, route = s.route.id, from = s.from,
		to = s.index, path = s.route.id, t = s.t }
	local bossMarker = markerAt(plan, grid, s.floor, x, y, BOSS)
	if bossMarker and bossMarker.encounter ~= nil and stepped[bossMarker.encounter] then
		bossMarker = nil
	end
	if bossMarker then
		step.marker = bossMarker.id
		step.encounter = bossMarker.encounter
	end
	step.pull = pt.pull
	if not step.pull then
		local pack = markerAt(plan, grid, s.floor, x, y, PACK)
		if pack and pack.pull then
			step.pull = pack.pull
		end
	end
	local other = not step.pull and not bossMarker
		and (markerAt(plan, grid, s.floor, x, y, ENTRANCE) or markerAt(plan, grid, s.floor, x, y, NOTABLE))
	if other then
		step.marker = other.id
	end
	step.kind = bossMarker and "boss" or step.pull and "pull"
		or other and (other.kind == "entrance" and "entrance" or "marker") or "move"
	if step.kind == "boss" and step.pull then
		-- The pack first, where its markers are; then the boss.
		local place = places[step.pull]
		local px, py = x, y
		if place and place[1] == s.floor then
			px, py = place[2], place[3]
		end
		local pull = { kind = "pull", pull = step.pull, floor = s.floor, x = px, y = py, stop = pt.step,
			route = s.route.id, from = s.from, to = s.index, path = s.route.id, t = s.t }
		return pull, step
	end
	return step
end

-- Route segments by floor and ROUTE_NEAR-sized cell, for the routes with numbered stops: each segment is in every cell
-- its box, widened by ROUTE_NEAR, touches. A route of one point is one segment of no length.
local function segmentGrid(plan, withStops)
	local grid = {}
	for order, route in ipairs(items(plan.routes)) do
		local pts = items(route.points)
		if withStops[route.id] and #pts > 0 then
			local cum = lengths(route)
			local n = math.max(1, #pts - 1)
			for i = 1, n do
				local a, b = pts[i], pts[math.min(i + 1, #pts)]
				local seg = { order = order, index = i, route = route.id, ax = a[1], ay = a[2], bx = b[1], by = b[2],
					t0 = cum[i] }
				local x0 = cellOf(math.min(a[1], b[1]) - ROUTE_NEAR, ROUTE_NEAR)
				local x1 = cellOf(math.max(a[1], b[1]) + ROUTE_NEAR, ROUTE_NEAR)
				local y0 = cellOf(math.min(a[2], b[2]) - ROUTE_NEAR, ROUTE_NEAR)
				local y1 = cellOf(math.max(a[2], b[2]) + ROUTE_NEAR, ROUTE_NEAR)
				local dx = b[1] - a[1]
				for cx = x0, x1 do
					-- A long slanted segment only in the cells near it: per column, the part of the segment over the
					-- column (widened by ROUTE_NEAR) and the rows within ROUTE_NEAR of that part.
					local ylo, yhi = y0, y1
					if math.abs(dx) > 1e-9 then
						local lo = math.max(math.min(a[1], b[1]), cx * ROUTE_NEAR - ROUTE_NEAR)
						local hi = math.min(math.max(a[1], b[1]), (cx + 1) * ROUTE_NEAR + ROUTE_NEAR)
						if lo <= hi then
							local ya = a[2] + (lo - a[1]) / dx * (b[2] - a[2])
							local yb = a[2] + (hi - a[1]) / dx * (b[2] - a[2])
							ylo = math.max(y0, cellOf(math.min(ya, yb) - ROUTE_NEAR, ROUTE_NEAR))
							yhi = math.min(y1, cellOf(math.max(ya, yb) + ROUTE_NEAR, ROUTE_NEAR))
						end
					end
					for cy = ylo, yhi do
						gridAdd(grid, route.floor, cx, cy, seg)
					end
				end
			end
		end
	end
	return grid
end

-- The route with numbered stops on `floor` that passes (x, y) within ROUTE_NEAR: its id and the distance along it to
-- there; nil when none does. The nearest segment wins; of equal distance, the earlier route, then the earlier segment
-- (Steps.Project over each route in plan order gives the same answer).
local function along(segments, floor, x, y)
	if not (floor and x and y) then
		return nil
	end
	local best, bestD, bestT
	local cell = gridCell(segments, floor, cellOf(x, ROUTE_NEAR), cellOf(y, ROUTE_NEAR))
	for k = 1, #cell do
		local seg = cell[k]
		-- A cheap squared distance first: a segment clearly farther than ROUTE_NEAR cannot be the answer.
		local ax, ay = seg.ax, seg.ay
		local sx, sy = seg.bx - ax, seg.by - ay
		local px, py = x - ax, y - ay
		local l2 = sx * sx + sy * sy
		local u = l2 > 0 and (px * sx + py * sy) / l2 or 0
		u = u < 0 and 0 or u > 1 and 1 or u
		local ex, ey = px - u * sx, py - u * sy
		if ex * ex + ey * ey <= NEAR2 then
			local d, uu, len2 = toSegment(x, y, ax, ay, seg.bx, seg.by)
			if not bestD or d < bestD
				or (d == bestD and (seg.order < best.order or (seg.order == best.order and seg.index < best.index))) then
				best, bestD, bestT = seg, d, seg.t0 + uu * math.sqrt(len2)
			end
		end
	end
	if best and bestD <= ROUTE_NEAR then
		return best.route, bestT
	end
	return nil
end


-- The step list while it is built: a linked list (head, tail, next, prev) with, per pull and per boss, the first and
-- last step about it, and per marker whether a step is about it.
local FIELDS = { "pull", "encounter" }

local function newChain()
	return { head = nil, tail = nil, n = 0, nxt = {}, prv = {}, first = { pull = {}, encounter = {} },
		last = { pull = {}, encounter = {} }, marker = {} }
end

-- Put `step` after `at` (nil: at the start). `appendLast`: the step is the last one about its pull / boss when it has
-- one already (true when it goes right after that last one, or at the end).
local function insertAfter(c, at, step)
	local nxt, prv = c.nxt, c.prv
	local after
	if at then
		after = nxt[at]
	else
		after = c.head
	end
	prv[step], nxt[step] = at, after
	if at then
		nxt[at] = step
	else
		c.head = step
	end
	if after then
		prv[after] = step
	else
		c.tail = step
	end
	c.n = c.n + 1
	for _, field in ipairs(FIELDS) do
		local v = step[field]
		if v ~= nil then
			local last = c.last[field][v]
			if last == nil then
				c.first[field][v], c.last[field][v] = step, step
			elseif last == at or after == nil then
				c.last[field][v] = step
			end
		end
	end
	if step.marker ~= nil then
		c.marker[step.marker] = true
	end
end

local function append(c, step)
	insertAfter(c, c.tail, step)
end

local function insertBefore(c, before, step)
	insertAfter(c, c.prv[before], step)
end

local function toList(c)
	local list, s = {}, c.head
	while s do
		list[#list + 1] = s
		s = c.nxt[s]
	end
	return list
end

-- Insert `step` among the steps of its route by distance along it: before the first one further along, else after the
-- last one on that route. paths[path] = that route's steps in list order.
local function insertAlong(c, paths, step)
	local seq = paths[step.path]
	local at
	for i, s in ipairs(seq) do
		if s.t and s.t > step.t then
			at = i
			break
		end
	end
	if at then
		insertBefore(c, seq[at], step)
		table.insert(seq, at, step)
	else
		insertAfter(c, seq[#seq], step)
		seq[#seq + 1] = step
	end
end

-- Put the items of `ids` (in their plan order) that no step covers next to their neighbours in that order: after the
-- last step about the one before it (which is placed by then), else before the first step about the nearest later one
-- that has a step, else at the end.
local function placeMissing(c, ids, field, make)
	local first, last = c.first[field], c.last[field]
	for k, id in ipairs(ids) do
		if not last[id] then
			local step = make(id)
			local prev = k > 1 and last[ids[k - 1]]
			if prev then
				insertAfter(c, prev, step)
			else
				local before
				for j = k + 1, #ids do
					before = first[ids[j]]
					if before then
						break
					end
				end
				if before then
					insertBefore(c, before, step)
				else
					append(c, step)
				end
			end
		end
	end
end

function Steps.Build(plan)
	if type(plan) ~= "table" then
		return {}
	end
	local c = newChain()
	local grid = markerGrid(plan)
	local places = pullPlaces(plan)
	local withStops, paths = {}, {}
	for _, s in ipairs(stops(plan)) do
		withStops[s.route.id] = true
		local a, b = stopSteps(plan, grid, places, s, c.last.encounter)
		-- A pull that has a stop of its own before its boss's stop is not repeated.
		local steps = (b and c.last.pull[a.pull]) and { b } or { a, b }
		for _, step in ipairs(steps) do
			append(c, step)
			local seq = paths[step.path] or {}
			paths[step.path] = seq
			seq[#seq + 1] = step
		end
	end
	if c.n > 0 then
		-- Pulls no stop covers, then notable markers, where the route passes them.
		local segments = segmentGrid(plan, withStops)
		for _, pull in ipairs(items(plan.pulls)) do
			if not c.last.pull[pull.id] then
				local place = places[pull.id]
				local floor, x, y = place and place[1], place and place[2], place and place[3]
				local path, t = along(segments, floor, x, y)
				if path then
					insertAlong(c, paths, { kind = "pull", pull = pull.id, floor = floor, x = x, y = y, path = path, t = t })
				end
			end
		end
		for _, m in ipairs(items(plan.markers)) do
			if NOTABLE[m.kind] and not c.marker[m.id] then
				local path, t = along(segments, m.floor, m.x, m.y)
				if path then
					insertAlong(c, paths, { kind = "marker", marker = m.id, floor = m.floor, x = m.x, y = m.y, note = m.note,
						path = path, t = t })
				end
			end
		end
	end
	if c.n == 0 then
		local entrance
		for _, m in ipairs(items(plan.markers)) do
			if m.kind == "entrance" and (not entrance or m.floor < entrance.floor) then
				entrance = m
			end
		end
		if entrance then
			append(c, { kind = "entrance", floor = entrance.floor, x = entrance.x, y = entrance.y, marker = entrance.id,
				note = entrance.note })
		end
	end

	local pullIds = {}
	for i, pull in ipairs(items(plan.pulls)) do
		pullIds[i] = pull.id
	end
	placeMissing(c, pullIds, "pull", function(id)
		local place = places[id]
		return { kind = "pull", pull = id, floor = place and place[1], x = place and place[2], y = place and place[3] }
	end)

	-- Bosses: right after their pull when their marker is in one; otherwise by boss order.
	local bossMarker = {}
	for _, m in ipairs(items(plan.markers)) do
		if m.kind == "boss" and m.encounter ~= nil and not bossMarker[m.encounter] then
			bossMarker[m.encounter] = m
		end
	end
	local encIds = {}
	for _, enc in ipairs(items(plan.encounters)) do
		local m = bossMarker[enc.id]
		if not c.last.encounter[enc.id] and m and m.pull and c.last.pull[m.pull] then
			insertAfter(c, c.last.pull[m.pull], { kind = "boss", encounter = enc.id, floor = m.floor, x = m.x, y = m.y,
				marker = m.id, pull = m.pull })
		end
		encIds[#encIds + 1] = enc.id
	end
	placeMissing(c, encIds, "encounter", function(id)
		local m = bossMarker[id]
		return { kind = "boss", encounter = id, floor = m and m.floor, x = m and m.x, y = m and m.y, marker = m and m.id }
	end)

	-- Objectives: right after their boss (after that boss's earlier objectives, so they keep the plan's order), else
	-- at the end.
	local lastObjective = {}
	for _, o in ipairs(items(plan.objectives)) do
		local step = { kind = "objective", objective = o.id, encounter = nil, note = o.text, after = o.encounter }
		local boss = o.encounter ~= nil and c.last.encounter[o.encounter]
		if boss then
			step.floor, step.x, step.y = boss.floor, boss.x, boss.y
			insertAfter(c, lastObjective[o.encounter] or boss, step)
			lastObjective[o.encounter] = step
		else
			append(c, step)
		end
	end
	return toList(c)
end

-- The number a route's numbered stop shows on the map: the number of the step it makes in `list` (the side panel's
-- and run mode's numbering), so the map and the list never disagree. A stop that makes two steps (a pull, then the boss
-- it stands on) shows the boss's: the stop is drawn on the boss, the pull has its own disc. { [routeId] = { [point
-- index] = step number } }, cached per list.
local stopNumbers = setmetatable({}, { __mode = "k" })
function Steps.StopNumbers(list)
	if type(list) ~= "table" then
		return {}
	end
	local out = stopNumbers[list]
	if not out then
		out = {}
		for i, s in ipairs(list) do
			if s.stop and s.route and s.to then
				out[s.route] = out[s.route] or {}
				out[s.route][s.to] = i
			end
		end
		stopNumbers[list] = out
	end
	return out
end

-- The first step that is about `encId` (a boss), or nil.
function Steps.IndexOfEncounter(list, encId)
	for i, s in ipairs(list) do
		if s.kind == "boss" and s.encounter == encId then
			return i
		end
	end
	return nil
end

-- After boss `encId` died, while the run is at step `current`: the step after that boss's step when the boss is at or
-- ahead of the current step (a kill never moves the run backwards), else `current`.
function Steps.AfterKill(list, current, encId)
	local i = Steps.IndexOfEncounter(list, encId)
	current = current or 1
	if i and i >= current then
		return math.min(i + 1, #list)
	end
	return current
end

-- The first step at or after `from` of `kind` ("pull" or "boss"), or nil.
function Steps.Next(list, from, kind)
	for i = math.max(1, from or 1), #list do
		if list[i].kind == kind then
			return i, list[i]
		end
	end
	return nil
end

-- Move `current` by `delta` within 1..#list (clamped).
function Steps.Move(list, current, delta)
	if #list == 0 then
		return nil
	end
	local i = (current or 1) + delta
	if i < 1 then
		return 1
	elseif i > #list then
		return #list
	end
	return i
end

-- What the map shows for a step: { floor, x, y, focusPull, focusEncounter, route, from, to }; nil without a step.
function Steps.Focus(step)
	if not step then
		return nil
	end
	return {
		floor = step.floor,
		x = step.x,
		y = step.y,
		focusPull = step.kind ~= "boss" and step.pull or nil,
		focusEncounter = step.encounter,
		route = step.route,
		from = step.from,
		to = step.to,
	}
end

-- The planned progress (forces %, Plan.UpdatePull) at step `index`: the last pull up to and including it that has one,
-- so a boss step shows the progress of the pull before it. Returns percent, the pull; nil when no pull so far has one.
function Steps.ProgressAt(plan, list, index)
	for i = math.min(index or 0, #list), 1, -1 do
		local step = list[i]
		if step.kind == "pull" and step.pull then
			for _, pull in ipairs(items(plan.pulls)) do
				if pull.id == step.pull and pull.progress then
					return pull.progress, pull
				end
			end
		end
	end
	return nil
end
