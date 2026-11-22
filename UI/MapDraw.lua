-- The map canvas, part 3: drawings (Model/Drawing.lua). Draws a plan's shapes on a map view and takes the drawing
-- tools' input: pen (freehand), line, arrow, circle, box, text, eraser and move.
--
-- Drawing: every shape is pooled line segments (the game's Line objects) on the canvas overlay, above the map art and
-- the route, under every pin; a polyline gets round joints only at bends sharper than JOINT_DEGREES, so a smooth stroke
-- costs one line per segment. Text labels are pooled font strings on a dark plate. Nothing is created per redraw, and
-- the drawings redraw only with the map (plan, view, focus or setting changes) or while a stroke is being made.
--
-- Input is part of the map's state machine (view.drag, UI/MapInput.lua): a left press with a drawing tool starts mode
-- "draw" instead of panning; OnUpdate runs only until the button is released, and only the stroke's preview (or the
-- moved shape) is redrawn while it runs. Drawing is never started in combat, and a stroke in progress is dropped when
-- combat starts. Selection and the eraser find shapes by distance (Drawing.HitTest), not by frames under the mouse.

local _, ns = ...
local MapDraw = ns:NewModule("MapDraw")
local S, W = ns.Style, ns.Widgets
local Drawing, Util = ns.Drawing, ns.Util

MapDraw.THICKNESS = { 2, 4, 7 } -- pixels per width at icon scale 1
MapDraw.JOINT_DEGREES = 20
MapDraw.HIT_PIXELS = 8 -- how close a click must be to a shape
MapDraw.SAMPLE_PIXELS = 3 -- a pen stroke takes a point every few pixels
MapDraw.RAW_POINTS = 2000 -- bound on a stroke's raw points before simplification
MapDraw.MAX_SEGMENTS = 2400 -- bound per redraw
MapDraw.TOOLS = { "pen", "line", "arrow", "circle", "rect", "text", "erase", "move" }
MapDraw.FONT = { "caption", "body", "title" } -- text label font per width

local function cursorIn(frame)
	local x, y = GetCursorPosition()
	local s = frame:GetEffectiveScale()
	return x / s, y / s
end

-- Who drew it: the player's name, when the client gives a plain one.
local function author()
	if type(UnitName) ~= "function" then
		return nil
	end
	local ok, name = pcall(UnitName, "player")
	name = ok and Util.Plain(name) or nil
	return type(name) == "string" and name ~= "" and name or nil
end
MapDraw.Author = author

local function inCombat()
	return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end
MapDraw.InCombat = inCombat

