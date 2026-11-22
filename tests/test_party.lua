-- The party strip filled from the group: the pure seating (Model/Party.lua: stored seats first, roles set, damage-only
-- classes, hybrids guessed from class, repeats, extras, raid counts), the game reads (Data/PartyInfo.lua) and the UI
-- (UI/PartySeats.lua, the side panel's strip, the Party section's card): labels follow roster events, coalesced, and
-- nothing redraws while hidden.
local T = ...
local ns, mock = T.ns, T.mock
local Party = ns.Party

local DPS = { DAMAGER = true }
local WARRIOR = { TANK = true, DAMAGER = true }
local PRIEST = { HEALER = true, DAMAGER = true }
local DRUID = { TANK = true, HEALER = true, DAMAGER = true }

local function who(fill)
	local out = {}
	for i, seat in ipairs(fill.seats) do
		out[i] = (seat.member and seat.member.id or seat.stored or "-") .. ":" .. tostring(seat.how)
	end
	return table.concat(out, " ")
end

T.case("Party.Fill: roles set take their seats, in group order", function()
	local fill = Party.Fill({}, {
		{ id = "Me", role = "DAMAGER" },
		{ id = "Heal", role = "HEALER" },
		{ id = "Tank", role = "TANK" },
		{ id = "D2", role = "DAMAGER" },
		{ id = "D3", role = "DAMAGER" },
	})
	T.eq(who(fill), "Tank:role Heal:role Me:role D2:role D3:role")
	T.eq(#fill.extra, 0)
end)

T.case("Party.Fill: no roles set: damage-only classes to damage, hybrids guessed into the seats they can fill", function()
	local fill = Party.Fill({}, {
		{ id = "Mage", roles = DPS },
		{ id = "Druid", roles = DRUID },
		{ id = "Warrior", roles = WARRIOR },
		{ id = "Priest", roles = PRIEST },
		{ id = "Unknown" },
	})
	-- The warrior and the priest each fit one empty seat, so they go first; the druid then deals damage.
	T.eq(who(fill), "Warrior:guess Priest:guess Mage:class Druid:guess Unknown:guess")
	-- A hybrid whose tank and healer seats are taken deals damage, still a guess.
	fill = Party.Fill({}, {
		{ id = "Tank", role = "TANK" },
		{ id = "Heal", role = "HEALER" },
		{ id = "Pal", roles = DRUID },
	})
	T.eq(who(fill), "Tank:role Heal:role Pal:guess -:nil -:nil")
	T.eq(fill.seats[3].role, "DAMAGER")
	-- A damage-only class never takes the tank seat by guess; it fills it only when nothing else is free.
	fill = Party.Fill({}, { { id = "Rogue", roles = DPS } })
	T.eq(who(fill), "-:nil -:nil Rogue:class -:nil -:nil")
end)

T.case("Party.Fill: repeats count once, and members past five are extras; a second tank sits off role", function()
	local fill = Party.Fill({}, {
		{ id = "Me", role = "TANK" },
		{ id = "Me", role = "HEALER" },
		{ id = "Tank2", role = "TANK" },
		{ id = "Heal", role = "HEALER" },
		{ id = "D1", role = "DAMAGER" },
		{ id = "D2", role = "DAMAGER" },
		{ id = "D3", role = "DAMAGER" },
		{ id = "D4", role = "DAMAGER" },
	})
	T.eq(who(fill), "Me:role Heal:role D1:role D2:role D3:role")
	T.eq(#fill.extra, 2, "the second tank and the fourth damage dealer")
	T.eq(fill.extra[1].id, "Tank2")
	-- With a free seat, the second tank sits in it, marked.
	fill = Party.Fill({}, { { id = "T1", role = "TANK" }, { id = "T2", role = "TANK" } })
	T.eq(who(fill), "T1:role -:nil T2:offrole -:nil -:nil")
	-- Bounded: forty members at most are read.
	local many = {}
	for i = 1, 60 do
		many[i] = { id = "M" .. i }
	end
	fill = Party.Fill({}, many)
	T.eq(#fill.extra, Party.MAX_MEMBERS - 5)
end)

T.case("Party.Fill: solo, the player sits alone; the rest are open", function()
	local fill = Party.Fill({ {}, {}, {} }, { { id = "Me", roles = WARRIOR, player = true } })
	T.eq(who(fill), "Me:guess -:nil -:nil -:nil -:nil")
end)

T.case("Party.Fill: stored seats win; a member matches by the whole name (surnames), never a first name", function()
	local groups = { { "Ana Smith" }, {}, { "Ana", "Bram" } }
	local fill = Party.Fill(groups, {
		{ id = "Tess Tester", role = "HEALER", player = true },
		{ id = "Ana Jones", role = "TANK" },
		{ id = "Ana Smith", role = "DAMAGER" },
	})
	-- Ana Smith keeps the tank seat the plan gives her though she queued as damage; Ana Jones is not "Ana" and the
	-- tank seat is stored, so she sits off role in the last free seat.
	T.eq(who(fill), "Ana Smith:stored Tess Tester:role Ana:stored Bram:stored Ana Jones:offrole")
	T.ok(fill.seats[1].member ~= nil, "matched to the live member")
	T.eq(fill.seats[3].member, nil, "a first name matches nobody")
	-- idOf normalises a stored name (Roster.Id: our realm left off).
	fill = Party.Fill({ { "Lead-HomeRealm" } }, { { id = "Lead", role = "DAMAGER" } }, function(name)
		return (name:gsub("%-HomeRealm$", ""))
	end)
	T.eq(who(fill), "Lead:stored -:nil -:nil -:nil -:nil")
	-- A name stored twice seats its member once.
	fill = Party.Fill({ { "Bram" }, { "Bram" } }, { { id = "Bram" } })
	T.ok(fill.seats[1].member and not fill.seats[2].member)
end)

T.case("Party.Fill: missing and secret values are left out, never compared", function()
	local fill = Party.Fill(nil, {
		"junk",
		{ id = nil, role = "TANK" },
		{ id = "", role = "TANK" },
		{ id = mock.SECRET and ns.Util.Plain(mock.SECRET) or nil },
		{ id = "Ok", role = ns.Util.Plain(mock.SECRET), roles = "junk" },
	})
	T.eq(who(fill), "-:nil -:nil Ok:guess -:nil -:nil")
	fill = Party.Fill({ "junk", { 42 } }, nil)
	T.eq(who(fill), "-:nil -:nil -:nil -:nil -:nil")
end)

T.case("Party.RaidCounts: the plan's groups when it sets any, else the raid's", function()
	local counts, live = Party.RaidCounts({ {}, {} }, { { subgroup = 1 }, { subgroup = 1 }, { subgroup = 2 }, { subgroup = 9 } }, 8)
	T.ok(live)
	T.eq(counts[1], 2)
	T.eq(counts[2], 1)
	T.eq(counts[8], 0)
	counts, live = Party.RaidCounts({ { "A" }, {} }, { { subgroup = 2 } }, 8)
	T.ok(not live)
	T.eq(counts[1], 1)
	T.eq(counts[2], 0)
	counts, live = Party.RaidCounts({}, {}, 8)
	T.ok(not live)
	T.eq(counts[1], 0, "no raid, no groups: all empty")
end)

-- The UI against the mock: a party of WoW: Forever characters (first name and surname from UnitName).
local saved = {}
local GLOBALS = { "UnitName", "UnitClass", "UnitGroupRolesAssigned", "UnitIsConnected", "GetNumSpecializationsForClassID",
	"GetSpecializationInfoForClassID", "RAID_CLASS_COLORS" }
local CLASS_IDS = { WARRIOR = 1, PRIEST = 5, MAGE = 8 }
local SPECS = { [1] = { "TANK", "DAMAGER" }, [5] = { "HEALER", "DAMAGER" }, [8] = { "DAMAGER" } }

local function world(units)
	for _, n in ipairs(GLOBALS) do
		if saved[n] == nil then
			saved[n] = rawget(_G, n) or false
		end
	end
	mock.inGroup = units ~= nil
	mock.units = units or {}
	_G.UnitName = function(unit)
		if unit == "player" then
			return "Tess", "Tester"
		end
		local u = mock.units[unit]
		return u and u.name, u and u.surname
	end
	_G.UnitClass = function(unit)
		local u = unit == "player" and { cls = "MAGE" } or mock.units[unit]
		local cls = u and u.cls
		return cls, cls, cls and CLASS_IDS[cls]
	end
	_G.UnitGroupRolesAssigned = function(unit)
		local u = mock.units[unit]
		return u and u.role or "NONE"
	end
	_G.UnitIsConnected = function(unit)
		local u = mock.units[unit]
		return not (u and u.offline)
	end
	_G.GetNumSpecializationsForClassID = function(id)
		return SPECS[id] and #SPECS[id] or 0
	end
	_G.GetSpecializationInfoForClassID = function(id, i)
		return id * 10 + i, "Spec", "", 0, SPECS[id][i]
	end
	_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		PRIEST = { r = 1, g = 1, b = 1 } }
end

local function restore()
	for n, v in pairs(saved) do
		_G[n] = v or nil
	end
	saved = {}
	mock.inGroup, mock.units = false, {}
end

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	return _G.DungeonPlannerMainFrame.instancePage.side
end

local function names(side)
	local out = {}
	for i = 1, 5 do
		out[i] = side.party.slots[i].name:GetText()
	end
	return table.concat(out, ",")
end

T.case("Party strip UI: the group fills the recommended plan's open seats; roster events redraw it, coalesced", function()
	world({ party1 = { name = "Aldra", surname = "Vey", cls = "WARRIOR", role = "TANK", level = 19 } })
	local ok, err = pcall(function()
		local side = boot()
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(names(side), "Aldra,Open,Tess,Open,Open", "the tank and the player (a mage: damage)")
		local tank = side.party.slots[1]
		T.eq(tank.level:GetText(), "19")
		local r, g = tank.name:GetTextColor()
		T.ok(math.abs(r - 0.78) < 0.01 and math.abs(g - 0.61) < 0.01, "class colour")
		T.eq(tank.seat.member.id, "Aldra Vey", "the whole name for the tooltip")
		T.ok(ns.PartySeats.Tooltip(tank, tank.seat, true), "a tooltip")
		-- A healer joins: nothing until the short timer, then one redraw for the burst.
		local draws, real = 0, side.RefreshParty
		side.RefreshParty = function(...)
			draws = draws + 1
			return real(...)
		end
		mock.units.party2 = { name = "Corin", surname = "Ash", cls = "PRIEST" }
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		mock.FireEvent("UNIT_NAME_UPDATE", "party2")
		mock.FireEvent("UNIT_LEVEL", "party2")
		T.eq(draws, 0, "waits for the timer")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 1, "one redraw for the burst")
		T.eq(names(side), "Aldra,Corin,Tess,Open,Open", "the priest without a role: guessed healer")
		T.eq(side.party.slots[2].seat.how, "guess")
		T.ok(side.party.slots[2].name:GetAlpha() < 1, "a guess is dimmer")
		-- Events about other units (nameplates, the target) are ignored.
		mock.FireEvent("UNIT_LEVEL", "nameplate3")
		mock.FireEvent("UNIT_FLAGS", "target")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 1)
		-- Offline: dimmed plate and label.
		mock.units.party1.offline = true
		mock.FireEvent("UNIT_CONNECTION", "party1", false)
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 2)
		T.ok(side.party.slots[1].icon:GetAlpha() < 1 and side.party.slots[1].name:GetAlpha() < 1, "offline: dimmed")
		-- Hidden: the events change nothing and no timer runs; showing the window again draws the new group.
		side:Hide()
		mock.units.party1.role = "DAMAGER"
		mock.units.party1.offline = nil
		mock.FireEvent("PLAYER_ROLES_ASSIGNED")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 2, "no redraw while hidden")
		T.eq(names(side), "Aldra,Corin,Tess,Open,Open", "unchanged while hidden")
		side:Show()
		T.eq(draws, 3, "drawn once when shown")
		T.eq(names(side), "Open,Corin,Aldra,Tess,Open", "redrawn when shown")
		side.RefreshParty = real
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Party strip UI: six members on a dungeon plan show +1 with a tooltip; a long name is cut with a tooltip", function()
	world({
		party1 = { name = "Aldra", cls = "WARRIOR", role = "TANK" },
		party2 = { name = "Corin", cls = "PRIEST", role = "HEALER" },
		party3 = { name = "Bartholomewandriusvonhohenstein", surname = "Longfellow", cls = "MAGE" },
		party4 = { name = "Dessa", cls = "MAGE", role = "DAMAGER" },
		raid6 = { name = "Ivo", cls = "MAGE" },
	})
	local realRaid, realUnits = _G.IsInRaid, ns.Roster.Units
	-- Six members: the roster's units are read as a raid's.
	ns.Roster.Units = function()
		return { "player", "party1", "party2", "party3", "party4", "raid6" }
	end
	local ok, err = pcall(function()
		local side = boot()
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(side.party.heading.count:GetText(), "+1")
		T.ok(side.party.dpTooltipText:find("Ivo", 1, true), "the extra is named in the strip's tooltip")
		T.eq(side.party.slots[5].seat.member.id, "Bartholomewandriusvonhohenstein Longfellow")
		-- One long word in a seat 42 px wide (six units a letter here): cut by its letters, the whole name kept for the
		-- tooltip; names of several words are cut after a whole word.
		local fs = UIParent:CreateFontString()
		fs:SetWidth(42)
		fs.IsTruncated = function(self)
			return #(self:GetText() or "") * 6 > 42
		end
		T.eq(ns.PartySeats.FitName(fs, "Bartholomewandrius"), "Bart...")
		T.eq(fs.dpFullText, "Bartholomewandrius")
		T.eq(ns.PartySeats.FitName(fs, "Ana Smith"), "Ana...")
		T.eq(ns.PartySeats.FitName(fs, "Ana"), "Ana")
		T.eq(fs.dpFullText, nil)
	end)
	ns.Roster.Units, _G.IsInRaid = realUnits, realRaid
	restore()
	T.ok(ok, err)
