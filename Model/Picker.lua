-- The instance picker's list, pure (UI/InstancePicker.lua draws it): which instances go under Dungeons and which under
-- Raids, the level bands that divide the dungeons, the search filter and the keyboard cursor.
--
-- rows = { { kind = "header", lo?, hi?, other? } | { kind = "item", entry } }, in the order given (the caller sorts by
-- level). A header opens each level band (lo..hi, BAND levels wide, from the instance's lowest level); instances
-- without a level come last under one header with other = true. Raids get no bands: they share one level.

local _, ns = ...
local Picker = ns:NewModule("Picker")

Picker.BAND = 10

-- "raid" or "dungeon" (zones and custom maps are listed with the dungeons).
function Picker.Section(entry)
	return entry and entry.kind == "raid" and "raid" or "dungeon"
end

-- Lower case, letters and digits only: "Zul'Farrak" and "zul farrak" match. Bytes above 127 (UTF-8 letters) stay.
function Picker.Norm(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:lower():gsub("[%c%p%s]", ""))
end

local function trim(s)
	return type(s) == "string" and s:match("^%s*(.-)%s*$") or ""
end

-- Is an instance new in WoW: Forever (its recommended plan's instance.origin, docs/DATA-SOURCES.md)?
function Picker.IsForever(entry)
	return type(entry) == "table" and entry.origin == "forever"
end

-- Does an instance match the search text? By name, a level number inside its range ("30" finds what a level-30
-- character can run), or "forever" (at least its first three letters) for the instances new in WoW: Forever.
function Picker.Matches(entry, query)
	query = trim(query)
	if query == "" then
		return true
	end
	local level = tonumber(query)
	if level and entry.levelLo then
		return level >= entry.levelLo and level <= (entry.levelHi or entry.levelLo)
	end
	local q = Picker.Norm(query)
	if q == "" then
		return false
	end
	if Picker.Norm(entry.name):find(q, 1, true) ~= nil then
		return true
	end
	return #q >= 3 and Picker.IsForever(entry) and ("forever"):sub(1, #q) == q
end

-- The band a level falls in: 13 -> 10, 19.
function Picker.Band(level, size)
	size = size or Picker.BAND
	local lo = math.floor(level / size) * size
	return lo, lo + size - 1
end

-- The rows of one section for a search text, and how many instances match in each section (for the tabs).
-- opts: section ("dungeon" | "raid"), query, bands (default true; raids never get bands).
function Picker.Rows(entries, opts)
	opts = opts or {}
	local section = opts.section or "dungeon"
	local banded = opts.bands ~= false and section == "dungeon"
	local rows, counts = {}, { dungeon = 0, raid = 0 }
	local band
	for _, entry in ipairs(entries or {}) do
		if Picker.Matches(entry, opts.query) then
			local s = Picker.Section(entry)
			counts[s] = counts[s] + 1
			if s == section then
				if banded then
					local key = entry.levelLo and Picker.Band(entry.levelLo) or "other"
					if key ~= band then
						band = key
						if entry.levelLo then
							local lo, hi = Picker.Band(entry.levelLo)
							rows[#rows + 1] = { kind = "header", lo = lo, hi = hi }
						else
							rows[#rows + 1] = { kind = "header", other = true }
						end
					end
				end
				rows[#rows + 1] = { kind = "item", entry = entry }
			end
		end
	end
	return rows, counts
end

local function isItem(rows, i)
	return rows[i] ~= nil and rows[i].kind == "item"
end

-- Move the cursor (an index into rows) by delta items, skipping headers and stopping at the ends. Without a cursor,
-- down starts at the first item and up at the last. nil when there is no item at all.
function Picker.Step(rows, index, delta)
	local n = #rows
	if not index or not isItem(rows, index) then
		local from, to, dir = 1, n, 1
		if delta < 0 then
			from, to, dir = n, 1, -1
		end
		for i = from, to, dir do
			if isItem(rows, i) then
				return i
			end
		end
		return nil
	end
	local dir = delta < 0 and -1 or 1
	local result, i = index, index
	for _ = 1, math.abs(delta) do
		local j = i + dir
		while j >= 1 and j <= n and not isItem(rows, j) do
			j = j + dir
		end
		if j < 1 or j > n then
			break
		end
		i, result = j, j
	end
	return result
end

-- The row index of the instance with this key, or nil.
function Picker.Find(rows, key)
	if key == nil then
		return nil
	end
	for i, row in ipairs(rows) do
		if row.kind == "item" and row.entry.key == key then
			return i
		end
	end
	return nil
end

-- The section to show when the search text changes: the current one while it has matches, else the other one if it
-- has any.
function Picker.SectionFor(current, counts)
	local other = current == "raid" and "dungeon" or "raid"
	if (counts[current] or 0) == 0 and (counts[other] or 0) > 0 then
		return other
	end
	return current
end
