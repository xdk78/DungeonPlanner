-- The gamepad interface style (Core/Compat.lua Gamepad): with it on, registering a slash command freezes the client
-- and the gamepad menus close the frames in UISpecialFrames, so Dungeon Planner registers no slash command and touches
-- no UISpecialFrames; with it off, both work as before. Detected from C_InputInterfaceStyle, else the CVar.
local T = ...
local ns = T.ns

local function withGlobals(set, fn)
	local saved = {}
	for k, v in pairs(set) do
		saved[k] = rawget(_G, k)
		rawset(_G, k, v)
	end
	ns.Compat.ResetGamepad()
	local ok, err = pcall(fn)
	for k in pairs(set) do
		rawset(_G, k, saved[k])
	end
	ns.Compat.ResetGamepad()
	assert(ok, err)
end

local GAMEPAD = 1
local enum = setmetatable({ InputInterfaceStyle = { KeyboardAndMouse = 0, Gamepad = GAMEPAD } },
	{ __index = rawget(_G, "Enum") })

local function registrations(fn)
	local addon = ns.addon
	local real, n = addon.RegisterChatCommand, 0
	addon.RegisterChatCommand = function()
		n = n + 1
	end
	local before = #(rawget(_G, "UISpecialFrames") or {})
	local ok, err = pcall(fn)
	addon.RegisterChatCommand = real
	assert(ok, err)
	return n, #(rawget(_G, "UISpecialFrames") or {}) - before
end

T.case("Gamepad style on: no slash command, nothing in UISpecialFrames, /dp debug says so", function()
	withGlobals({ C_InputInterfaceStyle = { GetCurrentStyle = function()
		return GAMEPAD
	end }, Enum = enum, UISpecialFrames = rawget(_G, "UISpecialFrames") or {} }, function()
		local on, how = ns.Compat.Gamepad()
		T.eq(on, true, "detected")
		T.eq(how, "api")
		local slashes, special = registrations(function()
			ns.Slash.Init()
			T.eq(ns.Widgets.AddSpecialFrame("DungeonPlannerTest"), false, "refused")
		end)
		T.eq(slashes, 0, "no slash command registered")
		T.eq(special, 0, "UISpecialFrames untouched")
		T.eq(ns.Slash.registered, false)
		local lines = {}
		local realPrint = print
		_G.print = function(text)
			lines[#lines + 1] = tostring(text)
		end
		local ok = pcall(ns.Slash.Debug)
		_G.print = realPrint
		T.ok(ok, "debug runs")
		local said = false
		for _, l in ipairs(lines) do
			said = said or l:find("Gamepad interface style: on", 1, true) ~= nil
		end
		T.ok(said, "/dp debug reports it")
	end)
end)

T.case("Gamepad style from the CVar when the API is missing; off: everything registers as before", function()
	withGlobals({ C_InputInterfaceStyle = false, Enum = enum, GetCVar = function(name)
		return name == "InputDeviceInterfaceStyle" and "1" or nil
	end, C_CVar = false }, function()
		local on, how = ns.Compat.Gamepad()
		T.eq(on, true, "the CVar says gamepad")
		T.eq(how, "cvar")
	end)
	withGlobals({ C_InputInterfaceStyle = { GetCurrentStyle = function()
		return 0
	end }, Enum = enum, UISpecialFrames = {} }, function()
		T.eq(ns.Compat.Gamepad(), false, "keyboard and mouse")
		local slashes, special = registrations(function()
			ns.Slash.Init()
			T.eq(ns.Widgets.AddSpecialFrame("DungeonPlannerTest"), true)
		end)
		T.eq(slashes, 2, "/dp and /dplan")
		T.eq(special, 1)
	end)
	-- A client that raises: off, nothing breaks.
	withGlobals({ C_InputInterfaceStyle = { GetCurrentStyle = function()
		error("blocked")
	end }, Enum = enum, GetCVar = false, C_CVar = false }, function()
		T.eq(ns.Compat.Gamepad(), false)
	end)
end)

T.case("Gamepad style: the CVar is read only against the game's own value; the setting overrides detection", function()
	local cvar = function(name)
		return name == "InputDeviceInterfaceStyle" and "1" or nil
	end
	-- Without Enum.InputInterfaceStyle, "1" means nothing known: not guessed.
	withGlobals({ C_InputInterfaceStyle = false, Enum = {}, GetCVar = cvar, C_CVar = false }, function()
		local on, how = ns.Compat.Gamepad()
		T.eq(on, false, "no guess")
		T.eq(how, "none")
	end)
	-- The game's value is not the CVar's: off.
	withGlobals({ C_InputInterfaceStyle = false, GetCVar = cvar, C_CVar = false,
		Enum = { InputInterfaceStyle = { KeyboardAndMouse = 0, Gamepad = 2 } } }, function()
		T.eq(ns.Compat.Gamepad(), false, "1 is not the gamepad value here")
	end)
	T.eq(ns.Defaults.settings.gamepad, "auto", "automatic by default")
	if not ns.db then
		T.freshDB() -- run alone (lua tests/run.lua Gamepad): no addon boot before this file
	end
	local settings = ns.db.settings
	local saved = settings.gamepad
	local ok, err = pcall(function()
		withGlobals({ C_InputInterfaceStyle = { GetCurrentStyle = function()
			return GAMEPAD
		end }, Enum = enum }, function()
			settings.gamepad = "off"
			ns.Compat.ResetGamepad()
			local on, how = ns.Compat.Gamepad()
			T.eq(on, false, "the setting says off")
			T.eq(how, "setting")
			settings.gamepad = "auto"
			ns.Compat.ResetGamepad()
			T.eq(ns.Compat.Gamepad(), true, "automatic: detected")
		end)
		withGlobals({ C_InputInterfaceStyle = false, Enum = {}, GetCVar = false, C_CVar = false }, function()
			settings.gamepad = "on"
			ns.Compat.ResetGamepad()
			local on, how = ns.Compat.Gamepad()
			T.eq(on, true, "the setting says on, nothing detected")
			T.eq(how, "setting")
		end)
	end)
	settings.gamepad = saved
	ns.Compat.ResetGamepad()
	assert(ok, err)
end)
