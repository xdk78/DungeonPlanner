-- Home: the briefing room. A table of instances on the left (name, level range, plans, bosses killed) and a large
-- preview of the selected one on the right (its loading-screen art or a drawn plate, quick facts, its plans and an
-- "Open plan" action). Segments above the table switch between Dungeons, Raids, My plans and Shared; the actions
-- (Current location, New plan, Custom map) sit in the window's bottom bar.
--   Dungeons / Raids  instances, sorted by level; click selects, double-click (or Open plan) opens the war table.
--   My plans          the player's plans, newest first, with the same preview.
--   Shared            plans received or imported, and the import box in place of the preview.
-- Rows are pooled (W.List draws only visible rows); data helpers live in UI/PlanActions.lua.

local _, ns = ...
local Home = ns:NewModule("Home")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE
local UI = ns.UI

local ROW_H = 40
local COL = { level = 70, plans = 64, bosses = 52 }

-- Rows ---------------------------------------------------------------------------------------------------------------------

local function instanceRowCreate(row)
	row.thumb = row:CreateTexture(nil, "ARTWORK")
	row.thumb:SetSize(56, ROW_H - 12)
	row.thumb:SetPoint("LEFT", SP.sm + 2, 0)
	row.thumbEdge = W.Panel(row, false, "border")
	row.thumbEdge:SetPoint("TOPLEFT", row.thumb, "TOPLEFT", -3, 3)
	row.thumbEdge:SetPoint("BOTTOMRIGHT", row.thumb, "BOTTOMRIGHT", 3, -3)
	row.thumbEdge:EnableMouse(false)
	-- Without a picture: the game's dungeon or raid mark on the slate, as the instance picker and the preview show.
	row.emblem = ns.Art.RoundTexture(row, "ARTWORK", 2)
	row.emblem:SetSize(ROW_H - 18, ROW_H - 18)
	row.emblem:SetPoint("CENTER", row.thumb, "CENTER")
	row.title = W.Text(row, "title", "gold")
	row.title:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", SP.md, -1)
	row.title:SetPoint("RIGHT", -(COL.level + COL.plans + COL.bosses + SP.md), 0)
	row.tag = W.Text(row, "caption", "muted")
	row.tag:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", SP.md, 1)
	row.tag:SetPoint("RIGHT", row.title, "RIGHT")
	-- "Forever": the instance is new in WoW: Forever. Centred on the row at the end of the name column, left of the
	-- levels as in the instance picker: on the tag line it touched the name above it and read as an underline.
	row.forever = W.Chip(row, L["Forever"], L["Forever"], L["New in WoW: Forever"])
	row.forever:SetPoint("RIGHT", -(COL.level + COL.plans + COL.bosses + SP.md), 0)
	row.bosses = W.Text(row, "body", "ink")
	row.bosses:SetPoint("RIGHT", -SP.md, 0)
	row.bosses:SetWidth(COL.bosses)
	row.bosses:SetJustifyH("RIGHT")
	row.check = row:CreateTexture(nil, "ARTWORK", nil, 3)
	row.check:SetSize(16, 16)
	row.check:SetPoint("RIGHT", -SP.md, 0)
	ns.Art.Set(row.check, "check")
	row.count = W.Text(row, "body", "ink")
	row.count:SetPoint("RIGHT", row.bosses, "LEFT", 0, 0)
	row.count:SetWidth(COL.plans)
	row.count:SetJustifyH("RIGHT")
	row.level = W.Text(row, "body", "ink")
	row.level:SetPoint("RIGHT", row.count, "LEFT", 0, 0)
	row.level:SetWidth(COL.level)
	row.level:SetJustifyH("RIGHT")
end

