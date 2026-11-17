-- Notices completed trades and cash-on-delivery mail, and offers to record them as orders.
-- Nothing is recorded without a click.
--
-- A job often takes several trades: the customer hands over materials, later collects the
-- finished goods, and may come back with a tip in gold or raw materials. Follow-up trades
-- with the same person are offered as part of the same order.
local _, ns = ...
local U, DB, M, Price = ns.Util, ns.DB, ns.Model, ns.Price

local TRADE_SLOTS = 6

local function allowed(key)
	return M.GetContact(key) ~= nil or DB.settings.promptStrangers
end

local function linesValue(lines)
	local v = 0
	for _, l in ipairs(lines) do v = v + (l.value or 0) * l.qty end
	return v
end

-- ---------------------------------------------------------------- trade window

local trade = {}

local function readSide(getLink, getInfo, priced)
	local out = {}
	for i = 1, TRADE_SLOTS do
		local link = getLink(i)
		if link then
			local name, _, count = getInfo(i)
			local line = { link = link, name = name or link:match("%[(.-)%]") or "item", qty = tonumber(count) or 1 }
			if priced then line.value, line.source = Price.Get(link) end
			out[#out + 1] = line
		end
	end
	return out
end

ns.On("TRADE_SHOW", function()
	local name, second = UnitName("NPC")
	trade = { valid = false }
	if type(name) == "string" and name ~= "" then
		trade.key = M.JoinName(name, second)
	end
end)

ns.On("TRADE_ACCEPT_UPDATE", function(player, target)
	if not (player == 1 or target == 1) then trade.valid = false return end
	trade.valid = true
	trade.gold = (tonumber(GetTargetTradeMoney()) or 0) - (tonumber(GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0)
	trade.given = readSide(GetTradePlayerItemLink, GetTradePlayerItemInfo, false)
	trade.received = readSide(GetTradeTargetItemLink, GetTradeTargetItemInfo, true)
end)

local function offerTrade(t)
	local key = t.key
	if not allowed(key) then return end
	local gold = math.max(0, t.gold or 0)
	if #t.given == 0 and #t.received == 0 and gold <= 0 then return end
	local now = U.Now()
	local current = M.CurrentOrder(key, now)

	local L = { "WoW CRM - trade with |cffffff00" .. U.Display(key, DB.realm) .. "|r", "" }
	if #t.given > 0 then L[#L + 1] = "You gave: " .. M.Summary(t.given, 90) end
	if #t.received > 0 then
		L[#L + 1] = ("You received: %s (worth about %s)"):format(M.Summary(t.received, 70), U.FormatMoney(linesValue(t.received)))
	end
	if gold > 0 then L[#L + 1] = "Gold received: " .. U.FormatMoney(gold) end
	L[#L + 1] = ""
	L[#L + 1] = current and ("Add this to their current order (" .. M.OrderTitle(current, 40) .. ")?") or "Record this as an order?"

	local function record(orderId)
		local o = M.AddTrade(orderId, key, { given = t.given, received = t.received, gold = gold }, U.Now())
		local g, goods, mats = M.OrderValue(o)
		ns.Print(("order for %s is now %s: %s gold, %s in goods, %s in materials supplied."):format(
			U.Display(key, DB.realm), o.status, U.FormatMoney(g), U.FormatMoney(goods), U.FormatMoney(mats)))
		ns.Changed()
	end
	if current then
		ns.Choose(table.concat(L, "\n"), function() record(current.id) end, function() record(nil) end)
	else
		ns.Confirm(table.concat(L, "\n"), function() record(nil) end)
	end
end

ns.On("UI_INFO_MESSAGE", function(messageType, message)
	local complete = (LE_GAME_ERR_TRADE_COMPLETE and messageType == LE_GAME_ERR_TRADE_COMPLETE)
		or (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE)
	if not complete or not ns.ready or not trade.valid or not trade.key then return end
	local t = trade
	trade = {}
	offerTrade(t)
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
					pending.items[#pending.items + 1] = { name = name, link = link, qty = tonumber(count) or 1 }
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
	local filled = ns.Mail.filled
	ns.Mail.filled = nil
	if filled and filled.key == key and M.RecordOutreach(key, filled.template, U.Now()) then
		local c = M.GetContact(key)
		ns.Print(("follow-up to %s recorded (%d sent in total)."):format(U.Display(key, DB.realm), c.outreach))
		ns.Changed()
	end
	if p.cod <= 0 or not allowed(key) then return end
	local text = ("WoW CRM\n\nRecord this cash-on-delivery mail as an order for |cffffff00%s|r?\n\n%s\n%s due"):format(
		U.Display(key, DB.realm), #p.items > 0 and M.Summary(p.items, 90) or "(no items attached)", U.FormatMoney(p.cod))
	ns.Confirm(text, function()
		local o, err = M.SaveOrder(nil, {
			contact = key, type = "goods", items = p.items, desc = #p.items == 0 and "Cash on delivery" or "",
			price = p.cod, status = "delivered", notes = "Sent cash on delivery. Mark paid when the gold arrives.",
		}, U.Now())
		if o then
			ns.Print("order recorded for " .. U.Display(key, DB.realm) .. ". Mark it paid when the gold arrives.")
			ns.Changed()
		else
			ns.Print(err)
		end
	end)
end)

ns.On("MAIL_FAILED", function() pending = nil end)
