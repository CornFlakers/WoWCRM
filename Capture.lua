-- Notices completed trades and cash-on-delivery mail, and offers to record them as orders.
-- Nothing is recorded without a click.
--
-- A job often takes several trades: the customer hands over materials, later collects the
-- finished goods, and may come back with a tip in gold or raw materials. Follow-up trades
-- with the same person are offered as part of the same order.
local _, ns = ...
local U, DB, M, Price = ns.Util, ns.DB, ns.Model, ns.Price

local TRADE_SLOTS = 6
local LOCKED_SLOT = 7 -- "Will not be traded": the item stays theirs; you work on it (pick a lock, enchant)

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
	trade = { valid = false, open = true }
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
	-- Their item in "Will not be traded", and what was done to it, if the game says.
	local link = GetTradeTargetItemLink and GetTradeTargetItemLink(LOCKED_SLOT)
	if link then
		local name, _, _, _, _, enchant = GetTradeTargetItemInfo(LOCKED_SLOT)
		trade.locked = { link = link, name = name or link:match("%[(.-)%]") or "item",
			enchant = type(enchant) == "string" and enchant ~= "" and enchant or nil }
	else
		trade.locked = nil
	end
end)

ns.On("TRADE_CLOSED", function() trade.open = false end)

local function spellName(id)
	id = U.Plain(id)
	if not id then return nil end
	local get = (C_Spell and C_Spell.GetSpellName) or rawget(_G, "GetSpellInfo")
	if type(get) ~= "function" then return nil end
	local ok, name = pcall(get, id)
	return ok and type(name) == "string" and name or nil
end

-- Your own spells: a lock picked or an enchant cast while a trade is open belongs to that trade;
-- a portal or summon is remembered so the payment that follows can be tied to it.
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if not ns.ready or unit ~= "player" then return end
	local spell = spellName(spellID)
	local service, viaTrade = M.ServiceForSpell(spell)
	if not service then return end
	if viaTrade then
		if trade.open then trade.service = service end
		return
	end
	local target
	if service == "Summon" then
		local n, second = UnitName("target")
		if type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) and UnitIsPlayer("target") then
			target = U.Display(M.JoinName(n, second), DB.realm)
		end
	end
	M.LogServiceCast(service, U.Now(), target)
	ns.Changed(true)
end)

