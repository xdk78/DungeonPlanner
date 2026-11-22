-- The problem report (Core/Report.lua, UI/ReportFrame.lua), the error ring (Core/Init.lua) and the perf probe
-- (Core/Perf.lua) against the mock client.
local T = ...
local ns, mock = T.ns, T.mock
local Report, Perf = ns.Report, ns.Perf

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function click(b)
	b:GetScript("OnClick")(b, "LeftButton")
end

-- Run fn with the game's error handler silenced (SafeCall passes errors on to it).
local function quietly(fn)
	local old = _G.geterrorhandler
	_G.geterrorhandler = function()
		return function() end
	end
	local ok, err = pcall(fn)
	_G.geterrorhandler = old
	assert(ok, err)
end

T.case("Errors: SafeCall keeps the last distinct errors with a count, bounded, without the player's name", function()
	ns.Errors.Clear()
	mock.realm = "Zxqrealm"
	quietly(function()
		local function boom()
			error("boom Tester-Zxqrealm in Interface\\AddOns\\DungeonPlanner\\UI\\X.lua")
		end
		ns.SafeCall(boom)
		ns.SafeCall(boom)
		T.eq(#ns.Errors.list, 1, "the same error is one row")
		T.eq(ns.Errors.list[1].count, 2)
		local m = ns.Errors.list[1].message
		T.ok(not m:find("Tester", 1, true) and not m:find("Zxqrealm", 1, true), m)
		T.ok(m:find("<name>", 1, true) and not m:find("Interface", 1, true), m)
		for i = 1, 25 do
			ns.SafeCall(function()
				error("distinct " .. i)
			end)
		end
	end)
	T.eq(#ns.Errors.list, ns.Errors.MAX, "bounded")
	T.ok(ns.Errors.list[#ns.Errors.list].message:find("distinct 25", 1, true), "newest last")
	mock.realm = "Forever"
	ns.Errors.Clear()
end)

T.case("Errors: a failing event handler and a failing bus listener are recorded; so is a failing slash command", function()
	ns.Errors.Clear()
	quietly(function()
		ns:On("REPORT_TEST", "report-test", function()
			error("listener failed")
		end)
		ns:Fire("REPORT_TEST")
		ns:Off("REPORT_TEST", "report-test")
	end)
	T.eq(#ns.Errors.list, 1)
	T.ok(ns.Errors.list[1].message:find("listener failed", 1, true))
	ns.Errors.Clear()
end)

T.case("Report: facts for a bug, nothing about the character, realm, guild, group or the plan's own words", function()
	boot()
	ns.Errors.Clear()
	mock.realm = "Zxqrealm"
	_G.GetGuildInfo = function()
		return "Zzguild"
	end
	mock.units.party1 = { name = "Zzfriend", level = 80, class = "MAGE" }
	local plan = ns.Plan.New({ name = "Zzsecretname", instance = { name = "Somewhere", kind = "dungeon", uiMapID = 7 } })
	ns.DB.AddPlan(plan)
	ns.UI.SelectPlan(plan.id)
	quietly(function()
		ns.SafeCall(function()
			error("failed for Tester on Zxqrealm")
		end)
	end)
	local text = Report.Text(Report.Collect(), "It broke when I clicked Zzfriend")
	mock.realm = "Forever"
	_G.GetGuildInfo = nil
	mock.units.party1 = nil
	for _, secret in ipairs({ "Tester", "Zxqrealm", "Zzguild", "Zzsecretname" }) do
		T.ok(not text:find(secret, 1, true), "the report leaks " .. secret .. ":\n" .. text)
	end
	for _, wanted in ipairs({ "Addon: ", "Client: ", "Language: ", "Plan: " .. plan.id, "(own)", "Window: ", "Other addons: ",
		"Debug summary:", "API checks missing", "Lua errors", "<name>", "What happened:", "It broke when I clicked" }) do
		T.ok(text:find(wanted, 1, true), "the report lacks " .. wanted .. ":\n" .. text)
	end
	T.ok(text:find("data schema " .. ns.DB.SCHEMA, 1, true), "schema version")
	T.ok(text:find("revision", 1, true), "plan revision")
	ns.DB.DeletePlan(plan.id)
	ns.Errors.Clear()
end)

T.case("Report: the step, the instance, the language and the integrations", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
	local data = Report.Collect()
	T.eq(data.plan.kind, "recommended")
	T.ok(data.plan.steps and data.plan.steps > 3, "the plan's steps are counted")
	T.eq(data.language.active, "enUS")
	local text = Report.Text(data, "")
	T.ok(text:find("Step: ", 1, true), text)
	T.ok(text:find("(not filled in)", 1, true))
	local folders = {}
	for _, row in ipairs(data.integrations) do
		folders[row.folder] = row.state
	end
	for _, folder in ipairs({ "OpenMap", "ForeverDungeonJournal", "DBM-Core", "BigWigs", "WoWPoPolskuForever" }) do
		T.ok(folders[folder], folder .. " is listed")
	end
	T.ok(not data.instance.inside or data.instance.name, "the instance only when inside one")
end)

T.case("Report: a broken collector becomes a line, never an error", function()
	boot()
	local old = ns.Instances.Current
	ns.Instances.Current = function()
		error("no map")
	end
	local ok, text = pcall(function()
		return Report.Text(Report.Collect(), "x")
	end)
	ns.Instances.Current = old
	T.ok(ok, text)
	T.ok(text:find("(unavailable) instance", 1, true), text)
end)

T.case("Report: Lua errors from BugGrabber are read, filtered to ours, and merged without duplicates", function()
	boot()
	ns.Errors.Clear()
	quietly(function()
		ns.SafeCall(function()
			error("own error")
		end)
	end)
	_G.BugGrabber = {
		GetDB = function()
			return {
				{ message = "Interface\\AddOns\\OtherAddon\\a.lua:1: nope", counter = 1 },
				{ message = "Interface\\AddOns\\DungeonPlanner\\Core\\X.lua:9: from the grabber", counter = 3 },
				{ message = "other", stack = "Interface\\AddOns\\DungeonPlanner\\UI\\Y.lua:2: in function", counter = 1 },
			}
		end,
	}
	local list = Report.Errors()
	_G.BugGrabber = nil
	T.eq(#list, 3, "own + two of ours from the grabber, not the other addon's")
	local sources = {}
	for _, e in ipairs(list) do
		sources[#sources + 1] = e.source
	end
	T.eq(table.concat(sources, ","), "BugGrabber,BugGrabber,Dungeon Planner")
	T.eq(list[1].count + list[2].count, 4, "the grabber's counters are kept")
	ns.Errors.Clear()
	T.eq(#Report.Errors(), 0)
end)

T.case("Report: the issue link is short, encoded, cuts a long text on a character and names real form fields", function()
	boot()
	local data = Report.Collect()
	local url = Report.IssueURL(data, string.rep("\196\133", 300) .. " end")
	T.ok(url:find("^https://github%.com/xdk78/DungeonPlanner/issues/new%?template=bug_report%.yml"), url)
	T.ok(#url < 600, "short: " .. #url)
	T.ok(not url:find("[ \n\"<>]"), "no raw spaces or quotes")
	local what = url:match("[?&]what=([^&]*)")
	local decoded = what:gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end)
	T.eq(#decoded % 2, 0, "ends on a whole two-byte letter")
	T.ok(#decoded <= Report.MAX_WHAT)
	T.ok(not Report.IssueURL(data, ""):find("what=", 1, true))
	T.eq(Report.UrlEncode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
	-- Every parameter is a field id of the issue form, and the form has a field for the pasted report.
	local f = assert(io.open(".github/ISSUE_TEMPLATE/bug_report.yml", "rb"))
	local yml = f:read("*a")
	f:close()
	local ids = {}
	for id in yml:gmatch("\n%s+id:%s*([%w_]+)") do
		ids[id] = true
	end
	for name in url:gmatch("[?&]([%w_]+)=") do
		T.ok(name == "template" or ids[name], "the issue form has no field with the id " .. name)
	end
	T.ok(ids.report, "a field for the pasted report")
	T.ok(not io.open(".github/ISSUE_TEMPLATE/bug_report.md", "rb"), "the old markdown template is gone")
end)

T.case("Report window: opens from /dp report and the title-bar button, shows the text and the link, follows What happened", function()
	boot()
	ns.UI.Show()
	local main = ns.UI.Frame()
	T.ok(main.bug, "a bug button in the title bar")
	click(main.bug)
	local f = ns.ReportFrame.Frame()
	T.ok(f:IsShown(), "opened by the button")
	T.ok(f.report:GetValue():find("Dungeon Planner problem report", 1, true))
	T.ok(f.link:GetValue():find("issues/new", 1, true))
	f:Hide()
	ns.Slash.Handle("report")
	T.ok(f:IsShown(), "opened by /dp report")
	f.what.edit:SetText("it broke")
	f.what.edit:GetScript("OnTextChanged")(f.what.edit, true)
	T.ok(f.report:GetValue():find("it broke", 1, true), "the report follows the text")
	T.ok(f.link:GetValue():find("what=it%20broke", 1, true), "the link follows the text")
	-- The report box is read only: typing restores it.
	local before = f.report:GetValue()
	f.report.edit:SetText("typed")
	f.report.edit:GetScript("OnTextChanged")(f.report.edit, true)
	T.eq(f.report.edit:GetText(), before)
	click(f.select)
	f:Hide()
end)

T.case("Perf: off by default, nothing wrapped; start wraps, stop restores", function()
	boot()
	T.ok(not Perf.IsRunning() and not Perf.HasData())
	local listeners = ns.ListenerTable()
	local owner = {}
	local function original() end
	ns:On("PERF_TEST", owner, original)
	local refresh = ns.UI.RefreshPage
	T.eq(listeners.PERF_TEST[1].fn, original, "untouched while off")
	local event = next(ns.EventTable())
	local handler = ns.EventTable()[event][1]
	T.ok(Perf.Start())
	T.ok(not Perf.Start(), "already running")
	T.ok(listeners.PERF_TEST[1].fn ~= original, "wrapped while running")
	T.ok(ns.UI.RefreshPage ~= refresh)
	T.ok(ns.EventTable()[event][1] ~= handler)
	T.ok(Perf.Stop())
	T.eq(listeners.PERF_TEST[1].fn, original, "restored")
	T.eq(ns.UI.RefreshPage, refresh)
	T.eq(ns.EventTable()[event][1], handler)
	ns:Off("PERF_TEST", owner)
	Perf.Reset()
end)

T.case("Perf: counts calls, records spikes over 5 ms, summarises, and reports memory only when the client has it", function()
	boot()
	local fake = 0
	local realClock = Perf.clock
	Perf.clock = function()
		return fake
	end
	local owner = {}
	ns:On("PERF_TEST", owner, function(slow)
		fake = fake + (slow and 7 or 1)
	end)
	_G.GetAddOnMemoryUsage = function()
		return 2048
	end
	Perf.Start()
	ns:Fire("PERF_TEST", false)
	ns:Fire("PERF_TEST", true)
	ns:Fire("PERF_TEST", false)
	local lines = Perf.Summary()
	Perf.Stop()
	Perf.clock = realClock
	_G.GetAddOnMemoryUsage = nil
	ns:Off("PERF_TEST", owner)
	local text = table.concat(lines, "\n")
	T.ok(text:find("message: PERF_TEST: 3 calls, total 9.00 ms", 1, true), text)
	T.ok(text:find("spikes 1", 1, true), text)
	T.ok(text:find("spike: message: PERF_TEST 7.00 ms", 1, true), text)
	T.ok(text:find("memory 2.0 MB", 1, true), text)
	T.ok(Perf.HasData())
	-- The report carries the numbers.
	T.ok(Report.Text(Report.Collect(), ""):find("Perf probe: stopped", 1, true))
	Perf.Reset()
	T.ok(not Perf.HasData())
	T.ok(table.concat(Perf.Summary(), "\n"):find("not available on this client", 1, true), "no profiler, no memory call: said so")
end)

T.case("Perf: /dp perf start, stop and reset; spikes stay bounded", function()
	boot()
	ns.Slash.Handle("perf start")
	T.ok(Perf.IsRunning())
	ns.Slash.Handle("perf")
	ns.Slash.Handle("perf stop")
	T.ok(not Perf.IsRunning())
	ns.Slash.Handle("perf reset")
	local fake = 0
	local realClock = Perf.clock
	Perf.clock = function()
		fake = fake + 10
		return fake
	end
	local owner = {}
	ns:On("PERF_TEST", owner, function() end)
	Perf.Start()
	for _ = 1, 50 do
		ns:Fire("PERF_TEST")
	end
	local spikes = 0
	for _, line in ipairs(Perf.Summary()) do
		if line:find("^  spike:") then
			spikes = spikes + 1
		end
	end
	Perf.Stop()
	Perf.clock = realClock
	ns:Off("PERF_TEST", owner)
	T.eq(spikes, Perf.MAX_SPIKES)
	Perf.Reset()
end)
