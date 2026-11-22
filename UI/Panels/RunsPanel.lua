-- Runs section: the run recorder (Tracker/Recorder.lua, opt-in) for this plan's instance. Left: the switch, the
-- recorded runs (newest first) with their time and the difference to the best one. Right: the selected run, shown one
-- of three ways (the "Show" dropdown): its summary (bosses as splits against the best and the previous run, its pulls),
-- against the plan (Model/RunCompare.lua: planned and actual pulls between boss kills, where the run went off plan),
-- or side by side with another run. "Create plan from run", and the dungeon's quests from Questie when it is installed
-- (Data/Providers/Questie.lua).

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE
local RunLog, RunCompare = ns.RunLog, ns.RunCompare

local Panel = {}
ns.Panels.runs = Panel

local T, D = RunLog.FormatTime, RunLog.FormatDelta
local COL = 58 -- the compare table's value columns

local function when(run)
	return date and run.t and date("%Y-%m-%d %H:%M", run.t) or ""
end

-- A time difference: "-0:12", "+1:30", and "0:00" for none.
local function timeDelta(n)
	if not n then
		return ""
	end
	return n == 0 and T(0) or D(n)
end

-- true when a lower value is better and A's is lower, false when higher, nil when equal or unknown.
local function lowerIsBetter(delta)
	if not delta or delta == 0 then
		return nil
	end
	return delta < 0
end

local function countDelta(n)
	if not n then
		return ""
	end
	return n > 0 and ("+" .. n) or tostring(n)
end

