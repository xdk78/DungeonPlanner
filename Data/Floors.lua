-- Every floor of an instance that can be shown, not only the floors a plan names. A plan stores the floors it was made
-- with (Model/Plan.lua); the instance may have more map art: the old dungeon map tiles (Data/GameFiles.lua), Santiago
-- Reyes' maps (Data/ReyesMaps.lua: Atal'Byzal, the Maximum Security Unit, the Prismatic Talus are in no recommended
-- plan) and the game's minimap pictures (Data/MinimapArt.lua). The map shows the merged list: the plan's floors first,
-- in their order (so markers keep their floor numbers), then the art floors no plan floor stands for.
--
-- An extra floor carries `artIndex` (its position in the instance's art) and `extra = true`; GameFiles.FloorArt and
-- MinimapArt.FloorArt take the art at `artIndex`, ReyesMaps.Pick finds it by its name. Floors.View(plan) is the plan as
-- the map draws it (the merged floors over the plan); Floors.Ensure adds the extra floors up to one to an own plan when
-- something is put on it.

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
-- Reyes floor plan floor i shows (ReyesMaps.Pick), if any. An art floor at position i is the plan's when plan floor i is
-- a dungeon floor (not the zone outside), or when a plan floor already shows its Reyes map. Returns a new list; the
-- plan's own floor tables are in it unchanged.
function Floors.Merge(planFloors, art, picks)
	local out, shown = {}, {}
	for i, f in ipairs(planFloors or {}) do
		out[i] = f
		if picks and picks[i] then
			shown[picks[i]] = true
		end
	end
	for i, a in ipairs(art or {}) do
		local own = planFloors and planFloors[i]
		local covered = (own ~= nil and not Floors.IsOutside(own)) or (a.reyes ~= nil and shown[a.reyes])
		if not covered and #out < ns.Schema.MAX.floors then
			out[#out + 1] = { name = a.label or "", extra = true, artIndex = i }
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
-- names; an unnamed one shows as "Floor N"). Returns true when the plan changed.
function Floors.Ensure(plan, index)
	if type(plan) ~= "table" or type(index) ~= "number" or index <= #plan.floors then
		return false
	end
	local list = Floors.For(plan)
	if not list[index] then
		return false
	end
	for k = #plan.floors + 1, index do
		plan.floors[k] = { name = list[k].name or "" }
	end
	return true
end

function Floors.Reset()
	cache = setmetatable({}, { __mode = "k" })
end
