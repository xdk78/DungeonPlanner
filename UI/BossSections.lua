-- The sections of a boss page that another addon provides (Data/BossInfo.lua: Dungeon Journal's description, summon
-- item and notable drops), drawn the same way on every page that shows a boss: item rows (icon, quality-coloured name,
-- slot; the game's item tooltip on hover; Shift-click links the item in chat) under a gold heading that carries the
-- source's name in muted text. FillDoc puts them into a W.Document (the marker's details, the Bosses page of a
-- recommended plan); Stack lays them out in a frame of their own (the Bosses page of an own plan). Nothing is shown
-- for a section the provider has no data for.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP = S.SPACE
local BossSections = ns:NewModule("BossSections")

local ROW_H = 34
local NOTE_H = 36 -- extra height of an ability row for its note (three lines of caption text)
local ICON = 28
local QUESTION_MARK = 134400 -- the game's question-mark icon file ID
BossSections.ROW_H = ROW_H

-- `text` in the muted colour, for the source's name next to a heading.
local function muted(text)
	local r, g, b = S.Color("muted")
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

local function headingText(section)
	return section.title .. (section.credit and ("  " .. muted(section.credit)) or "")
end

-- The item's chat link from the client's item cache, nil while it is not cached (or without the API).
local function itemLink(itemID)
	local items = rawget(_G, "C_Item")
	local get = items and items.GetItemInfo or rawget(_G, "GetItemInfo")
	if type(get) ~= "function" then
		return nil
	end
	local ok, _, link = pcall(get, itemID)
	link = ok and ns.Util.Plain(link) or nil
	return type(link) == "string" and link ~= "" and link or nil
end

-- The game's spell tooltip for an ability row.
local function showSpellTooltip(row, tt)
	W.TipBeside(tt, row)
	if tt.SetSpellByID then
		pcall(tt.SetSpellByID, tt, row.dpSpell.spellID)
	end
	tt:Show()
end

local function showTooltip(row)
	local tt = rawget(_G, "GameTooltip")
	if tt and row.dpSpell then
		return showSpellTooltip(row, tt)
	end
	local id = row.dpItem and row.dpItem.itemID
	if not (tt and id) then
		return
	end
	W.TipBeside(tt, row)
	ns.Names.ItemHovered(id) -- a drop still without its name asks for it again
	local ok = false
	local link = itemLink(id)
	if link and tt.SetHyperlink then
		ok = pcall(tt.SetHyperlink, tt, link)
	end
	if not ok and tt.SetItemByID then
		pcall(tt.SetItemByID, tt, id)
	end
	tt:Show()
end

local function hideTooltip(row)
	local tt = rawget(_G, "GameTooltip")
	if tt and tt.IsOwned and tt:IsOwned(row) then
		tt:Hide()
	end
end

local function newRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 0, 0)
	row.name = W.Text(row, "body", "white")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", SP.sm, 0)
	row.name:SetPoint("RIGHT", -SP.xs, 0)
	row.meta = W.Text(row, "caption", "muted")
	row.meta:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", SP.sm, 0)
	row.meta:SetPoint("RIGHT", -SP.xs, 0)
	-- An ability's note, wrapped under the icon (hidden on item rows).
	row.note = W.Paragraph(row, "caption", "muted")
	row.note:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -SP.xxs)
	row.note:SetPoint("RIGHT", -SP.xs, 0)
	if row.note.SetMaxLines then
		row.note:SetMaxLines(3)
	end
	row.note:Hide()
	row.glow = W.RowHighlight(row)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function(self)
		local id = self.dpItem and self.dpItem.itemID
		local insert = rawget(_G, "ChatEdit_InsertLink")
		if id and IsShiftKeyDown and IsShiftKeyDown() and type(insert) == "function" then
			local link = itemLink(id)
			if link then
				pcall(insert, link)
			end
		end
	end)
	return row
end

-- Fill a row with an item { itemID, name?, quality?, slot?, slotText? }: the client's name, quality and icon where it
-- has them (its language), else what the provider gave.
local function setRow(row, it)
	row.dpItem, row.dpSpell = it, nil
	row.note:Hide()
	row:SetHeight(ROW_H)
	row.dpHeight = ROW_H
	local clientName = ns.Names.Item(it.itemID)
	local name, quality, icon = ns.Names.ItemInfo({ itemID = it.itemID, label = "" })
	row.icon:SetTexture(it.icon or icon or QUESTION_MARK)
	row.name:SetText(clientName or it.name or name)
	row.name:SetTextColor(ns.Names.QualityColor(quality or it.quality))
	local slot = it.slot and L["slot:" .. it.slot] or it.slotText
	row.meta:SetText(slot or "")
	row.meta:SetShown(slot ~= nil)
