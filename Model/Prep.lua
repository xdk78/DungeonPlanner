-- Prep: what a player checks before going into an instance, as pure functions over plain data (Data/PrepInfo.lua and
-- Data/Travel.lua read the game and call these). Quests to pick up, keys and attunements, the group's levels and roles,
-- the nearest flight masters and the way from them, a bearing, and the one-line summary run mode shows.

local _, ns = ...
local Prep = ns:NewModule("Prep")

local sqrt, floor, atan2, deg = math.sqrt, math.floor, math.atan2, math.deg

Prep.MAX_QUESTS = 40 -- rows shown; an instance's list is bounded by the data anyway
Prep.MAX_MEMBERS = 40
Prep.DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
Prep.DUNGEON_NEED = { TANK = 1, HEALER = 1, DAMAGER = 3 }
Prep.FACTION_BIT = { alliance = 1, horde = 2 }

local function sideOk(side, faction)
	return side == nil or side == "both" or faction == nil or side == faction
end
Prep.SideOk = sideOk

-- A quest's state for this character: "done", "log" (in the quest log), "low" (below its required level), "available".
function Prep.QuestStatus(q, env)
	if env.completed and env.completed(q.questID) then
		return "done"
	elseif env.inLog and env.inLog(q.questID) then
		return "log"
	elseif q.req and env.level and env.level < q.req then
		return "low"
	end
	return "available"
end

local ORDER = { log = 1, available = 2, low = 3, done = 4 }

