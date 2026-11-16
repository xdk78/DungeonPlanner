-- A bounded raw-DEFLATE (RFC 1951) decoder, after zlib's "puff" reference decoder.
--
-- Why not LibDeflate:DecompressDeflate? It has no output limit: a few kilobytes of hostile input can inflate to hundreds
-- of megabytes in pure Lua and freeze the client. Received plans are hostile input, so decoding stops as soon as the
-- output would pass `maxOut` bytes. LibDeflate is still used to compress (and for its print-safe encoding).
-- Pure arithmetic: no bit library needed, so the offline tests run it as is.

local _, ns = ...
local Inflate = ns:NewModule("Inflate")

local strbyte, strchar, unpack, concat = string.byte, string.char, unpack, table.concat

local POW2 = {}
for i = 0, 31 do
	POW2[i] = 2 ^ i
end

local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195,
	227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
	4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function fail(msg)
	error(msg, 0)
end

-- Read n bits, least significant first.
local function bits(st, n)
	local buf, cnt = st.bitbuf, st.bitcnt
	while cnt < n do
		local b = strbyte(st.s, st.pos)
		if not b then
			fail("truncated input")
		end
		st.pos = st.pos + 1
		buf = buf + b * POW2[cnt]
		cnt = cnt + 8
	end
	local p = POW2[n]
	local val = buf % p
	st.bitbuf = (buf - val) / p
	st.bitcnt = cnt - n
	return val
end

-- Build a canonical Huffman table from code lengths[offset .. offset+n-1] (symbols 0..n-1).
local function construct(lengths, offset, n)
	local count, symbol, offs = {}, {}, {}
	for len = 0, 15 do
		count[len] = 0
	end
	for sym = 0, n - 1 do
		local len = lengths[offset + sym]
		count[len] = count[len] + 1
	end
	if count[0] == n then
		return { count = count, symbol = symbol }, 0
	end
	local left = 1
	for len = 1, 15 do
		left = left * 2 - count[len]
		if left < 0 then
			fail("over-subscribed code")
		end
	end
	offs[1] = 0
	for len = 1, 14 do
		offs[len + 1] = offs[len] + count[len]
	end
	for sym = 0, n - 1 do
		local len = lengths[offset + sym]
		if len ~= 0 then
			symbol[offs[len]] = sym
			offs[len] = offs[len] + 1
		end
	end
	return { count = count, symbol = symbol }, left
end

local function decode(st, h)
	local code, first, index = 0, 0, 0
	local count = h.count
	for len = 1, 15 do
		code = code + bits(st, 1)
		local c = count[len]
		if code - c < first then
			local sym = h.symbol[index + (code - first)]
			if sym == nil then
				fail("bad code")
			end
			return sym
		end
		index = index + c
		first = (first + c) * 2
		code = code * 2
	end
	fail("ran out of codes")
end

local function put(st, byte)
	local n = st.outLen + 1
	if n > st.maxOut then
		fail("output too large")
	end
	st.out[n] = byte
	st.outLen = n
end

local function codes(st, lencode, distcode)
	local out = st.out
	while true do
		local sym = decode(st, lencode)
		if sym < 256 then
			put(st, sym)
		elseif sym == 256 then
			return
		else
			sym = sym - 257
			if sym >= 29 then
				fail("bad length symbol")
			end
			local len = LBASE[sym + 1] + bits(st, LEXT[sym + 1])
			local dsym = decode(st, distcode)
			if dsym >= 30 then
				fail("bad distance symbol")
			end
			local dist = DBASE[dsym + 1] + bits(st, DEXT[dsym + 1])
			if dist > st.outLen then
				fail("distance too far back")
			end
			if st.outLen + len > st.maxOut then
				fail("output too large")
			end
			local from = st.outLen - dist
			for i = 1, len do
				out[st.outLen + i] = out[from + i]
			end
			st.outLen = st.outLen + len
		end
	end
end

