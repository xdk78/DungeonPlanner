-- The map's marker editor, in the floating legend panel (UI/Panels/MapPanel.lua): the fields a marker kind uses (label,
-- kind, role, raid mark, pull, boss, the floor a door leads to, note) and Delete, for the player's own plans; for a
-- recommended plan the same panel shows the marker's details as text.

local _, ns = ...
local MapEditor = ns:NewModule("MapEditor")
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Schema = ns.Plan, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local ICON_NAMES = { "None", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local HEAD_H = 56 -- the boss header: portrait, name, level

-- h = { plan(), changed(what), readOnly(), selected(), kindOptions(), roleOptions(), width }
function MapEditor.Build(f, ctx, rail, h)
	local plan, changed, readOnly, selected = h.plan, h.changed, h.readOnly, h.selected
	local kindOptions, roleOptions, width = h.kindOptions, h.roleOptions, h.width
	-- Marker editor (own plans) and details (recommended plans).
	local ed = CreateFrame("Frame", nil, rail)
	ed:SetPoint("TOPLEFT", SP.md, -SP.md)
	ed:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
	local function update(fields, what)
		local p, m = plan(), selected()
		if p and m and not readOnly() then
			Plan.UpdateMarker(p, m.id, fields)
			changed(what or "markers")
		end
	end

	ed.close = W.IconButton(ed, "x", L["Close"], function()
		ctx.selectedMarker = nil
		f:Refresh()
	end)
	ed.close:SetPoint("TOPRIGHT", 0, 4)
	-- The title stops before the close button: a long one ("Druids of the Fang and vipers near Anacondra") is cut after
	-- a whole word, with the whole title in a tooltip.
	ed.heading = W.Heading(ed, L["Marker"])
	ed.heading:SetPoint("TOPLEFT")
	ed.heading:SetPoint("RIGHT", ed.close, "LEFT", -SP.xs, 0)
	local headTip = CreateFrame("Frame", nil, ed)
	headTip:SetAllPoints(ed.heading)
	headTip:SetScript("OnEnter", function(self)
		W.FullTextTooltip(self, ed.heading)
	end)
	headTip:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	ed.headTip = headTip
	-- Set the title (cut to fit; the tooltip only while it is cut).
	function ed:SetTitle(text)
		self.title = text
		local _, cut = W.FitText(self.heading, text)
		headTip:EnableMouse(cut)
	end
	-- Fitted again when the pane's size changes: on first open the heading has no width yet when the title is set.
	ed:HookScript("OnSizeChanged", function(self)
		if self.title then
			self:SetTitle(self.title)
		end
	end)
	-- Details of a recommended plan's marker: a scrolling document (a boss: portrait, name and level, then what Dungeon
	-- Journal states about it, the plan's strategy and the note).
	ed.details = W.Document(ed)
	ed.details:SetPoint("TOPLEFT", 0, -(18 + SP.md))
	ed.details:SetPoint("BOTTOMRIGHT")
	local head = CreateFrame("Frame", nil, ed.details.content)
	head:SetHeight(HEAD_H)
	head.portrait = W.Portrait(head, 44)
	head.portrait:SetPoint("LEFT", SP.sm, 0)
	head.name = W.Text(head, "title", "gold")
	head.name:SetPoint("BOTTOMLEFT", head.portrait, "RIGHT", SP.md + 2, 0)
	head.name:SetPoint("RIGHT", 0, 0)
	head.meta = W.Text(head, "caption", "muted")
	head.meta:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -SP.xxs)
	head.meta:SetPoint("RIGHT", 0, 0)
	ed.head = head

	local form = CreateFrame("Frame", nil, ed)
	form:SetPoint("TOPLEFT", 0, -(18 + SP.sm))
	form:SetPoint("BOTTOMRIGHT")
	ed.form = form
	local y = 0
	local rows = {}
	local function label(text)
		local fs = W.Label(form, text)
		fs:SetPoint("TOPLEFT", 0, y)
		y = y - 12 - SP.xxs
		return fs
	end
	local function place(widget, height)
		widget:SetPoint("TOPLEFT", 0, y)
		widget:SetPoint("RIGHT", 0, 0)
		y = y - (height or SZ.control) - SP.sm
	end
	local function field(key, text, widget)
		local startY = y
		local lbl = label(text)
		place(widget)
		rows[key] = { label = lbl, widget = widget, y = startY }
	end

	field("label", L["Label"], W.Input(form, {
		maxBytes = Schema.TEXT.label,
		placeholder = L["For example: Patrol, Caster pack"],
		onCommit = function(text)
			update({ label = text })
		end,
	}))
	ed.label = rows.label.widget
	field("kind", L["Kind"], W.Dropdown(form, {
		width = width,
		options = function()
			local out = kindOptions()
			out[#out + 1] = { text = L.position, value = "position" }
			return out
		end,
		get = function()
			local m = selected()
			return m and m.kind
		end,
		set = function(v)
			update({ kind = v })
		end,
	}))
	ed.kind = rows.kind.widget
	field("role", L["Role"], W.Dropdown(form, {
		width = width,
		options = roleOptions,
		get = function()
			local m = selected()
			return m and m.role
		end,
		set = function(v)
			update({ role = v })
		end,
	}))
	ed.role = rows.role.widget
	field("icon", L["Raid mark"], W.Dropdown(form, {
		width = width,
		options = function()
			local out = {}
			for i, name in ipairs(ICON_NAMES) do
				out[#out + 1] = { text = L[name], value = i - 1 }
			end
			return out
		end,
		get = function()
			local m = selected()
			return m and m.icon or 0
		end,
		set = function(v)
			update({ icon = v })
		end,
	}))
	ed.icon = rows.icon.widget
	field("pull", L["Pull"], W.Dropdown(form, {
		width = width,
		placeholder = L["Not in a pull"],
		options = function()
			local out = { { text = L["Not in a pull"], value = false } }
			local p = plan()
			for i, pull in ipairs(p and p.pulls or {}) do
				out[#out + 1] = { text = i .. ". " .. pull.name, value = pull.id }
			end
			return out
		end,
		get = function()
			local m = selected()
			return m and m.pull or false
		end,
		set = function(v)
			update({ pull = v }, "pulls")
		end,
	}))
	ed.pull = rows.pull.widget
	field("encounter", L["Boss"], W.Dropdown(form, {
		width = width,
		placeholder = L["None"],
		options = function()
			local out = { { text = L["None"], value = false } }
			local p = plan()
			for _, enc in ipairs(p and p.encounters or {}) do
				out[#out + 1] = { text = ns.Names.Encounter(enc), value = enc.id }
			end
			return out
		end,
		get = function()
			local m = selected()
			return m and m.encounter or false
		end,
		set = function(v)
			update({ encounter = v })
		end,
	}))
	ed.encounter = rows.encounter.widget
	field("toFloor", L["Leads to"], W.Dropdown(form, {
		width = width,
		placeholder = L["Nowhere"],
		options = function()
			local out = { { text = L["Nowhere"], value = false } }
			local p = plan()
			for i, floor in ipairs(p and p.floors or {}) do
				out[#out + 1] = { text = ns.Names.Floor(floor, i, p), value = i }
			end
			return out
		end,
		get = function()
			local m = selected()
			return m and m.toFloor or false
		end,
		set = function(v)
			update({ toFloor = v or false })
		end,
	}))
	ed.toFloor = rows.toFloor.widget
	rows.note = { label = label(L["Note"]), y = y }
	ed.note = W.MultiLine(form, {
		maxBytes = Schema.TEXT.note,
		onCommit = function(text)
			update({ note = text })
		end,
	})
	ed.note:SetPoint("TOPLEFT", rows.note.label, "BOTTOMLEFT", 0, -SP.xxs)
	ed.note:SetPoint("RIGHT", 0, 0)
	ed.note:SetPoint("BOTTOM", 0, SZ.control + SP.sm)
	ed.delete = W.Button(form, L["Delete marker"], "red", function()
		local p, m = plan(), selected()
		if p and m and not readOnly() then
			Plan.RemoveMarker(p, m.id)
			ctx.selectedMarker = nil
			changed("markers")
		end
	end)
	ed.delete:SetPoint("BOTTOMLEFT")

	-- Show the fields a kind uses, stacked without gaps.
	local ORDER = { "label", "kind", "role", "icon", "pull", "encounter", "toFloor" }
	local function layoutForm(m)
		local yy = 0
		for _, key in ipairs(ORDER) do
			local row = rows[key]
			local show = true
			if key == "role" then
				show = m.kind == "position"
			elseif key == "toFloor" then
				local p = plan()
				show = Schema.LINK_KINDS[m.kind] == true and p ~= nil and #p.floors > 1
			end
			row.label:SetShown(show)
			row.widget:SetShown(show)
			if show then
				row.label:ClearAllPoints()
				row.label:SetPoint("TOPLEFT", 0, yy)
				row.widget:ClearAllPoints()
				row.widget:SetPoint("TOPLEFT", 0, yy - 12 - SP.xxs)
				row.widget:SetPoint("RIGHT", 0, 0)
				yy = yy - 12 - SP.xxs - SZ.control - SP.sm
			end
		end
		rows.note.label:ClearAllPoints()
		rows.note.label:SetPoint("TOPLEFT", 0, yy)
	end

	-- The details of a marker of a recommended plan (Data/BossInfo.lua decides what they say, without repeating the
	-- name): a boss marker gets its header, what Dungeon Journal states and the plan's strategy; any marker its facts
	-- and note.
	function ed:ShowDetails(p, m)
		local d = ns.BossInfo.MarkerDetail(p, m)
		local doc = self.details
		self:SetTitle(d.heading)
		doc:Begin()
		if d.boss then
			local boss = d.boss
			head.portrait:SetBoss(boss.enc and ns.Journal.BossArt(p, boss.enc) or nil)
			W.FitText(head.name, boss.name)
			local meta = ns.BossInfo.Meta(boss.info)
			head.meta:SetText(meta or "")
			head.meta:SetShown(meta ~= nil)
			-- The name sits on the portrait's middle line with the level under it; alone, it is centred on it.
			head.name:ClearAllPoints()
			head.name:SetPoint(meta and "BOTTOMLEFT" or "LEFT", head.portrait, "RIGHT", SP.md + 2, 0)
			head.name:SetPoint("RIGHT", 0, 0)
			doc:Place(head, HEAD_H, true)
			if boss.enc then
				ns.BossSections.FillDoc(doc, ns.BossInfo.Sections(p, boss.enc, { maxDrops = 6 }))
			end
			if boss.strategy then
				doc:Add("label", L["Strategy"])
				doc:Add("text", boss.strategy)
			end
		elseif d.kind then
			doc:Add("label", d.kind)
		end
		doc:Add("text", table.concat(d.lines, "\n"))
		if d.boss and (d.note or d.approx) then
			doc:Add("label", L["Note"])
		end
		if d.note then
			doc:Add("text", S.WithApprox(d.note, d.approx))
		elseif d.approx then
			doc:Add("text", S.ApproxMark())
		end
		doc:Finish()
	end

	-- Fill the panel for marker m of plan p (ro: read-only, details instead of the form).
	function ed:ShowMarker(p, m, ro)
		self.form:SetShown(not ro)
		self.details:SetShown(ro)
		if ro then
			self:ShowDetails(p, m)
		else
			self:SetTitle(m.label ~= "" and m.label or L[m.kind])
			layoutForm(m)
			self.label:SetValue(m.label)
			self.kind:Refresh()
			self.role:Refresh()
			self.icon:Refresh()
			self.pull:Refresh()
			self.encounter:Refresh()
			self.toFloor:Refresh()
			self.note:SetValue(m.note)
		end
	end
	return ed
end