end

-- Fill a row with an ability { spellID, tags, note? }: the spell's icon and name from the client (C_Spell, guarded), its
-- tags and the short note under it. The game's own tooltip shows the description.
local function setAbilityRow(row, ab)
	row.dpItem, row.dpSpell = nil, ab
	local spells = rawget(_G, "C_Spell")
	local name, icon
	if spells and type(spells.GetSpellName) == "function" then
		local ok, n = pcall(spells.GetSpellName, ab.spellID)
		name = ok and ns.Util.Plain(n) or nil
	end
	if spells and type(spells.GetSpellTexture) == "function" then
		local ok, t = pcall(spells.GetSpellTexture, ab.spellID)
		icon = ok and ns.Util.Plain(t) or nil
	end
	row.icon:SetTexture(icon or QUESTION_MARK)
	row.name:SetText(name or string.format(L["Spell %d"], ab.spellID))
	S.TextColor(row.name, "white")
	local tags = ns.BossInfo.TagText(ab.tags)
	row.meta:SetText(tags)
	row.meta:SetShown(tags ~= "")
	local note = ab.note and ab.note ~= "" and ab.note or nil
	row.note:SetText(note or "")
	row.note:SetShown(note ~= nil)
	row.dpHeight = note and (ROW_H + NOTE_H) or ROW_H
	row:SetHeight(row.dpHeight)
end

-- Into a W.Document: after the text the page has put in already. sections = BossInfo.Sections(...).
function BossSections.FillDoc(doc, sections)
	local pool = doc.dpItemRows
	if not pool then
		pool = {}
		doc.dpItemRows = pool
	end
	local used = 0
	for _, s in ipairs(sections) do
		if s.title then
			doc:Add("label", headingText(s))
			doc:Space(SP.xs)
		end
		if s.text then
			doc:Add("text", s.text)
			if s.credit then
				doc:Add("muted", s.credit)
			end
		end
		for _, it in ipairs(s.items or {}) do
			used = used + 1
			local row = pool[used]
			if not row then
				row = newRow(doc.content)
				pool[used] = row
			end
			setRow(row, it)
			doc:Place(row, ROW_H + SP.xxs, true)
		end
		for _, ab in ipairs(s.abilities or {}) do
			used = used + 1
			local row = pool[used]
			if not row then
				row = newRow(doc.content)
				pool[used] = row
			end
			setAbilityRow(row, ab)
			doc:Place(row, row.dpHeight + SP.xxs, true)
		end
	end
end

-- A frame of its own for the sections: frame:SetPoint(...) it (left and right), then :Set(sections) -> its height.
function BossSections.Stack(parent)
	local st = CreateFrame("Frame", nil, parent)
	local labels, texts, rows = {}, {}, {}
	local function take(pool, n, make)
		local w = pool[n]
		if not w then
			w = make()
			pool[n] = w
		end
		w:Show()
		return w
	end
	function st:Set(sections)
		for _, pool in ipairs({ labels, texts, rows }) do
			for _, w in ipairs(pool) do
				w:Hide()
			end
		end
		local y, nl, nt, nr = 0, 0, 0, 0
		for _, s in ipairs(sections) do
			if s.title then
				nl = nl + 1
				local fs = take(labels, nl, function()
					return W.Label(self, "")
				end)
				fs:SetText(headingText(s))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 0, -y)
				fs:SetPoint("RIGHT", 0, 0)
				y = y + 16 + SP.xs
			end
			if s.text then
				nt = nt + 1
				local fs = take(texts, nt, function()
					return W.Paragraph(self, "body", "ink")
				end)
				fs:SetText(s.text .. (s.credit and ("\n" .. muted(s.credit)) or ""))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 0, -y)
				fs:SetPoint("RIGHT", 0, 0)
				y = y + math.max(16, math.ceil(fs:GetStringHeight() or 16)) + SP.xs
			end
			for _, it in ipairs(s.items or {}) do
				nr = nr + 1
				local row = take(rows, nr, function()
					return newRow(self)
				end)
				setRow(row, it)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT", 0, 0)
				y = y + ROW_H + SP.xxs
			end
			for _, ab in ipairs(s.abilities or {}) do
				nr = nr + 1
				local row = take(rows, nr, function()
					return newRow(self)
				end)
				setAbilityRow(row, ab)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetPoint("RIGHT", 0, 0)
				y = y + row.dpHeight + SP.xxs
			end
			y = y + SP.sm
		end
		self:SetHeight(math.max(1, y))
		return y
	end
	return st
end
