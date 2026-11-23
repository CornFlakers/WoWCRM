-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- A short guide to getting each consumable: who makes it, roughly what skill, what it takes,
-- and where the recipe comes from. Written from general game knowledge, so it is a starting
-- point: skills are approximate, and this client may have changed some recipes. When one of
-- your characters has scanned the profession with Mastercraft, that scan's exact materials are
-- shown instead (see Howto.lua). No game API in this file.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D = ns.Data

local TRAINER = { Blacksmithing = "Taught by Blacksmithing trainers", Alchemy = "Taught by Alchemy trainers",
	Cooking = "Taught by Cooking trainers", Enchanting = "Taught by Enchanting trainers", Poisons = "Taught by rogue trainers" }

-- HOW[itemID] = { prof, skill, recipe, mats = { { id, n }, ... } }
local HOW = {}
D.HOW = HOW
local function how(id, prof, skill, recipe, mats)
	HOW[id] = { prof = prof, skill = skill, recipe = recipe or TRAINER[prof], mats = mats }
end

-- Blacksmithing
how(2862, "Blacksmithing", 1, nil, { { 2835, 1 } })
how(2863, "Blacksmithing", 65, nil, { { 2836, 2 } })
how(2871, "Blacksmithing", 125, nil, { { 2838, 1 } })
how(7964, "Blacksmithing", 200, nil, { { 7912, 1 } })
how(12404, "Blacksmithing", 250, nil, { { 12365, 1 } })
how(18262, "Blacksmithing", 300, "Plans drop in Molten Core")
how(3239, "Blacksmithing", 25, nil, { { 2835, 1 }, { 2589, 1 } })
how(3240, "Blacksmithing", 65, nil, { { 2836, 1 }, { 2592, 1 } })
how(3241, "Blacksmithing", 125, nil, { { 2838, 1 }, { 2592, 1 } })
how(7965, "Blacksmithing", 200, nil, { { 7912, 1 }, { 4306, 1 } })
how(12643, "Blacksmithing", 250, nil, { { 12365, 1 }, { 14047, 1 } })

-- Enchanting oils
local ENCH_VENDOR = "Formula sold by enchanting supply vendors in the capital cities"
how(20744, "Enchanting", 45, ENCH_VENDOR)
how(20745, "Enchanting", 150, ENCH_VENDOR)
how(20746, "Enchanting", 200, ENCH_VENDOR)
how(20747, "Enchanting", 250, "Formula sold by Kania at Cenarion Hold, Silithus")
how(20750, "Enchanting", 275, "Formula sold by Kania at Cenarion Hold, Silithus")
how(20749, "Enchanting", 300, "Formula from the Zandalar Tribe on Yojamba Isle, Stranglethorn Vale (needs reputation)")
how(20748, "Enchanting", 300, "Formula from the Zandalar Tribe on Yojamba Isle, Stranglethorn Vale (needs reputation)")

-- Rogue poisons
how(6947, "Poisons", 1, nil, { { 2928, 1 }, { 3371, 1 } })
for _, id in ipairs({ 6949, 6950, 8926, 8927, 8928 }) do how(id, "Poisons", nil) end

-- Alchemy
how(2457, "Alchemy", 50)
how(3390, "Alchemy", 140)
how(8949, "Alchemy", 185)
how(9187, "Alchemy", 240)
how(13452, "Alchemy", 280, "Recipe is a drop from enemies in high-level zones; also on the Auction House", { { 8838, 2 }, { 8846, 2 }, { 8925, 1 } })
how(2454, "Alchemy", 1, nil, { { 2449, 1 }, { 765, 1 }, { 3371, 1 } })
how(3391, "Alchemy", 150)
how(9206, "Alchemy", 245, "Recipe is a drop; also on the Auction House")
how(6373, "Alchemy", 140, "Recipe sold by some alchemy supply vendors")
how(9155, "Alchemy", 235)
how(9264, "Alchemy", 250, "Recipe sold by some alchemy supply vendors")
how(17708, "Alchemy", 190, "Recipe from the Winter Veil holiday")
how(13454, "Alchemy", 285, nil, { { 13463, 3 }, { 13465, 1 }, { 8925, 1 } })
how(21546, "Alchemy", 250)
how(3383, "Alchemy", 90)
how(9179, "Alchemy", 235)
how(5997, "Alchemy", 1, nil, { { 765, 2 }, { 3371, 1 } })
how(3389, "Alchemy", 130)
how(8951, "Alchemy", 195)
how(13445, "Alchemy", 265, "Recipe is a drop; also on the Auction House")
how(2458, "Alchemy", 50)
how(3825, "Alchemy", 175)

