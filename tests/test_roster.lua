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

-- Refused and held addon messages (Share/SendStats.lua, Comm.Problem): WoW: Forever 1.60.1 was reported to answer
-- AreOutgoingAddonChatMessagesRestricted() = true and to refuse some sends with result 7 (InvalidChannel).

T.case("SendStats: outcomes per distribution, refusals in a row, a success resets them, one line", function()
	local S = ns.SendStats
	local st = S.New()
	T.eq(S.Record(st, "PARTY", true, 1), true)
	T.eq(S.Record(st, "PARTY", 0, 2), true, "result code Success")
	T.eq(S.Record(st, "PARTY", nil, 3), nil, "an older library that says nothing: not counted")
	T.eq(st.by.PARTY.sent, 2)
	local ok, code = S.Record(st, "PARTY", 7, 4)
	T.eq(ok, false)
	T.eq(code, 7)
	S.Record(st, "PARTY", false, 5)
	T.eq(S.Refusing(st, "PARTY"), nil, "two in a row are not yet a pattern")
	S.Record(st, "PARTY", false, 6)
	T.ok(S.Refusing(st, "PARTY"), "three in a row")
	T.ok(S.Refusing(st), "on any distribution")
	T.eq(S.Refusing(st, "WHISPER"), nil, "only that distribution")
	T.eq(st.by.PARTY.code, nil, "the last refusal came without a code")
	T.eq(S.Describe(st), "PARTY 2 sent, 3 refused (last code not given, 3 in a row)")
	S.Record(st, "PARTY", true, 7)
	T.eq(S.Refusing(st), nil, "a success ends the streak")
	-- Bounded: unknown distributions share one entry.
	S.Record(st, "CHANNEL", 7, 8)
	S.Record(st, "SAY", 7, 9)
	T.eq(st.by.OTHER.refused, 2)
	T.eq(st.by.CHANNEL, nil)
	T.eq(S.Describe(S.New()), "nothing sent yet")
end)

T.case("Comm: no message goes to a custom channel; every distribution used is a group, guild or whisper one", function()
	for _, path in ipairs({ "Share/Comm.lua", "UI/RunSync.lua", "UI/NotesFrame.lua", "UI/Panels/SharePanel.lua",
		"UI/Panels/AssignmentsPanel.lua", "Core/Actions.lua" }) do
		local h = assert(io.open(path, "rb"))
		local text = h:read("*a")
		h:close()
		T.ok(not text:find('"CHANNEL"', 1, true), path)
	end
end)

