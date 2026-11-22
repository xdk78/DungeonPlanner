-- /dp scan: what this client really returns, saved into DungeonPlannerDB.diagnostics (written on /reload) so it can be
-- read offline. On demand only, out of combat, never while the Blizzard journal is open. Compact: one string per row.
--
-- It answers, in one run: is the Adventure Guide empty, also after loading Blizzard_EncounterJournal and telling it it
-- was opened (and 3 seconds later); what the Group Finder lists (names, levels, instance map IDs, background
-- pictures); which of the plans' map IDs exist and have art; which maps carry a plan's instance or floor name; which
-- old dungeon map tiles and loading screens the client has (Data/GameFiles.lua); the portrait APIs; the UI font; and
-- whether the player's position and a targeted mob can be read where the scan runs (inside a dungeon: spawn recording).

local _, ns = ...
local Diagnostics = ns:NewModule("Diagnostics")
local Util = ns.Util

local function v(x)
	if x == nil then
		return ""
	end
	x = Util.Plain(x)
	return tostring(x)
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return false, "missing"
	end
	return pcall(fn, ...)
end

-- Instances the journal lists for each isRaid value, in the selected tier (no tier change): "dungeons/raids".
local function journalCounts()
	local counts = {}
	for _, isRaid in ipairs({ false, true }) do
		local n = 0
		for index = 1, 200 do
			local ok, id = call(EJ_GetInstanceByIndex, index, isRaid)
			if not ok or Util.Plain(id) == nil then
				break
			end
			n = n + 1
		end
		counts[#counts + 1] = n
	end
	local okT, tiers = call(EJ_GetNumTiers)
	return string.format("tiers %s, dungeons %d, raids %d", okT and v(tiers) or "error", counts[1], counts[2])
end

local function gameRule(name)
	local rules, enum = rawget(_G, "C_GameRules"), rawget(_G, "Enum")
	local id = enum and type(enum.GameRule) == "table" and enum.GameRule[name]
	if not (rules and type(rules.IsGameRuleActive) == "function" and id) then
		return "unknown"
	end
	local ok, active = pcall(rules.IsGameRuleActive, id)
	return ok and v(active) or "error"
end

local function journal(out)
	local j = { before = journalCounts(), encounterJournalDisabled = gameRule("EncounterJournalDisabled") }
	local addons = rawget(_G, "C_AddOns")
	local name = "Blizzard_EncounterJournal"
	if addons then
		local okL, loaded = call(addons.IsAddOnLoaded, name)
		local okA, loadable, reason = call(addons.IsAddOnLoadable, name)
		j.addon = string.format("loaded %s, loadable %s %s", okL and v(loaded) or "?", okA and v(loadable) or "?",
			okA and v(reason) or "")
		if okL and not loaded and okA and loadable then
			local okLoad, result, why = call(addons.LoadAddOn, name)
			j.load = string.format("LoadAddOn %s %s %s", v(okLoad), v(result), v(why))
		end
	end
	j.afterLoad = journalCounts()
	local ej = rawget(_G, "C_EncounterJournal")
	if ej and type(ej.OnOpen) == "function" then
		local ok, err = pcall(ej.OnOpen)
		j.onOpen = ok and "called" or ("error " .. v(err))
		j.afterOpen = journalCounts()
		if type(ej.OnClose) == "function" then
			pcall(ej.OnClose)
		end
	end
	out.journal = j
	-- Data may come from the server: look again a few seconds later (saved with the rest on /reload).
	if C_Timer and C_Timer.After then
		C_Timer.After(3, function()
			j.after3s = journalCounts()
		end)
	end
end

local function finder(out)
	ns.GameFiles.Reset()
	local f = ns.GameFiles.Finder()
	local rows = {}
	for i, e in ipairs(f.list) do
		if i > 300 then
			break
		end
		-- "source id|name|type/subtype|min-max|instance map ID|background"
		rows[#rows + 1] = table.concat({ e.source .. " " .. v(e.id), e.name, v(e.typeID) .. "/" .. v(e.subtypeID or e.categoryID),
			v(e.minLevel) .. "-" .. v(e.maxLevel), v(e.mapID), v(e.texture) }, "|")
	end
	local okO, order = call(GetLFDChoiceOrder)
	out.finder = { count = #f.list, choiceOrder = okO and type(order) == "table" and #order or v(order), rows = rows,
		raw = ns.GameFiles.rawLfd }
