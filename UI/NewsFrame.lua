-- The "What's new" card and the first-run welcome (Core/WhatsNew.lua decides when and what). A small movable window with
-- a scrolling document; "Got it" closes it. Built on first use; it costs nothing while closed.

local _, ns = ...
local NewsFrame = ns:NewModule("NewsFrame")
local S, W, L = ns.Style, ns.Widgets, ns.L
local SP, SZ = S.SPACE, S.SIZE

local MIN_W, MIN_H = 360, 300
local frame

local function saved()
	ns.db.ui.news = type(ns.db.ui.news) == "table" and ns.db.ui.news or {}
	return ns.db.ui.news
end

local function build()
	local s = saved()
	s.width, s.height = s.width or 460, s.height or 500 -- tall enough for a version's highlights without scrolling
	local f = W.Window("DungeonPlannerNewsFrame", L["What's new"], s, MIN_W, MIN_H, { compact = true })
	f:SetFrameStrata("DIALOG")
	f:SetScale(ns.db.settings.scale or 1)
	local ins = f.insets
	local inner = CreateFrame("Frame", nil, f)
	inner:SetPoint("TOPLEFT", ins.left + SP.md, -(ins.top + SP.md))
	inner:SetPoint("BOTTOMRIGHT", -(ins.right + SP.md), ins.bottom + SP.md)
	f.ok = W.Button(inner, L["Got it"], "red", function()
		f:Hide()
	end)
	f.ok:SetPoint("BOTTOMLEFT")
	f.open = W.Button(inner, L["Open the planner"], "outline", function()
		f:Hide()
		ns.UI.Show()
	end)
	f.open:SetPoint("LEFT", f.ok, "RIGHT", SP.sm, 0)
	f.settings = W.Button(inner, L["Open Settings"], "outline", function()
		ns.UI.OpenSettings(f.settingsGroup)
	end)
	f.settings:SetPoint("LEFT", f.ok, "RIGHT", SP.sm, 0)
	f.doc = W.Document(inner)
	f.doc:SetPoint("TOPLEFT")
	f.doc:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", 0, SZ.control + SP.md)
	f:Hide()
	frame = f
end

-- kind: "welcome" or "news"; version: the entry to show (news; default the running version).
function NewsFrame.Show(kind, version)
	if not frame then
		build()
	end
	local content
	if kind == "welcome" then
		content = ns.WhatsNew.Welcome()
	else
		content = ns.WhatsNew.Entry(version or ns.version)
	end
	if not content then
		return false
	end
	frame.title:SetText(kind == "welcome" and L["Welcome"] or L["What's new"])
	local doc = frame.doc
	doc:Begin()
	doc:Add("title", content.title)
	if content.intro then
		doc:Add("text", content.intro)
	end
	frame.settingsGroup = nil
	for _, item in ipairs(content.items) do
		doc:Add("label", item[1])
		doc:Add("text", item[2])
		frame.settingsGroup = frame.settingsGroup or item[3] -- a note can name the Settings group it is about
	end
	doc:Finish()
	frame.open:SetShown(kind == "welcome")
	frame.settings:SetShown(frame.settingsGroup ~= nil)
	frame:Show()
	return true
end

function NewsFrame.Frame()
	return frame
end
