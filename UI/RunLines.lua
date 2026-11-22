-- Run mode's status lines (UI/RunMode.lua draws them): the recorder line, the drift against the plan while a run is
-- recorded, and the prep line before the first step; plus the drift line's click (go to the estimated step).
-- Loaded after UI/RunMode.lua; the functions live on RunMode. After an update that added this file, run mode shows
-- none of these lines until the game restarts (Compat.FILES).

local _, ns = ...
local RunMode = ns.RunMode
local L = ns.L
local UI = ns.UI

local function ctx()
	return UI.ctx
end

-- The recorder line: "Recording • pull 3 of 9 planned", or how to start it.
function RunMode.RecorderText(plan)
	local R = ns.Recorder
	if not R.Enabled() then
		return L["Not recording (click to record this run)"], false
	end
	local run = R.Current()
	local inside = ns.Instances.Current().inInstance
	if not run or not inside then
		return L["Recording starts when you enter a dungeon."], false
	end
	local pulls = #run.p
	local open = ns.RunLog.OpenPull(run) ~= nil
	local text = L["Recording"] .. " • " .. (open and string.format(L["pull %d (in combat)"], pulls) or ns.Plural(pulls, L["%d pull|%d pulls"]))
	if plan and #plan.pulls > 0 then
		text = text .. " • " .. string.format(L["plan: %d"], #plan.pulls)
	end
	if #run.b > 0 then
		text = text .. " • " .. ns.Plural(#run.b, L["%d boss|%d bosses"])
	end
	return text, true
end

-- Progress against the plan while a run of its instance is recorded: RunCompare.Drift, or nil.
function RunMode.Drift(plan)
	local R = ns.Recorder
	if not (plan and R.Enabled()) then
		return nil
	end
	local run = R.Current()
	if not R.RunMatchesPlan(run, plan) or (#run.p == 0 and #run.b == 0) then
		return nil
	end
	return ns.RunCompare.Drift(plan, run, ctx():Steps(), ns.Panels.runs.CompareOptions(plan))
end

-- The drift line's text, whether it warns, and its tooltip lines; nil without a drift.
function RunMode.DriftText(plan)
	local d = RunMode.Drift(plan)
	if not d then
		return nil
	end
	local function bossName(encId)
		local enc = ns.Util.FindById(plan.encounters, encId)
		return enc and ns.Names.Encounter(enc) or L["Boss"]
	end
	local lines = { string.format(L["Pulls: %d of %d planned"], d.pullsDone, d.pullsPlanned) }
	if d.nextBoss then
		lines[#lines + 1] = string.format(L["Since the last boss: %d, planned %d before %s"], d.since, d.sincePlanned,
			bossName(d.nextBoss))
	end
	local steps = ctx():Steps()
	if d.step and steps[d.step] then
		lines[#lines + 1] = string.format(L["Probably at step %d: %s. Click to go there."], d.step,
			(UI.StepText(plan, steps[d.step])))
	end
	lines[#lines + 1] =
		L["An estimate from boss kills and the pull count: the game does not show where you are or which pack you pulled."]
	local w = d.warnings[1]
	if w then
		return ns.Discord.DivergenceText(w, bossName), true, lines, d
	end
	local text = L["On plan"]
	if d.step then
		text = text .. " • " .. string.format(L["step ~ %d"], d.step)
	end
	return text, false, lines, d
end

-- The prep line before the first step (not started, or on step 1): "Prep: 3 quests to pick up • 1 key missing", nil
-- when there is nothing left to do.
function RunMode.PrepText(plan)
	local index = ctx():StepIndex()
	if not plan or (index and index > 1) then
		return nil
	end
	local sum = ns.PrepInfo.Summary(plan)
	if not sum then
		return nil
	end
	local parts = {}
	if sum.quests > 0 then
		parts[#parts + 1] = ns.Plural(sum.quests, L["%d quest to pick up|%d quests to pick up"])
	end
	if sum.keys > 0 then
		parts[#parts + 1] = ns.Plural(sum.keys, L["%d key missing|%d keys missing"])
	end
	return string.format(L["Prep: %s"], table.concat(parts, "  •  "))
end

-- Go to the step the run is probably at (the drift line's click).
function RunMode.GoToEstimate()
	local plan = ctx():Plan()
	local _, _, _, d = RunMode.DriftText(plan)
	if d and d.step and d.step ~= ctx():StepIndex() then
		UI.FocusStep(d.step, { stay = true })
		RunMode.Refresh()
	end
end
