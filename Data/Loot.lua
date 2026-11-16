-- What drops in an instance, from the client's Adventure Guide (Encounter Journal), read at runtime: nothing is
-- bundled. Used by the Gear page and the boss page next to the plan's own gear recommendations.
--
-- Every call here is inferred on WoW: Forever (Retail 12.1.5 API; no installed Forever addon reads journal loot - the
-- Dungeon Journal addon ships its own loot tables), so each one is guarded and reported by /dp debug, and the pages
-- fall back to the plan's own list when anything is missing:
--   EJ_SelectInstance(id), EJ_SelectEncounter(journalEncounterID)
--   EJ_GetLootFilter() -> classID, specID; EJ_SetLootFilter(classID, specID) (0, 0 = everything)
--   EJ_GetNumLoot() -> n
--   C_EncounterJournal.GetLootInfoByIndex(i) -> { itemID, encounterID, name, itemQuality, icon, slot, armorType, link }
--     or the older EJ_GetLootInfoByIndex(i) -> itemID, encounterID, name, icon, slot, armorType, link
--   GetItemInfoInstant(itemID) -> itemID, type, subType, equipLoc, icon (the slot, whatever the client's language)
-- Item data loads asynchronously: an incomplete read is not cached, and EJ_LOOT_DATA_RECIEVED (the game's spelling)
-- refreshes the open page. Reading moves the journal's selection, so it never runs while the Blizzard journal is open,
-- and it puts the journal's loot filter back afterwards.

local _, ns = ...
local Loot = ns:NewModule("Loot")
local Util = ns.Util

Loot.MAX = 200
local cache = {} -- [key] = list

-- The game's equip locations to Dungeon Planner's slots (Schema.SLOTS).
local EQUIP_SLOT = {
	INVTYPE_HEAD = "HEAD",
	INVTYPE_NECK = "NECK",
	INVTYPE_SHOULDER = "SHOULDER",
	INVTYPE_CLOAK = "BACK",
	INVTYPE_CHEST = "CHEST",
	INVTYPE_ROBE = "CHEST",
	INVTYPE_WRIST = "WRIST",
	INVTYPE_HAND = "HANDS",
	INVTYPE_WAIST = "WAIST",
	INVTYPE_LEGS = "LEGS",
	INVTYPE_FEET = "FEET",
	INVTYPE_FINGER = "FINGER",
	INVTYPE_TRINKET = "TRINKET",
	INVTYPE_WEAPON = "MAINHAND",
	INVTYPE_WEAPONMAINHAND = "MAINHAND",
	INVTYPE_WEAPONOFFHAND = "OFFHAND",
	INVTYPE_SHIELD = "OFFHAND",
	INVTYPE_HOLDABLE = "OFFHAND",
	INVTYPE_2HWEAPON = "TWOHAND",
	INVTYPE_RANGED = "RANGED",
	INVTYPE_RANGEDRIGHT = "RANGED",
	INVTYPE_THROWN = "RANGED",
	INVTYPE_RELIC = "RANGED",
}
Loot.EQUIP_SLOT = EQUIP_SLOT

-- Loot needs the API and a journal with instances in it (on WoW: Forever the functions exist but the journal is empty).
function Loot.APIAvailable()
	local c = rawget(_G, "C_EncounterJournal")
	return ns.Journal.Available() and type(EJ_GetNumLoot) == "function"
		and ((c and type(c.GetLootInfoByIndex) == "function") or type(rawget(_G, "EJ_GetLootInfoByIndex")) == "function")
end

function Loot.Available()
	return Loot.APIAvailable() and ns.Journal.HasData()
end

local function int(v)
	v = Util.Plain(v)
	return Util.IsInteger(v) and v > 0 and v or nil
end

local function str(v)
	v = Util.Plain(v)
	return type(v) == "string" and v ~= "" and v or nil
end

function Loot.SlotOf(itemID)
	if not itemID or type(GetItemInfoInstant) ~= "function" then
		return nil
	end
	local ok, _, _, _, equipLoc = pcall(GetItemInfoInstant, itemID)
	return ok and EQUIP_SLOT[Util.Plain(equipLoc)] or nil
end

local function itemQuality(itemID, journalQuality)
	journalQuality = Util.Plain(journalQuality)
	if Util.IsInteger(journalQuality) then
		return journalQuality
	end
	itemID = Util.Plain(itemID)
	local items = rawget(_G, "C_Item")
	if Util.IsInteger(itemID) and items and type(items.GetItemQualityByID) == "function" then
		local ok, q = pcall(items.GetItemQualityByID, itemID)
		q = ok and Util.Plain(q) or nil
		return Util.IsInteger(q) and q or nil
	end
	return nil
end

local function lootInfo(index)
	local c = rawget(_G, "C_EncounterJournal")
	if c and type(c.GetLootInfoByIndex) == "function" then
		local ok, info = pcall(c.GetLootInfoByIndex, index)
		if ok and type(info) == "table" then
			return {
				itemID = int(info.itemID),
				encounterID = int(info.encounterID),
				name = str(info.name),
				-- itemQuality is a colour string on current clients (the API documentation's EncounterJournalItemInfo);
				-- the number comes from the item itself.
				quality = itemQuality(info.itemID, info.itemQuality),
				icon = Util.Plain(info.icon),
				slotText = str(info.slot),
				armorType = str(info.armorType),
				link = str(info.link),
			}
		end
	end
	local old = rawget(_G, "EJ_GetLootInfoByIndex")
	if type(old) == "function" then
		local ok, itemID, encounterID, name, icon, slot, armorType, link = pcall(old, index)
		if ok and int(itemID) then
			return {
				itemID = int(itemID),
				encounterID = int(encounterID),
				name = str(name),
				icon = Util.Plain(icon),
				slotText = str(slot),
				armorType = str(armorType),
				link = str(link),
			}
		end
	end
	return nil
end

-- Read the loot of one boss (ejEncounterID) or the whole instance (nil) for a class/spec (nil, nil = everyone).
-- Returns list, complete (false while item data is still loading).
local function read(ejInstanceID, ejEncounterID, classID, specID)
	local list, complete = {}, true
	pcall(EJ_SelectInstance, ejInstanceID)
	if ejEncounterID and type(EJ_SelectEncounter) == "function" then
		pcall(EJ_SelectEncounter, ejEncounterID)
	end
	local oldClass, oldSpec
	if type(EJ_GetLootFilter) == "function" then
		local ok, c, s = pcall(EJ_GetLootFilter)
		if ok then
			oldClass, oldSpec = Util.Plain(c), Util.Plain(s)
		end
	end
	if type(EJ_SetLootFilter) == "function" then
		pcall(EJ_SetLootFilter, classID or 0, specID or 0)
	end
	local okN, n = pcall(EJ_GetNumLoot)
	n = okN and int(n) or 0
	for i = 1, math.min(n, Loot.MAX) do
		local item = lootInfo(i)
		if item and item.itemID then
			if not item.name then
				complete = false
			end
			item.slot = Loot.SlotOf(item.itemID)
			item.ejEncounterID = item.encounterID or ejEncounterID
			list[#list + 1] = item
		end
	end
	if type(EJ_SetLootFilter) == "function" and oldClass then
		pcall(EJ_SetLootFilter, oldClass, oldSpec or 0)
	end
	return list, complete
end

-- The specializations of a class with a role ("TANK", "HEALER", "DAMAGER"): spec IDs, or nil when the client cannot
-- say (then the role does not narrow journal loot).
local function specsFor(classID, role)
	local get = rawget(_G, "GetSpecializationInfoForClassID")
	local count = rawget(_G, "C_SpecializationInfo") and rawget(_G, "C_SpecializationInfo").GetNumSpecializationsForClassID
		or rawget(_G, "GetNumSpecializationsForClassID")
	if not (classID and role and type(get) == "function" and type(count) == "function") then
		return nil
	end
	local okN, n = pcall(count, classID)
	n = okN and int(n) or nil
	if not n then
		return nil
	end
	local out = {}
	for i = 1, math.min(n, 6) do
		local ok, id, _, _, _, specRole = pcall(get, classID, i)
		if ok and int(id) and Util.Plain(specRole) == role then
			out[#out + 1] = id
		end
	end
	return out
end

-- Loot for the Gear page: { item, ... } in journal order, each { itemID, name, quality, icon, slot, slotText,
-- armorType, link, ejEncounterID }. filter = { classID?, role?, slot? }. Returns list, status: "ok", "loading" (some
-- items still arriving; call again on EJ_LOOT_DATA_RECIEVED) or "unavailable" (no journal loot on this client).
function Loot.For(ejInstanceID, ejEncounterID, filter)
	if not ejInstanceID or not Loot.Available() then
		return {}, "unavailable"
	end
	if ns.Journal.IsBlizzardJournalOpen() then
		return {}, "unavailable"
	end
	filter = filter or {}
	local specs = specsFor(filter.classID, filter.role)
	local reads = specs and #specs > 0 and specs or { 0 }
	local key = table.concat({ ejInstanceID, tostring(ejEncounterID), tostring(filter.classID), table.concat(reads, ",") }, ":")
	local list = cache[key]
	local status = "ok"
	if not list then
		local seen, complete = {}, true
		list = {}
		for _, spec in ipairs(reads) do
			local part, done = read(ejInstanceID, ejEncounterID, filter.classID, spec)
			complete = complete and done
			for _, item in ipairs(part) do
				if not seen[item.itemID] then
					seen[item.itemID] = true
					list[#list + 1] = item
				end
			end
		end
		if complete then
			cache[key] = list
		else
			status = "loading"
		end
	end
	if filter.slot then
		local out = {}
		for _, item in ipairs(list) do
			if item.slot == filter.slot then
				out[#out + 1] = item
			end
		end
		list = out
	end
	return list, status
end

function Loot.Reset()
	cache = {}
end
