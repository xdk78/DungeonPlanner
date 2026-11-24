-- Default settings. DB.lua fills missing keys from here on every load, so a new setting needs only a line here.

local _, ns = ...
local Defaults = ns:NewModule("Defaults")

Defaults.settings = {
	theme = "native", -- one look since version 2 (older "dark" / "light" values are ignored)
	font = "auto", -- "auto" | "game" | "follow" | "clean" (UI/Style.lua explains each)
	scale = 1.0,
	locale = "auto", -- "auto" | a code of ns.LOCALE_LIST ("enUS", "deDE", "esES", "frFR", "plPL", "ruRU")
	debug = false,
	gamepad = "auto", -- the gamepad interface style: "auto" (detected) | "on" | "off" (Core/Compat.lua Gamepad)
	showCoordinates = true,
	mapHere = true, -- the map's "You are here (approx.)" marker inside dungeons (UI/MapHere.lua)
	mapGroup = true, -- the group members' rooms on dungeon maps, from their own addon (UI/MapGroup.lua)
	confirmDelete = true,
	colorblind = false, -- colour-blind friendly colours for pulls, routes, drawings and roles (UI/Style.lua)
	gameIcon = false, -- the minimap button and the window show the game's map icon instead of our logo (UI/Art.lua)
	tracker = {
		enabled = true,
		announceKills = false, -- print a line when a planned boss dies
	},
	recorder = {
		enabled = false, -- opt-in: record pulls, bosses and wipes inside instances (Tracker/Recorder.lua)
	},
	notes = {
		autoShow = true, -- the Notes window opens with the boss's page when its encounter starts (UI/NotesFrame.lua)
		hideInCombat = false,
		acceptFrom = "leaders", -- pages pushed by: "leaders" (leader, raid assistants) | "group" | "nobody"
	},
	providers = {}, -- [adapter id] = false when switched off (Data/Providers.lua); every adapter is on by default
	preferProviderMaps = true, -- drawn maps (Data/ReyesMaps.lua, other addons') before the game's minimap pictures
	openmapOverlay = false, -- experimental: the plan drawn on OpenMap's own dungeon map (UI/OpenMapOverlay.lua)
	mapColors = "parchment", -- minimap floors: "parchment" (tinted like the old map tiles) | "game" (UI/MapCanvas.lua)
	-- How routes look on the map (UI/MapRoutes.lua; sizes in UI/Style.lua ROUTE).
	routes = {
		width = "medium", -- "thin" | "medium" | "thick"
		arrows = "normal", -- direction arrows: "off" | "few" | "normal" | "many"
		arrowSize = "medium", -- "small" | "medium" | "large"
		heads = true, -- an arrowhead just before each numbered stop and at the route's end
		opacity = 1, -- the lines' opacity, 0.4 .. 1
		outline = true, -- a dark edge around lines and arrows
		color = 0, -- 0: each route's own colour; 1 .. 8: every plan route in that palette colour
		ramp = true, -- the colour runs along the route, from that colour at its start to a partner colour at its end
		focusArrows = false, -- while a step is in focus, arrows only on the leg that leads to it
		hover = true, -- highlight the leg under the pointer (and a hovered step's) with a tooltip
	},
	share = {
		acceptFrom = "groupGuild", -- "nobody" | "group" | "groupGuild" | "anyone"
		announce = true, -- send a hello to the group so others see who runs Dungeon Planner
		replyHello = true,
		rooms = true, -- tell the group which room of a dungeon you are in (UI/GroupRooms.lua)
	},
}

Defaults.ui = {
	point = nil, -- { point, relativePoint, x, y }
	width = 1000,
	height = 680,
	view = "home", -- "home" | "instance"
	homeTab = "dungeons", -- "dungeons" | "raids" | "plans" | "shared"
	instance = nil, -- the open instance page: { key, name, kind, ejInstanceID?, uiMapID?, levelMin?, levelMax? }
	tab = "map", -- the instance page's section
	selectedPlan = nil,
	lastPlans = {}, -- [instance key] = the plan last chosen there (DB.RememberPlan)
	onlyWithPlans = false, -- home grid filter
	mapLayers = {}, -- [layer id] = false when hidden on the map (Schema.LAYERS)
	iconScale = 1.0, -- map icon size, 0.5 .. 1.5
	snapRoutes = true, -- the route tool's "Snap to corridors" (UI/RouteSnap.lua)
	showLegend = nil, -- nil: shown the first time the map opens, then hidden until the Legend button shows it
	legendSeen = false,
	homeSelected = nil, -- the instance selected in the home table (its key)
	step = nil, -- the current step: { plan = id, index = n } (Model/Steps.lua)
	run = {}, -- run mode window: { point, shown }
	notes = { width = 380, height = 400 }, -- the Notes window: { point, width, height }; resizable, its size saved
	partyMode = "assignments", -- the Party section: "assignments" | "pages"
	travel = { width = 380, height = 560 }, -- the Getting there window (live map on top): { point, width, height }
	prepShowAll = false, -- the Prep section lists done and too-low quests too
}

-- Fill missing keys of `target` from `defaults` (recursively), and replace values of the wrong type.
function Defaults.Fill(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			Defaults.Fill(target[key], value)
		elseif target[key] == nil or type(target[key]) ~= type(value) then
			target[key] = value
		end
	end
	return target
end
