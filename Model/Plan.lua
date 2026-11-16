-- Plan operations. A plan is a plain table (shape in Validate.lua); these functions are the only code that changes one,
-- so limits and references stay consistent (with Model/PlanLists.lua, gear and objectives, and Model/PlanBosses.lua,
-- bosses, assignments and groups). All pure: no WoW API, no UI. Each mutating call stamps plan.updated.
-- Functions that can fail return nil plus a reason ("limit", "missing", "invalid").

local _, ns = ...
local Plan = ns:NewModule("Plan")
local Util, Schema = ns.Util, ns.Schema
local MAX, TEXT = Schema.MAX, Schema.TEXT

local function touch(plan)
	plan.updated = ns.Now()
end

-- Ids are a letter plus the plan's counter: short in export strings and unique inside one plan.
local function nextId(plan, letter)
	local n = plan.nextId or 1
	plan.nextId = n + 1
	return letter .. n
end

function Plan.New(opts)
	opts = opts or {}
	local now = ns.Now()
	local raw = {
		id = Util.UniqueId("p"),
		name = opts.name or "New plan",
		author = opts.author or "",
		difficulty = opts.difficulty or "",
		instance = opts.instance or { name = "", kind = "other" },
		floors = opts.floors,
		created = now,
		updated = now,
	}
	local plan = ns.Validate.Plan(raw)
	plan.id = raw.id
	return plan
end

-- A copy with a new id and name, for "Duplicate" and for saving an imported plan next to an existing one.
-- A recommended (bundled) plan's copy keeps origin = { bundled = id, rev } and becomes an ordinary, editable plan.
function Plan.Duplicate(plan, newName)
	local copy = ns.Validate.Plan(Util.DeepCopy(plan))
	local bundledId = type(plan.id) == "string" and plan.id:match("^b:(.+)$")
	if bundledId then
		copy.origin = { bundled = bundledId, rev = plan.rev }
		copy.rev = nil
	end
	copy.id = Util.UniqueId("p")
	copy.name = Util.CleanText(newName or (plan.name .. " (copy)"), TEXT.name)
	copy.created = ns.Now()
	copy.updated = copy.created
	return copy
end

-- Store the IDs the client's Adventure Guide gave a plan (Data/Journal.lua, Journal.IdsFor), so a copy of a recommended
-- plan keeps them: IDs are the truth, names are display. Only fills what is missing; never overwrites.
-- info = { instance = { ejInstanceID, uiMapID }, encounters = { [i] = { ejEncounterID, dungeonEncounterID } },
-- floors = { [i] = uiMapID } }. Returns the number of fields filled.
function Plan.ApplyJournalIds(plan, info)
	if type(info) ~= "table" then
		return 0
	end
	local n = 0
	local function fill(t, key, value)
		if t and t[key] == nil and Util.IsInteger(value) and value > 0 then
			t[key] = value
			n = n + 1
		end
	end
	local inst = info.instance or {}
	fill(plan.instance, "ejInstanceID", inst.ejInstanceID)
	fill(plan.instance, "uiMapID", inst.uiMapID)
	for i, ids in pairs(info.encounters or {}) do
		local enc = plan.encounters[i]
		if enc and type(ids) == "table" then
			fill(enc, "ejEncounterID", ids.ejEncounterID)
			fill(enc, "dungeonEncounterID", ids.dungeonEncounterID)
		end
	end
	for i, id in pairs(info.floors or {}) do
		fill(plan.floors[i], "uiMapID", id)
	end
	if n > 0 then
		touch(plan)
	end
	return n
end

function Plan.SetField(plan, field, value)
	local limits = {
		name = TEXT.name,
		author = TEXT.author,
		difficulty = TEXT.difficulty,
	}
	local multiline = { description = TEXT.description, notes = TEXT.notes }
	if limits[field] then
		plan[field] = Util.CleanText(value, limits[field]) or ""
	elseif multiline[field] then
		plan[field] = Util.CleanText(value, multiline[field], true) or ""
	else
		return nil, "invalid"
	end
	touch(plan)
	return true
end

-- Markers -------------------------------------------------------------------------------------------------------------

