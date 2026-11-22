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

-- Shortens the add-on path and removes the player's name and realm, so a message can be pasted in public.
function Errors.Clean(text)
	text = tostring(text or ""):gsub("Interface[/\\]AddOns[/\\]", "")
	for _, secret in ipairs({ UnitName and UnitName("player") or false, GetRealmName and GetRealmName() or false }) do
		if type(secret) == "string" and #secret > 2 then
			text = text:gsub(secret:gsub("%p", "%%%0"), "<name>")
		end
	end
	if #text > 400 then
		text = text:sub(1, 400) .. "..."
	end
	return text
end

function Errors.Record(err)
	local message = Errors.Clean(err)
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

function ns.SafeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		pcall(Errors.Record, err)
		local handler = geterrorhandler and geterrorhandler()
		if handler then
			handler(err)
		else
			print("DungeonPlanner error: " .. tostring(err))
		end
	end
	return ok, err
end

-- Internal message bus ------------------------------------------------------------------------------------------------
-- Between our own modules ("PLAN_CHANGED", "STYLE_CHANGED", ...). Synchronous; one failing listener never stops the
-- others. Public events for other addons go through ns.API's CallbackHandler (Core/API.lua).

local listeners = {}

-- For /dp perf (Core/Perf.lua), which wraps handlers only while a probe runs.
function ns.ListenerTable()
	return listeners
end

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
