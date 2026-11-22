-- The live "Getting there" map's lifecycle as a state machine (pure), and which entrances are learned from play. It
-- ticks (redraws the player's arrow, the bearing and the distance) only while its window is shown and the player is
-- outdoors: the client gives no position inside instances (docs/COMPATIBILITY.md section 10), and an idle addon costs
-- nothing.
--
--   state = { mode = "hidden" | "waiting" | "live", target = instance key | nil, inside = bool }
--     inside: the last world event put the player in the target instance (only arriving from outside counts)
--   TravelLive.Step(state, event) -> new state, effects
--   events: { kind = "show", target, outdoors, instances }  the window opened (outdoors: the client gives a position
--                                                            now; instances: the keys of the instance the player is in)
--           { kind = "hide" }                                the window closed
--           { kind = "world", outdoors, instances }          a loading screen or zone change ended
--           { kind = "tick", outdoors, player }              the ticker fired; outdoors false when the position is gone
--   instances: { [instance key] = true } (Travel.Here: by instance ID, not the localized name), or nil outdoors
--   effects: "start" (the ticker), "stop", "draw" (redraw now), "arrived" (the player went from outside into the
--            target instance: open its plan and run mode)

local _, ns = ...
local TravelLive = ns:NewModule("TravelLive")

TravelLive.INTERVAL = 0.1 -- seconds between redraws while live (10 Hz)

-- Entrances learned from play (per account, global.entrances): [instance key] = { map, x, y, at }, the spot on the
-- instance's zone map where the player stood before a loading screen that ended inside it; `at` is when it was learned.
-- Bounded and checked on load.
TravelLive.MAX_LEARNED = 100
-- A spot counts as the entrance only this near (world yards) to the bundled one, so a summon, a hearthstone or a portal
-- taken far from the entrance teaches nothing (one taken nearer can). Instances without a bundled entrance take a spot
-- on their zone's map.
TravelLive.LEARN_RADIUS = 400
-- A learned entrance is replaced only by a spot this near (world yards) to it; a later spot elsewhere keeps the first.
TravelLive.RELEARN_RADIUS = 100

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

-- Whether the spot the player left from can be this instance's entrance. last: { uiMapID, x, y, continent?, wx?, wy? }
-- (Travel.Player before the loading screen); ent: the bundled entrance (Travel.Bundled) or nil; zoneMap: the record's
-- zone map (uiMapID) or nil. The zone map alone counts only for a record with no bundled entrance: when the client
-- cannot place a bundled one in the world, nothing is learned.
function TravelLive.Accept(last, ent, zoneMap)
	if type(last) ~= "table" then
		return false
	end
	if ent then
		if not (ent.wx and last.wx and last.continent == ent.continent) then
			return false
		end
		local dx, dy = last.wx - ent.wx, last.wy - ent.wy
		return math.sqrt(dx * dx + dy * dy) <= TravelLive.LEARN_RADIUS
	end
	return zoneMap ~= nil and last.uiMapID == zoneMap
end

-- The one record to learn for: of the records of the instance entered (Travel.Here), those that accept the spot; nil
-- when none does, or when several do (wings with one shared entrance: the spot says nothing about which).
-- bundledOf(rec), zoneMapOf(rec): Travel.Bundled, Travel.ZoneMap.
function TravelLive.Choose(records, last, bundledOf, zoneMapOf)
	local hit
	for _, rec in ipairs(records or {}) do
		if TravelLive.Accept(last, bundledOf(rec), zoneMapOf(rec)) then
			if hit then
				return nil
			end
			hit = rec
		end
	end
	return hit
end

-- Files a spot (already on the record's zone map: { map, x, y }) under the instance. True when stored. When one is
-- learned already, the new spot replaces it only within RELEARN_RADIUS of it; apart(a, b) -> world yards between two
-- spots, or nil when the client cannot tell (then the first is kept).
function TravelLive.Learn(store, key, spot, now, apart)
	if type(store) ~= "table" or type(key) ~= "string" or type(spot) ~= "table" then
		return false
	end
	local fresh = TravelLive.NormalizeLearned({ [key] = { map = spot.map, x = spot.x, y = spot.y, at = now } })[key]
	if not fresh then
		return false
	end
	local old = store[key]
	if old then
		local yards = apart and apart(old, fresh)
		if not (yards and yards <= TravelLive.RELEARN_RADIUS) then
			return false
		end
	end
	store[key] = fresh
	return true
end

-- Forgets every learned entrance; returns how many there were.
function TravelLive.Forget(store)
	local n = 0
	for k in pairs(type(store) == "table" and store or {}) do
		store[k] = nil
		n = n + 1
	end
	return n
end

function TravelLive.New()
	return { mode = "hidden", inside = false }
end

local function to(state, mode, target, inside)
	return { mode = mode, target = target or state.target, inside = inside == true }
end

local function inTarget(target, instances)
	return target ~= nil and type(instances) == "table" and instances[target] == true
end

function TravelLive.Step(state, event)
	local mode = state.mode
	local kind = event.kind
	if kind == "show" then
		if event.outdoors then
			return to(state, "live", event.target, false), mode == "live" and { "draw" } or { "start", "draw" }
		end
		-- Opened while already inside the target: remembered, so it is no arrival.
		local inside = inTarget(event.target, event.instances)
		return to(state, "waiting", event.target, inside), mode == "live" and { "stop", "draw" } or { "draw" }
	elseif kind == "hide" then
		return to(state, "hidden"), mode == "live" and { "stop" } or {}
	elseif mode == "hidden" then
		return state, {} -- nothing runs while hidden; a stale tick changes nothing
	elseif kind == "world" then
		if inTarget(state.target, event.instances) then
			local fx = mode == "live" and { "stop" } or {}
			if not state.inside then
				fx[#fx + 1] = "arrived"
			end
			return to(state, "waiting", nil, true), fx
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
