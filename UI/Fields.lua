-- The widget kit, part 1b: text fields (one line and several), check boxes, dropdowns and menus. Part 1 (UI/Widgets.lua)
-- has text, tooltips, panels, section headers and buttons; part 1c (UI/Tabs.lua) the tabs. All fill ns.Widgets.

local _, ns = ...
local W = ns.Widgets
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE
local clamp = ns.Util.Clamp

-- Inputs -----------------------------------------------------------------------------------------------------------------
-- Every field shows its border: a near-black field with the bronze edge that brightens on hover and focus.

local function paintField(holder)
	local edit = holder.edit
	local active = edit:HasFocus() or holder.dpHover
	S.PaintBackdrop(holder, "field", active and "borderHover" or "border")
	-- A search field keeps its placeholder while it is empty, focused or not (a picker focuses its search on open);
	-- other fields hide it on focus.
	if holder.placeholder then
		holder.placeholder:SetShown(edit:GetText() == "" and (holder.dpSearch or not edit:HasFocus()))
	end
	if holder.clear then
		holder.clear:SetShown(edit:GetText() ~= "")
	end
end

-- Pending text. In the game a click on a button, a list row or the map does not take the keyboard focus from a field,
-- so text typed for one item would still be in the field, uncommitted, after another item was selected, and would then
-- be written into that one. W.CommitFocus() commits the field being edited (its focus loss does) while its item is
-- still the selected one: called before every selection change (buttons, list rows, the map, UI.SelectPlan), and on
-- any mouse press outside the field where the client reports those (GLOBAL_MOUSE_DOWN, inferred, guarded).
local focusWatch

function W.CommitFocus()
	local edit = W.focusedField
	if edit and edit:HasFocus() then
		edit:ClearFocus()
	end
end

local function watchFocus(edit)
	W.focusedField = edit
	if not focusWatch then
		focusWatch = CreateFrame("Frame")
		focusWatch:SetScript("OnEvent", function()
			local e = W.focusedField
			if e and not (e.dpHolder and e.dpHolder:IsMouseOver()) then
				W.CommitFocus()
			end
		end)
	end
	pcall(focusWatch.RegisterEvent, focusWatch, "GLOBAL_MOUSE_DOWN")
end

local function unwatchFocus(edit)
	if W.focusedField == edit then
		W.focusedField = nil
		if focusWatch then
			pcall(focusWatch.UnregisterEvent, focusWatch, "GLOBAL_MOUSE_DOWN")
		end
	end
end

local function fieldScripts(holder, edit, opts)
	edit.dpHolder = holder
	edit:SetScript("OnEscapePressed", function(self)
		-- SetText does not report as the user's input, so a field that filters as you type (onChange) is told here.
		local back = holder.dpCommitted or ""
		local changed = self:GetText() ~= back
		self:SetText(back)
		self:ClearFocus()
		if changed and opts.onChange then
			ns.SafeCall(opts.onChange, back)
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		if opts.onCommit and not opts.readOnly then
			watchFocus(self)
		end
		paintField(holder)
	end)
	edit:SetScript("OnEditFocusLost", function(self)
		unwatchFocus(self)
		paintField(holder)
		local text = self:GetText()
		if text ~= holder.dpCommitted then
			holder.dpCommitted = text
			if opts.onCommit then
				ns.SafeCall(opts.onCommit, text)
			end
		end
	end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		paintField(holder)
		if userInput and opts.onChange then
			ns.SafeCall(opts.onChange, self:GetText())
		end
	end)
	edit:SetScript("OnEnter", function()
		holder.dpHover = true
		paintField(holder)
	end)
	edit:SetScript("OnLeave", function()
		holder.dpHover = false
		paintField(holder)
	end)
end

