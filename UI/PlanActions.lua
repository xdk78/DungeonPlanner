-- What the home screen, the header and the menus share: making, copying and managing plans; the list of instances
-- with their level range, plan count and progress; instance pictures (the loading screen, cropped) and the drawn
-- plate shown where the game has no picture. All of it lives on ns.Home (UI/Home.lua builds the screen).

local _, ns = ...
local Home = ns.Home
local S, W, L, Art = ns.Style, ns.Widgets, ns.L, ns.Art
local SP = S.SPACE
local UI = ns.UI

-- Plans ------------------------------------------------------------------------------------------------------------------

local function createPlan(templateId, name, entry)
	local info
	if entry then
		info = {
			name = entry.name or "",
			kind = entry.kind or "other",
			ejInstanceID = entry.ejInstanceID,
			uiMapID = entry.uiMapID,
		}
	else
		local cur = ns.Instances.Current()
		info = { name = cur.name or "", kind = cur.kind, ejInstanceID = cur.ejInstanceID, uiMapID = cur.uiMapID }
	end
	local author = UnitName and ns.Util.Plain(UnitName("player")) or ""
	local plan = ns.Plan.New({
		name = name,
		author = author,
		instance = info,
		floors = ns.Instances.Floors(info.uiMapID),
	})
	ns.Templates.Get(templateId).apply(plan)
	if info.ejInstanceID then
		ns.Templates.AddJournalEncounters(plan, info.ejInstanceID)
	end
	ns.DB.AddPlan(plan)
	UI.SelectPlan(plan.id)
	return plan
end
Home.CreatePlan = createPlan

-- "New plan": choose a template, then a name. entry = the instance (nil: where the player is).
function UI.NewPlan(owner, entry)
	if ns.DB.IsReadOnly() then
		return
	end
	local function ask(templateId)
		W.AskText(L["New plan"], L["Name the plan, for example the strategy or difficulty."], L["New plan"], function(name)
			createPlan(templateId, name ~= "" and name or L["New plan"], entry)
		end)
	end
	local items = { { title = L["New plan"] } }
	for _, t in ipairs(ns.Templates.list) do
		items[#items + 1] = {
			L[t.title],
			function()
				ask(t.id)
			end,
		}
	end
	if not W.Menu(owner, items) then
		ask("blank")
	end
end

-- Import a pasted string. When it holds a plan with the name of one of yours for the same instance, ask first: keep
-- both (the primary choice) or replace yours. Replacing the plan on the table can be undone (it is one more step in its
-- history). onDone(ok, message) gets the import's result; nothing happens on Cancel.
-- The notice for imported plans last changed before yours (DB.ImportConflicts older): which, by whom and when, or nil.
function UI.OlderImportNotice(conflicts)
	local lines = {}
	for _, c in ipairs(conflicts or {}) do
		if c.older then
			local function day(t)
				return t and type(date) == "function" and date("%Y-%m-%d %H:%M", t) or "?"
			end
			local who = (c.incomingAuthor or "") ~= "" and c.incomingAuthor or L["unknown"]
			lines[#lines + 1] = string.format(L["\"%s\" from %s was last changed %s, before yours (%s): replacing would undo your newer changes."],
				c.incoming, who, day(c.incomingUpdated), day(c.existing.updated))
		end
	end
	if #lines == 0 then
		return nil
	end
	return "|cffff9933" .. table.concat(lines, "\n") .. "|r"
end

