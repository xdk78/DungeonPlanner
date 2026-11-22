-- The live "Getting there" map, outdoors only: the entrance's zone map from the game's own map art (C_Map), the
-- entrance, the nearest flight masters and a summoning stone as pins, and the player as an arrow turned to their
-- facing, with the straight-line distance and direction under it. It sits at the top of the Getting there window
-- (UI/GettingThere.lua). The lifecycle is Model/TravelLive.lua's state machine: a 10 Hz ticker runs only while the
-- window shows and the client gives a position (never inside an instance, where it gives none); going from outside
-- into the target instance opens its plan and run mode. The instance is recognised by its instance ID (and a wing by
-- its floor map), never by its localized name. Loading screens also teach the entrance: the last outdoor spot before
-- one that ends inside an instance is kept per account (TravelLive.Learn) when it lies near that instance's bundled
-- entrance, and preferred over the bundled spot; /dp entrances reset forgets them.
--
-- Everything is drawn on our own frames (parented to our window); nothing touches the world map or the minimap.

local _, ns = ...
local TravelMap = ns:NewModule("TravelMap")
local W, L = ns.Widgets, ns.L
local Live = ns.TravelLive

TravelMap.HEIGHT = 170
TravelMap.PIN = 18
local MAX_FLIGHTS = 4

-- The map widget ------------------------------------------------------------------------------------------------------

function TravelMap.Create(parent)
	local f = W.Panel(parent, "mapBackdrop", "border")
	f:SetHeight(TravelMap.HEIGHT)
	if f.SetClipsChildren then
		f:SetClipsChildren(true)
	end
	f.canvas = CreateFrame("Frame", nil, f)
	f.tiles = {}
	f.flights = {}
	local function pin(art, size)
		local t = f.canvas:CreateTexture(nil, "OVERLAY")
		t:SetSize(size or TravelMap.PIN, size or TravelMap.PIN)
		ns.Art.Set(t, art)
		t:Hide()
		return t
	end
	f.entrance = pin("kind_entrance", TravelMap.PIN + 4)
	f.stone = pin("travelStone")
	for i = 1, MAX_FLIGHTS do
		f.flights[i] = pin("travelFlight", TravelMap.PIN - 2)
	end
	f.player = pin("travelPlayer", TravelMap.PIN + 6)
	f.player:SetDrawLayer("OVERLAY", 7)
	f.empty = W.Text(f, "caption", "muted")
	f.empty:SetPoint("CENTER")
	f.empty:SetText(L["No map art for this zone."])

	-- Fit the map's art (its aspect) into the frame, centred.
	function f:Layout()
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		local a = self.art
		local aw, ah = a and a.width or 1, a and a.height or 1
		local s = math.min(w / aw, h / ah)
		if s <= 0 or s ~= s then
			s = 1
		end
		self.scale = s
		self.cw, self.ch = aw * s, ah * s
		self.canvas:ClearAllPoints()
		self.canvas:SetSize(self.cw, self.ch)
		self.canvas:SetPoint("CENTER")
		for _, t in ipairs(self.tiles) do
			t:Hide()
		end
		if not a then
			return
		end
		local cols = math.ceil(a.width / a.tileWidth)
		for i, file in ipairs(a.textures) do
			local tex = self.tiles[i]
			if not tex then
				tex = self.canvas:CreateTexture(nil, "BACKGROUND")
				self.tiles[i] = tex
			end
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local tw = math.min(a.tileWidth, a.width - col * a.tileWidth)
			local th = math.min(a.tileHeight, a.height - row * a.tileHeight)
			tex:ClearAllPoints()
			tex:SetTexture(file)
			tex:SetSize(math.max(1, tw * s), math.max(1, th * s))
			tex:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", col * a.tileWidth * s, -row * a.tileHeight * s)
			tex:SetTexCoord(0, math.max(0, tw) / a.tileWidth, 0, math.max(0, th) / a.tileHeight)
			tex:Show()
		end
	end

	function f:Place(tex, x, y)
		if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
			tex:Hide()
			return
		end
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", self.canvas, "TOPLEFT", x * (self.cw or 0), -y * (self.ch or 0))
		tex:Show()
	end

	-- Each pin where it was last put (on resize only these are placed again).
	function f:Pin(tex, x, y)
		self.spots[tex] = { x, y }
		self:Place(tex, x, y)
	end

	-- The zone of the entrance and its pins (once per target).
	function f:SetTarget(rec, ent)
		self.rec, self.ent = rec, ent
		local map = ent and ent.uiMapID
		self.map = map
		self.spots = {}
		self.art = map and ns.Instances.MapArt(map) or nil
		self.empty:SetShown(self.art == nil)
		self:Layout()
		self:Pin(self.entrance, ent and ent.x, ent and ent.y)
		local stone = rec and rec.stone
		if stone and stone.map == map then
			self:Pin(self.stone, stone.x / 100, stone.y / 100)
		else
			self.stone:Hide()
		end
		local shown = 0
		for _, side in ipairs({ "alliance", "horde" }) do
			for _, near in ipairs(rec and map and ns.Travel.Nearest(rec, side, 2) or {}) do
				local m, x, y = ns.Travel.NodeOnMap(near.id, map)
				if m == map and shown < MAX_FLIGHTS then
					shown = shown + 1
					self.flights[shown].name = near.name
					self:Pin(self.flights[shown], x, y)
				end
			end
		end
		for i = shown + 1, MAX_FLIGHTS do
			self.flights[i]:Hide()
		end
	end

	-- The player: an arrow where they stand on the entrance's map (a position on a city, cave or other map below it is
	-- projected from world yards), turned to the facing (radians, 0 = north, counter-clockwise, as the client gives it).
	function f:SetPlayer(player)
		local x, y
		if player and player.uiMapID == self.map then
			x, y = player.x, player.y
		elseif player and player.wx and self.map then
			local m, px, py = ns.Travel.ToMap(player.continent, player.wx, player.wy, self.map)
			if m == self.map then
				x, y = px, py
			end
		end
		self.spots[self.player] = { x, y }
		self:Place(self.player, x, y)
		if x and player.facing and self.player.SetRotation then
			self.player:SetRotation(player.facing)
		end
	end

	-- A new size: the art laid out again and the pins put back where they were (nothing looked up again).
	f.spots = {}
	f:HookScript("OnSizeChanged", function(self)
		if not self.rec then
			return
		end
		self:Layout()
		for tex, at in pairs(self.spots) do
			self:Place(tex, at[1], at[2])
		end
	end)
	return f
