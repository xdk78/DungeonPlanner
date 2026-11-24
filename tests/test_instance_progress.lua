-- What the client says about the instance the player is in (Tracker/Tracker.lua, Model/Progress.lua, Tracker/Recorder.lua,
-- Model/RunLog.lua, UI/RunMode.lua): bosses already dead when the player joins (the instance's lock), a reset (the system
-- message, or a boss that starts though it is dead), and the enemies the group killed per recorded pull (PARTY_KILL).
local T = ...
local ns, mock = T.ns, T.mock
local Progress, RunLog, Tracker, R = ns.Progress, ns.RunLog, ns.Tracker, ns.Recorder

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

local function handlers(event)
	return #(ns.EventTable()[event] or {})
end

local INSIDE = function()
	return "Test Dungeon", "party", 1, "Normal", 5, 0, false, 9001
end
local OUTSIDE = function()
	return "Elwynn Forest", "none", 0, "", 0, 0, false, 0
end

-- lock = { { name, killed }, ... } as GetInstanceLockTimeRemainingEncounter lists them (a name may be mock.SECRET).
local function setLock(entries, opts)
	opts = opts or {}
	_G.GetInstanceLockTimeRemaining = function()
		return 0, opts.previous or false, opts.total or #entries, opts.complete or 0
	end
	_G.GetInstanceLockTimeRemainingEncounter = function(i)
		local e = entries[i]
		if not e then
			return nil
		end
		return e[1], 1234, e[2], false
	end
end

-- Runs fn(plan) with the tracker's store, the instance and the clock the test controls, and puts everything back, also
-- when fn fails. The plan is a saved one for the mock's instance with three bosses.
local function scenario(fn)
	boot()
	local saved = { progress = ns.char.progress, info = _G.GetInstanceInfo, now = ns.Now, lock = _G.GetInstanceLockTimeRemaining,
		lockEntry = _G.GetInstanceLockTimeRemainingEncounter, request = _G.RequestRaidInfo, reset = rawget(_G, "INSTANCE_RESET_SUCCESS"),
		selected = ns.db.ui.selectedPlan, step = ns.db.ui.step, recorder = ns.db.settings.recorder.enabled }
	ns.char.progress = Progress.NewStore()
	R.SetEnabled(false)
	R.ClearHistory()
	local plan = ns.Plan.New({ name = "Lock test", instance = { name = "Test Dungeon", kind = "dungeon", instanceMapID = 9001 } })
	ns.Plan.AddEncounter(plan, { name = "Boss A", dungeonEncounterID = 501 })
	ns.Plan.AddEncounter(plan, { name = "Boss B", dungeonEncounterID = 502 })
	ns.Plan.AddEncounter(plan, { name = "Boss C", dungeonEncounterID = 503 })
	ns.DB.AddPlan(plan)
	_G.GetInstanceInfo = INSIDE
	_G.INSTANCE_RESET_SUCCESS = "%s has been reset."
	Tracker.ResetPatterns()
	local now = 1000000
	ns.Now = function()
		return now
	end
	local ctl = { advance = function(s)
		now = now + s
	end }
	local ok, err = pcall(fn, plan, ctl)
	ns.Now, _G.GetInstanceInfo = saved.now, saved.info
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter, _G.RequestRaidInfo = saved.lock, saved.lockEntry, saved.request
	_G.INSTANCE_RESET_SUCCESS = saved.reset
	Tracker.ResetPatterns()
	R.SetEnabled(false)
	R.ClearHistory()
	ns.DB.DeletePlan(plan.id)
	ns.db.ui.selectedPlan, ns.db.ui.step = saved.selected, saved.step
	ns.db.settings.recorder.enabled = saved.recorder
	ns.RunSync.state = ns.Sync.New()
	ns.char.progress = saved.progress
	Tracker.EndRun() -- listens to nothing for the run this case left
	if not ok then
		error(err, 0)
	end
end

local function enter()
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	return ns.char.progress.run
end

-- Model ----------------------------------------------------------------------------------------------------------------

T.case("Progress: a boss found dead counts as killed in the run, but is not the player's kill", function()
	local s = Progress.NewStore()
	T.eq(Progress.MarkDeadOnJoin(s, 501, 100), false, "no run, nothing to mark")
	Progress.EnterInstance(s, "9001", "Test Dungeon", 1, 100)
	T.ok(Progress.MarkDeadOnJoin(s, 501, 110))
	T.eq(Progress.MarkDeadOnJoin(s, 501, 120), false, "once")
	T.eq(Progress.MarkDeadOnJoin(s, "x", 120), false, "not an encounter ID")
	T.ok(Progress.IsKilledInRun(s, 501))
	T.ok(Progress.WasDeadOnJoin(s, 501))
	T.eq(Progress.KilledAt(s, 501), 110)
	T.eq(Progress.KillsOf(s, 501), 0, "not among the player's kills")
	T.eq(next(s.kills), nil, "no lifetime record")
	Progress.RecordKill(s, 502, 1, "Boss B", 130)
	T.ok(not Progress.WasDeadOnJoin(s, 502), "a kill of the player's own")
	T.eq(Progress.KillsOf(s, 502), 1)
	-- Killed by the player after all: no longer "found dead".
	Progress.RecordKill(s, 501, 1, "Boss A", 140)
	T.ok(not Progress.WasDeadOnJoin(s, 501))
	T.ok(Progress.IsKilledInRun(s, 501))
	-- The summary counts both.
	local plan = { id = "p", objectives = {}, encounters = { { dungeonEncounterID = 501 }, { dungeonEncounterID = 502 }, { dungeonEncounterID = 503 } } }
	Progress.MarkDeadOnJoin(s, 503, 150)
	T.eq(Progress.PlanSummary(s, plan).bossesKilled, 3)
	-- A saved run with a junk `pre` is repaired.
	s.run.pre = "x"
	T.eq(Progress.Normalize(s).run.pre, nil)
	T.eq(Progress.WasDeadOnJoin(s, 503), false)
end)

