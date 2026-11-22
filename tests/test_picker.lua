-- The instance picker and the popup list behind every dropdown: sections, level bands, search, the current instance,
-- the keyboard, closing on an outside click (Model/Picker.lua, UI/Popup.lua, UI/InstancePicker.lua); and route paths
-- with many bends (UI/MapRoutes.lua).
local T = ...
local ns, mock = T.ns, T.mock
local Picker = ns.Picker

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

local ENTRIES = {
	{ key = "rfc", name = "Ragefire Chasm", kind = "dungeon", levelLo = 13, levelHi = 18 },
	{ key = "hot", name = "Hall of Thanes", kind = "dungeon", levelLo = 13, levelHi = 20 },
	{ key = "dm", name = "The Deadmines", kind = "dungeon", levelLo = 17, levelHi = 26 },
	{ key = "sfk", name = "Shadowfang Keep", kind = "dungeon", levelLo = 20, levelHi = 30 },
	{ key = "zf", name = "Zul'Farrak", kind = "dungeon", levelLo = 44, levelHi = 54 },
	{ key = "mc", name = "Molten Core", kind = "raid", levelLo = 60, levelHi = 60 },
	{ key = "zg", name = "Zul'Gurub", kind = "raid", levelLo = 60, levelHi = 60 },
	{ key = "map:1", name = "Custom map", kind = "other" },
}

