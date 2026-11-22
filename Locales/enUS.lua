-- Localization. English text is the key itself, so a missing translation shows English, never a blank.
-- Other languages add a table to ns.Locales (Locales/<code>.lua, Locales/README.md). AceLocale-3.0 is not used on
-- purpose: it picks the language from GetLocale() once at load, and WoW has no Polish client - WoW Po Polsku runs on an
-- English client - so the language has to be chosen at runtime (settings: Automatic or a language of ns.LOCALE_LIST).
-- tools/locale_keys.lua checks coverage.

local _, ns = ...

ns.Locales = ns.Locales or {}

-- English: only keys whose text differs from the key (internal names, slot codes) and the key-binding strings.
ns.Locales.enUS = {
	["ability:interrupt"] = "Interrupt",
	["ability:dispel"] = "Dispel",
	["ability:tank"] = "Tank",
	["ability:healer"] = "Healer",
	["ability:enrage"] = "Enrage",
	["ability:deadly"] = "Deadly",
	["ability:bleed"] = "Bleed",
	["ability:control"] = "Crowd control",
	["ability:aoe"] = "Area damage",
	["ability:adds"] = "Summons",
	boss = "Boss",
	rare = "Rare",
	pack = "Pack",
	patrol = "Patrol",
	loot = "Loot",
	chest = "Chest",
	quest_item = "Quest item",
	quest_npc = "Quest giver",
	npc = "NPC",
	interactive = "Interactive object",
	entrance = "Entrance",
	exit = "Exit",
	shortcut = "Shortcut",
	stairs = "Stairs or passage",
	hazard = "Hazard",
	position = "Position",
	note = "Note",
	["role:TANK"] = "Tank",
	["role:HEALER"] = "Healer",
	["role:MELEE"] = "Melee",
	["role:RANGED"] = "Ranged",
	["slot:HEAD"] = "Head",
	["slot:NECK"] = "Neck",
	["slot:SHOULDER"] = "Shoulder",
	["slot:BACK"] = "Back",
	["slot:CHEST"] = "Chest",
	["slot:WRIST"] = "Wrist",
	["slot:HANDS"] = "Hands",
	["slot:WAIST"] = "Waist",
	["slot:LEGS"] = "Legs",
	["slot:FEET"] = "Feet",
	["slot:FINGER"] = "Finger",
	["slot:TRINKET"] = "Trinket",
	["slot:MAINHAND"] = "Main hand",
	["slot:OFFHAND"] = "Off hand",
	["slot:TWOHAND"] = "Two-hand",
	["slot:RANGED"] = "Ranged",
	["party:open"] = "Open", -- an empty seat in the party strip
	-- Pull tags and planned marks (Schema.PULL_TAGS, cd, lust): full names in the Pulls editor, short ones in lists.
	["tag:interrupt"] = "Interrupt",
	["tag:cc"] = "Crowd control",
	["tag:los"] = "Line of sight",
	["tag:next"] = "Pull with next",
	["tag:skip"] = "Skip",
	["tag:careful"] = "Careful",
	["tag:cd"] = "Cooldowns",
	["tag:lust"] = "Bloodlust / Heroism",
	["tagShort:interrupt"] = "Interrupt",
	["tagShort:cc"] = "CC",
	["tagShort:los"] = "LoS",
	["tagShort:next"] = "+ next",
	["tagShort:skip"] = "Skip",
	["tagShort:careful"] = "Careful",
	["tagShort:cd"] = "CDs",
	["tagShort:lust"] = "Lust",
	-- A recommended plan's research confidence (its "confidence: <level>" tag).
	["confidence:low"] = "low",
	["confidence:medium"] = "medium",
	["confidence:high"] = "high",
	-- Map drawing tools (Model/Drawing.lua kinds) and widths.
	["draw:pen"] = "Pen",
	["draw:line"] = "Line",
	["draw:arrow"] = "Arrow",
	["draw:circle"] = "Circle",
	["draw:rect"] = "Box",
	["draw:text"] = "Text",
	["draw:erase"] = "Eraser",
	["draw:move"] = "Move",
	["width:1"] = "Thin",
	["width:2"] = "Medium",
	["width:3"] = "Thick",
	BINDING_HEADER_DUNGEONPLANNER = "Dungeon Planner",
	BINDING_NAME_DUNGEONPLANNER_TOGGLE = "Open or close the planner",
	BINDING_NAME_DUNGEONPLANNER_MAP = "Open the plan's map",
	BINDING_NAME_DUNGEONPLANNER_NEXT_PULL = "Next pull",
	BINDING_NAME_DUNGEONPLANNER_PREVIOUS_PULL = "Previous pull",
	BINDING_NAME_DUNGEONPLANNER_RUN_MODE = "Toggle run mode",
	BINDING_NAME_DUNGEONPLANNER_BOSS_KILLED = "Mark the next boss killed",
	BINDING_NAME_DUNGEONPLANNER_SHARE_GROUP = "Share the plan with my group",
}

