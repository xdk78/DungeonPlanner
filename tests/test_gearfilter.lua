-- The Gear page's filters (Model/GearFilter.lua, Data/Loot.lua's item types, UI/Panels/GearPanel.lua), driven through
-- the dropdowns' own clicks and the popup's rows, and the header's Show location button (UI/InstancePage.lua,
-- UI/GettingThere.lua).
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

local function page()
	return _G.DungeonPlannerMainFrame.instancePage
end

-- WoW: Forever's Adventure Guide is empty: the drops come from the bundled boss data, as in game.
local realHasData = ns.Journal.HasData
local function noJournal(on)
	ns.Journal.HasData = on and function()
		return false
	end or realHasData
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

-- Open a dropdown with its own click and click the popup row showing `text`.
local function choose(dd, text)
	dd:GetScript("OnClick")(dd, "LeftButton")
	local p = ns.Widgets.ActivePopup()
	T.ok(p and p.owner == dd, "the dropdown's list is open")
	for _, f in ipairs(p.pools[p.spec.style].item) do
		if f:IsShown() and f.label and f.label:GetText() == text then
			f:GetScript("OnClick")(f, "LeftButton")
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

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end

T.case("GearFilter: what a class can equip, cloaks and non-equipment for everyone, unknown items unknown", function()
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
end)

