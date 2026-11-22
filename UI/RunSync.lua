-- Group sync for run mode: the glue between Share/Sync.lua's state machine and the game, plus run mode's sync line.
--
-- * Out: Sync's "send" effects go through Comm.SendSync (the lockdown outbox; a newer state replaces an older one still
--   waiting), "timer" through C_Timer, "focus" selects the matching plan and its step while run mode is open, "offer"
--   shares the plan by whisper (the normal transfer and prompt).
-- * In: Comm hands over R / F / Q / W messages from group members; their rank comes from this client's own roster
--   (Comm.GroupRank). The player's step changes, boss kills, roster changes and plan changes become events.
-- * Display: one line under the plan's name in run mode (who leads, who follows, Unfollow / Rejoin / Ask for it), and
--   the Share section's "Has this plan" line (RunSync.Summary).
-- Nothing runs while nobody leads: no timer, no message; a lead sends only when its step, pull or plan changes.

local _, ns = ...
local RunSync = ns:NewModule("RunSync")
local Sync = ns.Sync
local L = ns.L

RunSync.state = Sync.New()
local applying = false -- set while a "focus" effect moves the step, so it does not read as the player's own move

local function now()
	return ns.Clock()
end

local function shown()
	return ns.RunMode ~= nil and ns.RunMode.IsShown()
end

local function resolve(planId, version)
	return Sync.Resolve(planId, version, ns.DB.GetPlan, ns.db.shareLinks)
end

-- The selected plan as the leader sends it: id, version, step (0 before the first) and the next pull's number.
function RunSync.Position()
	local ctx = ns.UI.ctx
	local plan = ctx:Plan()
	if not plan then
		return nil
	end
	local index = ctx:StepIndex() or 0
	local _, pullStep = ns.Steps.Next(ctx:Steps(), math.max(1, index), "pull")
	local pull = pullStep and ns.Plan.PullIndex(plan, pullStep.pull) or 0
	return { plan = plan.id, version = plan.updated or 0, step = index, pull = pull }
end

local apply

function RunSync.Step(event)
	apply(Sync.Step(RunSync.state, event, now()))
end

local function focus(localId, step)
	if not shown() or not ns.DB.GetPlan(localId) then
		return
	end
	applying = true
	ns.SafeCall(function()
		if ns.db.ui.selectedPlan ~= localId then
			ns.UI.SelectPlan(localId, true)
		end
		if step > 0 then
			ns.UI.FocusStep(step, { stay = true })
		elseif ns.db.ui.step then
			ns.db.ui.step = nil
			ns:Fire("STEP_CHANGED")
		end
	end)
	applying = false
end

local function offer(name, planId)
	local plan = ns.DB.GetPlan(planId)
	if not plan then
		return
	end
	ns:RunOutOfCombat(function()
		if ns.Comm.SharePlan(plan, "WHISPER", name) then
			ns:Print(string.format(L["%s asked for the plan you lead: offered it."], name))
		end
	end)
end

function apply(effects)
	for _, e in ipairs(effects) do
		local kind = e[1]
		if kind == "send" then
			local channel = e[3] == "GROUP" and ns.Comm.GroupChannel() or e[3]
			ns.Comm.SendSync(ns.Transfer.Encode(e[2]), channel, e[4], e[5] .. ":" .. tostring(e[4] or ""))
		elseif kind == "timer" then
			if C_Timer and C_Timer.After then
				C_Timer.After(e[2] + 0.05, function()
					ns.SafeCall(RunSync.Step, { type = "tick" })
				end)
			end
		elseif kind == "focus" then
			focus(e[2], e[3])
		elseif kind == "offer" then
			offer(e[2], e[3])
		elseif kind == "status" then
			ns:Fire("SYNC_CHANGED")
		elseif kind == "refused" then
			ns:Print(L["Only the group's leader or a raid assistant can lead the run."])
		end
	end
end

