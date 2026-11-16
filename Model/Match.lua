-- Matching plans to what the client's Adventure Guide knows. Recommended plans are written outside the game and carry
-- names (and sometimes a map ID) but no journal IDs, so at display time each plan instance and boss is matched to a
-- journal entry: by journal ID when the plan has one, else by name, else by map ID. The scores below rank candidates;
-- the best one at or above MIN wins. Pure Lua: the journal data comes in as tables (Data/Journal.lua reads it).

local _, ns = ...
local Match = ns:NewModule("Match")

Match.MIN = 40

-- Lower case, no spaces or punctuation; bytes >= 128 (UTF-8 letters) are kept. "The Deadmines" -> "thedeadmines".
function Match.Norm(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:lower():gsub("[^%w\128-\255]", ""))
end

-- The same without a leading English article: "The Hall of Thanes" and "Hall of Thanes" are the same place.
local function stripArticle(s)
	if type(s) ~= "string" then
		return ""
	end
	return Match.Norm((s:gsub("^%s*[Tt][Hh][Ee]%s+", "")))
end
Match.StripArticle = stripArticle

-- The part of a name before a wing or variant: "Dire Maul: East", "Stratholme - Main Gate", "Stratholme (Live)" ->
-- "dire maul", "stratholme". Returns nil when the name has no such part.
function Match.Base(s)
	if type(s) ~= "string" then
		return nil
	end
	local base = s:match("^(.-)%s*[:%(]") or s:match("^(.-)%s+[%-\226]")
	if base and base ~= "" and base ~= s then
		return stripArticle(base)
	end
	return nil
end

local scoreOf -- the scoring below, memoized: the home grid compares every plan with every card on each refresh

local function nameScore(a, b)
	if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then
		return 0
	end
	return scoreOf(a, b)
end

local memo, memoSize = {}, 0
function scoreOf(a, b)
	local key = a .. "\0" .. b
	local hit = memo[key]
	if hit then
		return hit
	end
	local s = Match.ScoreNames(a, b)
	if memoSize > 5000 then
		memo, memoSize = {}, 0
	end
	memo[key], memoSize = s, memoSize + 1
	return s
end

-- The name score without the memo (see nameScore).
function Match.ScoreNames(a, b)
	local na, nb = Match.Norm(a), Match.Norm(b)
	if na == "" or nb == "" then
		return 0
	end
	if na == nb then
		return 90
	end
	local sa, sb = stripArticle(a), stripArticle(b)
	if sa ~= "" and sa == sb then
		return 85
	end
	local ba, bb = Match.Base(a), Match.Base(b)
	-- A wing and the whole instance ("Dire Maul: East" ~ "Dire Maul").
	if (ba and ba == sb) or (bb and bb == sa) then
		return 60
	end
	-- Two variants of one instance ("Stratholme (Live)" ~ "Stratholme - Main Gate").
	if ba and bb and ba == bb and #ba >= 4 then
		return 50
	end
	-- One name inside the other ("Magmatus" ~ "Magmatus the Molten").
	if #sa >= 5 and #sb >= 5 and (sa:find(sb, 1, true) or sb:find(sa, 1, true)) then
		return 45
	end
	return 0
end
Match.NameScore = nameScore

