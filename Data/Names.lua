-- Display names for things a plan refers to by ID. The ID is the truth; the name stored in the plan is only a fallback
-- for clients that cannot resolve the ID (no journal entry, a custom boss, an offline validator). So a plan made on an
-- English client shows Polish, German, ... names on another client, in that client's language, and the other way round.
--   Encounter: EJ_GetEncounterInfo(ejEncounterID), unless the planner renamed it (enc.custom).
--   Instance:  EJ_GetInstanceInfo(ejInstanceID), else the map name, else the stored name.
--   Floor:     C_Map.GetMapInfo(uiMapID).name, else the stored name.
-- Lookups are cached for the session (names do not change while playing).

local _, ns = ...
local Names = ns:NewModule("Names")
local Util = ns.Util

local encounterNames, instanceNames = {}, {}

local function journalEncounterName(id)
	if encounterNames[id] ~= nil then
		return encounterNames[id] or nil
	end
	local name
	if type(EJ_GetEncounterInfo) == "function" then
		local ok, n = pcall(EJ_GetEncounterInfo, id)
		n = ok and Util.Plain(n) or nil
		if type(n) == "string" and n ~= "" then
			name = n
		end
	end
	encounterNames[id] = name or false
	return name
end

local function journalInstanceName(id)
	if instanceNames[id] ~= nil then
		return instanceNames[id] or nil
	end
	local name
	if type(EJ_GetInstanceInfo) == "function" then
		local ok, n = pcall(EJ_GetInstanceInfo, id)
		n = ok and Util.Plain(n) or nil
		if type(n) == "string" and n ~= "" then
			name = n
		end
	end
	instanceNames[id] = name or false
	return name
end

function Names.Encounter(enc)
	if not enc then
		return ""
	end
	if not enc.custom and enc.ejEncounterID then
		local name = journalEncounterName(enc.ejEncounterID)
		if name then
			return name
		end
	end
	if enc.name and enc.name ~= "" then
		return enc.name
	end
	if enc.dungeonEncounterID then
		return string.format(ns.L["Boss %d"], enc.dungeonEncounterID)
	end
	return ns.L["Boss"]
end

function Names.Instance(inst)
	if not inst then
		return ""
	end
	if inst.ejInstanceID then
		local name = journalInstanceName(inst.ejInstanceID)
		if name then
			return name
		end
	end
	if inst.uiMapID then
		local name = ns.Instances.MapName(inst.uiMapID)
		if name and name ~= "" then
			return name
		end
	end
	return inst.name or ""
end

function Names.Floor(floor, index)
	if floor and floor.uiMapID then
		local name = ns.Instances.MapName(floor.uiMapID)
		if name and name ~= "" then
			return name
		end
	end
	if floor and floor.name and floor.name ~= "" then
		return floor.name
	end
	return string.format(ns.L["Floor %d"], index or 1)
end

-- Items -----------------------------------------------------------------------------------------------------------------
-- Names, quality and icons come from the client (C_Item, guarded; uncached items fill in later). Nothing is bundled.

local function itemCall(fn, id)
	if type(fn) ~= "function" or not id then
		return nil
	end
	local ok, value = pcall(fn, id)
	return ok and ns.Util.Plain(value) or nil
end

-- An item the client has not cached has no name yet. The first lookup asks the client to load it (once per item); when
-- GET_ITEM_INFO_RECEIVED (or the item mixin's callback) says it arrived, the arrivals of the next 0.2 s go out as one
-- ITEMS_READY message, so open lists redraw once with the names in place of "Item 12345".
local ITEM_BATCH = 0.2
local itemAsked = {} -- [itemID] = true while the client was asked and has not answered, false once it did
local itemArrived, itemTimer = {}, false
local itemEventHooked = false

local function flushItems()
	itemTimer = false
	local any = false
	for id in pairs(itemArrived) do
		itemArrived[id] = nil
		if Names.Item(id) then
			any = true
		end
	end
	if any and ns.Fire then
		ns:Fire("ITEMS_READY")
	end
end

function Names.ItemArrived(itemID, success)
	if itemAsked[itemID] ~= true then
		return
	end
	itemAsked[itemID] = false
	if success == false then
		return
	end
	itemArrived[itemID] = true
	if not itemTimer and C_Timer and C_Timer.After then
		itemTimer = true
		C_Timer.After(ITEM_BATCH, function()
			ns.SafeCall(flushItems)
		end)
	end
end

-- Ask the client to load an item's data (guarded: either API may be missing). Asked once per item.
function Names.RequestItem(itemID)
	if not Util.IsInteger(itemID) or itemAsked[itemID] ~= nil then
		return
	end
	itemAsked[itemID] = true
	if not itemEventHooked then
		itemEventHooked = true
		ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id, success)
			Names.ItemArrived(Util.Plain(id), Util.Plain(success))
		end)
	end
	local items = rawget(_G, "C_Item")
	if items and type(items.RequestLoadItemDataByID) == "function" then
		pcall(items.RequestLoadItemDataByID, itemID)
		return
	end
	local mixin = rawget(_G, "Item")
	if mixin and type(mixin.CreateFromItemID) == "function" then
		local ok, item = pcall(mixin.CreateFromItemID, mixin, itemID)
		if ok and item and type(item.ContinueOnItemLoad) == "function" then
			pcall(item.ContinueOnItemLoad, item, function()
				Names.ItemArrived(itemID, true)
			end)
		end
	end
end

function Names.Item(itemID)
	local get = C_Item and C_Item.GetItemNameByID
	local name = itemCall(get, itemID)
	if type(name) == "string" and name ~= "" then
		return name
	end
	Names.RequestItem(itemID)
	return nil
end

-- name, quality (0-7 or nil), icon (file ID or nil) for a gear entry { itemID?, label }.
function Names.ItemInfo(g)
	local name = g.itemID and Names.Item(g.itemID)
	local quality = g.itemID and itemCall(C_Item and C_Item.GetItemQualityByID, g.itemID)
	local icon = g.itemID and itemCall(C_Item and C_Item.GetItemIconByID, g.itemID)
	if not name then
		name = g.label ~= "" and g.label or (ns.L["Item"] .. " " .. tostring(g.itemID or "?"))
	end
	return name, ns.Util.IsInteger(quality) and quality or nil, icon
end

-- The game's item quality colours (ITEM_QUALITY_COLORS when present), white otherwise.
function Names.QualityColor(quality)
	local colors = rawget(_G, "ITEM_QUALITY_COLORS")
	local c = quality and type(colors) == "table" and colors[quality]
	if type(c) == "table" and c.r then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

-- A route's name. Generated plans name a single-floor route "Route" (English data): that, and an empty name, show the
-- UI's own word for it, so a Polish UI says "Trasa". Names the planner typed are shown as written.
function Names.Route(route)
	local name = type(route) == "table" and route.name or nil
	if type(name) ~= "string" or name == "" or name == "Route" then
		return ns.L["Route"]
	end
	return name
end