local function describe(rows)
	local out = {}
	for _, r in ipairs(rows) do
		if r.kind == "header" then
			out[#out + 1] = r.other and "[other]" or ("[" .. r.lo .. "-" .. r.hi .. "]")
		else
			out[#out + 1] = r.entry.key
		end
	end
	return table.concat(out, " ")
end

T.case("Picker: dungeons and raids in their own sections, dungeons in level bands", function()
	local rows, counts = Picker.Rows(ENTRIES, { section = "dungeon" })
	T.eq(describe(rows), "[10-19] rfc hot dm [20-29] sfk [40-49] zf [other] map:1", "bands open where the level changes")
	T.eq(counts.dungeon, 6, "zones and custom maps go with the dungeons")
	T.eq(counts.raid, 2)
	rows = Picker.Rows(ENTRIES, { section = "raid" })
	T.eq(describe(rows), "mc zg", "raids share one level: no bands")
	T.eq(Picker.Section({ kind = "raid" }), "raid")
	T.eq(Picker.Section({ kind = "other" }), "dungeon")
	T.eq(select(2, Picker.Band(13)), 19)
	T.eq(Picker.Band(60), 60)
end)

T.case("Picker: search by name (case and punctuation ignored) or by a level inside the range", function()
	local rows, counts = Picker.Rows(ENTRIES, { section = "dungeon", query = "zul farrak" })
	T.eq(describe(rows), "[40-49] zf", "Zul'Farrak found without the apostrophe")
	T.eq(counts.raid, 0, "Zul'Gurub does not match")
	rows, counts = Picker.Rows(ENTRIES, { section = "dungeon", query = "  ZUL " })
	T.eq(describe(rows), "[40-49] zf")
	T.eq(counts.raid, 1, "the raid tab counts its match")
	rows = Picker.Rows(ENTRIES, { section = "dungeon", query = "18" })
	T.eq(describe(rows), "[10-19] rfc hot dm", "a level finds what a character of that level can run")
	rows = Picker.Rows(ENTRIES, { section = "dungeon", query = "nothing like it" })
	T.eq(#rows, 0, "no match, no headers")
	-- The section follows the search when the current one has no match.
	T.eq(Picker.SectionFor("dungeon", { dungeon = 0, raid = 2 }), "raid")
	T.eq(Picker.SectionFor("dungeon", { dungeon = 1, raid = 2 }), "dungeon")
	T.eq(Picker.SectionFor("raid", { dungeon = 0, raid = 0 }), "raid")
end)

T.case("Picker: the cursor skips headers and stops at the ends; the current instance is found", function()
	local rows = Picker.Rows(ENTRIES, { section = "dungeon" })
	-- [10-19] rfc hot dm [20-29] sfk [40-49] zf [other] map:1
	T.eq(Picker.Step(rows, nil, 1), 2, "down from nothing: the first item, not the header")
	T.eq(Picker.Step(rows, nil, -1), #rows, "up from nothing: the last item")
	T.eq(Picker.Step(rows, 4, 1), 6, "over the band header")
	T.eq(Picker.Step(rows, 6, -1), 4, "and back")
	T.eq(Picker.Step(rows, 2, -1), 2, "stays on the first item")
	T.eq(Picker.Step(rows, #rows, 1), #rows, "stays on the last item")
	T.eq(Picker.Step(rows, 2, 3), 6, "a page counts items, not headers")
	T.eq(Picker.Step({ { kind = "header" } }, nil, 1), nil, "nothing to point at")
	T.eq(Picker.Find(rows, "hot"), 3)
	T.eq(Picker.Find(rows, "mc"), nil, "a raid is not in the dungeon rows")
end)

local function page()
	return _G.DungeonPlannerMainFrame.instancePage
end

local function openPicker()
	local pick = page().instancePick
	mock.Click(pick)
	return ns.Widgets.ActivePopup(), pick
end

-- The cursor's look on a row: the game's list hover where the client has the atlas, else the amber fill.
local function cursorOn(f)
	if f.cursorTex then
		return f.cursorTex:IsShown()
	end
	return f.dpFillRole == "selected"
end

local function itemFrame(p, index)
	for _, f in ipairs(p.pools[p.poolKey].item) do
		if f:IsShown() and f.index == index then
			return f
		end
	end
	return nil
end

T.case("Instance picker: an opaque popup with sections, bands and the open instance marked", function()
	boot()
	ns.UI.SelectPlan("b:hall-of-thanes")
	local p, pick = openPicker()
	T.ok(p, "the picker opened")
	T.eq(p.spec.style, "instance")
	T.eq(p.owner, pick, "anchored to the instance control")
	local anchor = p:FindPoint("TOPLEFT") or p:FindPoint("BOTTOMLEFT")
	T.ok(anchor and anchor[2] == pick, "placed against the control")
	T.ok(p.dpFillRole == "menu" or (p.fill ~= nil and p.fill:IsShown()), "the opaque popup fill")
	T.eq(select(4, ns.Style.Color("menu")), 1, "nothing shows through")
	T.eq(p.tab, "dungeon", "opens on the open instance's section")
	T.ok(p.tabBar and p.tabBar:IsShown(), "Dungeons and Raids tabs")
	T.ok(p.search:IsShown(), "a search field at the top")
	-- Its placeholder, worded like the home list's, shows while the field is empty, though the field has the focus.
	T.ok(p.search.placeholder and p.search.placeholder:IsShown(), "the search's placeholder shows")
	T.eq(p.search.placeholder:GetText(), ns.L["Search dungeons and raids..."])
	p.search.edit:SetFocus()
	mock.FireScript(p.search.edit, "OnEditFocusGained")
	T.ok(p.search.placeholder:IsShown(), "still there while the empty field has the focus")
	p.search.edit:SetText("rag")
	mock.FireScript(p.search.edit, "OnTextChanged", false)
	T.ok(not p.search.placeholder:IsShown(), "gone once something is typed")
	p.search.edit:SetText("")
	mock.FireScript(p.search.edit, "OnTextChanged", false)
	T.eq(p:GetHeight() - 2 * p.shadowY, 440, "a fixed height (the menu art's shadow around it)")
	T.ok(p.rows[1].kind == "header", "the first band's divider")
	local cur = p.rows[p.cursor]
	T.eq(cur.entry.name, "Hall of Thanes", "the cursor starts on the open instance")
	local f = itemFrame(p, p.cursor)
	T.ok(f, "its row is drawn")
	T.ok(f.mark:IsShown(), "the open instance carries the bronze bar")
	T.ok(cursorOn(f), "one highlight: the cursor (the game's list hover)")
	T.ok(p.dpMenuBg ~= nil, "the game's menu panel behind the list")
	T.ok(f.thumb:GetTexture() ~= nil, "a thumbnail (the loading screen or the plate's stone)")
	T.ok(not f.emblem:IsShown(), "Hall of Thanes: its loading screen, no plate mark")
	T.eq(f.thumb:GetTexture(), 7963781)
	T.eq(f.level:GetText(), "LV 13-20")
	T.ok(f.star:IsShown(), "a recommended plan: the star")
	-- The header's tooltips open below their control and stay away while the list is open.
	T.eq(pick.dpTooltipAnchor, "below")
	T.eq(page().planPick.dpTooltipAnchor, "below")
	T.ok(pick.dpPopupOpen, "no tooltip over the open list")
	-- Pooled rows: only the visible ones exist.
	local made = #p.pools.instance.item
	T.ok(made < #p.rows, "virtual: " .. made .. " frames for " .. #p.rows .. " rows")
	mock.Wheel(p.view, -1)
	mock.Wheel(p.view, 1)
	T.ok(#p.pools.instance.item <= made + 1, "scrolling reuses them")
	-- The control's own click closes it again.
	mock.Click(pick)
	T.eq(ns.Widgets.ActivePopup(), nil, "toggled closed")
	T.ok(not pick.dpPopupOpen)
end)

T.case("Instance picker: keyboard, hover and search share one cursor; Enter opens, Escape closes", function()
	boot()
	ns.UI.SelectPlan("b:hall-of-thanes")
	local p = openPicker()
	local edit = p.search.edit
	local start = p.cursor
	mock.FireScript(edit, "OnArrowPressed", "DOWN")
	T.ok(p.cursor > start and p.rows[p.cursor].kind == "item", "down moves to the next instance")
	T.ok(cursorOn(itemFrame(p, p.cursor)), "the highlight follows")
	T.ok(not cursorOn(itemFrame(p, start)), "and leaves the old row")
	mock.FireScript(edit, "OnArrowPressed", "UP")
	T.eq(p.cursor, start, "up comes back")
	-- The pointer moves the same highlight.
	local other = Picker.Step(p.rows, start, 1)
	local f = itemFrame(p, other)
	mock.Hover(f)
	T.eq(p.cursor, other, "hovering moves the cursor")
	-- Tab switches the section.
	mock.FireScript(edit, "OnTabPressed")
	T.eq(p.tab, "raid")
	for _, r in ipairs(p.rows) do
		T.eq(r.kind, "item", "raids have no level bands")
		T.eq(r.entry.kind, "raid")
	end
	mock.FireScript(edit, "OnTabPressed")
	T.eq(p.tab, "dungeon")
	-- Typing filters as you type; a raid name switches to the raids.
	edit:SetText("molten")
	mock.FireScript(edit, "OnTextChanged", true)
	T.eq(p.tab, "raid", "the section with matches")
	T.eq(#p.rows, 1)
	T.eq(p.rows[1].entry.name, "Molten Core")
	local raids = p.tabBar:Button("raid")
	T.ok(raids.label:GetText():find("1", 1, true), "the tab shows its match count while searching")
	edit:SetText("lordaeron")
	mock.FireScript(edit, "OnTextChanged", true)
	T.eq(p.tab, "dungeon")
	T.eq(p.rows[p.cursor].entry.name, "Ruins of Lordaeron", "the cursor on the first match")
	edit:SetText("no such place")
	mock.FireScript(edit, "OnTextChanged", true)
	T.eq(#p.rows, 0)
	T.ok(p.empty:IsShown(), "says nothing matches")
	mock.FireScript(edit, "OnEnterPressed")
	T.ok(ns.Widgets.ActivePopup(), "Enter on nothing keeps it open")
	edit:SetText("lordaeron")
	mock.FireScript(edit, "OnTextChanged", true)
	mock.FireScript(edit, "OnEnterPressed")
	T.eq(ns.Widgets.ActivePopup(), nil, "Enter chooses and closes")
	T.eq(ns.db.ui.instance.name, "Ruins of Lordaeron", "the chosen instance is open")
	-- Escape closes without choosing.
	p = openPicker()
	T.eq(p.rows[p.cursor].entry.name, "Ruins of Lordaeron", "the new current instance")
	mock.FireScript(p.search.edit, "OnEscapePressed")
	T.eq(ns.Widgets.ActivePopup(), nil, "Escape closes")
	T.eq(ns.db.ui.instance.name, "Ruins of Lordaeron", "nothing changed")
	ns.UI.SelectPlan("b:hall-of-thanes")
end)

T.case("Forever: the instances new in WoW: Forever carry a bronze tag and match the search \"forever\"", function()
	local hot = { key = "hot", name = "Hall of Thanes", kind = "dungeon", origin = "forever" }
	local dm = { key = "dm", name = "The Deadmines", kind = "dungeon", origin = "classic" }
	T.ok(Picker.IsForever(hot) and not Picker.IsForever(dm) and not Picker.IsForever({ name = "x" }))
	T.ok(Picker.Matches(hot, "forever") and Picker.Matches(hot, " Forev "), "the word or its start")
	T.ok(not Picker.Matches(dm, "forever"), "not a classic instance")
	T.ok(not Picker.Matches(hot, "fo"), "two letters are too few")
	local rows = Picker.Rows({ hot, dm }, { section = "dungeon", query = "forever", bands = false })
	T.eq(#rows, 1)
	T.eq(rows[1].entry.key, "hot")
	-- The picker's rows and the home table show the tag only for those instances.
	boot()
	ns.UI.SelectPlan("b:hall-of-thanes")
	local p = openPicker()
	local f = itemFrame(p, p.cursor)
	T.eq(p.rows[p.cursor].entry.origin, "forever", "the recommended plan's origin reaches the entry")
	T.ok(f.forever:IsShown(), "Hall of Thanes: tagged")
	T.eq(f.forever.text:GetText(), "Forever")
	T.eq(f.forever.dpTooltipText, "New in WoW: Forever")
	local tagged, untagged = 0, 0
	for _, row in ipairs(p.rows) do
		if row.kind == "item" then
			if row.entry.origin == "forever" then
				tagged = tagged + 1
			elseif row.entry.origin == "classic" then
				untagged = untagged + 1
			end
		end
	end
	T.ok(tagged >= 9 and untagged >= 20, "origins on the entries (" .. tagged .. " Forever, " .. untagged .. " classic)")
	p.search.edit:SetText("forever")
	mock.FireScript(p.search.edit, "OnTextChanged", true)
	for _, row in ipairs(p.rows) do
		if row.kind == "item" then
			T.eq(row.entry.origin, "forever", "the search keeps only Forever's instances: " .. row.entry.name)
		end
	end
	for _, item in ipairs(p.pools.instance.item) do
		if item:IsShown() then
			T.eq(item.forever:IsShown(), true, "every row it shows is tagged")
		end
	end
	-- Without the search: a classic instance's row has no tag.
	p.search.edit:SetText("")
	mock.FireScript(p.search.edit, "OnTextChanged", true)
	local classic = 0
	for _, item in ipairs(p.pools.instance.item) do
		local row = item:IsShown() and p.rows[item.index]
		if row and row.kind == "item" and row.entry.origin == "classic" then
			classic = classic + 1
			T.ok(not item.forever:IsShown(), "a classic instance: no tag (" .. row.entry.name .. ")")
		end
	end
	T.ok(classic > 0, "classic rows drawn")
	ns.Widgets.ClosePopup()
end)

T.case("Popups close on a click outside, when their control hides, and a click on a row chooses", function()
	boot()
	ns.UI.SelectPlan("b:hall-of-thanes")
	local p = openPicker()
	T.ok(p:IsEventRegistered("GLOBAL_MOUSE_DOWN"), "listens for clicks while open")
	mock.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
	T.eq(ns.Widgets.ActivePopup(), nil, "a click elsewhere closes it")
	T.ok(not p:IsEventRegistered("GLOBAL_MOUSE_DOWN"), "and it stops listening")
	-- A click inside does not.
	p = openPicker()
	mock.Hover(p)
	mock.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
	T.ok(ns.Widgets.ActivePopup(), "a click inside keeps it")
	mock.Leave(p)
	-- Hiding the control (the window closes) closes it.
	page().instancePick:Hide()
	T.eq(ns.Widgets.ActivePopup(), nil, "closed with its control")
	page().instancePick:Show()
	-- The plan dropdown uses the same popup: opaque, the current plan marked, keys without a search field.
	local plan = page().planPick
	mock.Click(plan)
	p = ns.Widgets.ActivePopup()
	T.ok(p and p.spec.style == "menu", "the plan list is the opaque popup")
	T.ok(not p.search:IsShown() and not (p.tabBar and p.tabBar:IsShown()), "no search, no tabs")
	T.ok(p.rows[p.cursor].value == "b:hall-of-thanes", "the cursor starts on the plan on the table")
	T.ok(itemFrame(p, p.cursor).mark:IsShown(), "marked as the current plan")
	T.ok(p:GetWidth() >= plan:GetWidth(), "at least as wide as its control")
	mock.FireScript(p, "OnKeyDown", "DOWN")
	T.ok(p.rows[p.cursor].value ~= "b:hall-of-thanes", "arrow keys move the cursor")
	mock.FireScript(p, "OnKeyDown", "ESCAPE")
	T.eq(ns.Widgets.ActivePopup(), nil, "Escape closes")
	-- Any other dropdown: a click on a row chooses it.
	ns.UI.SelectTab("map")
	local focus = page().panels.map.focus
	mock.Click(focus)
	p = ns.Widgets.ActivePopup()
	T.ok(p and #p.rows > 1, "the focus list")
	local target = Picker.Step(p.rows, p.cursor, 1)
	local f = itemFrame(p, target)
	local value = p.rows[target].value
	mock.Click(f)
	T.eq(ns.Widgets.ActivePopup(), nil, "closed after the choice")
	T.ok(focus.label:GetText() == p.rows[target].text or value ~= nil, "the choice is shown")
	mock.Click(focus)
	T.eq(ns.Widgets.ActivePopup().rows[ns.Widgets.ActivePopup().cursor].value, value, "and is the current one next time")
	ns.Widgets.ClosePopup()
	-- A combat that starts while a keyboard list is open closes it (it could not pass keys on any more).
	mock.Click(plan)
	mock.FireEvent("PLAYER_REGEN_DISABLED")
	T.eq(ns.Widgets.ActivePopup(), nil, "closed on entering combat")
end)

T.case("Route paths: a corridor route with many bends draws one joint per bend from pools, chevrons bounded", function()
	boot()
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local canvas = page().panels.map.canvas
	local points = { { 0.05, 0.5, step = 1 } }
	for i = 1, 80 do
		points[#points + 1] = { 0.05 + i * 0.011, 0.5 + ((i % 2 == 0) and 0.03 or -0.03) }
	end
	points[#points + 1] = { 0.95, 0.5, step = 2 }
	local plan = { routes = { { id = "rz", floor = 1, color = 2, points = points } } }
	local function px(x)
		return x * 1000
	end
	local function py(y)
		return -y * 600
	end
	local n = canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1 })
	T.eq(n.lines, #points - 1, "one line per segment")
	T.eq(n.outlines, n.lines, "each outlined")
	T.eq(n.joints, 80, "a joint at every bend")
	T.ok(n.arrows >= 1 and n.arrows <= ns.MapRoutes.MAX_ARROWS, "chevrons along the way, bounded: " .. n.arrows)
	local made = #canvas.pools.joints
	canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1 })
	T.eq(#canvas.pools.joints, made, "redrawing creates nothing new")
	canvas:DrawContent()
end)