-- opts: width, maxBytes, numeric, placeholder, onCommit(text), onChange(text), search (magnifier and clear button),
-- onSubmit(text): Enter only (an "add" field: leaving it, or clicking elsewhere, adds nothing; holder:Submit() for its
-- button).
function W.Input(parent, opts)
	opts = opts or {}
	local holder = Art.CreateFrame("Frame", opts.name, parent, "BackdropTemplate")
	holder:SetHeight(SZ.control)
	if opts.width then
		holder:SetWidth(opts.width)
	end
	S.Backdrop(holder, "panel", "field", "border")
	S.Register(holder, paintField)

	local left = SP.sm
	holder.dpSearch = opts.search and true or nil
	if opts.search then
		holder.icon = holder:CreateTexture(nil, "ARTWORK")
		holder.icon:SetSize(14, 14)
		holder.icon:SetPoint("LEFT", SP.sm, 0)
		Art.Set(holder.icon, "search")
		holder.icon:SetVertexColor(0.8, 0.75, 0.65)
		left = SP.sm + 14 + SP.xs
	end

	local edit = CreateFrame("EditBox", nil, holder)
	edit:SetPoint("TOPLEFT", left, 0)
	edit:SetPoint("BOTTOMRIGHT", -(opts.search and SZ.small + 2 or SP.sm), 0) -- left of the clear button (it keeps 2 px)
	edit:SetFontObject(S.fonts.body)
	S.TextColor(edit, "white")
	edit:SetAutoFocus(false)
	edit:SetMaxBytes(opts.maxBytes or 255)
	if opts.numeric then
		edit:SetNumeric(true)
	end
	holder.edit = edit

	if opts.placeholder then
		holder.placeholder = W.Text(holder, "body", "dim")
		holder.placeholder:SetPoint("LEFT", left, 0)
		holder.placeholder:SetPoint("RIGHT", -SP.sm, 0)
		holder.placeholder:SetText(opts.placeholder)
	end
	if opts.search then
		holder.clear = W.IconButton(holder, "x", nil, function()
			edit:SetText("")
			edit:ClearFocus()
			holder.dpCommitted = ""
			if opts.onChange then
				ns.SafeCall(opts.onChange, "")
			end
			paintField(holder)
		end)
		holder.clear:SetSize(SZ.small, SZ.small)
		holder.clear:SetPoint("RIGHT", -2, 0)
	end

	function holder:Submit()
		if opts.onSubmit then
			ns.SafeCall(opts.onSubmit, ns.Util.Trim(self.edit:GetText() or ""))
		end
	end
	edit:SetScript("OnEnterPressed", function(self)
		holder:Submit()
		self:ClearFocus()
	end)
	fieldScripts(holder, edit, opts)

	-- Set the text without calling onCommit.
	-- While the field is being typed in, a refresh with the same value leaves the typed text alone; a different
	-- value means the item under the field changed, and the typed text goes rather than land in the new item.
	function holder:SetValue(text)
		text = text or ""
		local same = text == self.dpCommitted
		self.dpCommitted = text
		if not (self.edit:HasFocus() and same) then
			self.edit:SetText(text)
			self.edit:SetCursorPosition(0)
		end
		paintField(self)
	end
	function holder:GetValue()
		return self.edit:GetText()
	end
	-- Item links shift-clicked while this field has focus land here through the game's own edit-box handling; we never
	-- hook Blizzard's link insertion.
	paintField(holder)
	return holder
end

-- A scrolling multi-line field.
function W.MultiLine(parent, opts)
	opts = opts or {}
	local holder = Art.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	S.Backdrop(holder, "panel", "field", "border")
	S.Register(holder, paintField)
	holder:EnableMouse(true)

	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetPoint("TOPLEFT", SP.sm, -SP.sm)
	scroll:SetPoint("BOTTOMRIGHT", -SP.sm, SP.sm)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(S.fonts.body)
	S.TextColor(edit, opts.readOnly and "muted" or "white")
	edit:SetMaxBytes(opts.maxBytes or 4000)
	edit:SetWidth(200)
	edit:SetHeight(20)
	scroll:SetScrollChild(edit)
	holder.edit, holder.scroll = edit, scroll

	scroll:SetScript("OnSizeChanged", function(_, w)
		edit:SetWidth(math.max(20, w))
	end)
	-- Keep the cursor in view while typing.
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
		local top = -y
		local visible = scroll:GetHeight()
		local current = scroll:GetVerticalScroll()
		if top < current then
			scroll:SetVerticalScroll(top)
		elseif top + h > current + visible then
			scroll:SetVerticalScroll(top + h - visible)
		end
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, edit:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(clamp(self:GetVerticalScroll() - delta * 40, 0, maxScroll))
	end)
	holder:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	fieldScripts(holder, edit, opts)
	if opts.readOnly then
		-- Export boxes: selectable, not editable. Any typing restores the text; focus selects everything for Ctrl+C.
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(holder.dpCommitted or "")
				self:HighlightText()
			end
		end)
		edit:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
			paintField(holder)
		end)
	end

	-- As W.Input's: a refresh of the page (a boss kill, a plan arriving) must not throw away what is being typed.
	function holder:SetValue(text)
		text = text or ""
		if self.edit:HasFocus() and text == self.dpCommitted then
			return
		end
		self.dpCommitted = text
		self.edit:SetText(text)
		self.edit:SetCursorPosition(0)
		self.scroll:SetVerticalScroll(0)
		paintField(self)
	end
	function holder:GetValue()
		return self.edit:GetText()
	end
	paintField(holder)
	return holder
end

-- Checkbox ---------------------------------------------------------------------------------------------------------------
-- The game's check box art; clicking the label ticks it too.

