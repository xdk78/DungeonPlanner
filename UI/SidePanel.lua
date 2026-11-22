-- The war table's side panel: the plan's state (a recommended plan says so and offers an editable copy), its steps
-- in order (Model/Steps.lua; the current one highlighted, click to focus the map on it), and the party at the bottom:
-- tank, healer and three damage dealers for a dungeon, the eight groups for a raid (click: the Party section).

local _, ns = ...
local SidePanel = ns:NewModule("SidePanel")
local S, W, L, Art = ns.Style, ns.Widgets, ns.L, ns.Art
local SP, SZ = S.SPACE, S.SIZE
local UI = ns.UI

local STEP_H = 38
local BADGE = 24 -- a step's icon inside its ring
local PARTY = { { "TANK", 1, 1 }, { "HEALER", 2, 1 }, { "DAMAGER", 3, 1 }, { "DAMAGER", 3, 2 }, { "DAMAGER", 3, 3 } }
local ROLE_ART = { TANK = "party_TANK", HEALER = "party_HEALER", DAMAGER = "party_DAMAGER" }
-- The group finder's round role icons, where the glyphs are missing (UI/Art.lua).
local ROLE_ART_DISC = { TANK = "partyDisc_TANK", HEALER = "partyDisc_HEALER", DAMAGER = "partyDisc_DAMAGER" }
local SLOT_DISC = 30 -- the party slot's plate
local PARTY_H = (SZ.row - 4) + SP.sm + SLOT_DISC + 2 + 14
local STEP_ART = { entrance = "kind_entrance", objective = "check" }

-- A step's badge, one look per kind of step: a boss shows its portrait in the gold ring of the game's map pins (the
-- skull until the portrait loads); a pull its own number on a disc in the pull's colour in the gold ring (as its map
-- pin); an entrance, objective or marker its icon in the gold ring (unmasked when the art is not a round icon). A move
-- (a route stop with nothing on it) is drawn as its stop on the map: a smaller dark disc ringed in the route's colour,
-- with the step's number, which the stop shows too (Steps.StopNumbers). So a step number never wears a pull's badge.
local STOP = 18 -- a move step's stop disc

-- The instance page's map (UI/MapCanvas.lua), while it is shown.
local function mapCanvas()
	local f = UI.Frame()
	local page = f and f.instancePage
	local map = page and page.panels and page.panels.map
	local canvas = map and map.canvas
	return canvas and canvas:IsVisible() and canvas or nil
end

local function stopBadge(b, plan, step, index)
	local route = step.route and ns.Util.FindById(plan.routes, step.route)
	b.disc:SetSize(STOP, STOP)
	b.disc:SetVertexColor(0.1, 0.07, 0.04, 1)
	b.ring:Hide()
	if route then
		b.stopRing:SetVertexColor(ns.MapRoutes.Color(route, true))
	else
		b.stopRing:SetVertexColor(S.PaletteColor(1))
	end
	b.stopRing:Show()
	b.num:SetText("")
	b.stopNum:SetText(tostring(index))
	b.stopNum:Show()
end

local function stepBadge(row, plan, step, index)
	local b = row.badge
	if step.kind ~= "boss" then
		Art.ReleasePortrait(b.icon) -- a pooled row that showed a boss gives its portrait back
	end
	b.icon:Hide()
	b.flat:Hide()
	b.stopRing:Hide()
	b.stopNum:Hide()
	b.ring:Show()
	b.disc:SetSize(BADGE, BADGE)
	b.disc:Show()
	b.num:SetText(tostring(index))
	local r, g, bl = 0.12, 0.09, 0.06
	if step.kind == "pull" then
		-- The pull's own number, as on its map pin and in its caption ("Pull 2").
		local pull, pullIndex = ns.Util.FindById(plan.pulls, step.pull)
		r, g, bl = S.PaletteColor(pull and pull.color or 1)
		r, g, bl = r * 0.8, g * 0.8, bl * 0.8
		b.num:SetText(tostring(pullIndex or index))
	elseif step.kind == "boss" then
		local enc = ns.Util.FindById(plan.encounters, step.encounter)
		Art.SetBossPortrait(b.icon, enc and ns.Journal.BossArt(plan, enc) or nil)
		b.icon:Show()
		b.num:SetText("")
	end
	b.disc:SetVertexColor(r, g, bl, 1)
	local art = STEP_ART[step.kind]
	if step.kind == "marker" then
		local m = ns.Util.FindById(plan.markers, step.marker)
		art = m and ns.MapPins.MarkerArt(m)
	end
	if art then
		local spec = type(art) == "table" and art or Art.SPECS[art]
		local tex = (spec and spec.round) and b.icon or b.flat
		if Art.Set(tex, art) then
			tex:Show()
			b.num:SetText("")
			return
		end
	end
	if step.kind ~= "pull" and step.kind ~= "boss" then
		stopBadge(b, plan, step, index)
	end
