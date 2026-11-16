-- Progress tracking from game events. The combat log is closed to addons on Forever (docs/COMPATIBILITY.md), so kills
-- come from ENCOUNTER_END (success = 1) and BOSS_KILL. As a fallback signal only, when DBM or BigWigs is loaded, their
-- public kill callbacks count too (guarded, no dependency). One kill is counted once per encounter per few seconds,
-- whichever source reports it first. Runs start and end with instance changes.

local _, ns = ...
local Tracker = ns:NewModule("Tracker")
local Util, Progress = ns.Util, ns.Progress

local DEDUPE = 15 -- seconds
local lastKill = {}

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
	Progress.RecordKill(store(), encounterID, difficultyID, name, ns.Now())
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
	return true
end

local function onZone()
	local current = ns.Instances.Current()
	local now = ns.Now()
	if current.inInstance and current.instanceID then
		local _, isNew = Progress.EnterInstance(store(), tostring(current.instanceID), current.name, current.difficultyID, now)
		if isNew then
			ns:Fire("PROGRESS_CHANGED")
		end
	else
		Progress.LeaveInstance(store(), now)
	end
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
	local function zone()
		if enabled() then
			onZone()
		end
	end
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", zone)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", zone)
	Tracker.sources.dbm = hookDBM() and true or false
	Tracker.sources.bigwigs = hookBigWigs() and true or false
end

function Tracker.EndRun()
	Progress.EndRun(store(), ns.Now())
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
