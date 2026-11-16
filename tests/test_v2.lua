-- Plan format 2: new marker kinds, roles, links, route stops, the version 1 upgrade (stored and shared), recommended
-- (bundled) plans and the read-only guard.
local T = ...
local ns = T.ns
local Validate, Plan, Schema, Codec, Bundled, DB = ns.Validate, ns.Plan, ns.Schema, ns.Codec, ns.Bundled, ns.DB

T.case("Format 2: every kind belongs to exactly one map layer", function()
	local seen = {}
	for _, layer in ipairs(Schema.LAYERS) do
		for _, kind in ipairs(layer.kinds) do
			T.ok(not seen[kind], "kind in one layer: " .. kind)
			seen[kind] = true
		end
	end
	for _, kind in ipairs(Schema.MARKER_KINDS) do
		T.ok(seen[kind], "kind has a layer: " .. kind)
	end
end)

T.case("Format 2: version 1 kinds are renamed, unknown kinds become notes", function()
	local plan = Validate.Plan({
		v = 1,
		markers = {
			{ id = "m1", x = 0.1, y = 0.1, kind = "mob" },
			{ id = "m2", x = 0.2, y = 0.2, kind = "objective" },
			{ id = "m3", x = 0.3, y = 0.3, kind = "dragon" },
			{ id = "m4", x = 0.4, y = 0.4, kind = "quest_item" },
		},
	})
	T.eq(plan.v, Schema.PLAN_VERSION)
	T.eq(plan.markers[1].kind, "pack")
	T.eq(plan.markers[2].kind, "interactive")
	T.eq(plan.markers[3].kind, "note")
	T.eq(plan.markers[4].kind, "quest_item")
end)

T.case("Format 2: roles only on positions, floor links only on doors and in range", function()
	local plan = Validate.Plan({
		floors = { { name = "Upper" }, { name = "Lower" } },
		markers = {
			{ id = "m1", x = 0.1, y = 0.1, kind = "position", role = "RANGED" },
			{ id = "m2", x = 0.1, y = 0.1, kind = "position", role = "WIZARD" },
			{ id = "m3", x = 0.1, y = 0.1, kind = "pack", role = "TANK" },
			{ id = "m4", x = 0.1, y = 0.1, kind = "stairs", toFloor = 2 },
			{ id = "m5", x = 0.1, y = 0.1, kind = "exit", toFloor = 9 },
			{ id = "m6", x = 0.1, y = 0.1, kind = "loot", toFloor = 2, itemID = "item:12345", npcID = 77, questID = -1 },
		},
	})
	local m = plan.markers
	T.eq(m[1].role, "RANGED")
	T.eq(m[2].role, nil, "unknown role dropped")
	T.eq(m[3].role, nil, "role only on positions")
	T.eq(m[4].toFloor, 2)
	T.eq(m[5].toFloor, nil, "link outside the floors dropped")
	T.eq(m[6].toFloor, nil, "links only on doors")
	T.eq(m[6].itemID, 12345)
	T.eq(m[6].npcID, 77)
	T.eq(m[6].questID, nil)
	-- The editor's path: kinds change, the role goes with them.
	Plan.UpdateMarker(plan, "m1", { kind = "note" })
	T.eq(plan.markers[1].role, nil)
	local pos = Plan.AddMarker(plan, 1, 0.5, 0.5, "position", "Heal here", { role = "HEALER" })
	T.eq(pos.role, "HEALER")
	T.eq(pos.label, "Heal here")
end)

T.case("Format 2: route stops keep step, note and pull; bends drop them", function()
	local plan = Validate.Plan({
		pulls = { { id = "u1", name = "A" } },
		routes = {
			{
				id = "r1",
				optional = true,
				points = {
					{ 0.1, 0.1, note = "a bend has no note" },
					{ 0.2, 0.2, step = 4, note = "Pull here", pull = "u1" },
					{ 0.3, 0.3, step = 9, pull = "u9" },
					{ 0.4, 0.4, step = 5000 },
				},
			},
		},
	})
	local pts = plan.routes[1].points
	T.eq(plan.routes[1].optional, true)
	T.eq(pts[1].note, nil)
	T.eq(pts[2].step, 4)
	T.eq(pts[2].note, "Pull here")
	T.eq(pts[2].pull, "u1")
	T.eq(pts[3].pull, nil, "unknown pull dropped")
	T.eq(pts[4].step, nil, "step out of range dropped")
	Plan.RenumberStops(plan, "r1")
	T.eq(pts[2].step, 1)
	T.eq(pts[3].step, 2)
	Plan.SetRouteStop(plan, "r1", 1, true)
	T.eq(pts[1].step, 1)
	T.eq(pts[2].step, 2)
	Plan.SetRouteStop(plan, "r1", 2, false)
	T.eq(pts[2].step, nil)
	T.eq(pts[2].note, nil)
	T.eq(pts[3].step, 2)
	Plan.UpdateRoutePoint(plan, "r1", 3, { note = "Wait for patrol", pull = "u1" })
	T.eq(pts[3].pull, "u1")
	Plan.RemovePull(plan, "u1")
	T.eq(pts[3].pull, nil, "removing a pull clears stops that named it")
	Plan.MoveRoutePoint(plan, "r1", 3, 2, -1)
	T.eq(pts[3][1], 1)
	T.eq(pts[3][2], 0)
end)

