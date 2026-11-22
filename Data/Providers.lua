-- Data providers: optional adapters that read dungeon data from other addons the player has installed, at runtime, in
-- the player's own client. Nothing from them is copied into this repository or the shipped data (the same way OpenMap
-- reads Questie at runtime). docs/ARCHITECTURE.md ("Data providers") and docs/COMPATIBILITY.md (section 6) list each
-- adapter, what it reads, and whether that is a public API or the other addon's internal tables.
--
-- Rules every adapter follows:
--   * Detect(): existence and shape checks; returns the data root or nil. Errors and wrong shapes make the adapter
--     inactive for the session (a later update of the other addon can only switch the adapter off, never break us).
--   * Every call into an adapter goes through Providers.Call (pcall); a failing call deactivates that adapter.
--   * Each adapter can be switched off in the settings (settings.providers[id] = false).
--   * Everything shown from an adapter names its source ("Map: Dungeon Journal").
--
-- Adapter fields: id, addon (folder name), title (credit), internals (true when it reads private tables), provides
-- (list of "map", "pins", "loot", "portraits", "info", "quests", "links"), Detect(), Counts(root) -> { name = n }, and
-- the capability functions it provides: FloorArt(root, plan, floor), BossPins(root, plan, floor), Loot(root, plan, enc),
-- Portrait(root, plan, enc), Boss(root, plan, enc) (level, description, summon item, drops), Quests(root, plan, done),
-- OpenLoot(root, plan, enc).

local _, ns = ...
local Providers = ns:NewModule("Providers")
local Util = ns.Util

Providers.list = {}
local byId = {}
local state = {} -- [id] = { root, version, failed } per session
-- Grows whenever what the providers can answer may have changed (switched on or off, one failed, detected again), for
-- caches of their answers (Journal.BossArt).
Providers.epoch = 0

