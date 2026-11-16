-- Default settings. DB.lua fills missing keys from here on every load, so a new setting needs only a line here.

local _, ns = ...
local Defaults = ns:NewModule("Defaults")

Defaults.settings = {
	theme = "native", -- one look since version 2 (older "dark" / "light" values are ignored)
	font = "auto", -- "auto" | "game" | "follow" | "clean" (UI/Style.lua explains each)
	scale = 1.0,
	locale = "auto", -- "auto" | "enUS" | "plPL"
	debug = false,
	showCoordinates = true,
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
	preferProviderMaps = true, -- another addon's drawn map before the game's minimap pictures (Data/MinimapArt.lua)
	mapColors = "parchment", -- minimap floors: "parchment" (tinted like the old map tiles) | "game" (UI/MapCanvas.lua)
	share = {
		acceptFrom = "groupGuild", -- "nobody" | "group" | "groupGuild" | "anyone"
		announce = true, -- send a hello to the group so others see who runs Dungeon Planner
		replyHello = true,
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
	showLegend = nil, -- nil: shown the first time the map opens, then hidden until the Legend button shows it
	legendSeen = false,
	homeSelected = nil, -- the instance selected in the home table (its key)
	step = nil, -- the current step: { plan = id, index = n } (Model/Steps.lua)
	run = {}, -- run mode window: { point, shown }
	notes = { width = 300, height = 240 }, -- the Notes window: { point, width, height }
	partyMode = "assignments", -- the Party section: "assignments" | "pages"
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
