-- Startup, in AceAddon's lifecycle:
--   OnInitialize (our SavedVariables are loaded): database, migrations.
--   OnEnable (PLAYER_LOGIN: every addon has loaded): language, fonts, sharing, tracking, integrations, settings, slash.
-- The window itself is built the first time it opens, never at login.

local _, ns = ...
local addon = ns.addon

local function applyLanguage()
	ns.SetLocale(ns.db.settings.locale)
	ns.ApplyBindingStrings()
end

function addon:OnInitialize()
	ns.DB.Init()
	-- Binding names must exist before the Key Bindings UI is opened; refined in OnEnable once all addons are known.
	applyLanguage()
end

function addon:OnEnable()
	ns.loggedIn = true
	ns.Compat.Gamepad() -- once, before anything registers (slash commands, Escape, menu entries)
	applyLanguage()
	ns.Style.Init()
	ns.Comm.Init()
	ns.Tracker.Init()
	ns.Recorder.Init()
	ns.Providers.Init()
	ns.Prompts.Init()
	ns.Art.ApplyLauncher(ns.db.settings)
	ns.Integrations.Init()
	ns.UI.InitSettings()
	ns.RunSync.Init()
	ns.PrepInfo.Init()
	ns.TravelMap.Init()
	ns.RunMode.Init()
	ns.NotesFrame.Init()
	ns.Portraits.Init()
	ns.Slash.Init()
	ns.WhatsNew.Init()
	ns.Report.Init()
	ns:On("PROFILE_CHANGED", addon, function()
		ns.Style.SetTheme(ns.db.settings.theme)
		ns.Style.SetupFonts()
		ns.UI.ApplyScale()
		if ns.UI.IsShown() then
			ns.UI.RefreshSidebar()
			ns.UI.RefreshPage()
		end
	end)
end