T.case("Progress: the lock's dead bosses are matched by plain name only, English and German", function()
	local bosses = {
		{ id = 501, names = { "Rhahk'Zor", "Rhahk'zor" } },
		{ id = 502, names = { "Sneed's Shredder" } },
		{ id = 503, names = { "Gilnid" } },
	}
	local function dead(entries)
		return table.concat(Progress.DeadByName(entries, bosses), ",")
	end
	-- English: case and punctuation do not matter.
	T.eq(dead({ { name = "Rhahk'Zor", killed = true }, { name = "sneeds shredder", killed = true }, { name = "Gilnid", killed = false } }),
		"501,502", "a killed boss by name, an alive one not")
	-- German: the client's own names, learned from its ENCOUNTER_END or the journal.
	local german = { { id = 501, names = { "Rhahk'Zor", "Rhahk'Zor der Große" } }, { id = 502, names = { "Sneeds Schredder" } } }
	T.eq(table.concat(Progress.DeadByName({ { name = "Sneeds Schredder", killed = true } }, german), ","), "502")
	T.eq(table.concat(Progress.DeadByName({ { name = "Sneed's Shredder", killed = true } }, german), ","), "", "English name on a German client")
	-- Nothing is guessed.
	T.eq(dead({ { name = "Unbekannter Boss", killed = true } }), "", "an unknown name")
	T.eq(dead({ { name = nil, killed = true } }), "", "a name the client kept secret (read as nil)")
	T.eq(dead({ { name = "Gilnid", killed = nil } }), "", "a flag the client kept secret")
	T.eq(dead({ { name = "Gilnid", killed = 1 } }), "", "only true means killed")
	T.eq(dead({ { name = 7, killed = true } }), "", "not text")
	T.eq(dead({}), "")
	-- Two bosses of one name: neither is marked.
	local twins = { { id = 601, names = { "Twin" } }, { id = 602, names = { "Twin" } }, { id = 603, names = { "Solo" } } }
	T.eq(table.concat(Progress.DeadByName({ { name = "Twin", killed = true }, { name = "Solo", killed = true } }, twins), ","), "603")
	-- A boss under two plans goes by both their names and is marked once.
	T.eq(dead({ { name = "Rhahk'zor", killed = true }, { name = "Rhahk'Zor", killed = true } }), "501")
end)

T.case("Progress: NameOf gives the name the client gave the boss at the player's latest kill", function()
	local s = Progress.NewStore()
	T.eq(Progress.NameOf(s, 501), nil)
	Progress.RecordKill(s, 501, 1, "Alt", 100)
	Progress.RecordKill(s, 501, 2, "Neu", 200)
	Progress.RecordKill(s, 5010, 1, "Other boss", 300)
	T.eq(Progress.NameOf(s, 501), "Neu", "the latest, and not another boss whose ID starts the same")
end)

-- The lock ---------------------------------------------------------------------------------------------------------------

T.case("Lock: readings are plain, secret or missing; only plain ones are kept", function()
	local saved = { lock = _G.GetInstanceLockTimeRemaining, entry = _G.GetInstanceLockTimeRemainingEncounter }
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter = nil, nil
	T.eq(Tracker.ReadLock(), nil, "no API")
	setLock({ { "Boss A", true }, { mock.SECRET, true }, { "Boss C", mock.SECRET }, { "Boss D", false } })
	local entries = Tracker.ReadLock()
	T.eq(#entries, 4)
	T.eq(entries[1].name, "Boss A")
	T.eq(entries[1].killed, true)
	T.eq(entries[2].name, nil, "a secret name is no name")
	T.eq(entries[2].killed, true)
	T.eq(entries[3].killed, nil, "a secret flag is not killed")
	T.eq(entries[4].killed, false)
	-- How many bosses there are must be plain, or nothing is read.
	_G.GetInstanceLockTimeRemaining = function()
		return 0, false, mock.SECRET, 0
	end
	T.eq(Tracker.ReadLock(), nil, "a secret count")
	_G.GetInstanceLockTimeRemaining = function()
		return 0, false, 0, 0
	end
	T.eq(Tracker.ReadLock(), nil, "no bosses")
	_G.GetInstanceLockTimeRemaining = function()
		return nil
	end
	T.eq(Tracker.ReadLock(), nil, "no answer")
	-- An error in the client is not ours.
	_G.GetInstanceLockTimeRemaining = function()
		error("boom")
	end
	T.eq(Tracker.ReadLock(), nil, "the call raises")
	setLock({ { "Boss A", true } }, { total = 1000 })
	entries = Tracker.ReadLock()
	T.eq(#entries, Tracker.LOCK_MAX, "bounded, however many bosses the client claims")
	T.eq(entries[2].name, nil, "an entry the client does not have has no name")
	_G.GetInstanceLockTimeRemainingEncounter = function()
		error("boom")
	end
	T.eq(#Tracker.ReadLock(), 0, "an entry that raises is skipped")
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter = saved.lock, saved.entry
end)

T.case("Lock: entering an instance marks the dead bosses of its plan, as found dead", function()
	scenario(function(plan)
		setLock({ { "Boss A", true }, { "Boss B", false }, { "Somebody Else", true } })
		local asked = 0
		_G.RequestRaidInfo = function()
			asked = asked + 1
		end
		local seen = { changed = 0 }
		ns:On("PROGRESS_CHANGED", seen, function()
			seen.changed = seen.changed + 1
		end)
		ns:On("BOSSES_FOUND_DEAD", seen, function(ids)
			seen.found = ids
		end)
		R.SetEnabled(true)
		local run = enter()
		ns:Off("PROGRESS_CHANGED", seen)
		ns:Off("BOSSES_FOUND_DEAD", seen)
		T.ok(run, "a run of the instance")
		T.ok(Progress.IsKilledInRun(ns.char.progress, 501), "Boss A is dead")
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 501), "and was found so")
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 502), "Boss B is not")
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 503), "nor is the one the lock does not list")
		T.eq(Progress.KillsOf(ns.char.progress, 501), 0, "not the player's kill")
		T.eq(table.concat(seen.found, ","), "501", "run mode is told")
		T.ok(seen.changed >= 1, "the progress views refresh")
		T.eq(asked, 1, "fresh lock data was asked for")
		T.ok(R.Current(), "the recorder was on while the player entered")
		T.eq(#R.Current().b, 0, "and has no kill for the boss found dead")
		R.SetEnabled(false)
		-- Asked again at once: not again within the throttle.
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(asked, 1, "RequestRaidInfo is throttled")
		mock.Advance(Tracker.LOCK_REQUEST_EVERY + 1)
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(asked, 2, "and asked again later")
		T.eq(ns.Plan.FindEncounterByGameID(plan, 501).name, "Boss A")
	end)
