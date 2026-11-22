-- The widget kit, part 2: containers. Scroll areas and virtual lists (with their scroll bars and row highlights), the
-- small pieces (badges, dots, labels, round icons, boss portraits, steppers). Part 1 (UI/Widgets.lua) has text,
-- panels, buttons, fields, check boxes, dropdowns, menus and tabs; part 4 (UI/Window.lua) the window and the dialogs.
-- All fill the same module, ns.Widgets.

local _, ns = ...
local W = ns.Widgets
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- The pointer's highlight on a list row: the game's list hover (Options_List_Hover) where the client has it, else the
-- quest-title glow, added at half strength. A HIGHLIGHT-layer texture, so the client shows it on hover by itself.
function W.RowHighlight(row)
	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetPoint("TOPLEFT", 2, -2)
	glow:SetPoint("BOTTOMRIGHT", -2, 2)
	Art.Set(glow, "listHover")
	if not Art.HasAtlas(Art.SPECS.listHover.atlas) then
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0.45)
	end
	return glow
end

-- Scroll bars -----------------------------------------------------------------------------------------------------------
-- W.AttachThumb(host, getRange, getValue, setValue) puts a scroll bar along host's right edge (inside the SP.md the
-- lists leave free) and returns it; bar:Sync() after the range or the value changed. getRange() -> range, visible
-- (in the host's own units: pixels or rows), getValue() -> 0..range, setValue(v) scrolls the host.
--
-- The game's minimal scroll bar (MinimalScrollBar: a slim track and thumb, as in the game's settings and lists) where
-- the client has it, driven by percentages: its own drag and wheel report OnScroll, which scrolls the host; our
-- updates move it without echoing back (a guard, and nothing sent when it already shows the value). Without it, a
-- slim gold thumb on a dark track, dragged with OnUpdate only while the mouse is down.

local function nativeBar(host, getRange, getValue, setValue)
	local events = rawget(_G, "BaseScrollBoxEvents")
	if type(events) ~= "table" or not events.OnScroll then
		return nil
	end
	local bar, templated = Art.CreateFrame("EventFrame", nil, host, "MinimalScrollBar")
	if not (templated and W.HasParts(bar, "Track") and type(bar.SetScrollPercentage) == "function"
			and type(bar.RegisterCallback) == "function"
			and type(bar.GetScrollPercentage) == "function" and type(bar.SetVisibleExtentPercentage) == "function") then
		bar:Hide()
		return nil
	end
	bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -2)
	bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -1, 2)
	bar:SetFrameLevel(host:GetFrameLevel() + 5)
	local quiet = false
	local ok = pcall(bar.RegisterCallback, bar, events.OnScroll, function()
		if quiet then
			return
		end
		local range = getRange()
		if range > 0 then
			local v = (bar:GetScrollPercentage() or 0) * range
			if math.abs(v - getValue()) >= 0.5 then
				setValue(clamp(v, 0, range))
			end
		end
	end, bar)
	if not ok then
		bar:Hide()
		return nil
	end
	bar.dpNative = true
	-- Named Sync, not Update: Update is the game's ScrollBarMixin method that its setters call to lay out the thumb.
	function bar:Sync()
		local range, visible = getRange()
		if range <= 0 or host:GetHeight() <= 0 then
			self:Hide()
			return
		end
		self:Show()
		quiet = true
		pcall(self.SetVisibleExtentPercentage, self, visible / (visible + range))
		if self.SetPanExtentPercentage then
			pcall(self.SetPanExtentPercentage, self, math.min(1, math.max(1, visible / 10) / range))
		end
		local pct = clamp(getValue() / range, 0, 1)
		if math.abs((self:GetScrollPercentage() or 0) * range - pct * range) >= 0.5 then
			pcall(self.SetScrollPercentage, self, pct, true)
		end
		quiet = false
	end
	bar:Hide()
	return bar
end

