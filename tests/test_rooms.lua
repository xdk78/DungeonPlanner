-- Where the group is, by room (Share/Rooms.lua, UI/GroupRooms.lua, UI/MapGroup.lua): the wire format, the state machine
-- (sent on change, coalesced and throttled, asked once and answered, nothing outside a group or an instance or with the
-- setting off, members kept, stale, dropped with the roster), the glue through the real Comm and its lockdown outbox,
-- two clients talking, and the dots on the map.
local T = ...
local ns, mock = T.ns, T.mock
local Rooms, Transfer = ns.Rooms, ns.Transfer
local RUINS = ns.SubzoneData.ruinsoflordaeron

local function find(effects, kind)
	for _, e in ipairs(effects) do
		if e[1] == kind then
			return e
		end
	end
	return nil
end

local function count(effects, kind)
	local n = 0
	for _, e in ipairs(effects) do
		if e[1] == kind then
			n = n + 1
		end
	end
	return n
end

local function where(iid, area, share, group)
	return { type = "where", group = group ~= false, share = share ~= false, iid = iid, area = area }
end

local function heard(from, iid, area, ask)
	return { type = "heard", from = from, iid = iid, area = area, ask = ask }
end

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
end

T.case("Rooms: wire format round-trips and rejects junk", function()
	local text = Transfer.Encode({ type = "room", proto = 2, iid = 2999, area = "a16612", ask = true })
	T.eq(text, "L^2^2999^a16612^1")
	local m = Transfer.Parse(text)
	T.eq(m.type, "room")
	T.eq(m.proto, 2)
	T.eq(m.iid, 2999)
	T.eq(m.area, "a16612")
	T.eq(m.ask, true)
	m = Transfer.Parse(Transfer.Encode({ type = "room", proto = 2, iid = 0 }))
	T.eq(m.iid, 0, "nowhere")
	T.eq(m.area, nil)
	T.eq(m.ask, false)
	m = Transfer.Parse("L^2^48^-^0")
	T.eq(m.iid, 48, "inside, in a spot the data does not name")
	T.eq(m.area, nil)
	T.eq(Transfer.Parse("L^2^48^w11910^0").area, "w11910")
	for _, bad in ipairs({
		"L^2^0^a16612^0", -- a room without an instance
		"L^2^-5^a1^0",
		"L^2^1.5^a1^0",
		"L^2^99999999999^a1^0", -- beyond 2^31
		"L^2^48^b12^0", -- not an area key
		"L^2^48^a^0",
		"L^2^48^a012^0",
		"L^2^48^Pool of Ask'ar^0", -- a name
		"L^2^48^a1234567890123^0", -- longer than MAX_KEY
		"L^2^48^a1^2", -- ask
		"L^2^48^a1", -- a field missing
		"L^2^48^a1^0^0", -- one too many
		"L^x^48^a1^0", -- protocol
		"L^2^48^^0",
	}) do
		T.eq(Transfer.Parse(bad), nil, bad)
	end
	T.eq(Transfer.Parse("L^2^48^a" .. string.rep("1", 300) .. "^0"), nil, "oversized")
end)

