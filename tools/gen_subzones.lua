-- Generates Data/SubzoneData.lua, the anchors of the map's "You are here (approx.)" marker, from
-- data-src/subzones/*.json (schema and sources: data-src/subzones/README.md).
--   lua tools/gen_subzones.lua            writes Data/SubzoneData.lua
--   lua tools/gen_subzones.lua --check    writes nothing; exits 1 when the JSON is invalid or the file differs
--   lua tools/gen_subzones.lua --report   also prints the coverage
-- Plain Lua 5.1, run from the repository root; deterministic output. The JSON and the output hold IDs, positions and
-- hashes of the names of WMO areas (tools/subzone_anchors.py computes them), never a name.

local IN_DIR = "data-src/subzones"
local PLANS_DIR = "data-src/dungeons"
local PLAN_DIR = "Data/Plans"
local OUT = "Data/SubzoneData.lua"

local spawns = dofile("tools/gen_spawns.lua")
local decode = spawns.DecodeJSON
local listFiles = dofile("tools/gen_bosses.lua").ListFiles

local M = {}
-- The client languages (GetLocale; enGB reports enUS): Blizzard lists none for WoW: Forever, and the client carries
-- all of these (docs/COMPATIBILITY.md section 8). A WMO area's hashes are in this order.
M.LOCALE_ORDER = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
M.POSITIONS = { game = true, fdr = true }
M.MAX_WHY, M.MAX_SPELLINGS, M.MAX_AREAS = 160, 4, 64

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

local function isHash(v)
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 2 ^ 32
end

local function inRange(v)
	return type(v) == "number" and v >= 0 and v <= 1
end

local function shortText(v, max)
	return type(v) == "string" and v ~= "" and #v <= max and not v:find("[%c|]")
end

-- An area's hashes: one per language of M.LOCALE_ORDER, each a hash, a list of 2 to M.MAX_SPELLINGS hashes, or false.
local function validHashes(h)
	if type(h) ~= "table" or #h ~= #M.LOCALE_ORDER then
		return false
	end
	for i = 1, #M.LOCALE_ORDER do
		local v = h[i]
		if type(v) == "table" then
			if #v < 2 or #v > M.MAX_SPELLINGS then
				return false
			end
			for _, x in ipairs(v) do
				if not isHash(x) then
					return false
				end
			end
		elseif v ~= false and not isHash(v) then
			return false
		end
	end
	return true
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
	local keys = {}
	if type(doc.areas) ~= "table" or #doc.areas == 0 or #doc.areas > M.MAX_AREAS then
		err("areas: 1 to %d", M.MAX_AREAS)
	end
	for i, a in ipairs(type(doc.areas) == "table" and doc.areas or {}) do
		local at = string.format("area %d (%s)", i, tostring(a.key))
		if (a.area ~= nil and not isInt(a.area)) or (a.wmo ~= nil and not isInt(a.wmo)) or (a.area == nil and a.wmo == nil) then
			err("%s: needs an area or wmo ID", at)
		elseif a.key ~= (a.area and "a" .. a.area or "w" .. a.wmo) then
			err("%s: the key is \"a\" and its AreaTable ID, else \"w\" and its WMO area ID", at)
		elseif keys[a.key] then
			err("%s: twice", at)
		end
		keys[a.key or i] = true
		if a.name ~= nil or a.names ~= nil then
			err("%s: no names here, only their hashes", at)
		end
		if (a.wmo ~= nil) ~= (a.hashes ~= nil) or (a.hashes ~= nil and not validHashes(a.hashes)) then
			err("%s: a WMO area needs its hashes (%d values: a hash, a list of hashes, or false), others none", at,
				#M.LOCALE_ORDER)
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
		if not (type(e) == "table" and keys[e.key] and shortText(e.why, M.MAX_WHY)) then
			err("exclude %d: needs the key of an area and why", i)
		end
	end
	for i, o in ipairs(type(doc.overrides) == "table" and doc.overrides or {}) do
		local ok = type(o) == "table" and keys[o.key] and isInt(o.floor) and o.floor <= floors and shortText(o.why, M.MAX_WHY)
		if ok and not o.drop then
			ok = inRange(o.x) and inRange(o.y) and (sources[o.src] or o.src == "own")
		end
		if not ok then
			err("override %d: needs an area's key, a floor, why, and drop or x, y and src", i)
		end
	end
	return errs
end

-- The anchors that ship for one file: the areas, less the excluded ones, with the overrides applied. Each
-- { key, area, wmo, hashes, at = { { floor, x, y } } }, sorted by key.
function M.Anchors(doc)
	local excluded = {}
	for _, e in ipairs(doc.exclude or {}) do
		excluded[e.key] = true
	end
	local out = {}
	for _, a in ipairs(doc.areas) do
		if not excluded[a.key] then
			local byFloor = {}
			for _, p in ipairs(a.at) do
				byFloor[p.floor] = { p.floor, p.x, p.y }
			end
			for _, o in ipairs(doc.overrides or {}) do
				if o.key == a.key then
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
				out[#out + 1] = { key = a.key, area = a.area, wmo = a.wmo, hashes = a.hashes, at = at }
			end
		end
	end
	table.sort(out, function(p, q)
		return p.key < q.key
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
					errs[#errs + 1] = string.format("%s: %s and %s share a name hash in %s", file, other.key, a.key, loc)
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
