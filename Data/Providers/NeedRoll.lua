-- Provider: NeedRoll (GPL-3.0). Public API only: its documented global functions open NeedRoll on a page
-- (NeedRoll_ShowLoot(instance, boss), NeedRoll_ShowMap(instance, boss); names in English or the client's language,
-- true when it opened). Its data tables (boss, rare and entrance spots, loot) live on its private namespace, which it
-- does not publish, so they cannot be read: this adapter offers "open in NeedRoll" links and nothing else.

local _, ns = ...
local Providers = ns.Providers

local A = {
	id = "needRoll",
	addon = "NeedRoll",
	title = "NeedRoll",
	internals = false,
	provides = { "links" },
}

function A.Detect()
	local loot = rawget(_G, "NeedRoll_ShowLoot")
	if type(loot) ~= "function" then
		return nil
	end
	return { showLoot = loot, showMap = rawget(_G, "NeedRoll_ShowMap") }
end

local function names(plan, enc)
	local inst = ns.Names.Instance(plan.instance)
	if inst == "" then
		inst = plan.instance.name
	end
	local boss = enc and (enc.name ~= "" and enc.name or ns.Names.Encounter(enc)) or nil
	return inst, boss
end

-- Open NeedRoll's loot page for a boss (or the instance). Returns true when it opened.
function A.OpenLoot(root, plan, enc)
	local inst, boss = names(plan, enc)
	return root.showLoot(inst, boss) == true
end

function A.OpenMap(root, plan, enc)
	if type(root.showMap) ~= "function" then
		return false
	end
	local inst, boss = names(plan, enc)
	return root.showMap(inst, boss) == true
end

function A.Counts()
	return { links = 1 }
end

Providers.Register(A)
