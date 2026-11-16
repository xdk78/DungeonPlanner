-- Renders an export string (or a community .dpplan file) as Discord messages, outside the game - the same text the
-- in-game "Discord" export makes. Output: the parts, separated by a line "=== part n/N ===".
--   lua tools/discord_render.lua community-plans/examples/template-five-player-run.dpplan [summary|full] [nostring]
-- No network access: post the parts yourself (or with a webhook tool you trust; never commit a webhook URL).

package.path = "./tools/?.lua;" .. package.path
local offline = require("offline")
local ns = offline.Load()
assert(loadfile("Share/Discord.lua"))("DungeonPlanner", ns)

local path, mode, nostring = arg[1], arg[2] or "full", arg[3] == "nostring"
if not path then
	io.stderr:write("usage: lua tools/discord_render.lua <file.dpplan|file.txt> [summary|full] [nostring]\n")
	os.exit(2)
end
local f = assert(io.open(path, "rb"))
local text = f:read("*a")
f:close()
local fields, body = offline.ParseFile(text)
if not fields then
	body = text
end
local kind, value = ns.Codec.Decode(body)
if not kind then
	io.stderr:write("cannot decode: " .. tostring(value) .. "\n")
	os.exit(1)
end
for _, plan in ipairs(kind == "plan" and { value } or value.plans) do
	local parts = ns.Discord.Render(plan, {
		mode = mode,
		version = "community",
		importString = not nostring and ns.Codec.ExportPlan(plan) or nil,
	})
	for n, part in ipairs(parts) do
		io.write(string.format("=== part %d/%d ===\n%s\n", n, #parts, part))
	end
end
