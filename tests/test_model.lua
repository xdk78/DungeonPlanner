-- Util, Validate, Plan, Route, Progress.
local T = ...
local ns = T.ns
local Util, Validate, Plan, Route, Progress, Schema = ns.Util, ns.Validate, ns.Plan, ns.Route, ns.Progress, ns.Schema

T.case("Util.TruncateUTF8 never splits a character", function()
	local s = "\197\130\197\130\197\130" -- ł ł ł (2 bytes each)
	T.eq(Util.TruncateUTF8(s, 3), "\197\130", "cut at 3 bytes")
	T.eq(Util.TruncateUTF8(s, 4), "\197\130\197\130", "cut at 4 bytes")
	T.eq(Util.TruncateUTF8("abc", 10), "abc")
end)

T.case("Util.StripEscapes removes UI escapes and control bytes", function()
	T.eq(Util.StripEscapes("|cff00ff00green|r"), "green")
	T.eq(Util.StripEscapes("a|TInterface\\x:0|tb"), "ab")
	T.eq(Util.StripEscapes("|Hitem:123|h[Sword]|h"), "[Sword]")
	T.eq(Util.StripEscapes("x\0y\7z"), "xyz")
	T.eq(Util.StripEscapes("a||b"), "ab")
end)

T.case("Util.ParseItemID accepts ids and links only", function()
	T.eq(Util.ParseItemID(19019), 19019)
	T.eq(Util.ParseItemID(" 42 "), 42)
	T.eq(Util.ParseItemID("|cffa335ee|Hitem:12345::::|h[X]|h|r"), 12345)
	T.eq(Util.ParseItemID("abc"), nil)
	T.eq(Util.ParseItemID(-5), nil)
	T.eq(Util.ParseItemID(1.5), nil)
end)