end

function SidePanel.Create(parent, ctx)
	local f = W.Panel(parent, "surface", "border")

	-- Plan state.
	f.state = W.Text(f, "caption", "muted")
	f.state:SetPoint("TOPLEFT", SP.md, -SP.md)
	f.state:SetPoint("RIGHT", -SP.md, 0)
	f.copy = W.Button(f, L["Make an editable copy"], "primary", function()
		local plan = ctx:Plan()
		if plan then
			UI.CopyPlan(plan)
		end
	end)
	f.copy:SetPoint("TOPLEFT", f.state, "BOTTOMLEFT", 0, -SP.sm)
	f.copy:SetPoint("RIGHT", -SP.md, 0)
	f.copy.dpFixedWidth = true
	W.SetTooltip(f.copy, L["Make an editable copy"],
		L["Recommended plans are read-only. Your copy keeps everything and can be changed and shared."])

	-- Steps: a section header (the heading on the game's header band, the count on the right) over the list.
	f.heading = W.SectionHeader(f, L["Steps"])
	f.count = f.heading.count

	f.list = W.List(f, {
		rowHeight = STEP_H,
		gap = SP.xxs,
		empty = L["No steps yet. Number route stops (Shift-click with the Route tool) or add pulls and bosses."],
		create = function(row)
			-- The badge: an icon (or a numbered disc) in a ring (stepBadge picks the ring per kind).
			local b = CreateFrame("Frame", nil, row)
			b:SetSize(BADGE, BADGE)
			b:SetPoint("LEFT", SP.sm + 2, 0)
			b.disc = b:CreateTexture(nil, "ARTWORK", nil, 0)
			b.disc:SetTexture(S.MEDIA .. "Circle")
			b.disc:SetPoint("CENTER") -- sized per kind (stepBadge, stopBadge)
			b.disc:SetSize(BADGE, BADGE)
			b.icon = Art.RoundTexture(b, "ARTWORK", 1)
			b.icon:SetAllPoints()
			b.flat = b:CreateTexture(nil, "ARTWORK", nil, 1)
			b.flat:SetSize(BADGE - 6, BADGE - 6)
			b.flat:SetPoint("CENTER")
			-- One ring for every kind (a boss's portrait included): the same outer size and centre on every row
			-- (Art.PlaceRing centres the ring on the badge).
			b.ring = b:CreateTexture(nil, "OVERLAY", nil, 1)
			Art.PlaceRing(b.ring, b, BADGE, "pinRing")
			b.num = W.Text(b, "number", "white")
			b.num:SetPoint("CENTER", 0, 0)
			b.num:SetJustifyH("CENTER")
			-- A move step's stop: the route's ring and the step number, as the stop on the map (stopBadge).
			b.stopRing = b:CreateTexture(nil, "OVERLAY", nil, 1)
			b.stopRing:SetTexture(S.MEDIA .. "Ring")
			b.stopRing:SetSize(STOP, STOP)
			b.stopRing:SetPoint("CENTER")
			b.stopRing:Hide()
			b.stopNum = W.Text(b, "caption", "white")
			b.stopNum:SetPoint("CENTER", 0, 0)
			b.stopNum:SetJustifyH("CENTER")
			b.stopNum:Hide()
			row.badge = b
			row.title = W.Text(row, "body", "ink")
			-- The two lines sit together, centred on the row and clear of its highlight's bright lines (top and bottom).
			row.title:SetPoint("TOPLEFT", b, "TOPRIGHT", SP.md, 0)
			row.title:SetPoint("RIGHT", -SP.xs, 0)
			row.caption = W.Text(row, "caption", "muted")
			row.caption:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
			row.caption:SetPoint("RIGHT", -SP.xs, 0)
		end,
		update = function(row, step, index)
			local plan = ctx:Plan()
			stepBadge(row, plan, step, index)
			local title, caption, approx = UI.StepText(plan, step)
			-- A long title is cut after a whole word; hovering the row shows it whole (with the caption and note).
			-- A quest item's name says what it is at its end ("...the Hungerer's Heart"): cut from the start.
			local m = step.kind == "marker" and ns.Util.FindById(plan.markers, step.marker)
			W.FitText(row.title, title, m and m.kind == "quest_item")
			-- A pull's tags, planned cooldowns, Bloodlust and progress follow its caption.
			if step.kind == "pull" then
				local marks = UI.PullMarks(ns.Util.FindById(plan.pulls, step.pull), { progress = true })
				if marks ~= "" then
					caption = caption .. "  •  " .. marks
				end
			end
			-- Cut after a whole word when the floor name and marks do not fit (the tooltip has it whole).
			W.FitText(row.caption, S.WithApprox(caption, approx))
			local current = ctx:StepIndex()
			S.TextColor(row.title, current == index and "white" or (current and index < current) and "muted" or "ink")
			S.TextColor(row.caption, step.kind == "boss" and "gold" or "muted")
		end,
		onClick = function(step, index)
			-- A second click on stairs or a portal (the current step) goes to the floor it leads to.
			local link = UI.StepLink(ctx:Plan(), step)
			if link and ctx:StepIndex() == index and ctx.floor ~= link then
				UI.GoToFloor(link)
				return
			end
			UI.FocusStep(index)
		end,
		onEnter = function(step, row)
			local plan = ctx:Plan()
			-- The leg of the route that leads to this step stands out on the map, as one under the pointer does.
			local canvas = mapCanvas()
			local focus = ns.Steps.Focus(step)
			if canvas and focus.route and focus.from and ns.db.settings.routes.hover ~= false then
				canvas:SetRouteHover({ route = focus.route, from = focus.from, to = focus.to }, "list")
			end
			local title, caption, _, note = UI.StepText(plan, step)
			local tt = W.Tip()
			if not (tt and plan) then
				return
			end
			if step.kind == "pull" then
				local pull = ns.Util.FindById(plan.pulls, step.pull)
				note = pull and pull.note ~= "" and pull.note or note
			end
			tt:SetOwner(row, "ANCHOR_RIGHT")
			tt:SetText(title ~= "" and title or caption, 1, 0.82, 0, 1, true)
			tt:AddLine(row.caption.dpFullText or row.caption:GetText() or caption, 0.71, 0.67, 0.59, true)
			if note and note ~= "" and note ~= title then
				tt:AddLine(note, 1, 1, 1, true)
			end
			W.TipShow(tt)
		end,
		onLeave = function()
			local canvas = mapCanvas()
			if canvas then
				canvas:ClearRouteHover("list")
			end
		end,
	})

	-- Party.
	local party = CreateFrame("Button", nil, f)
	party:SetPoint("BOTTOMLEFT", SP.md, SP.md)
	party:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
	party:SetHeight(PARTY_H)
	party:RegisterForClicks("LeftButtonUp")
	party:SetScript("OnClick", function()
		UI.SelectTab("assignments")
	end)
	-- The strip's tooltip (its text set by RefreshParty: the extras, or where raid counts come from), shown beside the
	-- strip or beside an open seat.
	party.tipTitle = L["Party"]
	party.tipText = L["Who plays which role. Click to edit the party and the assignments."]
	local function stripTip(owner)
		local tt = W.Tip()
		if tt then
			W.TipBeside(tt, owner)
			tt:SetText(party.tipTitle, 1, 0.82, 0, 1, true)
			tt:AddLine(party.tipText, 1, 1, 1, true)
			W.TipShow(tt)
		end
	end
	party:SetScript("OnEnter", stripTip)
	party:SetScript("OnLeave", ns.PartySeats.HideTip)
	f.party = party
	party.heading = W.SectionHeader(party, L["Party"])
	party.heading:SetPoint("TOPLEFT")
	party.heading:SetPoint("TOPRIGHT")
	party.slots = {}
	local function openParty()
		UI.SelectTab("assignments")
	end
	for i = 1, 8 do
		-- A button of its own for the seat's tooltip; a click opens the Party section as the strip does.
		local slot = CreateFrame("Button", nil, party)
		slot:SetSize(40, SLOT_DISC + 16)
		slot:RegisterForClicks("LeftButtonUp")
		slot:SetScript("OnClick", openParty)
		slot:SetScript("OnEnter", function(self)
			if not (self.seat and ns.PartySeats.Tooltip(self, self.seat, self.inGroup)) then
				stripTip(self)
			end
		end)
		slot:SetScript("OnLeave", ns.PartySeats.HideTip)
		-- A slate plate in a bronze ring with the role's glyph (or, for a raid, the group number) on it. The ring stays
		-- bronze for every role: a red ring around a slanted sword reads as a "no entry" sign.
		slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 0)
		slot.icon:SetTexture(S.MEDIA .. "Circle")
		slot.icon:SetSize(SLOT_DISC, SLOT_DISC)
		slot.icon:SetPoint("TOP", 0, -1)
		slot.role = slot:CreateTexture(nil, "ARTWORK", nil, 1)
		slot.role:SetSize(SLOT_DISC - 8, SLOT_DISC - 8)
		slot.role:SetPoint("CENTER", slot.icon, "CENTER")
		slot.ring = slot:CreateTexture(nil, "OVERLAY")
		slot.ring:SetTexture(S.MEDIA .. "Ring")
		slot.ring:SetSize(SLOT_DISC + 2, SLOT_DISC + 2)
		slot.ring:SetPoint("CENTER", slot.icon, "CENTER")
		slot.num = W.Text(slot, "number", "white")
		slot.num:SetPoint("CENTER", slot.icon, "CENTER")
		slot.num:SetJustifyH("CENTER")
		slot.name = W.Text(slot, "caption", "ink")
		slot.name:SetPoint("TOP", slot.icon, "BOTTOM", 0, -2)
		slot.name:SetWidth(40)
		slot.name:SetJustifyH("CENTER")
		slot.name:SetWordWrap(false)
		-- A member's level on the plate's lower right, as the game's party frames show it.
		slot.level = W.Text(slot, "caption", "ink")
		slot.level:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 5, -2)
		party.slots[i] = slot
	end

	local function isRaid(plan)
		return plan and plan.instance.kind == "raid"
	end

	-- The strip as the plan stores it, with the group filled in where it stores nobody (UI/PartySeats.lua).
	function f:RefreshParty(plan)
		local raid = isRaid(plan)
		party.heading:SetText(raid and L["Raid groups"] or L["Party"])
		local w = math.max(10, party:GetWidth())
		local n = raid and 8 or #PARTY
		local slotW = w / n
		local fill = plan and not raid and ns.PartySeats.Fill(plan)
		local counts, live = nil, false
		if plan and raid then
			counts, live = ns.PartySeats.RaidCounts(plan, n)
		end
		-- Members beyond the five seats (a raid on a dungeon plan) are named in the strip's tooltip.
		local extra = fill and #fill.extra or 0
		party.heading:SetCount(extra > 0 and ("+" .. extra) or nil)
		local tip = L["Who plays which role. Click to edit the party and the assignments."]
		if extra > 0 then
			tip = tip .. "\n\n" .. L["Also in your group:"] .. "\n" .. table.concat(ns.PartySeats.ExtraLines(fill.extra), "\n")
		elseif live then
			tip = tip .. "\n\n" .. L["Groups as your raid stands now: the plan sets none."]
		end
		party.tipTitle, party.tipText = raid and L["Raid groups"] or L["Party"], tip
		for i, slot in ipairs(party.slots) do
			slot:ClearAllPoints()
			slot.seat, slot.inGroup = nil, nil
			slot.level:SetText("")
			slot.icon:SetAlpha(1)
			slot.role:SetAlpha(1)
			slot.name:SetAlpha(1)
			if i <= n and plan then
				slot:SetWidth(slotW)
				slot:SetPoint("TOPLEFT", party, "TOPLEFT", (i - 1) * slotW, -((SZ.row - 4) + SP.sm))
				slot.name:SetWidth(slotW)
				slot:Show()
				slot.icon:SetVertexColor(S.Color("raised"))
				slot.icon:Show()
				slot.ring:Show()
				if raid then
					local count = counts[i] or 0
					slot.role:Hide()
					slot.num:SetText(tostring(i))
					slot.ring:SetVertexColor(S.Color(count > 0 and "borderHover" or "border"))
					slot.name:SetText(count .. "/5")
					S.TextColor(slot.name, live and "muted" or "ink")
				else
					local spec = PARTY[i]
					local seat = fill.seats[i]
					slot.seat, slot.inGroup = seat, fill.inGroup
					slot.num:SetText("")
					slot.role:Show()
					slot.role:SetVertexColor(1, 1, 1, 1)
					if not Art.Set(slot.role, ROLE_ART[spec[1]]) then
						Art.Set(slot.role, ROLE_ART_DISC[spec[1]])
					end
					local taken = seat.member or seat.stored
					slot.ring:SetVertexColor(S.Color(taken and "borderHover" or "border"))
					-- An empty seat says so (muted), so the strip never shows a bare dash.
					local plate = ns.PartySeats.Paint(slot.name, seat)
					slot.icon:SetAlpha(plate)
					slot.role:SetAlpha(plate)
					local level = seat.member and seat.member.level
					slot.level:SetText(level and tostring(level) or "")
					slot.level:SetAlpha(plate)
				end
			else
				slot:Hide()
			end
		end
	end

	function f:Refresh()
		local plan = ctx:Plan()
		local bundled = plan and plan.bundled
		local readOnlyData = ns.DB.IsReadOnly()
		if not plan then
			self.state:SetText(L["No plan for this instance yet"])
		elseif bundled then
			-- Researched well before this game build: say so (the Notes section has the dates and the source).
			local stale = UI.StaleLine(plan) ~= nil
			self.state:SetText(stale and L["Recommended plan • may be out of date"] or L["Recommended plan • read-only"])
		elseif plan.origin then
			self.state:SetText(L["Your copy of a recommended plan"])
		else
			self.state:SetText(plan.author ~= "" and string.format(L["by %s"], plan.author) or L["Your plan"])
		end
		self.copy:SetShown(bundled and not readOnlyData or false)
		local anchor = self.copy:IsShown() and self.copy or self.state
		self.heading:ClearAllPoints()
		self.heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SP.md)
		self.heading:SetPoint("RIGHT", -SP.md, 0)
		self.list:ClearAllPoints()
		self.list:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", -SP.xs, -SP.xs)
		self.list:SetPoint("BOTTOMRIGHT", party, "TOPRIGHT", SP.md - SP.xs, SP.sm)
		local steps = plan and ctx:Steps() or {}
		self.heading:SetCount(#steps > 0 and #steps or nil)
		self.list:SetItems(steps)
		local current = ctx:StepIndex()
		if current then
			self.list:ScrollTo(current)
		end
		self.party:SetShown(plan ~= nil)
		self:RefreshParty(plan)
	end

	-- One highlight: the current step.
	local paint = f.list.Refresh
	function f.list:Refresh()
		paint(self)
		local current = ctx:StepIndex()
		for _, row in ipairs(self.rows) do
			row.dpSelected = row.index ~= nil and row.index == current
			row.paint(row)
		end
	end

	f:HookScript("OnSizeChanged", function(self)
		self:RefreshParty(ctx:Plan())
	end)
	-- The group changes while the strip is shown: redraw it (coalesced in Data/PartyInfo.lua); hidden, nothing.
	local function partyShown()
		return f:IsVisible() and party:IsShown()
	end
	ns.PartySeats.Watch(f, partyShown, function()
		f:RefreshParty(ctx:Plan())
	end)
	f:HookScript("OnShow", function(self)
		self:RefreshParty(ctx:Plan())
	end)
	return f
end