local active = ns.Locales.enUS

ns.L = setmetatable({}, {
	__index = function(_, key)
		local value = active[key]
		if value == nil then
			value = ns.Locales.enUS[key]
		end
		if value ~= nil then
			return value
		end
		return key
	end,
	__newindex = function()
		error("ns.L is read-only; add strings to a Locales file")
	end,
})

-- The languages the picker offers (Settings, the window's gear menu): code, the language's own name. Spanish has one
-- translation, shared by esES and esMX clients (LOCALE_ALIAS). "Русский" is followed by its English name because a
-- Latin-only game face draws Cyrillic as boxes, and the menu must still be readable then.
ns.LOCALE_LIST = {
	{ "enUS", "English" },
	{ "deDE", "Deutsch" },
	{ "esES", "Español" },
	{ "frFR", "Français" },
	{ "plPL", "Polski" },
	{ "ruRU", "Русский (Russian)" },
}
local LOCALE_ALIAS = { enGB = "enUS", esMX = "esES" }

-- Plurals. A plural string lists its forms separated by "|". English, German and Spanish have two ("%d plan|%d plans":
-- 1, other); French has two too, but 0 is singular as well (0 plan, 1 plan, 2 plans). Polish and Russian have three
-- ("%d plan|%d plany|%d planów": 1; 2-4 except 12-14; everything else, 0 included). Russian differs from Polish in its
-- first form, which is also used for 21, 31, ... (not 11). Use it as
--   ns.Plural(n, L["%d plan|%d plans"])
-- so tools/locale_keys.lua sees the key. Extra arguments follow the count in string.format. Missing forms fall back to
-- the last one given.
local function oneOrOther(n)
	return n == 1 and 1 or 2
end
local function fewForms(n, oneForm)
	if oneForm then
		return 1
	end
	local last, lastTwo = n % 10, n % 100
	if last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) then
		return 2
	end
	return 3
end
local PLURAL_RULES = {
	enUS = oneOrOther,
	deDE = oneOrOther,
	esES = oneOrOther,
	frFR = function(n)
		return n <= 1 and 1 or 2
	end,
	plPL = function(n)
		return fewForms(n, n == 1)
	end,
	ruRU = function(n)
		return fewForms(n, n % 10 == 1 and n % 100 ~= 11)
	end,
}
ns.PLURAL_RULES = PLURAL_RULES

function ns.PluralForm(n, code)
	code = code or ns.activeLocale or "enUS"
	local rule = PLURAL_RULES[LOCALE_ALIAS[code] or code] or PLURAL_RULES.enUS
	return rule(math.abs(math.floor(tonumber(n) or 0)))
end

function ns.Plural(n, forms, ...)
	local list = {}
	for form in tostring(forms):gmatch("[^|]+") do
		list[#list + 1] = form
	end
	local text = list[math.min(ns.PluralForm(n), #list)] or tostring(forms)
	if text:find("%", 1, true) then
		return string.format(text, n, ...)
	end
	return text
end

-- Choose the language. `code` is "auto" or a locale code of ns.LOCALE_LIST. "auto" follows the client's GetLocale()
-- when we have that language (enGB is English, esMX is Spanish), except that a loaded WoW Po Polsku (set to Polish)
-- means Polish, because that translation runs on an English client. Any other client language gets English.
function ns.SetLocale(code)
	if code == nil or code == "auto" then
		code = (GetLocale and GetLocale()) or "enUS"
		if ns.Integrations and ns.Integrations.PolishTranslationLoaded() then
			code = "plPL"
		end
	end
	code = LOCALE_ALIAS[code] or code
	active = ns.Locales[code] or ns.Locales.enUS
	ns.activeLocale = ns.Locales[code] and code or "enUS"
	return ns.activeLocale
end

-- Key-binding labels are globals the Key Bindings UI reads (BINDING_HEADER_* / BINDING_NAME_*).
function ns.ApplyBindingStrings()
	if not _G then
		return
	end
	for key in pairs(ns.Locales.enUS) do
		if key:match("^BINDING_") then
			_G[key] = ns.L[key]
		end
	end
end