function UI.ImportWithConfirm(text, source, onDone)
	local function run(replace)
		local ok, message, _, replaced = ns.DB.ImportString(text, source, { replace = replace })
		for _, plan in ipairs(replaced or {}) do
			if plan.id == ns.db.ui.selectedPlan then
				UI.ctx:Changed("import")
			end
		end
		if onDone then
			onDone(ok, message)
		end
	end
	local conflicts = ns.DB.ImportConflicts(text)
	if #conflicts == 0 then
		run(false)
		return
	end
	local question
	if #conflicts == 1 then
		question = string.format(L["You already have a plan named \"%s\" for this instance. Keep both, or replace yours with the imported one?"],
			conflicts[1].existing.name)
	else
		question = ns.Plural(#conflicts,
			L["%d imported plan is named like one of yours. Keep both or replace?|%d imported plans are named like plans of yours. Keep both or replace?"])
	end
	-- An older revision over a newer one (MDT #430: a stale copy wiped newer work): say whose and when, in orange.
	local older = UI.OlderImportNotice(conflicts)
	W.ShowDialog({
		title = L["Replace your plan?"],
		text = question .. "\n\n" .. (older and (older .. "\n\n") or "")
			.. L["Replacing overwrites your plan with the imported one."],
		buttons = {
			{
				L["Keep both"],
				function()
					run(false)
				end,
				true,
			},
			{
				L["Replace mine"],
				function()
					run(true)
				end,
			},
			{ L["Cancel"] },
		},
	})
end

-- An editable copy of any plan (the way to change a recommended one).
function UI.CopyPlan(plan)
	if ns.DB.IsReadOnly() then
		return nil
	end
	local name = plan.bundled and string.format(L["%s (my copy)"], plan.name) or nil
	local copy = ns.Plan.Duplicate(plan, name)
	-- The copy remembers the journal IDs this client found for the plan (recommended plans ship without them).
	ns.Plan.ApplyJournalIds(copy, ns.Journal.IdsFor(plan))
	ns.DB.AddPlan(copy)
	UI.SelectPlan(copy.id)
	return copy
end

-- Right-click menu of a plan.
function UI.PlanMenu(plan, owner)
	local items = { { title = plan.name } }
	items[#items + 1] = {
		L["Open"],
		function()
			UI.SelectPlan(plan.id)
		end,
	}
	if not ns.DB.IsReadOnly() then
		items[#items + 1] = {
			plan.bundled and L["Make an editable copy"] or L["Duplicate"],
			function()
				UI.CopyPlan(plan)
			end,
		}
	end
	if ns.DB.IsEditable(plan) then
		items[#items + 1] = {
			L["Rename"],
			function()
				W.AskText(L["Rename plan"], "", plan.name, function(value)
					ns.Plan.SetField(plan, "name", value)
					ns.DB.Changed(plan, "meta")
				end)
			end,
		}
	end
	items[#items + 1] = {
		L["Export"],
		function()
			UI.SelectPlan(plan.id)
			UI.SelectTab("share")
		end,
	}
	if ns.DB.IsEditable(plan) then
		items[#items + 1] = "-"
		items[#items + 1] = {
			L["Delete"],
			function()
				local function del()
					ns.DB.DeletePlan(plan.id)
				end
				if ns.db.settings.confirmDelete then
					W.Confirm(L["Delete plan?"], string.format(L["\"%s\" will be deleted. This cannot be undone."], plan.name),
						L["Delete"], del)
				else
					del()
				end
			end,
		}
	end
	W.Menu(owner, items)
end

-- Pictures ---------------------------------------------------------------------------------------------------------------

-- The painted part of each journal picture (the rest of the file is padding), as u0, u1, v0, v1, and that part's
-- width / height in pixels. Retail's layouts (inferred on Forever; /dp scan lists the files the client returns).
local ART_AREA = {
	button = { 0, 0.68359375, 0, 0.7421875, 175 / 95 }, -- the instance button: 175 x 95 of 256 x 128
	button2 = { 0, 1, 0, 1, 2 },
	lore = { 0, 1, 0, 0.75, 512 / 384 },
	background = { 0, 1, 0, 1, 2 },
}
local ART_ORDER = {
	card = { "button", "button2", "lore", "background" },
	header = { "lore", "background", "button2", "button" },
}

-- Crop a picture's painted area to the texture's aspect (centre), so wide plates and rows never stretch it.
local function cropToFit(tex, area, w, h)
	local u0, u1, v0, v1 = area[1], area[2], area[3], area[4]
	if w and h and w > 1 and h > 1 then
		local aw, ah = u1 - u0, v1 - v0
		local texelAspect = area[5]
		local want = w / h
		if want > texelAspect then
			local keep = ah * texelAspect / want
			local cut = (ah - keep) / 2
			v0, v1 = v0 + cut, v1 - cut
		else
			local keep = aw * want / texelAspect
			local cut = (aw - keep) / 2
			u0, u1 = u0 + cut, u1 - cut
		end
	end
	tex:SetTexCoord(u0, u1, v0, v1)
end

-- Instance art on a texture: the Adventure Guide's picture (where a client has one), else the game's loading screen or
-- Group Finder picture, else an installed addon's own picture (Data/GameFiles.lua, InstancePictures), cropped to fit.
-- Returns true and, for an addon's picture, its credit ("Dungeon Journal"). Without any, the texture shows dark slate
-- stone and the function returns false, so the caller can draw its plate (Home.ArtPlate). `use` = "card" (default) or
-- "header".
function Home.SetInstanceArt(tex, entry, use, w, h)
	local art = entry and ns.Journal.InstanceArt(entry)
	if art then
		for _, key in ipairs(ART_ORDER[use or "card"]) do
			local file = art[key]
			if file and Art.SetFile(tex, file) then
				cropToFit(tex, ART_AREA[key], w or tex:GetWidth(), h or tex:GetHeight())
				tex:SetVertexColor(1, 1, 1, 1)
				return true
			end
		end
	end
	for _, pic in ipairs(entry and ns.GameFiles.InstancePictures(entry) or {}) do
		if Art.SetFile(tex, pic.file) then
			cropToFit(tex, pic.area, w or tex:GetWidth(), h or tex:GetHeight())
			tex:SetVertexColor(1, 1, 1, 1)
			return true, pic.credit
		end
	end
	tex:SetTexture(S.WindowBackground())
	tex:SetTexCoord(0, 1, 0, 0.6)
	tex:SetVertexColor(0.24, 0.27, 0.32, 1)
	return false
end

-- A picture plate: the instance's art, or where the game has none, slate stone with a bronze-ringed emblem (the
-- game's dungeon or raid mark) and the instance's name engraved faintly across it. plate:SetEntry(entry, use).
function Home.ArtPlate(parent, opts)
	opts = opts or {}
	local f = W.Panel(parent, "field", "border")
	f.art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.art:SetPoint("TOPLEFT", 4, -4)
	f.art:SetPoint("BOTTOMRIGHT", -4, 4)
	f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.shade:SetColorTexture(0, 0, 0, 0.45)
	f.shade:SetPoint("BOTTOMLEFT", 4, 4)
	f.shade:SetPoint("BOTTOMRIGHT", -4, 4)
	f.shade:SetHeight(opts.shade or 0)
	f.shade:SetShown((opts.shade or 0) > 0)
	f.emblem = CreateFrame("Frame", nil, f)
	f.emblem:SetPoint("CENTER", 0, opts.emblemY or 0)
	f.emblem.icon = Art.RoundTexture(f.emblem, "ARTWORK", 0)
	f.emblem.icon:SetPoint("CENTER")
	f.emblem.ring = f.emblem:CreateTexture(nil, "OVERLAY")
	f.emblem.ring:SetTexture(S.MEDIA .. "Ring")
	S.Tint(f.emblem.ring, "borderHover")
	f.watermark = W.Text(f, opts.watermarkFont or "huge", "gold", "ARTWORK")
	f.watermark:SetPoint("TOP", f.emblem, "BOTTOM", 0, -SP.sm)
	f.watermark:SetPoint("LEFT", SP.md, 0)
	f.watermark:SetPoint("RIGHT", -SP.md, 0)
	f.watermark:SetJustifyH("CENTER")
	f.watermark:SetAlpha(0.5)
	-- Where the picture is another addon's: its name, small in the top right corner.
	f.credit = W.Text(f, "caption", "muted", "OVERLAY")
	f.credit:SetPoint("TOPRIGHT", -SP.sm, -SP.sm)
	f.credit:Hide()

	function f:SetEntry(entry, use)
		local w, h = self:GetWidth() - 8, self:GetHeight() - 8
		local has, credit = Home.SetInstanceArt(self.art, entry, use, w, h)
		self.hasArt = has
		self.creditText = credit and string.format(L["Picture: %s"], credit) or nil
		self.credit:SetText(self.creditText or "")
		self.credit:SetShown(self.creditText ~= nil and not opts.noCredit)
		local size = math.max(16, math.min(64, math.floor(math.min(w, h) * 0.38)))
		self.emblem:SetSize(size, size)
		self.emblem.icon:SetSize(size, size)
		self.emblem.ring:SetSize(size + 8, size + 8)
		self.emblem.ring:SetPoint("CENTER")
		Art.Set(self.emblem.icon, entry and entry.kind == "raid" and "emblemRaid" or "emblemDungeon")
		self.emblem:SetShown(not has)
		self.watermark:SetShown(not has and not opts.noWatermark and h > 70)
		self.watermark:SetText(entry and entry.name or "")
		return has
	end
	return f
end

-- Instances ----------------------------------------------------------------------------------------------------------------

local function norm(s)
	return type(s) == "string" and s:lower() or ""
end
Home.Norm = norm

-- Every instance the screen can show: the journal's, plus instances that only plans know (custom maps, journals that
-- could not be read). Returns the list and whether the journal could be read completely.
function Home.AllEntries()
	local out, seen = {}, {}
	local data = ns.Instances.GetAll()
	local index = 0
	for _, tier in ipairs(data.tiers) do
		for _, entry in ipairs(tier.instances) do
			if not seen[entry.key] then
				seen[entry.key] = true
				index = index + 1
				entry.order = index
				out[#out + 1] = entry
			end
		end
	end
	local function addFromPlan(plan)
		local key = ns.DB.InstanceKey(plan.instance)
		if seen[key] or key == "other" then
			return
		end
		for _, e in ipairs(out) do
			if ns.Bundled.SameInstance(plan.instance, e) then
				return
			end
		end
		seen[key] = true
		index = index + 1
		local entry = UI.EntryForPlan(plan)
		entry.order = index
		out[#out + 1] = entry
	end
	for _, plan in ipairs(ns.Bundled.All()) do
		addFromPlan(plan)
	end
	for _, plan in ipairs(ns.DB.Plans()) do
		addFromPlan(plan)
	end
	return out, data.complete
end

-- Bosses of an instance killed by this character (lifetime) and how many there are: from the journal when it lists
-- the instance, else from the instance's first plan when its bosses carry game IDs. nil when nothing can be counted.
function Home.Progress(entry)
	if not ns.char then
		return nil
	end
	local journal, score = ns.Journal.ResolveInstance(entry)
	if journal and score >= 75 then
		local bosses = ns.Instances.GetEncounters(journal.ejInstanceID)
		if #bosses > 0 then
			local killed = 0
			for _, boss in ipairs(bosses) do
				if boss.dungeonEncounterID and ns.Progress.KillsOf(ns.char.progress, boss.dungeonEncounterID) > 0 then
					killed = killed + 1
				end
			end
			return killed, #bosses
		end
	end
	local plan = UI.PlansFor(entry)[1]
	if not plan or #plan.encounters == 0 then
		return nil
	end
	local idOf = ns.Journal.GameIdOf(plan)
	local known, killed = 0, 0
	for _, enc in ipairs(plan.encounters) do
		local id = enc.dungeonEncounterID or idOf(enc)
		if id then
			known = known + 1
			if ns.Progress.KillsOf(ns.char.progress, id) > 0 then
				killed = killed + 1
			end
		end
	end
	if known == 0 then
		return nil, #plan.encounters
	end
	return killed, #plan.encounters
end

-- Counts and levels for one entry (cached on it until the next refresh).
function Home.Decorate(entry)
	entry.plans = #ns.DB.PlansFor(entry)
	local bundled = ns.Bundled.ForInstance(entry)
	entry.recommended = #bundled
	local lo, hi = ns.Instances.LevelRange(entry)
	if not lo and bundled[1] then
		lo, hi = ns.GameFiles.ResolveRange(nil, bundled[1].instance)
	end
	entry.levelLo, entry.levelHi = lo, hi
	entry.killed, entry.bosses = Home.Progress(entry)
	-- New in WoW: Forever or from the original game: known from the recommended plan's research (instance.origin).
	entry.origin = entry.origin or (bundled[1] and bundled[1].instance.origin) or nil
end

function Home.MatchesSearch(entry, query)
	if query == "" then
		return true
	end
	if norm(entry.name):find(query, 1, true) then
		return true
	end
	for _, plan in ipairs(UI.PlansFor(entry)) do
		if norm(plan.name):find(query, 1, true) then
			return true
		end
	end
	return false
end

function Home.LevelText(entry)
	if not entry.levelLo then
		return entry.kind == "raid" and L["Raid"] or L["Dungeon"]
	end
	if entry.levelHi and entry.levelHi ~= entry.levelLo then
		return string.format(L["LV %d-%d"], entry.levelLo, entry.levelHi)
	end
	return string.format(L["LV %d"], entry.levelLo)
end

-- Sorted by level when the client knows levels, else in the journal's order.
function Home.SortEntries(list)
	table.sort(list, function(a, b)
		if a.levelLo and b.levelLo and a.levelLo ~= b.levelLo then
			return a.levelLo < b.levelLo
		end
		if (a.levelLo ~= nil) ~= (b.levelLo ~= nil) then
			return a.levelLo ~= nil
		end
		if a.order ~= b.order then
			return (a.order or 0) < (b.order or 0)
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end
