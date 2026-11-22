-- Map pins: the pooled buttons the map canvas (UI/MapCanvas.lua) draws markers, route stops and boss pins on, their
-- styles (round art in a ring, unmasked art, pull-coloured discs), and where their labels go (Model/MapLayout.lua).
-- Labels sit on a dark plate so they stay readable over a map's own painted names. The route paths under the stops
-- (MapRoutes) are at the end of this file: the client lists an addon's files when the game starts, so a new file would
-- be missing after an update until a restart.

local _, ns = ...
local MapPins = ns:NewModule("MapPins")
local S, W, Art = ns.Style, ns.Widgets, ns.Art
local Plan, Util = ns.Plan, ns.Util

local BOSS_SIZE, PIN_SIZE, DISC_SIZE = 34, 22, 20 -- at icon scale 1

-- Kind -> fallback letter when the client lacks the art.
local GLYPH = {
	boss = "B",
	rare = "R",
	pack = "",
	patrol = "P",
	loot = "L",
	chest = "C",
	quest_item = "?",
	quest_npc = "!",
	npc = "N",
	interactive = "I",
	entrance = "E",
	exit = "X",
	shortcut = "S",
	stairs = "S",
	hazard = "H",
	position = "",
	note = "i",
}
MapPins.GLYPH = GLYPH

-- Texture:SetRotation is inferred on Forever (Retail API): without it arrows keep pointing up.
local function rotate(tex, radians)
	if tex.SetRotation then
		tex:SetRotation(radians)
	end
end

-- Art key for a marker (its role for positions).
function MapPins.ArtKey(m)
	if m.kind == "position" and m.role then
		return "role_" .. m.role
	end
	return "kind_" .. m.kind
end
MapPins.Rotate = rotate

-- The art of a marker that is not a boss, pack or position: its kind's (UI/Art.lua), or for a quest item the item's
-- own icon when the client knows it (C_Item, guarded). A key of Art.SPECS or a spec table.
function MapPins.MarkerArt(m)
	if m.kind == "quest_item" and m.itemID then
		local get = C_Item and C_Item.GetItemIconByID
		local ok, icon = false, nil
		if type(get) == "function" then
			ok, icon = pcall(get, m.itemID)
		end
		icon = ok and ns.Util.Plain(icon) or nil
		if icon ~= nil and (type(icon) == "number" or (type(icon) == "string" and icon ~= "")) then
			return { file = icon, round = true }
		end
	end
	return "kind_" .. m.kind
end

