-- Optional integrations with other addons. Each uses only the other addon's public entry points, is guarded, and does
-- nothing when the addon is missing. Nothing here hooks another addon's internals. docs/COMPATIBILITY.md has the matrix
-- of what is integrated, what was decided against, and what is verified.
--
--   Dungeon Journal (ForeverDungeonJournal): the global ForeverDungeonJournal_Toggle() (its binding/compartment entry).
--   OpenMap: OpenMapAPI major 1: RegisterDungeonSection (our plans on its dungeon card) and RegisterMenuToggle; the
--     experimental plan overlay on its own dungeon view reads that private frame (UI/OpenMapOverlay.lua).
--   WoW Po Polsku Forever: detected to choose Polish (Locales) and to follow its fonts (UI/Style.lua).
--   LibDataBroker-1.1 + LibDBIcon-1.0: the launcher and the minimap button (collectors such as MinimapButtonButton
--     pick LibDBIcon buttons up by themselves).

local _, ns = ...
local Integrations = ns:NewModule("Integrations")

-- WoW Po Polsku ---------------------------------------------------------------------------------------------------------
-- The translation runs on an English client: GetLocale() stays "enUS" (its own code checks for an English client), so
-- the only signal that a player wants Polish is the addon itself. Its folder is WoWPoPolskuForever (v0.4.0 on this
-- machine); other folders containing "polsku" are matched too. It can also translate into Czech, Hungarian or
-- Vietnamese: its saved choice (WoWPoPolskuForeverDB.jezyk, read only) decides whether Polish is meant.

local POLISH_FOLDERS = { "WoWPoPolskuForever", "WoWPoPolsku" }

local function addonState(name)
	if not C_AddOns then
		return false, false
	end
	local loaded = false
	if C_AddOns.IsAddOnLoaded then
		local ok, v = pcall(C_AddOns.IsAddOnLoaded, name)
		loaded = ok and v == true
	end
	-- Enabled for this character (it may simply load after us: "D" comes before "W").
	local enabled = loaded
	if not enabled and C_AddOns.GetAddOnEnableState then
		local player = UnitName and UnitName("player") or nil
		local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, player)
		enabled = ok and type(state) == "number" and state > 0
	end
	return loaded, enabled
end

-- An addon's state for this character: "loaded", "enabled" (it loads later), "disabled", "missing" or "unknown". Used
-- for the font chain (UI/Fonts.lua): the client does not open the files of a disabled addon.
function Integrations.AddonState(name)
	local loaded, enabled = addonState(name)
	if loaded then
		return "loaded"
	elseif enabled then
		return "enabled"
	end
	if C_AddOns and C_AddOns.GetAddOnInfo then
		-- name, title, notes, loadable, reason ("DISABLED", "MISSING", ...); no name: not installed.
		local ok, found, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, name)
		if ok then
			return (found == nil or reason == "MISSING") and "missing" or "disabled"
		end
	end
	return "unknown"
end

-- The language WoW Po Polsku actually translates into, or nil. It only translates once the player has picked a language
-- in its first-run chooser: its Rdzen.lua accepts db.jezyk only when db.wyborJezyka >= 1. An installed but never
-- configured copy (no language chosen) translates nothing, so it must not switch us to Polish either.
local function translationLanguage()
	local db = rawget(_G, "WoWPoPolskuForeverDB")
	if type(db) ~= "table" or db.wlaczony == false then
		return nil
	end
	if (tonumber(db.wyborJezyka) or 0) < 1 then
		return nil
	end
	local code = db.jezyk
	return type(code) == "string" and code or nil
end

local polish
function Integrations.PolishTranslationLoaded()
	if polish ~= nil then
		return polish
	end
	local found = false
	for _, name in ipairs(POLISH_FOLDERS) do
		local loaded, enabled = addonState(name)
		if loaded or enabled then
			found = true
			break
		end
	end
	if not found and C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetNumAddOns then
		for i = 1, C_AddOns.GetNumAddOns() do
			local ok, name = pcall(C_AddOns.GetAddOnInfo, i)
			if ok and type(name) == "string" and name:lower():find("polsku", 1, true) then
				local loaded, enabled = addonState(name)
				if loaded or enabled then
					found = true
					break
				end
			end
		end
	end
	if found then
		-- Its saved language is known once its SavedVariables are loaded (after PLAYER_LOGIN at the latest).
		found = translationLanguage() == "plPL"
	end
	if ns.loggedIn then
		polish = found
	end
	return found
