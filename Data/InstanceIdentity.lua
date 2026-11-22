-- Which bundled instance a plan is for, in any client language. The bundled data (map tiles, Santiago Reyes' maps,
-- minimap pictures, enemies, boss facts, travel facts, corridor grids, recommended plans, other addons' tables) is
-- keyed by the instance's English name, while a plan made on a German, Spanish, ... client stores that client's name
-- ("Die Todesminen"). So every lookup asks here first, by identity, and uses the stored name only as a fallback:
--
--   0. A home entry made from a plan names the bundled instance it is (`canonicalKey`, UI.EntryForPlan; not stored).
--   1. The exact English name, when it names a bundled instance the instance map ID does not rule out (every plan made
--      on an English client, every copy of a recommended plan: they resolve as they always did).
--   2. The plan's instance map ID (instance.instanceMapID, GetInstanceInfo's eighth return; the journal's for a
--      journal ID) against the travel data's `iid`. An ID no bundled instance has ends the search here, and so does a
--      plan for a zone or another place (kind "other").
--   3. The map IDs of the instance and its dungeon floors against the travel data's `maps` and the recommended plans'.
--   4. The floor names: a plan whose floors carry a recommended plan's floor names ("Ironclad Cove").
--   5. The client's own names: GetRealZoneText(instance ID) for each bundled instance, the Group Finder's activities
--      (localized name and instance map ID) and the Adventure Guide, where the client has them.
-- Wings that share one instance ID (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire) are told apart by the
-- floor maps, then the floor names (of several fits, the wing with exactly those floors) and the words of the wing's
-- own label ("Library", "East", "Undead", "Upper") in the instance name or a floor name, never in the plan's own name.
--
-- A plan none of this places keeps its stored name (no bundled data for it). A wing that cannot be told apart is not
-- guessed: Instances.Resolve says "ambiguous" with the candidates, and the wing's maps, enemies, boss facts and travel
-- facts stay off; /dp debug lists such plans (Instances.IdentityReport).
--
--   Instances.Resolve(target)       -> record { name (English), key, iid?, maps, floors } | nil, how, candidates?
--                                      target: a plan, or an instance or home entry { name, instanceMapID?, ... }
--   Instances.ResolvedKey(target)   -> the record's key, or nil
--   Instances.CanonicalName(target) -> the English name, else the stored name
--   Instances.CanonicalKey(target)  -> Providers.Key of that name
--   Instances.InstanceMapID(target) -> the instance map ID (stored, else the record's), and whether wings share it
--   Instances.RecommendedFor(key)   -> the first recommended plan of a bundled instance (its home card), or nil
--   Instances.IsHere(plan, here)    -> is the player (Instances.Current()) in the plan's instance (and wing, if known)

local _, ns = ...
local Instances = ns.Instances
local Util, Match = ns.Util, ns.Match

local index -- { stamp, list, byKey, byIid, byMap } built on first use, again when the recommended plans change
local clientNames -- [name key] = instance map ID, or false when two instances share the name; per session
local memo = setmetatable({}, { __mode = "k" }) -- [target] = { the fields the answer depends on, rec, how, cands }
local EMPTY = {}

local function push(t, k, v)
	local list = t[k]
	if not list then
		list = {}
		t[k] = list
	end
	list[#list + 1] = v
end

local function byKey(a, b)
	return a.key < b.key
end

local function outsideMap(m)
	return ns.Floors.IsZoneMap(m)
end

local function build()
	local stamp = ns.Bundled.revision
	if index and index.stamp == stamp then
		return index
	end
	index = { stamp = stamp, list = {}, byKey = {}, byIid = {}, byMap = {} }
	local function record(name)
		local k = type(name) == "string" and ns.Providers.Key(name)
		if not k then
			return nil
		end
		local r = index.byKey[k]
		if not r then
			r = { name = name, key = k, maps = {}, floors = {}, floorCount = 0 }
			index.byKey[k] = r
			index.list[#index.list + 1] = r
		end
		return r
	end
	local function addMap(r, m)
		if Util.IsInteger(m) and not outsideMap(m) and not r.maps[m] then
			r.maps[m] = true
			push(index.byMap, m, r)
		end
	end
	local data = rawget(ns, "TravelData")
	for name, t in pairs(data and data.instances or {}) do
		local r = type(t) == "table" and record(name)
		if r then
			if Util.IsInteger(t.iid) and not r.iid then
				r.iid = t.iid
				push(index.byIid, t.iid, r)
			end
			for _, m in ipairs(type(t.maps) == "table" and t.maps or {}) do
				addMap(r, m)
			end
		end
	end
	for _, plan in ipairs(ns.Bundled.All()) do
		local r = record(plan.instance.name)
		if r then
			r.recommended = r.recommended or plan -- the first: the plan whose card the home table shows
			addMap(r, plan.instance.uiMapID)
			for _, f in ipairs(plan.floors) do
				if not ns.Floors.IsOutside(f) then
					addMap(r, f.uiMapID)
					local n = Match.StripArticle(f.name)
					if n ~= "" and not r.floors[n] then
						r.floors[n] = true
						r.floorCount = r.floorCount + 1
					end
				end
			end
		end
	end
	table.sort(index.list, byKey)
	for _, t in pairs(index.byIid) do
		table.sort(t, byKey)
	end
	for _, t in pairs(index.byMap) do
		table.sort(t, byKey)
	end
	return index
end

-- The parts of a target: its instance table, its floors (plans only) and the plan's own name.
local function parts(target)
	if type(target) ~= "table" then
		return nil
	end
	if type(target.instance) == "table" then
		return target.instance, type(target.floors) == "table" and target.floors or {}
	end
	return target, EMPTY
end

-- The map IDs that say where the plan is: its instance's and its dungeon floors' (not the zone outside).
local function mapsOf(inst, floors)
	local out, seen = {}, {}
	local function add(m)
		if Util.IsInteger(m) and not seen[m] and not outsideMap(m) then
			seen[m] = true
			out[#out + 1] = m
		end
	end
	add(inst.uiMapID)
	for _, f in ipairs(floors) do
		if type(f) == "table" and not ns.Floors.IsOutside(f) then
			add(f.uiMapID)
		end
	end
	return out
end

-- Candidates that hold every given map, else any of them, else all (a map no wing has tells nothing).
local function narrow(cands, maps)
	if #cands < 2 or #maps == 0 then
		return cands
	end
	local all, any = {}, {}
	for _, r in ipairs(cands) do
		local n = 0
		for _, m in ipairs(maps) do
			if r.maps[m] then
				n = n + 1
			end
		end
		if n == #maps then
			all[#all + 1] = r
		end
		if n > 0 then
			any[#any + 1] = r
		end
	end
	return #all > 0 and all or #any > 0 and any or cands
end

-- The one candidate (or bundled instance, without candidates) whose recommended plan has every named dungeon floor of
-- the plan; of several, the one with exactly those floors.
local function byFloorNames(floors, cands)
	local names, count = {}, 0
	for _, f in ipairs(floors) do
		local n = type(f) == "table" and not f.extra and not ns.Floors.IsOutside(f) and Match.StripArticle(f.name) or ""
		if n ~= "" and not names[n] then
			names[n] = true
			count = count + 1
		end
	end
	if count == 0 then
		return nil
	end
	local fits, exact = {}, {}
	for _, r in ipairs(cands or build().list) do
		local all = true
		for n in pairs(names) do
			if not r.floors[n] then
				all = false
				break
			end
		end
		if all then
			fits[#fits + 1] = r
			if r.floorCount == count then
				exact[#exact + 1] = r
			end
		end
	end
	if #fits == 1 then
		return fits[1]
	end
	return #exact == 1 and exact[1] or nil
end

local function wordsOf(s, out)
	for w in tostring(s or ""):lower():gmatch("%w+") do
		out[w] = true
	end
	return out
end

-- The words of a wing's own label: the part after ":" and before "(" ("Scarlet Monastery: Library" -> library,
-- "Stratholme: Live (Main Gate)" -> live), so generic words ("main", "gate", "entrance") never count; a name without
-- a label gives all its words, and only those not every candidate has count ("Lower Blackrock Spire" -> lower).
local function labelWords(name)
	local label = name:match(":%s*([^%(]+)")
	return wordsOf(label or name, {})
end

-- The one candidate whose own label words appear in the instance name or a floor name. Never the plan's name: a player
-- names a plan freely ("Main tank route", "Upper key quest").
local function byWords(cands, inst, floors)
	local seen = wordsOf(inst.name, {})
	for _, f in ipairs(floors) do
		if type(f) == "table" then
			wordsOf(f.name, seen)
		end
	end
	local count, own = {}, {}
	for i, r in ipairs(cands) do
		own[i] = labelWords(r.name)
		for w in pairs(own[i]) do
			count[w] = (count[w] or 0) + 1
		end
	end
	local hits = {}
	for i, r in ipairs(cands) do
		for w in pairs(own[i]) do
			if count[w] < #cands and seen[w] then
				hits[#hits + 1] = r
				break
			end
		end
	end
	return #hits == 1 and hits[1] or nil
end

-- Several wings (or instances) fit the IDs: the one the plan's data names, else none.
local function pick(cands, inst, floors)
	local r = byFloorNames(floors, cands)
	if r then
		return r, "floors"
	end
	r = byWords(cands, inst, floors)
	if r then
		return r, "words"
	end
	return nil, "ambiguous"
end

-- The instance map ID the client gives the name: its name for each bundled instance ID (GetRealZoneText, the map's
-- name in the client's language, which is what GetInstanceInfo returns inside), else the Group Finder's entry of that
-- name, else the Adventure Guide's sure match.
local function clientIid(inst)
	local k = ns.GameFiles.Key(inst.name)
	if not k then
		return nil
	end
	if not clientNames then
		clientNames = {}
		local zoneText = rawget(_G, "GetRealZoneText")
		if type(zoneText) == "function" then
			for iid in pairs(build().byIid) do
				local ok, name = pcall(zoneText, iid)
				local nk = ok and ns.GameFiles.Key(Util.Plain(name))
				if nk then
					if clientNames[nk] == nil then
						clientNames[nk] = iid
					elseif clientNames[nk] ~= iid then
						clientNames[nk] = false -- one name for two instances (or the current zone for any ID): no answer
					end
				end
			end
		end
	end
	if clientNames[k] then
		return clientNames[k]
	end
	local hit = ns.GameFiles.Finder().byKey[k]
	if hit and Util.IsInteger(hit.mapID) then
		return hit.mapID
	end
	local entry, score = ns.Journal.ResolveInstance(inst)
	if entry and score >= 75 and Util.IsInteger(entry.instanceMapID) then
		return entry.instanceMapID
	end
	return nil
end

-- The instance map ID a plan stores, else its journal entry's.
local function storedIid(inst)
	if Util.IsInteger(inst.instanceMapID) then
		return inst.instanceMapID
	end
	local entry = inst.ejInstanceID and ns.Journal.ByInstanceID(inst.ejInstanceID)
	return entry and Util.IsInteger(entry.instanceMapID) and entry.instanceMapID or nil
end

local function fromCandidates(cands, maps, inst, floors, how)
	cands = narrow(cands, maps)
	if #cands == 1 then
		return cands[1], how
	end
	local r, why = pick(cands, inst, floors)
	if r then
		return r, why
	end
	return nil, why, cands
end

local function contains(list, x)
	for _, v in ipairs(list) do
		if v == x then
			return true
		end
	end
	return false
end

local function resolve(inst, floors)
	local ix = build()
	-- 0. A home entry made from a plan says which bundled instance it is (UI.EntryForPlan).
	if type(inst.canonicalKey) == "string" and ix.byKey[inst.canonicalKey] then
		return ix.byKey[inst.canonicalKey], "entry"
	end
	local iid = storedIid(inst)
	local idCands = iid and ix.byIid[iid]
	-- 1. The exact English name, unless the instance map ID names other instances: English plans resolve as before.
	local k = ns.Providers.Key(inst.name)
	local named = k and ix.byKey[k]
	if named and (not idCands or contains(idCands, named)) then
		return named, "name"
	end
	local maps = mapsOf(inst, floors)
	-- 2. The instance map ID.
	if idCands then
		return fromCandidates(idCands, maps, inst, floors, "id")
	end
	-- An instance map ID no bundled instance has: another instance, whatever its maps or floors look like. A zone or
	-- another place ("other") is not looked for by maps, floor names or the client's names either.
	if iid or inst.kind == "other" then
		return nil
	end
	-- 3. The map IDs of the instance and its floors.
	local cands, seen = nil, {}
	for _, m in ipairs(maps) do
		for _, r in ipairs(ix.byMap[m] or EMPTY) do
			if not seen[r] then
				seen[r] = true
				cands = cands or {}
				cands[#cands + 1] = r
			end
		end
	end
	if cands then
		table.sort(cands, byKey)
		return fromCandidates(cands, maps, inst, floors, "map")
	end
	-- 4. The floor names.
	local r = byFloorNames(floors, nil)
	if r then
		return r, "floors"
	end
	-- 5. The client's names.
	iid = clientIid(inst)
	if iid and ix.byIid[iid] then
		return fromCandidates(ix.byIid[iid], maps, inst, floors, "client")
	end
	return nil
end

-- The same table is asked many times per redraw (the home table compares every plan with every card): an answer stands
-- while the recommended plans, the instance's fields and, for a plan, its revision (DB.Revision), `updated` stamp and
-- floor count stay the same. No strings are built and the index is not touched on a hit.
-- A plan's instance fields change only through plan operations, which stamp `updated` and the revision; an entry is
-- built once, so its fields are compared directly.
local Bundled, DB = ns.Bundled, ns.DB
local function fresh(m, target)
	local inst = m.inst
	if m.stamp ~= Bundled.revision or m.name ~= inst.name or m.iid ~= inst.instanceMapID then
		return false
	end
	if m.plan then
		return target.instance == inst and m.updated == target.updated and m.rev == DB.Revision(target)
			and m.nf == #(target.floors or EMPTY)
	end
	return m.ej == inst.ejInstanceID and m.map == inst.uiMapID and m.ck == inst.canonicalKey and m.kind == inst.kind
end

function Instances.Resolve(target)
	local m = memo[target]
	if m and fresh(m, target) then
		return m.rec, m.how, m.cands
	end
	local inst, floors = parts(target)
	if not inst then
		return nil
	end
	build()
	local rec, how, cands = resolve(inst, floors)
	local plan = inst ~= target
	memo[target] = { inst = inst, plan = plan, stamp = index.stamp, name = inst.name, iid = inst.instanceMapID,
		ej = inst.ejInstanceID, map = inst.uiMapID, ck = inst.canonicalKey, kind = inst.kind, nf = #floors,
		updated = plan and target.updated or nil, rev = plan and ns.DB.Revision(target) or nil, rec = rec, how = how,
		cands = cands }
	return rec, how, cands
end

-- The recommended plan whose card the home table shows for a bundled instance key (the first one), or nil.
function Instances.RecommendedFor(key)
	local r = key and build().byKey[key]
	return r and r.recommended or nil
end

function Instances.ResolvedKey(target)
	local m = memo[target]
	local rec = m and fresh(m, target) and m.rec or Instances.Resolve(target)
	return rec and rec.key or nil
end

function Instances.CanonicalName(target)
	local rec = Instances.Resolve(target)
	if rec then
		return rec.name
	end
	local inst = parts(target)
	return inst and type(inst.name) == "string" and inst.name or ""
end

function Instances.CanonicalKey(target)
	return ns.Providers.Key(Instances.CanonicalName(target))
end

-- The instance map ID: the stored one, else the resolved instance's, else (an unresolved wing) the one its candidates
-- share, else the Group Finder's entry of exactly that name. The second value is true when several wings share it.
function Instances.InstanceMapID(target)
	local inst = parts(target)
	if not inst then
		return nil
	end
	local rec, _, cands = Instances.Resolve(target)
	local iid = storedIid(inst) or rec and rec.iid
	if not iid and cands then
		for _, c in ipairs(cands) do
			if iid and c.iid ~= iid then
				iid = nil
				break
			end
			iid = c.iid
		end
	end
	if not iid and inst.kind ~= "other" then
		local k = ns.GameFiles.Key(inst.name)
		local hit = k and ns.GameFiles.Finder().byKey[k]
		iid = hit and Util.IsInteger(hit.mapID) and hit.mapID or nil
	end
	local shared = iid ~= nil and #(build().byIid[iid] or {}) > 1
	return iid, shared
end

-- Is the player (`here` = Instances.Current()) in the plan's instance? By the instance map ID (the same in every client
-- language), else by name. Wings share one ID: when the client's map names the player's wing (Travel.Here) and the
-- plan's wing is known, they must be the same; when either is unclear, the shared instance counts.
function Instances.IsHere(plan, here)
	if type(here) ~= "table" or not here.inInstance then
		return false
	end
	local iid = Instances.InstanceMapID(plan)
	local same = iid and here.instanceID == iid
		or Match.Norm(here.name or "") == Match.Norm(ns.Names.Instance(plan.instance))
	if not same then
		return false
	end
	local rec = Instances.Resolve(plan)
	local wings = rec and Util.IsInteger(here.instanceID) and ns.Travel.Here(here.instanceID, here.uiMapID) or EMPTY
	return not (#wings == 1 and wings[1].key ~= rec.key)
end

-- For /dp debug: saved plans for a dungeon or raid that no bundled instance fits, and those whose wing is unclear.
-- Returns matched, total, { names not matched }, { names with an unclear wing }.
function Instances.IdentityReport(plans)
	local matched, total, unknown, unclear = 0, 0, {}, {}
	for _, plan in ipairs(plans or {}) do
		if plan.instance.kind ~= "other" then
			total = total + 1
			local rec, how = Instances.Resolve(plan)
			if rec then
				matched = matched + 1
			else
				local list = how == "ambiguous" and unclear or unknown
				list[#list + 1] = string.format("%s (%s)", plan.name, plan.instance.name)
			end
		end
	end
	return matched, total, unknown, unclear
end

-- For tests: forget the index, the client's names and every answer.
function Instances.ForgetIdentity()
	index, clientNames = nil, nil
	memo = setmetatable({}, { __mode = "k" })
end

-- Recommended plans compare instances through the same identity (Model/Bundled.lua is pure and loads first).
ns.Bundled.canonicalKey = Instances.ResolvedKey
