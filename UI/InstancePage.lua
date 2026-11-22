-- The instance page: the war table itself. The section (the map by default) fills the page; a narrow side panel on the
-- left holds the plan's steps in order (entrance, packs, bosses, objectives: Model/Steps.lua) and the party below
-- them. Clicking a step focuses the map on it: its floor, its route segment, its pull or boss and the party
-- positions for it. The window's header carries the instance and plan pickers (plus the plan menu and Undo); the
-- sections (Map, Bosses, Pulls, Party, Gear, Runs, Share, Notes) are the game's window tabs under the window, and the
-- bottom bar carries Run mode. Panels are built the first time their section opens.

local _, ns = ...
local InstancePage = ns:NewModule("InstancePage")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE
local UI = ns.UI

local SIDE_W = 236

-- Header controls (in the window's header strip) ---------------------------------------------------------------------------

local function buildChrome(f, ctx, window)
	local chrome = CreateFrame("Frame", nil, window.bar)
	chrome:SetPoint("LEFT", window.barStart, "RIGHT", SP.md, 0)
	chrome:SetPoint("RIGHT", window.bug or window.settings, "LEFT", -SP.sm, 0)
	chrome:SetHeight(SZ.header)
	f.chrome = chrome

	f.back = W.IconButton(chrome, "prevPage", L["All instances"], function()
		UI.GoHome()
	end)
	f.back:SetPoint("LEFT", 0, 0)
	-- Header tooltips open below their control, so they never cover the next one.
	W.SetTooltip(f.back, L["All instances"], nil, "below")

	-- The instance picker: its own popup (UI/InstancePicker.lua) with sections, level bands and search.
	f.instancePick = W.Dropdown(chrome, {
		width = 200,
		options = function()
			return {}
		end,
		get = function()
			local inst = ctx:Instance()
			return inst and inst.key
		end,
		open = function(button)
			ns.InstancePicker.Open(button, ctx:Instance())
		end,
	})
	f.instancePick:SetPoint("LEFT", f.back, "RIGHT", SP.xs, 0)
	-- The label is the open instance's name; the full list is built only when the menu opens.
	function f.instancePick:Refresh()
		local inst = ctx:Instance()
		W.FitText(self.label, inst and inst.name ~= "" and inst.name or L["Unnamed instance"])
	end
	W.SetTooltip(f.instancePick, L["Instance"], L["Switch to another dungeon or raid."], "below")

	-- Show location: the entrance on the world map, the same action as the Getting there card's (GettingThere.Locate);
	-- right-click or Shift-click opens the Getting there window. Off without a travel record, and in combat.
	local function locationTarget()
		return ctx:Plan() or ctx:Instance()
	end
	f.location = W.IconButton(chrome, "showLocation", nil, function(_, mouse)
		local shift = IsShiftKeyDown and IsShiftKeyDown()
		ns.GettingThere.Locate(locationTarget(), mouse == "RightButton" or shift == true)
	end)
	f.location:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f.location:SetPoint("LEFT", f.instancePick, "RIGHT", SP.xs, 0)
	-- The pin's picture has a wide clear margin: it fills the button to stay as legible as the back arrow beside it.
	f.location.art:ClearAllPoints()
	f.location.art:SetAllPoints()
	-- combat: true from PLAYER_REGEN_DISABLED, which fires before InCombatLockdown says so.
	function f.location:Update(combat)
		local loc = ns.GettingThere.Location(locationTarget())
		local state = (combat and loc.state == "ready") and "blocked" or loc.state
		self.dpState = state
		self:SetDisabled(state ~= "ready")
		local text
		if state == "ready" then
			local hint = loc.mapped and L["Click: show the entrance on the world map. Right-click or Shift-click: Getting there."]
				or L["Click: open Getting there (the entrance lies on no map)."]
			if loc.mapped and not ns.Navigation.CanOpenMap() then
				hint = L["Click: set the map pin (the world map does not open with the gamepad interface style). Right-click or Shift-click: Getting there."]
			end
			text = (loc.zone and (loc.zone .. "\n") or "") .. hint
		elseif state == "blocked" then
			text = L["Not available in combat."]
		else
			text = L["Dungeon Planner has no travel facts for this instance."]
		end
		W.SetTooltip(self, L["Show location"], text, "below")
	end
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if f.location:IsVisible() then
			f.location:Update(true)
		end
	end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if f.location:IsVisible() then
			f.location:Update(false)
		end
	end)

	f.planPick = W.Dropdown(chrome, {
		width = 250,
		placeholder = L["No plan yet"],
		options = function()
			local out = {}
			local entry = ctx:Instance()
			if entry then
				for _, plan in ipairs(UI.PlansFor(entry)) do
					out[#out + 1] = { text = UI.PlanTitle(plan), value = plan.id }
				end
			end
			if not ns.DB.IsReadOnly() then
				out[#out + 1] = { text = L["+ New plan"], value = "new" }
			end
			return out
		end,
		get = function()
			return ns.db.ui.selectedPlan
		end,
		set = function(v)
			if v == "new" then
				UI.NewPlan(f.planPick, ctx:Instance())
			else
				UI.SelectPlan(v, true)
				f:Refresh()
			end
		end,
	})
	f.planPick:SetPoint("LEFT", f.location, "RIGHT", SP.xs, 0)
	W.SetTooltip(f.planPick, L["Plan"], L["The plan on the table. Recommended plans are marked with a star."], "below")

	-- The plan's own menu (rename, export, delete...).
	f.planMenu = W.Button(chrome, "...", "outline", function(self)
		local plan = ctx:Plan()
		if plan then
			UI.PlanMenu(plan, self)
		end
	end, SZ.control + 6)
	f.planMenu:SetPoint("LEFT", f.planPick, "RIGHT", SP.xs, 0)
	W.SetTooltip(f.planMenu, L["Plan menu"], L["Rename, duplicate, export or delete this plan."], "below")
	f.undo = W.Button(chrome, L["Undo"], "outline", function()
		ctx:Undo()
	end)
	f.undo:SetPoint("LEFT", f.planMenu, "RIGHT", SP.xs, 0)
	W.SetTooltip(f.undo, L["Undo"], L["Undo the last change to this plan (up to 50 steps, until you pick another plan)."], "below")
	f.redo = W.Button(chrome, L["Redo"], "outline", function()
		ctx:Redo()
	end)
	f.redo:SetPoint("LEFT", f.undo, "RIGHT", SP.xs, 0)
	W.SetTooltip(f.redo, L["Redo"], L["Make an undone change again."], "below")
end

-- Sections and run mode ----------------------------------------------------------------------------------------------
-- The sections are the game's window tabs hanging under the window's bottom edge (W.HangTabs), as in the game's own
-- windows; without them, segment plates with icons on the bottom bar. Run mode stays on the bottom bar.

local function buildSectionBar(f, window)
	local items = {}
	for i, sec in ipairs(UI.SECTIONS) do
		items[i] = { id = sec.id, text = L[sec.text], art = sec.art }
	end
	local hang = window.dpNative
	f.sectionBar = W.Tabs(hang and window or window.footer, items, function(id)
		UI.SelectTab(id)
	end, { height = SZ.control + 4, style = hang and "bottom" or nil })
	if f.sectionBar.style == "bottom" then
		W.HangTabs(f.sectionBar, window)
	else
		f.sectionBar:SetParent(window.footer)
		f.sectionBar:ClearAllPoints()
		f.sectionBar:SetPoint("BOTTOMLEFT", window.footer, "BOTTOMLEFT")
	end
	f.sectionButtons = {}
	for _, b in ipairs(f.sectionBar.buttons) do
		b.sectionId = b.id
		f.sectionButtons[b.id] = b
	end

	f.runButton = W.Button(window.footer, L["Run mode"], "outline", function()
		ns.RunMode.Toggle()
	end)
	f.runButton:SetHeight(SZ.control + 4)
	f.runButton:SetIcon("runMode", SZ.control - 4)
	f.runButton:SetPoint("RIGHT", window.footer.status, "LEFT", -SP.md, 0)
	W.SetTooltip(f.runButton, L["Run mode"],
		L["A small window for the run: the current step, the next pull, tips for the next boss and a mini map. Stays open while you play."])
end

-- Page ---------------------------------------------------------------------------------------------------------------------

function InstancePage.Create(parent, ctx, window)
	local f = CreateFrame("Frame", "DungeonPlannerInstancePage", parent)
	f.panels = {}

	buildChrome(f, ctx, window)
	buildSectionBar(f, window)

	-- Side panel: steps and party (UI/SidePanel.lua).
	f.side = ns.SidePanel.Create(f, ctx)
	f.side:SetPoint("TOPLEFT")
	f.side:SetPoint("BOTTOMLEFT")
	f.side:SetWidth(SIDE_W)

	-- Section body.
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f.side, "TOPRIGHT", SP.md, 0)
	body:SetPoint("BOTTOMRIGHT")
	f.body = body

	-- The names tests and older code use for the header's controls.
	f.header = { plan = f.planPick, more = f.planMenu, undo = f.undo, redo = f.redo, copy = f.side.copy }

	-- No plan for this instance yet.
	local empty = W.Panel(body, "surface", "border")
	empty:SetAllPoints()
	empty.title = W.Heading(empty, L["No plan for this instance yet"], "page")
	empty.title:SetPoint("TOPLEFT", SP.xxl, -SP.xxl)
	empty.text = W.Paragraph(empty, "body", "ink")
	empty.text:SetPoint("TOPLEFT", empty.title, "BOTTOMLEFT", 0, -SP.md)
	empty.text:SetWidth(460)
	local intro = "Create a plan: mark bosses and pulls on the map, draw the route, write strategies, assign players and "
		.. "list gear. Share it with your group or as a string."
	empty.text:SetText(L[intro])
	empty.create = W.Button(empty, L["Create a plan"], "primary", function(self)
		UI.NewPlan(self, ctx:Instance())
	end)
	empty.create:SetPoint("TOPLEFT", empty.text, "BOTTOMLEFT", 0, -SP.lg)
	f.empty = empty

	function f:ShowChrome(on)
		self.chrome:SetShown(on)
		self.sectionBar:SetShown(on)
		self.runButton:SetShown(on)
	end

	-- Sections --------------------------------------------------------------------------------------------------------------

	-- One pass (UI.Batch): a section that is shown (its OnShow) and asked to refresh refreshes once.
	function f:SelectSection(id)
		UI.Batch(self.ShowSection, self, id)
	end

	function f:ShowSection(id)
		if not ns.Panels[id] then
			id = "map"
		end
		ns.db.ui.tab = id
		self.sectionBar:Select(id)
		for panelId, panel in pairs(self.panels) do
			panel:SetShown(panelId == id)
		end
		if not ctx:Plan() then
			return
		end
		local panel = self.panels[id]
		if not panel then
			-- The map draws its own frame; the other sections sit in one inset panel.
			if id == "map" or id == "plan" or id == "prep" then
				panel = ns.Panels[id].Create(body, ctx)
				panel:SetAllPoints()
			else
				local holder = W.Panel(body, "surface", "border")
				holder:SetAllPoints()
				local inner = ns.Panels[id].Create(holder, ctx)
				inner:SetPoint("TOPLEFT", SP.md, -SP.md)
				inner:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
				holder.inner = inner
				holder.Refresh = function(h)
					h.inner:Refresh()
				end
				panel = holder
			end
			self.panels[id] = panel
		end
		panel:Show()
		ns.SafeCall(panel.Refresh, panel)
	end

	-- Focus the map on a step (UI.FocusStep did the context).
	function f:FocusStep(step, focus)
		self.side:Refresh()
		local map = self.panels.map
		if map and map:IsShown() and map.FocusStep then
			map:FocusStep(step, focus)
		end
	end

	function f:RefreshSteps()
		self.side:Refresh()
	end

	function f:Refresh()
		local entry = ctx:Instance()
		if not entry then
			return
		end
		self.instancePick:Refresh()
		self.location:Update()
		local plan = ctx:Plan()
		if plan and not ns.Bundled.SameInstance(plan.instance, entry) then
			plan = nil
		end
		self.planPick:Refresh()
		self.planPick:SetDisabled(#UI.PlansFor(entry) == 0 and ns.DB.IsReadOnly())
		-- The picker's tooltip says where the plan comes from: a recommended plan's source, revision and data date.
		local tip = L["The plan on the table. Recommended plans are marked with a star."]
		local _, sourceLines = UI.PlanSource(plan)
		if sourceLines then
			tip = tip .. "\n\n" .. table.concat(sourceLines, "\n")
		end
		W.SetTooltip(self.planPick, L["Plan"], tip)
		self.planMenu:SetShown(plan ~= nil)
		local bundled = plan ~= nil and plan.bundled == true
		self.undo:SetShown(plan ~= nil and not bundled)
		self.undo:SetDisabled(not ctx:CanUndo())
		self.redo:SetShown(plan ~= nil and not bundled)
		self.redo:SetDisabled(not ctx:CanRedo())
		for _, b in pairs(self.sectionButtons) do
			b:SetShown(plan ~= nil)
		end
		self.sectionBar:Reflow()
		self.runButton:SetShown(plan ~= nil)
		self.empty:SetShown(plan == nil)
		self.empty.create:SetDisabled(ns.DB.IsReadOnly())
		self.side:Refresh()
		if not plan then
			for _, panel in pairs(self.panels) do
				panel:Hide()
			end
			return
		end
		self:SelectSection(ns.db.ui.tab or "map")
	end

	return f
end
