-- The game's own window parts (UI/Window.lua, UI/Style.lua Materials, the kit's tabs, buttons and scroll bars) against
-- the mock's templates, and the drawn fallbacks without them; boss portraits that arrive while a view is open
-- (UI/Art.lua); item tooltips beside the item's name (UI/Panels/GearPanel.lua).
local T = ...
local ns, mock = T.ns, T.mock
local W, S, Art = ns.Widgets, ns.Style, ns.Art

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

-- Run every pending timer (other tests leave some), so a case starts with none of its own.
local function settle()
	for _ = 1, 5 do
		mock.Advance(10)
	end
end

T.case("Boss portraits: the skull first, then the portrait on the same row texture after one timer for the batch", function()
	boot()
	settle()
	local fired = 0
	local owner = {}
	ns:On("PORTRAITS_READY", owner, function()
		fired = fired + 1
	end)
	local timersBefore = #mock.timers
	local list = W.List(UIParent, {
		rowHeight = 44,
		create = function(row)
			row.portrait = W.Portrait(row, 40)
		end,
		update = function(row, item)
			row.portrait:SetBoss({ displayInfo = item.id })
		end,
	})
	list:SetHeight(300)
	list:SetItems({ { id = 70001 }, { id = 70002 }, { id = 70003 } })
	local face = list.rows[1].portrait.face

	-- First render: the placeholder skull; the creatures load off screen.
	T.ok(tostring(face:GetTexture()):find("HumanSkull", 1, true), "the placeholder skull on the row")
	T.eq(Art.PortraitShown(face), nil, "no portrait yet")
	local loading, waiting = Art.PortraitsLoading()
	T.eq(loading, 3, "three creatures loading")
	T.ok(waiting, "a timer waits for them")
	T.eq(#mock.timers - timersBefore, 1, "one timer for the batch, not one per row")
	local model = face.dpModel
	T.ok(model and model:GetParent() ~= face:GetParent(), "the portrait waits off screen")

	-- A refresh while they load (the list redraws on every resize) asks for no new timer.
	list:Refresh()
	T.eq(#mock.timers - timersBefore, 1, "still one timer")
	mock.Advance(1)
	T.eq(Art.PortraitShown(face), nil, "not before the load time")

	-- The timer: every row's own texture now shows its creature, without rebuilding the list.
	mock.Advance(Art.PORTRAIT_LOAD)
	T.eq(Art.PortraitShown(face), 70001, "the same row texture shows the portrait")
	T.eq(Art.PortraitShown(list.rows[2].portrait.face), 70002)
	T.eq(Art.PortraitShown(list.rows[3].portrait.face), 70003)
	T.eq(face.dpModel, model, "the portrait made for the row")
	T.eq(model:GetParent(), face:GetParent(), "moved onto the row")
	T.ok((model._portraitDraws or 0) >= 2, "drawn again once the creature had loaded")
	T.eq(fired, 1, "PORTRAITS_READY once for the batch")
	loading, waiting = Art.PortraitsLoading()
	T.eq(loading, 0, "nothing loading")
	T.ok(not waiting, "and no timer left: no polling")
	T.eq(#mock.timers, timersBefore, "no timer of ours queued")

	-- Shown again later: placed at once, no new timer.
	list:Refresh()
	T.eq(Art.PortraitShown(face), 70001)
	T.eq(#mock.timers, timersBefore)

	-- A creature asked for during another's wait gets the next timer; a killed boss greys its portrait too.
	list:SetItems({ { id = 70001 }, { id = 70004 } })
	T.eq(Art.PortraitShown(face), 70001, "a loaded creature shows at once")
	T.eq(Art.PortraitShown(list.rows[2].portrait.face), nil, "a new one waits")
	list.rows[1].portrait:SetDone(true)
	mock.Advance(Art.PORTRAIT_LOAD + 0.1)
	T.eq(Art.PortraitShown(list.rows[2].portrait.face), 70004)
	T.eq(fired, 2)
	ns:Off("PORTRAITS_READY", owner)
end)

T.case("Boss portraits: choosing Molten Core starts its bosses loading; after the timer every step and pin has its face", function()
	boot()
	settle()
	Art.ResetPortraitCache()
	local savedBossData = ns.BossData.enabled
	ns.BossData.enabled = true -- the bundled display IDs, as in game (provider tests switch them off)
	ns.Journal.epoch = (ns.Journal.epoch or 0) + 1 -- forget portraits cached while they were off
	ns.UI.SelectPlan("b:molten-core")
	-- Chosen: every boss's creature is loading before the page has drawn anything (UI/Portraits.lua).
	local ids = ns.Journal.PlanPortraits(ns.DB.GetPlan("b:molten-core"))
	T.ok(#ids >= 8, "Molten Core's bosses have bundled portraits: " .. #ids)
	local loading = Art.PortraitsLoading()
	T.ok(loading >= #ids, "loading from the choice on: " .. loading)
	T.eq(Art.PrefetchPortraits(ids), 0, "asked again: nothing new starts")

	ns.UI.SelectTab("map")
	local page = _G.DungeonPlannerMainFrame.instancePage
	local map = page.panels.map
	map:RefreshNow()
	local function bossHosts()
		local hosts = {}
		for _, row in ipairs(page.side.list.rows) do
			if row:IsShown() and row.item and row.item.kind == "boss" then
				hosts[#hosts + 1] = { "step " .. tostring(row.item.encounter), row.badge.icon }
			end
		end
		local plan = ns.DB.GetPlan("b:molten-core")
		for _, b in ipairs(map.canvas.pools.pins) do
			local m = b:IsShown() and b.markerId and ns.Util.FindById(plan.markers, b.markerId)
			if m and m.kind == "boss" then
				hosts[#hosts + 1] = { "pin " .. tostring(m.label), b.icon }
			end
		end
		return hosts
	end
	local hosts = bossHosts()
	local steps, pins = 0, 0
	for _, h in ipairs(hosts) do
		if h[1]:find("^step") then
			steps = steps + 1
		else
			pins = pins + 1
		end
	end
	T.ok(steps >= 5 and pins >= 8, "boss steps and pins on screen: " .. steps .. ", " .. pins)
	-- First render: the skull (the creatures are still loading), on one timer for all of them.
	for _, h in ipairs(hosts) do
		T.eq(Art.PortraitShown(h[2]), nil, h[1] .. " waits")
	end
	local _, waiting = Art.PortraitsLoading()
	T.ok(waiting, "one batch timer waits")

	-- The timer: each step row and map pin shows its creature in place, without the view being drawn again.
	mock.Advance(Art.PORTRAIT_LOAD + 0.1)
	for _, h in ipairs(hosts) do
		T.ok(Art.PortraitShown(h[2]) ~= nil, h[1] .. " shows its portrait")
	end
	T.eq((Art.PortraitsLoading()), 0, "nothing left loading")
	-- Drawn again (a redraw re-pools the pins): faces at once, no new wait.
	map.canvas:DrawContent()
	page.side.list:Refresh()
	for _, h in ipairs(bossHosts()) do
		T.ok(Art.PortraitShown(h[2]) ~= nil, h[1] .. " at once after a redraw")
	end
	T.eq((Art.PortraitsLoading()), 0, "a loaded creature never waits again")
	ns.BossData.enabled = savedBossData
	ns.Journal.epoch = ns.Journal.epoch + 1
end)

T.case("Gear: an item's tooltip opens beside its name, and off 'Open in NeedRoll'", function()
	boot()
	local plan
	for _, p in ipairs(ns.DB.Plans()) do
		plan = plan or p
	end
	T.ok(plan, "an own plan from the earlier cases")
	ns.UI.SelectPlan(plan.id)
	ns.Plan.AddGear(plan, { itemID = 19019, priority = 2 })
	ns.UI.SelectTab("gear")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
	panel:Refresh()
	local row -- the item's cell in its line
	for _, r in ipairs(panel.list.rows) do
		for _, cell in ipairs(r:IsShown() and r.cells or {}) do
			if not row and cell:IsShown() and cell.entry and cell.entry.gear then
				row = cell
			end
		end
	end
	T.ok(row, "a gear item")
	panel.needRoll:Hide()
	row:GetScript("OnEnter")(row)
	local a = GameTooltip:FindPoint("TOPLEFT")
	T.ok(a, "anchored by its top-left corner")
	T.eq(a[2], row.title, "to the item's name, not the row's far edge")
	local width = math.min(row.title:GetStringWidth(), row.title:GetWidth())
	T.eq(a[4], math.ceil(width) + S.SPACE.md, "just right of the name's last letter")
	T.eq(GameTooltip:FindPoint("TOPRIGHT"), nil, "one anchor")
	-- Pushed up over "Open in NeedRoll" (the game keeps tooltips on screen): it opens left of the icon instead.
	panel.needRoll:Show()
	row:GetScript("OnEnter")(row)
	local flipped = GameTooltip:FindPoint("TOPRIGHT")
	T.ok(flipped and flipped[2] == row.icon, "left of the item's icon")
	T.eq(GameTooltip:FindPoint("TOPLEFT"), nil, "and only there")
	row:GetScript("OnLeave")(row)
	panel.needRoll:Hide()
end)

T.case("Gear: the items fill the page's width, side by side, the headings on lines of their own", function()
	boot()
	local saved = ns.BossData.enabled
	ns.BossData.enabled = true -- the bundled drops, as in game (provider tests switch them off)
	ns.Providers.ResetCaches()
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("gear")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.gear.inner
	panel:Refresh()
	local function check(width, cols)
		panel.list:SetWidth(width)
		panel.list:GetScript("OnSizeChanged")(panel.list, width, panel.list:GetHeight())
		T.eq(panel.cols, cols, width .. " px wide")
		local entries, placed = 0, 0
		for _, e in ipairs(panel.entries) do
			if not e.header then
				entries = entries + 1
			end
		end
		for _, line in ipairs(panel.list.items) do
			if line.cells then
				T.ok(#line.cells <= cols, "at most " .. cols .. " a line")
				placed = placed + #line.cells
			else
				T.ok(line.header, "a heading alone")
			end
		end
		T.ok(entries > 3, "Hall of Thanes' drops are listed")
		T.eq(placed, entries, "every item placed once")
		-- The cells of a full line share its width, in reading order.
		for _, row in ipairs(panel.list.rows) do
			if row:IsShown() and row.item and row.item.cells and #row.item.cells == cols and cols > 1 then
				local a, b = row.cells[1]:FindPoint("TOPLEFT"), row.cells[2]:FindPoint("TOPLEFT")
				T.ok(b[4] > a[4] + row.cells[1]:GetWidth() - 1, "side by side")
				return
			end
		end
		T.eq(cols, 1, "a full line is shown")
	end
	check(900, 3)
	check(560, 2)
	check(300, 1)
	ns.BossData.enabled = saved
	ns.Providers.ResetCaches()
end)

T.case("Native window: the game's framed window, insets, tabs under the window, panel buttons and scroll bars", function()
	boot()
	local frame = _G.DungeonPlannerMainFrame
	T.ok(frame.dpNative, "the game's window template")
	T.eq(frame.title:GetText(), ns.title, "the title in the title bar")
	T.eq(frame.title:GetFontObject(), S.fonts.title, "in our font (Polish letters)")
	T.ok(frame._buttonBarHidden and not frame.Inset:IsShown(), "no button bar, no template inset")
	T.eq(frame.emblem:GetTexture(), Art.SPECS.launcher.file, "the addon's logo in the portrait ring")
	T.ok(frame.insets.top > 40 and frame.insets.left < 10, "content under the header row, inside the edge")
	-- The close button is ours (the template's would go through the game's panel code).
	frame.close:GetScript("OnClick")(frame.close)
	T.ok(not frame:IsShown(), "closed")
	ns.UI.Toggle()
	T.ok(frame:IsShown(), "open again")

	local plan = ns.DB.Plans()[1]
	ns.UI.SelectPlan(plan.id)
	local page = frame.instancePage
	-- Header controls on the window's bar.
	T.eq(page.chrome:GetParent(), frame.bar, "the pickers on the header row")
	-- Sections: the game's window tabs hanging under the window.
	local bar = page.sectionBar
	T.eq(bar.style, "bottom", "the game's tabs")
	local hang = bar:FindPoint("TOPLEFT")
	T.ok(hang and hang[2] == frame and hang[3] == "BOTTOMLEFT", "under the window's bottom edge")
	ns.UI.SelectTab("pulls")
	local pulls = bar:Button("pulls")
	T.ok(pulls._selected, "selected through the game's tab helper")
	T.eq(pulls.Text:GetFontObject(), S.fonts.tabHighlight, "our font, set again after the helper")
	T.eq(pulls._disabledFont, S.fonts.tabHighlight, "its selected state's font object too")
	T.ok(not bar:Button("map")._selected, "the others deselected")
	T.eq(frame.home.tabs.style, "bottom", "the home lists are tabs under the window too")
	-- Materials.
	local side = page.side
	T.ok(side.dpInset, "the side panel is the game's inset")
	T.eq(side.dpNine._layout, "InsetFrameTemplate", "its bevel")
	T.ok(side.dpInsetBg ~= nil, "its marble")
	T.ok(side.heading.strip ~= nil, "Steps: a section header on the header band")
	T.ok(side.copy.dpNative or plan.bundled == nil, "primary actions are the game's red panel button")
	local primary = W.Button(UIParent, "Go", "primary")
	T.ok(primary.dpNative, "a primary button from UIPanelButtonTemplate")
	T.eq(primary.label:GetText(), "Go", "our label draws the text")
	-- Lists: the game's scroll bar, updated without echoing its own report back.
	local list = side.list
	T.ok(list.thumb.dpNative, "MinimalScrollBar")
	local long = W.List(UIParent, {
		rowHeight = 20,
		create = function() end,
		update = function() end,
	})
	long:SetHeight(200)
	local many = {}
	for i = 1, 40 do
		many[i] = { i }
	end
	long:SetItems(many)
	local lbar = long.thumb
	T.ok(lbar:IsShown(), "shown when the list scrolls")
	T.ok(lbar._visible and lbar._visible < 1, "the thumb sized to the visible part")
	-- Dragging the game's lbar scrolls the list; the list's own update does not send the value back.
	local sets = lbar._sets or 0
	lbar:SetScrollPercentage(0.5)
	local range = #many - math.floor(200 / 20)
	T.eq(long.offset, math.floor(0.5 * range + 0.5), "the list follows the lbar")
	T.eq((lbar._sets or 0) - sets, 1, "no echo back to the lbar")
	-- The mouse wheel on the list moves the lbar.
	long:GetScript("OnMouseWheel")(long, -1)
	T.ok(math.abs(lbar:GetScrollPercentage() - long.offset / range) < 0.01, "the lbar follows the list")
	-- Scroll areas (real scroll frames): the game's own wiring joins them to its scroll bar.
	local area = W.ScrollArea(UIParent)
	T.ok(area.thumb.dpScrollUtil and area._scrollBar == area.thumb, "ScrollUtil.InitScrollFrameWithScrollBar")
	area:SetContentHeight(900)
	-- Popups: the game's menu panel.
	T.ok(page.planPick, "plan picker")
	page.planPick:GetScript("OnClick")(page.planPick, "LeftButton")
	local p = W.ActivePopup()
	T.ok(p and p.dpMenuBg, "the game's menu art behind the list")
	W.ClosePopup()
	-- Dialogs: the game's dialog border.
	W.ShowDialog({ title = "T", text = "x" })
	T.eq(_G.DungeonPlannerDialog.dpNine._layout, "Dialog", "the dialog layout")
	_G.DungeonPlannerDialog:Hide()
	-- Run mode: the compact window, no portrait.
	ns.RunMode.Show()
	T.ok(_G.DungeonPlannerRunFrame.dpNative and _G.DungeonPlannerRunFrame._portraitHidden, "compact: no portrait")
	ns.RunMode.Hide()
	-- /dp debug lists the game's parts.
	local rows = Art.NativeReport()
	T.ok(#rows >= 15, "templates, layouts and helpers reported")
	for _, row in ipairs(rows) do
		if row.kind ~= "template" then
			T.ok(row.ok, row.name .. " found")
		end
	end
	ns.Slash.Handle("debug")
	local dialog = _G.DungeonPlannerDialog
	for _ = 1, 20 do
		if not (dialog and dialog:IsShown()) then
			break
		end
		dialog:Hide()
	end
end)

T.case("Without the game's parts: the drawn window, segment tabs, plates and thumb", function()
	boot()
	local saved = {}
	for _, name in ipairs({ "ButtonFrameTemplate", "PanelTabButtonTemplate", "UIPanelButtonTemplate", "MinimalScrollBar" }) do
		saved[name] = mock.templates[name]
		mock.templates[name] = nil
	end
	local layout = mock.layouts.InsetFrameTemplate
	mock.layouts.InsetFrameTemplate = nil
	local ok, err = pcall(function()
		local f = W.Window("DungeonPlannerTestPlainWindow", "Plain", {}, 400, 300)
		T.eq(f.dpNative, false, "drawn window")
		T.eq(f.bar, f.header, "controls go on the header strip")
		T.eq(f.barStart, f.title, "after the title")
		T.ok(f.insets.top > 30, "content under the header strip")
		T.ok(f.dpHasBackdrop or f.dpFallbackFill, "stone and edge")
		local tabs = W.Tabs(f, { { id = "a", text = "A" }, { id = "b", text = "B" } }, function() end, { style = "bottom" })
		T.eq(tabs.style, nil, "segment plates instead of the game's tabs")
		tabs:Select("b")
		T.ok(tabs:Button("b").dpActive and not tabs:Button("a").dpActive, "one active")
		local b = W.Button(f, "Go", "primary")
		T.ok(not b.dpNative and b.dpHasBackdrop ~= nil, "a drawn red plate")
		local panel = W.Panel(f)
		T.eq(panel.dpInset, false, "no inset layout: the drawn panel")
		T.eq(panel.dpBorderRole, "border", "with its edge")
		local list = W.List(f, { create = function() end, update = function() end })
		T.ok(not list.thumb.dpNative, "the drawn thumb")
		f:Hide()
	end)
	for name, fn in pairs(saved) do
		mock.templates[name] = fn
	end
	mock.layouts.InsetFrameTemplate = layout
	T.ok(ok, tostring(err))
end)
