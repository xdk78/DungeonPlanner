-- The map's controls in its bottom-left corner, inside the gold frame with a margin of their own: Labels and Icon size,
-- and above them, with the route tool, "Snap to corridors" (UI/RouteSnap.lua), faded on a floor without corridor data.
-- Built by UI/Panels/MapPanel.lua: f.controls, f.labels, f.iconSize, f.snapBox, f.snap.

local _, ns = ...
local MapControls = ns:NewModule("MapControls")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

function MapControls.Build(f, ctx, canvas)
	local controls = CreateFrame("Frame", nil, canvas.edge)
	controls:SetPoint("BOTTOMLEFT", ns.MapCanvas.FRAME_INSET + SP.sm, ns.MapCanvas.FRAME_INSET + SP.sm)
	controls:SetSize(120, 80)
	f.labels = W.Check(controls, L["Labels"], function(on)
		ctx.showLabels = on
		canvas:DrawContent()
	end)
	local labelsBox = W.Panel(controls, "surface", "border")
	labelsBox:SetPoint("TOPLEFT")
	labelsBox:SetSize(112, SZ.control + 4)
	f.labels:SetParent(labelsBox)
	f.labels:SetPoint("LEFT", SP.sm, 0)
	f.iconSize = W.Stepper(controls, L["Icon size"], {
		min = 0.5,
		max = 1.5,
		step = 0.1,
		get = function()
			return ns.db.ui.iconScale or 1
		end,
		set = function(v)
			ns.db.ui.iconScale = v
			canvas:DrawContent()
		end,
		format = function(v)
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end,
	})
	f.iconSize:SetPoint("TOPLEFT", labelsBox, "BOTTOMLEFT", 0, -SP.xs)
	f.controls = controls

	local snapBox = W.Panel(controls, "surface", "border")
	snapBox:SetPoint("BOTTOMLEFT", controls, "TOPLEFT", 0, SP.xs)
	snapBox:SetHeight(SZ.control + 4)
	f.snap = W.Check(snapBox, L["Snap to corridors"], function(on)
		ns.db.ui.snapRoutes = on
		f:Refresh()
	end)
	f.snap:SetPoint("LEFT", SP.sm, 0)
	snapBox:SetWidth(math.max(112, f.snap:GetWidth() + 2 * SP.sm))
	W.SetTooltip(f.snap, L["Snap to corridors"],
		L["Clicks add numbered stops and the path between them follows the corridors; Shift-click for a straight leg. Dragging a stop finds its legs again."])
	f.snapBox = snapBox
	-- A hidden map needs no corridor data: the decoded grids go (prepared again when the route tool is next used).
	canvas:HookScript("OnHide", function()
		ns.Corridors.Reset()
	end)
end

-- Their boxes in the map view's pixels (top left origin), for the map's fit: rects gets them appended.
function MapControls.Rects(f, rects, vh, inset)
	local controls, snapBox = f.controls, f.snapBox
	local cw, ch = controls:GetWidth() or 0, controls:GetHeight() or 0
	rects[#rects + 1] = { inset, vh - inset - ch, inset + cw, vh - inset }
	if snapBox:IsShown() then
		local top = vh - inset - ch - SP.xs - snapBox:GetHeight()
		rects[#rects + 1] = { inset, top, inset + snapBox:GetWidth(), top + snapBox:GetHeight() }
	end
end

-- The switch shown with the route tool (route), its state; returns whether a click snaps on this floor. With the route
-- tool on a snapping floor (the tool just chosen, another floor, the switch turned on), the floor's corridor data is
-- prepared over the next frames, so the first click finds its leg at once (Data/Corridors.lua); with another tool the
-- decoded grids are let go, as when the map hides (MapControls.Build).
function MapControls.Refresh(f, plan, floor, route)
	f.snapBox:SetShown(route)
	f.snap:SetChecked(ns.RouteSnap.Enabled())
	f.snap:SetAlpha(ns.Corridors.Has(plan, floor) and 1 or 0.5)
	local active = ns.RouteSnap.Active(plan, floor)
	if route and active then
		ns.Corridors.Prepare(plan, floor)
	elseif not route then
		ns.Corridors.Reset()
	end
	return active
end
