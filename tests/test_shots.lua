-- /dp shots (UI/Shots.lua) through LibUIShots-1.0 against the mock client: every step runs, a screenshot follows
-- each, the manifest lands in DungeonPlannerDB.shots, and the window is put back as it was.
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if ns.loggedIn then
		return
	end
	_G.DungeonPlannerDB = nil
	mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
	mock.loggedIn = true
	mock.FireEvent("PLAYER_LOGIN")
	mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
end

local function walk(seconds)
	for _ = 1, math.ceil(seconds / 0.1) do
		mock.Advance(0.1)
		if mock.shotPending then
			mock.shotPending = false
			mock.FireEvent("SCREENSHOT_SUCCEEDED")
		end
	end
end

T.case("/dp shots walks every view, saves the manifest and restores the window", function()
	boot()
	local shots = 0
	_G.Screenshot = function()
		shots = shots + 1
		mock.shotPending = true
	end
	ns.UI.GoHome("dungeons")
	if ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	local steps = ns.Shots.Steps()
	T.ok(#steps >= 12, "home, picker, sections, run mode, maps, debug, settings")
	ns.Slash.Handle("shots")
	T.ok(LibStub("LibUIShots-1.0"):IsRunning("DungeonPlanner"), "running")
	walk(#steps * 3 + 5)
	T.ok(not LibStub("LibUIShots-1.0"):IsRunning(), "finished")
	T.eq(shots, #steps, "one screenshot per step")
	local m = _G.DungeonPlannerDB.shots
	T.ok(m, "manifest saved")
	T.eq(#m.shots, #steps)
	T.eq(m.shots[1].name, "home: dungeons")
	T.ok(m.shots[1].date, "each shot has a time")
	T.eq(ns.db.ui.view, "home", "back on the home view")
	T.ok(not ns.UI.IsShown(), "the window is closed again, as it was")
	T.ok(not ns.RunMode.IsShown(), "run mode closed")
end)

T.case("/dp shots does not start in combat", function()
	boot()
	mock.inCombat = true
	ns.Slash.Handle("shots")
	mock.inCombat = false
	T.ok(not LibStub("LibUIShots-1.0"):IsRunning(), "not started")
end)
