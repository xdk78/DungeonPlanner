-- Progress tracking from game events. The combat log is closed to addons on Forever (docs/COMPATIBILITY.md), so kills
-- come from ENCOUNTER_END (success = 1) and BOSS_KILL. As a fallback signal only, when DBM or BigWigs is loaded, their
-- public kill callbacks count too (guarded, no dependency). One kill is counted once per encounter per few seconds,
-- whichever source reports it first. Runs start and end with instance changes.
--
-- Two more things come from the client's own words about the instance (docs/COMPATIBILITY.md, sections 3 and 10):
--   * Bosses already dead when the player enters or joins: the instance's lock (GetInstanceLockTimeRemaining and
--     ...Encounter) lists its bosses by name and whether each is killed. They are matched to the plans' bosses by plain
--     name, never guessed, and marked killed in this run as "found dead" (Progress.MarkDeadOnJoin), not as the
--     player's kills.
--   * A reset: the system message INSTANCE_RESET_SUCCESS ("%s has been reset.") names the instance. A boss that starts
--     (ENCOUNTER_START) though this run has it dead also means a new copy of the instance. Both end the run, and
--     INSTANCE_RESET tells the recorder and run mode.
-- Neither listens while idle: the lock events are registered only inside the instance of a run, the system message
-- only while a run exists.

local _, ns = ...
local Tracker = ns:NewModule("Tracker")
local Util, Progress, Match = ns.Util, ns.Progress, ns.Match

local DEDUPE = 15 -- seconds
local lastKill = {}

Tracker.LOCK_MAX = 40
Tracker.LOCK_REQUEST_EVERY = 10 -- seconds between two RequestRaidInfo calls
Tracker.NEW_COPY_GRACE = 30 -- seconds: a boss killed this recently that starts again is a late or repeated event

local function enabled()
	return ns.db and ns.db.settings.tracker.enabled and not ns.DB.IsReadOnly()
end

local function store()
	return ns.char.progress
end

function Tracker.RecordKill(encounterID, name, difficultyID, source)
	encounterID, name, difficultyID = Util.Plain(encounterID), Util.Plain(name), Util.Plain(difficultyID)
	if not Util.IsInteger(encounterID) or not enabled() then
		return false
	end
	local clock = ns.Clock()
	if lastKill[encounterID] and clock - lastKill[encounterID] < DEDUPE then
		return false
	end
	lastKill[encounterID] = clock
	if not Util.IsInteger(difficultyID) then
		difficultyID = ns.Instances.Current().difficultyID
	end
	Progress.RecordKill(store(), encounterID, difficultyID, name, ns.Now(), source == "manual")
	ns:Fire("PROGRESS_CHANGED", encounterID)

	local planId
	for _, plan in pairs(ns.db.plans) do
		local enc = ns.Plan.FindEncounterByGameID(plan, encounterID, ns.Journal.GameIdOf(plan))
		if enc then
			planId = plan.id
			if ns.db.settings.tracker.announceKills then
				ns:Print(string.format(ns.L["%s defeated (plan: %s)."], ns.Names.Encounter(enc), plan.name))
			end
			break
		end
	end
	ns:FirePublic("DUNGEONPLANNER_BOSS_KILLED", encounterID, type(name) == "string" and name or nil, planId)
	ns:Fire("BOSS_KILLED", encounterID, type(name) == "string" and name or nil)
	ns:Debug("kill", encounterID, source or "event")
	-- The lock may list other bosses dead now (a lock that updated late).
	Tracker.ReadDeadBosses(true)
	return true
end

local syncSources

local wasInside = false

local function onZone()
	local current = ns.Instances.Current()
	local now = ns.Now()
	if current.inInstance and current.instanceID then
		local _, isNew = Progress.EnterInstance(store(), tostring(current.instanceID), current.name, current.difficultyID, now)
		if isNew then
			ns:Fire("PROGRESS_CHANGED")
		end
		wasInside = true
	else
		-- Stamped when the player leaves, not by every outdoor event: a login would else make an old run fresh again.
		if wasInside then
			Progress.LeaveInstance(store(), now)
		end
		wasInside = false
	end
	syncSources()
end

