-- Reads the character map of a TrueType file (cmap formats 4 and 12, Unicode platforms) so tests can ask whether a face
-- has a character. Plain Lua 5.1.
--   local cmap = require("ttf_cmap").Load("Media/Fonts/AlegreyaSans-Medium.ttf")
--   cmap.has[0x416]               -- true when the face has U+0416
--   cmap.Missing("Привет")        -- list of the code points of a UTF-8 string that the face lacks

local M = {}

local byte = string.byte

local function u16(s, i)
	local a, b = byte(s, i, i + 1)
	return a * 256 + b
end

local function u32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

local function format4(s, at, has)
	local segX2 = u16(s, at + 6)
	local ends, starts, deltas, offsets = at + 14, at + 16 + segX2, at + 16 + 2 * segX2, at + 16 + 3 * segX2
	for seg = 0, segX2 / 2 - 1 do
		local last, first = u16(s, ends + 2 * seg), u16(s, starts + 2 * seg)
		local delta, rangeOffset = u16(s, deltas + 2 * seg), u16(s, offsets + 2 * seg)
		for cp = first, last do
			if cp ~= 0xFFFF then
				local glyph
				if rangeOffset == 0 then
					glyph = (cp + delta) % 65536
				else
					glyph = u16(s, offsets + 2 * seg + rangeOffset + 2 * (cp - first))
					if glyph ~= 0 then
						glyph = (glyph + delta) % 65536
					end
				end
				if glyph ~= 0 then
					has[cp] = true
				end
			end
		end
	end
end

local function format12(s, at, has)
	for g = 0, u32(s, at + 12) - 1 do
		local first, last, glyph = u32(s, at + 16 + 12 * g), u32(s, at + 20 + 12 * g), u32(s, at + 24 + 12 * g)
		for cp = first, last do
			if glyph + (cp - first) ~= 0 then
				has[cp] = true
			end
		end
	end
end

-- The UTF-8 string's code points.
function M.CodePoints(text)
	local out = {}
	local i = 1
	while i <= #text do
		local c = byte(text, i)
		local cp, n
		if c < 0x80 then
			cp, n = c, 1
		elseif c < 0xE0 then
			cp, n = (c % 0x20) * 0x40 + (byte(text, i + 1) % 0x40), 2
		elseif c < 0xF0 then
			cp, n = ((c % 0x10) * 0x40 + (byte(text, i + 1) % 0x40)) * 0x40 + (byte(text, i + 2) % 0x40), 3
		else
			cp, n = (((c % 8) * 0x40 + (byte(text, i + 1) % 0x40)) * 0x40 + (byte(text, i + 2) % 0x40)) * 0x40
				+ (byte(text, i + 3) % 0x40), 4
		end
		out[#out + 1] = cp
		i = i + n
	end
	return out
end

function M.Load(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	local numTables = u16(s, 5)
	local cmapAt
	for t = 0, numTables - 1 do
		local rec = 13 + 16 * t
		if s:sub(rec, rec + 3) == "cmap" then
			cmapAt = u32(s, rec + 8) + 1
		end
	end
	assert(cmapAt, path .. ": no cmap table")
	local has = {}
	for sub = 0, u16(s, cmapAt + 2) - 1 do
		local platform, encoding = u16(s, cmapAt + 4 + 8 * sub), u16(s, cmapAt + 6 + 8 * sub)
		local at = cmapAt + u32(s, cmapAt + 8 + 8 * sub)
		local unicode = platform == 0 or (platform == 3 and (encoding == 1 or encoding == 10))
		if unicode then
			local format = u16(s, at)
			if format == 4 then
				format4(s, at, has)
			elseif format == 12 then
				format12(s, at, has)
			end
		end
	end
	local cmap = { has = has }
	function cmap.Missing(text)
		local out, seen = {}, {}
		for _, cp in ipairs(M.CodePoints(text)) do
			if not has[cp] and not seen[cp] and cp >= 0x20 then
				seen[cp] = true
				out[#out + 1] = cp
			end
		end
		return out
	end
	return cmap
end

return M
