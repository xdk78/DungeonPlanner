-- The map section's edit tools (own plans): Select, Marker, Position, Pull, Route, Draw, Erase, each a button with the
-- game's picture for it (UI/Art.lua tool_*) and its name, the chosen one lit. Their help: the tooltips and the legend's
-- help line (UI/Panels/MapPanel.lua).
-- Layout of the toolbar line (MapToolbar.Layout): the tools from the left, then the kind, role or pull picker of the
-- chosen tool; Legend, Fit, Focus and the floor list from the right. On a narrow table things give way in this order:
-- Focus, then the tools' names (the pictures stay, the names in their tooltips), then Fit. A tool whose picture the
-- client lacks keeps its name.

local _, ns = ...
local MapToolbar = ns:NewModule("MapToolbar")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP = S.SPACE

MapToolbar.TOOLS = { "select", "marker", "position", "pull", "route", "draw", "erase" }
local TOOL_TEXT = {
	select = "Select",
	marker = "Marker",
	position = "Position",
	pull = "Pull",
	route = "Route",
	draw = "Draw",
	erase = "Erase",
}
MapToolbar.HELP = {
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
-- What gives way on a narrow table, tried in order until the line fits: each level hides one more thing than the one
-- before (Focus, then the names, then Fit), so nothing comes back as the table narrows, and all of it returns, in the
-- reverse order, as it widens.
MapToolbar.LEVELS = {
	{ index = 1, names = true, focus = true, fit = true },
	{ index = 2, names = true, focus = false, fit = true },
	{ index = 3, names = false, focus = false, fit = true },
	{ index = 4, names = false, focus = false, fit = false },
}

-- The tool buttons in `bar`, as f.toolButtons; a click chooses the tool (`ctx.tool`) and refreshes the section.
function MapToolbar.Build(f, ctx, bar)
	f.toolButtons = {}
	local prev
	for _, tool in ipairs(MapToolbar.TOOLS) do
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
		b:SetIcon("tool_" .. tool)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", SP.xs, 0)
		else
			b:SetPoint("LEFT", 0, 0)
		end
		W.SetTooltip(b, L[TOOL_TEXT[tool]], L[TOOL_TIP[tool] or MapToolbar.HELP[tool]])
		f.toolButtons[tool] = b
		prev = b
	end
	-- A resized table lays the line out again (Layout is a few sums; the section's refresh sets `many`).
	bar:HookScript("OnSizeChanged", function()
		if f.toolbarMany ~= nil then
			MapToolbar.Layout(f, bar, f.toolbarMany)
		end
	end)
	return prev -- the last tool: the chosen tool's picker sits after it
end

-- Lay the line out for the bar's width: which of the tools' names, Focus and Fit show, and where the right-hand
-- buttons sit. `many`: the floor list shows (an instance with many floors). Returns the chosen level (LEVELS).
function MapToolbar.Layout(f, bar, many)
	f.toolbarMany = many and true or false
	local width = bar:GetWidth() or 0
	local picker = f.kind:IsShown() and f.kind or f.role:IsShown() and f.role or f.pull:IsShown() and f.pull or nil
	-- Each width measured once, without changing a button: the tools named and compact, the rest as they are.
	local named, compact = 0, 0
	for _, tool in ipairs(MapToolbar.TOOLS) do
		local b = f.toolButtons[tool]
		if b:IsShown() then
			named = named + b:WidthFor(false) + SP.xs
			compact = compact + b:WidthFor(true) + SP.xs
		end
	end
	local fixed = SP.sm + f.legendButton:GetWidth() + (picker and SP.sm + picker:GetWidth() or 0)
		+ (many and SP.sm + f.floor:GetWidth() or 0)
	local fitW, focusW = SP.sm + f.fit:GetWidth(), SP.sm + f.focus:GetWidth()
	local chosen = MapToolbar.LEVELS[1]
	if width > 0 then
		for _, level in ipairs(MapToolbar.LEVELS) do
			chosen = level
			local need = (level.names and named or compact) + fixed + (level.fit and fitW or 0)
				+ (level.focus and focusW or 0)
			if need <= width then
				break
			end
		end
	end
	for _, tool in ipairs(MapToolbar.TOOLS) do
		f.toolButtons[tool]:SetCompact(not chosen.names)
	end
	f.focus:SetShown(chosen.focus)
	f.fit:SetShown(chosen.fit)
	-- Right to left: the floor list at the edge, then Focus, Fit and Legend, each a small gap from the last.
	local last = many and f.floor or nil
	for _, item in ipairs({ f.focus, f.fit, f.legendButton }) do
		if item:IsShown() then
			item:ClearAllPoints()
			if last then
				item:SetPoint("RIGHT", last, "LEFT", -SP.sm, 0)
			else
				item:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
			end
			last = item
		end
	end
	return chosen
end
