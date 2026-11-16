-- Pure helpers shared by every module. No WoW API calls except the guarded secret-value check, so this file loads in
-- plain Lua 5.1 for the offline tests.

local _, ns = ...
local Util = ns:NewModule("Util")

local type, tostring, tonumber, pairs, ipairs = type, tostring, tonumber, pairs, ipairs
local floor, huge = math.floor, math.huge
local strbyte, strsub, strgsub, strfind = string.byte, string.sub, string.gsub, string.find

-- Secret values (Midnight / Forever): a value the client hands over opaquely. Comparing one raises, so anything read from
-- the game that we compare or store goes through Plain(). Returns nil for a secret.
function Util.IsSecret(value)
	local check = issecretvalue
	if type(check) == "function" then
		local ok, secret = pcall(check, value)
		return ok and secret == true
	end
	return false
end

function Util.Plain(value)
	if Util.IsSecret(value) then
		return nil
	end
	return value
end

function Util.IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > -huge and value < huge
end

function Util.IsInteger(value)
	return Util.IsFiniteNumber(value) and value == floor(value)
end

function Util.Clamp(value, low, high)
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

-- Round to `decimals` places (coordinates are stored with 4: ~0.1 px on a 1000 px map, and short export strings).
function Util.Round(value, decimals)
	local m = 10 ^ (decimals or 0)
	return floor(value * m + 0.5) / m
end

-- Linear in the length of s: a lazy "(.-)%s*$" rescans every run of spaces from each of its characters, which a
-- received text made of spaces turns into seconds of work.
function Util.Trim(s)
	return string.match(s, "^%s*(.*%S)") or ""
end

-- Recommended plans mark estimated spots with "(approx.)" in their notes (docs/DATA-SOURCES.md). Returns the text
-- without that mark and whether it had it, so the UI shows a small marker instead of the words.
function Util.SplitApprox(text)
	if type(text) ~= "string" then
		return text, false
	end
	local cleaned, n = strgsub(text, "%s*%(approx%.%)", "")
	if n == 0 then
		return text, false
	end
	return Util.Trim(cleaned), true
end

-- Cut a UTF-8 string to at most maxBytes without splitting a character.
function Util.TruncateUTF8(s, maxBytes)
	if #s <= maxBytes then
		return s
	end
	local cut = maxBytes
	-- Step back over continuation bytes (10xxxxxx) so the cut lands on a character boundary.
	while cut > 0 do
		local b = strbyte(s, cut + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return strsub(s, 1, cut)
end

-- Remove WoW UI escape sequences and control characters from user text. Imported and received text is shown in our
-- frames; stripping escapes keeps it from drawing textures, hyperlinks or colours we did not intend.
-- Kept: plain text, newlines, tabs. Removed: |c........ |r |T...|t |A...|a |H...|h |K...|k |n || and stray pipes.
function Util.StripEscapes(s)
	s = strgsub(s, "|[Cc]%x%x%x%x%x%x%x%x", "")
	s = strgsub(s, "|[Cc]n[^:|]*:", "") -- |cn<colour name>:
	s = strgsub(s, "|[Rr]", "")
	-- Each of these stops at the next pipe, so text full of unclosed "|T" costs one pass, not one pass per "|T"
	-- (a lazy ".-" scans to the end of the text from every opener that has no closer).
	s = strgsub(s, "|T[^|]*|t", "")
	s = strgsub(s, "|A[^|]*|a", "")
	s = strgsub(s, "|K[^|]*|k", "")
	s = strgsub(s, "|H[^|]*|h", "") -- a link's opening part; its text stays
	s = strgsub(s, "|h", "")
	s = strgsub(s, "|n", "\n")
	s = strgsub(s, "|", "")
	-- Control characters except \t (9) and \n (10).
	s = strgsub(s, "[%z\1-\8\11-\31\127]", "")
	return s
end

-- Clean user or received text: string only, escapes stripped, trimmed when single-line, UTF-8-safe length cap.
function Util.CleanText(value, maxBytes, multiline)
	if type(value) == "number" then
		value = tostring(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	value = Util.StripEscapes(value)
	if not multiline then
		value = strgsub(value, "[\r\n\t]", " ")
		value = Util.Trim(value)
	else
		value = strgsub(value, "\r\n?", "\n")
	end
	return Util.TruncateUTF8(value, maxBytes)
end

function Util.DeepCopy(value, depth)
	depth = depth or 0
	if type(value) ~= "table" or depth > 32 then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[Util.DeepCopy(k, depth + 1)] = Util.DeepCopy(v, depth + 1)
	end
	return copy
end

-- Deterministic key order: numbers ascending, then strings ascending, then anything else by tostring.
local function keyRank(k)
	local t = type(k)
	if t == "number" then
		return 1
	elseif t == "string" then
		return 2
	end
	return 3
end

function Util.SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local ra, rb = keyRank(a), keyRank(b)
		if ra ~= rb then
			return ra < rb
		end
		if ra == 3 then
			return tostring(a) < tostring(b)
		end
		return a < b
	end)
	return keys
end

function Util.Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

function Util.IndexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

function Util.FindById(list, id)
	if type(list) ~= "table" then
		return nil
	end
	for i, item in ipairs(list) do
		if item.id == id then
			return item, i
		end
	end
	return nil
end

function Util.Split(s, sep, plain)
	local parts, start = {}, 1
	while true do
		local i, j = strfind(s, sep, start, plain ~= false)
		if not i then
			parts[#parts + 1] = strsub(s, start)
			break
		end
		parts[#parts + 1] = strsub(s, start, i - 1)
		start = j + 1
	end
	return parts
end

-- Player names on Forever carry no realm (docs/COMPATIBILITY.md); Ambiguate also strips one if a client ever adds it.
function Util.ShortName(name)
	name = Util.Plain(name)
	if type(name) ~= "string" then
		return nil
	end
	if Ambiguate then
		local ok, short = pcall(Ambiguate, name, "none")
		if ok and type(short) == "string" then
			return short
		end
	end
	return (strgsub(name, "%-.*$", ""))
end

-- Parse an item reference: a number, "12345", or an item link "|Hitem:12345:...". Returns a positive integer or nil.
function Util.ParseItemID(value)
	if type(value) == "number" then
		if Util.IsInteger(value) and value > 0 and value < 2 ^ 31 then
			return value
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local id = value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$")
	id = tonumber(id)
	if id and id > 0 and id < 2 ^ 31 then
		return id
	end
	return nil
end

-- A short random-ish id suffix; uniqueness inside a plan comes from the plan's counter, this only separates plans.
local counter = 0
function Util.UniqueId(prefix)
	counter = counter + 1
	local t = (ns.Now and ns.Now()) or 0
	return string.format("%s%x%04x%02x", prefix or "", t, floor(math.random() * 0xFFFF), counter % 256)
end
