-- Discord export: a plan as Discord-flavoured Markdown, split into messages of at most 2000 characters (Discord's
-- limit for a normal message). Addons have no network access, so the player copies each part from a read-only box and
-- pastes it into Discord. Pure apart from the display names (Data/Names.lua), so the tests render it offline.
--
-- opts: { mode = "summary" | "full", importString = string or nil, version = "..." }
-- Returns a list of parts; each starts with "[n/N]" when there is more than one.

local _, ns = ...
local Discord = ns:NewModule("Discord")
local Util = ns.Util

Discord.LIMIT = 2000
local RESERVE = 16 -- room for the "`[n/N]`" line

-- Plain Unicode role marks (no custom Discord emoji).
local ROLE_MARK = { TANK = "\240\159\155\161\239\184\143", HEALER = "\240\159\146\154", DAMAGER = "\226\154\148\239\184\143" }
local ALL_MARK = "\240\159\145\165"

local LUST_MARK = "\240\159\165\129" -- drum: Bloodlust / Heroism planned on this pull

-- A pull's plan marks for Discord: tags in brackets, planned cooldowns, Bloodlust and progress. "" without any.
function Discord.PullMarks(pull, L)
	local parts = {}
	for _, tag in ipairs(pull.tags or {}) do
		parts[#parts + 1] = L["tagShort:" .. tag]
	end
	if pull.cd then
		parts[#parts + 1] = L["tagShort:cd"]
	end
	local out = #parts > 0 and ("[" .. table.concat(parts, ", ") .. "]") or ""
	if pull.lust then
		out = out .. (out ~= "" and " " or "") .. LUST_MARK .. " " .. L["tag:lust"]
	end
	if pull.progress then
		out = out .. (out ~= "" and " " or "") .. "*" .. pull.progress .. "%*"
	end
	return out
end

-- Escape Markdown in player text, and break @everyone / @here mentions with a zero-width space.
function Discord.Escape(text)
	text = tostring(text or "")
	text = text:gsub("([%*_`~|>#%[%]\\])", "\\%1")
	text = text:gsub("@", "@\226\128\139")
	return text
end
local esc = Discord.Escape

local function oneLine(text)
	return (tostring(text or ""):gsub("%s*\n%s*", " "))
end

local function who(target, L)
	local role = target:match("^role:(%u+)$")
	if role then
		return (ROLE_MARK[role] or "") .. " " .. L[role == "DAMAGER" and "Damage" or (role == "TANK" and "Tank" or "Healer")]
	end
	local group = target:match("^group:(%d)$")
	if group then
		return string.format(L["Group %s"], group)
	end
	if target == "all" then
		return ALL_MARK .. " " .. L["Everyone"]
	end
	return esc(target)
end

-- The plan as a list of blocks (each a list of lines). Blocks are kept together when splitting where they fit.
local function blocks(plan, opts)
	local L = ns.L
	local Names = ns.Names
	local out = {}
	local function block(lines)
		if #lines > 0 then
			out[#out + 1] = lines
		end
	end

	-- Header.
	local header = { "## " .. esc(plan.name) }
	local facts = {}
	local instance = Names and Names.Instance(plan.instance) or plan.instance.name
	if instance ~= "" then
		facts[#facts + 1] = "**" .. L["Instance"] .. ":** " .. esc(instance)
	end
	if plan.difficulty ~= "" then
		facts[#facts + 1] = "**" .. L["Difficulty"] .. ":** " .. esc(plan.difficulty)
	end
	if plan.author ~= "" then
		facts[#facts + 1] = "**" .. L["Author"] .. ":** " .. esc(plan.author)
	end
	if #facts > 0 then
		header[#header + 1] = table.concat(facts, " \194\183 ")
	end
	header[#header + 1] = string.format("**%s:** %d \194\183 **%s:** %d \194\183 **%s:** %d", L["Pulls"], #plan.pulls,
		L["Bosses"], #plan.encounters, L["Assignments"], #plan.assignments)
	if plan.description ~= "" then
		header[#header + 1] = "> " .. esc(oneLine(plan.description))
	end
	header[#header + 1] = "-# Dungeon Planner " .. esc(opts.version or ns.version or "")
	block(header)

	local full = opts.mode == "full"

	-- Pulls.
	if #plan.pulls > 0 then
		local lines = { "### " .. L["Pulls"] }
		if full then
			for i, pull in ipairs(plan.pulls) do
				local count = #ns.Plan.MarkersOfPull(plan, pull.id)
				local line = string.format("%d. **%s** (%d)", i, esc(pull.name), count)
				local marks = Discord.PullMarks(pull, L)
				if marks ~= "" then
					line = line .. " " .. marks
				end
				if pull.note ~= "" then
					line = line .. " - " .. esc(oneLine(pull.note))
				end
				lines[#lines + 1] = line
			end
		else
			local names = {}
			for i, pull in ipairs(plan.pulls) do
				local name = i .. ". " .. esc(pull.name)
				if pull.lust then
					name = name .. " " .. LUST_MARK
				end
				names[#names + 1] = name
			end
			lines[#lines + 1] = table.concat(names, " \194\183 ")
		end
		block(lines)
	end

	-- Bosses: strategy and phases (full), names only (summary).
	if #plan.encounters > 0 then
		if full then
			for _, enc in ipairs(plan.encounters) do
				local name = Names and Names.Encounter(enc) or enc.name
				local lines = { "### " .. esc(name) }
				if enc.strategy ~= "" then
					for paragraph in (enc.strategy .. "\n"):gmatch("(.-)\n") do
						if paragraph ~= "" then
							lines[#lines + 1] = "> " .. esc(paragraph)
						end
					end
				end
				for i, phase in ipairs(enc.phases) do
					local line = "- **" .. esc(phase.name ~= "" and phase.name or (L["Phase"] .. " " .. i)) .. "**"
					if phase.trigger ~= "" then
						line = line .. " (" .. esc(phase.trigger) .. ")"
					end
					if phase.notes ~= "" then
						line = line .. ": " .. esc(oneLine(phase.notes))
					end
					lines[#lines + 1] = line
				end
				block(lines)
			end
		else
			local names = {}
			for _, enc in ipairs(plan.encounters) do
				names[#names + 1] = esc(Names and Names.Encounter(enc) or enc.name)
			end
			block({ "### " .. L["Bosses"], table.concat(names, " \194\183 ") })
		end
	end

	-- Assignments, grouped: general first, then per boss.
	if #plan.assignments > 0 then
		local groups, order = {}, { false }
		for _, enc in ipairs(plan.encounters) do
			order[#order + 1] = enc.id
		end
		for _, a in ipairs(plan.assignments) do
			local key = a.encounter or false
			groups[key] = groups[key] or {}
			table.insert(groups[key], a)
		end
		local lines = { "### " .. L["Assignments"] }
		for _, key in ipairs(order) do
			local list = groups[key]
			if list then
				local title = key and (Names and Names.Encounter(Util.FindById(plan.encounters, key))) or L["General"]
				lines[#lines + 1] = "**" .. esc(title) .. "**"
				for _, a in ipairs(list) do
					local phase = a.phase and (" [" .. L["Phase"] .. " " .. a.phase .. "]") or ""
					lines[#lines + 1] = "- " .. who(a.target, L) .. phase .. ": " .. esc(a.task)
				end
			end
		end
		block(lines)
	end

	if full then
		-- Raid groups.
		local groupLines = { "### " .. L["Raid groups"] }
		for g, members in ipairs(plan.groups) do
			if #members > 0 then
				local names = {}
				for i, name in ipairs(members) do
					names[i] = esc(name)
				end
				groupLines[#groupLines + 1] = string.format("**%s:** %s", string.format(L["Group %s"], g), table.concat(names, ", "))
			end
		end
		if #groupLines > 1 then
			block(groupLines)
		end

		-- Objectives.
		if #plan.objectives > 0 then
			local lines = { "### " .. L["Objectives"] }
			for _, o in ipairs(plan.objectives) do
				lines[#lines + 1] = "- [ ] " .. esc(o.text)
			end
			block(lines)
		end

		-- Gear.
		if #plan.gear > 0 then
			local lines = { "### " .. L["Gear"] }
			for _, g in ipairs(ns.Plan.FilterGear(plan, {})) do
				local label = g.label ~= "" and g.label or ("item " .. tostring(g.itemID))
				local line = "- " .. esc(label)
				if g.itemID then
					line = line .. " (`" .. g.itemID .. "`)"
				end
				local tags = {}
				if g.slot then
					tags[#tags + 1] = g.slot:lower()
				end
				if g.class then
					tags[#tags + 1] = g.class:lower()
				end
				if g.role then
					tags[#tags + 1] = g.role:lower()
				end
				if #tags > 0 then
					line = line .. " \194\183 " .. table.concat(tags, ", ")
				end
				if g.note ~= "" then
					line = line .. " - " .. esc(g.note)
				end
				lines[#lines + 1] = line
			end
			block(lines)
		end

		-- General notes.
		if plan.notes ~= "" then
			local lines = { "### " .. L["Notes"] }
			for paragraph in (plan.notes .. "\n"):gmatch("(.-)\n") do
				if paragraph ~= "" then
					lines[#lines + 1] = esc(paragraph)
				end
			end
			block(lines)
		end
	end
	return out
end

-- Cut a line longer than `max` at spaces where possible.
local function wrap(line, max)
	local out = {}
	while #line > max do
		local cut = max
		local space = line:sub(1, max):match(".*()%s")
		if space and space > max / 2 then
			cut = space
		end
		out[#out + 1] = line:sub(1, cut)
		line = line:sub(cut + 1)
	end
	out[#out + 1] = line
	return out
end

-- Pack blocks into parts: a block that fits stays whole; one that doesn't is split by lines.
local function pack(blockList, limit)
	local parts, current = {}, {}
	local size = 0
	local function flush()
		if #current > 0 then
			parts[#parts + 1] = table.concat(current, "\n")
			current, size = {}, 0
		end
	end
	for _, lines in ipairs(blockList) do
		local text = table.concat(lines, "\n")
		local need = #text + (size > 0 and 2 or 0)
		if size + need <= limit then
			if size > 0 then
				current[#current + 1] = ""
			end
			current[#current + 1] = text
			size = size + need
		else
			flush()
			for _, line in ipairs(lines) do
				for _, piece in ipairs(wrap(line, limit)) do
					if size + #piece + 1 > limit then
						flush()
					end
					current[#current + 1] = piece
					size = size + #piece + 1
				end
			end
		end
	end
	flush()
	return parts
end

function Discord.Render(plan, opts)
	opts = opts or {}
	local L = ns.L
	local limit = Discord.LIMIT - RESERVE
	local parts = pack(blocks(plan, opts), limit)

	-- The import string, in code blocks of its own (one per part when it is long).
	if opts.importString then
		local s = opts.importString
		local fence = 8 -- "```\n" + "\n```"
		local intro = L["Import string: paste every piece, in order, into Dungeon Planner > Share > Import."]
		local room = limit - fence - #intro - 1
		local first = true
		local i = 1
		while i <= #s do
			local chunk = s:sub(i, i + room - 1)
			i = i + room
			local text = "```\n" .. chunk .. "\n```"
			if first then
				text = intro .. "\n" .. text
				first = false
			end
			parts[#parts + 1] = text
		end
	end

	if #parts > 1 then
		for n, part in ipairs(parts) do
			parts[n] = string.format("`[%d/%d]`\n", n, #parts) .. part
		end
	end
	return parts
end

-- A recorded run (Model/RunLog.lua) against its plan (Model/RunCompare.lua), for Share > Advanced > Discord.
-- info = { overlay = RunCompare.Overlay(...), splits = RunCompare.Splits(...), date = "2026-11-16 21:04",
--          bossName = function(encId) -> display name }. Returns parts like Discord.Render.
function Discord.RenderRun(plan, run, info, opts)
	opts = opts or {}
	local L = ns.L
	local T, D = ns.RunLog.FormatTime, ns.RunLog.FormatDelta
	local s = ns.RunLog.Summary(run)
	local ov = info.overlay
	local function boss(encId)
		return esc(encId and info.bossName and info.bossName(encId) or L["Boss"])
	end
	local out = {}
	local instance = ns.Names and ns.Names.Instance(plan.instance) or (run.n or "")
	local header = { "## " .. esc(string.format(L["Run: %s"], instance)) .. (info.date and (" \194\183 " .. esc(info.date)) or "") }
	local facts = { string.format("**%s:** %s", L["Time"], T(s.duration)) }
	facts[#facts + 1] = string.format("**%s:** %d (%s)", L["Pulls"], ov and ov.actual or s.pulls,
		string.format(L["plan: %d"], ov and ov.planned or #plan.pulls))
	facts[#facts + 1] = string.format("**%s:** %d/%d", L["Bosses"], ov and ov.bossesKilled or s.bosses,
		ov and ov.bossesPlanned or #plan.encounters)
	facts[#facts + 1] = string.format("**%s:** %d", L["Wipes"], s.wipes)
	facts[#facts + 1] = string.format("**%s:** %s", L["Deaths"], s.deaths and tostring(s.deaths) or L["not available"])
	header[#header + 1] = table.concat(facts, " \194\183 ")
	header[#header + 1] = "-# " .. esc(string.format(L["Plan: %s"], plan.name)) .. " \194\183 Dungeon Planner "
		.. esc(opts.version or ns.version or "")
	out[#out + 1] = header

	if info.splits and #info.splits > 0 then
		local lines = { "### " .. L["Bosses"] }
		for i, sp in ipairs(info.splits) do
			local line = string.format("%d. %s **%s**", i, esc(sp.name or "?"), T(sp.at))
			local cmp = {}
			if sp.delta then
				cmp[#cmp + 1] = string.format(L["best %s"], D(sp.delta))
			end
			if sp.prevDelta then
				cmp[#cmp + 1] = string.format(L["previous %s"], D(sp.prevDelta))
			end
			if #cmp > 0 then
				line = line .. " (" .. table.concat(cmp, " \194\183 ") .. ")"
			end
			lines[#lines + 1] = line
		end
		out[#out + 1] = lines
	end

	if ov and #ov.segments > 0 then
		local lines = { "### " .. L["Against the plan"] }
		for _, seg in ipairs(ov.segments) do
			if #seg.planned + #seg.actual > 0 then
				local where = seg.boss and string.format(L["Before %s"], boss(seg.boss))
					or (seg.kill and string.format(L["Before %s"], esc(seg.kill.n or "?")) or L["After the last boss"])
				local delta = seg.delta ~= 0 and (" **" .. (seg.delta > 0 and "+" or "") .. seg.delta .. "**") or ""
				lines[#lines + 1] = "- " .. where .. ": " .. ns.Plural(#seg.actual, L["%d pull, plan %d|%d pulls, plan %d"], #seg.planned)
					.. delta
			end
		end
		out[#out + 1] = lines
		if #ov.divergences > 0 then
			local off = { "### " .. L["Off plan"] }
			for _, d in ipairs(ov.divergences) do
				off[#off + 1] = "- " .. esc(Discord.DivergenceText(d, info.bossName))
			end
			out[#out + 1] = off
		end
	end
	local parts = pack(out, Discord.LIMIT - RESERVE)
	if #parts > 1 then
		for n, part in ipairs(parts) do
			parts[n] = string.format("`[%d/%d]`\n", n, #parts) .. part
		end
	end
	return parts
end

-- One divergence (RunCompare.Overlay) as a sentence. bossName(encId) -> display name.
function Discord.DivergenceText(d, bossName)
	local L = ns.L
	local function name(encId)
		return encId and bossName and bossName(encId) or L["the last boss"]
	end
	if d.kind == "extra" then
		return d.boss and ns.Plural(d.n, L["%d pull more than planned before %s|%d pulls more than planned before %s"], name(d.boss))
			or ns.Plural(d.n, L["%d pull after the last planned boss|%d pulls after the last planned boss"])
	elseif d.kind == "skipped" then
		return d.boss and ns.Plural(d.n, L["%d planned pull skipped before %s|%d planned pulls skipped before %s"], name(d.boss))
			or ns.Plural(d.n, L["%d planned pull skipped after the last boss|%d planned pulls skipped after the last boss"])
	elseif d.kind == "order" then
		return string.format(L["%s killed before %s"], name(d.boss), name(d.before))
	elseif d.kind == "unplanned" then
		return string.format(L["A boss the plan does not have: %s"], d.name or "?")
	elseif d.kind == "notReached" then
		return string.format(L["Not reached: %s"], name(d.boss))
	end
	return ""
end
