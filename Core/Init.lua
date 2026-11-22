-- Dungeon Planner: namespace, version, events and the internal message bus.
--
-- State lives in the private table `ns` (the second vararg every file receives). The addon object for the Ace3
-- lifecycle is `ns.addon` (AceAddon-3.0 with AceEvent, AceTimer, AceConsole, AceComm); it is a separate table so
-- AceAddon's own NewModule/RegisterEvent never clash with ours. The only public globals are documented in
-- docs/API.md (`DungeonPlanner` and the few names the game requires: bindings, frames, the compartment function).
-- This file must load in plain Lua 5.1 too: tests/ load it without the Ace libraries.

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME or "DungeonPlanner"
ns.title = "Dungeon Planner"
ns.prefix = "DungeonPlanner" -- addon-message prefix, <= 16 bytes (docs/COMPATIBILITY.md)

-- Version from the TOC (the packager replaces @project-version@); a source checkout reports "dev".
do
	local version
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		version = C_AddOns.GetAddOnMetadata(ns.name, "Version")
	end
	if type(version) ~= "string" or version == "" or version:find("@", 1, true) then
		version = "dev"
	end
	ns.version = version
end

-- Protocol and format versions are independent of the addon version: they only change when the wire or string
-- format changes (docs/SHARING-FORMAT.md).
ns.PROTOCOL_VERSION = 2 -- 2: payloads are !DP2! strings (plan format 2)
ns.EXPORT_VERSION = 1

-- Module registry -------------------------------------------------------------------------------------------------------

ns.modules = ns.modules or {}

