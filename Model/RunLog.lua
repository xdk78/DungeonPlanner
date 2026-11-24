-- RunLog, the run recorder's model: what happened in a dungeon run, from what the client lets an addon read inside an instance.
-- Pure Lua 5.1; Tracker/Recorder.lua feeds it game events. docs/COMPATIBILITY.md section 10 says what can and cannot be
-- read inside instances: no positions, no creature identity, so a run is recorded as a sequence of pulls (combat
-- segments) with their size and make-up, boss kills and wipes, with timing. Nothing secret is stored: every value
-- read from the game passes Util.Plain before it reaches this module.
--
-- The store (DungeonPlannerDB.char[key].recorder), compact field names because it is saved:
--   current   the run being recorded or nil
--   runs      [instance key] = { run, ... } finished runs, oldest first, at most MAX_RUNS per instance
-- An instance key is GetInstanceInfo's instance ID as a string ("189"), or, for one wing of an instance whose wings
-- share that ID (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire), the ID and the wing's bundled key
-- ("189:scarletmonasterylibrary"). A run whose wing was not known keeps the plain ID (runs saved before 0.2.1 all do).
-- A run:
--   k key, n instance name, d difficultyID, t start (wall time), e end (wall time), done = finished
--   p pulls: { s = start (seconds after t), u = duration, c = enemies seen at once (peak), el = elites, r = rares,
--              b = bosses (by classification), lo/hi = level range, nm = plain names (<= MAX_NAMES), z = sub-zone,
--              kn = names of enemies fought, from kill messages and casts (<= MAX_NAMES, see Learn), dd = deaths,
--              w = wipe, k = encounter killed during the pull }
--   b boss kills: { i = encounterID, n = name, a = seconds after t, p = pull index }
--   w wipes (count), dd deaths (count), dk = deaths could be read (else the deaths count is not available)
--   wx = seen in two wings (kills of two wings' bosses): its wing stays unknown (Unwing)

local _, ns = ...
local Recorder = ns:NewModule("RunLog")
local Util = ns.Util

Recorder.MAX_RUNS = 20 -- per instance
Recorder.MAX_PULLS = 120 -- per run
Recorder.MAX_NAMES = 4 -- per pull
Recorder.MAX_INSTANCES = 60
Recorder.RESUME = 30 * 60 -- a run continues when the player comes back to the same instance within this time
Recorder.KILL_DEDUPE = 15 -- ENCOUNTER_END and BOSS_KILL report the same kill

local CLASS = { elite = "el", rareelite = "r", rare = "r", worldboss = "b" }

function Recorder.NewStore()
	return { runs = {} }
end

-- Repair a store loaded from SavedVariables (wrong types become empty, lists are capped).
-- A stored run the rest of this file can read: its key and start time, pulls with their start, kills with their
-- encounter and time. A missing kill list is filled in.
local function soundRun(run)
	if type(run) ~= "table" or type(run.k) ~= "string" or type(run.t) ~= "number" or type(run.p) ~= "table" then
		return false
	end
	if run.b == nil then
		run.b = {}
	end
	if type(run.b) ~= "table" then
		return false
	end
	for _, p in ipairs(run.p) do
		if type(p) ~= "table" or type(p.s) ~= "number" then
			return false
		end
	end
	for _, b in ipairs(run.b) do
		if type(b) ~= "table" or type(b.a) ~= "number" or type(b.i) ~= "number" then
			return false
		end
	end
	return true
end

function Recorder.Normalize(store)
	if type(store) ~= "table" then
		return Recorder.NewStore()
	end
	if type(store.runs) ~= "table" then
		store.runs = {}
	end
	for key, list in pairs(store.runs) do
		if type(key) ~= "string" or type(list) ~= "table" then
			store.runs[key] = nil
		else
			for i = #list, 1, -1 do
				if not soundRun(list[i]) then
					table.remove(list, i)
				end
			end
			while #list > Recorder.MAX_RUNS do
				table.remove(list, 1)
			end
		end
	end
	if store.current ~= nil and not soundRun(store.current) then
		store.current = nil
	end
	return store
end

-- Instance keys ----------------------------------------------------------------------------------------------------------

-- The key of one wing of an instance: "189:scarletmonasterylibrary".
function Recorder.WingKey(instanceKey, wing)
	return tostring(instanceKey) .. ":" .. wing
end

-- A key's instance part ("189") and its wing (nil for a key without one).
function Recorder.SplitKey(key)
	if type(key) ~= "string" then
		return nil
	end
	local iid, wing = key:match("^([^:]+):(.+)$")
	if iid then
		return iid, wing
	end
	return key, nil
end

-- Can a run recorded under `run.k` go on under `key`? The same instance and not two different wings. A run whose wing
-- was not known takes the wing `key` names, unless it was seen in two wings (`wx`, Unwing): that run stays unknown.
function Recorder.Adopt(run, key)
	local iid, wing = Recorder.SplitKey(key)
	local runIid, runWing = Recorder.SplitKey(run.k)
	if not iid or iid ~= runIid or (wing and runWing and wing ~= runWing) then
		return false
	end
	if wing and not runWing and not run.wx then
		run.k = key
	end
	return true
end

-- A run that turned out to span two wings (a kill of another wing's boss, where the floor map cannot tell the wings
-- apart: Dire Maul, Stratholme): back to the bare instance ID, "wing unknown" for good (`wx`), never another wing's.
-- Returns true when the key changed.
function Recorder.Unwing(run)
	local iid, wing = Recorder.SplitKey(run.k)
	run.wx = true
	if wing then
		run.k = iid
		return true
	end
	return false
end

local function newRun(key, name, difficultyID, now)
	return { k = key, n = Util.CleanText(name or "", 64) or "", d = Util.IsInteger(difficultyID) and difficultyID or nil,
		t = now, seen = now, p = {}, b = {}, w = 0, dd = 0 }
end

-- Entering an instance: continue the current run when it is the same instance (and not another wing of it) and recent,
-- otherwise finish it and start a new one. Returns the run and whether it is new.
function Recorder.Enter(store, key, name, difficultyID, now)
	local run = store.current
	if run and run.d == (Util.IsInteger(difficultyID) and difficultyID or nil)
		and now - (run.seen or run.t) <= Recorder.RESUME and Recorder.Adopt(run, key) then
		run.seen = now
		return run, false
	end
	Recorder.Finish(store, now)
	run = newRun(key, name, difficultyID, now)
	store.current = run
	return run, true
end

function Recorder.Leave(store, now)
	if store.current then
		store.current.seen = now
	end
end

-- The pull in progress (the last one, while it has no duration yet).
function Recorder.OpenPull(run)
	local pull = run and run.p[#run.p]
	if pull and pull.u == nil then
		return pull
	end
	return nil
end

function Recorder.PullStart(run, now, subzone)
	if not run or Recorder.OpenPull(run) or #run.p >= Recorder.MAX_PULLS then
		return nil
	end
	local pull = { s = math.max(0, now - run.t), c = 0, el = 0, r = 0, b = 0 }
	subzone = Util.CleanText(subzone, 48)
	if subzone and subzone ~= "" then
		pull.z = subzone
	end
	run.p[#run.p + 1] = pull
	run.seen = now
	return pull
end

-- Add a plain name to one of a pull's name lists (nm, kn): bounded, each name once. Returns whether it was added.
local function addName(pull, field, name)
	name = type(name) == "string" and Util.CleanText(name, 48) or nil
	if not name or name == "" then
		return false
	end
	local list = pull[field]
	if list and (#list >= Recorder.MAX_NAMES or Util.IndexOf(list, name)) then
		return false
	end
	if not list then
		list = {}
		pull[field] = list
	end
	list[#list + 1] = name
	return true
end

-- One look at the enemies in combat: units = { { level = n?, class = "elite"|..., name = plain string? }, ... }.
-- Unit identity is secret inside instances, so the same mob cannot be told apart between looks: a pull's size is the
-- most enemies seen at once (peak), and so is each class count.
function Recorder.Observe(run, units)
	local pull = Recorder.OpenPull(run)
	if not pull or type(units) ~= "table" then
		return
	end
	local c, el, r, b = 0, 0, 0, 0
	for _, u in ipairs(units) do
		c = c + 1
		local field = CLASS[u.class]
		if field == "el" then
			el = el + 1
		elseif field == "r" then
			r = r + 1
		elseif field == "b" then
			b = b + 1
		end
		local lv = u.level
		if Util.IsInteger(lv) and lv > 0 then
			pull.lo = math.min(pull.lo or lv, lv)
			pull.hi = math.max(pull.hi or lv, lv)
		elseif lv == -1 then
			b = b + (field == "b" and 0 or 1) -- "??" level: a boss
		end
		addName(pull, "nm", u.name)
	end
	pull.c = math.max(pull.c, c)
	pull.el = math.max(pull.el, el)
	pull.r = math.max(pull.r, r)
	pull.b = math.max(pull.b, b)
end

-- An enemy's name from the game's own text (a kill message, a cast's target) for the pull in progress. It goes in kn,
-- beside the nameplates' nm, and never replaces it.
function Recorder.Learn(run, name)
	local pull = Recorder.OpenPull(run)
	return pull ~= nil and addName(pull, "kn", name)
end

-- A pull's names to show: the nameplates' first, then the learned ones, each once, at most MAX_NAMES.
function Recorder.PullNames(pull)
	local out = {}
	for _, field in ipairs({ "nm", "kn" }) do
		for _, name in ipairs(type(pull[field]) == "table" and pull[field] or {}) do
			if type(name) == "string" and #out < Recorder.MAX_NAMES and not Util.IndexOf(out, name) then
				out[#out + 1] = name
			end
		end
	end
	return out
end

-- A client format string ("%s dies, you gain %d experience.", "%1$s dies.") as a Lua pattern, so the message reads in
-- every client language. Returns the pattern and which capture is the format's first argument (the dead enemy's name);
-- nil when there is none or the format uses a conversion other than %s and %d.
function Recorder.FormatPattern(format)
	if type(format) ~= "string" then
		return nil
	end
	local parts, args, sequential, i = {}, {}, 0, 1
	while i <= #format do
		if format:sub(i, i) ~= "%" then
			parts[#parts + 1] = (format:sub(i, i):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
			i = i + 1
		else
			local _, last, position, conversion = format:find("^%%(%d+)%$([sd])", i)
			if not last then
				_, last, conversion = format:find("^%%([sd])", i)
				sequential = sequential + (last and 1 or 0)
				position = sequential
			end
			if last then
				args[#args + 1] = { position = tonumber(position), conversion = conversion }
				parts[#parts + 1] = conversion == "s" and "(.-)" or "(%d+)"
				i = last + 1
			elseif format:sub(i + 1, i + 1) == "%" then
				parts[#parts + 1] = "%%"
				i = i + 2
			else
				return nil
			end
		end
	end
	for at, arg in ipairs(args) do
		if arg.position == 1 and arg.conversion == "s" then
			return "^" .. table.concat(parts) .. "$", at
		end
	end
	return nil
end

function Recorder.KillPatterns(formats)
	local out = {}
	for _, format in ipairs(formats) do
		local pattern, at = Recorder.FormatPattern(format)
		if pattern then
			out[#out + 1] = { pattern = pattern, at = at }
		end
	end
	return out
end

function Recorder.KilledName(patterns, text)
	if type(text) ~= "string" then
		return nil
	end
	for _, p in ipairs(patterns) do
		local name = ({ text:match(p.pattern) })[p.at]
		if name and name ~= "" then
			return name
		end
	end
	return nil
end

-- Combat ended. deaths = group members dead at the end; wiped = everyone dead. A pull in which no enemy was ever seen
-- (a stray hit, a duel, combat with no nameplate shown) is dropped, unless a kill message or cast named an enemy.
function Recorder.PullEnd(run, now, deaths, wiped)
	local pull = Recorder.OpenPull(run)
	if not pull then
		return nil
	end
	pull.u = math.max(0, now - run.t - pull.s)
	if Util.IsInteger(deaths) then
		run.dk = true
	end
	if Util.IsInteger(deaths) and deaths > 0 then
		pull.dd = deaths
		run.dd = (run.dd or 0) + deaths
	end
	if wiped and not pull.w then
		pull.w = true
		run.w = (run.w or 0) + 1
	end
	if pull.c == 0 and not pull.k and not pull.w and not pull.kn then
		run.p[#run.p] = nil
		return nil
	end
	run.seen = now
	return pull
end

-- A boss died (ENCOUNTER_END success or BOSS_KILL). Repeated reports of one kill count once.
function Recorder.BossKill(run, encounterID, name, now)
	if not run or not Util.IsInteger(encounterID) then
		return nil
	end
	for _, b in ipairs(run.b) do
		if b.i == encounterID and math.abs((run.t + b.a) - now) < Recorder.KILL_DEDUPE then
			if (b.n == nil or b.n == "") and type(name) == "string" then
				b.n = Util.CleanText(name, 64)
			end
			return nil
		end
	end
	local pull = Recorder.OpenPull(run) or run.p[#run.p]
	local kill = { i = encounterID, n = type(name) == "string" and Util.CleanText(name, 64) or nil, a = math.max(0, now - run.t),
		p = pull and #run.p or nil }
	if pull then
		pull.k = encounterID
	end
	run.b[#run.b + 1] = kill
	run.seen = now
	return kill
end

-- ENCOUNTER_END without success: a wipe on a boss.
function Recorder.BossWipe(run, now)
	if not run then
		return
	end
	local pull = Recorder.OpenPull(run) or run.p[#run.p]
	if pull then
		pull.e = true -- an encounter's attempt, whatever its enemies looked like (RunCompare)
	end
	if pull and not pull.w then
		pull.w = true
		run.w = (run.w or 0) + 1
	end
	run.seen = now
end

-- Archive the current run (it needs at least one pull or kill to be kept). Returns the archived run or nil.
function Recorder.Finish(store, now)
	local run = store.current
	store.current = nil
	if not run then
		return nil
	end
	local open = Recorder.OpenPull(run)
	if open then
		Recorder.PullEnd(run, run.seen or now)
	end
	if #run.p == 0 and #run.b == 0 then
		return nil
	end
	run.e = run.seen or now
	run.done = true
	run.seen = nil
	local list = store.runs[run.k]
	if not list then
		-- A new key when MAX_INSTANCES keys are kept: the key whose newest run is the oldest makes room.
		local n, stale, staleAt = 0, nil, nil
		for k, runs in pairs(store.runs) do
			n = n + 1
			local last = runs[#runs]
			local at = last and (last.e or last.t) or -math.huge
			if not staleAt or at < staleAt or (at == staleAt and k < stale) then
				stale, staleAt = k, at
			end
		end
		if n >= Recorder.MAX_INSTANCES and stale then
			store.runs[stale] = nil
		end
		list = {}
		store.runs[run.k] = list
	end
	list[#list + 1] = run
	while #list > Recorder.MAX_RUNS do
		table.remove(list, 1)
	end
	return run
end

function Recorder.Clear(store, key)
	if key then
		store.runs[key] = nil
	else
		store.runs = {}
		store.current = nil
	end
end

-- Runs of an instance, newest first.
function Recorder.Runs(store, key)
	local out = {}
	local list = store.runs[key] or {}
	for i = #list, 1, -1 do
		out[#out + 1] = list[i]
	end
	return out
end

-- Runs under any of several keys (a wing's and its instance's), newest first.
function Recorder.RunsOf(store, keys)
	local out = {}
	for _, key in ipairs(keys) do
		for _, run in ipairs(store.runs[key] or {}) do
			out[#out + 1] = run
		end
	end
	table.sort(out, function(a, b)
		return a.t > b.t
	end)
	return out
end

-- Summary -----------------------------------------------------------------------------------------------------------------

-- The run's length: until the last boss kill or the end of the last pull, whichever is later.
function Recorder.Duration(run)
	local last = 0
	for _, p in ipairs(run.p) do
		last = math.max(last, p.s + (p.u or 0))
	end
	for _, b in ipairs(run.b) do
		last = math.max(last, b.a)
	end
	return last
end

function Recorder.Summary(run)
	local fight, enemies = 0, 0
	for _, p in ipairs(run.p) do
		fight = fight + (p.u or 0)
		enemies = enemies + (p.c or 0)
	end
	-- Deaths are known only when the client answered for the group at least once; otherwise nil ("not available"),
	-- never a made-up zero.
	local deaths = (run.dk or (run.dd or 0) > 0) and (run.dd or 0) or nil
	return { duration = Recorder.Duration(run), pulls = #run.p, bosses = #run.b, wipes = run.w or 0, deaths = deaths,
		fighting = fight, enemies = enemies }
end

local function bossKey(b)
	return b.i and ("e" .. b.i) or ("n" .. (b.n or ""))
end

-- The finished runs under a key, or under a list of keys (a wing's and its instance's), oldest first.
local function oldestFirst(store, keys)
	if type(keys) ~= "table" then
		return store.runs[keys] or {}
	end
	local out = Recorder.RunsOf(store, keys)
	for i = 1, math.floor(#out / 2) do
		out[i], out[#out + 1 - i] = out[#out + 1 - i], out[i]
	end
	return out
end
Recorder.OldestFirst = oldestFirst

-- Best times over the finished runs of an instance (a key, or a list of keys), split by boss: best[bossKey] = fastest
-- time to that kill, and total = the fastest run that killed at least as many bosses as the most complete run. Also
-- the previous run.
function Recorder.Best(store, keys, except)
	local list = oldestFirst(store, keys)
	local splits, most = {}, 0
	for _, run in ipairs(list) do
		if run ~= except then
			most = math.max(most, #run.b)
			for _, b in ipairs(run.b) do
				local k = bossKey(b)
				if not splits[k] or b.a < splits[k] then
					splits[k] = b.a
				end
			end
		end
	end
	local total, previous, count = nil, nil, 0
	for _, run in ipairs(list) do
		if run ~= except then
			if most > 0 and #run.b >= most then
				local d = Recorder.Duration(run)
				if not total or d < total then
					total = d
				end
			end
			previous = run
			count = count + 1
		end
	end
	return { splits = splits, total = total, previous = previous, runs = count }
end

-- Per boss of a run: time, best split from the other runs (under `keys`, else the run's own key), and the difference
-- (negative = faster).
function Recorder.Splits(store, run, keys)
	local best = Recorder.Best(store, keys or run.k, run)
	local out = {}
	for _, b in ipairs(run.b) do
		local bestA = best.splits[bossKey(b)]
		out[#out + 1] = { name = b.n, encounterID = b.i, at = b.a, best = bestA, delta = bestA and (b.a - bestA) or nil }
	end
	return out, best
end

-- "12:05" or "1:02:05".
function Recorder.FormatTime(seconds)
	seconds = math.floor(math.max(0, tonumber(seconds) or 0) + 0.5)
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- "+0:12" / "-0:40".
function Recorder.FormatDelta(seconds)
	if type(seconds) ~= "number" then
		return ""
	end
	return (seconds < 0 and "-" or "+") .. Recorder.FormatTime(math.abs(seconds))
end

-- Plan from a run ----------------------------------------------------------------------------------------------------------

-- A pull's one-line description: "5 enemies (2 elite), level 14-15". L = the locale table (text from the UI).
function Recorder.PullText(pull, L, plural)
	local parts = { plural(pull.c or 0, L["%d enemy|%d enemies"]) }
	local kinds = {}
	if (pull.el or 0) > 0 then
		kinds[#kinds + 1] = plural(pull.el, L["%d elite|%d elites"])
	end
	if (pull.r or 0) > 0 then
		kinds[#kinds + 1] = plural(pull.r, L["%d rare|%d rares"])
	end
	if (pull.b or 0) > 0 then
		kinds[#kinds + 1] = L["with a boss"]
	end
	if #kinds > 0 then
		parts[1] = parts[1] .. " (" .. table.concat(kinds, ", ") .. ")"
	end
	if pull.lo then
		parts[#parts + 1] = pull.lo == pull.hi and string.format(L["level %d"], pull.lo)
			or string.format(L["level %d-%d"], pull.lo, pull.hi)
	end
	return table.concat(parts, ", ")
end

-- A draft plan (raw, for Validate.Plan) from a recorded run: its pulls in order with their size and make-up in the
-- note, its bosses in kill order with their encounter IDs, no markers (the player places them with the editor).
-- instance = the plan's instance table ({ name, kind, ... }); text = { L, plural, title }.
function Recorder.PlanFromRun(run, instance, text)
	local L, plural = text.L, text.plural
	local plan = {
		name = text.title or string.format(L["Recorded run %s"], text.date or ""),
		instance = Util.DeepCopy(instance or { name = run.n, kind = "dungeon" }),
		floors = { { name = "" } },
		pulls = {},
		encounters = {},
		markers = {},
		routes = {},
		notes = "",
	}
	local killedIn = {}
	for _, b in ipairs(run.b) do
		if b.p then
			killedIn[b.p] = b
		end
	end
	local n = 0
	for i, p in ipairs(run.p) do
		local boss = killedIn[i]
		if not boss then
			n = n + 1
			local note = Recorder.PullText(p, L, plural)
			local extra = {}
			local names = Recorder.PullNames(p)
			if #names > 0 then
				extra[#extra + 1] = table.concat(names, ", ")
			end
			if p.z then
				extra[#extra + 1] = p.z
			end
			extra[#extra + 1] = string.format(L["%s in combat"], Recorder.FormatTime(p.u))
			if p.w then
				extra[#extra + 1] = L["wipe"]
			end
			plan.pulls[#plan.pulls + 1] = { id = "u" .. n, name = string.format(L["Pull %d"], n) .. " (" .. (p.c or 0) .. ")",
				note = note .. ". " .. table.concat(extra, " • ") .. "." }
		end
	end
	for i, b in ipairs(run.b) do
		plan.encounters[#plan.encounters + 1] = { id = "e" .. i, name = b.n or string.format(L["Boss %d"], i),
			dungeonEncounterID = b.i }
	end
	local s = Recorder.Summary(run)
	plan.notes = string.format(L["Drafted from a recorded run: %s, %s, %s, %s. Place the pulls and bosses on the map with the editor."],
		Recorder.FormatTime(s.duration), plural(s.pulls, L["%d pull|%d pulls"]), plural(s.bosses, L["%d boss|%d bosses"]),
		plural(s.wipes, L["%d wipe|%d wipes"]))
	return plan
end