end)

T.case("Lock: UPDATE_INSTANCE_INFO and a kill read it again; missing or secret readings mark nothing", function()
	scenario(function()
		local asked = 0
		_G.RequestRaidInfo = function()
			asked = asked + 1
		end
		setLock({})
		enter()
		T.eq(next(ns.char.progress.run.kills), nil, "an empty lock")
		-- The answer to RequestRaidInfo arrives: read again, and never asked for again from there.
		setLock({ { "Boss B", true } })
		local before = asked
		mock.FireEvent("UPDATE_INSTANCE_INFO")
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 502), "found on UPDATE_INSTANCE_INFO")
		T.eq(asked, before, "that read does not ask again")
		-- The player kills Boss A; the lock now lists Boss C dead too (a group member's kill).
		setLock({ { "Boss A", true }, { "Boss B", true }, { "Boss C", true } })
		mock.Advance(Tracker.LOCK_REQUEST_EVERY + 1)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		T.ok(not Progress.WasDeadOnJoin(ns.char.progress, 501), "Boss A is the player's own kill")
		T.eq(Progress.KillsOf(ns.char.progress, 501), 1)
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 503), "Boss C was found after the kill")
		T.eq(asked, before + 1, "the kill asked for fresh data")
		-- Secret and missing: nothing more is marked, nothing raises.
		ns.char.progress.run.kills[503], ns.char.progress.run.pre[503] = nil, nil
		setLock({ { mock.SECRET, true } })
		mock.FireEvent("UPDATE_INSTANCE_INFO")
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 503), "a secret name marks nothing")
		_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter, _G.RequestRaidInfo = nil, nil, nil
		mock.FireEvent("UPDATE_INSTANCE_INFO")
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 503), "a client without the API marks nothing")
	end)
end)

T.case("Lock: the name the client gave at an earlier kill, or the journal's, matches in another language", function()
	scenario(function(plan)
		-- Plan bosses carry English names; this client says them in German. The first boss was killed in an earlier run (the
		-- name came with ENCOUNTER_END); the second has a journal entry, whose name this client gives in German.
		Progress.RecordKill(ns.char.progress, 501, 1, "Der Erste", 1)
		plan.encounters[2].ejEncounterID = 987654
		local savedEJ = _G.EJ_GetEncounterInfo
		_G.EJ_GetEncounterInfo = function(id)
			return id == 987654 and "Der Zweite" or nil
		end
		setLock({ { "Der Erste", true }, { "Der Zweite", true }, { "Boss C", true } })
		local ok, err = pcall(enter)
		_G.EJ_GetEncounterInfo = savedEJ
		T.ok(ok, tostring(err))
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 501), "by the name from an earlier kill")
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 502), "by the journal's name")
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 503), "by the plan's own name, which is the client's here")
	end)
end)

T.case("Lock: events are listened to only inside the instance of a run (and the system message only while a run exists)", function()
	scenario(function(_, clock)
		setLock({})
		local base = { info = handlers("UPDATE_INSTANCE_INFO"), start = handlers("ENCOUNTER_START"), system = handlers("CHAT_MSG_SYSTEM"),
			lockStart = handlers("INSTANCE_LOCK_START") }
		-- Tracking off: nothing is started, nothing listened to.
		ns.db.settings.tracker.enabled = false
		enter()
		ns.db.settings.tracker.enabled = true
		T.eq(handlers("UPDATE_INSTANCE_INFO"), base.info)
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system)
		enter()
		T.ok(ns.char.progress.run, "a run")
		T.eq(handlers("UPDATE_INSTANCE_INFO"), base.info + 1, "inside: the lock's update")
		T.eq(handlers("ENCOUNTER_START"), base.start + 1, "inside: encounters starting")
		T.eq(handlers("INSTANCE_LOCK_START"), base.lockStart + 1, "inside: the lock prompt")
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system + 1, "a run: the reset message")
		-- Leaving the instance: the run stays, so the reset message can still come; the rest stops.
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.ok(ns.char.progress.run, "the run is kept")
		T.eq(handlers("UPDATE_INSTANCE_INFO"), base.info, "outside: no lock events")
		T.eq(handlers("ENCOUNTER_START"), base.start)
		T.eq(handlers("INSTANCE_LOCK_START"), base.lockStart)
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system + 1, "the reset message still counts")
		-- Long after leaving, the run is no longer one the player can come back to: the first message sees it and stops
		-- listening, with no timer. Neither does a login (outdoors) make it fresh again.
		clock.advance(Progress.RESUME - 60)
		mock.FireEvent("CHAT_MSG_SYSTEM", "Welcome to the game.")
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system + 1, "still within the window")
		clock.advance(120)
		mock.FireEvent("CHAT_MSG_SYSTEM", "Welcome to the game.")
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system, "past it: not listening")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system, "a login does not bring it back")
		-- Without a run, nothing at all.
		_G.GetInstanceInfo = INSIDE
		enter()
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system + 1)
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		Tracker.EndRun()
		T.eq(handlers("CHAT_MSG_SYSTEM"), base.system, "no run: no listening")
		_G.GetInstanceInfo = INSIDE
	end)
