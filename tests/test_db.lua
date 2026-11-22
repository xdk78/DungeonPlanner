-- Migrations, quarantine, read-only mode, import into the store, locales.
local T = ...
local ns = T.ns
local DB = ns.DB

T.case("Migration 0 -> 1 turns a plan list into a map and validates", function()
	local global = { plans = { { id = "pA", name = "A" }, { name = "B" }, "junk" } }
	local info = DB.LoadGlobal(global)
	T.eq(global.schema, DB.SCHEMA)
	T.eq(info.migratedFrom, 0)
	T.ok(global.plans.pA, "kept by id")
	local n = 0
	for id, plan in pairs(global.plans) do
		n = n + 1
		T.eq(plan.id, id)
	end
	T.eq(n, 2, "two plans, junk skipped")
end)

T.case("Invalid stored plans are quarantined, not deleted", function()
	local global = { schema = 1, plans = { good = { name = "ok" }, bad = "not a table" } }
	local info = DB.LoadGlobal(global)
	T.eq(info.quarantined, 1)
	T.eq(global.quarantine[1].data, "not a table")
	T.ok(global.plans.good)
	T.eq(global.plans.bad, nil)
end)

T.case("Data from a newer schema is left untouched", function()
	local global = { schema = DB.SCHEMA + 1, plans = { x = "whatever" } }
	local info = DB.LoadGlobal(global)
	T.ok(info.readOnly)
	T.eq(global.plans.x, "whatever")
end)

