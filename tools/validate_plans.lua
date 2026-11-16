-- Validates community plan files (community-plans/**/*.dpplan). CI runs it on every push and pull request.
--   lua tools/validate_plans.lua                      -- every file under community-plans/
--   lua tools/validate_plans.lua path/to/file.dpplan  -- just these
-- A file passes when its header has the required fields, its export string decodes (checksum, size limits) and the
-- plan survives validation without anything dropped. Exit code 1 on any failure.

package.path = "./tools/?.lua;" .. package.path
local offline = require("offline")
local ns = offline.Load()

local REQUIRED = { "title", "instance", "author", "client", "license" }
local CLIENTS = { ["forever 16001"] = true }
local MAX_FILE = 200000

local function listFiles()
	local files = {}
	local cmd = package.config:sub(1, 1) == "\\" and 'dir /s /b community-plans\\*.dpplan 2>nul'
		or 'find community-plans -name "*.dpplan" 2>/dev/null'
	local p = io.popen(cmd)
	for line in p:lines() do
		files[#files + 1] = line
	end
	p:close()
	table.sort(files)
	return files
end

local function check(path)
	local f = io.open(path, "rb")
	if not f then
		return false, "cannot open"
	end
	local text = f:read("*a")
	f:close()
	if #text > MAX_FILE then
		return false, "file larger than " .. MAX_FILE .. " bytes"
	end
	local fields, body = offline.ParseFile(text)
	if not fields then
		return false, body
	end
	for _, key in ipairs(REQUIRED) do
		if not fields[key] or fields[key] == "" then
			return false, "header field missing: " .. key
		end
	end
	if not CLIENTS[fields.client:lower()] then
		return false, "unknown client '" .. fields.client .. "' (expected: forever 16001)"
	end
	if fields.license ~= "CC0-1.0" and fields.license ~= "CC-BY-4.0" then
		return false, "license must be CC0-1.0 or CC-BY-4.0"
	end
	local kind, value, report = ns.Codec.Decode(body)
	if not kind then
		return false, "export string: " .. tostring(value)
	end
	local summary = ns.Validate.Summary(report)
	if summary then
		return false, "invalid parts would be dropped on import: " .. summary
	end
	local plans = kind == "plan" and { value } or value.plans
	for _, plan in ipairs(plans) do
		if plan.source then
			return false, "remove the source field (export the plan again)"
		end
	end
	if kind == "plan" and value.name ~= fields.title then
		return true, string.format("note: title '%s' differs from the plan name '%s'", fields.title, value.name)
	end
	return true, string.format("%s, %d plan(s)", kind, #plans)
end

local files = {}
for i = 1, #arg do
	files[#files + 1] = arg[i]
end
if #files == 0 then
	files = listFiles()
end

local failed = 0
for _, path in ipairs(files) do
	local ok, msg = check(path)
	print(string.format("%s %s: %s", ok and "ok  " or "FAIL", path, msg or ""))
	if not ok then
		failed = failed + 1
	end
end
print(string.format("%d file(s), %d failed", #files, failed))
os.exit(failed == 0 and 0 or 1)
