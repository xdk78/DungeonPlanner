-- The map canvas: the dungeon's map art (drawn at runtime; no Blizzard art is shipped) in a bronze-edged frame, with
-- the plan on it: round boss portraits, round icons in the minimap ring, pull-coloured discs for packs, role icons for
-- party positions, the route (UI/MapRoutes.lua) with numbered stops (the focused step's segment bold), and the Enemies layer
-- underneath (UI/MapSpawns.lua). A parchment grid stands in when a map has no art.
--
-- Coordinates: plans store normalized x, y in 0..1 over the art layer (0,0 top-left). The canvas lays everything out
-- in view units itself (no SetScale), so zooming re-positions tiles and pins and pins keep their size.
--
-- Layers (Schema.LAYERS) can be hidden; position markers tied to a boss or a pull show only while that boss or pull is
-- in focus. Every drawn object comes from a pool and is redrawn only when the plan, the view or a setting changes.
--
-- Interaction is an explicit state machine (view.drag): idle | pan | marker | point. OnUpdate runs only while dragging
-- or while the pointer is over the map (coordinates, 20 Hz), so an idle map costs nothing per frame.

local _, ns = ...
local MapCanvas = ns:NewModule("MapCanvas")
local S, W, Art = ns.Style, ns.Widgets, ns.Art
local Util, Schema = ns.Util, ns.Schema
local SP = S.SPACE

local GRID_W, GRID_H = 1002, 668 -- fallback canvas size (3:2, like dungeon map art)
local MapPins = ns.MapPins
local BOSS_SIZE = MapPins.BOSS_SIZE
local FRAME_INSET = 7 -- the gold frame's width over the parchment
MapCanvas.FRAME_INSET = FRAME_INSET
MapCanvas.GLYPH = MapPins.GLYPH
MapCanvas.ArtKey = MapPins.ArtKey
local resetPin, styleRound = MapPins.Reset, MapPins.StyleRound
local layoutItem, stylePin, boss = MapPins.LayoutItem, MapPins.Style, MapPins.Boss
MapCanvas.BossOf = boss

-- Another addon's route on this floor (Data/Providers.lua Routes) as routes for MapRoutes to draw in the map's own
-- coordinates: its main path in teal, its side paths fainter. nil when there is none for this map.
MapCanvas.PROVIDER_ROUTE_COLOR = 6
function MapCanvas.ProviderRoutes(plan, floor, art)
	local r = ns.Providers.Routes(plan, floor, art)
	if not r then
		return nil
	end
	local out = {}
	for i, l in ipairs(r.lines) do
		out[i] = { id = "provider" .. i, floor = floor, color = MapCanvas.PROVIDER_ROUTE_COLOR, optional = l.side or nil,
			mapSpace = true, points = l.points }
	end
	return out, r
end

-- A map's painted names (art.keepOut: { x1, y1, x2, y2 } in 0..1 of the picture) as boxes in canvas units, added to
-- `into` (a new list when nil). Pure.
function MapCanvas.KeepOutRects(art, w, h, s, into)
	local out = into or {}
	for _, r in ipairs(art and art.keepOut or {}) do
		out[#out + 1] = { r[1] * w * s, r[2] * h * s, r[3] * w * s, r[4] * h * s }
	end
	return out
end

function MapCanvas.Create(parent, cb)
	local view = Art.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	if view.SetClipsChildren then
		view:SetClipsChildren(true)
	end
	S.Backdrop(view, "thin", "mapBackdrop", false)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view.cb = cb
	view.zoom = 1
	view.ox, view.oy = 0, 0
	view.drag = { mode = "idle" }
	-- The table under the map: where a map's shape leaves bands beside it (a 3:2 map in a wider frame), the quest-log
	-- parchment, a shade darker than the map and burnt at the edges, rather than a black gap.
	view.board = view:CreateTexture(nil, "BACKGROUND", nil, 1)
	view.board:SetAllPoints()
	Art.Set(view.board, "parchment")
	view.board:SetTexCoord(0, 0.6, 0, 0.75)
	view.board:SetVertexColor(0.5, 0.4, 0.28, 1)
	view.boardEdge = view:CreateTexture(nil, "BACKGROUND", nil, 2)
	view.boardEdge:SetAllPoints()
	view.boardEdge:SetTexture(S.MEDIA .. "Vignette")
	view.boardEdge:SetVertexColor(0.16, 0.09, 0.03, 0.85)

	local canvas = CreateFrame("Frame", nil, view)
	canvas:SetPoint("TOPLEFT")
	canvas:SetSize(GRID_W, GRID_H)
	view.canvas = canvas

	local art = CreateFrame("Frame", nil, canvas)
	art:SetAllPoints()
	view.art = art
	view.tiles = {}
	view.lifts = {} -- per tile, a lighter copy added on top (MapCanvas.ArtStyle)
	view.gridLines = {}
	-- Parchment under a map without art.
	view.paper = art:CreateTexture(nil, "BACKGROUND", nil, 0)
	view.paper:SetAllPoints()
	Art.Set(view.paper, "parchment")
	view.paper:SetTexCoord(0, 0.6, 0, 0.75)
	view.paper:SetVertexColor(0.95, 0.85, 0.65, 1)
	-- Darkened edges over a minimap floor drawn in the parchment colours (MapCanvas.ArtStyle).
	view.vignette = art:CreateTexture(nil, "BACKGROUND", nil, 3)
	view.vignette:SetAllPoints()
	view.vignette:SetTexture(S.MEDIA .. "Vignette")
	view.vignette:Hide()

	local overlay = CreateFrame("Frame", nil, canvas)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(canvas:GetFrameLevel() + 5)
	view.overlay = overlay
	view.pools = { lines = {}, arrows = {}, points = {}, pins = {}, journal = {} } -- route paths: UI/MapRoutes.lua
	-- Where the current step is on a compact map (run mode): a soft accent disc with a ring, under the pins.
	view.focusGlow = overlay:CreateTexture(nil, "ARTWORK", nil, 0)
	view.focusGlow:SetTexture(S.MEDIA .. "Circle")
	view.focusRing = overlay:CreateTexture(nil, "ARTWORK", nil, 2)
	view.focusRing:SetTexture(S.MEDIA .. "Ring")
	view.focusGlow:Hide()
	view.focusRing:Hide()

	-- The gold frame over the edges of the parchment.
	local edge = Art.CreateFrame("Frame", nil, view, "BackdropTemplate")
	edge:SetAllPoints()
	edge:SetFrameLevel(view:GetFrameLevel() + 40)
	edge:EnableMouse(false)
	S.Backdrop(edge, "window", false, "border")
	view.edge = edge

	view.noArt = W.Paragraph(edge, "caption", "ink")
	-- At the top: the bottom-left corner holds the Labels and Icon size controls.
	view.noArt:SetPoint("TOPLEFT", FRAME_INSET + SP.sm, -FRAME_INSET - SP.sm)
	view.noArt:SetPoint("RIGHT", -FRAME_INSET - SP.sm, 0)
	view.noArt:SetText(ns.L["No map art for this map. Markers and routes still work on the parchment grid."])
	view.noArt:Hide()

	-- Who drew the map: "Map by Santiago Reyes" on his bundled maps (Data/ReyesMaps.lua), or the addon a map and its
	-- boss pins come from (Data/Providers.lua): a small chip in the map's top-left corner (view:PlaceCredit), on a
	-- dark plate so the art under it does not show through. A compact map (run mode) leaves it to the window around it
	-- (view.creditText).
	view.credit = W.Text(edge, "caption", "ink")
	view.credit:SetPoint("TOPLEFT", FRAME_INSET + SP.sm, -FRAME_INSET - SP.sm)
	view.credit:Hide()
	view.creditPlate = edge:CreateTexture(nil, "ARTWORK", nil, -8)
	view.creditPlate:SetColorTexture(0.03, 0.035, 0.045, 0.78)
	view.creditPlate:SetPoint("TOPLEFT", view.credit, "TOPLEFT", -SP.xs, SP.xxs + 1)
	view.creditPlate:SetPoint("BOTTOMRIGHT", view.credit, "BOTTOMRIGHT", SP.xs, -(SP.xxs + 1))
	view.creditPlate:Hide()
	-- Hover target over the chip of a bundled map (Data/ReyesMaps.lua): the artist, his site and his donation page.
	view.creditHit = CreateFrame("Frame", nil, edge)
	view.creditHit:SetPoint("TOPLEFT", view.creditPlate, "TOPLEFT")
	view.creditHit:SetPoint("BOTTOMRIGHT", view.creditPlate, "BOTTOMRIGHT")
	view.creditHit:EnableMouse(true)
	W.SetTooltip(view.creditHit, string.format(ns.L["Map by %s"], ns.ReyesMaps.ARTIST),
		string.format(ns.L["From his Atlas de Azeroth: Forever (%s), used with his permission. Like his maps? Support the artist: %s"],
			ns.ReyesMaps.SITE, ns.ReyesMaps.DONATE))
	view.creditHit:Hide()

	view.coords = W.Text(edge, "caption", "white")
	view.coords:SetPoint("BOTTOMRIGHT", -FRAME_INSET - SP.sm, FRAME_INSET + SP.sm)
	view.coords:SetJustifyH("RIGHT")

	MapCanvas.Install(view)
	MapCanvas.InstallArt(view) -- UI/MapArt.lua
	ns.MapSpawns.Install(view)
	if ns.MapRoutes then
		ns.MapRoutes.Install(view)
	else
		-- UI/MapRoutes.lua came with an update while the game ran: the client reads an addon's files at start, so it
		-- loads after a restart (docs/COMPATIBILITY.md section 7; `/dp debug` says so). Until then the map has no routes.
		local none = { lines = 0, outlines = 0, joints = 0, arrows = 0, dashes = 0 }
		view.DrawRoutePaths = function()
			return none
		end
		view.DrawRouteStops = function()
			return 0
		end
		view.DrawRouteArrows, view.PlaceRouteArrows = view.DrawRouteStops, view.DrawRouteStops
		view.SetRouteHover = function()
			return false
		end
	end
	ns.MapDraw.Install(view)
	return view
end

-- Layout ---------------------------------------------------------------------------------------------------------------

function MapCanvas.Install(view)
	local canvas = view.canvas
	local L = ns.L

	function view:BaseSize()
		local a = self.artInfo
		if a then
			return a.width, a.height
		end
		return GRID_W, GRID_H
	end

	-- The plan's points on this floor in map space (0..1 of the drawn picture): floating panels must not cover them.
	-- Cached per plan revision, floor and map alignment.
	function view:ContentMapPoints()
		local plan = self.cb.getPlan and self.cb.getPlan()
		if not plan then
			return {}
		end
		local key = tostring(plan.id) .. ":" .. tostring(ns.DB and ns.DB.Revision(plan) or 0) .. ":"
			.. tostring(self.cb.getFloor()) .. ":" .. tostring(self.xf)
		if self.contentKey ~= key then
			local pts = {}
			for _, p in ipairs(self:ContentPoints()) do
				local x, y = self:ToMap(p[1], p[2])
				if type(x) == "number" and type(y) == "number" then
					pts[#pts + 1] = { x, y }
				end
			end
			self.contentKey, self.contentPts = key, pts
		end
		return self.contentPts
	end

	-- The whole map at zoom 1 (MapLayout.MapFit): as large as the frame allows, always centred, the floating panels
	-- (the legend, the map's controls: view.fitAvoid() gives their boxes) over its edges and, where shrinking a little
	-- about the centre does it, clear of the plan. Cached per size, panels and plan.
	function view:FitBox()
		local w, h = self:BaseSize()
		local avoid = self.fitAvoid and self.fitAvoid() or nil
		local parts = { w, h, self:GetWidth(), self:GetHeight(), self.reserveRight or 0, tostring(self.fitBeside) }
		for _, r in ipairs(avoid or {}) do
			parts[#parts + 1] = table.concat(r, ",")
		end
		local pts = avoid and self:ContentMapPoints() or nil
		parts[#parts + 1] = tostring(self.contentKey)
		local key = table.concat(parts, ":")
		if self.fitKey ~= key then
			self.fitKey = key
			self.fitBox = ns.MapLayout.MapFit({ viewW = self:GetWidth(), viewH = self:GetHeight(), baseW = w, baseH = h,
				inset = FRAME_INSET, reserveRight = self.reserveRight or 0, besideRight = self.fitBeside, avoid = avoid, points = pts })
		end
		return self.fitBox
	end

	-- Is the whole map at its full size and centred (no panel made it smaller or moved it)?
	function view:FitIsWhole()
		local box = self:FitBox()
		local w, h = self:BaseSize()
		local availW, availH = (self:GetWidth() or 0) - 2 * FRAME_INSET, (self:GetHeight() or 0) - 2 * FRAME_INSET
		if not box or availW <= 0 or availH <= 0 then
			return true
		end
		local full = math.min(availW / w, availH / h)
		return math.abs(box.scale - full) < 1e-6 and math.abs(box.ox - (FRAME_INSET + (availW - w * full) / 2)) < 0.5
	end

	-- Scale that fits the whole map inside the frame.
	function view:FitScale()
		local box = self:FitBox()
		return box and box.scale > 0 and box.scale or 1
	end

	function view:Scale()
		return self:FitScale() * self.zoom
	end

	function view:Aspect()
		local w, h = self:BaseSize()
		return w / h
	end

	-- Keep at least a quarter of the map inside the view.
	function view:ClampPan()
		local w, h = self:BaseSize()
		local s = self:Scale()
		local cw, ch = w * s, h * s
		local vw, vh = self:GetWidth(), self:GetHeight()
		-- The whole map (zoom 1): where the fit puts it (centred, clear of the legend). Zoomed in and narrower than the
		-- room left of the legend: centred there. Wider: where the pointer put it, kept in reach.
		local box = math.abs((self.zoom or 1) - 1) < 1e-6 and self:FitBox() or nil
		if box then
			self.ox, self.oy = box.ox, box.oy
			return
		end
		if cw <= vw - (self.reserveRight or 0) then
			self.ox = (vw - (self.reserveRight or 0) - cw) / 2
		else
			self.ox = Util.Clamp(self.ox, vw - cw - vw / 4, vw / 4)
		end
		if ch <= vh then
			self.oy = (vh - ch) / 2
		else
			self.oy = Util.Clamp(self.oy, vh - ch - vh / 4, vh / 4)
		end
	end

	-- During a pan only the canvas moves (pins, routes and drawings are anchored to it); Layout runs on release, so label
	-- placement against the legend and everything else is done once (UI/MapInput.lua).
	function view:MoveCanvas()
		self:ClampPan()
		canvas:ClearAllPoints()
		canvas:SetPoint("TOPLEFT", self, "TOPLEFT", self.ox, -self.oy)
		self:PlaceCredit()
	end

	-- Put something on the current floor: `add(floor)` returns it or nil and an error. The map section makes a floor
	-- only the map had part of the plan first, and takes it back when the add fails.
	function view:AddOnFloor(add)
		if self.cb.addOnFloor then
			return self.cb.addOnFloor(add)
		end
		return add(self.cb.getFloor())
	end

	-- The credit chip sits in the map's own top-left corner (inside the picture, not on the frame's empty band above
	-- it), or in the frame's corner when that corner of the map is scrolled out of view.
	function view:PlaceCredit()
		local x = math.max(FRAME_INSET, self.ox or 0) + SP.sm
		local y = math.max(FRAME_INSET, self.oy or 0) + SP.sm
		self.credit:ClearAllPoints()
		self.credit:SetPoint("TOPLEFT", self, "TOPLEFT", math.floor(x + 0.5), -math.floor(y + 0.5))
	end

	-- Fit the whole map again when the panels or the plan moved its fit (zoom 1 only). Returns true when it laid out
	-- (and drew) the map.
	function view:Refit()
		if math.abs((self.zoom or 1) - 1) >= 1e-6 or self:FitBox() == self.laidFit then
			return false
		end
		self:Layout()
		return true
	end

	function view:Layout()
		self:MoveCanvas()
		self.laidFit = math.abs((self.zoom or 1) - 1) < 1e-6 and self.fitBox or nil
		local w, h = self:BaseSize()
		local s = self:Scale()
		canvas:SetSize(math.max(1, w * s), math.max(1, h * s))
		local a = self.artInfo
		if a and a.pieces then
			self:LayoutPieces(a, s)
		elseif a then
			local cols = math.ceil(a.width / a.tileWidth)
			for i, tex in ipairs(self.tiles) do
				local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
				-- The last column and row may use only part of their tile (the old dungeon maps: 234 and 156 of 256 px).
				local tw = math.min(a.tileWidth, a.width - col * a.tileWidth)
				local th = math.min(a.tileHeight, a.height - row * a.tileHeight)
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * a.tileWidth * s, -row * a.tileHeight * s)
				tex:SetSize(math.max(1, tw) * s, math.max(1, th) * s)
				tex:SetTexCoord(0, math.max(0, tw) / a.tileWidth, 0, math.max(0, th) / a.tileHeight)
			end
		end
		self:LayoutGrid()
		self:DrawContent()
	end

	-- A map made of placed pictures (Data/MinimapArt.lua): each piece at its own box in map units, its texture
	-- coordinates given at the box's four corners (a picture may be turned or cut).
	function view:LayoutPieces(a, s)
		for i, p in ipairs(a.pieces) do
			local tex = self.tiles[i]
			if tex then
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", p.x * s, -p.y * s)
				tex:SetSize(math.max(1, p.w * s), math.max(1, p.h * s))
				local c = p.coords
				tex:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
				local lift = self.lifts[i]
				if lift then
					lift:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
				end
			end
		end
	end

	-- Pools ---------------------------------------------------------------------------------------------------------------

	local pools = view.pools

	local function newPin(parentFrame)
		return MapPins.New(view, parentFrame)
	end

	local function getPin(i)
		local b = pools.pins[i]
		if b then
			return b
		end
		b = newPin(view.overlay)
		b:SetScript("OnClick", function(self, mouse)
			view:OnMarkerClick(self.markerId, mouse, self)
		end)
		b:SetScript("OnDragStart", function(self)
			if view.cb.getTool() == "select" and not view.cb.readOnly() then
				view.drag = { mode = "marker", id = self.markerId }
				view:SetScript("OnUpdate", view.OnDragUpdate)
			end
		end)
		b:SetScript("OnDragStop", function()
			view:EndDrag()
		end)
		b:SetScript("OnEnter", function(self)
			view:MarkerTooltip(self)
		end)
		b:SetScript("OnLeave", function(self)
			local tt = W.Tip()
			if tt and tt:IsOwned(self) then
				tt:Hide()
			end
		end)
		pools.pins[i] = b
		return b
	end

	-- Route points: numbered stops (always) and bends (while that route is being edited).
	local function getPoint(i)
		local b = pools.points[i]
		if b then
			return b
		end
		b = newPin(view.overlay)
		b:SetFrameLevel(view.overlay:GetFrameLevel() + 3)
		b:SetScript("OnClick", function(self, mouse)
			view:OnPointClick(self.routeId, self.pointIndex, mouse, self)
		end)
		b:SetScript("OnDragStart", function(self)
			local tool = view.cb.getTool()
			if (tool == "select" or tool == "route") and not view.cb.readOnly() then
				view.drag = { mode = "point", routeId = self.routeId, index = self.pointIndex }
				view:SetScript("OnUpdate", view.OnDragUpdate)
			end
		end)
		b:SetScript("OnDragStop", function()
			view:EndDrag()
		end)
		b:SetScript("OnEnter", function(self)
			view:PointTooltip(self)
		end)
		b:SetScript("OnLeave", function(self)
			local tt = W.Tip()
			if tt and tt:IsOwned(self) then
				tt:Hide()
			end
		end)
		pools.points[i] = b
		return b
	end

	local function getJournalPin(i)
		local b = pools.journal[i]
		if b then
			return b
		end
		b = newPin(view.overlay)
		b:SetScript("OnEnter", function(self)
			local tt = W.Tip()
			if not tt then
				return
			end
			W.TipBeside(tt, self)
			tt:SetText(self.name or "", 1, 0.82, 0)
			tt:AddLine(self.source and string.format(L["Boss position from %s"], self.source)
				or L["Boss position from the Adventure Guide"], 1, 1, 1, true)
			W.TipShow(tt)
		end)
		b:SetScript("OnLeave", function(self)
			local tt = W.Tip()
			if tt and tt:IsOwned(self) then
				tt:Hide()
			end
		end)
		b:SetScript("OnClick", function(_, mouse)
			view:OnMapClick(mouse)
		end)
		pools.journal[i] = b
		return b
	end

	-- The visible part of the map (within the gold frame) in canvas units (y down), or nil before it is laid out.
	local function visibleBox()
		local box = { FRAME_INSET - view.ox, FRAME_INSET - view.oy, view:GetWidth() - FRAME_INSET - view.ox,
			view:GetHeight() - FRAME_INSET - view.oy }
		if box[3] - box[1] < 40 or box[4] - box[2] < 40 then
			return nil -- not laid out yet
		end
		return box
	end
	-- Where route arrows and dashes are made: the visible map and a margin of one view size on every side, in canvas
	-- offsets (y up), so a pan (which moves the canvas without a redraw) shows them on the map it reveals; beyond that
	-- they come with the redraw on release.
	local function routeBounds(shown)
		local mw, mh = shown and shown[3] - shown[1], shown and shown[4] - shown[2]
		return shown and { shown[1] - mw, -shown[4] - mh, shown[3] + mw, -shown[2] + mh }
	end

	-- Labels keep clear of what floats over the map (the legend: view.avoidFrame, set by the map section; the note shown
	-- when a map has no art).
	local function applyLayout(list)
		local avoid
		for _, over in ipairs({ view.avoidFrame or false, view.noArt }) do
			if over and over:IsShown() then
				local l, t, r, b = over:GetLeft(), over:GetTop(), over:GetRight(), over:GetBottom()
				local cl, ct = canvas:GetLeft(), canvas:GetTop()
				if l and t and r and b and cl and ct then
					-- A font string has no scale of its own: its frame's.
					local scaled = over.GetEffectiveScale and over or over:GetParent()
					local k = (scaled:GetEffectiveScale() or 1) / (canvas:GetEffectiveScale() or 1)
					avoid = avoid or {}
					avoid[#avoid + 1] = { l * k - cl, ct - t * k, r * k - cl, ct - b * k }
				end
			end
		end
		-- And the names painted on the map (a bundled map's keepOut, in the picture's 0..1), where another side is free.
		local bw, bh = view:BaseSize()
		avoid = MapCanvas.KeepOutRects(view.artInfo, bw, bh, view:Scale(), avoid)
		-- Labels stay inside the visible part of the map (within the gold frame), in canvas units.
		local bounds = visibleBox()
		-- And the coordinate readout (shown while the pointer is over the map) where it is anchored: the bottom-right
		-- corner, or above the floor switcher (UI/Panels/FloorBar.lua). Its right and bottom edges from its anchor, the
		-- room its widest text takes measured once per font. view.coordsBox: that rectangle in canvas units.
		view.coordsBox = nil
		if bounds and view.cb.showCoordinates and view.cb.showCoordinates() then
			local c = view.coords
			local font = c:GetFont()
			if view.coordsFont ~= font then
				local text = c:GetText()
				c:SetText("100.0, 100.0")
				view.coordsFont, view.coordsW, view.coordsH = font, c:GetStringWidth() or 0, c:GetStringHeight() or 0
				c:SetText(text or "")
			end
			local r, b, cl, ct = c:GetRight(), c:GetBottom(), canvas:GetLeft(), canvas:GetTop()
			if r and b and cl and ct then
				local k = (c:GetParent():GetEffectiveScale() or 1) / (canvas:GetEffectiveScale() or 1)
				local right, bottom = r * k - cl, ct - b * k
				view.coordsBox = { right - (view.coordsW + SP.xs) * k, bottom - (view.coordsH + SP.xs) * k, right + SP.xs * k,
					bottom + SP.xs * k }
				avoid = avoid or {}
				avoid[#avoid + 1] = view.coordsBox
			end
		end
		MapPins.ApplyLayout(list, canvas, avoid, bounds)
		return bounds
	end

	-- Visibility ----------------------------------------------------------------------------------------------------------

	local function layerShown(layerId)
		return view.cb.layerVisible == nil or view.cb.layerVisible(layerId)
	end

	-- Positions tied to a boss or a pull show while that boss or pull is in focus; untied ones always, except on a
	-- compact map (run mode), which shows only the current step's.
	local function positionShown(m, focusPull, focusEncounter, compact)
		if m.kind ~= "position" then
			return true
		end
		if m.encounter then
			return focusEncounter == m.encounter
		end
		if m.pull then
			return focusPull == m.pull
		end
		return not compact
	end
	MapCanvas.PositionShown = positionShown

	-- Content -----------------------------------------------------------------------------------------------------------

	function view:DrawContent()
		local plan = self.cb.getPlan()
		local floor = self.cb.getFloor()
		local nPins, nLines, nArrows, nPoints, nJournal, nSpawns = 0, 0, 0, 0, 0, 0
		local pathsDrawn = false
		local layout = {}
		if plan then
			local w, h = self:BaseSize()
			local s = self:Scale()
			local scale = (self.cb.iconScale and self.cb.iconScale() or 1)
			local selected = self.cb.getSelectedMarker()
			local focusPull = self.cb.getFocusPull and self.cb.getFocusPull()
			local focusEncounter = self.cb.getFocusEncounter and self.cb.getFocusEncounter()
			local activeRoute = self.cb.getActiveRoute and self.cb.getActiveRoute()
			local editingRoutes = self.cb.getTool() == "route"
			-- The focused step's route segment (points from..to of one route) is drawn bold; the rest of the path dims.
			local seg = self.cb.getFocusSegment and self.cb.getFocusSegment()
			-- A compact map (run mode's): no labels, no numbered stops, only the current step's positions, and a ring
			-- where the current step is.
			local compact = self.cb.compact and self.cb.compact()
			-- Plan coordinates to canvas pixels (through a provider map's alignment when there is one).
			-- px(x, y) and py(y, x) take both coordinates: a minimap floor's transform mixes them (MinimapArt.ToMap).
			local xf = self.xf
			local function px(x, y)
				return (xf and (x * xf.sx + (xf.kx or 0) * (y or 0) + xf.tx) or x) * w * s
			end
			local function py(y, x)
				return -(xf and ((xf.ky or 0) * (x or 0) + y * xf.sy + xf.ty) or y) * h * s
			end
			-- Pins already in map space (a provider's boss pins).
			local function mx(x)
				return x * w * s
			end
			local function my(y)
				return -y * h * s
			end
			local provided = self.provided
			local pinsOnly = provided and provided.align and provided.align.mode == "pins"

			-- Where enemies stand (Data/Spawns.lua), under everything the plan draws.
			local spawns = self.cb.spawnsShown and self.cb.spawnsShown()
			nSpawns = self:DrawSpawns(spawns and plan or nil, floor, px, py, scale)

			-- Routes under the pins (UI/MapRoutes.lua): the paths (cased lines, joints at bends), then the stops; the
			-- direction arrows once the pins and labels are laid out (below), so they keep clear of them.
			-- Another addon's route as an extra layer (Data/Providers.lua Routes), in the map's own coordinates.
			local extra = not compact and self.cb.providerRoutesShown and self.cb.providerRoutesShown()
				and MapCanvas.ProviderRoutes(plan, floor, self.artInfo) or nil
			if layerShown("route") or extra then
				local own = layerShown("route") and plan or nil
				local drawn = self:DrawRoutePaths(own, floor, px, py, { scale = scale, seg = seg, activeRoute = activeRoute,
					extra = extra, mx = mx, my = my, deferArrows = true, bounds = routeBounds(visibleBox()),
					-- Run mode: the current step's leg highlighted as a hovered one is (UI/MapRoutes.lua SetRouteHover).
					highlight = self.cb.highlightFocus and self.cb.highlightFocus() and seg or nil })
				nLines, pathsDrawn = drawn.lines, true
				self.routeCounts = drawn
				if own then
					nPoints = self:DrawRouteStops(plan, floor, px, py, { getPoint = getPoint, layout = layout, scale = scale,
						seg = seg, activeRoute = activeRoute, editing = editingRoutes, compact = compact,
						stopNumber = self.cb.stopNumber, drawTool = self.cb.drawTool and self.cb.drawTool() })
				end
			end

			-- Drawings (UI/MapDraw.lua): over the route, under every pin. Run mode's mini map follows its own setting
			-- (the current step's drawings, all, or none); the full map shows all and dims those of other steps.
			local drawMode = not layerShown("drawings") and "off"
				or (compact and (self.cb.drawingsMode and self.cb.drawingsMode() or "step")) or "all"
			self:DrawShapes(plan, floor, { px = px, py = py, scale = scale, mode = drawMode, focusPull = focusPull,
				focusEncounter = focusEncounter, selected = self.cb.getSelectedShape and self.cb.getSelectedShape() })
			-- While a drawing tool is in use, pins let presses through to the map, so strokes can start anywhere.
			local drawing = self.cb.drawTool and self.cb.drawTool() ~= nil

			-- Markers.
			local bossesOnFloor = false
			for _, m in ipairs(plan.markers) do
				if m.floor == floor then
					if m.kind == "boss" then
						bossesOnFloor = true
					end
					local layer = Schema.KIND_LAYER[m.kind] or "notes"
					-- On a provider map the plan's boss markers do not line up with: its pins stand in for them.
					local hidden = pinsOnly and m.kind == "boss" and m.id ~= selected
					if not hidden and layerShown(layer) and positionShown(m, focusPull, focusEncounter, compact) then
						nPins = nPins + 1
						local b = getPin(nPins)
						b.markerId = m.id
						b:EnableMouse(not drawing)
						local size = stylePin(b, plan, m, scale)
						b:ClearAllPoints()
						b:SetPoint("CENTER", canvas, "TOPLEFT", px(m.x, m.y), py(m.y, m.x))
						if selected == m.id then
							b.select:ClearAllPoints()
							b.select:SetPoint("CENTER")
							b.select:SetSize(size + 10, size + 10)
							b.select:Show()
						end
						local dimmed = (focusPull and m.pull ~= focusPull and m.kind ~= "boss")
							or (focusEncounter and m.encounter and m.encounter ~= focusEncounter)
						b:SetAlpha(dimmed and 0.4 or 1)
						-- Labels: bosses always (gold, like the journal's map), the rest when labels are on.
						if compact then
							b.label:SetText("")
						elseif m.label ~= "" and (m.kind == "boss" or selected == m.id or self.cb.showLabels()) then
							b.label:SetText(m.label)
							S.TextColor(b.label, m.kind == "boss" and "gold" or "white")
						else
							if m.kind == "boss" and m.label == "" then
								local _, enc = boss(plan, m)
								b.label:SetText(enc and ns.Names.Encounter(enc) or "")
								S.TextColor(b.label, "gold")
							end
						end
						-- Stairs and portals say where they lead, labels on or off.
						if not compact and m.toFloor and plan.floors[m.toFloor] then
							local to = string.format(L["to %s"], ns.Names.Floor(plan.floors[m.toFloor], m.toFloor, plan))
							local text = b.label:GetText() or ""
							b.label:SetText(text ~= "" and (text .. "  \226\128\162  " .. to) or to)
							S.TextColor(b.label, "goldBright")
						end
						b:Show()
						local kind = m.kind == "boss" and "boss" or (m.kind == "pack" or m.kind == "patrol") and "disc" or "pin"
						local prio = selected == m.id and 4 or m.kind == "boss" and 3 or 1
						layoutItem(layout, b, px(m.x, m.y), -py(m.y, m.x), size, kind, prio)
					end
				end
			end

			-- The Adventure Guide's own boss pins: while your plan has no boss on this floor, or, for a recommended plan
			-- and its copies (which place only the bosses their research found), for each boss the plan does not place.
			if layerShown("bosses") and self.journalMapID and (not bossesOnFloor or plan.bundled or plan.origin) then
				local pins = ns.Instances.JournalPins(self.journalMapID, self.journalInstanceID)
				if plan.bundled or plan.origin then
					pins = ns.Instances.PinsNotPlaced(plan, floor, pins)
				end
				for _, pin in ipairs(pins) do
					nJournal = nJournal + 1
					local b = getJournalPin(nJournal)
					b:EnableMouse(not drawing)
					local size = BOSS_SIZE * scale
					resetPin(b, size)
					styleRound(b, size, ns.Journal.BossArtById(pin.ejEncounterID) or "kind_boss", "bossRing")
					b.name, b.source = pin.name, nil
					b.label:SetText(compact and "" or pin.name)
					S.TextColor(b.label, "gold")
					b:SetAlpha(0.9)
					b:ClearAllPoints()
					b:SetPoint("CENTER", canvas, "TOPLEFT", px(pin.x, pin.y), py(pin.y, pin.x))
					b:Show()
					layoutItem(layout, b, px(pin.x, pin.y), -py(pin.y, pin.x), size, "boss", 3)
				end
			end
			-- A provider map's own boss pins: for the bosses the plan does not place, or for every boss when the plan's
			-- boss markers do not line up with that map (Providers.Align "pins").
			if provided and layerShown("bosses") and #(provided.pins or {}) > 0 then
				local pins = pinsOnly and provided.pins or ns.Instances.PinsNotPlaced(plan, floor, provided.pins)
				for _, pin in ipairs(pins) do
					nJournal = nJournal + 1
					local b = getJournalPin(nJournal)
					b:EnableMouse(not drawing)
					local size = BOSS_SIZE * scale
					resetPin(b, size)
					styleRound(b, size, "kind_boss", "bossRing")
					b.name, b.source = pin.name, provided.pinsCredit or provided.credit
					b.label:SetText(compact and "" or pin.name)
					S.TextColor(b.label, "gold")
					b:SetAlpha(0.9)
					b:ClearAllPoints()
					b:SetPoint("CENTER", canvas, "TOPLEFT", mx(pin.x), my(pin.y))
					b:Show()
					layoutItem(layout, b, mx(pin.x), -my(pin.y), size, "boss", 3)
				end
			end
			-- The current step's spot on a compact map.
			local fp = compact and self.cb.getFocusPoint and self.cb.getFocusPoint()
			if fp and fp.floor == floor and type(fp.x) == "number" and type(fp.y) == "number" then
				local size = 40 * math.max(0.75, scale)
				local r, g, bl = S.Color("accent")
				for _, tex in ipairs({ self.focusGlow, self.focusRing }) do
					tex:ClearAllPoints()
					tex:SetPoint("CENTER", canvas, "TOPLEFT", px(fp.x, fp.y), py(fp.y, fp.x))
					tex:SetSize(size, size)
					tex:Show()
				end
				self.focusGlow:SetVertexColor(r, g, bl, 0.28)
				self.focusRing:SetVertexColor(r, g, bl, 0.95)
			else
				self.focusGlow:Hide()
				self.focusRing:Hide()
			end
			local shown = applyLayout(layout)
			if pathsDrawn then
				-- Arrows clear of the pins and labels, only on the visible map and its margin (routeBounds).
				local obstacles = ns.RouteArrows.Obstacles(layout, true)
				obstacles.bounds = routeBounds(shown)
				nArrows = self:PlaceRouteArrows(obstacles)
			end
		end
		for i = nPins + 1, #pools.pins do
			pools.pins[i]:Hide()
		end
		if not pathsDrawn then
			self:DrawRoutePaths(nil) -- the route layer hidden or no plan: hide every pooled path piece
		end
		for i = nPoints + 1, #pools.points do
			pools.points[i]:Hide()
		end
		for i = nJournal + 1, #pools.journal do
			pools.journal[i]:Hide()
		end
		if not plan then
			self:DrawShapes(nil)
			self:DrawSpawns(nil)
			self.focusGlow:Hide()
			self.focusRing:Hide()
		end
		self.counts = { pins = nPins, lines = nLines, arrows = nArrows, points = nPoints, journal = nJournal,
			spawns = nSpawns, shapes = self.drawCounts and self.drawCounts.shapes or 0 }
	end

	-- Tooltips and input live in UI/MapInput.lua.
	MapCanvas.InstallInput(view)

end
