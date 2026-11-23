-- Offline test runner. Plain Lua 5.1, no busted. From the repo root:
--   lua tests/run.lua [filter] [--file <names>] [--reverse | --shuffle <seed>]
-- Loads the whole addon (TOC order, embedded libraries included) against tests/wowmock.lua, then runs every
-- tests/test_*.lua file. Exit code 1 when anything fails.
--   filter            only the cases whose name contains this text
--   --file <names>    only these files, in this order (comma-separated: test_native, test_native.lua or native),
--                     on a freshly loaded addon; one name runs that file alone
--   --reverse         the files in reverse order; --shuffle <seed> in a seeded random order. Both catch a case that
--                     passes only because another file's cases ran first.

package.path = "./tests/?.lua;" .. package.path
math.randomseed(42)

local realPrint = print
local mock = require("wowmock")
mock.Install()

local ns = {}
mock.LoadAddon(".", "DungeonPlanner.toc", "DungeonPlanner", ns)
mock.KnowArt(ns)

local T = { passed = 0, failed = 0, failures = {}, mock = mock, ns = ns }
local filter, onlyFile, order, seed
do
	local i = 1
	while i <= #arg do
		local a = arg[i]
		if a == "--file" then
			onlyFile = {}
			for name in assert(arg[i + 1], "--file needs a name"):gmatch("[^,]+") do
				onlyFile[#onlyFile + 1] = "test_" .. name:gsub("%.lua$", ""):gsub("^test_", "") .. ".lua"
			end
			i = i + 1
		elseif a == "--reverse" then
			order = "reverse"
		elseif a == "--shuffle" then
			order, seed = "shuffle", assert(tonumber(arg[i + 1]), "--shuffle needs a numeric seed")
			i = i + 1
		elseif a:sub(1, 2) == "--" then
			error("unknown option " .. a)
		else
			filter = a
		end
		i = i + 1
	end
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "values differ", tostring(expected), tostring(actual)), 2)
	end
end

function T.ok(value, msg)
	if not value then
		error(msg or "expected a true value", 2)
	end
end

function T.raises(fn, msg)
	local ok = pcall(fn)
	if ok then
		error(msg or "expected an error", 2)
	end
end

-- The sending functions cases replace to see what goes out, and the game's lockdown answers: put back after every case,
-- so a case that fails before its own cleanup does not take the next ones' messages (or hold them) with it.
local comm = {}
local function saveComm()
	if not comm.saved and ns.addon then
		comm.saved = true
		comm.send = ns.addon.SendCommMessage
		comm.sendAddon = _G.C_ChatInfo.SendAddonMessage
		comm.restricted = _G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
	end
end
local function restoreComm()
	if comm.saved then
		ns.addon.SendCommMessage = comm.send
		_G.C_ChatInfo.SendAddonMessage = comm.sendAddon
		_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = comm.restricted
	end
	mock.lockdown = false
end

-- Addon messages from a known state, for cases that count what goes out: no group, no lockdown, nothing waiting in
-- Comm's outbox, no run led or followed, the timers an earlier file left run out (a hello goes 5 s after a roster
-- change), and ChatThrottleLib's queue sent. Advances the mock clock by 10 s.
function T.quietComm()
	mock.inGroup, mock.units, mock.lockdown = false, {}, false
	ns.Comm.outbox = {}
	ns.RunSync.state = ns.Sync.New()
	mock.Advance(10, 0.1)
end

