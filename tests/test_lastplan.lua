-- An instance remembers the plan last chosen there (ui.lastPlans, DB.RememberPlan): coming back to it shows that plan,
-- not always the newest; a deleted or foreign plan is not remembered; recommended plans count.
local T = ...
local ns, mock = T.ns, T.mock

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

local function entryOf(mapID, name)
	return { key = "map:" .. mapID, name = name, kind = "dungeon", uiMapID = mapID }
end

local function addPlan(entry, name, updated)
	local plan = ns.Plan.New({
		name = name,
		instance = { name = entry.name, kind = "dungeon", uiMapID = entry.uiMapID },
	})
	plan.updated = updated
	ns.DB.AddPlan(plan)
	return plan
end

T.case("Last plan per instance: A, B, A brings back the plan chosen in A, not the newest", function()
	boot()
	local A, B = entryOf(88101, "Remember Alpha"), entryOf(88102, "Remember Beta")
	local a1, a2 = addPlan(A, "Alpha old", 1000), addPlan(A, "Alpha new", 2000)
	local b1 = addPlan(B, "Beta only", 1500)
	-- First visit, nothing chosen yet: the newest own plan.
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a2.id, "no choice yet: the newest")
	-- Choose the older one in A (the plan picker), go to B and back.
	ns.UI.SelectPlan(a1.id, true)
	ns.UI.OpenInstance(B)
	T.eq(ns.db.ui.selectedPlan, b1.id, "B shows its own plan")
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a1.id, "back in A: the plan chosen there")
	T.eq(ns.db.ui.lastPlans[A.key], a1.id)
	T.eq(ns.db.ui.lastPlans[B.key], b1.id)
	-- Choosing again updates it.
	ns.UI.SelectPlan(a2.id, true)
	ns.UI.OpenInstance(B)
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a2.id, "the newest choice wins")
	-- A copy that becomes active is the one remembered.
	local copy = ns.UI.CopyPlan(ns.DB.GetPlan(a1.id))
	ns.UI.OpenInstance(B)
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, copy.id, "a new copy is remembered once it is active")
end)

T.case("Last plan per instance: a deleted plan is forgotten, a plan of another instance is ignored", function()
	boot()
	local A, B = entryOf(88111, "Forget Alpha"), entryOf(88112, "Forget Beta")
	local a1, a2 = addPlan(A, "Alpha old", 1000), addPlan(A, "Alpha new", 2000)
	local b1 = addPlan(B, "Beta only", 1500)
	ns.UI.SelectPlan(a1.id, true)
	ns.UI.OpenInstance(B)
	T.ok(ns.DB.DeletePlan(a1.id), "deleted")
	T.eq(ns.db.ui.lastPlans[A.key], nil, "its id is cleared")
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a2.id, "falls back to the newest")
	-- A stale id (hand-edited or from another profile) that names a plan of another instance is not used.
	ns.db.ui.lastPlans[A.key] = b1.id
	ns.UI.OpenInstance(B)
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a2.id, "a foreign plan is not taken")
	ns.db.ui.lastPlans[A.key] = "p-gone"
	ns.UI.OpenInstance(B)
	ns.UI.OpenInstance(A)
	T.eq(ns.db.ui.selectedPlan, a2.id, "an id that no longer exists is not taken")
end)

T.case("Last plan per instance: a recommended plan is remembered over a newer own plan", function()
	boot()
	local rec = ns.DB.GetPlan("b:hall-of-thanes")
	T.ok(rec, "the recommended plan exists")
	local H = ns.UI.EntryForPlan(rec)
	local other = entryOf(88121, "Remember Gamma")
	local mine = addPlan(other, "Gamma plan", 1000)
	local copy = ns.Plan.Duplicate(rec, "My Hall copy")
	copy.updated = 5000
	ns.DB.AddPlan(copy)
	ns.UI.SelectPlan(rec.id, true)
	T.eq(ns.db.ui.lastPlans[H.key], rec.id, "remembered under the instance's key")
	ns.UI.OpenInstance(other)
	T.eq(ns.db.ui.selectedPlan, mine.id)
	ns.UI.OpenInstance(H)
	T.eq(ns.db.ui.selectedPlan, rec.id, "the recommended plan, not the newer copy")
	-- Without a choice the rule is unchanged: the newest own plan.
	ns.db.ui.lastPlans[H.key] = nil
	ns.UI.OpenInstance(other)
	ns.UI.OpenInstance(H)
	T.eq(ns.db.ui.selectedPlan, copy.id, "no memory: the newest own plan")
end)

-- Header, list and tooltip fixes from the same round ------------------------------------------------------------------

T.case("Plan list: sized to its rows, no scroll bar while they all fit; scrolls past 12 rows", function()
	boot()
	local W = ns.Widgets
	local owner = CreateFrame("Button", nil, UIParent)
	owner:SetSize(200, 24)
	owner:SetPoint("TOPLEFT", 100, -100)
	local function open(n)
		local rows = {}
		for i = 1, n do
			rows[i] = { kind = "item", text = "Plan " .. i, value = i }
		end
		return W.OpenPopup(owner, {
			-- Its own row style: rows are pooled per style, and these rows have no label for W.Dropdown to fill.
			style = "test-scroll",
			rowHeight = ns.Style.SIZE.control,
			maxHeight = 12 * ns.Style.SIZE.control + 2 * ns.Style.SPACE.sm,
			rows = function()
				return rows
			end,
			createItem = function() end,
			updateItem = function() end,
			onChoose = function() end,
		})
	end
	local p = open(3)
	T.eq(p:MaxScroll(), 0, "three rows fit")
	T.ok(not p.thumb:IsShown(), "no scroll bar")
	T.ok(p.view:GetHeight() >= 3 * ns.Style.SIZE.control, "every row shown")
	W.ClosePopup()
	p = open(30)
	T.ok(p:MaxScroll() > 0, "a long list scrolls")
	T.ok(p.view:GetHeight() <= 12 * ns.Style.SIZE.control + 1, "at most 12 rows tall")
	W.ClosePopup()
end)

T.case("Run mode: title inside the title bar, planner button beside the close button, no empty row", function()
	boot()
	ns.RunMode.Show()
	local f = _G.DungeonPlannerRunFrame
	T.ok(f, "run mode built")
	T.eq(f.open:GetParent(), f, "the planner button is on the window, not on a row under the title bar")
	local _, rel = f.open:GetPoint(1)
	T.eq(rel, f.close, "left of the close button")
	T.eq(f.bar:GetHeight(), 0, "no row under the title bar")
	local _, _, _, x = f.title:GetPoint(1)
	T.ok(x and x > 6, "the title keeps clear of the window's left edge")
	ns.RunMode.Hide()
end)

T.case("Map tooltips go beside their pin, to its left when the screen has no room on the right", function()
	boot()
	local W = ns.Widgets
	local tt = W.Tip()
	local near = CreateFrame("Button", nil, UIParent)
	near:SetSize(20, 20)
	near.GetRight = function()
		return 20
	end
	W.TipBeside(tt, near)
	local point, _, relPoint = tt:GetPoint(1)
	T.eq(point .. relPoint, "TOPLEFTTOPRIGHT", "room on the right: beside it")
	local far = CreateFrame("Button", nil, UIParent)
	far:SetSize(20, 20)
	far.GetRight = function()
		return UIParent:GetRight() - 10 -- the mock does not lay out anchors: say where it is
	end
	W.TipBeside(tt, far)
	point, _, relPoint = tt:GetPoint(1)
	T.eq(point .. relPoint, "TOPRIGHTTOPLEFT", "no room: to its left")
end)
