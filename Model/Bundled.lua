-- Recommended plans that ship with the addon (Data/Plans*.lua, generated from data-src/ by the data tools). They are
-- read-only: the UI shows each as "Recommended plan" and offers an editable copy (Plan.Duplicate keeps origin).
--
-- Data files call Bundled.Add(rawPlan) while the addon loads; the table has the plan format of
-- docs/SHARING-FORMAT.md plus a string `id` (letters, digits, "_" and "-", unique among bundled plans) and an optional
-- integer `rev` (the data revision). Nothing is validated at load: the first use validates every plan through
-- Validate.Plan, like any plan that enters the addon. Invalid ones are skipped and listed by /dp debug.
-- Pure Lua: no game API.

local _, ns = ...
local Bundled = ns:NewModule("Bundled")
local Validate = ns.Validate

Bundled.MAX = 300 -- bundled plans in total
Bundled.PREFIX = "b:" -- plan ids of bundled plans: "b:<id>"

local raws, order = {}, {} -- added, not yet validated
local seen = {} -- every id ever added
local cache = { list = {}, byId = {} } -- validated: { list = { plan, ... }, byId = { ["b:<id>"] = plan } }
Bundled.problems = {} -- { "<id>: what was wrong" }, shown by /dp debug
Bundled.revision = 0 -- counts plans added, so caches over the recommended plans see a change without validating them

