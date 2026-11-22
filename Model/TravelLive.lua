-- The live "Getting there" map's lifecycle as a state machine (pure). It ticks (redraws the player's arrow, the
-- bearing and the distance) only while its window is shown and the player is outdoors: the client gives no position
-- inside instances (docs/COMPATIBILITY.md section 10), and an idle addon costs nothing.
--
--   state = { mode = "hidden" | "waiting" | "live", target = instance key | nil }
--   TravelLive.Step(state, event) -> new state, effects
--   events: { kind = "show", target, outdoors }  the window opened (outdoors: the client gives a position now)
--           { kind = "hide" }                     the window closed
--           { kind = "world", outdoors, instance } a loading screen or zone change ended; instance: the key of the
--                                                 instance the player is in, or nil
--           { kind = "tick", outdoors }           the ticker fired; outdoors false when the position is gone
--   effects: "start" (the ticker), "stop", "draw" (redraw now), "arrived" (the player entered the target instance:
--            open its plan and run mode)

local _, ns = ...
local TravelLive = ns:NewModule("TravelLive")

TravelLive.INTERVAL = 0.1 -- seconds between redraws while live (10 Hz)

-- Entrances learned from play (per account, global.entrances): [instance key] = { map, x, y, at }, the last outdoor
-- spot before a loading screen that ended inside that instance. Bounded and checked on load.
TravelLive.MAX_LEARNED = 100

function TravelLive.NormalizeLearned(t)
	local out, n = {}, 0
	if type(t) ~= "table" then
		return out
	end
	local Util = ns.Util
	for k, v in pairs(t) do
		if n >= TravelLive.MAX_LEARNED then
			break
		end
		if type(k) == "string" and #k <= 64 and type(v) == "table" and Util.IsInteger(v.map) and v.map > 0
			and Util.IsFiniteNumber(v.x) and Util.IsFiniteNumber(v.y) and v.x >= 0 and v.x <= 1 and v.y >= 0 and v.y <= 1 then
			out[k] = { map = v.map, x = Util.Round(v.x, 4), y = Util.Round(v.y, 4), at = Util.IsInteger(v.at) and v.at or 0 }
			n = n + 1
		end
	end
	return out
end

-- What to remember at a loading screen's end: the spot before it, filed under the instance it ended in. A spot older
-- than MAX_AGE seconds (a hearthstone, a portal elsewhere) is not the entrance.
TravelLive.MAX_AGE = 120
function TravelLive.Learn(store, key, last, now)
	if type(store) ~= "table" or type(key) ~= "string" or type(last) ~= "table" or not last.map then
		return false
	end
	if (now or 0) - (last.at or 0) > TravelLive.MAX_AGE then
		return false
	end
	local fresh = TravelLive.NormalizeLearned({ [key] = { map = last.map, x = last.x, y = last.y, at = now } })[key]
	if not fresh then
		return false
	end
	store[key] = fresh
	return true
end

function TravelLive.New()
	return { mode = "hidden" }
end

local function to(state, mode, target)
	return { mode = mode, target = target or state.target }
end

function TravelLive.Step(state, event)
	local mode = state.mode
	local kind = event.kind
	if kind == "show" then
		if event.outdoors then
			return to(state, "live", event.target), mode == "live" and { "draw" } or { "start", "draw" }
		end
		return to(state, "waiting", event.target), mode == "live" and { "stop", "draw" } or { "draw" }
	elseif kind == "hide" then
		return to(state, "hidden"), mode == "live" and { "stop" } or {}
	elseif mode == "hidden" then
		return state, {} -- nothing runs while hidden; a stale tick changes nothing
	elseif kind == "world" then
		if event.instance and state.target and event.instance == state.target then
			return to(state, "waiting"), mode == "live" and { "stop", "arrived" } or { "arrived" }
		end
		if event.outdoors then
			return to(state, "live"), mode == "live" and { "draw" } or { "start", "draw" }
		end
		return to(state, "waiting"), mode == "live" and { "stop", "draw" } or { "draw" }
	elseif kind == "tick" then
		if mode ~= "live" then
			return state, {}
		end
		if event.outdoors then
			return state, { "draw" }
		end
		return to(state, "waiting"), { "stop", "draw" }
	end
	return state, {}
end
