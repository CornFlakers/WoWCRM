-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- The buff manager's thinking: for each buff group, are you covered, and if not, what is the
-- best thing you could use, and where is it? No game API in this file: Game.lua gathers the
-- state below and the UI shows the answer.
--
-- state:
--   class, level       "MAGE", 40
--   auras              { ["Arcane Intellect"] = true, ... }   buffs on you now
--   weapons            { [16] = { id, subclass, enchanted }, [17] = ... }   equipped weapons
--   tracking           { ["Find Herbs"] = true }   tracking that is on
--   known(name, id)    true when you have learned that spell
--   itemLevel(id)      the item's required level, or nil if the game has not said
--   itemSpell(id)      the buff name the item gives, or nil
--   stock              from Stock.Collect
--   muted              { [groupKey] = true }
--   extras             include elixirs and scrolls
--
-- Each result: { group, status, pick, better, get, where }
--   status  "active"   you have it
--           "covered"  a buff that does the same job is on you
--           "ready"    missing, and you can fix it now (in your bags, or a spell you know)
--           "elsewhere" missing, and the best you own is in your bank or on another character
--           "get"      missing, and you own nothing for it: see .get for what to go and get
--           "muted"    you asked not to be reminded
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D, Stock, Spec = ns.Data, ns.Stock, ns.Spec
local B = {}
ns.Buffs = B

-- What an option is worth to you. Options with stats are scored with your spec's weights
-- (Spec.lua); every Well Fed food is worth a little even with no useful stat, for its 5% more
-- experience from kills. Others (class spells, tracking) rank by their tier or level.
local function raw(o, state)
	if o.stats and state.weights then return Spec.Score(o.stats, state.weights) end
	return nil
end
local function value(o, g, state)
	local v = raw(o, state)
	if v == nil then return o.tier or o.level or 0 end
	if g.food then v = v + 0.5 end
	return v
end
B.Value = value

-- Does this option suit this character at all (ignoring level and whether it is owned)?
local function suits(o, g, state)
	if o.classes and not o.classes[state.class] then return false end
	if not g.food then
		local v = raw(o, state)
		if v ~= nil and v <= 0 then return false end -- a stat your spec has no use for
	end
	if g.kind == "weapon" and o.weapon then
		local w = state.weapons and state.weapons[g.slot]
		local edge = w and w.subclass and D.WEAPON[w.subclass]
		if edge and edge ~= o.weapon then return false end
	end
	return true
end

local function levelOf(o, state)
	if o.item and state.itemLevel then
		local ok, v = pcall(state.itemLevel, o.item)
		if ok and tonumber(v) then return tonumber(v) end
	end
	return o.level or 1
end

-- The buff names that count for this group: its own, its spells', its items' use effects.
function B.AuraNames(g, state)
	local names = {}
	for _, n in ipairs(g.auras or {}) do names[n] = true end
	for _, o in ipairs(g.options) do
		if o.spell then names[o.spell] = true end
		if o.item and not g.food and state.itemSpell then
			local ok, n = pcall(state.itemSpell, o.item)
			if ok and type(n) == "string" and n ~= "" then names[n] = true end
		end
	end
	return names
end

local function anyAura(names, auras)
	for n in pairs(names) do if auras[n] then return n end end
end

-- Is this group relevant to this character at all? Returns false to leave it out entirely.
B.RELEVANT = 10 -- an extra must be worth this much to your spec (its best version) to be listed

local function applies(g, state)
	if g.classes and not g.classes[state.class] then return false end
	if g.optional and not state.extras then return false end
	if g.optional and state.weights then
		local best = 0
		for _, o in ipairs(g.options) do
			if not (o.classes and not o.classes[state.class]) and (o.level or 1) <= (state.level or 1) then
				best = math.max(best, raw(o, state) or 0)
			end
		end
		if best < B.RELEVANT then return false end
	end
	if g.kind == "weapon" then
		local w = state.weapons and state.weapons[g.slot]
		if not w or not w.id then return false end
		-- ranged weapons, wands and fishing poles take no stone or oil; unknown kinds get the benefit of the doubt
		if w.subclass ~= nil and not D.WEAPON[w.subclass] then return false end
	end
	if g.kind == "tracking" then
		for _, o in ipairs(g.options) do if state.known(o.spell, o.id) then return true end end
		return false
	end
	return true
