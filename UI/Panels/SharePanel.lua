-- Share tab: export string, import, and sending in game; the Discord text is folded away under "Advanced" at the end of
-- Export (few players need it, and the export string already pastes into Discord); opening it pushes the rest down.
-- Copying uses the pattern big addons use: a read-only box whose text is selected on click, then Ctrl+C (addons cannot
-- touch the clipboard).

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

local Panel = {}
ns.Panels.share = Panel

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)
	local area = W.ScrollArea(f)
	area:SetAllPoints()
	local c = area.content
	f.content = c
	local discordParts, discordIndex = {}, 1
	local discordOpts = { mode = "full", includeString = true }

	local function plan()
		return ctx:Plan()
	end

	-- Layout helpers: each places its frame at the running offset y of its parent (`into`).
	local y = 0
	local into = c
	-- A section heading on the header band, as the other sections head their columns.
	local function section(title)
		local fs = W.Heading(into, title, nil, true)
		fs:SetPoint("TOPLEFT", SP.xs, -(y + 4))
		y = y + 20 + SP.md
		return fs
	end
	local function row(h)
		local top = y
		y = y + h + SP.md
		return -top
	end
	-- A hint under a control: wraps onto two lines as wide as the section.
	local function hint(text)
		local fs = W.Paragraph(into, "caption", "muted")
		fs:SetPoint("TOPLEFT", 0, row(28))
		fs:SetPoint("RIGHT", into, "RIGHT", -SP.sm, 0)
		fs:SetText(text)
		return fs
	end

	-- Export ------------------------------------------------------------------------------------------------------------
	section(L["Export"])
	local top = row(SZ.control)
	c.exportPlan = W.Button(c, L["Export this plan"], "outline", function()
		local text, err = ns.Codec.ExportPlan(plan())
		c.exportBox:SetValue(text or ("Error: " .. tostring(err)))
		c.exportBox.edit:SetFocus()
	end)
	c.exportPlan:SetPoint("TOPLEFT", 0, top)
	c.exportPlan.dpGround = "surface"
	c.exportPack = W.Button(c, L["Export all plans of this instance"], "outline", function()
		local p = plan()
		-- Every own plan of the same instance, whatever language or key it was saved under (Bundled.SameInstance).
		local plans = ns.DB.PlansFor(ns.UI.EntryForPlan(p))
		local text, err = ns.Codec.ExportPack(ns.Names.Instance(p.instance), "", plans)
		c.exportBox:SetValue(text or ("Error: " .. tostring(err)))
		c.exportBox.edit:SetFocus()
	end)
	c.exportPack:SetPoint("LEFT", c.exportPlan, "RIGHT", SP.sm, 0)
	c.exportPack.dpGround = "surface"
	c.exportBox = W.MultiLine(c, { readOnly = true, maxBytes = 0 })
	c.exportBox:SetPoint("TOPLEFT", 0, row(64))
	c.exportBox:SetPoint("RIGHT", c, "RIGHT", -SP.sm, 0)
	c.exportBox:SetHeight(64)
	hint(L["Click the box, then press Ctrl+C to copy. Paste it anywhere: chat, a forum, Discord, or the community plans repository."])
	-- Advanced: the Discord text, folded away ------------------------------------------------------------------------------
	c.advanced = W.Disclosure(c, L["Advanced"], function(open)
		ns.db.ui.shareAdvanced = open
		f:Layout()
	end)
	c.advanced:SetPoint("TOPLEFT", 0, row(SZ.small))
	y = y + SP.xs
	W.SetTooltip(c.advanced, L["Advanced"], L["The plan as Discord messages."])
	local baseHeight = y

	local adv = CreateFrame("Frame", nil, c)
	adv:SetPoint("TOPLEFT", 0, -y)
	adv:SetPoint("RIGHT", c, "RIGHT")
	c.discord, f.discord = adv, adv
	into, y = adv, 0
	section(L["Discord"])
	top = row(SZ.control)
	adv.mode = W.Dropdown(adv, {
		width = 160,
		options = function()
			return { { text = L["Full plan"], value = "full" }, { text = L["Summary"], value = "summary" },
				{ text = L["Run summary"], value = "run" } }
		end,
		get = function()
			return discordOpts.mode
		end,
		set = function(v)
			discordOpts.mode = v
		end,
	})
	adv.mode:SetPoint("TOPLEFT", 0, top)
	adv.includeString = W.Check(adv, L["Include the import string"], function(v)
		discordOpts.includeString = v
	end)
	adv.includeString:SetPoint("LEFT", adv.mode, "RIGHT", SP.md, 0)
	adv.includeString:SetChecked(true)
	adv.make = W.Button(adv, L["Create Discord text"], "outline", function()
		local p = plan()
		local opts = { mode = discordOpts.mode, version = ns.version }
		if discordOpts.mode == "run" then
			discordParts = f:RunParts(p, opts)
			discordIndex = 1
			f:ShowDiscordPart()
			return
		end
		if discordOpts.includeString then
			opts.importString = ns.Codec.ExportPlan(p)
		end
		discordParts = ns.Discord.Render(p, opts)
		discordIndex = 1
		f:ShowDiscordPart()
	end)
	adv.make:SetPoint("LEFT", adv.includeString, "RIGHT", SP.md, 0)
	adv.make.dpGround = "surface"

	top = row(SZ.control)
	adv.partPrev = W.IconButton(adv, "<", L["Previous part"], function()
		discordIndex = math.max(1, discordIndex - 1)
		f:ShowDiscordPart()
	end)
	adv.partPrev:SetPoint("TOPLEFT", 0, top - 2)
	adv.partText = W.Text(adv, "body", "muted")
	adv.partText:SetPoint("LEFT", adv.partPrev, "RIGHT", SP.sm, 0)
	adv.partNext = W.IconButton(adv, ">", L["Next part"], function()
		discordIndex = math.min(#discordParts, discordIndex + 1)
		f:ShowDiscordPart()
	end)
	adv.partNext:SetPoint("LEFT", adv.partText, "RIGHT", SP.sm, 0)
	adv.box = W.MultiLine(adv, { readOnly = true, maxBytes = 0 })
	adv.box:SetPoint("TOPLEFT", 0, row(140))
	adv.box:SetPoint("RIGHT", adv, "RIGHT", -SP.sm, 0)
	adv.box:SetHeight(140)
	hint(L["Each part fits one Discord message (2000 characters). Copy a part with Ctrl+C, paste it in Discord, then take the next part."])
	adv:SetHeight(y)
	local advHeight = y

	-- Import and Send in game: under Advanced, or under the Discord part while it is open (f:Layout).
	local rest = CreateFrame("Frame", nil, c)
	rest:SetPoint("RIGHT", c, "RIGHT")
	c.rest = rest
	into, y = rest, 0

	-- Import ------------------------------------------------------------------------------------------------------------
	section(L["Import"])
	c.importBox = W.MultiLine(rest, { maxBytes = 0 })
	c.importBox:SetPoint("TOPLEFT", 0, row(64))
	c.importBox:SetPoint("RIGHT", rest, "RIGHT", -SP.sm, 0)
	c.importBox:SetHeight(64)
	top = row(SZ.control)
	c.import = W.Button(rest, L["Import"], "soft", function()
		-- A plan named like one of yours asks first: keep both, or replace yours (UI.ImportWithConfirm).
		ns.UI.ImportWithConfirm(c.importBox:GetValue(), { kind = "import" }, function(ok, message)
			c.importResult:SetText(ok and message or (L["Could not import:"] .. " " .. tostring(message)))
			if ok then
				c.importBox:SetValue("")
			end
		end)
	end)
	c.import:SetPoint("TOPLEFT", 0, top)
	c.importResult = W.Paragraph(rest, "body", "muted")
	c.importResult:SetPoint("LEFT", c.import, "RIGHT", SP.md, 0)
	c.importResult:SetPoint("RIGHT", rest, "RIGHT", -SP.sm, 0)
	hint(L["Paste a plan or pack string (several Discord pieces too). A plan named like one of yours asks before replacing it."])
	y = y + SP.md

	-- Send in-game --------------------------------------------------------------------------------------------------------
	section(L["Send in game"])
	top = row(SZ.control)
	c.sendGroup = W.Button(rest, L["Send to group"], "outline", function()
		f:Send("GROUP")
	end)
	c.sendGroup:SetPoint("TOPLEFT", 0, top)
	c.sendGroup.dpGround = "surface"
	c.sendGuild = W.Button(rest, L["Send to guild"], "outline", function()
		f:Send("GUILD")
	end)
	c.sendGuild:SetPoint("LEFT", c.sendGroup, "RIGHT", SP.sm, 0)
	c.sendGuild.dpGround = "surface"
	c.whisper = W.Input(rest, { width = 160, maxBytes = 48, placeholder = L["Player name"] })
	c.whisper:SetPoint("LEFT", c.sendGuild, "RIGHT", SP.md, 0)
	c.sendWhisper = W.Button(rest, L["Send"], "outline", function()
		f:Send("WHISPER", c.whisper:GetValue())
	end)
	c.sendWhisper:SetPoint("LEFT", c.whisper, "RIGHT", SP.sm, 0)
	c.sendWhisper.dpGround = "surface"
	c.peers = W.Text(rest, "caption", "muted")
	c.peers:SetPoint("TOPLEFT", 0, row(16))
	-- Who in the group has this plan (Share/Acks.lua): a line, and each member in its tooltip.
	local track = CreateFrame("Button", nil, rest)
	track:SetPoint("TOPLEFT", 0, row(16))
	track:SetPoint("RIGHT", rest, "RIGHT", -SP.sm, 0)
	track:SetHeight(16)
	track.text = W.Text(track, "caption", "ink")
	track.text:SetPoint("LEFT")
	track.text:SetPoint("RIGHT")
	track:SetScript("OnEnter", function(self)
		local tt = W.Tip()
		if not (tt and self.status) then
			return
		end
		tt:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		tt:AddLine(L["Who has this plan"], 1, 0.82, 0)
		local STATE = {
			current = L["has this version"],
			outdated = L["has an older version"],
			missing = L["not yet"],
			unknown = L["unknown"],
		}
		-- While you lead this plan's run (UI/RunSync.lua): who follows, who steps on their own, who is out of sync.
		local SYNC = { following = L["following"], free = L["steps on their own"], missing = L["out of sync"],
			version = L["out of sync"] }
		local sync = {}
		for _, m in ipairs(self.sync and self.sync.list or {}) do
			sync[m.name] = SYNC[m.state]
		end
		for _, m in ipairs(self.status.list) do
			local state = STATE[m.state] or m.state
			if sync[m.name] then
				state = state .. "  •  " .. sync[m.name]
			end
			tt:AddDoubleLine(m.name, state, 0.93, 0.91, 0.86, 0.71, 0.67, 0.59)
		end
		tt:AddLine(
			L["From the reply a player's Dungeon Planner sends after importing your plan. Unknown: no reply can come (no addon, other client, trial account)."],
			0.71, 0.67, 0.59, true)
		W.TipShow(tt)
	end)
	track:SetScript("OnLeave", function(self)
		local tt = W.Tip()
		if tt and tt:IsOwned(self) then
			tt:Hide()
		end
	end)
	c.track = track
	c.status = W.Paragraph(rest, "body", "muted")
	c.status:SetPoint("TOPLEFT", 0, row(40))
	c.status:SetPoint("RIGHT", rest, "RIGHT", -SP.sm, 0)
	y = y + SP.md
	local restHeight = y
	rest:SetHeight(restHeight)

	-- Older names (tests, skins).
	c.discordMode, c.discordString, c.discordMake, c.discordBox = adv.mode, adv.includeString, adv.make, adv.box
	c.partPrev, c.partText, c.partNext = adv.partPrev, adv.partText, adv.partNext

	function f:Layout()
		-- The content is as wide as the scroll area (the hints wrap to it), also before the area reports its size.
		c:SetWidth(math.max(10, (area:GetWidth() or 0) - SP.md))
		local open = ns.db.ui.shareAdvanced == true
		c.advanced:SetOpen(open)
		adv:SetShown(open)
		rest:ClearAllPoints()
		rest:SetPoint("TOPLEFT", 0, -(baseHeight + (open and advHeight or 0) + SP.md))
		rest:SetPoint("RIGHT", c, "RIGHT")
		area:SetContentHeight(baseHeight + (open and advHeight or 0) + SP.md + restHeight + SP.lg)
	end

	-- A recorded run against the plan: the run chosen in the Runs section, else this instance's latest, a run of the
	-- plan's own wing before one whose wing is not known. A run whose wing is not known says so in the text.
	function f:RunParts(p, opts)
		local R = ns.Recorder
		local st = R.Store()
		local run = ctx.selectedRun
		if not R.RunMatchesPlan(run, p) then
			local runs = R.RunsForPlan(p)
			run = runs[1]
			for _, r in ipairs(runs) do
				if not R.WingUnknown(r, p) then
					run = r
					break
				end
			end
		end
		if not run then
			-- Like the Runs section's empty pane: the turn-on hint only while recording is off.
			if R.Enabled() then
				return { L["No recorded run of this instance yet. Recording is on: your next run here can be shared."] }
			end
			return { L["No recorded run of this instance yet. Turn on \"Record my runs\" in the Runs section."] }
		end
		local Runs = ns.Panels.runs
		local splits = ns.RunCompare.Splits(st, run, R.KeysForPlan(p))
		local when = date and date("%Y-%m-%d %H:%M", run.t) or nil
		if R.WingUnknown(run, p) then
			when = (when and (when .. " ") or "") .. "(" .. L["wing unknown"] .. ")"
		end
		return ns.Discord.RenderRun(p, run, {
			overlay = Runs.Overlay(p, run),
			splits = splits,
			date = when,
			bossName = function(encId)
				local enc = ns.Util.FindById(p.encounters, encId)
				return enc and ns.Names.Encounter(enc) or "?"
			end,
		}, opts)
	end

	function f:ShowDiscordPart()
		local n = #discordParts
		if n == 0 then
			adv.partText:SetText(L["No text yet"])
			adv.box:SetValue("")
		else
			adv.partText:SetText(string.format(L["Part %d of %d (%s)"], discordIndex, n,
				ns.Plural(#discordParts[discordIndex], L["%d character|%d characters"])))
			adv.box:SetValue(discordParts[discordIndex])
			adv.box.edit:SetFocus()
		end
		adv.partPrev:SetDisabled(discordIndex <= 1)
		adv.partNext:SetDisabled(discordIndex >= n)
	end

	function f:Send(channel, target)
		local p = plan()
		if not p then
			return
		end
		ns:RunOutOfCombat(function()
			local transfer, err = ns.Comm.SharePlan(p, channel, target)
			if not transfer then
				c.status:SetText(tostring(err))
			end
		end)
	end

	local STATE_TEXT = {
		offering = "waiting for answers",
		sending = "sending",
		done = "sent",
		declined = "declined",
		expired = "nobody accepted",
		cancelled = "cancelled",
		receiving = "receiving",
		failed = "failed",
	}
	-- A transfer's state, with the cause when the outbox had no room for it or the game refused it (Share/Comm.lua).
	local function stateText(t)
		if t.state == "failed" and t.reason == "outbox" then
			return L["failed: too many messages were waiting for a boss fight to end"]
		elseif t.state == "failed" and t.reason == "refused" then
			return L["failed: the game refused the message"]
		end
		return L[STATE_TEXT[t.state] or t.state]
	end

	function f:RefreshStatus()
		local lines = {}
		-- The game holds or refuses addon messages: say so first, so a share that goes nowhere is not silent.
		local problem = ns.Comm.ProblemText()
		if problem then
			lines[1] = problem
		end
		for _, t in pairs(ns.Comm.outgoing) do
			local who = t.target or t.channel
			local text = string.format(L["\"%s\" to %s: %s"], t.name, who, stateText(t))
			if t.state == "offering" and t.acceptCount > 0 then
				text = text .. " (" .. string.format(L["%d accepted"], t.acceptCount) .. ")"
			elseif t.state == "sending" and t.total then
				text = text .. string.format(" (%d%%)", math.floor(100 * (t.sent or 0) / math.max(1, t.total)))
			end
			lines[#lines + 1] = text
		end
		for _, t in pairs(ns.Comm.incoming) do
			if t.state ~= "prompt" then
				lines[#lines + 1] = string.format(L["\"%s\" from %s: %s"], t.name, t.sender, stateText(t))
			end
		end
		c.status:SetText(table.concat(lines, "\n"))
		-- Who has this plan, while in a group.
		local status = ns.Comm.GroupChannel() and ns.Comm.PlanStatus(plan()) or nil
		if status and status.total > 0 then
			local text = string.format(L["Has this plan: %d of %s, outdated: %d"], status.has,
				ns.Plural(status.total, L["%d group member|%d group members"]),
				status.outdated)
			if status.unknown > 0 then
				text = text .. ", " .. string.format(L["unknown: %d"], status.unknown)
			end
			-- Leading this plan's run: who follows it and who is out of sync.
			local sync = ns.RunSync.Summary(plan())
			if sync then
				text = text .. "; " .. string.format(L["following: %d"], sync.following)
				if sync.outOfSync > 0 then
					text = text .. ", " .. string.format(L["out of sync: %d"], sync.outOfSync)
				end
			end
			W.FitText(c.track.text, text)
			c.track.status, c.track.sync = status, sync
		else
			c.track.text:SetText("")
			c.track.status, c.track.sync = nil, nil
		end
		local n = ns.Comm.PeerCount()
		c.peers:SetText(n > 0 and ns.Plural(n,
			L["%d player in your group or guild runs Dungeon Planner.|%d players in your group or guild run Dungeon Planner."]) or "")
	end

	ns:On("SHARE_STATUS", f, function()
		if f:IsVisible() then
			f:RefreshStatus()
		end
	end)
	ns:On("SHARE_ACKS", f, function()
		if f:IsVisible() then
			f:RefreshStatus()
		end
	end)
	ns:On("SHARE_PEERS", f, function()
		if f:IsVisible() then
			f:RefreshStatus()
		end
	end)
	-- Also when the game starts or stops holding or refusing addon messages (UI/RunSync.lua passes COMM_STATE on).
	ns:On("SYNC_CHANGED", f, function()
		if f:IsVisible() then
			f:RefreshStatus()
		end
	end)

	function f:Refresh()
		local available = ns.Comm.IsAvailable()
		c.sendGroup:SetDisabled(not available or ns.Comm.GroupChannel() == nil)
		c.sendGuild:SetDisabled(not available or not (IsInGuild and IsInGuild()))
		c.sendWhisper:SetDisabled(not available)
		c.import:SetDisabled(ctx:ReadOnly())
		f:Layout()
		f:ShowDiscordPart()
		f:RefreshStatus()
	end
	return f
end
