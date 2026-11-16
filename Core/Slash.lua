-- Slash commands: /dp and /dplan (neither is used by any installed addon: docs/COMPATIBILITY.md). AceConsole registers
-- them. /dp debug prints the API availability report and runs the in-game self-tests.

local _, ns = ...
local Slash = ns:NewModule("Slash")
local L = ns.L

local function line(ok, text)
	return (ok and "|cff3fb27fOK|r " or "|cffe5534bmissing|r ") .. text
end

-- One line: how many recommended plan floors draw the game's map art, the old map tiles, the minimap pictures,
-- another addon's map or the grid, and which are on the grid. /dp scan records every floor (mapSources).
function Slash.MapSources()
	local ok, counts, grid = pcall(ns.MinimapArt.Summary)
	if not ok then
		print("    " .. line(false, "maps: " .. tostring(counts)))
		return
	end
	print("  " .. string.format(L["Floor maps: %d game map, %d old map tiles, %d minimap pictures, %d other addons, %d grid."],
		counts.map, counts.tiles, counts.minimap, counts.provider, counts.grid)
		.. (#grid > 0 and (" " .. L["Grid:"] .. " " .. table.concat(grid, ", ")) or ""))
end

function Slash.Debug()
	local info = ns.Compat.ClientInfo()
	ns:Print(string.format("%s %s | client %s (%s) toc %s | project %s%s | locale %s | UI language %s | font %s",
		ns.title, ns.version, tostring(info.version), tostring(info.build), tostring(info.toc), tostring(info.project),
		info.isForever and " (Forever)" or "", tostring(info.locale), tostring(ns.activeLocale),
		tostring(ns.Style.fontFile)))
	local missing = 0
	for _, row in ipairs(ns.Compat.Report()) do
		if not row.ok then
			missing = missing + 1
			print("  " .. line(false, row.name .. " (" .. row.path .. ") - " .. L["affects:"] .. " " .. row.degrades))
		end
	end
	print("  " .. string.format(L["%d API checks missing."], missing))
	for _, r in ipairs(ns.Compat.SelfTest()) do
		print("  " .. line(r.ok, r.name .. (r.ok and "" or (": " .. r.detail))))
	end
	local s = ns.Integrations.status
	print("  " .. string.format("Integrations: launcher %s, OpenMap %s, Dungeon Journal %s, WoW Po Polsku %s, DBM %s, BigWigs %s",
		tostring(s.launcher), tostring(s.openMap), tostring(s.dungeonJournal), tostring(s.polish),
		tostring(ns.Tracker.sources.dbm), tostring(ns.Tracker.sources.bigwigs)))
	-- Data providers (Data/Providers.lua): every adapter, active or not, with what it found.
	for _, row in ipairs(ns.Providers.Report()) do
		local counts = {}
		for _, k in ipairs(ns.Util.SortedKeys(row.counts or {})) do
			counts[#counts + 1] = k .. " " .. tostring(row.counts[k])
		end
		local status = row.active and "|cff3fb27factive|r" or "|cffa1a1a1inactive|r"
		local why = not row.enabled and L["switched off"]
			or row.failed and ("|cffe5534b" .. L["failed:"] .. "|r " .. ns.Providers.ShortError(row.failed))
			or (not row.active and row.loaded == false) and L["not installed"] or (not row.active) and L["data not found"] or nil
		print("  " .. string.format("%s: %s (%s%s%s)%s", L["Source"], row.title, status, row.version and (" " .. row.version) or "",
			row.internals and (", " .. L["internal tables"]) or (", " .. L["public API"]), why and (" - " .. why) or "")
			.. (#counts > 0 and (" " .. table.concat(counts, ", ")) or ""))
	end
	-- The run recorder (Tracker/Recorder.lua).
	local rec = ns.Recorder
	local store = rec.Store()
	local runs = 0
	for _, list in pairs(store and store.runs or {}) do
		runs = runs + #list
	end
	print("  " .. string.format(L["Run recorder: %s, %d runs saved, nameplates %s, unit names %s."],
		rec.Enabled() and L["on"] or L["off"], runs, tostring(rec.api.namePlates == nil and "?" or rec.api.namePlates),
		tostring(rec.api.names or "?")))
	-- Blizzard art the window draws (UI/Art.lua): atlases and files this client lacks, and frame templates that failed.
	local missingArt = {}
	for _, row in ipairs(ns.Art.Report()) do
		if row.atlas and row.atlasOk == false then
			missingArt[#missingArt + 1] = row.key .. " (atlas " .. row.atlas .. ", "
				.. (row.file and L["using the file"] or L["drawn instead"]) .. ")"
		end
		if row.file and row.fileOk == false then
			missingArt[#missingArt + 1] = row.key .. " (" .. tostring(row.file) .. ")"
		end
	end
	for template in pairs(ns.Art.missingTemplates) do
		missingArt[#missingArt + 1] = L["template"] .. " " .. template
	end
	print("  " .. string.format(L["Art: %d missing."], #missingArt) .. (#missingArt > 0 and (" " .. table.concat(missingArt, "; ")) or ""))
	-- The game's window parts (UI/Art.lua, Native pieces): each missing one is drawn by Dungeon Planner instead.
	local native, have, lacking = ns.Art.NativeReport(), 0, {}
	for _, row in ipairs(native) do
		if row.ok then
			have = have + 1
		else
			lacking[#lacking + 1] = row.name .. (row.ok == nil and " (?)" or "")
		end
	end
	print("  " .. string.format(L["Window parts from the game: %d of %d."], have, #native)
		.. (#lacking > 0 and (" " .. L["Drawn instead:"] .. " " .. table.concat(lacking, ", ")) or ""))
	if type(GetFileIDFromPath) ~= "function" then
		print("  " .. L["Art files cannot be checked on this client (no GetFileIDFromPath); missing files show as empty icons."])
	end
	-- The Adventure Guide as the resolver sees it, and how many recommended plans it matched.
	local journal = ns.Journal.GetAll()
	local scan = ns.Journal.lastScan or { tiers = 0, instances = #journal.list, errors = {} }
	local matched = 0
	for _, plan in ipairs(ns.Bundled.All()) do
		if ns.Journal.ForPlan(plan) then
			matched = matched + 1
		end
	end
	print("  " .. string.format(L["Adventure Guide: %d tiers, %d instances; %d of %d recommended plans matched; loot %s."],
		scan.tiers or 0, #journal.list, matched, ns.Bundled.Count(),
		ns.Loot.Available() and L["available"] or L["not available"]))
	for i, err in ipairs(scan.errors or {}) do
		if i > 5 then
			break
		end
		print("    " .. line(false, tostring(err)))
	end
	-- Recommended plans that ship with the addon, and where each floor's map comes from (Data/MinimapArt.lua).
	print("  " .. string.format(L["Recommended plans: %d."], ns.Bundled.Count()))
	Slash.MapSources()
	for i, problem in ipairs(ns.Bundled.problems) do
		if i > 10 then
			break
		end
		print("    " .. line(false, problem))
	end
	if ns.db and #ns.db.quarantine > 0 then
		print("  " .. ns.Plural(#ns.db.quarantine,
			L["%d unreadable plan kept in DungeonPlannerDB.global.quarantine.|%d unreadable plans kept in DungeonPlannerDB.global.quarantine."]))
	end
	-- Polish letters: would a Polish UI render? The letters are drawn in the face the Polish chain picks (UI/Fonts.lua:
	-- WoW Po Polsku's Friz Quadrata while that addon is enabled, else the bundled Alegreya Sans, else its cleaned copy,
	-- else the game face), whatever the language is now; the current UI face is named too. Chat uses another font, so
	-- the dialog is the real test. Below it, the font test draws every face of the chain and looks at them again a few
	-- seconds later (the result goes to chat).
	local lower = "\196\133\196\135\196\153\197\130\197\132\195\179\197\155\197\186\197\188"
	local upper = "\196\132\196\134\196\152\197\129\197\131\195\147\197\154\197\185\197\187"
	local function yesNo(v)
		return v == nil and "?" or tostring(v)
	end
	local S = ns.Style
	local polishFile, polishKind = S.PolishFace()
	local polishName = string.format("%s, %s", S.FontShortName(polishFile),
		polishKind == "wowpopolsku" and L["WoW Po Polsku's Friz Quadrata"]
		or polishKind == "bundled" and L["bundled with Dungeon Planner"] or L["the game font, without Polish letters"])
	local face = S.fontFile
	print("  " .. L["Polish letters test:"] .. " " .. lower .. " " .. upper)
	print("    " .. string.format(L["A Polish UI would use: %s (%s)"], polishName, yesNo(S.CanLoadFont(polishFile))))
	print("    " .. string.format(L["UI font: %s (%s)"], S.FontShortName(face), yesNo(S.CanLoadFont(face))))
	local faces = {}
	for _, file in ipairs(S.POLISH_FACES) do
		faces[#faces + 1] = S.FontShortName(file) .. "=" .. yesNo(S.CanLoadFont(file))
	end
	local polishAddon = ns.Integrations.AddonState and ns.Integrations.AddonState("WoWPoPolskuForever") or "unknown"
	print("    " .. L["Polish faces:"] .. " " .. table.concat(faces, " ") .. " (WoW Po Polsku: " .. polishAddon .. ")")
	local notes = {}
	if polishAddon == "disabled" then
		notes[#notes + 1] = L["WoW Po Polsku is disabled, so its Friz Quadrata with Polish letters cannot be used."]
	end
	if polishKind == "game" then
		notes[#notes + 1] = line(false, L["No font with Polish letters could be loaded; text uses the game font (boxes for some letters)."])
	end
	notes[#notes + 1] = L["The font test below draws each face; its result follows in chat in a few seconds."]
	for _, note in ipairs(notes) do
		print("    " .. note)
	end
	if ns.Widgets and ns.Widgets.ShowDialog then
		ns.Widgets.ShowDialog({
			title = L["Polish letters test:"],
			width = 560, -- wide enough that the face's name is not split over two lines
			-- Drawn in the bundled face even when no face loads, so the eye can check what the probe says.
			sample = { text = lower .. "  " .. upper, font = polishKind == "game" and S.BUNDLED_FACE or polishFile },
			text = string.format(L["A Polish UI would use: %s (%s)"], polishName, yesNo(S.CanLoadFont(polishFile)))
				.. "\n" .. string.format(L["UI font: %s (%s)"], S.FontShortName(face), yesNo(S.CanLoadFont(face)))
				.. "\n" .. table.concat(notes, "\n"),
			buttons = { { L["Close"] } },
		})
	end
	S.RunFontTest({ show = true, print = true })
end

local HELP = {
	"/dp - open or close the planner",
	"/dp map - open the map of the selected plan",
	"/dp next | prev - next or previous pull (in run mode: step)",
	"/dp run - open or close run mode",
	"/dp notes - open or close the Notes window (raid pages)",
	"/dp share - offer the selected plan to your group",
	"/dp import - open the Share tab",
	"/dp settings - options",
	"/dp minimap - show or hide the minimap button",
	"/dp reset - reset the window position",
	"/dp debug - API report and self-test",
	"/dp mapid - print the current map ID",
	"/dp scan - save what the Adventure Guide, Group Finder, maps and game files return into DungeonPlannerDB.diagnostics (written on /reload)",
	"/dp scan clear - remove those diagnostics",
	"/dp shots - screenshot every view of the window (Escape stops; list in DungeonPlannerDB.shots)",
}

-- /dp scan: the resolver's view of the Adventure Guide, saved for offline reading. On demand only; out of combat.
function Slash.Scan(arg)
	local sv = rawget(_G, "DungeonPlannerDB")
	if type(sv) ~= "table" then
		return
	end
	if arg == "clear" then
		sv.diagnostics = nil
		ns:Print(L["Diagnostics removed."])
		return
	end
	if ns.Journal.IsBlizzardJournalOpen() then
		ns:Print(L["Close the Adventure Guide first, then run /dp scan again."])
		return
	end
	ns:RunOutOfCombat(function()
		local info = ns.Compat.ClientInfo()
		local data = ns.Diagnostics.Collect()
		data.at = date and date("%Y-%m-%d %H:%M") or ""
		data.addon = ns.version
		data.client = string.format("%s (%s) toc %s, locale %s", tostring(info.version), tostring(info.build),
			tostring(info.toc), tostring(info.locale))
		sv.diagnostics = data
		ns:Print(string.format(L["Scanned: %d journal instances, %d Group Finder entries, %d maps. Wait 3 s, then /reload to save (/dp scan clear removes)."],
			#data.instances, data.finder and data.finder.count or 0, data.maps and ns.Util.Count(data.maps.byId) or 0))
	end)
end

function Slash.Handle(input)
	local cmd = (input or ""):match("^%s*(%S*)"):lower()
	local A = ns.Actions
	if cmd == "" then
		A.Toggle()
	elseif cmd == "map" then
		A.OpenMap()
	elseif cmd == "run" then
		ns.RunMode.Toggle()
	elseif cmd == "notes" then
		ns.NotesFrame.Toggle()
	elseif cmd == "next" then
		A.StepPull(1)
	elseif cmd == "prev" or cmd == "previous" then
		A.StepPull(-1)
	elseif cmd == "share" then
		A.ShareWithGroup()
	elseif cmd == "import" or cmd == "export" then
		ns.UI.Show("share")
	elseif cmd == "settings" or cmd == "options" or cmd == "config" then
		ns.UI.OpenSettings()
	elseif cmd == "minimap" then
		ns.Integrations.SetMinimapShown(ns.db.minimap.hide)
	elseif cmd == "reset" then
		ns.UI.ResetPosition()
	elseif cmd == "debug" then
		Slash.Debug()
	elseif cmd == "scan" then
		Slash.Scan((input or ""):match("^%s*%S+%s+(%S+)"))
	elseif cmd == "shots" then
		ns.Shots.Run((input or ""):match("^%s*%S+%s+(%S+)"))
	elseif cmd == "mapid" then
		local cur = ns.Instances.Current()
		ns:Print(string.format("uiMapID %s, journal instance %s, %s", tostring(cur.uiMapID), tostring(cur.ejInstanceID),
			tostring(cur.name)))
	else
		ns:Print(L["Commands:"])
		for _, text in ipairs(HELP) do
			print("  " .. text)
		end
	end
end

function Slash.Init()
	if ns.addon and ns.addon.RegisterChatCommand then
		ns.addon:RegisterChatCommand("dp", Slash.Handle)
		ns.addon:RegisterChatCommand("dplan", Slash.Handle)
	end
end
