-- The Gear page's filters (Model/GearFilter.lua, Data/Loot.lua's item types, UI/Panels/GearPanel.lua), driven through
-- the dropdowns' own clicks and the popup's rows; the popup's row pools (UI/Popup.lua); and the header's Show location
-- button (UI/InstancePage.lua, UI/GettingThere.lua).
local T = ...
local ns, mock = T.ns, T.mock
local GF = ns.GearFilter

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.BossData.enabled = true
	mock.playerPos = nil
end

-- A case whose stubs are put back whether it passes or fails: every global or field it may replace is saved first and
-- restored after it, then any error goes on to T.case.
local function case(name, fn)
	T.case(name, function()
		local items = _G.C_Item
		local saved = {
			hasData = ns.Journal.HasData, travelFor = ns.Travel.For, gamepad = ns.Compat.Gamepad,
			name = items.GetItemNameByID, request = items.RequestLoadItemDataByID,
			dead = _G.UnitIsDeadOrGhost, inCombat = mock.inCombat,
		}
		mock.itemTypes = {}
		ns.Names.ResetItems()
		local ok, err = pcall(fn)
		ns.Journal.HasData, ns.Travel.For, ns.Compat.Gamepad = saved.hasData, saved.travelFor, saved.gamepad
		items.GetItemNameByID, items.RequestLoadItemDataByID = saved.name, saved.request
		_G.UnitIsDeadOrGhost, mock.inCombat = saved.dead, saved.inCombat
		mock.ResetInput()
		mock.itemTypes = {}
		ns.Names.ResetItems()
		ns.Widgets.ClosePopup()
		local w = ns.GettingThere.Window()
		if w then
			w:Hide()
		end
		if not ok then
			error(err, 0)
		end
	end)
end

-- WoW: Forever's Adventure Guide is empty: the drops come from the bundled boss data, as in game.
local function noJournal()
	ns.Journal.HasData = function()
		return false
	end
end

local function page()
	return _G.DungeonPlannerMainFrame.instancePage
end

local function openPlan(slug)
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. slug)
	ns.UI.SelectPlan(plan.id)
	return plan
end

local function gearPage()
	ns.UI.SelectTab("gear")
	local gear = page().panels.gear.inner
	gear:Refresh()
	return gear
end

-- Open a dropdown with its own click and click the popup row showing `text`.
local function choose(dd, text)
	mock.Click(dd)
	local p = ns.Widgets.ActivePopup()
	T.ok(p and p.owner == dd, "the dropdown's list is open")
	for _, f in ipairs(p.pools[p.poolKey].item) do
		if f:IsShown() and f.label and f.label:GetText() == text then
			mock.Click(f)
			T.eq(ns.Widgets.ActivePopup(), nil, "choosing closes the list")
			return
		end
	end
	p:Close()
	error("no option " .. text)
end

-- The drops the list draws: every item cell's item ID, scrolled through like a player would.
local function shown(gear)
	local ids = {}
	for index, line in ipairs(gear.list.items) do
		if line.cells then
			gear.list:ScrollTo(index)
			for _, row in ipairs(gear.list.rows) do
				if row.item == line then
					for _, cell in ipairs(row.cells) do
						if cell:IsShown() and cell.entry and cell.entry.loot then
							ids[cell.entry.loot.itemID] = true
						end
					end
				end
			end
		end
	end
	return ids
end

local function ownLabels(gear)
	local labels = {}
	for _, e in ipairs(gear.entries) do
		if e.gear then
			labels[e.gear.label] = true
		end
	end
	return labels
end

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end

local function run(seconds)
	for _ = 1, seconds * 4 do
		mock.Advance(0.25)
	end
end

