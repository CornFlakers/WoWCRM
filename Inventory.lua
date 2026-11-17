-- Works out how many of an item you own across the places you choose to count:
-- your bags, your bank, your other characters' bags and banks, and guild banks.
--
-- Your own bags and bank come from the game. Other characters come from what the
-- Mastercraft add-on has recorded (or Bagnon's shared store if Mastercraft is absent);
-- guild banks come from Bagnon's store. Those are snapshots from the last time each
-- character or guild bank was opened. No game API in this file.
local _, ns = ...
local Inv = {}
ns.Inventory = Inv

Inv.SOURCES = { "bags", "bank", "altBags", "altBank", "guild" }
Inv.LABEL = { bags = "My bags", bank = "My bank", altBags = "Alts' bags", altBank = "Alts' bank", guild = "Guild bank" }
Inv.SHORT = { bags = "bags", bank = "bank", altBags = "alts' bags", altBank = "alts' bank", guild = "guild" }

local function add(t, id, n)
	id, n = tonumber(id), tonumber(n)
	if id and n and n > 0 then t[id] = (t[id] or 0) + n end
end

-- Bagnon stores an item as "id", "id;count" or "id:details...;count".
function Inv.ParseItem(s)
	if type(s) ~= "string" then return nil end
	local id = tonumber(s:match("^(%d+)"))
	if not id then return nil end
	return id, tonumber(s:match(";(%d+)$")) or 1
end

local function addItems(items, out)
	for _, s in pairs(type(items) == "table" and items or {}) do
		local id, n = Inv.ParseItem(s)
		add(out, id, n)
	end
end

-- Every "items" list anywhere inside a guild's stored tabs.
local function walkGuild(t, out, depth)
	if type(t) ~= "table" or depth > 4 then return end
	for k, v in pairs(t) do
		if type(v) == "table" then
			if k == "items" then addItems(v, out) else walkGuild(v, out, depth + 1) end
		end
	end
end

-- opts: mastercraft = MastercraftDB.inv, guid = this character's id,
--       brother = BrotherBags, name = this character's name
-- Returns item counts per place, and which places had any data to read.
function Inv.Collect(opts)
	local data = { myBank = {}, altBags = {}, altBank = {}, guild = {}, found = { alts = false, guild = false } }
	local mc, brother = opts.mastercraft, opts.brother

	if type(mc) == "table" then
		for guid, d in pairs(mc) do
			if type(d) == "table" then
				if guid == opts.guid then
					for id, n in pairs(type(d.bank) == "table" and d.bank or {}) do add(data.myBank, id, n) end
				else
					data.found.alts = true
					for id, n in pairs(type(d.bags) == "table" and d.bags or {}) do add(data.altBags, id, n) end
					for id, n in pairs(type(d.bank) == "table" and d.bank or {}) do add(data.altBank, id, n) end
				end
			end
		end
	end

	for _, owners in pairs(type(brother) == "table" and brother or {}) do
		for owner, cache in pairs(type(owners) == "table" and owners or {}) do
			if type(owner) == "string" and type(cache) == "table" then
				if owner:sub(-1) == "*" then
					data.found.guild = true
					walkGuild(cache, data.guild, 1)
				elseif type(mc) ~= "table" and owner ~= opts.name then
					-- No Mastercraft: fall back to Bagnon for other characters. Bank bags carry a bankType.
					data.found.alts = true
					for _, bag in pairs(cache) do
						if type(bag) == "table" and type(bag.items) == "table" then
							addItems(bag.items, bag.bankType ~= nil and data.altBank or data.altBags)
						end
					end
				end
			end
		end
	end
	return data
end

-- enabled: source name -> true.  liveBags(id), liveBank(id): counts from the game for this character.
-- Returns count(id) -> total, and parts(id) -> "bags 4, bank 10" for the places that hold some.
function Inv.Counter(data, enabled, liveBags, liveBank)
	local function each(id)
		local bank = math.max(liveBank and (tonumber(liveBank(id)) or 0) or 0, data.myBank[id] or 0)
		return {
			bags = liveBags and (tonumber(liveBags(id)) or 0) or 0,
			bank = bank,
			altBags = data.altBags[id] or 0,
			altBank = data.altBank[id] or 0,
			guild = data.guild[id] or 0,
		}
	end
	local function count(id)
		local c, total = each(id), 0
		for _, src in ipairs(Inv.SOURCES) do
			if enabled[src] then total = total + c[src] end
		end
		return total
	end
	local function parts(id)
		local c, out = each(id), {}
		for _, src in ipairs(Inv.SOURCES) do
			if enabled[src] and c[src] > 0 then out[#out + 1] = Inv.SHORT[src] .. " " .. c[src] end
		end
		return #out > 0 and table.concat(out, ", ") or "none"
	end
	return count, parts
end
