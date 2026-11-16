-- Writes community-plans/examples/template-five-player-run.dpplan: a TEMPLATE plan with no game data (no boss names,
-- no IDs, no map), showing the file format. Regenerate after a format change:  lua tools/make_example.lua

package.path = "./tools/?.lua;" .. package.path
local offline = require("offline")
local ns = offline.Load()
local Plan = ns.Plan

local plan = Plan.New({ name = "Template: five-player run", author = "Dungeon Planner", difficulty = "Any" })
plan.instance = { name = "", kind = "dungeon" }
plan.description = "A starting structure for a 5-player dungeon run. Import it, then pick the instance's map and add "
	.. "its bosses from the Adventure Guide (Encounters > Add from journal)."
plan.created, plan.updated = 0, 0
plan.id = "template5"
Plan.AddObjective(plan, "Everyone has repairs, food and reagents")
Plan.AddObjective(plan, "Roles and marks agreed")
Plan.AddObjective(plan, "Route and pulls agreed")
Plan.AddAssignment(plan, "role:TANK", "Pull and mark targets: skull first, then cross")
Plan.AddAssignment(plan, "role:HEALER", "Call out low mana before the next pull")
Plan.AddAssignment(plan, "role:DAMAGER", "Interrupt casters; stay out of patrols' path")
local p1 = Plan.AddPull(plan, "Opening pack")
p1.note = "Wait for the patrol to walk away."
local p2 = Plan.AddPull(plan, "Second pack")
p2.note = "Crowd-control the caster."
local m1 = Plan.AddMarker(plan, 1, 0.2, 0.7, "entrance", "Entrance")
local m2 = Plan.AddMarker(plan, 1, 0.35, 0.6, "pack", "Pack")
local m3 = Plan.AddMarker(plan, 1, 0.5, 0.45, "pack", "Pack")
Plan.UpdateMarker(plan, m2.id, { pull = p1.id })
Plan.UpdateMarker(plan, m3.id, { pull = p2.id })
local route = Plan.AddRoute(plan, 1, "Main route", 1)
for _, m in ipairs({ m1, m2, m3 }) do
	Plan.AddRoutePoint(plan, route.id, m.x, m.y)
end
plan.notes = "Template. Replace the markers after choosing the dungeon's map."

local text = assert(ns.Codec.ExportPlan(plan))
local out = assert(io.open("community-plans/examples/template-five-player-run.dpplan", "wb"))
out:write(table.concat({
	"# Dungeon Planner community plan (format: docs/COMMUNITY-PLANS.md)",
	"title: " .. plan.name,
	"instance: any five-player dungeon (template)",
	"author: Dungeon Planner",
	"client: forever 16001",
	"license: CC0-1.0",
	"tags: template, example",
	"description: " .. plan.description,
	"---",
	text,
	"",
}, "\n"))
out:close()
print("wrote community-plans/examples/template-five-player-run.dpplan (" .. #text .. " chars)")