end)

-- Reset ------------------------------------------------------------------------------------------------------------------

T.case("Reset: the client's own message becomes a pattern, in English and German", function()
	local saved = rawget(_G, "INSTANCE_RESET_SUCCESS")
	_G.INSTANCE_RESET_SUCCESS = "%s has been reset."
	Tracker.ResetPatterns()
	T.eq(Tracker.ResetName("Test Dungeon has been reset."), "Test Dungeon")
	T.eq(Tracker.ResetName("The Deadmines has been reset."), "The Deadmines")
	T.eq(Tracker.ResetName("Ma-gus (heroic) [x] 100% has been reset."), "Ma-gus (heroic) [x] 100%", "pattern characters in the name")
	T.eq(Tracker.ResetName("Test Dungeon could not be reset."), nil, "another message")
	T.eq(Tracker.ResetName("You gain 5 experience."), nil)
	T.eq(Tracker.ResetName(" has been reset."), nil, "no name")
	T.eq(Tracker.ResetName(12), nil, "not text")
	T.eq(Tracker.ResetName(nil), nil)
	_G.INSTANCE_RESET_SUCCESS = "%s wurde zur\195\188ckgesetzt."
	Tracker.ResetPatterns()
	T.eq(Tracker.ResetName("Die Todesminen wurde zur\195\188ckgesetzt."), "Die Todesminen")
	T.eq(Tracker.ResetName("Test Dungeon has been reset."), nil, "English text on a German client")
	-- A language that puts a word after the name, or numbers the argument.
	_G.INSTANCE_RESET_SUCCESS = "Die Instanz %1$s wurde zur\195\188ckgesetzt."
	Tracker.ResetPatterns()
	T.eq(Tracker.ResetName("Die Instanz Gnomeregan wurde zur\195\188ckgesetzt."), "Gnomeregan")
	-- A client without the string reads nothing.
	_G.INSTANCE_RESET_SUCCESS = nil
	Tracker.ResetPatterns()
	T.eq(Tracker.ResetName("Test Dungeon has been reset."), nil)
	_G.INSTANCE_RESET_SUCCESS = saved
	Tracker.ResetPatterns()
end)

local function twoKills(plan)
	-- Boss A killed by the player, Boss B found dead.
	setLock({ { "Boss B", true } })
	enter()
	mock.Advance(20)
	mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
	T.ok(Progress.IsKilledInRun(ns.char.progress, 501) and Progress.WasDeadOnJoin(ns.char.progress, 502))
	ns.db.ui.selectedPlan = plan.id
	ns.UI.FocusStep(2, { stay = true })
	T.eq(ns.UI.ctx:StepIndex(), 2)
	return ns.char.progress.run
end