T.case("Comm: sends the game refuses (result 7) are counted, fail their transfer, and sharing and sync say so", function()
	boot()
	local Comm = ns.Comm
	local realSendAddon = _G.C_ChatInfo.SendAddonMessage
	-- Own state: no lockdown, nothing waiting, no run being led, and ChatThrottleLib's queue drained of what earlier
	-- tests sent (it would be counted here otherwise).
	mock.lockdown, Comm.outbox = false, {}
	ns.RunSync.state = ns.Sync.New()
	mock.Advance(10, 0.1)
	local stats = Comm.sendStats
	Comm.sendStats = ns.SendStats.New()
	mock.inGroup, mock.units = true, { party1 = { name = "Anna" } }
	local states = {}
	ns:On("COMM_STATE", states, function(problem)
		states[#states + 1] = problem or "ok"
	end)
	local leaderFn = _G.UnitIsGroupLeader
	_G.UnitIsGroupLeader = function(unit)
		return unit == "player"
	end
	-- The real AceComm and ChatThrottleLib on the mock client (ChatThrottleLib sends from its OnUpdate, so time moves
	-- after each send); the game answers InvalidChannel, with the restriction answer true as reported on Forever.
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function()
		return true
	end
	local calls = 0
	_G.C_ChatInfo.SendAddonMessage = function()
		calls = calls + 1
		return 7
	end
	local function settle()
		mock.Advance(2, 0.1)
	end
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Refused", instance = { name = "Test Keep", kind = "dungeon" } }))
	local t = assert(Comm.SharePlan(plan, "GROUP"))
	settle()
	T.eq(t.state, "failed", "the offer was refused: no waiting for answers that cannot come")
	T.eq(t.reason, "refused")
	-- The group's channel (the mock's group reads as an instance group: INSTANCE_CHAT).
	local ch = Comm.GroupChannel()
	local e = Comm.sendStats.by[ch]
	T.eq(e and e.refused, 1)
	-- AceComm-3.0 (minor 14) passes only "not sent", not the code: recorded without one.
	T.eq(e.code, nil)
	T.eq(Comm.Problem(ch), nil, "one refusal is not yet a pattern")
	Comm.SendSync(Transfer.Encode({ type = "query", proto = ns.PROTOCOL_VERSION }), ch)
	settle()
	Comm.SendSync(Transfer.Encode({ type = "query", proto = ns.PROTOCOL_VERSION }), ch)
	settle()
	-- At least these three (run mode left open by an earlier test may send on the same channel).
	T.ok(e.refused >= 3, tostring(e.refused))
	-- Refused once each, never sent again (no retry loop).
	T.eq(#Comm.outbox, 0)
	local before = calls
	mock.Advance(10, 0.5)
	T.eq(calls, before, "nothing retried")
	T.eq(Comm.Problem(ch), "refused")
	T.eq(Comm.Problem("GUILD"), nil, "only the distribution that refuses")
	T.eq(states[#states], "refused", "COMM_STATE told the UI")
	T.eq(Comm.ProblemText(ch), "The game refused the last addon messages: other players may not receive them.")
	-- Group sync's line (the leader's "Lead this run") and the debug line say so.
	local st = ns.RunSync.LineState(plan)
	T.eq(st and st.text, Comm.ProblemText(ch))
	T.eq(st and st.dot, "warning")
	T.eq(st and st.action, "lead", "the button stays")
	T.ok(Comm.DebugLine():find(string.format("%s 0 sent, %d refused (last code not given, %d in a row)", ch, e.refused,
		e.streak), 1, true), Comm.DebugLine())
	-- A library that passes the code has it recorded.
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, _, text, _, _, _, callback)
		callback(nil, #text, #text, 7)
	end
	Comm.SendSync("x", ch)
	T.eq(e.code, 7)
	ns.addon.SendCommMessage = realSend
	-- The game takes messages again: the streak ends and the line goes.
	_G.C_ChatInfo.SendAddonMessage = realSendAddon
	Comm.SendSync(Transfer.Encode({ type = "query", proto = ns.PROTOCOL_VERSION }), ch)
	settle()
	T.eq(e.streak, 0)
	T.ok(e.sent >= 1)
	T.eq(Comm.Problem(), nil)
	T.eq(states[#states], "ok")
	T.eq(ns.RunSync.LineState(plan).text, ns.L["Lead the group's run mode"])
	ns:Off("COMM_STATE", states)
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
	_G.UnitIsGroupLeader = leaderFn
	Comm.sendStats = stats
	mock.inGroup, mock.units = false, {}
	ns.DB.DeletePlan(plan.id)
end)

T.case("Comm: the restriction answer alone holds nothing: messages are sent, debug shows the flag", function()
	boot()
	local Comm = ns.Comm
	mock.lockdown, Comm.outbox, Comm.sendStats = false, {}, ns.SendStats.New()
	ns.RunSync.state = ns.Sync.New()
	mock.Advance(10, 0.1) -- ChatThrottleLib's queue drained of earlier tests' messages
	local sent = #mock.sent
	mock.inGroup = true
	-- Forever 1.60.1 was reported to answer true outside encounters; holding on it would send nothing ever.
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function()
		return true
	end
	T.eq(Comm.IsLockedDown(), false)
	T.eq(Comm.Problem(), nil, "no line while sends are not refused")
	T.eq(Comm.ProblemText(), nil)
	Comm.SendSync(Transfer.Encode({ type = "query", proto = ns.PROTOCOL_VERSION }), "PARTY", nil, "query")
	T.eq(#Comm.outbox, 0, "not held")
	mock.Advance(2, 0.1)
	T.eq(#mock.sent, sent + 1, "sent")
	T.ok(Comm.DebugLine():find("lockdown no, outgoing restricted yes, waiting 0", 1, true), Comm.DebugLine())
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
	T.ok(Comm.DebugLine():find("outgoing restricted n/a", 1, true), "a client without the function")
	mock.inGroup = false
end)

T.case("Comm: during the encounter lockdown messages wait, sharing says so, and they go out after it", function()
	boot()
	local Comm = ns.Comm
	mock.lockdown, Comm.outbox, Comm.sendStats = false, {}, ns.SendStats.New()
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
	ns.RunSync.state = ns.Sync.New()
	mock.Advance(10, 0.1) -- ChatThrottleLib's queue drained of earlier tests' messages
	local sent = #mock.sent
	mock.inGroup, mock.lockdown = true, true
	T.eq(Comm.Problem(), "blocked")
	T.eq(Comm.ProblemText(), "Addon messages are blocked by the game right now: they wait and go out when it allows them.")
	Comm.SendSync(Transfer.Encode({ type = "query", proto = ns.PROTOCOL_VERSION }), "PARTY", nil, "query")
	T.eq(#Comm.outbox, 1, "it waits")
	mock.Advance(2, 0.1)
	T.eq(#mock.sent, sent, "nothing went out")
	T.ok(Comm.DebugLine():find("lockdown yes, outgoing restricted n/a, waiting 1", 1, true), Comm.DebugLine())
	-- The share section's status starts with the line.
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("share")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.share.inner
	panel:RefreshStatus()
	T.eq(panel.content.status:GetText():match("^[^\n]*"), Comm.ProblemText())
	mock.lockdown = false
	mock.Advance(2, 0.1)
	T.eq(#Comm.outbox, 0)
	T.eq(#mock.sent, sent + 1, "sent once the lockdown lifts")
	T.eq(Comm.Problem(), nil)
	panel:RefreshStatus()
	T.ok(not (panel.content.status:GetText() or ""):find("blocked", 1, true), "the line is gone")
	mock.inGroup = false
end)

T.case("Compat: /dp debug checks both addon message restriction functions", function()
	local paths = {}
	for _, row in ipairs(ns.Compat.Report()) do
		paths[row.path] = true
	end
	T.ok(paths["C_ChatInfo.InChatMessagingLockdown"])
	T.ok(paths["C_ChatInfo.AreOutgoingAddonChatMessagesRestricted"])
end)
