-- Route helpers: path length and a suggested visiting order through a set of points ("optimal path"). Pure.
--
-- The order is a heuristic, not a guarantee: nearest neighbour from the start point, then 2-opt improvement with an
-- iteration cap so it stays fast on 100+ points. It works on straight-line distance across the map, so it does not
-- know about walls; the planner reviews and edits the result. `aspect` is the map's width / height, because normalized
-- x and y are not the same length on a non-square map.

local _, ns = ...
local Route = ns:NewModule("Route")

local sqrt = math.sqrt

local function dist(a, b, aspect)
	local dx = (a[1] - b[1]) * aspect
	local dy = a[2] - b[2]
	return sqrt(dx * dx + dy * dy)
end

function Route.Length(points, aspect)
	aspect = aspect or 1
	local total = 0
	for i = 2, #points do
		total = total + dist(points[i - 1], points[i], aspect)
	end
	return total
end

-- points: { {x, y}, ... }; start: index of the fixed first point (default 1). Returns an array of indexes into points.
-- An open path (no return to the start), which is what a dungeon route is.
function Route.SuggestOrder(points, aspect, start, maxIterations)
	aspect = aspect or 1
	start = start or 1
	maxIterations = maxIterations or 2000
	local n = #points
	if n <= 2 then
		local order = {}
		for i = 1, n do
			order[i] = i
		end
		if n == 2 and start == 2 then
			order = { 2, 1 }
		end
		return order
	end

	-- Nearest neighbour.
	local order, used = { start }, { [start] = true }
	local current = start
	for _ = 2, n do
		local best, bestD = nil, math.huge
		for j = 1, n do
			if not used[j] then
				local d = dist(points[current], points[j], aspect)
				if d < bestD then
					best, bestD = j, d
				end
			end
		end
		order[#order + 1] = best
		used[best] = true
		current = best
	end

	-- 2-opt on the open path, keeping order[1] fixed: reverse order[i..k] when that shortens the path.
	local iterations = 0
	local improved = true
	while improved and iterations < maxIterations do
		improved = false
		for i = 2, n - 1 do
			for k = i + 1, n do
				iterations = iterations + 1
				local a, b = points[order[i - 1]], points[order[i]]
				local c = points[order[k]]
				local d = order[k + 1] and points[order[k + 1]]
				local before = dist(a, b, aspect) + (d and dist(c, d, aspect) or 0)
				local after = dist(a, c, aspect) + (d and dist(b, d, aspect) or 0)
				if after + 1e-9 < before then
					local lo, hi = i, k
					while lo < hi do
						order[lo], order[hi] = order[hi], order[lo]
						lo, hi = lo + 1, hi - 1
					end
					improved = true
				end
				if iterations >= maxIterations then
					break
				end
			end
			if iterations >= maxIterations then
				break
			end
		end
	end
	return order
end

-- The centre of a set of markers (a pull's position on the map).
function Route.Centroid(markers)
	local sx, sy, n = 0, 0, 0
	for _, m in ipairs(markers) do
		sx, sy, n = sx + m.x, sy + m.y, n + 1
	end
	if n == 0 then
		return nil
	end
	return sx / n, sy / n
end

-- Build a route through the pulls of one floor in their planned order, from each pull's centroid. Used by
-- "Route from pulls"; reordering is "Suggest order".
function Route.PointsFromPulls(plan, floor)
	local points = {}
	for _, pull in ipairs(plan.pulls) do
		local onFloor = {}
		for _, m in ipairs(plan.markers) do
			if m.pull == pull.id and m.floor == floor then
				onFloor[#onFloor + 1] = m
			end
		end
		local x, y = Route.Centroid(onFloor)
		if x then
			points[#points + 1] = { x, y, pull = pull.id }
		end
	end
	return points
end
