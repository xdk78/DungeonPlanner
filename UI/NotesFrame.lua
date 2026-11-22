-- The Notes window: a small movable window that shows a raid assignment page (Model/Pages.lua) with its keywords
-- expanded: raid target icons, role and class icons, the plan's raid groups, names in class colour, the player's own
-- lines marked. It shows the pages received from the group's leader (newest first), then the selected plan's pages;
-- the arrows page through them.
--
-- When a boss's encounter starts (ENCOUNTER_START, Verified), the page for that boss (received first, else the plan's)
-- is chosen and, with "Show on the boss pull" on, the window opens; ENCOUNTER_END closes it again unless the player had
-- opened it. "Hide in combat" hides it while in combat. The rules are Pages.ViewStep's state machine.
--
-- Also here: what the UI passes to the pure expansion (class tokens, colours and icons from the client, guarded),
-- sending a page to the group (Comm.SendPage) and posting it to group chat (ChatThrottleLib).
--
-- A plain frame (no secure template): showing, hiding and updating it is allowed in combat. Built on first show; idle
-- it costs nothing (event handlers only). Its position and size are saved (ui.notes).

local _, ns = ...
local NotesFrame = ns:NewModule("NotesFrame")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP = S.SPACE
local Pages, Util = ns.Pages, ns.Util

local MIN_W, MIN_H = 220, 150
local PAGE_BUTTON = 32 -- the page arrows' size
local CHAT_LINES, CHAT_BYTES = 20, 250

local frame
local view = Pages.NewView()
local entries, index = {}, 1 -- what the arrows page through, and the one shown
local current -- the entry shown: { page, from?, plan? }

local function saved()
	ns.db.ui.notes = type(ns.db.ui.notes) == "table" and ns.db.ui.notes or {}
	return ns.db.ui.notes
end

local function settings()
	return ns.db.settings.notes
end

-- The client's data for the expansion ----------------------------------------------------------------------------------

local classes -- [lower-case token or class name] = TOKEN, read once from the client
local function classTable()
	if classes then
		return classes
	end
	classes = {}
	local count = GetNumClasses and select(2, pcall(GetNumClasses)) or 0
	for i = 1, (Util.IsInteger(count) and count or 0) do
		local ok, name, token = pcall(GetClassInfo, i)
		name, token = ok and Util.Plain(name), ok and Util.Plain(token)
		if type(token) == "string" and token:match("^%u+$") then
			classes[token:lower()] = token
			if type(name) == "string" and name ~= "" then
				classes[name:lower()] = token
			end
		end
	end
	return classes
end

local function className(token)
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	if type(names) == "table" and type(names[token]) == "string" then
		return names[token]
	end
	for word, t in pairs(classTable()) do
		if t == token and word ~= token:lower() then
			return word
		end
	end
	return token:sub(1, 1) .. token:sub(2):lower()
end

-- "ffc79c6e" for a class token, from the client (RAID_CLASS_COLORS), or nil.
local function classHex(token)
	local colors = rawget(_G, "RAID_CLASS_COLORS")
	local c = type(colors) == "table" and colors[token]
	if type(c) ~= "table" then
		return nil
	end
	if type(c.colorStr) == "string" and c.colorStr:match("^%x%x%x%x%x%x%x%x$") then
		return c.colorStr
	end
	if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
		return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
	end
	return nil
end

local function classIcon(token)
	local coords = rawget(_G, "CLASS_ICON_TCOORDS")
	local c = type(coords) == "table" and coords[token]
	if type(c) ~= "table" or type(c[1]) ~= "number" then
		return nil
	end
	return string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:0:0:0:0:256:256:%d:%d:%d:%d|t",
		c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- The group finder's classic role sheet (64 x 16: damage, tank, healer at 16, 32 and 48 px), as UI/Art.lua cuts it.
local ROLE_X = { DAMAGER = 16, TANK = 32, HEALER = 48 }
local function roleIcon(role)
	local x = ROLE_X[role]
	return x and string.format("|TInterface\\LFGFrame\\LFGRole:0:0:0:0:64:16:%d:%d:0:16|t", x, x + 16) or role
