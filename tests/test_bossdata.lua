-- Bundled boss facts (tools/gen_bosses.lua, data-src/bosses/*.json, Data/BossData.lua, Data/Bosses/*.lua): the data files
-- validate, every boss of every recommended plan has an entry, IDs are numbers, the generator refuses bad input, the
-- generated Lua is current, and the lookups have the adapter's shape and are what BossInfo, portraits and loot use first.
local T = ...
local ns = T.ns
ns.BossData.enabled = true -- the other test files switch it off for the provider path
T.finish = nil
local G = dofile("tools/gen_bosses.lua")
local P = dofile("tools/gen_plans.lua")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local function slugs()
	local out = {}
	for _, name in ipairs(G.ListFiles("data-src/bosses", ".json")) do
		out[#out + 1] = (name:gsub("%.json$", ""))
	end
	return out
end

local function isInt(v)
	return type(v) == "number" and v == math.floor(v) and v > 0
end

T.case("BossData: every data file validates, all IDs are numbers, every plan boss has an entry", function()
	local list = slugs()
	T.eq(#list, 43, "one file per recommended plan")
	for _, slug in ipairs(list) do
		local doc = P.DecodeJSON(read("data-src/bosses/" .. slug .. ".json"))
		local plan = P.DecodeJSON(read("data-src/dungeons/" .. slug .. ".json"))
		local errs = G.Validate(doc, slug .. ".json", plan)
		T.eq(#errs, 0, table.concat(errs, "; "))
		local named = {}
		for _, b in ipairs(doc.bosses) do
			named[b.point] = true
			T.ok(b.npcID == nil or isInt(b.npcID), slug .. " " .. b.name .. " npcID")
			T.ok(b.displayID == nil or isInt(b.displayID), slug .. " " .. b.name .. " displayID")
			for _, a in ipairs(b.abilities or {}) do
				T.ok(isInt(a.spell), slug .. " " .. b.name .. " spell")
			end
			for _, l in ipairs(b.loot or {}) do
				T.ok(isInt(l.item), slug .. " " .. b.name .. " item")
			end
		end
		for _, p in ipairs(plan.points) do
			if p.kind == "boss" then
				T.ok(named[p.id], slug .. ": boss " .. p.name .. " has no entry")
			end
		end
	end
end)

T.case("BossData: the generator refuses bad data", function()
	local good = [[{ "schema": 1, "updated": "2026-11-16", "slug": "x", "name": "X", "kind": "dungeon", "origin": "classic",
		"sources": [ { "id": 1, "name": "S", "url": "u", "licence": "facts" } ],
		"bosses": [ { "point": "p1", "name": "A", "npcID": 5, "displayID": 6, "level": [10, 11], "class": "elite",
			"abilities": [ { "spell": 7, "tags": [ "interrupt" ], "src": 1 } ], "loot": [ { "item": 8, "src": 1 } ] } ] }]]
	local plan = { points = { { id = "p1", kind = "boss", name = "A" } } }
	T.eq(#G.Validate(P.DecodeJSON(good), "x.json", plan), 0, "good data")
	local function bad(from, to, what)
		local errs = G.Validate(P.DecodeJSON((good:gsub(from, to))), "x.json", plan)
		T.ok(#errs > 0, what)
	end
	bad('"npcID": 5', '"npcID": "5"', "npc ID as text")
	bad('"displayID": 6', '"displayID": 0', "display ID zero")
	bad('"interrupt"', '"flee"', "unknown tag")
	bad('"item": 8, "src": 1', '"item": 8, "src": 9', "unknown source")
	bad('"level": %[10, 11%]', '"level": [12, 11]', "level range")
	bad('"class": "elite"', '"class": "boss"', "class")
	bad('"p1", "name": "A"', '"p1", "name": "B"', "plan boss of another name")
	local missing = G.Validate(P.DecodeJSON(good), "x.json", { points = { { id = "p1", kind = "boss", name = "A" },
		{ id = "p2", kind = "boss", name = "B" } } })
	T.eq(#missing, 1, "a plan boss without an entry")
	local noData = G.Validate(P.DecodeJSON([[{ "schema": 1, "updated": "2026-11-16", "slug": "x", "name": "X", "kind": "dungeon",
		"sources": [ { "id": 1, "name": "S", "url": "u", "licence": "facts" } ], "bosses": [ { "point": "p1", "name": "A" } ] }]]),
		"x.json", plan)
	T.eq(#noData, 1, "an empty entry needs a gap reason")
end)

T.case("BossData: the generated Lua files match the JSON", function()
	for _, slug in ipairs(slugs()) do
		local doc = P.DecodeJSON(read("data-src/bosses/" .. slug .. ".json"))
		T.ok(G.Render(doc, slug .. ".json") == read("Data/Bosses/" .. slug .. ".lua"), slug .. " is out of date")
	end
end)

T.case("BossData: lookups have the provider adapter's shape and match by instance and boss name", function()
	local B = ns.BossData
	local plan = ns.Bundled.Get("b:the-deadmines")
	local function enc(name)
		for _, e in ipairs(plan.encounters) do
			if e.name == name then
				return e
			end
		end
	end
	local smite = enc("Mr. Smite")
	T.ok(smite, "plan boss")
	local info = B.Boss(plan, smite)
	T.eq(info.level, "20", "level text")
	T.eq(info.npcID, 646)
	T.ok(#info.drops > 0 and isInt(info.drops[1].itemID), "drops")
	T.ok(#info.abilities > 0 and isInt(info.abilities[1].spellID) and type(info.abilities[1].tags) == "table", "abilities")
	T.eq(B.Portrait(plan, smite).displayInfo, B.Entry(plan, smite).disp, "portrait")
	T.eq(#B.Loot(plan, smite), #info.drops)
	T.eq(B.Boss(plan, { name = "Nobody" }), nil, "unknown boss")
	T.eq(B.Boss({ instance = { name = "Nowhere" } }, smite), nil, "unknown instance")
	T.eq(B.Boss(nil, smite), nil, "no plan")
	local sneed = enc("Sneed's Shredder / Sneed")
	if sneed then
		T.ok(B.Entry(plan, { name = "Sneed" }), "either part of a group name matches")
	end
	T.ok(#(B.Quests(plan) or {}) > 0, "quests of the Deadmines")
	local c = B.Counts()
	T.eq(c.instances, 43)
end)

T.case("BossData: BossInfo, portraits and loot use the bundled facts first and a provider fills the rest", function()
	local P2 = ns.Providers
	P2.Reset()
	P2.ResetCaches()
	local plan = ns.Bundled.Get("b:the-deadmines")
	local smite
	for _, e in ipairs(plan.encounters) do
		if e.name == "Mr. Smite" then
			smite = e
		end
	end
	local info = ns.BossInfo.For(plan, smite)
	T.eq(info.level, "20")
	T.ok(info.dropsCredit and info.dropsCredit:find("Wowhead", 1, true), "drops credit names the sources")
	local sections = ns.BossInfo.Sections(plan, smite)
	local ids = {}
	for _, s in ipairs(sections) do
		ids[s.id] = s
	end
	T.ok(ids.abilities and #ids.abilities.abilities > 0, "an abilities section without any provider")
	T.ok(ids.drops and #ids.drops.items > 0, "a drops section without any provider")
	T.ok(ns.Providers.Portrait(plan, smite).displayInfo, "portrait without any provider")
	T.ok(#ns.Providers.Loot(plan, smite) > 0, "loot without any provider")
	T.ok(#ns.BossInfo.KeyAbilities(plan, smite, 3) <= 3, "at most three key abilities")
	T.eq(ns.BossInfo.TagText({ "interrupt", "dispel" }), "Interrupt, Dispel")
	ns.BossData.enabled = false
end)
