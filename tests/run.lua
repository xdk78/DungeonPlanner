-- Offline test runner. Plain Lua 5.1, no busted. From the repo root:  lua tests/run.lua [filter]
-- Loads the whole addon (TOC order, embedded libraries included) against tests/wowmock.lua, then runs every
-- tests/test_*.lua file. Exit code 1 when anything fails.

package.path = "./tests/?.lua;" .. package.path
math.randomseed(42)

local realPrint = print
local mock = require("wowmock")
mock.Install()

local ns = {}
mock.LoadAddon(".", "DungeonPlanner.toc", "DungeonPlanner", ns)
mock.KnowArt(ns)

local T = { passed = 0, failed = 0, failures = {}, mock = mock, ns = ns }
local filter = arg[1]

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

function T.case(name, fn)
	if filter and not name:find(filter, 1, true) then
		return
	end
	local ok, err = pcall(fn)
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		T.failures[#T.failures + 1] = name .. ": " .. tostring(err)
		realPrint("FAIL " .. name .. "\n     " .. tostring(err))
	end
end

-- A fresh in-memory database for tests that need ns.db (the real one comes from AceDB in Boot).
function T.freshDB()
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
	"test_review.lua", "test_followups.lua", "test_lastplan.lua", "test_bossinfo.lua", "test_minimapart.lua", "test_mapfamily.lua", "test_perf.lua" }
for _, file in ipairs(files) do
	local chunk = assert(loadfile("tests/" .. file))
	chunk(T)
end

realPrint(string.format("\n%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
