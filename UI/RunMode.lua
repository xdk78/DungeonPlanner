-- Run mode: a compact window to keep open while running the instance. It shows the plan's current step (Model/Steps.lua),
-- the next pull with its note, tips for the next boss, and a mini map framing the step and its neighbours, with its
-- route segment, a ring on the step's spot and only that step's party positions (no labels: MapCanvas compact mode).
-- Spots the plan only estimates carry a small "~" (Style.WithApprox) instead of the words "(approx.)".
-- Prev / Next move through the steps; so do the "Next pull" / "Previous pull" key bindings while it is open, and a
-- boss kill the tracker detects moves past that boss's step. "Toggle run mode" has its own key binding (no default).
--
-- The window is our own plain frame (no secure template): showing, hiding and updating it is allowed in combat. It
-- is movable; its position and whether it was open are saved in the profile (ui.run). Built on first use.

local _, ns = ...
local RunMode = ns:NewModule("RunMode")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE
local UI = ns.UI

local WIDTH, HEIGHT, MAP_H = 300, 556, 170
-- The step block's room: its label, title and two lines of text. A step with one line takes less, and the mini map
-- grows into the rest, so no gap is left between the step's text and the map.
local STEP_H = 72
local BUTTON_W = 92 -- Prev and Next; the step counter sits between them
local frame

local function saved()
	ns.db.ui.run = type(ns.db.ui.run) == "table" and ns.db.ui.run or {}
	return ns.db.ui.run
end

local function ctx()
	return UI.ctx
end

-- The first `n` characters of text, cut at a word, with an ellipsis.
local function excerpt(text, n)
	text = tostring(text or ""):gsub("%s+", " ")
	if #text <= n then
		return text
	end
	local cut = text:sub(1, n):match("^(.*)%s") or text:sub(1, n)
	return cut .. "..."
end

-- A titled block: a gold label, a title (one line, or `titleLines` lines that wrap) and a wrapping text. A block
-- with a wrapping title takes the height its lines need (b:Fit).
local function block(parent, label, maxLines, titleLines)
	local b = CreateFrame("Frame", nil, parent)
	b.label = W.Label(b, label)
	b.label:SetPoint("TOPLEFT")
	b.title = W.Text(b, "title", "ink")
	b.title:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -SP.xxs)
	b.title:SetPoint("RIGHT")
	if titleLines and titleLines > 1 then
		b.title:SetWordWrap(true)
		b.title:SetJustifyV("TOP")
		if b.title.SetMaxLines then
			b.title:SetMaxLines(titleLines)
		end
	end
	b.text = W.Paragraph(b, "caption", "muted")
	b.text:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -SP.xxs)
	b.text:SetPoint("RIGHT")
	if b.text.SetMaxLines then
		b.text:SetMaxLines(maxLines or 4)
	end
	-- A long title is cut after a whole word; hovering the block shows it whole.
	function b:Set(title, text)
		W.FitText(self.title, title or "")
		self.text:SetText(text or "")
		if titleLines and titleLines > 1 then
			self:Fit()
		end
	end
	-- The height of the label, the title's lines and the text's, with their gaps.
	function b:Fit()
		local h = (self.label:GetStringHeight() or 12) + SP.xxs + (self.title:GetStringHeight() or 16) + SP.xxs
			+ ((self.text:GetText() or "") ~= "" and (self.text:GetStringHeight() or 0) or 0)
		self:SetHeight(math.ceil(h) + SP.xxs)
	end
	b:EnableMouse(true)
	b:SetScript("OnEnter", function(self)
		W.FullTextTooltip(self, self.title)
	end)
	b:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	return b
end

-- Up to three key abilities of the next boss as spell icons on the block's label line, each with the game's spell tooltip.
local ABILITY_ICONS = 3
local ICON_SIZE = 18

