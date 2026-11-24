-- The map's "You are here (approx.)" marker, installed on a map view (UI/MapCanvas.lua): the map section's and run
-- mode's mini map alike.
--
-- Inside a dungeon the game names only the area the player is in (Data/Subzones.lua), so the marker is an area, not a
-- point: a soft disc with a ring at the middle of that area, sized in map units so it grows with the zoom like the
-- room it stands for. It shows only inside the plan's own instance, while the area has an anchor on the floor shown,
-- and with the setting "Show where you are on dungeon maps" on.
--
-- It takes no mouse, so the enemy dots, route legs and coordinates under it keep theirs: the map's own hover update
-- (UI/MapInput.lua) shows its tooltip when the pointer is inside it and nothing else is hovered. Where the player is
-- is asked on the zone events and when the view shows, not on every draw; the events are registered only while the
-- view is shown, and a zone change moves the marker alone. No OnUpdate of its own.

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
	b:EnableMouse(false)
	b.fill = b:CreateTexture(nil, "ARTWORK", nil, 0)
	b.fill:SetTexture(S.MEDIA .. "Circle")
	b.fill:SetAllPoints()
	b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.ring:SetTexture(S.MEDIA .. "Ring")
	b.ring:SetAllPoints()
	b.inner = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.inner:SetTexture(S.MEDIA .. "Ring")
	b.inner:SetPoint("CENTER")
	b:Hide()
	view.here = b

	local function hideTip()
		local tt = W.Tip()
		if view.hereTip and tt and tt:IsOwned(view) then
			tt:Hide()
		end
		view.hereTip = nil
	end

	local listening = false
	local function onZone()
		view.hereWhere = ns.Subzones.Where()
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
		onZone()
	end)
	view:HookScript("OnHide", function()
		hideTip()
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

	-- Show or hide the marker for where the game said the player is; true when shown.
	function view:PlaceHere()
		local a = self.hereArgs
		if a and not self.hereWhere then
			self.hereWhere = ns.Subzones.Where()
		end
		local here = a and MapHere.Enabled() and ns.Subzones.Here(a.plan, a.floor, self.hereWhere)
		self.hereAt = nil
		if not here then
			b:Hide()
			hideTip()
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
		local x, y = a.px(here.x, here.y), a.py(here.y, here.x)
		b:ClearAllPoints()
		b:SetPoint("CENTER", view.canvas, "TOPLEFT", x, y)
		self.hereAt = { x = x, y = y, r = size / 2, name = here.name }
		b:Show()
		return true
	end

	-- From the map's hover update: the pointer at canvas offset (x, y) (y up, as the marker is placed), or nil when it
	-- left the map. The tooltip shows while the pointer is inside the marker and no route leg has the tooltip.
	function view:HereHover(x, y)
		if self.routeTip then
			self.hereTip = nil
			return
		end
		local at = self.hereAt
		if not (at and x and (x - at.x) ^ 2 + (y - at.y) ^ 2 <= at.r ^ 2) then
			hideTip()
			return
		end
		if self.hereTip == at then
			return
		end
		local tt = W.Tip()
		if not tt then
			return
		end
		tt:SetOwner(self, "ANCHOR_CURSOR")
		tt:SetText(L["You are here (approx.)"], 1, 0.82, 0)
		tt:AddLine(at.name, 1, 1, 1, true)
		tt:AddLine(L["Inside dungeons the game tells addons only the name of the area you are in, so this marks the middle of that area."],
			1, 1, 1, true)
		W.TipShow(tt)
		self.hereTip = at
	end
end
