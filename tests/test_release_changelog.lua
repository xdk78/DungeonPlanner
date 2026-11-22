-- The release's changelog (tools/release_changelog.lua, run by .github/workflows/release.yml before the packager): only
-- the tag's section of CHANGELOG.md, the repository's paths linked to the tag, and no release without a section.
-- Checked against the real CHANGELOG.md (its 0.2.0 and 0.1.0 sections stay as released).
local T = ...
local R = dofile("tools/release_changelog.lua")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local changelog = read("CHANGELOG.md")
local BASE = "https://github.com/xdk78/DungeonPlanner"

T.case("Release changelog: the 0.2.0 section alone", function()
	local body = assert(R.Section(changelog, R.Version("v0.2.0")))
	T.ok(body:find("^Highlights, upgrade notes"), "starts with the section's first line, not its heading")
	T.ok(body:find("### Added", 1, true), "its subsections")
	T.ok(not body:find("## [", 1, true), "no other section's heading")
	T.ok(not body:find("All notable changes", 1, true), "not the file's introduction")
	local unreleased = R.Section(changelog, "Unreleased")
	T.ok(not unreleased or not body:find(unreleased, 1, true), "not [Unreleased]")
	local older = assert(R.Section(changelog, "0.1.0"))
	T.ok(not body:find(older:match("^[^\n]+"), 1, true), "nothing of 0.1.0")
	T.eq(body:sub(-1), "\n")
	T.ok(not body:find("\n\n$"), "no blank lines at the end")
	T.eq(R.Version("refs/tags/v0.2.0"), "0.2.0")
end)

T.case("Release changelog: the last section runs to the end of the file", function()
	local body = assert(R.Section(changelog, "0.1.0"))
	local tail = changelog:gsub("\r\n", "\n"):gsub("%s+$", "")
	T.eq(body:gsub("%s+$", ""), tail:sub(-#body:gsub("%s+$", "")), "the file's last lines")
end)

T.case("Release changelog: repository paths become links to the tag; other links stay", function()
	local paths = R.RepoPaths()
	local out = R.Linkify(assert(R.Section(changelog, "0.2.0")), paths, BASE, "v0.2.0")
	T.ok(out:find("[`docs/RELEASE-NOTES-0.2.0.md`](" .. BASE .. "/blob/v0.2.0/docs/RELEASE-NOTES-0.2.0.md)", 1, true),
		"a path in backticks")
	T.ok(out:find("[`Locales/README.md`](" .. BASE .. "/blob/v0.2.0/Locales/README.md)", 1, true), "another")
	T.ok(out:find("[`data-src/travel/`](" .. BASE .. "/tree/v0.2.0/data-src/travel)", 1, true), "a folder")
	T.ok(out:find("`/dp debug`", 1, true) and not out:find("[`/dp debug`]", 1, true), "code that is no path stays")
	for target in out:gmatch("%b[]%((.-)%)") do
		T.ok(target:find("^https?://") or target:find("^#"), "every link absolute: " .. target)
	end
	-- 0.1.0 has relative Markdown links and plain paths.
	local old = R.Linkify(assert(R.Section(changelog, "0.1.0")), paths, BASE, "v0.1.0")
	T.ok(old:find("[docs/API.md](" .. BASE .. "/blob/v0.1.0/docs/API.md)", 1, true), "a relative link's target")
	T.ok(old:find("[AGENTS.md](" .. BASE .. "/blob/v0.1.0/AGENTS.md)", 1, true), "a plain path")
	for target in old:gmatch("%b[]%((.-)%)") do
		T.ok(target:find("^https?://") or target:find("^#"), "every link absolute: " .. target)
	end
	-- Shapes the current file does not have: an anchor, a ./ path, an external link, a path at a sentence's end.
	local text = "See [the API](./docs/API.md#events), [Keep a Changelog](https://keepachangelog.com/) and"
		.. " docs/API.md. Not a path: notes.md, e.g. or 1.2.\n"
	T.eq(R.Linkify(text, paths, BASE, "v9.9.9"), "See [the API](" .. BASE .. "/blob/v9.9.9/docs/API.md#events),"
		.. " [Keep a Changelog](https://keepachangelog.com/) and [docs/API.md](" .. BASE .. "/blob/v9.9.9/docs/API.md)."
		.. " Not a path: notes.md, e.g. or 1.2.\n")
end)

T.case("Release changelog: a heading's date need not be the tag's; no section or an empty one fails", function()
	local text = "# Changelog\n\n## [Unreleased]\n\n- next\n\n## [1.2.0] - 2020-01-31\n\n- one\n- two\n\n## [1.1.0]\n\n"
		.. "## [1.0.0] - 2019-12-01\n- first\n"
	T.eq(R.Section(text, R.Version("v1.2.0")), "- one\n- two\n", "the date in the heading is not compared")
	T.eq(R.Latest(text), "1.2.0", "the newest released section, not [Unreleased]")
	local none, why = R.Section(text, "1.3.0")
	T.eq(none, nil)
	T.ok(why:find("no section for 1.3.0", 1, true), why)
	local empty, why2 = R.Section(text, "1.1.0")
	T.eq(empty, nil)
	T.ok(why2:find("empty", 1, true), why2)
	-- The command line: exit code 1 and the reason, nothing written.
	local code, message = R.Main({ "v99.0.0" })
	T.eq(code, 1)
	T.ok(message:find("no section for 99.0.0", 1, true), message)
	-- The newest released section of the real file (what CI checks before a tag).
	local latest = R.Latest(changelog)
	T.ok(latest and latest:find("^%d+%.%d+%.%d+$"), "a released version heads the file: " .. tostring(latest))
	local ok, body = R.Main({ "--latest" })
	T.eq(ok, 0, body)
	T.ok(#body > 0)
end)
