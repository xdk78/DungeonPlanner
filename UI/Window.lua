-- The widget kit, part 4: the window and the dialogs (parts 1-3: UI/Widgets.lua, UI/Containers.lua, UI/Popup.lua).
-- Both fill ns.Widgets.

local _, ns = ...
local W = ns.Widgets
local S, Art = ns.Style, ns.Art
local SP, SZ = S.SPACE, S.SIZE

-- Escape -------------------------------------------------------------------------------------------------------------------
-- One Escape closes one of our frames, the topmost. The game hides every UISpecialFrames entry on one Escape
-- (CloseAllWindows -> CloseSpecialWindows), so a confirmation and the window behind it would close together. Our
-- frames are therefore not in that list: one hidden stand-in is, shown while any of ours is open. Escape hides the
-- stand-in; its OnHide hides our topmost frame (the higher strata first, then the one shown last) and shows the
-- stand-in again while another of ours is still open, for the next Escape. Registering a handler with the game's
-- own Escape list (RegisterGameMenuEscHandler) from an addon taints that list; UISpecialFrames is the path the game
-- leaves to addons.
--
-- Hiding the whole UI (Alt+Z) also runs OnHide, on the stand-in and on every frame, but leaves them "shown"
-- (IsShown stays true while UIParent is hidden): such a hide is ignored here, and W.Hidden(frame) tells the frames'
-- own OnHide handlers the same, so nothing is declined or cancelled and everything is back when the UI is.

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
	TOOLTIP = 8 }
local escapeOpen = {} -- our open frames that Escape closes, oldest first
local escapeProxy
local syncing = false

-- Was `frame` hidden itself (true), or only with the whole UI (false: Alt+Z; it shows again with the UI)? For OnHide.
function W.Hidden(frame)
	return not frame:IsShown()
end

-- Is the whole UI hidden (Alt+Z)? For OnHide handlers of controls inside a window, which stay "shown" either way.
function W.UIHidden()
	return UIParent ~= nil and not UIParent:IsShown()
end

local function topmost()
	local best, bestRank
	for i = #escapeOpen, 1, -1 do -- newest first: of two in one strata, the one shown last
		local f = escapeOpen[i]
		local rank = STRATA[f:GetFrameStrata()] or 0
		if not best or rank > bestRank then
			best, bestRank = f, rank
		end
	end
	return best
end

