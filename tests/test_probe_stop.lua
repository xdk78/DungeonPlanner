-- /dp perf start and stop driven the way the game drives them: through ns.SafeCall (Slash.Init wraps every command in
-- it), which the probe swaps while it runs. The stop command is itself a timed call that ends after the probe stopped.
local T = ...
local ns, mock = T.ns, T.mock
local Perf = ns.Perf

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("Perf: stopping from a command leaves the depth at 0 and records nothing after the stop", function()
	boot()
	Perf.Reset()
	ns.SafeCall(ns.Slash.Handle, "perf start") -- the original SafeCall: the probe starts inside it
	T.ok(Perf.IsRunning())
	ns.SafeCall(function() end) -- a timed top-level call
	ns.SafeCall(ns.Slash.Handle, "perf stop") -- timed, and it stops the probe in the middle of itself
	T.ok(not Perf.IsRunning())
	T.eq(Perf.Depth(), 0, "the stop command did not take the depth below 0")
	local text = table.concat(Perf.Summary(), "\n")
	T.ok(text:find("callback (SafeCall): 1 calls", 1, true), "only the call made while running is counted: " .. text)
	-- Starting again from a clean depth works, and an old call ending after the restart does not count either.
	Perf.Reset()
	Perf.Start()
	T.eq(Perf.Depth(), 0)
	ns.SafeCall(function() end)
	T.ok(table.concat(Perf.Summary(), "\n"):find("callback (SafeCall): 1 calls", 1, true))
	Perf.Stop()
	Perf.Reset()
end)