T.case("Reset: the message clears the run's kills and takes run mode back to the start", function()
	scenario(function(plan)
		local old = twoKills(plan)
		local tellings = {}
		ns:On("INSTANCE_RESET", tellings, function(name, key)
			tellings[#tellings + 1] = name .. "|" .. tostring(key)
		end)
		-- Another instance's reset changes nothing.
		mock.FireEvent("CHAT_MSG_SYSTEM", "Somewhere Else has been reset.")
		T.ok(ns.char.progress.run == old and Progress.IsKilledInRun(ns.char.progress, 501), "not this instance")
		mock.FireEvent("CHAT_MSG_SYSTEM", "You gain 5 experience.")
		mock.FireEvent("CHAT_MSG_SYSTEM", mock.SECRET)
		T.ok(ns.char.progress.run == old, "other and secret messages")
		-- Out of the instance, as a reset is done.
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		mock.FireEvent("CHAT_MSG_SYSTEM", "Test Dungeon has been reset.")
		ns:Off("INSTANCE_RESET", tellings)
		T.eq(ns.char.progress.run, nil, "the run of the old copy is over")
		T.eq(#ns.char.progress.history, 1, "and kept with its kills")
		T.ok(ns.char.progress.history[1].kills[501])
		T.eq(tellings[1], "Test Dungeon|9001")
		T.eq(ns.db.ui.step, nil, "run mode is back at the start")
		T.eq(Progress.KillsOf(ns.char.progress, 501), 1, "the lifetime count stays")
		-- Back in: a new run with nothing killed, and the lock is read again for the new copy.
		_G.GetInstanceInfo = INSIDE
		setLock({})
		local run = enter()
		T.ok(run and run ~= old and next(run.kills) == nil, "a new copy starts with no kills")
		-- A boss killed now is killed once, not taken for a repeat of the old copy's kill.
		mock.Advance(1)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		T.ok(Progress.IsKilledInRun(ns.char.progress, 501))
		T.eq(Progress.KillsOf(ns.char.progress, 501), 2)
	end)
end)

T.case("Reset: it also ends the recorder's run for that instance, and run mode keeps a followed leader's step", function()
	scenario(function(plan)
		R.SetEnabled(true)
		local rec = R.Current()
		local pull = RunLog.PullStart(rec, ns.Now() + 5)
		pull.c = 3
		RunLog.PullEnd(rec, ns.Now() + 20, 0, false)
		twoKills(plan)
		-- Following a leader: the step is the leader's to move.
		ns.RunSync.state = { mode = "following" }
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		mock.FireEvent("CHAT_MSG_SYSTEM", "Test Dungeon has been reset.")
		T.ok(ns.db.ui.step ~= nil, "a follower's step stays until the leader's arrives")
		T.eq(ns.char.progress.run, nil)
		T.ok(R.Current() == nil or R.Current() ~= rec, "the recorded run of the old copy ended")
		T.eq(#R.Store().runs["9001"], 1, "and was kept")
		T.ok(R.Store().runs["9001"][1] == rec)
	end)
end)

T.case("Reset: a boss that starts though the run has it dead is a new copy, a wipe and retry is not", function()
	scenario(function(_, clock)
		local listener, resets = {}, 0
		ns:On("INSTANCE_RESET", listener, function()
			resets = resets + 1
		end)
		setLock({})
		local run = enter()
		-- Boss A: an attempt, a wipe, another attempt, the kill.
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 0)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 0)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		T.ok(ns.char.progress.run == run and resets == 0, "a wipe and retry is not a new copy")
		mock.Advance(1)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		-- Boss B, wiped on and retried: Boss A's kill stays.
		mock.FireEvent("ENCOUNTER_START", 502, "Boss B", 1, 5)
		mock.FireEvent("ENCOUNTER_END", 502, "Boss B", 1, 5, 0)
		mock.FireEvent("ENCOUNTER_START", 502, "Boss B", 1, 5)
		T.ok(ns.char.progress.run == run and Progress.IsKilledInRun(ns.char.progress, 501) and resets == 0)
		-- A late or repeated start of the boss just killed: inside the grace, not a new copy.
		clock.advance(Tracker.NEW_COPY_GRACE - 1)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		T.ok(ns.char.progress.run == run and resets == 0, "inside the grace")
		-- Later, the same boss starts: its old kill belongs to another copy.
		clock.advance(2)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		ns:Off("INSTANCE_RESET", listener)
		T.eq(resets, 1, "told once")
		T.ok(ns.char.progress.run ~= run, "a new run")
		T.eq(next(ns.char.progress.run.kills), nil, "with nothing killed")
		T.eq(ns.char.progress.history[#ns.char.progress.history].kills[501] ~= nil, true, "the old copy's run is kept")
		-- The kill of the fight in progress lands in the new run.
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		T.ok(Progress.IsKilledInRun(ns.char.progress, 501))
		T.ok(not Progress.WasDeadOnJoin(ns.char.progress, 501))
	end)
end)

T.case("Reset: a boss found dead that then starts means the lock was another copy's, at once", function()
	scenario(function()
		setLock({ { "Boss B", true } })
		local run = enter()
		T.ok(Progress.WasDeadOnJoin(ns.char.progress, 502))
		mock.FireEvent("ENCOUNTER_START", 503, "Boss C", 1, 5)
		T.ok(ns.char.progress.run == run, "another boss starting changes nothing")
		setLock({})
		mock.FireEvent("ENCOUNTER_START", 502, "Boss B", 1, 5)
		T.ok(ns.char.progress.run ~= run and next(ns.char.progress.run.kills) == nil, "found dead, yet alive: the lock was stale")
	end)
end)

T.case("Reset: with tracking off nothing is cleared, and an outside run is not touched", function()
	scenario(function()
		setLock({})
		local run = enter()
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		ns.db.settings.tracker.enabled = false
		T.eq(Tracker.OnInstanceReset("Test Dungeon"), false)
		T.eq(Tracker.OnEncounterStart(501), false)
		ns.db.settings.tracker.enabled = true
		T.ok(ns.char.progress.run == run)
		T.eq(Tracker.OnInstanceReset(""), false, "no name")
		T.eq(Tracker.OnInstanceReset("Test Dungeon"), true)
	end)
end)

T.case("Reset: a boss marked by hand that starts is alive: only that mark goes, the run stays", function()
	scenario(function(plan, clock)
		local listener, resets = {}, 0
		ns:On("INSTANCE_RESET", listener, function()
			resets = resets + 1
		end)
		setLock({})
		local run = enter()
		ns.db.ui.selectedPlan = plan.id
		T.eq(Tracker.MarkNextBossKilled().id, plan.encounters[1].id, "Boss A, marked by hand")
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 502, "Boss B", 1, 5, 1)
		T.ok(Progress.MarkedByHand(ns.char.progress, 501) and not Progress.MarkedByHand(ns.char.progress, 502))
		clock.advance(Tracker.NEW_COPY_GRACE * 3)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		T.ok(ns.char.progress.run == run, "the same run")
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 501), "the mark is gone")
		T.ok(Progress.IsKilledInRun(ns.char.progress, 502), "the game's kill stays")
		T.eq(resets, 0, "and nothing was told to start over")
		-- Marked by hand, then killed for real: the game has said it, so it is no longer only a mark.
		Tracker.MarkNextBossKilled()
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		T.ok(not Progress.MarkedByHand(ns.char.progress, 501))
		clock.advance(Tracker.NEW_COPY_GRACE * 3)
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		ns:Off("INSTANCE_RESET", listener)
		T.eq(resets, 1, "that kill does mean a new copy when the boss starts again")
	end)
end)

T.case("Lock: entering again with a lock that lists a killed boss alive does not end the run", function()
	scenario(function(_, clock)
		setLock({})
		local run = enter()
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		clock.advance(Tracker.NEW_COPY_GRACE * 3)
		-- The client's list may be cached while RequestRaidInfo is still answering: a /reload or a portal must not read
		-- it as a reset.
		setLock({ { "Boss A", false } })
		T.ok(enter() == run and Progress.IsKilledInRun(ns.char.progress, 501))
	end)
end)

