-- The map's legend (UI/Panels/MapPanel.lua): the layer switches, each layer with its icon, its count on this floor and
-- a check box, plus "Enemies" where spawn data exists and "Addon route" where another addon has a route here. Its
-- title is a disclosure: folded, the legend is that one line, so the art under it (a map's painted title in that
-- corner) shows; the choice is saved (ui.legendFolded).

local _, ns = ...
local S, W, L, Art = ns.Style, ns.Widgets, ns.L, ns.Art
local Schema = ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local MapLegend = {}
ns.MapLegend = MapLegend

local LAYER_TEXT = {
	spawns = "Enemies",
	bosses = "Bosses and rares",
	enemies = "Packs and patrols",
	loot = "Loot and chests",
	quests = "Quests and NPCs",
	travel = "Entrances and exits", -- the full name, "Entrances, exits and shortcuts", did not fit the legend
	hazards = "Hazards",
	positions = "Party positions",
	notes = "Notes",
	route = "Route",
	drawings = "Drawings",
	providerRoutes = "Routes: %s",
}
local LAYER_ART = {
	spawns = "skull",
	bosses = "kind_boss",
	enemies = "skull",
	loot = "kind_loot",
	quests = "kind_quest_npc",
	travel = "kind_entrance",
	hazards = "kind_hazard",
	positions = "role_TANK",
	notes = "kind_note",
	route = "sectionPulls",
	drawings = "drawings",
	providerRoutes = "sectionPulls",
}

local HEAD_H = 18 -- the title line

-- Folded: the player's choice (ui.legendFolded), else as the map section decided for this map (MapLegend.auto: folded
-- where the open legend would cover the plan on the whole, centred map).
MapLegend.auto = false
function MapLegend.Folded()
	if ns.db.ui.legendFolded ~= nil then
		return ns.db.ui.legendFolded == true
	end
	return MapLegend.auto == true
end

-- The legend inside `rail`. o = { canvas, layerVisible(id), onToggle() (lays the map section out again) }.
function MapLegend.Build(rail, o)
	local canvas = o.canvas
	local legend = CreateFrame("Frame", nil, rail)
	legend:SetPoint("TOPLEFT", SP.md, -SP.md)
	legend:SetPoint("RIGHT", -SP.md, 0)
	legend.heading = W.Disclosure(legend, L["Legend"], function(open)
		ns.db.ui.legendFolded = not open
		if o.onToggle then
			o.onToggle()
		end
	end)
	legend.heading:SetPoint("TOPLEFT")
	legend.heading:SetHeight(HEAD_H)
	W.SetTooltip(legend.heading, L["Legend"], L["Fold the legend to its title, so the map under it shows; click again to open it."])
	legend.rows = {}
	local layers = {}
	for i, layer in ipairs(Schema.LAYERS) do
		layers[#layers + 1] = layer
		if i == 2 then
			layers[#layers + 1] = { id = "spawns", spawns = true } -- Data/Spawns.lua: where enemies stand
		end
	end
	layers[#layers + 1] = { id = "providerRoutes", providerRoutes = true } -- another addon's route (Data/Providers.lua)
	for _, layer in ipairs(layers) do
		local row = CreateFrame("Frame", nil, legend)
		row:SetHeight(SZ.small + 2)
		row.check = W.Check(row, "", function(on)
			ns.db.ui.mapLayers[layer.id] = on and true or false
			canvas:DrawContent()
		end)
		row.index = #legend.rows + 1
		row.check:SetPoint("LEFT")
		row.check:SetWidth(SZ.small)
		row.icon = Art.RoundTexture(row, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", SZ.small + SP.xs, 0)
		Art.Set(row.icon, LAYER_ART[layer.id])
		row.text = W.Text(row, "caption", "ink")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", SP.sm, 0)
		row.text:SetPoint("RIGHT", -22, 0)
		row.text:SetText(L[LAYER_TEXT[layer.id]])
		row.count = W.Text(row, "caption", "muted")
		row.count:SetPoint("RIGHT")
		row.count:SetJustifyH("RIGHT")
		row.layer = layer
		legend.rows[#legend.rows + 1] = row
	end

	function legend:IsFolded()
		return MapLegend.Folded()
	end

	-- Counts on this floor and the switches' state; the rows that apply, one under the other (none while folded).
	function legend:Update(p, floor, artInfo)
		local folded = MapLegend.Folded()
		self.heading:SetOpen(not folded)
		local counts = {}
		for _, m in ipairs(p.markers) do
			if m.floor == floor then
				local layer = Schema.KIND_LAYER[m.kind] or "notes"
				counts[layer] = (counts[layer] or 0) + 1
			end
		end
		for _, r in ipairs(p.routes) do
			if r.floor == floor then
				counts.route = (counts.route or 0) + 1
			end
		end
		counts.spawns = #ns.MapSpawns.Visible(p, floor)
		counts.drawings = ns.Drawing.Count(p, floor)
		local extraRoutes, extraInfo = ns.MapCanvas.ProviderRoutes(p, floor, artInfo)
		counts.providerRoutes = extraRoutes and #extraRoutes or 0
		local ry = -(HEAD_H + SP.sm)
		for _, row in ipairs(self.rows) do
			local spawns, provider = row.layer.spawns, row.layer.providerRoutes
			local shown = not folded and (not spawns or counts.spawns > 0) and (not provider or counts.providerRoutes > 0)
			row:SetShown(shown)
			if shown then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, ry)
				row:SetPoint("RIGHT")
				ry = ry - (SZ.small + 2)
			end
			if spawns then
				row.check:SetChecked(ns.MapSpawns.LayerShown(p))
			elseif provider then
				row.check:SetChecked(ns.db.ui.mapLayers.providerRoutes == true)
				-- The provider's full name does not fit the compact legend: a short label, the name in the tooltip.
				row.text:SetText(L["Addon route"])
				W.SetTooltip(row, L["Addon route"], string.format(L["Routes: %s"], extraInfo and extraInfo.credit or ""))
			else
				row.check:SetChecked(o.layerVisible(row.layer.id))
			end
			row.count:SetText(tostring(counts[row.layer.id] or 0))
			row.text:SetAlpha((counts[row.layer.id] or 0) > 0 and 1 or 0.55)
		end
		self:SetHeight(folded and HEAD_H or -ry)
	end
	return legend
end