-- Messages (from Comm.OnMessage, protocol checked): only from players in the group.
function RunSync.OnMessage(msg, sender)
	local rank = ns.Comm.GroupRank(sender)
	if not rank.inGroup then
		return
	end
	local t = msg.type
	if t == "run" then
		local lead = Sync.LeadName(RunSync.state)
		RunSync.Step({ type = "run", from = sender, rank = rank, msg = msg,
			leadRank = lead and ns.Comm.GroupRank(lead) or nil,
			match = msg.plan and resolve(msg.plan, msg.version) or nil })
	elseif t == "follow" then
		RunSync.Step({ type = "report", from = sender, rank = rank, session = msg.session, status = msg.status })
	elseif t == "query" then
		RunSync.Step({ type = "query", from = sender, rank = rank })
	elseif t == "want" then
		RunSync.Step({ type = "want", from = sender, rank = rank, session = msg.session })
	end
end

-- Actions (the sync line's button) ----------------------------------------------------------------------------------------

function RunSync.CanLead()
	return ns.Comm.IsAvailable() and ns.Comm.GroupChannel() ~= nil and Sync.Trusted(ns.Comm.GroupRank())
end

function RunSync.Lead()
	local pos = RunSync.Position()
	if not pos then
		ns:Print(L["Select a plan first."])
		return
	end
	if not ns.Comm.GroupChannel() then
		ns:Print(L["You are not in a group."])
		return
	end
	pos.type, pos.rank, pos.session = "lead", ns.Comm.GroupRank(), ns.Transfer.NewTid()
	RunSync.Step(pos)
end

function RunSync.Act(action)
	if action == "lead" then
		RunSync.Lead()
	elseif action == "stop" then
		RunSync.Step({ type = "stop" })
	elseif action == "unfollow" then
		RunSync.Step({ type = "unfollow" })
	elseif action == "rejoin" then
		RunSync.Step({ type = "rejoin" })
	elseif action == "ask" then
		RunSync.Step({ type = "request" })
	end
end

-- Called by run mode before a boss kill moves its step (RunMode.OnKill).
function RunSync.LocalKill(planId, index)
	RunSync.Step({ type = "localKill", plan = planId, index = index })
end

function RunSync.OnShow()
	RunSync.Step({ type = "show", inGroup = ns.Comm.GroupChannel() ~= nil })
end

-- The leader's view of the group for this plan (nil unless leading it): Sync.Summary over the members and acks.
function RunSync.Summary(plan)
	local s = RunSync.state
	if s.mode ~= "leading" or not plan or plan.id ~= s.plan then
		return nil
	end
	local acks = ns.Comm.PlanStatus(plan)
	return Sync.Summary(s, ns.Comm.GroupMembers(), acks and acks.list)
end

-- The sync line ------------------------------------------------------------------------------------------------------------

-- What the line says: text, dot status, button label and action; nil when there is nothing to show.
function RunSync.LineState(plan)
	local s = RunSync.state
	if s.mode == "leading" then
		local sum = RunSync.Summary(plan) or Sync.Summary(s, ns.Comm.GroupMembers())
		local text = string.format(L["Leading: %d of %d following"], sum.following, sum.total)
		if sum.outOfSync > 0 then
			text = text .. " · " .. string.format(L["out of sync: %d"], sum.outOfSync)
		end
		return { text = text, dot = "ok", button = L["Stop"], action = "stop", summary = sum }
	elseif s.mode == "following" then
		return { text = string.format(L["Following %s"], s.lead.name), dot = "ok", button = L["Unfollow"],
			action = "unfollow" }
	elseif s.mode == "free" then
		return { text = string.format(L["%s leads; you step on your own"], s.lead.name), dot = "dim", button = L["Rejoin"],
			action = "rejoin" }
	elseif s.mode == "mismatch" then
		local asked = s.askedAt and now() - s.askedAt < Sync.ASK_INTERVAL
		local text
		if asked then
			text = string.format(L["Asked %s for the plan: accept it when it comes."], s.lead.name)
		elseif s.why == "missing" then
			text = L["Leader is on a plan you don't have: ask for it"]
		else
			text = L["Leader is on another version of this plan: ask for it"]
		end
		return { text = text, dot = "warning", button = L["Ask for it"], action = "ask", disabled = asked }
	elseif RunSync.CanLead() then
		return { text = L["Lead the group's run mode"], dot = "dim", button = L["Lead this run"], action = "lead" }
	end
	return nil
end

local W, S

local function lineTooltip(self)
	local tt = W.Tip()
	local st = self.dpState
	if not (tt and st) then
		return
	end
	tt:SetOwner(self, "ANCHOR_BOTTOM")
	tt:AddLine(L["Group run"], 1, 0.82, 0)
	if st.summary then
		local STATE = {
			following = L["following"],
			free = L["steps on their own"],
			missing = L["does not have the plan"],
			version = L["has another version"],
			unknown = L["no answer"],
		}
		for _, m in ipairs(st.summary.list) do
			tt:AddDoubleLine(m.name, STATE[m.state] or m.state, 0.93, 0.91, 0.86, 0.71, 0.67, 0.59)
		end
		tt:AddLine(L["Members' run mode shows your step, next pull and boss. No answer: no addon, an older version or a trial account."],
			0.71, 0.67, 0.59, true)
	else
		tt:AddLine(L["While the group's leader leads, your run mode shows their step. Prev or Next to step on your own; Rejoin to follow again."],
			0.71, 0.67, 0.59, true)
	end
	W.TipShow(tt)
end

function RunSync.BuildLine(parent)
	W, S = ns.Widgets, ns.Style
	local SP, SZ = S.SPACE, S.SIZE
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(SZ.control)
	line:EnableMouse(true)
	line.dot = W.Dot(line, "dim")
	line.dot:SetPoint("LEFT")
	line.button = W.Button(line, L["Lead this run"], "outline", function()
		RunSync.Act(line.dpState and line.dpState.action)
	end)
	line.button:SetPoint("RIGHT")
	line.text = W.Text(line, "caption", "ink")
	line.text:SetWordWrap(true)
	if line.text.SetMaxLines then
		line.text:SetMaxLines(2)
	end
	line.text:SetPoint("LEFT", line.dot, "RIGHT", SP.xs, 0)
	line.text:SetPoint("RIGHT", line.button, "LEFT", -SP.sm, 0)
	line:SetScript("OnEnter", lineTooltip)
	line:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	line:Hide()
	return line
end

-- Fill the line for `plan`; returns its height when shown, else 0.
function RunSync.RefreshLine(line, plan)
	local st = RunSync.LineState(plan)
	line.dpState = st
	if not st then
		line:Hide()
		return 0
	end
	line.dot:SetStatus(st.dot)
	line.button:SetLabel(st.button)
	line.button:SetDisabled(st.disabled == true)
	line.text:SetText(st.text)
	S.TextColor(line.text, st.dot == "warning" and "warning" or "ink")
	local h = math.max(S.SIZE.control, math.ceil(line.text:GetStringHeight() or 0))
	line:SetHeight(h)
	line:Show()
	return h
end

-- Events -------------------------------------------------------------------------------------------------------------------

local function rematch()
	local lead = RunSync.state.lead
	if lead then
		RunSync.Step({ type = "resolve", match = resolve(lead.plan, lead.version) })
	end
end

function RunSync.Init()
	ns:On("STEP_CHANGED", RunSync, function()
		if applying then
			return
		end
		local s = RunSync.state
		if s.mode == "leading" then
			local pos = RunSync.Position()
			if pos then
				pos.type = "moved"
				RunSync.Step(pos)
			end
		elseif s.mode == "following" and shown() then
			RunSync.Step({ type = "localStep", plan = ns.db.ui.selectedPlan, index = ns.UI.ctx:StepIndex() or 0 })
		end
	end)
	ns:On("PLAN_CHANGED", RunSync, function(plan)
		local s = RunSync.state
		if s.mode == "leading" then
			if plan and plan.id == s.plan then
				local pos = RunSync.Position()
				if pos and pos.plan == s.plan then
					pos.type = "moved"
					RunSync.Step(pos)
				end
			end
		else
			rematch()
		end
	end)
	ns:On("PLAN_IMPORTED", RunSync, rematch)
	ns:On("PLANS_CHANGED", RunSync, rematch)
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		local lead = Sync.LeadName(RunSync.state)
		RunSync.Step({ type = "roster", inGroup = ns.Comm.GroupChannel() ~= nil, self = ns.Comm.GroupRank(),
			leadRank = lead and ns.Comm.GroupRank(lead) or nil, members = ns.Comm.GroupMembers(), shown = shown() })
	end)
end
