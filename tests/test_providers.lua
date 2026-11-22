-- Data providers (Data/Providers.lua and Data/Providers/*.lua) against fake installed addons (tests/wowmock.lua):
-- each adapter with good, missing and malformed data; alignment of plan points with a provider's map; and the UI
-- fixes that go with them (provider map on the canvas with its credit, compact legend off after the first view,
-- party role icons, Fit framing the plan's markers on a map without art).
local T = ...
local ns, mock = T.ns, T.mock
local P = ns.Providers

-- These cases are about other addons' maps: the player prefers them over the game's minimap pictures
-- (settings.preferProviderMaps; Data/MinimapArt.lua and tests/test_minimapart.lua cover the default order).
local function preferProviders(on)
	if ns.db then
		ns.db.settings.preferProviderMaps = on or nil
	end
	ns.MinimapArt.Reset()
end

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

-- These tests are about what the providers answer: the bundled facts (Data/BossData.lua) would answer first.
local function fresh()
	ns.BossData.enabled = false
	P.Reset()
	P.ResetCaches()
end

local function hot()
	return ns.Bundled.Get("b:hall-of-thanes")
end

local function row(id)
	for _, r in ipairs(P.Report()) do
		if r.id == id then
			return r
		end
	end
end

T.case("Providers: nothing installed means every adapter is inactive and nothing changes", function()
	boot()
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
	T.ok(#P.list >= 4, "four adapters registered")
	for _, r in ipairs(P.Report()) do
		T.ok(not r.active, r.id .. " inactive")
	end
	T.eq(P.FloorArt(hot(), 1), nil)
	T.eq(P.Loot(hot(), hot().encounters[1]), nil)
	T.eq(#P.LootLinks(), 0)
	-- The settings hint lists what is not installed (an adapter whose addon the client does not report as loaded).
	for _, a in ipairs(P.Missing()) do
		T.ok(P.AddonLoaded(a.addon) == false, a.id .. " is missing")
	end
end)

T.case("Dungeon Journal adapter: map, pins, loot and portraits from its tables", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	local r = row("dungeonJournal")
	T.ok(r.active and r.internals, "active, reads internals")
	T.eq(r.counts.maps, 1)
	T.eq(r.counts.pins, 4)
	local plan = hot()
	local art = P.FloorArt(plan, 1)
	T.ok(art, "a map for Hall of Thanes")
	T.eq(art.provider, "dungeonJournal")
	T.eq(art.credit, "Dungeon Journal")
	T.eq(art.width, 1024)
	T.eq(art.height, 683, "cropped like the addon crops it")
	T.eq(#art.textures, 1)
	T.eq(#art.pins, 4)
	T.eq(art.align.mode, "same", "the recommended plan's bosses already line up with its map")
	-- Loot for a boss by name; the trash list is not a boss.
	local faldrim
	for _, enc in ipairs(plan.encounters) do
		if enc.name == "Faldrim Anvilmar" then
			faldrim = enc
		end
	end
	local items, credit = P.Loot(plan, faldrim)
	T.eq(#items, 2)
	T.eq(items[1].itemID, 900101)
	T.eq(items[1].quality, 3)
	T.eq(credit, "Dungeon Journal")
	-- Portraits: a baked picture by display ID, else the display ID for a model portrait.
	local pic = P.Portrait(plan, faldrim)
	T.ok(pic and pic.icon and pic.icon:find("Portraits\\555", 1, true), "baked portrait")
	local magmatus
	for _, enc in ipairs(plan.encounters) do
		if enc.name == "Magmatus" then
			magmatus = enc
		end
	end
	T.eq(P.Portrait(plan, magmatus).displayInfo, 777, "a display ID for a model portrait")
	-- Journal.BossArt falls back to the provider (credited) when the journal has no portrait.
	local ej = _G.EJ_GetCreatureInfo
	_G.EJ_GetCreatureInfo = nil
	local unmatched = { id = "x1", name = "Faldrim Anvilmar" }
	local art2 = ns.Journal.BossArt(plan, unmatched)
	_G.EJ_GetCreatureInfo = ej
	if art2 and art2.credit then
		T.eq(art2.credit, "Dungeon Journal")
	end
	mock.RemoveProviders()
	preferProviders(false)
end)

T.case("Dungeon Journal adapter: missing and malformed data switch it off or skip the bad parts", function()
	boot()
	_G.ForeverDungeonJournal_NS = { DB = "not a table" }
	fresh()
	T.ok(not row("dungeonJournal").active, "wrong shape: inactive")
	_G.ForeverDungeonJournal_NS = { DB = {}, DUNGEON_MAPS = 5 }
	fresh()
	T.ok(not row("dungeonJournal").active, "wrong map table: inactive")
	_G.ForeverDungeonJournal_NS = {
		DB = { ["Hall of Thanes"] = { bosses = { { name = "Faldrim Anvilmar", loot = { "junk", { -1 }, { 5, "Ok" } } } } } },
		DUNGEON_MAPS = { ["Hall of Thanes"] = { floors = { { tiles = "classic floor" } }, bosses = { { name = "X", x = 4, y = 0 } } } },
	}
	fresh()
	T.ok(row("dungeonJournal").active)
	T.eq(P.FloorArt(hot(), 1), nil, "a floor without its own picture is not a map")
	local enc = hot().encounters[1]
	local items = P.Loot(hot(), enc)
	T.eq(items and #items, 1, "bad loot rows are skipped")
	-- An error inside the other addon's data switches the adapter off for the session, not us.
	_G.ForeverDungeonJournal_NS = setmetatable({ DB = {} }, { __index = function(_, k)
		if k == "DUNGEON_MAPS" then
			error("boom")
		end
	end })
	fresh()
	T.ok(not row("dungeonJournal").active and row("dungeonJournal").failed, "a raising table: failed, inactive")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("OpenMap adapter: drawn maps with the artist and boss pins per floor; shape checks", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	_G.ForeverDungeonJournal_NS = nil
	fresh()
	local plan = ns.Bundled.Get("b:ruins-of-lordaeron")
	T.ok(plan, "the recommended Ruins of Lordaeron plan")
	local art = P.FloorArt(plan, 1)
	T.ok(art, "OpenMap's drawn map")
	T.eq(art.provider, "openMap")
	T.eq(#art.textures, 12)
	T.eq(art.artist, "An Artist")
	T.eq(#art.pins, 1, "only this floor's bosses")
	T.eq(art.pins[1].name, "Witherfang")
	_G.OpenMap.MapDungeonDrawn[2999][1].tiles[12] = nil
	fresh()
	T.eq(P.FloorArt(plan, 1), nil, "eleven tiles is not a map")
	_G.OpenMap = { MapPlaces = {} }
	fresh()
	T.ok(not row("openMap").active, "no instance list: inactive")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Providers pick a floor by its name, not its position (City of Dalaran's Underbelly)", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	-- Dungeon Journal lists the Underbelly first and labels neither floor.
	_G.ForeverDungeonJournal_NS.DUNGEON_MAPS["City of Dalaran"] = {
		floors = {
			{ texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranUnderbellyMap", texBottom = 1365 / 2048 },
			{ texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranCityMap", texBottom = 1365 / 2048 },
		},
		bosses = { { name = "Atrexis the Grave Knight", floor = 1, x = 0.535, y = 0.505 },
			{ name = "Fel Ancient", floor = 2, x = 0.513, y = 0.549 } },
	}
	fresh()
	local plan = ns.Bundled.Get("b:city-of-dalaran")
	T.eq(plan.floors[1].name, "City of Dalaran")
	local art = P.FloorArt(plan, 1)
	T.ok(art and art.textures[1]:find("DalaranCityMap", 1, true), "plan floor 1 (the city) shows the city")
	T.eq(art.pins[1] and art.pins[1].name, "Fel Ancient", "with the city's pins")
	art = P.FloorArt(plan, 2)
	T.ok(art and art.textures[1]:find("DalaranUnderbellyMap", 1, true), "plan floor 2 shows the Underbelly")
	-- The rule itself: a label, else the most words of the name, else the position.
	local function d(c)
		return c[1], c[2]
	end
	local blackmaw = { floors = { { name = "Blackmaw Grove" }, { name = "Festering Grotto" }, { name = "Fallen Grove" },
		{ name = "Burrow" }, { name = "Elders' Cavern" }, { name = "Forbidden Magic" } } }
	local list = { { "Blackmaw Grove", "BlackmawHoldGroveMap" }, { "Festering Grotto", "BlackmawHoldFesteringGrottoMap" },
		{ "Depths of the Fallen Grove", "BlackmawHoldFallenGroveMap" }, { "Depths of the Elders", "BlackmawHoldEldersMap" },
		{ "Depths of the Burrow", "BlackmawHoldBurrowMap" }, { "Depths of Forbidden Magic", "BlackmawHoldForbiddenMagicMap" } }
	local want = { 1, 2, 3, 5, 4, 6 }
	for f = 1, 6 do
		local _, i = P.PickFloor(blackmaw, f, list, d)
		T.eq(i, want[f], blackmaw.floors[f].name)
	end
	local alcaz = { floors = { { name = "Alcaz Prison" }, { name = "Maximum Security" } } }
	local two = { { nil, "AlcazPrisonMap" }, { nil, "AlcazPrisonMap2" } }
	T.eq(select(2, P.PickFloor(alcaz, 1, two, d)), 1, "a tie: by position")
	T.eq(select(2, P.PickFloor(alcaz, 2, two, d)), 2, "no word matches: by position")
	T.eq(P.PickFloor(alcaz, 3, two, d), nil, "nothing at that position")
	-- OpenMap's drawings by name too.
	_G.OpenMap.MapDungeonDrawn[2999] = {
		{ name = "Somewhere Else", tiles = { "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12" } },
		{ name = "Ruins of Lordaeron", tiles = { "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t9", "t10", "t11", "t12" } },
	}
	_G.ForeverDungeonJournal_NS = nil
	fresh()
	art = P.FloorArt(ns.Bundled.Get("b:ruins-of-lordaeron"), 1)
	T.eq(art and art.textures[1], "t1", "OpenMap: the drawing of the same name")
	T.eq(#art.pins, 1, "with the pins of that drawing's index")
	T.eq(art.pins[1].name, "Bjork")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Forever Dungeon Routes adapter: shape checks, its maps after Dungeon Journal's, routes only on the art they fit", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	local r = row("foreverDungeonRoutes")
	T.ok(r and r.active and r.internals, "active, reads internals")
	T.eq(r.counts.dungeons, 2)
	T.eq(r.counts.routes, 3, "a route and a dungeon with two variants")
	T.eq(r.counts.maps, 1)
	T.eq(r.counts.rooms, 2)
	local a = P.Adapter("foreverDungeonRoutes")
	local plan = hot()
	-- Map priority: Dungeon Journal's picture first; without it this addon's (the same picture).
	T.eq(P.FloorArt(plan, 1).provider, "dungeonJournal")
	_G.ForeverDungeonJournal_NS = nil
	fresh()
	local art = P.FloorArt(plan, 1)
	T.ok(art and art.provider == "foreverDungeonRoutes", "its map where Dungeon Journal has none")
	T.eq(art.textures[1], "Interface\\AddOns\\ForeverDungeonRoutes\\maps\\hallofthanes")
	T.eq(art.width, 1024)
	T.eq(art.height, 683, "cropped like the addon crops it")
	T.eq(art.artist, "A Painter")
	T.eq(#art.pins, 1, "its boss stops as pins (not the rare)")
	-- Routes: on its own picture or Dungeon Journal's; not on another map, not on the grid.
	local routes = P.Routes(plan, 1, art)
	T.ok(routes and routes.provider == "foreverDungeonRoutes" and routes.credit == "Forever Dungeon Routes", "credited")
	T.eq(#routes.lines, 2, "the main path and the side path; the line off the map and the odd one are skipped")
	T.eq(routes.lines[1].points[2][2], 0.66)
	T.eq(routes.lines[2].side, true)
	T.eq(routes.lines[2].title, "A side way")
	T.eq(#routes.stops, 2)
	fresh()
	T.ok(P.Routes(plan, 1, { source = "provider", provider = "dungeonJournal" }), "Dungeon Journal's picture is the same")
	T.eq(P.Routes(plan, 1, { source = "provider", provider = "openMap" }), nil, "another drawing: nothing")
	T.eq(P.Routes(plan, 1, nil), nil, "the grid: nothing")
	-- A classic floor: matched by its first map tile's file ID, drawn on the game's map art only.
	local dm = ns.Bundled.Get("b:the-deadmines")
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	ns.GameFiles.Reset()
	fresh()
	T.eq(a.FloorOf(_G.ForeverDungeonRoutes, dm, 1), 291, "floor 1 by its tile's file ID")
	local tiles = { source = "tiles" }
	local dmr = P.Routes(dm, 1, tiles)
	T.ok(dmr and #dmr.lines == 1, "the full clear's line on floor 1 (of two variants)")
	T.eq(P.Routes(dm, 2, tiles), nil, "floor 2's tile unknown to this client: no match, nothing")
	-- The map draws it as an extra layer, off until ticked; the legend names it.
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	canvas.loadedKey = nil
	ns.db.ui.legendFolded = false -- the legend open (its rows)
	map:Refresh()
	ns.db.ui.legendFolded = nil
	canvas:DrawContent()
	local before = canvas.counts.lines
	local legendRow
	for _, rowFrame in ipairs(map.legend.rows) do
		if rowFrame.layer.id == "providerRoutes" then
			legendRow = rowFrame
		end
	end
	T.ok(legendRow and legendRow:IsShown(), "a legend row where it has a route")
	T.eq(legendRow.text:GetText(), "Addon route", "a short label in the compact legend")
	T.eq(legendRow.dpTooltipText, "Routes: Forever Dungeon Routes", "the addon's name in the tooltip")
	T.eq(legendRow.check:GetChecked(), false, "off at first")
	ns.db.ui.mapLayers.providerRoutes = true
	canvas:DrawContent()
	T.eq(canvas.counts.lines, before + 3, "its two lines drawn too (2 + 1 segments)")
	ns.db.ui.mapLayers.providerRoutes = nil
	-- Shape checks: wrong shapes switch it off; an error inside a call turns it off for the session.
	_G.ForeverDungeonRoutes.Rooms = "rooms"
	fresh()
	T.ok(not row("foreverDungeonRoutes").active, "Rooms of the wrong type: inactive")
	_G.ForeverDungeonRoutes.Rooms = nil
	_G.ForeverDungeonRoutes.DefaultRoutes = nil
	fresh()
	T.ok(not row("foreverDungeonRoutes").active, "no routes table: inactive")
	_G.ForeverDungeonRoutes.DefaultRoutes = {}
	_G.ForeverDungeonRoutes.Floors[1030651] = setmetatable({}, { __index = function()
		error("boom")
	end })
	fresh()
	T.eq(P.Routes(plan, 1, art), nil)
	T.ok(row("foreverDungeonRoutes").failed, "a failing read switches it off and says why")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
	ns.GameFiles.Reset()
end)

T.case("NeedRoll adapter: public links only; Questie adapter: dungeon quests through LibQuestieDB", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	T.ok(row("needRoll").active and not row("needRoll").internals)
	local links = P.LootLinks()
	T.eq(#links, 1)
	local plan = hot()
	P.Call("needRoll", "OpenLoot", plan, plan.encounters[1])
	T.eq(mock.needRollCalls[1][1], "Hall of Thanes")
	T.eq(mock.needRollCalls[1][2], plan.encounters[1].name)
	-- Questie: quests filed under the dungeon's area, by level, with who starts them.
	local done = false
	local list, finished = P.Call("questie", "Quests", plan, function()
		done = true
	end)
	for _ = 1, 5 do
		if finished or done then
			break
		end
		mock.Advance(0.1)
		list, finished = P.Call("questie", "Quests", plan)
	end
	T.ok(finished or done, "the scan finishes")
	T.eq(#list, 2)
	T.eq(list[1].name, "Treaty", "lowest level first")
	T.eq(list[2].starter, "Thane Keeper")
	T.eq(#ns.Providers.Adapter("questie").EnumNames("The Hall of Thanes"), 2)
	-- A newer contract than the adapter knows: inactive.
	_G.LibQuestieDB.RequireContract = function()
		return false, "too new"
	end
	fresh()
	T.ok(not row("questie").active)
	-- Switched off in the settings.
	P.SetEnabled("needRoll", false)
	T.ok(not row("needRoll").active and not row("needRoll").enabled)
	P.SetEnabled("needRoll", true)
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Providers.Align: same, fitted or replaced by the provider's pins", function()
	local same = P.Align({ { 0.5, 0.5, 0.51, 0.49 }, { 0.2, 0.3, 0.2, 0.31 } })
	T.eq(same.mode, "same")
	local list = {}
	for _, p in ipairs({ { 0.1, 0.1 }, { 0.9, 0.2 }, { 0.5, 0.8 }, { 0.3, 0.6 } }) do
		list[#list + 1] = { p[1], p[2], p[1] * 0.8 + 0.1, p[2] * 0.7 + 0.05 }
	end
	local fit = P.Align(list)
	T.eq(fit.mode, "fit")
	T.ok(math.abs(fit.sx - 0.8) < 1e-6 and math.abs(fit.ty - 0.05) < 1e-6)
	local bad = P.Align({ { 0.1, 0.1, 0.9, 0.9 }, { 0.9, 0.9, 0.1, 0.5 }, { 0.5, 0.1, 0.2, 0.8 } })
	T.eq(bad.mode, "pins")
	T.eq(P.Align({}).mode, "none")
end)

T.case("Map: a provider's map is drawn with its credit; Fit frames the markers; the legend is compact", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	map:Refresh()
	local canvas = map.canvas
	T.ok(canvas.provided, "the canvas uses a drawn map")
	T.eq(canvas.artInfo.source, "reyes", "Santiago Reyes' bundled map comes first")
	T.ok(canvas.credit:IsShown() and canvas.credit:GetText():find("Santiago Reyes", 1, true), "credited to the artist")
	-- Without the bundled map: the provider's, credited.
	local bundled = ns.ReyesMaps.DUNGEONS.hallofthanes
	ns.ReyesMaps.DUNGEONS.hallofthanes = nil
	ns.ReyesMaps.Reset()
	canvas.loadedKey = nil
	map:Refresh()
	T.eq(canvas.artInfo.source, "provider", "then the provider's map")
	T.ok(canvas.credit:IsShown() and canvas.credit:GetText():find("Dungeon Journal", 1, true), "credited")
	ns.ReyesMaps.DUNGEONS.hallofthanes = bundled
	ns.ReyesMaps.Reset()
	-- Legend: compact (not the full height), and reserved when fitting.
	if map.rail:IsShown() then
		T.ok(map.rail:GetWidth() < 248, "the legend alone is narrower than the editor")
		T.ok((canvas.reserveRight or 0) > 0, "fitting keeps clear of the legend")
	end
	-- Without a provider: the parchment grid, and Fit frames the plan's markers instead of the empty grid.
	mock.RemoveProviders()
	preferProviders(false)
	ns.db.settings.preferProviderMaps = false
	fresh()
	canvas.loadedKey = nil
	map:Refresh()
	T.eq(canvas.provided, nil)
	T.eq(canvas.artInfo and canvas.artInfo.source, "minimap", "drawn maps not preferred: the game's minimap pictures")
	-- Neither (no minimap pictures, no bundled map): the grid.
	local data = ns.MinimapArtData
	ns.MinimapArtData = {}
	ns.ReyesMaps.DUNGEONS.hallofthanes = nil
	ns.MinimapArt.Reset()
	ns.ReyesMaps.Reset()
	canvas.loadedKey = nil
	map:Refresh()
	T.eq(canvas.artInfo, nil, "no art: the grid")
	canvas:ResetView()
	local w, h = canvas:BaseSize()
	local framed = ns.MapLayout.FitView(canvas:ContentPoints(), { viewW = canvas:GetWidth(), viewH = canvas:GetHeight(),
		baseW = w, baseH = h, fitScale = canvas:FitScale(), inset = ns.MapCanvas.FRAME_INSET, reserveRight = canvas.reserveRight or 0 })
	T.ok(framed and math.abs(canvas.zoom - framed.zoom) < 1e-6, "Fit frames the markers")
	ns.MinimapArtData = data
	ns.ReyesMaps.DUNGEONS.hallofthanes = bundled
	ns.db.settings.preferProviderMaps = nil
	ns.MinimapArt.Reset()
	ns.ReyesMaps.Reset()
	canvas.loadedKey = nil
	-- A later session: the legend stays off until the button turns it on.
	ns.db.ui.showLegend = nil
	local later = ns.Panels.map.Create(_G.UIParent, ns.UI.ctx)
	T.eq(later.LegendShown(), false, "off after the first view")
	later.legendButton:GetScript("OnClick")(later.legendButton, "LeftButton")
	T.eq(ns.db.ui.showLegend, true, "the button's choice sticks")
	ns.db.ui.showLegend = nil
end)

T.case("Map legend: its title folds it, the choice sticks; untouched, it folds where it would move the map", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.db.ui.showLegend = true
	ns.UI.SelectPlan("b:molten-core")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	local whole = canvas.FitIsWhole
	-- Untouched: open where the whole map stays centred, folded where the open legend would move or shrink it.
	ns.db.ui.legendFolded = nil
	canvas.FitIsWhole = function()
		return true
	end
	map:RefreshNow()
	T.eq(map.legend:IsFolded(), false, "open: the map keeps its place")
	T.ok(map.legend.rows[1]:IsShown(), "with its rows")
	canvas.FitIsWhole = function()
		return ns.MapLegend.Folded()
	end
	map:RefreshNow()
	T.eq(map.legend:IsFolded(), true, "folded: the map keeps its centre")
	T.ok(not map.legend.rows[1]:IsShown(), "the title alone")
	T.ok(map.rail:GetWidth() < 150 and map.rail:GetHeight() < 60, "a small box")
	-- The title opens it, and that choice sticks on every map.
	map.legend.heading:GetScript("OnClick")(map.legend.heading, "LeftButton")
	T.eq(ns.db.ui.legendFolded, false, "opened by the player")
	map:RefreshNow()
	T.eq(map.legend:IsFolded(), false, "stays open")
	map.legend.heading:GetScript("OnClick")(map.legend.heading, "LeftButton")
	T.eq(ns.db.ui.legendFolded, true, "folded by the player")
	canvas.FitIsWhole = whole
	ns.db.ui.legendFolded, ns.db.ui.showLegend = nil, nil
end)

T.case("Map legend: untouched, it folds wherever it lies over the map's picture (Molten Core's painted title)", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	-- The game's old dungeon maps (the client has their first tiles), as in game.
	local files = mock.files
	mock.files = {}
	mock.files[("Interface\\WorldMap\\MoltenCore\\MoltenCore1_1"):lower()] = 451000
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	ns.GameFiles.Reset()
	ns.db.ui.showLegend, ns.db.ui.legendFolded = true, nil
	ns.UI.SelectPlan("b:molten-core")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	-- The map view as large as in game on a 1440p screen (1170 x 718): Molten Core's whole map (1002 x 668) fits
	-- centred at its full size, and the open legend lies over its top-right corner (the painted "THE MOLTEN CORE"),
	-- clear of every boss.
	local getW, getH = canvas.GetWidth, canvas.GetHeight
	canvas.GetWidth = function()
		return 1170
	end
	canvas.GetHeight = function()
		return 718
	end
	canvas.loadedKey = nil
	map:RefreshNow()
	T.eq(canvas.artInfo and canvas.artInfo.source, "tiles", "Molten Core's map tiles")
	ns.db.ui.legendFolded = false -- the open legend, as the player would see it
	map:RefreshNow()
	T.ok(canvas:FitIsWhole(), "the open legend neither moves nor shrinks the map (the old rule kept it open)")
	local w, h = canvas:BaseSize()
	local rail = { 1170 - 15 - map.rail:GetWidth(), 15, 1170 - 15, 15 + map.rail:GetHeight() }
	T.ok(ns.MapLayout.PanelOverMap(rail, canvas:FitBox(), w, h), "but it lies over the map's picture")
	ns.db.ui.legendFolded = nil
	map:RefreshNow()
	T.eq(map.legend:IsFolded(), true, "so it starts folded: the painted title shows")
	T.ok(map.rail:IsShown() and map.rail:GetWidth() < 150, "the title alone")
	T.ok(canvas:FitIsWhole(), "the whole map, centred, at its full size")
	-- The other maps of the in-game walk start folded too.
	for _, id in ipairs({ "b:hall-of-thanes", "b:the-deadmines" }) do
		ns.UI.SelectPlan(id)
		ns.UI.SelectTab("map")
		map:RefreshNow()
		T.eq(map.legend:IsFolded(), true, id .. ": folded")
	end
	-- The player's choice wins: opened, it stays open over the map.
	ns.db.ui.legendFolded = false
	map:RefreshNow()
	T.eq(map.legend:IsFolded(), false, "opened by the player")
	-- In an empty band beside a narrow map (or only touching its edge), a panel is not over it.
	local fit = { scale = 1, ox = 100, oy = 0 }
	T.eq(ns.MapLayout.PanelOverMap({ 520, 15, 700, 300 }, fit, 400, 600), false, "beside the map")
	T.eq(ns.MapLayout.PanelOverMap({ 500, 15, 700, 300 }, fit, 400, 600), false, "touching its edge")
	T.eq(ns.MapLayout.PanelOverMap({ 480, 15, 700, 300 }, fit, 400, 600), true, "over its corner")
	canvas.GetWidth, canvas.GetHeight = getW, getH
	canvas.loadedKey = nil
	mock.files = files
	ns.GameFiles.Reset()
	ns.db.ui.legendFolded, ns.db.ui.showLegend = nil, nil
end)

T.case("MapLayout.MapFit: the whole map as large as the view allows, always centred, the legend and controls clear of the plan", function()
	local M = ns.MapLayout
	-- The legend (top right, 219 wide with its margin, 300 tall) and the controls (bottom left) of a 1000 x 700 view.
	local legend = { 1000 - 219, 15, 1000 - 15, 315 }
	local controls = { 15, 700 - 15 - 80, 15 + 120, 700 - 15 }
	local function o(points, extra)
		local t = { viewW = 1000, viewH = 700, baseW = 1002, baseH = 668, inset = 7, reserveRight = 219,
			avoid = { legend, controls }, points = points }
		for k, v in pairs(extra or {}) do
			t[k] = v
		end
		return t
	end
	local function clear(fit, points)
		for _, p in ipairs(points) do
			local x, y = fit.ox + p[1] * 1002 * fit.scale, fit.oy + p[2] * 668 * fit.scale
			for _, r in ipairs({ legend, controls }) do
				if x > r[1] - 30 + 1e-6 and x < r[3] + 30 - 1e-6 and y > r[2] - 30 + 1e-6 and y < r[4] + 30 - 1e-6 then
					return false
				end
			end
		end
		return true
	end
	-- No legend, no points: as wide as the view (the map is wider than the view's shape), centred.
	local fit = M.MapFit({ viewW = 1000, viewH = 700, baseW = 1002, baseH = 668, inset = 7 })
	T.ok(math.abs(fit.scale - (986 / 1002)) < 1e-6, "fills the width")
	T.ok(math.abs(fit.ox - 7) < 1e-6 and math.abs(fit.oy - (7 + (686 - 668 * fit.scale) / 2)) < 1e-6, "centred")
	-- The plan away from the panels: the same size and place; the legend floats over the map's edge.
	local away = { { 0.5, 0.5 }, { 0.3, 0.2 }, { 0.6, 0.9 } }
	local over = M.MapFit(o(away))
	T.eq(over.scale, fit.scale, "no band above and below for the legend")
	T.eq(over.ox, fit.ox)
	-- A point under the legend, one level with the controls: smaller about the centre, until both are clear.
	local near = { { 0.77, 0.1 }, { 0.15, 0.97 }, { 0.5, 0.5 } }
	local shrunk = M.MapFit(o(near))
	T.ok(shrunk.scale < fit.scale and shrunk.scale > fit.scale * 0.85, "smaller only as needed")
	T.ok(clear(shrunk, near), "no point under a panel")
	T.ok(math.abs((shrunk.ox - 7) - (986 - 1002 * shrunk.scale - (shrunk.ox - 7))) < 1e-6, "still centred: equal bands")
	-- A point below the legend (not level with it) does not count.
	local below = M.MapFit(o({ { 0.97, 0.8 } }))
	T.eq(below.scale, fit.scale, "below the legend: the full size")
	-- A point at the very edge: shrinking about the centre does not clear it, moving within the map's band does.
	local edge = M.MapFit(o({ { 0.9, 0.3 } }, { baseW = 800 }))
	T.ok(edge.ox + 0.9 * 800 * edge.scale < 1000 - 219 - 30, "clear of the legend")
	T.ok(math.abs(edge.scale - 686 / 668) < 1e-6, "at the full size")
	T.ok(edge.ox < 7 + (986 - 800 * edge.scale) / 2, "moved left")
	T.ok(edge.ox >= 7 - 1e-6, "never past the frame's inset")
	-- Nothing clears it: the size beside the legend, centred in the room it leaves.
	local least = M.MapFit(o({ { 1, 0 }, { 0, 1 } }, { viewW = 600, avoid = { { 600 - 219, 15, 585, 315 }, controls } }))
	local room = 600 - 14 - 219
	T.ok(math.abs(least.scale - math.min(room / 1002, 686 / 668)) < 1e-6, "the size beside the legend")
	T.ok(math.abs(least.ox - (7 + (room - 1002 * least.scale) / 2)) < 1e-6, "centred beside the legend")
	-- No panel beside: the full size, centred, whatever the points.
	local none = M.MapFit({ viewW = 1000, viewH = 700, baseW = 1002, baseH = 668, inset = 7, points = { { 1, 0 } },
		avoid = { legend } })
	T.ok(math.abs(none.ox - fit.ox) < 1e-6 and none.scale == fit.scale, "no reserve: centred at the full size")
	T.eq(M.MapFit({ viewW = 0, viewH = 1, baseW = 1, baseH = 1 }), nil)
end)

T.case("MapLayout.FitView frames points inside the free part of the view", function()
	local fit = ns.MapLayout.FitView({ { 0.4, 0.4 }, { 0.5, 0.5 } },
		{ viewW = 800, viewH = 600, baseW = 1000, baseH = 667, fitScale = 0.8, inset = 8, reserveRight = 200 })
	T.ok(fit and fit.zoom > 1)
	local s = 0.8 * fit.zoom
	local cx = 0.45 * 1000 * s + fit.ox
	T.ok(math.abs(cx - (8 + (800 - 16 - 200) / 2)) < 1, "centred in the free part")
	T.eq(ns.MapLayout.FitView({}, { viewW = 1, viewH = 1 }), nil)
end)

T.case("Party strip: role glyphs on a bronze-ringed plate, and empty seats say so", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	local side = _G.DungeonPlannerMainFrame.instancePage.side
	side:RefreshParty(ns.DB.GetPlan("b:hall-of-thanes"))
	-- Solo, the player takes the first damage seat (the mock's class lists no specializations); the next one is open.
	local slot = side.party.slots[4]
	T.ok(slot.role:IsShown() and slot.ring:IsShown() and slot.icon:IsShown(), "glyph on its plate")
	T.eq(ns.Art.SPECS.party_DAMAGER.atlas, "groupfinder-icon-role-micro-dps", "the sword glyph, not the red disc")
	T.eq(ns.Art.SPECS.partyDisc_DAMAGER.atlas, "UI-LFG-RoleIcon-DPS", "the disc only as a fallback")
	T.eq(slot.name:GetText(), ns.L["party:open"], "an empty seat reads Open, not a dash")
	local r, g, b = slot.ring:GetVertexColor()
	local br, bg, bb = ns.Style.Color("border")
	T.ok(r == br and g == bg and b == bb, "bronze ring for every role")
	T.ok(side.party:GetHeight() >= 70, "a taller strip")
end)

T.case("Run mode on Hall of Thanes: next pull from step 1, a compact mini map, the counter between the buttons", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	local plan = hot()
	ns.UI.SelectPlan(plan.id)
	ns.RunMode.Show()
	ns.UI.FocusStep(1, { stay = true })
	ns.RunMode.Refresh()
	local f = _G.DungeonPlannerRunFrame
	T.ok(f.pull.title:GetText():find("Pull 1", 1, true), "next pull at step 1: " .. tostring(f.pull.title:GetText()))
	-- "(approx.)" becomes a small mark.
	local text = f.step.text:GetText()
	T.ok(not text:find("approx", 1, true), "no (approx.) in run mode: " .. text)
	T.ok(text:find(ns.Style.APPROX, 1, true), "the approx mark instead")
	-- The counter sits between Prev and Next, not under Next.
	local left, right = f.counter:FindPoint("LEFT"), f.counter:FindPoint("RIGHT")
	T.ok(left and left[2] == f.prev and left[3] == "RIGHT", "counter starts after Prev")
	T.ok(right and right[2] == f.next and right[3] == "LEFT", "counter ends before Next")
	T.eq(f.prev:GetWidth(), f.next:GetWidth(), "buttons of one width")
	-- The last step (Durgen): his party positions only, no labels, no numbered stops, the credit under the map.
	local steps = ns.UI.ctx:Steps()
	ns.UI.FocusStep(#steps, { stay = true })
	ns.RunMode.Refresh()
	local map = f.map
	T.ok(map.provided, "a drawn map")
	T.ok(not map.credit:IsShown() and not map.creditPlate:IsShown(), "no caption over the art")
	T.ok(f.mapCredit:GetText():find("Santiago Reyes", 1, true), "the credit under the map")
	map:DrawContent()
	local positions = 0
	for i = 1, map.counts.pins do
		local b = map.pools.pins[i]
		local m = ns.Util.FindById(plan.markers, b.markerId)
		if m.kind == "position" then
			T.eq(m.encounter, "e4", "only the current step's positions")
			positions = positions + 1
		end
		T.eq(b.label:GetText(), "", "no labels on the mini map")
	end
	for i = 1, map.counts.journal do
		T.eq(map.pools.journal[i].label:GetText(), "", "no labels on boss pins either")
	end
	T.eq(positions, 4, "Durgen's four positions")
	T.eq(map.counts.points, 0, "no numbered stops (their numbers are not the step numbers)")
	T.ok(map.focusRing:IsShown(), "a ring on the step")
	T.ok(map.zoom > 1.2, "framed closer than the whole map")
	ns.RunMode.Hide()
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Map labels sit on a plate; the provider credit is a chip", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	map:Refresh()
	local canvas = map.canvas
	canvas:DrawContent()
	T.ok(canvas.credit:IsShown() and canvas.creditPlate:IsShown(), "credit on its plate")
	local labelled = 0
	for _, pool in ipairs({ canvas.pools.pins, canvas.pools.journal }) do
		for _, b in ipairs(pool) do
			if b:IsShown() then
				local has = (b.label:GetText() or "") ~= "" and b.label:IsShown()
				T.eq(b.plate:IsShown() and true or false, has, "a plate exactly under a shown label")
				if has then
					labelled = labelled + 1
				end
			end
		end
	end
	T.ok(labelled > 0, "some labels drawn")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Gear: the filters and the NeedRoll button never share a line with the hint", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("gear")
	local gear = _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
	gear:Refresh()
	local top = gear.status:FindPoint("TOPLEFT")
	T.ok(top and top[2] == gear.class and top[3] == "BOTTOMLEFT", "the hint line is under the filters")
	-- On the hint's line (the filters are SZ.control tall), anchored to the panel, never to the hint: the hint's right
	-- edge is anchored to the button, and the client refuses an anchor cycle.
	local nr = gear.needRoll:FindPoint("TOPRIGHT")
	T.ok(nr and nr[2] == gear and nr[5] == -(ns.Style.SIZE.control + ns.Style.SPACE.sm), "Open in NeedRoll on the hint's line")
	T.eq(top[5], -ns.Style.SPACE.sm, "the hint one small gap under the filters")
	T.ok(gear.needRoll:IsShown(), "NeedRoll is installed")
	-- Regression (in game): the button read greyed out and cut ("Open in NeedRo").
	T.ok(gear.needRoll:IsEnabled(), "enabled while NeedRoll is loaded")
	T.ok(gear.needRoll:GetWidth() >= gear.needRoll.label:GetStringWidth() + 2 * ns.Style.SPACE.md, "the label fits")
	local right = gear.status:FindPoint("RIGHT")
	T.ok(right and right[2] == gear.needRoll and right[3] == "LEFT", "the hint stops before the button")
	T.ok(not gear.status:GetText():find("Dungeon Journal", 1, true), "the source is in the section header, not here")
	-- A narrow panel: the filters shrink alike instead of running under each other.
	gear:SetWidth(420)
	gear:GetScript("OnSizeChanged")(gear, 420, 300)
	local sum = gear.class:GetWidth() + gear.role:GetWidth() + gear.encounter:GetWidth() + gear.slot:GetWidth()
	T.ok(sum + 3 * ns.Style.SPACE.sm <= 420, "filters fit: " .. sum)
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

-- Regression (in game, Hall of Thanes): the hint line's anchor and the NeedRoll button's anchor formed a cycle, the
-- client refused it inside Refresh, and the Gear page stayed on "No gear for this filter." with no hint.
local function gearPage()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("gear")
	return _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
end

T.case("Gear: with the Dungeon Journal installed and default filters, the drops are listed per boss", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	local gear = gearPage()
	gear:Refresh() -- the client raises on an anchor cycle (tests/wowmock.lua does too), which emptied this page
	local headers, items = {}, 0
	for _, it in ipairs(gear.entries) do
		if it.header then
			headers[#headers + 1] = it.header
		elseif it.loot then
			items = items + 1
		end
	end
	T.eq(headers[1], "Drops (Dungeon Journal)")
	T.ok(table.concat(headers, "|"):find("Faldrim Anvilmar", 1, true), "a boss header")
	T.eq(items, 3, "Faldrim's two drops and Magmatus's one, no trash")
	T.ok(gear.status:GetText() ~= "" and gear.status:GetText() ~= nil, "the hint is set")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Gear: a Dungeon Journal adapter that switched itself off says why", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	fresh()
	-- Malformed data in the other addon: a boss row whose loot read throws.
	local bosses = _G.ForeverDungeonJournal_NS.DB["Hall of Thanes"].bosses
	bosses[1] = setmetatable({}, { __index = function()
		error("Interface/AddOns/DungeonPlanner/Data/Providers/DungeonJournal.lua:104: broken table", 0)
	end })
	local gear = gearPage()
	gear:Refresh()
	local failures = P.Failures("loot")
	T.eq(#failures, 1, "the adapter is off for the session")
	T.eq(failures[1].reason, "DungeonJournal.lua:104: broken table", "the reason without folders")
	T.eq(gear.status:GetText(), "Dungeon Journal data unavailable: DungeonJournal.lua:104: broken table")
	T.eq(#P.Failures("quests"), 0, "only adapters that provide the capability")
	local r = row("dungeonJournal")
	T.ok(r.failed and not r.active, "/dp debug lists it as failed")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Dungeon Journal adapter: its own card pictures only, with shape checks", function()
	boot()
	mock.InstallProviders()
	preferProviders(true)
	local fdj = _G.ForeverDungeonJournal_NS
	local own = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\KroldokHome"
	fdj.DUNGEON_HOME_ART = {
		["Krol'dok Stronghold"] = own,
		["Alcaz Prison"] = "Interface\\AddOns\\SomeOtherAddon\\Media\\AlcazPrisonHome", -- not its folder
		["Shaper's Terrace"] = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\..\\..\\Elsewhere\\X", -- not a plain name
		["The Drowned City"] = 7963741, -- a file ID: the game's file, ours already
		["Blackmaw Hold"] = { "not a path" },
	}
	fdj.DUNGEON_HOME_TEXCOORD = { ["Krol'dok Stronghold"] = { 0.5, 0.1, 0, 1 } } -- reversed: ignored
	fresh()
	T.ok(row("dungeonJournal").active)
	local art = P.InstanceArt("Krol'dok Stronghold")
	T.eq(art and art.file, own)
	T.eq(art.area[1], 0, "bad coordinates: the whole picture")
	T.eq(art.area[5], 2)
	T.eq(art.credit, "Dungeon Journal")
	T.eq(P.InstanceArt("Alcaz Prison"), nil, "another addon's folder")
	T.eq(P.InstanceArt("Shaper's Terrace"), nil, "a path out of its folder")
	T.eq(P.InstanceArt("The Drowned City"), nil, "a game file ID")
	T.eq(P.InstanceArt("Blackmaw Hold"), nil, "not a string")
	T.eq(P.InstanceArt("Nowhere"), nil)
	-- No picture table at all: nothing, the adapter stays on.
	fdj.DUNGEON_HOME_ART = "nope"
	fresh()
	T.eq(P.InstanceArt("Krol'dok Stronghold"), nil)
	T.ok(row("dungeonJournal").active, "a wrong picture table does not switch the adapter off")
	mock.RemoveProviders()
	preferProviders(false)
	fresh()
end)

T.case("Party positions: shown for the boss or pull in focus; at \"everything\" the legend says so and focuses one", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.db.ui.showLegend, ns.db.ui.legendFolded = true, false
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local ctx = ns.UI.ctx
	ctx.focusEncounter, ctx.focusPull = nil, nil
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	map:RefreshNow()
	local plan = ctx:Plan()
	local function shownPositions()
		local n = 0
		for _, b in ipairs(canvas.pools.pins) do
			local m = b:IsShown() and b.markerId and ns.Util.FindById(plan.markers, b.markerId)
			if m and m.kind == "position" then
				n = n + 1
			end
		end
		return n
	end
	-- Every recommended position belongs to a boss: none on the map at "Focus: everything" (by design: one boss's
	-- tank, healer and damage spots around every boss would crowd the whole map).
	local n, target = ns.MapLegend.FocusTarget(plan, 1)
	T.eq(n, 12, "Hall of Thanes: twelve positions, each a boss's")
	T.eq(shownPositions(), 0, "none shown with nothing in focus")
	local hint = map.legend.positionsHint
	T.ok(hint:IsShown(), "the positions row says why")
	T.eq(hint.text:GetText(), ns.L["Focus a boss to show them"])
	T.eq(target.kind, "encounter")
	T.eq(target.id, plan.encounters[1].id, "the first boss with positions")
	-- A click on the hint focuses that boss, as the Focus menu would: its positions show, the hint goes.
	hint:GetScript("OnClick")(hint, "LeftButton")
	map:RefreshNow()
	T.eq(ctx.focusEncounter, target.id, "the boss in focus")
	T.ok(shownPositions() > 0, "its positions on the map")
	T.ok(not hint:IsShown(), "no hint while something is in focus")
	-- The layer switched off: no hint either.
	ctx.focusEncounter = nil
	ns.db.ui.mapLayers.positions = false
	map:RefreshNow()
	T.ok(not hint:IsShown(), "no hint for a hidden layer")
	ns.db.ui.mapLayers.positions = nil
	ns.db.ui.legendFolded, ns.db.ui.showLegend = nil, nil
end)
