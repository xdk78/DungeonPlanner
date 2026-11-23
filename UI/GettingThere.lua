-- Getting there: where an instance is and how to reach it. One card, drawn into a document (W.Document) by
-- GettingThere.Fill: the zone, the area the entrance lies in and the zone's faction, the entrance's coordinates, the
-- nearest flight masters for each faction with the way from them, boats and zeppelins when the player is on another
-- continent, Forever's summoning stones, the level range against the player's level and the group size, and (outdoors
-- only: the client gives no position inside instances) the player's distance and direction. Under it: Show on world
-- map, Navigate (the best of Polestar, TomTom and the game's own pin; Data/Navigation.lua) with the others in its
-- menu. The Prep section shows the card beside the quests; the home table's "Getting there" opens it in its own small
-- window (GettingThere.Open), also without a plan.

local _, ns = ...
local GT = ns:NewModule("GettingThere")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

-- Words looked up when drawn (the language can change after load).
local DIRECTION = {
	N = function() return L["north"] end, NE = function() return L["north-east"] end,
	E = function() return L["east"] end, SE = function() return L["south-east"] end,
	S = function() return L["south"] end, SW = function() return L["south-west"] end,
	W = function() return L["west"] end, NW = function() return L["north-west"] end,
}
local APPROACH = {
	cave = function() return L["a cave"] end, building = function() return L["a building"] end,
	mountain = function() return L["the mountain"] end, open = function() return L["open ground"] end,
	underwater = function() return L["the water"] end, ship = function() return L["a ship"] end,
	tower = function() return L["a tower"] end,
}
local FACTION = {
	alliance = function() return L["Alliance territory"] end, horde = function() return L["Horde territory"] end,
	contested = function() return L["Contested territory"] end, neutral = function() return L["Neutral territory"] end,
}
local function word(t, k)
	return t[k] and t[k]() or ""
end

local function color(role, text)
	local r, g, b = S.Color(role)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5), text)
end
GT.Color = color

function GT.Direction(key)
	return word(DIRECTION, key)
end

function GT.Yards(yards)
	local n = math.floor(yards / 10 + 0.5) * 10
	if n >= 1000 then
		return string.format(L["%d,%03d yd"], math.floor(n / 1000), n % 1000)
	end
	return string.format(L["%d yd"], n)
end

local function coords(x, y)
	return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- The target's facts: { rec, ent, name, kind, lo, hi } for a plan or a home entry.
function GT.Facts(target)
	local rec = ns.Travel.For(target)
	local inst = type(target.instance) == "table" and target.instance or target
	local entry = type(target.instance) == "table" and ns.UI.EntryForPlan(target) or target
	local lo, hi = ns.Instances.LevelRange(entry)
	return { rec = rec, ent = rec and ns.Travel.Entrance(rec) or nil, name = ns.Names.Instance(inst),
		kind = inst.kind, lo = lo, hi = hi }
end

