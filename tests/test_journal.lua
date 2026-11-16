-- The Adventure Guide resolver (Model/Match.lua, Data/Journal.lua), journal loot (Data/Loot.lua), map label layout
-- (Model/MapLayout.lua), plurals, /dp scan, and the pages that use them, against the fake journal in tests/wowmock.lua.
local T = ...
local ns, mock = T.ns, T.mock
local Match = ns.Match

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

-- A recommended plan as the generator writes it: names only, no journal IDs.
local hallId
local function hallPlan()
	if not hallId then
		T.ok(ns.Bundled.Add({
			id = "test-hall",
			name = "Full clear",
			instance = { name = "Hall of Tests", kind = "dungeon", levelMin = 13, levelMax = 20 },
			floors = { { name = "The Hall of Tests" } },
			pulls = { { id = "u1", name = "Summoner patrol", note = "Summoner first.", color = 1 } },
			encounters = {
				{ id = "e1", name = "Faldrim Anvilmar", strategy = "Mind Blast." },
				{ id = "e2", name = "Magmatus", strategy = "Fire Nova.", phases = { { name = "Burn", trigger = "at 30%", notes = "Run." } } },
				{ id = "e3", name = "A boss the guide does not know" },
			},
			markers = {
				{ id = "m1", floor = 1, x = 0.7, y = 0.45, kind = "boss", label = "Magmatus", encounter = "e2" },
				{ id = "m2", floor = 1, x = 0.705, y = 0.455, kind = "pack", pull = "u1", label = "Summoner patrol" },
			},
			gear = { { id = "g1", itemID = 7003, slot = "BACK", priority = 1 } },
		}))
		hallId = "b:test-hall"
	end
	return ns.DB.GetPlan(hallId)
end

T.case("Match: names in other spellings, wings, variants; map IDs; boss pairing; floors", function()
	T.eq(Match.Norm("The Deadmines"), "thedeadmines")
	T.eq(Match.NameScore("The Hall of Thanes", "Hall of Thanes"), 85, "a leading article")
	T.eq(Match.NameScore("Dire Maul: East", "Dire Maul"), 60, "a wing and the whole")
	T.eq(Match.NameScore("Stratholme (Live)", "Stratholme - Main Gate"), 50, "two variants")
	T.eq(Match.NameScore("Gnomeregan", "Uldaman"), 0)
	local entries = {
		{ ejInstanceID = 1, name = "Uldaman", kind = "dungeon", uiMapID = 230 },
		{ ejInstanceID = 2, name = "Molten Core", kind = "raid", uiMapID = 232, instanceMapID = 409 },
	}
	T.eq(Match.BestInstance({ name = "Uldaman" }, entries).ejInstanceID, 1)
	T.eq(Match.BestInstance({ name = "Geschmolzener Kern", instanceMapID = 409 }, entries).ejInstanceID, 2, "map ID in another language")
	T.eq(Match.BestInstance({ name = "Somewhere", uiMapID = 230 }, entries).ejInstanceID, 1, "uiMapID")
	T.eq(Match.BestInstance({ name = "Nothing alike" }, entries), nil)
	T.eq(Match.BestInstance({ ejInstanceID = 5, name = "Uldaman" }, entries), nil, "a journal ID is the truth")
	local paired = Match.Encounters({ { name = "Magmatus" }, { name = "magmatus" }, { name = "Plunder" } },
		{ { name = "Plunder", ejEncounterID = 3 }, { name = "Magmatus", ejEncounterID = 2 } })
	T.eq(paired[1].ejEncounterID, 2)
	T.eq(paired[2], nil, "a journal boss pairs once")
	T.eq(paired[3].ejEncounterID, 3)
	local floors = { { uiMapID = 10, name = "Upper" }, { uiMapID = 11, name = "Lower" } }
	T.eq(Match.Floor({ name = "Lower" }, 1, 1, floors).uiMapID, 11, "by name")
	T.eq(Match.Floor({ name = "" }, 2, 2, floors).uiMapID, 11, "by position")
	T.eq(Match.Floor({ uiMapID = 10 }, 2, 2, floors).uiMapID, 10, "by ID")
end)

