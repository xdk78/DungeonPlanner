-- Dungeon Planner's mock client. The generic WoW API mock (frames, regions, anchors, fonts, events, timers, the
-- client's common functions, and optional layout resolution) is wow-ui-harness's `wowui.mock`, vendored in
-- tests/vendor/wow-ui-harness/ (tools/sync_harness.sh, VERSION there). This file adds what is specific to this addon:
-- the client it targets (WoW: Forever) and made-up game data in the client's shapes - an Adventure Guide, maps, the
-- dungeon finder, the Group Finder - plus fake installed provider addons. It does not draw anything; the goal is to
-- catch errors in our own code paths before an in-game test, not to emulate the game.

package.path = "./tests/vendor/wow-ui-harness/lua/?.lua;" .. package.path
local M = require("wowui.mock")

M.buildInfo = { "1.60.1", "70938", "Nov 13 2026", 16001 }
M.realm = "Forever"
M.loadableAddons = { Blizzard_EncounterJournal = true }
-- Atlases the mock client "has" (C_Texture.GetAtlasInfo); tests add names to exercise both art paths.
M.atlases = {
	Dungeon = true,
	["common-icon-checkmark"] = true,
	["common-dropdown-bg"] = true,
	Options_List_Hover = true,
	Options_List_Active = true,
}

-- The game's window parts as current clients have them (only what our code touches): frame templates, nine-slice
-- layouts, the PanelTemplates and ButtonFrameTemplate helpers, the scroll bar's events, model portraits.
M.layouts = { PortraitFrameTemplate = {}, ButtonFrameTemplateNoPortrait = {}, InsetFrameTemplate = {}, Dialog = {} }

local function tex(parent)
	return M.CreateFrame("Texture", nil, parent)
end

local function tabParts(f)
	f.Text = M.CreateFrame("FontString", nil, f)
	f.Left, f.Middle, f.Right = tex(f), tex(f), tex(f)
	f.LeftActive, f.MiddleActive, f.RightActive = tex(f), tex(f), tex(f)
	f._h = 32
	-- PanelTabButtonMixin:OnShow: the tab sizes itself again from its parent's tabPadding / minTabWidth / maxTabWidth.
	f:SetScript("OnShow", function(self)
		local p = self:GetParent()
		_G.PanelTemplates_TabResize(self, p and p.tabPadding, nil, p and p.minTabWidth, p and p.maxTabWidth)
	end)
end

