-- The Party section's people (UI/Panels/AssignmentsPanel.lua): a dungeon's party as a card of five seats (tank,
-- healer, three damage dealers) centred over the assignments, or a raid's eight groups in a grid that fills its column
-- beside them. Dungeon Planner never moves players between groups: groups here are the plan, and "Fill from my raid"
-- copies the current layout into it. In a dungeon plan the party is stored in groups 1-3 by role: 1 = tank, 2 =
-- healer, 3 = damage.

local _, ns = ...
local S, W, L, Art = ns.Style, ns.Widgets, ns.L, ns.Art
local Plan, Schema = ns.Plan, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local PartyGroups = {}
ns.PartyGroups = PartyGroups

local PARTY = { { "TANK", 1, 1 }, { "HEALER", 2, 1 }, { "DAMAGER", 3, 1 }, { "DAMAGER", 3, 2 }, { "DAMAGER", 3, 3 } }
-- The group finder's role glyphs (as the side panel's party strip), else the round role icons.
local ROLE_ART = { TANK = "party_TANK", HEALER = "party_HEALER", DAMAGER = "party_DAMAGER" }
local ROLE_ART_DISC = { TANK = "partyDisc_TANK", HEALER = "partyDisc_HEALER", DAMAGER = "partyDisc_DAMAGER" }
local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

local SEAT_DISC = 40 -- a seat's plate
local SEAT_H = SEAT_DISC + 4 + 14 + 2 + 18 -- plate, role, name
PartyGroups.CARD_MAX = 640 -- the party card's widest
local HEAD_H = SZ.row - 4
local NAME_H = 16 -- a name line in a group box
local NAMES_TOP = 28 -- names start under the box's "+" button (24 px tall at 2 px from the top)
PartyGroups.BOX_MIN = 5 * NAME_H + NAMES_TOP + SP.xs -- a group box with room for five names

