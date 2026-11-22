-- Errors.Scrub (Core/Init.lua) at the edges: names next to non-ASCII punctuation, the guild's name without its rank, own
-- plan names that would eat the messages, a last word of a name, and names learned after a message was stored; and the
-- order of the errors the report merges.
local T = ...
local ns, mock = T.ns, T.mock
local Report = ns.Report

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function withNames(fn)
	local oldRealm = mock.realm
	mock.units.party1 = { name = "\208\152\208\178\208\176\208\189" } -- Иван
	mock.units.party2 = { name = "Z\196\133\197\188" } -- Zął
	mock.units.party3 = { name = "J\195\188rgen" }
	local ok, err = pcall(fn)
	mock.realm, mock.units.party1, mock.units.party2, mock.units.party3 = oldRealm, nil, nil, nil
	_G.GetGuildInfo = nil
	ns.Errors.Clear()
	assert(ok, err)
end

T.case("Scrub: names beside non-ASCII punctuation and letters", function()
	boot()
	withNames(function()
		local scrub = ns.Errors.Scrub
		local cases = {
			{ "\194\171\208\152\208\178\208\176\208\189\194\187 left", "<name>" }, -- «Иван»
			{ "\226\128\158Tester\226\128\157 said", "<name>" }, -- „Tester”
			{ "Tester\226\128\166 next", "<name>" }, -- Tester…
			{ "Tester\194\160more", "<name>" }, -- Tester NBSP more
			{ "Tester\226\128\148x", "<name>" }, -- Tester—x
			{ "(J\195\188rgen), J\195\188rgen.", "<name>" },
			{ "Z\196\133\197\188:", "<name>" },
		}
		for _, c in ipairs(cases) do
			local text = scrub(c[1])
			T.ok(text:find(c[2], 1, true), c[1] .. " -> " .. text)
			for _, secret in ipairs({ "Tester", "\208\152\208\178\208\176\208\189", "J\195\188rgen", "Z\196\133\197\188" }) do
				T.ok(not text:find(secret, 1, true), secret .. " left in: " .. text)
			end
		end
		-- A letter beside the name (ASCII or not) makes it part of another word.
		local kept = "xTester Testerx \208\152\208\178\208\176\208\189\208\190 J\195\188rgens"
		T.eq(scrub(kept), kept)
	end)
end)

T.case("Scrub: the guild's name, not its rank; the last word of a name; short realms", function()
	boot()
	withNames(function()
		_G.GetGuildInfo = function()
			return "Dark Brotherhood", "Officer", 3
		end
		mock.realm = "Area 52"
		local text = ns.Errors.Scrub("Officer of Brotherhood, Dark Brotherhood, Area 52, slot 52, Dark times")
		T.ok(text:find("Officer", 1, true), "the rank is not a private name: " .. text)
		T.ok(not text:find("Brotherhood", 1, true), "the guild, and its last word on its own: " .. text)
		T.ok(text:find("slot 52", 1, true), "a two-character last word is left alone: " .. text)
		T.ok(text:find("Dark times", 1, true), "the first word is not scrubbed on its own: " .. text)
	end)
end)

T.case("Scrub: own plan names that would eat the messages are left out", function()
	boot()
	local made = {}
	for _, name in ipairs({ "UI", "123", "ab", "Core", "Compat", "lua", "Zzplanname" }) do
		local plan = ns.Plan.New({ name = name })
		ns.DB.AddPlan(plan)
		made[#made + 1] = plan.id
	end
	local ok, err = pcall(function()
		local text = ns.Errors.Scrub("Core/UI/Compat.lua:12: ab 123 Zzplanname")
		T.eq(text, "Core/UI/Compat.lua:12: ab 123 <name>")
	end)
	for _, id in ipairs(made) do
		ns.DB.DeletePlan(id)
	end
	T.ok(ok, err)
end)

T.case("Report: stored errors and log lines are scrubbed again with names known only now", function()
	boot()
	ns.Errors.Clear()
	_G.GetGuildInfo = nil
	ns.Errors.Record("failed in Zzlategang")
	ns.Log("log for Zzlategang")
	_G.GetGuildInfo = function()
		return "Zzlategang", "Member", 1
	end
	local text = Report.Text(Report.Collect(), "")
	_G.GetGuildInfo = nil
	ns.Errors.Clear()
	T.ok(not text:find("Zzlategang", 1, true), text)
	T.ok(text:find("failed in <name>", 1, true), text)
end)

T.case("Report: BugGrabber's errors keep their order and the oldest are trimmed first", function()
	boot()
	ns.Errors.Clear()
	ns.Errors.Record("own error")
	local db = {}
	for i = 1, 12 do
		db[i] = { message = "Interface\\AddOns\\DungeonPlanner\\X.lua:" .. i .. ": grabbed " .. i, counter = 1 }
	end
	_G.BugGrabber = {
		GetDB = function()
			return db
		end,
	}
	local list = Report.Errors()
	_G.BugGrabber = nil
	ns.Errors.Clear()
	T.eq(#list, Report.MAX_ERRORS)
	T.ok(list[#list].message:find("own error", 1, true), "ours is the newest")
	T.ok(list[1].message:find("grabbed 4", 1, true), "the oldest are the ones dropped: " .. list[1].message)
	for i = 2, #list - 1 do
		T.ok(list[i].message:find("grabbed " .. (i + 3), 1, true), i .. ": " .. list[i].message)
	end
end)
