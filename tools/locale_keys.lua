-- Lists every localization key used in the addon's code (L["..."] with a literal string), and checks a locale file
-- for missing and unused keys and for format specifiers that differ from the English. Run from the repo root:
--   lua tools/locale_keys.lua                   -- print all keys
--   lua tools/locale_keys.lua Locales/plPL.lua  -- report keys missing from, unused in or malformed in that file
--   lua tools/locale_keys.lua --all             -- the same for every file in Locales/ but enUS (CI); exit 1 if any fails
--   lua tools/locale_keys.lua --template deDE   -- print a skeleton for a new locale (English text as the values)
--   lua tools/locale_keys.lua --missing-lines Locales/deDE.lua -- print the lines that file lacks, English as the value
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
	-- the recommended plans' standard notes paragraph (UI/Panels/NotesPanel.lua ESTIMATES)
	'Spots marked "~" are estimates, not measurements. Party positions are generic suggestions: tank where the group arrives, healer and ranged behind, melee beside the boss. Check everything in game and adjust it in your own copy.',
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

-- English text of each key: enUS.lua holds internal names ("boss" = "Boss"); every other key is its own English text.
local enNs = { Locales = {} }
assert(loadfile("Locales/enUS.lua"))("DungeonPlanner", enNs)
local english = enNs.Locales.enUS

