-- Raid assignment pages (Model/Pages.lua): edits, validation, the export string round trip (old strings still import,
-- a newer page format is dropped), keyword expansion, send and accept permissions, the Notes window's state machine,
-- received pages, and pushing a page over AceComm with the permission check and the lockdown outbox.
local T = ...
local ns, mock = T.ns, T.mock
local Pages, Codec = ns.Pages, ns.Codec

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

local function raidPlan()
	local plan = ns.Validate.Plan({
		name = "Core night",
		instance = { name = "Molten Core", kind = "raid" },
		encounters = { { id = "e1", name = "Lucifron", dungeonEncounterID = 663 }, { id = "e2", name = "Ragnaros" } },
	})
	plan.groups[1] = { "Bram", "Dessa", "Tester" }
	plan.groups[2] = { "Corin", "Aldra" }
	return plan
end

T.case("Pages: add, update, move, remove; unlinked with their boss; recommended plans refuse", function()
	local plan = raidPlan()
	local a = Pages.Add(plan, "Lucifron", "e1")
	local b = Pages.Add(plan, "Trash", "nope")
	T.eq(a.id:sub(1, 1), "n")
	T.eq(b.encounter, nil, "an unknown boss is not kept")
	T.ok(Pages.Update(plan, a.id, { text = "{skull} on the boss|cffff0000red|r" }))
	T.eq(a.text, "{skull} on the bossred", "escape codes are stripped")
	T.ok(Pages.Move(plan, b.id, -1))
	T.eq(Pages.List(plan)[1], b)
	T.eq(Pages.Move(plan, b.id, -1), nil, "already first")
	ns.Plan.RemoveEncounter(plan, "e1")
	T.eq(a.encounter, nil, "the page stays, as a general page")
	T.ok(Pages.Remove(plan, a.id))
	T.ok(Pages.Remove(plan, b.id))
	T.eq(plan.pages, nil, "no field when empty")
	for _ = 1, ns.Schema.MAX.pages do
		T.ok(Pages.Add(plan, "p"))
	end
	T.eq(select(2, Pages.Add(plan, "one too many")), "limit")
	T.eq(select(2, Pages.Add({ bundled = true }, "x")), "read-only")
end)

