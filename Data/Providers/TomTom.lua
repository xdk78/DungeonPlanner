-- Provider: TomTom's waypoint arrow, through its public method TomTom:AddWaypoint(uiMapID, x, y, opts) (x, y 0..1;
-- opts.title, opts.from). Prep's "Navigate" sends the instance entrance, or the nearest flight master and then the
-- entrance as a chain. Nothing is read from TomTom's tables.

local _, ns = ...
local Providers = ns.Providers

local A = {
	id = "tomtom",
	addon = "TomTom",
	title = "TomTom",
	internals = false,
	provides = { "navigation" },
}

-- The real TomTom only: Polestar can install a stand-in global `TomTom`, so the addon itself must be loaded (when the
-- client can say).
function A.Detect()
	local t = rawget(_G, "TomTom")
	if Providers.AddonLoaded(A.addon) == false then
		return nil
	end
	if type(t) == "table" and type(t.AddWaypoint) == "function" then
		return t
	end
	return nil
end

-- points: { { uiMapID, x, y, title }, ... } in the order to walk them. Returns how many TomTom took.
function A.Waypoints(t, points)
	local n = 0
	for _, p in ipairs(points) do
		local uid = t:AddWaypoint(p[1], p[2], p[3], { title = p[4], from = "Dungeon Planner", persistent = false })
		if uid ~= nil then
			n = n + 1
		end
	end
	return n
end

function A.Counts()
	return {}
end

Providers.Register(A)
