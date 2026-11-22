-- The changelog of one release: the section of CHANGELOG.md for that version, with the repository's own paths turned
-- into links to the release's tag, for the packager's manual changelog (.pkgmeta), which is the CurseForge file's
-- changelog and the GitHub release's text. Run from the repository root:
--   lua tools/release_changelog.lua v0.2.0 [--out .release/CHANGELOG-release.md] [--repo https://github.com/owner/name]
--   lua tools/release_changelog.lua --latest [--out <file>]     # the newest released section (CI checks its shape)
-- The section is the lines under "## [0.2.0] ..." (whatever follows the brackets, such as a date) up to the next
-- "## [". Paths of files or folders the repository has (`git ls-files`), as a relative Markdown link, in backticks or
-- in plain text, become links to that path at the tag (blob for a file, tree for a folder); the paths are the tag's
-- when git has it (`git ls-tree`), else the checkout's. Exit code 1, with the
-- reason, when the version has no section or its section is empty: a release never goes out with the whole file.

local M = {}

M.REPO = "https://github.com/xdk78/DungeonPlanner"

-- "v0.2.0", "refs/tags/v0.2.0" or "0.2.0" -> "0.2.0"
function M.Version(tag)
	return (tostring(tag):gsub("^refs/tags/", ""):gsub("^v", ""))
end

local function lines(text)
	local out = {}
	for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end

-- The body of `version`'s section (no heading, no blank lines at either end), or nil and why.
function M.Section(text, version)
	local body, inside = {}, false
	for _, line in ipairs(lines(text)) do
		local name = line:match("^## %[(.-)%]")
		if name then
			if inside then
				break
			end
			inside = name == version
		elseif inside then
			body[#body + 1] = line
		end
	end
	if not inside then
		return nil, string.format('CHANGELOG.md has no section for %s: add a heading "## [%s] - <date>" before tagging',
			version, version)
	end
	while body[1] and body[1]:match("^%s*$") do
		table.remove(body, 1)
	end
	while body[#body] and body[#body]:match("^%s*$") do
		table.remove(body)
	end
	if #body == 0 then
		return nil, string.format("CHANGELOG.md's section for %s is empty", version)
	end
	return table.concat(body, "\n") .. "\n"
end

-- The newest released version: the first "## [x.y.z]" heading that is not [Unreleased].
function M.Latest(text)
	for _, line in ipairs(lines(text)) do
		local name = line:match("^## %[(.-)%]")
		if name and name ~= "Unreleased" then
			return name
		end
	end
	return nil
end

-- The repository's paths at `ref` when git knows that ref (`git ls-tree`), else the checkout's (`git ls-files`):
-- { files = { [path] = true }, dirs = { [path] = true } }.
function M.RepoPaths(ref)
	local files, dirs = {}, {}
	local cmd = "git ls-files"
	if ref and ref:match("^[%w%._%-]+$") then
		-- Quoted: cmd.exe would take ^ as its escape character.
		local probe = io.popen('git rev-parse --verify --quiet "' .. ref .. '^{commit}"')
		local known = probe:read("*a"):match("%x+")
		probe:close()
		if known then
			cmd = "git ls-tree -r --name-only " .. ref
		end
	end
	local p = io.popen(cmd)
	for path in p:read("*a"):gmatch("[^\r\n]+") do
		files[path] = true
		local dir = path:match("^(.+)/[^/]+$")
		while dir and not dirs[dir] do
			dirs[dir] = true
			dir = dir:match("^(.+)/[^/]+$")
		end
	end
	p:close()
	return { files = files, dirs = dirs }
end

-- The URL of a repository path at `ref`, or nil when the repository has no such path.
local function urlOf(path, paths, base, ref)
	local clean = path:gsub("^%./", ""):gsub("/$", "")
	if paths.files[clean] then
		return base .. "/blob/" .. ref .. "/" .. clean
	elseif paths.dirs[clean] then
		return base .. "/tree/" .. ref .. "/" .. clean
	end
	return nil
end

-- Plain text: every word that is a repository path becomes a link (punctuation after it stays outside).
local function plain(text, paths, base, ref)
	return (text:gsub("[%w_%.%-/]+", function(word)
		local path, rest = word:match("^(.-)([%.]*)$")
		local url = (path:find("/", 1, true) or path:find(".", 1, true)) and urlOf(path, paths, base, ref)
		if url then
			return "[" .. path .. "](" .. url .. ")" .. rest
		end
		return word
	end))
end

-- One line: Markdown links (relative targets rewritten), code spans (a repository path in them linked), plain text.
local function line(text, paths, base, ref)
	local out, i = {}, 1
	while i <= #text do
		local ls, le, label, target = text:find("(%b[])(%b())", i)
		local cs = text:find("`", i, true)
		local ce = cs and text:find("`", cs + 1, true)
		if ls and (not ce or ls < cs) then
			out[#out + 1] = plain(text:sub(i, ls - 1), paths, base, ref)
			local dest = target:sub(2, -2)
			local path, anchor = dest:match("^([^#]*)(.*)$")
			if path ~= "" and not path:match("^%a[%w+.%-]*:") and not path:match("^/") then
				local url = urlOf(path, paths, base, ref)
				if url then
					dest = url .. anchor
				end
			end
			out[#out + 1] = label .. "(" .. dest .. ")"
			i = le + 1
		elseif ce then
			out[#out + 1] = plain(text:sub(i, cs - 1), paths, base, ref)
			local code = text:sub(cs, ce)
			local url = urlOf(code:sub(2, -2), paths, base, ref)
			out[#out + 1] = url and ("[" .. code .. "](" .. url .. ")") or code
			i = ce + 1
		else
			out[#out + 1] = plain(text:sub(i), paths, base, ref)
			break
		end
	end
	return table.concat(out)
end

-- `text` with the repository's paths linked to `ref` (a tag) at `base` (the repository's URL).
function M.Linkify(text, paths, base, ref)
	local out = {}
	for _, l in ipairs(lines(text)) do
		out[#out + 1] = line(l, paths, base, ref)
	end
	return table.concat(out, "\n"):gsub("\n+$", "") .. "\n"
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- The command line. Returns the exit code and what to print (to stderr when the code is not 0).
function M.Main(args)
	local opts, tag = { changelog = "CHANGELOG.md", repo = M.REPO }, nil
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--out" or a == "--repo" or a == "--changelog" then
			opts[a:sub(3)] = args[i + 1]
			i = i + 1
		elseif a == "--latest" then
			opts.latest = true
		else
			tag = a
		end
		i = i + 1
	end
	local text = read(opts.changelog)
	if not text then
		return 1, "cannot read " .. opts.changelog
	end
	local version = tag and M.Version(tag) or (opts.latest and M.Latest(text))
	if not version then
		return 1, "usage: lua tools/release_changelog.lua <tag> | --latest [--out FILE] [--repo URL]"
	end
	local body, err = M.Section(text, version)
	if not body then
		return 1, err
	end
	local ref = "v" .. version
	local out = M.Linkify(body, M.RepoPaths(ref), (opts.repo:gsub("/+$", "")), ref)
	if opts.out then
		local f = io.open(opts.out, "wb")
		if not f then
			return 1, "cannot write " .. opts.out
		end
		f:write(out)
		f:close()
		return 0, string.format("%s: the changelog of %s (%d lines)", opts.out, version, select(2, out:gsub("\n", "")))
	end
	return 0, out
end

if arg and type(arg[0]) == "string" and arg[0]:find("release_changelog", 1, true) then
	local code, message = M.Main(arg)
	if code == 0 then
		io.write(message:sub(-1) == "\n" and message or message .. "\n")
	else
		io.stderr:write("release_changelog: " .. message .. "\n")
	end
	os.exit(code)
end
return M
