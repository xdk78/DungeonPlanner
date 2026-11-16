-- Plan section: the plan's details and notes (left, UI/Panels/NotesPanel.lua) beside this run's progress and the
-- objective checklist (right, UI/Panels/ProgressPanel.lua), each in an inset panel. For a recommended plan it also
-- says where the plan comes from.

local _, ns = ...
local W, L = ns.Widgets, ns.L
local SP = ns.Style.SPACE

local Panel = {}
ns.Panels.plan = Panel

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", "DungeonPlannerPlanSection", parent)

	-- Two halves by anchors alone (each side of the middle, half a gap away), so they follow every resize.
	local left = W.Panel(f, "surface", "border")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -SP.md / 2, 0)
	local right = W.Panel(f, "surface", "border")
	right:SetPoint("TOPLEFT", f, "TOP", SP.md / 2, 0)
	right:SetPoint("BOTTOMRIGHT")

	left.heading = W.Heading(left, L["Plan"], nil, true)
	left.heading:SetPoint("TOPLEFT", SP.md, -SP.md)
	-- Where an editable plan comes from, on its own line under the heading (a recommended plan's document lists its
	-- source in full instead). Hovering it lists the details (UI.PlanSource).
	left.origin = W.Text(left, "caption", "goldBright")
	left.origin:SetPoint("TOPLEFT", left.heading, "BOTTOMLEFT", 0, -SP.sm)
	left.origin:SetPoint("RIGHT", -SP.md, 0)
	left.originHit = CreateFrame("Frame", nil, left)
	left.originHit:SetAllPoints(left.origin)
	left.originHit:EnableMouse(true)
	right.heading = W.Heading(right, L["Progress"], nil, true)
	right.heading:SetPoint("TOPLEFT", SP.md, -SP.md)

	local notes = ns.Panels.notes.Create(left, ctx)
	local progress = ns.Panels.progress.Create(right, ctx)
	progress:SetPoint("TOPLEFT", right.heading, "BOTTOMLEFT", 0, -SP.md)
	progress:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
	f.notes, f.progress = notes, progress

	function f:Refresh()
		local plan = ctx:Plan()
		if not plan then
			return
		end
		-- A copy: the plan it is based on; a shared plan: who sent it.
		local short, lines = ns.UI.PlanSource(plan)
		local origin = short ~= nil and not ctx:ReadOnly()
		W.FitText(left.origin, origin and short or "")
		left.origin:SetShown(origin)
		W.SetTooltip(left.originHit, L["Source"], lines and table.concat(lines, "\n") or nil)
		left.originHit:SetShown(origin and lines ~= nil)
		notes:ClearAllPoints()
		notes:SetPoint("TOPLEFT", origin and left.origin or left.heading, "BOTTOMLEFT", 0, -SP.md)
		notes:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
		ns.SafeCall(notes.Refresh, notes)
		ns.SafeCall(progress.Refresh, progress)
	end
	return f
end
