-- Shared-plan tracking: who has which version of a plan this character sent in game. Pure (no game API); Comm.lua
-- sends and receives the acknowledgements, the Share section shows the summary.
--
-- A receiver that imported a plan from an in-game transfer whispers back a small ack, K^<tid>^<plan id>^<version>
-- (docs/SHARING-FORMAT.md): the transfer, the sender's plan id and the plan's `updated` time as it was sent. The sender
-- keeps, per plan, each member's version. Against the plan's current `updated` an ack is "current" or "outdated".
-- Group members without an ack are "missing" when they run Dungeon Planner (their hello was seen) and "unknown"
-- otherwise: trial accounts cannot send addon messages, other clients and players without the addon never answer,
-- and the game does not say which is which.
--
-- Store (DungeonPlannerDB.char[key].shareAcks): { plans = { [plan id] = { at, members = { [name] = { v, at } } } } }

local _, ns = ...
local Acks = ns:NewModule("Acks")
local Util = ns.Util

Acks.MAX_PLANS = 30
Acks.MAX_MEMBERS = 40

local EMPTY = {}

function Acks.ValidPlanId(id)
	return type(id) == "string" and #id >= 1 and #id <= 48 and id:match("^[%w_:%-]+$") ~= nil
end

function Acks.Normalize(store)
	if type(store) ~= "table" then
		store = {}
	end
	local plans = {}
	local n = 0
	for id, rec in pairs(type(store.plans) == "table" and store.plans or EMPTY) do
		if Acks.ValidPlanId(id) and type(rec) == "table" and type(rec.members) == "table" and n < Acks.MAX_PLANS then
			local members, m = {}, 0
			for name, a in pairs(rec.members) do
				if type(name) == "string" and #name <= ns.Schema.TEXT.player and type(a) == "table" and Util.IsInteger(a.v)
					and m < Acks.MAX_MEMBERS then
					members[name] = { v = a.v, at = Util.IsInteger(a.at) and a.at or 0 }
					m = m + 1
				end
			end
			plans[id] = { at = Util.IsInteger(rec.at) and rec.at or 0, members = members }
			n = n + 1
		end
	end
	store.plans = plans
	return store
end

-- Record that `name` has version `version` of plan `planId`. A newer version replaces an older one, never the other way
-- round. The oldest plan goes first when the store is full; a plan keeps at most MAX_MEMBERS names (the oldest go).
-- Returns true when something changed.
function Acks.Record(store, planId, name, version, now)
	if not (Acks.ValidPlanId(planId) and type(name) == "string" and name ~= "" and Util.IsInteger(version)) then
		return false
	end
	local rec = store.plans[planId]
	if not rec then
		local count, oldestId, oldestAt = 0, nil, nil
		for id, r in pairs(store.plans) do
			count = count + 1
			if not oldestAt or r.at < oldestAt then
				oldestId, oldestAt = id, r.at
			end
		end
		if count >= Acks.MAX_PLANS and oldestId then
			store.plans[oldestId] = nil
		end
		rec = { at = now, members = {} }
		store.plans[planId] = rec
	end
	local old = rec.members[name]
	if old and old.v >= version then
		return false
	end
	if not old then
		local count, oldestName, oldestAt = 0, nil, nil
		for n, a in pairs(rec.members) do
			count = count + 1
			if not oldestAt or a.at < oldestAt then
				oldestName, oldestAt = n, a.at
			end
		end
		if count >= Acks.MAX_MEMBERS and oldestName then
			rec.members[oldestName] = nil
		end
	end
	rec.members[name] = { v = version, at = now }
	rec.at = now
	return true
end

-- Links: which plan a received or imported copy came from, so a leader's run (Share/Sync.lua) is matched to the copy.
-- An import gets a new id here; the link keeps the sender's plan id (`b:<id>` for a recommended plan), the version it
-- had (its `updated`) and the copy's own `updated` right after the import (an edit since makes it another version).
-- Store (DungeonPlannerDB.global.shareLinks): { [local plan id] = { plan, v, u, at } }, since schema 5 (Config/DB.lua
-- migration 5).
Acks.MAX_LINKS = 100

local function validLink(id, l)
	return Acks.ValidPlanId(id) and type(l) == "table" and Acks.ValidPlanId(l.plan) and Util.IsInteger(l.v)
		and Util.IsInteger(l.u)
end

function Acks.NormalizeLinks(links)
	local out, n = {}, 0
	for id, l in pairs(type(links) == "table" and links or EMPTY) do
		if validLink(id, l) and n < Acks.MAX_LINKS then
			out[id] = { plan = l.plan, v = l.v, u = l.u, at = Util.IsInteger(l.at) and l.at or 0 }
			n = n + 1
		end
	end
	return out
end

-- Remember that local plan `localId` is plan `planId` at version `version`; `updated` is the copy's own. The oldest
-- link goes when the store is full. Returns true when stored.
function Acks.Link(links, localId, planId, version, updated, now)
	local l = { plan = planId, v = version, u = updated, at = now }
	if not (type(links) == "table" and validLink(localId, l)) then
		return false
	end
	if not links[localId] then
		local count, oldestId, oldestAt = 0, nil, nil
		for id, old in pairs(links) do
			count = count + 1
			if not oldestAt or old.at < oldestAt then
				oldestId, oldestAt = id, old.at
			end
		end
		if count >= Acks.MAX_LINKS and oldestId then
			links[oldestId] = nil
		end
	end
	links[localId] = l
	return true
end

-- The group against a plan: members = the other group members' names, current = the plan's `updated`, peers = the
-- names known to run Dungeon Planner (Comm.peers). Returns { total, has, current, outdated, missing, unknown,
-- list = { { name, state = "current" | "outdated" | "missing" | "unknown" } } }; `has` counts current and outdated.
function Acks.Status(store, planId, current, members, peers)
	local rec = store and store.plans[planId]
	local out = { total = #members, has = 0, current = 0, outdated = 0, missing = 0, unknown = 0, list = {} }
	for _, name in ipairs(members) do
		local a = rec and rec.members[name]
		local state
		if a then
			state = (current and a.v < current) and "outdated" or "current"
			out.has = out.has + 1
		elseif peers and peers[name] then
			state = "missing"
		else
			state = "unknown"
		end
		out[state] = out[state] + 1
		out.list[#out.list + 1] = { name = name, state = state }
	end
	return out
end
