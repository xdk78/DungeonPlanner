-- Generates the bundled travel facts (Data/TravelData.lua): where each recommended plan's instance is entered outside,
-- the flight masters and the boats and zeppelins, and the researched places (zone, the area the entrance lies in, the
-- zone's faction, Forever's summoning stones, a hint of our own). Schema and sources: data-src/travel/README.md.
--   lua tools/gen_travel.lua                      writes Data/TravelData.lua
--   lua tools/gen_travel.lua --check              writes nothing; exits 1 when the JSON is invalid or the file differs
--   lua tools/gen_travel.lua --openmap <folder>   first refreshes data-src/travel/openmap.json from a local OpenMap
--                                                 install (MIT; its Data/Forever/Places.lua and FlightData.lua)
--   lua tools/gen_travel.lua --report             also prints the coverage
-- Plain Lua 5.1, run from the repository root; deterministic output.

local IN_DIR = "data-src/travel"
local PLANS_DIR = "data-src/dungeons"
local OUT = "Data/TravelData.lua"

local plans = dofile("tools/gen_plans.lua")
local decode = plans.DecodeJSON
local bosses = dofile("tools/gen_bosses.lua")

local M = {}
M.FACTIONS = { alliance = true, horde = true, contested = true, neutral = true }
M.APPROACH = { cave = true, building = true, mountain = true, open = true, underwater = true, ship = true, tower = true }
M.MAX_HINT = 80
-- A dock belongs to the factions of the flight masters within this many yards of it; a boat or zeppelin leg is one
-- faction's when both its docks are that faction's only (Grom'gol, Orgrimmar and Undercity: Horde; Menethil,
-- Theramore, Auberdine: Alliance). A dock without a flight master that near says nothing, and the leg stays open to both.
M.DOCK_RADIUS = 1000

-- OpenMap's instance names (the Group Finder's) for each plan slug.
M.OPENMAP_SLUGS = {
	["Shadowfang Keep"] = { "shadowfang-keep" }, ["Stormwind Stockade"] = { "the-stockade" },
	["Deadmines"] = { "the-deadmines" }, ["Wailing Caverns"] = { "wailing-caverns" },
	["Razorfen Kraul"] = { "razorfen-kraul" }, ["Blackfathom Deeps"] = { "blackfathom-deeps" },
	["Uldaman"] = { "uldaman" }, ["Gnomeregan"] = { "gnomeregan" }, ["Sunken Temple"] = { "temple-of-atalhakkar" },
	["Razorfen Downs"] = { "razorfen-downs" },
	["Scarlet Monastery - Graveyard"] = { "scarlet-monastery-graveyard" },
	["Scarlet Monastery - Library"] = { "scarlet-monastery-library" },
	["Scarlet Monastery - Armory"] = { "scarlet-monastery-armory" },
	["Scarlet Monastery - Cathedral"] = { "scarlet-monastery-cathedral" },
	["Zul'Farrak"] = { "zulfarrak" }, ["Lower Blackrock Spire"] = { "lower-blackrock-spire" },
	["Upper Blackrock Spire"] = { "upper-blackrock-spire" }, ["Molten Core"] = { "molten-core" },
	["Blackwing Lair"] = { "blackwing-lair" }, ["Blackrock Depths"] = { "blackrock-depths" },
	["Onyxia's Lair"] = { "onyxias-lair" }, ["Scholomance"] = { "scholomance" }, ["Zul'Gurub"] = { "zulgurub" },
	["Stratholme"] = { "stratholme-live", "stratholme-undead" }, ["Maraudon"] = { "maraudon" },
	["Ragefire Chasm"] = { "ragefire-chasm" }, ["Dire Maul - East"] = { "dire-maul-east" },
	["Dire Maul - West"] = { "dire-maul-west" }, ["Dire Maul - North"] = { "dire-maul-north" },
	["Ruins of Ahn'Qiraj"] = { "ruins-of-ahnqiraj" }, ["Ahn'Qiraj Temple"] = { "temple-of-ahnqiraj" },
	["City of Dalaran"] = { "city-of-dalaran" }, ["The Drowned City"] = { "the-drowned-city" },
	["Blackmaw Hold"] = { "blackmaw-hold" }, ["Alcaz Prison"] = { "alcaz-prison" },
	["Excavation Site: Wetlands"] = { "excavation-site-wetlands" }, ["Ruins of Lordaeron"] = { "ruins-of-lordaeron" },
	["Shaper's Terrace"] = { "shapers-terrace" }, ["Krol'dok Stronghold"] = { "kroldok-stronghold" },
	["The Hall of Thanes"] = { "hall-of-thanes" },
}

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function writeFile(path, text)
	local w = assert(io.open(path, "wb"))
	w:write(text)
	w:close()
end