T.case("ImportString adds new plans with source info and never overwrites", function()
	T.freshDB()
	local plan = ns.Plan.New({ name = "Shared" })
	ns.DB.AddPlan(plan)
	local text = ns.Codec.ExportPlan(plan)
	local ok, msg, added = ns.DB.ImportString(text, { from = "Anna", kind = "received" })
	T.ok(ok, msg)
	T.ok(added[1].id ~= plan.id, "new id")
	T.eq(added[1].source.from, "Anna")
	T.eq(#ns.DB.Plans(), 2)
	local bad = ns.DB.ImportString("!DP1!garbage")
	T.eq(bad, false)
	-- Read-only mode refuses.
	ns.dbInfo.readOnly = true
	T.eq(ns.DB.ImportString(text), false)
	T.eq(ns.DB.AddPlan(ns.Plan.New({})), nil)
	ns.dbInfo.readOnly = false
end)

T.case("Plans are grouped by instance key", function()
	T.freshDB()
	ns.DB.AddPlan(ns.Plan.New({ instance = { name = "A", kind = "dungeon", ejInstanceID = 63 } }))
	ns.DB.AddPlan(ns.Plan.New({ instance = { name = "B", kind = "dungeon", uiMapID = 7 } }))
	T.eq(#ns.DB.Plans("ej:63"), 1)
	T.eq(#ns.DB.Plans("map:7"), 1)
	T.eq(#ns.DB.Plans(), 2)
end)

T.case("Polish locale covers every key and is chosen with WoW Po Polsku", function()
	local en = ns.SetLocale("auto")
	T.eq(en, "enUS", "plain English client")
	T.eq(ns.L["Map"], "Map")
	T.mock.loadedAddons = { WoWPoPolskuForever = true }
	-- Installed but no language picked in its chooser: it translates nothing, so neither do we.
	_G.WoWPoPolskuForeverDB = nil
	T.eq(ns.SetLocale("auto"), "enUS", "translation addon installed, never configured")
	_G.WoWPoPolskuForeverDB = { wlaczony = true, wersjaInstalki = 1 }
	T.eq(ns.SetLocale("auto"), "enUS", "translation addon without a chosen language")
	_G.WoWPoPolskuForeverDB = { jezyk = "plPL" }
	T.eq(ns.SetLocale("auto"), "enUS", "language saved before the chooser existed is ignored, as the addon does")
	_G.WoWPoPolskuForeverDB = { jezyk = "plPL", wyborJezyka = 1 }
	T.eq(ns.SetLocale("auto"), "plPL", "translation addon set to Polish")
	T.eq(ns.L["Map"], "Mapa")
	T.eq(ns.L["boss"], "Boss")
	-- The translation set to another language does not switch us to Polish.
	_G.WoWPoPolskuForeverDB = { jezyk = "csCZ", wyborJezyka = 1 }
	T.eq(ns.SetLocale("auto"), "enUS")
	_G.WoWPoPolskuForeverDB = { jezyk = "plPL", wyborJezyka = 1, wlaczony = false }
	T.eq(ns.SetLocale("auto"), "enUS", "translation switched off")
	_G.WoWPoPolskuForeverDB = nil
	T.mock.loadedAddons = nil
	T.eq(ns.SetLocale("plPL"), "plPL", "forced Polish")
	T.eq(ns.L["missing key stays"], "missing key stays")
	ns.SetLocale("enUS")
	-- Every shipped language: string pairs, the same format specifiers in the same order (or string.format breaks),
	-- and as many plural forms as the language has.
	local FORMS = { plPL = 3, ruRU = 3, deDE = 2, esES = 2, frFR = 2 }
	local function specs(s)
		local out = {}
		for spec in s:gmatch("%%[%d%.]*[sdf]") do
			out[#out + 1] = spec
		end
		return table.concat(out, ",")
	end
	for _, entry in ipairs(ns.LOCALE_LIST) do
		local code = entry[1]
		if code ~= "enUS" then
			T.ok(ns.Locales[code], code .. " is loaded")
			for k, v in pairs(ns.Locales[code]) do
				T.ok(type(k) == "string" and type(v) == "string" and v ~= "", code .. ": string pairs")
				if k:find("|", 1, true) then
					local want = specs(k:match("^[^|]*"))
					local n = 0
					for form in v:gmatch("[^|]+") do
						n = n + 1
						T.eq(specs(form), want, code .. ": format specifiers of a form of " .. k)
					end
					T.eq(n, FORMS[code], code .. ": plural forms of " .. k)
				elseif k:find("%", 1, true) then
					T.eq(specs(v), specs(k), code .. ": format specifiers of " .. k)
				end
			end
		end
	end
end)

T.case("Automatic language follows the client's locale when we have it", function()
	local mock = T.mock
	local was = mock.locale
	local CASES = {
		{ "enUS", "enUS" }, { "enGB", "enUS" }, { "deDE", "deDE" }, { "frFR", "frFR" }, { "esES", "esES" },
		{ "esMX", "esES", "the Spanish translation serves Latin America" }, { "ruRU", "ruRU" },
		{ "koKR", "enUS", "no Korean translation: English" }, { "itIT", "enUS", "no Italian translation: English" },
	}
	for _, c in ipairs(CASES) do
		mock.locale = c[1]
		T.eq(ns.SetLocale("auto"), c[2], c[3] or ("client " .. c[1]))
	end
	-- A chosen language wins over the client's, and aliases resolve.
	mock.locale = "deDE"
	T.eq(ns.SetLocale("frFR"), "frFR")
	T.eq(ns.SetLocale("esMX"), "esES")
	T.eq(ns.SetLocale("nonsense"), "enUS", "an unknown code is English")
	-- The language list offers every shipped locale once.
	local seen = {}
	for _, entry in ipairs(ns.LOCALE_LIST) do
		T.ok(not seen[entry[1]], "listed once: " .. entry[1])
		seen[entry[1]] = true
		T.ok(ns.Locales[entry[1]], "has a table: " .. entry[1])
	end
	-- A translated string comes out in each language, an untranslated one in English.
	ns.SetLocale("deDE")
	T.eq(ns.L["Close"], "Schließen")
	T.eq(ns.L["not a key"], "not a key")
	mock.locale = was
	ns.SetLocale("enUS")
end)