local function instanceRowUpdate(row, entry)
	row.entry = entry
	local hasArt = Home.SetInstanceArt(row.thumb, entry, "card", 56, ROW_H - 12)
	row.emblem:SetShown(not hasArt)
	if not hasArt then
		ns.Art.Set(row.emblem, entry.kind == "raid" and "emblemRaid" or "emblemDungeon")
	end
	local forever = ns.Picker.IsForever(entry)
	row.forever:SetShown(forever)
	-- The name and the tag line end before the chip when it shows.
	row.title:ClearAllPoints()
	row.title:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", SP.md, -1)
	if forever then
		row.title:SetPoint("RIGHT", row.forever, "LEFT", -SP.md, 0)
	else
		row.title:SetPoint("RIGHT", -(COL.level + COL.plans + COL.bosses + SP.md), 0)
	end
	W.FitText(row.title, entry.name ~= "" and entry.name or L["Unnamed instance"])
	row.tag:SetText(entry.recommended > 0 and L["Recommended plan"] or (entry.kind == "raid" and L["Raid"] or L["Dungeon"]))
	S.TextColor(row.tag, entry.recommended > 0 and "goldBright" or "muted")
	local total = entry.plans + entry.recommended
	row.count:SetText(total > 0 and ns.Plural(total, L["%d plan|%d plans"]) or "-")
	S.TextColor(row.count, total > 0 and "ink" or "dim")
	row.level:SetText(Home.LevelText(entry))
	if entry.levelLo then
		row.level:SetTextColor(S.LevelColor(entry.levelLo, entry.levelHi))
	else
		S.TextColor(row.level, "muted")
	end
	local done = entry.killed and entry.bosses and entry.bosses > 0 and entry.killed >= entry.bosses
	row.check:SetShown(done and true or false)
	row.bosses:SetShown(not done)
	if entry.killed then
		row.bosses:SetText(entry.killed .. "/" .. entry.bosses)
	else
		row.bosses:SetText(entry.bosses and tostring(entry.bosses) or "-")
	end
	S.TextColor(row.bosses, entry.killed and "ink" or "muted")
end

local function planRowCreate(row)
	row.thumb = row:CreateTexture(nil, "ARTWORK")
	row.thumb:SetSize(56, ROW_H - 12)
	row.thumb:SetPoint("LEFT", SP.sm + 2, 0)
	row.emblem = ns.Art.RoundTexture(row, "ARTWORK", 2)
	row.emblem:SetSize(ROW_H - 18, ROW_H - 18)
	row.emblem:SetPoint("CENTER", row.thumb, "CENTER")
	-- The tag (recommended, a copy, or the date) at the top right, on the title's line; the meta line runs under both.
	row.tag = W.Text(row, "caption", "goldBright")
	row.tag:SetPoint("TOPRIGHT", -SP.md, -(SP.sm + 2))
	row.tag:SetJustifyH("RIGHT")
	row.title = W.Text(row, "title", "gold")
	row.title:SetPoint("TOPLEFT", row.thumb, "TOPRIGHT", SP.md, -1)
	row.title:SetPoint("RIGHT", row.tag, "LEFT", -SP.md, 0)
	row.meta = W.Text(row, "caption", "muted")
	row.meta:SetPoint("BOTTOMLEFT", row.thumb, "BOTTOMRIGHT", SP.md, 1)
	row.meta:SetPoint("RIGHT", -SP.md, 0)
end

