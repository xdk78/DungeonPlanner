-- Fonts: Dungeon Planner's own font objects (DungeonPlannerFont_*), the Polish face chain and the probe that the font
-- test (UI/FontTest.lua, /dp debug and /dp scan) reads. Loaded right after UI/Style.lua; the functions live on Style
-- (Style.SetupFonts, ...).
-- Dungeon Planner never changes the game's font objects: it only creates its own.
--
-- What this client does with fonts (WoW: Forever, 12.x family; docs/COMPATIBILITY.md, "Fonts"):
--   * Text is drawn with Slug (GPU outlines). The game's faces are compiled into <game>\Fonts\<fileID>.slug at start;
--     an addon's .ttf is compiled when it is first used and cached as <game>\Fonts\override_<n>.slugo, where n is the
--     FNV-1a (32 bit) hash of the file's bytes. So the client reads the file itself to find its cache.
--   * A FontString's SetFont returns true or false (SimpleFontStringAPI); a Font object's returns nothing.
--   * WoW Po Polsku's frizquadratatt_pl.ttf: true while that addon was enabled, false once it was disabled, although
--     its compiled cache stayed on disk. The client does not open the files of a disabled addon.
--   * The bundled Alegreya Sans read false at every probe and was never compiled (no override_*.slugo for it). The probe
--     used to keep that first false for the whole session and the chain then never used the face, so nothing could
--     ever change it. The font test (UI/FontTest.lua) records enough to tell the remaining causes apart in one run: the file
--     (a cleaned copy, DPSans.ttf, beside it), the addon folder (other addons' fonts as controls) or the probe itself
--     (direct SetFont against a Font object, widths of Polish letters, a second look a few seconds later).

local _, ns = ...
local Style = ns.Style
local L = ns.L
local MEDIA = Style.MEDIA

-- Font choice (settings.font):
--   "auto"   the default: "follow" when a Polish translation addon is loaded (it brings fonts with Polish glyphs and
--            applies them to the game's font objects), else "game".
--   "game"   the game's own face for the client's alphabet, as Dungeon Journal and OpenMap use: Friz Quadrata for
--            Latin, its Cyrillic cut for Russian, the Korean and Chinese faces otherwise (file names as in the client's
--            Blizzard_Fonts_Shared, the same table ForeverDungeonJournal's Core/Fonts.lua documents).
--   "follow" whatever face GameFontHighlight has *when our UI is built* (never cached at load), so font replacers and
--            translation packs that restyle the game's fonts also restyle ours.
--   "clean"  Arial Narrow, Latin clients only.
local GAME_FACE = {
	roman = "Fonts\\FRIZQT__.TTF",
	russian = "Fonts\\FRIZQT___CYR.TTF",
	korean = "Fonts\\2002.TTF",
	simplifiedchinese = "Fonts\\ARKai_T.ttf",
	traditionalchinese = "Fonts\\blei00d.TTF",
}
local ALPHABET = { ruRU = "russian", koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese" }

Style.fonts = {}
-- name = { size, flags, colour role or nil }. Text colours are set per FontString (Style.TextColor); the coloured ones
-- here are for Blizzard templates that pick a font object per state (the top tabs: gold normal, white when selected).
-- Sizes follow the game's: small 10, normal 12, large 14/16, huge 20.
local FONT_SPECS = {
	caption = { 10, "" },
	body = { 12, "" },
	title = { 14, "" },
	page = { 18, "" },
	huge = { 22, "" },
	mono = { 11, "" },
	number = { 12, "OUTLINE" }, -- level badges, step numbers and pull numbers on the map
	label = { 12, "OUTLINE" }, -- labels drawn on the map
	tab = { 10, "", "gold" }, -- PanelTopTabButtonTemplate's normal text (the game uses GameFontNormalSmall)
	tabHighlight = { 10, "", "white" }, -- its highlighted and selected text (GameFontHighlightSmall)
}

function Style.FontMode()
	local setting = ns.db and ns.db.settings.font or "auto"
	if setting == "auto" then
		return (ns.Integrations and ns.Integrations.PolishTranslationLoaded()) and "follow" or "game"
	end
	return setting
end

-- Faces with Polish letters, tried in order, for a Polish UI only (English keeps the game's Friz Quadrata). The client's
-- own FRIZQT__.TTF lacks ą ć ę ń ś ź ż (seen in game: boxes, while ó and ł render).
--   1. Friz Quadrata with Polish glyphs from WoW Po Polsku's folder: the game's look. Only while that addon is enabled.
--   2. Alegreya Sans Medium, bundled in Media/Fonts/ (SIL Open Font License, Media/Fonts/OFL.txt).
--   3. DPSans.ttf, the same face cut down to plain TrueType (Latin and Latin Extended-A, no layout tables, no hinting;
--      Media/Fonts/FONTLOG.txt), in case the client refuses the full file.
--   4. The game face (FontFile's fallback).
local POLISH_ADDON = "WoWPoPolskuForever"
local POLISH_FACE = "Interface\\AddOns\\" .. POLISH_ADDON .. "\\Media\\frizquadratatt_pl.ttf"
Style.POLISH_FACE = POLISH_FACE
Style.BUNDLED_FACE = MEDIA .. "Fonts\\AlegreyaSans-Medium.ttf"
Style.CLEAN_FACE = MEDIA .. "Fonts\\DPSans.ttf"
Style.POLISH_FACES = { POLISH_FACE, Style.BUNDLED_FACE, Style.CLEAN_FACE }
-- A Russian UI's faces (Media/Fonts/FONTLOG.txt: Alegreya Sans has all of U+0410-044F; DPSans.ttf has none).
Style.CYRILLIC_FACES = { GAME_FACE.russian, Style.BUNDLED_FACE }

-- "wowpopolsku", "bundled" or "game".
function Style.FaceKind(file)
	if file == POLISH_FACE then
		return "wowpopolsku"
	elseif type(file) == "string" and file:sub(1, #MEDIA) == MEDIA then
		return "bundled"
	end
	return "game"
end

local function shortName(file)
	return tostring(file):match("[^\\/]+$") or tostring(file)
end
Style.FontShortName = shortName

-- WoW Po Polsku's state: "loaded", "enabled", "disabled", "missing" or "unknown". Its face is only tried while it is
-- loaded or enabled: the client does not open a disabled addon's files.
local function polishAddonState()
	if ns.Integrations and ns.Integrations.AddonState then
		return ns.Integrations.AddonState(POLISH_ADDON)
	end
	return "unknown"
end

-- Probing -------------------------------------------------------------------------------------------------------------
-- One look at a face (Style.ProbeFace): a FontString's SetFont (its return value and the face it reports afterwards),
-- the same face through a Font object of ours (how the UI really uses faces), and for both the width of Polish letters
-- against their plain twins ("ąćęńśźż" against "acenszz": equal in a face that has them, different where the game
-- face draws boxes). The probe strings sit in a shown, fully transparent frame, so they are laid out like any text.

local PROBE_SIZE = 14
local SAMPLE_PL = "\196\133\196\135\196\153\197\132\197\155\197\186\197\188" -- ąćęńśźż
local SAMPLE_ASCII = "acenszz"
local probeHolder, probeString, objectString
local faceFonts = {}
local usable = {} -- file -> true once a face has worked (a face that works keeps working; a failure is never kept)
local firstProbe = {} -- file -> this session's first probe (for the font test)
local rechecked -- Style.RecheckFonts ran this session

local function probeFrames()
	if probeString then
		return true
	end
	if not (CreateFrame and UIParent) then
		return false
	end
	probeHolder = CreateFrame("Frame", nil, UIParent)
	probeHolder:SetSize(1, 1)
	probeHolder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	probeHolder:SetAlpha(0)
	probeString = probeHolder:CreateFontString(nil, "OVERLAY")
	objectString = probeHolder:CreateFontString(nil, "OVERLAY")
	return true
end

-- Our Font object for a face of the chain (DungeonPlannerFont_face<i>, CreateFont needs names), or nil.
local function faceFont(file)
	if faceFonts[file] then
		return faceFonts[file]
	end
	if not CreateFont then
		return nil
	end
	for i, f in ipairs(Style.POLISH_FACES) do
		if f == file then
			local ok, font = pcall(CreateFont, "DungeonPlannerFont_face" .. i)
			if ok and font then
				faceFonts[file] = font
				return font
			end
		end
	end
	return nil
end

local function sameFile(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then
		return false
	end
	return a:gsub("/", "\\"):lower() == b:gsub("/", "\\"):lower()
end

local function widths(fs)
	fs:SetText(SAMPLE_PL)
	local pl = tonumber(fs:GetStringWidth()) or 0
	fs:SetText(SAMPLE_ASCII)
	local ascii = tonumber(fs:GetStringWidth()) or 0
	fs:SetText("")
	return pl, ascii
end

-- Polish letters as wide as their plain twins (within 4 %): the face has them.
local function hasPolish(pl, ascii)
	return pl > 0 and ascii > 0 and math.abs(pl - ascii) <= math.max(1, ascii * 0.04)
end

local function round(x)
	return math.floor((tonumber(x) or 0) * 10 + 0.5) / 10
end

-- r.set: SetFont's return (true/false, nil when it returned nothing, "error" when it raised); r.got: the face the
-- string reports afterwards; r.glyphs: Polish letters measured in it; r.obj*: the same through our Font object (only
-- for the chain's faces); r.base: the game face's width of the Polish letters, for comparison. r.usable: the face can
-- carry the UI (SetFont said true, or the Font object really draws Polish letters, wider or narrower than the game's
-- boxes).
function Style.ProbeFace(file)
	local r = { file = file, t = GetTime and GetTime() or 0 }
	if type(file) ~= "string" or file == "" or not probeFrames() then
		return r
	end
	local base = STANDARD_TEXT_FONT or GAME_FACE.roman
	pcall(probeString.SetFont, probeString, base, PROBE_SIZE, "")
	local basePl = widths(probeString)
	r.base = round(basePl)
	local ok, result = pcall(probeString.SetFont, probeString, file, PROBE_SIZE, "")
	if ok then
		r.set = result
	else
		r.set = "error"
	end
	local okG, got = pcall(probeString.GetFont, probeString)
	r.got = okG and got or nil
	r.applied = sameFile(r.got, file)
	local pl, ascii = widths(probeString)
	r.pl, r.ascii, r.glyphs = round(pl), round(ascii), hasPolish(pl, ascii)
	local font = faceFont(file)
	if font then
		pcall(font.SetFont, font, file, PROBE_SIZE, "")
		objectString:SetFontObject(font)
		local okO, objGot = pcall(objectString.GetFont, objectString)
		r.objGot = okO and objGot or nil
		local opl, oascii = widths(objectString)
		r.objPl, r.objAscii = round(opl), round(oascii)
		r.objGlyphs = hasPolish(opl, oascii) and math.abs(opl - basePl) >= 1
	end
	r.usable = r.set == true or r.objGlyphs == true
	firstProbe[file] = firstProbe[file] or r
	return r
end

-- Can this face carry text? true, false, or nil when the client cannot tell (no frames yet). Re-probed on every call
-- until it works: one early failure no longer sticks for the session.
function Style.CanLoadFont(file)
	if type(file) ~= "string" or file == "" then
		return false
	end
	if usable[file] then
		return true
	end
	local r = Style.ProbeFace(file)
	if r.usable then
		usable[file] = true
		return true
	end
	if r.set == nil or r.set == "error" then
		return nil -- no frames yet, or a SetFont that returns nothing: cannot tell
	end
	return false
end

-- For tests: forget which faces loaded.
function Style.ForgetFontProbes()
	usable, firstProbe, rechecked = {}, {}, nil
end

-- What the font test (UI/FontTest.lua) reads of the probe: this session's first probe of a face, marking a face that
-- worked, the probe's frame (nil without frames) and the helpers it shares.
Style.fontProbe = {
	first = function(file)
		return firstProbe[file]
	end,
	worked = function(file)
		usable[file] = true
	end,
	holder = function()
		return probeFrames() and probeHolder or nil
	end,
	polishAddonState = polishAddonState,
	faceFont = faceFont,
	sameFile = sameFile,
	round = round,
	GAME_FACE = GAME_FACE,
}

-- Polish text on screen: the active UI language, or the one just chosen (applied after /reload; the reload prompt
-- itself is already Polish, so it needs the face now).
function Style.WantsPolish()
	if ns.activeLocale == "plPL" then
		return true
	end
	local chosen = ns.db and ns.db.settings.locale
	return chosen == "plPL"
end

-- Russian text on screen: the active UI language, or the one just chosen (applied after /reload).
function Style.WantsCyrillic()
	if ns.activeLocale == "ruRU" then
		return true
	end
	return (ns.db and ns.db.settings.locale) == "ruRU"
end

-- The chain's faces that may be tried now (WoW Po Polsku's only while that addon is enabled).
local function candidates()
	local list = {}
	local state = polishAddonState()
	for _, file in ipairs(Style.POLISH_FACES) do
		if file ~= POLISH_FACE or (state ~= "disabled" and state ~= "missing") then
			list[#list + 1] = file
		end
	end
	return list
end

local function firstLoadable()
	for _, file in ipairs(candidates()) do
		if Style.CanLoadFont(file) ~= false then
			return file
		end
	end
	return nil
end

-- The face a Russian UI uses on a client that is not Russian: the game's Cyrillic cut, else the bundled Alegreya Sans.
-- A face proven to load comes first; one the client cannot tell about yet (nil, no frames) is taken too, and
-- Style.RecheckFonts looks again after the first loading screen, as it does for Polish.
local function firstCyrillic()
	for pass = 1, 2 do
		for _, file in ipairs(Style.CYRILLIC_FACES) do
			local can = Style.CanLoadFont(file)
			if (pass == 1 and can == true) or (pass == 2 and can ~= false) then
				return file
			end
		end
	end
	return nil
end

-- The face a Polish UI would use, whatever the language is now (the chain above): its file and its kind, "wowpopolsku",
-- "bundled" or "game" (no Polish letters).
function Style.PolishFace()
	local file = firstLoadable()
	if file then
		return file, Style.FaceKind(file)
	end
	return GAME_FACE.roman, "game"
end

-- Returns the font file and a size adjustment.
function Style.FontFile()
	local mode = Style.FontMode()
	local locale = GetLocale and GetLocale() or "enUS"
	local alphabet = ALPHABET[locale] or "roman"
	Style.polishFace, Style.cyrillicFace = nil, nil
	if Style.WantsPolish() and (mode == "game" or mode == "follow") and alphabet == "roman" then
		local file = firstLoadable()
		if file then
			Style.polishFace = file
			return file, 0
		end
	end
	-- A Russian UI on a client that is not Russian: the game's Cyrillic cut if this client has it, else the bundled
	-- Alegreya Sans (it has Cyrillic; DPSans.ttf has not). German, French and Spanish need no face of their own: the
	-- client's Friz Quadrata covers Latin-1 (ä ö ü ß é è ê ç ñ ¿ ¡), as those clients use it themselves.
	if Style.WantsCyrillic() and (mode == "game" or mode == "follow") and alphabet == "roman" then
		local file = firstCyrillic()
		if file then
			Style.cyrillicFace = file
			return file, 0
		end
	end
	-- "lsm:<name>": a font registered in LibSharedMedia-3.0 by any addon (fonts with full Polish glyphs, ElvUI's, ...).
	local lsmName = type(mode) == "string" and mode:match("^lsm:(.+)$")
	if lsmName then
		local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
		local file = LSM and LSM:IsValid("font", lsmName) and LSM:Fetch("font", lsmName, true)
		if type(file) == "string" then
			return file, 0
		end
		mode = "game"
	end
	if mode == "follow" and GameFontHighlight and GameFontHighlight.GetFont then
		local file = GameFontHighlight:GetFont()
		if type(file) == "string" and file ~= "" then
			return file, 0
		end
	end
	if mode == "clean" and alphabet == "roman" then
		-- Arial Narrow sets about one point smaller than Friz Quadrata at the same size.
		return "Fonts\\ARIALN.TTF", 1
	end
	return GAME_FACE[alphabet] or STANDARD_TEXT_FONT or GAME_FACE.roman, 0
end

function Style.SetupFonts()
	if not CreateFont then
		return
	end
	local file, bump = Style.FontFile()
	-- A face the client refuses (probe says false) falls back to the game's. Font:SetFont has no return value here.
	if Style.CanLoadFont(file) == false then
		file, bump = STANDARD_TEXT_FONT or GAME_FACE.roman, 0
	end
	Style.fontFile = file
	for name, spec in pairs(FONT_SPECS) do
		local font = Style.fonts[name]
		if not font then
			font = CreateFont("DungeonPlannerFont_" .. name)
			Style.fonts[name] = font
		end
		local size, flags = spec[1] + bump, spec[2]
		font:SetFont(file, size, flags)
		-- The game's text has a 1 px black shadow; outlined faces need none.
		if flags == "" then
			font:SetShadowColor(0, 0, 0, 1)
			font:SetShadowOffset(1, -1)
		else
			font:SetShadowOffset(0, 0)
		end
		font:SetJustifyH("LEFT")
		if spec[3] and font.SetTextColor and Style.current then
			font:SetTextColor(Style.Color(spec[3]))
		end
	end
end

-- A Polish UI without a Polish face --------------------------------------------------------------------------------
-- Decision: the UI stays Polish (the player chose it; most text reads, ó and ł render) and says once why ą ć ę ń ś ź ż
-- show as boxes, pointing at /dp debug and at English. The language dialog says it before the reload too
-- (Style.PolishFontNote).

-- Is a Polish face usable now? false only when every candidate has been tried and failed.
local function polishFaceMissing()
	if not Style.WantsPolish() then
		return false
	end
	local mode = Style.FontMode()
	if mode ~= "game" and mode ~= "follow" then
		return false -- an LSM or Arial Narrow face is the player's own choice
	end
	for _, file in ipairs(candidates()) do
		if Style.CanLoadFont(file) ~= false then
			return false
		end
	end
	return true
end

local function noFaceText()
	return L["No font with Polish letters loads, so ą ć ę ń ś ź ż show as boxes. The UI stays Polish; /dp debug tests the fonts, English avoids the boxes."]
end

-- The same for Russian: nothing with Cyrillic loads, or the font setting is one we cannot vouch for (Arial Narrow, a
-- SharedMedia face). Returns the note's text, or nil.
local function cyrillicNote()
	if not Style.WantsCyrillic() then
		return nil
	end
	local mode = Style.FontMode()
	if mode == "clean" or (type(mode) == "string" and mode:match("^lsm:")) then
		return L["Your font (Arial Narrow or SharedMedia) may lack Cyrillic letters, so Russian text can show as boxes. Choose Automatic or Game font in Settings."]
	end
	if (ALPHABET[GetLocale and GetLocale() or "enUS"] or "roman") ~= "roman" then
		return nil -- the client's own face
	end
	for _, file in ipairs(Style.CYRILLIC_FACES) do
		if Style.CanLoadFont(file) ~= false then
			return nil
		end
	end
	return L["No font with Cyrillic letters loads, so Russian text shows as boxes. The UI stays Russian; /dp debug tests the fonts, English avoids the boxes."]
end

-- The language dialog's note when Polish or Russian is chosen but no face for its letters loads ("" otherwise).
-- (The name is from when Polish was the only language with its own letters.)
function Style.PolishFontNote()
	if polishFaceMissing() then
		return "\n\n" .. noFaceText()
	end
	local cyrillic = cyrillicNote()
	if cyrillic then
		return "\n\n" .. cyrillic
	end
	return ""
end

-- After the first loading screen: give the faces a second look a few seconds later (a face the client loads on first
-- use reads true by then) and switch to the first that works. If none does, say so once. One timer, once a session.
function Style.RecheckFonts(delay)
	if rechecked then
		return
	end
	rechecked = true
	-- Polish without a face yet, or Russian with no face or one the client could not vouch for yet (nil).
	local polish = Style.WantsPolish() and Style.polishFace == nil
	-- (A Russian client uses its own cut: nothing to look at again there.)
	local cyrillic = Style.WantsCyrillic() and (ALPHABET[GetLocale and GetLocale() or "enUS"] or "roman") == "roman"
		and (Style.cyrillicFace == nil or Style.CanLoadFont(Style.cyrillicFace) ~= true)
	if not (polish or cyrillic) then
		return
	end
	-- Warm-up: the faces through our Font objects, as the UI would use them.
	for _, file in ipairs(polish and candidates() or Style.CYRILLIC_FACES) do
		Style.ProbeFace(file)
	end
	local before = Style.cyrillicFace
	local function again()
		Style.SetupFonts()
		if polish and Style.polishFace then
			ns:Print(string.format(L["Polish letters: %s is now used."], shortName(Style.polishFace)))
		elseif polish and polishFaceMissing() then
			ns:Print(noFaceText())
		elseif cyrillic and Style.cyrillicFace and Style.cyrillicFace ~= before then
			ns:Print(string.format(L["Cyrillic letters: %s is now used."], shortName(Style.cyrillicFace)))
		elseif cyrillic and cyrillicNote() then
			ns:Print(cyrillicNote())
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(delay or 3, again)
	else
		again()
	end
end

function Style.InitFonts()
	Style.SetupFonts()
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		-- An older version kept one probe per face here; that record was misleading (a single early SetFont).
		local sv = rawget(_G, "DungeonPlannerDB")
		if type(sv) == "table" then
			sv.fontsAtLogin = nil
		end
		Style.RecheckFonts()
	end)
end
