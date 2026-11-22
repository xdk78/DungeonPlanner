-- Validation and sanitizing. Every plan that enters the addon goes through Validate.Plan: plans created here, plans read
-- from SavedVariables, imported strings and plans received from other players. It never trusts the input: it builds a
-- fresh table holding only known fields of the right type and size, drops what does not fit, and fixes references
-- (a marker's pull must exist, and so on). It never executes anything (no loadstring anywhere in the addon).

local _, ns = ...
local Validate = ns:NewModule("Validate")
local Util, Schema = ns.Util, ns.Schema

local type, ipairs = type, ipairs
local TEXT, MAX = Schema.TEXT, Schema.MAX

local function text(value, limit, multiline)
	return Util.CleanText(value, limit, multiline)
end

local function int(value, low, high)
	if not Util.IsInteger(value) then
		return nil
	end
	if (low and value < low) or (high and value > high) then
		return nil
	end
	return value
end

local function coord(value)
	if not Util.IsFiniteNumber(value) then
		return nil
	end
	return Util.Round(Util.Clamp(value, 0, 1), 4)
end

-- Ids are a letter and the plan's counter (Plan.lua's nextId). A plan from outside (an import, a received plan) may
-- only use ids up to STRICT_ID_LENGTH characters: the plan's counter continues after the highest id, and an id grown
-- past 12 characters would be dropped the next time the plan loads. Saved plans keep the full 12.
local STRICT_ID_LENGTH = 9
local idLength = 12

local function id(value)
	if type(value) == "string" and #value <= idLength and value:match("^%l%d+$") then
		return value
	end
	return nil
end

local function list(value)
	if type(value) == "table" then
		return value
	end
	return {}
end

-- A report collects what was dropped, so the UI can tell the user ("3 markers were invalid and were skipped").
local function newReport()
	return { dropped = {}, errors = {} }
end

local function drop(report, what)
	report.dropped[what] = (report.dropped[what] or 0) + 1
end

-- Unique, well-formed ids in one list. Returns a set of accepted ids.
local function takeId(seen, raw, report, what)
	local v = id(raw)
	if not v or seen[v] then
		drop(report, what)
		return nil
	end
	seen[v] = true
	return v
end

-- Highest numeric part of all ids, so nextId never collides after an import.
local function maxIdNumber(plan)
	local highest = 0
	local function scan(items)
		for _, item in ipairs(items) do
			local n = tonumber(item.id:match("%d+$"))
			if n and n > highest then
				highest = n
			end
		end
	end
	scan(plan.markers)
	scan(plan.routes)
	scan(plan.pulls)
	scan(plan.encounters)
	scan(plan.assignments)
	scan(plan.gear)
	scan(plan.objectives)
	scan(plan.drawings and plan.drawings.shapes or {})
	scan(plan.pages and plan.pages.list or {})
	return highest
end

local validatePlan

-- strict: the plan comes from outside (Codec.Decode, packs), see STRICT_ID_LENGTH.
function Validate.Plan(raw, strict)
	local before = idLength
	idLength = strict and STRICT_ID_LENGTH or 12
	local ok, plan, report = pcall(validatePlan, raw)
	idLength = before
	if not ok then
		error(plan, 0)
	end
	return plan, report
end

