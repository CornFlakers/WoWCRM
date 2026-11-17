-- Turns a scanned recipe list into rows that can be filtered and sorted.
-- No game API in this file: recipes and the price function are passed in.
local _, ns = ...
local U = ns.Util
local Cat = {}
ns.Catalog = Cat

Cat.SORTS = { "name", "margin", "bag size", "mats cost", "sale value", "times sold", "can make" }
Cat.ALL_BAGS = "All bags"

local function isBag(category) return category:lower():find("bag", 1, true) ~= nil end

function Cat.Key(profession, name)
	return profession .. "|" .. name
end

-- recipes: array of { id, name, category, learned, output, outputQty, reagents = { { itemID, qty } } }
-- priceOf(itemID) -> copper (0 when unknown)
-- sold: item name -> quantity sold;  products: key -> anything, for recipes marked as "my products"
-- countOf(itemID) -> how many are in the player's bags right now (optional)
-- slotsOf(itemID) -> number of slots when the item is a bag (optional)
-- A product's own asking price, when set, is used for the margin instead of the auction price.
-- heldFree: materials you already hold cost nothing, so a craft costs only what you still have to buy.
function Cat.Build(recipes, profession, priceOf, sold, products, countOf, slotsOf, heldFree)
	local rows = {}
	for _, r in ipairs(recipes or {}) do
		if type(r) == "table" and r.name then
			local row = {
				id = r.id or r.name, key = nil, name = r.name, profession = profession,
				category = (r.category and r.category ~= "") and r.category or "Other",
				learned = r.learned and true or false,
				output = r.output, outputQty = tonumber(r.outputQty) or 1,
				reagents = {}, mats = 0, unpriced = 0, buy = 0, unpricedBuy = 0,
			}
			local canMake
			for _, g in ipairs(r.reagents or {}) do
				local each = priceOf(g.itemID) or 0
				local qty = math.max(1, tonumber(g.qty) or 1)
				local have = countOf and (tonumber(countOf(g.itemID)) or 0) or 0
				local times = math.floor(have / qty)
				if not canMake or times < canMake then canMake = times end
				local short = math.max(0, qty - have) -- how many of this material one craft still needs bought
				row.reagents[#row.reagents + 1] = { itemID = g.itemID, qty = qty, each = each, have = have, short = short }
				if each > 0 then
					row.mats = row.mats + each * qty
					row.buy = row.buy + each * short
				else
					row.unpriced = row.unpriced + 1
					if short > 0 then row.unpricedBuy = row.unpricedBuy + 1 end
				end
			end
			-- How many crafts the materials in your bags cover right now (the scarcest material decides).
			row.canMake = canMake or 0
			row.sale = row.output and (priceOf(row.output) or 0) * row.outputQty or 0
			local mine = products and products[Cat.Key(profession, r.name)]
			row.product = mine and true or false
			row.myPrice = type(mine) == "table" and tonumber(mine.price) or nil
			row.price = row.myPrice or row.sale -- what a customer would be quoted
			-- mats = every material at today's price; buy = only what you do not already hold.
			row.cost = heldFree and row.buy or row.mats
			row.margin = row.price > 0 and (row.price - row.cost) or 0
			row.sold = (sold and sold[r.name]) or 0
			if slotsOf and row.output and isBag(row.category) then row.slots = tonumber(slotsOf(row.output)) end
			rows[#rows + 1] = row
		end
	end
	return rows
end

-- "All" first, then every category that appears, in alphabetical order.
function Cat.Categories(rows)
	local seen, out = {}, {}
	for _, r in ipairs(rows) do
		if not seen[r.category] then seen[r.category] = true; out[#out + 1] = r.category end
	end
	table.sort(out)
	local bags = 0
	for _, c in ipairs(out) do if isBag(c) then bags = bags + 1 end end
	if bags >= 2 then table.insert(out, 1, Cat.ALL_BAGS) end
	table.insert(out, 1, "All")
	return out
end

-- opts: category ("All" or a name), learnedOnly, craftableOnly, productsOnly, search
function Cat.Filter(rows, opts)
	local q = U.Trim(opts.search):lower()
	local out = {}
	for _, r in ipairs(rows) do
		local ok = (not opts.category or opts.category == "All" or r.category == opts.category
				or (opts.category == Cat.ALL_BAGS and isBag(r.category)))
			and (not opts.learnedOnly or r.learned)
			and (not opts.productsOnly or r.product)
			and (not opts.craftableOnly or r.canMake >= 1)
			and (q == "" or r.name:lower():find(q, 1, true) ~= nil)
		if ok then out[#out + 1] = r end
	end
	return out
end

-- Money and sales columns sort highest first, except materials cost (cheapest first).
function Cat.Sort(rows, by)
	local function cmp(a, b)
		local x, y
		if by == "bag size" then
			x, y = a.slots or 0, b.slots or 0
			if x ~= y then return x > y end
		elseif by == "mats cost" then
			if a.cost ~= b.cost then return a.cost < b.cost end
		elseif by == "sale value" then
			if a.sale ~= b.sale then return a.sale > b.sale end
		elseif by == "margin" then
			if a.margin ~= b.margin then return a.margin > b.margin end
		elseif by == "times sold" then
			if a.sold ~= b.sold then return a.sold > b.sold end
		elseif by == "can make" then
			if a.canMake ~= b.canMake then return a.canMake > b.canMake end
		end
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.id) < tostring(b.id)
	end
	table.sort(rows, cmp)
	return rows
end

-- Sorts the rows, then lays them out under a heading per category:
-- { header = true, name = "Bags", count = 3 }, row, row, row, { header = true, ... }, ...
-- With only one category there are no headings.
function Cat.Group(rows, by)
	Cat.Sort(rows, by)
	local order, groups = {}, {}
	for _, r in ipairs(rows) do
		if not groups[r.category] then groups[r.category] = {}; order[#order + 1] = r.category end
		table.insert(groups[r.category], r)
	end
	if #order <= 1 then return rows end
	table.sort(order)
	local out = {}
	for _, c in ipairs(order) do
		out[#out + 1] = { header = true, id = "header:" .. c, name = c, count = #groups[c] }
		for _, r in ipairs(groups[c]) do out[#out + 1] = r end
	end
	return out
end

-- "Runecloth Bag (14 slot) 3g". label lets the caller pass an item link instead of the name.
function Cat.Quote(row, label)
	if not row.price or row.price <= 0 then return nil end
	return (label or row.name) .. (row.slots and (" (" .. row.slots .. " slot)") or "") .. " " .. U.FormatMoney(row.price)
end

-- A one-message price list from the given rows, in their order, that fits in maxBytes.
-- Rows without a price are left out. Returns the text and how many items made it in.
function Cat.QuoteList(rows, maxBytes)
	local text, n = "", 0
	for _, r in ipairs(rows) do
		local q = (not r.header) and Cat.Quote(r)
		if q then
			local nextText = text == "" and q or (text .. ", " .. q)
			if #nextText > maxBytes then break end
			text, n = nextText, n + 1
		end
	end
	return text, n
end