function Bundled.Add(raw)
	if type(raw) ~= "table" then
		Bundled.problems[#Bundled.problems + 1] = "not a table"
		return false
	end
	local key = type(raw.id) == "string" and #raw.id <= 40 and raw.id:match("^[%w_%-]+$") and raw.id or nil
	if not key then
		Bundled.problems[#Bundled.problems + 1] = "a plan without a valid id: " .. tostring(raw.name)
		return false
	end
	if seen[key] then
		Bundled.problems[#Bundled.problems + 1] = key .. ": duplicate id"
		return false
	end
	if #cache.list + #order >= Bundled.MAX then
		Bundled.problems[#Bundled.problems + 1] = key .. ": more than " .. Bundled.MAX .. " bundled plans"
		return false
	end
	seen[key] = true
	raws[key] = raw
	order[#order + 1] = key
	Bundled.revision = Bundled.revision + 1
	return true
end

-- Validate what was added since the last use.
local function get()
	if #order == 0 then
		return cache
	end
	for _, key in ipairs(order) do
		local plan, report = Validate.Plan(raws[key])
		if plan then
			plan.id = Bundled.PREFIX .. key
			plan.bundled = true
			plan.source = nil
			cache.list[#cache.list + 1] = plan
			cache.byId[plan.id] = plan
			local summary = Validate.Summary(report)
			if summary then
				Bundled.problems[#Bundled.problems + 1] = key .. ": skipped " .. summary
			end
		else
			Bundled.problems[#Bundled.problems + 1] = key .. ": invalid plan"
		end
		raws[key] = nil -- the validated copy is all we keep
	end
	order = {}
	return cache
end

-- Every recommended plan (validated), in the order the data files added them.
function Bundled.All()
	return get().list
end

function Bundled.Get(id)
	if type(id) ~= "string" or id:sub(1, #Bundled.PREFIX) ~= Bundled.PREFIX then
		return nil
	end
	return get().byId[id]
end

function Bundled.IsBundled(planOrId)
	local id = type(planOrId) == "table" and planOrId.id or planOrId
	return type(id) == "string" and id:sub(1, #Bundled.PREFIX) == Bundled.PREFIX
end

function Bundled.Count()
	return #get().list
end

-- Optional: function(planInstance) -> the journal instance ID it surely is (Data/Journal.lua sets it in game; the
-- offline validator has no journal). Used when a plan has no journal ID and the other side has one.
Bundled.journalID = nil

-- Optional: function(planOrInstance) -> the key of the bundled instance it surely is, in any client language
-- (Data/InstanceIdentity.lua sets it in game; the offline validator compares as before).
Bundled.canonicalKey = nil

-- Does a plan (or a plan's instance) describe the same instance as `entry` ({ ejInstanceID?, uiMapID?, name? })?
-- Journal ID first, then map ID, then the bundled instance both are (a plan's floors tell a wing; a localized name
-- finds its instance by ID), then name: recommended plans are written outside the game and may carry only some of them.
-- `entryKey` (optional): the entry's canonical key, worked out once by a caller that compares many plans with it
-- (false: none).
function Bundled.SameInstance(plan, entry, entryKey)
	local planInstance = type(plan) == "table" and type(plan.instance) == "table" and plan.instance or plan
	if type(planInstance) ~= "table" or type(entry) ~= "table" then
		return false
	end
	if planInstance.ejInstanceID and entry.ejInstanceID then
		return planInstance.ejInstanceID == entry.ejInstanceID
	end
	if planInstance.uiMapID and entry.uiMapID and planInstance.uiMapID == entry.uiMapID then
		return true
	end
	local canonical = Bundled.canonicalKey
	if canonical then
		local b = entryKey
		if b == nil then
			b = canonical(entry)
		end
		local a = b and canonical(plan)
		if a then
			return a == b
		end
	end
	-- Names compare without case, spaces, punctuation and a leading article ("The Hall of Thanes" ~ "hall of thanes").
	if ns.Match.NameScore(planInstance.name, entry.name) >= 85 then
		return true
	end
	-- A recommended plan (no journal ID) and a journal entry: the journal's match for the plan, when it is a sure one
	-- (same name in another spelling, or the same map).
	local resolve = Bundled.journalID
	if resolve and entry.ejInstanceID and not planInstance.ejInstanceID then
		return resolve(planInstance) == entry.ejInstanceID
	end
	return false
end

-- The `entryKey` for SameInstance: the entry's canonical key, false without one (or without the identity module).
function Bundled.EntryKey(entry)
	local canonical = Bundled.canonicalKey
	return canonical and type(entry) == "table" and canonical(entry) or false
end

-- Recommended plans for one instance.
function Bundled.ForInstance(entry)
	local out = {}
	local key = Bundled.EntryKey(entry)
	for _, plan in ipairs(get().list) do
		if Bundled.SameInstance(plan, entry, key) then
			out[#out + 1] = plan
		end
	end
	return out
end

-- Is a recommended plan's research clearly older than the game build the player runs? Routes are the part of a dungeon
-- guide that goes stale first. All recommended plans are researched together and builds come often, so a build only
-- counts as newer when it is more than STALE_DAYS after the research: a plan is not flagged by every hotfix.
-- `dataTime`: the plan's data date (plan.updated, seconds); `buildDate`: GetBuildInfo's third value ("Nov 20 2026").
-- Returns stale (true / false) and the build's day as "YYYY-MM-DD", or nil when either is unknown. Pure.
Bundled.STALE_DAYS = 90
local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }

-- Days since 1970-01-01 of a calendar day (proleptic Gregorian; no time zones, no date()).
local function dayNumber(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m > 2 and m - 3 or m + 9) + 2) / 5) + d - 1
	return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end

function Bundled.Stale(dataTime, buildDate)
	if type(dataTime) ~= "number" or dataTime <= 0 or type(buildDate) ~= "string" then
		return nil
	end
	local mon, d, y = buildDate:match("^%s*(%a%a%a)%a*%s+(%d+)%s+(%d%d%d%d)")
	local m = mon and MONTHS[mon:lower()]
	d, y = tonumber(d), tonumber(y)
	if not m or d < 1 or d > 31 then
		return nil
	end
	local days = dayNumber(y, m, d) - math.floor(dataTime / 86400)
	return days > Bundled.STALE_DAYS, string.format("%04d-%02d-%02d", y, m, d)
end
