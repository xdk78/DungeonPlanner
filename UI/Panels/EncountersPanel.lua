-- Bosses section, as Dungeon Journal's instance page: the bosses of the plan on the left (round journal portraits with
-- their order in a badge, Dungeon Journal's brown selected row), and the selected boss on the right: a big portrait,
-- strategy and phases, the boss's assignments and its loot/gear list. Bosses come from the game's journal at runtime or
-- are added by hand; names come from the journal by ID (Data/Names.lua), so they are in the reader's game language.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema = ns.Plan, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local LIST_W = 300
local ROW_H = 56

local Panel = {}
ns.Panels.encounters = Panel

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local selectedId, phaseIndex

	local function plan()
		return ctx:Plan()
	end
	local function selected()
		local p = plan()
		return p and selectedId and Util.FindById(p.encounters, selectedId)
	end
	local function changed()
		ctx:Changed("encounters")
	end

	f.add = W.Button(f, L["Add boss"], "red", function()
		local p = plan()
		if not p then
			return
		end
		W.AskText(L["Add boss"], L["Name of the boss or encounter."], "", function(name)
			local enc = Plan.AddEncounter(p, { name = name ~= "" and name or L["Boss"] })
			if enc then
				enc.custom = true
				selectedId = enc.id
				changed()
			end
		end)
	end)
	f.add:SetPoint("TOPLEFT")

	f.journal = W.Button(f, L["Add from journal"], "outline", function()
		local p = plan()
		local entry = p and ns.Journal.ForPlan(p)
		if entry then
			local n = ns.Templates.AddJournalEncounters(p, entry.ejInstanceID)
			ns:Print(ns.Plural(n, L["Added %d boss from the Adventure Guide.|Added %d bosses from the Adventure Guide."]))
			changed()
		end
	end)
	f.journal:SetPoint("LEFT", f.add, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.journal, L["Add from journal"], L["Adds the instance's bosses from the game's Adventure Guide, in their order."])

	f.dj = W.Button(f, L["Dungeon Journal"], "outline", function()
		ns.Integrations.OpenDungeonJournal()
	end)
	f.dj:SetPoint("LEFT", f.journal, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.dj, L["Dungeon Journal"], L["Opens the Dungeon Journal addon for loot and boss details."])

	f.list = W.List(f, {
		rowHeight = ROW_H,
		gap = SP.xs,
		boxed = true,
		empty = L["No bosses yet."],
		create = function(row)
			row.portrait = W.Portrait(row, 40)
			row.portrait:SetPoint("LEFT", SP.md, 0)
			row.title = W.Text(row, "title", "gold")
			row.title:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", SP.md, -2)
			row.title:SetPoint("RIGHT", -32, 0)
			row.meta = W.Text(row, "caption", "muted")
			row.meta:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", SP.md, 2)
			row.meta:SetPoint("RIGHT", -32, 0)
			row.check = row:CreateTexture(nil, "ARTWORK")
			row.check:SetSize(20, 20)
			row.check:SetPoint("RIGHT", -SP.md, 0)
			ns.Art.Set(row.check, "check")
		end,
		update = function(row, enc, index)
			local p = plan()
			row.title:SetText(ns.Names.Encounter(enc))
			row.portrait:SetBoss(ns.Journal.BossArt(p, enc))
			row.portrait:SetBadge(tostring(index))
			local _, dungeonID = ns.Journal.EncounterIds(p, enc)
			local killed = dungeonID and ns.Progress.IsKilledInRun(ns.char.progress, dungeonID)
			row.portrait:SetDone(killed)
			row.check:SetShown(killed and true or false)
			S.TextColor(row.title, enc.id == selectedId and "white" or "ink")
			local meta = #enc.phases > 0 and ns.Plural(#enc.phases, L["%d phase|%d phases"]) or ""
			if killed then
				meta = (meta ~= "" and (meta .. " \226\128\162 ") or "") .. L["killed this run"]
			end
			row.meta:SetText(meta)
			-- Without a second line the name sits in the middle of the row.
			row.title:ClearAllPoints()
			if meta ~= "" then
				row.title:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", SP.md, -2)
			else
				row.title:SetPoint("LEFT", row.portrait, "RIGHT", SP.md, 0)
			end
			row.title:SetPoint("RIGHT", -32, 0)
		end,
		isSelected = function(enc)
			return enc.id == selectedId
		end,
		onClick = function(enc, _, mouse, row)
			if mouse == "RightButton" then
				if ctx:ReadOnly() then
					return
				end
				W.Menu(row, {
					{ title = ns.Names.Encounter(enc) },
					{
						L["Delete boss"],
						function()
							Plan.RemoveEncounter(plan(), enc.id)
							selectedId = nil
							changed()
						end,
					},
				})
			else
				selectedId, phaseIndex = enc.id, nil
				f:Refresh()
			end
		end,
	})
	f.list:SetPoint("TOPLEFT", f.add, "BOTTOMLEFT", 0, -SP.md)
	f.list:SetPoint("BOTTOMLEFT")
	f.list:SetWidth(LIST_W)

	-- Editor in a scroll area.
	local area = W.ScrollArea(f)
	area:SetPoint("TOPLEFT", f.list, "TOPRIGHT", SP.xl, 0)
	area:SetPoint("BOTTOMRIGHT")
	local c = area.content
	f.area = area

	local y = 0
	local function add(widget, h, gap)
		widget:SetPoint("TOPLEFT", 0, -y)
		widget:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
		y = y + h + (gap or SP.md)
	end

	-- The boss: big portrait and name (Dungeon Journal's boss page).
	c.portrait = W.Portrait(c, 72)
	c.portrait:SetPoint("TOPLEFT", SP.md, -SP.md)
	c.bossName = W.Text(c, "huge", "gold")
	c.bossName:SetPoint("LEFT", c.portrait, "RIGHT", SP.lg, 8)
	c.bossName:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
	y = 72 + 2 * SP.md
	c.ids = W.Text(c, "caption", "dim")
	c.ids:SetPoint("TOPLEFT", c.bossName, "BOTTOMLEFT", 0, -SP.xs)
	c.ids:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)

	c.nameLabel = W.Label(c, L["Name (leave empty to use the journal's name)"])
	add(c.nameLabel, 16, SP.xs)
	c.name = W.Input(c, {
		maxBytes = Schema.TEXT.name,
		placeholder = " ", -- replaced by the journal's name for the selected boss
		onCommit = function(text)
			local enc = selected()
			if enc then
				Plan.UpdateEncounter(plan(), enc.id, { name = text })
				changed()
			end
		end,
	})
	add(c.name, SZ.control)

	c.strategyLabel = W.Label(c, L["Strategy"])
	add(c.strategyLabel, 16, SP.xs)
	c.strategy = W.MultiLine(c, {
		maxBytes = Schema.TEXT.strategy,
		onCommit = function(text)
			local enc = selected()
			if enc then
				Plan.UpdateEncounter(plan(), enc.id, { strategy = text })
				changed()
			end
		end,
	})
	c.strategy:SetHeight(160)
	add(c.strategy, 160, SP.xl)

	c.phasesTitle = W.Heading(c, "")
	c.phasesTitle:SetText(L["Phases"])
	add(c.phasesTitle, 20)

	c.addPhase = W.Button(c, L["Add phase"], "outline", function()
		local enc = selected()
		if enc then
			local _, index = Plan.AddPhase(plan(), enc.id)
			phaseIndex = index
			changed()
		end
	end)
	c.addPhase:SetPoint("TOPLEFT", 0, -y)
	c.addPhase.dpGround = "surface"
	y = y + SZ.control + SP.md

	c.phaseTabs = CreateFrame("Frame", nil, c)
	c.phaseTabs:SetHeight(SZ.control)
	add(c.phaseTabs, SZ.control)
	c.phaseButtons = {}

	c.phaseNameLabel = W.Label(c, L["Phase name"])
	add(c.phaseNameLabel, 16, SP.xs)
	c.phaseName = W.Input(c, {
		maxBytes = Schema.TEXT.label,
		onCommit = function(text)
			local enc = selected()
			if enc and phaseIndex then
				Plan.UpdatePhase(plan(), enc.id, phaseIndex, { name = text })
				changed()
			end
		end,
	})
	add(c.phaseName, SZ.control)
	c.triggerLabel = W.Label(c, L["Starts when (trigger)"])
	add(c.triggerLabel, 16, SP.xs)
	c.trigger = W.Input(c, {
		maxBytes = Schema.TEXT.short,
		placeholder = L["For example: at 60% health"],
		onCommit = function(text)
			local enc = selected()
			if enc and phaseIndex then
				Plan.UpdatePhase(plan(), enc.id, phaseIndex, { trigger = text })
				changed()
			end
		end,
	})
	add(c.trigger, SZ.control)
	c.phaseNotesLabel = W.Label(c, L["What to do"])
	add(c.phaseNotesLabel, 16, SP.xs)
	c.phaseNotes = W.MultiLine(c, {
		maxBytes = Schema.TEXT.strategy,
		onCommit = function(text)
			local enc = selected()
			if enc and phaseIndex then
				Plan.UpdatePhase(plan(), enc.id, phaseIndex, { notes = text })
				changed()
			end
		end,
	})
	c.phaseNotes:SetHeight(120)
	add(c.phaseNotes, 120)
	c.removePhase = W.Button(c, L["Remove phase"], "outline", function()
		local enc = selected()
		if enc and phaseIndex then
			Plan.RemovePhase(plan(), enc.id, phaseIndex)
			phaseIndex = nil
			changed()
		end
	end)
	c.removePhase:SetPoint("TOPLEFT", 0, -y)
	y = y + SZ.control + SP.xl

	-- This boss's assignments and its loot / gear list (Dungeon Journal's loot rows: icon, quality-coloured name, slot).
	c.assignTitle = W.Heading(c, L["Assignments"])
	add(c.assignTitle, 18, SP.sm)
	c.assignText = W.Paragraph(c, "body", "ink")
	add(c.assignText, 16, SP.lg)
	c.lootTitle = W.Heading(c, L["Loot and gear"])
	c.lootTitle:SetPoint("TOPLEFT", c.assignText, "BOTTOMLEFT", 0, -SP.lg)
	c.lootRows = {}
	for i = 1, 8 do
		local row = W.Panel(c, "raised", "border")
		row:SetHeight(44)
		row:SetPoint("TOPLEFT", c.lootTitle, "BOTTOMLEFT", 0, -SP.sm - (i - 1) * (44 + SP.xs))
		row:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(32, 32)
		row.icon:SetPoint("LEFT", SP.sm, 0)
		row.name = W.Text(row, "body", "white")
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", SP.sm, -1)
		row.name:SetPoint("RIGHT", -SP.sm, 0)
		row.slot = W.Text(row, "caption", "ink")
		row.slot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", SP.sm, 1)
		row.slot:SetPoint("RIGHT", -SP.sm, 0)
		c.lootRows[i] = row
	end
	c.lootEmpty = W.Paragraph(c, "caption", "muted")
	c.lootEmpty:SetPoint("TOPLEFT", c.lootTitle, "BOTTOMLEFT", 0, -SP.sm)
	c.lootEmpty:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
	c.lootEmpty:SetText(L["No gear for this boss yet. Add items on the Gear page and pick this boss."])
	c.dj = ns.BossSections.Stack(c)
	c.dj:Hide()
	local baseHeight = y + 18 + SP.lg
	area:SetContentHeight(baseHeight)

	local phaseWidgets = { c.phaseNameLabel, c.phaseName, c.triggerLabel, c.trigger, c.phaseNotesLabel, c.phaseNotes,
		c.removePhase }

	-- Read-only view (recommended plans): the boss as formatted text, like Dungeon Journal's boss page.
	local doc = W.Document(f)
	doc:SetPoint("TOPLEFT", f.list, "TOPRIGHT", SP.xl, 0)
	doc:SetPoint("BOTTOMRIGHT")
	f.doc = doc
	local head = CreateFrame("Frame", nil, doc.content)
	head:SetSize(400, 72 + 2 * SP.md)
	head.portrait = W.Portrait(head, 72)
	head.portrait:SetPoint("TOPLEFT", SP.md, -SP.md)
	head.name = W.Text(head, "huge", "gold")
	-- Its bottom on the portrait's middle line, the meta under it (one vertical anchor: no second centre).
	head.name:SetPoint("BOTTOMLEFT", head.portrait, "RIGHT", SP.lg, -2)
	head.name:SetPoint("RIGHT", doc.content, "RIGHT", -SP.sm, 0)
	head.meta = W.Text(head, "caption", "muted")
	head.meta:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -SP.xs)
	head.meta:SetPoint("RIGHT", doc.content, "RIGHT", -SP.sm, 0)

	local function showDocument(p, enc, index)
		doc:Begin(p.id .. "|" .. enc.id)
		head.portrait:SetBoss(ns.Journal.BossArt(p, enc))
		head.portrait:SetBadge(index and tostring(index) or nil)
		head.name:SetText(ns.Names.Encounter(enc))
		local meta = {}
		if index then
			meta[#meta + 1] = string.format(L["Boss %d of %d"], index, #p.encounters)
		end
		local level = ns.BossInfo.Meta(ns.BossInfo.For(p, enc))
		if level then
			meta[#meta + 1] = level
		end
		local _, dungeonID = ns.Journal.EncounterIds(p, enc)
		if dungeonID and ns.Progress.IsKilledInRun(ns.char.progress, dungeonID) then
			meta[#meta + 1] = L["killed this run"]
		end
		head.meta:SetText(table.concat(meta, "  \226\128\162  "))
		doc:Place(head, 72 + 2 * SP.md)
		doc:Add("heading", L["Strategy"])
		doc:Add("text", enc.strategy ~= "" and enc.strategy or L["No strategy written for this boss."])
		-- What another addon states about the boss (Dungeon Journal: description, summon item, drops), credited.
		ns.BossSections.FillDoc(doc, ns.BossInfo.Sections(p, enc, { maxDrops = 12 }))
		if #enc.phases > 0 then
			doc:Add("heading", L["Phases"])
			for i, phase in ipairs(enc.phases) do
				doc:Add("label", phase.name ~= "" and phase.name or (L["Phase"] .. " " .. i))
				if phase.trigger ~= "" then
					doc:Add("muted", string.format(L["Starts: %s"], phase.trigger))
				end
				doc:Add("text", phase.notes)
			end
		end
		local lines = Plan.AssignmentLines(p, enc.id)
		if #lines > 0 then
			doc:Add("heading", L["Assignments"])
			doc:Add("text", table.concat(lines, "\n"))
		end
		local gear = Plan.FilterGear(p, { encounter = enc.id })
		local entry = ns.Journal.ForPlan(p)
		local ej = ns.Journal.EncounterIds(p, enc)
		local drops = entry and ej and ns.Loot.For(entry.ejInstanceID, ej, {}) or {}
		if #gear > 0 or #drops > 0 then
			doc:Add("heading", L["Loot"])
			local out = {}
			for _, g in ipairs(gear) do
				local name = ns.Names.ItemInfo(g)
				out[#out + 1] = "\226\128\162 " .. name .. (g.slot and ("  |cff9d9d9d" .. L["slot:" .. g.slot] .. "|r") or "")
			end
			for _, it in ipairs(drops) do
				local name = it.link or it.name or ns.Names.ItemInfo({ itemID = it.itemID, label = "" })
				local slot = it.slot and L["slot:" .. it.slot] or it.slotText
				out[#out + 1] = "\226\128\162 " .. name .. (slot and ("  |cff9d9d9d" .. slot .. "|r") or "")
			end
			doc:Add("text", table.concat(out, "\n"))
			if #drops > 0 then
				doc:Add("muted", L["More on the Gear page: filters, tooltips and links."])
			end
		end
		doc:Finish()
	end

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		if selectedId and not Util.FindById(p.encounters, selectedId) then
			selectedId = nil
		end
		if not selectedId and p.encounters[1] then
			selectedId = p.encounters[1].id
		end
		self.list:SetItems(p.encounters, p.id)
		local ro = ctx:ReadOnly()
		-- Read-only plans have nothing to add: their toolbar keeps only the Dungeon Journal link.
		self.add:SetShown(not ro)
		self.journal:SetShown(not ro and ns.Journal.ForPlan(p) ~= nil)
		self.dj:SetShown(ns.Integrations.HasDungeonJournal())
		self.dj:ClearAllPoints()
		if self.journal:IsShown() then
			self.dj:SetPoint("LEFT", self.journal, "RIGHT", SP.sm, 0)
		elseif self.add:IsShown() then
			self.dj:SetPoint("LEFT", self.add, "RIGHT", SP.sm, 0)
		else
			self.dj:SetPoint("TOPLEFT")
		end
		self.list:ClearAllPoints()
		if self.add:IsShown() or self.dj:IsShown() then
			self.list:SetPoint("TOPLEFT", self.add, "BOTTOMLEFT", 0, -SP.md)
		else
			self.list:SetPoint("TOPLEFT")
		end
		self.list:SetPoint("BOTTOMLEFT")

		local enc = selected()
		area:SetShown(enc ~= nil and not ro)
		doc:SetShown(enc ~= nil and ro)
		if not enc then
			return
		end
		if ro then
			showDocument(p, enc, select(2, Util.FindById(p.encounters, enc.id)))
			return
		end
		area:SetOwner(p.id .. "|" .. enc.id)
		c.portrait:SetBoss(ns.Journal.BossArt(p, enc))
		local index = select(2, Util.FindById(p.encounters, enc.id))
		c.portrait:SetBadge(index and tostring(index) or nil)
		c.bossName:SetText(ns.Names.Encounter(enc))
		c.phasesTitle:SetText(L["Phases"])
		c.name:SetValue(enc.custom and enc.name or "")
		c.name.placeholder:SetText(ns.Names.Encounter(enc))
		local ejID, dungeonID = ns.Journal.EncounterIds(p, enc)
		if ejID or dungeonID then
			c.ids:SetText(string.format(L["Journal ID %s • encounter ID %s"], tostring(ejID or "-"),
				tostring(dungeonID or "-")))
		else
			c.ids:SetText(L["Not linked to the journal: kills of this boss are not tracked automatically."])
		end
		c.strategy:SetValue(enc.strategy)

		for _, b in ipairs(c.phaseButtons) do
			b:Hide()
		end
		local x = 0
		for i, phase in ipairs(enc.phases) do
			local b = c.phaseButtons[i]
			if not b then
				b = W.Button(c.phaseTabs, "", "ghost")
				c.phaseButtons[i] = b
			end
			b:SetLabel(phase.name ~= "" and phase.name or (L["Phase"] .. " " .. i))
			b:SetScript("OnClick", function()
				phaseIndex = i
				f:Refresh()
			end)
			b:ClearAllPoints()
			b:SetPoint("LEFT", x, 0)
			b:SetActive(i == phaseIndex)
			b:Show()
			x = x + b:GetWidth() + SP.xs
		end
		if phaseIndex and not enc.phases[phaseIndex] then
			phaseIndex = nil
		end
		if not phaseIndex and enc.phases[1] then
			phaseIndex = 1
			for i, b in ipairs(c.phaseButtons) do
				b:SetActive(i == 1)
			end
		end
		local phase = phaseIndex and enc.phases[phaseIndex]
		for _, w in ipairs(phaseWidgets) do
			w:SetShown(phase ~= nil)
		end
		if phase then
			c.phaseName:SetValue(phase.name)
			c.trigger:SetValue(phase.trigger)
			c.phaseNotes:SetValue(phase.notes)
		end
		c.addPhase:SetDisabled(ro or #enc.phases >= Schema.MAX.phases)
		c.removePhase:SetDisabled(ro)

		local lines = Plan.AssignmentLines(p, enc.id)
		c.assignText:SetText(#lines > 0 and table.concat(lines, "\n") or L["No assignments for this boss."])
		local assignHeight = math.max(16, math.ceil(c.assignText:GetStringHeight()))
		local gear = Plan.FilterGear(p, { encounter = enc.id })
		for i, row in ipairs(c.lootRows) do
			local g = gear[i]
			row:SetShown(g ~= nil)
			if g then
				local name, quality, icon = ns.Names.ItemInfo(g)
				row.icon:SetTexture(icon or 134400)
				row.name:SetText(name)
				local r, gg, b = ns.Names.QualityColor(quality)
				row.name:SetTextColor(r, gg, b)
				local slot = g.slot and L["slot:" .. g.slot] or ""
				if g.note ~= "" then
					slot = slot ~= "" and (slot .. "  \226\128\162  " .. g.note) or g.note
				end
				row.slot:SetText(slot)
			end
		end
		c.lootEmpty:SetShown(#gear == 0)
		local lootHeight = #gear > 0 and math.min(#gear, #c.lootRows) * (44 + SP.xs) or 20
		-- Under the loot: what another addon states about the boss (Dungeon Journal), when it states anything.
		local sections = ns.BossInfo.Sections(p, enc, { maxDrops = 8 })
		c.dj:SetShown(#sections > 0)
		local djHeight = 0
		if #sections > 0 then
			c.dj:ClearAllPoints()
			c.dj:SetPoint("TOPLEFT", c.lootTitle, "BOTTOMLEFT", 0, -(SP.sm + lootHeight + SP.lg))
			c.dj:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
			djHeight = c.dj:Set(sections) + SP.lg
		end
		area:SetContentHeight(baseHeight + assignHeight + SP.lg + 18 + SP.sm + lootHeight + SP.lg + djHeight)
	end
	return f
end
