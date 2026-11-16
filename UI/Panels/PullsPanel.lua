-- Pulls tab: the ordered pull list on the left, the selected pull's editor on the right (name, colour, tags, planned
-- cooldowns and Bloodlust, planned progress, note). Markers join pulls on the Map
-- tab (Pull tool or the marker editor); "Show on map" highlights a pull there. A read-only plan (a recommended one)
-- shows the pull as formatted text instead of the editor.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema = ns.Plan, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

-- The list takes nearly half the section (at least 280 px, at most 440): wide enough for pull names on two
-- lines, leaving the detail the rest.
local LIST_MIN, LIST_MAX, LIST_SHARE = 280, 440, 0.45

local Panel = {}
ns.Panels.pulls = Panel

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local selectedId

	local function plan()
		return ctx:Plan()
	end
	local function selected()
		local p = plan()
		return p and selectedId and Util.FindById(p.pulls, selectedId)
	end
	local function changed()
		ctx:Changed("pulls")
	end

	f.add = W.Button(f, L["Add pull"], "red", function()
		local p = plan()
		if not p then
			return
		end
		local pull, err = Plan.AddPull(p)
		if pull then
			selectedId = pull.id
			changed()
		else
			ns:Print(L["Cannot add more pulls:"], err)
		end
	end)
	f.add:SetPoint("TOPLEFT")

	f.up = W.Button(f, L["Move up"], "outline", function()
		local p = plan()
		if p and selectedId and Plan.MovePull(p, selectedId, -1) then
			changed()
		end
	end)
	f.up:SetPoint("LEFT", f.add, "RIGHT", SP.sm, 0)
	f.down = W.Button(f, L["Move down"], "outline", function()
		local p = plan()
		if p and selectedId and Plan.MovePull(p, selectedId, 1) then
			changed()
		end
	end)
	f.down:SetPoint("LEFT", f.up, "RIGHT", SP.sm, 0)

	-- Rows of two lines: a pull's name ("Dark Iron Summoner patrol (Magmatus)") wraps instead of being cut.
	f.list = W.List(f, {
		rowHeight = SZ.row2,
		empty = L["No pulls yet. Add one here, or use the Pull tool on the map."],
		create = function(row)
			row.swatch = row:CreateTexture(nil, "ARTWORK")
			row.swatch:SetTexture(S.MEDIA .. "Circle")
			row.swatch:SetSize(10, 10)
			row.swatch:SetPoint("LEFT", SP.sm, 0)
			row.count = W.Text(row, "caption", "muted")
			row.count:SetPoint("RIGHT", -SP.sm, 0)
			row.count:SetJustifyH("RIGHT")
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("LEFT", row.swatch, "RIGHT", SP.sm, 0)
			row.text:SetPoint("RIGHT", row.count, "LEFT", -SP.sm, 0)
			row.text:SetWordWrap(true)
			if row.text.SetMaxLines then
				row.text:SetMaxLines(2)
			end
		end,
		update = function(row, pull, index)
			row.swatch:SetVertexColor(S.PaletteColor(pull.color))
			-- The name on up to two lines, cut after a whole word beyond that (hover: whole); its marks after it when
			-- they fit.
			local marks = ns.UI.PullMarks(pull)
			local shown, cut = W.FitText(row.text, index .. ". " .. pull.name)
			if marks ~= "" and not cut then
				row.text:SetText(shown .. "  |cffb5ab96" .. marks .. "|r")
				if (row.text:GetWidth() or 0) > 0 and W.TextOverflows(row.text, row.text:GetWidth()) then
					row.text:SetText(shown)
				end
			end
			local packs = 0
			for _, m in ipairs(Plan.MarkersOfPull(plan(), pull.id)) do
				if m.kind == "pack" or m.kind == "patrol" or m.kind == "rare" then
					packs = packs + 1
				end
			end
			row.count:SetText(packs > 0 and ns.Plural(packs, L["%d pack|%d packs"]) or "")
		end,
		isSelected = function(pull)
			return pull.id == selectedId
		end,
		onEnter = function(pull, row)
			local marks = ns.UI.PullMarks(pull, { long = true })
			W.FullTextTooltip(row, row.text, marks ~= "" and { marks } or nil)
		end,
		onClick = function(pull)
			selectedId = pull.id
			f:Refresh()
		end,
	})
	f.list:SetPoint("TOPLEFT", f.add, "BOTTOMLEFT", 0, -SP.md)
	f.list:SetPoint("BOTTOMLEFT")
	f.list:SetWidth(LIST_MIN)
	function f:SizeList()
		local w = math.floor(math.max(LIST_MIN, math.min(LIST_MAX, (self:GetWidth() or 0) * LIST_SHARE)))
		if math.abs((self.list:GetWidth() or 0) - w) >= 1 then
			self.list:SetWidth(w)
			return true
		end
		return false
	end
	f:SetScript("OnSizeChanged", function(self)
		if self:SizeList() and self:IsShown() then
			self:Refresh() -- the names fit again at the new width
		end
	end)

	-- Editor.
	local ed = CreateFrame("Frame", nil, f)
	ed:SetPoint("TOPLEFT", f.list, "TOPRIGHT", SP.xl, 0)
	ed:SetPoint("BOTTOMRIGHT")
	f.editor = ed

	ed.nameLabel = W.Label(ed, L["Name"])
	ed.nameLabel:SetPoint("TOPLEFT")
	ed.name = W.Input(ed, {
		maxBytes = Schema.TEXT.label,
		onCommit = function(text)
			local p, pull = plan(), selected()
			if pull then
				Plan.UpdatePull(p, pull.id, { name = text })
				changed()
			end
		end,
	})
	ed.name:SetPoint("TOPLEFT", ed.nameLabel, "BOTTOMLEFT", 0, -SP.xs)
	ed.name:SetPoint("RIGHT", -160, 0)

	ed.colorLabel = W.Label(ed, L["Colour"])
	ed.colorLabel:SetPoint("TOPLEFT", ed.name, "TOPRIGHT", SP.md, 16 + SP.xs)
	ed.color = W.Dropdown(ed, {
		width = 148,
		options = function()
			local out = {}
			for i = 1, Schema.COLOR_COUNT do
				out[i] = { text = L["Colour"] .. " " .. i, value = i }
			end
			return out
		end,
		get = function()
			local pull = selected()
			return pull and pull.color
		end,
		set = function(v)
			local p, pull = plan(), selected()
			if pull then
				Plan.UpdatePull(p, pull.id, { color = v })
				changed()
			end
		end,
	})
	ed.color:SetPoint("TOPLEFT", ed.colorLabel, "BOTTOMLEFT", 0, -SP.xs)

	-- Plan marks: tags, planned cooldowns and Bloodlust (toggles that wrap to the editor's width), then the planned
	-- progress. Shown in the steps, run mode and the Discord text. Planning only: nothing is detected in combat.
	ed.marksLabel = W.Label(ed, L["Tags and planned cooldowns"])
	ed.marksLabel:SetPoint("TOPLEFT", ed.name, "BOTTOMLEFT", 0, -SP.md)
	ed.marks = CreateFrame("Frame", nil, ed)
	ed.marks:SetPoint("TOPLEFT", ed.marksLabel, "BOTTOMLEFT", 0, -SP.xs)
	ed.marks:SetPoint("RIGHT")
	ed.marks:SetHeight(SZ.control)
	ed.toggles = {}
	local MARKS = {}
	for _, tag in ipairs(Schema.PULL_TAGS) do
		MARKS[#MARKS + 1] = tag
	end
	MARKS[#MARKS + 1] = "cd"
	MARKS[#MARKS + 1] = "lust"
	for _, key in ipairs(MARKS) do
		local b = W.Button(ed.marks, L["tag:" .. key], "outline", function()
			local p, pull = plan(), selected()
			if not pull then
				return
			end
			if key == "cd" then
				Plan.UpdatePull(p, pull.id, { cd = not pull.cd })
			elseif key == "lust" then
				Plan.UpdatePull(p, pull.id, { lust = not pull.lust })
			else
				Plan.UpdatePull(p, pull.id, { tags = { [key] = not Plan.HasTag(pull, key) } })
			end
			changed()
		end)
		b.markKey = key
		b.dpGround = "surface"
		ed.toggles[#ed.toggles + 1] = b
	end
	W.SetTooltip(ed.toggles[#ed.toggles], L["tag:lust"], L["Plan Bloodlust or Heroism on this pull. Shown in the steps and in run mode."])
	W.SetTooltip(ed.toggles[#ed.toggles - 1], L["tag:cd"], L["Plan the group's big cooldowns on this pull."])
	-- Lay the toggles out in lines as wide as the editor.
	function ed:FlowMarks()
		local width = self.marks:GetWidth()
		if not width or width <= 0 then
			width = 420
		end
		local x, y = 0, 0
		for _, b in ipairs(self.toggles) do
			local w = b:GetWidth()
			if x > 0 and x + w > width then
				x, y = 0, y + SZ.control + SP.xs
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.marks, "TOPLEFT", x, -y)
			x = x + w + SP.xs
		end
		self.marks:SetHeight(y + SZ.control)
	end
	ed.marks:SetScript("OnSizeChanged", function()
		ed:FlowMarks()
	end)

	ed.progressLabel = W.Label(ed, L["Forces after this pull (%)"])
	ed.progressLabel:SetPoint("TOPLEFT", ed.marks, "BOTTOMLEFT", 0, -SP.md)
	ed.progress = W.Input(ed, {
		width = 64,
		maxBytes = 3,
		numeric = true,
		onCommit = function(text)
			local p, pull = plan(), selected()
			if pull then
				local v = tonumber(text)
				Plan.UpdatePull(p, pull.id, { progress = v or false })
				changed()
			end
		end,
	})
	ed.progress:SetPoint("TOPLEFT", ed.progressLabel, "BOTTOMLEFT", 0, -SP.xs)
	ed.progressHint = W.Text(ed, "caption", "muted")
	ed.progressHint:SetPoint("LEFT", ed.progress, "RIGHT", SP.sm, 0)
	ed.progressHint:SetPoint("RIGHT")
	ed.progressHint:SetText(L["Planned enemy forces or a checkpoint; run mode shows it. Empty: none."])

	ed.noteLabel = W.Label(ed, L["Note (what to watch for, who interrupts, CC)"])
	ed.noteLabel:SetPoint("TOPLEFT", ed.progress, "BOTTOMLEFT", 0, -SP.md)
	ed.note = W.MultiLine(ed, {
		maxBytes = Schema.TEXT.note,
		onCommit = function(text)
			local p, pull = plan(), selected()
			if pull then
				Plan.UpdatePull(p, pull.id, { note = text })
				changed()
			end
		end,
	})
	ed.note:SetPoint("TOPLEFT", ed.noteLabel, "BOTTOMLEFT", 0, -SP.xs)
	ed.note:SetPoint("RIGHT")
	ed.note:SetHeight(100)

	ed.members = W.Paragraph(ed, "body", "muted")
	ed.members:SetPoint("TOPLEFT", ed.note, "BOTTOMLEFT", 0, -SP.md)
	ed.members:SetPoint("RIGHT")

	ed.show = W.Button(ed, L["Show on map"], "outline", function()
		local pull = selected()
		if pull then
			ctx.focusPull = pull.id
			ctx.currentPull = pull.id
			ctx:ShowTab("map")
		end
	end)
	ed.show:SetPoint("TOPLEFT", ed.members, "BOTTOMLEFT", 0, -SP.md)
	ed.show.dpGround = "surface"
	ed.clearFocus = W.Button(ed, L["Show all pulls"], "outline", function()
		ctx.focusPull = nil
		f:Refresh()
	end)
	ed.clearFocus:SetPoint("LEFT", ed.show, "RIGHT", SP.sm, 0)
	ed.delete = W.Button(ed, L["Delete pull"], "outline", function()
		local p, pull = plan(), selected()
		if pull then
			Plan.RemovePull(p, pull.id)
			if ctx.focusPull == pull.id then
				ctx.focusPull = nil
			end
			selectedId = nil
			changed()
		end
	end)
	ed.delete:SetPoint("LEFT", ed.show, "RIGHT", SP.sm, 0)
	ed.delete.dpGround = "surface"
	W.SetTooltip(ed.clearFocus, L["Show all pulls"], L["The map stops highlighting one pull."])

	-- Read-only view: the pull as text, with the same map buttons.
	local doc = W.Document(f)
	doc:SetPoint("TOPLEFT", f.list, "TOPRIGHT", SP.xl, 0)
	doc:SetPoint("BOTTOMRIGHT")
	f.doc = doc
	local actions = CreateFrame("Frame", nil, doc.content)
	actions:SetSize(300, SZ.control)
	actions.show = W.Button(actions, L["Show on map"], "outline", function()
		ed.show:GetScript("OnClick")(ed.show, "LeftButton")
	end)
	actions.show:SetPoint("LEFT")
	actions.show.dpGround = "surface"
	actions.all = W.Button(actions, L["Show all pulls"], "outline", function()
		ctx.focusPull = nil
		f:Refresh()
	end)
	actions.all:SetPoint("LEFT", actions.show, "RIGHT", SP.sm, 0)
	actions.all.dpGround = "surface"
	f.actions = actions

	local function memberText(p, pull)
		local markers = Plan.MarkersOfPull(p, pull.id)
		local names = {}
		for _, m in ipairs(markers) do
			names[#names + 1] = m.label ~= "" and m.label or L[m.kind]
		end
		return markers, names
	end

	local function showDocument(p, pull, index)
		doc:Begin()
		doc:Add("title", index .. ". " .. pull.name)
		local marks = ns.UI.PullMarks(pull, { long = true })
		if marks ~= "" then
			doc:Add("muted", marks)
		end
		if pull.progress then
			doc:Add("muted", string.format(L["Forces after this pull: %d%%"], pull.progress))
		end
		doc:Add("text", pull.note ~= "" and pull.note or L["No note for this pull."])
		local markers, names = memberText(p, pull)
		if #markers > 0 then
			doc:Add("heading", L["On the map"])
			doc:Add("muted", table.concat(names, ", "))
		end
		-- Where it comes in the run: its step and the boss it leads to (Model/Steps.lua).
		local steps = ctx:Steps()
		for i, step in ipairs(steps) do
			if step.kind == "pull" and step.pull == pull.id then
				doc:Add("heading", L["In the run"])
				local _, bossStep = ns.Steps.Next(steps, i, "boss")
				local enc = bossStep and Util.FindById(p.encounters, bossStep.encounter)
				doc:Add("muted", enc and string.format(L["Step %d of %d, before %s"], i, #steps, ns.Names.Encounter(enc))
					or string.format(L["Step %d of %d"], i, #steps))
				break
			end
		end
		doc:Space(SP.lg)
		actions.all:SetShown(ctx.focusPull ~= nil)
		doc:Place(actions, SZ.control)
		doc:Finish()
	end

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		if selectedId and not Util.FindById(p.pulls, selectedId) then
			selectedId = nil
		end
		if not selectedId and p.pulls[1] then
			selectedId = p.pulls[1].id
		end
		self:SizeList()
		self.list:SetItems(p.pulls)
		local ro = ctx:ReadOnly()
		-- Read-only plans have nothing to add or reorder: the toolbar goes and the list moves up.
		self.add:SetShown(not ro)
		self.up:SetShown(not ro)
		self.down:SetShown(not ro)
		self.up:SetDisabled(not selectedId)
		self.down:SetDisabled(not selectedId)
		self.list:ClearAllPoints()
		if ro then
			self.list:SetPoint("TOPLEFT")
		else
			self.list:SetPoint("TOPLEFT", self.add, "BOTTOMLEFT", 0, -SP.md)
		end
		self.list:SetPoint("BOTTOMLEFT")
		local pull = selected()
		ed:SetShown(pull ~= nil and not ro)
		doc:SetShown(pull ~= nil and ro)
		if pull and ro then
			showDocument(p, pull, select(2, Util.FindById(p.pulls, pull.id)))
			return
		end
		if pull then
			ed.name:SetValue(pull.name)
			ed.color:Refresh()
			ed.note:SetValue(pull.note)
			for _, b in ipairs(ed.toggles) do
				local key = b.markKey
				local on = (key == "cd" and pull.cd) or (key == "lust" and pull.lust) or Plan.HasTag(pull, key)
				b:SetActive(on and true or false)
			end
			ed:FlowMarks()
			ed.progress:SetValue(pull.progress and tostring(pull.progress) or "")
			ed.clearFocus:SetShown(ctx.focusPull ~= nil)
			ed.delete:ClearAllPoints()
			ed.delete:SetPoint("LEFT", ed.clearFocus:IsShown() and ed.clearFocus or ed.show, "RIGHT", SP.sm, 0)
			local markers, names = memberText(p, pull)
			ed.members:SetText(#markers == 0 and L["No markers in this pull yet. On the Map tab, pick the Pull tool and click markers."]
				or ns.Plural(#markers, L["%d marker: %s|%d markers: %s"], table.concat(names, ", ")))
			ed.delete:SetDisabled(ro)
		end
	end
	return f
end