T.case("Hand marks: the game's report within the dedupe window replaces the mark, and a mark survives a reload", function()
	scenario(function(plan, clock)
		setLock({})
		enter()
		ns.db.ui.selectedPlan = plan.id
		Tracker.MarkNextBossKilled()
		T.eq(Progress.KillsOf(ns.char.progress, 501), 1)
		-- The real kill comes at once (inside the 15 s dedupe window).
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		T.ok(not Progress.MarkedByHand(ns.char.progress, 501), "no longer only a mark")
		T.ok(Progress.IsKilledInRun(ns.char.progress, 501))
		T.eq(Progress.KillsOf(ns.char.progress, 501), 1, "the same kill, counted once")
		-- It is now game evidence: the boss starting again later means a new copy.
		clock.advance(Tracker.NEW_COPY_GRACE * 3)
		local run = ns.char.progress.run
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		T.ok(ns.char.progress.run ~= run)
		-- A mark made by hand is still one after the saved data is read back.
		Tracker.MarkNextBossKilled()
		T.ok(Progress.MarkedByHand(ns.char.progress, 501))
		local loaded = Progress.Normalize(ns.Util.DeepCopy(ns.char.progress))
		T.ok(loaded.run.hand and loaded.run.hand[501], "kept by Normalize")
		ns.char.progress = loaded
		T.ok(Progress.MarkedByHand(ns.char.progress, 501))
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 501), "and a boss that starts still only loses it")
		T.ok(ns.char.progress.run, "the run stays")
		-- A saved `hand` of the wrong type is dropped.
		loaded.run.hand = "x"
		T.eq(Progress.Normalize(loaded).run.hand, nil)
	end)
end)

T.case("Resume: the run is stamped while inside, so a logout or a reload inside, long after it began, still resumes it", function()
	scenario(function(_, clock)
		setLock({})
		local MIN = 60
		local run = enter()
		-- A logout inside, 26 minutes after the last zone event inside and another 26 after that: logging in outdoors
		-- 6 minutes later and walking back in resumes the run.
		clock.advance(26 * MIN)
		enter()
		clock.advance(26 * MIN)
		ns.EventDispatcher()("PLAYER_LOGOUT") -- our handlers only: the mock's logout also closes the saved data
		clock.advance(6 * MIN)
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		T.ok(ns.char.progress.run == run, "kept")
		_G.GetInstanceInfo = INSIDE
		T.ok(enter() == run, "resumed")
		-- Outdoor events never refresh it: 40 minutes of them leave it behind.
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_LEAVING_WORLD")
		for _ = 1, 4 do
			clock.advance(10 * MIN)
			mock.FireEvent("ZONE_CHANGED_NEW_AREA")
		end
		_G.GetInstanceInfo = INSIDE
		T.ok(enter() ~= run, "a new run after being away for long")
		-- A reload inside after a long quiet stretch: PLAYER_LEAVING_WORLD stamps, so the run goes on.
		local second = ns.char.progress.run
		clock.advance(2 * 60 * MIN)
		mock.FireEvent("PLAYER_LEAVING_WORLD")
		T.ok(enter() == second, "the run of a long dungeon survives a reload")
		-- And a kill is activity too.
		clock.advance(29 * MIN)
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		clock.advance(29 * MIN)
		T.ok(enter() == second and Progress.IsKilledInRun(ns.char.progress, 501), "29 minutes after a kill, resumed")
	end)
end)