-- How well a plan's instance { ejInstanceID?, uiMapID?, instanceMapID?, name?, kind? } (plus the uiMapIDs of its
-- floors, `floorMaps`) fits a journal entry { ejInstanceID, name, uiMapID, instanceMapID, kind, floorMaps? }.
function Match.InstanceScore(inst, entry, floorMaps)
	if type(inst) ~= "table" or type(entry) ~= "table" then
		return 0
	end
	if inst.ejInstanceID and entry.ejInstanceID then
		return inst.ejInstanceID == entry.ejInstanceID and 100 or 0
	end
	local score = nameScore(inst.name, entry.name)
	if score < 80 and inst.instanceMapID and entry.instanceMapID and inst.instanceMapID == entry.instanceMapID then
		score = 80
	end
	if score < 75 then
		local maps = {}
		if inst.uiMapID then
			maps[#maps + 1] = inst.uiMapID
		end
		for _, id in ipairs(floorMaps or {}) do
			maps[#maps + 1] = id
		end
		for _, id in ipairs(maps) do
			if id == entry.uiMapID then
				score = 75
				break
			end
			for _, f in ipairs(entry.floorMaps or {}) do
				if id == f then
					score = 75
					break
				end
			end
		end
	end
	if score > 0 and inst.kind and entry.kind and inst.kind ~= "other" and inst.kind ~= entry.kind then
		score = score - 30
	end
	return score
end

-- The best journal entry for a plan instance, or nil. Ties keep the journal's order.
function Match.BestInstance(inst, entries, floorMaps)
	local best, bestScore = nil, Match.MIN - 1
	for _, entry in ipairs(entries or {}) do
		local s = Match.InstanceScore(inst, entry, floorMaps)
		if s > bestScore then
			best, bestScore = entry, s
		end
	end
	return best, best and bestScore or 0
end

-- How well a plan boss { ejEncounterID?, dungeonEncounterID?, name? } fits a journal boss { ejEncounterID,
-- dungeonEncounterID, name, creatures = { { name } } }.
function Match.EncounterScore(enc, j)
	if type(enc) ~= "table" or type(j) ~= "table" then
		return 0
	end
	if enc.ejEncounterID and j.ejEncounterID then
		return enc.ejEncounterID == j.ejEncounterID and 100 or 0
	end
	if enc.dungeonEncounterID and j.dungeonEncounterID and enc.dungeonEncounterID == j.dungeonEncounterID then
		return 95
	end
	local score = nameScore(enc.name, j.name)
	for _, c in ipairs(j.creatures or {}) do
		local s = nameScore(enc.name, c.name)
		if s > score then
			score = s
		end
	end
	-- Wing/variant matches mean nothing for boss names.
	if score == 60 or score == 50 then
		score = 0
	end
	return score
end

-- Pair each plan boss with at most one journal boss (best scores first). Returns { [planIndex] = journalBoss }.
function Match.Encounters(planEncounters, journalEncounters)
	local pairsList = {}
	for i, enc in ipairs(planEncounters or {}) do
		for j, jEnc in ipairs(journalEncounters or {}) do
			local s = Match.EncounterScore(enc, jEnc)
			if s >= Match.MIN then
				pairsList[#pairsList + 1] = { i = i, j = j, s = s }
			end
		end
	end
	table.sort(pairsList, function(a, b)
		if a.s ~= b.s then
			return a.s > b.s
		end
		if a.i ~= b.i then
			return a.i < b.i
		end
		return a.j < b.j
	end)
	local out, usedPlan, usedJournal = {}, {}, {}
	for _, p in ipairs(pairsList) do
		if not usedPlan[p.i] and not usedJournal[p.j] then
			usedPlan[p.i], usedJournal[p.j] = true, true
			out[p.i] = journalEncounters[p.j]
		end
	end
	return out
end

-- Which of an instance's floors { { uiMapID, name } } a plan floor { uiMapID?, name? } (the index-th of `count`) is:
-- the same map ID, else the same name, else the same position when both have as many floors, else the first floor
-- when the plan has one. Returns the floor or nil.
function Match.Floor(floor, index, count, floors)
	if type(floors) ~= "table" or #floors == 0 then
		return nil
	end
	floor = floor or {}
	if floor.uiMapID then
		for _, f in ipairs(floors) do
			if f.uiMapID == floor.uiMapID then
				return f
			end
		end
	end
	local best, bestScore = nil, 79
	for _, f in ipairs(floors) do
		local s = nameScore(floor.name, f.name)
		if s > bestScore then
			best, bestScore = f, s
		end
	end
	if best then
		return best
	end
	if count == #floors then
		return floors[index]
	end
	if count == 1 then
		return floors[1]
	end
	return floors[index]
end
