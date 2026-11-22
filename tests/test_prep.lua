-- Prep: the pure model (Model/Prep.lua: quests, keys, group, bearings, flight masters, crossings, the run-mode
-- summary), the bundled keys and travel facts (Data/BossData.lua, Data/Travel.lua, tools/gen_travel.lua), the game reads
-- (Data/PrepInfo.lua) and navigation (Data/Navigation.lua with the TomTom, Polestar and Shortest Path Forever
-- adapters, Questie's givers), the prep notes field, and the UI: the Prep section, the Getting there window, run mode's
-- prep line and the home preview's button.
local T = ...
local ns, mock = T.ns, T.mock
local Prep = ns.Prep

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.BossData.enabled = true -- the provider tests switch the bundled facts off
	mock.playerPos = nil
end

local function bundled(slug)
	return ns.Bundled.Get(ns.Bundled.PREFIX .. slug)
end

T.case("Prep.Quests: the other faction's quests hidden, status by log and level, done hidden by default", function()
	local quests = {
		{ questID = 1, name = "Zeta", level = 20, req = 15, side = "alliance" },
		{ questID = 2, name = "Alpha", level = 18, req = 14, side = "horde" },
		{ questID = 3, name = "Beta", level = 22, req = 21, side = "both" },
		{ questID = 4, name = "Gamma", level = 19 },
		{ questID = 5, name = "Done one", level = 17 },
		{ questID = 4, name = "Gamma again" },
	}
	local env = { faction = "alliance", level = 18,
		completed = function(id) return id == 5 end,
		inLog = function(id) return id == 4 end,
		title = function(id) return id == 1 and "Zeta (client)" or nil end }
	local rows, counts = Prep.Quests(quests, env)
	T.eq(counts.other, 1, "the Horde quest is not counted")
	T.eq(counts.total, 4)
	T.eq(counts.log, 1)
	T.eq(counts.available, 1)
	T.eq(counts.low, 1)
	T.eq(counts.done, 1)
	T.eq(#rows, 2, "done and too low hidden, duplicate ID once")
	T.eq(rows[1].status, "log")
	T.eq(rows[2].name, "Zeta (client)", "the client's title wins")
	env.showAll = true
	rows = Prep.Quests(quests, env)
	T.eq(rows[#rows].status, "done")
	-- No faction known: every quest counts.
	local _, all = Prep.Quests(quests, {})
	T.eq(all.other, 0)
	T.eq(all.available, 5)
end)

T.case("Prep.Keys, Group, Summary", function()
	local keys = Prep.Keys({
		{ itemID = 10, name = "Key", kind = "key", required = false },
		{ itemID = 11, name = "Seal", kind = "key", required = true },
		{ questID = 20, name = "Attune", kind = "attunement", required = true, side = "horde" },
		{ questID = 21, name = "Chain", kind = "attunement", required = true },
	}, { faction = "alliance", count = function(id) return id == 10 and 1 or 0 end,
		completed = function(id) return id == 21 end })
	T.eq(#keys, 3, "the Horde step left out")
	T.ok(keys[1].required and keys[2].required, "required first")
	local byName = {}
	for _, k in ipairs(keys) do
		byName[k.name] = k
	end
	T.eq(byName.Key.have, true)
	T.eq(byName.Seal.have, false)
	T.eq(byName.Chain.have, true)
	T.eq(Prep.Keys({ { itemID = 1, name = "X", kind = "key" } }, {})[1].have, nil, "unknown without a count")

	local g = Prep.Group({ { name = "A", level = 16, role = "TANK", player = true }, { name = "B", level = 30, role = "DAMAGER" },
		{ name = "C", level = 12, role = "NONE" }, { name = "D" } }, 15, 22, "dungeon")
	T.eq(g.size, 4)
	T.eq(g.low, 1)
	T.eq(g.members[2].fit, "high")
	T.eq(g.members[3].fit, "low")
	T.eq(g.members[4].fit, nil)
	T.eq(g.missing.HEALER, 1)
	T.eq(g.missing.DAMAGER, 2)
	T.eq(g.missing.TANK, 0)
	T.eq(Prep.Group({}, nil, nil, "raid").missing, nil, "a raid has no fixed seats")

	T.eq(Prep.Summary({ available = 0 }, {}), nil)
	local s = Prep.Summary({ available = 3 }, keys)
	T.eq(s.quests, 3)
	T.eq(s.keys, 1)
end)

T.case("Prep bearings, nearest flight masters by faction, crossings", function()
	local d, dir = Prep.Bearing(100, 0)
	T.eq(math.floor(d + 0.5), 100)
	T.eq(dir, "E")
	T.eq(select(2, Prep.Bearing(0, 100)), "S")
	T.eq(select(2, Prep.Bearing(-70, -70)), "NW")
	T.eq(select(2, Prep.Bearing(0, 0)), nil)
	-- World: x north, y west. Deadmines from Sentinel Hill is south-west.
	T.eq(select(2, Prep.WorldBearing(-10628.9, 1036.7, -11207.8, 1681.2)), "SW")
	local nodes = { { 1, "Ally", 0, 0, 0, 1 }, { 2, "Horde", 0, 10, 0, 2 }, { 3, "Both", 0, 500, 0, 3 },
		{ 4, "Far", 1, 0, 0, 1 } }
	local a = Prep.NearestNodes(nodes, 0, 20, 0, "alliance", 2)
	T.eq(#a, 2)
	T.eq(a[1].name, "Ally")
	T.eq(a[2].name, "Both")
	T.eq(Prep.NearestNodes(nodes, 0, 20, 0, "horde", 1)[1].name, "Horde")
	T.eq(#Prep.NearestNodes(nodes, 1, 0, 0, "horde", 2), 0, "no Horde flight master on that continent")
	local ships = Prep.Crossings({ { "boat", "A - B", 0, 0, 0, 1 }, { "boat", "A - B", 0, 1, 1, 1 },
		{ "zeppelin", "C", 1, 0, 0, 0 } }, 0, 1, "alliance")
	T.eq(#ships, 1)
	T.eq(ships[1].route, "A - B")
end)

T.case("Bundled keys and travel facts: generated, valid, matched by instance name", function()
	boot()
	local ony = ns.BossData.Keys(bundled("onyxias-lair"))
	T.ok(ony and #ony >= 3)
	T.eq(ony[1].itemID, 16309)
	T.ok(ony[1].required and ony[1].forever)
	T.eq(ony[2].side, "alliance")
	T.eq(ns.BossData.Keys(bundled("the-deadmines")), nil, "the Deadmines needs no key")
	local rec = ns.Travel.For(bundled("the-deadmines"))
	T.eq(rec.zone, "Westfall")
	T.eq(rec.sub, "Moonbrook")
	T.eq(rec.e.c, 0)
	T.ok(ns.Travel.For({ name = "Deadmines" }) == rec, "a home entry with the finder's name finds it")
	local hot = ns.Travel.For(bundled("hall-of-thanes"))
	T.eq(hot.e.map, 1455)
	T.ok(#ns.Travel.Nodes() > 50 and #ns.Travel.Transports() > 10)
	-- The generator's checks catch broken data.
	local gen = dofile("tools/gen_travel.lua")
	local errs = gen.Validate({ schema = 1, entrances = { nowhere = { x = 2, y = 0.5, map = 1 } }, nodes = {}, transports = {} },
		{ schema = 1, sources = { { id = 1, name = "s", url = "u", licence = "l" } },
			places = { ["the-deadmines"] = { zone = "Westfall", zoneFaction = "everyone", hint = "a|b", src = { 9 } } } },
		{ ["the-deadmines"] = true })
	T.ok(#errs >= 4, "unknown plan, bad entrance, faction, hint, source: " .. #errs)
end)

T.case("Travel: entrance on its zone map, outdoor distance, none inside", function()
	boot()
	ns.Travel.Reset()
	mock.playerPos = nil
	local rec = ns.Travel.For(bundled("hall-of-thanes"))
	local ent = ns.Travel.Entrance(rec)
	T.eq(ent.uiMapID, 1455)
	T.eq(ent.continent, 1455 % 2)
	T.ok(ent.wx ~= nil, "Forever map spot placed in the world")
	local yards, why = ns.Travel.Distance(ent)
	T.eq(yards, nil)
	T.eq(why, "inside", "no position: no distance")
	-- Outdoors on the same map, 100 yards south of the entrance (map y 0.1 more; the mock's maps are 1000 yd tall).
	mock.playerPos = { map = 1455, x = ent.x, y = ent.y + 0.1 }
	yards, why = ns.Travel.Distance(ent)
	T.eq(math.floor(yards + 0.5), 100)
	T.eq(why, "N", "the entrance lies north")
	mock.playerPos = { map = 1456, x = 0.5, y = 0.5 }
	T.eq(select(2, ns.Travel.Distance(ent)), "continent")
	mock.playerPos = nil
	-- A classic entrance in world yards lands on the client's best map.
	local dm = ns.Travel.Entrance(ns.Travel.For(bundled("the-deadmines")))
	T.ok(dm.uiMapID ~= nil)
	T.ok(dm.x >= 0 and dm.x <= 1 and dm.y >= 0 and dm.y <= 1, "a spot on that map")
end)

T.case("Navigation: the game's pin, providers best first, nothing in combat, the map through C_Map only", function()
	boot()
	ns.Providers.Reset()
	mock.waypoints, mock.openedMaps = {}, {}
	local targets = ns.Navigation.Targets(1455)
	T.eq(#targets, 1)
	T.eq(targets[1].id, "game")
	T.eq(#ns.Navigation.Targets(300), 0, "a map that takes no pin")
	T.ok(ns.Navigation.Go("game", { { 1455, 0.3, 0.4, "Hall" } }))
	T.eq(#mock.waypoints, 1)
	T.eq(mock.waypoints[1].uiMapID, 1455)
	T.eq(mock.superTracked, true)
	mock.inCombat = true
	T.ok(not ns.Navigation.Go("game", { { 1455, 0.3, 0.4 } }), "nothing in combat")
	T.ok(not ns.Navigation.CanOpenMap())
	mock.inCombat = false
	ns.Navigation.ShowOnMap(1455, 0.3, 0.4)
	T.eq(mock.openedMaps[1], 1455)
	local globalOpen = false
	_G.OpenWorldMap = function()
		globalOpen = true
	end
	local open = _G.C_Map.OpenWorldMap
	_G.C_Map.OpenWorldMap = nil
	ns.Navigation.ShowOnMap(1455, 0.3, 0.4)
	T.ok(not globalOpen, "never the global OpenWorldMap (it taints the map)")
	_G.C_Map.OpenWorldMap, _G.OpenWorldMap = open, nil
	-- The gamepad interface style (Compat.Gamepad): no map opening.
	local oldEnum = _G.Enum.InputInterfaceStyle
	_G.Enum.InputInterfaceStyle = { KeyboardAndMouse = 0, Gamepad = 1 }
	_G.C_InputInterfaceStyle = { GetCurrentStyle = function()
		return 1
	end }
	ns.Compat.ResetGamepad()
	T.ok(not ns.Navigation.CanOpenMap())
	_G.C_InputInterfaceStyle, _G.Enum.InputInterfaceStyle = nil, oldEnum
	ns.Compat.ResetGamepad()
	T.ok(ns.Navigation.CanOpenMap())
end)

T.case("Navigation adapters: TomTom (the real addon only), Polestar and Shortest Path Forever by their public API", function()
	boot()
	local P = ns.Providers
	local added = {}
	_G.TomTom = { AddWaypoint = function(_, m, x, y, opts)
		added[#added + 1] = { m, x, y, opts.title }
		return #added
	end }
	mock.loadedAddons = { TomTom = false }
	P.Reset()
	T.eq(P.Get("tomtom"), nil, "a stand-in TomTom global without the addon loaded is not used")
	mock.loadedAddons = { TomTom = true }
	P.Reset()
	T.ok(P.Get("tomtom"))
	T.ok(ns.Navigation.Go("tomtom", { { 1436, 0.5, 0.5, "Flight" }, { 1436, 0.4, 0.7, "Entrance" } }))
	T.eq(#added, 2, "the flight master, then the entrance")
	T.eq(added[2][4], "Entrance")

	local navigated
	_G.Polestar = { Nav = { API = { version = 1, Navigate = function(owner, m, x, y, title)
		navigated = { owner, m, x, y, title }
		return true
	end, Estimate = function()
		return 400
	end } } }
	P.Reset()
	local t = ns.Navigation.Targets(1436)
	T.eq(t[1].id, "polestar", "Polestar first")
	T.eq(t[2].id, "tomtom")
	T.eq(t[#t].id, "game")
	T.ok(ns.Navigation.Go("polestar", { { 1436, 0.5, 0.5, "Flight" }, { 1436, 0.4, 0.7, "Entrance" } }))
	T.eq(navigated[1], "DungeonPlanner")
	T.eq(navigated[5], "Entrance", "Polestar takes the destination only")
	T.eq(ns.Navigation.Estimate(1436, 0.4, 0.7), 400)
	_G.Polestar.Nav.API.version = 2
	P.Reset()
	T.eq(P.Get("polestar"), nil, "an unknown API version is not used")

	local spf
	_G.ShortestPathForever = { API = { version = 2, Navigate = function(owner, m)
		spf = { owner, m }
		return true
	end, Cancel = function() end } }
	P.Reset()
	T.ok(ns.Navigation.Go("shortestPath", { { 1436, 0.4, 0.7, "Entrance" } }))
	T.eq(spf[2], 1436)
	_G.ShortestPathForever.API.Cancel = nil
	P.Reset()
	T.eq(P.Get("shortestPath"), nil, "the API without Cancel is not used")
	_G.TomTom, _G.Polestar, _G.ShortestPathForever, mock.loadedAddons = nil, nil, nil, nil
	P.Reset()
end)

T.case("Questie givers: name, area and the first spawn", function()
	boot()
	mock.InstallProviders()
	ns.Providers.Reset()
	local g = ns.Providers.Call("questie", "Givers", { 101, 102, 999 })
	T.eq(g[101].name, "Thane Keeper")
	T.eq(g[101].area, 1537)
	T.eq(g[101].x, 45.2)
	T.eq(g[102], nil, "no starter")
	mock.RemoveProviders()
	ns.Providers.Reset()
end)

T.case("PrepInfo: the Hall of Thanes for an Alliance player at level 12", function()
	boot()
	local plan = bundled("hall-of-thanes")
	mock.questsDone, mock.questLog = { [96393] = true }, { [96395] = true }
	mock.units = {}
	local rows, counts = ns.PrepInfo.Quests(plan, false)
	T.eq(counts.done, 1)
	T.eq(counts.log, 1)
	T.ok(counts.total >= 4)
	T.eq(rows[1].questID, 96395, "the quest in the log first")
	for _, r in ipairs(rows) do
		T.ok(r.status ~= "done")
	end
	local sum = ns.PrepInfo.Summary(plan)
	T.ok(sum and sum.quests >= 1)
	local group = ns.PrepInfo.Group(plan)
	T.eq(group.size, 1, "only the player")
	T.eq(group.members[1].player, true)
	mock.questsDone, mock.questLog = {}, {}
end)

T.case("Prep notes: plan format 5, stored only when written, saved data moves to schema 6", function()
	boot()
	local p = ns.Validate.Plan({ name = "P", prep = "Flasks\nFood" })
	T.eq(p.prep, "Flasks\nFood")
	T.eq(ns.Validate.Plan({ name = "Q" }).prep, nil)
	T.eq(ns.Validate.Plan({ name = "Q", prep = "" }).prep, nil)
	T.ok(ns.Plan.SetField(p, "prep", "Bandages"))
	T.eq(p.prep, "Bandages")
	T.eq(ns.Schema.PLAN_VERSION, 5)
	T.eq(ns.DB.SCHEMA, 6)
	-- The 5 -> 6 step: nothing to convert, the data is marked (an older version opens it read-only).
	local five = { schema = 5, plans = { p1 = { id = "p1", name = "Five", prep = "y" } }, shareLinks = {} }
	T.ok(ns.DB.Migrate(five, 6, ns.DB.migrations))
	T.eq(five.schema, 6)
	T.eq(five.plans.p1.prep, "y")
	local global = { schema = 4, plans = { p1 = { id = "p1", name = "Old", prep = "x" } } }
	local info = ns.DB.LoadGlobal(global)
	T.eq(global.schema, ns.DB.SCHEMA)
	T.eq(info.migratedFrom, 4)
	T.eq(global.plans.p1.prep, "x")
end)

T.case("Prep UI: the section, the Getting there window, run mode's prep line, the home preview's button", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "the-deadmines")
	ns.UI.SelectTab("prep")
	ns.UI.RefreshPage()
	local page = _G.DungeonPlannerMainFrame.instancePage
	local panel = page.panels.prep
	T.ok(panel and panel:IsShown(), "the Prep section is built and shown")
	T.ok(panel.notesText:IsShown() and not panel.notes:IsShown(), "a recommended plan's notes are not editable")
	-- The card's lines: zone, territory, the way from each faction's flight master.
	local lines = ns.GettingThere.Lines(bundled("the-deadmines"))
	local text = {}
	for _, l in ipairs(lines) do
		text[#text + 1] = l[2]
	end
	text = table.concat(text, "\n")
	T.ok(text:find("Westfall", 1, true) and text:find("Moonbrook", 1, true), text)
	T.ok(text:find("Sentinel Hill", 1, true), "the Alliance flight master")
	T.ok(text:find("outdoors", 1, true), "no position: says where distances show")
	T.ok(page.panels.prep.bar.nav:IsShown())
	-- TomTom's chain: the nearest flight master, then the entrance.
	local pts = ns.GettingThere.Points(ns.GettingThere.Facts(bundled("the-deadmines")), true)
	T.eq(#pts, 2)
	T.ok(pts[1][4]:find("Sentinel Hill", 1, true))
	T.eq(#ns.GettingThere.Points(ns.GettingThere.Facts(bundled("the-deadmines"))), 1, "the entrance alone")
	-- The window opens from the home preview without a plan.
	local w = ns.GettingThere.Open({ name = "Deadmines", kind = "dungeon" })
	T.ok(w:IsShown())
	w:Hide()
	-- Run mode: the prep line before the first step only.
	mock.questsDone, mock.questLog = {}, {}
	ns.RunMode.Show()
	ns.UI.FocusStep(1)
	ns.RunMode.Refresh()
	local text1 = ns.RunMode.PrepText(bundled("the-deadmines"))
	T.ok(text1 and text1:find("quests? to pick up"), tostring(text1))
	ns.UI.FocusStep(3)
	T.eq(ns.RunMode.PrepText(bundled("the-deadmines")), nil, "after the first step: no prep line")
	ns.RunMode.Hide()
	-- The home preview: the zone (its map's name, in the client's language) in its subtitle and the Getting there button.
	ns.UI.GoHome("dungeons")
	mock.mapInfo[1436] = { name = "Westfalia" }
	local preview = _G.DungeonPlannerMainFrame.home.preview
	preview:ShowEntry({ key = "dm", name = "The Deadmines", kind = "dungeon" }, nil)
	T.ok(preview.travel:IsShown())
	T.ok(preview.sub:GetText():find("Westfalia", 1, true), preview.sub:GetText())
	preview:ShowEntry({ key = "x", name = "Nowhere Keep", kind = "dungeon" }, nil)
	T.ok(not preview.travel:IsShown(), "no button without travel facts")
	mock.mapInfo = {}
end)

local function cardText(target)
	local out = {}
	for _, l in ipairs(ns.GettingThere.Lines(target)) do
		out[#out + 1] = l[2]
	end
	return table.concat(out, "\n")
end

T.case("Travel: the entrance on its bundled zone map, names in the client's language, the continent by parents", function()
	boot()
	ns.UI.Show() -- the home table's preview below
	ns.Travel.Reset()
	ns.Instances.ForgetMapNames()
	local rec = ns.Travel.For(bundled("the-deadmines"))
	T.eq(rec.zm, 1436, "the zone's uiMapID ships with the record")
	-- A German client: the zone map's name is not "Westfall", so a name lookup would miss it; the bundled ID does not.
	mock.mapBoxes[1436] = { 0, rec.e.x + 500, rec.e.y + 5000 }
	mock.mapInfo[1436] = { name = "Westfalia", mapType = 3, parentMapID = 1415 }
	mock.mapInfo[1415] = { name = "Oestliche Koenigreiche", mapType = 2, parentMapID = 947 }
	mock.mapInfo[1416] = { name = "Alteracgebirge", mapType = 3, parentMapID = 1415 }
	local ent = ns.Travel.Entrance(rec)
	T.eq(ent.uiMapID, 1436, "placed on the zone's own map, not the client's best map")
	T.ok(math.abs(ent.x - 0.5) < 0.001 and math.abs(ent.y - 0.5) < 0.001)
	T.eq(ns.Travel.ZoneName(rec), "Westfalia")
	T.eq(ns.Travel.ContinentName(1436), "Oestliche Koenigreiche", "up the parents to the continent map")
	T.eq(ns.Travel.ContinentName(300), nil, "no continent above")
	local text = cardText(bundled("the-deadmines"))
	T.ok(text:find("Westfalia", 1, true) and text:find("Oestliche Koenigreiche", 1, true), text)
	T.ok(not text:find("Westfall  ", 1, true))
	-- The summoning stone by its map, also in the client's language.
	T.ok(cardText(bundled("city-of-dalaran")):find("Alteracgebirge", 1, true))
	mock.mapBoxes, mock.mapInfo = {}, {}
	ns.Travel.Reset()
	-- Blackrock Depths: the zone is the map the entrance is placed on (Burning Steppes), the area Blackrock Mountain.
	local brdRec = ns.Travel.For(bundled("blackrock-depths"))
	mock.mapBoxes[1428] = { 0, brdRec.e.x + 500, brdRec.e.y + 5000 }
	mock.mapInfo[1428] = { name = "Burning Steppes", mapType = 3, parentMapID = 1415 }
	local brd = cardText(bundled("blackrock-depths"))
	T.ok(brd:find("Burning Steppes  •  Blackrock Mountain", 1, true), brd)
	-- The nearest flight master lies across the mountain in Searing Gorge; its line names that zone.
	T.ok(brd:find("Thorium Point, Searing Gorge", 1, true), brd)
	T.eq(ns.Travel.Where({ zone = "Westfall", zm = 1428, sub = "burning steppes" }), "Burning Steppes",
		"an area that reads the same as the zone shown is left out")
	ns.UI.GoHome("dungeons")
	local preview = _G.DungeonPlannerMainFrame.home.preview
	preview:ShowEntry({ key = "brd", name = "Blackrock Depths", kind = "dungeon" }, nil)
	T.ok(preview.sub:GetText():find("Blackrock Mountain", 1, true), preview.sub:GetText())
	mock.mapBoxes, mock.mapInfo = {}, {}
	ns.Travel.Reset()
	-- The generator: an entrance needs its place, a place its zone map, a stone its map.
	local gen = dofile("tools/gen_travel.lua")
	local errs = gen.Validate({ schema = 1, entrances = { ["the-deadmines"] = { continent = 0, x = 1, y = 2 },
		uldaman = { continent = 0, x = 1, y = 2 } }, nodes = {}, transports = {} },
		{ schema = 1, sources = { { id = 1, name = "s", url = "u", licence = "l" } },
			places = { ["the-deadmines"] = { zone = "Westfall", stone = { zone = "Westfall", x = 1, y = 2 }, src = { 1 } } } },
		{ ["the-deadmines"] = true, uldaman = true })
	local all = table.concat(errs, "\n")
	T.ok(all:find("uldaman has an entrance but no place", 1, true), all)
	T.ok(all:find("zoneMap", 1, true), all)
	T.ok(all:find("bad stone", 1, true), all)
end)

-- Required keys still missing for the bundled plan, as run mode counts them.
local function keysMissing(slug)
	local sum = ns.Prep.Summary({ available = 0 }, ns.PrepInfo.Keys(bundled(slug)))
	return sum and sum.keys or 0
end

T.case("Keys with the bundled data: one per key group, any of a quest's IDs counts", function()
	boot()
	mock.questsDone, mock.itemCounts = {}, {}
	-- Naxxramas: one attunement, three quest IDs (Honored, Revered, Exalted).
	T.eq(keysMissing("naxxramas"), 1)
	mock.questsDone = { [9123] = true }
	T.eq(keysMissing("naxxramas"), 0, "the Exalted version counts")
	T.eq(ns.PrepInfo.Keys(bundled("naxxramas"))[1].have, true)
	-- Molten Core: optional; either ID of Attunement to the Core counts, for both factions.
	mock.questsDone = { [7848] = true }
	local mc = ns.PrepInfo.Keys(bundled("molten-core"))
	T.eq(mc[1].have, true)
	T.eq(keysMissing("molten-core"), 0)
	-- Onyxia (an Alliance player): the amulet and its chain are one key.
	mock.questsDone = {}
	T.eq(keysMissing("onyxias-lair"), 1, "not 2: the amulet and the chain's first quest")
	mock.questsDone = { [4182] = true }
	T.eq(keysMissing("onyxias-lair"), 1, "the chain started, the amulet not yet")
	mock.itemCounts = { [16309] = 1 }
	mock.questsDone = {}
	T.eq(keysMissing("onyxias-lair"), 0, "carrying the amulet settles it")
	-- Upper Blackrock Spire: the seal and its first quest are one key.
	mock.itemCounts = {}
	T.eq(keysMissing("upper-blackrock-spire"), 1)
	mock.itemCounts = { [12344] = 1 }
	T.eq(keysMissing("upper-blackrock-spire"), 0)
	-- Scholomance: both keys are optional (Rattlegore drops the Viewing Room Key inside).
	mock.itemCounts = {}
	T.eq(keysMissing("scholomance"), 0)
	-- Blackwing Lair: the brand quest is the attunement.
	T.eq(keysMissing("blackwing-lair"), 1)
	mock.questsDone = { [7761] = true }
	T.eq(keysMissing("blackwing-lair"), 0)
	mock.questsDone, mock.itemCounts = {}, {}
	-- Rows of the same weight keep the data's order (table.sort alone is not stable): Blackrock Depths' optional keys.
	local want = {}
	for _, k in ipairs(ns.BossData.Keys(bundled("blackrock-depths")) or {}) do
		want[#want + 1] = k.name
	end
	T.ok(#want >= 4, "Blackrock Depths has its optional keys")
	local got = {}
	for _, row in ipairs(ns.Prep.Keys(ns.BossData.Keys(bundled("blackrock-depths")))) do
		got[#got + 1] = row.name
	end
	T.eq(table.concat(got, "|"), table.concat(want, "|"))
	local mixed = ns.Prep.Keys({ { name = "a" }, { name = "b", required = true }, { name = "c" }, { name = "d" },
		{ name = "e", required = true }, { name = "f" }, { name = "g" }, { name = "h" } })
	local order = {}
	for _, row in ipairs(mixed) do
		order[#order + 1] = row.name
	end
	T.eq(table.concat(order), "beacdfgh", "required first, each part in its order")
	-- The generator checks the new fields.
	local gen = dofile("tools/gen_bosses.lua")
	local doc = { keys = { { quest = 1, alt = { 1 }, name = "Q", kind = "attunement", required = true, forever = false,
		group = "Not ok" } } }
	local all = table.concat(gen.Validate(doc, "x.json", nil), "\n")
	T.ok(all:find("alt must", 1, true) and all:find("group must", 1, true), all)
end)

T.case("Boats and zeppelins: a leg is one faction's when both docks' flight masters are", function()
	boot()
	local function routes(faction)
		local out = {}
		for _, t in ipairs(ns.Prep.Crossings(ns.Travel.Transports(), 0, 1, faction)) do
			out[t.route] = true
		end
		return out
	end
	local ally, horde = routes("alliance"), routes("horde")
	T.ok(not ally["Grom'gol - Orgrimmar"] and not ally["Undercity - Orgrimmar"], "no Horde zeppelin for the Alliance")
	T.ok(ally["Menethil Harbor - Theramore"] and ally["Booty Bay - Ratchet"])
	T.ok(horde["Grom'gol - Orgrimmar"] and horde["Undercity - Orgrimmar"] and horde["Booty Bay - Ratchet"])
	T.ok(not horde["Menethil Harbor - Theramore"], "no Alliance boat for the Horde")
	-- Labels name the docks in the direction of travel; OpenMap's route name stays where no flight master names a dock.
	T.ok(routes(nil)["Steamwheedle Port - Powderfuse Port"])
	for _, t in ipairs(ns.Travel.Transports()) do
		T.ok(not t[2]:find("Zepplin", 1, true), t[2])
	end
	local gen = dofile("tools/gen_travel.lua")
	local nodes = { { id = 1, continent = 0, x = 0, y = 0, factions = 2 }, { id = 2, continent = 1, x = 0, y = 0, factions = 3 },
		{ id = 3, continent = 1, x = 5000, y = 0, factions = 2 } }
	nodes[1].name, nodes[2].name, nodes[3].name = "Grom'gol, Stranglethorn", "Ratchet, The Barrens", "Orgrimmar, Durotar"
	T.eq(gen.TransportLabel({ route = "R", continent = 0, x = 10, y = 0, toContinent = 1, toX = 5000, toY = 10 }, nodes),
		"Grom'gol - Orgrimmar")
	T.eq(gen.TransportLabel({ route = "R", continent = 0, x = 3000, y = 0, toContinent = 1, toX = 0, toY = 0 }, nodes),
		"R", "no flight master near one dock: OpenMap's name")
	T.eq(gen.TransportFaction({ continent = 0, x = 10, y = 0, toContinent = 1, toX = 5000, toY = 10 }, nodes), "horde")
	T.eq(gen.TransportFaction({ continent = 0, x = 10, y = 0, toContinent = 1, toX = 0, toY = 10 }, nodes), "horde",
		"a both-faction dock does not open a Horde-only one")
	T.eq(gen.TransportFaction({ continent = 0, x = 3000, y = 0, toContinent = 1, toX = 0, toY = 0 }, nodes), nil,
		"no flight master near one dock: open to both")
end)

T.case("Prep redraws: run mode's line and the Getting there window follow PREP_CHANGED while shown", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	local plan = bundled("the-deadmines")
	ns.UI.SelectPlan(plan.id)
	mock.questsDone, mock.questLog = {}, {}
	ns.RunMode.Show()
	ns.UI.FocusStep(1)
	ns.RunMode.Refresh()
	local run = _G.DungeonPlannerRunFrame
	T.ok(run.prep:IsShown(), "quests to pick up")
	local before = run.prep.text:GetText()
	-- Pick up every quest of the instance: QUEST_ACCEPTED, then the message a moment later.
	for _, q in ipairs(ns.BossData.Quests(plan) or {}) do
		mock.questLog[q.questID] = true
	end
	mock.FireEvent("QUEST_ACCEPTED", 0)
	mock.Advance(ns.PrepInfo.DELAY + 0.1)
	T.ok(not run.prep:IsShown() or run.prep.text:GetText() ~= before, "the line changed: " .. tostring(before))
	ns.RunMode.Hide()
	mock.questLog = {}
	-- The Getting there window redraws while shown, and not once hidden.
	local refreshes, real = 0, ns.GettingThere.Refresh
	ns.GettingThere.Refresh = function(...)
		refreshes = refreshes + 1
		return real(...)
	end
	local w = ns.GettingThere.Open(plan)
	refreshes = 0
	mock.FireEvent("PLAYER_LEVEL_UP", 16)
	mock.Advance(ns.PrepInfo.DELAY + 0.1)
	T.eq(refreshes, 1)
	w:Hide()
	mock.FireEvent("PLAYER_LEVEL_UP", 17)
	mock.Advance(ns.PrepInfo.DELAY + 0.1)
	T.eq(refreshes, 1, "hidden: no redraw")
	ns.GettingThere.Refresh = real
end)

T.case("Prep notes: an own plan's notes show read-only in read-only mode", function()
	boot()
	ns.UI.Show() -- the window's instance page holds the section built below
	local plan = bundled("the-deadmines")
	local ro = true
	local ctx = { Plan = function() return plan end, ReadOnly = function() return ro end }
	local f = ns.Panels.prep.Create(_G.DungeonPlannerMainFrame.instancePage, ctx)
	local texts = {}
	local add = f.notesText.Add
	f.notesText.Add = function(self, style, text)
		texts[#texts + 1] = text
		return add(self, style, text)
	end
	-- Without notes: the hint.
	f:Refresh()
	T.ok(texts[1] and texts[1]:find("editable copy", 1, true), tostring(texts[1]))
	-- With notes (own plan opened read-only): the notes themselves.
	plan = ns.Validate.Plan({ name = "Mine", prep = "Flasks and food" })
	texts = {}
	f:Refresh()
	T.eq(texts[1], "Flasks and food")
	T.ok(f.notesText:IsShown() and not f.notes:IsShown())
	ro = false
	f:Refresh()
	T.ok(f.notes:IsShown(), "editable when not read-only")
	f:Hide()
end)
