-- The map's drawing tools (own plans): a second toolbar line under the map tools while "Draw" is the active tool.
--   tools    Pen, Line, Arrow, Circle, Box, Text, Eraser, Move
--   style    the 8 pull colours (the colour-blind setting switches them, drawings included) and 3 line widths; with a
--            drawing selected (Move tool) they restyle it
--   clear    Clear floor, Clear all: each asks first; Undo brings drawings back
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
		local b = W.Button(db, L["draw:" .. tool], "outline", function()
			ctx.drawTool = tool
			if tool ~= "move" then
				ctx.selectedShape = nil
			end
			f:Refresh()
		end)
		b.dpGround = "surface"
		W.SetTooltip(b, L["draw:" .. tool], L[TOOL_HELP[tool]])
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

	-- Widths.
	db.widths = {}
	for i = 1, Drawing.WIDTHS do
		local b = W.Button(db, L["width:" .. i], "outline", function()
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
		W.SetTooltip(b, L["width:" .. i], L["The line width of new drawings (and of the selected one); for text, its size."])
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
	db.clearFloor = add(W.Button(db, L["Clear floor"], "outline", function()
		db:ClearFloor()
	end), true)
	db.clearFloor.dpGround = "surface"
	W.SetTooltip(db.clearFloor, L["Clear floor"], L["Remove every drawing on this floor (asks first)."])
	db.clearAll = add(W.Button(db, L["Clear all"], "outline", function()
		db:ClearAll()
	end))
	db.clearAll.dpGround = "surface"
	W.SetTooltip(db.clearAll, L["Clear all"], L["Remove every drawing of this plan, on every floor (asks first)."])

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
		self.clearFloor:SetDisabled(not p or Drawing.Count(p, ctx.floor) == 0)
		self.clearAll:SetDisabled(not p or Drawing.Count(p) == 0)
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
				local shape, err = Drawing.Add(p, ctx:EditFloor(), "text", { x, y }, {
					text = text,
					color = ctx.drawColor,
					width = ctx.drawWidth,
					author = ns.MapDraw.Author(),
					encounter = cb.drawLinkEncounter(),
					pull = cb.drawLinkPull(),
				})
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