end

local function mapRow(id)
	local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, id))
	local art = ns.Instances.MapArt(id)
	local okG, group = call(C_Map and C_Map.GetMapGroupID, id)
	if type(info) ~= "table" then
		return "none"
	end
	return table.concat({ v(info.name), "type " .. v(info.mapType), "parent " .. v(info.parentMapID),
		art and (art.width .. "x" .. art.height .. " " .. #art.textures .. " tiles") or "no art", "group " .. (okG and v(group) or "") }, "|")
end

local function maps(out)
	local ids, names = {}, {}
	for _, plan in ipairs(ns.Bundled.All()) do
		names[ns.Match.StripArticle(plan.instance.name)] = plan.instance.name
		if plan.instance.uiMapID then
			ids[plan.instance.uiMapID] = true
		end
		for _, f in ipairs(plan.floors) do
			if f.uiMapID then
				ids[f.uiMapID] = true
			end
			if f.name ~= "" then
				names[ns.Match.StripArticle(f.name)] = f.name
			end
		end
	end
	-- Maps carrying a plan's instance or floor name, anywhere in 1..4000.
	local byName = {}
	if C_Map and C_Map.GetMapInfo then
		for id = 1, 4000 do
			local ok, info = pcall(C_Map.GetMapInfo, id)
			local n = ok and type(info) == "table" and Util.Plain(info.name)
			local k = type(n) == "string" and ns.Match.StripArticle(n)
			if k and names[k] then
				byName[names[k]] = (byName[names[k]] and (byName[names[k]] .. ",") or "") .. id
				ids[id] = true
			end
		end
	end
	local rows = {}
	for _, id in ipairs(ns.Util.SortedKeys(ids)) do
		rows[tostring(id)] = mapRow(id)
	end
	out.maps = { byId = rows, byName = byName }
end

-- Where each recommended plan floor's map comes from (Data/MinimapArt.lua): "map", "tiles", "minimap",
-- "provider:<id>" or "grid", per plan, in floor order.
local function mapSources(out)
	local sources = {}
	for _, plan in ipairs(ns.Bundled.All()) do
		sources[plan.id] = table.concat(ns.MinimapArt.Sources(plan), ",")
	end
	out.mapSources = sources
end

local function files(out)
	local tiles, screens = {}, {}
	local function fileID(path)
		if type(path) == "number" then
			return "id"
		end
		local ok, id = call(GetFileIDFromPath, path)
		return ok and v(id) or "?"
	end
	for k, spec in pairs(ns.GameFiles.INSTANCES) do
		for i, base in ipairs(spec.tiles or {}) do
			tiles[k .. " " .. i] = base .. " = " .. fileID("Interface\\WorldMap\\" .. base .. "1")
		end
	end
	for _, plan in ipairs(ns.Bundled.All()) do
		local name = plan.instance.name
		if not screens[name] then
			local found = {}
			for _, file in ipairs((ns.GameFiles.LoadingScreenCandidates(name))) do
				local id = fileID(file)
				found[#found + 1] = tostring(file):match("[^\\]+$") .. "=" .. id
			end
			screens[name] = table.concat(found, " ")
		end
	end
	-- More names tried for pictures and maps the client may have under another spelling (recorded, not used).
	local probes = {}
	for _, path in ipairs(ns.GameFiles.PROBES) do
		probes[path] = fileID(path)
	end
	out.tiles, out.loadingScreens, out.probes = tiles, screens, probes
end

local function portraits(out)
	local p = {
		modelPortrait = v(type(SetPortraitTextureFromCreatureDisplayID) == "function"),
		creatureInfo = v(type(EJ_GetCreatureInfo) == "function"),
	}
	-- Plans that name a creature (npcID on a marker): a display ID needs a model lookup, which is not done.
	local npcs = 0
	for _, plan in ipairs(ns.Bundled.All()) do
		for _, m in ipairs(plan.markers) do
			if m.npcID then
				npcs = npcs + 1
			end
		end
	end
	p.markersWithNpcID = npcs
	out.portraits = p
end

-- The UI face and the font test (UI/Fonts.lua): each Polish face's SetFont, GetFont and Polish-letter widths, directly
-- and through a Font object; this session's first probe; the game face and other addons' fonts as controls; one of our
-- textures. fontTest is written now and again 2 seconds later with the second look (fontTest.faces[*].later).
local function fonts(out)
	local S = ns.Style
	local faces = {}
	for _, file in ipairs(S.POLISH_FACES) do
		faces[#faces + 1] = S.FontShortName(file) .. "=" .. v(S.CanLoadFont(file))
	end
	out.fonts = { file = v(S.fontFile), polish = v(S.polishFace), faces = table.concat(faces, " "),
		locale = v(ns.activeLocale), setting = v(ns.db and ns.db.settings.locale) }
	local test = S.RunFontTest({
		delay = 2,
		done = function(t)
			out.fontTest = S.FontTestRecord(t)
		end,
	})
	out.fontTest = out.fontTest or S.FontTestRecord(test)
end

-- Could an in-game spawn recorder work (data-src/spawns/README.md)? Run inside a dungeon with a hostile mob targeted:
-- the player's map position (C_Map) and world position (UnitPosition), and whether the target's GUID and name can be
-- read. Each value is "nil", "secret", "missing", "error" or the value itself (numbers rounded). Of a GUID only its
-- type and NPC ID are kept.
local function state(ok, x)
	if not ok then
		return x == "missing" and "missing" or "error"
	elseif x == nil then
		return "nil"
	elseif Util.IsSecret(x) then
		return "secret"
	elseif type(x) == "number" then
		return string.format("%.4f", x)
	end
	return tostring(x)
end

local function position(out)
	local mapAPI = rawget(_G, "C_Map") or {}
	local okI, inside, kind = call(IsInInstance)
	local okN, name, _, _, _, _, _, _, instanceID = call(GetInstanceInfo)
	local p = {
		instance = state(okI, inside) .. " " .. state(okI, kind) .. " | " .. state(okN, name) .. " " .. state(okN, instanceID),
		subzone = state(call(GetSubZoneText)),
	}
	local okB, best = call(mapAPI.GetBestMapForUnit, "player")
	p.bestMap = state(okB, best)
	-- The instance's map ID (GetInstanceInfo's 8th value) on its own, the indoor flag, and the best map's floor group
	-- with each member's relativeHeightIndex: what an automatic floor switch would need (Data/Floors.lua PlayerFloor,
	-- unverified until a scan inside a dungeon shows a map).
	p.instanceMapID = state(okN, instanceID)
	p.indoors = state(call(rawget(_G, "IsIndoors")))
	if okB and type(Util.Plain(best)) == "number" then
		local okG, group = call(mapAPI.GetMapGroupID, best)
		p.mapGroup = state(okG, group)
		if okG and type(Util.Plain(group)) == "number" then
			local okM, members = call(mapAPI.GetMapGroupMembersInfo, group)
			local rows = {}
			for _, m in ipairs(okM and type(Util.Plain(members)) == "table" and members or {}) do
				if type(m) == "table" then
					rows[#rows + 1] = state(true, Util.Plain(m.mapID)) .. " " .. state(true, Util.Plain(m.name)) .. " h"
						.. state(true, Util.Plain(m.relativeHeightIndex))
				end
			end
			p.mapGroupMembers = okM and rows or state(okM, members)
		end
		local okF, floor = pcall(ns.Floors.Match, {}, ns.Floors.PlayerMap())
		p.playerFloorAPI = okF and "ok" or ("error " .. tostring(floor))
	end
	if okB and type(Util.Plain(best)) == "number" then
		local okP, pos = call(mapAPI.GetPlayerMapPosition, best, "player")
		local okXY, x, y = false, nil, nil
		if okP and type(Util.Plain(pos)) == "table" and type(pos.GetXY) == "function" then
			okXY, x, y = pcall(pos.GetXY, pos)
		end
		p.mapPosition = (okP and pos == nil) and "nil" or (state(okXY, x) .. ", " .. state(okXY, y))
	end
	local okU, wy, wx, _, continent = call(UnitPosition, "player")
	p.unitPosition = state(okU, wx) .. ", " .. state(okU, wy) .. " | " .. state(okU, continent)
	local okE, exists = call(UnitExists, "target")
	if okE and Util.Plain(exists) then
		local okG, guid = call(UnitGUID, "target")
		local plain = okG and Util.Plain(guid)
		p.targetGUID = type(plain) == "string"
			and ((plain:match("^(%a+)%-") or "?") .. " npc " .. (plain:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "?"))
			or state(okG, guid)
		local okNm, tname = call(UnitName, "target")
		p.targetName = (okNm and Util.IsSecret(tname)) and "secret" or (okNm and tname ~= nil) and "plain" or state(okNm, tname)
		p.targetLevel = state(call(UnitLevel, "target"))
		p.targetClass = state(call(UnitClassification, "target"))
		p.targetHostile = state(call(UnitCanAttack, "player", "target"))
	end
	p.facing = state(call(GetPlayerFacing))
	p.minimapZone = state(call(GetMinimapZoneText))
	out.position = p
end

-- What else the client gives inside an instance (docs/COMPATIBILITY.md section 10): the Minimap frame (protected? who
-- owns it? a ping's offset from the player), and the nameplates (how many, whether each unit's hostility, level,
-- classification, combat flag and name are readable, and whether the plate has a screen position). Read only;
-- nothing is moved, pinged or changed.
local function minimap(out)
	local mm = rawget(_G, "Minimap")
	local m = {}
	if type(mm) == "table" then
		local function method(name, ...)
			return state(call(mm[name], mm, ...))
		end
		m.protected = method("IsProtected")
		local okP, parent = call(mm.GetParent, mm)
		m.parent = okP and type(parent) == "table" and state(call(parent.GetName, parent)) or state(okP, parent)
		m.zoom = method("GetZoom")
		m.zoomLevels = method("GetZoomLevels")
		local okX, px, py = call(mm.GetPingPosition, mm)
		m.ping = state(okX, px) .. ", " .. state(okX, py)
		m.size = method("GetWidth") .. " x " .. method("GetHeight")
	else
		m.frame = "missing"
	end
	out.minimap = m
end

local function namePlates(out)
	local np = rawget(_G, "C_NamePlate") or {}
	local okN, plates = call(np.GetNamePlates)
	local n = { count = okN and type(plates) == "table" and #plates or state(okN, plates), rows = {} }
	if okN and type(plates) == "table" then
		for i = 1, math.min(#plates, 8) do
			local plate = plates[i]
			local unit = type(plate) == "table" and (Util.Plain(plate.namePlateUnitToken)
				or (type(plate.UnitFrame) == "table" and Util.Plain(plate.UnitFrame.unit))) or nil
			if type(unit) == "string" then
				local okNm, name = call(UnitName, unit)
				local okC, cx = call(plate.GetCenter, plate)
				n.rows[#n.rows + 1] = table.concat({ unit:gsub("%d+", "#"),
					"hostile " .. state(call(UnitCanAttack, "player", unit)),
					"level " .. state(call(UnitLevel, unit)),
					"class " .. state(call(UnitClassification, unit)),
					"combat " .. state(call(UnitAffectingCombat, unit)),
					"name " .. ((okNm and Util.IsSecret(name)) and "secret" or (okNm and name ~= nil) and "plain" or state(okNm, name)),
					"screen " .. ((okC and type(Util.Plain(cx)) == "number") and "yes" or state(okC, cx)) }, "|")
			else
				n.rows[#n.rows + 1] = "no unit token"
			end
		end
	end
	out.namePlates = n
end

-- Everything above, plus the journal resolver's own view (Journal.Diagnostics). Each part is guarded on its own.
function Diagnostics.Collect()
	local out = ns.Journal.Diagnostics()
	out.errors = out.errors or {}
	for _, part in ipairs({ { "journal", journal }, { "finder", finder }, { "maps", maps }, { "mapSources", mapSources }, { "files", files },
		{ "portraits", portraits }, { "fonts", fonts }, { "position", position }, { "minimap", minimap },
		{ "namePlates", namePlates } }) do
		local ok, err = pcall(part[2], out)
		if not ok then
			out.errors[#out.errors + 1] = part[1] .. ": " .. tostring(err)
		end
	end
	return out
end
