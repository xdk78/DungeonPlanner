-- Map drawings: freehand strokes, lines, arrows, circles, rectangles and text labels a planner draws over the map. Pure
-- (no game API): the data model, its edits, the geometry the map draws from, and hit-testing. UI/MapDraw.lua draws and
-- edits them on the map canvas; Validate.lua checks them on every plan that enters the addon.
--
-- Storage, in the plan (optional; absent when a plan has no drawings, so older readers and older strings are untouched):
--
--   plan.drawings = { v = 1, shapes = { shape, ... } }
--   shape = { id = "d12", floor = 1, kind = "pen" | "line" | "arrow" | "circle" | "rect" | "text",
--             color = 1..8 (the pull palette, so the colour-blind setting recolours drawings too), width = 1..3,
--             pts = { x1, y1, x2, y2, ... } (normalized 0..1 over the floor's map art, 3 decimals),
--             text? (a text label), author? (who drew it), pull? / encounter? (shown with that step in run mode) }
--
-- pen: a polyline, simplified with Ramer-Douglas-Peucker and quantized, at most Schema.MAX.strokePoints points.
-- line, arrow: 2 points (from, to; the arrow's head at the end). circle: the 2 corners of the box the ellipse fills.
-- rect: 2 opposite corners. text: 1 point (the label's centre) and its text.
--
-- Every function that changes a plan refuses a recommended (bundled) plan, like Model/Plan.lua; each change stamps
-- plan.updated. Ids come from the plan's own counter (letter "d"), shared with markers, pulls and routes.

local _, ns = ...
local Drawing = ns:NewModule("Drawing")
local Util, Schema = ns.Util, ns.Schema

Drawing.VERSION = 1
Drawing.KINDS = { "pen", "line", "arrow", "circle", "rect", "text" }
Drawing.KIND_SET = { pen = true, line = true, arrow = true, circle = true, rect = true, text = true }
Drawing.WIDTHS = 3 -- thin, medium, thick
Drawing.DECIMALS = 3
Drawing.ELLIPSE_SEGMENTS = 24
-- The number of points each kind needs (pen: at least 2, at most Schema.MAX.strokePoints).
Drawing.POINTS = { line = 2, arrow = 2, circle = 2, rect = 2, text = 1 }

local EMPTY = {}
local sqrt, abs, max, min = math.sqrt, math.abs, math.max, math.min

local function touch(plan)
	plan.updated = ns.Now()
end

local function q(v)
	return Util.Round(Util.Clamp(v, 0, 1), Drawing.DECIMALS)
end

-- The plan's shapes (never nil; read-only use).
function Drawing.Shapes(plan)
	local d = plan and plan.drawings
	return type(d) == "table" and type(d.shapes) == "table" and d.shapes or EMPTY
end

function Drawing.OnFloor(plan, floor)
	local out = {}
	for _, s in ipairs(Drawing.Shapes(plan)) do
		if s.floor == floor then
			out[#out + 1] = s
		end
	end
	return out
end

function Drawing.Count(plan, floor)
	local n = 0
	for _, s in ipairs(Drawing.Shapes(plan)) do
		if floor == nil or s.floor == floor then
			n = n + 1
		end
	end
	return n
end

-- Geometry ----------------------------------------------------------------------------------------------------------------
-- Distances are measured with x scaled by the map's aspect (width / height), so a tolerance means the same on screen
-- in both directions (as Plan.MarkerAt does).

-- Distance from (px, py) to the segment a-b.
local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local t = 0
	if len2 > 0 then
		t = ((px - ax) * dx + (py - ay) * dy) / len2
		t = t < 0 and 0 or (t > 1 and 1 or t)
	end
	local cx, cy = ax + t * dx - px, ay + t * dy - py
	return sqrt(cx * cx + cy * cy)
end
Drawing.SegmentDistance = segDist

-- Ramer-Douglas-Peucker on a flat point list { x1, y1, ... }: keeps the points that matter for the shape within
-- `epsilon` (in aspect-scaled units). Returns a new flat list. Iterative (no recursion depth to worry about).
function Drawing.Simplify(pts, epsilon, aspect)
	aspect = aspect or 1
	local n = math.floor(#pts / 2)
	if n <= 2 then
		local copy = {}
		for i = 1, n * 2 do
			copy[i] = pts[i]
		end
		return copy
	end
	local keep = { [1] = true, [n] = true }
	local stack = { 1, n }
	while #stack > 0 do
		local last = table.remove(stack)
		local first = table.remove(stack)
		local ax, ay = pts[2 * first - 1] * aspect, pts[2 * first]
		local bx, by = pts[2 * last - 1] * aspect, pts[2 * last]
		local worst, at = 0, nil
		for i = first + 1, last - 1 do
			local d = segDist(pts[2 * i - 1] * aspect, pts[2 * i], ax, ay, bx, by)
			if d > worst then
				worst, at = d, i
			end
		end
		if at and worst > epsilon then
			keep[at] = true
			stack[#stack + 1] = first
			stack[#stack + 1] = at
			stack[#stack + 1] = at
			stack[#stack + 1] = last
		end
	end
	local out = {}
	for i = 1, n do
		if keep[i] then
			out[#out + 1] = pts[2 * i - 1]
			out[#out + 1] = pts[2 * i]
		end
	end
	return out
end

-- Round to the stored precision and drop points that became equal to the one before.
function Drawing.Quantize(pts)
	local out = {}
	local lx, ly
	for i = 1, #pts - 1, 2 do
		local x, y = q(pts[i]), q(pts[i + 1])
		if x ~= lx or y ~= ly then
			out[#out + 1] = x
			out[#out + 1] = y
			lx, ly = x, y
		end
	end
	return out
end

-- A freehand stroke ready to store: simplified (the tolerance grows until it fits maxPoints), quantized. nil when
-- fewer than 2 distinct points remain (a click, not a stroke).
function Drawing.FitStroke(pts, opts)
	opts = opts or {}
	local maxPoints = opts.maxPoints or Schema.MAX.strokePoints
	local aspect = opts.aspect or 1
	local epsilon = opts.epsilon or 0.002
	local out = Drawing.Simplify(pts, epsilon, aspect)
	local tries = 0
	while #out / 2 > maxPoints and tries < 40 do
		epsilon = epsilon * 1.5
		out = Drawing.Simplify(pts, epsilon, aspect)
		tries = tries + 1
	end
	if #out / 2 > maxPoints then
		-- Pathological input: keep evenly spaced points, the ends included.
		local n, kept = #out / 2, {}
		for k = 0, maxPoints - 1 do
			local i = 1 + math.floor(k * (n - 1) / (maxPoints - 1) + 0.5)
			kept[#kept + 1] = out[2 * i - 1]
			kept[#kept + 1] = out[2 * i]
		end
		out = kept
	end
	out = Drawing.Quantize(out)
	if #out < 4 then
		return nil
	end
	return out
end

-- Where to draw a round joint on a polyline: at bends sharper than `minDegrees` (shallow bends need none: the line
-- segments overlap enough). Returns point indexes (1-based, interior points only).
function Drawing.Joints(pts, minDegrees, aspect)
	aspect = aspect or 1
	local out = {}
	local cosLimit = math.cos(math.rad(minDegrees or 20))
	local n = math.floor(#pts / 2)
	for i = 2, n - 1 do
		local ax, ay = (pts[2 * i - 1] - pts[2 * i - 3]) * aspect, pts[2 * i] - pts[2 * i - 2]
		local bx, by = (pts[2 * i + 1] - pts[2 * i - 1]) * aspect, pts[2 * i + 2] - pts[2 * i]
		local la, lb = sqrt(ax * ax + ay * ay), sqrt(bx * bx + by * by)
		if la > 0 and lb > 0 and (ax * bx + ay * by) / (la * lb) < cosLimit then
			out[#out + 1] = i
		end
	end
	return out
end

-- The ellipse inside the box (x1, y1)-(x2, y2) as a closed flat polyline.
function Drawing.Ellipse(x1, y1, x2, y2, segments)
	segments = segments or Drawing.ELLIPSE_SEGMENTS
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
	local rx, ry = abs(x2 - x1) / 2, abs(y2 - y1) / 2
	local out = {}
	for k = 0, segments do
		local a = 2 * math.pi * k / segments
		out[#out + 1] = cx + rx * math.cos(a)
		out[#out + 1] = cy + ry * math.sin(a)
	end
	return out
end

-- The arrow head's two strokes at (x2, y2), each `len` long (aspect-scaled units), 28 degrees off the shaft.
function Drawing.ArrowHead(x1, y1, x2, y2, len, aspect)
	aspect = aspect or 1
	local dx, dy = (x2 - x1) * aspect, y2 - y1
	local l = sqrt(dx * dx + dy * dy)
	if l == 0 then
		return nil
	end
	local ux, uy = dx / l, dy / l
	local spread = math.rad(28)
	local heads = {}
	for _, s in ipairs({ spread, -spread }) do
		local c, sn = math.cos(s), math.sin(s)
		local hx, hy = -(ux * c - uy * sn) * len, -(ux * sn + uy * c) * len
		heads[#heads + 1] = { x2, y2, x2 + hx / aspect, y2 + hy }
	end
	return heads
end

-- The lines a shape is drawn with: a list of flat polylines in map coordinates. o = { aspect, head (the arrow head's
-- length in aspect-scaled units), dx, dy (an offset while the shape is being moved) }. Text has none.
function Drawing.Polylines(shape, o)
	o = o or {}
	local pts = shape.pts or EMPTY
	local dx, dy = o.dx or 0, o.dy or 0
	local function at(i)
		return (pts[2 * i - 1] or 0) + dx, (pts[2 * i] or 0) + dy
	end
	local kind = shape.kind
	if kind == "pen" then
		if dx == 0 and dy == 0 then
			return { pts }
		end
		local moved = {}
		for i = 1, #pts, 2 do
			moved[i], moved[i + 1] = pts[i] + dx, pts[i + 1] + dy
		end
		return { moved }
	end
	local x1, y1 = at(1)
	local x2, y2 = at(2)
	if kind == "line" then
		return { { x1, y1, x2, y2 } }
	elseif kind == "arrow" then
		local out = { { x1, y1, x2, y2 } }
		for _, h in ipairs(Drawing.ArrowHead(x1, y1, x2, y2, o.head or 0.025, o.aspect) or EMPTY) do
			out[#out + 1] = h
		end
		return out
	elseif kind == "rect" then
		return { { x1, y1, x2, y1, x2, y2, x1, y2, x1, y1 } }
	elseif kind == "circle" then
		return { Drawing.Ellipse(x1, y1, x2, y2) }
	end
	return {}
end

-- How far (x, y) is from what the shape draws, in aspect-scaled units. A text label counts as a box of
-- o.textW x o.textH around its point (in aspect-scaled units; defaults suit a short label).
function Drawing.Distance(shape, x, y, o)
	o = o or {}
	local aspect = o.aspect or 1
	if shape.kind == "text" then
		local pts = shape.pts or EMPTY
		local cx, cy = (pts[1] or 0) * aspect, pts[2] or 0
		local hw, hh = (o.textW or 0.12) / 2, (o.textH or 0.03) / 2
		local ddx = max(0, abs(x * aspect - cx) - hw)
		local ddy = max(0, abs(y - cy) - hh)
		return sqrt(ddx * ddx + ddy * ddy)
	end
	local best = math.huge
	for _, line in ipairs(Drawing.Polylines(shape, o)) do
		if #line == 2 then
			best = min(best, sqrt(((line[1] - x) * aspect) ^ 2 + (line[2] - y) ^ 2))
		end
		for i = 3, #line - 1, 2 do
			local d = segDist(x * aspect, y, line[i - 2] * aspect, line[i - 1], line[i] * aspect, line[i + 1])
			if d < best then
				best = d
			end
		end
	end
	return best
end

-- The shape on `floor` nearest to (x, y) within `tolerance`, preferring the one drawn last (on top). `shown(shape)`
-- (optional) leaves out shapes that are hidden.
function Drawing.HitTest(plan, floor, x, y, tolerance, o, shown)
	local best, bestD
	local shapes = Drawing.Shapes(plan)
	for i = #shapes, 1, -1 do
		local s = shapes[i]
		if s.floor == floor and (not shown or shown(s)) then
			local d = Drawing.Distance(s, x, y, o)
			if d <= tolerance and (not bestD or d < bestD - 1e-9) then
				best, bestD = s, d
			end
		end
	end
	return best
end

-- Shapes linked to a pull or a boss show with that step; unlinked ones always. mode = "all" | "step" | "off".
function Drawing.Visible(shape, mode, focusPull, focusEncounter)
	if mode == "off" then
		return false
	end
	if mode ~= "step" or not (shape.pull or shape.encounter) then
		return true
	end
	return (shape.pull ~= nil and shape.pull == focusPull) or (shape.encounter ~= nil and shape.encounter == focusEncounter)
end

-- Edits ---------------------------------------------------------------------------------------------------------------------

local function store(plan)
	if type(plan.drawings) ~= "table" or type(plan.drawings.shapes) ~= "table" then
		plan.drawings = { v = Drawing.VERSION, shapes = {} }
	end
	return plan.drawings.shapes
end

local function tidy(plan)
	if type(plan.drawings) == "table" and #Drawing.Shapes(plan) == 0 then
		plan.drawings = nil
	end
end

local function findShape(plan, id)
	for i, s in ipairs(Drawing.Shapes(plan)) do
		if s.id == id then
			return s, i
		end
	end
	return nil
end
Drawing.Find = findShape

local function clampWidth(w)
	return (Util.IsInteger(w) and w >= 1 and w <= Drawing.WIDTHS) and w or 2
end
local function clampColor(c)
	return (Util.IsInteger(c) and c >= 1 and c <= Schema.COLOR_COUNT) and c or 1
end

-- Add a shape. pts: a flat list in map coordinates (a pen stroke as drawn: it is simplified here). fields = { color,
-- width, text, author, pull, encounter, aspect, epsilon (the simplification tolerance) }. Returns the shape, or nil and "limit" | "invalid".
function Drawing.Add(plan, floor, kind, pts, fields)
	fields = fields or {}
	if not Drawing.KIND_SET[kind] or type(pts) ~= "table" then
		return nil, "invalid"
	end
	floor = Util.IsInteger(floor) and floor >= 1 and floor <= #plan.floors and floor or 1
	if Drawing.Count(plan) >= Schema.MAX.drawings or Drawing.Count(plan, floor) >= Schema.MAX.drawingsPerFloor then
		return nil, "limit"
	end
	for i = 1, #pts do
		if not Util.IsFiniteNumber(pts[i]) then
			return nil, "invalid"
		end
	end
	local clean
	if kind == "pen" then
		clean = Drawing.FitStroke(pts, { aspect = fields.aspect, epsilon = fields.epsilon })
	else
		local need = Drawing.POINTS[kind]
		if #pts < need * 2 then
			return nil, "invalid"
		end
		clean = {}
		for i = 1, need * 2 do
			clean[i] = q(pts[i])
		end
		-- A line, arrow, circle or box with no size is a stray click.
		if need == 2 and clean[1] == clean[3] and clean[2] == clean[4] then
			clean = nil
		end
	end
	if not clean then
		return nil, "invalid"
	end
	local text
	if kind == "text" then
		text = Util.CleanText(fields.text or "", Schema.TEXT.label) or ""
		if text == "" then
			return nil, "invalid"
		end
	end
	local n = plan.nextId or 1
	plan.nextId = n + 1
	local shape = {
		id = "d" .. n,
		floor = floor,
		kind = kind,
		color = clampColor(fields.color),
		width = clampWidth(fields.width),
		pts = clean,
		text = text,
		author = fields.author and Util.CleanText(fields.author, Schema.TEXT.player) or nil,
		pull = fields.pull and Util.FindById(plan.pulls, fields.pull) and fields.pull or nil,
		encounter = fields.encounter and Util.FindById(plan.encounters, fields.encounter) and fields.encounter or nil,
	}
	if shape.author == "" then
		shape.author = nil
	end
	local shapes = store(plan)
	shapes[#shapes + 1] = shape
	touch(plan)
	return shape
end

-- Change a shape's colour, width, text or its pull / boss link (false clears a link).
function Drawing.Update(plan, id, fields)
	local s = findShape(plan, id)
	if not s then
		return nil, "missing"
	end
	if fields.color ~= nil then
		s.color = clampColor(fields.color)
	end
	if fields.width ~= nil then
		s.width = clampWidth(fields.width)
	end
	if fields.text ~= nil and s.kind == "text" then
		local t = Util.CleanText(fields.text, Schema.TEXT.label) or ""
		if t == "" then
			return nil, "invalid"
		end
		s.text = t
	end
	if fields.pull ~= nil then
		s.pull = fields.pull and Util.FindById(plan.pulls, fields.pull) and fields.pull or nil
		if s.pull then
			s.encounter = nil
		end
	end
	if fields.encounter ~= nil then
		s.encounter = fields.encounter and Util.FindById(plan.encounters, fields.encounter) and fields.encounter or nil
		if s.encounter then
			s.pull = nil
		end
	end
	touch(plan)
	return s
end

-- Move a shape by (dx, dy), kept whole inside the map.
function Drawing.Move(plan, id, dx, dy)
	local s = findShape(plan, id)
	if not s or not (Util.IsFiniteNumber(dx) and Util.IsFiniteNumber(dy)) then
		return nil, "missing"
	end
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for i = 1, #s.pts - 1, 2 do
		minX, maxX = min(minX, s.pts[i]), max(maxX, s.pts[i])
		minY, maxY = min(minY, s.pts[i + 1]), max(maxY, s.pts[i + 1])
	end
	dx = Util.Clamp(dx, -minX, 1 - maxX)
	dy = Util.Clamp(dy, -minY, 1 - maxY)
	for i = 1, #s.pts - 1, 2 do
		s.pts[i], s.pts[i + 1] = q(s.pts[i] + dx), q(s.pts[i + 1] + dy)
	end
	touch(plan)
	return s
end

function Drawing.Remove(plan, id)
	local _, index = findShape(plan, id)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.drawings.shapes, index)
	tidy(plan)
	touch(plan)
	return true
end

-- Remove every shape on `floor` (nil: every floor). Returns how many went.
function Drawing.Clear(plan, floor)
	local shapes = Drawing.Shapes(plan)
	local n = 0
	for i = #shapes, 1, -1 do
		if floor == nil or shapes[i].floor == floor then
			table.remove(shapes, i)
			n = n + 1
		end
	end
	if n > 0 then
		tidy(plan)
		touch(plan)
	end
	return n
end

-- Keep links and floors consistent when the plan changes around the drawings (Plan.RemovePull, RemoveEncounter,
-- SetFloors call these). Not wrapped: callers already checked the plan is editable.
function Drawing.Unlink(plan, field, id)
	for _, s in ipairs(Drawing.Shapes(plan)) do
		if s[field] == id then
			s[field] = nil
		end
	end
end

function Drawing.ClampFloors(plan, floorCount)
	for _, s in ipairs(Drawing.Shapes(plan)) do
		if s.floor > floorCount then
			s.floor = 1
		end
	end
end

-- Recommended plans are read-only (Model/Plan.lua does the same for its functions).
local READ_ONLY_SAFE = {
	Shapes = true,
	OnFloor = true,
	Count = true,
	SegmentDistance = true,
	Simplify = true,
	Quantize = true,
	FitStroke = true,
	Joints = true,
	Ellipse = true,
	ArrowHead = true,
	Polylines = true,
	Distance = true,
	HitTest = true,
	Visible = true,
	Find = true,
}
for name, fn in pairs(Drawing) do
	if type(fn) == "function" and not READ_ONLY_SAFE[name] then
		Drawing[name] = function(plan, ...)
			if type(plan) == "table" and plan.bundled then
				return nil, "read-only"
			end
			return fn(plan, ...)
		end
	end
end
