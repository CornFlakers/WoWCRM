-- Turns a scanned recipe list into rows that can be filtered and sorted.
-- No game API in this file: recipes and the price function are passed in.
local _, ns = ...
local U = ns.Util
local Cat = {}
ns.Catalog = Cat

Cat.SORTS = { "name", "category", "mats cost", "sale value", "margin", "times sold" }

function Cat.Key(profession, name)
	return profession .. "|" .. name
end

-- recipes: array of { id, name, category, learned, output, outputQty, reagents = { { itemID, qty } } }
-- priceOf(itemID) -> copper (0 when unknown)
-- sold: item name -> quantity sold;  products: key -> anything, for recipes marked as "my products"
function Cat.Build(recipes, profession, priceOf, sold, products)
	local rows = {}
	for _, r in ipairs(recipes or {}) do
		if type(r) == "table" and r.name then
			local row = {
				id = r.id or r.name, key = nil, name = r.name, profession = profession,
				category = (r.category and r.category ~= "") and r.category or "Other",
				learned = r.learned and true or false,
				output = r.output, outputQty = tonumber(r.outputQty) or 1,
				reagents = {}, mats = 0, unpriced = 0,
			}
			for _, g in ipairs(r.reagents or {}) do
				local each = priceOf(g.itemID) or 0
				local qty = tonumber(g.qty) or 1
				row.reagents[#row.reagents + 1] = { itemID = g.itemID, qty = qty, each = each }
				if each > 0 then row.mats = row.mats + each * qty else row.unpriced = row.unpriced + 1 end
			end
			row.sale = row.output and (priceOf(row.output) or 0) * row.outputQty or 0
			row.margin = row.sale > 0 and (row.sale - row.mats) or 0
			row.sold = (sold and sold[r.name]) or 0
			row.product = (products and products[Cat.Key(profession, r.name)]) and true or false
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
	table.insert(out, 1, "All")
	return out
end

-- opts: category ("All" or a name), learnedOnly, productsOnly, search
function Cat.Filter(rows, opts)
	local q = U.Trim(opts.search):lower()
	local out = {}
	for _, r in ipairs(rows) do
		local ok = (not opts.category or opts.category == "All" or r.category == opts.category)
			and (not opts.learnedOnly or r.learned)
			and (not opts.productsOnly or r.product)
			and (q == "" or r.name:lower():find(q, 1, true) ~= nil)
		if ok then out[#out + 1] = r end
	end
	return out
end

-- Money and sales columns sort highest first, except materials cost (cheapest first).
function Cat.Sort(rows, by)
	local function cmp(a, b)
		local x, y
		if by == "category" then x, y = a.category, b.category
			if x ~= y then return x < y end
		elseif by == "mats cost" then
			if a.mats ~= b.mats then return a.mats < b.mats end
		elseif by == "sale value" then
			if a.sale ~= b.sale then return a.sale > b.sale end
		elseif by == "margin" then
			if a.margin ~= b.margin then return a.margin > b.margin end
		elseif by == "times sold" then
			if a.sold ~= b.sold then return a.sold > b.sold end
		end
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.id) < tostring(b.id)
	end
	table.sort(rows, cmp)
	return rows
end
