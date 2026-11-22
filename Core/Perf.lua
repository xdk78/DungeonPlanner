-- /dp perf: an opt-in probe, free when off. Everything the addon runs for the game goes through three funnels in
-- Core/Init.lua: the event dispatcher (one AceEvent callback for every event we listen to), `ns:Fire` (the internal bus)
-- and `ns.SafeCall` (button clicks, timers, anything that must not break its caller). `/dp perf start` swaps those three
-- for timed versions and watches the frame rate; `/dp perf stop` puts the originals back. While it is off nothing is
-- wrapped and nothing runs: no OnUpdate, no ticker.
--
-- What it keeps (all bounded): per name the calls, total and own time (own = total minus the calls inside it, tracked
-- with a depth stack, so a redraw inside an event is not counted twice), the worst calls over SPIKE_MS in a ring of
-- SPIKE_MAX with what called them, per frame the time we used and its 3 slowest calls (frames that cost over SPIKE_MS), the
-- number of hitches (frames over HITCH_MS) and how many were ours. The probe's own per-call cost is measured at the start
-- and subtracted. Every 5 s it samples the game's addon profiler (C_AddOnProfiler), each call guarded; when the game's own
-- number is far above what we measured, the summary says some time is not seen here (an OnUpdate or a timer callback
-- that bypasses SafeCall).

local _, ns = ...
local Perf = ns:NewModule("Perf")

Perf.SPIKE_MS = 5
Perf.HITCH_MS = 50
Perf.SPIKE_MAX = 200
Perf.FRAME_MAX = 20
Perf.SAMPLE_EVERY = 5

local running = false
local startedAt
local stats, spikes, slowFrames = {}, {}, {}
local frames, hitches, hitchesOurs = 0, 0, 0
local frameSum, frameTop = 0, {} -- this frame: our time, and its 3 slowest top-level calls
local overhead = 0
local stack, depth = {}, 0
local profiler = {} -- the last sample of the game's profiler
local original = {} -- what the funnels were before the probe
local ticker, frame

-- Milliseconds. Tests replace Perf.clock.
function Perf.clock()
	if debugprofilestop then
		return debugprofilestop()
	end
	return os.clock() * 1000
end

function Perf.IsRunning()
	return running
end

function Perf.HasData()
	return next(stats) ~= nil or frames > 0
end

-- Timing ------------------------------------------------------------------------------------------------------------------

-- A call that began under one run of the probe and ends after it was stopped (or restarted) must not touch the books: a
-- slash command goes through the timed SafeCall, and `/dp perf stop` is such a call. Each entry carries the run's number.
local gen = 0

local function enter(name)
	depth = depth + 1
	local e = { name = name, t0 = Perf.clock(), child = 0, gen = gen }
	stack[depth] = e
	return e
end

