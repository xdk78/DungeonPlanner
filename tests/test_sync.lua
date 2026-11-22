-- Group sync for run mode (Share/Sync.lua, UI/RunSync.lua): the wire format, the state machine (leading, following,
-- unfollow and rejoin, a boss kill against a leader's state held in a lockdown, stale and out-of-order sequence numbers,
-- who is trusted, malformed input), matching the leader's plan to a local copy, and two clients talking through the real
-- Comm and outbox.
local T = ...
local ns, mock = T.ns, T.mock
local Sync, Transfer = ns.Sync, ns.Transfer

local LEADER = { inGroup = true, leader = true }
local ASSIST = { inGroup = true, inRaid = true, assist = true }
local MEMBER = { inGroup = true }
local OUTSIDER = { inGroup = false }

local function find(effects, kind)
	for _, e in ipairs(effects) do
		if e[1] == kind then
			return e
		end
	end
	return nil
end

local function count(effects, kind)
	local n = 0
	for _, e in ipairs(effects) do
		if e[1] == kind then
			n = n + 1
		end
	end
	return n
end

local function runMsg(session, seq, step, plan)
	return { type = "run", proto = ns.PROTOCOL_VERSION, session = session, seq = seq, plan = plan or "p1", version = 100,
		step = step, pull = 1 }
end

local OK = { status = "ok", id = "local1" }

local function runEvent(from, rank, msg, match, leadRank)
	return { type = "run", from = from, rank = rank, msg = msg, match = match or OK, leadRank = leadRank }
end

T.case("Sync: wire format round-trips and rejects junk", function()
	local text = Transfer.Encode(runMsg("abc1", 7, 12))
	T.eq(text, "R^2^abc1^7^p1^100^12^1")
	local m = Transfer.Parse(text)
	T.eq(m.type, "run")
	T.eq(m.session, "abc1")
	T.eq(m.seq, 7)
	T.eq(m.plan, "p1")
	T.eq(m.version, 100)
	T.eq(m.step, 12)
	T.eq(m.pull, 1)
	local ended = Transfer.Parse(Transfer.Encode({ type = "run", proto = 2, session = "abc1", seq = 8 }))
	T.eq(ended.plan, nil, "the lead ended")
	T.eq(ended.seq, 8)
	T.eq(Transfer.Parse("R^2^abc1^1^b:hall-of-thanes^5^0^0").plan, "b:hall-of-thanes")
	local f = Transfer.Parse(Transfer.Encode({ type = "follow", proto = 2, session = "abc1", status = "u" }))
	T.eq(f.type, "follow")
	T.eq(f.status, "u")
	T.eq(Transfer.Parse(Transfer.Encode({ type = "query", proto = 2 })).type, "query")
	T.eq(Transfer.Parse(Transfer.Encode({ type = "want", proto = 2, session = "abc1" })).session, "abc1")
	for _, bad in ipairs({
		"R^2^ABC^1^p1^1^1^1", -- session
		"R^2^abc^0^p1^1^1^1", -- seq starts at 1
		"R^2^abc^-3^p1^1^1^1",
		"R^2^abc^1.5^p1^1^1^1",
		"R^2^abc^1^p 1^1^1^1", -- plan id
		"R^2^abc^1^p1^-1^1^1", -- version
		"R^2^abc^1^p1^1^1000^1", -- step
		"R^2^abc^1^p1^1^1^101", -- pull
		"R^2^abc^1^p1^1^1", -- a field missing
		"R^2^abc^1^p1^1^1^1^9", -- one too many
		"R^x^abc^1^p1^1^1^1", -- protocol
		"R^2^abc^99999999999^p1^1^1^1", -- beyond 2^31
		"F^2^abc^z", -- status
		"F^2^abc",
		"Q^2^extra",
		"W^2",
		"W^2^a-b",
	}) do
		T.eq(Transfer.Parse(bad), nil, bad)
	end
end)