-- o = { plan(), changed(), readOnly() }.
function PartyGroups.Create(parent, o)
	local g = CreateFrame("Frame", nil, parent)

	local function askName(title, group)
		W.AskText(title, L["Type the player's name."], "", function(name)
			local p = o.plan()
			if p and name ~= "" then
				local ok, err = Plan.SetGroup(p, name, group)
				if not ok then
					ns:Print(L["Could not add the player:"], err)
				end
				o.changed()
			end
		end)
	end

	local function memberMenu(self)
		local p = o.plan()
		if p and self.name and not o.readOnly() then
			W.Menu(self, {
				{ title = self.name },
				{
					L["Remove from group"],
					function()
						Plan.SetGroup(p, self.name, nil)
						o.changed()
					end,
				},
			})
		end
	end

	local function isParty()
		local p = o.plan()
		return p ~= nil and p.instance.kind ~= "raid"
	end
	g.IsParty = isParty

	g.fill = W.Button(parent, L["Fill from my raid"], "outline", function()
		g:Fill()
	end)
	g.fill.dpGround = "surface"

	-- The party: a card of five seats in a row, each a plate in a bronze ring with the role's glyph, the role and the
	-- player (or "Open", muted, with "+" while the plan can change). A right-click on a name removes it.
	local card = W.Panel(g)
	g.card = card
	card.title = W.Heading(card, L["Party"])
	card.title:SetPoint("TOPLEFT", SP.md, -SP.md)
	card.seats = {}
	for i, slot in ipairs(PARTY) do
		local seat = CreateFrame("Button", nil, card)
		seat:SetHeight(SEAT_H)
		seat.disc = seat:CreateTexture(nil, "ARTWORK", nil, 0)
		seat.disc:SetTexture(S.MEDIA .. "Circle")
		seat.disc:SetSize(SEAT_DISC, SEAT_DISC)
		seat.disc:SetPoint("TOP")
		seat.disc:SetVertexColor(S.Color("raised"))
		seat.glyph = seat:CreateTexture(nil, "ARTWORK", nil, 1)
		seat.glyph:SetSize(SEAT_DISC - 12, SEAT_DISC - 12)
		seat.glyph:SetPoint("CENTER", seat.disc, "CENTER")
		if not Art.Set(seat.glyph, ROLE_ART[slot[1]]) then
			Art.Set(seat.glyph, ROLE_ART_DISC[slot[1]])
		end
		seat.ring = seat:CreateTexture(nil, "OVERLAY")
		seat.ring:SetTexture(S.MEDIA .. "Ring")
		seat.ring:SetSize(SEAT_DISC + 2, SEAT_DISC + 2)
		seat.ring:SetPoint("CENTER", seat.disc, "CENTER")
		seat.role = W.Text(seat, "caption", "gold")
		seat.role:SetPoint("TOP", seat.disc, "BOTTOM", 0, -4)
		seat.role:SetJustifyH("CENTER")
		seat.text = W.Text(seat, "body", "ink")
		seat.text:SetPoint("TOP", seat.role, "BOTTOM", 0, -2)
		seat.text:SetJustifyH("CENTER")
		seat.add = W.IconButton(seat, "+", L["Add a player"], function()
			askName(L[ROLE_TEXT[slot[1]]], slot[2])
		end)
		seat.add:SetPoint("LEFT", seat.disc, "RIGHT", SP.xs, 0)
		seat.slot = slot
		seat:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		seat:SetScript("OnClick", memberMenu)
		seat:SetScript("OnEnter", function(self)
			if self.seat then
				ns.PartySeats.Tooltip(self, self.seat, self.inGroup)
			end
		end)
		seat:SetScript("OnLeave", ns.PartySeats.HideTip)
		card.seats[i] = seat
	end
	-- Members beyond the five seats (a raid on a dungeon plan): a note at the card's top right, named in its tooltip.
	card.extra = CreateFrame("Button", nil, card)
	card.extra:SetPoint("TOPRIGHT", -SP.md, -SP.md)
	card.extra:SetSize(200, HEAD_H)
	card.extra.text = W.Text(card.extra, "caption", "muted")
	card.extra.text:SetPoint("RIGHT")
	card.extra.text:SetJustifyH("RIGHT")
	card.extra:SetScript("OnEnter", function(self)
		local tt = W.Tip()
		if tt then
			W.TipBeside(tt, self)
			tt:SetText(L["Also in your group:"], 1, 0.82, 0, 1, true)
			for _, line in ipairs(self.lines or {}) do
				tt:AddLine(line, 1, 1, 1, true)
			end
			W.TipShow(tt)
		end
	end)
	card.extra:SetScript("OnLeave", ns.PartySeats.HideTip)
	card.extra:Hide()
	card.hint = W.Paragraph(card, "caption", "muted")
	card.hint:SetJustifyH("CENTER")
	card.hint:SetText(L["Fill from my party stores the seats as shown, guesses included; + adds a name by hand. Right-click a name to remove it."])

	-- The seats share the card's width; the hint under them while the plan can change.
	function g:LayoutCard(width)
		card:SetWidth(width)
		local inner = width - 2 * SP.md
		local seatW = math.floor(inner / #PARTY)
		local top = SP.md + HEAD_H + SP.sm
		for i, seat in ipairs(card.seats) do
			seat:ClearAllPoints()
			seat:SetWidth(seatW)
			seat:SetPoint("TOPLEFT", SP.md + (i - 1) * seatW, -top)
			seat.role:SetWidth(seatW - SP.xs)
			seat.text:SetWidth(seatW - SP.xs)
		end
		card.hint:ClearAllPoints()
		card.hint:SetPoint("TOPLEFT", SP.md, -(top + SEAT_H + SP.sm))
		card.hint:SetPoint("RIGHT", -SP.md, 0)
		local h = top + SEAT_H + SP.md
		if card.hint:IsShown() then
			h = h + SP.sm + math.ceil(card.hint:GetStringHeight() or 14)
		end
		card:SetHeight(h)
		return h
	end

	-- The raid: eight boxes in two columns, as tall as the column allows (never shorter than five names; then it
	-- scrolls).
	local raid = CreateFrame("Frame", nil, g)
	raid:SetAllPoints()
	g.raid = raid
	raid.title = W.Heading(raid, L["Raid groups"], nil, true)
	raid.title:SetPoint("TOPLEFT", 0, -(SZ.control - HEAD_H) / 2)
	local grid = W.ScrollArea(raid)
	grid:SetPoint("TOPLEFT", 0, -(SZ.control + SP.md))
	grid:SetPoint("BOTTOMRIGHT")
	raid.grid = grid
	raid.boxes = {}
	for gi = 1, Schema.MAX.groups do
		local box = CreateFrame("Frame", nil, grid.content)
		S.Surface(box, "surface", S.RADIUS.container, "hairline")
		box.title = W.Text(box, "caption", "gold")
		box.title:SetPoint("TOPLEFT", SP.sm, -SP.xs - 2)
		box.title:SetText(string.format(L["Group %s"], gi))
		box.count = W.Text(box, "caption", "muted")
		box.count:SetPoint("LEFT", box.title, "RIGHT", SP.xs, 0)
		box.addButton = W.IconButton(box, "+", L["Add a player to this group"], function()
			askName(string.format(L["Group %s"], gi), gi)
		end)
		box.addButton:SetPoint("TOPRIGHT", -2, -2)
		box.names = {}
		for i = 1, Schema.MAX.groupSize do
			local b = CreateFrame("Button", nil, box)
			b:SetHeight(NAME_H)
			b:SetPoint("TOPLEFT", SP.sm, -(NAMES_TOP + (i - 1) * NAME_H))
			b:SetPoint("RIGHT", -SP.sm, 0)
			b.text = W.Text(b, "caption", "ink")
			b.text:SetAllPoints()
			b:SetScript("OnClick", memberMenu)
			box.names[i] = b
		end
		raid.boxes[gi] = box
	end

	function g:LayoutGrid(width, height)
		local boxW = math.floor((width - SP.md - SP.sm) / 2)
		local rows = math.ceil(Schema.MAX.groups / 2)
		local room = (height or 0) - (SZ.control + SP.md)
		local boxH = math.max(PartyGroups.BOX_MIN, math.floor((room - (rows - 1) * SP.sm) / rows))
		for gi, box in ipairs(raid.boxes) do
			box:SetSize(boxW, boxH)
			local col, row = (gi - 1) % 2, math.floor((gi - 1) / 2)
			box:ClearAllPoints()
			box:SetPoint("TOPLEFT", col * (boxW + SP.sm), -(row * (boxH + SP.sm)))
		end
		grid:SetContentHeight(rows * boxH + (rows - 1) * SP.sm)
	end

	-- Fill from the group: the party by the roles players chose (UnitGroupRolesAssigned), the raid by its groups.
	function g:Fill()
		local p = o.plan()
		if not p then
			return
		end
		if isParty() then
			if not ns.PartyInfo.InGroup() then
				ns:Print(L["You are not in a group."])
				return
			end
			-- The seats as the strip fills them from the group (Model/Party.lua), stored by whole name so the plan
			-- matches its members again later (Share/Roster.lua). In a raid: the player's own group.
			local members = ns.PartyInfo.Members()
			local mine = members[1] and members[1].player and members[1].subgroup
			if mine then
				local own = {}
				for _, m in ipairs(members) do
					if m.subgroup == mine then
						own[#own + 1] = m
					end
				end
				members = own
			end
			local fill = ns.Party.Fill({}, members)
			for gi = 1, Schema.MAX.groups do
				p.groups[gi] = {}
			end
			for i, seat in ipairs(fill.seats) do
				if seat.member then
					Plan.SetGroup(p, seat.member.id, ns.Party.SEATS[i].group)
				end
			end
			o.changed()
			return
		end
		if not ns.PartyInfo.RaidGroups() then
			ns:Print(L["You are not in a raid."])
			return
		end
		for gi = 1, Schema.MAX.groups do
			p.groups[gi] = {}
		end
		-- The raid's groups, by whole name.
		for _, m in ipairs(ns.PartyInfo.Members()) do
			if m.subgroup then
				Plan.SetGroup(p, m.id, m.subgroup)
			end
		end
		o.changed()
	end

	function g:Refresh()
		local p = o.plan()
		if not p then
			return
		end
		grid:SetOwner(p.id)
		local ro = o.readOnly()
		local party = isParty()
		self.fill:SetLabel(party and L["Fill from my party"] or L["Fill from my raid"])
		self.fill:SetShown(not ro)
		card:SetShown(party)
		raid:SetShown(not party)
		card.hint:SetShown(not ro)
		if party then
			-- The stored seats, the group filled in where the plan stores nobody (UI/PartySeats.lua).
			local fill = ns.PartySeats.Fill(p)
			for i, seat in ipairs(card.seats) do
				local name = (p.groups[seat.slot[2]] or {})[seat.slot[3]]
				local s = fill.seats[i]
				seat.name, seat.seat, seat.inGroup = name, s, fill.inGroup
				local level = s.member and s.member.level
				W.FitText(seat.role, level and string.format(L["%s • level %d"], L[ROLE_TEXT[seat.slot[1]]], level)
					or L[ROLE_TEXT[seat.slot[1]]])
				local plate = ns.PartySeats.Paint(seat.text, s)
				seat.disc:SetAlpha(plate)
				seat.glyph:SetAlpha(plate)
				seat.ring:SetVertexColor(S.Color((name or s.member) and "borderHover" or "border"))
				seat.add:SetShown(not ro and name == nil and #(p.groups[seat.slot[2]] or {}) < seat.slot[3])
			end
			local extra = #fill.extra
			card.extra:SetShown(extra > 0)
			card.extra.lines = ns.PartySeats.ExtraLines(fill.extra)
			card.extra.text:SetText(string.format(L["+%d more in your group"], extra))
		else
			for gi, box in ipairs(raid.boxes) do
				local members = p.groups[gi] or {}
				box.count:SetText(#members .. "/" .. Schema.MAX.groupSize)
				for i, b in ipairs(box.names) do
					b.name = members[i]
					-- A whole name reads as the member's short name while they are in the group.
				b.text:SetText(members[i] and ns.PartySeats.Short(members[i]) or "")
					b:SetShown(members[i] ~= nil)
				end
				box.addButton:SetShown(not ro)
				box.addButton:SetDisabled(#members >= Schema.MAX.groupSize)
			end
		end
	end
	-- The group changes while the party card is shown: repaint it (coalesced in Data/PartyInfo.lua).
	local function cardShown()
		return card:IsVisible()
	end
	ns.PartySeats.Watch(g, cardShown, function()
		g:Refresh()
	end)
	return g
end