end

local function isActive(g, state)
	if g.kind == "weapon" then
		return state.weapons[g.slot].enchanted and true or false
	end
	if g.kind == "tracking" then
		for _, o in ipairs(g.options) do
			if state.tracking[o.spell] or state.auras[o.spell] then return true end
		end
		return false
	end
	return anyAura(B.AuraNames(g, state), state.auras) ~= nil
end

function B.EvaluateGroup(g, state)
	if not applies(g, state) then return nil end
	local r = { group = g }
	if isActive(g, state) then r.status = "active"; return r end
	for _, n in ipairs(g.blockedBy or {}) do
		if state.auras[n] then r.status = "covered"; r.coveredBy = n; return r end
	end

	-- every option that suits you and your level, best first; for food, also any other
	-- Well Fed food in your bags that the catalog does not know
	local options = g.options
	if g.food and state.extraFoods and #state.extraFoods > 0 then
		local known, all = {}, {}
		for _, o in ipairs(g.options) do known[o.item] = true; all[#all + 1] = o end
		for _, o in ipairs(state.extraFoods) do if not known[o.item] then all[#all + 1] = o end end
		options = all
	end
	local fits = {}
	for _, o in ipairs(options) do
		if suits(o, g, state) and levelOf(o, state) <= (state.level or 1) then fits[#fits + 1] = o end
	end
	local function tier(o) return value(o, g, state) end
	table.sort(fits, function(a, b)
		local ta, tb = tier(a), tier(b)
		if ta ~= tb then return ta > tb end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return (a.item or 0) < (b.item or 0)
	end)

	-- the best one you can use right now, and the best one you own anywhere
	local now, owned
	for _, o in ipairs(fits) do
		local cand
		if o.spell then
			if state.known(o.spell, o.id) then cand = { option = o, rank = Stock.BAGS, spell = true } end
		else
			local found = Stock.Find(state.stock, o.item)
			if #found > 0 then
				table.sort(found, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.n > b.n end)
				cand = { option = o, rank = found[1].rank, where = found }
			end
		end
		if cand then
			if not owned then owned = cand end
			if cand.rank == Stock.BAGS and not now then now = cand end
		end
	end

	if now then
		r.status, r.pick = "ready", now
		if owned ~= now and tier(owned.option) > tier(now.option) then r.better = owned end
	elseif owned then
		-- nothing usable now: the nearest place first, then the best item there
		local best = owned
		for _, o in ipairs(fits) do
			local found = (not o.spell) and Stock.Find(state.stock, o.item) or {}
			for _, f in ipairs(found) do
				if f.rank < best.rank then
					table.sort(found, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.n > b.n end)
					best = { option = o, rank = f.rank, where = found }
					break
				end
			end
		end
		r.status, r.pick = "elsewhere", best
		if best ~= owned and tier(owned.option) > tier(best.option) then r.better = owned end
	else
		r.status = "get"
	end
	-- what to go and get: the best thing for your level that you do not have
	if r.status == "get" or r.better == nil then
		-- for food, the dishes your spec's guide names come first, best of them first
		local order = fits
		local listed = g.food and state.spec and state.spec.foods
		if listed then
			local named = {}
			for _, id in ipairs(listed) do named[id] = true end
			order = {}
			for _, o in ipairs(fits) do if named[o.item] then order[#order + 1] = o end end
			for _, o in ipairs(fits) do if not named[o.item] then order[#order + 1] = o end end
		end
		for _, o in ipairs(order) do
			if not (r.pick and r.pick.option == o) then
				local mine = o.spell and state.known(o.spell, o.id) or (o.item and #Stock.Find(state.stock, o.item) > 0)
				-- an upgrade is only worth going for when it is clearly better (10% or more)
				if not mine and not o.talent and (not r.pick or tier(o) > tier(r.pick.option) * 1.1) then
					r.get = o
					break
				end
			end
		end
	end
	if state.muted and state.muted[g.key] then r.status = "muted" end
	return r
end

function B.Evaluate(state, groups)
	if not state.spec then state.spec = Spec.Resolve(state) end
	if not state.weights then state.weights = state.spec.weights end
	local out = {}
	for _, g in ipairs(groups or D.GROUPS) do
		local r = B.EvaluateGroup(g, state)
		if r then out[#out + 1] = r end
	end
	return out
end

-- The reminders that belong on screen: missing buffs you can fix now, and missing core buffs
-- whose item is in your bank or on another character. Extras only when in your bags.
function B.Reminders(results)
	local out = {}
	for _, r in ipairs(results) do
		if r.status == "ready" or (r.status == "elsewhere" and not r.group.optional) then out[#out + 1] = r end
	end
	return out
end

-- The "what to go and get" list.
function B.Shopping(results)
	local out = {}
	for _, r in ipairs(results) do
		if r.get and r.status ~= "muted" and r.status ~= "covered" then out[#out + 1] = r end
	end
	return out
end

-- "Mithril Head Trout (+20 Attack Power)"
local function optionName(o)
	if o.spell then return o.spell end
	local stats = o.stats and Spec.StatText(o.stats) or ""
	if stats ~= "" and not (o.stats.wdmg and o.stats.wdmg < 1) and not o.stats.poison and not o.stats.imbue then
		return o.name .. " (" .. stats .. ")"
	end
	if o.stats and o.stats.mcrit then return o.name .. " (+" .. o.stats.mcrit .. "% melee crit)" end
	return o.name
end
B.OptionName = optionName

-- One line of text for a result.
function B.Describe(r)
	local g, p = r.group, r.pick
	if r.status == "active" then return g.label .. ": active" end
	if r.status == "covered" then return g.label .. ": covered by " .. r.coveredBy end
	if r.status == "muted" then return g.label .. ": muted" end
	if r.status == "ready" then
		local s
		if p.spell then s = "cast " .. optionName(p.option)
		else s = "use " .. optionName(p.option) .. " (" .. Stock.Describe(p.where, 2) .. ")" end
		if r.better then s = s .. "; better: " .. optionName(r.better.option) .. (r.better.where and (" in " .. Stock.Describe(r.better.where, 1)) or "") end
		return g.label .. " missing: " .. s
	end
	if r.status == "elsewhere" then
		return g.label .. " missing: " .. optionName(p.option) .. " is in " .. Stock.Describe(p.where, 2)
	end
	return g.label .. " missing: nothing for it in your bags, bank or other characters"
end

-- One line for the shopping list: what, and roughly where to get it.
function B.DescribeGet(r)
	local o = r.get
	if o.spell then
		return ("%s: train %s at your class trainer (from about level %d)"):format(r.group.label, o.spell, o.level or 1)
	end
	return ("%s: %s - %s"):format(r.group.label, optionName(o), o.source or "Auction House")
end

-- The slash text a secure button runs for a result, or nil when nothing can be clicked.
-- Items go through /use with the item id; weapon items are then put on the weapon slot.
function B.Macro(r)
	if r.status ~= "ready" or not r.pick then return nil end
	local o = r.pick.option
	if o.spell then
		if r.group.kind == "tracking" then return "/cast " .. o.spell end
		return "/cast [target=player] " .. o.spell
	end
	if r.group.kind == "weapon" then
		return ("/use item:%d\n/use %d"):format(o.item, r.group.slot)
	end
	return ("/use item:%d"):format(o.item)
end
