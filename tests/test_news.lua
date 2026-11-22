-- "What's new" and the first-run welcome (Core/WhatsNew.lua, UI/NewsFrame.lua): the changelog and the highlights stay in
-- step, the decision of what to show is right for a fresh install, an update, the same version and a development
-- checkout, the card shows once, and it is written in Polish too.
local T = ...
local ns, mock = T.ns, T.mock
local WN = ns.WhatsNew

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function changelogVersions()
	local f = assert(io.open("CHANGELOG.md", "rb"))
	local text = f:read("*a")
	f:close()
	local released, unreleased = {}, false
	for start, heading in text:gmatch("\n()## %[([^%]]+)%]") do
		if heading == "Unreleased" then
			-- Only an [Unreleased] section with entries needs a newer card; an empty one right after a release does not.
			local body = text:sub(start):match("^[^\n]*\n(.-)\n## ") or text:sub(start)
			unreleased = body:match("%S") ~= nil
		elseif heading:match("^%d+%.%d+%.%d+$") then
			released[#released + 1] = heading
		end
	end
	return released, unreleased
end

T.case("What's new: the newest changelog version has highlights, and an [Unreleased] section has a newer entry", function()
	local released, unreleased = changelogVersions()
	T.ok(#released > 0, "CHANGELOG.md lists released versions")
	local newest = released[1]
	for _, v in ipairs(released) do
		if WN.Compare(v, newest) > 0 then
			newest = v
		end
	end
	T.ok(WN.Entry(newest), "CHANGELOG.md's newest version " .. newest .. " has no entry in Core/WhatsNew.lua (ENTRIES)")
	if unreleased then
		local top = WN.Versions()[1]
		T.ok(WN.Compare(top, newest) > 0,
			"CHANGELOG.md has an [Unreleased] section: Core/WhatsNew.lua needs an entry newer than " .. newest)
	end
	for _, version in ipairs(WN.Versions()) do
		local entry = WN.Entry(version)
		T.ok(#entry.items >= 1 and entry.title, version .. " has a title and highlights")
	end
end)

T.case("What's new: Decide for a fresh install, an update, the same version and a checkout", function()
	T.eq(WN.Decide(nil, "0.2.0", true, true), "welcome", "fresh install")
	T.eq(WN.Decide(nil, "0.2.0", false, true), "news", "update from a version that saved nothing")
	T.eq(WN.Decide("0.1.0", "0.2.0", false, true), "news", "update")
	T.eq(WN.Decide("0.2.0", "0.2.0", false, true), nil, "same version: shown already")
	T.eq(WN.Decide("0.2.0", "0.2.0", true, true), nil, "same version, even on a fresh flag")
	T.eq(WN.Decide("0.1.0", "0.2.0", false, false), nil, "no highlights for this version: nothing to show")
	T.eq(WN.Decide(nil, "dev", true, true), nil, "development checkout")
	T.eq(WN.Decide("0.1.0", "v0.2.0-3-gabc", false, true), "news", "tags and describe suffixes are read")
end)

T.case("What's new: Check shows once, never on a first install, and remembers the version", function()
	boot()
	for _, name in ipairs({ "DungeonPlannerMainFrame", "DungeonPlannerRunFrame", "DungeonPlannerNotesFrame", "DungeonPlannerDialog" }) do
		local f = rawget(_G, name)
		-- Hiding the dialog shows the next one waiting in its queue (earlier files may leave some): until none is left.
		for _ = 1, 20 do
			if not (f and f:IsShown()) then
				break
			end
			f:Hide()
		end
	end
	local oldInstance = _G.IsInInstance
	_G.IsInInstance = function() return false, "none" end
	local oldVersion, oldAdb, oldFresh = ns.version, ns.adb, ns.freshInstall
	local shown = {}
	local oldShow = ns.NewsFrame.Show
	ns.NewsFrame.Show = function(kind)
		shown[#shown + 1] = kind
		return true
	end
	local ok, err = pcall(function()
		ns.version = "0.2.0"
		-- A fresh install: the welcome, once.
		ns.adb, ns.freshInstall = { global = {} }, true
		T.eq(WN.Check(), "welcome")
		T.eq(ns.adb.global.news.seen, "0.2.0")
		T.eq(WN.Check(), nil, "not again")
		-- An update: the news, once.
		ns.adb, ns.freshInstall = { global = { news = { seen = "0.1.0" } } }, false
		T.eq(WN.Check(), "news")
		T.eq(WN.Check(), nil)
		-- 0.1.0 saved nothing: an install with data and no marker is an update, not a first install.
		ns.adb = { global = {} }
		T.eq(WN.Check(), "news")
		-- A checkout reports "dev": nothing shown, nothing saved.
		ns.version = "dev"
		ns.adb = { global = { news = { seen = "0.1.0" } } }
		T.eq(WN.Check(), nil)
		T.eq(ns.adb.global.news.seen, "0.1.0")
		-- Data from a newer version stays untouched.
		ns.version = "0.2.0"
		ns.adb = { global = {} }
		ns.dbInfo.readOnly = true
		T.eq(WN.Check(), nil)
		T.eq(ns.adb.global.news, nil)
	end)
	ns.dbInfo.readOnly = false
	_G.IsInInstance = oldInstance
	ns.NewsFrame.Show = oldShow
	ns.version, ns.adb, ns.freshInstall = oldVersion, oldAdb, oldFresh
	T.ok(ok, err)
	T.eq(table.concat(shown, ","), "welcome,news,news")
end)

T.case("What's new: DB.Init flags a first install from the saved data it finds", function()
	boot()
	local saved = _G.DungeonPlannerDB
	local oldAdb, oldDb, oldInfo, oldChar = ns.adb, ns.db, ns.dbInfo, ns.char
	local ok, err = pcall(function()
		_G.DungeonPlannerDB = nil
		ns.DB.Init()
		T.ok(ns.freshInstall, "no saved variables: fresh")
		_G.DungeonPlannerDB = { global = { plans = {} } }
		ns.DB.Init()
		T.ok(not ns.freshInstall, "saved data exists: not fresh")
	end)
	_G.DungeonPlannerDB = saved
	ns.adb, ns.db, ns.dbInfo, ns.char = oldAdb, oldDb, oldInfo, oldChar
	ns.freshInstall = false
	T.ok(ok, err)
end)

T.case("What's new: the card and the welcome are built, dismissable, and reopen with /dp new", function()
	boot()
	local welcome = WN.Welcome()
	T.ok(welcome.intro and #welcome.items >= 3, "what it is, and tips")
	T.ok(ns.NewsFrame.Show("welcome"))
	local f = ns.NewsFrame.Frame()
	T.ok(f:IsShown(), "welcome shown")
	T.ok(f.open:IsShown(), "the welcome offers to open the planner")
	mock.Click(f.ok)
	T.ok(not f:IsShown(), "dismissed")
	ns.Slash.Handle("new")
	T.ok(f:IsShown(), "/dp new reopens it")
	T.ok(not f.open:IsShown(), "the news card has no open button")
	f:Hide()
end)

T.case("What's new: written in Polish too", function()
	ns.SetLocale("plPL")
	local ok, err = pcall(function()
		for _, version in ipairs(WN.Versions()) do
			local entry = WN.Entry(version)
			T.ok(entry.title:find("Co nowego", 1, true), version .. " title: " .. entry.title)
		end
		T.eq(WN.Welcome().title, "Witaj w Dungeon Plannerze")
	end)
	ns.SetLocale("enUS")
	T.ok(ok, err)
	T.eq(WN.Welcome().title, "Welcome to Dungeon Planner")
end)
