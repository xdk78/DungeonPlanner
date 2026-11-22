-- The party strip filled from the group: the pure seating (Model/Party.lua: stored seats first, matched by the whole
-- name or a unique first name, roles set, damage-only classes, hybrids guessed from class, free seats, repeats,
-- extras, raid counts), the game reads (Data/PartyInfo.lua) and the UI (UI/PartySeats.lua, the side panel's strip, the
-- Party section's card): labels follow roster events, coalesced, and nothing redraws while hidden. Also one identity
-- across the plan: Fill from my party / raid, the assignment targets and the Notes window store and match whole names.
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
	-- The warrior and the priest each fit one empty seat, so they go first; the druid then deals damage. A class the
	-- client could not tell is placed, not guessed.
	T.eq(who(fill), "Warrior:guess Priest:guess Mage:class Druid:guess Unknown:free")
	-- A hybrid whose tank and healer seats are taken deals damage, still a guess.
	fill = Party.Fill({}, {
		{ id = "Tank", role = "TANK" },
		{ id = "Heal", role = "HEALER" },
		{ id = "Pal", roles = DRUID },
	})
	T.eq(who(fill), "Tank:role Heal:role Pal:guess -:nil -:nil")
	T.eq(fill.seats[3].role, "DAMAGER")
	fill = Party.Fill({}, { { id = "Rogue", roles = DPS } })
	T.eq(who(fill), "-:nil -:nil Rogue:class -:nil -:nil")
	-- Four mages: three deal damage; the fourth sits in the free tank seat, which nothing says it can fill.
	fill = Party.Fill({}, { { id = "M1", roles = DPS }, { id = "M2", roles = DPS }, { id = "M3", roles = DPS },
		{ id = "M4", roles = DPS } })
	T.eq(who(fill), "M4:free -:nil M1:class M2:class M3:class")
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
	-- With a free seat, the second tank sits in a damage seat, marked.
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

T.case("Party.Fill: stored seats win, matched by the whole name or a first name only one member has", function()
	local groups = { { "Ana Smith" }, {}, { "Ana", "Bram" } }
	local fill = Party.Fill(groups, {
		{ id = "Tess Tester", first = "Tess", role = "HEALER", player = true },
		{ id = "Ana Jones", first = "Ana", role = "TANK" },
		{ id = "Ana Smith", first = "Ana", role = "DAMAGER" },
	})
	-- Ana Smith keeps the tank seat the plan gives her though she queued as damage. "Ana" could be either Ana: it
	-- matches neither, and says so rather than "not in your group". Ana Jones sits off role in the last free seat.
	T.eq(who(fill), "Ana Smith:stored Tess Tester:role Ana:stored Bram:stored Ana Jones:offrole")
	T.ok(fill.seats[1].member ~= nil, "matched to the live member")
	T.eq(fill.seats[3].member, nil, "a shared first name matches nobody")
	T.eq(fill.seats[3].present, "ambiguous")
	T.eq(fill.seats[4].present, nil, "Bram is not in the group")
	-- A plan that stored first names (before plans kept surnames) matches a lone member with that first name.
	fill = Party.Fill({ { "Aldra" }, { "Corin" } }, {
		{ id = "Tess Tester", first = "Tess", player = true, roles = DPS },
		{ id = "Aldra Vey", first = "Aldra", roles = WARRIOR },
		{ id = "Corin Ash", first = "Corin", roles = PRIEST },
	})
	T.eq(who(fill), "Aldra Vey:stored Corin Ash:stored Tess Tester:class -:nil -:nil")
	T.eq(fill.seats[1].stored, "Aldra")
	T.eq(fill.seats[1].member.id, "Aldra Vey")
	T.eq(#fill.extra, 0, "nobody twice")
	-- Without a surname (realms elsewhere) there is no first-name match.
	T.eq((Party.Match("Bob", { { id = "Bob-OtherRealm" } })), nil)
	-- idOf normalises a stored name (Roster.Id: our realm left off).
	fill = Party.Fill({ { "Lead-HomeRealm" } }, { { id = "Lead", role = "DAMAGER" } }, function(name)
		return (name:gsub("%-HomeRealm$", ""))
	end)
	T.eq(who(fill), "Lead:stored -:nil -:nil -:nil -:nil")
	-- A name stored twice seats its member once; the second seat knows the member is here.
	fill = Party.Fill({ { "Bram" }, { "Bram" } }, { { id = "Bram" } })
	T.ok(fill.seats[1].member and not fill.seats[2].member)
	T.eq(fill.seats[2].present, "twice")
end)

T.case("Party.Fill: missing and secret values are left out, never compared", function()
	local fill = Party.Fill(nil, {
		"junk",
		{ id = nil, role = "TANK" },
		{ id = "", role = "TANK" },
		{ id = ns.Util.Plain(mock.SECRET) },
		{ id = "Ok", role = ns.Util.Plain(mock.SECRET), roles = "junk" },
	})
	T.eq(who(fill), "-:nil -:nil Ok:free -:nil -:nil")
	fill = Party.Fill({ "junk", { 42 } }, nil)
	T.eq(who(fill), "-:nil -:nil -:nil -:nil -:nil")
	T.eq((Party.Match(nil, {})), nil)
end)

T.case("Party.RaidCounts: the plan's groups when it sets any, else the raid's", function()
	local counts, live = Party.RaidCounts({ {}, {} }, { [1] = 2, [2] = 1, [9] = 1 }, 8)
	T.ok(live)
	T.eq(counts[1], 2)
	T.eq(counts[2], 1)
	T.eq(counts[8], 0)
	counts, live = Party.RaidCounts({ { "A" }, {} }, { [2] = 1 }, 8)
	T.ok(not live)
	T.eq(counts[1], 1)
	T.eq(counts[2], 0)
	counts, live = Party.RaidCounts({}, nil, 8)
	T.ok(not live)
	T.eq(counts[1], 0, "no raid, no groups: all empty")
end)

-- The UI against the mock: a party of WoW: Forever characters (first name and surname from UnitName).
local saved = {}
local GLOBALS = { "UnitName", "UnitClass", "UnitGroupRolesAssigned", "UnitIsConnected", "UnitIsUnit", "IsInRaid",
	"GetRaidRosterInfo", "GetNumGroupMembers", "GetNumSpecializationsForClassID", "GetSpecializationInfoForClassID",
	"RAID_CLASS_COLORS" }
local CLASS_IDS = { WARRIOR = 1, PRIEST = 5, MAGE = 8 }
local SPECS = { [1] = { "TANK", "DAMAGER" }, [5] = { "HEALER", "DAMAGER" }, [8] = { "DAMAGER" } }

-- units: mock units (party1.. or raid1..; in a raid, raid1 is the player); raid: { [index] = subgroup } for a raid.
local function world(units, raid)
	for _, n in ipairs(GLOBALS) do
		if saved[n] == nil then
			saved[n] = rawget(_G, n) or false
		end
	end
	mock.inGroup = units ~= nil
	mock.units = units or {}
	local function unitOf(unit)
		if unit == "player" then
			return raid and mock.units.raid1 or { name = "Tess", surname = "Tester", cls = "MAGE" }
		end
		return mock.units[unit]
	end
	_G.UnitName = function(unit)
		local u = unitOf(unit)
		return u and u.name, u and u.surname
	end
	_G.UnitClass = function(unit)
		local u = unitOf(unit)
		local cls = u and u.cls
		if cls == mock.SECRET then
			return cls, cls, cls
		end
		return cls, cls, cls and CLASS_IDS[cls]
	end
	_G.UnitGroupRolesAssigned = function(unit)
		local u = unitOf(unit)
		return u and u.role or "NONE"
	end
	_G.UnitIsConnected = function(unit)
		local u = unitOf(unit)
		return not (u and u.offline)
	end
	_G.UnitIsUnit = function(a, b)
		return a == b or (raid ~= nil and b == "player" and a == "raid1")
	end
	_G.IsInRaid = function()
		return raid ~= nil
	end
	_G.GetNumGroupMembers = function()
		local n = 0
		for _ in pairs(mock.units) do
			n = n + 1
		end
		return units and (raid and n or n + 1) or 0
	end
	_G.GetRaidRosterInfo = function(i)
		local u = raid and mock.units["raid" .. i]
		return u and u.name, 0, u and raid[i]
	end
	_G.GetNumSpecializationsForClassID = function(id)
		return SPECS[id] and #SPECS[id] or 0
	end
	_G.GetSpecializationInfoForClassID = function(id, i)
		return id * 10 + i, "Spec", "", 0, SPECS[id][i]
	end
	_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		PRIEST = { r = 1, g = 1, b = 1 } }
	mock.FireEvent("GROUP_ROSTER_UPDATE") -- the roster changed: the strip's cached read is dropped
end

local function restore()
	for n, v in pairs(saved) do
		_G[n] = v or nil
	end
	saved = {}
	local tt = ns.Widgets.Tip()
	tt.SetOwner, tt.IsOwned, tt.SetText, tt.AddLine = nil, nil, nil, nil -- the mock's own methods again
	mock.inGroup, mock.units = false, {}
	mock.FireEvent("GROUP_ROSTER_UPDATE")
	mock.Advance(ns.PartyInfo.DELAY + 0.1)
end

-- The mock's tooltip keeps no lines or owner: record them on the tooltip for these tests.
local tipText, tipOwner = {}, nil
local function recordTips()
	local tt = ns.Widgets.Tip()
	tt.SetOwner = function(_, owner)
		tipOwner, tipText = owner, {}
	end
	tt.IsOwned = function(_, owner)
		return owner == tipOwner
	end
	tt.SetText = function(_, line)
		tipText = { line }
	end
	tt.AddLine = function(_, line)
		tipText[#tipText + 1] = line
	end
end
local function tipLines()
	return table.concat(tipText, "\n")
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
	recordTips()
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
		mock.Hover(tank)
		T.ok(tipLines():find("Aldra Vey", 1, true), "the tooltip names the whole name")
		-- An open seat shows the strip's own tooltip.
		local open = side.party.slots[2]
		mock.Hover(open)
		T.ok(ns.Widgets.Tip():IsOwned(open), "an open seat has a tooltip")
		T.ok(tipLines():find(ns.L["Who plays which role. Click to edit the party and the assignments."], 1, true))
		mock.Leave(open)
		-- Resizes and redraws do not read the roster again until a group event.
		local reads, realMembers = 0, ns.PartyInfo.Members
		ns.PartyInfo.Members = function(...)
			reads = reads + 1
			return realMembers(...)
		end
		side:RefreshParty(ns.UI.ctx:Plan())
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(reads, 0, "cached until the roster changes")
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
		T.eq(reads, 1, "one read for it")
		ns.PartyInfo.Members = realMembers
		T.eq(names(side), "Aldra,Corin,Tess,Open,Open", "the priest without a role: guessed healer")
		T.eq(side.party.slots[2].seat.how, "guess")
		T.ok(side.party.slots[2].name:GetAlpha() < 1, "a guess is dimmer")
		-- Events about other units (nameplates, the target) are ignored.
		mock.FireEvent("UNIT_LEVEL", "nameplate3")
		mock.FireEvent("UNIT_FLAGS", "target")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 1)
		-- Offline: dimmed plate and label. The player's death redraws too.
		mock.units.party1.offline = true
		mock.FireEvent("UNIT_CONNECTION", "party1", false)
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 2)
		T.ok(side.party.slots[1].icon:GetAlpha() < 1 and side.party.slots[1].name:GetAlpha() < 1, "offline: dimmed")
		mock.FireEvent("PLAYER_DEAD")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 3, "the player's death")
		-- Hidden: the events change nothing and no timer runs; showing it again draws the new group.
		side:Hide()
		mock.units.party1.role = "DAMAGER"
		mock.units.party1.offline = nil
		mock.FireEvent("PLAYER_ROLES_ASSIGNED")
		mock.Advance(ns.PartyInfo.DELAY + 0.1)
		T.eq(draws, 3, "no redraw while hidden")
		T.eq(names(side), "Aldra,Corin,Tess,Open,Open", "unchanged while hidden")
		side:Show()
		T.eq(draws, 4, "drawn once when shown")
		T.eq(names(side), "Open,Corin,Aldra,Tess,Open", "redrawn when shown")
		side.RefreshParty = real
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Party strip UI: secret answers for one member: left out or shown plainly; the others draw", function()
	world({
		party1 = { name = "Aldra", surname = "Vey", cls = "WARRIOR", role = "TANK", level = 19 },
		party2 = { name = "Corin", surname = "Ash", cls = mock.SECRET, role = mock.SECRET, level = mock.SECRET },
		party3 = { name = mock.SECRET, cls = "MAGE", role = "DAMAGER" },
	})
	local ok, err = pcall(function()
		local members = ns.PartyInfo.Members()
		T.eq(#members, 3, "the player, Aldra and Corin; a secret name has no identity")
		local corin = members[3]
		T.eq(corin.id, "Corin Ash")
		T.ok(corin.class == nil and corin.role == nil and corin.level == nil and corin.roles == nil, "plain: no class")
		local side = boot()
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(names(side), "Aldra,Open,Tess,Corin,Open")
		T.eq(side.party.slots[4].seat.how, "free", "no role and no class: a free seat")
		local r, g, b = side.party.slots[4].name:GetTextColor()
		local ir, ig, ib = ns.Style.Color("ink")
		T.ok(r == ir and g == ig and b == ib, "no class colour")
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Party strip UI: a plan with first names matches a Forever group; no duplicate seats or extras", function()
	world({
		party1 = { name = "Aldra", surname = "Vey", cls = "WARRIOR", role = "TANK" },
		party2 = { name = "Corin", surname = "Ash", cls = "PRIEST", role = "HEALER" },
	})
	local ok, err = pcall(function()
		local side = boot()
		local own = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		own.groups[1], own.groups[2], own.groups[3] = { "Aldra" }, { "Corin" }, { "Tess", "Bram" }
		ns.UI.SelectPlan(own.id)
		side:RefreshParty(own)
		T.eq(names(side), "Aldra,Corin,Tess,Bram,Open")
		T.ok(side.party.slots[1].seat.member and side.party.slots[3].seat.member, "matched by first name")
		T.eq(side.party.heading.count:GetText(), "", "nobody extra")
		local slot = side.party.slots[1]
		mock.Hover(slot)
		T.ok(not tipLines():find(ns.L["Not in your group."], 1, true), "Aldra is here")
		slot = side.party.slots[4]
		mock.Hover(slot)
		T.ok(tipLines():find(ns.L["Not in your group."], 1, true), "Bram is not")
		ns.DB.DeletePlan(own.id)
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Party strip UI: six in a raid on a dungeon plan show +1; Fill takes the player's own raid group", function()
	world({
		raid1 = { name = "Tess", surname = "Tester", cls = "MAGE" },
		raid2 = { name = "Aldra", cls = "WARRIOR", role = "TANK" },
		raid3 = { name = "Corin", cls = "PRIEST", role = "HEALER" },
		raid4 = { name = "Bartholomewandriusvonhohenstein", surname = "Longfellow", cls = "MAGE" },
		raid5 = { name = "Dessa", cls = "MAGE", role = "DAMAGER" },
		raid6 = { name = "Ivo", cls = "MAGE" },
	}, { 1, 1, 1, 1, 1, 2 })
	local ok, err = pcall(function()
		local side = boot()
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(side.party.heading.count:GetText(), "+1")
		T.ok(side.party.tipText:find("Ivo", 1, true), "the extra is named in the strip's tooltip")
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
		-- Fill from my party in a raid: the player's own group (1), not Ivo in group 2.
		local own = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		ns.UI.SelectPlan(own.id)
		ns.UI.SelectTab("assignments")
		ns.UI.RefreshPage()
		_G.DungeonPlannerMainFrame.instancePage.panels.assignments.inner.groups:Fill()
		local stored = {}
		for gi = 1, 3 do
			for _, name in ipairs(own.groups[gi]) do
				stored[#stored + 1] = name
			end
		end
		T.eq(#stored, 5)
		T.ok(not ns.Util.IndexOf(stored, "Ivo"), "Ivo is in another group")
		T.ok(ns.Util.IndexOf(stored, "Tess Tester"), "the player by whole name")
		ns.DB.DeletePlan(own.id)
	end)
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
		T.eq(groups.card.seats[1].text:GetText(), "Aldra", "shown by the short name")
		-- Assignment targets: the members by whole name, shown short; a stored whole name reads short.
		local ed = _G.DungeonPlannerMainFrame.instancePage.panels.assignments.inner.editor
		local a = ns.Plan.AddAssignment(own, "Aldra Vey", "Interrupt", nil)
		ns.UI.RefreshPage()
		local values = {}
		for _, opt in ipairs(ed.who.dpOptions()) do
			values[opt.value] = opt.text
		end
		T.eq(values["Aldra Vey"], "Aldra", "stored whole, shown short")
		T.eq(values["Tess Tester"], "Tess")
		T.eq(values["Aldra"], nil, "no first-name entry")
		local list = _G.DungeonPlannerMainFrame.instancePage.panels.assignments.inner.list
		local found = false
		for _, row in ipairs(list.rows) do
			found = found or (row.title:GetText() or ""):find("^Aldra: Interrupt") ~= nil
		end
		T.ok(found, "the row reads the short name")
		ns.Plan.RemoveAssignment(own, a.id)
		ns.DB.DeletePlan(own.id)
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Raid: the strip shows the raid's groups when the plan sets none; Fill from my raid stores whole names", function()
	world({
		raid1 = { name = "Tess", surname = "Tester", cls = "MAGE" },
		raid2 = { name = "Aldra", surname = "Vey", cls = "WARRIOR" },
		raid3 = { name = "Dessa", surname = "Moor", cls = "MAGE" },
	}, { 1, 1, 3 })
	local ok, err = pcall(function()
		local side = boot()
		ns.UI.SelectPlan("b:molten-core")
		side:RefreshParty(ns.UI.ctx:Plan())
		T.eq(side.party.slots[1].name:GetText(), "2/5")
		T.eq(side.party.slots[3].name:GetText(), "1/5")
		T.eq(side.party.slots[2].name:GetText(), "0/5")
		T.eq(side.party.slots[1].name.dpColorRole, "muted", "the raid's, not the plan's")
		T.ok(side.party.tipText:find(ns.L["Groups as your raid stands now: the plan sets none."], 1, true))
		local own = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		ns.UI.SelectPlan(own.id)
		ns.UI.SelectTab("assignments")
		ns.UI.RefreshPage()
		local groups = _G.DungeonPlannerMainFrame.instancePage.panels.assignments.inner.groups
		groups:Fill()
		T.eq(table.concat(own.groups[1], ","), "Tess Tester,Aldra Vey")
		T.eq(table.concat(own.groups[3], ","), "Dessa Moor")
		ns.UI.RefreshPage()
		T.eq(groups.raid.boxes[1].names[2].text:GetText(), "Aldra", "shown by the short name")
		ns.DB.DeletePlan(own.id)
	end)
	restore()
	T.ok(ok, err)
end)

T.case("Notes window: names in pages match members by whole name or a unique first name; own lines", function()
	world({
		party1 = { name = "Aldra", surname = "Vey", cls = "WARRIOR" },
		party2 = { name = "Ana", surname = "Smith", cls = "PRIEST" },
		party3 = { name = "Ana", surname = "Jones", cls = "MAGE" },
	})
	local ok, err = pcall(function()
		boot()
		local env = ns.NotesFrame.Env({ { "Tess Tester", "Aldra Vey" }, { "Aldra" } })
		T.eq(env.me, "Tess")
		T.ok(env.isMe("Tess Tester") and env.isMe("Tess"), "the whole name and the old first name")
		T.ok(not env.isMe("Aldra Vey"))
		T.eq(env.classOf("Aldra"), "WARRIOR", "a word in a page: the one Aldra")
		T.eq(env.classOf("Aldra Vey"), "WARRIOR", "a stored whole name")
		T.eq(env.classOf("Ana"), nil, "two Anas: no colour")
		local text, marked = ns.Pages.Expand("{group 1} stack left.\nAldra taunts.", env)
		T.eq(marked, 1, "the player's group line")
		T.ok(text:find("Aldra|r", 1, true) and not text:find("Aldra Vey", 1, true), "group names shown short, coloured")
		-- The old first-name form of the player in a group marks the line too.
		env = ns.NotesFrame.Env({ { "Tess" } })
		local _, n = ns.Pages.Expand("{group 1} go.", env)
		T.eq(n, 1)
	end)
	restore()
	T.ok(ok, err)
end)
