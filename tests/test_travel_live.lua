-- The live Getting there map: its state machine (Model/TravelLive.lua: the ticker only while shown and outdoors, arrival
-- only from outside into the target instance), which entrances are learned (near the bundled one only) and how they are
-- forgotten, the controller against the mock (UI/TravelMap.lua: instances by ID, a localized name, a wing, the arrow off
-- the entrance's map, no redraw without a change), the card under the map, the saved store, and a guard over the code:
-- nothing of ours writes into or parents frames under the game's world map or minimap.
local T = ...
local ns, mock = T.ns, T.mock
local Live = ns.TravelLive

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	ns.BossData.enabled = true
end

local function has(list, x)
	for _, v in ipairs(list) do
		if v == x then
			return true
		end
	end
	return false
end

local DM = { dm = true }

T.case("TravelLive.Step: ticks only while shown and outdoors; arriving from outside into the target", function()
	local s, fx = Live.Step(Live.New(), { kind = "show", target = "dm", outdoors = true })
	T.eq(s.mode, "live")
	T.ok(has(fx, "start") and has(fx, "draw"))
	s, fx = Live.Step(s, { kind = "tick", outdoors = true })
	T.eq(s.mode, "live")
	T.ok(has(fx, "draw") and not has(fx, "start"))
	s, fx = Live.Step(s, { kind = "tick", outdoors = false })
	T.eq(s.mode, "waiting", "the position is gone")
	T.ok(has(fx, "stop"))
	s, fx = Live.Step(s, { kind = "tick", outdoors = true })
	T.eq(#fx, 0, "a stale tick after the stop changes nothing")
	s, fx = Live.Step(s, { kind = "world", outdoors = true })
	T.eq(s.mode, "live")
	T.ok(has(fx, "start"))
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instances = { other = true } })
	T.eq(s.mode, "waiting")
	T.ok(has(fx, "stop") and not has(fx, "arrived"))
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instances = DM })
	T.ok(has(fx, "arrived"), "from another instance into the target")
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instances = DM })
	T.ok(not has(fx, "arrived"), "a second world event inside (a zone change) is no new arrival")
	s, fx = Live.Step(s, { kind = "hide" })
	T.eq(s.mode, "hidden")
	T.eq(#fx, 0, "nothing was running")
	s, fx = Live.Step(s, { kind = "world", outdoors = true })
	T.eq(s.mode, "hidden", "hidden: the world changing starts nothing")
	T.eq(#fx, 0)
	-- Opened while already inside the target: no arrival until the player has been out.
	s, fx = Live.Step(Live.New(), { kind = "show", target = "dm", outdoors = false, instances = DM })
	T.eq(s.mode, "waiting", "shown inside an instance: no ticker")
	T.ok(not has(fx, "start") and not has(fx, "arrived"))
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instances = DM })
	T.ok(not has(fx, "arrived"), "still inside")
	s = Live.Step(s, { kind = "world", outdoors = true })
	local _, back = Live.Step(s, { kind = "world", outdoors = false, instances = DM })
	T.ok(has(back, "arrived"), "out and back in")
	s, fx = Live.Step({ mode = "live", target = "dm" }, { kind = "hide" })
	T.eq(s.mode, "hidden")
	T.ok(has(fx, "stop"))
end)

