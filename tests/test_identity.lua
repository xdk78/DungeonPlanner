-- Instance identity (Data/InstanceIdentity.lua): a plan saved under a localized instance name finds the same bundled
-- data as an English one: map art, enemies, boss facts, prep and travel facts, corridor grids and its recommended plan.
-- Plans are made through the real New plan action (Home.CreatePlan) inside an instance on a German client, received
-- from a Spanish one through an export string, and saved by older versions without an instance ID.
local T = ...
local ns, mock = T.ns, T.mock
local Instances = ns.Instances

local function boot()
	if not _G.DungeonPlannerDB then
		mock.FireEvent("ADDON_LOADED", "DungeonPlanner")
		mock.loggedIn = true
		mock.FireEvent("PLAYER_LOGIN")
		mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	end
	if not ns.UI.IsShown() then
		ns.UI.Toggle()
	end
end

-- The old dungeon map tiles are in the client (Data/GameFiles.lua): the mock knows their first tiles for this file's
-- cases, and forgets them after the last one (other files' cases need a client without them).
local addedTiles = {}
for _, spec in pairs(ns.GameFiles.INSTANCES) do
	for _, base in ipairs(spec.tiles or {}) do
		local path = ("Interface\\WorldMap\\" .. base .. "1"):lower()
		if not mock.artFiles[path] then
			mock.artFiles[path] = true
			addedTiles[#addedTiles + 1] = path
		end
	end
end
ns.GameFiles.Reset()

local function bundled(id)
	return assert(ns.Bundled.Get(ns.Bundled.PREFIX .. id), id)
end

-- A plan as it is saved: validated, with an id.
local function make(raw)
	local plan = ns.Validate.Plan(raw)
	plan.id = ns.Util.UniqueId("p")
	return plan
end

-- A WoW: Forever client in another language, standing inside an instance: GetInstanceInfo gives the localized name
-- and the instance's map ID, the client has no map for the player there and no map info for the classic dungeon maps.
-- `zoneNames` = { [instance ID] = localized name } answers GetRealZoneText. Returns a function that restores it all.
local function client(locale, name, instanceID, zoneNames)
	local saved = {
		info = _G.GetInstanceInfo,
		best = _G.C_Map.GetBestMapForUnit,
		locale = _G.GetLocale,
		zone = rawget(_G, "GetRealZoneText"),
		mapInfo = mock.mapInfo,
	}
	_G.GetInstanceInfo = function()
		return name, name and "party" or "none", 1, "Normal", 5, 0, false, instanceID
	end
	_G.C_Map.GetBestMapForUnit = function()
		return nil
	end
	_G.GetLocale = function()
		return locale
	end
	_G.GetRealZoneText = zoneNames and function(id)
		return zoneNames[id] or ""
	end or nil
	mock.mapInfo = setmetatable({}, { __index = function()
		return { name = "" }
	end })
	ns.SetLocale("auto")
	Instances.ForgetIdentity()
	return function()
		_G.GetInstanceInfo, _G.C_Map.GetBestMapForUnit, _G.GetLocale = saved.info, saved.best, saved.locale
		_G.GetRealZoneText = saved.zone
		mock.mapInfo = saved.mapInfo
		ns.SetLocale("auto")
		Instances.ForgetIdentity()
	end
end

local function run(restore, fn)
	local ok, err = pcall(fn)
	restore()
	assert(ok, err)
end

local function count(list)
	return list and #list or 0
end

-- Everything the bundled data gives a plan, as one comparable description.
local function data(plan)
	local out = {}
	out[#out + 1] = "maps " .. table.concat(ns.MinimapArt.Sources(plan), ",")
	for i = 1, #plan.floors do
		local tiles = ns.GameFiles.FloorArt(plan, i)
		local reyes = ns.ReyesMaps.Pick(plan, i)
		out[#out + 1] = string.format("floor %d: tiles %s, reyes %s, enemies %d, corridors %s", i,
			tostring(tiles and tiles.base), tostring(reyes and reyes.file), #ns.Spawns.For(plan, i),
			tostring((ns.Corridors.KeyFor(plan, i))))
	end
	local boss = ns.BossData.Instance(plan)
	local travel = ns.Travel.For(plan)
	out[#out + 1] = string.format("bosses %s, quests %d, keys %d, travel %s, floors shown %d", tostring(boss and boss.slug),
		count(ns.BossData.Quests(plan)), count(ns.BossData.Keys(plan)), tostring(travel and travel.key),
		#ns.Floors.For(plan))
	return table.concat(out, "\n")
end

T.case("Identity: a new plan made inside an instance on a German client gets the English plan's data", function()
	boot()
	for _, c in ipairs({
		{ "Die Todesminen", "The Deadmines", "the-deadmines" },
		{ "Höhlen des Wehklagens", "Wailing Caverns", "wailing-caverns" },
		{ "Halle der Thane", "Hall of Thanes", "hall-of-thanes" },
	}) do
		local german, english, id = c[1], c[2], c[3]
		local iid = ns.TravelData.instances[english].iid
		local rec = bundled(id)
		-- The English client's plan, made the same way.
		local en
		run(client("enUS", english, iid), function()
			en = ns.Home.CreatePlan("blank", "New plan", nil)
		end)
		run(client("deDE", german, iid), function()
			T.eq(ns.activeLocale, "deDE", "a German interface")
			local plan = ns.Home.CreatePlan("blank", "Neuer Plan", nil)
			T.eq(plan.instance.name, german, "the client's name is stored for display")
			T.eq(plan.instance.instanceMapID, iid, english .. ": the instance's map ID is stored")
			T.eq(Instances.CanonicalName(plan), english)
			local d = data(plan)
			T.eq(d, data(en), english .. ": the same data as the English plan")
			T.ok(d:find("travel " .. ns.Providers.Key(english), 1, true), english .. ": travel facts\n" .. d)
			T.ok(d:find("bosses " .. id, 1, true), english .. ": boss facts\n" .. d)
			T.ok(not d:find("enemies 0", 1, true) or id == "hall-of-thanes", english .. ": enemies\n" .. d)
			T.eq(table.concat(ns.MinimapArt.Sources(plan), ","), table.concat(ns.MinimapArt.Sources(rec), ","),
				english .. ": the recommended plan's maps")
			-- The recommended plan is linked: the plan's page lists it, the home table shows one instance, not two.
			local entry = ns.UI.EntryForPlan(plan)
			T.eq(ns.Bundled.ForInstance(entry)[1], rec, english .. ": its recommended plan")
			T.ok(ns.Bundled.SameInstance(plan, ns.UI.EntryForPlan(rec)), english .. ": the same instance as the recommended")
			local cards = 0
			for _, e in ipairs((ns.Home.AllEntries())) do
				if ns.Bundled.SameInstance(plan, e) then
					cards = cards + 1
				end
			end
			T.eq(cards, 1, english .. ": one card on the home table")
			T.eq(ns.Recorder.KeyForPlan(plan), tostring(iid), english .. ": runs recorded there")
			local pics, recPics = ns.GameFiles.InstancePictures(entry), ns.GameFiles.InstancePictures(ns.UI.EntryForPlan(rec))
			T.eq(#pics, #recPics, english .. ": as many pictures for its card")
			T.eq(pics[1] and pics[1].file, recPics[1] and recPics[1].file, english .. ": the same picture on its card")
			T.ok(id ~= "hall-of-thanes" or #pics > 0, "Hall of Thanes' loading screen")
			ns.DB.DeletePlan(plan.id)
		end)
		ns.DB.DeletePlan(en.id)
	end
end)

T.case("Identity: a plan from the picker of a journal client in German stores the journal's instance map ID", function()
	boot()
	run(client("deDE", nil, nil), function()
		local entry = { key = "ej:7777", name = "Die Todesminen", kind = "dungeon", ejInstanceID = 7777, instanceMapID = 36 }
		local plan = ns.Home.CreatePlan("blank", "Neuer Plan", entry)
		T.eq(plan.instance.instanceMapID, 36)
		T.eq(plan.instance.ejInstanceID, 7777)
		T.eq(#plan.floors, 2, "the recommended plan's floors")
		T.eq(Instances.ResolvedKey(plan), "deadmines")
		T.eq(data(plan), data(bundled("the-deadmines")), "the recommended plan's data")
		ns.DB.DeletePlan(plan.id)
		-- On WoW: Forever the picker lists the recommended plans' instances, in English: the ID is stored as well.
		local english = ns.Home.CreatePlan("blank", "Neuer Plan", ns.UI.EntryForPlan(bundled("hall-of-thanes")))
		T.eq(english.instance.instanceMapID, ns.TravelData.instances["Hall of Thanes"].iid)
		ns.DB.DeletePlan(english.id)
	end)
end)

T.case("Identity: a plan received from a Spanish client finds the same data", function()
	boot()
	run(client("enUS", nil, nil), function()
		local rec = bundled("the-deadmines")
		-- Made inside the instance on a Spanish client by this version: the name in Spanish, the instance's map ID.
		local spanish = ns.Plan.New({ name = "Mi plan", instance = { name = "Las Minas de la Muerte", kind = "dungeon",
			instanceMapID = 36 }, floors = ns.Floors.Initial({ name = "Las Minas de la Muerte", kind = "dungeon" }, 36) })
		local text = assert(ns.Codec.ExportPlan(spanish))
		local ok, message, added = ns.DB.ImportString(text, { kind = "paste" })
		T.ok(ok, message)
		local got = added[1]
		T.eq(got.instance.name, "Las Minas de la Muerte")
		T.eq(got.instance.instanceMapID, 36, "the ID survives the export string")
		T.eq(data(got), data(rec), "the recommended plan's data")
		T.eq(ns.Bundled.ForInstance(ns.UI.EntryForPlan(got))[1], rec)
		ns.DB.DeletePlan(got.id)
		-- Made by an older version: no instance ID, but the recommended plan's floors with their maps.
		local old = make({ name = "Viejo", instance = { name = "Las Minas de la Muerte", kind = "dungeon" },
			floors = { { uiMapID = 291, name = "The Deadmines" }, { uiMapID = 292, name = "Ironclad Cove" } } })
		T.eq(Instances.ResolvedKey(old), "deadmines", "by the floors' maps")
		T.eq(data(old), data(rec))
		-- A Forever dungeon from an older version: no ID, no floor maps; the floors carry the recommended plan's names.
		local hall = bundled("hall-of-thanes")
		local floors = {}
		for i, f in ipairs(hall.floors) do
			floors[i] = { name = f.name }
		end
		local forever = make({ name = "Viejo", instance = { name = "Salón de los Thane", kind = "dungeon" },
			floors = floors })
		local r, how = Instances.Resolve(forever)
		T.ok(r and r.key == "hallofthanes" and how == "floors", "by the floor names: " .. tostring(how))
		T.eq(table.concat(ns.MinimapArt.Sources(forever), ","), table.concat(ns.MinimapArt.Sources(hall), ","))
	end)
end)

T.case("Identity: wings sharing one instance ID are told apart by floor, name or words, never guessed", function()
	boot()
	run(client("deDE", nil, nil), function()
		local iid = ns.TravelData.instances["Scarlet Monastery: Library"].iid
		local function plan(name, floors, planName)
			return make({ name = planName or "Plan", instance = { name = name, kind = "dungeon", instanceMapID = iid },
				floors = floors })
		end
		local library = plan("Scharlachrotes Kloster", { { uiMapID = 303, name = "" } })
		T.eq(Instances.ResolvedKey(library), "scarletmonasterylibrary", "the Library by its floor's map")
		T.eq(ns.GameFiles.FloorArt(library, 1).base, ns.GameFiles.FloorArt(bundled("scarlet-monastery-library"), 1).base,
			"the Library's map")
		local armory = plan("Scharlachrotes Kloster", { { uiMapID = 437, name = "" } })
		T.eq(Instances.ResolvedKey(armory), "scarletmonasteryarmory", "the Armory by its floor's map")
		T.ok(ns.GameFiles.FloorArt(armory, 1).base ~= ns.GameFiles.FloorArt(library, 1).base, "another map")
		T.eq(Instances.ResolvedKey(plan("Scharlachrotes Kloster", { { name = "Cathedral" } })), "scarletmonasterycathedral",
			"by the recommended plan's floor name")
		T.eq(Instances.ResolvedKey(plan("Scharlachrotes Kloster (Graveyard)", { { name = "" } })),
			"scarletmonasterygraveyard", "by the wing's label in the instance name")
		T.eq(Instances.ResolvedKey(plan("Scarlet Monastery: Armory", { { name = "" } })), "scarletmonasteryarmory",
			"by the English name")
		-- Nothing tells the wing: no wing at all, not the first one.
		local unclear = plan("Scharlachrotes Kloster", { { name = "Scharlachrotes Kloster" } }, "Mein Plan")
		local r, how, cands = Instances.Resolve(unclear)
		T.ok(r == nil and how == "ambiguous" and #cands == 4, "four wings, none picked")
		T.eq(ns.GameFiles.FloorArt(unclear, 1), nil, "no wing's map")
		T.eq(ns.Spawns.KeyFor(unclear), nil, "no wing's enemies")
		T.eq(ns.Travel.For(unclear), nil, "no wing's travel facts")
		T.eq(ns.BossData.Instance(unclear), nil, "no wing's boss facts")
		T.eq(select(1, Instances.InstanceMapID(unclear)), iid, "the instance itself is known")
		local _, _, _, unclearList = Instances.IdentityReport({ unclear, library })
		T.eq(#unclearList, 1, "/dp debug lists it")
		-- New plan inside Scarlet Monastery: the client says which instance, not which wing.
		local restore = client("deDE", "Scharlachrotes Kloster", iid)
		local ok, err = pcall(function()
			local made = ns.Home.CreatePlan("blank", "Neuer Plan", nil)
			T.eq(made.instance.instanceMapID, iid)
			T.eq(#made.floors, 1, "one floor, no wing's floors")
			T.eq(Instances.ResolvedKey(made), nil, "no wing guessed")
			T.eq(ns.GameFiles.FloorArt(made, 1), nil)
			ns.DB.DeletePlan(made.id)
		end)
		restore()
		assert(ok, err)
		-- Stratholme's two wings have the same floors: only a name tells them apart.
		local strat = ns.TravelData.instances["Stratholme: Live (Main Gate)"].iid
		local function stratPlan(planName)
			return make({ name = planName, instance = { name = "Stratholme", kind = "dungeon", instanceMapID = strat },
				floors = { { name = "Crusader's Square" }, { name = "The Gauntlet" } } })
		end
		T.eq(Instances.ResolvedKey(stratPlan("Plan")), nil, "both wings have these floors")
		-- A plan's own name never picks a wing: players name plans freely, and words such as "main", "gate", "entrance"
		-- or another wing's label in it say nothing about the wing.
		for _, name in ipairs({ "Main tank route", "Entrance pulls", "Undead side", "Service entrance run", "Live" }) do
			T.eq(Instances.ResolvedKey(stratPlan(name)), nil, "plan name '" .. name .. "' picks no wing")
		end
		T.eq(Instances.ResolvedKey(plan("Scharlachrotes Kloster", { { name = "" } }, "Library and Graveyard")), nil,
			"Scarlet Monastery: the plan's name picks no wing")
		local lower = make({ name = "Upper key quest", instance = { name = "Untere Schwarzfelsspitze", kind = "dungeon",
			instanceMapID = ns.TravelData.instances["Lower Blackrock Spire"].iid }, floors = { { name = "" } } })
		T.eq(Instances.ResolvedKey(lower), nil, "a Lower Spire plan named 'Upper ...' is not the Upper Spire")
		-- Only the label counts in the instance name: "Main Gate" is not "Live".
		local function stratNamed(name)
			return make({ name = "Plan", instance = { name = name, kind = "dungeon", instanceMapID = strat },
				floors = { { name = "" } } })
		end
		T.eq(Instances.ResolvedKey(stratNamed("Stratholme (Undead)")), "stratholmeundeadserviceentrance", "its label")
		T.eq(Instances.ResolvedKey(stratNamed("Stratholme Main Gate")), nil, "generic words of the name do not count")
		-- Blackrock Spire: the lower spire's six floors, or the upper spire's seventh.
		local brs = ns.TravelData.instances["Lower Blackrock Spire"].iid
		local function spire(rec)
			local floors = {}
			for i, f in ipairs(rec.floors) do
				floors[i] = { name = f.name }
			end
			return make({ name = "Plan", instance = { name = "Schwarzfelsspitze", kind = "dungeon",
				instanceMapID = brs }, floors = floors })
		end
		T.eq(Instances.ResolvedKey(spire(bundled("lower-blackrock-spire"))), "lowerblackrockspire", "exactly its floors")
		T.eq(Instances.ResolvedKey(spire(bundled("upper-blackrock-spire"))), "upperblackrockspire", "the seventh floor")
		-- Dire Maul: each wing's floors have their own names.
		local dm = ns.TravelData.instances["Dire Maul: East"].iid
		local east = make({ name = "Plan", instance = { name = "Düsterbruch", kind = "dungeon", instanceMapID = dm },
			floors = { { name = "Warpwood Quarter" } } })
		T.eq(Instances.ResolvedKey(east), "diremauleast")
	end)
end)

T.case("Identity: a plan with only a localized name is found through the client's names, else listed", function()
	boot()
	local rec = bundled("the-deadmines")
	local function saved(name)
		return make({ name = "Alt", instance = { name = name, kind = "dungeon" }, floors = { { name = name } } })
	end
	-- The client names each instance ID (GetRealZoneText): the plan's name is one of them.
	run(client("deDE", nil, nil, { [36] = "Die Todesminen", [43] = "Die Höhlen des Wehklagens" }), function()
		local plan = saved("Die Todesminen")
		local r, how = Instances.Resolve(plan)
		T.ok(r and r.key == "deadmines" and how == "client", "by the client's name: " .. tostring(how))
		T.eq(ns.Travel.For(plan), ns.Travel.For(rec))
		T.eq(ns.BossData.Instance(plan), ns.BossData.Instance(rec))
		T.eq(ns.GameFiles.FloorArt(plan, 1).base, ns.GameFiles.FloorArt(rec, 1).base, "the map of the first floor")
		T.eq(ns.Bundled.ForInstance(ns.UI.EntryForPlan(plan))[1], rec, "its recommended plan")
		T.eq(Instances.InstanceMapID(plan), 36)
	end)
	-- The Group Finder's browse list names it (the mock's Forever dungeon, instance 3065).
	run(client("deDE", nil, nil), function()
		T.eq(Instances.ResolvedKey(saved("Hall of Forever Tests")), "hallofthanes", "by the Group Finder's name")
	end)
	-- Neither: the stored name stays, and /dp debug says so.
	run(client("esES", nil, nil), function()
		local plan = saved("Las Minas de la Muerte")
		T.eq(Instances.Resolve(plan), nil)
		T.eq(Instances.CanonicalName(plan), "Las Minas de la Muerte", "the stored name as the fallback")
		T.eq(ns.Travel.For(plan), nil)
		local matched, total, unknown = Instances.IdentityReport({ plan, rec })
		T.ok(matched == 1 and total == 2 and #unknown == 1 and unknown[1]:find("Las Minas", 1, true), "listed")
		-- An instance ID no bundled instance has: another instance, whatever its floors' maps say.
		local other = make({ name = "X", instance = { name = "Somewhere", kind = "dungeon", instanceMapID = 99999 },
			floors = { { uiMapID = 291, name = "" } } })
		T.eq(Instances.Resolve(other), nil)
		-- An outdoor plan is not an instance: its zone map is not a floor of one.
		local zone = ns.TravelData.instances["Scholomance"].zm
		local outdoor = make({ name = "X", instance = { name = "Westliche Pestländer", kind = "other",
			uiMapID = zone }, floors = { { uiMapID = zone, name = "" } } })
		T.eq(Instances.Resolve(outdoor), nil, "Scholomance's outside floor does not make the zone Scholomance")
	end)
end)

T.case("Identity: the instance map ID is an optional plan field; copies and older readers keep the plan valid", function()
	local p = make({ name = "A", instance = { name = "Die Todesminen", kind = "dungeon", instanceMapID = 36 } })
	T.eq(p.instance.instanceMapID, 36)
	T.eq(make({ name = "A", instance = { name = "x", instanceMapID = "36" } }).instance.instanceMapID, nil,
		"only an integer")
	T.eq(make({ name = "A", instance = { name = "x", instanceMapID = -1 } }).instance.instanceMapID, nil)
	T.eq(ns.Plan.Duplicate(p, "B").instance.instanceMapID, 36, "a copy keeps it")
	-- Every recommended plan is its own instance.
	for _, rec in ipairs(ns.Bundled.All()) do
		if ns.TravelData.instances[rec.instance.name] then -- the shipped ones (tests add their own)
			T.eq(Instances.ResolvedKey(rec), ns.Providers.Key(rec.instance.name), rec.id)
			T.ok(ns.Travel.For(rec) ~= nil, rec.id .. ": travel facts")
		end
	end
end)

T.case("Identity: an English name resolves as before; zones are never looked for by maps, floors or client names", function()
	boot()
	run(client("enUS", nil, nil), function()
		-- The exact English name first, unless the instance's ID rules it out: an ID no bundled instance has does not.
		local mc = make({ name = "Plan", instance = { name = "Molten Core", kind = "raid", instanceMapID = 99999 } })
		T.eq(Instances.ResolvedKey(mc), "moltencore", "Molten Core with an unknown instance ID")
		-- An English Lower Spire plan whose floors carry every spire map (the Upper Spire's seventh too): its name wins.
		local floors = {}
		for m = 250, 256 do
			floors[#floors + 1] = { uiMapID = m, name = "" }
		end
		local brs = ns.TravelData.instances["Lower Blackrock Spire"].iid
		for _, iid in ipairs({ false, brs }) do
			local lower = make({ name = "Plan", instance = { name = "Lower Blackrock Spire", kind = "dungeon",
				instanceMapID = iid or nil }, floors = floors })
			T.eq(Instances.ResolvedKey(lower), "lowerblackrockspire", "by its English name, ID " .. tostring(iid))
		end
		-- A zone (kind "other") with a floor named like a recommended plan's floor stays a zone.
		local zone = make({ name = "Plan", instance = { name = "Somewhere outdoors", kind = "other" },
			floors = { { name = "Library" } } })
		T.eq(Instances.Resolve(zone), nil, "a zone plan with a floor named Library")
		local dungeon = make({ name = "Plan", instance = { name = "Somewhere", kind = "dungeon" }, floors = { { name = "Library" } } })
		T.eq(Instances.ResolvedKey(dungeon), "scarletmonasterylibrary", "the same floor in a dungeon plan does count")
	end)
end)

T.case("Identity: the client's names answer only when one instance has the name", function()
	boot()
	local function saved(name)
		return make({ name = "Alt", instance = { name = name, kind = "dungeon" }, floors = { { name = name } } })
	end
	-- Two instance IDs answer the same name: no answer.
	run(client("deDE", nil, nil, { [36] = "Die Todesminen", [43] = "Die Todesminen" }), function()
		T.eq(Instances.Resolve(saved("Die Todesminen")), nil, "one name, two instances")
	end)
	-- The client ignores the argument and gives the current zone for every ID: no answer for anything.
	local everywhere = setmetatable({}, { __index = function()
		return "Wald von Elwynn"
	end })
	run(client("deDE", nil, nil, everywhere), function()
		T.eq(Instances.Resolve(saved("Wald von Elwynn")), nil, "the current zone is no instance")
		T.eq(Instances.Resolve(saved("Die Todesminen")), nil, "and names nothing else")
	end)
end)

T.case("Identity: level ranges by instance ID only when the Group Finder lists one instance for it", function()
	boot()
	local real = _G.C_LFGList
	_G.C_LFGList = {
		GetAvailableActivities = function()
			return { 1, 2, 3 }
		end,
		GetActivityInfoTable = function(id)
			local rows = {
				{ "Blackrock Depths - Detention Block", 40, 45, 230 },
				{ "Blackrock Depths - Upper City", 45, 50, 230 },
				{ "Die Todesminen", 18, 23, 36 },
			}
			local r = rows[id]
			return r and { fullName = r[1], minLevelSuggestion = r[2], maxLevelSuggestion = r[3], mapID = r[4] } or nil
		end,
	}
	ns.GameFiles.Reset()
	local ok, err = pcall(function()
		local brd = bundled("blackrock-depths")
		local lo, hi = ns.Instances.LevelRange(ns.UI.EntryForPlan(brd))
		T.ok(lo == brd.instance.levelMin and hi == brd.instance.levelMax, "two parts listed: the plan's own range, "
			.. tostring(lo) .. "-" .. tostring(hi))
		lo, hi = ns.Instances.LevelRange(ns.UI.EntryForPlan(bundled("the-deadmines")))
		T.ok(lo == 18 and hi == 23, "one entry for the Deadmines' ID, in German: " .. tostring(lo) .. "-" .. tostring(hi))
	end)
	_G.C_LFGList = real
	ns.GameFiles.Reset()
	assert(ok, err)
end)

T.case("Identity: run mode's 'in the plan's instance' tells wings apart when both are known", function()
	boot()
	run(client("deDE", nil, nil), function()
		local iid = ns.TravelData.instances["Scarlet Monastery: Library"].iid
		local library = make({ name = "Plan", instance = { name = "Scharlachrotes Kloster", kind = "dungeon",
			instanceMapID = iid }, floors = { { uiMapID = 303, name = "" } } })
		local unclear = make({ name = "Plan", instance = { name = "Scharlachrotes Kloster", kind = "dungeon",
			instanceMapID = iid }, floors = { { name = "" } } })
		local function here(uiMapID, instanceID)
			return { inInstance = true, instanceID = instanceID or iid, uiMapID = uiMapID, name = "Scharlachrotes Kloster" }
		end
		T.ok(Instances.IsHere(library, here(303)), "in the Library")
		T.ok(not Instances.IsHere(library, here(437)), "the client says Armory: not the Library's run")
		T.ok(Instances.IsHere(library, here(nil)), "the client names no wing: the shared instance counts")
		T.ok(Instances.IsHere(unclear, here(437)), "the plan's wing is unclear: the shared instance counts")
		T.ok(not Instances.IsHere(library, here(nil, 36)), "another instance")
		T.ok(not Instances.IsHere(library, { inInstance = false }), "outside")
	end)
end)

-- After the last case: the client without the tiles this file added.
for _, path in ipairs(addedTiles) do
	mock.artFiles[path] = nil
end
ns.GameFiles.Reset()
