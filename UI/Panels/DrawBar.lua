-- The map's drawing tools (own plans): a second toolbar line under the map tools while "Draw" is the active tool, one
-- line of square picture buttons (names and hints in their tooltips), wrapping only on a table narrower than it.
--   tools    Pen, Line, Arrow, Circle, Box, Text (glyphs of what they draw), Eraser, Move (the game's broom and move
--            cursors, else glyphs)
--   style    the 8 pull colours (the colour-blind setting switches them, drawings included) and 3 line widths (a line
--            of each width); with a drawing selected (Move tool) they restyle it
--   clear    a menu: Clear floor, Clear all; each asks first; Undo brings drawings back
-- It wires the map canvas's drawing callbacks (UI/MapDraw.lua): the active tool, colour and width, which step new
-- drawings belong to (the boss or pull in focus, like party positions), the text field, and a drawing's right-click
-- menu. All changes go through ctx:Changed, so they share the plan's undo history. Recommended plans have no tools.

local _, ns = ...
local DrawBar = ns:NewModule("DrawBar")
local S, W, L = ns.Style, ns.Widgets, ns.L
local Drawing, Util, Schema = ns.Drawing, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local TOOL_HELP = {
	pen = "Drag to draw freehand.",
	line = "Drag from start to end.",
	arrow = "Drag from where to where.",
	circle = "Drag across the circle's box.",
	rect = "Drag from corner to corner.",
	text = "Click to write a label; click a label to change it.",
	erase = "Click or drag over drawings to erase them.",
	move = "Drag a drawing to move it; click one to restyle it with the colours and widths.",
}

