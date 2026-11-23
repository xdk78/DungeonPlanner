-- Scroll owners (UI/Containers.lua): a list or document starts at the top when what it shows changes (another plan,
-- boss, floor or filter) and keeps its offset on a refresh of the same; the side panel's steps keep the current step in
-- view instead.
local T = ...
local ns, mock = T.ns, T.mock
local W = ns.Widgets

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

-- An own plan whose steps (one per pull) and gear (label-only entries: no item lookups) are longer than their lists.
local function longPlan(name)
	local pulls = {}
	for i = 1, 40 do
		pulls[i] = { id = "u" .. i, name = "Pack " .. i }
	end
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = name, instance = { name = "Scroll Keep", kind = "dungeon" },
		pulls = pulls }))
	for i = 1, 120 do
		ns.Plan.AddGear(plan, { label = "Item " .. i })
	end
	return plan
end

-- Two such plans for one case; the plan selected before comes back afterwards and the two are deleted, so no other
-- file meets them (some pick the first own plan).
local function withPlans(fn)
	boot()
	local before, tab, step = ns.db.ui.selectedPlan, ns.db.ui.tab, ns.db.ui.step
	local a, b = longPlan("Scroll A"), longPlan("Scroll B")
	ns.db.ui.step = nil
	local ok, err = pcall(fn, a, b, _G.DungeonPlannerMainFrame.instancePage)
	ns.db.ui.tab, ns.db.ui.step = tab, step
	ns.UI.SelectPlan(before)
	ns.DB.DeletePlan(a.id)
	ns.DB.DeletePlan(b.id)
	assert(ok, err)
end

-- Pick the first option of a dropdown that `wanted(value)` accepts, through its popup list.
local function choose(dropdown, wanted)
	mock.Click(dropdown)
	local popup = W.ActivePopup()
	assert(popup, "the dropdown opens")
	for i, row in ipairs(popup.rows) do
		if wanted(row.value) then
			popup:Choose(i)
			return
		end
	end
	error("no such option")
end

-- The row showing item `index`, when one shows it.
local function shownRow(list, index)
	for _, row in ipairs(list.rows) do
		if row:IsShown() and row.index == index then
			return row
		end
	end
	return nil
end

T.case("Scroll: another plan opens Gear and Steps at the top; a refresh of the same plan keeps the offset", function()
	withPlans(function(a, b, page)
		ns.UI.SelectPlan(a.id)
		ns.UI.SelectTab("gear")
		local steps, gear = page.side.list, page.panels.gear.inner
		T.ok(#steps.items > #steps.rows, "the steps are longer than their list")
		T.ok(#gear.list.items > #gear.list.rows, "the gear lines are longer than theirs")
		steps:ScrollTo(#steps.items)
		gear.list:ScrollTo(#gear.list.items)
		local stepsAt, gearAt = steps.offset, gear.list.offset
		T.ok(stepsAt > 0 and gearAt > 0, "both scrolled down")

		-- A plain refresh (data arriving, a setting changed, the page drawn again): nothing moves.
		ns.UI.RefreshPage()
		gear:Refresh()
		T.eq(steps.offset, stepsAt, "a refresh keeps the steps' offset")
		T.eq(gear.list.offset, gearAt, "and the gear list's")
		-- Gear: another filter is another list, from the top (a class filter keeps these entries: they name no class).
		choose(gear.class, function(value)
			return value ~= false
		end)
		T.ok(#gear.list.items > #gear.list.rows, "still a long list")
		T.eq(gear.list.offset, 0, "another gear filter starts at the top")
		choose(gear.class, function(value)
			return value == false
		end)

		ns.UI.SelectPlan(b.id)
		T.eq(ns.db.ui.tab, "gear", "the same section")
		T.eq(steps.offset, 0, "another plan's steps start at the top")
		T.eq(gear.list.offset, 0, "and its gear")
		T.ok(shownRow(steps, 1) and shownRow(gear.list, 1), "the first rows show")
		-- Back to the first plan: a switch, not a refresh, so the top again.
		gear.list:ScrollTo(#gear.list.items)
		ns.UI.SelectPlan(a.id)
		T.eq(gear.list.offset, 0, "switching back starts at the top too")
	end)
end)

T.case("Scroll: after a plan switch the current step is scrolled into view and is the one highlight", function()
	withPlans(function(a, b, page)
		ns.UI.SelectPlan(b.id)
		local steps = page.side.list
		local last = #steps.items
		ns.UI.FocusStep(last, { stay = true })
		T.ok(shownRow(steps, last), "the current step shows")
		ns.UI.SelectPlan(a.id)
		T.eq(ns.UI.ctx:StepIndex(), nil, "this plan has no current step")
		T.eq(steps.offset, 0, "so its steps start at the top")
		ns.UI.SelectPlan(b.id)
		T.eq(ns.UI.ctx:StepIndex(), last, "the other plan's current step")
		local row = shownRow(steps, last)
		T.ok(row, "is in view after the switch, not the top")
		T.ok(steps.offset > 0, "the list scrolled to it")
		for _, r in ipairs(steps.rows) do
			T.eq(r.dpSelected == true, r == row, "one highlight: the current step's row")
		end
	end)
end)

T.case("Scroll: a document keeps its offset for the same owner and starts at the top for another", function()
	boot()
	local doc = W.Document(UIParent)
	doc:SetSize(300, 120)
	local function fill(owner)
		doc:Begin(owner)
		for i = 1, 60 do
			doc:Add("text", "Line " .. i)
		end
		doc:Finish()
	end
	fill("plan-a")
	doc:SetVerticalScroll(200)
	fill("plan-a")
	T.eq(doc:GetVerticalScroll(), 200, "the same owner: the offset stays")
	fill("plan-b")
	T.eq(doc:GetVerticalScroll(), 0, "another owner: the top")
	doc:SetVerticalScroll(200)
	fill(nil)
	T.eq(doc:GetVerticalScroll(), 0, "no owner: the top every time")
	-- A scroll area alike.
	local area = W.ScrollArea(UIParent)
	area:SetSize(300, 120)
	area:SetContentHeight(1000)
	area:SetOwner("plan-a")
	area:SetVerticalScroll(300)
	area:SetOwner("plan-a")
	T.eq(area:GetVerticalScroll(), 300, "area: the same owner keeps the offset")
	area:SetOwner("plan-b")
	T.eq(area:GetVerticalScroll(), 0, "area: another owner, the top")
	doc:Hide()
	area:Hide()
end)
