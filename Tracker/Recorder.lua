-- The run recorder (opt-in, off by default): records a dungeon run from what the client exposes inside an instance
-- (docs/COMPATIBILITY.md section 10) into Model/RunLog.lua's store. Event-driven and cheap:
--   PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA  start or continue a run inside a dungeon or raid
--   PLAYER_REGEN_DISABLED / ENABLED                one pull = one combat segment
--   a 0.5 s ticker, only while in combat           enemy nameplates: count, level and classification (names only when
--                                                 they are not secret); never positions, never GUIDs
--   ENCOUNTER_END / BOSS_KILL                      boss kills with timing; a failed encounter is a wipe
--   CHAT_MSG_COMBAT_XP_GAIN / _HOSTILE_DEATH,      names of enemies fought, only while a run is being recorded
--   UNIT_SPELLCAST_SENT                            (inside its instance), for the pull in progress
-- Nothing runs while idle or out of combat, and nothing here touches protected frames.

local _, ns = ...
local Recorder = ns:NewModule("Recorder")
local Util, RunLog = ns.Util, ns.RunLog

Recorder.SCAN_EVERY = 0.5
Recorder.MAX_PLATES = 40

local ticker
Recorder.api = {} -- what this client allowed in the last scan (for /dp debug): { namePlates, names = "plain"|"secret" }

function Recorder.Enabled()
	return ns.db ~= nil and ns.db.settings.recorder.enabled and not ns.DB.IsReadOnly()
end

function Recorder.Store()
	local char = ns.char
	if not char then
		return nil
	end
	if type(char.recorder) ~= "table" or type(char.recorder.runs) ~= "table" then
		char.recorder = RunLog.Normalize(char.recorder)
	end
	return char.recorder
end

function Recorder.Current()
	local store = Recorder.Store()
	return store and store.current or nil
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Util.Plain(a), Util.Plain(b), Util.Plain(c)
end

