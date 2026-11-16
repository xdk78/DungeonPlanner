-- The code review's follow-ups: buttons take left clicks only, Escape closes our topmost frame first, hiding the UI
-- (Alt+Z) declines and cancels nothing, missing texture files pick their fallback, the dungeon's own map tiles before a
-- same-named map, the game's tabs keep their padding, the close button and size grip above the window's border, the
-- map pans with the Draw tool in combat, and the objective field adds only on Enter or its button.
local T = ...
local ns, mock = T.ns, T.mock
local W = ns.Widgets

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.UI.Show()
end

-- What the game does on Escape once its own handlers are done: CloseAllWindows -> CloseSpecialWindows.
local function pressEscape()
	local found
	for _, name in pairs(_G.UISpecialFrames) do
		local f = _G[name]
		if f and f:IsShown() then
			f:Hide()
			found = 1
		end
	end
	return found
end

-- Alt+Z: UIParent hides, and every visible frame under it gets OnHide while it stays "shown".
local function toggleUI(frames)
	_G.UIParent:Hide()
	for _, f in ipairs(frames) do
		local fn = f:GetScript("OnHide")
		if fn and f:IsShown() then
			fn(f)
		end
	end
	_G.UIParent:Show()
end

local function closeDialogs()
	local dialog = _G.DungeonPlannerDialog
	for _ = 1, 10 do
		if not (dialog and dialog:IsShown()) then
			return
		end
		dialog:Hide()
	end
end

