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

		-- The player scrolls away from the current step: a refresh leaves the list there.
		steps:ScrollTo(1)
		T.eq(steps.offset, 0, "scrolled back to the top")
		ns.UI.RefreshPage()
		page.side:Refresh()
		T.eq(steps.offset, 0, "a refresh does not snap back to the current step")
		-- Another current step (run mode's Next, a click): the list follows it.
		ns.UI.FocusStep(last - 1, { stay = true })
		T.ok(shownRow(steps, last - 1) and steps.offset > 0, "a new current step is scrolled into view")
	end)
end)

T.case("Scroll: the same owner with fewer items clamps the offset instead of resetting it", function()
	boot()
	local list = W.List(UIParent, { rowHeight = 20, create = function() end, update = function() end })
	list:SetSize(200, 100) -- five rows in view
	local function items(n)
		local out = {}
		for i = 1, n do
			out[i] = { i }
		end
		return out
	end
	list:SetItems(items(30), "plan-a")
	list:ScrollTo(30)
	T.eq(list.offset, 25, "at the end")
	T.eq(list:SetItems(items(10), "plan-a"), false, "the same owner")
	T.eq(list.offset, 5, "ten items: clamped to the last five, not back to the top")
	list:SetItems(items(3), "plan-a")
	T.eq(list.offset, 0, "three fit")
	T.eq(list:SetItems(items(30), "plan-b"), true, "another owner")
	list:Hide()
end)

