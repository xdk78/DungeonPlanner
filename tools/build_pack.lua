-- Builds one "import pack" string from community plan files, for players to paste into Share > Import.
--   lua tools/build_pack.lua "Pack name" community-plans/forever/*.dpplan > pack.txt
-- Every file is validated first (same rules as validate_plans.lua decoding).

package.path = "./tools/?.lua;" .. package.path
local offline = require("offline")
local ns = offline.Load()

local name = arg[1]
if not name or #arg < 2 then
	io.stderr:write('usage: lua tools/build_pack.lua "Pack name" file.dpplan [...]\n')
	os.exit(2)
end

local plans = {}
for i = 2, #arg do
	local f = assert(io.open(arg[i], "rb"))
	local text = f:read("*a")
	f:close()
	local fields, body = offline.ParseFile(text)
	if not fields then
		io.stderr:write(arg[i] .. ": " .. tostring(body) .. "\n")
		os.exit(1)
	end
	local kind, value = ns.Codec.Decode(body)
	if not kind then
		io.stderr:write(arg[i] .. ": " .. tostring(value) .. "\n")
		os.exit(1)
	end
	for _, plan in ipairs(kind == "plan" and { value } or value.plans) do
		plans[#plans + 1] = plan
	end
end
if #plans > ns.Schema.MAX.plansPerPack then
	io.stderr:write("too many plans for one pack (max " .. ns.Schema.MAX.plansPerPack .. ")\n")
	os.exit(1)
end
io.write(assert(ns.Codec.ExportPack(name, "Built from community-plans/", plans)), "\n")
