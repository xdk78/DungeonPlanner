-- /dp perf (Core/Perf.lua): free when off, swaps the dispatcher, the bus and SafeCall while it runs, counts own and total
-- time without double counting nested calls, keeps bounded rings, sees hitches, and reads the game's profiler when there is
-- one.
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

-- A fake clock the test advances itself, and no probe overhead, so the numbers are exact.
local function fakeClock()
	local t = { now = 0, real = Perf.clock }
	Perf.clock = function()
		return t.now
	end
	Perf.fixedOverhead = 0
	function t.restore()
		Perf.clock, Perf.fixedOverhead = t.real, nil
	end
	return t
end

T.case("Perf: off by default; start swaps the dispatcher, the bus and SafeCall, stop puts them back", function()
	boot()
	T.ok(not Perf.IsRunning() and not Perf.HasData())
	local fire, safe, dispatcher = ns.Fire, ns.SafeCall, ns.EventDispatcher()
	T.ok(Perf.Start())
	T.ok(not Perf.Start(), "already running")
	T.ok(ns.Fire ~= fire and ns.SafeCall ~= safe, "timed versions in place")
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	local text = table.concat(Perf.Summary(), "\n")
	T.ok(text:find("event: PLAYER_REGEN_ENABLED", 1, true), text)
	T.ok(Perf.Stop())
	T.eq(ns.Fire, fire)
	T.eq(ns.SafeCall, safe)
	T.eq(ns.EventDispatcher(), dispatcher)
	local before = table.concat(Perf.Summary(), "\n")
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.eq(table.concat(Perf.Summary(), "\n"), before, "nothing is counted after stop")
	Perf.Reset()
	T.ok(not Perf.HasData())
end)

T.case("Perf: own time is total minus the calls inside it; spikes name what called them", function()
	boot()
	local clock = fakeClock()
	local owner = {}
	ns:On("PERF_OUTER", owner, function()
		clock.now = clock.now + 2
		ns:Fire("PERF_INNER")
	end)
	ns:On("PERF_INNER", owner, function()
		clock.now = clock.now + 7
	end)
	Perf.Start()
	ns:Fire("PERF_OUTER")
	local text = table.concat(Perf.Summary(), "\n")
	Perf.Stop()
	clock.restore()
	ns:Off("PERF_OUTER", owner)
	ns:Off("PERF_INNER", owner)
	T.ok(text:find("message: PERF_OUTER: 1 calls, own 2.00 ms, total 9.00 ms", 1, true), text)
	T.ok(text:find("message: PERF_INNER: 1 calls, own 7.00 ms, total 7.00 ms", 1, true), text)
	T.ok(text:find("spike: message: PERF_INNER 7.00 ms (own 7.00) inside message: PERF_OUTER", 1, true), text)
	Perf.Reset()
end)

T.case("Perf: the probe's own per-call cost is subtracted", function()
	boot()
	local clock = fakeClock()
	Perf.fixedOverhead = 0.5
	local owner = {}
	ns:On("PERF_COST", owner, function()
		clock.now = clock.now + 4 -- 3.5 ms of work, and the 0.5 ms the probe itself costs a call
	end)
	Perf.Start()
	ns:Fire("PERF_COST")
	local text = table.concat(Perf.Summary(), "\n")
	Perf.Stop()
	clock.restore()
	ns:Off("PERF_COST", owner)
	T.ok(text:find("message: PERF_COST: 1 calls, own 3.50 ms", 1, true), text)
	Perf.Reset()
end)

T.case("Perf: frames, hitches and the ones that were ours; the slowest frame's calls", function()
	boot()
	local clock = fakeClock()
	local owner = {}
	ns:On("PERF_WORK", owner, function()
		clock.now = clock.now + 12
	end)
	Perf.Start()
	ns:Fire("PERF_WORK")
	Perf.OnFrame(0.2) -- a 200 ms frame in which we used 12 ms: ours
	Perf.OnFrame(0.2) -- another, with nothing of ours in it
	Perf.OnFrame(0.016)
	local text = table.concat(Perf.Summary(), "\n")
	Perf.Stop()
	clock.restore()
	ns:Off("PERF_WORK", owner)
	T.ok(text:find("3 frames watched, 2 hitches (1 ours)", 1, true), text)
	T.ok(text:find("slowest recent frame: ours 12.00 ms of 200.00 ms: message: PERF_WORK 12.00", 1, true), text)
	Perf.Reset()
end)

T.case("Perf: the spike ring is bounded", function()
	boot()
	local clock = fakeClock()
	local owner = {}
	ns:On("PERF_SLOW", owner, function()
		clock.now = clock.now + 6
	end)
	Perf.Start()
	for _ = 1, Perf.SPIKE_MAX + 50 do
		ns:Fire("PERF_SLOW")
	end
	T.eq(Perf.SpikeCount(), Perf.SPIKE_MAX)
	Perf.Stop()
	clock.restore()
	ns:Off("PERF_SLOW", owner)
	Perf.Reset()
end)

T.case("Perf: top-level SafeCall callbacks are counted, nested ones only inside their parent", function()
	boot()
	Perf.Start()
	ns.SafeCall(function() end)
	local text = table.concat(Perf.Summary(), "\n")
	Perf.Stop()
	T.ok(text:find("callback (SafeCall): 1 calls", 1, true), text)
	Perf.Reset()
end)

T.case("Perf: the game's profiler and memory, guarded; a profiler that sees more says so", function()
	boot()
	_G.Enum = _G.Enum or {}
	local oldEnum = _G.Enum.AddOnProfilerMetric
	_G.Enum.AddOnProfilerMetric = { LastTime = 1, RecentAverageTime = 2, PeakTime = 3, CountTimeOver5Ms = 4, CountTimeOver10Ms = 5,
		CountTimeOver50Ms = 6, CountTimeOver100Ms = 7 }
	_G.C_AddOnProfiler = {
		IsEnabled = function()
			return true
		end,
		GetAddOnMetric = function(_, metric)
			return metric == 2 and 20 or metric * 1.5
		end,
		GetOverallMetric = function()
			return 3
		end,
	}
	_G.GetAddOnMemoryUsage = function()
		return 2048
	end
	Perf.Start()
	Perf.OnFrame(0.016)
	local text = table.concat(Perf.Summary(), "\n")
	Perf.Stop()
	_G.Enum.AddOnProfilerMetric, _G.C_AddOnProfiler, _G.GetAddOnMemoryUsage = oldEnum, nil, nil
	T.ok(text:find("memory 2.0 MB", 1, true), text)
	T.ok(text:find("profiler recent avg 20.00 ms", 1, true), text)
	T.ok(text:find("frames >5 ms: 6", 1, true), text)
	T.ok(text:find("an OnUpdate or a timer callback outside SafeCall", 1, true), text)
	Perf.Reset()
	T.ok(table.concat(Perf.Summary(), "\n"):find("not available on this client", 1, true), "no profiler, no memory call: said so")
end)

T.case("Perf: /dp perf start, stop and reset, and the report carries the numbers", function()
	boot()
	ns.Slash.Handle("perf start")
	T.ok(Perf.IsRunning())
	ns.Fire(ns, "PERF_ANY")
	ns.Slash.Handle("perf")
	ns.Slash.Handle("perf stop")
	T.ok(not Perf.IsRunning())
	T.ok(ns.Report.Text(ns.Report.Collect(), ""):find("Perf probe: stopped", 1, true))
	ns.Slash.Handle("perf reset")
	T.ok(not Perf.HasData())
end)