T.case("Sync: the leader sends on change only, coalesced and throttled; stop ends the lead", function()
	local s = Sync.New()
	local fx = Sync.Step(s, { type = "lead", rank = MEMBER, session = "s1", plan = "p1", version = 100, step = 1 }, 0)
	T.ok(find(fx, "refused"), "a member cannot lead")
	T.eq(s.mode, "idle")
	T.ok(find(Sync.Step(s, { type = "lead", rank = { inGroup = true, assist = true }, session = "s1", plan = "p1" }, 0),
		"refused"), "an assistant leads only in a raid")
	fx = Sync.Step(s, { type = "lead", rank = LEADER, session = "s1", plan = "p1", version = 100, step = 1, pull = 1 }, 10)
	T.eq(s.mode, "leading")
	local send = find(fx, "send")
	T.eq(send[2].seq, 1)
	T.eq(send[2].step, 1)
	T.eq(send[3], "GROUP")
	-- Within MIN_INTERVAL: one timer, no message; a second change waits for the same timer.
	fx = Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = 2, pull = 1 }, 10.2)
	T.eq(count(fx, "send"), 0)
	T.ok(math.abs(find(fx, "timer")[2] - 0.8) < 1e-9, "the rest of the second")
	fx = Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = 3, pull = 2 }, 10.5)
	T.eq(#fx, 0, "coalesced into the pending send")
	T.eq(#Sync.Step(s, { type = "tick" }, 10.6), 0, "too early")
	fx = Sync.Step(s, { type = "tick" }, 11)
	send = find(fx, "send")
	T.eq(send[2].step, 3, "the newest state")
	T.eq(send[2].pull, 2)
	T.eq(send[2].seq, 2)
	T.eq(#Sync.Step(s, { type = "tick" }, 12), 0, "a stale timer changes nothing")
	-- Nothing changed: nothing sent.
	T.eq(#Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = 3, pull = 2 }, 20), 0)
	-- After a quiet second a change goes out at once; out-of-range numbers are clamped.
	send = find(Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = 5000, pull = -4 }, 30), "send")
	T.eq(send[2].step, Sync.MAX_STEP)
	T.eq(send[2].pull, 0)
	-- A change and back before the timer: nothing.
	Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = 4, pull = 2 }, 30.1)
	Sync.Step(s, { type = "moved", plan = "p1", version = 100, step = Sync.MAX_STEP, pull = 0 }, 30.2)
	T.eq(#Sync.Step(s, { type = "tick" }, 31.1), 0, "back to what the group has")
	-- Stop: the end message, then idle.
	fx = Sync.Step(s, { type = "stop" }, 31)
	send = find(fx, "send")
	T.eq(send[2].plan, nil)
	T.eq(send[2].seq, 4)
	T.eq(s.mode, "idle")
	-- Losing the rank ends the lead too.
	Sync.Step(s, { type = "lead", rank = LEADER, session = "s2", plan = "p1", version = 100, step = 1 }, 40)
	fx = Sync.Step(s, { type = "roster", inGroup = true, self = MEMBER, members = {} }, 41)
	T.eq(s.mode, "idle")
	T.eq(find(fx, "send")[2].plan, nil)
end)

