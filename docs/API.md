# Public API

For other addons and WeakAuras. The global `DungeonPlanner` holds one field, `API`. Everything else is private.

```lua
local DP = DungeonPlanner and DungeonPlanner.API
if DP and DP.major == 1 then
  local plan = DP.GetActivePlan()
end
```

`API.major` changes only when something is removed or changes meaning; `API.version` goes up when something is added.
Every getter returns a **copy**; changing it changes nothing in Dungeon Planner.

## Functions (major 1, version 1)

| Function | Returns |
|---|---|
| `GetActivePlan()` | Summary of the plan open in the window, or nil: `{ id, name, instance, ejInstanceID, uiMapID, difficulty, author, pulls, encounters, updated }` (`instance` is the display name in the reader's language) |
| `GetPlans([ejInstanceID])` | List of summaries, newest first, optionally for one journal instance |
| `GetPlanCopy(planId)` | Deep copy of a whole plan (format: docs/SHARING-FORMAT.md, "Plan") |
| `GetCurrentPull()` | `{ index, name, note, markers }` of the current pull of the active plan, or nil |
| `GetAssignmentLines([dungeonEncounterID])` | Assignments of the active plan as plain lines ("Name: task"), optionally for one encounter (the `ENCOUNTER_START` ID) |
| `Open([tab])` | Opens the window, optionally on a section of the active plan's page: `"map"`, `"plan"`, `"encounters"` (Bosses), `"pulls"`, `"assignments"`, `"gear"` or `"share"` (`"notes"` and `"progress"` open `"plan"`) |
| `ImportString(text)` | Imports an export string as new plan(s); returns `ok, message` |
| `GetFrames()` | `{ main = DungeonPlannerMainFrame, dialog = DungeonPlannerDialog }` for skin addons (nil until first opened) |

## Events (CallbackHandler-1.0)

```lua
DungeonPlanner.API.RegisterCallback(myAddon, "DUNGEONPLANNER_PULL_ADVANCED", function(event, planId, index, name) end)
DungeonPlanner.API.UnregisterCallback(myAddon, "DUNGEONPLANNER_PULL_ADVANCED")
```

| Event | Arguments | When |
|---|---|---|
| `DUNGEONPLANNER_PLAN_CHANGED` | `planId` | A plan was edited, added, imported or deleted |
| `DUNGEONPLANNER_ACTIVE_PLAN` | `planId` or nil | Another plan was selected in the window |
| `DUNGEONPLANNER_PULL_ADVANCED` | `planId, pullIndex, pullName` | Next/previous pull (key binding, `/dp next`, minimap menu) |
| `DUNGEONPLANNER_BOSS_KILLED` | `encounterID, name, planId` | A boss died (ENCOUNTER_END, BOSS_KILL, or DBM/BigWigs); `planId` is a plan containing that boss, or nil |
| `DUNGEONPLANNER_STEP` | `planId, stepIndex, stepTitle` | Run mode moved to another step of the plan (Prev / Next, the pull key bindings while run mode is open) |

Callbacks run inside Dungeon Planner's event handling; keep them short and do not raise.

## Other globals (required by the game)

| Name | Why |
|---|---|
| `DungeonPlannerMainFrame`, `DungeonPlannerDialog` | `UISpecialFrames` (Escape closes them) and skin addons |
| `DungeonPlannerRunFrame`, `DungeonPlannerPopup` | The run mode window (its position is saved) and the dropdown list |
| `DungeonPlannerNotesFrame` | The Notes window (raid pages; its position and size are saved) |
| `DungeonPlannerTravelFrame` | The Getting there window (`UISpecialFrames`: Escape closes it; its position and size are saved) |
| Parts the game's window template names after its window (for example `DungeonPlannerMainFrameInset`) | Created by `ButtonFrameTemplate` itself where its parts carry `$parent` names; Dungeon Planner neither reads nor writes them |
| `DungeonPlannerHome`, `DungeonPlannerInstancePage`, `DungeonPlannerInstanceHeader`, `DungeonPlannerSearchBox`, `DungeonPlannerMapSection`, `DungeonPlannerPlanSection`, `DungeonPlannerPrepSection` | Stable names of the window's parts, for skin addons (created on first open) |
| `DungeonPlanner_Binding(action)` | Called by `Bindings.xml` |
| `DungeonPlanner_OnAddonCompartmentClick` | The TOC's `AddonCompartmentFunc` |
| `BINDING_HEADER_DUNGEONPLANNER`, `BINDING_NAME_DUNGEONPLANNER_*` | Key Bindings UI labels |
| `DungeonPlannerFont_caption`, `_body`, `_title`, `_page`, `_huge`, `_mono`, `_number`, `_label`, `_tab`, `_tabHighlight` | Font objects (`CreateFont` needs names) |
| `DungeonPlannerFont_face1`, `_face2`, `_face3` | One font object per Polish face of the chain, for the font test and its probe (`UI/Fonts.lua`) |
| `DungeonPlannerTooltip` | Our own tooltip (GameTooltipTemplate), so its lines use our fonts without changing the shared GameTooltip |
| `DungeonPlannerDB` | SavedVariables (AceDB) |

## Other addons' frames read

Dungeon Planner defines no global for these; it only reads them, guarded (docs/COMPATIBILITY.md section 5).

| Name | Addon | Why |
|---|---|---|
| `OpenMapDungeonView` | OpenMap (its private dungeon view, 0.8.12) | The experimental plan overlay (`UI/OpenMapOverlay.lua`, off by default): one frame of ours on its `page`, and `HookScript` on its own frames (`OnShow`, `OnHide`, the page's `OnSizeChanged`, the floor buttons' `OnClick`). Its fields `page`, `floor`, `floors`, `inst`, `source`, `prev`, `next`, `floorButton`, `list.rows`, `side.pool.thumb` and `bossPins` are read with shape checks and never written |
