-- The "Report a problem" window (/dp report, the ! button in the main window's title bar): the report text of
-- Core/Report.lua in a read-only box that selects everything for Ctrl+C, a "What happened?" field that goes into it, and
-- the GitHub new-issue link to copy (the game cannot open links). A plain window: building it and showing it is allowed
-- in combat, and nothing runs while it is closed.

local _, ns = ...
local ReportFrame = ns:NewModule("ReportFrame")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP = S.SPACE
local Report = ns.Report

local MIN_W, MIN_H = 480, 460
local frame
local data -- the collected facts (Report.Collect), refreshed on open and with the Refresh button

local function saved()
	ns.db.ui.report = type(ns.db.ui.report) == "table" and ns.db.ui.report or {}
	return ns.db.ui.report
end

-- Put the report and the link into their boxes (cheap: the facts are collected once per open).
function ReportFrame.Update()
	if not frame or not data then
		return
	end
	local what = frame.what:GetValue()
	frame.report:SetValue(Report.Text(data, what, frame.short:GetChecked() and { limit = Report.DISCORD_LIMIT } or nil))
	frame.link:SetValue(Report.IssueURL(data, what))
end

local function selectAll(box)
	box.edit:SetFocus()
	box.edit:HighlightText()
end

local function build()
	local s = saved()
	s.width, s.height = s.width or 560, s.height or 580
	local f = W.Window("DungeonPlannerReportFrame", L["Report a problem"], s, MIN_W, MIN_H, { compact = true })
	f:SetFrameStrata("DIALOG")
	f:SetScale(ns.db.settings.scale or 1)

	local ins = f.insets
	local inner = CreateFrame("Frame", nil, f)
	inner:SetPoint("TOPLEFT", ins.left + SP.md, -(ins.top + SP.md))
	inner:SetPoint("BOTTOMRIGHT", -(ins.right + SP.md), ins.bottom + SP.md)
	f.inner = inner

	f.intro = W.Paragraph(inner, "caption", "ink")
	f.intro:SetPoint("TOPLEFT")
	f.intro:SetPoint("RIGHT")
	f.intro:SetText(
		L["Gathers versions, language, your plan's id and size, other addons and the latest errors. No character name, realm, guild, group members or chat."]
	)

	f.whatLabel = W.Text(inner, "caption", "gold")
	f.whatLabel:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -SP.md)
	f.whatLabel:SetText(L["What happened?"])
	f.what = W.MultiLine(inner, {
		maxBytes = 1500,
		onChange = function()
			ReportFrame.Update()
		end,
	})
	f.what:SetPoint("TOPLEFT", f.whatLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.what:SetPoint("RIGHT")
	f.what:SetHeight(72)

	f.reportLabel = W.Text(inner, "caption", "gold")
	f.reportLabel:SetPoint("TOPLEFT", f.what, "BOTTOMLEFT", 0, -SP.md)
	f.reportLabel:SetText(L["Report"])
	f.hint = W.Text(inner, "caption", "muted")
	f.hint:SetPoint("LEFT", f.reportLabel, "RIGHT", SP.md, 0)
	f.hint:SetText(L["Click the box, then Ctrl+C to copy"])
	f.short = W.Check(inner, L["Short for Discord (2000 characters)"], function()
		ReportFrame.Update()
	end)
	f.short:SetPoint("TOPRIGHT", f.what, "BOTTOMRIGHT", 0, -SP.md)

	-- Bottom up: buttons, the link, then the report fills what is left.
	f.select = W.Button(inner, L["Select the report"], "red", function()
		selectAll(f.report)
	end)
	f.select:SetPoint("BOTTOMLEFT")
	f.refresh = W.Button(inner, L["Refresh"], "outline", function()
		ReportFrame.Collect()
	end)
	f.refresh:SetPoint("LEFT", f.select, "RIGHT", SP.sm, 0)
	f.close2 = W.Button(inner, L["Close"], "outline", function()
		f:Hide()
	end)
	f.close2:SetPoint("LEFT", f.refresh, "RIGHT", SP.sm, 0)

	f.link = W.MultiLine(inner, { readOnly = true, maxBytes = 1200 })
	f.link:SetPoint("BOTTOMLEFT", f.select, "TOPLEFT", 0, SP.md)
	f.link:SetPoint("RIGHT")
	f.link:SetHeight(58)
	f.linkLabel = W.Text(inner, "caption", "gold")
	f.linkLabel:SetPoint("BOTTOMLEFT", f.link, "TOPLEFT", 0, SP.xs)
	f.linkLabel:SetText(L["Issue link: copy it into a browser, then paste the report into the form"])
	f.linkLabel:SetPoint("RIGHT")
	f.linkLabel:SetJustifyH("LEFT")

	f.report = W.MultiLine(inner, { readOnly = true, maxBytes = 30000 })
	f.report:SetPoint("TOPLEFT", f.reportLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.report:SetPoint("BOTTOMRIGHT", f.linkLabel, "TOPRIGHT", 0, SP.sm)
	f:Hide()
	frame = f
	return f
end

-- Gather the facts again and fill the boxes.
function ReportFrame.Collect()
	data = Report.Collect()
	ReportFrame.Update()
end

function ReportFrame.Show()
	if not frame then
		build()
	end
	frame:Show()
	ReportFrame.Collect()
	frame.report.scroll:SetVerticalScroll(0)
end

function ReportFrame.Frame()
	return frame
end
