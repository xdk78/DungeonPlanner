-- In-game sharing: the wire format and the transfer state machines. Pure (no WoW API); Comm.lua turns the effects
-- into AceComm messages, timers and UI prompts.
--
-- Each transfer is an explicit state machine: a state table plus step functions that take an event and return a list
-- of effects instead of performing them. Timers are events too ("tick"), so a stale timer changes nothing.
--
-- Wire messages (AceComm, prefix "DungeonPlanner"; fields joined by "^"; no field may contain "^"):
--   H^<proto>^<version>                                    hello, broadcast to the group
--   h^<proto>^<version>                                    hello reply, whispered
--   O^<proto>^<tid>^<bytes>^<sum>^<kind>^<name>            offer
--   A^<tid>   accept      D^<tid>   decline      X^<tid>   cancel
--   P^<tid>^<export string>                                the payload, sent after an accept
--   N^<proto>^<note string>                                a raid assignment page pushed to the group (leader or assist)
--   K^<tid>^<plan id>^<version>                            ack: the plan of transfer tid was imported (Share/Acks.lua)
--   R^<proto>^<session>^<seq>^<plan id>^<version>^<step>^<pull>   a leader's run mode (Share/Sync.lua); plan id "-":
--                                                          the lead ended
--   F^<proto>^<session>^<status>                           a member's follow status, whispered to the leader
--   Q^<proto>                                              who leads the run? (to the group)
--   W^<proto>^<session>                                    a member asks the leader for the plan (whispered)
--   L^<proto>^<instance>^<area>^<ask>                      the room a member is in (Share/Rooms.lua); instance 0 and
--                                                          area "-": nowhere to show; ask 1: send yours
-- AceComm splits long messages into parts and ChatThrottleLib paces them; we only bound sizes and check sums.
-- See docs/SHARING-FORMAT.md.

local _, ns = ...
local Transfer = ns:NewModule("Transfer")
local Util = ns.Util

Transfer.MAX_BYTES = 96000 -- largest export string sent in-game (~400 addon messages); bigger plans use Export
Transfer.MAX_MESSAGE = Transfer.MAX_BYTES + 32
Transfer.OFFER_TIMEOUT = 90 -- seconds a receiver has to answer the prompt
Transfer.GATHER = 6 -- seconds a group offer waits for more accepts after the first one
Transfer.RECEIVE_TIMEOUT = 300 -- seconds after accepting before a receive gives up
Transfer.MAX_NOTE = 12000 -- a pushed page's encoded string (Codec.EncodeNote of at most Schema.TEXT.page bytes)

local SEP = "^"

local function field(s)
	return (tostring(s):gsub("%^", ""))
end

