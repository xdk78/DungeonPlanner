-- Every floor of an instance that can be shown, not only the floors a plan names. A plan stores the floors it was made
-- with (Model/Plan.lua); the instance may have more map art: the old dungeon map tiles (Data/GameFiles.lua), Santiago
-- Reyes' maps (Data/ReyesMaps.lua: Atal'Byzal, the Maximum Security Unit, the Prismatic Talus are in no recommended
-- plan) and the game's minimap pictures (Data/MinimapArt.lua). The map shows the merged list: the plan's floors first,
-- in their order (so markers keep their floor numbers), then the art floors no plan floor stands for.
--
-- A floor that shows art other than the art at its own position carries `art` (that art's position in the instance's
-- art): an extra floor always does (with `extra = true`), and keeps it when Floors.Ensure makes it the plan's own. The
-- field is optional, so an older reader drops it and shows the art at the floor's position. GameFiles.FloorArt,
-- MinimapArt.FloorArt, ReyesMaps.Pick and Providers.PickFloor take the art at `art` when it is set, else at the floor's
-- position. Floors.View(plan) is the plan as the map draws it (the merged floors
-- over the plan); Floors.Ensure adds the extra floors up to one to an own plan when something is put on it.

local _, ns = ...
local Floors = ns:NewModule("Floors")

-- A plan floor that stands for the zone outside (no name, its own map): it has no dungeon art.
function Floors.IsOutside(floor)
	return type(floor) == "table" and (floor.name or "") == "" and floor.uiMapID ~= nil
end