local function syncProxy()
	if not escapeProxy then
		return
	end
	syncing = true
	escapeProxy:SetShown(#escapeOpen > 0)
	syncing = false
end

local function forget(frame)
	for i = #escapeOpen, 1, -1 do
		if escapeOpen[i] == frame then
			table.remove(escapeOpen, i)
		end
	end
end

local function buildProxy()
	escapeProxy = CreateFrame("Frame", "DungeonPlannerEscape", UIParent)
	escapeProxy:SetSize(1, 1)
	escapeProxy:SetPoint("TOPLEFT")
	escapeProxy:Hide()
	escapeProxy:SetScript("OnHide", function(self)
		if syncing or not W.Hidden(self) then
			return -- our own sync, or the whole UI hidden
		end
		local f = topmost()
		if f then
			f:Hide() -- its OnHide forgets it and shows the stand-in again while others are open
		end
		syncProxy()
	end)
	W.AddSpecialFrame("DungeonPlannerEscape")
end

-- A frame name into the game's UISpecialFrames (closed by Escape), except with the gamepad interface style on: its
-- menus read and close those frames (Compat.Gamepad); the window then closes with its close button. True when added.
function W.AddSpecialFrame(name)
	if type(UISpecialFrames) ~= "table" or ns.Compat.Gamepad() then
		return false
	end
	table.insert(UISpecialFrames, name)
	return true
end

-- Let Escape close `frame` (topmost first). Hooks, so the frame's own OnShow / OnHide scripts may be set before or after.
function W.CloseOnEscape(frame)
	if not escapeProxy then
		buildProxy()
	end
	frame:HookScript("OnShow", function(self)
		forget(self)
		escapeOpen[#escapeOpen + 1] = self
		syncProxy()
	end)
	frame:HookScript("OnHide", function(self)
		if W.Hidden(self) then
			forget(self)
			syncProxy()
		end
	end)
	if frame:IsShown() then
		escapeOpen[#escapeOpen + 1] = frame
		syncProxy()
	end
end

-- For /dp debug and tests: the frames Escape would close, in the order it would close them.
function W.EscapeOrder()
	local out = {}
	for i = #escapeOpen, 1, -1 do
		out[#out + 1] = escapeOpen[i]
	end
	-- Stable for equal strata: the newest stays first (insertion sort; the list is a handful of frames).
	for i = 2, #out do
		local f, j = out[i], i - 1
		local rank = STRATA[f:GetFrameStrata()] or 0
		while j >= 1 and (STRATA[out[j]:GetFrameStrata()] or 0) < rank do
			out[j + 1] = out[j]
			j = j - 1
		end
		out[j + 1] = f
	end
	return out
end

-- Window ---------------------------------------------------------------------------------------------------------------------
-- W.Window(name, title, saved, minW, minH, opts) -> a movable, resizable window that closes with Escape (W.CloseOnEscape;
-- opts.noEscape: it stays open, as run mode and the Notes window do mid-fight). Position and size are saved in `saved`
-- ({ point, width, height }). opts.compact: no portrait ring and no row under the title bar (a small window: run mode;
-- its title sits inside the bar, its header buttons go left of the close button).
--
-- The game's own window where the client has it (ButtonFrameTemplate: the metal nine-slice frame with the round
-- portrait ring, the textured title bar with the title in Friz Quadrata gold, the dark rock background, the red close
-- button; its inset and button bar are not used), with the launcher icon in the portrait ring. Without it: the drawn
-- window, the stone inside the game's metal dialog edge tinted gold-bronze, a dark header strip with the emblem (the
-- map icon in a gold ring) and the title, the game's close button.
--
-- Either way the window offers the same parts, so the pages never ask which one they got:
--   header      the drag area along the top (the title bar and the row under it)
--   bar         the row for a page's header controls: under the title bar, right of the portrait (native), or the
--               header strip itself, right of the title (drawn)
--   barStart    a region whose RIGHT edge, plus SP.md, is where the first control goes
--   barRightPad room to leave at the bar's right end (the drawn header keeps the close button there)
--   insets      { left, right, top, bottom }: the frame's chrome; content goes inside it
--   title, close, grip, emblem (the portrait texture, or the drawn emblem)
-- The game's window: a 22 px title bar, the 60 px portrait ring over the top-left corner, a 4-6 px metal edge.
local NATIVE = { barLeft = 60, barTop = 25, side = 6, bottom = 6 }
local COMPACT = { barLeft = 8, barTop = 24, side = 6, bottom = 6 }

-- The title text of the game's window (TitleContainer on current clients, TitleText before), or nil.
local function templateTitle(f)
	local holder = type(f.TitleContainer) == "table" and f.TitleContainer or nil
	local fs = holder and holder.TitleText or f.TitleText
	return type(fs) == "table" and fs or nil
end

-- Dress a frame made from ButtonFrameTemplate. Returns false (nothing changed) when its parts are not all there.
local function nativeChrome(f, title, compact)
	if not W.HasParts(f, "NineSlice", "Bg", "CloseButton") then
		return false
	end
	if type(f.Inset) == "table" then
		f.Inset:Hide()
	end
	local hideBar = Art.Helper("ButtonFrameTemplate_HideButtonBar")
	if hideBar then
		pcall(hideBar, f)
	end
	if compact then
		local hidePortrait = Art.Helper("ButtonFrameTemplate_HidePortrait")
		if hidePortrait then
			pcall(hidePortrait, f)
		end
	else
		-- The launcher icon (our logo, or the game's map icon: Art.ApplyLauncher) in the portrait ring
		-- (PortraitFrameMixin; else the game's round-portrait function).
		local portrait = type(f.PortraitContainer) == "table" and f.PortraitContainer.portrait or f.portrait
		local icon = Art.SPECS.launcher.file
		if type(f.SetPortraitToAsset) == "function" then
			pcall(f.SetPortraitToAsset, f, icon)
		elseif type(portrait) == "table" and Art.Helper("SetPortraitToTexture") then
			pcall(Art.Helper("SetPortraitToTexture"), portrait, icon)
		end
		f.emblem = type(portrait) == "table" and portrait or nil
	end
	if type(f.SetTitle) == "function" then
		pcall(f.SetTitle, f, title or "")
	end
	local fs = templateTitle(f)
	if not fs then
		fs = W.Text(f, "title", "gold")
		fs:SetPoint("TOP", 0, -5)
	end
	fs:SetFontObject(S.fonts.title) -- our face: Polish letters in a Polish title
	S.TextColor(fs, "gold")
	fs:SetText(title or "")
	f.title = fs
	if compact then
		-- Without the portrait the template puts the title on the window's left edge: set it inside the title bar, as the
		-- title of the portrait window sits (after the ring), clear of the metal edge.
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", f, "TOPLEFT", COMPACT.side + SP.md, -(COMPACT.barTop / 2) - 1)
		fs:SetJustifyH("LEFT")
	end
	-- The template's close button hides its parent through the game's panel code; ours just hides the window (below).
	f.close = f.CloseButton
	pcall(f.close.UnregisterAllEvents, f.close)
	-- The rock background, warmed (its light kept: a tint, not a fill).
	f.Bg.dpRole = "page"
	S.Tint(f.Bg, "page")
	S.Register(f.Bg, function(t)
		S.Tint(t, t.dpRole)
	end)
	return true
end

-- The drawn window's chrome: stone and metal edge, the header strip with the emblem and the title, a close button.
local function drawnChrome(f, header, title)
	S.Backdrop(f, "window", "page", "border")
	S.Register(f, function(w)
		S.PaintBackdrop(w)
	end)
	header:SetPoint("TOPLEFT", 7, -7)
	header:SetPoint("TOPRIGHT", -7, -7)
	header:SetHeight(SZ.header)
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.bg:SetColorTexture(1, 1, 1, 1)
	S.Tint(header.bg, "titleBar")
	header.line = S.Hairline(header)
	header.line:SetPoint("BOTTOMLEFT")
	header.line:SetPoint("BOTTOMRIGHT")
	-- Emblem: the launcher icon in a gold ring.
	f.emblem = CreateFrame("Frame", nil, header)
	f.emblem:SetSize(SZ.header - 12, SZ.header - 12)
	f.emblem:SetPoint("LEFT", SP.sm, 0)
	f.emblem.icon = Art.RoundTexture(f.emblem, "ARTWORK", 0)
	f.emblem.icon:SetAllPoints()
	Art.Set(f.emblem.icon, "launcher")
	f.emblem.ring = f.emblem:CreateTexture(nil, "OVERLAY")
	f.emblem.ring:SetTexture(S.MEDIA .. "Ring")
	f.emblem.ring:SetPoint("TOPLEFT", -2, 2)
	f.emblem.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	S.Tint(f.emblem.ring, "borderHover")
	f.title = W.Text(header, "title", "gold")
	f.title:SetPoint("LEFT", f.emblem, "RIGHT", SP.sm, 0)
	f.title:SetText(title)
	f.close = W.CloseButton(f, function() end)
	f.close:SetPoint("TOPRIGHT", 2, 2)
	f.close:SetFrameLevel(header:GetFrameLevel() + 5)
	f.bar, f.barStart, f.barRightPad = header, f.title, SZ.header - 2
	f.insets = { left = 7, right = 7, top = 7 + SZ.header, bottom = 7 }
end

-- The game's window draws its metal border on a NineSlice child at frame level 500 (NineSlicePanelTemplate) and keeps
-- its own close button at 510 (UIPanelCloseButtonNoScripts); a button we place on the corners must sit above the
-- border the same way, or the border is drawn over it. Without the game's frame: above the window and its header.
function W.RaiseAboveBorder(f, ...)
	local base = f:GetFrameLevel() + 20
	if f.dpNative and type(f.NineSlice) == "table" and f.NineSlice.GetFrameLevel then
		base = math.max(base, f.NineSlice:GetFrameLevel() + 10)
	end
	for i = 1, select("#", ...) do
		local b = select(i, ...)
		if b then
			b:SetFrameLevel(base)
		end
	end
end

function W.Window(name, title, saved, minW, minH, opts)
	opts = opts or {}
	local f, templated = Art.CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	f.dpNative = templated and nativeChrome(f, title, opts.compact) or false
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:EnableMouse(true)
	-- A size saved before the window's minimum grew (or by hand) opens at the minimum, not below it.
	f:SetSize(math.max(minW, saved.width or 1000), math.max(minH, saved.height or 680))
	if f.SetResizeBounds then
		f:SetResizeBounds(minW, minH)
	elseif f.SetMinResize then
		f:SetMinResize(minW, minH)
	end
	if type(saved.point) == "table" and saved.point[1] then
		f:SetPoint(saved.point[1], UIParent, saved.point[2] or saved.point[1], saved.point[3] or 0, saved.point[4] or 0)
	else
		f:SetPoint("CENTER")
	end

	local function save()
		local point, _, relativePoint, x, y = f:GetPoint(1)
		saved.point = { point, relativePoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
		saved.width, saved.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
	end

	local header = CreateFrame("Frame", nil, f)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		save()
	end)
	f.header = header

	if f.dpNative then
		local geo = opts.compact and COMPACT or NATIVE
		local barH = opts.compact and 0 or SZ.control + 4 -- a compact window has the title bar only
		header:SetPoint("TOPLEFT")
		header:SetPoint("TOPRIGHT", -26, 0) -- the close button keeps its corner
		header:SetHeight(geo.barTop + barH)
		local bar = CreateFrame("Frame", nil, header)
		bar:SetPoint("TOPLEFT", f, "TOPLEFT", geo.barLeft, -geo.barTop)
		bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(geo.side + 2), -geo.barTop)
		bar:SetHeight(barH)
		f.bar = bar
		f.barStart = CreateFrame("Frame", nil, bar)
		f.barStart:SetSize(1, 1)
		f.barStart:SetPoint("RIGHT", bar, "LEFT", -SP.md, 0)
		f.barRightPad = 0
		f.insets = { left = geo.side, right = geo.side, top = geo.barTop + barH, bottom = geo.bottom }
	else
		drawnChrome(f, header, title)
	end
	f.close:SetScript("OnClick", function()
		f:Hide()
	end)

	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", f.dpNative and -4 or -6, f.dpNative and 4 or 6)
	W.RaiseAboveBorder(f, f.close, grip)
	local function gripArt(key)
		local tex = grip:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints()
		Art.Set(tex, key)
		return tex
	end
	grip.normal = gripArt("sizeGrip")
	grip.down = gripArt("sizeGripDown")
	grip.down:Hide()
	grip.highlight = grip:CreateTexture(nil, "HIGHLIGHT")
	grip.highlight:SetAllPoints()
	Art.Set(grip.highlight, "sizeGripHighlight")
	grip:SetScript("OnMouseDown", function()
		grip.down:Show()
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		grip.down:Hide()
		f:StopMovingOrSizing()
		save()
	end)
	f.grip = grip

	if not opts.noEscape then
		W.CloseOnEscape(f)
	end
	f.SavePosition = save
	return f
end

-- Dialogs ----------------------------------------------------------------------------------------------------------------------
-- One dialog at a time, queued. buttons = { { text, fn, primary } } (the game's red panel buttons). Optional input field
-- (opts.input = { value, placeholder }) whose text is passed to the button callbacks. Primary first, at the start of
-- the line. spec.body: a frame of the caller's shown under the text (as tall as it is), hidden with the dialog; /dp
-- debug puts its font test there, so the two tests are one dialog.

local dialog
local dialogQueue = {}

local function buildDialog()
	local d = Art.CreateFrame("Frame", "DungeonPlannerDialog", UIParent, "BackdropTemplate")
	d:SetFrameStrata("DIALOG")
	d:SetToplevel(true)
	d:SetClampedToScreen(true)
	d:EnableMouse(true)
	d:SetWidth(400)
	d:SetPoint("CENTER", 0, 120)
	-- The game's dialog (its popup border over the dark dialog background), else the drawn window's stone and edge.
	if not S.DialogChrome(d) then
		S.Backdrop(d, "window", "page", "border")
	end
	d.title = W.Text(d, "title", "gold")
	d.title:SetPoint("TOPLEFT", SP.xl, -SP.xl)
	d.title:SetPoint("RIGHT", -SP.xl, 0)
	d.text = W.Paragraph(d, "body", "ink")
	d.text:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -SP.md)
	d.text:SetPoint("RIGHT", -SP.xl, 0)
	-- spec.sample: a line drawn in a font file of its own (the Polish letters test), between the title and the text.
	d.sample = W.Text(d, "page", "white")
	d.sample:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -SP.md)
	d.sample:SetPoint("RIGHT", -SP.xl, 0)
	d.sample:Hide()
	d.input = W.Input(d, { maxBytes = 200 })
	d.input:SetPoint("LEFT", SP.xl, 0)
	d.input:SetPoint("RIGHT", -SP.xl, 0)
	d.buttons = {}
	d:Hide()
	d:SetScript("OnHide", function(self)
		if not W.Hidden(self) then
			return -- the whole UI was hidden (Alt+Z): the question stays, unanswered, until it is back
		end
		if self.body then
			self.body:Hide()
			self.body = nil
		end
		if self.onDismiss then
			local fn = self.onDismiss
			self.onDismiss = nil
			ns.SafeCall(fn)
		end
		local nextItem = table.remove(dialogQueue, 1)
		if nextItem then
			W.ShowDialog(nextItem)
		end
	end)
	-- Escape closes the dialog before the window behind it (and, on a share prompt, declines it: Prompts.lua).
	W.CloseOnEscape(d)
	return d
end

function W.ShowDialog(spec)
	dialog = dialog or buildDialog()
	if dialog:IsShown() then
		dialogQueue[#dialogQueue + 1] = spec
		return
	end
	dialog.spec = spec
	dialog:SetWidth(spec.width or 400) -- before the text is measured: its height depends on the width
	dialog.title:SetText(spec.title or "")
	dialog.text:SetText(spec.text or "")
	local sampleHeight = 0
	dialog.text:ClearAllPoints()
	dialog.text:SetPoint("RIGHT", -SP.xl, 0)
	if spec.sample then
		-- Our font objects stay as they are; only this line gets the sample's face (a FontString's SetFont).
		dialog.sample:SetFontObject(S.fonts.page)
		if spec.sample.font then
			pcall(dialog.sample.SetFont, dialog.sample, spec.sample.font, 18, "")
		end
		dialog.sample:SetText(spec.sample.text or "")
		dialog.sample:Show()
		sampleHeight = math.ceil(dialog.sample:GetStringHeight()) + SP.md
		dialog.text:SetPoint("TOPLEFT", dialog.sample, "BOTTOMLEFT", 0, -SP.md)
	else
		dialog.sample:Hide()
		dialog.text:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -SP.md)
	end
	-- The height follows what the text takes (the title's and the sample's own heights too: a sample in a font file of
	-- its own can be taller than its size says). Measured again a frame later, when a font loaded late has laid out.
	local function contentHeight()
		local sh = spec.sample and (math.ceil(dialog.sample:GetStringHeight() or 0) + SP.md) or 0
		local th = math.max(18, math.ceil(dialog.title:GetStringHeight() or 0))
		return SP.xl + th + SP.md + sh + math.ceil(dialog.text:GetStringHeight() or 0) + SP.lg
	end
	local y = math.max(contentHeight(), SP.xl + 18 + SP.md + sampleHeight + SP.lg)
	if dialog.body and dialog.body ~= spec.body then
		dialog.body:Hide()
	end
	dialog.body = spec.body
	if spec.body then
		local body = spec.body
		body:SetParent(dialog)
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", dialog.text, "BOTTOMLEFT", 0, -SP.lg)
		body:SetPoint("RIGHT", -SP.xl, 0)
		body:Show()
		y = y + math.ceil(body:GetHeight() or 0) + SP.lg
	end
	if spec.input then
		dialog.input:Show()
		dialog.input:ClearAllPoints()
		dialog.input:SetPoint("TOPLEFT", spec.body or dialog.text, "BOTTOMLEFT", 0, -SP.md)
		dialog.input:SetPoint("RIGHT", -SP.xl, 0)
		dialog.input:SetValue(spec.input.value or "")
		y = y + SZ.control + SP.md
	else
		dialog.input:Hide()
	end
	for _, b in ipairs(dialog.buttons) do
		b:Hide()
	end
	local x = SP.xl
	for i, def in ipairs(spec.buttons or { { ns.L["OK"] } }) do
		local b = dialog.buttons[i]
		if not b then
			b = W.Button(dialog, "", "red")
			dialog.buttons[i] = b
		end
		b:SetLabel(def[1])
		b:SetWidth(math.max(96, b:GetWidth()))
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", x, SP.xl)
		b:SetScript("OnClick", function()
			local value = spec.input and dialog.input:GetValue() or nil
			dialog.onDismiss = nil
			dialog:Hide()
			if def[2] then
				ns.SafeCall(def[2], value)
			end
		end)
		W.PaintButton(b)
		b:Show()
		x = x + b:GetWidth() + SP.sm
	end
	dialog:SetHeight(y + SZ.control + SP.xl)
	local extra = y - contentHeight()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if dialog:IsShown() and dialog.spec == spec then
				dialog:SetHeight(math.max(dialog:GetHeight(), contentHeight() + extra + SZ.control + SP.xl))
			end
		end)
	end
	dialog.onDismiss = spec.onDismiss
	dialog:Show()
	if spec.input then
		dialog.input.edit:SetFocus()
		dialog.input.edit:HighlightText()
	end
end

function W.Confirm(title, text, confirmText, onConfirm)
	W.ShowDialog({
		title = title,
		text = text,
		buttons = { { confirmText, onConfirm, true }, { ns.L["Cancel"] } },
	})
end

function W.AskText(title, text, value, onOK)
	W.ShowDialog({
		title = title,
		text = text,
		input = { value = value },
		buttons = { { ns.L["OK"], onOK, true }, { ns.L["Cancel"] } },
	})
end

