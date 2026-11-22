-- The experimental plan overlay on OpenMap's own dungeon map (UI/OpenMapOverlay.lua, Data/Providers/OpenMap.lua
-- Placement) against a fake OpenMapDungeonView built like OpenMap 0.8.12's (Map/Dungeons.lua: a frame with `page`,
-- `floor`, `floors`, `inst`, `source`, the floor buttons `prev`, `next`, `floorButton`): off by default, detection
-- failures degrade with a reason, plan and floor matching by tile file ID and by name, the alignment path, the overlay's
-- place in OpenMap's frames, floor changes through the hooked buttons and through the fallback check, nothing running
-- while hidden or off, the gamepad interface style, and no frame made in combat.
local T = ...
local ns, mock = T.ns, T.mock
local O = ns.OpenMapOverlay

local DEADMINES = "b:the-deadmines"

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function tiles(first, prefix)
	local out = { first }
	for i = 2, 12 do
		out[i] = prefix and (prefix .. i) or (first + i)
	end
	return out
end

-- The plan's boss markers on a floor as OpenMap boss positions, moved by x' = x * k + d (k = 1, d = 0: the same).
local function pinsFrom(plan, floor, k, d)
	local out = {}
	for _, m in ipairs(plan.markers) do
		if m.kind == "boss" and m.floor == floor then
			out[m.label] = { floor, m.x * k + d, m.y * k + d }
		end
	end
	return out
end

-- OpenMap's namespace (made-up content in its shapes) with the Deadmines on the game's maps and as a drawing.
local function installOpenMap()
	mock.InstallProviders()
	local root = _G.OpenMap
	root.MapDungeonMaps = { [36] = {
		{ tiles = tiles(449591), name = "The Deadmines" },
		{ tiles = tiles(449603), name = "Ironclad Cove" },
	} }
	root.MapDungeonDrawn[36] = { { tiles = tiles("d1_1", "d1_"), name = "The Deadmines" },
		{ tiles = tiles("d2_1", "d2_"), name = "Ironclad Cove" } }
	root.MapDungeonBosses[36] = {}
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"):lower()] = 449591
	mock.files[("Interface\\WorldMap\\TheDeadmines\\TheDeadmines2_1"):lower()] = 449603
	-- Its public API's callbacks (CallbackHandler's shape: RegisterCallback(owner, event, fn)); fire(event) calls them.
	local callbacks = {}
	_G.OpenMapAPI = { major = 1, version = 4,
		RegisterCallback = function(owner, event, fn)
			callbacks[event] = callbacks[event] or {}
			callbacks[event][owner] = fn
		end,
		UnregisterCallback = function(owner, event)
			if callbacks[event] then
				callbacks[event][owner] = nil
			end
		end,
		fire = function(event, ...)
			for _, fn in pairs(callbacks[event] or {}) do
				fn(event, ...)
			end
		end,
	}
	ns.GameFiles.Reset()
	ns.Providers.Reset()
	ns.Providers.ResetCaches()
	return root
end

