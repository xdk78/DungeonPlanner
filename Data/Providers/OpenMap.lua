-- Provider: OpenMap (MIT). Its public API (OpenMapAPI, major 1) has no call that returns dungeon maps or boss
-- positions, so this adapter reads its INTERNAL data tables on the namespace it publishes as the global `OpenMap`
-- (Core.lua: `_G.OpenMap = ns`), with shape checks. Read at runtime only; nothing is copied.
--
--   MapPlaces.instances[i] = { continent, x, y, { { instance mapID, name, raid, minLevel, maxLevel }, ... } }
--   MapDungeonDrawn[instance mapID or name] = { { tiles = { 12 texture paths, 4 x 3 }, name?, credit? }, ... }
--     players' drawings of Forever's new dungeons, laid out like the game's dungeon maps (1002 x 668 in 256 px tiles)
--   MapDungeonBosses[instance mapID or name] = { [boss name] = { floor, x, y } }   (x, y 0..1 of that floor's picture)
--     ["minimap:<mapID>"] = the same on its maps built from the minimap pictures
--   MapDungeonMaps[instance mapID] = { { tiles = { 12 game file IDs }, name?, wing? }, ... }   the game's own dungeon maps
--   MapDungeonMinimap[instance mapID] = { { tiles = { 12 textures }, name }, ... }   its maps from the minimap pictures
--
-- The experimental overlay on OpenMap's own dungeon view (UI/OpenMapOverlay.lua) asks Placement() where a plan floor
-- goes on the floor that view shows; see "OpenMap's dungeon view" below.

local _, ns = ...
local Providers = ns.Providers
local Util = ns.Util

local A = {
	id = "openMap",
	addon = "OpenMap",
	title = "OpenMap",
	internals = true,
	provides = { "map", "pins" },
}

local index -- [instance key] = { mapID, name }

function A.Reset()
	index = nil
end

function A.Detect()
	local root = rawget(_G, "OpenMap")
	if type(root) ~= "table" or type(root.MapPlaces) ~= "table" or type(root.MapPlaces.instances) ~= "table" then
		return nil
	end
	if type(root.MapDungeonDrawn) ~= "table" and type(root.MapDungeonBosses) ~= "table"
		and type(root.MapDungeonMaps) ~= "table" and type(root.MapDungeonMinimap) ~= "table" then
		return nil
	end
	return root
end

local function instanceOf(root, plan)
	if not index then
		index = {}
		for _, place in ipairs(root.MapPlaces.instances) do
			local list = type(place) == "table" and place[4]
			for _, inst in ipairs(type(list) == "table" and list or {}) do
				local name = type(inst) == "table" and inst[2]
				local k = type(name) == "string" and Providers.Key(name)
				if k and not index[k] then
					index[k] = { mapID = Util.IsInteger(inst[1]) and inst[1] > 0 and inst[1] or nil, name = name }
				end
			end
		end
	end
	local k = Providers.PlanKey(plan)
	return k and index[k] or nil
end
A.InstanceOf = instanceOf

local function lookup(t, inst)
	if type(t) ~= "table" or not inst then
		return nil
	end
	local v = (inst.mapID and t[inst.mapID]) or t[inst.name]
	return type(v) == "table" and v or nil
end

function A.FloorArt(root, plan, floor)
	local inst = instanceOf(root, plan)
	local floors = lookup(root.MapDungeonDrawn, inst)
	-- The drawing of the same name (its name, else the words of its first tile's file name), else the same position.
	local f, at = Providers.PickFloor(plan, floor, floors, function(c)
		if type(c) ~= "table" then
			return nil
		end
		local first = type(c.tiles) == "table" and c.tiles[1]
		return c.name, type(first) == "string" and first or nil
	end)
	if type(f) ~= "table" or type(f.tiles) ~= "table" or #f.tiles ~= 12 then
		return nil
	end
	for _, t in ipairs(f.tiles) do
		if type(t) ~= "string" and type(t) ~= "number" then
			return nil
		end
	end
	local art = { width = ns.GameFiles.MAP_WIDTH, height = ns.GameFiles.MAP_HEIGHT, tileWidth = 256, tileHeight = 256,
		textures = f.tiles, artist = type(f.credit) == "string" and Util.CleanText(f.credit, 48) or nil }
	local pins = {}
	for name, p in pairs(lookup(root.MapDungeonBosses, inst) or {}) do
		if type(name) == "string" and type(p) == "table" and p[1] == at and Providers.IsNumber01(p[2])
			and Providers.IsNumber01(p[3]) then
			pins[#pins + 1] = { name = name, x = p[2], y = p[3] }
		end
	end
	table.sort(pins, function(a, b)
		return a.name < b.name
	end)
	return art, pins
end

local function floorCount(t)
	local n = 0
	for _, floors in pairs(type(t) == "table" and t or {}) do
		n = n + (type(floors) == "table" and #floors or 0)
	end
	return n
end

function A.Counts(root)
	local pins = 0
	for _, bosses in pairs(type(root.MapDungeonBosses) == "table" and root.MapDungeonBosses or {}) do
		pins = pins + (type(bosses) == "table" and Util.Count(bosses) or 0)
	end
	return { maps = floorCount(root.MapDungeonDrawn), pins = pins, gameMaps = floorCount(root.MapDungeonMaps),
		minimapMaps = floorCount(root.MapDungeonMinimap) }
end

-- OpenMap's dungeon view --------------------------------------------------------------------------------------------
-- On WoW: Forever OpenMap shows a dungeon's map in a view of its own (the frame OpenMapDungeonView, private). The
-- overlay (UI/OpenMapOverlay.lua) reads what that view shows into a plain snapshot, s = { floor = index, floors = the
-- list shown (each { tiles, name? }), inst = { mapID, name }, source = "blizzard" | "drawn" | "minimap" | nil }, and asks
-- here where a plan goes on it. Nothing is guessed: a floor that cannot be placed draws nothing.
--   1. A floor of the game's own dungeon maps whose first tile is the plan floor's first old map tile (file IDs,
--      GameFiles): the same picture, drawn as it is.
--   2. Else the plan floor matched by name (Providers.PickFloor, OpenMap's floor names), placed through the plan's
--      boss markers paired with OpenMap's boss positions on that floor (Providers.Align): "same" or "fit".
--   3. Else nothing.

-- Which of OpenMap's tables the shown floors come from (its own word for it when it gives one).
function A.ViewSource(root, s)
	if s.source == "blizzard" or s.source == "drawn" or s.source == "minimap" then
		return s.source
	end
	local id = s.inst.mapID
	for source, t in pairs({ blizzard = root.MapDungeonMaps, minimap = root.MapDungeonMinimap, drawn = root.MapDungeonDrawn }) do
		if type(t) == "table" and ((id and t[id] == s.floors) or t[s.inst.name] == s.floors) then
			return source
		end
	end
	return nil
end

-- OpenMap's boss positions on the shown floor: { { name, x, y } } (0..1 of its picture), sorted by name.
function A.ViewPins(root, s)
	local bosses = type(root.MapDungeonBosses) == "table" and root.MapDungeonBosses or {}
	local id = s.inst.mapID
	local list
	if A.ViewSource(root, s) == "minimap" then
		list = id and bosses["minimap:" .. id]
	else
		list = (id and id ~= 0 and bosses[id]) or bosses[s.inst.name]
	end
	local out = {}
	for name, p in pairs(type(list) == "table" and list or {}) do
		if type(name) == "string" and type(p) == "table" and p[1] == s.floor and Providers.IsNumber01(p[2])
			and Providers.IsNumber01(p[3]) then
			out[#out + 1] = { name = name, x = p[2], y = p[3] }
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- The file ID of a texture (a number, or a path the client knows).
local function fileID(t)
	if Util.IsInteger(t) and t > 0 then
		return t
	end
	return type(t) == "string" and ns.GameFiles.FileID(t) or nil
end

-- The plan floor the shown floor is: index, how ("tile": the same picture | "name"), or nil.
function A.ViewFloor(root, plan, s)
	local shown = s.floors[s.floor]
	local first = type(shown) == "table" and type(shown.tiles) == "table" and fileID(shown.tiles[1]) or nil
	if first and A.ViewSource(root, s) ~= "minimap" then
		for i = 1, #plan.floors do
			local art = ns.GameFiles.FloorArt(plan, i)
			if art and fileID(art.textures[1]) == first then
				return i, "tile"
			end
		end
	end
	for i = 1, #plan.floors do
		local _, at = Providers.PickFloor(plan, i, s.floors, function(c)
			if type(c) ~= "table" then
				return nil
			end
			local t = type(c.tiles) == "table" and c.tiles[1]
			return type(c.name) == "string" and c.name or nil, type(t) == "string" and t or nil
		end)
		if at == s.floor then
			return i, "name"
		end
	end
	return nil
end

-- Where the plan goes on the shown floor: { floor = plan floor, how, mode = "tile" | "same" | "fit", xf = the
-- alignment for "fit" (plan -> picture, MinimapArt.ToMap's shape) or nil, pins = OpenMap's boss positions }, or nil
-- and a reason for /dp debug.
function A.Placement(root, plan, s)
	if type(plan) ~= "table" or type(s) ~= "table" or type(s.floors) ~= "table" or type(s.inst) ~= "table" then
		return nil, "nothing to place"
	end
	local floor, how = A.ViewFloor(root, plan, s)
	if not floor then
		return nil, "no floor of the plan matches this floor"
	end
	local pins = A.ViewPins(root, s)
	if how == "tile" then
		return { floor = floor, how = how, mode = "tile", pins = pins }
	end
	local list = Providers.BossPairs(plan, floor, pins)
	if #list == 0 then
		return nil, "no boss positions to line the plan up with"
	end
	local a = Providers.Align(list)
	if a.mode == "same" then
		return { floor = floor, how = how, mode = "same", pins = pins }
	elseif a.mode == "fit" then
		return { floor = floor, how = how, mode = "fit", xf = a, pins = pins }
	end
	return nil, "the plan's bosses do not line up with OpenMap's"
end

Providers.Register(A)
