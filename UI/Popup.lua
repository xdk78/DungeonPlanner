-- The widget kit, part 3: the popup list behind every dropdown and the instance picker. One opaque panel in the game's
-- menu look (Style.MenuBackground; else a dark fill with a gold edge), anchored under the control that opened it
-- (above it when there is no room below), in the FULLSCREEN_DIALOG strata so the window's map, its pins and labels
-- never show through or over it.
--
--   W.OpenPopup(owner, spec)  open (or, for the same owner, close) the popup; returns it
--   W.ClosePopup()            close it
--   W.ActivePopup()           the open popup, or nil
--
-- spec: style (rows are pooled per style), width?, height? (fixed) or maxHeight?, rowHeight, headerHeight?,
--   search? = { placeholder }, tabs? = { { id, text, art? } }, tab?, rows(query, tab) -> rows, counts?,
--   pickTab?(tab, counts) -> tab, isCurrent(row), onChoose(row), createItem(frame), updateItem(frame, row, current),
--   createHeader?(frame), updateHeader?(frame, row), empty? text.
-- rows = { { kind = "item" | "header", ... } }; only items take the cursor.
--
-- The list is virtual: rows of mixed heights are laid out by offset and only the visible ones get a frame from the
-- pool. One highlight: the cursor (the game's list hover), moved by the pointer and the keyboard alike; the
-- current choice carries a gold bar on its left and bright text. Keys: Up / Down, Page Up / Down, Home / End, Enter,
-- Escape, Tab (next section); typing goes to the search field. A click anywhere else closes it (GLOBAL_MOUSE_DOWN; a
-- full-screen catcher where the client lacks that event), as does hiding the control that opened it.

local _, ns = ...
local W = ns.Widgets
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE
local Picker = ns.Picker

local THUMB_ROOM = 10 -- the scroll thumb's lane on the right
local popup

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function inCombat()
	return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

local function hideTips(owner)
	for _, tt in ipairs({ GameTooltip, W.Tip() }) do
		if tt and tt.IsOwned and tt:IsOwned(owner) then
			tt:Hide()
		end
	end
end

-- Pooled rows ----------------------------------------------------------------------------------------------------------

-- The cursor: the game's list hover (Options_List_Hover, as the game's menus and settings list light the entry under
-- the pointer) where the client has it, else an amber fill with a gold edge. The current choice: a gold bar.
local function paintItem(f, cursor, current)
	if f.cursorTex then
		f.cursorTex:SetShown(cursor and true or false)
	elseif cursor then
		S.PaintBackdrop(f, "selected", "borderSelected")
	else
		S.PaintBackdrop(f, false, false)
	end
	f.mark:SetShown(current and true or false)
end

local function makeItem(p)
	local f = Art.CreateFrame("Button", nil, p.view, "BackdropTemplate")
	f:RegisterForClicks("LeftButtonUp")
	S.Backdrop(f, "panel", false, false)
	if Art.HasAtlas(Art.SPECS.listHover.atlas) then
		f.cursorTex = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		f.cursorTex:SetPoint("TOPLEFT", 1, -1)
		f.cursorTex:SetPoint("BOTTOMRIGHT", -1, 1)
		Art.Set(f.cursorTex, "listHover")
		f.cursorTex:Hide()
	end
	f.mark = f:CreateTexture(nil, "ARTWORK", nil, 5)
	f.mark:SetColorTexture(1, 1, 1, 1)
	S.Tint(f.mark, "borderSelected")
	f.mark:SetPoint("TOPLEFT", 3, -3)
	f.mark:SetPoint("BOTTOMLEFT", 3, 3)
	f.mark:SetWidth(3)
	f.mark:Hide()
	S.Register(f, function(row)
		S.PaintBackdrop(row)
	end)
	f:SetScript("OnEnter", function(self)
		if self.index and p.cursor ~= self.index then
			p:SetCursor(self.index)
		end
		-- A name cut to fit (W.FitText) shows whole in a tooltip.
		W.FullTextTooltip(self, self.name or self.label)
	end)
	f:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	f:SetScript("OnClick", function(self)
		if self.index then
			p:Choose(self.index)
		end
	end)
	p.spec.createItem(f)
	return f
end

local function makeHeader(p)
	local f = CreateFrame("Frame", nil, p.view)
	f:EnableMouse(false)
	if p.spec.createHeader then
		p.spec.createHeader(f)
	end
	return f
