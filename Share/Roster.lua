-- Who is in the group, their rank, and who a message came from. Glue over the game's unit API (UnitName,
-- UnitIsGroupLeader, ...); every answer goes through Util.Plain, and a secret or missing answer counts as "no". Comm and
-- group sync use it for ranks, members and whisper targets.
--
-- Player identity (docs/COMPATIBILITY.md, "Player names"). On WoW: Forever characters carry a surname: UnitName's second
-- return is the surname, not a realm, and addon-message senders read "First Surname" (Constants'
-- CHARACTERNAME_SURNAME_SEPARATOR, a space), with "-Realm" from another realm; a Forever realm may have no name at all.
-- Elsewhere a unit is "Name" (and its realm as UnitName's second return when it is from another one), and senders are
-- "Name-Realm". Roster.Id gives one form for both: "First Surname" where names carry surnames (unique there, so the realm
-- is left off, as the Forever addons that sync parties do), else "Name" on the player's realm and "Name-Realm" from
-- another. A sender is matched to a group unit by that whole identity, never by a first name, and two units with the
-- same identity make the sender untrusted.

local _, ns = ...
local Roster = ns:NewModule("Roster")
local Util = ns.Util

Roster.MAX_HEARD = 80

local function plainCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Util.Plain(a), Util.Plain(b)
end

local function text(v)
	return type(v) == "string" and v ~= "" and v or nil
end

local function separator()
	local c = rawget(_G, "Constants")
	local consts = type(c) == "table" and c.CharacterNameSeparatorConsts
	local sep = type(consts) == "table" and consts.CHARACTERNAME_SURNAME_SEPARATOR
	return text(sep) or " "
end

-- The player's realm without spaces or hyphens, as senders carry it; nil where the realm has no name (Forever).
local function myRealm()
	local realm = text((plainCall(rawget(_G, "GetNormalizedRealmName"))))
		or text((plainCall(rawget(_G, "GetRealmName"))))
	return realm and text((realm:gsub("[%s%-]", ""))) or nil
end

-- Do names carry surnames here? The player's own name tells: a second return from UnitNameUnmodified or UnitName (the
-- realm never comes back for the player elsewhere), or the separator in the name.
function Roster.Surnames()
	for _, fn in ipairs({ rawget(_G, "UnitNameUnmodified") or false, UnitName or false }) do
		local name, second = plainCall(fn, "player")
		if text(second) or (text(name) and name:find(separator(), 1, true)) then
			return true
		end
	end
	return false
end

-- A sender (as AceComm hands it over) or a typed name in identity form; nil for nothing usable.
function Roster.Id(sender)
	sender = text(Util.Plain(sender))
	if not sender then
		return nil
	end
	local name, realm = sender:match("^(.-)%-([^%-]*)$")
	name = text(name) or sender
	if Roster.Surnames() then
		return name
	end
	realm = realm and text((realm:gsub("[%s%-]", ""))) or nil
	if not realm or realm == myRealm() then
		return name
	end
	return name .. "-" .. realm
end

-- A unit's identity in Roster.Id's form; nil while the client does not know it or keeps it secret.
function Roster.UnitId(unit)
	local name, second = plainCall(UnitName, unit)
	name, second = text(name), text(second)
	if not name then
		return nil
	end
	if Roster.Surnames() then
		if name:find(separator(), 1, true) or not second then
			return name
		end
		return name .. separator() .. second
	end
	return second and Roster.Id(name .. "-" .. second) or name
end

function Roster.Me()
	return Roster.UnitId("player")
end

-- The group's unit tokens (the player first, then the party or raid).
function Roster.Units()
	local units = { "player" }
	if IsInRaid and IsInRaid() then
		units = {}
		for i = 1, 40 do
			units[i] = "raid" .. i
		end
	else
		for i = 1, 4 do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

-- The other group members' identities, never secret values.
function Roster.Members()
	local out, me = {}, Roster.Me()
	for _, unit in ipairs(Roster.Units()) do
		if plainCall(UnitExists, unit) then
			local id = Roster.UnitId(unit)
			if id and id ~= me and not Util.IndexOf(out, id) then
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- Who `id` (a Roster.Id; nil: the player) is in the group: { inGroup, inRaid, leader, assist, unit }. Exactly one unit
-- must have that identity: none, or two (a name the client cannot tell apart), is not in the group.
function Roster.Rank(id)
	local inGroup = (IsInGroup and IsInGroup()) and true or false
	local inRaid = (IsInRaid and IsInRaid()) and true or false
	local unit
	if id == nil then
		unit = "player"
	elseif inGroup then
		local found = 0
		for _, u in ipairs(Roster.Units()) do
			if Roster.UnitId(u) == id then
				unit, found = u, found + 1
			end
		end
		-- No unit reads as that name (one the client spells otherwise): ask the client which unit the sender, as it
		-- arrived, is. Still exactly one.
		if found == 0 then
			local asked = Roster.WhisperTarget(id)
			for _, u in ipairs(Roster.Units()) do
				if plainCall(rawget(_G, "UnitIsUnit"), asked, u) == true then
					unit, found = u, found + 1
				end
			end
		end
		if found ~= 1 then
			unit = nil
		end
	end
	local info = { inGroup = inGroup and unit ~= nil, inRaid = inRaid, unit = unit }
	if unit then
		info.leader = plainCall(rawget(_G, "UnitIsGroupLeader"), unit) == true
		info.assist = plainCall(rawget(_G, "UnitIsGroupAssistant"), unit) == true
	end
	return info
end

-- Whisper targets: a reply goes to the sender's name exactly as it arrived (with its realm or surname), not to the
-- identity, which may have left the realm off. Remembered per identity, the last MAX_HEARD senders.
local heard, heardCount = {}, 0

function Roster.Heard(id, raw)
	if not (id and text(raw)) then
		return
	end
	if not heard[id] then
		if heardCount >= Roster.MAX_HEARD then
			heard, heardCount = {}, 0
		end
		heardCount = heardCount + 1
	end
	heard[id] = raw
end

function Roster.WhisperTarget(id)
	return id and heard[id] or id
end