function M.InstallNative()
	M.templates.ButtonFrameTemplate = function(f)
		f.NineSlice = M.CreateFrame("Frame", nil, f)
		f.NineSlice:SetFrameLevel(500) -- NineSlicePanelTemplate's frameLevel: the metal border over the window's children
		f.Bg, f.TitleBg = tex(f), tex(f)
		f.CloseButton = M.CreateFrame("Button", nil, f)
		f.CloseButton:SetFrameLevel(510) -- UIPanelCloseButtonNoScripts
		f.CloseButton:SetScript("OnClick", function()
			error("the template's close handler must be replaced")
		end)
		f.Inset = M.CreateFrame("Frame", nil, f)
		f.PortraitContainer = M.CreateFrame("Frame", nil, f)
		f.PortraitContainer.portrait = tex(f.PortraitContainer)
		f.TitleContainer = M.CreateFrame("Frame", nil, f)
		f.TitleContainer.TitleText = M.CreateFrame("FontString", nil, f.TitleContainer)
		f.SetTitle = function(self, text)
			self.TitleContainer.TitleText:SetText(text)
		end
		f.SetPortraitToAsset = function(self, file)
			self.PortraitContainer.portrait:SetTexture(file)
		end
		-- Where the game's template puts its title, portrait and close button (approximate; for the UI dump's pictures).
		f.TitleContainer:SetPoint("TOPLEFT", 58, -1)
		f.TitleContainer:SetPoint("TOPRIGHT", -24, -1)
		f.TitleContainer:SetHeight(20)
		f.TitleContainer.TitleText:SetPoint("TOP", 0, -5)
		f.TitleContainer.TitleText:SetFontObject(_G.GameFontNormal)
		f.PortraitContainer:SetSize(62, 62)
		f.PortraitContainer:SetPoint("TOPLEFT", -5, 7)
		f.PortraitContainer.portrait:SetAllPoints()
		f.PortraitContainer.portrait._layer = "OVERLAY"
		f.PortraitContainer.portrait:AddMaskTexture({ _texture = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
			_points = { { "TOPLEFT", f.PortraitContainer, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", f.PortraitContainer, "BOTTOMRIGHT", 0, 0 } } })
		f.CloseButton:SetSize(24, 24)
		f.CloseButton:SetPoint("TOPRIGHT", 1, 0)
		f.CloseButton:GetNormalTexture():SetAtlas("RedButton-Exit")
	end
	M.templates.UIPanelButtonTemplate = function(f)
		f.Left, f.Middle, f.Right = tex(f), tex(f), tex(f)
	end
	M.templates.PanelTabButtonTemplate = tabParts
	M.templates.PanelTopTabButtonTemplate = tabParts
	M.templates.MinimalScrollBar = function(f)
		f._pct, f._callbacks = 0, {}
		f.Track = M.CreateFrame("Frame", nil, f)
		f.RegisterCallback = function(self, event, fn, owner)
			self._callbacks[#self._callbacks + 1] = { event, fn, owner }
		end
		-- As the game's bar does, a change reports OnScroll (our code must not echo it back).
		f.SetScrollPercentage = function(self, pct)
			self._pct = pct
			self:Update()
			self._sets = (self._sets or 0) + 1
			for _, cb in ipairs(self._callbacks) do
				if cb[1] == "OnScroll" then
					cb[2](cb[3], pct)
				end
			end
		end
		f.GetScrollPercentage = function(self)
			return self._pct
		end
		-- The game's ScrollBarMixin: its setters call self:Update(), which alone sizes and shows the thumb. An addon that
		-- replaces Update on the bar loses the thumb (and recurses when its own Update calls a setter).
		f._updates = 0
		f.Update = function(self)
			self._updates = self._updates + 1
			self._thumbShown = (self._visible or 0) > 0 and (self._visible or 0) < 1
		end
		f.SetVisibleExtentPercentage = function(self, v)
			self._visible = v
			self:Update()
		end
		f.SetPanExtentPercentage = function(self, v)
			self._pan = v
		end
	end
	_G.BaseScrollBoxEvents = { OnScroll = "OnScroll" }
	_G.ScrollUtil = {
		InitScrollFrameWithScrollBar = function(scrollFrame, bar)
			scrollFrame._scrollBar, bar._scrollFrame = bar, scrollFrame
		end,
	}
	_G.NineSliceUtil = {
		GetLayout = function(name)
			return M.layouts[name]
		end,
		ApplyLayoutByName = function(frame, name)
			if not M.layouts[name] then
				error("no layout " .. tostring(name))
			end
			frame._layout = name
			frame._nineSlice = name -- for wow-ui-harness's dump and renderer
		end,
	}
	_G.PanelTemplates_SelectTab = function(tab)
		tab._selected = true
		tab:Disable()
		tab:SetDisabledFontObject(_G.GameFontHighlightSmall) -- as the game's helper does
	end
	_G.PanelTemplates_DeselectTab = function(tab)
		tab._selected = false
		tab:Enable()
	end
	_G.PanelTemplates_TabResize = function(tab, padding, absoluteSize, minWidth, maxWidth)
		local width = absoluteSize or (tab.Text:GetStringWidth() + 2 * (padding or 0))
		if not absoluteSize then
			width = math.max(minWidth or 0, math.min(maxWidth or math.huge, width))
		end
		tab:SetWidth(width)
	end
	_G.ButtonFrameTemplate_HideButtonBar = function(f)
		f._buttonBarHidden = true
	end
	_G.ButtonFrameTemplate_HidePortrait = function(f)
		f._portraitHidden = true
		f._noPortrait = true
	end
	-- A model portrait: remembers the creature and how often it was drawn.
	_G.SetPortraitTextureFromCreatureDisplayID = function(t, displayID)
		t._portrait = displayID
		t._portraitDraws = (t._portraitDraws or 0) + 1
	end
end


local coreInstall = M.Install

-- The client's own art: every texture file the UI names (UI/Art.lua's SPECS, Style's stone) is in a real client, so the
-- mock client has it too (M.KnowArt, after the addon loaded), unless a test lists it in M.missingFiles. Game data files
-- (loading screens, old map tiles) are known only when a test puts them in M.files, as before.
M.artFiles, M.missingFiles = {}, {}

-- Which mouse buttons a button takes (RegisterForClicks), for tests.
M.DEFAULTS.RegisterForClicks = function(self, ...)
	self._clicks = { ... }
end
function M.KnowArt(ns)
	for _, spec in pairs(ns.Art.SPECS) do
		if type(spec.file) == "string" then
			M.artFiles[spec.file:lower()] = true
		end
	end
	M.artFiles[ns.Style.STONE:lower()] = true
end

function M.Install()
	coreInstall()
	local fileID = _G.GetFileIDFromPath
	_G.GetFileIDFromPath = function(path)
		local id = fileID(path)
		if id == nil and type(path) == "string" and M.artFiles[path:lower()] and not M.missingFiles[path:lower()] then
			id = M.SyntheticFileID(path)
		end
		return id
	end
	M.InstallNative()
	_G.WOW_PROJECT_ID = 18
	-- Group membership by name: the units the tests place while M.inGroup is set.
	_G.UnitInParty = function(name)
		if not M.inGroup then
			return false
		end
		for _, u in pairs(M.units or {}) do
			if u.name == name then
				return true
			end
		end
		return false
	end
	_G.WOW_PROJECT_CAMELOT = 18
	_G.LE_PARTY_CATEGORY_INSTANCE = 2
	_G.GetInstanceInfo = function()
		return "Test Dungeon", "party", 1, "Normal", 5, 0, false, 9001
	end
	-- WoW: Forever's game rules: the Adventure Guide is disabled there (tests set M.gameRules).
	_G.C_GameRules = {
		IsGameRuleActive = function(rule)
			return M.gameRules and M.gameRules[rule] or false
		end,
	}
	_G.Enum.GameRule = { EncounterJournalDisabled = 77 }
	_G.C_Map = {
		-- M.mapInfo[id] = { name?, mapType?, parentMapID? } sets a map's answer (tests: a zone in another language).
		GetMapInfo = function(id)
			local over = M.mapInfo and M.mapInfo[id] or {}
			return { mapID = id, name = over.name or (id == 300 and "The Hall of Tests" or ("Map " .. id)),
				mapType = over.mapType, parentMapID = over.parentMapID }
		end,
		GetBestMapForUnit = function()
			return 100
		end,
		GetMapArtLayers = function(id)
			if id == 100 or id == 300 then
				return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
			end
			return {}
		end,
		GetMapArtLayerTextures = function(id)
			if id == 100 or id == 300 then
				local t = {}
				for i = 1, 12 do
					t[i] = 5000 + i
				end
				return t
			end
			return {}
		end,
		GetMapGroupID = function()
			return nil
		end,
	}
	-- Prep and Getting there (Data/PrepInfo.lua, Data/Travel.lua, Data/Navigation.lua). A made-up world: map m spans
	-- 10000 x 1000 yards (east-west, north-south) from world (500 - 10 m, 6000) to the south-east, map x going east
	-- (world y falls), map y south (world x falls), on continent m % 2 unless a world spot placed it on another. Without
	-- an override the "best" map of a world spot is the one whose band holds it. M.mapBoxes[m] = { continent, x0, y0 }
	-- moves a map's top-left corner (a zone map round a real entrance). M.playerPos = { map, x, y } is where the player
	-- stands outdoors (nil: inside an instance, no position).
	M.questsDone, M.questLog, M.itemCounts, M.waypoints, M.openedMaps = {}, {}, {}, {}, {}
	M.playerPos, M.mapBoxes, M.mapInfo = nil, {}, {}
	local mapContinent = {}
	_G.CreateVector2D = function(x, y)
		return { x = x, y = y, GetXY = function(v)
			return v.x, v.y
		end }
	end
	local function box(m)
		local b = M.mapBoxes[m]
		if b then
			return b[1], b[2], b[3]
		end
		return mapContinent[m] or m % 2, -m * 10 + 500, 6000
	end
	_G.C_Map.GetWorldPosFromMapPos = function(m, pos)
		local c, x0, y0 = box(m)
		return c, _G.CreateVector2D(x0 - pos.y * 1000, y0 - pos.x * 10000)
	end
	_G.C_Map.GetMapPosFromWorldPos = function(c, pos, override)
		local m = override or math.floor(-pos.x / 10)
		if not override and not mapContinent[m] then
			mapContinent[m] = c
		end
		local mc, x0, y0 = box(m)
		if c ~= mc then
			return nil
		end
		return m, _G.CreateVector2D((y0 - pos.y) / 10000, (x0 - pos.x) / 1000)
	end
	_G.C_Map.GetPlayerMapPosition = function(m)
		local p = M.playerPos
		if p and p.map == m then
			return _G.CreateVector2D(p.x, p.y)
		end
		return nil
	end
	_G.C_Map.GetBestMapForUnit = function()
		return M.playerPos and M.playerPos.map or 100
	end
	_G.C_Map.CanSetUserWaypointOnMap = function(m)
		return m ~= 300
	end
	_G.C_Map.SetUserWaypoint = function(point)
		M.waypoints[#M.waypoints + 1] = point
	end
	_G.C_Map.OpenWorldMap = function(m)
		M.openedMaps[#M.openedMaps + 1] = m
	end
	_G.C_Map.GetAreaInfo = function(area)
		return "Area " .. area
	end
	_G.UiMapPoint = { CreateFromCoordinates = function(m, x, y)
		return { uiMapID = m, position = _G.CreateVector2D(x, y) }
	end }
	_G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on)
		M.superTracked = on
	end }
	_G.C_QuestLog = {
		IsQuestFlaggedCompleted = function(id)
			return M.questsDone[id] == true
		end,
		IsOnQuest = function(id)
			return M.questLog[id] == true
		end,
		GetTitleForQuestID = function()
			return nil
		end,
	}
	if _G.C_Item then
		_G.C_Item.GetItemCount = function(id)
			return M.itemCounts[id] or 0
		end
	end
	-- A fake Adventure Guide (tests replace M.journal to try other shapes). Tier 1 has the classic test dungeon (63) and
	-- a raid (70); tier 2 is a new dungeon whose journal name differs from the plans' ("The Hall of Tests"), with a map
	-- (300, with art), bosses, creature portraits and loot.
	M.journal = {
		tiers = {
			{
				name = "Classic",
				dungeons = {
					{ id = 63, name = "Test Dungeon", areaMap = 100, mapID = 389, art = { 0, 0, 0, 0 } },
				},
				raids = {
					{ id = 70, name = "Test Raid", areaMap = 0, mapID = 409, art = { 2001, 2002, 2003, 2004 } },
				},
			},
			{
				name = "Forever",
				dungeons = {
					{ id = 900, name = "The Hall of Tests", areaMap = 300, mapID = 3065, art = { 3101, 3102, 3103, 3104 } },
				},
				raids = {},
			},
		},
		-- [instanceID] = { { name, ejID, dungeonID, creatures = { { name, display, icon } } } }
		encounters = {
			[900] = {
				{ "Faldrim Anvilmar", 901, 3001, { { "Faldrim Anvilmar", 50001, 0 } } },
				{ "Magmatus", 902, 3002, { { "Magmatus", 50002, 0 } } },
				{ "Plunder", 903, 3003, { { "Plunder", 50003, 0 } } },
			},
		},
		-- [journalEncounterID] = { { itemID, name, quality, equipLoc, classes = { [classID] = true } (nil: everyone) } }
		loot = {
			[901] = {
				{ 7001, "Ephemeral Choker", 3, "INVTYPE_NECK" },
				{ 7002, "Aetherwisp Bracers", 3, "INVTYPE_WRIST", { [8] = true } },
			},
			[902] = { { 7003, "Spiritwraith Drape", 3, "INVTYPE_CLOAK" } },
		},
		pins = { [300] = { { 0.5, 0.7, 901, "Faldrim Anvilmar" }, { 0.7, 0.45, 902, "Magmatus" } } },
	}
	local ej = { tier = 1, instance = nil, encounter = nil, classID = 0, specID = 0 }
	M.ej = ej
	local function tierInfo(t)
		return M.journal.tiers[t or ej.tier]
	end
	local function findInstance(id)
		for _, tier in ipairs(M.journal.tiers) do
			for _, list in ipairs({ tier.dungeons, tier.raids }) do
				for _, inst in ipairs(list) do
					if inst.id == id then
						return inst
					end
				end
			end
		end
		return nil
	end
	local function encountersOf(id)
		local list = M.journal.encounters[id]
		if list then
			return list
		end
		if id == 63 then -- the classic test dungeon: two generic bosses
			return {
				{ "Boss 1", 91, 201, { { "Creature 91", 3091, 4091 } } },
				{ "Boss 2", 92, 202, { { "Creature 92", 3092, 4092 } } },
			}
		end
		return {}
	end
	_G.EJ_GetNumTiers = function()
		return #M.journal.tiers
	end
	_G.EJ_SelectTier = function(t)
		ej.tier = t
	end
	_G.EJ_GetCurrentTier = function()
		return ej.tier
	end
	_G.EJ_GetTierInfo = function(t)
		local tier = tierInfo(t)
		return tier and tier.name
	end
	-- instanceID, name, description, bgImage, buttonImage1, loreImage, buttonImage2, dungeonAreaMapID, link,
	-- shouldDisplayDifficulty, mapID
	_G.EJ_GetInstanceByIndex = function(index, isRaid)
		local tier = tierInfo()
		local inst = tier and (isRaid and tier.raids or tier.dungeons)[index]
		if not inst then
			return nil
		end
		return inst.id, inst.name, "", inst.art[4], inst.art[1], inst.art[3], inst.art[2], inst.areaMap, "", false,
			inst.mapID
	end
	_G.EJ_SelectInstance = function(id)
		ej.instance, ej.encounter = id, nil
	end
	_G.EJ_SelectEncounter = function(id)
		ej.encounter = id
	end
	-- name, description, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
	_G.EJ_GetEncounterInfoByIndex = function(index, instanceID)
		local e = encountersOf(instanceID or ej.instance)[index]
		if not e then
			return nil
		end
		return e[1], "", e[2], 0, "", instanceID or ej.instance, e[3], 9001
	end
	_G.EJ_GetEncounterInfo = function(id)
		return "Journal boss " .. id
	end
	-- name, description, bgImage, buttonImage1, loreImage, buttonImage2, dungeonAreaMapID, link, showDifficulty, mapID
	_G.EJ_GetInstanceInfo = function(id)
		local inst = findInstance(id)
		if inst and id ~= 63 then
			return inst.name, "", inst.art[4], inst.art[1], inst.art[3], inst.art[2], inst.areaMap, "", false, inst.mapID
		end
		return "Journal instance " .. id, "", 1001, 1002, 1003, 1004, 100, "", false, 389
	end
	-- id, name, description, displayInfo, iconImage, uiModelSceneID
	_G.EJ_GetCreatureInfo = function(index, encounterID)
		for _, list in pairs(M.journal.encounters) do
			for _, e in ipairs(list) do
				if e[2] == encounterID then
					local c = e[4][index]
					if c then
						return 7000 + encounterID, c[1], "", c[2], c[3], 0
					end
					return nil
				end
			end
		end
		if index == 1 and encounterID then
			return 7000 + encounterID, "Creature " .. encounterID, "", 3000 + encounterID, 4000 + encounterID, 0
		end
		return nil
	end
	-- x, y, instanceID, name, description, encounterID
	_G.EJ_GetMapEncounter = function(mapID, index)
		local pins = M.journal.pins[mapID]
		if pins then
			local p = pins[index]
			if p then
				return p[1], p[2], 900, p[4], "", p[3]
			end
			return nil
		end
		if mapID == 100 and index <= 2 then
			return 0.3 * index, 0.4, 63, "Boss " .. index, "", 90 + index
		end
		return nil
	end
	-- Loot of the selected encounter (or every encounter of the selected instance), for the loot filter's class.
	local function lootList()
		local out = {}
		local ids = {}
		if ej.encounter then
			ids[1] = ej.encounter
		else
			for _, e in ipairs(encountersOf(ej.instance)) do
				ids[#ids + 1] = e[2]
			end
		end
		for _, encID in ipairs(ids) do
			for _, item in ipairs(M.journal.loot[encID] or {}) do
				if ej.classID == 0 or not item[5] or item[5][ej.classID] then
					out[#out + 1] = { item = item, encounterID = encID }
				end
			end
		end
		return out
	end
	_G.EJ_SetLootFilter = function(classID, specID)
		ej.classID, ej.specID = classID or 0, specID or 0
	end
	_G.EJ_GetLootFilter = function()
		return ej.classID, ej.specID
	end
	_G.EJ_GetNumLoot = function()
		return #lootList()
	end
	_G.C_EncounterJournal = {
		GetLootInfoByIndex = function(index)
			local row = lootList()[index]
			if not row then
				return nil
			end
			local item = row.item
			return {
				itemID = item[1],
				encounterID = row.encounterID,
				name = (not M.lootLoading) and item[2] or nil,
				itemQuality = item[3],
				icon = 135000 + index,
				slot = "Slot",
				armorType = "Cloth",
				link = "|cff0070dd|Hitem:" .. item[1] .. "::::::::|h[" .. item[2] .. "]|h|r",
			}
		end,
	}
	-- The client's answer: itemID, itemType, itemSubType, equipLoc, icon, classID, subclassID (the API's seven values),
	-- or nothing for an item the client has no data for. M.itemTypes[id] = { equipLoc, classID, subclassID } sets an
	-- item's type, false makes it unknown; others are cloth (class 4, subclass 1), the journal's equip location or a head.
	M.itemTypes = {}
	local function itemInfoInstant(itemID)
		local t = M.itemTypes[itemID]
		if t == false then
			return nil
		elseif t then
			return itemID, "Type", "Subtype", t[1], 135000, t[2], t[3]
		end
		for _, list in pairs(M.journal.loot) do
			for _, item in ipairs(list) do
				if item[1] == itemID then
					return itemID, "Armor", "Cloth", item[4], 135000, 4, 1
				end
			end
		end
		return itemID, "Armor", "Cloth", "INVTYPE_HEAD", 135000, 4, 1
	end
	_G.GetItemInfoInstant = itemInfoInstant
	_G.C_Item = _G.C_Item or {}
	_G.C_Item.GetItemInfoInstant = itemInfoInstant
	-- Dungeon finder: one entry (id 5) for the test dungeon's instance map 389, levels 13-18.
	_G.GetLFGDungeonInfo = function(id)
		if id == 5 then
			return "Test Dungeon", 1, 0, 10, 20, 15, 13, 18, 0, 0, "", 1, 5, "", false, 0, 1, false, "Test Dungeon", 0,
				false, 389
		end
		return nil
	end
	-- The Group Finder's browse list (C_LFGList): one Forever-style dungeon only listed there.
	_G.C_LFGList = {
		GetAvailableActivities = function()
			return { 1201 }
		end,
		GetActivityInfoTable = function(id)
			if id == 1201 then
				return { fullName = "Hall of Forever Tests", shortName = "HoFT", categoryID = 2, minLevelSuggestion = 13,
					maxLevelSuggestion = 20, mapID = 3065 }
			end
			return nil
		end,
	}
	_G.GetQuestDifficultyColor = function(level)
		return { r = level > 17 and 1 or 0.25, g = 0.75, b = 0.25 }
	end
	_G.EJ_GetInstanceForMap = function()
		return 63
	end
end

-- Fake installed addons for the data-provider adapters (Data/Providers/*.lua): the shapes their real data has, made
-- up content. M.InstallProviders() puts them in _G, M.RemoveProviders() takes them away again.
function M.InstallProviders()
	_G.ForeverDungeonJournal_NS = {
		DB = {
			["Hall of Thanes"] = { level = "13-20", bosses = {
				{ name = "Faldrim Anvilmar", npcID = 900001, loot = { { 900101, "Test Choker", "Neck", 3 }, { 900102, "Test Boots", "Feet, Cloth", 2 } } },
				{ name = "Magmatus", npcID = 900002, displayID = 777, loot = { { 900103, "Test Blade", "One-Hand, Sword", 3 } },
					summonItem = 900150, description = "Made-up description for the tests." },
				{ name = "Trash Drops", trash = true, loot = { { 900199, "Trash", "Misc", 1 } } },
			} },
		},
		BOSS_LEVELS = { ["Hall of Thanes"] = { ["Faldrim Anvilmar"] = "16", Magmatus = "17-18" } },
		DUNGEON_MAPS = {
			["Hall of Thanes"] = {
				floors = { { texture = "Interface\AddOns\ForeverDungeonJournal\Media\HallOfThanesMap", texBottom = 683 / 1024 } },
				bosses = { { name = "Faldrim Anvilmar", x = 0.509, y = 0.668 }, { name = "Magmatus", x = 0.748, y = 0.478 },
					{ name = "Plunder", x = 0.510, y = 0.515 }, { name = "Durgen Dirgehammer", x = 0.509, y = 0.170 } },
			},
		},
		STATIC_DISPLAY_IDS = { [900001] = 555 },
		BAKED_PORTRAITS = { [555] = true },
	}
	_G.OpenMap = {
		MapPlaces = { instances = { { nil, 0.2, 0.4, { { 3065, "The Hall of Thanes", false, 13, 20 } } },
			{ 0, 1, 2, { { 2999, "Ruins of Lordaeron", false, 15, 22 } } } } },
		MapDungeonDrawn = { [2999] = { { tiles = { "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t9", "t10", "t11", "t12" },
			credit = "An Artist" } } },
		MapDungeonBosses = { [2999] = { ["Witherfang"] = { 1, 0.3, 0.4 }, ["Bjork"] = { 2, 0.5, 0.5 } } },
	}
	-- Forever Dungeon Routes' namespace (made-up routes in its shapes): a picture floor and a classic floor.
	_G.ForeverDungeonRoutes = {
		Dungeons = {
			{ key = "hallofthanes", name = "The Hall of Thanes", floors = { 1030651 } },
			{ key = "deadmines", name = "Deadmines", floors = { 291, 292 } },
		},
		Floors = {
			[291] = { name = "Deadmines", tiles = { 449591, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } },
			[292] = { name = "Ironclad Cove", tiles = { 449603, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } },
			[1030651] = { name = "The Hall of Thanes", credit = "A Painter",
				image = { file = "maps\\hallofthanes", right = 1, bottom = 0.667 } },
		},
		DefaultRoutes = {
			hallofthanes = { id = "default", name = "Test route",
				paths = {
					{ kind = "main", floor = 1030651, pts = { 0.51, 0.95, 0.51, 0.66, 0.73, 0.47 } },
					{ kind = "side", floor = 1030651, title = "A side way", pts = { 0.5, 0.5, 0.4, 0.4 } },
					{ kind = "main", floor = 1030651, pts = { 0.1, 1.5, 0.2, 0.2 } }, -- off the map: skipped
					{ kind = "main", floor = 1030651, pts = { 0.1, 0.2, 0.3 } }, -- odd: skipped
				},
				stops = { { kind = "boss", floor = 1030651, x = 0.503, y = 0.666, name = "Faldrim Anvilmar" },
					{ kind = "rare", floor = 1030651, x = 0.3, y = 0.3, name = "A Rare" } } },
			deadmines = { { id = "default:a", name = "Alpha", paths = { { kind = "main", floor = 292, pts = { 0.1, 0.1, 0.2, 0.2 } } } },
				{ id = "default:full", name = "Full clear", paths = { { kind = "main", floor = 291, pts = { 0.2, 0.3, 0.4, 0.5 } } } } },
		},
		Rooms = { deadmines = { { name = "A" }, { name = "B" } } },
	}
	M.needRollCalls = {}
	_G.NeedRoll_ShowLoot = function(instance, boss)
		M.needRollCalls[#M.needRollCalls + 1] = { instance, boss }
		return true
	end
	local quests = { [101] = { 16919, "Ancient Grudge", 16, { { 5001 } } }, [102] = { 1581, "Elsewhere", 18 },
		[103] = { 16919, "Treaty", 15 } }
	_G.LibQuestieDB = {
		contractVersion = 4,
		RequireContract = function(n)
			return n <= 4, n <= 4 and "" or "too new"
		end,
		Enum = { zoneIDs = { THE_HALL_OF_THANES = 16919, THE_DEADMINES = 1581 } },
		Quest = {
			GetAllIds = function()
				return { 101, 102, 103 }
			end,
			zoneOrSort = function(id)
				return quests[id] and quests[id][1]
			end,
			name = function(id)
				return quests[id] and quests[id][2]
			end,
			questLevel = function(id)
				return quests[id] and quests[id][3]
			end,
			startedBy = function(id)
				return quests[id] and quests[id][4]
			end,
		},
		Npc = {
			name = function(id)
				return id == 5001 and "Thane Keeper" or nil
			end,
			spawns = function(id)
				return id == 5001 and { [1537] = { { 45.2, 61.75 } } } or nil
			end,
		},
	}
end

function M.RemoveProviders()
	_G.ForeverDungeonJournal_NS, _G.OpenMap, _G.NeedRoll_ShowLoot, _G.LibQuestieDB = nil, nil, nil, nil
	_G.ForeverDungeonRoutes = nil
end

return M
