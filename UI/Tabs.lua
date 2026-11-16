-- The widget kit, part 1c: tabs, the game's window tabs (hanging under a window, or standing on a panel) or segment
-- plates. Part 1 (UI/Widgets.lua) has text, tooltips, panels and buttons; part 1b (UI/Fields.lua) fields and dropdowns.

local _, ns = ...
local W = ns.Widgets
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE

-- Tabs -------------------------------------------------------------------------------------------------------------------
-- items = { { id, text, art? } }; onSelect(id). opts: height, gap, equal (every tab as wide as the widest), style:
--   "bottom"  the game's window tabs (PanelTabButtonTemplate), hanging under a window's bottom edge: anchor the bar's
--             TOPLEFT to the window's BOTTOMLEFT (W.HangTabs). Text only.
--   "top"     the game's top tabs (PanelTopTabButtonTemplate), standing on the panel under them. Text only.
--   nil       segment plates (a gold bar along the active one), with the item's icon.
-- The game's tabs need their template and the PanelTemplates helpers; without them the bar is made of segment plates.
-- Their text uses our tab fonts (Polish letters), set again after every select (the helpers switch font objects).
local TAB_TEMPLATE = { bottom = "PanelTabButtonTemplate", top = "PanelTopTabButtonTemplate" }
local TAB_PAD = 20 -- text to the tab's caps

local function tabFonts(b, selected)
	b:SetNormalFontObject(S.fonts.tab)
	b:SetHighlightFontObject(S.fonts.tabHighlight)
	b:SetDisabledFontObject(S.fonts.tabHighlight)
	b.Text:SetFontObject(selected and S.fonts.tabHighlight or S.fonts.tab)
end

local function nativeTab(bar, item, style)
	if not (Art.Helper("PanelTemplates_SelectTab") and Art.Helper("PanelTemplates_DeselectTab")) then
		return nil
	end
	local b, templated = Art.CreateFrame("Button", nil, bar, TAB_TEMPLATE[style])
	if not (templated and W.HasParts(b, "Text", "Left", "Middle", "Right")) then
		b:Hide()
		return nil
	end
	b.dpNativeTab = true
	tabFonts(b)
	b.Text:SetText(item.text or "")
	b.label = b.Text
	return b
end

-- Size a game tab to its text (PanelTemplates_TabResize where the client has it), or to `width`.
local function sizeTab(b, width)
	local resize = Art.Helper("PanelTemplates_TabResize")
	if not (resize and pcall(resize, b, TAB_PAD, width)) then
		b:SetWidth(width or (math.ceil(b.Text:GetStringWidth() or 0) + 2 * TAB_PAD))
	end
end

local function selectTab(b, on)
	if b.dpNativeTab then
		pcall(Art.Helper(on and "PanelTemplates_SelectTab" or "PanelTemplates_DeselectTab"), b)
		tabFonts(b, on)
		b.dpActive = on
	else
		b:SetActive(on)
	end
end

function W.Tabs(parent, items, onSelect, opts)
	opts = opts or {}
	local style = TAB_TEMPLATE[opts.style or ""] and opts.style or nil
	local height = opts.height or SZ.control
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height)
	bar.buttons = {}
	bar.style = style
	-- The game's tab sizes itself again on every show (PanelTabButtonMixin:OnShow and on DISPLAY_SIZE_CHANGED) from
	-- its parent's tabPadding, minTabWidth and maxTabWidth, as the game's own panels set them; without them it would
	-- lose our padding (and an equal bar its common width) the first time it shows.
	bar.tabPadding = TAB_PAD
	local widest = 0
	if style then
		for i, item in ipairs(items) do
			local b = nativeTab(bar, item, style)
			if not b then
				-- One missing piece: the whole bar is drawn instead, so the tabs never mix looks.
				for _, made in ipairs(bar.buttons) do
					made:Hide()
				end
				bar.buttons, bar.style, style = {}, nil, nil
				break
			end
			b:SetID(i)
			b.id = item.id
			b:SetScript("OnClick", function()
				if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
					pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
				end
				bar:Select(item.id)
				ns.SafeCall(onSelect, item.id)
			end)
			sizeTab(b)
			widest = math.max(widest, b:GetWidth())
			bar.buttons[#bar.buttons + 1] = b
		end
	end
	if style then
		if opts.equal then
			bar.minTabWidth = widest
		end
		for _, b in ipairs(bar.buttons) do
			if opts.equal then
				sizeTab(b, widest)
			end
		end
		bar:SetHeight(bar.buttons[1] and bar.buttons[1]:GetHeight() or height)
	end
	for i, item in ipairs(style and {} or items) do
		local b = W.Button(bar, item.text, "segment", function()
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
				pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
			end
			bar:Select(item.id)
			ns.SafeCall(onSelect, item.id)
		end)
		b:SetHeight(height)
		if item.art then
			b:SetIcon(item.art, height - 8)
		end
		b:SetID(i)
		b.id = item.id
		widest = math.max(widest, b:GetWidth())
		bar.buttons[#bar.buttons + 1] = b
	end
	if not style then
		local x = 0
		for _, b in ipairs(bar.buttons) do
			if opts.equal then
				b.dpFixedWidth = true
				b:SetWidth(widest)
			end
			b:SetPoint("BOTTOMLEFT", x, 0)
			x = x + b:GetWidth() + (opts.gap or SP.xxs)
		end
		bar:SetWidth(math.max(1, x))
	end

	function bar:Select(id)
		self.selected = id
		for _, b in ipairs(self.buttons) do
			selectTab(b, b.id == id)
		end
	end
	-- Lay the shown tabs out again (some hide: sections without a plan) and return the bar's width. The game's tabs
	-- are chained, each beside the one before it (as the game's windows place them), so a tab that sizes itself again
	-- when shown pushes the next one along instead of overlapping it.
	function bar:Reflow()
		local x, prev = 0, nil
		local top = self.style == "bottom"
		for _, b in ipairs(self.buttons) do
			if b:IsShown() then
				b:ClearAllPoints()
				local gap = opts.gap or (self.style and 1 or SP.xxs)
				if self.style and prev then
					b:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", prev, top and "TOPRIGHT" or "BOTTOMRIGHT", gap, 0)
				else
					b:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", x, 0)
				end
				x = x + b:GetWidth() + gap
				prev = b
			end
		end
		self:SetWidth(math.max(1, x))
		return x
	end
	if style then
		bar:Reflow()
	end
	function bar:Button(id)
		for _, b in ipairs(self.buttons) do
			if b.id == id then
				return b
			end
		end
		return nil
	end
	return bar
end

-- Hang a bar of the game's window tabs under `window`'s bottom edge (their tops overlap the edge by 2 px, as the
-- game's own windows place them), and keep them on screen with the window. Other bars go where the caller puts them.
function W.HangTabs(bar, window, x)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", window, "BOTTOMLEFT", x or 11, 2)
	if window.SetClampRectInsets then
		pcall(window.SetClampRectInsets, window, 0, 0, 0, -(bar:GetHeight() - 2))
	end
end
