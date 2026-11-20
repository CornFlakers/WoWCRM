-- Where a crafting material comes from, and what to craft first.
-- No game API in this file: the profession window is read in Reagents.lua and handed in here.
local _, ns = ...
local S = {}
ns.Sources = S

-- ---------------------------------------------------------------- built-in notes
-- Where common materials come from, for when nothing better is installed. Keyed by the item's
-- name in lower case, as the profession window shows it. Questie's database, when installed,
-- adds the named creatures and vendors; Wowhead has the full list with drop chances.

local NOTES = {}
local function note(text, ...)
	for _, name in ipairs({ ... }) do
		local list = NOTES[name] or {}
		list[#list + 1] = text
		NOTES[name] = list
	end
end

-- Mining
note("Mined from Copper Veins (Mining 1), found in every starting area.", "copper ore", "rough stone")
note("Mined from Tin Veins (Mining 65).", "tin ore", "coarse stone")
note("Mined from Silver Veins (Mining 75), a rare node that appears among Tin Veins.", "silver ore", "coarse stone")
note("Mined from Iron Deposits (Mining 125).", "iron ore", "heavy stone")
note("Mined from Gold Veins (Mining 155), a rare node that appears among Iron and Mithril.", "gold ore", "heavy stone")
note("Mined from Mithril Deposits (Mining 175).", "mithril ore", "solid stone")
note("Mined from Truesilver Deposits (Mining 230), a rare node that appears among Mithril.", "truesilver ore", "solid stone")
note("Mined from Small Thorium Veins (Mining 245) and Rich Thorium Veins (Mining 275).", "thorium ore", "dense stone")
note("Mined from Dark Iron Deposits (Mining 230) in Searing Gorge, Burning Steppes and Blackrock Depths.", "dark iron ore")
note("Comes out of mining nodes now and then, alongside the ore.", "rough stone", "coarse stone", "heavy stone", "solid stone", "dense stone")

-- Smelting
note("Smelted from Copper Ore (Mining 1).", "copper bar")
note("Smelted from Tin Ore (Mining 65).", "tin bar")
note("Smelted from Copper Bars and Tin Bars (Mining 65).", "bronze bar")
note("Smelted from Silver Ore (Mining 75).", "silver bar")
note("Smelted from Iron Ore (Mining 125).", "iron bar")
note("Smelted from Gold Ore (Mining 155).", "gold bar")
note("Smelted from Iron Bars and Coal (Mining 165).", "steel bar")
note("Smelted from Mithril Ore (Mining 175).", "mithril bar")
note("Smelted from Truesilver Ore (Mining 230).", "truesilver bar")
note("Smelted from Thorium Ore (Mining 250).", "thorium bar")
note("Smelted from Dark Iron Ore (Mining 230) at the Black Forge inside Blackrock Depths.", "dark iron bar")
note("Smelting needs the Mining skill; anyone with Mining can smelt at a forge.", "copper bar", "tin bar", "bronze bar",
	"silver bar", "iron bar", "gold bar", "steel bar", "mithril bar", "truesilver bar", "thorium bar", "dark iron bar")

-- Blacksmithing parts made from stone
note("Made by Blacksmithing from Rough Stone.", "rough grinding stone", "rough sharpening stone", "rough weightstone")
note("Made by Blacksmithing from Coarse Stone.", "coarse grinding stone", "coarse sharpening stone", "coarse weightstone")
note("Made by Blacksmithing from Heavy Stone.", "heavy grinding stone", "heavy sharpening stone", "heavy weightstone")
note("Made by Blacksmithing from Solid Stone.", "solid grinding stone", "solid sharpening stone", "solid weightstone")
note("Made by Blacksmithing from Dense Stone.", "dense grinding stone", "dense sharpening stone", "dense weightstone")

-- Trade supplies sold by vendors
local VENDOR = "Sold by trade supply vendors and profession suppliers in towns and cities."
note(VENDOR, "coal", "weak flux", "strong flux", "coarse thread", "fine thread", "silken thread", "heavy silken thread",
	"rune thread", "salt", "gray dye", "bleach", "red dye", "empty vial", "leaded vial", "crystal vial",
	"copper rod", "simple wood", "refreshing spring water", "mild spices")

-- Cloth
note("Dropped by humanoids of about level 5 to 15.", "linen cloth")
note("Dropped by humanoids of about level 15 to 25.", "wool cloth")
note("Dropped by humanoids of about level 25 to 40.", "silk cloth")
note("Dropped by humanoids of about level 35 to 50.", "mageweave cloth")
note("Dropped by humanoids of about level 48 and up.", "runecloth")
note("Dropped by demons of level 50 and up, such as those in Felwood, Azshara and the Blasted Lands.", "felcloth")
note("Woven by Tailoring from Linen Cloth.", "bolt of linen cloth")
note("Woven by Tailoring from Wool Cloth.", "bolt of woolen cloth")
note("Woven by Tailoring from Silk Cloth.", "bolt of silk cloth")
note("Woven by Tailoring from Mageweave Cloth.", "bolt of mageweave")
note("Woven by Tailoring from Runecloth.", "bolt of runecloth")

-- Leather
note("Skinned from beasts of level 1 to 15.", "ruined leather scraps")
note("Skinned from beasts of about level 10 to 20.", "light leather", "light hide")
note("Skinned from beasts of about level 20 to 30.", "medium leather", "medium hide")
note("Skinned from beasts of about level 30 to 40.", "heavy leather", "heavy hide")
note("Skinned from beasts of about level 40 to 50.", "thick leather", "thick hide")
note("Skinned from beasts of about level 50 to 60.", "rugged leather", "rugged hide")
note("Made by Leatherworking from Ruined Leather Scraps.", "light leather")
note("Made by Leatherworking from Light Leather.", "medium leather")
note("Made by Leatherworking from Medium Leather.", "heavy leather")
note("Made by Leatherworking from a hide and Salt.", "cured light hide", "cured medium hide", "cured heavy hide",
	"cured thick hide", "cured rugged hide")

-- Elemental
note("Dropped by earth elementals and rock creatures.", "elemental earth")
note("Dropped by fire elementals.", "elemental fire")
note("Dropped by water elementals.", "elemental water")
note("Dropped by air elementals.", "elemental air")

-- Enchanting
local DE = "Made by disenchanting uncommon (green) and better items. Enchanters disenchant; buy it from them or the auction house."
note(DE, "strange dust", "soul dust", "vision dust", "dream dust", "illusion dust", "lesser magic essence",
	"greater magic essence", "lesser astral essence", "greater astral essence", "lesser mystic essence",
	"greater mystic essence", "lesser nether essence", "greater nether essence", "lesser eternal essence",
	"greater eternal essence", "small glimmering shard", "large glimmering shard", "small glowing shard",
	"large glowing shard", "small radiant shard", "large radiant shard", "small brilliant shard", "large brilliant shard")

-- Herbs
local HERB = "Picked with Herbalism from the plant of the same name."
note(HERB, "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "swiftthistle", "bruiseweed",
	"stranglekelp", "grave moss", "wild steelbloom", "kingsblood", "liferoot", "fadeleaf", "goldthorn",
	"khadgar's whisker", "wintersbite", "firebloom", "purple lotus", "arthas' tears", "sungrass", "blindweed",
	"ghost mushroom", "gromsblood", "golden sansam", "dreamfoil", "mountain silversage", "plaguebloom",
	"icecap", "black lotus")

function S.Notes(name)
	if type(name) ~= "string" then return nil end
	return NOTES[name:lower()]
end

-- ---------------------------------------------------------------- items and links

-- "|cffffffff|Hitem:2838::::::::|h[Heavy Stone]|h|r" -> 2838
function S.ItemID(link)
	if type(link) == "number" then return link end
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- Wowhead's item page lists every creature that drops it, every node it comes from and every vendor.
function S.WowheadURL(itemID, name)
	if itemID then return "https://www.wowhead.com/forever/item=" .. itemID end
	return "https://www.wowhead.com/forever/search?q=" .. (tostring(name or ""):gsub("[^%w]+", "+"))
end

-- ---------------------------------------------------------------- what to craft first
-- recipeOf(key) -> { name, made = how many one craft makes, reagents = { { key, name, qty } } } or nil
-- countOf(key)  -> how many you hold.
-- Returns steps, the crafts to make first in the order to make them: { key, name, crafts, makes },
-- and missing, the materials you neither hold nor can make here: { key, name, qty }.
-- What one step makes beyond what is needed is kept for the next.
function S.Plan(rootKey, recipeOf, countOf)
	local pool, steps, byKey, missing, missingByKey = {}, {}, {}, {}, {}
	local root = recipeOf(rootKey)
	if not root then return steps, missing end

	local function have(k)
		if pool[k] == nil then pool[k] = math.max(0, tonumber(countOf and countOf(k)) or 0) end
		return pool[k]
	end

	local function make(recipe, times, path, depth)
		for _, g in ipairs(recipe.reagents or {}) do
			local need = math.max(1, tonumber(g.qty) or 1) * times
			local held = have(g.key)
			local use = math.min(held, need)
			pool[g.key] = held - use
			local short = need - use
			if short > 0 then
				local sub = depth < 8 and not path[g.key] and recipeOf(g.key)
				if sub then
					local made = math.max(1, tonumber(sub.made) or 1)
					local crafts = math.ceil(short / made)
					path[g.key] = true
					make(sub, crafts, path, depth + 1)
					path[g.key] = nil
					pool[g.key] = pool[g.key] + crafts * made - short
					local s = byKey[g.key]
					if s then
						s.crafts = s.crafts + crafts
					else
						s = { key = g.key, name = sub.name or g.name, crafts = crafts, makes = g.name }
						byKey[g.key] = s
						steps[#steps + 1] = s
					end
				else
					local m = missingByKey[g.key]
					if m then m.qty = m.qty + short else
						m = { key = g.key, name = g.name, qty = short }
						missingByKey[g.key] = m
						missing[#missing + 1] = m
					end
				end
			end
		end
	end

	make(root, 1, { [rootKey] = true }, 0)
	return steps, missing
end

-- "Craft first: 2x Coarse Grinding Stone, then 1x Bronze Tube" or nil when nothing needs crafting.
function S.PlanText(steps)
	if not steps or #steps == 0 then return nil end
	local parts = {}
	for i, s in ipairs(steps) do parts[i] = s.crafts .. "x " .. s.name end
	return "Craft first: " .. table.concat(parts, ", then ")
end

-- ---------------------------------------------------------------- the way back
-- Each jump to a material's recipe remembers the recipe you came from, so Back returns there.

function S.Push(trail, entry)
	local top = trail[#trail]
	if top and top.name == entry.name then return trail end
	trail[#trail + 1] = entry
	return trail
end

function S.Pop(trail)
	local top = trail[#trail]
	trail[#trail] = nil
	return top
end