-- JSON (sorted keys, one space indent like the other data-src files) -------------------------------------------------

local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n == #t
end

local function encode(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "string" then
		return (string.format("%q", v):gsub("\\\n", "\\n"))
	elseif t == "number" then
		if v == math.floor(v) then
			return string.format("%d", v)
		end
		return (string.format("%.4f", v):gsub("0+$", ""))
	elseif t == "boolean" then
		return tostring(v)
	elseif t ~= "table" then
		return "null"
	end
	local inner = indent .. " "
	local parts = {}
	if isArray(v) then
		if #v == 0 then
			return "[]"
		end
		local flat = true
		for _, x in ipairs(v) do
			flat = flat and type(x) ~= "table"
		end
		for i, x in ipairs(v) do
			parts[i] = encode(x, inner)
		end
		if flat then
			return "[" .. table.concat(parts, ", ") .. "]"
		end
		return "[\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "]"
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then
			return na < nb
		end
		return a < b
	end)
	for i, k in ipairs(keys) do
		local x = v[k]
		if x == nil then
			x = v[tonumber(k)]
		end
		parts[i] = string.format("%q", k) .. ": " .. encode(x, inner)
	end
	return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "}"
end
M.Encode = encode

-- OpenMap's data files, read as data in an empty environment (they only assign tables to their namespace).
local function loadOpenMap(folder, file)
	local path = folder .. "/Data/Forever/" .. file
	local chunk = assert(loadfile(path))
	local ns = {}
	setfenv(chunk, {})
	chunk(nil, ns)
	return ns
end

