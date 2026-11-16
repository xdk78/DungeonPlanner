-- Instances, map floors and the player's location, read from the client at runtime. Dungeon Planner ships no game
-- data: nothing in this file is a hard-coded ID. The Adventure Guide (tiers, instances, bosses, pictures, pins) lives in
-- Data/Journal.lua; this file keeps thin wrappers for it, plus C_Map (names, floors, art) and the dungeon finder's level
-- ranges. Everything is read on demand and cached for the session.

local _, ns = ...
local Instances = ns:NewModule("Instances")
local Util = ns.Util

function Instances.HasJournal()
	return ns.Journal.Available()
end

-- The journal's instances: { tiers = { { name, instances } }, list, byKey, complete }.
function Instances.GetAll()
	return ns.Journal.GetAll()
end

function Instances.Get(key)
	return ns.Journal.Get(key)
end

-- Bosses of a journal instance: { { name, ejEncounterID, dungeonEncounterID, displayInfo, icon } } in journal order.
function Instances.GetEncounters(ejInstanceID)
	return ns.Journal.Encounters(ejInstanceID)
end

-- Maps ----------------------------------------------------------------------------------------------------------------
function Instances.MapName(uiMapID)
	if not (uiMapID and C_Map and C_Map.GetMapInfo) then
		return nil
	end
	local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
	if ok and type(info) == "table" then
		return Util.Plain(info.name)
	end
	return nil
end

