-- The run recorder's extra sources of enemy names (Tracker/Recorder.lua, Model/RunLog.lua): kill messages read through
-- the client's own format strings, and the target of the player's casts. Listened to only while a run is recorded.
local T = ...
local ns, mock = T.ns, T.mock
local RunLog, R = ns.RunLog, ns.Recorder

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local EVENTS = { "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "UNIT_SPELLCAST_SENT" }

local function listening()
	local n = 0
	for _, event in ipairs(EVENTS) do
		if ns.EventTable()[event] then
			n = n + 1
		end
	end
	return n
end

-- Is any frame (AceEvent's) still registered for the event, so the client sends it?
local function clientDelivers(event)
	for _, f in ipairs(mock.frames) do
		if f._events and f._events[event] then
			return true
		end
	end
	return false
end

T.case("Kill messages: formats become patterns, English and German, positional and escaped", function()
	local english = RunLog.KillPatterns({ "%s dies, you gain %d experience.", "%s dies." })
	T.eq(#english, 2)
	T.eq(RunLog.KilledName(english, "Defias Thug dies, you gain 120 experience."), "Defias Thug")
	T.eq(RunLog.KilledName(english, "Defias Thug dies."), "Defias Thug")
	T.eq(RunLog.KilledName(english, "Ma-gus (the 2nd) [x] 100% dies."), "Ma-gus (the 2nd) [x] 100%", "a name with pattern characters")
	T.eq(RunLog.KilledName(english, "You gain 5 experience."), nil, "another message")
	local german = RunLog.KillPatterns({ "%s stirbt, Ihr erhaltet %d Erfahrung.", "%s stirbt." })
	T.eq(RunLog.KilledName(german, "Gnoll-Wächter stirbt, Ihr erhaltet 85 Erfahrung."), "Gnoll-Wächter")
	T.eq(RunLog.KilledName(german, "Gnoll-Wächter stirbt."), "Gnoll-Wächter")
	T.eq(RunLog.KilledName(german, "Defias Thug dies."), nil, "English text on a German client")
	-- A language that puts the number first: the name is the first argument, not the first capture.
	local positional = RunLog.KillPatterns({ "Ihr erhaltet %2$d Erfahrung, weil %1$s stirbt." })
	T.eq(RunLog.KilledName(positional, "Ihr erhaltet 90 Erfahrung, weil Hogger stirbt."), "Hogger")
	T.eq(#RunLog.KillPatterns({ "You gain %d experience." }), 0, "no name in it: no pattern")
	T.eq(#RunLog.KillPatterns({ "%s dies, %.1f xp." }), 0, "a conversion other than %s and %d: no pattern")
	T.eq(#RunLog.KillPatterns({ "%d xp from %s." }), 0, "the name is not the first argument: no pattern")
	T.eq(RunLog.KilledName(RunLog.KillPatterns({ "%s dies 100%% dead." }), "Rat dies 100% dead."), "Rat", "an escaped percent sign")
	T.eq(RunLog.KilledName(english, 12), nil, "not text")
end)

T.case("Run log: learned names sit beside the nameplates', each once, bounded", function()
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 1000)
	T.eq(RunLog.Learn(run, "Early"), false, "no pull in progress")
	RunLog.PullStart(run, 1010)
	RunLog.Observe(run, { { level = 14, class = "elite", name = "Ghost" } })
	T.ok(RunLog.Learn(run, "Rat"))
	T.eq(RunLog.Learn(run, "Rat"), false, "each name once")
	T.eq(RunLog.Learn(run, mock.SECRET), false, "not a string")
	T.eq(RunLog.Learn(run, ""), false)
	for i = 1, RunLog.MAX_NAMES + 3 do
		RunLog.Learn(run, "Mob " .. i)
	end
	local pull = run.p[1]
	T.eq(#pull.kn, RunLog.MAX_NAMES, "bounded")
	T.eq(#pull.nm, 1, "the nameplates' list is its own")
	T.eq(pull.nm[1], "Ghost", "and is not replaced")
	local shown = RunLog.PullNames(pull)
	T.eq(#shown, RunLog.MAX_NAMES, "shown at most MAX_NAMES")
	T.eq(shown[1], "Ghost", "nameplate names first")
	T.eq(shown[2], "Rat")
	RunLog.Observe(run, { { level = 14, class = "normal", name = "Rat" } })
	T.eq(#RunLog.PullNames(pull), RunLog.MAX_NAMES, "a name both found shows once")
	T.eq(RunLog.PullNames({ nm = { "A", 5, "A" }, kn = "bad" })[2], nil, "junk in a saved pull is skipped")
	RunLog.PullEnd(run, 1040, 0, false)
	local raw = RunLog.PlanFromRun(run, { name = "Hall of Thanes", kind = "dungeon" },
		{ L = ns.L, plural = ns.Plural, date = "today" })
	T.ok(raw.pulls[1].note:find("Ghost, Rat", 1, true), "the draft plan's note names them: " .. raw.pulls[1].note)
end)

T.case("Recorder: name sources are listened to only while a run is recorded in its instance", function()
	boot()
	local saved = { UNITDIESOTHER = rawget(_G, "UNITDIESOTHER"), XP = rawget(_G, "COMBATLOG_XPGAIN_FIRSTPERSON"),
		GetInstanceInfo = _G.GetInstanceInfo }
	_G.UNITDIESOTHER = "%s dies."
	_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
	R.ResetKillPatterns()
	R.SetEnabled(false)
	R.ClearHistory()
	T.eq(listening(), 0, "recording off: nothing listens")
	T.ok(not clientDelivers("UNIT_SPELLCAST_SENT"), "the client does not even send the cast event")
	R.SetEnabled(true)
	local run = R.Current()
	T.ok(run, "inside an instance, a run is recorded")
	T.eq(listening(), #EVENTS, "recording: all three")
	-- Outside the instance the run stays but nothing listens.
	_G.GetInstanceInfo = function()
		return "", "none", 0, "", 0, 0, false, 0
	end
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	T.eq(listening(), 0, "outdoors: nothing listens")
	_G.GetInstanceInfo = saved.GetInstanceInfo
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	T.eq(listening(), #EVENTS, "back inside: listening again")
	R.FinishRun()
	T.eq(listening(), 0, "the run finished: nothing listens")
	R.SetEnabled(true)
	T.eq(listening(), #EVENTS)
	R.SetEnabled(false)
	T.eq(listening(), 0, "recording switched off")
	T.ok(not ns.EventTable().UNIT_SPELLCAST_SENT, "the event is dropped, not just emptied")
	R.ClearHistory()
	_G.UNITDIESOTHER, _G.COMBATLOG_XPGAIN_FIRSTPERSON, _G.GetInstanceInfo = saved.UNITDIESOTHER, saved.XP, saved.GetInstanceInfo
	R.ResetKillPatterns()
end)

T.case("Recorder: kill messages and casts name enemies in the pull in progress; secrets and friends are ignored", function()
	boot()
	local saved = { UNITDIESOTHER = rawget(_G, "UNITDIESOTHER"), XP = rawget(_G, "COMBATLOG_XPGAIN_FIRSTPERSON") }
	_G.UNITDIESOTHER = "%s dies."
	_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
	R.ResetKillPatterns()
	R.SetEnabled(false)
	R.ClearHistory()
	R.SetEnabled(true)
	local run = R.Current()
	mock.units = {
		nameplate1 = { level = 14, class = "elite", name = mock.SECRET, hostile = true, combat = true },
		target = { level = 14, class = "elite", name = mock.SECRET, hostile = true },
		party1 = { name = "Healbot" },
	}
	mock.plates = { "nameplate1" }
	-- Between pulls nothing is learned.
	mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Early Bird dies.")
	mock.inCombat = true
	mock.FireEvent("PLAYER_REGEN_DISABLED")
	T.ok(RunLog.OpenPull(run))
	T.eq(run.p[1].kn, nil, "nothing learned before the pull")
	mock.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 120 experience.")
	mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Defias Thug dies.")
	mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Defias Mage dies.")
	T.eq(table.concat(run.p[1].kn, ","), "Defias Thug,Defias Mage", "the experience and death messages name the same kill once")
	-- A secret message is dropped whole.
	mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", mock.SECRET)
	mock.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", mock.SECRET)
	T.eq(#run.p[1].kn, 2, "a secret message is ignored")
	-- Casts: the cast's target name counts only when it is the player's hostile target's plain name.
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "Gnoll Brute", "cast-guid", 133)
	T.eq(#run.p[1].kn, 2, "the target's name is secret: a cast's name cannot be matched to it")
	mock.units.target.name = "Gnoll Brute"
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "Gnoll Brute", "cast-guid", 133)
	T.eq(run.p[1].kn[3], "Gnoll Brute", "the target of the player's cast")
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "Healbot", "cast-guid", 133)
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "Tester", "cast-guid", 133)
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", mock.SECRET, "cast-guid", 133)
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "cast-guid", 133)
	mock.FireEvent("UNIT_SPELLCAST_SENT", "party1", "Gnoll Shaman", "cast-guid", 133)
	mock.FireEvent("UNIT_SPELLCAST_SENT", mock.SECRET, "Gnoll Shaman", "cast-guid", 133)
	T.eq(#run.p[1].kn, 3, "a hostile target, but the cast names an ally, the player, a secret or empty name, or another unit's cast")
	mock.units.target.hostile, mock.units.target.name = false, "Friendly Vendor"
	mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "Friendly Vendor", "cast-guid", 133)
	T.eq(#run.p[1].kn, 3, "a friendly target is not an enemy")
	mock.units.target.hostile = true
	for i = 1, RunLog.MAX_NAMES + 2 do
		mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Extra " .. i .. " dies.")
	end
	T.eq(#run.p[1].kn, RunLog.MAX_NAMES, "bounded")
	mock.Advance(0.6)
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	local pull = run.p[1]
	T.eq(pull.c, 1, "the nameplates' count is untouched")
	T.eq(pull.nm, nil, "and so are their names (secret here)")
	mock.FireEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Late Bird dies.")
	T.eq(#pull.kn, RunLog.MAX_NAMES, "a finished pull is not changed")
	T.ok(not (function(v)
		local function holds(x, depth)
			if x == mock.SECRET then
				return true
			end
			if type(x) == "table" and depth < 12 then
				for k, y in pairs(x) do
					if holds(k, depth + 1) or holds(y, depth + 1) then
						return true
					end
				end
			end
			return false
		end
		return holds(v, 0)
	end)(R.Store()), "no secret value reached SavedVariables")
	R.SetEnabled(false)
	R.ClearHistory()
	mock.units, mock.plates, mock.inCombat = {}, {}, false
	_G.UNITDIESOTHER, _G.COMBATLOG_XPGAIN_FIRSTPERSON = saved.UNITDIESOTHER, saved.XP
	R.ResetKillPatterns()
end)

T.case("Recorder: a client without the format strings reads no kill messages", function()
	local saved = { UNITDIESOTHER = rawget(_G, "UNITDIESOTHER"), XP = rawget(_G, "COMBATLOG_XPGAIN_FIRSTPERSON") }
	_G.UNITDIESOTHER, _G.COMBATLOG_XPGAIN_FIRSTPERSON = nil, nil
	R.ResetKillPatterns()
	T.eq(#R.KillPatterns(), 0)
	_G.UNITDIESOTHER = "%s dies."
	R.ResetKillPatterns()
	T.eq(#R.KillPatterns(), 1, "each global on its own")
	_G.UNITDIESOTHER, _G.COMBATLOG_XPGAIN_FIRSTPERSON = saved.UNITDIESOTHER, saved.XP
	R.ResetKillPatterns()
end)

T.case("Compat: /dp debug reports the new events and format strings", function()
	local rows, found = ns.Compat.Report(), {}
	for _, row in ipairs(rows) do
		found[row.name] = row
	end
	for _, event in ipairs(EVENTS) do
		T.ok(found["Event " .. event] and found["Event " .. event].ok, event)
	end
	T.ok(found["Kill message: death"] and found["Kill message: experience"], "the format strings")
	T.ok(found["Secrets API"] and found["Addon restriction state"] and found["Unit distance"], "the scan's probes")
end)

T.case("Run log: a pull whose enemy a kill message named is kept even with no nameplate count", function()
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "3065", "Hall of Thanes", 1, 1000)
	RunLog.PullStart(run, 1010)
	T.ok(RunLog.Learn(run, "Defias Thug"))
	T.ok(RunLog.PullEnd(run, 1030, 0, false), "kept")
	T.eq(run.p[1].c, 0)
	RunLog.PullStart(run, 1100)
	T.eq(RunLog.PullEnd(run, 1110, 0, false), nil, "nothing seen and nothing named: dropped")
	T.eq(#run.p, 1)
end)

T.case("Events: removing a handler leaves the others; the last one unregisters the event", function()
	boot()
	local event, calls = "DP_TEST_EVENT", {}
	local function a()
		calls[#calls + 1] = "a"
	end
	local function b()
		calls[#calls + 1] = "b"
	end
	T.ok(ns:RegisterEvent(event, a))
	T.ok(ns:RegisterEvent(event, b))
	mock.FireEvent(event)
	T.eq(table.concat(calls), "ab")
	ns:UnregisterEvent(event, a)
	calls = {}
	mock.FireEvent(event)
	T.eq(table.concat(calls), "b", "the other handler still runs")
	T.ok(ns.EventTable()[event], "and the event stays registered")
	ns:UnregisterEvent(event, a)
	ns:UnregisterEvent("DP_NEVER_REGISTERED", a)
	T.eq(#ns.EventTable()[event], 1, "a handler that was not registered changes nothing")
	T.eq(ns.EventTable().DP_NEVER_REGISTERED, nil)
	-- Registered twice, it runs twice and one call removes both.
	ns:RegisterEvent(event, a)
	ns:RegisterEvent(event, a)
	calls = {}
	mock.FireEvent(event)
	T.eq(table.concat(calls), "baa")
	ns:UnregisterEvent(event, a)
	calls = {}
	mock.FireEvent(event)
	T.eq(table.concat(calls), "b", "every registration of the handler is gone")
	ns:UnregisterEvent(event, b)
	T.eq(ns.EventTable()[event], nil, "the last handler takes the event with it")
	T.ok(not clientDelivers(event), "the client is told to stop")
	calls = {}
	mock.FireEvent(event)
	T.eq(#calls, 0, "and the game no longer delivers it")
end)

T.case("Perf: an event unregistered during a probe stays unregistered when the probe stops", function()
	boot()
	local Perf = ns.Perf
	local event, ran = "DP_TEST_PROBE_EVENT", 0
	local function handler()
		ran = ran + 1
	end
	ns:RegisterEvent(event, handler)
	T.ok(Perf.Start())
	mock.FireEvent(event)
	T.eq(ran, 1, "timed, and still delivered")
	ns:UnregisterEvent(event, handler)
	Perf.Stop()
	mock.FireEvent(event)
	T.eq(ran, 1, "not delivered again after the stop")
	T.eq(ns.EventTable()[event], nil)
	T.ok(not clientDelivers(event), "and the client no longer sends it to the addon")
	Perf.Reset()
end)

T.case("Recorder: switching recording off removes the sources even when it was not through SetEnabled", function()
	boot()
	R.SetEnabled(false)
	R.ClearHistory()
	R.SetEnabled(true)
	T.eq(listening(), #EVENTS)
	ns.db.settings.recorder.enabled = false
	R.OnZone()
	T.eq(listening(), 0, "a zone change with recording off drops them")
	R.SetEnabled(false)
	R.ClearHistory()
end)
