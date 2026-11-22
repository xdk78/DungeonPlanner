-- Review fixes: the name scrub (realm forms, case, short names, group, guild, plans), error-handler isolation, What's new
-- across sessions and downgrades, and the Discord form's hard limit.
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

T.case("Scrub: realm in its display and normalized forms, any case, short names, group, guild and plan names", function()
	boot()
	local oldRealm = mock.realm
	mock.realm = "Area 52"
	_G.GetNormalizedRealmName = function()
		return "Area52"
	end
	_G.GetGuildInfo = function()
		return "Zzguild"
	end
	mock.units.party1 = { name = "Bo" }
	mock.units.raid7 = { name = "Zzfriend" }
	local plan = ns.Plan.New({ name = "Zzplanname" })
	ns.DB.AddPlan(plan)
	local ok, err = pcall(function()
		local text = ns.Errors.Scrub("boom Tester-Area52 on Area 52, AREA52 and area 52; tester said Bo went to Boston with "
			.. "ZZFRIEND of <Zzguild> in zzplanname")
		for _, secret in ipairs({ "tester", "area 52", "area52", "zzfriend", "zzguild", "zzplanname" }) do
			T.ok(not text:lower():find(secret, 1, true), secret .. " is still in: " .. text)
		end
		T.ok(not text:find("Bo went", 1, true) and text:find("Boston", 1, true), "a short name goes, whole words only: " .. text)
		T.ok(text:find("<name>-<name>", 1, true), text)
		-- The same through the report: errors, log and the player's own words.
		ns.Errors.Clear()
		ns.Errors.Record("failed for Tester in Area 52")
		local report = Report.Text(Report.Collect(), "I am Tester from Zzguild, my plan Zzplanname broke")
		for _, secret in ipairs({ "tester", "area 52", "zzguild", "zzplanname" }) do
			T.ok(not report:lower():find(secret, 1, true), secret .. " leaked into the report:\n" .. report)
		end
		T.ok(not Report.IssueURL(Report.Collect(), "Tester Zzguild"):find("Tester", 1, true), "and not into the link")
	end)
	ns.DB.DeletePlan(plan.id)
	mock.realm, mock.units.party1, mock.units.raid7 = oldRealm, nil, nil
	_G.GetNormalizedRealmName, _G.GetGuildInfo = nil, nil
	ns.Errors.Clear()
	T.ok(ok, err)
end)

T.case("SafeCall: a failing error handler or failing bookkeeping never escapes", function()
	boot()
	ns.Errors.Clear()
	local oldHandler, oldClock = _G.geterrorhandler, ns.Clock
	local raised = 0
	local ok, err = pcall(function()
		_G.geterrorhandler = function()
			return function()
				error("the error addon is broken")
			end
		end
		local good = ns.SafeCall(function()
			error("first")
		end)
		T.eq(good, false, "SafeCall returns normally")
		-- Bookkeeping (the clock) fails: the error still goes to the handler.
		_G.geterrorhandler = function()
			return function()
				raised = raised + 1
			end
		end
		ns.Clock = function()
			error("no clock")
		end
		ns.SafeCall(function()
			error("second")
		end)
		T.eq(raised, 1)
	end)
	_G.geterrorhandler, ns.Clock = oldHandler, oldClock
	ns.Errors.Clear()
	T.ok(ok, err)
end)

T.case("Blocked actions: a failing debugstack gives an unknown location, not an error", function()
	boot()
	ns.Errors.Clear()
	_G.debugstack = function()
		error("no stack")
	end
	mock.FireEvent("ADDON_ACTION_BLOCKED", "DungeonPlanner", "SetCVar")
	_G.debugstack = nil
	T.eq(ns.Errors.list[1].message, "blocked: SetCVar at location unknown")
	ns.Errors.Clear()
end)

