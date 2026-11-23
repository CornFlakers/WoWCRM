-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- Where your items are: your bags, your bank (as last seen), and your other characters.
--
-- Your bags come from the game. Your bank comes from the game while you are at it, and from
-- the snapshot this add-on (or Mastercraft, or Bagnon) took the last time you were there.
-- Other characters come from Mastercraft's inventory (MastercraftDB.inv) and from
-- BagBrother/Bagnon's shared store (BrotherBags). No game API in this file.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local S = {}
ns.Stock = S

S.BAGS, S.BANK, S.OTHER = 1, 2, 3

local function add(t, id, n)
	id, n = tonumber(id), tonumber(n)
	if id and n and n > 0 then t[id] = (t[id] or 0) + n end
end

-- Bagnon stores an item as "id", "id;count" or "id:details...;count".
function S.ParseItem(s)
	if type(s) ~= "string" then return nil end
	local id = tonumber(s:match("^(%d+)"))
	if not id then return nil end
	return id, tonumber(s:match(";(%d+)$")) or 1
end

local function addItems(items, out)
	for _, s in pairs(type(items) == "table" and items or {}) do
		local id, n = S.ParseItem(s)
		add(out, id, n)
	end
end

-- Every "items" list anywhere inside a guild's stored tabs.
local function walk(t, out, depth)
	if type(t) ~= "table" or depth > 4 then return end
	for k, v in pairs(t) do
		if type(v) == "table" then
			if k == "items" then addItems(v, out) else walk(v, out, depth + 1) end
		end
	end
end

local function copyCounts(t, out)
	for id, n in pairs(type(t) == "table" and t or {}) do add(out, id, n) end
end

local function same(a, b)
	return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- Mastercraft keeps a character's first name and surname apart.
function S.MastercraftName(info)
	if type(info) ~= "table" or type(info.name) ~= "string" then return nil end
	if type(info.surname) == "string" and info.surname ~= "" then return info.name .. " " .. info.surname end
	return info.name
end

-- opts:
--   me          this character's name (with surname, if any)
--   guid        this character's GUID
--   bags(id)    count in bags now (from the game)
--   bank(id)    count in the bank from the game (0 when the game does not know)
--   savedBank   { [id] = n } this add-on's last look at this character's bank
--   mastercraft MastercraftDB
--   brother     BrotherBags
-- Returns a stock: a list of places { label, rank, owner, counts = { [id] = n } }.
function S.Collect(opts)
	local bank = {}
	copyCounts(opts.savedBank, bank)
	local places = {}
	local others = {} -- owner name -> { bags = {}, bank = {}, mail = {} }
	local order = {}
	local function other(name)
		if not others[name] then
			others[name] = { bags = {}, bank = {}, mail = {} }
			order[#order + 1] = name
		end
		return others[name]
	end
	local function maxInto(dst, src)
		for id, n in pairs(src) do if n > (dst[id] or 0) then dst[id] = n end end
	end

	local mc = type(opts.mastercraft) == "table" and opts.mastercraft or nil
	local mcNames = {}
	if mc and type(mc.inv) == "table" then
		local chars = type(mc.chars) == "table" and mc.chars or {}
		for guid, d in pairs(mc.inv) do
			if type(d) == "table" then
				local name = S.MastercraftName(chars[guid]) or tostring(guid)
				if guid == opts.guid or same(name, opts.me) then
					local b = {}
					copyCounts(d.bank, b)
					maxInto(bank, b)
				else
					mcNames[name:lower()] = true
					local o = other(name)
					copyCounts(d.bags, o.bags)
					copyCounts(d.bank, o.bank)
					copyCounts(d.mail, o.mail)
				end
			end
		end
	end

	for _, owners in pairs(type(opts.brother) == "table" and opts.brother or {}) do
		for owner, cache in pairs(type(owners) == "table" and owners or {}) do
			if type(owner) == "string" and type(cache) == "table" then
				local guild = owner:sub(-1) == "*"
				local mine = same(owner, opts.me)
				if guild or mine or not mcNames[owner:lower()] then
					local bagsT, bankT = {}, {}
					if guild then walk(cache, bankT, 1) end
					for _, bag in pairs(guild and {} or cache) do
						if type(bag) == "table" and type(bag.items) == "table" then
							addItems(bag.items, bag.bankType ~= nil and bankT or bagsT)
						end
					end
					if mine then
						maxInto(bank, bankT)
					elseif guild then
						local o = other("Guild bank (" .. owner:sub(1, -2) .. ")")
						copyCounts(bankT, o.bank)
					else
						local o = other(owner)
						copyCounts(bagsT, o.bags)
						copyCounts(bankT, o.bank)
					end
				end
			end
		end
	end

	-- the game's own view of the bank is current while you are there
	places[1] = { label = "your bags", rank = S.BAGS, live = opts.bags }
	places[2] = { label = "your bank", rank = S.BANK, counts = bank, live = opts.bank, liveMax = true }
	table.sort(order)
	for _, name in ipairs(order) do
		local o = others[name]
		local guild = name:find("^Guild bank") ~= nil
		if guild then
			places[#places + 1] = { label = name, owner = name, rank = S.OTHER, counts = o.bank }
		else
			places[#places + 1] = { label = name .. "'s bags", owner = name, rank = S.OTHER, counts = o.bags }
			places[#places + 1] = { label = name .. "'s bank", owner = name, rank = S.OTHER, counts = o.bank }
			places[#places + 1] = { label = name .. "'s mailbox", owner = name, rank = S.OTHER, counts = o.mail }
		end
	end
	return places
end

local function countAt(place, id)
	local n = place.counts and place.counts[id] or 0
	if place.live then
		local ok, v = pcall(place.live, id)
		v = ok and tonumber(v) or 0
		if place.liveMax then n = math.max(n, v) else n = v end
	end
	return n
end

-- Every place that holds the item, best place first: { { label, rank, n }, ... }
function S.Find(stock, id)
	local out = {}
	for _, p in ipairs(stock or {}) do
		local n = countAt(p, id)
		if n > 0 then out[#out + 1] = { label = p.label, rank = p.rank, owner = p.owner, n = n } end
	end
	return out
end

-- "your bank (5)" / "Skotor Ironmark's bags (3), your bank (2)"
function S.Describe(found, limit)
	local parts = {}
	for i, f in ipairs(found or {}) do
		if limit and i > limit then parts[#parts + 1] = "..."; break end
		parts[#parts + 1] = ("%s (%d)"):format(f.label, f.n)
	end
	return table.concat(parts, ", ")
end
