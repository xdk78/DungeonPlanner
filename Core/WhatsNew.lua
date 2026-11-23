-- "What's new" and the first-run welcome: what to show and when. The window is UI/NewsFrame.lua.
--
-- The highlights are a small table (ENTRIES) kept in step with CHANGELOG.md: a test (tests/test_news.lua) fails when the
-- newest released version in the changelog has no entry, or when the changelog's [Unreleased] section has entries and
-- no entry is newer than the last release. Strings go through L, so each language has its own text (Locales/plPL.lua).
--
-- When it shows (Decide, pure): the saved version (global.news.seen) is compared with the running one.
--   * nothing saved and this is a fresh install (no saved data existed before this session, or an earlier session of
--     it has not shown its welcome yet, global.news.firstRun): the welcome;
--   * nothing saved on an install that had data (0.1.0 saved nothing): the entry for this version;
--   * a different, older version saved: the entry for this version, if there is one;
--   * the same or a newer version saved (a downgrade), or a development checkout ("dev"): nothing.
-- The version is saved once the card has been shown (Show returned true), or at once when the version has no entry and
-- there is nothing to show; until then the card stays pending for the next quiet moment.

local _, ns = ...
local WhatsNew = ns:NewModule("WhatsNew")
local L = ns.L

-- "v0.2.0", "0.2.0-3-gabc" -> "0.2.0"; nil for anything else (a checkout reports "dev").
function WhatsNew.Normalize(version)
	return type(version) == "string" and version:match("^v?(%d+%.%d+%.%d+)") or nil
end