local function planMeta(plan)
	local parts = {}
	local inst = ns.Names.Instance(plan.instance)
	if inst ~= "" then
		parts[#parts + 1] = inst
	end
	parts[#parts + 1] = ns.Plural(#plan.pulls, L["%d pull|%d pulls"])
	parts[#parts + 1] = ns.Plural(#plan.encounters, L["%d boss|%d bosses"])
	if plan.source and plan.source.from then
		parts[#parts + 1] = string.format(L["from %s"], plan.source.from)
	elseif plan.author ~= "" then
		parts[#parts + 1] = string.format(L["by %s"], plan.author)
	end
	return table.concat(parts, "  ·  ")
end

local function planRowUpdate(row, plan)
	local entry = UI.EntryForPlan(plan)
	local hasArt = Home.SetInstanceArt(row.thumb, entry, "card", 56, ROW_H - 12)
	row.emblem:SetShown(not hasArt)
	if not hasArt then
		ns.Art.Set(row.emblem, entry and entry.kind == "raid" and "emblemRaid" or "emblemDungeon")
	end
	if plan.bundled then
		row.tag:SetText(L["Recommended plan"])
	elseif plan.origin then
		row.tag:SetText(L["Based on a recommended plan"])
	else
		row.tag:SetText(date and plan.updated > 0 and date("%Y-%m-%d", plan.updated) or "")
	end
	W.FitText(row.title, plan.name)
	W.FitText(row.meta, planMeta(plan))
end

-- Preview ------------------------------------------------------------------------------------------------------------------

local function buildPreview(f)
	local p = W.Panel(f, "surface", "border")
	f.preview = p
	p.plate = Home.ArtPlate(p, { shade = 44, emblemY = 8, noWatermark = true })
	p.plate:SetPoint("TOPLEFT", SP.sm, -SP.sm)
	p.plate:SetPoint("TOPRIGHT", -SP.sm, -SP.sm)
	p.plate:SetHeight(180)
	p.name = W.Text(p.plate, "huge", "gold", "OVERLAY")
	p.name:SetPoint("BOTTOMLEFT", SP.md, SP.sm + 14)
	p.name:SetPoint("RIGHT", -SP.md, 0)
	p.sub = W.Text(p.plate, "caption", "ink", "OVERLAY")
	p.sub:SetPoint("BOTTOMLEFT", SP.md, SP.sm)

	-- Quick facts: a row of label / value pairs.
	p.facts = {}
	local labels = { L["Levels"], L["Plans"], L["Bosses"], L["Floors"] }
	for i, text in ipairs(labels) do
		local cell = CreateFrame("Frame", nil, p)
		cell:SetHeight(36)
		cell.label = W.Label(cell, text)
		cell.label:SetPoint("TOPLEFT")
		cell.value = W.Text(cell, "title", "ink")
		cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -SP.xxs)
		p.facts[i] = cell
	end
	p.rule = S.Hairline(p)
	p.plansHeading = W.Heading(p, L["Plans"])
	p.planLines = {}
	for i = 1, 5 do
		local line = W.Text(p, "body", "ink")
		p.planLines[i] = line
	end
	p.note = W.Paragraph(p, "caption", "muted")

	p.open = W.Button(p, L["Open plan"], "primary", function()
		if p.plan then
			UI.SelectPlan(p.plan.id)
		elseif p.entry then
			UI.OpenInstance(p.entry)
		end
	end)
	p.open:SetPoint("BOTTOMLEFT", SP.md, SP.md)
	p.new = W.Button(p, L["New plan"], "outline", function(self)
		if p.entry then
			UI.OpenInstance(p.entry)
			UI.NewPlan(self, p.entry)
		end
	end)
	p.new:SetPoint("LEFT", p.open, "RIGHT", SP.sm, 0)

	function p:Layout()
		local w = self:GetWidth()
		local plateH = math.floor(math.max(120, math.min(240, (w - 2 * SP.sm) * 0.5)))
		self.plate:SetHeight(plateH)
		local cw = (w - 2 * SP.md) / #self.facts
		for i, cell in ipairs(self.facts) do
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", self.plate, "BOTTOMLEFT", SP.sm + (i - 1) * cw, -SP.md)
			cell:SetWidth(cw)
		end
		self.rule:ClearAllPoints()
		self.rule:SetPoint("TOPLEFT", self.plate, "BOTTOMLEFT", SP.xs, -(SP.md + 36 + SP.sm))
		self.rule:SetPoint("RIGHT", -SP.md, 0)
		self.plansHeading:ClearAllPoints()
		self.plansHeading:SetPoint("TOPLEFT", self.rule, "BOTTOMLEFT", SP.xs, -SP.sm)
		local prev = self.plansHeading
		for _, line in ipairs(self.planLines) do
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SP.xs)
			line:SetPoint("RIGHT", -SP.md, 0)
			prev = line
		end
		self.note:ClearAllPoints()
		self.note:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SP.sm)
		self.note:SetPoint("RIGHT", -SP.md, 0)
		self.note:SetPoint("BOTTOM", self.open, "TOP", 0, SP.sm)
	end

	-- Show an instance (entry) or a plan (with its instance).
	function p:ShowEntry(entry, plan)
		self.entry, self.plan = entry, plan
		local has = entry ~= nil
		for _, cell in ipairs(self.facts) do
			cell:SetShown(has)
		end
		self.open:SetShown(has)
		self.new:SetShown(has and plan == nil and not ns.DB.IsReadOnly())
		if not entry then
			self.plate:SetEntry(nil)
			self.name:SetText("")
			self.sub:SetText("")
			for _, line in ipairs(self.planLines) do
				line:SetText("")
			end
			self.plansHeading:SetText("")
			self.note:SetText(L["Choose an instance on the left."])
			return
		end
		self:Layout()
		self.plate:SetEntry(entry, "header")
		self.name:SetText(plan and plan.name or entry.name or "")
		self.sub:SetText(plan and (entry.name or "") or (entry.kind == "raid" and L["Raid"] or L["Dungeon"]))
		if not entry.plans then
			Home.Decorate(entry)
		end
		local plans = UI.PlansFor(entry)
		local values = {
			Home.LevelText(entry),
			tostring(#plans),
			entry.killed and (entry.killed .. "/" .. entry.bosses) or (entry.bosses and tostring(entry.bosses) or "-"),
			tostring(plans[1] and #plans[1].floors or 0),
		}
		for i, cell in ipairs(self.facts) do
			cell.value:SetText(values[i])
		end
		if entry.levelLo then
			self.facts[1].value:SetTextColor(S.LevelColor(entry.levelLo, entry.levelHi))
		else
			S.TextColor(self.facts[1].value, "ink")
		end
		if plan then
			self.plansHeading:SetText(L["About this plan"])
			self.planLines[1]:SetText(planMeta(plan))
			for i = 2, #self.planLines do
				self.planLines[i]:SetText("")
			end
			self.note:SetText(plan.description ~= "" and plan.description or "")
			self.open:SetLabel(L["Open plan"])
		else
			self.plansHeading:SetText(L["Plans"])
			for i, line in ipairs(self.planLines) do
				local pl = plans[i]
				line:SetText(pl and ("· " .. UI.PlanTitle(pl)) or "")
			end
			self.note:SetText(#plans == 0 and L["No plan for this instance yet"] or "")
			self.open:SetLabel(#plans > 0 and L["Open plan"] or L["Open"])
		end
	end
	p:HookScript("OnSizeChanged", function(self)
		if self.entry then
			self:ShowEntry(self.entry, self.plan)
		end
	end)
	return p
end

-- Build ------------------------------------------------------------------------------------------------------------------------

function Home.Create(parent, ctx, actionBar)
	local f = CreateFrame("Frame", "DungeonPlannerHome", parent)

	-- Left column: segments, filter row, table.
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	f.left = left

	local tabItems = {}
	for i, t in ipairs(UI.HOME_TABS) do
		tabItems[i] = { id = t.id, text = L[t.text] }
	end
	-- The lists are the game's window tabs under the window (in the sections' place, which hide on this page), else
	-- segment plates at the top of the column.
	local window = actionBar and actionBar:GetParent()
	local hang = window and window.dpNative
	f.tabs = W.Tabs(hang and f or left, tabItems, function(id)
		UI.GoHome(id)
	end, { equal = true, style = hang and "bottom" or nil })
	local filter = CreateFrame("Frame", nil, left)
	if f.tabs.style == "bottom" then
		W.HangTabs(f.tabs, window)
		filter:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	else
		f.tabs:SetParent(left)
		f.tabs:ClearAllPoints()
		f.tabs:SetPoint("TOPLEFT", left, "TOPLEFT")
		filter:SetPoint("TOPLEFT", f.tabs, "BOTTOMLEFT", 0, -SP.sm)
	end
	filter:SetPoint("RIGHT")
	filter:SetHeight(SZ.control)
	f.filter = filter
	f.search = W.Input(filter, {
		name = "DungeonPlannerSearchBox",
		search = true,
		placeholder = L["Search dungeons and plans..."],
		maxBytes = 64,
		onChange = function(text)
			ctx.search = text or ""
			f:Refresh()
		end,
	})
	f.onlyPlans = W.Check(filter, L["Only with plans"], function(on)
		ns.db.ui.onlyWithPlans = on
		f:Refresh()
	end)
	f.onlyPlans:SetPoint("RIGHT", 0, 0)
	f.search:SetPoint("LEFT")
	f.search:SetPoint("RIGHT", f.onlyPlans, "LEFT", -SP.md, 0)

	-- Column heads (instances only).
	local heads = CreateFrame("Frame", nil, left)
	heads:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 0, -SP.sm)
	heads:SetPoint("RIGHT")
	heads:SetHeight(18)
	f.heads = heads
	local function head(text, width, anchor, x)
		local fs = W.Label(heads, text)
		if width then
			fs:SetWidth(width)
			fs:SetJustifyH("RIGHT")
		end
		fs:SetPoint(anchor, x, 0)
		return fs
	end
	heads.name = head(L["Instance"], nil, "LEFT", SP.sm + 2)
	heads.bosses = head(L["Bosses"], COL.bosses, "RIGHT", -(SP.md + SP.md))
	heads.plans = head(L["Plans"], COL.plans, "RIGHT", -(SP.md + SP.md + COL.bosses))
	heads.level = head(L["Levels"], COL.level, "RIGHT", -(SP.md + SP.md + COL.bosses + COL.plans))
	-- What the level colours mean (Style.LevelColor), on hovering the heading.
	heads.levelHit = CreateFrame("Frame", nil, heads)
	heads.levelHit:SetPoint("TOPLEFT", heads.level, "TOPLEFT", 0, 2)
	heads.levelHit:SetPoint("BOTTOMRIGHT", heads.level, "BOTTOMRIGHT", 0, -2)
	heads.levelHit:EnableMouse(true)
	W.SetTooltip(heads.levelHit, L["Levels"],
		L["Coloured like quests for your level: grey is trivial, green easy, yellow a fair match, orange hard or still above your level."])
	heads.rule = S.Hairline(heads)
	heads.rule:SetPoint("BOTTOMLEFT")
	heads.rule:SetPoint("BOTTOMRIGHT", -SP.md, 0)

	local content = CreateFrame("Frame", nil, left)
	content:SetPoint("TOPLEFT", heads, "BOTTOMLEFT", 0, -SP.xs)
	content:SetPoint("BOTTOMRIGHT")
	f.content = content

	local function selectEntry(entry)
		ns.db.ui.homeSelected = entry and entry.key or nil
		f.list:Refresh()
		f.preview:ShowEntry(entry, nil)
		-- Opening it is likely next: the plan it opens with starts loading its bosses' portraits (UI/Portraits.lua).
		UI.PrefetchPortraits(entry and UI.DefaultPlanFor(entry))
	end

	f.list = W.List(content, {
		rowHeight = ROW_H,
		gap = SP.xxs,
		boxed = true,
		empty = L["No instances to show. Close the Adventure Guide if it is open, or clear the search."],
		create = instanceRowCreate,
		update = instanceRowUpdate,
		isSelected = function(entry)
			return entry.key == ns.db.ui.homeSelected
		end,
		onClick = function(entry, _, mouse, row)
			if mouse == "RightButton" then
				local items = { { title = entry.name } }
				items[#items + 1] = {
					L["Open"],
					function()
						UI.OpenInstance(entry)
					end,
				}
				if not ns.DB.IsReadOnly() then
					items[#items + 1] = {
						L["New plan"],
						function()
							UI.OpenInstance(entry)
							UI.NewPlan(row, entry)
						end,
					}
				end
				W.Menu(row, items)
			else
				selectEntry(entry)
			end
		end,
		onDoubleClick = function(entry)
			UI.OpenInstance(entry)
		end,
	})
	f.list:SetAllPoints()
	f.grid = f.list -- older name

	local function selectPlan(plan)
		ns.db.ui.homeSelectedPlan = plan and plan.id or nil
		f.plans:Refresh()
		f.preview:ShowEntry(plan and UI.EntryForPlan(plan) or nil, plan)
	end
	f.plans = W.List(content, {
		rowHeight = ROW_H,
		gap = SP.xxs,
		boxed = true,
		empty = L["No plans yet. Open a dungeon and create one, or copy a recommended plan."],
		create = planRowCreate,
		update = planRowUpdate,
		onClick = function(plan, _, mouse, row)
			if mouse == "RightButton" then
				UI.PlanMenu(plan, row)
			else
				selectPlan(plan)
			end
		end,
		onDoubleClick = function(plan)
			UI.SelectPlan(plan.id)
		end,
		isSelected = function(plan)
			return plan.id == ns.db.ui.homeSelectedPlan
		end,
	})
	f.plans:SetAllPoints()

	local shared = CreateFrame("Frame", nil, content)
	shared:SetAllPoints()
	f.shared = shared
	shared.list = W.List(shared, {
		rowHeight = ROW_H,
		gap = SP.xxs,
		boxed = true,
		empty = L["Nothing shared yet. Plans other players send you, and plans you import, appear here."],
		create = planRowCreate,
		update = planRowUpdate,
		onClick = function(plan, _, mouse, row)
			if mouse == "RightButton" then
				UI.PlanMenu(plan, row)
			else
				UI.SelectPlan(plan.id)
			end
		end,
		isSelected = function(plan)
			return plan.id == ns.db.ui.selectedPlan
		end,
	})
	shared.list:SetAllPoints()

	-- Right column: preview (instances, plans) or the import box (Shared).
	buildPreview(f)
	f.preview:SetPoint("TOPLEFT", left, "TOPRIGHT", SP.md, 0)
	f.preview:SetPoint("BOTTOMRIGHT")

	local importPanel = W.Panel(f, "surface", "border")
	importPanel:SetAllPoints(f.preview)
	importPanel.title = W.Heading(importPanel, L["Import a plan"])
	importPanel.title:SetPoint("TOPLEFT", SP.md, -SP.md)
	importPanel.text = W.Paragraph(importPanel, "caption", "muted")
	importPanel.text:SetPoint("TOPLEFT", importPanel.title, "BOTTOMLEFT", 0, -SP.sm)
	importPanel.text:SetPoint("RIGHT", -SP.md, 0)
	importPanel.text:SetText(L["Paste a Dungeon Planner string (it starts with !DP). Discord messages in several parts can be pasted together."])
	importPanel.box = W.MultiLine(importPanel, { maxBytes = 400000 })
	importPanel.box:SetPoint("TOPLEFT", importPanel.text, "BOTTOMLEFT", 0, -SP.md)
	importPanel.box:SetPoint("BOTTOMRIGHT", -SP.md, SZ.control + 2 * SP.md)
	importPanel.go = W.Button(importPanel, L["Import"], "primary", function()
		-- A plan named like one of yours asks first: keep both, or replace yours (UI.ImportWithConfirm).
		ns.UI.ImportWithConfirm(importPanel.box:GetValue(), { kind = "paste" }, function(ok, message)
			if ok then
				importPanel.box:SetValue("")
			else
				ns:Print(L["Import failed:"], tostring(message))
			end
		end)
	end)
	importPanel.go:SetPoint("BOTTOMLEFT", SP.md, SP.md)
	shared.importPanel = importPanel

	-- Actions in the window's bottom bar: primary first.
	local actions = CreateFrame("Frame", nil, actionBar or f)
	actions:SetPoint("LEFT")
	actions:SetSize(10, SZ.control)
	f.actions = actions
	f.newPlan = W.Button(actions, L["New plan"], "primary", function(self)
		UI.NewPlan(self, nil)
	end)
	f.newPlan:SetPoint("LEFT")
	W.SetTooltip(f.newPlan, L["New plan"], L["A plan for the instance or zone you are in."])
	f.here = W.Button(actions, L["Current location"], "outline", function()
		UI.OpenInstance((UI.CurrentEntry()))
	end)
	f.here:SetPoint("LEFT", f.newPlan, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.here, L["Current location"], L["Opens the instance or zone you are in."])
	f.customMap = W.Button(actions, L["Custom map..."], "outline", function()
		W.AskText(L["Custom map"], L["Enter a map ID (uiMapID). Use /dp mapid in the zone to see the current one."], "",
			function(value)
				local id = tonumber(value)
				if not id or id < 1 or id ~= math.floor(id) then
					return
				end
				local name = ns.Instances.MapName(id) or (L["Map"] .. " " .. id)
				UI.OpenInstance({ key = "map:" .. id, name = name, kind = "other", uiMapID = id })
			end)
	end)
	f.customMap:SetPoint("LEFT", f.here, "RIGHT", SP.sm, 0)
	f.count = W.Text(actions, "caption", "muted")
	f.count:SetPoint("LEFT", f.customMap, "RIGHT", SP.lg, 0)

	function f:Refresh()
		local tab = ns.db.ui.homeTab or "dungeons"
		self.tabs:Select(tab)
		local query = Home.Norm(ctx.search):gsub("^%s+", ""):gsub("%s+$", "")
		local isInstances = tab == "dungeons" or tab == "raids"
		self.list:SetShown(isInstances)
		self.heads:SetShown(isInstances)
		self.plans:SetShown(tab == "plans")
		self.shared:SetShown(tab == "shared")
		self.onlyPlans:SetShown(isInstances)
		self.onlyPlans:SetChecked(ns.db.ui.onlyWithPlans)
		self.search:ClearAllPoints()
		self.search:SetPoint("LEFT")
		self.search:SetPoint("RIGHT", isInstances and self.onlyPlans or self.filter, isInstances and "LEFT" or "RIGHT",
			isInstances and -SP.md or 0, 0)
		self.content:ClearAllPoints()
		self.content:SetPoint("TOPLEFT", isInstances and self.heads or self.filter, "BOTTOMLEFT", 0, -SP.xs)
		self.content:SetPoint("BOTTOMRIGHT", self.left, "BOTTOMRIGHT")
		self.newPlan:SetDisabled(ns.DB.IsReadOnly())
		local onShared = tab == "shared"
		-- Making a plan or opening a map belongs to the instance lists, not to the list of plans others shared.
		self.newPlan:SetShown(not onShared)
		self.here:SetShown(not onShared)
		self.customMap:SetShown(not onShared)
		self.count:ClearAllPoints()
		if onShared then
			self.count:SetPoint("LEFT", self.actions, "LEFT", 0, 0)
		else
			self.count:SetPoint("LEFT", self.customMap, "RIGHT", SP.lg, 0)
		end
		self.preview:SetShown(not onShared)
		self.shared.importPanel:SetShown(onShared)
		-- The table takes a little more than half; the preview the rest.
		self.left:SetWidth(math.max(360, math.floor((self:GetWidth() - SP.md) * 0.56)))

		if isInstances then
			local entries, complete = Home.AllEntries()
			local shown = {}
			for _, entry in ipairs(entries) do
				if (entry.kind == "raid") == (tab == "raids") then
					Home.Decorate(entry)
					if Home.MatchesSearch(entry, query)
						and (not ns.db.ui.onlyWithPlans or entry.plans + entry.recommended > 0) then
						shown[#shown + 1] = entry
					end
				end
			end
			Home.SortEntries(shown)
			local selected
			for _, e in ipairs(shown) do
				if e.key == ns.db.ui.homeSelected then
					selected = e
				end
			end
			selected = selected or shown[1]
			ns.db.ui.homeSelected = selected and selected.key or nil
			self.list:SetItems(shown)
			self.preview:ShowEntry(selected, nil)
			local text = ns.Plural(#shown, L["%d instance|%d instances"])
			if not complete then
				text = L["Close the Adventure Guide to list instances."]
			end
			self.count:SetText(text)
		elseif tab == "plans" then
			local list = {}
			for _, plan in ipairs(ns.DB.Plans()) do
				if query == "" or Home.Norm(plan.name):find(query, 1, true)
					or Home.Norm(ns.Names.Instance(plan.instance)):find(query, 1, true) then
					list[#list + 1] = plan
				end
			end
			local selected
			for _, plan in ipairs(list) do
				if plan.id == ns.db.ui.homeSelectedPlan then
					selected = plan
				end
			end
			selected = selected or list[1]
			ns.db.ui.homeSelectedPlan = selected and selected.id or nil
			self.plans:SetItems(list)
			self.preview:ShowEntry(selected and UI.EntryForPlan(selected) or nil, selected)
			self.count:SetText(ns.Plural(#list, L["%d plan|%d plans"]))
		else
			-- Shared: plans other players sent and plans imported from strings or packs. Recommended plans are not
			-- here: they are listed with their instance.
			local received = {}
			for _, plan in ipairs(ns.DB.Plans()) do
				if plan.source and (query == "" or Home.Norm(plan.name):find(query, 1, true)
					or Home.Norm(ns.Names.Instance(plan.instance)):find(query, 1, true)) then
					received[#received + 1] = plan
				end
			end
			table.sort(received, function(a, b)
				return (a.source.at or 0) > (b.source.at or 0)
			end)
			self.shared.list:SetItems(received)
			local all = 0
			for _, plan in ipairs(ns.DB.Plans()) do
				if plan.source then
					all = all + 1
				end
			end
			self.count:SetText(ns.Plural(all, L["%d shared plan|%d shared plans"]))
		end
	end

	-- Dragging the size grip reports a new size every frame: only the split follows at once (the lists lay themselves
	-- out); the table's data is rebuilt once, shortly after the last change.
	f:SetScript("OnSizeChanged", function(self)
		if not self:IsShown() then
			return
		end
		self.left:SetWidth(math.max(360, math.floor((self:GetWidth() - SP.md) * 0.56)))
		if not (C_Timer and C_Timer.After) then
			self:Refresh()
		elseif not self.dpResizing then
			self.dpResizing = true
			C_Timer.After(0.1, function()
				self.dpResizing = nil
				if self:IsShown() then
					self:Refresh()
				end
			end)
		end
	end)
	return f
end