function ns:NewModule(name)
	local module = self[name] or {}
	self[name] = module
	self.modules[#self.modules + 1] = name
	return module
end

-- Clock: wall time for stored timestamps, GetTime() for intervals. Tests replace these.
function ns.Now()
	return time()
end

function ns.Clock()
	if GetTime then
		return GetTime()
	end
	return os.clock()
end

-- Error isolation -------------------------------------------------------------------------------------------------------

-- Errors raised inside our own entry points (events, bus listeners, button clicks, slash commands) are caught here, kept
-- in a small ring (the last MAX distinct messages, with a count) for the report window (UI/ReportFrame.lua), and passed on
-- to the game's error handler as before. Nothing hooks the global error handler.
local Errors = { MAX = 10, list = {} }
ns.Errors = Errors

-- Names that must not leave the machine in a pasted message: the character, the realm (as shown, "Area 52", and
-- normalized, "Area52"), the guild, everyone in the group, and the player's own plans. A short list, read when needed.
local function privateNames()
	local names, seen = {}, {}
	local plain = ns.Util and ns.Util.Plain or function(v)
		return v
	end
	local function include(variant)
		local key = variant:lower()
		if variant ~= "" and not seen[key] then
			seen[key] = true
			names[#names + 1] = variant
		end
	end
	-- The name as it is, without spaces and hyphens ("Area52"), and for a name of several words its last word on its
	-- own ("First Surname" -> "Surname") when that has 3 characters or more. Plans: the name only (their words are common).
	local function add(name, wholeOnly)
		name = plain(name)
		if type(name) ~= "string" or name == "" then
			return
		end
		include(name)
		if not wholeOnly then
			include((name:gsub("[%s%-]", "")))
			local last = name:match("%s(%S+)$")
			if last and #last >= 3 then
				include(last)
			end
		end
	end
	-- fn's first result, or both for UnitName (name and realm).
	local function call(fn, both, ...)
		if type(fn) == "function" then
			local ok, a, b = pcall(fn, ...)
			if ok then
				add(a)
				if both then
					add(b)
				end
			end
		end
	end
	call(UnitName, true, "player")
	call(GetRealmName, false)
	call(rawget(_G, "GetNormalizedRealmName"), false)
	call(rawget(_G, "GetGuildInfo"), false, "player") -- the guild's name only, not the rank that follows it
	local unitName = UnitName
	if type(unitName) == "function" then
		for i = 1, 4 do
			call(unitName, true, "party" .. i)
		end
		for i = 1, 40 do
			call(unitName, true, "raid" .. i)
		end
	end
	-- The player's own plans, by name, unless the name would eat the messages themselves: under 3 characters, only
	-- digits, or a directory, file or module name that stack lines hold ("Core", "UI", "Model", "Init", "lua", ...).
	local plans = ns.db and ns.db.plans
	if type(plans) == "table" then
		local prefix = ns.Bundled and ns.Bundled.PREFIX
		local reserved = { dungeonplanner = true, interface = true, addons = true, lua = true, core = true, ui = true, model = true,
			share = true, data = true, config = true, tracker = true, libs = true, locales = true, panels = true }
		for _, module in ipairs(ns.modules or {}) do
			reserved[tostring(module):lower()] = true
		end
		for id, plan in pairs(plans) do
			if type(plan) == "table" and not (prefix and type(id) == "string" and id:sub(1, #prefix) == prefix) then
				local name = plain(plan.name)
				if type(name) == "string" and #name >= 3 and not name:find("^%d+$") and not reserved[name:lower()] then
					add(name, true)
				end
			end
		end
	end
	return names
end

-- The code point of the UTF-8 character that starts at byte j, or nil when the bytes are not valid.
local function codePoint(text, j)
	local lead = text:byte(j)
	if not lead then
		return nil
	end
	if lead < 0x80 then
		return lead
	end
	local n = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or nil
	if not n then
		return nil
	end
	local cp = lead - (n == 4 and 0xF0 or n == 3 and 0xE0 or 0xC0)
	for k = 1, n - 1 do
		local b = text:byte(j + k)
		if not b or b < 0x80 or b >= 0xC0 then
			return nil
		end
		cp = cp * 64 + (b - 0x80)
	end
	return cp
end

-- Does the character with this code point belong to a word? ASCII letters and digits, and non-ASCII letters; not the
-- Latin-1 punctuation and no-break space (U+0080-00BF: guillemets, NBSP, inverted marks), the multiplication and division
-- signs, general punctuation and symbols (U+2000-2BFF: dashes, curly quotes, ellipsis) or CJK punctuation.
local function wordChar(cp)
	if cp == nil then
		return true -- invalid bytes: treated as part of a word, the safe side for the rest of the text
	end
	if cp < 0x80 then
		return string.char(cp):find("%w") ~= nil
	end
	return not (cp <= 0xBF or cp == 0xD7 or cp == 0xF7 or (cp >= 0x2000 and cp <= 0x2BFF) or (cp >= 0x3000 and cp <= 0x303F)
		or (cp >= 0xFE00 and cp <= 0xFE0F) or (cp >= 0xFF00 and cp <= 0xFF0F))
end

-- The character that ends just before byte s, and the one that starts at byte e.
local function wordBefore(text, s)
	local i = s - 1
	if i < 1 then
		return false
	end
	local j = i
	while j > 1 and i - j < 3 and text:byte(j) >= 0x80 and text:byte(j) < 0xC0 do
		j = j - 1
	end
	return wordChar(codePoint(text, j))
end

local function wordAfter(text, e)
	if e > #text then
		return false
	end
	return wordChar(codePoint(text, e))
end

-- `name` replaced by <name> wherever it stands as a whole word. The match ignores case for ASCII letters only (the
-- lower-casing is byte-wise), so "Tester" and "TESTER" match, "Zażółć" and "ZAŻÓŁĆ" do not.
local function scrubName(text, name)
	local low, wanted = text:lower(), name:lower()
	local out, pos = {}, 1
	while true do
		local s, e = low:find(wanted, pos, true)
		if not s then
			break
		end
		if not wordBefore(text, s) and not wordAfter(text, e + 1) then
			out[#out + 1] = text:sub(pos, s - 1)
			out[#out + 1] = "<name>"
			pos = e + 1
		else
			out[#out + 1] = text:sub(pos, s)
			pos = s + 1
		end
	end
	out[#out + 1] = text:sub(pos)
	return table.concat(out)
end

-- The text with those names replaced, of any length, whole words only (so a two-letter name does not eat other words).
function Errors.Scrub(text)
	text = tostring(text or "")
	local ok, names = pcall(privateNames)
	if ok then
		-- Longest first: "Area 52" before "Area".
		table.sort(names, function(a, b)
			return #a > #b
		end)
		for _, name in ipairs(names) do
			text = scrubName(text, name)
		end
	end
	return text
end

-- Shortens the add-on path, scrubs the names (above) and cuts the message, so it can be pasted in public.
function Errors.Clean(text)
	text = tostring(text or ""):gsub("Interface[/\\]AddOns[/\\]", "")
	text = Errors.Scrub(text)
	if #text > 400 then
		text = text:sub(1, 400) .. "..."
	end
	return text
end

-- A short log of what the addon did (about LOG_MAX lines; the report window shows the last few). Only our own system
-- facts go in, never chat or names: errors, the probe starting, a plan opened by id. Bounded.
local LOG_MAX = 200
local log = {}

function ns.Log(text)
	log[#log + 1] = { at = ns.Now and ns.Now() or 0, text = Errors.Clean(text) }
	if #log > LOG_MAX then
		table.remove(log, 1)
	end
end

function ns.LogLines(count)
	local out = {}
	for i = math.max(1, #log - count + 1), #log do
		out[#out + 1] = log[i]
	end
	return out
end

function Errors.Record(err, kind)
	local message = (kind and (kind .. " ") or "") .. Errors.Clean(err)
	ns.Log(message)
	local list = Errors.list
	for i = #list, 1, -1 do
		if list[i].message == message then
			local item = table.remove(list, i)
			item.count = item.count + 1
			list[#list + 1] = item
			return
		end
	end
	list[#list + 1] = { message = message, count = 1 }
	while #list > Errors.MAX do
		table.remove(list, 1)
	end
end

function Errors.Clear()
	Errors.list = {}
end

-- The same message goes to the game's error handler (BugSack and the error frame, untouched: nothing replaces it) at most
-- once every RAISE_EVERY seconds; a handler that fails every frame would otherwise flood them.
local RAISE_EVERY = 30
local raised = {}
local raisedCount = 0

local function throttle(err)
	local key = Errors.Clean(err)
	local now = ns.Clock()
	local last = raised[key]
	if last and now - last < RAISE_EVERY then
		return false
	end
	if raisedCount >= 50 then
		raised, raisedCount = {}, 0
	end
	if not last then
		raisedCount = raisedCount + 1
	end
	raised[key] = now
	return true
end

-- Raise when in doubt: if the bookkeeping itself fails, the error still goes through.
local function shouldRaise(err)
	local ok, raise = pcall(throttle, err)
	return not ok or raise
end

function ns.SafeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		pcall(Errors.Record, err)
		if shouldRaise(err) then
			-- A broken error handler (a failing BugSack) must not escape the isolation either.
			local handler = geterrorhandler and geterrorhandler()
			if handler then
				pcall(handler, err)
			else
				print("DungeonPlanner error: " .. tostring(err))
			end
		end
	end
	return ok, err
end

-- Internal message bus ------------------------------------------------------------------------------------------------
-- Between our own modules ("PLAN_CHANGED", "STYLE_CHANGED", ...). Synchronous; one failing listener never stops the
-- others. Public events for other addons go through ns.API's CallbackHandler (Core/API.lua).

local listeners = {}

function ns:On(message, owner, fn)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[#list + 1] = { owner = owner, fn = fn }
end

function ns:Off(message, owner)
	local list = listeners[message]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i].owner == owner then
			table.remove(list, i)
		end
	end
end

function ns:Fire(message, ...)
	local list = listeners[message]
	if not list then
		return
	end
	local copy = {}
	for i = 1, #list do
		copy[i] = list[i]
	end
	for i = 1, #copy do
		self.SafeCall(copy[i].fn, ...)
	end
end

-- Printing --------------------------------------------------------------------------------------------------------------

function ns:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	print("|cffa1a1a1Dungeon Planner:|r " .. table.concat(parts, " "))
end

function ns:Debug(...)
	if self.db and self.db.settings and self.db.settings.debug then
		self:Print("[debug]", ...)
	end
end

-- Ace3 addon object -------------------------------------------------------------------------------------------------------

local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
if AceAddon then
	ns.addon = AceAddon:NewAddon(ns.name, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0", "AceComm-3.0")
end

-- Game events -------------------------------------------------------------------------------------------------------------
-- AceEvent allows one handler per event per object; modules may each want the same event, so ns:RegisterEvent keeps a
-- list per event and registers one AceEvent dispatcher for it.

local eventHandlers = {}

-- The events we listen to (for /dp perf, which swaps the dispatcher only while a probe runs).
function ns.EventTable()
	return eventHandlers
end

local function dispatch(event, ...)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	for i = 1, #handlers do
		ns.SafeCall(handlers[i], event, ...)
	end
end

-- The one callback AceEvent calls for every event we listen to (/dp perf registers a timed one in its place).
function ns.EventDispatcher()
	return dispatch
end

function ns:RegisterEvent(event, handler)
	local handlers = eventHandlers[event]
	if not handlers then
		handlers = {}
		eventHandlers[event] = handlers
		if self.addon then
			-- RegisterEvent raises for an event the client does not know: that is a missing feature here, not an error.
			local ok = pcall(self.addon.RegisterEvent, self.addon, event, dispatch)
			if not ok then
				eventHandlers[event] = nil
				return false
			end
		end
	end
	handlers[#handlers + 1] = handler
	return true
end

-- Combat deferral: run fn now, or when combat ends. Dungeon Planner never touches protected frames, but sharing,
-- popups and heavy work wait until the player is out of combat.
local afterCombat = {}

function ns:RunOutOfCombat(fn)
	if InCombatLockdown and InCombatLockdown() then
		afterCombat[#afterCombat + 1] = fn
		return false
	end
	fn()
	return true
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local queue = afterCombat
	afterCombat = {}
	for i = 1, #queue do
		ns.SafeCall(queue[i])
	end
end)
