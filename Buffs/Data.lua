-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- The buff catalog: which self-buffs are worth having, and what gives each one.
-- No game API in this file.
--
-- Items, required levels and effects are WoW: Forever's own (patch 1.60.1), read from Wowhead's
-- Forever item tooltips in November 2026; many changed from the original game (Crab Cake is a
-- level 5 Intellect food now, Heavy Sharpening Stone needs level 15, and so on). When the game
-- has an item's details cached, its real "Requires Level" is used instead.
--
-- A group is one slot of benefit: only one buff from a group counts at a time
-- (one weapon buff per weapon, one Well Fed, one agility elixir, one mage armor...).
--   key      saved under this name (mute list)
--   label    what the reminder says is missing
--   kind     "weapon" (temporary weapon enchant on slot), "aura" (a buff on you), "tracking"
--   auras    buff names that count as having it (item use-spell names are added at runtime)
--   blockedBy  buff names that already cover this one (they do not stack)
--   classes  only for these classes (classFile names)
--   optional an extra (elixirs, scrolls): reminded only when it is in your bags
--   food     the Well Fed group: any Well Fed food you carry counts too (see Game.lua)
--   options  what gives it: { item = id, name, level, stats, weapon, classes, source }
--                        or { spell = name, id = spell id, level, stats, talent, classes }
--            stats are what it gives; Spec.lua turns them into a score for your spec.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D = {}
ns.Data = D

-- Weapon item subclass ids -> what kind of edge it has. Missing ones (bows, guns, wands,
-- fishing poles, thrown) take no stone or oil.
D.WEAPON = {
	[0] = "sharp", [1] = "sharp", [6] = "sharp", [7] = "sharp", [8] = "sharp", [13] = "sharp", [15] = "sharp",
	[4] = "blunt", [5] = "blunt", [10] = "blunt",
}

local BS = "Blacksmiths make these; also on the Auction House"
local EN = "Enchanters make these; also on the Auction House"
local AL = "Alchemists make these; also on the Auction House"
D.COOK = "Cooking (a trainer or vendor recipe, or caught and cooked fish); also on the Auction House"
local SC = "Found as loot from humanoids; also on the Auction House"
local PO = "Make them with your Poisons skill; reagents from poison vendors in rogue areas"