end

-- For tests: forget the answer kept since the login.
function Integrations.ForgetPolishTranslation()
	polish = nil
end

-- Dungeon Journal ---------------------------------------------------------------------------------------------------------

function Integrations.HasDungeonJournal()
	return type(rawget(_G, "ForeverDungeonJournal_Toggle")) == "function"
end

function Integrations.OpenDungeonJournal()
	if Integrations.HasDungeonJournal() then
		ns.SafeCall(_G.ForeverDungeonJournal_Toggle)
		return true
	end
	return false
end

-- OpenMap -----------------------------------------------------------------------------------------------------------------

local function openMapApi()
	local api = rawget(_G, "OpenMapAPI")
	if type(api) == "table" and api.major == 1 then
		return api
	end
	return nil
end

-- Plans that belong to a dungeon map OpenMap shows: by map ID (a plan floor's uiMapID) or by instance name. Saved and
-- recommended plans.
function Integrations.PlansForOpenMap(info)
	local out = {}
	if type(info) ~= "table" or not ns.db then
		return out
	end
	local names = {}
	if type(info.instances) == "table" then
		for _, inst in ipairs(info.instances) do
			if type(inst) == "table" and type(inst.name) == "string" then
				names[inst.name:lower()] = true
			end
		end
	end
	local all = {}
	for _, plan in pairs(ns.db.plans) do
		all[#all + 1] = plan
	end
	-- Recommended plans too (shown with their name; opening one in Dungeon Planner offers an editable copy).
	for _, plan in ipairs(ns.Bundled and ns.Bundled.All() or {}) do
		all[#all + 1] = plan
	end
	for _, plan in ipairs(all) do
		local match = false
		for _, floor in ipairs(plan.floors) do
			if floor.uiMapID and floor.uiMapID == info.mapID then
				match = true
			end
		end
		if names[ns.Names.Instance(plan.instance):lower()] or names[(plan.instance.name or ""):lower()]
			or names[ns.Instances.CanonicalName(plan):lower()] then
			match = true
		end
		if match then
			out[#out + 1] = plan
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function registerOpenMap()
	local api = openMapApi()
	if not api then
		return false
	end
	if type(api.RegisterDungeonSection) == "function" then
		pcall(api.RegisterDungeonSection, ns.name, function(info)
			-- OpenMap's dungeon card is up: its own dungeon view may open next (UI/OpenMapOverlay.lua).
			if ns.OpenMapOverlay then
				ns.OpenMapOverlay.CardShown()
			end
			local plans = Integrations.PlansForOpenMap(info)
			if #plans == 0 then
				return nil
			end
			local lines = {}
			for i, plan in ipairs(plans) do
				if i > 12 then
					break
				end
				lines[#lines + 1] = string.format("%s (%s, %s)", plan.name, ns.Plural(#plan.pulls, ns.L["%d pull|%d pulls"]),
					ns.Plural(#plan.encounters, ns.L["%d boss|%d bosses"]))
			end
			lines[#lines + 1] = ns.L["Open with /dp"]
			return ns.title, lines
		end)
	end
	-- No menu entry with the gamepad interface style on (Compat.Gamepad).
	if type(api.RegisterMenuToggle) == "function" and not ns.Compat.Gamepad() then
		pcall(api.RegisterMenuToggle, ns.name, {
			id = "window",
			label = ns.title,
			icon = Integrations.LauncherIcon(),
			tab = "more",
			get = function()
				return ns.UI.IsShown()
			end,
			set = function(on)
				if on ~= ns.UI.IsShown() then
					ns.UI.Toggle()
				end
			end,
		})
		-- Experimental: the plan on OpenMap's own dungeon map (UI/OpenMapOverlay.lua; off by default).
		local overlay = ns.OpenMapOverlay
		if overlay then
			pcall(api.RegisterMenuToggle, ns.name, {
				id = "openmapOverlay",
				label = ns.L["Show plan on OpenMap's dungeon map (experimental)"],
				icon = Integrations.LauncherIcon(),
				section = ns.title,
				get = function()
					overlay.Look()
					return overlay.IsEnabled()
				end,
				set = function(on)
					overlay.SetEnabled(on)
				end,
			})
		end
	end
	return true
end

-- Launcher and minimap button ---------------------------------------------------------------------------------------------

-- Our logo (Media/LogoIcon.tga, shipped with the addon), or the game's map icon when the player picks it
-- (settings.gameIcon); the drawn route icon if the client lacks the game's.
function Integrations.LauncherIcon()
	local spec = ns.Art and ns.Art.SPECS.launcher
	local path = spec and spec.file
	if not path or (spec ~= ns.Art.SPECS.launcherLogo and ns.Art.FileExists(path) == false) then
		return ns.Style.MEDIA .. "Icon"
	end
	return path
end

-- After the setting changes: the minimap button takes the new icon at once (LibDBIcon follows the data object).
function Integrations.RefreshLauncherIcon()
	ns.Art.ApplyLauncher(ns.db.settings)
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local object = LDB and LDB:GetDataObjectByName(ns.name)
	if object then
		object.icon = Integrations.LauncherIcon()
	end
end

local function tooltip(tt)
	tt:AddLine(ns.title)
	local plan = ns.DB.GetPlan(ns.db.ui.selectedPlan)
	if plan then
		tt:AddLine(plan.name, 1, 1, 1)
		local inst = ns.Names.Instance(plan.instance)
		if inst ~= "" then
			tt:AddLine(inst, 0.63, 0.63, 0.63)
		end
		local pull = ns.API.GetCurrentPull()
		if pull then
			tt:AddLine(string.format(ns.L["Pull %d/%d: %s"], pull.index, #plan.pulls, pull.name), 0.63, 0.63, 0.63)
		end
	else
		tt:AddLine(ns.L["No plan selected"], 0.63, 0.63, 0.63)
	end
	tt:AddLine(" ")
	tt:AddLine(ns.L["Click to open. Right-click for the menu. Drag to move."], 0.63, 0.63, 0.63)
end

function Integrations.QuickMenu(owner)
	local A = ns.Actions
	ns.Widgets.Menu(owner, {
		{ title = ns.title },
		{ ns.L["Open"], A.Toggle },
		{ ns.L["Map"], A.OpenMap },
		{
			ns.L["Next pull"],
			function()
				A.StepPull(1)
			end,
		},
		{ ns.L["Share with group"], A.ShareWithGroup },
		"-",
		{ ns.L["Settings"], ns.UI.OpenSettings },
		{
			ns.L["Hide minimap button"],
			function()
				Integrations.SetMinimapShown(false)
			end,
		},
	})
end

function Integrations.SetMinimapShown(show)
	ns.db.minimap.hide = not show
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if icon then
		if show then
			icon:Show(ns.name)
		else
			icon:Hide(ns.name)
			ns:Print(ns.L["Minimap button hidden. /dp minimap shows it again."])
		end
	end
end

local function registerLauncher()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if not LDB then
		return false
	end
	local object = LDB:GetDataObjectByName(ns.name) or LDB:NewDataObject(ns.name, {
		type = "launcher",
		label = ns.title,
		icon = Integrations.LauncherIcon(),
		OnClick = function(frame, button)
			if button == "RightButton" then
				Integrations.QuickMenu(frame)
			else
				ns.UI.Toggle()
			end
		end,
		OnTooltipShow = tooltip,
	})
	local icon = LibStub("LibDBIcon-1.0", true)
	if icon and not icon:IsRegistered(ns.name) then
		-- LibDBIcon saves the angle (minimapPos) and hide flag in our profile, and lets the player drag the button
		-- around the minimap edge.
		icon:Register(ns.name, object, ns.db.minimap)
	end
	return true
end

Integrations.status = {}

function Integrations.Init()
	Integrations.status.launcher = registerLauncher()
	Integrations.status.openMap = registerOpenMap()
	if ns.OpenMapOverlay then
		ns.OpenMapOverlay.Init()
	end
	Integrations.status.dungeonJournal = Integrations.HasDungeonJournal()
	Integrations.status.polish = Integrations.PolishTranslationLoaded()
	ns:On("PROFILE_CHANGED", Integrations, function()
		Integrations.RefreshLauncherIcon()
		local icon = LibStub and LibStub("LibDBIcon-1.0", true)
		if icon and icon.Refresh then
			pcall(icon.Refresh, icon, ns.name, ns.db.minimap)
		end
	end)
end

-- Addon compartment (the TOC's AddonCompartmentFunc needs a global function).
function _G.DungeonPlanner_OnAddonCompartmentClick(_, button)
	if not ns.db then
		return
	end
	if button == "RightButton" then
		ns.UI.OpenSettings()
	else
		ns.UI.Toggle()
	end
end
