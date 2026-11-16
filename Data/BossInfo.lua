-- What the boss pages show about a boss beyond the plan's own text, and what a marker's details show. Pure data for
-- the UI: the facts come from the data providers (Data/Providers.lua, "info": Dungeon Journal's level, description,
-- summon item and drops), read at runtime in the player's client and credited by name wherever they show. Without a
-- provider every function here returns less (or nil), and the pages hide what is missing.

local _, ns = ...
local BossInfo = ns:NewModule("BossInfo")
local Util, L = ns.Util, ns.L

local DEFAULT_DROPS = 8
local DEFAULT_ABILITIES = 6
local MIDDOT = " \194\183 "

-- Facts per plan revision and provider state: every redraw of the map and the pages asks again.
local cache = setmetatable({}, { __mode = "k" }) -- [plan] = { stamp, by = { [key] = info or false } }

-- The boss a boss marker stands for: its linked encounter, else (a boss marker without a link) the encounter with the
-- marker's name. A marker naming a boss the plan does not list gets a stand-in { name, standIn = true }, which the
-- providers can still match by name. nil for any other kind of marker without a link.
function BossInfo.EncounterOf(plan, m)
	if type(plan) ~= "table" or type(m) ~= "table" then
		return nil
	end
	local enc = m.encounter and Util.FindById(plan.encounters, m.encounter)
	if enc then
		return enc
	end
	if m.kind ~= "boss" or type(m.label) ~= "string" or m.label == "" then
		return nil
	end
	local want = ns.Match.StripArticle(m.label)
	for _, e in ipairs(plan.encounters or {}) do
		if ns.Match.StripArticle(ns.Names.Encounter(e)) == want or ns.Match.StripArticle(e.name or "") == want then
			return e
		end
	end
	return { name = m.label, standIn = true }
end

-- What is known about a plan boss: the bundled facts (Data/BossData.lua: level, drops, abilities) first, then what the
-- providers state (Dungeon Journal) filling what the bundled data lacks and adding its own (description, summon item):
-- { level?, rare?, description?, summon?, drops?, abilities?, credit, dropsCredit?, abilitiesCredit? }, or nil.
-- `credit` names the provider (for its description and summon item); the *Credit fields name the source of bundled
-- lists ("Sources: ...").
function BossInfo.For(plan, enc)
	if type(plan) ~= "table" or type(enc) ~= "table" then
		return nil
	end
	local stamp = (ns.DB and ns.DB.Revision(plan) or 0) .. ":" .. (ns.Providers and ns.Providers.epoch or 0)
	local hit = cache[plan]
	if not hit or hit.stamp ~= stamp then
		hit = { stamp = stamp, by = {} }
		cache[plan] = hit
	end
	local key = enc.id ~= nil and enc.id or ("name:" .. tostring(enc.name))
	local info = hit.by[key]
	if info == nil then
		local bundled = ns.BossData and ns.BossData.Boss(plan, enc)
		local found, credit
		if ns.Providers then
			found, credit = ns.Providers.BossInfo(plan, enc)
		end
		info = bundled or {}
		if bundled then
			local source = string.format(L["Sources: %s"], ns.BossData.Credit)
			info.dropsCredit = bundled.drops and source or nil
			info.abilitiesCredit = bundled.abilities and source or nil
		end
		if found then
			for k, v in pairs(found) do
				if info[k] == nil then
					info[k] = v
				end
			end
			info.credit = credit
			if info.dropsCredit == nil then
				info.dropsCredit = credit
			end
		end
		if next(info) == nil then
			info = false
		end
		hit.by[key] = info
	end
	return info or nil
end

-- "Level 16", "Levels 24-25", "Level ??" from the provider's level text; nil for anything else.
function BossInfo.LevelText(level)
	if type(level) ~= "string" then
		return nil
	end
	local n = level:match("^(%d+)$")
	if n then
		return string.format(L["Level %d"], tonumber(n))
	end
	local a, b = level:match("^(%d+)%-(%d+)$")
	if a then
		return string.format(L["Levels %d-%d"], tonumber(a), tonumber(b))
	end
	if level == "??" then
		return (L["Level %d"]:gsub("%%d", "??"))
	end
	return nil
end

