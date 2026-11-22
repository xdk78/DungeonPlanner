-- Regressions from the code review before the first in-game test: hostile text that took quadratic time, sharing
-- (late accepts, acks from strangers), saved data (quarantine, newer data, damaged stores), ids, run comparison, steps.
local T = ...
local ns, mock = T.ns, T.mock
local Util, Transfer, DB = ns.Util, ns.Transfer, ns.DB

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("Review: cleaning hostile text takes linear time", function()
	local n = 150000
	local cases = {
		spaces = "x" .. string.rep(" ", n) .. "x" .. string.rep(" ", n),
		textures = string.rep("|T", n),
		links = string.rep("|H", n) .. "|h",
		atlases = string.rep("|A", n),
	}
	for name, text in pairs(cases) do
		local t0 = os.clock()
		local single = Util.CleanText(text, 64)
		local multi = Util.CleanText(text, 3000, true)
		T.ok(os.clock() - t0 < 2, name .. ": cleaning took " .. (os.clock() - t0) .. " s")
		T.ok(#single <= 64 and #multi <= 3000, name .. ": cut to the limit")
		T.ok(not multi:find("|", 1, true), name .. ": no pipe left")
	end
	T.eq(Util.Trim("  a b \n"), "a b")
	T.eq(Util.Trim("   "), "")
	T.eq(Util.Trim(""), "")
	T.eq(Util.StripEscapes("|cff00ff00|Hitem:19019:0|h[Thunderfury]|h|r and |TInterface\\Icons\\x:16|t."), "[Thunderfury] and .")
	T.eq(Util.StripEscapes("a |Aatlas:16:16|a b |Kq1|k c"), "a  b  c")
end)

T.case("Review: a group member who accepts after the payload went out still gets it", function()
	local data = "!DP2!" .. string.rep("a", 50)
	local out = Transfer.NewOutgoing(data, "plan", "Plan", "PARTY", nil, 0)
	Transfer.StepOutgoing(out, { type = "accept", from = "Anna" }, 1)
	local fx = Transfer.StepOutgoing(out, { type = "tick" }, 1 + Transfer.GATHER)
	T.eq(fx[1][1], "sendPayload")
	T.eq(out.state, "sending")
	-- Bob was in combat: his prompt came later, and so does his accept.
	fx = Transfer.StepOutgoing(out, { type = "accept", from = "Bob" }, 20)
	T.eq(fx[1] and fx[1][1], "sendPayloadTo", "the late accepter is sent the plan")
	T.eq(fx[1][4], "Bob")
	T.eq(Transfer.Parse(fx[1][3]).data, data)
	T.eq(#Transfer.StepOutgoing(out, { type = "accept", from = "Bob" }, 21), 0, "once per member")
	T.eq(#Transfer.StepOutgoing(out, { type = "accept", from = "Anna" }, 21), 0, "not again to who had it")
	Transfer.StepOutgoing(out, { type = "sent" }, 22)
	T.eq(out.state, "done")
	fx = Transfer.StepOutgoing(out, { type = "accept", from = "Cara" }, 30)
	T.eq(fx[1] and fx[1][1], "sendPayloadTo", "also after the group send finished")
	-- A whispered offer has one receiver.
	local w = Transfer.NewOutgoing(data, "plan", "Plan", "WHISPER", "Anna", 0)
	Transfer.StepOutgoing(w, { type = "accept", from = "Anna" }, 1)
	T.eq(#Transfer.StepOutgoing(w, { type = "accept", from = "Mallory" }, 2), 0)
end)

T.case("Review: acks count only from those the plan was offered to", function()
	boot()
	local Comm = ns.Comm
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function() end
	mock.inGroup = true
	mock.units = { party1 = { name = "Anna" } }
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "Acked", instance = { name = "Ack Keep", kind = "dungeon" } }))
	plan.updated = 5000
	local store = Comm.AcksStore()
	local function has(name)
		local rec = store.plans[plan.id]
		return rec and rec.members[name] and rec.members[name].v or nil
	end
	-- A stranger's whisper about a plan we have (they only need its id) is not our group's word.
	Comm.OnMessage(ns.prefix, "K^zz7^" .. plan.id .. "^5000", "WHISPER", "Mallory")
	T.eq(has("Mallory"), nil, "a stranger is not recorded")
	-- A group member, for a transfer this session no longer knows: taken, but never a version from the future.
	Comm.OnMessage(ns.prefix, "K^zz8^" .. plan.id .. "^999999999999", "WHISPER", "Anna")
	T.eq(has("Anna"), nil, "a version the plan never had is refused")
	Comm.OnMessage(ns.prefix, "K^zz8^" .. plan.id .. "^5000", "WHISPER", "Anna")
	T.eq(has("Anna"), 5000)
	-- A whispered offer: only its target's ack counts.
	local transfer = assert(Comm.SharePlan(plan, "WHISPER", "Bob"))
	Comm.OnMessage(ns.prefix, "K^" .. transfer.tid .. "^" .. plan.id .. "^5000", "WHISPER", "Mallory")
	T.eq(has("Mallory"), nil)
	Comm.OnMessage(ns.prefix, "K^" .. transfer.tid .. "^" .. plan.id .. "^5000", "WHISPER", "Bob")
	T.eq(has("Bob"), 5000)
	Comm.Cancel(transfer)
	-- A name typed in another case is the same receiver: the accept counts and the plan is sent.
	local typed = assert(Comm.SharePlan(plan, "WHISPER", "bob"))
	Comm.OnMessage(ns.prefix, "A^" .. typed.tid, "WHISPER", "Bob")
	T.ok(typed.state == "sending" or typed.state == "done", "accepted: " .. typed.state)
	T.eq(typed.target, "Bob")
	Comm.Cancel(typed)
	mock.inGroup, mock.units = false, {}
	ns.addon.SendCommMessage = realSend
	ns.DB.DeletePlan(plan.id)
end)

T.case("Review: a pushed page cannot inflate past its own limit", function()
	local big = ns.Codec.EncodeNote({ title = "Big", text = string.rep("a", 200000) })
	T.ok(#big < Transfer.MAX_NOTE, "a small string on the wire")
	local page, why = ns.Codec.DecodeNote(big)
	T.eq(page, nil, "refused before it is deserialized")
	T.ok(tostring(why):find("too large", 1, true), tostring(why))
	T.ok(ns.Codec.DecodeNote(ns.Codec.EncodeNote({ title = "Ok", text = string.rep("b", 3000) })), "a full page still decodes")
end)

T.case("Review: every unreadable plan is set aside, however many", function()
	local global = { schema = DB.SCHEMA, plans = {} }
	for i = 1, DB.MAX_QUARANTINE + 5 do
		global.plans["bad" .. i] = "junk " .. i
	end
	local info = DB.LoadGlobal(global)
	T.eq(info.quarantined, DB.MAX_QUARANTINE + 5)
	T.eq(#global.quarantine, DB.MAX_QUARANTINE + 5, "none dropped")
end)

T.case("Review: migration 1 keeps plans stored by id beside the old list; a damaged schema number is repaired", function()
	local global = { plans = { { id = "pA", name = "A" }, pB = { name = "B" } } }
	DB.LoadGlobal(global)
	T.ok(global.plans.pA and global.plans.pB, "both kept")
	T.eq(global.quarantine[1], nil)
	local g2 = { schema = 2.5, plans = { pC = { name = "C" } } }
	local info = DB.LoadGlobal(g2)
	T.eq(g2.schema, DB.SCHEMA, "a fractional schema does not end above the current one")
	T.eq(info.readOnly, false)
	local g3 = { schema = -3, plans = {} }
	DB.LoadGlobal(g3)
	T.eq(g3.schema, DB.SCHEMA)
end)

T.case("Review: newer saved data is shown through validated copies and never touched", function()
	local raw = { schema = DB.SCHEMA + 1, plans = { pOk = { name = "From the future", markers = "new shape", extra = { 1 } },
		pBad = "also new", [7] = { name = "odd key" } } }
	local view = DB.ReadOnlyPlans(raw)
	T.eq(view.pOk.name, "From the future")
	T.eq(view.pOk.id, "pOk")
	T.eq(type(view.pOk.markers), "table", "validated, so the UI can read it")
	T.eq(view.pBad, nil)
	T.eq(view[7], nil)
	T.eq(raw.plans.pOk.markers, "new shape", "the stored plan is as it was")
	T.eq(raw.plans.pOk.extra[1], 1)
	T.eq(raw.plans.pBad, "also new")
	T.eq(next(DB.ReadOnlyPlans({ schema = 99, plans = "not a table" })), nil)
end)

T.case("Review: an imported plan cannot push ids past what a saved plan may hold", function()
	local raw = { name = "Ids", instance = { name = "X" }, markers = { { id = "m99999999999", x = 0.5, y = 0.5 },
		{ id = "m7", x = 0.1, y = 0.1 } } }
	local _, plan, report = ns.Codec.Decode(ns.Codec.Encode("plan", raw))
	T.eq(#plan.markers, 1, "the marker with the huge id is dropped on import")
	T.eq(report.dropped.markers, 1)
	local added = ns.Plan.AddMarker(plan, 1, 0.2, 0.2, "pack")
	local again = ns.Validate.Plan(Util.DeepCopy(plan))
	T.ok(Util.FindById(again.markers, added.id), "a marker added after the import survives the next load")
	-- Saved plans keep whatever ids they have.
	local saved = ns.Validate.Plan({ name = "Saved", markers = { { id = "m99999999999", x = 0.5, y = 0.5 } } })
	T.eq(#saved.markers, 1)
end)

T.case("Review: damaged progress and recorder stores are repaired, not fatal", function()
	local P, RunLog = ns.Progress, ns.RunLog
	local store = P.Normalize({ run = { key = "1", started = 1 }, kills = { ["5:1"] = true } })
	P.RecordKill(store, 5, 1, "Boss", 100)
	P.EnterInstance(store, "1", "Keep", 1, 200)
	T.ok(not P.IsKilledInRun(store, 6))
	local rs = RunLog.Normalize({ current = { k = "1", p = {} }, runs = { ["1"] = { { k = "1", t = 5, p = {} }, { p = {}, b = {} },
		{ k = "1", t = 9, p = { "junk" }, b = {} }, { k = "1", t = 10, p = { { s = 1, u = 2, c = 1 } }, b = { { i = 3, a = 4 } } } } } })
	T.eq(rs.current, nil, "a run without its start time is dropped")
	T.eq(#rs.runs["1"], 2, "runs without a key or with junk pulls are dropped")
	T.ok(type(rs.runs["1"][1].b) == "table", "a missing kill list is filled")
	T.ok(ns.RunCompare.Pair(rs.runs["1"][1], rs.runs["1"][2]))
	RunLog.Enter(rs, "1", "Keep", 1, 1000)
end)

T.case("Review: a boss wipe is a boss attempt even when no boss-level enemy was seen", function()
	local plan = ns.Validate.Plan({ name = "t", instance = { name = "X" }, floors = { { name = "F" } },
		pulls = { { id = "u1", name = "trash" } }, encounters = { { id = "e1", name = "Edwin VanCleef", dungeonEncounterID = 1144 } } })
	local RunLog = ns.RunLog
	local store = RunLog.NewStore()
	local run = RunLog.Enter(store, "36", "Deadmines", 1, 1000)
	local function pull(t0, t1, units, during)
		RunLog.PullStart(run, t0)
		RunLog.Observe(run, units)
		if during then
			during()
		end
		RunLog.PullEnd(run, t1, 0, false)
	end
	pull(1010, 1040, { { level = 19, class = "elite" }, { level = 19, class = "normal" } })
	pull(1100, 1160, { { level = 21, class = "elite" } }, function()
		RunLog.BossWipe(run, 1150)
	end)
	pull(1300, 1400, { { level = 21, class = "elite" } }, function()
		RunLog.BossKill(run, 1144, "Edwin VanCleef", 1390)
	end)
	local seg = ns.RunCompare.Overlay(plan, run, ns.Steps.Build(plan)).segments[1]
	T.eq(#seg.actual, 1, "one trash pull before the boss")
	T.eq(seg.attempts, 1, "the wipe is an attempt")
	T.eq(seg.delta, 0)
end)

T.case("Review: several objectives of one boss keep their order in the steps", function()
	local plan = ns.Validate.Plan({ name = "t", instance = { name = "X" }, floors = { { name = "F" } },
		encounters = { { id = "e1", name = "Boss" } },
		objectives = { { id = "o1", text = "first", encounter = "e1" }, { id = "o2", text = "second", encounter = "e1" },
			{ id = "o3", text = "third", encounter = "e1" } } })
	local order = {}
	for _, step in ipairs(ns.Steps.Build(plan)) do
		if step.kind == "objective" then
			order[#order + 1] = step.note
		end
	end
	T.eq(table.concat(order, " "), "first second third")
end)

-- The window ---------------------------------------------------------------------------------------------------------------

local function page()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	return _G.DungeonPlannerMainFrame.instancePage
end

local function testEntry()
	return ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
end

-- The mock's edit boxes never hold the focus; give one the game's behaviour (ClearFocus reports the focus loss).
local function focus(edit)
	local focused = true
	edit.HasFocus = function()
		return focused
	end
	edit.ClearFocus = function(self)
		if focused then
			focused = false
			mock.FireScript(self, "OnEditFocusLost")
		end
	end
	mock.FireScript(edit, "OnEditFocusGained")
end

T.case("Review: the game's scroll bar keeps its own Update, so its thumb is laid out", function()
	boot()
	local W = ns.Widgets
	local list = W.List(UIParent, { rowHeight = 20, create = function() end, update = function() end })
	list:SetHeight(200)
	local items = {}
	for i = 1, 40 do
		items[i] = { i }
	end
	list:SetItems(items)
	local bar = list.thumb
	T.ok(bar.dpNative, "the game's bar")
	T.ok(bar._updates > 0, "the bar's own Update ran")
	T.ok(bar._updates < 20, "and did not recurse (" .. bar._updates .. " calls)")
	T.eq(bar._thumbShown, true, "the thumb is shown")
	local area = W.ScrollArea(UIParent)
	area:SetSize(200, 100)
	area:SetContentHeight(400)
	area.thumb:SetVisibleExtentPercentage(0.25)
	T.eq(area.thumb._thumbShown, true, "a scroll area's bar lays out its thumb too")
end)

T.case("Review: text typed for one pull is not written into the pull clicked next", function()
	page()
	local plan = ns.DB.AddPlan(ns.Validate.Plan({ name = "P", instance = { name = "Keep", kind = "dungeon" },
		floors = { { name = "F" } }, pulls = { { id = "u1", name = "Alpha" }, { id = "u2", name = "Beta" } } }))
	ns.UI.SelectPlan(plan.id, true)
	local f = ns.Panels.pulls.Create(UIParent, ns.UI.ctx)
	f:SetSize(800, 500)
	f:Refresh()
	local edit = f.editor.name.edit
	focus(edit)
	edit:SetText("Typed for Alpha")
	local rowB = f.list.rows[2]
	mock.Click(rowB)
	edit:ClearFocus()
	T.eq(plan.pulls[2].name, "Beta", "the second pull keeps its name")
	T.eq(plan.pulls[1].name, "Typed for Alpha", "the typed name went to the pull it was typed for")
	ns.DB.DeletePlan(plan.id)
end)

T.case("Review: a page refresh keeps the notes being typed", function()
	local p = page()
	local plan = ns.Home.CreatePlan("dungeon", "Scratch notes", testEntry())
	ns.UI.SelectTab("plan")
	local edit = p.panels.plan.notes.notes.edit
	focus(edit)
	edit:SetText("Half a page of notes typed so far")
	ns:Fire("PROGRESS_CHANGED")
	T.eq(edit:GetText(), "Half a page of notes typed so far", "still in the field")
	edit:ClearFocus()
	T.eq(plan.notes, "Half a page of notes typed so far")
	ns.DB.DeletePlan(plan.id)
end)

T.case("Review: Escape in the home search clears the filter with the text", function()
	boot()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.GoHome()
	local home = ns.UI.Frame().home
	local edit = home.search.edit
	edit:SetText("dead")
	mock.FireScript(edit, "OnTextChanged", true)
	T.eq(ns.UI.ctx.search, "dead")
	mock.FireScript(edit, "OnEscapePressed")
	T.eq(ns.UI.ctx.search or "", "", "the list is no longer filtered")
end)

T.case("Review: an edit on a provider's map keeps the zoom and pan", function()
	local p = page()
	mock.InstallProviders()
	ns.db.settings.preferProviderMaps = true -- this case is about another addon's map (Data/MinimapArt.lua)
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	local realNow, clock = ns.Now, 1000
	ns.Now = function()
		return clock
	end
	local copy = ns.DB.AddPlan(ns.Plan.Duplicate(ns.Bundled.Get("b:hall-of-thanes")))
	ns.UI.SelectPlan(copy.id)
	ns.UI.SelectTab("map")
	local map = p.panels.map
	local view = map.canvas
	map:Refresh()
	T.ok(view.provided, "a provider's map is drawn")
	view.zoom, view.ox, view.oy = 4, -300, -200
	view:Layout()
	local zoom, ox = view.zoom, view.ox
	clock = clock + 1
	ns.Plan.AddMarker(copy, 1, 0.4, 0.4, "pack")
	ns.UI.ctx:Changed("markers")
	T.eq(view.zoom, zoom, "zoom kept")
	T.eq(view.ox, ox, "pan kept")
	ns.Now = realNow
	ns.DB.DeletePlan(copy.id)
	mock.RemoveProviders()
	ns.db.settings.preferProviderMaps = nil
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
end)

T.case("Review: map presses: one drag at a time, the readout survives a click, a still pointer redraws nothing", function()
	local p = page()
	local plan = ns.Home.CreatePlan("dungeon", "Scratch map", testEntry())
	ns.UI.SelectTab("map")
	local map = p.panels.map
	local ctx, view = ns.UI.ctx, map.canvas
	view:SetSize(900, 600)
	-- An eraser stroke interrupted by the other button still reports what it removed (one undo step).
	ctx.tool, ctx.drawTool = "draw", "line"
	map:Refresh()
	T.ok(ns.Drawing.Add(plan, 1, "line", { 0.2, 0.5, 0.8, 0.5 }, { color = 1, width = 2 }))
	ctx:Changed("drawings")
	local changes, realChanged = 0, ctx.Changed
	ctx.Changed = function(...)
		changes = changes + 1
		return realChanged(...)
	end
	ctx.drawTool = "erase"
	map:Refresh()
	local realCursor = view.CursorPosition
	view.CursorPosition = function()
		return 0.5, 0.5
	end
	mock.FireScript(view, "OnMouseDown", "LeftButton")
	mock.FireScript(view, "OnMouseDown", "RightButton")
	mock.FireScript(view, "OnMouseUp", "RightButton")
	mock.FireScript(view, "OnMouseUp", "LeftButton")
	T.eq(ns.Drawing.Count(plan, 1), 0, "erased")
	T.eq(changes, 1, "and reported once")
	T.eq(view.drawErase, nil)
	ctx.Changed = realChanged
	view.CursorPosition = realCursor
	ctx.tool = "select"
	map:Refresh()
	-- After a click the coordinate readout keeps updating while the pointer stays over the map.
	ns.db.settings.showCoordinates = true
	mock.Hover(view)
	T.ok(view:GetScript("OnUpdate"), "hovering updates the readout")
	mock.FireScript(view, "OnMouseDown", "LeftButton")
	mock.FireScript(view, "OnMouseUp", "LeftButton")
	T.ok(view:GetScript("OnUpdate"), "also after a click")
	mock.Leave(view)
	-- A held button with a still pointer: no redraw.
	mock.SetCursor(100, 100)
	mock.SetMouseButtonDown("LeftButton", true)
	mock.FireScript(view, "OnMouseDown", "LeftButton")
	mock.SetCursor(140, 100)
	mock.FireScript(view, "OnUpdate", 0.016)
	local redraws, realDraw, moves, realMove = 0, view.DrawContent, 0, view.MoveCanvas
	view.DrawContent = function(...)
		redraws = redraws + 1
		return realDraw(...)
	end
	view.MoveCanvas = function(...)
		moves = moves + 1
		return realMove(...)
	end
	for _ = 1, 30 do
		mock.FireScript(view, "OnUpdate", 0.016)
	end
	T.eq(redraws + moves, 0, "nothing moved, nothing redrawn")
	mock.SetCursor(160, 100)
	mock.FireScript(view, "OnUpdate", 0.016)
	T.eq(moves, 1, "a move moves the map")
	T.eq(redraws, 0, "without a redraw (the follow-ups: transform only while panning)")
	mock.SetMouseButtonDown("LeftButton", false)
	mock.FireScript(view, "OnMouseUp", "LeftButton")
	T.eq(redraws, 1, "laid out once on release")
	view.DrawContent, view.MoveCanvas = realDraw, realMove
	mock.ResetInput()
	ns.DB.DeletePlan(plan.id)
end)

T.case("Review: the Pull tool works again after its current pull was deleted", function()
	local p = page()
	local plan = ns.Home.CreatePlan("dungeon", "Scratch pulls", testEntry())
	local ctx = ns.UI.ctx
	ns.UI.SelectTab("map")
	local map = p.panels.map
	local pull = ns.Plan.AddPull(plan)
	local m = ns.Plan.AddMarker(plan, 1, 0.5, 0.5, "pack")
	ctx:Changed("pulls")
	ctx.currentPull, ctx.focusPull = pull.id, pull.id
	ns.Plan.RemovePull(plan, pull.id)
	ctx:Changed("pulls")
	ctx.tool = "pull"
	map:Refresh()
	T.eq(ctx.currentPull, nil, "the deleted pull is no longer current")
	T.eq(ctx.focusPull, nil)
	map.canvas.cb.onSelectMarker(m.id)
	T.eq(#plan.pulls, 1, "a click with the Pull tool starts a new pull")
	T.eq(m.pull, plan.pulls[1].id, "and the pack joins it")
	ctx.tool = "select"
	ns.DB.DeletePlan(plan.id)
end)

T.case("Review: the Group Finder's own instance names answer for the plans' names", function()
	boot()
	local GF = ns.GameFiles
	local activities, info = _G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable
	_G.C_LFGList.GetAvailableActivities = function()
		return { 801, 802 }
	end
	_G.C_LFGList.GetActivityInfoTable = function(id)
		if id == 801 then
			return { fullName = "Sunken Temple", minLevelSuggestion = 45, maxLevelSuggestion = 55, mapID = 109 }
		elseif id == 802 then
			return { fullName = "Ahn'Qiraj Temple", minLevelSuggestion = 60, maxLevelSuggestion = 60, mapID = 531 }
		end
		return nil
	end
	GF.Reset()
	local hit = GF.FinderFor("The Temple of Atal'Hakkar")
	T.eq(hit and hit.mapID, 109)
	hit = GF.FinderFor("Temple of Ahn'Qiraj")
	T.eq(hit and hit.mapID, 531)
	_G.C_LFGList.GetAvailableActivities, _G.C_LFGList.GetActivityInfoTable = activities, info
	GF.Reset()
end)
