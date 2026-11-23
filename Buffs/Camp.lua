-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- Camping (WoW: Forever): camp objects that professions craft and place by a campfire. Anyone
-- sitting nearby for a minute gets their buff for an hour. This file knows the objects, which
-- ones suit your class and talent spec best, and which of those you are missing. No game API.
--
-- Where the facts and rankings come from (read November 2026):
--   * Wowhead's Forever camping guide (guide=34796) and the camp spells' own tooltips
--     (spell 1307229 and up): what each object does, its size by level, what it does not stack with.
--   * Wowhead's Forever class levelling guides, one per talent spec, each with a
--     "Best Levelling Camping Buffs" section: the per-spec order below.
--   * WowVendor's "Best WoW Forever Camping buffs" tier list (15 Nov 2026): the per-role
--     lists used when you set your style yourself with /crm buffs style.
-- A camp buff counts as on when its spell id or one of the object's names is among your buffs.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D, Stock = ns.Data, ns.Stock
local C = {}
ns.Camp = C

local function camp101(prof)
	return ('Quest "Camping 101: %s", from your %s trainer (offered after "The Great Outdoors", around level 5)'):format(prof, prof)
end

-- Size of a buff at a level, from bands { { below level, value }, ..., { nil, value } }.
local function band(list)
	return function(level)
		for _, b in ipairs(list) do
			if not b[1] or level < b[1] then return b[2] end
		end
	end
end

