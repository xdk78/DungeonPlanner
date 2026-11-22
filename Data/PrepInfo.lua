-- What Prep reads from the game: the character's faction and level, quest state, item counts, the group, and the
-- Questie givers when it is installed. Each call is guarded and every value passes Util.Plain; Model/Prep.lua does the
-- sorting and counting. Read on demand (when the Prep section, run mode's line or the Getting there window draws),
-- never on a timer.
--
--   PrepInfo.Quests(plan, showAll) -> rows, counts      PrepInfo.Keys(plan) -> rows
--   PrepInfo.Group(plan) -> Prep.Group result            PrepInfo.Summary(plan) -> Prep.Summary result
--   PrepInfo.Faction() -> "alliance" | "horde" | nil      PrepInfo.Level() -> n | nil

local _, ns = ...
local PrepInfo = ns:NewModule("PrepInfo")
local Util, Prep = ns.Util, ns.Prep

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Util.Plain(a), Util.Plain(b)
end

function PrepInfo.Faction()
	local f = call(rawget(_G, "UnitFactionGroup"), "player")
	if f == "Alliance" then
		return "alliance"
	elseif f == "Horde" then
		return "horde"
	end
	return nil
end

function PrepInfo.Level()
	local n = call(rawget(_G, "UnitLevel"), "player")
	return Util.IsInteger(n) and n > 0 and n or nil
end

local function questLog()
	return rawget(_G, "C_QuestLog") or {}
end

function PrepInfo.QuestDone(id)
	local v = call(questLog().IsQuestFlaggedCompleted, id)
	if v == nil then
		return nil
	end
	return v == true
end

function PrepInfo.QuestInLog(id)
	local log = questLog()
	if type(log.IsOnQuest) == "function" then
		return call(log.IsOnQuest, id) == true
	end
	local index = call(log.GetLogIndexForQuestID, id)
	return Util.IsInteger(index) and index > 0
end

-- The quest's title in the player's language when the client has it cached.
function PrepInfo.QuestTitle(id)
	local title = call(questLog().GetTitleForQuestID, id)
	if type(title) == "string" and title ~= "" then
		return title
	end
	return nil
end

-- Items carried, in the bank and on the key ring.
function PrepInfo.ItemCount(itemID)
	local item = rawget(_G, "C_Item")
	local n = call(item and item.GetItemCount, itemID, true)
	if n == nil then
		n = call(rawget(_G, "GetItemCount"), itemID, true)
	end
	return Util.IsInteger(n) and n or nil
end

-- Quest givers from Questie (its public data contract) for the plan's quests, or nil without it.
local function givers(quests)
	if not ns.Providers.Get("questie") then
		return nil
	end
	local ids = {}
	for _, q in ipairs(quests) do
		ids[#ids + 1] = q.questID
	end
	local found = ns.Providers.Call("questie", "Givers", ids)
	if type(found) ~= "table" then
		return nil
	end
	-- Zone names in the player's language from the client's area table.
	local mapApi = rawget(_G, "C_Map")
	for _, g in pairs(found) do
		if g.area and mapApi and g.zone == nil then
			local name = call(mapApi.GetAreaInfo, g.area)
			g.zone = type(name) == "string" and name ~= "" and name or nil
		end
	end
	return found
end

function PrepInfo.Env(showAll)
	return {
		faction = PrepInfo.Faction(),
		level = PrepInfo.Level(),
		completed = PrepInfo.QuestDone,
		inLog = PrepInfo.QuestInLog,
		title = PrepInfo.QuestTitle,
		count = PrepInfo.ItemCount,
		showAll = showAll,
	}
end

function PrepInfo.Quests(plan, showAll)
	local quests = ns.BossData.Quests(plan) or {}
	local env = PrepInfo.Env(showAll)
	env.givers = #quests > 0 and givers(quests) or nil
	return Prep.Quests(quests, env)
end

function PrepInfo.Keys(plan)
	return Prep.Keys(ns.BossData.Keys(plan) or {}, PrepInfo.Env())
end

-- The group: the player and party1-4, or raid1-40 in a raid; name, level and the role chosen in the group finder.
function PrepInfo.Members()
	local out = {}
	local function add(unit, isPlayer)
		local exists = isPlayer or call(rawget(_G, "UnitExists"), unit)
		if not exists then
			return
		end
		local name = call(rawget(_G, "UnitName"), unit)
		local level = call(rawget(_G, "UnitLevel"), unit)
		local role = call(rawget(_G, "UnitGroupRolesAssigned"), unit)
		out[#out + 1] = { name = type(name) == "string" and name or "?", level = Util.IsInteger(level) and level or nil,
			role = role, player = isPlayer or nil }
	end
	local inRaid = call(rawget(_G, "IsInRaid")) == true
	if inRaid then
		local n = call(rawget(_G, "GetNumGroupMembers")) or 0
		for i = 1, math.min(40, Util.IsInteger(n) and n or 0) do
			local unit = "raid" .. i
			if call(rawget(_G, "UnitIsUnit"), unit, "player") then
				add(unit, true)
			else
				add(unit)
			end
		end
		if #out == 0 then
			add("player", true)
		end
	else
		add("player", true)
		for i = 1, 4 do
			add("party" .. i)
		end
	end
	return out
end

function PrepInfo.Group(plan)
	local lo, hi = ns.Instances.LevelRange(ns.UI.EntryForPlan(plan))
	return Prep.Group(PrepInfo.Members(), lo, hi, plan.instance and plan.instance.kind), lo, hi
end

-- What the Prep section, run mode's prep line and the Getting there window show changes with these; each registers a
-- watcher (PrepInfo.Watch) and listens for PREP_CHANGED. One PREP_CHANGED goes out a moment after the first of a burst
-- (a bag update fires many times), and only while a watcher says it shows prep.
PrepInfo.EVENTS = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED",
	"GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ROLES_ASSIGNED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }
PrepInfo.DELAY = 0.3
PrepInfo.watchers = {} -- [owner] = function() -> true while it shows prep

local pending = false
function PrepInfo.Changed()
	local wanted = false
	for _, shows in pairs(PrepInfo.watchers) do
		wanted = wanted or shows() == true
	end
	if not wanted or pending then
		return
	end
	pending = true
	local function fire()
		pending = false
		ns:Fire("PREP_CHANGED")
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(PrepInfo.DELAY, fire)
	else
		fire()
	end
end

function PrepInfo.Watch(owner, shows)
	PrepInfo.watchers[owner] = shows
end

function PrepInfo.Init()
	for _, event in ipairs(PrepInfo.EVENTS) do
		ns:RegisterEvent(event, PrepInfo.Changed)
	end
end

function PrepInfo.Summary(plan)
	if not plan then
		return nil
	end
	local _, counts = PrepInfo.Quests(plan, false)
	return Prep.Summary(counts, PrepInfo.Keys(plan))
end