T.case("Gear filters: the class, boss and slot dropdowns change the drops listed; uncached items join once loaded", function()
	noJournal(true)
	local plan = openPlan("wailing-caverns")
	local cobrahn = plan.encounters[2]
	local drops = ns.BossData.Loot(plan, cobrahn)
	T.ok(drops and #drops >= 2, "Lord Cobrahn has bundled drops")
	-- Cobrahn's first drop leather legs, his second a mail belt; every other drop a wand.
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

	ns.UI.SelectTab("gear")
	local gear = page().panels.gear.inner
	gear:Refresh()
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
	T.ok(not his[others[1]] or count(his) < total, "not the other bosses'")
	T.eq(count(his), #drops)
	-- One slot, by the item's type.
	choose(gear.slot, ns.L["slot:LEGS"])
	local onlyLegs = shown(gear)
	T.ok(onlyLegs[legs] and not onlyLegs[belt], "only the legs")
	choose(gear.slot, ns.L["All slots"])
	choose(gear.encounter, ns.L["Whole instance"])

	-- An item the client has no data for yet: left out of a filtered list, asked for, and in once it arrives.
	local items = _G.C_Item
	local savedName, savedRequest = items.GetItemNameByID, items.RequestLoadItemDataByID
	local requested = {}
	items.RequestLoadItemDataByID = function(id)
		requested[id] = (requested[id] or 0) + 1
	end
	items.GetItemNameByID = function(id)
		if id == legs and mock.itemTypes[legs] == false then
			return nil
		end
		return "Real " .. id
	end
	ns.Names.ResetItems()
	mock.itemTypes[legs] = false
	choose(gear.class, "Warrior")
	T.ok(not shown(gear)[legs], "not listed while its type is unknown")
	T.eq(requested[legs], 1, "asked for once")
	T.eq(gear.status:GetText(), ns.L["Loading items..."], "says it is loading")
	mock.itemTypes[legs] = { "INVTYPE_LEGS", 4, 2 }
	mock.FireEvent("ITEM_DATA_LOAD_RESULT", legs, true)
	for _ = 1, 8 do
		mock.Advance(0.25)
	end
	T.ok(shown(gear)[legs], "listed once it arrived (one redraw, ITEMS_READY)")
	T.ok(gear.status:GetText() ~= ns.L["Loading items..."], "no longer loading")
	T.eq(requested[legs], 1, "no more asks")

	choose(gear.class, "All classes")
	items.GetItemNameByID, items.RequestLoadItemDataByID = savedName, savedRequest
	ns.Names.ResetItems()
	mock.itemTypes = {}
	noJournal(false)
end)

T.case("Gear filters: the role filter is off on a read-only plan whose entries name no role, and says why", function()
	noJournal(true)
	openPlan("wailing-caverns")
	ns.UI.SelectTab("gear")
	local gear = page().panels.gear.inner
	gear:Refresh()
	T.ok(not gear.role:IsEnabled(), "nothing to filter by role")
	T.ok(gear.role.dpTooltipText:find("no role", 1, true), gear.role.dpTooltipText)
	-- An own plan: the role tags the plan's own entries (and the add form's).
	local wc = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns")
	local editable = ns.DB.AddPlan(ns.Plan.New({ name = "Mine", instance = ns.Util.DeepCopy(wc.instance) }))
	T.ok(editable, "an own plan")
	ns.Plan.AddGear(editable, { label = "Tank shield", role = "TANK", priority = 1 })
	ns.Plan.AddGear(editable, { label = "Healer mace", role = "HEALER", priority = 1 })
	ns.UI.SelectPlan(editable.id)
	ns.UI.SelectTab("gear")
	gear:Refresh()
	T.ok(gear.role:IsEnabled(), "on for an editable plan")
	choose(gear.role, ns.L["Tank"])
	local labels = {}
	for _, e in ipairs(gear.entries) do
		if e.gear then
			labels[e.gear.label] = true
		end
	end
	T.ok(labels["Tank shield"] and not labels["Healer mace"], "the plan's own entries by role")
	choose(gear.role, ns.L["All roles"])
	noJournal(false)
end)

T.case("Show location: the header button pins the entrance and opens the map, right-click opens Getting there", function()
	openPlan("hall-of-thanes")
	local b = page().location
	page():Refresh()
	T.ok(b:IsShown() and b:IsEnabled(), "on for an instance with travel facts")
	T.eq(b.dpTooltipTitle, ns.L["Show location"])
	local loc = ns.GettingThere.Location(ns.UI.Plan and ns.UI.Plan() or ns.Bundled.Get(ns.Bundled.PREFIX .. "hall-of-thanes"))
	T.ok(loc.zone and b.dpTooltipText:find(loc.zone, 1, true), "the tooltip names the zone")
	T.ok(b.dpTooltipText:find("Right-click", 1, true), "and the hint")
	-- Right after the instance picker, before the plan picker (the header's fit is checked by tests/ui_dump.lua's lint).
	T.eq(select(2, b:GetPoint(1)), page().instancePick, "after the instance picker")
	T.eq(select(2, page().planPick:GetPoint(1)), b, "before the plan picker")

	mock.waypoints, mock.openedMaps = {}, {}
	b:GetScript("OnClick")(b, "LeftButton")
	T.eq(#mock.waypoints, 1, "the game's pin")
	T.eq(#mock.openedMaps, 1, "the world map opened")
	T.eq(mock.openedMaps[1], mock.waypoints[1].uiMapID, "on the entrance's map")

	local w = ns.GettingThere.Window()
	if w then
		w:Hide()
	end
	b:GetScript("OnClick")(b, "RightButton")
	T.ok(ns.GettingThere.Window() and ns.GettingThere.Window():IsShown(), "right-click: the Getting there window")
	ns.GettingThere.Window():Hide()
	local realShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function()
		return true
	end
	mock.openedMaps = {}
	b:GetScript("OnClick")(b, "LeftButton")
	_G.IsShiftKeyDown = realShift
	T.ok(ns.GettingThere.Window():IsShown(), "Shift-click too")
	T.eq(#mock.openedMaps, 0, "and no map")
	ns.GettingThere.Window():Hide()

	-- Combat: off, and says so; on again after it.
	mock.FireEvent("PLAYER_REGEN_DISABLED")
	T.ok(not b:IsEnabled(), "off in combat")
	T.eq(b.dpTooltipText, ns.L["Not available in combat."])
	mock.inCombat = true
	mock.openedMaps = {}
	b:GetScript("OnClick")(b, "LeftButton")
	T.eq(#mock.openedMaps, 0, "a click in combat does nothing")
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.ok(b:IsEnabled(), "on again after combat")

	-- An instance without a travel record: off, with the reason.
	local loc2 = ns.GettingThere.Location({ name = "Nowhere Keep", kind = "dungeon" })
	T.eq(loc2.state, "unknown")
	local realFor = ns.Travel.For
	ns.Travel.For = function()
		return nil
	end
	page():Refresh()
	T.ok(not b:IsEnabled(), "off without travel facts")
	T.eq(b.dpTooltipText, ns.L["Dungeon Planner has no travel facts for this instance."])
	ns.Travel.For = realFor
	page():Refresh()
	T.ok(b:IsEnabled())
end)