local function abilityIcons(b)
	if b.abilityIcons then
		return b.abilityIcons
	end
	local icons = {}
	for i = 1, ABILITY_ICONS do
		local btn = CreateFrame("Button", nil, b)
		btn:SetSize(ICON_SIZE, ICON_SIZE)
		btn:SetPoint("TOPRIGHT", -(i - 1) * (ICON_SIZE + SP.xs), 0)
		btn.tex = btn:CreateTexture(nil, "ARTWORK")
		btn.tex:SetAllPoints()
		btn:SetScript("OnEnter", function(self)
			local tt = rawget(_G, "GameTooltip")
			if tt and self.spellID then
				W.TipBeside(tt, self)
				if tt.SetSpellByID then
					pcall(tt.SetSpellByID, tt, self.spellID)
				end
				local tags = ns.BossInfo.TagText(self.tags)
				if tags ~= "" and tt.AddLine then
					tt:AddLine(tags, 1, 0.82, 0)
				end
				tt:Show()
			end
		end)
		btn:SetScript("OnLeave", function(self)
			local tt = rawget(_G, "GameTooltip")
			if tt and tt.IsOwned and tt:IsOwned(self) then
				tt:Hide()
			end
		end)
		btn:Hide()
		icons[i] = btn
	end
	b.abilityIcons = icons
	return icons
end

-- Show the boss's key abilities (none: hide the icons).
local function setAbilityIcons(b, plan, enc)
	local icons = abilityIcons(b)
	local list = enc and ns.BossInfo.KeyAbilities(plan, enc, ABILITY_ICONS) or {}
	local spells = rawget(_G, "C_Spell")
	for i, btn in ipairs(icons) do
		local ab = list[i]
		btn.spellID, btn.tags = ab and ab.spellID, ab and ab.tags
		btn:SetShown(ab ~= nil)
		if ab then
			local texture
			if spells and type(spells.GetSpellTexture) == "function" then
				local ok, t = pcall(spells.GetSpellTexture, ab.spellID)
				texture = ok and ns.Util.Plain(t) or nil
			end
			btn.tex:SetTexture(texture or 134400)
		end
	end
end