T.case("Sync: a member follows only a trusted leader; stale, repeated and out-of-order states are ignored", function()
	local s = Sync.New()
	T.eq(#Sync.Step(s, runEvent("Bob", MEMBER, runMsg("s1", 1, 3)), 0), 0, "not the leader")
	T.eq(#Sync.Step(s, runEvent("Out", OUTSIDER, runMsg("s1", 1, 3)), 0), 0, "not in the group")
	T.eq(#Sync.Step(s, runEvent("Lead", { inGroup = true, assist = true }, runMsg("s1", 1, 3)), 0), 0,
		"an assistant outside a raid")
	local fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 1, 3)), 0)
	T.eq(s.mode, "following")
	T.eq(find(fx, "focus")[2], "local1")
	T.eq(find(fx, "focus")[3], 3)
	local rep = find(fx, "send")
	T.eq(rep[2].type, "follow")
	T.eq(rep[2].status, "f")
	T.eq(rep[3], "WHISPER")
	T.eq(rep[4], "Lead")
	fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 3, 5), OK, LEADER), 1)
	T.eq(find(fx, "focus")[3], 5)
	T.eq(count(fx, "send"), 0, "no report: nothing changed for the leader")
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 2, 4), OK, LEADER), 2), 0, "out of order")
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 3, 4), OK, LEADER), 2), 0, "repeated seq")
	T.eq(s.lead.step, 5)
	-- A new session (the leader reloaded, or led again) starts its own sequence.
	fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s2", 1, 2), OK, LEADER), 3)
	T.eq(find(fx, "focus")[3], 2)
	T.ok(find(fx, "send"), "reported again for the new session")
	-- Malformed events change nothing.
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, nil, OK, LEADER), 4), 0)
	T.eq(#Sync.Step(s, nil, 4), 0)
	T.eq(#Sync.Step(s, { type = "nonsense" }, 4), 0)
	T.eq(s.mode, "following")
	-- The leader ends the lead; an end from someone else does nothing.
	T.eq(#Sync.Step(s, runEvent("Other", LEADER, { type = "run", session = "x", seq = 9 }, nil, LEADER), 5), 0)
	Sync.Step(s, runEvent("Lead", LEADER, { type = "run", session = "s2", seq = 2 }, nil, LEADER), 5)
	T.eq(s.mode, "idle")
end)

T.case("Sync: unfollow, step freely, rejoin; the group's leader takes over from an assistant", function()
	local s = Sync.New()
	Sync.Step(s, runEvent("Asst", ASSIST, runMsg("a1", 1, 2)), 0)
	T.eq(s.lead.name, "Asst")
	-- Another assistant is ignored while the first is still trusted.
	T.eq(#Sync.Step(s, runEvent("Asst2", ASSIST, runMsg("b1", 1, 9), OK, ASSIST), 1), 0)
	-- The raid's leader takes over.
	Sync.Step(s, runEvent("Boss", { inGroup = true, inRaid = true, leader = true }, runMsg("c1", 1, 4), OK, ASSIST), 2)
	T.eq(s.lead.name, "Boss")
	T.eq(s.applied, 4)
	-- Stepping on one's own: free; the leader's next states do not move the step.
	T.eq(#Sync.Step(s, { type = "localStep", plan = "local1", index = 4 }, 3), 0, "the step we applied")
	local fx = Sync.Step(s, { type = "localStep", plan = "local1", index = 5 }, 3)
	T.eq(s.mode, "free")
	T.eq(find(fx, "send")[2].status, "u")
	fx = Sync.Step(s, runEvent("Boss", LEADER, runMsg("c1", 2, 6), OK, LEADER), 4)
	T.eq(count(fx, "focus"), 0)
	T.eq(s.lead.step, 6)
	-- Rejoin snaps back to the leader's step.
	fx = Sync.Step(s, { type = "rejoin" }, 5)
	T.eq(s.mode, "following")
	T.eq(find(fx, "focus")[3], 6)
	T.eq(find(fx, "send")[2].status, "f")
	-- Unfollow by the button; choosing another plan also counts as stepping away.
	Sync.Step(s, { type = "unfollow" }, 6)
	T.eq(s.mode, "free")
	Sync.Step(s, { type = "rejoin" }, 7)
	Sync.Step(s, { type = "localStep", plan = "other", index = 6 }, 8)
	T.eq(s.mode, "free")
	-- The leader is demoted: nothing to follow.
	Sync.Step(s, { type = "roster", inGroup = true, leadRank = MEMBER }, 9)
	T.eq(s.mode, "idle")
	T.eq(s.lead, nil)
end)

T.case("Sync: a boss kill seen here holds against the leader's older state from the lockdown", function()
	local s = Sync.New()
	Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 1, 5)), 0)
	-- Our tracker saw the kill: run mode moves to 7 (RunMode.OnKill), the step change is not "stepping away".
	local fx = Sync.Step(s, { type = "localKill", plan = "local1", index = 7 }, 100)
	T.eq(find(fx, "timer")[2], Sync.KILL_HOLD)
	T.eq(#Sync.Step(s, { type = "localStep", plan = "local1", index = 7 }, 100), 0)
	T.eq(s.mode, "following")
	-- The leader's state from before the kill comes out of the outbox: held.
	fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 2, 5), OK, LEADER), 101)
	T.eq(count(fx, "focus"), 0, "no pull back to the boss")
	-- Its state after the kill: already there, the hold ends.
	fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 3, 7), OK, LEADER), 102)
	T.eq(count(fx, "focus"), 0)
	T.eq(s.hold, nil)
	-- When the leader really stays behind, its word wins once the hold is over.
	Sync.Step(s, { type = "localKill", plan = "local1", index = 9 }, 200)
	Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 4, 7), OK, LEADER), 201)
	T.eq(#Sync.Step(s, { type = "tick" }, 205), 0, "still holding")
	fx = Sync.Step(s, { type = "tick" }, 200 + Sync.KILL_HOLD)
	T.eq(find(fx, "focus")[3], 7)
	-- A kill on another plan, or while not following, does nothing.
	T.eq(#Sync.Step(s, { type = "localKill", plan = "other", index = 3 }, 300), 0)
end)

T.case("Sync: a missing or other version asks the leader, who offers the plan; the copy then matches", function()
	local s = Sync.New()
	local fx = Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 1, 3), { status = "missing" }), 0)
	T.eq(s.mode, "mismatch")
	T.eq(s.why, "missing")
	T.eq(find(fx, "send")[2].status, "m")
	T.eq(count(fx, "focus"), 0)
	fx = Sync.Step(s, { type = "request" }, 1)
	local want = find(fx, "send")
	T.eq(want[2].type, "want")
	T.eq(want[4], "Lead")
	T.eq(#Sync.Step(s, { type = "request" }, 5), 0, "asked recently")
	-- The leader's side: one offer per member per minute, only for its session.
	local l = Sync.New()
	Sync.Step(l, { type = "lead", rank = LEADER, session = "s1", plan = "p1", version = 100, step = 3 }, 0)
	T.eq(#Sync.Step(l, { type = "want", from = "Mem", rank = MEMBER, session = "zz" }, 1), 0, "another session")
	T.eq(#Sync.Step(l, { type = "want", from = "Out", rank = OUTSIDER, session = "s1" }, 1), 0, "not in the group")
	local offer = find(Sync.Step(l, { type = "want", from = "Mem", rank = MEMBER, session = "s1" }, 1), "offer")
	T.eq(offer[2], "Mem")
	T.eq(offer[3], "p1")
	T.eq(#Sync.Step(l, { type = "want", from = "Mem", rank = MEMBER, session = "s1" }, 30), 0)
	-- The plan arrived and matches: following.
	fx = Sync.Step(s, { type = "resolve", match = OK }, 40)
	T.eq(s.mode, "following")
	T.eq(find(fx, "focus")[3], 3)
	T.eq(find(fx, "send")[2].status, "f")
	-- Edited here afterwards: another version.
	Sync.Step(s, { type = "resolve", match = { status = "version" } }, 50)
	T.eq(s.why, "version")
end)

T.case("Sync: the leader's view of who follows; answers to who leads are rate-limited", function()
	local l = Sync.New()
	Sync.Step(l, { type = "lead", rank = LEADER, session = "s1", plan = "p1", version = 100, step = 1 }, 0)
	T.eq(#Sync.Step(l, { type = "report", from = "Anna", rank = MEMBER, session = "old", status = "f" }, 1), 0)
	T.eq(#Sync.Step(l, { type = "report", from = "Anna", rank = MEMBER, session = "s1", status = "q" }, 1), 0)
	T.eq(#Sync.Step(l, { type = "report", from = "Out", rank = OUTSIDER, session = "s1", status = "f" }, 1), 0)
	Sync.Step(l, { type = "report", from = "Anna", rank = MEMBER, session = "s1", status = "f" }, 1)
	Sync.Step(l, { type = "report", from = "Bram", rank = MEMBER, session = "s1", status = "u" }, 1)
	Sync.Step(l, { type = "report", from = "Cara", rank = MEMBER, session = "s1", status = "m" }, 1)
	local sum = Sync.Summary(l, { "Anna", "Bram", "Cara", "Dov", "Eli" }, { { name = "Dov", state = "outdated" } })
	T.eq(sum.total, 5)
	T.eq(sum.following, 1)
	T.eq(sum.free, 1)
	T.eq(sum.outOfSync, 2, "Cara has no plan; Dov's ack is for an older version")
	T.eq(sum.unknown, 1, "Eli never answered")
	-- Cara left the group: pruned.
	Sync.Step(l, { type = "roster", inGroup = true, self = LEADER, members = { "Anna", "Bram" } }, 2)
	T.eq(l.followers.Cara, nil)
	-- Who leads? One asker within ANSWER_DELAY: the state, whispered; at most every ANSWER_INTERVAL per member.
	local fx = Sync.Step(l, { type = "query", from = "Fay", rank = MEMBER }, 3)
	T.eq(find(fx, "timer")[2], Sync.ANSWER_DELAY)
	T.eq(count(fx, "send"), 0, "waits for more questions")
	T.eq(#Sync.Step(l, { type = "query", from = "Fay", rank = MEMBER }, 3.5), 0)
	T.eq(#Sync.Step(l, { type = "query", from = "Out", rank = OUTSIDER }, 3.5), 0)
	local send = find(Sync.Step(l, { type = "tick" }, 4), "send")
	T.eq(send[3], "WHISPER")
	T.eq(send[4], "Fay")
	T.eq(send[2].plan, "p1")
	-- A raid's burst: several askers within the second get one group message, not a whisper each.
	for i = 1, 6 do
		Sync.Step(l, { type = "query", from = "R" .. i, rank = MEMBER }, 6 + i / 10)
	end
	fx = Sync.Step(l, { type = "tick" }, 7.1)
	T.eq(count(fx, "send"), 1)
	T.eq(find(fx, "send")[3], "GROUP")
	T.eq(#Sync.Step(l, { type = "tick" }, 8), 0, "answered")
	-- Bounded.
	for i = 1, Sync.MAX_FOLLOWERS + 5 do
		Sync.Step(l, { type = "report", from = "M" .. i, rank = MEMBER, session = "s1", status = "f" }, 10 + i)
	end
	local n = 0
	for _ in pairs(l.followers) do
		n = n + 1
	end
	T.ok(n <= Sync.MAX_FOLLOWERS)
	-- A member asks the group who leads once per QUERY_INTERVAL, only in a group, after its random wait.
	local m = Sync.New()
	T.eq(#Sync.Step(m, { type = "show", inGroup = false }, 0), 0)
	fx = Sync.Step(m, { type = "show", inGroup = true, jitter = 1.5 }, 0)
	T.eq(find(fx, "timer")[2], 1.5)
	T.eq(count(fx, "send"), 0)
	T.eq(#Sync.Step(m, { type = "tick" }, 1), 0, "still waiting")
	T.eq(find(Sync.Step(m, { type = "tick" }, 1.5), "send")[2].type, "query")
	T.eq(#Sync.Step(m, { type = "tick" }, 2), 0, "asked once")
	T.eq(#Sync.Step(m, { type = "show", inGroup = true, jitter = 9 }, 10), 0)
	T.eq(find(Sync.Step(m, { type = "roster", inGroup = true, shown = true, jitter = 9 }, 40), "timer")[2],
		Sync.QUERY_JITTER, "the wait is capped")
	-- A lead heard while waiting: the question is not asked.
	Sync.Step(m, runEvent("Lead", LEADER, runMsg("s9", 1, 2)), 41)
	T.eq(count(Sync.Step(m, { type = "tick" }, 43), "send"), 0)
end)

T.case("Sync: the leader's plan is matched to a local plan, a received copy, or neither", function()
	-- sig stands in for each plan's steps revision.
	local plans = {
		["b:hall"] = { id = "b:hall", sig = 500 },
		copy1 = { id = "copy1", sig = 700 },
		copy2 = { id = "copy2", sig = 800 },
		newer = { id = "newer", sig = 800 },
	}
	local function get(id)
		return plans[id]
	end
	local function sigOf(p)
		return p.sig
	end
	local links = {
		copy1 = { plan = "pLead", at = 1 },
		copy2 = { plan = "pLead", at = 2 },
		newer = { plan = "pLead", at = 3 },
		gone = { plan = "pLead", at = 4 }, -- deleted since
	}
	T.eq(Sync.Resolve("b:hall", 500, get, links, sigOf).id, "b:hall", "a recommended plan by its id")
	T.eq(Sync.Resolve("b:hall", 400, get, links, sigOf).status, "version", "its steps differ")
	T.eq(Sync.Resolve("pLead", 800, get, links, sigOf).id, "newer", "the newest copy with those steps")
	T.eq(Sync.Resolve("pLead", 700, get, links, sigOf).id, "copy1")
	T.eq(Sync.Resolve("pLead", 999, get, links, sigOf).status, "version")
	T.eq(Sync.Resolve("pNone", 1, get, links, sigOf).status, "missing")
	T.eq(Sync.Resolve("pNone", 1, get, nil, sigOf).status, "missing")
	-- The steps revision: the steps' kinds and what they are, in order; nothing else.
	local a = { { kind = "pull", pull = "u1" }, { kind = "boss", encounter = "e1" } }
	local b = { { kind = "pull", pull = "u1", note = "changed", x = 0.5 }, { kind = "boss", encounter = "e1" } }
	T.eq(Sync.Signature(a), Sync.Signature(b), "notes and spots do not change it")
	T.ok(Sync.Signature(a) ~= Sync.Signature({ a[2], a[1] }), "the order does")
	T.ok(Sync.Signature(a) ~= Sync.Signature({ a[1], a[2], { kind = "pull", pull = "u2" } }), "a new step does")
	-- The link store: bounded, repaired.
	local store = ns.Acks.NormalizeLinks({ a1 = { plan = "p1", at = 2 }, ["bad id"] = {}, b1 = { plan = "p 1" } })
	T.eq(ns.Util.Count(store), 1)
	for i = 1, ns.Acks.MAX_LINKS + 3 do
		ns.Acks.Link(store, "c" .. i, "p1", i)
	end
	T.eq(ns.Util.Count(store), ns.Acks.MAX_LINKS)
	T.eq(ns.Acks.Link(store, "x1", "bad id", 1), false)
end)

-- Two clients through the real Comm, AceComm and outbox: this client runs UI/RunSync.lua, the other side runs the same
-- state machine on its own (its messages encoded and parsed with the real wire format).
local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function withGroup(leaderUnit, fn)
	local leaderFn, assistFn = _G.UnitIsGroupLeader, _G.UnitIsGroupAssistant
	_G.UnitIsGroupLeader = function(unit)
		return unit == leaderUnit
	end
	_G.UnitIsGroupAssistant = function()
		return false
	end
	mock.inGroup = true
	mock.units = { party1 = { name = "Lead" }, party2 = { name = "Mem" } }
	local outgoing = {}
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, _, text, channel, target)
		outgoing[#outgoing + 1] = { text = text, channel = channel, target = target }
	end
	local ok, err = pcall(fn, outgoing)
	ns.addon.SendCommMessage = realSend
	_G.UnitIsGroupLeader, _G.UnitIsGroupAssistant = leaderFn, assistFn
	mock.inGroup, mock.units, mock.lockdown = false, {}, false
	ns.RunSync.state = Sync.New()
	if ns.RunMode.IsShown() then
		ns.RunMode.Hide()
	end
	assert(ok, err)
end

-- Messages this client sent, parsed, and the list emptied.
local function drain(outgoing)
	local out = {}
	for _, m in ipairs(outgoing) do
		local msg = Transfer.Parse(m.text)
		if msg and (msg.type == "run" or msg.type == "follow" or msg.type == "query" or msg.type == "want") then
			out[#out + 1] = { msg = msg, channel = m.channel, target = m.target }
		end
	end
	for i = #outgoing, 1, -1 do
		outgoing[i] = nil
	end
	return out
end

T.case("Sync, two clients: a member follows the leader's run mode, unfollows, rejoins; an outsider is ignored", function()
	boot()
	withGroup("party1", function(outgoing)
		local plan = ns.DB.GetPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		T.ok(plan, "the recommended plan is here")
		local sig = ns.RunSync.Signature(plan)
		ns.UI.SelectPlan(plan.id, true)
		ns.UI.FocusStep(1, { stay = true })
		ns.RunMode.Show()
		drain(outgoing) -- the "who leads?" question run mode asked on opening
		-- The remote leader starts on step 4 of the same plan.
		local leader = Sync.New()
		local now = 1000
		local function deliver(effects)
			for _, e in ipairs(effects) do
				if e[1] == "send" then
					ns.Comm.OnMessage(ns.prefix, Transfer.Encode(e[2]), e[3] == "GROUP" and "PARTY" or e[3], "Lead")
				end
			end
		end
		deliver(Sync.Step(leader, { type = "lead", rank = LEADER, session = "ld1", plan = plan.id,
			version = sig, step = 4, pull = 2 }, now))
		T.eq(ns.RunSync.state.mode, "following")
		T.eq(ns.UI.ctx:StepIndex(), 4, "run mode shows the leader's step")
		-- The member's report reaches the leader.
		local sent = drain(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.type, "follow")
		T.eq(sent[1].target, "Lead")
		Sync.Step(leader, { type = "report", from = "Tester", rank = MEMBER, session = sent[1].msg.session,
			status = sent[1].msg.status }, now)
		T.eq(leader.followers.Tester.status, "following")
		-- The leader moves on.
		deliver(Sync.Step(leader, { type = "moved", plan = plan.id, version = sig, step = 6, pull = 3 }, now + 5))
		T.eq(ns.UI.ctx:StepIndex(), 6)
		T.eq(#drain(outgoing), 0, "nothing to report")
		-- The player presses Next: stepping on their own.
		ns.RunMode.Step(1)
		T.eq(ns.RunSync.state.mode, "free")
		T.eq(ns.UI.ctx:StepIndex(), 7)
		sent = drain(outgoing)
		T.eq(sent[1].msg.status, "u")
		deliver(Sync.Step(leader, { type = "moved", plan = plan.id, version = sig, step = 8, pull = 4 }, now + 10))
		T.eq(ns.UI.ctx:StepIndex(), 7, "free: the leader's step does not move it")
		-- Rejoin.
		ns.RunSync.Act("rejoin")
		T.eq(ns.UI.ctx:StepIndex(), 8)
		-- Someone who is not the leader, and someone not in the group, cannot drive it.
		ns.Comm.OnMessage(ns.prefix, "R^2^zz1^1^" .. plan.id .. "^" .. sig .. "^2^1", "PARTY", "Mem")
		ns.Comm.OnMessage(ns.prefix, "R^2^zz2^1^" .. plan.id .. "^" .. sig .. "^2^1", "WHISPER", "Stranger")
		T.eq(ns.UI.ctx:StepIndex(), 8)
		T.eq(ns.RunSync.state.lead.name, "Lead")
		-- An older Dungeon Planner's unknown tag and junk are ignored without an error.
		ns.Comm.OnMessage(ns.prefix, "R^2^bad", "PARTY", "Lead")
		ns.Comm.OnMessage(ns.prefix, "Z^2^whatever", "PARTY", "Lead")
		T.eq(ns.UI.ctx:StepIndex(), 8)
		-- The leader stops.
		deliver(Sync.Step(leader, { type = "stop" }, now + 20))
		T.eq(ns.RunSync.state.mode, "idle")
		-- A plan this client does not have: the request goes to the leader, who offers it.
		deliver(Sync.Step(leader, { type = "lead", rank = LEADER, session = "ld2", plan = "pNotHere", version = 1, step = 1 }, now + 30))
		T.eq(ns.RunSync.state.mode, "mismatch")
		T.eq(ns.RunSync.LineState(ns.UI.ctx:Plan()).action, "ask")
		drain(outgoing)
		ns.RunSync.Act("ask")
		sent = drain(outgoing)
		T.eq(sent[1].msg.type, "want")
		T.eq(sent[1].target, "Lead")
		local fx = Sync.Step(leader, { type = "want", from = "Tester", rank = MEMBER, session = sent[1].msg.session }, now + 31)
		T.eq(find(fx, "offer")[2], "Tester")
		-- The leader's own plan, sent and imported here: the copy is linked to the leader's id and version, and followed.
		local theirs = ns.DB.AddPlan(ns.Validate.Plan({ name = "Their route", instance = { name = "Test Keep", kind = "dungeon" },
			pulls = { { id = "u1", name = "First" }, { id = "u2", name = "Second" } } }))
		local theirSig = ns.RunSync.Signature(theirs)
		local data = ns.Codec.ExportPlan(theirs)
		ns.DB.DeletePlan(theirs.id) -- the leader's, not here
		deliver(Sync.Step(leader, { type = "lead", rank = LEADER, session = "ld3", plan = theirs.id, version = theirSig, step = 2,
			pull = 2 }, now + 40))
		T.eq(ns.RunSync.state.mode, "mismatch")
		T.ok(ns.DB.ImportString(data, { from = "Lead", kind = "received" }))
		T.eq(ns.RunSync.state.mode, "following", "the received copy matches")
		local copy = ns.UI.ctx:Plan()
		T.eq(ns.db.shareLinks[copy.id].plan, theirs.id)
		T.eq(ns.UI.ctx:StepIndex(), 2, "on the leader's step of the copy")
		ns.DB.DeletePlan(copy.id)
		T.eq(ns.RunSync.state.mode, "mismatch", "deleted: missing again")
	end)
end)

T.case("Sync, two clients: the leader's states wait out a lockdown as one message; a member's kill is not undone", function()
	boot()
	withGroup("player", function(outgoing)
		local plan = ns.DB.GetPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		ns.UI.SelectPlan(plan.id, true)
		ns.UI.FocusStep(2, { stay = true })
		ns.RunMode.Show()
		drain(outgoing)
		T.eq(ns.RunSync.LineState(plan).action, "lead", "the group's leader may lead")
		ns.RunSync.Act("lead")
		local sent = drain(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.type, "run")
		T.eq(sent[1].msg.step, 2)
		T.eq(sent[1].channel, ns.Comm.GroupChannel(), "to the group")
		-- The remote member has the same recommended plan and follows.
		local member = Sync.New()
		local function get(id)
			return id == plan.id and plan or nil
		end
		local function toMember(list, t)
			local fx = {}
			for _, m in ipairs(list) do
				local match = m.msg.plan and Sync.Resolve(m.msg.plan, m.msg.version, get, {}, ns.RunSync.Signature) or nil
				for _, e in ipairs(Sync.Step(member, runEvent("Tester", LEADER, m.msg, match, LEADER), t)) do
					fx[#fx + 1] = e
				end
			end
			return fx
		end
		local fx = toMember(sent, 0)
		T.eq(member.mode, "following")
		T.eq(member.applied, 2)
		-- Its report back, through Comm.
		ns.Comm.OnMessage(ns.prefix, Transfer.Encode(find(fx, "send")[2]), "WHISPER", "Mem")
		T.eq(ns.RunSync.Summary(plan).following, 1)
		-- A boss fight: the game holds addon messages. The leader steps three times; only the newest leaves, after it.
		mock.lockdown = true
		mock.Advance(2)
		ns.UI.FocusStep(3, { stay = true })
		mock.Advance(2)
		ns.UI.FocusStep(4, { stay = true })
		mock.Advance(2)
		ns.UI.FocusStep(5, { stay = true })
		mock.Advance(2)
		T.eq(#drain(outgoing), 0, "nothing during the lockdown")
		T.eq(#ns.Comm.outbox, 1, "one waiting message: the newest replaced the older ones")
		-- Meanwhile the member's tracker saw the kill and moved to 6.
		Sync.Step(member, { type = "localKill", plan = plan.id, index = 6 }, 5)
		mock.lockdown = false
		mock.Advance(1)
		sent = drain(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.step, 5)
		fx = toMember(sent, 6)
		T.eq(count(fx, "focus"), 0, "the older step does not pull the member back")
		T.eq(member.applied, 6)
		-- The leader's own kill brings it to 6 too: in sync, nothing to undo.
		ns.UI.FocusStep(6, { stay = true })
		mock.Advance(2)
		fx = toMember(drain(outgoing), 7)
		T.eq(count(fx, "focus"), 0)
		T.eq(member.hold, nil)
		-- The Share section's line counts who follows.
		T.eq(ns.RunSync.Summary(plan).total, 2)
		-- Promoted away: the lead ends with a last message.
		_G.UnitIsGroupLeader = function(unit)
			return unit == "party1"
		end
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		T.eq(ns.RunSync.state.mode, "idle")
		sent = drain(outgoing)
		T.eq(sent[#sent].msg.plan, nil, "the end of the lead")
	end)
end)

T.case("Sync: saved data moves to schema 5 with the link store; data from a newer schema stays read-only", function()
	local DB = ns.DB
	T.eq(DB.SCHEMA, 5)
	-- Schema 4 (0.1.0): no store yet; the migration starts it and the plans load as before.
	local global = { schema = 4, plans = { p1 = { id = "p1", name = "Old" } } }
	local info = DB.LoadGlobal(global)
	T.eq(global.schema, 5)
	T.eq(info.migratedFrom, 4)
	T.eq(type(global.shareLinks), "table")
	T.eq(ns.Util.Count(global.shareLinks), 0)
	T.eq(global.plans.p1.name, "Old")
	-- A store already there (written by a pre-release build) is repaired, not dropped.
	global = { schema = 4, plans = {}, shareLinks = { c1 = { plan = "p9", at = 1 }, ["bad id"] = { plan = "p9" } } }
	DB.LoadGlobal(global)
	T.eq(global.shareLinks.c1.plan, "p9")
	T.eq(global.shareLinks["bad id"], nil)
	-- Saved by a newer version: read-only, the links untouched.
	local links = { c1 = { plan = "p9", at = 1 } }
	local newer = { schema = DB.SCHEMA + 1, plans = {}, shareLinks = links }
	T.ok(DB.LoadGlobal(newer).readOnly)
	T.eq(newer.shareLinks, links)
end)

T.case("Sync: a plan received in game is linked to its sender's plan, a pasted one is not; deleting drops the link", function()
	boot()
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Linked", instance = { name = "Test Keep", kind = "dungeon" },
		pulls = { { id = "u1", name = "One" } } }))
	local data = ns.Codec.ExportPlan(plan)
	local ok, _, added = ns.DB.ImportString(data, { from = "Lead", kind = "received" })
	T.ok(ok)
	local copy = added[1]
	T.eq(ns.db.shareLinks[copy.id].plan, plan.id)
	local function others(id)
		return id ~= plan.id and ns.DB.GetPlan(id) or nil
	end
	T.eq(Sync.Resolve(plan.id, ns.RunSync.Signature(plan), others, ns.db.shareLinks, ns.RunSync.Signature).id, copy.id)
	local _, _, pasted = ns.DB.ImportString(data, { kind = "import" })
	T.eq(ns.db.shareLinks[pasted[1].id], nil, "a pasted string makes no link")
	ns.DB.DeletePlan(copy.id)
	T.eq(ns.db.shareLinks[copy.id], nil)
	ns.DB.DeletePlan(pasted[1].id)
	ns.DB.DeletePlan(plan.id)
end)

T.case("Sync: an end held in an outbox does not end a newer lead; an ended session stays ended", function()
	local s = Sync.New()
	Sync.Step(s, runEvent("Lead", LEADER, runMsg("s1", 1, 2)), 0)
	-- The leader stopped s1 in a fight and led again as s2; s2's state arrives before s1's end.
	Sync.Step(s, runEvent("Lead", LEADER, runMsg("s2", 1, 3), OK, LEADER), 1)
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, { type = "run", session = "s1", seq = 9 }, nil, LEADER), 2), 0)
	T.eq(s.mode, "following")
	T.eq(s.lead.session, "s2")
	-- s2 ends: nothing more of s2 counts, whatever its number.
	Sync.Step(s, runEvent("Lead", LEADER, { type = "run", session = "s2", seq = 2 }, nil, LEADER), 3)
	T.eq(s.mode, "idle")
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, runMsg("s2", 50, 4), OK, LEADER), 4), 0)
	T.eq(s.mode, "idle")
	Sync.Step(s, runEvent("Lead", LEADER, runMsg("s3", 1, 4), OK, LEADER), 5)
	T.eq(s.mode, "following", "a new lead is taken")
	-- s3 ends too; a delayed state of s2 (two leads back) still cannot bring it back.
	Sync.Step(s, runEvent("Lead", LEADER, { type = "run", session = "s3", seq = 2 }, nil, LEADER), 6)
	T.eq(#Sync.Step(s, runEvent("Lead", LEADER, runMsg("s2", 60, 5), OK, LEADER), 7), 0)
	T.eq(s.mode, "idle")
	-- Bounded.
	for i = 1, Sync.MAX_ENDED + 3 do
		Sync.Step(s, runEvent("Lead", LEADER, runMsg("e" .. i, 1, 1), OK, LEADER), 10 + i)
		Sync.Step(s, runEvent("Lead", LEADER, { type = "run", session = "e" .. i, seq = 2 }, nil, LEADER), 10 + i)
	end
	T.eq(#s.ended, Sync.MAX_ENDED)
end)

T.case("Sync, Comm: after a lockdown, what waited goes before anything newer (R and F keep their order)", function()
	boot()
	withGroup("player", function(outgoing)
		local plan = ns.DB.GetPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		ns.UI.SelectPlan(plan.id, true)
		ns.UI.FocusStep(2, { stay = true })
		ns.RunMode.Show()
		drain(outgoing)
		ns.RunSync.Act("lead")
		local member = Sync.New()
		local function toMember(list)
			for _, m in ipairs(list) do
				local match = m.msg.plan and Sync.Resolve(m.msg.plan, m.msg.version, ns.DB.GetPlan, {}, ns.RunSync.Signature)
				Sync.Step(member, runEvent("Tester", LEADER, m.msg, match, LEADER), 0)
			end
		end
		toMember(drain(outgoing))
		T.eq(member.mode, "following")
		-- Stop in a fight: the end waits. The fight ends, and the leader leads again before the next tick.
		mock.lockdown = true
		ns.RunSync.Act("stop")
		T.eq(#outgoing, 0)
		mock.lockdown = false
		ns.RunSync.Act("lead")
		local sent = drain(outgoing)
		T.eq(#sent, 2, "the waiting end, then the new lead")
		T.eq(sent[1].msg.plan, nil)
		T.eq(sent[2].msg.plan, plan.id)
		toMember(sent)
		mock.Advance(1)
		toMember(drain(outgoing))
		T.eq(member.mode, "following", "the new lead is followed")
	end)
	-- The member side: a status that waited ("u") goes before the newer one ("f"), so the leader ends with "f".
	withGroup("party1", function(outgoing)
		local plan = ns.DB.GetPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		ns.UI.SelectPlan(plan.id, true)
		ns.RunMode.Show()
		local sig = ns.RunSync.Signature(plan)
		ns.Comm.OnMessage(ns.prefix, "R^2^ld9^1^" .. plan.id .. "^" .. sig .. "^3^1", "PARTY", "Lead")
		drain(outgoing)
		mock.lockdown = true
		ns.RunSync.Act("unfollow")
		mock.lockdown = false
		ns.RunSync.Act("rejoin")
		local sent = drain(outgoing)
		T.eq(#sent, 2)
		T.eq(sent[1].msg.status, "u")
		T.eq(sent[2].msg.status, "f", "the newest last")
	end)
end)

T.case("Sync: a leader's edits that leave the steps as they were keep followers; new steps make another version", function()
	boot()
	local own = ns.DB.AddPlan(ns.Validate.Plan({ name = "Edited", instance = { name = "Test Keep", kind = "dungeon" },
		pulls = { { id = "u1", name = "One", note = "" }, { id = "u2", name = "Two" } } }))
	local sig = ns.RunSync.Signature(own)
	ns.Plan.UpdatePull(own, "u1", { note = "Wait for the patrol" })
	ns.DB.Changed(own, "pull")
	T.ok(own.updated ~= nil)
	T.eq(ns.RunSync.Signature(own), sig, "a note: same steps, the followers stay")
	ns.Plan.AddPull(own, "Three")
	ns.DB.Changed(own, "pull")
	T.ok(ns.RunSync.Signature(own) ~= sig, "a new pull: another version")
	ns.DB.DeletePlan(own.id)
end)
