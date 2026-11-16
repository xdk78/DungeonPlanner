-- Export strings: what players copy, paste, post and submit to the community repository.
--
--   !DP2!<print-safe text>          (!DP1! strings from version 1 still decode; Validate.Plan upgrades them)
--   print-safe text = LibDeflate:EncodeForPrint( raw DEFLATE( body ) )
--   body            = kind "\n" adler32-hex "\n" payload
--   payload         = LibSerialize:Serialize(plan or pack)
--
-- kind is "plan" or "pack". Compression and serialization use the standard libraries (LibDeflate, LibSerialize);
-- decompression uses our bounded inflater (Share/Inflate.lua) so a hostile string cannot inflate without limit.
-- LibSerialize's reader never executes code; its result is then rebuilt field by field by Validate.Plan / Validate.Pack.
-- The full specification is docs/SHARING-FORMAT.md.

local _, ns = ...
local Codec = ns:NewModule("Codec")
local Checksum, Inflate, Validate = ns.Checksum, ns.Inflate, ns.Validate

Codec.VERSION = 2
Codec.HEADER = "!DP" .. Codec.VERSION .. "!"
Codec.READABLE = { [1] = true, [2] = true } -- header versions this build decodes
Codec.KINDS = { plan = true, pack = true }
Codec.LIMITS = {
	encodedChars = 400000, -- what a paste may contain
	inflatedBytes = 1024 * 1024, -- bounded inflate
	-- A pushed page arrives without a prompt, so it gets a limit of its own: a page is at most Schema.TEXT.page bytes
	-- of text plus a few short fields.
	noteInflatedBytes = 32 * 1024,
}

local function libs()
	if not LibStub then
		return nil, nil
	end
	return LibStub("LibDeflate", true), LibStub("LibSerialize", true)
end

-- A raid assignment page sent to the group (Share/Comm.lua): the same encoding with the kind "note". It never decodes
-- as a plan or pack, and Codec.Decode refuses it (Codec.DecodeNote reads it).
Codec.NOTE = "note"

local function encode(kind, value)
	local LibDeflate, LibSerialize = libs()
	if not (LibDeflate and LibSerialize) then
		return nil, "libraries missing"
	end
	local ok, payload = pcall(LibSerialize.Serialize, LibSerialize, value)
	if not ok then
		return nil, tostring(payload)
	end
	local body = kind .. "\n" .. Checksum.Hex(Checksum.Adler32(payload)) .. "\n" .. payload
	local compressed = LibDeflate:CompressDeflate(body, { level = 9 })
	return Codec.HEADER .. LibDeflate:EncodeForPrint(compressed)
end

function Codec.Encode(kind, value)
	if not Codec.KINDS[kind] then
		return nil, "unknown kind"
	end
	return encode(kind, value)
end

function Codec.EncodeNote(page)
	return encode(Codec.NOTE, page)
end

-- The checked, deserialized body of a string: kind, value (not validated yet); or nil, reason.
local function decodeBody(text, maxInflated)
	if type(text) ~= "string" then
		return nil, "not a string"
	end
	if #text > Codec.LIMITS.encodedChars then
		return nil, "too long"
	end
	-- Pasted text may carry whitespace, line breaks, Discord code fences, Discord part markers ("[2/5]") or quotes.
	text = text:gsub("%[%d+/%d+%]", ""):gsub("```", ""):gsub("[%s\"'`]", "")
	local start, stop, version = text:find("!DP(%d+)!")
	if not start then
		return nil, "not a Dungeon Planner string"
	end
	version = tonumber(version)
	if not Codec.READABLE[version] then
		if version and version > Codec.VERSION then
			return nil, "made by a newer Dungeon Planner"
		end
		return nil, "not a Dungeon Planner string"
	end
	local encoded = text:sub(stop + 1)
	if encoded == "" or encoded:find("[^%w%(%)]") then
		return nil, "damaged string"
	end
	local LibDeflate, LibSerialize = libs()
	if not (LibDeflate and LibSerialize) then
		return nil, "libraries missing"
	end
	local compressed = LibDeflate:DecodeForPrint(encoded)
	if not compressed then
		return nil, "damaged string"
	end
	local body, err = Inflate.Raw(compressed, maxInflated or Codec.LIMITS.inflatedBytes)
	if not body then
		return nil, "damaged string (" .. tostring(err) .. ")"
	end
	local kind, sum, payload = body:match("^(%l+)\n(%x%x%x%x%x%x%x%x)\n(.*)$")
	if not kind or not (Codec.KINDS[kind] or kind == Codec.NOTE) then
		return nil, "unknown content"
	end
	if Checksum.Hex(Checksum.Adler32(payload)) ~= sum then
		return nil, "checksum mismatch"
	end
	-- Deserialize raises on malformed input (also for nesting deep enough to overflow the stack): pcall it.
	local ok, success, value = pcall(LibSerialize.Deserialize, LibSerialize, payload)
	if not ok or not success then
		return nil, "damaged data"
	end
	return kind, value
end

-- Returns kind, value (already validated), report; or nil, reason.
function Codec.Decode(text)
	local kind, value = decodeBody(text)
	if not kind then
		return nil, value
	end
	if not Codec.KINDS[kind] then
		return nil, "unknown content"
	end
	local clean, report
	if kind == "plan" then
		clean, report = Validate.Plan(value, true)
	else
		clean, report = Validate.Pack(value)
	end
	if not clean then
		return nil, "invalid " .. kind
	end
	return kind, clean, report
end

-- Plans exported for sharing drop machine-local fields (source); nextId stays so ids stay unique on later edits.
local function exportCopy(plan)
	local copy = ns.Util.DeepCopy(plan)
	copy.source = nil
	-- A recommended plan travels as an ordinary plan that remembers where it came from.
	local bundledId = type(plan.id) == "string" and plan.id:match("^b:(.+)$")
	if bundledId then
		copy.id, copy.bundled, copy.rev = nil, nil, nil
		copy.origin = { bundled = bundledId, rev = plan.rev }
	end
	return copy
end

-- A received page: validated (Pages.ValidatePush), or nil, reason.
function Codec.DecodeNote(text)
	local kind, value = decodeBody(text, Codec.LIMITS.noteInflatedBytes)
	if kind ~= Codec.NOTE then
		return nil, kind and "unknown content" or value
	end
	local page = ns.Pages.ValidatePush(value)
	if not page then
		return nil, "invalid note"
	end
	return page
end

function Codec.ExportPlan(plan)
	local copy = exportCopy(plan)
	return Codec.Encode("plan", copy)
end

function Codec.ExportPack(name, description, plans)
	local pack = { name = name, description = description or "", plans = {} }
	for i, plan in ipairs(plans) do
		pack.plans[i] = exportCopy(plan)
	end
	return Codec.Encode("pack", pack)
end
