-- The views tests/ui_dump.lua dumps (wow-ui-harness, wowui.runner): the window's home (every tab), the instance
-- picker and other dropdown lists, every section of a Forever dungeon on a provider's map (Share with Advanced open),
-- a raid's party, a classic dungeon and a raid on the game's old map tiles, an own plan with the drawing tools and
-- drawings (also at the window's minimum size, 880 x 560, and a large one), run mode at its first, a middle and its
-- last step, the /dp debug dialog and a confirmation. The client is set up the way WoW: Forever is: an empty Adventure Guide, the
-- recommended plans, and (made-up data in their real shapes) the provider addons.
--
-- Not here: the Settings panel (the game's own Settings frame with AceConfig's widgets, which the mock cannot build).
-- `/dp shots` takes it in game.

local V = {}

local mock -- set by prepare
local ns = {}

local function page()
	return _G.DungeonPlannerMainFrame.instancePage
end

local function window()
	return _G.DungeonPlannerMainFrame
end

local function closeAll()
	if ns.Widgets and ns.Widgets.ClosePopup then
		ns.Widgets.ClosePopup()
	end
	local d = rawget(_G, "DungeonPlannerDialog")
	if d then
		d:Hide()
	end
	if ns.RunMode and ns.RunMode.IsShown() then
		ns.RunMode.Hide()
	end
end

-- The views show the new dungeons on a provider's map (installed below), as players with one of those addons and the
-- setting see them; map-minimap shows the default, the game's own minimap pictures (Data/MinimapArt.lua).
local function openPlan(id, section, minimap)
	closeAll()
	ns.db.settings.preferProviderMaps = not minimap
	ns.MinimapArt.Reset()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. id)
	ns.UI.SelectTab(section or "map")
	ns.UI.RefreshPage()
end

local function sectionView(section)
	return {
		name = "section-" .. section,
		setup = function()
			openPlan("hall-of-thanes", section)
		end,
		window = window,
	}
end

-- The steps list with a step selected (its row highlight over the two text lines).
local function stepsView()
	return {
		name = "steps-selected",
		setup = function()
			openPlan("hall-of-thanes", "map")
			ns.UI.FocusStep(7)
		end,
		window = window,
	}
end

-- A control's click, as the game runs it.
local function click(b)
	b:GetScript("OnClick")(b, "LeftButton")
end

-- The window at a size (the minimum, 880 x 560, or a large one); views after it get the default back.
local DEFAULT_W, DEFAULT_H
local function resize(w, h)
	local f = window()
	DEFAULT_W, DEFAULT_H = DEFAULT_W or f:GetWidth(), DEFAULT_H or f:GetHeight()
	f:SetSize(w or DEFAULT_W, h or DEFAULT_H)
end

-- An editable copy of Hall of Thanes with drawings of every kind, tied to no step, a pull and a boss.
local own
local function ownPlan()
	if not own then
		closeAll()
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
		own = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		local D = ns.Drawing
		D.Add(own, 1, "arrow", { 0.40, 0.80, 0.47, 0.62 }, { color = 3, width = 3 })
		D.Add(own, 1, "circle", { 0.60, 0.42, 0.78, 0.58 }, { color = 1, width = 2, pull = own.pulls[1].id })
		D.Add(own, 1, "rect", { 0.20, 0.30, 0.34, 0.44 }, { color = 6, width = 1 })
		D.Add(own, 1, "line", { 0.36, 0.20, 0.56, 0.20 }, { color = 2, width = 2 })
		D.Add(own, 1, "pen", { 0.22, 0.70, 0.25, 0.66, 0.29, 0.65, 0.33, 0.68, 0.36, 0.64 }, { color = 5, width = 2 })
		D.Add(own, 1, "text", { 0.24, 0.52 }, { color = 7, width = 2, text = "Wait here" })
	end
	return own
end

local function openOwn(section, tool)
	closeAll()
	ns.UI.SelectPlan(ownPlan().id)
	ns.UI.ctx.tool = tool or "select"
	ns.UI.SelectTab(section or "map")
	ns.UI.RefreshPage()
end