function validatePlan(raw)
	local report = newReport()
	if type(raw) ~= "table" then
		report.errors[#report.errors + 1] = "not a table"
		return nil, report
	end

	local plan = {
		v = Schema.PLAN_VERSION,
		id = (type(raw.id) == "string" and #raw.id <= 40 and raw.id:match("^[%w_]+$")) and raw.id or nil,
		name = text(raw.name, TEXT.name) or "",
		author = text(raw.author, TEXT.author) or "",
		description = text(raw.description, TEXT.description, true) or "",
		difficulty = text(raw.difficulty, TEXT.difficulty) or "",
		notes = text(raw.notes, TEXT.notes, true) or "",
		-- Prep notes (format 5, optional): left out when empty, so older readers see nothing new.
		prep = text(raw.prep, TEXT.prep, true),
		created = int(raw.created, 0) or 0,
		updated = int(raw.updated, 0) or 0,
		tags = {},
		floors = {},
		markers = {},
		routes = {},
		pulls = {},
		encounters = {},
		assignments = {},
		groups = {},
		gear = {},
		objectives = {},
	}
	if plan.name == "" then
		plan.name = "Untitled plan"
	end
	if plan.prep == "" then
		plan.prep = nil
	end

	for _, tag in ipairs(list(raw.tags)) do
		local t = text(tag, TEXT.tag)
		if t and t ~= "" and #plan.tags < MAX.tags then
			plan.tags[#plan.tags + 1] = t
		end
	end

	-- Instance: what the plan is for. IDs come from the client at runtime; here only their shape is checked.
	local inst = type(raw.instance) == "table" and raw.instance or {}
	plan.instance = {
		name = text(inst.name, TEXT.name) or "",
		kind = Schema.INSTANCE_KINDS[inst.kind] and inst.kind or "other",
		ejInstanceID = int(inst.ejInstanceID, 1, 2 ^ 31),
		uiMapID = int(inst.uiMapID, 1, 2 ^ 31),
		-- Optional: the instance's map ID (GetInstanceInfo's eighth return), the same in every client language, so the
		-- bundled data finds a plan saved under a localized name (Data/InstanceIdentity.lua). Older readers drop it.
		instanceMapID = int(inst.instanceMapID, 1, 2 ^ 31),
		-- Level range (version 2): from a recommended plan's data or the author; the UI prefers the client's own.
		levelMin = int(inst.levelMin, 1, Schema.MAX_LEVEL),
		levelMax = int(inst.levelMax, 1, Schema.MAX_LEVEL),
		-- Where the instance comes from (version 2, optional): "forever" (new in WoW: Forever) or "classic".
		origin = Schema.INSTANCE_ORIGINS[inst.origin] and inst.origin or nil,
	}
	if plan.instance.levelMin and plan.instance.levelMax and plan.instance.levelMax < plan.instance.levelMin then
		plan.instance.levelMax = plan.instance.levelMin
	end

	-- Floors: the map pages of the instance, in order. Markers and routes refer to them by index.
	for i, floor in ipairs(list(raw.floors)) do
		if i > MAX.floors then
			drop(report, "floors")
			break
		end
		if type(floor) == "table" then
			plan.floors[#plan.floors + 1] = {
				uiMapID = int(floor.uiMapID, 1, 2 ^ 31),
				name = text(floor.name, TEXT.name) or "",
				-- Optional: the position of the instance's map art this floor shows (Data/Floors.lua).
				art = int(floor.art, 1, MAX.floors),
			}
		else
			drop(report, "floors")
		end
	end
	if #plan.floors == 0 then
		plan.floors[1] = { uiMapID = plan.instance.uiMapID, name = "" }
	end
	local floorCount = #plan.floors

	-- Pulls first: markers refer to them.
	local pullIds = {}
	for _, pull in ipairs(list(raw.pulls)) do
		if #plan.pulls >= MAX.pulls then
			drop(report, "pulls")
			break
		end
		local pid = type(pull) == "table" and takeId(pullIds, pull.id, report, "pulls")
		if pid then
			plan.pulls[#plan.pulls + 1] = {
				id = pid,
				name = text(pull.name, TEXT.label) or "",
				note = text(pull.note, TEXT.note, true) or "",
				color = int(pull.color, 1, Schema.COLOR_COUNT) or 1,
				-- Format 3 (optional): tags, planned cooldowns and Bloodlust / Heroism, planned progress (forces %).
				tags = Validate.PullTags(pull.tags),
				cd = pull.cd == true or nil,
				lust = pull.lust == true or nil,
				progress = int(pull.progress, 0, 100),
			}
		end
	end

	-- Encounters (bosses) with phases.
	local encounterIds = {}
	for _, enc in ipairs(list(raw.encounters)) do
		if #plan.encounters >= MAX.encounters then
			drop(report, "encounters")
			break
		end
		local eid = type(enc) == "table" and takeId(encounterIds, enc.id, report, "encounters")
		if eid then
			local phases = {}
			for _, phase in ipairs(list(enc.phases)) do
				if #phases >= MAX.phases then
					drop(report, "phases")
					break
				end
				if type(phase) == "table" then
					phases[#phases + 1] = {
						name = text(phase.name, TEXT.label) or "",
						trigger = text(phase.trigger, TEXT.short) or "",
						notes = text(phase.notes, TEXT.strategy, true) or "",
					}
				else
					drop(report, "phases")
				end
			end
			plan.encounters[#plan.encounters + 1] = {
				id = eid,
				name = text(enc.name, TEXT.name) or "",
				-- custom: the planner renamed it, so the stored name wins over the journal's (Data/Names.lua).
				custom = enc.custom == true or nil,
				ejEncounterID = int(enc.ejEncounterID, 1, 2 ^ 31),
				dungeonEncounterID = int(enc.dungeonEncounterID, 1, 2 ^ 31),
				strategy = text(enc.strategy, TEXT.strategy, true) or "",
				phases = phases,
			}
		end
	end

	-- Markers.
	local markerIds = {}
	local perPull = {}
	for _, m in ipairs(list(raw.markers)) do
		if #plan.markers >= MAX.markers then
			drop(report, "markers")
			break
		end
		local x, y = type(m) == "table" and coord(m.x), type(m) == "table" and coord(m.y)
		local mid = x and y and takeId(markerIds, m.id, report, "markers")
		if mid then
			local pull = m.pull and pullIds[m.pull] and m.pull or nil
			if pull then
				perPull[pull] = (perPull[pull] or 0) + 1
				if perPull[pull] > MAX.planMarkersPerPull then
					pull = nil
				end
			end
			-- Version 1 kinds are renamed (mob -> pack, objective -> interactive); unknown kinds become notes.
			local kind = Schema.KIND_ALIASES[m.kind] or m.kind
			kind = Schema.MARKER_KIND_SET[kind] and kind or "note"
			plan.markers[#plan.markers + 1] = {
				id = mid,
				floor = int(m.floor, 1, floorCount) or 1,
				x = x,
				y = y,
				kind = kind,
				label = text(m.label, TEXT.label) or "",
				note = text(m.note, TEXT.note, true) or "",
				icon = int(m.icon, 0, 8) or 0,
				pull = pull,
				encounter = m.encounter and encounterIds[m.encounter] and m.encounter or nil,
				-- Version 2 fields. IDs are the client's; names and icons are read from the client at display time.
				role = kind == "position" and Schema.POSITION_ROLE_SET[m.role] and m.role or nil,
				npcID = int(m.npcID, 1, 2 ^ 31),
				itemID = Util.ParseItemID(m.itemID),
				questID = int(m.questID, 1, 2 ^ 31),
				toFloor = Schema.LINK_KINDS[kind] and int(m.toFloor, 1, floorCount) or nil,
			}
		elseif type(m) ~= "table" or not (x and y) then
			drop(report, "markers")
		end
	end

	-- Routes: polylines on one floor.
	local routeIds = {}
	for _, r in ipairs(list(raw.routes)) do
		if #plan.routes >= MAX.routes then
			drop(report, "routes")
			break
		end
		local rid = type(r) == "table" and takeId(routeIds, r.id, report, "routes")
		if rid then
			local points = {}
			for _, p in ipairs(list(r.points)) do
				if #points >= MAX.routePoints then
					drop(report, "routePoints")
					break
				end
				local px, py = type(p) == "table" and coord(p[1]), type(p) == "table" and coord(p[2])
				if px and py then
					-- A point is a bend of the path, or a numbered stop (step) with an optional note and pull.
					local point = { px, py }
					point.step = int(p.step, 1, Schema.MAX_STEP)
					if point.step then
						local note = text(p.note, TEXT.short)
						point.note = note ~= "" and note or nil
						point.pull = p.pull and pullIds[p.pull] and p.pull or nil
					end
					points[#points + 1] = point
				else
					drop(report, "routePoints")
				end
			end
			plan.routes[#plan.routes + 1] = {
				id = rid,
				name = text(r.name, TEXT.label) or "",
				floor = int(r.floor, 1, floorCount) or 1,
				color = int(r.color, 1, Schema.COLOR_COUNT) or 1,
				optional = r.optional == true or nil,
				points = points,
			}
		end
	end

	-- Assignments: who does what, optionally tied to an encounter, phase and marker.
	local assignmentIds = {}
	for _, a in ipairs(list(raw.assignments)) do
		if #plan.assignments >= MAX.assignments then
			drop(report, "assignments")
			break
		end
		local aid = type(a) == "table" and takeId(assignmentIds, a.id, report, "assignments")
		if aid then
			local target = text(a.target, TEXT.player)
			if target and Schema.IsValidTarget(target) then
				local encounter = a.encounter and encounterIds[a.encounter] and a.encounter or nil
				plan.assignments[#plan.assignments + 1] = {
					id = aid,
					target = target,
					task = text(a.task, TEXT.task) or "",
					encounter = encounter,
					phase = encounter and int(a.phase, 1, MAX.phases) or nil,
					marker = a.marker and markerIds[a.marker] and a.marker or nil,
				}
			else
				drop(report, "assignments")
			end
		end
	end

	-- Raid groups 1..8, up to 5 names each (planning only; Dungeon Planner never moves players).
	local rawGroups = list(raw.groups)
	for g = 1, MAX.groups do
		local names = {}
		for _, name in ipairs(list(rawGroups[g])) do
			local n = text(name, TEXT.player)
			if n and n ~= "" and #names < MAX.groupSize and Schema.IsValidTarget(n) and not n:find(":") then
				names[#names + 1] = n
			end
		end
		plan.groups[g] = names
	end

	-- Gear recommendations: user-authored; item IDs are only shape-checked and resolved by the client at runtime.
	local gearIds = {}
	for _, gitem in ipairs(list(raw.gear)) do
		if #plan.gear >= MAX.gear then
			drop(report, "gear")
			break
		end
		local gid = type(gitem) == "table" and takeId(gearIds, gitem.id, report, "gear")
		if gid then
			local itemID = Util.ParseItemID(gitem.itemID)
			local label = text(gitem.label, TEXT.label) or ""
			if itemID or label ~= "" then
				plan.gear[#plan.gear + 1] = {
					id = gid,
					itemID = itemID,
					label = label,
					note = text(gitem.note, TEXT.task) or "",
					slot = Schema.SLOT_SET[gitem.slot] and gitem.slot or nil,
					class = Schema.IsClassToken(gitem.class) and gitem.class or nil,
					role = Schema.ROLE_SET[gitem.role] and gitem.role or nil,
					encounter = gitem.encounter and encounterIds[gitem.encounter] and gitem.encounter or nil,
					priority = int(gitem.priority, 1, 5) or 3,
				}
			else
				drop(report, "gear")
			end
		end
	end

	-- Objectives: a checklist for the run.
	local objectiveIds = {}
	for _, o in ipairs(list(raw.objectives)) do
		if #plan.objectives >= MAX.objectives then
			drop(report, "objectives")
			break
		end
		local oid = type(o) == "table" and takeId(objectiveIds, o.id, report, "objectives")
		if oid then
			local t = text(o.text, TEXT.short)
			if t and t ~= "" then
				plan.objectives[#plan.objectives + 1] = {
					id = oid,
					text = t,
					encounter = o.encounter and encounterIds[o.encounter] and o.encounter or nil,
				}
			else
				drop(report, "objectives")
			end
		end
	end

	-- Map drawings (format 3, optional; Model/Drawing.lua). Older readers drop the whole field.
	plan.drawings = Validate.Drawings(raw.drawings, floorCount, pullIds, encounterIds, report)
	-- Raid assignment pages (format 4, optional; Model/Pages.lua). Older readers drop the whole field.
	plan.pages = ns.Pages.Validate(raw.pages, encounterIds, report, takeId)

	-- A copy of a recommended (bundled) plan remembers which one, so the UI can say "based on" and offer updates.
	if type(raw.origin) == "table" then
		local bundled = type(raw.origin.bundled) == "string" and #raw.origin.bundled <= 40
			and raw.origin.bundled:match("^[%w_%-]+$") and raw.origin.bundled or nil
		if bundled then
			plan.origin = { bundled = bundled, rev = int(raw.origin.rev, 0, 2 ^ 31) }
		end
	end
	-- Revision of a recommended plan's data (bundled plans only; kept on copies through origin.rev).
	plan.rev = int(raw.rev, 0, 2 ^ 31)

	-- Where a received or imported plan came from (shown in the UI, never trusted for anything).
	if type(raw.source) == "table" then
		plan.source = {
			from = text(raw.source.from, TEXT.player),
			at = int(raw.source.at, 0),
			kind = text(raw.source.kind, TEXT.tag),
		}
	end

	plan.nextId = math.max(int(raw.nextId, 1, 2 ^ 31) or 1, maxIdNumber(plan) + 1)
	return plan, report
end

-- Pull tags: known tags only, each once, in Schema.PULL_TAGS order. nil when none (keeps strings small).
function Validate.PullTags(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local have = {}
	for _, tag in ipairs(raw) do
		if Schema.PULL_TAG_SET[tag] then
			have[tag] = true
		end
	end
	local out = {}
	for _, tag in ipairs(Schema.PULL_TAGS) do
		if have[tag] then
			out[#out + 1] = tag
		end
	end
	return #out > 0 and out or nil
end

-- Map drawings: { v = 1, shapes = { ... } } (docs/SHARING-FORMAT.md). A newer drawing version is dropped whole (this
-- build cannot know what it means); shapes of an unknown kind, without enough points or on top of the caps are
-- dropped one by one. Returns nil when nothing is left.
local DRAW_POINTS = { line = 2, arrow = 2, circle = 2, rect = 2, text = 1 }
local DRAW_KINDS = { pen = true, line = true, arrow = true, circle = true, rect = true, text = true }

function Validate.Drawings(raw, floorCount, pullIds, encounterIds, report)
	if type(raw) ~= "table" then
		return nil
	end
	local version = raw.v == nil and 1 or int(raw.v, 1)
	local shapesIn = list(raw.shapes)
	if not version or version > 1 then
		if #shapesIn > 0 then
			report.dropped.drawings = (report.dropped.drawings or 0) + #shapesIn
		end
		return nil
	end
	local shapes, seen, perFloor = {}, {}, {}
	for _, s in ipairs(shapesIn) do
		if #shapes >= MAX.drawings then
			drop(report, "drawings")
			break
		end
		local kind = type(s) == "table" and DRAW_KINDS[s.kind] and s.kind or nil
		local sid = kind and takeId(seen, s.id, report, "drawings")
		local floor = sid and (int(s.floor, 1, floorCount) or 1)
		local pts = {}
		if sid then
			local need = DRAW_POINTS[kind]
			local cap = need or MAX.strokePoints
			for i, v in ipairs(list(s.pts)) do
				if i > cap * 2 then
					break
				end
				local c = coord(v)
				if not c then
					pts = nil
					break
				end
				pts[i] = Util.Round(c, 3)
			end
			if pts and #pts % 2 == 1 then
				pts[#pts] = nil
			end
			if pts and #pts < (need or 2) * 2 then
				pts = nil
			end
		end
		local label = sid and kind == "text" and text(s.text, TEXT.label) or nil
		if not sid then
			if not kind then
				drop(report, "drawings")
			end
		elseif not pts or (kind == "text" and (not label or label == "")) then
			drop(report, "drawings")
		elseif (perFloor[floor] or 0) >= MAX.drawingsPerFloor then
			drop(report, "drawings")
		else
			perFloor[floor] = (perFloor[floor] or 0) + 1
			local author = text(s.author, TEXT.player)
			local pull = s.pull and pullIds[s.pull] and s.pull or nil
			shapes[#shapes + 1] = {
				id = sid,
				floor = floor,
				kind = kind,
				color = int(s.color, 1, Schema.COLOR_COUNT) or 1,
				width = int(s.width, 1, 3) or 2,
				pts = pts,
				text = label,
				author = author ~= "" and author or nil,
				pull = pull,
				encounter = not pull and s.encounter and encounterIds[s.encounter] and s.encounter or nil,
			}
		end
	end
	if #shapes == 0 then
		return nil
	end
	return { v = 1, shapes = shapes }
end

-- A pack: several plans under one name (community "import packs").
function Validate.Pack(raw)
	local report = newReport()
	if type(raw) ~= "table" then
		report.errors[#report.errors + 1] = "not a table"
		return nil, report
	end
	local pack = {
		name = text(raw.name, TEXT.name) or "Plan pack",
		description = text(raw.description, TEXT.description, true) or "",
		plans = {},
	}
	for _, rawPlan in ipairs(list(raw.plans)) do
		if #pack.plans >= MAX.plansPerPack then
			drop(report, "plans")
			break
		end
		local plan = Validate.Plan(rawPlan, true)
		if plan then
			pack.plans[#pack.plans + 1] = plan
		else
			drop(report, "plans")
		end
	end
	return pack, report
end

-- One line for the user: "Skipped: 2 markers, 1 route." or nil when nothing was dropped.
function Validate.Summary(report)
	if not report then
		return nil
	end
	local parts = {}
	for _, key in ipairs(Util.SortedKeys(report.dropped)) do
		parts[#parts + 1] = report.dropped[key] .. " " .. key
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ")
end
