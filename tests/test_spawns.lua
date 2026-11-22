-- Creature spawn data for the map's "Enemies" layer (Data/Spawns.lua, Data/Spawns/*.lua from tools/gen_spawns.lua),
-- and the /dp scan probe that says whether an in-game spawn recorder could work.
local T = ...
local ns = T.ns
local Spawns = ns.Spawns

local function bundled(id)
	return assert(ns.Bundled.Get("b:" .. id), "bundled plan " .. id)
end

local function dungeonFloor(floor)
	return not ns.Floors.IsOutside(floor)
end

T.case("Spawns: data loads and is available", function()
	T.ok(Spawns.Available(), "available")
	local s = Spawns.Stats()
	T.ok(s.instances >= 30, "instances: " .. s.instances)
	T.ok(s.spawns >= 150, "spawns: " .. s.spawns)
end)

T.case("Spawns: every entry of every recommended plan floor is in range and well formed", function()
	local total = 0
	for _, plan in ipairs(ns.Bundled.All()) do
		for i in ipairs(plan.floors) do
			for _, e in ipairs(Spawns.For(plan, i)) do
				total = total + 1
				T.ok(e.x >= 0 and e.x <= 1 and e.y >= 0 and e.y <= 1, plan.id .. " floor " .. i .. ": coordinates")
				T.ok(Spawns.KINDS[e.kind], "kind " .. tostring(e.kind))
				T.ok(type(e.name) == "string" and e.name ~= "", "name")
				T.ok(e.npcID == nil or (type(e.npcID) == "number" and e.npcID > 0), "npcID")
				T.eq(e.rare == true, e.kind == "rare", "rare flag")
			end
		end
	end
	T.eq(total, Spawns.Stats().spawns, "every loaded spawn is reachable from a recommended plan")
end)

-- The transform: spawns are stored in the plans' own space (the floor's classic dungeon map, 0..1), so each boss marker
-- of a recommended plan must have a boss spawn of the same name at the same spot.
T.case("Spawns: boss spawns sit on the plans' boss markers (transform error 0)", function()
	local checked, worst = 0, 0
	for _, plan in ipairs(ns.Bundled.All()) do
		-- Other tests' own bundled plans are not from Data/Plans and have no spawns.
		local file = io.open("Data/Plans/" .. plan.id:gsub("^b:", "") .. ".lua", "rb")
		if file then
			file:close()
		end
		for _, m in ipairs(file and plan.markers or {}) do
			local floor = plan.floors[m.floor or 1]
			if m.kind == "boss" and floor and dungeonFloor(floor) then
				local best
				for _, e in ipairs(Spawns.For(plan, m.floor or 1)) do
					if e.kind == "boss" and e.name == m.label then
						local d = math.max(math.abs(e.x - m.x), math.abs(e.y - m.y))
						best = best and math.min(best, d) or d
					end
				end
				T.ok(best, plan.id .. ": no spawn for boss " .. tostring(m.label))
				worst = math.max(worst, best)
				checked = checked + 1
			end
		end
	end
	T.ok(checked >= 150, "bosses checked: " .. checked)
	T.ok(worst <= 0.00005, "largest boss offset " .. worst)
	-- Known points, by hand: Edwin VanCleef (Ironclad Cove) and Mutanus (Wailing Caverns).
	local van = bundled("the-deadmines")
	local found
	for _, e in ipairs(Spawns.For(van, 2)) do
		if e.name == "Edwin VanCleef" then
			found = e
		end
	end
	T.ok(found and math.abs(found.x - 0.6076) < 1e-9 and math.abs(found.y - 0.4489) < 1e-9, "VanCleef")
	T.eq(found.npcID, 639, "VanCleef's NPC ID")
	T.ok(found.elite, "a boss is elite")
end)