end

-- The popup ------------------------------------------------------------------------------------------------------------

local Popup = {}

function Popup:Height(row)
	return row.kind == "header" and (self.spec.headerHeight or 18) or self.spec.rowHeight
end

-- Rows for the current query and tab (the tab may change when the search finds nothing in it).
function Popup:Rebuild(keepCursor)
	local spec = self.spec
	local rows, counts = spec.rows(self.query, self.tab)
	if spec.pickTab and counts then
		local tab = spec.pickTab(self.tab, counts)
		if tab ~= self.tab then
			self.tab = tab
			rows, counts = spec.rows(self.query, self.tab)
		end
	end
	self.rows, self.counts = rows or {}, counts
	self.tops, self.total = {}, 0
	for i, row in ipairs(self.rows) do
		self.tops[i] = self.total
		self.total = self.total + self:Height(row)
	end
	if not keepCursor then
		local cursor
		if self.query == "" and spec.isCurrent then
			for i, row in ipairs(self.rows) do
				if row.kind == "item" and spec.isCurrent(row) then
					cursor = i
					break
				end
			end
		end
		self.cursor = cursor or Picker.Step(self.rows, nil, 1)
		self.scroll = 0
	end
	self:UpdateTabs()
end

function Popup:UpdateTabs()
	local bar = self.tabBar
	if not bar then
		return
	end
	bar:Select(self.tab)
	for _, b in ipairs(bar.buttons) do
		local text = b.dpBaseText
		local n = self.counts and self.counts[b.id]
		if self.query ~= "" and n then
			text = text .. "  |cff9aa3ad" .. n .. "|r"
		end
		b:SetLabel(text)
	end
end

-- How far the list scrolls. Under 2 pixels over is rounding, not a hidden row: such a list fits, shows no scroll bar.
function Popup:MaxScroll()
	local over = self.total - self.view:GetHeight()
	return over >= 2 and over or 0
end

-- Scroll so row i is in view (with the band header right above it, when there is one).
function Popup:Reveal(i)
	if not i or not self.tops[i] then
		return
	end
	local top = self.tops[i]
	if i > 1 and self.rows[i - 1].kind == "header" then
		top = self.tops[i - 1]
	end
	local bottom = self.tops[i] + self:Height(self.rows[i])
	local h = self.view:GetHeight()
	if top < self.scroll then
		self.scroll = top
	elseif bottom > self.scroll + h then
		self.scroll = bottom - h
	end
end

