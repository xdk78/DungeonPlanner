-- Where the group is inside a dungeon, by room. The client gives no positions there, but it names the area each player
-- stands in, and Data/Subzones.lua finds that area's key by ID; each member's Dungeon Planner tells the group its key,
-- and the maps draw the others in their rooms (UI/MapGroup.lua). Pure (no game API): one explicit state machine,
-- Rooms.Step(state, event, now) -> effects. UI/GroupRooms.lua turns the effects into addon messages (through Comm's
-- lockdown outbox) and timers, and feeds back the zone and roster changes as events.
--
-- State:
--   mine      what the group should know of the player: { iid, area } (area nil: a spot the data does not name), or
--             NOWHERE (outside an instance the data covers, or not sharing); nil outside a group
--   told      what the group was last told (nil: nothing since joining, which the others read as NOWHERE)
--   sentAt    when the last message left; pending: a change waits for MIN_INTERVAL to end
--   ask       the next message asks the others for theirs; asked: that question went out since entering the instance;
--   reply     someone asked: the next message goes out even though nothing changed
--   members   { [name] = { iid, area, at } }: what the other members said, at most MAX_MEMBERS (oldest out first)
--   wake      when the last timer asked for runs out
-- Events:
--   where  { group, share, iid, area }  the player's own place (iid nil: outside an instance the data covers)
--   heard  { from, iid, area, ask }     a group member's message, parsed (Transfer.Parse) and from the group
--   roster { members }                  the other members' names (empty outside a group)
--   tick
-- Effects: { "send", msg } to the group, { "timer", seconds }, { "changed" } (the members' rooms changed: redraw).

local _, ns = ...
local Rooms = ns:NewModule("Rooms")

Rooms.MIN_INTERVAL = 3 -- seconds between two messages: changes in between go out as one, the newest
Rooms.REFRESH = 60 -- a member who stays in one room says so again this often while inside
Rooms.STALE = 300 -- a member not heard from for this long is dropped (disconnected, or the addon gone)
Rooms.MAX_MEMBERS = 40
Rooms.MAX_IID = 2 ^ 31 - 1
Rooms.MAX_KEY = 12 -- "a" or "w" and an ID

local NOWHERE = { iid = 0 }

function Rooms.New()
	return { members = {} }
end

local function same(a, b)
	a, b = a or NOWHERE, b or NOWHERE
	return a.iid == b.iid and a.area == b.area
end

local function inside(s)
	return s.mine ~= nil and s.mine.iid > 0
end

local function send(s, now, effects)
	local m = s.mine
	effects[#effects + 1] = { "send", { type = "room", proto = ns.PROTOCOL_VERSION, iid = m.iid, area = m.area,
		ask = s.ask or nil } }
	s.told, s.sentAt, s.pending, s.ask, s.reply = m, now, nil, nil, nil
end

local function due(s)
	return s.mine ~= nil and (s.ask or s.reply or not same(s.mine, s.told))
end

-- Send now when the last message left MIN_INTERVAL ago, else when that ends (the tick); back to what the group already
-- has, nothing waits.
local function queue(s, now, effects)
	if not due(s) then
		s.pending = nil
	elseif not s.sentAt or now - s.sentAt >= Rooms.MIN_INTERVAL then
		send(s, now, effects)
	else
		s.pending = true
	end
end

local function drop(s, name, effects)
	if s.members[name] then
		s.members[name] = nil
		effects.changed = true
	end
end

local handlers = {}

function handlers.where(s, e, now, effects)
	if not e.group then
		s.mine, s.told, s.sentAt, s.pending, s.ask, s.asked, s.reply = nil, nil, nil, nil, nil, nil, nil
		return
	end
	local iid = e.iid
	if not iid then
		s.asked = nil -- the next instance asks again
	elseif not s.asked then
		s.asked, s.ask = true, true -- entering, joining inside, or a reload: ask the others where they are
	end
	s.mine = (iid and e.share) and { iid = iid, area = e.area } or NOWHERE
	queue(s, now, effects)
end

function handlers.heard(s, e, now, effects)
	if type(e.from) ~= "string" then
		return
	end
	if not (e.iid and e.iid > 0) then
		drop(s, e.from, effects)
	else
		local old = s.members[e.from]
		if not old and ns.Util.Count(s.members) >= Rooms.MAX_MEMBERS then
			local oldest
			for name, m in pairs(s.members) do
				if not oldest or m.at < s.members[oldest].at then
					oldest = name
				end
			end
			drop(s, oldest, effects)
		end
		s.members[e.from] = { iid = e.iid, area = e.area, at = now }
		effects.changed = effects.changed or not (old and old.iid == e.iid and old.area == e.area)
	end
	if e.ask and inside(s) then
		s.reply = true
		queue(s, now, effects)
	end
end

function handlers.roster(s, e, _, effects)
	local keep = {}
	for _, name in ipairs(e.members or {}) do
		keep[name] = true
	end
	for name in pairs(s.members) do
		if not keep[name] then
			drop(s, name, effects)
		end
	end
end

function handlers.tick(s, _, now, effects)
	if s.pending and now - s.sentAt >= Rooms.MIN_INTERVAL then
		queue(s, now, effects)
	elseif inside(s) and s.sentAt and now - s.sentAt >= Rooms.REFRESH then
		send(s, now, effects)
	end
	for name, m in pairs(s.members) do
		if now - m.at >= Rooms.STALE then
			drop(s, name, effects)
		end
	end
end

-- The next time something is due: a waiting change, the refresh, or the oldest member going stale; nil with nothing to
-- wait for, so an idle state asks for no timer.
local function nextWake(s)
	local t
	local function at(v)
		if not t or v < t then
			t = v
		end
	end
	if s.pending then
		at(s.sentAt + Rooms.MIN_INTERVAL)
	end
	if inside(s) and s.sentAt then
		at(s.sentAt + Rooms.REFRESH)
	end
	for _, m in pairs(s.members) do
		at(m.at + Rooms.STALE)
	end
	return t
end

function Rooms.Step(s, e, now)
	local fn = type(e) == "table" and handlers[e.type]
	if not fn then
		return {}
	end
	if e.type == "tick" and s.wake and now >= s.wake then
		s.wake = nil
	end
	local effects = {}
	fn(s, e, now, effects)
	if effects.changed then
		effects.changed = nil
		effects[#effects + 1] = { "changed" }
	end
	local t = nextWake(s)
	if t and not (s.wake and s.wake > now and s.wake <= t) then
		s.wake = t
		effects[#effects + 1] = { "timer", math.max(0, t - now) }
	end
	return effects
end