-- Newest first by the entry's version; each entry is a function so the text follows the language chosen at runtime.
-- items = { { heading, text, settingsGroup? } } (the card's Open Settings button goes to the first group named)
local ENTRIES = {
	["0.2.2"] = function()
		return {
			title = L["What's new in 0.2.2"],
			items = {
				{ L["Lists start at the top"],
					L["Another plan opens its steps, gear and other lists at the top; a refresh keeps your place."] },
			},
		}
	end,
	["0.2.1"] = function()
		return {
			title = L["What's new in 0.2.1"],
			items = {
				{ L["Bosses on the route"],
					L["Where another addon's map puts the bosses elsewhere than the plan, the map keeps the plan's bosses at its route's stops."] },
				{ L["Blocked addon messages"],
					L["Sharing and group sync say when the game blocks or refuses addon messages, instead of waiting for answers that cannot come."] },
				{ L["Runs per wing"],
					L["In dungeons with wings, each wing keeps its own runs and best times."] },
			},
		}
	end,
	["0.2.0"] = function()
		return {
			title = L["What's new in 0.2.0"],
			items = {
				{ L["Six languages"],
					L["German, Spanish, French and Russian join English and Polish. Automatic follows your game's language."] },
				{ L["Group sync in run mode"],
					L["The leader clicks Lead this run; members with the same plan follow along, and one without it asks for it in one click."] },
				{ L["Prep and Getting there"],
					L["Prep lists quests, keys and group levels. Getting there shows the way to the entrance and hands it to Polestar, Shortest Path Forever or TomTom."] },
				{ L["Every floor on the map"],
					L["A floor switcher in the map's corner; Shift + mouse wheel changes floor too."] },
				{ L["Clearer routes"],
					L["Snap to corridors, colour along the route, clearer arrows, the hovered leg highlighted, and a Routes group in Settings."], "routes" },
				{ L["Your group in the plan"],
					L["The party seats fill from your group, and the Gear class and slot filters now change the drop list."] },
				{ L["Report a problem"],
					L["/dp report gathers version, plan and error details into a text for a GitHub issue, without your character, realm, guild or group."] },
			},
		}
	end,
	["0.1.0"] = function()
		return {
			title = L["What's new in 0.1.0"],
			items = {
				{ L["The war table"],
					L["A dungeon map with the plan's steps beside it, and the sections (Map, Bosses, Pulls, Party, Gear, Runs, Share, Notes) as tabs."] },
				{ L["43 recommended plans"],
					L["Boss order, routes, pulls and strategies for the classic dungeons and raids and Forever's new dungeons. Make an editable copy to change one."] },
				{ L["Maps for the new dungeons"],
					L["Santiago Reyes' hand-drawn maps and the game's minimap pictures cover Forever's new dungeons without other addons."] },
			},
		}
	end,
}

function WhatsNew.Versions()
	local out = {}
	for version in pairs(ENTRIES) do
		out[#out + 1] = version
	end
	table.sort(out, function(a, b)
		return WhatsNew.Compare(a, b) > 0
	end)
	return out
end

-- 1, 0, -1 for two normalized versions.
function WhatsNew.Compare(a, b)
	local pa, pb = { a:match("^(%d+)%.(%d+)%.(%d+)") }, { b:match("^(%d+)%.(%d+)%.(%d+)") }
	for i = 1, 3 do
		local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
		if x ~= y then
			return x > y and 1 or -1
		end
	end
	return 0
end

-- { title, items } in the current language, or nil when the version has no entry.
function WhatsNew.Entry(version)
	local make = ENTRIES[WhatsNew.Normalize(version) or ""]
	return make and make() or nil
end

-- The first-run welcome: what the addon is, how to open it and run mode, three tips.
function WhatsNew.Welcome()
	return {
		title = L["Welcome to Dungeon Planner"],
		intro = L["Plan a dungeon or raid run on its map: the route, the pulls, the bosses, who stands where, and share it with your group."],
		items = {
			{ L["Open it"], L["Type /dp, press the minimap button, or pick it from the addon list. Choose a dungeon, then a plan."] },
			{ L["Run mode"], L["/dp run opens a small window that follows your plan step by step; /dp next and /dp prev move through it."] },
			{ L["Tip: recommended plans"], L["Every dungeon has a recommended plan. Make an editable copy to change it; your own plans are never touched by updates."] },
			{ L["Tip: share"], L["The Share section sends a plan to your group or turns it into a text string for Discord."] },
			{ L["Tip: help"], L["/dp lists every command. If something breaks, /dp report builds a text you can paste into an issue."] },
		},
	}
end

-- Pure: "welcome", "news" or nil. seen: the saved version (nil if none), current: the running version, fresh: no data
-- existed before this session, hasEntry: the current version has highlights.
function WhatsNew.Decide(seen, current, fresh, hasEntry)
	current = WhatsNew.Normalize(current)
	if not current then
		return nil
	end
	if seen == current then
		return nil
	end
	if seen and WhatsNew.Compare(seen, current) > 0 then
		return nil -- a downgrade: the card for a newer version was shown already
	end
	if seen == nil and fresh then
		return "welcome"
	end
	return hasEntry and "news" or nil
end

-- The saved state: DungeonPlannerDB.global.news = { seen = "0.2.0" } (additive: older versions ignore it).
local function store()
	local adb = ns.adb
	if adb and type(adb.global) == "table" and not ns.DB.IsReadOnly() then
		if type(adb.global.news) ~= "table" then
			adb.global.news = {}
		end
		return adb.global.news
	end
	return nil
end

-- Our own windows: the card never opens over one of them.
local WINDOWS = { "DungeonPlannerMainFrame", "DungeonPlannerRunFrame", "DungeonPlannerNotesFrame", "DungeonPlannerReportFrame",
	"DungeonPlannerDialog" }

local function called(name)
	local fn = rawget(_G, name)
	if type(fn) ~= "function" then
		return false
	end
	local ok, value = pcall(fn)
	return ok and value and true or false
end

-- A quiet moment: true, or false and why. Not in combat, not in a cinematic, not inside an instance (a run is no time
-- for a card), not over another of our windows.
function WhatsNew.Quiet()
	if InCombatLockdown and InCombatLockdown() then
		return false, "combat"
	end
	if called("IsInInstance") or called("InCinematic") or called("IsInCinematicScene") then
		return false, "instance or cinematic"
	end
	for _, name in ipairs(WINDOWS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.IsShown and f:IsShown() then
			return false, name
		end
	end
	return true
end

local pending, pendingVersion -- decided, waiting for a quiet moment

-- Show the pending card if the moment is quiet; the version is saved only then, so a reload before it shows leaves it
-- pending. Returns true when shown.
function WhatsNew.TryShow()
	if not pending or not ns.NewsFrame then
		return false
	end
	if not WhatsNew.Quiet() then
		return false
	end
	local kind, version = pending, pendingVersion
	-- Saved only once the card really showed; if it could not be shown it stays pending for the next quiet moment.
	if not ns.NewsFrame.Show(kind) then
		return false
	end
	pending = nil
	local saved = store()
	if saved then
		saved.firstRun = nil
		if version then
			saved.seen = version
		end
	end
	return true
end

-- At login, a few seconds after the first frame: decide; show now if quiet, else when the matching events say it is.
-- Returns what was decided.
function WhatsNew.Check()
	local saved = store()
	if not saved then
		return nil
	end
	local current = WhatsNew.Normalize(ns.version)
	local seen = WhatsNew.Normalize(saved.seen)
	-- A first install stays a first install until its welcome was shown, even across sessions (a first session spent in an
	-- instance, or ended before the card showed).
	if seen == nil and ns.freshInstall then
		saved.firstRun = true
	end
	local fresh = ns.freshInstall or saved.firstRun == true
	local kind = WhatsNew.Decide(seen, current, fresh, current and WhatsNew.Entry(current) ~= nil)
	if not kind then
		if current and (seen == nil or WhatsNew.Compare(seen, current) < 0) then
			saved.seen = current -- nothing to show for this version: remembered all the same (never lowered on a downgrade)
		end
		return nil
	end
	pending, pendingVersion = kind, current
	WhatsNew.TryShow()
	return kind
end

function WhatsNew.IsPending()
	return pending
end

-- /dp new: the highlights of this version (the newest entry on a development checkout).
function WhatsNew.Open()
	local current = WhatsNew.Normalize(ns.version) or WhatsNew.Versions()[1]
	ns.NewsFrame.Show("news", current)
end

-- A few seconds after login; then, while a card waits, whenever combat, a cinematic or a loading screen ends.
function WhatsNew.Init()
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CINEMATIC_STOP" }) do
		ns:RegisterEvent(event, function()
			if pending then
				-- After the event's own work is done (the instance flag, the windows, are right a moment later).
				if C_Timer and C_Timer.After then
					C_Timer.After(3, WhatsNew.TryShow)
				else
					WhatsNew.TryShow()
				end
			end
		end)
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(5, function()
			ns.SafeCall(WhatsNew.Check)
		end)
	end
end
