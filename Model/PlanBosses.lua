-- Plan operations, part 3: bosses (encounters and their phases), assignments and raid groups (Model/Plan.lua has the
-- rest and the rules: pure, the only code that changes a plan, each change stamps plan.updated, failures return nil
-- plus a reason; part 2, Model/PlanLists.lua, gear and objectives). Split from Plan.lua to keep files small; these
-- functions refuse a recommended (bundled) plan like the others.

local _, ns = ...
local Plan = ns.Plan
local Util, Schema = ns.Util, ns.Schema
local MAX, TEXT = Schema.MAX, Schema.TEXT

local function touch(plan)
	plan.updated = ns.Now()
end

-- Ids are a letter plus the plan's counter (as in Plan.lua).
local function nextId(plan, letter)
	local n = plan.nextId or 1
	plan.nextId = n + 1
	return letter .. n
end

-- Encounters and phases -------------------------------------------------------------------------------------------------

function Plan.AddEncounter(plan, fields)
	if #plan.encounters >= MAX.encounters then
		return nil, "limit"
	end
	fields = fields or {}
	local enc = {
		id = nextId(plan, "e"),
		name = Util.CleanText(fields.name or "Boss", TEXT.name) or "",
		ejEncounterID = Util.IsInteger(fields.ejEncounterID) and fields.ejEncounterID or nil,
		dungeonEncounterID = Util.IsInteger(fields.dungeonEncounterID) and fields.dungeonEncounterID or nil,
		strategy = "",
		phases = {},
	}
	plan.encounters[#plan.encounters + 1] = enc
	touch(plan)
	return enc
end

-- `idOf(enc)` (optional) gives the encounter ID of a boss that has none of its own (the Adventure Guide's, in game).
function Plan.FindEncounterByGameID(plan, dungeonEncounterID, idOf)
	for _, enc in ipairs(plan.encounters) do
		local id = enc.dungeonEncounterID or (idOf and idOf(enc))
		if id and id == dungeonEncounterID then
			return enc
		end
	end
	return nil
end

function Plan.UpdateEncounter(plan, encId, fields)
	local enc = Util.FindById(plan.encounters, encId)
	if not enc then
		return nil, "missing"
	end
	if fields.name ~= nil then
		-- A renamed boss keeps the planner's name on every client. An emptied name goes back to the journal's name
		-- (resolved by ID at display time); the stored name stays as the fallback for clients without that entry.
		local name = Util.CleanText(fields.name, TEXT.name) or ""
		if name ~= "" then
			enc.name, enc.custom = name, true
		else
			enc.custom = nil
		end
	end
	if fields.strategy ~= nil then
		enc.strategy = Util.CleanText(fields.strategy, TEXT.strategy, true) or ""
	end
	touch(plan)
	return enc
end

function Plan.RemoveEncounter(plan, encId)
	local _, index = Util.FindById(plan.encounters, encId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.encounters, index)
	local function clear(items)
		for _, item in ipairs(items) do
			if item.encounter == encId then
				item.encounter = nil
				item.phase = nil
			end
		end
	end
	clear(plan.markers)
	clear(plan.assignments)
	clear(plan.gear)
	clear(plan.objectives)
	ns.Drawing.Unlink(plan, "encounter", encId)
	ns.Pages.Unlink(plan, encId)
	touch(plan)
	return true
end

function Plan.AddPhase(plan, encId, name)
	local enc = Util.FindById(plan.encounters, encId)
	if not enc then
		return nil, "missing"
	end
	if #enc.phases >= MAX.phases then
		return nil, "limit"
	end
	local phase = {
		name = Util.CleanText(name or ("Phase " .. (#enc.phases + 1)), TEXT.label) or "",
		trigger = "",
		notes = "",
	}
	enc.phases[#enc.phases + 1] = phase
	touch(plan)
	return phase, #enc.phases
end

function Plan.UpdatePhase(plan, encId, index, fields)
	local enc = Util.FindById(plan.encounters, encId)
	local phase = enc and enc.phases[index]
	if not phase then
		return nil, "missing"
	end
	if fields.name ~= nil then
		phase.name = Util.CleanText(fields.name, TEXT.label) or ""
	end
	if fields.trigger ~= nil then
		phase.trigger = Util.CleanText(fields.trigger, TEXT.short) or ""
	end
	if fields.notes ~= nil then
		phase.notes = Util.CleanText(fields.notes, TEXT.strategy, true) or ""
	end
	touch(plan)
	return phase
end

function Plan.RemovePhase(plan, encId, index)
	local enc = Util.FindById(plan.encounters, encId)
	if not enc or not enc.phases[index] then
		return nil, "missing"
	end
	table.remove(enc.phases, index)
	-- Assignments pointing past the end lose their phase; later ones shift down with the list.
	for _, a in ipairs(plan.assignments) do
		if a.encounter == encId and a.phase then
			if a.phase == index then
				a.phase = nil
			elseif a.phase > index then
				a.phase = a.phase - 1
			end
		end
	end
	touch(plan)
	return true
end

-- Assignments and groups -------------------------------------------------------------------------------------------------

function Plan.AddAssignment(plan, target, task, encounter, phase)
	if #plan.assignments >= MAX.assignments then
		return nil, "limit"
	end
	target = Util.CleanText(target or "", TEXT.player)
	if not (target and Schema.IsValidTarget(target)) then
		return nil, "invalid"
	end
	local enc = encounter and Util.FindById(plan.encounters, encounter)
	local a = {
		id = nextId(plan, "a"),
		target = target,
		task = Util.CleanText(task or "", TEXT.task) or "",
		encounter = enc and encounter or nil,
		phase = (enc and Util.IsInteger(phase) and enc.phases[phase]) and phase or nil,
	}
	plan.assignments[#plan.assignments + 1] = a
	touch(plan)
	return a
end

function Plan.UpdateAssignment(plan, assignmentId, fields)
	local a = Util.FindById(plan.assignments, assignmentId)
	if not a then
		return nil, "missing"
	end
	if fields.target ~= nil then
		local t = Util.CleanText(fields.target, TEXT.player)
		if t and Schema.IsValidTarget(t) then
			a.target = t
		end
	end
	if fields.task ~= nil then
		a.task = Util.CleanText(fields.task, TEXT.task) or ""
	end
	if fields.encounter ~= nil then
		if fields.encounter == false then
			a.encounter, a.phase = nil, nil
		elseif Util.FindById(plan.encounters, fields.encounter) then
			a.encounter, a.phase = fields.encounter, nil
		end
	end
	if fields.phase ~= nil then
		local enc = a.encounter and Util.FindById(plan.encounters, a.encounter)
		if fields.phase == false then
			a.phase = nil
		elseif enc and Util.IsInteger(fields.phase) and enc.phases[fields.phase] then
			a.phase = fields.phase
		end
	end
	if fields.marker ~= nil then
		if fields.marker == false then
			a.marker = nil
		elseif Util.FindById(plan.markers, fields.marker) then
			a.marker = fields.marker
		end
	end
	touch(plan)
	return a
end

function Plan.RemoveAssignment(plan, assignmentId)
	local _, index = Util.FindById(plan.assignments, assignmentId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.assignments, index)
	touch(plan)
	return true
end

-- Put a player into raid group g (1..8), taking them out of any other group first.
function Plan.SetGroup(plan, name, g)
	name = Util.CleanText(name or "", TEXT.player)
	if not name or name == "" or name:find(":") then
		return nil, "invalid"
	end
	for _, members in ipairs(plan.groups) do
		local i = Util.IndexOf(members, name)
		if i then
			table.remove(members, i)
		end
	end
	if g then
		local members = plan.groups[g]
		if not members then
			return nil, "invalid"
		end
		if #members >= MAX.groupSize then
			return nil, "limit"
		end
		members[#members + 1] = name
	end
	touch(plan)
	return true
end

-- Assignments as chat lines ("Name: task"), grouped by encounter; used by "Post to chat". Plain text only.
function Plan.AssignmentLines(plan, encounterId)
	local lines = {}
	for _, a in ipairs(plan.assignments) do
		if encounterId == nil or a.encounter == encounterId then
			local who = a.target
			local role = who:match("^role:(%u+)$")
			local group = who:match("^group:(%d)$")
			if role then
				who = role
			elseif group then
				who = "G" .. group
			elseif who == "all" then
				who = "All"
			end
			local line = who .. ": " .. a.task
			if a.phase then
				line = "[P" .. a.phase .. "] " .. line
			end
			lines[#lines + 1] = line
		end
	end
	return lines
end

-- Recommended plans are read-only (as in Plan.lua); the lookups stay open to them.
for _, name in ipairs({ "AddEncounter", "UpdateEncounter", "RemoveEncounter", "AddPhase", "UpdatePhase", "RemovePhase",
	"AddAssignment", "UpdateAssignment", "RemoveAssignment", "SetGroup" }) do
	local fn = Plan[name]
	Plan[name] = function(plan, ...)
		if type(plan) == "table" and plan.bundled then
			return nil, "read-only"
		end
		return fn(plan, ...)
	end
end
