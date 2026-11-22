-- The report's further facts and limits (Core/Report.lua, Core/Init.lua): blocked actions, the throttled re-raise, the
-- log ring, the settings diff, the input style, the Discord budget and the link's length; and the What's new card's quiet
-- moment gating (Core/WhatsNew.lua).
local T = ...
local ns, mock = T.ns, T.mock
local Report, WN = ns.Report, ns.WhatsNew

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("SafeCall: the same error reaches the game's handler once in 30 s; the ring keeps every count", function()
	boot()
	ns.Errors.Clear()
	local old, raised = _G.geterrorhandler, 0
	_G.geterrorhandler = function()
		return function()
			raised = raised + 1
		end
	end
	local function boom()
		error("same every time")
	end
	local function other()
		error("another one")
	end
	local ok, err = pcall(function()
		for _ = 1, 3 do
			ns.SafeCall(boom)
		end
		T.eq(raised, 1, "once")
		ns.SafeCall(other)
		T.eq(raised, 2, "a different message goes through")
		mock.Advance(31)
		ns.SafeCall(boom)
		T.eq(raised, 3, "and again after 30 s")
	end)
	_G.geterrorhandler = old
	T.ok(ok, err)
	T.eq(ns.Errors.list[#ns.Errors.list].count, 4, "the ring counts every time, raised or not")
	ns.Errors.Clear()
end)

T.case("Blocked actions: ADDON_ACTION_BLOCKED and _FORBIDDEN for us are recorded with where they happened", function()
	boot()
	ns.Errors.Clear()
	_G.debugstack = function()
		return "[C]: in function `SetCVar'\nInterface\\AddOns\\DungeonPlanner\\UI\\Foo.lua:12: in function `Apply'\nOther.lua:1: in main chunk"
	end
	mock.FireEvent("ADDON_ACTION_BLOCKED", "DungeonPlanner", "SetCVar")
	mock.FireEvent("ADDON_ACTION_FORBIDDEN", "DungeonPlanner", "ClearTarget")
	mock.FireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "SetCVar")
	_G.debugstack = function()
		return "[C]: in function `SetBinding'\nBlizzard_X.lua:5: in function `Run'"
	end
	mock.FireEvent("ADDON_ACTION_BLOCKED", "DungeonPlanner", "SetBinding")
	_G.debugstack = nil
	mock.FireEvent("ADDON_ACTION_BLOCKED", "DungeonPlanner", "Nothing")
	local list = {}
	for _, e in ipairs(ns.Errors.list) do
		list[#list + 1] = e.message
	end
	T.eq(#list, 4, table.concat(list, " | "))
	T.eq(list[1], "blocked: SetCVar at DungeonPlanner\\UI\\Foo.lua:12: in function `Apply'")
	T.ok(list[2]:find("^forbidden: ClearTarget at DungeonPlanner"), list[2])
	T.eq(list[3], "blocked: SetBinding at via [C]: in function `SetBinding'")
	T.eq(list[4], "blocked: Nothing at location unknown")
	T.ok(Report.Text(Report.Collect(), ""):find("blocked: SetCVar", 1, true), "the report shows them under the errors")
	ns.Errors.Clear()
end)

T.case("Log: a bounded ring; the report shows the last five lines", function()
	boot()
	for i = 1, 260 do
		ns.Log("line " .. i .. " by Tester")
	end
	local all = ns.LogLines(1000)
	T.eq(#all, 200)
	T.eq(all[#all].text, "line 260 by <name>")
	local text = Report.Text(Report.Collect(), "")
	T.ok(text:find("Log (last 5):", 1, true) and text:find("line 256 by <name>", 1, true), text)
	T.ok(not text:find("line 255 by", 1, true))
end)

T.case("Settings: only what differs from the defaults; a profile named after a character is 'custom'", function()
	boot()
	local s = ns.db.settings
	local oldScale, oldTracker = s.scale, s.tracker.enabled
	s.scale, s.tracker.enabled = 1.2, false
	local oldAdb = ns.adb
	ns.adb = { GetCurrentProfile = function() return "Tester - Zxqrealm" end }
	local text = Report.Text(Report.Collect(), "")
	ns.adb = oldAdb
	s.scale, s.tracker.enabled = oldScale, oldTracker
	T.ok(text:find("Settings (profile custom, differing from the defaults): ", 1, true), text)
	T.ok(text:find("scale=1.2", 1, true) and text:find("tracker.enabled=false", 1, true), text)
	T.ok(not text:find("Zxqrealm", 1, true) and not text:find("Tester", 1, true))
	T.ok(not text:find("theme=", 1, true), "defaults are not listed")
	T.ok(Report.Text(Report.Collect(), ""):find("profile Default", 1, true) or not oldAdb.GetCurrentProfile)
end)

T.case("Input style: what the addon detected (Compat.Gamepad) and how: the setting, the API, the CVar or nothing", function()
	boot()
	_G.Enum = _G.Enum or {}
	local oldEnum, oldApi, oldGet, oldCVar = _G.Enum.InputInterfaceStyle, rawget(_G, "C_InputInterfaceStyle"),
		rawget(_G, "GetCVar"), rawget(_G, "C_CVar")
	local oldSetting = ns.db.settings.gamepad
	local function style()
		ns.Compat.ResetGamepad()
		return Report.InputStyle()
	end
	local ok, err = pcall(function()
		ns.db.settings.gamepad = "auto"
		_G.C_CVar = nil
		_G.Enum.InputInterfaceStyle = { Gamepad = 2, Mouse = 1 }
		_G.C_InputInterfaceStyle = { GetCurrentStyle = function() return 2 end }
		T.eq(style(), "gamepad (api)")
		_G.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
		T.eq(style(), "keyboard and mouse (api)")
		_G.C_InputInterfaceStyle = nil
		_G.GetCVar = function() return "2" end
		T.eq(style(), "gamepad (cvar)")
		_G.Enum.InputInterfaceStyle = nil
		T.eq(style(), "unknown (none)", "no enum value: the CVar is not guessed")
		_G.GetCVar = nil
		T.eq(style(), "unknown (none)")
		ns.db.settings.gamepad = "off"
		T.eq(style(), "keyboard and mouse (setting)")
		ns.db.settings.gamepad = "on"
		style()
		T.ok(Report.Text(Report.Collect(), ""):find("Input: gamepad (setting)", 1, true))
	end)
	ns.db.settings.gamepad = oldSetting
	_G.C_InputInterfaceStyle, _G.Enum.InputInterfaceStyle, _G.GetCVar, _G.C_CVar = oldApi, oldEnum, oldGet, oldCVar
	ns.Compat.ResetGamepad()
	assert(ok, err)
end)

T.case("Report for Discord: characters not bytes, the free text whole, details dropped in a fixed order", function()
	boot()
	T.eq(Report.CharCount("\196\133\196\133a"), 3)
	ns.Errors.Clear()
	for i = 1, 5 do
		ns.Errors.Record("error number " .. i .. " " .. string.rep("x", 150))
	end
	local data = Report.Collect()
	data.perf = { string.rep("p", 900) }
	local words = string.rep("\196\133", 400) .. " the whole story"
	local full = Report.Text(data, words)
	T.ok(Report.CharCount(full) > 2000, "the full report is longer than Discord allows")
	local short = Report.Text(data, words, { limit = Report.DISCORD_LIMIT })
	T.ok(Report.CharCount(short) <= 2000, Report.CharCount(short))
	T.ok(short:find(words, 1, true), "the player's words, whole")
	T.ok(short:find("Addon: ", 1, true) and short:find("Client: ", 1, true), "the core facts stay")
	T.ok(not short:find(string.rep("p", 900), 1, true), "perf goes first")
	T.ok(short:find("(left out to fit: ", 1, true), "it says what it left out")
	local left = short:match("%(left out to fit: ([^)]*)%)")
	T.ok(short:find("error number 5", 1, true) and left and not left:find("errors", 1, true), "errors go last: " .. tostring(left))
	-- Without words that large, less is dropped; a limit that fits drops nothing.
	T.ok(not Report.Text(data, "short", { limit = 100000 }):find("left out", 1, true))
	ns.Errors.Clear()
end)

T.case("Issue link: never longer than the cap, whatever the free text", function()
	boot()
	local data = Report.Collect()
	for _, what in ipairs({ "", "short", string.rep("word ", 200), string.rep("\196\133", 500), string.rep("&=? ", 300) }) do
		local url = Report.IssueURL(data, what)
		T.ok(#url <= Report.MAX_URL, #url .. " for " .. what:sub(1, 12))
		T.ok(url:find("^https://github%.com/xdk78/DungeonPlanner/issues/new%?template=bug_report%.yml&version="), url)
	end
end)

-- What's new: the quiet moment ---------------------------------------------------------------------------------------------

local function windowsClosed()
	for _, name in ipairs({ "DungeonPlannerMainFrame", "DungeonPlannerRunFrame", "DungeonPlannerNotesFrame",
		"DungeonPlannerReportFrame", "DungeonPlannerNewsFrame", "DungeonPlannerDialog" }) do
		local f = rawget(_G, name)
		if f and f.IsShown and f:IsShown() then
			f:Hide()
		end
	end
end

T.case("What's new: waits for a quiet moment (combat, instance, cinematic, our windows) and saves the version only when shown", function()
	boot()
	windowsClosed()
	local oldInstance = _G.IsInInstance
	_G.IsInInstance = function() return false, "none" end
	local oldVersion, oldAdb, oldFresh = ns.version, ns.adb, ns.freshInstall
	local shown = 0
	local oldShow = ns.NewsFrame.Show
	ns.NewsFrame.Show = function()
		shown = shown + 1
		return true
	end
	local ok, err = pcall(function()
		ns.version = "0.2.0"
		ns.adb, ns.freshInstall = { global = { news = { seen = "0.1.0" } } }, false
		-- In combat: decided, not shown, not saved.
		mock.inCombat = true
		T.eq(WN.Check(), "news")
		T.eq(shown, 0)
		T.eq(ns.adb.global.news.seen, "0.1.0", "not saved while it waits")
		T.eq(WN.IsPending(), "news")
		-- Combat ends: it shows, and only then is the version saved.
		mock.inCombat = false
		mock.FireEvent("PLAYER_REGEN_ENABLED")
		mock.Advance(4)
		T.eq(shown, 1, "pending " .. tostring(WN.IsPending()) .. " quiet " .. tostring((select(2, WN.Quiet()))))
		T.eq(ns.adb.global.news.seen, "0.2.0")
		T.eq(WN.IsPending(), nil)
		-- Inside an instance, in a cinematic, over our own window: not yet.
		ns.adb.global.news.seen = "0.1.0"
		_G.IsInInstance = function() return true, "party" end
		T.eq(WN.Check(), "news")
		T.eq(shown, 1, "inside an instance")
		_G.IsInInstance = function() return false, "none" end
		_G.InCinematic = function() return true end
		T.ok(not WN.TryShow() and shown == 1, "in a cinematic")
		_G.InCinematic = nil
		ns.UI.Show()
		T.ok(not WN.TryShow() and shown == 1, "over the planner window")
		windowsClosed()
		mock.FireEvent("CINEMATIC_STOP")
		mock.Advance(4)
		T.eq(shown, 2, "shown once the moment is quiet")
		T.eq(ns.adb.global.news.seen, "0.2.0")
	end)
	mock.inCombat = false
	_G.IsInInstance, _G.InCinematic = oldInstance, nil
	ns.NewsFrame.Show = oldShow
	ns.version, ns.adb, ns.freshInstall = oldVersion, oldAdb, oldFresh
	T.ok(ok, err)
end)

T.case("What's new: a note can name its Settings group, and the card offers to open it", function()
	boot()
	windowsClosed()
	ns.NewsFrame.Show("news", "0.2.0")
	local f = ns.NewsFrame.Frame()
	T.eq(f.settingsGroup, "routes")
	T.ok(f.settings:IsShown())
	local opened
	local old = ns.UI.OpenSettings
	ns.UI.OpenSettings = function(group)
		opened = group
	end
	mock.Click(f.settings)
	ns.UI.OpenSettings = old
	T.eq(opened, "routes")
	ns.NewsFrame.Show("welcome")
	T.ok(not f.settings:IsShown(), "the welcome has no settings note")
	f:Hide()
end)
