-- Boss information from Dungeon Journal (Data/Providers/DungeonJournal.lua "Boss", Data/BossInfo.lua, UI/BossSections.lua):
-- the adapter's shape checks with good, missing and malformed data, what a marker's details say (no repeated names), and
-- the detail pane, the Bosses page and run mode with and without the addon.
local T = ...
local ns, mock = T.ns, T.mock
local P = ns.Providers

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

-- These tests are about what the providers answer: the bundled facts (Data/BossData.lua) would answer first.
local function fresh()
	ns.BossData.enabled = false
	P.Reset()
	P.ResetCaches()
end

local function hot()
	return ns.Bundled.Get("b:hall-of-thanes")
end

local function boss(plan, name)
	for _, enc in ipairs(plan.encounters) do
		if enc.name == name then
			return enc
		end
	end
end

local function markerFor(plan, label)
	for _, m in ipairs(plan.markers) do
		if m.kind == "boss" and m.label == label then
			return m
		end
	end
end

-- The texts a frame shows (shown font strings below it, none under a hidden frame).
local function shownTexts(root)
	local out = {}
	local function visible(f)
		while f do
			if f._shown == false then
				return false
			end
			if f == root then
				return true
			end
			f = f._parent
		end
		return false
	end
	for _, f in ipairs(mock.frames) do
		if f._type == "FontString" and f._text and f._text ~= "" and visible(f) then
			out[#out + 1] = f._text
		end
	end
	return out
end

local function has(texts, needle)
	for _, t in ipairs(texts) do
		if t:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function count(texts, needle)
	local n = 0
	for _, t in ipairs(texts) do
		if t == needle then
			n = n + 1
		end
	end
	return n
end

T.case("Dungeon Journal boss info: level, description, summon item and drops, credited", function()
	boot()
	mock.InstallProviders()
	fresh()
	local plan = hot()
	local info, credit = P.BossInfo(plan, boss(plan, "Magmatus"))
	T.eq(credit, "Dungeon Journal")
	T.eq(info.level, "17-18")
	T.eq(info.description, "Made-up description for the tests.")
	T.eq(info.summon.itemID, 900150)
	T.eq(#info.drops, 1)
	T.eq(info.drops[1].itemID, 900103)
	local faldrim = P.BossInfo(plan, boss(plan, "Faldrim Anvilmar"))
	T.eq(faldrim.level, "16")
	T.eq(faldrim.description, nil, "no description where the journal has none")
	T.eq(faldrim.summon, nil)
	T.eq(#faldrim.drops, 2)
	-- A boss the journal does not list, and the trash list, give nothing.
	T.eq(P.BossInfo(plan, { id = "x", name = "Nobody" }), nil)
	T.eq(P.BossInfo(plan, { id = "x", name = "Trash Drops" }), nil)
	-- Switched off in the settings: nothing, and back again.
	P.SetEnabled("dungeonJournal", false)
	T.eq(P.BossInfo(plan, boss(plan, "Magmatus")), nil)
	T.eq(ns.BossInfo.For(plan, boss(plan, "Magmatus")), nil, "the page-level cache follows the setting")
	P.SetEnabled("dungeonJournal", true)
	T.ok(ns.BossInfo.For(plan, boss(plan, "Magmatus")), "on again")
	mock.RemoveProviders()
	fresh()
	T.eq(P.BossInfo(plan, boss(plan, "Magmatus")), nil, "addon not installed")
	T.eq(ns.BossInfo.For(plan, boss(plan, "Magmatus")), nil)
	T.eq(#ns.BossInfo.Sections(plan, boss(plan, "Magmatus")), 0)
end)

T.case("Dungeon Journal boss info: malformed fields are skipped, text is cleaned, the adapter stays on", function()
	boot()
	local function install(bossRow, levels)
		_G.ForeverDungeonJournal_NS = { DB = { ["Hall of Thanes"] = { bosses = { bossRow } } }, BOSS_LEVELS = levels }
		fresh()
	end
	local plan = hot()
	local enc = boss(plan, "Faldrim Anvilmar")
	-- Levels: a number, text, a range, "??"; anything else is dropped.
	for given, want in pairs({ [16] = "16", ["24-25"] = "24-25", ["??"] = "??", ["junk"] = false, [-1] = false,
		[{}] = false, [true] = false, ["1|cffff0000"] = false }) do
		install({ name = "Faldrim Anvilmar", loot = { { 5, "Ok" } } }, { ["Hall of Thanes"] = { ["Faldrim Anvilmar"] = given } })
		local info = P.BossInfo(plan, enc)
		T.eq(info and info.level, want or nil, "level " .. tostring(given))
	end
	-- BOSS_LEVELS of the wrong shape: no level, the rest still there.
	for _, levels in ipairs({ 5, "x", { ["Hall of Thanes"] = 7 }, { ["Hall of Thanes"] = { "x" } } }) do
		install({ name = "Faldrim Anvilmar", loot = { { 5, "Ok" } } }, levels)
		local info = P.BossInfo(plan, enc)
		T.ok(info and info.level == nil and #info.drops == 1, "levels of the wrong shape")
	end
	-- Text: control characters and colour or link codes are removed, long text is cut at a whole character.
	install({ name = "Faldrim Anvilmar", description = "A |cffff0000red|r\tword\n|Hitem:1|h[x]|h" .. string.rep("\195\169", 400),
		summonItem = "nope", loot = { { 7, "Bad |cffff0000name|r", "Neck|n", 3 }, "junk", { -1 }, { 8, 5 } } })
	local info = P.BossInfo(plan, enc)
	T.ok(not info.description:find("|", 1, true), "no escape codes: " .. info.description)
	T.ok(#info.description <= 300 and info.description:sub(-3) == "...", "cut")
	T.ok(not info.description:match("[\194-\244]%.%.%.$"), "not inside a character")
	T.eq(info.summon, nil, "a summon item that is not an ID")
	T.eq(#info.drops, 2, "bad loot rows skipped")
	T.ok(not info.drops[1].name:find("|", 1, true), "item names cleaned")
	T.eq(info.drops[2].name, nil, "a name that is not text")
	-- Many drops are capped; an empty boss row (no data at all) is nil.
	local loot = {}
	for i = 1, 30 do
		loot[i] = { 1000 + i, "Item " .. i, "Neck", 2 }
	end
	install({ name = "Faldrim Anvilmar", loot = loot })
	T.eq(#P.BossInfo(plan, enc).drops, 12)
	install({ name = "Faldrim Anvilmar" })
	T.eq(P.BossInfo(plan, enc), nil, "nothing known")
	T.ok(P.Get("dungeonJournal"), "the adapter is still on")
	-- A boss that is not a table, a table that raises: the adapter switches off, we do not.
	install("junk")
	T.eq(P.BossInfo(plan, enc), nil)
	_G.ForeverDungeonJournal_NS = setmetatable({ DB = {} }, { __index = function(_, k)
		if k == "BOSS_LEVELS" then
			error("boom")
		end
	end })
	fresh()
	T.eq(P.BossInfo(plan, enc), nil)
	mock.RemoveProviders()
	fresh()
end)

T.case("Boss info: level text, the line under a name, and the sections in reading order", function()
	boot()
	mock.InstallProviders()
	fresh()
	local BI = ns.BossInfo
	T.eq(BI.LevelText("16"), "Level 16")
	T.eq(BI.LevelText("24-25"), "Levels 24-25")
	T.eq(BI.LevelText("??"), "Level ??")
	T.eq(BI.LevelText("x"), nil)
	T.eq(BI.LevelText(16), nil)
	T.eq(BI.Meta({ level = "16", rare = true }), "Level 16 \194\183 Rare")
	T.eq(BI.Meta({ rare = true }), "Rare")
	T.eq(BI.Meta({}), nil)
	T.eq(BI.Meta(nil), nil)
	local plan = hot()
	local sections, info = BI.Sections(plan, boss(plan, "Magmatus"))
	local ids = {}
	for i, s in ipairs(sections) do
		ids[i] = s.id
		T.eq(s.credit, "Dungeon Journal")
	end
	T.eq(table.concat(ids, ","), "description,summon,drops")
	T.eq(info.level, "17-18")
	local capped = BI.Sections(plan, boss(plan, "Faldrim Anvilmar"), { maxDrops = 1 })
	T.eq(#capped, 1)
	T.eq(#capped[1].items, 1, "the page's limit")
	T.eq(BI.RunMeta(plan, boss(plan, "Faldrim Anvilmar")), "Level 16")
	mock.RemoveProviders()
	fresh()
end)

T.case("Marker details: no name said twice, per kind", function()
	boot()
	mock.InstallProviders()
	fresh()
	local BI = ns.BossInfo
	local plan = hot()
	-- A boss marker: the heading is its kind; the name is the header, once.
	local m = markerFor(plan, "Faldrim Anvilmar")
	local d = BI.MarkerDetail(plan, m)
	T.eq(d.heading, "Boss")
	T.eq(d.kind, nil)
	T.eq(d.boss.name, "Faldrim Anvilmar")
	T.eq(d.boss.info.level, "16")
	T.eq(#d.lines, 0, "no 'Boss: name' line")
	-- Without the addon the header is still there, with no facts.
	mock.RemoveProviders()
	fresh()
	d = BI.MarkerDetail(plan, m)
	T.eq(d.boss.name, "Faldrim Anvilmar")
	T.eq(d.boss.info, nil)
	-- Every other marker: its name is the heading, its kind one line, and no line repeats the heading.
	for _, mk in ipairs(plan.markers) do
		d = BI.MarkerDetail(plan, mk)
		if mk.kind ~= "boss" then
			T.eq(d.heading, mk.label ~= "" and mk.label or ns.L[mk.kind], "heading of " .. mk.kind)
			T.eq(d.kind, mk.label ~= "" and ns.L[mk.kind] or nil)
		end
		for _, line in ipairs(d.lines) do
			T.ok(line ~= d.heading and line ~= (d.boss and d.boss.name), "a line repeats the heading: " .. line)
		end
		T.eq(d.boss ~= nil, mk.kind == "boss" and (mk.label ~= "" or mk.encounter ~= nil))
	end
	-- A pull marker named like its pull says only the pull's number; a differently named pull is spelled out.
	local pull = plan.pulls[1]
	local named = { id = "mx", floor = 1, x = 0.5, y = 0.5, kind = "pack", label = pull.name, pull = pull.id, note = "Watch out", role = nil }
	d = BI.MarkerDetail(plan, named)
	T.eq(d.heading, pull.name)
	T.eq(d.lines[1], "Pull 1")
	T.eq(d.note, "Watch out")
	named.label = "Left side"
	d = BI.MarkerDetail(plan, named)
	T.eq(d.lines[1], string.format("Pull 1: %s", pull.name))
	-- A position keeps its role; an unnamed marker has its kind as heading and no kind line.
	d = BI.MarkerDetail(plan, { id = "my", floor = 1, x = 0.1, y = 0.1, kind = "position", label = "", role = "TANK", note = "" })
	T.eq(d.heading, ns.L.position)
	T.eq(d.kind, nil)
	T.eq(d.lines[1], "Role: Tank")
	T.eq(d.note, nil)
	-- A boss marker that names a boss the plan does not list is looked up by name, not linked to the plan.
	d = BI.MarkerDetail(plan, { id = "mz", floor = 1, x = 0.1, y = 0.1, kind = "boss", label = "Some Other Boss", note = "x" })
	T.eq(d.boss.name, "Some Other Boss")
	T.ok(d.boss.standIn and d.boss.strategy == nil)
	-- A boss marker with no name and no link: just the kind.
	d = BI.MarkerDetail(plan, { id = "mw", floor = 1, x = 0.1, y = 0.1, kind = "boss", label = "", note = "" })
	T.eq(d.heading, "Boss")
	T.eq(d.boss, nil)
end)

T.case("Detail pane of a boss marker: header, level, drops, strategy and the note; sections hidden without data", function()
	boot()
	mock.InstallProviders()
	fresh()
	local plan = hot()
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("map")
	local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
	local ed = map.editor
	local m = markerFor(plan, "Faldrim Anvilmar")
	ed:ShowMarker(plan, m, true)
	local texts = shownTexts(ed.details)
	T.eq(ed.heading:GetText(), "Boss")
	T.eq(count(texts, "Faldrim Anvilmar"), 1, "the name once")
	T.ok(has(texts, "Level 16"), "the level")
	T.ok(has(texts, "Drops"), "the drops section")
	T.ok(has(texts, "Dungeon Journal"), "credited")
	T.ok(has(texts, "Item 900101") and has(texts, "Item 900102"), "the drops")
	T.ok(has(texts, "Head") or has(texts, "Neck"), "their slot")
	T.ok(not has(texts, "Boss: "), "no 'Boss: name' line")
	if m.note ~= "" then
		T.ok(has(texts, (ns.Util.SplitApprox(m.note))), "the note")
	end
	-- Magmatus: description and the summon item too.
	ed:ShowMarker(plan, markerFor(plan, "Magmatus"), true)
	texts = shownTexts(ed.details)
	T.ok(has(texts, "Made-up description for the tests."), "description")
	T.ok(has(texts, "Summon with"), "summon item")
	T.ok(has(texts, "Levels 17-18"))
	-- Without the addon: the header and the plan's own text only.
	mock.RemoveProviders()
	fresh()
	ed:ShowMarker(plan, m, true)
	texts = shownTexts(ed.details)
	T.eq(count(texts, "Faldrim Anvilmar"), 1)
	T.ok(not has(texts, "Drops") and not has(texts, "Dungeon Journal") and not has(texts, "Level"), "nothing from the addon")
	-- A marker that is not a boss: its name once, its kind, its note.
	for _, mk in ipairs(plan.markers) do
		if mk.kind ~= "boss" and mk.label ~= "" then
			ed:ShowMarker(plan, mk, true)
			texts = shownTexts(ed.details)
			T.eq(ed.heading:GetText(), mk.label)
			T.eq(count(texts, mk.label), 0, "the heading is the name: not again in the text (" .. mk.kind .. ")")
			T.ok(has(texts, ns.L[mk.kind]), "its kind")
			break
		end
	end
end)

T.case("Bosses page and run mode show the same facts, hidden without them", function()
	boot()
	mock.InstallProviders()
	fresh()
	local plan = hot()
	ns.UI.SelectPlan(plan.id)
	ns.UI.SelectTab("encounters")
	local panel = _G.DungeonPlannerMainFrame.instancePage.panels.encounters.inner
	local function pick(name)
		panel:Refresh()
		for _, row in ipairs(panel.list.rows) do
			if row.item and row.item.name == name then
				row:GetScript("OnClick")(row, "LeftButton")
			end
		end
		return shownTexts(panel.doc)
	end
	local texts = pick("Magmatus")
	T.ok(has(texts, "Made-up description for the tests."), "description under the strategy")
	T.ok(has(texts, "Summon with") and has(texts, "Drops") and has(texts, "Item 900103"))
	T.ok(has(texts, "Dungeon Journal"), "credited")
	T.ok(has(texts, "Levels 17-18"), "the level in the header")
	-- Run mode: the level leads the next boss's line.
	ns.db.ui.step = nil
	ns.RunMode.Show()
	local f = _G.DungeonPlannerRunFrame
	ns.UI.FocusStep(1, { stay = true })
	ns.RunMode.Refresh()
	T.ok(f.boss.text:GetText():find("Level 16", 1, true), "run mode: " .. tostring(f.boss.text:GetText()))
	ns.RunMode.Hide()
	-- Own copies show the sections under their loot.
	local copy = ns.UI.CopyPlan(plan)
	ns.UI.SelectPlan(copy.id)
	ns.UI.SelectTab("encounters")
	local own = _G.DungeonPlannerMainFrame.instancePage.panels.encounters.inner
	own:Refresh()
	T.ok(own.area.content.dj:IsShown() and has(shownTexts(own.area.content.dj), "Drops"), "sections under the loot of an own plan")
	-- Without the addon nothing of it shows.
	mock.RemoveProviders()
	fresh()
	own:Refresh()
	T.ok(not own.area.content.dj:IsShown(), "hidden without data")
	ns.UI.SelectPlan(plan.id)
	panel:Refresh()
	texts = pick("Magmatus")
	T.ok(not has(texts, "Drops") and not has(texts, "Dungeon Journal") and not has(texts, "Summon with"))
	T.ok(has(texts, "Boss 2 of 4"), "the header without a level")
end)

T.case("Bosses page: an ability's note hangs under its name, not under its icon", function()
	boot()
	local saved = ns.BossData.enabled
	ns.BossData.enabled = true -- the bundled abilities and their notes, as in game
	P.ResetCaches()
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
	ns.UI.SelectPlan("b:hall-of-thanes")
	ns.UI.SelectTab("encounters")
	local page = _G.DungeonPlannerMainFrame.instancePage.panels.encounters.inner
	page:Refresh()
	local plan = ns.UI.ctx:Plan()
	for _, row in ipairs(page.list.rows) do
		if row.item == plan.encounters[1] then
			row:GetScript("OnClick")(row, "LeftButton")
		end
	end
	local found
	for _, row in ipairs(page.doc.dpItemRows or {}) do
		if row:IsShown() and row.dpSpell and row.note:IsShown() then
			found = row
			break
		end
	end
	T.ok(found, "an ability with a note (Hall of Thanes' first boss)")
	local note, name = found.note:FindPoint("TOPLEFT"), found.name:FindPoint("TOPLEFT")
	T.ok(note and note[2] == found.icon and note[3] == "BOTTOMRIGHT", "the note starts at the icon's right edge")
	T.eq(note[4], name[4], "as far in as the name")
	T.eq(name[2], found.icon)
	local icon = found.icon:FindPoint("TOPLEFT")
	T.ok(icon and (icon[2] == nil or icon[2] == found), "the icon at the row's top")
	-- The row is as tall as its note's lines: a short note leaves no empty lines under it.
	local ROW_H = ns.BossSections.ROW_H
	local lines = math.ceil(found.note:GetStringHeight())
	T.ok(lines > 0, "the note is measured")
	T.eq(found:GetHeight(), ROW_H + lines, "name, tags and the note's own lines")
	found.note:SetText("Short.")
	local oneLine = math.ceil(found.note:GetStringHeight())
	page.doc:Finish() -- the layout again, as on a resize
	T.ok(found:GetHeight() < ROW_H + 2 * oneLine, "a one-line note adds one line: " .. found:GetHeight())
	ns.BossData.enabled = saved
	P.ResetCaches()
end)
