-- Notices completed trades and cash-on-delivery mail, and offers to record them as orders.
-- Nothing is recorded without a click.
local _, ns = ...
local U, DB, M = ns.Util, ns.DB, ns.Model

local TRADE_SLOTS = 6

local function describe(items)
	local parts, firstLink = {}, nil
	for _, it in ipairs(items) do
		firstLink = firstLink or it.link
		parts[#parts + 1] = (it.count > 1 and (it.count .. "x ") or "") .. it.name
	end
	return U.Shorten(table.concat(parts, ", "), 120), firstLink
end

local function offer(key, items, price, status, how)
	local known = M.GetContact(key) ~= nil
	if not known and not DB.settings.promptStrangers then return end
	if #items == 0 and price <= 0 then return end
	local desc, link = describe(items)
	local otype = "goods"
	if #items == 0 then desc, otype = "Service", "service" end
	local text = ("WoW CRM\n\nRecord this %s as an order for |cffffff00%s|r?\n\n%s\n%s"):format(
		how, U.Display(key, DB.realm), desc, U.FormatMoney(price))
	ns.Confirm(text, function()
		local o, err = M.SaveOrder(nil, {
			contact = key, type = otype, desc = desc, link = link, qty = 1, price = price, status = status,
			notes = "Recorded from " .. how,
		}, U.Now())
		if o then
			ns.Print("order recorded for " .. U.Display(key, DB.realm) .. ". Edit it in the Orders tab.")
			ns.Changed()
		else
			ns.Print(err)
		end
	end)
end

-- ---------------------------------------------------------------- trade window

local trade = {}

ns.On("TRADE_SHOW", function()
	local name, realm = UnitName("NPC")
	trade = { valid = false }
	if type(name) == "string" and name ~= "" then
		trade.key = U.NormName((realm and realm ~= "") and (name .. "-" .. realm) or name, DB.realm)
	end
end)

ns.On("TRADE_ACCEPT_UPDATE", function(player, target)
	if not (player == 1 or target == 1) then trade.valid = false return end
	trade.valid = true
	trade.received = tonumber(GetTargetTradeMoney()) or 0
	trade.given = {}
	for i = 1, TRADE_SLOTS do
		local link = GetTradePlayerItemLink(i)
		if link then
			local name, _, count = GetTradePlayerItemInfo(i)
			trade.given[#trade.given + 1] = { link = link, name = name or link:match("%[(.-)%]") or "item", count = tonumber(count) or 1 }
		end
	end
end)

ns.On("UI_INFO_MESSAGE", function(messageType, message)
	local complete = (LE_GAME_ERR_TRADE_COMPLETE and messageType == LE_GAME_ERR_TRADE_COMPLETE)
		or (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE)
	if not complete or not ns.ready or not trade.valid or not trade.key then return end
	local t = trade
	trade = {}
	offer(t.key, t.given, t.received, t.received > 0 and "paid" or "delivered", "trade")
end)

-- ---------------------------------------------------------------- mail

local pending

if type(SendMail) == "function" then
	hooksecurefunc("SendMail", function(recipient, subject)
		if not ns.ready or type(recipient) ~= "string" then return end
		pending = { key = U.NormName(recipient, DB.realm, true), subject = subject or "", items = {}, cod = 0 }
		if GetSendMailCOD then pending.cod = tonumber(GetSendMailCOD()) or 0 end
		if GetSendMailItem then
			for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
				local name, _, _, count = GetSendMailItem(i)
				if name then
					local link = GetSendMailItemLink and GetSendMailItemLink(i)
					pending.items[#pending.items + 1] = { name = name, link = link, count = tonumber(count) or 1 }
				end
			end
		end
	end)
end

ns.On("MAIL_SEND_SUCCESS", function()
	local p = pending
	pending = nil
	if not p or not p.key then return end
	local c = M.FindContact(p.key)
	local key = c and c.key or p.key
	if M.LogMail(key, p.subject, U.Now()) then ns.Changed(true) end
	if p.cod > 0 then
		offer(key, p.items, p.cod, "delivered", "cash-on-delivery mail")
	end
end)

ns.On("MAIL_FAILED", function() pending = nil end)
