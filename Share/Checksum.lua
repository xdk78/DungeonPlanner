-- Adler-32 (RFC 1950) in plain arithmetic: Lua 5.1 has no bit operators and the offline tests run without WoW's `bit`.
-- Used to detect corrupted or truncated export strings and transfers, not as a security measure.

local _, ns = ...
local Checksum = ns:NewModule("Checksum")

local strbyte = string.byte
local MOD = 65521
local NMAX = 5552 -- zlib's block size: sums stay small before each modulo

function Checksum.Adler32(s)
	local a, b = 1, 0
	local len = #s
	local i = 1
	while i <= len do
		local stop = i + NMAX - 1
		if stop > len then
			stop = len
		end
		for j = i, stop do
			a = a + strbyte(s, j)
			b = b + a
		end
		a = a % MOD
		b = b % MOD
		i = stop + 1
	end
	return b * 65536 + a
end

-- Two 16-bit halves: Lua 5.1's %x goes through a C long, which is 32-bit and signed on Windows.
function Checksum.Hex(n)
	return string.format("%04x%04x", math.floor(n / 65536), n % 65536)
end
