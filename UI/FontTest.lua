-- The font test that /dp debug and /dp scan run (UI/Fonts.lua has the faces, the chain and the probe it reads; the
-- comment at its top says what the test is for). Loaded right after UI/Fonts.lua; the functions live on Style
-- (Style.RunFontTest, ...). After an update that added this file, the test is missing until the game restarts
-- (Compat.FILES): /dp debug shows the rest of its report and /dp scan saves no fontTest record.

local _, ns = ...
local Style = ns.Style
local L = ns.L
local MEDIA = Style.MEDIA
local POLISH_FACE = Style.POLISH_FACE
local shortName = Style.FontShortName
local probe = Style.fontProbe
local GAME_FACE, sameFile, round, faceFont = probe.GAME_FACE, probe.sameFile, probe.round, probe.faceFont
local probeTexture

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
	local test = { at = GetTime and GetTime() or 0, faces = {}, controls = {}, polishAddon = probe.polishAddonState() }
	for _, file in ipairs(Style.POLISH_FACES) do
		local first = probe.first(file)
		local now = Style.ProbeFace(file)
		if now.usable then
			probe.worked(file)
		end
		test.faces[#test.faces + 1] = { file = file, kind = Style.FaceKind(file), first = first, now = now }
	end
	test.game = Style.ProbeFace(GAME_FACE.roman)
	-- The game's Cyrillic cut (the bundled Alegreya Sans, the other Russian face, is in test.faces above).
	test.cyrillic = Style.ProbeFace(GAME_FACE.russian)
	if test.cyrillic.usable then
		probe.worked(GAME_FACE.russian)
	end
	for _, file in ipairs(controlFaces()) do
		test.controls[#test.controls + 1] = Style.ProbeFace(file)
	end
	local holder = probe.holder()
	if holder then
		probeTexture = probeTexture or holder:CreateTexture(nil, "ARTWORK")
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
			probe.worked(f.file)
		end
	end
	if test.cyrillic and not test.cyrillic.usable then
		test.cyrillic = Style.ProbeFace(GAME_FACE.russian)
		if test.cyrillic.usable then
			probe.worked(GAME_FACE.russian)
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

-- "not installed" or "switched off" for a face whose file the client will not open (WoW Po Polsku's, while that addon is
-- missing or disabled: the same check the chat report uses), else nil. Such a face is not drawn: it would be boxes.
local function absentStatus(test, f)
	if f.kind == "wowpopolsku" then
		if test.polishAddon == "missing" then
			return L["not installed"]
		elseif test.polishAddon == "disabled" then
			return L["switched off"]
		end
	end
	return nil
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
			local absent = absentStatus(test, f)
			row.label:SetText(rowLabel(f, absent))
			row.direct:SetShown(not absent)
			row.object:SetShown(not absent)
			if not absent then
				row.direct:SetFontObject(Style.fonts.body)
				pcall(row.direct.SetFont, row.direct, f.file, 16, "")
				row.direct:SetText(SAMPLE_TEXT)
				local font = faceFont(f.file)
				row.object:SetFontObject(font or Style.fonts.body)
				row.object:SetText(SAMPLE_TEXT)
			end
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
			row.label:SetText(rowLabel(f, absentStatus(test, f) or (faceWorks(f) and L["loads"] or L["does not load"])))
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