local function weaponOptions()
	return {
		{ item = 2862, name = "Rough Sharpening Stone", level = 1, weapon = "sharp", stats = { wdmg = 2 }, source = BS },
		{ item = 2863, name = "Coarse Sharpening Stone", level = 5, weapon = "sharp", stats = { wdmg = 3 }, source = BS },
		{ item = 2871, name = "Heavy Sharpening Stone", level = 15, weapon = "sharp", stats = { wdmg = 4 }, source = BS },
		{ item = 7964, name = "Solid Sharpening Stone", level = 25, weapon = "sharp", stats = { wdmg = 6 }, source = BS },
		{ item = 12404, name = "Dense Sharpening Stone", level = 35, weapon = "sharp", stats = { wdmg = 8 }, source = BS },
		{ item = 18262, name = "Elemental Sharpening Stone", level = 50, stats = { mcrit = 2, wdmg = 0.01 }, source = "Blacksmiths (recipe from Molten Core); Auction House" },
		{ item = 3239, name = "Rough Weightstone", level = 1, weapon = "blunt", stats = { wdmg = 2 }, source = BS },
		{ item = 3240, name = "Coarse Weightstone", level = 5, weapon = "blunt", stats = { wdmg = 3 }, source = BS },
		{ item = 3241, name = "Heavy Weightstone", level = 15, weapon = "blunt", stats = { wdmg = 4 }, source = BS },
		{ item = 7965, name = "Solid Weightstone", level = 25, weapon = "blunt", stats = { wdmg = 6 }, source = BS },
		{ item = 12643, name = "Dense Weightstone", level = 35, weapon = "blunt", stats = { wdmg = 8 }, source = BS },
		{ item = 20744, name = "Minor Wizard Oil", level = 5, stats = { sd = 8 }, source = EN },
		{ item = 20746, name = "Lesser Wizard Oil", level = 30, stats = { sd = 16 }, source = EN },
		{ item = 20750, name = "Wizard Oil", level = 40, stats = { sd = 24 }, source = EN },
		{ item = 20749, name = "Brilliant Wizard Oil", level = 45, stats = { sd = 36, scrit = 1 }, source = EN },
		{ item = 20745, name = "Minor Mana Oil", level = 20, stats = { mp5 = 5, heal = 10 }, source = EN },
		{ item = 20747, name = "Lesser Mana Oil", level = 40, stats = { mp5 = 10, heal = 20 }, source = EN },
		{ item = 20748, name = "Brilliant Mana Oil", level = 45, stats = { mp5 = 15, heal = 25 }, source = EN },
		{ item = 6947, name = "Instant Poison", level = 20, stats = { poison = 20 }, classes = { ROGUE = true }, source = PO },
		{ item = 6949, name = "Instant Poison II", level = 28, stats = { poison = 28 }, classes = { ROGUE = true }, source = PO },
		{ item = 6950, name = "Instant Poison III", level = 36, stats = { poison = 36 }, classes = { ROGUE = true }, source = PO },
		{ item = 8926, name = "Instant Poison IV", level = 44, stats = { poison = 44 }, classes = { ROGUE = true }, source = PO },
		{ item = 8927, name = "Instant Poison V", level = 52, stats = { poison = 52 }, classes = { ROGUE = true }, source = PO },
		{ item = 8928, name = "Instant Poison VI", level = 60, stats = { poison = 60 }, classes = { ROGUE = true }, source = PO },
		{ spell = "Windfury Weapon", id = 8232, level = 30, stats = { imbue = 70 }, classes = { SHAMAN = true } },
		{ spell = "Flametongue Weapon", id = 8024, level = 10, stats = { imbue = 69 }, classes = { SHAMAN = true } },
		{ spell = "Rockbiter Weapon", id = 8017, level = 1, stats = { imbue = 68 }, classes = { SHAMAN = true } },
	}
end