local function attachThumb(host, getRange, getValue, setValue)
	local native = nativeBar(host, getRange, getValue, setValue)
	if native then
		return native
	end
	local track = host:CreateTexture(nil, "BACKGROUND", nil, 2)
	track:SetColorTexture(0, 0, 0, 0.35)
	track:SetWidth(6)
	track:SetPoint("TOPRIGHT", -1, 0)
	track:SetPoint("BOTTOMRIGHT", -1, 0)
	track:Hide()

	local thumb = Art.CreateFrame("Button", nil, host, "BackdropTemplate")
	thumb:SetWidth(8)
	thumb:SetFrameLevel(host:GetFrameLevel() + 5)
	S.Backdrop(thumb, "thin", "buttonHover", "border")
	thumb:SetScript("OnEnter", function(self)
		S.PaintBackdrop(self, "selected", "borderHover")
	end)
	thumb:SetScript("OnLeave", function(self)
		S.PaintBackdrop(self, "buttonHover", "border")
	end)

	function thumb:Sync()
		local range, visible = getRange()
		local h = host:GetHeight()
		if range <= 0 or h <= 0 then
			self:Hide()
			track:Hide()
			return
		end
		self:Show()
		track:Show()
		local size = math.max(24, h * visible / (visible + range))
		local pos = (h - size) * (getValue() / range)
		self:SetHeight(size)
		self:ClearAllPoints()
		self:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -pos)
	end

	thumb:SetScript("OnMouseDown", function(self)
		local _, startY = GetCursorPosition()
		local startValue = getValue()
		local scale = self:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local range, visible = getRange()
			local h = host:GetHeight()
			local size = math.max(24, h * visible / (visible + range))
			local _, y = GetCursorPosition()
			local dy = (startY - y) / scale
			local length = h - size
			if length > 0 then
				setValue(clamp(startValue + dy / length * range, 0, range))
			end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	thumb:Hide()
	return thumb
end
W.AttachThumb = attachThumb

-- ScrollArea: a scrolling container for forms. Put children on area.content and call area:SetContentHeight(h).

function W.ScrollArea(parent)
	local area = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, area)
	content:SetSize(10, 10)
	area:SetScrollChild(content)
	area.content = content
	area:SetScript("OnSizeChanged", function(self, w)
		content:SetWidth(math.max(10, w - SP.md))
		if self.thumb then
			self.thumb:Sync()
		end
	end)
	local function range()
		return math.max(0, content:GetHeight() - area:GetHeight()), area:GetHeight()
	end
	area.thumb = attachThumb(area, range, function()
		return area:GetVerticalScroll()
	end, function(v)
		area:SetVerticalScroll(v)
		area.thumb:Sync()
	end)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(clamp(self:GetVerticalScroll() - delta * 48, 0, maxScroll))
		self.thumb:Sync()
	end)
	-- A real scroll frame: where the client has it, the game's own wiring (ScrollUtil.InitScrollFrameWithScrollBar,
	-- as the game's settings pages do) joins it to a MinimalScrollBar, which then follows the frame's range and
	-- offset by itself; the percentage bar above stands in otherwise.
	local util = rawget(_G, "ScrollUtil")
	if type(util) == "table" and type(util.InitScrollFrameWithScrollBar) == "function" then
		local bar, templated = Art.CreateFrame("EventFrame", nil, area, "MinimalScrollBar")
		bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -2)
		bar:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 2)
		if templated and W.HasParts(bar, "Track") and pcall(util.InitScrollFrameWithScrollBar, area, bar) then
			area.thumb:Hide()
			bar.dpNative, bar.dpScrollUtil = true, true
			bar.Sync = function() end -- the scroll frame reports to it
			area.thumb = bar
		else
			bar:Hide()
		end
	end
	function area:SetContentHeight(h)
		content:SetHeight(math.max(10, h))
		local maxScroll = math.max(0, h - self:GetHeight())
		if self:GetVerticalScroll() > maxScroll then
			self:SetVerticalScroll(maxScroll)
		end
		self.thumb:Sync()
	end
	return area
end

-- Document: read-only formatted text in a scroll area, as Dungeon Journal's detail pane (recommended plans show their
-- text this way instead of in input boxes). Build it with doc:Begin(), then doc:Add(style, text), doc:Space(px) and
-- doc:Place(frame, height or function(width)[, stretch]) in reading order, then doc:Finish(). Font strings are pooled; the layout reruns when the
-- area changes size. Styles: title, heading, label, text, muted.

