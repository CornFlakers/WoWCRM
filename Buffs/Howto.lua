-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- "How do I get this?": the lines under an item or spell's tooltip. What you already have
-- and where, who makes it, which of your characters can, the materials (with how many of each
-- you own) and where the recipe comes from.
--
-- Exact materials come from your own characters' profession scans, which Mastercraft saves in
-- MastercraftDB.recipes (learned and not-yet-learned recipes). Otherwise the guide in Guide.lua
-- is used. No game API in this file.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D, Stock = ns.Data, ns.Stock
local H = {}
ns.Howto = H

-- Every recipe your characters' scans hold, by what it makes:
-- { [outputItemID] = { { who, prof, learned, reagents = { { id, n } } }, ... } }
-- and which characters have which profession: profs[prof] = { name, ... }
function H.Index(mastercraft)
	local byOutput, profs = {}, {}
	local mc = type(mastercraft) == "table" and mastercraft or {}
	local chars = type(mc.chars) == "table" and mc.chars or {}
	for guid, list in pairs(type(mc.recipes) == "table" and mc.recipes or {}) do
		local who = Stock.MastercraftName(chars[guid]) or tostring(guid)
		for prof, p in pairs(type(list) == "table" and list or {}) do
			if type(p) == "table" and type(p.list) == "table" then
				profs[prof] = profs[prof] or {}
				table.insert(profs[prof], who)
				for _, rec in ipairs(p.list) do
					local out = type(rec) == "table" and tonumber(rec.output)
					if out then
						local mats = {}
						for _, r in ipairs(type(rec.reagents) == "table" and rec.reagents or {}) do
							local id, n = tonumber(r.itemID), tonumber(r.qty)
							if id and n then mats[#mats + 1] = { id, n } end
						end
						byOutput[out] = byOutput[out] or {}
						table.insert(byOutput[out], { who = who, prof = prof, learned = rec.learned and true or false, reagents = mats })
					end
				end
			end
		end
	end
	for _, list in pairs(byOutput) do
		table.sort(list, function(a, b)
			if a.learned ~= b.learned then return a.learned end
			return a.who < b.who
		end)
	end
	for _, names in pairs(profs) do table.sort(names) end
	return { byOutput = byOutput, profs = profs }
end

local function nameOf(id, ctx)
	local n = ctx.itemName and ctx.itemName(id)
	if type(n) == "string" and n ~= "" then return n end
	local m = D.MATS[id]
	return m and m.name or ("item " .. id)
end

-- ctx: { stock, index (from H.Index), itemName(id), known(name, id), level }
-- Returns lines: { { text, kind } } where kind is "head", "good", "warn", "info" or "dim".
function H.Lines(o, ctx)
	local out = {}
	local function add(text, kind) out[#out + 1] = { text, kind or "info" } end

	if o.spell then
		if ctx.known and ctx.known(o.spell, o.id) then add("You know this spell.", "good")
		elseif o.talent then add("A talent: put a talent point into it to learn it.", "warn")
		else
			local lvl = o.level or 1
			if (ctx.level or 1) >= lvl then add("Train it at your class trainer (from about level " .. lvl .. ").", "warn")
			else add("You can train it at your class trainer from about level " .. lvl .. ".", "dim") end
		end
		return out
	end

	local id = o.item
	local found = Stock.Find(ctx.stock, id)
	if #found > 0 then add("You have: " .. Stock.Describe(found, 3), "good")
	else add("You have none on any character.", "warn") end

	local guide = D.HOW[id]
	local scans = ctx.index and ctx.index.byOutput[id] or nil
	local prof = (scans and scans[1] and scans[1].prof) or (guide and guide.prof)
	if not prof then
		add("How to get it", "head")
		add(o.source or "Auction House", "info")
		return out
	end

	add("How to get it", "head")
	add(("Made with %s%s"):format(prof, guide and guide.skill and (" (about skill " .. guide.skill .. ")") or ""), "info")

	-- which of your characters can make it
	local told = {}
	for i, s in ipairs(scans or {}) do
		if i > 3 then break end
		told[s.who] = true
		if s.learned then add(s.who .. " knows this recipe", "good")
		else add(s.who .. " has " .. s.prof .. " but has not learned this recipe yet", "warn") end
	end
	local others = ctx.index and ctx.index.profs[prof] or {}
	for _, who in ipairs(others) do
		if not told[who] then add(who .. " has " .. prof .. "; this recipe is not in their list yet", "dim") end
	end
	if not scans and #others == 0 then add("None of your characters has " .. prof .. " (in Mastercraft's scans)", "dim") end

	-- materials
	local mats, from = nil, nil
	if scans and #scans[1].reagents > 0 then mats, from = scans[1].reagents, "from " .. scans[1].who .. "'s recipe"
	elseif guide and guide.mats then mats, from = guide.mats, "usual recipe" end
	if mats then
		add("Materials (" .. from .. "):", "head")
		for _, m in ipairs(mats) do
			local have = Stock.Find(ctx.stock, m[1])
			local line = ("  %d x %s: "):format(m[2], nameOf(m[1], ctx))
			if #have > 0 then
				add(line .. "you have " .. Stock.Describe(have, 2), "good")
			else
				local note = D.MATS[m[1]] and D.MATS[m[1]].note or "Auction House"
				add(line .. "none - " .. note, "warn")
			end
		end
	else
		add("Materials: open the " .. prof .. " window on a character that has it, and Mastercraft records them.", "dim")
	end

	if guide and guide.recipe then add("Recipe: " .. guide.recipe, "info") end
	add("Or buy it on the Auction House, or from a player who makes it.", "dim")
	return out
end
