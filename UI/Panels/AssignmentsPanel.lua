-- Assignments tab: who does what (per boss and phase), the raid groups, and "Post to chat" for the group.
-- Targets are a player, a role, a raid group or everyone. Dungeon Planner never moves players between groups; groups
-- here are the plan, and "Fill from my raid" copies the current layout into it. A dungeon shows its party instead:
-- tank, healer and three damage dealers, filled from the party by the roles players chose.
-- A switch over the left column shows the assignments or the raid pages (UI/Panels/PagesEditor.lua); the groups stay.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema = ns.Plan, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

-- The groups column: about two fifths of the section (300 to 440 px), so a dungeon's party box does not sit far off on
-- the right of an empty assignments column; f:LayoutColumns sets it on every resize.
local GROUPS_MIN, GROUPS_MAX, GROUPS_SHARE = 300, 440, 0.42
local GROUPS_SHARE_PARTY = 0.5 -- a dungeon's party: two even columns


local Panel = {}
ns.Panels.assignments = Panel

-- The current group's member names (never secret values).
local function roster()
	local names = {}
	local function add(name)
		name = Util.ShortName(name)
		if name and not Util.IndexOf(names, name) then
			names[#names + 1] = name
		end
	end
	if IsInRaid and IsInRaid() and GetRaidRosterInfo then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
			add((GetRaidRosterInfo(i)))
		end
	else
		add(UnitName and UnitName("player"))
		for i = 1, 4 do
			if UnitExists and UnitExists("party" .. i) then
				add(UnitName("party" .. i))
			end
		end
	end
	table.sort(names)
	return names
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
	return target
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

	f.filter = W.Dropdown(f, {
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
	-- Assignments or pages, over the left column.
	local MODE_TOP = -(SZ.control + SP.md)
	f.mode = W.Tabs(f, {
		{ id = "assignments", text = L["Assignments"] },
		{ id = "pages", text = L["Pages"] },
	}, function(id)
		ns.db.ui.partyMode = id
		f:Refresh()
	end)
	f.mode:SetPoint("TOPLEFT")
	f.filter:SetPoint("TOPLEFT", 0, MODE_TOP)
	f.pages = ns.PagesEditor.Create(f, ctx)
	f.pages:SetPoint("TOPLEFT", 0, MODE_TOP)
	f.pages:SetPoint("BOTTOMRIGHT", -(GROUPS_MIN + SP.xl), 0)

	f.add = W.Button(f, L["Add assignment"], "red", function()
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

	f.post = W.Button(f, L["Post to chat"], "outline", function()
		f:PostToChat()
	end)
	f.post:SetPoint("LEFT", f.add, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.post, L["Post to chat"], L["Sends the shown assignments to your group chat, one line at a time."])

	-- List.
	f.list = W.List(f, {
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
				meta = meta .. " \194\183 " .. (enc.phases[a.phase].name ~= "" and enc.phases[a.phase].name or (L["Phase"] .. " " .. a.phase))
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
	f.list:SetPoint("TOPLEFT", f.filter, "BOTTOMLEFT", 0, -SP.md)
	f.list:SetPoint("RIGHT", -(GROUPS_MIN + SP.xl), 0)
	f.list:SetPoint("BOTTOM", 0, SZ.control * 2 + SP.md * 3 + 16)

	-- Editor under the list.
	local ed = CreateFrame("Frame", nil, f)
	ed:SetPoint("TOPLEFT", f.list, "BOTTOMLEFT", 0, -SP.md)
	ed:SetPoint("BOTTOMRIGHT", -(GROUPS_MIN + SP.xl), 0)
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
			if a and not a.target:find(":") and a.target ~= "all" and not Util.IndexOf(names, a.target) then
				table.insert(names, 1, a.target)
			end
			for _, name in ipairs(names) do
				out[#out + 1] = { text = name, value = name }
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
	ed.task:SetPoint("RIGHT")

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

	-- Groups: a dungeon's party (tank, healer, three damage dealers) or a raid's eight groups (a scrolling grid). In a
	-- dungeon plan the party is stored in groups 1-3 by role: 1 = tank, 2 = healer, 3 = damage.
	local groups = CreateFrame("Frame", nil, f)
	groups:SetPoint("TOPRIGHT")
	groups:SetPoint("BOTTOMRIGHT")
	groups:SetWidth(GROUPS_MIN)
	f.groups = groups
	groups.title = W.Heading(groups, L["Raid groups"], nil, true)
	groups.title:SetPoint("TOPLEFT")

	local function isParty()
		local p = plan()
		return p ~= nil and p.instance.kind ~= "raid"
	end

	local function askName(title, g)
		W.AskText(title, L["Type the player's name."], "", function(name)
			local p = plan()
			if p and name ~= "" then
				local ok, err = Plan.SetGroup(p, name, g)
				if not ok then
					ns:Print(L["Could not add the player:"], err)
				end
				changed()
			end
		end)
	end

	local function memberMenu(self)
		local p = plan()
		if p and self.name and not ctx:ReadOnly() then
			W.Menu(self, {
				{ title = self.name },
				{
					L["Remove from group"],
					function()
						Plan.SetGroup(p, self.name, nil)
						changed()
					end,
				},
			})
		end
	end

	groups.fill = W.Button(groups, L["Fill from my raid"], "outline", function()
		local p = plan()
		if not p then
			return
		end
		if isParty() then
			-- The party by the roles players chose (UnitGroupRolesAssigned): tank, healer, damage.
			if not (IsInGroup and IsInGroup()) then
				ns:Print(L["You are not in a group."])
				return
			end
			for g = 1, Schema.MAX.groups do
				p.groups[g] = {}
			end
			local units = { "player", "party1", "party2", "party3", "party4" }
			for _, unit in ipairs(units) do
				if UnitExists and UnitExists(unit) then
					local name = Util.ShortName(UnitName(unit))
					local role = UnitGroupRolesAssigned and Util.Plain(UnitGroupRolesAssigned(unit)) or nil
					local g = role == "TANK" and 1 or role == "HEALER" and 2 or 3
					if name and #p.groups[g] >= (g == 3 and 3 or 1) then
						g = #p.groups[3] < 3 and 3 or (#p.groups[1] < 1 and 1 or 2)
					end
					if name then
						Plan.SetGroup(p, name, g)
					end
				end
			end
			changed()
			return
		end
		if not (IsInRaid and IsInRaid() and GetRaidRosterInfo) then
			ns:Print(L["You are not in a raid."])
			return
		end
		for g = 1, Schema.MAX.groups do
			p.groups[g] = {}
		end
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup = GetRaidRosterInfo(i)
			name, subgroup = Util.ShortName(name), Util.Plain(subgroup)
			if name and Util.IsInteger(subgroup) then
				Plan.SetGroup(p, name, subgroup)
			end
		end
		changed()
	end)
	groups.fill:SetPoint("TOPRIGHT", 0, 2)
	groups.fill.dpGround = "surface"

	-- Party: five rows (role icon, role, name or "+").
	local PARTY = { { "TANK", 1, 1 }, { "HEALER", 2, 1 }, { "DAMAGER", 3, 1 }, { "DAMAGER", 3, 2 }, { "DAMAGER", 3, 3 } }
	local ROLE_ART = { TANK = "role_TANK", HEALER = "role_HEALER", DAMAGER = "role_MELEE" }
	local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
	local party = W.Panel(groups, "surface", "hairline")
	party:SetPoint("TOPLEFT", 0, -(SZ.control + SP.md))
	party:SetPoint("RIGHT")
	-- Rows of the larger size (34 px), with the role glyph a little bigger: the party is the column's whole content.
	local PARTY_ROW = 34
	party:SetHeight(#PARTY * (PARTY_ROW + SP.xs) + SP.sm * 2)
	groups.party = party
	party.rows = {}
	for i, slot in ipairs(PARTY) do
		local row = CreateFrame("Button", nil, party)
		row:SetHeight(PARTY_ROW)
		row:SetPoint("TOPLEFT", SP.sm, -(SP.sm + (i - 1) * (PARTY_ROW + SP.xs)))
		row:SetPoint("RIGHT", -SP.sm, 0)
		row.icon = W.RoundIcon(row, 22, "pinRing")
		row.icon:SetPoint("LEFT", 6, 0)
		ns.Art.Set(row.icon.icon, ROLE_ART[slot[1]])
		row.role = W.Text(row, "body", "muted")
		row.role:SetPoint("LEFT", row.icon, "RIGHT", SP.md, 0)
		row.role:SetWidth(70)
		row.role:SetText(L[ROLE_TEXT[slot[1]]])
		row.text = W.Text(row, "body", "ink")
		row.text:SetPoint("LEFT", row.role, "RIGHT", SP.sm, 0)
		row.text:SetPoint("RIGHT", -28, 0)
		row.add = W.IconButton(row, "+", L["Add a player"], function()
			askName(L[ROLE_TEXT[slot[1]]], slot[2])
		end)
		row.add:SetPoint("RIGHT")
		row.slot = slot
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", memberMenu)
		party.rows[i] = row
	end
	-- The role column is as wide as its longest name ("Zadający obrażenia" in Polish), within reason.
	local roleW = 0
	for _, row in ipairs(party.rows) do
		local w = row.role.GetUnboundedStringWidth and row.role:GetUnboundedStringWidth() or row.role:GetStringWidth()
		roleW = math.max(roleW, math.ceil(tonumber(w) or 0))
	end
	roleW = math.min(150, math.max(70, roleW + 2))
	for _, row in ipairs(party.rows) do
		row.role:SetWidth(roleW)
	end
	-- How the seats fill, under the box.
	party.hint = W.Paragraph(groups, "caption", "muted")
	party.hint:SetPoint("TOPLEFT", party, "BOTTOMLEFT", SP.xs, -SP.sm)
	party.hint:SetPoint("RIGHT", -SP.xs, 0)
	party.hint:SetText(L["Fill from my party takes the roles your group chose; + adds a name by hand. Right-click a name to remove it."])

	-- Raid: the eight groups in two columns, scrolling when the window is short.
	local grid = W.ScrollArea(groups)
	grid:SetPoint("TOPLEFT", 0, -(SZ.control + SP.md))
	grid:SetPoint("BOTTOMRIGHT")
	groups.grid = grid
	groups.boxes = {}
	-- Names start under the box's "+" button (24 px tall at 2 px from the top), so the two never overlap.
	local NAMES_TOP = 28
	local boxH = 5 * 16 + NAMES_TOP + SP.xs
	-- Two boxes a line, as wide as the column allows (f:LayoutColumns).
	local function placeBoxes()
		local boxW = ((f.groupsW or GROUPS_MIN) - SP.md - SP.sm) / 2
		for g, box in ipairs(groups.boxes) do
			box:SetSize(boxW, boxH)
			local col, row = (g - 1) % 2, math.floor((g - 1) / 2)
			box:ClearAllPoints()
			box:SetPoint("TOPLEFT", col * (boxW + SP.sm), -(row * (boxH + SP.sm)))
		end
	end
	for g = 1, Schema.MAX.groups do
		local box = CreateFrame("Frame", nil, grid.content)
		S.Surface(box, "surface", S.RADIUS.container, "hairline")
		box.title = W.Text(box, "caption", "muted")
		box.title:SetPoint("TOPLEFT", SP.sm, -SP.xs)
		box.title:SetText(string.format(L["Group %s"], g))
		box.addButton = W.IconButton(box, "+", L["Add a player to this group"], function()
			askName(string.format(L["Group %s"], g), g)
		end)
		box.addButton:SetPoint("TOPRIGHT", -2, -2)
		box.names = {}
		for i = 1, Schema.MAX.groupSize do
			local b = CreateFrame("Button", nil, box)
			b:SetHeight(16)
			b:SetPoint("TOPLEFT", SP.sm, -(NAMES_TOP + (i - 1) * 16))
			b:SetPoint("RIGHT", -SP.sm, 0)
			b.text = W.Text(b, "caption", "ink")
			b.text:SetAllPoints()
			b:SetScript("OnClick", memberMenu)
			box.names[i] = b
		end
		groups.boxes[g] = box
	end
	placeBoxes()
	grid:SetContentHeight(math.ceil(Schema.MAX.groups / 2) * (boxH + SP.sm))

	-- The two columns share the width: the groups take about two fifths, the left column the rest.
	function f:LayoutColumns()
		local share = isParty() and GROUPS_SHARE_PARTY or GROUPS_SHARE
		local w = math.floor(math.max(GROUPS_MIN, math.min(GROUPS_MAX, (self:GetWidth() or 0) * share)))
		if w == f.groupsW then
			return
		end
		self.groupsW = w
		groups:SetWidth(w)
		self.pages:SetPoint("BOTTOMRIGHT", -(w + SP.xl), 0)
		self.list:SetPoint("RIGHT", -(w + SP.xl), 0)
		self.editor:SetPoint("BOTTOMRIGHT", -(w + SP.xl), 0)
		placeBoxes()
	end
	f:SetScript("OnSizeChanged", function(self)
		self:LayoutColumns()
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
		self.filter:Refresh()
		self.list:SetItems(items)
		-- A recommended plan has none: say how to get some.
		self.list.emptyText:SetText(ctx:ReadOnly() and L["No assignments in a recommended plan. Make an editable copy to say who does what, per boss."]
			or L["No assignments yet."])
		local ro = ctx:ReadOnly()
		self.add:SetShown(not ro)
		self.post:ClearAllPoints()
		if ro then
			self.post:SetPoint("LEFT", self.filter, "RIGHT", SP.sm, 0)
		else
			self.post:SetPoint("LEFT", self.add, "RIGHT", SP.sm, 0)
		end
		local a = selected()
		ed:SetShown(a ~= nil and not ro)
		if a then
			ed.who:Refresh()
			ed.task:SetValue(a.task)
			ed.encounter:Refresh()
			ed.phase:Refresh()
			ed.phase:SetShown(a.encounter ~= nil)
			ed.delete:SetDisabled(ro)
		end
		-- Assignments or pages in the left column.
		local pagesMode = ns.db.ui.partyMode == "pages"
		self.mode:Select(pagesMode and "pages" or "assignments")
		self.pages:SetShown(pagesMode)
		if pagesMode then
			self.pages:Refresh()
			for _, w in ipairs({ self.filter, self.add, self.post, self.list, ed }) do
				w:Hide()
			end
		else
			self.filter:Show()
			self.list:Show()
			self.post:Show()
		end
		self:LayoutColumns()
		local partyMode = isParty()
		groups.title:SetText(partyMode and L["Party"] or L["Raid groups"])
		groups.fill:SetLabel(partyMode and L["Fill from my party"] or L["Fill from my raid"])
		groups.fill:SetShown(not ro)
		groups.party:SetShown(partyMode)
		groups.party.hint:SetShown(partyMode and not ro)
		groups.grid:SetShown(not partyMode)
		if partyMode then
			for _, row in ipairs(groups.party.rows) do
				local name = (p.groups[row.slot[2]] or {})[row.slot[3]]
				row.name = name
				row.text:SetText(name or L["empty"])
				S.TextColor(row.text, name and "ink" or "dim")
				row.add:SetShown(not ro and name == nil and #(p.groups[row.slot[2]] or {}) < row.slot[3])
			end
		else
			for g, box in ipairs(groups.boxes) do
				local members = p.groups[g] or {}
				for i, b in ipairs(box.names) do
					b.name = members[i]
					b.text:SetText(members[i] or "")
					b:SetShown(members[i] ~= nil)
				end
				box.addButton:SetShown(not ro)
				box.addButton:SetDisabled(#members >= Schema.MAX.groupSize)
			end
		end
	end
	return f
end