T.case("TravelLive: a spot is learned only near the bundled entrance; bounded, checked, forgotten", function()
	local ent = { continent = 0, wx = -11000, wy = 1500 }
	local near = { uiMapID = 1436, x = 0.4, y = 0.7, continent = 0, wx = -11100, wy = 1700 }
	T.ok(Live.Accept(near, ent, 1436), "about 220 yards from it")
	T.ok(not Live.Accept({ uiMapID = 1454, x = 0.5, y = 0.5, continent = 0, wx = -8000, wy = 1500 }, ent, 1436),
		"3000 yards away: a summon or a portal, not the entrance")
	T.ok(not Live.Accept({ uiMapID = 1454, x = 0.5, y = 0.5, continent = 1, wx = -11000, wy = 1500 }, ent, 1436),
		"another continent")
	T.ok(Live.Accept({ uiMapID = 1423, x = 0.4, y = 0.3 }, nil, 1423), "no bundled entrance: its zone's map")
	T.ok(not Live.Accept({ uiMapID = 1420, x = 0.4, y = 0.3 }, nil, 1423), "no bundled entrance: another zone")
	T.ok(not Live.Accept({ uiMapID = 1436, x = 0.4, y = 0.7 }, { uiMapID = 1436, x = 0.4, y = 0.7 }, 1436),
		"a bundled entrance the client cannot place in the world: nothing learned, not the zone-map fallback")
	-- Of several records, the one that accepts; none when two share the spot (one courtyard for four wings).
	local a, b = { key = "a", e = ent }, { key = "b" }
	local function bundledOf(rec)
		return rec.e
	end
	local function zoneOf()
		return 1436
	end
	T.eq(Live.Choose({ a, b }, near, bundledOf, function() return nil end), a)
	T.eq(Live.Choose({ a, { key = "c", e = ent } }, near, bundledOf, zoneOf), nil, "ambiguous: nothing learned")
	local store = {}
	T.ok(Live.Learn(store, "deadmines", { map = 1436, x = 0.42, y = 0.71 }, 130))
	T.eq(store.deadmines.map, 1436)
	T.eq(store.deadmines.at, 130, "when it was learned")
	T.ok(not Live.Learn(store, "y", { map = 1436, x = 1.4, y = 0.7 }, 12), "off the map")
	-- A learned entrance is replaced only by a spot within RELEARN_RADIUS of it.
	local function apart(p, q)
		return math.abs(p.x - q.x) * 10000 + math.abs(p.y - q.y) * 1000
	end
	T.ok(not Live.Learn(store, "deadmines", { map = 1436, x = 0.45, y = 0.71 }, 140, apart), "300 yards off: kept")
	T.eq(store.deadmines.x, 0.42)
	T.ok(not Live.Learn(store, "deadmines", { map = 1436, x = 0.42, y = 0.72 }, 140), "cannot tell: kept")
	T.ok(Live.Learn(store, "deadmines", { map = 1436, x = 0.42, y = 0.76 }, 150, apart), "50 yards off: replaced")
	T.eq(store.deadmines.y, 0.76)
	T.eq(store.deadmines.at, 150)
	local big = {}
	for i = 1, 150 do
		big["k" .. i] = { map = 1, x = 0.5, y = 0.5, at = 1 }
	end
	big.bad = { map = "x", x = 0.5, y = 0.5 }
	local n = 0
	for _ in pairs(Live.NormalizeLearned(big)) do
		n = n + 1
	end
	T.eq(n, Live.MAX_LEARNED)
	T.eq(next(Live.NormalizeLearned("junk")), nil)
	T.eq(Live.Forget(store), 1)
	T.eq(next(store), nil)
end)

