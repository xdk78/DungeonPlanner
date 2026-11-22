-- The bundled face (Media/Fonts/AlegreyaSans-Medium.ttf) must have every character the shipped locales use: it is the
-- fallback for a Russian UI on a client without the game's Cyrillic cut, and for Polish without WoW Po Polsku. The
-- character map is read straight from the file (tools/ttf_cmap.lua); docs: Media/Fonts/FONTLOG.txt.
local T = ...
local ns = T.ns

package.path = "./tools/?.lua;" .. package.path
local Cmap = require("ttf_cmap")

local FACE = "Media/Fonts/AlegreyaSans-Medium.ttf"

local function cp(c)
	return string.format("U+%04X", c)
end

T.case("The bundled face has the whole Russian alphabet (U+0410-044F, Ё, ё)", function()
	local cmap = Cmap.Load(FACE)
	for c = 0x410, 0x44F do
		T.ok(cmap.has[c], "Alegreya Sans lacks " .. cp(c))
	end
	T.ok(cmap.has[0x401] and cmap.has[0x451], "Ё and ё")
	-- The reader itself: a letter of Latin Extended-A and a character no Latin face has.
	T.ok(cmap.has[0x105], "ą")
	T.ok(not cmap.has[0x4E2D], "no Chinese")
	T.eq(#Cmap.CodePoints("aЖ\226\128\148"), 3, "UTF-8 decoding")
end)

T.case("Every character of every shipped locale and of the language list is in the bundled face", function()
	local cmap = Cmap.Load(FACE)
	local function check(label, text)
		local missing = cmap.Missing(text)
		if #missing > 0 then
			local list = {}
			for _, c in ipairs(missing) do
				list[#list + 1] = cp(c)
			end
			error(label .. " uses characters the bundled face lacks: " .. table.concat(list, " "))
		end
	end
	for code, tbl in pairs(ns.Locales) do
		local parts = {}
		for _, v in pairs(tbl) do
			parts[#parts + 1] = v -- values only: the keys are English
		end
		check(code, table.concat(parts, "\n"))
	end
	for _, entry in ipairs(ns.LOCALE_LIST) do
		check("language name " .. entry[1], entry[2])
	end
end)

-- Characters a face a locale can use lacks (checked with tools/ttf_cmap.lua on the client's files, which are not in the
-- repository): the game's Cyrillic face FRIZQT___CYR.TTF has no middle dot U+00B7, so a Russian UI showed a box for
-- every "·" separator. The separator is a bullet (U+2022), which every face has.
local NOT_IN_GAME_FACES = { [0xB7] = "the middle dot: FRIZQT___CYR.TTF (Russian) lacks it; use the bullet U+2022" }

-- The text of every string literal in a Lua file, with "\ddd" escapes decoded; comments are skipped. A small scanner:
-- quoted strings (with escapes), long strings and comments ([[ ]] and [=[ ]=]).
local function codeStrings(path)
	local src = assert(io.open(path, "rb")):read("*a")
	local out, i, n = {}, 1, #src
	local function long(at)
		local eq = src:match("^%[(=*)%[", at)
		if not eq then
			return nil
		end
		local close = "]" .. eq .. "]"
		local s, e = src:find(close, at + #eq + 2, true)
		return src:sub(at + #eq + 2, (s or n + 1) - 1), (e or n) + 1
	end
	while i <= n do
		local c = src:sub(i, i)
		if c == "-" and src:sub(i + 1, i + 1) == "-" then
			local _, after = long(i + 2)
			i = after or ((src:find("\n", i, true) or n) + 1)
		elseif c == "[" and src:match("^%[=*%[", i) then
			local body, after = long(i)
			out[#out + 1] = body
			i = after
		elseif c == '"' or c == "'" then
			local buf, j = {}, i + 1
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then
					local num = src:match("^%d%d?%d?", j + 1)
					if num then
						buf[#buf + 1] = string.char(tonumber(num))
						j = j + 1 + #num
					else
						buf[#buf + 1] = src:sub(j + 1, j + 1)
						j = j + 2
					end
				elseif d == c or d == "\n" then
					break
				else
					buf[#buf + 1] = d
					j = j + 1
				end
			end
			local s = table.concat(buf)
			-- A Lua pattern's byte classes ("[\128-\255]") are not text shown to anyone.
			if not s:find("[", 1, true) then
				out[#out + 1] = s
			end
			i = j + 1
		else
			i = i + 1
		end
	end
	return table.concat(out, "\n")
end

T.case("The separators the code builds and every locale string have glyphs in every face (no middle dot)", function()
	local cmap = Cmap.Load(FACE)
	local files = {}
	-- git ls-files, as tests/test_source.lua does: `find` is another program on Windows.
	local p = io.popen("git ls-files -- Core Model Share Config Data UI Tracker")
	T.ok(p, "git ls-files can run")
	for path in p:lines() do
		if path:match("%.lua$") and not path:find("^Data/Plans/") then
			files[#files + 1] = path
		end
	end
	p:close()
	T.ok(#files > 50, "git ls-files listed the addon's Lua files (run the tests from a git checkout): " .. #files)
	for _, path in ipairs(files) do
		-- Discord export text is read in Discord, not in the game.
		if not path:find("Discord", 1, true) then
			local text = codeStrings(path)
			for _, c in ipairs(Cmap.CodePoints(text)) do
				T.ok(not NOT_IN_GAME_FACES[c], path .. ": " .. tostring(NOT_IN_GAME_FACES[c]))
			end
			local missing = {}
			for _, c in ipairs(cmap.Missing(text)) do
				-- Printable characters only: control bytes and byte ranges in patterns, and bytes that are no UTF-8 (a
				-- self-test's garbage input), are not text.
				if c >= 0xA0 and c <= 0x10FFFF then
					missing[#missing + 1] = c
				end
			end
			T.eq(#missing, 0, path .. " builds text the bundled face lacks: " .. (missing[1] and cp(missing[1]) or ""))
		end
	end
	for code, tbl in pairs(ns.Locales) do
		for k, v in pairs(tbl) do
			for _, s in ipairs({ type(k) == "string" and k or "", type(v) == "string" and v or "" }) do
				for _, c in ipairs(Cmap.CodePoints(s)) do
					T.ok(not NOT_IN_GAME_FACES[c], code .. " \"" .. s:sub(1, 40) .. "\": " .. tostring(NOT_IN_GAME_FACES[c]))
				end
			end
		end
	end
	-- A separator left at the end of a cut line goes with it (W.FitText): the bullet, three bytes.
	local fs = ns.Widgets.Text(UIParent, "body", "ink")
	fs:SetWidth(60)
	local shown = ns.Widgets.FitText(fs, "Pull \226\128\162 Interrupt \226\128\162 Crowd control and more words")
	T.ok(not shown:find("\226\128\162%.%.%.$") and not shown:find("[\128-\255]%.%.%.$"), "no separator before the dots: " .. shown)
end)

T.case("DPSans.ttf (the cleaned Latin copy) is never a Russian fallback", function()
	local cmap = Cmap.Load("Media/Fonts/DPSans.ttf")
	T.ok(not cmap.has[0x416], "DPSans has no Cyrillic; if it gains some, revisit UI/Fonts.lua")
	T.ok(ns.Style.POLISH_FACES[#ns.Style.POLISH_FACES] == ns.Style.CLEAN_FACE)
end)
