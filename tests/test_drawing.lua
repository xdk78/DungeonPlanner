-- Plan format 3: map drawings (Model/Drawing.lua), pull tags and planned progress, undo and redo (Model/History.lua),
-- and that drawings travel in export strings without breaking older strings or older readers.
local T = ...
local ns = T.ns
local Drawing, Validate, Plan, Codec, History, Schema = ns.Drawing, ns.Validate, ns.Plan, ns.Codec, ns.History, ns.Schema

local function newPlan()
	local plan = Validate.Plan({ name = "Draw", floors = { { name = "A" }, { name = "B" } } })
	plan.id = "pdraw"
	return plan
end

-- A wobbly line from (0.1, 0.5) to (0.9, 0.5): 401 raw points, never more than 0.0005 off the straight line.
local function wobble()
	local pts = {}
	for i = 0, 400 do
		pts[#pts + 1] = 0.1 + 0.8 * i / 400
		pts[#pts + 1] = 0.5 + ((i % 2 == 0) and 0.0005 or -0.0005)
	end
	return pts
end

T.case("Drawing: Ramer-Douglas-Peucker keeps corners and drops noise", function()
	local straight = Drawing.Simplify(wobble(), 0.002, 1)
	T.eq(#straight, 4, "a wobbly straight line becomes its two ends")
	T.eq(straight[1], 0.1)
	T.eq(straight[3], 0.9)
	-- An L shape keeps its corner.
	local l = {}
	for i = 0, 50 do
		l[#l + 1] = 0.2
		l[#l + 1] = 0.2 + 0.5 * i / 50
	end
	for i = 1, 50 do
		l[#l + 1] = 0.2 + 0.5 * i / 50
		l[#l + 1] = 0.7
	end
	local s = Drawing.Simplify(l, 0.002, 1)
	T.eq(#s, 6, "start, corner, end")
	T.eq(s[3], 0.2)
	T.eq(s[4], 0.7)
	-- Two points or fewer come back unchanged (a copy).
	local two = { 0.1, 0.2, 0.3, 0.4 }
	local copy = Drawing.Simplify(two, 1, 1)
	T.ok(copy ~= two and copy[4] == 0.4, "copied")
end)

T.case("Drawing: a stroke is quantized and capped at the point limit", function()
	-- A circle drawn with 1000 points cannot be simplified to 2: the tolerance grows until it fits.
	local pts = {}
	for i = 0, 999 do
		local a = 2 * math.pi * i / 999
		pts[#pts + 1] = 0.5 + 0.3 * math.cos(a) + 0.00012345
		pts[#pts + 1] = 0.5 + 0.3 * math.sin(a)
	end
	local fit = Drawing.FitStroke(pts, { maxPoints = 12 })
	T.ok(#fit / 2 <= 12 and #fit / 2 >= 4, "at most 12 points, still a loop: " .. #fit / 2)
	for _, v in ipairs(fit) do
		T.eq(v, math.floor(v * 1000 + 0.5) / 1000, "3 decimals")
		T.ok(v >= 0 and v <= 1, "inside the map")
	end
	T.eq(Drawing.FitStroke({ 0.5, 0.5, 0.5, 0.5 }), nil, "a click is not a stroke")
	-- Quantizing removes points that became equal.
	T.eq(#Drawing.Quantize({ 0.10001, 0.2, 0.10002, 0.2, 0.3, 0.3 }), 4)
end)

T.case("Drawing: add every kind, caps per floor and in total, read-only plans refuse", function()
	local plan = newPlan()
	local pen = Drawing.Add(plan, 1, "pen", wobble(), { color = 3, width = 3, author = "Someone" })
	T.ok(pen, "pen")
	T.eq(pen.id:sub(1, 1), "d")
	T.eq(#pen.pts, 4, "simplified")
	T.eq(pen.color, 3)
	T.eq(pen.author, "Someone")
	T.ok(Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.4, 0.4 }), "line")
	T.ok(Drawing.Add(plan, 1, "arrow", { 0.1, 0.1, 0.4, 0.1 }), "arrow")
	T.ok(Drawing.Add(plan, 2, "circle", { 0.2, 0.2, 0.4, 0.3 }), "circle on floor 2")
	T.ok(Drawing.Add(plan, 1, "rect", { 0.5, 0.5, 0.7, 0.6 }), "rect")
	local label = Drawing.Add(plan, 1, "text", { 0.5, 0.5 }, { text = "Skip |cffff0000here|r" })
	T.eq(label.text, "Skip here", "escape codes removed")
	T.eq(select(2, Drawing.Add(plan, 1, "text", { 0.5, 0.5 }, { text = "  " })), "invalid", "empty text")
	T.eq(select(2, Drawing.Add(plan, 1, "line", { 0.3, 0.3, 0.3, 0.3 })), "invalid", "a line without length")
	T.eq(select(2, Drawing.Add(plan, 1, "blob", { 0.3, 0.3, 0.4, 0.4 })), "invalid", "unknown kind")
	T.eq(select(2, Drawing.Add(plan, 1, "line", { 0.3, 0 / 0, 0.4, 0.4 })), "invalid", "NaN")
	T.eq(Drawing.Count(plan), 6)
	T.eq(Drawing.Count(plan, 1), 5)
	T.eq(#Drawing.OnFloor(plan, 2), 1)
	-- Per-floor cap.
	for _ = Drawing.Count(plan, 1) + 1, Schema.MAX.drawingsPerFloor do
		T.ok(Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.2, 0.2 }))
	end
	T.eq(select(2, Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.2, 0.2 })), "limit", "floor full")
	T.ok(Drawing.Add(plan, 2, "line", { 0.1, 0.1, 0.2, 0.2 }), "other floor still has room")
	-- Recommended plans are read-only.
	local bundled = newPlan()
	bundled.bundled = true
	T.eq(select(2, Drawing.Add(bundled, 1, "line", { 0.1, 0.1, 0.2, 0.2 })), "read-only")
	T.eq(select(2, Drawing.Clear(bundled)), "read-only")
end)

T.case("Drawing: hit-testing by distance, topmost first, text boxes and hidden shapes", function()
	local plan = newPlan()
	local line = Drawing.Add(plan, 1, "line", { 0.1, 0.5, 0.9, 0.5 })
	local box = Drawing.Add(plan, 1, "rect", { 0.4, 0.4, 0.6, 0.6 })
	local ring = Drawing.Add(plan, 1, "circle", { 0.1, 0.1, 0.3, 0.3 })
	local arrow = Drawing.Add(plan, 1, "arrow", { 0.7, 0.1, 0.9, 0.1 })
	local label = Drawing.Add(plan, 1, "text", { 0.2, 0.8 }, { text = "LoS" })
	local o = { aspect = 1.5 }
	T.eq(Drawing.HitTest(plan, 1, 0.2, 0.505, 0.01, o), line, "near the line")
	T.eq(Drawing.HitTest(plan, 1, 0.2, 0.55, 0.01, o), nil, "too far")
	T.eq(Drawing.HitTest(plan, 1, 0.5, 0.5, 0.01, o), line, "where line and box cross the nearer wins")
	T.eq(Drawing.HitTest(plan, 1, 0.4, 0.45, 0.01, o), box, "on the box's edge")
	T.eq(Drawing.HitTest(plan, 1, 0.5, 0.45, 0.01, o), nil, "inside the box is not its outline")
	T.eq(Drawing.HitTest(plan, 1, 0.3, 0.2, 0.01, o), ring, "on the ellipse")
	T.eq(Drawing.HitTest(plan, 1, 0.2, 0.2, 0.01, o), nil, "the ellipse's centre is empty")
	T.eq(Drawing.HitTest(plan, 1, 0.21, 0.8, 0.01, o), label, "inside the label's box")
	T.eq(Drawing.HitTest(plan, 1, 0.8, 0.1, 0.01, o), arrow, "the arrow's shaft")
	T.eq(Drawing.HitTest(plan, 2, 0.2, 0.5, 0.01, o), nil, "other floor")
	T.eq(Drawing.HitTest(plan, 1, 0.2, 0.5, 0.01, o, function(s)
		return s ~= line
	end), nil, "hidden shapes are not hit")
	-- Topmost of two equal hits.
	local over = Drawing.Add(plan, 1, "line", { 0.1, 0.5, 0.9, 0.5 })
	T.eq(Drawing.HitTest(plan, 1, 0.2, 0.5, 0.01, o), over, "the one drawn last")
end)

T.case("Drawing: geometry for the renderer (arrow heads, ellipses, joints at sharp bends only)", function()
	local heads = Drawing.ArrowHead(0, 0.5, 0.5, 0.5, 0.05, 1)
	T.eq(#heads, 2)
	for _, h in ipairs(heads) do
		T.eq(h[1], 0.5, "starts at the tip")
		T.ok(h[3] < 0.5, "points back along the shaft")
	end
	local e = Drawing.Ellipse(0, 0, 1, 0.5, 8)
	T.eq(#e, 18, "closed: 9 points")
	T.ok(math.abs(e[1] - 1) < 1e-9 and math.abs(e[2] - 0.25) < 1e-9, "starts on the right")
	-- A zig-zag gets joints, a gentle curve none.
	T.eq(#Drawing.Joints({ 0, 0, 0.5, 0.5, 1, 0 }, 20), 1, "a sharp bend")
	T.eq(#Drawing.Joints({ 0, 0, 0.5, 0.01, 1, 0.03 }, 20), 0, "a shallow one")
	local poly = Drawing.Polylines({ kind = "rect", pts = { 0.1, 0.1, 0.2, 0.2 } }, { dx = 0.1 })
	T.eq(poly[1][1], 0.2, "moved while dragging")
	T.eq(#Drawing.Polylines({ kind = "text", pts = { 0.1, 0.1 } }), 0, "text draws no lines")
end)

T.case("Drawing: edit, move inside the map, links, clear, and upkeep when pulls and floors go", function()
	local plan = newPlan()
	local pull = Plan.AddPull(plan, "First")
	local enc = Plan.AddEncounter(plan, { name = "Boss" })
	local s = Drawing.Add(plan, 2, "rect", { 0.8, 0.8, 0.9, 0.9 }, { pull = pull.id })
	T.eq(s.pull, pull.id)
	Drawing.Update(plan, s.id, { color = 5, width = 1 })
	T.eq(s.color, 5)
	T.eq(s.width, 1)
	Drawing.Update(plan, s.id, { encounter = enc.id })
	T.eq(s.encounter, enc.id)
	T.eq(s.pull, nil, "one link at a time")
	Drawing.Update(plan, s.id, { color = 99, width = 7 })
	T.eq(s.color, 1, "bad colour")
	T.eq(s.width, 2, "bad width")
	Drawing.Move(plan, s.id, 0.5, 0.5)
	T.eq(s.pts[3], 1, "kept inside the map")
	T.eq(s.pts[1], 0.9, "moved as a whole")
	-- Visibility per run-mode setting.
	T.ok(Drawing.Visible(s, "all"), "all")
	T.ok(not Drawing.Visible(s, "off"), "off")
	T.ok(not Drawing.Visible(s, "step", nil, nil), "linked: hidden on another step")
	T.ok(Drawing.Visible(s, "step", nil, enc.id), "linked: shown on its step")
	T.ok(Drawing.Visible({ kind = "line" }, "step"), "unlinked: always")
	-- Removing the boss unlinks; removing floors moves the drawing to floor 1.
	Plan.RemoveEncounter(plan, enc.id)
	T.eq(s.encounter, nil)
	Plan.SetFloors(plan, { { name = "Only" } })
	T.eq(s.floor, 1)
	local other = Drawing.Add(plan, 1, "line", { 0.1, 0.1, 0.2, 0.2 }, { pull = pull.id })
	Plan.RemovePull(plan, pull.id)
	T.eq(other.pull, nil)
	T.eq(Drawing.Clear(plan, 1), 2, "clear a floor")
	T.eq(plan.drawings, nil, "no empty table left behind")
	T.ok(Drawing.Remove(plan, "d999") == nil, "missing")
end)

T.case("Drawing: validation drops bad shapes, a newer version and anything over the caps", function()
	local raw = {
		floors = { { name = "A" } },
		pulls = { { id = "u1", name = "P" } },
		drawings = {
			v = 1,
			shapes = {
				{ id = "d1", kind = "pen", floor = 1, color = 2, width = 3, pts = { 0.1, 0.2, 0.30004, 0.4, 1.5, -1 }, pull = "u1" },
				{ id = "d2", kind = "line", pts = { 0.1, 0.1 } }, -- one point: dropped
				{ id = "d3", kind = "text", pts = { 0.5, 0.5 }, text = "" }, -- empty: dropped
				{ id = "d4", kind = "spiral", pts = { 0.1, 0.1, 0.2, 0.2 } }, -- unknown: dropped
				{ id = "d1", kind = "line", pts = { 0.1, 0.1, 0.2, 0.2 } }, -- duplicate id: dropped
				{ id = "d5", kind = "arrow", pts = { 0.1, 0.1, 0.2, 0.2, 0.3, 0.3 }, pull = "nope", floor = 9 },
				{ id = "d6", kind = "line", pts = { 0.1, "x", 0.2, 0.2 } }, -- not a number: dropped
				"junk",
			},
		},
	}
	local plan, report = Validate.Plan(raw)
	local shapes = plan.drawings.shapes
	T.eq(#shapes, 2)
	T.eq(shapes[1].pts[3], 0.3, "3 decimals")
	T.eq(shapes[1].pts[5], 1, "clamped")
	T.eq(shapes[1].pts[6], 0, "clamped")
	T.eq(shapes[1].pull, "u1")
	T.eq(#shapes[2].pts, 4, "a line keeps 2 points")
	T.eq(shapes[2].pull, nil, "unknown pull")
	T.eq(shapes[2].floor, 1, "floor out of range")
	T.eq(report.dropped.drawings, 6)
	T.ok(plan.nextId > 5, "ids of drawings count for nextId")
	-- A newer drawing format is dropped whole, the rest of the plan stays.
	local newer, r2 = Validate.Plan({ name = "N", drawings = { v = 2, shapes = { { id = "d1", kind = "line" } } } })
	T.eq(newer.drawings, nil)
	T.eq(r2.dropped.drawings, 1)
	T.eq(newer.name, "N")
	-- Caps: a pen stroke over the point limit is cut, a floor over the shape limit loses the rest.
	local long, many = {}, {}
	for i = 1, Schema.MAX.strokePoints * 2 + 10 do
		long[i] = (i % 100) / 100
	end
	for i = 1, Schema.MAX.drawingsPerFloor + 5 do
		many[i] = { id = "d" .. i, kind = "line", pts = { 0.1, 0.1, 0.2, 0.2 } }
	end
	many[1] = { id = "d1", kind = "pen", pts = long }
	local capped = Validate.Plan({ drawings = { shapes = many } })
	T.eq(#capped.drawings.shapes, Schema.MAX.drawingsPerFloor)
	T.eq(#capped.drawings.shapes[1].pts, Schema.MAX.strokePoints * 2)
	T.eq(Validate.Plan({ drawings = "x" }).drawings, nil)
end)

T.case("Drawing: export string round trip, and older strings and readers", function()
	local plan = newPlan()
	local pull = Plan.AddPull(plan, "First")
	Plan.UpdatePull(plan, pull.id, { tags = { "interrupt", "los" }, cd = true, lust = true, progress = 34 })
	Drawing.Add(plan, 1, "pen", wobble(), { color = 4, width = 1, pull = pull.id })
	Drawing.Add(plan, 2, "text", { 0.4, 0.6 }, { text = "Jump down" })
	local text = Codec.ExportPlan(plan)
	T.eq(text:sub(1, 5), "!DP2!", "the header stays: older readers still import the rest")
	local kind, back = Codec.Decode(text)
	T.eq(kind, "plan")
	T.eq(#back.drawings.shapes, 2)
	T.eq(back.drawings.v, 1)
	local pen = back.drawings.shapes[1]
	T.eq(pen.kind, "pen")
	T.eq(pen.color, 4)
	T.eq(pen.pull, back.pulls[1].id)
	T.eq(table.concat(pen.pts, ","), table.concat(plan.drawings.shapes[1].pts, ","))
	T.eq(back.drawings.shapes[2].text, "Jump down")
	T.eq(back.drawings.shapes[2].floor, 2)
	local p = back.pulls[1]
	T.eq(table.concat(p.tags, ","), "interrupt,los")
	T.ok(p.cd and p.lust, "cooldowns and Bloodlust")
	T.eq(p.progress, 34)
	-- An older reader keeps only the fields it knows: drawings and the new pull fields are simply not there. A plan
	-- read that way (simulated: the new fields stripped) is still a whole plan.
	local old = ns.Util.DeepCopy(back)
	old.drawings = nil
	for _, u in ipairs(old.pulls) do
		u.tags, u.cd, u.lust, u.progress = nil, nil, nil, nil
	end
	local reread = Validate.Plan(old)
	T.eq(#reread.pulls, 1)
	T.eq(reread.drawings, nil)
	-- Strings made before drawings existed still import unchanged (the community example is a version 1 string).
	local f = assert(io.open("community-plans/examples/template-five-player-run.dpplan", "rb"))
	local example = f:read("*a")
	f:close()
	local k2, plan2 = Codec.Decode(example)
	T.eq(k2, "plan")
	T.eq(plan2.drawings, nil)
	T.ok(#plan2.markers > 0)
	-- A plan without drawings exports without the field at all.
	local bare = newPlan()
	local _, bareBack = Codec.Decode(Codec.ExportPlan(bare))
	T.eq(bareBack.drawings, nil)
end)

T.case("Pull tags: known tags only, in order, switched one by one; progress clamped", function()
	local plan = newPlan()
	local pull = Plan.AddPull(plan)
	Plan.UpdatePull(plan, pull.id, { tags = { "careful", "interrupt", "bogus", "interrupt" } })
	T.eq(table.concat(pull.tags, ","), "interrupt,careful", "known, unique, in Schema order")
	Plan.UpdatePull(plan, pull.id, { tags = { cc = true, careful = false } })
	T.eq(table.concat(pull.tags, ","), "interrupt,cc", "switched one by one")
	T.ok(Plan.HasTag(pull, "cc"))
	T.ok(not Plan.HasTag(pull, "skip"))
	Plan.UpdatePull(plan, pull.id, { tags = {} })
	T.eq(pull.tags, nil, "cleared")
	Plan.UpdatePull(plan, pull.id, { progress = 33.6 })
	T.eq(pull.progress, 34)
	Plan.UpdatePull(plan, pull.id, { progress = 140 })
	T.eq(pull.progress, nil, "out of range clears it")
	Plan.UpdatePull(plan, pull.id, { lust = true, cd = true })
	Plan.UpdatePull(plan, pull.id, { lust = false })
	T.ok(pull.cd and not pull.lust)
	local v = Validate.Plan({ pulls = { { id = "u1", tags = "interrupt", cd = "yes", lust = 1, progress = -3 } } })
	local u = v.pulls[1]
	T.ok(u.tags == nil and u.cd == nil and u.lust == nil and u.progress == nil, "wrong types dropped")
end)

T.case("History: 50 steps of undo, redo, and a new change clears redo", function()
	local h = History.New(50)
	History.Reset(h, "p", { n = 0 })
	for i = 1, 60 do
		History.Record(h, "p", { n = i })
	end
	local undo, redo = History.Counts(h)
	T.eq(undo, 50, "bounded")
	T.eq(redo, 0)
	T.eq(History.Undo(h).n, 59)
	T.eq(History.Undo(h).n, 58)
	T.ok(History.CanRedo(h, "p"))
	T.eq(History.Redo(h).n, 59)
	History.Record(h, "p", { n = 100 })
	T.ok(not History.CanRedo(h, "p"), "a new change ends redo")
	T.eq(History.Undo(h).n, 59)
	T.ok(not History.CanUndo(h, "other"), "another plan has no history here")
	History.Record(h, "other", { n = 1 })
	T.ok(not History.CanUndo(h, "other"), "switching plans starts over")
	for _ = 1, 60 do
		History.Undo(h)
	end
	T.eq(History.Undo(h), nil, "nothing left")
end)