function M.FromOpenMap(folder)
	local places = loadOpenMap(folder, "Places.lua").MapPlaces
	local flights = loadOpenMap(folder, "FlightData.lua").MapFlights
	local entrances = {}
	for _, g in ipairs(places.instances) do
		for _, inst in ipairs(g[4]) do
			for _, slug in ipairs(M.OPENMAP_SLUGS[inst[2]] or {}) do
				if g.map then
					entrances[slug] = { map = g.map, x = g[2], y = g[3] }
				else
					entrances[slug] = { continent = g[1], x = g[2], y = g[3] }
				end
			end
		end
	end
	local nodes = {}
	for id, n in pairs(flights.nodes) do
		-- Class-only flight paths (a sixth field) are left out.
		if n[6] == nil then
			nodes[#nodes + 1] = { id = id, name = n[1], continent = n[2], x = n[3], y = n[4], factions = n[5] }
		end
	end
	table.sort(nodes, function(a, b)
		return a.id < b.id
	end)
	local transports = {}
	for _, t in ipairs(places.transports or {}) do
		transports[#transports + 1] = { kind = t[1], route = t[2], continent = t[3], x = t[4], y = t[5],
			toContinent = t[6], toX = t[7], toY = t[8], faction = t.faction }
	end
	return {
		schema = 1,
		source = "OpenMap (MIT): Data/Forever/Places.lua, Data/Forever/FlightData.lua, from the game's tables",
		entrances = entrances,
		nodes = nodes,
		transports = transports,
	}
end

-- The factions a dock serves, from the flight masters near it: { alliance = bool, horde = bool }, or nil when none is
-- near. Flight master factions: 1 Alliance, 2 Horde, 3 both.
local function dockFactions(nodes, continent, x, y)
	local out
	for _, nd in ipairs(nodes or {}) do
		if nd.continent == continent and math.sqrt((nd.x - x) ^ 2 + (nd.y - y) ^ 2) <= M.DOCK_RADIUS then
			out = out or { alliance = false, horde = false }
			out.alliance = out.alliance or nd.factions ~= 2
			out.horde = out.horde or nd.factions ~= 1
		end
	end
	return out
end

-- A transport leg's faction ("alliance" | "horde") from both docks' flight masters, or nil (both, or unknown).
function M.TransportFaction(t, nodes)
	local from = dockFactions(nodes, t.continent, t.x, t.y)
	local to = t.toX and dockFactions(nodes, t.toContinent, t.toX, t.toY)
	if not (from and to) then
		return nil
	end
	local alliance, horde = from.alliance and to.alliance, from.horde and to.horde
	if alliance ~= horde then
		return alliance and "alliance" or "horde"
	end
	return nil
end

-- Validation ----------------------------------------------------------------------------------------------------------

local function num(v)
	return type(v) == "number" and v == v and math.abs(v) < 1e6
end

function M.Validate(openmap, placesDoc, slugs)
	local errs = {}
	local function err(...)
		errs[#errs + 1] = string.format(...)
	end
	if type(openmap) ~= "table" or openmap.schema ~= 1 then
		err("openmap.json: schema must be 1")
		return errs
	end
	for slug, e in pairs(openmap.entrances or {}) do
		if not slugs[slug] then
			err("openmap.json: entrance for unknown plan %s", slug)
		end
		local fine = num(e.x) and num(e.y)
		if e.map then
			fine = fine and e.x >= 0 and e.x <= 1 and e.y >= 0 and e.y <= 1
		else
			fine = fine and num(e.continent)
		end
		if not fine then
			err("openmap.json: bad entrance for %s", slug)
		end
	end
	for i, n in ipairs(openmap.nodes or {}) do
		if not (num(n.id) and type(n.name) == "string" and num(n.continent) and num(n.x) and num(n.y)
			and (n.factions == 1 or n.factions == 2 or n.factions == 3)) then
			err("openmap.json: bad flight node %d", i)
		end
	end
	for i, t in ipairs(openmap.transports or {}) do
		if not (type(t.kind) == "string" and type(t.route) == "string" and num(t.continent) and num(t.x) and num(t.y)
			and num(t.toContinent)) then
			err("openmap.json: bad transport %d", i)
		end
	end
	if type(placesDoc) ~= "table" or placesDoc.schema ~= 1 or type(placesDoc.places) ~= "table" then
		err("places.json: schema must be 1 with places")
		return errs
	end
	local sources = {}
	for _, s in ipairs(placesDoc.sources or {}) do
		if num(s.id) and type(s.name) == "string" and type(s.url) == "string" and type(s.licence) == "string" then
			sources[s.id] = true
		else
			err("places.json: a source needs id, name, url and licence")
		end
	end
	for slug, p in pairs(placesDoc.places) do
		local at = "places.json " .. slug
		if not slugs[slug] then
			err("%s: not a recommended plan", at)
		end
		if type(p.zone) ~= "string" or p.zone == "" then
			err("%s: zone missing", at)
		end
		if not (num(p.zoneMap) and p.zoneMap > 0 and p.zoneMap == math.floor(p.zoneMap)) then
			err("%s: zoneMap (the zone's uiMapID) missing", at)
		end
		if p.zoneFaction ~= nil and not M.FACTIONS[p.zoneFaction] then
			err("%s: unknown zoneFaction", at)
		end
		if p.approach ~= nil and not M.APPROACH[p.approach] then
			err("%s: unknown approach", at)
		end
		if p.hint ~= nil and (type(p.hint) ~= "string" or #p.hint > M.MAX_HINT or p.hint:find("[|%c]")) then
			err("%s: bad hint", at)
		end
		if p.stone ~= nil and not (type(p.stone.zone) == "string" and num(p.stone.map) and p.stone.map > 0
			and num(p.stone.x) and num(p.stone.y)) then
			err("%s: bad stone", at)
		end
		for _, s in ipairs(p.src or {}) do
			if not sources[s] then
				err("%s: unknown source %s", at, tostring(s))
			end
		end
		if not p.src or #p.src == 0 then
			err("%s: no source", at)
		end
	end
	-- An entrance needs its place: the zone the card names and the map it is drawn on.
	for slug in pairs(openmap.entrances or {}) do
		if slugs[slug] and not placesDoc.places[slug] then
			err("places.json: %s has an entrance but no place", slug)
		end
	end
	return errs
end

-- Rendering -----------------------------------------------------------------------------------------------------------

local function q(s)
	return (string.format("%q", s):gsub("\\\n", "\\n"))
end

local function n(v)
	if v == math.floor(v) then
		return string.format("%d", v)
	end
	return (string.format("%.4f", v):gsub("0+$", ""))
end

function M.Render(openmap, placesDoc, names)
	local out = {
		"-- GENERATED by tools/gen_travel.lua from data-src/travel/openmap.json and places.json. Do not edit by hand:",
		"-- change the data or the generator and run `lua tools/gen_travel.lua`. Sources: OpenMap (MIT; the game's tables),",
		"-- warcraft.wiki.gg (facts only; hints in our own words). docs/DATA-SOURCES.md.",
		"",
		"local _, ns = ...",
		"ns.TravelData = {",
		"\t-- [instance name] = { e = entrance { c, x, y } (world yards: x north, y west) or { map, x, y } (0..1),",
		"\t--   zone (English), zm (the zone's uiMapID), sub, fac (zone faction), how (approach),",
		"\t--   stone = { map, zone, x, y } (0-100 on that map), hint }",
		"\tinstances = {",
	}
	local slugs = {}
	for slug in pairs(names) do
		slugs[#slugs + 1] = slug
	end
	table.sort(slugs, function(a, b)
		return names[a] < names[b]
	end)
	for _, slug in ipairs(slugs) do
		local e = openmap.entrances[slug]
		local p = placesDoc.places[slug]
		if e or p then
			local f = {}
			if e and e.map then
				f[#f + 1] = string.format("e = { map = %d, x = %s, y = %s }", e.map, n(e.x), n(e.y))
			elseif e then
				f[#f + 1] = string.format("e = { c = %d, x = %s, y = %s }", e.continent, n(e.x), n(e.y))
			end
			if p then
				f[#f + 1] = "zone = " .. q(p.zone)
				f[#f + 1] = string.format("zm = %d", p.zoneMap)
				if p.subzone then
					f[#f + 1] = "sub = " .. q(p.subzone)
				end
				if p.zoneFaction then
					f[#f + 1] = "fac = " .. q(p.zoneFaction)
				end
				if p.approach then
					f[#f + 1] = "how = " .. q(p.approach)
				end
				if p.stone then
					f[#f + 1] = string.format("stone = { map = %d, zone = %s, x = %s, y = %s }", p.stone.map,
						q(p.stone.zone), n(p.stone.x), n(p.stone.y))
				end
			end
			if p and p.hint then
				f[#f + 1] = "hint = " .. q(p.hint)
			end
			out[#out + 1] = "\t\t[" .. q(names[slug]) .. "] = {\n\t\t\t" .. table.concat(f, ",\n\t\t\t") .. ",\n\t\t},"
		end
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "\t-- flight masters: { id, name, continent, x, y, factions = 1 Alliance | 2 Horde | 3 both }"
	out[#out + 1] = "\tnodes = {"
	for _, nd in ipairs(openmap.nodes) do
		out[#out + 1] = string.format("\t\t{ %d, %s, %d, %s, %s, %d },", nd.id, q(nd.name), nd.continent, n(nd.x), n(nd.y),
			nd.factions)
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "\t-- boats, zeppelins, airships: { kind, route, continent, x, y, toContinent, faction? } (faction: both docks'"
	out[#out + 1] = "\t-- flight masters serve only it; none: open to both or not known)"
	out[#out + 1] = "\ttransports = {"
	for _, t in ipairs(openmap.transports) do
		local faction = t.faction and t.faction:lower() or M.TransportFaction(t, openmap.nodes)
		out[#out + 1] = string.format("\t\t{ %s, %s, %d, %s, %s, %d%s },", q(t.kind), q(t.route), t.continent, n(t.x),
			n(t.y), t.toContinent, faction and (", " .. q(faction)) or "")
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

-- Main ----------------------------------------------------------------------------------------------------------------

local function main(args)
	local check, report, openmapDir = false, false, nil
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--check" then
			check = true
		elseif a == "--report" then
			report = true
		elseif a == "--openmap" then
			openmapDir = args[i + 1]
			i = i + 1
		end
		i = i + 1
	end
	local names, slugs = {}, {}
	for _, file in ipairs(bosses.ListFiles(PLANS_DIR, ".json")) do
		local doc = decode(assert(readFile(PLANS_DIR .. "/" .. file)))
		local slug = file:gsub("%.json$", "")
		names[slug], slugs[slug] = doc.name, true
	end
	local differs = {}
	local omPath = IN_DIR .. "/openmap.json"
	if openmapDir then
		local text = encode(M.FromOpenMap(openmapDir))
		if readFile(omPath) ~= text then
			differs[#differs + 1] = omPath
			if not check then
				writeFile(omPath, text)
			end
		end
	end
	local openmap = decode(assert(readFile(omPath), "missing " .. omPath))
	local placesDoc = decode(assert(readFile(IN_DIR .. "/places.json"), "missing places.json"))
	local errs = M.Validate(openmap, placesDoc, slugs)
	if #errs > 0 then
		for _, e in ipairs(errs) do
			print(e)
		end
		os.exit(1)
	end
	local text = M.Render(openmap, placesDoc, names)
	if readFile(OUT) ~= text then
		differs[#differs + 1] = OUT
		if not check then
			writeFile(OUT, text)
		end
	end
	if report then
		local e, p, s = 0, 0, 0
		for slug in pairs(slugs) do
			e = e + (openmap.entrances[slug] and 1 or 0)
			p = p + (placesDoc.places[slug] and 1 or 0)
			s = s + ((placesDoc.places[slug] or {}).stone and 1 or 0)
		end
		print(string.format("plans %d, entrances %d, places %d, stones %d, flight masters %d, transports %d, bytes %d",
			#bosses.ListFiles(PLANS_DIR, ".json"), e, p, s, #openmap.nodes, #openmap.transports, #text))
	end
	if check then
		if #differs > 0 then
			print("out of date (run `lua tools/gen_travel.lua`):")
			for _, path in ipairs(differs) do
				print("  " .. path)
			end
			os.exit(1)
		end
		print("generated travel facts are up to date")
	else
		print(string.format("wrote %s (%d changed)", OUT, #differs))
	end
end

if arg and type(arg[0]) == "string" and arg[0]:find("gen_travel", 1, true) then
	main(arg)
end
return M