function MapDraw.Install(view)
	local overlay = view.overlay
	local pools = view.pools
	pools.drawLines, pools.drawJoints, pools.drawTexts = {}, {}, {}
	pools.previewLines = {}

	local function line(list, i, sublevel)
		local l = list[i]
		if not l and overlay.CreateLine then
			l = overlay:CreateLine(nil, "ARTWORK", nil, sublevel)
			l:SetColorTexture(1, 1, 1, 1)
			list[i] = l
		end
		return l
	end
	local function joint(i)
		local t = pools.drawJoints[i]
		if not t then
			t = overlay:CreateTexture(nil, "ARTWORK", nil, 5)
			t:SetTexture(S.MEDIA .. "Circle")
			pools.drawJoints[i] = t
		end
		return t
	end
	local function label(i)
		local t = pools.drawTexts[i]
		if not t then
			t = W.Text(overlay, "body", "white", "OVERLAY")
			t:SetJustifyH("CENTER")
			t.plate = overlay:CreateTexture(nil, "ARTWORK", nil, 6)
			t.plate:SetColorTexture(0.03, 0.035, 0.045, 0.72)
			t.plate:SetPoint("TOPLEFT", t, "TOPLEFT", -4, 2)
			t.plate:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 4, -2)
			pools.drawTexts[i] = t
		end
		return t
	end

	-- Plan coordinates to canvas offsets, as DrawContent set them for this redraw.
	local function toPx(x, y)
		local ctx = view.shapeCtx
		return ctx.px(x, y), ctx.py(y, x)
	end

	-- The lines of one shape in canvas offsets: polylines, plus the arrow's head built in screen space.
	local function screenLines(shape, thickness, dx, dy)
		local lines = {}
		if shape.kind == "arrow" then
			local p = shape.pts
			local x1, y1 = toPx(p[1] + dx, p[2] + dy)
			local x2, y2 = toPx(p[3] + dx, p[4] + dy)
			lines[1] = { x1, y1, x2, y2 }
			for _, h in ipairs(Drawing.ArrowHead(x1, y1, x2, y2, 10 + 2.5 * thickness, 1) or {}) do
				lines[#lines + 1] = h
			end
			return lines
		end
		for _, poly in ipairs(Drawing.Polylines(shape, { dx = dx, dy = dy })) do
			local out = {}
			for i = 1, #poly - 1, 2 do
				local sx, sy = toPx(poly[i], poly[i + 1])
				out[#out + 1] = sx
				out[#out + 1] = sy
			end
			lines[#lines + 1] = out
		end
		return lines
	end

	local function thicknessOf(width)
		local u = math.max(0.75, view.shapeCtx and view.shapeCtx.scale or 1)
		return (MapDraw.THICKNESS[width] or MapDraw.THICKNESS[2]) * u
	end

	-- Place polylines from the pool `list` starting after n; returns the new count. Joints go on sharp bends.
	local function placeLines(list, n, lines, thickness, r, g, b, a, sublevel, counts)
		local canvas = view.canvas
		for _, poly in ipairs(lines) do
			for i = 3, #poly - 1, 2 do
				if n >= MapDraw.MAX_SEGMENTS then
					return n
				end
				local l = line(list, n + 1, sublevel)
				if l then
					n = n + 1
					l:SetStartPoint("TOPLEFT", canvas, poly[i - 2], poly[i - 1])
					l:SetEndPoint("TOPLEFT", canvas, poly[i], poly[i + 1])
					l:SetThickness(thickness)
					l:SetVertexColor(r, g, b, a)
					l:Show()
				end
			end
			if counts and thickness >= 4 and #poly >= 6 then
				for _, i in ipairs(Drawing.Joints(poly, MapDraw.JOINT_DEGREES, 1)) do
					counts.joints = counts.joints + 1
					local t = joint(counts.joints)
					t:ClearAllPoints()
					t:SetPoint("CENTER", canvas, "TOPLEFT", poly[2 * i - 1], poly[2 * i])
					t:SetSize(thickness, thickness)
					t:SetVertexColor(r, g, b, a)
					t:Show()
				end
			end
		end
		return n
	end

	-- Draw the plan's shapes on `floor`. o = { px, py (plan coordinates to canvas offsets), scale (icon size), mode
	-- ("all" | "step" | "off"), focusPull, focusEncounter, selected (a shape id), moving = { id, dx, dy } }.
	-- Returns the counts drawn.
	function view:DrawShapes(plan, floor, o)
		o = o or {}
		self.shapeCtx = { plan = plan, floor = floor, px = o.px, py = o.py, scale = o.scale or 1, mode = o.mode,
			focusPull = o.focusPull, focusEncounter = o.focusEncounter, selected = o.selected }
		local counts = { shapes = 0, lines = 0, joints = 0, texts = 0 }
		if plan and o.px and o.mode ~= "off" then
			local moving = self.drawMove
			for _, shape in ipairs(Drawing.Shapes(plan)) do
				if shape.floor == floor and Drawing.Visible(shape, o.mode, o.focusPull, o.focusEncounter) then
					counts.shapes = counts.shapes + 1
					local r, g, b = S.PaletteColor(shape.color)
					-- On the full map, drawings tied to another pull or boss than the one in focus dim.
					local dim = o.mode == "all" and (o.focusPull or o.focusEncounter) and (shape.pull or shape.encounter)
						and shape.pull ~= o.focusPull and shape.encounter ~= o.focusEncounter
					local a = dim and 0.35 or 1
					local dx, dy = 0, 0
					if moving and moving.id == shape.id then
						dx, dy = moving.dx or 0, moving.dy or 0
					end
					local th = thicknessOf(shape.width)
					if shape.kind == "text" then
						counts.texts = counts.texts + 1
						local t = label(counts.texts)
						t:SetFontObject(S.fonts[MapDraw.FONT[shape.width] or "body"] or S.fonts.body)
						t:SetText(shape.text or "")
						t:SetTextColor(r, g, b, a)
						t:ClearAllPoints()
						local sx, sy = toPx(shape.pts[1] + dx, shape.pts[2] + dy)
						t:SetPoint("CENTER", self.canvas, "TOPLEFT", sx, sy)
						t:Show()
						t.plate:SetAlpha(a)
						t.plate:SetShown(true)
						if o.selected == shape.id then
							t.plate:SetColorTexture(0.35, 0.3, 0.2, 0.85)
						else
							t.plate:SetColorTexture(0.03, 0.035, 0.045, 0.72)
						end
					else
						local lines = screenLines(shape, th, dx, dy)
						if o.selected == shape.id then
							-- The selected shape: a light halo under its lines.
							counts.lines = placeLines(pools.drawLines, counts.lines, lines, th + 4, 1, 1, 1, 0.55, 4)
						end
						counts.lines = placeLines(pools.drawLines, counts.lines, lines, th, r, g, b, a, 5, counts)
					end
				end
			end
		end
		for i = counts.lines + 1, #pools.drawLines do
			pools.drawLines[i]:Hide()
		end
		for i = counts.joints + 1, #pools.drawJoints do
			pools.drawJoints[i]:Hide()
		end
		for i = counts.texts + 1, #pools.drawTexts do
			pools.drawTexts[i]:Hide()
			pools.drawTexts[i].plate:Hide()
		end
		self.drawCounts = counts
		return counts
	end

	-- Redraw only the drawings (a shape being moved or erased), with what the last full redraw set.
	function view:RedrawShapes()
		local c = self.shapeCtx
		if c then
			self:DrawShapes(c.plan, c.floor, c)
		end
	end

	-- The stroke being drawn: its preview lines (a pool of their own), redrawn as the pointer moves.
	function view:DrawPreview()
		local d = self.drawing
		local n = 0
		if d and self.shapeCtx and self.shapeCtx.px then
			local r, g, b = S.PaletteColor(d.color)
			local th = thicknessOf(d.width)
			local lines
			if d.tool == "pen" then
				-- Only the new part of a freehand stroke is placed; the rest is already on screen.
				local pts = d.pts
				n = d.previewDrawn or 0
				local start = math.max(3, 2 * n + 3)
				local poly = {}
				for i = start - 2, #pts - 1, 2 do
					local sx, sy = toPx(pts[i], pts[i + 1])
					poly[#poly + 1] = sx
					poly[#poly + 1] = sy
				end
				n = placeLines(pools.previewLines, n, { poly }, th, r, g, b, 1, 6)
				d.previewDrawn = n
				return n
			elseif #d.pts >= 4 then
				lines = screenLines({ kind = d.tool, pts = d.pts }, th, 0, 0)
				n = placeLines(pools.previewLines, 0, lines, th, r, g, b, 0.9, 6)
			end
		end
		for i = n + 1, #pools.previewLines do
			pools.previewLines[i]:Hide()
		end
		return n
	end

	local function clearPreview()
		for _, l in ipairs(pools.previewLines) do
			l:Hide()
		end
	end

	-- Input ---------------------------------------------------------------------------------------------------------------

	-- Hit-test tolerance and aspect at the current zoom.
	function view:HitOptions()
		local w, h = self:BaseSize()
		local s = self:Scale()
		local heightPx = math.max(1, h * s)
		return MapDraw.HIT_PIXELS / heightPx, { aspect = w / h, textW = 120 / heightPx, textH = 22 / heightPx }
	end

	function view:ShapeAt(x, y)
		local plan = self.cb.getPlan()
		local c = self.shapeCtx
		if not (plan and x) then
			return nil
		end
		local tol, o = self:HitOptions()
		return Drawing.HitTest(plan, self.cb.getFloor(), x, y, tol, o, function(shape)
			return not c or Drawing.Visible(shape, c.mode or "all", c.focusPull, c.focusEncounter)
		end)
	end

	-- A left press with a drawing tool at map position (x, y). Returns true when the press was taken.
	function view:DrawBegin(x, y)
		local tool = self.cb.drawTool and self.cb.drawTool()
		local plan = self.cb.getPlan()
		if not (tool and plan and x) or self.cb.readOnly() then
			return false
		end
		if inCombat() then
			-- No drawing in combat: the press pans the map instead. The reason is said once per fight.
			if not self.drawCombatNoted then
				self.drawCombatNoted = true
				ns:Print(ns.L["Drawing is not available in combat."])
			end
			return false
		end
		self.drawCombatNoted = nil
		local style = self.cb.drawStyle and self.cb.drawStyle() or { color = 1, width = 2 }
		if tool == "move" then
			local shape = self:ShapeAt(x, y)
			if not shape then
				self.cb.onSelectShape(nil)
				return false -- an empty spot: the map pans
			end
			self.cb.onSelectShape(shape.id)
			self.drawMove = { id = shape.id, x0 = x, y0 = y, dx = 0, dy = 0 }
		elseif tool == "erase" then
			self.drawErase = { removed = 0 }
			self:DrawMove(x, y)
		elseif tool == "text" then
			self.drawing = { tool = "text", x = x, y = y }
		else
			self.drawing = { tool = tool, color = style.color, width = style.width, pts = { x, y }, x0 = x, y0 = y }
		end
		self.drag = { mode = "draw" }
		return true
	end

	-- The pointer moved to (x, y) during a press.
	function view:DrawMove(x, y)
		if not x then
			return
		end
		local plan = self.cb.getPlan()
		local d = self.drawing
		if self.drawMove then
			local m = self.drawMove
			m.dx, m.dy = x - m.x0, y - m.y0
			m.moved = m.moved or math.abs(m.dx) + math.abs(m.dy) > 0.002
			self:RedrawShapes()
		elseif self.drawErase then
			local shape = self:ShapeAt(x, y)
			if shape and plan and Drawing.Remove(plan, shape.id) then
				self.drawErase.removed = self.drawErase.removed + 1
				self:RedrawShapes()
			end
		elseif d and d.tool == "pen" then
			local pts = d.pts
			local w, h = self:BaseSize()
			local s = self:Scale()
			local lx, ly = pts[#pts - 1], pts[#pts]
			local step = MapDraw.SAMPLE_PIXELS
			if (math.abs(x - lx) * w * s >= step or math.abs(y - ly) * h * s >= step) and #pts < 2 * MapDraw.RAW_POINTS then
				pts[#pts + 1] = x
				pts[#pts + 1] = y
				self:DrawPreview()
			end
		elseif d and d.tool ~= "text" then
			d.pts = { d.x0, d.y0, x, y }
			self:DrawPreview()
		end
	end

	-- The press ended: store what was drawn (one undo step), or open the text field.
	function view:DrawEnd()
		local plan = self.cb.getPlan()
		local d, m, e = self.drawing, self.drawMove, self.drawErase
		self.drawing, self.drawMove, self.drawErase = nil, nil, nil
		self:Idle()
		clearPreview()
		if not plan or self.cb.readOnly() then
			return
		end
		if m then
			if m.moved then
				Drawing.Move(plan, m.id, m.dx, m.dy)
				self.cb.onChanged("drawings")
			else
				self:RedrawShapes()
			end
		elseif e then
			if e.removed > 0 then
				self.cb.onChanged("drawings")
			end
		elseif d and d.tool == "text" then
			local existing = self:ShapeAt(d.x, d.y)
			if existing and existing.kind == "text" then
				self.cb.onEditText(existing)
			else
				self.cb.onNewText(d.x, d.y)
			end
		elseif d then
			local w, h = self:BaseSize()
			local s = self:Scale()
			local shape, err = Drawing.Add(plan, self:EditFloor(), d.tool, d.pts, {
				color = d.color,
				width = d.width,
				author = author(),
				aspect = w / h,
				epsilon = 1.5 / math.max(1, h * s), -- a pixel and a half at this zoom
				pull = self.cb.drawLinkPull and self.cb.drawLinkPull() or nil,
				encounter = self.cb.drawLinkEncounter and self.cb.drawLinkEncounter() or nil,
			})
			if shape then
				self.cb.onChanged("drawings")
			elseif err == "limit" then
				ns:Print(ns.L["This floor has the most drawings a plan can keep. Erase some first."])
			end
		end
	end

	-- Drop a stroke in progress without storing it (combat started, the map was hidden).
	function view:DrawCancel()
		local erased = self.drawErase and self.drawErase.removed > 0
		self.drawing, self.drawMove, self.drawErase = nil, nil, nil
		clearPreview()
		if self.drag.mode == "draw" then
			self:Idle()
		end
		if erased then
			self.cb.onChanged("drawings") -- what was erased is gone: make it one undo step
		else
			self:RedrawShapes()
		end
	end

	-- OnUpdate while a drawing press lasts: follow the pointer; combat drops the stroke.
	function view.OnDrawUpdate(self)
		if inCombat() then
			self:DrawCancel()
			return
		end
		self:DrawMove(self:CursorPosition())
	end

	-- A left press on the map: a drawing tool takes it, else the map pans (UI/MapInput.lua).
	function view:DrawPress()
		local x, y = self:CursorPosition()
		if self:DrawBegin(x, y) then
			if self.drag.mode == "draw" then
				self:SetScript("OnUpdate", self.OnDrawUpdate)
			end
			return true
		end
		return false
	end

	MapDraw.CursorIn = cursorIn
end