T.case("Scroll: Home's lists start at the top for another tab or search and keep their place on a refresh", function()
	boot()
	ns.UI.GoHome("dungeons")
	local home = _G.DungeonPlannerMainFrame.home
	local list = home.list
	T.ok(#list.items > #list.rows, "the dungeons are longer than the list")
	list:ScrollTo(#list.items)
	local at = list.offset
	T.ok(at > 0, "scrolled down")
	home:Refresh()
	T.eq(list.offset, at, "a refresh keeps the offset")
	ns.UI.GoHome("raids")
	ns.UI.GoHome("dungeons")
	T.eq(list.offset, 0, "back from another tab: the top")
	list:ScrollTo(#list.items)
	local search = ns.UI.ctx.search
	ns.UI.ctx.search = "e"
	home:Refresh()
	T.ok(#list.items > #list.rows, "the search still lists many")
	T.eq(list.offset, 0, "another search: the top")
	ns.UI.ctx.search = search
	home:Refresh()
end)

T.case("Scroll: the Runs list starts at the top when the plan lists another wing's runs", function()
	boot()
	local R, RunLog = ns.Recorder, ns.RunLog
	R.SetEnabled(false)
	R.ClearHistory()
	local iid = ns.TravelData.instances["Scarlet Monastery: Library"].iid
	local shared = tostring(iid)
	-- A plan whose wing is unclear lists its instance's runs and every wing's.
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Some wing",
		instance = { name = "Scroll Monastery", kind = "dungeon", instanceMapID = iid } }))
	local store = R.Store()
	local libKey, armKey = RunLog.WingKey(shared, "scarletmonasterylibrary"), RunLog.WingKey(shared, "scarletmonasteryarmory")
	local function record(key, at)
		local run = RunLog.Enter(store, key, "Scarlet Monastery", 1, at)
		RunLog.PullStart(run, at + 1)
		RunLog.Observe(run, { { level = 30, class = "elite" } })
		RunLog.PullEnd(run, at + 20, 0, false)
		RunLog.Finish(store, at + 60)
	end
	local ok, err = pcall(function()
		for i = 1, 18 do
			record(libKey, ns.Now() - 100000 + i * 1000)
		end
		ns.UI.SelectPlan(plan.id)
		ns.UI.SelectTab("runs")
		local runs = _G.DungeonPlannerMainFrame.instancePage.panels.runs.inner.runs
		T.ok(#runs.items > #runs.rows, "more runs than rows")
		runs:ScrollTo(#runs.items)
		local at = runs.offset
		T.ok(at > 0, "scrolled down")
		ns:Fire("RECORDER_CHANGED")
		T.eq(runs.offset, at, "a refresh with the same wings keeps the offset")
		record(armKey, ns.Now() - 1000)
		ns:Fire("RECORDER_CHANGED")
		T.ok(#runs.items > #runs.rows, "still a long list")
		T.eq(runs.offset, 0, "another wing's runs listed: the top")
	end)
	R.ClearHistory()
	ns.DB.DeletePlan(plan.id)
	assert(ok, err)
end)

-- The mock's edit boxes never hold the focus; give one the game's behaviour (ClearFocus reports the focus loss).
local function focus(edit)
	local focused = true
	edit.HasFocus = function()
		return focused
	end
	edit.ClearFocus = function(self)
		if focused then
			focused = false
			mock.FireScript(self, "OnEditFocusLost")
		end
	end
	mock.FireScript(edit, "OnEditFocusGained")
end

T.case("Scroll: a multi-line field keeps its place for the same owner, never loses typing, and resets for another", function()
	boot()
	local committed
	local field = W.MultiLine(UIParent, { onCommit = function(text)
		committed = text
	end })
	field:SetSize(200, 60)
	local long = string.rep("A line of notes\n", 30)
	field:SetValue(long, "plan-a")
	field.scroll:SetVerticalScroll(80)
	field:SetValue(long, "plan-a")
	T.eq(field.scroll:GetVerticalScroll(), 80, "the same text again: the offset stays")
	field:SetValue(long, "plan-b")
	T.eq(field.scroll:GetVerticalScroll(), 0, "the same text of another plan: from the top")
	-- Typing, then a refresh of the same plan brings other text (a plan arriving): what is typed stays and is saved.
	focus(field.edit)
	field.edit:SetText("typed")
	field:SetValue("from elsewhere", "plan-b")
	T.eq(field.edit:GetText(), "typed", "the text being typed stays")
	field.edit:ClearFocus()
	T.eq(committed, "typed", "leaving the field saves it")
	-- Another plan replaces even a focused field's text.
	focus(field.edit)
	field.edit:SetText("half typed")
	field:SetValue("plan c's text", "plan-c")
	T.eq(field.edit:GetText(), "plan c's text", "another owner gets its own text")
	field.edit:ClearFocus()
	-- A box that saves nothing (import) takes the text its own action sets, focused or not.
	local box = W.MultiLine(UIParent, {})
	focus(box.edit)
	box.edit:SetText("!DP1!pasted")
	box:SetValue("")
	T.eq(box.edit:GetText(), "", "an import box is cleared after its import")
	field:Hide()
	box:Hide()
end)

T.case("Scroll: the Bosses edit form starts at the top for another boss or plan and keeps its place on a refresh", function()
	withPlans(function(a, b)
		for _, p in ipairs({ a, b }) do
			for i = 1, 3 do
				local enc = ns.Plan.AddEncounter(p, { name = "Boss " .. i })
				for j = 1, 6 do
					ns.Plan.AddPhase(p, enc.id, "Phase " .. j)
				end
			end
		end
		ns.UI.SelectPlan(a.id)
		ns.UI.SelectTab("encounters")
		local panel = _G.DungeonPlannerMainFrame.instancePage.panels.encounters.inner
		local area = panel.area
		panel:Refresh()
		area:SetVerticalScroll(40)
		T.eq(area:GetVerticalScroll(), 40, "scrolled down")
		panel:Refresh()
		T.eq(area:GetVerticalScroll(), 40, "a refresh keeps the offset")
		local second = shownRow(panel.list, 2)
		T.ok(second, "the second boss's row")
		mock.Click(second)
		T.eq(area:GetVerticalScroll(), 0, "another boss: the top")
		area:SetVerticalScroll(40)
		ns.UI.SelectPlan(b.id)
		T.eq(area:GetVerticalScroll(), 0, "another plan: the top")
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