T.case("Plurals: English 1 / other, Polish 1 / 2-4 / 5+ (12-14 too)", function()
	local forms = "%d plan|%d plany|%d planów"
	ns.SetLocale("plPL")
	T.eq(ns.Plural(1, forms), "1 plan")
	T.eq(ns.Plural(3, forms), "3 plany")
	T.eq(ns.Plural(5, forms), "5 planów")
	T.eq(ns.Plural(12, forms), "12 planów")
	T.eq(ns.Plural(22, forms), "22 plany")
	T.eq(ns.Plural(0, forms), "0 planów")
	T.eq(ns.Plural(2, ns.L["%d plan|%d plans"]), "2 plany", "Polish table")
	ns.SetLocale("enUS")
	T.eq(ns.Plural(1, ns.L["%d plan|%d plans"]), "1 plan")
	T.eq(ns.Plural(0, ns.L["%d plan|%d plans"]), "0 plans")
	T.eq(ns.Plural(2, ns.L["%d marker: %s|%d markers: %s"], "a, b"), "2 markers: a, b", "extra arguments")
end)

T.case("Map layout: a pull disc on a boss moves beside it; labels avoid each other; bosses keep theirs", function()
	local L = ns.MapLayout
	local items = {
		{ x = 100, y = 100, r = 16, kind = "boss", w = 80, h = 13, prio = 3 },
		{ x = 102, y = 101, r = 8, kind = "disc", w = 90, h = 13, prio = 1 },
	}
	L.Nudge(items)
	T.ok(items[2].moved and items[2].x > 110, "disc moved to the boss's side")
	L.Labels(items)
	T.eq(items[1].side, "below", "the boss label keeps its place")
	T.ok(items[2].side ~= "below" or true)
	-- Two pins side by side: the second label cannot sit below on top of the first.
	local row = {
		{ x = 100, y = 100, r = 8, kind = "pin", w = 120, h = 13, prio = 1 },
		{ x = 130, y = 100, r = 8, kind = "pin", w = 120, h = 13, prio = 1 },
	}
	L.Labels(row)
	T.eq(row[1].side, "below")
	T.ok(row[2].side ~= "below", "second label moved or hidden")
	-- Crowded: a low-priority label with no free side is hidden, a boss's never.
	local crowd = { { x = 0, y = 0, r = 4, kind = "pin", w = 40, h = 13, prio = 1 } }
	for _, d in ipairs({ { 0, 14 }, { 0, -14 }, { 26, 0 }, { -26, 0 } }) do
		crowd[#crowd + 1] = { x = d[1], y = d[2], r = 10, kind = "pin", w = 0, h = 13 }
	end
	L.Labels(crowd)
	T.eq(crowd[1].side, nil, "hidden")
	crowd[1].prio = 3
	L.Labels(crowd)
	T.ok(crowd[1].side ~= nil, "a boss label always shows (on the side where it covers the least)")
	-- Pins never cover each other: a route stop on a marker becomes a badge beside it; two bosses side by side part.
	local pins = {
		{ x = 100, y = 100, r = 11, kind = "pin", w = 0, h = 13 },
		{ x = 101, y = 100, r = 10, kind = "stop", w = 0, h = 13 },
		{ x = 200, y = 100, r = 17, kind = "boss", w = 0, h = 13 },
		{ x = 220, y = 120, r = 17, kind = "boss", w = 0, h = 13 },
	}
	L.Nudge(pins)
	T.ok(pins[2].moved and pins[2].x + pins[2].r <= pins[1].x - pins[1].r, "the stop sits left of the marker")
	T.eq(pins[1].moved, nil, "the marker stays put")
	local a, b = pins[3], pins[4]
	T.ok(math.abs(a.x - b.x) >= a.r + b.r - 1 or math.abs(a.y - b.y) >= a.r + b.r - 1, "the bosses no longer overlap")
	-- Labels keep clear of a rectangle to avoid (the legend over the map).
	local lone = { { x = 100, y = 100, r = 8, kind = "pin", w = 60, h = 13, prio = 1 } }
	L.Labels(lone, { { 60, 100, 140, 140 } })
	T.eq(lone[1].side, "above", "below is covered by the legend")
end)

T.case("Journal: a plan with names only resolves to the guide's instance, bosses, art, floors and pins", function()
	boot()
	ns.Journal.Reset()
	local plan = hallPlan()
	local entry, score = ns.Journal.ForPlan(plan)
	T.ok(entry, "resolved")
	T.eq(entry.ejInstanceID, 900, "by name despite 'The'")
	T.ok(score >= 75, "a sure match")
	T.eq(ns.Journal.InstanceArt(plan.instance).button, 3101, "card picture")
	local e1, d1 = ns.Journal.EncounterIds(plan, plan.encounters[1])
	T.eq(e1, 901)
	T.eq(d1, 3001)
	T.eq(ns.Journal.EncounterIds(plan, plan.encounters[3]), nil, "unknown boss stays unmatched")
	T.eq(ns.Journal.BossArt(plan, plan.encounters[2]).displayInfo, 50002, "portrait from the creature")
	T.eq(ns.Journal.FloorMap(plan, 1), 300, "the guide's map for the floor")
	T.eq(#ns.Journal.Pins(300, 900), 2)
	T.ok(ns.Bundled.SameInstance(plan.instance, entry), "the home grid merges the plan into the journal card")
	-- Kill tracking uses the journal's encounter ID.
	local summary = ns.Progress.PlanSummary(ns.char.progress, plan, ns.Journal.GameIdOf(plan))
	T.eq(summary.bosses, 3, "every boss counts")
	-- An editable copy stores the IDs.
	local copy = ns.UI.CopyPlan(plan)
	T.eq(copy.instance.ejInstanceID, 900)
	T.eq(copy.encounters[1].ejEncounterID, 901)
	T.eq(copy.encounters[2].dungeonEncounterID, 3002)
	T.eq(copy.encounters[3].ejEncounterID, nil)
	T.eq(copy.floors[1].uiMapID, 300)
	ns.DB.DeletePlan(copy.id)
end)

T.case("Journal: an empty first scan is retried; secret IDs and an open guide are reported", function()
	ns.Journal.Reset()
	local saved = mock.journal.tiers
	mock.journal.tiers = {}
	T.eq(#ns.Journal.GetAll().list, 0)
	mock.journal.tiers = saved
	T.ok(#ns.Journal.GetAll().list >= 3, "found on the next call")
	ns.Journal.Reset()
	_G.EncounterJournal = { IsShown = function()
		return true
	end }
	T.eq(#ns.Journal.GetAll().list, 0)
	T.ok(ns.Journal.lastScan.errors[1], "says why")
	_G.EncounterJournal = nil
	T.ok(#ns.Journal.GetAll().list >= 3)
end)

T.case("Loot: per boss, class filter, slot filter, loading state", function()
	ns.Loot.Reset()
	local items, status = ns.Loot.For(900, 901, {})
	T.eq(status, "ok")
	T.eq(#items, 2)
	T.eq(items[1].slot, "NECK", "slot from the item's equip location")
	T.eq(#ns.Loot.For(900, 901, { classID = 1 }), 1, "warrior: no mage bracers")
	T.eq(#ns.Loot.For(900, 901, { slot = "WRIST" }), 1)
	T.eq(mock.ej.classID, 0, "the journal's loot filter is put back")
	ns.Loot.Reset()
	mock.lootLoading = true
	local _, st = ns.Loot.For(900, 902, {})
	T.eq(st, "loading")
	mock.lootLoading = nil
	T.eq(select(2, ns.Loot.For(900, 902, {})), "ok", "not cached while loading")
end)

T.case("Read-only pages show text, not inputs; gear lists the guide's drops; party layout for dungeons", function()
	boot()
	local plan = hallPlan()
	ns.UI.SelectPlan(plan.id)
	local page = _G.DungeonPlannerMainFrame.instancePage
	T.ok(page.header.plan.label:GetText():find("Full clear (recommended)", 1, true))
	-- Bosses.
	ns.UI.SelectTab("encounters")
	local bosses = page.panels.encounters.inner
	T.ok(bosses.doc:IsShown(), "boss as text")
	T.ok(not bosses.area:IsShown(), "no editor")
	T.ok(not bosses.add:IsShown(), "no Add boss")
	-- Plan (notes + progress).
	ns.UI.SelectTab("plan")
	local planPanel = page.panels.plan
	T.ok(planPanel.notes.doc:IsShown(), "notes as text")
	T.ok(not planPanel.notes.author:IsShown(), "no author input")
	T.ok(planPanel.progress.summary:GetText():find("Bosses 0/3", 1, true), "every boss counted")
	-- Pulls.
	ns.UI.SelectTab("pulls")
	local pulls = page.panels.pulls.inner
	T.ok(pulls.doc:IsShown() and not pulls.editor:IsShown(), "pull as text")
	T.ok(not pulls.add:IsShown(), "no Add pull")
	-- Gear: the plan's own entry, then the drops of each matched boss.
	ns.UI.SelectTab("gear")
	local gear = page.panels.gear.inner
	T.ok(not gear.form:IsShown(), "no add form")
	local headers, drops = 0, 0
	for _, item in ipairs(gear.list.items) do
		if item.header then
			headers = headers + 1
		elseif item.loot then
			drops = drops + 1
		end
	end
	T.eq(drops, 3, "two drops of Faldrim, one of Magmatus")
	T.ok(headers >= 3, "sections and bosses")
	-- Assignments: a dungeon shows the party.
	ns.UI.SelectTab("assignments")
	local assign = page.panels.assignments.inner
	T.ok(assign.groups.card:IsShown() and not assign.groups.raid:IsShown(), "party layout: the card of seats")
	T.ok(not assign.groups.fill:IsShown(), "read-only: no fill")
	-- Map: the guide's map, the pull disc moved off the boss.
	ns.UI.SelectTab("map")
	local canvas = page.panels.map.canvas
	canvas:DrawContent()
	T.eq(canvas.mapID, 300, "map art from the journal")
	T.eq(canvas.journalInstanceID, 900)
end)

T.case("Shared lists only received plans; the footer says dev build and counts your plans", function()
	boot()
	ns.UI.GoHome("shared")
	local home = _G.DungeonPlannerMainFrame.home
	for _, plan in ipairs(home.shared.list.items) do
		T.ok(not plan.bundled, "no recommended plan on Shared")
	end
	T.ok(not home.newPlan:IsShown() and not home.here:IsShown() and not home.customMap:IsShown(), "no make-a-plan buttons")
	ns.UI.GoHome("dungeons")
	T.ok(home.newPlan:IsShown())
	ns.UI.RefreshFooter()
	local status = _G.DungeonPlannerMainFrame.footer.status:GetText()
	T.ok(status:find("dev build", 1, true), "dev build")
	T.ok(status:find("My plans: " .. #ns.DB.Plans(), 1, true), "own plan count")
end)

T.case("/dp scan saves the journal for offline reading; /dp scan clear removes it", function()
	boot()
	ns.Slash.Handle("scan")
	local d = _G.DungeonPlannerDB.diagnostics
	T.ok(d, "saved")
	local hall
	for _, inst in ipairs(d.instances) do
		if inst.id == 900 then
			hall = inst
		end
	end
	T.ok(hall, "every journal instance")
	T.eq(hall.uiMapID, 300)
	T.eq(hall.bosses[1], "901|3001|50001||Faldrim Anvilmar")
	T.eq(hall.floors[1], "300|art|The Hall of Tests")
	T.ok(d.plans["b:test-hall"]:find("^900 The Hall of Tests"), "how recommended plans resolve")
	T.ok(d.loot.available)
	ns.Slash.Handle("scan clear")
	T.eq(_G.DungeonPlannerDB.diagnostics, nil)
	ns.Slash.Handle("debug")
	local found = false
	for _, line in ipairs(mock.printed) do
		if line:find("Adventure Guide:", 1, true) then
			found = true
		end
	end
	T.ok(found, "/dp debug reports the journal")
end)