T.case("Lock: a lock of a previous instance is not read", function()
	scenario(function()
		setLock({ { "Boss A", true } }, { previous = true })
		T.eq(Tracker.ReadLock(), nil)
		enter()
		T.ok(not Progress.IsKilledInRun(ns.char.progress, 501), "nothing marked from it")
		setLock({ { "Boss A", true } }, { previous = false })
		T.eq(#Tracker.ReadLock(), 1)
		setLock({ { "Boss A", true } }, { previous = mock.SECRET })
		T.eq(#Tracker.ReadLock(), 1, "a secret answer is not a yes")
	end)
end)

T.case("Recorder: a reset found by a boss starting in combat goes on recording the fight in the new run", function()
	scenario(function(_, clock)
		setLock({})
		R.SetEnabled(true)
		enter()
		local old = R.Current()
		mock.Advance(20)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		clock.advance(Tracker.NEW_COPY_GRACE + 5)
		mock.units = { player = { combat = true }, nameplate1 = { level = 14, class = "elite", name = "Boss A", hostile = true, combat = true } }
		mock.plates = { "nameplate1" }
		mock.inCombat = true
		mock.FireEvent("PLAYER_REGEN_DISABLED")
		mock.FireEvent("ENCOUNTER_START", 501, "Boss A", 1, 5)
		local run = R.Current()
		T.ok(run and run ~= old, "a new recorder run")
		T.ok(RunLog.OpenPull(run), "the fight under way is its first pull")
		mock.FireEvent("PARTY_KILL", mock.SECRET, mock.SECRET)
		mock.FireEvent("ENCOUNTER_END", 501, "Boss A", 1, 5, 1)
		mock.inCombat = false
		mock.FireEvent("PLAYER_REGEN_ENABLED")
		T.eq(run.p[1].gk, 1, "its group kills are counted")
		T.eq(run.p[1].c, 1, "and its nameplates scanned")
		T.eq(#run.b, 1, "and the kill is in the new run")
		T.eq(#R.Store().runs["9001"], 1, "the old copy's run was kept apart")
		mock.units, mock.plates = {}, {}
	end)
end)

T.case("Events: a handler that unregisters while an event is delivered does not make the next one skip", function()
	local calls = {}
	local function second()
		calls[#calls + 1] = "second"
	end
	local function first()
		calls[#calls + 1] = "first"
		ns:UnregisterEvent("DP_TEST_EVENT", first)
	end
	ns:RegisterEvent("DP_TEST_EVENT", first)
	ns:RegisterEvent("DP_TEST_EVENT", second)
	ns.EventDispatcher()("DP_TEST_EVENT")
	T.eq(table.concat(calls, ","), "first,second")
	ns.EventDispatcher()("DP_TEST_EVENT")
	T.eq(table.concat(calls, ","), "first,second,second", "the one that left is gone")
	ns:UnregisterEvent("DP_TEST_EVENT", second)
	T.ok(not ns.EventTable().DP_TEST_EVENT)
end)

T.case("Events: a handler registered while an event is delivered runs from the next delivery on", function()
	local calls = {}
	local function late()
		calls[#calls + 1] = "late"
	end
	local function early()
		calls[#calls + 1] = "early"
		ns:RegisterEvent("DP_TEST_EVENT", late)
	end
	ns:RegisterEvent("DP_TEST_EVENT", early)
	ns.EventDispatcher()("DP_TEST_EVENT")
	T.eq(table.concat(calls, ","), "early", "not in the round that registered it")
	ns:UnregisterEvent("DP_TEST_EVENT", early) -- or it would register another one each round
	ns.EventDispatcher()("DP_TEST_EVENT")
	T.eq(table.concat(calls, ","), "early,late", "in the next")
	ns:UnregisterEvent("DP_TEST_EVENT", late)
	T.ok(not ns.EventTable().DP_TEST_EVENT)
end)

T.case("Run mode: bosses found dead move the step past them, never back, and not while following", function()
	scenario(function(plan)
		ns.db.ui.selectedPlan = plan.id
		local c = ns.UI.ctx
		local steps = c:Steps()
		local stepOf = function(code)
			return ns.Steps.IndexOfEncounter(steps, ns.Plan.FindEncounterByGameID(plan, code).id)
		end
		ns.db.ui.step = nil
		ns.RunMode.OnFoundDead({ 502 })
		T.eq(c:StepIndex(), math.min(stepOf(502) + 1, #steps), "from before the first step, past that boss's step")
		local after = c:StepIndex()
		ns.RunMode.OnFoundDead({ 501 })
		T.eq(c:StepIndex(), math.max(after, math.min(stepOf(501) + 1, #steps)), "an earlier boss never moves it back")
		ns.RunMode.OnFoundDead({ 999 })
		ns.RunMode.OnFoundDead({})
		T.ok(c:StepIndex() >= after, "an unknown boss changes nothing")
		ns.db.ui.step = nil
		ns.RunSync.state = { mode = "following" }
		ns.RunMode.OnFoundDead({ 502 })
		T.eq(c:StepIndex(), nil, "a follower waits for the leader's step")
	end)
end)

-- PARTY_KILL -------------------------------------------------------------------------------------------------------------------

T.case("RunLog: group kills are a count of their own, bounded, and keep a pull that has them", function()
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 1000)
	T.eq(RunLog.GroupKill(run), false, "no pull in progress")
	RunLog.PullStart(run, 1010)
	T.ok(RunLog.GroupKill(run))
	T.ok(RunLog.GroupKill(run))
	RunLog.Observe(run, { { level = 14, class = "normal" } })
	T.eq(run.p[1].gk, 2)
	T.eq(run.p[1].c, 1, "the nameplates' count is not touched")
	RunLog.Observe(run, { { level = 14, class = "normal" }, { level = 14, class = "normal" }, { level = 14, class = "normal" } })
	T.eq(run.p[1].gk, 2, "and the nameplates do not touch the kills")
	RunLog.PullEnd(run, 1040, 0, false)
	T.eq(RunLog.Summary(run).killed, 2)
	-- A pull with kills and nothing else seen is kept; one with nothing is dropped.
	RunLog.PullStart(run, 1100)
	RunLog.GroupKill(run)
	T.ok(RunLog.PullEnd(run, 1105, 0, false), "kills only: kept")
	T.eq(run.p[2].gk, 1)
	RunLog.PullStart(run, 1200)
	T.eq(RunLog.PullEnd(run, 1205, 0, false), nil, "nothing seen, nothing killed: dropped")
	T.eq(#run.p, 2)
	T.eq(RunLog.Summary(run).killed, 3, "summed over the pulls")
	-- Bounded.
	RunLog.PullStart(run, 1300)
	for _ = 1, RunLog.MAX_GROUP_KILLS + 25 do
		RunLog.GroupKill(run)
	end
	T.eq(run.p[3].gk, RunLog.MAX_GROUP_KILLS)
	T.eq(RunLog.GroupKill(run), false, "at the bound")
	-- A saved pull with junk is repaired, a huge count capped.
	run.p[1].gk, run.p[2].gk, run.p[3].gk = "x", -4, 10 ^ 9
	RunLog.PullEnd(run, 1310, 0, false)
	store.current = run
	local norm = RunLog.Normalize(store)
	T.eq(norm.current.p[1].gk, nil)
	T.eq(norm.current.p[2].gk, nil)
	T.eq(norm.current.p[3].gk, RunLog.MAX_GROUP_KILLS)
end)

T.case("Recorder: PARTY_KILL is counted per pull, only while a run is recorded in its instance", function()
	scenario(function()
		T.eq(handlers("PARTY_KILL"), 0, "recording off: not listened to")
		T.ok(not ns.EventTable().PARTY_KILL)
		R.SetEnabled(true)
		local run = R.Current()
		T.eq(handlers("PARTY_KILL"), 1, "recording: listened to")
		-- Between pulls nothing is counted.
		mock.FireEvent("PARTY_KILL", "Player-1-0000", "Creature-0-0-0-0-1-0000")
		T.eq(#run.p, 0)
		mock.units, mock.plates = {}, {}
		mock.inCombat = true
		mock.FireEvent("PLAYER_REGEN_DISABLED")
		mock.FireEvent("PARTY_KILL", "Player-1-0000", "Creature-0-0-0-0-1-0000")
		mock.FireEvent("PARTY_KILL", "Pet-0-0-0-0-1-0000", mock.SECRET)
		mock.FireEvent("PARTY_KILL", mock.SECRET, mock.SECRET)
		mock.inCombat = false
		mock.FireEvent("PLAYER_REGEN_ENABLED")
		T.eq(#run.p, 1, "a pull with kills and no nameplate seen is kept")
		T.eq(run.p[1].gk, 3, "kills of secret enemies count too")
		T.eq(run.p[1].c, 0)
		mock.FireEvent("PARTY_KILL", "Player-1-0000", "Creature-0-0-0-0-1-0000")
		T.eq(run.p[1].gk, 3, "a pull that has ended counts no more")
		T.ok(not holdsSecret(R.Store()), "no secret GUID was stored")
		-- Outside the instance, and with recording off, nothing listens.
		_G.GetInstanceInfo = OUTSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(handlers("PARTY_KILL"), 0, "outdoors")
		_G.GetInstanceInfo = INSIDE
		mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		T.eq(handlers("PARTY_KILL"), 1)
		R.SetEnabled(false)
		T.eq(handlers("PARTY_KILL"), 0, "recording off again")
		T.ok(not ns.EventTable().PARTY_KILL, "the event is dropped, not just emptied")
	end)
end)

T.case("Runs section: a pull and the run say how many enemies the group killed", function()
	scenario(function()
		R.SetEnabled(true)
		local run = R.Current()
		RunLog.PullStart(run, ns.Now() + 5)
		RunLog.Observe(run, { { level = 14, class = "normal" } })
		RunLog.GroupKill(run)
		RunLog.GroupKill(run)
		RunLog.PullEnd(run, ns.Now() + 30, 0, false)
		local plan = ns.Plan.New({ name = "Runs", instance = { name = "Test Dungeon", kind = "dungeon", instanceMapID = 9001 } })
		ns.DB.AddPlan(plan)
		local savedPlan = ns.db.ui.selectedPlan
		ns.db.ui.selectedPlan = plan.id
		if not ns.UI.IsShown() then
			ns.UI.Toggle()
		end
		ns.UI.SelectPlan(plan.id)
		ns.UI.SelectTab("runs")
		local panel = _G.DungeonPlannerMainFrame.instancePage.panels.runs.inner
		local lines = {}
		local add = panel.detail.Add
		panel.detail.Add = function(doc, style, text)
			lines[#lines + 1] = text
			return add(doc, style, text)
		end
		panel:Refresh()
		local text = table.concat(lines, "\n")
		panel.detail.Add = add
		ns.DB.DeletePlan(plan.id)
		ns.db.ui.selectedPlan = savedPlan
		T.ok(text:find("2 killed", 1, true), "the run and its pull name the kills: " .. text)
		local _, n = text:gsub("2 killed", "")
		T.eq(n, 2, "once for the run, once for the pull")
	end)
end)

-- /dp scan and /dp debug ---------------------------------------------------------------------------------------------------

T.case("/dp scan: the instance lock's raw readings are plain, secret, nil or missing", function()
	local saved = { lock = _G.GetInstanceLockTimeRemaining, entry = _G.GetInstanceLockTimeRemainingEncounter, request = _G.RequestRaidInfo }
	local function lock()
		local ok, d = pcall(ns.Diagnostics.Collect)
		T.ok(ok, tostring(d))
		T.ok(d.instanceLock, "an instanceLock part")
		return d.instanceLock
	end
	setLock({ { "Boss A", true }, { mock.SECRET, false }, { nil, mock.SECRET } }, { complete = 1 })
	_G.RequestRaidInfo = function() end
	local l = lock()
	T.eq(l.encountersTotal, "3")
	T.eq(l.encountersComplete, "1")
	T.eq(l.timeLeft, "0")
	T.eq(l.previousInstance, "false")
	T.eq(l.requestRaidInfo, "present")
	T.eq(l.encounters[1], "1 plain Boss A | killed true")
	T.eq(l.encounters[2], "2 secret | killed false")
	T.eq(l.encounters[3], "3 nil | killed secret")
	_G.GetInstanceLockTimeRemaining = function()
		return nil
	end
	l = lock()
	T.eq(l.encountersTotal, "nil")
	T.eq(#l.encounters, 1, "the count is not known: the first entry is probed")
	setLock({}, { total = 100 })
	T.eq(#lock().encounters, 12, "bounded")
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter, _G.RequestRaidInfo = nil, nil, nil
	l = lock()
	T.eq(l.timeLeft, "missing")
	T.eq(l.requestRaidInfo, "missing")
	T.eq(l.encounters[1], "1 missing | killed -")
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter = function()
		error("boom")
	end, function()
		error("boom")
	end
	T.eq(lock().timeLeft, "error")
	_G.GetInstanceLockTimeRemaining, _G.GetInstanceLockTimeRemainingEncounter, _G.RequestRaidInfo = saved.lock, saved.entry, saved.request
end)

T.case("/dp debug: every new API and event is checked", function()
	local rows = {}
	for _, row in ipairs(ns.Compat.Report()) do
		rows[row.name] = row
	end
	for _, name in ipairs({ "Instance lock", "Instance lock bosses", "Raid info request", "Reset message", "Event PARTY_KILL",
		"Event UPDATE_INSTANCE_INFO", "Event CHAT_MSG_SYSTEM" }) do
		T.ok(rows[name], "reported: " .. name)
	end
	T.eq(rows["Instance lock"].path, "GetInstanceLockTimeRemaining")
end)
