-- Prep section: what to do before going in. Left, in an inset: the instance's quests to pick up (bundled IDs, names
-- from the client where it has them, the giver and zone from Questie when it is installed), keys and attunements (item
-- counts, quest state) and the group's levels and roles. Right: Getting there (UI/GettingThere.lua) and the plan's
-- prep notes, editable in own plans. The logic is Model/Prep.lua; the game reads are Data/PrepInfo.lua.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Schema = ns.Plan, ns.Schema
local SP = S.SPACE
local GT = ns.GettingThere

local Panel = {}
ns.Panels.prep = Panel

Panel.NOTES_H = 110

-- Words looked up when drawn (the language can change after load).
local STATUS = {
	log = { function() return L["In your log"] end, "ok" },
	available = { function() return L["To pick up"] end, "gold" },
	low = { function() return L["Too low"] end, "warning" },
	done = { function() return L["Done"] end, "muted" },
}
local ROLE = {
	TANK = function() return L["Tank"] end, HEALER = function() return L["Healer"] end,
	DAMAGER = function() return L["Damage"] end, NONE = function() return L["No role"] end,
}

local function icon(itemID)
	local _, _, tex = ns.Names.ItemInfo({ itemID = itemID, label = "" })
	return tex and ("|T" .. tex .. ":14:14:0:0|t ") or ""
end

local function itemName(itemID)
	local name = ns.Names.ItemInfo({ itemID = itemID, label = "" })
	return name
end

