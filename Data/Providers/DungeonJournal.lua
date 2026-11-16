-- Provider: Dungeon Journal (the ForeverDungeonJournal addon). Reads its INTERNAL tables, so every read checks shapes
-- and an update of that addon can only switch this adapter off. It has no data API: its only public entry point is
-- ForeverDungeonJournal_Toggle(). Read at runtime in the player's client; nothing is copied (it states no licence).
--
-- What is read (all from the global namespace table ForeverDungeonJournal_NS, filled when its files load):
--   DUNGEON_MAPS[dungeon name] = { floors = { { texture, texBottom?, texRight?, label? } | { uiMapID, tiles } },
--     bosses = { { name, x, y, floor? } } }    its own map pictures of Forever's new dungeons (x, y 0..1 of the art)
--   DB[dungeon name].bosses[i] = { name, npcID?, displayID?, loot = { { itemID, name, "Slot, Type", quality }, ... },
--     rare?, description?, summonItem? }   (it has no abilities, spell IDs or lore for a boss: nothing of that is read)
--   BOSS_LEVELS[dungeon name][boss name] = "16" (a level or a range, as text)
--   STATIC_DISPLAY_IDS[npcID] = displayID, BAKED_PORTRAITS[displayID] = true (pictures in its Media\Portraits folder)

local _, ns = ...
local Providers = ns.Providers
local Util = ns.Util

local A = {
	id = "dungeonJournal",
	addon = "ForeverDungeonJournal",
	title = "Dungeon Journal",
	internals = true,
	provides = { "map", "pins", "loot", "portraits", "info" },
}

local PORTRAITS = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\Portraits\\"
local TEX = 1024 -- its map pictures are 1024 x 1024 files cropped with texRight / texBottom

local index -- [instance key] = dungeon name

function A.Reset()
	index = nil
end

function A.Detect()
	local root = rawget(_G, "ForeverDungeonJournal_NS")
	if type(root) ~= "table" or type(root.DB) ~= "table" then
		return nil
	end
	if root.DUNGEON_MAPS ~= nil and type(root.DUNGEON_MAPS) ~= "table" then
		return nil
	end
	return root
end

local function dungeonName(root, plan)
	if not index then
		index = {}
		for _, t in ipairs({ root.DB, root.DUNGEON_MAPS or {} }) do
			for name in pairs(t) do
				local k = type(name) == "string" and Providers.Key(name)
				if k and not index[k] then
					index[k] = name
				end
			end
		end
	end
	local k = Providers.PlanKey(plan)
	return k and index[k] or nil
end
A.DungeonName = dungeonName

