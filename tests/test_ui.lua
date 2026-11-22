-- Smoke test of the whole addon against the mock client: boot through AceAddon's events, build the window and every
-- panel, use the map tools, share a plan through AceComm, run the slash commands and validate the settings table.
-- Nothing is drawn; this catches errors in our code paths before the first in-game test.
local T = ...
local ns, mock = T.ns, T.mock

-- The home table's row for an instance (other test files may add instances through recommended plans). Scrolls the
-- virtual list to the instance first.
local function findCard(home, name)
	for i, entry in ipairs(home.list.items) do
		if entry.name == name then
			home.list:ScrollTo(i)
			for _, row in ipairs(home.list.rows) do
				if row.entry == entry and row:IsShown() then
					return row
				end
			end
		end
	end
	return nil
end

local booted = false
local function boot()
	if booted then
		return
	end
	booted = true
	_G.DungeonPlannerDB = nil
	mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
	mock.loggedIn = true
	mock.FireEvent("PLAYER_LOGIN")
	mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
end

T.case("Addon boots: database, settings, slash, launcher", function()
	boot()
	T.ok(ns.loggedIn, "OnEnable ran")
	T.ok(ns.adb, "AceDB created")
	T.eq(type(_G.DungeonPlannerDB), "table", "SavedVariable exists")
	T.eq(ns.db.settings.theme, "native")
	T.eq(ns.activeLocale, "enUS", "English without the translation addon")
	T.ok(_G.BINDING_HEADER_DUNGEONPLANNER, "binding header")
	T.eq(_G.BINDING_NAME_DUNGEONPLANNER_NEXT_PULL, "Next pull")
	T.ok(ns.Integrations.status.launcher, "LDB launcher registered")
	-- The launcher shows our logo; the setting switches it to the game's map icon and back.
	local logo = "Interface\\AddOns\\DungeonPlanner\\Media\\LogoIcon"
	T.eq(ns.Integrations.LauncherIcon(), logo, "our logo by default")
	local object = LibStub("LibDataBroker-1.1"):GetDataObjectByName(ns.name)
	ns.db.settings.gameIcon = true
	ns.Integrations.RefreshLauncherIcon()
	T.eq(ns.Art.SPECS.launcher, ns.Art.SPECS.launcherGame, "the game's map icon when picked")
	T.eq(object.icon, ns.Integrations.LauncherIcon(), "the minimap button follows")
	T.ok(object.icon ~= logo, "no longer the logo")
	ns.db.settings.gameIcon = false
	ns.Integrations.RefreshLauncherIcon()
	T.eq(object.icon, logo, "back to the logo")
	T.ok(type(_G.DungeonPlanner.API.GetActivePlan) == "function", "public API")
	T.ok(ns.Style.fonts.body, "font objects")
end)

T.case("Settings options table validates", function()
	boot()
	local registry = LibStub("AceConfigRegistry-3.0")
	local opts = registry:GetOptionsTable("DungeonPlanner", "dialog", "DungeonPlannerTest-1.0")
	T.ok(opts, "registered")
	registry:ValidateOptionsTable(opts, "DungeonPlanner")
	-- Exercise every getter and setter once.
	local function walk(group)
		for _, opt in pairs(group.args or {}) do
			if opt.type == "group" then
				walk(opt)
			elseif opt.get then
				local v = opt.get({})
				if opt.set and opt.type ~= "execute" then
					opt.set({}, v)
				end
			end
		end
	end
	walk(opts)
	local profiles = registry:GetOptionsTable("DungeonPlanner_Profiles", "dialog", "DungeonPlannerTest-1.0")
	T.ok(profiles, "profiles page")
end)

