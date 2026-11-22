-- The party's seats as the side panel's strip and the Party section's card draw them: the plan's stored names, the
-- group filled in where the plan has none (Model/Party.lua over Data/PartyInfo.lua), each seat's label (the short
-- name in class colour; dimmed when offline, dead or guessed) and its tooltip (the whole identity, class, level and
-- how the seat was chosen). Both views redraw on PARTY_CHANGED while shown (PartySeats.Watch).

local _, ns = ...
local PartySeats = ns:NewModule("PartySeats")
local S, W, L = ns.Style, ns.Widgets, ns.L

local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
PartySeats.ROLE_TEXT = ROLE_TEXT
PartySeats.DIM = 0.45 -- offline or dead
PartySeats.GUESS = 0.65 -- placed from the class, not a role the player set

-- The seats of a dungeon plan with the group as it is now: { seats, extra, inGroup }. The roster is read once per
-- group event (PartyInfo.Cached), not on every redraw.
function PartySeats.Fill(plan)
	local fill = ns.Party.Fill(plan and plan.groups, ns.PartyInfo.Cached(), ns.Roster.Id)
	fill.inGroup = ns.PartyInfo.InGroup()
	if not fill.inGroup then
		fill.extra = {} -- solo: a plan that seats others has no one extra to name
	end
	return fill
end

-- The raid strip's counts: the plan's groups, else the raid's (GetRaidRosterInfo only).
function PartySeats.RaidCounts(plan, n)
	return ns.Party.RaidCounts(plan and plan.groups, ns.PartyInfo.RaidGroups(), n)
end

-- How a name the plan stores reads: the member's short name when it stands for one in the group (Party.Match),
-- else the name as stored.
function PartySeats.Short(name, members)
	local m = ns.Party.Match(name, members or ns.PartyInfo.Cached(), ns.Roster.Id)
	return m and m.name or name
end

-- A name on one line: cut after a whole word (W.FitText), and a single long word by its letters, with "..." and the
-- whole name in fs.dpFullText.
function PartySeats.FitName(fs, text)
	local shown, cut = W.FitText(fs, text)
	if cut or not W.TextOverflows(fs, fs:GetWidth() or 0) then
		return shown
	end
	local chars = {}
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		chars[#chars + 1] = ch
	end
	for n = #chars - 1, 1, -1 do
		local short = table.concat(chars, "", 1, n) .. "..."
		fs:SetText(short)
		if not W.TextOverflows(fs, fs:GetWidth() or 0) then
			fs.dpFullText = text
			return short
		end
	end
	return shown
end

local function label(seat)
	local m = seat.member
	if m then
		return m.name or m.id
	end
	return seat.stored and ns.Util.ShortName(seat.stored) or nil
end

-- Paint a seat's label: the name in class colour, or the stored name, or a muted "Open". Returns the alpha for the
-- seat's plate (dimmed while the member is offline or dead).
function PartySeats.Paint(fs, seat)
	local name = label(seat)
	PartySeats.FitName(fs, name or L["party:open"])
	S.TextColor(fs, name and "ink" or "muted")
	local m = seat.member
	local r, g, b
	if m then
		r, g, b = ns.PartyInfo.ClassColor(m.class)
	end
	if r then
		fs:SetTextColor(r, g, b)
	end
	local away = m and (m.offline or m.dead)
	local guessed = seat.how == "guess" or seat.how == "offrole" or seat.how == "free"
	fs:SetAlpha(away and PartySeats.DIM or guessed and PartySeats.GUESS or 1)
	return away and PartySeats.DIM or 1
end

-- What a member's line says about them: class, level, online and alive.
local function facts(m)
	local parts = {}
	if m.level then
		parts[#parts + 1] = string.format(L["Level %d"], m.level)
	end
	if m.className then
		parts[#parts + 1] = m.className
	end
	return table.concat(parts, " • ")
end

-- The seat's tooltip, beside `owner`. Nothing for an open seat.
function PartySeats.Tooltip(owner, seat, inGroup)
	local m = seat.member
	if not (m or seat.stored) then
		return false
	end
	local tt = W.Tip()
	if not tt then
		return false
	end
	W.TipBeside(tt, owner)
	local r, g, b = 1, 0.82, 0
	if m and ns.PartyInfo.ClassColor(m.class) then
		r, g, b = ns.PartyInfo.ClassColor(m.class)
	end
	tt:SetText(m and m.id or seat.stored, r, g, b, 1, true)
	local role = L[ROLE_TEXT[seat.role]]
	tt:AddLine(role, 1, 0.82, 0, true)
	if m then
		local line = facts(m)
		if line ~= "" then
			tt:AddLine(line, 1, 1, 1, true)
		end
		if m.offline then
			tt:AddLine(L["Offline"], 0.71, 0.67, 0.59, true)
		elseif m.dead then
			tt:AddLine(L["Dead"], 0.71, 0.67, 0.59, true)
		end
	end
	local how = seat.how
	if how == "stored" then
		tt:AddLine(L["Seat set in the plan."], 0.71, 0.67, 0.59, true)
		-- Only a name nobody in the group answers to is "not in your group".
		if seat.present == "twice" then
			tt:AddLine(L["The plan names this player in another seat too."], 0.71, 0.67, 0.59, true)
		elseif seat.present == "ambiguous" then
			tt:AddLine(L["More than one member of your group has this first name."], 0.71, 0.67, 0.59, true)
		elseif not m and inGroup then
			tt:AddLine(L["Not in your group."], 0.71, 0.67, 0.59, true)
		end
	elseif how == "role" then
		tt:AddLine(L["From your group: the role they chose."], 0.71, 0.67, 0.59, true)
	elseif how == "class" then
		tt:AddLine(L["Role not set: this class only deals damage."], 0.71, 0.67, 0.59, true)
	elseif how == "guess" then
		tt:AddLine(L["Role not set: guessed from class."], 1, 0.6, 0.2, true)
	elseif how == "free" then
		tt:AddLine(L["Role not set: placed in a free seat."], 1, 0.6, 0.2, true)
	elseif how == "offrole" then
		tt:AddLine(string.format(L["Chose %s, but that seat is taken."], L[ROLE_TEXT[m.role]] or m.role), 1, 0.6, 0.2, true)
	end
	W.TipShow(tt)
	return true
end

-- OnLeave for a seat: hide the tooltip it owns.
function PartySeats.HideTip(owner)
	local tt = W.Tip()
	if tt and tt:IsOwned(owner) then
		tt:Hide()
	end
end

-- The members who found no seat, for a tooltip: "Name (Tank)".
function PartySeats.ExtraLines(extra)
	local lines = {}
	for _, m in ipairs(extra or {}) do
		local role = m.role and L[ROLE_TEXT[m.role]]
		lines[#lines + 1] = role and string.format("%s (%s)", m.id, role) or m.id
	end
	return lines
end

-- Redraw `owner` with `redraw` on PARTY_CHANGED while `shows()` says it is on screen.
function PartySeats.Watch(owner, shows, redraw)
	ns.PartyInfo.Watch(owner, shows)
	ns:On("PARTY_CHANGED", owner, function()
		if shows() then
			redraw()
		end
	end)
end
