-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- Your class and talent spec, and what each spec values: the stat weights that rank food,
-- elixirs, scrolls and weapon buffs for you. No game API in this file.
--
-- The weights follow what each spec's Wowhead Forever guides recommend (the "Best Levelling
-- Consumables" sections of the levelling guides and the "Enchants & Consumables" guides, read
-- November 2026). For example, warriors are told Strength food (Goretusk Liver Pie, Bear Brisket,
-- Savory Stag Sliders, Smoked Desert Dumplings); rogues Agility food (Hot Lion Chops ... Filet o'
-- Flank); casters Spell Power food (Smoked Sagefish, Briny Seafood Stew, Nightfin Soup, Baked
-- Salmon); Restoration druids and shamans the healing teas; Beast Mastery and Marksmanship
-- hunters Brilliant Mana Oil; priests Lesser Wizard Oil.
-- Units: about one attack power (melee), or one spell power (casters), per point of weight.
--   str agi ap sta int spi   the stats
--   sd heal                  spell damage, healing
--   crit                     per 1% critical strike chance
--   armor hp mp5             armor, maximum health, mana every 5 sec
--   wdmg                     per point of weapon damage (sharpening stones, weightstones)
--   poison imbue             rogue poisons, shaman weapon spells (per level of the item or spell)
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local S = {}
ns.Spec = S

S.TREES = {
	WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral", "Restoration" },
}
S.CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
-- The tree most people level in, used before you have spent talent points.
S.DEFAULT_TREE = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

local MELEE_STR = { str = 2.05, agi = 1, ap = 1, crit = 22, sta = 0.3, wdmg = 4, armor = 0.01, hp = 0.03 }
local TANK = { str = 1.6, agi = 1.2, ap = 0.8, sta = 2, crit = 10, armor = 0.1, hp = 0.2, wdmg = 3, mp5 = 0 }
local ROGUE = { agi = 2.2, str = 1, ap = 1, crit = 25, sta = 0.3, wdmg = 4, poison = 1.5, hp = 0.03 }
local HUNTER = { agi = 2, ap = 0.5, crit = 25, mcrit = 2, int = 0.5, mp5 = 3, sta = 0.3, hp = 0.03 }
local HUNTER_SV = { agi = 2, ap = 0.8, crit = 25, int = 0.4, mp5 = 1, sta = 0.3, wdmg = 3, hp = 0.03 }
local MAGE = { sd = 1, int = 0.5, spi = 0.15, scrit = 12, mp5 = 1, sta = 0.2, hp = 0.02, armor = 0.01 }
local LOCK = { sd = 1, int = 0.3, spi = 0.1, scrit = 10, mp5 = 1, sta = 0.4, hp = 0.05, armor = 0.01 }
local PRIEST_HEAL = { sd = 1, heal = 0.6, int = 0.6, spi = 0.5, mp5 = 1.5, scrit = 10, sta = 0.2, hp = 0.02 }
local PRIEST_SHADOW = { sd = 1, int = 0.6, spi = 0.5, mp5 = 1.5, scrit = 10, sta = 0.3, hp = 0.03 }
local CASTER = { sd = 1, int = 0.6, spi = 0.3, scrit = 12, mp5 = 1.5, sta = 0.2, hp = 0.02 }
local RESTO = { heal = 1, int = 0.7, mp5 = 2, spi = 0.4, sd = 0.2, sta = 0.2, hp = 0.02 }

