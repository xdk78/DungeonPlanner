-- Progress: boss kills, runs and plan objectives, per character. Pure; Tracker.lua feeds it game events.
--
-- The store (DungeonPlannerCharDB.progress):
--   kills      ["<encounterID>:<difficultyID>"] = { name, count, first, last }   lifetime, per difficulty
--   run        the current instance run or nil: { key, name, difficultyID, started, kills = { [encounterID] = time },
--              pre = { [encounterID] = true } }; `pre` lists the kills that were already there when the player joined
--              (the instance's lock says the boss is dead): they count as killed, but they are not the player's kills;
--              hand = { [encounterID] = true }, the kills the player marked by hand (the game did not report them)
--   history    finished runs, newest last, at most MAX_HISTORY
--   objectives [planId] = { [objectiveId] = true }
-- A run is "the same" while the player stays in, or comes back to, the same instance within RESUME seconds.

local _, ns = ...
local Progress = ns:NewModule("Progress")
local Util, Match = ns.Util, ns.Match

Progress.MAX_HISTORY = 50
Progress.RESUME = 30 * 60

function Progress.NewStore()
	return { kills = {}, run = nil, history = {}, objectives = {} }
end

-- Repair a store loaded from SavedVariables (wrong types become empty).
function Progress.Normalize(store)
	if type(store) ~= "table" then
		return Progress.NewStore()
	end
	if type(store.kills) ~= "table" then
		store.kills = {}
	end
	if type(store.history) ~= "table" then
		store.history = {}
	end
	if type(store.objectives) ~= "table" then
		store.objectives = {}
	end
	if store.run ~= nil and (type(store.run) ~= "table" or type(store.run.kills) ~= "table") then
		store.run = nil
	end
	for _, field in ipairs({ "pre", "hand" }) do
		if store.run and type(store.run[field]) ~= "table" then
			store.run[field] = nil
		end
	end
	for key, rec in pairs(store.kills) do
		if type(rec) ~= "table" or type(rec.count) ~= "number" then
			store.kills[key] = nil
		end
	end
	for i = #store.history, 1, -1 do
		if type(store.history[i]) ~= "table" or type(store.history[i].kills) ~= "table" then
			table.remove(store.history, i)
		end
	end
	return store
end

local function killKey(encounterID, difficultyID)
	return tostring(encounterID) .. ":" .. tostring(difficultyID or 0)
end
Progress.KillKey = killKey

-- An ENCOUNTER_END with success, or a BOSS_KILL; `byHand` for the player's own mark (the "Boss killed" binding), which
-- the game did not report. Returns the kill record.
function Progress.RecordKill(store, encounterID, difficultyID, name, now, byHand)
	if not Util.IsInteger(encounterID) then
		return nil
	end
	local key = killKey(encounterID, difficultyID)
	local rec = store.kills[key]
	if not rec then
		rec = { name = "", count = 0, first = now }
		store.kills[key] = rec
	end
	rec.count = rec.count + 1
	rec.last = now
	if type(name) == "string" and name ~= "" then
		rec.name = Util.CleanText(name, 64) or rec.name
	end
	local run = store.run
	if run then
		run.kills[encounterID] = now
		if run.pre then
			run.pre[encounterID] = nil -- the player killed it after all
		end
		if byHand then
			run.hand = run.hand or {}
			run.hand[encounterID] = true
		elseif run.hand then
			run.hand[encounterID] = nil
		end
	end
	return rec
end

-- Was the boss's kill in this run only marked by hand?
function Progress.MarkedByHand(store, encounterID)
	local run = store.run
	return run ~= nil and run.hand ~= nil and run.hand[encounterID] == true
end

-- Take back a mark made by hand (the boss turned out to be alive). The lifetime count stays.
function Progress.DropMark(store, encounterID)
	local run = store.run
	if run and run.hand and run.hand[encounterID] then
		run.hand[encounterID] = nil
		run.kills[encounterID] = nil
		return true
	end
	return false
end

-- Has the run been in its instance within RESUME seconds of `now`?
function Progress.Fresh(run, now)
	return now - (run.seen or run.started) <= Progress.RESUME
end

-- A boss the instance's lock reports dead that the player did not kill: killed in this run, but not among the player's
-- kills (store.kills). Returns whether it was new.
function Progress.MarkDeadOnJoin(store, encounterID, now)
	local run = store.run
	if not (run and Util.IsInteger(encounterID)) or run.kills[encounterID] ~= nil then
		return false
	end
	run.kills[encounterID] = now
	run.pre = run.pre or {}
	run.pre[encounterID] = true
	return true
end

function Progress.WasDeadOnJoin(store, encounterID)
	local run = store.run
	return run ~= nil and run.pre ~= nil and run.pre[encounterID] == true
end

function Progress.KilledAt(store, encounterID)
	local run = store.run
	return run and run.kills[encounterID] or nil
end

-- Total kills of an encounter over every difficulty, and the latest kill time.
function Progress.KillsOf(store, encounterID)
	local count, last = 0, nil
	local prefix = tostring(encounterID) .. ":"
	for key, rec in pairs(store.kills) do
		if key:sub(1, #prefix) == prefix then
			count = count + rec.count
			if not last or (rec.last and rec.last > last) then
				last = rec.last
			end
		end
	end
	return count, last
end

-- The name the client gave a boss when the player last killed it (ENCOUNTER_END's, in the client's language), or nil.
function Progress.NameOf(store, encounterID)
	local name, last = nil, nil
	local prefix = tostring(encounterID) .. ":"
	for key, rec in pairs(store.kills) do
		if key:sub(1, #prefix) == prefix and rec.name ~= "" and (not last or (rec.last or 0) > last) then
			name, last = rec.name, rec.last or 0
		end
	end
	return name
end

-- Which bosses the instance's lock lists with the given state. entries = { { name = plain string or nil, killed =
-- boolean or nil } }, bosses = { { id = encounterID, names = { ... } } }. The lock gives no ID, so a boss matches by
-- its plain name, and only when that name belongs to exactly one boss: a secret, missing, unknown or shared name marks
-- nothing, and so does a flag that is not plainly true or false.
local function matchByName(entries, bosses, killed)
	local byName = {} -- normalized name -> encounterID, or false when two bosses have it
	for _, boss in ipairs(bosses) do
		for _, name in ipairs(boss.names) do
			local key = Match.Norm(name)
			if key ~= "" then
				if byName[key] == nil or byName[key] == boss.id then
					byName[key] = boss.id
				else
					byName[key] = false
				end
			end
		end
	end
	local out, seen = {}, {}
	for _, e in ipairs(entries) do
		local id = e.killed == killed and type(e.name) == "string" and byName[Match.Norm(e.name)] or nil
		if id and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

function Progress.DeadByName(entries, bosses)
	return matchByName(entries, bosses, true)
end

function Progress.AliveByName(entries, bosses)
	return matchByName(entries, bosses, false)
end

-- Entering an instance: resume the current run if it is the same instance and recent, otherwise archive it and start
-- a new one. `key` identifies the instance (its instanceID from GetInstanceInfo, as a string).
function Progress.EnterInstance(store, key, name, difficultyID, now)
	local run = store.run
	if run and run.key == key and run.difficultyID == difficultyID and Progress.Fresh(run, now) then
		run.seen = now
		return run, false
	end
	Progress.EndRun(store, now)
	run = {
		key = key,
		name = Util.CleanText(name or "", 64) or "",
		difficultyID = difficultyID,
		started = now,
		seen = now,
		kills = {},
	}
	store.run = run
	return run, true
end

-- Leaving: keep the run (the player may come back), just stamp when it was last seen.
function Progress.LeaveInstance(store, now)
	if store.run then
		store.run.seen = now
	end
end

function Progress.EndRun(store, now)
	local run = store.run
	if not run then
		return nil
	end
	store.run = nil
	if next(run.kills) then
		run.ended = now
		store.history[#store.history + 1] = run
		while #store.history > Progress.MAX_HISTORY do
			table.remove(store.history, 1)
		end
	end
	return run
end

function Progress.IsKilledInRun(store, encounterID)
	return store.run ~= nil and store.run.kills[encounterID] ~= nil
end

-- Objectives -------------------------------------------------------------------------------------------------------------

function Progress.SetObjective(store, planId, objectiveId, done)
	local plan = store.objectives[planId]
	if not plan then
		plan = {}
		store.objectives[planId] = plan
	end
	plan[objectiveId] = done and true or nil
	if not next(plan) then
		store.objectives[planId] = nil
	end
end

function Progress.IsObjectiveDone(store, planId, objectiveId)
	local plan = store.objectives[planId]
	return plan ~= nil and plan[objectiveId] == true
end

function Progress.ResetObjectives(store, planId)
	store.objectives[planId] = nil
end

-- Summary for a plan: objectives done / total, bosses killed in the current run / all the plan's bosses. `idOf(enc)`
-- (optional) gives a boss's encounter ID when the plan has none (the UI asks the Adventure Guide); without one a boss
-- counts but cannot be killed.
function Progress.PlanSummary(store, plan, idOf)
	local done = 0
	for _, o in ipairs(plan.objectives) do
		if Progress.IsObjectiveDone(store, plan.id, o.id) then
			done = done + 1
		end
	end
	local bosses, killed = 0, 0
	for _, enc in ipairs(plan.encounters) do
		bosses = bosses + 1
		local id = enc.dungeonEncounterID or (idOf and idOf(enc))
		if id and Progress.IsKilledInRun(store, id) then
			killed = killed + 1
		end
	end
	return { objectivesDone = done, objectives = #plan.objectives, bossesKilled = killed, bosses = bosses }
end
