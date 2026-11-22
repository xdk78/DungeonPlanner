-- The live Getting there map: its state machine (Model/TravelLive.lua: the ticker only while shown and outdoors, arrival
-- in the target instance), the controller against the mock (UI/TravelMap.lua), entrances learned from loading screens,
-- and a guard over the code: nothing of ours writes into or parents frames under the game's world map or minimap.
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

T.case("TravelLive.Step: ticks only while shown and outdoors; arriving in the target instance", function()
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
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instance = "other" })
	T.eq(s.mode, "waiting")
	T.ok(has(fx, "stop") and not has(fx, "arrived"))
	s, fx = Live.Step(s, { kind = "world", outdoors = false, instance = "dm" })
	T.ok(has(fx, "arrived"))
	s, fx = Live.Step(s, { kind = "hide" })
	T.eq(s.mode, "hidden")
	T.eq(#fx, 0, "nothing was running")
	s, fx = Live.Step(s, { kind = "world", outdoors = true })
	T.eq(s.mode, "hidden", "hidden: the world changing starts nothing")
	T.eq(#fx, 0)
	s, fx = Live.Step(Live.New(), { kind = "show", target = "dm", outdoors = false })
	T.eq(s.mode, "waiting", "shown inside an instance: no ticker")
	T.ok(not has(fx, "start"))
	s, fx = Live.Step({ mode = "live", target = "dm" }, { kind = "hide" })
	T.ok(has(fx, "stop"))
end)

T.case("TravelLive: learned entrances are bounded, checked and only fresh", function()
	local store = {}
	T.ok(Live.Learn(store, "deadmines", { map = 1436, x = 0.42, y = 0.71, at = 100 }, 130))
	T.eq(store.deadmines.map, 1436)
	T.ok(not Live.Learn(store, "x", { map = 1436, x = 0.4, y = 0.7, at = 0 }, 1000), "a spot from minutes ago")
	T.ok(not Live.Learn(store, "y", { map = 1436, x = 1.4, y = 0.7, at = 10 }, 12), "off the map")
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
end)

T.case("Live map: the ticker runs while the window shows outdoors and stops otherwise; arrival opens run mode", function()
	boot()
	ns.Travel.Reset()
	local plan = ns.Bundled.Get(ns.Bundled.PREFIX .. "the-deadmines")
	local ent = ns.Travel.Entrance(ns.Travel.For(plan))
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
	-- Shown again outdoors, then the loading screen ends inside the Deadmines: the plan and run mode open, the spot
	-- before the screen is learned.
	w = ns.GettingThere.Open(plan)
	T.ok(select(2, ns.TravelMap.State()))
	ns.TravelMap.OnLeavingWorld()
	mock.playerPos = nil
	local realInfo = _G.GetInstanceInfo
	_G.GetInstanceInfo = function()
		return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36
	end
	ns.TravelMap.OnWorld()
	_G.GetInstanceInfo = realInfo
	T.ok(not w:IsShown(), "the travel window closes")
	T.ok(ns.RunMode.IsShown(), "run mode opens")
	T.eq(ns.UI.ctx:Plan().id, plan.id)
	T.ok(not select(2, ns.TravelMap.State()))
	local learned = ns.db.entrances[ns.Travel.For(plan).key]
	T.ok(learned and learned.map == ent.uiMapID, "the entrance is learned")
	T.ok(ns.Travel.Entrance(ns.Travel.For(plan)).learned, "and preferred")
	ns.RunMode.Hide()
	ns.db.entrances[ns.Travel.For(plan).key] = nil
	ns.Travel.Reset()
end)

-- Our code never reaches into the game's world map, quest map or minimap frames, never opens the map through the
-- global OpenWorldMap (it taints the map frame) and makes no frame pools on game frames (docs/COMPATIBILITY.md,
-- "Navigation and the world map"). The places that touch game UI are listed here; a new one fails until it is checked
-- and added.
T.case("Game UI guard: what our code touches of the game's map and minimap", function()
	local FORBIDDEN = { "WorldMapFrame", "QuestMapFrame", "AcquirePin", "CreateFramePool", "MinimapCluster",
		"[^%.%w_]OpenWorldMap%(", "Minimap:", "Minimap%.", "WorldMapButton" }
	local ALLOWED = {} -- "file:pattern" = reason
	local found = {}
	for _, dir in ipairs({ "Core", "Model", "Share", "Config", "Data", "Tracker", "UI" }) do
		local p = io.popen('find "' .. dir .. '" -name "*.lua"')
		for path in p:lines() do
			local f = assert(io.open(path, "rb"))
			local n = 0
			for line in f:lines() do
				n = n + 1
				local code = line:gsub("%-%-.*$", "")
				for _, pat in ipairs(FORBIDDEN) do
					if code:find(pat) and not ALLOWED[path .. ":" .. pat] then
						found[#found + 1] = path .. ":" .. n .. ": " .. pat
					end
				end
			end
			f:close()
		end
		p:close()
	end
	T.eq(#found, 0, table.concat(found, "\n"))
end)
