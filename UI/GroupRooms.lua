-- Where the group is, by room: the glue between Share/Rooms.lua's state machine and the game.
--
-- * In: the zone events and group changes become "where" and "roster" events; Comm hands over L messages from the
--   group channel, taken only from members of this client's own roster.
-- * Out: "send" goes to the group through Comm.SendSync (the lockdown outbox; a newer room replaces one still waiting),
--   "timer" through C_Timer, "changed" fires GROUP_ROOMS (map views place the dots again, UI/MapGroup.lua).
-- Outside a group nothing is read from the game but whether there is one. Nothing is sent outside an instance except
-- the one message that tells the group the player left it; a timer runs only while a change waits, a refresh is due
-- inside, or a member's room can go stale.

local _, ns = ...
local GroupRooms = ns:NewModule("GroupRooms")
local Rooms = ns.Rooms

GroupRooms.EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
	"GROUP_ROSTER_UPDATE" }
GroupRooms.state = Rooms.New()

local apply

function GroupRooms.Step(event)
	event.locked = ns.Comm.IsLockedDown()
	apply(Rooms.Step(GroupRooms.state, event, ns.Clock()))
end

-- Setting "Share my room with my group".
function GroupRooms.Sharing()
	return not (ns.db and ns.db.settings.share.rooms == false)
end

-- The player's place as the game says it: the instance map ID while the data names that instance's areas, and the key
-- of the first area the sub-zone names, in any plan of the instance (nil for none).
function GroupRooms.Where()
	local Subzones = ns.Subzones
	local where = Subzones.Where()
	local all = Subzones.ForInstance(where.instanceID)
	if #all == 0 then
		return nil
	end
	for _, data in ipairs(all) do
		local area = Subzones.Find(data, where)[1]
		if area then
			return where.instanceID, Subzones.Key(area)
		end
	end
	return where.instanceID, nil
end

-- On a zone or group change, and when the setting changes.
function GroupRooms.Update()
	local group = ns.Comm.IsAvailable() and ns.Comm.GroupChannel() ~= nil
	local iid, area
	if group then
		iid, area = GroupRooms.Where()
	end
	GroupRooms.Step({ type = "where", group = group, share = GroupRooms.Sharing(), iid = iid, area = area })
	GroupRooms.Step({ type = "roster", members = group and ns.Comm.GroupMembers() or {} })
end

-- What the other members said: { [name] = { iid, area, at } }. Read it, never change it.
function GroupRooms.Members()
	return GroupRooms.state.members
end

function apply(effects)
	for _, e in ipairs(effects) do
		local kind = e[1]
		if kind == "send" then
			ns.Comm.SendSync(ns.Transfer.Encode(e[2]), ns.Comm.GroupChannel(), nil, "room")
		elseif kind == "timer" then
			if C_Timer and C_Timer.After then
				C_Timer.After(e[2] + 0.05, function()
					ns.SafeCall(GroupRooms.Step, { type = "tick" })
				end)
			end
		elseif kind == "changed" then
			ns:Fire("GROUP_ROOMS")
		end
	end
end

-- From Comm.OnMessage, protocol checked: only on the group channel, only from a member of the group.
local GROUP_CHANNEL = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
function GroupRooms.OnMessage(msg, sender, channel)
	if not GROUP_CHANNEL[channel] or not ns.Comm.GroupRank(sender).inGroup then
		return
	end
	GroupRooms.Step({ type = "heard", from = sender, iid = msg.iid, area = msg.area, ask = msg.ask })
end

function GroupRooms.Init()
	for _, event in ipairs(GroupRooms.EVENTS) do
		ns:RegisterEvent(event, GroupRooms.Update)
	end
end
