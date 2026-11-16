-- The instance picker: the list under the header's instance control. An opaque popup (UI/Popup.lua) with a search
-- field, Dungeons and Raids as sections (the game's Dungeon and Raid marks), the dungeons divided into level bands,
-- and one row per instance: a small picture (its loading screen, cropped, or the drawn plate's mark), the name, the
-- level range in the game's difficulty colours, a bronze "Forever" chip for an instance new in WoW: Forever, its
-- plans (the raid star when a recommended plan exists) and the bosses this character has killed (a check when all
-- are). The open instance carries the bronze bar. The list logic (sections, bands, search, cursor) is Model/Picker.lua.

local _, ns = ...
local InstancePicker = ns:NewModule("InstancePicker")
local S, W, L, Art = ns.Style, ns.Widgets, ns.L, ns.Art
local SP = S.SPACE
local Home, Picker, UI = ns.Home, ns.Picker, ns.UI

local WIDTH, HEIGHT = 420, 440
local ROW_H, HEAD_H = 34, 22
local THUMB_W, THUMB_H = 46, 24
local COL = { level = 58, plans = 32, done = 30 }

-- Rows -----------------------------------------------------------------------------------------------------------------

local function createItem(f)
	f.edge = f:CreateTexture(nil, "ARTWORK", nil, -1)
	f.edge:SetColorTexture(1, 1, 1, 1)
	S.Tint(f.edge, "border")
	f.thumb = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.thumb:SetSize(THUMB_W, THUMB_H)
	f.thumb:SetPoint("LEFT", SP.sm + 2, 0)
	f.edge:SetPoint("TOPLEFT", f.thumb, "TOPLEFT", -1, 1)
	f.edge:SetPoint("BOTTOMRIGHT", f.thumb, "BOTTOMRIGHT", 1, -1)
	f.emblem = Art.RoundTexture(f, "ARTWORK", 2)
	f.emblem:SetSize(THUMB_H - 6, THUMB_H - 6)
	f.emblem:SetPoint("CENTER", f.thumb, "CENTER", 0, 0)

	f.check = f:CreateTexture(nil, "ARTWORK", nil, 3)
	f.check:SetSize(14, 14)
	f.check:SetPoint("RIGHT", -(SP.sm + 6), 0)
	Art.Set(f.check, "check")
	f.done = W.Text(f, "caption", "muted")
	f.done:SetPoint("RIGHT", -SP.sm, 0)
	f.done:SetWidth(COL.done)
	f.done:SetJustifyH("RIGHT")

	f.count = W.Text(f, "caption", "ink")
	f.count:SetPoint("RIGHT", -(SP.sm + COL.done), 0)
	f.count:SetWidth(14)
	f.count:SetJustifyH("RIGHT")
	f.star = f:CreateTexture(nil, "ARTWORK", nil, 3)
	f.star:SetSize(12, 12)
	f.star:SetPoint("RIGHT", f.count, "LEFT", -2, 0)
	Art.Set(f.star, "recommended")

	f.level = W.Text(f, "caption", "ink")
	f.level:SetPoint("RIGHT", -(SP.sm + COL.done + COL.plans), 0)
	f.level:SetWidth(COL.level)
	f.level:SetJustifyH("RIGHT")

	-- "Forever": the instance is new in WoW: Forever.
	f.forever = W.Chip(f, L["Forever"], L["Forever"], L["New in WoW: Forever"])
	f.forever:SetPoint("RIGHT", f.level, "LEFT", -SP.xs, 0)

	f.name = W.Text(f, "body", "ink")
	f.name:SetPoint("LEFT", f.thumb, "RIGHT", SP.sm, 0)
	f.name:SetPoint("RIGHT", f.level, "LEFT", -SP.xs, 0)
end

local function updateItem(f, row, current)
	local e = row.entry
	local hasArt = Home.SetInstanceArt(f.thumb, e, "card", THUMB_W, THUMB_H)
	f.emblem:SetShown(not hasArt)
	if not hasArt then
		Art.Set(f.emblem, e.kind == "raid" and "emblemRaid" or "emblemDungeon")
	end
	S.TextColor(f.name, current and "goldBright" or "ink")
	local forever = Picker.IsForever(e)
	f.forever:SetShown(forever)
	f.name:SetPoint("RIGHT", forever and f.forever or f.level, "LEFT", -SP.xs, 0)
	W.FitText(f.name, e.name ~= "" and e.name or L["Unnamed instance"])

	if e.levelLo then
		f.level:SetText(Home.LevelText(e))
		f.level:SetTextColor(S.LevelColor(e.levelLo, e.levelHi))
	else
		f.level:SetText("-")
		S.TextColor(f.level, "dim")
	end

	local total = (e.plans or 0) + (e.recommended or 0)
	f.count:SetText(total > 0 and tostring(total) or "-")
	S.TextColor(f.count, total > 0 and "ink" or "dim")
	f.star:SetShown((e.recommended or 0) > 0)

	local complete = e.killed and e.bosses and e.bosses > 0 and e.killed >= e.bosses
	f.check:SetShown(complete and true or false)
	f.done:SetShown(not complete)
	f.done:SetText(not complete and e.killed and e.killed > 0 and (e.killed .. "/" .. e.bosses) or "")
end

-- A level band's divider: "Levels 10-19" and a bronze rule to the edge.
local function createHeader(f)
	f.text = W.Text(f, "caption", "gold")
	f.text:SetPoint("LEFT", SP.sm, -1)
	f.line = S.Hairline(f)
	f.line:SetPoint("LEFT", f.text, "RIGHT", SP.sm, 0)
	f.line:SetPoint("RIGHT", -SP.sm, -1)
end

local function updateHeader(f, row)
	if row.other then
		f.text:SetText(L["Other"])
	else
		f.text:SetText(string.format(L["Levels %d-%d"], row.lo, row.hi))
	end
end

-- Data -------------------------------------------------------------------------------------------------------------------

-- Every instance with its counts and levels, sorted by level; the open instance is always there (custom maps are not
-- in the journal's list).
function InstancePicker.Entries(current)
	local entries = Home.AllEntries()
	for _, e in ipairs(entries) do
		Home.Decorate(e)
	end
	Home.SortEntries(entries)
	if current and current.key then
		for _, e in ipairs(entries) do
			if e.key == current.key then
				return entries
			end
		end
		Home.Decorate(current)
		entries[#entries + 1] = current
	end
	return entries
end

-- The popup's description for the open instance `current` (tests read it too).
function InstancePicker.Spec(current)
	local entries = InstancePicker.Entries(current)
	return {
		style = "instance",
		width = WIDTH,
		height = HEIGHT,
		rowHeight = ROW_H,
		headerHeight = HEAD_H,
		search = { placeholder = L["Search instances or a level..."] }, -- "forever" finds the new instances too
		tabs = {
			{ id = "dungeon", text = L["Dungeons"], art = "emblemDungeon" },
			{ id = "raid", text = L["Raids"], art = "emblemRaid" },
		},
		tab = Picker.Section(current),
		rows = function(query, tab)
			return Picker.Rows(entries, { section = tab, query = query })
		end,
		pickTab = Picker.SectionFor,
		isCurrent = function(row)
			return current ~= nil and row.entry.key == current.key
		end,
		createItem = createItem,
		updateItem = updateItem,
		createHeader = createHeader,
		updateHeader = updateHeader,
		empty = L["No instance matches the search."],
		onChoose = function(row)
			if not current or row.entry.key ~= current.key then
				UI.OpenInstance(row.entry)
			end
		end,
	}
end

function InstancePicker.Open(owner, current)
	return W.OpenPopup(owner, InstancePicker.Spec(current))
end