T.case("Validate.Plan rejects non-tables and fills defaults", function()
	T.eq(Validate.Plan("x"), nil)
	local plan = Validate.Plan({})
	T.eq(plan.name, "Untitled plan")
	T.eq(#plan.floors, 1)
	T.eq(#plan.groups, Schema.MAX.groups)
	T.eq(plan.nextId, 1)
end)

T.case("Validate.Plan clamps, drops and fixes references", function()
	local raw = {
		name = string.rep("n", 200),
		pulls = { { id = "u1", name = "P1", color = 99 }, { id = "u1", name = "dup" }, { id = "bad id" } },
		markers = {
			{ id = "m1", x = 1.7, y = -2, kind = "boss", pull = "u1", floor = 9 },
			{ id = "m2", x = 0.5, y = 0.5, pull = "nope", kind = "unknown" },
			{ id = "m3", x = "0.5", y = 0.5 },
			{ id = "m4", x = 0 / 0, y = 0.5 },
		},
		routes = { { id = "r1", points = { { 0.1, 0.2 }, { "a", 1 }, { 0.3, 0.4 } } } },
		encounters = { { id = "e1", name = "B", phases = { { name = "P1" }, "junk" }, custom = "yes" } },
		assignments = {
			{ id = "a1", target = "role:TANK", task = "t", encounter = "e1", phase = 1 },
			{ id = "a2", target = "role:WIZARD" },
			{ id = "a3", target = "group:9" },
			{ id = "a4", target = "Name^Bad" },
		},
		gear = { { id = "g1", itemID = "item:555", slot = "HEAD", class = "WARRIOR", role = "TANK", priority = 9 }, { id = "g2" } },
		objectives = { { id = "o1", text = "x" }, { id = "o2", text = "" } },
		groups = { { "A", "B", "C", "D", "E", "F" }, { "role:TANK" } },
	}
	local plan, report = Validate.Plan(raw)
	T.eq(#plan.name, Schema.TEXT.name, "name capped")
	T.eq(#plan.pulls, 1, "duplicate and bad pull ids dropped")
	T.eq(plan.pulls[1].color, 1, "bad colour reset")
	T.eq(#plan.markers, 2, "markers with bad coordinates dropped")
	T.eq(plan.markers[1].x, 1, "x clamped")
	T.eq(plan.markers[1].y, 0, "y clamped")
	T.eq(plan.markers[1].floor, 1, "floor clamped to existing floors")
	T.eq(plan.markers[1].pull, "u1")
	T.eq(plan.markers[2].pull, nil, "dangling pull reference removed")
	T.eq(plan.markers[2].kind, "note", "unknown kind becomes note")
	T.eq(#plan.routes[1].points, 2)
	T.eq(#plan.encounters[1].phases, 1)
	T.eq(plan.encounters[1].custom, nil, "custom must be boolean true")
	T.eq(#plan.assignments, 1)
	T.eq(plan.assignments[1].phase, 1)
	T.eq(plan.gear[1].itemID, 555)
	T.eq(plan.gear[1].priority, 3)
	T.eq(#plan.gear, 1, "empty gear entry dropped")
	T.eq(#plan.objectives, 1)
	T.eq(#plan.groups[1], 5, "group size capped")
	T.eq(#plan.groups[2], 0, "role is not a player name")
	T.ok(plan.nextId > 2, "nextId above every kept id")
	T.ok(report.dropped.markers == 2, "report counts dropped markers")
	T.ok(Validate.Summary(report):find("markers"), "summary mentions markers")
end)

T.case("Validate.Plan survives cyclic and hostile tables", function()
	local raw = { name = "cyc" }
	raw.markers = { raw }
	raw.pulls = raw.markers
	raw.instance = raw
	local plan = Validate.Plan(raw)
	T.eq(plan.name, "cyc")
	T.eq(#plan.markers, 0)
end)

T.case("Validate.Plan enforces list limits", function()
	local raw = { markers = {} }
	for i = 1, Schema.MAX.markers + 50 do
		raw.markers[i] = { id = "m" .. i, x = 0.5, y = 0.5 }
	end
	local plan, report = Validate.Plan(raw)
	T.eq(#plan.markers, Schema.MAX.markers)
	T.ok(report.dropped.markers >= 1)
end)

T.case("Plan operations keep references consistent", function()
	local plan = Plan.New({ name = "Test", floors = { { uiMapID = 100, name = "A" }, { uiMapID = 101, name = "B" } } })
	T.ok(plan.id:match("^p"), "plan id")
	local pull = Plan.AddPull(plan)
	local m1 = Plan.AddMarker(plan, 2, 0.1, 0.2, "mob", "Pack")
	local m2 = Plan.AddMarker(plan, 1, 0.5, 0.5, "boss")
	Plan.UpdateMarker(plan, m1.id, { pull = pull.id, note = "watch out", icon = 8 })
	T.eq(#Plan.MarkersOfPull(plan, pull.id), 1)
	local enc = Plan.AddEncounter(plan, { name = "Boss", dungeonEncounterID = 1234, ejEncounterID = 99 })
	Plan.AddPhase(plan, enc.id)
	Plan.AddPhase(plan, enc.id)
	local a = Plan.AddAssignment(plan, "role:HEALER", "heal", enc.id, 2)
	T.eq(a.phase, 2)
	Plan.RemovePhase(plan, enc.id, 1)
	T.eq(a.phase, 1, "phase index shifts down")
	Plan.UpdateAssignment(plan, a.id, { marker = m2.id })
	Plan.RemoveMarker(plan, m2.id)
	T.eq(a.marker, nil, "assignment marker cleared")
	Plan.RemovePull(plan, pull.id)
	T.eq(m1.pull, nil, "marker pull cleared")
	T.eq(Plan.FindEncounterByGameID(plan, 1234), enc)
	Plan.RemoveEncounter(plan, enc.id)
	T.eq(a.encounter, nil, "assignment encounter cleared")
	-- Renaming: a name makes the boss custom; an empty name goes back to the journal's, keeping the fallback.
	local e2 = Plan.AddEncounter(plan, { name = "Journal name", ejEncounterID = 5 })
	Plan.UpdateEncounter(plan, e2.id, { name = "Mine" })
	T.eq(e2.custom, true)
	Plan.UpdateEncounter(plan, e2.id, { name = "" })
	T.eq(e2.custom, nil)
	T.eq(e2.name, "Mine", "fallback name kept")
	-- Floors shrinking moves things to floor 1.
	Plan.SetFloors(plan, { { uiMapID = 100 } })
	T.eq(m1.floor, 1)
	-- Pull ordering.
	local p1, p2 = Plan.AddPull(plan, "one"), Plan.AddPull(plan, "two")
	Plan.MovePull(plan, p2.id, -1)
	T.eq(plan.pulls[1].id, p2.id)
	T.eq(Plan.MovePull(plan, p2.id, -1), nil, "cannot move above the first")
	T.ok(p1)
	-- A validated round trip keeps everything.
	local again = Validate.Plan(Util.DeepCopy(plan))
	T.eq(#again.markers, #plan.markers)
	T.eq(again.nextId >= plan.nextId, true)
end)

T.case("Plan.SetGroup moves players and respects size", function()
	local plan = Plan.New({})
	for i = 1, 5 do
		T.ok(Plan.SetGroup(plan, "P" .. i, 1))
	end
	T.eq(Plan.SetGroup(plan, "P6", 1), nil, "group full")
	Plan.SetGroup(plan, "P1", 2)
	T.eq(#plan.groups[1], 4)
	T.eq(plan.groups[2][1], "P1")
	T.eq(Plan.SetGroup(plan, "role:TANK", 3), nil, "roles are not players")
end)

T.case("Plan.FilterGear treats empty class/role as universal and sorts by priority", function()
	local plan = Plan.New({})
	Plan.AddGear(plan, { itemID = 1, label = "b", priority = 2 })
	Plan.AddGear(plan, { itemID = 2, label = "a", class = "MAGE", priority = 1 })
	Plan.AddGear(plan, { itemID = 3, label = "c", class = "WARRIOR", role = "TANK", priority = 1 })
	local mage = Plan.FilterGear(plan, { class = "MAGE" })
	T.eq(#mage, 2)
	T.eq(mage[1].itemID, 2)
	T.eq(#Plan.FilterGear(plan, { role = "HEALER" }), 2)
	T.eq(Plan.AddGear(plan, {}), nil, "needs an item or a label")
end)

T.case("Plan.AssignmentLines formats roles, groups and phases", function()
	local plan = Plan.New({})
	local enc = Plan.AddEncounter(plan, { name = "B" })
	Plan.AddPhase(plan, enc.id)
	Plan.AddAssignment(plan, "role:TANK", "tank it", enc.id, 1)
	Plan.AddAssignment(plan, "group:3", "stack")
	Plan.AddAssignment(plan, "Anna", "kick")
	local lines = Plan.AssignmentLines(plan)
	T.eq(lines[1], "[P1] TANK: tank it")
	T.eq(lines[2], "G3: stack")
	T.eq(lines[3], "Anna: kick")
	T.eq(#Plan.AssignmentLines(plan, enc.id), 1)
end)

T.case("Route.SuggestOrder finds the short path and keeps the start", function()
	local pts = { { 0, 0 }, { 0.9, 0 }, { 0.1, 0 }, { 0.5, 0 }, { 0.3, 0 } }
	local order = Route.SuggestOrder(pts, 1, 1)
	T.eq(order[1], 1)
	local sorted = {}
	for i, idx in ipairs(order) do
		sorted[i] = pts[idx][1]
	end
	T.eq(table.concat(sorted, ","), "0,0.1,0.3,0.5,0.9")
	-- 2-opt improves on a crossing.
	local square = { { 0, 0 }, { 1, 1 }, { 1, 0 }, { 0, 1 } }
	local o = Route.SuggestOrder(square, 1, 1, 100)
	local ordered = {}
	for i, idx in ipairs(o) do
		ordered[i] = square[idx]
	end
	T.ok(Route.Length(ordered, 1) <= 3.0001, "no crossing")
	T.eq(#Route.SuggestOrder({}, 1), 0)
end)

T.case("Route.PointsFromPulls uses pull centroids in order", function()
	local plan = Plan.New({})
	local a, b = Plan.AddPull(plan), Plan.AddPull(plan)
	local m1 = Plan.AddMarker(plan, 1, 0.2, 0.2, "mob")
	local m2 = Plan.AddMarker(plan, 1, 0.4, 0.4, "mob")
	local m3 = Plan.AddMarker(plan, 1, 0.8, 0.8, "mob")
	Plan.UpdateMarker(plan, m1.id, { pull = a.id })
	Plan.UpdateMarker(plan, m2.id, { pull = a.id })
	Plan.UpdateMarker(plan, m3.id, { pull = b.id })
	local pts = Route.PointsFromPulls(plan, 1)
	T.eq(#pts, 2)
	T.ok(math.abs(pts[1][1] - 0.3) < 1e-9)
	T.eq(pts[2][1], 0.8)
end)

T.case("Progress records kills, runs and objectives", function()
	local s = Progress.NewStore()
	Progress.EnterInstance(s, "9001", "Dungeon", 1, 100)
	Progress.RecordKill(s, 201, 1, "Boss 1", 110)
	Progress.RecordKill(s, 201, 2, "Boss 1", 120)
	T.eq(Progress.KillsOf(s, 201), 2)
	T.ok(Progress.IsKilledInRun(s, 201))
	local _, isNew = Progress.EnterInstance(s, "9001", "Dungeon", 1, 200)
	T.eq(isNew, false, "same instance soon after: same run")
	local run
	run, isNew = Progress.EnterInstance(s, "9001", "Dungeon", 1, 200 + Progress.RESUME + 1)
	T.eq(isNew, true, "long gap: new run")
	T.eq(#s.history, 1, "old run archived")
	T.ok(not Progress.IsKilledInRun(s, 201))
	Progress.SetObjective(s, "p1", "o1", true)
	T.ok(Progress.IsObjectiveDone(s, "p1", "o1"))
	Progress.SetObjective(s, "p1", "o1", false)
	T.eq(s.objectives.p1, nil, "empty objective table removed")
	T.eq(Progress.RecordKill(s, "x", 1), nil)
	T.ok(run)
	local norm = Progress.Normalize({ kills = 5 })
	T.eq(type(norm.kills), "table")
end)
