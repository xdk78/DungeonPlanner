-- What became of the addon messages this session sent, per distribution: how many the game took, how many it refused,
-- the last refusal's result code when the library passes one, and how many refusals came in a row (Share/Comm.lua
-- records every part through AceComm's send callback). Pure: no game calls.
--
-- AceComm-3.0 (minor 14) forwards ChatThrottleLib's "sent" flag to the callback but not its result code
-- (Enum.SendAddonMessageResult), so with the vendored libraries a refusal is counted without a code; a library that
-- passes the number has it recorded. Throttled sends never reach the callback: ChatThrottleLib queues and retries them.
--
-- Bounded: one entry per distribution of a fixed list (anything else counts as "OTHER"); the counters are numbers.

local _, ns = ...
local SendStats = ns:NewModule("SendStats")

-- Refusals in a row on one distribution before sharing and group sync say the game refuses their messages.
SendStats.REFUSED_STREAK = 3

local DISTRIBUTIONS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, WHISPER = true }
SendStats.ORDER = { "PARTY", "RAID", "INSTANCE_CHAT", "GUILD", "WHISPER", "OTHER" }

function SendStats.New()
	return { by = {} }
end

-- The outcome AceComm's callback hands over: true / false (sent or not), a result code (0 = Success), or nil (an older
-- library that says nothing). Returns true (sent), false (refused, with the code or nil) or nil (unknown).
function SendStats.Outcome(result)
	if result == true or result == 0 then
		return true
	elseif result == false then
		return false, nil
	elseif type(result) == "number" then
		return false, result
	end
	return nil
end

-- Record one part sent on `channel`. Returns the outcome (SendStats.Outcome).
function SendStats.Record(stats, channel, result, now)
	local ok, code = SendStats.Outcome(result)
	if ok == nil then
		return nil
	end
	local key = DISTRIBUTIONS[channel] and channel or "OTHER"
	local e = stats.by[key]
	if not e then
		e = { sent = 0, refused = 0, streak = 0 }
		stats.by[key] = e
	end
	if ok then
		e.sent, e.streak = e.sent + 1, 0
	else
		e.refused, e.streak, e.code, e.at = e.refused + 1, e.streak + 1, code, now
	end
	return ok, code
end

-- Is the game refusing messages on `channel` (nil: on any distribution)? Returns the entry when it is.
function SendStats.Refusing(stats, channel)
	if channel then
		local e = stats.by[DISTRIBUTIONS[channel] and channel or "OTHER"]
		return e and e.streak >= SendStats.REFUSED_STREAK and e or nil
	end
	for _, key in ipairs(SendStats.ORDER) do
		local e = stats.by[key]
		if e and e.streak >= SendStats.REFUSED_STREAK then
			return e
		end
	end
	return nil
end

-- One plain line for /dp debug and /dp report: "PARTY 12 sent, 3 refused (last code 7, 3 in a row); WHISPER 2 sent".
function SendStats.Describe(stats)
	local parts = {}
	for _, key in ipairs(SendStats.ORDER) do
		local e = stats.by[key]
		if e then
			local text = string.format("%s %d sent", key, e.sent)
			if e.refused > 0 then
				text = text .. string.format(", %d refused (last code %s%s)", e.refused, e.code and tostring(e.code) or "not given",
					e.streak > 0 and string.format(", %d in a row", e.streak) or "")
			end
			parts[#parts + 1] = text
		end
	end
	return #parts > 0 and table.concat(parts, "; ") or "nothing sent yet"
end