local DOC_STYLES = {
	title = { "huge", "gold", 0 },
	heading = { "title", "gold", SP.lg },
	label = { "caption", "gold", SP.sm },
	text = { "body", "ink", SP.xs },
	muted = { "caption", "muted", SP.xs },
}

function W.Document(parent)
	local area = W.ScrollArea(parent)
	local content = area.content
	local pools, blocks, used = {}, {}, {}

	local function fontString(style)
		used[style] = (used[style] or 0) + 1
		pools[style] = pools[style] or {}
		local fs = pools[style][used[style]]
		if not fs then
			local spec = DOC_STYLES[style] or DOC_STYLES.text
			fs = W.Paragraph(content, spec[1], spec[2])
			pools[style][used[style]] = fs
		end
		return fs
	end

	local function layout()
		for _, pool in pairs(pools) do
			for _, fs in ipairs(pool) do
				fs:Hide()
			end
		end
		used = {}
		local width = math.max(40, (area:GetWidth() or 0) - SP.md - SP.sm)
		local y = 0
		for i, b in ipairs(blocks) do
			if b.space then
				y = y + b.space
			elseif b.frame then
				b.frame:ClearAllPoints()
				b.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				if b.stretch then
					b.frame:SetWidth(width)
				end
				b.frame:Show()
				y = y + (type(b.height) == "function" and b.height(width) or b.height)
			else
				local spec = DOC_STYLES[b.style] or DOC_STYLES.text
				if i > 1 then
					y = y + spec[3]
				end
				local fs = fontString(b.style)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				fs:SetWidth(width)
				fs:SetText(b.text)
				fs:Show()
				y = y + math.max(12, math.ceil(fs:GetStringHeight() or 12))
			end
		end
		area:SetContentHeight(y + SP.md)
	end

	function area:Begin()
		for _, b in ipairs(blocks) do
			if b.frame then
				b.frame:Hide()
			end
		end
		blocks = {}
		self:SetVerticalScroll(0)
	end
	function area:Add(style, text)
		if text and text ~= "" then
			blocks[#blocks + 1] = { style = style, text = text }
		end
	end
	function area:Space(px)
		blocks[#blocks + 1] = { space = px }
	end
	-- stretch: the frame is as wide as the text blocks (kept up when the area resizes). height: pixels, or
	-- function(width) -> pixels for a frame whose height follows its width (wrapped text).
	function area:Place(frame, height, stretch)
		blocks[#blocks + 1] = { frame = frame, height = height, stretch = stretch }
	end
	function area:Finish()
		layout()
	end
	area:HookScript("OnSizeChanged", function()
		if #blocks > 0 then
			layout()
		end
	end)
	return area
end

-- List -----------------------------------------------------------------------------------------------------------------------
-- A virtual list: only visible rows exist. opts: rowHeight, gap, create(row), update(row, item, index),
-- onClick(item, index, mouseButton, row), onDoubleClick(item, index, row), isSelected(item), empty, boxed.
-- One highlight per list: the selected row wears the game's list selection (Options_List_Active, the settings list's)
-- over an amber fill with a gold edge for boxed rows; where the atlas is missing, an amber fill, gold edge and a gold
-- bar on its left. The pointer adds the game's list hover (Options_List_Hover, else the quest-title glow).

local function paintRow(r)
	local selected = r.dpSelected and true or false
	if r.accent then
		r.accent:SetShown(selected and not r.selection)
	end
	if r.selection then
		r.selection:SetShown(selected)
	end
	if selected and r.selection and not r.dpBoxed then
		S.PaintBackdrop(r, false, false)
	elseif selected then
		S.PaintBackdrop(r, "selected", "borderSelected")
	elseif r.dpBoxed then
		S.PaintBackdrop(r, "raised", "border")
	else
		S.PaintBackdrop(r, false, false)
	end
end

function W.List(parent, opts)
	local list = CreateFrame("Frame", nil, parent)
	if list.SetClipsChildren then
		list:SetClipsChildren(true)
	end
	local gap = opts.gap or 0
	local rh = (opts.rowHeight or SZ.row) + gap
	list.items, list.offset, list.rows = {}, 0, {}

	list.emptyText = W.Paragraph(list, "body", "muted")
	list.emptyText:SetPoint("TOPLEFT", SP.md, -SP.md)
	list.emptyText:SetPoint("RIGHT", -SP.md, 0)
	list.emptyText:SetText(opts.empty or "")

	local function visibleCount()
		return math.max(1, math.floor((list:GetHeight() + gap) / rh))
	end
	local function maxOffset()
		return math.max(0, #list.items - visibleCount())
	end

	local function makeRow(i)
		local row = Art.CreateFrame("Button", nil, list, "BackdropTemplate")
		row:SetHeight(rh - gap)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rh)
		row:SetPoint("RIGHT", -SP.md, 0)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.dpBoxed = opts.boxed
		S.Backdrop(row, "panel", false, false)
		row.glow = W.RowHighlight(row)
		if Art.HasAtlas(Art.SPECS.listSelected.atlas) then
			row.selection = row:CreateTexture(nil, "BACKGROUND", nil, 2)
			row.selection:SetPoint("TOPLEFT", 2, -2)
			row.selection:SetPoint("BOTTOMRIGHT", -2, 2)
			Art.Set(row.selection, "listSelected")
			row.selection:Hide()
		end
		row.accent = row:CreateTexture(nil, "ARTWORK", nil, 5)
		row.accent:SetColorTexture(1, 1, 1, 1)
		S.Tint(row.accent, "borderSelected")
		row.accent:SetPoint("TOPLEFT", 3, -3)
		row.accent:SetPoint("BOTTOMLEFT", 3, 3)
		row.accent:SetWidth(3)
		row.accent:Hide()
		row.paint = paintRow
		S.Register(row, paintRow)
		row:SetScript("OnEnter", function(self)
			if opts.onEnter and self.item then
				ns.SafeCall(opts.onEnter, self.item, self)
			end
		end)
		row:SetScript("OnLeave", function(self)
			for _, tt in ipairs({ GameTooltip, W.Tip() }) do
				if tt and tt:IsOwned(self) then
					tt:Hide()
				end
			end
		end)
		row:SetScript("OnClick", function(self, mouse)
			W.CommitFocus()
			if self.item and opts.onClick then
				ns.SafeCall(opts.onClick, self.item, self.index, mouse, self)
			end
		end)
		if opts.onDoubleClick then
			row:SetScript("OnDoubleClick", function(self, mouse)
				if self.item and mouse ~= "RightButton" then
					ns.SafeCall(opts.onDoubleClick, self.item, self.index, self)
				end
			end)
		end
		if opts.create then
			opts.create(row)
		end
		paintRow(row)
		return row
	end

	function list:Refresh()
		local n = visibleCount() + 1
		for i = #self.rows + 1, n do
			self.rows[i] = makeRow(i)
		end
		self.offset = clamp(self.offset, 0, maxOffset())
		for i, row in ipairs(self.rows) do
			local index = self.offset + i
			local item = self.items[index]
			if item and i <= n then
				row.item, row.index = item, index
				row.dpSelected = opts.isSelected and opts.isSelected(item) or false
				row:Show()
				opts.update(row, item, index)
				paintRow(row)
			else
				row.item, row.index = nil, nil
				row:Hide()
			end
		end
		self.emptyText:SetShown(#self.items == 0)
		self.thumb:Sync()
	end

	function list:SetItems(items)
		self.items = items or {}
		self:Refresh()
	end

	function list:ScrollTo(index)
		local vis = visibleCount()
		if index <= self.offset then
			self.offset = index - 1
		elseif index > self.offset + vis then
			self.offset = index - vis
		end
		self:Refresh()
	end

	list.thumb = attachThumb(list, function()
		return maxOffset(), visibleCount()
	end, function()
		return list.offset
	end, function(v)
		list.offset = math.floor(v + 0.5)
		list:Refresh()
	end)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = clamp(self.offset - delta * 3, 0, maxOffset())
		self:Refresh()
	end)
	list:SetScript("OnSizeChanged", function(self)
		self:Refresh()
	end)
	return list
end

-- Small pieces ---------------------------------------------------------------------------------------------------------------

-- A count badge: a small dark pill with a gold edge.
function W.Badge(parent)
	local f = Art.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetHeight(18)
	S.Backdrop(f, "thin", "field", "border")
	f.text = W.Text(f, "caption", "gold")
	f.text:SetPoint("CENTER", 0, 0)
	function f:SetCount(n)
		self.text:SetText(tostring(n))
		self:SetWidth(math.max(18, math.ceil(self.text:GetStringWidth()) + SP.sm))
	end
	f:SetCount(0)
	return f
end

-- A small tag chip: caption text in bronze-gold on a dark pill with a bronze edge, a tooltip when hovered. The chip
-- takes the mouse only for hovering where the client allows it, so a click still reaches the row under it.
function W.Chip(parent, text, tipTitle, tipText)
	local f = Art.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetHeight(16)
	S.Backdrop(f, "thin", "field", "border")
	f.text = W.Text(f, "caption", "gold")
	f.text:SetPoint("CENTER", 0, 0)
	function f:SetLabel(s)
		self.text:SetText(s)
		self:SetWidth(math.max(16, math.ceil(self.text:GetStringWidth()) + SP.sm + 2))
	end
	f:SetLabel(text or "")
	if tipTitle and f.SetMouseClickEnabled and f.SetMouseMotionEnabled then
		f:EnableMouse(true)
		f:SetMouseClickEnabled(false)
		f:SetMouseMotionEnabled(true)
		W.SetTooltip(f, tipTitle, tipText)
	end
	return f
end

-- A 8 pt status dot (ok / info / warning / danger / dim).
function W.Dot(parent, status)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(S.MEDIA .. "Circle")
	tex:SetSize(8, 8)
	tex.dpStatus = status or "dim"
	S.Tint(tex, tex.dpStatus)
	S.Register(tex, function(t)
		S.Tint(t, t.dpStatus)
	end)
	function tex:SetStatus(s)
		self.dpStatus = s
		S.Tint(self, s)
	end
	return tex
end

-- A small gold label above a field.
function W.Label(parent, text)
	local fs = W.Text(parent, "caption", "gold")
	fs:SetText(text)
	return fs
end

-- A round icon (masked) inside the gold minimap ring, as Dungeon Journal draws its map pins. size = inner diameter.
function W.RoundIcon(parent, size, ringKey)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.icon = Art.RoundTexture(f, "ARTWORK", 0)
	f.icon:SetAllPoints()
	f.ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
	Art.PlaceRing(f.ring, f, size, ringKey or "pinRing")
	return f
end

-- A boss portrait: round face, the Adventure Guide's ring, and a number badge (Dungeon Journal's boss rows).
function W.Portrait(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.face = Art.RoundTexture(f, "ARTWORK", 0)
	f.face:SetAllPoints()
	f.ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
	Art.PlaceRing(f.ring, f, size, "bossRing")
	f.badge = CreateFrame("Frame", nil, f)
	local bs = math.max(18, math.floor(size * 0.42))
	f.badge:SetSize(bs, bs)
	f.badge:SetPoint("BOTTOMLEFT", -size * 0.12, -size * 0.12)
	f.badge:SetFrameLevel(f:GetFrameLevel() + 2)
	f.badge.bg = f.badge:CreateTexture(nil, "ARTWORK")
	f.badge.bg:SetTexture(S.MEDIA .. "Circle")
	f.badge.bg:SetAllPoints()
	f.badge.bg:SetVertexColor(0.08, 0.06, 0.04, 1)
	f.badge.ring = f.badge:CreateTexture(nil, "OVERLAY")
	f.badge.ring:SetTexture(S.MEDIA .. "Ring")
	f.badge.ring:SetAllPoints()
	S.Tint(f.badge.ring, "gold")
	f.badge.text = W.Text(f.badge, "number", "white")
	f.badge.text:SetPoint("CENTER", 0, 0)
	f.badge.text:SetJustifyH("CENTER")

	function f:SetBoss(art)
		Art.SetBossPortrait(self.face, art)
	end
	function f:SetBadge(text)
		self.badge:SetShown(text ~= nil and text ~= "")
		self.badge.text:SetText(text or "")
	end
	function f:SetDone(done)
		self.face:SetDesaturated(done and true or false)
		local model = self.face.dpModel -- a creature portrait on the face (UI/Art.lua) follows it
		if model and model.SetDesaturated then
			model:SetDesaturated(done and true or false)
		end
	end
	f:SetBadge(nil)
	return f
end

-- A "- 90% +" stepper (Dungeon Journal's "Boss icons" control). opts: get(), set(v), min, max, step, format(v).
function W.Stepper(parent, label, opts)
	local f = W.Panel(parent, "surface", "border")
	f:SetSize(112, 48)
	f.title = W.Text(f, "caption", "ink")
	f.title:SetPoint("TOP", 0, -SP.xs - 2)
	f.title:SetText(label)
	f.value = W.Text(f, "body", "white")
	f.value:SetPoint("BOTTOM", 0, SP.sm)
	f.value:SetJustifyH("CENTER")
	local function step(dir)
		local v = opts.get() + dir * opts.step
		v = clamp(math.floor(v / opts.step + 0.5) * opts.step, opts.min, opts.max)
		ns.SafeCall(opts.set, v)
		f:Refresh()
	end
	f.minus = W.Button(f, "-", "red", function()
		step(-1)
	end, 22)
	f.minus:SetHeight(20)
	f.minus:SetPoint("BOTTOMLEFT", SP.sm, SP.xs + 1)
	f.plus = W.Button(f, "+", "red", function()
		step(1)
	end, 22)
	f.plus:SetHeight(20)
	f.plus:SetPoint("BOTTOMRIGHT", -SP.sm, SP.xs + 1)
	function f:Refresh()
		local v = opts.get()
		self.value:SetText(opts.format and opts.format(v) or tostring(v))
		self.minus:SetDisabled(v <= opts.min + 1e-6)
		self.plus:SetDisabled(v >= opts.max - 1e-6)
	end
	f:Refresh()
	return f
end

-- Layout helper: place frames left to right with a gap, starting at (x, y) in parent.
function W.Row(parent, frames, x, y, gap)
	gap = gap or SP.sm
	for _, frame in ipairs(frames) do
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		x = x + frame:GetWidth() + gap
	end
	return x
end

-- A disclosure: a caret and a gold label that fold a section away (closed: the caret points right; open: down). For
-- options most players never need ("Advanced"), so the view stays short. onToggle(open) lays the view out again.
function W.Disclosure(parent, text, onToggle)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(SZ.small)
	b.caret = b:CreateTexture(nil, "ARTWORK")
	b.caret:SetSize(12, 12)
	b.caret:SetPoint("LEFT")
	Art.Set(b.caret, "caret")
	b.label = W.Text(b, "title", "gold")
	b.label:SetPoint("LEFT", b.caret, "RIGHT", SP.xs, 0)
	b.label:SetText(text or "")
	b:SetWidth(12 + SP.xs + math.ceil(b.label:GetStringWidth() or 0) + SP.xs)
	function b:SetOpen(open)
		self.dpOpen = open and true or false
		-- The caret art points down; a quarter turn makes it point right. Without SetRotation it stays down.
		if self.caret.SetRotation then
			self.caret:SetRotation(self.dpOpen and 0 or math.pi / 2)
		end
	end
	function b:IsOpen()
		return self.dpOpen
	end
	b:SetScript("OnClick", function(self)
		self:SetOpen(not self.dpOpen)
		if onToggle then
			ns.SafeCall(onToggle, self.dpOpen)
		end
	end)
	b:SetScript("OnEnter", function(self)
		S.TextColor(self.label, "white")
	end)
	b:SetScript("OnLeave", function(self)
		S.TextColor(self.label, "gold")
	end)
	b:SetOpen(false)
	return b
end