-- Every WoW: Forever food that makes you Well Fed with a stat: { id, name, level, stats }.
-- All of them also give 5% more experience from kills. Zone-only foods (Westfall Stew,
-- Sweetpaw Jam) and fishing or herbalism skill foods are left out.
D.FOODS = {
	{ 787, "Slitherskin Mackerel", 1, { ap = 6 } },
	{ 2680, "Spiced Wolf Meat", 1, { agi = 1 } },
	{ 2681, "Roasted Boar Meat", 1, { str = 1 } },
	{ 2888, "Beer Basted Boar Ribs", 1, { str = 1 } },
	{ 3663, "Murloc Fin Soup", 1, { sta = 1 } },
	{ 2682, "Cooked Crab Claw", 1, { int = 1 } },
	{ 5472, "Kaldorei Spider Kabob", 1, { sta = 1 } },
	{ 5474, "Roasted Kodo Meat", 1, { sta = 1 } },
	{ 5477, "Strider Stew", 1, { int = 1 } },
	{ 6290, "Brilliant Smallfish", 1, { ap = 2 } },
	{ 6890, "Smoked Bear Meat", 1, { str = 1 } },
	{ 6888, "Herb Baked Egg", 1, { sta = 1 } },
	{ 7806, "Lollipop", 1, { sta = 2, spi = 2 } },
	{ 7808, "Chocolate Square", 1, { sta = 2, spi = 2 } },
	{ 7807, "Candy Bar", 1, { sta = 2, spi = 2 } },
	{ 11584, "Cactus Apple Surprise", 1, { sta = 2, spi = 2 } },
	{ 12224, "Crispy Bat Wing", 1, { int = 1 } },
	{ 17197, "Gingerbread Cookie", 1, { sta = 2, spi = 2 } },
	{ 17198, "Egg Nog", 1, { sta = 2, spi = 2 } },
	{ 20516, "Bobbing Apple", 1, { sta = 1, spi = 1 } },
	{ 21254, "Winter Veil Cookie", 1, { sta = 1, spi = 1 } },
	{ 249865, "Peace Tea", 1, { heal = 2 } },
	{ 249871, "Venomous Smoothie", 1, { spi = 1 } },
	{ 250079, "Tasty Raptor Bites", 1, { int = 1 } },
	{ 724, "Goretusk Liver Pie", 5, { str = 3 } },
	{ 1082, "Redridge Goulash", 5, { int = 3 } },
	{ 2684, "Coyote Steak", 5, { agi = 3 } },
	{ 2683, "Crab Cake", 5, { int = 3 } },
	{ 2687, "Dry Pork Ribs", 5, { str = 3 } },
	{ 3220, "Blood Sausage", 5, { str = 3 } },
	{ 3726, "Big Bear Steak", 5, { str = 3 } },
	{ 3662, "Crocolisk Steak", 5, { agi = 3 } },
	{ 4592, "Longjaw Mud Snapper", 5, { ap = 10 } },
	{ 5095, "Rainbow Fin Albacore", 5, { sd = 1 } },
	{ 5479, "Crispy Lizard Tail", 5, { sta = 3 } },
	{ 12213, "Carrion Surprise", 5, { sta = 3 } },
	{ 249866, "Royal Tea", 5, { heal = 7 } },
	{ 249872, "Slimy Smoothie", 5, { spi = 3 } },
	{ 250077, "Twice-Spiced Raptor Slice", 5, { int = 3 } },
	{ 250080, "Breakfast Omelette", 5, { sta = 3 } },
	{ 263509, "Skywall Souffle", 5, { sta = 1 } },
	{ 263512, "Pincer Bites", 5, { int = 1 } },
	{ 268912, "Expiring Crab Cake", 5, { sta = 3 } },
	{ 268913, "Expiring Crocolisk Steak", 5, { sta = 3 } },
	{ 21072, "Smoked Sagefish", 10, { sd = 4 } },
	{ 1017, "Seasoned Wolf Kabob", 15, { agi = 5 } },
	{ 2685, "Succulent Pork Ribs", 15, { str = 5 } },
	{ 3664, "Crocolisk Gumbo", 15, { agi = 5 } },
	{ 3666, "Gooey Spider Cake", 15, { sta = 5 } },
	{ 3727, "Hot Lion Chops", 15, { agi = 5 } },
	{ 3665, "Curiously Tasty Omelet", 15, { sta = 5 } },
	{ 3729, "Soothing Turtle Bisque", 15, { sta = 5 } },
	{ 5480, "Lean Venison", 15, { str = 5 } },
	{ 5527, "Goblin Deviled Clams", 15, { sta = 6, spi = 6 } },
	{ 12209, "Lean Wolf Steak", 15, { agi = 5 } },
	{ 12210, "Roast Raptor", 15, { int = 5 } },
	{ 12214, "Mystery Stew", 15, { sta = 5 } },
	{ 249867, "Root Tea", 15, { heal = 11 } },
	{ 249873, "Mrrggl Smrrthle", 15, { spi = 5 } },
	{ 3728, "Tasty Lion Steak", 25, { agi = 10 } },
	{ 4457, "Barbecued Buzzard Wing", 25, { int = 10 } },
	{ 6038, "Giant Clam Scorcho", 25, { sta = 10 } },
	{ 8364, "Mithril Head Trout", 25, { ap = 20 } },
	{ 12215, "Heavy Kodo Stew", 25, { sta = 10 } },
	{ 12216, "Spiced Chili Crab", 25, { int = 10 } },
	{ 13851, "Hot Wolf Ribs", 25, { agi = 10 } },
	{ 20074, "Heavy Crocolisk Stew", 25, { agi = 10 } },
	{ 249868, "Triage Tea", 25, { heal = 22 } },
	{ 249874, "Calcified Smoothie", 25, { spi = 10 } },
	{ 250074, "Bear Brisket", 25, { str = 10 } },
	{ 250073, "Raging Raptor Ribs", 25, { int = 10 } },
	{ 250078, "Giant Scrambled Eggs", 25, { sta = 10 } },
	{ 274971, "Briny Seafood Stew", 25, { sd = 14 } },
	{ 274976, "Plain Ol' Paletusk", 25, { str = 10 } },
	{ 21217, "Sagefish Delight", 30, { sd = 7 } },
	{ 6887, "Spotted Yellowtail", 35, { sd = 22 } },
	{ 12218, "Monster Omelet", 35, { sta = 15 } },
	{ 12212, "Jungle Stew", 35, { agi = 15 } },
	{ 13927, "Cooked Glossy Mightfish", 35, { ap = 30 } },
	{ 13928, "Grilled Squid", 35, { acrit = 1 } },
	{ 13931, "Nightfin Soup", 35, { sd = 22 } },
	{ 13932, "Poached Sunscale Salmon", 35, { ap = 40 } },
	{ 13929, "Hot Smoked Bass", 35, { acrit = 1 } },
	{ 17222, "Spider Sausage", 35, { sta = 15 } },
	{ 18045, "Tender Wolf Steak", 35, { agi = 15 } },
	{ 18254, "Runn Tum Tuber Surprise", 35, { int = 15 } },
	{ 249869, "Sunny Tea", 35, { heal = 33 } },
	{ 249875, "Spicy Smoothie", 35, { spi = 15 } },
	{ 250065, "Savory Stag Sliders", 35, { str = 15 } },
	{ 250076, "Raptor Rouladen", 35, { int = 15 } },
	{ 286152, "Plated Armorfish", 35, { armor = 150 } },
	{ 16971, "Clamlette Surprise", 40, { sta = 12, spi = 12 } },
	{ 13933, "Lobster Stew", 45, { sd = 28 } },
	{ 13935, "Baked Salmon", 45, { sd = 28 } },
	{ 13934, "Mightfish Steak", 45, { ap = 40 } },
	{ 20452, "Smoked Desert Dumplings", 45, { str = 20 } },
	{ 21023, "Dirge's Kickin' Chimaerok Chops", 45, { sta = 25 } },
	{ 249870, "Sage's Tea", 45, { heal = 44 } },
	{ 250066, "Soaring Pamplona", 45, { int = 20 } },
	{ 249876, "Wicked Smoothie", 45, { spi = 20 } },
	{ 250067, "Bat Hachee", 45, { int = 20 } },
	{ 250071, "Steaming Stag Steak", 45, { str = 20 } },
	{ 250068, "Savory Turtle Stew", 45, { sta = 20 } },
	{ 250070, "Bear Bruscitti", 45, { str = 20 } },
	{ 250069, "Flank au Poivre", 45, { agi = 20 } },
	{ 250072, "Swiftstrike Steak", 45, { agi = 20 } },
	{ 250075, "Prehistoric Pulled Raptor", 45, { int = 20 } },
	{ 238638, "Filet o' Flank", 55, { agi = 25, sta = 10 } },
}

