-- /dp perf: an opt-in probe. Off by default and free when off: nothing here runs, and no handler is wrapped, until
-- `/dp perf start`. Start swaps each of our event handlers, bus listeners and main redraw functions for a thin wrapper
-- that times the call (debugprofilestop, in milliseconds), counts it and records the ones over SPIKE_MS; `/dp perf stop`
-- puts the originals back. The numbers stay for `/dp perf` and the report window (UI/ReportFrame.lua) until
-- `/dp perf reset`. Memory comes from C_AddOnProfiler and the addon memory call, each guarded.
--
-- Limits: a function another module copied into a local before the probe started is not seen (it keeps calling the
-- original); handlers registered while the probe runs are not wrapped; timings include the cost of what the handler
-- calls (a redraw inside an event is counted twice, once under each name).

local _, ns = ...
local Perf = ns:NewModule("Perf")

Perf.SPIKE_MS = 5
Perf.MAX_SPIKES = 10 -- spikes kept, newest last (bounded)

local running = false
local startedAt
local stats = {} -- [name] = { calls, total, max, spikes }
local spikes = {}
local undo = {} -- { restore function }

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
	return next(stats) ~= nil
end

local function record(name, t0, ...)
	local ms = Perf.clock() - t0
	local s = stats[name]
	if not s then
		s = { calls = 0, total = 0, max = 0, spikes = 0 }
		stats[name] = s
	end
	s.calls = s.calls + 1
	s.total = s.total + ms
	if ms > s.max then
		s.max = ms
	end
	if ms > Perf.SPIKE_MS then
		s.spikes = s.spikes + 1
		spikes[#spikes + 1] = { name = name, ms = ms, at = (Perf.clock() - startedAt) / 1000 }
		if #spikes > Perf.MAX_SPIKES then
			table.remove(spikes, 1)
		end
	end
	return ...
end

local function timed(name, fn)
	return function(...)
		return record(name, Perf.clock(), fn(...))
	end
end

-- Replace owner[key] (a function) with a timed wrapper; remember how to put it back.
local function wrapField(name, owner, key)
	local original = type(owner) == "table" and owner[key]
	if type(original) ~= "function" then
		return
	end
	local wrapper = timed(name, original)
	owner[key] = wrapper
	undo[#undo + 1] = function()
		if owner[key] == wrapper then
			owner[key] = original
		end
	end
end

-- The main redraws, by name: the window's page, the page's pieces, the map, run mode and the Notes window.
local function redraws()
	local UI = ns.UI
	local frame = UI and UI.Frame and UI.Frame()
	return {
		{ "redraw: page", UI, "RefreshPage" },
		{ "redraw: footer", UI, "RefreshFooter" },
		{ "redraw: instance page", frame and frame.instancePage, "Refresh" },
		{ "redraw: steps list", frame and frame.instancePage, "RefreshSteps" },
		{ "redraw: home", frame and frame.home, "Refresh" },
		{ "redraw: map", UI and UI.mapCanvas, "DrawContent" },
		{ "redraw: run mode", ns.RunMode, "Refresh" },
		{ "redraw: notes", ns.NotesFrame, "Refresh" },
	}
end

function Perf.Start()
	if running then
		return false
	end
	running = true
	startedAt = Perf.clock()
	for event, handlers in pairs(ns.EventTable()) do
		for i = 1, #handlers do
			wrapField("event: " .. event, handlers, i)
		end
	end
	for message, list in pairs(ns.ListenerTable()) do
		for i = 1, #list do
			wrapField("message: " .. message, list[i], "fn")
		end
	end
	for _, r in ipairs(redraws()) do
		wrapField(r[1], r[2], r[3])
	end
	return true
end

function Perf.Stop()
	if not running then
		return false
	end
	for i = #undo, 1, -1 do
		undo[i]()
	end
	undo = {}
	running = false
	startedAt = nil
	return true
end

function Perf.Reset()
	stats, spikes = {}, {}
	if running then
		startedAt = Perf.clock()
	end
end

-- Memory and the game's own profiler, guarded: { memoryKB?, recent?, peak?, over5ms? }.
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
	local profiler, enum = rawget(_G, "C_AddOnProfiler"), rawget(_G, "Enum")
	local metrics = type(enum) == "table" and enum.AddOnProfilerMetric
	if type(profiler) == "table" and type(profiler.GetAddOnMetric) == "function" and type(metrics) == "table" then
		local function metric(key)
			local ok, v = pcall(profiler.GetAddOnMetric, ns.name, metrics[key])
			v = ok and ns.Util.Plain(v) or nil
			return type(v) == "number" and v or nil
		end
		out.recent, out.peak, out.over5ms = metric("RecentAverageTime"), metric("PeakTime"), metric("CountTimeOver5Ms")
	end
	return out
end

local function ms(v)
	return string.format("%.2f", v)
end

-- A short plain-text summary, for chat and the report window: lines.
function Perf.Summary(top)
	local lines = {}
	local state = running and string.format("running for %d s", math.floor((Perf.clock() - startedAt) / 1000))
		or (Perf.HasData() and "stopped" or "off")
	lines[#lines + 1] = "Perf probe: " .. state .. " (spikes are calls over " .. Perf.SPIKE_MS .. " ms)"
	local mem = Perf.Memory()
	local bits = {}
	if mem.memoryKB then
		bits[#bits + 1] = string.format("memory %.1f MB", mem.memoryKB / 1024)
	end
	if mem.recent then
		bits[#bits + 1] = "profiler recent avg " .. ms(mem.recent) .. " ms"
	end
	if mem.peak then
		bits[#bits + 1] = "peak " .. ms(mem.peak) .. " ms"
	end
	if mem.over5ms then
		bits[#bits + 1] = "frames over 5 ms: " .. mem.over5ms
	end
	lines[#lines + 1] = #bits > 0 and table.concat(bits, ", ") or "memory and profiler: not available on this client"
	local names = {}
	for name in pairs(stats) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		if stats[a].total ~= stats[b].total then
			return stats[a].total > stats[b].total
		end
		return a < b
	end)
	for i = 1, math.min(#names, top or 12) do
		local s = stats[names[i]]
		lines[#lines + 1] = string.format("  %s: %d calls, total %s ms, avg %s, max %s, spikes %d", names[i], s.calls,
			ms(s.total), ms(s.total / s.calls), ms(s.max), s.spikes)
	end
	if #names > (top or 12) then
		lines[#lines + 1] = string.format("  (+%d more)", #names - (top or 12))
	end
	for _, sp in ipairs(spikes) do
		lines[#lines + 1] = string.format("  spike: %s %s ms at +%d s", sp.name, ms(sp.ms), math.floor(sp.at))
	end
	return lines
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
