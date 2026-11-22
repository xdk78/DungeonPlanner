-- Which bundled instance a plan is for, in any client language. The bundled data (map tiles, Santiago Reyes' maps,
-- minimap pictures, enemies, boss facts, travel facts, corridor grids, recommended plans, other addons' tables) is
-- keyed by the instance's English name, while a plan made on a German, Spanish, ... client stores that client's name
-- ("Die Todesminen"). So every lookup asks here first, by identity, and uses the stored name only as a fallback:
--
--   0. A home entry made from a plan names the bundled instance it is (`canonicalKey`, UI.EntryForPlan; not stored).
--   1. The plan's instance map ID (instance.instanceMapID, GetInstanceInfo's eighth return; the journal's for a
--      journal ID) against the travel data's `iid`. An ID no bundled instance has ends the search after step 2.
--   2. The English name, when it names a bundled instance (every plan made on an English client, every copy of a
--      recommended plan).
--   3. The map IDs of the instance and its dungeon floors against the travel data's `maps` and the recommended plans'.
--   4. The floor names: a plan whose floors carry a recommended plan's floor names ("Ironclad Cove").
--   5. The client's own names: GetRealZoneText(instance ID) for each bundled instance, the Group Finder's activities
--      (localized name and instance map ID) and the Adventure Guide, where the client has them.
-- Wings that share one instance ID (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire) are told apart by the
-- floor maps, then by the English name, the floor names (of several fits, the wing with exactly those floors) and the
-- wing's own words ("Library", "East", "Upper") in the instance name, the plan name or the floor names.
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

local _, ns = ...
local Instances = ns.Instances
local Util, Match = ns.Util, ns.Match

local index -- { stamp, list, byKey, byIid, byMap } built on first use, again when the recommended plans change
local clientNames -- [name key] = instance map ID, or false when two instances share the name; per session
local memo = setmetatable({}, { __mode = "k" }) -- [target] = { sig, rec, how, cands }

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
	local stamp = ns.Bundled.Count()
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
		return target.instance, type(target.floors) == "table" and target.floors or {}, target.name
	end
	return target, {}, nil
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

-- The one candidate whose own words (those not every candidate's name has: "library", "east", "upper") appear in the
-- instance name, the plan name or a floor name.
local function byWords(cands, inst, floors, planName)
	local seen = wordsOf(planName, wordsOf(inst.name, {}))
	for _, f in ipairs(floors) do
		if type(f) == "table" then
			wordsOf(f.name, seen)
		end
	end
	local count, own = {}, {}
	for i, r in ipairs(cands) do
		own[i] = wordsOf(r.name, {})
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
local function pick(cands, inst, floors, planName)
	local k = ns.Providers.Key(inst.name)
	for _, r in ipairs(cands) do
		if r.key == k then
			return r, "name"
		end
	end
	local r = byFloorNames(floors, cands)
	if r then
		return r, "floors"
	end
	r = byWords(cands, inst, floors, planName)
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

local function fromCandidates(cands, maps, inst, floors, planName, how)
	cands = narrow(cands, maps)
	if #cands == 1 then
		return cands[1], how
	end
	local r, why = pick(cands, inst, floors, planName)
	if r then
		return r, why
	end
	return nil, why, cands
end

local function resolve(inst, floors, planName)
	local ix = build()
	-- 0. A home entry made from a plan says which bundled instance it is (UI.EntryForPlan).
	if type(inst.canonicalKey) == "string" and ix.byKey[inst.canonicalKey] then
		return ix.byKey[inst.canonicalKey], "entry"
	end
	local maps = mapsOf(inst, floors)
	-- 1. The instance map ID.
	local iid = storedIid(inst)
	if iid and ix.byIid[iid] then
		return fromCandidates(ix.byIid[iid], maps, inst, floors, planName, "id")
	end
	-- 2. The English name.
	local k = ns.Providers.Key(inst.name)
	if k and ix.byKey[k] then
		return ix.byKey[k], "name"
	end
	-- An instance map ID no bundled instance has: another instance, whatever its maps or floors look like.
	if iid then
		return nil
	end
	-- 3. The map IDs of the instance and its floors.
	local cands, seen = nil, {}
	for _, m in ipairs(maps) do
		for _, r in ipairs(ix.byMap[m] or {}) do
			if not seen[r] then
				seen[r] = true
				cands = cands or {}
				cands[#cands + 1] = r
			end
		end
	end
	if cands then
		table.sort(cands, byKey)
		return fromCandidates(cands, maps, inst, floors, planName, "map")
	end
	-- 4. The floor names.
	local r = byFloorNames(floors, nil)
	if r then
		return r, "floors"
	end
	-- 5. The client's names.
	iid = clientIid(inst)
	if iid and ix.byIid[iid] then
		return fromCandidates(ix.byIid[iid], maps, inst, floors, planName, "client")
	end
	return nil
end

-- A cheap fingerprint of what the answer depends on (the same table is asked many times per redraw).
local function signature(inst, floors, planName)
	local s = { tostring(inst.name), tostring(inst.instanceMapID), tostring(inst.ejInstanceID), tostring(inst.uiMapID),
		tostring(inst.canonicalKey), tostring(planName), index and index.stamp or 0 }
	for _, f in ipairs(floors) do
		if type(f) == "table" then
			s[#s + 1] = tostring(f.uiMapID) .. ":" .. tostring(f.name)
		end
	end
	return table.concat(s, "|")
end

function Instances.Resolve(target)
	local inst, floors, planName = parts(target)
	if not inst then
		return nil
	end
	build()
	local sig = signature(inst, floors, planName)
	local m = memo[target]
	if m and m.sig == sig then
		return m.rec, m.how, m.cands
	end
	local rec, how, cands = resolve(inst, floors, planName)
	memo[target] = { sig = sig, rec = rec, how = how, cands = cands }
	return rec, how, cands
end

function Instances.ResolvedKey(target)
	local rec = Instances.Resolve(target)
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
	if not iid then
		local k = ns.GameFiles.Key(inst.name)
		local hit = k and ns.GameFiles.Finder().byKey[k]
		iid = hit and Util.IsInteger(hit.mapID) and hit.mapID or nil
	end
	local shared = iid ~= nil and #(build().byIid[iid] or {}) > 1
	return iid, shared
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