-- The picture of one floor (only its own pictures: classic floors drawn from the game's tiles are ours already).
function A.FloorArt(root, plan, floor)
	local name = dungeonName(root, plan)
	local map = name and type(root.DUNGEON_MAPS) == "table" and root.DUNGEON_MAPS[name]
	if type(map) ~= "table" or type(map.floors) ~= "table" then
		return nil
	end
	-- The floor of the same name (its label, else the words of its file name), else the same position
	-- (Providers.PickFloor: it lists Dalaran's Underbelly first, unlabelled).
	local f = Providers.PickFloor(plan, floor, map.floors, function(c)
		if type(c) ~= "table" then
			return nil
		end
		return c.label, c.texture
	end)
	if type(f) ~= "table" or type(f.texture) ~= "string" or f.texture == "" then
		return nil
	end
	local right = Providers.IsNumber01(f.texRight) and f.texRight > 0 and f.texRight or 1
	local bottom = Providers.IsNumber01(f.texBottom) and f.texBottom > 0 and f.texBottom or 1
	local art = { width = math.floor(TEX * right + 0.5), height = math.floor(TEX * bottom + 0.5), tileWidth = TEX,
		tileHeight = TEX, textures = { f.texture } }
	local index1 = Util.IndexOf(map.floors, f)
	local pins = {}
	for _, b in ipairs(type(map.bosses) == "table" and map.bosses or {}) do
		if type(b) == "table" and type(b.name) == "string" and Providers.IsNumber01(b.x) and Providers.IsNumber01(b.y)
			and (tonumber(b.floor) or 1) == index1 then
			pins[#pins + 1] = { name = b.name, x = b.x, y = b.y }
		end
	end
	return art, pins
end

local function boss(root, plan, enc)
	local name = dungeonName(root, plan)
	local d = name and root.DB[name]
	local bosses = type(d) == "table" and d.bosses
	if type(bosses) ~= "table" then
		return nil
	end
	local want = Providers.BossKey(enc)
	for _, b in ipairs(bosses) do
		if type(b) == "table" and type(b.name) == "string" and not b.trash then
			if ns.Match.StripArticle(b.name) == want then
				return b, name
			end
			for _, alias in ipairs(type(b.aliases) == "table" and b.aliases or {}) do
				if type(alias) == "string" and ns.Match.StripArticle(alias) == want then
					return b, name
				end
			end
		end
	end
	return nil
end

-- Text from the other addon for display: one line without control characters or "|" (colour and link codes), cut at n
-- bytes without splitting a UTF-8 character. nil when it is not a string or empty.
local function text(v, n)
	if type(v) ~= "string" then
		return nil
	end
	v = v:gsub("[%c|]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
	if v == "" then
		return nil
	end
	if #v > n then
		v = v:sub(1, n - 3):gsub("[\128-\191]+$", ""):gsub("[\192-\255]$", "") .. "..."
	end
	return v
end

local function item(row)
	if type(row) ~= "table" then
		return nil
	end
	local id = row[1] or row.itemID
	if not Util.IsInteger(id) or id <= 0 then
		return nil
	end
	local q = row[4] or row.quality
	return { itemID = id, name = text(row[2], 80), quality = Util.IsInteger(q) and q or nil,
		slotText = text(row[3], 40), slot = ns.Loot.SlotOf(id) }
end

function A.Loot(root, plan, enc)
	local b, dungeon = boss(root, plan, enc)
	if not b then
		return nil
	end
	local out, seen = {}, {}
	local function add(row)
		local it = item(row)
		if it and not seen[it.itemID] and #out < 80 then
			seen[it.itemID] = true
			out[#out + 1] = it
		end
	end
	for _, row in ipairs(type(b.loot) == "table" and b.loot or {}) do
		add(row)
	end
	local shared = type(root.SHARED_BY_BOSS) == "table" and root.SHARED_BY_BOSS[dungeon]
	shared = type(shared) == "table" and shared[b.name]
	for _, row in ipairs(type(shared) == "table" and shared or {}) do
		add(row)
	end
	return out
end

function A.Portrait(root, plan, enc)
	local b = boss(root, plan, enc)
	if not b then
		return nil
	end
	local display = Util.IsInteger(b.displayID) and b.displayID or nil
	if not display and Util.IsInteger(b.npcID) and type(root.STATIC_DISPLAY_IDS) == "table" then
		local d = root.STATIC_DISPLAY_IDS[b.npcID]
		display = Util.IsInteger(d) and d or nil
	end
	if not display then
		return nil
	end
	if type(root.BAKED_PORTRAITS) == "table" and root.BAKED_PORTRAITS[display] == true then
		return { icon = PORTRAITS .. display }
	end
	return { displayInfo = display }
end

-- The boss's level as the journal states it: "16", a range "24-25", or "??"; nil for anything else.
local function levelText(root, dungeon, b)
	local byDungeon = type(root.BOSS_LEVELS) == "table" and root.BOSS_LEVELS[dungeon]
	local v = type(byDungeon) == "table" and byDungeon[b.name]
	if Util.IsInteger(v) and v > 0 and v < 200 then
		return tostring(v)
	end
	if type(v) == "string" and (v:match("^%d%d?%d?$") or v:match("^%d%d?%d?%-%d%d?%d?$") or v == "??") then
		return v
	end
	return nil
end

local MAX_DROPS = 12

-- What it states about one boss, for the detail pages: { level?, rare?, description?, summon = { itemID }?, drops? }
-- (drops: the Loot() items), or nil when it knows none of that. Every field is optional and checked.
function A.Boss(root, plan, enc)
	local b, dungeon = boss(root, plan, enc)
	if not b then
		return nil
	end
	local info = { level = levelText(root, dungeon, b), rare = b.rare == true or nil, description = text(b.description, 300) }
	if Util.IsInteger(b.summonItem) and b.summonItem > 0 then
		info.summon = { itemID = b.summonItem }
	end
	local drops = A.Loot(root, plan, enc)
	if drops and #drops > 0 then
		while #drops > MAX_DROPS do
			table.remove(drops)
		end
		info.drops = drops
	end
	if next(info) == nil then
		return nil
	end
	return info
end

-- Instance pictures ---------------------------------------------------------------------------------------------------
-- DUNGEON_HOME_ART[dungeon name] = texture (a game file, a file ID, or one of its own pictures in its Media folder),
-- DUNGEON_HOME_TEXCOORD[dungeon name] = { u0, u1, v0, v1 } (UI/ThemeData.lua). Only its own pictures are taken (the
-- game's files are ours already, Data/GameFiles.lua): the card art of Forever's new dungeons. Its card pictures are
-- 2:1 files (512 x 256, Hall of Thanes' and Ruins of Lordaeron's 1024 x 512).
A.provides[#A.provides + 1] = "pictures"
local OWN_MEDIA = "^interface[\\/]addons[\\/]foreverdungeonjournal[\\/]media[\\/][%w_]+[^\\/]*$"

function A.CardArt(root, instanceName)
	local art, coords = root.DUNGEON_HOME_ART, root.DUNGEON_HOME_TEXCOORD
	local want = Providers.Key(instanceName)
	if type(art) ~= "table" or not want then
		return nil
	end
	for name, file in pairs(art) do
		if type(name) == "string" and Providers.Key(name) == want and type(file) == "string"
			and file:lower():find(OWN_MEDIA) then
			local c = type(coords) == "table" and coords[name]
			local u0, u1, v0, v1 = 0, 1, 0, 1
			if type(c) == "table" and Providers.IsNumber01(c[1]) and Providers.IsNumber01(c[2])
				and Providers.IsNumber01(c[3]) and Providers.IsNumber01(c[4]) and c[1] < c[2] and c[3] < c[4] then
				u0, u1, v0, v1 = c[1], c[2], c[3], c[4]
			end
			return { file = file, area = { u0, u1, v0, v1, 2 * (u1 - u0) / (v1 - v0) } }
		end
	end
	return nil
end

function A.Counts(root)
	local dungeons, maps, pins, loot = 0, 0, 0, 0
	for _, d in pairs(root.DB) do
		dungeons = dungeons + 1
		for _, b in ipairs(type(d) == "table" and type(d.bosses) == "table" and d.bosses or {}) do
			loot = loot + (type(b) == "table" and type(b.loot) == "table" and #b.loot or 0)
		end
	end
	for _, m in pairs(type(root.DUNGEON_MAPS) == "table" and root.DUNGEON_MAPS or {}) do
		for _, f in ipairs(type(m) == "table" and type(m.floors) == "table" and m.floors or {}) do
			if type(f) == "table" and type(f.texture) == "string" then
				maps = maps + 1
			end
		end
		pins = pins + (type(m) == "table" and type(m.bosses) == "table" and #m.bosses or 0)
	end
	return { dungeons = dungeons, maps = maps, pins = pins, loot = loot }
end

Providers.Register(A)
