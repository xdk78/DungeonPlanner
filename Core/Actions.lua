-- Actions shared by key bindings (Bindings.xml), the minimap button menu and slash commands. All non-secure.
-- Anything that sends messages waits until combat ends (ns:RunOutOfCombat); showing our own (non-protected) window is
-- allowed in combat, so the plan can be read mid-fight.

local _, ns = ...
local Actions = ns:NewModule("Actions")
local L = ns.L

local function activePlan()
	return ns.db and ns.DB.GetPlan(ns.db.ui.selectedPlan)
end

function Actions.Toggle()
	ns.UI.Toggle()
end

function Actions.OpenMap()
	ns.UI.Show("map")
end

-- Move the current pull by delta (+1 next, -1 previous) and say it in chat (only to the player). While run mode is
-- open, the same keys walk the plan's steps instead (UI/RunMode.lua).
function Actions.StepPull(delta)
	if ns.RunMode and ns.RunMode.IsShown() then
		ns.RunMode.Step(delta)
		return
	end
	local plan = activePlan()
	if not plan or #plan.pulls == 0 then
		ns:Print(L["The active plan has no pulls."])
		return
	end
	local ctx = ns.UI.ctx
	local index = ctx.focusPull and ns.Plan.PullIndex(plan, ctx.focusPull) or 0
	index = index + delta
	if index < 1 then
		index = #plan.pulls
	elseif index > #plan.pulls then
		index = 1
	end
	local pull = plan.pulls[index]
	ctx.focusPull = pull.id
	ctx.currentPull = pull.id
	local line = string.format(L["Pull %d/%d: %s"], index, #plan.pulls, pull.name)
	if pull.note ~= "" then
		line = line .. " - " .. pull.note:gsub("\n", " ")
	end
	ns:Print(line)
	ns:FirePublic("DUNGEONPLANNER_PULL_ADVANCED", plan.id, index, pull.name)
	if ns.UI.IsShown() then
		ns.UI.RefreshPage()
	end
end

function Actions.BossKilled()
	local enc = ns.Tracker.MarkNextBossKilled()
	if enc then
		ns:Print(string.format(L["Marked as killed: %s"], ns.Names.Encounter(enc)))
	else
		ns:Print(L["No boss left to mark in the active plan (bosses need a journal link)."])
	end
end

function Actions.ShareWithGroup()
	local plan = activePlan()
	if not plan then
		ns:Print(L["Select a plan first."])
		return
	end
	ns:RunOutOfCombat(function()
		local transfer, err = ns.Comm.SharePlan(plan, "GROUP")
		if transfer then
			ns:Print(string.format(L["Offered \"%s\" to your group."], plan.name))
		else
			ns:Print(err)
		end
	end)
end

local BINDINGS = {
	toggle = Actions.Toggle,
	map = Actions.OpenMap,
	nextPull = function()
		Actions.StepPull(1)
	end,
	previousPull = function()
		Actions.StepPull(-1)
	end,
	bossKilled = Actions.BossKilled,
	runMode = function()
		ns.RunMode.Toggle()
	end,
	shareGroup = Actions.ShareWithGroup,
}

-- The one global the bindings call.
function _G.DungeonPlanner_Binding(action)
	local fn = BINDINGS[action]
	if fn and ns.db then
		ns.SafeCall(fn)
	end
end
