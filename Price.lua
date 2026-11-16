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
