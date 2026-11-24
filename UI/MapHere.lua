-- The map's "You are here (approx.)" marker, installed on a map view (UI/MapCanvas.lua): the map section's and run
-- mode's mini map alike.
--
-- Inside a dungeon the game names only the area the player is in (Data/Subzones.lua), so the marker is an area, not a
-- point: a soft disc with a ring at the middle of that area, sized in map units so it grows with the zoom like the
-- room it stands for. It shows only inside the plan's own instance, while the area has an anchor on the floor shown,
-- and with the setting "Show where you are on dungeon maps" on. The tooltip names the area.
--
-- The zone events are registered only while the view is shown (its OnShow / OnHide), and a zone change moves the
-- marker alone: the rest of the map is not redrawn. No OnUpdate.

local _, ns = ...
local MapHere = ns:NewModule("MapHere")
local S, W = ns.Style, ns.Widgets

MapHere.EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
MapHere.SPAN = 0.12 -- the marker's width as a share of the map's: about a room
MapHere.MIN, MapHere.MAX = 48, 180 -- its width on screen, in UI units, at any zoom

function MapHere.Enabled()
	return not (ns.db and ns.db.settings.mapHere == false)
end

function MapHere.Install(view)
	local L = ns.L
	local b = CreateFrame("Frame", nil, view.overlay)
	-- Over the enemy dots (+1), under the route's stops (+3) and the plan's pins.
	b:SetFrameLevel(view.overlay:GetFrameLevel() + 2)
	b.fill = b:CreateTexture(nil, "ARTWORK", nil, 0)
	b.fill:SetTexture(S.MEDIA .. "Circle")
	b.fill:SetAllPoints()
	b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.ring:SetTexture(S.MEDIA .. "Ring")
	b.ring:SetAllPoints()
	b.inner = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.inner:SetTexture(S.MEDIA .. "Ring")
	b.inner:SetPoint("CENTER")
	-- The pointer over it shows the tooltip; presses go through to the map and the pins, so the marker never stands in
	-- the way of a tool. Without these calls it takes no mouse at all (no tooltip).
	if b.SetMouseClickEnabled and b.SetMouseMotionEnabled then
		b:EnableMouse(true)
		b:SetMouseClickEnabled(false)
		b:SetMouseMotionEnabled(true)
	else
		b:EnableMouse(false)
	end
	b:Hide()
	view.here = b

	local listening = false
	local function onZone()
		view:PlaceHere()
	end
	view.hereHandler = onZone
	local function listen()
		if not listening then
			listening = true
			for _, e in ipairs(MapHere.EVENTS) do
				ns:RegisterEvent(e, onZone)
			end
		end
	end
	view:HookScript("OnShow", function()
		listen()
		view:PlaceHere()
	end)
	view:HookScript("OnHide", function()
		if listening then
			listening = false
			for _, e in ipairs(MapHere.EVENTS) do
				ns:UnregisterEvent(e, onZone)
			end
		end
	end)
	-- A view made inside a shown window is visible without an OnShow.
	if view:IsVisible() then
		listen()
	end

	-- From MapCanvas's DrawContent: the plan and floor drawn, and how plan coordinates become canvas offsets. Kept, so
	-- a zone change can move the marker on its own.
	function view:DrawHere(plan, floor, px, py, s)
		self.hereArgs = plan and { plan = plan, floor = floor, px = px, py = py, s = s } or nil
		if self:IsVisible() then
			listen()
		end
		return self:PlaceHere()
	end

	-- Show or hide the marker for where the game says the player is now; true when shown.
	function view:PlaceHere()
		local a = self.hereArgs
		local here = a and MapHere.Enabled() and ns.Subzones.Here(a.plan, a.floor)
		if not here then
			b:Hide()
			return false
		end
		local w = self:BaseSize()
		local size = math.max(MapHere.MIN, math.min(MapHere.MAX, MapHere.SPAN * w * a.s))
		local r, g, bl = S.Color("here")
		b:SetSize(size, size)
		b.fill:SetVertexColor(r, g, bl, 0.3)
		b.ring:SetVertexColor(r, g, bl, 0.9)
		b.inner:SetSize(size * 0.55, size * 0.55)
		b.inner:SetVertexColor(r, g, bl, 0.35)
		b:ClearAllPoints()
		b:SetPoint("CENTER", view.canvas, "TOPLEFT", a.px(here.x, here.y), a.py(here.y, here.x))
		W.SetTooltip(b, L["You are here (approx.)"], here.name .. "\n"
			.. L["Inside dungeons the game tells addons only the name of the area you are in, so this marks the middle of that area."])
		b:Show()
		return true
	end
end
