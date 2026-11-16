-- Generates the recommended (bundled) plans from the research data.
--   lua tools/gen_plans.lua            writes Data/Plans/<slug>.lua for every data-src/dungeons/*.json
--   lua tools/gen_plans.lua --check    writes nothing; exits 1 when a file on disk differs from what would be written
--   lua tools/gen_plans.lua --report   also prints the licence audit and what was dropped
-- Plain Lua 5.1, run from the repository root. The output is deterministic: the same input gives the same bytes.
--
-- What it does, in short (docs/DATA-SOURCES.md has the rules):
--   * reads each research file (a small JSON reader below) and maps it to plan format 2 (docs/SHARING-FORMAT.md);
--   * drops every value whose source is AllTheThings or NeedRoll's own data (licence), and anything without a source
--     unless it is marked approximate; null coordinates never become map markers;
--   * keeps a short "(approx.)" in the note of every estimated marker and stop;
--   * cleans researcher remarks (source names, "not sourced", first person) out of the text that ships;
--   * puts in the route bends of data-src/routes/<slug>.json (tools/route_paths.py): between two consecutive stops
--     the bends of the leg with the same floor and ends, and estimated stops and markers moved off walls ("moves");
--   * applies an imported route from the same file ("import", tools/import_routes.py): positions for estimated or
--     unplaced points, stops the research lacks, side paths as optional routes, and a credit line in the notes.

local OUT_DIR = "Data/Plans"
local IN_DIR = "data-src/dungeons"
local ROUTES_DIR = "data-src/routes"
local MAX_ROUTE_POINTS = 200 -- Model/Schema.lua
local TOC = "DungeonPlanner.toc"

-- Policy switches. The defaults follow the licence rules; see docs/DATA-SOURCES.md before changing them.
local ALLOW_ATT_IDS = false -- journal instance IDs and map IDs that only AllTheThings confirmed
local ALLOW_ART = true -- positions the researcher estimated by eye from a dungeon map picture (not copied data)

-- JSON reader ------------------------------------------------------------------------------------------------------------

local function utf8char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
	return string.char(
		0xF0 + math.floor(cp / 0x40000),
		0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40,
		0x80 + cp % 0x40
	)
end

-- Decodes JSON text. null becomes nil (absent): the research files treat both the same way.
local function decode(text)
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
				if map[e] then
					out[#out + 1] = map[e]
					pos = pos + 2
				elseif e == "u" then
					local cp = tonumber(text:sub(pos + 2, pos + 5), 16) or fail("bad \\u escape")
					pos = pos + 6
					if cp >= 0xD800 and cp < 0xDC00 and text:sub(pos, pos + 1) == "\\u" then
						local low = tonumber(text:sub(pos + 2, pos + 5), 16) or fail("bad surrogate")
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
						pos = pos + 6
					end
					out[#out + 1] = utf8char(cp)
				else
					fail("bad escape")
				end
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
			local obj = {}
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				skip()
				if text:sub(pos, pos) ~= '"' then
					fail("object key expected")
				end
				local key = str()
				skip()
				if text:sub(pos, pos) ~= ":" then
					fail("':' expected")
				end
				pos = pos + 1
				obj[key] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					fail("',' or '}' expected")
				end
			end
		elseif c == "[" then
			local arr, n = {}, 0
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				n = n + 1
				arr[n] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					fail("',' or ']' expected")
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
		local num = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
		if not num or num == "" then
			fail("value expected")
		end
		pos = pos + #num
		return tonumber(num)
	end
	local result = value()
	skip()
	if pos <= #text then
		fail("trailing data")
	end
	return result
end

-- Small helpers ----------------------------------------------------------------------------------------------------------

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- Cut to at most n bytes without splitting a UTF-8 character.
-- The research data's date ("updated": "YYYY-MM-DD" in each file) as Unix time at 00:00 UTC, so the plan can say how
-- old its data is (docs/DATA-SOURCES.md). Computed without the local time zone, so every machine writes the same file.
local function dataTime(text, slug)
	local y, m, d = tostring(text or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	assert(y, slug .. ": updated must be a date (YYYY-MM-DD)")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return (era * 146097 + doe - 719468) * 86400
end

local function cut(s, n)
	if #s <= n then
		return s
	end
	local i = n
	while i > 0 do
		local b = s:byte(i + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		i = i - 1
	end
	return s:sub(1, i)
end

-- Cut at a word boundary, adding "..." when something was left out.
local function shorten(s, n)
	if #s <= n then
		return s
	end
	local t = cut(s, n - 3)
	local space = t:match("^(.*)%s%S*$")
	if space and #space > n / 2 then
		t = space
	end
	return (t:gsub("[%s%p]+$", "")) .. "..."
end

local function listFiles()
	local cmd = package.config:sub(1, 1) == "\\" and ('dir /b "' .. IN_DIR:gsub("/", "\\") .. '\\*.json" 2>nul')
		or ('ls "' .. IN_DIR .. '"')
	local p = io.popen(cmd)
	local names = {}
	for line in p:lines() do
		line = line:gsub("\r", "")
		if line:match("%.json$") then
			names[#names + 1] = line
		end
	end
	p:close()
	table.sort(names)
	return names
end

-- Text cleaning ----------------------------------------------------------------------------------------------------------

-- Researcher remarks that must not ship: source and licence names, provenance talk, first person, raw map jargon.
local BLOCKED = {
	"needroll", "allthethings", "all the things", "openmap", "wowhead", "warcraft tavern", "method", "gpl", "fdj",
	"foreverdungeonjournal", "dungeon journal", "encounter journal", "journal data", "client table", "licen", "boost",
	"map picture", "picture", "sourced", "not found in any", "uimapid", "inferred", "coordinate", "x/y", "null",
	"verify in game", "from memory", "position unknown", "entrance spot", "position not", "no measured",
	"%f[%w]att%f[%W]", "%f[%w]i%f[%W]", "%f[%w]my%f[%W]", "%f[%w]pins?%f[%W]", "%f[%w]sources?%f[%W]",
	"%f[%w]art estimate", "%f[%w]guide %d", "npc ids", "npc or item", "level range", "wing%-local", "instance map",
	"assumed for", "client's group finder",
}

local function blocked(s)
	local l = s:lower()
	for _, p in ipairs(BLOCKED) do
		if l:find(p) then
			return true
		end
	end
	return false
end

-- Removes blocked parentheticals and blocked sentences. Returns "" when nothing public is left.
local function clean(text)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("%b()", function(paren)
		return blocked(paren) and "" or paren
	end)
	text = text:gsub("^%s*[Ee]stimate:%s*", ""):gsub("%s+([%.,;:])", "%1")
	-- Sentences end at . ! or ? followed by white space (so "0.52" and "Dr.Foo" do not split).
	local kept, i = {}, 1
	while i <= #text do
		local s, e = text:find("[%.!?]%s+", i)
		local sentence = s and text:sub(i, s) or text:sub(i)
		if not blocked(sentence) then
			kept[#kept + 1] = sentence
		end
		if not s then
			break
		end
		i = e + 1
	end
	return (table.concat(kept, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Serializer -------------------------------------------------------------------------------------------------------------

local function quote(s)
	s = s:gsub("[%c\"\\]", function(c)
		if c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		elseif c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		end
		return string.format("\\%03d", c:byte())
	end)
	return '"' .. s .. '"'
end

local function num(n)
	if n == math.floor(n) then
		return string.format("%d", n)
	end
	local s = string.format("%.4f", n):gsub("0+$", "")
	return s
end

local function scalar(v)
	if type(v) == "string" then
		return quote(v)
	elseif type(v) == "number" then
		return num(v)
	end
	return tostring(v)
end

-- A table on one line: array part first, then the named keys in the given order.
local function line(t, keys)
	local parts = {}
	for _, v in ipairs(t) do
		parts[#parts + 1] = type(v) == "table" and line(v, nil) or scalar(v)
	end
	for _, k in ipairs(keys or {}) do
		local v = t[k]
		if v ~= nil then
			parts[#parts + 1] = k .. " = " .. (type(v) == "table" and line(v, nil) or scalar(v))
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local MARKER_KEYS = { "id", "floor", "x", "y", "kind", "label", "note", "pull", "encounter", "role", "npcID", "itemID", "toFloor" }
local POINT_KEYS = { "step", "pull", "note" }
local ENCOUNTER_KEYS = { "id", "name", "strategy" }
local PULL_KEYS = { "id", "name", "note", "color" }

local function routeLine(route)
	local pts = {}
	for _, p in ipairs(route.points) do
		pts[#pts + 1] = line(p, POINT_KEYS)
	end
	return string.format(
		"{ id = %s, name = %s, floor = %d, color = %d,%s points = {\n\t\t\t%s,\n\t\t} },",
		quote(route.id),
		quote(route.name),
		route.floor,
		route.color,
		route.optional and " optional = true," or "",
		table.concat(pts, ",\n\t\t\t")
	)
end

-- Source classification --------------------------------------------------------------------------------------------------

-- "att", "needroll" (NeedRoll's own data), "art" (estimated by eye from a map picture), "ok" or "none".
local function classify(src)
	if not src then
		return "none"
	end
	local text = ((src.url or "") .. " " .. (src.what or "")):lower()
	if text:find("allthethings", 1, true) then
		return "att"
	end
	if text:find("needroll", 1, true) then
		if text:find("viewed only", 1, true) or text:find("map pictures", 1, true) then
			return "art"
		end
		return "needroll"
	end
	return "ok"
end

local function allowed(class)
	if class == "att" or class == "needroll" then
		return false
	end
	if class == "art" then
		return ALLOW_ART
	end
	return true
end

-- Mapping ----------------------------------------------------------------------------------------------------------------

local ROLE = { tank = "TANK", healer = "HEALER", melee = "MELEE", ranged = "RANGED" }
local KIND = {
	boss = "boss",
	rare = "rare",
	pack = "pack",
	patrol = "patrol",
	loot = "loot",
	chest = "chest",
	quest_item = "quest_item",
	quest_npc = "quest_npc",
	interactive = "interactive",
	entrance = "entrance",
	exit = "exit",
	shortcut = "shortcut",
	hazard = "hazard",
	note = "note",
}
local KIND_WORD = {
	rare = "Rare",
	quest_item = "Quest item",
	quest_npc = "Quest NPC",
	interactive = "Object",
	chest = "Chest",
	pack = "Pack",
	loot = "Loot",
}

local function approxNote(note, approx, limit)
	note = clean(note)
	if approx then
		note = (note ~= "" and (note .. " ") or "") .. "(approx.)"
	end
	return shorten(note, limit)
end

local function near(a, b)
	return math.abs(a - b) < 0.0006
end

local function hasCoords(e)
	return type(e.x) == "number" and type(e.y) == "number"
end

local stats

-- Route bends and moves (data-src/routes/<slug>.json, written by tools/route_paths.py). Points match by floor and
-- position (4 decimals, as the plans print them), so a leg whose stops moved in the research simply no longer applies.
local function same(a, b)
	return math.abs(a - b) < 0.00006
end

local function routeData(routes)
	local r = { moves = {}, legs = {} }
	for _, m in ipairs(routes and routes.moves or {}) do
		r.moves[#r.moves + 1] = m
	end
	for _, l in ipairs(routes and routes.legs or {}) do
		r.legs[#r.legs + 1] = l
	end
	-- Where a point on a floor ends up after the moves.
	function r.Move(floor, x, y)
		for _, m in ipairs(r.moves) do
			if m.floor == floor and same(m.from[1], x) and same(m.from[2], y) then
				stats.moves = stats.moves + 1
				return m.to[1], m.to[2]
			end
		end
		return x, y
	end
	-- The bends between two stops, or nil.
	function r.Bends(floor, a, b)
		for _, l in ipairs(r.legs) do
			if l.floor == floor and same(l.from[1], a.x) and same(l.from[2], a.y) and same(l.to[1], b.x) and same(l.to[2], b.y) then
				l.used = true
				return l.bends or {}
			end
		end
		return nil
	end
	return r
end

-- An imported route (the "import" block of data-src/routes/<slug>.json, written by tools/import_routes.py from Forever
-- Dungeon Routes, MIT): positions for the research's estimated or unplaced points ("fill", by point id and floor),
-- stops the research lacks ("add", after a research step number, 0 = first), side paths as optional routes ("side")
-- and a credit line for the plan's notes ("note"). The research's steps, pulls and bosses stay as they are.
local IMPORT_SOURCE = "import"

local function applyImport(data, imp)
	if type(imp) ~= "table" then
		return nil
	end
	local byPoint = {}
	for _, f in ipairs(imp.fill or {}) do
		byPoint[f.point] = f
	end
	for _, p in ipairs(data.points) do
		local f = byPoint[p.id]
		if f and (p.floor == nil or p.floor == f.floor) then
			p.floor, p.x, p.y, p.approx = f.floor, f.at[1], f.at[2], f.approx
			stats.filled = stats.filled + 1
		end
	end
	local route = {}
	local function adds(after)
		for _, a in ipairs(imp.add or {}) do
			if a.after == after then
				route[#route + 1] = { floor = a.floor, x = a.at[1], y = a.at[2], note = a.note, approx = a.approx,
					source = IMPORT_SOURCE }
				stats.added = stats.added + 1
			end
		end
	end
	adds(0)
	for _, step in ipairs(data.route or {}) do
		local f = step.point and byPoint[step.point]
		if f and (step.floor == nil or step.floor == f.floor) then
			step.floor, step.x, step.y, step.approx = f.floor, f.at[1], f.at[2], f.approx
		end
		route[#route + 1] = step
		adds(step.step)
	end
	data.route = route
	data.sources = data.sources or {}
	data.sources[#data.sources + 1] = { id = IMPORT_SOURCE, url = imp.url or "", what = imp.note or "imported route" }
	return imp
end

local function build(data, routes)
	local imported = applyImport(data, routes and routes["import"])
	routes = routeData(routes)
	local srcClass = {}
	local hasATT = false
	for _, s in ipairs(data.sources or {}) do
		srcClass[s.id] = classify(s)
		if srcClass[s.id] == "att" then
			hasATT = true
		end
	end
	local function srcOK(id)
		-- A point without a source is only acceptable when it is marked approximate (checked by the caller).
		if id == nil then
			return true
		end
		local c = srcClass[id] or "none"
		if not allowed(c) then
			stats.dropped[c] = (stats.dropped[c] or 0) + 1
			return false
		end
		stats.used[c] = (stats.used[c] or 0) + 1
		return true
	end

	local floors, floorCount = {}, #data.maps
	for i, m in ipairs(data.maps) do
		local id = m.uiMapID
		if m.uiMapIDInferred or (hasATT and not ALLOW_ATT_IDS) then
			id = nil
		end
		floors[i] = { uiMapID = id, name = m.name or "" }
	end

	local plan = {
		id = data.slug,
		rev = 1,
		updated = dataTime(data.updated, data.slug),
		author = "Dungeon Planner",
		instance = {
			name = data.name,
			kind = data.kind,
			levelMin = data.levelRange and data.levelRange[1],
			levelMax = data.levelRange and data.levelRange[2],
			-- New in WoW: Forever or from the original game, when a source says so (docs/DATA-SOURCES.md).
			origin = (data.origin == "forever" or data.origin == "classic") and data.originSource ~= nil
				and allowed(srcClass[data.originSource] or "none") and data.origin or nil,
		},
		floors = floors,
		markers = {},
		routes = {},
		pulls = {},
		encounters = {},
	}
	if data.ejInstanceID and (not hasATT or ALLOW_ATT_IDS) then
		plan.instance.ejInstanceID = data.ejInstanceID
	end
	plan.instance.uiMapID = floors[1] and floors[1].uiMapID or nil

	-- Which points survive: licence, then coordinates. byId maps a research point id to what became of it.
	local points = {}
	for _, p in ipairs(data.points) do
		local entry = { src = p, ok = true }
		if p.source ~= nil then
			entry.ok = srcOK(p.source)
		elseif not p.approx then
			entry.ok = false -- no source and not marked as an estimate
			stats.dropped.nosource = (stats.dropped.nosource or 0) + 1
		end
		points[p.id] = entry
	end
	local function idOK(p)
		return p.idSource ~= nil and allowed(srcClass[p.idSource] or "none")
	end

	-- Floors that lie outside the dungeon (floor 0, a zone map): appended after the dungeon's floors.
	local outside = {} -- uiMapID -> floor index
	local function outsideFloor(uiMapID)
		if not outside[uiMapID] then
			floors[#floors + 1] = { uiMapID = uiMapID, name = "" }
			outside[uiMapID] = #floors
		end
		return outside[uiMapID]
	end
	local function floorOf(e)
		local f = e.floor
		if type(f) == "number" and f >= 1 and f <= floorCount then
			return f
		end
		if f == 0 and type(e.uiMapID) == "number" then
			return outsideFloor(e.uiMapID)
		end
		return nil
	end

	-- Bosses become encounters, in kill order: route order first, then the order of the points.
	local order, seenBoss = {}, {}
	for _, step in ipairs(data.route or {}) do
		local e = step.point and points[step.point]
		if e and e.src.kind == "boss" and not seenBoss[step.point] then
			seenBoss[step.point] = true
			order[#order + 1] = step.point
		end
	end
	local routeBosses = #order
	for _, p in ipairs(data.points) do
		if p.kind == "boss" and not seenBoss[p.id] then
			seenBoss[p.id] = true
			order[#order + 1] = p.id
		end
	end
	local encOf = {}
	for _, pid in ipairs(order) do
		local e = points[pid]
		if e.ok and #plan.encounters < 40 then
			local id = "e" .. (#plan.encounters + 1)
			encOf[pid] = id
			plan.encounters[#plan.encounters + 1] = { id = id, name = shorten(e.src.name, 64), _texts = {} }
		end
	end
	for _, s in ipairs(data.strategies or {}) do
		local enc = s.boss and encOf[s.boss]
		local text = clean(s.text)
		if enc and text ~= "" then
			for _, e in ipairs(plan.encounters) do
				if e.id == enc then
					e._texts[#e._texts + 1] = text
				end
			end
		end
	end

	-- Pulls: markers of the pack kind point at their pull; boss entries stay in the pull's note.
	local packPull = {}
	local pullOf = {} -- research point id -> pull id (for route stops)
	for _, pl in ipairs(data.pulls or {}) do
		if #plan.pulls < 100 then
			local id = "u" .. (#plan.pulls + 1)
			local names = {}
			for _, pid in ipairs(pl.points or {}) do
				local e = points[pid]
				if e and e.ok then
					names[#names + 1] = e.src.name
					pullOf[pid] = pullOf[pid] or id
					if e.src.kind == "pack" and not packPull[pid] then
						packPull[pid] = id
					end
				end
			end
			if #names > 0 then
				-- A name another one already says ("Summoner patrol (Magmatus)" + "Magmatus") is left out.
				local kept = {}
				for i, n in ipairs(names) do
					local said = false
					for j, other in ipairs(names) do
						if i ~= j and #other > #n and other:lower():find(n:lower(), 1, true) then
							said = true
						end
						if j < i and other == n then
							said = true
						end
					end
					if not said then
						kept[#kept + 1] = n
					end
				end
				plan.pulls[#plan.pulls + 1] = {
					id = id,
					name = shorten(table.concat(kept, " + "), 64),
					note = shorten(clean(pl.note), 1000),
					color = (#plan.pulls) % 8 + 1,
				}
			end
		end
	end

	-- Markers.
	local counter = 0
	local function addMarker(m)
		counter = counter + 1
		m.id = "m" .. counter
		plan.markers[#plan.markers + 1] = m
		return m
	end
	local bossAt = {} -- encounter id -> { floor, x, y } of its marker, to fold things lying on top of a boss
	local unplaced = {} -- text lines for things that have no place on the map
	local folded = {} -- encounter id -> list of text lines
	for _, p in ipairs(data.points) do
		local e = points[p.id]
		if e.ok and p.kind == "boss" and hasCoords(p) then
			local floor = floorOf(p)
			if floor then
				local m = addMarker({
					floor = floor,
					x = p.x,
					y = p.y,
					kind = "boss",
					label = shorten(p.name, 64),
					note = approxNote(p.note, p.approx, 1000),
					encounter = encOf[p.id],
				})
				if idOK(p) then
					m.npcID = p.npcID
				end
				if encOf[p.id] then
					bossAt[#bossAt + 1] = { enc = encOf[p.id], floor = floor, x = p.x, y = p.y }
				end
			end
		end
	end
	local function foldedInto(floor, x, y)
		for _, b in ipairs(bossAt) do
			if b.floor == floor and near(b.x, x) and near(b.y, y) then
				return b.enc
			end
		end
		return nil
	end
	for _, p in ipairs(data.points) do
		local e = points[p.id]
		local kind = KIND[p.kind]
		if e.ok and p.kind ~= "boss" and kind then
			local floor = hasCoords(p) and floorOf(p)
			if not hasCoords(p) then
				-- Not on the map: keep what a player needs to know as a line of text.
				if p.kind ~= "entrance" and p.kind ~= "exit" then
					local note = clean(p.note)
					unplaced[#unplaced + 1] = (KIND_WORD[p.kind] or "Point") .. ": " .. p.name .. (note ~= "" and (" - " .. note) or "")
					stats.nullCoords = stats.nullCoords + 1
				else
					stats.nullCoords = stats.nullCoords + 1
				end
			elseif floor then
				local enc = (p.kind == "quest_item" or p.kind == "chest" or p.kind == "interactive" or p.kind == "loot")
					and foldedInto(floor, p.x, p.y)
				if enc then
					local note = clean(p.note)
					folded[enc] = folded[enc] or {}
					folded[enc][#folded[enc] + 1] = (KIND_WORD[p.kind] or "Drop") .. ": " .. p.name .. (note ~= "" and (" - " .. note) or "")
				else
					local m = addMarker({
						floor = floor,
						x = p.x,
						y = p.y,
						kind = kind,
						label = shorten(p.name, 64),
						note = approxNote(p.note, p.approx, 1000),
						pull = packPull[p.id],
					})
					if kind == "entrance" and floor > floorCount then
						m.toFloor = 1
					end
					if idOK(p) then
						m.npcID = p.npcID
						m.itemID = p.itemID
					end
				end
			end
		end
	end

	-- Party positions, tied to their boss.
	for _, pos in ipairs(data.positions or {}) do
		local enc = pos.boss and encOf[pos.boss]
		local floor = hasCoords(pos) and floorOf(pos)
		if enc and floor and (pos.approx or pos.source ~= nil) then
			local role = ROLE[pos.role]
			if role then
				addMarker({ floor = floor, x = pos.x, y = pos.y, kind = "position", role = role, encounter = enc, note = pos.approx and "(approx.)" or nil })
			elseif pos.role == "all" then
				addMarker({ floor = floor, x = pos.x, y = pos.y, kind = "note", label = "Everyone", note = approxNote(pos.note, pos.approx, 1000) })
			end
		end
	end

	for _, m in ipairs(plan.markers) do
		m.x, m.y = routes.Move(m.floor, m.x, m.y)
	end

	-- Routes: one per run of steps on the same floor. Steps without coordinates stay in the text order list.
	local stepLines, fullyDrawn = {}, true
	local runs, run = {}, nil
	local stopsTotal = 0
	for _, step in ipairs(data.route or {}) do
		local linked = step.point and points[step.point]
		local dropped = linked and not linked.ok
		if step.source ~= nil and not srcOK(step.source) then
			dropped = true
		end
		if step.approx == false and not linked and step.source == nil then
			dropped = true -- exact, but nothing says where it comes from
		end
		local text = clean(step.note)
		local floor = (not dropped) and hasCoords(step) and floorOf(step)
		if text == "" and linked then
			text = linked.src.name
		end
		if floor then
			if not run or run.floor ~= floor then
				run = { floor = floor, points = {} }
				runs[#runs + 1] = run
			end
			local x, y = routes.Move(floor, step.x, step.y)
			run.points[#run.points + 1] = {
				step = #run.points + 1,
				pull = step.point and pullOf[step.point] or nil,
				note = approxNote(text, step.approx, 120),
				x = x,
				y = y,
			}
			stopsTotal = stopsTotal + 1
		else
			fullyDrawn = false
		end
		stepLines[#stepLines + 1] = (#stepLines + 1) .. ". " .. (text ~= "" and text or "...")
	end
	local floorsUsed = {}
	for _, r in ipairs(runs) do
		floorsUsed[r.floor] = true
	end
	local multi = 0
	for _ in pairs(floorsUsed) do
		multi = multi + 1
	end
	for i, r in ipairs(runs) do
		if #plan.routes < 20 then
			-- Stops, and between two of them the bends that keep the line on the floor (stops first if the cap is near).
			local bendsTotal, bendsOf = 0, {}
			for k = 2, #r.points do
				bendsOf[k] = routes.Bends(r.floor, r.points[k - 1], r.points[k]) or {}
				bendsTotal = bendsTotal + #bendsOf[k]
			end
			assert(#r.points + bendsTotal <= MAX_ROUTE_POINTS, data.slug .. ": too many route points")
			local pts = {}
			for k, p in ipairs(r.points) do
				for _, b in ipairs(bendsOf[k] or {}) do
					pts[#pts + 1] = { b[1], b[2] }
					stats.bends = stats.bends + 1
				end
				pts[#pts + 1] = { p.x, p.y, step = p.step, pull = p.pull, note = p.note ~= "" and p.note or nil }
			end
			plan.routes[#plan.routes + 1] = {
				id = "r" .. i,
				name = multi > 1 and (floors[r.floor].name ~= "" and floors[r.floor].name or ("Floor " .. r.floor)) or "Route",
				floor = r.floor,
				color = (i - 1) % 8 + 1,
				points = pts,
			}
		end
	end
	-- An imported route's side paths (to an optional boss, a rare): optional routes in the colour of that floor's route.
	for _, side in ipairs(imported and imported.side or {}) do
		if #plan.routes < 20 and side.floor >= 1 and side.floor <= #floors and #side.points >= 2 then
			local color = 1
			for _, r in ipairs(plan.routes) do
				if r.floor == side.floor and not r.optional then
					color = r.color
					break
				end
			end
			local pts = {}
			for k = 1, math.min(#side.points, MAX_ROUTE_POINTS) do
				pts[k] = { side.points[k][1], side.points[k][2] }
			end
			plan.routes[#plan.routes + 1] = { id = "r" .. (#plan.routes + 1), name = shorten(side.name, 64), floor = side.floor,
				color = color, optional = true, points = pts }
			stats.sides = stats.sides + 1
		end
	end

	-- Encounter text: strategy, then what drops or lies at the boss.
	for _, enc in ipairs(plan.encounters) do
		local parts = {}
		for _, t in ipairs(enc._texts) do
			parts[#parts + 1] = t
		end
		if folded[enc.id] then
			parts[#parts + 1] = table.concat(folded[enc.id], "\n")
		end
		enc.strategy = #parts > 0 and cut(table.concat(parts, "\n"), 4000) or nil
		enc._texts = nil
	end

	-- Text: the plan note and the description.
	local placed, bosses = 0, 0
	for _, m in ipairs(plan.markers) do
		if m.kind == "boss" then
			placed = placed + 1
		end
	end
	for _, p in ipairs(data.points) do
		if p.kind == "boss" and points[p.id].ok then
			bosses = bosses + 1
		end
	end
	local conf = data.confidence or "low"
	local intro = "Community-researched plan with approximate positions. Confidence: " .. conf .. "."
	local coverage
	if bosses == 0 then
		coverage = ""
	elseif placed == bosses then
		coverage = string.format(" All %d bosses are placed on the map.", bosses)
	elseif placed == 0 then
		coverage = string.format(" None of the %d bosses has a position here; the Adventure Guide's pins show where the game puts them.", bosses)
	else
		coverage = string.format(" %d of %d bosses are placed on the map; the Adventure Guide's pins fill in the rest.", placed, bosses)
	end
	plan.description = intro .. coverage
	local notes = {
		intro .. coverage,
		'Spots marked "~" are estimates, not measurements. Party positions are generic suggestions: tank where '
			.. "the group arrives, healer and ranged behind, melee beside the boss. Check everything in game and adjust it "
			.. "in your own copy.",
	}
	if not fullyDrawn or stopsTotal == 0 then
		if #stepLines > 0 then
			notes[#notes + 1] = "Order of the clear:\n" .. table.concat(stepLines, "\n")
		end
	end
	if #unplaced > 0 then
		notes[#notes + 1] = "Not on the map (no position known):\n" .. table.concat(unplaced, "\n")
	end
	if imported and type(imported.note) == "string" and imported.note ~= "" then
		notes[#notes + 1] = imported.note -- the credit line, written by the import tool (not research text)
	end
	local extra = clean(data.notes)
	if extra ~= "" then
		notes[#notes + 1] = "More: " .. extra
	end
	plan.notes = cut(table.concat(notes, "\n\n"), 8000)
	-- The name says what the plan is (the UI adds "(recommended)"): a route through every boss is a full clear, a
	-- route through some of them a boss route, and bosses without a route (every raid) a boss order.
	if data.kind ~= "raid" and routeBosses > 0 and routeBosses >= bosses then
		plan.name = "Full clear"
	elseif data.kind ~= "raid" and routeBosses > 0 then
		plan.name = "Boss route"
	else
		plan.name = "Boss order"
	end
	plan.tags = { "recommended", data.kind, "confidence: " .. conf }
	-- Counters for the report.
	stats.markers = stats.markers + #plan.markers
	stats.bosses = stats.bosses + bosses
	stats.placed = stats.placed + placed
	stats.confidence[conf] = (stats.confidence[conf] or 0) + 1
	return plan
end

-- Output -----------------------------------------------------------------------------------------------------------------

local function render(plan, slug)
	local out = {
		"-- GENERATED by tools/gen_plans.lua from data-src/dungeons/" .. slug .. ".json. Do not edit by hand:",
		"-- change the research data or the generator and run `lua tools/gen_plans.lua`.",
		"-- A recommended plan (docs/SHARING-FORMAT.md): community-researched, positions approximate.",
		"",
		"local _, ns = ...",
		"ns.Bundled.Add({",
		"\tid = " .. quote(plan.id) .. ",",
		"\trev = " .. plan.rev .. ",",
		"\tupdated = " .. plan.updated .. ",",
		"\tname = " .. quote(plan.name) .. ",",
		"\tauthor = " .. quote(plan.author) .. ",",
		"\tdescription = " .. quote(plan.description) .. ",",
		"\tnotes = " .. quote(plan.notes) .. ",",
		"\ttags = " .. line(plan.tags) .. ",",
		"\tinstance = " .. line(plan.instance, { "name", "kind", "origin", "ejInstanceID", "uiMapID", "levelMin", "levelMax" }) .. ",",
		"\tfloors = {",
	}
	for _, f in ipairs(plan.floors) do
		out[#out + 1] = "\t\t" .. line(f, { "uiMapID", "name" }) .. ","
	end
	out[#out + 1] = "\t},"
	local function section(name, items, keys)
		out[#out + 1] = "\t" .. name .. " = {"
		for _, it in ipairs(items) do
			out[#out + 1] = "\t\t" .. line(it, keys) .. ","
		end
		out[#out + 1] = "\t},"
	end
	section("pulls", plan.pulls, PULL_KEYS)
	section("encounters", plan.encounters, ENCOUNTER_KEYS)
	section("markers", plan.markers, MARKER_KEYS)
	out[#out + 1] = "\troutes = {"
	for _, r in ipairs(plan.routes) do
		out[#out + 1] = "\t\t" .. routeLine(r)
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "})"
	return table.concat(out, "\n") .. "\n"
end

local function main(args)
	local check, report = false, false
	for _, a in ipairs(args) do
		check = check or a == "--check"
		report = report or a == "--report"
	end
	stats = { dropped = {}, used = {}, markers = 0, bosses = 0, placed = 0, nullCoords = 0, confidence = {}, bytes = 0, files = 0,
		bends = 0, moves = 0, filled = 0, added = 0, sides = 0 }
	local differs, stale = {}, {}
	local names = listFiles()
	assert(#names > 0, "no research files in " .. IN_DIR)
	local tocLines = {}
	for _, name in ipairs(names) do
		local data = decode(readFile(IN_DIR .. "/" .. name))
		assert(data.schema == 1, name .. ": unknown schema")
		local rf = io.open(ROUTES_DIR .. "/" .. data.slug .. ".json", "rb")
		local routes = rf and decode(rf:read("*a"))
		if rf then
			rf:close()
		end
		local plan = build(data, routes)
		for _, l in ipairs(routes and routes.legs or {}) do
			if not l.used then
				stale[#stale + 1] = string.format("%s floor %d: %s,%s -> %s,%s", data.slug, l.floor, l.from[1], l.from[2], l.to[1], l.to[2])
			end
		end
		local text = render(plan, data.slug)
		local path = OUT_DIR .. "/" .. data.slug .. ".lua"
		stats.bytes = stats.bytes + #text
		stats.files = stats.files + 1
		tocLines[#tocLines + 1] = "Data\\Plans\\" .. data.slug .. ".lua"
		local f = io.open(path, "rb")
		local old = f and f:read("*a")
		if f then
			f:close()
		end
		if old ~= text then
			differs[#differs + 1] = path
			if not check then
				local w = assert(io.open(path, "wb"))
				w:write(text)
				w:close()
			end
		end
	end
	-- The TOC lists every generated file between two comment lines (the offline loader and the game both skip them).
	local tocText = readFile(TOC)
	local eol = tocText:find("\r\n", 1, true) and "\r\n" or "\n"
	local block = "# BEGIN generated plans (tools/gen_plans.lua)" .. eol .. table.concat(tocLines, eol) .. eol .. "# END generated plans"
	local newToc
	if tocText:find("# BEGIN generated plans", 1, true) then
		newToc = tocText:gsub("# BEGIN generated plans.-# END generated plans", function()
			return block
		end)
	else
		newToc = tocText:gsub("(Data\\Templates%.lua)", function(anchor)
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
		print(string.format("plans: %d, bytes: %d, markers: %d, bosses placed: %d of %d", stats.files, stats.bytes, stats.markers, stats.placed, stats.bosses))
		print("values used by source class:")
		for k, v in pairs(stats.used) do
			print("  " .. k, v)
		end
		print("values dropped by source class:")
		for k, v in pairs(stats.dropped) do
			print("  " .. k, v)
		end
		print("points with null coordinates (not map markers): " .. stats.nullCoords)
		print(string.format("route bends: %d, moved points: %d (data-src/routes)", stats.bends, stats.moves))
		print(string.format("imported routes: %d points placed, %d stops added, %d side paths", stats.filled, stats.added,
			stats.sides))
		for k, v in pairs(stats.confidence) do
			print("confidence " .. k, v)
		end
		print("TOC lines:")
		for _, l in ipairs(tocLines) do
			print(l)
		end
	end
	-- A leg that matches no pair of stops: the research moved a stop since tools/route_paths.py ran. Not an error (that
	-- route is drawn straight there), but worth re-running the tool for.
	for _, l in ipairs(stale) do
		print("route leg without its stops (re-run tools/route_paths.py): " .. l)
	end
	if check then
		if #differs > 0 then
			print("out of date (run `lua tools/gen_plans.lua`):")
			for _, p in ipairs(differs) do
				print("  " .. p)
			end
			os.exit(1)
		end
		print("generated plans are up to date")
	else
		print(string.format("wrote %d plans (%d changed), %d bytes", stats.files, #differs, stats.bytes))
	end
end

-- Run as a script; `dofile` from the tests only returns these.
if arg and type(arg[0]) == "string" and arg[0]:find("gen_plans", 1, true) then
	main(arg)
end
return { DecodeJSON = decode, Same = same }