end

-- The controller --------------------------------------------------------------------------------------------------------

local state = Live.New()
local ticker
local view -- { map = widget, line = font string, target = plan or entry, key = instance key }

-- The records of the instance the player is in (by its instance ID and map, not its localized name), or nil outdoors.
local function currentRecords()
	local here = ns.Instances.Current()
	if not here.inInstance then
		return nil
	end
	return ns.Travel.Here(here.instanceID, here.uiMapID)
end

local function keySet(records)
	if not records then
		return nil
	end
	local out = {}
	for _, rec in ipairs(records) do
		out[rec.key] = true
	end
	return out
end

-- The arrow, the distance and the direction. player: Travel.Player() (the tick passes the one it read). Nothing is
-- redrawn when the position, the facing and the line are the ones already shown.
function TravelMap.Draw(player)
	if not view then
		return
	end
	local ent = view.map.ent
	local text
	if not player then
		text = L["Distance and direction show outdoors (the game gives no position inside instances)."]
	elseif ent then
		local yards, dir = ns.Travel.Distance(ent, player)
		if yards and yards > 0 then
			text = string.format(L["You are %s away; it lies %s."], ns.GettingThere.Yards(yards), ns.GettingThere.Direction(dir))
		elseif yards then
			text = L["You are at the entrance."]
		elseif dir == "continent" then
			text = L["You are on another continent."]
		end
		if player.uiMapID ~= view.map.map and text then
			text = text .. "  " .. string.format(L["(you are in %s)"], ns.Instances.MapName(player.uiMapID) or "?")
		end
	end
	text = text or ""
	local last = view.drawn
	if last and player and last.map == player.uiMapID and last.x == player.x and last.y == player.y
		and last.facing == player.facing and last.text == text then
		return
	end
	view.drawn = player and { map = player.uiMapID, x = player.x, y = player.y, facing = player.facing, text = text }
		or nil
	view.map:SetPlayer(player)
	W.FitText(view.line, text)
end

-- Entering the target instance: its plan on the table and run mode open, the travel window closed.
function TravelMap.Arrive()
	local target = view and view.target
	if not target then
		return
	end
	local plan = target.instance and target or (ns.UI.DefaultPlanFor and ns.UI.DefaultPlanFor(target))
	if plan then
		ns.UI.SelectPlan(plan.id, true)
		ns.RunMode.Show()
	end
	local w = ns.GettingThere.Window()
	if w then
		w:Hide()
	end