-- The nameplate units of hostile, living enemies. Each value is read on its own and dropped when secret.
function Recorder.ScanPlates()
	local np = rawget(_G, "C_NamePlate")
	local plates = np and type(np.GetNamePlates) == "function" and select(2, pcall(np.GetNamePlates)) or nil
	Recorder.api.namePlates = type(plates) == "table"
	local units = {}
	if type(plates) ~= "table" then
		return units
	end
	for i = 1, math.min(#plates, Recorder.MAX_PLATES) do
		local plate = plates[i]
		local unit = type(plate) == "table" and (Util.Plain(plate.namePlateUnitToken)
			or (type(plate.UnitFrame) == "table" and Util.Plain(plate.UnitFrame.unit))) or nil
		if type(unit) == "string" then
			local hostile = call(UnitCanAttack, "player", unit)
			local dead = call(UnitIsDead, unit)
			local fighting = call(UnitAffectingCombat, unit)
			-- Only enemies in combat count; when the client hides the combat flag, every hostile plate counts.
			if hostile == true and dead ~= true and fighting ~= false then
				-- An enemy's name is secret in combat: it may be handed on (to issecretvalue), never compared, not
				-- even with nil.
				local okName, name = pcall(UnitName, unit)
				local secret = okName and Util.IsSecret(name)
				local plainName = okName and not secret and name or nil
				if secret then
					Recorder.api.names = "secret"
				elseif plainName ~= nil then
					Recorder.api.names = "plain"
				end
				units[#units + 1] = { level = call(UnitLevel, unit), class = call(UnitClassification, unit),
					name = type(plainName) == "string" and plainName or nil }
			end
		end
	end
	return units
end

local function scan()
	local run = Recorder.Current()
	if run and RunLog.OpenPull(run) then
		RunLog.Observe(run, Recorder.ScanPlates())
		ns:Fire("RECORDER_CHANGED")
	end
end

local function stopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Enemy names for the pull in progress where nameplate names are secret: the client's kill messages and the target of
-- the player's own casts. A secret message or name is dropped.

-- Format strings whose first argument is the dead enemy's name; each is looked up alone, so a client without one loses
-- only that pattern.
Recorder.KILL_TEXTS = { "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
	"UNITDIESOTHER" }

local killPatterns

function Recorder.KillPatterns()
	if not killPatterns then
		local formats = {}
		for _, name in ipairs(Recorder.KILL_TEXTS) do
			local format = rawget(_G, name)
			if type(format) == "string" then
				formats[#formats + 1] = format
			end
		end
		killPatterns = RunLog.KillPatterns(formats)
	end
	return killPatterns
end

-- Tests change the globals.
function Recorder.ResetKillPatterns()
	killPatterns = nil
end

local function onKillMessage(_, text)
	local run = Recorder.Current()
	if run and RunLog.OpenPull(run) then
		RunLog.Learn(run, RunLog.KilledName(Recorder.KillPatterns(), Util.Plain(text)))
	end
end

-- A cast can name a mouseover, a focus or an ally by name, so its target is taken only when it is the player's own
-- hostile target: the same plain name as UnitName("target"), which is nil while the client keeps it secret.
local function onCastSent(_, unit, target)
	local run = Recorder.Current()
	target = Util.Plain(target)
	if not (Util.Plain(unit) == "player" and type(target) == "string" and target ~= "" and run and RunLog.OpenPull(run)) then
		return
	end
	if call(UnitName, "target") == target and call(UnitCanAttack, "player", "target") == true then
		RunLog.Learn(run, target)
	end
end

local SOURCES = { { "CHAT_MSG_COMBAT_XP_GAIN", onKillMessage }, { "CHAT_MSG_COMBAT_HOSTILE_DEATH", onKillMessage },
	{ "UNIT_SPELLCAST_SENT", onCastSent } }
local listening = false

-- Handlers on these events exist only while a run of the instance the player is in is recorded.
local function syncSources()
	local run = Recorder.Enabled() and Recorder.Current()
	local cur = run and ns.Instances.Current()
	local want = cur and cur.inInstance and RunLog.SplitKey(run.k) == tostring(cur.instanceID) or false
	if want == listening then
		return
	end
	listening = want
	for _, source in ipairs(SOURCES) do
		if want then
			ns:RegisterEvent(source[1], source[2])
		else
			ns:UnregisterEvent(source[1], source[2])
		end
	end
end

-- Group members dead now (player included), and whether all of them are. nil when the client gave no plain answer for
-- anyone (a secret or a missing API): then the run says deaths are not available instead of counting none.
local function deaths()
	local units = { "player" }
	for i = 1, 4 do
		units[#units + 1] = "party" .. i
	end
	if call(IsInRaid) then
		units = {}
		for i = 1, 40 do
			units[#units + 1] = "raid" .. i
		end
	end
	local dead, present, known = 0, 0, 0
	for _, unit in ipairs(units) do
		if call(UnitExists, unit) then
			present = present + 1
			local isDead = call(UnitIsDeadOrGhost, unit)
			if isDead ~= nil then
				known = known + 1
			end
			if isDead then
				dead = dead + 1
			end
		end
	end
	if known == 0 then
		return nil, false
	end
	return dead, present > 0 and dead == present
end

-- Where a run's wing comes from: only what the game reports, never a plan (the plan shown changes when the player
-- browses or follows a leader, and says nothing about where they are).
--   * the client's floor map, when it names exactly one wing of the instance (Travel.Here);
--   * the first boss kill whose encounter ID belongs to exactly one wing (Data/Bosses' `enc`, BossData).
-- Until then the run keeps the bare instance ID ("wing unknown"). A wing is added to a run (RunLog.Adopt) and never
-- changed to another wing: a kill of another wing's boss puts the run back to "wing unknown" for good (RunLog.Unwing;
-- Dire Maul's and Stratholme's floor maps cannot tell their wings apart). A new run for another wing starts only when
-- the floor map names that other wing (RunLog.Enter).

-- The key a run here is recorded under (RunLog's instance keys): the instance ID, with the wing when the instance's
-- wings share it and the client's floor map names exactly one of them. Otherwise the ID alone.
function Recorder.KeyHere(cur)
	local key = tostring(cur.instanceID)
	if not Util.IsInteger(cur.instanceID) or #ns.Travel.Here(cur.instanceID) < 2 then
		return key
	end
	local wings = ns.Travel.Here(cur.instanceID, cur.uiMapID)
	if #wings == 1 then
		return RunLog.WingKey(key, wings[1].key)
	end
	return key
end

-- The wing key a boss kill names for a run of a shared instance ID: the one wing of that instance whose bosses have
-- the encounter ID, else nil.
function Recorder.WingForKill(instanceKey, encounterID)
	local iid = tonumber(instanceKey)
	if not (Util.IsInteger(iid) and Util.IsInteger(encounterID)) then
		return nil
	end
	local wings = ns.Travel.Here(iid)
	if #wings < 2 then
		return nil
	end
	local hit
	for _, k in ipairs(ns.BossData.InstancesForEncounter(encounterID)) do
		for _, w in ipairs(wings) do
			if w.key == k then
				if hit and hit ~= k then
					return nil
				end
				hit = k
			end
		end
	end
	return hit and RunLog.WingKey(instanceKey, hit) or nil
end

function Recorder.OnZone()
	local store = Recorder.Store()
	if not store or not Recorder.Enabled() then
		syncSources()
		return
	end
	local cur = ns.Instances.Current()
	local now = ns.Now()
	if cur.inInstance and cur.instanceID then
		local before = store.current and store.current.k
		local run, isNew = RunLog.Enter(store, Recorder.KeyHere(cur), cur.name, cur.difficultyID, now)
		if isNew or run.k ~= before then
			ns:Fire("RECORDER_CHANGED")
		end
	else
		RunLog.Leave(store, now)
	end
	syncSources()
end

function Recorder.OnCombat(started)
	local run = Recorder.Current()
	if not run or not Recorder.Enabled() then
		stopTicker()
		return
	end
	local cur = ns.Instances.Current()
	if started then
		-- The same instance, by its ID alone: a pull is never dropped over a wing. A run whose wing was not known takes
		-- the one the floor map names now (RunLog.Adopt; never another wing).
		if not (cur.inInstance and RunLog.SplitKey(run.k) == tostring(cur.instanceID)) then
			return
		end
		RunLog.Adopt(run, Recorder.KeyHere(cur))
		local zone = call(GetSubZoneText)
		if type(zone) ~= "string" or zone == "" then
			zone = call(GetMinimapZoneText)
		end
		if RunLog.PullStart(run, ns.Now(), type(zone) == "string" and zone or nil) then
			scan()
			stopTicker()
			if C_Timer and C_Timer.NewTicker then
				ticker = C_Timer.NewTicker(Recorder.SCAN_EVERY, scan)
			end
		end
	else
		stopTicker()
		if RunLog.OpenPull(run) then
			local dead, all = deaths()
			RunLog.PullEnd(run, ns.Now(), dead, all)
		end
	end
	ns:Fire("RECORDER_CHANGED")
end

function Recorder.OnKill(encounterID, name)
	local run = Recorder.Current()
	encounterID, name = Util.Plain(encounterID), Util.Plain(name)
	if not (run and Recorder.Enabled()) then
		return
	end
	-- Only a kill inside the run's instance (by its ID, like a pull): not one outdoors after leaving.
	local cur = ns.Instances.Current()
	local iid, wing = RunLog.SplitKey(run.k)
	if not (cur.inInstance and iid == tostring(cur.instanceID)) then
		return
	end
	local before = run.k
	local changed = RunLog.BossKill(run, encounterID, name, ns.Now())
	-- A run whose wing is not known learns it from the first kill of a boss only one wing has; a kill of another
	-- wing's boss puts it back to "wing unknown" (it spans two wings), never into the other wing.
	local wingKey = Recorder.WingForKill(iid, encounterID)
	if wingKey and not wing then
		RunLog.Adopt(run, wingKey)
	elseif wingKey and wing and wingKey ~= run.k then
		RunLog.Unwing(run)
	end
	changed = changed or run.k ~= before
	if changed then
		ns:Fire("RECORDER_CHANGED")
	end
end

function Recorder.SetEnabled(on)
	ns.db.settings.recorder.enabled = on and true or false
	if on then
		Recorder.OnZone()
	else
		stopTicker()
	end
	syncSources()
	ns:Fire("RECORDER_CHANGED")
end

-- Finish the current run now (the Run mode's "End run", or before clearing).
function Recorder.FinishRun()
	local store = Recorder.Store()
	stopTicker()
	local run = store and RunLog.Finish(store, ns.Now())
	syncSources()
	ns:Fire("RECORDER_CHANGED")
	return run
end

function Recorder.ClearHistory(key)
	local store = Recorder.Store()
	if store then
		RunLog.Clear(store, key)
		syncSources()
		ns:Fire("RECORDER_CHANGED")
	end
end

-- The instance part of a plan's key (GetInstanceInfo's instance ID): the plan's instance map ID (stored, else its
-- bundled instance's: Instances.InstanceMapID), else the Group Finder's for its name, else a run recorded under the
-- same instance name, else nil.
local function instanceKey(plan)
	local name = type(plan) == "table" and plan.instance and plan.instance.name
	local iid = name and ns.Instances.InstanceMapID(plan)
	if iid then
		return tostring(iid)
	end
	local hit = name and ns.GameFiles.FinderFor(name)
	if hit and hit.mapID then
		return tostring(hit.mapID)
	end
	local store = Recorder.Store()
	local key = name and ns.Match.StripArticle(name)
	for k, list in pairs(store and store.runs or {}) do
		local last = list[#list]
		if last and key and ns.Match.StripArticle(last.n or "") == key then
			return (RunLog.SplitKey(k))
		end
	end
	local cur = store and store.current
	if cur and key and ns.Match.StripArticle(cur.n or "") == key then
		return (RunLog.SplitKey(cur.k))
	end
	return nil
end

-- The key a plan's runs are recorded under (RunLog's instance keys): its instance's, and for one wing of an instance
-- whose wings share the instance ID, that wing's key when the resolver knows the plan's wing. The second value, for
-- such a wing: its instance's key, under which runs whose wing was not known are stored (every run recorded before
-- 0.2.1, and runs where neither the floor map nor a boss kill named the wing).
function Recorder.KeyForPlan(plan)
	local key = instanceKey(plan)
	if not key then
		return nil
	end
	local iid, shared = ns.Instances.InstanceMapID(plan)
	local rec = shared and tostring(iid) == key and ns.Instances.Resolve(plan)
	if rec and rec.iid == iid then
		return RunLog.WingKey(key, rec.key), key
	end
	return key
end

-- The keys whose runs a plan lists: its own; for a wing, also its instance's (runs whose wing was not known); for a
-- plan whose wing is unclear, its instance's and every wing's of it (any of them may be its runs).
function Recorder.KeysForPlan(plan)
	local key, shared = Recorder.KeyForPlan(plan)
	if not key then
		return {}
	end
	if shared then
		return { key, shared }
	end
	local wings = {}
	local store = Recorder.Store()
	local function add(k)
		local iid, wing = RunLog.SplitKey(k)
		if wing and iid == key and not Util.IndexOf(wings, k) then
			wings[#wings + 1] = k
		end
	end
	for k in pairs(store and store.runs or {}) do
		add(k)
	end
	if store and store.current then
		add(store.current.k)
	end
	table.sort(wings)
	table.insert(wings, 1, key)
	return wings
end

-- Is a run one of the plan's (KeysForPlan)?
function Recorder.RunMatchesPlan(run, plan)
	return run ~= nil and Util.IndexOf(Recorder.KeysForPlan(plan), run.k) ~= nil
end

-- Is a run listed for a wing's plan one whose wing was not known (stored under the shared instance key)?
function Recorder.WingUnknown(run, plan)
	local _, shared = Recorder.KeyForPlan(plan)
	return shared ~= nil and run ~= nil and run.k == shared
end

-- The short name of a run's wing, from its recommended plan's English instance name ("Scarlet Monastery: Library" ->
-- "Library", "Lower Blackrock Spire" as it is), or nil for a run without a wing.
function Recorder.WingName(run)
	local _, wing = RunLog.SplitKey(run and run.k)
	local rec = wing and ns.Instances.RecommendedFor(wing)
	local name = rec and rec.instance and rec.instance.name
	if type(name) ~= "string" then
		return nil
	end
	return name:match(":%s*(.+)$") or name
end

-- A plan's runs, newest first; the run being recorded first when it is one of them.
function Recorder.RunsForPlan(plan)
	local store = Recorder.Store()
	if not store then
		return {}
	end
	local keys = Recorder.KeysForPlan(plan)
	local runs = RunLog.RunsOf(store, keys)
	if store.current and Util.IndexOf(keys, store.current.k) then
		table.insert(runs, 1, store.current)
	end
	return runs
end

-- Remove a plan's runs: a wing's own runs (the runs whose wing was not known are kept, since every wing lists them,
-- unless `alsoUnknown`), else every run the plan lists (KeysForPlan).
function Recorder.ClearForPlan(plan, alsoUnknown)
	local store = Recorder.Store()
	if not store then
		return
	end
	local key, shared = Recorder.KeyForPlan(plan)
	if shared then
		RunLog.Clear(store, key)
		if alsoUnknown then
			RunLog.Clear(store, shared)
		end
	else
		for _, k in ipairs(Recorder.KeysForPlan(plan)) do
			RunLog.Clear(store, k)
		end
	end
	ns:Fire("RECORDER_CHANGED")
end

-- A draft plan from a recorded run, saved as a new editable plan. Returns the plan.
function Recorder.CreatePlan(run, basePlan)
	local L = ns.L
	local instance = basePlan and ns.Util.DeepCopy(basePlan.instance) or { name = run.n, kind = "dungeon" }
	instance.ejInstanceID = nil
	-- The run's key is the instance's map ID (GetInstanceInfo's eighth return): the same in every client language.
	instance.instanceMapID = instance.instanceMapID or tonumber((RunLog.SplitKey(run.k)))
	local raw = RunLog.PlanFromRun(run, instance, {
		L = L,
		plural = ns.Plural,
		date = date and date("%Y-%m-%d %H:%M", run.t) or "",
	})
	if basePlan and type(basePlan.floors) == "table" and #basePlan.floors > 0 then
		raw.floors = ns.Util.DeepCopy(basePlan.floors)
	end
	local plan = ns.Validate.Plan(raw)
	if not plan then
		return nil
	end
	plan.created, plan.updated = ns.Now(), ns.Now()
	return ns.DB.AddPlan(plan)
end

function Recorder.Init()
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", Recorder.OnZone)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", Recorder.OnZone)
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		Recorder.OnCombat(true)
	end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		Recorder.OnCombat(false)
	end)
	ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, _, _, success)
		success = Util.Plain(success)
		if success == 1 then
			Recorder.OnKill(encounterID, encounterName)
		elseif success == 0 then
			local run = Recorder.Current()
			if run and Recorder.Enabled() then
				RunLog.BossWipe(run, ns.Now())
				ns:Fire("RECORDER_CHANGED")
			end
		end
	end)
	ns:RegisterEvent("BOSS_KILL", function(_, encounterID, encounterName)
		Recorder.OnKill(encounterID, encounterName)
	end)
end
