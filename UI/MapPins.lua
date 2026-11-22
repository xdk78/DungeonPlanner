-- Map pins: the pooled buttons the map canvas (UI/MapCanvas.lua) draws markers, route stops and boss pins on, their
-- styles (round art in a ring, unmasked art, pull-coloured discs), and where their labels go (Model/MapLayout.lua).
-- Labels sit on a dark plate so they stay readable over a map's own painted names. The route paths under the stops and
-- the stops themselves are drawn by UI/MapRoutes.lua.

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
		if it.covered then
			it.b:Hide() -- a route bend's handle under a pin
		end
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
