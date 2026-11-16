-- Settings: an AceConfig-3.0 options table, shown in the game's Settings panel (Options > AddOns > Dungeon Planner)
-- through AceConfigDialog, with AceDBOptions' profile page under it. /dp settings opens it.

local _, ns = ...
local UI = ns.UI
local L = ns.L

local APP = "DungeonPlanner"
local categoryID

local function set(path, value)
	local t = ns.db.settings
	for i = 1, #path - 1 do
		t = t[path[i]]
	end
	t[path[#path]] = value
end

local function get(path)
	local t = ns.db.settings
	for i = 1, #path do
		t = t[path[i]]
	end
	return t
end

local function fontValues()
	local values = {
		auto = L["Automatic"],
		game = L["Game font"],
		follow = L["Follow the game's fonts (translation and font addons)"],
		clean = L["Arial Narrow (Latin only)"],
	}
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("font")) do
			values["lsm:" .. name] = "SharedMedia: " .. name
		end
	end
	return values
end

local function options()
	return {
		type = "group",
		name = ns.title,
		args = {
			about = {
				type = "description",
				order = 1,
				fontSize = "medium",
				name = string.format(L["Version %s. Open the planner with /dp, the minimap button or a key binding."], ns.version),
			},
			look = {
				type = "group",
				inline = true,
				order = 10,
				name = L["Appearance"],
				args = {
					language = {
						type = "select",
						order = 1,
						name = L["Language"],
						desc = L["Automatic uses Polish when WoW Po Polsku is loaded, otherwise the game's language. Takes effect after /reload."],
						values = { auto = L["Automatic"], enUS = "English", plPL = "Polski" },
						get = function()
							return ns.db.settings.locale
						end,
						set = function(_, v)
							ns.db.settings.locale = v
							ns.Style.SetupFonts()
							-- Polish without a loadable Polish face: say so now (UI/Fonts.lua).
							ns:Print(L["Language changes take effect after /reload."] .. ns.Style.PolishFontNote():gsub("\n\n", " "))
						end,
					},
					font = {
						type = "select",
						order = 3,
						width = "double",
						name = L["Font"],
						desc = L["Automatic follows WoW Po Polsku's fonts when it is loaded (they have Polish letters), else the game font."],
						values = fontValues,
						get = function()
							return ns.db.settings.font
						end,
						set = function(_, v)
							ns.db.settings.font = v
							ns.Style.SetupFonts()
							ns.Style.Repaint()
						end,
					},
					scale = {
						type = "range",
						order = 4,
						name = L["Window scale"],
						min = 0.7,
						max = 1.4,
						step = 0.05,
						get = function()
							return ns.db.settings.scale
						end,
						set = function(_, v)
							ns.db.settings.scale = v
							UI.ApplyScale()
						end,
					},
					minimap = {
						type = "toggle",
						order = 5,
						name = L["Minimap button"],
						get = function()
							return not ns.db.minimap.hide
						end,
						set = function(_, v)
							ns.Integrations.SetMinimapShown(v)
						end,
					},
					coords = {
						type = "toggle",
						order = 6,
						name = L["Show map coordinates"],
						get = function()
							return get({ "showCoordinates" })
						end,
						set = function(_, v)
							set({ "showCoordinates" }, v)
						end,
					},
					mapColors = {
						type = "select",
						order = 6.2,
						name = L["Map colours"],
						desc = L["Forever's new dungeons without another addon's map: in parchment colours like the classic maps, or the minimap's own."],
						values = { parchment = L["Parchment"], game = L["Game minimap colours"] },
						sorting = { "parchment", "game" },
						get = function()
							return ns.MapCanvas.MapColors()
						end,
						set = function(_, v)
							ns.db.settings.mapColors = v == "game" and "game" or "parchment"
							UI.ApplyColors()
						end,
					},
					colorblind = {
						type = "toggle",
						order = 6.5,
						width = "double",
						name = L["Colour-blind friendly colours"],
						desc = L["Pulls, routes, drawings and party roles use colours that stay apart with red-green or blue-yellow colour blindness."],
						get = function()
							return get({ "colorblind" })
						end,
						set = function(_, v)
							set({ "colorblind" }, v)
							UI.ApplyColors()
						end,
					},
					confirm = {
						type = "toggle",
						order = 7,
						name = L["Confirm before deleting plans"],
						get = function()
							return get({ "confirmDelete" })
						end,
						set = function(_, v)
							set({ "confirmDelete" }, v)
						end,
					},
					reset = {
						type = "execute",
						order = 8,
						name = L["Reset window position"],
						func = function()
							UI.ResetPosition()
						end,
					},
				},
			},
			tracking = {
				type = "group",
				inline = true,
				order = 20,
				name = L["Progress tracking"],
				args = {
					enabled = {
						type = "toggle",
						order = 1,
						name = L["Track boss kills and runs"],
						get = function()
							return get({ "tracker", "enabled" })
						end,
						set = function(_, v)
							set({ "tracker", "enabled" }, v)
						end,
					},
					announce = {
						type = "toggle",
						order = 2,
						name = L["Say in chat when a planned boss dies (only you see it)"],
						width = "double",
						get = function()
							return get({ "tracker", "announceKills" })
						end,
						set = function(_, v)
							set({ "tracker", "announceKills" }, v)
						end,
					},
					record = {
						type = "toggle",
						order = 3,
						name = L["Record my runs"],
						desc = L["Records pulls (time, enemies, elites, deaths), boss kills and wipes in dungeons. No positions: the game hides them. Last 20 runs kept."],
						width = "double",
						get = function()
							return ns.Recorder.Enabled()
						end,
						set = function(_, v)
							ns.Recorder.SetEnabled(v)
						end,
					},
					clearRuns = {
						type = "execute",
						order = 4,
						name = L["Clear all recorded runs"],
						confirm = true,
						confirmText = L["Remove every recorded run of this character? This cannot be undone."],
						func = function()
							ns.Recorder.ClearHistory()
						end,
					},
				},
			},
			providers = {
				type = "group",
				inline = true,
				order = 25,
				name = L["Data from other addons"],
				args = (function()
					local args = {
						about = {
							type = "description",
							order = 0,
							name = L["Read from addons you have installed, in your game only; nothing is copied. Each source is named where its data shows."],
						},
					}
					for i, a in ipairs(ns.Providers.list) do
						args[a.id] = {
							type = "toggle",
							order = i,
							width = "double",
							name = string.format(L["Use %s"], a.title),
							desc = a.internals and L["Reads that addon's internal tables; an update of it may switch this off until Dungeon Planner is updated."]
								or L["Uses that addon's public interface."],
							get = function()
								return ns.Providers.Enabled(a.id)
							end,
							set = function(_, v)
								ns.Providers.SetEnabled(a.id, v)
							end,
						}
					end
					-- Floors drawn from the game's minimap pictures (Data/MinimapArt.lua) can show another addon's drawn
					-- map instead.
					args.preferProviderMaps = {
						type = "toggle",
						order = #ns.Providers.list + 1,
						width = "full",
						name = L["Prefer drawn maps from Dungeon Journal / Forever Dungeon Routes when installed"],
						desc = L["Without this, floors that have no map in the game are drawn from the game's own minimap pictures."],
						get = function()
							return ns.db.settings.preferProviderMaps == true
						end,
						set = function(_, v)
							ns.db.settings.preferProviderMaps = v and true or false
							ns.Providers.epoch = ns.Providers.epoch + 1
							ns:Fire("PROVIDERS_CHANGED", "maps")
						end,
					}
					return args
				end)(),
			},
			sharing = {
				type = "group",
				inline = true,
				order = 30,
				name = L["Sharing"],
				args = {
					acceptFrom = {
						type = "select",
						order = 1,
						name = L["Accept plan offers from"],
						values = {
							nobody = L["Nobody"],
							group = L["My group"],
							groupGuild = L["My group and guild"],
							anyone = L["Anyone"],
						},
						get = function()
							return get({ "share", "acceptFrom" })
						end,
						set = function(_, v)
							set({ "share", "acceptFrom" }, v)
						end,
					},
					announce = {
						type = "toggle",
						order = 2,
						name = L["Tell my group I use Dungeon Planner"],
						width = "double",
						get = function()
							return get({ "share", "announce" })
						end,
						set = function(_, v)
							set({ "share", "announce" }, v)
						end,
					},
				},
			},
			notes = {
				type = "group",
				inline = true,
				order = 35,
				name = L["Raid pages"],
				args = {
					autoShow = {
						type = "toggle",
						order = 1,
						name = L["Show the boss's page when its fight starts"],
						width = "double",
						get = function()
							return get({ "notes", "autoShow" })
						end,
						set = function(_, v)
							set({ "notes", "autoShow" }, v)
						end,
					},
					hideInCombat = {
						type = "toggle",
						order = 2,
						name = L["Hide the Notes window in combat"],
						width = "double",
						get = function()
							return get({ "notes", "hideInCombat" })
						end,
						set = function(_, v)
							set({ "notes", "hideInCombat" }, v)
						end,
					},
					acceptFrom = {
						type = "select",
						order = 3,
						name = L["Accept pages from"],
						values = {
							leaders = L["The group's leader and raid assistants"],
							group = L["Anyone in my group"],
							nobody = L["Nobody"],
						},
						get = function()
							return get({ "notes", "acceptFrom" })
						end,
						set = function(_, v)
							set({ "notes", "acceptFrom" }, v)
						end,
					},
					toggle = {
						type = "execute",
						order = 4,
						name = L["Show or hide the Notes window"],
						func = function()
							ns.NotesFrame.Toggle()
						end,
					},
				},
			},
			advanced = {
				type = "group",
				inline = true,
				order = 40,
				name = L["Troubleshooting"],
				args = {
					debug = {
						type = "toggle",
						order = 1,
						name = L["Debug messages"],
						get = function()
							return get({ "debug" })
						end,
						set = function(_, v)
							set({ "debug" }, v)
						end,
					},
					selftest = {
						type = "execute",
						order = 2,
						name = L["Run self-test (/dp debug)"],
						func = function()
							ns.Slash.Debug()
						end,
					},
				},
			},
		},
	}
end

function UI.InitSettings()
	local AceConfig = LibStub("AceConfig-3.0", true)
	local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
	if not (AceConfig and AceConfigDialog) then
		return false
	end
	AceConfig:RegisterOptionsTable(APP, options)
	local ok, _, id = pcall(AceConfigDialog.AddToBlizOptions, AceConfigDialog, APP, ns.title)
	if ok then
		categoryID = id
	end
	local AceDBOptions = LibStub("AceDBOptions-3.0", true)
	if AceDBOptions and ns.adb then
		AceConfig:RegisterOptionsTable(APP .. "_Profiles", AceDBOptions:GetOptionsTable(ns.adb))
		pcall(AceConfigDialog.AddToBlizOptions, AceConfigDialog, APP .. "_Profiles", L["Profiles"], ns.title)
	end
	return true
end

-- Opening the game's Settings panel is not allowed in combat on recent clients: wait for combat to end.
function UI.OpenSettings()
	ns:RunOutOfCombat(function()
		if categoryID and Settings and Settings.OpenToCategory then
			if pcall(Settings.OpenToCategory, categoryID) then
				return
			end
		end
		local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
		if AceConfigDialog then
			AceConfigDialog:Open(APP)
		end
	end)
end
