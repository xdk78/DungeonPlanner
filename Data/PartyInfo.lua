-- What the party strip reads from the game: the group's members (identity, name, role, class, level, online, alive,
-- raid group) and what each class can do. Each call is guarded and every value passes Util.Plain; Model/Party.lua
-- places the members in seats. Read on demand, when the strip or the Party section draws.
--
--   PartyInfo.Members() -> { { id, name, role?, class?, className?, roles?, level?, offline?, dead?, player?,
--                             subgroup? }, ... } (the player first)
--   PartyInfo.InGroup() -> bool                PartyInfo.ClassColor(token) -> r, g, b | nil
--   PartyInfo.Watch(owner, shows)              PARTY_CHANGED goes out a moment after a burst of group events

local _, ns = ...
local PartyInfo = ns:NewModule("PartyInfo")
local Util = ns.Util

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Util.Plain(a), Util.Plain(b), Util.Plain(c)
end

local function g(name)
	return rawget(_G, name)
end

local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- What a class can do ({ TANK = true, ... }) from its specializations, as the client lists them; nil when the client
-- cannot say. A handful of classes: the answers are cached for the session.
local classRoles = {}
local MAX_CLASSES = 32
local function rolesOf(classID)
	if not Util.IsInteger(classID) then
		return nil
	end
	if classRoles[classID] then
		return classRoles[classID]
	end
	local spec = g("C_SpecializationInfo")
	local count = type(spec) == "table" and spec.GetNumSpecializationsForClassID or g("GetNumSpecializationsForClassID")
	local n = call(count, classID)
	local roles = false
	if Util.IsInteger(n) and n > 0 then
		roles = {}
		local get = g("GetSpecializationInfoForClassID")
		for i = 1, math.min(n, 6) do
			local ok, _, _, _, _, role = pcall(get, classID, i)
			role = ok and Util.Plain(role) or nil
			if ROLES[role] then
				roles[role] = true
			end
		end
		if not next(roles) then
			roles = false
		end
	end
	if not roles then
		return nil -- not cached: the client may know the class later
	end
	local size = 0
	for _ in pairs(classRoles) do
		size = size + 1
	end
	if size < MAX_CLASSES then
		classRoles[classID] = roles
	end
	return roles
end
PartyInfo.ClassRoles = rolesOf

function PartyInfo.InGroup()
	return call(g("IsInGroup")) == true
end

-- r, g, b of a class token's colour (RAID_CLASS_COLORS), or nil.
function PartyInfo.ClassColor(token)
	local colors = g("RAID_CLASS_COLORS")
	local c = type(token) == "string" and type(colors) == "table" and colors[token]
	if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
		return c.r, c.g, c.b
	end
	return nil
end

local function member(unit, isPlayer, subgroup)
	local id = ns.Roster.UnitId(unit)
	if not id then
		return nil
	end
	local first = call(UnitName, unit)
	local className, token, classID = call(g("UnitClass"), unit)
	local role = call(g("UnitGroupRolesAssigned"), unit)
	local level = call(g("UnitLevel"), unit)
	return {
		id = id,
		name = Util.ShortName(first) or id,
		role = ROLES[role] and role or nil,
		class = type(token) == "string" and token or nil,
		className = type(className) == "string" and className or nil,
		roles = rolesOf(classID),
		level = Util.IsInteger(level) and level > 0 and level or nil,
		offline = call(g("UnitIsConnected"), unit) == false or nil,
		dead = call(g("UnitIsDeadOrGhost"), unit) == true or nil,
		player = isPlayer or nil,
		subgroup = subgroup,
	}
end

function PartyInfo.Members()
	local out = {}
	if not PartyInfo.InGroup() then
		out[1] = member("player", true)
		return out
	end
	local inRaid = call(g("IsInRaid")) == true
	for i, unit in ipairs(ns.Roster.Units()) do
		if unit == "player" or call(g("UnitExists"), unit) then
			local isPlayer = unit == "player" or call(g("UnitIsUnit"), unit, "player") == true
			local subgroup = inRaid and select(3, call(g("GetRaidRosterInfo"), i)) or nil
			local m = member(unit, isPlayer, Util.IsInteger(subgroup) and subgroup or nil)
			if m then
				-- The player first: the seats fill in this order.
				table.insert(out, isPlayer and 1 or #out + 1, m)
			end
		end
	end
	return out
end

-- The strip and the Party section redraw on PARTY_CHANGED, sent once a moment after the first of a burst of these, and
-- only while one of them is shown (PartyInfo.Watch). UNIT_* events count only for the group's own units.
PartyInfo.EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "PLAYER_LEVEL_UP",
	"UNIT_CONNECTION", "UNIT_FLAGS" }
PartyInfo.DELAY = 0.3
PartyInfo.watchers = {} -- [owner] = function() -> true while it shows the party

local function groupUnit(unit)
	return unit == "player" or (type(unit) == "string" and (unit:match("^party%d$") or unit:match("^raid%d+$"))) ~= nil
end

local pending = false
function PartyInfo.Changed(event, unit)
	if type(event) == "string" and event:sub(1, 5) == "UNIT_" and not groupUnit(unit) then
		return
	end
	local wanted = false
	for _, shows in pairs(PartyInfo.watchers) do
		wanted = wanted or shows() == true
	end
	if not wanted or pending then
		return
	end
	pending = true
	local function fire()
		pending = false
		ns:Fire("PARTY_CHANGED")
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(PartyInfo.DELAY, fire)
	else
		fire()
	end
end

function PartyInfo.Watch(owner, shows)
	PartyInfo.watchers[owner] = shows
end

function PartyInfo.Init()
	for _, event in ipairs(PartyInfo.EVENTS) do
		ns:RegisterEvent(event, PartyInfo.Changed)
	end
end
