-- The map canvas's art (UI/MapCanvas.lua): the map picture as tiles or pieces (the client's map art, the game's old
-- dungeon map tiles, a minimap floor, Santiago Reyes' bundled maps or another addon's), its colours, the credit chip
-- that names who drew it, and the parchment grid that stands in where a map has no art.

local _, ns = ...
local MapCanvas = ns.MapCanvas
local S = ns.Style

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

-- Adds the art methods to a map view (MapCanvas.Create): SetMap, PaintArt, LayoutGrid.
function MapCanvas.InstallArt(view)
	local L = ns.L
	local canvas = view.canvas

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
		-- The bundled map's chip names the artist and his site (a tooltip: the client opens no links).
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

end