-- Cooking
local CK_VENDOR = "Recipe sold by cooking supply vendors in that region"
how(2680, "Cooking", 10, nil, { { 2672, 1 }, { 2678, 1 } })
how(5474, "Cooking", 35, "Recipe sold in Mulgore and The Barrens", { { 5467, 1 }, { 2678, 1 } })
how(12224, "Cooking", 1, "Recipe sold in Tirisfal Glades", { { 12223, 1 }, { 2678, 1 } })
how(2888, "Cooking", 25, "Recipe sold in Dun Morogh", { { 2886, 1 }, { 2894, 1 } })
how(2683, "Cooking", 75, CK_VENDOR, { { 2674, 1 }, { 2678, 1 } })
how(2684, "Cooking", 50, nil, { { 2673, 1 } })
how(3662, "Cooking", 80, CK_VENDOR, { { 2924, 1 }, { 2678, 1 } })
how(5527, "Cooking", 125, nil, { { 5504, 1 } })
how(3726, "Cooking", 110, CK_VENDOR, { { 3730, 1 }, { 2692, 1 } })
how(3729, "Cooking", 175, CK_VENDOR, { { 3712, 1 }, { 3713, 1 } })
how(12210, "Cooking", 175, "Recipe sold in Booty Bay and Dustwallow Marsh", { { 12184, 1 }, { 2692, 1 } })
how(12212, "Cooking", 175, CK_VENDOR)
how(17222, "Cooking", 200)
how(12218, "Cooking", 225, CK_VENDOR, { { 12207, 1 }, { 3713, 2 } })
how(18045, "Cooking", 225, CK_VENDOR, { { 12208, 1 } })
how(13928, "Cooking", 240, CK_VENDOR, { { 13755, 1 } })
how(13931, "Cooking", 250, CK_VENDOR)
how(18254, "Cooking", 275, "Recipe drops in Dire Maul", { { 18255, 1 } })
how(20452, "Cooking", 285, "Recipe from a Cenarion Hold quest in Silithus")
how(21023, "Cooking", 300, "Recipe from Dirge Quikcleave's quest in Gadgetzan, Tanaris")

-- Where materials come from: MATS[itemID] = { name, note }
local MATS = {}
D.MATS = MATS
local function mat(note, list)
	for id, name in pairs(list) do MATS[id] = { name = name, note = note } end
end
mat("Mined from Copper Veins; also from mining nodes", { [2835] = "Rough Stone" })
mat("Mined from Tin Veins", { [2836] = "Coarse Stone" })
mat("Mined from Iron Deposits", { [2838] = "Heavy Stone" })
mat("Mined from Mithril Deposits", { [7912] = "Solid Stone" })
mat("Mined from Thorium Veins", { [12365] = "Dense Stone" })
mat("Dropped by humanoid enemies", { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [4306] = "Silk Cloth", [14047] = "Runecloth" })
mat("Sold by trade and alchemy supply vendors", { [3371] = "Empty Vial", [3372] = "Leaded Vial", [8925] = "Crystal Vial", [18256] = "Imbued Vial" })
mat("Sold by cooking supply vendors and innkeepers", { [2678] = "Mild Spices", [2692] = "Hot Spices", [3713] = "Soothing Spices",
	[159] = "Refreshing Spring Water", [2894] = "Rhapsody Malt" })
mat("From disenchanting green items", { [10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust",
	[11176] = "Dream Dust", [16204] = "Illusion Dust", [11174] = "Lesser Nether Essence", [14344] = "Large Brilliant Shard" })
mat("Sold by reagent vendors", { [17034] = "Maple Seed", [17035] = "Stranglethorn Seed", [17036] = "Ashwood Seed" })
mat("Sold by poison supply vendors", { [2928] = "Dust of Decay", [8924] = "Dust of Deterioration" })
mat("Picked with Herbalism; also on the Auction House", { [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal",
	[8838] = "Sungrass", [8846] = "Gromsblood", [13463] = "Dreamfoil", [13465] = "Mountain Silversage", [4625] = "Firebloom",
	[8831] = "Purple Lotus", [3820] = "Stranglekelp", [3355] = "Wild Steelbloom", [3821] = "Goldthorn", [8839] = "Blindweed" })
mat("Dropped by beasts", { [2672] = "Stringy Wolf Meat", [5467] = "Kodo Meat", [12223] = "Meaty Bat Wing", [2886] = "Crag Boar Rib",
	[2673] = "Coyote Meat", [2924] = "Crocolisk Meat", [3730] = "Big Bear Meat", [3712] = "Turtle Meat", [12184] = "Raptor Flesh",
	[12207] = "Giant Egg", [12208] = "Tender Wolf Meat" })
mat("Dropped by crawlers and crabs", { [2674] = "Crawler Meat" })
mat("Found in clams", { [5503] = "Clam Meat", [5504] = "Tangy Clam Meat" })
mat("Caught by fishing", { [13755] = "Winter Squid" })
mat("Found in Dire Maul", { [18255] = "Runn Tum Tuber" })
