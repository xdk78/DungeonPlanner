-- Provider: NeedRoll (GPL-3.0). Public API only: its documented global functions open NeedRoll on a page
-- (NeedRoll_ShowLoot(instance, boss), NeedRoll_ShowMap(instance, boss); names in English or the client's language,
-- true when it opened). Its data tables (boss, rare and entrance spots, loot) live on its private namespace, which it
-- does not publish, so they cannot be read: this adapter offers "open in NeedRoll" links and nothing else.
-- The instance goes by its English name first (Instances.CanonicalName: the same for a plan saved in any client
-- language), then by the name the client shows, then by the stored one, until NeedRoll says it opened.

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

-- The instance's names to try, each once, in order; and the boss's name.
local function names(plan, enc)
	local list = {}
	local function add(name)
		if type(name) == "string" and name ~= "" and not ns.Util.IndexOf(list, name) then
			list[#list + 1] = name
		end
	end
	add(ns.Instances.CanonicalName(plan))
	add(ns.Names.Instance(plan.instance))
	add(plan.instance.name)
	local boss = enc and (enc.name ~= "" and enc.name or ns.Names.Encounter(enc)) or nil
	return list, boss
end

local function open(fn, plan, enc)
	local list, boss = names(plan, enc)
	for _, inst in ipairs(list) do
		if fn(inst, boss) == true then
			return true
		end
	end
	return false
end

-- Open NeedRoll's loot page for a boss (or the instance). Returns true when it opened.
function A.OpenLoot(root, plan, enc)
	return open(root.showLoot, plan, enc)
end

function A.OpenMap(root, plan, enc)
	if type(root.showMap) ~= "function" then
		return false
	end
	return open(root.showMap, plan, enc)
end

function A.Counts()
	return { links = 1 }
end

Providers.Register(A)
