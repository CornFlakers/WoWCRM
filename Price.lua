-- What an item is worth right now, so goods received in trade can be given a value.
-- Uses TradeSkillMaster or Auctionator when installed, otherwise the vendor price.
local _, ns = ...
local Price = {}
ns.Price = Price

local CALLER = "WoWCRM"

local function positive(ok, v)
	if ok and type(v) == "number" and v > 0 then return math.floor(v + 0.5) end
end

-- Returns copper for one item, and where the figure came from ("TSM", "Auctionator", "vendor" or "none").
function Price.Get(link)
	if type(link) ~= "string" or link == "" then return 0, "none" end

	if TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue then
		local ok, itemString = pcall(TSM_API.ToItemString, link)
		if ok and itemString then
			local v = positive(pcall(TSM_API.GetCustomPriceValue, "dbmarket", itemString))
				or positive(pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", itemString))
			if v then return v, "TSM" end
		end
	end

	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemLink then
		local v = positive(pcall(api.GetAuctionPriceByItemLink, CALLER, link))
		if v then return v, "Auctionator" end
	end

	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if getInfo then
		local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(getInfo, link)
		local v = positive(ok, sell)
		if v then return v, "vendor" end
	end
	return 0, "none"
end

-- ---------------------------------------------------------------- by item id (for recipe lists)

local cache = {}
local CACHE_SECONDS = 120

function Price.Reset() cache = {}; if Price.ResetSlots then Price.ResetSlots() end end

function Price.GetByID(itemID)
	itemID = tonumber(itemID)
	if not itemID then return 0, "none" end
	local hit = cache[itemID]
	local now = GetTime()
	if hit and now - hit.at < CACHE_SECONDS then return hit.value, hit.source end

	local value, source = 0, "none"
	if TSM_API and TSM_API.GetCustomPriceValue then
		local v = positive(pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID))
			or positive(pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", "i:" .. itemID))
		if v then value, source = v, "TSM" end
	end
	if value == 0 then
		local api = Auctionator and Auctionator.API and Auctionator.API.v1
		if api and api.GetAuctionPriceByItemID then
			local v = positive(pcall(api.GetAuctionPriceByItemID, CALLER, itemID))
			if v then value, source = v, "Auctionator" end
		end
	end
	if value == 0 then
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		if getInfo then
			local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(getInfo, itemID)
			local v = positive(ok, sell)
			if v then value, source = v, "vendor" end
		end
	end
	cache[itemID] = { value = value, source = source, at = now }
	return value, source
end

-- The item's name, or a placeholder until the game has loaded it.
function Price.ItemName(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if getInfo then
		local ok, name = pcall(getInfo, itemID)
		if ok and type(name) == "string" then return name end
	end
	return "item " .. tostring(itemID)
end

-- ---------------------------------------------------------------- bag sizes
-- The number of slots is only written in the item's tooltip ("16 Slot Bag"), so read it there.

local slotCache = {}
local scanTip

local function slotsIn(text)
	if type(text) ~= "string" then return nil end
	return tonumber(text:match("(%d+)[%- ][Ss]lot"))
end

function Price.BagSlots(itemID)
	itemID = tonumber(itemID)
	if not itemID then return nil end
	if slotCache[itemID] ~= nil then return slotCache[itemID] or nil end
	local n
	if C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			for _, line in ipairs(data.lines) do
				n = slotsIn(line.leftText)
				if n then break end
			end
		end
	end
	if not n and GameTooltip and UIParent then
		scanTip = scanTip or CreateFrame("GameTooltip", "WoWCRMScanTooltip", nil, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
		if pcall(scanTip.SetHyperlink, scanTip, "item:" .. itemID) then
			for i = 2, 10 do
				local fs = _G["WoWCRMScanTooltipTextLeft" .. i]
				n = fs and slotsIn(fs:GetText())
				if n then break end
			end
		end
	end
	-- Remember "not a bag" only once the game has the item loaded; before that, try again later.
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local loaded = getInfo and select(2, pcall(getInfo, itemID)) ~= nil
	if n or loaded then slotCache[itemID] = n or false end
	return n
end

function Price.ItemLink(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if getInfo then
		local ok, _, link = pcall(getInfo, itemID)
		if ok and type(link) == "string" then return link end
	end
end

function Price.ResetSlots() slotCache = {} end

-- ---------------------------------------------------------------- where a recipe comes from
-- The game can say how an unlearned recipe is obtained ("Vendor: ...", "Drop: ..."), usually
-- only while that profession's window is open. What it says is remembered, so it is there next time.

function Price.RecipeSource(recipeID)
	local known = ns.DB.R.recipeSources
	local get = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSourceText
	if get and recipeID then
		local ok, text = pcall(get, recipeID)
		if ok and type(text) == "string" and text:find("%S") then
			text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*[\r\n]+%s*", " / ")
			if known[recipeID] ~= text then known[recipeID] = text end
		end
	end
	return known[recipeID]
end
