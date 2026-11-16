-- Lists every localization key used in the addon's code (L["..."] with a literal string), and checks a locale file
-- for missing and unused keys. Run from the repo root:
--   lua tools/locale_keys.lua                 -- print all keys
--   lua tools/locale_keys.lua Locales/plPL.lua  -- report keys missing from (or unused in) that file
-- Keys built at runtime (L[kind], L["slot:" .. slot], L[t.title], ...) are listed in DYNAMIC below.

local FILES = {}
local function scanDir(dir)
	local p = io.popen('find "' .. dir .. '" -name "*.lua"')
	for path in p:lines() do
		FILES[#FILES + 1] = path
	end
	p:close()
end
for _, dir in ipairs({ "Core", "Model", "Share", "Config", "Data", "Tracker", "UI" }) do
	scanDir(dir)
end

local DYNAMIC = {
	-- marker kinds (Schema.MARKER_KINDS)
	"boss", "rare", "pack", "patrol", "loot", "chest", "quest_item", "quest_npc", "npc", "interactive", "entrance", "exit",
	"shortcut", "stairs", "hazard", "position", "note",
	-- boss ability tags as "ability:<tag>" (tools/gen_bosses.lua TAGS)
	"ability:interrupt", "ability:dispel", "ability:tank", "ability:healer", "ability:enrage", "ability:deadly",
	"ability:bleed", "ability:control", "ability:aoe", "ability:adds",
	-- position roles (Schema.POSITION_ROLES) as "role:<ROLE>"
	"role:TANK", "role:HEALER", "role:MELEE", "role:RANGED",
	-- window tabs and sections (UI/MainFrame.lua), map tools and layers (UI/Panels/MapPanel.lua)
	"Dungeons", "Raids", "My plans", "Shared", "Plan", "Bosses", "Position",
	"Bosses and rares", "Packs and patrols", "Loot and chests", "Quests and NPCs", "Entrances, exits and shortcuts",
	"Entrances and exits",
	"Hazards", "Party positions", "Enemies", "Party",
	"Click to add route points, Shift-click for a numbered stop. Right-click to finish the route.",
	"Click the map to place a party position for the chosen role. With a boss or pull in focus, it belongs to it.",
	"Click a marker or route point to delete it.",
	"Create a plan: mark bosses and pulls on the map, draw the route, write strategies, assign players and list gear. Share it with your group or as a string.",
	"A recommended plan. Hover markers for notes; make an editable copy to change it.",
	"Click a dungeon to open it  ·  Right-click a plan for more  ·  /dp help",
	"Drag to pan  ·  Scroll to zoom  ·  Hover a marker for its note",
	"Right-click a row for more  ·  Changes are saved as you make them",
	-- pull tags and planned marks as "tag:<tag>" and "tagShort:<tag>" (Schema.PULL_TAGS, cd, lust)
	"tag:interrupt", "tag:cc", "tag:los", "tag:next", "tag:skip", "tag:careful", "tag:cd", "tag:lust",
	"tagShort:interrupt", "tagShort:cc", "tagShort:los", "tagShort:next", "tagShort:skip", "tagShort:careful",
	"tagShort:cd", "tagShort:lust",
	-- map drawing tools and line widths (UI/Panels/DrawBar.lua) as "draw:<tool>" and "width:<n>"
	"draw:pen", "draw:line", "draw:arrow", "draw:circle", "draw:rect", "draw:text", "draw:erase", "draw:move",
	"width:1", "width:2", "width:3", "Drawings",
	-- a recommended plan's confidence tag (UI.PlanSource)
	"confidence:low", "confidence:medium", "confidence:high",
	-- run mode's drawings switch (UI/RunMode.lua DRAWING_TEXT)
	"Drawings: this step", "Drawings: all", "Drawings: hidden",
	-- slots (Schema.SLOTS) as "slot:<SLOT>"
	"slot:HEAD", "slot:NECK", "slot:SHOULDER", "slot:BACK", "slot:CHEST", "slot:WRIST", "slot:HANDS", "slot:WAIST",
	"slot:LEGS", "slot:FEET", "slot:FINGER", "slot:TRINKET", "slot:MAINHAND", "slot:OFFHAND", "slot:TWOHAND",
	"slot:RANGED",
	-- tabs, tools, raid marks, templates, transfer states
	"Map", "Pulls", "Encounters", "Assignments", "Gear", "Notes", "Progress", "Share",
	"Select", "Marker", "Pull", "Route", "Erase", "Draw",
	"Pick a tool, colour and width above. Drawings made while a boss or pull is in focus belong to it. Right-click one for more.",
	"Drag to draw freehand.", "Drag from start to end.", "Drag from where to where.", "Drag across the circle's box.",
	"Drag from corner to corner.", "Click to write a label; click a label to change it.",
	"Click or drag over drawings to erase them.",
	"Drag a drawing to move it; click one to restyle it with the colours and widths.",
	"Click a marker to edit it; drag to move it. Drag the map to pan, scroll to zoom.",
	"Click the map to place a marker of the chosen kind.",
	"Click markers to add them to the current pull, or to take them out.",
	"Click to add route points. Right-click to finish the route.",
	"Click a marker to delete it.",
	"None", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull",
	"Blank plan", "Dungeon run (5 players)", "Raid night",
	"waiting for answers", "sending", "sent", "declined", "nobody accepted", "cancelled", "receiving", "failed",
	"Tank", "Healer", "Damage",
}

local keys, seen = {}, {}
local function add(k)
	if not seen[k] then
		seen[k] = true
		keys[#keys + 1] = k
	end
end
for _, k in ipairs(DYNAMIC) do
	add(k)
end
for _, path in ipairs(FILES) do
	local f = assert(io.open(path, "rb"))
	local src = f:read("*a")
	f:close()
	-- Scan for L["...", honouring \" escapes; keep only literals closed by "] (skips L["slot:" .. slot]).
	local pos = 1
	while true do
		local s = src:find('L%["', pos)
		if not s then
			break
		end
		local i, buf = s + 3, {}
		while i <= #src do
			local ch = src:sub(i, i)
			if ch == "\\" then
				buf[#buf + 1] = src:sub(i, i + 1)
				i = i + 2
			elseif ch == '"' then
				break
			else
				buf[#buf + 1] = ch
				i = i + 1
			end
		end
		if src:sub(i + 1, i + 1) == "]" then
			local k = table.concat(buf):gsub('\\"', '"'):gsub("\\194\\183", "\194\183")
			add(k)
		end
		pos = i + 1
	end
end
table.sort(keys)

local target = arg[1]
if not target then
	for _, k in ipairs(keys) do
		print(k)
	end
	return
end

-- Load the locale file with a fake ns and compare.
local ns = { Locales = {} }
local chunk = assert(loadfile(target))
chunk("DungeonPlanner", ns)
local _, tbl = next(ns.Locales)
local missing, unused = {}, {}
for _, k in ipairs(keys) do
	if tbl[k] == nil then
		missing[#missing + 1] = k
	end
end
for k in pairs(tbl) do
	if not seen[k] and not k:match("^BINDING_") then
		unused[#unused + 1] = k
	end
end
table.sort(unused)
print(string.format("%d keys used, %d missing in %s, %d unused", #keys, #missing, target, #unused))
for _, k in ipairs(missing) do
	print("  missing: " .. k)
end
for _, k in ipairs(unused) do
	print("  unused:  " .. k)
end
os.exit(#missing == 0 and 0 or 1)
