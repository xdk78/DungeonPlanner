-- Undo and redo (Model/History.lua): copies of the selected plan, taken after each change, 50 steps. Every edit (map,
-- drawings, pulls, steps, notes, bosses, party, gear) goes through ctx:Changed, so they all share one history. Kept in
-- memory only; selecting another plan starts a new history (UI.ResetUndo, from UI.SelectPlan in UI/MainFrame.lua).

local _, ns = ...
local UI = ns.UI
local ctx = UI.ctx

local history = ns.History.New(ns.History.MAX)
UI.history = history

function UI.ResetUndo(plan)
	ns.History.Reset(history, plan and plan.id or nil, plan and not plan.bundled and ns.Util.DeepCopy(plan) or nil)
end

function ctx:Changed(what)
	local plan = self:Plan()
	if not plan or plan.bundled then
		return
	end
	ns.History.Record(history, plan.id, ns.Util.DeepCopy(plan))
	ns.DB.Changed(plan, what)
end

function ctx:CanUndo()
	local plan = self:Plan()
	return plan ~= nil and ns.History.CanUndo(history, plan.id) and ns.DB.IsEditable(plan)
end

function ctx:CanRedo()
	local plan = self:Plan()
	return plan ~= nil and ns.History.CanRedo(history, plan.id) and ns.DB.IsEditable(plan)
end

-- Restore in place: the plan table stays the same object (it is referenced by id from the store).
local function restore(self, plan, state, what)
	for k in pairs(plan) do
		plan[k] = nil
	end
	for k, v in pairs(ns.Util.DeepCopy(state)) do
		plan[k] = v
	end
	self.selectedMarker, self.selectedShape = nil, nil
	ns.DB.Changed(plan, what)
end

function ctx:Undo()
	if self:CanUndo() then
		restore(self, self:Plan(), ns.History.Undo(history), "undo")
	end
end

function ctx:Redo()
	if self:CanRedo() then
		restore(self, self:Plan(), ns.History.Redo(history), "redo")
	end
end
