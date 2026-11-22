-- SavedVariables (AceDB-3.0), schema version, migrations and the plan store.
--
--   DungeonPlannerDB (one SavedVariable, AceDB layout):
--     global  = { schema, plans = { [id] = plan }, quarantine = { ... } }   plans are shared by all characters
--     profiles[name] = { settings, ui, minimap }                              look and behaviour, switchable profiles
--     char[key] = { schema, progress }                                        boss kills, runs, objectives
--
-- ns.db is a small view over the AceDB object (ns.db.settings, ns.db.ui, ns.db.plans, ...), so modules never care
-- which profile is active. Rules:
-- * Migrations run in order from the stored schema to DB.SCHEMA (LoadGlobal is pure; tests call it directly).
-- * Data from a newer addon version (schema > DB.SCHEMA) is never rewritten: the addon runs read-only until updated.
-- * A plan that fails validation is moved to `quarantine`, never deleted, so a bug cannot destroy a user's work.

local _, ns = ...
local DB = ns:NewModule("DB")
local Util, Validate, Defaults = ns.Util, ns.Validate, ns.Defaults

DB.SCHEMA = 5
DB.MAX_QUARANTINE = 50

-- migrations[n] upgrades the global table from schema n-1 to n.
DB.migrations = {
	-- 0 -> 1: the first released layout. Pre-release builds kept plans in a list; turn it into a map by id.
	[1] = function(global)
		if type(global.plans) == "table" and global.plans[1] ~= nil then
			local byId = {}
			-- Plans already stored by id beside the list stay.
			for id, plan in pairs(global.plans) do
				if type(id) == "string" then
					byId[id] = plan
				end
			end
			for _, plan in ipairs(global.plans) do
				if type(plan) == "table" then
					local id = type(plan.id) == "string" and plan.id or nil
					while not id or byId[id] ~= nil do
						id = Util.UniqueId("p")
					end
					plan.id = id
					byId[id] = plan
				end
			end
			global.plans = byId
		end
	end,
	-- 1 -> 2: plan format 2 (new marker kinds, position roles, route stops). Validate.Plan upgrades each plan as it
	-- loads (mob -> pack, objective -> interactive), so this step only marks the data: an older Dungeon Planner then
	-- opens it read-only instead of turning the new kinds into notes.
	[2] = function(global)
		if type(global.plans) == "table" then
			for _, plan in pairs(global.plans) do
				if type(plan) == "table" and type(plan.markers) == "table" then
					for _, m in ipairs(plan.markers) do
						if type(m) == "table" and ns.Schema.KIND_ALIASES[m.kind] then
							m.kind = ns.Schema.KIND_ALIASES[m.kind]
						end
					end
				end
			end
		end
	end,
	-- 2 -> 3: plan format 3 (map drawings, pull tags, planned cooldowns, Bloodlust and progress). Nothing to convert:
	-- the new fields are optional. The step only marks the data, so an older Dungeon Planner opens it read-only
	-- instead of loading the plans and dropping their drawings and tags the next time it saves.
	[3] = function() end,
	-- 3 -> 4: plan format 4 (raid assignment pages). Nothing to convert; like 3, the step marks the data so an older
	-- Dungeon Planner opens it read-only instead of dropping the pages on its next save.
	[4] = function() end,
	-- 4 -> 5: group sync's links from received copies to their sender's plan (global.shareLinks, Acks.Link). The step
	-- starts the store (repairing anything there) and marks the data, so an older Dungeon Planner opens it read-only.
	[5] = function(global)
		global.shareLinks = ns.Acks.NormalizeLinks(global.shareLinks)
	end,
}

function DB.Migrate(t, current, migrations)
	local from = tonumber(t.schema) or 0
	-- A damaged number (a fraction, a negative, not a number) starts from the last whole step below it: left as it
	-- is, 2.5 would end at 4.5 and read as "newer" for ever.
	if not Util.IsFiniteNumber(from) or from < 0 then
		from = 0
	end
	if from > current then
		return false, from
	end
	from = math.floor(from)
	for n = from + 1, current do
		local step = migrations[n]
		if step then
			step(t)
		end
		t.schema = n
	end
	return true, from
end

