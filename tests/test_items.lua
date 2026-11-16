-- Item names the client has not cached yet: asked for once, filled in when they arrive (Data/Names.lua).
local T = ...
local ns, mock = T.ns, T.mock

local function settle()
	for _ = 1, 5 do
		mock.Advance(10)
	end
end

T.case("Item names: a miss asks the client once, the arrival fires one batched message with the name", function()
	settle()
	local items = _G.C_Item
	local savedName, savedRequest = items.GetItemNameByID, items.RequestLoadItemDataByID
	local cache, requests = {}, {}
	items.GetItemNameByID = function(id)
		return cache[id]
	end
	items.RequestLoadItemDataByID = function(id)
		requests[#requests + 1] = id
	end
	local fired = 0
	local owner = {}
	ns:On("ITEMS_READY", owner, function()
		fired = fired + 1
	end)

	T.eq(ns.Names.Item(910001), nil, "no name while uncached")
	T.eq(ns.Names.Item(910001), nil, "still none")
	T.eq(ns.Names.Item(910002), nil)
	local first = 0
	for _, id in ipairs(requests) do
		if id == 910001 or id == 910002 then
			first = first + 1
		end
	end
	T.eq(first, 2, "each item asked once")
	local name = ns.Names.ItemInfo({ itemID = 910001, label = "" })
	T.ok(name:find("910001", 1, true), "the placeholder meanwhile")

	cache[910001], cache[910002] = "Real Helm", "Real Boots"
	mock.FireEvent("GET_ITEM_INFO_RECEIVED", 910001, true)
	mock.FireEvent("GET_ITEM_INFO_RECEIVED", 910002, true)
	mock.FireEvent("GET_ITEM_INFO_RECEIVED", 555, true) -- not ours
	T.eq(fired, 0, "batched, not at once")
	settle()
	T.eq(fired, 1, "one message for both items")
	T.eq(ns.Names.ItemInfo({ itemID = 910001, label = "" }), "Real Helm")

	-- A failed load is not asked again and fires nothing.
	T.eq(ns.Names.Item(910003), nil)
	mock.FireEvent("GET_ITEM_INFO_RECEIVED", 910003, false)
	settle()
	T.eq(ns.Names.Item(910003), nil)
	local asked = 0
	for _, id in ipairs(requests) do
		if id == 910003 then
			asked = asked + 1
		end
	end
	T.eq(asked, 1, "not asked again")
	T.eq(fired, 1)

	ns:Off("ITEMS_READY", owner)
	items.GetItemNameByID, items.RequestLoadItemDataByID = savedName, savedRequest
end)

T.case("Item names: without C_Item.RequestLoadItemDataByID the item mixin's callback does it", function()
	settle()
	local items = _G.C_Item
	local savedName, savedRequest, savedItem = items.GetItemNameByID, items.RequestLoadItemDataByID, _G.Item
	local cache, callbacks = {}, {}
	items.GetItemNameByID = function(id)
		return cache[id]
	end
	items.RequestLoadItemDataByID = nil
	_G.Item = {
		CreateFromItemID = function(_, id)
			return {
				ContinueOnItemLoad = function(_, fn)
					callbacks[id] = fn
				end,
			}
		end,
	}
	local fired = 0
	local owner = {}
	ns:On("ITEMS_READY", owner, function()
		fired = fired + 1
	end)
	T.eq(ns.Names.Item(910010), nil)
	T.ok(callbacks[910010], "the callback was registered")
	cache[910010] = "Late Ring"
	callbacks[910010]()
	settle()
	T.eq(fired, 1)
	T.eq(ns.Names.Item(910010), "Late Ring")
	ns:Off("ITEMS_READY", owner)
	items.GetItemNameByID, items.RequestLoadItemDataByID, _G.Item = savedName, savedRequest, savedItem
end)

T.case("Item names: an arrival while the window is open fires its message once", function()
	settle()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	local items = _G.C_Item
	local savedName = items.GetItemNameByID
	local cache = {}
	items.GetItemNameByID = function(id)
		return cache[id]
	end
	local fired = 0
	local owner = {}
	ns:On("ITEMS_READY", owner, function()
		fired = fired + 1
	end)
	T.eq(ns.Names.Item(910020), nil)
	cache[910020] = "Drop Name"
	mock.FireEvent("GET_ITEM_INFO_RECEIVED", 910020, true)
	settle()
	T.eq(fired, 1)
	ns:Off("ITEMS_READY", owner)
	items.GetItemNameByID = savedName
end)
