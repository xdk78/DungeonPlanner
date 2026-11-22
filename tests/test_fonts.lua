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

T.case("DPSans.ttf (the cleaned Latin copy) is never a Russian fallback", function()
	local cmap = Cmap.Load("Media/Fonts/DPSans.ttf")
	T.ok(not cmap.has[0x416], "DPSans has no Cyrillic; if it gains some, revisit UI/Fonts.lua")
	T.ok(ns.Style.POLISH_FACES[#ns.Style.POLISH_FACES] == ns.Style.CLEAN_FACE)
end)
