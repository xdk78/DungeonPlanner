-- Every piece of Blizzard art the UI draws, by name, with a fallback for each. Nothing here is copied into the addon:
-- these are paths and atlas names the client resolves at runtime. Atlases are checked with C_Texture.GetAtlasInfo
-- (SetAtlas fails silently, so a pcall around it guards nothing - NeedRoll and OpenMap check the same way); files are
-- checked with GetFileIDFromPath (Art.SetFile): SetTexture returns true on this client even for a file it does not
-- have, so its return value cannot pick a fallback.
--
-- Where a name comes from (read in the installed addons, docs/UI.md): Dungeon Journal (FDJ), NeedRoll (NR), OpenMap
-- (OM), others by name. "classic" = a texture that has shipped since the original game and is still used by
-- Blizzard's own UI. Frame templates and nine-slice layouts are at the end of this file (Native pieces).

local _, ns = ...
local Art = ns:NewModule("Art")

local ICONS = "Interface\\Icons\\"
local LFG_ROLES = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local LFG_ROLE_GLYPHS = "Interface\\LFGFrame\\LFGRole"

-- key = { atlas = optional atlas, file = path or file ID, coords = { l, r, t, b }, round = mask into a circle }
Art.SPECS = {
	-- Chrome
	search = { atlas = "common-search-magnifyingglass", file = "Interface\\Common\\UI-Searchbox-Icon" }, -- NR, OM
	gear = { atlas = "OptionsIcon-Brown", file = "Interface\\Buttons\\UI-OptionsButton" }, -- FDJ, NR
	caret = { file = "Interface\\Buttons\\Arrow-Down-Up" }, -- OM
	check = { atlas = "common-icon-checkmark", file = "Interface\\RaidFrame\\ReadyCheck-Ready" }, -- NR, FDJ
	sizeGrip = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" }, -- FDJ, NR
	sizeGripDown = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down" },
	sizeGripHighlight = { file = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" },
	rowHighlight = { file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" }, -- NR (hover, additive)
	checkboxUp = { file = "Interface\\Buttons\\UI-CheckBox-Up" }, -- classic
	checkboxDown = { file = "Interface\\Buttons\\UI-CheckBox-Down" },
	checkboxHighlight = { file = "Interface\\Buttons\\UI-CheckBox-Highlight" },
	checkboxCheck = { file = "Interface\\Buttons\\UI-CheckBox-Check" },
	plus = { file = "Interface\\Buttons\\UI-PlusButton-Up" }, -- NR
	minus = { file = "Interface\\Buttons\\UI-MinusButton-Up" },
	prevPage = { file = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" }, -- NR
	nextPage = { file = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" },
	parchment = { file = "Interface\\QuestFrame\\QuestBG" }, -- FDJ (wash), classic
	-- Portraits and pins
	portraitMask = { file = "Interface\\CharacterFrame\\TempPortraitAlphaMask" }, -- NR, FDJ
	-- Rings around round art. `ring`: the ring texture's size per diameter of the art inside it; each crop is a square
	-- centred on its ring, so the ring is drawn centred on the art (Art.PlaceRing). Measured in the client's files:
	bossRing = { -- the Adventure Guide's boss pin ring (NR): its ring is centred in this 62 x 61 px crop
		file = "Interface\\EncounterJournal\\UI-EncounterJournalTextures",
		coords = { 0.84960938, 0.97070313, 0.42871094, 0.48828125 },
		ring = 1.32,
	},
	-- The minimap's tracking ring (FDJ map pins), 64 x 64 px: the ring (outer radius 16 px, inner 12.5) is centred at
	-- (20, 19), not in the middle of the file, and its shadow falls to the bottom right. The crop is the 38 px square
	-- around that centre; the art fills the ring's hole (25 of 38 px).
	pinRing = {
		file = "Interface\\Minimap\\MiniMap-TrackingBorder",
		coords = { 1 / 64, 39 / 64, 0, 38 / 64 },
		ring = 38 / 24.8,
		centre = { 20, 19, 64 }, -- x, y, file size in px (tests/test_mapfamily.lua checks the crop against it)
	},
	-- A boss without a portrait (WoW: Forever's journal has no bosses, so no display IDs): a skull icon in the ring.
	-- The journal's own blank face (UI-EJ-BOSS-Default) shows a red question mark on this client.
	bossDefault = { file = ICONS .. "INV_Misc_Bone_HumanSkull_01", round = true }, -- classic icon
	skull = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" }, -- OM
	-- Section buttons
	sectionMap = { file = ICONS .. "INV_Misc_Map_01", round = true },
	sectionPlan = { file = ICONS .. "INV_Misc_Book_09", round = true },
	sectionBosses = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
	sectionPulls = { file = ICONS .. "Ability_Warrior_Charge", round = true },
	sectionAssignments = { file = ICONS .. "Ability_Warrior_BattleShout", round = true },
	sectionGear = { file = ICONS .. "INV_Chest_Plate01", round = true },
	sectionRuns = { file = ICONS .. "INV_Misc_PocketWatch_01", round = true },
	sectionShare = { file = ICONS .. "INV_Scroll_03", round = true },
	sectionPrep = { file = ICONS .. "INV_Misc_Bag_08", round = true },
	-- The live Getting there map (UI/TravelMap.lua): the player's arrow, flight masters, a summoning stone.
	travelPlayer = { file = "Interface\\Minimap\\MinimapArrow" },
	travelFlight = { file = ICONS .. "Ability_Mount_Wyvern_01", round = true },
	travelStone = { file = ICONS .. "INV_Misc_Rune_01", round = true },
	-- Marker kinds on the map (bosses use their journal portrait; packs and patrols are pull-coloured discs)
	kind_boss = { file = ICONS .. "INV_Misc_Bone_HumanSkull_01", round = true },
	kind_rare = { file = ICONS .. "INV_Misc_Head_Dragon_01", round = true },
	kind_pack = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
	kind_patrol = { file = "Interface\\AddOns\\DungeonPlanner\\Media\\Arrow" },
	kind_loot = { file = ICONS .. "INV_Misc_Bag_10", round = true },
	kind_chest = { file = ICONS .. "INV_Box_01", round = true },
	-- A quest item shows its own icon where the client knows the item (MapPins.MarkerArt); this pouch otherwise. (The
	-- quest-in-progress atlas is three dots on this client: in a ring it read as cut-off text.)
	kind_quest_item = { file = ICONS .. "INV_Misc_Bag_07", round = true },
	kind_quest_npc = { atlas = "QuestNormal", file = "Interface\\GossipFrame\\AvailableQuestIcon" }, -- OM
	kind_npc = { file = "Interface\\GossipFrame\\GossipGossipIcon" }, -- classic
	kind_interactive = { file = ICONS .. "INV_Misc_Key_03", round = true },
	kind_entrance = { atlas = "Dungeon", file = ICONS .. "Spell_Arcane_PortalStormWind", round = true }, -- FDJ, OM
	kind_exit = { atlas = "poi-door", file = ICONS .. "Spell_Arcane_Blink", round = true }, -- OM
	kind_shortcut = { file = ICONS .. "Ability_Rogue_Sprint", round = true },
	kind_stairs = { atlas = "poi-door-arrow-up", file = ICONS .. "Spell_Magic_FeatherFall", round = true }, -- OM
	kind_hazard = { file = ICONS .. "Spell_Fire_Fire", round = true },
	kind_position = { file = ICONS .. "Ability_Warrior_DefensiveStance", round = true },
	kind_note = { file = ICONS .. "INV_Misc_Note_01", round = true },
	-- The legend's drawings layer (map drawings, UI/MapDraw.lua): a quill and parchment, classic
	drawings = { file = ICONS .. "INV_Misc_Note_02", round = true },
	-- The map's toolbar (UI/Panels/MapToolbar.lua) and drawing tools (UI/Panels/DrawBar.lua): the game's own cursors
	-- where one fits (the pointer, the map-pin cursor, the missions cursor's crossed swords, the directions scroll, the
	-- palette, the broom, the move arrows), the social queue's group, the red X and the delete button's bin; all in this
	-- client's atlas table. Atlases only: without one a tool shows its name, a drawing tool its glyph drawn by the addon.
	tool_select = { atlas = "crosshair_point_32" },
	tool_marker = { atlas = "crosshair_mappincursor_32" },
	tool_position = { atlas = "socialqueuing-icon-group" },
	tool_pull = { atlas = "crosshair_missions_32" },
	tool_route = { atlas = "crosshair_directions_32" },
	tool_draw = { atlas = "crosshair_palette_32" },
	tool_erase = { atlas = "common-icon-redx" },
	draw_erase = { atlas = "crosshair_broom_32" },
	draw_move = { atlas = "crosshair_ui-cursor-move_32" },
	draw_clear = { atlas = "128-redbutton-delete" },
	-- Party roles
	role_TANK = { file = ICONS .. "Ability_Warrior_DefensiveStance", round = true },
	role_HEALER = { file = ICONS .. "Spell_Holy_FlashHeal", round = true },
	role_MELEE = { file = ICONS .. "Ability_MeleeDamage", round = true },
	role_RANGED = { file = ICONS .. "Ability_Marksmanship", round = true },
	-- The party strip: the group finder's role glyphs (a shield, a cross, a sword, no coloured disc; the atlases its
	-- group list uses since Retail 7.x, else the classic LFGRole sheet cut the way the game's GetTexCoordsForRoleSmall
	-- does). Their round icons (partyDisc_*) are the fallback: at party-strip size the damage one, a slanted sword on
	-- a red disc, reads as a "no entry" sign.
	party_TANK = { atlas = "groupfinder-icon-role-micro-tank", file = LFG_ROLE_GLYPHS, coords = { 0.5, 0.75, 0, 1 } },
	party_HEALER = { atlas = "groupfinder-icon-role-micro-heal", file = LFG_ROLE_GLYPHS, coords = { 0.75, 1, 0, 1 } },
	party_DAMAGER = { atlas = "groupfinder-icon-role-micro-dps", file = LFG_ROLE_GLYPHS, coords = { 0.25, 0.5, 0, 1 } },
	partyDisc_TANK = { atlas = "UI-LFG-RoleIcon-Tank", file = LFG_ROLES, coords = { 0, 19 / 64, 22 / 64, 41 / 64 } },
	partyDisc_HEALER = { atlas = "UI-LFG-RoleIcon-Healer", file = LFG_ROLES,
		coords = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } },
	partyDisc_DAMAGER = { atlas = "UI-LFG-RoleIcon-DPS", file = LFG_ROLES,
		coords = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } },
	-- Launcher (minimap button, run mode's open button) and the window's emblem: Dungeon Planner's own logo
	-- (Media/LogoIcon.tga, rendered from Media/Logo/logo-icon.svg by tools/render_logo.py; the TOC's IconTexture too),
	-- or the game's map icon with the setting "Game map icon" (settings.gameIcon, Art.ApplyLauncher).
	launcher = { file = "Interface\\AddOns\\DungeonPlanner\\Media\\LogoIcon" },
	launcherLogo = { file = "Interface\\AddOns\\DungeonPlanner\\Media\\LogoIcon" },
	launcherGame = { file = ICONS .. "INV_Misc_Map_01", round = true }, -- classic
	-- Run mode, and the emblems on the plate drawn where the game has no picture of an instance
	runMode = { file = ICONS .. "Ability_Rogue_Sprint", round = true },
	emblemDungeon = { atlas = "Dungeon", file = ICONS .. "Spell_Arcane_PortalStormWind", round = true }, -- OM
	emblemRaid = { atlas = "Raid", file = ICONS .. "INV_Misc_Head_Dragon_01", round = true },
	-- A recommended plan: the raid target star (classic), as in the plan picker.
	recommended = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
	-- The drawn window's stone (UI/Style.lua; the rock is the fallback)
	windowStone = { file = "Interface\\FrameGeneral\\UI-Background-Marble" },
	windowEdge = { file = "Interface\\DialogFrame\\UI-DialogBox-Border" }, -- FDJ, OM
	-- Materials (UI/Style.lua; docs/UI.md). The inset's marble is the one InsetFrameTemplate tiles; the dialog's dark
	-- background is an atlas on current clients (WhatsTraining's Forever pages) and a file since the original game.
	insetBg = { file = "Interface\\FrameGeneral\\UI-Background-Marble" },
	dialogBg = { atlas = "UI-DialogBox-Background-Dark", file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
	menuBg = { atlas = "common-dropdown-bg" }, -- ForeverCore, OM, WhatsTraining (the game's menus)
	-- List rows: the settings list's hover and selection (WhatsTraining's Forever pages, Baganator), else the quest
	-- title glow and our drawn selection.
	listHover = { atlas = "Options_List_Hover", file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
	listSelected = { atlas = "Options_List_Active" },
	headerStrip = { file = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" }, -- GearQuest Forever, NR, DBM
	-- The game's page arrows (the spell book's and merchant's previous / next page; W.PageButton). FDJ, OM, NR,
	-- Leatrix Plus.
	pagePrevUp = { file = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" },
	pagePrevDown = { file = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down" },
	pagePrevDisabled = { file = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled" },
	pageNextUp = { file = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" },
	pageNextDown = { file = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down" },
	pageNextDisabled = { file = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled" },
	buttonHighlight = { file = "Interface\\Buttons\\UI-Common-MouseHilight" },
}

-- Which icon the launcher shows: our logo, or the game's map icon when the player picks it (settings.gameIcon). Every
-- user of the "launcher" key reads it from here; the window and run mode take a change on their next build (/reload).
function Art.ApplyLauncher(settings)
	local game = type(settings) == "table" and settings.gameIcon == true
	Art.SPECS.launcher = game and Art.SPECS.launcherGame or Art.SPECS.launcherLogo
	return Art.SPECS.launcher
end

local atlasCache = {}

function Art.HasAtlas(name)
	if not name then
		return false
	end
	if atlasCache[name] == nil then
		local ok, info = false, nil
		if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
			ok, info = pcall(C_Texture.GetAtlasInfo, name)
		end
		atlasCache[name] = ok and type(info) == "table" or false
	end
	return atlasCache[name]
end

-- Width / height of the atlas art `key` draws with (an Art key), or nil: no atlas, the client lacks it, or its info
-- has no size. Pictures in a square slot keep this shape (W.Button SetIcon).
function Art.AtlasAspect(key)
	local spec = Art.SPECS[key]
	if not (spec and spec.atlas and Art.HasAtlas(spec.atlas)) then
		return nil
	end
	local ok, info = pcall(C_Texture.GetAtlasInfo, spec.atlas)
	local w = ok and type(info) == "table" and tonumber(info.width)
	local h = ok and type(info) == "table" and tonumber(info.height)
	if w and h and w > 0 and h > 0 then
		return w / h
	end
end

-- Is a texture file known to the client? true / false, or nil when the client cannot tell us.
function Art.FileExists(path)
	if type(path) == "number" then
		return true
	end
	if type(GetFileIDFromPath) ~= "function" then
		return nil
	end
	local ok, id = pcall(GetFileIDFromPath, path)
	return ok and id ~= nil
end

-- The answers per path for the session (a file does not appear while the game runs). Art.ForgetFiles: for tests (the
-- atlas answers go too).
local fileKnown = {}
function Art.ForgetFiles()
	fileKnown = {}
	atlasCache = {}
end

-- Set a file on a texture when the client has it: true when set, false (the texture untouched) when it is missing, so
-- the caller draws its fallback. A game file is looked up by name (GetFileIDFromPath): SetTexture answers true on this
-- client even for a missing file. The addon's own Media files are loose files the lookup does not list; they, file IDs,
-- and every file on a client without the lookup are set and trusted as before.
function Art.SetFile(tex, file)
	if type(file) == "string" and file ~= "" and not file:lower():find("^interface[\\/]addons[\\/]") then
		local known = fileKnown[file]
		if known == nil then
			known = Art.FileExists(file)
			fileKnown[file] = known == nil and "unknown" or known
		end
		if known == false then
			return false
		end
	elseif type(file) ~= "number" and type(file) ~= "string" then
		return false
	end
	return tex:SetTexture(file) ~= false
end

-- Draw art `key` on a texture. Returns true when something was set. A missing file (Art.SetFile) leaves the texture
-- as it was, so the caller can show its own fallback (a glyph, a colour).
function Art.Set(tex, key, desaturate)
	local spec = type(key) == "table" and key or Art.SPECS[key]
	if not spec then
		return false
	end
	if tex.dpModel then
		Art.ReleasePortrait(tex) -- a creature portrait over this texture goes back to the pool
	end
	local ok = false
	if spec.atlas and Art.HasAtlas(spec.atlas) and tex.SetAtlas then
		tex:SetAtlas(spec.atlas)
		tex:SetTexCoord(0, 1, 0, 1)
		ok = true
	elseif spec.file then
		ok = Art.SetFile(tex, spec.file)
		local c = spec.coords
		if c then
			tex:SetTexCoord(c[1], c[2], c[3], c[4])
		elseif spec.round then
			-- Icons have a dark 1/16 rim; crop it like the game's own round icons.
			tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		else
			tex:SetTexCoord(0, 1, 0, 1)
		end
	end
	if tex.SetDesaturated then
		tex:SetDesaturated(desaturate and true or false)
	end
	return ok
end

-- Draw ring `key` (pinRing, bossRing) on `tex` around round art `size` across that is centred on `anchor`: the ring's
-- centre on the art's centre, one size per art size, for every map pin, step badge and list icon alike.
function Art.PlaceRing(tex, anchor, size, key, desaturate)
	key = key or "pinRing"
	local spec = Art.SPECS[key]
	local d = size * (spec and spec.ring or 1.5)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	tex:SetSize(d, d)
	return Art.Set(tex, key, desaturate)
end

-- A circular texture: a texture plus the game's round portrait mask (CreateMaskTexture). Without masks it stays square.
function Art.RoundTexture(parent, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	if parent.CreateMaskTexture and tex.AddMaskTexture then
		local mask = parent:CreateMaskTexture()
		local spec = Art.SPECS.portraitMask
		pcall(mask.SetTexture, mask, spec.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(tex)
		tex:AddMaskTexture(mask)
		tex.dpMask = mask
	end
	return tex
end

-- Creature portraits. On WoW: Forever a model portrait drawn on a visible texture before the model has loaded shows
-- as a black square painted over every window (the Dungeon Journal addon documents this). So a model portrait is first
-- drawn on a texture parked on a frame far off screen while the client loads the creature (PORTRAIT_LOAD seconds), and
-- only then moved over the texture that shows it (the "host", which shows the placeholder skull meanwhile). Finished
-- portraits are pooled per creature and reused for the session; a host that shows something else gives its portrait
-- back.
--
-- Every portrait still loading waits for one shared timer (a batch): when it fires, each ready portrait is drawn
-- again (the creature is loaded by now, so this time the picture is complete) and moved onto its host in place, so the
-- rows, the boss header and the map pins on screen change from the skull to the face without being rebuilt; then
-- PORTRAITS_READY fires. A portrait asked for later in the wait gets one more timer for the rest; with nothing
-- loading, no timer runs.
--
-- A creature loads once: a second texture for a creature that is still loading shares the first one's wait, and one
-- for a creature already loaded is ready at once. Art.PrefetchPortraits starts the wait before anything shows the
-- creature (a plan is chosen, the player enters an instance), so the rows and pins drawn a moment later get the face
-- sooner, or at once.
local PORTRAIT_LOAD = 2.5
Art.PORTRAIT_LOAD = PORTRAIT_LOAD
local staging
local portraitPool = {} -- [displayID] = { texture, ... }
local loading = {} -- textures whose creature is still loading, in the order they were asked for
local loaded = {} -- [displayID] = true once a texture of that creature finished its wait
local batchTimer = false -- a timer is pending

local function now()
	return GetTime and GetTime() or 0
end

local function stagingFrame()
	if not staging then
		staging = CreateFrame("Frame", nil, UIParent)
		staging:SetSize(64, 64)
		staging:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0)
		staging:Show()
	end
	return staging
end

local function park(model)
	model:SetParent(stagingFrame())
	model:ClearAllPoints()
	model:SetAllPoints(staging)
	model:Show()
end

function Art.ReleasePortrait(host)
	local model = host and host.dpModel
	if not model then
		return
	end
	if host.dpMask and model.RemoveMaskTexture then
		pcall(model.RemoveMaskTexture, model, host.dpMask)
	end
	host.dpModel, model.dpHost = nil, nil
	park(model)
end

local function placePortrait(host, model)
	if host.dpModel ~= model or not model.dpReady then
		return
	end
	local parent = host:GetParent()
	if not parent then
		return
	end
	model:SetParent(parent)
	model:ClearAllPoints()
	model:SetAllPoints(host)
	local layer, sub = host:GetDrawLayer()
	if layer then
		model:SetDrawLayer(layer, math.min(7, (sub or 0) + 1))
	end
	if host.dpMask and model.AddMaskTexture then
		pcall(model.AddMaskTexture, model, host.dpMask)
	end
	model:SetTexCoord(0, 1, 0, 1)
	if model.SetDesaturated and host.IsDesaturated then
		model:SetDesaturated(host:IsDesaturated() and true or false)
	end
	model:Show()
end

local scheduleBatch

-- The batch timer: every portrait whose wait is over becomes ready and goes onto its host; the rest wait for one more
-- timer.
local function flushPortraits()
	batchTimer = false
	local t, still, done = now(), {}, 0
	for _, model in ipairs(loading) do
		if (model.dpReadyAt or 0) <= t + 0.01 then
			model.dpReady = true
			loaded[model.dpDisplayID] = true
			done = done + 1
			-- Drawn again while still parked: the creature has loaded, so the picture is complete this time.
			pcall(SetPortraitTextureFromCreatureDisplayID, model, model.dpDisplayID)
			local host = model.dpHost
			if host then
				placePortrait(host, model)
			end
		else
			still[#still + 1] = model
		end
	end
	loading = still
	if #loading > 0 then
		scheduleBatch()
	end
	if done > 0 and ns.Fire then
		ns:Fire("PORTRAITS_READY")
	end
end

scheduleBatch = function()
	if batchTimer or #loading == 0 or not (C_Timer and C_Timer.After) then
		return
	end
	local first = math.huge
	for _, model in ipairs(loading) do
		first = math.min(first, model.dpReadyAt or 0)
	end
	batchTimer = true
	C_Timer.After(math.max(0, first - now()) + 0.05, function()
		ns.SafeCall(flushPortraits)
	end)
end

-- For tests: forget which creatures have loaded and the free textures, as at the start of a session (textures on a
-- host stay there).
function Art.ResetPortraitCache()
	portraitPool, loaded = {}, {}
end

-- For tests and /dp debug: how many portraits are loading, and whether a timer waits for them.
function Art.PortraitsLoading()
	return #loading, batchTimer
end

-- The creature `host` shows right now (its portrait is ready and on it), or nil (a placeholder or a plain picture).
function Art.PortraitShown(host)
	local model = host and host.dpModel
	if model and model.dpReady and model.dpHost == host and model:GetParent() == host:GetParent() then
		return model.dpDisplayID
	end
	return nil
end

local function canDrawPortraits()
	return type(SetPortraitTextureFromCreatureDisplayID) == "function" and CreateFrame ~= nil
end

-- A new parked texture for creature `displayID`, added to its pool: ready at once when the creature has loaded
-- before, else waiting (with the creature's earlier textures still loading, until they are ready). Nil when the client
-- cannot draw it.
local function newModel(displayID)
	local list = portraitPool[displayID] or {}
	portraitPool[displayID] = list
	local model = stagingFrame():CreateTexture(nil, "ARTWORK")
	park(model)
	if not pcall(SetPortraitTextureFromCreatureDisplayID, model, displayID) then
		model:Hide()
		return nil
	end
	model.dpDisplayID = displayID
	list[#list + 1] = model
	if loaded[displayID] or not (C_Timer and C_Timer.After) then
		model.dpReady = true -- loaded already, or no timers on this client: nothing to wait for
		return model
	end
	local readyAt = now() + PORTRAIT_LOAD
	for _, other in ipairs(loading) do
		if other.dpDisplayID == displayID then
			readyAt = math.min(readyAt, other.dpReadyAt or readyAt)
		end
	end
	model.dpReadyAt = readyAt
	loading[#loading + 1] = model
	scheduleBatch()
	return model
end

-- Show creature `displayID` on `host`. Returns false when the client cannot draw it.
local function acquirePortrait(host, displayID)
	if not canDrawPortraits() then
		return false
	end
	if host.dpModel and host.dpModel.dpDisplayID == displayID then
		placePortrait(host, host.dpModel)
		return true
	end
	Art.ReleasePortrait(host)
	local model
	for _, candidate in ipairs(portraitPool[displayID] or {}) do
		if not candidate.dpHost then
			model = candidate
			break
		end
	end
	model = model or newModel(displayID)
	if not model then
		return false
	end
	model.dpHost, host.dpModel = host, model
	placePortrait(host, model) -- only when ready; otherwise the batch timer places it
	return true
end

-- Start loading creatures before anything shows them: one parked texture per creature not asked for yet (the first
-- view that shows it takes that texture; more views of it share its wait). Nothing else happens: no frame, no
-- timer beyond the batch's. displayIDs: a list (repeats are skipped). Returns how many started loading.
function Art.PrefetchPortraits(displayIDs)
	if type(displayIDs) ~= "table" or not canDrawPortraits() then
		return 0
	end
	local started = 0
	for _, id in ipairs(displayIDs) do
		if type(id) == "number" and not (portraitPool[id] and #portraitPool[id] > 0) and newModel(id) then
			started = started + 1
		end
	end
	return started
end

-- A boss portrait from the client: the creature's model portrait (the journal's display ID, loaded off screen as
-- above), else the journal's boss icon (a file), else the journal's blank face. The face stays under the portrait
-- until it is ready.
function Art.SetBossPortrait(tex, art)
	Art.Set(tex, "bossDefault")
	if art and art.displayInfo and acquirePortrait(tex, art.displayInfo) then
		return true
	end
	if art and art.icon and Art.SetFile(tex, art.icon) then
		tex:SetTexCoord(0, 1, 0, 1)
		return true
	end
	return Art.Set(tex, "bossDefault")
end

-- For /dp debug: every atlas and file this UI uses, and which ones the client does not have.
function Art.Report()
	local rows = {}
	for _, key in ipairs(ns.Util.SortedKeys(Art.SPECS)) do
		local spec = Art.SPECS[key]
		local atlasOk = spec.atlas and Art.HasAtlas(spec.atlas) or nil
		local fileOk = spec.file and Art.FileExists(spec.file)
		rows[#rows + 1] = { key = key, atlas = spec.atlas, atlasOk = atlasOk, file = spec.file, fileOk = fileOk }
	end
	return rows
end

-- Native pieces --------------------------------------------------------------------------------------------------------
-- The game's own window parts (docs/UI.md, Materials): frame templates, nine-slice border layouts and the helper
-- functions that drive them. Each is used through the functions below, which check it first and report a fallback, so
-- a client without one draws our own version instead. Where each was seen on WoW: Forever (read in the installed
-- addons, never copied): ButtonFrameTemplate and its helpers NeedRoll, DBM, Baganator; PortraitFrameTemplate
-- GearQuest Forever; InsetFrameTemplate, MinimalScrollBar WhatsTraining's Forever pages, Dungeon Journal; layouts
-- ButtonFrameTemplateNoPortrait OpenMap and DBM, InsetFrameTemplate Auctionator, Dialog Baganator; PanelTabButtonTemplate
-- with the PanelTemplates helpers BugSack and DBM ("Forever shares Mainline's tab helpers"); UIPanelButtonTemplate,
-- PanelTopTabButtonTemplate NeedRoll.
Art.TEMPLATES = {
	"BackdropTemplate",
	"ButtonFrameTemplate",
	"GameTooltipTemplate",
	"MinimalScrollBar",
	"NineSlicePanelTemplate",
	"PanelTabButtonTemplate",
	"PanelTopTabButtonTemplate",
	"UIPanelButtonTemplate",
	"UIPanelCloseButton",
}
Art.LAYOUTS = { "ButtonFrameTemplateNoPortrait", "Dialog", "InsetFrameTemplate", "PortraitFrameTemplate" }
Art.HELPERS = {
	"ButtonFrameTemplate_HideButtonBar",
	"ButtonFrameTemplate_HidePortrait",
	"NineSliceUtil.ApplyLayoutByName",
	"PanelTemplates_DeselectTab",
	"PanelTemplates_SelectTab",
	"PanelTemplates_TabResize",
}
Art.missingTemplates = {}
Art.usedTemplates = {}

function Art.CreateFrame(kind, name, parent, template)
	if template then
		local ok, frame = pcall(CreateFrame, kind, name, parent, template)
		if ok and frame then
			Art.usedTemplates[template] = true
			return frame, true
		end
		Art.missingTemplates[template] = true
	end
	return CreateFrame(kind, name, parent), false
end

-- A global function by name ("NineSliceUtil.ApplyLayoutByName" looks inside a table), or nil.
function Art.Helper(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		value = type(value) == "table" and rawget(value, part) or nil
	end
	return type(value) == "function" and value or nil
end

-- Does the client have nine-slice layout `name` (NineSliceUtil.GetLayout, as OpenMap checks)?
function Art.HasLayout(name)
	local util = rawget(_G, "NineSliceUtil")
	if type(util) ~= "table" or type(util.GetLayout) ~= "function" or not Art.Helper("NineSliceUtil.ApplyLayoutByName") then
		return false
	end
	local ok, layout = pcall(util.GetLayout, name)
	return ok and layout ~= nil
end

-- Draw layout `name` on `frame` (its border pieces become textures of `frame`). Returns true when it was drawn.
function Art.ApplyLayout(frame, name)
	if not Art.HasLayout(name) then
		return false
	end
	return (pcall(Art.Helper("NineSliceUtil.ApplyLayoutByName"), frame, name))
end

-- Is frame template `name` known to the client? true / false, or nil when it cannot tell (C_XMLUtil missing and the
-- UI has not tried it yet).
function Art.HasTemplate(name)
	if Art.usedTemplates[name] then
		return true
	elseif Art.missingTemplates[name] then
		return false
	end
	local xml = rawget(_G, "C_XMLUtil")
	if type(xml) == "table" and type(xml.GetTemplateInfo) == "function" then
		local ok, info = pcall(xml.GetTemplateInfo, name)
		return ok and info ~= nil
	end
	return nil
end

-- For /dp debug: each native piece and whether this client has it ({ kind, name, ok }; ok nil = cannot tell).
function Art.NativeReport()
	local rows = {}
	for _, name in ipairs(Art.TEMPLATES) do
		rows[#rows + 1] = { kind = "template", name = name, ok = Art.HasTemplate(name) }
	end
	for _, name in ipairs(Art.LAYOUTS) do
		rows[#rows + 1] = { kind = "layout", name = name, ok = Art.HasLayout(name) }
	end
	for _, name in ipairs(Art.HELPERS) do
		rows[#rows + 1] = { kind = "helper", name = name, ok = Art.Helper(name) ~= nil }
	end
	return rows
end