function Transfer.NewTid()
	local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	local out = {}
	for i = 1, 6 do
		local n = math.random(1, #alphabet)
		out[i] = alphabet:sub(n, n)
	end
	return table.concat(out)
end

local function validTid(tid)
	return type(tid) == "string" and tid:match("^[a-z0-9]+$") ~= nil and #tid <= 8
end

function Transfer.Encode(msg)
	local t = msg.type
	if t == "hello" or t == "helloReply" then
		return (t == "hello" and "H" or "h") .. SEP .. msg.proto .. SEP .. field(msg.version)
	elseif t == "offer" then
		return table.concat({
			"O",
			msg.proto,
			msg.tid,
			msg.bytes,
			msg.sum,
			msg.kind,
			field(Util.CleanText(msg.name or "", 64) or ""),
		}, SEP)
	elseif t == "accept" then
		return "A" .. SEP .. msg.tid
	elseif t == "decline" then
		return "D" .. SEP .. msg.tid
	elseif t == "cancel" then
		return "X" .. SEP .. msg.tid
	elseif t == "payload" then
		return "P" .. SEP .. msg.tid .. SEP .. msg.data
	elseif t == "note" then
		return "N" .. SEP .. msg.proto .. SEP .. msg.data
	elseif t == "ack" then
		return "K" .. SEP .. msg.tid .. SEP .. field(msg.plan or "-") .. SEP .. math.floor(tonumber(msg.version) or 0)
	elseif t == "run" then
		local on = msg.plan ~= nil
		return table.concat({ "R", msg.proto, msg.session, msg.seq, on and field(msg.plan) or "-", on and msg.version or 0,
			on and msg.step or 0, on and msg.pull or 0 }, SEP)
	elseif t == "follow" then
		return table.concat({ "F", msg.proto, msg.session, msg.status }, SEP)
	elseif t == "query" then
		return "Q" .. SEP .. msg.proto
	elseif t == "want" then
		return "W" .. SEP .. msg.proto .. SEP .. msg.session
	elseif t == "room" then
		return table.concat({ "L", msg.proto, msg.iid, msg.area or "-", msg.ask and 1 or 0 }, SEP)
	end
	error("unknown message type " .. tostring(t))
end

-- An integer within lo..hi, else nil.
local function intIn(s, lo, hi)
	local n = tonumber(s)
	return Util.IsInteger(n) and n >= lo and n <= hi and n or nil
end

-- Run sync (Share/Sync.lua): each field is checked here; who may send and which plan it is, in Sync.Step.
local FOLLOW_STATUS = { f = true, u = true, m = true, o = true }
local function parseSync(tag, parts)
	local proto = intIn(parts[2], 0, 999)
	if not proto then
		return nil
	end
	if tag == "Q" then
		return #parts == 2 and { type = "query", proto = proto } or nil
	end
	if not validTid(parts[3]) then
		return nil
	end
	if tag == "W" then
		return #parts == 3 and { type = "want", proto = proto, session = parts[3] } or nil
	elseif tag == "F" then
		if #parts ~= 4 or not FOLLOW_STATUS[parts[4]] then
			return nil
		end
		return { type = "follow", proto = proto, session = parts[3], status = parts[4] }
	end
	if #parts ~= 8 then
		return nil
	end
	local Sync = ns.Sync
	local seq, version = intIn(parts[4], 1, Sync.MAX_SEQ), intIn(parts[6], 0, Sync.MAX_VERSION)
	local step, pull = intIn(parts[7], 0, Sync.MAX_STEP), intIn(parts[8], 0, Sync.MAX_PULL)
	if not (seq and version and step and pull) then
		return nil
	end
	local plan = parts[5]
	if plan == "-" then
		return { type = "run", proto = proto, session = parts[3], seq = seq }
	elseif not ns.Acks.ValidPlanId(plan) then
		return nil
	end
	return { type = "run", proto = proto, session = parts[3], seq = seq, plan = plan, version = version, step = step,
		pull = pull }
end

-- A member's room (Share/Rooms.lua): an instance map ID (0: nowhere) and an area key of Data/Subzones.lua ("a" or "w"
-- and an ID; "-": none), never a name.
local function parseRoom(parts)
	local Rooms = ns.Rooms
	local proto, iid, ask = intIn(parts[2], 0, 999), intIn(parts[3], 0, Rooms.MAX_IID), intIn(parts[5], 0, 1)
	local area = parts[4]
	if #parts ~= 5 or not (proto and iid and ask) then
		return nil
	end
	if area == "-" then
		area = nil
	elseif iid == 0 or #area > Rooms.MAX_KEY or not area:match("^[aw][1-9]%d*$") then
		return nil
	end
	return { type = "room", proto = proto, iid = iid, area = area, ask = ask == 1 }
end