-- Texture coordinates that show a square texture turned `r` radians counter-clockwise on screen (y up), for
-- SetTexCoord's eight values (UL, LL, UR, LR). The turn is done in the coordinates, not with Texture:SetRotation: on
-- WoW: Forever the route chevrons drawn with SetRotation all pointed up, whatever their path's direction. The texture
-- needs a clamped wrap with a transparent border (the corners sample past 0..1).
function MapPins.TurnedCoords(r)
	local c, s = math.cos(r), math.sin(r)
	local out = {}
	for _, p in ipairs({ { -0.5, 0.5 }, { -0.5, -0.5 }, { 0.5, 0.5 }, { 0.5, -0.5 } }) do
		-- The picture turned by r shows at p what the unturned picture has at p turned back by r.
		local qx, qy = c * p[1] + s * p[2], -s * p[1] + c * p[2]
		out[#out + 1] = 0.5 + qx
		out[#out + 1] = 0.5 - qy
	end
	return out
end
MapPins.BOSS_SIZE, MapPins.PIN_SIZE, MapPins.DISC_SIZE = BOSS_SIZE, PIN_SIZE, DISC_SIZE

local PLATE_X, PLATE_Y = 3, 1 -- the label plate's margin around the text

-- A pin: a button with a body (round icon, portrait, or disc), a ring, a glyph, a raid mark and a label.
function MapPins.New(view, parentFrame)
	local b = CreateFrame("Button", nil, parentFrame)
	b:SetFrameLevel(view.overlay:GetFrameLevel() + 4)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b.shadow = b:CreateTexture(nil, "BACKGROUND")
	b.shadow:SetTexture(S.MEDIA .. "Circle")
	b.shadow:SetVertexColor(0, 0, 0, 0.55)
	b.disc = b:CreateTexture(nil, "ARTWORK", nil, 0)
	b.disc:SetTexture(S.MEDIA .. "Circle")
	b.icon = Art.RoundTexture(b, "ARTWORK", 1)
	b.flat = b:CreateTexture(nil, "ARTWORK", nil, 2) -- unmasked art (atlases, quest marks, skull, arrow)
	b.ring = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.roleRing = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.roleRing:SetTexture(S.MEDIA .. "Ring")
	b.select = b:CreateTexture(nil, "OVERLAY", nil, 3)
	b.select:SetTexture(S.MEDIA .. "Ring")
	S.Tint(b.select, "white")
	b.mark = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.text = W.Text(b, "number", "white")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetJustifyH("CENTER")
	b.label = W.Text(b, "label", "white")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -1)
	b.label:SetJustifyH("CENTER")
	-- A dark plate behind the label: readable over a map's own painted names and art.
	b.plate = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.plate:SetColorTexture(0.03, 0.035, 0.045, 0.86) -- dense enough to hide a painted name under it
	b.plate:SetPoint("TOPLEFT", b.label, "TOPLEFT", -PLATE_X, PLATE_Y)
	b.plate:SetPoint("BOTTOMRIGHT", b.label, "BOTTOMRIGHT", PLATE_X, -PLATE_Y)
	b.plate:Hide()
	return b
end

-- Styles -----------------------------------------------------------------------------------------------------------

local function resetPin(b, size)
	b:SetSize(size, size)
	b.shadow:ClearAllPoints()
	b.shadow:SetPoint("CENTER", 1, -1)
	b.shadow:SetSize(size + 2, size + 2)
	b.disc:Hide()
	Art.ReleasePortrait(b.icon)
	b.icon:Hide()
	b.flat:Hide()
	b.ring:Hide()
	b.dpRingKey = nil
	b.roleRing:Hide()
	b.select:Hide()
	b.mark:Hide()
	b.text:SetText("")
	b.label:SetText("")
	b.plate:Hide()
	rotate(b.flat, 0)
	b:SetAlpha(1)
end

-- Round masked art inside a ring: the Adventure Guide's (bosses) or the minimap's gold ring (everything else).
local function styleRound(b, size, key, ringKey, desaturate)
	b.icon:ClearAllPoints()
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(size, size)
	b.icon:Show()
	local ok = type(key) == "table" and Art.SetBossPortrait(b.icon, key) or Art.Set(b.icon, key, desaturate)
	Art.PlaceRing(b.ring, b, size, ringKey or "pinRing", desaturate)
	b.ring:Show()
	b.dpRingKey = ringKey or "pinRing"
	return ok
end

-- Art without a mask (atlases and the game's own marks).
local function styleFlat(b, size, key)
	b.flat:ClearAllPoints()
	b.flat:SetPoint("CENTER")
	b.flat:SetSize(size, size)
	b.flat:SetVertexColor(1, 1, 1, 1)
	b.flat:Show()
	return Art.Set(b.flat, key)
end

-- A pull-coloured disc with a dark edge and the pull number (packs and patrols).
local function styleDisc(b, size, r, g, bl, number, kind)
	b.disc:ClearAllPoints()
	b.disc:SetPoint("CENTER")
	b.disc:SetSize(size, size)
	b.disc:SetVertexColor(r, g, bl, 1)
	b.disc:Show()
	b.ring:ClearAllPoints()
	b.ring:SetPoint("CENTER")
	b.ring:SetSize(size, size)
	b.ring:SetTexture(S.MEDIA .. "Ring")
	b.ring:SetTexCoord(0, 1, 0, 1)
	b.ring:SetVertexColor(0.1, 0.07, 0.04, 1)
	b.ring:Show()
	if number then
		b.text:SetText(number)
	elseif kind == "patrol" then
		b.flat:ClearAllPoints()
		b.flat:SetPoint("CENTER")
		b.flat:SetSize(size * 0.6, size * 0.6)
		b.flat:SetTexture(S.MEDIA .. "Arrow", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		-- Pointing right (a quarter turn clockwise, in the texture coordinates: MapPins.TurnedCoords).
		local tc = MapPins.TurnedCoords(-math.pi / 2)
		b.flat:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
		b.flat:SetVertexColor(1, 1, 1, 1)
		b.flat:Show()
	else
		styleFlat(b, size * 0.7, "skull")
	end
end

-- The boss of a boss marker and its face (the matched journal boss's portrait, Data/Journal.lua).
local function boss(plan, m)
	local enc = m.encounter and Util.FindById(plan.encounters, m.encounter)
	return enc and ns.Journal.BossArt(plan, enc) or nil, enc
end

-- Labels go where they cover nothing (Model/MapLayout.lua); pull discs on a boss move beside it. The boxes include
-- the label's plate.
local LABEL_H = 13 + 2 * PLATE_Y
local LABEL_ANCHOR = {
	below = { "TOP", "BOTTOM", 0, -(1 + PLATE_Y) },
	above = { "BOTTOM", "TOP", 0, 1 + PLATE_Y },
	right = { "LEFT", "RIGHT", 2 + PLATE_X, 0 },
	left = { "RIGHT", "LEFT", -(2 + PLATE_X), 0 },
}
-- How far a pin's look reaches from its centre: the minimap ring stands out past the art it circles (its gold edge at
-- 0.64 of the art's size; the Adventure Guide's ring stays within it).
local RING_REACH = 0.64
local function layoutItem(list, b, x, y, size, kind, prio)
	local text = b.label:GetText()
	local w = (text and text ~= "") and math.ceil(b.label:GetStringWidth() or 0) + 2 * PLATE_X or 0
	local r = (b.dpRingKey == "pinRing" and b.ring:IsShown()) and size * RING_REACH or size / 2
	list[#list + 1] = { b = b, x = x, y = y, r = r, kind = kind, w = w, h = LABEL_H, prio = prio }
end
local function applyLayout(list, canvas, avoid, bounds)
	ns.MapLayout.Nudge(list)
	ns.MapLayout.Labels(list, avoid, bounds)
	for _, it in ipairs(list) do
		if it.moved then
			it.b:ClearAllPoints()
			it.b:SetPoint("CENTER", canvas, "TOPLEFT", it.x, -it.y)
		end
		if it.w > 0 then
			local a = LABEL_ANCHOR[it.side]
			it.b.label:ClearAllPoints()
			if a then
				-- Moved to stay inside the visible map (MapLayout.Labels: dx right, dy down).
				it.b.label:SetPoint(a[1], it.b, a[2], a[3] + (it.dx or 0), a[4] - (it.dy or 0))
				it.b.label:Show()
				it.b.plate:Show()
			else
				it.b.label:Hide()
				it.b.plate:Hide()
			end
		end
	end
end
MapPins.Boss = boss

-- Draw one marker on pin b.
local function stylePin(b, plan, m, scale)
	local kind = m.kind
	local size
	if kind == "boss" then
		size = BOSS_SIZE * scale
		resetPin(b, size)
		local art = boss(plan, m)
		styleRound(b, size, art or "kind_boss", "bossRing")
	elseif kind == "pack" or kind == "patrol" then
		size = DISC_SIZE * scale
		resetPin(b, size)
		local r, g, bl = 0.55, 0.12, 0.08
		local index
		if m.pull then
			r, g, bl = S.PaletteColor((Util.FindById(plan.pulls, m.pull) or {}).color or 1)
			index = Plan.PullIndex(plan, m.pull)
		end
		styleDisc(b, size, r, g, bl, index and tostring(index) or nil, kind)
	elseif kind == "position" then
		size = PIN_SIZE * scale
		resetPin(b, size)
		styleRound(b, size, MapPins.ArtKey(m), "pinRing")
		b.ring:Hide()
		b.roleRing:ClearAllPoints()
		b.roleRing:SetPoint("CENTER")
		b.roleRing:SetSize(size + 4, size + 4)
		b.roleRing:SetVertexColor(S.RoleColor(m.role or "TANK"))
		b.roleRing:Show()
	else
		size = PIN_SIZE * scale
		resetPin(b, size)
		local key = MapPins.MarkerArt(m)
		local spec = type(key) == "table" and key or Art.SPECS[key]
		local ok
		if spec and spec.atlas and Art.HasAtlas(spec.atlas) then
			ok = styleFlat(b, size * 1.25, spec)
		elseif spec and not spec.round then
			ok = styleFlat(b, size * 1.1, spec)
		else
			ok = styleRound(b, size, key, "pinRing", kind == "rare")
		end
		if not ok then
			b.text:SetText(GLYPH[kind] or "?")
		end
	end
	-- Raid mark in the top-right corner.
	if m.icon and m.icon > 0 then
		b.mark:ClearAllPoints()
		b.mark:SetSize(size * 0.6, size * 0.6)
		b.mark:SetPoint("CENTER", b, "TOPRIGHT", -size * 0.1, -size * 0.1)
		b.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. m.icon)
		b.mark:Show()
	end
	return size
end
MapPins.Reset, MapPins.StyleRound, MapPins.StyleFlat, MapPins.StyleDisc = resetPin, styleRound, styleFlat, styleDisc
MapPins.LayoutItem, MapPins.ApplyLayout, MapPins.Style = layoutItem, applyLayout, stylePin

-- Route paths ------------------------------------------------------------------------------------------------------------
-- The route's path on a map view (UI/MapCanvas.lua draws the numbered stops and calls this first, under them).
--
-- A route must read on busy map art (parchment, painted names, rocks) and stay calm where it bends, doubles back or
-- crosses itself. Each segment is a line in the route's colour over a dark outline line; each bend gets a joint (a disc
-- in the line's colour over a dark disc), so a path with many bends turns smoothly. Direction arrows
-- (Media/RouteArrowEdge.tga, a small solid arrowhead with a thin dark edge baked in; Media/RouteArrow.tga without the
-- edge) in a lighter tone of the line sit on it, a little wider than the line: one just before each numbered stop and
-- at the route's end, and others spaced by distance on screen (Model/RouteArrows.lua: clear of stops, sharp bends, pins,
-- labels, each other and other parts of the line, so crossings and paths that double back stay clean). The Routes
-- settings (settings.routes, UI/Settings.lua) choose the lines' width, opacity, outline and colour and the arrows'
-- density and size. While a step is in focus its leg is brighter and wider and the rest of the path dims.
--
-- Everything comes from pools on the view (outlines, lines, joints, arrows) and is redrawn only when the map redraws
-- (plan, view, focus or setting changes), never per frame. The map places the arrows after its pins and labels
-- (DrawRouteArrows), so they keep clear of them; a draw without them places the arrows at once.

local MapRoutes = ns:NewModule("MapRoutes")

MapRoutes.MAX_ARROWS = 400 -- bound per redraw, all routes together (each route: RouteArrows.LIMIT)
local ARROW_FILE, ARROW_EDGE_FILE = S.MEDIA .. "RouteArrow", S.MEDIA .. "RouteArrowEdge"
-- A file added while the game runs cannot be opened until a restart (docs/COMPATIBILITY.md section 9): then the older
-- shapes stand in (SetTexture's success flag, where the client gives one).
local FALLBACK_FILES = { S.MEDIA .. "Chevron", S.MEDIA .. "Arrow" }
MapRoutes.ARROW_FILE, MapRoutes.ARROW_EDGE_FILE = ARROW_FILE, ARROW_EDGE_FILE

-- A colour mixed towards white by k (0..1).
local function lighten(r, g, b, k)
	return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end
MapRoutes.Lighten = lighten

-- The Routes settings (settings.routes) as sizes in screen units (UI/Style.lua ROUTE); u: the icon size.
function MapRoutes.Look(u)
	local R = S.ROUTE
	local s = ns.db and ns.db.settings and ns.db.settings.routes
	s = type(s) == "table" and s or {}
	u = u or 1
	local spacing = R.spacing[s.arrows]
	if spacing == nil then
		spacing = R.spacing.normal
	end
	local color = tonumber(s.color) or 0
	return {
		width = (R.width[s.width] or R.width.medium) * u,
		outline = s.outline ~= false and R.outline * u or 0,
		spacing = spacing and spacing * u or nil,
		arrow = R.arrow[s.arrowSize] or R.arrow.medium,
		heads = spacing and s.heads ~= false or false,
		opacity = math.max(0.4, math.min(1, tonumber(s.opacity) or 1)),
		color = color >= 1 and color <= #S.Palette() and math.floor(color) or nil,
		focusOnly = s.focusArrows == true,
	}
end

-- A route's colour on the map: the Routes setting's one colour for the plan's own routes when it is set, else the
-- route's own. Lines, arrows, stop rings and bend discs all read it here. own: a route of the plan (not another
-- addon's).
function MapRoutes.Color(route, own)
	local look = MapRoutes.Look(1)
	return S.PaletteColor(own and look.color or route.color)
end

function MapRoutes.Install(view)
	local overlay = view.overlay
	local pools = view.pools
	pools.outlines, pools.joints, pools.jointOutlines = pools.outlines or {}, pools.joints or {}, pools.jointOutlines or {}

	-- Pooled pieces on the overlay; their draw layers are below (OUTLINE .. ARROW).
	local function line(list, i, sublevel)
		local l = list[i]
		if not l and overlay.CreateLine then
			l = overlay:CreateLine(nil, "ARTWORK", nil, sublevel)
			l:SetColorTexture(1, 1, 1, 1)
			list[i] = l
		end
		return l
	end
	local function disc(list, i, sublevel)
		local t = list[i]
		if not t then
			t = overlay:CreateTexture(nil, "ARTWORK", nil, sublevel)
			t:SetTexture(S.MEDIA .. "Circle")
			list[i] = t
		end
		return t
	end
	local function arrow(i, file)
		local a = pools.arrows[i]
		if not a then
			a = overlay:CreateTexture(nil, "ARTWORK", nil, 4) -- above every line, the highlighted one too
			pools.arrows[i] = a
		end
		if a.dpFile ~= file then
			a.dpFile = file
			if a:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") == false then
				for _, f in ipairs(FALLBACK_FILES) do
					if a:SetTexture(f, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") ~= false then
						break
					end
				end
			end
		end
		return a
	end

	local function place(l, x0, y0, x1, y1, canvas)
		l:SetStartPoint("TOPLEFT", canvas, x0, y0)
		l:SetEndPoint("TOPLEFT", canvas, x1, y1)
	end

	-- Draw layers on the overlay (sublevels): outlines and joint outlines, lines and joints, then the highlighted leg's
	-- outline and line above every other line, and the arrows on top. Pins and stops are frames above all of these.
	local OUTLINE, LINE, TOP_OUTLINE, TOP_LINE, ARROW = 0, 1, 2, 3, 4

	-- Draw every route path on `floor`. px, py: plan coordinates to canvas offsets (py negative downwards). o = { scale
	-- (icon size), seg (the focused step's { route, from, to } or nil), highlight (a leg { route, from, to } drawn as the
	-- hover highlight: run mode's current step), activeRoute, extra (more routes in the map's own coordinates: another
	-- addon's, Data/Providers.lua Routes), mx, my (map coordinates to canvas offsets), deferArrows (the caller places the
	-- arrows with PlaceRouteArrows once its pins are laid out), restyle (a hover change: same paths, new looks) }.
	-- view.routeHover, the leg under the pointer or a hovered step (SetRouteHover), wins over o.highlight. Returns the
	-- counts drawn.
	function view:DrawRoutePaths(plan, floor, px, py, o)
		o = o or {}
		if o.deferArrows and not o.restyle then
			self.routeArgs = { plan, floor, px, py, o }
		end
		local canvas = self.canvas
		local n = { lines = 0, outlines = 0, joints = 0, arrows = 0 }
		local u = math.max(0.75, o.scale or 1)
		local look = MapRoutes.Look(u)
		local seg = o.seg
		local hl = self.routeHover or o.highlight
		local jobs = { paths = {}, styles = {}, routes = {}, raw = {}, ranges = {}, look = look, u = u, counts = n, hl = hl }
		self.routeJobs = jobs
		local all = {}
		for _, route in ipairs(plan and plan.routes or {}) do
			all[#all + 1] = { route = route, own = true }
		end
		for _, route in ipairs(o.extra or {}) do
			all[#all + 1] = { route = route }
		end
		for _, entry in ipairs(all) do
			local route = entry.route
			if route.floor == floor and #route.points >= 2 then
				local r, g, b = MapRoutes.Color(route, entry.own)
				local alpha = (route.optional and 0.55 or 1) * look.opacity
				local thickness = look.width + (route.id == o.activeRoute and u or 0)
				local fx, fy = px, py
				if route.mapSpace then
					fx, fy = o.mx or px, o.my or py
				end
				local raw = {}
				for i, pt in ipairs(route.points) do
					raw[i] = { fx(pt[1], pt[2]), fy(pt[2], pt[1]), stop = pt.step ~= nil }
				end
				-- A corridor walked out and back draws as two lanes, each direction on its own right
				-- (Model/RouteLegs.lua); lanes[k].seg is the route's own segment for drawn segment k.
				local wide = thickness + look.outline
				local lanes = ns.RouteLegs.Lanes(raw, { shift = wide * S.ROUTE.lane, near = wide * 1.2, yUp = true })
				local focusHere = seg and seg.route == route.id
				-- The route's own segment i (joining points i - 1 and i): its colour, alpha, width, whether it is
				-- brighter, and whether it draws above the other lines.
				local function segLook(i)
					if hl then
						if hl.route == route.id and i > hl.from and i <= hl.to then
							local lr, lg, lb = lighten(r, g, b, 0.12)
							return lr, lg, lb, alpha, thickness + S.ROUTE.focusWidth * u, true, true
						end
						return r, g, b, alpha * S.ROUTE.dim, thickness, false, false
					elseif focusHere and i > seg.from and i <= seg.to then
						local lr, lg, lb = lighten(r, g, b, 0.25)
						return lr, lg, lb, alpha, thickness + S.ROUTE.focusWidth * u, true, false
					elseif seg then
						return r, g, b, alpha * 0.45, thickness, false, false
					end
					return r, g, b, alpha, thickness, false, false
				end
				local function laneLook(k)
					return segLook(lanes[k].seg or k)
				end
				for k = 2, #lanes do
					local a, c = lanes[k - 1], lanes[k]
					local cr, cg, cb, ca, th, _, top = laneLook(k)
					local l = line(pools.lines, n.lines + 1, LINE)
					if l then
						n.lines = n.lines + 1
						place(l, a[1], a[2], c[1], c[2], canvas)
						l:SetDrawLayer("ARTWORK", top and TOP_LINE or LINE)
						l:SetThickness(th)
						l:SetVertexColor(cr, cg, cb, ca)
						l:Show()
						local ol = look.outline > 0 and line(pools.outlines, n.outlines + 1, OUTLINE)
						if ol then
							n.outlines = n.outlines + 1
							place(ol, a[1], a[2], c[1], c[2], canvas)
							ol:SetDrawLayer("ARTWORK", top and TOP_OUTLINE or OUTLINE)
							ol:SetThickness(th + look.outline)
							ol:SetVertexColor(0.05, 0.03, 0.02, ca * 0.8)
							ol:Show()
						end
					end
				end
				-- A joint takes the look of the segment that arrives at the bend.
				for _, k in ipairs(ns.RouteArrows.Joints(lanes)) do
					local cr, cg, cb, ca, th, _, top = laneLook(k)
					local p = lanes[k]
					n.joints = n.joints + 1
					local outer, inner = disc(pools.jointOutlines, n.joints, OUTLINE), disc(pools.joints, n.joints, LINE)
					outer:SetDrawLayer("ARTWORK", top and TOP_OUTLINE or OUTLINE)
					outer:ClearAllPoints()
					outer:SetPoint("CENTER", canvas, "TOPLEFT", p[1], p[2])
					outer:SetSize(th + look.outline, th + look.outline)
					outer:SetVertexColor(0.05, 0.03, 0.02, ca * 0.8)
					if look.outline > 0 then
						outer:Show()
					else
						outer:Hide()
					end
					inner:SetDrawLayer("ARTWORK", top and TOP_LINE or LINE)
					inner:ClearAllPoints()
					inner:SetPoint("CENTER", canvas, "TOPLEFT", p[1], p[2])
					inner:SetSize(th, th)
					inner:SetVertexColor(cr, cg, cb, ca)
					inner:Show()
				end
				-- The drawn points from..to of the route's own points: from its last copy of `from` (a doubled turning
				-- point) to its first copy of `to`.
				local function laneRange(from, to)
					local lf, lt
					for k, p in ipairs(lanes) do
						if p.i == from then
							lf = k
						end
						if p.i == to and not lt then
							lt = k
						end
					end
					return { from = lf or 1, to = lt or #lanes }
				end
				-- Arrows keep clear of the whole outlined line, of this route and the others.
				local path = { pts = lanes, half = wide / 2, hit = entry.own and not route.mapSpace or false }
				if look.focusOnly and seg then
					if focusHere then
						path.range = laneRange(seg.from, seg.to)
					else
						path.arrows = false
					end
				end
				local index = #jobs.paths + 1
				jobs.paths[index], jobs.styles[index], jobs.ranges[index] = path, laneLook, laneRange
				jobs.routes[index], jobs.raw[index] = route.id, raw
			end
		end
		for key, list in pairs({ lines = pools.lines, outlines = pools.outlines }) do
			for i = n[key] + 1, #list do
				list[i]:Hide()
			end
		end
		for i = n.joints + 1, #pools.joints do
			pools.joints[i]:Hide()
			pools.jointOutlines[i]:Hide()
		end
		if not o.deferArrows then
			self:DrawRouteArrows()
		end
		return n
	end

	local function placeOptions(jobs, obstacles, spacing, heads)
		local u, R, look = jobs.u, S.ROUTE, jobs.look
		local size = (look.width + R.outline * u) * look.arrow
		return {
			spacing = spacing,
			size = size,
			headSize = heads and size * R.head or nil,
			stopGap = 12 * u, -- a numbered stop's disc is 20 across at icon scale 1
			bendGap = 2 * u,
			gap = 2 * u,
			pins = obstacles and obstacles.pins,
			boxes = obstacles and obstacles.boxes,
			bounds = obstacles and obstacles.bounds,
			total = MapRoutes.MAX_ARROWS,
		}
	end

	-- The highlighted leg's own arrows at the normal density, when the settings show fewer (or only another leg's):
	-- placed once per highlighted leg, on that leg alone. Arrows turned off stay off.
	local function legMarks(v, jobs)
		local hl, look = jobs.hl, jobs.look
		local normal = S.ROUTE.spacing.normal * jobs.u
		if not hl or not look.spacing or (look.spacing <= normal and look.heads and not look.focusOnly) then
			return nil
		end
		local key = hl.route .. ":" .. hl.from .. ":" .. hl.to
		if v.legMarksKey == key and v.legMarksJobs == jobs then
			return v.legMarks
		end
		local paths, index = {}, nil
		for i, path in ipairs(jobs.paths) do
			local copy = { pts = path.pts, half = path.half, arrows = false }
			if jobs.routes[i] == hl.route then
				copy.arrows, copy.range, index = true, jobs.ranges[i](hl.from, hl.to), i
			end
			paths[i] = copy
		end
		local marks = index and ns.RouteArrows.Place(paths, placeOptions(jobs, v.arrowObstacles, normal, true)) or {}
		v.legMarksKey, v.legMarksJobs, v.legMarks = key, jobs, marks
		return marks
	end

	-- Draw arrows (RouteArrows.Place marks on the drawn lanes) in the look their segment has now. Returns how many.
	local function drawMarks(v, marks)
		local jobs = v.routeJobs
		local count = 0
		if jobs then
			local extra = legMarks(v, jobs)
			local hl = jobs.hl
			local list = marks or {}
			if extra then
				-- The leg's own arrows replace whatever the settings left on it.
				list = {}
				for _, m in ipairs(marks or {}) do
					local _, _, _, _, _, _, top = jobs.styles[m.path](m.seg)
					if not (top and jobs.routes[m.path] == hl.route) then
						list[#list + 1] = m
					end
				end
				for _, m in ipairs(extra) do
					list[#list + 1] = m
				end
			end
			local file = jobs.look.outline > 0 and ARROW_EDGE_FILE or ARROW_FILE
			local canvas = v.canvas
			for _, m in ipairs(list) do
				local cr, cg, cb, ca, _, bright = jobs.styles[m.path](m.seg)
				count = count + 1
				local a = arrow(count, file)
				local sz = m.size * (bright and 1.15 or 1)
				a:SetSize(sz, sz)
				a:ClearAllPoints()
				a:SetPoint("CENTER", canvas, "TOPLEFT", m.x, m.y)
				local ar, ag, ab = lighten(cr, cg, cb, S.ROUTE.tone)
				a:SetVertexColor(ar, ag, ab, ca)
				-- m.angle: the path's direction in canvas offsets (y up); the arrow points up unturned.
				local tc = MapPins.TurnedCoords(m.angle - math.pi / 2)
				a:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
				a:Show()
			end
			jobs.counts.arrows = count
		end
		for i = count + 1, #pools.arrows do
			pools.arrows[i]:Hide()
		end
		return count
	end

	-- Place and draw the direction arrows of the paths DrawRoutePaths drew last, clear of `obstacles` (pins and labels
	-- in the paths' canvas offsets: RouteArrows.Obstacles, and the visible bounds). Returns how many it drew.
	function view:DrawRouteArrows(obstacles)
		local jobs = self.routeJobs
		local marks
		self.arrowObstacles = obstacles
		if jobs and jobs.look.spacing and #jobs.paths > 0 then
			marks = ns.RouteArrows.Place(jobs.paths, placeOptions(jobs, obstacles, jobs.look.spacing, jobs.look.heads))
		end
		self.routeMarks = marks
		return drawMarks(self, marks)
	end

	-- While a marker or route point is dragged, or a window is being resized, the map redraws on every pointer move:
	-- the arrows hide then and are placed once the drag or resize ends (a short timer checks; a stale tick does nothing).
	local function busy(v)
		local mode = v.drag and v.drag.mode
		return mode == "marker" or mode == "point" or ns.sizingWindow ~= nil
	end
	local function settle()
		view.arrowTimer = nil
		if not view.arrowsPending then
			return
		end
		if busy(view) then
			view.arrowTimer = true
			C_Timer.After(0.1, settle)
			return
		end
		view.arrowsPending = nil
		if view:IsVisible() then
			local n = view:DrawRouteArrows(view.arrowObstacles)
			if view.counts then
				view.counts.arrows = n
			end
		end
	end
	-- The map's way to draw the arrows (UI/MapCanvas.lua DrawContent). Returns how many it drew now.
	function view:PlaceRouteArrows(obstacles)
		self.arrowObstacles = obstacles
		if not busy(self) then
			self.arrowsPending = nil
			return self:DrawRouteArrows(obstacles)
		end
		self.arrowsPending = true
		for i = 1, #pools.arrows do
			pools.arrows[i]:Hide()
		end
		if not self.arrowTimer and C_Timer and C_Timer.After then
			self.arrowTimer = true
			C_Timer.After(0.1, settle)
		end
		return 0
	end

	-- The highlighted leg: { route, from, to } (the route's own point indices) or nil, from the pointer over a line
	-- (source "map", UI/MapInput.lua) or a hovered step in the list (source "list", UI/SidePanel.lua); one at a time.
	-- A change restyles the lines and reuses the placed arrows: nothing is placed again, except the leg's own arrows
	-- when the settings show fewer (once per leg).
	function view:SetRouteHover(leg, source)
		local cur = self.routeHover
		if leg and cur and leg.route == cur.route and leg.from == cur.from and leg.to == cur.to then
			self.routeHoverSource = source
			return false
		end
		if not leg and not cur then
			return false
		end
		self.routeHover, self.routeHoverSource = leg, leg and source or nil
		local args = self.routeArgs
		if args and self:IsVisible() then
			local o = {}
			for k, v in pairs(args[5]) do
				o[k] = v
			end
			o.restyle = true
			self:DrawRoutePaths(args[1], args[2], args[3], args[4], o)
			local n = drawMarks(self, self.routeMarks)
			if self.counts then
				self.counts.arrows = n
			end
		end
		return true
	end
end
