-- Model/RunCompare.lua: a recorded run against its plan (pulls paired by order between boss kills, skipped and extra
-- pulls, boss order), live drift (pulls since the last kill, the estimated step, warnings), two runs side by side, the
-- previous run's splits, and the Discord run summary.
local T = ...
local ns = T.ns
local RunLog, RC = ns.RunLog, ns.RunCompare

-- A plan: pull 1, pull 2 (tagged "next": pulled with pull 3), pull 3, boss A, pull 4 (tagged "skip"), pull 5, boss B,
-- then pull 6 after the last boss.
local function plan()
	return ns.Validate.Plan({
		name = "Drift",
		instance = { name = "Test Keep", kind = "dungeon" },
		pulls = {
			{ id = "u1", name = "Gate" },
			{ id = "u2", name = "Hall", tags = { "next" } },
			{ id = "u3", name = "Hall patrol" },
			{ id = "u4", name = "Side room", tags = { "skip" } },
			{ id = "u5", name = "Stairs" },
			{ id = "u6", name = "Treasure" },
		},
		encounters = {
			{ id = "e1", name = "Boss A", dungeonEncounterID = 101 },
			{ id = "e2", name = "Boss B", dungeonEncounterID = 102 },
		},
	})
end

local function steps()
	local list = {}
	for _, s in ipairs({ { "pull", "u1" }, { "pull", "u2" }, { "pull", "u3" }, { "boss", "e1" }, { "pull", "u4" },
		{ "pull", "u5" }, { "boss", "e2" }, { "pull", "u6" } }) do
		list[#list + 1] = s[1] == "pull" and { kind = "pull", pull = s[2] } or { kind = "boss", encounter = s[2] }
	end
	return list
end

-- A run from a script: "t" = a trash pull of n enemies, { "k", id, name } = a boss pull with its kill, "w" = a boss
-- attempt that wiped.
local function record(script, store, t0)
	store = store or RunLog.NewStore()
	t0 = t0 or 1000
	local run = RunLog.Enter(store, "77", "Test Keep", 1, t0)
	local now = t0
	for _, item in ipairs(script) do
		now = now + 30
		RunLog.PullStart(run, now)
		if item == "t" then
			RunLog.Observe(run, { { level = 20, class = "elite" }, { level = 20, class = "normal" } })
			RunLog.PullEnd(run, now + 20, 0, false)
		elseif item == "w" then
			RunLog.Observe(run, { { level = -1, class = "worldboss" } })
			RunLog.PullEnd(run, now + 20, 5, true)
		else
			RunLog.Observe(run, { { level = -1, class = "worldboss" } })
			RunLog.BossKill(run, item[2], item[3], now + 15)
			RunLog.PullEnd(run, now + 20, 0, false)
		end
		now = now + 20
	end
	return run, store
end

T.case("RunCompare: the plan's sequence skips 'skip' pulls and merges 'next' pulls", function()
	local seq = RC.PlanSequence(plan(), steps())
	T.eq(#seq.segments, 3, "before A, before B, after B")
	T.eq(#seq.segments[1].planned, 2, "Gate, then Hall + Hall patrol as one pull")
	T.eq(#seq.segments[1].planned[2].pulls, 2)
	T.eq(seq.segments[1].boss, "e1")
	T.eq(#seq.segments[2].planned, 1, "the skipped side room is not planned")
	T.eq(seq.segments[3].boss, nil)
	T.eq(seq.total, 4)
	T.eq(seq.bosses[2], "e2")
	-- Without steps: pull order, then the bosses.
	T.eq(RC.PlanSequence(plan(), nil).total, 4)
end)

T.case("RunCompare: overlay pairs pulls by order, finds extra and skipped pulls and boss order", function()
	local p = plan()
	-- Three trash pulls before A (one more than planned), boss B before boss A, nothing between.
	local run = record({ "t", "t", "t", { "k", 102, "Boss B" }, { "k", 101, "Boss A" }, "t" })
	run.done = true
	local ov = RC.Overlay(p, run, steps())
	T.eq(ov.planned, 4)
	T.eq(ov.actual, 4)
	T.eq(ov.bossesKilled, 2)
	-- Trash before B's kill is the stretch before B in the run; A came with nothing before it.
	local segB = ov.segments[2]
	T.eq(segB.boss, "e2")
	T.eq(#segB.actual, 3, "the three pulls before B's kill")
	T.eq(segB.delta, 2)
	T.eq(segB.rows[2].kind, "extra")
	local segA = ov.segments[1]
	T.eq(#segA.actual, 0)
	T.eq(segA.rows[1].kind, "skipped")
	local kinds = {}
	for _, d in ipairs(ov.divergences) do
		kinds[d.kind] = (kinds[d.kind] or 0) + 1
		if d.kind == "order" then
			T.eq(d.boss, "e2")
			T.eq(d.before, "e1")
		end
	end
	T.eq(kinds.order, 1, "B killed before A")
	T.eq(kinds.extra, 1)
	T.eq(kinds.skipped, 1, "before A; the tail had one pull for one planned")
	-- An unknown boss, and a boss matched by name (an ID the plan does not carry).
	local run2 = record({ "t", { "k", 555, "boss a" }, { "k", 999, "Stranger" } })
	local ov2 = RC.Overlay(p, run2, steps())
	T.eq(ov2.segments[1].kill.n, "boss a", "matched by name")
	local unplanned
	for _, d in ipairs(ov2.divergences) do
		unplanned = unplanned or (d.kind == "unplanned" and d.name)
	end
	T.eq(unplanned, "Stranger")
end)

T.case("RunCompare: a failed boss attempt is not a trash pull; boss game IDs come from opts", function()
	local p = plan()
	local run = record({ "t", "t", "w", { "k", 7001, "Boss A" } })
	local ov = RC.Overlay(p, run, steps(), {
		idOf = function(enc)
			return enc.id == "e1" and 7001 or nil
		end,
	})
	T.eq(ov.segments[1].state, "done")
	T.eq(#ov.segments[1].actual, 2)
	T.eq(ov.segments[1].attempts, 1)
	T.eq(ov.segments[1].delta, 0)
end)

T.case("RunCompare: drift warns about extra pulls and out-of-order kills and estimates the step", function()
	local p = plan()
	local st = steps()
	local run = record({ "t" })
	local d = RC.Drift(p, run, st)
	T.eq(d.pullsDone, 1)
	T.eq(d.pullsPlanned, 4)
	T.eq(d.since, 1)
	T.eq(d.sincePlanned, 2)
	T.eq(d.nextBoss, "e1")
	T.eq(d.step, 2, "next: the merged Hall pull")
	T.eq(#d.warnings, 0)
	run = record({ "t", "t" })
	T.eq(RC.Drift(p, run, st).step, 4, "the stretch's pulls are done: the boss is next")
	run = record({ "t", "t", "t" })
	d = RC.Drift(p, run, st)
	T.eq(d.warnings[1].kind, "extra")
	T.eq(d.warnings[1].n, 1)
	T.eq(d.warnings[1].boss, "e1")
	-- An open pull in combat is not counted yet.
	RunLog.PullStart(run, 5000)
	RunLog.Observe(run, { { level = 20, class = "normal" } })
	d = RC.Drift(p, run, st)
	T.ok(d.inCombat)
	T.eq(d.since, 3)
	-- Killing B first: an order warning, and the stretch is now A's.
	run = record({ "t", { "k", 102, "Boss B" } })
	d = RC.Drift(p, run, st)
	T.eq(d.warnings[1].kind, "order")
	T.eq(d.nextBoss, "e1")
	T.eq(d.since, 0)
	-- Everything killed: the stretch after the last boss.
	run = record({ "t", "t", { "k", 101 }, "t", { "k", 102 }, "t", "t" })
	d = RC.Drift(p, run, st)
	T.eq(d.nextBoss, nil)
	T.eq(d.since, 2)
	T.eq(d.sincePlanned, 1)
	T.eq(d.warnings[1].kind, "extra")
end)

T.case("RunCompare: two runs side by side, previous run's splits, Discord run summary", function()
	local store = RunLog.NewStore()
	local first = record({ "t", "t", { "k", 101, "Boss A" }, "t", { "k", 102, "Boss B" } }, store, 1000)
	RunLog.Finish(store, 5000)
	local second = record({ "t", { "k", 101, "Boss A" }, "w", "t", "t", { "k", 102, "Boss B" } }, store, 10000)
	RunLog.Finish(store, 20000)
	T.eq(RC.Previous(store, second), first)
	T.eq(RC.Previous(store, first), nil)
	local pair = RC.Pair(second, first)
	local rows = {}
	for _, r in ipairs(pair.summary) do
		rows[r.id] = r
	end
	T.eq(rows.pulls.a, 6)
	T.eq(rows.pulls.b, 5)
	T.eq(rows.pulls.delta, 1)
	T.eq(rows.wipes.delta, 1)
	T.eq(#pair.bosses, 2)
	T.ok(pair.bosses[1].delta < 0, "A was faster the second time")
	T.eq(pair.stretches[1].a, 1)
	T.eq(pair.stretches[1].b, 2)
	T.eq(pair.stretches[2].a, 2, "the wipe is a boss attempt, not trash")
	local splits = RC.Splits(store, second)
	T.eq(#splits, 2)
	T.ok(splits[1].prevDelta < 0)
	-- Discord: parts under the limit, the plan's name, the off-plan lines.
	local p = plan()
	local parts = ns.Discord.RenderRun(p, second, {
		overlay = RC.Overlay(p, second, steps()),
		splits = splits,
		date = "2026-11-16 21:04",
		bossName = function(encId)
			return encId == "e1" and "Boss A" or "Boss B"
		end,
	}, { version = "1.0" })
	local text = table.concat(parts, "\n")
	T.ok(#parts >= 1 and #parts[1] <= ns.Discord.LIMIT)
	T.ok(text:find("Drift", 1, true), "the plan's name")
	T.ok(text:find("Against the plan", 1, true), text)
	T.ok(text:find("previous -", 1, true), "the previous run's difference")
	T.ok(text:find("1 pull more than planned before Boss B", 1, true), text)
end)

T.case("Run mode: the drift line while recording, its warning, and going to the estimated step", function()
	if not _G.DungeonPlannerDB then
		T.mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		T.mock.loggedIn = true
		T.mock.FireEvent("PLAYER_LOGIN")
		T.mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	local R = ns.Recorder
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "hall-of-thanes")
	local p = ns.UI.ctx:Plan()
	T.eq(ns.RunMode.DriftText(p), nil, "nothing while not recording")
	R.ClearHistory()
	ns.db.settings.recorder.enabled = true
	local store = R.Store()
	local key = R.KeyForPlan(p) or "3065"
	local run = RunLog.Enter(store, key, "Hall of Thanes", 1, 1000)
	T.eq(ns.RunMode.DriftText(p), nil, "nothing before the first pull")
	-- Faldrim, then two trash pulls before Magmatus (the plan has one).
	RunLog.PullStart(run, 1010)
	RunLog.Observe(run, { { level = -1, class = "worldboss" } })
	RunLog.BossKill(run, 4001, "Faldrim Anvilmar", 1040)
	RunLog.PullEnd(run, 1041, 0, false)
	RunLog.PullStart(run, 1100)
	RunLog.Observe(run, { { level = 15, class = "elite" } })
	RunLog.PullEnd(run, 1130, 0, false)
	local text, warns, lines, d = ns.RunMode.DriftText(p)
	T.ok(text and not warns, tostring(text))
	T.ok(text:find("On plan", 1, true))
	T.ok(d.step, "a step estimate")
	T.ok(lines[#lines]:find("does not show where you are", 1, true), "says what it cannot know")
	ns.RunMode.Show()
	ns.RunMode.Refresh()
	ns.RunMode.GoToEstimate()
	T.eq(ns.UI.ctx:StepIndex(), d.step, "the click goes to the estimated step")
	RunLog.PullStart(run, 1200)
	RunLog.Observe(run, { { level = 15, class = "elite" } })
	RunLog.PullEnd(run, 1230, 0, false)
	text, warns = ns.RunMode.DriftText(p)
	T.ok(warns, "a warning")
	T.ok(text:find("1 pull more than planned before Magmatus", 1, true), text)
	ns.RunMode.Hide()
	R.ClearHistory()
	ns.db.settings.recorder.enabled = false
end)