function T.case(name, fn)
	if filter and not name:find(filter, 1, true) then
		return
	end
	saveComm()
	local ok, err = pcall(fn)
	saveComm() -- the first case boots the addon
	restoreComm()
	mock.ResetInput() -- no cursor, key or button carried into the next case, also after a failure
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		T.failures[#T.failures + 1] = name .. ": " .. tostring(err)
		realPrint("FAIL " .. name .. "\n     " .. tostring(err))
	end
end

-- A fresh in-memory database for tests that need ns.db (the real one comes from AceDB in Boot). The one it replaces
-- comes back after the file, so the files after it keep the booted addon's database.
local replacedDB
function T.freshDB()
	replacedDB = replacedDB or { db = ns.db, char = ns.char, dbInfo = ns.dbInfo }
	local adb = { profile = { settings = {}, ui = {}, minimap = {} }, global = { plans = {}, quarantine = {} }, char = {} }
	ns.Defaults.Fill(adb.profile.settings, ns.Defaults.settings)
	ns.Defaults.Fill(adb.profile.ui, ns.Defaults.ui)
	adb.char.progress = ns.Progress.NewStore()
	ns.db = setmetatable({}, {
		__index = function(_, k)
			if k == "settings" or k == "ui" or k == "minimap" then
				return adb.profile[k]
			end
			return adb.global[k]
		end,
	})
	ns.char = adb.char
	ns.dbInfo = { readOnly = false }
	return adb
end

-- Listed explicitly (portable: no directory listing in plain Lua). Add new test files here.
local files = { "test_model.lua", "test_share.lua", "test_db.lua", "test_v2.lua", "test_plans.lua", "test_ui.lua", "test_journal.lua",
	"test_gamefiles.lua", "test_spawns.lua", "test_bossdata.lua", "test_wartable.lua", "test_recorder.lua", "test_providers.lua", "test_picker.lua",
	"test_native.lua", "test_drawing.lua", "test_drawing_ui.lua", "test_shots.lua", "test_simplify.lua", "test_runcompare.lua", "test_pages.lua", "test_acks.lua",
	"test_review.lua", "test_followups.lua", "test_lastplan.lua", "test_bossinfo.lua", "test_minimapart.lua", "test_mapfamily.lua", "test_items.lua",
	"test_source.lua", "test_reyesmaps.lua", "test_fonts.lua", "test_floors.lua", "test_gamepad.lua", "test_perf.lua", "test_sync.lua",
	"test_roster.lua", "test_news.lua", "test_report.lua", "test_probe.lua", "test_probe_stop.lua", "test_feedback.lua", "test_fixes.lua",
	"test_scrub.lua",
	"test_prep.lua", "test_travel_live.lua", "test_party.lua",
	"test_walk.lua", "test_walk_ui.lua", "test_gearfilter.lua", "test_routes.lua",
	"test_provider_pins.lua", "test_scroll.lua",
	"test_routelegs.lua", "test_routelook.lua", "test_openmap_overlay.lua", "test_identity.lua", "test_zoom.lua",
	"test_release_changelog.lua" }
if onlyFile then
	local listed = {}
	for _, file in ipairs(files) do
		listed[file] = true
	end
	for _, file in ipairs(onlyFile) do
		assert(listed[file], "no test file " .. file .. " in the list")
	end
	files = onlyFile
elseif order == "reverse" then
	for i = 1, math.floor(#files / 2) do
		files[i], files[#files + 1 - i] = files[#files + 1 - i], files[i]
	end
elseif order == "shuffle" then
	-- An own generator (Park-Miller), so math.random keeps the sequence the cases see in a normal run.
	local state = seed % 2147483646 + 1
	for i = #files, 2, -1 do
		state = state * 16807 % 2147483647
		local j = state % i + 1
		files[i], files[j] = files[j], files[i]
	end
	realPrint("file order (seed " .. seed .. "): " .. table.concat(files, " "))
end
-- Between files every list, document, scroll area and multi-line field forgets what it was showing (its scroll owner,
-- UI/Containers.lua): the next file's first refresh starts it at the top, as another plan would, so no file finds the
-- offset or cursor an earlier one left on the same plan's list.
local function forgetScrollOwners()
	for _, f in ipairs(mock.frames) do
		f.scrollOwner, f.valueOwner = nil, nil
	end
end

for _, file in ipairs(files) do
	local chunk = assert(loadfile("tests/" .. file))
	forgetScrollOwners()
	chunk(T)
	if replacedDB then
		ns.db, ns.char, ns.dbInfo = replacedDB.db, replacedDB.char, replacedDB.dbInfo
		replacedDB = nil
	end
end

realPrint(string.format("\n%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