-- Returns a message table or nil for anything malformed. Never raises.
function Transfer.Parse(text)
	if type(text) ~= "string" or #text > Transfer.MAX_MESSAGE then
		return nil
	end
	local tag = text:sub(1, 1)
	if tag == "P" then
		local tid, data = text:match("^P%^([a-z0-9]+)%^(.+)$")
		if not validTid(tid) or #data > Transfer.MAX_BYTES or data:find("[^%w%(%)!]") then
			return nil
		end
		return { type = "payload", tid = tid, data = data }
	end
	if tag == "N" then
		local proto, data = text:match("^N%^(%d+)%^(!DP%d+![%w%(%)]+)$")
		if not proto or #data > Transfer.MAX_NOTE then
			return nil
		end
		return { type = "note", proto = tonumber(proto), data = data }
	end
	if #text > 255 then
		return nil
	end
	local parts = Util.Split(text, SEP)
	if tag == "H" or tag == "h" then
		local proto = tonumber(parts[2])
		if not proto or #parts ~= 3 then
			return nil
		end
		return {
			type = tag == "H" and "hello" or "helloReply",
			proto = proto,
			version = Util.CleanText(parts[3], 24) or "?",
		}
	elseif tag == "O" then
		if #parts ~= 7 then
			return nil
		end
		local proto, bytes = tonumber(parts[2]), tonumber(parts[4])
		if not (proto and validTid(parts[3]) and Util.IsInteger(bytes)) then
			return nil
		end
		if not parts[5]:match("^%x%x%x%x%x%x%x%x$") or not ns.Codec.KINDS[parts[6]] then
			return nil
		end
		return {
			type = "offer",
			proto = proto,
			tid = parts[3],
			bytes = bytes,
			sum = parts[5],
			kind = parts[6],
			name = Util.CleanText(parts[7], 64) or "",
		}
	elseif tag == "K" then
		local version = tonumber(parts[4])
		if #parts ~= 4 or not validTid(parts[2]) or not Util.IsInteger(version) or version < 0 then
			return nil
		end
		local plan = parts[3] ~= "-" and ns.Acks.ValidPlanId(parts[3]) and parts[3] or nil
		return { type = "ack", tid = parts[2], plan = plan, version = version }
	elseif tag == "R" or tag == "F" or tag == "Q" or tag == "W" then
		return parseSync(tag, parts)
	elseif tag == "L" then
		return parseRoom(parts)
	elseif tag == "A" or tag == "D" or tag == "X" then
		if #parts ~= 2 or not validTid(parts[2]) then
			return nil
		end
		local types = { A = "accept", D = "decline", X = "cancel" }
		return { type = types[tag], tid = parts[2] }
	end
	return nil
end

-- Outgoing ----------------------------------------------------------------------------------------------------------------
-- States: offering -> sending -> done; or declined / expired / cancelled.
-- channel is "PARTY", "RAID", "INSTANCE_CHAT", "GUILD" or "WHISPER" (with target).

function Transfer.NewOutgoing(data, kind, name, channel, target, now)
	if #data > Transfer.MAX_BYTES then
		return nil, "too large"
	end
	local t = {
		dir = "out",
		state = "offering",
		tid = Transfer.NewTid(),
		kind = kind,
		name = name,
		channel = channel,
		target = target,
		data = data,
		sum = ns.Checksum.Hex(ns.Checksum.Adler32(data)),
		accepted = {},
		acceptCount = 0,
		started = now,
		deadline = now + Transfer.OFFER_TIMEOUT,
	}
	local offer = Transfer.Encode({
		type = "offer",
		proto = ns.PROTOCOL_VERSION,
		tid = t.tid,
		bytes = #data,
		sum = t.sum,
		kind = kind,
		name = name,
	})
	return t, { { "send", offer, channel, target } }
end

local function startSending(t)
	t.state = "sending"
	-- A whispered offer sends to the one receiver; a group offer sends once to the group channel, and only players
	-- who accepted keep the payload.
	local msg = Transfer.Encode({ type = "payload", tid = t.tid, data = t.data })
	return { { "sendPayload", t, msg }, { "status", t } }
end

-- A group offer sends its payload once, a few seconds after the first accept. A member who answers the prompt later
-- (it waits for the end of combat, and stays open for OFFER_TIMEOUT) missed that send: they get their own copy, whispered.
local function lateAccept(t, event)
	if t.channel == "WHISPER" or not event.from or t.accepted[event.from] then
		return {}
	end
	t.accepted[event.from] = true
	t.acceptCount = t.acceptCount + 1
	return { { "sendPayloadTo", t, Transfer.Encode({ type = "payload", tid = t.tid, data = t.data }), event.from }, { "status", t } }
end

