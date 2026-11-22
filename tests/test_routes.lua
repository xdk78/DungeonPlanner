-- Route direction arrows (Model/RouteArrows.lua): spacing by on-screen distance, no overlaps, clear of stops, bends,
-- pins, labels and crossings, arrowheads before stops, bounded; and the Routes settings (UI/Settings.lua, drawn by
-- UI/MapRoutes.lua): stored in the profile, applied to the map at once.
local T = ...
local ns, mock = T.ns, T.mock
local RA = ns.RouteArrows

local function boot()
	mock.ResetInput() -- no button or key left held by a case that failed
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

local function dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- No two arrows closer than their own sizes (with room to spare: an arrow's length between them).
local function apart(arrows)
	for i = 1, #arrows do
		for j = i + 1, #arrows do
			if dist(arrows[i], arrows[j]) < (arrows[i].size + arrows[j].size) / 2 then
				return false, i, j
			end
		end
	end
	return true
end

local O = { spacing = 100, size = 12, stopGap = 12, bendGap = 2, gap = 2 }

local function with(extra)
	local o = {}
	for k, v in pairs(O) do
		o[k] = v
	end
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return o
end

T.case("Route arrows: spaced by on-screen path length, clear of stops, pointing along the path", function()
	local straight = { pts = { { 0, 0, stop = true }, { 500, 0, stop = true } }, half = 3.5 }
	local arrows = RA.Place({ straight }, O)
	T.eq(#arrows, 5, "every 100 units on 500")
	for i, a in ipairs(arrows) do
		T.ok(a.x >= 12 + 6 and a.x <= 500 - 12 - 6, "clear of the stops: " .. a.x)
		T.eq(a.angle, 0, "pointing along the path")
		T.eq(a.size, 12)
		if i > 1 then
			T.ok(math.abs(a.x - arrows[i - 1].x - 100) < 1e-6, "regular spacing")
		end
	end
	-- Zoomed in twice as far: twice the path on screen, twice the arrows; the gap between them stays the same.
	local zoomed = RA.Place({ { pts = { { 0, 0, stop = true }, { 1000, 0, stop = true } } } }, O)
	T.eq(#zoomed, 10, "same on-screen spacing")
	-- Pointing the other way along a path that runs left.
	local back = RA.Place({ { pts = { { 500, 0, stop = true }, { 0, 0, stop = true } } } }, O)
	T.ok(math.abs(math.abs(back[1].angle) - math.pi) < 1e-6, "pointing left")
	-- Not per segment: a straight path cut into many short segments gets the same arrows as one segment.
	local cut = { { 0, 0, stop = true } }
	for i = 1, 49 do
		cut[#cut + 1] = { i * 10, 0 }
	end
	cut[#cut + 1] = { 500, 0, stop = true }
	T.eq(#RA.Place({ { pts = cut } }, O), 5, "spacing runs across segments")
	-- Too short for an arrow clear of both stops: none.
	T.eq(#RA.Place({ { pts = { { 0, 0, stop = true }, { 30, 0, stop = true } } } }, O), 0, "no clutter on a short leg")
	T.eq(#RA.Place({ { pts = { { 0, 0 } } } }, O), 0, "a single point draws nothing")
	T.eq(#RA.Place({}, O), 0, "no paths")
end)

T.case("Route arrows: a stop in the middle of a path keeps arrows away; a leg with none gets one", function()
	local pts = { { 0, 0, stop = true }, { 100, 0, stop = true }, { 400, 0, stop = true } }
	local arrows = RA.Place({ { pts = pts } }, O)
	for _, a in ipairs(arrows) do
		T.ok(math.abs(a.x - 100) >= 12 + 6 - 1e-6, "clear of the middle stop: " .. a.x)
	end
	-- The first leg (100 units) falls between two spacing marks but still gets one arrow.
	local first = 0
	for _, a in ipairs(arrows) do
		if a.x < 100 then
			first = first + 1
		end
	end
	T.eq(first, 1, "one arrow on the short first leg")
end)

T.case("Route arrows: none over a corner, fine through a small zigzag", function()
	-- A right-angle corner at (200, 0): no arrow whose footprint reaches it.
	local corner = { { 0, 0, stop = true }, { 200, 0 }, { 200, 200, stop = true } }
	local arrows = RA.Place({ { pts = corner } }, with({ spacing = 20 }))
	T.ok(#arrows > 0, "arrows on the straight parts")
	for _, a in ipairs(arrows) do
		T.ok(math.abs(a.x - 200) + math.abs(a.y) >= 6, "clear of the corner: " .. a.x .. "," .. a.y)
		T.ok(math.abs(a.angle) < 1e-6 or math.abs(a.angle - math.pi / 2) < 1e-6, "along a straight part")
	end
	-- A corridor's small zigzag (2 units either side) still carries arrows, pointing along its overall direction.
	local zig = { { 0, 0, stop = true } }
	for i = 1, 39 do
		zig[#zig + 1] = { i * 10, (i % 2) * 2 }
	end
	zig[#zig + 1] = { 400, 0, stop = true }
	local z = RA.Place({ { pts = zig } }, O)
	T.ok(#z >= 3, "arrows along a zigzag: " .. #z)
	for _, a in ipairs(z) do
		T.ok(math.abs(a.angle) < 0.25, "pointing along the corridor")
	end
end)

T.case("Route arrows: none where another part of the route crosses; a stretch walked both ways keeps them apart", function()
	-- A path that crosses itself at (200, 0): out along y = 0, around and back down x = 200.
	local cross = { pts = { { 0, 0, stop = true }, { 400, 0 }, { 400, 150 }, { 200, 150 }, { 200, -150, stop = true } },
		half = 3.5 }
	local arrows = RA.Place({ cross }, with({ spacing = 20 }))
	T.ok(#arrows > 5, "arrows elsewhere: " .. #arrows)
	for _, a in ipairs(arrows) do
		T.ok(dist(a, { x = 200, y = 0 }) >= 6 + 3.5 - 1e-6, "none at the crossing: " .. a.x .. "," .. a.y)
	end
	-- Another route crossing counts too.
	local other = { pts = { { 250, -100, stop = true }, { 250, 100, stop = true } }, half = 3.5, arrows = false }
	local line = { pts = { { 0, 0, stop = true }, { 500, 0, stop = true } }, half = 3.5 }
	local two = RA.Place({ line, other }, with({ spacing = 20 }))
	for _, a in ipairs(two) do
		T.eq(a.path, 1, "a line with arrows = false gets none")
		T.ok(math.abs(a.x - 250) >= 6 + 3.5 - 1e-6, "none where the other route crosses: " .. a.x)
	end
	-- Out and back along the same corridor (5 units apart): arrows both ways, never on top of each other.
	local outBack = { pts = { { 0, 0, stop = true }, { 600, 0 }, { 600, 5 }, { 0, 5, stop = true } }, half = 3.5 }
	local ob = RA.Place({ outBack }, with({ spacing = 60 }))
	local right, left = 0, 0
	for _, a in ipairs(ob) do
		if math.abs(a.angle) < 0.1 then
			right = right + 1
		elseif math.abs(math.abs(a.angle) - math.pi) < 0.1 then
			left = left + 1
		end
	end
	T.ok(right > 0 and left > 0, "both directions shown: " .. right .. " / " .. left)
	local ok, i, j = apart(ob)
	T.ok(ok, "no overlap: " .. tostring(i) .. " " .. tostring(j))
end)

T.case("Route arrows: clear of pins and labels", function()
	local line = { pts = { { 0, 0, stop = true }, { 600, 0, stop = true } }, half = 3.5 }
	local pins = { { 150, 0, 17 } }
	local boxes = { { 300, -8, 380, 8 } }
	local arrows = RA.Place({ line }, with({ spacing = 20, pins = pins, boxes = boxes }))
	T.ok(#arrows > 5, "arrows elsewhere")
	for _, a in ipairs(arrows) do
		T.ok(math.abs(a.x - 150) >= 17 + 6 + 2 - 1e-6, "clear of the pin: " .. a.x)
		T.ok(a.x <= 300 - 6 - 2 + 1e-6 or a.x >= 380 + 6 + 2 - 1e-6, "clear of the label: " .. a.x)
	end
	-- A leg whose only clear place is too narrow for a full-size arrow gets a smaller one there.
	local tight = RA.Place({ { pts = { { 0, 0, stop = true }, { 120, 0, stop = true } } } },
		with({ size = 16, boxes = { { -10, -8, 51, 8 }, { 69, -8, 130, 8 } } }))
	T.eq(#tight, 1, "one arrow on the leg")
	T.eq(tight[1].size, 12, "three quarters of the size")
	T.ok(tight[1].x >= 51 + 6 + 2 - 1e-6 and tight[1].x <= 69 - 6 - 2 + 1e-6, "between the labels: " .. tight[1].x)
	-- Laid-out map items (y down) as obstacles in canvas offsets (y up): a pin and its label below it.
	local items = { { x = 100, y = 50, r = 10, w = 40, h = 15, side = "below", dx = 5, dy = 0 },
		{ x = 200, y = 80, r = 8, w = 0, h = 15 } }
	local ob = RA.Obstacles(items, true)
	T.eq(#ob.pins, 2)
	T.eq(ob.pins[1][2], -50, "y flipped")
	T.eq(#ob.boxes, 1, "only shown labels")
	local b = ob.boxes[1]
	T.ok(b[1] == 85 and b[3] == 125 and b[2] < b[4] and b[4] == -61, "below the pin, slid right, flipped: "
		.. table.concat(b, ","))
end)

T.case("Route arrows: an arrowhead before each stop; only the focused leg; bounded", function()
	local pts = { { 0, 0, stop = true }, { 200, 0, stop = true }, { 400, 0, stop = true } }
	local arrows = RA.Place({ { pts = pts } }, with({ headSize = 16 }))
	local heads = {}
	for _, a in ipairs(arrows) do
		if a.head then
			heads[#heads + 1] = a
		end
	end
	T.eq(#heads, 2, "one before each stop after the first")
	T.eq(heads[1].x, 200 - 12 - 8, "just before the stop")
	T.eq(heads[2].x, 400 - 12 - 8, "and at the end")
	T.eq(heads[1].size, 16, "larger")
	T.ok(apart(arrows), "no overlap with the arrows between")
	-- Without spacing: the arrowheads alone.
	T.eq(#RA.Place({ { pts = pts } }, with({ spacing = false, headSize = 16 })), 2, "only arrowheads")
	-- A range: arrows only between those points.
	local ranged = RA.Place({ { pts = pts, range = { from = 2, to = 3 } } }, with({ headSize = 16 }))
	T.ok(#ranged > 0, "arrows on the focused leg")
	for _, a in ipairs(ranged) do
		T.ok(a.x > 200, "only on the focused leg: " .. a.x)
	end
	-- Bounded per path and in all.
	local long = { pts = { { 0, 0, stop = true }, { 100000, 0, stop = true } } }
	T.eq(#RA.Place({ long }, O), RA.LIMIT, "per path")
	T.eq(#RA.Place({ long, long }, with({ total = 250 })), 250, "in all")
	T.eq(#RA.Place({ long }, with({ limit = 3 })), 3, "a smaller limit")
end)

T.case("Route arrows: a recommended plan's long route (Wailing Caverns) never stacks arrows", function()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns")
	local paths = {}
	for _, route in ipairs(plan.routes) do
		if route.floor == 1 then
			local pts = {}
			for i, p in ipairs(route.points) do
				pts[i] = { p[1] * 900, -p[2] * 600, stop = p.step ~= nil }
			end
			paths[#paths + 1] = { pts = pts, half = 3.5 }
		end
	end
	T.ok(#paths > 0, "the plan has a route")
	local arrows = RA.Place(paths, with({ spacing = 120, size = 17, headSize = 23 }))
	T.ok(#arrows >= 8, "arrows along the route: " .. #arrows)
	local ok, i, j = apart(arrows)
	T.ok(ok, "no two arrows overlap: " .. tostring(i) .. " " .. tostring(j))
	-- Joints: at every inner bend but not at stops.
	for _, path in ipairs(paths) do
		for _, k in ipairs(RA.Joints(path.pts)) do
			T.ok(not path.pts[k].stop and k > 1 and k < #path.pts, "joints at inner bends only")
		end
	end
	T.eq(#RA.Joints({ { 0, 0 }, { 100, 0 }, { 200, 0 } }), 0, "no joint where the path runs straight on")
	T.eq(#RA.Joints({ { 0, 0 }, { 100, 0 }, { 100, 100 } }), 1, "one at a corner")
end)

-- The Routes settings group, through the options table the game's Settings panel shows.
local function routesOptions()
	local registry = LibStub("AceConfigRegistry-3.0")
	local opts = registry:GetOptionsTable("DungeonPlanner", "dialog", "DungeonPlannerTest-1.0")
	return opts.args.routes.args
end

T.case("Routes settings: defaults are the readable look, stored in the profile, every option round-trips", function()
	boot()
	local s = ns.db.settings.routes
	T.eq(s.width, "medium")
	T.eq(s.arrows, "normal")
	T.eq(s.arrowSize, "medium")
	T.eq(s.heads, true)
	T.eq(s.outline, true)
	T.eq(s.opacity, 1)
	T.eq(s.color, 0, "each route's own colour")
	T.eq(s.focusArrows, false)
	T.eq(s.ramp, true, "colour along the route")
	T.ok(ns.adb.profile.settings.routes == s, "in the active profile (AceDB defaults)")
	local args = routesOptions()
	T.ok(args.width and args.arrows and args.arrowSize and args.opacity and args.outline and args.color and args.heads
		and args.focusArrows and args.ramp, "every option in the Routes group")
	local cases = {
		{ "width", "thick", "width", "thick" },
		{ "arrows", "few", "arrows", "few" },
		{ "arrowSize", "large", "arrowSize", "large" },
		{ "opacity", "60", "opacity", 0.6 },
		{ "outline", false, "outline", false },
		{ "color", "3", "color", 3 },
		{ "ramp", false, "ramp", false },
		{ "heads", false, "heads", false },
		{ "focusArrows", true, "focusArrows", true },
	}
	for _, c in ipairs(cases) do
		args[c[1]].set({}, c[2])
		T.eq(ns.db.settings.routes[c[3]], c[4], c[1] .. " stored")
		T.eq(args[c[1]].get({}), c[2], c[1] .. " read back")
	end
	-- A wrong value in a saved profile falls back to the default on load (Defaults.Fill) or when drawn (MapRoutes.Look).
	ns.db.settings.routes.width = "huge"
	T.eq(ns.MapRoutes.Look(1).width, ns.Style.ROUTE.width.medium, "unknown width drawn as medium")
	local broken = { routes = "nonsense" }
	ns.Defaults.Fill(broken, ns.Defaults.settings)
	T.eq(broken.routes.arrows, "normal", "a damaged table refilled")
	for k, v in pairs(ns.Defaults.settings.routes) do
		ns.db.settings.routes[k] = v
	end
end)

T.case("Routes settings: a change redraws the map at once", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local pools = canvas.pools
	local args = routesOptions()
	local before = canvas.counts.arrows
	T.ok(before > 0, "arrows on the map: " .. before)
	T.ok(canvas.counts.lines > 0 and pools.outlines[1]:IsShown(), "outlined lines")
	T.eq(pools.arrows[1]:GetTexture(), ns.MapRoutes.ARROW_EDGE_FILE)
	-- Placed once per redraw, never per frame: one call for the whole map.
	local place, calls = RA.Place, 0
	RA.Place = function(...)
		calls = calls + 1
		return place(...)
	end
	canvas:DrawContent()
	RA.Place = place
	T.eq(calls, 1, "one placement per redraw")
	-- Arrows off: none drawn, the pooled ones hidden.
	args.arrows.set({}, "off")
	T.eq(canvas.counts.arrows, 0, "arrows off")
	T.ok(not pools.arrows[1]:IsShown(), "pooled arrows hidden")
	-- Denser on the same path (a long straight route drawn directly).
	local straight = { routes = { { id = "rs", floor = 1, color = 1, points = { { 0, 0.5, step = 1 }, { 1, 0.5, step = 2 } } } } }
	local function px(x)
		return x * 2000
	end
	local function py(y)
		return -y * 600
	end
	args.arrows.set({}, "many")
	local many = canvas:DrawRoutePaths(straight, 1, px, py, { scale = 1 }).arrows
	args.arrows.set({}, "normal")
	local normal = canvas:DrawRoutePaths(straight, 1, px, py, { scale = 1 }).arrows
	args.arrows.set({}, "few")
	local few = canvas:DrawRoutePaths(straight, 1, px, py, { scale = 1 }).arrows
	T.ok(many > normal and normal > few and few > 0, "many > normal > few: " .. many .. ", " .. normal .. ", " .. few)
	args.arrows.set({}, "normal")
	-- Thick lines; no outline (lines alone, arrows without the baked edge).
	local thin = pools.lines[1]:GetThickness()
	args.width.set({}, "thick")
	T.ok(pools.lines[1]:GetThickness() > thin, "thicker line")
	args.outline.set({}, false)
	T.ok(not pools.outlines[1]:IsShown(), "no outline")
	T.eq(pools.arrows[1]:GetTexture(), ns.MapRoutes.ARROW_FILE, "arrows without the edge")
	-- One colour for every route, and the opacity.
	args.color.set({}, "2")
	args.opacity.set({}, "50")
	local r, g, b, a = pools.lines[1]:GetVertexColor()
	local chosen = { ns.Style.PaletteColor(2) }
	local Distance = ns.RouteLook.Distance
	-- Colour along the route: it starts in the chosen colour and moves away from it towards the end.
	T.ok(Distance({ r, g, b }, chosen) < 0.03, "the route starts in the chosen colour")
	local lr, lg, lb = pools.lines[canvas.counts.lines]:GetVertexColor()
	T.ok(Distance({ lr, lg, lb }, chosen) > 0.2, "and ends far from it")
	T.ok(math.abs(a - 0.5) < 1e-6, "half opacity: " .. a)
	-- Colour along the route off: every line in the chosen colour.
	args.ramp.set({}, false)
	for i = 1, canvas.counts.lines do
		r, g, b = pools.lines[i]:GetVertexColor()
		T.ok(r == chosen[1] and g == chosen[2] and b == chosen[3], "the chosen colour")
	end
	args.ramp.set({}, true)
	-- Only the focused step's leg carries arrows.
	args.focusArrows.set({}, true)
	ns.UI.FocusStep(3, { stay = true })
	ns.UI.RefreshPage()
	local focused = canvas.counts.arrows
	args.focusArrows.set({}, false)
	T.ok(focused < canvas.counts.arrows, "fewer arrows with only the focused leg: " .. focused)
	for k, v in pairs(ns.Defaults.settings.routes) do
		ns.db.settings.routes[k] = v
	end
	ns.UI.RefreshPage()
end)

T.case("Route arrows: only on the visible part, so a long route zoomed in still shows them near its end", function()
	-- Wailing Caverns at the deepest zoom on "many": the whole route is far longer than the caps allow.
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns")
	local route = plan.routes[1]
	local zoom = 8 * 900
	local pts = {}
	for i, p in ipairs(route.points) do
		pts[i] = { p[1] * zoom, -p[2] * zoom, stop = p.step ~= nil }
	end
	local last = pts[#pts]
	local view = { last[1] - 400, last[2] - 300, last[1] + 400, last[2] + 300 }
	local o = with({ spacing = 75, size = 17, headSize = 23 })
	local function inView(arrows)
		local n = 0
		for _, a in ipairs(arrows) do
			if a.x >= view[1] and a.x <= view[3] and a.y >= view[2] and a.y <= view[4] then
				n = n + 1
			end
		end
		return n
	end
	local everywhere = RA.Place({ { pts = pts } }, o)
	T.eq(#everywhere, RA.LIMIT, "without bounds the cap is spent from the start")
	T.ok(inView(everywhere) <= 1, "and at most the end's arrowhead is left for the end: " .. inView(everywhere))
	o.bounds = view
	local visible = RA.Place({ { pts = pts } }, o)
	T.ok(inView(visible) >= 3, "arrows near the route's end: " .. inView(visible))
	for _, a in ipairs(visible) do
		T.ok(a.x + 9 >= view[1] and a.x - 9 <= view[3] and a.y + 9 >= view[2] and a.y - 9 <= view[4], "none outside the bounds")
	end
end)

T.case("Route arrows: a doubled point still makes a corner; bends are not obstacles; spacing at least twice the size", function()
	local corner = { { 0, 0, stop = true }, { 200, 0 }, { 200, 0 }, { 200, 200, stop = true } }
	for _, a in ipairs(RA.Place({ { pts = corner } }, with({ spacing = 20 }))) do
		T.ok(math.abs(a.x - 200) + math.abs(a.y) >= 6, "clear of the corner: " .. a.x .. "," .. a.y)
	end
	T.eq(#RA.Joints(corner), 2, "the doubled corner gets its joints")
	local ob = RA.Obstacles({ { x = 10, y = 0, r = 5, bend = true }, { x = 50, y = 0, r = 10 } }, true)
	T.eq(#ob.pins, 1, "a bend point is not an obstacle")
	local tight = RA.Place({ { pts = { { 0, 0, stop = true }, { 600, 0, stop = true } } } }, with({ spacing = 5 }))
	for i = 2, #tight do
		T.ok(tight[i].x - tight[i - 1].x >= 24 - 1e-6, "at least twice the size apart")
	end
end)

T.case("Routes: one colour for every plan route reaches stops; another addon's route keeps its own", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.db.settings.routes.color = 2
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local want = { ns.Style.PaletteColor(2) }
	local plan0 = ns.UI.ctx:Plan()
	-- Colour along the route: each ring in the route's colour at its stop, further from the chosen colour the later
	-- the stop.
	local byIndex = {}
	for _, p in ipairs(canvas.pools.points) do
		if p:IsShown() and p.ring:IsShown() then
			local route = ns.Util.FindById(plan0.routes, p.routeId)
			local r, g, b = p.ring:GetVertexColor()
			local er, eg, eb = ns.MapRoutes.StopColor(route, p.pointIndex)
			T.ok(r == er and g == eg and b == eb, "a stop ring in the colour at its place")
			byIndex[#byIndex + 1] = { i = p.pointIndex, d = ns.RouteLook.Distance({ r, g, b }, want) }
		end
	end
	T.ok(#byIndex > 3, "stops drawn: " .. #byIndex)
	table.sort(byIndex, function(x, y)
		return x.i < y.i
	end)
	T.ok(byIndex[1].d < 0.05, "the first stop near the chosen colour: " .. byIndex[1].d)
	T.ok(byIndex[#byIndex].d > 0.15, "the last far from it: " .. byIndex[#byIndex].d)
	for k = 2, #byIndex do
		T.ok(byIndex[k].d >= byIndex[k - 1].d - 1e-6, "further along, further from the start colour")
	end
	-- Colour along the route off: every ring in the chosen colour.
	ns.db.settings.routes.ramp = false
	ns.UI.RefreshPage()
	local rings = 0
	for _, p in ipairs(canvas.pools.points) do
		if p:IsShown() and p.ring:IsShown() then
			local r, g, b = p.ring:GetVertexColor()
			T.ok(r == want[1] and g == want[2] and b == want[3], "a stop ring in the chosen colour")
			rings = rings + 1
		end
	end
	T.ok(rings > 0, "stops drawn: " .. rings)
	-- A provider's route (Data/Providers.lua Routes) beside a plan route.
	local plan = { routes = { { id = "own", floor = 1, color = 1, points = { { 0.1, 0.1, step = 1 }, { 0.9, 0.1, step = 2 } } } } }
	local extra = { { id = "provider1", floor = 1, color = 6, mapSpace = true, points = { { 0.1, 0.5 }, { 0.9, 0.5 } } } }
	local function px(x)
		return x * 1000
	end
	local function py(y)
		return -y * 600
	end
	canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1, extra = extra, mx = px, my = py })
	local r1, g1, b1 = canvas.pools.lines[1]:GetVertexColor()
	local r2, g2, b2 = canvas.pools.lines[2]:GetVertexColor()
	local teal = { ns.Style.PaletteColor(6) }
	T.ok(r1 == want[1] and g1 == want[2] and b1 == want[3], "the plan's route in the chosen colour")
	T.ok(r2 == teal[1] and g2 == teal[2] and b2 == teal[3], "the provider's route keeps its colour")
	-- With colour along the route the plan's route changes along its length; the provider's keeps its one colour.
	ns.db.settings.routes.ramp = true
	local n = canvas:DrawRoutePaths(plan, 1, px, py, { scale = 1, extra = extra, mx = px, my = py }).lines
	r2, g2, b2 = canvas.pools.lines[n]:GetVertexColor()
	T.ok(r2 == teal[1] and g2 == teal[2] and b2 == teal[3], "the provider's route still in its colour")
	r1, g1, b1 = canvas.pools.lines[n - 1]:GetVertexColor()
	T.ok(ns.RouteLook.Distance({ r1, g1, b1 }, want) > 0.2, "the plan's route ends in another colour")
	ns.db.settings.routes.color = 0
	ns.UI.RefreshPage()
end)

T.case("Routes settings: run mode's map follows a change at once; arrow options wait while arrows are off", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.FocusStep(3, { stay = true })
	ns.RunMode.Show()
	ns.RunMode.Refresh()
	local run = _G.DungeonPlannerRunFrame.map
	local args = routesOptions()
	local before = run.pools.lines[1]:GetThickness()
	args.width.set({}, "thick")
	T.ok(run.pools.lines[1]:GetThickness() > before, "run mode's lines thicker")
	args.arrows.set({}, "off")
	T.eq(run.counts.arrows, 0, "run mode's arrows off")
	T.ok(args.heads.disabled() and args.arrowSize.disabled() and args.focusArrows.disabled(), "arrow options greyed out")
	args.arrows.set({}, "normal")
	T.ok(not args.heads.disabled(), "available again")
	args.width.set({}, "medium")
	ns.RunMode.Hide()
end)

T.case("Route arrows wait while a route point is dragged or the window is resized, then come back", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local before = canvas.counts.arrows
	T.ok(before > 0, "arrows to begin with")
	local place, calls = RA.Place, 0
	RA.Place = function(...)
		calls = calls + 1
		return place(...)
	end
	canvas.drag = { mode = "point" }
	canvas:DrawContent()
	canvas:DrawContent()
	T.eq(calls, 0, "no placement while dragging")
	T.ok(not canvas.pools.arrows[1]:IsShown(), "arrows hidden meanwhile")
	canvas.drag = { mode = "idle" }
	mock.Advance(0.2)
	T.eq(calls, 1, "placed once when the drag ends")
	T.eq(canvas.counts.arrows, before, "all back")
	ns.sizingWindow = _G.DungeonPlannerMainFrame
	mock.SetMouseButtonDown("LeftButton", true) -- the size grip is held
	canvas:DrawContent()
	mock.Advance(0.2)
	T.eq(calls, 1, "none while the window is resized")
	ns.sizingWindow = nil
	mock.SetMouseButtonDown("LeftButton", false)
	mock.Advance(0.2)
	T.eq(calls, 2, "placed once the resize ends")
	RA.Place = place
end)

-- Plan point (x, y) of the map shown, as the pointer's screen position.
local function pointAt(view, x, y)
	local c = view.canvas
	local s = c:GetEffectiveScale()
	return (c:GetLeft() + x * c:GetWidth()) * s, (c:GetTop() - y * c:GetHeight()) * s
end

T.case("Route arrows: a real route point drag hides them; the drop places them in its own redraw", function()
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns"))
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	ns.UI.ctx.tool, ns.UI.ctx.floor = "select", 1
	ns.db.ui.snapRoutes = false
	map:RefreshNow()
	local canvas = map.canvas
	T.ok(canvas.counts.arrows > 0, "arrows to begin with")
	local pin
	for _, p in ipairs(canvas.pools.points) do
		if p:IsShown() and p.routeId then
			pin = p
			break
		end
	end
	T.ok(pin, "a numbered stop's pin")
	local pt = ns.Util.FindById(copy.routes, pin.routeId).points[pin.pointIndex]
	local real = _G.GetCursorPosition
	local tx, ty = pt[1] + 0.01, pt[2]
	_G.GetCursorPosition = function()
		return pointAt(canvas, tx, ty)
	end
	pin:GetScript("OnDragStart")(pin)
	mock.Advance(0.016) -- one frame: OnDragUpdate moves the point and redraws the map
	T.ok(canvas.drag.mode == "point" and canvas.drag.moved, "dragging the point")
	T.eq(canvas.counts.arrows, 0, "no arrows while it moves")
	T.ok(not canvas.pools.arrows[1]:IsShown(), "hidden")
	pin:GetScript("OnDragStop")(pin)
	T.eq(canvas.drag.mode, "idle")
	T.ok(canvas.counts.arrows > 0, "placed by the drop's redraw, before any timer: " .. canvas.counts.arrows)
	T.ok(canvas.pools.arrows[1]:IsShown(), "shown")
	_G.GetCursorPosition = real
	ns.DB.DeletePlan(copy.id)
end)

T.case("Route arrows: the size grip holds them until its release, the window hides, or no button is held", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local f = _G.DungeonPlannerMainFrame
	local canvas = f.instancePage.panels.map.canvas
	local grip = f.grip
	local before = canvas.counts.arrows
	T.ok(before > 0, "arrows to begin with")
	local place, calls = RA.Place, 0
	RA.Place = function(...)
		calls = calls + 1
		return place(...)
	end
	-- The grip pressed and released with the left button held in between (mock input, as the client reports it).
	local function press()
		mock.SetMouseButtonDown("LeftButton", true)
		mock.FireScript(grip, "OnMouseDown", "LeftButton")
	end
	local function release()
		mock.SetMouseButtonDown("LeftButton", false)
		mock.FireScript(grip, "OnMouseUp", "LeftButton")
	end
	local ok, err = pcall(function()
		-- Pressed and released.
		press()
		T.eq(ns.sizingWindow, f, "resizing")
		canvas:DrawContent()
		T.eq(canvas.counts.arrows, 0, "none while resizing")
		mock.Advance(0.2)
		T.eq(calls, 0, "the timer waits")
		release()
		T.eq(ns.sizingWindow, nil, "released")
		mock.Advance(0.2)
		T.eq(calls, 1, "placed once")
		T.eq(canvas.counts.arrows, before, "all back")
		-- The window hidden mid-resize (Escape): its grip gets no release.
		press()
		canvas:DrawContent()
		f:Hide()
		T.eq(ns.sizingWindow, nil, "the resize ends with the window")
		mock.SetMouseButtonDown("LeftButton", false)
		f:Show()
		canvas:DrawContent()
		mock.Advance(0.2)
		T.ok(canvas.counts.arrows > 0, "arrows when it is back")
		-- The release lost: once no mouse button is held, the timer stops waiting.
		press()
		canvas:DrawContent()
		calls = 0
		mock.Advance(0.2)
		T.eq(calls, 0, "a button still held: waiting")
		mock.SetMouseButtonDown("LeftButton", false) -- released away from the grip: no OnMouseUp
		mock.Advance(0.2)
		T.eq(calls, 1, "no button held: placed")
		T.eq(ns.sizingWindow, nil, "and the resize counts as over")
		T.eq(canvas.counts.arrows, before)
	end)
	mock.ResetInput()
	ns.sizingWindow = nil
	RA.Place = place
	if not ok then
		error(err, 0)
	end
end)

T.case("Route arrows: placed a view's size beyond the visible map too, so a pan shows them on what it reveals", function()
	boot()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	-- Zoomed in on the route's middle stop.
	local route = plan.routes[1]
	local mid = route.points[math.floor(#route.points / 2)]
	local vw, vh = canvas:GetWidth(), canvas:GetHeight()
	canvas.zoom = 4
	local w, h = canvas:BaseSize()
	local s = canvas:Scale()
	canvas.ox, canvas.oy = vw / 2 - mid[1] * w * s, vh / 2 - mid[2] * h * s
	canvas:Layout()
	-- The visible map in canvas offsets (y up) and the arrows placed outside it.
	local x1, x2, y1, y2 = -canvas.ox, vw - canvas.ox, canvas.oy - vh, canvas.oy
	local beyond, inside, far = 0, 0, 0
	for _, m in ipairs(canvas.routeMarks or {}) do
		local dx = math.max(x1 - m.x, m.x - x2, 0)
		local dy = math.max(y1 - m.y, m.y - y2, 0)
		if dx > 60 or dy > 60 then
			beyond = beyond + 1
		elseif dx == 0 and dy == 0 then
			inside = inside + 1
		end
		if dx > vw + 60 or dy > vh + 60 then
			far = far + 1
		end
	end
	T.ok(inside > 0, "arrows on the visible map: " .. inside)
	T.ok(beyond > 0, "and on the map a pan would reveal: " .. beyond)
	T.eq(far, 0, "none farther than a view's size")
	canvas:ResetView()
end)

T.case("Map labels keep clear of the coordinate readout above the floor switcher on a map with floors", function()
	boot()
	ns.db.settings.showCoordinates = true
	ns.UI.SelectPlan("b:the-deadmines")
	ns.UI.SelectTab("map")
	ns.UI.GoToFloor(1)
	ns.UI.RefreshPage()
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	T.ok(map.floorBar:IsShown(), "the floor switcher is shown")
	local c, inner = canvas.coords, canvas.canvas
	local above = false
	for _, p in ipairs(c._points or {}) do
		above = above or (p[1] == "BOTTOMRIGHT" and p[2] == map.floorBar and p[3] == "TOPRIGHT")
	end
	T.ok(above, "the floor switcher moves the readout above itself")
	-- Where the client puts them (the offline mock resolves no anchors): the map's canvas with its top left at
	-- (100, 700), the readout's bottom right at (580, 236), just above the switcher, far from the map's bottom corner.
	c.GetRight, c.GetBottom = function()
		return 580
	end, function()
		return 236
	end
	inner.GetLeft, inner.GetTop = function()
		return 100
	end, function()
		return 700
	end
	local ok, err = pcall(function()
		canvas:DrawContent()
		local box, xs = canvas.coordsBox, ns.Style.SPACE.xs
		T.ok(box, "a keep-out box for the readout")
		-- In canvas units (y down): right edge 480, bottom 464.
		local function near(a, b)
			return math.abs(a - b) < 1e-6
		end
		T.ok(near(box[3], 480 + xs) and near(box[4], 464 + xs), "at the readout's right and bottom edges: " .. box[3]
			.. ", " .. box[4])
		T.ok(near(box[1], 480 - canvas.coordsW - xs) and near(box[2], 464 - canvas.coordsH - xs),
			"with the room of its widest text: " .. box[1] .. ", " .. box[2])
	end)
	c.GetRight, c.GetBottom, inner.GetLeft, inner.GetTop = nil, nil, nil, nil
	canvas:DrawContent()
	if not ok then
		error(err, 0)
	end
end)