T.case("Window opens on the home grid; tabs switch; an instance page builds every section", function()
	boot()
	ns.UI.Toggle()
	T.ok(ns.UI.IsShown(), "shown")
	local frame = _G.DungeonPlannerMainFrame
	T.ok(frame, "named main frame for skins")
	T.ok(_G.DungeonPlannerHome and _G.DungeonPlannerInstancePage, "named home and instance page")
	T.ok(#_G.UISpecialFrames >= 1, "Escape closes it")
	T.eq(ns.db.ui.view, "home")
	local home = frame.home
	T.ok(home.grid:IsShown(), "grid on the Dungeons tab")
	local card = findCard(home, "Test Dungeon")
	T.ok(card, "a card for the journal's dungeon")
	T.eq(card.level:GetText(), "LV 13-18", "level range from the dungeon finder")
	-- Other tabs.
	ns.UI.GoHome("raids")
	T.ok(not findCard(home, "Test Dungeon"), "dungeons are not on the Raids tab")
	ns.UI.GoHome("plans")
	T.ok(home.plans:IsShown())
	ns.UI.GoHome("shared")
	T.ok(home.shared:IsShown())
	ns.UI.GoHome("dungeons")
	-- Search filters the grid.
	ns.UI.ctx.search = "nothing like this"
	home:Refresh()
	T.eq(#home.grid.items, 0, "search hides the card")
	ns.UI.ctx.search = ""
	home:Refresh()

	-- Open the instance: no plan yet, so the page offers to create one.
	card:GetScript("OnDoubleClick")(card, "LeftButton")
	T.eq(ns.db.ui.view, "instance")
	local page = frame.instancePage
	T.ok(page.empty:IsShown(), "empty state")
	local plan = ns.Home.CreatePlan("dungeon", "Smoke", card.entry)
	T.eq(#plan.encounters, 2, "bosses from the journal")
	T.eq(ns.db.ui.selectedPlan, plan.id)
	T.ok(not page.empty:IsShown(), "plan shown")
	for _, sec in ipairs(ns.UI.SECTIONS) do
		ns.UI.SelectTab(sec.id)
		local panel = page.panels[sec.id]
		T.ok(panel, "section " .. sec.id)
		panel:Refresh()
	end
	ns.UI.SelectTab("notes")
	T.eq(ns.db.ui.tab, "plan", "old tab names map to sections")
	T.eq(ns.Names.Encounter(plan.encounters[1]), "Journal boss 91", "names come from the journal by ID")
	-- Breadcrumb back home.
	page.back:GetScript("OnClick")(page.back, "LeftButton")
	T.eq(ns.db.ui.view, "home")
	home:Refresh()
	T.eq(findCard(home, "Test Dungeon").count:GetText(), "1 plan", "card counts the plan")
	ns.UI.SelectPlan(plan.id)
	T.eq(ns.db.ui.view, "instance", "selecting a plan opens its page")
end)

T.case("Map tools add markers, positions, pulls and routes; layers and undo", function()
	boot()
	local ctx = ns.UI.ctx
	local plan = ctx:Plan()
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	T.ok(canvas.artInfo, "map art found for uiMapID 100")
	T.eq(#canvas.tiles, 12, "12 tiles")
	-- No boss markers yet: the Adventure Guide's pins are shown.
	canvas:DrawContent()
	T.eq(canvas.counts.journal, 2, "journal boss pins")
	-- The mock cursor is at (0,0) of a canvas whose top is 300: normalized (0, 1).
	ctx.tool = "marker"
	ctx.kind = "boss"
	canvas:OnMapClick("LeftButton")
	T.eq(#plan.markers, 1, "marker placed")
	canvas:DrawContent()
	T.eq(canvas.counts.journal, 0, "journal pins give way to the plan's bosses")
	ctx.tool = "position"
	ctx.role = "HEALER"
	ctx.focusEncounter = plan.encounters[1].id
	canvas:OnMapClick("LeftButton")
	local pos = plan.markers[2]
	T.eq(pos.kind, "position")
	T.eq(pos.role, "HEALER")
	T.eq(pos.encounter, plan.encounters[1].id, "position belongs to the focused boss")
	canvas:DrawContent()
	T.eq(canvas.counts.pins, 2, "position shown while its boss is in focus")
	ctx.focusEncounter = nil
	canvas:DrawContent()
	T.eq(canvas.counts.pins, 1, "and hidden otherwise")
	ctx.tool = "pull"
	ctx.currentPull = nil
	canvas.cb.onSelectMarker(plan.markers[1].id)
	T.eq(#plan.pulls, 1, "pull created by the pull tool")
	T.eq(plan.markers[1].pull, plan.pulls[1].id)
	ctx.tool = "route"
	canvas:OnMapClick("LeftButton")
	mock.shiftDown = true
	canvas:OnMapClick("LeftButton")
	mock.shiftDown = false
	T.eq(#plan.routes, 1)
	T.eq(#plan.routes[1].points, 2)
	T.eq(plan.routes[1].points[2].step, 1, "shift-click adds a numbered stop")
	canvas:OnMapClick("RightButton")
	T.eq(ctx.activeRoute, nil, "right click finishes the route")
	ctx.tool = "select"
	canvas:DrawContent()
	T.ok(canvas.counts.lines >= 1 and canvas.counts.points >= 1, "path and stop drawn")
	-- Layers: hiding bosses hides the boss pin.
	ns.db.ui.mapLayers.bosses = false
	canvas:DrawContent()
	T.eq(canvas.counts.pins, 0, "bosses layer hidden")
	ns.db.ui.mapLayers.bosses = nil
	map.iconSize.plus:GetScript("OnClick")(map.iconSize.plus, "LeftButton")
	T.ok(ns.db.ui.iconScale > 1, "icon size stepper")
	ns.db.ui.iconScale = 1
	canvas:ZoomAt(1)
	canvas:ZoomAt(-1)
	canvas:ResetView()
	map:Refresh()
	-- Undo the stop.
	T.ok(ctx:CanUndo())
	ctx:Undo()
	T.eq(#ctx:Plan().routes[1].points, 1, "undo removed a point")
	map:Refresh()
	-- A map without art falls back to the parchment grid.
	canvas:SetMap(999)
	T.eq(canvas.artInfo, nil)
	T.ok(canvas.noArt:IsShown(), "grid message shown")
	canvas:SetMap(100)
end)

T.case("A recommended plan is read-only, shows as recommended, and copies into an editable plan", function()
	boot()
	local smokeId = ns.db.ui.selectedPlan
	local ok = ns.Bundled.Add({
		id = "test-dungeon-standard",
		rev = 3,
		name = "Standard route",
		author = "Data team",
		instance = { name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63, levelMin = 13, levelMax = 18 },
		floors = { { uiMapID = 100, name = "" } },
		pulls = { { id = "u1", name = "First pack", color = 2 } },
		markers = {
			{ id = "m1", floor = 1, x = 0.2, y = 0.3, kind = "pack", pull = "u1", label = "Casters" },
			{ id = "m2", floor = 1, x = 0.4, y = 0.3, kind = "position", role = "TANK", label = "Tank here" },
			{ id = "m3", floor = 1, x = 0.5, y = 0.9, kind = "entrance" },
		},
		routes = {
			{ id = "r1", floor = 1, color = 1, points = { { 0.5, 0.9 }, { 0.2, 0.3, step = 1, note = "Pull", pull = "u1" } } },
		},
	})
	T.ok(ok, "added")
	local rec = ns.DB.GetPlan("b:test-dungeon-standard")
	T.ok(rec and rec.bundled, "found by id")
	T.eq(ns.Plan.AddPull(rec), nil, "model refuses to change it")
	-- The page shows it as recommended, without edit tools.
	local frame = _G.DungeonPlannerMainFrame
	ns.UI.SelectPlan(rec.id)
	local page = frame.instancePage
	T.ok(page.header.copy:IsShown(), "copy button")
	T.ok(page.header.plan.label:GetText():find("Standard route (recommended)", 1, true), "the picker says recommended")
	ns.UI.SelectTab("map")
	local map = page.panels.map
	T.ok(not map.toolButtons.marker:IsShown(), "no edit tools")
	local before = #rec.markers
	map.canvas:OnMapClick("LeftButton")
	T.eq(#rec.markers, before, "clicking the map adds nothing")
	map.canvas:DrawContent()
	T.eq(map.canvas.counts.points, 1, "numbered stop drawn")
	-- Home counts it.
	ns.UI.GoHome("dungeons")
	T.eq(findCard(frame.home, "Test Dungeon").tag:GetText(), "Recommended plan")
	-- Copy.
	ns.UI.SelectPlan(rec.id)
	page.header.copy:GetScript("OnClick")(page.header.copy, "LeftButton")
	local copy = ns.UI.ctx:Plan()
	T.ok(copy and not copy.bundled, "the copy is selected")
	T.eq(copy.origin.bundled, "test-dungeon-standard")
	T.eq(copy.origin.rev, 3)
	T.ok(ns.Plan.AddPull(copy), "the copy can be edited")
	T.eq(copy.routes[1].points[2].note, "Pull")
	-- Exporting the recommended plan keeps where it came from.
	local kind, back = ns.Codec.Decode(ns.Codec.ExportPlan(rec))
	T.eq(kind, "plan")
	T.eq(back.origin.bundled, "test-dungeon-standard")
	T.eq(back.markers[2].role, "TANK")
	ns.UI.SelectPlan(smokeId)
end)

T.case("A recommended plan that places some bosses still gets the Adventure Guide's pins for the others", function()
	boot()
	local smokeId = ns.db.ui.selectedPlan
	-- The mock journal pins map 100 with "Boss 1" at (0.3, 0.4) and "Boss 2" at (0.6, 0.4).
	local function add(id, bosses)
		local markers = {}
		for i, b in ipairs(bosses) do
			markers[i] = { id = "m" .. i, floor = 1, x = b.x, y = b.y, kind = "boss", label = b.name }
		end
		T.ok(ns.Bundled.Add({
			id = id,
			name = id,
			instance = { name = "Pin Fallback Dungeon", kind = "dungeon" },
			floors = { { uiMapID = 100, name = "" } },
			markers = markers,
		}))
		return "b:" .. id
	end
	local function pinsShown(planId)
		ns.UI.SelectPlan(planId)
		ns.UI.SelectTab("map")
		local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
		canvas:DrawContent()
		return canvas.counts.journal
	end
	T.eq(pinsShown(add("pin-none", {})), 2, "no bosses placed: both pins")
	T.eq(pinsShown(add("pin-by-name", { { name = "Boss 1", x = 0.9, y = 0.9 } })), 1, "a boss with the pin's name hides that pin")
	T.eq(pinsShown(add("pin-by-spot", { { name = "Another name", x = 0.61, y = 0.41 } })), 1, "a boss at the pin's spot hides that pin")
	T.eq(pinsShown(add("pin-all", { { name = "Boss 1", x = 0.1, y = 0.1 }, { name = "boss 2", x = 0.2, y = 0.2 } })), 0, "every boss placed")
	-- A plan of your own keeps the simple rule: any boss on the floor hides the pins.
	T.eq(#ns.Instances.PinsNotPlaced({ markers = {}, encounters = {} }, 1, { { x = 0.5, y = 0.5, name = "X" } }), 1)
	ns.UI.SelectPlan(smokeId)
end)

T.case("Art report and debug list atlases, files and templates", function()
	boot()
	local rows = ns.Art.Report()
	T.ok(#rows > 20, "every art key reported")
	local tex = _G.DungeonPlannerMainFrame:CreateTexture()
	T.ok(ns.Art.Set(tex, "kind_entrance"), "atlas path")
	T.ok(ns.Art.Set(tex, "kind_loot"), "file path")
	T.eq(ns.Art.HasAtlas("Dungeon"), true)
	T.eq(ns.Art.HasAtlas("no-such-atlas"), false)
	ns.Slash.Handle("debug")
end)

T.case("Actions, slash commands and the public API", function()
	boot()
	ns.Slash.Handle("next")
	T.ok(ns.API.GetCurrentPull(), "current pull after next")
	ns.Slash.Handle("prev")
	ns.Slash.Handle("help")
	ns.Slash.Handle("debug")
	ns.Slash.Handle("mapid")
	ns.Slash.Handle("minimap")
	T.eq(ns.db.minimap.hide, true)
	ns.Slash.Handle("minimap")
	T.eq(ns.db.minimap.hide, false)
	local fired = {}
	ns.API.RegisterCallback(fired, "DUNGEONPLANNER_PULL_ADVANCED", function(_, _planId, index)
		fired.index = index
	end)
	_G.DungeonPlanner_Binding("nextPull")
	T.ok(fired.index, "public event fired")
	T.ok(#ns.API.GetPlans() >= 1)
	T.ok(ns.API.GetPlanCopy(ns.db.ui.selectedPlan))
	local selfTests = ns.Compat.SelfTest()
	for _, r in ipairs(selfTests) do
		T.ok(r.ok, "self-test " .. r.name .. ": " .. r.detail)
	end
end)

T.case("Boss kills from ENCOUNTER_END are tracked once", function()
	boot()
	local plan = ns.UI.ctx:Plan()
	local enc = plan.encounters[1]
	local seen = { n = 0 }
	ns.API.RegisterCallback(seen, "DUNGEONPLANNER_BOSS_KILLED", function()
		seen.n = seen.n + 1
	end)
	mock.FireEvent("ENCOUNTER_END", enc.dungeonEncounterID, "Boss 1", 1, 5, 1)
	mock.FireEvent("BOSS_KILL", enc.dungeonEncounterID, "Boss 1")
	T.eq(ns.Progress.KillsOf(ns.char.progress, enc.dungeonEncounterID), 1, "deduplicated")
	T.ok(ns.Progress.IsKilledInRun(ns.char.progress, enc.dungeonEncounterID))
	mock.FireEvent("ENCOUNTER_END", 999, "Wipe", 1, 5, 0)
	T.eq(ns.Progress.KillsOf(ns.char.progress, 999), 0, "a wipe is not a kill")
end)

T.case("Sharing over AceComm: offer, accept, payload, import", function()
	boot()
	local plan = ns.UI.ctx:Plan()
	mock.inGroup = true
	mock.sent = {}
	local transfer, err = ns.Comm.SharePlan(plan, "GROUP")
	T.ok(transfer, tostring(err))
	mock.Advance(1)
	T.ok(#mock.sent >= 1, "offer sent through ChatThrottleLib")
	-- Another player accepts; after the gather window the payload goes out.
	ns.Comm.OnMessage(ns.prefix, "A^" .. transfer.tid, "WHISPER", "Anna")
	for _ = 1, 40 do
		mock.Advance(0.5)
	end
	T.ok(transfer.state == "sending" or transfer.state == "done", "state " .. transfer.state)
	-- Receiving side: an offer from a group member is prompted, accepted, and imported.
	local realUnitInParty = _G.UnitInParty
	_G.UnitInParty = function(name)
		return name == "Bob"
	end
	local before = #ns.DB.Plans()
	local data = ns.Codec.ExportPlan(plan)
	local offer = ns.Transfer.Encode({ type = "offer", proto = ns.PROTOCOL_VERSION, tid = "zz1", bytes = #data,
		sum = ns.Checksum.Hex(ns.Checksum.Adler32(data)), kind = "plan", name = plan.name })
	local prompted
	ns:On("SHARE_PROMPT", "test", function(t)
		prompted = t
	end)
	ns.Comm.OnMessage(ns.prefix, offer, "PARTY", "Bob")
	T.ok(prompted, "prompt shown")
	ns.Comm.Respond(prompted, true)
	ns.Comm.OnMessage(ns.prefix, "P^zz1^" .. data, "PARTY", "Bob")
	T.eq(#ns.DB.Plans(), before + 1, "received plan imported")
	-- Strangers are refused under the default policy.
	prompted = nil
	ns.Comm.OnMessage(ns.prefix, offer:gsub("zz1", "zz2"), "WHISPER", "Stranger")
	T.eq(prompted, nil, "stranger not prompted")
	mock.inGroup = false
	_G.UnitInParty = realUnitInParty
end)

T.case("Theme switch and Polish fonts follow the translation addon", function()
	boot()
	ns.Style.SetTheme("dark")
	ns.db.settings.font = "follow"
	_G.GameFontHighlight._font = "Interface\\AddOns\\WoWPoPolskuForever\\Media\\frizquadratatt_pl.ttf"
	ns.Style.SetupFonts()
	T.eq(ns.Style.fontFile, _G.GameFontHighlight._font, "follows the game's (translated) font")
	ns.db.settings.font = "auto"
	ns.Style.SetupFonts()
	T.eq(ns.Style.fontFile, "Fonts\\FRIZQT__.TTF", "auto without the translation addon: game font")
end)

T.case("A Polish UI puts our font objects on every text, with a Polish-capable face", function()
	boot()
	local S = ns.Style
	local wasLocale = ns.activeLocale
	ns.SetLocale("plPL")
	mock.loadedAddons = { WoWPoPolskuForever = true }
	-- WoW Po Polsku's face cannot be opened: the bundled one is next.
	mock.missingFonts = { [S.POLISH_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, S.MEDIA .. "Fonts\\AlegreyaSans-Medium.ttf", "bundled face when WoW Po Polsku's is missing")
	T.eq(S.polishFace, S.fontFile)
	mock.missingFonts = nil
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, S.POLISH_FACE, "WoW Po Polsku's face first")
	-- Nothing loads: the game face, and /dp debug says so.
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, S.CLEAN_FACE, "the cleaned copy when the full file is refused")
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true, [S.CLEAN_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, "Fonts\\FRIZQT__.TTF", "game face last")
	mock.loadedAddons = nil
	mock.missingFonts = nil
	S.ForgetFontProbes()
	S.SetupFonts()

	-- Build everything: home tabs, an instance page with every section, a dialog, a tooltip.
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	for _, tab in ipairs({ "raids", "plans", "shared", "dungeons" }) do
		ns.UI.GoHome(tab)
	end
	local plans = ns.DB.Plans()
	if plans[1] then
		ns.UI.SelectPlan(plans[1].id)
		for _, sec in ipairs(ns.UI.SECTIONS) do
			ns.UI.SelectTab(sec.id)
		end
	end
	ns.Widgets.ShowDialog({ title = "Test", text = "Test", buttons = { { "OK" } } })
	local tipOwner = CreateFrame("Button", nil, _G.DungeonPlannerMainFrame)
	ns.Widgets.SetTooltip(tipOwner, "Title", "Text")

	local roots = { _G.DungeonPlannerMainFrame, _G.DungeonPlannerDialog }
	local function ours(f)
		local depth = 0
		while f and depth < 60 do
			for _, r in ipairs(roots) do
				if f == r then
					return true
				end
			end
			f, depth = f._parent, depth + 1
		end
		return false
	end
	local function isOurFont(o)
		local name = o and o.GetName and o:GetName()
		return type(name) == "string" and name:find("^DungeonPlannerFont_") ~= nil
	end
	local checked, bad = 0, {}
	for _, f in ipairs(mock.frames) do
		if ours(f) then
			local t = f._type
			if t == "FontString" and f._text and f._text ~= "" then
				checked = checked + 1
				if not isOurFont(f._fontObject) then
					bad[#bad + 1] = "text \"" .. f._text .. "\""
				end
			elseif t == "Button" and f._text and f._text ~= "" then
				checked = checked + 1
				if not isOurFont(f._normalFont) then
					bad[#bad + 1] = "template button \"" .. f._text .. "\""
				end
			elseif t == "EditBox" then
				checked = checked + 1
				if not isOurFont(f._fontObject) then
					bad[#bad + 1] = "edit box"
				end
			end
		end
	end
	T.ok(checked > 50, "many texts checked (" .. checked .. ")")
	T.eq(#bad, 0, "texts without our font: " .. table.concat(bad, "; ", 1, math.min(#bad, 8)))
	_G.DungeonPlannerDialog:Hide()
	ns.SetLocale(wasLocale)
	S.SetupFonts()
end)

T.case("A Russian UI gets a face with Cyrillic on a client that is not Russian; German, French and Spanish keep the game face", function()
	boot()
	local S = ns.Style
	local wasLocale = ns.activeLocale
	local CYRILLIC = "Fonts\\FRIZQT___CYR.TTF"
	for _, code in ipairs({ "deDE", "frFR", "esES" }) do
		ns.SetLocale(code)
		S.ForgetFontProbes()
		S.SetupFonts()
		T.eq(S.fontFile, "Fonts\\FRIZQT__.TTF", code .. ": Latin-1 letters are in the game's face")
	end
	ns.SetLocale("ruRU")
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, CYRILLIC, "the game's Cyrillic cut when this client has it")
	mock.missingFonts = { [CYRILLIC] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, S.BUNDLED_FACE, "the bundled Alegreya Sans (it has Cyrillic) when the client has no Cyrillic cut")
	mock.missingFonts = { [CYRILLIC] = true, [S.BUNDLED_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, "Fonts\\FRIZQT__.TTF", "the game face last")
	T.eq(S.cyrillicFace, nil, "no Cyrillic face loads")
	T.ok(S.PolishFontNote() ~= "", "the language dialog says Russian will show boxes")
	mock.missingFonts = { [CYRILLIC] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.cyrillicFace, S.BUNDLED_FACE, "the face in use is recorded")
	T.eq(S.PolishFontNote(), "", "no note while a face loads")
	-- A font setting we cannot vouch for gets a note, not a silent box.
	ns.db.settings.font = "clean"
	T.ok(S.PolishFontNote():find("Arial Narrow", 1, true), "Arial Narrow with a Russian UI")
	ns.db.settings.font = "auto"
	-- The font test lists the game's Cyrillic cut.
	mock.missingFonts = nil
	S.ForgetFontProbes()
	local test = S.FontTest()
	T.ok(test.cyrillic and test.cyrillic.usable, "FRIZQT___CYR.TTF is probed")
	local listed = false
	for _, line in ipairs(S.FontTestLines(test)) do
		listed = listed or line:find("FRIZQT___CYR.TTF", 1, true) ~= nil
	end
	T.ok(listed, "/dp debug lists it")
	-- A Russian client keeps its own cut whatever the UI language.
	mock.missingFonts = nil
	mock.locale = "ruRU"
	ns.SetLocale("enUS")
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, CYRILLIC, "Russian client, English UI")
	mock.locale = "enUS"
	ns.SetLocale(wasLocale or "enUS")
	S.ForgetFontProbes()
	S.SetupFonts()
end)

T.case("A Russian UI looks at its face again after the loading screen: confirmed, switched, or not needed", function()
	boot()
	local S = ns.Style
	local wasLocale, wasFont, wasTimer, wasPrint, wasCan = ns.activeLocale, ns.db.settings.font, _G.C_Timer, ns.Print, S.CanLoadFont
	local CYRILLIC = "Fonts\\FRIZQT___CYR.TTF"
	local pending, printed
	_G.C_Timer = { After = function(_, fn)
		pending = fn
	end }
	ns.Print = function(_, ...)
		printed = table.concat({ ... }, " ")
	end
	local function fresh(answers)
		pending, printed = nil, nil
		S.CanLoadFont = wasCan
		S.ForgetFontProbes() -- also allows RecheckFonts to run again
		S.CanLoadFont = function(file)
			return answers[file]
		end
		S.SetupFonts()
	end
	ns.db.settings.font = "auto"
	ns.SetLocale("ruRU")
	mock.locale = "enUS"

	-- The client cannot tell yet (nil): the game's cut is taken, looked at again, and confirmed: no message.
	local answers = {}
	fresh(answers)
	T.eq(S.cyrillicFace, CYRILLIC, "an unproven face is taken")
	S.RecheckFonts()
	T.ok(pending, "a second look is scheduled")
	answers[CYRILLIC] = true
	pending()
	T.eq(S.cyrillicFace, CYRILLIC, "confirmed: kept")
	T.eq(printed, nil, "and nothing said")

	-- Unproven, then refused: the bundled Alegreya Sans takes over, and the chat says so.
	answers = {}
	fresh(answers)
	S.RecheckFonts()
	T.ok(pending, "a second look is scheduled")
	answers[CYRILLIC] = false
	answers[S.BUNDLED_FACE] = true
	pending()
	T.eq(S.cyrillicFace, S.BUNDLED_FACE, "switched to the bundled face")
	T.eq(S.fontFile, S.BUNDLED_FACE)
	T.ok(printed and printed:find("AlegreyaSans-Medium.ttf", 1, true), "the chat names the face")

	-- A face already proven needs no second look.
	answers = { [CYRILLIC] = true }
	fresh(answers)
	S.RecheckFonts()
	T.eq(pending, nil, "proven: no timer")

	-- A Russian client uses its own cut, so there is nothing to look at again.
	mock.locale = "ruRU"
	fresh({})
	S.RecheckFonts()
	T.eq(pending, nil, "Russian client: no timer")

	mock.locale = "enUS"
	S.CanLoadFont = wasCan
	ns.Print = wasPrint
	_G.C_Timer = wasTimer
	ns.db.settings.font = wasFont
	ns.SetLocale(wasLocale or "enUS")
	S.ForgetFontProbes()
	S.SetupFonts()
end)

T.case("Route names generated in English show the UI's word", function()
	boot()
	T.eq(ns.Names.Route({ name = "Route" }), ns.L["Route"])
	T.eq(ns.Names.Route({ name = "" }), ns.L["Route"])
	T.eq(ns.Names.Route({ name = "Upper deck" }), "Upper deck")
end)

T.case("Polish letters test: drawn in the face a Polish UI would use, even when the UI is English", function()
	boot()
	local S = ns.Style
	local wasLocale = ns.activeLocale
	ns.SetLocale("enUS")
	mock.missingFonts = nil
	mock.loadedAddons = { WoWPoPolskuForever = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, "Fonts\\FRIZQT__.TTF", "English: the game face")
	local file, kind = S.PolishFace()
	T.eq(file, S.POLISH_FACE, "WoW Po Polsku's face first")
	T.eq(kind, "wowpopolsku")
	-- Dismiss dialogs earlier tests left (each Hide shows the next queued one).
	local dialog = _G.DungeonPlannerDialog
	for _ = 1, 20 do
		if not (dialog and dialog:IsShown()) then
			break
		end
		dialog:Hide()
	end
	ns.Slash.Handle("debug")
	dialog = _G.DungeonPlannerDialog
	T.ok(dialog and dialog:IsShown(), "the test dialog")
	T.ok(dialog.sample:IsShown(), "a sample line")
	T.eq((dialog.sample:GetFont()), S.POLISH_FACE, "the sample uses the Polish face, not the UI's")
	T.ok(dialog.text:GetText():find("FRIZQT__.TTF", 1, true), "and names the current UI face")
	T.ok(dialog.text:GetText():find("frizquadratatt_pl.ttf", 1, true), "and the Polish one")
	dialog:Hide()
	-- Without WoW Po Polsku: the bundled face; without either: the game face, said plainly.
	mock.missingFonts = { [S.POLISH_FACE] = true }
	S.ForgetFontProbes()
	file, kind = S.PolishFace()
	T.eq(file, S.MEDIA .. "Fonts\\AlegreyaSans-Medium.ttf")
	T.eq(kind, "bundled")
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true, [S.CLEAN_FACE] = true }
	S.ForgetFontProbes()
	file, kind = S.PolishFace()
	T.eq(kind, "game")
	T.eq(file, "Fonts\\FRIZQT__.TTF")
	mock.missingFonts = nil
	mock.loadedAddons = nil
	S.ForgetFontProbes()
	ns.SetLocale(wasLocale or "enUS")
	S.SetupFonts()
	-- The bundled face is where the addon's folder says (Interface\AddOns\DungeonPlanner\Media\Fonts\...).
	for _, path in ipairs({ "Media/Fonts/AlegreyaSans-Medium.ttf", "Media/Fonts/DPSans.ttf" }) do
		local f = io.open(path, "rb")
		T.ok(f, path .. " exists at the path the chain uses")
		if f then
			f:close()
		end
	end
	T.eq(S.BUNDLED_FACE, S.MEDIA .. "Fonts\\AlegreyaSans-Medium.ttf")
	T.eq(S.CLEAN_FACE, S.MEDIA .. "Fonts\\DPSans.ttf")
	T.eq(S.MEDIA, "Interface\\AddOns\\DungeonPlanner\\Media\\", "the addon folder's name")
end)

local function closeAllDialogs()
	local dialog = _G.DungeonPlannerDialog
	for _ = 1, 20 do
		if not (dialog and dialog:IsShown()) then
			break
		end
		dialog:Hide()
	end
end

-- /dp debug's dialog text and what it printed, including the font test's second look (2 s later).
local function runDebug()
	closeAllDialogs()
	local from = #mock.printed + 1
	ns.Slash.Handle("debug")
	local dialog = _G.DungeonPlannerDialog
	local text = dialog.text:GetText()
	mock.Advance(2.5)
	local chat = table.concat(mock.printed, "\n", from)
	closeAllDialogs()
	return text, chat
end

T.case("Fonts: a face that failed once is tried again; nothing is called missing or damaged", function()
	boot()
	local S = ns.Style
	local bundled = S.BUNDLED_FACE
	mock.loadedAddons = { WoWPoPolskuForever = true }
	mock.missingFonts = { [bundled] = true }
	S.ForgetFontProbes()
	T.eq(S.CanLoadFont(bundled), false, "refused now")
	mock.missingFonts = nil
	T.eq(S.CanLoadFont(bundled), true, "and tried again: the first failure does not stick")
	-- Nothing loads: the debug report says what it saw, never "missing or damaged".
	mock.missingFonts = { [S.POLISH_FACE] = true, [bundled] = true, [S.CLEAN_FACE] = true }
	S.ForgetFontProbes()
	local text, chat = runDebug()
	T.ok(not (text .. chat):find("damaged", 1, true) and not (text .. chat):find("cannot be opened", 1, true),
		"no claim the file is broken")
	T.ok(chat:find("AlegreyaSans-Medium.ttf: does not load (SetFont false, then false", 1, true), "each face's probes")
	T.ok(chat:find("Neither bundled font loads", 1, true), "the verdict without other addons' fonts to compare")
	T.eq(_G.DungeonPlannerDialog.spec.sample.font, S.BUNDLED_FACE, "the sample is drawn in the bundled face anyway")
	-- The cleaned copy loads, the full file does not: the file is the problem, and the copy is used.
	mock.missingFonts = { [S.POLISH_FACE] = true, [bundled] = true }
	S.ForgetFontProbes()
	text, chat = runDebug()
	T.ok(chat:find("DPSans.ttf loads but AlegreyaSans-Medium.ttf does not", 1, true), "file verdict")
	T.ok(text:find("DPSans.ttf", 1, true), "a Polish UI would use the cleaned copy")
	mock.missingFonts = nil
	mock.loadedAddons = nil
	S.ForgetFontProbes()
end)

T.case("Fonts: WoW Po Polsku disabled is said so, and its face is not tried", function()
	boot()
	local S = ns.Style
	mock.loadedAddons = nil -- installed or not, not enabled: the mock's GetAddOnInfo knows no addon
	mock.missingFonts = nil
	S.ForgetFontProbes()
	local file, kind = S.PolishFace()
	T.eq(file, S.BUNDLED_FACE, "the bundled face first when WoW Po Polsku is not enabled")
	T.eq(kind, "bundled")
	local realInfo = _G.C_AddOns.GetAddOnInfo
	_G.C_AddOns.GetAddOnInfo = function(name)
		if name == "WoWPoPolskuForever" then
			return name, "WoW Po Polsku", "", false, "DISABLED"
		end
		return nil
	end
	T.eq(ns.Integrations.AddonState("WoWPoPolskuForever"), "disabled")
	local text, chat = runDebug()
	T.ok(text:find("WoW Po Polsku is disabled", 1, true), "the dialog says it is disabled")
	T.ok(chat:find("frizquadratatt_pl.ttf: WoW Po Polsku is disabled", 1, true), "and so does the report")
	T.ok(not chat:find("frizquadratatt_pl.ttf: does not load", 1, true), "not a bare false")
	_G.C_AddOns.GetAddOnInfo = realInfo
	T.eq(ns.Integrations.AddonState("WoWPoPolskuForever"), "missing")
	_G.C_AddOns.GetAddOnInfo = realInfo
	S.ForgetFontProbes()
end)

T.case("Fonts: the font test draws every face and /dp scan saves both looks", function()
	boot()
	local S = ns.Style
	mock.loadedAddons = { WoWPoPolskuForever = true }
	mock.missingFonts = { [S.BUNDLED_FACE] = true }
	S.ForgetFontProbes()
	closeAllDialogs()
	ns.Slash.Handle("debug")
	local dialog = _G.DungeonPlannerDialog
	local test = S.FontTest()
	local panel = S.ShowFontTest(test)
	T.ok(panel and panel:IsShown(), "the test panel")
	T.eq(#panel.rows, #S.POLISH_FACES, "one row per face")
	T.eq((panel.rows[3].direct:GetFont()), S.CLEAN_FACE, "drawn in its face")
	T.eq((panel.rows[3].object:GetFont()), S.CLEAN_FACE, "and through its font object")
	dialog:Hide()
	T.ok(not panel:IsShown(), "closing the dialog closes the test")
	mock.Advance(2.5)
	-- /dp scan: the record now and after the second look.
	ns.Slash.Handle("scan")
	local d = _G.DungeonPlannerDB.diagnostics
	T.ok(d.fontTest and d.fontTest.faces["DPSans.ttf"], "per face")
	T.ok(d.fontTest.faces["AlegreyaSans-Medium.ttf"].now:find("set=false", 1, true), "SetFont's return")
	T.eq(d.fontTest.texture, "true", "one of our textures as a control")
	T.ok(d.fontTest.game:find("got=FRIZQT__.TTF", 1, true), "the game face as a control")
	mock.Advance(2.5)
	T.ok(d.fontTest.faces["DPSans.ttf"].later:find("set=true", 1, true), "the second look")
	T.ok(d.fontTest.verdict[#d.fontTest.verdict]:find("DPSans.ttf loads", 1, true), "and its verdict")
	ns.Slash.Handle("scan clear")
	mock.missingFonts = nil
	mock.loadedAddons = nil
	S.ForgetFontProbes()
	closeAllDialogs()
end)

T.case("Fonts: a Polish UI without a Polish face stays Polish, says why once, and takes a face that loads later", function()
	boot()
	local S = ns.Style
	local wasLocale = ns.activeLocale
	ns.SetLocale("plPL")
	mock.loadedAddons = nil
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true, [S.CLEAN_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	T.eq(S.fontFile, "Fonts\\FRIZQT__.TTF", "no face: the game's")
	T.ok(S.PolishFontNote() ~= "", "the language dialog explains it")
	-- The first loading screen: a second look 3 s later picks a face that loads by then.
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true }
	mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	mock.Advance(3.5)
	T.eq(S.fontFile, S.CLEAN_FACE, "switched to the face that loads")
	T.eq(S.PolishFontNote(), "", "no note once a face loads")
	T.eq(_G.DungeonPlannerDB.fontsAtLogin, nil, "the old login record is gone")
	-- Still nothing after the second look: one line in chat, and the UI stays Polish.
	mock.missingFonts = { [S.POLISH_FACE] = true, [S.BUNDLED_FACE] = true, [S.CLEAN_FACE] = true }
	S.ForgetFontProbes()
	S.SetupFonts()
	local from = #mock.printed + 1
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	mock.Advance(3.5)
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	mock.Advance(3.5)
	local said = 0
	for i = from, #mock.printed do
		if mock.printed[i]:find(ns.L["Font test"] == "Font test" and "No font with Polish letters loads,"
			or "czcionka z polskimi literami", 1, true) then
			said = said + 1
		end
	end
	T.eq(said, 1, "said once")
	T.eq(ns.activeLocale, "plPL", "the UI stays Polish")
	mock.missingFonts = nil
	S.ForgetFontProbes()
	ns.SetLocale(wasLocale or "enUS")
	S.SetupFonts()
end)

T.case("Approximate spots: '(approx.)' becomes a small mark in step text and tooltips", function()
	boot()
	local U = ns.Util
	local text, approx = U.SplitApprox("Enter and clear the ghost dwarves (approx.)")
	T.eq(text, "Enter and clear the ghost dwarves")
	T.eq(approx, true)
	text, approx = U.SplitApprox("(approx.)")
	T.eq(text, "")
	T.eq(approx, true)
	T.eq(select(2, U.SplitApprox("Exact")), false)
	T.eq(U.SplitApprox(nil), nil)
	T.ok(ns.Style.WithApprox("Boss", true):find(ns.Style.APPROX, 1, true))
	T.eq(ns.Style.WithApprox("Boss", false), "Boss")
	-- Only the text, a no-break space and the mark: no control bytes (a mangled escape once drew a box and "94p").
	local marked = ns.Style.WithApprox("Boss", true)
	T.eq(marked, "Boss\194\160" .. ns.Style.ApproxMark())
	local plain = marked:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	T.eq(plain, "Boss\194\160" .. ns.Style.APPROX)
	T.ok(not plain:find("[%z\1-\31\127]"), "no control characters")
	-- Hall of Thanes: the quest giver's step and a boss step.
	local plan = ns.Bundled.Get("b:hall-of-thanes")
	local steps = ns.Steps.Build(plan)
	local title, caption, isApprox, note = ns.UI.StepText(plan, steps[2])
	T.eq(title, "Ghostly Attendant")
	T.eq(caption, ns.L.quest_npc)
	T.eq(isApprox, true)
	T.ok(not note:find("approx", 1, true), "note without the words")
	local portalTitle, _, portalApprox = ns.UI.StepText(plan, steps[1])
	T.eq(portalTitle, "Portal in")
	T.eq(portalApprox, true)
	-- A map tooltip: the note without the words, a muted line saying it is an estimate.
	local lines = {}
	local tt = { AddLine = function(_, line)
		lines[#lines + 1] = line
	end }
	ns.MapCanvas.AddNote(tt, "Kill the Summoner first. (approx.)")
	T.eq(lines[1], "Kill the Summoner first.")
	T.ok(lines[2] and lines[2]:find(ns.Style.APPROX, 1, true), "the estimate line")
end)