function Transfer.StepOutgoing(t, event, now)
	local kind = event.type
	if t.state == "offering" then
		if kind == "accept" then
			if t.channel == "WHISPER" and event.from ~= t.target then
				return {}
			end
			if not t.accepted[event.from] then
				t.accepted[event.from] = true
				t.acceptCount = t.acceptCount + 1
			end
			if t.channel == "WHISPER" then
				return startSending(t)
			end
			t.sendAt = t.sendAt or (now + Transfer.GATHER)
			return { { "status", t } }
		elseif kind == "decline" then
			if t.channel == "WHISPER" and event.from == t.target then
				t.state = "declined"
				return { { "status", t } }
			end
			return {}
		elseif kind == "tick" then
			if t.sendAt and now >= t.sendAt then
				return startSending(t)
			end
			if now >= t.deadline then
				t.state = "expired"
				return { { "status", t } }
			end
			return {}
		elseif kind == "cancel" then
			t.state = "cancelled"
			return { { "send", Transfer.Encode({ type = "cancel", tid = t.tid }), t.channel, t.target }, { "status", t } }
		end
	elseif t.state == "sending" then
		if kind == "accept" then
			return lateAccept(t, event)
		elseif kind == "progress" then
			t.sent, t.total = event.sent, event.total
			return { { "status", t } }
		elseif kind == "sent" then
			t.state = "done"
			return { { "status", t } }
		elseif kind == "cancel" then
			t.state = "cancelled"
			return { { "send", Transfer.Encode({ type = "cancel", tid = t.tid }), t.channel, t.target }, { "status", t } }
		end
	elseif t.state == "done" and kind == "accept" then
		return lateAccept(t, event)
	end
	return {}
end

-- Incoming ----------------------------------------------------------------------------------------------------------------
-- States: prompt -> receiving -> done; or declined / failed / cancelled.

function Transfer.NewIncoming(offer, sender, channel, now)
	if offer.proto ~= ns.PROTOCOL_VERSION then
		return nil, "protocol"
	end
	if offer.bytes < 1 or offer.bytes > Transfer.MAX_BYTES then
		return nil, "too large"
	end
	local t = {
		dir = "in",
		state = "prompt",
		tid = offer.tid,
		sender = sender,
		channel = channel,
		kind = offer.kind,
		name = offer.name,
		bytes = offer.bytes,
		sum = offer.sum,
		deadline = now + Transfer.OFFER_TIMEOUT,
	}
	return t, { { "prompt", t } }
end

local function fail(t, reason)
	t.state = "failed"
	t.reason = reason
	return { { "status", t } }
end

function Transfer.StepIncoming(t, event, now)
	local kind = event.type
	if t.state == "prompt" then
		if kind == "accept" then
			t.state = "receiving"
			t.deadline = now + Transfer.RECEIVE_TIMEOUT
			return { { "send", Transfer.Encode({ type = "accept", tid = t.tid }), "WHISPER", t.sender }, { "status", t } }
		elseif kind == "decline" then
			t.state = "declined"
			return { { "send", Transfer.Encode({ type = "decline", tid = t.tid }), "WHISPER", t.sender }, { "status", t } }
		elseif kind == "cancel" then
			t.state = "cancelled"
			return { { "closePrompt", t }, { "status", t } }
		elseif kind == "tick" and now >= t.deadline then
			t.state = "declined"
			return { { "closePrompt", t }, { "status", t } }
		end
		-- A payload that arrives before the player answered is ignored; the sender waits for the accept.
		return {}
	elseif t.state == "receiving" then
		if kind == "payload" then
			if #event.data ~= t.bytes or ns.Checksum.Hex(ns.Checksum.Adler32(event.data)) ~= t.sum then
				return fail(t, "checksum")
			end
			t.state = "done"
			return { { "complete", t, event.data }, { "status", t } }
		elseif kind == "cancel" then
			t.state = "cancelled"
			return { { "status", t } }
		elseif kind == "tick" and now >= t.deadline then
			return fail(t, "timeout")
		end
	end
	return {}
end

function Transfer.IsFinished(t)
	return t.state ~= "offering" and t.state ~= "sending" and t.state ~= "prompt" and t.state ~= "receiving"
end