end)

T.case("Party section: the card shows the group too; Fill from my party stores whole names by seat", function()
	world({
		party1 = { name = "Aldra", surname = "Vey", cls = "WARRIOR" },
		party2 = { name = "Corin", surname = "Ash", cls = "PRIEST", role = "HEALER" },
	})
	local ok, err = pcall(function()
		boot()
		local own = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		ns.UI.SelectPlan(own.id)
		ns.UI.SelectTab("assignments")
		ns.UI.RefreshPage()
		local groups = _G.DungeonPlannerMainFrame.instancePage.panels.assignments.inner.groups
		T.eq(groups.card.seats[1].text:GetText(), "Aldra", "the warrior guessed into the open tank seat")
		T.eq(groups.card.seats[1].seat.how, "guess")
		T.eq(groups.card.seats[2].role:GetText(), ns.L["Healer"], "no level known: the role alone")
		groups:Fill()
		T.eq(own.groups[1][1], "Aldra Vey", "the whole name")
		T.eq(own.groups[2][1], "Corin Ash")
		T.eq(own.groups[3][1], "Tess Tester")
		ns.UI.RefreshPage()
		T.eq(groups.card.seats[1].seat.how, "stored")
		T.ok(groups.card.seats[1].seat.member, "the stored name matches the member again")
		ns.DB.DeletePlan(own.id)
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Raid strip UI: a raid plan that sets no groups shows the raid's groups as they stand, muted", function()
	world({ raid1 = { name = "Aldra" }, raid2 = { name = "Corin" }, raid3 = { name = "Dessa" } })
	local realRaid, realInfo = _G.IsInRaid, _G.GetRaidRosterInfo
	_G.IsInRaid = function()
		return true
	end
	local sub = { 1, 1, 3 }
	_G.GetRaidRosterInfo = function(i)
		local u = mock.units["raid" .. i]
		return u and u.name, 0, sub[i]
	end
	local ok, err = pcall(function()
		local side = boot()
		ns.UI.SelectPlan("b:molten-core")
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(side.party.slots[1].name:GetText(), "2/5")
		T.eq(side.party.slots[3].name:GetText(), "1/5")
		T.eq(side.party.slots[2].name:GetText(), "0/5")
		T.eq(side.party.slots[1].name.dpColorRole, "muted", "the raid's, not the plan's")
		T.ok(side.party.dpTooltipText:find(ns.L["Groups as your raid stands now: the plan sets none."], 1, true))
	end)
	_G.IsInRaid, _G.GetRaidRosterInfo = realRaid, realInfo
	restore()
	T.ok(ok, err)
end)
