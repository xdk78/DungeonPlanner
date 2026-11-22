-- Times "Snap to corridors" (Data/Corridors.lua, Model/Walk.lua) over every leg of the recommended plans (consecutive
-- stops of a route on a floor with a grid), with the addon loaded against the offline mock client. From the repo root:
--   lua tools/walk_timing.lua [repeats]
-- Prints the median and the longest time of: one leg on a prepared grid; the leg between each floor's two stops that
-- lie farthest apart (any two stops of its routes, not only consecutive ones); preparing a floor (decoding its grid,
-- then the three passes of Walk.Prices) and the longest of those pieces, one frame each in game; and a first click
-- that has to finish preparing its floor as well (preparation plus the slowest of that floor's legs, the farthest pair
-- included). Each time is the mean of `repeats` runs (default 20), because os.clock is coarse on some systems.
-- docs/DATA-SOURCES.md quotes the results.

package.path = "./tests/?.lua;" .. package.path
local print = print -- the mock client replaces it
local mock = require("wowmock")
mock.Install()
local ns = {}
mock.LoadAddon(".", "DungeonPlanner.toc", "DungeonPlanner", ns)

local repeats = tonumber(arg[1]) or 20
local Corridors, Walk = ns.Corridors, ns.Walk
local clock = os.clock

local function ms(fn)
	local t = clock()
	for _ = 1, repeats do
		fn()
	end
	return (clock() - t) * 1000 / repeats
end

local function summary(list)
	table.sort(list)
	local n = #list
	local median = n % 2 == 1 and list[(n + 1) / 2] or (list[n / 2] + list[n / 2 + 1]) / 2
	return string.format("median %.2f ms, at most %.2f ms (%d)", median, list[n], n)
end

-- Every floor with a grid, its recommended legs and its stops: { key, plan, index, legs = { { ax, ay, bx, by } },
-- stops = { { x, y } } }.
local floors, byKey = {}, {}
for _, plan in ipairs(ns.Bundled.All()) do
	for _, route in ipairs(plan.routes) do
		local key = Corridors.KeyFor(plan, route.floor)
		if key then
			local f = byKey[plan.id .. "#" .. route.floor]
			if not f then
				f = { key = key, plan = plan, index = route.floor, legs = {}, stops = {} }
				byKey[plan.id .. "#" .. route.floor] = f
				floors[#floors + 1] = f
			end
			local last
			for _, p in ipairs(route.points) do
				if p.step then
					f.stops[#f.stops + 1] = p
					if last then
						f.legs[#f.legs + 1] = { last[1], last[2], p[1], p[2] }
					end
					last = p
				end
			end
		end
	end
end

-- The two stops of a floor that lie farthest apart, as a leg (nil with fewer than two stops).
local function farthest(stops)
	local best, leg = -1, nil
	for i = 1, #stops do
		for j = i + 1, #stops do
			local a, b = stops[i], stops[j]
			local d = (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2
			if d > best then
				best, leg = d, { a[1], a[2], b[1], b[2] }
			end
		end
	end
	return leg
end

local legTimes, farTimes, prepTimes, pieceTimes, firstTimes = {}, {}, {}, {}, {}
for _, f in ipairs(floors) do
	local d = ns.WalkData[f.key]
	-- Preparing: the decoding, then each pass of Walk.Prices, timed piece by piece on fresh grids.
	local pieces = { 0, 0, 0, 0 }
	for _ = 1, repeats do
		local t = clock()
		local g = Walk.Decode(d[1], d[2], d[3])
		pieces[1] = pieces[1] + clock() - t
		local co = coroutine.create(function()
			Walk.Prices(g, coroutine.yield)
		end)
		for k = 2, 4 do
			t = clock()
			assert(coroutine.resume(co))
			pieces[k] = pieces[k] + clock() - t
		end
	end
	local prep = 0
	for k = 1, 4 do
		pieces[k] = pieces[k] * 1000 / repeats
		prep = prep + pieces[k]
		pieceTimes[#pieceTimes + 1] = pieces[k]
	end
	prepTimes[#prepTimes + 1] = prep
	-- Legs on the prepared grid.
	Corridors.Reset()
	Corridors.Leg(f.plan, f.index, 0.5, 0.5, 0.5, 0.5)
	local function time(leg)
		return ms(function()
			Corridors.Leg(f.plan, f.index, leg[1], leg[2], leg[3], leg[4])
		end)
	end
	local slowest = 0
	for _, leg in ipairs(f.legs) do
		local t = time(leg)
		legTimes[#legTimes + 1] = t
		slowest = math.max(slowest, t)
	end
	local far = farthest(f.stops)
	if far then
		local t = time(far)
		farTimes[#farTimes + 1] = t
		slowest = math.max(slowest, t)
	end
	firstTimes[#firstTimes + 1] = prep + slowest
end

print(string.format("%d floors with a grid, %d legs, %d repeats each, %s", #floors, #legTimes, repeats, _VERSION))
print("one leg, prepared grid:      " .. summary(legTimes))
print("farthest stops of a floor:   " .. summary(farTimes))
print("preparing a floor:           " .. summary(prepTimes))
print("one piece of preparing:      " .. summary(pieceTimes))
print("first click, not prepared:   " .. summary(firstTimes))