-- The food lines the guides name, by item id. "What to go and get" points at the best of these
-- for your level; food you already carry is ranked by what it gives (so a +20 Attack Power fish
-- in your bags is used rather than sent back for a +10 Strength dish).
local STR_FOOD = { 724, 2685, 250074, 250065, 20452 } -- Goretusk Liver Pie, Succulent Pork Ribs, Bear Brisket, Savory Stag Sliders, Smoked Desert Dumplings
local AGI_FOOD = { 2684, 3727, 13851, 18045, 250072, 238638 } -- Coyote Steak, Hot Lion Chops, Hot Wolf Ribs, Tender Wolf Steak, Swiftstrike Steak, Filet o' Flank
local SP_FOOD = { 5095, 21072, 274971, 13931, 6887, 13935, 13933 } -- Rainbow Fin Albacore, Smoked Sagefish, Briny Seafood Stew, Nightfin Soup, Spotted Yellowtail, Baked Salmon, Lobster Stew
local INT_FOOD = { 250079, 250077, 12210, 250073, 250076, 250066, 250067 } -- the raptor dishes, Soaring Pamplona, Bat Hachee
local TEA = { 249865, 249866, 249867, 249868, 249869, 249870 } -- Peace Tea to Sage's Tea
local HOLY_PALADIN_FOOD = { 12224, 250077, 4457, 250067 } -- Crispy Bat Wing, Twice-Spiced Raptor Slice, Barbecued Buzzard Wing, Bat Hachee
local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do for _, id in ipairs(list) do out[#out + 1] = id end end
	return out
end

-- [class][tree] = { w = weights, food = what its guide tells you to eat, foods = those foods' ids }
local G = "Wowhead's %s guides"
S.SPECS = {
	WARRIOR = {
		{ w = MELEE_STR, food = "Strength food", foods = STR_FOOD },
		{ w = MELEE_STR, food = "attack power or Strength food", foods = join({ 4592 }, STR_FOOD) },
		{ w = TANK, food = "Strength food; any food buff for the experience", foods = STR_FOOD },
	},
	PALADIN = {
		{ w = { int = 1, heal = 0.3, sd = 0.4, mp5 = 2, spi = 0.4, scrit = 8, sta = 0.2, hp = 0.02 }, food = "Intellect food", foods = join(HOLY_PALADIN_FOOD, INT_FOOD) },
		{ w = { str = 1, sta = 2, sd = 1, int = 0.5, mp5 = 1, armor = 0.1, hp = 0.2, crit = 8, wdmg = 2 }, food = "Spell Power food", foods = SP_FOOD },
		{ w = { str = 2, ap = 1, sd = 1, int = 0.4, crit = 20, mp5 = 1, wdmg = 4, sta = 0.3, hp = 0.03 }, food = "Spell Power or Strength food", foods = join(STR_FOOD, SP_FOOD) },
	},
	HUNTER = {
		{ w = HUNTER, food = "Agility food (Swiftstrike Steak at 45)", foods = AGI_FOOD },
		{ w = HUNTER, food = "Agility food (Swiftstrike Steak at 45)", foods = AGI_FOOD },
		{ w = HUNTER_SV, food = "Agility food (Swiftstrike Steak at 45)", foods = AGI_FOOD },
	},
	ROGUE = {
		{ w = ROGUE, food = "Agility food", foods = AGI_FOOD },
		{ w = ROGUE, food = "Agility food", foods = AGI_FOOD },
		{ w = ROGUE, food = "Agility food", foods = AGI_FOOD },
	},
	PRIEST = {
		{ w = PRIEST_HEAL, food = "Spell Power food", foods = SP_FOOD },
		{ w = PRIEST_HEAL, food = "Spell Power food", foods = SP_FOOD },
		{ w = PRIEST_SHADOW, food = "Spell Power food", foods = SP_FOOD },
	},
	SHAMAN = {
		{ w = CASTER, food = "Spell Power food, else Intellect", foods = join(SP_FOOD, INT_FOOD) },
		{ w = { str = 2, agi = 1, ap = 1, sd = 1.5, crit = 22, wdmg = 4, imbue = 1, int = 0.3, mp5 = 1, sta = 0.3, hp = 0.03 }, food = "Baked Salmon (Spell Power) at 45", foods = join(SP_FOOD, STR_FOOD) },
		{ w = RESTO, food = "healing teas, else Intellect", foods = join(TEA, INT_FOOD) },
	},
	MAGE = {
		{ w = MAGE, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
		{ w = MAGE, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
		{ w = MAGE, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
	},
	WARLOCK = {
		{ w = LOCK, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
		{ w = LOCK, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
		{ w = LOCK, food = "Spell Power food", foods = join(SP_FOOD, INT_FOOD) },
	},
	DRUID = {
		{ w = CASTER, food = "Spell Power food", foods = SP_FOOD },
		{ w = { agi = 2.3, str = 1.8, ap = 1, crit = 22, sta = 0.5, wdmg = 0.5, hp = 0.03 }, food = "Agility food (Swiftstrike Steak at 45)", foods = AGI_FOOD },
		{ w = RESTO, food = "healing teas", foods = TEA },
	},
}
for class, trees in pairs(S.SPECS) do
	for i, s in ipairs(trees) do s.guide = G:format(S.TREES[class][i] .. " " .. S.CLASS_NAMES[class]) end
end

-- When you set your role yourself (/crm buffs style), the matching tree of your class, or a stand-in.
S.STYLE_TREE = {
	tank = { WARRIOR = 3, PALADIN = 2, DRUID = 2 },
	melee = { WARRIOR = 1, PALADIN = 3, SHAMAN = 2, DRUID = 2, ROGUE = 2, HUNTER = 3 },
	ranged = { HUNTER = 1 },
	caster = { MAGE = 3, WARLOCK = 1, PRIEST = 3, SHAMAN = 1, DRUID = 1, PALADIN = 2 },
	healer = { PRIEST = 2, PALADIN = 1, SHAMAN = 3, DRUID = 3 },
}
S.STYLE_WEIGHTS = {
	tank = TANK, melee = MELEE_STR, ranged = HUNTER, caster = MAGE, healer = RESTO,
}
S.FERAL_TANK = { agi = 1.5, str = 1.5, ap = 0.8, sta = 2, armor = 0.1, hp = 0.2, crit = 10 }

-- Tree with the most points, or nil before any are spent.
function S.TopTree(points)
	local best, most = nil, 0
	for tab, n in pairs(points or {}) do
		if (tonumber(n) or 0) > most then best, most = tab, tonumber(n) end
	end
	return best
end

-- state: { class, talents, styleOverride }
-- Returns { class, tree, label, guessed, weights, food, guide }
function S.Resolve(state)
	local class = state.class or "WARRIOR"
	local trees = S.SPECS[class]
	local override = state.styleOverride
	if override and S.STYLE_WEIGHTS[override] then
		local tree = S.STYLE_TREE[override][class]
		if override == "tank" and class == "DRUID" then
			return { class = class, tree = 2, label = "Feral Druid tank", weights = S.FERAL_TANK, food = "Stamina, Agility or Strength food", foods = STR_FOOD,
				guide = "Wowhead's Feral Druid tank guides", override = override }
		end
		if tree and trees then
			local s = trees[tree]
			return { class = class, tree = tree, label = S.TREES[class][tree] .. " " .. S.CLASS_NAMES[class], weights = s.w, food = s.food, foods = s.foods,
				guide = s.guide, override = override }
		end
		return { class = class, label = override, weights = S.STYLE_WEIGHTS[override], food = "the best food for a " .. override,
			guide = "the role's usual picks", override = override }
	end
	local tree = S.TopTree(state.talents)
	local guessed = tree == nil
	tree = tree or S.DEFAULT_TREE[class] or 1
	local s = trees and trees[tree]
	if not s then return { class = class, label = "?", weights = MELEE_STR, food = "any food", guide = "?" } end
	return { class = class, tree = tree, guessed = guessed, weights = s.w, food = s.food, foods = s.foods, guide = s.guide,
		label = S.TREES[class][tree] .. " " .. S.CLASS_NAMES[class] .. (guessed and " (no talents yet, so a guess)" or "") }
end

-- How much a set of stats is worth to this spec.
function S.Score(stats, weights)
	local total = 0
	for k, v in pairs(stats or {}) do total = total + S.Weight(weights, k) * v end
	return total
end

-- crit is physical crit, scrit spell crit, acrit both (it counts as the better of the two).
-- A spec that uses spell power values spell crit like crit unless it says otherwise.
function S.Weight(weights, k)
	if k == "scrit" and weights.scrit == nil then
		return ((weights.sd or 0) > 0) and (weights.crit or 0) or 0
	end
	if k == "acrit" then return math.max(weights.crit or 0, S.Weight(weights, "scrit")) end
	if k == "mcrit" then return weights.mcrit or weights.crit or 0 end -- melee only (Elemental Sharpening Stone)
	return weights[k] or 0
end

local KEYS = { ["attack power"] = "ap", strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi",
	["spell damage"] = "sd", ["spell power"] = "sd", ["healing power"] = "heal", ["critical strike chance"] = "acrit", armor = "armor" }

-- The stats in a food's tooltip: "...you will become well fed and gain 20 Attack Power for 15 min."
-- Also "25 Agility and 10 Stamina", "6 Stamina and Spirit", "1% Critical Strike chance".
-- Returns stats, or {} for a Well Fed food with no stat we know, or nil when it is not Well Fed food.
function S.ParseWellFed(text)
	if type(text) ~= "string" or not text:lower():find("well fed", 1, true) then return nil end
	local gain = text:match("[Ww]ell [Ff]ed and gain (.-) for ") or text:match("[Ww]ell [Ff]ed and gain (.-)%.") or ""
	local stats, last, pending = {}, nil, {}
	for part in (gain:gsub("%%", "") .. " and "):gmatch("(.-) and ") do
		local n, what = part:match("^%s*(%d*)%s*(.-)%s*$")
		local key = KEYS[(what or ""):lower()]
		if key then
			n = tonumber(n)
			if n then last = n end
			pending[#pending + 1] = { key, n }
		end
	end
	for _, p in ipairs(pending) do stats[p[1]] = p[2] or last or 1 end
	return stats
end

local LABEL = { str = "Strength", agi = "Agility", ap = "Attack Power", sta = "Stamina", int = "Intellect", spi = "Spirit",
	sd = "Spell Power", heal = "healing", crit = "% crit", armor = "Armor", hp = "maximum health", mp5 = "mana every 5 sec",
	wdmg = "weapon damage" }
local CRIT = { crit = "% melee and ranged crit", scrit = "% spell crit", acrit = "% crit", mcrit = "% melee crit" }
local ORDER = { "str", "agi", "ap", "sd", "heal", "int", "spi", "sta", "crit", "mcrit", "scrit", "acrit", "armor", "hp", "mp5", "wdmg" }

-- "+20 Attack Power", "+25 Agility, +10 Stamina", "+1% crit"
function S.StatText(stats)
	local out = {}
	for _, k in ipairs(ORDER) do
		local v = stats and stats[k]
		if v then out[#out + 1] = CRIT[k] and ("+" .. v .. CRIT[k]) or ("+" .. v .. " " .. LABEL[k]) end
	end
	return table.concat(out, ", ")
end
