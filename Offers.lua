-- Bag offers for players you meet out in the world: "bring the cloth, pay for thread and dye
-- plus a small tip, and I make it right here".
-- No game API in this file: the recipe list, names and prices are passed in.
--
-- Recipes come from the same scan the Products tab reads ({ id, name, learned, output, outputQty,
-- reagents = { { itemID, qty } } }), so quantities are whatever this client says they are.
-- Parts you make yourself (bolts of cloth) are broken down into what they are made from, so the
-- offer asks for "8 Linen Cloth", not "4 Bolt of Linen Cloth".
local _, ns = ...
local U = ns.Util
local O = {}
ns.Offers = O

-- The biggest plain bag of each cloth, in the order you meet the cloth while levelling, with the
-- levels where players usually carry that cloth. Bags marked as products are offered too.
O.BAGS = {
	{ name = "Red Linen Bag", min = 1, max = 20 },
	{ name = "Red Woolen Bag", min = 15, max = 30 },
	{ name = "Green Woolen Bag", min = 15, max = 30 },
	{ name = "Black Silk Pack", min = 25, max = 40 },
	{ name = "Green Silk Pack", min = 25, max = 40 },
	{ name = "Red Mageweave Bag", min = 35, max = 50 },
	{ name = "Runecloth Bag", min = 45, max = 60 },
	{ name = "Mooncloth Bag", min = 55, max = 60 },
}

-- Materials a vendor sells. Anything else is something the customer brings.
O.VENDOR_WORDS = { "thread", "dye", "salt", "flux", "bleach", "vial" }

O.DEFAULT_TEXT = "{recipe} makes {item}{size}. Bring {mats} + {fee} for {vendor} and a tip, and I'll make it right here!"

local MAX_DEPTH = 4

function O.IsVendorName(name)
	name = tostring(name or ""):lower()
	for _, w in ipairs(O.VENDOR_WORDS) do
		if name:find(w, 1, true) then return true end
	end
	return false
end

-- Item made -> the recipe that makes it. A learned recipe wins over one not learned.
function O.Index(list)
	local idx = {}
	for _, r in ipairs(list or {}) do
		if type(r) == "table" and r.output then
			local had = idx[r.output]
			if not had or (r.learned and not had.learned) then idx[r.output] = r end
		end
	end
	return idx
end