T.case("Travel.Here: the instance by its ID, a wing by its floor map", function()
	boot()
	ns.Travel.Reset()
	local dm = ns.Travel.Here(36)
	T.eq(#dm, 1)
	T.eq(dm[1], ns.Travel.For(ns.Bundled.Get(ns.Bundled.PREFIX .. "the-deadmines")))
	T.eq(#ns.Travel.Here(189), 4, "Scarlet Monastery's four wings share one instance ID")
	local lib = ns.Travel.Here(189, 303)
	T.eq(#lib, 1)
	T.eq(lib[1], ns.Travel.For(ns.Bundled.Get(ns.Bundled.PREFIX .. "scarlet-monastery-library")), "the Library's floor")
	T.eq(#ns.Travel.Here(189, 9999), 4, "a map no wing has: all of them")
	T.eq(#ns.Travel.Here(nil), 0)
end)

local function inside(name, instanceID)
	local real = _G.GetInstanceInfo
	_G.GetInstanceInfo = function()
		return name, "party", 1, "Normal", 5, 0, false, instanceID
	end
	return function()
		_G.GetInstanceInfo = real
	end
end

T.case("Live map: ticker while shown outdoors, arrival by instance ID (a localized name), learning near the entrance", function()
	boot()
	ns.Travel.Reset()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "the-deadmines")
	local rec = ns.Travel.For(plan)
	local ent = ns.Travel.Entrance(rec)
	mock.playerPos = { map = ent.uiMapID, x = ent.x, y = math.min(1, ent.y + 0.2) }
	local w = ns.GettingThere.Open(plan)
	local st, ticking = ns.TravelMap.State()
	T.eq(st.mode, "live")
	T.ok(ticking, "outdoors and shown: ticking")
	T.ok(w.map.player:IsShown(), "the player's arrow on the entrance's map")
	T.ok(w.map.entrance:IsShown())
	T.ok(w.live:GetText():find("away", 1, true), w.live:GetText())
	-- The position goes away (a loading screen into an instance): the next tick stops the ticker.
	mock.playerPos = nil
	mock.Advance(0.25)
	st, ticking = ns.TravelMap.State()
	T.eq(st.mode, "waiting")
	T.ok(not ticking)
	-- Hidden: nothing runs, whatever the world does.
	w:Hide()
	mock.playerPos = { map = ent.uiMapID, x = ent.x, y = ent.y }
	ns.TravelMap.OnWorld()
	st, ticking = ns.TravelMap.State()
	T.eq(st.mode, "hidden")
	T.ok(not ticking)
	-- A far spot (3000 yards off) before a loading screen into the Deadmines teaches nothing.
	mock.playerPos = { map = 1454, x = 0.5, y = 0.5 }
	mock.FireEvent("PLAYER_LEAVING_WORLD")
	mock.playerPos = nil
	local restore = inside("Las Minas de la Muerte", 36)
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	restore()
	T.eq(ns.db.entrances[rec.key], nil, "a summon from far away is not the entrance")
	-- Shown again outdoors near the entrance, then the loading screen ends inside the Deadmines (a Spanish client's
	-- name: matched by the instance ID): the plan and run mode open, the spot before the screen is learned. A zone
	-- change that arrives before the screen's end does not drop the spot.
	mock.playerPos = { map = ent.uiMapID, x = ent.x, y = ent.y }
	w = ns.GettingThere.Open(plan)
	T.ok(select(2, ns.TravelMap.State()))
	mock.FireEvent("PLAYER_LEAVING_WORLD")
	mock.playerPos = nil
	restore = inside("Las Minas de la Muerte", 36)
	mock.FireEvent("ZONE_CHANGED_NEW_AREA")
	T.eq(ns.db.entrances[rec.key], nil, "a zone change learns nothing")
	mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	restore()
	T.ok(not w:IsShown(), "the travel window closes")
	T.ok(ns.RunMode.IsShown(), "run mode opens")
	T.eq(ns.UI.ctx:Plan().id, plan.id)
	T.ok(not select(2, ns.TravelMap.State()))
	local learned = ns.db.entrances[rec.key]
	T.ok(learned and learned.map == ent.uiMapID, "the entrance is learned on its zone map")
	T.ok(ns.Travel.Entrance(rec).learned, "and preferred")
	ns.RunMode.Hide()
	-- A later screen from 250 yards off (near the bundled entrance, so accepted, but not near the learned one): the
	-- first stays. 50 yards off: it is refined.
	local first = { x = learned.x, y = learned.y }
	mock.playerPos = { map = ent.uiMapID, x = ent.x + 0.025, y = ent.y }
	ns.TravelMap.OnLeavingWorld()
	mock.playerPos = nil
	restore = inside("Las Minas de la Muerte", 36)
	ns.TravelMap.OnEnteringWorld()
	restore()
	T.ok(ns.db.entrances[rec.key].x == first.x and ns.db.entrances[rec.key].y == first.y, "the first spot is kept")
	local nearY = ent.y + (ent.y < 0.9 and 0.05 or -0.05)
	mock.playerPos = { map = ent.uiMapID, x = ent.x, y = nearY }
	ns.TravelMap.OnLeavingWorld()
	mock.playerPos = nil
	restore = inside("Las Minas de la Muerte", 36)
	ns.TravelMap.OnEnteringWorld()
	restore()
	T.ok(math.abs(ns.db.entrances[rec.key].y - nearY) < 0.001, "a spot near the learned one replaces it")
	ns.RunMode.Hide()
	-- /dp entrances reset forgets it; the bundled entrance is used again.
	ns.Slash.Handle("entrances reset")
	T.eq(next(ns.db.entrances), nil)
	T.ok(not ns.Travel.Entrance(rec).learned)
	-- The Settings panel's button does the same, for players without slash commands; in combat it waits.
	ns.db.entrances[rec.key] = { map = ent.uiMapID, x = ent.x, y = ent.y, at = 1 }
	ns.Travel.Reset()
	T.ok(ns.Travel.Entrance(rec).learned)
	local opts = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("DungeonPlanner", "dialog", "DungeonPlannerTest-1.0")
	local button = opts.args.advanced.args.forgetEntrances
	T.ok(button and button.type == "execute", "Troubleshooting has the button")
	T.ok(button.order > opts.args.advanced.args.selftest.order and button.order < opts.args.advanced.args.report.order,
		"next to the self-test")
	mock.inCombat = true
	button.func()
	T.ok(ns.db.entrances[rec.key], "in combat: not yet")
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.eq(next(ns.db.entrances), nil, "after combat: forgotten")
	T.ok(not ns.Travel.Entrance(rec).learned, "the bundled entrance at once")
	ns.Travel.Reset()
end)

T.case("Live map: opened inside the target is no arrival; a wing is told apart by its floor", function()
	boot()
	ns.Travel.Reset()
	ns.RunMode.Hide()
	local lib = ns.Bundled.Get(ns.Bundled.PREFIX .. "scarlet-monastery-library")
	-- Inside the Armory (its floor map 437, no position): the Library's window opens, nothing happens.
	mock.playerPos = { map = 437, x = 0, y = 0 }
	local restore = inside("Monasterio Escarlata", 189)
	local w = ns.GettingThere.Open(lib)
	ns.TravelMap.OnWorld()
	T.ok(w:IsShown() and not ns.RunMode.IsShown(), "another wing of the same instance: not arrived")
	-- Opened inside the Library itself: not an arrival either (the player did not come in).
	w:Hide()
	mock.playerPos = { map = 303, x = 0, y = 0 }
	w = ns.GettingThere.Open(lib)
	ns.TravelMap.OnWorld()
	T.ok(w:IsShown() and not ns.RunMode.IsShown(), "already inside when the window opened")
	restore()
	w:Hide()
	mock.playerPos = nil
end)

T.case("Live map: the arrow off the entrance's map, no redraw without a change, the card under it", function()
	boot()
	ns.Travel.Reset()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "the-deadmines")
	local ent = ns.Travel.Entrance(ns.Travel.For(plan))
	-- On another (overlapping) map of the same continent: the arrow is placed from world yards.
	mock.playerPos = { map = ent.uiMapID + 2, x = ent.x, y = 0.5 }
	local w = ns.GettingThere.Open(plan)
	T.ok(w.map.player:IsShown(), "projected onto the entrance's map")
	-- The same spot twice: the line is not fitted again.
	local fits, real = 0, ns.Widgets.FitText
	ns.Widgets.FitText = function(...)
		fits = fits + 1
		return real(...)
	end
	local p = ns.Travel.Player()
	ns.TravelMap.Dispatch({ kind = "tick", outdoors = true, player = p })
	ns.TravelMap.Dispatch({ kind = "tick", outdoors = true, player = p })
	T.eq(fits, 0, "unchanged: nothing redrawn")
	mock.playerPos = { map = ent.uiMapID, x = ent.x, y = math.min(1, ent.y + 0.3) }
	ns.TravelMap.Dispatch({ kind = "tick", outdoors = true, player = ns.Travel.Player() })
	T.eq(fits, 1, "moved: redrawn once")
	ns.Widgets.FitText = real
	-- The card under the live map leaves the distance to the live line; the Prep card keeps it.
	local function text(live)
		local out = {}
		for _, l in ipairs(ns.GettingThere.Lines(plan, live)) do
			out[#out + 1] = l[2]
		end
		return table.concat(out, "\n")
	end
	T.ok(text(false):find("away", 1, true), "Prep card: the distance")
	T.ok(not text(true):find("away", 1, true), "under the live map: no second distance line")
	-- A resize (the client's OnSizeChanged, run by the harness) fits the map to the window, lays the art out again and
	-- puts the pins back, scaled, without looking anything up.
	local Layout = require("wowui.layout")
	local ins, SP = w.insets, ns.Style.SPACE
	local function entranceX()
		local pt = w.map.entrance:FindPoint("CENTER")
		return pt and pt[4]
	end
	-- Wide art for the entrance's map, so its width (not the map's fixed height) sets the scale.
	local cmap = _G.C_Map
	local realLayers, realTextures = cmap.GetMapArtLayers, cmap.GetMapArtLayerTextures
	cmap.GetMapArtLayers = function(id)
		if id == ent.uiMapID then
			return { { layerWidth = 1000, layerHeight = 200, tileWidth = 256, tileHeight = 256 } }
		end
		return realLayers(id)
	end
	cmap.GetMapArtLayerTextures = function(id, layer)
		return id == ent.uiMapID and { 1, 2, 3, 4 } or realTextures(id, layer)
	end
	w.map:SetTarget(ns.Travel.For(plan), ent)
	w:SetSize(ns.GettingThere.MIN_W, 600)
	Layout.SettleSizes(mock)
	local cw1, x1 = w.map.cw, entranceX()
	local nearest, realNearest = 0, ns.Travel.Nearest
	ns.Travel.Nearest = function(...)
		nearest = nearest + 1
		return realNearest(...)
	end
	w:SetSize(ns.GettingThere.MIN_W + 40, 600)
	T.ok(Layout.SettleSizes(mock) > 0, "the size scripts ran")
	ns.Travel.Nearest = realNearest
	T.eq(nearest, 0, "no flight masters looked up on resize")
	T.eq(w.map:GetWidth(), ns.GettingThere.MIN_W + 40 - ins.left - ins.right - 2 * SP.md, "the map follows the window")
	T.ok(w.map.cw > cw1, "the art grows with it: " .. tostring(cw1) .. " -> " .. tostring(w.map.cw))
	T.ok(w.map.entrance:IsShown())
	T.ok(math.abs(entranceX() - x1 * w.map.cw / cw1) < 0.01, "the entrance pin's offset scales with the art")
	T.ok(math.abs(entranceX() - ent.x * w.map.cw) < 0.01)
	cmap.GetMapArtLayers, cmap.GetMapArtLayerTextures = realLayers, realTextures
	w:Hide()
	-- Leaving from that other map next to the entrance: the spot is learned on the entrance's map.
	mock.playerPos = { map = ent.uiMapID + 2, x = ent.x, y = 0.5 }
	ns.TravelMap.OnLeavingWorld()
	mock.playerPos = nil
	local restore = inside("The Deadmines", 36)
	ns.TravelMap.OnEnteringWorld()
	restore()
	local key = ns.Travel.For(plan).key
	local learned = ns.db.entrances[key]
	T.ok(learned and learned.map == ent.uiMapID, "projected onto the entrance's map")
	ns.db.entrances[key] = nil
	ns.Travel.Reset()
	ns.RunMode.Hide()
end)

T.case("Windows: a saved size under the minimum opens at the minimum", function()
	boot()
	local f = ns.Widgets.Window("DungeonPlannerTestSmallFrame", "Test", { width = 300, height = 400 },
		ns.GettingThere.MIN_W, ns.GettingThere.MIN_H, { compact = true })
	T.eq(f:GetWidth(), ns.GettingThere.MIN_W)
	T.eq(f:GetHeight(), ns.GettingThere.MIN_H)
	f:Hide()
	f = ns.Widgets.Window("DungeonPlannerTestBigFrame", "Test", { width = 500, height = 700 }, 320, 460, { compact = true })
	T.eq(f:GetWidth(), 500, "a larger saved size is kept")
	f:Hide()
end)

T.case("Learned entrances in the saved data: junk dropped on load, none while the data is read-only", function()
	boot()
	local saved = _G.DungeonPlannerDB
	local oldAdb, oldDb, oldInfo, oldChar = ns.adb, ns.db, ns.dbInfo, ns.char
	local ok, err = pcall(function()
		_G.DungeonPlannerDB = { global = { schema = ns.DB.SCHEMA, plans = {}, entrances = {
			good = { map = 1436, x = 0.5, y = 0.25, at = 7 }, bad = { map = "x", x = 0.5, y = 0.5 },
			off = { map = 1436, x = 3, y = 0.5 }, [5] = { map = 1436, x = 0.5, y = 0.5 } } } }
		ns.DB.Init()
		T.eq(ns.db.entrances.good.map, 1436)
		T.eq(ns.db.entrances.bad, nil)
		T.eq(ns.db.entrances.off, nil)
		T.eq(ns.Util.Count(ns.db.entrances), 1)
		-- Saved by a newer version: read-only, no store (nothing learned, nothing rewritten).
		local entrances = { good = { map = 1436, x = 0.5, y = 0.25 } }
		_G.DungeonPlannerDB = { global = { schema = ns.DB.SCHEMA + 1, plans = {}, entrances = entrances } }
		ns.DB.Init()
		T.eq(ns.db.entrances, nil)
		T.eq(_G.DungeonPlannerDB.global.entrances, entrances)
	end)
	_G.DungeonPlannerDB = saved
	ns.adb, ns.db, ns.dbInfo, ns.char = oldAdb, oldDb, oldInfo, oldChar
	T.ok(ok, err)
end)

-- Our code never reaches into the game's world map, quest map or minimap frames, never opens the map through the
-- global OpenWorldMap (it taints the map frame) and makes no frame pools on game frames (docs/COMPATIBILITY.md,
-- "Navigation and the world map"). The addon's tracked Lua files (git ls-files, as tests/test_source.lua does) are
-- scanned line by line, comments left out; every directory must list files, so the guard cannot pass by scanning
-- nothing. Each line is scanned with a space before and after it, so a call at column 1 is caught too. A new use fails
-- until it is checked and listed in ALLOWED.
T.case("Game UI guard: what our code touches of the game's map and minimap", function()
	local FORBIDDEN = { "WorldMapFrame", "QuestMapFrame", "AcquirePin", "CreateFramePool", "MinimapCluster",
		"[^%.%w_]OpenWorldMap%(", "Minimap:", "Minimap%.", "WorldMapButton",
		"[\"']Minimap[\"']", "_G%.Minimap[^%w_]" } -- the minimap by name: rawget(_G, "Minimap"), _G["Minimap"], _G.Minimap
	local ALLOWED = { -- "file:pattern" = reason
		["Data/Diagnostics.lua:[\"']Minimap[\"']"] = "/dp debug reads the Minimap frame's state inside instances (read only)",
	}
	local function hits(line, pat)
		return (" " .. line .. " "):find(pat) ~= nil
	end
	-- The patterns catch what they are for.
	for _, sample in ipairs({ "OpenWorldMap(1)", "local m = rawget(_G, \"Minimap\")", "x = _G['Minimap']",
		"local m = _G.Minimap", "Minimap:SetZoom(1)" }) do
		local caught = false
		for _, pat in ipairs(FORBIDDEN) do
			caught = caught or hits(sample, pat)
		end
		T.ok(caught, "the guard catches: " .. sample)
	end
	local found = {}
	for _, dir in ipairs({ "Core", "Model", "Share", "Config", "Data", "Tracker", "UI" }) do
		local p = io.popen("git ls-files -- " .. dir)
		T.ok(p, "git ls-files can run")
		local scanned = 0
		for path in p:lines() do
			if path:match("%.lua$") then
				scanned = scanned + 1
				local f = assert(io.open(path, "rb"))
				local n = 0
				for line in f:lines() do
					n = n + 1
					local code = line:gsub("%-%-.*$", "")
					for _, pat in ipairs(FORBIDDEN) do
						if hits(code, pat) and not ALLOWED[path .. ":" .. pat] then
							found[#found + 1] = path .. ":" .. n .. ": " .. pat
						end
					end
				end
				f:close()
			end
		end
		p:close()
		T.ok(scanned > 0, dir .. ": git ls-files listed its Lua files (run the tests from a git checkout)")
	end
	T.eq(#found, 0, table.concat(found, "\n"))
end)
