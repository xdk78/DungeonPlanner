-- The map canvas, part 2: tooltips and input (UI/MapCanvas.lua draws). Hover a pin for its label, kind, pull, boss
-- and note; click selects, right-click opens its menu, drag moves it (own plans, Select tool). The map itself pans by
-- dragging and zooms with the wheel around the cursor; a click that did not pan places what the current tool places.
-- Dragging is an explicit state machine (view.drag: idle | pan | marker | point | draw, the last in UI/MapDraw.lua) and
-- runs OnUpdate only while the mouse is down; hovering updates the coordinate readout at most 20 times a second.

local _, ns = ...
local MapCanvas = ns.MapCanvas
local Plan, Util = ns.Plan, ns.Util

local MIN_ZOOM, MAX_ZOOM = 1, 8
local CLICK_SLOP = 4 -- pixels of movement before a press becomes a drag

-- A note in a tooltip: estimates ("(approx.)") lose those words and get a muted line saying so instead.
local function addNote(tt, text)
	local note, approx = Util.SplitApprox(text)
	if note and note ~= "" then
		tt:AddLine(note, 1, 1, 1, true)
	end
	if approx then
		tt:AddLine(ns.Style.APPROX .. " " .. ns.L["Approximate: an estimate, check it in game"], 0.6, 0.62, 0.66, true)
	end
end
MapCanvas.AddNote = addNote

local function cursorIn(frame)
	local x, y = GetCursorPosition()
	local s = frame:GetEffectiveScale()
	return x / s, y / s
end