local function build()
	local f = W.Window("DungeonPlannerRunFrame", L["Run mode"], { width = WIDTH, height = HEIGHT }, WIDTH, HEIGHT,
		{ compact = true, noEscape = true }) -- Escape must not close it mid-run
	f:SetFrameStrata("MEDIUM")
	f:SetResizable(false)
	f.grip:Hide()
	-- Position from the profile.
	local pos = saved().point
	if type(pos) == "table" and pos[1] then
		f:ClearAllPoints()
		f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
	else
		f:ClearAllPoints()
		f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 40)
	end
	f:SetScale(ns.db.settings.scale or 1)
	f.title:SetFontObject(S.fonts.body)
	f.close:SetScript("OnClick", function()
		RunMode.Hide()
	end)
	-- Save where it was dragged.
	f.header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, relativePoint, x, y = f:GetPoint(1)
		saved().point = { point, relativePoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
	end)
	-- In the title bar, left of the close button (the window has no row under it).
	f.open = W.IconButton(f, "launcher", L["Open the planner"], function()
		UI.Show("map")
	end)
	f.open:SetPoint("RIGHT", f.close, "LEFT", -SP.xs, 0)
	W.RaiseAboveBorder(f, f.open)

	local ins = f.insets
	local inner = CreateFrame("Frame", nil, f)
	inner:SetPoint("TOPLEFT", ins.left + SP.md, -(ins.top + SP.sm))
	inner:SetPoint("BOTTOMRIGHT", -(ins.right + SP.md), ins.bottom + SP.md)
	f.inner = inner

	f.planName = W.Text(inner, "caption", "muted")
	f.planName:SetPoint("TOPLEFT")
	f.planName:SetPoint("RIGHT")
	-- Group sync (UI/RunSync.lua): who leads and who follows, with Lead / Unfollow / Rejoin / Ask for it. Shown only in a
	-- group with something to say; the window grows by its height.
	f.sync = ns.RunSync.BuildLine(inner)
	f.sync:SetPoint("TOPLEFT", f.planName, "BOTTOMLEFT", 0, -SP.xs)
	f.sync:SetPoint("RIGHT")
	-- The run recorder (Tracker/Recorder.lua): a red dot and "Recording" while it records, the live pull count against
	-- the plan's pulls; a click switches recording on or off.
	f.rec = CreateFrame("Button", nil, inner)
	f.rec:SetPoint("TOPLEFT", f.planName, "BOTTOMLEFT", 0, -SP.xxs)
	f.rec:SetPoint("RIGHT")
	f.rec:SetHeight(14)
	f.rec.dot = W.Dot(f.rec, "danger")
	f.rec.dot:SetPoint("LEFT")
	f.rec.text = W.Text(f.rec, "caption", "muted")
	f.rec.text:SetPoint("LEFT", f.rec.dot, "RIGHT", SP.xs, 0)
	f.rec.text:SetPoint("RIGHT")
	f.rec:SetScript("OnClick", function()
		ns.Recorder.SetEnabled(not ns.Recorder.Enabled())
	end)
	W.SetTooltip(f.rec, L["Record my runs"], L["Click to switch the run recorder on or off. Recorded runs are in the Runs section."])
	-- Progress against the plan while recording (Model/RunCompare.lua Drift): on plan with the step the run is probably
	-- at, or a warning; a click goes to that step. Shown only while a run of this plan's instance is recorded.
	f.drift = CreateFrame("Button", nil, inner)
	f.drift:SetPoint("TOPLEFT", f.rec, "BOTTOMLEFT", 0, -SP.xxs)
	f.drift:SetPoint("RIGHT")
	f.drift:SetHeight(14)
	f.drift.text = W.Text(f.drift, "caption", "muted")
	f.drift.text:SetPoint("LEFT")
	f.drift.text:SetPoint("RIGHT")
	f.drift:SetScript("OnClick", function()
		RunMode.GoToEstimate()
	end)
	f.drift:SetScript("OnEnter", function(self)
		local tt = W.Tip()
		if not tt or not self.lines then
			return
		end
		tt:SetOwner(self, "ANCHOR_BOTTOM")
		tt:AddLine(L["Progress against the plan"], 1, 0.82, 0)
		for _, line in ipairs(self.lines) do
			tt:AddLine(line, 0.93, 0.91, 0.86, true)
		end
		W.TipShow(tt)
	end)
	f.drift:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	-- Before the first step: what is left to prepare ("Prep: 3 quests to pick up"); a click opens the Prep section.
	-- In the drift line's place (that one shows only once a run is recorded, so after the start).
	f.prep = CreateFrame("Button", nil, inner)
	f.prep:SetPoint("TOPLEFT", f.rec, "BOTTOMLEFT", 0, -SP.xxs)
	f.prep:SetPoint("RIGHT")
	f.prep:SetHeight(14)
	f.prep.text = W.Text(f.prep, "caption", "gold")
	f.prep.text:SetPoint("LEFT")
	f.prep.text:SetPoint("RIGHT")
	f.prep:SetScript("OnClick", function()
		UI.Show("prep")
	end)
	W.SetTooltip(f.prep, L["Prep"], L["Quests, keys, the group and the way there. Click to open the Prep section."])
	f.prep:Hide()
	f.step = block(inner, L["Step"], 2)
	f.step:SetPoint("TOPLEFT", f.rec, "BOTTOMLEFT", 0, -SP.sm)
	f.step:SetPoint("RIGHT")
	f.step:SetHeight(STEP_H)
	f.step.title:SetFontObject(S.fonts.page)
	S.TextColor(f.step.title, "gold")

	-- Mini map: the plan's floor, read-only, centred on the step.
	f.map = ns.MapCanvas.Create(inner, {
		getPlan = function()
			return ctx():Plan()
		end,
		readOnly = function()
			return true
		end,
		getFloor = function()
			return f.floor or 1
		end,
		getTool = function()
			return "select"
		end,
		getSelectedMarker = function()
			return nil
		end,
		getFocusPull = function()
			return ctx().focusPull
		end,
		getFocusEncounter = function()
			return ctx().focusEncounter
		end,
		getFocusSegment = function()
			return ctx().focusSegment
		end,
		-- The current step's leg stands out as a hovered one does on the big map (the rest of the routes dim).
		highlightFocus = function()
			return ns.db.settings.routes.hover ~= false
		end,
		getActiveRoute = function()
			return nil
		end,
		showLabels = function()
			return false
		end,
		compact = function()
			return true
		end,
		getFocusPoint = function()
			local c = ctx()
			local index = c:StepIndex()
			return c:Steps()[index or 1]
		end,
		showCoordinates = function()
			return false
		end,
		layerVisible = function(id)
			return ns.db.ui.mapLayers[id] ~= false
		end,
		spawnsShown = function()
			return ns.MapSpawns.LayerShown(ctx():Plan())
		end,
		iconScale = function()
			return 0.7
		end,
		-- The plan's drawings: the current step's (and those tied to no step), all, or none (RunMode.DRAWINGS).
		drawingsMode = function()
			return RunMode.DrawingsMode()
		end,
		onSelectMarker = function() end,
		onSelectRoute = function() end,
		onMarkerMenu = function() end,
		onPointMenu = function() end,
		onChanged = function() end,
		onRoutePoint = function() end,
		onRouteFinished = function() end,
	})
	f.map:SetPoint("TOPLEFT", f.step, "BOTTOMLEFT", 0, -SP.sm)
	f.map:SetPoint("RIGHT")
	f.map:SetHeight(MAP_H)
	f.map.noArt:SetText("")
	-- Which floor the mini map shows, on a dark plate in its top-left corner (an instance of several floors only).
	local inset = ns.MapCanvas.FRAME_INSET + SP.xs
	f.mapFloor = W.Text(f.map.edge, "caption", "white")
	f.mapFloor:SetPoint("TOPLEFT", inset + SP.xs, -(inset + SP.xxs))
	f.mapFloorPlate = f.map.edge:CreateTexture(nil, "ARTWORK", nil, -8)
	f.mapFloorPlate:SetColorTexture(0.03, 0.035, 0.045, 0.78)
	f.mapFloorPlate:SetPoint("TOPLEFT", f.mapFloor, "TOPLEFT", -SP.xs, SP.xxs + 1)
	f.mapFloorPlate:SetPoint("BOTTOMRIGHT", f.mapFloor, "BOTTOMRIGHT", SP.xs, -(SP.xxs + 1))
	-- Where the map comes from, under it (not over the art).
	f.mapCredit = W.Text(inner, "caption", "muted")
	f.mapCredit:SetPoint("TOPRIGHT", f.map, "BOTTOMRIGHT", 0, -SP.xxs)
	f.mapCredit:SetJustifyH("RIGHT")
	-- One click cycles which drawings the mini map shows: this step's, all, none.
	f.drawings = CreateFrame("Button", nil, inner)
	f.drawings:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -SP.xxs)
	f.drawings:SetSize(150, 14)
	f.drawings.text = W.Text(f.drawings, "caption", "muted")
	f.drawings.text:SetPoint("LEFT")
	f.drawings:SetScript("OnClick", function()
		RunMode.CycleDrawings()
	end)
	f.drawings:SetScript("OnEnter", function(self)
		S.TextColor(self.text, "white")
	end)
	f.drawings:SetScript("OnLeave", function(self)
		S.TextColor(self.text, "muted")
	end)
	W.SetTooltip(f.drawings, L["Drawings"],
		L["Click to show this step's drawings (and those tied to no step), all of them, or none."])

	f.pull = block(inner, L["Next pull"], 2, 2) -- "Pull 1: Dark Iron Summoner patrol (Magmatus)" on two lines
	f.pull:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -(SP.sm + 14))
	f.pull:SetPoint("RIGHT")
	f.pull:SetHeight(64)
	f.boss = block(inner, L["Next boss"], 5)
	f.boss:SetPoint("TOPLEFT", f.pull, "BOTTOMLEFT", 0, -SP.sm)
	f.boss:SetPoint("RIGHT")
	f.boss:SetPoint("BOTTOM", 0, SZ.control + SP.sm)
	S.TextColor(f.boss.title, "gold")

	-- Both the game's panel buttons: a disabled Prev (on the first step) looks as the game's disabled buttons do.
	f.prev = W.Button(inner, L["Prev"], "primary", function()
		RunMode.Step(-1)
	end)
	f.prev:SetPoint("BOTTOMLEFT")
	f.prev:SetWidth(BUTTON_W)
	f.prev.dpFixedWidth = true
	f.next = W.Button(inner, L["Next"], "primary", function()
		RunMode.Step(1)
	end)
	f.next:SetPoint("BOTTOMRIGHT")
	f.next:SetWidth(BUTTON_W)
	f.next.dpFixedWidth = true
	-- Between the buttons, never under them.
	f.counter = W.Text(inner, "caption", "muted")
	f.counter:SetPoint("LEFT", f.prev, "RIGHT", SP.xs, 0)
	f.counter:SetPoint("RIGHT", f.next, "LEFT", -SP.xs, 0)
	f.counter:SetJustifyH("CENTER")
	f:SetScript("OnShow", function()
		saved().shown = true
		RunMode.Refresh()
		ns.RunSync.OnShow()
	end)
	f:Hide()
	frame = f
