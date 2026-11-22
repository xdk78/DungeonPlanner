-- Provider: Polestar's navigation, through its public API (Polestar.Nav.API, version 1): Navigate(owner, uiMapID, x, y,
-- title) sets the target of its arrow and walking route (x, y 0..1), Estimate(fromMap, fromX, fromY, toMap, toX, toY)
-- gives its travel time in seconds (nil from = the player), Cancel(owner) clears a target we set. Polestar is GPL-3.0:
-- only its public calls are made at runtime; nothing is copied. Shortest Path Forever's router lives on inside
-- Polestar_Nav; Shortest Path Forever itself documents no destination API (docs/COMPATIBILITY.md section 6).

local _, ns = ...
local Providers = ns.Providers

local A = {
	id = "polestar",
	addon = "Polestar",
	title = "Polestar",
	internals = false,
	provides = { "navigation" },
}

A.OWNER = "DungeonPlanner"
A.VERSION = 1

function A.Detect()
	local p = rawget(_G, "Polestar")
	local api = type(p) == "table" and type(p.Nav) == "table" and p.Nav.API
	if type(api) == "table" and api.version == A.VERSION and type(api.Navigate) == "function" then
		return api
	end
	return nil
end

function A.Waypoints(api, points)
	local last = points[#points]
	if not last then
		return 0
	end
	-- Polestar plans the whole way itself (flights, boats): it takes the destination only.
	return api.Navigate(A.OWNER, last[1], last[2], last[3], last[4]) == true and 1 or 0
end

-- Seconds from the player to a spot, or nil.
function A.Estimate(api, uiMapID, x, y)
	if type(api.Estimate) ~= "function" then
		return nil
	end
	local s = api.Estimate(nil, nil, nil, uiMapID, x, y)
	return type(s) == "number" and s == s and s >= 0 and s or nil
end

function A.Counts()
	return {}
end

Providers.Register(A)
