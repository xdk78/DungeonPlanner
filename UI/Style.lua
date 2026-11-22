-- The visual system: a "war table", a raid leader's briefing board, built from the game's own window materials (its
-- framed window with the portrait ring, inset panels, panel buttons, tabs and scroll bars, Friz Quadrata in the game's
-- gold and white; drawn at runtime, never copied) with a layout of its own. Rules: one spacing scale and size set, one
-- highlight per list, inputs show their border, primary action first (docs/UI.md).
--
-- This file supplies colour tokens, backdrops (font objects: UI/Fonts.lua), the materials (Style.Inset, Style.MenuBackground,
-- Style.DialogChrome, Style.HeaderStrip: the game's pieces where the client has them, our drawn ones otherwise) and a
-- repaint registry. UI/Art.lua names every Blizzard texture, atlas, template and layout the UI draws (with fallbacks)
-- so /dp debug can report what this client lacks.

local _, ns = ...
local Style = ns:NewModule("Style")

local MEDIA = "Interface\\AddOns\\DungeonPlanner\\Media\\"
Style.MEDIA = MEDIA

-- Spacing scale and sizes. Every gap comes from SPACE, every control height from SIZE.
Style.SPACE = { xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48 }
Style.SIZE = {
	control = 24, -- buttons, fields, dropdowns (Blizzard's panel buttons are 22-24)
	small = 20,
	row = 28,
	row2 = 44,
	nav = 28,
	tab = 32,
	header = 36, -- the window's title bar
	icon = 24,
	portrait = 40, -- boss list portraits
	bigPortrait = 88,
	card = 132, -- instance cards on the home grid
}
-- Kept for code that still names a radius; the game's frames have their own corners.
Style.RADIUS = { badge = 2, control = 4, container = 4, dialog = 6 }
-- Route lines and their direction arrows on the map (UI/MapRoutes.lua), at icon size 1, by the Routes settings
-- (settings.routes). width: the line; outline: the dark casing around it (both sides together) in `casing`'s colour;
-- spacing: path length on screen between arrows (false: no arrows); arrow: an arrow's size as a share of the outlined
-- line's width; head: the arrowhead before each stop, as a share of an arrow; tone: how far an arrow's fill is mixed
-- towards white.
Style.ROUTE = {
	width = { thin = 1.5, medium = 2.5, thick = 3.75 },
	outline = 2.5,
	casing = { 0.05, 0.03, 0.02, 0.85 },
	spacing = { off = false, few = 190, normal = 120, many = 75 },
	arrow = { small = 2.3, medium = 2.9, large = 3.6 },
	head = 1.35,
	tone = 0.25,
	focusWidth = 2, -- the focused step's leg is this much wider
	-- The rest of the routes while a leg is highlighted (hover, a hovered step, run mode's current step) or a step is in
	-- focus: this much of their opacity, their colour moved this far towards grey (so it does not fade to pink on
	-- parchment).
	dim = 0.55,
	dimGrey = 0.5,
	lane = 0.6, -- a corridor walked out and back: each direction moves this share of the outlined width to its right
	dash = { 2, 1.2 }, -- the way back through such a corridor: dash and gap, in outlined line widths
	maxDashes = 600, -- per redraw, all routes together; longer dashes and gaps beyond it
	-- Colour along the route (Model/RouteLook.lua): the line runs from the route's colour to a partner colour, its hue
	-- turned by `turn` degrees (the way that reads best: red runs through magenta to blue), its lightness moved by
	-- `lift` (within low..high; lighter when the start is darker than `mid`), its chroma at least `chroma`. A stretch
	-- longer than 1/pieces of the route is drawn in pieces so its colour flows. paper and dark: the map art the ramp
	-- is checked against (parchment, the game's dark minimap pictures).
	ramp = {
		turn = 120,
		lift = 0.14,
		low = 0.55,
		high = 0.78,
		mid = 0.66,
		chroma = 0.11,
		grey = 0.04, -- a start with less chroma (white) turns towards greyHue (blue)
		greyHue = 255,
		steps = 32,
		pieces = 48,
		paper = { 0.80, 0.68, 0.48 },
		dark = { 0.12, 0.10, 0.08 },
	},
}

local function rgb(r, g, b, a)
	return { r, g, b, a or 1 }
end

-- One palette, the game's own: dark brown and stone surfaces, gold headings (the game's NORMAL_FONT_COLOR) over
-- warm off-white body text (its highlight colour, softened), gold-bronze edges, an amber selection like the Adventure
-- Guide's. Steel blue stays only on the map (the focused step's ring), where it reads against parchment. Status and map
-- colours stay strong enough to read on parchment.
Style.THEMES = {
	native = {
		-- Text
		gold = rgb(1, 0.82, 0), -- headings and labels: the game's gold
		goldBright = rgb(1, 0.91, 0.55),
		ink = rgb(0.93, 0.91, 0.86),
		white = rgb(1, 1, 1),
		muted = rgb(0.71, 0.67, 0.59),
		dim = rgb(0.50, 0.47, 0.42),
		-- Surfaces
		page = rgb(0.62, 0.56, 0.49), -- tint of the window's stone background
		titleBar = rgb(0.09, 0.07, 0.05, 0.97),
		surface = rgb(0.075, 0.062, 0.05, 0.94), -- inset panels (under the game's inset art where it draws)
		insetTint = rgb(0.86, 0.78, 0.68, 1), -- the inset's own marble, warmed
		raised = rgb(0.15, 0.115, 0.08, 0.96), -- headers, rows and plates on a panel
		menu = rgb(0.06, 0.05, 0.04, 1), -- popups and dropdown lists: opaque, so nothing shows through
		hover = rgb(0.22, 0.17, 0.11, 0.92),
		selected = rgb(0.38, 0.24, 0.09, 0.96), -- amber, like the Adventure Guide's selected row
		accent = rgb(0.42, 0.66, 0.82, 1), -- steel blue: the focused step's ring on the map
		button = rgb(0.16, 0.12, 0.085, 0.97),
		buttonHover = rgb(0.24, 0.18, 0.12, 0.97),
		buttonPress = rgb(0.09, 0.07, 0.05, 0.97),
		primary = rgb(0.50, 0.09, 0.06, 0.97), -- primary actions (drawn fallback of the game's red panel button)
		primaryHover = rgb(0.62, 0.13, 0.08, 0.97),
		field = rgb(0.03, 0.025, 0.02, 0.96),
		-- Borders and lines (gold-bronze)
		border = rgb(0.62, 0.49, 0.29, 0.95),
		borderHover = rgb(0.88, 0.70, 0.40, 1),
		borderSelected = rgb(1, 0.82, 0.38, 1),
		hairline = rgb(0.72, 0.57, 0.33, 0.55),
		steelLine = rgb(0.40, 0.45, 0.52, 0.5),
		focus = rgb(1, 0.82, 0.38, 1),
		headerStrip = rgb(0.80, 0.58, 0.25, 0.55), -- the section headers' glow
		-- Status (dots, checkmarks, level colours)
		ok = rgb(0.30, 0.82, 0.42),
		info = rgb(0.42, 0.66, 0.95),
		warning = rgb(1, 0.62, 0.20),
		danger = rgb(1, 0.34, 0.28),
		-- Map
		mapBackdrop = rgb(0.07, 0.05, 0.035, 1),
		grid = rgb(0.48, 0.38, 0.22, 0.6),
		-- Pull and route colours: strong enough to read on parchment, in the order pulls take them.
		palette = {
			rgb(0.86, 0.20, 0.16), -- red
			rgb(0.18, 0.45, 0.90), -- blue
			rgb(0.20, 0.66, 0.26), -- green
			rgb(0.62, 0.30, 0.86), -- violet
			rgb(0.95, 0.55, 0.10), -- orange
			rgb(0.10, 0.68, 0.72), -- teal
			rgb(0.92, 0.80, 0.18), -- yellow
			rgb(0.85, 0.85, 0.85), -- white
		},
		-- The colour-blind set (settings.colorblind): the Okabe-Ito palette, which stays apart for red-green and blue-
		-- yellow colour blindness, in the same slots (1 is still the "red" one), its black swapped for a light grey that
		-- reads on parchment. Pulls, routes, drawings and party roles all switch.
		paletteColorblind = {
			rgb(0.84, 0.37, 0.00), -- vermillion
			rgb(0.00, 0.45, 0.70), -- blue
			rgb(0.00, 0.62, 0.45), -- bluish green
			rgb(0.80, 0.47, 0.65), -- reddish purple
			rgb(0.90, 0.62, 0.00), -- orange
			rgb(0.34, 0.71, 0.91), -- sky blue
			rgb(0.94, 0.89, 0.26), -- yellow
			rgb(0.88, 0.88, 0.88), -- light grey
		},
		rolesColorblind = {
			TANK = rgb(0.00, 0.45, 0.70),
			HEALER = rgb(0.00, 0.62, 0.45),
			MELEE = rgb(0.84, 0.37, 0.00),
			RANGED = rgb(0.94, 0.89, 0.26),
		},
		-- Party roles on the map.
		roles = {
			TANK = rgb(0.25, 0.55, 1),
			HEALER = rgb(0.25, 0.85, 0.35),
			MELEE = rgb(0.95, 0.30, 0.25),
			RANGED = rgb(0.95, 0.65, 0.15),
		},
	},
}
-- The old "dark"/"light" settings both mean the native look.
Style.THEMES.dark = Style.THEMES.native
Style.THEMES.light = Style.THEMES.native

Style.current = Style.THEMES.native

function Style.Color(name)
	local c = Style.current[name] or Style.current.ink
	return c[1], c[2], c[3], c[4]
end

-- The colour-blind setting (settings.colorblind) switches pull, route and drawing colours and party roles everywhere:
-- every map colour is read through these two functions.
function Style.Colorblind()
	local db = ns.db
	local settings = db and db.settings
	return type(settings) == "table" and settings.colorblind == true
end

function Style.Palette()
	return Style.Colorblind() and Style.current.paletteColorblind or Style.current.palette
end

function Style.PaletteColor(index)
	local palette = Style.Palette()
	local c = palette[index] or palette[#palette]
	return c[1], c[2], c[3], c[4]
end

function Style.RoleColor(role)
	local roles = Style.Colorblind() and Style.current.rolesColorblind or Style.current.roles
	local c = roles[role] or Style.current.gold
	return c[1], c[2], c[3], c[4]
end

-- Backdrops -----------------------------------------------------------------------------------------------------------
-- The game's frame borders (BackdropTemplate). Frames not created from the template get its mixin, as Blizzard's own
-- code and most addons do; without backdrop support we draw a fill and a 1 px border instead.

local WHITE = "Interface\\Buttons\\WHITE8X8"
Style.WHITE = WHITE

-- The drawn window's background (clients without the game's window template): the game's marble stone
-- (Interface\FrameGeneral, shipped since the original game), or the rock texture the installed Forever addons prove
-- exists, tinted warm either way (Style.WindowBackground).
Style.STONE = "Interface\\FrameGeneral\\UI-Background-Marble"
Style.ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"

Style.BACKDROPS = {
	-- The drawn window: stone with the game's metal dialog border (UI-DialogBox-Border, the classic grey frame edge),
	-- tinted gold-bronze.
	window = {
		bgFile = Style.ROCK,
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 256,
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	},
	-- Plates, rows and fields (and inset panels where the game's inset art is missing): a flat fill with the tooltip
	-- border, tinted gold-bronze.
	panel = {
		bgFile = WHITE,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = false,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	},
	thin = {
		bgFile = WHITE,
		edgeFile = WHITE,
		tile = false,
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	},
}

-- Marble when the client has it (checked once with GetFileIDFromPath), else the rock every Forever client has.
function Style.WindowBackground()
	if Style.stoneChecked == nil then
		local known = ns.Art and ns.Art.FileExists(Style.STONE)
		Style.stoneChecked = known == true
		if Style.stoneChecked then
			Style.BACKDROPS.window.bgFile = Style.STONE
		end
	end
	return Style.BACKDROPS.window.bgFile
end

local function hasBackdrop(frame)
	if frame.SetBackdrop then
		return true
	end
	if BackdropTemplateMixin and Mixin then
		Mixin(frame, BackdropTemplateMixin)
		-- BackdropTemplate refreshes its tiling on size changes; a hook survives later OnSizeChanged scripts... unless
		-- someone replaces it with SetScript, so frames with a backdrop use HookScript for their own handlers.
		if frame.HookScript and frame.OnBackdropSizeChanged then
			frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
		end
		return frame.SetBackdrop ~= nil
	end
	return false
end

-- Give a frame a backdrop preset and colours (fill role, border role). Returns true when the game's backdrop is used.
function Style.Backdrop(frame, preset, fillRole, borderRole)
	frame.dpBackdropPreset = preset
	if preset == "window" then
		Style.WindowBackground()
	end
	if hasBackdrop(frame) then
		local ok = pcall(frame.SetBackdrop, frame, Style.BACKDROPS[preset] or Style.BACKDROPS.panel)
		if ok then
			frame.dpHasBackdrop = true
		end
	end
	if not frame.dpHasBackdrop and not frame.dpFallbackFill then
		local border = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		border:SetColorTexture(1, 1, 1, 1)
		border:SetAllPoints()
		local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		fill:SetColorTexture(1, 1, 1, 1)
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", -1, 1)
		frame.dpFallbackFill, frame.dpFallbackBorder = fill, border
	end
	Style.PaintBackdrop(frame, fillRole, borderRole)
	return frame.dpHasBackdrop == true
end

-- Repaint a backdrop. A nil role keeps the current one; false hides that part.
function Style.PaintBackdrop(frame, fillRole, borderRole)
	if fillRole ~= nil then
		frame.dpFillRole = fillRole
	end
	if borderRole ~= nil then
		frame.dpBorderRole = borderRole
	end
	local fr, fg, fb, fa = 0, 0, 0, 0
	if frame.dpFillRole then
		fr, fg, fb, fa = Style.Color(frame.dpFillRole)
	end
	local br, bg, bb, ba = 0, 0, 0, 0
	if frame.dpBorderRole then
		br, bg, bb, ba = Style.Color(frame.dpBorderRole)
	end
	if frame.dpHasBackdrop then
		if frame.dpBackdropPreset == "window" then
			-- The stone is tinted, not replaced (keep its light); the grey metal edge is tinted gold-bronze.
			frame:SetBackdropColor(fr, fg, fb, fa)
			frame:SetBackdropBorderColor(0.86, 0.66, 0.42, frame.dpBorderRole and 1 or 0)
		else
			frame:SetBackdropColor(fr, fg, fb, fa)
			frame:SetBackdropBorderColor(br, bg, bb, ba)
		end
	elseif frame.dpFallbackFill then
		frame.dpFallbackFill:SetVertexColor(fr, fg, fb, fa)
		frame.dpFallbackBorder:SetVertexColor(br, bg, bb, ba)
	end
end

-- The surface API the panels use: Surface(frame, fillRole, radius, borderRole) and frame:SetSurface(fill, border).
-- A surface with a border is a tooltip-bordered panel; without one, a flat fill.
function Style.Surface(frame, fillRole, _radius, borderRole)
	Style.Backdrop(frame, borderRole and "panel" or "thin", fillRole or false, borderRole or false)
	if not borderRole and frame.dpHasBackdrop then
		frame:SetBackdropBorderColor(0, 0, 0, 0)
	end
	function frame:SetSurface(newFill, newBorder)
		Style.PaintBackdrop(self, newFill, newBorder)
	end
	Style.Register(frame, function(f)
		Style.PaintBackdrop(f)
	end)
end

function Style.Tint(tex, name)
	tex:SetVertexColor(Style.Color(name))
end

-- Square fills only; kept so old callers work. The game's frames bring their own corners.
function Style.Round(tex)
	tex:SetColorTexture(1, 1, 1, 1)
end

-- One physical pixel in this frame's coordinates (hairlines stay 1 px at any UI scale).
function Style.Pixel(frame)
	if PixelUtil and PixelUtil.GetNearestPixelSize and frame and frame.GetEffectiveScale then
		local ok, size = pcall(PixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
		if ok and size then
			return size
		end
	end
	return 1
end

-- A gold divider (role "hairline") or a steel one ("steelLine"). Horizontal by default.
function Style.Hairline(parent, vertical, role)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 1)
	Style.Tint(line, role or "hairline")
	local px = Style.Pixel(parent)
	if vertical then
		line:SetWidth(px)
	else
		line:SetHeight(px)
	end
	return line
end

-- Materials ---------------------------------------------------------------------------------------------------------
-- The game's own surfaces, each drawn only where the client has it (UI/Art.lua checks the layout, atlas or file) and
-- otherwise left to the drawn backdrop above. docs/UI.md lists them with where each was seen on WoW: Forever.

-- A nine-slice border layout on a child frame at the parent's level, so it draws over the parent's background and
-- under its children, as the game's templates do (useParentLevel). Returns the child, or nil without the layout.
function Style.NineSlice(frame, layout)
	if frame.dpNine then
		return frame.dpNine
	end
	if not (ns.Art and ns.Art.HasLayout(layout)) then
		return nil
	end
	local nine = ns.Art.CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
	nine:SetAllPoints()
	-- It follows the parent's level when that changes later (a panel raised over the map): the client's own
	-- useParentLevel where it has it, else our SetFrameLevel passes the level on.
	if not (nine.SetUsingParentLevel and pcall(nine.SetUsingParentLevel, nine, true)) then
		nine:SetFrameLevel(frame:GetFrameLevel())
		local setLevel = frame.SetFrameLevel
		frame.SetFrameLevel = function(self, level)
			setLevel(self, level)
			nine:SetFrameLevel(level)
		end
	end
	if nine.EnableMouse then
		nine:EnableMouse(false)
	end
	if not ns.Art.ApplyLayout(nine, layout) then
		nine:Hide()
		return nil
	end
	frame.dpNine = nine
	return nine
end

-- A tiled background texture (an Art key) inside `frame`, `inset` px from its edges, tinted with colour `role`.
local function tiled(frame, key, inset, role, sublevel)
	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel or -6)
	tex:SetPoint("TOPLEFT", inset, -inset)
	tex:SetPoint("BOTTOMRIGHT", -inset, inset)
	if not ns.Art.Set(tex, key) then
		tex:Hide()
		return nil
	end
	if tex.SetHorizTile then
		tex:SetHorizTile(true)
		tex:SetVertTile(true)
	end
	if role then
		Style.Tint(tex, role)
	end
	return tex
end

-- An inset panel in the game's look (InsetFrameTemplate's parts): its marble, warmed, inside the inset bevel (the
-- layout's dark edge with a soft inner shadow). Returns true when drawn; the frame's own fill and border then step
-- back. Without the layout the drawn panel (fill and tooltip border) stays.
function Style.Inset(frame)
	if frame.dpInset ~= nil then
		return frame.dpInset
	end
	frame.dpInset = false
	if not Style.NineSlice(frame, "InsetFrameTemplate") then
		return false
	end
	frame.dpInsetBg = tiled(frame, "insetBg", 2, "insetTint")
	frame.dpInset = true
	return true
end

-- A dropdown list's panel: the game's menu art (common-dropdown-bg, a nine-slice atlas with its own soft shadow
-- around the panel), filling the frame. The panel itself sits Style.MENU_SHADOW (x, y) inside the frame's edges, as
-- the game's menus draw it, so the frame covers everything drawn and its content goes inside that margin. Returns
-- true when drawn.
Style.MENU_SHADOW = { x = 10, y = 3 }
function Style.MenuBackground(frame)
	if frame.dpMenuBg then
		return true
	end
	if not (ns.Art and ns.Art.HasAtlas("common-dropdown-bg")) then
		return false
	end
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetAllPoints()
	ns.Art.Set(bg, "menuBg")
	frame.dpMenuBg = bg
	return true
end

-- A dialog in the game's look: the Dialog layout (the game's popup border) over its dark dialog background. Returns
-- true when drawn.
function Style.DialogChrome(frame)
	if not Style.NineSlice(frame, "Dialog") then
		return false
	end
	frame.dpDialogBg = tiled(frame, "dialogBg", 8, nil, -6)
	return true
end

-- A section header's strip: the quest log's header glow, tinted gold, behind the heading (as the game's quest log and
-- the Adventure Guide set their headers on a band). Returns the texture, or nil without the file.
function Style.HeaderStrip(frame)
	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	if not ns.Art.Set(tex, "headerStrip") then
		tex:Hide()
		return nil
	end
	tex:SetBlendMode("ADD")
	tex.dpRole = "headerStrip"
	Style.Tint(tex, "headerStrip")
	Style.Register(tex, function(t)
		Style.Tint(t, t.dpRole)
	end)
	return tex
end

-- Repaint registry --------------------------------------------------------------------------------------------------------
-- Weak keys: widgets that are garbage collected drop out by themselves.

local registry = setmetatable({}, { __mode = "k" })

function Style.Register(obj, paint)
	registry[obj] = paint
end

function Style.Repaint()
	for obj, paint in pairs(registry) do
		ns.SafeCall(paint, obj)
	end
	ns:Fire("STYLE_CHANGED")
end

-- There is one look now; a theme change only repaints (kept for settings saved by older versions).
function Style.SetTheme()
	Style.current = Style.THEMES.native
	Style.Repaint()
end

-- Text colour helper that survives repaints.
function Style.TextColor(fontString, role)
	fontString.dpColorRole = role
	fontString:SetTextColor(Style.Color(role))
	if not fontString.dpRegistered then
		fontString.dpRegistered = true
		Style.Register(fontString, function(fs)
			fs:SetTextColor(Style.Color(fs.dpColorRole))
		end)
	end
end

-- An estimated spot (Util.SplitApprox): a small muted "~" after the text instead of the words "(approx.)".
Style.APPROX = "~" -- plain ASCII: every face has it; U+2248 read as "=" at caption size in game
function Style.ApproxMark()
	local r, g, b = Style.Color("muted")
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5), Style.APPROX)
end

-- `text` with the approx mark appended when `approx`.
function Style.WithApprox(text, approx)
	if not approx then
		return text
	end
	if text == nil or text == "" then
		return Style.ApproxMark()
	end
	-- A no-break space, so the mark never wraps onto a line of its own.
	return text .. "\194\160" .. Style.ApproxMark()
end

-- Level range text coloured like the game colours quest difficulty (GetQuestDifficultyColor, guarded; OpenMap uses
-- the same call), or the heading colour without it. Grey, green, yellow and orange as the quest log shows them, but
-- never its red: a dungeon far above the player's level is shown in the orange of "very difficult" (probed at five
-- levels above at most), because a list of red level ranges read as a warning or an error, not as "later". The home
-- table's Levels heading explains the colours in its tooltip (UI/Home.lua).
function Style.LevelColor(levelMin, levelMax)
	if not levelMin then
		return Style.Color("gold")
	end
	local playerLevel = UnitLevel and ns.Util.Plain(UnitLevel("player"))
	if type(GetQuestDifficultyColor) == "function" and ns.Util.IsInteger(playerLevel) then
		local probe = levelMin
		if levelMax and playerLevel > levelMax then
			probe = levelMax - 2
		end
		probe = math.min(probe, playerLevel + 4) -- orange at most (5 levels above is the quest log's red)
		local ok, color = pcall(GetQuestDifficultyColor, probe)
		if ok and type(color) == "table" and color.r then
			return color.r, color.g, color.b, 1
		end
	end
	return Style.Color("gold")
end

function Style.Init()
	Style.current = Style.THEMES.native
	Style.InitFonts() -- UI/Fonts.lua
end