function Popup:Render()
	local spec = self.spec
	local pool = self.pools[spec.style]
	local viewH = self.view:GetHeight()
	local maxScroll = self:MaxScroll()
	self.scroll = clamp(self.scroll or 0, 0, maxScroll)
	local width = self.view:GetWidth() - (maxScroll > 0 and THUMB_ROOM or 0)
	local used = { item = 0, header = 0 }
	for i, row in ipairs(self.rows) do
		local top, h = self.tops[i], self:Height(row)
		if top + h > self.scroll and top < self.scroll + viewH then
			local kind = row.kind == "header" and "header" or "item"
			used[kind] = used[kind] + 1
			local f = pool[kind][used[kind]]
			if not f then
				f = kind == "header" and makeHeader(self) or makeItem(self)
				pool[kind][used[kind]] = f
			end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, -(top - self.scroll))
			f:SetSize(width, h)
			f.index, f.row = i, row
			f:Show()
			if kind == "header" then
				if spec.updateHeader then
					spec.updateHeader(f, row)
				end
			else
				local current = spec.isCurrent ~= nil and spec.isCurrent(row) or false
				f.current = current
				spec.updateItem(f, row, current)
				paintItem(f, i == self.cursor, current)
			end
		end
	end
	for style, p in pairs(self.pools) do
		for kind, list in pairs(p) do
			local keep = style == spec.style and used[kind] or 0
			for j = keep + 1, #list do
				list[j]:Hide()
				list[j].index, list[j].row = nil, nil
			end
		end
	end
	self.empty:SetShown(#self.rows == 0)
	self.thumb:Sync()
	if maxScroll <= 0 then
		self.thumb:Hide() -- a list that fits has no bar, whatever the bar template did on its own
	end
end

-- Move the one highlight to row i (pointer or keys); only the shown rows repaint.
function Popup:SetCursor(i, reveal)
	self.cursor = i
	if reveal then
		self:Reveal(i)
		self:Render()
		return
	end
	for _, f in ipairs(self.pools[self.spec.style].item) do
		if f:IsShown() and f.index then
			paintItem(f, f.index == i, f.current)
		end
	end
end

function Popup:Move(delta)
	local i = Picker.Step(self.rows, self.cursor, delta)
	if i then
		self:SetCursor(i, true)
	end
end

function Popup:PageItems()
	return math.max(1, math.floor(self.view:GetHeight() / self.spec.rowHeight) - 1)
end

function Popup:Choose(i)
	local row = self.rows[i or self.cursor]
	if not row or row.kind ~= "item" then
		return
	end
	local spec = self.spec
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
	self:Close()
	ns.SafeCall(spec.onChoose, row)
end

function Popup:SelectTab(id)
	if not self.tabBar or id == self.tab then
		return
	end
	self.tab = id
	self:Rebuild()
	self:Reveal(self.cursor)
	self:Render()
	if self.spec.search then
		self.search.edit:SetFocus()
	end
end

function Popup:NextTab()
	local tabs = self.spec.tabs
	if not tabs then
		return false
	end
	for i, t in ipairs(tabs) do
		if t.id == self.tab then
			self:SelectTab(tabs[i % #tabs + 1].id)
			return true
		end
	end
	return false
end

function Popup:SetQuery(text)
	self.query = text or ""
	self:Rebuild()
	self:Render()
end

-- A key: true when the popup used it.
function Popup:HandleKey(key)
	if key == "UP" then
		self:Move(-1)
	elseif key == "DOWN" then
		self:Move(1)
	elseif key == "PAGEUP" then
		self:Move(-self:PageItems())
	elseif key == "PAGEDOWN" then
		self:Move(self:PageItems())
	elseif key == "HOME" and not self.spec.search then
		self:Move(-#self.rows)
	elseif key == "END" and not self.spec.search then
		self:Move(#self.rows)
	elseif key == "ENTER" then
		self:Choose()
	elseif key == "ESCAPE" then
		self:Close()
	elseif key == "TAB" then
		return self:NextTab()
	else
		return false
	end
	return true
end

-- Back to closed: events, the click catcher, the keyboard, the opening control. Once per opening (dpOpen), from Close or
-- from OnHide, whichever comes first: while the whole UI is hidden (Alt+Z) a Hide fires no OnHide.
local function finish(p)
	if not p.dpOpen then
		return
	end
	p.dpOpen = nil
	p:UnregisterAllEvents()
	p.catcher:Hide()
	p:EnableKeyboard(false)
	p.search.edit:ClearFocus()
	local owner = p.owner
	p.owner = nil
	if owner then
		owner.dpPopupOpen = nil
		if owner.SetActive then
			owner:SetActive(false)
		end
	end
end

function Popup:Close()
	if self:IsShown() then
		self:Hide()
	end
	finish(self)
end

-- Build ---------------------------------------------------------------------------------------------------------------

local function build()
	local p = Art.CreateFrame("Frame", "DungeonPlannerPopup", UIParent, "BackdropTemplate")
	for k, fn in pairs(Popup) do
		p[k] = fn
	end
	p:Hide()
	p:SetFrameStrata("FULLSCREEN_DIALOG")
	p:SetToplevel(true)
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	-- The game's menu panel (Style.MenuBackground) over an opaque fill; else the fill with a gold edge.
	S.Backdrop(p, "panel", "menu", "borderHover")
	p.shadowX, p.shadowY = 0, 0
	if S.MenuBackground(p) then
		-- The menu art fills the frame, its shadow included; an opaque fill sits under its panel only.
		S.PaintBackdrop(p, false, false)
		p.shadowX, p.shadowY = S.MENU_SHADOW.x, S.MENU_SHADOW.y
		p.fill = p:CreateTexture(nil, "BACKGROUND", nil, -8)
		p.fill:SetColorTexture(1, 1, 1, 1)
		p.fill:SetPoint("TOPLEFT", p.shadowX, -p.shadowY)
		p.fill:SetPoint("BOTTOMRIGHT", -p.shadowX, p.shadowY)
		S.Tint(p.fill, "menu")
	end
	S.Register(p, function(f)
		S.PaintBackdrop(f)
	end)
	p.pools, p.tabBars = {}, {}
	p.query, p.scroll, p.total, p.rows, p.tops = "", 0, 0, {}, {}

	p.search = W.Input(p, {
		search = true,
		maxBytes = 64,
		onChange = function(text)
			p:SetQuery(text)
		end,
	})
	local edit = p.search.edit
	edit:SetScript("OnEnterPressed", function()
		p:Choose()
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		p:Close()
	end)
	edit:SetScript("OnTabPressed", function()
		p:NextTab()
	end)
	edit:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" or key == "DOWN" then
			p:HandleKey(key)
		end
	end)
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "PAGEUP" or key == "PAGEDOWN" then
			p:HandleKey(key)
		end
	end)
	p.search:Hide()

	p.rule = S.Hairline(p)

	p.view = CreateFrame("Frame", nil, p)
	if p.view.SetClipsChildren then
		p.view:SetClipsChildren(true)
	end
	p.view:EnableMouseWheel(true)
	p.view:SetScript("OnMouseWheel", function(_, delta)
		p.scroll = clamp(p.scroll - delta * 3 * p.spec.rowHeight, 0, p:MaxScroll())
		p:Render()
	end)
	p.thumb = W.AttachThumb(p.view, function()
		return p:MaxScroll(), p.view:GetHeight()
	end, function()
		return p.scroll
	end, function(v)
		p.scroll = v
		p:Render()
	end)
	p.empty = W.Paragraph(p.view, "body", "muted")
	p.empty:SetPoint("TOPLEFT", SP.sm, -SP.sm)
	p.empty:SetPoint("RIGHT", -SP.sm, 0)

	-- Width of the longest text row (dropdowns size to their options).
	p.measure = W.Text(p, "body", "ink")
	p.measure:Hide()

	-- Keys without a search field: the popup takes the keyboard, passing on every key it does not use (out of combat;
	-- a combat that starts while it is open closes it, so it never holds keys it can no longer pass on).
	p:SetScript("OnKeyDown", function(self, key)
		local used = self:HandleKey(key)
		if self.SetPropagateKeyboardInput and not inCombat() then
			pcall(self.SetPropagateKeyboardInput, self, not used)
		end
	end)

	-- A click anywhere else closes; the opening control's own click toggles it instead.
	p:SetScript("OnEvent", function(self, event)
		if event == "GLOBAL_MOUSE_DOWN" then
			if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then
				return
			end
			self:Close()
		elseif event == "PLAYER_REGEN_DISABLED" then
			self:Close()
		end
	end)
	p.catcher = CreateFrame("Button", nil, UIParent)
	p.catcher:SetAllPoints(UIParent)
	p.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	p.catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.catcher:SetScript("OnClick", function()
		p:Close()
	end)
	p.catcher:Hide()

	p:SetScript("OnHide", function(self)
		-- The whole UI hidden (Alt+Z) leaves the list open as it was; it shows again with the UI.
		if W.Hidden(self) then
			finish(self)
		end
	end)
	-- In combat the list has no keyboard, so Escape reaches the game: it closes the list first, not the window.
	W.CloseOnEscape(p)
	return p
end

local function tabBar(p, spec)
	local bar = p.tabBars[spec.style]
	if not bar then
		local items = {}
		for i, t in ipairs(spec.tabs) do
			items[i] = { id = t.id, text = t.text, art = t.art }
		end
		bar = W.Tabs(p, items, function(id)
			p:SelectTab(id)
		end, { equal = true })
		for i, b in ipairs(bar.buttons) do
			b.dpBaseText = spec.tabs[i].text
		end
		p.tabBars[spec.style] = bar
	end
	return bar
end

-- Width for a list of text rows: the widest text plus padding, at least as wide as the control that opened it.
local function textWidth(p, spec, owner)
	local widest = 0
	for _, row in ipairs(spec.rows("", spec.tab) or {}) do
		if row.text then
			p.measure:SetText(row.text)
			widest = math.max(widest, math.ceil(p.measure:GetStringWidth()))
		end
	end
	return clamp(widest + 2 * SP.md + THUMB_ROOM + 2 * SP.sm, math.floor(owner:GetWidth() + 0.5), 420)
end

-- API -----------------------------------------------------------------------------------------------------------------

function W.ActivePopup()
	return popup and popup:IsShown() and popup or nil
end

function W.ClosePopup()
	if popup then
		popup:Close()
	end
end

function W.OpenPopup(owner, spec)
	popup = popup or build()
	local p = popup
	if p:IsShown() then
		local same = p.owner == owner
		p:Close()
		if same then
			return nil
		end
	end
	p.owner, p.spec, p.dpOpen = owner, spec, true
	p.query, p.scroll, p.tab = "", 0, spec.tab
	p.pools[spec.style] = p.pools[spec.style] or { item = {}, header = {} }
	hideTips(owner)
	owner.dpPopupOpen = true
	if owner.SetActive then
		owner:SetActive(true)
	end
	if not owner.dpPopupHooked then
		owner.dpPopupHooked = true
		owner:HookScript("OnHide", function(self)
			-- Not when the whole UI was hidden (Alt+Z): the list and its control come back together.
			if popup and popup.owner == self and not W.UIHidden() then
				popup:Close()
			end
		end)
	end

	-- `width` and `height` are the menu panel's; the frame adds the art's shadow around it (Style.MenuBackground).
	local width = spec.width or textWidth(p, spec, owner)
	local pad = SP.sm
	local sx, sy = p.shadowX, p.shadowY
	local padX = pad + sx
	local y = -(pad + sy)
	p.search:SetShown(spec.search ~= nil)
	if spec.search then
		p.search:ClearAllPoints()
		p.search:SetPoint("TOPLEFT", padX, y)
		p.search:SetPoint("RIGHT", -padX, 0)
		p.search:SetValue("")
		if p.search.placeholder then
			p.search.placeholder:SetText(spec.search.placeholder or "")
		end
		y = y - SZ.control - SP.xs
	end
	for style, bar in pairs(p.tabBars) do
		bar:SetShown(style == spec.style and spec.tabs ~= nil)
	end
	p.tabBar = nil
	if spec.tabs then
		local bar = tabBar(p, spec)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", padX, y)
		local each = math.floor((width - 2 * pad - SP.xxs * (#bar.buttons - 1)) / #bar.buttons)
		for i, b in ipairs(bar.buttons) do
			b:SetWidth(each)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", (i - 1) * (each + SP.xxs), 0)
		end
		bar:SetWidth(width - 2 * pad)
		p.tabBar = bar
		y = y - SZ.control - SP.xs
	end
	local chrome = -y - pad - sy
	p.rule:SetShown(chrome > 0)
	if chrome > 0 then
		p.rule:ClearAllPoints()
		p.rule:SetPoint("TOPLEFT", padX, y)
		p.rule:SetPoint("RIGHT", -padX, 0)
		y = y - SP.xs
	end
	p.empty:SetText(spec.empty or "")

	p:Rebuild()
	local top = -y - sy
	local height = spec.height or math.min(spec.maxHeight or 320, top + math.max(p.total, spec.rowHeight) + pad)
	p.view:ClearAllPoints()
	p.view:SetPoint("TOPLEFT", padX, y)
	p.view:SetWidth(width - 2 * pad)
	p.view:SetHeight(math.max(spec.rowHeight, height - top - pad))
	p:SetSize(width + 2 * sx, height + 2 * sy)

	-- Under the control, or above it when the screen has no room below; the panel (not its shadow) lines up with the
	-- control's left edge.
	p:ClearAllPoints()
	local bottom = owner:GetBottom()
	local ratio = (owner:GetEffectiveScale() or 1) / (p:GetEffectiveScale() or 1)
	if bottom and bottom * ratio < height + SP.sm then
		p:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -sx, SP.xxs - sy)
	else
		p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -sx, -SP.xxs + sy)
	end
	p:Show()

	if not pcall(p.RegisterEvent, p, "GLOBAL_MOUSE_DOWN") then
		p.catcher:SetFrameLevel(math.max(0, p:GetFrameLevel() - 1))
		p.catcher:Show()
	end
	local keys = not spec.search and not inCombat()
	p:EnableKeyboard(keys)
	if keys then
		if p.SetPropagateKeyboardInput then
			pcall(p.SetPropagateKeyboardInput, p, true)
		end
		pcall(p.RegisterEvent, p, "PLAYER_REGEN_DISABLED")
	end
	if spec.search then
		p.search.edit:SetFocus()
	end
	p:Reveal(p.cursor)
	if p.cursor and p.scroll > 0 then
		-- Open with the current choice in the middle of the list rather than at its edge.
		p.scroll = p.tops[p.cursor] - math.floor((p.view:GetHeight() - spec.rowHeight) / 2)
	end
	p:Render()
	return p
end
