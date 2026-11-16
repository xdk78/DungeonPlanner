-- Shared-plan tracking (Share/Acks.lua and Comm): the ack message, recording versions, the group's status (current,
-- outdated, missing, unknown), the receiver's ack after an import, the lockdown outbox and the per-sender flood limit.
local T = ...
local ns, mock = T.ns, T.mock
local Acks, Transfer = ns.Acks, ns.Transfer

T.case("Acks: wire format parses what it encodes and rejects junk", function()
	local text = Transfer.Encode({ type = "ack", tid = "abc123", plan = "p1f2", version = 1763300000 })
	T.eq(text, "K^abc123^p1f2^1763300000")
	local msg = Transfer.Parse(text)
	T.eq(msg.type, "ack")
	T.eq(msg.plan, "p1f2")
	T.eq(msg.version, 1763300000)
	T.eq(Transfer.Parse("K^abc123^-^5").plan, nil, "no plan id")
	T.eq(Transfer.Parse("K^ABC^p1^5"), nil, "bad tid")
	T.eq(Transfer.Parse("K^abc^p1^-5"), nil, "negative version")
	T.eq(Transfer.Parse("K^abc^p1^1.5"), nil, "not an integer")
	T.eq(Transfer.Parse("K^abc^p 1^5").plan, nil, "a bad plan id is dropped")
	T.eq(Transfer.Parse("K^abc^p1"), nil, "missing field")
	T.eq(Transfer.Parse("K^abc^b:hall-of-thanes^5").plan, "b:hall-of-thanes", "recommended plans' ids")
end)

T.case("Acks: versions only move forward; caps; status of the group", function()
	local store = Acks.Normalize(nil)
	T.ok(Acks.Record(store, "p1", "Anna", 100, 1))
	T.eq(Acks.Record(store, "p1", "Anna", 90, 2), false, "an older version does not replace a newer one")
	T.ok(Acks.Record(store, "p1", "Anna", 120, 3))
	T.ok(Acks.Record(store, "p1", "Bob", 100, 4))
	T.eq(Acks.Record(store, "p1", "", 100, 5), false)
	T.eq(Acks.Record(store, "bad id!", "Anna", 1, 5), false)
	local status = Acks.Status(store, "p1", 120, { "Anna", "Bob", "Cara", "Dov" }, { Cara = { version = "1" } })
	T.eq(status.total, 4)
	T.eq(status.has, 2)
	T.eq(status.current, 1)
	T.eq(status.outdated, 1, "Bob has the older version")
	T.eq(status.missing, 1, "Cara runs the addon but has not imported it")
	T.eq(status.unknown, 1, "Dov cannot answer (no addon, another client or a trial account)")
	T.eq(status.list[4].state, "unknown")
	-- Caps: plans and members.
	for i = 1, Acks.MAX_PLANS + 2 do
		Acks.Record(store, "q" .. i, "Anna", 1, 10 + i)
	end
	T.eq(ns.Util.Count(store.plans), Acks.MAX_PLANS)
	for i = 1, Acks.MAX_MEMBERS + 5 do
		Acks.Record(store, "q40", "M" .. i, 1, 100 + i)
	end
	T.eq(ns.Util.Count(store.plans.q40.members), Acks.MAX_MEMBERS)
	-- Normalize repairs junk.
	local junk = Acks.Normalize({ plans = { p1 = { members = { Anna = { v = 1 }, [5] = {}, Bob = { v = "x" } } }, ["bad id"] = {} } })
	T.eq(ns.Util.Count(junk.plans), 1)
	T.eq(ns.Util.Count(junk.plans.p1.members), 1)
end)

T.case("Acks over AceComm: the receiver acks an import; the sender records it; lockdown and flood limits", function()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	local Comm = ns.Comm
	local outgoing = {}
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, prefix, text, channel, target)
		outgoing[#outgoing + 1] = { prefix, text, channel, target }
	end
	mock.inGroup = true
	mock.units = { party1 = { name = "Anna" }, party2 = { name = "Bob" }, party3 = { name = "Cara" } }
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Tracked", instance = { name = "Test Keep", kind = "dungeon" } }))
	plan.updated = 5000
	-- The sender offers it; the transfer remembers the plan and its version.
	local transfer = assert(Comm.SharePlan(plan, "GROUP"))
	T.eq(transfer.planId, plan.id)
	T.eq(transfer.version, 5000)
	-- Anna acks it: recorded with the transfer's version.
	Comm.OnMessage(ns.prefix, Transfer.Encode({ type = "ack", tid = transfer.tid, plan = plan.id, version = 5000 }), "WHISPER",
		"Anna")
	local status = Comm.PlanStatus(plan)
	T.eq(status.total, 3)
	T.eq(status.has, 1)
	T.eq(status.unknown, 2, "Bob and Cara: no reply and no hello")
	-- Bob runs the addon (his hello came) but has not imported: missing, not unknown.
	Comm.peers.Bob = { version = "1", proto = 2, seen = 0 }
	status = Comm.PlanStatus(plan)
	T.eq(status.missing, 1)
	T.eq(status.unknown, 1)
	-- The plan changes: Anna's copy is outdated now.
	plan.updated = 6000
	status = Comm.PlanStatus(plan)
	T.eq(status.outdated, 1)
	T.eq(status.current, 0)
	-- An ack for an unknown transfer and a plan we do not have is ignored.
	Comm.OnMessage(ns.prefix, "K^zz9^nothere^1", "WHISPER", "Cara")
	T.eq(Comm.PlanStatus(plan).has, 1)
	-- Flood: past the per-sender budget, Cara's acks are ignored.
	for _ = 1, 30 do
		Comm.OnMessage(ns.prefix, "K^zz9^nothere^1", "WHISPER", "Cara")
	end
	Comm.OnMessage(ns.prefix, Transfer.Encode({ type = "ack", tid = transfer.tid, plan = plan.id, version = 6000 }), "WHISPER",
		"Cara")
	T.eq(Comm.PlanStatus(plan).has, 1, "Cara is over her budget")

	-- The receiving side: an imported plan is acked once, to its sender, with the payload's id and version; during a
	-- lockdown the ack waits in the outbox.
	local data = ns.Codec.ExportPlan(plan)
	local t = { kind = "plan", sender = "Anna", tid = "rx1" }
	mock.lockdown = true
	outgoing = {}
	T.ok(Comm.SendAck(t, data))
	T.eq(#outgoing, 0, "held in the lockdown")
	T.eq(Comm.SendAck(t, data), false, "once per transfer")
	mock.lockdown = false
	mock.Advance(1)
	T.eq(#outgoing, 1)
	local msg = Transfer.Parse(outgoing[1][2])
	T.eq(msg.type, "ack")
	T.eq(msg.tid, "rx1")
	T.eq(msg.plan, plan.id)
	T.eq(msg.version, 6000)
	T.eq(outgoing[1][3], "WHISPER")
	T.eq(outgoing[1][4], "Anna")
	T.eq(Comm.SendAck({ kind = "pack", sender = "Anna", tid = "rx2" }, data), false, "no acks for packs")

	ns.addon.SendCommMessage = realSend
	ns.DB.DeletePlan(plan.id)
	mock.inGroup, mock.units = false, {}
	Comm.peers.Bob = nil
end)
