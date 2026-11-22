-- Where enemies stand: creature spawn positions per plan floor, drawn as the map's "Enemies" layer
-- (UI/MapSpawns.lua).
--
--   Spawns.Available() -> true when spawn data exists for this client at all.
--   Spawns.For(plan, floorIndex) -> an array of
--     { x, y, name, npcID?, level?, elite?, rare?, kind = "mob" | "elite" | "rare" | "boss" | "npc" }
--     with x and y normalized 0..1 on that floor's map (the same space as the plan's markers). Never nil; an empty
--     array when nothing is known for that floor. The entries are shared: read them, never change them.
--
-- The data is generated (tools/gen_spawns.lua -> Data/Spawns/<instance>.lua, data-src/spawns/README.md says what it
-- holds and where it comes from). Each data file calls Spawns.Add with compact rows; a floor's rows become entry
-- tables the first time that floor is asked for, and stay cached.
--
-- Matching: by instance, not by plan, so a player's own plan or a copy of a recommended one gets the same spawns. The
-- instance is found by name the way Data/GameFiles.lua finds the floor's map (GameFiles.Key, aliases included), and a
-- floor by its position, as the map tiles are: floor i of a plan is the instance's i-th dungeon map. The zone outside
-- (Floors.IsOutside: an unnamed floor on an entrance zone's map) gets none.
-- Pure Lua apart from GameFiles' name keys: no game API.

local _, ns = ...
local Spawns = ns:NewModule("Spawns")

local EMPTY = setmetatable({}, { __newindex = function() end })

Spawns.KINDS = { mob = true, elite = true, rare = true, boss = true, npc = true }
Spawns.MAX_PER_FLOOR = 400 -- the generator caps below this; Add drops anything past it

local raw = {} -- [instance key] = { [floor] = { row, ... } } as the data files give them
local built = {} -- [instance key] = { [floor] = { entry, ... } }
local count = { instances = 0, floors = 0, spawns = 0 }

-- A data file's rows for one instance: { [floorIndex] = { { x, y, name, kind, npcID?, level? }, ... } }.
function Spawns.Add(key, floors)
	if type(key) ~= "string" or key == "" or type(floors) ~= "table" or raw[key] then
		return false
	end
	raw[key] = floors
	count.instances = count.instances + 1
	for _, rows in pairs(floors) do
		count.floors = count.floors + 1
		count.spawns = count.spawns + math.min(#rows, Spawns.MAX_PER_FLOOR)
	end
	return true
end

function Spawns.Available()
	return count.spawns > 0
end

-- { instances, floors, spawns } loaded (for /dp debug and tests).
function Spawns.Stats()
	return { instances = count.instances, floors = count.floors, spawns = count.spawns }
end

local function entry(row)
	local x, y, name, kind = row[1], row[2], row[3], row[4]
	if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 or type(name) ~= "string"
		or not Spawns.KINDS[kind] then
		return nil
	end
	local npcID, level = row[5], row[6]
	return {
		x = x,
		y = y,
		name = name,
		kind = kind,
		npcID = type(npcID) == "number" and npcID > 0 and npcID or nil,
		level = type(level) == "number" and level > 0 and level or nil,
		elite = (kind == "elite" or kind == "boss") or nil,
		rare = kind == "rare" or nil,
	}
end

local function floorEntries(key, index)
	local cache = built[key]
	if not cache then
		cache = {}
		built[key] = cache
	end
	if cache[index] == nil then
		local rows = raw[key][index]
		local out = {}
		if type(rows) == "table" then
			for i = 1, math.min(#rows, Spawns.MAX_PER_FLOOR) do
				local e = type(rows[i]) == "table" and entry(rows[i])
				if e then
					out[#out + 1] = e
				end
			end
		end
		cache[index] = out
	end
	return cache[index]
end

-- The data key of a plan's instance (nil when there is no data for it).
function Spawns.KeyFor(plan)
	local GameFiles = ns.GameFiles
	local name = type(plan) == "table" and type(plan.instance) == "table" and ns.Instances.CanonicalName(plan)
	local key = GameFiles and type(name) == "string" and GameFiles.Key(name)
	if not key then
		return nil
	end
	if raw[key] then
		return key
	end
	local spec = GameFiles.INSTANCES and GameFiles.INSTANCES[key]
	local alias = type(spec) == "table" and spec.alias
	return alias and raw[alias] and alias or nil
end

function Spawns.For(plan, floorIndex)
	if type(floorIndex) ~= "number" then
		return EMPTY
	end
	local key = Spawns.KeyFor(plan)
	local floor = key and type(plan.floors) == "table" and plan.floors[floorIndex]
	if type(floor) ~= "table" then
		return EMPTY
	end
	if ns.Floors.IsOutside(floor) then
		return EMPTY -- the zone outside, not a dungeon floor
	end
	return floorEntries(key, floorIndex)
end
