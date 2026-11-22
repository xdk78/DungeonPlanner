-- Snap to corridors, the model and data: Model/Walk.lua (run lengths, the path search, its node cap, the prices'
-- passes) on synthetic grids, Data/WalkData.lua (every grid decodes and names a picture the addon draws) and
-- Data/Corridors.lua (which floor gets which grid; legs between the recommended plans' stops stay on walkable cells;
-- a floor prepared over frames, or finished by the first leg that needs it).
local T = ...
local ns, mock = T.ns, T.mock
local Walk = ns.Walk

-- A grid from rows of text: "#" blocked, "r" rough (drawn, not floor), anything else floor.
local function grid(rows)
	local h, w = #rows, #rows[1]
	local function at(x, y)
		return rows[y + 1]:sub(x + 1, x + 1)
	end
	return assert(Walk.Decode(w, h, Walk.Encode(w, h, function(x, y)
		local c = at(x, y)
		return c == "r" and 2 or c ~= "#" and 1 or 0
	end)))
end

-- Every piece of a,bends..,b (normalized), the first and last too, crosses floor or rough cells only, never a blocked
-- one; except that a stop off the floor may reach it across the blocked cells within 2 cells of it (Walk.Path's snap).
local function walkable(g, ax, ay, bends, bx, by)
	local pts = { { ax, ay } }
	for _, b in ipairs(bends) do
		pts[#pts + 1] = b
	end
	pts[#pts + 1] = { bx, by }
	local allow = setmetatable({}, { __index = g.rough })
	for _, p in ipairs({ pts[1], pts[#pts] }) do
		local cx, cy = math.floor(p[1] * g.w), math.floor(p[2] * g.h)
		if not Walk.Open(g, cx, cy) then
			for y = math.max(0, cy - 2), math.min(g.h - 1, cy + 2) do
				for x = math.max(0, cx - 2), math.min(g.w - 1, cx + 2) do
					allow[(y + 1) * g.stride + x + 2] = true
				end
			end
		end
	end
	for i = 2, #pts do
		local p, q = pts[i - 1], pts[i]
		if not Walk.Clear(g, p[1] * g.w, p[2] * g.h, q[1] * g.w, q[2] * g.h, allow) then
			return false, i
		end
	end
	return true
end

T.case("Walk: run lengths round-trip; a wrong length or character is refused", function()
	local rows = { "#...#", "..#..", "#####" }
	local g = grid(rows)
	T.eq(g.w, 5)
	T.eq(g.h, 3)
	T.eq(g.open, 7)
	for y = 0, 2 do
		for x = 0, 4 do
			T.eq(Walk.Open(g, x, y) and true or false, rows[y + 1]:sub(x + 1, x + 1) ~= "#", x .. "," .. y)
		end
	end
	T.ok(not Walk.Open(g, -1, 0) and not Walk.Open(g, 5, 0), "outside the grid is blocked")
	-- Long runs take several characters (base 32 digits).
	local runs = Walk.Encode(100, 80, function(x)
		return x < 50
	end)
	local big = assert(Walk.Decode(100, 80, runs))
	T.eq(big.open, 4000)
	T.eq(select(2, Walk.Decode(5, 3, Walk.Encode(5, 3, function() return true end) .. "1")), "length")
	T.eq(select(2, Walk.Decode(5, 3, "!")), "character")
	T.eq(select(2, Walk.Decode(5, 4, Walk.Encode(5, 3, function() return true end))), "length")
	T.eq(select(2, Walk.Decode(1, 3, "3")), "size")
	T.eq(select(2, Walk.Decode(300, 300, "")), "size", "a grid larger than MAX_CELLS")
end)

T.case("Walk: a path goes round the wall through the corridor; a clear line has no bends", function()
	local g = grid({
		"..........",
		"..........",
		"########..",
		"..........",
		"..........",
	})
	-- From the top left to the bottom left: round the end of the wall on the right.
	local ax, ay, bx, by = 0.05, 0.1, 0.05, 0.9
	local bends, why, st = Walk.Path(g, ax, ay, bx, by)
	T.ok(bends, "found: " .. tostring(why))
	T.ok(#bends >= 1 and #bends <= 4, "a few bends, not every cell: " .. #bends)
	T.ok(walkable(g, ax, ay, bends, bx, by), "every piece on walkable cells")
	T.ok(st.expanded > 0)
	local passesGap = false
	for _, b in ipairs(bends) do
		if b[1] >= 0.75 then
			passesGap = true
		end
	end
	T.ok(passesGap, "through the gap on the right")
	local straight = assert(Walk.Path(g, 0.05, 0.1, 0.95, 0.1))
	T.eq(#straight, 0, "same row, nothing in the way: straight")
	-- A stop just off the floor (in the wall) still gets a path from the nearest walkable cell.
	local off, whyOff = Walk.Path(g, 0.3, 0.5, 0.05, 0.9)
	T.ok(off ~= nil, "found: " .. tostring(whyOff))
	T.ok(off and walkable(g, 0.3, 0.5, off, 0.05, 0.9), "from the wall onto the floor, then on walkable cells")
end)

T.case("Walk: a dead end, an unreachable stop and a stop far off the floor", function()
	local g = grid({
		"....#.....",
		"..#.#.###.",
		"..#.#.#...",
		"..###.#.##",
		"......#...",
	})
	-- Into the dead end at the top of the middle column and out again: the only way is round the bottom.
	local bends = assert(Walk.Path(g, 0.35, 0.1, 0.55, 0.1))
	T.ok(walkable(g, 0.35, 0.1, bends, 0.55, 0.1), "round the wall, on walkable cells")
	-- The right-hand pocket is closed off.
	local closed = grid({
		"......#...",
		"......#...",
		"......#...",
	})
	local none, why = Walk.Path(closed, 0.1, 0.5, 0.9, 0.5)
	T.eq(none, nil)
	T.eq(why, "none")
	local far, why2 = Walk.Path(grid({ "..........", "##########", "##########", "##########", "##########" }),
		0.5, 0.1, 0.5, 0.95)
	T.eq(far, nil)
	T.eq(why2, "off", "the end lies more than 2 cells from any floor")
	-- A door drawn across the way (rough): crossed where the floor does not connect, at its narrowest.
	local door = grid({
		"......r...",
		"......r...",
		"......r...",
		"......#...",
	})
	local through, why3, st = Walk.Path(door, 0.1, 0.4, 0.9, 0.4)
	T.ok(through, tostring(why3))
	T.ok(st.rough >= 1 and st.rough <= 2, "crosses the door once: " .. st.rough)
	T.ok(walkable(door, 0.1, 0.4, through, 0.9, 0.4), "never over the blocked cell")
	-- With a way round on the floor, the door is not crossed.
	local round = grid({
		"......r.....",
		"......r.....",
		"............",
		"............",
		"............",
		"............",
		"............",
		"............",
	})
	local _, _, st2 = Walk.Path(round, 0.1, 0.07, 0.9, 0.07)
	T.eq(st2.rough, 0, "round by the floor")
end)

T.case("Walk: the node cap stops a search; the prices yield between their passes", function()
	-- A serpentine: rows of wall with a gap at alternate ends; the way from top to bottom visits nearly every cell.
	local rows = {}
	for y = 0, 39 do
		local row = {}
		for x = 0, 59 do
			local wall = y % 4 == 2 and ((y % 8 == 2 and x < 57) or (y % 8 == 6 and x > 2))
			row[#row + 1] = wall and "#" or "."
		end
		rows[#rows + 1] = table.concat(row)
	end
	local g = grid(rows)
	local bends, why, st = Walk.Path(g, 0.01, 0.01, 0.01, 0.99, { maxNodes = 200 })
	T.eq(bends, nil)
	T.eq(why, "limit")
	T.eq(st.expanded, 200, "stopped at the cap")
	-- Without the cap, the whole serpentine in one call.
	local found = Walk.Path(g, 0.01, 0.01, 0.01, 0.99)
	T.ok(found and #found >= 10, "the whole serpentine")
	T.ok(walkable(g, 0.01, 0.01, found, 0.01, 0.99))
	-- A grid's one-time prices: three passes with a yield between them, then kept on the grid.
	local fresh = grid(rows)
	local co = coroutine.create(function()
		return Walk.Prices(fresh, coroutine.yield)
	end)
	local yields = 0
	repeat
		local ok, err = coroutine.resume(co)
		T.ok(ok, tostring(err))
		if coroutine.status(co) == "suspended" then
			yields = yields + 1
		end
	until coroutine.status(co) == "dead"
	T.eq(yields, 2, "between the passes")
	T.ok(fresh.price and fresh.g, "the prices and the search's arrays")
	T.eq(Walk.Prices(fresh, error), fresh.price, "kept: no second computation")
end)

T.case("Walk data: every grid decodes and names a picture the addon draws", function()
	local count, chars = 0, 0
	local tiles, reyes = {}, {}
	for _, spec in pairs(ns.GameFiles.INSTANCES) do
		for _, base in ipairs(spec.tiles or {}) do
			tiles[base] = true
		end
	end
	for _, f in ipairs(ns.ReyesMaps.All()) do
		reyes[f.file] = true
	end
	for key, d in pairs(ns.WalkData) do
		count = count + 1
		chars = chars + #d[3]
		local g, err = Walk.Decode(d[1], d[2], d[3])
		T.ok(g, key .. ": " .. tostring(err))
		T.ok(g.open > 50, key .. ": some floor")
		local kind, rest = key:match("^(%a):(.+)$")
		if kind == "t" then
			T.ok(tiles[rest], key .. ": a tile name of Data/GameFiles.lua")
		elseif kind == "r" then
			T.ok(reyes[rest], key .. ": a bundled map")
		else
			local inst, floor = rest:match("^(.+):(%d+)$")
			T.eq(kind, "m", key)
			T.ok(ns.MinimapArtData[inst] and ns.MinimapArtData[inst][tonumber(floor)], key .. ": a minimap floor")
		end
	end
	T.ok(count >= 60, "grids: " .. count)
	T.ok(chars < 150 * 1024, "small: " .. chars .. " characters")
end)

-- The recommended plans' stops, floor by floor, through the grids: every found leg stays on walkable cells.
T.case("Corridors: legs between the recommended plans' stops stay walkable", function()
	local Corridors = ns.Corridors
	local legs, found, floors = 0, 0, 0
	for _, plan in ipairs(ns.Bundled.All()) do
		for _, route in ipairs(plan.routes) do
			local key, align = Corridors.KeyFor(plan, route.floor)
			local g = key and Corridors.Grid(key)
			if g then
				floors = floors + 1
				local stops = {}
				for _, p in ipairs(route.points) do
					if p.step then
						stops[#stops + 1] = p
					end
				end
				for i = 2, #stops do
					local a, b = stops[i - 1], stops[i]
					legs = legs + 1
					local bends = Corridors.Leg(plan, route.floor, a[1], a[2], b[1], b[2])
					if bends then
						found = found + 1
						local gb = {}
						for k, p in ipairs(bends) do
							gb[k] = { ns.MinimapArt.ToMap(align, p[1], p[2]) }
						end
						local ax, ay = ns.MinimapArt.ToMap(align, a[1], a[2])
						local bx, by = ns.MinimapArt.ToMap(align, b[1], b[2])
						local ok, at = walkable(g, ax, ay, gb, bx, by)
						T.ok(ok, string.format("%s floor %d leg %d: piece %s crosses a wall", plan.id, route.floor, i,
							tostring(at)))
					end
				end
			end
		end
	end
	T.ok(floors >= 40, "floors with a grid and a route: " .. floors)
	T.ok(legs >= 100, "legs: " .. legs)
	T.ok(found >= legs * 0.9, string.format("found %d of %d", found, legs))
	T.ok(Corridors.stats.maxExpanded <= Walk.MAX_NODES, "every search within the node cap")
end)

-- The first and last stops of the Deadmines' floor-1 route.
local function deadminesLeg()
	local plan = ns.Bundled.Get("b:the-deadmines")
	local stops = {}
	for _, p in ipairs(plan.routes[1].points) do
		if p.step then
			stops[#stops + 1] = p
		end
	end
	return plan, stops[1], stops[#stops]
end

T.case("Corridors: a floor is prepared over a few frames, then nothing runs", function()
	local Corridors = ns.Corridors
	Corridors.Reset()
	local plan = deadminesLeg()
	local key = Corridors.KeyFor(plan, 1)
	local steps = Corridors.stats.steps
	Corridors.Prepare(plan, 1)
	T.eq(Corridors.Preparing(), key, "started")
	T.eq(Corridors.stats.steps, steps, "nothing in the calling frame")
	local frames = 0
	while Corridors.Preparing() and frames < 20 do
		mock.Advance(0.016)
		frames = frames + 1
	end
	T.eq(Corridors.Preparing(), nil, "done")
	T.ok(Corridors.Ready(key), "decoded with its prices")
	T.eq(Corridors.stats.steps - steps, 4, "decoding and the three passes, one frame each")
	T.eq(frames, 4)
	local done = Corridors.stats.steps
	for _ = 1, 10 do
		mock.Advance(0.016)
	end
	T.eq(Corridors.stats.steps, done, "no step runs once it is done")
	Corridors.Prepare(plan, 1)
	T.eq(Corridors.Preparing(), nil, "a prepared floor is not prepared again")
	-- A floor without a grid has nothing to prepare.
	Corridors.Prepare(ns.Bundled.Get("b:kroldok-stronghold"), 1)
	T.eq(Corridors.Preparing(), nil, "no grid, nothing to do")
end)

T.case("Corridors: a leg before its floor is prepared finishes the preparation in the call", function()
	local Corridors = ns.Corridors
	Corridors.Reset()
	local plan, a, b = deadminesLeg()
	local key = Corridors.KeyFor(plan, 1)
	Corridors.Prepare(plan, 1)
	mock.Advance(0.016) -- one piece done: the grid is decoded, its prices are not
	T.eq(Corridors.Preparing(), key)
	T.ok(not Corridors.Ready(key), "still preparing")
	local bends = Corridors.Leg(plan, 1, a[1], a[2], b[1], b[2])
	T.ok(bends and #bends > 0, "the leg found at once")
	T.eq(Corridors.Preparing(), nil, "the preparation was finished by the leg")
	T.ok(Corridors.Ready(key))
	local steps = Corridors.stats.steps
	mock.Advance(0.016)
	T.eq(Corridors.stats.steps, steps, "the frame that was waiting has nothing left to do")
	-- Not started at all: the leg prepares the floor itself.
	Corridors.Reset()
	local again = Corridors.Leg(plan, 1, a[1], a[2], b[1], b[2])
	T.eq(#again, #bends, "the same leg")
	T.ok(Corridors.Ready(key))
	-- Another floor asked for while one is being prepared: that one is dropped, the new one prepared.
	Corridors.Reset()
	local hall = ns.Bundled.Get("b:hall-of-thanes")
	Corridors.Prepare(plan, 1)
	mock.Advance(0.016)
	Corridors.Prepare(hall, 1)
	T.eq(Corridors.Preparing(), Corridors.KeyFor(hall, 1), "the new floor")
	for _ = 1, 10 do
		mock.Advance(0.016)
	end
	T.eq(Corridors.Preparing(), nil)
	T.ok(Corridors.Ready(Corridors.KeyFor(hall, 1)), "the new floor prepared")
	T.ok(not Corridors.Ready(key), "the dropped one left as it was")
	T.ok(Corridors.Leg(plan, 1, a[1], a[2], b[1], b[2]), "and prepared when it is asked for")
end)

T.case("Corridors: which floors have a grid; /dp debug's summary", function()
	local Corridors = ns.Corridors
	local plan = ns.Bundled.Get("b:the-deadmines")
	T.eq(Corridors.KeyFor(plan, 1), "t:TheDeadmines\\TheDeadmines1_")
	local hall = ns.Bundled.Get("b:hall-of-thanes")
	T.eq(Corridors.KeyFor(hall, 1), "r:HallOfThanes")
	local scholo = ns.Bundled.Get("b:scholomance")
	T.eq(Corridors.KeyFor(scholo, 1), "m:scholomance:1")
	T.ok(select(2, Corridors.KeyFor(scholo, 1)) ~= nil, "through the minimap floor's transform")
	-- An open outdoor map (Krol'dok) has none: its legs stay straight.
	local kroldok = ns.Bundled.Get("b:kroldok-stronghold")
	T.eq(Corridors.KeyFor(kroldok, 1), nil)
	local s = Corridors.Summary()
	T.ok(s.floors >= 60 and s.grids >= 60, "floors " .. s.floors .. ", grids " .. s.grids)
	local named = false
	for _, f in ipairs(s.without) do
		named = named or f:find("Krol", 1, true) ~= nil
	end
	T.ok(named, "the floors without are named")
	-- The decoded grids are bounded.
	for _, k in ipairs({ "t:TheDeadmines\\TheDeadmines1_", "t:TheDeadmines\\TheDeadmines2_", "r:HallOfThanes",
		"m:scholomance:1", "m:scholomance:2", "t:Ragefire\\Ragefire1_" }) do
		T.ok(Corridors.Grid(k), k)
	end
	T.ok(Corridors.Grid("t:TheDeadmines\\TheDeadmines1_"), "decoded again after being dropped")
	local printed = {}
	local realPrint = _G.print
	_G.print = function(s2)
		printed[#printed + 1] = s2
	end
	ns.Slash.MapSources()
	_G.print = realPrint
	T.ok(table.concat(printed, "\n"):find("Corridor data", 1, true), "/dp debug names the corridor data")
end)
