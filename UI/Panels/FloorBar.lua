-- The map's floor switcher, in the map's bottom-right corner inside its frame (left of the marker editor while that
-- takes the map's height; the coordinates sit over it): every floor the instance has (Data/Floors.lua: the plan's own
-- and the map art's other floors), as a strip of tabs for two to four floors, or the floor's name between previous /
-- next arrows for more (the toolbar's floor list stays for those). Hidden on a map of one floor. Each floor's tooltip
-- counts the plan's markers on it; Shift + mouse wheel over the map goes to the next or previous floor. The top-left
-- corner was tried first: the entrance stands there on many maps (the Deadmines), under the switcher.

local _, ns = ...
local FloorBar = ns:NewModule("FloorBar")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

FloorBar.TABS = 4 -- up to this many floors: a tab each; more: the name between arrows
local TAB_MAX = 170 -- a tab's widest; a longer name is cut (the tooltip has it whole)
local NAME_MAX = 220 -- the pager's name plate at most

-- Markers of `plan` on floor `index`.
function FloorBar.MarkerCount(plan, index)
	local n = 0
	for _, m in ipairs(plan and plan.markers or {}) do
		if m.floor == index then
			n = n + 1
		end
	end
	return n
end

-- The floor after (+1) or before (-1) `current` of `count`, wrapping round; nil with one floor.
function FloorBar.Step(current, count, delta)
	if count <= 1 then
		return nil
	end
	return (current - 1 + delta) % count + 1
end

-- Build the switcher on map section `f` (UI/Panels/MapPanel.lua: f:GoToFloor) over `canvas`.
function FloorBar.Build(f, ctx, canvas)
	local inset = ns.MapCanvas.FRAME_INSET + SP.sm
	local right
	local bar = W.Panel(canvas.edge, "surface", "border")
	bar:SetPoint("BOTTOMRIGHT", -inset, inset)
	bar:SetHeight(SZ.control + 2 * SP.xs)
	bar:EnableMouse(true)
	bar:Hide()
	f.floorBar = bar
	bar.tabs = {}
	bar.measure = W.Text(bar, "body", "gold")
	bar.measure:Hide()

	local function tooltip(owner, index)
		local tt = W.Tip()
		local p = ctx:Plan()
		local floor = ctx:Floors()[index]
		if not (tt and p and floor) then
			return
		end
		tt:SetOwner(owner, "ANCHOR_BOTTOM")
		tt:SetText(ns.Names.Floor(floor, index), 1, 0.82, 0, 1, true)
		local n = FloorBar.MarkerCount(p, index)
		if floor.extra then
			tt:AddLine(ctx:ReadOnly() and L["The instance's map of this floor; this plan has nothing on it."]
				or L["The instance's map of this floor. Put something on it and it joins your plan."], 1, 1, 1, true)
		else
			tt:AddLine(ns.Plural(n, L["%d marker on this floor|%d markers on this floor"]), 1, 1, 1, true)
		end
		tt:AddLine(L["Shift + mouse wheel over the map: the next floor."], 0.71, 0.67, 0.59, true)
		W.TipShow(tt)
	end
	local function hideTip(owner)
		local tt = W.Tip()
		if tt and tt:IsOwned(owner) then
			tt:Hide()
		end
	end
	local function hook(b)
		b:HookScript("OnEnter", function(self)
			tooltip(self, self.floorIndex or ctx.floor)
		end)
		b:HookScript("OnLeave", hideTip)
	end

	-- Pager: previous, the floor's name and number, next.
	local function go(delta)
		local nextFloor = FloorBar.Step(ctx.floor, #ctx:Floors(), delta)
		if nextFloor then
			f:GoToFloor(nextFloor)
		end
	end
	bar.prev = W.Button(bar, "<", "outline", function()
		go(-1)
	end, SZ.control)
	bar.next = W.Button(bar, ">", "outline", function()
		go(1)
	end, SZ.control)
	bar.name = W.Button(bar, "", "segment", nil)
	bar.name:EnableMouse(true)
	hook(bar.name)
	W.SetTooltip(bar.prev, L["Previous floor"])
	W.SetTooltip(bar.next, L["Next floor"])

	local function tab(i)
		local b = bar.tabs[i]
		if not b then
			b = W.Button(bar, "", "segment", function(self)
				f:GoToFloor(self.floorIndex)
			end)
			hook(b)
			bar.tabs[i] = b
		end
		return b
	end

	-- A button's label, cut to `max` wide with its whole text in the tooltip.
	local function label(b, text, max)
		if not b.dpFloorLabel then
			-- The label across the button (inside its margins), so a cut name ends at the button's edge.
			b.dpFloorLabel = true
			b.dpFixedWidth = true
			b.label:ClearAllPoints()
			b.label:SetPoint("LEFT", SP.sm, 0)
			b.label:SetPoint("RIGHT", -SP.sm, 0)
			b.label:SetJustifyH("CENTER")
		end
		-- Measured on a free copy: the label's own width is the button's, which may be the last, shorter name's.
		bar.measure:SetText(text)
		local natural = math.ceil(bar.measure:GetStringWidth() or 0) + 2 * SP.md
		b:SetWidth(math.max(SZ.control, math.min(natural, max)))
		W.FitText(b.label, text)
	end

	-- What the marker editor takes of the map's right side (it stands the map's whole height: canvas.fitBeside).
	right = function()
		return canvas.fitBeside and (canvas.reserveRight or 0) or 0
	end
	-- Room on the map's bottom edge: right of the labels and icon-size controls, left of the marker editor.
	local function room()
		local controls = f.controls and f.controls:GetWidth() or 120
		return math.max(120, (canvas:GetWidth() or 0) - 2 * inset - controls - SP.md - right())
	end

	function bar:Refresh()
		local floors = ctx:Floors()
		local n = #floors
		local shown = n > 1
		self:SetShown(shown)
		-- Left of the marker editor when it takes the map's whole height; the coordinates move up over it.
		self:ClearAllPoints()
		self:SetPoint("BOTTOMRIGHT", -(inset + right()), inset)
		canvas.coords:ClearAllPoints()
		if shown then
			canvas.coords:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, SP.xs)
		else
			canvas.coords:SetPoint("BOTTOMRIGHT", -inset, inset)
		end
		for _, b in ipairs(self.tabs) do
			b:Hide()
		end
		if not shown then
			return
		end
		local x, tabsW = SP.xs, SP.xs
		local useTabs = n <= FloorBar.TABS
		if useTabs then
			for i, floor in ipairs(floors) do
				local b = tab(i)
				b.floorIndex = i
				label(b, ns.Names.Floor(floor, i), TAB_MAX)
				tabsW = tabsW + b:GetWidth() + SP.xs
			end
			-- Too wide for the map's edge (long names in Polish): the pager instead.
			useTabs = tabsW <= room()
		end
		self.prev:SetShown(not useTabs)
		self.next:SetShown(not useTabs)
		self.name:SetShown(not useTabs)
		if useTabs then
			for i = 1, n do
				local b = self.tabs[i]
				b:ClearAllPoints()
				b:SetPoint("LEFT", x, 0)
				b:SetActive(i == ctx.floor)
				b:Show()
				x = x + b:GetWidth() + SP.xs
			end
		else
			self.name.floorIndex = ctx.floor
			label(self.name, string.format("%s  %d/%d", ns.Names.Floor(floors[ctx.floor], ctx.floor), ctx.floor, n),
				math.min(NAME_MAX, room() - 2 * SZ.control - 4 * SP.xs))
			self.name:SetActive(true)
			self.prev:ClearAllPoints()
			self.prev:SetPoint("LEFT", x, 0)
			self.name:ClearAllPoints()
			self.name:SetPoint("LEFT", self.prev, "RIGHT", SP.xs, 0)
			self.next:ClearAllPoints()
			self.next:SetPoint("LEFT", self.name, "RIGHT", SP.xs, 0)
			x = x + 2 * SZ.control + self.name:GetWidth() + 2 * SP.xs
		end
		self:SetWidth(x)
	end

	-- The switcher's box in the map view's pixels (top left origin), for the map's fit (MapPanel fitAvoid).
	function bar:Rect()
		local vw, vh = canvas:GetWidth() or 0, canvas:GetHeight() or 0
		local r, b = vw - inset - right(), vh - inset
		return { r - (self:GetWidth() or 0), b - (self:GetHeight() or 0), r, b }
	end

	-- Inside an instance, the map follows the player to another floor when the client says which (Floors.PlayerFloor;
	-- unverified on Forever, nil until a scan shows a map there). Only on a change of the player's floor, so a floor
	-- the player picked by hand stays until they move. Not while a marker, route or drawing is selected (switching
	-- floors would drop it): the map follows on the next change after that. Another plan, or a new instance
	-- (PLAYER_ENTERING_WORLD), starts over.
	local function follow()
		local inInstance = rawget(_G, "IsInInstance")
		local ok, inside = false, nil
		if type(inInstance) == "function" then
			ok, inside = pcall(inInstance)
		end
		if not (ok and ns.Util.Plain(inside) == true and f:IsVisible()) then
			return
		end
		local plan = ctx:Plan()
		local id = plan and plan.id
		if bar.playerPlan ~= id then
			bar.playerPlan, bar.playerFloor = id, nil
		end
		if ctx.selectedMarker or ctx.activeRoute or ctx.selectedShape then
			return
		end
		local index = ns.Floors.PlayerFloor(plan)
		if index and index ~= bar.playerFloor then
			bar.playerFloor = index
			f:GoToFloor(index)
		end
	end
	f.FollowPlayerFloor = follow
	for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns:RegisterEvent(event, function()
			if event == "PLAYER_ENTERING_WORLD" then
				bar.playerFloor = nil
			end
			ns.SafeCall(follow)
		end)
	end

	-- Shift + mouse wheel over the map: the next or previous floor (the wheel alone zooms).
	local zoom = canvas:GetScript("OnMouseWheel")
	canvas:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown and IsShiftKeyDown() and #ctx:Floors() > 1 then
			go(delta > 0 and -1 or 1)
		elseif zoom then
			zoom(self, delta)
		end
	end)
	return bar
end
