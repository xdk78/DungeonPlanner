-- Who a message came from and where replies go (Share/Roster.lua), and Comm's outbox: a sender is matched by its whole
-- name (surnames on Forever, realms elsewhere), messages only on their own channels, whisper targets as names arrived,
-- the outbox bound, and acks for a plan whispered to a typed first name.
local T = ...
local ns, mock = T.ns, T.mock
local Sync, Transfer = ns.Sync, ns.Transfer

local LEADER = { inGroup = true, leader = true }

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("Sync, Roster: a sender is matched by its whole name; a namesake from elsewhere gets no rank", function()
	boot()
	local realName, realLeader = _G.UnitName, _G.UnitIsGroupLeader
	local realm = mock.realm
	mock.inGroup = true
	_G.UnitIsGroupLeader = function(unit)
		return unit == "party1"
	end
	-- Named realms (as elsewhere): the leader "Lead" on our realm, a "Lead" from another realm in the group too.
	mock.realm = "Home Realm"
	mock.units = { party1 = { name = "Lead" }, party2 = { name = "Lead", realm = "Other Realm" } }
	_G.UnitName = function(unit)
		if unit == "player" then
			return "Tester"
		end
		local u = mock.units[unit]
		return u and u.name, u and u.realm
	end
	local R = ns.Roster
	T.eq(R.Id("Lead-HomeRealm"), "Lead", "our realm is left off")
	T.eq(R.Id("Lead-OtherRealm"), "Lead-OtherRealm")
	T.eq(R.UnitId("party2"), "Lead-OtherRealm")
	T.ok(ns.Comm.GroupRank(R.Id("Lead-HomeRealm")).leader, "the leader")
	T.eq(ns.Comm.GroupRank(R.Id("Lead-OtherRealm")).leader, false, "the namesake is not the leader")
	T.eq(ns.Comm.GroupRank(R.Id("Lead-OtherRealm")).inGroup, true)
	T.eq(R.UnitId("party2"), R.Id("Lead-Other Realm"), "realm spaces and hyphens normalised on both sides")
	-- A same-realm stranger "Bob" is not the member "Bob-OtherRealm", whatever the client would resolve a bare name to.
	mock.units.party3 = { name = "Bob", realm = "Other Realm" }
	local realIsUnit = _G.UnitIsUnit
	_G.UnitIsUnit = function()
		return true
	end
	T.eq(ns.Comm.GroupRank(R.Id("Bob")).inGroup, false, "a stranger named Bob")
	T.eq(ns.Comm.GroupRank(R.Id("Bob-OtherRealm")).inGroup, true)
	_G.UnitIsUnit = realIsUnit
	mock.units.party3 = nil
	-- A reply goes to the name as it arrived: heard only from group members, least recently heard out first.
	ns.Comm.OnMessage(ns.prefix, "H^2^1.0", "PARTY", "Lead-HomeRealm")
	T.eq(R.WhisperTarget("Lead"), "Lead-HomeRealm")
	ns.Comm.OnMessage(ns.prefix, "H^2^1.0", "WHISPER", "Stranger-HomeRealm")
	T.eq(R.WhisperTarget("Stranger"), "Stranger", "not a member: not recorded")
	for i = 1, R.MAX_HEARD do
		R.Heard("M" .. i, "M" .. i .. "-X")
	end
	T.eq(R.WhisperTarget("Lead"), "Lead", "the least recently heard went")
	T.eq(R.WhisperTarget("M1"), "M1-X")
	R.Heard("M1", "M1-X") -- heard again: now the newest
	R.Heard("N1", "N1-X")
	T.eq(R.WhisperTarget("M1"), "M1-X", "kept")
	T.eq(R.WhisperTarget("M2"), "M2", "M2 was the oldest")
	-- WoW: Forever: surnames. UnitName's second return is the surname; senders read "First Surname".
	mock.realm = ""
	mock.units = { party1 = { name = "Ana", realm = "Smith" }, party2 = { name = "Ana", realm = "Jones" } }
	_G.UnitName = function(unit)
		if unit == "player" then
			return "Tess", "Tester"
		end
		local u = mock.units[unit]
		return u and u.name, u and u.realm
	end
	T.ok(R.Surnames())
	T.eq(R.Me(), "Tess Tester")
	T.eq(R.Id("Ana Smith"), "Ana Smith")
	T.eq(R.Id("Ana Smith-"), "Ana Smith", "an empty realm suffix is left off")
	T.eq(R.Id("Ana Smith-X"), "Ana Smith-X", "a realm suffix is kept")
	T.ok(ns.Comm.GroupRank("Ana Smith").leader)
	T.eq(ns.Comm.GroupRank(R.Id("Ana Smith-X")).inGroup, false, "Ana Smith from realm X is not the member Ana Smith")
	T.eq(ns.Comm.GroupRank("Ana Jones").leader, false, "same first name, another player")
	T.eq(ns.Comm.GroupRank("Ana").inGroup, false, "a first name alone is nobody")
	-- Two units the client cannot tell apart: untrusted.
	mock.units.party2 = { name = "Ana", realm = "Smith" }
	T.eq(ns.Comm.GroupRank("Ana Smith").inGroup, false)
	-- Through Comm: a run state from the namesake, or from realm X, is not followed.
	mock.units.party2 = { name = "Ana", realm = "Jones" }
	local outgoing = {}
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, _, text, channel, target)
		outgoing[#outgoing + 1] = { text = text, channel = channel, target = target }
	end
	local plan = ns.DB.GetPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
	ns.UI.SelectPlan(plan.id, true)
	ns.RunMode.Show()
	local msg = "R^2^nm1^1^" .. plan.id .. "^" .. ns.RunSync.Signature(plan) .. "^3^1"
	ns.Comm.OnMessage(ns.prefix, msg, "PARTY", "Ana Jones")
	T.eq(ns.RunSync.state.mode, "idle", "not the leader")
	ns.Comm.OnMessage(ns.prefix, msg, "PARTY", "Ana Smith-X")
	T.eq(ns.RunSync.state.mode, "idle", "another realm's Ana Smith")
	-- The right sender on the wrong channel: dropped.
	ns.Comm.OnMessage(ns.prefix, msg, "GUILD", "Ana Smith")
	T.eq(ns.RunSync.state.mode, "idle", "R in guild chat")
	ns.Comm.OnMessage(ns.prefix, msg, "PARTY", "Ana Smith")
	T.eq(ns.RunSync.state.mode, "following")
	T.eq(ns.RunSync.state.lead.name, "Ana Smith")
	local report
	for _, m in ipairs(outgoing) do
		if m.text:sub(1, 2) == "F^" then
			report = m
		end
	end
	T.eq(report.target, "Ana Smith", "whispered to the name it came from")
	-- As the leader: F and W only as whispers, Q only from the group.
	local s = Sync.New()
	ns.RunSync.state = s
	Sync.Step(s, { type = "lead", rank = LEADER, session = "ch1", plan = plan.id, version = 1, step = 1 }, 0)
	ns.Comm.OnMessage(ns.prefix, "F^2^ch1^f", "PARTY", "Ana Jones")
	T.eq(s.followers["Ana Jones"], nil, "F to the party: dropped")
	ns.Comm.OnMessage(ns.prefix, "F^2^ch1^f", "WHISPER", "Ana Jones")
	T.eq(s.followers["Ana Jones"].status, "following")
	ns.Comm.OnMessage(ns.prefix, "Q^2", "WHISPER", "Ana Jones")
	T.eq(next(s.askers), nil, "Q whispered: dropped")
	ns.Comm.OnMessage(ns.prefix, "Q^2", "PARTY", "Ana Jones")
	T.ok(s.askers["Ana Jones"])
	ns.addon.SendCommMessage = realSend
	ns.RunMode.Hide()
	ns.RunSync.state = Sync.New()
	ns.Comm.peers.Lead = nil
	_G.UnitName, _G.UnitIsGroupLeader, mock.realm = realName, realLeader, realm
	mock.inGroup, mock.units = false, {}
end)

