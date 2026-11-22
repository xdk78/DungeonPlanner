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
	-- The zone outside (an unnamed floor with its own map) whose map has no name on this client.
	if floor and floor.uiMapID then
		return ns.L["Outside"]
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

-- An item the client has not cached has no name yet. Names.Item asks the client to load it
-- (C_Item.RequestLoadItemDataByID, else the item mixin) and listens for ITEM_DATA_LOAD_RESULT, the event that request
-- answers with (the client's own ItemEventListener waits for the same one). GET_ITEM_INFO_RECEIVED counts too (a
-- tooltip's or another addon's load), but the request alone does not fire it: listening only to that event left every
-- row on "Item 12345" until its page happened to be built again.
-- Arrivals within ITEM_BATCH seconds go out as one ITEMS_READY message; the open window and run mode redraw once.
-- An item still nameless ITEM_RETRY seconds after it was asked for (no answer, a failed one, or an answer before the
-- name) is checked and asked again, at most ITEM_TRIES times a session. After that it keeps its "Item 12345" label;
-- hovering it (its tooltip loads the item) asks once more. The sweep timer runs only while an item waits.
local ITEM_BATCH, ITEM_RETRY, ITEM_TRIES, ITEM_MAX = 0.2, 4, 3, 2000
local itemState, itemCount = {}, 0 -- [itemID] = { tries = asks so far, at = GetTime() of the last ask, done = named }
local itemArrived, batchTimer, sweepTimer = {}, false, false
local itemEventsHooked = false

local function clock()
	return type(GetTime) == "function" and GetTime() or 0
end

local function clientItemName(itemID)
	local name = itemCall(C_Item and C_Item.GetItemNameByID, itemID)
	return type(name) == "string" and name ~= "" and name or nil
end

-- Mark the items of `ids` (a set) that have their name now; true when any did.
local function settleItems(ids)
	local any = false
	for id in pairs(ids) do
		local s = itemState[id]
		if s and not s.done and clientItemName(id) then
			s.done = true
			any = true
		end
	end
	return any
end

local function itemsReady()
	if ns.Fire then
		ns:Fire("ITEMS_READY")
	end
end

local function flushItems()
	batchTimer = false
	local ids = itemArrived
	itemArrived = {}
	if settleItems(ids) then
		itemsReady()
	end
end

local askItem, scheduleSweep

local function sweepItems()
	sweepTimer = false
	local named = settleItems(itemState)
	local t = clock()
	for id, s in pairs(itemState) do
		if not s.done then
			if t - s.at < ITEM_RETRY - 0.05 then -- this sweep's own asks are due now, not one interval later
				scheduleSweep()
			elseif s.tries < ITEM_TRIES then
				askItem(id, s)
			end
		end
	end
	if named then
		itemsReady()
	end
end

function scheduleSweep()
	if not sweepTimer and C_Timer and C_Timer.After then
		sweepTimer = true
		C_Timer.After(ITEM_RETRY, function()
			ns.SafeCall(sweepItems)
		end)
	end
end

function askItem(itemID, s)
	s.tries, s.at = s.tries + 1, clock()
	scheduleSweep()
	local items = rawget(_G, "C_Item")
	if items and type(items.RequestLoadItemDataByID) == "function" then
		pcall(items.RequestLoadItemDataByID, itemID)
		return
	end
	local mixin = rawget(_G, "Item")
	if mixin and type(mixin.CreateFromItemID) == "function" then
		local ok, item = pcall(mixin.CreateFromItemID, mixin, itemID)
		if ok and item and type(item.ContinueOnItemLoad) == "function" then
			pcall(item.ContinueOnItemLoad, item, function(_, success)
				Names.ItemArrived(itemID, success ~= false)
			end)
		end
	end
end

-- The client says an item's data arrived (or that it could not load it: success false; the sweep asks again later).
function Names.ItemArrived(itemID, success)
	local s = itemState[itemID]
	if not s or s.done or success == false then
		return
	end
	itemArrived[itemID] = true
	if not batchTimer and C_Timer and C_Timer.After then
		batchTimer = true
		C_Timer.After(ITEM_BATCH, function()
			ns.SafeCall(flushItems)
		end)
	end
end

local function hookItemEvents()
	if itemEventsHooked then
		return
	end
	itemEventsHooked = true
	local function arrived(_, id, success)
		Names.ItemArrived(Util.Plain(id), Util.Plain(success))
	end
	ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", arrived)
	ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", arrived)
end

-- Ask the client to load an item's data (guarded: either API may be missing): not while an ask is in flight, at most
-- ITEM_TRIES times, or once more with `again` (a hover, also no sooner than ITEM_RETRY after the last ask).
function Names.RequestItem(itemID, again)
	if not Util.IsInteger(itemID) then
		return
	end
	local s = itemState[itemID]
	if not s then
		if itemCount >= ITEM_MAX then
			return
		end
		itemCount = itemCount + 1
		s = { tries = 0, at = 0 }
		itemState[itemID] = s
		hookItemEvents()
	end
	s.done = false
	if s.tries > 0 and clock() - s.at < ITEM_RETRY then
		return
	end
	if s.tries >= ITEM_TRIES and not again then
		return
	end
	askItem(itemID, s)
end

-- A row showing an item is hovered: its tooltip loads the item; ask once more when it has no name yet.
function Names.ItemHovered(itemID)
	if itemID and not clientItemName(itemID) then
		Names.RequestItem(itemID, true)
	end
end

-- True while an item asked for may still arrive: no name yet and asks left, or the last ask is recent.
function Names.ItemLoading(itemID)
	local s = itemState[itemID]
	if not s or s.done or clientItemName(itemID) then
		return false
	end
	return s.tries < ITEM_TRIES or clock() - s.at < ITEM_RETRY
end

-- For tests: forget every item asked for.
function Names.ResetItems()
	itemState, itemCount, itemArrived = {}, 0, {}
end

function Names.Item(itemID)
	local name = clientItemName(itemID)
	if name then
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