-- Migrate and validate the global section. Returns info { readOnly, quarantined, migratedFrom }.
function DB.LoadGlobal(global)
	local info = { readOnly = false, quarantined = 0, migratedFrom = nil }
	local ok, from = DB.Migrate(global, DB.SCHEMA, DB.migrations)
	if not ok then
		info.readOnly = true
		return info
	end
	if from ~= DB.SCHEMA then
		info.migratedFrom = from
	end
	if type(global.plans) ~= "table" then
		global.plans = {}
	end
	if type(global.quarantine) ~= "table" then
		global.quarantine = {}
	end
	for id, raw in pairs(global.plans) do
		local plan = Validate.Plan(raw)
		if plan and type(id) == "string" then
			plan.id = id
			global.plans[id] = plan
		else
			global.plans[id] = nil
			-- Always kept, also past MAX_QUARANTINE: a plan leaves the store only once, so this cannot grow by itself.
			global.quarantine[#global.quarantine + 1] = { at = ns.Now(), data = raw }
			info.quarantined = info.quarantined + 1
		end
	end
	return info
end

-- Saved data from a newer Dungeon Planner is never rewritten, and its plans may have shapes this build does not know.
-- The UI reads validated copies instead (Validate.Plan builds new tables and leaves its input alone); nothing done to
-- them is saved.
function DB.ReadOnlyPlans(global)
	local out = {}
	if type(global) == "table" and type(global.plans) == "table" then
		for id, raw in pairs(global.plans) do
			local plan = type(id) == "string" and Validate.Plan(raw) or nil
			if plan then
				plan.id = id
				out[id] = plan
			end
		end
	end
	return out
end

local function defaults()
	return {
		profile = {
			settings = Defaults.settings,
			ui = Defaults.ui,
			minimap = { hide = false, minimapPos = 200 },
		},
		global = {
			plans = {},
			quarantine = {},
		},
		char = {
			progress = {},
			recorder = {},
			notes = {}, -- raid assignment pages received from the group's leader (Model/Pages.lua)
			shareAcks = {}, -- who has which version of the plans this character sent (Share/Acks.lua)
		},
	}
end

-- A read-through view so `ns.db.settings` always means the active profile's settings.
local function makeView(adb, readOnlyPlans)
	local noQuarantine = {}
	return setmetatable({}, {
		__index = function(_, key)
			if key == "settings" or key == "ui" or key == "minimap" then
				return adb.profile[key]
			elseif key == "plans" then
				return readOnlyPlans or adb.global.plans
			elseif key == "quarantine" then
				local q = adb.global.quarantine
				return type(q) == "table" and q or noQuarantine
			elseif key == "shareLinks" then
				-- Which plan each received copy came from (Acks.Link); none while the data is read-only.
				if readOnlyPlans then
					return nil
				end
				if type(adb.global.shareLinks) ~= "table" then
					adb.global.shareLinks = {}
				end
				return adb.global.shareLinks
			end
			return nil
		end,
		__newindex = function()
			error("ns.db is a view; write to its tables")
		end,
	})
end

-- Another addon's drawn map (Dungeon Journal, Forever Dungeon Routes) comes first again by default
-- (settings.preferProviderMaps, Data/MinimapArt.lua): for a while the game's minimap pictures did. AceDB does not save
-- a value equal to its default, so profiles saved then hold no `false`; one that does (whatever wrote it) is taken as
-- that old default and goes back to the new one, once (global.providerMapsFirst marks the data). Pure; returns how
-- many profiles changed.
function DB.ProviderMapsFirst(raw)
	if type(raw) ~= "table" or (type(raw.global) == "table" and raw.global.providerMapsFirst) then
		return 0
	end
	local n = 0
	for _, profile in pairs(type(raw.profiles) == "table" and raw.profiles or {}) do
		local s = type(profile) == "table" and profile.settings
		if type(s) == "table" and s.preferProviderMaps == false then
			s.preferProviderMaps = nil
			n = n + 1
		end
	end
	if type(raw.global) ~= "table" then
		raw.global = {}
	end
	raw.global.providerMapsFirst = true
	return n
end

function DB.Init()
	-- Look before AceDB touches anything: newer data must stay as it is.
	local raw = _G.DungeonPlannerDB
	-- No saved data at all: the first session on this install (Core/WhatsNew.lua shows the welcome, not "what's new").
	ns.freshInstall = type(raw) ~= "table" or type(raw.global) ~= "table"
	local newer = type(raw) == "table" and type(raw.global) == "table" and (tonumber(raw.global.schema) or 0) > DB.SCHEMA
	if type(raw) == "table" and not newer then
		DB.ProviderMapsFirst(raw)
	end
	local AceDB = LibStub("AceDB-3.0")
	local adb = AceDB:New("DungeonPlannerDB", defaults(), true)
	ns.adb = adb
	local info = newer and { readOnly = true, quarantined = 0 } or DB.LoadGlobal(adb.global)
	adb.char.progress = ns.Progress.Normalize(adb.char.progress)
	adb.char.recorder = ns.RunLog.Normalize(adb.char.recorder)
	adb.char.notes = ns.Pages.NormalizeReceived(adb.char.notes)
	adb.char.shareAcks = ns.Acks.Normalize(adb.char.shareAcks)
	if not newer then
		adb.global.shareLinks = ns.Acks.NormalizeLinks(adb.global.shareLinks)
	end
	ns.db = makeView(adb, newer and DB.ReadOnlyPlans(adb.global) or nil)
	ns.char = setmetatable({}, {
		__index = function(_, key)
			return adb.char[key]
		end,
		-- A store replaced after a repair (Comm.AcksStore, Recorder.Store) must land in the saved table, not here.
		__newindex = function(_, key, value)
			adb.char[key] = value
		end,
	})
	ns.dbInfo = info

	local function profileChanged()
		ns:Fire("PROFILE_CHANGED")
	end
	adb.RegisterCallback(DB, "OnProfileChanged", profileChanged)
	adb.RegisterCallback(DB, "OnProfileCopied", profileChanged)
	adb.RegisterCallback(DB, "OnProfileReset", profileChanged)

	if info.readOnly then
		ns:Print(ns.L["Your saved plans come from a newer Dungeon Planner. Update the addon; nothing will be changed until then."])
	end
	if info.quarantined > 0 then
		ns:Print(ns.Plural(info.quarantined,
			ns.L["%d saved plan could not be read and was set aside (see /dp debug).|%d saved plans could not be read and were set aside (see /dp debug)."]))
	end
end

function DB.IsReadOnly()
	return ns.dbInfo ~= nil and ns.dbInfo.readOnly
end

-- Instance key used to group plans: the journal ID when known, else the map, else the name.
function DB.InstanceKey(instance)
	if not instance then
		return "other"
	end
	if instance.ejInstanceID then
		return "ej:" .. instance.ejInstanceID
	elseif instance.uiMapID then
		return "map:" .. instance.uiMapID
	elseif instance.name and instance.name ~= "" then
		return "name:" .. instance.name:lower()
	end
	return "other"
end

function DB.Plans(instanceKey)
	local out = {}
	for _, plan in pairs(ns.db.plans) do
		if not instanceKey or DB.InstanceKey(plan.instance) == instanceKey then
			out[#out + 1] = plan
		end
	end
	table.sort(out, function(a, b)
		if a.updated ~= b.updated then
			return a.updated > b.updated
		end
		return a.name < b.name
	end)
	return out
end

-- A saved plan, or a recommended (bundled, read-only) one: ids "b:<id>" (Model/Bundled.lua).
function DB.GetPlan(id)
	if not id then
		return nil
	end
	return ns.db.plans[id] or (ns.Bundled and ns.Bundled.Get(id)) or nil
end

-- Can this plan be changed? Not while the saved data is read-only, and never a recommended plan (make a copy).
function DB.IsEditable(plan)
	return plan ~= nil and not DB.IsReadOnly() and not plan.bundled
end

-- Saved plans for an instance entry ({ ejInstanceID?, uiMapID?, name? }), matched like recommended plans are.
function DB.PlansFor(entry)
	local out = {}
	for _, plan in ipairs(DB.Plans()) do
		if ns.Bundled.SameInstance(plan.instance, entry) then
			out[#out + 1] = plan
		end
	end
	return out
end

-- The plan last chosen for an instance (ui.lastPlans[instance key] = plan id), so coming back to an instance shows the
-- plan you left there. DB.RememberPlan stores it; DB.RememberedPlan gives it back only while it still exists and still
-- belongs to the instance (a deleted plan is cleared in DeletePlan, anything else stale is ignored here).
function DB.RememberPlan(instanceKey, planId)
	if type(instanceKey) == "string" and type(planId) == "string" then
		ns.db.ui.lastPlans[instanceKey] = planId
	end
end

function DB.RememberedPlan(entry)
	local id = entry and entry.key and ns.db.ui.lastPlans[entry.key]
	local plan = id and DB.GetPlan(id)
	if plan and ns.Bundled.SameInstance(plan.instance, entry) then
		return plan
	end
	return nil
end

function DB.AddPlan(plan)
	if DB.IsReadOnly() then
		return nil, "read-only"
	end
	while not plan.id or ns.db.plans[plan.id] do
		plan.id = Util.UniqueId("p")
	end
	ns.db.plans[plan.id] = plan
	ns:Fire("PLANS_CHANGED", plan.id)
	if ns.FirePublic then
		ns:FirePublic("DUNGEONPLANNER_PLAN_CHANGED", plan.id)
	end
	return plan
end

function DB.DeletePlan(id)
	if DB.IsReadOnly() or not ns.db.plans[id] then
		return false
	end
	ns.db.plans[id] = nil
	ns.char.progress.objectives[id] = nil
	if ns.db.shareLinks then
		ns.db.shareLinks[id] = nil
	end
	if ns.db.ui.selectedPlan == id then
		ns.db.ui.selectedPlan = nil
	end
	for key, planId in pairs(ns.db.ui.lastPlans) do
		if planId == id then
			ns.db.ui.lastPlans[key] = nil
		end
	end
	ns:Fire("PLANS_CHANGED", id)
	if ns.FirePublic then
		ns:FirePublic("DUNGEONPLANNER_PLAN_CHANGED", id)
	end
	return true
end

-- A plan's revision: a number that grows with every DB.Changed, for caches of what is computed from a plan (never
-- saved; a plan table seen for the first time is at 0).
local revisions = setmetatable({}, { __mode = "k" })
function DB.Revision(plan)
	return revisions[plan] or 0
end

-- Every edit goes through here so the UI and other listeners refresh.
function DB.Changed(plan, what)
	revisions[plan] = (revisions[plan] or 0) + 1
	ns:Fire("PLAN_CHANGED", plan, what)
	if ns.FirePublic then
		ns:FirePublic("DUNGEONPLANNER_PLAN_CHANGED", plan.id)
	end
end

-- Your plan that an imported plan would replace: the same instance and the same name (case ignored); of several, the
-- plan on the table, else the newest. nil when there is none.
function DB.SameNamePlan(plan)
	local key, name = DB.InstanceKey(plan.instance), (plan.name or ""):lower()
	local found
	for _, own in ipairs(DB.Plans(key)) do
		if (own.name or ""):lower() == name then
			if own.id == ns.db.ui.selectedPlan then
				return own
			end
			found = found or own
		end
	end
	return found
end

-- What an import string would replace if the player chose to: a list of { incoming = name, existing = plan }. Empty
-- for a string that does not decode (the import itself reports why).
function DB.ImportConflicts(text)
	local kind, value = ns.Codec.Decode(text)
	local out = {}
	if not kind then
		return out
	end
	for _, plan in ipairs(kind == "plan" and { value } or value.plans) do
		local existing = DB.SameNamePlan(plan)
		if existing then
			out[#out + 1] = { incoming = plan.name, existing = existing }
		end
	end
	return out
end

-- Import an export string (pasted or received). Plans arrive as new plans with a new id, unless opts.replace is set:
-- then a plan with the same name and instance as one of yours replaces that plan in place (same id, so lists, the
-- selection and the undo history follow it). Only the player's own choice in the import dialog sets it; received
-- plans never replace anything. Returns true, message, added (plans), replaced (plans) or false, error.
function DB.ImportString(text, source, opts)
	if DB.IsReadOnly() then
		return false, ns.L["Saved data is read-only (newer version)."]
	end
	local kind, value, report = ns.Codec.Decode(text)
	if not kind then
		return false, value
	end
	local plans = kind == "plan" and { value } or value.plans
	local added, replaced, from = {}, {}, {}
	for _, plan in ipairs(plans) do
		-- The sender's id, for the link (Acks.Link): a recommended plan travels without its id.
		from[#from + 1] = plan.id or (plan.origin and plan.origin.bundled and (ns.Bundled.PREFIX .. plan.origin.bundled))
			or false
		plan.id = nil
		plan.source = {
			from = source and source.from or nil,
			at = ns.Now(),
			kind = source and source.kind or "import",
		}
		plan.updated = ns.Now()
		local existing = opts and opts.replace and DB.SameNamePlan(plan)
		if existing then
			local id, created = existing.id, existing.created
			for k in pairs(existing) do
				existing[k] = nil
			end
			for k, v in pairs(plan) do
				existing[k] = v
			end
			existing.id, existing.created = id, created
			replaced[#replaced + 1] = existing
			added[#added + 1] = existing
			DB.Changed(existing, "import")
		else
			added[#added + 1] = DB.AddPlan(plan)
		end
	end
	-- Only a plan received in game from a group member's transfer is linked (group sync); pasted strings are not.
	local links = source and source.kind == "received" and ns.db.shareLinks
	for i, plan in ipairs(added) do
		if links and from[i] then
			ns.Acks.Link(links, plan.id, from[i], ns.Now())
		end
	end
	local summary = Validate.Summary(report)
	local message
	if kind == "pack" then
		message = ns.Plural(#added, ns.L["Imported %d plan from pack \"%s\".|Imported %d plans from pack \"%s\"."], value.name)
	else
		message = string.format(ns.L["Imported plan \"%s\"."], value.name)
	end
	if source and source.from then
		message = message .. " " .. string.format(ns.L["From %s."], source.from)
	end
	if #replaced > 0 then
		message = message .. " " .. ns.Plural(#replaced, ns.L["%d plan of yours was replaced.|%d plans of yours were replaced."])
	end
	if summary then
		message = message .. " " .. ns.L["Skipped invalid parts:"] .. " " .. summary
	end
	ns:Print(message)
	ns:Fire("PLAN_IMPORTED", added)
	return true, message, added, replaced
end