T.case("Follow-ups: buttons take left clicks only", function()
	boot()
	local parent = _G.DungeonPlannerMainFrame
	for _, variant in ipairs({ "red", "outline", "ghost", "segment" }) do
		local b = W.Button(parent, "Delete pull", variant, function() end)
		T.eq(#b._clicks, 1, variant .. ": one button")
		T.eq(b._clicks[1], "LeftButtonUp", variant)
	end
end)

T.case("Follow-ups: Escape closes the topmost of our frames, one per press", function()
	boot()
	closeDialogs()
	local main = _G.DungeonPlannerMainFrame
	T.ok(main:IsShown())
	for _, name in ipairs(_G.UISpecialFrames) do
		T.ok(name ~= "DungeonPlannerMainFrame" and name ~= "DungeonPlannerDialog", "only the stand-in is in the list")
	end
	local confirmed = 0
	W.Confirm("Delete pull", "Sure?", "Delete", function()
		confirmed = confirmed + 1
	end)
	local dialog = _G.DungeonPlannerDialog
	T.eq(W.EscapeOrder()[1], dialog, "the dialog first")
	T.ok(pressEscape(), "Escape was taken")
	T.ok(not dialog:IsShown(), "the dialog closed")
	T.ok(main:IsShown(), "the window behind it stayed open")
	T.eq(confirmed, 0, "Escape is not the confirm button")
	T.ok(pressEscape(), "the next Escape is taken too")
	T.ok(not main:IsShown(), "and closes the window")
	T.eq(pressEscape(), nil, "nothing of ours open: the game's menu opens")
	-- Run mode and the Notes window are never closed by Escape.
	ns.UI.Show()
	ns.RunMode.Toggle()
	local run = _G.DungeonPlannerRunFrame
	if run and run:IsShown() then
		pressEscape()
		T.ok(run:IsShown(), "run mode stays")
		T.ok(not main:IsShown(), "the window went")
		ns.RunMode.Toggle()
	end
	ns.UI.Show()
end)

T.case("Follow-ups: hiding the UI (Alt+Z) declines nothing; Escape on a prompt still does", function()
	boot()
	closeDialogs()
	local declined = 0
	W.ShowDialog({
		title = "Plan offered",
		text = "Anna wants to send you a plan.",
		buttons = { { "Accept", function() end, true }, { "Decline" } },
		onDismiss = function()
			declined = declined + 1
		end,
	})
	local dialog = _G.DungeonPlannerDialog
	toggleUI({ dialog, _G.DungeonPlannerEscape })
	T.eq(declined, 0, "the prompt was not declined")
	T.ok(dialog:IsShown(), "it is still there with the UI")
	T.ok(_G.DungeonPlannerEscape:IsShown(), "and Escape still reaches it")
	pressEscape()
	T.eq(declined, 1, "Escape on the prompt declines it, once")
	T.ok(_G.DungeonPlannerMainFrame:IsShown(), "the window stayed")
end)

T.case("Follow-ups: a dropdown list survives Alt+Z whole, and closes cleanly afterwards", function()
	boot()
	local value = "a"
	local dd = W.Dropdown(_G.DungeonPlannerMainFrame, {
		options = function()
			return { { value = "a", text = "Alpha" }, { value = "b", text = "Beta" } }
		end,
		get = function()
			return value
		end,
		set = function(v)
			value = v
		end,
	})
	dd:GetScript("OnClick")(dd, "LeftButton")
	local popup = W.ActivePopup()
	T.ok(popup, "the list is open")
	toggleUI({ popup, dd })
	T.eq(popup.owner, dd, "still tied to its control")
	T.ok(popup:IsShown() and dd.dpPopupOpen, "still open")
	popup:Close()
	T.ok(not popup:IsShown(), "closed")
	T.eq(popup.owner, nil, "and finished: no owner")
	T.ok(not dd.dpPopupOpen, "the control knows")
	-- Closing while the UI is hidden (no OnHide then) still finishes it.
	dd:GetScript("OnClick")(dd, "LeftButton")
	popup = W.ActivePopup()
	popup:Close()
	T.eq(popup.owner, nil)
end)

T.case("Follow-ups: a missing game texture picks the fallback (SetTexture says yes to anything)", function()
	boot()
	ns.Art.ForgetFiles()
	local tex = _G.DungeonPlannerMainFrame:CreateTexture()
	T.eq(ns.Art.SetFile(tex, "Interface\\Icons\\No_Such_Icon"), false, "a file the client does not have")
	T.eq(tex:GetTexture(), nil, "the texture untouched")
	T.eq(ns.Art.SetFile(tex, ns.Art.SPECS.kind_loot.file), true, "a file it has")
	T.eq(ns.Art.SetFile(tex, "Interface\\AddOns\\DungeonPlanner\\Media\\Ring"), true, "our own files are trusted")
	T.eq(ns.Art.SetFile(tex, 12345), true, "a file ID")
	-- A boss icon the client lacks: the skull stays.
	ns.Art.SetBossPortrait(tex, { icon = "Interface\\Icons\\No_Such_Boss" })
	T.ok(tostring(tex:GetTexture()):find("HumanSkull", 1, true), "the skull, not an empty square")
	-- An art key whose file is missing reports it, so the caller draws its own fallback.
	mock.missingFiles[ns.Art.SPECS.kind_loot.file:lower()] = true
	ns.Art.ForgetFiles()
	T.eq(ns.Art.Set(tex, "kind_loot"), false)
	mock.missingFiles = {}
	ns.Art.ForgetFiles()
end)

T.case("Follow-ups: the dungeon's own map tiles before a same-named map; map names read once", function()
	boot()
	local saved = mock.journal.tiers
	mock.journal.tiers = {}
	mock.files = {}
	ns.Journal.Reset()
	ns.GameFiles.Reset()
	ns.Instances.ForgetMapNames()
	local plan = ns.Util.DeepCopy(ns.Bundled.Get("b:the-deadmines"))
	plan.bundled = nil
	plan.floors[1].name = "The Hall of Tests" -- the mock's UiMap 300, which has art
	plan.floors[1].uiMapID = nil
	T.eq(ns.Journal.FloorMap(plan, 1), 300, "without tiles the named map stands in")
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	ns.GameFiles.Reset()
	T.eq(ns.Journal.FloorMap(plan, 1), nil, "with the dungeon's tiles: no same-named map")
	T.ok(ns.GameFiles.FloorArt(plan, 1), "the tiles are what the canvas draws")
	-- The name index: one pass over the map IDs for any number of names.
	local real, calls = _G.C_Map.GetMapInfo, 0
	_G.C_Map.GetMapInfo = function(id)
		calls = calls + 1
		return real(id)
	end
	ns.Instances.ForgetMapNames()
	for _, name in ipairs({ "The Hall of Tests", "Nowhere", "Map 7", "Elsewhere", "The Hall of Tests" }) do
		ns.Instances.FindArtMapByName(name)
	end
	_G.C_Map.GetMapInfo = real
	T.ok(calls <= ns.Instances.MAP_SCAN, "one scan, not one per name: " .. calls)
	T.eq(ns.Instances.FindArtMapByName("the hall of tests"), 300)
	mock.journal.tiers = saved
	mock.files = {}
	ns.Journal.Reset()
	ns.GameFiles.Reset()
	ns.Instances.ForgetMapNames()
end)

T.case("Follow-ups: the game's tabs keep their padding and common width when they show", function()
	boot()
	local bar = W.Tabs(_G.DungeonPlannerMainFrame, { { id = "a", text = "Map" }, { id = "b", text = "Assignments" } },
		function() end, { style = "bottom", equal = true })
	T.eq(bar.style, "bottom", "the game's tabs")
	local widths = {}
	for i, b in ipairs(bar.buttons) do
		widths[i] = b:GetWidth()
	end
	T.eq(widths[1], widths[2], "equal")
	for i, b in ipairs(bar.buttons) do
		b:Hide()
		b:Show() -- the template sizes itself again from its parent
		T.eq(b:GetWidth(), widths[i], "tab " .. i .. " keeps its width")
	end
	local single = W.Tabs(_G.DungeonPlannerMainFrame, { { id = "a", text = "Map" } }, function() end, { style = "bottom" })
	local w = single.buttons[1]:GetWidth()
	single.buttons[1]:Hide()
	single.buttons[1]:Show()
	T.eq(single.buttons[1]:GetWidth(), w, "its padding stays")
end)

T.case("Follow-ups: the close button and the size grip sit above the window's metal border", function()
	boot()
	local f = _G.DungeonPlannerMainFrame
	T.ok(f.dpNative, "the game's window")
	local border = f.NineSlice:GetFrameLevel()
	T.ok(f.close:GetFrameLevel() > border, "close above the border")
	T.ok(f.grip:GetFrameLevel() > border, "grip above the border")
end)

T.case("Follow-ups: the objective field adds on Enter or its button, never on leaving it", function()
	boot()
	local entry = ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
	local plan = ns.Home.CreatePlan("dungeon", "Objectives", entry)
	ns.UI.SelectTab("plan")
	local progress = _G.DungeonPlannerMainFrame.instancePage.panels.plan.progress
	local field, edit = progress.newObjective, progress.newObjective.edit
	local before = #plan.objectives
	edit:SetText("Buy repairs")
	edit:GetScript("OnEditFocusLost")(edit)
	T.eq(#plan.objectives, before, "leaving the field adds nothing")
	T.eq(field:GetValue(), "Buy repairs", "and keeps the text")
	edit:GetScript("OnEnterPressed")(edit)
	T.eq(#plan.objectives, before + 1, "Enter adds")
	T.eq(plan.objectives[#plan.objectives].text, "Buy repairs")
	T.eq(field:GetValue(), "", "the field empties")
	edit:SetText("Agree on marks")
	progress.addObjective:GetScript("OnClick")(progress.addObjective, "LeftButton")
	T.eq(#plan.objectives, before + 2, "the button adds")
	edit:SetText("   ")
	edit:GetScript("OnEnterPressed")(edit)
	T.eq(#plan.objectives, before + 2, "blank text adds nothing")
end)
