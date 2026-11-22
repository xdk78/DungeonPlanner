-- How a route's line looks along its length (Model/RouteLook.lua, drawn by UI/MapRoutes.lua): the colour ramp from the
-- route's colour to its partner (anchored, gradual, readable on parchment and dark map art, and with colour
-- blindness), the pieces and dashes a path is drawn in (bounded, only on the way back through a corridor), and that the
-- map and run mode follow the "Colour along the route" setting. Also: a route bend's handle under a pin is left out.
local T = ...
local ns, mock = T.ns, T.mock
local RL = ns.RouteLook

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

-- Colour vision deficiency, simulated (Machado, Oliveira and Fernandes 2009, severity 1, on linear RGB): test tooling
-- only, to check that a ramp's start and end stay apart for players with red-green or blue-yellow colour blindness.
local CVD = {
	deuteranopia = { { 0.367322, 0.860646, -0.227968 }, { 0.280085, 0.672501, 0.047413 }, { -0.011820, 0.042940, 0.968881 } },
	protanopia = { { 0.152286, 1.052583, -0.204868 }, { 0.114503, 0.786281, 0.099216 }, { -0.003882, -0.048116, 1.051998 } },
	tritanopia = { { 1.255528, -0.076749, -0.178779 }, { -0.078411, 0.930809, 0.147602 }, { 0.004733, 0.691367, 0.303900 } },
}
local function lin(c)
	return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local function gam(c)
	c = math.max(0, math.min(1, c))
	return c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055
end
local function simulate(c, m)
	local r, g, b = lin(c[1]), lin(c[2]), lin(c[3])
	local out = {}
	for i = 1, 3 do
		out[i] = gam(m[i][1] * r + m[i][2] * g + m[i][3] * b)
	end
	return out
end

