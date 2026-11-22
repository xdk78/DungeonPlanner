-- In-game sharing: the glue between Transfer.lua's state machines and the game, over AceComm-3.0 (which splits long
-- messages and paces them through ChatThrottleLib; ChatThrottleLib v32 also retries the server's "throttled" answer).
--
-- What we add on top:
-- * Lockdowns: on Forever the game blocks addon messages at times (boss fights, restricted states). Messages wait in
--   our small outbox until C_ChatInfo says the lockdown is over, instead of being dropped.
-- * Incoming offers are filtered by the sharing setting, rate-limited per sender, and prompted out of combat.
-- * A timer runs only while something waits or a transfer is open; an idle addon has no timer.

local _, ns = ...
local Comm = ns:NewModule("Comm")
local Transfer, Util = ns.Transfer, ns.Util

local TICK = 0.5
local MAX_OPEN_PROMPTS = 3
local SENDER_BUDGET = 20 -- messages per sender per SENDER_WINDOW before we ignore them
local SENDER_WINDOW = 10
local HELLO_INTERVAL = 60

Comm.outgoing = {} -- tid -> transfer
Comm.incoming = {} -- sender .. ":" .. tid -> transfer
Comm.peers = {} -- name -> { version, proto, seen }
Comm.outbox = {} -- messages waiting for a lockdown to end

local ticker
local senderCounts = {}
local lastHello = {}

local function now()
	return ns.Clock()
end

function Comm.IsAvailable()
	return ns.addon ~= nil and ns.addon.SendCommMessage ~= nil and C_ChatInfo ~= nil
		and C_ChatInfo.SendAddonMessage ~= nil
end

-- True while the game blocks addon messages. Only a plain `true` counts; a check that errors does not.
function Comm.IsLockedDown()
	if not C_ChatInfo then
		return false
	end
	for _, name in ipairs({ "InChatMessagingLockdown", "AreOutgoingAddonChatMessagesRestricted" }) do
		local fn = C_ChatInfo[name]
		if type(fn) == "function" then
			local ok, restricted = pcall(fn)
			if ok and restricted == true then
				return true
			end
		end
	end
	return false
end

function Comm.GroupChannel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	elseif IsInRaid and IsInRaid() then
		return "RAID"
	elseif IsInGroup and IsInGroup() then
		return "PARTY"
	end
	return nil
end

-- Timer -------------------------------------------------------------------------------------------------------------------

local function hasWork()
	if #Comm.outbox > 0 then
		return true
	end
	for _, t in pairs(Comm.outgoing) do
		if not Transfer.IsFinished(t) then
			return true
		end
	end
	for _, t in pairs(Comm.incoming) do
		if not Transfer.IsFinished(t) then
			return true
		end
	end
	return false
end

local function ensureTicker()
	if not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(TICK, function()
			ns.SafeCall(Comm.OnTick)
		end)
	end
end

local function stopTickerIfIdle()
	if ticker and not hasWork() then
		ticker:Cancel()
		ticker = nil
	end
end

-- Sending -----------------------------------------------------------------------------------------------------------------

-- prio: "ALERT" for short control messages, "BULK" for payloads (ChatThrottleLib priorities).
local function send(msg, channel, target, prio, callback, arg)
	ns.addon:SendCommMessage(ns.prefix, msg, channel, target, prio or "NORMAL", callback, arg)
end