T.case("What's new: a downgrade shows nothing and keeps the newer version", function()
	boot()
	T.eq(WN.Decide("0.3.0", "0.2.0", false, true), nil)
	local oldVersion, oldAdb, oldFresh = ns.version, ns.adb, ns.freshInstall
	ns.version, ns.freshInstall = "0.2.0", false
	ns.adb = { global = { news = { seen = "0.3.0" } } }
	local ok, err = pcall(function()
		T.eq(WN.Check(), nil)
		T.eq(ns.adb.global.news.seen, "0.3.0", "not lowered")
	end)
	ns.version, ns.adb, ns.freshInstall = oldVersion, oldAdb, oldFresh
	T.ok(ok, err)
end)

T.case("What's new: saved only after Show succeeds; a first install keeps its welcome across sessions", function()
	boot()
	local oldVersion, oldAdb, oldFresh, oldShow = ns.version, ns.adb, ns.freshInstall, ns.NewsFrame.Show
	local oldInstance = _G.IsInInstance
	_G.IsInInstance = function()
		return false, "none"
	end
	for _, name in ipairs({ "DungeonPlannerMainFrame", "DungeonPlannerRunFrame", "DungeonPlannerNotesFrame", "DungeonPlannerReportFrame",
		"DungeonPlannerNewsFrame", "DungeonPlannerDialog" }) do
		local f = rawget(_G, name)
		if f and f.IsShown and f:IsShown() then
			f:Hide()
		end
	end
	local works = false
	ns.NewsFrame.Show = function()
		return works
	end
	local ok, err = pcall(function()
		ns.version, ns.freshInstall = "0.2.0", true
		ns.adb = { global = {} }
		-- The card cannot be built: nothing saved, still pending.
		T.eq(WN.Check(), "welcome")
		T.eq(ns.adb.global.news.seen, nil, "not saved: it never showed")
		T.eq(WN.IsPending(), "welcome")
		T.eq(ns.adb.global.news.firstRun, true, "remembered as a first install")
		-- The next session: not a fresh install any more (data exists), the welcome is still owed.
		WN.TryShow()
		T.eq(WN.IsPending(), "welcome")
		ns.freshInstall = false
		works = true
		T.eq(WN.Check(), "welcome", "a later session still shows the welcome")
		T.eq(ns.adb.global.news.seen, "0.2.0")
		T.eq(ns.adb.global.news.firstRun, nil)
		T.eq(WN.IsPending(), nil)
		T.eq(WN.Check(), nil, "and once")
	end)
	_G.IsInInstance, ns.NewsFrame.Show = oldInstance, oldShow
	ns.version, ns.adb, ns.freshInstall = oldVersion, oldAdb, oldFresh
	T.ok(ok, err)
end)

T.case("Report for Discord: words that cannot fit are cut with an ellipsis so the total is at most 2000", function()
	boot()
	ns.Errors.Clear()
	for i = 1, 10 do
		ns.Errors.Record("error " .. i .. " " .. string.rep("x", 200))
	end
	local data = Report.Collect()
	-- As long as the limit itself: too long whatever the core facts say (their length depends on the session's state).
	local words = string.rep("\196\133", Report.DISCORD_LIMIT)
	local text = Report.Text(data, words, { limit = Report.DISCORD_LIMIT })
	T.ok(Report.CharCount(text) <= Report.DISCORD_LIMIT, Report.CharCount(text))
	T.ok(text:find("\226\128\166", 1, true), "the words end with an ellipsis")
	T.ok(text:find(string.rep("\196\133", 50), 1, true), "and keep their start")
	T.ok(text:find("Addon: ", 1, true), "the core facts stay")
	-- Words that fit are never cut.
	local short = Report.Text(data, string.rep("\196\133", 300), { limit = Report.DISCORD_LIMIT })
	T.ok(short:find(string.rep("\196\133", 300), 1, true) and not short:find("\226\128\166", 1, true))
	ns.Errors.Clear()
end)
