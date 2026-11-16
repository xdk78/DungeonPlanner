-- The research batch's simplifications: where a recommended plan comes from (source, revision, data date), the Discord
-- text folded under "Advanced", importing over a plan of yours only after asking, and stats the client cannot give
-- shown as "not available" rather than zero.
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

T.case("Recommended plans name their source, revision and data date; copies say what they are based on", function()
	boot()
	local rec = ns.Bundled.Get("b:the-deadmines")
	T.ok(rec.updated and rec.updated > 0, "the data date ships with the plan")
	local short, lines = ns.UI.PlanSource(rec)
	T.ok(short:find("revision 1", 1, true), short)
	T.ok(short:find(date("%Y-%m-%d", rec.updated), 1, true), "the date in the short line")
	local all = table.concat(lines, "\n")
	T.ok(all:find("Dungeon Planner", 1, true), "the source")
	T.ok(all:find("Data date", 1, true), "the date")
	T.ok(all:find("Route: Forever Dungeon Routes", 1, true), "the route's credit")
	-- The plan picker's tooltip carries the lines.
	ns.UI.SelectPlan(rec.id)
	local page = _G.DungeonPlannerMainFrame.instancePage
	T.ok(page.planPick.dpTooltipText:find("Data revision: 1", 1, true), "header tooltip")
	-- The Notes section says it too.
	ns.UI.SelectTab("plan")
	local planPage = page.panels.plan
	planPage:Refresh()
	T.eq(planPage.notes.doc:IsShown(), true)
	-- A copy names the plan it is based on.
	local copy = ns.UI.CopyPlan(rec)
	local cshort, clines = ns.UI.PlanSource(copy)
	T.ok(cshort:find("revision 1", 1, true), cshort)
	T.ok(table.concat(clines, "\n"):find("Full clear", 1, true), "the original's name")
	-- A plan of your own has no source line.
	T.eq(ns.UI.PlanSource(ns.Validate.Plan({ name = "Mine" })), nil)
end)

T.case("Share: the Discord text is folded under Advanced", function()
	boot()
	local rec = ns.Bundled.Get("b:the-deadmines")
	ns.UI.SelectPlan(rec.id)
	ns.db.ui.shareAdvanced = nil
	ns.UI.SelectTab("share")
	local share = _G.DungeonPlannerMainFrame.instancePage.panels.share.inner
	share:Refresh()
	local c = share.content
	T.ok(not share.discord:IsShown(), "closed by default")
	click(c.advanced)
	T.ok(share.discord:IsShown(), "opened")
	T.eq(ns.db.ui.shareAdvanced, true, "remembered")
	click(c.discordMake)
	T.ok((c.discordBox:GetValue() or ""):find("Full clear", 1, true), "Discord text made")
	click(c.advanced)
	T.ok(not share.discord:IsShown(), "folded again")
end)

T.case("Import: a plan named like one of yours asks first; keep both adds, replace overwrites (and Undo returns it)", function()
	boot()
	closeDialogs()
	local entry = ns.Instances.Get("ej:63") or { key = "ej:63", name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63 }
	local mine = ns.Home.CreatePlan("dungeon", "Same name", entry)
	ns.Plan.AddPull(mine, "Mine only")
	ns.UI.ctx:Changed("pulls")
	local other = ns.Util.DeepCopy(mine)
	other.pulls = {}
	ns.Plan.AddPull(other, "Imported pull")
	local text = ns.Codec.ExportPlan(other)
	-- A string without a clash imports at once.
	local fresh = ns.Util.DeepCopy(other)
	fresh.name = "Something else"
	local before = #ns.DB.Plans()
	ns.UI.ImportWithConfirm(ns.Codec.ExportPlan(fresh), { kind = "import" })
	T.eq(#ns.DB.Plans(), before + 1, "no question without a clash")
	-- A clash asks; Cancel does nothing.
	T.eq(#ns.DB.ImportConflicts(text), 1)
	before = #ns.DB.Plans()
	ns.UI.ImportWithConfirm(text, { kind = "import" })
	local dialog = _G.DungeonPlannerDialog
	T.ok(dialog:IsShown(), "asked")
	T.eq(#ns.DB.Plans(), before, "nothing yet")
	click(dialog.buttons[3])
	T.eq(#ns.DB.Plans(), before, "cancelled")
	-- Keep both.
	ns.UI.ImportWithConfirm(text, { kind = "import" })
	click(dialog.buttons[1])
	T.eq(#ns.DB.Plans(), before + 1, "kept both")
	-- Replace: the plan on the table is overwritten in place; Undo brings it back.
	ns.UI.SelectPlan(mine.id, true)
	before = #ns.DB.Plans()
	ns.UI.ImportWithConfirm(text, { kind = "import" })
	click(dialog.buttons[2])
	T.eq(#ns.DB.Plans(), before, "replaced, not added")
	T.eq(ns.DB.GetPlan(mine.id).pulls[1].name, "Imported pull", "overwritten in place, same id")
	T.ok(ns.UI.ctx:CanUndo(), "undoable")
	ns.UI.ctx:Undo()
	T.eq(ns.DB.GetPlan(mine.id).pulls[1].name, "Mine only", "undo returns your plan")
	-- Received plans never replace anything.
	local ok, _, added, replaced = ns.DB.ImportString(text, { from = "Someone", kind = "received" })
	T.ok(ok and #added == 1 and #replaced == 0, "received: always a new plan")
end)

T.case("Runs: deaths the client cannot read are not available, not zero", function()
	local RunLog = ns.RunLog
	local run = RunLog.NewRun and RunLog.NewRun("k", "Test", 1, 0) or { k = "k", n = "Test", t = 0, seen = 0, p = {}, b = {},
		w = 0, dd = 0 }
	run.p[1] = { s = 0, c = 3 }
	RunLog.PullEnd(run, 10, nil, false)
	T.eq(RunLog.Summary(run).deaths, nil, "unknown")
	run.p[2] = { s = 20, c = 2 }
	RunLog.PullEnd(run, 30, 0, false)
	T.eq(RunLog.Summary(run).deaths, 0, "read once: a real zero")
	run.p[3] = { s = 40, c = 2 }
	RunLog.PullEnd(run, 50, 2, false)
	T.eq(RunLog.Summary(run).deaths, 2)
	-- An older run with deaths recorded still shows them.
	T.eq(RunLog.Summary({ p = {}, b = {}, dd = 3 }).deaths, 3)
end)
