-- The client's Adventure Guide (Encounter Journal), read at runtime and matched to plans. Dungeon Planner ships no
-- journal IDs: recommended plans carry names (and sometimes a map ID), so this module finds the journal entry for each
-- plan instance and boss (Model/Match.lua: journal ID, else name, else map ID) and reads from it the instance's
-- pictures, its bosses with their portraits, its map and floors, and the guide's boss pins.
--
-- API return orders. Verified = an installed WoW: Forever addon reads the value on this client; the rest follows
-- Retail 12.1.5 and is guarded (docs/COMPATIBILITY.md), and `/dp scan` saves what the client really returns.
--   EJ_GetNumTiers() -> n; EJ_SelectTier(i); EJ_GetCurrentTier() -> i                                  verified
--   EJ_GetInstanceByIndex(i, isRaid) -> instanceID, name (verified), description, bgImage, buttonImage1, loreImage,
--     buttonImage2, dungeonAreaMapID, link, shouldDisplayDifficulty, mapID                         rest inferred
--   EJ_GetInstanceInfo(id) -> name, description, bgImage, buttonImage1, loreImage, buttonImage2, dungeonAreaMapID,
--     link, shouldDisplayDifficulty, mapID                                                                inferred
--   EJ_SelectInstance(id); EJ_GetEncounterInfoByIndex(i[, instanceID]) -> name, description, journalEncounterID
--     (verified), rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID               rest inferred
--   EJ_GetCreatureInfo(i, journalEncounterID) -> id, name, description, displayInfo, iconImage, uiModelSceneID verified
-- Scanning moves the journal's selection, so it never runs while the Blizzard journal is open, restores the selected
-- tier, and runs on demand only (the first card, page or map that needs it). Everything is cached for the session.

local _, ns = ...
local Journal = ns:NewModule("Journal")
local Util, Match = ns.Util, ns.Match

local MAX_TIERS, MAX_INSTANCES, MAX_ENCOUNTERS, MAX_CREATURES = 40, 200, 40, 8

local cache -- { tiers = { { name, instances } }, list = { entry }, byKey = {}, complete, tried = n }
local encounterCache = {} -- [ejInstanceID] = { boss, ... }
local resolveCache = {} -- [signature] = entry or false
local byTable = setmetatable({}, { __mode = "k" }) -- [instance table] = last answer
local planCache = setmetatable({}, { __mode = "k" }) -- [plan] = { sig, byIndex }
Journal.lastScan = nil -- what the last scan saw: { tiers, instances, errors }, for /dp debug

local function journalOpen()
	local frame = rawget(_G, "EncounterJournal")
	return frame and frame.IsShown and frame:IsShown() and true or false
end
Journal.IsBlizzardJournalOpen = journalOpen

function Journal.Available()
	return type(EJ_GetInstanceByIndex) == "function" and type(EJ_SelectInstance) == "function"
end

local function int(v)
	v = Util.Plain(v)
	return Util.IsInteger(v) and v > 0 and v or nil
end

-- A picture: a file ID (> 0) or a path; anything else is "none".
local function file(v)
	v = Util.Plain(v)
	if (type(v) == "number" and v > 0) or (type(v) == "string" and v ~= "") then
		return v
	end
	return nil
end
Journal.File = file

local function str(v)
	v = Util.Plain(v)
	return type(v) == "string" and v or nil
end

-- Scan -------------------------------------------------------------------------------------------------------------------

local function currentTier()
	if type(EJ_GetCurrentTier) == "function" then
		local ok, t = pcall(EJ_GetCurrentTier)
		if ok then
			return int(t)
		end
	end
	return nil
end

local function selectTier(tier)
	if tier and type(EJ_SelectTier) == "function" then
		pcall(EJ_SelectTier, tier)
	end
end

