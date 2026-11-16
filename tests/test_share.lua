-- Checksum, bounded inflate, export strings, transfers, Discord rendering.
local T = ...
local ns = T.ns
local Checksum, Inflate, Codec, Transfer, Plan, Discord = ns.Checksum, ns.Inflate, ns.Codec, ns.Transfer, ns.Plan,
	ns.Discord
local LibDeflate = LibStub("LibDeflate")

T.case("Adler-32 matches known values", function()
	T.eq(Checksum.Adler32(""), 1)
	T.eq(Checksum.Hex(Checksum.Adler32("Wikipedia")), "11e60398")
	T.eq(Checksum.Hex(Checksum.Adler32(string.rep("a", 100000))), Checksum.Hex(Checksum.Adler32(string.rep("a", 100000))))
	T.eq(Checksum.Hex(4294967295), "ffffffff")
end)

T.case("Inflate decodes what LibDeflate compresses (all levels, random data)", function()
	local samples = { "", "a", string.rep("abc", 1000), "The quick brown fox jumps over the lazy dog" }
	local rnd = {}
	for i = 1, 5000 do
		rnd[i] = string.char(math.random(0, 255))
	end
	samples[#samples + 1] = table.concat(rnd)
	local words = {}
	for i = 1, 3000 do
		words[i] = ({ "boss", "pull", "mob", "route", "\197\130up" })[math.random(1, 5)]
	end
	samples[#samples + 1] = table.concat(words, " ")
	for _, s in ipairs(samples) do
		for _, level in ipairs({ 0, 1, 5, 9 }) do
			local c = LibDeflate:CompressDeflate(s, { level = level })
			local out, err = Inflate.Raw(c, 1024 * 1024)
			T.eq(out, s, "round trip at level " .. level .. " (" .. tostring(err) .. ")")
		end
	end
end)

T.case("Inflate stops at the output limit (no decompression bombs)", function()
	local bomb = LibDeflate:CompressDeflate(string.rep("\0", 200000), { level = 9 })
	T.ok(#bomb < 1000, "small input")
	local out, err = Inflate.Raw(bomb, 50000)
	T.eq(out, nil)
	T.ok(tostring(err):find("too large"), "reason given")
end)

T.case("Inflate rejects garbage without raising", function()
	for _ = 1, 200 do
		local junk = {}
		for i = 1, math.random(1, 64) do
			junk[i] = string.char(math.random(0, 255))
		end
		local ok = pcall(Inflate.Raw, table.concat(junk), 10000)
		T.ok(ok, "never raises")
	end
	T.eq(Inflate.Raw(nil), nil)
end)

local function samplePlan()
	local plan = Plan.New({ name = "Sample \197\130\195\179d\197\186", author = "Tester", difficulty = "Heroic",
		instance = { name = "Test Dungeon", kind = "dungeon", ejInstanceID = 63, uiMapID = 100 } })
	local pull = Plan.AddPull(plan, "First")
	local m = Plan.AddMarker(plan, 1, 0.123456, 0.5, "mob", "Caster")
	Plan.UpdateMarker(plan, m.id, { pull = pull.id, note = "Kick the *fireball*" })
	local enc = Plan.AddEncounter(plan, { name = "Boss 1", ejEncounterID = 91, dungeonEncounterID = 201 })
	enc.strategy = "Tank faces away.\nSpread at 50%. @everyone"
	Plan.AddPhase(plan, enc.id, "Burn")
	Plan.AddAssignment(plan, "role:TANK", "Face away", enc.id, 1)
	Plan.AddAssignment(plan, "Anna", "Interrupt")
	Plan.AddGear(plan, { itemID = 19019, label = "Sword", slot = "MAINHAND", class = "WARRIOR" })
	Plan.AddObjective(plan, "Clear trash")
	local route = Plan.AddRoute(plan, 1, "Main", 2)
	Plan.AddRoutePoint(plan, route.id, 0.1, 0.1)
	Plan.AddRoutePoint(plan, route.id, 0.9, 0.9)
	plan.notes = "Bring potions."
	return plan
end
T.samplePlan = samplePlan

T.case("Export string round trip keeps the plan", function()
	local plan = samplePlan()
	local text = assert(Codec.ExportPlan(plan))
	T.ok(text:sub(1, 5) == "!DP2!", "header")
	T.ok(not text:find("[^%w%(%)!]"), "print-safe alphabet")
	local kind, back, report = Codec.Decode(text)
	T.eq(kind, "plan", tostring(back))
	T.eq(back.name, plan.name)
	T.eq(#back.markers, 1)
	T.eq(back.markers[1].x, 0.1235, "coordinates rounded to 4 places")
	T.eq(back.markers[1].pull, plan.pulls[1].id)
	T.eq(back.encounters[1].dungeonEncounterID, 201)
	T.eq(back.gear[1].itemID, 19019)
	T.eq(#back.routes[1].points, 2)
	T.ok(report)
	-- Whitespace, quotes and Discord fences around it are tolerated.
	local fenced = "```\n" .. text:sub(1, 40) .. "\n" .. text:sub(41) .. "\n```"
	T.eq(Codec.Decode(fenced), "plan")
end)

T.case("Export string tampering is detected", function()
	local text = assert(Codec.ExportPlan(samplePlan()))
	T.eq(Codec.Decode("hello"), nil)
	T.eq(Codec.Decode(text:sub(1, #text - 10)), nil, "truncated")
	local i = 20
	local flipped = text:sub(1, i - 1) .. (text:sub(i, i) == "a" and "b" or "a") .. text:sub(i + 1)
	T.eq(Codec.Decode(flipped), nil, "one character changed")
	T.eq(Codec.Decode("!DP1!$$$$"), nil, "bad alphabet")
	T.eq(Codec.Decode(string.rep("x", Codec.LIMITS.encodedChars + 1)), nil, "too long")
end)

T.case("Codec rejects a body whose checksum does not match", function()
	local LibSerialize = LibStub("LibSerialize")
	local payload = LibSerialize:Serialize({ name = "x" })
	local body = "plan\n00000000\n" .. payload
	local text = Codec.HEADER .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(body))
	local kind, err = Codec.Decode(text)
	T.eq(kind, nil)
	T.eq(err, "checksum mismatch")
end)

T.case("Packs carry several plans", function()
	local a, b = samplePlan(), samplePlan()
	b.name = "Second"
	local text = assert(Codec.ExportPack("Pack", "desc", { a, b }))
	local kind, pack = Codec.Decode(text)
	T.eq(kind, "pack")
	T.eq(#pack.plans, 2)
	T.eq(pack.plans[2].name, "Second")
end)

T.case("Transfer wire format parses what it encodes and rejects junk", function()
	local offer = Transfer.Encode({ type = "offer", proto = 1, tid = "abc123", bytes = 500, sum = "0123abcd", kind = "plan",
		name = "My ^plan" })
	local msg = Transfer.Parse(offer)
	T.eq(msg.type, "offer")
	T.eq(msg.name, "My plan", "separator stripped from names")
	T.eq(Transfer.Parse("O^1^ABC^5^0123abcd^plan^x"), nil, "bad tid")
	T.eq(Transfer.Parse("O^1^abc^5^xyz^plan^x"), nil, "bad sum")
	T.eq(Transfer.Parse("O^1^abc^5^0123abcd^virus^x"), nil, "bad kind")
	T.eq(Transfer.Parse("P^abc^!DP1!abc$"), nil, "payload outside alphabet")
	T.eq(Transfer.Parse("Z^1"), nil)
	T.eq(Transfer.Parse(string.rep("A", 300)), nil)
	T.eq(Transfer.Parse("H^1^v1.0").type, "hello")
end)

T.case("Transfer state machines: whisper accept, payload, checksum", function()
	local data = assert(Codec.ExportPlan(samplePlan()))
	local out, effects = Transfer.NewOutgoing(data, "plan", "P", "WHISPER", "Anna", 0)
	T.eq(effects[1][1], "send")
	local offer = Transfer.Parse(effects[1][2])
	local inc, inEffects = Transfer.NewIncoming(offer, "Bob", "WHISPER", 0)
	T.eq(inEffects[1][1], "prompt")
	-- Accept from the wrong player is ignored for a whisper.
	T.eq(#Transfer.StepOutgoing(out, { type = "accept", from = "Eve" }, 1), 0)
	local fx = Transfer.StepIncoming(inc, { type = "accept" }, 1)
	T.eq(fx[1][1], "send")
	T.eq(inc.state, "receiving")
	fx = Transfer.StepOutgoing(out, { type = "accept", from = "Anna" }, 1)
	T.eq(out.state, "sending")
	T.eq(fx[1][1], "sendPayload")
	local payload = Transfer.Parse(fx[1][3])
	T.eq(payload.type, "payload")
	fx = Transfer.StepIncoming(inc, payload, 2)
	T.eq(inc.state, "done")
	T.eq(fx[1][1], "complete")
	T.eq(fx[1][3], data)
	Transfer.StepOutgoing(out, { type = "sent" }, 3)
	T.eq(out.state, "done")
	T.ok(Transfer.IsFinished(out) and Transfer.IsFinished(inc))
end)

T.case("Transfer state machines: corruption, timeouts, group gather", function()
	local data = assert(Codec.ExportPlan(samplePlan()))
	local _, effects = Transfer.NewOutgoing(data, "plan", "P", "PARTY", nil, 0)
	local offer = Transfer.Parse(effects[1][2])
	local inc = Transfer.NewIncoming(offer, "Bob", "PARTY", 0)
	Transfer.StepIncoming(inc, { type = "accept" }, 1)
	Transfer.StepIncoming(inc, { type = "payload", tid = inc.tid, data = data:sub(1, -2) .. "x" }, 2)
	T.eq(inc.state, "failed")
	T.eq(inc.reason, "checksum")
	-- Unanswered prompt expires.
	local inc2 = Transfer.NewIncoming(offer, "Bob", "PARTY", 0)
	Transfer.StepIncoming(inc2, { type = "tick" }, Transfer.OFFER_TIMEOUT + 1)
	T.eq(inc2.state, "declined")
	-- Group offer: waits GATHER seconds after the first accept, then sends once.
	local out = Transfer.NewOutgoing(data, "plan", "P", "PARTY", nil, 0)
	Transfer.StepOutgoing(out, { type = "accept", from = "A" }, 1)
	Transfer.StepOutgoing(out, { type = "accept", from = "B" }, 2)
	T.eq(out.state, "offering")
	T.eq(out.acceptCount, 2)
	local fx = Transfer.StepOutgoing(out, { type = "tick" }, 1 + Transfer.GATHER)
	T.eq(out.state, "sending")
	T.eq(fx[1][1], "sendPayload")
	-- Nobody accepts: expires.
	local lonely = Transfer.NewOutgoing(data, "plan", "P", "PARTY", nil, 0)
	Transfer.StepOutgoing(lonely, { type = "tick" }, Transfer.OFFER_TIMEOUT + 1)
	T.eq(lonely.state, "expired")
	-- Oversized offers are refused.
	T.eq(Transfer.NewIncoming({ proto = 1, tid = "a", bytes = Transfer.MAX_BYTES + 1, sum = "00000000", kind = "plan" }, "X",
		"WHISPER", 0), nil)
	T.eq(Transfer.NewIncoming({ proto = 99, tid = "a", bytes = 10, sum = "00000000", kind = "plan" }, "X", "WHISPER", 0), nil)
	T.eq(Transfer.NewOutgoing(string.rep("a", Transfer.MAX_BYTES + 1), "plan", "x", "PARTY", nil, 0), nil)
end)

T.case("Discord export: parts under 2000 characters, import string survives", function()
	local plan = samplePlan()
	plan.pulls[1].note = "Kick the *fireball*"
	-- Make it big: many pulls and long strategies.
	for i = 1, 60 do
		local p = Plan.AddPull(plan, "Pull number " .. i)
		p.note = string.rep("Careful with the patrol. ", 5)
	end
	plan.encounters[1].strategy = string.rep("A long strategy line. ", 150)
	local text = assert(Codec.ExportPlan(plan))
	local parts = Discord.Render(plan, { mode = "full", importString = text, version = "1.0" })
	T.ok(#parts > 2, "split into several parts")
	local joined = {}
	for n, part in ipairs(parts) do
		T.ok(#part <= Discord.LIMIT, "part " .. n .. " is " .. #part .. " bytes")
		T.ok(part:find(string.format("[%d/%d]", n, #parts), 1, true), "numbered")
		joined[#joined + 1] = part
	end
	T.ok(parts[1]:find("## Sample", 1, true), "title header")
	T.ok(not table.concat(joined):find("@everyone", 1, true), "mentions are broken")
	T.ok(table.concat(joined):find("Kick the \\*fireball\\*", 1, true), "markdown escaped")
	-- Pasting every part together imports the plan.
	T.eq(Codec.Decode(table.concat(joined, "\n")), "plan")
	-- Summary without the string is short.
	local summary = Discord.Render(plan, { mode = "summary" })
	T.ok(#summary >= 1)
	T.ok(not summary[1]:find("```", 1, true))
end)