function W.Check(parent, label, onToggle)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(SZ.small)
	local box = b:CreateTexture(nil, "ARTWORK")
	box:SetSize(SZ.small + 2, SZ.small + 2)
	box:SetPoint("LEFT", -2, 0)
	Art.Set(box, "checkboxUp")
	local mark = b:CreateTexture(nil, "OVERLAY")
	mark:SetAllPoints(box)
	Art.Set(mark, "checkboxCheck")
	local glow = b:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints(box)
	Art.Set(glow, "checkboxHighlight")
	glow:SetBlendMode("ADD")
	b.label = W.Text(b, "body", "ink")
	b.label:SetPoint("LEFT", box, "RIGHT", SP.xxs, 0)
	b.label:SetText(label or "")
	b:SetWidth(SZ.small + SP.xxs + math.ceil(b.label:GetStringWidth())) -- the hit area ends with the text

	function b:SetChecked(v)
		self.dpChecked = v and true or false
		mark:SetShown(self.dpChecked)
	end
	function b:GetChecked()
		return self.dpChecked
	end
	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.dpChecked)
		if PlaySound and SOUNDKIT then
			local sound = self.dpChecked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
			if sound then
				pcall(PlaySound, sound)
			end
		end
		if onToggle then
			ns.SafeCall(onToggle, self.dpChecked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		S.TextColor(self.label, "white")
	end)
	b:SetScript("OnLeave", function(self)
		S.TextColor(self.label, "ink")
	end)
	b:SetChecked(false)
	return b
end

-- Menu entries in our font (MenuUtil element initializers; guarded: without them the menu keeps the game's font).
local function menuFont(desc)
	if type(desc) == "table" and desc.AddInitializer then
		pcall(desc.AddInitializer, desc, function(frame)
			local fs = frame and frame.fontString
			if fs and fs.SetFontObject then
				fs:SetFontObject(S.fonts.body)
			end
		end)
	end
	return desc
end
W.MenuFont = menuFont

-- Dropdown ---------------------------------------------------------------------------------------------------------------
-- A steel plate with the value and a caret; the list is our opaque popup (UI/Popup.lua), keyboard included.
-- opts: width, options() -> { { text, value } }, get() -> value, set(value), placeholder; open(button) replaces the
-- list with a popup of the caller's own (the instance picker).
local MENU_ROW = SZ.control

local function menuItemCreate(f)
	f.label = W.Text(f, "body", "ink")
	f.label:SetPoint("LEFT", SP.md, 0)
	f.label:SetPoint("RIGHT", -SP.sm, 0)
end

local function menuItemUpdate(f, row, current)
	W.FitText(f.label, row.text or "")
	S.TextColor(f.label, current and "goldBright" or "ink")
end

function W.Dropdown(parent, opts)
	local b = W.Button(parent, "", "outline", nil, opts.width or 160)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", SP.sm, 0)
	b.label:SetPoint("RIGHT", -SP.xl, 0)
	b.dpValueLabel = true
	b.dpOptions = opts.options -- what it lists (callers size it to its longest option)
	local caret = b:CreateTexture(nil, "ARTWORK")
	caret:SetSize(12, 12)
	caret:SetPoint("RIGHT", -SP.sm, -1)
	Art.Set(caret, "caret")
	b.caret = caret

	function b:Refresh()
		local current = opts.get()
		local text = opts.placeholder or ""
		for _, opt in ipairs(opts.options()) do
			if opt.value == current then
				text = opt.text
				break
			end
		end
		W.FitText(self.label, text)
	end

	b:SetScript("OnClick", function(self)
		if opts.open then
			ns.SafeCall(opts.open, self)
			return
		end
		local rows = {}
		for _, opt in ipairs(opts.options()) do
			rows[#rows + 1] = { kind = "item", text = opt.text, value = opt.value }
		end
		if #rows == 0 then
			return
		end
		W.OpenPopup(self, {
			style = "menu",
			rowHeight = MENU_ROW,
			maxHeight = 12 * MENU_ROW + 2 * SP.sm,
			rows = function()
				return rows
			end,
			isCurrent = function(row)
				return opts.get() == row.value
			end,
			createItem = menuItemCreate,
			updateItem = menuItemUpdate,
			onChoose = function(row)
				ns.SafeCall(opts.set, row.value)
				self:Refresh()
			end,
		})
	end)
	b:Refresh()
	return b
end

-- A menu of actions at the cursor: items = { { text, fn } | "-" | { title = text } }.
function W.Menu(owner, items)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, item in ipairs(items) do
				if item == "-" then
					root:CreateDivider()
				elseif item.title then
					menuFont(root:CreateTitle(item.title))
				else
					menuFont(root:CreateButton(item[1], function()
						ns.SafeCall(item[2])
					end))
				end
			end
		end)
		return true
	end
	return false
end
