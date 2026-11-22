-- Generates the creature spawn data of the map's "Enemies" layer (Data/Spawns.lua reads it).
--   lua tools/gen_spawns.lua            writes Data/Spawns/<instance>.lua and the block in DungeonPlanner.toc
--   lua tools/gen_spawns.lua --check    writes nothing; exits 1 when a file on disk differs from what would be written
--   lua tools/gen_spawns.lua --report   also prints counts per instance and floor, and the size
-- Plain Lua 5.1, run from the repository root, after tools/gen_plans.lua. The output is deterministic.
--
-- Inputs (data-src/spawns/README.md has the rules and the reasons):
--   * the recommended plans (Data/Plans/*.lua, generated from data-src/dungeons by tools/gen_plans.lua, already
--     licence-filtered): their bosses, rares, trash packs, patrols and quest NPCs that have a position on a dungeon
--     floor. Same coordinate space as the plans (the floor's classic dungeon map, 0..1), so no transform is needed.
--   * data-src/spawns/*.json: further spawn points, each file naming its source and licence. Only permissive licences
--     or the contributors' own in-game observations are accepted; the generator refuses anything else.
-- Rows are deduplicated (same name and kind within DEDUPE of each other) and capped at CAP per floor.

local OUT_DIR = "Data/Spawns"
local PLAN_DIR = "Data/Plans"
local IN_DIR = "data-src/spawns"
local TOC = "DungeonPlanner.toc"

local M = {}
M.DEDUPE = 0.01 -- two rows of one creature closer than this (in map widths) are one spawn
M.CAP = 300 -- rows per floor (Data/Spawns.lua drops anything past its own MAX_PER_FLOOR, 400)
M.KINDS = { mob = true, elite = true, rare = true, boss = true, npc = true }
-- Plan marker kind -> spawn kind. A pack or patrol is "mob": the research does not say whether it is elite.
M.FROM_MARKER = { boss = "boss", rare = "rare", pack = "mob", patrol = "mob", quest_npc = "npc" }
-- Licences a data-src/spawns file may name ("own": observed in game by the contributor; facts, given under MIT).
M.LICENCES = { MIT = true, ["BSD-2-Clause"] = true, ["BSD-3-Clause"] = true, ["CC0-1.0"] = true,
	["CC-BY-4.0"] = true, own = true }

-- Files ------------------------------------------------------------------------------------------------------------------

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function listFiles(dir, ext)
	local sep = package.config:sub(1, 1)
	local cmd = sep == "\\" and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. dir .. '" 2>/dev/null')
	local out = {}
	local p = io.popen(cmd)
	if p then
		for name in p:lines() do
			name = name:gsub("\r", "")
			if name:sub(-#ext) == ext then
				out[#out + 1] = name
			end
		end
		p:close()
	end
	table.sort(out)
	return out
end

-- The addon's own name normalisation (Model/Match.lua), so keys equal what GameFiles.Key gives in game.
local Match
local function instanceKey(name)
	if not Match then
		local ns = { modules = {} }
		function ns:NewModule(n)
			self[n] = self[n] or {}
			return self[n]
		end
		assert(loadfile("Model/Match.lua"))("DungeonPlanner", ns)
		Match = ns.Match
	end
	local k = Match.StripArticle(name)
	return k ~= "" and k or nil
end
M.InstanceKey = instanceKey

-- JSON reader (null becomes nil) ----------------------------------------------------------------------------------------

function M.DecodeJSON(text)
	local pos = 1
	local function fail(msg)
		error(string.format("JSON: %s at byte %d", msg, pos), 0)
	end
	local function skip()
		pos = text:find("[^ \t\r\n]", pos) or #text + 1
	end
	local value
	local function str()
		local out = {}
		pos = pos + 1
		while true do
			local c = text:sub(pos, pos)
			if c == "" then
				fail("unterminated string")
			elseif c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if not map[e] then
					fail("unsupported escape (write the character itself, UTF-8)")
				end
				out[#out + 1] = map[e]
				pos = pos + 2
			else
				local stop = text:find('["\\]', pos) or #text + 1
				out[#out + 1] = text:sub(pos, stop - 1)
				pos = stop
			end
		end
	end
	function value()
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return t
			end
			while true do
				skip()
				if text:sub(pos, pos) ~= '"' then
					fail("expected a key")
				end
				local k = str()
				skip()
				if text:sub(pos, pos) ~= ":" then
					fail("expected ':'")
				end
				pos = pos + 1
				t[k] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return t
				elseif d ~= "," then
					fail("expected ',' or '}'")
				end
			end
		elseif c == "[" then
			local t, n = {}, 0
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return t
			end
			while true do
				n = n + 1
				t[n] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return t
				elseif d ~= "," then
					fail("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return str()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not num or num == "" or not tonumber(num) then
			fail("unexpected character")
		end
		pos = pos + #num
		return tonumber(num)
	end
	local v = value()
	skip()
	if pos <= #text then
		fail("trailing text")
	end
	return v
end

-- Collecting rows --------------------------------------------------------------------------------------------------------

-- The entrance zones' uiMapIDs (Data/TravelData.lua, `zm`), read once.
local zoneMaps
local function isZoneMap(uiMapID)
	if not zoneMaps then
		zoneMaps = {}
		local ns = {}
		local chunk = assert(loadfile("Data/TravelData.lua"))
		setfenv(chunk, {})
		chunk("DungeonPlanner", ns)
		for _, rec in pairs(ns.TravelData.instances) do
			if type(rec.zm) == "number" then
				zoneMaps[rec.zm] = true
			end
		end
	end
	return zoneMaps[uiMapID] == true
end

-- A floor that is a dungeon floor, as Data/Spawns.lua decides (Floors.IsOutside: the zone outside is an unnamed floor
-- whose map is an entrance zone).
local function dungeonFloor(floor)
	return type(floor) == "table" and not ((floor.name or "") == "" and floor.uiMapID and isZoneMap(floor.uiMapID))
end

local function inRange(v)
	return type(v) == "number" and v >= 0 and v <= 1
end

-- Adds one row to instances[key].floors[floor], deduplicating. Returns true when kept.
local function addRow(instances, key, name, floorIndex, row, stats)
	local inst = instances[key]
	if not inst then
		inst = { key = key, name = name, floors = {} }
		instances[key] = inst
	end
	local rows = inst.floors[floorIndex]
	if not rows then
		rows = {}
		inst.floors[floorIndex] = rows
	end
	for _, r in ipairs(rows) do
		if r.name == row.name and r.kind == row.kind and math.abs(r.x - row.x) < M.DEDUPE and math.abs(r.y - row.y) < M.DEDUPE then
			stats.deduped = stats.deduped + 1
			return false
		end
	end
	if #rows >= M.CAP then
		stats.capped = stats.capped + 1
		return false
	end
	rows[#rows + 1] = row
	return true
end

-- The recommended plans' markers. `plans` is a list of raw plan tables (as Data/Plans files pass to Bundled.Add).
function M.FromPlans(instances, plans, stats)
	for _, plan in ipairs(plans) do
		local name = plan.instance and plan.instance.name
		local key = type(name) == "string" and instanceKey(name)
		for _, m in ipairs(key and plan.markers or {}) do
			local kind = M.FROM_MARKER[m.kind]
			local floor = plan.floors and plan.floors[m.floor or 1]
			if kind and dungeonFloor(floor) and inRange(m.x) and inRange(m.y) and type(m.label) == "string" then
				local approx = type(m.note) == "string" and m.note:find("(approx.)", 1, true) ~= nil
				if addRow(instances, key, name, m.floor or 1, { x = m.x, y = m.y, name = m.label, kind = kind,
					npcID = m.npcID, approx = approx, from = "plan" }, stats) then
					stats.fromPlans = stats.fromPlans + 1
				end
			end
		end
	end
end

-- One data-src/spawns file, decoded. Errors (as strings) for anything that would put unclear data in the addon.
function M.FromSpawnFile(instances, data, file, stats)
	local errors = {}
	local function bad(msg)
		errors[#errors + 1] = file .. ": " .. msg
	end
	if type(data) ~= "table" or data.schema ~= 1 then
		bad("schema must be 1")
		return errors
	end
	local key = type(data.instance) == "string" and instanceKey(data.instance)
	if not key then
		bad("instance must be the instance's name, as the plans name it")
		return errors
	end
	local sources = {}
	for i, s in ipairs(data.sources or {}) do
		if type(s.id) ~= "string" or type(s.what) ~= "string" then
			bad("source " .. i .. " needs an id and a what")
		elseif not M.LICENCES[s.licence] then
			bad("source " .. s.id .. ": licence " .. tostring(s.licence) .. " is not accepted (see data-src/spawns/README.md)")
		else
			sources[s.id] = s
		end
	end
	for i, p in ipairs(data.spawns or {}) do
		local where = "spawn " .. i
		if not sources[p.source] then
			bad(where .. ": its source must be one of the file's accepted sources")
		elseif type(p.floor) ~= "number" or p.floor < 1 or p.floor % 1 ~= 0 then
			bad(where .. ": floor must be 1 or more")
		elseif not (inRange(p.x) and inRange(p.y)) then
			bad(where .. ": x and y must be 0..1 on the floor's map")
		elseif type(p.name) ~= "string" or p.name == "" or #p.name > 80 then
			bad(where .. ": name must be text, up to 80 bytes")
		elseif not M.KINDS[p.kind] then
			bad(where .. ": kind must be mob, elite, rare, boss or npc")
		elseif p.npcID ~= nil and (type(p.npcID) ~= "number" or p.npcID < 1 or p.npcID % 1 ~= 0) then
			bad(where .. ": npcID must be a positive whole number")
		elseif p.level ~= nil and (type(p.level) ~= "number" or p.level < 1 or p.level > 100 or p.level % 1 ~= 0) then
			bad(where .. ": level must be 1..100")
		elseif addRow(instances, key, data.instance, p.floor, { x = p.x, y = p.y, name = p.name, kind = p.kind,
			npcID = p.npcID, level = p.level, approx = p.approx == true, from = "file" }, stats) then
			stats.fromFiles = stats.fromFiles + 1
		end
	end
	return errors
end

-- Rendering --------------------------------------------------------------------------------------------------------------

local function quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return map[c] or string.format("\\%03d", c:byte())
	end) .. '"'
end

local function num(n)
	local s = string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "")
	return s
end

function M.Render(inst, origin)
	local out = {
		"-- GENERATED by tools/gen_spawns.lua from " .. origin .. ". Do not edit by hand:",
		"-- change the research data or the generator and run `lua tools/gen_spawns.lua`.",
		"-- Spawn points of " .. inst.name .. " per floor: { x, y, name, kind, npcID or false, level or false, approx }",
		"-- (data-src/spawns/README.md). Coordinates are 0..1 on the floor's map, as the plans' markers.",
		"",
		"local _, ns = ...",
		"ns.Spawns.Add(" .. quote(inst.key) .. ", {",
	}
	local floors = {}
	for f in pairs(inst.floors) do
		floors[#floors + 1] = f
	end
	table.sort(floors)
	for _, f in ipairs(floors) do
		out[#out + 1] = "\t[" .. f .. "] = {"
		for _, r in ipairs(inst.floors[f]) do
			out[#out + 1] = string.format("\t\t{ %s, %s, %s, %q, %s, %s, %s },", num(r.x), num(r.y), quote(r.name), r.kind,
				r.npcID and tostring(r.npcID) or "false", r.level and tostring(r.level) or "false", tostring(r.approx == true))
		end
		out[#out + 1] = "\t},"
	end
	out[#out + 1] = "})"
	return table.concat(out, "\n") .. "\n"
end

-- Reading the generated plans --------------------------------------------------------------------------------------------

local function loadPlans()
	local plans = {}
	local ns = { Bundled = { Add = function(raw)
		plans[#plans + 1] = raw
	end } }
	for _, file in ipairs(listFiles(PLAN_DIR, ".lua")) do
		local chunk = assert(loadfile(PLAN_DIR .. "/" .. file))
		setfenv(chunk, {})
		chunk("DungeonPlanner", ns)
	end
	return plans
end

-- Main -------------------------------------------------------------------------------------------------------------------

local function main(args)
	local check, report = false, false
	for _, a in ipairs(args) do
		check = check or a == "--check"
		report = report or a == "--report"
	end
	local stats = { fromPlans = 0, fromFiles = 0, deduped = 0, capped = 0 }
	local instances = {}
	M.FromPlans(instances, loadPlans(), stats)
	local errors = {}
	for _, file in ipairs(listFiles(IN_DIR, ".json")) do
		local ok, data = pcall(M.DecodeJSON, assert(readFile(IN_DIR .. "/" .. file)))
		if not ok then
			errors[#errors + 1] = file .. ": " .. tostring(data)
		else
			for _, e in ipairs(M.FromSpawnFile(instances, data, file, stats)) do
				errors[#errors + 1] = e
			end
		end
	end
	if #errors > 0 then
		for _, e in ipairs(errors) do
			print(e)
		end
		os.exit(1)
	end

	local keys = {}
	for k in pairs(instances) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local differs, tocLines, bytes, rows, floorsN = {}, {}, 0, 0, 0
	local wanted = {}
	for _, k in ipairs(keys) do
		local inst = instances[k]
		local text = M.Render(inst, "the recommended plans and data-src/spawns")
		local path = OUT_DIR .. "/" .. k .. ".lua"
		wanted[k .. ".lua"] = true
		bytes = bytes + #text
		tocLines[#tocLines + 1] = "Data\\Spawns\\" .. k .. ".lua"
		local per = {}
		for f, list in pairs(inst.floors) do
			floorsN = floorsN + 1
			rows = rows + #list
			per[#per + 1] = string.format("%d:%d", f, #list)
		end
		table.sort(per)
		if report then
			print(string.format("  %-32s %s", k, table.concat(per, " ")))
		end
		if readFile(path) ~= text then
			differs[#differs + 1] = path
			if not check then
				local w = assert(io.open(path, "wb"))
				w:write(text)
				w:close()
			end
		end
	end
	for _, file in ipairs(listFiles(OUT_DIR, ".lua")) do
		if not wanted[file] then
			differs[#differs + 1] = OUT_DIR .. "/" .. file .. " (no longer generated)"
			if not check then
				os.remove(OUT_DIR .. "/" .. file)
			end
		end
	end

	-- The TOC lists every generated file between two comment lines, right after the generated plans.
	local tocText = assert(readFile(TOC))
	local eol = tocText:find("\r\n", 1, true) and "\r\n" or "\n"
	local block = "# BEGIN generated spawns (tools/gen_spawns.lua)" .. eol .. table.concat(tocLines, eol)
		.. (#tocLines > 0 and eol or "") .. "# END generated spawns"
	local newToc
	if tocText:find("# BEGIN generated spawns", 1, true) then
		newToc = tocText:gsub("# BEGIN generated spawns.-# END generated spawns", function()
			return block
		end)
	else
		newToc = tocText:gsub("(# END generated plans)", function(anchor)
			return anchor .. eol .. eol .. block
		end, 1)
	end
	if newToc ~= tocText then
		differs[#differs + 1] = TOC
		if not check then
			local w = assert(io.open(TOC, "wb"))
			w:write(newToc)
			w:close()
		end
	end

	if report then
		print(string.format("instances: %d, floors: %d, spawns: %d (from plans %d, from data-src/spawns %d), "
			.. "deduplicated %d, over the cap %d, bytes: %d", #keys, floorsN, rows, stats.fromPlans, stats.fromFiles,
			stats.deduped, stats.capped, bytes))
	end
	if check then
		if #differs > 0 then
			print("out of date (run `lua tools/gen_spawns.lua`):")
			for _, p in ipairs(differs) do
				print("  " .. p)
			end
			os.exit(1)
		end
		print("generated spawns are up to date")
	else
		print(string.format("wrote %d spawn files (%d changed), %d spawns, %d bytes", #keys, #differs, rows, bytes))
	end
end

-- Run as a script; `dofile` from the tests only returns the functions above.
if arg and type(arg[0]) == "string" and arg[0]:find("gen_spawns", 1, true) then
	main(arg)
end
return M
