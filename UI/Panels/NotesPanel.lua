-- Notes tab: plan details (difficulty, author, description) and free-form notes. A read-only plan (a recommended one)
-- shows them as formatted text instead of input boxes.

local _, ns = ...
local S, W, L = ns.Style, ns.Widgets, ns.L
local Plan, Schema = ns.Plan, ns.Schema
local SP = S.SPACE

local Panel = {}
ns.Panels.notes = Panel

-- Every recommended plan's notes carry this paragraph (tools/gen_plans.lua, word for word; a test checks): shown
-- translated. Estimated spots carry a small "~" in the UI (Style.WithApprox).
Panel.ESTIMATES = 'Spots marked "~" are estimates, not measurements. Party positions are generic suggestions: tank where '
	.. "the group arrives, healer and ranged behind, melee beside the boss. Check everything in game and adjust it in "
	.. "your own copy."

function Panel.Create(parent, ctx)
	local f = CreateFrame("Frame", nil, parent)

	local function set(field, value)
		local p = ctx:Plan()
		if p then
			Plan.SetField(p, field, value)
			ctx:Changed("meta")
		end
	end

	f.diffLabel = W.Label(f, L["Difficulty or variant"])
	f.diffLabel:SetPoint("TOPLEFT")
	-- Difficulty and author on lines of their own, as wide as the column (the plan column is narrow on a small window).
	f.difficulty = W.Input(f, {
		maxBytes = Schema.TEXT.difficulty,
		placeholder = L["For example: Normal, Heroic, speed run"],
		onCommit = function(text)
			set("difficulty", text)
		end,
	})
	f.difficulty:SetPoint("TOPLEFT", f.diffLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.difficulty:SetPoint("RIGHT")

	f.authorLabel = W.Label(f, L["Author"])
	f.authorLabel:SetPoint("TOPLEFT", f.difficulty, "BOTTOMLEFT", 0, -SP.md)
	f.author = W.Input(f, {
		maxBytes = Schema.TEXT.author,
		onCommit = function(text)
			set("author", text)
		end,
	})
	f.author:SetPoint("TOPLEFT", f.authorLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.author:SetPoint("RIGHT")

	f.descLabel = W.Label(f, L["Description (shown when sharing)"])
	f.descLabel:SetPoint("TOPLEFT", f.author, "BOTTOMLEFT", 0, -SP.md)
	f.description = W.MultiLine(f, {
		maxBytes = Schema.TEXT.description,
		onCommit = function(text)
			set("description", text)
		end,
	})
	f.description:SetPoint("TOPLEFT", f.descLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.description:SetPoint("RIGHT")
	f.description:SetHeight(80)

	f.notesLabel = W.Label(f, L["Notes"])
	f.notesLabel:SetPoint("TOPLEFT", f.description, "BOTTOMLEFT", 0, -SP.md)
	f.notes = W.MultiLine(f, {
		maxBytes = Schema.TEXT.notes,
		onCommit = function(text)
			set("notes", text)
		end,
	})
	f.notes:SetPoint("TOPLEFT", f.notesLabel, "BOTTOMLEFT", 0, -SP.xs)
	f.notes:SetPoint("BOTTOMRIGHT")

	-- Where a shared plan came from, on the author label's line, at the right.
	f.source = W.Text(f, "caption", "dim")
	f.source:SetPoint("BOTTOMLEFT", f.authorLabel, "BOTTOMRIGHT", SP.md, 0)
	f.source:SetPoint("RIGHT")
	f.source:SetJustifyH("RIGHT")

	local editors = { f.diffLabel, f.difficulty, f.authorLabel, f.author, f.descLabel, f.description, f.notesLabel,
		f.notes, f.source }
	f.doc = W.Document(f)
	f.doc:SetAllPoints()

	local function showDocument(p)
		local doc = f.doc
		doc:Begin(p.id)
		doc:Add("title", p.name)
		local meta = {}
		if p.author ~= "" then
			meta[#meta + 1] = string.format(L["by %s"], p.author)
		end
		if p.difficulty ~= "" then
			meta[#meta + 1] = p.difficulty
		end
		doc:Add("muted", table.concat(meta, "  \226\128\162  "))
		-- Where it comes from: a recommended plan's source, data revision and data date (UI.PlanSource).
		local _, sourceLines = ns.UI.PlanSource(p)
		if sourceLines then
			doc:Add("heading", L["Source"])
			for _, line in ipairs(sourceLines) do
				doc:Add("muted", line)
			end
		end
		doc:Add("heading", L["About this plan"])
		doc:Add("text", p.description)
		if p.notes ~= "" and p.notes ~= p.description then
			doc:Add("heading", L["Notes"])
			-- The description often opens the notes; do not print it twice.
			local notes = p.notes
			if p.description ~= "" and notes:sub(1, #p.description) == p.description then
				notes = notes:sub(#p.description + 1):gsub("^%s+", "")
			end
			-- The recommended plans' standard paragraph (tools/gen_plans.lua writes it in English) in the player's language.
			local i, j = notes:find(Panel.ESTIMATES, 1, true)
			if i then
				notes = notes:sub(1, i - 1) .. L[Panel.ESTIMATES] .. notes:sub(j + 1)
			end
			doc:Add("text", notes)
		end
		doc:Finish()
	end

	function f:Refresh()
		local p = ctx:Plan()
		if not p then
			return
		end
		local ro = ctx:ReadOnly()
		for _, w in ipairs(editors) do
			w:SetShown(not ro)
		end
		self.doc:SetShown(ro)
		if ro then
			showDocument(p)
			return
		end
		self.difficulty:SetValue(p.difficulty)
		self.author:SetValue(p.author)
		self.description:SetValue(p.description)
		self.notes:SetValue(p.notes)
		if p.source and p.source.from then
			self.source:SetText(string.format(L["Received from %s"], p.source.from))
		elseif p.source and p.source.kind then
			self.source:SetText(L["Imported"])
		else
			self.source:SetText("")
		end
	end
	return f
end
