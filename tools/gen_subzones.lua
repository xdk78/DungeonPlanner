-- Generates Data/SubzoneData.lua, the anchors of the map's "You are here (approx.)" marker, from
-- data-src/subzones/*.json (schema and sources: data-src/subzones/README.md).
--   lua tools/gen_subzones.lua            writes Data/SubzoneData.lua
--   lua tools/gen_subzones.lua --check    writes nothing; exits 1 when the JSON is invalid or the file differs
--   lua tools/gen_subzones.lua --report   also prints the coverage
-- Plain Lua 5.1, run from the repository root; deterministic output. Only IDs, positions and hashes of the names of
-- WMO areas (which no game function returns by ID) ship, never a name.

local IN_DIR = "data-src/subzones"
local PLANS_DIR = "data-src/dungeons"
local PLAN_DIR = "Data/Plans"
local OUT = "Data/SubzoneData.lua"

local spawns = dofile("tools/gen_spawns.lua")
local decode = spawns.DecodeJSON
local listFiles = dofile("tools/gen_bosses.lua").ListFiles

-- The addon's own hash (Data/Subzones.lua), so the shipped hashes are what the game's text hashes to in game.
local Subzones
do
	local ns = { Util = {} }
	function ns:NewModule(name)
		self[name] = {}
		return self[name]
	end
	assert(loadfile("Data/Subzones.lua"))("DungeonPlanner", ns)
	Subzones = ns.Subzones
end

local M = {}
-- The client languages (GetLocale; enGB reports enUS): Blizzard lists none for WoW: Forever, and the client carries
-- all of these (docs/COMPATIBILITY.md section 8).
M.LOCALE_ORDER = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
M.LOCALES = {}
for _, loc in ipairs(M.LOCALE_ORDER) do
	M.LOCALES[loc] = true
end
M.POSITIONS = { game = true, fdr = true }
M.MAX_NAME, M.MAX_WHY, M.MAX_SPELLINGS, M.MAX_AREAS = 128, 160, 4, 64 -- name: bytes (UTF-8)
M.Hash = Subzones.Hash

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function isInt(v)
	return type(v) == "number" and v == math.floor(v) and v > 0 and v < 2 ^ 31
end

local function inRange(v)
	return type(v) == "number" and v >= 0 and v <= 1
end

local function shortText(v, max)
	return type(v) == "string" and v ~= "" and #v <= max and not v:find("[%c|]")
end

-- The number of floors of each recommended plan, by slug (the generated plans, as the addon loads them).
function M.PlanFloors()
	local out = {}
	local ns = { Bundled = { Add = function(raw)
		out[raw.id] = #raw.floors
	end } }
	for _, file in ipairs(listFiles(PLAN_DIR, ".lua")) do
		local chunk = assert(loadfile(PLAN_DIR .. "/" .. file))
		setfenv(chunk, {})
		chunk("DungeonPlanner", ns)
	end
	return out
end

-- Checks one file. `research` is data-src/dungeons/<slug>.json; `floors` the plan's floor count. Returns a list of
-- errors.
function M.Validate(doc, file, research, floors)
	local errs = {}
	local function err(fmt, ...)
		errs[#errs + 1] = file .. ": " .. string.format(fmt, ...)
	end
	if type(doc) ~= "table" or doc.schema ~= 1 then
		err("schema must be 1")
		return errs
	end
	if doc.slug .. ".json" ~= file then
		err("slug %s does not match the file name", tostring(doc.slug))
	end
	if not research then
		err("no matching file in %s", PLANS_DIR)
	elseif research.instanceMapID ~= doc.instanceMapID or not isInt(doc.instanceMapID) then
		err("instanceMapID %s is not the plan's (%s)", tostring(doc.instanceMapID), tostring(research.instanceMapID))
	end
	if not floors then
		err("no recommended plan %s", tostring(doc.slug))
		floors = 0
	end
	local sources = {}
	for i, s in ipairs(type(doc.sources) == "table" and doc.sources or {}) do
		if type(s) ~= "table" or type(s.id) ~= "string" or not shortText(s.name, 200) or not shortText(s.licence, 80) then
			err("source %d needs id, name and licence", i)
		else
			sources[s.id] = true
		end
	end
	if not sources.wago then
		err("the area IDs need their source (id \"wago\")")
	end
	if not (M.POSITIONS[doc.position] and sources[doc.position]) then
		err("position must name a listed source (game or fdr)")
	end
	local names = {}
	if type(doc.areas) ~= "table" or #doc.areas == 0 or #doc.areas > M.MAX_AREAS then
		err("areas: 1 to %d", M.MAX_AREAS)
	end
	for i, a in ipairs(type(doc.areas) == "table" and doc.areas or {}) do
		local at = string.format("area %d (%s)", i, tostring(a.name))
		if not shortText(a.name, M.MAX_NAME) then
			err("%s: bad name", at)
		elseif names[a.name] then
			err("%s: name twice", at)
		end
		names[a.name or i] = true
		if a.area == nil and a.wmo == nil then
			err("%s: needs an area or wmo ID", at)
		end
		if (a.area ~= nil and not isInt(a.area)) or (a.wmo ~= nil and not isInt(a.wmo)) then
			err("%s: bad ID", at)
		end
		if a.wmo ~= nil and type(a.names) ~= "table" then
			err("%s: a WMO area needs its names in the client's languages", at)
		end
		for loc, list in pairs(type(a.names) == "table" and a.names or {}) do
			if not M.LOCALES[loc] or loc == "enUS" or type(list) ~= "table" or #list == 0 or #list > M.MAX_SPELLINGS then
				err("%s: bad names for %s", at, tostring(loc))
			else
				for _, n in ipairs(list) do
					if not shortText(n, M.MAX_NAME) then
						err("%s: bad name in %s", at, loc)
					end
				end
			end
		end
		if type(a.at) ~= "table" or #a.at == 0 then
			err("%s: no anchor", at)
		end
		for _, p in ipairs(type(a.at) == "table" and a.at or {}) do
			if not (isInt(p.floor) and p.floor <= floors and inRange(p.x) and inRange(p.y)) then
				err("%s: bad anchor", at)
			end
		end
	end
	for i, e in ipairs(type(doc.exclude) == "table" and doc.exclude or {}) do
		if not (type(e) == "table" and names[e.name] and shortText(e.why, M.MAX_WHY)) then
			err("exclude %d: needs the name of an area and why", i)
		end
	end
	for i, o in ipairs(type(doc.overrides) == "table" and doc.overrides or {}) do
		local ok = type(o) == "table" and names[o.name] and isInt(o.floor) and o.floor <= floors and shortText(o.why, M.MAX_WHY)
		if ok and not o.drop then
			ok = inRange(o.x) and inRange(o.y) and (sources[o.src] or o.src == "own")
		end
		if not ok then
			err("override %d: needs an area's name, a floor, why, and drop or x, y and src", i)
		end
	end
	return errs
end

-- The hashes of an area's names, one per client language in M.LOCALE_ORDER: a number, a list of numbers (spellings
-- that differ between rows of the area), or false (no name in that language). Hashed with the addon's own function.
local function hashes(a)
	local out = {}
	for i, loc in ipairs(M.LOCALE_ORDER) do
		local list = loc == "enUS" and { a.name } or (a.names or {})[loc] or {}
		local seen, h = {}, {}
		for _, name in ipairs(list) do
			local v = Subzones.Hash(name)
			if not seen[v] then
				seen[v] = true
				h[#h + 1] = v
			end
		end
		table.sort(h)
		if #h == 0 then
			out[i] = false
		else
			out[i] = #h == 1 and h[1] or h
		end
	end
	return out
end

-- The anchors that ship for one file: the areas, less the excluded ones, with the overrides applied. Each
-- { name, area, wmo, hashes (WMO areas), at = { { floor, x, y } } }, sorted by name.
function M.Anchors(doc)
	local excluded = {}
	for _, e in ipairs(doc.exclude or {}) do
		excluded[e.name] = true
	end
	local out = {}
	for _, a in ipairs(doc.areas) do
		if not excluded[a.name] then
			local byFloor = {}
			for _, p in ipairs(a.at) do
				byFloor[p.floor] = { p.floor, p.x, p.y }
			end
			for _, o in ipairs(doc.overrides or {}) do
				if o.name == a.name then
					byFloor[o.floor] = not o.drop and { o.floor, o.x, o.y } or nil
				end
			end
			local at = {}
			for _, p in pairs(byFloor) do
				at[#at + 1] = p
			end
			table.sort(at, function(p, q)
				return p[1] < q[1]
			end)
			if #at > 0 then
				out[#out + 1] = { name = a.name, area = a.area, wmo = a.wmo, hashes = a.wmo and hashes(a) or nil, at = at }
			end
		end
	end
	table.sort(out, function(p, q)
		return p.name < q.name
	end)
	return out
end

local function anchorsKey(a)
	local parts = {}
	for i, p in ipairs(a.at) do
		parts[i] = table.concat(p, ",")
	end
	return table.concat(parts, ";")
end

-- Two areas of one instance whose names hash alike in a language, where their anchors differ: the addon could not tell
-- which one the player is in. Returns a list of errors.
function M.Collisions(anchors, file)
	local errs = {}
	for i, loc in ipairs(M.LOCALE_ORDER) do
		local owner = {}
		for _, a in ipairs(anchors) do
			local h = a.hashes and a.hashes[i]
			for _, v in ipairs(type(h) == "table" and h or { h or nil }) do
				local other = owner[v]
				if other and other ~= a and anchorsKey(other) ~= anchorsKey(a) then
					errs[#errs + 1] = string.format("%s: %s and %s share a name hash in %s", file, other.name, a.name, loc)
				end
				owner[v] = owner[v] or a
			end
		end
	end
	return errs
end

-- Rendering --------------------------------------------------------------------------------------------------------------

local function num(v)
	local s = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- Values joined with ", " and wrapped under the 160-column lint limit, continuation lines at `indent`.
local function wrap(values, indent)
	local lines, cur = {}, ""
	for i, v in ipairs(values) do
		local piece = v .. (i < #values and "," or "")
		if cur ~= "" and #indent + #cur + #piece + 1 > 120 then
			lines[#lines + 1] = cur
			cur = piece
		else
			cur = cur == "" and piece or cur .. " " .. piece
		end
	end
	lines[#lines + 1] = cur
	return table.concat(lines, "\n" .. indent)
end

local function renderArea(a)
	local parts = {}
	if a.area then
		parts[#parts + 1] = "a = " .. a.area
	end
	if a.wmo then
		parts[#parts + 1] = "w = " .. a.wmo
	end
	for i, p in ipairs(a.at) do
		parts[#parts + 1] = (i == 1 and "at = { " or "") .. "{ " .. p[1] .. ", " .. num(p[2]) .. ", " .. num(p[3]) .. " }"
			.. (i == #a.at and " }" or "")
	end
	local line = "\t\t{ " .. wrap(parts, "\t\t\t")
	if not a.hashes then
		return line .. " },"
	end
	local h = {}
	for i, v in ipairs(a.hashes) do
		h[i] = type(v) == "table" and "{ " .. table.concat(v, ", ") .. " }" or tostring(v)
	end
	return line .. ",\n\t\t\th = { " .. wrap(h, "\t\t\t\t") .. " } },"
end

function M.Render(entries)
	local out = {
		"-- GENERATED by tools/gen_subzones.lua from data-src/subzones/*.json. Do not edit by hand: change the JSON and run",
		"-- `lua tools/gen_subzones.lua`. Sources and coverage: data-src/subzones/README.md, docs/DATA-SOURCES.md.",
		"-- Where each named area of a dungeon lies on its recommended plan's floors, for the map's \"You are here (approx.)\"",
		"-- marker (Data/Subzones.lua). Every anchor is approximate: the middle of the area's ground. IDs and names from the",
		"-- client's own tables (wago.tools exports); anchors from the client's own files (\"the game's files\") or from",
		"-- Forever Dungeon Routes' room boxes (MIT, Copyright (c) 2026 Checkov23, docs/licenses/ForeverDungeonRoutes-LICENSE.txt).",
		"--   [instance key] = { iid = instance map ID (GetInstanceInfo's eighth value),",
		"--     { a = AreaTable ID (its name from C_Map.GetAreaInfo), w = WMOAreaTable ID, at = { { plan floor, x, y }, ... },",
		"--       h = a WMO area's name hashes (Subzones.Hash) in the order of ns.SubzoneLocales: one, several, or false } }",
		"",
		"local _, ns = ...",
		"ns.SubzoneLocales = { \"" .. table.concat(M.LOCALE_ORDER, "\", \"") .. "\" }",
		"ns.SubzoneData = {",
	}
	local from = { game = "the game's files", fdr = "Forever Dungeon Routes (MIT)" }
	for _, e in ipairs(entries) do
		out[#out + 1] = "\t" .. e.key .. " = { iid = " .. e.iid .. ", -- anchors: " .. from[e.position]
		for _, a in ipairs(e.anchors) do
			out[#out + 1] = renderArea(a)
		end
		out[#out + 1] = "\t},"
	end
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

-- Main -------------------------------------------------------------------------------------------------------------------

local function main(args)
	local check, report = false, false
	for _, a in ipairs(args) do
		check = check or a == "--check"
		report = report or a == "--report"
	end
	local floors = M.PlanFloors()
	local errors, entries = {}, {}
	for _, file in ipairs(listFiles(IN_DIR, ".json")) do
		local ok, doc = pcall(decode, assert(readFile(IN_DIR .. "/" .. file)))
		if not ok then
			errors[#errors + 1] = file .. ": " .. tostring(doc)
		else
			local rt = readFile(PLANS_DIR .. "/" .. file)
			local research = rt and decode(rt)
			local errs = M.Validate(doc, file, research, floors[doc.slug])
			for _, e in ipairs(errs) do
				errors[#errors + 1] = e
			end
			local anchors = #errs == 0 and M.Anchors(doc) or {}
			for _, e in ipairs(M.Collisions(anchors, file)) do
				errors[#errors + 1] = e
			end
			if #anchors > 0 then
				entries[#entries + 1] = { key = spawns.InstanceKey(research.name), iid = doc.instanceMapID, slug = doc.slug,
					position = doc.position, anchors = anchors }
			end
		end
	end
	if #errors > 0 then
		for _, e in ipairs(errors) do
			print(e)
		end
		os.exit(1)
	end
	table.sort(entries, function(a, b)
		return a.key < b.key
	end)
	local text = M.Render(entries)
	if report then
		local areas, anchors = 0, 0
		for _, e in ipairs(entries) do
			areas = areas + #e.anchors
			for _, a in ipairs(e.anchors) do
				anchors = anchors + #a.at
			end
			print(string.format("%-32s %3d areas", e.slug, #e.anchors))
		end
		print(string.format("%d instances, %d areas, %d anchors, %d bytes", #entries, areas, anchors, #text))
	end
	if readFile(OUT) == text then
		print(OUT .. " is up to date")
	elseif check then
		print(OUT .. " is out of date (run `lua tools/gen_subzones.lua`)")
		os.exit(1)
	else
		local w = assert(io.open(OUT, "wb"))
		w:write(text)
		w:close()
		print("wrote " .. OUT)
	end
end

if arg and type(arg[0]) == "string" and arg[0]:find("gen_subzones", 1, true) then
	main(arg)
end
return M
