-- The source text itself: no stray control bytes and valid UTF-8 in every tracked text file. A raw byte 0x01 followed by
-- "94p" (what was left of the escape "\194\160") once reached the game and drew a box and "94p" after every estimate.
local T = ...

local function trackedTextFiles()
	local pipe = io.popen("git ls-files")
	T.ok(pipe, "git ls-files can run")
	local files = {}
	for line in pipe:lines() do
		local ext = line:match("%.(%w+)$")
		if ext == "lua" or ext == "toc" or ext == "xml" or ext == "md" then
			files[#files + 1] = line
		end
	end
	pipe:close()
	T.ok(#files > 100, "git ls-files listed the repository's files")
	return files
end

-- 1-based byte position of the first invalid UTF-8 sequence, or nil.
local function badUtf8(s)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local len = c < 0x80 and 1 or c >= 0xC2 and c <= 0xDF and 2 or c >= 0xE0 and c <= 0xEF and 3
			or c >= 0xF0 and c <= 0xF4 and 4 or nil
		if not len or i + len - 1 > n then
			return i
		end
		for k = i + 1, i + len - 1 do
			local cc = s:byte(k)
			if cc < 0x80 or cc > 0xBF then
				return i
			end
		end
		i = i + len
	end
	return nil
end

T.case("Source: tracked .lua/.toc/.xml/.md files have no control characters but tab, LF and CR, and are UTF-8", function()
	local problems = {}
	for _, path in ipairs(trackedTextFiles()) do
		local f = io.open(path, "rb")
		if f then
			local text = f:read("*a")
			f:close()
			local line = 1
			for pos = 1, #text do
				local b = text:byte(pos)
				if b == 10 then
					line = line + 1
				elseif (b < 32 and b ~= 9 and b ~= 13) or b == 127 then
					problems[#problems + 1] = string.format("%s:%d: control byte 0x%02X", path, line, b)
					break
				end
			end
			local bad = badUtf8(text)
			if bad then
				local _, lines = text:sub(1, bad):gsub("\n", "")
				problems[#problems + 1] = string.format("%s:%d: invalid UTF-8", path, lines + 1)
			end
		end
	end
	T.eq(#problems, 0, table.concat(problems, "; "))
end)