-- items: tier 1, 2, 3 (higher tiers keep the tier 1 buff); names: what may show as your buff;
-- spells: the camp buff spell ids; exclusive: class buffs it does not stack with
C.FEATURES = {
	{ key = "fishbowl", name = "Fish Bowl", prof = "Fishing", buff = "8% more stats",
		exclusive = { "Blessing of Kings", "Greater Blessing of Kings" }, spells = { 1307245, 1307246, 1307247 },
		items = { 279967, 279965, 279966 }, names = { "Fish Bowl", "Fishing Rack", "Fishing Hut" },
		mats = { { 6291, 1 }, { 3371, 1 } },
		upgrades = "Fishing Rack (blueprint from Doctor Theolen Krastinov), Fishing Hut (Jammal'an the Prophet, Sunken Temple)" },
	{ key = "lute", name = "Enchanted Lute", prof = "Enchanting", buff = "armor, all stats and resistances",
		size = band({ { 10, 28 }, { 20, 71 }, { 30, 114 }, { 40, 163 }, { 50, 211 }, { 60, 260 }, { nil, 308 } }), unit = "armor, plus stats and resistances",
		exclusive = { "Mark of the Wild", "Gift of the Wild" }, spells = { 1307234, 1307223 },
		items = { 279976, 279985, 279987 }, names = { "Enchanted Lute", "Arcane Salvager", "Arcane Forge" },
		upgrades = "Arcane Salvager (Charlga Razorflank, Razorfen Kraul), Arcane Forge (Nanaya, Shaper's Terrace)" },
	{ key = "lodestone", name = "Lodestone", prof = "Mining", buff = "melee attack power",
		size = band({ { 12, 12 }, { 22, 20 }, { 32, 32 }, { 42, 49 }, { 52, 67 }, { nil, 90 } }), unit = "melee attack power",
		exclusive = { "Blessing of Might", "Greater Blessing of Might" }, spells = { 1307254, 1307264 },
		items = { 279960, 279948, 279952 }, names = { "Lodestone", "Rock Garden", "Molten Foundry" },
		mats = { { 2835, 1 }, { 2840, 1 } },
		upgrades = "Rock Garden (Relic Guardian, Excavation Site in the Wetlands), Molten Foundry (Relic Guardian, Blackrock Depths)" },
	{ key = "wheel", name = "Sharpening Wheel", prof = "Blacksmithing", buff = "Strength (+34 at level 60)",
		exclusive = { "Strength of Earth" }, spells = { 1307261 },
		items = { 279944, 279988, 279955 }, names = { "Sharpening Wheel", "Anvil", "Master Forge" },
		upgrades = "Anvil (Gilnid, The Deadmines), Master Forge (Golem Lord Argelmach, Blackrock Depths)" },
	{ key = "chair", name = "Camp Chair", prof = "Skinning", buff = "+2% critical strike with spells and attacks",
		exclusive = { "Moonkin Aura", "Leader of the Pack" }, spells = { 1307229, 1307243 },
		items = { 279979, 279969, 279938 }, names = { "Camp Chair", "Field Guide", "Trapper's Workbench" },
		upgrades = "Field Guide (Lady Anacondra, Wailing Caverns), Trapper's Workbench (The Beast, Blackrock Spire)" },
	{ key = "candle", name = "Incense Candle", prof = "Herbalism", buff = "Intellect",
		size = band({ { 14, 2 }, { 28, 6 }, { 42, 12 }, { 56, 18 }, { nil, 25 } }), unit = "Intellect",
		exclusive = { "Arcane Intellect", "Arcane Brilliance" }, spells = { 1307251, 1307248 },
		items = { 279962, 279964, 279947 }, names = { "Incense Candle", "Greenhouse", "Seed Hybridizer" },
		upgrades = "Greenhouse (Shadetooth, Excavation Site in the Wetlands), Seed Hybridizer (Tendris Warpwood, Dire Maul)" },
	{ key = "banner", name = "Faction Banner", prof = "Tailoring", buff = "Spirit",
		size = band({ { 40, 14 }, { 50, 19 }, { 60, 27 }, { nil, 32 } }), unit = "Spirit",
		exclusive = { "Divine Spirit", "Prayer of Spirit" }, spells = { 1307239, 1307240, 1307255 },
		items = { 279972, 279943, 279959 }, names = { "Faction Banner", "Spinning Wheel", "Loom" },
		upgrades = "Spinning Wheel (Unstable Sentinel, Dalaran), Loom (Baroness Anastari, Stratholme)" },
	{ key = "manawell", name = "Mana Well", prof = "Alchemy", buff = "mana every 5 sec",
		size = band({ { 24, 10 }, { 34, 15 }, { 44, 20 }, { 54, 24 }, { nil, 29 } }), unit = "mana every 5 sec",
		exclusive = { "Blessing of Wisdom", "Greater Blessing of Wisdom" }, spells = { 1307259, 1307242 },
		items = { 279956, 279970, 279990 }, names = { "Mana Well", "Fermenter", "Alchemy Laboratory" },
		mats = { { 2447, 1 }, { 3371, 1 } },
		upgrades = "Fermenter (Rath'mael, Ruins of Lordaeron), Alchemy Laboratory (Ras Frostwhisper, Scholomance)" },
	{ key = "firstaid", name = "First Aid Kit", prof = "First Aid", buff = "Stamina",
		size = band({ { 12, 3 }, { 24, 8 }, { 36, 21 }, { 48, 34 }, { 60, 45 }, { nil, 56 } }), unit = "Stamina",
		exclusive = { "Power Word: Fortitude", "Prayer of Fortitude" }, spells = { 1307244, 1307265 },
		items = { 279968, 279940, 279951 }, names = { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" },
		upgrades = "Toxin Study (Commander Springvale, Shadowfang Keep), Plague Doctor's Laboratory (Doctor Theolen Krastinov, Scholomance)" },
	{ key = "feast", name = "Cookie's Feast", prof = "Cooking", skill = 140, buff = "Stamina food for everyone at the camp",
		spells = { 1307257 }, items = { 279957 }, names = { "Cookie's Feast" },
		recipe = "Blueprint drops from Cookie in The Deadmines (needs Cooking 140)" },
	{ key = "tent", name = "Camp Tent", prof = "Leatherworking", buff = "tops rested XP up to 5% of a level", leveling = true,
		spells = { 1307230 },
		items = { 279978, 279941, 279945 }, names = { "Camp Tent", "Tanning Rack", "Sewing Machine" },
		upgrades = "Tanning Rack (Razorclaw the Butcher, Shadowfang Keep), Sewing Machine (Vectus, Scholomance)" },
}
C.CAMPFIRE = { 279981, 279961, 279974 } -- Basic, Journeyman, Expert Campfire Kit

-- ---------------------------------------------------------------- rankings
-- Per class and talent tree (1, 2, 3 in the talent window's order), best first, leaving out the
-- Camp Tent, which goes in by level (see C.Order). From each spec's Wowhead levelling guide.
local W = "Wowhead's %s levelling guide"
C.TREES = {
	WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral", "Restoration" },
}
C.CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
-- The tree most people level in, used before you have spent talent points.
C.DEFAULT_TREE = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

local ROGUE = { order = { "chair", "wheel", "lodestone", "fishbowl", "lute", "firstaid" },
	note = "Its top three: Camp Chair, Sharpening Wheel, Lodestone - the buffs you are least likely to get from other classes." }
local MAGE = { order = { "banner", "manawell", "candle", "firstaid", "chair", "fishbowl", "lute" },
	note = "Camp Tent matters most while levelling; the rest are nice to have. Incense Candle does not stack with your Arcane Intellect." }
local LOCK = { order = { "manawell", "candle", "firstaid", "chair", "fishbowl", "lute" },
	note = "Camp Tent matters most while levelling. Stamina is more health to Life Tap with; spell crit helps your damage over time." }
local HUNTER = { order = { "fishbowl", "lute", "chair", "manawell", "candle", "lodestone" },
	note = "Fish Bowl, Enchanted Lute, Camp Chair and Mana Well always help; Camp Tent is a nice extra; Incense Candle less so." }
C.SPEC = {
	WARRIOR = {
		{ order = { "lodestone", "wheel", "chair", "fishbowl", "lute", "firstaid" },
			note = "If you can only have one, Camp Tent gives the most while levelling." },
		{ order = { "chair", "fishbowl", "lodestone", "wheel", "lute", "firstaid" },
			note = "Camp Chair and Camp Tent first: crit feeds Flurry and rage. Then Fish Bowl and Lodestone." },
		{ order = { "wheel", "chair", "fishbowl", "firstaid", "lodestone", "banner", "lute" },
			note = "Strength and attack power early; Camp Chair (crit you cannot get elsewhere) and First Aid Kit later. Camp Tent is worth it from about level 22." },
	},
	PALADIN = {
		{ order = { "manawell", "candle", "fishbowl", "chair", "banner", "firstaid", "lute", "wheel", "lodestone" },
			note = "Almost every camp buff helps a Holy Paladin. Fish Bowl does not stack with Kings, Lodestone not with Might." },
		{ order = { "wheel", "chair", "banner", "lodestone", "manawell", "fishbowl", "firstaid" },
			note = "Sharpening Wheel and Faction Banner early; Lodestone and Mana Well from level 14 once you use a different Blessing. Camp Tent from about level 22." },
		{ order = { "wheel", "chair", "fishbowl", "manawell", "candle", "lodestone" },
			note = "Sharpening Wheel is your best damage buff while levelling. Skip Lodestone while Blessing of Might is on you; Fish Bowl stands in for Kings." },
	},
	HUNTER = {
		HUNTER, HUNTER,
		{ order = { "fishbowl", "lute", "chair", "manawell", "lodestone", "wheel", "candle" },
			note = "Lodestone and Sharpening Wheel help Survival's melee, a little below the always-useful four." },
	},
	ROGUE = { ROGUE, ROGUE, ROGUE },
	PRIEST = {
		{ order = { "manawell", "lute", "candle", "banner", "fishbowl", "firstaid" },
			note = "Camp Tent is a major time save; Mana Well, Enchanted Lute and Incense Candle are the ones to look for. Camp whenever you are back in town." },
		{ order = { "banner", "manawell", "candle", "lute", "fishbowl", "firstaid" },
			note = "Spirit is your regeneration out of combat; Mana Well ticks while you cast. First Aid Kit does not stack with Fortitude, nor Banner with Divine Spirit." },
		{ order = { "manawell", "lute", "candle", "fishbowl", "chair", "firstaid" },
			note = "Camp Tent, Mana Well, Enchanted Lute and Incense Candle are the most useful. First Aid Kit does not stack with your Fortitude." },
	},
	SHAMAN = {
		{ order = { "chair", "manawell", "candle", "fishbowl", "banner", "lute" },
			note = "Shamans use nearly every stat. Camp Chair's crit works with your talents; Camp Tent is free experience." },
		{ order = { "chair", "fishbowl", "wheel", "lodestone", "manawell", "lute" },
			note = "Strength and attack power feel strong early, Fish Bowl's 8% later. Sharpening Wheel does not stack with Strength of Earth Totem." },
		{ order = { "chair", "manawell", "candle", "fishbowl", "banner", "lute" },
			note = "Shamans use nearly every stat. Camp Chair's crit works with your healing talents; Camp Tent is free experience." },
	},
	MAGE = { MAGE, MAGE, MAGE },
	WARLOCK = { LOCK, LOCK, LOCK },
	DRUID = {
		{ order = { "manawell", "candle", "chair", "banner", "fishbowl", "lute" },
			note = "Mana Well cuts your downtime most. Camp Chair stops counting once you have Moonkin Aura (level 40)." },
		{ order = { "chair", "fishbowl", "lodestone", "wheel", "firstaid", "lute" },
			note = "Camp Chair is your best damage buff until Leader of the Pack, then Fish Bowl. Camp Tent is a must-have past level 30. Bears: Fish Bowl and First Aid Kit first." },
		{ order = { "manawell", "fishbowl", "candle", "chair", "banner" },
			note = "Skip Enchanted Lute: it does not stack with your Mark of the Wild." },
	},
}
for class, trees in pairs(C.SPEC) do
	for i, s in ipairs(trees) do
		-- specs of one class may share a list; each gets its own copy naming its own guide
		trees[i] = { order = s.order, note = s.note, source = W:format(C.TREES[class][i] .. " " .. C.CLASS_NAMES[class]) }
	end
end
-- Feral druids who tank (set /crm buffs style tank) get the bear list.
C.FERAL_TANK = { order = { "fishbowl", "firstaid", "wheel", "lodestone", "chair", "lute" },
	note = "Fish Bowl and First Aid Kit always; Strength and attack power next. Camp Chair and Enchanted Lute overlap your own Leader of the Pack and Mark of the Wild.",
	source = "Wowhead's Feral Druid tank levelling guide" }

-- Per role, when you set your style yourself (/crm buffs style). From WowVendor's tier list.
C.STYLE_ORDER = {
	tank = { "firstaid", "fishbowl", "lute", "chair", "wheel", "lodestone" },
	melee = { "chair", "lodestone", "wheel", "fishbowl", "lute", "firstaid" },
	ranged = { "chair", "fishbowl", "candle", "lute", "manawell", "firstaid" },
	caster = { "manawell", "candle", "chair", "fishbowl", "banner", "lute" },
	healer = { "manawell", "fishbowl", "firstaid", "candle", "banner", "lute" },
}
C.STYLE_LABEL = { tank = "tank", melee = "melee damage", ranged = "ranged damage", caster = "spell damage", healer = "healer" }
C.STYLE_SOURCE = "WowVendor's camping buff tier list (role picks)"

C.WHY = {
	fishbowl = "8% more of every stat; top of most tier lists",
	lute = "armor, stats and resistances",
	lodestone = "flat melee attack power",
	wheel = "Strength, which turns into attack power",
	chair = "2% crit, which hardly anything else gives",
	candle = "Intellect: a bigger mana pool",
	manawell = "mana back even while you cast",
	banner = "Spirit: regeneration between fights",
	firstaid = "Stamina: more health",
	feast = "Stamina food for the whole camp",
	tent = "rested XP: the biggest speed-up while levelling",
}

-- Tree with the most points, or nil before any are spent.
function C.TopTree(points)
	local best, most = nil, 0
	for tab, n in pairs(points or {}) do
		if (tonumber(n) or 0) > most then best, most = tab, tonumber(n) end
	end
	return best
end

local TREE_STYLE = {
	WARRIOR = { "melee", "melee", "tank" }, PALADIN = { "healer", "tank", "melee" }, HUNTER = { "ranged", "ranged", "ranged" },
	ROGUE = { "melee", "melee", "melee" }, PRIEST = { "healer", "healer", "caster" }, SHAMAN = { "caster", "melee", "healer" },
	MAGE = { "caster", "caster", "caster" }, WARLOCK = { "caster", "caster", "caster" }, DRUID = { "caster", "melee", "healer" },
}
function C.StyleFromTalents(class, points)
	local tree = C.TopTree(points) or C.DEFAULT_TREE[class]
	return (TREE_STYLE[class] and TREE_STYLE[class][tree]) or "melee"
end

function C.Feature(key)
	for _, f in ipairs(C.FEATURES) do if f.key == key then return f end end
end

-- What to rank by. state: { class, talents = { [tree] = points }, styleOverride, level, maxLevel }
-- Returns { order = { keys }, label, source, note }
function C.Plan(state)
	local plan
	local class = state.class
	if state.styleOverride == "tank" and class == "DRUID" then
		plan = C.FERAL_TANK
		plan = { order = plan.order, note = plan.note, source = plan.source, label = "Feral Druid tank" }
	elseif state.styleOverride and C.STYLE_ORDER[state.styleOverride] then
		plan = { order = C.STYLE_ORDER[state.styleOverride], source = C.STYLE_SOURCE, label = C.STYLE_LABEL[state.styleOverride],
			note = "Set with /crm buffs style; /crm buffs style auto goes back to your talents." }
	else
		local tree = C.TopTree(state.talents)
		local guessed = tree == nil
		tree = tree or C.DEFAULT_TREE[class] or 1
		local spec = C.SPEC[class] and C.SPEC[class][tree]
		if spec then
			plan = { order = spec.order, note = spec.note, source = spec.source,
				label = C.TREES[class][tree] .. " " .. C.CLASS_NAMES[class] .. (guessed and " (no talents yet, so a guess)" or "") }
		else
			plan = { order = C.STYLE_ORDER.melee, source = C.STYLE_SOURCE, label = "melee damage" }
		end
	end
	local order = {}
	for _, k in ipairs(plan.order) do order[#order + 1] = k end
	-- Camp Tent: first while levelling from about level 20 (every spec's guide rates it highly),
	-- third before that (it is a small amount of experience early on), gone at max level.
	local level, max = state.level or 1, state.maxLevel or 60
	if level < max then table.insert(order, level >= 20 and 1 or math.min(3, #order + 1), "tent") end
	plan.order = order
	return plan
end

-- The guide entry for each camp item, so hovering one shows how it is made.
for _, f in ipairs(C.FEATURES) do
	for _, id in ipairs(f.items) do D.EXTRA_ITEMS[#D.EXTRA_ITEMS + 1] = id end
	D.HOW[f.items[1]] = { prof = f.prof, skill = f.skill or 20, mats = f.mats,
		recipe = f.recipe or (camp101(f.prof) .. (f.upgrades and ("; upgrades: " .. f.upgrades) or "")) }
end
for _, id in ipairs(C.CAMPFIRE) do D.EXTRA_ITEMS[#D.EXTRA_ITEMS + 1] = id end
D.HOW[C.CAMPFIRE[1]] = { prof = "Cooking", skill = 1, mats = { { 4470, 1 }, { 4471, 1 } },
	recipe = 'Taught by Cooking trainers after "The Great Outdoors" (around level 5); they also sell Simple Wood and Flint and Tinder' }
D.MATS[4470] = { name = "Simple Wood", note = "Sold by Cooking trainers and trade supply vendors" }
D.MATS[4471] = { name = "Flint and Tinder", note = "Sold by Cooking trainers and trade supply vendors" }
D.MATS[6291] = { name = "Raw Brilliant Smallfish", note = "Caught by fishing in starting-zone waters" }
D.MATS[2447] = { name = "Peacebloom", note = "Picked with Herbalism; also on the Auction House" }
D.MATS[2840] = { name = "Copper Bar", note = "Smelted from Copper Ore (Mining 1); also on the Auction House" }

local function owned(stock, items)
	local all = {}
	for _, id in ipairs(items) do
		for _, f in ipairs(Stock.Find(stock, id)) do all[#all + 1] = { label = f.label, rank = f.rank, n = f.n, item = id } end
	end
	table.sort(all, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.n > b.n end)
	return all
end
C.Owned = owned

-- "+49 melee attack power at your level", or the plain description
function C.BuffText(f, level)
	if f.size then return ("+%d %s at your level"):format(f.size(level or 1), f.unit) end
	return f.buff
end

-- state: { class, talents, styleOverride, level, maxLevel, auras, auraIds, stock }
-- Returns { label, source, note, list = { { feature, status, coveredBy, where, why }, ... best first },
--           missing = n in the top 3, top = 3, campfire = where your campfire kits are }
--   status: "active", "covered" (a class buff that does not stack is on you), "ready" (in your bags),
--           "elsewhere" (owned on a bank or another character), "get"
function C.Evaluate(state)
	local plan = C.Plan(state)
	local out = { label = plan.label, source = plan.source, note = plan.note, list = {}, missing = 0, top = 3, level = state.level }
	local ids = state.auraIds or {}
	for i, key in ipairs(plan.order) do
		local f = C.Feature(key)
		local r = { feature = f, why = C.WHY[key], rank = i }
		for _, n in ipairs(f.names) do if state.auras[n] then r.status = "active" end end
		for _, id in ipairs(f.spells or {}) do if ids[id] then r.status = "active" end end
		if not r.status then
			for _, n in ipairs(f.exclusive or {}) do
				if state.auras[n] then r.status, r.coveredBy = "covered", n end
			end
		end
		if not r.status then
			r.where = owned(state.stock, f.items)
			if #r.where == 0 then r.status = "get"
			elseif r.where[1].rank == Stock.BAGS then r.status = "ready"
			else r.status = "elsewhere" end
		end
		out.list[#out.list + 1] = r
	end
	-- the top three that would actually do something (covered ones are skipped)
	local counted = 0
	for _, r in ipairs(out.list) do
		if r.status ~= "covered" then
			counted = counted + 1
			r.top = counted <= out.top
			if r.top and r.status ~= "active" then out.missing = out.missing + 1 end
		end
	end
	out.campfire = owned(state.stock, C.CAMPFIRE)
	return out
end

-- "Fish Bowl, Lodestone": the best ones you are missing
function C.MissingTop(camp)
	local names = {}
	for _, r in ipairs(camp.list) do
		if r.top and r.status ~= "active" then names[#names + 1] = r.feature.name end
	end
	return names
end

function C.Describe(r, level)
	local f = r.feature
	if r.status == "active" then return f.name .. ": on (" .. C.BuffText(f, level) .. ")" end
	if r.status == "covered" then return f.name .. ": your " .. r.coveredBy .. " does the same job (they do not stack)" end
	local s = f.name .. " (" .. C.BuffText(f, level) .. ")"
	if r.status == "ready" then return s .. ": in your bags, place it by a campfire" end
	if r.status == "elsewhere" then return s .. ": in " .. Stock.Describe(r.where, 2) end
	return s .. ": made by " .. f.prof .. " - hover for how"
end
