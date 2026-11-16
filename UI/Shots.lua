-- /dp shots: screenshots of every view of the window, for reviewing the UI without clicking through it (AGENTS.md,
-- "Seeing the UI"). The walking, the screenshots, Escape, the combat stop and the backdrop are LibUIShots-1.0's
-- (Libs/LibUIShots-1.0, from wow-ui-harness); this file only lists Dungeon Planner's steps and puts the window back as
-- it was. The manifest (step names and times, to match the files in the game's Screenshots folder) is printed to chat
-- and saved in DungeonPlannerDB.shots.

local _, ns = ...
local Shots = ns:NewModule("Shots")
local L = ns.L

local KEY = "DungeonPlanner"

-- Representative plans: a Forever dungeon on its drawn map (Santiago Reyes'), a classic dungeon on the game's map tiles, a raid.
local FOREVER, CLASSIC, RAID = "hall-of-thanes", "the-deadmines", "molten-core"

local function lib()
	return LibStub and LibStub("LibUIShots-1.0", true)
end

local function frame()
	return ns.UI.Frame()
end

local function closeExtras()
	if ns.Widgets.ClosePopup then
		ns.Widgets.ClosePopup()
	end
	local dialog = rawget(_G, "DungeonPlannerDialog")
	if dialog and dialog:IsShown() then
		dialog:Hide()
	end
	if ns.RunMode.IsShown() then
		ns.RunMode.Hide()
	end
end

local function bundledID(key)
	return ns.Bundled.PREFIX .. key
end

local function openPlan(key, section)
	closeExtras()
	ns.UI.Show()
	ns.UI.SelectPlan(bundledID(key))
	ns.UI.SelectTab(section)
end

-- The steps, for the plans this client has (a missing one is left out).
function Shots.Steps()
	local steps = {
		{ name = "home: dungeons", setup = function()
			closeExtras()
			ns.UI.Show()
			ns.UI.GoHome("dungeons")
		end },
		{ name = "home: raids", setup = function()
			ns.UI.GoHome("raids")
		end },
		{ name = "home: my plans", setup = function()
			ns.UI.GoHome("plans")
		end },
	}
	local function add(step)
		steps[#steps + 1] = step
	end
	if ns.DB.GetPlan(bundledID(FOREVER)) then
		add({ name = "instance picker (" .. FOREVER .. ")", setup = function()
			openPlan(FOREVER, "map")
			local page = frame() and frame().instancePage
			if page and page.instancePick then
				ns.InstancePicker.Open(page.instancePick, ns.UI.ctx:Instance())
			end
		end, teardown = closeExtras })
		for _, sec in ipairs(ns.UI.SECTIONS) do
			add({ name = "section " .. sec.id .. " (" .. FOREVER .. ")", setup = function()
				openPlan(FOREVER, sec.id)
			end })
		end
		add({ name = "run mode (" .. FOREVER .. ")", setup = function()
			openPlan(FOREVER, "map")
			ns.UI.Toggle() -- run mode is used with the planner closed
			ns.RunMode.Show()
		end, teardown = function()
			ns.RunMode.Hide()
			ns.UI.Show()
		end })
	end
	for _, key in ipairs({ CLASSIC, RAID }) do
		if ns.DB.GetPlan(bundledID(key)) then
			add({ name = "section map (" .. key .. ")", setup = function()
				openPlan(key, "map")
			end })
		end
	end
	if ns.DB.GetPlan(bundledID(RAID)) then
		add({ name = "party: raid pages (" .. RAID .. ")", setup = function()
			ns.db.ui.partyMode = "pages"
			openPlan(RAID, "assignments")
		end, teardown = function()
			ns.db.ui.partyMode = "assignments"
		end })
	end
	add({ name = "notes window", setup = function()
		closeExtras()
		ns.UI.Toggle() -- like run mode, used with the planner closed
		ns.NotesFrame.Open()
	end, teardown = function()
		ns.NotesFrame.Close()
		ns.UI.Show()
	end })
	add({ name = "debug dialog", setup = function()
		closeExtras()
		ns.Slash.Debug()
	end, teardown = closeExtras })
	-- Last: the game's Settings panel stays open (close it with Escape when the walk is over).
	add({ name = "settings", setup = function()
		closeExtras()
		ns.UI.OpenSettings()
	end, delay = 1.5 })
	return steps
end

-- What the walk changes, to put back afterwards.
local saved

local function before()
	local ui = ns.db.ui
	saved = {
		shown = ns.UI.IsShown(),
		view = ui.view,
		homeTab = ui.homeTab,
		tab = ui.tab,
		plan = ui.selectedPlan,
		instance = ui.instance,
	}
end

local function after(manifest)
	manifest.addon = ns.title .. " " .. tostring(ns.version)
	manifest.language = ns.activeLocale
	closeExtras()
	local s = saved
	saved = nil
	if not s then
		return
	end
	ns.UI.SelectPlan(s.plan, true)
	ns.db.ui.tab = s.tab
	ns.db.ui.homeTab = s.homeTab
	ns.db.ui.instance = s.instance
	if s.view == "instance" and s.instance then
		ns.UI.Show(s.tab)
	else
		ns.UI.GoHome(s.homeTab)
	end
	if not s.shown and ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

local function text()
	return {
		started = L["Screenshots: %d steps. Press Escape to stop."],
		step = L["Screenshot %d/%d: %s"],
		done = L["Screenshots done: %d taken. They are in the game's Screenshots folder, in this order:"],
		aborted = L["Screenshots stopped (%s) after %d."],
		combat = L["in combat"],
		escape = L["Escape"],
		failed = L["A step failed: %s"],
		busy = L["already running"],
		noSteps = L["nothing to show"],
		inCombat = L["in combat"],
	}
end

-- /dp shots (and /dp shots stop).
function Shots.Run(arg)
	local Lib = lib()
	if not Lib then
		ns:Print(L["The screenshot library is missing."])
		return
	end
	if arg == "stop" then
		Lib:Stop(KEY, "stopped")
		return
	end
	if InCombatLockdown() then
		ns:Print(L["Screenshots wait until you leave combat."])
		return
	end
	Lib:Register(KEY, Shots.Steps(), {
		store = function()
			return rawget(_G, "DungeonPlannerDB")
		end,
		print = function(msg)
			ns:Print(msg)
		end,
		before = before,
		after = after,
		text = text(),
	})
	local ok, why = Lib:Start(KEY)
	if not ok then
		ns:Print(string.format(L["Screenshots cannot start: %s"], text()[why] or tostring(why)))
	end
end
