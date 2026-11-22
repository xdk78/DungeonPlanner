-- The widget kit, part 1: text, tooltips, panels, section headers and buttons (part 1b, UI/Fields.lua: fields, check
-- boxes, dropdowns and menus; part 1c, UI/Tabs.lua: tabs; part 2, UI/Containers.lua: lists, scroll areas and bars,
-- portraits, steppers; part 3, UI/Popup.lua: dropdown lists; part 4, UI/Window.lua: the window, dialogs and Escape).
-- Every panel builds from these, so controls look and behave the same everywhere and new panels inherit the look: the
-- game's own materials (UI/Style.lua, Materials) where the client has them, our drawn versions otherwise. Templates
-- only through Art.CreateFrame (pcall, with a drawn fallback), never secure ones.

local _, ns = ...
local W = ns:NewModule("Widgets")
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE

-- Does a frame made from a template have the parts (regions or child frames, by key) the code is about to use? A
-- template that changed shape on some client then falls back to the drawn version instead of erroring.
function W.HasParts(frame, ...)
	for i = 1, select("#", ...) do
		if type(frame[select(i, ...)]) ~= "table" then
			return false
		end
	end
	return true
end

-- Text -----------------------------------------------------------------------------------------------------------------

function W.Text(parent, font, role, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(S.fonts[font or "body"])
	S.TextColor(fs, role or "ink")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("MIDDLE")
	fs:SetWordWrap(false)
	return fs
end

-- One line of text that may be longer than its room: shown whole when it fits, else cut after the last whole word that
-- fits, with "..." (never inside a word; a separator such as ",", "+" or "•" left at the end goes too). Needs the
-- string's width (its anchors or SetWidth); without one yet, the text is set whole. Returns the text shown, and
-- whether it was shortened; fs.dpFullText then holds the whole text, for a tooltip (W.FullTextTooltip).
local TRAIL = { [" "] = true, [","] = true, [":"] = true, [";"] = true, ["+"] = true, ["-"] = true, ["("] = true,
	["/"] = true, ["&"] = true }
local MIDDOT = "\226\128\162" -- the separator (a bullet: the Cyrillic game face has no middle dot)
local function trimEnd(t)
	while #t > 0 do
		local last = t:sub(-1)
		if TRAIL[last] then
			t = t:sub(1, -2)
		elseif t:sub(-#MIDDOT) == MIDDOT then
			t = t:sub(1, -(#MIDDOT + 1))
		else
			break
		end
	end
	return t
end

-- Is the text cut? The client says so itself (IsTruncated); without that method, its width against the room
-- (GetStringWidth stops at the string's width on current clients, so the unbounded width where there is one).
local function overflows(fs, room)
	if fs.IsTruncated then
		return fs:IsTruncated() == true
	end
	local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	return (w or 0) > room + 0.5
end
W.TextOverflows = overflows

-- Fit a text on one line: cut after a whole word with "..." (the whole text in fs.dpFullText for a tooltip). `fromStart`:
-- cut whole words from the start instead ("...Hungerer's Heart"), for names whose last words say what the thing is.
function W.FitText(fs, text, fromStart)
	text = tostring(text or "")
	fs.dpFullText = nil
	fs:SetText(text)
	local room = fs:GetWidth()
	if not room or room <= 0 or not overflows(fs, room) then
		return text, false
	end
	local cut = text
	if fromStart then
		while true do
			local shorter = cut:match("^%s*%S+%s+(%S.*)$")
			if not shorter then
				break
			end
			cut = shorter
			fs:SetText("..." .. cut)
			if not overflows(fs, room) then
				fs.dpFullText = text
				return "..." .. cut, true
			end
		end
		fs:SetText(text)
		return text, false
	end
	while true do
		local shorter = cut:match("^(.*%S)%s+%S+%s*$")
		if not shorter then
			break
		end
		cut = trimEnd(shorter)
		if cut == "" then
			break
		end
		fs:SetText(cut .. "...")
		if not overflows(fs, room) then
			fs.dpFullText = text
			return cut .. "...", true
		end
	end
	-- One long word: the game's own cut is all that is left.
	fs:SetText(text)
	return text, false
end

-- Show the whole text of a shortened FontString (W.FitText) in a tooltip on `owner`, with `extra` lines under it.
-- Returns true when it showed one.
function W.FullTextTooltip(owner, fs, extra)
	local tt = W.Tip()
	if not (tt and fs and fs.dpFullText) then
		return false
	end
	W.TipBeside(tt, owner)
	tt:SetText(fs.dpFullText, 1, 0.82, 0, 1, true)
	for _, line in ipairs(extra or {}) do
		tt:AddLine(line, 1, 1, 1, true)
	end
	W.TipShow(tt)
	return true
end

-- A paragraph that wraps.
function W.Paragraph(parent, font, role)
	local fs = W.Text(parent, font or "body", role or "muted")
	fs:SetWordWrap(true)
	fs:SetJustifyV("TOP")
	fs:SetSpacing(3)
	return fs
end

-- A gold section heading (the Adventure Guide's "Bosses"). band: set it on the game's header band (Style.HeaderStrip),
-- from the heading to the parent's right edge, as W.SectionHeader draws it, for a heading that heads a column.
function W.Heading(parent, text, font, band)
	local fs = W.Text(parent, font or "title", "gold")
	fs:SetText(text or "")
	if band then
		local strip = S.HeaderStrip(parent)
		if strip then
			-- One anchor (the heading's left, so the band stays on the heading's line), and a width to the parent's
			-- right edge, kept up when the parent resizes. Anchoring its right to the parent as well would give the
			-- band two vertical centres; clients settle that differently.
			strip:SetPoint("LEFT", fs, "LEFT", -SP.xs, 0)
			strip:SetHeight(SZ.row - 4)
			fs.dpStrip = strip
			local function fit()
				local pr, fl = parent:GetRight(), fs:GetLeft()
				local w = (pr and fl) and (pr - fl) or ((parent:GetWidth() or 0) - SP.md)
				strip:SetWidth(math.max(1, w))
			end
			fs.FitBand = fit
			parent:HookScript("OnSizeChanged", fit)
			fit()
		end
	end
	return fs
end

-- Tooltips: our own tooltip (GameTooltipTemplate, non-secure, named DungeonPlannerTooltip) so its lines can use our font
-- objects (the game's tooltip font has no Polish ą ę ś ż) without touching the shared GameTooltip that other addons
-- use. Item tooltips (SetItemByID) stay on GameTooltip: their text is the game's. Falls back to GameTooltip.
local tip
function W.Tip()
	if tip == nil then
		tip = false
		if CreateFrame and UIParent then
			local ok, t = pcall(CreateFrame, "GameTooltip", "DungeonPlannerTooltip", UIParent, "GameTooltipTemplate")
			if ok and t and t.SetOwner then
				tip = t
			end
		end
	end
	return tip or GameTooltip
end

-- Our fonts on every line of a tooltip we filled (keeping each line's colour), then show it.
function W.TipShow(tt)
	if tt and tt ~= GameTooltip and tt.NumLines then
		local name = tt:GetName()
		for i = 1, tt:NumLines() or 0 do
			for _, side in ipairs({ "Left", "Right" }) do
				local fs = name and rawget(_G, name .. "Text" .. side .. i)
				if fs and fs.SetFontObject then
					local r, g, b, a = fs:GetTextColor()
					fs:SetFontObject(S.fonts[i == 1 and "title" or "body"])
					if r then
						fs:SetTextColor(r, g, b, a)
					end
				end
			end
		end
	end
	if tt then
		tt:Show()
	end
end

-- Put tooltip `tt` (owned by `owner`) beside `text`, a FontString in the owner: its top-left corner just right of the
-- text's last letter, top-aligned with the text. A wide row whose name is short keeps its tooltip next to the name, so
-- the game's comparison tooltips (anchored to this one) line up beside it too. The game keeps tooltips on screen.
function W.AnchorBeside(tt, owner, text, gap)
	tt:SetOwner(owner, "ANCHOR_NONE")
	tt:ClearAllPoints()
	local width = math.ceil(text:GetStringWidth() or 0)
	local room = text:GetWidth()
	if room and room > 0 then
		width = math.min(width, math.ceil(room))
	end
	tt:SetPoint("TOPLEFT", text, "TOPLEFT", width + (gap or SP.md), SP.xs)
end

-- Put tooltip `tt` (owned by `owner`) beside the owner: to its right, or to its left when the screen has no room there
-- (a window near the right edge: run mode). The tooltip is kept on screen either way. Lines should be added with wrap
-- (the tooltip wraps them at its own width instead of running off the screen).
local TIP_ROOM = 320
function W.TipBeside(tt, owner)
	tt:SetOwner(owner, "ANCHOR_NONE")
	tt:ClearAllPoints()
	local right = owner:GetRight()
	local screen = UIParent and UIParent:GetRight()
	local fits = true
	if right and screen then
		local scale = (owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		fits = right * scale + TIP_ROOM + SP.sm <= screen
	end
	if fits then
		tt:SetPoint("TOPLEFT", owner, "TOPRIGHT", SP.xs, 0)
	else
		tt:SetPoint("TOPRIGHT", owner, "TOPLEFT", -SP.xs, 0)
	end
	if tt.SetClampedToScreen then
		tt:SetClampedToScreen(true)
	end
end

-- Do two shown regions overlap on screen? (Moving a tooltip off a button.)
function W.Overlaps(a, b)
	if not (a and b and a:IsShown() and b:IsShown()) then
		return false
	end
	local l1, r1, t1, b1 = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
	local l2, r2, t2, b2 = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
	if not (l1 and r1 and t1 and b1 and l2 and r2 and t2 and b2) then
		return false
	end
	return l1 < r2 and r1 > l2 and b1 < t2 and t1 > b2
end

-- anchor: nil (right of the control, the game's default) or "below" (under it: header controls, so the tooltip never
-- covers the control beside it).
function W.SetTooltip(frame, title, text, anchor)
	frame.dpTooltipTitle, frame.dpTooltipText = title, text
	if anchor ~= nil then
		frame.dpTooltipAnchor = anchor
	end
	if frame.dpTooltipHooked then
		return
	end
	frame.dpTooltipHooked = true
	frame:HookScript("OnEnter", function(self)
		local tt = W.Tip()
		-- No tooltip over the list a control has open.
		if not self.dpTooltipTitle or not tt or self.dpPopupOpen then
			return
		end
		if self.dpTooltipAnchor == "below" then
			tt:SetOwner(self, "ANCHOR_NONE")
			tt:ClearAllPoints()
			tt:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -SP.xs)
		else
			W.TipBeside(tt, self)
		end
		tt:SetText(self.dpTooltipTitle, 1, 0.82, 0, 1, true)
		if self.dpTooltipText then
			tt:AddLine(self.dpTooltipText, 1, 1, 1, true)
		end
		W.TipShow(tt)
	end)
	frame:HookScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
end

-- Panels ---------------------------------------------------------------------------------------------------------------

-- A panel. With the default roles (fill "surface", a border) it is an inset panel: the game's inset (its marble inside
-- the inset bevel, Style.Inset) where the client has it, else a dark fill with the tooltip border. Other roles give a
-- drawn plate (rows, fields, small boxes).
function W.Panel(parent, fillRole, borderRole, name)
	local f = Art.CreateFrame("Frame", name, parent, "BackdropTemplate")
	if fillRole == nil then
		fillRole = "surface"
	end
	if borderRole == nil then
		borderRole = "border"
	end
	S.Surface(f, fillRole, nil, borderRole)
	if fillRole == "surface" and borderRole and S.Inset(f) then
		-- The inset draws the edge; our fill stays only where its marble is missing.
		S.PaintBackdrop(f, not f.dpInsetBg and "surface" or false, false)
	end
	return f
end

-- A gold divider line under a heading.
function W.Divider(parent)
	return S.Hairline(parent)
end

-- A section header: a gold heading on the game's header band (the quest log's header glow, Style.HeaderStrip) with a
-- gold rule under it, and an optional count on the right. Anchor it by its top and sides; it is SZ.row - 4 tall.
-- .text is the heading; SetText(t), SetCount(n or nil).
function W.SectionHeader(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(SZ.row - 4)
	f.strip = S.HeaderStrip(f)
	if f.strip then
		f.strip:SetPoint("TOPLEFT", -SP.xs, 0)
		f.strip:SetPoint("BOTTOMRIGHT", SP.xs, 0)
	end
	f.text = W.Text(f, "title", "gold")
	f.text:SetPoint("LEFT", SP.xs, 0)
	f.text:SetText(text or "")
	f.count = W.Text(f, "caption", "muted")
	f.count:SetPoint("RIGHT", -SP.xs, 0)
	f.count:SetJustifyH("RIGHT")
	f.rule = S.Hairline(f)
	f.rule:SetPoint("BOTTOMLEFT")
	f.rule:SetPoint("BOTTOMRIGHT")
	function f:SetText(t)
		self.text:SetText(t or "")
	end
	function f:SetCount(n)
		self.count:SetText(n and tostring(n) or "")
	end
	return f
end

-- Buttons ----------------------------------------------------------------------------------------------------------------
-- variant: "primary" (the main action of a view: the game's red panel button, UIPanelButtonTemplate, with gold text; a
-- drawn red plate without it; "red" and "soft" are old names for it), "outline" (a dark plate with a gold edge, like
-- the Adventure Guide's secondary buttons), "ghost" (text and a highlight only: toolbars, lists), "segment" (a plate
-- whose active state lights a gold bar along its top: tabs inside popups, and W.Tabs without the game's tabs).

local PRIMARY = { red = true, soft = true, primary = true }

local function paintButton(b)
	local enabled = b:IsEnabled()
	local hover, down = b.dpHover and enabled, b.dpDown and enabled
	local v = b.dpVariant
	if b.dpNative then
		-- The game's panel button draws its own states (normal, pushed, disabled); only the label is ours.
		if b.label then
			S.TextColor(b.label, not enabled and "dim" or hover and "white" or "gold")
		end
		return
	end
	if v == "ghost" then
		if b.dpActive then
			S.PaintBackdrop(b, "selected", "borderSelected")
		elseif hover or down then
			S.PaintBackdrop(b, "hover", "border")
		else
			S.PaintBackdrop(b, false, false)
		end
	elseif v == "primary" then
		local fill = hover and not down and "primaryHover" or "primary"
		S.PaintBackdrop(b, fill, (hover or b.dpActive) and "borderSelected" or "borderHover")
	elseif v == "segment" then
		local fill = b.dpActive and "raised" or down and "buttonPress" or hover and "buttonHover" or "surface"
		S.PaintBackdrop(b, fill, b.dpActive and "borderHover" or "border")
		if b.dpBar then
			b.dpBar:SetShown(b.dpActive and true or false)
		end
	else
		local fill = b.dpActive and "selected" or down and "buttonPress" or hover and "buttonHover" or "button"
		S.PaintBackdrop(b, fill, (b.dpActive or hover) and "borderHover" or "border")
	end
	if b.label then
		local role
		if not enabled then
			role = "dim"
		elseif v == "primary" then
			role = hover and "white" or "goldBright"
		elseif v == "segment" then
			role = b.dpActive and "goldBright" or hover and "white" or "muted"
		else
			role = (hover or b.dpActive) and "white" or (v == "ghost" and "ink" or "gold")
		end
		S.TextColor(b.label, role)
		-- A drawn glyph (SetGlyph) takes the label's colour: gold, white on hover and when chosen, grey when disabled.
		for _, part in ipairs(b.glyph and b.glyph.parts or {}) do
			if part:GetObjectType() == "FontString" then
				part:SetTextColor(S.Color(role))
			else
				part:SetVertexColor(S.Color(role))
			end
		end
	end
	if b.icon then
		b.icon:SetDesaturated(not enabled or (v == "segment" and not b.dpActive and not hover))
		b.icon:SetAlpha(enabled and 1 or 0.5)
	end
end
W.PaintButton = paintButton

function W.Button(parent, text, variant, onClick, width)
	variant = variant or "outline"
	if PRIMARY[variant] then
		variant = "primary"
	end
	local b
	if variant == "primary" then
		-- The game's red panel button; its parts are checked, so a client (or a test) without them gets the drawn one.
		local templated
		b, templated = Art.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b.dpNative = templated and W.HasParts(b, "Left", "Middle", "Right") or nil
	else
		b = Art.CreateFrame("Button", nil, parent, "BackdropTemplate")
	end
	b.dpVariant = variant
	b:SetHeight(SZ.control)
	if b.dpNative then
		b:SetText("") -- our label (our font: Polish letters) draws the text
	else
		S.Backdrop(b, "panel", "button", "border")
	end
	if b.dpNative then
		b.dpSheen = nil
	elseif variant == "primary" or variant == "outline" then
		-- A faint light along the top half, as on the game's metal plates.
		b.dpSheen = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		b.dpSheen:SetColorTexture(1, 1, 1, 0.06)
		b.dpSheen:SetPoint("TOPLEFT", 3, -3)
		b.dpSheen:SetPoint("TOPRIGHT", -3, -3)
		b.dpSheen:SetHeight(math.floor(SZ.control / 2) - 3)
	elseif variant == "segment" then
		b.dpBar = b:CreateTexture(nil, "ARTWORK", nil, 3)
		b.dpBar:SetColorTexture(1, 1, 1, 1)
		S.Tint(b.dpBar, "borderSelected")
		b.dpBar:SetPoint("TOPLEFT", 3, -3)
		b.dpBar:SetPoint("TOPRIGHT", -3, -3)
		b.dpBar:SetHeight(2)
		b.dpBar:Hide()
	end
	b.label = W.Text(b, "body", "gold")
	b.label:SetPoint("CENTER")
	-- Left clicks only: a right-click on "Delete pull" or a dialog's button must not act like a left one. Rows that
	-- open a menu on right-click are W.List rows (UI/Containers.lua), not buttons.
	b:RegisterForClicks("LeftButtonUp")
	S.Register(b, paintButton)

	-- The button's picture: its icon (SetIcon) where the client has the art, else its glyph (SetGlyph), else none.
	local function picture(self)
		if self.icon and self.icon:IsShown() then
			return self.icon
		elseif self.glyph and self.glyph:IsShown() then
			return self.glyph
		end
	end
	-- The picture left of the label, or alone in the middle when the button is compact (SetCompact); no picture: the
	-- label alone, so a client without the art still names the button.
	local function place(self)
		local pic = picture(self)
		self.label:ClearAllPoints()
		if pic then
			pic:ClearAllPoints()
			if self.dpCompact then
				pic:SetPoint("CENTER")
			else
				pic:SetPoint("LEFT", SP.sm, 0)
				self.label:SetPoint("LEFT", pic, "RIGHT", SP.xs, 0)
				self.label:SetPoint("RIGHT", -SP.sm, 0)
				self.label:SetJustifyH("CENTER")
			end
		else
			self.label:SetPoint("CENTER")
		end
		self.label:SetShown(not (pic and self.dpCompact))
	end
	-- The width the button takes compact or not, without changing it (toolbars measure both before choosing).
	function b:WidthFor(compact)
		if self.dpFixedWidth then
			return self:GetWidth()
		end
		local pic = picture(self)
		if pic and compact then
			return SZ.control
		end
		local w = math.ceil(self.label:GetStringWidth()) + 2 * SP.md
		if pic then
			w = w + pic:GetWidth() + SP.xs
		end
		return math.max(SZ.control, w)
	end
	local function fit(self)
		if not self.dpFixedWidth then
			self:SetWidth(self:WidthFor(self.dpCompact))
		end
	end
	function b:SetLabel(t)
		self.label:SetText(t or "")
		fit(self)
	end
	function b:SetActive(active)
		self.dpActive = active
		paintButton(self)
	end
	function b:SetDisabled(disabled)
		self:SetEnabled(not disabled)
		paintButton(self)
	end
	-- An icon left of the label: an Art key. Returns whether the client has the art; without it the icon hides and the
	-- glyph (SetGlyph) or the label stands in.
	function b:SetIcon(key, size)
		if not self.icon then
			local round = Art.SPECS[key] and Art.SPECS[key].round
			self.icon = round and Art.RoundTexture(self, "ARTWORK", 2) or self:CreateTexture(nil, "ARTWORK", nil, 2)
		end
		size = size or (SZ.control - 6)
		local ok = Art.Set(self.icon, key)
		-- An atlas that is not square keeps its shape inside the size x size slot.
		local aspect = ok and Art.AtlasAspect(key)
		if aspect and aspect > 1 then
			self.icon:SetSize(size, size / aspect)
		elseif aspect and aspect < 1 then
			self.icon:SetSize(size * aspect, size)
		else
			self.icon:SetSize(size, size)
		end
		self.icon:SetShown(ok)
		if self.glyph then
			self.glyph:SetShown(not ok)
		end
		place(self)
		fit(self)
		paintButton(self)
		return ok
	end
	-- A picture drawn by the addon (lines, a letter) where no game art fits or the client lacks it: draw(holder, size)
	-- adds the regions to `holder` and returns them; they take the label's colour. An icon that shows wins over it.
	function b:SetGlyph(draw, size)
		size = size or (SZ.control - 6)
		self.glyph = CreateFrame("Frame", nil, self)
		self.glyph:SetSize(size, size)
		self.glyph.parts = draw(self.glyph, size) or {}
		self.glyph:SetShown(not (self.icon and self.icon:IsShown()))
		place(self)
		fit(self)
		paintButton(self)
	end
	-- Compact: the picture alone on a square button, the label left to the tooltip (narrow toolbars). A button without
	-- a picture keeps its label.
	function b:SetCompact(compact)
		compact = compact and true or nil
		if compact == self.dpCompact then
			return
		end
		self.dpCompact = compact
		place(self)
		fit(self)
	end

	if width then
		b.dpFixedWidth = true
		b:SetWidth(width)
	end
	b:SetLabel(text)
	b:HookScript("OnEnter", function(self)
		self.dpHover = true
		paintButton(self)
	end)
	b:HookScript("OnLeave", function(self)
		self.dpHover, self.dpDown = false, false
		paintButton(self)
	end)
	b:HookScript("OnMouseDown", function(self)
		self.dpDown = true
		paintButton(self)
	end)
	b:HookScript("OnMouseUp", function(self)
		self.dpDown = false
		paintButton(self)
	end)
	if onClick then
		b:SetScript("OnClick", function(self, mouse)
			W.CommitFocus()
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
				pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			end
			ns.SafeCall(onClick, self, mouse)
		end)
	end
	paintButton(b)
	return b
end

-- A square button showing art (an Art key) or a short glyph ("+", "<", ">").
function W.IconButton(parent, glyph, tooltip, onClick)
	local b = W.Button(parent, "", "ghost", onClick, SZ.icon)
	b:SetHeight(SZ.icon)
	if Art.SPECS[glyph] then
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetPoint("TOPLEFT", 3, -3)
		b.art:SetPoint("BOTTOMRIGHT", -3, 3)
		Art.Set(b.art, glyph)
	else
		b.label:SetFontObject(S.fonts.title)
		b:SetLabel(glyph)
	end
	if tooltip then
		W.SetTooltip(b, tooltip)
	end
	return b
end

-- A square toolbar button with a picture and no words: art `key` (an Art key, or nil) where the client has it, else
-- the addon's glyph `draw` (b:SetGlyph, or nil), else `text` as its label. The tooltip names it (`text`) under `hint`.
-- The chosen one is lit with SetActive, as every outline button.
function W.ToolButton(parent, key, draw, text, hint, onClick)
	local b = W.Button(parent, text, "outline", onClick)
	if draw then
		b:SetGlyph(draw)
	end
	if key then
		b:SetIcon(key)
	end
	b:SetCompact(true)
	W.SetTooltip(b, text, hint)
	return b
end

-- The game's page arrow ("prev" or "next"): the spell book's round arrow buttons with their pressed and disabled
-- looks and the game's highlight, `size` px (default 26). Without the files: a drawn "<" / ">" button. :SetDisabled.
function W.PageButton(parent, dir, tooltip, onClick, size)
	local key = dir == "prev" and "pagePrev" or "pageNext"
	local up = Art.SPECS[key .. "Up"]
	if Art.FileExists(up.file) == false then
		return W.IconButton(parent, dir == "prev" and "<" or ">", tooltip, onClick)
	end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 26, size or 26)
	b:SetNormalTexture(up.file)
	b:SetPushedTexture(Art.SPECS[key .. "Down"].file)
	b:SetDisabledTexture(Art.SPECS[key .. "Disabled"].file)
	b:SetHighlightTexture(Art.SPECS.buttonHighlight.file, "ADD")
	b.dpNative = true
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function()
		ns.SafeCall(onClick)
	end)
	if tooltip then
		W.SetTooltip(b, tooltip)
	end
	function b:SetDisabled(disabled)
		self:SetEnabled(not disabled)
	end
	return b
end

-- The game's red close button (UIPanelCloseButton), or a drawn one.
function W.CloseButton(parent, onClick)
	local b, templated = Art.CreateFrame("Button", nil, parent, "UIPanelCloseButton")
	if not templated then
		b = W.IconButton(parent, "x", ns.L["Close"])
	end
	b:SetScript("OnClick", function()
		ns.SafeCall(onClick)
	end)
	return b
end