-- Every palette colour a route can have: the usual set and the colour-blind one.
local function paletteColours()
	local out = {}
	for _, key in ipairs({ "palette", "paletteColorblind" }) do
		for i, c in ipairs(ns.Style.current[key]) do
			out[#out + 1] = { c[1], c[2], c[3], name = key .. " " .. i }
		end
	end
	return out
end

T.case("Route colour ramp: anchored on the route's colour, moving steadily away from it, in the sRGB gamut", function()
	local O = ns.Style.ROUTE.ramp
	for _, c in ipairs(paletteColours()) do
		local ramp = RL.Ramp(c[1], c[2], c[3], O)
		local r0, g0, b0 = RL.At(ramp, 0)
		T.ok(r0 == c[1] and g0 == c[2] and b0 == c[3], c.name .. ": starts in the route's own colour")
		local last, prev = 0, { r0, g0, b0 }
		for i = 1, 64 do
			local col = { RL.At(ramp, i / 64) }
			for k = 1, 3 do
				T.ok(col[k] >= 0 and col[k] <= 1, c.name .. ": in the gamut")
			end
			local d = RL.Distance(col, c)
			T.ok(d >= last - 1e-3, c.name .. ": further from the start along the route (" .. i .. ")")
			T.ok(RL.Distance(col, prev) < 0.03, c.name .. ": gradual, no jump (" .. i .. ")")
			last, prev = d, col
		end
		T.ok(last >= 0.17, c.name .. ": the end reads apart from the start: " .. last)
		local er, eg, eb = RL.End(c[1], c[2], c[3], O)
		T.ok(RL.Distance({ RL.At(ramp, 1) }, { er, eg, eb }) < 1e-6, c.name .. ": ends in its partner colour")
	end
	-- The default red runs through magenta to a blue.
	local red = ns.Style.current.palette[1]
	local mr, _, mb = RL.At(RL.Ramp(red[1], red[2], red[3], O), 0.5)
	local er, eg, eb = RL.End(red[1], red[2], red[3], O)
	T.ok(mb > 0.5 and mr > 0.5, "magenta in the middle")
	T.ok(eb > er and eb > eg, "blue at the end")
end)

T.case("Route colour ramp: readable on parchment and on dark map art, and with colour blindness", function()
	local O = ns.Style.ROUTE.ramp
	for _, c in ipairs(paletteColours()) do
		local ramp = RL.Ramp(c[1], c[2], c[3], O)
		for i = 0, 16 do
			local col = { RL.At(ramp, i / 16) }
			local paper, dark = RL.Distance(col, O.paper), RL.Distance(col, O.dark)
			T.ok(paper >= 0.08, c.name .. ": apart from parchment at " .. i .. "/16: " .. paper)
			T.ok(dark >= 0.33, c.name .. ": apart from dark map art at " .. i .. "/16: " .. dark)
		end
		local s, e = { RL.At(ramp, 0) }, { RL.At(ramp, 1) }
		for kind, m in pairs(CVD) do
			local d = RL.Distance(simulate(s, m), simulate(e, m))
			T.ok(d >= (kind == "tritanopia" and 0.12 or 0.15), c.name .. ": start and end apart with " .. kind .. ": " .. d)
		end
	end
	-- The dimmed rest of a route turns greyer, keeping its lightness (not paler).
	local r, g, b = RL.Desaturate(0.86, 0.2, 0.16, 0.5)
	T.ok(math.max(r, g, b) - math.min(r, g, b) < 0.4, "less saturated")
	T.ok(math.abs(RL.Oklab(r, g, b) - RL.Oklab(0.86, 0.2, 0.16)) < 0.06, "about as light")
end)

T.case("Route pieces: long stretches cut so the colour flows, bounded; dashes only on the way back", function()
	-- No ramp, no dashes: one piece per segment.
	local plain = { { 0, 0 }, { 100, 0 }, { 100, 100 } }
	T.eq(#RL.Pieces(plain, {}), 2)
	-- With the ramp: a stretch longer than 1/steps of the path is cut, at most `split` pieces, joined end to end.
	local long = RL.Pieces({ { 0, 0 }, { 480, 0 } }, { steps = 48, split = 8 })
	T.eq(#long, 8, "capped")
	for i = 2, #long do
		T.ok(math.abs(long[i][1] - long[i - 1][3]) < 1e-9, "contiguous")
	end
	T.eq(long[#long][3], 480)
	-- Out and back along one corridor: only the second pass is the way back.
	local lanes = ns.RouteLegs.Lanes({ { 0, 0, stop = true }, { 200, 0, stop = true }, { 0, 0, stop = true } },
		{ shift = 4, near = 8, yUp = true })
	for k = 1, #lanes do
		T.eq(lanes[k].back == true, k == #lanes, "point " .. k .. ": back only at the end of the way back")
	end
	local pieces, dashes = RL.Pieces(lanes, { dash = { on = 10, off = 6 }, limit = 400 })
	T.eq(dashes, math.ceil(200 / 16), "dashes along the 200 long way back")
	local solid = 0
	for _, p in ipairs(pieces) do
		if p.dash then
			T.eq(p[5], #lanes, "dashes only on the way back")
			T.ok(math.abs(p[2] - 4) < 1e-9 and math.abs(p[4] - 4) < 1e-9, "in its lane")
			T.ok(math.abs(p[1] - p[3]) <= 10 + 1e-9, "no longer than a dash")
		else
			solid = solid + 1
		end
	end
	T.eq(solid, 2, "the way there and the turn stay solid")
	-- A path that never comes back has no way back.
	for _, p in ipairs(ns.RouteLegs.Lanes({ { 0, 0 }, { 100, 0 }, { 100, 100 } }, { shift = 4, near = 8 })) do
		T.ok(not p.back, "nothing marked")
	end
	-- Bounded: many dashes become fewer, longer ones.
	local _, capped = RL.Pieces(lanes, { dash = { on = 1, off = 1 }, limit = 10 })
	T.ok(capped <= 11, "at most the limit (and one more per stretch): " .. capped)
end)

T.case("Route look on the map: dashes on Wailing Caverns' way back, bounded; the setting redraws the map and run mode", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local counts = canvas.routeCounts
	T.ok(counts.dashes > 0 and counts.dashes <= ns.Style.ROUTE.maxDashes, "dashes: " .. counts.dashes)
	T.ok(counts.outlines < counts.lines, "the way back keeps one casing under its dashes")
	local function lastColour(view)
		return { view.pools.lines[view.routeCounts.lines]:GetVertexColor() }
	end
	local first = { canvas.pools.lines[1]:GetVertexColor() }
	T.ok(RL.Distance(lastColour(canvas), first) > 0.2, "the route's end in another colour than its start")
	local args = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("DungeonPlanner", "dialog", "DungeonPlannerTest-1.0")
		.args.routes.args
	args.ramp.set({}, false)
	local base = { ns.MapRoutes.Color(ns.UI.ctx:Plan().routes[1], true) }
	T.ok(RL.Distance(lastColour(canvas), base) < 1e-6, "off: the map's route in one colour")
	args.ramp.set({}, true)
	ns.UI.FocusStep(3, { stay = true })
	ns.RunMode.Show()
	ns.RunMode.Refresh()
	local run = _G.DungeonPlannerRunFrame.map
	local runBefore = lastColour(run)
	args.ramp.set({}, false)
	T.ok(RL.Distance(lastColour(run), runBefore) > 1e-3, "run mode's map redrawn too")
	args.ramp.set({}, true)
	ns.RunMode.Hide()
end)

T.case("Marker details: a long title stops before the close button, cut after a word, whole in its tooltip", function()
	boot()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "wailing-caverns")
	ns.UI.SelectTab("map")
	ns.UI.ctx.selectedMarker = "m12" -- "Druids of the Fang and vipers near Anacondra"
	ns.UI.RefreshPage()
	local ed = _G.DungeonPlannerMainFrame.instancePage.panels.map.editor
	T.ok(ed:IsVisible(), "the details pane is open")
	-- The mock does not lay out anchors (the dump view pack-detail checks the layout): the title's right edge is tied
	-- to the close button's left.
	local tied = false
	for i = 1, ed.heading:GetNumPoints() do
		local point, rel, relPoint = ed.heading:GetPoint(i)
		tied = tied or (point == "RIGHT" and rel == ed.close and relPoint == "LEFT")
	end
	T.ok(tied, "the title ends before the close button")
	ns.UI.ctx.selectedMarker = nil
	ns.UI.RefreshPage()
end)

T.case("Route bends: a bend's handle under a pin is left out, unless it is being dragged", function()
	local L = ns.MapLayout
	local items = {
		{ x = 100, y = 100, r = 10, kind = "stop", w = 0, h = 13 },
		{ x = 106, y = 94, r = 4.5, kind = "pin", w = 0, h = 13, bend = true },
		{ x = 160, y = 100, r = 4.5, kind = "pin", w = 0, h = 13, bend = true },
		{ x = 98, y = 103, r = 4.5, kind = "pin", w = 0, h = 13, bend = true, keep = true },
	}
	L.Nudge(items)
	T.ok(items[2].covered, "under the stop: left out")
	T.ok(not items[3].covered, "clear of it: shown")
	T.ok(not items[4].covered, "being dragged: shown")
	T.ok(not items[2].moved and not items[1].moved, "nothing moved for it")
	-- On the map: an own route being edited, a bend right beside a numbered stop.
	boot()
	local copy = ns.UI.CopyPlan(ns.Bundled.Get(ns.Bundled.PREFIX .. "wailing-caverns"))
	copy.routes = { { id = "rb", floor = 1, color = 1, points = {
		{ 0.3, 0.5, step = 1 }, { 0.302, 0.502 }, { 0.5, 0.5 }, { 0.7, 0.5, step = 2 } } } }
	ns.UI.ctx.tool, ns.UI.ctx.floor, ns.UI.ctx.activeRoute = "route", 1, "rb"
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local function pinOf(index)
		for _, p in ipairs(canvas.pools.points) do
			if p.routeId == "rb" and p.pointIndex == index and p:IsShown() then
				return p
			end
		end
	end
	T.ok(pinOf(1) and pinOf(4), "both stops shown")
	T.ok(not pinOf(2), "the bend beside stop 1 left out")
	T.ok(pinOf(3), "the bend in the open shown")
	canvas.drag = { mode = "point", routeId = "rb", index = 2 }
	canvas:DrawContent()
	T.ok(pinOf(2), "shown while it is dragged")
	canvas.drag = { mode = "idle" }
	ns.UI.ctx.tool, ns.UI.ctx.activeRoute = "select", nil
	ns.DB.DeletePlan(copy.id)
end)
