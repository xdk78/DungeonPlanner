-- The run recorder: Model/RunLog.lua (pull segmentation, composition from nameplates, boss kills and wipes, history
-- caps, best splits, plan from run) and Tracker/Recorder.lua against the mock client (opt-in, events, the combat-only
-- ticker, secret values never stored), and Run mode's recorder line.
local T = ...
local ns, mock = T.ns, T.mock
local RunLog = ns.RunLog

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

-- Does a value (deeply) contain the mock's secret marker?
local function holdsSecret(v, depth)
	depth = depth or 0
	if v == mock.SECRET then
		return true
	end
	if type(v) == "table" and depth < 12 then
		for k, x in pairs(v) do
			if holdsSecret(k, depth + 1) or holdsSecret(x, depth + 1) then
				return true
			end
		end
	end
	return false
end

T.case("RunLog: pulls are combat segments; size is the peak seen at once; empty pulls are dropped", function()
	local store = RunLog.NewStore()
	local run, new = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 1000)
	T.ok(new and store.current == run)
	local again, new2 = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 1200)
	T.ok(again == run and not new2, "coming back within RESUME continues the run")
	T.ok(RunLog.PullStart(run, 1010, "Anvilmar's Rest"))
	T.eq(RunLog.PullStart(run, 1011), nil, "one pull at a time")
	RunLog.Observe(run, { { level = 14, class = "elite", name = "Ghost" }, { level = 13, class = "normal" } })
	RunLog.Observe(run, { { level = 14, class = "elite" }, { level = 15, class = "elite" }, { level = 13, class = "normal" } })
	RunLog.Observe(run, { { level = 14, class = "elite" } })
	local pull = RunLog.PullEnd(run, 1040, 1, false)
	T.eq(pull.c, 3, "peak enemies")
	T.eq(pull.el, 2, "peak elites")
	T.eq(pull.lo, 13)
	T.eq(pull.hi, 15)
	T.eq(pull.u, 30, "duration")
	T.eq(pull.s, 10, "start after the run began")
	T.eq(pull.z, "Anvilmar's Rest")
	T.eq(pull.nm[1], "Ghost", "plain names are kept")
	T.eq(pull.dd, 1)
	-- A combat in which no enemy was seen is not a pull.
	RunLog.PullStart(run, 1100)
	T.eq(RunLog.PullEnd(run, 1105, 0, false), nil)
	T.eq(#run.p, 1)
end)

T.case("RunLog: boss kills are linked to their pull, deduplicated; wipes count", function()
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 0)
	RunLog.PullStart(run, 60)
	RunLog.Observe(run, { { level = -1, class = "worldboss" } })
	T.ok(RunLog.BossKill(run, 3493, "Faldrim Anvilmar", 120))
	T.eq(RunLog.BossKill(run, 3493, nil, 121), nil, "ENCOUNTER_END and BOSS_KILL report one kill")
	RunLog.PullEnd(run, 122, 0, false)
	T.eq(run.p[1].k, 3493)
	T.eq(run.p[1].b, 1, "a boss in the pull")
	T.eq(run.b[1].p, 1)
	RunLog.PullStart(run, 200)
	RunLog.Observe(run, { { level = 16, class = "elite" } })
	RunLog.BossWipe(run, 230)
	RunLog.PullEnd(run, 231, 5, true)
	T.eq(run.w, 1, "one wipe, counted once")
	T.ok(run.p[2].w)
	T.eq(run.dd, 5)
	local s = RunLog.Summary(run)
	T.eq(s.pulls, 2)
	T.eq(s.bosses, 1)
	T.eq(s.duration, 231)
end)

