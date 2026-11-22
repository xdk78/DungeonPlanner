-- Raid assignment pages: named pages of free text per boss or phase, in the style of the raid assignment addons
-- (docs/research/feature-research.md, section 1.4). Pure (no game API): the data and its edits, validation, the
-- keyword expansion, the send and accept permissions, the Notes window's show/hide state machine, and the store of
-- pages received from the raid leader. UI/NotesFrame.lua draws them; Share/Comm.lua sends them.
--
-- Storage, in the plan (optional; absent when a plan has none, so older readers and older strings are untouched):
--
--   plan.pages = { v = 1, list = { page, ... } }
--   page = { id = "n4", title = "Phase 2", encounter = "e2"? (the boss it belongs to), text = "..." }
--
-- Keywords in a page's text, case ignored, expanded when the page is shown or posted (never stored expanded):
--   {star} {circle} {diamond} {triangle} {moon} {square} {cross} {x} {skull}, {rt1}..{rt8}   raid target icons
--   {tank} {healer} {heal} {dps} {damage}                                                    role icons
--   {group 2} {group2} {g2}                                       the names in that raid group of the plan
--   {warrior} {mage} ... (the client's class tokens and names)                                 class icons
-- Player names whose class is known (the group the player is in) are coloured by class; a line naming the player, or
-- the group the plan puts them in, is marked as theirs.
--
-- Every function that changes a plan refuses a recommended (bundled) plan, like Model/Plan.lua; each change stamps
-- plan.updated. Ids come from the plan's own counter (letter "n").

local _, ns = ...
local Pages = ns:NewModule("Pages")
local Util, Schema = ns.Util, ns.Schema

Pages.VERSION = 1
Pages.MAX_RECEIVED = 10 -- pages kept from the raid leader, per character

local EMPTY = {}

local function touch(plan)
	plan.updated = ns.Now()
end

-- The plan's pages (never nil; read-only use).
function Pages.List(plan)
	local p = plan and plan.pages
	return type(p) == "table" and type(p.list) == "table" and p.list or EMPTY
end

function Pages.Find(plan, id)
	for i, page in ipairs(Pages.List(plan)) do
		if page.id == id then
			return page, i
		end
	end
	return nil
end

-- Validation ---------------------------------------------------------------------------------------------------------------

-- { v = 1, list = { ... } } from untrusted input; nil when nothing is left. A newer `v` is dropped whole (this build
-- cannot know what it means) and reported; pages over the cap, without an id or without any text are dropped.
function Pages.Validate(raw, encounterIds, report, takeId)
	if type(raw) ~= "table" then
		return nil
	end
	local version = raw.v == nil and 1 or (Util.IsInteger(raw.v) and raw.v >= 1 and raw.v or nil)
	local listIn = type(raw.list) == "table" and raw.list or EMPTY
	local function drop()
		report.dropped.pages = (report.dropped.pages or 0) + 1
	end
	if not version or version > Pages.VERSION then
		for _ in ipairs(listIn) do
			drop()
		end
		return nil
	end
	local out, seen = {}, {}
	for _, p in ipairs(listIn) do
		if #out >= Schema.MAX.pages then
			drop()
		else
			local pid = type(p) == "table" and takeId(seen, p.id, report, "pages")
			if pid then
				local title = Util.CleanText(p.title, Schema.TEXT.name) or ""
				local text = Util.CleanText(p.text, Schema.TEXT.page, true) or ""
				if title == "" and text == "" then
					drop()
				else
					out[#out + 1] = {
						id = pid,
						title = title,
						text = text,
						encounter = p.encounter and encounterIds[p.encounter] and p.encounter or nil,
					}
				end
			end
		end
	end
	if #out == 0 then
		return nil
	end
	return { v = Pages.VERSION, list = out }
end

-- Edits --------------------------------------------------------------------------------------------------------------------

function Pages.Add(plan, title, encounter)
	local list = Pages.List(plan)
	if #list >= Schema.MAX.pages then
		return nil, "limit"
	end
	if list == EMPTY then
		plan.pages = { v = Pages.VERSION, list = {} }
		list = plan.pages.list
	end
	local n = plan.nextId or 1
	plan.nextId = n + 1
	local page = {
		id = "n" .. n,
		title = Util.CleanText(title or "", Schema.TEXT.name) or "",
		text = "",
		encounter = encounter and Util.FindById(plan.encounters, encounter) and encounter or nil,
	}
	list[#list + 1] = page
	touch(plan)
	return page
end

-- fields: title, text, encounter (false clears it).
function Pages.Update(plan, id, fields)
	local page = Pages.Find(plan, id)
	if not page then
		return nil, "missing"
	end
	if fields.title ~= nil then
		page.title = Util.CleanText(fields.title, Schema.TEXT.name) or ""
	end
	if fields.text ~= nil then
		page.text = Util.CleanText(fields.text, Schema.TEXT.page, true) or ""
	end
	if fields.encounter ~= nil then
		page.encounter = fields.encounter and Util.FindById(plan.encounters, fields.encounter) and fields.encounter or nil
	end
	touch(plan)
	return page
end

function Pages.Remove(plan, id)
	local _, index = Pages.Find(plan, id)
	if not index then
		return nil, "missing"
	end
	table.remove(plan.pages.list, index)
	if #plan.pages.list == 0 then
		plan.pages = nil
	end
	touch(plan)
	return true
end

function Pages.Move(plan, id, delta)
	local list = Pages.List(plan)
	local _, index = Pages.Find(plan, id)
	local to = index and index + delta
	if not to or to < 1 or to > #list then
		return nil, "edge"
	end
	list[index], list[to] = list[to], list[index]
	touch(plan)
	return true
end

-- A boss was removed: its pages stay, as general pages.
function Pages.Unlink(plan, encId)
	for _, page in ipairs(Pages.List(plan)) do
		if page.encounter == encId then
			page.encounter = nil
		end
	end
end

-- The page for an encounter that started: the first page tied to the plan boss whose game ID (idOf) or name (nameOf)
-- matches. nil when none.
function Pages.ForEncounter(plan, encounterID, name, idOf, nameOf)
	local want = ns.Match.Norm(name or "")
	for _, page in ipairs(Pages.List(plan)) do
		local enc = page.encounter and Util.FindById(plan.encounters, page.encounter)
		if enc then
			local id = idOf and idOf(enc)
			if (id and encounterID and id == encounterID) or (want ~= "" and (ns.Match.Norm(nameOf and nameOf(enc) or "") == want
				or ns.Match.Norm(enc.name or "") == want)) then
				return page
			end
		end
	end
	return nil
end

-- Keywords -----------------------------------------------------------------------------------------------------------------

Pages.RAID_ICONS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8 }
Pages.ROLES = { tank = "TANK", tanks = "TANK", healer = "HEALER", healers = "HEALER", heal = "HEALER", dps = "DAMAGER",
	damage = "DAMAGER", damager = "DAMAGER" }

-- What a {keyword} is: "icon", n | "role", ROLE | "group", n | "class", TOKEN | nil.
function Pages.Keyword(word, classes)
	word = word:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if Pages.RAID_ICONS[word] then
		return "icon", Pages.RAID_ICONS[word]
	end
	local rt = tonumber(word:match("^rt(%d)$") or "")
	if rt and rt >= 1 and rt <= 8 then
		return "icon", rt
	end
	if Pages.ROLES[word] then
		return "role", Pages.ROLES[word]
	end
	local g = tonumber(word:match("^group%s*(%d)$") or word:match("^g(%d)$") or "")
	if g and g >= 1 and g <= Schema.MAX.groups then
		return "group", g
	end
	if classes and classes[word] then
		return "class", classes[word]
	end
	return nil
end

-- The raid group (1..8) the plan puts `name` in, or nil. isMe(stored): an own test for the stored names (the whole
-- name, or a first name stored before plans kept surnames: Party.Match), instead of comparing them with `name`.
function Pages.GroupOf(groups, name, isMe)
	for g, members in ipairs(groups or EMPTY) do
		if isMe then
			for _, stored in ipairs(members) do
				if isMe(stored) then
					return g
				end
			end
		elseif Util.IndexOf(members, name) then
			return g
		end
	end
	return nil
end

local NAME_CHARS = "[%a\128-\255]+"

-- Expand a page's text. env (all optional):
--   chat = true            for raid chat: {rtN} (the chat draws the icon), role and class words, plain names
--   groups                 the plan's raid groups (for {group N})
--   me                     the player's name: their lines are marked
--   isMe(name)             is a name the plan stores the player's (whole or first name)? (else: equal to me)
--   own                    the mark put before the player's lines (display only), e.g. a coloured ">"
--   classes                [lower-case class token or name] = TOKEN (from the client)
--   classOf(name)          a group member's class token, when known
--   raidIcon(n), roleIcon(role), classIcon(token)   inline textures (display)
--   roleName(role), className(token)                words (chat, and display without an icon)
--   colorName(name, token)                          a name in its class colour (display)
-- Returns the expanded text and the number of lines marked as the player's.
function Pages.Expand(text, env)
	env = env or {}
	local myGroup = env.me and Pages.GroupOf(env.groups, env.me, env.isMe)
	local function plainName(name)
		if env.chat or not env.classOf or not env.colorName then
			return name
		end
		local token = env.classOf(name)
		return token and env.colorName(name, token) or name
	end
	local function names(g)
		local out = {}
		for _, name in ipairs((env.groups or EMPTY)[g] or EMPTY) do
			out[#out + 1] = plainName(name)
		end
		return out
	end
	local function keyword(inner)
		local kind, value = Pages.Keyword(inner, env.classes)
		if kind == "icon" then
			if env.chat then
				return "{rt" .. value .. "}"
			end
			return env.raidIcon and env.raidIcon(value) or ("{rt" .. value .. "}")
		elseif kind == "role" then
			if not env.chat and env.roleIcon then
				return env.roleIcon(value)
			end
			return env.roleName and env.roleName(value) or value
		elseif kind == "group" then
			local list = names(value)
			if #list == 0 then
				return env.groupName and env.groupName(value) or ("G" .. value)
			end
			return table.concat(list, ", ")
		elseif kind == "class" then
			if not env.chat and env.classIcon then
				local icon = env.classIcon(value)
				if icon then
					return icon
				end
			end
			return env.className and env.className(value) or value
		end
		return "{" .. inner .. "}"
	end
	local lines, marked = {}, 0
	for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
		local mine = false
		if env.me then
			for word in line:gmatch(NAME_CHARS) do
				if word == env.me then
					mine = true
				end
			end
			if myGroup then
				for inner in line:gmatch("{([^{}]*)}") do
					local kind, value = Pages.Keyword(inner, env.classes)
					if kind == "group" and value == myGroup then
						mine = true
					end
				end
			end
		end
		-- Plain text between keywords: names coloured; keywords: expanded.
		local out, pos = {}, 1
		while true do
			local s, e, inner = line:find("{([^{}]*)}", pos)
			local plain = line:sub(pos, (s or 0) - 1)
			if s == nil then
				plain = line:sub(pos)
			end
			out[#out + 1] = (plain:gsub(NAME_CHARS, plainName))
			if not s then
				break
			end
			out[#out + 1] = keyword(inner)
			pos = e + 1
		end
		local expanded = table.concat(out)
		if mine then
			marked = marked + 1
			if env.own and not env.chat then
				expanded = env.own .. expanded
			end
		end
		lines[#lines + 1] = expanded
	end
	-- The loop adds one empty line for the final "\n" it appended.
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return table.concat(lines, "\n"), marked
end

-- Raid chat lines from a page: expanded for chat, empty lines left out, each cut to `max` bytes, at most `limit`.
function Pages.ChatLines(page, env, max, limit)
	local chatEnv = setmetatable({ chat = true }, { __index = env })
	local text = Pages.Expand(page.text, chatEnv)
	local out = {}
	if page.title ~= "" then
		out[1] = Util.TruncateUTF8(page.title, max)
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		line = Util.Trim(line)
		if line ~= "" and #out < limit then
			out[#out + 1] = Util.TruncateUTF8(line, max)
		end
	end
	return out
end

-- Permissions --------------------------------------------------------------------------------------------------------------

-- May the player send a page to their group? group = { inGroup, inRaid, leader, assist }. In a raid the leader and
-- assistants may; in a party the leader. Returns true, or false and "group" (not in a group) / "rank".
function Pages.CanSend(group)
	if not (group and group.inGroup) then
		return false, "group"
	end
	if group.leader or (group.inRaid and group.assist) then
		return true
	end
	return false, "rank"
end

-- Does the player take a page from `sender`? policy: "leaders" (the group's leader or, in a raid, an assistant),
-- "group" (anyone in the group) or "nobody". sender = { inGroup, leader, assist, inRaid }.
function Pages.AcceptFrom(policy, sender)
	if policy == "nobody" or not (sender and sender.inGroup) then
		return false
	end
	if policy == "group" then
		return true
	end
	return sender.leader == true or (sender.inRaid == true and sender.assist == true)
end

-- A received page, from untrusted input: { title, text, boss?, enc?, plan? }, or nil.
function Pages.ValidatePush(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local text = Util.CleanText(raw.text, Schema.TEXT.page, true) or ""
	local title = Util.CleanText(raw.title, Schema.TEXT.name) or ""
	if text == "" and title == "" then
		return nil
	end
	return {
		title = title,
		text = text,
		boss = Util.CleanText(raw.boss, Schema.TEXT.name) or nil,
		enc = Util.IsInteger(raw.enc) and raw.enc > 0 and raw.enc or nil,
		plan = Util.CleanText(raw.plan, Schema.TEXT.name) or nil,
	}
end

-- Received pages (DungeonPlannerDB.char[key].notes) --------------------------------------------------------------------------

function Pages.NormalizeReceived(store)
	if type(store) ~= "table" then
		store = {}
	end
	local list = {}
	for _, r in ipairs(type(store.received) == "table" and store.received or EMPTY) do
		local page = type(r) == "table" and Pages.ValidatePush(r)
		if page and #list < Pages.MAX_RECEIVED then
			page.from = Util.CleanText(r.from, Schema.TEXT.player) or "?"
			page.at = Util.IsInteger(r.at) and r.at or 0
			list[#list + 1] = page
		end
	end
	store.received = list
	return store
end

-- Keep a received page: it replaces an older one from the same sender with the same title; the oldest go first.
function Pages.Receive(store, page, from, now)
	page.from, page.at = from, now
	for i = #store.received, 1, -1 do
		local r = store.received[i]
		if r.from == from and r.title == page.title then
			table.remove(store.received, i)
		end
	end
	store.received[#store.received + 1] = page
	while #store.received > Pages.MAX_RECEIVED do
		table.remove(store.received, 1)
	end
	return page
end

-- The received page for an encounter that started (newest first), by game ID or boss name.
function Pages.ReceivedFor(store, encounterID, name)
	local want = ns.Match.Norm(name or "")
	for i = #store.received, 1, -1 do
		local r = store.received[i]
		if (r.enc and encounterID and r.enc == encounterID) or (want ~= "" and r.boss and ns.Match.Norm(r.boss) == want) then
			return r
		end
	end
	return nil
end

-- The Notes window -------------------------------------------------------------------------------------------------------
-- State: { shown (the player opened it), auto (opened by a boss pull), combat, hideInCombat }. Events:
--   { type = "open" } { type = "close" } { type = "toggle" }
--   { type = "encounterStart", page = true when a page was found, autoShow = setting } { type = "encounterEnd" }
--   { type = "combat", on = bool } { type = "setting", hideInCombat = bool }
-- Returns whether the window is visible now. A boss pull shows it (when a page belongs to that boss and auto-show is on)
-- and its end hides it again, unless the player had opened it. "Hide in combat" wins while in combat.

function Pages.NewView()
	return { shown = false, auto = false, combat = false, hideInCombat = false }
end

function Pages.Visible(view)
	return (view.shown or view.auto) and not (view.hideInCombat and view.combat)
end

function Pages.ViewStep(view, event)
	local t = event.type
	if t == "open" then
		view.shown = true
	elseif t == "close" then
		view.shown, view.auto = false, false
	elseif t == "toggle" then
		if Pages.Visible(view) or view.shown or view.auto then
			view.shown, view.auto = false, false
		else
			view.shown = true
		end
	elseif t == "encounterStart" then
		if event.page and event.autoShow then
			view.auto = true
		end
	elseif t == "encounterEnd" then
		view.auto = false
	elseif t == "combat" then
		view.combat = event.on and true or false
	elseif t == "setting" then
		view.hideInCombat = event.hideInCombat and true or false
	end
	return Pages.Visible(view)
end

-- Recommended plans are read-only: the edits refuse them, like Model/Plan.lua's.
for _, name in ipairs({ "Add", "Update", "Remove", "Move", "Unlink" }) do
	local fn = Pages[name]
	Pages[name] = function(plan, ...)
		if type(plan) == "table" and plan.bundled then
			return nil, "read-only"
		end
		return fn(plan, ...)
	end
end
