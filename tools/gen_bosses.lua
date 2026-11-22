-- Generates the bundled boss facts (Data/Bosses/<slug>.lua) from data-src/bosses/*.json (schema: data-src/bosses/README.md).
--   lua tools/gen_bosses.lua            writes Data/Bosses/<slug>.lua and the TOC block
--   lua tools/gen_bosses.lua --check    writes nothing; exits 1 when the JSON is invalid, a boss of a recommended plan
--                                       (data-src/dungeons/*.json) has no entry, or a file on disk differs
--   lua tools/gen_bosses.lua --report   also prints the coverage per field
-- Plain Lua 5.1, run from the repository root. The output is deterministic. Only IDs, numbers and short tags ship (the
-- game supplies spell, item and creature text); quest titles, key names and the researcher's own notes on abilities
-- and keys are the exceptions.

local OUT_DIR = "Data/Bosses"
local IN_DIR = "data-src/bosses"
local PLANS_DIR = "data-src/dungeons"
local TOC = "DungeonPlanner.toc"

local plans = dofile("tools/gen_plans.lua")
local decode = plans.DecodeJSON

local M = {}
M.CLASSES = { normal = "n", elite = "e", rareelite = "re", worldboss = "wb", rare = "r" }
M.TAGS = { interrupt = true, dispel = true, tank = true, healer = true, enrage = true, deadly = true, bleed = true,
	control = true, aoe = true, adds = true }
M.SIDES = { both = "b", alliance = "a", horde = "h" }
M.MAX_ABILITIES, M.MAX_LOOT, M.MAX_NOTE = 8, 16, 160
M.KEY_KINDS = { key = true, attunement = true, summon = true }
M.MAX_KEYS = 8

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function listFiles(dir, ext)
	local sep = package.config:sub(1, 1)
	local cmd = sep == "\\" and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. dir .. '" 2>/dev/null')
	local out = {}
	local p = io.popen(cmd)
	if p then
		for name in p:lines() do
			name = name:gsub("\r", "")
			if name:sub(-#ext) == ext then
				out[#out + 1] = name
			end
		end
		p:close()
	end
	table.sort(out)
	return out
end

M.ListFiles = listFiles

local function isInt(v)
	return type(v) == "number" and v == math.floor(v) and v > 0 and v < 2 ^ 31
end

-- Validation -------------------------------------------------------------------------------------------------------------

-- The errors (strings) of one decoded data-src/bosses file; `plan` is the decoded data-src/dungeons file of the same slug.
function M.Validate(doc, file, plan)
	local errs = {}
	local function err(msg, ...)
		errs[#errs + 1] = file .. ": " .. string.format(msg, ...)
	end
	if type(doc) ~= "table" then
		return { file .. ": not an object" }
	end
	if doc.schema ~= 1 then
		err("schema must be 1")
	end
	if doc.slug ~= file:gsub("%.json$", "") then
		err("slug %s does not match the file name", tostring(doc.slug))
	end
	if type(doc.name) ~= "string" or doc.name == "" then
		err("name missing")
	end
	if type(doc.updated) ~= "string" or not doc.updated:match("^%d%d%d%d%-%d%d%-%d%d$") then
		err("updated must be YYYY-MM-DD")
	end
	local sources = {}
	for _, s in ipairs(type(doc.sources) == "table" and doc.sources or {}) do
		if isInt(s.id) and type(s.name) == "string" and type(s.url) == "string" and type(s.licence) == "string" then
			sources[s.id] = s
		else
			err("a source needs id, name, url and licence")
		end
	end
	if next(sources) == nil then
		err("no sources")
	end
	local function src(v, what)
		if not sources[v] then
			err("%s names an unknown source %s", what, tostring(v))
		end
	end
	local points = {}
	for _, p in ipairs(plan and plan.points or {}) do
		if p.kind == "boss" then
			points[p.id] = p.name
		end
	end
	local seen = {}
	for i, b in ipairs(type(doc.bosses) == "table" and doc.bosses or {}) do
		local at = "boss " .. i .. " (" .. tostring(b.name) .. ")"
		if type(b.point) ~= "string" or type(b.name) ~= "string" then
			err("%s: point and name are required", at)
		else
			if plan and points[b.point] ~= b.name then
				err("%s: point %s is not a boss of that name in data-src/dungeons", at, b.point)
			end
			seen[b.point] = true
		end
		for _, key in ipairs({ "npcID", "displayID" }) do
			if b[key] ~= nil and not isInt(b[key]) then
				err("%s: %s must be a positive integer", at, key)
			end
		end
		for _, m in ipairs(b.members or {}) do
			if not isInt(m) then
				err("%s: members must be integers", at)
			end
		end
		if b.level ~= nil then
			local l = b.level
			if not (l == "??" or (type(l) == "table" and isInt(l[1]) and isInt(l[2]) and l[1] <= l[2] and l[2] < 200)) then
				err("%s: level must be [min, max] or \"??\"", at)
			end
		end
		if b.class ~= nil and not M.CLASSES[b.class] then
			err("%s: unknown class %s", at, tostring(b.class))
		end
		if #(b.abilities or {}) > M.MAX_ABILITIES then
			err("%s: more than %d abilities", at, M.MAX_ABILITIES)
		end
		for _, a in ipairs(b.abilities or {}) do
			if not isInt(a.spell) then
				err("%s: ability spell must be an integer", at)
			end
			for _, t in ipairs(a.tags or {}) do
				if not M.TAGS[t] then
					err("%s: unknown ability tag %s", at, tostring(t))
				end
			end
			if a.note ~= nil and (type(a.note) ~= "string" or #a.note > M.MAX_NOTE or a.note:find("[|%c]")) then
				err("%s: ability %s has a bad note", at, tostring(a.spell))
			end
			src(a.src, at .. " ability")
		end
		if #(b.loot or {}) > M.MAX_LOOT then
			err("%s: more than %d drops", at, M.MAX_LOOT)
		end
		for _, l in ipairs(b.loot or {}) do
			if not isInt(l.item) then
				err("%s: item must be an integer", at)
			end
			src(l.src, at .. " drop")
		end
		for k, v in pairs(b.src or {}) do
			src(v, at .. " " .. k)
		end
		local has = b.npcID or b.displayID or b.level or b.class or (b.abilities and #b.abilities > 0)
			or (b.loot and #b.loot > 0)
		if not has and type(b.gap) ~= "string" then
			err("%s: no data and no gap reason", at)
		end
	end
	for id, name in pairs(points) do
		if not seen[id] then
			err("boss %s (%s) of the recommended plan has no entry", id, name)
		end
	end
	for i, q in ipairs(type(doc.quests) == "table" and doc.quests or {}) do
		local at = "quest " .. i
		if not isInt(q.id) or type(q.name) ~= "string" then
			err("%s: id and name are required", at)
		end
		for _, key in ipairs({ "level", "req", "giver" }) do
			if q[key] ~= nil and not isInt(q[key]) then
				err("%s: %s must be an integer", at, key)
			end
		end
		if not M.SIDES[q.side or "both"] then
			err("%s: unknown side", at)
		end
		for _, it in ipairs(q.items or {}) do
			if not isInt(it) then
				err("%s: items must be integers", at)
			end
		end
		src(q.src, at)
	end
	-- Keys and attunements: an item (its count is checked) or a quest (completed or not; `alt` lists other IDs of the
	-- same quest, any of which counts). Rows with the same `group` are one key (an item and the quests toward it).
	local keys = type(doc.keys) == "table" and doc.keys or {}
	if #keys > M.MAX_KEYS then
		err("more than %d keys", M.MAX_KEYS)
	end
	for i, k in ipairs(keys) do
		local at = "key " .. i .. " (" .. tostring(k.name) .. ")"
		if (k.item ~= nil) == (k.quest ~= nil) or not isInt(k.item or k.quest) then
			err("%s: needs one of item or quest (an integer)", at)
		end
		if type(k.name) ~= "string" or k.name == "" or k.name:find("[|%c]") then
			err("%s: name is required", at)
		end
		if not M.KEY_KINDS[k.kind] then
			err("%s: unknown kind %s", at, tostring(k.kind))
		end
		if type(k.required) ~= "boolean" or type(k.forever) ~= "boolean" then
			err("%s: required and forever must be true or false", at)
		end
		if not M.SIDES[k.side or "both"] then
			err("%s: unknown side", at)
		end
		for _, id in ipairs(k.quests or {}) do
			if not isInt(id) then
				err("%s: quests must be integers", at)
			end
		end
		if k.alt ~= nil then
			local fine = k.quest ~= nil and type(k.alt) == "table" and #k.alt > 0 and #k.alt <= 4
			for _, id in ipairs(type(k.alt) == "table" and k.alt or {}) do
				fine = fine and isInt(id) and id ~= k.quest
			end
			if not fine then
				err("%s: alt must list 1-4 other quest IDs of a quest key", at)
			end
		end
		if k.group ~= nil and not (type(k.group) == "string" and k.group:match("^[a-z]+$") and #k.group <= 16) then
			err("%s: group must be a short lower-case word", at)
		end
		if k.note ~= nil and (type(k.note) ~= "string" or #k.note > M.MAX_NOTE or k.note:find("[|%c]")) then
			err("%s: bad note", at)
		end
		src(k.src, at)
	end
	return errs
end

-- Rendering --------------------------------------------------------------------------------------------------------------

local function q(s)
	return string.format("%q", s):gsub("\\\n", "\\n")
end

local function ints(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = string.format("%d", v)
	end
	return "{ " .. table.concat(out, ", ") .. " }"
end

-- Numbers wrapped under the 160-column lint limit, one indented block.
local function wrapInts(list, indent)
	local lines, cur = {}, indent
	for i, v in ipairs(list) do
		local piece = string.format("%d", v) .. ","
		if #cur + #piece + 1 > 120 and cur ~= indent then
			lines[#lines + 1] = cur
			cur = indent
		end
		cur = cur .. (cur ~= indent and " " or "") .. piece
		if i == #list then
			lines[#lines + 1] = cur
		end
	end
	return table.concat(lines, "\n")
end

local function renderBoss(b)
	local head = { "name = " .. q(b.name) }
	if b.npcID then
		head[#head + 1] = "npc = " .. b.npcID
	end
	if b.displayID then
		head[#head + 1] = "disp = " .. b.displayID
	end
	if b.level then
		head[#head + 1] = "lv = " .. (b.level == "??" and '"??"' or string.format("{ %d, %d }", b.level[1], b.level[2]))
	end
	if b.class then
		head[#head + 1] = "cls = " .. q(M.CLASSES[b.class])
	end
	local out = { "\t\t{ " .. table.concat(head, ", ") .. "," }
	if b.members and #b.members > 0 then
		out[#out + 1] = "\t\t\tmembers = " .. ints(b.members) .. ","
	end
	if b.abilities and #b.abilities > 0 then
		out[#out + 1] = "\t\t\tab = {"
		for _, a in ipairs(b.abilities) do
			local row = string.format("{ %d", a.spell)
			local tags = a.tags and #a.tags > 0 and table.concat(a.tags, ",") or nil
			if tags or a.note then
				row = row .. ", " .. (tags and q(tags) or "false")
			end
			if a.note then
				row = row .. ", " .. q(a.note)
			end
			out[#out + 1] = "\t\t\t\t" .. row .. " },"
		end
		out[#out + 1] = "\t\t\t},"
	end
	if b.loot and #b.loot > 0 then
		local all, notable = {}, {}
		for _, l in ipairs(b.loot) do
			all[#all + 1] = l.item
			if l.notable then
				notable[#notable + 1] = l.item
			end
		end
		out[#out + 1] = "\t\t\tloot = {\n" .. wrapInts(all, "\t\t\t\t") .. "\n\t\t\t},"
		if #notable > 0 then
			out[#out + 1] = "\t\t\tnotable = {\n" .. wrapInts(notable, "\t\t\t\t") .. "\n\t\t\t},"
		end
	end
	out[#out + 1] = "\t\t},"
	return table.concat(out, "\n") .. "\n"
end

local function renderQuest(x)
	local f = { string.format("id = %d", x.id), "name = " .. q(x.name) }
	if x.level then
		f[#f + 1] = "lv = " .. x.level
	end
	if x.req then
		f[#f + 1] = "req = " .. x.req
	end
	if x.side and x.side ~= "both" then
		f[#f + 1] = "side = " .. q(M.SIDES[x.side])
	end
	if x.giver then
		f[#f + 1] = "giver = " .. x.giver
	end
	if x.items and #x.items > 0 then
		f[#f + 1] = "items = " .. ints(x.items)
	end
	return "\t\t{ " .. table.concat(f, ", ") .. " },\n"
end

local function renderKey(k)
	local f = { k.item and string.format("item = %d", k.item) or string.format("quest = %d", k.quest),
		"name = " .. q(k.name), "kind = " .. q(k.kind) }
	if k.required then
		f[#f + 1] = "req = true"
	end
	if k.side and k.side ~= "both" then
		f[#f + 1] = "side = " .. q(M.SIDES[k.side])
	end
	if k.quests and #k.quests > 0 then
		f[#f + 1] = "quests = " .. ints(k.quests)
	end
	if k.alt then
		f[#f + 1] = "alt = " .. ints(k.alt)
	end
	if k.group then
		f[#f + 1] = "group = " .. q(k.group)
	end
	if k.forever then
		f[#f + 1] = "fv = true"
	end
	local line = "\t\t{ " .. table.concat(f, ", ")
	if k.note then
		line = line .. ",\n\t\t\tnote = " .. q(k.note)
	end
	return line .. " },"
end

function M.Render(doc, file)
	local names = {}
	for _, s in ipairs(doc.sources) do
		names[#names + 1] = s.name
	end
	local out = {
		"-- GENERATED by tools/gen_bosses.lua from data-src/bosses/" .. file .. ". Do not edit by hand:",
		"-- change the research data or the generator and run `lua tools/gen_bosses.lua`.",
		"-- Bundled boss facts (IDs and numbers; docs/DATA-SOURCES.md): " .. table.concat(names, ", ") .. ".",
		"",
		"local _, ns = ...",
		"ns.BossData.Add({",
		"\tslug = " .. q(doc.slug) .. ",",
		"\tname = " .. q(doc.name) .. ",",
		"\tkind = " .. q(doc.kind) .. ",",
		"\tupdated = " .. q(doc.updated) .. ",",
		"\tbosses = {",
	}
	for _, b in ipairs(doc.bosses) do
		out[#out + 1] = (renderBoss(b):gsub("\n$", ""))
	end
	out[#out + 1] = "\t},"
	if doc.quests and #doc.quests > 0 then
		out[#out + 1] = "\tquests = {"
		for _, x in ipairs(doc.quests) do
			out[#out + 1] = (renderQuest(x):gsub("\n$", ""))
		end
		out[#out + 1] = "\t},"
	end
	if doc.keys and #doc.keys > 0 then
		out[#out + 1] = "\tkeys = {"
		for _, k in ipairs(doc.keys) do
			out[#out + 1] = renderKey(k)
		end
		out[#out + 1] = "\t},"
	end
	out[#out + 1] = "})"
	return table.concat(out, "\n") .. "\n"
end

-- Main -------------------------------------------------------------------------------------------------------------------

local function main(args)
	local check, report = false, false
	for _, a in ipairs(args) do
		check = check or a == "--check"
		report = report or a == "--report"
	end
	local errors, docs = {}, {}
	local planFiles = listFiles(PLANS_DIR, ".json")
	local have = {}
	for _, file in ipairs(listFiles(IN_DIR, ".json")) do
		have[file] = true
		local ok, doc = pcall(decode, assert(readFile(IN_DIR .. "/" .. file)))
		if not ok then
			errors[#errors + 1] = file .. ": " .. tostring(doc)
		else
			local pt = readFile(PLANS_DIR .. "/" .. file)
			local plan = pt and decode(pt)
			if not plan then
				errors[#errors + 1] = file .. ": no matching file in " .. PLANS_DIR
			end
			for _, e in ipairs(M.Validate(doc, file, plan)) do
				errors[#errors + 1] = e
			end
			docs[#docs + 1] = { file = file, doc = doc }
		end
	end
	for _, file in ipairs(planFiles) do
		if not have[file] then
			errors[#errors + 1] = file .. ": no file in " .. IN_DIR
		end
	end
	if #errors > 0 then
		for _, e in ipairs(errors) do
			print(e)
		end
		os.exit(1)
	end
	local differs, tocLines, bytes, wanted = {}, {}, 0, {}
	local cov = { bosses = 0, npc = 0, disp = 0, level = 0, ab = 0, loot = 0, quests = 0, keys = 0 }
	for _, d in ipairs(docs) do
		local slug = d.doc.slug
		local text = M.Render(d.doc, d.file)
		local path = OUT_DIR .. "/" .. slug .. ".lua"
		wanted[slug .. ".lua"] = true
		bytes = bytes + #text
		tocLines[#tocLines + 1] = "Data\\Bosses\\" .. slug .. ".lua"
		for _, b in ipairs(d.doc.bosses) do
			cov.bosses = cov.bosses + 1
			cov.npc = cov.npc + (b.npcID and 1 or 0)
			cov.disp = cov.disp + (b.displayID and 1 or 0)
			cov.level = cov.level + (b.level and 1 or 0)
			cov.ab = cov.ab + ((b.abilities and #b.abilities > 0) and 1 or 0)
			cov.loot = cov.loot + ((b.loot and #b.loot > 0) and 1 or 0)
		end
		cov.quests = cov.quests + #(d.doc.quests or {})
		cov.keys = cov.keys + #(d.doc.keys or {})
		if readFile(path) ~= text then
			differs[#differs + 1] = path
			if not check then
				local w = assert(io.open(path, "wb"))
				w:write(text)
				w:close()
			end
		end
	end
	for _, file in ipairs(listFiles(OUT_DIR, ".lua")) do
		if not wanted[file] then
			differs[#differs + 1] = OUT_DIR .. "/" .. file .. " (no longer generated)"
			if not check then
				os.remove(OUT_DIR .. "/" .. file)
			end
		end
	end
	local tocText = assert(readFile(TOC))
	local eol = tocText:find("\r\n", 1, true) and "\r\n" or "\n"
	local block = "# BEGIN generated bosses (tools/gen_bosses.lua)" .. eol .. table.concat(tocLines, eol) .. eol
		.. "# END generated bosses"
	local newToc
	if tocText:find("# BEGIN generated bosses", 1, true) then
		newToc = tocText:gsub("# BEGIN generated bosses.-# END generated bosses", function()
			return block
		end)
	else
		newToc = tocText:gsub("(# END generated spawns)", function(anchor)
			return anchor .. eol .. eol .. block
		end, 1)
	end
	if newToc ~= tocText then
		differs[#differs + 1] = TOC
		if not check then
			local w = assert(io.open(TOC, "wb"))
			w:write(newToc)
			w:close()
		end
	end
	if report then
		print(string.format("bosses %d, npc %d, display %d, level %d, abilities %d, loot %d, quests %d, "
			.. "keys %d, bytes %d", cov.bosses, cov.npc, cov.disp, cov.level, cov.ab, cov.loot, cov.quests,
			cov.keys, bytes))
	end
	if check then
		if #differs > 0 then
			print("out of date (run `lua tools/gen_bosses.lua`):")
			for _, p in ipairs(differs) do
				print("  " .. p)
			end
			os.exit(1)
		end
		print("generated boss facts are up to date")
	else
		print(string.format("wrote %d boss files (%d changed), %d bytes", #docs, #differs, bytes))
	end
end

if arg and type(arg[0]) == "string" and arg[0]:find("gen_bosses", 1, true) then
	main(arg)
end
return M