-- key (optional): a message that only the newest of its kind matters for (run sync's state): one still waiting in the
-- outbox under the same key is replaced in place, so a lockdown sends one current message, not every one before it.
local function enqueue(msg, channel, target, prio, callback, arg, key)
	if Comm.IsLockedDown() then
		local item = { msg, channel, target, prio, callback, arg, key = key }
		if key then
			for i, old in ipairs(Comm.outbox) do
				if old.key == key then
					Comm.outbox[i] = item
					return
				end
			end
		end
		Comm.outbox[#Comm.outbox + 1] = item
		ensureTicker()
	else
		send(msg, channel, target, prio, callback, arg)
	end
end

local applyEffects

local function stepOut(t, event)
	applyEffects(Transfer.StepOutgoing(t, event, now()))
end

local function stepIn(t, event)
	applyEffects(Transfer.StepIncoming(t, event, now()))
end

function applyEffects(effects)
	for _, e in ipairs(effects) do
		local kind = e[1]
		if kind == "send" then
			enqueue(e[2], e[3], e[4], "ALERT")
		elseif kind == "sendPayload" then
			local t, msg = e[2], e[3]
			-- AceComm calls back after each part with (arg, bytesSent, bytesTotal).
			enqueue(msg, t.channel, t.target, "BULK", function(transfer, sent, total)
				if transfer.state ~= "sending" then
					return
				end
				if sent >= total then
					stepOut(transfer, { type = "sent" })
				else
					stepOut(transfer, { type = "progress", sent = sent, total = total })
				end
			end, t)
		elseif kind == "sendPayloadTo" then
			enqueue(e[3], "WHISPER", e[4], "BULK")
		elseif kind == "prompt" then
			local t = e[2]
			ns:RunOutOfCombat(function()
				if t.state == "prompt" then
					ns:Fire("SHARE_PROMPT", t)
				end
			end)
		elseif kind == "closePrompt" then
			ns:Fire("SHARE_PROMPT_CLOSED", e[2])
		elseif kind == "status" then
			ns:Fire("SHARE_STATUS", e[2])
		elseif kind == "complete" then
			local t, data = e[2], e[3]
			ns:RunOutOfCombat(function()
				local ok, err = ns.DB.ImportString(data, { from = t.sender, kind = "received" })
				if not ok then
					ns:Print(ns.L["Received plan could not be read:"], err)
				else
					Comm.SendAck(t, data)
				end
			end)
		end
	end
	ensureTicker()
end

function Comm.OnTick()
	for _, transfer in pairs(Comm.outgoing) do
		if not Transfer.IsFinished(transfer) then
			stepOut(transfer, { type = "tick" })
		end
	end
	for _, transfer in pairs(Comm.incoming) do
		if not Transfer.IsFinished(transfer) then
			stepIn(transfer, { type = "tick" })
		end
	end
	if #Comm.outbox > 0 and not Comm.IsLockedDown() then
		local box = Comm.outbox
		Comm.outbox = {}
		for _, item in ipairs(box) do
			send(unpack(item, 1, 6))
		end
	end
	stopTickerIfIdle()
end

-- Public: share a plan --------------------------------------------------------------------------------------------------

-- channel: "GROUP" (picks PARTY/RAID/INSTANCE_CHAT), "GUILD" or "WHISPER" with target.
function Comm.SharePlan(plan, channel, target)
	if not Comm.IsAvailable() then
		return nil, ns.L["Addon messages are not available on this client."]
	end
	if channel == "GROUP" then
		channel = Comm.GroupChannel()
		if not channel then
			return nil, ns.L["You are not in a group."]
		end
	end
	if channel == "WHISPER" then
		target = Util.CleanText(target or "", 48)
		if not target or target == "" then
			return nil, ns.L["Enter a player name."]
		end
	end
	local data, err = ns.Codec.ExportPlan(plan)
	if not data then
		return nil, err
	end
	local transfer, effects = Transfer.NewOutgoing(data, "plan", plan.name, channel, target, now())
	if not transfer then
		return nil, ns.L["This plan is too large to send in-game. Use Export instead."]
	end
	-- For the acks of who imported it (Share/Acks.lua): which plan, which version.
	transfer.planId, transfer.version = plan.id, plan.updated
	Comm.outgoing[transfer.tid] = transfer
	applyEffects(effects)
	ns:Fire("SHARE_STATUS", transfer)
	return transfer
end

function Comm.Respond(transfer, accept)
	if transfer.dir ~= "in" or transfer.state ~= "prompt" then
		return
	end
	stepIn(transfer, { type = accept and "accept" or "decline" })
end

function Comm.Cancel(transfer)
	if transfer.dir == "out" then
		stepOut(transfer, { type = "cancel" })
	elseif transfer.dir == "in" and not Transfer.IsFinished(transfer) then
		enqueue(Transfer.Encode({ type = "cancel", tid = transfer.tid }), "WHISPER", transfer.sender, "ALERT")
		stepIn(transfer, { type = "cancel" })
	end
end

-- Hello: who in the group runs Dungeon Planner, and which version. Never in combat or a lockdown.
function Comm.SayHello()
	local channel = Comm.GroupChannel()
	if not channel or not Comm.IsAvailable() then
		return
	end
	if (InCombatLockdown and InCombatLockdown()) or Comm.IsLockedDown() then
		return
	end
	local t = now()
	if lastHello[channel] and t - lastHello[channel] < HELLO_INTERVAL then
		return
	end
	lastHello[channel] = t
	send(Transfer.Encode({ type = "hello", proto = ns.PROTOCOL_VERSION, version = ns.version }), channel, nil, "BULK")
end

function Comm.PeerCount()
	return Util.Count(Comm.peers)
end

-- Group -------------------------------------------------------------------------------------------------------------------

local function plainCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	return ok and Util.Plain(v) or nil
end

-- The group's unit tokens (the player first, then the party or raid).
function Comm.GroupUnits()
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

-- The other group members' names (plain, short), never secret values.
function Comm.GroupMembers()
	local out = {}
	local me = UnitName and Util.ShortName(plainCall(UnitName, "player"))
	for _, unit in ipairs(Comm.GroupUnits()) do
		if plainCall(UnitExists, unit) then
			local name = Util.ShortName(plainCall(UnitName, unit))
			if name and name ~= me and not Util.IndexOf(out, name) then
				out[#out + 1] = name
			end
		end
	end
	return out
end

-- Who `name` (nil: the player) is in the group: { inGroup, inRaid, leader, assist, unit }. Leader and assistant come
-- from UnitIsGroupLeader / UnitIsGroupAssistant (guarded; a secret or missing answer counts as no).
function Comm.GroupRank(name)
	local inGroup = (IsInGroup and IsInGroup()) and true or false
	local inRaid = (IsInRaid and IsInRaid()) and true or false
	local unit
	if name == nil then
		unit = "player"
	elseif inGroup then
		for _, u in ipairs(Comm.GroupUnits()) do
			if Util.ShortName(plainCall(UnitName, u)) == name then
				unit = u
				break
			end
		end
	end
	local info = { inGroup = inGroup and unit ~= nil, inRaid = inRaid, unit = unit }
	if unit then
		info.leader = plainCall(rawget(_G, "UnitIsGroupLeader"), unit) == true
		info.assist = plainCall(rawget(_G, "UnitIsGroupAssistant"), unit) == true
	end
	return info
end

-- Shared-plan tracking (Share/Acks.lua) ----------------------------------------------------------------------------------

-- Who has which version of the plans this character sent (DungeonPlannerDB.char[key].shareAcks).
function Comm.AcksStore()
	local char = ns.char
	if not char then
		return nil
	end
	local s = char.shareAcks
	if type(s) ~= "table" or type(s.plans) ~= "table" then
		s = ns.Acks.Normalize(s)
		char.shareAcks = s
	end
	return s
end

-- After importing a received plan: tell its sender which plan and version arrived. Whispered, through the outbox (a
-- lockdown holds it), once per transfer; never for packs. The plan's id and version are read from the payload as sent.
function Comm.SendAck(t, data)
	if t.acked or t.kind ~= "plan" or not t.sender then
		return false
	end
	local kind, plan = ns.Codec.Decode(data)
	if kind ~= "plan" then
		return false
	end
	t.acked = true
	local id = plan.id
	if not id and plan.origin and plan.origin.bundled then
		id = ns.Bundled.PREFIX .. plan.origin.bundled
	end
	enqueue(Transfer.Encode({ type = "ack", tid = t.tid, plan = id, version = plan.updated or 0 }), "WHISPER", t.sender,
		"BULK")
	return true
end

-- Is `name` in the player's party or raid? Only a plain `true` counts (a secret answer is "no").
local function inMyGroup(name)
	if plainCall(UnitInParty, name) == true then
		return true
	end
	local raid = plainCall(UnitInRaid, name) -- the raid index, or nil
	return raid ~= nil and raid ~= false
end

-- A whisper finds its player whatever the case of the typed name, but replies carry the name as the game spells it:
-- the first reply from that player fixes the transfer's target, so "anna" and "Anna" are one receiver.
local function adoptTarget(out, sender)
	if out and out.channel == "WHISPER" and out.target ~= sender and type(out.target) == "string"
		and out.target:lower() == sender:lower() then
		out.target = sender
	end
end

local function onAck(msg, sender)
	-- Only for our own transfers, or plans we have: anything else is noise.
	local out = Comm.outgoing[msg.tid]
	adoptTarget(out, sender)
	local planId, version = msg.plan, msg.version
	if out then
		-- From someone the offer went to: the whisper's target, or a member of the group it was offered to.
		if out.channel == "WHISPER" then
			if out.target ~= sender then
				return
			end
		elseif not (out.accepted[sender] or inMyGroup(sender) or out.channel == "GUILD") then
			return
		end
		planId, version = out.planId or planId, out.version or version
	else
		-- A transfer this session no longer knows (a reload since): only a group member's word is taken, and never a
		-- version the plan has not reached, which would read as "current" for ever.
		local plan = planId and ns.DB.GetPlan(planId)
		if not (plan and inMyGroup(sender)) or version > (plan.updated or 0) then
			return
		end
	end
	local store = Comm.AcksStore()
	if store and ns.Acks.Record(store, planId, sender, version, ns.Now()) then
		ns:Fire("SHARE_ACKS", planId)
	end
end

-- The group against a plan (Acks.Status): who has it, who has an older version, who cannot tell.
function Comm.PlanStatus(plan)
	if not plan then
		return nil
	end
	return ns.Acks.Status(Comm.AcksStore(), plan.id, plan.updated, Comm.GroupMembers(), Comm.peers)
end

-- Run sync (Share/Sync.lua, UI/RunSync.lua): small state messages at NORMAL priority, through the outbox; `key` keeps
-- only the newest one of a kind waiting in a lockdown. Returns false when addon messages are not available.
function Comm.SendSync(msg, channel, target, key)
	if not Comm.IsAvailable() or not channel then
		return false
	end
	enqueue(msg, channel, target, "NORMAL", nil, nil, key)
	return true
end

-- Raid assignment pages ----------------------------------------------------------------------------------------------------

-- The pages received from the group's leader (DungeonPlannerDB.char[key].notes).
function Comm.NotesStore()
	local char = ns.char
	if not char then
		return nil
	end
	local s = char.notes
	if type(s) ~= "table" or type(s.received) ~= "table" then
		s = ns.Pages.NormalizeReceived(s)
		char.notes = s
	end
	return s
end

-- Push a page to the group: the leader (or, in a raid, an assistant) only. `payload` = { title, text, boss?, enc?,
-- plan? } (UI/NotesFrame.lua builds it). Goes through the outbox, so it waits out a lockdown. Returns true or nil, error.
function Comm.SendPage(payload)
	if not Comm.IsAvailable() then
		return nil, ns.L["Addon messages are not available on this client."]
	end
	local channel = Comm.GroupChannel()
	local ok, why = ns.Pages.CanSend(Comm.GroupRank())
	if not channel or why == "group" then
		return nil, ns.L["You are not in a group."]
	elseif not ok then
		return nil, ns.L["Only the group's leader or a raid assistant can send pages."]
	end
	local data = ns.Codec.EncodeNote(payload)
	if not data or #data > Transfer.MAX_NOTE then
		return nil, ns.L["This page is too long to send."]
	end
	-- While the game holds addon messages (a boss fight), the outbox keeps it until the lockdown ends.
	local waiting = Comm.IsLockedDown()
	enqueue(Transfer.Encode({ type = "note", proto = ns.PROTOCOL_VERSION, data = data }), channel, nil, "ALERT")
	return true, waiting
end

local function onNote(msg, sender)
	if msg.proto ~= ns.PROTOCOL_VERSION then
		return
	end
	local policy = ns.db and ns.db.settings.notes.acceptFrom or "leaders"
	if not ns.Pages.AcceptFrom(policy, Comm.GroupRank(sender)) then
		return
	end
	local page = ns.Codec.DecodeNote(msg.data)
	local store = page and Comm.NotesStore()
	if store then
		ns.Pages.Receive(store, page, sender, ns.Now())
		ns:Fire("NOTES_RECEIVED", page)
	end
end

-- Receiving ---------------------------------------------------------------------------------------------------------------

local function senderAllowed(sender, channel)
	local policy = ns.db and ns.db.settings.share.acceptFrom or "groupGuild"
	if policy == "nobody" then
		return false
	elseif policy == "anyone" then
		return true
	end
	if inMyGroup(sender) then
		return true
	end
	if policy == "groupGuild" then
		if channel == "GUILD" then
			return true
		end
		if C_GuildInfo and C_GuildInfo.MemberExistsByName then
			local ok, member = pcall(C_GuildInfo.MemberExistsByName, sender)
			if ok and member == true then
				return true
			end
		end
	end
	return false
end

local function withinBudget(sender, t)
	local rec = senderCounts[sender]
	if not rec or t - rec.start > SENDER_WINDOW then
		rec = { start = t, n = 0 }
		senderCounts[sender] = rec
	end
	rec.n = rec.n + 1
	return rec.n <= SENDER_BUDGET
end

local function openPrompts()
	local n = 0
	for _, t in pairs(Comm.incoming) do
		if t.state == "prompt" then
			n = n + 1
		end
	end
	return n
end

-- AceComm hands over whole messages (already reassembled).
function Comm.OnMessage(prefix, text, channel, sender)
	if prefix ~= ns.prefix then
		return
	end
	text, sender = Util.Plain(text), Util.ShortName(sender)
	if type(text) ~= "string" or not sender then
		return
	end
	local me = UnitName and Util.ShortName(UnitName("player"))
	if sender == me then
		return
	end
	local t = now()
	if not withinBudget(sender, t) then
		return
	end
	local msg = Transfer.Parse(text)
	if not msg then
		return
	end

	if msg.type == "hello" or msg.type == "helloReply" then
		Comm.peers[sender] = { version = msg.version, proto = msg.proto, seen = t }
		if msg.type == "hello" and ns.db and ns.db.settings.share.replyHello then
			enqueue(Transfer.Encode({ type = "helloReply", proto = ns.PROTOCOL_VERSION, version = ns.version }), "WHISPER",
				sender, "BULK")
		end
		ns:Fire("SHARE_PEERS")
		return
	end

	if msg.type == "note" then
		onNote(msg, sender)
		return
	end
	if msg.type == "ack" then
		onAck(msg, sender)
		return
	end
	-- Run sync: older Dungeon Planners parse these tags as nothing and drop them (Transfer.Parse returns nil).
	if msg.type == "run" or msg.type == "follow" or msg.type == "query" or msg.type == "want" then
		if msg.proto == ns.PROTOCOL_VERSION and ns.RunSync then
			ns.RunSync.OnMessage(msg, sender, channel)
		end
		return
	end

	if msg.type == "offer" then
		local key = sender .. ":" .. msg.tid
		if Comm.incoming[key] then
			return
		end
		if msg.proto ~= ns.PROTOCOL_VERSION then
			ns:Print(string.format(ns.L["%s offered a plan made with a different Dungeon Planner version. Ask them to export it instead."], sender))
			return
		end
		if not senderAllowed(sender, channel) or openPrompts() >= MAX_OPEN_PROMPTS then
			if channel == "WHISPER" then
				enqueue(Transfer.Encode({ type = "decline", tid = msg.tid }), "WHISPER", sender, "ALERT")
			end
			return
		end
		local transfer, effects = Transfer.NewIncoming(msg, sender, channel, t)
		if transfer then
			Comm.incoming[key] = transfer
			applyEffects(effects)
		end
		return
	end

	if msg.type == "accept" or msg.type == "decline" then
		local transfer = Comm.outgoing[msg.tid]
		if transfer then
			adoptTarget(transfer, sender)
			stepOut(transfer, { type = msg.type, from = sender })
		end
	elseif msg.type == "payload" or msg.type == "cancel" then
		local transfer = Comm.incoming[sender .. ":" .. msg.tid]
		if transfer then
			stepIn(transfer, msg)
		elseif msg.type == "cancel" then
			local out = Comm.outgoing[msg.tid]
			adoptTarget(out, sender)
			if out and out.channel == "WHISPER" and out.target == sender then
				stepOut(out, { type = "cancel" })
			end
		end
	end
end

function Comm.Prune()
	local t = now()
	for key, transfer in pairs(Comm.incoming) do
		if Transfer.IsFinished(transfer) and t - (transfer.deadline or t) > 300 then
			Comm.incoming[key] = nil
		end
	end
	for key, transfer in pairs(Comm.outgoing) do
		if Transfer.IsFinished(transfer) and t - (transfer.started or t) > 600 then
			Comm.outgoing[key] = nil
		end
	end
	for name, rec in pairs(senderCounts) do
		if t - rec.start > SENDER_WINDOW then
			senderCounts[name] = nil
		end
	end
end

function Comm.Init()
	if not Comm.IsAvailable() then
		return false
	end
	ns.addon:RegisterComm(ns.prefix, function(prefix, text, channel, sender)
		ns.SafeCall(Comm.OnMessage, prefix, text, channel, sender)
	end)
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		Comm.Prune()
		if ns.db and ns.db.settings.share.announce and C_Timer then
			C_Timer.After(5, function()
				ns.SafeCall(Comm.SayHello)
			end)
		end
	end)
	return true
end
