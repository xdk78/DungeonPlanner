-- Provider: Shortest Path Forever's route, through its public API ShortestPathForever.API (version 1 or 2; a later
-- version is treated as absent): Navigate(owner, uiMapID, x, y, title) and Cancel(owner), each checked before it is
-- called. GPL-3.0-or-later: only its public calls are made at runtime; nothing is copied. The call shape is inferred
-- from Polestar's integration and not yet verified against Shortest Path Forever itself (docs/COMPATIBILITY.md section 6).

local _, ns = ...
local Providers = ns.Providers

local A = {
	id = "shortestPath",
	addon = "ShortestPathForever",
	title = "Shortest Path Forever",
	internals = false,
	provides = { "navigation" },
}

A.OWNER = "DungeonPlanner"

function A.Detect()
	local s = rawget(_G, "ShortestPathForever")
	local api = type(s) == "table" and s.API
	if type(api) ~= "table" or (api.version ~= 1 and api.version ~= 2) or type(api.Navigate) ~= "function"
		or type(api.Cancel) ~= "function" then
		return nil
	end
	return api
end

function A.Waypoints(api, points)
	local last = points[#points]
	if not last then
		return 0
	end
	return api.Navigate(A.OWNER, last[1], last[2], last[3], last[4]) and 1 or 0
end

function A.Counts()
	return {}
end

Providers.Register(A)