local function foodOptions()
	local out = {}
	for _, f in ipairs(D.FOODS) do
		out[#out + 1] = { item = f[1], name = f[2], level = f[3], stats = f[4], source = D.COOK }
	end
	return out
end

local function elixirs(key, label, list, extra)
	local g = { key = key, label = label, kind = "aura", optional = true, options = list }
	for k, v in pairs(extra or {}) do g[k] = v end
	for _, o in ipairs(list) do o.source = o.source or AL end
	return g
end

-- { id, level, amount } for tiers I to IV
local function scrolls(key, stat, statKey, list, blockedBy, aura)
	local out = {}
	for i, s in ipairs(list) do
		out[i] = { item = s[1], name = "Scroll of " .. stat .. ({ "", " II", " III", " IV" })[i], level = s[2], stats = { [statKey] = s[3] }, source = SC }
	end
	return { key = key, label = "Scroll of " .. stat, kind = "aura", optional = true, auras = { aura or stat }, blockedBy = blockedBy, options = out }
end

local function spells(key, label, classes, list, extra)
	local g = { key = key, label = label, kind = "aura", classes = classes, options = list }
	for k, v in pairs(extra or {}) do g[k] = v end
	return g
end

D.GROUPS = {
	{ key = "weapon", label = "Weapon buff (main hand)", kind = "weapon", slot = 16, options = weaponOptions() },
	{ key = "offhand", label = "Weapon buff (off hand)", kind = "weapon", slot = 17, options = weaponOptions() },
	{ key = "tracking", label = "Gathering tracking", kind = "tracking", options = {
		{ spell = "Find Minerals", id = 2580, level = 1, tier = 3 },
		{ spell = "Find Herbs", id = 2383, level = 1, tier = 2 },
		{ spell = "Find Treasure", id = 2481, level = 1 },
	} },
	{ key = "food", label = "Well Fed (food buff)", kind = "aura", auras = { "Well Fed" }, food = true, options = foodOptions() },

	-- class self-buffs
	spells("ai", "Arcane Intellect", { MAGE = true }, { { spell = "Arcane Intellect", id = 1459, level = 1 } }, { blockedBy = { "Arcane Brilliance" } }),
	spells("magearmor", "Mage armor", { MAGE = true }, {
		{ spell = "Mage Armor", id = 6117, level = 34, tier = 3 },
		{ spell = "Ice Armor", id = 7302, level = 30, tier = 2 },
		{ spell = "Frost Armor", id = 168, level = 1, tier = 1 },
	}),
	spells("fort", "Power Word: Fortitude", { PRIEST = true }, { { spell = "Power Word: Fortitude", id = 1243, level = 1 } }, { blockedBy = { "Prayer of Fortitude" } }),
	spells("innerfire", "Inner Fire", { PRIEST = true }, { { spell = "Inner Fire", id = 588, level = 12 } }),
	spells("spirit", "Divine Spirit", { PRIEST = true }, { { spell = "Divine Spirit", id = 14752, level = 30, talent = true } }, { blockedBy = { "Prayer of Spirit" } }),
	spells("motw", "Mark of the Wild", { DRUID = true }, { { spell = "Mark of the Wild", id = 1126, level = 1 } }, { blockedBy = { "Gift of the Wild" } }),
	spells("thorns", "Thorns", { DRUID = true }, { { spell = "Thorns", id = 467, level = 6 } }),
	spells("demonarmor", "Warlock armor", { WARLOCK = true }, {
		{ spell = "Demon Armor", id = 706, level = 20, tier = 2 },
		{ spell = "Demon Skin", id = 687, level = 1, tier = 1 },
	}),
	spells("blessing", "Paladin blessing", { PALADIN = true }, {
		{ spell = "Blessing of Kings", id = 20217, level = 20, tier = 3, talent = true },
		{ spell = "Blessing of Might", id = 19740, level = 4, tier = 2 },
		{ spell = "Blessing of Wisdom", id = 19742, level = 14, tier = 1 },
	}, { blockedBy = { "Greater Blessing of Kings", "Greater Blessing of Might", "Greater Blessing of Wisdom" } }),
	spells("palaura", "Paladin aura", { PALADIN = true }, {
		{ spell = "Devotion Aura", id = 465, level = 1, tier = 3 },
		{ spell = "Retribution Aura", id = 7294, level = 16, tier = 2 },
		{ spell = "Concentration Aura", id = 19746, level = 22, tier = 1 },
	}),
	spells("aspect", "Hunter aspect", { HUNTER = true }, {
		{ spell = "Aspect of the Hawk", id = 13165, level = 10, tier = 2 },
		{ spell = "Aspect of the Monkey", id = 13163, level = 4, tier = 1 },
	}, { auras = { "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast" } }),
	spells("trueshot", "Trueshot Aura", { HUNTER = true }, { { spell = "Trueshot Aura", id = 19506, level = 40, talent = true } }),
	spells("lshield", "Lightning Shield", { SHAMAN = true }, { { spell = "Lightning Shield", id = 324, level = 8 } }),

	-- extras: elixirs, one per line (in Forever elixirs of different lines all stack), and scrolls
	elixirs("agi", "Agility elixir", {
		{ item = 2457, name = "Elixir of Minor Agility", level = 2, stats = { agi = 4 } },
		{ item = 3390, name = "Elixir of Lesser Agility", level = 18, stats = { agi = 8 } },
		{ item = 8949, name = "Elixir of Agility", level = 27, stats = { agi = 15 } },
		{ item = 9187, name = "Elixir of Greater Agility", level = 38, stats = { agi = 25 } },
		{ item = 13452, name = "Elixir of the Mongoose", level = 46, stats = { agi = 25, crit = 2 } },
	}),
	elixirs("str", "Strength elixir", {
		{ item = 2454, name = "Elixir of Minor Strength", level = 1, stats = { str = 4 } },
		{ item = 3391, name = "Elixir of Ogre Strength", level = 20, stats = { str = 8 } },
		{ item = 9206, name = "Elixir of Greater Strength", level = 48, stats = { str = 25 } },
		{ item = 250351, name = "Elixir of the Grizzly", level = 55, stats = { str = 25, crit = 2 } },
	}),
	elixirs("ferocity", "Elixir of Ferocity", {
		{ item = 250350, name = "Elixir of Ferocity", level = 55, stats = { str = 18, agi = 18 } },
	}),
	elixirs("sp", "Spell power elixir", {
		{ item = 247754, name = "Minor Arcane Elixir", level = 1, stats = { sd = 5 } },
		{ item = 250342, name = "Lesser Arcane Elixir", level = 25, stats = { sd = 15 } },
		{ item = 9155, name = "Arcane Elixir", level = 37, stats = { sd = 20 } },
		{ item = 13454, name = "Greater Arcane Elixir", level = 47, stats = { sd = 35 } },
	}),
	elixirs("school", "Spell school elixir", {
		{ item = 6373, name = "Elixir of Fire Power", level = 18, stats = { sd = 9 }, classes = { MAGE = true, WARLOCK = true } },
		{ item = 17708, name = "Elixir of Frost Power", level = 28, stats = { sd = 13 }, classes = { MAGE = true } },
		{ item = 9264, name = "Elixir of Shadow Power", level = 40, stats = { sd = 36 }, classes = { WARLOCK = true, PRIEST = true } },
		{ item = 21546, name = "Elixir of Holy Power", level = 40, stats = { sd = 36 }, classes = { PALADIN = true, PRIEST = true } },
		{ item = 250343, name = "Elixir of Nature Power", level = 55, stats = { sd = 36 }, classes = { DRUID = true, SHAMAN = true } },
	}),
	elixirs("int", "Intellect elixir", {
		{ item = 3383, name = "Elixir of Wisdom", level = 10, stats = { int = 3 } },
		{ item = 250353, name = "Elixir of Lesser Intellect", level = 25, stats = { int = 6 } },
		{ item = 9179, name = "Elixir of Greater Intellect", level = 37, stats = { int = 25 } },
		{ item = 13447, name = "Elixir of the Sages", level = 38, stats = { int = 18, spi = 18 } },
		{ item = 250354, name = "Elixir of Intellect", level = 45, stats = { int = 10 } },
		{ item = 250337, name = "Elixir of the Owl", level = 55, stats = { int = 25, acrit = 2 } },
	}),
	elixirs("spi", "Spirit elixir", {
		{ item = 250344, name = "Elixir of Minor Spirit", level = 5, stats = { spi = 3 } },
		{ item = 250345, name = "Elixir of Lesser Spirit", level = 25, stats = { spi = 6 } },
		{ item = 250346, name = "Elixir of Spirit", level = 45, stats = { spi = 10 } },
		{ item = 250347, name = "Elixir of Greater Spirit", level = 55, stats = { spi = 18 } },
		{ item = 250338, name = "Elixir of Sages", level = 55, stats = { spi = 25, acrit = 2 } },
		{ item = 250348, name = "Elixir of the Whale", level = 55, stats = { spi = 25, acrit = 2 } },
	}),
	elixirs("mana", "Mana regeneration elixir", {
		{ item = 250339, name = "Minor Mageblood Elixir", level = 5, stats = { mp5 = 3 } },
		{ item = 250340, name = "Lesser Mageblood Elixir", level = 25, stats = { mp5 = 6 } },
		{ item = 20007, name = "Mageblood Elixir", level = 40, stats = { mp5 = 12 } },
		{ item = 250336, name = "Elixir of Wicked Regeneration", level = 55, stats = { mp5 = 11 } },
		{ item = 250341, name = "Greater Mageblood Elixir", level = 55, stats = { mp5 = 20 } },
	}),
	elixirs("healing", "Healing elixir", {
		{ item = 250331, name = "Lesser Cleric's Elixir", level = 25, stats = { heal = 20 } },
		{ item = 250332, name = "Cleric's Elixir", level = 45, stats = { heal = 30 } },
		{ item = 250333, name = "Greater Cleric's Elixir", level = 55, stats = { heal = 40 } },
	}),
	elixirs("hp", "Health elixir", {
		{ item = 2458, name = "Elixir of Minor Fortitude", level = 2, stats = { hp = 27 } },
		{ item = 3825, name = "Elixir of Lesser Fortitude", level = 25, stats = { hp = 120 } },
		{ item = 250334, name = "Elixir of Fortitude", level = 45, stats = { hp = 200 } },
		{ item = 250335, name = "Elixir of Greater Fortitude", level = 55, stats = { hp = 400 } },
	}),
	elixirs("def", "Armor elixir", {
		{ item = 5997, name = "Elixir of Minor Defense", level = 1, stats = { armor = 50 } },
		{ item = 3389, name = "Elixir of Lesser Defense", level = 16, stats = { armor = 150 } },
		{ item = 8951, name = "Elixir of Defense", level = 29, stats = { armor = 250 } },
		{ item = 13445, name = "Elixir of Greater Defense", level = 43, stats = { armor = 450 } },
	}),
	scrolls("sagi", "Agility", "agi", { { 3012, 10, 5 }, { 1477, 25, 9 }, { 4425, 40, 13 }, { 10309, 55, 17 } }),
	scrolls("sstr", "Strength", "str", { { 954, 10, 5 }, { 2289, 25, 9 }, { 4426, 40, 13 }, { 10310, 55, 17 } }, { "Blessing of Might", "Greater Blessing of Might" }),
	scrolls("ssta", "Stamina", "sta", { { 1180, 5, 4 }, { 1711, 20, 8 }, { 4422, 35, 12 }, { 10307, 50, 16 } }, { "Power Word: Fortitude", "Prayer of Fortitude" }),
	scrolls("sint", "Intellect", "int", { { 955, 5, 4 }, { 2290, 20, 8 }, { 4419, 35, 12 }, { 10308, 50, 16 } }, { "Arcane Intellect", "Arcane Brilliance" }),
	scrolls("sspi", "Spirit", "spi", { { 1181, 1, 3 }, { 1712, 15, 7 }, { 4424, 30, 11 }, { 10306, 45, 15 } }, { "Divine Spirit", "Prayer of Spirit" }),
	scrolls("sprot", "Protection", "armor", { { 3013, 1, 60 }, { 1478, 15, 120 }, { 4421, 30, 180 }, { 10305, 45, 240 } }, nil, "Armor"),
}

-- Buffs that a place gives you: shown as "zone bonus" lines when you have them.
D.PLACE_AURAS = { "Cozy Fire", "Campfire", "Rested", "Well Rested" }

-- Other items worth counting in bags and banks (camp objects add theirs).
D.EXTRA_ITEMS = {}

-- Every item id in the catalog, for scanning bags and banks.
function D.AllItems()
	local out, seen = {}, {}
	for _, g in ipairs(D.GROUPS) do
		for _, o in ipairs(g.options) do
			if o.item and not seen[o.item] then seen[o.item] = true; out[#out + 1] = o.item end
		end
	end
	for _, id in ipairs(D.EXTRA_ITEMS) do
		if not seen[id] then seen[id] = true; out[#out + 1] = id end
	end
	return out
end

function D.Group(key)
	for _, g in ipairs(D.GROUPS) do if g.key == key then return g end end
end
