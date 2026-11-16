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

	-- A failed load fires nothing; it is asked again a few seconds later, three times in all, then left alone.
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
	T.eq(asked, 3, "asked three times, no more")
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

-- In game (Hall of Thanes, /dp shots): the Bosses page and the Gear page kept "Item 271097" while the client loaded the
-- items, because the client answers C_Item.RequestLoadItemDataByID with ITEM_DATA_LOAD_RESULT and the addon only
-- listened for GET_ITEM_INFO_RECEIVED. Here the client is like that one: answers come late, in a random order, some
-- fail first, some names land without any event, one item never answers; GET_ITEM_INFO_RECEIVED never fires.
T.case("Item names: drops of every boss end up named on the open pages, however the answers arrive", function()
	settle()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.Names.ResetItems()
	local savedBossData = ns.BossData.enabled
	ns.BossData.enabled = true -- the bundled drops, as in game (provider tests switch them off)
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	local items = _G.C_Item
	local savedName, savedRequest = items.GetItemNameByID, items.RequestLoadItemDataByID
	local cache, asks, never = {}, {}, nil
	local seed = 20261116
	local function rand(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	items.GetItemNameByID = function(id)
		return cache[id]
	end
	items.RequestLoadItemDataByID = function(id)
		asks[id] = (asks[id] or 0) + 1
		if id == never then
			return
		end
		local kind, delay = rand(4), 0.05 + rand(60) / 10 -- up to 6 s
		C_Timer.After(delay, function()
			if kind == 0 and asks[id] == 1 then
				mock.FireEvent("ITEM_DATA_LOAD_RESULT", id, false) -- the first answer fails
			elseif kind == 1 then
				cache[id] = "Real " .. id -- the name lands without any event
			elseif kind == 2 then
				mock.FireEvent("ITEM_DATA_LOAD_RESULT", id, true) -- the event comes before the name
				C_Timer.After(1, function()
					cache[id] = "Real " .. id
				end)
			else
				cache[id] = "Real " .. id
				mock.FireEvent("ITEM_DATA_LOAD_RESULT", id, true)
			end
		end)
	end
	local function run(seconds)
		for _ = 1, seconds * 4 do
			mock.Advance(0.25)
		end
	end

	local plan = ns.Bundled.Get("b:hall-of-thanes")
	local all, bosses = {}, 0
	for _, enc in ipairs(plan.encounters) do
		local drops = ns.BossData.Loot(plan, enc) or {}
		bosses = bosses + (#drops > 0 and 1 or 0)
		for _, d in ipairs(drops) do
			all[#all + 1] = d.itemID
		end
	end
	T.ok(bosses >= 3 and #all >= 9, "several bosses with drops")
	never = all[#all]

	-- The Bosses page, first boss: its drops are asked for and filled in while the page stays open.
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("encounters")
	local bossPage = _G.DungeonPlannerMainFrame.instancePage.panels.encounters.inner
	bossPage:Refresh()
	for _, row in ipairs(bossPage.list.rows) do
		if row.item == plan.encounters[1] then
			row:GetScript("OnClick")(row, "LeftButton")
		end
	end
	local function bossRows()
		local out = {}
		for _, row in ipairs(bossPage.doc.dpItemRows or {}) do
			if row:IsShown() and row.dpItem then
				out[#out + 1] = row
			end
		end
		return out
	end
	local first = bossRows()
	T.ok(#first >= 3, "the first boss's drops are listed")
	T.eq(first[1].name:GetText(), "Item " .. first[1].dpItem.itemID, "a placeholder before the answer")
	run(30)
	for _, row in ipairs(bossRows()) do
		T.eq(row.name:GetText(), "Real " .. row.dpItem.itemID, "Bosses page row")
	end

	-- The Gear page lists every boss's drops; the rest are asked for now and filled in while it stays open.
	ns.UI.SelectTab("gear")
	local gear = _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
	gear:Refresh()
	run(60)
	local seen = 0
	for index, item in ipairs(gear.list.items) do
		if item.loot then
			gear.list:ScrollTo(index)
			for _, row in ipairs(gear.list.rows) do
				if row.item == item then
					seen = seen + 1
					local id = item.loot.itemID
					T.eq(row.title:GetText(), id == never and ("Item " .. id) or ("Real " .. id), "Gear page row")
				end
			end
		end
	end
	T.eq(seen, #all, "every drop has a row")

	-- Bounded: no item asked more than three times, and nothing is asked once the work is over.
	for id, n in pairs(asks) do
		T.ok(n <= 3, "item " .. id .. " asked " .. n .. " times")
	end
	T.eq(asks[never], 3, "the silent item was retried, then given up")
	local before = 0
	for _, n in pairs(asks) do
		before = before + n
	end
	run(120)
	gear:Refresh()
	local after = 0
	for _, n in pairs(asks) do
		after = after + n
	end
	T.eq(after, before, "no more asks once every item is named or given up")
	-- Hovering the nameless one asks once more (its tooltip loads it too).
	ns.Names.ItemHovered(never)
	ns.Names.ItemHovered(never)
	T.eq(asks[never], 4, "one more ask per hover, not one per call")

	items.GetItemNameByID, items.RequestLoadItemDataByID = savedName, savedRequest
	ns.Names.ResetItems()
	ns.BossData.enabled = savedBossData
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
end)
