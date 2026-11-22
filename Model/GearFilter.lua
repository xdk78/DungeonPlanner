-- The Gear page's filters over drops, pure: which classes can equip an item, by the item's class and subclass (the
-- client's item class enums, read from the item with GetItemInfoInstant: Data/Loot.lua's Loot.ItemType), and whether
-- an item matches a filter { class = class file ("WARRIOR"), slot = Schema slot }.
--
-- The rule is what the class can wear and wield at full level, by the current client's class rules: armor up to the
-- class's heaviest type (cloth for everyone, leather, mail, plate), shields, relics and the weapon types the class can
-- use. Cloaks, rings, necklaces, trinkets and held-in-off-hand items (the armor subclasses "miscellaneous" and the
-- cloak's cloth) suit every class. Items that are not armor or weapons (quest items, recipes, reagents) are not class
-- gear and pass the class filter. A class this table does not know (a client with another class list) is not filtered.
-- Not modelled: the level at which a class may start wearing mail or plate, and whether WoW: Forever follows the
-- classic rules here (mail and plate from level 40, no one-handed axes for rogues, no polearms for druids); that is
-- listed in docs/UI.md, "Needs a look in game", so the table can be adjusted once checked.
--
--   GearFilter.CanEquip(classFile, itemType) -> true | false | nil (nil: the item's type is not known yet)
--   GearFilter.Match(filter, itemType)       -> true | false | nil (nil: cannot tell until the item loads)
--
-- itemType = { classID, subclassID, slot, alsoSlot? } (Loot.ItemType: a one-hand weapon also fits the off hand), or
-- nil while the client has no data for the item.

local _, ns = ...
local GearFilter = ns:NewModule("GearFilter")

-- The client's Enum.ItemClass / Enum.ItemArmorSubclass / Enum.ItemWeaponSubclass, with their documented values for a
-- client (or a test) without the Enum tables.
local function enum(name, key, default)
	local e = rawget(_G, "Enum")
	local t = type(e) == "table" and rawget(e, name)
	local v = type(t) == "table" and rawget(t, key)
	return type(v) == "number" and v or default
end

local CLASS_WEAPON = enum("ItemClass", "Weapon", 2)
local CLASS_ARMOR = enum("ItemClass", "Armor", 4)
GearFilter.CLASS_WEAPON, GearFilter.CLASS_ARMOR = CLASS_WEAPON, CLASS_ARMOR

local A = {
	misc = enum("ItemArmorSubclass", "Generic", 0),
	cloth = enum("ItemArmorSubclass", "Cloth", 1),
	leather = enum("ItemArmorSubclass", "Leather", 2),
	mail = enum("ItemArmorSubclass", "Mail", 3),
	plate = enum("ItemArmorSubclass", "Plate", 4),
	cosmetic = enum("ItemArmorSubclass", "Cosmetic", 5),
	shield = enum("ItemArmorSubclass", "Shield", 6),
	libram = enum("ItemArmorSubclass", "Libram", 7),
	idol = enum("ItemArmorSubclass", "Idol", 8),
	totem = enum("ItemArmorSubclass", "Totem", 9),
	sigil = enum("ItemArmorSubclass", "Sigil", 10),
	relic = enum("ItemArmorSubclass", "Relic", 11),
}

local Wp = {
	axe1 = enum("ItemWeaponSubclass", "Axe1H", 0),
	axe2 = enum("ItemWeaponSubclass", "Axe2H", 1),
	bow = enum("ItemWeaponSubclass", "Bows", 2),
	gun = enum("ItemWeaponSubclass", "Guns", 3),
	mace1 = enum("ItemWeaponSubclass", "Mace1H", 4),
	mace2 = enum("ItemWeaponSubclass", "Mace2H", 5),
	polearm = enum("ItemWeaponSubclass", "Polearm", 6),
	sword1 = enum("ItemWeaponSubclass", "Sword1H", 7),
	sword2 = enum("ItemWeaponSubclass", "Sword2H", 8),
	warglaive = enum("ItemWeaponSubclass", "Warglaive", 9),
	staff = enum("ItemWeaponSubclass", "Staff", 10),
	fist = enum("ItemWeaponSubclass", "Unarmed", 13),
	generic = enum("ItemWeaponSubclass", "Generic", 14),
	dagger = enum("ItemWeaponSubclass", "Dagger", 15),
	thrown = enum("ItemWeaponSubclass", "Thrown", 16),
	crossbow = enum("ItemWeaponSubclass", "Crossbow", 18),
	wand = enum("ItemWeaponSubclass", "Wand", 19),
	fishing = enum("ItemWeaponSubclass", "Fishingpole", 20),
}

local function set(names, from)
	local out = {}
	for _, n in ipairs(names) do
		out[from[n]] = true
	end
	return out
end

-- Per class: the heaviest armor, the extra armor subclasses (shield, relic), the weapon subclasses.
local ARMOR_ORDER = { A.cloth, A.leather, A.mail, A.plate }
local RULES = {
	WARRIOR = { armor = A.plate, extra = { "shield" }, weapons = { "axe1", "axe2", "mace1", "mace2", "sword1", "sword2",
		"polearm", "staff", "dagger", "fist", "bow", "crossbow", "gun", "thrown" } },
	PALADIN = { armor = A.plate, extra = { "shield", "libram" }, weapons = { "axe1", "axe2", "mace1", "mace2", "sword1",
		"sword2", "polearm" } },
	HUNTER = { armor = A.mail, weapons = { "axe1", "axe2", "sword1", "sword2", "polearm", "staff", "dagger", "fist",
		"bow", "crossbow", "gun", "thrown" } },
	ROGUE = { armor = A.leather, weapons = { "dagger", "fist", "axe1", "mace1", "sword1", "bow", "crossbow", "gun",
		"thrown" } },
	PRIEST = { armor = A.cloth, weapons = { "dagger", "mace1", "staff", "wand" } },
	SHAMAN = { armor = A.mail, extra = { "shield", "totem" }, weapons = { "axe1", "axe2", "mace1", "mace2", "dagger",
		"fist", "staff" } },
	MAGE = { armor = A.cloth, weapons = { "dagger", "sword1", "staff", "wand" } },
	WARLOCK = { armor = A.cloth, weapons = { "dagger", "sword1", "staff", "wand" } },
	DRUID = { armor = A.leather, extra = { "idol" }, weapons = { "dagger", "fist", "mace1", "mace2", "polearm", "staff" } },
	DEATHKNIGHT = { armor = A.plate, extra = { "sigil" }, weapons = { "axe1", "axe2", "mace1", "mace2", "sword1",
		"sword2", "polearm" } },
	MONK = { armor = A.leather, weapons = { "axe1", "mace1", "sword1", "fist", "polearm", "staff" } },
	DEMONHUNTER = { armor = A.leather, weapons = { "warglaive", "axe1", "sword1", "fist" } },
	EVOKER = { armor = A.mail, weapons = { "axe1", "axe2", "mace1", "mace2", "sword1", "sword2", "dagger", "fist",
		"staff" } },
}
-- Every class: rings, necklaces, trinkets, held-in-off-hand (misc), cosmetic armor, generic relics, the generic and
-- fishing "weapons".
local ANY_ARMOR = { [A.misc] = true, [A.cosmetic] = true, [A.relic] = true }
local ANY_WEAPON = { [Wp.generic] = true, [Wp.fishing] = true }

local compiled = {}
for file, r in pairs(RULES) do
	local armor = set(r.extra or {}, A)
	for _, sub in ipairs(ARMOR_ORDER) do
		armor[sub] = true
		if sub == r.armor then
			break
		end
	end
	compiled[file] = { armor = armor, weapons = set(r.weapons, Wp) }
end

function GearFilter.Knows(classFile)
	return compiled[classFile] ~= nil
end

function GearFilter.CanEquip(classFile, itemType)
	local rules = classFile and compiled[classFile]
	if not rules then
		return true
	end
	if type(itemType) ~= "table" or type(itemType.classID) ~= "number" then
		return nil
	end
	local sub = itemType.subclassID
	if itemType.classID == CLASS_ARMOR then
		-- A cloak is cloth for every class.
		return ANY_ARMOR[sub] or itemType.slot == "BACK" or rules.armor[sub] or false
	elseif itemType.classID == CLASS_WEAPON then
		return ANY_WEAPON[sub] or rules.weapons[sub] or false
	end
	return true
end

function GearFilter.Match(filter, itemType)
	filter = filter or {}
	if not filter.class and not filter.slot then
		return true
	end
	if type(itemType) ~= "table" then
		return nil
	end
	if filter.slot and itemType.slot ~= filter.slot and itemType.alsoSlot ~= filter.slot then
		return false
	end
	if filter.class then
		return GearFilter.CanEquip(filter.class, itemType)
	end
	return true
end
