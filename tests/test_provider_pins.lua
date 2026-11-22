-- A provider map whose boss pins match the plan's bosses by name but lie elsewhere (Providers.Align "pins"): the plan's
-- own boss markers stay where the plan puts them, because its route was made against them, and the provider's pins
-- show only for the bosses the plan does not place. Fake Dungeon Journal data (tests/wowmock.lua), pins moved here.
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("Map: on a provider map whose pins do not line up (\"pins\"), the plan's boss markers stay and lead", function()
	boot()
	mock.InstallProviders()
	ns.db.settings.preferProviderMaps = true
	ns.MinimapArt.Reset()
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	local plan = ns.Bundled.Get("b:hall-of-thanes")
	local at = {}
	for _, m in ipairs(plan.markers) do
		if m.floor == 1 and m.kind == "boss" then
			at[m.label] = m
		end
	end
	-- Each boss 0.1 away from the plan's marker, in directions no per-axis scale and offset can undo; one more boss
	-- the plan does not place.
	local moved = {}
	for i, name in ipairs({ "Faldrim Anvilmar", "Magmatus", "Plunder", "Durgen Dirgehammer" }) do
		local m = at[name]
		T.ok(m, name .. " is placed by the plan")
		local d = (i % 2 == 1) and 0.1 or -0.1
		moved[#moved + 1] = { name = name, x = m.x + d, y = m.y - d }
	end
	moved[#moved + 1] = { name = "A Boss The Plan Lacks", x = 0.3, y = 0.3 }
	local maps = _G.ForeverDungeonJournal_NS.DUNGEON_MAPS["Hall of Thanes"]
	local original, originalFloors = maps.bosses, maps.floors
	maps.bosses = moved
	-- Its picture is Santiago Reyes' bundled map (as Shaper's Terrace's is in Dungeon Journal), so the bundled map is
	-- drawn with the provider's pins and alignment.
	maps.floors = { { texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\HallOfThanesMap", texBottom = 683 / 1024 } }
	ns.ReyesMaps.Reset()

	local art = ns.Providers.FloorArt(plan, 1)
	T.ok(art and art.align, "the provider map and its alignment")
	T.eq(art.align.mode, "pins", "matched by name, neither the same nor fitted")
	T.eq(art.align.sx, 1, "drawn without a transform")

	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local canvas = map.canvas
	canvas.loadedKey = nil
	map:RefreshNow()
	T.eq(canvas.artInfo and canvas.artInfo.source, "reyes", "the bundled map")
	T.eq(canvas.provided and canvas.provided.align and canvas.provided.align.mode, "pins", "the canvas draws in that mode")

	-- The plan's boss markers are on the map, at the plan's own positions.
	local shown = {}
	for _, b in ipairs(canvas.pools.pins) do
		local m = b:IsShown() and b.markerId and ns.Util.FindById(plan.markers, b.markerId)
		if m and m.kind == "boss" then
			shown[m.label] = b
		end
	end
	local w, h = canvas:BaseSize()
	local s = canvas:Scale()
	for name, m in pairs(at) do
		local b = shown[name]
		T.ok(b, name .. ": the plan's marker is drawn")
		if b then
			local _, _, _, x, y = b:GetPoint(1)
			local u, v = canvas:ToMap(m.x, m.y)
			T.ok(math.abs(x - u * w * s) < 0.5 and math.abs(y + v * h * s) < 0.5, name .. ": at the plan's position")
		end
	end
	-- The provider's pins: only the boss the plan does not place.
	local journal = {}
	for _, b in ipairs(canvas.pools.journal) do
		if b:IsShown() and b.name then
			journal[b.name] = true
		end
	end
	T.ok(journal["A Boss The Plan Lacks"], "the provider's pin for a boss the plan lacks")
	for name in pairs(at) do
		T.ok(not journal[name], name .. ": no second pin from the provider")
	end

	maps.bosses, maps.floors = original, originalFloors
	mock.RemoveProviders()
	ns.ReyesMaps.Reset()
	ns.db.settings.preferProviderMaps = nil
	ns.MinimapArt.Reset()
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	canvas.loadedKey = nil
end)