-- The floors of a map: every member of its map group (multi-level dungeons), or just the map.
-- Returns { { uiMapID, name } }.
function Instances.Floors(uiMapID)
	if not uiMapID then
		return { { uiMapID = nil, name = "" } }
	end
	local floors = {}
	if C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo then
		local ok, groupID = pcall(C_Map.GetMapGroupID, uiMapID)
		groupID = ok and Util.Plain(groupID) or nil
		if groupID then
			local ok2, members = pcall(C_Map.GetMapGroupMembersInfo, groupID)
			if ok2 and type(members) == "table" then
				table.sort(members, function(a, b)
					return (a.relativeHeightIndex or 0) < (b.relativeHeightIndex or 0)
				end)
				for _, member in ipairs(members) do
					local id, name = Util.Plain(member.mapID), Util.Plain(member.name)
					if Util.IsInteger(id) then
						floors[#floors + 1] = { uiMapID = id, name = type(name) == "string" and name or "" }
					end
				end
			end
		end
	end
	if #floors == 0 then
		floors[1] = { uiMapID = uiMapID, name = Instances.MapName(uiMapID) or "" }
	end
	return floors
end

-- Map art: the tiles of art layer 1. Returns { width, height, tileWidth, tileHeight, textures = { fileID, ... } } or
-- nil when the map has no art (the canvas then draws a grid).
function Instances.MapArt(uiMapID)
	if not (uiMapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
		return nil
	end
	local ok, layers = pcall(C_Map.GetMapArtLayers, uiMapID)
	if not ok or type(layers) ~= "table" or type(layers[1]) ~= "table" then
		return nil
	end
	local layer = layers[1]
	local ok2, textures = pcall(C_Map.GetMapArtLayerTextures, uiMapID, 1)
	if not ok2 or type(textures) ~= "table" or #textures == 0 then
		return nil
	end
	local w, h = Util.Plain(layer.layerWidth), Util.Plain(layer.layerHeight)
	local tw, th = Util.Plain(layer.tileWidth), Util.Plain(layer.tileHeight)
	if not (Util.IsFiniteNumber(w) and Util.IsFiniteNumber(h) and Util.IsFiniteNumber(tw) and Util.IsFiniteNumber(th)) then
		return nil
	end
	if w <= 0 or h <= 0 or tw <= 0 or th <= 0 then
		return nil
	end
	return { width = w, height = h, tileWidth = tw, tileHeight = th, textures = textures }
end

-- Map IDs can differ between client builds (ForeverDungeonJournal's MapArtFinder found this on Forever), so when a
-- stored floor's map has no art, look for a map with the same name that has art. Same approach as that addon, our own
-- code: the names of map IDs 1..MAP_SCAN are read once per session, the first time a floor needs one (one GetMapInfo
-- per ID), into a name -> map IDs index; each name's answer (the first of its maps with art) is then cached.
local MAP_SCAN = 3000
Instances.MAP_SCAN = MAP_SCAN
local artByName = {}
local mapsByName -- [normalized name] = { uiMapID, ... } in ID order; built on first use
local function normName(s)
	return ns.Match.Norm(s)
end

local function nameIndex()
	if not mapsByName then
		mapsByName = {}
		for id = 1, MAP_SCAN do
			local ok, info = pcall(C_Map.GetMapInfo, id)
			local key = ok and type(info) == "table" and normName(Util.Plain(info.name)) or nil
			if key and key ~= "" then
				local list = mapsByName[key]
				if not list then
					list = {}
					mapsByName[key] = list
				end
				list[#list + 1] = id
			end
		end
	end
	return mapsByName
end

function Instances.FindArtMapByName(name)
	local key = normName(name)
	if not key or key == "" or not (C_Map and C_Map.GetMapInfo) then
		return nil
	end
	if artByName[key] ~= nil then
		return artByName[key] or nil
	end
	local found = false
	for _, id in ipairs(nameIndex()[key] or {}) do
		if Instances.MapArt(id) then
			found = id
			break
		end
	end
	artByName[key] = found
	return found or nil
end

-- For tests: forget the name index and its answers.
function Instances.ForgetMapNames()
	artByName, mapsByName = {}, nil
end

-- The map to draw for a plan floor: its own map if that has art, else a same-named map with art, else its own (grid).
function Instances.ArtMapForFloor(floor)
	if not floor then
		return nil
	end
	if floor.uiMapID and Instances.MapArt(floor.uiMapID) then
		return floor.uiMapID
	end
	local name = floor.name ~= "" and floor.name or (floor.uiMapID and Instances.MapName(floor.uiMapID))
	return Instances.FindArtMapByName(name) or floor.uiMapID
end

-- Where the player is: { name, uiMapID, ejInstanceID?, kind, difficultyID, instanceID }.
function Instances.Current()
	local info = { kind = "other" }
	if GetInstanceInfo then
		local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
		info.name = Util.Plain(name)
		info.difficultyID = Util.Plain(difficultyID)
		info.instanceID = Util.Plain(instanceID)
		instanceType = Util.Plain(instanceType)
		if instanceType == "party" then
			info.kind = "dungeon"
		elseif instanceType == "raid" then
			info.kind = "raid"
		end
		info.inInstance = instanceType == "party" or instanceType == "raid"
	end
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		mapID = ok and Util.Plain(mapID) or nil
		if Util.IsInteger(mapID) then
			info.uiMapID = mapID
			if not info.name or info.name == "" then
				info.name = Instances.MapName(mapID)
			end
		end
	end
	if info.uiMapID and type(EJ_GetInstanceForMap) == "function" then
		local ok, ej = pcall(EJ_GetInstanceForMap, info.uiMapID)
		ej = ok and Util.Plain(ej) or nil
		if Util.IsInteger(ej) and ej > 0 then
			info.ejInstanceID = ej
		end
	end
	return info
end

-- An instance description for a new plan, from a picker entry or the current location.
function Instances.ToPlanInstance(entry)
	return {
		name = entry.name or "",
		kind = entry.kind or "other",
		ejInstanceID = entry.ejInstanceID,
		uiMapID = entry.uiMapID,
	}
end

-- Journal art and positions ----------------------------------------------------------------------------------------------
-- All inferred on Forever (Retail 12.1.5 API, not seen in a Forever-only addon): every call is guarded, cached per
-- session and reported by /dp debug. No Dungeon Planner art replaces what the client lacks; the UI draws a parchment.
-- Journal pictures, portraits and pins (Data/Journal.lua) ----------------------------------------------------------------

-- The Adventure Guide's pictures of a journal instance: { button, button2, lore, background } or nil.
function Instances.InstanceArt(ejInstanceID)
	local entry = ns.Journal.ByInstanceID(ejInstanceID)
	return entry and ns.Journal.InstanceArt(entry) or nil
end

-- A boss's face by journal encounter ID: { icon, displayInfo } or nil.
function Instances.BossArt(ejEncounterID)
	return ns.Journal.BossArtById(ejEncounterID)
end

-- The Adventure Guide's boss pins on a map (Journal.Pins).
function Instances.JournalPins(uiMapID, ejInstanceID)
	return ns.Journal.Pins(uiMapID, ejInstanceID)
end

-- Pins from the Adventure Guide that a recommended plan (or an editable copy of one) does not already show: recommended
-- plans place only the bosses their research found, so the guide's pins fill in the rest. A pin counts as placed when a
-- boss marker of the plan has the same encounter ID or a similar name (whatever the client's language lets us compare),
-- or sits at almost the same spot on the same floor. `floor` is the plan floor the pins belong to.
local PIN_NEAR = 0.025 -- normalized map units

local function sameBossName(a, b)
	a, b = normName(a), normName(b)
	if not a or not b or a == "" or b == "" then
		return false
	end
	return a == b or (#b >= 5 and a:find(b, 1, true) ~= nil) or (#a >= 5 and b:find(a, 1, true) ~= nil)
end

function Instances.PinsNotPlaced(plan, floor, pins)
	local out = {}
	for _, pin in ipairs(pins) do
		local placed = false
		for _, m in ipairs(plan.markers) do
			if m.kind == "boss" then
				local enc = m.encounter and Util.FindById(plan.encounters, m.encounter)
				local ej = enc and ns.Journal.EncounterIds(plan, enc)
				if
					(ej and pin.ejEncounterID and ej == pin.ejEncounterID)
					or sameBossName(m.label, pin.name)
					or (enc and sameBossName(enc.name, pin.name))
					or (m.floor == floor and math.abs(m.x - pin.x) < PIN_NEAR and math.abs(m.y - pin.y) < PIN_NEAR)
				then
					placed = true
					break
				end
			end
		end
		if not placed then
			out[#out + 1] = pin
		end
	end
	return out
end

-- An instance's level range: the Group Finder's (by the journal's instance map ID, else by name; Data/GameFiles.lua)
-- when it gives two different levels, else a plan's (recommended plans carry one), else the finder's one level
-- (GameFiles.ResolveRange). entry = a home entry or plan instance { ejInstanceID?, name?, levelMin?, levelMax? }.
-- Returns min, max or nil.
function Instances.LevelRange(entry)
	local journal = entry and ns.Journal.ResolveInstance(entry)
	local hit = ns.GameFiles.FinderFor(entry and entry.name, journal and journal.instanceMapID)
	return ns.GameFiles.ResolveRange(hit, entry)
end