local function offerOrder(t)
	local key = t.key
	local gold = math.max(0, t.gold or 0)
	local now = U.Now()
	local current = M.CurrentOrder(key, now)

	local L = { "WoW CRM - trade with |cffffff00" .. U.Display(key, DB.realm) .. "|r", "" }
	if #t.given > 0 then L[#L + 1] = "You gave: " .. M.Summary(t.given, 90) end
	if #t.received > 0 then
		L[#L + 1] = ("You received: %s (worth about %s)"):format(M.Summary(t.received, 70), U.FormatMoney(linesValue(t.received)))
	end
	if gold > 0 then L[#L + 1] = "Gold received: " .. U.FormatMoney(gold) end
	L[#L + 1] = ""
	if current then
		local _, planned = M.ItemCounts(current)
		L[#L + 1] = ("Add this to their order (%s%s%s)?"):format(M.OrderTitle(current, 40),
			current.quote and (", agreed " .. U.FormatMoney(current.quote)) or "",
			planned > 0 and ", not yet handed over" or "")
	else
		L[#L + 1] = "Record this as an order?"
	end

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

-- A trade with someone who has an open opportunity is offered to that job first:
--   they hand over materials -> "are these for the Opty?" (logged on it, no order yet)
--   you hand over the goods  -> "deliver the Opty?" (the order is logged now, with their
--                               materials as supplied and whatever they paid)
-- "Not for it" goes on to the usual order question.
local function offerOpty(t)
	local key = t.key
	if not allowed(key) then return end
	local gold = math.max(0, t.gold or 0)
	if #t.given == 0 and #t.received == 0 and gold <= 0 then return end
	local opp = M.OpenOpportunityFor(key)
	if not opp then return offerOrder(t) end
	local who = U.Display(key, DB.realm)
	local title = M.OpportunityTitle(opp, 50)
	if #t.given == 0 then
		local L = { "WoW CRM - trade with |cffffff00" .. who .. "|r", "" }
		if #t.received > 0 then L[#L + 1] = "You received: " .. M.Summary(t.received, 80) end
		if gold > 0 then L[#L + 1] = "Gold received: " .. U.FormatMoney(gold) end
		L[#L + 1] = ""
		L[#L + 1] = ("Are these for their Opty \"%s\"?"):format(title)
		ns.ChooseOpty(table.concat(L, "\n"), "For this Opty", function()
			M.AddOpportunityMats(opp.id, t.received, U.Now(), gold)
			ns.Print(("logged on %s's Opty \"%s\": %s%s. Open the Opty tab to see their price now."):format(
				who, title, #t.received > 0 and M.Summary(t.received, 60) or "",
				gold > 0 and ((#t.received > 0 and " and " or "") .. U.FormatMoney(gold)) or ""))
			ns.Changed()
		end, function() offerOrder(t) end)
		return
	end
	local L = { "WoW CRM - trade with |cffffff00" .. who .. "|r", "", "You gave: " .. M.Summary(t.given, 80) }
	if #t.received > 0 then L[#L + 1] = "You received: " .. M.Summary(t.received, 70) end
	if gold > 0 then L[#L + 1] = "Gold received: " .. U.FormatMoney(gold) end
	L[#L + 1] = ""
	L[#L + 1] = ("Deliver their Opty \"%s\"? This logs the order%s."):format(title,
		(opp.mats and #opp.mats > 0) and ", with the materials they brought" or "")
	ns.ChooseOpty(table.concat(L, "\n"), "Deliver the Opty", function()
		local ord = M.OpportunityToOrder(opp.id, U.Now())
		if not ord then return offerOrder(t) end
		local o = M.AddTrade(ord.id, key, { given = t.given, received = t.received, gold = gold }, U.Now())
		local g, goods, mats = M.OrderValue(o)
		ns.Print(("Opty delivered: order for %s is %s: %s gold, %s in goods, %s in materials they supplied."):format(
			who, o.status, U.FormatMoney(g), U.FormatMoney(goods), U.FormatMoney(mats)))
		ns.Changed()
	end, function() offerOrder(t) end)
end

-- Services first:
--   their item sat in "Will not be traded" and you picked its lock or enchanted it
--     -> logged as a service order by itself (nothing to click)
--   you cast a portal or summon in the last 10 minutes and they only handed you gold
--     -> "was this payment for the portal?"
-- Anything else goes on to the Opty and order questions.
local SERVICE_PAY_WINDOW = 600

local function offerTrade(t)
	local key = t.key
	if not key then return end
	local gold = math.max(0, t.gold or 0)
	local who = U.Display(key, DB.realm)
	local service = t.locked and (t.service or t.locked.enchant)
	if service then
		local o = M.RecordService(key, service, t.locked.name, { received = t.received, gold = gold }, U.Now())
		ns.Print(("logged: %s for %s%s. The Orders tab has it, to change or delete."):format(o.desc, who,
			gold > 0 and (", " .. U.FormatMoney(gold)) or ", no payment"))
		ns.Changed()
		return
	end
	local cast = M.RecentServiceCast(U.Now(), SERVICE_PAY_WINDOW)
	if cast and gold > 0 and #t.given == 0 and #t.received == 0 then
		local label = (cast.name == "Summon" and cast.target) and ("Summon: " .. cast.target) or cast.name
		local text = ("WoW CRM - trade with |cffffff00%s|r\n\nGold received: %s\n\nPayment for %s (%s ago)?"):format(
			who, U.FormatMoney(gold), label, M.Clock(U.Now() - cast.time))
		ns.ChooseOpty(text, "Yes, payment", function()
			local o = M.RecordService(key, cast.name, cast.name == "Summon" and cast.target or nil, { gold = gold }, U.Now())
			ns.Print(("logged: %s for %s, %s."):format(o.desc, who, U.FormatMoney(gold)))
			ns.Changed()
		end, function() offerOpty(t) end)
		return
	end
	offerOpty(t)
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
