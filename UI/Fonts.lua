-- Fonts: Dungeon Planner's own font objects (DungeonPlannerFont_*), the Polish face chain and the font test that
-- /dp debug and /dp scan run. Loaded right after UI/Style.lua; the functions live on Style (Style.SetupFonts, ...).
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
--     ever change it. The font test below records enough to tell the remaining causes apart in one run: the file
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
local probeHolder, probeString, objectString, probeTexture
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
	local cyrillic = Style.WantsCyrillic()
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

-- The font test (/dp debug, /dp scan) ---------------------------------------------------------------------------------

local function yesNo(x)
	if x == nil then
		return "?"
	end
	return tostring(x)
end

-- Other addons' fonts registered in LibSharedMedia (files under Interface\AddOns\, not ours): controls that show
-- whether this client loads addon fonts at all. At most four, by name.
local function controlFaces()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local list = {}
	if not (LSM and LSM.HashTable) then
		return list
	end
	local ok, fonts = pcall(LSM.HashTable, LSM, "font")
	if not ok or type(fonts) ~= "table" then
		return list
	end
	local names = {}
	for name, file in pairs(fonts) do
		if type(file) == "string" and file:gsub("/", "\\"):lower():find("^interface\\addons\\")
			and not sameFile(file:sub(1, #MEDIA), MEDIA) and file ~= POLISH_FACE then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	for i = 1, math.min(#names, 4) do
		list[#list + 1] = fonts[names[i]]
	end
	return list
end

-- One compact string per probe, for chat and DungeonPlannerDB.diagnostics.
local function describe(r)
	if not r then
		return ""
	end
	local parts = { "set=" .. yesNo(r.set), "got=" .. (r.got and shortName(r.got) or "?"), "pl/ascii=" .. yesNo(r.pl) .. "/" .. yesNo(r.ascii),
		"glyphs=" .. yesNo(r.glyphs) }
	if r.objGot ~= nil or r.objPl ~= nil then
		parts[#parts + 1] = "obj=" .. (r.objGot and shortName(r.objGot) or "?") .. " " .. yesNo(r.objPl) .. "/" .. yesNo(r.objAscii)
			.. " glyphs=" .. yesNo(r.objGlyphs)
	end
	parts[#parts + 1] = "base=" .. yesNo(r.base)
	return table.concat(parts, " ")
end
Style.DescribeProbe = describe

-- Everything the test knows now: the chain's faces (with WoW Po Polsku's state and this session's first probe), the
-- game face as a control for the width test, other addons' fonts, and one of our textures (the same folder, another
-- file type).
function Style.FontTest()
	local test = { at = GetTime and GetTime() or 0, faces = {}, controls = {}, polishAddon = polishAddonState() }
	for _, file in ipairs(Style.POLISH_FACES) do
		local first = firstProbe[file]
		local now = Style.ProbeFace(file)
		if now.usable then
			usable[file] = true
		end
		test.faces[#test.faces + 1] = { file = file, kind = Style.FaceKind(file), first = first, now = now }
	end
	test.game = Style.ProbeFace(GAME_FACE.roman)
	-- The game's Cyrillic cut (the bundled Alegreya Sans, the other Russian face, is in test.faces above).
	test.cyrillic = Style.ProbeFace(GAME_FACE.russian)
	if test.cyrillic.usable then
		usable[GAME_FACE.russian] = true
	end
	for _, file in ipairs(controlFaces()) do
		test.controls[#test.controls + 1] = Style.ProbeFace(file)
	end
	if probeFrames() then
		probeTexture = probeTexture or probeHolder:CreateTexture(nil, "ARTWORK")
		local ok, res = pcall(probeTexture.SetTexture, probeTexture, MEDIA .. "Chevron")
		test.texture = ok and yesNo(res) or "error"
	end
	return test
end

-- A second look at the same faces (test.faces[i].later), a few seconds after the first.
function Style.FontTestAgain(test)
	for _, f in ipairs(test.faces) do
		f.later = Style.ProbeFace(f.file)
		if f.later.usable then
			usable[f.file] = true
		end
	end
	if test.cyrillic and not test.cyrillic.usable then
		test.cyrillic = Style.ProbeFace(GAME_FACE.russian)
		if test.cyrillic.usable then
			usable[GAME_FACE.russian] = true
		end
	end
	for i, r in ipairs(test.controls) do
		if not r.usable then
			test.controls[i] = Style.ProbeFace(r.file)
		end
	end
end

local function faceWorks(f)
	return (f.later and f.later.usable) or (f.now and f.now.usable) or false
end

-- What the test means, as lines for chat (the verdict last).
function Style.FontTestLines(test)
	local lines = {}
	local bundled, bundledOk = {}, {}
	for _, f in ipairs(test.faces) do
		local name = shortName(f.file)
		if f.kind == "wowpopolsku" and (test.polishAddon == "disabled" or test.polishAddon == "missing") then
			lines[#lines + 1] = string.format(test.polishAddon == "disabled"
				and L["%s: WoW Po Polsku is disabled, and the game does not open the files of a disabled addon."]
				or L["%s: WoW Po Polsku is not installed."], name)
		else
			local r = f.later or f.now
			lines[#lines + 1] = string.format(L["%s: %s (SetFont %s, then %s; Polish letters %s; through a font object %s)"], name,
				faceWorks(f) and L["loads"] or L["does not load"], yesNo(f.now and f.now.set), yesNo(f.later and f.later.set),
				yesNo(r and r.glyphs), yesNo(r and r.objGlyphs))
		end
		if f.kind == "bundled" then
			bundled[#bundled + 1] = f
			if faceWorks(f) then
				bundledOk[#bundledOk + 1] = f
			end
		end
	end
	if test.cyrillic then
		lines[#lines + 1] = string.format(L["%s (Russian): %s (SetFont %s)"], shortName(GAME_FACE.russian),
			test.cyrillic.usable and L["loads"] or L["does not load"], yesNo(test.cyrillic.set))
	end
	local controlsOk = 0
	for _, r in ipairs(test.controls) do
		if r.usable then
			controlsOk = controlsOk + 1
		end
	end
	if #bundledOk == #bundled then
		lines[#lines + 1] = L["The bundled fonts load."]
	elseif #bundledOk > 0 then
		lines[#lines + 1] = string.format(L["%s loads but %s does not: that file is the problem, and the working one is used."],
			shortName(bundledOk[1].file), shortName((bundled[1] == bundledOk[1] and bundled[2] or bundled[1]).file))
	elseif #test.controls == 0 then
		lines[#lines + 1] = L["Neither bundled font loads, and no other addon's font was found to compare with."]
	elseif controlsOk > 0 then
		lines[#lines + 1] =
			L["Other addons' fonts load, Dungeon Planner's do not: its folder's fonts cannot be read. If that folder is a link (junction, symlink), use a real copy."]
	else
		lines[#lines + 1] = L["No addon font loads on this client: other addons' fonts fail too."]
	end
	return lines
end

-- The compact record /dp scan saves (DungeonPlannerDB.diagnostics.fontTest).
function Style.FontTestRecord(test)
	local rec = { polishAddon = test.polishAddon, texture = test.texture, game = describe(test.game),
		cyrillic = describe(test.cyrillic), faces = {}, controls = {} }
	for _, f in ipairs(test.faces) do
		rec.faces[shortName(f.file)] = { first = describe(f.first), now = describe(f.now), later = describe(f.later),
			firstAt = f.first and round(f.first.t) or nil, works = faceWorks(f) }
	end
	for _, r in ipairs(test.controls) do
		rec.controls[shortName(r.file)] = describe(r)
	end
	rec.verdict = Style.FontTestLines(test)
	return rec
end

-- The visible part of /dp debug's test: each face of the chain drawn twice, set directly on the line (left) and through
-- our Font object (right), so the eye sees what the numbers say (boxes = the face did not apply). Drawing the faces
-- also makes the client load them, before the second look. It is part of the /dp debug dialog (its body, under the
-- Polish letters test), never a second window over it; on its own it opens in a dialog of its own.
local panel
local SAMPLE_TEXT = "Za\197\188\195\179\197\130\196\135 g\196\153\197\155l\196\133 ja\197\186\197\132"

local PANEL_W = 512 -- the /dp debug dialog's width (560) inside its margins

local function buildPanel()
	local W, SP = ns.Widgets, Style.SPACE
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetWidth(PANEL_W)
	p:Hide()
	p.title = W.Text(p, "title", "gold")
	p.title:SetPoint("TOPLEFT")
	p.title:SetText(L["Font test"])
	p.rule = Style.Hairline(p)
	p.rule:SetPoint("TOPLEFT", 0, SP.sm)
	p.rule:SetPoint("TOPRIGHT", 0, SP.sm)
	p.rows = {}
	local y = 18 + SP.sm
	for i = 1, #Style.POLISH_FACES do
		local row = {}
		row.label = W.Text(p, "caption", "gold")
		row.label:SetPoint("TOPLEFT", 0, -y)
		row.label:SetPoint("RIGHT")
		row.direct = p:CreateFontString(nil, "OVERLAY")
		row.direct:SetFontObject(Style.fonts.body)
		row.direct:SetPoint("TOPLEFT", 0, -(y + 14))
		row.object = p:CreateFontString(nil, "OVERLAY")
		row.object:SetFontObject(Style.fonts.body)
		row.object:SetPoint("TOPLEFT", math.floor(PANEL_W / 2), -(y + 14))
		p.rows[i] = row
		y = y + 14 + 22 + SP.xs
	end
	p.note = W.Paragraph(p, "caption", "ink")
	p.note:SetPoint("TOPLEFT", 0, -y)
	p.note:SetPoint("RIGHT")
	p.note:SetText(L["Left: the face set on the line itself; right: through a font object. Boxes mean that face did not apply."])
	p:SetHeight(y + math.ceil(p.note:GetStringHeight() or 24))
	return p
end

-- The test's frame, to put in a dialog (W.ShowDialog's body).
function Style.FontTestPanel()
	panel = panel or buildPanel()
	return panel
end

local function rowLabel(f, status)
	local text = shortName(f.file)
	if status then
		text = text .. "  -  " .. status
	end
	return text
end

function Style.ShowFontTest(test)
	if not (CreateFrame and UIParent and ns.Widgets and ns.Widgets.Text) then
		return nil
	end
	panel = panel or buildPanel()
	local dialog = rawget(_G, "DungeonPlannerDialog")
	-- Not in the open /dp debug dialog: a dialog of its own (one at a time: it waits for the one that is open).
	local inDebug = dialog and dialog:IsShown() and dialog.spec and dialog.spec.body == panel
	-- Its own heading under the Polish letters test; on its own, the dialog's title says it.
	panel.title:SetShown(inDebug and true or false)
	panel.rule:SetShown(inDebug and true or false)
	if not inDebug then
		ns.Widgets.ShowDialog({ title = L["Font test"], width = 560, body = panel, buttons = { { L["Close"] } } })
	end
	for i, f in ipairs(test.faces) do
		local row = panel.rows[i]
		if row then
			row.label:SetText(rowLabel(f))
			row.direct:SetFontObject(Style.fonts.body)
			pcall(row.direct.SetFont, row.direct, f.file, 16, "")
			row.direct:SetText(SAMPLE_TEXT)
			local font = faceFont(f.file)
			row.object:SetFontObject(font or Style.fonts.body)
			row.object:SetText(SAMPLE_TEXT)
		end
	end
	return panel
end

-- After the second look: each row says whether its face loads.
function Style.MarkFontTest(test)
	if not (panel and panel:IsShown()) then
		return
	end
	for i, f in ipairs(test.faces) do
		local row = panel.rows[i]
		if row then
			row.label:SetText(rowLabel(f, faceWorks(f) and L["loads"] or L["does not load"]))
		end
	end
end

-- /dp debug and /dp scan: probe now, draw the faces, look again `delay` seconds later; then report (print = true),
-- switch a Polish UI to a face that now works, and hand the test to `done`.
function Style.RunFontTest(opts)
	opts = opts or {}
	local test = Style.FontTest()
	if opts.show then
		Style.ShowFontTest(test)
	end
	local function finish()
		Style.FontTestAgain(test)
		Style.MarkFontTest(test)
		local before = Style.fontFile
		if Style.WantsPolish() or Style.WantsCyrillic() then
			Style.SetupFonts()
		end
		if opts.print then
			ns:Print(L["Font test, a few seconds later:"])
			for _, line in ipairs(Style.FontTestLines(test)) do
				print("    " .. line)
			end
			if Style.fontFile ~= before and Style.polishFace then
				print("    " .. string.format(L["Polish letters: %s is now used."], shortName(Style.polishFace)))
			elseif Style.fontFile ~= before and Style.cyrillicFace then
				print("    " .. string.format(L["Cyrillic letters: %s is now used."], shortName(Style.cyrillicFace)))
			end
		end
		if opts.done then
			opts.done(test)
		end
	end
	if C_Timer and C_Timer.After and (opts.delay or 2) > 0 then
		C_Timer.After(opts.delay or 2, finish)
	else
		finish()
	end
	return test
end