T.case("Comm: the outbox is bounded; acks and hellos go first; a transfer is aborted, never cut", function()
	boot()
	local Comm = ns.Comm
	local realMax, realSend = Comm.MAX_OUTBOX, ns.addon.SendCommMessage
	local sent = {}
	ns.addon.SendCommMessage = function(_, _, text)
		sent[#sent + 1] = text
	end
	Comm.MAX_OUTBOX = 4
	mock.inGroup = true
	mock.units = { party1 = { name = "Anna" } }
	mock.lockdown = true
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Boxed", instance = { name = "Test Keep", kind = "dungeon" } }))
	local data = ns.Codec.ExportPlan(plan)
	local function ack(i)
		return Comm.SendAck({ kind = "plan", sender = "Anna", tid = "ob" .. i }, data)
	end
	ack(1)
	ack(2)
	local t1 = assert(Comm.SharePlan(plan, "GROUP")) -- its offer waits
	ack(3)
	T.eq(#Comm.outbox, 4)
	-- Full: the oldest ack goes for a new one.
	ack(4)
	T.eq(#Comm.outbox, 4)
	T.eq(Transfer.Parse(Comm.outbox[1][1]).tid, "ob2", "ack 1 dropped")
	-- Three more transfers take the acks' room; then nothing can go: the newest transfer is aborted, the others kept.
	local t2 = assert(Comm.SharePlan(plan, "GROUP"))
	local t3 = assert(Comm.SharePlan(plan, "GROUP"))
	local t4 = assert(Comm.SharePlan(plan, "GROUP")) -- the last ack makes room
	local t5 = Comm.SharePlan(plan, "GROUP")
	T.eq(t5.state, "failed", "no room: aborted")
	T.eq(t5.reason, "outbox")
	T.eq(t1.state, "offering")
	T.eq(t2.state, "offering")
	T.eq(t3.state, "offering")
	T.eq(t4.state, "offering")
	for _, item in ipairs(Comm.outbox) do
		T.ok(item.transfer ~= t5, "nothing of the aborted transfer waits")
		T.ok(item.kind ~= "ack", "every ack made room")
	end
	-- A raid page with no room: not sent, and the sender is told so (the page waits on nobody).
	local leaderFn = _G.UnitIsGroupLeader
	_G.UnitIsGroupLeader = function(unit)
		return unit == "player"
	end
	local ok, err = Comm.SendPage({ title = "Pull", text = "go" })
	T.eq(ok, nil)
	T.ok(err:find("not sent", 1, true), tostring(err))
	_G.UnitIsGroupLeader = leaderFn
	-- The player cancels t1 while nothing can be queued: it stays "cancelled", not "failed".
	Comm.Cancel(t1)
	T.eq(t1.state, "cancelled")
	T.eq(t1.reason, nil)
	-- Keyed messages replace each other and do not count.
	Comm.SendSync("Q^2", "PARTY", nil, "query:")
	Comm.SendSync("Q^2", "PARTY", nil, "query:")
	T.eq(#Comm.outbox, 4, "t2, t3, t4 and the one keyed message (t1 cancelled, its offer gone)")
	mock.lockdown = false
	mock.Advance(1)
	T.eq(#Comm.outbox, 0)
	T.ok(#sent >= 4, "all sent after the lockdown")
	for _, t in ipairs({ t1, t2, t3, t4 }) do
		Comm.Cancel(t)
	end
	Comm.MAX_OUTBOX, ns.addon.SendCommMessage = realMax, realSend
	mock.inGroup, mock.units = false, {}
	ns.DB.DeletePlan(plan.id)
end)

T.case("Comm: a plan whispered to a typed first name is acked by the whole name and counted", function()
	boot()
	local Comm = ns.Comm
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function() end
	mock.inGroup, mock.units = true, { party1 = { name = "Ana Smith" } }
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Typed", instance = { name = "Test Keep", kind = "dungeon" } }))
	local t = assert(Comm.SharePlan(plan, "WHISPER", "ana"))
	Comm.OnMessage(ns.prefix, Transfer.Encode({ type = "ack", tid = t.tid, plan = plan.id, version = plan.updated or 0 }),
		"WHISPER", "Ana Smith")
	T.eq(t.target, "Ana Smith", "the whole name adopted")
	T.eq(Comm.PlanStatus(plan).has, 1, "Ana Smith has it")
	-- Someone else's first name does not take over the transfer.
	local t2 = assert(Comm.SharePlan(plan, "WHISPER", "bob"))
	Comm.OnMessage(ns.prefix, Transfer.Encode({ type = "accept", tid = t2.tid }), "WHISPER", "Ana Smith")
	T.eq(t2.target, "bob")
	Comm.Cancel(t)
	Comm.Cancel(t2)
	ns.addon.SendCommMessage = realSend
	mock.inGroup, mock.units = false, {}
	Comm.AcksStore().plans = {}
	ns.DB.DeletePlan(plan.id)
end)
