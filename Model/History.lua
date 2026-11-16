-- Undo and redo for plan edits: a bounded history of snapshots of one plan. Pure (no game API); the UI (UI/MainFrame.lua,
-- ctx:Changed / ctx:Undo / ctx:Redo) takes a deep copy of the plan after every change and hands it here. Everything that
-- changes a plan goes through ctx:Changed, so markers, routes, pulls, steps, notes, bosses, party, gear and drawings all
-- share one history: one Undo takes back the last change, whatever it was.
--
--   h = History.New(max)            -- max snapshots kept for undo (the oldest are dropped)
--   History.Reset(h, key, snap)     -- a new plan (key = its id): the history starts empty from this state
--   History.Record(h, key, snap)    -- after a change: the state before it becomes undoable, redo is cleared
--   snap = History.Undo(h)          -- the state to restore (nil when there is nothing to undo)
--   snap = History.Redo(h)          -- the state to restore again (nil when there is nothing to redo)
--
-- Snapshots are stored as given; the caller copies them in and out, so restoring never shares tables with the history.

local _, ns = ...
local History = ns:NewModule("History")

History.MAX = 50

function History.New(max)
	return { max = max or History.MAX, key = nil, current = nil, undo = {}, redo = {} }
end

function History.Reset(h, key, snapshot)
	h.key, h.current = key, snapshot
	h.undo, h.redo = {}, {}
end

-- A change was made to the plan `key`; `snapshot` is its state after the change. A different key starts over.
function History.Record(h, key, snapshot)
	if h.key ~= key or h.current == nil then
		History.Reset(h, key, snapshot)
		return
	end
	h.undo[#h.undo + 1] = h.current
	while #h.undo > h.max do
		table.remove(h.undo, 1)
	end
	h.current = snapshot
	h.redo = {}
end

function History.CanUndo(h, key)
	return h.key ~= nil and h.key == key and #h.undo > 0
end

function History.CanRedo(h, key)
	return h.key ~= nil and h.key == key and #h.redo > 0
end

function History.Undo(h)
	local previous = table.remove(h.undo)
	if previous == nil then
		return nil
	end
	h.redo[#h.redo + 1] = h.current
	h.current = previous
	return previous
end

function History.Redo(h)
	local nextState = table.remove(h.redo)
	if nextState == nil then
		return nil
	end
	h.undo[#h.undo + 1] = h.current
	h.current = nextState
	return nextState
end

function History.Counts(h)
	return #h.undo, #h.redo
end