-- The line under a boss's name: "Level 16 · Rare", or nil when nothing is known.
function BossInfo.Meta(info)
	if type(info) ~= "table" then
		return nil
	end
	local parts = {}
	local level = BossInfo.LevelText(info.level)
	if level then
		parts[#parts + 1] = level
	end
	if info.rare then
		parts[#parts + 1] = L["Rare"]
	end
	return #parts > 0 and table.concat(parts, MIDDOT) or nil
end

-- The sections of a boss page that come from a provider, in reading order: { { id, title?, text?, items?, credit } }.
-- "description" (text), "summon" (the item that summons the boss) and "drops" (its notable drops, at most opts.maxDrops).
-- Empty when no provider knows the boss; a section the provider has no data for is not in the list.
function BossInfo.Sections(plan, enc, opts)
	local info = BossInfo.For(plan, enc)
	local out = {}
	if not info then
		return out, nil
	end
	if info.description then
		out[#out + 1] = { id = "description", text = info.description, credit = info.credit }
	end
	if info.abilities and #info.abilities > 0 then
		local rows = {}
		local max = opts and opts.maxAbilities or DEFAULT_ABILITIES
		for i = 1, math.min(#info.abilities, max) do
			rows[i] = info.abilities[i]
		end
		out[#out + 1] = { id = "abilities", title = L["Abilities"], abilities = rows, credit = info.abilitiesCredit }
	end
	if info.summon then
		out[#out + 1] = { id = "summon", title = L["Summon with"], items = { { itemID = info.summon.itemID } }, credit = info.credit }
	end
	if info.drops and #info.drops > 0 then
		local items = {}
		local max = opts and opts.maxDrops or DEFAULT_DROPS
		for i = 1, math.min(#info.drops, max) do
			items[i] = info.drops[i]
		end
		out[#out + 1] = { id = "drops", title = L["Drops"], items = items, credit = info.dropsCredit or info.credit }
	end
	return out, info
end

-- The compact line of run mode's "Next boss": the level (and "Rare") the provider states, nil without one.
function BossInfo.RunMeta(plan, enc)
	return BossInfo.Meta(BossInfo.For(plan, enc))
end

-- The abilities worth a glance in run mode: up to n of the boss's abilities, those with a tag first (the order of the
-- data otherwise), as { spellID, tags, note? }; empty without data.
function BossInfo.KeyAbilities(plan, enc, n)
	local info = BossInfo.For(plan, enc)
	local out = {}
	if not (info and info.abilities) then
		return out
	end
	for _, a in ipairs(info.abilities) do
		if #a.tags > 0 and #out < n then
			out[#out + 1] = a
		end
	end
	for _, a in ipairs(info.abilities) do
		if #a.tags == 0 and #out < n then
			out[#out + 1] = a
		end
	end
	return out
end

-- "Interrupt, Dispel" for an ability's tags (localised), "" without tags.
function BossInfo.TagText(tags)
	local out = {}
	for _, t in ipairs(tags or {}) do
		out[#out + 1] = L["ability:" .. t]
	end
	return table.concat(out, ", ")
end

-- What the details of marker m show (UI/Panels/MapEditor.lua):
--   heading   the panel's title: a boss marker's kind ("Boss": its name is the header under it), else the marker's name,
--             else its kind
--   kind      the kind as a line under a named marker's heading (nil when the heading already is the kind)
--   boss      for a boss marker with a name: { name, enc, standIn, info, strategy? }
--   lines     the other facts (role, pull, a boss the marker belongs to), never repeating the heading
--   note, approx   the marker's note (Util.SplitApprox)
function BossInfo.MarkerDetail(plan, m)
	local d = { lines = {} }
	local label = type(m.label) == "string" and m.label or ""
	local kindText = L[m.kind]
	local enc = BossInfo.EncounterOf(plan, m)
	local encName = enc and ns.Names.Encounter(enc) or ""
	if m.kind == "boss" then
		d.heading = kindText
		local name = encName ~= "" and encName or label
		if name ~= "" then
			d.boss = { name = name, enc = enc, standIn = enc and enc.standIn or nil, info = enc and BossInfo.For(plan, enc) or nil,
				strategy = enc and not enc.standIn and enc.strategy ~= "" and enc.strategy or nil }
			if label ~= "" and label ~= name then
				d.lines[#d.lines + 1] = label
			end
		end
	else
		d.heading = label ~= "" and label or kindText
		d.kind = label ~= "" and kindText or nil
		if m.role then
			d.lines[#d.lines + 1] = L["Role"] .. ": " .. L["role:" .. m.role]
		end
		local pull, index = Util.FindById(plan.pulls, m.pull)
		if pull then
			if pull.name == label or pull.name == "" then
				-- The heading is the pull's name: only its number is new.
				d.lines[#d.lines + 1] = string.format(L["Pull %d"], index)
			else
				d.lines[#d.lines + 1] = string.format(L["Pull %d: %s"], index, pull.name)
			end
		end
		if enc and not enc.standIn and encName ~= label then
			d.lines[#d.lines + 1] = L["Boss"] .. ": " .. encName
		end
	end
	local note, approx = Util.SplitApprox(m.note)
	d.note, d.approx = note ~= "" and note or nil, approx
	return d
end
