-- The map canvas: the dungeon's map art (drawn at runtime; no Blizzard art is shipped) in a bronze-edged frame, with
-- the plan on it: round boss portraits, round icons in the minimap ring, pull-coloured discs for packs, role icons for
-- party positions, the route (UI/MapPins.lua) with numbered stops (the focused step's segment bold), and the Enemies layer
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
local resetPin, styleRound, styleDisc = MapPins.Reset, MapPins.StyleRound, MapPins.StyleDisc
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

-- Map colours. The classic dungeons draw on the old map tiles: a drawn map on sepia parchment. The game's minimap
-- pictures (Data/MinimapArt.lua) are dark 3D art or full-colour terrain; by default (settings.mapColors =
-- "parchment") they join that family: the parchment under them (where a building floor has no picture), each picture
-- in grey tinted to the parchment's brown, a little of the parchment showing through, and darkened edges. "game"
-- draws them as the minimap does. Other art (the old tiles, a drawn map: Santiago Reyes' bundled
-- maps, another addon's) is never touched.
-- Returns { name, paper, desaturate, tint = { r, g, b, a }, lift = the added copy's colour or nil, vignette } (pure).
local SEPIA = { 1, 0.8, 0.5, 0.9 }
local LIFT = { 0.62, 0.48, 0.24, 1 }
local VIGNETTE = { 0.22, 0.13, 0.05, 0.9 }
MapCanvas.SEPIA, MapCanvas.LIFT, MapCanvas.VIGNETTE = SEPIA, LIFT, VIGNETTE
function MapCanvas.ArtStyle(info, colors)
	if not info then
		return { name = "grid", paper = true, desaturate = false, tint = { 1, 1, 1, 1 }, vignette = false }
	end
	if info.source == "minimap" and colors ~= "game" then
		return { name = "parchment", paper = true, desaturate = true, tint = SEPIA, lift = LIFT, vignette = true }
	end
	return { name = "art", paper = false, desaturate = false, tint = { 1, 1, 1, 1 }, vignette = false }
end

-- The player's choice for minimap floors: "parchment" (the default) or "game".
function MapCanvas.MapColors()
	return ns.db and ns.db.settings.mapColors == "game" and "game" or "parchment"
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
	view.pools = { lines = {}, arrows = {}, points = {}, pins = {}, journal = {} } -- route paths: UI/MapPins.lua
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
	-- boss pins come from (Data/Providers.lua): a small chip
	-- in the corner, on a dark plate so the art under it does not show through. A compact map (run mode) leaves it to
	-- the window around it (view.creditText).
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
	ns.MapSpawns.Install(view)
	ns.MapRoutes.Install(view)
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

	-- Scale that fits the whole map inside the frame.
	function view:FitScale()
		local w, h = self:BaseSize()
		local vw, vh = self:GetWidth() - 2 * FRAME_INSET - (self.reserveRight or 0), self:GetHeight() - 2 * FRAME_INSET
		if vw <= 0 or vh <= 0 then
			return 1
		end
		return math.min(vw / w, vh / h)
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
		-- Narrower than the room left of the legend: centred there. Wider: where Fit or the pointer put it, kept in
		-- reach (re-centring it on the whole view would slide it under the legend).
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
	end

	function view:Layout()
		self:MoveCanvas()
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

	-- Art ---------------------------------------------------------------------------------------------------------------

	-- uiMapID: the map whose art is drawn. journalMapID: the map whose Adventure Guide boss pins are shown (normally
	-- the same); ejInstanceID: the journal instance, when known, for those pins. art: tiles to draw instead when the
	-- map has no art layer (the game's old dungeon map textures, Data/GameFiles.lua), in Instances.MapArt's shape.
	function view:SetMap(uiMapID, journalMapID, ejInstanceID, art)
		self.journalInstanceID = ejInstanceID
		for _, tex in ipairs(self.tiles) do
			tex:Hide()
		end
		local info = ns.Instances.MapArt(uiMapID) or art
		self.artInfo = info
		self.mapID = uiMapID
		self.journalMapID = journalMapID or uiMapID
		if info then
			for i, fileID in ipairs(info.textures) do
				local tex = self.tiles[i]
				if not tex then
					tex = self.art:CreateTexture(nil, "BACKGROUND", nil, 1)
					self.tiles[i] = tex
				end
				-- A turned minimap picture leaves the corners of its box outside the picture: clamped to transparent.
				local piece = info.pieces and info.pieces[i]
				if piece and piece.clamp then
					tex:SetTexture(fileID, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				else
					tex:SetTexture(fileID)
				end
				tex.dpFile, tex.dpClamp = fileID, piece and piece.clamp or false
				tex:Show()
			end
		end
		self:PaintArt()
		self.noArt:SetShown(info == nil)
		-- A drawn map: Santiago Reyes' bundled map (Data/ReyesMaps.lua) or another addon's. Name it, and draw the plan
		-- through the alignment found for it (Providers.Align; a bundled map takes it, and the boss pins, from an addon
		-- that draws the same picture).
		local reyes = info and info.source == "reyes"
		local provided = info and (info.source == "provider" or reyes) and info or nil
		self.provided = provided
		-- A minimap floor (Data/MinimapArt.lua) is drawn north up: the plan goes through that floor's own transform.
		local align = (provided and provided.align) or (info and info.source == "minimap" and info.align) or nil
		self.xf = align and align.mode == "fit" and align or nil
		if reyes then
			self.credit:SetText(string.format(L["Map by %s"], provided.artist or ns.ReyesMaps.ARTIST))
		elseif provided then
			local credit = string.format(L["Map: %s"], provided.credit or "")
			if provided.artist then
				credit = credit .. " (" .. provided.artist .. ")"
			end
			self.credit:SetText(credit)
		end
		self.creditText = provided and self.credit:GetText() or nil
		local showCredit = provided ~= nil and not (self.cb.compact and self.cb.compact())
		self.credit:SetShown(showCredit)
		self.creditPlate:SetShown(showCredit)
		-- The bundled map's chip names the artist's site and where to support him (a tooltip: the client opens no links).
		self.creditHit:SetShown(showCredit and reyes or false)
		self.zoom, self.ox, self.oy = 1, 0, 0
		self:Layout()
		if not info then
			self:FitContent()
		end
	end

	-- The colours of the art (MapCanvas.ArtStyle): a minimap floor in the parchment colours, or as the game draws it.
	function view:PaintArt()
		local info = self.artInfo
		local style = MapCanvas.ArtStyle(info, MapCanvas.MapColors())
		self.artStyle = style.name
		local n = info and #info.textures or 0
		for i, tex in ipairs(self.tiles) do
			if i <= n then
				if tex.SetDesaturated then
					tex:SetDesaturated(style.desaturate)
				end
				tex:SetVertexColor(style.tint[1], style.tint[2], style.tint[3], style.tint[4])
			end
			-- The lift: the same picture added on top (ADD), so the minimap's mid greys reach the parchment's light
			-- brown while its dark corridors stay dark.
			local lift = self.lifts[i]
			if style.lift and i <= n then
				if not lift then
					lift = self.art:CreateTexture(nil, "BACKGROUND", nil, 2)
					lift:SetAllPoints(tex)
					if lift.SetBlendMode then
						lift:SetBlendMode("ADD")
					end
					self.lifts[i] = lift
				end
				if tex.dpClamp then
					lift:SetTexture(tex.dpFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				else
					lift:SetTexture(tex.dpFile)
				end
				if lift.SetDesaturated then
					lift:SetDesaturated(true)
				end
				lift:SetVertexColor(style.lift[1], style.lift[2], style.lift[3], style.lift[4])
				local piece = info.pieces and info.pieces[i]
				if piece then
					local c = piece.coords
					lift:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
				end
				lift:Show()
			elseif lift then
				lift:Hide()
			end
		end
		self.paper:SetShown(style.paper)
		self.vignette:SetShown(style.vignette)
		self.vignette:SetVertexColor(VIGNETTE[1], VIGNETTE[2], VIGNETTE[3], VIGNETTE[4])
	end

	function view:LayoutGrid()
		local show = self.artInfo == nil
		local s = self:Scale()
		local w, h = self:BaseSize()
		local n = 0
		if show then
			for i = 1, 9 do
				for _, vertical in ipairs({ true, false }) do
					n = n + 1
					local line = self.gridLines[n]
					if not line then
						line = self.art:CreateTexture(nil, "BACKGROUND", nil, 2)
						line:SetColorTexture(1, 1, 1, 1)
						self.gridLines[n] = line
					end
					S.Tint(line, "grid")
					line:ClearAllPoints()
					if vertical then
						line:SetSize(1, h * s)
						line:SetPoint("TOPLEFT", canvas, "TOPLEFT", w * s * i / 10, 0)
					else
						line:SetSize(w * s, 1)
						line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -h * s * i / 10)
					end
					line:Show()
				end
			end
		end
		for i = n + 1, #self.gridLines do
			self.gridLines[i]:Hide()
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

	-- Labels keep clear of what floats over the map (the legend: view.avoidFrame, set by the map section).
	local function applyLayout(list)
		local avoid
		local over = view.avoidFrame
		if over and over:IsShown() then
			local l, t, r, b = over:GetLeft(), over:GetTop(), over:GetRight(), over:GetBottom()
			local cl, ct = canvas:GetLeft(), canvas:GetTop()
			if l and t and r and b and cl and ct then
				local k = (over:GetEffectiveScale() or 1) / (canvas:GetEffectiveScale() or 1)
				avoid = { { l * k - cl, ct - t * k, r * k - cl, ct - b * k } }
			end
		end
		-- Labels stay inside the visible part of the map (within the gold frame), in canvas units.
		local bounds = { FRAME_INSET - view.ox, FRAME_INSET - view.oy, view:GetWidth() - FRAME_INSET - view.ox,
			view:GetHeight() - FRAME_INSET - view.oy }
		if bounds[3] - bounds[1] < 40 or bounds[4] - bounds[2] < 40 then
			bounds = nil -- not laid out yet
		end
		MapPins.ApplyLayout(list, canvas, avoid, bounds)
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

			-- Routes under the pins: the paths (outlined lines, joints at bends, direction chevrons: MapRoutes in
			-- UI/MapPins.lua), then the stops.
			-- Another addon's route as an extra layer (Data/Providers.lua Routes), in the map's own coordinates.
			local extra = not compact and self.cb.providerRoutesShown and self.cb.providerRoutesShown()
				and MapCanvas.ProviderRoutes(plan, floor, self.artInfo) or nil
			if layerShown("route") or extra then
				local own = layerShown("route") and plan or nil
				local drawn = self:DrawRoutePaths(own, floor, px, py, { scale = scale, seg = seg, activeRoute = activeRoute,
					extra = extra, mx = mx, my = my })
				nLines, nArrows, pathsDrawn = drawn.lines, drawn.arrows, true
				self.routeCounts = drawn
				for _, route in ipairs(own and plan.routes or {}) do
					if route.floor == floor then
						local r, g, b = S.PaletteColor(route.color)
						local active = route.id == activeRoute
						for i, pt in ipairs(route.points) do
							if (pt.step and not compact) or active or editingRoutes then
								nPoints = nPoints + 1
								local p = getPoint(nPoints)
								p.routeId, p.pointIndex = route.id, i
								p:EnableMouse(not (self.cb.drawTool and self.cb.drawTool()))
								local size = (pt.step and 20 or 9) * math.max(0.75, scale)
								resetPin(p, size)
								p:ClearAllPoints()
								p:SetPoint("CENTER", canvas, "TOPLEFT", px(pt[1], pt[2]), py(pt[2], pt[1]))
								if pt.step then
									-- A dark disc with a ring in the route's colour: the number reads on any art and over the line.
									-- The number is the step's in the side panel (Steps.StopNumbers), not the stop's own order.
									local number = self.cb.stopNumber and self.cb.stopNumber(route.id, i) or pt.step
									styleDisc(p, size, 0.1, 0.07, 0.04, tostring(number))
									p.ring:SetVertexColor(r, g, b, 1)
									if seg and seg.route == route.id and seg.to == i then
										p.select:ClearAllPoints()
										p.select:SetPoint("CENTER")
										p.select:SetSize(size + 10, size + 10)
										p.select:SetVertexColor(S.Color("accent"))
										p.select:Show()
									end
								else
									p.disc:ClearAllPoints()
									p.disc:SetPoint("CENTER")
									p.disc:SetSize(size, size)
									p.disc:SetVertexColor(r, g, b, 1)
									p.disc:Show()
								end
								p:SetAlpha(route.optional and 0.7 or 1)
								p:Show()
								layoutItem(layout, p, px(pt[1], pt[2]), -py(pt[2], pt[1]), size, pt.step and "stop" or "pin", 0)
							end
						end
					end
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
			applyLayout(layout)
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
