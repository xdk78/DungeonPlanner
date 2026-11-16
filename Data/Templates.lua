-- Plan templates: starting structure for a new plan. TEMPLATES, NOT GAME DATA. They contain no boss names, item IDs,
-- NPC IDs or map IDs, only generic headings the planner fills in. Real bosses come from the journal at runtime
-- (Data/Instances.lua); real strategies from players and the community repository (community-plans/).

local _, ns = ...
local Templates = ns:NewModule("Templates")
local L = ns.L

-- Each template: id, title (localized at use), apply(plan).
Templates.list = {
	{
		id = "blank",
		title = "Blank plan",
		apply = function() end,
	},
	{
		id = "dungeon",
		title = "Dungeon run (5 players)",
		apply = function(plan)
			ns.Plan.AddObjective(plan, L["Everyone has repairs, food and reagents"])
			ns.Plan.AddObjective(plan, L["Roles and marks agreed"])
			ns.Plan.AddObjective(plan, L["Route and pulls agreed"])
			ns.Plan.AddAssignment(plan, "role:TANK", L["Pull and mark targets"])
			ns.Plan.AddAssignment(plan, "role:HEALER", L["Call out low mana"])
			ns.Plan.AddAssignment(plan, "role:DAMAGER", L["Kill order: skull, then cross"])
		end,
	},
	{
		id = "raid",
		title = "Raid night",
		apply = function(plan)
			ns.Plan.AddObjective(plan, L["Consumables and resistances checked"])
			ns.Plan.AddObjective(plan, L["Groups and assignments posted"])
			ns.Plan.AddObjective(plan, L["Loot rules announced"])
			ns.Plan.AddAssignment(plan, "role:TANK", L["Main tank / off tank swap"])
			ns.Plan.AddAssignment(plan, "role:HEALER", L["Tank healing and raid healing split"])
			ns.Plan.AddAssignment(plan, "all", L["Spread for positioning marks"])
		end,
	},
}

function Templates.Get(id)
	for _, t in ipairs(Templates.list) do
		if t.id == id then
			return t
		end
	end
	return Templates.list[1]
end

-- Generic phase names offered when adding a phase.
Templates.PHASES = { "Phase 1", "Phase 2", "Phase 3", "Intermission", "Burn" }

-- Encounters from the journal, as plan encounters (names and IDs from the client, at runtime).
function Templates.AddJournalEncounters(plan, ejInstanceID)
	local added = 0
	for _, enc in ipairs(ns.Instances.GetEncounters(ejInstanceID)) do
		local exists = false
		for _, have in ipairs(plan.encounters) do
			if (enc.ejEncounterID and have.ejEncounterID == enc.ejEncounterID) or have.name == enc.name then
				exists = true
				break
			end
		end
		if not exists and ns.Plan.AddEncounter(plan, enc) then
			added = added + 1
		end
	end
	return added
end