-- The card's lines: { { style, text } } for W.Document (pure over the facts and what the client says). live: the card
-- sits under the live map (the window), which shows the distance itself.
function GT.Lines(target, live)
	local f = GT.Facts(target)
	local out = {}
	local function add(style, text)
		out[#out + 1] = { style, text }
	end
	local rec, ent = f.rec, f.ent
	local faction = ns.PrepInfo.Faction()
	if not rec then
		add("muted", L["Dungeon Planner has no travel facts for this instance."])
		return out, f
	end
	-- Where.
	-- The zone in the player's language: the map the entrance is placed on, else the bundled zone map's name (the
	-- English name only when the client has neither), then the research's area inside it.
	local map = (ent and ent.uiMapID) or rec.zm
	local where = ns.Travel.Where(rec, ent and ent.uiMapID)
	local continent = map and ns.Travel.ContinentName(map)
	add("text", continent and (where .. "  •  " .. continent) or where)
	if rec.fac then
		local enemy = faction and ((rec.fac == "alliance" and faction == "horde") or (rec.fac == "horde"
			and faction == "alliance"))
		local text = word(FACTION, rec.fac)
		add("muted", enemy and color("warning", text .. "  •  " .. L["enemy territory for you"]) or text)
	end
	if ent and ent.x then
		local line = string.format(L["Entrance: %s on the map of %s"], coords(ent.x, ent.y),
			ns.Instances.MapName(ent.uiMapID) or ns.Travel.ZoneName(rec))
		if rec.how then
			line = line .. "  •  " .. string.format(L["through %s"], word(APPROACH, rec.how))
		end
		add("text", line)
	elseif rec.how then
		add("text", string.format(L["Entered through %s"], word(APPROACH, rec.how)))
	end
	if rec.hint then
		add("muted", rec.hint)
	end
	if rec.stone then
		add("text", string.format(L["Summoning stone: %s, %s"], ns.Travel.StoneZone(rec.stone),
			string.format("%.1f, %.1f", rec.stone.x, rec.stone.y)))
	end
	-- Level and group.
	local level = ns.PrepInfo.Level()
	if f.lo then
		local range = f.lo == f.hi and tostring(f.lo) or (f.lo .. "-" .. (f.hi or f.lo))
		local r, g, b = S.LevelColor(f.lo, f.hi)
		local hex = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
			math.floor(b * 255 + 0.5))
		local line = string.format(L["Levels %s"], hex .. range .. "|r")
		if level then
			line = line .. "  •  " .. string.format(L["you are %d"], level)
		end
		add("text", line .. "  •  " .. (f.kind == "raid" and L["a raid group"] or L["a party of 5"]))
	end
	-- How to get there: each faction's nearest flight master, the player's own first.
	if ent and ent.wx then
		add("label", L["How to get there"])
		local order = faction == "horde" and { "horde", "alliance" } or { "alliance", "horde" }
		for _, side in ipairs(order) do
			local near = ns.Travel.Nearest(rec, side, 1)[1]
			local who = side == "alliance" and L["Alliance"] or L["Horde"]
			local text
			if near then
				text = string.format(L["%s: fly to %s, then go %s (about %s)."], who, near.name,
					GT.Direction(near.dir), GT.Yards(near.yards))
			else
				text = string.format(L["%s: no flight master on this continent."], who)
			end
			add(side == faction and "text" or "muted", text)
		end
	end
	-- Where the player is (outdoors only). With the live map (the window), its own line keeps the distance and
	-- direction current, so the card leaves them out and keeps Polestar's estimate and the boats and zeppelins.
	local player = ns.Travel.Player()
	if not player then
		if not live then
			add("muted", L["Distance and direction show outdoors (the game gives no position inside instances)."])
		end
	elseif ent then
		local yards, why = ns.Travel.Distance(ent, player)
		if yards and yards > 0 then
			local eta = ent.uiMapID and ns.Navigation.Estimate(ent.uiMapID, ent.x, ent.y)
			eta = eta and string.format(L["About %d min with Polestar."], math.max(1, math.floor(eta / 60 + 0.5)))
			if not live then
				local line = string.format(L["You are %s away; it lies %s."], GT.Yards(yards), GT.Direction(why))
				add("text", eta and (line .. "  " .. eta) or line)
			elseif eta then
				add("text", eta)
			end
		elseif yards then
			if not live then
				add("text", L["You are at the entrance."])
			end
		elseif why == "continent" then
			if not live then
				add("text", color("warning", L["You are on another continent."]))
			end
			local ships = ns.Prep.Crossings(ns.Travel.Transports(), player.continent, ent.continent, faction)
			if #ships > 0 then
				local names = {}
				for i, t in ipairs(ships) do
					if i > 4 then
						break
					end
					names[#names + 1] = t.route
				end
				add("muted", string.format(L["Boats and zeppelins there: %s"], table.concat(names, ", ")))
			end
		end
	end
	return out, f
end

-- The point list Navigate sends: the entrance (TomTom also gets the nearest flight master first).
local function points(f, withFlight)
	local ent = f.ent
	if not (ent and ent.uiMapID and ent.x) then
		return nil
	end
	local list = {}
	if withFlight and f.rec then
		local near = ns.Travel.Nearest(f.rec, ns.PrepInfo.Faction(), 1)[1]
		local map, x, y
		if near then
			map, x, y = ns.Travel.NodeOnMap(near.id)
		end
		if map and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			list[#list + 1] = { map, x, y, near.name }
		end
	end
	list[#list + 1] = { ent.uiMapID, ent.x, ent.y, f.name }
	return list
end
GT.Points = points

-- The entrance on the world map: the game's pin, then the map on its zone (Navigation.ShowOnMap: nothing in combat,
-- no map with the gamepad interface style). The card's "Show on world map" and the header's Show location button.
-- False when the facts have no entrance on a map.
function GT.ShowEntrance(facts)
	local p = facts and points(facts)
	if not p then
		return false
	end
	ns.Navigation.ShowOnMap(p[#p][1], p[#p][2], p[#p][3])
	return true
end

-- The header's Show location button for a plan or a home entry: { state, facts, zone, canPin, canOpen, gamepad }.
-- state: "ready", "combat" or "dead" (Navigation.BlockReason), "unknown" (no travel record for the instance) or "none"
-- (no target). canPin: the game can pin the entrance; canOpen: the world map can open on it (not with the gamepad
-- interface style); with neither, a click opens the Getting there window instead.
function GT.Location(target)
	if type(target) ~= "table" then
		return { state = "none" }
	end
	local facts = GT.Facts(target)
	if not facts.rec then
		return { state = "unknown", facts = facts }
	end
	local ent, p = facts.ent, points(facts)
	local m = rawget(_G, "C_Map")
	local gamepad = ns.Compat.Gamepad()
	return { state = ns.Navigation.BlockReason() or "ready", facts = facts, gamepad = gamepad,
		zone = ns.Travel.Where(facts.rec, ent and ent.uiMapID),
		canPin = p ~= nil and ns.Navigation.CanPin(p[#p][1]),
		canOpen = p ~= nil and m ~= nil and type(m.OpenWorldMap) == "function" and not gamepad }
end

-- A click on that button: the world map (left), or the Getting there window (right-click, Shift-click, or an
-- entrance the game can neither pin nor show). Nothing while blocked.
function GT.Locate(target, window)
	local loc = GT.Location(target)
	if loc.state ~= "ready" then
		return false
	end
	if window or not (loc.canPin or loc.canOpen) then
		GT.Open(target)
		return "window"
	end
	GT.ShowEntrance(loc.facts)
	return "map"
end

-- The buttons under the card: Show on world map, Navigate (and its menu of the other ways).
function GT.Actions(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(SZ.control)
	bar.map = W.Button(bar, L["Show on world map"], "outline", function()
		GT.ShowEntrance(bar.facts)
	end)
	bar.map:SetPoint("LEFT")
	bar.nav = W.Button(bar, L["Navigate"], "outline", function(self)
		local targets = bar.targets or {}
		if #targets == 0 or not bar.facts then
			return
		end
		if IsShiftKeyDown and IsShiftKeyDown() and #targets > 1 then
			local items = { { title = L["Navigate with"] } }
			for _, t in ipairs(targets) do
				items[#items + 1] = { t.title, function()
					ns.Navigation.Go(t.id, points(bar.facts, t.id == "tomtom"))
				end }
			end
			W.Menu(self, items)
			return
		end
		local t = targets[1]
		ns.Navigation.Go(t.id, points(bar.facts, t.id == "tomtom"))
	end)
	bar.nav:SetPoint("LEFT", bar.map, "RIGHT", SP.sm, 0)
	bar.more = W.Button(bar, "...", "outline", function(self)
		local items = { { title = L["Navigate with"] } }
		for _, t in ipairs(bar.targets or {}) do
			items[#items + 1] = { t.title, function()
				ns.Navigation.Go(t.id, points(bar.facts, t.id == "tomtom"))
			end }
		end
		W.Menu(self, items)
	end, SZ.control + 6)
	bar.more:SetPoint("LEFT", bar.nav, "RIGHT", SP.xs, 0)
	W.SetTooltip(bar.more, L["Navigate with"], L["Pick which addon or the game's own map pin guides you there."])

	function bar:Set(target, facts)
		self.target, self.facts = target, facts
		local p = facts and points(facts)
		local map = p and p[#p][1]
		self.targets = map and ns.Navigation.Targets(map) or {}
		self.map:SetDisabled(not p)
		self.nav:SetDisabled(#self.targets == 0)
		self.more:SetShown(#self.targets > 1)
		local best = self.targets[1]
		self.nav:SetLabel(best and string.format(L["Navigate: %s"], best.title) or L["Navigate"])
		W.SetTooltip(self.nav, L["Navigate"], best and string.format(
			L["Sends the entrance to %s. The \"...\" button lists the other ways."], best.title)
			or L["No way to set a waypoint here: the game cannot pin this map."])
	end
	return bar
end

-- Draw the card into a document; `bar` (GT.Actions) is placed under it.
function GT.Fill(doc, target, bar, heading, live)
	local lines, facts = GT.Lines(target, live)
	if heading ~= false then
		doc:Add("heading", L["Getting there"])
	end
	for _, l in ipairs(lines) do
		doc:Add(l[1], l[2])
	end
	if bar then
		bar:Set(target, facts)
		doc:Space(SP.sm)
		doc:Place(bar, SZ.control, true)
	end
	return facts
end

-- The small window (home table's "Getting there", the Prep card's Pop out). Escape closes it like the other windows.
-- While shown it redraws on PREP_CHANGED (level, group, zone changes; Data/PrepInfo.lua).
local window
GT.MIN_W, GT.MIN_H = 320, 460
function GT.Open(target)
	if not window then
		local saved = ns.db.ui.travel
		-- At least the live map, its line and the first lines of the card under it.
		window = W.Window("DungeonPlannerTravelFrame", L["Getting there"], saved, GT.MIN_W, GT.MIN_H, { compact = true })
		-- Over the planner it was opened from (both are movable; Escape closes this one first).
		window:SetFrameStrata("DIALOG")
		local ins = window.insets
		-- The live map (UI/TravelMap.lua): outdoors, the player's arrow on the entrance's zone map, updated while shown.
		window.map = ns.TravelMap.Create(window)
		window.map:SetPoint("TOPLEFT", ins.left + SP.md, -(ins.top + SP.sm))
		-- A fixed width from the window's (not a second anchor), so pins are placed right on the first draw.
		local function fit()
			window.map:SetWidth(math.max(100, (window:GetWidth() or 0) - ins.left - ins.right - 2 * SP.md))
		end
		fit()
		window:HookScript("OnSizeChanged", fit)
		window.live = W.Text(window, "caption", "ink")
		window.live:SetPoint("TOPLEFT", window.map, "BOTTOMLEFT", 0, -SP.xs)
		window.live:SetPoint("RIGHT", window.map, "RIGHT")
		ns.TravelMap.Attach(window.map, window.live)
		window.doc = W.Document(window)
		window.doc:SetPoint("TOPLEFT", window.live, "BOTTOMLEFT", 0, -SP.sm)
		window.doc:SetPoint("BOTTOMRIGHT", -(ins.right + SP.sm), ins.bottom + SP.md)
		window.bar = GT.Actions(window.doc.content)
		ns.PrepInfo.Watch(window, function()
			return window:IsShown()
		end)
		ns:On("PREP_CHANGED", window, function()
			if window:IsShown() then
				GT.Refresh()
			end
		end)
		window:HookScript("OnShow", function(self)
			ns.TravelMap.Show(self.target)
		end)
		window:HookScript("OnHide", function()
			ns.TravelMap.Hide()
		end)
	end
	window.target = target
	GT.Refresh()
	if window:IsShown() then
		ns.TravelMap.Show(target)
	end
	window:Show()
	return window
end

function GT.Refresh()
	if not (window and window.target) then
		return
	end
	local doc = window.doc
	doc:Begin(window.target) -- live updates (PREP_CHANGED) keep the offset; another place starts at the top
	doc:Add("title", GT.Facts(window.target).name)
	GT.Fill(doc, window.target, window.bar, false, true)
	doc:Finish()
end

function GT.Window()
	return window
end