T.case("Rooms: a change goes out at once, then coalesced and throttled; nothing outside a group or an instance", function()
	local s = Rooms.New()
	T.eq(#Rooms.Step(s, where(2999, "a1", true, false), 0), 0, "not in a group")
	T.eq(#Rooms.Step(s, where(nil, nil), 0), 0, "in a group, outside an instance")
	local fx = Rooms.Step(s, where(2999, "a1"), 10)
	local send = find(fx, "send")[2]
	T.eq(send.iid, 2999)
	T.eq(send.area, "a1")
	T.eq(send.ask, true, "entering asks the others where they are")
	T.ok(find(fx, "timer"), "the refresh")
	fx = Rooms.Step(s, where(2999, "a2"), 11)
	T.eq(count(fx, "send"), 0, "within MIN_INTERVAL")
	T.ok(math.abs(find(fx, "timer")[2] - 2) < 1e-9, "the rest of the interval")
	T.eq(#Rooms.Step(s, where(2999, "a3"), 11.5), 0, "coalesced into the waiting one")
	T.eq(#Rooms.Step(s, where(2999, "a1"), 12), 0, "back to what the group has: nothing waits")
	T.eq(s.pending, nil)
	Rooms.Step(s, where(2999, "a3"), 12.5)
	T.eq(count(Rooms.Step(s, { type = "tick" }, 12.9), "send"), 0, "too early")
	send = find(Rooms.Step(s, { type = "tick" }, 13), "send")[2]
	T.eq(send.area, "a3", "the newest")
	T.eq(send.ask, nil, "asked once")
	T.eq(count(Rooms.Step(s, { type = "tick" }, 13.2), "send"), 0, "a stale tick changes nothing")
	-- Standing in one room: said again every REFRESH, so the others keep it.
	T.eq(find(Rooms.Step(s, { type = "tick" }, 13 + Rooms.REFRESH), "send")[2].area, "a3")
	-- Leaving the instance: one message that says so, then nothing, and no timer.
	fx = Rooms.Step(s, where(nil, nil), 80)
	T.eq(find(fx, "send")[2].iid, 0, "nowhere")
	T.eq(find(fx, "timer"), nil, "nothing left to wait for")
	T.eq(#Rooms.Step(s, where(nil, nil), 90), 0)
	T.eq(count(Rooms.Step(s, { type = "tick" }, 200), "send"), 0, "no refresh outside")
	-- Back inside: the question again, and a timer though an old one was asked for.
	fx = Rooms.Step(s, where(2999, "a2"), 300)
	T.eq(find(fx, "send")[2].ask, true)
	T.ok(find(fx, "timer"))
	-- Leaving the group: nothing to send, nothing to wait for.
	T.eq(#Rooms.Step(s, where(nil, nil, true, false), 400), 0)
	T.eq(s.mine, nil)
end)

T.case("Rooms: with the setting off only the question goes out; turning it off tells the group", function()
	local s = Rooms.New()
	local send = find(Rooms.Step(s, where(2999, "a1", false), 0), "send")[2]
	T.eq(send.iid, 0, "no room")
	T.eq(send.ask, true, "the others are asked for theirs")
	T.eq(#Rooms.Step(s, where(2999, "a2", false), 10), 0, "zone changes send nothing")
	send = find(Rooms.Step(s, where(2999, "a2", true), 20), "send")[2]
	T.eq(send.area, "a2", "on: the room")
	T.eq(send.ask, nil)
	send = find(Rooms.Step(s, where(2999, "a2", false), 30), "send")[2]
	T.eq(send.iid, 0, "off again: the others drop the player")
	T.eq(count(Rooms.Step(s, { type = "tick" }, 200), "send"), 0, "no refresh")
	T.eq(count(Rooms.Step(s, heard("Ann", 2999, "a1", true), 210), "send"), 0, "no room to answer with")
end)

T.case("Rooms: members are kept, a question is answered, stale entries expire, the roster drops leavers", function()
	local s = Rooms.New()
	Rooms.Step(s, where(2999, "a1"), 0)
	local fx = Rooms.Step(s, heard("Ann", 2999, "a2", true), 1)
	T.ok(find(fx, "changed"))
	T.eq(s.members.Ann.area, "a2")
	T.eq(count(fx, "send"), 0, "the answer waits for MIN_INTERVAL")
	local send = find(Rooms.Step(s, { type = "tick" }, 3), "send")[2]
	T.eq(send.area, "a1", "answered though nothing changed")
	T.eq(send.ask, nil, "an answer asks nothing")
	T.eq(find(Rooms.Step(s, heard("Ann", 2999, "a2"), 5), "changed"), nil, "the same room again")
	T.eq(s.members.Ann.at, 5, "but heard again")
	fx = Rooms.Step(s, heard("Bob", 2999, nil), 10)
	T.ok(find(fx, "changed"))
	T.eq(s.members.Bob.area, nil, "inside, in a spot the data does not name")
	Rooms.Step(s, heard("Ann", 0), 11)
	T.eq(s.members.Ann, nil, "Ann left the instance")
	T.eq(#Rooms.Step(s, heard(nil, 2999, "a1"), 11), 0, "no sender, no entry")
	-- Bob is not heard from again.
	T.ok(s.members.Bob)
	Rooms.Step(s, { type = "tick" }, 10 + Rooms.STALE - 1)
	T.ok(s.members.Bob, "not yet")
	fx = Rooms.Step(s, { type = "tick" }, 10 + Rooms.STALE)
	T.eq(s.members.Bob, nil, "stale")
	T.ok(find(fx, "changed"))
	-- The roster: who left the group goes; out of the group, everyone.
	Rooms.Step(s, heard("Cid", 2999, "a1"), 400)
	Rooms.Step(s, heard("Dee", 2999, "a1"), 400)
	fx = Rooms.Step(s, { type = "roster", members = { "Dee", "Eve" } }, 401)
	T.eq(s.members.Cid, nil)
	T.ok(s.members.Dee)
	T.ok(find(fx, "changed"))
	T.eq(count(Rooms.Step(s, { type = "roster", members = { "Dee" } }, 402), "changed"), 0, "nothing changed")
	Rooms.Step(s, { type = "roster", members = {} }, 403)
	T.eq(next(s.members), nil, "out of the group: nobody")
	-- Bounded: the oldest goes first.
	for i = 1, Rooms.MAX_MEMBERS + 5 do
		Rooms.Step(s, heard("M" .. i, 2999, "a1"), 500 + i)
	end
	T.eq(ns.Util.Count(s.members), Rooms.MAX_MEMBERS)
	T.eq(s.members.M1, nil)
	T.ok(s.members["M" .. (Rooms.MAX_MEMBERS + 5)])
end)

T.case("Rooms: nobody goes stale while the game holds messages; the clock restarts when they flow", function()
	local s = Rooms.New()
	Rooms.Step(s, heard("Ann", 2999, "a1"), 0)
	local fx = Rooms.Step(s, { type = "tick", locked = true }, Rooms.STALE)
	T.ok(s.members.Ann, "a long boss fight keeps her")
	T.ok(math.abs(find(fx, "timer")[2] - Rooms.LOCK_CHECK) < 1e-9, "a look whether messages flow again")
	Rooms.Step(s, { type = "tick", locked = true }, Rooms.STALE + 600)
	T.ok(s.members.Ann)
	fx = Rooms.Step(s, { type = "tick" }, Rooms.STALE + 610)
	T.ok(s.members.Ann, "messages flow: her clock starts again")
	T.ok(math.abs(find(fx, "timer")[2] - Rooms.STALE) < 1e-9)
	Rooms.Step(s, { type = "tick" }, Rooms.STALE + 610 + Rooms.STALE - 1)
	T.ok(s.members.Ann)
	Rooms.Step(s, { type = "tick" }, Rooms.STALE + 610 + Rooms.STALE)
	T.eq(s.members.Ann, nil, "stale after the fight")
	T.eq(#Rooms.Step(s, { type = "tick", locked = true }, 2000), 0, "nobody to keep: no timer")
end)

T.case("Transfer.Parse: the tag is the whole first field, numbers are plain digits", function()
	local good = { "H^2^0.2.3", "h^2^dev", "O^2^abc1^120^0000abcd^plan^My plan", "K^abc1^p1^1700000000", "A^abc1",
		"D^abc1", "X^abc1", "R^2^abc1^7^p1^100^12^1", "F^2^abc1^u", "Q^2", "W^2^abc1", "L^2^48^a1^0" }
	for _, text in ipairs(good) do
		T.ok(Transfer.Parse(text), text)
		local tag, rest = text:sub(1, 1), text:sub(2)
		T.eq(Transfer.Parse(tag .. "x" .. rest), nil, "tag " .. tag .. "x")
	end
	for _, bad in ipairs({
		"H^0x2^v", "H^ 2^v", "H^2.0^v", "H^-2^v",
		"O^2^abc1^0x78^0000abcd^plan^n", "O^2^abc1^1.2e2^0000abcd^plan^n", "O^ 2^abc1^120^0000abcd^plan^n",
		"K^abc1^p1^ 17", "K^abc1^p1^-1", "K^abc1^p1^1e3",
		"R^2^abc1^0x7^p1^100^12^1", "R^2^abc1^7^p1^1e2^12^1", "R^2^abc1^7^p1^100^ 12^1", "R^2^abc1^7^p1^100^12^+1",
		"F^0x2^abc1^u", "Q^ 2", "W^2.0^abc1",
		"L^2^0x30^a1^0", "L^2^ 48^a1^0", "L^2^4.8e1^a1^0", "L^2^48^a1^ 1", "L^02e0^48^a1^0",
	}) do
		T.eq(Transfer.Parse(bad), nil, bad)
	end
end)

T.case("Rooms: an update that added the files, before a restart: no errors without them", function()
	boot()
	ns.UI.Show()
	ns.UI.SelectPlan(ns.Bundled.PREFIX .. "ruins-of-lordaeron")
	ns.UI.SelectTab("map")
	local saved = { Rooms = ns.Rooms, GroupRooms = ns.GroupRooms, MapGroup = ns.MapGroup }
	ns.Rooms, ns.GroupRooms, ns.MapGroup = nil, nil, nil
	local ok, err = pcall(function()
		T.eq(Transfer.Parse("L^2^48^a1^0").area, "a1", "parsed without Share/Rooms.lua")
		ns.Comm.OnMessage(ns.prefix, "L^2^48^a1^0", "PARTY", "Ann")
		local map = _G.DungeonPlannerMainFrame.instancePage.panels.map
		local view = ns.MapCanvas.Create(UIParent, map.canvas.cb)
		view:DrawContent()
		view:HereHover(0, 0)
		T.eq(rawget(view, "PlaceGroup"), nil, "no group dots")
		view:Hide()
	end)
	ns.Rooms, ns.GroupRooms, ns.MapGroup = saved.Rooms, saved.GroupRooms, saved.MapGroup
	T.ok(ok, tostring(err))
end)

-- The real Comm, AceComm and outbox, as tests/test_sync.lua drives them.

-- The client in Ruins of Lordaeron, in the area with this AreaTable ID (the mock names it "Area <ID>"); nil: outside
-- an instance.
local function inRuins(areaID)
	_G.GetInstanceInfo = function()
		if not areaID then
			return "Somewhere", "none", 0, "", 0, 0, false, 0
		end
		return "Ruins of Lordaeron", "party", 1, "Normal", 5, 0, false, RUINS.iid
	end
	mock.subzone = areaID and ("Area " .. areaID) or ""
end

local function withGroup(fn)
	T.quietComm()
	local saved = { info = _G.GetInstanceInfo, sub = mock.subzone, class = _G.UnitClass,
		colors = rawget(_G, "RAID_CLASS_COLORS") }
	mock.inGroup = true
	mock.units = { party1 = { name = "Ann", cls = "PRIEST" }, party2 = { name = "Bob", cls = "ROGUE" },
		party3 = { name = "Cid", cls = "MAGE" } }
	_G.UnitClass = function(unit)
		local u = unit == "player" and { cls = "WARRIOR" } or mock.units[unit]
		return u and u.cls, u and u.cls, 1
	end
	_G.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
		MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
	mock.FireEvent("GROUP_ROSTER_UPDATE")
	local outgoing = {}
	local realSend = ns.addon.SendCommMessage
	ns.addon.SendCommMessage = function(_, _, text, channel, target)
		outgoing[#outgoing + 1] = { text = text, channel = channel, target = target }
	end
	local ok, err = pcall(fn, outgoing)
	ns.addon.SendCommMessage = realSend
	_G.GetInstanceInfo, mock.subzone, _G.UnitClass, _G.RAID_CLASS_COLORS = saved.info, saved.sub, saved.class,
		saved.colors
	ns.db.settings.share.rooms, ns.db.settings.mapGroup = true, true
	mock.inGroup, mock.units, mock.lockdown = false, {}, false
	mock.FireEvent("GROUP_ROSTER_UPDATE")
	ns.GroupRooms.state = Rooms.New()
	assert(ok, err)
end

-- The rooms this client sent, parsed, and the list emptied.
local function sentRooms(outgoing)
	local out = {}
	for _, m in ipairs(outgoing) do
		local msg = Transfer.Parse(m.text)
		if msg and msg.type == "room" then
			out[#out + 1] = { msg = msg, channel = m.channel }
		end
	end
	for i = #outgoing, 1, -1 do
		outgoing[i] = nil
	end
	return out
end

local function waitingRooms()
	local n = 0
	for _, item in ipairs(ns.Comm.outbox) do
		if item.key == "room" then
			n = n + 1
		end
	end
	return n
end

T.case("Rooms, in game: sent on a zone change through Comm, coalesced, held in a lockdown; quiet outside", function()
	boot()
	withGroup(function(outgoing)
		local a1, a2, a3 = RUINS[1].a, RUINS[2].a, RUINS[3].a
		mock.inGroup = false
		inRuins(a1)
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		mock.FireEvent("ZONE_CHANGED")
		T.eq(#sentRooms(outgoing), 0, "not in a group")
		mock.inGroup = true
		inRuins(nil)
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		T.eq(#sentRooms(outgoing), 0, "in a group, outside an instance")
		-- Entering: the room at once, asking the others.
		inRuins(a1)
		mock.FireEvent("PLAYER_ENTERING_WORLD")
		local sent = sentRooms(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.iid, RUINS.iid)
		T.eq(sent[1].msg.area, "a" .. a1)
		T.eq(sent[1].msg.ask, true)
		T.eq(sent[1].channel, ns.Comm.GroupChannel(), "to the group")
		-- Zone flicker: one message, the newest, when MIN_INTERVAL ends.
		mock.subzone = "Area " .. a2
		mock.FireEvent("ZONE_CHANGED")
		mock.subzone = "Area " .. a3
		mock.FireEvent("ZONE_CHANGED_INDOORS")
		T.eq(#sentRooms(outgoing), 0)
		mock.Advance(Rooms.MIN_INTERVAL + 0.5, 0.1)
		sent = sentRooms(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.area, "a" .. a3)
		-- The setting off: one message so the others drop the player, then nothing on zone changes.
		ns.db.settings.share.rooms = false
		ns.GroupRooms.Update()
		mock.Advance(Rooms.MIN_INTERVAL + 0.5, 0.1)
		sent = sentRooms(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.iid, 0)
		mock.subzone = "Area " .. a1
		mock.FireEvent("ZONE_CHANGED")
		mock.Advance(Rooms.MIN_INTERVAL + 0.5, 0.1)
		T.eq(#sentRooms(outgoing), 0, "off: zone changes send nothing")
		ns.db.settings.share.rooms = true
		ns.GroupRooms.Update()
		T.eq(sentRooms(outgoing)[1].msg.area, "a" .. a1, "on again")
		-- A boss fight: the game holds addon messages. Three rooms; after it one message, the newest.
		mock.lockdown = true
		for _, a in ipairs({ a2, a3, a2 }) do
			mock.subzone = "Area " .. a
			mock.FireEvent("ZONE_CHANGED")
			mock.Advance(Rooms.MIN_INTERVAL + 0.5, 0.1)
		end
		T.eq(#sentRooms(outgoing), 0, "nothing during the lockdown")
		T.eq(waitingRooms(), 1, "one waiting: the newest replaced the older ones")
		local refreshes, sendSync = 0, ns.Comm.SendSync
		ns.Comm.SendSync = function(...)
			refreshes = refreshes + 1
			return sendSync(...)
		end
		mock.Advance(2 * Rooms.REFRESH + 5, 1)
		ns.Comm.SendSync = sendSync
		T.eq(refreshes, 2, "two refreshes in the fight")
		T.eq(waitingRooms(), 1, "still one waiting")
		mock.lockdown = false
		mock.Advance(1, 0.1)
		sent = sentRooms(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.area, "a" .. a2)
		-- Leaving the instance: one message, then nothing outside, not even the refresh.
		inRuins(nil)
		mock.FireEvent("PLAYER_ENTERING_WORLD")
		mock.Advance(Rooms.MIN_INTERVAL + 0.5, 0.1)
		sent = sentRooms(outgoing)
		T.eq(#sent, 1)
		T.eq(sent[1].msg.iid, 0)
		mock.FireEvent("ZONE_CHANGED_NEW_AREA")
		mock.Advance(Rooms.REFRESH + 5, 1)
		T.eq(#sentRooms(outgoing), 0, "no traffic outside an instance")
	end)
end)

T.case("Rooms, two clients: rooms both ways through Comm; outsiders, whispers and junk ignored; leaving clears", function()
	boot()
	withGroup(function(outgoing)
		local a1, a2 = RUINS[1].a, RUINS[2].a
		local members = ns.GroupRooms.Members
		local function deliver(effects, from)
			for _, e in ipairs(effects) do
				if e[1] == "send" then
					ns.Comm.OnMessage(ns.prefix, Transfer.Encode(e[2]), "PARTY", from or "Ann")
				end
			end
		end
		-- What this client sent, heard by Ann's own state machine.
		local ann = Rooms.New()
		local function toAnn(t)
			local fx = {}
			for _, m in ipairs(sentRooms(outgoing)) do
				local msg = m.msg
				for _, e in ipairs(Rooms.Step(ann, heard("Tester", msg.iid, msg.area, msg.ask), t)) do
					fx[#fx + 1] = e
				end
			end
			return fx
		end
		-- Ann is inside; this client is not yet, so her question has no answer.
		deliver(Rooms.Step(ann, where(RUINS.iid, "a" .. a2), 0))
		T.eq(members().Ann.area, "a" .. a2, "Ann's room arrived")
		T.eq(#sentRooms(outgoing), 0, "outside: nothing to answer")
		-- This client enters: its room and question reach Ann, and her answer comes back.
		inRuins(a1)
		mock.FireEvent("PLAYER_ENTERING_WORLD")
		local fx = toAnn(5)
		T.eq(ann.members.Tester.area, "a" .. a1)
		T.ok(find(fx, "send"), "Ann answers")
		ns.GroupRooms.state.members.Ann = nil
		deliver(fx)
		T.eq(members().Ann.area, "a" .. a2, "her answer")
		deliver(Rooms.Step(ann, where(RUINS.iid, "a" .. a1), 20))
		T.eq(members().Ann.area, "a" .. a1, "Ann moved")
		-- Someone outside the group, a whisper, junk and another protocol change nothing, without an error.
		ns.Comm.OnMessage(ns.prefix, "L^2^2999^a" .. a2 .. "^0", "PARTY", "Stranger")
		ns.Comm.OnMessage(ns.prefix, "L^2^2999^a" .. a2 .. "^0", "WHISPER", "Ann")
		ns.Comm.OnMessage(ns.prefix, "L^2^2999^Room^0", "PARTY", "Ann")
		ns.Comm.OnMessage(ns.prefix, "L^1^2999^a" .. a2 .. "^0", "PARTY", "Ann")
		T.eq(members().Stranger, nil)
		T.eq(members().Ann.area, "a" .. a1)
		-- Bob leaves the group; then the player does, and everyone goes.
		deliver(Rooms.Step(Rooms.New(), where(RUINS.iid, "a" .. a2), 30), "Bob")
		T.ok(members().Bob)
		mock.units.party2 = nil
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		T.eq(members().Bob, nil, "Bob left the group")
		T.ok(members().Ann, "Ann stays")
		-- A boss fight longer than STALE: the game holds everyone's refresh, so nobody goes stale; afterwards the clock
		-- starts again.
		mock.lockdown = true
		mock.Advance(Rooms.STALE + 30, 5)
		T.ok(members().Ann, "kept through a long fight")
		mock.lockdown = false
		mock.Advance(Rooms.LOCK_CHECK + 1, 1)
		T.ok(members().Ann, "kept right after it")
		mock.Advance(Rooms.STALE, 5)
		T.eq(members().Ann, nil, "stale once a full STALE passed without her")
		mock.inGroup = false
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		T.eq(next(members()), nil, "out of the group: nobody")
	end)
end)

T.case("Rooms: which rooms are drawn on a floor (the plan's instance, the floor, a room the data names)", function()
	local bfd = assert(ns.Bundled.Get("b:blackfathom-deeps"))
	local data = ns.SubzoneData.blackfathomdeeps
	local floor1, floor2 = data[1], data[3]
	T.eq(floor1.at[1][1], 1)
	T.eq(floor2.at[1][1], 2)
	local key1, key2 = ns.Subzones.Key(floor1), ns.Subzones.Key(floor2)
	local members = {
		Ann = { iid = data.iid, area = key1 },
		Bob = { iid = data.iid, area = key1 },
		Cid = { iid = data.iid, area = key2 },
		Dee = { iid = data.iid }, -- in a spot the data does not name
		Eve = { iid = RUINS.iid, area = "a" .. RUINS[1].a }, -- in another instance
	}
	local who = { Ann = { name = "Ann", class = "PRIEST" } }
	local rooms = ns.MapGroup.Rooms(bfd, 1, members, who)
	T.eq(#rooms, 1)
	T.eq(rooms[1].key, key1)
	T.eq(rooms[1].x, floor1.at[1][2])
	T.eq(#rooms[1].members, 2)
	T.eq(rooms[1].members[1].name, "Ann")
	T.eq(rooms[1].members[1].class, "PRIEST")
	T.eq(rooms[1].members[2].name, "Bob", "a member the roster does not know yet: the sender's name")
	rooms = ns.MapGroup.Rooms(bfd, 2, members, who)
	T.eq(#rooms, 1, "floor 2")
	T.eq(rooms[1].members[1].name, "Cid")
	T.eq(#ns.MapGroup.Rooms({ instance = { name = "Nowhere" }, floors = { {} } }, 1, members, who), 0, "no data")
	-- The ring: one dot on the point, several apart, around a minimum.
	local one = ns.MapLayout.Ring(1, 16, 0)
	T.eq(one[1][1], 0)
	T.eq(one[1][2], 0)
	local five = ns.MapLayout.Ring(5, 16, 0)
	for i = 1, 5 do
		local j = i % 5 + 1
		local d = math.sqrt((five[i][1] - five[j][1]) ^ 2 + (five[i][2] - five[j][2]) ^ 2)
		T.ok(d >= 16 - 1e-9, "neighbours apart")
	end
	T.ok(math.abs(ns.MapLayout.Ring(1, 16, 30)[1][2] + 30) < 1e-9, "one on a minimum: at the top")
end)

T.case("Rooms: an instance several plans share (Scarlet Monastery): the sender's wing, the shown plan's areas", function()
	local Subzones = ns.Subzones
	local all = Subzones.ForInstance(189)
	T.eq(#all, 4, "four wings")
	T.eq(all[1], ns.SubzoneData.scarletmonasteryarmory, "in the order of their keys")
	-- A room of the last wing, named for the test (the data holds only hashes of the client's names).
	local room = ns.SubzoneData.scarletmonasterylibrary[3]
	local saved = { h = room.h[1], info = _G.GetInstanceInfo, sub = mock.subzone }
	room.h[1] = Subzones.Hash("Test Reading Room")
	Subzones.Reset()
	_G.GetInstanceInfo = function()
		return "Scarlet Monastery", "party", 1, "Normal", 5, 0, false, 189
	end
	mock.subzone = "Test Reading Room"
	local ok, err = pcall(function()
		local iid, key = ns.GroupRooms.Where()
		T.eq(iid, 189)
		T.eq(key, Subzones.Key(room), "the library's room")
		local members = { Ann = { iid = 189, area = key } }
		T.eq(#ns.MapGroup.Rooms(assert(ns.Bundled.Get("b:scarlet-monastery-library")), 1, members, {}), 1,
			"drawn on the library's map")
		T.eq(#ns.MapGroup.Rooms(assert(ns.Bundled.Get("b:scarlet-monastery-cathedral")), 1, members, {}), 0,
			"not on the cathedral's")
		-- A room of the same name in an earlier wing: the sender sends that wing's key, and the library's map still
		-- draws the member in its own room of that name.
		local twin = ns.SubzoneData.scarletmonasterycathedral[2]
		saved.twin = twin.h[1]
		twin.h[1] = room.h[1]
		Subzones.Reset()
		iid, key = ns.GroupRooms.Where()
		T.eq(iid, 189)
		T.eq(key, Subzones.Key(twin), "the first wing's room of that name")
		members.Ann.area = key
		local rooms = ns.MapGroup.Rooms(assert(ns.Bundled.Get("b:scarlet-monastery-library")), 1, members, {})
		T.eq(#rooms, 1, "drawn on the library's map too")
		T.eq(rooms[1].key, Subzones.Key(room), "in the library's room of that name")
		T.eq(#ns.MapGroup.Rooms(assert(ns.Bundled.Get("b:scarlet-monastery-armory")), 1, members, {}), 0,
			"not on a wing without that name")
		mock.subzone = "A corridor"
		iid, key = ns.GroupRooms.Where()
		T.eq(iid, 189)
		T.eq(key, nil, "inside, no area of that name")
	end)
	if saved.twin then
		ns.SubzoneData.scarletmonasterycathedral[2].h[1] = saved.twin
	end
	room.h[1], _G.GetInstanceInfo, mock.subzone = saved.h, saved.info, saved.sub
	Subzones.Reset()
	T.ok(ok, tostring(err))
end)

T.case("Rooms: areas that share a name count as one: the first with an anchor on the floor shown", function()
	local Subzones = ns.Subzones
	Subzones.Reset()
	local function hashes(v)
		local t = {}
		for i = 1, #ns.SubzoneLocales do
			t[i] = false
		end
		t[1] = v -- enUS, the mock client's language
		return t
	end
	local hall = Subzones.Hash("Hall")
	local data = { iid = 9001,
		{ w = 1, h = hashes(hall), at = { { 1, 0.1, 0.1 } } },
		{ w = 2, h = hashes(hall), at = { { 2, 0.2, 0.2 } } },
		{ a = 7, at = { { 2, 0.7, 0.7 }, { 3, 0.3, 0.3 } } }, -- the mock client names it "Area 7"
		{ w = 3, h = hashes(Subzones.Hash("Area 7")), at = { { 3, 0.9, 0.9 } } },
		{ w = 4, h = hashes(Subzones.Hash("Other")), at = { { 2, 0.4, 0.4 } } },
	}
	T.eq(Subzones.Place(data, "w1", 1).w, 1)
	local a, x, y = Subzones.Place(data, "w1", 2)
	T.eq(a.w, 2, "the same name on the floor shown")
	T.eq(x, 0.2)
	T.eq(y, 0.2)
	T.eq(Subzones.Place(data, "w2", 1).w, 1, "either key: the first in the data's order")
	T.eq(Subzones.Place(data, "w3", 3).a, 7, "an AreaTable name and a room's hash alike")
	T.eq(Subzones.Place(data, "w4", 1), nil, "no area of that name on that floor")
	T.eq(Subzones.Place(data, "w9", 1), nil, "a key the data does not have")
	-- Members who sent either key sit in one room.
	ns.SubzoneData.testinstance = data
	local plan = { instance = { name = "Test Instance" }, floors = { {}, {} } }
	local rooms = ns.MapGroup.Rooms(plan, 2, { Ann = { iid = 9001, area = "w1" }, Bob = { iid = 9001, area = "w2" } }, {})
	ns.SubzoneData.testinstance = nil
	T.eq(#rooms, 1)
	T.eq(rooms[1].key, "w2")
	T.eq(#rooms[1].members, 2)
end)

T.case("Subzones: an area name the client has not given yet is asked again, not kept as none", function()
	local Subzones = ns.Subzones
	local real = _G.C_Map.GetAreaInfo
	local answer
	_G.C_Map.GetAreaInfo = function()
		return answer
	end
	Subzones.Reset()
	local h = {}
	for i = 1, #ns.SubzoneLocales do
		h[i] = false
	end
	h[1] = Subzones.Hash("Late name")
	local data = { iid = 9001, { a = 7, at = { { 1, 0.5, 0.5 } } }, { w = 3, h = h, at = { { 1, 0.2, 0.2 } } } }
	local late = { instanceID = 9001, subzone = "Late name", hash = Subzones.Hash("Late name") }
	local ok, err = pcall(function()
		T.eq(Subzones.Names(data[1], late), false, "no name yet")
		T.eq(Subzones.Place(data, "w3", 1).w, 3, "the room alone")
		answer = "Late name"
		T.eq(Subzones.Names(data[1], late), true, "asked again")
		T.eq(Subzones.Place(data, "w3", 1).a, 7, "its hashes asked again: the first of that name")
	end)
	_G.C_Map.GetAreaInfo = real
	Subzones.Reset()
	T.ok(ok, tostring(err))
end)

T.case("Rooms on the map: several in a room spread, the player's room around the marker, another floor hides them", function()
	boot()
	ns.UI.Show()
	withGroup(function()
		local a1, a2 = RUINS[1].a, RUINS[2].a
		inRuins(a1)
		mock.FireEvent("ZONE_CHANGED")
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "ruins-of-lordaeron")
		ns.UI.SelectTab("map")
		ns.UI.RefreshPage()
		local view = _G.DungeonPlannerMainFrame.instancePage.panels.map.canvas
		view:DrawContent()
		T.ok(view.here:IsShown(), "the player's marker")
		T.eq(view.groupAt, nil, "nobody heard yet")
		-- Heard while the map shows: placed without a redraw.
		for _, h in ipairs({ { "Ann", a2 }, { "Bob", a2 }, { "Cid", a1 } }) do
			ns.GroupRooms.Step(heard(h[1], RUINS.iid, "a" .. h[2]))
		end
		local spots = view.groupAt
		T.eq(#spots, 2)
		local a = view.hereArgs
		local function anchor(area)
			local x, y = ns.Subzones.Anchor(ns.Subzones.Area(RUINS, "a" .. area), a.floor)
			return a.px(x, y), a.py(y, x)
		end
		local two, mine
		for _, spot in ipairs(spots) do
			if spot.mine then
				mine = spot
			else
				two = spot
			end
		end
		T.eq(#two.members, 2)
		T.eq(two.members[1].name, "Ann")
		local cx, cy = anchor(a2)
		local d1, d2 = two.dots[1], two.dots[2]
		T.ok((d1.x - d2.x) ^ 2 + (d1.y - d2.y) ^ 2 >= ns.MapGroup.DOT ^ 2, "two in one room do not overlap")
		T.ok(math.abs((d1.x - cx) ^ 2 + (d1.y - cy) ^ 2 - ((d2.x - cx) ^ 2 + (d2.y - cy) ^ 2)) < 1e-6, "around the room")
		T.eq(mine.members[1].name, "Cid")
		local at = view.hereAt
		local r = math.sqrt((mine.dots[1].x - at.x) ^ 2 + (mine.dots[1].y - at.y) ^ 2)
		T.ok(math.abs(r - at.r) < 1e-6, "on the edge of the player's marker")
		T.eq(view:GroupWithMe(), "Cid")
		-- The tooltip, from the map's hover update: over a dot it names that room's members.
		view:HereHover(d1.x, d1.y)
		T.eq(view.hereTip, two, "a dot's room")
		view:HereHover(at.x, at.y)
		T.eq(view.hereTip, at, "the marker's own tooltip inside it")
		view:HereHover(nil)
		local lines = {}
		local tt = { SetText = function(_, text)
			lines[#lines + 1] = text
		end, AddLine = function(_, text)
			lines[#lines + 1] = text
		end }
		ns.MapGroup.Tooltip(tt, two)
		T.eq(lines[2], "Ann")
		T.eq(lines[3], "Bob")
		-- No mouse taken: the map under the dots keeps it.
		local dots = 0
		for _, child in ipairs(rawget(view.overlay, "_children") or {}) do -- the mock's own list (GetChildren is a stub)
			if child.letter and child:IsShown() then
				dots = dots + 1
				T.ok(not child:IsMouseEnabled(), "a dot takes no mouse")
			end
		end
		T.eq(dots, 3)
		-- Ann moves to the player's room; Bob leaves the group.
		ns.GroupRooms.Step(heard("Ann", RUINS.iid, "a" .. a1))
		mock.units.party2 = nil
		mock.FireEvent("GROUP_ROSTER_UPDATE")
		T.eq(#view.groupAt, 1)
		T.eq(#view.groupAt[1].members, 2, "Ann and Cid with the player")
		-- The setting off hides them; on again shows them.
		ns.db.settings.mapGroup = false
		view:DrawContent()
		T.eq(view.groupAt, nil, "the setting turns them off")
		ns.db.settings.mapGroup = true
		view:DrawContent()
		T.ok(view.groupAt, "back on")
		-- Another floor: Blackfathom Deeps, members in a room of floor 2.
		local bfd = ns.SubzoneData.blackfathomdeeps
		ns.GroupRooms.Step(heard("Ann", bfd.iid, ns.Subzones.Key(bfd[3])))
		ns.GroupRooms.Step(heard("Cid", bfd.iid, ns.Subzones.Key(bfd[3])))
		ns.UI.SelectPlan(ns.Bundled.PREFIX .. "blackfathom-deeps")
		ns.UI.RefreshPage()
		ns.UI.GoToFloor(1)
		view:DrawContent()
		T.eq(view.groupAt, nil, "on another floor")
		ns.UI.GoToFloor(2)
		view:DrawContent()
		T.eq(#view.groupAt, 1, "on their floor")
		T.eq(#view.groupAt[1].members, 2)
	end)
	ns.UI.GoToFloor(1)
end)