T.case("Format 2: a version 1 export string still imports (community example)", function()
	local f = assert(io.open("community-plans/examples/template-five-player-run.dpplan", "rb"))
	local text = f:read("*a")
	f:close()
	T.ok(text:find("!DP1!", 1, true), "the example is a version 1 string")
	local kind, plan = Codec.Decode(text)
	T.eq(kind, "plan")
	T.eq(plan.v, Schema.PLAN_VERSION)
	for _, m in ipairs(plan.markers) do
		T.ok(Schema.MARKER_KIND_SET[m.kind], "kind upgraded: " .. m.kind)
		T.ok(m.kind ~= "mob", "no version 1 kinds left")
	end
	-- New strings carry the new header and a newer header is refused with a clear reason.
	T.eq(Codec.ExportPlan(plan):sub(1, 5), "!DP2!")
	local _, err = Codec.Decode("!DP3!abc")
	T.eq(err, "made by a newer Dungeon Planner")
end)

T.case("Migration 1 -> 2 renames stored kinds and marks the data", function()
	local global = {
		schema = 1,
		plans = { p1 = { id = "p1", name = "Old", markers = { { id = "m1", x = 0.5, y = 0.5, kind = "mob" } } } },
	}
	local info = DB.LoadGlobal(global)
	T.eq(global.schema, DB.SCHEMA)
	T.eq(info.migratedFrom, 1)
	T.eq(global.plans.p1.markers[1].kind, "pack")
	T.eq(global.plans.p1.v, Schema.PLAN_VERSION)
end)

T.case("Bundled plans: ids, duplicates, matching an instance, read-only guard", function()
	T.ok(not Bundled.Add({ name = "no id" }), "id required")
	T.ok(not Bundled.Add({ id = "bad id!" }), "id shape checked")
	T.ok(Bundled.Add({ id = "v2-test-a", name = "A", instance = { name = "Fixture Dungeon", kind = "dungeon" } }))
	T.ok(not Bundled.Add({ id = "v2-test-a", name = "again" }), "duplicate refused")
	local plan = DB.GetPlan and Bundled.Get("b:v2-test-a")
	T.ok(plan and plan.bundled, "validated on first use")
	T.ok(Bundled.IsBundled(plan))
	T.ok(Bundled.SameInstance(plan.instance, { name = "fixture dungeon" }), "names match loosely")
	T.ok(not Bundled.SameInstance({ ejInstanceID = 1 }, { ejInstanceID = 2 }), "journal IDs decide")
	T.eq(#Bundled.ForInstance({ name = "Fixture Dungeon" }), 1)
	-- No mutator changes it.
	T.eq(Plan.SetField(plan, "name", "Changed"), nil)
	T.eq(plan.name, "A")
	T.eq(Plan.AddMarker(plan, 1, 0.5, 0.5, "boss"), nil)
	T.eq(#plan.markers, 0)
	-- Readers still work.
	T.eq(#Plan.AssignmentLines(plan), 0)
	local copy = Plan.Duplicate(plan)
	T.ok(not copy.bundled)
	T.eq(copy.origin.bundled, "v2-test-a")
	T.ok(Plan.AddMarker(copy, 1, 0.5, 0.5, "boss"), "the copy is editable")
end)

T.case("Level ranges: client first, then the plan's", function()
	local lo, hi = ns.Instances.LevelRange({ ejInstanceID = 63 })
	T.eq(lo, 13)
	T.eq(hi, 18)
	lo, hi = ns.Instances.LevelRange({ levelMin = 20, levelMax = 30 })
	T.eq(lo, 20)
	T.eq(hi, 30)
	T.eq(ns.Instances.LevelRange({}), nil)
	local plan = Validate.Plan({ instance = { levelMin = 30, levelMax = 20 } })
	T.eq(plan.instance.levelMax, 30, "max never below min")
end)
