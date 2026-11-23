-- Progress tab: this run's boss kills (from ENCOUNTER_END / BOSS_KILL), lifetime kills, and the plan's objective
-- checklist (per character). Bosses without their own encounter ID use the one the Adventure Guide gives the matched
-- journal boss (Data/Journal.lua), so recommended plans are tracked too.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Progress, Schema = ns.Plan, ns.Progress, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local Panel = {}
ns.Panels.progress = Panel

-- The bosses and the objectives stand one under the other while they fit; from this width of the panel on they may
-- stand side by side when they do not.
local TWO_COLUMNS = 460

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)

	local function plan()
		return ctx:Plan()
	end
	local function store()
		return ns.char.progress
	end
	local function gameID(enc)
		local _, id = ns.Journal.EncounterIds(plan(), enc)
		return id
	end

	f.summary = W.Text(f, "title", "gold")
	f.summary:SetPoint("TOPLEFT")
	f.summary:SetPoint("RIGHT")
	f.run = W.Text(f, "caption", "muted")
	f.run:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -SP.xs)
	f.run:SetPoint("RIGHT")

	f.mark = W.Button(f, L["Mark next boss killed"], "outline", function()
		ns.Actions.BossKilled()
	end)
	f.mark:SetPoint("TOPLEFT", f.run, "BOTTOMLEFT", 0, -SP.md)
	f.mark.dpGround = "surface"
	f.endRun = W.Button(f, L["Start a new run"], "outline", function()
		ns.Tracker.EndRun()
	end)
	f.endRun.dpGround = "surface"
	W.SetTooltip(f.endRun, L["Start a new run"],
		L["Archives the current run's kills. Runs also start by themselves when you enter an instance after a while away."])

	-- Bosses and objectives: two columns, or one above the other on a narrow panel (f:Layout).
	local left = CreateFrame("Frame", nil, f)
	local right = CreateFrame("Frame", nil, f)
	f.left, f.right = left, right

	-- The buttons share a line when it holds both, else the second goes under the first; then the columns.
	function f:Layout()
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		self.endRun:ClearAllPoints()
		local oneLine = w <= 0 or self.mark:GetWidth() + SP.sm + self.endRun:GetWidth() <= w
		if oneLine then
			self.endRun:SetPoint("LEFT", self.mark, "RIGHT", SP.sm, 0)
		else
			self.endRun:SetPoint("TOPLEFT", self.mark, "BOTTOMLEFT", 0, -SP.xs)
		end
		local below = oneLine and self.mark or self.endRun
		left:ClearAllPoints()
		right:ClearAllPoints()
		left:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -SP.xl)
		-- One under the other, each as tall as its rows, while that fits; side by side only when it does not (a raid's
		-- bosses) and the panel is wide enough. Before, short lists stood in two columns over an empty half page, or
		-- the objectives sat at the bottom far below the bosses.
		local head = 18 + SP.sm
		local form = ctx:ReadOnly() and 0 or (SZ.control + SP.sm)
		local bossH = head + math.max(1, #self.bosses.items) * SZ.row2
		local objH = head + form + math.max(1, #self.objectives.items) * SZ.row
		local room = h - ((self:GetTop() or 0) - (left:GetTop() or 0))
		self.stacked = w > 0 and (w < TWO_COLUMNS or bossH + SP.lg + objH <= room)
		if not self.stacked then
			left:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -SP.md, 0)
			right:SetPoint("TOPLEFT", left, "TOPRIGHT", 2 * SP.md, 0)
			right:SetPoint("BOTTOMRIGHT")
		else
			-- The bosses as tall as their rows, leaving the objectives at least their heading, the field and their rows
			-- (three at most; the rest scroll).
			local objMin = head + form + math.min(3, math.max(1, #self.objectives.items)) * SZ.row
			bossH = math.max(head + SZ.row2, math.min(bossH, room - objMin - SP.lg))
			left:SetPoint("RIGHT")
			left:SetHeight(bossH)
			right:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -SP.lg)
			right:SetPoint("BOTTOMRIGHT")
		end
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Layout()
	end)

	f.bossTitle = W.Heading(left, L["Bosses"], nil, true)
	f.bossTitle:SetPoint("TOPLEFT")
	-- Two lines a boss: the name gets the column's whole width ("Durgen Dirgehammer" was cut beside "not tracked"),
	-- the kills or "not tracked" under it.
	f.bosses = W.List(left, {
		rowHeight = SZ.row2,
		empty = L["Add bosses on the Bosses page."],
		create = function(row)
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("TOPLEFT", SP.sm + 8 + SP.sm, -6)
			row.text:SetPoint("RIGHT", -SP.sm, 0)
			row.dot = W.Dot(row, "dim")
			row.dot:SetPoint("RIGHT", row.text, "LEFT", -SP.sm, 0)
			row.meta = W.Text(row, "caption", "muted")
			row.meta:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -SP.xxs)
			row.meta:SetPoint("RIGHT", -SP.sm, 0)
		end,
		update = function(row, enc)
			local id = gameID(enc)
			local killed = id and Progress.IsKilledInRun(store(), id)
			row.dot:SetStatus(killed and "ok" or "dim")
			W.FitText(row.text, ns.Names.Encounter(enc))
			if id then
				row.meta:SetText(ns.Plural(Progress.KillsOf(store(), id), L["%d kill|%d kills"]))
			else
				row.meta:SetText(L["not tracked"])
			end
		end,
	})
	f.bosses:SetPoint("TOPLEFT", f.bossTitle, "BOTTOMLEFT", 0, -SP.sm)
	f.bosses:SetPoint("BOTTOMRIGHT")

	f.objTitle = W.Heading(right, L["Objectives"], nil, true)
	f.objTitle:SetPoint("TOPLEFT")
	f.reset = W.Button(right, L["Clear checkmarks"], "outline", function()
		local p = plan()
		if p then
			Progress.ResetObjectives(store(), p.id)
			f:Refresh()
		end
	end)
	f.reset:SetPoint("TOPRIGHT", 0, 4)
	f.reset.dpGround = "surface"
	W.SetTooltip(f.reset, L["Clear checkmarks"], L["Unticks every objective of this plan for this character."])
	-- Adds on Enter or the Add button only: leaving the field (a click elsewhere) keeps the text and adds nothing.
	f.newObjective = W.Input(right, {
		maxBytes = Schema.TEXT.short,
		placeholder = L["Add an objective and press Enter"],
		onSubmit = function(text)
			local p = plan()
			if p and text ~= "" and not ctx:ReadOnly() then
				Plan.AddObjective(p, text)
				f.newObjective:SetValue("")
				ctx:Changed("objectives")
			end
		end,
	})
	f.addObjective = W.Button(right, L["Add"], "outline", function()
		f.newObjective:Submit()
	end)
	f.newObjective:SetPoint("TOPLEFT", f.objTitle, "BOTTOMLEFT", 0, -SP.sm)
	f.newObjective:SetPoint("RIGHT", -(f.addObjective:GetWidth() + SP.sm), 0)
	f.addObjective:SetPoint("LEFT", f.newObjective, "RIGHT", SP.sm, 0)
	f.objectives = W.List(right, {
		rowHeight = SZ.row,
		empty = L["No objectives."],
		create = function(row)
			row.box = CreateFrame("Frame", nil, row)
			row.box:SetSize(16, 16)
			row.box:SetPoint("LEFT", SP.sm, 0)
			S.Surface(row.box, "hover", S.RADIUS.badge, "border")
			row.mark = row.box:CreateTexture(nil, "ARTWORK")
			S.Round(row.mark, S.RADIUS.badge)
			row.mark:SetPoint("TOPLEFT", 4, -4)
			row.mark:SetPoint("BOTTOMRIGHT", -4, 4)
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("LEFT", row.box, "RIGHT", SP.sm, 0)
			row.text:SetPoint("RIGHT", -SP.sm, 0)
		end,
		update = function(row, o)
			local done = Progress.IsObjectiveDone(store(), plan().id, o.id)
			S.Tint(row.mark, "ink")
			row.mark:SetShown(done)
			S.TextColor(row.text, done and "muted" or "ink")
			row.text:SetText(o.text)
		end,
		onClick = function(o, _, mouse, row)
			local p = plan()
			if mouse == "RightButton" then
				if not ctx:ReadOnly() then
					W.Menu(row, {
						{
							L["Delete"],
							function()
								Plan.RemoveObjective(p, o.id)
								ctx:Changed("objectives")
							end,
						},
					})
				end
				return
			end
			Progress.SetObjective(store(), p.id, o.id, not Progress.IsObjectiveDone(store(), p.id, o.id))
			f:Refresh()
		end,
	})

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		local sum = Progress.PlanSummary(store(), p, gameID)
		local text = string.format(L["Bosses %d/%d"], sum.bossesKilled, sum.bosses)
		if sum.objectives > 0 then
			text = text .. "  \226\128\162  " .. string.format(L["objectives %d/%d"], sum.objectivesDone, sum.objectives)
		end
		self.summary:SetText(text)
		local run = store().run
		if run then
			self.run:SetText(string.format(L["Current run: %s, started %s"], run.name ~= "" and run.name or "?",
				date and date("%H:%M", run.started) or ""))
		else
			self.run:SetText(L["No run in progress. A run starts when you enter an instance."])
		end
		self.bosses:SetItems(p.encounters, p.id)
		self.objectives:SetItems(p.objectives, p.id)
		local ro = ctx:ReadOnly()
		self.newObjective:SetShown(not ro)
		self.addObjective:SetShown(not ro)
		self.objectives:ClearAllPoints()
		if ro then
			self.objectives:SetPoint("TOPLEFT", self.objTitle, "BOTTOMLEFT", 0, -SP.sm)
		else
			self.objectives:SetPoint("TOPLEFT", self.newObjective, "BOTTOMLEFT", 0, -SP.sm)
		end
		self.objectives:SetPoint("BOTTOMRIGHT")
		self.reset:SetShown(sum.objectivesDone > 0)
		self:Layout()
	end
	return f
end
