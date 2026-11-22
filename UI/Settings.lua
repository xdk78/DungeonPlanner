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

local function languageValues()
	local values, order = { auto = L["Automatic"] }, { "auto" }
	for _, entry in ipairs(ns.LOCALE_LIST) do
		values[entry[1]] = entry[2]
		order[#order + 1] = entry[1]
	end
	return values, order
end

local scaleValues, scaleSorting = {}, {}
for pct = 70, 140, 5 do
	scaleValues[tostring(pct)] = pct .. "%"
	scaleSorting[#scaleSorting + 1] = tostring(pct)
end

-- Routes: how route lines and their direction arrows look on the map (settings.routes; UI/MapRoutes.lua).
-- Every change redraws the map and run mode at once.
local function routesGroup()
	-- The palette's colours in order (UI/Style.lua palette; the colour-blind set keeps the same slots).
	local COLOR_NAMES = { L["Red"], L["Blue"], L["Green"], L["Violet"], L["Orange"], L["Teal"], L["Yellow"], L["White"] }
	local function routeGet(key)
		return function()
			return ns.db.settings.routes[key]
		end
	end
	local function routeSet(key, convert)
		return function(_, v)
			ns.db.settings.routes[key] = convert and convert(v) or v
			UI.ApplyColors()
		end
	end
	-- The arrows' own options mean nothing while the arrows are off.
	local function arrowsOff()
		return ns.db.settings.routes.arrows == "off"
	end
	local opacityValues, opacitySorting = {}, {}
	for pct = 40, 100, 10 do
		opacityValues[tostring(pct)] = pct .. "%"
		opacitySorting[#opacitySorting + 1] = tostring(pct)
	end
	local colorSorting = { "0" }
	for i = 1, #COLOR_NAMES do
		colorSorting[#colorSorting + 1] = tostring(i)
	end
	local function colorValues()
		local values = { ["0"] = L["Each route's own"] }
		for i, name in ipairs(COLOR_NAMES) do
			local r, g, b = ns.Style.PaletteColor(i)
			values[tostring(i)] = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
		end
		return values
	end
	return {
		type = "group",
		inline = true,
		order = 15,
		name = L["Routes"],
		args = {
			width = {
				type = "select",
				order = 1,
				name = L["Line width"],
				values = { thin = L["Thin"], medium = L["Medium"], thick = L["Thick"] },
				sorting = { "thin", "medium", "thick" },
				get = routeGet("width"),
				set = routeSet("width"),
			},
			opacity = {
				type = "select",
				order = 2,
				name = L["Line opacity"],
				values = opacityValues,
				sorting = opacitySorting,
				get = function()
					local pct = math.floor((tonumber(ns.db.settings.routes.opacity) or 1) * 10 + 0.5) * 10
					return tostring(math.max(40, math.min(100, pct)))
				end,
				set = routeSet("opacity", function(v)
					return (tonumber(v) or 100) / 100
				end),
			},
			color = {
				type = "select",
				order = 3,
				name = L["Route colour"],
				desc = L["Each route's own colour, or one colour for every route of a plan. Another addon's routes keep theirs."],
				values = colorValues,
				sorting = colorSorting,
				get = function()
					return tostring(ns.db.settings.routes.color or 0)
				end,
				set = routeSet("color", function(v)
					return tonumber(v) or 0
				end),
			},
			ramp = {
				type = "toggle",
				order = 3.5,
				name = L["Colour along the route"],
				desc = L["The line's colour shifts from the start of a route to its end, so you can tell which part comes first. Off: one colour."],
				get = routeGet("ramp"),
				set = routeSet("ramp"),
			},
			outline = {
				type = "toggle",
				order = 4,
				name = L["Dark outline"],
				desc = L["A dark edge around route lines and arrows, so they read on light map art."],
				get = routeGet("outline"),
				set = routeSet("outline"),
			},
			arrows = {
				type = "select",
				order = 5,
				name = L["Direction arrows"],
				desc = L["How many arrows show the direction along a route. They keep clear of stops, bends, pins, labels and places where a route crosses itself."],
				values = { off = L["Off"], few = L["Few"], normal = L["Normal"], many = L["Many"] },
				sorting = { "off", "few", "normal", "many" },
				get = routeGet("arrows"),
				set = routeSet("arrows"),
			},
			arrowSize = {
				type = "select",
				order = 6,
				name = L["Arrow size"],
				values = { small = L["Small"], medium = L["Standard"], large = L["Large"] },
				sorting = { "small", "medium", "large" },
				get = routeGet("arrowSize"),
				set = routeSet("arrowSize"),
				disabled = arrowsOff,
			},
			heads = {
				type = "toggle",
				order = 7,
				name = L["Arrowheads at stops"],
				desc = L["A larger arrowhead just before each numbered stop and at the route's end."],
				get = routeGet("heads"),
				set = routeSet("heads"),
				disabled = arrowsOff,
			},
			focusArrows = {
				type = "toggle",
				order = 8,
				width = "double",
				name = L["Arrows only on the focused step's leg"],
				desc = L["While a step is in focus, direction arrows show only on the part of the route that leads to it."],
				get = routeGet("focusArrows"),
				set = routeSet("focusArrows"),
				disabled = arrowsOff,
			},
			hover = {
				type = "toggle",
				order = 9,
				width = "double",
				name = L["Highlight the route under the pointer"],
				desc = L["The leg under the pointer, or of a step pointed at in the list, stands out with its arrows; the rest dims. So does run mode's current step."],
				get = routeGet("hover"),
				set = routeSet("hover"),
			},
		},
	}
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
						values = languageValues(),
						sorting = select(2, languageValues()),
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
					-- A list of steps rather than a slider: the slider's value box sat on its track in the game's skin.
					scale = {
						type = "select",
						order = 4,
						name = L["Window scale"],
						values = scaleValues,
						sorting = scaleSorting,
						get = function()
							local pct = math.floor((ns.db.settings.scale or 1) * 100 / 5 + 0.5) * 5
							return tostring(math.max(70, math.min(140, pct)))
						end,
						set = function(_, v)
							ns.db.settings.scale = (tonumber(v) or 100) / 100
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
					gameIcon = {
						type = "toggle",
						order = 5.5,
						name = L["Game map icon"],
						desc = L["The minimap button and the planner's window show the game's map icon instead of Dungeon Planner's own. The window changes after /reload."],
						get = function()
							return get({ "gameIcon" })
						end,
						set = function(_, v)
							set({ "gameIcon" }, v)
							ns.Integrations.RefreshLauncherIcon()
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
					-- Forever's new dungeons (Data/MinimapArt.lua Choose): drawn maps (Santiago Reyes' bundled ones,
					-- another addon's) or the game's own minimap pictures first.
					preferProviderMaps = {
						type = "toggle",
						order = 6.1,
						width = "full",
						name = L["Prefer drawn maps over the game's minimap pictures"],
						desc = L["Forever's new dungeons: Santiago Reyes' maps (they come with the addon), else another addon's. Off: the game's minimap pictures first."],
						get = function()
							return ns.MinimapArt.PreferProviders()
						end,
						set = function(_, v)
							ns.db.settings.preferProviderMaps = v and true or false
							ns.Providers.epoch = ns.Providers.epoch + 1
							ns:Fire("PROVIDERS_CHANGED", "maps")
						end,
					},
					mapColors = {
						type = "select",
						order = 6.2,
						name = L["Map colours"],
						desc = L["Floors drawn from the game's minimap pictures: parchment colours like the classic maps, or the minimap's own."],
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
					reyesCredit = {
						type = "description",
						order = 6.3,
						width = "full",
						name = string.format(L["Maps of Forever's new dungeons by Santiago Reyes (%s), used with his permission. Like them? Support the artist: %s"],
							ns.ReyesMaps.SITE, ns.ReyesMaps.DONATE),
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
						width = "double",
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
			routes = routesGroup(),
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
					-- Experimental (UI/OpenMapOverlay.lua): the plan on OpenMap's own dungeon map; off by default.
					args.openmapOverlay = {
						type = "toggle",
						order = #ns.Providers.list + 1,
						width = "full",
						name = L["Show plan on OpenMap's dungeon map (experimental)"],
						desc = L["Draws your plan's route, stops and markers on OpenMap's dungeon map. It uses parts of OpenMap that are not public: an update may stop it."],
						hidden = function()
							return ns.OpenMapOverlay == nil
						end,
						disabled = function()
							return ns.Compat.Gamepad() or (rawget(_G, "OpenMapAPI") == nil and rawget(_G, "OpenMap") == nil)
						end,
						get = function()
							return ns.OpenMapOverlay ~= nil and ns.OpenMapOverlay.IsEnabled()
						end,
						set = function(_, v)
							if ns.OpenMapOverlay then
								ns.OpenMapOverlay.SetEnabled(v)
							end
						end,
					}
					-- Supported addons that are not loaded, one line each (read when the panel is drawn).
					local BENEFITS = {
						dungeonJournal = L["drawn maps of Forever's new dungeons, boss portraits and loot"],
						foreverDungeonRoutes = L["a route layer on the map and drawn maps of Forever's new dungeons"],
						openMap = L["more drawn dungeon maps, and your plans on its dungeon cards"],
						needRoll = L["\"Open in NeedRoll\" in Gear"],
						questie = L["the dungeon's quests in Runs"],
						tomtom = L["\"Navigate\" in Prep sets TomTom's arrow"],
						polestar = L["\"Navigate\" in Prep hands the way to Polestar"],
						shortestPath = L["\"Navigate\" in Prep hands the way to Shortest Path Forever"],
					}
					args.missing = {
						type = "description",
						order = #ns.Providers.list + 2,
						width = "full",
						hidden = function()
							return #ns.Providers.Missing() == 0
						end,
						name = function()
							local lines = { L["Not installed (optional):"] }
							for _, a in ipairs(ns.Providers.Missing()) do
								lines[#lines + 1] = string.format("%s: %s", a.title, BENEFITS[a.id] or "")
							end
							return table.concat(lines, "\n")
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
					-- /dp entrances reset for players without slash commands (gamepad style).
					forgetEntrances = {
						type = "execute",
						order = 2.5,
						name = L["Forget learned entrances"],
						desc = L["Getting there uses the bundled entrances again."],
						func = function()
							ns:RunOutOfCombat(function()
								ns:Print(ns.Plural(ns.TravelMap.ForgetLearned(),
									L["Forgot %d learned entrance.|Forgot %d learned entrances."]))
							end)
						end,
					},
					report = {
						type = "execute",
						order = 3,
						name = L["Report a problem"],
						func = function()
							ns.Report.Open()
						end,
					},
					whatsnew = {
						type = "execute",
						order = 4,
						name = L["Show what's new"],
						func = function()
							ns.WhatsNew.Open()
						end,
					},
					-- When the gamepad style is detected wrongly (Core/Compat.lua Gamepad; read once at login).
					gamepad = {
						type = "select",
						order = 5,
						name = L["Gamepad interface style"],
						desc = L["Automatic follows the game. On: no slash commands; open the planner from the minimap button or a key binding. Takes effect after /reload."],
						values = { auto = L["Automatic"], on = L["On"], off = L["Off"] },
						sorting = { "auto", "on", "off" },
						get = function()
							local v = ns.db.settings.gamepad
							return (v == "on" or v == "off") and v or "auto"
						end,
						set = function(_, v)
							ns.db.settings.gamepad = v
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
-- group: an options group's key ("advanced" is Troubleshooting) to select once the page is open.
function UI.OpenSettings(group)
	ns:RunOutOfCombat(function()
		local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
		local function openGroup()
			if group and AceConfigDialog and AceConfigDialog.SelectGroup then
				pcall(AceConfigDialog.SelectGroup, AceConfigDialog, APP, group)
			end
		end
		if categoryID and Settings and Settings.OpenToCategory then
			if pcall(Settings.OpenToCategory, categoryID) then
				openGroup()
				return
			end
		end
		if AceConfigDialog then
			AceConfigDialog:Open(APP)
			openGroup()
		end
	end)
end
