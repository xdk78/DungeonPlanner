-- Party section: who does what (per boss and phase), the party or raid groups (UI/Panels/PartyGroups.lua), and "Post
-- to chat" for the group. Targets are a player, a role, a raid group or everyone. A switch shows the assignments or
-- the raid pages (UI/Panels/PagesEditor.lua).
-- A dungeon: the party as a card of five seats, centred at the top, the assignments (or pages) under it across the
-- section. A raid: the assignments (or pages) on the left, the eight groups beside them in a grid that fills the column.
-- The list sits in an inset; its empty state is centred inside it.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema = ns.Plan, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

-- A raid's groups column: about two fifths of the section (300 to 440 px); f:Arrange sets it on every resize.
local GROUPS_MIN, GROUPS_MAX, GROUPS_SHARE = 300, 440, 0.42
local MODE_TOP = -(SZ.control + SP.md) -- under the Assignments | Pages switch
local EDITOR_H = SZ.control * 2 + SP.md -- the selected assignment's editor, under the list

local Panel = {}
ns.Panels.assignments = Panel

-- The current group's members as assignment targets: { value = the whole name (what is stored), text = the short name,
-- or the whole one where two members share it }, by text (Data/PartyInfo.lua; never secret values).
local function roster()
	local members, seen = ns.PartyInfo.Members(), {}
	for _, m in ipairs(members) do
		seen[m.name] = (seen[m.name] or 0) + 1
	end
	local out = {}
	for _, m in ipairs(members) do
		out[#out + 1] = { value = m.id, text = seen[m.name] > 1 and m.id or m.name }
	end
	table.sort(out, function(a, b)
		return a.text < b.text
	end)
	return out
end

local function targetText(target)
	local role = target:match("^role:(%u+)$")
	if role then
		return L[role == "TANK" and "Tank" or role == "HEALER" and "Healer" or "Damage"]
	end
	local group = target:match("^group:(%d)$")
	if group then
		return string.format(L["Group %s"], group)
	end
	if target == "all" then
		return L["Everyone"]
	end
	return ns.PartySeats.Short(target) -- a whole name reads as the member's short name while they are in the group
end

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local filter = "all" -- "all", "general" or an encounter id
	local selectedId

	local function plan()
		return ctx:Plan()
	end
	local function selected()
		local p = plan()
		return p and selectedId and Util.FindById(p.assignments, selectedId)
	end
	local function changed()
		ctx:Changed("assignments")
	end

	-- Assignments or pages.
	f.mode = W.Tabs(f, {
		{ id = "assignments", text = L["Assignments"] },
		{ id = "pages", text = L["Pages"] },
	}, function(id)
		ns.db.ui.partyMode = id
		f:Refresh()
	end)
	f.mode:SetPoint("TOPLEFT")

	-- The people: the party card or the raid's groups, and "Fill from my party / raid".
	local groups = ns.PartyGroups.Create(f, {
		plan = plan,
		changed = changed,
		readOnly = function()
			return ctx:ReadOnly()
		end,
	})
	f.groups = groups

	-- Where the assignments or the pages go (f:Arrange places it).
	local content = CreateFrame("Frame", nil, f)
	f.content = content
	f.pages = ns.PagesEditor.Create(content, ctx)
	f.pages:SetAllPoints()

	f.filter = W.Dropdown(content, {
		width = 200,
		options = function()
			local out = { { text = L["All bosses"], value = "all" }, { text = L["General"], value = "general" } }
			for _, enc in ipairs(plan() and plan().encounters or {}) do
				out[#out + 1] = { text = ns.Names.Encounter(enc), value = enc.id }
			end
			return out
		end,
		get = function()
			return filter
		end,
		set = function(v)
			filter = v
			f:Refresh()
		end,
	})
	f.filter:SetPoint("TOPLEFT")

	f.add = W.Button(content, L["Add assignment"], "red", function()
		local p = plan()
		if not p then
			return
		end
		local enc = (filter ~= "all" and filter ~= "general") and filter or nil
		local a, err = Plan.AddAssignment(p, "all", "", enc)
		if a then
			selectedId = a.id
			changed()
		else
			ns:Print(L["Cannot add more assignments:"], err)
		end
	end)
	f.add:SetPoint("LEFT", f.filter, "RIGHT", SP.sm, 0)

	f.post = W.Button(content, L["Post to chat"], "outline", function()
		f:PostToChat()
	end)
	f.post:SetPoint("LEFT", f.add, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.post, L["Post to chat"], L["Sends the shown assignments to your group chat, one line at a time."])

	-- The list, in an inset; with nothing in it, its message is centred in the box.
	local box = W.Panel(content)
	box:SetPoint("TOPLEFT", f.filter, "BOTTOMLEFT", 0, -SP.md)
	box:SetPoint("RIGHT")
	box:SetPoint("BOTTOM")
	f.listBox = box
	f.list = W.List(box, {
		rowHeight = SZ.row2,
		empty = L["No assignments yet."],
		create = function(row)
			row.title = W.Text(row, "body", "ink")
			row.title:SetPoint("TOPLEFT", SP.sm, -6)
			row.title:SetPoint("RIGHT", -SP.sm, 0)
			row.meta = W.Text(row, "caption", "muted")
			row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -SP.xxs)
			row.meta:SetPoint("RIGHT", -SP.sm, 0)
		end,
		update = function(row, a)
			row.title:SetText(targetText(a.target) .. ": " .. (a.task ~= "" and a.task or L["(no task yet)"]))
			local enc = a.encounter and Util.FindById(plan().encounters, a.encounter)
			local meta = enc and ns.Names.Encounter(enc) or L["General"]
			if a.phase and enc and enc.phases[a.phase] then
				meta = meta .. " \226\128\162 " .. (enc.phases[a.phase].name ~= "" and enc.phases[a.phase].name or (L["Phase"] .. " " .. a.phase))
			end
			row.meta:SetText(meta)
		end,
		isSelected = function(a)
			return a.id == selectedId
		end,
		onClick = function(a)
			selectedId = a.id
			f:Refresh()
		end,
	})
	f.list:SetPoint("TOPLEFT", SP.xs, -SP.xs)
	f.list:SetPoint("BOTTOMRIGHT", -SP.xs, SP.xs)
	local empty = f.list.emptyText
	empty:ClearAllPoints()
	empty:SetPoint("LEFT", SP.xl, 0)
	empty:SetPoint("RIGHT", -SP.xl, 0)
	empty:SetJustifyH("CENTER")

	-- Editor under the list.
	local ed = CreateFrame("Frame", nil, content)
	ed:SetPoint("BOTTOMLEFT")
	ed:SetPoint("BOTTOMRIGHT")
	ed:SetHeight(EDITOR_H)
	f.editor = ed

	local function update(fields)
		local a = selected()
		if a then
			Plan.UpdateAssignment(plan(), a.id, fields)
			changed()
		end
	end

	ed.who = W.Dropdown(ed, {
		width = 170,
		options = function()
			local out = {
				{ text = L["Everyone"], value = "all" },
				{ text = L["Tank"], value = "role:TANK" },
				{ text = L["Healer"], value = "role:HEALER" },
				{ text = L["Damage"], value = "role:DAMAGER" },
			}
			-- Raid groups make sense in raids; a dungeon party is addressed by role.
			local p = plan()
			if p and p.instance.kind == "raid" then
				for g = 1, Schema.MAX.groups do
					out[#out + 1] = { text = string.format(L["Group %s"], g), value = "group:" .. g }
				end
			end
			local a = selected()
			local names = roster()
			local listed = false
			for _, n in ipairs(names) do
				listed = listed or (a ~= nil and n.value == a.target)
			end
			if a and not a.target:find(":") and a.target ~= "all" and not listed then
				table.insert(names, 1, { value = a.target, text = targetText(a.target) })
			end
			for _, n in ipairs(names) do
				out[#out + 1] = n
			end
			out[#out + 1] = { text = L["Other player..."], value = "?" }
			return out
		end,
		get = function()
			local a = selected()
			return a and a.target
		end,
		set = function(v)
			if v == "?" then
				W.AskText(L["Player"], L["Type the player's name."], "", function(name)
					update({ target = name })
				end)
			else
				update({ target = v })
			end
		end,
	})
	ed.who:SetPoint("TOPLEFT")

	ed.task = W.Input(ed, {
		maxBytes = Schema.TEXT.task,
		placeholder = L["Task, for example: interrupt the caster"],
		onCommit = function(text)
			update({ task = text })
		end,
	})
	ed.task:SetPoint("LEFT", ed.who, "RIGHT", SP.sm, 0)
	ed.task:SetPoint("RIGHT", ed, "TOPRIGHT", 0, -SZ.control / 2) -- on the first line, as the dropdown

	ed.encounter = W.Dropdown(ed, {
		width = 170,
		options = function()
			local out = { { text = L["General"], value = false } }
			for _, enc in ipairs(plan() and plan().encounters or {}) do
				out[#out + 1] = { text = ns.Names.Encounter(enc), value = enc.id }
			end
			return out
		end,
		get = function()
			local a = selected()
			return a and a.encounter or false
		end,
		set = function(v)
			update({ encounter = v })
		end,
	})
	ed.encounter:SetPoint("TOPLEFT", ed.who, "BOTTOMLEFT", 0, -SP.md)

	ed.phase = W.Dropdown(ed, {
		width = 150,
		options = function()
			local out = { { text = L["Whole fight"], value = false } }
			local a = selected()
			local enc = a and a.encounter and Util.FindById(plan().encounters, a.encounter)
			for i, phase in ipairs(enc and enc.phases or {}) do
				out[#out + 1] = { text = phase.name ~= "" and phase.name or (L["Phase"] .. " " .. i), value = i }
			end
			return out
		end,
		get = function()
			local a = selected()
			return a and a.phase or false
		end,
		set = function(v)
			update({ phase = v })
		end,
	})
	ed.phase:SetPoint("LEFT", ed.encounter, "RIGHT", SP.sm, 0)

	ed.delete = W.Button(ed, L["Delete"], "outline", function()
		local a = selected()
		if a then
			Plan.RemoveAssignment(plan(), a.id)
			selectedId = nil
			changed()
		end
	end)
	ed.delete:SetPoint("LEFT", ed.phase, "RIGHT", SP.sm, 0)
	ed.delete.dpGround = "surface"

	-- The layout. A dungeon: the switch and "Fill from my party" on the top line, the party card centred under them,
	-- the content across the section under the card. A raid: the content on the left under the switch, the groups
	-- column on the right with its own heading and "Fill from my raid".
	function f:Arrange()
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		local party = groups.IsParty()
		groups:ClearAllPoints()
		groups.fill:ClearAllPoints()
		content:ClearAllPoints()
		if party then
			local cardW = math.floor(math.min(w, ns.PartyGroups.CARD_MAX))
			local cardH = groups:LayoutCard(math.max(200, cardW))
			groups:SetPoint("TOP", self, "TOP", 0, MODE_TOP)
			groups:SetSize(math.max(200, cardW), cardH)
			groups.card:ClearAllPoints()
			groups.card:SetAllPoints()
			groups.fill:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
			content:SetPoint("TOPLEFT", 0, MODE_TOP - cardH - SP.lg)
			content:SetPoint("BOTTOMRIGHT")
		else
			local gw = math.floor(math.max(GROUPS_MIN, math.min(GROUPS_MAX, w * GROUPS_SHARE)))
			groups:SetPoint("TOPRIGHT")
			groups:SetPoint("BOTTOMRIGHT")
			groups:SetWidth(gw)
			groups:LayoutGrid(gw, h)
			groups.fill:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
			content:SetPoint("TOPLEFT", 0, MODE_TOP)
			content:SetPoint("BOTTOMRIGHT", -(gw + SP.xl), 0)
		end
		-- The filter gives up width so its buttons stay on the line.
		local cw = party and w or (w - (groups:GetWidth() or 0) - SP.xl)
		local buttons = (self.add:IsShown() and (self.add:GetWidth() + SP.sm) or 0) + self.post:GetWidth() + SP.sm
		self.filter:SetWidth(math.floor(math.max(110, math.min(200, cw - buttons))))
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Arrange()
	end)

	-- Post to chat: lines go out spaced 0.4 s apart, out of combat only, never during a messaging lockdown.
	function f:PostToChat()
		local p = plan()
		if not p then
			return
		end
		local encId = (filter ~= "all" and filter ~= "general") and filter or nil
		local lines = Plan.AssignmentLines(p, encId)
		if filter == "general" then
			lines = {}
			for _, a in ipairs(p.assignments) do
				if not a.encounter then
					lines[#lines + 1] = targetText(a.target) .. ": " .. a.task
				end
			end
		end
		if #lines == 0 then
			ns:Print(L["Nothing to post."])
			return
		end
		local channel = ns.Comm.GroupChannel()
		if not channel then
			ns:Print(L["You are not in a group."])
			return
		end
		ns:RunOutOfCombat(function()
			if ns.Comm.IsLockedDown() then
				ns:Print(L["Chat is locked right now (boss fight). Try again after it."])
				return
			end
			local header = "[" .. ns.title .. "] " .. p.name
			if encId then
				header = header .. " - " .. ns.Names.Encounter(Util.FindById(p.encounters, encId))
			end
			table.insert(lines, 1, header)
			for i, line in ipairs(lines) do
				if i > 15 then
					break
				end
				C_Timer.After((i - 1) * 0.4, function()
					-- The global SendChatMessage is only a deprecation fallback on current clients (it exists while
					-- the loadDeprecationFallbacks setting is on); C_ChatInfo has the function itself.
					local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
					if send and not (InCombatLockdown and InCombatLockdown()) and not ns.Comm.IsLockedDown() then
						pcall(send, Util.TruncateUTF8(line, 250), channel)
					end
				end)
			end
		end)
	end

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		if filter ~= "all" and filter ~= "general" and not Util.FindById(p.encounters, filter) then
			filter = "all"
		end
		local items = {}
		for _, a in ipairs(p.assignments) do
			if filter == "all" or (filter == "general" and not a.encounter) or a.encounter == filter then
				items[#items + 1] = a
			end
		end
		local ro = ctx:ReadOnly()
		self.filter:Refresh()
		self.list:SetItems(items)
		-- A recommended plan has none: say how to get some.
		self.list.emptyText:SetText(ro and L["No assignments in a recommended plan. Make an editable copy to say who does what, per boss."]
			or L["No assignments yet."])
		self.add:SetShown(not ro)
		self.post:ClearAllPoints()
		self.post:SetPoint("LEFT", ro and self.filter or self.add, "RIGHT", SP.sm, 0)
		local a = selected()
		local editing = a ~= nil and not ro
		ed:SetShown(editing)
		box:SetPoint("BOTTOM", 0, editing and (EDITOR_H + SP.md) or 0)
		if a then
			ed.who:Refresh()
			ed.task:SetValue(a.task)
			ed.encounter:Refresh()
			ed.phase:Refresh()
			ed.phase:SetShown(a.encounter ~= nil)
			ed.delete:SetDisabled(ro)
		end
		-- Assignments or pages.
		local pagesMode = ns.db.ui.partyMode == "pages"
		self.mode:Select(pagesMode and "pages" or "assignments")
		self.pages:SetShown(pagesMode)
		for _, w in ipairs({ self.filter, self.post, box }) do
			w:SetShown(not pagesMode)
		end
		if pagesMode then
			self.add:Hide()
			ed:Hide()
			self.pages:Refresh()
		end
		groups:Refresh()
		self:Arrange()
		self.filter:Refresh() -- its text fits the width Arrange gave it
	end
	return f
end