function MapCanvas.InstallInput(view)
	local canvas = view.canvas
	local L = ns.L
	local boss = MapCanvas.BossOf

	-- Tooltips --------------------------------------------------------------------------------------------------------------

	function view:MarkerTooltip(b)
		local plan = self.cb.getPlan()
		local m = plan and Util.FindById(plan.markers, b.markerId)
		local tt = ns.Widgets.Tip()
		if not m or not tt then
			return
		end
		ns.Widgets.TipBeside(tt, b)
		local _, enc = boss(plan, m)
		local title = m.label ~= "" and m.label or (enc and ns.Names.Encounter(enc)) or L[m.kind]
		tt:SetText(title, 1, 0.82, 0, 1, true)
		local kindLine = L[m.kind]
		if m.kind == "position" and m.role then
			kindLine = kindLine .. ": " .. L["role:" .. m.role]
		end
		tt:AddLine(kindLine, 0.75, 0.75, 0.75, true)
		if m.pull then
			local pull, index = Util.FindById(plan.pulls, m.pull)
			if pull then
				tt:AddLine(string.format(L["Pull %d: %s"], index, pull.name), 0.75, 0.75, 0.75, true)
			end
		end
		local menc = m.encounter and Util.FindById(plan.encounters, m.encounter)
		if menc and m.kind ~= "boss" then
			tt:AddLine(string.format(L["For %s"], ns.Names.Encounter(menc)), 0.75, 0.75, 0.75, true)
		end
		if m.toFloor and plan.floors[m.toFloor] then
			tt:AddLine(string.format(L["Leads to %s"], ns.Names.Floor(plan.floors[m.toFloor], m.toFloor)), 0.75,
				0.75, 0.75, true)
		end
		if m.itemID then
			local name = ns.Names.Item and ns.Names.Item(m.itemID)
			if name then
				tt:AddLine(name, 1, 1, 1, true)
			end
		end
		addNote(tt, m.note)
		if not self.cb.readOnly() then
			tt:AddLine(L["Right-click for options"], 0.5, 0.5, 0.5)
		end
		ns.Widgets.TipShow(tt)
	end

	function view:PointTooltip(b)
		local plan = self.cb.getPlan()
		local route = plan and Util.FindById(plan.routes, b.routeId)
		local pt = route and route.points[b.pointIndex]
		local tt = ns.Widgets.Tip()
		if not pt or not tt then
			return
		end
		ns.Widgets.TipBeside(tt, b)
		local number = pt.step and self.cb.stopNumber and self.cb.stopNumber(b.routeId, b.pointIndex)
		if number then
			-- The map shows the step's number (the side panel's); the stop's own order in the route under it.
			tt:SetText(string.format(L["Step %d"], number), 1, 0.82, 0, 1, true)
			tt:AddLine(string.format(L["Stop %d"], pt.step), 0.75, 0.75, 0.75, true)
		elseif pt.step then
			tt:SetText(string.format(L["Stop %d"], pt.step), 1, 0.82, 0, 1, true)
		else
			tt:SetText(ns.Names.Route(route), 1, 0.82, 0, 1, true)
		end
		if route.name ~= "" and pt.step then
			tt:AddLine(ns.Names.Route(route), 0.75, 0.75, 0.75, true)
		end
		if pt.pull then
			local pull, index = Util.FindById(plan.pulls, pt.pull)
			if pull then
				tt:AddLine(string.format(L["Pull %d: %s"], index, pull.name), 0.75, 0.75, 0.75, true)
			end
		end
		addNote(tt, pt.note)
		ns.Widgets.TipShow(tt)
	end

	-- Input ---------------------------------------------------------------------------------------------------------------

	-- Normalized map position under the cursor, or nil outside the map.
	function view:CursorPosition()
		local cx, cy = cursorIn(canvas)
		local left, top = canvas:GetLeft(), canvas:GetTop()
		local cw, ch = canvas:GetWidth(), canvas:GetHeight()
		if not left or cw <= 0 or ch <= 0 then
			return nil
		end
		local x, y = (cx - left) / cw, (top - cy) / ch
		if x < 0 or x > 1 or y < 0 or y > 1 then
			return nil
		end
		-- Back into the plan's own space when a provider map is drawn through an alignment (MapCanvas ToMap).
		return self:FromMap(x, y)
	end

	function view:ZoomAt(delta)
		local old = self:Scale()
		local newZoom = Util.Clamp(self.zoom * (delta > 0 and 1.25 or 0.8), MIN_ZOOM, MAX_ZOOM)
		if newZoom == self.zoom then
			return
		end
		-- Keep the point under the cursor still.
		local cx, cy = cursorIn(self)
		local vx, vy = cx - self:GetLeft(), self:GetTop() - cy
		local mx, my = (vx - self.ox) / old, (vy - self.oy) / old
		self.zoom = newZoom
		local new = self:Scale()
		self.ox, self.oy = vx - mx * new, vy - my * new
		self:Layout()
	end

	function view:ResetView()
		self:FitContent()
	end

	function view.OnDragUpdate(self)
		local d = self.drag
		-- A held button with a still pointer changes nothing: no layout, no redraw.
		local px, py = GetCursorPosition()
		if px == d.lastX and py == d.lastY then
			return
		end
		d.lastX, d.lastY = px, py
		if d.mode == "pan" then
			local cx, cy = cursorIn(self)
			local dx, dy = cx - d.startX, d.startY - cy
			if math.abs(dx) + math.abs(dy) > CLICK_SLOP then
				d.moved = true
			end
			if d.moved then
				-- Transform only: the canvas follows the pointer; the full layout waits for the release.
				self.ox, self.oy = d.ox + dx, d.oy + dy
				self:MoveCanvas()
			end
		elseif d.mode == "marker" or d.mode == "point" then
			local x, y = self:CursorPosition()
			local plan = self.cb.getPlan()
			if x and plan then
				if d.mode == "marker" then
					local m = Util.FindById(plan.markers, d.id)
					if m then
						m.x, m.y = Util.Round(x, 4), Util.Round(y, 4)
					end
				else
					local route = Util.FindById(plan.routes, d.routeId)
					local pt = route and route.points[d.index]
					if pt then
						pt[1], pt[2] = Util.Round(x, 4), Util.Round(y, 4)
					end
				end
				d.moved = true
				self:DrawContent()
			end
		end
		self:UpdateCoords()
	end

	function view:EndDrag()
		local d = self.drag
		local plan = self.cb.getPlan()
		if plan and d.moved then
			if d.mode == "marker" then
				local m = Util.FindById(plan.markers, d.id)
				if m then
					Plan.MoveMarker(plan, d.id, m.x, m.y)
					self.cb.onChanged("markers")
				end
			elseif d.mode == "point" then
				local route = Util.FindById(plan.routes, d.routeId)
				local pt = route and route.points[d.index]
				if pt then
					Plan.MoveRoutePoint(plan, d.routeId, d.index, pt[1], pt[2])
					self.cb.onChanged("routes")
				end
			end
		end
		self:Idle()
	end
	view.EndMarkerDrag = view.EndDrag

	function view:UpdateCoords()
		if not self.cb.showCoordinates() then
			self.coords:SetText("")
			return
		end
		local x, y = self:CursorPosition()
		if x then
			self.coords:SetText(string.format("%.1f, %.1f", x * 100, y * 100))
		else
			self.coords:SetText("")
		end
	end

	function view:OnMarkerClick(markerId, mouse, button)
		local plan = self.cb.getPlan()
		if not plan then
			return
		end
		local tool = self.cb.getTool()
		if mouse == "RightButton" then
			self.cb.onMarkerMenu(markerId, button)
		elseif tool == "erase" then
			if not self.cb.readOnly() then
				Plan.RemoveMarker(plan, markerId)
				self.cb.onSelectMarker(nil)
				self.cb.onChanged("markers")
			end
		else
			self.cb.onSelectMarker(markerId)
		end
	end

	function view:OnPointClick(routeId, index, mouse, button)
		local plan = self.cb.getPlan()
		if not plan then
			return
		end
		if mouse == "RightButton" then
			if self.cb.onPointMenu then
				self.cb.onPointMenu(routeId, index, button)
			end
		elseif self.cb.getTool() == "erase" and not self.cb.readOnly() then
			local route = Util.FindById(plan.routes, routeId)
			if route and route.points[index] then
				table.remove(route.points, index)
				Plan.RenumberStops(plan, routeId)
				self.cb.onChanged("routes")
			end
		elseif self.cb.onSelectRoute then
			self.cb.onSelectRoute(routeId)
		end
	end

	-- A click on the map (not on a pin), after the press did not turn into a pan.
	function view:OnMapClick(mouse)
		local plan = self.cb.getPlan()
		if not plan or self.cb.readOnly() then
			if plan and mouse ~= "RightButton" then
				self.cb.onSelectMarker(nil)
			end
			return
		end
		local x, y = self:CursorPosition()
		local tool = self.cb.getTool()
		if mouse == "RightButton" then
			if tool == "route" then
				self.cb.onRouteFinished()
			elseif self.cb.drawTool and self.cb.drawTool() and self.cb.onShapeMenu then
				-- A drawing under the pointer: its menu (colour, link, text, delete).
				local shape = self.ShapeAt and self:ShapeAt(x, y)
				if shape then
					self.cb.onShapeMenu(shape)
				end
			end
			return
		end
		if not x then
			return
		end
		if tool == "marker" or tool == "position" then
			local kind = tool == "position" and "position" or self.cb.getKind()
			local extra
			if kind == "position" then
				extra = {
					role = self.cb.getRole and self.cb.getRole() or "TANK",
					encounter = self.cb.getFocusEncounter and self.cb.getFocusEncounter() or nil,
					pull = (not (self.cb.getFocusEncounter and self.cb.getFocusEncounter())) and self.cb.getFocusPull
						and self.cb.getFocusPull() or nil,
				}
			end
			local m, err = Plan.AddMarker(plan, self.cb.getFloor(), x, y, kind, nil, extra)
			if m then
				self.cb.onSelectMarker(m.id)
				self.cb.onChanged("markers")
			else
				ns:Print(ns.L["Cannot add more markers:"], err)
			end
		elseif tool == "route" then
			self.cb.onRoutePoint(x, y, IsShiftKeyDown and IsShiftKeyDown() or false)
		else
			self.cb.onSelectMarker(nil)
		end
	end

	view:SetScript("OnMouseDown", function(self, mouse)
		-- One drag at a time: a second button pressed during a stroke or a pan must not replace it (an eraser stroke
		-- replaced by a pan would never report the shapes it removed).
		if self.drag.mode ~= "idle" then
			return
		end
		ns.Widgets.CommitFocus()
		-- A drawing tool takes a left press (UI/MapDraw.lua); otherwise the press may become a pan.
		if mouse == "LeftButton" and self.DrawPress and self:DrawPress() then
			if self.drag.mode == "draw" then
				self.drag.button = mouse
			end
			return
		end
		local cx, cy = cursorIn(self)
		self.drag = { mode = "pan", startX = cx, startY = cy, ox = self.ox, oy = self.oy, moved = false, button = mouse }
		self:SetScript("OnUpdate", self.OnDragUpdate)
	end)
	view:SetScript("OnMouseUp", function(self, mouse)
		local d = self.drag
		if d.button and d.button ~= mouse then
			return -- another button's release
		end
		if d.mode == "draw" then
			self:DrawEnd()
			return
		end
		self:Idle()
		if d.mode == "pan" and d.moved then
			self:Layout()
		elseif d.mode == "pan" then
			self:OnMapClick(mouse)
		end
	end)
	view:SetScript("OnMouseWheel", function(self, delta)
		self:ZoomAt(delta)
	end)
	-- While the pointer is over the map, the coordinate readout updates at most 20 times a second.
	local sinceCoords = 0
	local function hoverUpdate(v, elapsed)
		sinceCoords = sinceCoords + (elapsed or 0)
		if sinceCoords >= 0.05 then
			sinceCoords = 0
			v:UpdateCoords()
		end
	end
	-- Back to idle after a press, a drag or a stroke: the coordinate readout keeps following a pointer that is still
	-- over the map.
	function view:Idle()
		self.drag = { mode = "idle" }
		local hover = self:IsVisible() and self:IsMouseOver() and self.cb.showCoordinates()
		self:SetScript("OnUpdate", hover and hoverUpdate or nil)
	end
	view:SetScript("OnEnter", function(self)
		if self.drag.mode == "idle" and self.cb.showCoordinates() then
			self:SetScript("OnUpdate", hoverUpdate)
		end
	end)
	view:SetScript("OnLeave", function(self)
		if self.drag.mode == "idle" then
			self:SetScript("OnUpdate", nil)
			self.coords:SetText("")
		end
	end)
	-- HookScript: the backdrop mixin listens to size changes too.
	view:HookScript("OnSizeChanged", function(self)
		self:Layout()
	end)
	view:SetScript("OnHide", function(self)
		if self.drag.mode == "pan" and self.drag.moved then
			self:Layout()
		elseif self.drag.mode == "marker" or self.drag.mode == "point" then
			self:EndDrag()
		elseif self.drag.mode == "draw" then
			self:DrawCancel()
		end
		self.drag = { mode = "idle" }
		self:SetScript("OnUpdate", nil)
	end)
end