local function button(parent, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetScript("OnClick", fn)
	return b
end

-- OpenMap's view: floors from its tables, the first shown. o = { source, floors, noButtons, inst }.
local function fakeView(root, o)
	o = o or {}
	local view = CreateFrame("Frame", "OpenMapDungeonView", UIParent)
	view:SetFrameLevel(100)
	view.port = CreateFrame("Frame", nil, view)
	view.port:SetFrameLevel(101)
	view.page = CreateFrame("Frame", nil, view.port)
	view.page:SetFrameLevel(102)
	view.page:SetSize(1002, 668)
	view.source = o.source or "blizzard"
	view.floors = o.floors or root.MapDungeonMaps[36]
	view.inst = o.inst or { 36, "Deadmines", false, 17, 26 }
	view.floor = 1
	local function show(i)
		view.floor = ((i - 1) % #view.floors) + 1
	end
	if not o.noButtons then
		view.prev = button(view, function()
			show(view.floor - 1)
		end)
		view.next = button(view, function()
			show(view.floor + 1)
		end)
		view.floorButton = button(view, function()
			view.list = view.list or { rows = { button(view, function(r)
				show(r.floor)
			end), button(view, function(r)
				show(r.floor)
			end) } }
			view.list.rows[1].floor, view.list.rows[2].floor = 1, 2
		end)
	end
	return view
end

-- A click runs the button's handler and the hooks added to it (our overlay's), as the client does.
local function click(b)
	mock.FireScript(b, "OnClick", "LeftButton", false)
end

local savedLast -- the plans last chosen per instance before a case (other tests leave some)
local function setup(o)
	boot()
	O.Reset()
	_G.OpenMapDungeonView = nil
	local root = installOpenMap()
	ns.db.settings.openmapOverlay = false
	ns.db.settings.gamepad = "auto"
	ns.Compat.ResetGamepad()
	ns.db.ui.selectedPlan = DEADMINES
	savedLast = savedLast or ns.db.ui.lastPlans
	ns.db.ui.lastPlans = {}
	local view = (not o or not o.noView) and fakeView(root, o) or nil
	return root, view
end

local function teardown()
	O.Reset()
	if savedLast then
		ns.db.ui.lastPlans, savedLast = savedLast, nil
	end
	_G.OpenMapDungeonView, _G.OpenMapAPI = nil, nil
	mock.inCombat = false
	mock.RemoveProviders()
	ns.Providers.Reset()
	ns.db.settings.openmapOverlay = false
	ns.db.settings.gamepad = "auto"
	ns.Compat.ResetGamepad()
end

local function case(name, fn)
	T.case(name, function()
		local ok, err = pcall(fn)
		teardown()
		assert(ok, err)
	end)
end

local function enable()
	O.SetEnabled(true)
	mock.Advance(0) -- OpenMap sets the floor just after showing its view: the drawing comes a frame later
end

case("OpenMap overlay: off by default; nothing is made or hooked", function()
	local _, view = setup()
	T.eq(ns.Defaults.settings.openmapOverlay, false, "default off")
	O.Init()
	mock.Advance(0)
	local drawn, frame, state = O.Drawn()
	T.eq(state.mode, "off")
	T.eq(drawn, nil)
	T.eq(frame, nil, "no frame of ours")
	T.eq(view:GetScript("OnShow"), nil, "OpenMap's view not hooked")
	T.ok(O.Status():find("off", 1, true), O.Status())
end)

case("OpenMap overlay: draws the selected plan on the game's map of the same floor (tile file IDs)", function()
	local _, view = setup()
	enable()
	local drawn, frame = O.Drawn()
	T.ok(drawn, "drawn: " .. O.Status())
	T.eq(drawn.floor, 1)
	T.eq(drawn.mode, "tile", "the same picture: drawn as it is")
	T.ok(drawn.counts.lines > 0, "route lines")
	T.ok(drawn.counts.stops > 0, "numbered stops")
	-- A child of OpenMap's page with all its points on it: pan and zoom carry it, the port clips it.
	T.eq(frame:GetParent(), view.page, "child of the page")
	local pts = frame._points
	T.eq(#pts, 2)
	T.eq(pts[1][1], "TOPLEFT")
	T.eq(pts[1][2], view.page)
	T.eq(pts[2][1], "BOTTOMRIGHT")
	T.eq(pts[2][2], view.page)
	T.eq(frame:GetFrameLevel(), view.page:GetFrameLevel() + O.LEVEL, "just over the picture, under OpenMap's pins")
	T.eq(frame._mouse, false, "no mouse: OpenMap's map keeps its clicks")
	T.ok(frame:IsShown())
	-- The route's lines start where the plan says on the page: plan (x, y) -> (x * width, -y * height).
	local route
	for _, r in ipairs(ns.DB.GetPlan(DEADMINES).routes) do
		if r.floor == 1 and #r.points >= 2 then
			route = route or r
		end
	end
	T.ok(route, "a route on floor 1")
	local want = { route.points[1][1] * 1002, -route.points[1][2] * 668 }
	local found = false
	for _, l in ipairs(O.Holder().pools.lines) do
		local p = l._startPoint
		if l:IsShown() and p and p[2] == frame and math.abs(p[3] - want[1]) < 6 and math.abs(p[4] - want[2]) < 6 then
			found = true
		end
	end
	T.ok(found, "a line from the route's first point")
	-- The numbered stops as the main map draws them (UI/MapRoutes.lua DrawRouteStops): rings in the colour along the
	-- route at their place (MapRoutes.StopColor), no mouse.
	local stop = O.Holder().pools.points[1]
	T.ok(stop and stop:IsShown(), "a stop drawn")
	local r, g, b = ns.MapRoutes.StopColor(ns.Util.FindById(ns.DB.GetPlan(DEADMINES).routes, stop.routeId), stop.pointIndex)
	local v = stop.ring._vertex
	T.ok(math.abs(v[1] - r) < 1e-6 and math.abs(v[2] - g) < 1e-6 and math.abs(v[3] - b) < 1e-6, "the ring's colour")
	T.eq(stop._mouse, false)
	T.ok(O.Status():find("floor buttons hooked", 1, true), O.Status())
end)

case("OpenMap overlay: floor changes through its arrows and its floor list follow at once", function()
	local _, view = setup()
	enable()
	click(view.next)
	T.eq(O.Drawn().floor, 2, "next floor")
	click(view.prev)
	T.eq(O.Drawn().floor, 1, "previous floor")
	-- The list is made when its button is first clicked; its rows are hooked then.
	click(view.floorButton)
	click(view.list.rows[2])
	T.eq(O.Drawn().floor, 2, "picked from the list")
	-- Zoom: the page's size changes, the drawing follows.
	local before = O.Drawn().key
	view.page:SetSize(2004, 1336)
	mock.FireScript(view.page, "OnSizeChanged")
	T.ok(O.Drawn().key ~= before, "redrawn for the new size")
	-- Nothing changed: no redraw (the same drawing).
	local same = O.Drawn()
	mock.FireScript(view.page, "OnSizeChanged")
	T.eq(O.Drawn(), same, "unchanged: not drawn again")
end)

case("OpenMap overlay: floor pictures the side panel makes later are hooked once its tab is clicked", function()
	local _, view = setup()
	-- The side panel (BuildView): its tabs; the Floors tab's pictures are made as the panel fills (FillSide).
	local side = CreateFrame("Frame", nil, view)
	side.pool = { thumb = {} }
	side.tabs = { button(side, function()
		for i = 1, #view.floors do
			local w = side.pool.thumb[i] or button(side, function(self)
				view.floor = self.item.floor
			end)
			w.item = { kind = "thumb", floor = i }
			side.pool.thumb[i] = w
		end
	end) }
	view.side = side
	enable()
	T.eq(O.Drawn().floor, 1)
	T.eq(#side.pool.thumb, 0, "no pictures yet")
	click(side.tabs[1]) -- the Floors tab: the pictures are made now
	mock.Advance(0) -- hooked a frame later
	click(side.pool.thumb[2]) -- at zoom 1: the page keeps its size, nothing else tells
	T.eq(O.Drawn().floor, 2, "the picture's floor drawn")
	click(side.pool.thumb[1])
	T.eq(O.Drawn().floor, 1)
end)

case("OpenMap overlay: without floor buttons, a check at most 4 times a second while shown, none while hidden", function()
	local _, view = setup({ noButtons = true })
	enable()
	T.eq(O.Drawn().floor, 1)
	T.ok(O.Status():find("4 times a second", 1, true), O.Status())
	view.floor = 2
	mock.Advance(O.POLL)
	T.eq(O.Drawn().floor, 2, "the check saw the new floor")
	view:Hide()
	local _, frame, state = O.Drawn()
	T.eq(state.mode, "hidden")
	T.ok(not frame:IsShown(), "hidden with the view")
	view.floor = 1
	for _ = 1, 8 do
		mock.Advance(O.POLL)
	end
	T.eq(O.Drawn().floor, 2, "nothing ran while hidden")
	view:Show()
	mock.Advance(0)
	T.eq(O.Drawn().floor, 1, "shown again: drawn for the floor shown")
	T.ok(frame:IsShown())
end)

case("OpenMap overlay: plan by the dungeon shown; the plan last chosen there when another is selected", function()
	setup()
	local plan, how = O.PlanFor("Deadmines")
	T.eq(plan and plan.id, DEADMINES)
	T.eq(how, "selected")
	ns.db.ui.selectedPlan = "b:hall-of-thanes"
	ns.db.ui.lastPlans.deadminesTest = DEADMINES
	plan, how = O.PlanFor("The Deadmines")
	T.eq(plan and plan.id, DEADMINES, "remembered for this dungeon")
	T.eq(how, "last")
	ns.db.ui.lastPlans.deadminesTest = nil
	T.eq(O.PlanFor("Deadmines"), nil, "no plan for it: nothing")
	enable()
	T.eq(O.Drawn(), nil)
	T.ok(O.Status():find("no plan for Deadmines", 1, true), O.Status())
end)

case("OpenMap overlay: a drawn floor matched by name is placed through OpenMap's boss positions, or not at all", function()
	local root = setup({ noView = true })
	local plan = ns.DB.GetPlan(DEADMINES)
	local snap = { floor = 2, floors = root.MapDungeonDrawn[36], source = "drawn", inst = { mapID = 36, name = "Deadmines" } }
	-- No boss positions: nothing to line up with, nothing drawn.
	local place, why = ns.Providers.Call("openMap", "Placement", plan, snap)
	T.eq(place, nil)
	T.ok(why and why:find("no boss positions", 1, true), tostring(why))
	-- The same positions: drawn as they are.
	root.MapDungeonBosses[36] = pinsFrom(plan, 2, 1, 0)
	place = ns.Providers.Call("openMap", "Placement", plan, snap)
	T.eq(place.floor, 2, "Ironclad Cove by name")
	T.eq(place.how, "name")
	T.eq(place.mode, "same")
	-- Scaled and moved: drawn through the fitted transform.
	root.MapDungeonBosses[36] = pinsFrom(plan, 2, 0.8, 0.1)
	place = ns.Providers.Call("openMap", "Placement", plan, snap)
	T.eq(place.mode, "fit")
	T.ok(math.abs(place.xf.sx - 0.8) < 1e-3 and math.abs(place.xf.tx - 0.1) < 1e-3, "the fit")
	-- Positions that agree with nothing: no guessed placement.
	local wild = pinsFrom(plan, 2, 1, 0)
	local k = 0
	for _, p in pairs(wild) do
		k = k + 1
		p[2], p[3] = (k * 0.37) % 1, (k * 0.61) % 1
	end
	root.MapDungeonBosses[36] = wild
	place, why = ns.Providers.Call("openMap", "Placement", plan, snap)
	T.eq(place, nil)
	T.ok(why:find("do not line up", 1, true), why)
	-- Boss positions on its minimap floors are OpenMap's "minimap:<id>" list.
	root.MapDungeonMinimap = { [36] = { { tiles = tiles("m1", "m"), name = "The Deadmines" } } }
	root.MapDungeonBosses["minimap:36"] = pinsFrom(plan, 1, 1, 0)
	place = ns.Providers.Call("openMap", "Placement", plan,
		{ floor = 1, floors = root.MapDungeonMinimap[36], inst = { mapID = 36, name = "Deadmines" } })
	T.eq(place and place.mode, "same", "minimap floor recognised by its table and placed by its own boss list")
	-- One boss matching of several OpenMap places on the floor: not enough.
	root.MapDungeonBosses[36] = { Gilnid = { 2, 0.1248, 0.759 }, ["Someone Else"] = { 2, 0.5, 0.5 } }
	place, why = ns.Providers.Call("openMap", "Placement", plan, snap)
	T.eq(place, nil)
	T.ok(why:find("only one", 1, true), why)
	-- OpenMap's blank page (a dungeon it has no map of) is never matched, not even by position.
	place, why = ns.Providers.Call("openMap", "Placement", plan,
		{ floor = 1, floors = { { blank = true } }, inst = { mapID = 36, name = "Deadmines" } })
	T.eq(place, nil)
	T.ok(why:find("no map of this floor", 1, true), why)
end)

case("OpenMap overlay: an error in the placement stays the overlay's; the OpenMap adapter keeps working", function()
	setup()
	local adapter = ns.Providers.Adapter("openMap")
	local real = adapter.Placement
	adapter.Placement = function()
		error("broken placement")
	end
	local ok, err = pcall(enable)
	adapter.Placement = real
	assert(ok, err)
	T.eq(O.Drawn(), nil)
	T.ok(O.Status():find("placement failed", 1, true), O.Status())
	T.ok(ns.Providers.Get("openMap"), "the adapter is still active for our own map")
end)

case("OpenMap overlay: the alignment carries the drawing on the view", function()
	local root = setup({ noView = true })
	local plan = ns.DB.GetPlan(DEADMINES)
	root.MapDungeonBosses[36] = pinsFrom(plan, 2, 0.8, 0.1)
	local view = fakeView(root, { source = "drawn", floors = root.MapDungeonDrawn[36] })
	view.floor = 2
	enable()
	local drawn, frame = O.Drawn()
	T.ok(drawn, O.Status())
	T.eq(drawn.mode, "fit")
	T.eq(drawn.floor, 2)
	-- A boss marker goes through the fit: x' = 0.8 x + 0.1 of the page.
	local m = plan.markers[3]
	T.eq(m.label, "Gilnid")
	local hit = false
	for _, b in ipairs(O.Holder().pools.pins) do
		local p = b:IsShown() and b._points and b._points[1]
		if p and p[2] == frame and math.abs(p[4] - (m.x * 0.8 + 0.1) * 1002) < 0.5
			and math.abs(p[5] + (m.y * 0.8 + 0.1) * 668) < 0.5 then
			hit = true
		end
	end
	T.ok(hit, "Gilnid's marker where the fit puts it")
	-- OpenMap pins the floor's five bosses itself: the plan's own boss markers stay off them.
	local withBosses = drawn.counts.markers
	view.bossPins = {}
	for name in pairs(root.MapDungeonBosses[36]) do
		local pin = CreateFrame("Button", nil, view.page)
		pin.name = name
		view.bossPins[#view.bossPins + 1] = pin
	end
	view.page:SetSize(1000, 668)
	mock.FireScript(view.page, "OnSizeChanged")
	T.eq(O.Drawn().counts.markers, withBosses - 5, "the five boss markers left to OpenMap's pins")
	T.ok(frame:IsShown())
end)

case("OpenMap overlay: what does not fit degrades with a reason in /dp debug, never an error", function()
	setup({ noView = true })
	enable()
	T.eq(O.Drawn(), nil)
	T.ok(O.Status():find("waiting for OpenMap's dungeon map", 1, true), O.Status())
	-- A frame by that name without its picture frame: unavailable.
	CreateFrame("Frame", "OpenMapDungeonView", UIParent)
	O.Look()
	local _, _, state = O.Drawn()
	T.eq(state.mode, "unavailable")
	T.ok(O.Status():find("unavailable (the view has no picture frame (page))", 1, true), O.Status())
	-- The view with a floor list of another shape: nothing drawn, said why.
	_G.OpenMapDungeonView = nil
	local root = _G.OpenMap
	local view = fakeView(root)
	O.SettingChanged()
	view.floors = "broken"
	mock.Advance(0)
	T.eq(O.Drawn(), nil)
	T.ok(O.Status():find("no floor list", 1, true), O.Status())
	view.floors, view.floor = root.MapDungeonMaps[36], nil
	mock.FireScript(view.page, "OnSizeChanged")
	T.eq(O.Drawn(), nil, "no floor shown yet")
	T.ok(O.Status():find("no floor shown", 1, true), O.Status())
	-- The debug command prints the line.
	local lines, realPrint = {}, print
	_G.print = function(text)
		lines[#lines + 1] = tostring(text)
	end
	local ok = pcall(ns.Slash.Debug)
	_G.print = realPrint
	T.ok(ok, "debug runs")
	T.ok(table.concat(lines, "\n"):find("OpenMap overlay:", 1, true), "reported")
end)

case("OpenMap overlay: found when the first dungeon map opens after its world map was used; the search stops itself", function()
	-- OpenMap makes its view when an entrance is clicked: no card shows and no callback fires then. The callbacks
	-- before it (the world map shown, moved) start the search; it keeps ticking while they come several a second.
	local root = setup({ noView = true })
	enable()
	_G.OpenMapAPI.fire("OpenMap_StitchedChanged", true)
	for _ = 1, 6 do
		mock.Advance(0.1)
		_G.OpenMapAPI.fire("OpenMap_ViewChanged", 0.5, 0.5, 2)
	end
	local view = fakeView(root) -- the click: built and shown, after the last callback
	mock.Advance(O.POLL)
	mock.Advance(0)
	local _, _, state = O.Drawn()
	T.eq(state.mode, "shown", "found and shown: " .. O.Status())
	T.ok(O.Drawn(), "drawn")
	T.eq(type(view:GetScript("OnShow")), "function", "its show hooked")
	-- The dungeon card asking for our section starts the search too.
	teardown()
	root = setup({ noView = true })
	enable()
	O.CardShown()
	mock.Advance(O.POLL)
	fakeView(root)
	mock.Advance(O.POLL)
	mock.Advance(0)
	T.ok(O.Drawn(), "found from the card")
	-- Not found within the search: no tick keeps running.
	teardown()
	setup({ noView = true })
	enable()
	_G.OpenMapAPI.fire("OpenMap_ViewChanged", 0.5, 0.5, 2)
	for _ = 1, math.ceil(O.WAIT / O.POLL) + 4 do
		mock.Advance(O.POLL)
	end
	fakeView(_G.OpenMap)
	for _ = 1, 4 do
		mock.Advance(O.POLL)
	end
	local _, _, after = O.Drawn()
	T.eq(after.mode, "waiting", "the search ended: nothing looked again on a timer")
	-- The next occasion (entering the world, OpenMap's callbacks, its menu) finds it.
	O.Look()
	mock.Advance(0)
	local _, _, found = O.Drawn()
	T.eq(found.mode, "shown")
end)

case("OpenMap overlay: off with the gamepad interface style", function()
	local _, view = setup()
	ns.db.settings.gamepad = "on"
	ns.Compat.ResetGamepad()
	enable()
	local drawn, frame, state = O.Drawn()
	T.eq(state.mode, "off")
	T.eq(drawn, nil)
	T.eq(frame, nil)
	T.eq(view:GetScript("OnShow"), nil, "not hooked")
	T.ok(O.Status():find("gamepad", 1, true), O.Status())
end)

case("OpenMap overlay: no frame is made in combat; drawn when combat ends; shown and hidden in combat", function()
	local _, view = setup()
	mock.inCombat = true
	enable()
	local drawn, frame = O.Drawn()
	T.eq(drawn, nil)
	T.eq(frame, nil, "nothing made in combat")
	T.ok(O.Status():find("end of combat", 1, true), O.Status())
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	drawn, frame = O.Drawn()
	T.ok(drawn, "drawn after combat: " .. O.Status())
	-- In combat the drawing made before hides and shows with the view.
	mock.inCombat = true
	view:Hide()
	T.ok(not frame:IsShown())
	view:Show()
	mock.Advance(0)
	T.ok(frame:IsShown(), "shown again unchanged")
	-- A change in combat waits.
	click(view.next)
	T.ok(not frame:IsShown(), "hidden until combat ends")
	mock.inCombat = false
	mock.FireEvent("PLAYER_REGEN_ENABLED")
	T.eq(O.Drawn().floor, 2)
	T.ok(frame:IsShown())
end)

T.case("OpenMap overlay: Step ignores ticks of phases that ended", function()
	local ctx = { enabled = true, attached = true, shown = false, poll = true, now = 0 }
	local s, e = O.Step({ mode = "hidden", poll = true }, "tick", ctx)
	T.eq(s.mode, "hidden")
	T.eq(#e, 0, "a tick while hidden does nothing")
	local _, ran = O.Step({ mode = "waiting", waitUntil = 5 }, "waitTick", { enabled = true, now = 6 })
	T.eq(#ran, 0, "the search ran out")
	s, e = O.Step({ mode = "shown" }, "change", { enabled = false })
	T.eq(s.mode, "off")
	T.eq(e[1], "clear")
end)
