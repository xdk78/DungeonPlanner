-- Navigation: sending a spot (an instance entrance, a flight master) to whatever can guide the player there. The game's
-- own map pin (C_Map.SetUserWaypoint with super-tracking) always, plus the navigation providers that are installed and
-- switched on, best first: Polestar (Data/Providers/Polestar.lua), Shortest Path Forever (ShortestPathForever.lua),
-- TomTom (TomTom.lua). One "Navigate" button uses the best of them; its menu lists the others.
--
-- Rules (docs/COMPATIBILITY.md, "Navigation and the world map"): nothing is sent in combat or while dead; the world map
-- opens only through C_Map.OpenWorldMap (the global OpenWorldMap taints the map frame), never in combat and never with
-- the gamepad interface style; nothing is written into the world map's frames or tables.
--
--   Navigation.Targets(uiMapID)          -> { { id, title } } available, best first
--   Navigation.Go(id, points)            -> true when the target took it; points = { { uiMapID, x, y, title } }
--   Navigation.SetGameWaypoint(map, x, y) -> true when the game's pin was set
--   Navigation.ShowOnMap(map, x, y)      -> sets the pin and opens the world map on that zone
--   Navigation.CanOpenMap()              -> false in combat, with the gamepad style, or without C_Map.OpenWorldMap

local _, ns = ...
local Navigation = ns:NewModule("Navigation")
local Util = ns.Util

Navigation.PROVIDERS = { "polestar", "shortestPath", "tomtom" }

local function plainCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	return ok and Util.Plain(v) or nil
end

-- Not now: in combat or dead (another addon's route or the map would be driven from a restricted state).
-- Navigation.BlockReason() -> "combat", "dead" or nil.
function Navigation.BlockReason()
	if plainCall(rawget(_G, "InCombatLockdown")) == true then
		return "combat"
	elseif plainCall(rawget(_G, "UnitIsDeadOrGhost"), "player") == true then
		return "dead"
	end
	return nil
end

function Navigation.Blocked()
	return Navigation.BlockReason() ~= nil
end

-- No world map opening under the gamepad interface style (Compat.Gamepad).
function Navigation.CanOpenMap()
	local m = rawget(_G, "C_Map")
	return m ~= nil and type(m.OpenWorldMap) == "function" and not ns.Compat.Gamepad() and not Navigation.Blocked()
end

local function canPin(uiMapID)
	local m = rawget(_G, "C_Map")
	local point = rawget(_G, "UiMapPoint")
	if not (m and type(m.SetUserWaypoint) == "function" and point and type(point.CreateFromCoordinates) == "function"
		and Util.IsInteger(uiMapID)) then
		return false
	end
	if type(m.CanSetUserWaypointOnMap) == "function" then
		return plainCall(m.CanSetUserWaypointOnMap, uiMapID) == true
	end
	return true
end
Navigation.CanPin = canPin

function Navigation.SetGameWaypoint(uiMapID, x, y)
	if Navigation.Blocked() or not canPin(uiMapID) then
		return false
	end
	local ok, point = pcall(UiMapPoint.CreateFromCoordinates, uiMapID, x, y)
	if not ok or not point or not pcall(C_Map.SetUserWaypoint, point) then
		return false
	end
	local st = rawget(_G, "C_SuperTrack")
	if st and type(st.SetSuperTrackedUserWaypoint) == "function" then
		pcall(st.SetSuperTrackedUserWaypoint, true)
	end
	return true
end

-- The world map on the zone, with the pin set.
function Navigation.ShowOnMap(uiMapID, x, y)
	local pinned = Navigation.SetGameWaypoint(uiMapID, x, y)
	if Navigation.CanOpenMap() then
		pcall(C_Map.OpenWorldMap, uiMapID)
	end
	return pinned
end

function Navigation.Targets(uiMapID)
	local out = {}
	for _, id in ipairs(Navigation.PROVIDERS) do
		local a = ns.Providers.Get(id)
		if a then
			out[#out + 1] = { id = id, title = a.title }
		end
	end
	if canPin(uiMapID) then
		out[#out + 1] = { id = "game", title = ns.L["Map pin"] }
	end
	return out
end

function Navigation.Go(id, points)
	if type(points) ~= "table" or #points == 0 or Navigation.Blocked() then
		return false
	end
	if id == "game" then
		local last = points[#points]
		return Navigation.SetGameWaypoint(last[1], last[2], last[3])
	end
	local n = ns.Providers.Call(id, "Waypoints", points)
	return type(n) == "number" and n > 0
end

-- Seconds to a spot from Polestar's router when it is installed (flights and boats counted), else nil.
function Navigation.Estimate(uiMapID, x, y)
	return ns.Providers.Call("polestar", "Estimate", uiMapID, x, y)
end
