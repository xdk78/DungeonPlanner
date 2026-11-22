-- RunCompare: a recorded run against its plan, two runs side by side, and the live drift from the plan. Pure Lua 5.1
-- over Model/RunLog.lua's runs and Model/Steps.lua's steps; no game API (the caller passes how a boss's game ID and
-- display name are found).
--
-- What a run can tell (docs/COMPATIBILITY.md section 10): its pulls in order (combat segments with their size, elites
-- and timing), its boss kills and wipes. What it cannot tell: which pack a pull was (no positions, creature identity
-- is secret), so planned and actual pulls are paired by order between two boss kills, never by place. A pull in which
-- a boss-level enemy was seen and the group wiped is a boss attempt, not trash.
--
-- The plan's side, from its steps (route order): trash pulls grouped by the boss that ends them. A pull tagged "skip"
-- is a planned skip (not counted); a pull tagged "next" is pulled together with the one after it (one planned pull).
--
--   segment = { boss = plan encounter id or nil (after the last boss), planned = { entry, ... },
--               actual = { { pull = run pull, index = n }, ... }, kill = run kill or nil, attempts = n,
--               rows = { { kind = "pair" | "extra" | "skipped", planned = entry?, actual = { pull, index }? }, ... },
--               delta = #actual - #planned, state = "done" | "current" | "ahead" }
--   entry   = { pulls = { plan pull, ... }, step = index of its first step }

local _, ns = ...
local RunCompare = ns:NewModule("RunCompare")
local RunLog = ns.RunLog

local NONE = {}

local function hasTag(pull, tag)
	for _, t in ipairs(pull.tags or NONE) do
		if t == tag then
			return true
		end
	end
	return false
end

local function norm(s)
	return ns.Match.Norm(s or "")
end

-- opts = { idOf = function(enc) -> dungeonEncounterID?, nameOf = function(enc) -> name }
local function options(opts)
	opts = opts or {}
	return {
		idOf = opts.idOf or function(enc)
			return enc.dungeonEncounterID
		end,
		nameOf = opts.nameOf or function(enc)
			return enc.name
		end,
	}
end

-- The plan's planned sequence: segments of trash entries, each ended by a boss (in step order), and a last segment
-- without a boss when pulls follow the last boss. steps = Steps.Build(plan) (or nil: pull order, then the bosses).
function RunCompare.PlanSequence(plan, steps)
	local pullsById = {}
	for _, p in ipairs(plan.pulls or NONE) do
		pullsById[p.id] = p
	end
	if not steps then
		steps = {}
		for _, p in ipairs(plan.pulls or NONE) do
			steps[#steps + 1] = { kind = "pull", pull = p.id }
		end
		for _, e in ipairs(plan.encounters or NONE) do
			steps[#steps + 1] = { kind = "boss", encounter = e.id }
		end
	end
	local segments, bossOrder, seenBoss, seenPull = {}, {}, {}, {}
	local current = { planned = {} }
	local merging = false
	for i, step in ipairs(steps) do
		if step.kind == "pull" and pullsById[step.pull] and not seenPull[step.pull] then
			seenPull[step.pull] = true
			local pull = pullsById[step.pull]
			if not hasTag(pull, "skip") then
				local last = current.planned[#current.planned]
				if merging and last then
					last.pulls[#last.pulls + 1] = pull
				else
					current.planned[#current.planned + 1] = { pulls = { pull }, step = i }
				end
				merging = hasTag(pull, "next")
			end
		elseif step.kind == "boss" and step.encounter and not seenBoss[step.encounter] then
			seenBoss[step.encounter] = true
			current.boss, current.step = step.encounter, i
			segments[#segments + 1] = current
			bossOrder[#bossOrder + 1] = step.encounter
			current = { planned = {} }
			merging = false
		end
	end
	if #current.planned > 0 then
		segments[#segments + 1] = current
	end
	local total = 0
	for _, seg in ipairs(segments) do
		total = total + #seg.planned
	end
	return { segments = segments, bosses = bossOrder, total = total }
end

-- The plan encounter a recorded kill is: by game ID, else by name. nil for a boss the plan does not have.
function RunCompare.MatchKill(plan, kill, opts)
	opts = options(opts)
	for _, enc in ipairs(plan.encounters or NONE) do
		local id = opts.idOf(enc)
		if id and kill.i and id == kill.i then
			return enc.id
		end
	end
	local want = norm(kill.n)
	if want ~= "" then
		for _, enc in ipairs(plan.encounters or NONE) do
			if norm(opts.nameOf(enc)) == want or norm(enc.name) == want then
				return enc.id
			end
		end
	end
	return nil
end

-- A boss attempt that failed: a wipe the game reported as a failed encounter (pull.e, RunLog.BossWipe), or, for runs
-- recorded before that mark, a wipe while a boss-level enemy was seen. Many bosses are plain elites.
local function isBossAttempt(p)
	return p.w and (p.e == true or (p.b or 0) > 0)
end

-- The run's actual sequence: segments of trash pulls, each ended by a boss kill (in kill order), and the trash after
-- the last kill. match(kill) -> plan encounter id or nil (nil without a plan). Returns segments
-- { kill?, enc?, actual = { { pull, index } }, attempts }, and the open pull when it is trash.
function RunCompare.RunSequence(run, match)
	local killsAt, loose = {}, {}
	for _, b in ipairs(run.b or NONE) do
		if b.p and run.p[b.p] then
			killsAt[b.p] = killsAt[b.p] or {}
			table.insert(killsAt[b.p], b)
		else
			loose[#loose + 1] = b
		end
	end
	table.sort(loose, function(x, y)
		return (x.a or 0) < (y.a or 0)
	end)
	local segments = {}
	local current = { actual = {}, attempts = 0 }
	local function close(kill)
		current.kill = kill
		current.enc = match and match(kill) or nil
		segments[#segments + 1] = current
		current = { actual = {}, attempts = 0 }
	end
	local nextLoose = 1
	local open = RunLog.OpenPull(run)
	for i, p in ipairs(run.p or NONE) do
		while loose[nextLoose] and (loose[nextLoose].a or 0) <= (p.s or 0) do
			close(loose[nextLoose])
			nextLoose = nextLoose + 1
		end
		if killsAt[i] then
			for _, kill in ipairs(killsAt[i]) do
				close(kill)
			end
		elseif isBossAttempt(p) then
			current.attempts = current.attempts + 1
		elseif p ~= open then
			current.actual[#current.actual + 1] = { pull = p, index = i }
		end
	end
	for k = nextLoose, #loose do
		close(loose[k])
	end
	local tail = current
	return segments, tail, open and not killsAt[#run.p] and open or nil
end

local function pairRows(planned, actual)
	local rows = {}
	for i = 1, math.max(#planned, #actual) do
		local p, a = planned[i], actual[i]
		rows[#rows + 1] = { kind = (p and a) and "pair" or (a and "extra" or "skipped"), planned = p, actual = a }
	end
	return rows
end

-- The run against the plan. Segments come in the plan's boss order; a kill the plan does not have adds a segment of
-- its own at the end. The trash after the run's last kill is compared with the first boss not yet killed (the boss
-- the run was heading for), else with the plan's pulls after its last boss.
-- Returns { segments, planned, actual, bossesPlanned, bossesKilled, divergences, next = segment heading for or nil }.
-- divergence = { kind = "extra" | "skipped", boss?, n } | { kind = "order", boss, before } | { kind = "unplanned",
-- name?, id? } | { kind = "notReached", boss }
function RunCompare.Overlay(plan, run, steps, opts)
	local seq = RunCompare.PlanSequence(plan, steps)
	local actualSegs, tail, open = RunCompare.RunSequence(run, function(kill)
		return RunCompare.MatchKill(plan, kill, opts)
	end)
	local byBoss, killed, order = {}, {}, {}
	for i, encId in ipairs(seq.bosses) do
		order[encId] = i
	end
	local out = { segments = {}, divergences = {}, planned = seq.total, actual = 0, bossesPlanned = #seq.bosses,
		bossesKilled = 0 }
	local unplanned = {}
	for _, seg in ipairs(actualSegs) do
		out.actual = out.actual + #seg.actual
		if seg.enc and not byBoss[seg.enc] then
			byBoss[seg.enc] = seg
		else
			unplanned[#unplanned + 1] = seg
		end
	end
	out.actual = out.actual + #tail.actual

	-- Boss order: a kill before an earlier planned boss that is still alive.
	for _, seg in ipairs(actualSegs) do
		if seg.enc and order[seg.enc] then
			for j = 1, order[seg.enc] - 1 do
				local earlier = seq.bosses[j]
				if not killed[earlier] then
					out.divergences[#out.divergences + 1] = { kind = "order", boss = seg.enc, before = earlier }
					break
				end
			end
			if not killed[seg.enc] then
				killed[seg.enc] = true
				out.bossesKilled = out.bossesKilled + 1
			end
		elseif seg.kill then
			out.divergences[#out.divergences + 1] = { kind = "unplanned", name = seg.kill.n, id = seg.kill.i }
		end
	end

	local headingFor
	for _, planned in ipairs(seq.segments) do
		local actualSeg = planned.boss and byBoss[planned.boss]
		local seg = { boss = planned.boss, planned = planned.planned, step = planned.step }
		if actualSeg then
			seg.actual, seg.kill, seg.attempts, seg.state = actualSeg.actual, actualSeg.kill, actualSeg.attempts, "done"
		elseif not headingFor then
			headingFor = seg
			seg.actual, seg.attempts, seg.state = tail.actual, tail.attempts, "current"
		else
			seg.actual, seg.attempts, seg.state = {}, 0, "ahead"
		end
		seg.rows = pairRows(seg.planned, seg.actual)
		seg.delta = #seg.actual - #seg.planned
		out.segments[#out.segments + 1] = seg
	end
	if not headingFor and #tail.actual > 0 then
		-- Every planned boss is down (or the plan has none): trash after them that the plan does not list.
		local seg = { planned = {}, actual = tail.actual, attempts = tail.attempts, state = "current" }
		seg.rows, seg.delta = pairRows(seg.planned, seg.actual), #seg.actual
		out.segments[#out.segments + 1] = seg
		headingFor = seg
	end
	for _, extra in ipairs(unplanned) do
		local seg = { planned = {}, actual = extra.actual, kill = extra.kill, attempts = extra.attempts, state = "done",
			unplanned = true }
		seg.rows, seg.delta = pairRows(seg.planned, seg.actual), #seg.actual
		out.segments[#out.segments + 1] = seg
	end
	out.next = headingFor
	out.open = open

	for _, seg in ipairs(out.segments) do
		-- Fewer pulls than planned counts only for a stretch the run has finished (a killed boss, or a finished run).
		if seg.delta > 0 and not seg.unplanned then
			out.divergences[#out.divergences + 1] = { kind = "extra", boss = seg.boss, n = seg.delta }
		elseif seg.delta < 0 and (seg.state == "done" or (run.done and seg.state == "current")) then
			out.divergences[#out.divergences + 1] = { kind = "skipped", boss = seg.boss, n = -seg.delta }
		end
		if run.done and seg.boss and seg.state ~= "done" then
			out.divergences[#out.divergences + 1] = { kind = "notReached", boss = seg.boss }
		end
	end
	return out
end

-- Live progress against the plan while a run is recorded: trash pulls done and planned, the stretch the run is in
-- (pulls since the last kill against the pulls planned before the boss it is heading for), the step the run is
-- probably at, and warnings. steps = Steps.Build(plan).
-- Returns { pullsDone, pullsPlanned, since, sincePlanned, nextBoss?, step?, inCombat, warnings = { ... } }
-- warning = { kind = "extra", boss?, n } | { kind = "order", boss, before }
function RunCompare.Drift(plan, run, steps, opts)
	local ov = RunCompare.Overlay(plan, run, steps, opts)
	local seg = ov.next
	local out = { pullsDone = ov.actual, pullsPlanned = ov.planned, warnings = {}, inCombat = ov.open ~= nil }
	out.since = seg and #seg.actual or 0
	out.sincePlanned = seg and #seg.planned or 0
	out.nextBoss = seg and seg.boss or nil
	if seg and out.since > out.sincePlanned then
		out.warnings[#out.warnings + 1] = { kind = "extra", boss = seg.boss, n = out.since - out.sincePlanned }
	end
	-- Only the latest kill can be "out of order" now; an earlier one was already said.
	local lastKill = run.b and run.b[#run.b]
	if lastKill then
		local enc = RunCompare.MatchKill(plan, lastKill, opts)
		for _, d in ipairs(ov.divergences) do
			if d.kind == "order" and d.boss == enc then
				out.warnings[#out.warnings + 1] = d
			end
		end
	end
	-- The step: the next planned pull of the stretch, or its boss once the stretch's pulls are done.
	if steps and #steps > 0 then
		if seg and seg.planned[out.since + 1] then
			out.step = seg.planned[out.since + 1].step
		elseif seg and seg.step then
			out.step = seg.step
		elseif not seg then
			out.step = #steps
		end
	end
	return out
end

-- Runs of the same instance --------------------------------------------------------------------------------------------

-- The run before `run` (by start time) among the store's runs under `keys` (a list: a wing's and its instance's), else
-- under the run's own key, or nil.
function RunCompare.Previous(store, run, keys)
	local best
	for _, r in ipairs(RunLog.OldestFirst(store, keys or run.k)) do
		if r ~= run and r.t < run.t and (not best or r.t > best.t) then
			best = r
		end
	end
	return best
end

local function bossKey(b)
	return b.i and ("e" .. b.i) or ("n" .. norm(b.n))
end
RunCompare.BossKey = bossKey

-- Per boss of `run`: time, best split of the other runs (under `keys`, as Previous), the previous run's time, and both
-- differences.
function RunCompare.Splits(store, run, keys)
	local splits, best = RunLog.Splits(store, run, keys)
	local prev = RunCompare.Previous(store, run, keys)
	local prevAt = {}
	for _, b in ipairs(prev and prev.b or NONE) do
		prevAt[bossKey(b)] = prevAt[bossKey(b)] or b.a
	end
	for i, sp in ipairs(splits) do
		local b = run.b[i]
		sp.prev = prevAt[bossKey(b)]
		sp.prevDelta = sp.prev and (sp.at - sp.prev) or nil
	end
	return splits, best, prev
end

-- Two runs side by side: { summary = { { id, a, b, delta } }, bosses = { { name, a?, b?, delta? } },
-- stretches = { { name?, a, b, delta } } (trash pulls before each boss, then after the last). Values are numbers; nil
-- where a run does not have it (deaths the client could not read, a boss one run did not kill).
function RunCompare.Pair(a, b)
	local sa, sb = RunLog.Summary(a), RunLog.Summary(b)
	local function row(id)
		local x, y = sa[id], sb[id]
		return { id = id, a = x, b = y, delta = (x and y) and (x - y) or nil }
	end
	local out = { summary = { row("duration"), row("pulls"), row("bosses"), row("wipes"), row("deaths"), row("fighting"),
		row("enemies") }, bosses = {}, stretches = {} }
	local index, order = {}, {}
	local function addBoss(kill, side)
		local key = bossKey(kill)
		local r = index[key]
		if not r then
			r = { name = kill.n }
			index[key] = r
			order[#order + 1] = r
		end
		r.name = r.name or kill.n
		if r[side] == nil then
			r[side] = kill.a
		end
		return r
	end
	for _, kill in ipairs(a.b or NONE) do
		addBoss(kill, "a")
	end
	for _, kill in ipairs(b.b or NONE) do
		addBoss(kill, "b")
	end
	for _, r in ipairs(order) do
		r.delta = (r.a and r.b) and (r.a - r.b) or nil
		out.bosses[#out.bosses + 1] = r
	end
	-- Trash pulls per stretch, keyed by the boss that ends it.
	local segA, tailA = RunCompare.RunSequence(a)
	local segB, tailB = RunCompare.RunSequence(b)
	local stretch, sorder = {}, {}
	local function addStretch(seg, side)
		local key = seg.kill and bossKey(seg.kill) or "tail"
		local r = stretch[key]
		if not r then
			r = { name = seg.kill and seg.kill.n, a = 0, b = 0 }
			stretch[key] = r
			sorder[#sorder + 1] = r
		end
		r[side] = r[side] + #seg.actual
	end
	for _, seg in ipairs(segA) do
		addStretch(seg, "a")
	end
	for _, seg in ipairs(segB) do
		addStretch(seg, "b")
	end
	if #tailA.actual + #tailB.actual > 0 then
		addStretch(tailA, "a")
		addStretch(tailB, "b")
	end
	for _, r in ipairs(sorder) do
		r.delta = r.a - r.b
		out.stretches[#out.stretches + 1] = r
	end
	return out
end
