-- The main window: a war table, as a raid leader would brief from.
--   header      emblem and title • (instance page) back, instance and plan pickers, plan menu, undo • settings, close
--   body        Home (UI/Home.lua): the instance table and a preview of the selected instance
--               Instance page (UI/InstancePage.lua): the plan's steps and party on the left, the section (the map by
--               default) filling the rest
--   bottom bar  Home: New plan, Current location, Custom map. Instance page: the sections (Map, Bosses, Pulls, Party,
--               Gear, Share, Notes) and Run mode. On the right: version and status.
-- Built on first open, never at login. Panels live in UI/Panels/*.lua and register in ns.Panels with
-- Create(parent, ctx) returning a frame with :Refresh(). `ctx` is the shared view state.

local _, ns = ...
local UI = ns:NewModule("UI")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

ns.Panels = ns.Panels or {}

-- Home segments.
UI.HOME_TABS = {
	{ id = "dungeons", text = "Dungeons" },
	{ id = "raids", text = "Raids" },
	{ id = "plans", text = "My plans" },
	{ id = "shared", text = "Shared" },
}

-- Sections of an instance page, in bar order. Old tab names (saved by earlier versions) map onto them.
UI.SECTIONS = {
	{ id = "map", text = "Map", art = "sectionMap" },
	{ id = "encounters", text = "Bosses", art = "sectionBosses" },
	{ id = "pulls", text = "Pulls", art = "sectionPulls" },
	{ id = "assignments", text = "Party", art = "sectionAssignments" },
	{ id = "gear", text = "Gear", art = "sectionGear" },
	{ id = "runs", text = "Runs", art = "sectionRuns" },
	{ id = "share", text = "Share", art = "sectionShare" },
	{ id = "plan", text = "Notes", art = "sectionPlan" },
}
local SECTION_ALIAS = { notes = "plan", progress = "plan", bosses = "encounters", party = "assignments" }

-- Context ----------------------------------------------------------------------------------------------------------------

local ctx = {
	floor = 1,
	tool = "select",
	kind = "pack",
	role = "TANK",
	selectedMarker = nil,
	focusPull = nil,
	focusEncounter = nil,
	focusSegment = nil, -- the focused step's route segment { route, from, to }
	currentPull = nil,
	activeRoute = nil,
	showLabels = true,
	search = "",
}
UI.ctx = ctx

function ctx:Plan()
	return ns.DB.GetPlan(ns.db.ui.selectedPlan)
end

-- The instance page's instance: { key, name, kind, ejInstanceID?, uiMapID?, levelMin?, levelMax? }.
function ctx:Instance()
	return ns.db.ui.instance
end

-- Refresh passes. One edit reaches a section through several paths (the page refresh, the section shown, its own
-- OnShow); inside UI.Batch a section that asks UI.Deferred(self) is only marked, and each marked one refreshes once
-- (self:RefreshNow()) when the outermost pass ends, before UI.Batch returns: in the same frame, still synchronous.
local batchDepth, batchOrder, batched = 0, {}, {}
function UI.Batch(fn, ...)
	batchDepth = batchDepth + 1
	ns.SafeCall(fn, ...)
	batchDepth = batchDepth - 1
	if batchDepth == 0 then
		local i = 1
		while batchOrder[i] do -- a refresh may mark another one
			local target = batchOrder[i]
			batched[target] = nil
			ns.SafeCall(target.RefreshNow, target)
			i = i + 1
		end
		batchOrder = {}
	end
end

-- Inside a pass: mark `target` for one refresh at its end and return true. Outside one: false (refresh now).
function UI.Deferred(target)
	if batchDepth == 0 then
		return false
	end
	if not batched[target] then
		batched[target] = true
		batchOrder[#batchOrder + 1] = target
	end
	return true
end

-- The plan's steps (Model/Steps.lua), rebuilt after any change to the plan.
local stepsCache = { planId = nil, list = nil }
function ctx:Steps()
	local plan = self:Plan()
	if not plan then
		return {}
	end
	if stepsCache.planId ~= plan.id or not stepsCache.list then
		stepsCache.planId, stepsCache.list = plan.id, ns.Steps.Build(plan)
	end
	return stepsCache.list
end

-- Every floor the map can show for the selected plan: its own, then the instance's other map art (Data/Floors.lua).
function ctx:Floors()
	return ns.Floors.For(self:Plan())
end

-- Put something on the current floor: `add(floor)` adds it and returns it (or nil and an error). A floor the map adds
-- becomes the own plan's first (Floors.Ensure), and stops being the plan's again when the add fails.
function ctx:AddOnFloor(add)
	local plan = self:Plan()
	local before = plan and not self:ReadOnly() and ns.Floors.Ensure(plan, self.floor) or nil
	local result, err = add(self.floor)
	if not result and before then
		ns.Floors.Unensure(plan, before)
	end
	return result, err
end

-- The current step of the selected plan (index), or nil before one is chosen.
function ctx:StepIndex()
	local plan = self:Plan()
	local s = ns.db.ui.step
	if plan and type(s) == "table" and s.plan == plan.id and type(s.index) == "number" then
		local n = #self:Steps()
		if n == 0 then
			return nil
		end
		return math.max(1, math.min(n, s.index))
	end
	return nil
end

-- Undo and redo (Model/History.lua): copies of the selected plan, taken after each change, 50 steps. Every edit (map,
-- drawings, pulls, steps, notes, bosses, party, gear) goes through ctx:Changed, so they all share one history. Kept in
-- memory only; selecting another plan starts a new history.
local history = ns.History.New(ns.History.MAX)
UI.history = history

local function resetUndo(plan)
	ns.History.Reset(history, plan and plan.id or nil, plan and not plan.bundled and ns.Util.DeepCopy(plan) or nil)
end

function ctx:Changed(what)
	local plan = self:Plan()
	if not plan or plan.bundled then
		return
	end
	ns.History.Record(history, plan.id, ns.Util.DeepCopy(plan))
	ns.DB.Changed(plan, what)
end

function ctx:CanUndo()
	local plan = self:Plan()
	return plan ~= nil and ns.History.CanUndo(history, plan.id) and ns.DB.IsEditable(plan)
end

function ctx:CanRedo()
	local plan = self:Plan()
	return plan ~= nil and ns.History.CanRedo(history, plan.id) and ns.DB.IsEditable(plan)
end

-- Restore in place: the plan table stays the same object (it is referenced by id from the store).
local function restore(self, plan, state, what)
	for k in pairs(plan) do
		plan[k] = nil
	end
	for k, v in pairs(ns.Util.DeepCopy(state)) do
		plan[k] = v
	end
	self.selectedMarker, self.selectedShape = nil, nil
	ns.DB.Changed(plan, what)
end

function ctx:Undo()
	if self:CanUndo() then
		restore(self, self:Plan(), ns.History.Undo(history), "undo")
	end
end

function ctx:Redo()
	if self:CanRedo() then
		restore(self, self:Plan(), ns.History.Redo(history), "redo")
	end
end

-- Read-only: the saved data is from a newer version, or the plan is a recommended (bundled) one.
function ctx:ReadOnly()
	local plan = self:Plan()
	return ns.DB.IsReadOnly() or (plan ~= nil and plan.bundled == true)
end

function ctx:ShowTab(id)
	UI.SelectTab(id)
end

-- Frame ------------------------------------------------------------------------------------------------------------------

local frame

-- An instance entry for a plan (the instance page it belongs on).
function UI.EntryForPlan(plan)
	local inst = plan.instance
	local key = ns.DB.InstanceKey(inst)
	local journal = ns.Instances.Get(key)
	if journal then
		return journal
	end
	-- A plan without journal IDs (a recommended one) opens its journal instance's page when the match is sure.
	local resolved, score = ns.Journal.ResolveInstance(inst)
	if resolved and score >= 75 then
		return resolved
	end
	return {
		key = key,
		name = ns.Names.Instance(inst),
		kind = inst.kind,
		ejInstanceID = inst.ejInstanceID,
		uiMapID = inst.uiMapID,
		levelMin = inst.levelMin,
		levelMax = inst.levelMax,
	}
end

-- A plan's name for lists and the plan picker: a recommended plan gets the raid star and "(recommended)".
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t "
function UI.PlanTitle(plan)
	if plan and plan.bundled then
		return STAR .. string.format(L["%s (recommended)"], plan.name)
	end
	return plan and plan.name or ""
end

-- Where a plan comes from, for the plan picker's tooltip and the Notes section: a short line and the full lines.
-- A recommended plan names its source, data revision and data date (the date of its research data, written by
-- tools/gen_plans.lua); a copy of one names the plan it is based on and says when a newer revision exists; a shared
-- plan names who sent it. nil for a plan of your own with no history.
local function day(t)
	if type(t) == "number" and t > 0 and type(date) == "function" then
		return date("%Y-%m-%d", t)
	end
	return nil
end

-- The credit line of a recommended plan's route ("Route: Forever Dungeon Routes (MIT), by ..."), from its notes.
local function routeCredit(plan)
	for paragraph in ((plan.notes or "") .. "\n\n"):gmatch("(.-)\n\n") do
		if paragraph:match("^Route: ") then
			return paragraph
		end
	end
	return nil
end

-- A recommended plan researched well before the game build the player runs (Bundled.Stale): one line that says so,
-- with the build's date; nil otherwise, or when the client's build date cannot be read.
function UI.StaleLine(plan)
	local stale, build = ns.Bundled.Stale(plan and plan.updated, ns.Compat.ClientInfo().date)
	if not stale then
		return nil
	end
	return string.format(L["Researched before this game build (%s): the route and pulls may have changed. Check them in game."], build)
end

function UI.PlanSource(plan)
	if not plan then
		return nil
	end
	local lines = {}
	local short
	if plan.bundled then
		local confidence
		for _, tag in ipairs(plan.tags or {}) do
			confidence = confidence or tag:match("^confidence: (%a+)$")
		end
		local when = day(plan.updated)
		short = when and string.format(L["Recommended plan • revision %d • data from %s"], plan.rev or 1, when)
			or string.format(L["Recommended plan • revision %d"], plan.rev or 1)
		lines[#lines + 1] = string.format(L["Source: %s, community research with approximate positions."], plan.author)
		if confidence then
			lines[#lines + 1] = string.format(L["Confidence: %s"], L["confidence:" .. confidence])
		end
		lines[#lines + 1] = string.format(L["Data revision: %d"], plan.rev or 1)
		if when then
			lines[#lines + 1] = string.format(L["Data date: %s"], when)
		end
		local credit = routeCredit(plan)
		if credit then
			lines[#lines + 1] = credit
		end
		local stale = UI.StaleLine(plan)
		if stale then
			lines[#lines + 1] = stale
		end
		lines[#lines + 1] = L["Read-only: make an editable copy to change it."]
	elseif plan.origin and plan.origin.bundled then
		local base = ns.Bundled.Get("b:" .. plan.origin.bundled)
		local rev = plan.origin.rev or 1
		short = string.format(L["Based on a recommended plan (revision %d)"], rev)
		if base then
			lines[#lines + 1] = string.format(L["Based on the recommended plan \"%s\"."], base.name)
			local when = day(base.updated)
			if when then
				lines[#lines + 1] = string.format(L["Data date: %s"], when)
			end
			if (base.rev or 1) > rev then
				lines[#lines + 1] = string.format(L["A newer revision (%d) of it ships with this version."], base.rev)
			end
			local stale = UI.StaleLine(base)
			if stale then
				lines[#lines + 1] = stale
			end
		end
		lines[#lines + 1] = string.format(L["Copied at revision %d."], rev)
	elseif plan.source and plan.source.from then
		short = string.format(L["from %s"], plan.source.from)
		lines[#lines + 1] = string.format(L["Received from %s."], plan.source.from)
		local when = day(plan.source.at)
		if when then
			lines[#lines + 1] = string.format(L["Arrived on %s."], when)
		end
	else
		return nil
	end
	return short, lines
end

-- Plans for an instance entry: recommended first, then the player's (newest first).
function UI.PlansFor(entry)
	local out = {}
	for _, plan in ipairs(ns.Bundled.ForInstance(entry)) do
		out[#out + 1] = plan
	end
	for _, plan in ipairs(ns.DB.PlansFor(entry)) do
		out[#out + 1] = plan
	end
	return out
end

local function setView(view)
	ns.db.ui.view = view
	if not frame then
		return
	end
	frame.home:SetShown(view == "home")
	frame.home.actions:SetShown(view == "home")
	frame.instancePage:SetShown(view == "instance")
	frame.instancePage:ShowChrome(view == "instance")
	UI.RefreshFooter()
end

function UI.GoHome(tab)
	if tab then
		ns.db.ui.homeTab = tab
	end
	setView("home")
	if frame then
		frame.home:Refresh()
	end
end

-- Open an instance page. Keeps the selected plan when it belongs there; else the plan last chosen for this instance
-- (while it exists), else the newest own plan, else the first recommended one, else none (the page then offers to
-- create one).
function UI.OpenInstance(entry)
	ns.db.ui.instance = {
		key = entry.key,
		name = entry.name,
		kind = entry.kind,
		ejInstanceID = entry.ejInstanceID,
		uiMapID = entry.uiMapID,
		levelMin = entry.levelMin,
		levelMax = entry.levelMax,
	}
	ns.db.ui.homeSelected = entry.key
	local current = ctx:Plan()
	if not (current and ns.Bundled.SameInstance(current.instance, entry)) then
		local pick = UI.DefaultPlanFor(entry) -- UI/Portraits.lua
		UI.SelectPlan(pick and pick.id or nil, true)
	end
	setView("instance")
	UI.RefreshPage()
end

function UI.SelectTab(id)
	id = SECTION_ALIAS[id] or id
	ns.db.ui.tab = id
	if not frame then
		return
	end
	frame.instancePage:SelectSection(id)
	UI.RefreshFooter()
end

function UI.RefreshPage()
	if not frame or not frame:IsShown() then
		return
	end
	if ns.db.ui.view == "instance" and ns.db.ui.instance then
		frame.instancePage:Refresh()
	else
		frame.home:Refresh()
	end
	UI.RefreshFooter()
end

-- Older name, called by Boot after a profile change.
function UI.RefreshSidebar()
	UI.RefreshPage()
end

-- Select a plan. Without stayOnPage, also opens its instance page.
function UI.SelectPlan(id, stayOnPage)
	if ns.db.ui.selectedPlan ~= id then
		ns.Widgets.CommitFocus() -- text still being typed belongs to the plan being left
		ns.db.ui.selectedPlan = id
		ctx.floor, ctx.selectedMarker, ctx.focusPull, ctx.currentPull, ctx.activeRoute = 1, nil, nil, nil, nil
		ctx.focusEncounter, ctx.focusSegment, ctx.selectedShape = nil, nil, nil
		stepsCache.list = nil
		resetUndo(ns.DB.GetPlan(id))
		ns:FirePublic("DUNGEONPLANNER_ACTIVE_PLAN", id)
		ns:Fire("STEP_CHANGED")
	end
	local plan = ns.DB.GetPlan(id)
	if plan then
		ns.DB.RememberPlan(UI.EntryForPlan(plan).key, plan.id)
		-- Before the page draws its steps and pins: the bosses' portraits start loading now (UI/Portraits.lua).
		UI.PrefetchPortraits(plan)
	end
	if stayOnPage then
		return
	end
	if plan then
		UI.OpenInstance(UI.EntryForPlan(plan))
	elseif frame then
		UI.RefreshPage()
	end
end

-- Steps ---------------------------------------------------------------------------------------------------------------------
-- (How a step reads: UI/StepText.lua.)

-- Make step `index` current: the side panel, run mode and the map follow. opts.stay = keep the current section (run
-- mode and key bindings); otherwise the window switches to the map.
function UI.FocusStep(index, opts)
	opts = opts or {}
	local plan = ctx:Plan()
	if not plan then
		return
	end
	local list = ctx:Steps()
	if #list == 0 then
		ns.db.ui.step = nil
		return
	end
	index = math.max(1, math.min(#list, index or 1))
	ns.db.ui.step = { plan = plan.id, index = index }
	local focus = ns.Steps.Focus(list[index])
	ctx.focusPull, ctx.focusEncounter = focus.focusPull, focus.focusEncounter
	if focus.focusPull then
		ctx.currentPull = focus.focusPull
	end
	ctx.focusSegment = focus.route and { route = focus.route, from = focus.from, to = focus.to } or nil
	if focus.floor and plan.floors[focus.floor] then
		ctx.floor = focus.floor
	end
	ctx.selectedMarker = nil
	if frame and frame:IsShown() and ns.db.ui.view == "instance" then
		if not opts.stay and ns.db.ui.tab ~= "map" then
			UI.SelectTab("map")
		end
		frame.instancePage:FocusStep(list[index], focus)
	end
	ns:Fire("STEP_CHANGED")
end

-- Show floor `index` of the map (every floor the instance has, ctx:Floors()).
function UI.GoToFloor(index)
	if not ctx:Floors()[index] then
		return
	end
	if frame and frame:IsShown() and ns.db.ui.view == "instance" then
		UI.SelectTab("map")
		local map = frame.instancePage.panels.map
		if map then
			map:GoToFloor(index)
			return
		end
	end
	ctx.floor = index
end

-- Move the current step by delta (+1 / -1); the first step when none is current.
function UI.StepBy(delta, opts)
	local list = ctx:Steps()
	if #list == 0 then
		return nil
	end
	local current = ctx:StepIndex()
	local index = current and ns.Steps.Move(list, current, delta) or 1
	UI.FocusStep(index, opts)
	return index
end

-- Footer ----------------------------------------------------------------------------------------------------------------

function UI.RefreshFooter()
	if not frame then
		return
	end
	-- A packaged release says its version; a copy straight from the repository (the packager never replaced the
	-- version token) says so instead of "vdev".
	local parts = { ns.version == "dev" and L["dev build"] or ("v" .. tostring(ns.version)) }
	if ns.DB.IsReadOnly() then
		parts[#parts + 1] = L["read-only"]
	end
	-- The same number the "My plans" list shows (recommended plans are not counted: they are not yours).
	parts[#parts + 1] = string.format(L["My plans: %d"], #ns.DB.Plans())
	local status = frame.footer.status
	status:SetText(table.concat(parts, "  •  "))
	-- On a narrow window the sections and Run mode need the line: the status gives way.
	local page = frame.instancePage
	-- The game's window tabs hang under the window; only the drawn section bar shares this line.
	local sections = page.sectionBar.style == "bottom" and 0 or page.sectionBar:GetWidth()
	local need = sections + page.runButton:GetWidth() + (status:GetStringWidth() or 0) + 3 * SP.md
	local room = frame.footer:GetWidth()
	status:SetShown(ns.db.ui.view ~= "instance" or room <= 0 or need <= room)
end

-- Header ------------------------------------------------------------------------------------------------------------------

local function askReload()
	W.ShowDialog({
		title = L["Language"],
		-- Polish chosen but no Polish face loads: say so before the reload (UI/Fonts.lua).
		text = L["The new language is used after the interface reloads."] .. ns.Style.PolishFontNote(),
		buttons = {
			{
				L["Reload now"],
				function()
					-- Reloading is refused in combat (the click then does nothing at all): say how to do it by hand.
					if InCombatLockdown and InCombatLockdown() then
						ns:Print(L["You are in combat. Type /reload when it ends."])
					elseif type(ReloadUI) == "function" then
						ReloadUI()
					end
				end,
				true,
			},
			{ L["Later"] },
		},
	})
end

local function setLanguage(v)
	if ns.db.settings.locale ~= v then
		ns.db.settings.locale = v
		-- Fonts follow at once (a Polish choice needs the Polish face for the prompt below, too).
		ns.Style.SetupFonts()
		askReload()
	end
end
UI.SetLanguage = setLanguage

-- The settings button: a small menu with the options page and the language.
local function settingsMenu(owner)
	local items = { { title = ns.title } }
	items[#items + 1] = {
		L["Settings"],
		function()
			UI.OpenSettings()
		end,
	}
	items[#items + 1] = "-"
	items[#items + 1] = { title = L["Language"] }
	local choices = { { L["Automatic"], "auto" } }
	for _, entry in ipairs(ns.LOCALE_LIST) do
		choices[#choices + 1] = { entry[2], entry[1] }
	end
	for _, opt in ipairs(choices) do
		local mark = ns.db.settings.locale == opt[2] and "> " or "   "
		items[#items + 1] = {
			mark .. opt[1],
			function()
				setLanguage(opt[2])
			end,
		}
	end
	if not W.Menu(owner, items) then
		UI.OpenSettings()
	end
end

local function buildHeader(f)
	f.settings = W.IconButton(f.bar, "gear", L["Settings"], function(self)
		settingsMenu(self)
	end)
	f.settings:SetPoint("RIGHT", -f.barRightPad, 0)
	W.SetTooltip(f.settings, L["Settings"],
		L["Options and language. Automatic uses Polish when WoW Po Polsku is set to Polish, otherwise the game's language."],
		"below")
	-- Report a problem: left of the settings button (the page's own header controls end at this one).
	f.bug = W.IconButton(f.bar, "!", L["Report a problem"], function()
		ns.Report.Open()
	end)
	f.bug:SetPoint("RIGHT", f.settings, "LEFT", -SP.xs, 0)
	W.SetTooltip(f.bug, L["Report a problem"],
		L["Builds a text with your version, plan and the latest errors, to paste into a GitHub issue. No character, realm, guild or group details."],
		"below")
end

-- Build ------------------------------------------------------------------------------------------------------------------

local function build()
	frame = W.Window("DungeonPlannerMainFrame", ns.title, ns.db.ui, 880, 560)
	frame:SetScale(ns.db.settings.scale or 1)
	buildHeader(frame)

	-- The body and the bottom bar sit inside the window's frame (frame.insets) with one gap.
	local ins = frame.insets
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT", ins.left + SP.sm, ins.bottom + SP.sm)
	footer:SetPoint("BOTTOMRIGHT", -(ins.right + SP.sm + 16), ins.bottom + SP.sm) -- leave the size grip free
	footer:SetHeight(SZ.control + 4)
	footer.rule = S.Hairline(footer)
	footer.rule:SetPoint("TOPLEFT", 0, SP.xs)
	footer.rule:SetPoint("TOPRIGHT", 16, SP.xs)
	footer.status = W.Text(footer, "caption", "muted")
	footer.status:SetPoint("RIGHT", 0, 0)
	footer.status:SetJustifyH("RIGHT")
	frame.footer = footer

	-- Body: everything between the header and the bottom bar.
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", ins.left + SP.sm, -(ins.top + SP.sm))
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(ins.right + SP.sm), ins.bottom + SP.sm + SZ.control + 4 + SP.md)
	frame.body = body

	frame.home = ns.Home.Create(body, ctx, footer)
	frame.home:SetAllPoints()
	frame.instancePage = ns.InstancePage.Create(body, ctx, frame)
	frame.instancePage:SetAllPoints()
	frame.tabs = frame.home.tabs

	ns:On("PLAN_CHANGED", UI, function(plan, what)
		if plan.id == ns.db.ui.selectedPlan then
			stepsCache.list = nil
		end
		if not frame:IsShown() then
			return
		end
		if plan.id == ns.db.ui.selectedPlan and ns.db.ui.view == "instance" then
			UI.Batch(frame.instancePage.Refresh, frame.instancePage, what)
		elseif ns.db.ui.view == "home" and (what == "meta" or what == "markers" or what == "pulls") then
			frame.home:Refresh()
		end
	end)
	ns:On("PLANS_CHANGED", UI, function()
		stepsCache.list = nil
		if frame:IsShown() then
			UI.RefreshPage()
		end
	end)
	ns:On("PLAN_IMPORTED", UI, function(added)
		if frame:IsShown() and added[1] then
			UI.SelectPlan(added[1].id)
		end
	end)
	ns:On("PROGRESS_CHANGED", UI, function()
		if frame:IsShown() then
			UI.RefreshPage()
		end
	end)
	-- Item names that arrived from the client (Names.RequestItem): the open page redraws once with them.
	ns:On("ITEMS_READY", UI, function()
		if frame:IsShown() then
			UI.RefreshPage()
		end
	end)
	ns:On("STEP_CHANGED", UI, function()
		if frame:IsShown() and ns.db.ui.view == "instance" then
			frame.instancePage:RefreshSteps()
		end
	end)
	-- HookScript: the window's Escape handling (W.CloseOnEscape) hooks OnShow too.
	frame:HookScript("OnShow", function()
		if ns.db.ui.view == "instance" and ns.db.ui.instance then
			setView("instance")
		else
			setView("home")
		end
		UI.RefreshPage()
	end)
	frame:Hide()
end

function UI.Toggle()
	if not frame then
		build()
	end
	frame:SetShown(not frame:IsShown())
end

-- Open the window; with a section ("map", "share", ...) open the selected plan's page on it.
function UI.Show(tab)
	if not frame then
		build()
	end
	if tab then
		ns.db.ui.tab = SECTION_ALIAS[tab] or tab
		local plan = ctx:Plan()
		if plan then
			ns.db.ui.view = "instance"
			ns.db.ui.instance = UI.EntryForPlan(plan)
		end
	end
	frame:Show()
	if tab and ns.db.ui.view == "instance" then
		setView("instance")
		UI.RefreshPage()
	end
end

function UI.IsShown()
	return frame ~= nil and frame:IsShown()
end

function UI.ApplyScale()
	if frame then
		frame:SetScale(ns.db.settings.scale or 1)
	end
	if ns.RunMode then
		ns.RunMode.ApplyScale()
	end
	if ns.NotesFrame then
		ns.NotesFrame.ApplyScale()
	end
end

-- The colour-blind setting changed: everything that draws pull, route, drawing or role colours redraws.
function UI.ApplyColors()
	if frame and frame:IsShown() then
		UI.RefreshPage()
	end
	if ns.RunMode then
		ns.RunMode.Refresh()
	end
end

function UI.ResetPosition()
	ns.db.ui.point = nil
	ns.db.ui.width, ns.db.ui.height = ns.Defaults.ui.width, ns.Defaults.ui.height
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
		frame:SetSize(ns.db.ui.width, ns.db.ui.height)
	end
end

function UI.Frame()
	return frame
end
