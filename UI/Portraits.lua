-- Boss portraits ahead of time. A creature's portrait loads off screen for a few seconds before it can show
-- (UI/Art.lua), so a plan's bosses start loading as soon as it is clear they will be seen: when the plan is chosen
-- (before its page draws its steps, map pins and Bosses rows), when an instance is picked on the home table, when
-- /dp shots starts its walk, and when the player enters an instance (the plan that instance opens with). Each creature
-- loads once per session; nothing runs while there is nothing new to load.

local _, ns = ...
local Portraits = ns:NewModule("Portraits")
local UI = ns.UI

-- Start loading the portraits of `plan`'s bosses. Returns how many started.
function UI.PrefetchPortraits(plan)
	if type(plan) ~= "table" then
		return 0
	end
	return ns.Art.PrefetchPortraits(ns.Journal.PlanPortraits(plan))
end

-- The plan an instance opens with (UI.OpenInstance): the one last chosen there, else the newest own plan, else the
-- first recommended one.
function UI.DefaultPlanFor(entry)
	if type(entry) ~= "table" then
		return nil
	end
	return ns.DB.RememberedPlan(entry) or ns.DB.PlansFor(entry)[1] or ns.Bundled.ForInstance(entry)[1]
end

-- Where the player is, as an instance entry ({ key, name, kind, ejInstanceID?, uiMapID? }), for "Current location".
function UI.CurrentEntry()
	local cur = ns.Instances.Current()
	local entry = cur.ejInstanceID and ns.Instances.Get("ej:" .. cur.ejInstanceID)
	if entry then
		return entry, cur
	end
	local info = { name = cur.name or "", kind = cur.kind, ejInstanceID = cur.ejInstanceID, uiMapID = cur.uiMapID }
	return { key = ns.DB.InstanceKey(info), name = info.name, kind = info.kind, ejInstanceID = info.ejInstanceID,
		uiMapID = info.uiMapID }, cur
end

-- Entering a dungeon or raid: the plan it would open with starts loading its portraits (outside instances, nothing).
function Portraits.OnZone()
	local entry, cur = UI.CurrentEntry()
	if cur and cur.inInstance and entry.name ~= "" then
		UI.PrefetchPortraits(UI.DefaultPlanFor(entry))
	end
end

function Portraits.Init()
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		ns.SafeCall(Portraits.OnZone)
	end)
end
