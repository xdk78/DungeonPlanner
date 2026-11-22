-- "What's new" and the first-run welcome: what to show and when. The window is UI/NewsFrame.lua.
--
-- The highlights are a small table (ENTRIES) kept in step with CHANGELOG.md: a test (tests/test_news.lua) fails when the
-- newest released version in the changelog has no entry, or when the changelog has an [Unreleased] section and no entry
-- is newer than the last release. Strings go through L, so each language has its own text (Locales/plPL.lua).
--
-- When it shows (Decide, pure): the saved version (global.news.seen, written once the card was shown or skipped) is
-- compared with the running one.
--   * nothing saved and this is a fresh install (no saved data existed before this session): the welcome;
--   * nothing saved on an install that had data (0.1.0 saved nothing): the entry for this version;
--   * a different version saved: the entry for this version, if there is one;
--   * the same version, or a development checkout ("dev"): nothing.
-- The version is saved as soon as the decision is made, so the card shows once.

local _, ns = ...
local WhatsNew = ns:NewModule("WhatsNew")
local L = ns.L

-- "v0.2.0", "0.2.0-3-gabc" -> "0.2.0"; nil for anything else (a checkout reports "dev").
function WhatsNew.Normalize(version)
	return type(version) == "string" and version:match("^v?(%d+%.%d+%.%d+)") or nil
end

-- Newest first by the entry's version; each entry is a function so the text follows the language chosen at runtime.
-- items = { { heading, text } }
local ENTRIES = {
	["0.2.0"] = function()
		return {
			title = L["What's new in 0.2.0"],
			items = {
				{ L["Report a problem"],
					L["/dp report gathers version, plan and error details into a text for a GitHub issue, without your character, realm, guild or group."] },
				{ L["What's new"],
					L["This card appears once after an update, and /dp new shows it again."] },
				{ L["Performance probe"],
					L["/dp perf start times the addon's handlers and redraws and shows its memory use; /dp perf stop removes it. It is off unless you start it."] },
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

-- At login, a few seconds after the first frame: decide, remember, and show. Returns what it showed.
function WhatsNew.Check()
	local saved = store()
	if not saved then
		return nil
	end
	local current = WhatsNew.Normalize(ns.version)
	local seen = WhatsNew.Normalize(saved.seen)
	local kind = WhatsNew.Decide(seen, current, ns.freshInstall, current and WhatsNew.Entry(current) ~= nil)
	if current then
		saved.seen = current
	end
	if kind and ns.NewsFrame then
		ns:RunOutOfCombat(function()
			ns.NewsFrame.Show(kind)
		end)
	end
	return kind
end

-- /dp new: the highlights of this version (the newest entry on a development checkout).
function WhatsNew.Open()
	local current = WhatsNew.Normalize(ns.version) or WhatsNew.Versions()[1]
	ns.NewsFrame.Show("news", current)
end

function WhatsNew.Init()
	if C_Timer and C_Timer.After then
		C_Timer.After(5, function()
			ns.SafeCall(WhatsNew.Check)
		end)
	end
end