end

-- Refresh ------------------------------------------------------------------------------------------------------------------

function RunMode.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local c = ctx()
	local plan = c:Plan()
	local steps = c:Steps()
	local index = c:StepIndex()
	frame.planName:SetText(plan and (ns.Names.Instance(plan.instance) .. "  •  " .. plan.name) or L["Select a plan first."])
	RunMode.RefreshSync(plan)
	RunMode.RefreshRecorder(plan)
	frame.prev:SetDisabled(not index or index <= 1)
	frame.next:SetDisabled(#steps == 0 or (index ~= nil and index >= #steps))
	frame.next:SetLabel(index and L["Next"] or L["Start"])
	frame.counter:SetText(index and string.format(L["%d of %d"], index, #steps) or "")
	if not plan or #steps == 0 then
		frame.step:Set(plan and L["No steps yet"] or "", "")
		frame.step:SetHeight(STEP_H)
		frame.pull:Set("-", "")
		frame.boss:Set("-", "")
		frame.map:Hide()
		frame.drawings:Hide()
		return
	end
	local step = steps[index or 1]
	local title, caption, approx, note = UI.StepText(plan, step)
	frame.step.label:SetText(index and string.format(L["Step %d"], index) or L["First step"])
	local text = caption
	if step.kind == "pull" then
		local marks = UI.PullMarks((ns.Util.FindById(plan.pulls, step.pull)))
		if marks ~= "" then
			text = text .. "  •  " .. marks
		end
	end
	-- Planned progress: the last pull so far that has one (a boss step shows the pull before it).
	local progress = ns.Steps.ProgressAt(plan, steps, index or 1)
	if progress then
		text = text .. "  •  " .. string.format(L["Forces %d%%"], progress)
	end
	if note and note ~= "" and note ~= title then
		text = text .. "  •  " .. note
	end
	frame.step:Set(title, S.WithApprox(text, approx))
	-- As tall as its lines; the map below takes what is left of the block's room (the blocks under it stay put).
	frame.step:Fit()
	local stepH = math.min(STEP_H, math.ceil(frame.step:GetHeight() or STEP_H))
	frame.step:SetHeight(stepH)
	frame.map:SetHeight(MAP_H + STEP_H - stepH)

	-- Next pull and next boss, from the current step on.
	local pi, pullStep = ns.Steps.Next(steps, index or 1, "pull")
	local pull = pullStep and ns.Util.FindById(plan.pulls, pullStep.pull)
	if pull then
		local pullNote, pullApprox = ns.Util.SplitApprox(pull.note)
		local marks = UI.PullMarks(pull, { progress = true })
		if marks ~= "" then
			pullNote = marks .. ((pullNote and pullNote ~= "") and ("  •  " .. pullNote) or "")
		end
		frame.pull:Set(string.format(L["Pull %d"], ns.Plan.PullIndex(plan, pull.id) or pi) .. ": " .. pull.name,
			S.WithApprox(pullNote, pullApprox))
	else
		frame.pull:Set(L["No more pulls"], "")
	end
	local _, bossStep = ns.Steps.Next(steps, index or 1, "boss")
	local enc = bossStep and ns.Util.FindById(plan.encounters, bossStep.encounter)
	if enc then
		-- The level (bundled data, else the provider's) leads the line under the name.
		local level = ns.BossInfo.RunMeta(plan, enc)
		local strategy = excerpt(enc.strategy, 220)
		frame.boss:Set(ns.Names.Encounter(enc), level and (strategy ~= "" and (level .. "  \226\128\162  " .. strategy) or level) or strategy)
		setAbilityIcons(frame.boss, plan, enc)
	elseif bossStep then
		frame.boss:Set(UI.StepText(plan, bossStep), "")
		setAbilityIcons(frame.boss, plan, nil)
	else
		frame.boss:Set(L["No more bosses"], "")
		setAbilityIcons(frame.boss, plan, nil)
	end

	-- Mini map on the step's floor, framing the step with the steps before and after it on that floor.
	frame.floor = step.floor or 1
	frame.map:Show()
	frame.map:LoadPlanFloor(plan, frame.floor)
	frame.mapCredit:SetText(frame.map.creditText or "")
	local floors = ns.Floors.For(plan)
	local several = #floors > 1 and floors[frame.floor] ~= nil
	local floorText = several and ns.Names.Floor(floors[frame.floor], frame.floor, plan) or ""
	-- Where the player is, when the client says (Floors.PlayerFloor; unverified on Forever) and it is another floor.
	local playerFloor = several and ns.Floors.PlayerFloor(plan) or nil
	frame.playerFloor = playerFloor -- what the zone events compare with
	if playerFloor and playerFloor ~= frame.floor and floors[playerFloor] then
		floorText = string.format(L["%s (you are on %s)"], floorText, ns.Names.Floor(floors[playerFloor], playerFloor, plan))
	end
	frame.mapFloor:SetText(floorText)
	frame.mapFloor:SetShown(several)
	frame.mapFloorPlate:SetShown(several)
	local hasDrawings = ns.Drawing.Count(plan) > 0
	frame.drawings:SetShown(hasDrawings)
	frame.drawings.text:SetText(L[RunMode.DRAWING_TEXT[RunMode.DrawingsMode()]])
	local here = index or 1
	if step.x then
		local points = { { step.x, step.y } }
		for _, i in ipairs({ here - 1, here + 1 }) do
			local s = steps[i]
			if s and s.x and s.floor == step.floor then
				points[#points + 1] = { s.x, s.y }
			end
		end
		-- With room around them: the step and its neighbours stay clear of the map's frame (labels painted on the map
		-- and the route leaving the box are not cut at the edge right by them).
		frame.map:FrameSteps(points, { pad = 0.1, minSpan = 0.3 })
	else
		frame.map:ResetView()
	end
end

-- Which drawings the mini map shows (saved in ui.run.drawings): the current step's ("step", the default: drawings tied to
-- that pull or boss, and those tied to no step), every one ("all"), or none ("off").
RunMode.DRAWINGS = { "step", "all", "off" }
RunMode.DRAWING_TEXT = { step = "Drawings: this step", all = "Drawings: all", off = "Drawings: hidden" }

-- A zone event: the floor line again when the player's floor changed (one floor: nothing to say, nothing done).
function RunMode.OnZoneChanged()
	if not (frame and RunMode.IsShown()) then
		return
	end
	local plan = ctx():Plan()
	if not plan or #ns.Floors.For(plan) <= 1 then
		return
	end
	if ns.Floors.PlayerFloor(plan) ~= frame.playerFloor then
		RunMode.Refresh()
	end
end

function RunMode.DrawingsMode()
	local mode = saved().drawings
	return RunMode.DRAWING_TEXT[mode] and mode or "step"
end

function RunMode.CycleDrawings()
	local current = RunMode.DrawingsMode()
	for i, mode in ipairs(RunMode.DRAWINGS) do
		if mode == current then
			saved().drawings = RunMode.DRAWINGS[i % #RunMode.DRAWINGS + 1]
			break
		end
	end
	RunMode.Refresh()
end

-- The recorder line: "Recording • pull 3 of 9 planned", or how to start it.
function RunMode.RecorderText(plan)
	local R = ns.Recorder
	if not R.Enabled() then
		return L["Not recording (click to record this run)"], false
	end
	local run = R.Current()
	local inside = ns.Instances.Current().inInstance
	if not run or not inside then
		return L["Recording starts when you enter a dungeon."], false
	end
	local pulls = #run.p
	local open = ns.RunLog.OpenPull(run) ~= nil
	local text = L["Recording"] .. " • " .. (open and string.format(L["pull %d (in combat)"], pulls) or ns.Plural(pulls, L["%d pull|%d pulls"]))
	if plan and #plan.pulls > 0 then
		text = text .. " • " .. string.format(L["plan: %d"], #plan.pulls)
	end
	if #run.b > 0 then
		text = text .. " • " .. ns.Plural(#run.b, L["%d boss|%d bosses"])
	end
	return text, true
end

-- Progress against the plan while a run of its instance is recorded: RunCompare.Drift, or nil.
function RunMode.Drift(plan)
	local R = ns.Recorder
	if not (plan and R.Enabled()) then
		return nil
	end
	local run = R.Current()
	if not run or run.k ~= R.KeyForPlan(plan) or (#run.p == 0 and #run.b == 0) then
		return nil
	end
	return ns.RunCompare.Drift(plan, run, ctx():Steps(), ns.Panels.runs.CompareOptions(plan))
end

-- The drift line's text, whether it warns, and its tooltip lines; nil without a drift.
function RunMode.DriftText(plan)
	local d = RunMode.Drift(plan)
	if not d then
		return nil
	end
	local function bossName(encId)
		local enc = ns.Util.FindById(plan.encounters, encId)
		return enc and ns.Names.Encounter(enc) or L["Boss"]
	end
	local lines = { string.format(L["Pulls: %d of %d planned"], d.pullsDone, d.pullsPlanned) }
	if d.nextBoss then
		lines[#lines + 1] = string.format(L["Since the last boss: %d, planned %d before %s"], d.since, d.sincePlanned,
			bossName(d.nextBoss))
	end
	local steps = ctx():Steps()
	if d.step and steps[d.step] then
		lines[#lines + 1] = string.format(L["Probably at step %d: %s. Click to go there."], d.step,
			(UI.StepText(plan, steps[d.step])))
	end
	lines[#lines + 1] =
		L["An estimate from boss kills and the pull count: the game does not show where you are or which pack you pulled."]
	local w = d.warnings[1]
	if w then
		return ns.Discord.DivergenceText(w, bossName), true, lines, d
	end
	local text = L["On plan"]
	if d.step then
		text = text .. " • " .. string.format(L["step ~ %d"], d.step)
	end
	return text, false, lines, d
end

-- The prep line before the first step (not started, or on step 1): "Prep: 3 quests to pick up • 1 key missing", nil
-- when there is nothing left to do.
function RunMode.PrepText(plan)
	local index = ctx():StepIndex()
	if not plan or (index and index > 1) then
		return nil
	end
	local sum = ns.PrepInfo.Summary(plan)
	if not sum then
		return nil
	end
	local parts = {}
	if sum.quests > 0 then
		parts[#parts + 1] = ns.Plural(sum.quests, L["%d quest to pick up|%d quests to pick up"])
	end
	if sum.keys > 0 then
		parts[#parts + 1] = ns.Plural(sum.keys, L["%d key missing|%d keys missing"])
	end
	return string.format(L["Prep: %s"], table.concat(parts, "  •  "))
end

-- Go to the step the run is probably at (the drift line's click).
function RunMode.GoToEstimate()
	local plan = ctx():Plan()
	local _, _, _, d = RunMode.DriftText(plan)
	if d and d.step and d.step ~= ctx():StepIndex() then
		UI.FocusStep(d.step, { stay = true })
		RunMode.Refresh()
	end
end

-- The group sync line (UI/RunSync.lua) under the plan's name; the recorder line goes under it, and the window grows by
-- its height so the blocks below keep theirs.
function RunMode.RefreshSync(plan)
	if not frame then
		return
	end
	local h = ns.RunSync.RefreshLine(frame.sync, plan)
	frame.rec:ClearAllPoints()
	frame.rec:SetPoint("TOPLEFT", h > 0 and frame.sync or frame.planName, "BOTTOMLEFT", 0, -SP.xxs)
	frame.rec:SetPoint("RIGHT")
	frame:SetHeight(HEIGHT + (h > 0 and (h + SP.xs) or 0))
end

-- The prep line alone (under the drift line, which hides it): redrawn on PREP_CHANGED, and by RefreshRecorder.
function RunMode.RefreshPrep(plan)
	if not frame then
		return
	end
	local drift = frame.drift:IsShown()
	local prepText = not drift and RunMode.PrepText(plan) or nil
	frame.prep:SetShown(prepText ~= nil)
	if prepText then
		W.FitText(frame.prep.text, prepText)
	end
	frame.step:ClearAllPoints()
	frame.step:SetPoint("TOPLEFT", (drift and frame.drift) or (prepText and frame.prep) or frame.rec, "BOTTOMLEFT", 0,
		-SP.sm)
	frame.step:SetPoint("RIGHT")
end

function RunMode.RefreshRecorder(plan)
	if not frame then
		return
	end
	local driftText, warns, lines = RunMode.DriftText(plan)
	frame.drift:SetShown(driftText ~= nil)
	frame.drift.lines = lines
	if driftText then
		W.FitText(frame.drift.text, (warns and "! " or "") .. driftText)
		S.TextColor(frame.drift.text, warns and "warning" or "muted")
	end
	RunMode.RefreshPrep(plan)
	local text, on = RunMode.RecorderText(plan)
	frame.rec.text:SetText(text)
	-- Red while recording, a dim dot when not: the line keeps its indent either way.
	frame.rec.dot:SetStatus(on and "danger" or "dim")
	S.TextColor(frame.rec.text, on and "ink" or "muted")
end

-- Actions ------------------------------------------------------------------------------------------------------------------

function RunMode.Step(delta)
	UI.StepBy(delta, { stay = true })
	local c = ctx()
	local plan, index = c:Plan(), c:StepIndex()
	local step = index and c:Steps()[index]
	if plan and step then
		local title = UI.StepText(plan, step)
		ns:FirePublic("DUNGEONPLANNER_STEP", plan.id, index, title)
	end
	RunMode.Refresh()
end

function RunMode.Show()
	if not frame then
		build()
	end
	frame:Show()
end

function RunMode.Hide()
	if frame then
		frame:Hide()
	end
	saved().shown = false
end

function RunMode.Toggle()
	if frame and frame:IsShown() then
		RunMode.Hide()
	else
		RunMode.Show()
	end
end

function RunMode.IsShown()
	return frame ~= nil and frame:IsShown()
end

function RunMode.ApplyScale()
	if frame then
		frame:SetScale(ns.db.settings.scale or 1)
	end
end

-- A boss died: move past its step (Steps.AfterKill). The plan's boss by game ID, else by name; a kill that matches no
-- boss of the plan, inside the instance, completes the next boss step from the current one.
function RunMode.OnKill(encounterID, name)
	local c = ctx()
	local plan = c:Plan()
	if not plan then
		return
	end
	local steps = c:Steps()
	if #steps == 0 then
		return
	end
	local enc = ns.Plan.FindEncounterByGameID(plan, encounterID, ns.Journal.GameIdOf(plan))
	if not enc and type(name) == "string" and name ~= "" then
		local want = ns.Match.Norm(name)
		for _, e in ipairs(plan.encounters) do
			if ns.Match.Norm(ns.Names.Encounter(e)) == want or ns.Match.Norm(e.name or "") == want then
				enc = e
				break
			end
		end
	end
	local current = c:StepIndex() or 1
	local nextIndex
	if enc then
		nextIndex = ns.Steps.AfterKill(steps, current, enc.id)
	else
		local here = ns.Instances.Current()
		local inst = ns.Names.Instance(plan.instance)
		if not (here.inInstance and ns.Match.Norm(here.name or "") == ns.Match.Norm(inst)) then
			return
		end
		local i = ns.Steps.Next(steps, current, "boss")
		nextIndex = i and math.min(i + 1, #steps) or current
	end
	if nextIndex ~= c:StepIndex() then
		-- Group sync: the leader's next state waits out the fight's lockdown; this kill must not read as stepping away.
		ns.RunSync.LocalKill(plan.id, nextIndex)
		UI.FocusStep(nextIndex, { stay = true })
		RunMode.Refresh()
	end
end

function RunMode.Init()
	ns:On("STEP_CHANGED", RunMode, RunMode.Refresh)
	ns:On("ITEMS_READY", RunMode, function()
		if RunMode.IsShown() then
			RunMode.Refresh()
		end
	end)
	-- The prep line follows the quest log, bags and group (Data/PrepInfo.lua): watched only while the window is open
	-- before the second step, where the line can show; only that line is redrawn.
	ns.PrepInfo.Watch(RunMode, function()
		return frame ~= nil and frame:IsShown() and (ctx():StepIndex() or 1) <= 1
	end)
	ns:On("PREP_CHANGED", RunMode, function()
		if frame and frame:IsShown() then
			RunMode.RefreshPrep(ctx():Plan())
		end
	end)
	-- Cheap: only the recorder line, and only while the window is open.
	ns:On("RECORDER_CHANGED", RunMode, function()
		if frame and frame:IsShown() then
			RunMode.RefreshRecorder(ctx():Plan())
		end
	end)
	ns:On("PLAN_CHANGED", RunMode, function()
		RunMode.Refresh()
	end)
	ns:On("SYNC_CHANGED", RunMode, function()
		if frame and frame:IsShown() then
			RunMode.RefreshSync(ctx():Plan())
		end
	end)
	ns:On("BOSS_KILLED", RunMode, function(encounterID, name)
		ns.SafeCall(RunMode.OnKill, encounterID, name)
	end)
	-- The mini map's floor line says where the player is (Floors.PlayerFloor), while the window is open: refreshed only
	-- when that floor changed, and never for an instance of one floor.
	for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns:RegisterEvent(event, function()
			ns.SafeCall(RunMode.OnZoneChanged)
		end)
	end
	if saved().shown then
		RunMode.Show()
	end
end