-- Everything one craft of the recipe needs, with parts you make broken down into what they are
-- made from. Returns { { itemID, qty } } in the order first met.
function O.RawMats(recipe, index)
	local order, total = {}, {}
	local function add(id, qty)
		if not total[id] then order[#order + 1] = id; total[id] = 0 end
		total[id] = total[id] + qty
	end
	local function walk(r, times, depth, seen)
		for _, g in ipairs(r.reagents or {}) do
			local id, qty = g.itemID, math.max(1, tonumber(g.qty) or 1) * times
			local sub = index and index[id]
			if sub and sub ~= r and depth < MAX_DEPTH and not seen[sub] then
				local crafts = math.ceil(qty / math.max(1, tonumber(sub.outputQty) or 1))
				seen[sub] = true
				walk(sub, crafts, depth + 1, seen)
				seen[sub] = nil
			else
				add(id, qty)
			end
		end
	end
	walk(recipe, 1, 0, { [recipe] = true })
	local out = {}
	for _, id in ipairs(order) do out[#out + 1] = { itemID = id, qty = total[id] } end
	return out
end

-- The fee: what the vendor materials cost, plus the tip, rounded up to a whole silver.
function O.Fee(vendorCost, tipPct)
	vendorCost = math.max(0, tonumber(vendorCost) or 0)
	if vendorCost == 0 then return 0 end
	local raw = vendorCost * (1 + math.max(0, tonumber(tipPct) or 0) / 100)
	return math.ceil(raw / 100) * 100
end

local function byName(list)
	local out = {}
	for _, r in ipairs(list or {}) do
		if type(r) == "table" and r.name and r.output then
			local had = out[r.name]
			if not had or (r.learned and not had.learned) then out[r.name] = r end
		end
	end
	return out
end

-- Builds the offers.
-- list: the scanned recipes of one profession.
-- opts: nameOf(itemID), vendorPrice(itemID) -> copper each and whether it is only an estimate,
--       isVendor(itemID) (optional, on top of the name check), tip (percent), slotsOf(itemID),
--       extra = { recipe name = true } for bags marked as products, level (who you are talking to).
-- Returns rows, and the names from O.BAGS that are not in the list at all.
function O.Build(list, opts)
	opts = opts or {}
	local nameOf = opts.nameOf or function(id) return "item " .. tostring(id) end
	local index, names = O.Index(list), byName(list)
	local rows, missing, used = {}, {}, {}

	local function make(r, tier)
		local row = {
			name = r.name, id = r.id, recipe = r, output = r.output, learned = r.learned and true or false,
			min = tier and tier.min, max = tier and tier.max,
			bring = {}, vendor = {}, vendorCost = 0, estimated = false, unpriced = 0,
		}
		for _, g in ipairs(O.RawMats(r, index)) do
			local name = nameOf(g.itemID)
			local each, guess = nil, false
			if opts.vendorPrice then each, guess = opts.vendorPrice(g.itemID) end
			local isVendor = O.IsVendorName(name) or (opts.isVendor and opts.isVendor(g.itemID)) or false
			local entry = { itemID = g.itemID, qty = g.qty, name = name }
			if isVendor then
				entry.each = tonumber(each) or 0
				if entry.each > 0 then
					row.vendorCost = row.vendorCost + entry.each * g.qty
					if guess then row.estimated = true end
				else
					row.unpriced = row.unpriced + 1
				end
				row.vendor[#row.vendor + 1] = entry
			else
				row.bring[#row.bring + 1] = entry
			end
		end
		row.fee = O.Fee(row.vendorCost, opts.tip)
		row.slots = opts.slotsOf and r.output and tonumber(opts.slotsOf(r.output)) or nil
		row.fits = (opts.level and row.min and opts.level >= row.min and opts.level <= row.max) and true or false
		return row
	end

	for _, tier in ipairs(O.BAGS) do
		local r = names[tier.name]
		if r then
			rows[#rows + 1] = make(r, tier)
			used[tier.name] = true
		else
			missing[#missing + 1] = tier.name
		end
	end
	local extras = {}
	for name in pairs(opts.extra or {}) do
		if names[name] and not used[name] then extras[#extras + 1] = name end
	end
	table.sort(extras)
	for _, name in ipairs(extras) do rows[#rows + 1] = make(names[name]) end
	return rows, missing
end

-- "8 Linen Cloth", "6 Wool Cloth and 2 Silk Cloth", "a, b and c"
local function joinList(parts)
	if #parts <= 1 then return parts[1] or "" end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

function O.MatsText(entries)
	local parts = {}
	for _, e in ipairs(entries or {}) do parts[#parts + 1] = e.qty .. " " .. e.name end
	return joinList(parts)
end

function O.VendorText(entries)
	local parts = {}
	for _, e in ipairs(entries or {}) do parts[#parts + 1] = e.name end
	return #parts > 0 and joinList(parts) or "my time"
end

-- The line placed in the chat box. opts: template, recipeLink, itemLink, maxBytes.
-- Links are long; when the line is too long they are swapped for plain names, recipe first.
-- Returns the text, or nil and the reason.
function O.Text(row, opts)
	opts = opts or {}
	local template = U.Trim(opts.template) ~= "" and opts.template or O.DEFAULT_TEXT
	local maxBytes = opts.maxBytes or ns.MAX_CHAT_BYTES
	local plainRecipe = (opts.profession and (opts.profession .. ": ") or "") .. row.name
	local function fill(recipe, item)
		return U.Fill(template, {
			recipe = recipe, item = item,
			size = row.slots and (" (" .. row.slots .. " slot)") or "",
			slots = row.slots and tostring(row.slots) or "",
			mats = #row.bring > 0 and O.MatsText(row.bring) or "nothing",
			fee = row.fee > 0 and U.FormatMoney(row.fee) or "a tip",
			vendor = O.VendorText(row.vendor),
		})
	end
	local tries = {
		{ opts.recipeLink or plainRecipe, opts.itemLink or row.name },
		{ plainRecipe, opts.itemLink or row.name },
		{ plainRecipe, row.name },
	}
	local text
	for _, t in ipairs(tries) do
		text = fill(t[1], t[2])
		if U.ByteLen(text) <= maxBytes then return text end
	end
	return nil, ("The offer is %d bytes; the chat limit is %d. Shorten the message."):format(U.ByteLen(text), maxBytes)
end
