-- Loads Dungeon Planner's pure modules (validation, export strings) in plain Lua 5.1, without the game.
-- Used by tools/validate_plans.lua and tools/build_pack.lua. Run those from the repo root.

local M = {}

function M.Load()
	_G.time = _G.time or os.time
	local ns = {}
	local function load(path)
		local chunk = assert(loadfile(path))
		chunk("DungeonPlanner", ns)
	end
	load("Libs/LibStub/LibStub.lua")
	load("Libs/LibSerialize/LibSerialize.lua")
	load("Libs/LibDeflate/LibDeflate.lua")
	for _, path in ipairs({
		"Core/Init.lua",
		"Core/Util.lua",
		"Locales/enUS.lua",
		"Model/Schema.lua",
		"Model/Validate.lua",
		"Model/Plan.lua",
		"Model/PlanLists.lua",
		"Model/PlanBosses.lua",
		"Model/Pages.lua", -- Validate.Plan checks raid pages through it
		"Share/Checksum.lua",
		"Share/Inflate.lua",
		"Share/Codec.lua",
	}) do
		load(path)
	end
	return ns
end

-- A community plan file: "key: value" header lines, a line "---", then the export string (may span lines).
function M.ParseFile(text)
	local header, body = text:match("^(.-)\n%-%-%-%s*\n(.*)$")
	if not header then
		return nil, "missing the '---' line between the header and the export string"
	end
	local fields = {}
	for line in (header .. "\n"):gmatch("(.-)\r?\n") do
		if not line:match("^%s*#") and line:match("%S") then
			local key, value = line:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
			if not key then
				return nil, "bad header line: " .. line
			end
			fields[key:lower()] = value
		end
	end
	return fields, body
end

return M
