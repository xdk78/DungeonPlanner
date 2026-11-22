-- Map section: the war table's map (UI/MapCanvas.lua) filling the section, with the labels and icon-size controls in
-- its bottom-left corner and a floating legend in its top-right corner (the "Legend" button shows or hides it): the
-- layer switch (each layer with its icon, count and a check box, plus "Enemies" where spawn data exists), the routes
-- on this floor, and the editor of the selected marker, which opens there whenever a marker is selected.
-- Your own plans get the edit tools above the map: Select (drag to move), Marker, Position (party role), Pull (click
-- markers into the current pull), Route (click adds a bend, Shift-click a numbered stop, right-click ends), Draw (the
-- drawing tools' own line, UI/Panels/DrawBar.lua) and Erase.
-- A recommended plan is read-only: no tools, and the rail shows the marker's details instead of an editor.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema, Route = ns.Plan, ns.Util, ns.Schema, ns.Route
local SP, SZ = S.SPACE, S.SIZE

local RAIL = 248 -- the marker editor's width
local LEGEND_W = 204 -- the legend alone: compact, so it covers little of the map
local RAIL_INSET = 7 + 8 -- the legend inside the map's gold frame (MapCanvas.FRAME_INSET) with a margin (SP.sm)
local TOOLS = { "select", "marker", "position", "pull", "route", "draw", "erase" }
local TOOL_TEXT = {
	select = "Select",
	marker = "Marker",
	position = "Position",
	pull = "Pull",
	route = "Route",
	draw = "Draw",
	erase = "Erase",
}
local TOOL_HELP = {
	select = "Click a marker to edit it; drag to move it. Drag the map to pan, scroll to zoom.",
	marker = "Click the map to place a marker of the chosen kind.",
	position = "Click the map to place a party position for the chosen role. With a boss or pull in focus, it belongs to it.",
	pull = "Click markers to add them to the current pull, or to take them out.",
	route = "Click to add route points, Shift-click for a numbered stop. Right-click to finish the route.",
	routeSnap = "Click to add numbered stops: the path between them follows the corridors. Shift-click for a straight leg. Right-click to finish the route.",
	erase = "Click a marker or route point to delete it.",
	draw = "Pick a tool, colour and width above. Drawings made while a boss or pull is in focus belong to it. Right-click one for more.",
	readOnly = "A recommended plan. Hover markers for notes; make an editable copy to change it.",
}
-- A tool button's tooltip where it differs from the tool's help (the Route tool's covers both modes).
local TOOL_TIP = {
	route = "Click to add route points, Shift-click for a numbered stop. With Snap to corridors on (where the floor has "
		.. "corridor data), a click adds a numbered stop whose path follows the corridors and Shift-click gives a straight "
		.. "leg. Right-click to finish the route.",
}

local Panel = {}
ns.Panels.map = Panel

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", "DungeonPlannerMapSection", parent)

	local function plan()
		return ctx:Plan()
	end
	local function changed(what)
		ctx:Changed(what)
	end
	local function readOnly()
		return ctx:ReadOnly()
	end
	local function layerVisible(id)
		return ns.db.ui.mapLayers[id] ~= false
	end

	-- Toolbar -------------------------------------------------------------------------------------------------------------
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(SZ.control)
	f.bar = bar

	f.toolButtons = {}
	local x = 0
	for _, tool in ipairs(TOOLS) do
		local b = W.Button(bar, L[TOOL_TEXT[tool]], "outline", function()
			ctx.tool = tool
			if tool ~= "route" then
				ctx.activeRoute = nil
			end
			if tool ~= "draw" then
				ctx.selectedShape = nil
			end
			f:Refresh()
		end)
		b:SetPoint("LEFT", x, 0)
		W.SetTooltip(b, L[TOOL_TEXT[tool]], L[TOOL_TIP[tool] or TOOL_HELP[tool]])
		x = x + b:GetWidth() + SP.xs
		f.toolButtons[tool] = b
	end
	local optionsX = x + SP.sm

	local function kindOptions()
		local out = {}
		for _, kind in ipairs(Schema.MARKER_KINDS) do
			if kind ~= "position" then
				out[#out + 1] = { text = L[kind], value = kind }
			end
		end
		return out
	end
	local function roleOptions()
		local out = {}
		for _, role in ipairs(Schema.POSITION_ROLES) do
			out[#out + 1] = { text = L["role:" .. role], value = role }
		end
		return out
	end

	f.kind = W.Dropdown(bar, {
		width = 140,
		options = kindOptions,
		get = function()
			return ctx.kind
		end,
		set = function(v)
			ctx.kind = v
		end,
	})
	f.kind:SetPoint("LEFT", optionsX, 0)

	f.role = W.Dropdown(bar, {
		width = 120,
		options = roleOptions,
		get = function()
			return ctx.role
		end,
		set = function(v)
			ctx.role = v
		end,
	})
	f.role:SetPoint("LEFT", optionsX, 0)

	f.pull = W.Dropdown(bar, {
		width = 150,
		placeholder = L["Choose a pull"],
		options = function()
			local out = {}
			local p = plan()
			if p then
				for i, pull in ipairs(p.pulls) do
					out[#out + 1] = { text = i .. ". " .. pull.name, value = pull.id }
				end
				if #p.pulls < Schema.MAX.pulls then
					out[#out + 1] = { text = L["+ New pull"], value = "new" }
				end
			end
			return out
		end,
		get = function()
			return ctx.currentPull
		end,
		set = function(v)
			local p = plan()
			if v == "new" and p then
				local pull = Plan.AddPull(p)
				ctx.currentPull = pull and pull.id or nil
				changed("pulls")
			else
				ctx.currentPull = v
			end
			f:Refresh()
		end,
	})
	f.pull:SetPoint("LEFT", optionsX, 0)

	-- Every floor the map can show (Data/Floors.lua). Going to one clears what belonged to the last.
	function f:GoToFloor(v)
		if v == ctx.floor or not ctx:Floors()[v] then
			return
		end
		ctx.floor = v
		ctx.selectedMarker, ctx.activeRoute, ctx.focusSegment = nil, nil, nil
		self:LoadFloor()
		self:Refresh()
	end
	-- The toolbar's floor list, for an instance with many floors; fewer have the switcher on the map (FloorBar).
	f.floor = W.Dropdown(bar, {
		width = 150,
		options = function()
			local out = {}
			for i, floor in ipairs(ctx:Floors()) do
				out[#out + 1] = { text = ns.Names.Floor(floor, i), value = i }
			end
			return out
		end,
		get = function()
			return ctx.floor
		end,
		set = function(v)
			f:GoToFloor(v)
		end,
	})
	f.floor:SetPoint("RIGHT", 0, 0)

	-- Focus: which boss or pull the party positions are shown for (and what the map dims around).
	f.focus = W.Dropdown(bar, {
		width = 170,
		options = function()
			local out = { { text = L["Focus: everything"], value = "all" } }
			local p = plan()
			if p then
				for _, enc in ipairs(p.encounters) do
					out[#out + 1] = { text = L["Boss:"] .. " " .. ns.Names.Encounter(enc), value = "e:" .. enc.id }
				end
				for i, pull in ipairs(p.pulls) do
					out[#out + 1] = { text = string.format(L["Pull %d: %s"], i, pull.name), value = "p:" .. pull.id }
				end
			end
			return out
		end,
		get = function()
			if ctx.focusEncounter then
				return "e:" .. ctx.focusEncounter
			elseif ctx.focusPull then
				return "p:" .. ctx.focusPull
			end
			return "all"
		end,
		set = function(v)
			ctx.focusEncounter = v:match("^e:(.+)$")
			ctx.focusPull = v:match("^p:(.+)$")
			ctx.focusSegment = nil
			f:Refresh()
		end,
	})
	f.focus:SetPoint("RIGHT", f.floor, "LEFT", -SP.sm, 0)
	W.SetTooltip(f.focus, L["Focus"], L["Shows the party positions for one boss or pull and dims the rest of the map."])

	f.fit = W.Button(bar, L["Fit"], "outline", function()
		f.canvas:ResetView()
	end)
	f.fit:SetPoint("RIGHT", f.focus, "LEFT", -SP.sm, 0)
	W.SetTooltip(f.fit, L["Fit"], L["Show the whole map."])
	-- The legend shows by itself the first time the map opens (ui.legendSeen), then stays off until the Legend button
	-- turns it on; once the button is used, its choice sticks (ui.showLegend).
	local firstView = not ns.db.ui.legendSeen
	ns.db.ui.legendSeen = true
	local function legendShown()
		if ns.db.ui.showLegend ~= nil then
			return ns.db.ui.showLegend and true or false
		end
		return firstView
	end
	f.LegendShown = legendShown
	f.legendButton = W.Button(bar, L["Legend"], "outline", function()
		ns.db.ui.showLegend = not legendShown()
		f:Refresh()
		f.canvas:FitContent()
	end)
	f.legendButton:SetPoint("RIGHT", f.fit, "LEFT", -SP.sm, 0)
	W.SetTooltip(f.legendButton, L["Legend"], L["Show or hide the legend: map layers, routes and the selected marker."])

	-- Canvas -----------------------------------------------------------------------------------------------------------
	local canvas = ns.MapCanvas.Create(f, {
		getPlan = plan,
		readOnly = readOnly,
		getFloor = function()
			return ctx.floor
		end,
		-- Put something on the current floor (a floor only the map had joins the plan first; ctx:AddOnFloor).
		addOnFloor = function(add)
			return ctx:AddOnFloor(add)
		end,
		-- A marker that leads to another floor (stairs, a portal) was clicked in a read-only plan: go there.
		onGoToFloor = function(index)
			f:GoToFloor(index)
		end,
		getTool = function()
			return readOnly() and "select" or ctx.tool
		end,
		getKind = function()
			return ctx.kind
		end,
		getRole = function()
			return ctx.role
		end,
		getSelectedMarker = function()
			return ctx.selectedMarker
		end,
		getFocusPull = function()
			return ctx.focusPull or (ctx.tool == "pull" and not readOnly() and ctx.currentPull) or nil
		end,
		getFocusEncounter = function()
			return ctx.focusEncounter
		end,
		getActiveRoute = function()
			return ctx.activeRoute
		end,
		getFocusSegment = function()
			return ctx.focusSegment
		end,
		-- A numbered stop shows the side panel's number of the step it makes (Steps.StopNumbers).
		stopNumber = function(routeId, index)
			local byRoute = ns.Steps.StopNumbers(ctx:Steps())[routeId]
			return byRoute and byRoute[index]
		end,
		spawnsShown = function()
			return ns.MapSpawns.LayerShown(plan())
		end,
		-- Another addon's route (Forever Dungeon Routes) as an extra layer: off until the player ticks it.
		providerRoutesShown = function()
			return ns.db.ui.mapLayers.providerRoutes == true
		end,
		showLabels = function()
			return ctx.showLabels
		end,
		showCoordinates = function()
			return ns.db.settings.showCoordinates
		end,
		layerVisible = layerVisible,
		iconScale = function()
			return ns.db.ui.iconScale or 1
		end,
		onSelectMarker = function(id)
			local p = plan()
			if ctx.tool == "pull" and id and p and not readOnly() then
				-- Pull tool: toggle membership in the current pull.
				if not (ctx.currentPull and Util.FindById(p.pulls, ctx.currentPull)) then
					local pull = Plan.AddPull(p)
					ctx.currentPull = pull and pull.id
				end
				local m = Util.FindById(p.markers, id)
				if m and ctx.currentPull then
					Plan.UpdateMarker(p, id, { pull = m.pull == ctx.currentPull and false or ctx.currentPull })
					changed("pulls")
				end
				return
			end
			ctx.selectedMarker = id
			f:Refresh()
		end,
		onSelectRoute = function(routeId)
			if not readOnly() then
				ctx.activeRoute = routeId
				f:Refresh()
			end
		end,
		onMarkerMenu = function(id, owner)
			f:MarkerMenu(id, owner)
		end,
		onPointMenu = function(routeId, index, owner)
			f:PointMenu(routeId, index, owner)
		end,
		onChanged = function(what)
			changed(what)
		end,
		-- shift: Shift held. Snapping (UI/RouteSnap.lua): a stop, its leg snapped (Shift: straight); otherwise a bend
		-- (Shift: a stop).
		onRoutePoint = function(px, py, shift)
			local p = plan()
			if not p then
				return
			end
			local route = ctx.activeRoute and Util.FindById(p.routes, ctx.activeRoute)
			local created = false
			if not route then
				route = ctx:AddOnFloor(function(floor)
					return Plan.AddRoute(p, floor, string.format(L["Route %d"], #p.routes + 1), (#p.routes % Schema.COLOR_COUNT) + 1)
				end)
				if not route then
					ns:Print(L["Cannot add more routes."])
					return
				end
				ctx.activeRoute, created = route.id, true
			end
			if not Plan.AddRoutePoint(p, route.id, px, py) then
				ns:Print(L["This route has the maximum number of points."])
				if not created then
					return -- nothing changed: no undo step
				end
			elseif ns.RouteSnap.Active(p, route.floor) then
				ns.RouteSnap.Stop(p, route.id, shift, f.canvas)
			elseif shift then
				Plan.SetRouteStop(p, route.id, #route.points, true)
			end
			changed("routes")
		end,
		onRouteFinished = function()
			ctx.activeRoute = nil
			f:Refresh()
		end,
		-- A dragged route point dropped, before the change is recorded: with the Route tool, a stop's legs found again
		-- when snapping (with Select a stop moves alone, as without snapping).
		onPointMoved = function(routeId, index, fromX, fromY, shift)
			local p = plan()
			if p and ctx.tool == "route" then
				ns.RouteSnap.Moved(p, routeId, index, fromX, fromY, shift, f.canvas)
			end
		end,
	})
	canvas:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -SP.sm)
	canvas:SetPoint("BOTTOMRIGHT")
	f.canvas = canvas
	ns.UI.mapCanvas = canvas -- for /dp perf (Core/Perf.lua)
	-- The drawing tools' line under the toolbar, and the canvas's drawing callbacks (UI/Panels/DrawBar.lua).
	ns.DrawBar.Build(f, ctx, bar, canvas)

	-- Map controls in the bottom-left corner: labels, icon size, the route tool's snap switch (UI/Panels/MapControls.lua).
	ns.MapControls.Build(f, ctx, canvas)
	-- The floor switcher in the top-left corner (UI/Panels/FloorBar.lua).
	ns.FloorBar.Build(f, ctx, canvas)

	-- Legend panel, floating over the map's top-right corner ------------------------------------------------------------
	local rail = W.Panel(f, "surface", "border")
	rail:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -RAIL_INSET, -RAIL_INSET)
	rail:SetWidth(LEGEND_W)
	rail:SetHeight(200)
	rail:SetFrameLevel(canvas.edge:GetFrameLevel() + 10)
	rail:EnableMouse(true)
	f.rail = rail
	-- The legend's box in the map view's pixels (top left origin).
	local function railRect()
		local vw = canvas:GetWidth() or 0
		local rw, rh = rail:GetWidth() or 0, rail:GetHeight() or 0
		return { vw - RAIL_INSET - rw, RAIL_INSET, vw - RAIL_INSET, RAIL_INSET + rh }
	end
	-- The whole map is fitted so that neither the legend nor the controls cover the plan's points (MapLayout.MapFit):
	-- their boxes in the map view's pixels.
	canvas.fitAvoid = function()
		local vh = canvas:GetHeight() or 0
		local inset = ns.MapCanvas.FRAME_INSET + SP.sm
		local rects = {}
		ns.MapControls.Rects(f, rects, vh, inset)
		if f.floorBar:IsShown() then
			rects[#rects + 1] = f.floorBar:Rect()
		end
		if rail:IsShown() and (canvas.reserveRight or 0) > 0 then
			rects[#rects + 1] = railRect()
		end
		for _, r in ipairs(rects) do
			for i = 1, 4 do
				r[i] = math.floor(r[i] + 0.5)
			end
		end
		return rects
	end

	-- Legend and layers (UI/Panels/MapLegend.lua): its title folds it to one line.
	local legend = ns.MapLegend.Build(rail, {
		canvas = canvas,
		layerVisible = layerVisible,
		onToggle = function()
			f:Refresh()
		end,
		focused = function()
			return ctx.focusEncounter ~= nil or ctx.focusPull ~= nil
		end,
		-- The positions row's hint: focus the first boss (or pull) with party positions, as the Focus menu would.
		onFocus = function(target)
			ctx.focusEncounter = target.kind == "encounter" and target.id or nil
			ctx.focusPull = target.kind == "pull" and target.id or nil
			ctx.focusSegment = nil
			f:Refresh()
		end,
	})
	f.legend = legend

	f.help = W.Paragraph(rail, "caption", "muted")
	f.help:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -SP.sm)
	f.help:SetPoint("RIGHT", -SP.md, 0)

	-- Routes on this floor.
	local routes = CreateFrame("Frame", nil, rail)
	routes:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -SP.md)
	routes:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
	f.routes = routes
	routes.heading = W.Heading(routes, L["Routes on this floor"])
	routes.heading:SetPoint("TOPLEFT")
	routes.fromPulls = W.Button(routes, L["Route from pulls"], "outline", function()
		local p = plan()
		if not p then
			return
		end
		local points = Route.PointsFromPulls(p, ctx.floor)
		if #points < 2 then
			ns:Print(L["Put markers of at least two pulls on this floor first."])
			return
		end
		local route = ctx:AddOnFloor(function(floor)
			return Plan.AddRoute(p, floor, L["Pull route"], 1)
		end)
		if route then
			for _, pt in ipairs(points) do
				Plan.AddRoutePoint(p, route.id, pt[1], pt[2])
				Plan.SetRouteStop(p, route.id, #route.points, true)
			end
			changed("routes")
		end
	end)
	routes.fromPulls:SetPoint("TOPLEFT", routes.heading, "BOTTOMLEFT", 0, -SP.sm)
	W.SetTooltip(routes.fromPulls, L["Route from pulls"], L["A route through the centre of each pull, in pull order, with a numbered stop at each."])
	routes.list = W.List(routes, {
		rowHeight = SZ.row,
		empty = L["No routes yet. Pick the Route tool and click the map."],
		create = function(row)
			row.swatch = row:CreateTexture(nil, "ARTWORK")
			row.swatch:SetTexture(S.MEDIA .. "Circle")
			row.swatch:SetSize(10, 10)
			row.swatch:SetPoint("LEFT", SP.sm, 0)
			-- The stop count in its own column (as the layer counts above), so a long name never hides it.
			row.count = W.Text(row, "caption", "muted")
			row.count:SetPoint("RIGHT", -SP.sm, 0)
			row.count:SetJustifyH("RIGHT")
			row.text = W.Text(row, "body", "ink")
			row.text:SetPoint("LEFT", row.swatch, "RIGHT", SP.sm, 0)
			row.text:SetPoint("RIGHT", row.count, "LEFT", -SP.sm, 0)
		end,
		update = function(row, route)
			row.swatch:SetVertexColor(S.PaletteColor(route.color))
			local stops = 0
			for _, pt in ipairs(route.points) do
				if pt.step then
					stops = stops + 1
				end
			end
			row.stops = stops
			row.count:SetText(tostring(stops))
			W.FitText(row.text, ns.Names.Route(route))
		end,
		onEnter = function(route, row)
			local tt = W.Tip()
			if tt then
				tt:SetOwner(row, "ANCHOR_RIGHT")
				tt:SetText(ns.Names.Route(route) .. " (" .. ns.Plural(row.stops or 0, L["%d stop|%d stops"]) .. ")", 1, 0.82, 0, 1, true)
				W.TipShow(tt)
			end
		end,
		isSelected = function(route)
			return route.id == ctx.activeRoute
		end,
		onClick = function(route, _, mouse, row)
			if mouse == "RightButton" then
				f:RouteMenu(route, row)
			elseif not readOnly() then
				ctx.activeRoute = route.id
				ctx.tool = "route"
				f:Refresh()
			end
		end,
	})
	routes.list:SetPoint("TOPLEFT", routes.fromPulls, "BOTTOMLEFT", 0, -SP.sm)
	routes.list:SetPoint("BOTTOMRIGHT")
	function routes:Place(withButton)
		self.list:ClearAllPoints()
		self.list:SetPoint("TOPLEFT", withButton and self.fromPulls or self.heading, "BOTTOMLEFT", 0, -SP.sm)
		self.list:SetPoint("BOTTOMRIGHT")
	end

	-- Marker editor (own plans) and details (recommended plans): UI/Panels/MapEditor.lua.
	local function selected()
		local p = plan()
		return p and ctx.selectedMarker and Util.FindById(p.markers, ctx.selectedMarker)
	end
	local ed = ns.MapEditor.Build(f, ctx, rail, {
		plan = plan,
		changed = changed,
		readOnly = readOnly,
		selected = selected,
		kindOptions = kindOptions,
		roleOptions = roleOptions,
		width = RAIL - 2 * SP.md,
	})
	f.editor = ed

	-- Right-click menus of markers, route points and routes: UI/Panels/MapMenus.lua.
	ns.MapMenus.Install(f, ctx)

	-- Refresh ------------------------------------------------------------------------------------------------------------

	function f:LoadFloor()
		local p = plan()
		if not p then
			return
		end
		if not ctx:Floors()[ctx.floor] then
			ctx.floor = 1
		end
		-- The floor's map art (UI/MapSpawns.lua: own map, the guide's, or the game's old dungeon map tiles), over every
		-- floor the instance has (Floors.View).
		self.canvas:LoadPlanFloor(ns.Floors.View(p), ctx.floor)
	end

	-- Focus on a step (UI.FocusStep set the floor, focus and segment): bring its spot to the middle of the map.
	function f:FocusStep(_, focus)
		self:RefreshNow() -- now: centring needs the floor loaded
		if focus and focus.x then
			self.canvas:CenterOn(focus.x, focus.y, nil, self.rail:IsShown() and -self.rail:GetWidth() / 2 or 0)
		end
	end

	-- Inside a refresh pass (UI.Batch) once at its end; otherwise now.
	function f:Refresh()
		if not ns.UI.Deferred(self) then
			self:RefreshNow()
		end
	end

	function f:RefreshNow()
		local p = plan()
		if not p then
			return
		end
		local ro = readOnly()
		if ro then
			ctx.activeRoute = nil
		end
		-- A pull or boss that is gone (deleted, undone) is no longer the current one or in focus: a stale id would
		-- leave the Pull tool adding packs to nothing and dim every marker.
		if ctx.currentPull and not Util.FindById(p.pulls, ctx.currentPull) then
			ctx.currentPull = nil
		end
		if ctx.focusPull and not Util.FindById(p.pulls, ctx.focusPull) then
			ctx.focusPull = nil
		end
		if ctx.focusEncounter and not Util.FindById(p.encounters, ctx.focusEncounter) then
			ctx.focusEncounter, ctx.focusSegment = nil, nil
		end
		-- Fitting keeps the map's content clear of the floating legend.
		local sel = selected()
		local railShown = sel ~= nil or legendShown()
		local function reserve()
			local legendW = sel and RAIL or ns.MapLegend.Folded() and (self.legend.heading:GetWidth() + 2 * SP.md) or LEGEND_W
			self.canvas.reserveRight = railShown and (legendW + RAIL_INSET) or 0
		end
		ns.MapLegend.auto = false
		reserve()
		self.canvas.fitBeside = sel ~= nil -- the marker editor takes the full height: the map sits beside it
		self:LoadFloor()
		for tool, b in pairs(self.toolButtons) do
			b:SetShown(not ro)
			b:SetActive(ctx.tool == tool)
		end
		-- Drawing tools: their own line under the toolbar, which pushes the map down while it shows.
		local drawing = not ro and ctx.tool == "draw"
		if not drawing then
			ctx.selectedShape = nil
		end
		self.drawBar:Refresh(drawing)
		self.canvas:ClearAllPoints()
		self.canvas:SetPoint("TOPLEFT", drawing and self.drawBar or bar, "BOTTOMLEFT", 0, -SP.sm)
		self.canvas:SetPoint("BOTTOMRIGHT")
		self.kind:SetShown(not ro and ctx.tool == "marker")
		self.role:SetShown(not ro and ctx.tool == "position")
		self.pull:SetShown(not ro and ctx.tool == "pull")
		local snapping = ns.MapControls.Refresh(self, p, ctx.floor, not ro and ctx.tool == "route")
		self.kind:Refresh()
		self.role:Refresh()
		self.pull:Refresh()
		self.floor:Refresh()
		self.focus:Refresh()
		-- Many floors: the toolbar's list as well as the switcher on the map.
		local many = #ctx:Floors() > ns.FloorBar.TABS
		self.floor:SetShown(many)
		self.floorBar:Refresh()
		self.focus:ClearAllPoints()
		if many then
			self.focus:SetPoint("RIGHT", self.floor, "LEFT", -SP.sm, 0)
		else
			self.focus:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
		end
		-- Narrow tables: the tools take the line, so the focus picker and Fit give way.
		local toolsW = 0
		for _, b in pairs(self.toolButtons) do
			if b:IsShown() then
				toolsW = toolsW + b:GetWidth() + SP.xs
			end
		end
		local optW = (self.kind:IsShown() or self.role:IsShown() or self.pull:IsShown()) and 160 or 0
		local rightW = (many and 158 or 0) + 178 + self.fit:GetWidth() + self.legendButton:GetWidth() + 3 * SP.sm
		local roomy = bar:GetWidth() <= 0 or toolsW + optW + rightW <= bar:GetWidth()
		self.focus:SetShown(roomy)
		self.fit:ClearAllPoints()
		self.fit:SetPoint("RIGHT", roomy and self.focus or (many and self.floor or bar), roomy and "LEFT" or
			(many and "LEFT" or "RIGHT"), roomy and -SP.sm or (many and -SP.sm or 0), 0)
		-- Still too narrow (long tool names, a floor picker): Fit gives way too, the Legend button takes its place.
		local fitRoom = roomy or toolsW + optW + rightW - 178 - SP.sm <= bar:GetWidth()
		self.fit:SetShown(fitRoom)
		self.legendButton:ClearAllPoints()
		if fitRoom then
			self.legendButton:SetPoint("RIGHT", self.fit, "LEFT", -SP.sm, 0)
		else
			self.legendButton:SetPoint("RIGHT", many and self.floor or bar, many and "LEFT" or "RIGHT",
				many and -SP.sm or 0, 0)
		end
		self.help:SetText(L[ro and TOOL_HELP.readOnly or (ctx.tool == "route" and snapping and TOOL_HELP.routeSnap)
			or TOOL_HELP[ctx.tool]])
		self.labels:SetChecked(ctx.showLabels)
		self.iconSize:Refresh()

		local m = selected()
		if not m then
			ctx.selectedMarker = nil
		end
		local list = {}
		if not m then
			for _, route in ipairs(p.routes) do
				if route.floor == ctx.floor then
					list[#list + 1] = route
				end
			end
		end
		self:PlaceLegend(p, m, ro, list)
		-- Until the player folds or opens the legend (its title), it starts folded wherever the open legend would lie
		-- over the map's picture (its painted title, the plan) or move the map; it opens by itself only in an empty band
		-- beside a narrow map. Folded, the map keeps its centre, its full size and its corner.
		if not m and legendShown() and ns.db.ui.legendFolded == nil and self:LegendOverMap() then
			ns.MapLegend.auto = true
			reserve()
			self:PlaceLegend(p, m, ro, list)
		end
		-- The legend's final size: a whole map (zoom 1) is fitted again around it when that moves the map.
		if not self.canvas:Refit() then
			self.canvas:DrawContent()
		end
	end

	-- Would the open legend cover any of the whole map (zoom 1), or has it moved or shrunk the map?
	function f:LegendOverMap()
		local c = self.canvas
		if not c:FitIsWhole() then
			return true
		end
		local w, h = c:BaseSize()
		return ns.MapLayout.PanelOverMap(railRect(), c:FitBox(), w, h)
	end

	-- The rail: the legend (counts, switches, the tool's help, the routes) or the marker editor, and its size.
	function f:PlaceLegend(p, m, ro, list)
		-- Legend counts (this floor) and layer switches.
		self.legend:Update(p, ctx.floor, self.canvas.artInfo)
		local folded = self.legend:IsFolded()
		self.rail:SetShown(m ~= nil or legendShown())
		self.legendButton:SetActive(legendShown())
		self.editor:SetShown(m ~= nil)
		self.legend:SetShown(m == nil)
		-- The legend alone is compact: the tool's help only while editing, the routes only when there are some (or the
		-- route tools can make one); the rail is as tall as that. The marker editor takes the full height and width.
		self.help:SetShown(m == nil and not ro and not folded)
		routes.fromPulls:SetShown(not ro)
		routes:Place(not ro)
		-- A recommended plan with one route on this floor: the Route row above already says so (the list would only
		-- repeat it, and its height would cover more of the map).
		self.routes:SetShown(m == nil and not folded and (ro and #list > 1 or not ro))
		-- A short map keeps the legend inside it: the tool's help gives way first (the tools' tooltips say the same),
		-- then the routes (the Pulls section and the route tool list them too).
		local maxH = (self.canvas:GetHeight() or 0) - 24
		local function railHeight()
			local h = SP.md * 2 + self.legend:GetHeight()
			if self.help:IsShown() then
				h = h + SP.sm + (self.help:GetStringHeight() or 24)
			end
			if self.routes:IsShown() then
				h = h + SP.md + 18 + SP.sm + (ro and 0 or (SZ.control + SP.sm)) + math.max(1, math.min(#list, 4)) * SZ.row
			end
			return h
		end
		if not m and maxH > 80 then
			if railHeight() > maxH then
				self.help:Hide()
			end
			if railHeight() > maxH then
				self.routes:Hide()
			end
		end
		self.routes:ClearAllPoints()
		self.routes:SetPoint("TOPLEFT", self.help:IsShown() and self.help or self.legend, "BOTTOMLEFT", 0, -SP.md)
		self.routes:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
		self.rail:ClearAllPoints()
		self.rail:SetPoint("TOPRIGHT", self.canvas, "TOPRIGHT", -RAIL_INSET, -RAIL_INSET)
		self.canvas.avoidFrame = self.rail
		if m then
			self.rail:SetWidth(RAIL)
			self.rail:SetPoint("BOTTOM", self.canvas, "BOTTOM", 0, RAIL_INSET)
			ed:ShowMarker(p, m, ro)
		else
			-- Folded: the title alone, as wide as it is.
			self.rail:SetWidth(folded and (self.legend.heading:GetWidth() + 2 * SP.md) or LEGEND_W)
			local h = railHeight()
			self.rail:SetHeight(maxH > 80 and math.min(h, maxH) or h)
			self.routes.list:SetItems(list)
		end
	end

	f:SetScript("OnShow", function(self)
		self:Refresh()
	end)
	return f
end