local function leave(e, ...)
	if e.gen ~= gen or not running then
		return ...
	end
	local raw = Perf.clock() - e.t0
	stack[depth] = nil
	depth = depth - 1
	local total = math.max(0, raw - overhead)
	local own = math.max(0, raw - e.child - overhead)
	local parent = stack[depth]
	if parent then
		parent.child = parent.child + raw
	else
		frameSum = frameSum + total
		frameTop[#frameTop + 1] = { name = e.name, ms = total }
		table.sort(frameTop, function(a, b)
			return a.ms > b.ms
		end)
		frameTop[4] = nil
	end
	local s = stats[e.name]
	if not s then
		s = { calls = 0, total = 0, own = 0, max = 0, spikes = 0 }
		stats[e.name] = s
	end
	s.calls, s.total, s.own = s.calls + 1, s.total + total, s.own + own
	if total > s.max then
		s.max = total
	end
	if total > Perf.SPIKE_MS then
		s.spikes = s.spikes + 1
		spikes[#spikes + 1] = { name = e.name, ms = total, own = own, from = parent and parent.name or nil,
			at = (Perf.clock() - startedAt) / 1000 }
		if #spikes > Perf.SPIKE_MAX then
			table.remove(spikes, 1)
		end
	end
	return ...
end

-- One frame ended (the probe's OnUpdate): elapsed seconds since the last one.
function Perf.OnFrame(elapsed)
	frames = frames + 1
	local frameMs = (elapsed or 0) * 1000
	if frameMs > Perf.HITCH_MS then
		hitches = hitches + 1
		-- Ours when we used a quarter of that frame or the spike limit, whichever is less.
		if frameSum >= math.min(frameMs * 0.25, Perf.SPIKE_MS) then
			hitchesOurs = hitchesOurs + 1
		end
	end
	if frameSum > Perf.SPIKE_MS then
		slowFrames[#slowFrames + 1] = { ms = frameSum, frame = frameMs, top = frameTop }
		if #slowFrames > Perf.FRAME_MAX then
			table.remove(slowFrames, 1)
		end
	end
	frameSum, frameTop = 0, {}
end

-- The game's profiler, every few seconds while running: each call guarded.
local function metricsOf()
	local api, enum = rawget(_G, "C_AddOnProfiler"), rawget(_G, "Enum")
	local metrics = type(enum) == "table" and enum.AddOnProfilerMetric
	if type(api) ~= "table" or type(api.GetAddOnMetric) ~= "function" or type(metrics) ~= "table" then
		return nil
	end
	return api, metrics
end

local function sample()
	local api, metrics = metricsOf()
	if not api then
		return
	end
	local function metric(key)
		local ok, v = pcall(api.GetAddOnMetric, ns.name, metrics[key])
		v = ok and ns.Util.Plain(v) or nil
		return type(v) == "number" and v or nil
	end
	profiler.last, profiler.recent, profiler.peak = metric("LastTime"), metric("RecentAverageTime"), metric("PeakTime")
	profiler.over = {}
	for _, ms in ipairs({ 5, 10, 50, 100 }) do
		profiler.over[ms] = metric("CountTimeOver" .. ms .. "Ms")
	end
	if type(api.IsEnabled) == "function" then
		local ok, v = pcall(api.IsEnabled)
		profiler.enabled = ok and v or nil
	end
	if type(api.GetOverallMetric) == "function" and type(metrics.RecentAverageTime) ~= "nil" then
		local ok, v = pcall(api.GetOverallMetric, metrics.RecentAverageTime)
		v = ok and ns.Util.Plain(v) or nil
		profiler.overall = type(v) == "number" and v or nil
	end
end
Perf.Sample = sample

-- Per call overhead of the probe itself, ms.
local function measureOverhead()
	if Perf.fixedOverhead then
		return Perf.fixedOverhead
	end
	local n = 200
	local t0 = Perf.clock()
	for _ = 1, n do
		local e = enter("calibrate")
		leave(e)
	end
	local per = (Perf.clock() - t0) / n
	stats.calibrate, spikes, frameSum, frameTop = nil, {}, 0, {}
	return per
end

-- Start and stop ---------------------------------------------------------------------------------------------------------

function Perf.Start()
	if running then
		return false
	end
	running = true
	gen = gen + 1
	stack, depth = {}, 0
	startedAt = Perf.clock()
	overhead = 0
	overhead = measureOverhead()
	-- 1. Events: the one dispatcher AceEvent calls, registered again with a timed version.
	original.dispatch = ns.EventDispatcher()
	original.events = {}
	local function timedDispatch(event, ...)
		local e = enter("event: " .. tostring(event))
		return leave(e, original.dispatch(event, ...))
	end
	for event in pairs(ns.EventTable()) do
		if ns.addon and pcall(ns.addon.RegisterEvent, ns.addon, event, timedDispatch) then
			original.events[#original.events + 1] = event
		end
	end
	-- 2. The bus.
	original.fire = ns.Fire
	ns.Fire = function(self, message, ...)
		local e = enter("message: " .. tostring(message))
		return leave(e, original.fire(self, message, ...))
	end
	-- 3. SafeCall: top-level calls only (those inside an event or a message are inside it already).
	original.safeCall = ns.SafeCall
	ns.SafeCall = function(fn, ...)
		if depth > 0 then
			return original.safeCall(fn, ...)
		end
		local e = enter("callback (SafeCall)")
		return leave(e, original.safeCall(fn, ...))
	end
	-- Frames: an OnUpdate for as long as the probe runs.
	if CreateFrame then
		frame = frame or CreateFrame("Frame")
		frame:SetScript("OnUpdate", function(_, elapsed)
			Perf.OnFrame(elapsed)
		end)
		frame:Show()
	end
	if C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(Perf.SAMPLE_EVERY, sample)
	end
	sample()
	ns.Log("perf probe started")
	return true
end

function Perf.Stop()
	if not running then
		return false
	end
	for _, event in ipairs(original.events or {}) do
		pcall(ns.addon.RegisterEvent, ns.addon, event, original.dispatch)
	end
	ns.Fire, ns.SafeCall = original.fire, original.safeCall
	original = {}
	if frame then
		frame:SetScript("OnUpdate", nil)
		frame:Hide()
	end
	if ticker and ticker.Cancel then
		ticker:Cancel()
	end
	ticker = nil
	stack, depth = {}, 0
	gen = gen + 1 -- calls still on the stack (this one, when a command ran it) end without a record
	running = false
	ns.Log("perf probe stopped")
	return true
end

function Perf.Reset()
	stats, spikes, slowFrames = {}, {}, {}
	frames, hitches, hitchesOurs, frameSum, frameTop = 0, 0, 0, 0, {}
	profiler = {}
	if running then
		startedAt = Perf.clock()
	end
end

-- Report -----------------------------------------------------------------------------------------------------------------

-- Memory from the addon memory call, guarded: { memoryKB? }.
function Perf.Memory()
	local out = {}
	local addons = rawget(_G, "C_AddOns")
	local update = addons and addons.UpdateAddOnMemoryUsage or rawget(_G, "UpdateAddOnMemoryUsage")
	local usage = addons and addons.GetAddOnMemoryUsage or rawget(_G, "GetAddOnMemoryUsage")
	if type(usage) == "function" then
		if type(update) == "function" then
			pcall(update)
		end
		local ok, kb = pcall(usage, ns.name)
		kb = ok and ns.Util.Plain(kb) or nil
		if type(kb) == "number" then
			out.memoryKB = kb
		end
	end
	return out
end

local function ms(v)
	return string.format("%.2f", v)
end

-- A short plain-text summary, for chat and the report window: lines.
function Perf.Summary(top)
	top = top or 12
	local lines = {}
	local state = running and string.format("running for %d s", math.floor((Perf.clock() - startedAt) / 1000))
		or (Perf.HasData() and "stopped" or "off")
	lines[#lines + 1] = "Perf probe: " .. state .. " (spike: a call over " .. Perf.SPIKE_MS .. " ms; hitch: a frame over "
		.. Perf.HITCH_MS .. " ms)"
	local bits = {}
	local mem = Perf.Memory()
	if mem.memoryKB then
		bits[#bits + 1] = string.format("memory %.1f MB", mem.memoryKB / 1024)
	end
	if profiler.recent then
		bits[#bits + 1] = "profiler recent avg " .. ms(profiler.recent) .. " ms"
	end
	if profiler.last then
		bits[#bits + 1] = "last " .. ms(profiler.last)
	end
	if profiler.peak then
		bits[#bits + 1] = "peak " .. ms(profiler.peak)
	end
	if profiler.over then
		local over = {}
		for _, limit in ipairs({ 5, 10, 50, 100 }) do
			if profiler.over[limit] then
				over[#over + 1] = ">" .. limit .. " ms: " .. profiler.over[limit]
			end
		end
		if #over > 0 then
			bits[#bits + 1] = "frames " .. table.concat(over, ", ")
		end
	end
	if profiler.enabled == false then
		bits[#bits + 1] = "the game's profiler is switched off"
	end
	lines[#lines + 1] = #bits > 0 and table.concat(bits, ", ") or "memory and profiler: not available on this client"
	if frames > 0 then
		local ours = 0
		for _, s in pairs(stats) do
			ours = ours + s.own
		end
		lines[#lines + 1] = string.format("%d frames watched, %d hitches (%d ours), our time per frame %s ms", frames, hitches,
			hitchesOurs, ms(ours / frames))
		if profiler.recent and profiler.recent > (ours / frames) * 2 + 1 then
			lines[#lines + 1] = "note: the game's profiler sees more time than was measured here: an OnUpdate or a timer callback outside SafeCall"
		end
	end
	local names = {}
	for name in pairs(stats) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		if stats[a].own ~= stats[b].own then
			return stats[a].own > stats[b].own
		end
		return a < b
	end)
	for i = 1, math.min(#names, top) do
		local s = stats[names[i]]
		lines[#lines + 1] = string.format("  %s: %d calls, own %s ms, total %s ms, avg %s, max %s, spikes %d", names[i], s.calls,
			ms(s.own), ms(s.total), ms(s.total / s.calls), ms(s.max), s.spikes)
	end
	if #names > top then
		lines[#lines + 1] = string.format("  (+%d more)", #names - top)
	end
	for i = math.max(1, #spikes - 4), #spikes do -- the last few; the ring keeps more
		local sp = spikes[i]
		lines[#lines + 1] = string.format("  spike: %s %s ms (own %s)%s at +%d s", sp.name, ms(sp.ms), ms(sp.own),
			sp.from and (" inside " .. sp.from) or "", math.floor(sp.at))
	end
	local worst = slowFrames[#slowFrames]
	if worst then
		local calls = {}
		for _, c in ipairs(worst.top) do
			calls[#calls + 1] = c.name .. " " .. ms(c.ms)
		end
		lines[#lines + 1] = string.format("  slowest recent frame: ours %s ms of %s ms: %s", ms(worst.ms), ms(worst.frame),
			table.concat(calls, "; "))
	end
	return lines
end

-- For tests: the depth of the call stack the probe tracks.
function Perf.Depth()
	return depth
end

-- For tests: how many spikes the ring holds.
function Perf.SpikeCount()
	return #spikes
end

-- /dp perf [start|stop|reset]
function Perf.Command(arg)
	local L = ns.L
	if arg == "start" then
		ns:Print(Perf.Start() and L["Perf probe started. Use the addon as usual, then /dp perf to read it and /dp perf stop to end it."]
			or L["The perf probe is already running."])
	elseif arg == "stop" then
		ns:Print(Perf.Stop() and L["Perf probe stopped; its numbers stay until /dp perf reset."] or L["The perf probe is not running."])
	elseif arg == "reset" then
		Perf.Reset()
		ns:Print(L["Perf numbers cleared."])
	else
		for _, line in ipairs(Perf.Summary()) do
			print(line)
		end
		if not running and not Perf.HasData() then
			ns:Print(L["Start it with /dp perf start (off by default; stop it with /dp perf stop)."])
		end
	end
end