local function specs(s)
	local out = {}
	for spec in s:gmatch("%%[%d%.]*[sdf]") do
		out[#out + 1] = spec
	end
	return table.concat(out, ",")
end

local function lq(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

-- Prints a skeleton for a new locale: every key with its English text as the value, ready to translate.
local function template(code)
	print("-- " .. code .. ": machine-assisted first pass. Native speakers: please improve it (see Locales/README.md).")
	print("")
	print("local _, ns = ...")
	print("ns.Locales = ns.Locales or {}")
	print("")
	print("ns.Locales." .. code .. " = {")
	for _, k in ipairs(keys) do
		print("\t[" .. lq(k) .. "] = " .. lq(english[k] or k) .. ",")
	end
	local bindings = {}
	for k in pairs(english) do
		if k:match("^BINDING_") then
			bindings[#bindings + 1] = k
		end
	end
	table.sort(bindings)
	for _, k in ipairs(bindings) do
		print("\t" .. k .. " = " .. lq(english[k]) .. ",")
	end
	print("}")
end

-- Checks one locale file. Prints the missing, unused and mismatched keys by name. Returns true when it is clean.
local function check(target)
	local ns = { Locales = {} }
	local chunk = assert(loadfile(target))
	chunk("DungeonPlanner", ns)
	local code, tbl = next(ns.Locales)
	local missing, unused, badFormat = {}, {}, {}
	-- A plural key has exactly as many forms as the language's rule (ns.PLURAL_RULES in Locales/enUS.lua) can pick.
	local rule = enNs.PLURAL_RULES[code]
	local formCount = 1
	if rule then
		for n = 0, 1000 do
			formCount = math.max(formCount, rule(n))
		end
	else
		badFormat[#badFormat + 1] = "(no plural rule for " .. tostring(code) .. " in Locales/enUS.lua)"
	end
	for _, k in ipairs(keys) do
		if tbl[k] == nil then
			missing[#missing + 1] = k
		end
	end
	for k, v in pairs(tbl) do
		if not seen[k] and not k:match("^BINDING_") then
			unused[#unused + 1] = k
		end
		if type(v) ~= "string" or v == "" then
			badFormat[#badFormat + 1] = k .. " (not a non-empty string)"
		elseif k:find("|", 1, true) then
			local want = specs(k:match("^[^|]*"))
			local n, bad = 0, false
			for form in v:gmatch("[^|]+") do
				n = n + 1
				bad = bad or specs(form) ~= want
			end
			if bad then
				badFormat[#badFormat + 1] = k
			elseif rule and n ~= formCount then
				badFormat[#badFormat + 1] = k .. " (" .. n .. " plural forms, " .. code .. " has " .. formCount .. ")"
			end
		elseif k:find("%", 1, true) and specs(v) ~= specs(k) then
			badFormat[#badFormat + 1] = k
		end
	end
	for k in pairs(english) do
		if k:match("^BINDING_") and tbl[k] == nil then
			missing[#missing + 1] = k
		end
	end
	table.sort(missing)
	table.sort(unused)
	table.sort(badFormat)
	print(string.format("%s: %d keys used, %d missing, %d unused, %d with wrong format specifiers", target, #keys,
		#missing, #unused, #badFormat))
	for _, k in ipairs(missing) do
		print("  missing: " .. k)
	end
	for _, k in ipairs(unused) do
		print("  unused:  " .. k)
	end
	for _, k in ipairs(badFormat) do
		print("  format:  " .. k)
	end
	return #missing == 0 and #unused == 0 and #badFormat == 0
end

-- The .lua files in Locales/. `dir /b` on Windows (cmd.exe, never System32's find.exe), `ls` elsewhere.
local function localeFolder()
	local windows = package.config:sub(1, 1) == "\\"
	local p = assert(io.popen(windows and "dir /b Locales\\*.lua" or "ls Locales"))
	local names = {}
	for name in p:lines() do
		name = name:gsub("%s+$", "")
		if name:match("^%a+%.lua$") then
			names[#names + 1] = name
		end
	end
	p:close()
	assert(#names > 0, "could not list the Locales folder")
	return names
end

-- Every locale file the TOC loads (its Locales\xxXX.lua lines) except enUS, and whether the TOC and the folder agree:
-- a file in Locales/ that the TOC does not load (or the reverse) is reported and makes the check fail.
local function allLocaleFiles()
	local files, listed = {}, {}
	local f = assert(io.open("DungeonPlanner.toc", "rb"))
	for line in f:lines() do
		local name = line:match("^Locales[\\/](%a+%.lua)%s*$")
		if name then
			listed[name] = true
			if name ~= "enUS.lua" then
				files[#files + 1] = "Locales/" .. name
			end
		end
	end
	f:close()
	table.sort(files)
	assert(#files > 0, "no Locales\\*.lua lines found in DungeonPlanner.toc")
	local agree = true
	local inFolder = {}
	for _, name in ipairs(localeFolder()) do
		inFolder[name] = true
		if not listed[name] then
			print("  not in DungeonPlanner.toc: Locales/" .. name)
			agree = false
		end
	end
	for name in pairs(listed) do
		if not inFolder[name] then
			print("  in DungeonPlanner.toc but not in the folder: Locales/" .. name)
			agree = false
		end
	end
	return files, agree
end

local first = arg[1]
if not first then
	for _, k in ipairs(keys) do
		print(k)
	end
	return
end
if first == "--template" then
	assert(arg[2], "usage: lua tools/locale_keys.lua --template <localeCode>")
	template(arg[2])
	return
end

if first == "--missing-lines" then
	-- The lines a locale still needs, English as the value, ready to paste into the file and translate.
	local ns = { Locales = {} }
	assert(loadfile(assert(arg[2], "usage: lua tools/locale_keys.lua --missing-lines Locales/<code>.lua")))("DungeonPlanner", ns)
	local _, tbl = next(ns.Locales)
	for _, k in ipairs(keys) do
		if tbl[k] == nil then
			print("\t[" .. lq(k) .. "] = " .. lq(english[k] or k) .. ",")
		end
	end
	local bindings = {}
	for k in pairs(english) do
		if k:match("^BINDING_") and tbl[k] == nil then
			bindings[#bindings + 1] = k
		end
	end
	table.sort(bindings)
	for _, k in ipairs(bindings) do
		print("\t" .. k .. " = " .. lq(english[k]) .. ",")
	end
	return
end

local targets, ok = arg, true
if first == "--all" then
	targets, ok = allLocaleFiles()
end
for _, target in ipairs(targets) do
	ok = check(target) and ok
end
os.exit(ok and 0 or 1)
