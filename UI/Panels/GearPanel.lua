-- Gear page: the plan's own gear recommendations first, then what the instance drops, boss by boss, from the client's
-- Adventure Guide (Data/Loot.lua; guarded, read on demand). Filters: class, role, boss and slot apply to both. Items
-- show the game's names, quality colours, icons and tooltips; Shift-click links one in chat. Editable plans add their
-- own entries (an item ID, a dragged item or a label) with the form at the bottom, or recommend a drop with a
-- right-click. Dungeon Planner ships no item database: names and icons come from the client (C_Item) at runtime, and
-- uncached items fill in when they arrive (Names.Item, ITEMS_READY) or EJ_LOOT_DATA_RECIEVED says the loot did.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Util, Schema = ns.Plan, ns.Util, ns.Schema
local SP, SZ = S.SPACE, S.SIZE

local Panel = {}
ns.Panels.gear = Panel

-- Classes this client has, from the game: { text, value = class file ("WARRIOR"), id = class ID }.
local function classes()
	local out = {}
	if GetNumClasses and GetClassInfo then
		for i = 1, GetNumClasses() do
			local ok, name, file, id = pcall(GetClassInfo, i)
			name, file, id = ok and Util.Plain(name), ok and Util.Plain(file), ok and Util.Plain(id)
			if type(name) == "string" and type(file) == "string" then
				out[#out + 1] = { text = name, value = file, id = Util.IsInteger(id) and id or i }
			end
		end
	end
	return out
end

local function classID(file)
	for _, c in ipairs(classes()) do
		if c.value == file then
			return c.id
		end
	end
	return nil
end

local function slotText(slot)
	return slot and L["slot:" .. slot] or ""
end

local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

local function hasRole(p)
	for _, g in ipairs(p.gear or {}) do
		if g.role then
			return true
		end
	end
	return false
end
-- Items side by side: as many columns as fit at CELL_MIN wide (an item's name and slot), at most COLS_MAX.
local CELL_MIN, COLS_MAX = 250, 3

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local filter = { class = nil, role = nil, encounter = nil, slot = nil }
	local draft = { slot = nil, priority = 3 }

	local function plan()
		return ctx:Plan()
	end
	local function changed()
		ctx:Changed("gear")
	end

	-- Filters (one line, the first at the start).
	local function dropdown(width, options, key)
		return W.Dropdown(f, {
			width = width,
			options = options,
			get = function()
				return filter[key] or false
			end,
			set = function(v)
				filter[key] = v or nil
				f:Refresh()
			end,
		})
	end
	f.class = dropdown(150, function()
		local out = { { text = L["All classes"], value = false } }
		for _, c in ipairs(classes()) do
			out[#out + 1] = c
		end
		return out
	end, "class")
	f.class:SetPoint("TOPLEFT")
	f.role = dropdown(130, function()
		return {
			{ text = L["All roles"], value = false },
			{ text = L["Tank"], value = "TANK" },
			{ text = L["Healer"], value = "HEALER" },
			{ text = L["Damage"], value = "DAMAGER" },
		}
	end, "role")
	f.role:SetPoint("LEFT", f.class, "RIGHT", SP.sm, 0)
	f.encounter = dropdown(180, function()
		local out = { { text = L["Whole instance"], value = false } }
		for _, enc in ipairs(plan() and plan().encounters or {}) do
			out[#out + 1] = { text = ns.Names.Encounter(enc), value = enc.id }
		end
		return out
	end, "encounter")
	f.encounter:SetPoint("LEFT", f.role, "RIGHT", SP.sm, 0)
	f.slot = dropdown(130, function()
		local out = { { text = L["All slots"], value = false } }
		for _, slot in ipairs(Schema.SLOTS) do
			out[#out + 1] = { text = slotText(slot), value = slot }
		end
		return out
	end, "slot")
	f.slot:SetPoint("LEFT", f.encounter, "RIGHT", SP.sm, 0)
	W.SetTooltip(f.class, L["Class"],
		L["Items this class can wear and wield at full level: armor up to its heaviest type, the weapons and shields it can use. Other items stay listed."])
	W.SetTooltip(f.encounter, L["Boss"], L["Shows the drops of one boss, or of the whole instance."])
	W.SetTooltip(f.slot, L["Slot"], L["Shows the items for one equipment slot."])
	-- The filters share the line, each as wide as its longest option (in either language); when the line is too narrow
	-- for that, they shrink alike (never under each other).
	f.measure = W.Text(f, "body", "ink")
	f.measure:Hide()
	local function naturalWidth(options)
		local widest = 0
		for _, opt in ipairs(options) do
			f.measure:SetText(opt.text or "")
			widest = math.max(widest, math.ceil(f.measure:GetStringWidth() or 0))
		end
		-- The label's inset on the left, the caret's room on the right (W.Dropdown).
		return math.min(220, math.max(90, widest + SP.sm + SP.xl + 2))
	end
	local function layoutFilters()
		local list = { f.class, f.role, f.encounter, f.slot }
		local natural, sum = {}, 0
		for i, dd in ipairs(list) do
			natural[i] = naturalWidth(dd.dpOptions())
			sum = sum + natural[i]
		end
		local room = (f:GetWidth() or 0) - 3 * SP.sm
		local k = room > 0 and math.min(1, room / sum) or 1
		for i, dd in ipairs(list) do
			dd:SetWidth(math.max(60, math.floor(natural[i] * k)))
		end
	end
	f.LayoutFilters = layoutFilters
	f:HookScript("OnSizeChanged", layoutFilters)
	-- A line of its own under the filters: the hint on the left, "Open in NeedRoll" on the right. Where the loot comes
	-- from is in the list's section header ("Drops (Dungeon Journal)").
	f.status = W.Text(f, "caption", "muted")
	f.status:SetPoint("TOPLEFT", f.class, "BOTTOMLEFT", 0, -SP.sm)
	f.status:SetHeight(SZ.control)
	f.status:SetPoint("RIGHT")

	-- Add form (bottom; editable plans only).
	local form = CreateFrame("Frame", nil, f)
	form:SetPoint("BOTTOMLEFT")
	form:SetPoint("BOTTOMRIGHT")
	form:SetHeight(16 + SP.xs + SZ.control)
	f.form = form

	form.hint = W.Label(form, L["Add: item ID or drag an item onto the field, a label, slot and priority. Class, role and boss come from the filters above."])
	form.hint:SetPoint("TOPLEFT")
	form.hint:SetPoint("RIGHT")
	form.item = W.Input(form, {
		width = 120,
		maxBytes = 300,
		placeholder = L["Item ID"],
	})
	form.item:SetPoint("BOTTOMLEFT")
	-- Drag an item from the bags onto the field.
	local function takeCursorItem()
		if not GetCursorInfo then
			return
		end
		local kind, itemID = GetCursorInfo()
		if kind == "item" and Util.IsInteger(itemID) then
			form.item:SetValue(tostring(itemID))
			if ClearCursor then
				ClearCursor()
			end
		end
	end
	form.item.edit:SetScript("OnReceiveDrag", takeCursorItem)
	form.item.edit:HookScript("OnMouseDown", function()
		if GetCursorInfo and GetCursorInfo() == "item" then
			takeCursorItem()
		end
	end)

	form.label = W.Input(form, { maxBytes = Schema.TEXT.label, placeholder = L["Label or note"] })
	form.label:SetPoint("LEFT", form.item, "RIGHT", SP.sm, 0)
	form.label:SetPoint("RIGHT", -(130 + 110 + 80 + SP.sm * 3), 0)

	form.slot = W.Dropdown(form, {
		width = 130,
		options = function()
			local out = { { text = L["Any slot"], value = false } }
			for _, slot in ipairs(Schema.SLOTS) do
				out[#out + 1] = { text = slotText(slot), value = slot }
			end
			return out
		end,
		get = function()
			return draft.slot or false
		end,
		set = function(v)
			draft.slot = v or nil
		end,
	})
	form.slot:SetPoint("LEFT", form.label, "RIGHT", SP.sm, 0)
	form.priority = W.Dropdown(form, {
		width = 110,
		options = function()
			local out = {}
			for i = 1, 5 do
				out[i] = { text = string.format(L["Priority %d"], i), value = i }
			end
			return out
		end,
		get = function()
			return draft.priority
		end,
		set = function(v)
			draft.priority = v
		end,
	})
	form.priority:SetPoint("LEFT", form.slot, "RIGHT", SP.sm, 0)

	local function addGear(fields)
		local p = plan()
		if not p or ctx:ReadOnly() then
			return nil
		end
		fields.class, fields.role, fields.encounter = filter.class, filter.role, fields.encounter or filter.encounter
		local g, err = Plan.AddGear(p, fields)
		if g then
			changed()
		else
			ns:Print(err == "invalid" and L["Enter an item ID, drag an item, or write a label."] or (L["Cannot add:"] .. " " .. tostring(err)))
		end
		return g
	end
	form.add = W.Button(form, L["Add"], "red", function()
		local g = addGear({
			itemID = form.item:GetValue(),
			label = form.label:GetValue(),
			slot = draft.slot,
			priority = draft.priority,
		})
		if g then
			form.item:SetValue("")
			form.label:SetValue("")
		end
	end, 80)
	form.add:SetPoint("LEFT", form.priority, "RIGHT", SP.sm, 0)

	-- The list: section headers, the plan's entries ({ gear = g }) and journal drops ({ loot = item }).
	local function showTooltip(row, itemID, link)
		if not GameTooltip then
			return
		end
		-- Beside the item's name, top-aligned with it (W.AnchorBeside): the game's comparison tooltips line up with
		-- this one, so they sit next to the item and cover the rows below, never the filters above the list.
		W.AnchorBeside(GameTooltip, row, row.title)
		ns.Names.ItemHovered(itemID) -- an item still without its name asks for it again
		local ok = false
		if link and GameTooltip.SetHyperlink then
			ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
		end
		if not ok and itemID and GameTooltip.SetItemByID then
			pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
		end
		GameTooltip:Show()
		-- Near the bottom of the screen the game pushes a tall tooltip up; if that puts it over "Open in NeedRoll"
		-- (top right of the page), it opens left of the item's icon instead, away from the button.
		if W.Overlaps(GameTooltip, f.needRoll) then
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("TOPRIGHT", row.icon, "TOPLEFT", -SP.md, SP.xs)
		end
	end
	local function linkInChat(link)
		local insert = rawget(_G, "ChatEdit_InsertLink")
		if link and type(insert) == "function" then
			pcall(insert, link)
		end
	end

	-- One entry (an own item or a drop) in a cell of a list line: the item's icon, name, slot and the like, a priority
	-- badge for own items.
	local function fillCell(cell, entry)
		cell.entry = entry
		if entry.gear then
			local g = entry.gear
			local name, quality, icon = ns.Names.ItemInfo(g)
			cell.icon:SetTexture(icon or 134400) -- 134400: the game's question-mark icon file ID
			cell.title:SetText(name)
			cell.title:SetTextColor(ns.Names.QualityColor(quality))
			local meta = {}
			if g.label ~= "" and g.itemID then
				meta[#meta + 1] = g.label
			end
			if g.slot then
				meta[#meta + 1] = slotText(g.slot)
			end
			if g.class then
				meta[#meta + 1] = g.class:sub(1, 1) .. g.class:sub(2):lower()
			end
			if g.role then
				meta[#meta + 1] = L[ROLE_TEXT[g.role] or "Damage"]
			end
			if g.encounter then
				local enc = Util.FindById(plan().encounters, g.encounter)
				if enc then
					meta[#meta + 1] = ns.Names.Encounter(enc)
				end
			end
			if g.note ~= "" then
				meta[#meta + 1] = g.note
			end
			cell.meta:SetText(table.concat(meta, " \226\128\162 "))
			cell.badge:SetText(string.format(L["Priority %d"], g.priority))
		else
			local it = entry.loot
			local cName, cQuality, cIcon = ns.Names.ItemInfo({ itemID = it.itemID, label = "" })
			cell.icon:SetTexture(it.icon or cIcon or 134400)
			cell.title:SetText(it.name or cName)
			cell.title:SetTextColor(ns.Names.QualityColor(it.quality or cQuality))
			local meta = {}
			if it.slot then
				meta[#meta + 1] = slotText(it.slot)
			elseif it.slotText then
				meta[#meta + 1] = it.slotText
			end
			if it.armorType then
				meta[#meta + 1] = it.armorType
			end
			cell.meta:SetText(table.concat(meta, ", "))
			cell.badge:SetText("")
		end
		-- The name and meta run to the badge when there is one, else to the cell's edge.
		local inset = entry.gear and -(math.ceil(cell.badge:GetStringWidth() or 0) + SP.md + SP.sm) or -SP.sm
		cell.title:SetPoint("RIGHT", inset, 0)
		cell.meta:SetPoint("RIGHT", inset, 0)
	end

	local function cellEnter(cell)
		local entry = cell.entry
		if entry and entry.gear and entry.gear.itemID then
			showTooltip(cell, entry.gear.itemID)
		elseif entry and entry.loot then
			showTooltip(cell, entry.loot.itemID, entry.loot.link)
		end
	end

	local function cellClick(cell, mouse)
		W.CommitFocus()
		local entry = cell.entry
		if not entry then
			return
		end
		local itemID = entry.gear and entry.gear.itemID or entry.loot and entry.loot.itemID
		if mouse == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
			linkInChat(entry.loot and entry.loot.link)
			return
		end
		if mouse ~= "RightButton" or ctx:ReadOnly() then
			return
		end
		if entry.gear then
			W.Menu(cell, {
				{
					L["Delete"],
					function()
						Plan.RemoveGear(plan(), entry.gear.id)
						changed()
					end,
				},
			})
		elseif itemID then
			W.Menu(cell, {
				{ title = entry.loot.name or tostring(itemID) },
				{
					L["Recommend this item"],
					function()
						addGear({ itemID = itemID, slot = entry.loot.slot, priority = draft.priority, encounter = entry.encounterId })
					end,
				},
			})
		end
	end

	local function makeCell(row)
		local cell = CreateFrame("Button", nil, row)
		cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		cell.glow = W.RowHighlight(cell)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(32, 32)
		cell.icon:SetPoint("LEFT", SP.sm, 0)
		cell.title = W.Text(cell, "body", "ink")
		cell.title:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", SP.sm, -1)
		cell.meta = W.Text(cell, "caption", "muted")
		cell.meta:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", SP.sm, 1)
		cell.badge = W.Text(cell, "caption", "goldBright")
		cell.badge:SetPoint("RIGHT", -SP.md, 0)
		cell.badge:SetJustifyH("RIGHT")
		cell:SetScript("OnEnter", cellEnter)
		cell:SetScript("OnLeave", function(self)
			if GameTooltip and GameTooltip:IsOwned(self) then
				GameTooltip:Hide()
			end
		end)
		cell:SetScript("OnClick", cellClick)
		return cell
	end

	-- The list's lines: a section or boss heading, or up to `cols` entries side by side (the page is wide; one entry a
	-- line left most of it empty).
	f.list = W.List(f, {
		rowHeight = SZ.row2,
		empty = L["No gear for this filter."],
		create = function(row)
			row.cells = {}
			for i = 1, COLS_MAX do
				row.cells[i] = makeCell(row)
			end
			row.heading = W.Text(row, "title", "gold")
			row.heading:SetPoint("BOTTOMLEFT", SP.sm, SP.xs + 2)
			row.heading:SetPoint("RIGHT", -SP.sm, 0)
			-- A header row stands on the game's header band (Style.HeaderStrip) with a gold rule, like W.SectionHeader.
			row.strip = S.HeaderStrip(row)
			if row.strip then
				row.strip:SetPoint("BOTTOMLEFT", 2, 2)
				row.strip:SetPoint("BOTTOMRIGHT", -2, 2)
				row.strip:SetHeight(SZ.row - 4)
			end
			row.rule = S.Hairline(row)
			row.rule:SetPoint("BOTTOMLEFT", 2, 2)
			row.rule:SetPoint("BOTTOMRIGHT", -2, 2)
		end,
		update = function(row, line)
			local isHeader = line.header ~= nil
			row.heading:SetShown(isHeader)
			-- The band marks the list's sections; the bosses under them (indented) are plain gold headings.
			local section = isHeader and not line.header:find("^%s")
			row.rule:SetShown(section)
			if row.strip then
				row.strip:SetShown(section)
			end
			row.glow:SetShown(false) -- each cell has its own
			if isHeader then
				row.heading:SetText(line.header)
			end
			local cells = line.cells or {}
			local cols = math.max(1, #cells == 0 and 1 or f.cols)
			local width = (math.max(0, f.list:GetWidth() - SP.md) - (cols - 1) * SP.sm) / cols
			for i, cell in ipairs(row.cells) do
				local entry = cells[i]
				cell:SetShown(entry ~= nil)
				if entry then
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", (i - 1) * (width + SP.sm), 0)
					cell:SetSize(math.max(1, width), SZ.row2)
					fillCell(cell, entry)
				else
					cell.entry = nil
				end
			end
		end,
	})
	f.list:SetPoint("TOPLEFT", f.class, "BOTTOMLEFT", 0, -SP.md)
	f.list:SetPoint("BOTTOMRIGHT", form, "TOPRIGHT", 0, SP.md)
	f.cols = 1

	-- Entries into lines: headings alone, the entries under each `cols` to a line.
	local function lines(entries, cols)
		local out, line = {}, nil
		for _, e in ipairs(entries) do
			if e.header then
				out[#out + 1] = e
				line = nil
			else
				if not line or #line.cells >= cols then
					line = { cells = {} }
					out[#out + 1] = line
				end
				line.cells[#line.cells + 1] = e
			end
		end
		return out
	end
	local function columns()
		local w = f.list:GetWidth() - SP.md
		return math.max(1, math.min(COLS_MAX, math.floor((w + SP.sm) / (CELL_MIN + SP.sm))))
	end
	-- The flat list of entries (headings, own items { gear }, drops { loot }) the lines are made of.
	f.entries = {}
	local function setLines()
		f.cols = columns()
		f.list:SetItems(lines(f.entries, f.cols))
	end
	f.list:HookScript("OnSizeChanged", function()
		if columns() ~= f.cols then
			setLines()
		end
	end)

	-- The journal's drops for the filter, grouped by boss (journal order).
	local function journalDrops(p)
		if not ns.Journal.HasData() then
			return {}, "nojournal" -- WoW: Forever's Adventure Guide is empty: no drop lists at all
		end
		local entry = ns.Journal.ForPlan(p)
		if not entry then
			return {}, "unavailable"
		end
		local lootFilter = { classID = filter.class and classID(filter.class), role = filter.role, slot = filter.slot }
		local bosses = {}
		if filter.encounter then
			local enc = Util.FindById(p.encounters, filter.encounter)
			if enc then
				bosses[1] = enc
			end
		else
			for _, enc in ipairs(p.encounters) do
				bosses[#bosses + 1] = enc
			end
		end
		local out, status = {}, "ok"
		for _, enc in ipairs(bosses) do
			local ej = ns.Journal.EncounterIds(p, enc)
			if ej then
				local items, st = ns.Loot.For(entry.ejInstanceID, ej, lootFilter)
				if st == "unavailable" then
					return {}, st
				end
				if st == "loading" then
					status = "loading"
				end
				if #items > 0 then
					local bossName = ns.Names.Encounter(enc)
					out[#out + 1] = { header = bossName }
					for _, it in ipairs(items) do
						out[#out + 1] = { loot = it, encounterId = enc.id }
					end
				end
			end
		end
		return out, status
	end

	-- Loot from the bundled boss data and the data providers, grouped by boss. These lists are item IDs only, so the
	-- class and slot filters read each item's type from the client (Loot.ItemType, GearFilter.Match). An item the
	-- client has no data for yet is asked for (Names.Item); it is left out of a filtered list until it arrives, and
	-- ITEMS_READY redraws the page once it does (out.loading meanwhile).
	local function providerDrops(p)
		local out = {}
		local want = { class = filter.class, slot = filter.slot }
		for _, enc in ipairs(p.encounters) do
			local list, credit = nil, nil
			if not filter.encounter or enc.id == filter.encounter then
				list, credit = ns.Providers.Loot(p, enc)
			end
			if list then
				out.credit = credit
				local rows = {}
				for _, it in ipairs(list) do
					local match = ns.GearFilter.Match(want, ns.Loot.ItemType(it.itemID))
					if match == nil then
						ns.Names.Item(it.itemID)
						out.loading = out.loading or ns.Names.ItemLoading(it.itemID)
					elseif match then
						rows[#rows + 1] = { loot = it, encounterId = enc.id }
					end
				end
				if #rows > 0 then
					out[#out + 1] = { header = "   " .. ns.Names.Encounter(enc) }
					for _, r in ipairs(rows) do
						out[#out + 1] = r
					end
				end
			end
		end
		return out
	end

	-- "Open in NeedRoll" (its public API) for the boss in the filter, or the instance.
	f.needRoll = W.Button(f, L["Open in NeedRoll"], "outline", function()
		local p = plan()
		if not p then
			return
		end
		local enc = filter.encounter and Util.FindById(p.encounters, filter.encounter)
		for _, a in ipairs(ns.Providers.LootLinks()) do
			ns.Providers.Call(a.id, "OpenLoot", p, enc)
		end
	end)
	-- On the hint's line, anchored to the panel (the filters are SZ.control tall): the hint's right edge is anchored to
	-- this button, so the button must not anchor to the hint (the client refuses a cycle and the page stays empty).
	f.needRoll:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(SZ.control + SP.sm))
	f.needRoll:Hide()
	W.SetTooltip(f.needRoll, L["Open in NeedRoll"], L["Opens NeedRoll's loot page for the boss picked in the filter (or the whole instance)."])

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		layoutFilters() -- the boss filter lists this plan's bosses
		self.class:Refresh()
		self.role:Refresh()
		self.encounter:Refresh()
		self.slot:Refresh()
		form.slot:Refresh()
		form.priority:Refresh()
		local ro = ctx:ReadOnly()
		-- Read-only plans (recommended ones) have nothing to add: the form goes, the list takes its place.
		form:SetShown(not ro)
		self.list:ClearAllPoints()
		self.list:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -SP.sm)
		if ro then
			self.list:SetPoint("BOTTOMRIGHT")
		else
			self.list:SetPoint("BOTTOMRIGHT", form, "TOPRIGHT", 0, SP.md)
		end

		-- The role filter needs data that names a role: the plan's own entries tagged with one (and the add form, which
		-- tags new entries), or the Adventure Guide's loot by specialization. A drop list of item IDs names none, so on
		-- a read-only plan without such entries the filter is switched off and says why.
		local roleUseful = not ro or ns.Journal.HasData() or hasRole(p)
		if not roleUseful then
			filter.role = nil
		end
		self.role:SetDisabled(not roleUseful)
		local roleTip = roleUseful
			and L["Filters this plan's own entries by the role they are tagged with. Drops carry no role, so they stay listed."]
			or L["Drops carry no role, and this plan tags none of its entries with one, so there is nothing to filter by role."]
		W.SetTooltip(self.role, L["Role"], roleTip)
		self.role:Refresh()

		local items = {}
		local own = {}
		for _, g in ipairs(Plan.FilterGear(p, filter)) do
			-- An entry tagged with no class follows the class filter by its item's type; one not known yet stays.
			if g.class or not (filter.class and g.itemID)
				or ns.GearFilter.CanEquip(filter.class, ns.Loot.ItemType(g.itemID)) ~= false then
				own[#own + 1] = g
			end
		end
		if #own > 0 then
			items[#items + 1] = { header = L["Recommended by this plan"] }
			for _, g in ipairs(own) do
				items[#items + 1] = { gear = g }
			end
		end
		local drops, status = journalDrops(p)
		if #drops > 0 then
			items[#items + 1] = { header = L["Drops (Adventure Guide)"] }
			for _, d in ipairs(drops) do
				if d.header then
					d = { header = "   " .. d.header }
				end
				items[#items + 1] = d
			end
		end
		-- Drops another installed addon lists for these bosses (Data/Providers.lua), named after it.
		local provided = providerDrops(p)
		if #provided > 0 then
			items[#items + 1] = { header = string.format(L["Drops (%s)"], provided.credit) }
			for _, d in ipairs(provided) do
				items[#items + 1] = d
			end
			if status == "nojournal" then
				status = "provider"
			end
		end
		if provided.loading and status ~= "loading" then
			status = "loading"
		end
		local links = #ns.Providers.LootLinks() > 0
		self.needRoll:SetShown(links)
		if links then
			-- Measured again once shown: the first measure can run before the font is ready, which cut the label.
			self.needRoll:SetLabel(L["Open in NeedRoll"])
			self.needRoll:SetDisabled(false)
		end
		self.status:SetPoint("RIGHT", links and self.needRoll or self, links and "LEFT" or "RIGHT", links and -SP.sm or 0, 0)
		self.loading = status == "loading"
		-- A loot provider that switched itself off after an error says so, instead of an unexplained empty list.
		local failed = #provided == 0 and ns.Providers.Failures("loot")[1]
		if failed then
			self.status:SetText(string.format(L["%s data unavailable: %s"], failed.title, failed.reason))
		elseif status == "provider" then
			self.status:SetText(L["Shift-click an item to link it in chat."])
		elseif status == "nojournal" then
			self.status:SetText(#own > 0 and L["The game's Adventure Guide has no loot lists on this client; showing this plan's own gear."]
				or L["The game's Adventure Guide has no loot lists on this client. Add the items you want to this plan's list."])
		elseif status == "unavailable" then
			self.status:SetText(L["This client's Adventure Guide lists no loot here."])
		elseif status == "loading" then
			self.status:SetText(L["Loading items..."])
		else
			self.status:SetText(L["Shift-click an item to link it in chat."])
		end
		-- The list draws only the rows in view; ask for every listed item now, so rows scrolled to later have names.
		for _, it in ipairs(items) do
			local id = it.gear and it.gear.itemID or it.loot and it.loot.itemID
			if id then
				ns.Names.Item(id)
			end
		end
		self.entries = items
		setLines()
	end

	-- Item and loot data arrive asynchronously; refresh while visible, at most once per half second.
	local pending = false
	local function later()
		if f:IsVisible() and not pending and C_Timer then
			pending = true
			C_Timer.After(0.5, function()
				pending = false
				if f:IsVisible() then
					ns.SafeCall(f.Refresh, f)
				end
			end)
		end
	end
	ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", later)
	ns:RegisterEvent("EJ_LOOT_DATA_RECIEVED", later)
	return f
end