local fixedLen, fixedDist
local function fixedTables()
	if not fixedLen then
		local lengths = {}
		for sym = 0, 143 do
			lengths[sym] = 8
		end
		for sym = 144, 255 do
			lengths[sym] = 9
		end
		for sym = 256, 279 do
			lengths[sym] = 7
		end
		for sym = 280, 287 do
			lengths[sym] = 8
		end
		fixedLen = construct(lengths, 0, 288)
		local dl = {}
		for sym = 0, 29 do
			dl[sym] = 5
		end
		fixedDist = construct(dl, 0, 30)
	end
	return fixedLen, fixedDist
end

local function dynamic(st)
	local nlen = bits(st, 5) + 257
	local ndist = bits(st, 5) + 1
	local ncode = bits(st, 4) + 4
	if nlen > 286 or ndist > 30 then
		fail("bad counts")
	end
	local lengths = {}
	for i = 0, 18 do
		lengths[i] = 0
	end
	for i = 1, ncode do
		lengths[CLORDER[i]] = bits(st, 3)
	end
	local lencode, left = construct(lengths, 0, 19)
	if left ~= 0 then
		fail("incomplete code-length code")
	end
	lengths = {}
	local index = 0
	while index < nlen + ndist do
		local sym = decode(st, lencode)
		if sym < 16 then
			lengths[index] = sym
			index = index + 1
		else
			local len, rep = 0
			if sym == 16 then
				if index == 0 then
					fail("repeat with no first length")
				end
				len = lengths[index - 1]
				rep = 3 + bits(st, 2)
			elseif sym == 17 then
				rep = 3 + bits(st, 3)
			else
				rep = 11 + bits(st, 7)
			end
			if index + rep > nlen + ndist then
				fail("too many lengths")
			end
			for _ = 1, rep do
				lengths[index] = len
				index = index + 1
			end
		end
	end
	if lengths[256] == 0 then
		fail("no end-of-block code")
	end
	local lc, lleft = construct(lengths, 0, nlen)
	if lleft < 0 or (lleft > 0 and nlen - lc.count[0] ~= 1) then
		fail("incomplete literal/length code")
	end
	local dc, dleft = construct(lengths, nlen, ndist)
	if dleft < 0 or (dleft > 0 and ndist - dc.count[0] ~= 1) then
		fail("incomplete distance code")
	end
	codes(st, lc, dc)
end

local function stored(st)
	-- Discard the rest of the current byte.
	st.bitbuf, st.bitcnt = 0, 0
	local s, pos = st.s, st.pos
	if pos + 3 > #s then
		fail("truncated stored block")
	end
	local b1, b2, b3, b4 = strbyte(s, pos, pos + 3)
	local len = b1 + b2 * 256
	local nlen = b3 + b4 * 256
	if len + nlen ~= 65535 then
		fail("stored length mismatch")
	end
	pos = pos + 4
	if pos + len - 1 > #s then
		fail("truncated stored block")
	end
	if st.outLen + len > st.maxOut then
		fail("output too large")
	end
	for i = 0, len - 1 do
		st.out[st.outLen + 1 + i] = strbyte(s, pos + i)
	end
	st.outLen = st.outLen + len
	st.pos = pos + len
end

local function run(st)
	local last
	repeat
		last = bits(st, 1)
		local btype = bits(st, 2)
		if btype == 0 then
			stored(st)
		elseif btype == 1 then
			local lc, dc = fixedTables()
			codes(st, lc, dc)
		elseif btype == 2 then
			dynamic(st)
		else
			fail("bad block type")
		end
	until last == 1
end

-- Decompress raw DEFLATE data. Returns the string, or nil and a reason. Never returns more than maxOut bytes.
function Inflate.Raw(data, maxOut)
	if type(data) ~= "string" then
		return nil, "not a string"
	end
	local st = { s = data, pos = 1, bitbuf = 0, bitcnt = 0, out = {}, outLen = 0, maxOut = maxOut or 262144 }
	local ok, err = pcall(run, st)
	if not ok then
		return nil, tostring(err)
	end
	local parts = {}
	local CHUNK = 4096
	for i = 1, st.outLen, CHUNK do
		local j = i + CHUNK - 1
		if j > st.outLen then
			j = st.outLen
		end
		parts[#parts + 1] = strchar(unpack(st.out, i, j))
	end
	return concat(parts)
end
