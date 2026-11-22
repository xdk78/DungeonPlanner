-- Group sync for run mode: the group leader's run mode drives the members'. Pure (no game API): one explicit state
-- machine, Sync.Step(state, event, now) -> effects. UI/RunSync.lua turns the effects into addon messages (through
-- Comm's lockdown outbox), timers and step changes, and feeds back what the game and the player do as events.
--
-- Modes (state.mode) and the data each one carries:
--   idle       nothing to follow, not leading
--   leading    this player drives the run: session, seq, plan, version, step, pull, sentAt, pending, sent,
--              followers = { [name] = { status, at } }, answered = { [name] = at }, offered = { [name] = at }
--   following  a trusted leader's run is followed: lead, localId (the matching local plan), applied (what was last
--              focused: appliedId, applied), hold (a boss kill moved on before the leader's word came), reported
--   free       the same lead, but the player steps on their own ("Rejoin" goes back): lead, localId, reported
--   mismatch   the leader is on a plan the player lacks ("missing") or has in another version ("version"): lead, why,
--              askedAt, reported
--   (leading also carries askers and answerAt while answering "who leads?"; idle, queryAt while its question waits)
-- `lead` = { name, session, seq, plan, version, step, pull } as the leader last sent it. `version` is the plan's steps
-- revision (Sync.Signature): edits that leave the steps as they were (notes, strategies, gear) keep it, so followers
-- stay with a leader who edits mid-run. Kept across modes: `queriedAt` (when the player last asked the group who
-- leads, a rate limit) and `ended` = { { name, session }, ... } (the last MAX_ENDED leads that ended, oldest first:
-- nothing more of them is taken, so a delayed state of an older session cannot bring it back).
--
-- Events:
--   leader:  lead { rank, session, plan, version, step, pull }  stop  moved { plan, version, step, pull }
--            report { from, rank, session, status }  query { from, rank }  want { from, rank, session }
--   member:  run { from, rank, leadRank, msg, match }  unfollow  rejoin  request  localStep { plan, index }
--            localKill { plan, index }  show { inGroup, jitter }  resolve { match }
--   both:    tick  roster { inGroup, self, leadRank, members, shown, jitter }  leave
-- `rank` = Comm.GroupRank of the sender as the receiver's own roster has it; `match` = Sync.Resolve of the leader's plan;
-- `jitter` = 0..QUERY_JITTER seconds the glue draws, so a raid's members do not all ask at once.
--
-- Effects: { "send", msg, "GROUP" | "WHISPER", target, key }  (key: a newer message with the same key replaces an
-- older one still waiting in the outbox), { "timer", seconds }, { "focus", local plan id, step (0: not started) },
-- { "offer", name, plan id }, { "status" }, { "refused" }.

local _, ns = ...
local Sync = ns:NewModule("Sync")

Sync.MIN_INTERVAL = 1 -- seconds between two run states from the leader: changes in between go out as one
Sync.KILL_HOLD = 10 -- seconds a boss kill seen here wins over an older step from the leader (held in a boss fight)
Sync.QUERY_INTERVAL = 30 -- a member asks the group who leads at most this often
Sync.QUERY_JITTER = 2 -- a member's question waits up to this long, drawn at random (a raid's members join at once)
Sync.ANSWER_INTERVAL = 5 -- the leader answers one member's question at most this often
Sync.ANSWER_DELAY = 1 -- questions within this long get one answer: a whisper to one asker, else one group message
Sync.OFFER_INTERVAL = 60 -- the leader offers the plan to one member at most this often
Sync.ASK_INTERVAL = 20 -- a member asks the leader for the plan at most this often
Sync.MAX_SEQ = 2 ^ 31 - 1
Sync.MAX_VERSION = 2 ^ 32 - 1 -- an Adler-32
Sync.MAX_STEP = 999
Sync.MAX_PULL = 100
Sync.MAX_FOLLOWERS = 40
Sync.MAX_ENDED = 8 -- ended leads remembered

-- The follow status a member reports (F^...^<code>).
Sync.CODE = { following = "f", free = "u", missing = "m", version = "o" }
Sync.STATUS = { f = "following", u = "free", m = "missing", o = "version" }

function Sync.New()
	return { mode = "idle" }
end

-- Who may lead, and whose run is followed: the group's leader, or in a raid an assistant (the same rule as raid pages).
function Sync.Trusted(rank)
	return ns.Pages.AcceptFrom("leaders", rank)