-- Lord Cobrahn's first drop leather legs, his second a mail belt; every other drop of the plan a wand.
local function typeDrops(plan)
	local cobrahn = plan.encounters[2]
	local drops = ns.BossData.Loot(plan, cobrahn)
	T.ok(drops and #drops >= 2, "Lord Cobrahn has bundled drops")
	local legs, belt = drops[1].itemID, drops[2].itemID
	local others = {}
	for _, enc in ipairs(plan.encounters) do
		for _, d in ipairs(ns.BossData.Loot(plan, enc) or {}) do
			if d.itemID ~= legs and d.itemID ~= belt then
				others[#others + 1] = d.itemID
				mock.itemTypes[d.itemID] = { "INVTYPE_RANGEDRIGHT", 2, 19 }
			end
		end
	end
	mock.itemTypes[legs] = { "INVTYPE_LEGS", 4, 2 }
	mock.itemTypes[belt] = { "INVTYPE_WAIST", 4, 3 }
	T.ok(#others > 0, "drops of other bosses")
	return legs, belt, others, cobrahn, #drops
end

case("GearFilter: what a class can equip, cloaks and non-equipment for everyone, unknown items unknown", function()
	local leatherLegs = { classID = 4, subclassID = 2, slot = "LEGS" }
	local mailWaist = { classID = 4, subclassID = 3, slot = "WAIST" }
	local plateChest = { classID = 4, subclassID = 4, slot = "CHEST" }
	local cloak = { classID = 4, subclassID = 1, slot = "BACK" }
	local ring = { classID = 4, subclassID = 0, slot = "FINGER" }
	local shield = { classID = 4, subclassID = 6, slot = "OFFHAND" }
	local wand = { classID = 2, subclassID = 19, slot = "RANGED" }
	local staff = { classID = 2, subclassID = 10, slot = "TWOHAND" }
	local quest = { classID = 12, subclassID = 0 }
	T.eq(GF.CanEquip("WARRIOR", leatherLegs), true, "a warrior can equip leather")
	T.eq(GF.CanEquip("WARRIOR", plateChest), true)
	T.eq(GF.CanEquip("WARRIOR", wand), false, "but no wand")
	T.eq(GF.CanEquip("MAGE", leatherLegs), false, "a mage wears cloth only")
	T.eq(GF.CanEquip("MAGE", mailWaist), false)
	T.eq(GF.CanEquip("MAGE", cloak), true, "a cloak suits everyone")
	T.eq(GF.CanEquip("MAGE", ring), true)
	T.eq(GF.CanEquip("MAGE", wand), true)
	T.eq(GF.CanEquip("MAGE", staff), true)
	T.eq(GF.CanEquip("MAGE", shield), false)
	T.eq(GF.CanEquip("SHAMAN", shield), true)
	T.eq(GF.CanEquip("ROGUE", mailWaist), false)
	T.eq(GF.CanEquip("HUNTER", mailWaist), true)
	T.eq(GF.CanEquip("PRIEST", quest), true, "not equipment: not class gear")
	T.eq(GF.CanEquip("MAGE", nil), nil, "unknown until the item loads")
	T.eq(GF.CanEquip("SOMECLASS", leatherLegs), true, "a class the rules do not know is not filtered")
	T.eq(GF.Match({}, nil), true, "no filter: everything, known or not")
	T.eq(GF.Match({ slot = "LEGS" }, leatherLegs), true)
	T.eq(GF.Match({ slot = "LEGS" }, mailWaist), false)
	T.eq(GF.Match({ slot = "LEGS", class = "MAGE" }, leatherLegs), false)
	T.eq(GF.Match({ slot = "LEGS" }, quest), false, "no slot: not under a slot")
	T.eq(GF.Match({ class = "MAGE" }, nil), nil)
	-- A one-hand weapon goes in either hand (Loot.ItemType's alsoSlot).
	mock.itemTypes[880001] = { "INVTYPE_WEAPON", 2, 7 }
	local sword = ns.Loot.ItemType(880001)
	T.eq(sword.slot, "MAINHAND")
	T.eq(GF.Match({ slot = "OFFHAND" }, sword), true, "a one-hand sword under off hand")
	T.eq(GF.Match({ slot = "MAINHAND" }, sword), true)
	T.ok(ns.Loot.FitsSlot(sword, "OFFHAND") and not ns.Loot.FitsSlot(sword, "TWOHAND"))
end)

case("Gear filters: the class, boss and slot dropdowns change the drops listed; uncached items join once loaded", function()
	noJournal()
	local plan = openPlan("wailing-caverns")
	local legs, belt, others, cobrahn, cobrahnDrops = typeDrops(plan)
	local gear = gearPage()
	local all = shown(gear)
	T.ok(all[legs] and all[belt], "everything listed without a filter")
	local total = count(all)

	choose(gear.class, "Warrior")
	T.eq(gear.class.label:GetText(), "Warrior", "the choice shows")
	local warrior = shown(gear)
	T.ok(warrior[legs] and warrior[belt], "a warrior can equip leather and mail")
	T.ok(not warrior[others[1]], "but no wand")
	T.eq(count(warrior), 2)

	choose(gear.class, "Mage")
	local mage = shown(gear)
	T.ok(not mage[legs] and not mage[belt], "a mage cannot wear Cobrahn's leather or mail")
	T.ok(mage[others[1]], "a mage can use a wand")

	choose(gear.class, "All classes")
	T.eq(count(shown(gear)), total, "back to everything")

	-- One boss: only his drops.
	choose(gear.encounter, ns.Names.Encounter(cobrahn))
	local his = shown(gear)
	T.ok(his[legs] and his[belt], "Cobrahn's drops")
	T.eq(count(his), cobrahnDrops, "not the other bosses'")
	-- One slot, by the item's type.
	choose(gear.slot, ns.L["slot:LEGS"])
	local onlyLegs = shown(gear)
	T.ok(onlyLegs[legs] and not onlyLegs[belt], "only the legs")
	choose(gear.slot, ns.L["All slots"])
	choose(gear.encounter, ns.L["Whole instance"])

	-- An item the client has no data for yet: left out of a filtered list, asked for, and in once it arrives.
	local items = _G.C_Item
	local requested = {}
	items.RequestLoadItemDataByID = function(id)
		requested[id] = (requested[id] or 0) + 1
	end
	items.GetItemNameByID = function(id)
		if mock.itemTypes[id] == false then
			return nil
		end
		return "Real " .. id
	end
	mock.itemTypes[legs] = false
	choose(gear.class, "Warrior")
	T.ok(not shown(gear)[legs], "not listed while its type is unknown")
	T.eq(requested[legs], 1, "asked for once")
	T.eq(gear.status:GetText(), ns.L["Loading items..."], "says it is loading")
	mock.itemTypes[legs] = { "INVTYPE_LEGS", 4, 2 }
	mock.FireEvent("ITEM_DATA_LOAD_RESULT", legs, true)
	run(2)
	T.ok(shown(gear)[legs], "listed once it arrived (one redraw, ITEMS_READY)")
	T.ok(gear.status:GetText() ~= ns.L["Loading items..."], "no longer loading")
	T.eq(requested[legs], 1, "no more asks")
	choose(gear.class, "All classes")
end)

case("Gear filters: an item that never arrives stops the loading line once the last ask goes unanswered", function()
	noJournal()
	local plan = openPlan("wailing-caverns")
	local legs = typeDrops(plan)
	local items = _G.C_Item
	local asks = 0
	items.RequestLoadItemDataByID = function(id)
		if id == legs then
			asks = asks + 1
		end
	end
	items.GetItemNameByID = function(id)
		return id ~= legs and ("Real " .. id) or nil
	end
	mock.itemTypes[legs] = false
	local gear = gearPage()
	choose(gear.class, "Warrior")
	T.eq(gear.status:GetText(), ns.L["Loading items..."], "loading while it may still come")
	T.ok(ns.Names.ItemLoading(legs))
	run(6)
	T.eq(gear.status:GetText(), ns.L["Loading items..."], "still asking")
	run(7)
	T.eq(asks, 3, "asked three times, then given up")
	T.ok(not ns.Names.ItemLoading(legs), "given up")
	T.ok(gear.status:GetText() ~= ns.L["Loading items..."], "after about 13 s the page no longer says it is loading")
	T.ok(not shown(gear)[legs], "and the unknown item stays out of the filtered list")
	run(30)
	T.eq(asks, 3, "nothing more is asked")
	choose(gear.class, "All classes")
	T.ok(shown(gear)[legs], "listed without a filter")
end)

case("Gear filters: the role filter is off on a read-only plan whose entries name no role; an own plan's entries", function()
	noJournal()
	openPlan("wailing-caverns")
	local gear = gearPage()
	T.ok(not gear.role:IsEnabled(), "nothing to filter by role")
	T.ok(gear.role.dpTooltipText:find("no role", 1, true), gear.role.dpTooltipText)
	-- An own plan: the role tags the plan's own entries (and the add form's).
	local wc = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns")
	local legs, belt = typeDrops(wc)
	local editable = ns.DB.AddPlan(ns.Plan.New({ name = "Mine", instance = ns.Util.DeepCopy(wc.instance) }))
	T.ok(editable, "an own plan")
	ns.Plan.AddGear(editable, { label = "Tank shield", role = "TANK", priority = 1 })
	ns.Plan.AddGear(editable, { label = "Healer mace", role = "HEALER", priority = 1 })
	-- Entries with an item: one untagged (it follows the class filter by its type), one tagged for mages.
	ns.Plan.AddGear(editable, { itemID = legs, label = "Untagged legs", priority = 2 })
	ns.Plan.AddGear(editable, { itemID = belt, label = "Mage belt", class = "MAGE", priority = 2 })
	ns.UI.SelectPlan(editable.id)
	gear = gearPage()
	T.ok(gear.role:IsEnabled(), "on for an editable plan")
	choose(gear.role, ns.L["Tank"])
	local labels = ownLabels(gear)
	T.ok(labels["Tank shield"] and not labels["Healer mace"], "the plan's own entries by role")
	choose(gear.role, ns.L["All roles"])

	choose(gear.class, "Mage")
	labels = ownLabels(gear)
	T.ok(not labels["Untagged legs"], "an untagged entry a mage cannot wear is left out")
	T.ok(labels["Mage belt"], "an entry tagged for the class stays, whatever its type")
	T.ok(labels["Tank shield"], "an entry without an item stays")
	choose(gear.class, "Warrior")
	labels = ownLabels(gear)
	T.ok(labels["Untagged legs"] and not labels["Mage belt"], "a warrior: the legs, not the mage's tag")
	choose(gear.class, "All classes")
end)

case("Popup rows: two lists of one style with different row builders never share rows", function()
	boot()
	local W = ns.Widgets
	local owner = CreateFrame("Button", nil, UIParent)
	owner:SetSize(200, 24)
	-- A "menu" list whose rows have no label, opened first.
	local p = W.OpenPopup(owner, {
		style = "menu",
		rowHeight = ns.Style.SIZE.control,
		rows = function()
			return { { kind = "item", text = "Bare", value = 1 } }
		end,
		createItem = function() end,
		updateItem = function() end,
		onChoose = function() end,
	})
	local bareKey = p.poolKey
	W.ClosePopup()
	-- Then a dropdown (also "menu"): its rows have labels to fill.
	local chosen
	local dd = W.Dropdown(UIParent, {
		options = function()
			return { { text = "One", value = 1 }, { text = "Two", value = 2 } }
		end,
		get = function()
			return chosen
		end,
		set = function(v)
			chosen = v
		end,
	})
	choose(dd, "Two")
	T.eq(chosen, 2, "the dropdown's rows work")
	mock.Click(dd)
	T.ok(ns.Widgets.ActivePopup().poolKey ~= bareKey, "its own row pool")
	W.ClosePopup()
end)

case("Show location: pins the entrance and opens the map, right-click opens Getting there, greyed when off", function()
	openPlan("hall-of-thanes")
	local b = page().location
	page():Refresh()
	T.ok(b:IsShown() and b:IsEnabled(), "on for an instance with travel facts")
	T.ok(not b.art:IsDesaturated() and b.art:GetAlpha() == 1, "the pin in colour")
	T.eq(b.dpTooltipTitle, ns.L["Show location"])
	local loc = ns.GettingThere.Location(ns.Bundled.Get(ns.Bundled.PREFIX .. "hall-of-thanes"))
	T.ok(loc.zone and b.dpTooltipText:find(loc.zone, 1, true), "the tooltip names the zone")
	T.ok(b.dpTooltipText:find(ns.L["Click: show the entrance on the world map. Right-click or Shift-click: Getting there."],
		1, true), "and what a click does")
	-- Right after the instance picker, before the plan picker (the header's fit is checked by tests/ui_dump.lua's lint).
	T.eq(select(2, b:GetPoint(1)), page().instancePick, "after the instance picker")
	T.eq(select(2, page().planPick:GetPoint(1)), b, "before the plan picker")

	mock.waypoints, mock.openedMaps = {}, {}
	mock.Click(b)
	T.eq(#mock.waypoints, 1, "the game's pin")
	T.eq(#mock.openedMaps, 1, "the world map opened")
	T.eq(mock.openedMaps[1], mock.waypoints[1].uiMapID, "on the entrance's map")

	mock.Click(b, "RightButton")
	T.ok(ns.GettingThere.Window() and ns.GettingThere.Window():IsShown(), "right-click: the Getting there window")
	ns.GettingThere.Window():Hide()
	mock.openedMaps = {}
	mock.WithInput({ keys = { "SHIFT" } }, mock.Click, b)
	T.ok(ns.GettingThere.Window():IsShown(), "Shift-click too")
	T.eq(#mock.openedMaps, 0, "and no map")
	ns.GettingThere.Window():Hide()

	-- Combat: off and greyed, and says so; on again after it.
	mock.FireEvent("PLAYER_REGEN_DISABLED")
	T.ok(not b:IsEnabled(), "off in combat")
	T.ok(b.art:IsDesaturated() and b.art:GetAlpha() < 1, "the pin greyed")
	T.eq(b.dpTooltipText, ns.L["Not available in combat."])
	mock.inCombat = true
	mock.openedMaps = {}
	mock.Click(b)
	T.eq(#mock.openedMaps, 0, "a click in combat does nothing")
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.ok(b:IsEnabled() and not b.art:IsDesaturated(), "on again after combat")

	-- Dead: off with its own reason, on again when alive.
	_G.UnitIsDeadOrGhost = function()
		return true
	end
	mock.FireEvent("PLAYER_DEAD")
	T.ok(not b:IsEnabled(), "off while dead")
	T.eq(b.dpTooltipText, ns.L["Not available while dead."])
	_G.UnitIsDeadOrGhost = function()
		return false
	end
	mock.FireEvent("PLAYER_UNGHOST")
	T.ok(b:IsEnabled(), "on again once alive")

	-- The gamepad interface style: the pin only, and the hint says so.
	ns.Compat.Gamepad = function()
		return true
	end
	page():Refresh()
	T.ok(b.dpTooltipText:find("gamepad", 1, true), b.dpTooltipText)
	mock.waypoints, mock.openedMaps = {}, {}
	mock.Click(b)
	T.eq(#mock.waypoints, 1, "the pin")
	T.eq(#mock.openedMaps, 0, "no world map")
	-- Neither a pin nor the map: a click opens Getting there.
	local canPin = ns.Navigation.CanPin
	ns.Navigation.CanPin = function()
		return false
	end
	page():Refresh()
	ns.Navigation.CanPin = canPin
	T.eq(b.dpTooltipText:match("[^\n]*$"), ns.L["Click: open Getting there (the game can neither pin nor show this entrance)."])
	ns.Navigation.CanPin = function()
		return false
	end
	mock.Click(b)
	ns.Navigation.CanPin = canPin
	T.ok(ns.GettingThere.Window():IsShown(), "the Getting there window instead")
	ns.Compat.Gamepad = function()
		return false
	end

	-- An instance without a travel record: off, with the reason.
	T.eq(ns.GettingThere.Location({ name = "Nowhere Keep", kind = "dungeon" }).state, "unknown")
	ns.Travel.For = function()
		return nil
	end
	page():Refresh()
	T.ok(not b:IsEnabled(), "off without travel facts")
	T.eq(b.dpTooltipText, ns.L["Dungeon Planner has no travel facts for this instance."])
end)
