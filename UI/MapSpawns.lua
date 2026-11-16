-- The map's "Enemies" layer and step focus, installed on a map view (UI/MapCanvas.lua).
--
-- Enemies: where creatures stand on this floor (Data/Spawns.lua), drawn under the plan's own markers as small pooled
-- dots: red for ordinary enemies, a bronze ring for elites, a silver ring for rares, the game's skull for bosses, gold
-- for friendly NPCs. Dots closer than a few pixels at the current zoom merge into one dot with a count
-- (Model/MapLayout.lua Cluster), so a crowded room stays readable. Hovering shows names and levels. The dots pass
-- clicks and drags through to the map. Without spawn data (the module missing, unavailable, or empty for the floor)
-- nothing is drawn and the layer's legend row is hidden.
--
-- Also installed here: view:LoadPlanFloor(plan, floor) (the map art for a plan floor, shared by the map section and
-- run mode) and view:CenterOn(x, y, zoom), which brings a point to the middle of the view for the focused step (whose
-- route segment MapCanvas draws bold from cb.getFocusSegment()), view:FitContent() (Fit: the whole map, or on a map
-- without art the plan's markers), and view:ToMap / FromMap (plan space <-> the drawn picture, through a provider
-- map's alignment, Data/Providers.lua).

local _, ns = ...
local MapSpawns = ns:NewModule("MapSpawns")
local S, W = ns.Style, ns.Widgets

local MAX_DOTS = 300 -- bound on drawn dots (clusters) per redraw
local CELL = 9 -- screen units under which two dots merge (at icon scale 1)
local SIZE = { mob = 7, npc = 7, elite = 9, rare = 9, boss = 13 }
local RANK = { npc = 1, mob = 2, elite = 3, rare = 4, boss = 5 }
local COLOR = {
	mob = { 0.86, 0.22, 0.18 },
	elite = { 0.92, 0.38, 0.14 },
	rare = { 0.78, 0.80, 0.86 },
	boss = { 1, 1, 1 },
	npc = { 0.95, 0.84, 0.32 },
}
local RING = {
	elite = { 0.95, 0.76, 0.45 }, -- bronze
	rare = { 0.85, 0.88, 0.95 }, -- silver
}

-- Spawn data for a plan floor, or an empty list (guarded: the module may be missing or fail).
function MapSpawns.For(plan, floor)
	local mod = ns.Spawns
	if not (mod and type(mod.Available) == "function" and type(mod.For) == "function") then
		return {}
	end
	local okA, available = pcall(mod.Available)
	if not okA or not available then
		return {}
	end
	local ok, list = pcall(mod.For, plan, floor)
	if not ok or type(list) ~= "table" then
		return {}
	end
	return list
end

local function kindOf(sp)
	if sp.kind and RANK[sp.kind] then
		return sp.kind
	end
	return sp.rare and "rare" or sp.elite and "elite" or "mob"
end

local function describe(sp)
	local kind = kindOf(sp)
	local parts = {}
	if type(sp.level) == "number" then
		parts[#parts + 1] = string.format(ns.L["Level %d"], sp.level)
	end
	if kind == "elite" or (sp.elite and kind ~= "boss") then
		parts[#parts + 1] = ns.L["Elite"]
	end
	if kind == "rare" then
		parts[#parts + 1] = ns.L["Rare"]
	elseif kind == "boss" then
		parts[#parts + 1] = ns.L["Boss"]
	end
	return table.concat(parts, " ")
end

-- Spawns the plan already draws: one whose name is a marker's label, or that stands within DUP of a marker on the same
-- floor, is left out so pins are not doubled (recommended plans put their bosses exactly on the spawn data's bosses).
local DUP = 0.02
-- Cached per plan, floor and revision (DB.Revision) and the spawn module: the map's redraws, the legend's count and its row ask for it on
-- every refresh. The list is shared: read it, never change it.
local visibleCache = setmetatable({}, { __mode = "k" })
local function visible(plan, floor)
	local out = {}
	local list = MapSpawns.For(plan, floor)
	if #list == 0 then
		return out
	end
	local names, markers = {}, {}
	for _, m in ipairs(plan.markers or {}) do
		if m.floor == floor then
			markers[#markers + 1] = m
			if type(m.label) == "string" and m.label ~= "" then
				names[ns.Match.Norm(m.label)] = true
			end
		end
	end
	for _, sp in ipairs(list) do
		if type(sp) == "table" and type(sp.x) == "number" and type(sp.y) == "number" then
			local dup = type(sp.name) == "string" and names[ns.Match.Norm(sp.name)]
			if not dup then
				for _, m in ipairs(markers) do
					if math.abs(m.x - sp.x) <= DUP and math.abs(m.y - sp.y) <= DUP then
						dup = true
						break
					end
				end
			end
			if not dup then
				out[#out + 1] = sp
			end
		end
	end
	return out
end

function MapSpawns.Visible(plan, floor)
	local rev = ns.DB.Revision(plan)
	local hit = visibleCache[plan]
	if not hit or hit.rev ~= rev or hit.source ~= ns.Spawns then
		hit = { rev = rev, source = ns.Spawns, floors = {} }
		visibleCache[plan] = hit
	end
	local list = hit.floors[floor]
	if not list then
		list = visible(plan, floor)
		hit.floors[floor] = list
	end
	return list
end

-- Is the Enemies layer on for this plan? The legend switch when the player set it (ui.mapLayers.spawns), else on for
-- recommended plans and off for the player's own.
function MapSpawns.LayerShown(plan)
	if not plan then
		return false
	end
	local v = ns.db and ns.db.ui.mapLayers.spawns
	if v == nil then
		return plan.bundled == true
	end
	return v == true
end

-- Does this plan floor have enemies to show beyond its own markers (the legend row shows only then)?
function MapSpawns.Has(plan, floor)
	return plan ~= nil and #MapSpawns.Visible(plan, floor) > 0
end

function MapSpawns.Install(view)
	view.pools.spawns = {}
	local canvas = view.canvas

	local function forward(script)
		return function(_, mouse)
			local fn = view:GetScript(script)
			if fn then
				fn(view, mouse)
			end
		end
	end

	local function tooltip(b)
		local tt = W.Tip()
		if not tt or not b.members then
			return
		end
		W.TipBeside(tt, b)
		local members = b.members
		if #members == 1 then
			local sp = members[1]
			tt:SetText(tostring(sp.name or ns.L["Enemy"]), 1, 0.82, 0.55)
			local line = describe(sp)
			if line ~= "" then
				tt:AddLine(line, 1, 1, 1, true)
			end
		else
			tt:SetText(ns.Plural(#members, ns.L["%d enemy|%d enemies"]), 1, 0.82, 0.55)
			-- Same name and level counted once: "Defias Pirate (18) x3".
			local seen, order = {}, {}
			for _, sp in ipairs(members) do
				local key = tostring(sp.name or "?") .. "|" .. tostring(sp.level or "")
				if not seen[key] then
					seen[key] = { sp = sp, n = 0 }
					order[#order + 1] = key
				end
				seen[key].n = seen[key].n + 1
			end
			for i, key in ipairs(order) do
				if i > 8 then
					tt:AddLine("...", 0.7, 0.7, 0.7)
					break
				end
				local e = seen[key]
				local text = tostring(e.sp.name or "?")
				if type(e.sp.level) == "number" then
					text = text .. " (" .. e.sp.level .. ")"
				end
				if e.n > 1 then
					text = text .. " x" .. e.n
				end
				tt:AddLine(text, 1, 1, 1, true)
			end
		end
		W.TipShow(tt)
	end

	local function getDot(i)
		local pool = view.pools.spawns
		local b = pool[i]
		if b then
			return b
		end
		b = CreateFrame("Button", nil, view.overlay)
		b:SetFrameLevel(view.overlay:GetFrameLevel() + 1) -- under route stops (+3) and pins (+4)
		b.disc = b:CreateTexture(nil, "ARTWORK", nil, 0)
		b.disc:SetTexture(S.MEDIA .. "Circle")
		b.disc:SetAllPoints()
		b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.ring:SetTexture(S.MEDIA .. "Ring")
		b.ring:SetPoint("CENTER")
		b.skull = b:CreateTexture(nil, "ARTWORK", nil, 2)
		b.skull:SetAllPoints()
		ns.Art.Set(b.skull, "skull")
		b.count = W.Text(b, "caption", "white")
		b.count:SetPoint("CENTER", 0, 0)
		b.count:SetJustifyH("CENTER")
		b:SetScript("OnMouseDown", forward("OnMouseDown"))
		b:SetScript("OnMouseUp", forward("OnMouseUp"))
		b:SetScript("OnEnter", tooltip)
		b:SetScript("OnLeave", function(self)
			local tt = W.Tip()
			if tt and tt:IsOwned(self) then
				tt:Hide()
			end
		end)
		pool[i] = b
		return b
	end

	-- Draw the floor's spawns; returns how many dots (clusters) were drawn.
	function view:DrawSpawns(plan, floor, px, py, scale)
		local n = 0
		local list = plan and MapSpawns.Visible(plan, floor) or {}
		if #list > 0 then
			local points = {}
			for _, sp in ipairs(list) do
				if type(sp) == "table" and type(sp.x) == "number" and type(sp.y) == "number" then
					points[#points + 1] = { x = px(sp.x, sp.y), y = -py(sp.y, sp.x), sp = sp }
				end
			end
			local groups = ns.MapLayout.Cluster(points, CELL * math.max(0.6, scale), MAX_DOTS)
			for _, g in ipairs(groups) do
				n = n + 1
				local b = getDot(n)
				local members, top = {}, "npc"
				for i, p in ipairs(g.members) do
					members[i] = p.sp
					local k = kindOf(p.sp)
					if RANK[k] > RANK[top] then
						top = k
					end
				end
				b.members = members
				local size = (SIZE[top] + (#members > 1 and 4 or 0)) * math.max(0.75, scale)
				b:SetSize(size, size)
				local c = COLOR[top]
				b.disc:SetVertexColor(c[1], c[2], c[3], 0.95)
				b.disc:SetShown(top ~= "boss")
				b.skull:SetShown(top == "boss")
				local ring = RING[top]
				b.ring:SetSize(size + 2, size + 2)
				if ring then
					b.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
				else
					b.ring:SetVertexColor(0.05, 0.04, 0.03, 0.9)
				end
				b.ring:SetShown(top ~= "boss")
				b.count:SetText(#members > 1 and tostring(#members) or "")
				b:ClearAllPoints()
				b:SetPoint("CENTER", canvas, "TOPLEFT", g.x, -g.y)
				b:Show()
			end
		end
		local pool = self.pools.spawns
		for i = n + 1, #pool do
			pool[i]:Hide()
			pool[i].members = nil
		end
		return n
	end

	-- Plan space (0..1 as stored) <-> map space (0..1 of the drawn picture), through a provider map's alignment.
	function view:ToMap(x, y)
		return ns.MinimapArt.ToMap(self.xf, x, y)
	end

	function view:FromMap(x, y)
		return ns.MinimapArt.FromMap(self.xf, x, y)
	end

	-- The plan's own points on the current floor (markers, route points), in plan space.
	function view:ContentPoints()
		local plan = self.cb.getPlan()
		local floor = self.cb.getFloor()
		local pts = {}
		if not plan then
			return pts
		end
		for _, m in ipairs(plan.markers) do
			if m.floor == floor then
				pts[#pts + 1] = { m.x, m.y }
			end
		end
		for _, r in ipairs(plan.routes) do
			if r.floor == floor then
				for _, p in ipairs(r.points) do
					pts[#pts + 1] = { p[1], p[2] }
				end
			end
		end
		return pts
	end

	-- Fit: on a map without art (the parchment grid) frame the plan's markers instead of the empty grid
	-- (MapLayout.FitView); with art, or without markers, show the whole map.
	function view:FitContent()
		local pts = not self.artInfo and self:ContentPoints() or {}
		local w, h = self:BaseSize()
		local fit = ns.MapLayout.FitView(pts, { viewW = self:GetWidth(), viewH = self:GetHeight(), baseW = w, baseH = h,
			fitScale = self:FitScale(), inset = ns.MapCanvas.FRAME_INSET, reserveRight = self.reserveRight or 0 })
		if fit then
			self.zoom, self.ox, self.oy = fit.zoom, fit.ox, fit.oy
		else
			self.zoom, self.ox, self.oy = 1, 0, 0
		end
		self:Layout()
	end

	-- Show a plan's floor: the floor's own map (else the map the Adventure Guide gives the instance), and without an
	-- art layer (Forever has no dungeon UiMaps) the game's old dungeon map tiles (Data/GameFiles.lua). Reloads only when
	-- something changed.
	function view:LoadPlanFloor(plan, floor)
		local mapID, entry = ns.Journal.FloorMap(plan, floor)
		-- No map in the game: the old dungeon map tiles, the minimap pictures or another addon's map, in that order
		-- (Data/MinimapArt.lua).
		local art = ns.MinimapArt.Choose(plan, floor, mapID)
		local key = plan.id .. ":" .. floor
		-- The picture, not the table: a provider's art is rebuilt after every edit of the plan (its alignment follows
		-- the plan's boss markers), and the same picture must not send the view back to the whole map.
		local picture = art and (tostring(art.provider or art.source) .. ":" .. tostring(art.textures and art.textures[1])) or ""
		if self.loadedKey ~= key or self.loadedMap ~= mapID or self.loadedPicture ~= picture then
			self.loadedKey, self.loadedMap, self.loadedArt, self.loadedPicture = key, mapID, art, picture
			self:SetMap(mapID, mapID, entry and entry.ejInstanceID, art)
			return true
		elseif self.loadedArt ~= art then
			-- The same picture with a new alignment: taken over where the view stands.
			local zoom, ox, oy = self.zoom, self.ox, self.oy
			self.loadedArt = art
			self:SetMap(mapID, mapID, entry and entry.ejInstanceID, art)
			self.zoom, self.ox, self.oy = zoom, ox, oy
			self:Layout()
			return true
		elseif self.artStyle ~= ns.MapCanvas.ArtStyle(self.artInfo, ns.MapCanvas.MapColors()).name then
			-- The map colours setting changed: the same map, repainted where the view stands.
			self:PaintArt()
			return true
		end
		return false
	end

	-- Frame a step and its neighbours (run mode's mini map): `points` are plan coordinates { x, y }, the first the
	-- current step's; neighbours further than `reach` from it are left out, so a long walk does not shrink the step.
	-- The box is at least `minSpan` of the map, so the step's party positions have room around it.
	function view:FrameSteps(points, o)
		o = o or {}
		local first = points[1]
		if not first then
			return self:FitContent()
		end
		local reach = o.reach or 0.3
		local pts = {}
		for i, p in ipairs(points) do
			if i == 1 or (math.abs(p[1] - first[1]) <= reach and math.abs(p[2] - first[2]) <= reach) then
				local x, y = self:ToMap(p[1], p[2])
				pts[#pts + 1] = { x, y }
			end
		end
		local w, h = self:BaseSize()
		local fit = ns.MapLayout.FitView(pts, { viewW = self:GetWidth(), viewH = self:GetHeight(), baseW = w, baseH = h,
			fitScale = self:FitScale(), inset = ns.MapCanvas.FRAME_INSET, maxZoom = o.maxZoom or 3.5,
			pad = o.pad or 0.05, minSpan = o.minSpan or 0.22 })
		if not fit then
			return self:CenterOn(first[1], first[2], 1.8)
		end
		self.zoom, self.ox, self.oy = fit.zoom, fit.ox, fit.oy
		self:Layout()
	end

	-- Bring normalized (x, y) to the middle of the view at `zoom` (default: keep the zoom, at least 1.5); `dx` moves
	-- the target left or right of the middle (the map section keeps it clear of its floating legend).
	function view:CenterOn(x, y, zoom, dx)
		if type(x) ~= "number" or type(y) ~= "number" then
			return
		end
		self.zoom = zoom or math.max(self.zoom or 1, 1.5)
		x, y = self:ToMap(x, y)
		local w, h = self:BaseSize()
		local s = self:Scale()
		self.ox = self:GetWidth() / 2 + (dx or 0) - x * w * s
		self.oy = self:GetHeight() / 2 - y * h * s
		self:Layout()
	end
end
