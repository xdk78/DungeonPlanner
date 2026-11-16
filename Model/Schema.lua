-- The plan schema: limits and enumerations. Validate.lua enforces them on every plan that enters the addon (created,
-- loaded from SavedVariables, imported or received). Changing a limit downward is a format change: bump
-- ns.EXPORT_VERSION and add a migration (docs/SHARING-FORMAT.md).

local _, ns = ...
local Schema = ns:NewModule("Schema")

-- Plan format version. 1: the first release. 2: new marker kinds (pack, rare, chest, quest_item, quest_npc,
-- interactive, exit, shortcut), position roles, marker links (npcID, itemID, questID, toFloor), route stops with step
-- numbers, optional routes, instance level range, instance origin (new in WoW: Forever or classic), origin of a
-- duplicated recommended plan. 3: optional fields older readers drop without harm: map drawings (Model/Drawing.lua),
-- pull tags, planned cooldowns and Bloodlust, planned progress per pull. 4: raid assignment pages (Model/Pages.lua), also
-- optional. Validate.Plan reads all four.
Schema.PLAN_VERSION = 4

-- Byte limits for text fields (UTF-8, cut on a character boundary).
Schema.TEXT = {
	name = 64,
	label = 64,
	short = 120,
	task = 200,
	note = 1000,
	strategy = 4000,
	description = 2000,
	notes = 8000,
	author = 48,
	difficulty = 32,
	player = 48,
	tag = 24,
	page = 3000, -- a raid assignment page's text (Model/Pages.lua)
}

-- Count limits per list. They keep a plan small enough to share in-game (docs/SHARING-FORMAT.md) and bound the work of
-- validating hostile input.
Schema.MAX = {
	floors = 16,
	markers = 500,
	routes = 20,
	routePoints = 200,
	pulls = 100,
	encounters = 40,
	phases = 12,
	assignments = 400,
	groups = 8,
	groupSize = 5,
	gear = 300,
	objectives = 100,
	tags = 8,
	planMarkersPerPull = 100,
	plansPerPack = 50,
	-- Map drawings (Model/Drawing.lua): small enough that a plan full of them still fits an in-game transfer.
	drawings = 150,
	drawingsPerFloor = 50,
	strokePoints = 40,
	-- Raid assignment pages (Model/Pages.lua).
	pages = 20,
}

-- Marker kinds, in the order the UI offers them. Stored as these strings.
Schema.MARKER_KINDS = {
	"boss",
	"rare",
	"pack",
	"patrol",
	"loot",
	"chest",
	"quest_item",
	"quest_npc",
	"npc",
	"interactive",
	"entrance",
	"exit",
	"shortcut",
	"stairs",
	"hazard",
	"position",
	"note",
}
Schema.MARKER_KIND_SET = {}
for _, kind in ipairs(Schema.MARKER_KINDS) do
	Schema.MARKER_KIND_SET[kind] = true
end

-- Version 1 kinds that were renamed in version 2.
Schema.KIND_ALIASES = { mob = "pack", objective = "interactive" }

-- Map layers: what the map's layer toggles show or hide. Every kind is in exactly one layer; "route" is the plan's
-- routes. Order = legend order.
Schema.LAYERS = {
	{ id = "bosses", kinds = { "boss", "rare" } },
	{ id = "enemies", kinds = { "pack", "patrol" } },
	{ id = "loot", kinds = { "loot", "chest" } },
	{ id = "quests", kinds = { "quest_item", "quest_npc", "npc", "interactive" } },
	{ id = "travel", kinds = { "entrance", "exit", "shortcut", "stairs" } },
	{ id = "hazards", kinds = { "hazard" } },
	{ id = "positions", kinds = { "position" } },
	{ id = "notes", kinds = { "note" } },
	{ id = "route", kinds = {} },
	{ id = "drawings", kinds = {} }, -- the plan's map drawings (Model/Drawing.lua)
}
Schema.KIND_LAYER = {}
for _, layer in ipairs(Schema.LAYERS) do
	for _, kind in ipairs(layer.kinds) do
		Schema.KIND_LAYER[kind] = layer.id
	end
end

-- Kinds that lead somewhere else (another floor of the plan): toFloor is kept for these.
Schema.LINK_KINDS = { entrance = true, exit = true, shortcut = true, stairs = true }

-- Party positions on the map (a position marker's role).
Schema.POSITION_ROLES = { "TANK", "HEALER", "MELEE", "RANGED" }
Schema.POSITION_ROLE_SET = { TANK = true, HEALER = true, MELEE = true, RANGED = true }

-- Route stops are numbered 1..MAX_STEP.
Schema.MAX_STEP = 999

-- Levels for an instance's level range (instance.levelMin / levelMax).
Schema.MAX_LEVEL = 200

-- Group roles as the game names them (UnitGroupRolesAssigned).
Schema.ROLES = { "TANK", "HEALER", "DAMAGER" }
Schema.ROLE_SET = { TANK = true, HEALER = true, DAMAGER = true }

-- Equipment slots for gear recommendations. Generic slot names, not game data.
Schema.SLOTS = {
	"HEAD",
	"NECK",
	"SHOULDER",
	"BACK",
	"CHEST",
	"WRIST",
	"HANDS",
	"WAIST",
	"LEGS",
	"FEET",
	"FINGER",
	"TRINKET",
	"MAINHAND",
	"OFFHAND",
	"TWOHAND",
	"RANGED",
}
Schema.SLOT_SET = {}
for _, slot in ipairs(Schema.SLOTS) do
	Schema.SLOT_SET[slot] = true
end

-- Pull tags (format 3), in the order the UI shows them: interrupt, crowd control, line of sight, pull together with
-- the next pull, skip, be careful. Stored as these strings in pull.tags.
Schema.PULL_TAGS = { "interrupt", "cc", "los", "next", "skip", "careful" }
Schema.PULL_TAG_SET = {}
for _, tag in ipairs(Schema.PULL_TAGS) do
	Schema.PULL_TAG_SET[tag] = true
end

-- Content colours for pulls and routes. Indexes are stored; the UI maps them to colours (UI/Style.lua).
Schema.COLOR_COUNT = 8

-- Instance kinds.
Schema.INSTANCE_KINDS = { dungeon = true, raid = true, other = true }
-- Instance origins: new in WoW: Forever, or from the original game (docs/DATA-SOURCES.md has the sources).
Schema.INSTANCE_ORIGINS = { forever = true, classic = true }

-- Assignment targets: a player name, "role:TANK", "group:3", or "all".
function Schema.IsValidTarget(target)
	if type(target) ~= "string" or target == "" then
		return false
	end
	if target == "all" then
		return true
	end
	local role = target:match("^role:(%u+)$")
	if role then
		return Schema.ROLE_SET[role] == true
	end
	local group = tonumber(target:match("^group:(%d)$") or "")
	if group then
		return group >= 1 and group <= Schema.MAX.groups
	end
	-- A player name: no separators that the wire format or the UI treat specially.
	return #target <= Schema.TEXT.player and not target:find("[%c%^|:]")
end

-- Class tokens come from the client at runtime (GetClassInfo); validation only checks the shape.
function Schema.IsClassToken(token)
	return type(token) == "string" and #token <= 16 and token:match("^%u+$") ~= nil
end