-- The number of tiers, and what EJ_GetNumTiers returned (for /dp scan). WoW: Forever returns 0: its client has no
-- journal tables (docs/COMPATIBILITY.md section 9). Without a count, one pass over the selected tier is still made.
local function numTiers()
	if type(EJ_GetNumTiers) == "function" then
		local ok, n = pcall(EJ_GetNumTiers)
		local raw = ok and Util.Plain(n) or nil
		n = ok and int(n) or nil
		if n then
			return math.min(n, MAX_TIERS), raw
		end
		return nil, raw
	end
	return nil, nil
end

local function scan()
	local result = { tiers = {}, list = {}, byKey = {} }
	local info = { tiers = 0, instances = 0, errors = {} }
	if not Journal.Available() then
		info.errors[#info.errors + 1] = "no journal API"
		return result, false, info
	end
	if journalOpen() then
		info.errors[#info.errors + 1] = "the Adventure Guide is open"
		return result, false, info
	end
	local previous = currentTier()
	local tiers, raw = numTiers()
	info.tiers = tiers or 0
	info.rawTiers = raw
	for tier = 1, tiers or 1 do
		if tiers then
			selectTier(tier)
		end
		local tierName
		if type(EJ_GetTierInfo) == "function" then
			local ok, name = pcall(EJ_GetTierInfo, tier)
			tierName = ok and str(name) or nil
		end
		local tierEntry = { name = tierName or ("Tier " .. tier), instances = {} }
		for _, isRaid in ipairs({ false, true }) do
			for index = 1, MAX_INSTANCES do
				local r = { pcall(EJ_GetInstanceByIndex, index, isRaid) }
				if not r[1] then
					info.errors[#info.errors + 1] = "EJ_GetInstanceByIndex: " .. tostring(r[2])
					break
				end
				local id, name = int(r[2]), str(r[3])
				if not id then
					if index == 1 and r[2] ~= nil and Util.IsSecret(r[2]) then
						info.errors[#info.errors + 1] = "secret instance IDs"
					end
					break
				end
				local key = "ej:" .. id
				if name and name ~= "" and not result.byKey[key] then
					local entry = {
						key = key,
						name = name,
						kind = isRaid and "raid" or "dungeon",
						ejInstanceID = id,
						uiMapID = int(r[9]),
						instanceMapID = int(r[12]),
						art = { background = file(r[5]), button = file(r[6]), lore = file(r[7]), button2 = file(r[8]) },
						tier = tier,
						tierName = tierEntry.name,
					}
					tierEntry.instances[#tierEntry.instances + 1] = entry
					result.list[#result.list + 1] = entry
					result.byKey[key] = entry
					info.instances = info.instances + 1
				end
			end
		end
		if #tierEntry.instances > 0 then
			result.tiers[#result.tiers + 1] = tierEntry
		end
	end
	selectTier(previous)
	return result, true, info
end

-- Fill what the index call did not return from EJ_GetInstanceInfo (inferred; guarded).
local function complete(entry)
	if entry.infoRead or type(EJ_GetInstanceInfo) ~= "function" then
		return entry
	end
	entry.infoRead = true
	local ok, name, _, bg, button1, lore, button2, areaMap, _, _, mapID = pcall(EJ_GetInstanceInfo, entry.ejInstanceID)
	if ok and str(name) then
		local art = entry.art
		art.background = art.background or file(bg)
		art.button = art.button or file(button1)
		art.lore = art.lore or file(lore)
		art.button2 = art.button2 or file(button2)
		entry.uiMapID = entry.uiMapID or int(areaMap)
		entry.instanceMapID = entry.instanceMapID or int(mapID)
	end
	return entry
end

-- Every journal instance. A scan that could not run, or found nothing, is retried on a later call (at most a few
-- times per session), so opening the window before the journal is ready does not leave it empty until /reload.
function Journal.GetAll()
	if not cache or (not cache.complete or #cache.list == 0) and (cache.tried or 0) < 3 then
		local tried = cache and cache.tried or 0
		local result, done, info = scan()
		result.complete = done
		result.tried = tried + 1
		cache = result
		Journal.lastScan = info
		Journal.epoch = (Journal.epoch or 0) + 1
		resolveCache = {}
		byTable = setmetatable({}, { __mode = "k" })
	end
	return cache
end

-- Does the client's journal list any instance? (false on WoW: Forever.)
function Journal.HasData()
	return #Journal.GetAll().list > 0
end

function Journal.Get(key)
	local entry = Journal.GetAll().byKey[key]
	return entry and complete(entry) or nil
end

function Journal.ByInstanceID(ejInstanceID)
	return ejInstanceID and Journal.Get("ej:" .. ejInstanceID) or nil
end

-- Bosses ------------------------------------------------------------------------------------------------------------------

-- Bosses of a journal instance in journal order: { name, ejEncounterID, dungeonEncounterID, creatures = { { name,
-- displayInfo, icon } }, displayInfo, icon } (the first creature's portrait is the boss's).
function Journal.Encounters(ejInstanceID)
	if not ejInstanceID then
		return {}
	end
	if encounterCache[ejInstanceID] then
		return encounterCache[ejInstanceID]
	end
	local list = {}
	if not Journal.Available() or type(EJ_GetEncounterInfoByIndex) ~= "function" or journalOpen() then
		return list
	end
	pcall(EJ_SelectInstance, ejInstanceID)
	for index = 1, MAX_ENCOUNTERS do
		-- Some clients want the instance ID here, some read the selected one: try both.
		local ok, name, _, ejID, _, _, _, dungeonID = pcall(EJ_GetEncounterInfoByIndex, index, ejInstanceID)
		if not ok or not str(name) then
			ok, name, _, ejID, _, _, _, dungeonID = pcall(EJ_GetEncounterInfoByIndex, index)
		end
		name = ok and str(name) or nil
		if not name then
			break
		end
		local boss = { name = name, ejEncounterID = int(ejID), dungeonEncounterID = int(dungeonID), creatures = {} }
		if boss.ejEncounterID and type(EJ_GetCreatureInfo) == "function" then
			for c = 1, MAX_CREATURES do
				local okC, _, cName, _, display, icon = pcall(EJ_GetCreatureInfo, c, boss.ejEncounterID)
				cName = okC and str(cName) or nil
				if not cName then
					break
				end
				boss.creatures[#boss.creatures + 1] = { name = cName, displayInfo = int(display), icon = file(icon) }
			end
		end
		local first = boss.creatures[1]
		boss.displayInfo = first and first.displayInfo or nil
		boss.icon = first and first.icon or nil
		list[#list + 1] = boss
	end
	encounterCache[ejInstanceID] = list
	return list
end

-- Matching ------------------------------------------------------------------------------------------------------------------

local function floorMapsOf(entry)
	if entry.floorMaps == nil then
		entry.floorMaps = {}
		if entry.uiMapID then
			for _, f in ipairs(ns.Instances.Floors(entry.uiMapID)) do
				if f.uiMapID then
					entry.floorMaps[#entry.floorMaps + 1] = f.uiMapID
				end
			end
		end
	end
	return entry.floorMaps
end

-- The journal entry for a plan instance or home entry { ejInstanceID?, uiMapID?, instanceMapID?, name, kind } (and the
-- uiMapIDs of the plan's floors, optional). Returns entry, score.
function Journal.ResolveInstance(inst, floorMaps)
	if type(inst) ~= "table" then
		return nil, 0
	end
	if inst.ejInstanceID then
		local direct = Journal.ByInstanceID(inst.ejInstanceID)
		if direct then
			return direct, 100
		end
	end
	local data = Journal.GetAll() -- (a rescan empties the caches below)
	-- The same table asked again (the home grid asks per card and per plan on every refresh): no string work.
	local plain = not floorMaps or #floorMaps == 0
	local quick = plain and byTable[inst]
	if quick and quick.name == inst.name and quick.ej == inst.ejInstanceID and quick.map == inst.uiMapID then
		return quick.entry, quick.score
	end
	local sig = table.concat({ tostring(inst.ejInstanceID), tostring(inst.uiMapID), tostring(inst.instanceMapID),
		Match.Norm(inst.name), tostring(inst.kind), table.concat(floorMaps or {}, ",") }, "|")
	local hit = resolveCache[sig]
	if hit ~= nil then
		if plain then
			byTable[inst] = { name = inst.name, ej = inst.ejInstanceID, map = inst.uiMapID, entry = hit and hit.entry or nil,
				score = hit and hit.score or 0 }
		end
		return hit and hit.entry or nil, hit and hit.score or 0
	end
	local wantsMaps = inst.uiMapID or inst.instanceMapID or (floorMaps and #floorMaps > 0)
	if wantsMaps then
		for _, entry in ipairs(data.list) do
			complete(entry)
			floorMapsOf(entry)
		end
	end
	local entry, score = Match.BestInstance(inst, data.list, floorMaps)
	if entry then
		complete(entry)
	end
	resolveCache[sig] = entry and { entry = entry, score = score } or false
	if plain then
		byTable[inst] = { name = inst.name, ej = inst.ejInstanceID, map = inst.uiMapID, entry = entry, score = score or 0 }
	end
	return entry, score
end

local function planFloorMaps(plan)
	local maps = {}
	for _, f in ipairs(plan.floors or {}) do
		if f.uiMapID then
			maps[#maps + 1] = f.uiMapID
		end
	end
	return maps
end

function Journal.ForPlan(plan)
	if type(plan) ~= "table" then
		return nil, 0
	end
	return Journal.ResolveInstance(plan.instance, planFloorMaps(plan))
end

-- Which journal boss each plan boss is. Cached per plan until its bosses change.
local function encounterSig(plan, entry)
	local parts = { entry and entry.key or "-" }
	for _, enc in ipairs(plan.encounters or {}) do
		parts[#parts + 1] = tostring(enc.id) .. ":" .. tostring(enc.ejEncounterID) .. ":" .. tostring(enc.name)
	end
	return table.concat(parts, "|")
end

local function pairing(plan)
	local entry = Journal.ForPlan(plan)
	local sig = encounterSig(plan, entry)
	local hit = planCache[plan]
	if hit and hit.sig == sig then
		return hit.byId
	end
	local byId = {}
	if entry then
		local matched = Match.Encounters(plan.encounters, Journal.Encounters(entry.ejInstanceID))
		for i, enc in ipairs(plan.encounters or {}) do
			if matched[i] then
				byId[enc.id] = matched[i]
			end
		end
	end
	planCache[plan] = { sig = sig, byId = byId }
	return byId
end

-- The journal boss for a plan boss, or nil.
function Journal.EncounterFor(plan, enc)
	if type(plan) ~= "table" or type(enc) ~= "table" then
		return nil
	end
	return pairing(plan)[enc.id]
end

-- The IDs to use for a plan boss: its own, else the matched journal boss's. Returns ejEncounterID, dungeonEncounterID.
function Journal.EncounterIds(plan, enc)
	if type(enc) ~= "table" then
		return nil, nil
	end
	local ej, dungeon = enc.ejEncounterID, enc.dungeonEncounterID
	if not (ej and dungeon) then
		local j = Journal.EncounterFor(plan, enc)
		if j then
			ej = ej or j.ejEncounterID
			dungeon = dungeon or j.dungeonEncounterID
		end
	end
	return ej, dungeon
end

-- function(enc) -> the encounter ID ENCOUNTER_END reports for a boss of `plan` (its own, else the journal's).
function Journal.GameIdOf(plan)
	return function(enc)
		local _, id = Journal.EncounterIds(plan, enc)
		return id
	end
end

-- A boss's face: { icon, displayInfo } from the matched journal boss, or from EJ_GetCreatureInfo(1, ejEncounterID).
local bossArt = {}
function Journal.BossArtById(ejEncounterID)
	if not ejEncounterID then
		return nil
	end
	if bossArt[ejEncounterID] ~= nil then
		return bossArt[ejEncounterID] or nil
	end
	local art = false
	if type(EJ_GetCreatureInfo) == "function" then
		local ok, _, _, _, displayInfo, icon = pcall(EJ_GetCreatureInfo, 1, ejEncounterID)
		if ok and (int(displayInfo) or file(icon)) then
			art = { displayInfo = int(displayInfo), icon = file(icon) }
		end
	end
	bossArt[ejEncounterID] = art
	return art or nil
end

-- Cached per plan revision (DB.Revision), the journal's scans and the data providers' state (Providers.epoch): every
-- redraw of the map, the side panel and Bosses asks for every boss.
local artCache = setmetatable({}, { __mode = "k" })
local bossArtNow
function Journal.BossArt(plan, enc)
	if type(plan) ~= "table" or type(enc) ~= "table" or enc.id == nil then
		return bossArtNow(plan, enc)
	end
	local rev = ns.DB and ns.DB.Revision(plan) or 0
	local epoch = (Journal.epoch or 0) .. ":" .. (ns.Providers and ns.Providers.epoch or 0)
	local hit = artCache[plan]
	if not hit or hit.rev ~= rev or hit.epoch ~= epoch then
		hit = { rev = rev, epoch = epoch, byId = {} }
		artCache[plan] = hit
	end
	local art = hit.byId[enc.id]
	if art == nil then
		art = bossArtNow(plan, enc) or false
		hit.byId[enc.id] = art
	end
	return art or nil
end

-- The creatures whose portraits a plan shows (its bosses, in the side panel's steps, on the map's pins and in the
-- Bosses section): their display IDs, each once, in the plan's order. For loading them early (Art.PrefetchPortraits).
function Journal.PlanPortraits(plan)
	local out, seen = {}, {}
	for _, enc in ipairs(type(plan) == "table" and plan.encounters or {}) do
		local art = Journal.BossArt(plan, enc)
		local id = art and art.displayInfo
		if id and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

function bossArtNow(plan, enc)
	local j = Journal.EncounterFor(plan, enc)
	if j and (j.displayInfo or j.icon) then
		return j
	end
	local ej = Journal.EncounterIds(plan, enc)
	local art = Journal.BossArtById(ej)
	if art then
		return art
	end
	-- No journal on Forever: a portrait another installed addon knows (Data/Providers.lua), credited in tooltips.
	if not ns.Providers then
		return nil
	end
	local provided, credit = ns.Providers.Portrait(plan, enc)
	if provided then
		provided.credit = credit
	end
	return provided
end

-- Pictures and maps ----------------------------------------------------------------------------------------------------------

-- The instance's pictures { button, button2, lore, background } for a plan instance or home entry, or nil.
function Journal.InstanceArt(inst)
	local entry = Journal.ResolveInstance(inst)
	if not entry then
		return nil
	end
	local art = entry.art
	if art.button or art.button2 or art.lore or art.background then
		return art
	end
	return nil
end

-- The instance's floors from the journal's map: { { uiMapID, name } } (empty without one).
function Journal.Floors(entry)
	if not (entry and entry.uiMapID) then
		return {}
	end
	if not entry.floors then
		entry.floors = ns.Instances.Floors(entry.uiMapID)
	end
	return entry.floors
end

-- The map to draw for floor `index` of a plan: the floor's own map when it has art; else the journal's floor that fits
-- (Match.Floor) when it has art; else, when the game's old dungeon tiles cover the floor (GameFiles.FloorArt, which the
-- canvas draws over a map without art), the floor's own map; else a same-named map with art (a guess: a zone or city
-- can share a dungeon floor's name, so it never wins over the dungeon's own tiles); else the floor's own map or the
-- journal's (the canvas then draws its parchment grid). Returns uiMapID or nil, and the journal entry.
function Journal.FloorMap(plan, index)
	local floor = plan and plan.floors and plan.floors[index]
	if not floor then
		return nil, nil
	end
	if floor.uiMapID and ns.Instances.MapArt(floor.uiMapID) then
		return floor.uiMapID, Journal.ForPlan(plan)
	end
	local entry = Journal.ForPlan(plan)
	local floors = Journal.Floors(entry)
	local f = Match.Floor(floor, index, #plan.floors, floors)
	if f and f.uiMapID and ns.Instances.MapArt(f.uiMapID) then
		return f.uiMapID, entry
	end
	if ns.GameFiles and ns.GameFiles.FloorArt(plan, index) then
		return floor.uiMapID or (f and f.uiMapID) or nil, entry
	end
	local byName = ns.Instances.FindArtMapByName(floor.name ~= "" and floor.name or nil)
	if byName then
		return byName, entry
	end
	if not floor.uiMapID and entry and entry.uiMapID and #plan.floors == 1 then
		byName = ns.Instances.FindArtMapByName(entry.name)
		if byName then
			return byName, entry
		end
	end
	return floor.uiMapID or (f and f.uiMapID) or nil, entry
end

-- The Adventure Guide's boss pins on a map: { { x, y, ejEncounterID, name } } (0..1, the art layer's coordinates).
-- EJ_GetMapEncounter(uiMapID, index[, fromJournal]) -> x, y, instanceID, name, description, encounterID (inferred).
-- Without pins, and with the instance known, it asks again with that instance selected (fromJournal = true).
local journalPins = {}
local function readPins(uiMapID, fromJournal)
	local pins = {}
	for index = 1, 40 do
		local ok, x, y, _, name, _, encounterID = pcall(EJ_GetMapEncounter, uiMapID, index, fromJournal)
		x, y = Util.Plain(x), Util.Plain(y)
		if not ok or not (Util.IsFiniteNumber(x) and Util.IsFiniteNumber(y)) then
			break
		end
		if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			pins[#pins + 1] = { x = x, y = y, ejEncounterID = int(encounterID), name = str(name) or "" }
		end
	end
	return pins
end

function Journal.Pins(uiMapID, ejInstanceID)
	if not Util.IsInteger(uiMapID) or type(EJ_GetMapEncounter) ~= "function" then
		return {}
	end
	local key = uiMapID .. ":" .. tostring(ejInstanceID)
	if journalPins[key] then
		return journalPins[key]
	end
	local pins = readPins(uiMapID, nil)
	local later = false
	if #pins == 0 and ejInstanceID and Journal.Available() then
		if journalOpen() then
			later = true -- the second read must not disturb the open guide: asked again on a later call
		else
			pcall(EJ_SelectInstance, ejInstanceID)
			pins = readPins(uiMapID, true)
		end
	end
	if not later then
		journalPins[key] = pins
	end
	return pins
end

-- Editable copies ----------------------------------------------------------------------------------------------------------

-- The IDs the journal knows for a plan, for Plan.ApplyJournalIds (an editable copy stores them: IDs are the truth).
function Journal.IdsFor(plan)
	local entry = Journal.ForPlan(plan)
	if not entry then
		return nil
	end
	local info = { instance = { ejInstanceID = entry.ejInstanceID, uiMapID = entry.uiMapID }, encounters = {}, floors = {} }
	for i, enc in ipairs(plan.encounters or {}) do
		local j = Journal.EncounterFor(plan, enc)
		if j then
			info.encounters[i] = { ejEncounterID = j.ejEncounterID, dungeonEncounterID = j.dungeonEncounterID }
		end
	end
	for i, floor in ipairs(plan.floors or {}) do
		if not floor.uiMapID then
			local f = Match.Floor(floor, i, #plan.floors, Journal.Floors(entry))
			info.floors[i] = f and f.uiMapID or nil
		end
	end
	return info
end

-- Diagnostics (/dp scan) ---------------------------------------------------------------------------------------------------
-- What the resolver sees, compact, for DungeonPlannerDB.diagnostics (saved on /reload, read offline). One line of text
-- per boss keeps it small: "journalEncounterID|dungeonEncounterID|displayInfo|icon|name".

local function v(x)
	return x == nil and "" or tostring(x)
end

function Journal.Diagnostics()
	cache = nil -- a fresh scan
	encounterCache, resolveCache = {}, {}
	byTable = setmetatable({}, { __mode = "k" })
	local data = Journal.GetAll()
	local out = {
		scan = Journal.lastScan,
		instances = {},
		plans = {},
		loot = { available = ns.Loot and ns.Loot.Available() or false, api = ns.Loot and ns.Loot.APIAvailable() or false },
	}
	for _, entry in ipairs(data.list) do
		complete(entry)
		local floors = {}
		for _, f in ipairs(Journal.Floors(entry)) do
			floors[#floors + 1] = v(f.uiMapID) .. "|" .. (ns.Instances.MapArt(f.uiMapID) and "art" or "no art") .. "|" .. v(f.name)
		end
		local bosses = {}
		for _, b in ipairs(Journal.Encounters(entry.ejInstanceID)) do
			bosses[#bosses + 1] = table.concat({ v(b.ejEncounterID), v(b.dungeonEncounterID), v(b.displayInfo), v(b.icon), v(b.name) }, "|")
		end
		local pins = entry.uiMapID and #Journal.Pins(entry.uiMapID, entry.ejInstanceID) or 0
		out.instances[#out.instances + 1] = {
			id = entry.ejInstanceID,
			name = entry.name,
			kind = entry.kind,
			tier = v(entry.tier) .. " " .. v(entry.tierName),
			uiMapID = entry.uiMapID,
			instanceMapID = entry.instanceMapID,
			art = table.concat({ v(entry.art.button), v(entry.art.button2), v(entry.art.lore), v(entry.art.background) }, "|"),
			floors = floors,
			pins = pins,
			bosses = bosses,
		}
	end
	-- How each recommended plan resolves: "journal instance ID (score), bosses matched/total, floor maps".
	for _, plan in ipairs(ns.Bundled.All()) do
		local entry, score = Journal.ForPlan(plan)
		local matched = 0
		for _, enc in ipairs(plan.encounters) do
			if Journal.EncounterFor(plan, enc) then
				matched = matched + 1
			end
		end
		local maps = {}
		for i = 1, #plan.floors do
			maps[#maps + 1] = v((Journal.FloorMap(plan, i))) .. (ns.GameFiles.FloorArt(plan, i) and "+tiles" or "")
		end
		out.plans[plan.id] = string.format("%s (%d) %d/%d bosses, maps %s", entry and (entry.ejInstanceID .. " " .. entry.name)
			or "none", score or 0, matched, #plan.encounters, table.concat(maps, ","))
	end
	if out.loot.available and out.instances[1] then
		local first = data.list[1]
		local boss = Journal.Encounters(first.ejInstanceID)[1]
		local items, status = ns.Loot.For(first.ejInstanceID, boss and boss.ejEncounterID, {})
		out.loot.sample = string.format("%s / %s: %d items (%s)", first.name, boss and boss.name or "-", #items, status)
	end
	return out
end

-- Recommended plans compare their instance with journal entries through this (Model/Bundled.lua stays pure).
ns.Bundled.journalID = function(inst)
	local entry, score = Journal.ResolveInstance(inst)
	if entry and score >= 75 then
		return entry.ejInstanceID
	end
	return nil
end

-- For tests: forget everything read from the journal.
function Journal.Reset()
	cache, encounterCache, resolveCache, bossArt, journalPins = nil, {}, {}, {}, {}
	byTable = setmetatable({}, { __mode = "k" })
	planCache = setmetatable({}, { __mode = "k" })
	artCache = setmetatable({}, { __mode = "k" })
	Journal.lastScan = nil
	Journal.epoch = (Journal.epoch or 0) + 1
end