end

local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

-- Class tokens of the group's members by name (plain values only).
local function rosterClasses()
	local out = {}
	for _, unit in ipairs(ns.Comm.GroupUnits()) do
		local okName, name = pcall(UnitName, unit)
		name = okName and Util.ShortName(Util.Plain(name)) or nil
		if name then
			local ok, _, token = pcall(rawget(_G, "UnitClass") or error, unit)
			token = ok and Util.Plain(token) or nil
			if type(token) == "string" then
				out[name] = token
			end
		end
	end
	return out
end

-- The expansion's environment (Pages.Expand) for the player's client. groups = the plan's raid groups, or nil.
function NotesFrame.Env(groups)
	local byName = rosterClasses()
	local me = UnitName and Util.ShortName(Util.Plain((UnitName("player"))))
	local own = "|cffffd100> |r" -- the game's gold
	return {
		groups = groups,
		me = me,
		own = own,
		classes = classTable(),
		classOf = function(name)
			return byName[name]
		end,
		colorName = function(name, token)
			local hex = classHex(token)
			return hex and ("|c" .. hex .. name .. "|r") or name
		end,
		raidIcon = function(n)
			return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":0|t"
		end,
		roleIcon = roleIcon,
		roleName = function(role)
			return L[ROLE_TEXT[role] or "Damage"]
		end,
		classIcon = classIcon,
		className = className,
		groupName = function(g)
			return string.format(L["Group %s"], g)
		end,
	}
end

-- {group N} written out as the plan's names, for pages that leave the plan (sent, posted): the receiver has no plan.
function NotesFrame.ResolveGroups(text, groups)
	return (tostring(text or ""):gsub("{([^{}]*)}", function(inner)
		local kind, g = Pages.Keyword(inner)
		local members = kind == "group" and groups and groups[g]
		if members and #members > 0 then
			return table.concat(members, ", ")
		end
		return nil
	end))
end

-- What a page sends: { title, text (groups written out), boss, enc, plan }.
function NotesFrame.Payload(plan, page)
	local enc = page.encounter and Util.FindById(plan.encounters, page.encounter)
	local id = enc and ns.Journal.GameIdOf(plan)(enc)
	return {
		title = page.title,
		text = NotesFrame.ResolveGroups(page.text, plan.groups),
		boss = enc and ns.Names.Encounter(enc) or nil,
		enc = id,
		plan = plan.name,
	}
end

-- Send a page to the group (leader or raid assistant). Prints what happened.
function NotesFrame.Send(plan, page)
	local ok, info = ns.Comm.SendPage(NotesFrame.Payload(plan, page))
	if not ok then
		ns:Print(info)
		return false
	end
	ns:Print(info and string.format(L["Page \"%s\" will be sent when the boss fight's message lock ends."], page.title)
		or string.format(L["Page \"%s\" sent to your group."], page.title))
	return true
end

-- Post a page to group chat, one line at a time (ChatThrottleLib paces them), out of combat and outside a message
-- lock. Raid icons go as {rt1}..{rt8}, which the chat draws; roles and classes as words; names plain.
function NotesFrame.PostToChat(plan, page)
	local channel = ns.Comm.GroupChannel()
	if not channel then
		ns:Print(L["You are not in a group."])
		return false
	end
	local text = page.text
	if plan then
		text = NotesFrame.ResolveGroups(text, plan.groups)
	end
	local lines = Pages.ChatLines({ title = page.title, text = text }, NotesFrame.Env(plan and plan.groups), CHAT_BYTES,
		CHAT_LINES)
	if #lines == 0 then
		ns:Print(L["Nothing to post."])
		return false
	end
	ns:RunOutOfCombat(function()
		if ns.Comm.IsLockedDown() then
			ns:Print(L["Chat is locked right now (boss fight). Try again after it."])
			return
		end
		local ctl = rawget(_G, "ChatThrottleLib")
		for i, line in ipairs(lines) do
			if ctl and ctl.SendChatMessage then
				pcall(ctl.SendChatMessage, ctl, "NORMAL", ns.prefix, line, channel)
			elseif SendChatMessage and C_Timer then
				C_Timer.After((i - 1) * 0.4, function()
					if not (InCombatLockdown and InCombatLockdown()) then
						pcall(SendChatMessage, line, channel)
					end
				end)
			end
		end
	end)
	return true
