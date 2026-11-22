-- The map's drawing tools end to end against the mock client: the Draw tool and its bar, strokes, shapes and text,
-- move, restyle, erase, the legend switch, clearing with a confirmation, undo and redo, nothing in combat, no tools on a
-- recommended plan, and run mode's drawings switch.
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

-- A fresh own plan on the test dungeon, its map section open with the Draw tool.
local function drawMap()
	boot()
	local entry = ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
	local plan = ns.Home.CreatePlan("dungeon", "Drawing test", entry)
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local ctx = ns.UI.ctx
	ctx.tool = "draw"
	ctx.focusPull, ctx.focusEncounter, ctx.selectedShape = nil, nil, nil
	map:Refresh()
	return plan, map, map.canvas, ctx
end

-- Hide whatever dialogs earlier steps left open (each Hide shows the next queued one).
local function closeDialogs()
	local dialog = _G.DungeonPlannerDialog
	for _ = 1, 10 do
		if not (dialog and dialog:IsShown()) then
			return
		end
		dialog:Hide()
	end
end

local function click(button)
	button:GetScript("OnClick")(button, "LeftButton")
end

T.case("Drawing UI: the Draw tool shows its bar; strokes, shapes and text become drawings with one undo each", function()
	local plan, map, canvas, ctx = drawMap()
	T.ok(map.toolButtons.draw:IsShown(), "Draw tool on an own plan")
	T.ok(map.drawBar:IsShown(), "the drawing line under the toolbar")
	T.eq(select(2, canvas:GetPoint(1)), map.drawBar, "the map sits under it")
	-- A pen stroke: press, move (several samples), release.
	ctx.drawTool, ctx.drawColor, ctx.drawWidth = "pen", 3, 3
	T.ok(canvas:DrawBegin(0.1, 0.1), "a press with a drawing tool is taken")
	T.eq(canvas.drag.mode, "draw")
	for i = 1, 40 do
		canvas:DrawMove(0.1 + i * 0.01, 0.1 + ((i % 2) * 0.0004))
	end
	T.ok(canvas.pools.previewLines[1] and canvas.pools.previewLines[1]:IsShown(), "a preview while drawing")
	canvas:DrawEnd()
	T.eq(canvas.drag.mode, "idle")
	local shapes = ns.Drawing.Shapes(plan)
	T.eq(#shapes, 1, "one stroke")
	T.eq(shapes[1].kind, "pen")
	T.eq(shapes[1].color, 3)
	T.ok(#shapes[1].pts <= 8, "a straight wobbly stroke is simplified")
	T.ok(not canvas.pools.previewLines[1]:IsShown(), "preview gone")
	-- An arrow, a box, a circle and a line.
	for _, tool in ipairs({ "arrow", "rect", "circle", "line" }) do
		ctx.drawTool = tool
		canvas:DrawBegin(0.4, 0.4)
		canvas:DrawMove(0.6, 0.55)
		canvas:DrawEnd()
	end
	T.eq(#ns.Drawing.Shapes(plan), 5)
	-- A click with the line tool draws nothing.
	ctx.drawTool = "line"
	canvas:DrawBegin(0.7, 0.7)
	canvas:DrawEnd()
	T.eq(#ns.Drawing.Shapes(plan), 5, "a click is not a line")
	-- Text: a click asks for the label.
	closeDialogs()
	ctx.drawTool = "text"
	canvas:DrawBegin(0.8, 0.2)
	canvas:DrawEnd()
	local dialog = _G.DungeonPlannerDialog
	T.ok(dialog:IsShown(), "the text field")
	dialog.input:SetValue("Jump down")
	click(dialog.buttons[1])
	shapes = ns.Drawing.Shapes(plan)
	T.eq(shapes[#shapes].text, "Jump down")
	-- Drawn: lines for the shapes, a label for the text.
	canvas:DrawContent()
	T.eq(canvas.counts.shapes, 6)
	T.ok(canvas.drawCounts.lines >= 3 + 4 + 24 + 1, "segments for every shape: " .. canvas.drawCounts.lines)
	T.eq(canvas.drawCounts.texts, 1)
	-- Undo takes back the label, then the line; redo brings the line back.
	T.ok(ctx:CanUndo())
	ctx:Undo()
	T.eq(#ns.Drawing.Shapes(plan), 5, "undo: the label")
	ctx:Undo()
	T.eq(#ns.Drawing.Shapes(plan), 4, "undo: the line")
	T.ok(ctx:CanRedo())
	ctx:Redo()
	T.eq(#ns.Drawing.Shapes(plan), 5, "redo: the line")
	T.ok(_G.DungeonPlannerMainFrame.instancePage.header.redo:IsShown(), "Redo in the header")
end)

T.case("Drawing UI: move, restyle, erase, the menu, the legend switch and clearing with a confirmation", function()
	local plan, map, canvas, ctx = drawMap()
	ctx.drawTool = "line"
	canvas:DrawBegin(0.2, 0.5)
	canvas:DrawMove(0.6, 0.5)
	canvas:DrawEnd()
	local line = ns.Drawing.Shapes(plan)[1]
	-- Move: a press on the line selects it, dragging moves it as one undo step.
	ctx.drawTool = "move"
	T.ok(canvas:DrawBegin(0.4, 0.5), "a press on a drawing")
	T.eq(ctx.selectedShape, line.id, "selected")
	canvas:DrawMove(0.4, 0.6)
	canvas:DrawEnd()
	T.eq(line.pts[2], 0.6, "moved down")
	ctx:Undo()
	line = ns.Drawing.Shapes(plan)[1]
	T.eq(line.pts[2], 0.5, "undo puts it back")
	-- A press on an empty spot with Move pans the map instead.
	T.ok(not canvas:DrawBegin(0.9, 0.1), "not taken: the map pans")
	-- Restyle the selected drawing from the bar.
	canvas:DrawBegin(0.4, 0.5)
	canvas:DrawEnd()
	click(map.drawBar.swatches[6])
	click(map.drawBar.widths[1])
	line = ns.Drawing.Shapes(plan)[1]
	T.eq(line.color, 6)
	T.eq(line.width, 1)
	-- The right-click menu opens for a drawing.
	canvas.cb.onShapeMenu(line)
	-- Legend (opened: untouched, it folds over the map): the Drawings layer hides them.
	ns.db.ui.legendFolded = false
	map:Refresh()
	ns.db.ui.legendFolded = nil
	local row
	for _, r in ipairs(map.legend.rows) do
		if r.layer.id == "drawings" then
			row = r
		end
	end
	T.ok(row and row:IsShown(), "a Drawings row in the legend")
	T.eq(row.count:GetText(), "1")
	row.check:GetScript("OnClick")(row.check)
	T.eq(ns.db.ui.mapLayers.drawings, false)
	canvas:DrawContent()
	T.eq(canvas.counts.shapes, 0, "hidden")
	ns.db.ui.mapLayers.drawings = nil
	canvas:DrawContent()
	-- Eraser: a press over a drawing removes it, as one undo step.
	ctx.drawTool = "erase"
	canvas:DrawBegin(0.3, 0.5)
	canvas:DrawEnd()
	T.eq(#ns.Drawing.Shapes(plan), 0, "erased")
	ctx:Undo()
	T.eq(#ns.Drawing.Shapes(plan), 1, "undo brings it back")
	-- The clear button opens a menu (the game's context menu, captured here): Clear floor and Clear all.
	closeDialogs()
	map:Refresh()
	local menu
	local fakeMenuUtil = {
		CreateContextMenu = function(owner, generate)
			menu = { owner = owner, buttons = {} }
			generate(owner, {
				CreateTitle = function(_, text)
					menu.title = text
				end,
				CreateDivider = function() end,
				CreateButton = function(_, text, fn)
					local desc = { text = text, fn = fn, enabled = true }
					function desc:SetEnabled(on)
						self.enabled = on
					end
					menu.buttons[#menu.buttons + 1] = desc
					return desc
				end,
			})
		end,
	}
	-- MenuUtil's elements take a boolean or a predicate; W.Menu passes a predicate.
	local function enabled(desc)
		if type(desc.enabled) == "function" then
			return desc.enabled(desc)
		end
		return desc.enabled
	end
	_G.MenuUtil = fakeMenuUtil
	T.ok(map.drawBar.clear:IsEnabled(), "the clear button with drawings on the plan")
	click(map.drawBar.clear)
	_G.MenuUtil = nil
	T.ok(menu and menu.owner == map.drawBar.clear, "a menu at the clear button")
	T.eq(menu.title, ns.L["Clear drawings"])
	T.eq(menu.buttons[1].text, ns.L["Clear floor"])
	T.eq(menu.buttons[2].text, ns.L["Clear all"])
	T.ok(enabled(menu.buttons[1]) and enabled(menu.buttons[2]), "both enabled with a drawing on this floor")
	-- Without MenuUtil the same actions open in the addon's own popup list.
	click(map.drawBar.clear)
	local popup = ns.Widgets.ActivePopup()
	T.ok(popup and popup.owner == map.drawBar.clear, "the popup list at the clear button")
	T.eq(#popup.rows, 2, "Clear floor and Clear all")
	T.eq(popup.rows[1].text, ns.L["Clear floor"])
	popup:Choose(1)
	T.ok(not ns.Widgets.ActivePopup(), "closed on a choice")
	T.ok(_G.DungeonPlannerDialog:IsShown(), "the choice asks first, as from the game's menu")
	closeDialogs()
	-- Clear floor asks first: nothing goes until the player confirms; Cancel keeps everything.
	menu.buttons[1].fn()
	local dialog = _G.DungeonPlannerDialog
	T.ok(dialog:IsShown(), "a confirmation")
	T.eq(#ns.Drawing.Shapes(plan), 1, "nothing removed yet")
	click(dialog.buttons[2])
	T.eq(#ns.Drawing.Shapes(plan), 1, "cancelled")
	menu.buttons[2].fn()
	T.ok(dialog:IsShown(), "clear all asks too")
	click(dialog.buttons[1])
	T.eq(#ns.Drawing.Shapes(plan), 0, "cleared after the confirmation")
	T.ok(not map.drawBar.clear:IsEnabled(), "nothing left to clear: the button is disabled")
	ctx:Undo()
	T.eq(#ns.Drawing.Shapes(plan), 1, "and undo brings it back")
	-- On another floor only Clear all has something to clear.
	ctx.floor = 2
	local items = map.drawBar:ClearItems()
	T.ok(items[2].disabled, "Clear floor greyed out on an empty floor")
	T.ok(not items[3].disabled, "Clear all still offered")
	_G.MenuUtil = fakeMenuUtil
	click(map.drawBar.clear)
	_G.MenuUtil = nil
	T.eq(enabled(menu.buttons[1]), false, "the game's menu greys it out")
	T.eq(enabled(menu.buttons[2]), true)
	click(map.drawBar.clear)
	T.eq(#ns.Widgets.ActivePopup().rows, 1, "our popup list leaves it out")
	ns.Widgets.ClosePopup()
	ctx.floor = 1
end)

-- The draw line and the tools' line: pictures with tooltips, the same tools behind them, fallbacks without the art.
T.case("Map toolbar: tool pictures, their fallbacks, tooltips and the lines' fit", function()
	local _, map, _, ctx = drawMap()
	-- The mock client lacks the toolbar's atlases: the tools show their names, the drawing tools their glyphs.
	for _, tool in ipairs(ns.MapToolbar.TOOLS) do
		local b = map.toolButtons[tool]
		T.ok(not b.icon:IsShown(), tool .. ": no picture without the atlas")
		T.ok(b.label:IsShown() and b.label:GetText() ~= "", tool .. ": its name instead")
		T.ok(b.dpTooltipTitle and b.dpTooltipText, tool .. ": a tooltip")
		click(b)
		T.eq(ctx.tool, tool, tool .. ": a click chooses it")
		T.ok(b.dpActive, tool .. ": lit")
		for other, ob in pairs(map.toolButtons) do
			if other ~= tool then
				T.ok(not ob.dpActive, "one tool lit at a time")
			end
		end
	end
	click(map.toolButtons.draw)
	local db = map.drawBar
	for _, tool in ipairs(ns.MapDraw.TOOLS) do
		local b = db.tools[tool]
		T.eq(b:GetWidth(), ns.Style.SIZE.control, tool .. ": a square button")
		T.ok(b.glyph and b.glyph:IsShown() and #b.glyph.parts > 0, tool .. ": its glyph")
		T.ok(not b.label:IsShown(), tool .. ": no words on the button")
		T.eq(b.dpTooltipTitle, ns.L["draw:" .. tool], tool .. ": named in the tooltip")
		T.ok(b.dpTooltipText, tool .. ": with a hint")
		click(b)
		T.eq(ctx.drawTool, tool, tool .. ": a click chooses it")
		T.ok(b.dpActive, tool .. ": lit")
	end
	for i, b in ipairs(db.widths) do
		T.eq(b:GetWidth(), ns.Style.SIZE.control, "width " .. i .. ": square")
		T.eq(b.dpTooltipTitle, ns.L["width:" .. i])
		click(b)
		T.eq(ctx.drawWidth, i)
	end
	T.ok(db.clear.glyph:IsShown(), "the clear button's bin glyph")
	-- One line: tools, colours, widths and the clear button.
	db:SetWidth(600)
	db:Flow()
	T.eq(db:GetHeight(), ns.Style.SIZE.control, "the drawing tools fit one line 600 px wide")
	local _, _, _, x = db.clear:GetPoint(1)
	T.ok(x + db.clear:GetWidth() <= 600, "the clear button at the line's end")
	-- A disabled button keeps its glyph, greyed.
	db.clear:SetDisabled(true)
	local r, g, bl = db.clear.glyph.parts[1]:GetVertexColor()
	T.eq(string.format("%.2f %.2f %.2f", r, g, bl), string.format("%.2f %.2f %.2f", ns.Style.Color("dim")))
	db.clear:SetDisabled(false)
	-- With the atlases the pictures show: the game's art for the tools and for Eraser and Move.
	for _, key in ipairs({ "tool_select", "tool_marker", "tool_position", "tool_pull", "tool_route", "tool_draw",
		"tool_erase", "draw_erase", "draw_move", "draw_clear" }) do
		mock.atlases[ns.Art.SPECS[key].atlas] = true
	end
	ns.Art.ForgetFiles()
	local b = ns.Widgets.Button(map, "Select", "outline")
	T.ok(b:SetIcon("tool_select"), "the atlas is used")
	T.ok(b.icon:IsShown() and b.label:IsShown(), "picture and name")
	local wide = b:GetWidth()
	b:SetCompact(true)
	T.eq(b:GetWidth(), ns.Style.SIZE.control, "compact: the picture alone")
	T.ok(not b.label:IsShown())
	b:SetCompact(false)
	T.eq(b:GetWidth(), wide, "and back")
	local t = ns.Widgets.ToolButton(map, "draw_move", ns.DrawBar.GLYPHS.move, "Move", "hint")
	T.ok(t.icon:IsShown() and not t.glyph:IsShown(), "the game's picture over the glyph")
	-- A picture that is not square keeps its shape in the square slot (the atlas's size from GetAtlasInfo).
	mock.atlases[ns.Art.SPECS.tool_position.atlas] = { 29, 26 }
	ns.Art.ForgetFiles()
	local pos = ns.Widgets.Button(map, "Position", "outline")
	pos:SetIcon("tool_position")
	T.eq(pos.icon:GetWidth(), 18, "as wide as the slot")
	T.eq(string.format("%.2f", pos.icon:GetHeight()), string.format("%.2f", 18 * 26 / 29), "and shorter")
	mock.atlases[ns.Art.SPECS.tool_position.atlas] = true
	ns.Art.ForgetFiles()
	-- Built again with the atlases, the tools' line shows pictures; the names give way on a narrow table.
	local f = ns.Panels.map.Create(_G.DungeonPlannerMainFrame, ctx)
	f:SetSize(1000, 600)
	f.bar:SetWidth(1000)
	ctx.tool = "select"
	f.kind:Hide()
	f.role:Hide()
	f.pull:Hide()
	ns.MapToolbar.Layout(f, f.bar, false)
	T.ok(f.toolButtons.select.icon:IsShown(), "a picture on the tool")
	T.ok(f.toolButtons.select.label:IsShown(), "and its name on a wide table")
	-- Narrowing step by step (the bar's OnSizeChanged lays it out again): each level hides one more thing, nothing
	-- comes back; widening brings everything back in the reverse order, the names included.
	local resized = f.bar:GetScript("OnSizeChanged")
	local function levelAt(w)
		f.bar:SetWidth(w)
		resized(f.bar)
		local named = f.toolButtons.select.label:IsShown()
		local level = (f.focus:IsShown() and 1) or (named and 2) or (f.fit:IsShown() and 3) or 4
		local spec = ns.MapToolbar.LEVELS[level]
		T.eq(f.focus:IsShown(), spec.focus, w .. " px: Focus")
		T.eq(f.fit:IsShown(), spec.fit, w .. " px: Fit")
		for _, tool in ipairs(ns.MapToolbar.TOOLS) do
			local b = f.toolButtons[tool]
			T.eq(b.label:IsShown(), spec.names, w .. " px: " .. tool .. "'s name")
			T.eq(b:GetWidth(), b:WidthFor(not spec.names), w .. " px: " .. tool .. "'s width")
		end
		return level
	end
	local seen, last = {}, 1
	for w = 1000, 200, -2 do
		local level = levelAt(w)
		T.ok(level >= last, w .. " px: narrowing never brings anything back")
		seen[level], last = true, level
	end
	T.ok(seen[1] and seen[2] and seen[3] and seen[4], "every level on the way down")
	for w = 200, 1000, 2 do
		local level = levelAt(w)
		T.ok(level <= last, w .. " px: widening never hides anything")
		last = level
	end
	T.eq(last, 1, "everything back on a wide table")
	T.ok(f.toolButtons.select.label:IsShown(), "the names included")
	for _, key in ipairs({ "tool_select", "tool_marker", "tool_position", "tool_pull", "tool_route", "tool_draw",
		"tool_erase", "draw_erase", "draw_move", "draw_clear" }) do
		mock.atlases[ns.Art.SPECS[key].atlas] = nil
	end
	ns.Art.ForgetFiles()
	f:Hide()
end)

T.case("Drawing UI: nothing in combat, no tools on a recommended plan, run mode shows a step's drawings", function()
	local plan, _, canvas, ctx = drawMap()
	ctx.drawTool = "pen"
	mock.inCombat = true
	T.ok(not canvas:DrawBegin(0.1, 0.1), "the press is left to the map")
	T.ok(canvas.drag.mode ~= "draw", "no stroke starts in combat")
	-- The left button pans instead.
	canvas:GetScript("OnMouseDown")(canvas, "LeftButton")
	T.eq(canvas.drag.mode, "pan", "the map pans with the Draw tool in combat")
	canvas:GetScript("OnMouseUp")(canvas, "LeftButton")
	T.eq(canvas.drag.mode, "idle")
	mock.inCombat = false
	-- A stroke under way is dropped when combat starts.
	canvas:DrawBegin(0.1, 0.1)
	canvas:SetScript("OnUpdate", canvas.OnDrawUpdate)
	canvas:DrawMove(0.3, 0.3)
	mock.inCombat = true
	canvas.OnDrawUpdate(canvas)
	mock.inCombat = false
	T.eq(canvas.drag.mode, "idle", "dropped")
	T.eq(#ns.Drawing.Shapes(plan), 0, "nothing stored")
	T.eq(canvas:GetScript("OnUpdate"), nil, "no OnUpdate left running")
	-- Drawings tied to a pull show with that step in run mode.
	local pull = ns.Plan.AddPull(plan, "First")
	ns.Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.3, 0.3 }, { pull = pull.id })
	ns.Drawing.Add(plan, 1, "line", { 0.5, 0.5, 0.7, 0.7 })
	ctx:Changed("drawings")
	ns.RunMode.Show()
	local f = _G.DungeonPlannerRunFrame
	ctx.focusPull, ctx.focusEncounter = nil, nil
	ns.db.ui.run.drawings = nil
	T.eq(ns.RunMode.DrawingsMode(), "step", "this step's drawings by default")
	f.map:DrawContent()
	T.eq(f.map.counts.shapes, 1, "only the drawing tied to no step")
	ctx.focusPull = pull.id
	f.map:DrawContent()
	T.eq(f.map.counts.shapes, 2, "and the pull's with its step")
	ctx.focusPull = nil
	ns.RunMode.Refresh()
	T.ok(f.drawings:IsShown(), "the switch shows when the plan has drawings")
	f.drawings:GetScript("OnClick")(f.drawings)
	T.eq(ns.RunMode.DrawingsMode(), "all")
	f.map:DrawContent()
	T.eq(f.map.counts.shapes, 2)
	f.drawings:GetScript("OnClick")(f.drawings)
	T.eq(ns.RunMode.DrawingsMode(), "off", "one click hides them")
	f.map:DrawContent()
	T.eq(f.map.counts.shapes, 0)
	f.drawings:GetScript("OnClick")(f.drawings)
	T.eq(ns.RunMode.DrawingsMode(), "step")
	ns.RunMode.Hide()
	-- A recommended plan: no Draw tool, presses pan the map.
	local rec = ns.Bundled.Get("b:ragefire-chasm")
	ns.UI.SelectPlan(rec.id)
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	ctx.tool = "draw"
	map:Refresh()
	T.ok(not map.toolButtons.draw:IsShown(), "no Draw tool")
	T.ok(not map.drawBar:IsShown(), "no drawing line")
	T.ok(not map.canvas:DrawBegin(0.5, 0.5), "presses pan the map")
	ctx.tool = "select"
end)

T.case("Pull tags: the Pulls editor switches them; steps, run mode and Discord show them", function()
	local plan, _, _, ctx = drawMap()
	ctx.tool = "select"
	local pull = ns.Plan.AddPull(plan, "Casters")
	ns.Plan.AddMarker(plan, 1, 0.3, 0.3, "pack", "Casters", { pull = pull.id })
	ctx:Changed("pulls")
	ns.UI.SelectTab("pulls")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.pulls.inner
	panel:Refresh()
	local ed = panel.editor
	local function toggle(key)
		for _, b in ipairs(ed.toggles) do
			if b.markKey == key then
				click(b)
				return b
			end
		end
	end
	local kick = toggle("interrupt")
	toggle("lust")
	T.ok(ns.Plan.HasTag(pull, "interrupt"), "tag switched on")
	T.ok(pull.lust, "Bloodlust planned")
	panel:Refresh()
	T.ok(kick.dpActive, "the toggle shows it")
	-- Progress: typed and committed.
	ed.progress.edit:SetText("45")
	ed.progress.edit:GetScript("OnEditFocusLost")(ed.progress.edit)
	T.eq(pull.progress, 45)
	-- Undo takes back the progress.
	ctx:Undo()
	T.eq(ns.Util.FindById(ctx:Plan().pulls, pull.id).progress, nil, "undo works on pulls too")
	ctx:Redo()
	pull = ns.Util.FindById(ctx:Plan().pulls, pull.id)
	T.eq(pull.progress, 45, "and redo")
	-- The pull list and the side panel's step caption carry the marks.
	local marks = ns.UI.PullMarks(pull, { progress = true })
	T.ok(marks:find(ns.L["tagShort:interrupt"], 1, true) and marks:find(ns.L["tagShort:lust"], 1, true), marks)
	T.ok(marks:find("45%", 1, true), "progress")
	local side = _G.DungeonPlannerMainFrame.instancePage.side
	side:Refresh()
	local found
	for _, row in ipairs(side.list.rows) do
		if row:IsShown() and (row.caption:GetText() or ""):find(ns.L["tagShort:lust"], 1, true) then
			found = true
		end
	end
	T.ok(found, "a step caption shows the pull's marks")
	-- Run mode: the next pull's marks and the planned forces at the step.
	local steps = ctx:Steps()
	local index = 1
	for i, s in ipairs(steps) do
		if s.kind == "pull" and s.pull == pull.id then
			index = i
		end
	end
	T.eq(ns.Steps.ProgressAt(ctx:Plan(), steps, index), 45)
	ns.RunMode.Show()
	ns.UI.FocusStep(index, { stay = true })
	ns.RunMode.Refresh()
	local f = _G.DungeonPlannerRunFrame
	T.ok((f.step.text:GetText() or ""):find("45", 1, true), "forces in run mode: " .. tostring(f.step.text:GetText()))
	ns.RunMode.Hide()
	-- Discord: tags in brackets, the Bloodlust mark and the progress.
	local text = table.concat(ns.Discord.Render(ctx:Plan(), { mode = "full" }), "\n")
	T.ok(text:find("[" .. ns.L["tagShort:interrupt"] .. "]", 1, true), "tags")
	T.ok(text:find(ns.L["tag:lust"], 1, true), "Bloodlust")
	T.ok(text:find("*45%*", 1, true), "progress")
end)

T.case("Colour-blind palette: one setting switches pull, route, drawing and role colours everywhere", function()
	local plan, map, canvas, ctx = drawMap()
	local S = ns.Style
	ns.db.settings.colorblind = false
	local r1, g1, b1 = S.PaletteColor(1)
	local tr = S.RoleColor("TANK")
	ns.Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.5, 0.5 }, { color = 1 })
	ctx:Changed("drawings")
	canvas:DrawContent()
	local line = canvas.pools.drawLines[1]
	T.eq(select(1, line:GetVertexColor()), r1, "drawn in the normal red")
	ns.db.settings.colorblind = true
	local r2, g2, b2 = S.PaletteColor(1)
	T.ok(r1 ~= r2 or g1 ~= g2 or b1 ~= b2, "slot 1 changes")
	T.ok(S.RoleColor("TANK") ~= tr, "roles change")
	T.eq(#S.Palette(), ns.Schema.COLOR_COUNT, "a full set")
	-- Every colour of the set differs from every other.
	for i = 1, ns.Schema.COLOR_COUNT do
		for j = i + 1, ns.Schema.COLOR_COUNT do
			local a, b = S.Palette()[i], S.Palette()[j]
			T.ok(a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3], "distinct " .. i .. "/" .. j)
		end
	end
	-- The settings switch redraws: the map line takes the new colour.
	local opts = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("DungeonPlanner", "dialog", "DungeonPlannerTest-1.0")
	local toggle
	local function walk(group)
		for key, opt in pairs(group.args or {}) do
			if key == "colorblind" then
				toggle = opt
			elseif opt.type == "group" then
				walk(opt)
			end
		end
	end
	walk(opts)
	T.ok(toggle, "a setting")
	toggle.set({}, true)
	map:Refresh()
	T.eq(select(1, canvas.pools.drawLines[1]:GetVertexColor()), r2, "drawn in the colour-blind set")
	toggle.set({}, false)
	T.eq(ns.db.settings.colorblind, false)
end)
