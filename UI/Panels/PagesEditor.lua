-- The Party section's Pages: raid assignment pages (Model/Pages.lua), named pages of free text per boss or phase with
-- keywords ({tank}, {group 2}, {star}, {warrior} ...). Pick a page, write it, tie it to a boss (its page then opens in
-- the Notes window when that boss is pulled), and Send to group (leader or raid assistant), Show in the Notes window or
-- Post to group chat. Recommended plans have no pages: make an editable copy to write some.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE
local Pages, Schema, Util = ns.Pages, ns.Schema, ns.Util

local Editor = {}
ns.PagesEditor = Editor

function Editor.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local selectedId

	local function plan()
		return ctx:Plan()
	end
	local function selected()
		local p = plan()
		return p and selectedId and Pages.Find(p, selectedId) or nil
	end
	local function changed()
		ctx:Changed("pages")
	end
	local function update(fields)
		local page = selected()
		if page then
			Pages.Update(plan(), page.id, fields)
			changed()
		end
	end
	local function pageName(page, i)
		return page.title ~= "" and page.title or string.format(L["Page %d"], i)
	end

	-- Row 1: the page, add, delete.
	f.add = W.Button(f, L["Add page"], "red", function()
		local p = plan()
		if not p then
			return
		end
		local page, err = Pages.Add(p, string.format(L["Page %d"], #Pages.List(p) + 1))
		if page then
			selectedId = page.id
			changed()
		else
			ns:Print(L["Cannot add more pages:"], tostring(err))
		end
	end)
	f.add:SetPoint("TOPLEFT")
	f.delete = W.IconButton(f, "x", L["Delete this page"], function()
		local page = selected()
		if not page then
			return
		end
		W.Confirm(L["Delete page"], string.format(L["Delete the page \"%s\"? Undo brings it back."], page.title),
			L["Delete"], function()
				Pages.Remove(plan(), page.id)
				selectedId = nil
				changed()
			end)
	end)
	f.delete:SetPoint("RIGHT", f, "TOPRIGHT", 0, -SZ.control / 2) -- centred on the row, like the others
	f.pick = W.Dropdown(f, {
		width = 160,
		placeholder = L["No pages yet"],
		options = function()
			local out = {}
			for i, page in ipairs(Pages.List(plan())) do
				local enc = page.encounter and Util.FindById(plan().encounters, page.encounter)
				local boss = enc and ns.Names.Encounter(enc)
				local name = pageName(page, i)
				-- The boss after the title, unless the title already is the boss's name.
				if boss and ns.Match.Norm(boss) ~= ns.Match.Norm(name) then
					name = name .. " · " .. boss
				end
				out[#out + 1] = { text = name, value = page.id }
			end
			return out
		end,
		get = function()
			return selectedId
		end,
		set = function(v)
			selectedId = v
			f:Refresh()
		end,
	})
	local function placePick(ro)
		f.pick:ClearAllPoints()
		if ro then
			f.pick:SetPoint("TOPLEFT")
		else
			f.pick:SetPoint("LEFT", f.add, "RIGHT", SP.sm, 0)
		end
		f.pick:SetPoint("RIGHT", f.delete, "LEFT", -SP.sm, 0)
	end
	placePick(false)

	-- Row 2: title and boss.
	local ROW2 = -(SZ.control + SP.sm)
	f.boss = W.Dropdown(f, {
		width = 140,
		options = function()
			local out = { { text = L["General"], value = false } }
			for _, enc in ipairs(plan() and plan().encounters or {}) do
				out[#out + 1] = { text = ns.Names.Encounter(enc), value = enc.id }
			end
			return out
		end,
		get = function()
			local page = selected()
			return page and page.encounter or false
		end,
		set = function(v)
			update({ encounter = v })
		end,
	})
	f.boss:SetPoint("TOPRIGHT", 0, ROW2)
	W.SetTooltip(f.boss, L["Boss"], L["The boss this page is for: it opens in the Notes window when that boss is pulled."])
	f.title = W.Input(f, {
		maxBytes = Schema.TEXT.name,
		placeholder = L["Page title, for example: Phase 2"],
		onCommit = function(text)
			update({ title = text })
		end,
	})
	f.title:SetPoint("TOPLEFT", 0, ROW2)
	f.title:SetPoint("RIGHT", f.boss, "LEFT", -SP.sm, 0)

	-- The actions, at the bottom; the keyword help above them; the text fills the rest.
	f.send = W.Button(f, L["Send to group"], "outline", function()
		local p, page = plan(), selected()
		if p and page then
			ns:RunOutOfCombat(function()
				ns.NotesFrame.Send(p, page)
			end)
		end
	end)
	f.send:SetPoint("BOTTOMLEFT")
	f.send.dpGround = "surface"
	W.SetTooltip(f.send, L["Send to group"],
		L["Sends this page to your group's Notes windows (leader or raid assistant only). In a boss fight it waits until addons may talk again."])
	f.show = W.Button(f, L["Show"], "outline", function()
		local page = selected()
		if page then
			ns.NotesFrame.Open(page)
		end
	end)
	f.show:SetPoint("LEFT", f.send, "RIGHT", SP.sm, 0)
	f.show.dpGround = "surface"
	W.SetTooltip(f.show, L["Show"], L["Opens this page in the Notes window (/dp notes)."])
	f.post = W.Button(f, L["Post to chat"], "outline", function()
		local page = selected()
		if page then
			ns.NotesFrame.PostToChat(plan(), page)
		end
	end)
	f.post:SetPoint("LEFT", f.show, "RIGHT", SP.sm, 0)
	f.post.dpGround = "surface"
	W.SetTooltip(f.post, L["Post to chat"], L["Posts this page to your group chat, one line at a time. Raid icons show in chat; names are plain."])

	f.hint = W.Paragraph(f, "caption", "muted")
	f.hint:SetPoint("BOTTOMLEFT", f.send, "TOPLEFT", 0, SP.sm)
	f.hint:SetPoint("RIGHT")
	f.hint:SetText(
		L["Keywords: {tank} {healer} {dps}, {group 1}, {star} {circle} {diamond} {triangle} {moon} {square} {cross} {skull}, {mage}. Your lines are marked."])

	f.text = W.MultiLine(f, {
		maxBytes = Schema.TEXT.page,
		onCommit = function(text)
			update({ text = text })
		end,
	})
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -SP.sm)
	f.text:SetPoint("RIGHT")
	f.text:SetPoint("BOTTOM", f.hint, "TOP", 0, SP.sm)

	f.empty = W.Paragraph(f, "body", "muted")
	f.empty:SetPoint("TOPLEFT", 0, ROW2)
	f.empty:SetPoint("RIGHT")

	function f:Refresh()
		local p = plan()
		if not p then
			return
		end
		local list = Pages.List(p)
		if selectedId and not Pages.Find(p, selectedId) then
			selectedId = nil
		end
		selectedId = selectedId or (list[1] and list[1].id)
		local page = selected()
		local ro = ctx:ReadOnly()
		self.pick:Refresh()
		placePick(ro)
		self.add:SetShown(not ro)
		self.delete:SetShown(not ro and page ~= nil)
		self.pick:SetShown(#list > 0)
		local editing = page ~= nil and not ro
		self.title:SetShown(editing)
		self.boss:SetShown(editing)
		self.text:SetShown(editing)
		self.hint:SetShown(editing)
		for _, b in ipairs({ self.send, self.show, self.post }) do
			b:SetShown(page ~= nil)
		end
		self.empty:SetShown(not editing)
		if ro then
			self.empty:SetText(#list > 0 and L["A recommended plan's pages can be shown and sent, not changed."]
				or L["Recommended plans have no raid pages. Make an editable copy to write some."])
		elseif not page then
			self.empty:SetText(
				L["Raid pages: who does what, per boss or phase, with keywords. Tie a page to a boss and send it: it opens in the group's Notes windows on that pull."])
		end
		if editing then
			self.title:SetValue(page.title)
			self.boss:Refresh()
			if not self.text.edit:HasFocus() then
				self.text:SetValue(page.text)
			end
		end
	end
	return f
end
