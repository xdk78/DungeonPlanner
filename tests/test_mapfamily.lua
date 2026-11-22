-- One look for every map and its pins: rings centred on what they circle (UI/Art.lua Art.PlaceRing, measured in the
-- client's files), minimap floors in the parchment colours (UI/MapCanvas.lua ArtStyle), route chevrons turned along
-- their path (UI/MapPins.lua TurnedCoords), map stops numbered like the steps (Model/Steps.lua StopNumbers), a stop
-- near a boss already stepped not doubling it, labels kept inside the visible map (Model/MapLayout.lua), quest items
-- by their own icon and name, and other addons' drawn maps first again (Config/DB.lua ProviderMapsFirst).
local T = ...
local ns, mock = T.ns, T.mock
local Steps = ns.Steps

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

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

-- The ring texture is anchored by its centre on `host`'s centre, square, `size` times the ring's factor.
local function centredRing(ring, host, size, key, what)
	local pts = ring._points or {}
	T.eq(#pts, 1, what .. ": one anchor")
	local p = pts[1]
	T.eq(p[1], "CENTER", what .. ": by its centre")
	T.eq(p[2], host, what .. ": on the art")
	T.eq(p[3], "CENTER", what .. ": on the art's centre")
	T.ok(near(p[4], 0) and near(p[5], 0), what .. ": no offset")
	local w, h = ring:GetSize()
	T.ok(near(w, h), what .. ": square")
	T.ok(near(w, size * ns.Art.SPECS[key].ring), what .. ": one size per art size")
end

T.case("Rings: each crop is a square centred on its ring as measured in the client's file", function()
	local pin = ns.Art.SPECS.pinRing
	local c, m = pin.coords, pin.centre
	T.ok(near(c[2] - c[1], c[4] - c[3]), "square crop")
	T.ok(near((c[1] + c[2]) / 2, m[1] / m[3]) and near((c[3] + c[4]) / 2, m[2] / m[3]), "centred on the ring (20, 19)")
	-- The art fills the ring's hole (inner radius 12.5 of 64 px): the art's edge sits under the gold.
	local holeShare = 2 * 12.5 / ((c[2] - c[1]) * m[3])
	T.ok(1 / pin.ring >= holeShare * 0.95 and 1 / pin.ring <= holeShare * 1.1, "art about the size of the hole")
	local boss = ns.Art.SPECS.bossRing
	T.ok(boss.ring > 1, "the boss ring stands out round the portrait")
end)

T.case("Rings: step badges, map pins, list icons and portraits all centre their ring", function()
	boot()
	local W = ns.Widgets
	local parent = CreateFrame("Frame", nil, UIParent)
	local icon = W.RoundIcon(parent, 18, "pinRing")
	centredRing(icon.ring, icon, 18, "pinRing", "round icon")
	local portrait = W.Portrait(parent, 40)
	centredRing(portrait.ring, portrait, 40, "bossRing", "portrait")
	-- The side panel: every kind of step (Ragefire Chasm has an entrance, pulls, bosses, a quest item and moves).
	ns.UI.SelectPlan("b:ragefire-chasm")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local side = _G.DungeonPlannerMainFrame.instancePage.side
	T.ok(side, "the side panel")
	-- From the top: the step list keeps its scroll offset across plans, and an earlier file may have scrolled it down.
	side.list:ScrollTo(1)
	local kinds = {}
	for _, row in ipairs(side.list.rows) do
		if row:IsShown() and row.badge then
			centredRing(row.badge.ring, row.badge, 24, "pinRing", "step badge")
			kinds[#kinds + 1] = true
		end
	end
	T.ok(#kinds >= 8, "the rows checked")
	-- Map pins: bosses in the Adventure Guide's ring, the rest in the minimap ring.
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local checked = { bossRing = 0, pinRing = 0 }
	for _, b in ipairs(canvas.pools.pins) do
		if b:IsShown() and b.ring:IsShown() and b.dpRingKey then
			local w = b:GetSize()
			centredRing(b.ring, b, w, b.dpRingKey, "map pin")
			checked[b.dpRingKey] = checked[b.dpRingKey] + 1
		end
	end
	T.ok(checked.bossRing > 0 and checked.pinRing > 0, "boss and other pins checked")
end)

T.case("Map colours: minimap floors join the parchment family unless the player picks the game's", function()
	local MC = ns.MapCanvas
	local mini = { source = "minimap", textures = { 1 } }
	local s = MC.ArtStyle(mini, "parchment")
	T.eq(s.name, "parchment")
	T.ok(s.paper and s.desaturate and s.vignette and s.lift, "parchment under, grey tinted brown, lifted, dark edges")
	T.ok(s.tint[1] >= s.tint[2] and s.tint[2] >= s.tint[3], "a warm tint")
	T.eq(MC.ArtStyle(mini, "game").name, "art", "the game's colours")
	T.eq(MC.ArtStyle({ source = "tiles", textures = { 1 } }, "parchment").name, "art", "the old tiles untouched")
	T.eq(MC.ArtStyle({ source = "provider", textures = { 1 } }, "parchment").name, "art", "a drawn map untouched")
	T.eq(MC.ArtStyle(nil, "parchment").name, "grid", "no art: the parchment grid")
	T.eq(ns.Defaults.settings.mapColors, "parchment", "the default")
end)

-- Where a texture with these coordinates (UL, LL, UR, LR) shows texture point (u, v): s right, t down over the quad.
local function whereShown(tc, u, v)
	local ux, uy = tc[5] - tc[1], tc[6] - tc[2] -- along s
	local vx, vy = tc[3] - tc[1], tc[4] - tc[2] -- along t
	local du, dv = u - tc[1], v - tc[2]
	local det = ux * vy - uy * vx
	return (du * vy - dv * vx) / det, (ux * dv - uy * du) / det
end

T.case("Route chevrons: turned in their texture coordinates to point along the path", function()
	local MP = ns.MapPins
	-- The chevron points up unturned: its tip is at the top centre of the texture.
	local tipU, tipV = 0.5, 11 / 32
	local function tip(dx, dy) -- a segment's direction in canvas offsets (y up)
		return whereShown(MP.TurnedCoords(math.atan2(dy, dx) - math.pi / 2), tipU, tipV)
	end
	local s, t = tip(0, -1)
	T.ok(t > 0.6 and near(s, 0.5, 0.01), "a segment going down the screen: the chevron points down")
	s, t = tip(0, 1)
	T.ok(t < 0.4 and near(s, 0.5, 0.01), "going up: up")
	s, t = tip(1, 0)
	T.ok(s > 0.6 and near(t, 0.5, 0.01), "going right: right")
	s, t = tip(-1, 0)
	T.ok(s < 0.4 and near(t, 0.5, 0.01), "going left: left")
	local tc = MP.TurnedCoords(0)
	T.ok(near(tc[1], 0) and near(tc[2], 0) and near(tc[7], 1) and near(tc[8], 1), "unturned: the plain coordinates")
	-- On the map: the chevrons of Ragefire Chasm's first leg (the portal down the corridor) point down.
	boot()
	ns.UI.SelectPlan("b:ragefire-chasm")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local down = 0
	for _, a in ipairs(canvas.pools.arrows) do
		if a:IsShown() then
			local c = { a:GetTexCoord() }
			T.eq(#c, 8, "eight coordinates")
			local _, tt = whereShown(c, tipU, tipV)
			if tt > 0.6 then
				down = down + 1
			end
			T.eq(a._rotation, nil, "no SetRotation")
		end
	end
	T.ok(down > 0, "some chevrons point down")
end)

T.case("Steps: a stop near a boss that already has its step is a move, not the boss again", function()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	local list = Steps.Build(plan)
	local seen = {}
	for _, s in ipairs(list) do
		if s.kind == "boss" then
			T.eq(seen[s.encounter], nil, "one step per boss: " .. tostring(s.encounter))
			seen[s.encounter] = true
		end
	end
	T.eq(list[3].kind, "boss", "Oggleflint")
	T.eq(list[4].kind, "move", "the stop that walks on past him")
	T.eq(list[4].stop, 4)
	-- Every recommended plan: no boss twice.
	for _, p in ipairs(ns.Bundled.All()) do
		local bosses = {}
		for _, s in ipairs(Steps.Build(p)) do
			if s.kind == "boss" then
				T.eq(bosses[s.encounter], nil, p.id .. ": boss " .. tostring(s.encounter) .. " once")
				bosses[s.encounter] = true
			end
		end
	end
end)

T.case("Map stops show the side panel's step numbers", function()
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	local list = Steps.Build(plan)
	local numbers = Steps.StopNumbers(list)
	T.eq(Steps.StopNumbers(list), numbers, "cached per list")
	local route = plan.routes[1]
	local n = 0
	for i, pt in ipairs(route.points) do
		if pt.step then
			local k = numbers[route.id][i]
			T.ok(k, "stop " .. pt.step .. " has a step")
			T.eq(list[k].stop, pt.step, "the step it makes")
			T.ok(list[k].kind ~= "pull" or not list[k + 1] or list[k + 1].stop ~= pt.step,
				"a stop on a boss with a pull shows the boss's number")
			n = n + 1
		end
	end
	T.eq(n, 8)
	T.eq(numbers[route.id][#route.points], #list, "the last stop is the last step")
	-- On the map.
	boot()
	ns.UI.SelectPlan("b:ragefire-chasm")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local canvas = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
	local shown = {}
	for _, p in ipairs(canvas.pools.points) do
		if p:IsShown() and p.text:GetText() ~= "" then
			shown[#shown + 1] = tonumber(p.text:GetText())
		end
	end
	table.sort(shown)
	T.eq(table.concat(shown, ","), "1,2,3,4,6,8,10,11", "step numbers on the stops")
end)

T.case("Map labels stay inside the visible map", function()
	local ML = ns.MapLayout
	local bounds = { 0, 0, 400, 300 }
	-- A pin near the left edge with a long label: below it, slid right to fit.
	local items = { { x = 20, y = 100, r = 10, kind = "disc", w = 200, h = 15, prio = 1 } }
	ML.Labels(items, nil, bounds)
	T.eq(items[1].side, "below")
	local box = ML.LabelBox(items[1], "below")
	T.ok(box[1] + items[1].dx >= 0, "inside on the left")
	T.ok(box[1] + items[1].dx <= items[1].x and box[3] + items[1].dx >= items[1].x, "still under its pin")
	-- At the bottom-left corner: above it.
	items = { { x = 20, y = 295, r = 10, kind = "disc", w = 120, h = 15, prio = 1 } }
	ML.Labels(items, nil, bounds)
	T.eq(items[1].side, "above", "flipped above")
	-- A boss label that must show is moved all the way in.
	items = { { x = -5, y = 150, r = 17, kind = "boss", w = 300, h = 15, prio = 3 } }
	ML.Labels(items, nil, bounds)
	box = ML.LabelBox(items[1], items[1].side)
	T.ok(box[1] + items[1].dx >= -0.5 and box[3] + items[1].dx <= 400.5, "inside")
	-- Without bounds: as before.
	items = { { x = 20, y = 100, r = 10, kind = "disc", w = 200, h = 15, prio = 1 } }
	ML.Labels(items)
	T.eq(items[1].side, "below")
	T.eq(items[1].dx, 0)
end)

T.case("Quest items: their own icon and name, cut from the start when long", function()
	local m = { kind = "quest_item", itemID = 14540 }
	local art = ns.MapPins.MarkerArt(m)
	T.eq(type(art), "table", "the item's icon")
	T.eq(art.file, 134400)
	T.eq(ns.MapPins.MarkerArt({ kind = "quest_item" }), "kind_quest_item", "no item: the kind's icon")
	T.ok(ns.Art.SPECS.kind_quest_item.round and not ns.Art.SPECS.kind_quest_item.atlas, "a round icon, not three dots")
	local fs = UIParent:CreateFontString()
	fs:SetWidth(120)
	-- Six units per letter: 20 letters fit.
	fs.IsTruncated = function(self)
		return #(self:GetText() or "") * 6 > 120
	end
	local text = ns.Widgets.FitText(fs, "Taragaman the Hungerer's Heart", true)
	T.eq(text, "...Hungerer's Heart", "the end kept")
	T.eq(fs.dpFullText, "Taragaman the Hungerer's Heart", "the whole name for the tooltip")
	T.eq(ns.Widgets.FitText(fs, "Taragaman the Hungerer's Heart"), "Taragaman the...", "titles cut at the end as before")
	-- The step's title is the item's name.
	local plan = ns.Bundled.Get("b:ragefire-chasm")
	for _, s in ipairs(Steps.Build(plan)) do
		local mk = s.marker and ns.Util.FindById(plan.markers, s.marker)
		if mk and mk.kind == "quest_item" then
			T.eq((ns.UI.StepText(plan, s)), "Item 14540", "the client's name for the item")
		end
	end
end)

T.case("Drawn maps from other addons come first again; profiles that held the old default follow", function()
	T.eq(ns.Defaults.settings.preferProviderMaps, true, "on by default")
	local raw = { global = { schema = 4 }, profiles = {
		Default = { settings = { preferProviderMaps = false, scale = 1.1 } },
		Other = { settings = { preferProviderMaps = true } },
		Empty = {},
	} }
	T.eq(ns.DB.ProviderMapsFirst(raw), 1, "one profile changed")
	T.eq(raw.profiles.Default.settings.preferProviderMaps, nil, "back to the default (on)")
	T.eq(raw.profiles.Default.settings.scale, 1.1, "nothing else touched")
	T.eq(raw.profiles.Other.settings.preferProviderMaps, true)
	T.eq(raw.global.providerMapsFirst, true, "done once")
	raw.profiles.Default.settings.preferProviderMaps = false -- the player's choice after the update
	T.eq(ns.DB.ProviderMapsFirst(raw), 0, "a later choice stays")
	T.eq(raw.profiles.Default.settings.preferProviderMaps, false)
	T.eq(ns.DB.ProviderMapsFirst(nil), 0)
	T.eq(ns.DB.ProviderMapsFirst({}), 0, "a new install")
end)

T.case("Steps list: a move wears its map stop (route ring, step number), a pull its own number; no repeated floor", function()
	boot()
	ns.UI.SelectPlan("b:the-deadmines")
	ns.UI.SelectTab("map")
	ns.UI.RefreshPage()
	local side = _G.DungeonPlannerMainFrame.instancePage.side
	local plan = ns.UI.ctx:Plan()
	local steps = ns.UI.ctx:Steps()
	local numbers = Steps.StopNumbers(steps)
	local moves, pulls = 0, 0
	-- The floors' names as the client has them ("The Deadmines", "Ironclad Cove"; the mock names them by map ID).
	local first, second = ns.Names.Floor(plan.floors[1], 1), ns.Names.Floor(plan.floors[2], 2)
	T.eq(first, ns.Names.Instance(plan.instance), "the first floor is named as the instance")
	T.ok(first ~= second)
	for _, row in ipairs(side.list.rows) do
		local step, index = row.item, row.index
		if row:IsShown() and step and index then
			local b = row.badge
			if step.kind == "move" then
				moves = moves + 1
				T.ok(b.stopRing:IsShown() and not b.ring:IsShown(), "a move: the stop's ring, not the pin's gold ring")
				T.eq(b.stopNum:GetText(), tostring(index), "with the step's number")
				T.eq(b.num:GetText(), "", "not in the pull badge's number")
				T.eq(numbers[step.route] and numbers[step.route][step.to], index, "the number its map stop shows")
				local route = ns.Util.FindById(plan.routes, step.route)
				-- The colour of the map's ring for that stop (the route's colour at that point along it).
				local r, g, bl = ns.MapRoutes.StopColor(route, step.to)
				local cr, cg, cb = b.stopRing:GetVertexColor()
				T.ok(near(cr, r) and near(cg, g) and near(cb, bl), "ringed in the route's colour at that stop")
				T.ok(b.disc:GetWidth() < 24, "smaller than a pull's badge")
			elseif step.kind == "pull" then
				pulls = pulls + 1
				local _, pullIndex = ns.Util.FindById(plan.pulls, step.pull)
				T.ok(b.ring:IsShown() and not b.stopRing:IsShown(), "a pull: the gold ring")
				T.eq(b.num:GetText(), tostring(pullIndex), "its pull number")
			end
			-- The first floor is named as the instance: not repeated on every row; the second floor's name stays.
			local caption = row.caption:GetText() or ""
			T.ok(not caption:find(first, 1, true), "no floor named as the instance: " .. caption)
			if step.floor == 2 then
				T.ok(caption:find(second, 1, true), "the other floor's name: " .. caption)
			end
		end
	end
	T.ok(moves >= 2 and pulls >= 1, "moves and pulls seen")
end)