-- extra (optional): { role = "TANK" | "HEALER" | "MELEE" | "RANGED", pull, encounter } for positions and the like.
function Plan.AddMarker(plan, floor, x, y, kind, label, extra)
	if #plan.markers >= MAX.markers then
		return nil, "limit"
	end
	if not (Util.IsFiniteNumber(x) and Util.IsFiniteNumber(y)) then
		return nil, "invalid"
	end
	local marker = {
		id = nextId(plan, "m"),
		floor = Util.Clamp(floor or 1, 1, #plan.floors),
		x = Util.Round(Util.Clamp(x, 0, 1), 4),
		y = Util.Round(Util.Clamp(y, 0, 1), 4),
		kind = Schema.MARKER_KIND_SET[Schema.KIND_ALIASES[kind] or kind] and (Schema.KIND_ALIASES[kind] or kind) or "note",
		label = Util.CleanText(label or "", TEXT.label) or "",
		note = "",
		icon = 0,
	}
	plan.markers[#plan.markers + 1] = marker
	touch(plan)
	if extra then
		Plan.UpdateMarker(plan, marker.id, extra)
	end
	return marker
end

function Plan.MoveMarker(plan, markerId, x, y)
	local marker = Util.FindById(plan.markers, markerId)
	if not marker then
		return nil, "missing"
	end
	marker.x = Util.Round(Util.Clamp(x, 0, 1), 4)
	marker.y = Util.Round(Util.Clamp(y, 0, 1), 4)
	touch(plan)
	return marker
end

function Plan.UpdateMarker(plan, markerId, fields)
	local marker = Util.FindById(plan.markers, markerId)
	if not marker then
		return nil, "missing"
	end
	if fields.label ~= nil then
		marker.label = Util.CleanText(fields.label, TEXT.label) or ""
	end
	if fields.note ~= nil then
		marker.note = Util.CleanText(fields.note, TEXT.note, true) or ""
	end
	local kind = fields.kind ~= nil and (Schema.KIND_ALIASES[fields.kind] or fields.kind) or nil
	if kind and Schema.MARKER_KIND_SET[kind] then
		marker.kind = kind
	end
	if fields.icon ~= nil and Util.IsInteger(fields.icon) and fields.icon >= 0 and fields.icon <= 8 then
		marker.icon = fields.icon
	end
	if fields.pull ~= nil then
		if fields.pull == false then
			marker.pull = nil
		elseif Util.FindById(plan.pulls, fields.pull) then
			marker.pull = fields.pull
		end
	end
	if fields.encounter ~= nil then
		if fields.encounter == false then
			marker.encounter = nil
		elseif Util.FindById(plan.encounters, fields.encounter) then
			marker.encounter = fields.encounter
		end
	end
	-- Version 2 fields: a position's role, a link to another floor, and the client's IDs behind a marker.
	if fields.role ~= nil then
		marker.role = Schema.POSITION_ROLE_SET[fields.role] and fields.role or nil
	end
	if marker.kind ~= "position" then
		marker.role = nil
	end
	if fields.toFloor ~= nil then
		local f = fields.toFloor
		marker.toFloor = (Util.IsInteger(f) and f >= 1 and f <= #plan.floors) and f or nil
	end
	if not Schema.LINK_KINDS[marker.kind] then
		marker.toFloor = nil
	end
	for _, key in ipairs({ "npcID", "questID" }) do
		local v = fields[key]
		if v ~= nil then
			marker[key] = (Util.IsInteger(v) and v > 0 and v < 2 ^ 31) and v or nil
		end
	end
	if fields.itemID ~= nil then
		marker.itemID = fields.itemID ~= false and Util.ParseItemID(fields.itemID) or nil
	end
	touch(plan)
	return marker
end

function Plan.RemoveMarker(plan, markerId)
	local _, index = Util.FindById(plan.markers, markerId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.markers, index)
	for _, a in ipairs(plan.assignments) do
		if a.marker == markerId then
			a.marker = nil
		end
	end
	touch(plan)
	return true
end

-- Nearest marker to (x, y) on a floor within `radius` (normalized units), for clicks and erasing.
function Plan.MarkerAt(plan, floor, x, y, radius, aspect)
	aspect = aspect or 1
	local best, bestDist = nil, radius * radius
	for _, m in ipairs(plan.markers) do
		if m.floor == floor then
			local dx, dy = (m.x - x) * aspect, m.y - y
			local d = dx * dx + dy * dy
			if d <= bestDist then
				best, bestDist = m, d
			end
		end
	end
	return best
end

-- Floors ----------------------------------------------------------------------------------------------------------------

function Plan.SetFloors(plan, floors)
	if type(floors) ~= "table" or #floors == 0 then
		return nil, "invalid"
	end
	local clean = {}
	for i, f in ipairs(floors) do
		if i > MAX.floors then
			break
		end
		clean[i] = {
			uiMapID = Util.IsInteger(f.uiMapID) and f.uiMapID > 0 and f.uiMapID or nil,
			name = Util.CleanText(f.name or "", TEXT.name) or "",
		}
	end
	plan.floors = clean
	-- Anything on a floor that no longer exists moves to floor 1 rather than disappearing.
	for _, m in ipairs(plan.markers) do
		if m.floor > #clean then
			m.floor = 1
		end
		if m.toFloor and m.toFloor > #clean then
			m.toFloor = nil
		end
	end
	for _, r in ipairs(plan.routes) do
		if r.floor > #clean then
			r.floor = 1
		end
	end
	ns.Drawing.ClampFloors(plan, #clean)
	touch(plan)
	return true
end

-- Routes ----------------------------------------------------------------------------------------------------------------

function Plan.AddRoute(plan, floor, name, color)
	if #plan.routes >= MAX.routes then
		return nil, "limit"
	end
	local route = {
		id = nextId(plan, "r"),
		name = Util.CleanText(name or "", TEXT.label) or "",
		floor = Util.Clamp(floor or 1, 1, #plan.floors),
		color = (Util.IsInteger(color) and color >= 1 and color <= Schema.COLOR_COUNT) and color or 1,
		points = {},
	}
	plan.routes[#plan.routes + 1] = route
	touch(plan)
	return route
end

function Plan.AddRoutePoint(plan, routeId, x, y)
	local route = Util.FindById(plan.routes, routeId)
	if not route then
		return nil, "missing"
	end
	if #route.points >= MAX.routePoints then
		return nil, "limit"
	end
	route.points[#route.points + 1] = { Util.Round(Util.Clamp(x, 0, 1), 4), Util.Round(Util.Clamp(y, 0, 1), 4) }
	touch(plan)
	return route
end

function Plan.RemoveLastRoutePoint(plan, routeId)
	local route = Util.FindById(plan.routes, routeId)
	if not route or #route.points == 0 then
		return nil, "missing"
	end
	route.points[#route.points] = nil
	touch(plan)
	return route
end

-- name, color 1..COLOR_COUNT, optional (drawn fainter: a skip or an alternative path).
function Plan.UpdateRoute(plan, routeId, fields)
	local route = Util.FindById(plan.routes, routeId)
	if not route then
		return nil, "missing"
	end
	if fields.name ~= nil then
		route.name = Util.CleanText(fields.name, TEXT.label) or route.name
	end
	if Util.IsInteger(fields.color) and fields.color >= 1 and fields.color <= Schema.COLOR_COUNT then
		route.color = fields.color
	end
	if fields.optional ~= nil then
		route.optional = fields.optional and true or nil
	end
	touch(plan)
	return route
end

-- Number the route's stops 1, 2, 3 ... in path order (after adding, removing or reordering stops).
function Plan.RenumberStops(plan, routeId)
	local route = Util.FindById(plan.routes, routeId)
	if not route then
		return nil, "missing"
	end
	local n = 0
	for _, point in ipairs(route.points) do
		if point.step then
			n = n + 1
			point.step = math.min(n, Schema.MAX_STEP)
		end
	end
	touch(plan)
	return n
end

-- Make point `index` a numbered stop (true) or a plain bend of the path (false). Stops are renumbered.
function Plan.SetRouteStop(plan, routeId, index, isStop)
	local route = Util.FindById(plan.routes, routeId)
	local point = route and route.points[index]
	if not point then
		return nil, "missing"
	end
	if isStop then
		point.step = point.step or Schema.MAX_STEP
	else
		point.step, point.note, point.pull = nil, nil, nil
	end
	Plan.RenumberStops(plan, routeId)
	return point
end

-- A stop's note and pull (the pull to take at this stop).
function Plan.UpdateRoutePoint(plan, routeId, index, fields)
	local route = Util.FindById(plan.routes, routeId)
	local point = route and route.points[index]
	if not point or not point.step then
		return nil, "missing"
	end
	if fields.note ~= nil then
		local note = Util.CleanText(fields.note, TEXT.short) or ""
		point.note = note ~= "" and note or nil
	end
	if fields.pull ~= nil then
		point.pull = fields.pull and Util.FindById(plan.pulls, fields.pull) and fields.pull or nil
	end
	touch(plan)
	return point
end

function Plan.MoveRoutePoint(plan, routeId, index, x, y)
	local route = Util.FindById(plan.routes, routeId)
	local point = route and route.points[index]
	if not point then
		return nil, "missing"
	end
	point[1] = Util.Round(Util.Clamp(x, 0, 1), 4)
	point[2] = Util.Round(Util.Clamp(y, 0, 1), 4)
	touch(plan)
	return point
end

function Plan.RemoveRoute(plan, routeId)
	local _, index = Util.FindById(plan.routes, routeId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.routes, index)
	touch(plan)
	return true
end

-- Pulls -----------------------------------------------------------------------------------------------------------------

function Plan.AddPull(plan, name)
	if #plan.pulls >= MAX.pulls then
		return nil, "limit"
	end
	local index = #plan.pulls + 1
	local pull = {
		id = nextId(plan, "u"),
		name = Util.CleanText(name or ("Pull " .. index), TEXT.label) or "",
		note = "",
		color = ((index - 1) % Schema.COLOR_COUNT) + 1,
	}
	plan.pulls[index] = pull
	touch(plan)
	return pull
end

function Plan.UpdatePull(plan, pullId, fields)
	local pull = Util.FindById(plan.pulls, pullId)
	if not pull then
		return nil, "missing"
	end
	if fields.name ~= nil then
		pull.name = Util.CleanText(fields.name, TEXT.label) or ""
	end
	if fields.note ~= nil then
		pull.note = Util.CleanText(fields.note, TEXT.note, true) or ""
	end
	if fields.color ~= nil and Util.IsInteger(fields.color) and fields.color >= 1 and fields.color <= Schema.COLOR_COUNT then
		pull.color = fields.color
	end
	-- Format 3: tags (a list, or { tag = true/false } to switch some), planned cooldowns, Bloodlust, progress (0-100,
	-- false clears it).
	if type(fields.tags) == "table" then
		local set = {}
		for _, tag in ipairs(pull.tags or {}) do
			set[tag] = true
		end
		if fields.tags[1] ~= nil or next(fields.tags) == nil then
			set = {}
			for _, tag in ipairs(fields.tags) do
				set[tag] = true
			end
		else
			for tag, on in pairs(fields.tags) do
				set[tag] = on and true or nil
			end
		end
		local list = {}
		for tag in pairs(set) do
			list[#list + 1] = tag
		end
		pull.tags = ns.Validate.PullTags(list)
	end
	if fields.cd ~= nil then
		pull.cd = fields.cd and true or nil
	end
	if fields.lust ~= nil then
		pull.lust = fields.lust and true or nil
	end
	if fields.progress ~= nil then
		local v = fields.progress
		pull.progress = (Util.IsFiniteNumber(v) and v >= 0 and v <= 100) and math.floor(v + 0.5) or nil
	end
	touch(plan)
	return pull
end

function Plan.HasTag(pull, tag)
	for _, t in ipairs(pull and pull.tags or {}) do
		if t == tag then
			return true
		end
	end
	return false
end

-- Move a pull up (-1) or down (+1) in the order.
function Plan.MovePull(plan, pullId, delta)
	local _, index = Util.FindById(plan.pulls, pullId)
	if not index then
		return nil, "missing"
	end
	local target = index + delta
	if target < 1 or target > #plan.pulls then
		return nil, "invalid"
	end
	plan.pulls[index], plan.pulls[target] = plan.pulls[target], plan.pulls[index]
	touch(plan)
	return true
end

function Plan.RemovePull(plan, pullId)
	local _, index = Util.FindById(plan.pulls, pullId)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.pulls, index)
	for _, m in ipairs(plan.markers) do
		if m.pull == pullId then
			m.pull = nil
		end
	end
	for _, route in ipairs(plan.routes) do
		for _, point in ipairs(route.points) do
			if point.pull == pullId then
				point.pull = nil
			end
		end
	end
	ns.Drawing.Unlink(plan, "pull", pullId)
	touch(plan)
	return true
end

function Plan.PullIndex(plan, pullId)
	local _, index = Util.FindById(plan.pulls, pullId)
	return index
end

function Plan.MarkersOfPull(plan, pullId)
	local out = {}
	for _, m in ipairs(plan.markers) do
		if m.pull == pullId then
			out[#out + 1] = m
		end
	end
	return out
end


-- Recommended plans are read-only ------------------------------------------------------------------------------------------
-- Every function above that changes a plan refuses a bundled one (Model/Bundled.lua) with nil, "read-only", so no UI
-- path can edit the shared copy by accident; the player edits a copy (Plan.Duplicate).

local READ_ONLY_SAFE = {
	New = true,
	Duplicate = true,
	MarkerAt = true,
	PullIndex = true,
	MarkersOfPull = true,
	HasTag = true,
}
for name, fn in pairs(Plan) do
	if type(fn) == "function" and not READ_ONLY_SAFE[name] then
		Plan[name] = function(plan, ...)
			if type(plan) == "table" and plan.bundled then
				return nil, "read-only"
			end
			return fn(plan, ...)
		end
	end
end
