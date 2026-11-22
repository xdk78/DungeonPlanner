-- Party: who sits in which seat of the party strip, as pure functions over plain data (Data/PartyInfo.lua reads the
-- group). A dungeon has five seats: tank, healer and three damage dealers; a plan stores names for them in groups 1-3
-- (1 = tank, 2 = healer, 3 = damage). What the plan stores wins: a live member is matched to a stored name by the
-- whole identity (Share/Roster.lua), never by a first name. The other seats take the group as it is now:
--
--   1. a member whose role is set (the group finder's) takes a free seat of that role;
--   2. a member without a role whose class can only deal damage takes a free damage seat;
--   3. a member without a role whose class can also tank or heal takes an empty tank or healer seat it can fill
--      (the most constrained member first), else a free damage seat: a guess, and marked as one;
--   4. whoever is left takes any free seat, marked as off their role (or a guess), and past five seats is an extra.
--
-- Nothing here is saved: the fill is drawn while the group lasts.

local _, ns = ...
local Party = ns:NewModule("Party")

Party.MAX_MEMBERS = 40
Party.SEATS = {
	{ role = "TANK", group = 1, index = 1 },
	{ role = "HEALER", group = 2, index = 1 },
	{ role = "DAMAGER", group = 3, index = 1 },
	{ role = "DAMAGER", group = 3, index = 2 },
	{ role = "DAMAGER", group = 3, index = 3 },
}
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function text(v)
	return type(v) == "string" and v ~= "" and v or nil
end

-- members: { { id, name, role?, roles? = { TANK = true, ... } (what the class can do; nil: unknown), ... } }, the
-- player first. Members without an identity, and repeats of one, are left out; at most MAX_MEMBERS.
local function clean(members)
	local out, seen = {}, {}
	for _, m in ipairs(type(members) == "table" and members or {}) do
		if #out >= Party.MAX_MEMBERS then
			break
		end
		local id = type(m) == "table" and text(m.id)
		if id and not seen[id] then
			seen[id] = true
			out[#out + 1] = m
		end
	end
	return out
end

-- The seat's role a member's class could fill, when the class can do more than deal damage.
local function canFill(m, role)
	return type(m.roles) == "table" and m.roles[role] == true
end

local function damageOnly(m)
	if type(m.roles) ~= "table" then
		return false
	end
	return m.roles.DAMAGER == true and not m.roles.TANK and not m.roles.HEALER
end

-- groups: the plan's groups (a dungeon's seats in groups 1-3); members: as above; idOf(name): a stored name in identity
-- form (Roster.Id; default: the name itself). Returns { seats = { { role, stored?, member?, how }, ... }, extra =
-- { member, ... } }. how: "stored" (a stored name, member set when it is in the group), "role" (the member's role),
-- "class" (a damage-only class), "guess" (a hybrid placed from its class, or a class the client could not tell),
-- "offrole" (a role whose seats are taken), nil (open).
function Party.Fill(groups, members, idOf)
	idOf = idOf or function(name)
		return name
	end
	groups = type(groups) == "table" and groups or {}
	local list = clean(members)
	local byId = {}
	for _, m in ipairs(list) do
		byId[m.id] = m
	end
	local placed, seats = {}, {}
	for i, spec in ipairs(Party.SEATS) do
		local g = groups[spec.group]
		local name = type(g) == "table" and text(g[spec.index]) or nil
		local seat = { role = spec.role }
		if name then
			seat.stored, seat.how = name, "stored"
			local m = byId[idOf(name) or name]
			if m and not placed[m] then
				seat.member, placed[m] = m, true
			end
		end
		seats[i] = seat
	end

	local function free(role)
		for _, seat in ipairs(seats) do
			if not seat.how and (role == nil or seat.role == role) then
				return seat
			end
		end
		return nil
	end
	local function sit(seat, m, how)
		seat.member, seat.how, placed[m] = m, how, true
	end

	-- 1. Roles set.
	for _, m in ipairs(list) do
		if not placed[m] and ROLES[m.role] then
			local seat = free(m.role)
			if seat then
				sit(seat, m, "role")
			end
		end
	end
	-- 2. Damage-only classes without a role.
	for _, m in ipairs(list) do
		if not placed[m] and not ROLES[m.role] and damageOnly(m) then
			local seat = free("DAMAGER")
			if seat then
				sit(seat, m, "class")
			end
		end
	end
	-- 3. Hybrids without a role: the empty tank and healer seats first, the member with the fewest choices first.
	local hybrids = {}
	for i, m in ipairs(list) do
		if not placed[m] and not ROLES[m.role] then
			hybrids[#hybrids + 1] = { m = m, order = i }
		end
	end
	local function choices(m)
		local n = 0
		for _, role in ipairs({ "TANK", "HEALER" }) do
			if canFill(m, role) and free(role) then
				n = n + 1
			end
		end
		return n
	end
	-- How many of tank and healer the class can do at all: on a tie, the less flexible member takes the seat (a priest
	-- heals before a druid, who can still tank or deal damage).
	local function flex(m)
		return (canFill(m, "TANK") and 1 or 0) + (canFill(m, "HEALER") and 1 or 0)
	end
	local function before(a, an, b, bn)
		if an ~= bn then
			return an < bn
		end
		if flex(a.m) ~= flex(b.m) then
			return flex(a.m) < flex(b.m)
		end
		return a.order < b.order
	end
	while true do
		local best, bestN
		for _, h in ipairs(hybrids) do
			if not placed[h.m] then
				local n = choices(h.m)
				if n > 0 and (not best or before(h, n, best, bestN)) then
					best, bestN = h, n
				end
			end
		end
		if not best then
			break
		end
		local role = (canFill(best.m, "TANK") and free("TANK")) and "TANK" or "HEALER"
		sit(free(role), best.m, "guess")
	end
	for _, h in ipairs(hybrids) do
		local seat = not placed[h.m] and free("DAMAGER")
		if seat then
			sit(seat, h.m, "guess")
		end
	end
	-- 4. The rest: a free damage seat, else any free seat, then the extras.
	local extra = {}
	for _, m in ipairs(list) do
		if not placed[m] then
			local seat = free("DAMAGER") or free(nil)
			if seat then
				sit(seat, m, ROLES[m.role] and "offrole" or "guess")
			else
				extra[#extra + 1] = m
			end
		end
	end
	return { seats = seats, extra = extra }
end

-- A raid's eight groups for the strip: the plan's counts when it stores any group, else the raid's as it is now.
-- groups: the plan's groups; members: { { subgroup }, ... } (none outside a raid); n: the number of groups. Returns
-- counts, live (true when the counts are the raid's).
function Party.RaidCounts(groups, members, n)
	local counts, stored = {}, false
	for gi = 1, n do
		local g = type(groups) == "table" and groups[gi]
		counts[gi] = type(g) == "table" and #g or 0
		stored = stored or counts[gi] > 0
	end
	if stored or type(members) ~= "table" or #members == 0 then
		return counts, false
	end
	for gi = 1, n do
		counts[gi] = 0
	end
	for i, m in ipairs(members) do
		if i > Party.MAX_MEMBERS then
			break
		end
		local gi = type(m) == "table" and m.subgroup
		if type(gi) == "number" and counts[gi] then
			counts[gi] = counts[gi] + 1
		end
	end
	return counts, true
end