-- The lock's bosses as the client lists them, { { name, killed }, ... }, or nil when the API is missing, does not say
-- how many there are, or describes a previous instance. A secret name is no name, a secret flag is not "killed".
function Tracker.ReadLock()
	local lock, encounter = rawget(_G, "GetInstanceLockTimeRemaining"), rawget(_G, "GetInstanceLockTimeRemainingEncounter")
	if type(lock) ~= "function" or type(encounter) ~= "function" then
		return nil
	end
	local ok, _, previous, total = pcall(lock)
	total = ok and Util.Plain(total) or nil
	if not Util.IsInteger(total) or total < 1 or Util.Plain(previous) == true then
		return nil
	end
	local entries = {}
	for i = 1, math.min(total, Tracker.LOCK_MAX) do
		local okEntry, name, _, killed = pcall(encounter, i)
		if okEntry then
			name, killed = Util.Plain(name), Util.Plain(killed)
			entries[#entries + 1] = { name = type(name) == "string" and name or nil, killed = killed }
		end
	end
	return entries
end

-- The bosses of the plans (saved and recommended) made for this instance, { { id = encounterID, names = { ... } } }.
-- A boss goes by the journal's name or the plan's own, and by the name ENCOUNTER_END gave at an earlier kill: the only
-- one in the client's language while the journal is empty.
local function hereBosses(current)
	local bosses, byId = {}, {}
	local function scan(plan)
		if not ns.Instances.IsHere(plan, current) then
			return
		end
		local idOf = ns.Journal.GameIdOf(plan)
		for _, enc in ipairs(plan.encounters) do
			local id = idOf(enc)
			if Util.IsInteger(id) then
				local boss = byId[id]
				if not boss then
					boss = { id = id, names = { Progress.NameOf(store(), id) } }
					byId[id] = boss
					bosses[#bosses + 1] = boss
				end
				boss.names[#boss.names + 1] = ns.Names.Encounter(enc)
			end
		end
	end
	for _, plan in pairs(ns.db.plans) do
		scan(plan)
	end
	for _, plan in ipairs(ns.Bundled.All()) do
		scan(plan)
	end
	return bosses
end

local lastRequest

-- Is the boss dead in this run by something the game said (a kill it reported, or the lock), and not just marked by
-- hand? A kill the player made only just now does not count: the lock and the events can lag.
local function provenDead(encounterID)
	local at = Progress.KilledAt(store(), encounterID)
	return at ~= nil and not Progress.MarkedByHand(store(), encounterID)
		and (Progress.WasDeadOnJoin(store(), encounterID) or ns.Now() - at >= Tracker.NEW_COPY_GRACE)
end

-- Mark the bosses the lock says are dead in this run. `request` first asks the game for fresh lock data (its answer,
-- UPDATE_INSTANCE_INFO, reads again without asking). `entering`: the player just came in; a boss this run has dead that
-- the lock lists alive means the instance is another copy than the run's (it was reset since), so the run ends first.
-- Returns the encounter IDs newly marked.
function Tracker.ReadDeadBosses(request, entering)
	local run = enabled() and store().run
	local current = run and ns.Instances.Current()
	if not (current and current.inInstance and tostring(current.instanceID) == run.key) then
		return {}
	end
	local requestRaidInfo, clock = rawget(_G, "RequestRaidInfo"), ns.Clock()
	if request and type(requestRaidInfo) == "function" and (not lastRequest or clock - lastRequest >= Tracker.LOCK_REQUEST_EVERY) then
		lastRequest = clock
		pcall(requestRaidInfo)
	end
	local entries = Tracker.ReadLock()
	local bosses = entries and hereBosses(current) or {}
	if entering then
		for _, id in ipairs(Progress.AliveByName(entries or {}, bosses)) do
			if provenDead(id) then
				Tracker.NewCopy(run.name, run.key)
				break
			end
		end
	end
	local found = {}
	for _, id in ipairs(entries and Progress.DeadByName(entries, bosses) or {}) do
		if Progress.MarkDeadOnJoin(store(), id, ns.Now()) then
			found[#found + 1] = id
		end
	end
	if #found > 0 then
		ns:Fire("PROGRESS_CHANGED")
		ns:Fire("BOSSES_FOUND_DEAD", found)
	end
	return found
end

-- The old copy's run is archived; inside an instance a new run starts at once. The recorder and run mode follow
-- INSTANCE_RESET.
function Tracker.NewCopy(name, key)
	Progress.EndRun(store(), ns.Now())
	for id in pairs(lastKill) do
		lastKill[id] = nil
	end
	onZone()
	ns:Fire("PROGRESS_CHANGED")
	ns:Fire("INSTANCE_RESET", name, key)
end

local resetPattern

-- The instance a system message says was reset, or nil: the client's own INSTANCE_RESET_SUCCESS ("%s has been reset.")
-- as a pattern, so it reads in every language.
function Tracker.ResetName(text)
	if type(text) ~= "string" then
		return nil
	end
	if resetPattern == nil then
		local pattern, at = ns.RunLog.FormatPattern(rawget(_G, "INSTANCE_RESET_SUCCESS"))
		resetPattern = pattern and { pattern = pattern, at = at } or false
	end
	local name = resetPattern and ({ text:match(resetPattern.pattern) })[resetPattern.at]
	return name ~= "" and name or nil
end

-- Tests change the global.
function Tracker.ResetPatterns()
	resetPattern = nil
end

function Tracker.OnInstanceReset(name)
	local run = enabled() and store().run
	if not run or Match.Norm(name) == "" or Match.Norm(run.name) ~= Match.Norm(name) then
		return false
	end
	Tracker.NewCopy(run.name, run.key)
	return true
end

-- A boss starts that this run has dead: a new copy, unless the kill is the player's own and only just happened. A
-- wiped boss is not dead, so a retry never gets here. A boss marked dead by hand that starts is alive: only that mark
-- goes, never the run.
function Tracker.OnEncounterStart(encounterID)
	encounterID = Util.Plain(encounterID)
	local run = enabled() and store().run
	if not (run and Util.IsInteger(encounterID)) then
		return false
	end
	if Progress.DropMark(store(), encounterID) then
		ns:Fire("PROGRESS_CHANGED")
		return false
	end
	if not provenDead(encounterID) then
		return false
	end
	Tracker.NewCopy(run.name, run.key)
	return true
end

-- A reset message can come while a run exists that the player was in lately; the lock's updates and encounters
-- starting matter only inside the run's instance. Outside both, nothing is registered.
local GROUPS = {
	run = { events = { { "CHAT_MSG_SYSTEM", function(_, text)
		local run = enabled() and store().run
		if not (run and Progress.Fresh(run, ns.Now())) then
			syncSources() -- the run was left long ago: stop listening
		end
		local name = Tracker.ResetName(Util.Plain(text))
		if name then
			Tracker.OnInstanceReset(name)
		end
	end } } },
	inside = { events = { { "UPDATE_INSTANCE_INFO", function()
		Tracker.ReadDeadBosses(false)
	end }, { "INSTANCE_LOCK_START", function()
		Tracker.ReadDeadBosses(false)
	end }, { "ENCOUNTER_START", function(_, encounterID)
		Tracker.OnEncounterStart(encounterID)
	end } } },
}

local function listen(group, want)
	if group.on == want then
		return
	end
	group.on = want
	for _, e in ipairs(group.events) do
		if want then
			ns:RegisterEvent(e[1], e[2])
		else
			ns:UnregisterEvent(e[1], e[2])
		end
	end
end

function syncSources()
	local run = enabled() and store().run
	local current = run and ns.Instances.Current()
	local inside = current and current.inInstance and tostring(current.instanceID) == run.key or false
	listen(GROUPS.run, run and (inside or Progress.Fresh(run, ns.Now())) and true or false)
	listen(GROUPS.inside, inside)
end

-- DBM: DBM:RegisterCallback("DBM_Kill", fn(event, mod)); mod.combatInfo.eId / mod.encounterId is the encounter ID.
local function hookDBM()
	local DBM = _G.DBM
	if type(DBM) ~= "table" or type(DBM.RegisterCallback) ~= "function" then
		return false
	end
	return pcall(DBM.RegisterCallback, DBM, "DBM_Kill", function(_, mod)
		if type(mod) ~= "table" then
			return
		end
		local id = mod.encounterId or (type(mod.combatInfo) == "table" and mod.combatInfo.eId)
		if type(id) == "table" then
			id = id[1]
		end
		ns.SafeCall(Tracker.RecordKill, tonumber(id), nil, nil, "DBM")
	end)
end

-- BigWigs: BigWigsLoader.RegisterMessage(owner, "BigWigs_OnBossWin", fn(event, module)); module.engageId.
local function hookBigWigs()
	local loader = _G.BigWigsLoader
	if type(loader) ~= "table" or type(loader.RegisterMessage) ~= "function" then
		return false
	end
	return pcall(loader.RegisterMessage, Tracker, "BigWigs_OnBossWin", function(_, module)
		if type(module) == "table" then
			ns.SafeCall(Tracker.RecordKill, tonumber(module.engageId), nil, nil, "BigWigs")
		end
	end)
end

Tracker.sources = {}

function Tracker.Init()
	ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, _, success)
		if Util.Plain(success) == 1 then
			Tracker.RecordKill(encounterID, encounterName, difficultyID, "ENCOUNTER_END")
		end
	end)
	ns:RegisterEvent("BOSS_KILL", function(_, encounterID, encounterName)
		Tracker.RecordKill(encounterID, encounterName, nil, "BOSS_KILL")
	end)
	local function zone(entering)
		if enabled() then
			onZone()
			Tracker.ReadDeadBosses(true, entering)
		end
	end
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		zone(true)
	end)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		zone(false)
	end)
	Tracker.sources.dbm = hookDBM() and true or false
	Tracker.sources.bigwigs = hookBigWigs() and true or false
end

function Tracker.EndRun()
	Progress.EndRun(store(), ns.Now())
	syncSources()
	ns:Fire("PROGRESS_CHANGED")
end

-- Manual "boss killed" (keybinding / Progress tab): the next boss of the active plan not yet killed in this run.
function Tracker.MarkNextBossKilled()
	local plan = ns.DB.GetPlan(ns.db.ui.selectedPlan)
	if not plan then
		return nil
	end
	local idOf = ns.Journal.GameIdOf(plan)
	for _, enc in ipairs(plan.encounters) do
		local id = idOf(enc)
		if id and not Progress.IsKilledInRun(store(), id) then
			lastKill[id] = nil
			Tracker.RecordKill(id, ns.Names.Encounter(enc), nil, "manual")
			return enc
		end
	end
	return nil
end
