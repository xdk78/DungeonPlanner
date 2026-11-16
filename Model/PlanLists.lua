-- Plan operations, part 2: gear recommendations and objectives (Model/Plan.lua has the rest and the rules: pure, the
-- only code that changes a plan, each change stamps plan.updated, failures return nil plus a reason). Split from
-- Plan.lua to keep files small; these functions refuse a recommended (bundled) plan like the others.

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

-- Gear ----------------------------------------------------------------------------------------------------------------

function Plan.AddGear(plan, fields)
	if #plan.gear >= MAX.gear then
		return nil, "limit"
	end
	fields = fields or {}
	local itemID = Util.ParseItemID(fields.itemID)
	local label = Util.CleanText(fields.label or "", TEXT.label) or ""
	if not itemID and label == "" then
		return nil, "invalid"
	end
	local g = {
		id = nextId(plan, "g"),
		itemID = itemID,
		label = label,
		note = Util.CleanText(fields.note or "", TEXT.task) or "",
		slot = Schema.SLOT_SET[fields.slot] and fields.slot or nil,
		class = Schema.IsClassToken(fields.class) and fields.class or nil,
		role = Schema.ROLE_SET[fields.role] and fields.role or nil,
		encounter = fields.encounter and Util.FindById(plan.encounters, fields.encounter) and fields.encounter or nil,
		priority = (Util.IsInteger(fields.priority) and fields.priority >= 1 and fields.priority <= 5) and fields.priority
			or 3,
	}
	plan.gear[#plan.gear + 1] = g
	touch(plan)
	return g
end

function Plan.RemoveGear(plan, gearId)
	local _, index = Util.FindById(plan.gear, gearId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.gear, index)
	touch(plan)
	return true
end

-- Gear entries matching a filter ({ class=, role=, slot=, encounter= }; nil fields match anything). An entry with no
-- class (or role) applies to every class (or role). Sorted by priority (1 first), then label.
function Plan.FilterGear(plan, filter)
	filter = filter or {}
	local out = {}
	for _, g in ipairs(plan.gear) do
		local ok = true
		if filter.class and g.class and g.class ~= filter.class then
			ok = false
		end
		if filter.role and g.role and g.role ~= filter.role then
			ok = false
		end
		if filter.slot and g.slot ~= filter.slot then
			ok = false
		end
		if filter.encounter and g.encounter ~= filter.encounter then
			ok = false
		end
		if ok then
			out[#out + 1] = g
		end
	end
	table.sort(out, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return (a.label or "") < (b.label or "")
	end)
	return out
end

-- Objectives ------------------------------------------------------------------------------------------------------------

function Plan.AddObjective(plan, text, encounter)
	if #plan.objectives >= MAX.objectives then
		return nil, "limit"
	end
	text = Util.CleanText(text or "", TEXT.short)
	if not text or text == "" then
		return nil, "invalid"
	end
	local o = {
		id = nextId(plan, "o"),
		text = text,
		encounter = encounter and Util.FindById(plan.encounters, encounter) and encounter or nil,
	}
	plan.objectives[#plan.objectives + 1] = o
	touch(plan)
	return o
end

function Plan.RemoveObjective(plan, objectiveId)
	local _, index = Util.FindById(plan.objectives, objectiveId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.objectives, index)
	touch(plan)
	return true
end

-- Recommended plans are read-only (as in Plan.lua).
for _, name in ipairs({ "AddGear", "RemoveGear", "AddObjective", "RemoveObjective" }) do
	local fn = Plan[name]
	Plan[name] = function(plan, ...)
		if type(plan) == "table" and plan.bundled then
			return nil, "read-only"
		end
		return fn(plan, ...)
	end
end