end

-- player: the position the event was made from (Travel.Player, read once per event).
local function apply(effects, player)
	for _, e in ipairs(effects) do
		if e == "start" and not ticker and C_Timer and C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(Live.INTERVAL, function()
				local p = ns.Travel.Player()
				TravelMap.Dispatch({ kind = "tick", outdoors = p ~= nil, player = p })
			end)
		elseif e == "stop" and ticker then
			ticker:Cancel()
			ticker = nil
		elseif e == "draw" then
			TravelMap.Draw(player)
		elseif e == "arrived" then
			TravelMap.Arrive()
		end
	end
end

function TravelMap.Dispatch(event)
	local effects
	state, effects = Live.Step(state, event)
	apply(effects, event.player)
end

function TravelMap.State()
	return state, ticker ~= nil
end

-- The window's map: set the target (a plan or a home entry) and start (TravelLive "show").
function TravelMap.Attach(map, line)
	view = { map = map, line = line }
end

function TravelMap.Show(target)
	if not view then
		return
	end
	view.target = target
	local rec = ns.Travel.For(target)
	view.key = rec and rec.key or nil
	view.drawn = nil
	view.map:SetTarget(rec, rec and ns.Travel.Entrance(rec))
	local p = ns.Travel.Player()
	TravelMap.Dispatch({ kind = "show", target = view.key, outdoors = p ~= nil, player = p,
		instances = keySet(currentRecords()) })
end

function TravelMap.Hide()
	TravelMap.Dispatch({ kind = "hide" })
end

-- The spot on the map the record's entrance is drawn on (the bundled entrance's map, else the zone's), or nil.
local function onEntranceMap(rec, last)
	local ent = ns.Travel.Bundled(rec)
	local map = (ent and ent.uiMapID) or ns.Travel.ZoneMap(rec)
	if not map then
		return nil
	end
	if last.uiMapID == map then
		return { map = map, x = last.x, y = last.y }
	end
	if not last.wx then
		return nil
	end
	local m, x, y = ns.Travel.ToMap(last.continent, last.wx, last.wy, map)
	if m == map and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		return { map = map, x = x, y = y }
	end
	return nil
end

-- World yards between two spots on maps ({ map, x, y }), or nil when the client cannot place both on one continent.
local function apart(a, b)
	local c1, x1, y1 = ns.Travel.ToWorld(a.map, a.x, a.y)
	local c2, x2, y2 = ns.Travel.ToWorld(b.map, b.x, b.y)
	if not (c1 and c1 == c2) then
		return nil
	end
	return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Loading screens: the world changed (live map), and the entrance learned: the spot before a screen that ended inside
-- an instance, when it lies near that instance's bundled entrance (TravelLive.Accept), kept on its zone map. Only
-- PLAYER_ENTERING_WORLD (the screen's end) uses the spot; a zone change on the way does not drop it.
local lastOutdoor
function TravelMap.OnLeavingWorld()
	lastOutdoor = ns.Travel.Player()
end

function TravelMap.OnWorld()
	local records = currentRecords()
	local p = ns.Travel.Player()
	TravelMap.Dispatch({ kind = "world", outdoors = p ~= nil, player = p, instances = keySet(records) })
end

function TravelMap.OnEnteringWorld()
	local records = currentRecords()
	local store = ns.db and ns.db.entrances
	if records and lastOutdoor and store then
		local rec = Live.Choose(records, lastOutdoor, ns.Travel.Bundled, ns.Travel.ZoneMap)
		local spot = rec and onEntranceMap(rec, lastOutdoor)
		if spot and Live.Learn(store, rec.key, spot, ns.Now(), apart) then
			ns.Travel.Reset()
		end
	end
	lastOutdoor = nil
	TravelMap.OnWorld()
end

-- /dp entrances reset and the Settings panel's button: forget every learned entrance (the bundled ones are used again).
function TravelMap.ForgetLearned()
	local n = Live.Forget(ns.db and ns.db.entrances)
	ns.Travel.Reset()
	if view and view.target then
		view.map:SetTarget(ns.Travel.For(view.target), ns.Travel.Entrance(ns.Travel.For(view.target)))
	end
	return n
end

function TravelMap.Init()
	ns:RegisterEvent("PLAYER_LEAVING_WORLD", TravelMap.OnLeavingWorld)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", TravelMap.OnEnteringWorld)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", TravelMap.OnWorld)
end
