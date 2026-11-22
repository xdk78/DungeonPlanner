-- The live "Getting there" map, outdoors only: the entrance's zone map from the game's own map art (C_Map), the
-- entrance, the nearest flight masters and a summoning stone as pins, and the player as an arrow turned to their
-- facing, with the straight-line distance and direction under it. It sits at the top of the Getting there window
-- (UI/GettingThere.lua). The lifecycle is Model/TravelLive.lua's state machine: a 10 Hz ticker runs only while the
-- window shows and the client gives a position (never inside an instance, where it gives none); entering the target
-- instance opens its plan and run mode. Loading screens also teach the entrance: the last outdoor spot before one that
-- ends inside an instance is kept per account (TravelLive.Learn) and preferred over the bundled spot.
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

	-- The zone of the entrance and its pins (once per target).
	function f:SetTarget(rec, ent)
		self.rec, self.ent = rec, ent
		local map = ent and ent.uiMapID
		self.map = map
		self.art = map and ns.Instances.MapArt(map) or nil
		self.empty:SetShown(self.art == nil)
		self:Layout()
		self:Place(self.entrance, ent and ent.x, ent and ent.y)
		local stone = rec and rec.stone
		local stoneMap = stone and ns.Instances.ZoneMapByName(stone.zone)
		if stone and (stoneMap == map or stone.zone == rec.zone) then
			self:Place(self.stone, stone.x / 100, stone.y / 100)
		else
			self.stone:Hide()
		end
		local shown = 0
		for _, side in ipairs({ "alliance", "horde" }) do
			for _, near in ipairs(rec and ns.Travel.Nearest(rec, side, 2) or {}) do
				local m, x, y = ns.Travel.NodeOnMap(near.id)
				if m == map and shown < MAX_FLIGHTS then
					shown = shown + 1
					self.flights[shown].name = near.name
					self:Place(self.flights[shown], x, y)
				end
			end
		end
		for i = shown + 1, MAX_FLIGHTS do
			self.flights[i]:Hide()
		end
	end

	-- The player: an arrow on the map when on the same map, turned to the facing (radians, 0 = north, counter-
	-- clockwise, as the client gives it).
	function f:SetPlayer(player)
		if not (player and player.uiMapID == self.map) then
			self.player:Hide()
			return
		end
		self:Place(self.player, player.x, player.y)
		if player.facing and self.player.SetRotation then
			self.player:SetRotation(player.facing)
		end
	end

	f:SetScript("OnSizeChanged", function(self)
		if self.rec then
			self:SetTarget(self.rec, self.ent)
		end
	end)
	return f
end

-- The controller --------------------------------------------------------------------------------------------------------

local state = Live.New()
local ticker
local view -- { map = widget, line = font string, target = plan or entry, key = instance key }

local function outdoors()
	return ns.Travel.Player() ~= nil
end

local function currentInstance()
	local here = ns.Instances.Current()
	if not here.inInstance then
		return nil
	end
	return ns.Providers.Key(here.name)
end

function TravelMap.Draw()
	if not view then
		return
	end
	local player = ns.Travel.Player()
	view.map:SetPlayer(player)
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
	W.FitText(view.line, text or "")
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

local function apply(effects)
	for _, e in ipairs(effects) do
		if e == "start" and not ticker and C_Timer and C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(Live.INTERVAL, function()
				TravelMap.Dispatch({ kind = "tick", outdoors = outdoors() })
			end)
		elseif e == "stop" and ticker then
			ticker:Cancel()
			ticker = nil
		elseif e == "draw" then
			TravelMap.Draw()
		elseif e == "arrived" then
			TravelMap.Arrive()
		end
	end
end

function TravelMap.Dispatch(event)
	local effects
	state, effects = Live.Step(state, event)
	apply(effects)
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
	view.map:SetTarget(rec, rec and ns.Travel.Entrance(rec))
	TravelMap.Dispatch({ kind = "show", target = view.key, outdoors = outdoors() })
end

function TravelMap.Hide()
	TravelMap.Dispatch({ kind = "hide" })
end

-- Loading screens: the world changed (live map), and the entrance learned (the spot before a screen that ended in an
-- instance).
local lastOutdoor
function TravelMap.OnLeavingWorld()
	local p = ns.Travel.Player()
	lastOutdoor = p and { map = p.uiMapID, x = p.x, y = p.y, at = ns.Now() } or nil
end

function TravelMap.OnWorld()
	local key = currentInstance()
	if key and lastOutdoor and ns.db and ns.db.entrances and ns.Travel.ByKey(key) then
		if Live.Learn(ns.db.entrances, key, lastOutdoor, ns.Now()) then
			ns.Travel.Reset()
		end
	end
	lastOutdoor = nil
	TravelMap.Dispatch({ kind = "world", outdoors = outdoors(), instance = key })
end

function TravelMap.Init()
	ns:RegisterEvent("PLAYER_LEAVING_WORLD", TravelMap.OnLeavingWorld)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", TravelMap.OnWorld)
	ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", TravelMap.OnWorld)
end