-- What the plan's pulls are called in the overlay: "Pull 3: Searing Blade" (several when pulled together).
local function entryText(plan, entry)
	local names = {}
	for _, pull in ipairs(entry.pulls) do
		local i = ns.Plan.PullIndex(plan, pull.id) or 0
		names[#names + 1] = pull.name ~= "" and string.format(L["Pull %d: %s"], i, pull.name) or string.format(L["Pull %d"], i)
	end
	return table.concat(names, " + ")
end

local function bossName(plan, encId)
	local enc = encId and ns.Util.FindById(plan.encounters, encId)
	return enc and ns.Names.Encounter(enc) or L["Boss"]
end

-- How the overlay is computed for a plan in the UI (game IDs from the journal resolver, display names).
function Panel.CompareOptions(plan)
	return {
		idOf = ns.Journal.GameIdOf(plan),
		nameOf = function(enc)
			return ns.Names.Encounter(enc)
		end,
	}
end

-- What the Run pane says before this instance has a run: how to start recording, or, with recording on, that the next
-- run will show up (the check box above and the Settings panel both fire RECORDER_CHANGED, which redraws it).
function Panel.EmptyText(recording)
	if recording then
		return L["Recording is on. Your next run in this instance will appear here."]
	end
	return L["Turn on \"Record my runs\" and play this instance: each run shows up here."]
end

function Panel.Overlay(plan, run)
	return RunCompare.Overlay(plan, run, ns.Steps.Build(plan), Panel.CompareOptions(plan))
end

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local Recorder = ns.Recorder
	local selectedRun
	local view, compareRun = "run", nil -- "run" | "plan" | "compare"

	local function plan()
		return ctx:Plan()
	end
	local function key()
		return Recorder.KeyForPlan(plan())
	end
	local function store()
		return Recorder.Store()
	end
	local function select(run)
		selectedRun = run
		ctx.selectedRun = run -- Share > Advanced > Discord's run summary uses it
	end

	f.record = W.Check(f, L["Record my runs"], function(on)
		Recorder.SetEnabled(on)
	end)
	f.record:SetPoint("TOPLEFT")
	W.SetTooltip(f.record, L["Record my runs"],
		L["Records pulls (time, enemies, elites, deaths), boss kills and wipes in dungeons. No positions: the game hides them. Last 20 runs kept."])
	f.state = W.Text(f, "caption", "muted")
	-- Beside the check box, on its line (its top and bottom: the right edge alone sets no height).
	f.state:SetPoint("TOPLEFT", f.record, "TOPRIGHT", SP.lg, 0)
	f.state:SetPoint("BOTTOMLEFT", f.record, "BOTTOMRIGHT", SP.lg, 0)
	f.state:SetPoint("RIGHT")

	local COLUMNS_TOP = -(SZ.control + SP.md)
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", 0, COLUMNS_TOP)
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -SP.md, 0)
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", f, "TOP", SP.md, COLUMNS_TOP)
	right:SetPoint("BOTTOMRIGHT")

	f.runsTitle = W.Heading(left, L["Runs"], nil, true)
	f.runsTitle:SetPoint("TOPLEFT")
	f.best = W.Text(left, "caption", "gold")
	-- On the heading's line: its top is the column's top, its bottom the heading's (one anchor per edge).
	f.best:SetPoint("TOPRIGHT")
	f.best:SetPoint("BOTTOMLEFT", f.runsTitle, "BOTTOMRIGHT", SP.md, 0)
	f.best:SetJustifyH("RIGHT")

	f.clear = W.Button(left, L["Clear history"], "outline", function()
		local p = plan()
		W.ShowDialog({
			title = L["Clear history"],
			text = L["Remove the recorded runs of this instance? This cannot be undone."],
			buttons = {
				{
					L["Clear history"],
					function()
						Recorder.ClearForPlan(p)
						select(nil)
						f:Refresh()
					end,
				},
				{ L["Cancel"] },
			},
		})
	end)
	f.clear:SetPoint("BOTTOMLEFT")
	f.finish = W.Button(left, L["End run"], "outline", function()
		Recorder.FinishRun()
		f:Refresh()
	end)
	f.finish:SetPoint("LEFT", f.clear, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.finish, L["End run"], L["Finish the run being recorded now (it also ends when you enter another instance)."])

	f.runs = W.List(left, {
		rowHeight = SZ.row,
		empty = L["No recorded runs of this instance yet."],
		create = function(row)
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("LEFT", SP.sm, 0)
			row.meta = W.Text(row, "caption", "muted")
			row.meta:SetPoint("RIGHT", -SP.sm, 0)
			row.meta:SetJustifyH("RIGHT")
			row.text:SetPoint("RIGHT", row.meta, "LEFT", -SP.sm, 0)
		end,
		update = function(row, run)
			local s = RunLog.Summary(run)
			row.text:SetText((run.done and "" or (L["Recording"] .. " • ")) .. when(run)
				.. (Recorder.WingUnknown(run, plan()) and (" • " .. L["wing unknown"]) or ""))
			local best = RunLog.Best(store(), run.k, run)
			local delta = best.total and run.done and (" " .. D(s.duration - best.total)) or ""
			row.meta:SetText(T(s.duration) .. " • " .. ns.Plural(s.pulls, L["%d pull|%d pulls"]) .. " • "
				.. ns.Plural(s.bosses, L["%d boss|%d bosses"]) .. delta)
		end,
		isSelected = function(run)
			return run == selectedRun
		end,
		onClick = function(run)
			select(run)
			if compareRun == run then
				compareRun = nil
			end
			f:Refresh()
		end,
	})
	f.runs:SetPoint("TOPLEFT", f.runsTitle, "BOTTOMLEFT", 0, -SP.sm)
	f.runs:SetPoint("BOTTOMRIGHT", 0, SZ.control + SP.sm)

	-- The selected run.
	f.detailTitle = W.Heading(right, L["Run"], nil, true)
	f.detailTitle:SetPoint("TOPLEFT")
	f.create = W.Button(right, L["Create plan from run"], "primary", function()
		if selectedRun then
			local p = Recorder.CreatePlan(selectedRun, plan())
			if p then
				ns:Print(string.format(L["Created the plan \"%s\". Place its pulls and bosses on the map."], p.name))
				ns.UI.SelectPlan(p.id, true)
				ns.UI.Show("map")
			end
		end
	end)
	f.create:SetPoint("TOPRIGHT", 0, 4)
	W.SetTooltip(f.create, L["Create plan from run"],
		L["This run's pulls in order and its bosses in kill order, as a new plan. Place them on the map with the editor."])

	-- How to show it: this run, against the plan, or beside another run.
	local runsShown = {}
	f.show = W.Dropdown(right, {
		width = 200,
		options = function()
			local out = { { text = L["This run"], value = "run" }, { text = L["Against the plan"], value = "plan" } }
			for _, run in ipairs(runsShown) do
				if run ~= selectedRun then
					out[#out + 1] = { text = string.format(L["Compare with %s"], when(run)), value = run }
				end
			end
			return out
		end,
		get = function()
			return view == "compare" and compareRun or view
		end,
		set = function(v)
			if type(v) == "table" then
				f.compareWith(v)
			else
				f.showView(v)
			end
		end,
	})
	function f.showView(v)
		view, compareRun = v, nil
		f:Refresh()
	end
	function f.compareWith(run)
		view, compareRun = "compare", run
		f:Refresh()
	end
	f.show:SetPoint("TOPLEFT", f.detailTitle, "BOTTOMLEFT", 0, -SP.sm)
	f.show:SetPoint("RIGHT")
	W.SetTooltip(f.show, L["Show"], L["This run's times and pulls, the run against the plan, or two runs side by side."])

	f.detail = W.Document(right)
	f.detail:SetPoint("TOPLEFT", f.show, "BOTTOMLEFT", 0, -SP.sm)
	f.detail:SetPoint("BOTTOMRIGHT")

	-- Two runs side by side: a header line, then rows "what | this run | the other | difference".
	local cmp = CreateFrame("Frame", nil, right)
	cmp:SetPoint("TOPLEFT", f.show, "BOTTOMLEFT", 0, -SP.sm)
	cmp:SetPoint("BOTTOMRIGHT")
	f.compare = cmp
	local function columns(row, font)
		row.delta = W.Text(row, font or "caption", "muted")
		row.delta:SetPoint("RIGHT", -SP.sm, 0)
		row.delta:SetWidth(COL)
		row.delta:SetJustifyH("RIGHT")
		row.b = W.Text(row, font or "body", "ink")
		row.b:SetPoint("RIGHT", row.delta, "LEFT", -SP.xs, 0)
		row.b:SetWidth(COL)
		row.b:SetJustifyH("RIGHT")
		row.a = W.Text(row, font or "body", "ink")
		row.a:SetPoint("RIGHT", row.b, "LEFT", -SP.xs, 0)
		row.a:SetWidth(COL)
		row.a:SetJustifyH("RIGHT")
		row.label = W.Text(row, font or "body", "ink")
		row.label:SetPoint("LEFT", SP.sm, 0)
		row.label:SetPoint("RIGHT", row.a, "LEFT", -SP.xs, 0)
	end
	cmp.head = CreateFrame("Frame", nil, cmp)
	cmp.head:SetPoint("TOPLEFT")
	cmp.head:SetPoint("RIGHT", -SP.md, 0)
	cmp.head:SetHeight(SZ.small)
	columns(cmp.head, "caption")
	for _, fs in ipairs({ cmp.head.label, cmp.head.a, cmp.head.b, cmp.head.delta }) do
		S.TextColor(fs, "gold")
	end
	cmp.list = W.List(cmp, {
		rowHeight = SZ.row,
		empty = L["Pick a run to compare with."],
		create = function(row)
			columns(row)
		end,
		update = function(row, item)
			W.FitText(row.label, item.label)
			S.TextColor(row.label, item.heading and "gold" or "ink")
			row.a:SetText(item.a or "")
			row.b:SetText(item.b or "")
			row.delta:SetText(item.delta or "")
			S.TextColor(row.delta, item.better == true and "ok" or item.better == false and "warning" or "muted")
		end,
	})
	cmp.list:SetPoint("TOPLEFT", cmp.head, "BOTTOMLEFT", 0, -SP.xxs)
	cmp.list:SetPoint("BOTTOMRIGHT")

	local function showRun(doc, run)
		local s = RunLog.Summary(run)
		doc:Add("title", T(s.duration))
		-- What the client cannot tell says so instead of showing a zero.
		local deaths = s.deaths and ns.Plural(s.deaths, L["%d death|%d deaths"]) or L["deaths not available"]
		doc:Add("muted", table.concat({ ns.Plural(s.pulls, L["%d pull|%d pulls"]), ns.Plural(s.bosses, L["%d boss|%d bosses"]),
			ns.Plural(s.wipes, L["%d wipe|%d wipes"]), deaths, string.format(L["%s in combat"], T(s.fighting)) }, " • "))
		if Recorder.WingUnknown(run, plan()) then
			doc:Add("muted", L["Recorded without knowing the wing: it may be a run of another wing of this instance."])
		end
		local splits, best, prev = RunCompare.Splits(store(), run)
		if best.total then
			doc:Add("muted", string.format(L["Best: %s over %s"], T(best.total), ns.Plural(best.runs, L["%d run|%d runs"])))
		end
		if prev then
			doc:Add("muted", string.format(L["Previous run: %s (%s)"], T(RunLog.Duration(prev)), D(s.duration - RunLog.Duration(prev))))
		end
		if #splits > 0 then
			doc:Add("heading", L["Bosses"])
			for i, sp in ipairs(splits) do
				local line = string.format("%d. %s  %s", i, sp.name or "?", T(sp.at))
				local cmpText = {}
				if sp.delta then
					cmpText[#cmpText + 1] = string.format(L["best %s"], D(sp.delta))
				end
				if sp.prevDelta then
					cmpText[#cmpText + 1] = string.format(L["previous %s"], D(sp.prevDelta))
				end
				if #cmpText > 0 then
					line = line .. "  (" .. table.concat(cmpText, " • ") .. ")"
				end
				doc:Add("text", line)
			end
		end
		if #run.p > 0 then
			doc:Add("heading", L["Pulls"])
			for i, p in ipairs(run.p) do
				local line = string.format("%d. %s  %s", i, T(p.u or 0), RunLog.PullText(p, L, ns.Plural))
				if p.z then
					line = line .. " • " .. p.z
				end
				if p.nm then
					line = line .. " • " .. table.concat(p.nm, ", ")
				end
				if p.w then
					line = line .. " • " .. L["wipe"]
				end
				doc:Add("text", line)
			end
		end
	end

	-- The run against the plan: pulls between boss kills, planned against actual, paired by order.
	local function showOverlay(doc, run)
		local p = plan()
		local ov = Panel.Overlay(p, run)
		local name = function(encId)
			return bossName(p, encId)
		end
		doc:Add("title", ns.Plural(ov.actual, L["%d pull, plan %d|%d pulls, plan %d"], ov.planned))
		doc:Add("muted", string.format(L["Bosses: %d of %d"], ov.bossesKilled, ov.bossesPlanned))
		if #ov.divergences > 0 then
			doc:Add("heading", L["Off plan"])
			for _, d in ipairs(ov.divergences) do
				doc:Add("text", ns.Discord.DivergenceText(d, name))
			end
		elseif ov.actual + ov.bossesKilled > 0 then
			doc:Add("muted", L["On plan so far."])
		end
		for _, seg in ipairs(ov.segments) do
			-- A boss straight after the one before it (nothing planned, nothing pulled) needs no heading.
			if #seg.planned + #seg.actual + (seg.attempts or 0) > 0 or (seg.boss and seg.state ~= "done") then
				local where = seg.boss and string.format(L["Before %s"], name(seg.boss))
					or (seg.kill and string.format(L["Before %s"], seg.kill.n or "?") or L["After the last boss"])
				doc:Add("heading", where)
				local line = ns.Plural(#seg.actual, L["%d pull, plan %d|%d pulls, plan %d"], #seg.planned)
				if seg.delta ~= 0 then
					line = line .. " (" .. countDelta(seg.delta) .. ")"
				end
				if seg.state == "current" and not run.done then
					line = line .. " • " .. L["now"]
				elseif seg.state ~= "done" then
					line = line .. " • " .. L["not reached"]
				end
				if (seg.attempts or 0) > 0 then
					line = line .. " • " .. ns.Plural(seg.attempts, L["%d wipe on the boss|%d wipes on the boss"])
				end
				doc:Add("muted", line)
				for i, row in ipairs(seg.rows) do
					local actual = row.actual and (RunLog.PullText(row.actual.pull, L, ns.Plural) .. ", " .. T(row.actual.pull.u or 0))
					if row.kind == "pair" then
						doc:Add("text", string.format("%d. %s • %s", i, entryText(p, row.planned), actual))
					elseif row.kind == "extra" then
						doc:Add("text", string.format(L["+ extra pull: %s"], actual))
					elseif seg.state == "done" or run.done then
						doc:Add("text", string.format(L["- skipped: %s"], entryText(p, row.planned)))
					else
						doc:Add("muted", string.format(L["next: %s"], entryText(p, row.planned)))
					end
				end
			end
		end
		doc:Add("muted", L["Pulls are paired by order between boss kills: the game does not say which pack was pulled, so two packs pulled together count as one."])
	end

	local function compareItems(a, b)
		local pair = RunCompare.Pair(a, b)
		local items = {}
		local LABEL = {
			duration = L["Time"],
			pulls = L["Pulls"],
			bosses = L["Bosses"],
			wipes = L["Wipes"],
			deaths = L["Deaths"],
			fighting = L["In combat"],
			enemies = L["Enemies seen"],
		}
		local TIME = { duration = true, fighting = true }
		local LOWER_BETTER = { duration = true, fighting = true, wipes = true, deaths = true }
		for _, r in ipairs(pair.summary) do
			local fmt = TIME[r.id] and T or tostring
			items[#items + 1] = {
				label = LABEL[r.id],
				a = r.a and fmt(r.a) or "-",
				b = r.b and fmt(r.b) or "-",
				delta = TIME[r.id] and timeDelta(r.delta) or countDelta(r.delta),
				-- Less time, fewer wipes and deaths is better; pulls and enemies are neither.
				better = LOWER_BETTER[r.id] and lowerIsBetter(r.delta),
			}
		end
		if #pair.bosses > 0 then
			items[#items + 1] = { label = L["Bosses"], heading = true }
			for _, r in ipairs(pair.bosses) do
				items[#items + 1] = { label = r.name or "?", a = r.a and T(r.a) or "-", b = r.b and T(r.b) or "-",
					delta = timeDelta(r.delta), better = lowerIsBetter(r.delta) }
			end
		end
		if #pair.stretches > 0 then
			items[#items + 1] = { label = L["Pulls before bosses"], heading = true }
			for _, r in ipairs(pair.stretches) do
				items[#items + 1] = { label = r.name and string.format(L["Before %s"], r.name) or L["After the last boss"],
					a = tostring(r.a), b = tostring(r.b), delta = countDelta(r.delta) }
			end
		end
		return items
	end

	local function showQuests(doc, p)
		local q = ns.Providers.Adapter("questie")
		if not (q and ns.Providers.Get("questie")) then
			return
		end
		local list, done = ns.Providers.Call("questie", "Quests", p, function()
			if f:IsVisible() then
				f:Refresh()
			end
		end)
		doc:Add("heading", string.format(L["Quests (%s)"], q.title))
		if not done then
			doc:Add("muted", L["Looking up quests..."])
		elseif not list or #list == 0 then
			doc:Add("muted", L["None filed under this instance."])
		else
			for _, quest in ipairs(list) do
				local line = (quest.level and ("[" .. quest.level .. "] ") or "") .. quest.name
				if quest.starter then
					line = line .. " • " .. string.format(L["from %s"], quest.starter)
				end
				doc:Add("text", line)
			end
		end
	end

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		self.record:SetChecked(Recorder.Enabled())
		local st = store()
		local k = key()
		local runs = Recorder.RunsForPlan(p)
		local cur = st and st.current
		runsShown = runs
		if selectedRun and not ns.Util.IndexOf(runs, selectedRun) then
			select(nil)
		end
		select(selectedRun or runs[1])
		if compareRun and (compareRun == selectedRun or not ns.Util.IndexOf(runs, compareRun)) then
			view, compareRun = "run", nil
		end
		if cur and Recorder.Enabled() then
			self.state:SetText(string.format(L["Recording: %s, pull %d"], cur.n ~= "" and cur.n or "?", #cur.p))
		else
			self.state:SetText(Recorder.Enabled() and L["Recording starts when you enter a dungeon."] or L["Off"])
		end
		local best = st and k and RunLog.Best(st, k)
		self.best:SetText(best and best.total and string.format(L["Best %s"], T(best.total)) or "")
		self.runs:SetItems(runs)
		self.finish:SetShown(cur ~= nil)
		self.create:SetShown(selectedRun ~= nil and #selectedRun.p + #selectedRun.b > 0 and not ns.DB.IsReadOnly())
		self.show:SetShown(selectedRun ~= nil)
		self.show:Refresh()
		local comparing = selectedRun ~= nil and view == "compare" and compareRun ~= nil
		self.compare:SetShown(comparing)
		self.detail:SetShown(not comparing)
		if comparing then
			-- A is the selected run, B the one it is compared with; the difference is A minus B.
			W.FitText(self.compare.head.label, "B: " .. when(compareRun))
			self.compare.head.a:SetText("A")
			self.compare.head.b:SetText("B")
			self.compare.head.delta:SetText("A - B")
			self.compare.list:SetItems(compareItems(selectedRun, compareRun))
			return
		end
		local doc = self.detail
		doc:Begin()
		if selectedRun and view == "plan" then
			showOverlay(doc, selectedRun)
		elseif selectedRun then
			showRun(doc, selectedRun)
		else
			doc:Add("muted", Panel.EmptyText(Recorder.Enabled()))
		end
		showQuests(doc, p)
		doc:Finish()
	end

	ns:On("RECORDER_CHANGED", f, function()
		if f:IsVisible() then
			f:Refresh()
		end
	end)
	return f
end
