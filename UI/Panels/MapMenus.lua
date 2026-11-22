-- Map section, part 2: the right-click menus. A marker: details or edit, go to the floor it leads to, add to or take
-- out of the current pull, delete. A route point: make it a numbered stop or a bend, the stop's note and pull, delete.
-- A route: rename, suggest an order, colour, main or optional, remove the last point, delete. Recommended plans offer
-- only what reads.

local _, ns = ...
local W, L = ns.Widgets, ns.L
local Plan, Util, Schema, Route = ns.Plan, ns.Util, ns.Schema, ns.Route

local MapMenus = ns:NewModule("MapMenus")

function MapMenus.Install(f, ctx)
	local function plan()
		return ctx:Plan()
	end
	local function changed(what)
		ctx:Changed(what)
	end
	local function readOnly()
		return ctx:ReadOnly()
	end


	function f:MarkerMenu(id, owner)
		local p = plan()
		local m = p and Util.FindById(p.markers, id)
		if not m then
			return
		end
		local items = { { title = m.label ~= "" and m.label or L[m.kind] } }
		items[#items + 1] = {
			readOnly() and L["Details"] or L["Edit"],
			function()
				ctx.selectedMarker = id
				ctx.tool = "select"
				f:Refresh()
			end,
		}
		if m.toFloor and p.floors[m.toFloor] then
			items[#items + 1] = {
				string.format(L["Go to %s"], ns.Names.Floor(p.floors[m.toFloor], m.toFloor, p)),
				function()
					ctx.floor = m.toFloor
					ctx.selectedMarker = nil
					f:LoadFloor()
					f:Refresh()
				end,
			}
		end
		if not readOnly() then
			if ctx.currentPull then
				items[#items + 1] = {
					m.pull == ctx.currentPull and L["Remove from current pull"] or L["Add to current pull"],
					function()
						Plan.UpdateMarker(p, id, { pull = m.pull == ctx.currentPull and false or ctx.currentPull })
						changed("pulls")
					end,
				}
			end
			items[#items + 1] = "-"
			items[#items + 1] = {
				L["Delete marker"],
				function()
					Plan.RemoveMarker(p, id)
					if ctx.selectedMarker == id then
						ctx.selectedMarker = nil
					end
					changed("markers")
				end,
			}
		end
		W.Menu(owner, items)
	end

	function f:PointMenu(routeId, index, owner)
		local p = plan()
		local route = p and Util.FindById(p.routes, routeId)
		local pt = route and route.points[index]
		if not pt or readOnly() then
			return
		end
		local items = { { title = pt.step and string.format(L["Stop %d"], pt.step) or ns.Names.Route(route) } }
		items[#items + 1] = {
			pt.step and L["Make it a bend"] or L["Make it a numbered stop"],
			function()
				Plan.SetRouteStop(p, routeId, index, not pt.step)
				changed("routes")
			end,
		}
		if pt.step then
			items[#items + 1] = {
				L["Note..."],
				function()
					W.AskText(string.format(L["Stop %d"], pt.step), L["What happens at this stop."], pt.note or "", function(text)
						Plan.UpdateRoutePoint(p, routeId, index, { note = text })
						changed("routes")
					end)
				end,
			}
			for i, pull in ipairs(p.pulls) do
				if i > 12 then
					break
				end
				items[#items + 1] = {
					(pt.pull == pull.id and "> " or "") .. string.format(L["Pull %d: %s"], i, pull.name),
					function()
						Plan.UpdateRoutePoint(p, routeId, index, { pull = pt.pull ~= pull.id and pull.id or false })
						changed("routes")
					end,
				}
			end
		end
		items[#items + 1] = "-"
		items[#items + 1] = {
			L["Delete point"],
			function()
				table.remove(route.points, index)
				Plan.RenumberStops(p, routeId)
				changed("routes")
			end,
		}
		W.Menu(owner, items)
	end

	function f:RouteMenu(route, owner)
		local p = plan()
		if readOnly() then
			return
		end
		W.Menu(owner, {
			{ title = ns.Names.Route(route) },
			{
				L["Rename"],
				function()
					W.AskText(L["Rename route"], "", route.name, function(value)
						Plan.UpdateRoute(p, route.id, { name = value })
						changed("routes")
					end)
				end,
			},
			{
				L["Suggest order"],
				function()
					-- Reorder the route's points into a short path, keeping the first point as the start.
					local order = Route.SuggestOrder(route.points, f.canvas:Aspect(), 1)
					local reordered = {}
					for i, index in ipairs(order) do
						reordered[i] = route.points[index]
					end
					route.points = reordered
					Plan.RenumberStops(p, route.id)
					changed("routes")
				end,
			},
			{
				L["Next colour"],
				function()
					Plan.UpdateRoute(p, route.id, { color = (route.color % Schema.COLOR_COUNT) + 1 })
					changed("routes")
				end,
			},
			{
				route.optional and L["Mark as the main route"] or L["Mark as optional"],
				function()
					Plan.UpdateRoute(p, route.id, { optional = not route.optional })
					changed("routes")
				end,
			},
			{
				L["Remove last point"],
				function()
					Plan.RemoveLastRoutePoint(p, route.id)
					Plan.RenumberStops(p, route.id)
					changed("routes")
				end,
			},
			"-",
			{
				L["Delete route"],
				function()
					Plan.RemoveRoute(p, route.id)
					if ctx.activeRoute == route.id then
						ctx.activeRoute = nil
					end
					changed("routes")
				end,
			},
		})
	end
end
