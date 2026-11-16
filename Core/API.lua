-- The public API for other addons and WeakAuras: the global `DungeonPlanner` holds only `API` (this table).
-- Versioned (API.version goes up when something is added; nothing is changed or removed without API.major going up).
-- Read-only: every getter returns a copy, so another addon cannot change a plan by accident.
-- Documented in docs/API.md.
--
-- Events (CallbackHandler-1.0): DungeonPlanner.API.RegisterCallback(owner, event, method)
--   "DUNGEONPLANNER_PLAN_CHANGED"  (planId)                       a plan was edited, added, imported or deleted
--   "DUNGEONPLANNER_ACTIVE_PLAN"   (planId or nil)                the plan shown in the window changed
--   "DUNGEONPLANNER_PULL_ADVANCED" (planId, pullIndex, pullName)  the current pull moved (keybinding or window)
--   "DUNGEONPLANNER_BOSS_KILLED"   (encounterID, name, planId)    a boss died (planId: a plan that has it, or nil)
--   "DUNGEONPLANNER_STEP"          (planId, stepIndex, stepTitle) run mode moved to another step

local _, ns = ...
local Util = ns.Util

local API = {
	major = 1,
	version = 1,
	addonVersion = ns.version,
}
ns.API = API

local CBH = LibStub and LibStub("CallbackHandler-1.0", true)
local callbacks = CBH and CBH:New(API, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")

function ns:FirePublic(event, ...)
	if callbacks then
		ns.SafeCall(callbacks.Fire, callbacks, event, ...)
	end
end

local function summary(plan)
	if not plan then
		return nil
	end
	return {
		id = plan.id,
		name = plan.name,
		instance = ns.Names.Instance(plan.instance),
		ejInstanceID = plan.instance.ejInstanceID,
		uiMapID = plan.instance.uiMapID,
		difficulty = plan.difficulty,
		author = plan.author,
		pulls = #plan.pulls,
		encounters = #plan.encounters,
		updated = plan.updated,
	}
end

-- The plan selected in the window (or nil): a summary table.
function API.GetActivePlan()
	return ns.db and summary(ns.DB.GetPlan(ns.db.ui.selectedPlan)) or nil
end

-- All plans, or those of a journal instance: summaries, newest first.
function API.GetPlans(ejInstanceID)
	local out = {}
	if not ns.db then
		return out
	end
	for _, plan in ipairs(ns.DB.Plans()) do
		if not ejInstanceID or plan.instance.ejInstanceID == ejInstanceID then
			out[#out + 1] = summary(plan)
		end
	end
	return out
end

-- A full copy of a plan (all markers, pulls, encounters...). Changing the copy changes nothing.
function API.GetPlanCopy(planId)
	local plan = ns.db and ns.DB.GetPlan(planId)
	return plan and Util.DeepCopy(plan) or nil
end

-- The current pull of the active plan: index, name, note, marker count. nil when none.
function API.GetCurrentPull()
	local plan = ns.db and ns.DB.GetPlan(ns.db.ui.selectedPlan)
	local id = ns.UI and ns.UI.ctx and ns.UI.ctx.focusPull
	if not plan or not id then
		return nil
	end
	local pull, index = Util.FindById(plan.pulls, id)
	if not pull then
		return nil
	end
	return { index = index, name = pull.name, note = pull.note, markers = #ns.Plan.MarkersOfPull(plan, id) }
end

-- The assignments of the active plan as plain lines ("Name: task"), optionally for one journal encounter.
function API.GetAssignmentLines(dungeonEncounterID)
	local plan = ns.db and ns.DB.GetPlan(ns.db.ui.selectedPlan)
	if not plan then
		return {}
	end
	local encId
	if dungeonEncounterID then
		local enc = ns.Plan.FindEncounterByGameID(plan, dungeonEncounterID, ns.Journal.GameIdOf(plan))
		if not enc then
			return {}
		end
		encId = enc.id
	end
	return ns.Plan.AssignmentLines(plan, encId)
end

-- Open the window (optionally on a tab: "map", "pulls", "encounters", "assignments", "gear", "notes", "progress",
-- "share").
function API.Open(tab)
	if ns.UI then
		ns.UI.Show(tab)
	end
end

-- Import an export string as a new plan (asks nothing; returns ok, message).
function API.ImportString(text)
	if not ns.db then
		return false, "not loaded"
	end
	return ns.DB.ImportString(text, { kind = "api" })
end

-- Stable frame names for skin addons (ElvUI / AddOnSkins): the main window and the dialog. nil until first opened.
function API.GetFrames()
	return {
		main = _G.DungeonPlannerMainFrame,
		dialog = _G.DungeonPlannerDialog,
	}
end

if _G then
	_G.DungeonPlanner = { API = API }
end
