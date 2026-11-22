-- The problem report (/dp report, the ! button in the title bar): one plain text a player pastes into a GitHub issue,
-- built from facts about the addon and the client. The window is UI/ReportFrame.lua.
--
-- Privacy: the report never holds the character name, realm, guild, group members or chat. Plan names and notes (the
-- player's own words) are left out too: a plan is named by its id and its sizes. Lua error messages go through
-- Errors.Clean, which also removes the player's name and realm. The only free text is what the player types into
-- "What happened?", and the window says so.
--
-- Lua errors: the last ones raised inside our own entry points (ns.SafeCall, Core/Init.lua), plus the ones BugGrabber
-- holds that mention Dungeon Planner (read only; nothing is hooked).

local _, ns = ...
local Report = ns:NewModule("Report")

Report.REPO = "xdk78/DungeonPlanner"
Report.MAX_ERRORS = 10
Report.DISCORD_LIMIT = 2000 -- characters
Report.MAX_URL = 420 -- the issue link never gets longer than this
Report.MAX_WHAT = 120 -- bytes of "What happened?" put into the issue link (the link stays short; the report has all of it)

-- Percent-encoding of a URL query value (UTF-8 bytes kept as %XX).
function Report.UrlEncode(text)
	return (tostring(text or ""):gsub("[^%w%-%._~]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

-- Cut to at most `max` bytes without ending inside a UTF-8 character.
local function cut(text, max)
	if #text <= max then
		return text
	end
	local stop = max
	while stop > 0 do
		local b = text:byte(stop + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		stop = stop - 1
	end
	return text:sub(1, stop)
end

-- The first `n` characters (not bytes) of a UTF-8 text.
local function charSub(text, n)
	local count = 0
	for i = 1, #text do
		local b = text:byte(i)
		if b < 0x80 or b >= 0xC0 then
			if count == n then
				return text:sub(1, i - 1)
			end
			count = count + 1
		end
	end
	return text
end

-- The new-issue link. GitHub fills an issue form's fields from query parameters named after the field ids in
-- .github/ISSUE_TEMPLATE/bug_report.yml (version, client, language, what); the long report is pasted by hand.
function Report.IssueURL(data, what)
	local parts = {
		"template=bug_report.yml",
		"version=" .. Report.UrlEncode(data.addon and data.addon.version or ""),
		"client=" .. Report.UrlEncode(data.client and string.format("%s (build %s)", tostring(data.client.version),
			tostring(data.client.build)) or ""),
		"language=" .. Report.UrlEncode(data.language and data.language.active or ""),
	}
	what = ns.Errors.Scrub(ns.Util.Trim(tostring(what or ""))):gsub("%s+", " ")
	local base = "https://github.com/" .. Report.REPO .. "/issues/new?" .. table.concat(parts, "&")
	-- Fixed length cap: the free text goes in as much as fits, cut on a whole character.
	local keep = math.min(#what, Report.MAX_WHAT)
	while keep > 0 do
		local url = base .. "&what=" .. Report.UrlEncode(cut(what, keep))
		if #url <= Report.MAX_URL then
			return url
		end
		keep = keep - 8
	end
	return base
end

-- Taint is not a Lua error: when the game blocks one of our actions (ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN) it
-- raises these events, and the report would say "no errors". Record each with where it happened: the first line of our own
-- code in the stack, else the first Lua line (and the C function that was called).
local function stackSpot()
	local stack = rawget(_G, "debugstack")
	local ok, text
	if type(stack) == "function" then
		ok, text = pcall(stack, 3, 12, 0)
	end
	if not ok or type(text) ~= "string" then
		return "location unknown"
	end
	local first
	for line in text:gmatch("[^\n]+") do
		line = ns.Errors.Clean(line)
		if line:find("DungeonPlanner", 1, true) then
			return line:match("^%s*(.-)%s*$")
		end
		first = first or line:match("^%s*(.-)%s*$")
	end
	return "via " .. (first or "?")
end

function Report.Init()
	for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
		ns:RegisterEvent(event, function(_, addon, func)
			if addon == ns.name then
				ns.Errors.Record(string.format("%s %s at %s", event == "ADDON_ACTION_BLOCKED" and "blocked:" or "forbidden:",
					tostring(func), stackSpot()))
			end
		end)
	end
end

-- Collection ------------------------------------------------------------------------------------------------------------

-- Run one collector; a failure becomes a line, never an error (the report must open even when something is broken).
local function guarded(name, fn)
	local ok, result = pcall(fn)
	if ok then
		return result
	end
	return { failed = name .. ": " .. ns.Errors.Clean(result) }
end

local function addonInfo()
	return {
		version = ns.version,
		schema = ns.DB.SCHEMA,
		protocol = ns.PROTOCOL_VERSION,
		export = ns.EXPORT_VERSION,
		readOnly = ns.DB.IsReadOnly() and true or false,
	}
end

local function languageInfo()
	return {
		client = ns.Compat.ClientInfo().locale,
		setting = ns.db.settings.locale,
		active = ns.activeLocale,
		font = ns.Style.FontShortName and ns.Style.FontShortName(ns.Style.fontFile) or tostring(ns.Style.fontFile),
	}
end

-- Where the player is: the instance only when inside one (an open-world zone says where the player is for no reason).
local function instanceInfo()
	local cur = ns.Instances.Current()
	if not cur.inInstance then
		return { inside = false }
	end
	return { inside = true, name = cur.name, kind = cur.kind, journal = cur.ejInstanceID, map = cur.uiMapID,
		difficulty = cur.difficultyID }
end

local function planInfo()
	local id = ns.db.ui.selectedPlan
	local plan = id and ns.DB.GetPlan(id)
	if not plan then
		return { none = true }
	end
	local bundled = id:sub(1, #ns.Bundled.PREFIX) == ns.Bundled.PREFIX
	local info = {
		id = id,
		kind = bundled and "recommended" or (plan.source and "received or imported" or "own"),
		revision = ns.DB.Revision(plan),
		markers = #(plan.markers or {}),
		routes = #(plan.routes or {}),
		pulls = #(plan.pulls or {}),
		encounters = #(plan.encounters or {}),
		floors = #(plan.floors or {}),
	}
	local ctx = ns.UI and ns.UI.ctx
	if ctx and ctx.Steps then
		info.steps = #ctx:Steps()
		local index = ctx:StepIndex()
		info.step = type(index) == "number" and index or nil
	end
	return info
end

local function windowInfo()
	return { shown = ns.UI.IsShown(), view = ns.db.ui.view, section = ns.db.ui.tab,
		runMode = ns.RunMode.IsShown() and true or false, scale = ns.db.settings.scale }
end

-- The addons Dungeon Planner reads from or works with, and whether each is loaded for this character.
function Report.IntegrationFolders()
	local folders, seen = {}, {}
	local function add(folder)
		if folder and not seen[folder] then
			seen[folder] = true
			folders[#folders + 1] = folder
		end
	end
	for _, row in ipairs(ns.Providers.Report()) do
		add(row.addon)
	end
	for _, folder in ipairs({ "ForeverDungeonJournal", "ForeverDungeonRoutes", "OpenMap", "NeedRoll", "QuestieDB", "DBM-Core",
		"BigWigs", "WoWPoPolskuForever", "BugGrabber" }) do
		add(folder)
	end
	return folders
end

local function integrations()
	local out = {}
	for _, folder in ipairs(Report.IntegrationFolders()) do
		out[#out + 1] = { folder = folder, state = ns.Integrations.AddonState(folder) }
	end
	return out
end

-- The /dp debug summary as plain lines (the chat version, with colours and the font test dialog, is Slash.Debug).
local function debugSummary()
	local lines = {}
	local missing = {}
	for _, row in ipairs(ns.Compat.Report()) do
		if not row.ok then
			missing[#missing + 1] = row.name
		end
	end
	lines[#lines + 1] = string.format("API checks missing: %d%s", #missing,
		#missing > 0 and (" (" .. table.concat(missing, ", ", 1, math.min(#missing, 15)) .. (#missing > 15 and ", ..." or "") .. ")") or "")
	local failed = {}
	for _, r in ipairs(ns.Compat.SelfTest()) do
		if not r.ok then
			failed[#failed + 1] = r.name .. (r.detail ~= "" and (": " .. ns.Errors.Clean(r.detail)) or "")
		end
	end
	lines[#lines + 1] = "Self-tests failed: " .. (#failed > 0 and table.concat(failed, "; ") or "none")
	for _, row in ipairs(ns.Providers.Report()) do
		local state = row.failed and ("failed: " .. ns.Providers.ShortError(row.failed))
			or row.active and "active" or (row.enabled == false and "switched off") or (row.loaded == false and "not installed") or "no data"
		lines[#lines + 1] = string.format("Source %s: %s%s", row.title, state, row.version and (" " .. row.version) or "")
	end
	local rec = ns.Recorder
	lines[#lines + 1] = "Run recorder: " .. (rec.Enabled() and "on" or "off")
	local artMissing = 0
	for _, row in ipairs(ns.Art.Report()) do
		if (row.atlas and row.atlasOk == false) or (row.file and row.fileOk == false) then
			artMissing = artMissing + 1
		end
	end
	local nativeLacking = {}
	for _, row in ipairs(ns.Art.NativeReport()) do
		if not row.ok then
			nativeLacking[#nativeLacking + 1] = row.name
		end
	end
	lines[#lines + 1] = string.format("Art missing: %d; window parts drawn instead: %s", artMissing,
		#nativeLacking > 0 and table.concat(nativeLacking, ", ") or "none")
	local journal = ns.Journal.GetAll()
	lines[#lines + 1] = string.format("Adventure Guide: %d instances; recommended plans: %d; loot %s", #journal.list,
		ns.Bundled.Count(), ns.Loot.Available() and "available" or "not available")
	local counts, grid = ns.MinimapArt.Summary()
	lines[#lines + 1] = string.format("Floor maps: %d game, %d tiles, %d Reyes, %d other addons, %d minimap, %d grid (%s)", counts.map,
		counts.tiles, counts.reyes, counts.provider, counts.minimap, counts.grid, table.concat(grid, ", "))
	if #ns.db.quarantine > 0 then
		lines[#lines + 1] = "Unreadable plans set aside: " .. #ns.db.quarantine
	end
	return lines
end

-- The newest errors, oldest first: { { message, count, source } }.
function Report.Errors()
	local out, seen = {}, {}
	for _, e in ipairs(ns.Errors.list) do
		seen[e.message] = true
		out[#out + 1] = { message = e.message, count = e.count, source = "Dungeon Planner" }
	end
	local grabber = rawget(_G, "BugGrabber")
	if type(grabber) == "table" and type(grabber.GetDB) == "function" then
		local ok, db = pcall(grabber.GetDB, grabber)
		if ok and type(db) == "table" then
			local found = {}
			for _, e in ipairs(db) do
				if type(e) == "table" and type(e.message) == "string"
					and (e.message:find("DungeonPlanner", 1, true) or (type(e.stack) == "string" and e.stack:find("DungeonPlanner", 1, true))) then
					local message = ns.Errors.Clean(e.message)
					if not seen[message] then
						seen[message] = true
						found[#found + 1] = { message = message, count = tonumber(e.counter) or 1, source = "BugGrabber" }
					end
				end
			end
			for i = math.max(1, #found - Report.MAX_ERRORS + 1), #found do
				table.insert(out, 1, found[i])
			end
		end
	end
	while #out > Report.MAX_ERRORS do
		table.remove(out, 1)
	end
	return out
end

-- "gamepad" or "keyboard and mouse": the interface style the client is in (the gamepad style changes how the game reads
-- slash commands and the Escape list, which matters for bug reports on Forever).
function Report.InputStyle()
	local style, gamepad
	local api, enum = rawget(_G, "C_InputInterfaceStyle"), rawget(_G, "Enum")
	if type(api) == "table" and type(api.GetCurrentStyle) == "function" and type(enum) == "table" and type(enum.InputInterfaceStyle) == "table" then
		local ok, v = pcall(api.GetCurrentStyle)
		style = ok and v or nil
		gamepad = style ~= nil and style == enum.InputInterfaceStyle.Gamepad
	elseif type(rawget(_G, "GetCVar")) == "function" then
		local ok, v = pcall(rawget(_G, "GetCVar"), "InputDeviceInterfaceStyle")
		style = ok and v or nil
		gamepad = style ~= nil and tostring(style):lower():find("gamepad", 1, true) ~= nil
	end
	if style == nil then
		return "unknown"
	end
	return gamepad and "gamepad" or "keyboard and mouse"
end

-- Settings that differ from the defaults, "path=value" sorted, and the profile name ("custom" unless it is the stock
-- "Default": a profile is often named after a character or realm).
local function settingsDiff()
	local out = {}
	local function walk(current, defaults, path)
		for _, key in ipairs(ns.Util.SortedKeys(current)) do
			local value, default = current[key], defaults and defaults[key]
			local name = path .. key
			if type(value) == "table" then
				walk(value, type(default) == "table" and default or nil, name .. ".")
			elseif type(value) ~= "function" and value ~= default and (type(value) ~= "string" or #value <= 40) then
				out[#out + 1] = name .. "=" .. tostring(value)
			end
		end
	end
	walk(ns.db.settings, ns.Defaults.settings, "")
	local profile = ns.adb and ns.adb.GetCurrentProfile and ns.adb:GetCurrentProfile() or "Default"
	return { profile = profile == "Default" and "Default" or "custom", diff = out }
end

local function logLines()
	local out = {}
	for _, entry in ipairs(ns.LogLines(5)) do
		out[#out + 1] = entry.text
	end
	return out
end

-- Everything the report says, as plain data (nothing the player wrote).
function Report.Collect()
	local data = {
		input = guarded("input", Report.InputStyle),
		settings = guarded("settings", settingsDiff),
		log = guarded("log", logLines),
		addon = guarded("addon", addonInfo),
		client = guarded("client", ns.Compat.ClientInfo),
		language = guarded("language", languageInfo),
		instance = guarded("instance", instanceInfo),
		plan = guarded("plan", planInfo),
		window = guarded("window", windowInfo),
		integrations = guarded("integrations", integrations),
		debug = guarded("debug", debugSummary),
		errors = guarded("errors", Report.Errors),
	}
	if ns.Perf.IsRunning() or ns.Perf.HasData() then
		data.perf = guarded("perf", ns.Perf.Summary)
	end
	return data
end

-- Text ------------------------------------------------------------------------------------------------------------------

-- Characters, not bytes (Discord counts characters): UTF-8 continuation bytes do not count.
function Report.CharCount(text)
	return #text - select(2, text:gsub("[\128-\191]", ""))
end

-- What goes first when a text must fit a limit (Discord's 2000 characters); the core facts and the player's own words
-- always stay, whole.
Report.DROP_ORDER = { "perf", "log", "settings", "integrations", "debug", "errors" }

-- opts.limit: at most that many characters; sections are dropped in DROP_ORDER until it fits (errors last, and a short
-- note says what was left out). Without it, the whole report.
function Report.Text(data, what, opts)
	local blocks, out = {}, {}
	local function block(name)
		out = {}
		blocks[#blocks + 1] = { name = name, lines = out }
	end
	-- A section that failed to collect becomes one line; the rest of the report stays.
	local function put(section, fn)
		if type(section) == "table" and section.failed then
			out[#out + 1] = "(unavailable) " .. section.failed
		else
			fn(section)
		end
	end
	local function line(text)
		out[#out + 1] = text
	end
	block("core")
	line("Dungeon Planner problem report")
	put(data.addon, function(a)
		line(string.format("Addon: %s | data schema %s | share protocol %s%s", tostring(a.version), tostring(a.schema),
			tostring(a.protocol), a.readOnly and " | READ-ONLY (saved data is newer)" or ""))
	end)
	put(data.client, function(c)
		line(string.format("Client: %s build %s (toc %s) | project %s%s", tostring(c.version), tostring(c.build), tostring(c.toc),
			tostring(c.project), c.isForever and " (Forever)" or ""))
	end)
	put(data.language, function(l)
		line(string.format("Language: client %s | UI %s (setting %s) | font %s", tostring(l.client), tostring(l.active),
			tostring(l.setting), tostring(l.font)))
	end)
	put(data.instance, function(i)
		line(i.inside and string.format("Instance: %s (%s) | journal id %s | map %s | difficulty %s", tostring(i.name),
			tostring(i.kind), tostring(i.journal), tostring(i.map), tostring(i.difficulty)) or "Instance: not inside one")
	end)
	put(data.plan, function(p)
		if p.none then
			line("Plan: none selected")
			return
		end
		line(string.format("Plan: %s (%s) | revision %s | %d markers, %d routes, %d pulls, %d bosses, %d floors", p.id, p.kind,
			tostring(p.revision), p.markers, p.routes, p.pulls, p.encounters, p.floors))
		if p.steps then
			line(string.format("Step: %s of %d", p.step and tostring(p.step) or "none chosen", p.steps))
		end
	end)
	put(data.window, function(w)
		line(string.format("Window: %s | view %s | section %s | run mode %s | scale %s", w.shown and "open" or "closed",
			tostring(w.view), tostring(w.section), w.runMode and "open" or "closed", tostring(w.scale)))
	end)
	put(data.input, function(i)
		line("Input: " .. tostring(i))
	end)
	block("integrations")
	put(data.integrations, function(list)
		local bits = {}
		for _, row in ipairs(list) do
			bits[#bits + 1] = row.folder .. " " .. row.state
		end
		line("Other addons: " .. table.concat(bits, ", "))
	end)
	block("settings")
	put(data.settings, function(s)
		line("Settings (profile " .. s.profile .. ", differing from the defaults): " .. (#s.diff > 0 and table.concat(s.diff, ", ") or "none"))
	end)
	block("debug")
	line("Debug summary:")
	put(data.debug, function(lines)
		for _, text in ipairs(lines) do
			line("  " .. text)
		end
	end)
	block("errors")
	line("Lua errors and blocked actions (newest last, up to " .. Report.MAX_ERRORS .. "):")
	put(data.errors, function(list)
		if #list == 0 then
			line("  none")
		end
		for _, e in ipairs(list) do
			line(string.format("  %s%s [%s]", e.count > 1 and (e.count .. "x ") or "", e.message, e.source))
		end
	end)
	block("log")
	put(data.log, function(lines)
		if #lines > 0 then
			line("Log (last " .. #lines .. "):")
			for _, text in ipairs(lines) do
				line("  " .. text)
			end
		end
	end)
	block("perf")
	if data.perf then
		put(data.perf, function(lines)
			for _, text in ipairs(lines) do
				line(text)
			end
		end)
	end
	-- The player's words are theirs, but a name in them (their own, a friend's) is scrubbed like one anywhere else.
	local words = ns.Errors.Scrub(ns.Util.Trim(tostring(what or "")))
	local tail
	local function setTail()
		tail = "What happened:\n" .. (words ~= "" and words or "(not filled in)")
	end
	setTail()
	local function compose(dropped)
		local parts = {}
		for _, b in ipairs(blocks) do
			if not dropped[b.name] and #b.lines > 0 then
				parts[#parts + 1] = table.concat(b.lines, "\n")
			end
		end
		local left = {}
		for name in pairs(dropped) do
			left[#left + 1] = name
		end
		table.sort(left)
		if #left > 0 then
			parts[#parts + 1] = "(left out to fit: " .. table.concat(left, ", ") .. ")"
		end
		parts[#parts + 1] = tail
		return table.concat(parts, "\n")
	end
	local dropped = {}
	local text = compose(dropped)
	local limit = opts and opts.limit
	for _, name in ipairs(Report.DROP_ORDER) do
		if not limit or Report.CharCount(text) <= limit then
			break
		end
		dropped[name] = true
		text = compose(dropped)
	end
	-- Still too long with every detail gone: the player's words are cut (with an ellipsis) so the total fits.
	if limit and Report.CharCount(text) > limit then
		local keep = math.max(0, Report.CharCount(words) - (Report.CharCount(text) - limit) - 1)
		if keep < Report.CharCount(words) then
			words = charSub(words, keep) .. "\226\128\166"
			setTail()
			text = compose(dropped)
		end
	end
	return text
end

-- /dp report [text]
function Report.Open()
	ns.ReportFrame.Show()
end