T.case("Pages: validation and the export string round trip; old strings import; a newer page format is dropped", function()
	local plan = raidPlan()
	local page = Pages.Add(plan, "Lucifron", "e1")
	Pages.Update(plan, page.id, { text = "{tank} Bram\n{group 2} heals" })
	local text = assert(Codec.ExportPlan(plan))
	local kind, back = Codec.Decode(text)
	T.eq(kind, "plan")
	T.eq(#back.pages.list, 1)
	T.eq(back.pages.list[1].text, "{tank} Bram\n{group 2} heals")
	T.eq(back.pages.list[1].encounter, "e1")
	T.ok(back.nextId > tonumber(page.id:match("%d+")), "ids stay unique after the import")
	-- A string from before pages (no field) imports with none.
	local old = raidPlan()
	local kind2, back2 = Codec.Decode(assert(Codec.ExportPlan(old)))
	T.eq(kind2, "plan")
	T.eq(back2.pages, nil)
	-- Junk is dropped page by page; a newer format is dropped whole and reported.
	local raw = { name = "x", encounters = { { id = "e1", name = "B" } }, pages = { v = 1, list = {
		{ id = "n1", title = "ok", text = "t", encounter = "e9" },
		{ id = "n1", title = "duplicate id" },
		{ id = "bad", title = "bad id" },
		{ id = "n3" },
		"junk",
	} } }
	local clean, report = ns.Validate.Plan(raw)
	T.eq(#clean.pages.list, 1)
	T.eq(clean.pages.list[1].encounter, nil, "a link to a missing boss is cleared")
	T.ok((report.dropped.pages or 0) >= 3, "dropped pages are reported")
	clean, report = ns.Validate.Plan({ name = "y", pages = { v = 2, list = { { id = "n1", title = "future" } } } })
	T.eq(clean.pages, nil)
	T.eq(report.dropped.pages, 1)
	-- An older reader keeps only the fields it knows: simulated by dropping the field before validation.
	local copy = ns.Util.DeepCopy(plan)
	copy.pages = nil
	T.ok(ns.Validate.Plan(copy), "the rest of the plan still validates without pages")
end)

T.case("Pages: keyword expansion for display and chat; own lines; unknown keywords stay", function()
	local plan = raidPlan()
	local classes = { mage = "MAGE", warrior = "WARRIOR", ["mag"] = nil }
	local env = {
		groups = plan.groups,
		me = "Tester",
		own = "> ",
		classes = classes,
		classOf = function(name)
			return ({ Bram = "WARRIOR", Aldra = "MAGE" })[name]
		end,
		colorName = function(name, token)
			return "<" .. token .. ":" .. name .. ">"
		end,
		raidIcon = function(n)
			return "[rt" .. n .. "]"
		end,
		roleIcon = function(role)
			return "[" .. role .. "]"
		end,
		roleName = function(role)
			return role:lower()
		end,
		classIcon = function(token)
			return "[" .. token .. "]"
		end,
		className = function(token)
			return token:lower()
		end,
	}
	local text = "{Skull} {TANK} Bram, {rt4} {x}\n{group 2} heal\n{Mage} decurse: Tester\n{g1} on {nothing}\n{group 9}"
	local out, mine = Pages.Expand(text, env)
	local lines = {}
	for l in (out .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = l
	end
	T.eq(lines[1], "[rt8] [TANK] <WARRIOR:Bram>, [rt4] [rt7]")
	T.eq(lines[2], "Corin, <MAGE:Aldra> heal")
	T.eq(lines[3], "> [MAGE] decurse: Tester", "a line naming the player is marked")
	T.eq(lines[4], "> <WARRIOR:Bram>, Dessa, Tester on {nothing}", "the player's group is theirs; unknown stays")
	T.eq(lines[5], "{group 9}", "group 9 does not exist")
	T.eq(mine, 2)
	-- Chat: icons as {rtN}, words, plain names, no marks; title first, empty lines out, cut and capped.
	local chat = Pages.ChatLines({ title = "Lucifron", text = "{star} {tank} Bram\n\n{mage} Aldra\n" .. string.rep("x", 300) }, env,
		250, 3)
	T.eq(chat[1], "Lucifron")
	T.eq(chat[2], "{rt1} tank Bram")
	T.eq(chat[3], "mage Aldra")
	T.eq(#chat, 3, "capped")
	T.ok(#Pages.ChatLines({ title = "", text = string.rep("y", 300) }, env, 250, 5)[1] <= 250)
	-- Names with non-ASCII letters are words too.
	local u = Pages.Expand("Zoë and Ånd", { classOf = function(n)
		return n == "Zoë" and "MAGE" or nil
	end, colorName = function(n)
		return "*" .. n .. "*"
	end })
	T.eq(u, "*Zoë* and Ånd")
end)

T.case("Pages: who may send and from whom pages are taken", function()
	T.eq(select(2, Pages.CanSend({ inGroup = false })), "group")
	T.ok(Pages.CanSend({ inGroup = true, leader = true }), "the party's leader")
	T.eq(select(2, Pages.CanSend({ inGroup = true, assist = true })), "rank", "a party has no assistants")
	T.ok(Pages.CanSend({ inGroup = true, inRaid = true, assist = true }), "a raid assistant")
	T.eq(select(2, Pages.CanSend({ inGroup = true, inRaid = true })), "rank")
	local leader = { inGroup = true, leader = true }
	local member = { inGroup = true, inRaid = true }
	local assist = { inGroup = true, inRaid = true, assist = true }
	T.ok(Pages.AcceptFrom("leaders", leader))
	T.ok(Pages.AcceptFrom("leaders", assist))
	T.ok(not Pages.AcceptFrom("leaders", member))
	T.ok(Pages.AcceptFrom("group", member))
	T.ok(not Pages.AcceptFrom("group", { inGroup = false }), "never from outside the group")
	T.ok(not Pages.AcceptFrom("nobody", leader))
end)

T.case("Pages: the Notes window's state machine (open, boss pull, hide in combat)", function()
	local v = Pages.NewView()
	T.eq(Pages.ViewStep(v, { type = "encounterStart", page = true, autoShow = true }), true, "a boss pull shows its page")
	T.eq(Pages.ViewStep(v, { type = "encounterEnd" }), false, "and its end hides it")
	T.eq(Pages.ViewStep(v, { type = "encounterStart", page = false, autoShow = true }), false, "no page: nothing")
	T.eq(Pages.ViewStep(v, { type = "encounterStart", page = true, autoShow = false }), false, "auto-show off")
	Pages.ViewStep(v, { type = "open" })
	T.eq(Pages.ViewStep(v, { type = "encounterEnd" }), true, "opened by the player: stays")
	Pages.ViewStep(v, { type = "setting", hideInCombat = true })
	T.eq(Pages.ViewStep(v, { type = "combat", on = true }), false, "hidden in combat")
	T.eq(Pages.ViewStep(v, { type = "combat", on = false }), true, "back after combat")
	T.eq(Pages.ViewStep(v, { type = "toggle" }), false)
	T.eq(Pages.ViewStep(v, { type = "toggle" }), true)
	T.eq(Pages.ViewStep(v, { type = "close" }), false)
end)

T.case("Pages: received pages are validated, replaced by title, capped, and found by boss", function()
	local store = Pages.NormalizeReceived({ received = { { title = "a", text = "x", from = "Lead" }, "junk", { text = "" } } })
	T.eq(#store.received, 1)
	T.eq(Pages.ValidatePush({ text = "", title = "" }), nil)
	local p = Pages.ValidatePush({ title = "Lucifron", text = "go|r", enc = 663, boss = "Lucifron", extra = 1 })
	T.eq(p.text, "go")
	T.eq(p.extra, nil)
	Pages.Receive(store, p, "Lead", 10)
	Pages.Receive(store, Pages.ValidatePush({ title = "Lucifron", text = "new", boss = "Lucifron" }), "Lead", 20)
	T.eq(#store.received, 2, "the same title from the same sender replaces")
	T.eq(Pages.ReceivedFor(store, nil, "lucifron").text, "new")
	T.eq(Pages.ReceivedFor(store, 999, "Ragnaros"), nil)
	for i = 1, Pages.MAX_RECEIVED + 3 do
		Pages.Receive(store, Pages.ValidatePush({ title = "t" .. i, text = "x" }), "Lead", 100 + i)
	end
	T.eq(#store.received, Pages.MAX_RECEIVED)
	local plan = raidPlan()
	local page = Pages.Add(plan, "Lucifron", "e1")
	T.eq(Pages.ForEncounter(plan, 663, nil, function(enc)
		return enc.dungeonEncounterID
	end), page, "by game ID")
	T.eq(Pages.ForEncounter(plan, nil, "LUCIFRON"), page, "by name")
	T.eq(Pages.ForEncounter(plan, 1, "Ragnaros"), nil)
end)

T.case("Pages over AceComm: only a leader sends; the receiver checks the sender; lockdown waits; Notes opens", function()
	boot()
	local plan = raidPlan()
	local page = Pages.Add(plan, "Lucifron", "e1")
	Pages.Update(plan, page.id, { text = "{group 2} heal" })
	local leaderFn, assistFn, raidFn = _G.UnitIsGroupLeader, _G.UnitIsGroupAssistant, _G.IsInRaid
	local leader = {}
	_G.UnitIsGroupLeader = function(unit)
		return leader[unit] == true
	end
	_G.UnitIsGroupAssistant = function()
		return false
	end
	mock.inGroup = true
	mock.units = { party1 = { name = "Lead" } }
	-- What leaves through AceComm (the mock's ChatThrottleLib path does not keep the text, so record it here).
	local outgoing = {}
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, prefix, text, channel)
		outgoing[#outgoing + 1] = { prefix, text, channel }
	end
	-- Not the leader: refused.
	local ok, err = ns.Comm.SendPage(ns.NotesFrame.Payload(plan, page))
	T.ok(not ok and err:find("leader", 1, true), tostring(err))
	-- The leader: sent, with the groups written out (the receiver has no plan).
	leader.player = true
	ok = ns.Comm.SendPage(ns.NotesFrame.Payload(plan, page))
	T.ok(ok)
	local sent
	for _, m in ipairs(outgoing) do
		if m[2]:sub(1, 2) == "N^" then
			sent = m[2]
			T.ok(m[3] ~= nil, "to the group channel")
		end
	end
	T.ok(sent, "a note message went out")
	local msg = ns.Transfer.Parse(sent)
	T.eq(msg.type, "note")
	local got = Codec.DecodeNote(msg.data)
	T.eq(got.text, "Corin, Aldra heal")
	T.eq(got.boss, "Lucifron")
	T.eq(Codec.Decode(msg.data), nil, "a note never imports as a plan")
	-- During a lockdown it waits in the outbox.
	mock.lockdown = true
	outgoing = {}
	local _, waiting = ns.Comm.SendPage(ns.NotesFrame.Payload(plan, page))
	T.ok(waiting, "says it waits")
	mock.Advance(1)
	T.eq(#outgoing, 0, "nothing sent in the lockdown")
	mock.lockdown = false
	mock.Advance(1)
	T.eq(#outgoing, 1, "sent after the lockdown")
	ns.addon.SendCommMessage = realSend
	-- Receiving: from a non-leader the page is ignored; from the leader it is stored and the Notes window opens.
	leader.player = nil
	local store = ns.Comm.NotesStore()
	local before = #store.received
	ns.Comm.OnMessage(ns.prefix, sent, "PARTY", "Lead")
	T.eq(#store.received, before, "not from a leader: ignored")
	leader.party1 = true
	ns.Comm.OnMessage(ns.prefix, sent, "PARTY", "Lead")
	T.eq(#store.received, before + 1)
	T.eq(store.received[#store.received].from, "Lead")
	T.ok(ns.NotesFrame.IsShown(), "the Notes window opens on a received page")
	-- A boss pull picks the page; its end closes the window again unless the player opened it.
	ns.NotesFrame.Close()
	mock.FireEvent("ENCOUNTER_START", 999, "Lucifron", 1, 40)
	T.ok(ns.NotesFrame.IsShown(), "shown on the boss pull (matched by name)")
	mock.FireEvent("ENCOUNTER_END", 999, "Lucifron", 1, 40, 1)
	T.ok(not ns.NotesFrame.IsShown(), "hidden at its end")
	-- Posting to chat: lines through ChatThrottleLib (or SendChatMessage), {rtN} kept for the chat to draw.
	local ctl = _G.ChatThrottleLib
	local realChat = ctl.SendChatMessage
	local chat = {}
	ctl.SendChatMessage = function(_, prio, prefix, text, channel)
		chat[#chat + 1] = { text, channel, prio, prefix }
	end
	Pages.Update(plan, page.id, { text = "{star} {group 2}" })
	ns.NotesFrame.PostToChat(plan, page)
	T.eq(#chat, 2, "title and a line posted")
	T.eq(chat[1][1], "Lucifron")
	T.eq(chat[2][1], "{rt1} Corin, Aldra")
	mock.lockdown = true
	chat = {}
	ns.NotesFrame.PostToChat(plan, page)
	T.eq(#chat, 0, "nothing posted during a lockdown")
	mock.lockdown = false
	ctl.SendChatMessage = realChat
	_G.UnitIsGroupLeader, _G.UnitIsGroupAssistant, _G.IsInRaid = leaderFn, assistFn, raidFn
	mock.inGroup, mock.units = false, {}
	store.received = {}
end)

T.case("Pages: saved data moves to schema 4 with its pages; data from a newer schema stays read-only", function()
	local DB = ns.DB
	T.eq(DB.SCHEMA, 4)
	local global = { schema = 3, plans = { p1 = { id = "p1", name = "Old", pages = { v = 1, list = { { id = "n1", title = "a", text = "b" } } } } } }
	local info = DB.LoadGlobal(global)
	T.eq(global.schema, 4)
	T.eq(info.migratedFrom, 3)
	T.eq(global.plans.p1.pages.list[1].text, "b", "pages survive the load")
	local newer = { schema = 5, plans = {} }
	T.ok(DB.LoadGlobal(newer).readOnly)
end)
