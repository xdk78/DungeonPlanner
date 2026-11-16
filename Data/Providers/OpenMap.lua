-- Provider: OpenMap (MIT). Its public API (OpenMapAPI, major 1) has no call that returns dungeon maps or boss
-- positions, so this adapter reads its INTERNAL data tables on the namespace it publishes as the global `OpenMap`
-- (Core.lua: `_G.OpenMap = ns`), with shape checks. Read at runtime only; nothing is copied.
--
--   MapPlaces.instances[i] = { continent, x, y, { { instance mapID, name, raid, minLevel, maxLevel }, ... } }
--   MapDungeonDrawn[instance mapID or name] = { { tiles = { 12 texture paths, 4 x 3 }, name?, credit? }, ... }
--     players' drawings of Forever's new dungeons, laid out like the game's dungeon maps (1002 x 668 in 256 px tiles)
--   MapDungeonBosses[instance mapID or name] = { [boss name] = { floor, x, y } }   (x, y 0..1 of that floor's picture)

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
	if type(root.MapDungeonDrawn) ~= "table" and type(root.MapDungeonBosses) ~= "table" then
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

function A.Counts(root)
	local maps, pins = 0, 0
	for _, floors in pairs(type(root.MapDungeonDrawn) == "table" and root.MapDungeonDrawn or {}) do
		maps = maps + (type(floors) == "table" and #floors or 0)
	end
	for _, bosses in pairs(type(root.MapDungeonBosses) == "table" and root.MapDungeonBosses or {}) do
		pins = pins + (type(bosses) == "table" and Util.Count(bosses) or 0)
	end
	return { maps = maps, pins = pins }
end

Providers.Register(A)
