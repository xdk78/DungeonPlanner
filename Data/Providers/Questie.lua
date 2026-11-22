-- Provider: Questie's database (QuestieDB, GPL-3.0), through its public data contract: the global LibQuestieDB with
-- RequireContract(4), LibQuestieDB.Enum.zoneIDs (area IDs by name), and the entity readers Quest.GetAllIds,
-- Quest.zoneOrSort, Quest.name, Quest.questLevel, Quest.startedBy, Npc.name and Npc.spawns. Read at runtime only;
-- nothing is copied.
--
-- What it gives: the quests filed under a dungeon's area (zoneOrSort = the dungeon's area ID), with their level and who
-- starts them. Questie has no positions inside dungeons (its instance NPCs carry the "-1, -1" placeholder), so there
-- is nothing for the map. The scan walks every quest ID once per dungeon, in slices of SLICE per frame (C_Timer), only
-- when the Notes section asks for it, and is cached for the session.

local _, ns = ...
local Providers = ns.Providers
local Util = ns.Util

local A = {
	id = "questie",
	addon = "QuestieDB",
	title = "Questie",
	internals = false,
	provides = { "quests" },
}

A.CONTRACT = 4
A.SLICE = 400
A.MAX = 40

local cache = {} -- [areaID] = { done = bool, list = { quest } }

function A.Reset()
	cache = {}
end

function A.Detect()
	local lib = rawget(_G, "LibQuestieDB")
	if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then
		return nil
	end
	local ok, fine = pcall(lib.RequireContract, A.CONTRACT)
	if not ok or not fine then
		return nil
	end
	local q = lib.Quest
	if type(q) ~= "table" or type(q.GetAllIds) ~= "function" or type(q.zoneOrSort) ~= "function"
		or type(q.name) ~= "function" or type(lib.Enum) ~= "table" or type(lib.Enum.zoneIDs) ~= "table" then
		return nil
	end
	return lib
end

-- "The Hall of Thanes" -> "THE_HALL_OF_THANES", "HALL_OF_THANES".
function A.EnumNames(name)
	local words = {}
	for w in tostring(name or ""):gsub("'", ""):gmatch("[%w]+") do
		words[#words + 1] = w:upper()
	end
	local full = table.concat(words, "_")
	local out = { full }
	if words[1] == "THE" then
		table.remove(words, 1)
		out[#out + 1] = table.concat(words, "_")
	else
		out[#out + 1] = "THE_" .. full
	end
	return out
end

function A.AreaFor(lib, plan)
	for _, n in ipairs(A.EnumNames(plan.instance and ns.Instances.CanonicalName(plan))) do
		local id = lib.Enum.zoneIDs[n]
		if Util.IsInteger(id) and id > 0 then
			return id
		end
	end
	return nil
end

local function read(fn, id)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, id)
	return ok and v or nil
end

local function questInfo(lib, id)
	local q = lib.Quest
	local name = read(q.name, id)
	if type(name) ~= "string" then
		return nil
	end
	local level = read(q.questLevel, id)
	local starter
	local by = read(q.startedBy, id)
	local npcs = type(by) == "table" and by[1]
	if type(npcs) == "table" and Util.IsInteger(npcs[1]) and type(lib.Npc) == "table" then
		local n = read(lib.Npc.name, npcs[1])
		starter = type(n) == "string" and n or nil
	end
	return { id = id, name = Util.CleanText(name, 80), level = Util.IsInteger(level) and level > 0 and level or nil,
		starter = starter and Util.CleanText(starter, 64) or nil }
end

-- Quests of a plan's dungeon: list, done. Starts the scan when needed; onDone() runs when it finishes.
function A.Quests(lib, plan, onDone)
	local area = A.AreaFor(lib, plan)
	if not area then
		return {}, true
	end
	local c = cache[area]
	if c then
		return c.list, c.done
	end
	c = { done = false, list = {} }
	cache[area] = c
	local ok, ids = pcall(lib.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then
		c.done = true
		return c.list, true
	end
	local i = 1
	local function slice()
		local stop = math.min(#ids, i + A.SLICE - 1)
		for k = i, stop do
			local id = ids[k]
			if read(lib.Quest.zoneOrSort, id) == area and #c.list < A.MAX then
				local info = questInfo(lib, id)
				if info then
					c.list[#c.list + 1] = info
				end
			end
		end
		i = stop + 1
		if i > #ids then
			c.done = true
			table.sort(c.list, function(a, b)
				if (a.level or 0) ~= (b.level or 0) then
					return (a.level or 0) < (b.level or 0)
				end
				return a.name < b.name
			end)
			if onDone then
				ns.SafeCall(onDone)
			end
		elseif C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				ns.SafeCall(slice)
			end)
		else
			slice()
		end
	end
	slice()
	return c.list, c.done
end

-- Who starts each quest and where (Prep's quest list): { [questID] = { name?, area?, x?, y? } } for the quests Questie
-- knows. x, y are the first spawn of the first starting NPC, 0-100 on that area's map (Questie's area IDs; the zone's
-- name comes from the client's C_Map.GetAreaInfo). A few lookups per quest, on demand; at most A.MAX quests.
function A.Givers(lib, questIDs)
	local out = {}
	local npc = type(lib.Npc) == "table" and lib.Npc or {}
	for i, id in ipairs(type(questIDs) == "table" and questIDs or {}) do
		if i > A.MAX then
			break
		end
		local by = read(lib.Quest.startedBy, id)
		local npcs = type(by) == "table" and by[1]
		local starter = type(npcs) == "table" and npcs[1]
		if Util.IsInteger(starter) then
			local g = {}
			local name = read(npc.name, starter)
			g.name = type(name) == "string" and Util.CleanText(name, 64) or nil
			local spawns = read(npc.spawns, starter)
			if type(spawns) == "table" then
				local best
				for area, list in pairs(spawns) do
					if Util.IsInteger(area) and area > 0 and type(list) == "table" and type(list[1]) == "table"
						and (not best or area < best) then
						best = area
					end
				end
				local p = best and spawns[best][1]
				if p and Util.IsFiniteNumber(p[1]) and Util.IsFiniteNumber(p[2]) and p[1] >= 0 and p[2] >= 0 then
					g.area, g.x, g.y = best, Util.Round(p[1], 1), Util.Round(p[2], 1)
				end
			end
			if g.name or g.area then
				out[id] = g
			end
		end
	end
	return out
end

function A.Counts(lib)
	local n = 0
	for _, c in pairs(cache) do
		n = n + #c.list
	end
	return { contract = tonumber(lib.contractVersion) or A.CONTRACT, quests = n }
end

Providers.Register(A)