-- quests: BossData.Quests rows ({ questID, name, level?, req?, side?, giver?, items? }).
-- env: { faction = "alliance" | "horde" | nil, level?, completed(id)?, inLog(id)?, title(id)?, givers = { [questID] =
-- { name?, zone?, x?, y? } }?, showAll? }. Returns the rows to show (in the log first, then to pick up, too low, done;
-- by level and name inside each) and the counts { log, available, low, done, other (the other faction's), total }.
function Prep.Quests(quests, env)
	env = env or {}
	local rows = {}
	local counts = { log = 0, available = 0, low = 0, done = 0, other = 0, total = 0 }
	local seen = {}
	for _, q in ipairs(quests or {}) do
		if q.questID and not seen[q.questID] then
			seen[q.questID] = true
			if not sideOk(q.side, env.faction) then
				counts.other = counts.other + 1
			else
				local status = Prep.QuestStatus(q, env)
				counts[status] = counts[status] + 1
				counts.total = counts.total + 1
				if ((status ~= "done" and status ~= "low") or env.showAll) and #rows < Prep.MAX_QUESTS then
					local title = env.title and env.title(q.questID)
					rows[#rows + 1] = {
						questID = q.questID,
						name = (type(title) == "string" and title ~= "") and title or q.name,
						level = q.level, req = q.req, side = q.side, items = q.items, giverID = q.giver,
						giver = env.givers and env.givers[q.questID] or nil,
						status = status,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if ORDER[a.status] ~= ORDER[b.status] then
			return ORDER[a.status] < ORDER[b.status]
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) < (b.level or 0)
		end
		return a.name < b.name
	end)
	return rows, counts
end

-- A quest key is done when its quest or one of its other IDs (alt: the same quest at another reputation, say) is.
local function questDone(k, completed)
	local have = completed(k.questID)
	for _, id in ipairs(k.alt or {}) do
		if have == true then
			break
		end
		local other = completed(id)
		if other ~= nil then
			have = other
		end
	end
	return have
end

-- keys: BossData.Keys rows ({ itemID? | questID?, name, kind, required, side?, quests?, alt?, group?, note?, forever? }).
-- env: { faction?, count(itemID) -> n | nil, completed(questID) -> bool | nil }. Rows keep the order (required first);
-- have = true / false, or nil when the client cannot tell.
function Prep.Keys(keys, env)
	env = env or {}
	local rows = {}
	for _, k in ipairs(keys or {}) do
		if sideOk(k.side, env.faction) then
			local have
			if k.itemID then
				local n = env.count and env.count(k.itemID)
				if type(n) == "number" then
					have = n > 0
				end
			elseif k.questID and env.completed then
				have = questDone(k, env.completed)
			end
			rows[#rows + 1] = { itemID = k.itemID, questID = k.questID, name = k.name, kind = k.kind, group = k.group,
				required = k.required and true or false, note = k.note, forever = k.forever, have = have }
		end
	end
	table.sort(rows, function(a, b)
		if a.required ~= b.required then
			return a.required
		end
		return false
	end)
	return rows
end

-- members: { { name, level?, role = "TANK" | "HEALER" | "DAMAGER" | "NONE", player? } }; lo, hi: the level range (or
-- nil); kind: "dungeon" | "raid". Returns { members (with fit = "low" | "high" | "ok" | nil), roles = counts,
-- missing = { TANK = n, ... } (a dungeon's five seats; nil for a raid), size, low (members under the range) }.
function Prep.Group(members, lo, hi, kind)
	local out = { members = {}, roles = { TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0 }, size = 0, low = 0 }
	for _, m in ipairs(members or {}) do
		if #out.members >= Prep.MAX_MEMBERS then
			break
		end
		local role = out.roles[m.role] and m.role or "NONE"
		out.roles[role] = out.roles[role] + 1
		local fit
		if type(m.level) == "number" and lo then
			if m.level < lo then
				fit = "low"
				out.low = out.low + 1
			elseif hi and m.level > hi then
				fit = "high"
			else
				fit = "ok"
			end
		end
		out.members[#out.members + 1] = { name = m.name, level = m.level, role = role, player = m.player, fit = fit }
		out.size = out.size + 1
	end
	if kind ~= "raid" then
		out.missing = {}
		for role, need in pairs(Prep.DUNGEON_NEED) do
			out.missing[role] = math.max(0, need - out.roles[role])
		end
	end
	return out
end

local function direction(east, north)
	local angle = deg(atan2(east, north)) % 360 -- 0 = north, clockwise
	return Prep.DIRECTIONS[floor((angle + 22.5) / 45) % 8 + 1]
end

-- Map axes: east and south in yards from the player to the target. -> yards, direction key ("NE") or nil when there.
function Prep.Bearing(east, south)
	local d = sqrt(east * east + south * south)
	if d < 1 then
		return 0, nil
	end
	return d, direction(east, -south)
end

-- World coordinates (the game's: x north, y west), from one point to another. -> yards, direction key.
function Prep.WorldBearing(fromX, fromY, toX, toY)
	local north, west = toX - fromX, toY - fromY
	local d = sqrt(north * north + west * west)
	if d < 1 then
		return 0, nil
	end
	return d, direction(-west, north)
end

-- The flight masters of a faction on a continent nearest to a world point: { { node, yards, dir }, ... }, at most n.
-- nodes: { { id, name, continent, x, y, factions (1 Alliance, 2 Horde, 3 both) } } (Data/TravelData.lua).
function Prep.NearestNodes(nodes, continent, x, y, faction, n)
	local bit = Prep.FACTION_BIT[faction]
	local out = {}
	for _, node in ipairs(nodes or {}) do
		local f = node[6]
		if node[3] == continent and (not bit or f == 3 or f == bit) then
			local yards, dir = Prep.WorldBearing(node[4], node[5], x, y)
			out[#out + 1] = { id = node[1], name = node[2], yards = yards, dir = dir }
		end
	end
	table.sort(out, function(a, b)
		return a.yards < b.yards
	end)
	for i = #out, (n or 2) + 1, -1 do
		out[i] = nil
	end
	return out
end

-- Boats and zeppelins from one continent to another a faction may take: { { kind, route }, ... }.
function Prep.Crossings(transports, fromC, toC, faction)
	local out, seen = {}, {}
	for _, t in ipairs(transports or {}) do
		local fine = t[3] == fromC and t[6] == toC and (t[7] == nil or faction == nil or t[7]:lower() == faction)
		if fine and not seen[t[2]] then
			seen[t[2]] = true
			out[#out + 1] = { kind = t[1], route = t[2] }
		end
	end
	return out
end

-- Run mode's prep line: quests still to pick up and required keys missing; nil when there is nothing to do. Rows of
-- one group are one key (an item and the quests toward it): carrying the item settles it; otherwise it is missing
-- once one of its required rows is.
function Prep.Summary(counts, keyRows)
	local quests = counts and counts.available or 0
	local groups, order = {}, {}
	for i, k in ipairs(keyRows or {}) do
		local id = k.group or i
		local g = groups[id]
		if not g then
			g = { missing = false, carried = false }
			groups[id] = g
			order[#order + 1] = g
		end
		if k.itemID and k.have == true then
			g.carried = true
		end
		if k.required and k.have == false then
			g.missing = true
		end
	end
	local keys = 0
	for _, g in ipairs(order) do
		if g.missing and not g.carried then
			keys = keys + 1
		end
	end
	if quests == 0 and keys == 0 then
		return nil
	end
	return { quests = quests, keys = keys }
end