function Providers.Register(adapter)
	if type(adapter) ~= "table" or type(adapter.id) ~= "string" or byId[adapter.id] then
		return false
	end
	byId[adapter.id] = adapter
	Providers.list[#Providers.list + 1] = adapter
	return true
end

function Providers.Adapter(id)
	return byId[id]
end

function Providers.Enabled(id)
	local s = ns.db and ns.db.settings.providers
	return not (type(s) == "table" and s[id] == false)
end

function Providers.SetEnabled(id, on)
	if ns.db then
		ns.db.settings.providers[id] = on and true or false
		state[id] = nil
		Providers.epoch = Providers.epoch + 1
		ns:Fire("PROVIDERS_CHANGED", id)
	end
end

-- Is the other addon loaded? (C_AddOns, guarded; true when the client cannot say and the data is there.)
function Providers.AddonLoaded(folder)
	local addons = rawget(_G, "C_AddOns")
	if addons and type(addons.IsAddOnLoaded) == "function" then
		local ok, loaded = pcall(addons.IsAddOnLoaded, folder)
		if ok then
			return Util.Plain(loaded) == true
		end
	end
	return nil
end

function Providers.AddonVersion(folder)
	local addons = rawget(_G, "C_AddOns")
	if addons and type(addons.GetAddOnMetadata) == "function" then
		local ok, v = pcall(addons.GetAddOnMetadata, folder, "Version")
		v = ok and Util.Plain(v) or nil
		if type(v) == "string" and v ~= "" then
			return v
		end
	end
	return nil
end

-- The adapter and its data root when it is enabled and its addon's data has the expected shape; nil otherwise.
function Providers.Get(id)
	local a = byId[id]
	if not a or not Providers.Enabled(id) then
		return nil
	end
	local s = state[id]
	if not s then
		s = {}
		state[id] = s
		local ok, root = pcall(a.Detect)
		if ok and root ~= nil then
			s.root = root
			s.version = Providers.AddonVersion(a.addon)
		elseif not ok then
			s.failed = tostring(root)
		end
	end
	if s.failed or s.root == nil then
		return nil
	end
	return a, s.root
end

-- Call a capability of one adapter. Returns its results, or nil when the adapter is inactive or the call fails (the
-- adapter then stays off for the session).
function Providers.Call(id, method, ...)
	local a, root = Providers.Get(id)
	local fn = a and a[method]
	if type(fn) ~= "function" then
		return nil
	end
	local r = { pcall(fn, root, ...) }
	if not r[1] then
		state[id].failed = tostring(r[2])
		Providers.epoch = Providers.epoch + 1
		ns:Debug("provider", id, method, r[2])
		return nil
	end
	return unpack(r, 2, 4)
end

-- The first active adapter that answers `method` with a non-nil value: value, extra, adapter.
function Providers.First(method, ...)
	for _, a in ipairs(Providers.list) do
		local v, extra = Providers.Call(a.id, method, ...)
		if v ~= nil then
			return v, extra, a
		end
	end
	return nil
end

-- For /dp debug and the settings: one row per adapter.
function Providers.Report()
	local rows = {}
	for _, a in ipairs(Providers.list) do
		local row = { id = a.id, title = a.title, addon = a.addon, internals = a.internals and true or false,
			enabled = Providers.Enabled(a.id), loaded = Providers.AddonLoaded(a.addon), provides = a.provides }
		local adapter, root = Providers.Get(a.id)
		row.active = adapter ~= nil
		local s = state[a.id]
		row.failed = s and s.failed or nil
		row.version = s and s.version or nil
		if adapter and type(a.Counts) == "function" then
			local ok, counts = pcall(a.Counts, root)
			row.counts = ok and type(counts) == "table" and counts or {}
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- Adapters whose addon is not loaded in this client (not installed, or disabled), for the settings hint: { adapter }.
function Providers.Missing()
	local out = {}
	for _, a in ipairs(Providers.list) do
		if Providers.AddonLoaded(a.addon) == false then
			out[#out + 1] = a
		end
	end
	return out
end

-- An error message made short enough for one line: the file name without its folders, at most 120 characters.
function Providers.ShortError(err)
	local s = tostring(err or "?"):gsub("^[^\n]-([^/\\\n]+%.lua:%d+:)", "%1"):gsub("\n.*$", "")
	if #s > 120 then
		s = s:sub(1, 117) .. "..."
	end
	return s
end

-- Enabled adapters that switched themselves off after an error, optionally only those that provide `capability`
-- ("loot", "map", ...): { { id, title, reason } }, so the pages can say why their data is missing.
function Providers.Failures(capability)
	local out = {}
	for _, a in ipairs(Providers.list) do
		local s = state[a.id]
		local provides = not capability or Util.IndexOf(a.provides or {}, capability) ~= nil
		if s and s.failed and provides and Providers.Enabled(a.id) then
			out[#out + 1] = { id = a.id, title = a.title, reason = Providers.ShortError(s.failed) }
		end
	end
	return out
end

-- For tests and after a settings change: detect again.
function Providers.Reset()
	state = {}
	Providers.epoch = Providers.epoch + 1
	for _, a in ipairs(Providers.list) do
		if type(a.Reset) == "function" then
			pcall(a.Reset)
		end
	end
end

-- Shared helpers for adapters --------------------------------------------------------------------------------------------

-- The comparison key of an instance or boss name (case, punctuation, a leading "The" ignored; GameFiles aliases such
-- as "Sunken Temple" = "The Temple of Atal'Hakkar" applied).
function Providers.Key(name)
	if type(name) ~= "string" then
		return nil
	end
	local k = ns.GameFiles.Key(name)
	local spec = k and ns.GameFiles.INSTANCES[k]
	if type(spec) == "table" and spec.alias then
		return spec.alias
	end
	return k
end

-- The key of a plan's instance: its English name's (Instances.CanonicalName, so a plan saved under a localized name
-- finds the same data), else its stored name's.
function Providers.PlanKey(plan)
	return type(plan) == "table" and type(plan.instance) == "table" and Providers.Key(ns.Instances.CanonicalName(plan))
		or nil
end

-- A boss's name for matching: the plan's stored name, else the display name.
function Providers.BossKey(enc)
	if type(enc) ~= "table" then
		return nil
	end
	return ns.Match.StripArticle(enc.name ~= "" and enc.name or ns.Names.Encounter(enc))
end

function Providers.IsNumber01(v)
	return type(v) == "number" and v >= 0 and v <= 1
end

-- Picking a provider's floor for a plan floor --------------------------------------------------------------------------
-- Providers list their floors in their own order and do not always label them (Dungeon Journal lists Dalaran's
-- Underbelly first, unlabelled), so a floor is matched by its name, not by its position:
--   1. a floor labelled with the plan floor's name;
--   2. else the floor whose label (or, unlabelled, file name) contains the most words of the plan floor's name, when
--      one alone does ("City of Dalaran": DalaranCityMap 2 words, DalaranUnderbellyMap 1; "Elders' Cavern": "Depths
--      of the Elders");
--   3. else the floor at the same position.
-- tools/route_paths.py picks the pictures it computes routes on the same way.
local STOP_WORDS = { the = true, of = true, ["and"] = true, map = true }

-- The words of a floor name: lower case, letters and digits, at least 3 long, without "the", "of", "and", "map".
function Providers.NameWords(name)
	local out = {}
	for w in tostring(name or ""):lower():gmatch("[%w]+") do
		if #w >= 3 and not STOP_WORDS[w] then
			out[#out + 1] = w
		end
	end
	return out
end

-- describe(candidate) -> label (or nil), file (or nil). Returns the candidate and its index, or nil.
function Providers.PickFloor(plan, floor, list, describe)
	if type(list) ~= "table" then
		return nil
	end
	local f = type(plan) == "table" and type(plan.floors) == "table" and plan.floors[floor]
	local want = type(f) == "table" and type(f.name) == "string" and f.name or ""
	local key = ns.Match.StripArticle(want)
	if key ~= "" then
		for i, c in ipairs(list) do
			local label = describe(c)
			if type(label) == "string" and ns.Match.StripArticle(label) == key then
				return c, i
			end
		end
		local words = Providers.NameWords(want)
		local best, bestI, bestScore, tie = nil, nil, 0, false
		for i, c in ipairs(list) do
			local label, file = describe(c)
			-- The label when there is one (a file name repeats the instance's name: "BlackmawHold..."), else the file.
			local text = type(label) == "string" and label ~= "" and label
				or type(file) == "string" and file:match("([^\\/]*)$") or ""
			text = text:lower():gsub("[^%w]", "")
			local score = 0
			for _, w in ipairs(words) do
				if text:find(w, 1, true) then
					score = score + 1
				end
			end
			if score > bestScore then
				best, bestI, bestScore, tie = c, i, score, false
			elseif score == bestScore and score > 0 then
				tie = true
			end
		end
		if best and not tie then
			return best, bestI
		end
	end
	-- The same position: the floor's `art` when it has one (Data/Floors.lua), else its place in the plan.
	local pos = type(f) == "table" and f.art or floor
	if type(pos) == "number" and list[pos] ~= nil then
		return list[pos], pos
	end
	return nil
end

-- Aligning plan points with a provider's map ---------------------------------------------------------------------------
-- Recommended plans for Forever's new dungeons were placed without a map in the client. When a provider's map is drawn
-- under them, the plan's boss markers are compared with the provider's boss pins of the same name:
--   "same"  the points already agree (root mean square distance <= TOLERANCE): drawn as they are
--   "fit"   a per-axis scale and offset (least squares over >= 3 bosses) brings them within TOLERANCE: the plan is drawn
--           through that transform (input goes through its inverse, so edits stay in the plan's own space)
--   "pins"  neither: the provider's boss pins are shown for every boss and the plan's boss markers are hidden; the
--           plan's other markers and steps still show
--   "none"  fewer than one matching boss: nothing to compare, drawn as they are.
Providers.TOLERANCE = 0.035

local function rms(list, sx, tx, sy, ty)
	local sum = 0
	for _, p in ipairs(list) do
		local dx, dy = p[1] * sx + tx - p[3], p[2] * sy + ty - p[4]
		sum = sum + dx * dx + dy * dy
	end
	return math.sqrt(sum / math.max(1, #list))
end

local function fitAxis(list, a, b)
	local n, sa, sb, saa, sab = #list, 0, 0, 0, 0
	for _, p in ipairs(list) do
		sa, sb = sa + p[a], sb + p[b]
		saa, sab = saa + p[a] * p[a], sab + p[a] * p[b]
	end
	local d = n * saa - sa * sa
	if math.abs(d) < 1e-9 then
		return 1, (sb - sa) / n
	end
	local s = (n * sab - sa * sb) / d
	return s, (sb - s * sa) / n
end

-- pairs = { { planX, planY, providerX, providerY }, ... }. Returns { mode, sx, tx, sy, ty, error }.
function Providers.Align(list)
	if type(list) ~= "table" or #list == 0 then
		return { mode = "none", sx = 1, tx = 0, sy = 1, ty = 0, error = 0 }
	end
	local same = rms(list, 1, 0, 1, 0)
	if same <= Providers.TOLERANCE then
		return { mode = "same", sx = 1, tx = 0, sy = 1, ty = 0, error = same }
	end
	if #list >= 3 then
		local sx, tx = fitAxis(list, 1, 3)
		local sy, ty = fitAxis(list, 2, 4)
		local err = rms(list, sx, tx, sy, ty)
		if err <= Providers.TOLERANCE and sx > 0.5 and sx < 2 and sy > 0.5 and sy < 2 then
			return { mode = "fit", sx = sx, tx = tx, sy = sy, ty = ty, error = err }
		end
	end
	return { mode = "pins", sx = 1, tx = 0, sy = 1, ty = 0, error = same }
end

-- The plan's boss markers on a floor paired with provider pins of the same name.
function Providers.BossPairs(plan, floor, pins)
	local byName = {}
	for _, pin in ipairs(pins or {}) do
		local k = ns.Match.StripArticle(pin.name or "")
		if k ~= "" then
			byName[k] = pin
		end
	end
	local out = {}
	for _, m in ipairs(plan.markers or {}) do
		if m.floor == floor and m.kind == "boss" then
			local enc = m.encounter and Util.FindById(plan.encounters, m.encounter)
			local k = ns.Match.StripArticle(m.label ~= "" and m.label or (enc and Providers.BossKey(enc)) or "")
			local pin = byName[k] or (enc and byName[Providers.BossKey(enc) or ""])
			if pin then
				out[#out + 1] = { m.x, m.y, pin.x, pin.y }
			end
		end
	end
	return out
end

-- Capabilities used by the UI --------------------------------------------------------------------------------------------

-- Map art for a plan floor that has no art of its own: { width, height, tileWidth, tileHeight, textures, source =
-- "provider", provider = id, credit = title, pins = { { name, x, y } }, align = Align result }, or nil.
local artCache = {}
function Providers.FloorArt(plan, floor)
	local key = Providers.PlanKey(plan)
	if not key or type(floor) ~= "number" then
		return nil
	end
	-- One entry per plan floor, replaced when the plan changes (an entry per edit would grow all session).
	local cacheKey, stamp = plan.id .. ":" .. floor, plan.updated or 0
	local cached = artCache[cacheKey]
	if cached and cached.stamp == stamp then
		return cached.art or nil
	end
	local art, pins, a = Providers.First("FloorArt", plan, floor)
	if art then
		art.source, art.provider, art.credit = "provider", a.id, a.title
		art.pins = type(pins) == "table" and pins or {}
		art.align = Providers.Align(Providers.BossPairs(plan, floor, art.pins))
	end
	artCache[cacheKey] = { stamp = stamp, art = art or false }
	return art
end

-- Another addon's own route on a plan floor, for the map's extra layer: { provider, credit, name?, lines = { { points,
-- side, title? } }, stops = { { name, kind, x, y } } } in the coordinates of the art the canvas draws (`art`, its
-- artInfo), or nil. The adapter decides whether its coordinates fit that art.
local routesCache = {}
function Providers.Routes(plan, floor, art)
	if not Providers.PlanKey(plan) or type(floor) ~= "number" or type(art) ~= "table" then
		return nil
	end
	local cacheKey = plan.id .. ":" .. floor .. ":" .. tostring(art.provider or art.source) .. ":"
		.. tostring(art.textures and art.textures[1] or art.fdr)
	local stamp = plan.updated or 0
	local cached = routesCache[cacheKey]
	if cached and cached.stamp == stamp then
		return cached.routes or nil
	end
	local found
	for _, a in ipairs(Providers.list) do
		if not found and type(a.Routes) == "function" then
			local r = Providers.Call(a.id, "Routes", plan, floor, art)
			if type(r) == "table" and type(r.lines) == "table" and #r.lines > 0 then
				r.provider, r.credit = a.id, a.title
				found = r
			end
		end
	end
	routesCache[cacheKey] = { stamp = stamp, routes = found or false }
	return found
end

-- Loot for a plan boss: the bundled drops (Data/BossData.lua) first, else the providers': items { itemID, name?, quality?, slot?, slotText? }, credit.
function Providers.Loot(plan, enc)
	local bundled = ns.BossData and ns.BossData.Loot(plan, enc)
	if bundled then
		return bundled, ns.BossData.Credit
	end
	local items, _, a = Providers.First("Loot", plan, enc)
	if type(items) == "table" and #items > 0 then
		return items, a.title
	end
	return nil
end

-- A boss portrait: the bundled creature display (Data/BossData.lua) first, else a provider's: { icon = file } or { displayInfo = id }, credit.
function Providers.Portrait(plan, enc)
	local bundled = ns.BossData and ns.BossData.Portrait(plan, enc)
	if bundled then
		return bundled, ns.BossData.Credit
	end
	local art, _, a = Providers.First("Portrait", plan, enc)
	if type(art) == "table" then
		return art, a.title
	end
	return nil
end

-- What a provider states about a plan boss: { level?, rare?, description?, summon = { itemID }?, drops? }, credit.
function Providers.BossInfo(plan, enc)
	local info, _, a = Providers.First("Boss", plan, enc)
	if type(info) == "table" then
		return info, a.title
	end
	return nil
end

-- Adapters that can open a page of their own addon for a boss's loot (public entry points only).
function Providers.LootLinks()
	local out = {}
	for _, a in ipairs(Providers.list) do
		if type(a.OpenLoot) == "function" and Providers.Get(a.id) then
			out[#out + 1] = a
		end
	end
	return out
end

-- An installed addon's own picture of an instance, for where the game has none (GameFiles.InstancePictures puts it
-- after the game's files), from the first adapter whose CardArt(root, instanceName) answers { file, area }: { file,
-- area = { u0, u1, v0, v1, aspect }, source = "provider", provider = id, credit = title } or nil. The adapter checks
-- its tables' shapes; this checks what it returns. Cached per instance name until the providers change.
local cardCache = {}
local function validArea(area)
	if type(area) ~= "table" then
		return false
	end
	for i = 1, 4 do
		if not Providers.IsNumber01(area[i]) then
			return false
		end
	end
	return area[1] < area[2] and area[3] < area[4] and type(area[5]) == "number" and area[5] > 0 and area[5] < 10
end
function Providers.InstanceArt(name)
	local key = Providers.Key(name)
	if not key then
		return nil
	end
	if cardCache[key] == nil then
		local art, _, a = Providers.First("CardArt", name)
		local ok = type(art) == "table" and type(art.file) == "string" and art.file ~= "" and validArea(art.area)
		cardCache[key] = ok and { file = art.file, area = art.area, source = "provider", provider = a.id,
			credit = a.title } or false
	end
	return cardCache[key] or nil
end

function Providers.ResetCaches()
	artCache, routesCache, cardCache = {}, {}, {}
end

function Providers.Init()
	ns:On("PLAN_CHANGED", Providers, Providers.ResetCaches)
	ns:On("PROVIDERS_CHANGED", Providers, Providers.ResetCaches)
end
