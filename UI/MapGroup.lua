-- Where the group is on the map: the members who share their room (UI/GroupRooms.lua) as small dots in their class
-- colour with their initial, at the middle of that room on the floor shown. Installed on a map view by UI/MapHere.lua,
-- so the map section and run mode's mini map both have it; setting "Show where your group is on dungeon maps".
--
-- Several members in one room sit on a small ring around its middle; members in the player's own room sit on the edge
-- of the player's marker. A member on another floor, in another instance, or in a spot the data cannot place is not
-- drawn. Like the marker, the dots take no mouse: the map's hover update asks view:GroupAt, and the marker's tooltip
-- code names everyone in that room. The dots are placed again on every map draw and when a member's room changes
-- (GROUP_ROOMS); names and classes come from Data/PartyInfo.lua's roster, cached until the next group event.

local _, ns = ...
local MapGroup = ns:NewModule("MapGroup")
local S, W, L = ns.Style, ns.Widgets, ns.L

MapGroup.DOT = 14 -- a dot's size on screen, in UI units
MapGroup.MAX = 40 -- dots drawn at most (a raid)

function MapGroup.Enabled()
	return not (ns.db and ns.db.settings.mapGroup == false)
end

-- The members' rooms on floor `floor` of `plan`: { { key, x, y (plan space), members = { { id, name, class } } } },
-- rooms and members in a stable order. members: GroupRooms.Members(); who: { [id] = a PartyInfo member }.
function MapGroup.Rooms(plan, floor, members, who)
	local out, byKey = {}, {}
	local data = ns.Subzones.For(plan)
	if not data then
		return out
	end
	for id, m in pairs(members) do
		local a, x, y
		if m.iid == data.iid and m.area then
			a, x, y = ns.Subzones.Place(data, m.area, floor)
		end
		if a then
			local key = ns.Subzones.Key(a)
			local room = byKey[key]
			if not room then
				room = { key = key, x = x, y = y, members = {} }
				byKey[key] = room
				out[#out + 1] = room
			end
			local p = who[id]
			room.members[#room.members + 1] = { id = id, name = p and p.name or ns.Util.ShortName(id) or id,
				class = p and p.class }
		end
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	for _, room in ipairs(out) do
		table.sort(room.members, function(a, b)
			return a.name < b.name
		end)
	end
	return out
end

-- The first letter of a name (UTF-8: one character, whatever its length in bytes).
local function initial(name)
	return name:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
end

-- The tooltip of the members in one room (a spot from view:GroupAt).
function MapGroup.Tooltip(tt, spot)
	tt:SetText(L["Your group here (approx.)"], 1, 0.82, 0)
	for _, m in ipairs(spot.members) do
		local r, g, b = ns.PartyInfo.ClassColor(m.class)
		tt:AddLine(m.name, r or 1, g or 1, b or 1)
	end
	tt:AddLine(L["Group members who share their room. Inside dungeons the game tells addons only the name of the area each of them is in."],
		1, 1, 1, true)
end

function MapGroup.Install(view)
	local pool = {}
	local DOT = MapGroup.DOT

	local function dot(i)
		local d = pool[i]
		if not d then
			d = CreateFrame("Frame", nil, view.overlay)
			-- The marker's level (+2), under the route's stops (+3) and the pins; drawn in OVERLAY, above the marker's
			-- ARTWORK, so they show on its edge.
			d:SetFrameLevel(view.overlay:GetFrameLevel() + 2)
			d:EnableMouse(false)
			d:SetSize(DOT, DOT)
			d.fill = d:CreateTexture(nil, "OVERLAY", nil, 1)
			d.fill:SetTexture(S.MEDIA .. "Circle")
			d.fill:SetAllPoints()
			d.ring = d:CreateTexture(nil, "OVERLAY", nil, 2)
			d.ring:SetTexture(S.MEDIA .. "Ring")
			d.ring:SetAllPoints()
			d.ring:SetVertexColor(0.08, 0.06, 0.04, 0.95)
			d.letter = W.Text(d, "caption", "ink")
			d.letter:SetDrawLayer("OVERLAY", 3)
			d.letter:SetAllPoints()
			d.letter:SetJustifyH("CENTER")
			d.letter:SetTextColor(0.08, 0.06, 0.04, 1)
			pool[i] = d
		end
		return d
	end

	-- Place the dots for the plan and floor the marker was last drawn for (view.hereArgs, UI/MapHere.lua).
	function view:PlaceGroup()
		local a = self.hereArgs
		local members = ns.GroupRooms and ns.GroupRooms.Members()
		local rooms = {}
		if a and members and next(members) and MapGroup.Enabled() then
			local who = {}
			for _, m in ipairs(ns.PartyInfo.Cached()) do
				who[m.id] = m
			end
			rooms = MapGroup.Rooms(a.plan, a.floor, members, who)
		end
		local here = self.hereAt
		local spots, n, sig = {}, 0, {}
		for _, room in ipairs(rooms) do
			local cx, cy = a.px(room.x, room.y), a.py(room.y, room.x)
			local mine = here ~= nil and math.abs(here.x - cx) < 0.5 and math.abs(here.y - cy) < 0.5
			local ring = ns.MapLayout.Ring(#room.members, DOT + 2, mine and here.r or 0)
			local spot = { members = room.members, dots = {}, mine = mine }
			for i, m in ipairs(room.members) do
				if n >= MapGroup.MAX then
					break
				end
				n = n + 1
				local x, y = cx + ring[i][1], cy - ring[i][2]
				local d = dot(n)
				local r, g, b = ns.PartyInfo.ClassColor(m.class)
				d.fill:SetVertexColor(r or 0.75, g or 0.75, b or 0.75, 1)
				d.letter:SetText(initial(m.name))
				d:ClearAllPoints()
				d:SetPoint("CENTER", self.canvas, "TOPLEFT", x, y)
				d:Show()
				spot.dots[i] = { x = x, y = y }
				sig[#sig + 1] = string.format("%s@%.1f,%.1f", m.id, x, y)
			end
			spots[#spots + 1] = spot
		end
		for i = n + 1, #pool do
			pool[i]:Hide()
		end
		self.groupAt = n > 0 and spots or nil
		sig = table.concat(sig, ";")
		if sig ~= self.groupSig then
			self.groupSig = sig
			self:HereMoved()
		end
	end

	-- The spot whose dot is under canvas offset (x, y) (y up, as the dots are placed), or nil.
	function view:GroupAt(x, y)
		local reach = (DOT / 2 + 2) ^ 2
		for _, spot in ipairs(self.groupAt or {}) do
			for _, d in ipairs(spot.dots) do
				if (x - d.x) ^ 2 + (y - d.y) ^ 2 <= reach then
					return spot
				end
			end
		end
		return nil
	end

	-- The names of the members in the player's own room, for the marker's tooltip; nil for none.
	function view:GroupWithMe()
		for _, spot in ipairs(self.groupAt or {}) do
			if spot.mine then
				local names = {}
				for i, m in ipairs(spot.members) do
					names[i] = m.name
				end
				return table.concat(names, ", ")
			end
		end
		return nil
	end

	ns:On("GROUP_ROOMS", view, function()
		if view:IsVisible() then
			view:PlaceGroup()
		end
	end)
end