end

-- What the window pages through ---------------------------------------------------------------------------------------

local function selectedPlan()
	return ns.DB.GetPlan(ns.db.ui.selectedPlan)
end

-- Received pages (newest first), then the selected plan's pages.
function NotesFrame.Entries()
	local out = {}
	local store = ns.Comm.NotesStore()
	for i = #(store and store.received or {}), 1, -1 do
		out[#out + 1] = { page = store.received[i], from = store.received[i].from }
	end
	local plan = selectedPlan()
	for _, page in ipairs(Pages.List(plan)) do
		out[#out + 1] = { page = page, plan = plan }
	end
	return out
end

local function findEntry(list, page)
	for i, e in ipairs(list) do
		if e.page == page then
			return i
		end
	end
	return nil
end

-- The window ---------------------------------------------------------------------------------------------------------------

local function build()
	-- Escape must not close it mid-fight (noEscape).
	local f = W.Window("DungeonPlannerNotesFrame", L["Notes"], saved(), MIN_W, MIN_H, { compact = true, noEscape = true })
	f:SetFrameStrata("MEDIUM")
	if not (type(saved().point) == "table" and saved().point[1]) then
		f:ClearAllPoints()
		f:SetPoint("LEFT", UIParent, "LEFT", 80, 60)
	end
	f:SetScale(ns.db.settings.scale or 1)
	f.title:SetFontObject(S.fonts.body)
	f.close:SetScript("OnClick", function()
		NotesFrame.Close()
	end)

	local ins = f.insets
	local inner = CreateFrame("Frame", nil, f)
	inner:SetPoint("TOPLEFT", ins.left + SP.md, -(ins.top + SP.sm))
	inner:SetPoint("BOTTOMRIGHT", -(ins.right + SP.sm), ins.bottom + SP.sm)
	f.inner = inner

	f.pageTitle = W.Text(inner, "title", "gold")
	f.pageTitle:SetPoint("TOPLEFT")
	f.pageTitle:SetPoint("RIGHT", -SP.sm, 0)
	f.source = W.Text(inner, "caption", "muted")
	f.source:SetPoint("TOPLEFT", f.pageTitle, "BOTTOMLEFT", 0, -SP.xxs)
	f.source:SetPoint("RIGHT", -SP.sm, 0)

	-- The game's page arrows (the spell book's, 32 px as in the game's PagingControls templates), the page label between
	-- them ("1 of 3", or "No pages"), as wide as it is.
	f.prev = W.PageButton(inner, "prev", L["Previous page"], function()
		NotesFrame.Step(-1)
	end, PAGE_BUTTON)
	f.prev:SetPoint("BOTTOMLEFT", -SP.xs, -SP.xs)
	f.counter = W.Text(inner, "caption", "ink")
	f.counter:SetPoint("LEFT", f.prev, "RIGHT", SP.xxs, 0)
	f.counter:SetJustifyH("CENTER")
	f.counter:SetWidth(64)
	f.next = W.PageButton(inner, "next", L["Next page"], function()
		NotesFrame.Step(1)
	end, PAGE_BUTTON)
	f.next:SetPoint("LEFT", f.counter, "RIGHT", SP.xxs, 0)

	f.doc = W.Document(inner)
	f.doc:SetPoint("TOPLEFT", f.source, "BOTTOMLEFT", 0, -SP.sm)
	f.doc:SetPoint("BOTTOMRIGHT", 0, PAGE_BUTTON)
	f:Hide()
	frame = f
end

function NotesFrame.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	entries = NotesFrame.Entries()
	local found = current and findEntry(entries, current.page)
	index = found or math.max(1, math.min(index, #entries))
	current = entries[index]
	local doc = frame.doc
	doc:Begin()
	if not current then
		W.FitText(frame.pageTitle, L["No pages"])
		frame.source:SetText("")
		doc:Add("muted", L["Write pages in a plan's Party section (Pages), or wait for your raid leader to send one."])
	else
		local page = current.page
		W.FitText(frame.pageTitle, page.title ~= "" and page.title or L["Page"])
		local src
		if current.from then
			src = string.format(L["From %s"], current.from) .. (page.boss and (" • " .. page.boss) or "")
		elseif current.plan then
			local enc = page.encounter and Util.FindById(current.plan.encounters, page.encounter)
			src = current.plan.name .. (enc and (" • " .. ns.Names.Encounter(enc)) or "")
		end
		W.FitText(frame.source, src or "")
		local text = Pages.Expand(page.text, NotesFrame.Env(current.plan and current.plan.groups))
		doc:Add("text", text ~= "" and text or " ")
	end
	doc:Finish()
	frame.counter:SetText(#entries > 0 and string.format(L["%d of %d"], index, #entries) or L["No pages"])
	frame.counter:SetWidth(math.max(48, math.ceil(frame.counter:GetStringWidth() or 0) + SP.md))
	frame.prev:SetDisabled(index <= 1)
	frame.next:SetDisabled(index >= #entries)
end

function NotesFrame.Step(delta)
	entries = NotesFrame.Entries()
	index = math.max(1, math.min(#entries, index + delta))
	current = entries[index]
	NotesFrame.Refresh()
end

-- Apply the state machine's answer: show or hide the window.
local function apply(visible)
	if visible then
		if not frame then
			build()
		end
		frame:Show()
		NotesFrame.Refresh()
	elseif frame then
		frame:Hide()
	end
end

local function step(event)
	view.hideInCombat = settings().hideInCombat and true or false
	apply(Pages.ViewStep(view, event))
end

-- Open on a page (an entry's page table), or on the current one.
function NotesFrame.Open(page)
	if page then
		entries = NotesFrame.Entries()
		index = findEntry(entries, page) or index
		current = entries[index]
	end
	saved().shown = true
	step({ type = "open" })
end

function NotesFrame.Close()
	saved().shown = false
	step({ type = "close" })
end

function NotesFrame.Toggle()
	step({ type = "toggle" })
	saved().shown = view.shown
end

function NotesFrame.IsShown()
	return frame ~= nil and frame:IsShown()
end

function NotesFrame.ApplyScale()
	if frame then
		frame:SetScale(ns.db.settings.scale or 1)
	end
end

-- A boss pull: the page for it (received first, else the selected plan's), and the window when auto-show is on.
function NotesFrame.OnEncounterStart(encounterID, name)
	encounterID, name = Util.Plain(encounterID), Util.Plain(name)
	encounterID = Util.IsInteger(encounterID) and encounterID or nil
	name = type(name) == "string" and name or nil
	local store = ns.Comm.NotesStore()
	local page = store and Pages.ReceivedFor(store, encounterID, name)
	local plan = selectedPlan()
	if not page and plan then
		page = Pages.ForEncounter(plan, encounterID, name, ns.Journal.GameIdOf(plan), function(enc)
			return ns.Names.Encounter(enc)
		end)
	end
	if page then
		entries = NotesFrame.Entries()
		index = findEntry(entries, page) or index
		current = entries[index]
	end
	step({ type = "encounterStart", page = page ~= nil, autoShow = settings().autoShow })
	return page
end

function NotesFrame.Init()
	view.shown = saved().shown == true
	ns:RegisterEvent("ENCOUNTER_START", function(_, encounterID, name)
		ns.SafeCall(NotesFrame.OnEncounterStart, encounterID, name)
	end)
	ns:RegisterEvent("ENCOUNTER_END", function()
		step({ type = "encounterEnd" })
	end)
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		step({ type = "combat", on = true })
	end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		step({ type = "combat", on = false })
	end)
	ns:On("NOTES_RECEIVED", NotesFrame, function(page)
		NotesFrame.Open(page)
	end)
	ns:On("PLAN_CHANGED", NotesFrame, NotesFrame.Refresh)
	ns:On("PLANS_CHANGED", NotesFrame, NotesFrame.Refresh)
	if view.shown then
		step({ type = "open" })
	end
end