-- The instance's art floors by position: { { label = Reyes' name or nil } }, as many as its richest source has.
function Floors.Art(name)
	local out = {}
	if type(name) ~= "string" or name == "" then
		return out
	end
	local tiles = ns.GameFiles.MapTiles(name) or {}
	local reyes = ns.ReyesMaps.Floors(name) or {}
	local mini = 0
	while ns.MinimapArt.Data(name, mini + 1) do
		mini = mini + 1
	end
	for i = 1, math.max(#tiles, #reyes, mini) do
		out[i] = { label = reyes[i] and reyes[i].label or nil, reyes = reyes[i] }
	end
	return out
end

-- Pure: the plan's floors, then the art floors none of them stands for. `art` = Floors.Art(...); `picks[i]` = the
-- Reyes floor plan floor i shows (ReyesMaps.Pick), if any. An art floor at position i is the plan's when a dungeon
-- floor of the plan (not the zone outside) names it (`art = i`), or has no `art` and stands at position i, or when a
-- plan floor already shows its Reyes map. Returns a new list; the plan's own floor tables are in it unchanged.
function Floors.Merge(planFloors, art, picks)
	local out, shown, covered = {}, {}, {}
	for i, f in ipairs(planFloors or {}) do
		out[i] = f
		if picks and picks[i] then
			shown[picks[i]] = true
		end
		if not Floors.IsOutside(f) then
			covered[f.art or i] = true
		end
	end
	for i, a in ipairs(art or {}) do
		if not covered[i] and not (a.reyes ~= nil and shown[a.reyes]) and #out < ns.Schema.MAX.floors then
			out[#out + 1] = { name = a.label or "", extra = true, art = i }
		end
	end
	return out
end

local cache = setmetatable({}, { __mode = "k" })

-- The merged floors of a plan (cached per plan revision).
function Floors.For(plan)
	if type(plan) ~= "table" or type(plan.floors) ~= "table" then
		return {}
	end
	local c = cache[plan]
	local stamp = tostring(plan.updated or 0) .. ":" .. #plan.floors
	if c and c.stamp == stamp then
		return c.list
	end
	local name = plan.instance and plan.instance.name
	local picks = {}
	for i = 1, #plan.floors do
		picks[i] = ns.ReyesMaps.Pick(plan, i)
	end
	local list = Floors.Merge(plan.floors, Floors.Art(name), picks)
	cache[plan] = { stamp = stamp, list = list }
	return list
end

-- How many floors the map can show for a plan (the home table's "Floors").
function Floors.Count(plan)
	return #Floors.For(plan)
end

-- The plan as the map draws floor art for it: its fields, with the merged floors. Read-only use.
function Floors.View(plan)
	if type(plan) ~= "table" then
		return plan
	end
	local list = Floors.For(plan)
	if #list == #plan.floors then
		return plan
	end
	-- The same table while the list stands (the map's art caches look plans up by table).
	local c = cache[plan]
	if not c.view then
		c.view = setmetatable({ floors = list }, { __index = plan })
	end
	return c.view
end

-- Before something is put on floor `index` of an own plan: the extra floors up to it become the plan's own (with their
-- names and the art they show; an unnamed one shows as "Floor N"). Returns the number of floors the plan had before
-- (for Floors.Unensure), or nil when the plan did not change.
function Floors.Ensure(plan, index)
	if type(plan) ~= "table" or type(index) ~= "number" or index <= #plan.floors then
		return nil
	end
	local list = Floors.For(plan)
	if not list[index] then
		return nil
	end
	local before = #plan.floors
	for k = before + 1, index do
		plan.floors[k] = { name = list[k].name or "", art = list[k].art }
	end
	return before
end

-- Undo Floors.Ensure when the add it was for failed: the plan keeps its first `before` floors.
function Floors.Unensure(plan, before)
	if type(plan) ~= "table" or type(before) ~= "number" then
		return
	end
	for k = #plan.floors, before + 1, -1 do
		plan.floors[k] = nil
	end
end

-- The player's floor -------------------------------------------------------------------------------------------------
-- UNVERIFIED on Forever: the 2026-11-15 scan in Hall of Thanes found C_Map.GetBestMapForUnit nil inside, but another
-- addon's recorder expects a uiMap inside Forever's new dungeons (it logs C_Map.GetMapGroupID and each group member's
-- relativeHeightIndex). /dp scan records all of it (Data/Diagnostics.lua position); until a scan shows a map, this
-- finds nothing and nothing switches.

-- The player's map and its floor group: { map = uiMapID, group = id or nil, members = { { uiMapID, name,
-- relativeHeightIndex } } }, or nil when the client gives no map (every call guarded, secret values dropped).
function Floors.PlayerMap()
	local api = rawget(_G, "C_Map")
	local Plain = ns.Util.Plain
	if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function" then
		return nil
	end
	local ok, map = pcall(api.GetBestMapForUnit, "player")
	map = ok and Plain(map) or nil
	if type(map) ~= "number" then
		return nil
	end
	local out = { map = map, members = {} }
	if type(api.GetMapGroupID) == "function" then
		local okG, group = pcall(api.GetMapGroupID, map)
		group = okG and Plain(group) or nil
		out.group = type(group) == "number" and group or nil
	end
	if out.group and type(api.GetMapGroupMembersInfo) == "function" then
		local okM, members = pcall(api.GetMapGroupMembersInfo, out.group)
		members = okM and Plain(members) or nil
		for _, m in ipairs(type(members) == "table" and members or {}) do
			if type(m) == "table" and type(Plain(m.mapID)) == "number" then
				out.members[#out.members + 1] = { uiMapID = Plain(m.mapID), name = Plain(m.name),
					relativeHeightIndex = Plain(m.relativeHeightIndex) }
			end
		end
	end
	return out
end

-- Pure: which of `floors` (Floors.For) the player stands on, given `where` (Floors.PlayerMap): the floor with that
-- uiMapID, else the one named like the map's group member. nil when none.
function Floors.Match(floors, where)
	if type(where) ~= "table" then
		return nil
	end
	for i, f in ipairs(floors or {}) do
		if f.uiMapID ~= nil and f.uiMapID == where.map then
			return i
		end
	end
	local name
	for _, m in ipairs(where.members or {}) do
		if m.uiMapID == where.map and type(m.name) == "string" then
			name = ns.Match.StripArticle(m.name)
		end
	end
	if name and name ~= "" then
		for i, f in ipairs(floors or {}) do
			if ns.Match.StripArticle(f.name or "") == name then
				return i
			end
		end
	end
	return nil
end

-- The floor of `plan` the player is on, or nil.
function Floors.PlayerFloor(plan)
	return Floors.Match(Floors.For(plan), Floors.PlayerMap())
end

function Floors.Reset()
	cache = setmetatable({}, { __mode = "k" })
end