-- The quests' lines.
function Panel.QuestLines(rows, counts, questie)
	local out = {}
	local function add(style, text)
		out[#out + 1] = { style, text }
	end
	local todo = counts.available
	add("heading", todo > 0 and string.format(L["Quests to pick up (%d)"], todo) or L["Quests"])
	if counts.total == 0 then
		add("muted", counts.other > 0 and L["Only the other faction has quests here."]
			or L["Dungeon Planner knows no quests for this instance."])
		return out
	end
	local parts = {}
	for _, k in ipairs({ "available", "log", "low", "done" }) do
		if counts[k] > 0 then
			parts[#parts + 1] = string.format("%s %d", STATUS[k][1](), counts[k])
		end
	end
	add("muted", table.concat(parts, "  •  "))
	for _, q in ipairs(rows) do
		local st = STATUS[q.status]
		local head = GT.Color(st[2], st[1]()) .. "  " .. (q.level and ("[" .. q.level .. "] ") or "") .. q.name
		if q.status == "low" and q.req then
			head = head .. "  " .. GT.Color("muted", string.format(L["(from level %d)"], q.req))
		end
		add("text", head)
		local details = {}
		if q.giver then
			local g = q.giver
			local where = g.zone and (g.x and string.format("%s %.1f, %.1f", g.zone, g.x, g.y) or g.zone) or nil
			details[#details + 1] = g.name and (where and string.format(L["%s, %s"], g.name, where) or g.name) or where
		end
		if q.items and #q.items > 0 then
			local names = {}
			for _, id in ipairs(q.items) do
				names[#names + 1] = icon(id) .. itemName(id)
			end
			details[#details + 1] = string.format(L["Bring: %s"], table.concat(names, ", "))
		end
		if #details > 0 then
			add("muted", table.concat(details, "  •  "))
		end
	end
	if not questie then
		add("muted", L["With Questie installed, each quest shows who gives it and where."])
	end
	return out
end

function Panel.KeyLines(rows)
	local out = {}
	if #rows == 0 then
		return out
	end
	out[#out + 1] = { "heading", L["Keys and attunements"] }
	for _, k in ipairs(rows) do
		local state
		if k.have == true then
			state = GT.Color("ok", k.itemID and L["You have it"] or L["Done"])
		elseif k.have == false then
			state = GT.Color(k.required and "warning" or "muted", k.itemID and L["Not with you"] or L["Not done"])
		else
			state = GT.Color("muted", L["Unknown"])
		end
		local name = k.itemID and (icon(k.itemID) .. (ns.Names.Item(k.itemID) or k.name)) or k.name
		local need = k.required and L["Required"] or L["Optional"]
		out[#out + 1] = { "text", state .. "  " .. name .. "  " .. GT.Color("muted", need) }
		local note = k.note or ""
		if not k.forever then
			note = note .. (note ~= "" and "  " or "") .. L["(classic fact; not checked on Forever)"]
		end
		if note ~= "" then
			out[#out + 1] = { "muted", note }
		end
	end
	return out
end

function Panel.GroupLines(group, lo, hi, kind)
	local out = {}
	out[#out + 1] = { "heading", L["Group"] }
	local range = lo and (lo == hi and tostring(lo) or (lo .. "-" .. (hi or lo)))
	if group.size <= 1 then
		out[#out + 1] = { "muted", L["You are not in a group."] }
	end
	local roleParts = {}
	for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
		roleParts[#roleParts + 1] = string.format("%s %d", ROLE[r](), group.roles[r])
	end
	local head = kind == "raid" and string.format(L["Raid: %d players"], group.size)
		or string.format(L["Party: %d of 5"], group.size)
	out[#out + 1] = { "text", head .. "  •  " .. table.concat(roleParts, "  •  ") }
	if group.missing then
		local miss = {}
		for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
			if group.missing[r] > 0 then
				miss[#miss + 1] = group.missing[r] .. " " .. ROLE[r]()
			end
		end
		if #miss > 0 then
			out[#out + 1] = { "text", GT.Color("warning", string.format(L["Still needed: %s"], table.concat(miss, ", "))) }
		end
	end
	for _, m in ipairs(group.members) do
		local lv = m.level and string.format(L["level %d"], m.level) or ""
		if m.fit == "low" then
			lv = GT.Color("warning", lv .. " (" .. string.format(L["below %s"], range) .. ")")
		elseif m.fit == "high" then
			lv = GT.Color("muted", lv)
		end
		out[#out + 1] = { "muted", m.name .. "  •  " .. lv .. "  •  " .. ROLE[m.role]() }
	end
	return out
end

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", "DungeonPlannerPrepSection", parent)

	local left = W.Panel(f, "surface", "border")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -SP.md / 2, 0)
	local right = W.Panel(f, "surface", "border")
	right:SetPoint("TOPLEFT", f, "TOP", SP.md / 2, 0)
	right:SetPoint("BOTTOMRIGHT")
	f.left, f.right = left, right

	left.heading = W.Heading(left, L["Before you go"], nil, true)
	left.heading:SetPoint("TOPLEFT", SP.md, -SP.md)
	f.showAll = W.Check(left, L["Show all"], function(v)
		ns.db.ui.prepShowAll = v
		f:Refresh()
	end)
	f.showAll:SetPoint("TOPRIGHT", -SP.md, -SP.md - 2)
	f.doc = W.Document(left)
	f.doc:SetPoint("TOPLEFT", left.heading, "BOTTOMLEFT", 0, -SP.sm)
	f.doc:SetPoint("BOTTOMRIGHT", -SP.sm, SP.md)

	right.heading = W.Heading(right, L["Getting there"], nil, true)
	right.heading:SetPoint("TOPLEFT", SP.md, -SP.md)
	f.travel = W.Document(right)
	f.travel:SetPoint("TOPLEFT", right.heading, "BOTTOMLEFT", 0, -SP.sm)
	f.travel:SetPoint("RIGHT", -SP.sm, 0)
	f.bar = GT.Actions(f.travel.content)
	-- Getting there in its own small window, to keep beside the game while travelling.
	f.pop = W.Button(right, L["Pop out"], "outline", function()
		local p = ctx:Plan()
		if p then
			GT.Open(p)
		end
	end)
	f.pop:SetPoint("TOPRIGHT", -SP.md, -SP.sm)
	W.SetTooltip(f.pop, L["Pop out"], L["Open Getting there in its own small window you can keep beside the game."])

	f.notesLabel = W.Heading(right, L["Prep notes"], nil, true)
	f.notesLabel:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", SP.md, SP.md + Panel.NOTES_H + SP.sm)
	f.travel:SetPoint("BOTTOM", f.notesLabel, "TOP", 0, SP.sm)
	f.notes = W.MultiLine(right, {
		maxBytes = Schema.TEXT.prep,
		onCommit = function(text)
			local p = ctx:Plan()
			if p and not ctx:ReadOnly() then
				Plan.SetField(p, "prep", text)
				ctx:Changed("meta")
			end
		end,
	})
	f.notes:SetPoint("TOPLEFT", f.notesLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.notes:SetPoint("BOTTOMRIGHT", -SP.md, SP.md)
	f.notesText = W.Document(right)
	f.notesText:SetPoint("TOPLEFT", f.notesLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.notesText:SetPoint("BOTTOMRIGHT", -SP.sm, SP.md)

	function f:Refresh()
		local p = ctx:Plan()
		if not p then
			return
		end
		self.showAll:SetChecked(ns.db.ui.prepShowAll)
		local rows, counts = ns.PrepInfo.Quests(p, ns.db.ui.prepShowAll)
		local doc = self.doc
		doc:Begin(p.id)
		local questie = ns.Providers.Get("questie") ~= nil
		for _, l in ipairs(Panel.QuestLines(rows, counts, questie)) do
			doc:Add(l[1], l[2])
		end
		for _, l in ipairs(Panel.KeyLines(ns.PrepInfo.Keys(p))) do
			doc:Add(l[1], l[2])
		end
		local group, lo, hi = ns.PrepInfo.Group(p)
		for _, l in ipairs(Panel.GroupLines(group, lo, hi, p.instance.kind)) do
			doc:Add(l[1], l[2])
		end
		doc:Finish()

		local travel = self.travel
		travel:Begin(p.id)
		GT.Fill(travel, p, self.bar, false)
		travel:Finish()

		local ro = ctx:ReadOnly()
		self.notes:SetShown(not ro)
		self.notesText:SetShown(ro)
		if ro then
			-- The plan's own notes, read-only (a received copy, data from a newer version); the hint when it has none.
			self.notesText:Begin(p.id)
			if p.prep and p.prep ~= "" then
				self.notesText:Add("text", p.prep)
			else
				self.notesText:Add("muted", L["Your own notes (consumables, reminders) go here in an editable copy of the plan."])
			end
			self.notesText:Finish()
		else
			self.notes:SetValue(p.prep or "")
		end
	end

	ns.PrepInfo.Watch(f, function()
		return f:IsVisible()
	end)
	ns:On("PREP_CHANGED", f, function()
		if f:IsVisible() then
			f:Refresh()
		end
	end)
	ns:On("ITEMS_READY", f, function()
		if f:IsVisible() then
			f:Refresh()
		end
	end)
	return f
end