T.case("RunLog: history is capped per instance, normalised, cleared; best splits and plan from run", function()
	local store = RunLog.NewStore()
	for i = 1, RunLog.MAX_RUNS + 3 do
		local t = i * 10000
		local run = RunLog.Enter(store, "36", "The Deadmines", 1, t)
		RunLog.PullStart(run, t + 10)
		RunLog.Observe(run, { { level = 18, class = "normal" }, { level = 18, class = "elite" } })
		RunLog.PullEnd(run, t + 40, 0, false)
		RunLog.PullStart(run, t + 50)
		RunLog.Observe(run, { { level = 19, class = "worldboss" } })
		RunLog.BossKill(run, 1, "Rhahk'Zor", t + 100 + i)
		RunLog.PullEnd(run, t + 110 + i, 0, false)
	end
	RunLog.Finish(store, 999999)
	T.eq(#store.runs["36"], RunLog.MAX_RUNS, "capped")
	T.eq(store.current, nil)
	local runs = RunLog.Runs(store, "36")
	local newest = runs[1]
	local splits, best = RunLog.Splits(store, newest)
	T.eq(#splits, 1)
	T.ok(splits[1].delta > 0, "slower than the best split of the other runs")
	T.ok(best.total and best.total < RunLog.Duration(newest))
	T.eq(best.previous, runs[2])
	-- Plan from a run: pulls in order without the boss pull, bosses with their encounter IDs; it validates.
	local raw = RunLog.PlanFromRun(newest, { name = "The Deadmines", kind = "dungeon" },
		{ L = ns.L, plural = ns.Plural, date = "today" })
	local plan = ns.Validate.Plan(raw)
	T.ok(plan, "a valid plan")
	T.eq(#plan.pulls, 1, "the boss's pull is the boss, not a pull")
	T.ok(plan.pulls[1].note:find("2 enemies", 1, true), plan.pulls[1].note)
	T.eq(#plan.encounters, 1)
	T.eq(plan.encounters[1].dungeonEncounterID, 1)
	T.eq(#plan.markers, 0, "no positions: the player places them")
	-- Normalise repairs junk; Clear removes.
	local junk = RunLog.Normalize({ runs = { x = { 1, { k = "x", t = 1, p = {} }, { p = {} } }, [5] = {} }, current = "bad" })
	T.eq(#junk.runs.x, 1)
	T.eq(junk.runs[5], nil)
	T.eq(junk.current, nil)
	RunLog.Clear(store, "36")
	T.eq(store.runs["36"], nil)
	T.eq(RunLog.FormatTime(3725), "1:02:05")
	T.eq(RunLog.FormatTime(65), "1:05")
	T.eq(RunLog.FormatDelta(-12), "-0:12")
end)

T.case("Recorder: off by default; records a run from events, nameplates and kills; stores nothing secret", function()
	boot()
	local R = ns.Recorder
	R.ClearHistory()
	T.eq(ns.db.settings.recorder.enabled, false, "opt-in")
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	T.eq(R.Current(), nil, "nothing recorded while off")
	R.SetEnabled(true)
	local run = R.Current()
	T.ok(run, "entering (already inside) the mock's instance starts a run")
	T.eq(run.k, "9001")
	mock.units = {
		nameplate1 = { level = 14, class = "elite", name = mock.SECRET, hostile = true, combat = true },
		nameplate2 = { level = mock.SECRET, class = "normal", name = "Plain Rat", hostile = true, combat = true },
		nameplate3 = { level = 14, class = "elite", hostile = false, combat = true }, -- friendly: not counted
		nameplate4 = { level = 14, class = "normal", hostile = true, combat = true, dead = true }, -- dead: not counted
	}
	mock.plates = { "nameplate1", "nameplate2", "nameplate3", "nameplate4" }
	mock.subzone = "Anvilmar's Rest"
	mock.inCombat = true
	mock.FireEvent("PLAYER_REGEN_DISABLED")
	T.ok(RunLog.OpenPull(run), "combat opens a pull")
	mock.Advance(0.6)
	mock.plates = { "nameplate1" }
	mock.Advance(0.6)
	local timers = #mock.timers
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.eq(RunLog.OpenPull(run), nil, "combat end closes it")
	mock.Advance(1)
	T.ok(#mock.timers < timers or timers == 0, "the scan ticker stops with combat")
	local pull = run.p[1]
	T.eq(pull.c, 2, "two hostile, living enemies at once")
	T.eq(pull.el, 1)
	T.eq(pull.lo, 14, "a secret level is left out")
	T.eq(pull.nm and #pull.nm, 1, "only the plain name")
	T.eq(pull.nm[1], "Plain Rat")
	T.eq(pull.z, "Anvilmar's Rest")
	T.eq(R.api.names, "secret", "the last look saw a secret name (reported by /dp debug)")
	mock.FireEvent("ENCOUNTER_END", 3493, mock.SECRET, 1, 5, 1)
	T.eq(#run.b, 1, "a kill from ENCOUNTER_END")
	T.eq(run.b[1].n, nil, "a secret boss name is not stored")
	mock.FireEvent("BOSS_KILL", 3493, "Faldrim Anvilmar")
	T.eq(#run.b, 1, "the same kill once")
	T.eq(run.b[1].n, "Faldrim Anvilmar", "a later plain name fills it in")
	T.ok(not holdsSecret(R.Store()), "no secret value reached SavedVariables")
	-- Run mode shows it.
	ns.RunMode.Show()
	local text = ns.RunMode.RecorderText(nil)
	T.ok(text:find("Recording", 1, true), text)
	-- Finish, plan from run, clear.
	local finished = R.FinishRun()
	T.ok(finished and finished.done)
	local plan = R.CreatePlan(finished, nil)
	T.ok(plan and ns.db.plans[plan.id], "the draft is saved as an editable plan")
	T.eq(#plan.encounters, 1)
	R.ClearHistory()
	T.eq(next(R.Store().runs), nil)
	R.SetEnabled(false)
	T.ok(ns.RunMode.RecorderText(nil):find("Not recording", 1, true))
	ns.RunMode.Hide()
	ns.DB.DeletePlan(plan.id)
	mock.units, mock.plates, mock.subzone = {}, {}, nil
end)

T.case("Runs section: before the first run, the Run pane says whether recording is on, and follows the switch", function()
	boot()
	local R, L = ns.Recorder, ns.L
	R.SetEnabled(false)
	R.ClearHistory()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("runs")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.runs.inner -- the section inside its inset panel
	-- What the Run pane is given, line by line (the document's own Add).
	local lines = {}
	local add = panel.detail.Add
	panel.detail.Add = function(doc, style, text)
		lines[#lines + 1] = text
		return add(doc, style, text)
	end
	local function says(text)
		for _, line in ipairs(lines) do
			if line == text then
				return true
			end
		end
		return false
	end
	local off = L["Turn on \"Record my runs\" and play this instance: each run shows up here."]
	local on = L["Recording is on. Your next run in this instance will appear here."]
	panel:Refresh()
	T.ok(says(off), "off: how to turn it on")
	-- Ticking "Record my runs" redraws the pane (RECORDER_CHANGED), with no run recorded yet.
	lines = {}
	mock.Click(panel.record)
	T.eq(R.Enabled(), true, "the check box turns recording on")
	T.ok(R.Current() == nil or R.Current().k ~= ns.Recorder.KeyForPlan(ns.UI.ctx:Plan()), "no run of this instance yet")
	T.ok(says(on), "on: the next run will appear here")
	T.ok(not says(off), "not the turn-on hint")
	-- Turned off again (here, or in the Settings panel: the same call), the hint comes back.
	lines = {}
	R.SetEnabled(false)
	T.ok(says(off), "off again")
	panel.detail.Add = add
	R.ClearHistory()
end)

T.case("Share section: the run text before the first run says whether recording is on", function()
	boot()
	local R, L = ns.Recorder, ns.L
	R.SetEnabled(false)
	R.ClearHistory()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("share")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.share.inner
	local p = ns.UI.ctx:Plan()
	local off = L["No recorded run of this instance yet. Turn on \"Record my runs\" in the Runs section."]
	local on = L["No recorded run of this instance yet. Recording is on: your next run here can be shared."]
	T.eq(panel:RunParts(p, {})[1], off, "off: how to turn it on")
	R.SetEnabled(true)
	T.eq(panel:RunParts(p, {})[1], on, "on: not the turn-on hint")
	R.SetEnabled(false)
	R.ClearHistory()
end)

T.case("Runs section lists recorded runs and drafts a plan", function()
	boot()
	local R = ns.Recorder
	R.ClearHistory()
	R.SetEnabled(true)
	local run = R.Current()
	RunLog.PullStart(run, ns.Now())
	RunLog.Observe(run, { { level = 15, class = "elite" } })
	RunLog.PullEnd(run, ns.Now() + 20, 0, false)
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	local plan = ns.Bundled.Get("b:hall-of-thanes")
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("runs")
	local page = _G.DungeonPlannerMainFrame.instancePage
	local panel = page.panels.runs
	T.ok(panel, "the Runs section exists")
	panel:Refresh()
	R.SetEnabled(false)
	R.ClearHistory()
end)

-- One pull, so a run is kept when it finishes.
local function pull(run, now)
	RunLog.PullStart(run, now)
	RunLog.Observe(run, { { level = 30, class = "elite" } })
	RunLog.PullEnd(run, now + 20, 0, false)
end

T.case("RunLog: instance keys with a wing; a run of the shared key takes the wing, another wing is another run", function()
	T.eq(RunLog.WingKey("189", "scarletmonasterylibrary"), "189:scarletmonasterylibrary")
	local iid, wing = RunLog.SplitKey("189:scarletmonasterylibrary")
	T.eq(iid, "189")
	T.eq(wing, "scarletmonasterylibrary")
	iid, wing = RunLog.SplitKey("189")
	T.eq(iid, "189")
	T.eq(wing, nil, "a key saved before 0.2.1 has no wing")
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "189", "Scarlet Monastery", 1, 1000)
	pull(run, 1010)
	local again, new = RunLog.Enter(store, "189:a", "Scarlet Monastery", 1, 1100)
	T.ok(again == run and not new, "the wing becomes known: the same run")
	T.eq(run.k, "189:a", "and it takes the wing")
	again, new = RunLog.Enter(store, "189", "Scarlet Monastery", 1, 1200)
	T.ok(again == run and not new and run.k == "189:a", "the wing unclear again: the run keeps its wing")
	local other, isNew = RunLog.Enter(store, "189:b", "Scarlet Monastery", 1, 1300)
	T.ok(isNew and other ~= run, "another wing: another run")
	T.eq(#store.runs["189:a"], 1, "the first run is kept under its wing")
	T.eq(store.runs["189"], nil, "nothing under the shared key")
	pull(other, 1310)
	local third = RunLog.Enter(store, "36", "The Deadmines", 1, 1400)
	T.ok(third ~= other and not RunLog.Adopt(third, "189"), "another instance")
	RunLog.Finish(store, 1500)
	store.runs["189"] = { { k = "189", t = 900, p = {}, b = {}, done = true } }
	local merged = RunLog.RunsOf(store, { "189:b", "189" })
	T.eq(#merged, 2)
	T.ok(merged[1] == other and merged[2].k == "189", "newest first across both keys")
end)

T.case("Recorder: wings sharing an instance ID record their runs apart; older runs show under every wing", function()
	boot()
	local R, L = ns.Recorder, ns.L
	R.SetEnabled(false)
	R.ClearHistory()
	local iid = ns.TravelData.instances["Scarlet Monastery: Library"].iid
	local shared = tostring(iid)
	local libKey, armKey = RunLog.WingKey(shared, "scarletmonasterylibrary"), RunLog.WingKey(shared, "scarletmonasteryarmory")
	local library = ns.Bundled.Get("b:scarlet-monastery-library")
	local armory = ns.Bundled.Get("b:scarlet-monastery-armory")
	T.ok(library and armory, "the recommended plans of two wings")
	local key, sharedKey = R.KeyForPlan(library)
	T.eq(key, libKey, "the Library's runs are its own")
	T.eq(sharedKey, shared, "runs whose wing was not known are under the instance ID")
	T.eq(R.KeyForPlan(armory), armKey)
	T.eq(R.KeyForPlan(ns.Bundled.Get("b:hall-of-thanes")), "3065", "an instance without wings: its ID alone")
	-- A run saved by 0.2.0: under the shared ID.
	local store = R.Store()
	local legacy = RunLog.Enter(store, shared, "Scharlachrotes Kloster", 1, ns.Now() - 5000)
	pull(legacy, ns.Now() - 4990)
	RunLog.Finish(store, ns.Now() - 4000)
	-- Standing in Scarlet Monastery: the client names the instance, its map no wing.
	local saved = { info = _G.GetInstanceInfo, best = _G.C_Map.GetBestMapForUnit }
	local map
	_G.GetInstanceInfo = function()
		return "Scharlachrotes Kloster", "party", 1, "Normal", 5, 0, false, iid
	end
	_G.C_Map.GetBestMapForUnit = function()
		return map
	end
	local ok, err = pcall(function()
		-- 1. Nothing says which wing: the shared key.
		R.SetEnabled(true)
		T.eq(R.Current().k, shared, "wing unclear: the shared instance ID")
		pull(R.Current(), ns.Now())
		R.FinishRun()
		T.eq(#store.runs[shared], 2, "kept under the shared key, with the older run")
		mock.Advance(60)
		-- 2. Run mode on the Library's plan: the Library.
		ns.UI.SelectPlan(library.id)
		ns.RunMode.Show()
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(R.Current().k, libKey, "run mode's plan names the wing")
		pull(R.Current(), ns.Now())
		local libRun = R.FinishRun()
		ns.RunMode.Hide()
		mock.Advance(60)
		-- 3. The client's map names the Armory.
		map = 437
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(R.Current().k, armKey, "the client's map names the wing")
		pull(R.Current(), ns.Now())
		local armRun = R.FinishRun()
		map = nil
		mock.Advance(60)
		-- 4. A run started without a wing takes the Library's once run mode shows its plan at the next pull.
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(R.Current().k, shared)
		ns.UI.SelectPlan(library.id)
		ns.RunMode.Show()
		mock.inCombat = true
		mock.FireEvent("PLAYER_REGEN_DISABLED")
		T.eq(R.Current().k, libKey, "the run takes the wing")
		mock.inCombat = false
		mock.FireEvent("PLAYER_REGEN_ENABLED")
		ns.RunMode.Hide()
		R.Current().p = {}
		R.FinishRun()
		-- What each plan lists.
		local function has(list, run)
			return ns.Util.IndexOf(list, run) ~= nil
		end
		local libRuns, armRuns = R.RunsForPlan(library), R.RunsForPlan(armory)
		T.eq(#libRuns, 3, "the Library: its run and the two whose wing was not known")
		T.ok(has(libRuns, libRun) and has(libRuns, legacy) and not has(libRuns, armRun), "not the Armory's run")
		T.eq(#armRuns, 3)
		T.ok(has(armRuns, armRun) and has(armRuns, legacy) and not has(armRuns, libRun), "not the Library's run")
		T.ok(R.WingUnknown(legacy, library) and not R.WingUnknown(libRun, library), "older runs are marked")
		T.ok(not R.WingUnknown(armRun, armory))
		local unclear = ns.Validate.Plan({ name = "Mein Plan", instance = { name = "Scharlachrotes Kloster",
			kind = "dungeon", instanceMapID = iid }, floors = { { name = "" } } })
		T.eq(R.KeyForPlan(unclear), shared, "a plan whose wing is unclear: the shared key")
		T.eq(#R.RunsForPlan(unclear), 4, "and every wing's runs")
		T.ok(not R.WingUnknown(legacy, unclear))
		T.eq(R.CreatePlan(libRun, nil).instance.instanceMapID, iid, "a plan from a wing's run knows the instance")
		-- The Runs section: the older run, newest here, says its wing is not known.
		legacy.t = ns.Now() + 10
		if not ns.UI.IsShown() then
			ns.UI.Toggle()
		end
		ns.UI.SelectPlan(library.id)
		ns.UI.SelectTab("runs")
		local panel = _G.DungeonPlannerMainFrame.instancePage.panels.runs.inner
		local lines = {}
		local add = panel.detail.Add
		panel.detail.Add = function(doc, style, text)
			lines[#lines + 1] = text
			return add(doc, style, text)
		end
		panel:Refresh()
		panel.detail.Add = add
		T.ok(ns.Util.IndexOf(lines, L["Recorded without knowing the wing: it may be a run of another wing of this instance."]),
			"the run's wing is not known")
		-- Clearing the Library's history removes what it lists; the Armory keeps its own run.
		R.ClearForPlan(library)
		T.eq(#R.RunsForPlan(library), 0)
		T.eq(#R.RunsForPlan(armory), 1)
	end)
	_G.GetInstanceInfo, _G.C_Map.GetBestMapForUnit = saved.info, saved.best
	local made = {}
	for id, p in pairs(ns.db.plans) do
		if p.instance.instanceMapID == iid then
			made[#made + 1] = id
		end
	end
	for _, id in ipairs(made) do
		ns.DB.DeletePlan(id)
	end
	R.SetEnabled(false)
	R.ClearHistory()
	ns.RunMode.Hide()
	assert(ok, err)
end)
