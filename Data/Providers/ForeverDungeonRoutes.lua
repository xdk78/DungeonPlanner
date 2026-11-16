-- Provider: Forever Dungeon Routes (an addon by Checkov23, MIT). It has no data API, so this adapter reads its INTERNAL
-- tables on the namespace it publishes as the global `ForeverDungeonRoutes` (its Core.lua: _G.ForeverDungeonRoutes =
-- DR), with shape checks: an update of that addon can only switch this adapter off. Read at runtime in the player's
-- client; nothing is copied (the recommended plans' imported routes are a separate, offline import of its MIT data:
-- docs/DATA-SOURCES.md).
--
-- What is read:
--   Dungeons[i] = { key, name, floors = { floor id, ... } }   floor ids: the classic floors' uiMapIDs, and 1000000 +
--     map ID * 10 + level for the pictures of Forever's new dungeons
--   Floors[floor id] = { name, tiles = { 12 file IDs } | image = { file, right, bottom }, credit? }   (Pictures.lua adds
--     the picture floors to this table; there is no separate Pictures table)
--   DefaultRoutes[dungeon key] = route | { route, ... }, route = { id, name?, paths = { { kind = "main" | "side", floor,
--     pts = { x1, y1, x2, y2, ... }, title? } }, stops = { { kind, floor, x, y, name } } }   (x, y 0..1 of the floor's art)
--   Rooms[dungeon key] = { ... }   counted for /dp debug only
--
-- What it gives: its routes on a plan floor as an extra map layer ("Routes: Forever Dungeon Routes", off until the
-- player ticks it), and its maps of Forever's new dungeons (Santiago Reyes' pictures, shipped with that addon) where the
-- game has no map. Map priority (docs/COMPATIBILITY.md section 6): the game's own map art, then the same pictures
-- bundled with Dungeon Planner (Data/ReyesMaps.lua, by Santiago Reyes' permission; its routes are drawn on them too),
-- then Dungeon Journal's pictures, then this addon's (the same pictures, the same crop), then OpenMap's drawings, then
-- the game's minimap pictures, then the parchment grid.

local _, ns = ...
local Providers = ns.Providers
local Util = ns.Util

local A = {
	id = "foreverDungeonRoutes",
	addon = "ForeverDungeonRoutes",
	title = "Forever Dungeon Routes",
	internals = true,
	provides = { "map", "pins", "routes" },
}

local FOLDER = "Interface\\AddOns\\ForeverDungeonRoutes\\"
local TEX = 1024 -- its pictures are 1024 x 1024 files, the map in the top rows (image.bottom)
local MAX_LINES = 20 -- per floor
local MAX_NUMBERS = 2000 -- per line (x and y)

local index -- [instance key] = dungeon entry

function A.Reset()
	index = nil
end

function A.Detect()
	local root = rawget(_G, "ForeverDungeonRoutes")
	if type(root) ~= "table" or type(root.DefaultRoutes) ~= "table" or type(root.Floors) ~= "table"
		or type(root.Dungeons) ~= "table" then
		return nil
	end
	if root.Rooms ~= nil and type(root.Rooms) ~= "table" then
		return nil
	end
	return root
end

-- Its dungeon for a plan: the same name, else one whose name starts the plan's (its "Stratholme" for "Stratholme: Live").
local function dungeonOf(root, plan)
	if not index then
		index = {}
		for _, d in ipairs(root.Dungeons) do
			local k = type(d) == "table" and type(d.name) == "string" and type(d.key) == "string"
				and type(d.floors) == "table" and Providers.Key(d.name)
			if k and not index[k] then
				index[k] = d
			end
		end
	end
	local k = Providers.PlanKey(plan)
	if not k then
		return nil
	end
	if index[k] then
		return index[k]
	end
	local best
	for key, d in pairs(index) do
		if #key >= 8 and k:sub(1, #key) == key and (not best or #key > #Providers.Key(best.name)) then
			best = d
		end
	end
	return best
end
A.DungeonOf = dungeonOf

local function floorInfo(root, id)
	local f = Util.IsInteger(id) and root.Floors[id]
	return type(f) == "table" and f or nil
end

local function picture(f)
	local image = f and f.image
	if type(image) ~= "table" or type(image.file) ~= "string" or image.file == "" or image.file:find("%.%.") then
		return nil
	end
	return image
end

-- Its floor id for a plan floor: a classic floor by the file ID of its first map tile (the game's map tables, which its
-- Floors carry), else by the same name; a picture floor by name (Providers.PickFloor). nil when none fits.
function A.FloorOf(root, plan, floor)
	local d = dungeonOf(root, plan)
	if not d then
		return nil
	end
	local tileID = ns.GameFiles.FloorTileID(plan, floor)
	local want = plan.floors and plan.floors[floor] and ns.Match.StripArticle(plan.floors[floor].name or "") or ""
	local pictures = {}
	for _, id in ipairs(d.floors) do
		local f = floorInfo(root, id)
		if f then
			if tileID and type(f.tiles) == "table" and f.tiles[1] == tileID then
				return id
			end
			if picture(f) then
				pictures[#pictures + 1] = id
			elseif want ~= "" and type(f.name) == "string" and ns.Match.StripArticle(f.name) == want then
				return id
			end
		end
	end
	if #pictures == 0 or tileID then
		return nil
	end
	return (Providers.PickFloor(plan, floor, pictures, function(id)
		local f = floorInfo(root, id)
		return f and f.name, f and picture(f) and picture(f).file
	end))
end

-- The route to show: of several, the one whose name begins like a word of the plan's name ("Living side" for
-- "Stratholme: Live"), else the full clear, else the first.
local function routeOf(root, plan, d)
	local entry = root.DefaultRoutes[d.key]
	if type(entry) ~= "table" then
		return nil
	end
	if entry.paths ~= nil or entry.stops ~= nil then
		return entry
	end
	local k = Providers.PlanKey(plan) or ""
	local full, first
	for _, r in ipairs(entry) do
		if type(r) == "table" then
			first = first or r
			local word = type(r.name) == "string" and r.name:lower():match("^(%a%a%a)")
			if word and k:find(word, #Providers.Key(d.name) + 1, true) then
				return r
			end
			if type(r.id) == "string" and r.id:find(":full$") then
				full = full or r
			end
		end
	end
	return full or first
end

local function line(pts)
	if type(pts) ~= "table" or #pts < 4 or #pts % 2 ~= 0 or #pts > MAX_NUMBERS then
		return nil
	end
	local out = {}
	for i = 1, #pts, 2 do
		local x, y = pts[i], pts[i + 1]
		if not (Providers.IsNumber01(x) and Providers.IsNumber01(y)) then
			return nil
		end
		out[#out + 1] = { x, y }
	end
	return out
end

-- Its route on a plan floor, in the coordinates of that floor's art: { name, lines = { { points = { {x, y}, ... },
-- side = bool, title? } }, stops = { { name, kind, x, y } } }, or nil. `art` is the map the canvas draws (its source):
-- the coordinates fit the game's own map art for a classic floor, and the bundled, Dungeon Journal's or this addon's
-- pictures for a picture floor; on any other map (OpenMap's drawings, the minimap pictures, the grid) nothing is given.
function A.Routes(root, plan, floor, art)
	local id = A.FloorOf(root, plan, floor)
	local f = id and floorInfo(root, id)
	if not f or type(art) ~= "table" then
		return nil
	end
	if picture(f) then
		-- Santiago Reyes' bundled map of the same floor (Data/ReyesMaps.lua) is the same picture, same crop.
		local same = art.source == "reyes" and art.fdr ~= nil and art.fdr == ns.ReyesMaps.BaseName(picture(f).file)
		if not same and (art.source ~= "provider" or (art.provider ~= "dungeonJournal" and art.provider ~= A.id)) then
			return nil
		end
	elseif art.source == "provider" or art.source == "reyes" then
		return nil
	end
	local route = routeOf(root, plan, dungeonOf(root, plan))
	if not route or type(route.paths) ~= "table" then
		return nil
	end
	local out = { name = type(route.name) == "string" and Util.CleanText(route.name, 48) or nil, lines = {}, stops = {} }
	for _, p in ipairs(route.paths) do
		if #out.lines < MAX_LINES and type(p) == "table" and p.floor == id then
			local pts = line(p.pts)
			if pts then
				out.lines[#out.lines + 1] = { points = pts, side = p.kind == "side",
					title = type(p.title) == "string" and Util.CleanText(p.title, 64) or nil }
			end
		end
	end
	for _, s in ipairs(type(route.stops) == "table" and route.stops or {}) do
		if type(s) == "table" and s.floor == id and type(s.name) == "string" and Providers.IsNumber01(s.x)
			and Providers.IsNumber01(s.y) and #out.stops < 60 then
			out.stops[#out.stops + 1] = { name = Util.CleanText(s.name, 64), kind = s.kind, x = s.x, y = s.y }
		end
	end
	if #out.lines == 0 then
		return nil
	end
	return out
end

-- Its picture of a Forever floor (classic floors have the game's own map).
function A.FloorArt(root, plan, floor)
	local id = A.FloorOf(root, plan, floor)
	local f = id and floorInfo(root, id)
	local image = picture(f)
	if not image then
		return nil
	end
	local right = Providers.IsNumber01(image.right) and image.right > 0 and image.right or 1
	local bottom = Providers.IsNumber01(image.bottom) and image.bottom > 0 and image.bottom or 1
	local art = { width = math.floor(TEX * right + 0.5), height = math.floor(TEX * bottom + 0.5), tileWidth = TEX,
		tileHeight = TEX, textures = { FOLDER .. image.file },
		artist = type(f.credit) == "string" and Util.CleanText(f.credit, 48) or nil }
	local pins = {}
	local route = routeOf(root, plan, dungeonOf(root, plan))
	for _, s in ipairs(route and type(route.stops) == "table" and route.stops or {}) do
		if type(s) == "table" and s.floor == id and (s.kind == "boss" or s.kind == "optional") and type(s.name) == "string"
			and Providers.IsNumber01(s.x) and Providers.IsNumber01(s.y) then
			pins[#pins + 1] = { name = s.name, x = s.x, y = s.y }
		end
	end
	return art, pins
end

function A.Counts(root)
	local dungeons, routes, pictures, rooms = 0, 0, 0, 0
	for _, d in ipairs(root.Dungeons) do
		if type(d) == "table" then
			dungeons = dungeons + 1
		end
	end
	for _, r in pairs(root.DefaultRoutes) do
		routes = routes + (type(r) == "table" and (r.paths and 1 or #r) or 0)
	end
	for _, f in pairs(root.Floors) do
		if type(f) == "table" and picture(f) then
			pictures = pictures + 1
		end
	end
	for _, list in pairs(type(root.Rooms) == "table" and root.Rooms or {}) do
		rooms = rooms + (type(list) == "table" and #list or 0)
	end
	return { dungeons = dungeons, routes = routes, maps = pictures, rooms = rooms }
end

Providers.Register(A)
