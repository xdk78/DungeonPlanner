-- The run recorder (opt-in, off by default): records a dungeon run from what the client exposes inside an instance
-- (docs/COMPATIBILITY.md section 10) into Model/RunLog.lua's store. Event-driven and cheap:
--   PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA  start or continue a run inside a dungeon or raid
--   PLAYER_REGEN_DISABLED / ENABLED                one pull = one combat segment
--   a 0.5 s ticker, only while in combat           enemy nameplates: count, level and classification (names only when
--                                                 they are not secret); never positions, never GUIDs
--   ENCOUNTER_END / BOSS_KILL                      boss kills with timing; a failed encounter is a wipe
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

function Recorder.OnZone()
	local store = Recorder.Store()
	if not store or not Recorder.Enabled() then
		return
	end
	local cur = ns.Instances.Current()
	local now = ns.Now()
	if cur.inInstance and cur.instanceID then
		local _, isNew = RunLog.Enter(store, tostring(cur.instanceID), cur.name, cur.difficultyID, now)
		if isNew then
			ns:Fire("RECORDER_CHANGED")
		end
	else
		RunLog.Leave(store, now)
	end
end

function Recorder.OnCombat(started)
	local run = Recorder.Current()
	if not run or not Recorder.Enabled() then
		stopTicker()
		return
	end
	local cur = ns.Instances.Current()
	if started then
		if not (cur.inInstance and tostring(cur.instanceID) == run.k) then
			return
		end
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
	if run and Recorder.Enabled() and RunLog.BossKill(run, encounterID, name, ns.Now()) then
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
	ns:Fire("RECORDER_CHANGED")
end

-- Finish the current run now (the Run mode's "End run", or before clearing).
function Recorder.FinishRun()
	local store = Recorder.Store()
	stopTicker()
	local run = store and RunLog.Finish(store, ns.Now())
	ns:Fire("RECORDER_CHANGED")
	return run
end

function Recorder.ClearHistory(key)
	local store = Recorder.Store()
	if store then
		RunLog.Clear(store, key)
		ns:Fire("RECORDER_CHANGED")
	end
end

-- The instance key of a plan for the recorder: the Group Finder's instance map ID for its name (the key the recorder
-- stores runs under is GetInstanceInfo's instance ID), else nil.
function Recorder.KeyForPlan(plan)
	local name = type(plan) == "table" and plan.instance and plan.instance.name
	local hit = name and ns.GameFiles.FinderFor(name)
	if hit and hit.mapID then
		return tostring(hit.mapID)
	end
	-- A run recorded under the same instance name.
	local store = Recorder.Store()
	local key = name and ns.Match.StripArticle(name)
	for k, list in pairs(store and store.runs or {}) do
		local last = list[#list]
		if last and key and ns.Match.StripArticle(last.n or "") == key then
			return k
		end
	end
	local cur = store and store.current
	if cur and key and ns.Match.StripArticle(cur.n or "") == key then
		return cur.k
	end
	return nil
end

-- A draft plan from a recorded run, saved as a new editable plan. Returns the plan.
function Recorder.CreatePlan(run, basePlan)
	local L = ns.L
	local instance = basePlan and ns.Util.DeepCopy(basePlan.instance) or { name = run.n, kind = "dungeon" }
	instance.ejInstanceID = nil
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