-- Glyphs: small pictures drawn with lines in a button's glyph frame (W.Button SetGlyph), in fractions of its size
-- from the top left. Each returns the regions it made, which take the button's text colour.
local function lines(holder, size, thickness, ...)
	local parts, pts = {}, { ... }
	if not holder.CreateLine then
		return parts
	end
	for i = 1, #pts - 3, 4 do
		local l = holder:CreateLine(nil, "ARTWORK")
		l:SetColorTexture(1, 1, 1, 1)
		l:SetThickness(thickness)
		l:SetStartPoint("TOPLEFT", holder, pts[i] * size, -pts[i + 1] * size)
		l:SetEndPoint("TOPLEFT", holder, pts[i + 2] * size, -pts[i + 3] * size)
		parts[#parts + 1] = l
	end
	return parts
end
-- A polyline through the points (x1, y1, x2, y2, ...).
local function path(holder, size, thickness, ...)
	local pts, segs = { ... }, {}
	for i = 1, #pts - 3, 2 do
		segs[#segs + 1], segs[#segs + 2], segs[#segs + 3], segs[#segs + 4] = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
	end
	return lines(holder, size, thickness, unpack(segs))
end
local GLYPHS = {
	pen = function(h, s)
		return path(h, s, 2, 0.1, 0.72, 0.28, 0.4, 0.46, 0.66, 0.64, 0.34, 0.9, 0.52)
	end,
	line = function(h, s)
		return lines(h, s, 2, 0.15, 0.85, 0.85, 0.15)
	end,
	arrow = function(h, s)
		return lines(h, s, 2, 0.15, 0.85, 0.85, 0.15, 0.85, 0.15, 0.45, 0.17, 0.85, 0.15, 0.83, 0.55)
	end,
	circle = function(h, s)
		local pts, n = {}, 16
		for i = 0, n do
			local a = 2 * math.pi * i / n
			pts[#pts + 1], pts[#pts + 2] = 0.5 + 0.38 * math.cos(a), 0.5 + 0.38 * math.sin(a)
		end
		return path(h, s, 2, unpack(pts))
	end,
	rect = function(h, s)
		return path(h, s, 2, 0.12, 0.25, 0.88, 0.25, 0.88, 0.75, 0.12, 0.75, 0.12, 0.25)
	end,
	text = function(h)
		local t = h:CreateFontString(nil, "ARTWORK")
		t:SetFontObject(S.fonts.title)
		t:SetPoint("CENTER")
		t:SetText("T")
		return { t }
	end,
	erase = function(h, s)
		return lines(h, s, 2, 0.2, 0.2, 0.8, 0.8, 0.2, 0.8, 0.8, 0.2)
	end,
	move = function(h, s)
		return lines(h, s, 2, 0.5, 0.1, 0.5, 0.9, 0.1, 0.5, 0.9, 0.5)
	end,
	clear = function(h, s) -- a bin: lid, handle, sides, bottom
		return lines(h, s, 2, 0.16, 0.28, 0.84, 0.28, 0.4, 0.16, 0.6, 0.16, 0.28, 0.36, 0.33, 0.86, 0.72, 0.36, 0.67,
			0.86, 0.33, 0.86, 0.67, 0.86)
	end,
}
DrawBar.GLYPHS = GLYPHS
-- The game's picture for a tool where one fits (UI/Art.lua); the others are glyphs only.
local TOOL_ART = { erase = "draw_erase", move = "draw_move" }

-- Build the bar in the map section `f` (UI/Panels/MapPanel.lua) under its toolbar `bar`, and wire `canvas`.
function DrawBar.Build(f, ctx, bar, canvas)
	ctx.drawTool = ctx.drawTool or "pen"
	ctx.drawColor = ctx.drawColor or 1
	ctx.drawWidth = ctx.drawWidth or 2

	local db = CreateFrame("Frame", nil, f)
	db:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -SP.xs)
	db:SetPoint("RIGHT", f, "RIGHT")
	db:SetHeight(SZ.control)
	db:Hide()
	f.drawBar = db
	db.items = {}

	local function plan()
		return ctx:Plan()
	end
	local function selectedShape()
		local p = plan()
		return p and ctx.selectedShape and Drawing.Find(p, ctx.selectedShape) or nil
	end
	local function changed()
		ctx:Changed("drawings")
	end

	local function add(item, gapBefore)
		item.gapBefore = gapBefore
		db.items[#db.items + 1] = item
		return item
	end

	-- Tools.
	db.tools = {}
	for _, tool in ipairs(ns.MapDraw.TOOLS) do
		local b = W.ToolButton(db, TOOL_ART[tool], GLYPHS[tool], L["draw:" .. tool], L[TOOL_HELP[tool]], function()
			ctx.drawTool = tool
			if tool ~= "move" then
				ctx.selectedShape = nil
			end
			f:Refresh()
		end)
		b.dpGround = "surface"
		db.tools[tool] = b
		add(b)
	end

	-- Colours: the pull palette (Style.PaletteColor), so the colour-blind setting recolours drawings as well.
	db.swatches = {}
	for i = 1, Schema.COLOR_COUNT do
		local b = W.Button(db, "", "outline", function()
			ctx.drawColor = i
			local p, s = plan(), selectedShape()
			if p and s then
				Drawing.Update(p, s.id, { color = i })
				changed()
			else
				f:Refresh()
			end
		end, SZ.control)
		b.chip = b:CreateTexture(nil, "ARTWORK", nil, 3)
		b.chip:SetPoint("TOPLEFT", 5, -5)
		b.chip:SetPoint("BOTTOMRIGHT", -5, 5)
		b.chip:SetColorTexture(1, 1, 1, 1)
		b.dpGround = "surface"
		W.SetTooltip(b, string.format(L["Colour %d"], i), L["The colour of new drawings (and of the selected one)."])
		db.swatches[i] = b
		add(b, i == 1)
	end

	-- Widths: a line as thick as the drawings' (MapDraw.THICKNESS at icon size 100%).
	db.widths = {}
	for i = 1, Drawing.WIDTHS do
		local function glyph(h, s)
			return lines(h, s, ns.MapDraw.THICKNESS[i], 0.1, 0.5, 0.9, 0.5)
		end
		local b = W.ToolButton(db, nil, glyph, L["width:" .. i],
			L["The line width of new drawings (and of the selected one); for text, its size."], function()
				ctx.drawWidth = i
				local p, s = plan(), selectedShape()
				if p and s then
					Drawing.Update(p, s.id, { width = i })
					changed()
				else
					f:Refresh()
				end
			end)
		b.dpGround = "surface"
		db.widths[i] = b
		add(b, i == 1)
	end

	-- Clearing asks first (players have lost work to a stray "clear all" in other planners); Undo brings it back.
	function db:ClearFloor()
		local p = plan()
		local n = p and Drawing.Count(p, ctx.floor) or 0
		if n == 0 then
			return
		end
		W.Confirm(L["Clear this floor's drawings?"],
			ns.Plural(n, L["%d drawing on this floor will be removed. Undo brings it back.|%d drawings on this floor will be removed. Undo brings them back."]),
			L["Clear floor"], function()
				local q = plan()
				if q and Drawing.Clear(q, ctx.floor) > 0 then
					ctx.selectedShape = nil
					changed()
				end
			end)
	end
	function db:ClearAll()
		local p = plan()
		local n = p and Drawing.Count(p) or 0
		if n == 0 then
			return
		end
		W.Confirm(L["Clear every drawing?"],
			ns.Plural(n, L["%d drawing on every floor will be removed. Undo brings it back.|%d drawings on every floor will be removed. Undo brings them back."]),
			L["Clear all"], function()
				local q = plan()
				if q and Drawing.Clear(q) > 0 then
					ctx.selectedShape = nil
					changed()
				end
			end)
	end
	-- One button at the line's end opens the choice (W.Menu), so clearing takes no room of its own.
	function db:ClearItems()
		local p = plan()
		return {
			{ title = L["Clear drawings"] },
			{
				L["Clear floor"],
				function()
					db:ClearFloor()
				end,
				disabled = not p or Drawing.Count(p, ctx.floor) == 0,
			},
			{
				L["Clear all"],
				function()
					db:ClearAll()
				end,
				disabled = not p or Drawing.Count(p) == 0,
			},
		}
	end
	db.clear = add(W.ToolButton(db, "draw_clear", GLYPHS.clear, L["Clear drawings"],
		L["Clear this floor's drawings or every drawing of the plan. Each asks first; Undo brings them back."], function(b)
			W.Menu(b, db:ClearItems())
		end), true)
	db.clear.dpGround = "surface"

	-- Lay the items out in lines as wide as the section, a group (the tools, the colours, the widths, clearing) at a
	-- time: a group that does not fit the rest of a line starts the next one, so no group is split unless it is wider
	-- than a whole line.
	function db:Flow()
		local width = self:GetWidth()
		if not width or width <= 0 then
			width = 640
		end
		local groups, current = {}, nil
		for _, item in ipairs(self.items) do
			if item.gapBefore or not current then
				current = { items = {}, w = 0 }
				groups[#groups + 1] = current
			end
			current.w = current.w + (#current.items > 0 and SP.xs or 0) + item:GetWidth()
			current.items[#current.items + 1] = item
		end
		local x, y = 0, 0
		for _, g in ipairs(groups) do
			if x > 0 and x + SP.md + g.w > width then
				x, y = 0, y + SZ.control + SP.xs
			elseif x > 0 then
				x = x + SP.md
			end
			for i, item in ipairs(g.items) do
				local w = item:GetWidth()
				if i > 1 then
					x = x + SP.xs
				end
				if x > 0 and x + w > width then
					x, y = 0, y + SZ.control + SP.xs
				end
				item:ClearAllPoints()
				item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
				x = x + w
			end
		end
		self:SetHeight(y + SZ.control)
	end
	db:SetScript("OnSizeChanged", function(self)
		self:Flow()
	end)

	function db:Refresh(active)
		self:SetShown(active)
		if not active then
			return
		end
		local p = plan()
		local sel = selectedShape()
		for tool, b in pairs(self.tools) do
			b:SetActive(ctx.drawTool == tool)
		end
		local color = sel and sel.color or ctx.drawColor
		local width = sel and sel.width or ctx.drawWidth
		for i, b in ipairs(self.swatches) do
			b.chip:SetVertexColor(S.PaletteColor(i))
			b:SetActive(color == i)
		end
		for i, b in ipairs(self.widths) do
			b:SetActive(width == i)
		end
		self.clear:SetDisabled(not p or Drawing.Count(p) == 0)
		self:Flow()
	end

	-- Canvas callbacks (UI/MapDraw.lua) --------------------------------------------------------------------------------
	local cb = canvas.cb
	function cb.drawTool()
		if ctx.tool ~= "draw" or ctx:ReadOnly() then
			return nil
		end
		return ctx.drawTool
	end
	function cb.drawStyle()
		return { color = ctx.drawColor, width = ctx.drawWidth }
	end
	-- New drawings belong to the boss or pull in focus (run mode then shows them with that step).
	function cb.drawLinkEncounter()
		return ctx.focusEncounter
	end
	function cb.drawLinkPull()
		return not ctx.focusEncounter and ctx.focusPull or nil
	end
	function cb.getSelectedShape()
		return ctx.tool == "draw" and ctx.selectedShape or nil
	end
	function cb.onSelectShape(id)
		if ctx.selectedShape ~= id then
			ctx.selectedShape = id
			f:Refresh()
		end
	end
	function cb.onNewText(x, y)
		W.AskText(L["Text on the map"], L["A short label, for example a pull's planned forces or \"jump down here\"."], "",
			function(text)
				local p = plan()
				if not p or ctx:ReadOnly() then
					return
				end
				local shape, err = ctx:AddOnFloor(function(floor)
					return Drawing.Add(p, floor, "text", { x, y }, {
						text = text,
						color = ctx.drawColor,
						width = ctx.drawWidth,
						author = ns.MapDraw.Author(),
						encounter = cb.drawLinkEncounter(),
						pull = cb.drawLinkPull(),
					})
				end)
				if shape then
					changed()
				elseif err == "limit" then
					ns:Print(L["This floor has the most drawings a plan can keep. Erase some first."])
				end
			end)
	end
	function cb.onEditText(shape)
		local id = shape.id
		W.AskText(L["Text on the map"], L["Change the label. To remove it, use the eraser."], shape.text or "", function(text)
			local p = plan()
			if p and Drawing.Find(p, id) and Drawing.Update(p, id, { text = text }) then
				changed()
			end
		end)
	end
	function cb.onShapeMenu(shape)
		local p = plan()
		if not p or ctx:ReadOnly() then
			return
		end
		local id = shape.id
		local items = { { title = L["draw:" .. shape.kind] } }
		if shape.author then
			items[#items + 1] = { title = string.format(L["Drawn by %s"], shape.author) }
		end
		if shape.kind == "text" then
			items[#items + 1] = {
				L["Change the text"],
				function()
					cb.onEditText(shape)
				end,
			}
		end
		items[#items + 1] = {
			L["Use the chosen colour and width"],
			function()
				if Drawing.Update(p, id, { color = ctx.drawColor, width = ctx.drawWidth }) then
					changed()
				end
			end,
		}
		local focusEnc, focusPull = ctx.focusEncounter, ctx.focusPull
		if focusEnc or focusPull then
			local name
			if focusEnc then
				local enc = Util.FindById(p.encounters, focusEnc)
				name = enc and ns.Names.Encounter(enc)
			else
				local pull, index = Util.FindById(p.pulls, focusPull)
				name = pull and string.format(L["Pull %d: %s"], index, pull.name)
			end
			if name then
				items[#items + 1] = {
					string.format(L["Show with: %s"], name),
					function()
						if Drawing.Update(p, id, focusEnc and { encounter = focusEnc } or { pull = focusPull }) then
							changed()
						end
					end,
				}
			end
		end
		if shape.pull or shape.encounter then
			items[#items + 1] = {
				L["Show on every step"],
				function()
					if Drawing.Update(p, id, { pull = false, encounter = false }) then
						changed()
					end
				end,
			}
		end
		items[#items + 1] = "-"
		items[#items + 1] = {
			L["Delete"],
			function()
				if Drawing.Remove(p, id) then
					if ctx.selectedShape == id then
						ctx.selectedShape = nil
					end
					changed()
				end
			end,
		}
		W.Menu(canvas, items)
	end
	return db
end