end

function Sync.LeadName(state)
	return state.lead and state.lead.name or nil
end

-- A plan's steps revision: the Adler-32 of its steps in order (kind and what each one is: pull, boss, marker,
-- objective). The step index means the same step on two clients exactly when this matches. steps = Steps.Build(plan).
function Sync.Signature(steps)
	steps = steps or {}
	local parts = { tostring(#steps) }
	for i, s in ipairs(steps) do
		parts[i + 1] = s.kind .. ":" .. tostring(s.pull or "") .. "/" .. tostring(s.encounter or "") .. "/"
			.. tostring(s.objective or s.marker or "")
	end
	return ns.Checksum.Adler32(table.concat(parts, ","))
end

-- The local plan that is the leader's plan `planId` with steps revision `version`: the plan with that id (a recommended
-- plan, or the same account), else the newest copy received from it (Acks.Link). get(id) -> plan or nil; links =
-- { [local id] = { plan, at } }; sigOf(plan) -> its Sync.Signature. Returns { status = "ok", id } or
-- { status = "version" } (only copies whose steps differ) or { status = "missing" }.
function Sync.Resolve(planId, version, get, links, sigOf)
	local candidates = {}
	local direct = get(planId)
	if direct then
		candidates[1] = { id = direct.id, plan = direct, at = math.huge }
	end
	for localId, l in pairs(links or {}) do
		local p = l.plan == planId and get(localId)
		if p then
			candidates[#candidates + 1] = { id = localId, plan = p, at = l.at }
		end
	end
	table.sort(candidates, function(a, b)
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.id < b.id
	end)
	for _, c in ipairs(candidates) do
		if sigOf(c.plan) == version then
			return { status = "ok", id = c.id }
		end
	end
	return { status = #candidates > 0 and "version" or "missing" }
end

-- Mode changes: everything but what is kept across modes goes; `fields` are the new mode's data.
local KEEP = { queriedAt = true, ended = true }
local function enter(state, mode, fields)
	for k in pairs(state) do
		if not KEEP[k] then
			state[k] = nil
		end
	end
	state.mode = mode
	for k, v in pairs(fields or {}) do
		state[k] = v
	end
end

local function proto()
	return ns.PROTOCOL_VERSION
end

-- Leader -----------------------------------------------------------------------------------------------------------------

local function broadcast(s, now, effects)
	s.seq = s.seq + 1
	s.sentAt, s.pending = now, nil
	s.sent = { plan = s.plan, version = s.version, step = s.step, pull = s.pull }
	effects[#effects + 1] = { "send", { type = "run", proto = proto(), session = s.session, seq = s.seq, plan = s.plan,
		version = s.version, step = s.step, pull = s.pull }, "GROUP", nil, "run" }
end

local function sameAs(a, e)
	return a ~= nil and a.plan == e.plan and a.version == e.version and a.step == e.step and a.pull == e.pull
end

local function clamp(n, hi)
	n = math.floor(tonumber(n) or 0)
	return math.max(0, math.min(hi, n))
end

local function endLead(s, effects)
	s.seq = s.seq + 1
	effects[#effects + 1] = { "send", { type = "run", proto = proto(), session = s.session, seq = s.seq }, "GROUP", nil,
		"run" }
	enter(s, "idle")
	effects[#effects + 1] = { "status" }
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- Forget the oldest entry of a { [name] = at | { at } } map once it holds MAX_FOLLOWERS.
local function bound(t)
	if count(t) < Sync.MAX_FOLLOWERS then
		return
	end
	local oldest, oldestAt
	for name, v in pairs(t) do
		local at = type(v) == "table" and v.at or v
		if not oldestAt or at < oldestAt then
			oldest, oldestAt = name, at
		end
	end
	t[oldest] = nil
end

local leader = {}

function leader.moved(s, e, now)
	if not e.plan then
		return {}
	end
	local pos = { plan = e.plan, version = clamp(e.version, Sync.MAX_VERSION), step = clamp(e.step, Sync.MAX_STEP),
		pull = clamp(e.pull, Sync.MAX_PULL) }
	s.plan, s.version, s.step, s.pull = pos.plan, pos.version, pos.step, pos.pull
	if sameAs(s.sent, pos) then
		s.pending = nil -- back to what the group has: nothing to send
		return {}
	end
	local effects = {}
	if now - s.sentAt >= Sync.MIN_INTERVAL then
		broadcast(s, now, effects)
	elseif not s.pending then
		s.pending = true
		effects[1] = { "timer", s.sentAt + Sync.MIN_INTERVAL - now }
	end
	return effects
end

function leader.tick(s, _, now)
	local effects = {}
	if s.answerAt and now >= s.answerAt then
		-- The questions of the last ANSWER_DELAY: one asker gets a whisper, several one group message.
		local only, n = nil, 0
		for name in pairs(s.askers) do
			only, n = name, n + 1
		end
		s.askers, s.answerAt = {}, nil
		if n > 1 then
			broadcast(s, now, effects)
		elseif only then
			s.seq = s.seq + 1
			effects[#effects + 1] = { "send", { type = "run", proto = proto(), session = s.session, seq = s.seq,
				plan = s.plan, version = s.version, step = s.step, pull = s.pull }, "WHISPER", only, "run" }
		end
	end
	if s.pending and now >= s.sentAt + Sync.MIN_INTERVAL then
		broadcast(s, now, effects)
	end
	return effects
end

function leader.stop(s)
	local effects = {}
	endLead(s, effects)
	return effects
end

function leader.report(s, e, now)
	local status = Sync.STATUS[e.status]
	if not (status and e.session == s.session and e.rank and e.rank.inGroup and type(e.from) == "string") then
		return {}
	end
	local old = s.followers[e.from]
	if old and old.status == status then
		old.at = now
		return {}
	end
	if not old then
		bound(s.followers)
	end
	s.followers[e.from] = { status = status, at = now }
	return { { "status" } }
end

-- A member asks who leads: the current state, whispered.
function leader.query(s, e, now)
	if not (e.rank and e.rank.inGroup and type(e.from) == "string") then
		return {}
	end
	local last = s.answered[e.from]
	if last and now - last < Sync.ANSWER_INTERVAL then
		return {}
	end
	if not last then
		bound(s.answered)
	end
	s.answered[e.from] = now
	s.askers[e.from] = true
	if s.answerAt then
		return {}
	end
	s.answerAt = now + Sync.ANSWER_DELAY
	return { { "timer", Sync.ANSWER_DELAY } }
end

-- A member without the plan (or with another version) asks for it: the normal share offer, whispered.
function leader.want(s, e, now)
	if not (e.rank and e.rank.inGroup and e.session == s.session and type(e.from) == "string") then
		return {}
	end
	local last = s.offered[e.from]
	if last and now - last < Sync.OFFER_INTERVAL then
		return {}
	end
	if not last then
		bound(s.offered)
	end
	s.offered[e.from] = now
	return { { "offer", e.from, s.plan } }
end

function leader.roster(s, e)
	if not e.inGroup then
		enter(s, "idle")
		return { { "status" } }
	end
	if not Sync.Trusted(e.self) then
		local effects = {}
		endLead(s, effects)
		return effects
	end
	local keep, changed = {}, false
	for _, name in ipairs(e.members or {}) do
		keep[name] = true
	end
	for name in pairs(s.followers) do
		if not keep[name] then
			s.followers[name] = nil
			changed = true
		end
	end
	return changed and { { "status" } } or {}
end

-- Member -----------------------------------------------------------------------------------------------------------------

local function code(s)
	if s.mode == "mismatch" then
		return s.why == "missing" and Sync.CODE.missing or Sync.CODE.version
	end
	return Sync.CODE[s.mode]
end

-- Tell the leader where this player stands, when it changed (or for a new lead).
local function report(s, effects, force)
	local c = code(s)
	if c and (force or s.reported ~= c) then
		s.reported = c
		effects[#effects + 1] = { "send", { type = "follow", proto = proto(), session = s.lead.session, status = c },
			"WHISPER", s.lead.name, "follow" }
	end
end

-- Show the leader's step, unless a boss kill seen here moved past it and the leader's word may still be on its way.
local function focusLead(s, now, effects)
	local h = s.hold
	if h then
		if s.lead.step < h.index and now < h.untilT then
			return
		end
		s.hold = nil
	end
	if s.applied ~= s.lead.step or s.appliedId ~= s.localId then
		s.applied, s.appliedId = s.lead.step, s.localId
		effects[#effects + 1] = { "focus", s.localId, s.lead.step }
	end
end

local function follow(s, lead, localId, reported, now, effects)
	enter(s, "following", { lead = lead, localId = localId, reported = reported })
	focusLead(s, now, effects)
end

-- Ask the group who leads, after a random wait (a raid's members open run mode or join at once): the question goes on
-- the tick at queryAt, unless a lead was heard meanwhile (a mode change drops queryAt).
local function maybeQuery(s, e, now, effects)
	if e.inGroup and (not s.queriedAt or now - s.queriedAt >= Sync.QUERY_INTERVAL) then
		local wait = math.max(0, math.min(Sync.QUERY_JITTER, tonumber(e.jitter) or 0))
		s.queriedAt, s.queryAt = now, now + wait
		effects[#effects + 1] = { "timer", wait }
	end
end

local member = {}

function member.run(s, e, now)
	local m = e.msg
	if s.mode == "leading" or type(m) ~= "table" or type(e.from) ~= "string" or not Sync.Trusted(e.rank) then
		return {}
	end
	for _, ended in ipairs(s.ended or {}) do
		if ended.name == e.from and ended.session == m.session then
			return {} -- that lead ended: nothing more of it counts, whatever its number
		end
	end
	local lead = s.lead
	if lead and lead.name ~= e.from then
		-- Another trusted sender takes over only from a lead that is no longer trusted, or as the group's leader from
		-- an assistant.
		if Sync.Trusted(e.leadRank) and not (e.rank.leader and not e.leadRank.leader) then
			return {}
		end
		lead = nil
	end
	if lead and m.session == lead.session and m.seq <= lead.seq then
		return {} -- stale or repeated
	end
	if not m.plan then
		-- Only the followed lead's own end counts: an end of an older session (held in an outbox) leaves a new one be.
		if not lead or m.session ~= lead.session then
			return {}
		end
		s.ended = s.ended or {}
		if #s.ended >= Sync.MAX_ENDED then
			table.remove(s.ended, 1)
		end
		s.ended[#s.ended + 1] = { name = e.from, session = m.session }
		enter(s, "idle")
		return { { "status" } }
	end
	local newSession = not lead or lead.session ~= m.session
	local nextLead = { name = e.from, session = m.session, seq = m.seq, plan = m.plan, version = m.version, step = m.step,
		pull = m.pull }
	local reported = not newSession and s.reported or nil
	local match = e.match or { status = "missing" }
	local effects = {}
	if match.status == "ok" then
		if s.mode == "free" and not newSession and s.localId == match.id then
			s.lead = nextLead
		elseif s.mode == "following" and not newSession and s.localId == match.id then
			s.lead = nextLead
			focusLead(s, now, effects)
		else
			follow(s, nextLead, match.id, reported, now, effects)
		end
	else
		local askedAt = s.mode == "mismatch" and not newSession and s.askedAt or nil
		enter(s, "mismatch", { lead = nextLead, why = match.status, askedAt = askedAt, reported = reported })
	end
	report(s, effects, newSession)
	effects[#effects + 1] = { "status" }
	return effects
end

function member.unfollow(s)
	if s.mode ~= "following" then
		return {}
	end
	enter(s, "free", { lead = s.lead, localId = s.localId, reported = s.reported })
	local effects = {}
	report(s, effects)
	effects[#effects + 1] = { "status" }
	return effects
end

function member.rejoin(s, _, now)
	if s.mode ~= "free" then
		return {}
	end
	local effects = {}
	follow(s, s.lead, s.localId, s.reported, now, effects)
	report(s, effects)
	effects[#effects + 1] = { "status" }
	return effects
end

-- The player moved on their own (Prev / Next, a step clicked, another plan chosen) while following: they step freely.
function member.localStep(s, e)
	if s.mode ~= "following" or (e.plan == s.appliedId and e.index == s.applied) then
		return {}
	end
	return member.unfollow(s)
end

-- Run mode moved past a boss on its kill (the leader's next state is held in the boss fight's lockdown): for a while an
-- older step from the leader does not pull the player back.
function member.localKill(s, e, now)
	if s.mode ~= "following" or e.plan ~= s.localId or type(e.index) ~= "number" then
		return {}
	end
	s.hold = { index = e.index, untilT = now + Sync.KILL_HOLD }
	s.applied, s.appliedId = e.index, s.localId
	return { { "timer", Sync.KILL_HOLD } }
end

-- Run mode opened: show the leader's step (the player may have moved while it was closed), or ask who leads.
function member.show(s, e, now)
	local effects = {}
	if s.mode == "following" then
		s.applied, s.hold = nil, nil
		focusLead(s, now, effects)
	elseif s.mode == "idle" then
		maybeQuery(s, e, now, effects)
	end
	return effects
end

-- The plans changed here (a plan received, edited or deleted): match the leader's plan again.
function member.resolve(s, e, now)
	if not s.lead or not e.match then
		return {}
	end
	local match, effects = e.match, {}
	if match.status ~= "ok" then
		if s.mode == "mismatch" and s.why == match.status then
			return {}
		end
		enter(s, "mismatch", { lead = s.lead, why = match.status, reported = s.reported })
	elseif s.mode == "mismatch" then
		follow(s, s.lead, match.id, s.reported, now, effects)
	elseif match.id ~= s.localId then
		s.localId = match.id
		if s.mode == "following" then
			focusLead(s, now, effects)
		end
	else
		return {}
	end
	report(s, effects)
	effects[#effects + 1] = { "status" }
	return effects
end

-- "Ask for it": the leader gets a request and offers the plan the usual way.
function member.request(s, _, now)
	if s.mode ~= "mismatch" or (s.askedAt and now - s.askedAt < Sync.ASK_INTERVAL) then
		return {}
	end
	s.askedAt = now
	return { { "send", { type = "want", proto = proto(), session = s.lead.session }, "WHISPER", s.lead.name, "want" },
		{ "status" } }
end

function member.tick(s, _, now)
	local effects = {}
	if s.mode == "following" and s.hold and now >= s.hold.untilT then
		focusLead(s, now, effects)
	elseif s.mode == "idle" and s.queryAt and now >= s.queryAt then
		s.queryAt = nil
		effects[1] = { "send", { type = "query", proto = proto() }, "GROUP", nil, "query" }
	end
	return effects
end

function member.roster(s, e, now)
	local effects = {}
	if not e.inGroup then
		if s.mode ~= "idle" then
			enter(s, "idle")
			effects[1] = { "status" }
		end
		return effects
	end
	if s.lead and not Sync.Trusted(e.leadRank) then
		enter(s, "idle")
		effects[1] = { "status" }
	end
	if s.mode == "idle" and e.shown then
		maybeQuery(s, e, now, effects)
	end
	return effects
end

-- Step ---------------------------------------------------------------------------------------------------------------------

function Sync.Step(s, e, now)
	local t = type(e) == "table" and e.type or nil
	if t == "leave" then
		if s.mode == "idle" then
			return {}
		end
		enter(s, "idle")
		return { { "status" } }
	end
	if t == "lead" then
		if not (Sync.Trusted(e.rank) and e.plan and type(e.session) == "string") then
			return { { "refused" } }
		end
		enter(s, "leading", { session = e.session, seq = 0, sentAt = now, followers = {}, answered = {}, offered = {}, askers = {},
			plan = e.plan, version = clamp(e.version, Sync.MAX_VERSION), step = clamp(e.step, Sync.MAX_STEP),
			pull = clamp(e.pull, Sync.MAX_PULL) })
		local effects = {}
		broadcast(s, now, effects)
		effects[#effects + 1] = { "status" }
		return effects
	end
	local handlers = s.mode == "leading" and leader or member
	local fn = handlers[t]
	return fn and fn(s, e, now) or {}
end

-- The leader's view of the group: members = the other group members' names; acks = Acks.Status's list (who has the
-- plan, for members that never reported). Returns { total, following, free, outOfSync, unknown,
-- list = { { name, state = "following" | "free" | "missing" | "version" | "unknown" } } }.
function Sync.Summary(s, members, acks)
	local out = { total = #members, following = 0, free = 0, outOfSync = 0, unknown = 0, list = {} }
	local ackOf = {}
	for _, a in ipairs(acks or {}) do
		ackOf[a.name] = a.state
	end
	for _, name in ipairs(members) do
		local f = s.mode == "leading" and s.followers[name]
		local state = f and f.status or (ackOf[name] == "outdated" and "version" or "unknown")
		if state == "following" or state == "free" or state == "unknown" then
			out[state] = out[state] + 1
		else
			out.outOfSync = out.outOfSync + 1
		end
		out.list[#out.list + 1] = { name = name, state = state }
	end
	return out
end