-- Run mode at step `which` ("first", "middle", "last") of Hall of Thanes.
local function runMode(which)
	return {
		name = "runmode-" .. which,
		setup = function()
			openPlan("hall-of-thanes", "map")
			local n = #ns.UI.ctx:Steps()
			local index = which == "first" and 1 or which == "last" and n or math.floor((n + 1) / 2)
			ns.UI.FocusStep(index, { stay = true })
			ns.RunMode.Show()
			ns.RunMode.Refresh()
			window():Hide() -- run mode is used with the planner closed
		end,
		window = function()
			return rawget(_G, "DungeonPlannerRunFrame")
		end,
		teardown = function()
			closeAll()
			window():Show()
		end,
	}
end

-- Two recorded runs of Hall of Thanes (made up, in the recorder's real shape): the newer one took an extra pull before
-- Magmatus and skipped the last planned pull; the older one wiped once on Plunder.
local function recordRuns()
	local R, RunLog = ns.Recorder, ns.RunLog
	R.ClearHistory()
	local plan = ns.UI.ctx:Plan()
	local key = R.KeyForPlan(plan) or "3065"
	local store = R.Store()
	local function run(t0, script)
		local r = RunLog.Enter(store, key, "Hall of Thanes", 1, t0)
		local now = t0
		for _, item in ipairs(script) do
			now = now + 40
			RunLog.PullStart(r, now, "Anvilmar's Rest")
			if item == "t" then
				RunLog.Observe(r, { { level = 15, class = "elite" }, { level = 14, class = "normal" }, { level = 14, class = "normal" } })
			else
				RunLog.Observe(r, { { level = -1, class = "worldboss" } })
			end
			if item == "w" then
				RunLog.PullEnd(r, now + 50, 5, true)
			else
				if item ~= "t" then
					RunLog.BossKill(r, 9000 + #r.b, item, now + 45)
				end
				RunLog.PullEnd(r, now + (item == "t" and 35 or 50), 0, false)
			end
			now = now + 50
		end
		RunLog.Finish(store, now + 10)
	end
	run(1763300000, { "Faldrim Anvilmar", "t", "Magmatus", "w", "Plunder", "t", "Durgen Dirgehammer" })
	run(1763390000, { "Faldrim Anvilmar", "t", "t", "Magmatus", "Plunder", "Durgen Dirgehammer" })
end

local function runsView(name, show)
	return {
		name = name,
		setup = function()
			openPlan("hall-of-thanes", "map")
			recordRuns()
			ns.UI.SelectTab("runs")
			ns.UI.RefreshPage()
			local panel = page().panels.runs.inner
			local runs = ns.RunLog.Runs(ns.Recorder.Store(), ns.Recorder.KeyForPlan(ns.UI.ctx:Plan()) or "3065")
			if show == "compare" then
				panel.compareWith(runs[2])
			else
				panel.showView(show)
			end
		end,
		window = window,
		teardown = function()
			ns.Recorder.ClearHistory()
		end,
	}
end

-- An editable copy of Molten Core with raid groups and two raid pages, and a party whose classes the client knows
-- (made-up names), so the Notes window shows class colours, icons and the player's own line.
local raidOwn
local PARTY = { { "Aldra", "MAGE" }, { "Bram", "WARRIOR" }, { "Corin", "PRIEST" }, { "Dessa", "ROGUE" } }
local function raidPlan()
	if not raidOwn then
		closeAll()
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "molten-core")
		raidOwn = ns.UI.CopyPlan(ns.UI.ctx:Plan())
		raidOwn.groups[1] = { "Bram", "Dessa", "Tester", "Ivo", "Juna" }
		raidOwn.groups[2] = { "Corin", "Aldra", "Kell", "Lio", "Mara" }
		local P = ns.Pages
		local pg = P.Add(raidOwn, "Lucifron", "e1")
		P.Update(raidOwn, pg.id, { text = "{skull} Lucifron: {tank} Bram, adds on {star} and {circle}.\n"
			.. "{healer} {group 2} keeps the tanks up.\nDecurse: {mage} Aldra and Tester.\nInterrupts: {rogue} Dessa." })
		pg = P.Add(raidOwn, "Ragnaros: sons", "e10")
		P.Update(raidOwn, pg.id, { text = "Group 1 stays on the boss.\nSons of Flame: {group 2}, then everyone.\n"
			.. "Melee out on Wrath of Ragnaros." })
	end
	return raidOwn
end

local savedUnitClass
local function party(on)
	if on then
		savedUnitClass = savedUnitClass or _G.UnitClass
		mock.inGroup = true
		mock.units = {}
		for i, m in ipairs(PARTY) do
			mock.units["party" .. i] = { name = m[1], cls = m[2] }
		end
		_G.UnitClass = function(unit)
			local u = unit == "player" and { cls = "MAGE" } or mock.units[unit]
			return u and u.cls, u and u.cls, 1
		end
	else
		mock.inGroup = false
		mock.units = {}
		_G.UnitClass = savedUnitClass or _G.UnitClass
	end
end

local function pagesView(name, w, h)
	return {
		name = name,
		setup = function()
			if w then
				resize(w, h)
			end
			closeAll()
			ns.UI.SelectPlan(raidPlan().id)
			ns.db.ui.partyMode = "pages"
			ns.UI.SelectTab("assignments")
			ns.UI.RefreshPage()
		end,
		window = window,
		teardown = function()
			ns.db.ui.partyMode = "assignments"
			if w then
				resize()
			end
		end,
	}
end

-- Share with a group of four: two imported the plan (one has an older version), one runs the addon and has not, one
-- cannot answer.
local function shareTracking()
	return {
		name = "share-tracking",
		setup = function()
			party(true)
			ns.Comm.peers.Corin = { version = "dev", proto = 2, seen = 0 }
			local plan = ownPlan()
			local store = ns.Comm.AcksStore()
			ns.Acks.Record(store, plan.id, "Aldra", plan.updated, 1)
			ns.Acks.Record(store, plan.id, "Bram", plan.updated - 60, 1)
			openOwn("share", "select")
		end,
		window = window,
		teardown = function()
			ns.Comm.peers.Corin = nil
			ns.Comm.AcksStore().plans = {}
			party(false)
		end,
	}
end

local function notesWindow()
	return {
		name = "notes-window",
		setup = function()
			party(true)
			closeAll()
			ns.UI.SelectPlan(raidPlan().id)
			ns.NotesFrame.Open(ns.Pages.List(raidPlan())[1])
			window():Hide()
		end,
		window = function()
			return rawget(_G, "DungeonPlannerNotesFrame")
		end,
		teardown = function()
			ns.NotesFrame.Close()
			party(false)
			window():Show()
		end,
	}
end

-- Run mode while recording: Faldrim down, two trash pulls before Magmatus where the plan has one (the drift warning).
local function runModeDrift()
	return {
		name = "runmode-drift",
		setup = function()
			openPlan("hall-of-thanes", "map")
			local R, RunLog = ns.Recorder, ns.RunLog
			R.ClearHistory()
			ns.db.settings.recorder.enabled = true
			local run = RunLog.Enter(R.Store(), R.KeyForPlan(ns.UI.ctx:Plan()) or "3065", "Hall of Thanes", 1, 1763300000)
			local t = 1763300000
			for i, item in ipairs({ "Faldrim Anvilmar", "t", "t" }) do
				t = t + 60 * i
				RunLog.PullStart(run, t)
				RunLog.Observe(run, { { level = item == "t" and 15 or -1, class = item == "t" and "elite" or "worldboss" } })
				if item ~= "t" then
					RunLog.BossKill(run, 9000, item, t + 30)
				end
				RunLog.PullEnd(run, t + 40, 0, false)
			end
			ns.UI.FocusStep(4, { stay = true })
			ns.RunMode.Show()
			ns.RunMode.Refresh()
			window():Hide()
		end,
		window = function()
			return rawget(_G, "DungeonPlannerRunFrame")
		end,
		teardown = function()
			ns.Recorder.ClearHistory()
			ns.db.settings.recorder.enabled = false
			closeAll()
			window():Show()
		end,
	}
end

local function homeView(tab)
	return {
		name = tab == "dungeons" and "home" or "home-" .. tab,
		setup = function()
			closeAll()
			ns.UI.GoHome(tab)
		end,
		window = window,
	}
end

V.views = {
	homeView("dungeons"),
	homeView("raids"),
	{
		name = "picker",
		setup = function()
			openPlan("hall-of-thanes", "map")
			ns.InstancePicker.Open(page().instancePick, ns.UI.ctx:Instance())
		end,
		window = function()
			return rawget(_G, "DungeonPlannerPopup")
		end,
		teardown = closeAll,
	},
	{
		name = "plan-dropdown",
		setup = function()
			openPlan("hall-of-thanes", "map")
			click(page().planPick)
		end,
		window = function()
			return rawget(_G, "DungeonPlannerPopup")
		end,
		teardown = closeAll,
	},
	sectionView("map"),
	stepsView(),
	sectionView("encounters"),
	sectionView("pulls"),
	sectionView("assignments"),
	sectionView("gear"),
	sectionView("runs"),
	sectionView("share"),
	sectionView("plan"),
	runsView("runs-plan", "plan"),
	runsView("runs-compare", "compare"),
	{
		name = "section-share-advanced",
		setup = function()
			ns.db.ui.shareAdvanced = true
			openPlan("hall-of-thanes", "share")
		end,
		window = window,
		teardown = function()
			ns.db.ui.shareAdvanced = nil
		end,
	},
	{
		name = "party-raid",
		setup = function()
			openPlan("molten-core", "assignments")
		end,
		window = window,
	},
	{
		name = "gear-dropdown",
		setup = function()
			openPlan("hall-of-thanes", "gear")
			click(page().panels.gear.inner.slot)
		end,
		window = function()
			return rawget(_G, "DungeonPlannerPopup")
		end,
		teardown = closeAll,
	},
	{
		-- A boss marker selected on a provider's map: the details pane with the boss header, level and drops.
		name = "boss-detail",
		setup = function()
			openPlan("hall-of-thanes", "map")
			local plan = ns.UI.ctx:Plan()
			for _, m in ipairs(plan.markers) do
				if m.kind == "boss" and m.label == "Magmatus" then
					ns.UI.ctx.selectedMarker = m.id
				end
			end
			ns.UI.RefreshPage()
		end,
		window = window,
		teardown = function()
			ns.UI.ctx.selectedMarker = nil
		end,
	},
	{
		-- The bundled facts alone (no provider): a Deadmines boss with its level, abilities (spell icon, tags, note) and drops.
		name = "boss-detail-bundled",
		setup = function()
			openPlan("the-deadmines", "map")
			local plan = ns.UI.ctx:Plan()
			for _, m in ipairs(plan.markers) do
				if m.kind == "boss" and m.label == "Mr. Smite" then
					ns.UI.ctx.selectedMarker = m.id
				end
			end
			ns.UI.RefreshPage()
		end,
		window = window,
		teardown = function()
			ns.UI.ctx.selectedMarker = nil
		end,
	},
	{
		name = "map-classic",
		setup = function()
			openPlan("the-deadmines", "map")
		end,
		window = window,
	},
	{
		name = "map-minimap",
		setup = function()
			openPlan("hall-of-thanes", "map", true)
		end,
		window = window,
	},
	-- One map family: a classic dungeon on its old tiles (Ragefire Chasm: every kind of step in the side panel, a label
	-- at the map's edge), an outdoor minimap floor (Ruins of Lordaeron) and a building floor (Blackmaw Hold, floor 2).
	{
		name = "map-ragefire",
		setup = function()
			openPlan("ragefire-chasm", "map")
		end,
		window = window,
	},
	{
		name = "map-outdoor",
		setup = function()
			openPlan("ruins-of-lordaeron", "map", true)
		end,
		window = window,
	},
	{
		name = "map-building",
		setup = function()
			openPlan("blackmaw-hold", "map", true)
			ns.UI.ctx.floor = 2
			ns.UI.RefreshPage()
		end,
		window = window,
	},
	{
		name = "map-raid",
		setup = function()
			openPlan("molten-core", "map")
		end,
		window = window,
	},
	{
		name = "map-draw",
		setup = function()
			openOwn("map", "draw")
		end,
		window = window,
	},
	{
		name = "map-min",
		setup = function()
			resize(880, 560)
			openOwn("map", "draw")
		end,
		window = window,
		teardown = function()
			resize()
		end,
	},
	{
		name = "map-large",
		setup = function()
			resize(1500, 940)
			openOwn("map", "select")
		end,
		window = window,
		teardown = function()
			resize()
		end,
	},
	{
		name = "notes-min",
		setup = function()
			resize(880, 560)
			openPlan("hall-of-thanes", "plan")
		end,
		window = window,
		teardown = function()
			resize()
		end,
	},
	{
		name = "notes-own",
		setup = function()
			openOwn("plan", "select")
		end,
		window = window,
	},
	homeView("plans"),
	homeView("shared"),
	runMode("first"),
	runMode("middle"),
	runMode("last"),
	runModeDrift(),
	pagesView("party-pages"),
	pagesView("party-pages-min", 880, 560),
	notesWindow(),
	shareTracking(),
	{
		name = "debug",
		setup = function()
			closeAll()
			ns.Slash.Debug()
		end,
		window = function()
			return rawget(_G, "DungeonPlannerDialog")
		end,
		teardown = closeAll,
	},
	{
		name = "confirm",
		setup = function()
			openOwn("map", "draw")
			page().panels.map.drawBar:ClearAll()
		end,
		window = function()
			return rawget(_G, "DungeonPlannerDialog")
		end,
		teardown = closeAll,
	},
}

-- The client: the mock's API, set up like WoW: Forever.
function V.install(ctx)
	mock = ctx.mock
	local locale = "enUS"
	for i, a in ipairs(ctx.args.rest) do
		if a == "--locale" then
			locale = ctx.args.rest[i + 1] or locale
		end
	end
	mock.locale = locale
	mock.Install()
	-- WoW: Forever: the Adventure Guide has no instances (docs/COMPATIBILITY.md section 9).
	mock.journal.tiers = {}
	mock.gameRules = { [77] = true }
	mock.InstallProviders()
	-- Made-up item names for the made-up drops (the mock's own are "Item <id>").
	local names = { [900101] = "Test Choker", [900102] = "Test Boots", [900103] = "Test Blade", [900150] = "Test Summoning Stone",
		[14540] = "Taragaman the Hungerer's Heart" } -- Ragefire Chasm's quest item, by its plan's label
	_G.C_Item.GetItemNameByID = function(id)
		return names[id] or ("Item " .. id)
	end
	-- The provider's real picture path (the made-up data's path is not a usable one).
	local maps = _G.ForeverDungeonJournal_NS.DUNGEON_MAPS
	maps["Hall of Thanes"].floors[1].texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\HallOfThanesMap"
	-- Map names: the client's own (unknown here: the plans' names show, as for instances the client does not list).
	_G.C_Map.GetMapInfo = function(id)
		return { mapID = id }
	end
	-- Class colours and icons as the client has them (a few classes; their real shape).
	_G.RAID_CLASS_COLORS = {
		MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
		WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc69b6d" },
		PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" },
		ROGUE = { r = 1, g = 0.96, b = 0.41, colorStr = "fffff468" },
	}
	_G.CLASS_ICON_TCOORDS = {
		WARRIOR = { 0, 0.25, 0, 0.25 },
		MAGE = { 0.25, 0.49609375, 0, 0.25 },
		ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
		PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
	}
	_G.GetNumClasses = function()
		return 4
	end
	_G.GetClassInfo = function(i)
		local list = { { "Warrior", "WARRIOR" }, { "Mage", "MAGE" }, { "Rogue", "ROGUE" }, { "Priest", "PRIEST" } }
		return list[i][1], list[i][2], i
	end
	-- Classic dungeon floors have no C_Map art on this client; the old tiles (Data/GameFiles.lua) are used by name.
	_G.C_Map.GetMapArtLayers = function()
		return {}
	end
	_G.C_Map.GetMapArtLayerTextures = function()
		return {}
	end
end

-- Before the views (layout is on now): the addon, a login, the window.
function V.prepare()
	_G.DungeonPlannerDB = nil
	mock.LoadAddon(".", "DungeonPlanner.toc", "DungeonPlanner", ns)
	mock.KnowArt(ns)
	mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
	mock.loggedIn = true
	mock.FireEvent("PLAYER_LOGIN")
	mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	ns.UI.Toggle()
end

V.meta = function(_, view)
	return { addon = "DungeonPlanner", view = view.name, locale = mock and mock.locale }
end

V.baseline = "tests/ui_lint_baseline.txt"
-- By design: the window template's portrait sits over its top-left corner.
V.lintIgnore = { "^outside%-window | [%w_.]*PortraitContainer" }
-- The game face is not in the repository: without a font folder (CI), text is measured with the bundled Alegreya
-- Sans, widened by 1.22: Friz Quadrata's advances over Alegreya's, summed over the UI's English strings.
V.fallbackFont = "Media/Fonts/AlegreyaSans-Medium.ttf"
V.fallbackScale = 1.22
V.fontRoots = { { "Interface\\AddOns\\DungeonPlanner\\", "." } }

return V