T.case("Spawns: matched by instance, so a copy or a player's own plan gets the same spawns", function()
	local plan = bundled("the-deadmines")
	local copy = ns.Plan.Duplicate(plan, "Mine")
	T.eq(#Spawns.For(copy, 2), #Spawns.For(plan, 2), "copy")
	local own = { instance = { name = "Deadmines" }, floors = { { name = "The Deadmines" }, { name = "Ironclad Cove" } } }
	T.ok(#Spawns.For(own, 1) > 0, "a plan named without the article")
	local stockade = { instance = { name = "Stormwind Stockade" }, floors = { { name = "The Stockade" } } }
	T.ok(#Spawns.For(stockade, 1) > 0, "an alias of GameFiles")
end)

T.case("Spawns: For() returns an empty array for unknown plans and floors", function()
	T.eq(#Spawns.For(nil, 1), 0, "nil plan")
	T.eq(#Spawns.For({}, 1), 0, "empty plan")
	T.eq(#Spawns.For({ instance = { name = "Nowhere Keep" }, floors = { { name = "A" } } }, 1), 0, "unknown instance")
	local plan = bundled("the-deadmines")
	T.eq(#Spawns.For(plan, 9), 0, "no such floor")
	T.eq(#Spawns.For(plan, "1"), 0, "floor index not a number")
	local outside = { instance = { name = "The Deadmines" }, floors = { { uiMapID = 1436 } } }
	T.eq(#Spawns.For(outside, 1), 0, "the zone outside")
	T.ok(Spawns.For(nil, 1) ~= nil, "never nil")
end)

T.case("Spawns: the generator refuses unclear licences and bad points, deduplicates, caps", function()
	local G = dofile("tools/gen_spawns.lua")
	T.eq(G.InstanceKey("The Deadmines"), "deadmines")
	local stats = { fromPlans = 0, fromFiles = 0, deduped = 0, capped = 0 }
	local inst = {}
	local data = G.DecodeJSON([[{ "schema": 1, "instance": "The Deadmines",
		"sources": [ { "id": "a", "what": "seen in game", "licence": "own" },
		             { "id": "g", "what": "a server database", "licence": "GPL-2.0" } ],
		"spawns": [ { "floor": 1, "x": 0.5, "y": 0.5, "name": "Defias Pirate", "kind": "elite", "npcID": 657, "level": 18, "source": "a" },
		            { "floor": 1, "x": 0.505, "y": 0.5, "name": "Defias Pirate", "kind": "elite", "source": "a" },
		            { "floor": 1, "x": 1.5, "y": 0.5, "name": "Out", "kind": "mob", "source": "a" },
		            { "floor": 1, "x": 0.2, "y": 0.2, "name": "Copied", "kind": "mob", "source": "g" } ] }]])
	local errors = G.FromSpawnFile(inst, data, "test.json", stats)
	T.eq(#errors, 3, "GPL source, its point, and the point out of range: " .. table.concat(errors, "; "))
	T.eq(#inst.deadmines.floors[1], 1, "one kept")
	T.eq(stats.deduped, 1, "stacked spawn merged")
	local text = G.Render(inst.deadmines, "a test")
	T.ok(text:find('{ 0.5, 0.5, "Defias Pirate", "elite", 657, 18, false },', 1, true), "compact row")
	T.ok(text:find("^%-%- GENERATED"), "generated header")
	local many = { schema = 1, instance = "Ragefire Chasm", sources = { { id = "a", what = "x", licence = "own" } }, spawns = {} }
	for i = 1, G.CAP + 5 do
		many.spawns[i] = { floor = 1, x = (i % 50) / 50, y = math.floor(i / 50) / 10, name = "Mob " .. i, kind = "mob", source = "a" }
	end
	T.eq(#G.FromSpawnFile(inst, many, "many.json", stats), 0)
	T.eq(#inst.ragefirechasm.floors[1], G.CAP, "capped")
	T.eq(stats.capped, 5)
end)

T.case("Spawns: /dp scan reports position and target readability", function()
	local secret = {}
	local saved = {
		issecretvalue = rawget(_G, "issecretvalue"),
		IsInInstance = rawget(_G, "IsInInstance"),
		UnitPosition = rawget(_G, "UnitPosition"),
		UnitExists = _G.UnitExists,
		UnitGUID = _G.UnitGUID,
		UnitClassification = rawget(_G, "UnitClassification"),
	}
	_G.issecretvalue = function(x)
		return x == secret
	end
	_G.IsInInstance = function()
		return true, "party"
	end
	_G.UnitPosition = function()
		return nil
	end
	_G.UnitExists = function()
		return true
	end
	_G.UnitGUID = function()
		return secret
	end
	_G.UnitClassification = function()
		return "elite"
	end
	local ok, d = pcall(ns.Diagnostics.Collect)
	for k, f in pairs(saved) do
		_G[k] = f
	end
	T.ok(ok, tostring(d))
	local p = d.position
	T.ok(p, "position part")
	T.ok(p.instance:find("^true party"), p.instance)
	T.eq(p.unitPosition, "nil, nil | nil")
	T.eq(p.targetGUID, "secret")
	T.eq(p.targetClass, "elite")
end)
