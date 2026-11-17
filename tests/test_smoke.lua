-- Loads the whole add-on against a stand-in for the game and walks through a selling session:
-- save a post, click it into chat, capture whispers, record orders, fill in a letter.
-- This catches Lua errors and wiring mistakes. It cannot prove how the real client behaves.

local unpack = table.unpack or unpack
local clock = 5000
local sent, printed, widgets = {}, {}, {}
local SECRET = {}

-- ---------------------------------------------------------------- stand-in widgets
local methods = {}
local function noop() end
local MT = {}
MT.__index = function(_, k)
	if methods[k] then return methods[k] end
	if type(k) == "string" and k:match("^%u") then return noop end
	return nil
end
local function widget(kind, parent)
	local w = setmetatable({ _kind = kind, _parent = parent, _scripts = {}, _shown = true, _enabled = true, _text = "" }, MT)
	widgets[#widgets + 1] = w
	return w
end
function methods:SetScript(n, f) self._scripts[n] = f end
function methods:SetText(t) self._text = tostring(t or ""); if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self) end end
function methods:GetText() return self._text end
function methods:Insert(t) self:SetText(self._text .. t) end
function methods:SetChecked(v) self._checked = v and true or false end
function methods:GetChecked() return self._checked or false end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:Enable() self._enabled = true end
function methods:Disable() self._enabled = false end
function methods:HasFocus() return self._focus or false end
function methods:SetFocus() self._focus = true end
function methods:ClearFocus() self._focus = false end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:CreateFontString() return widget("FontString", self) end
function methods:CreateTexture() return widget("Texture", self) end

-- ---------------------------------------------------------------- stand-in game API
function CreateFrame(kind, name, parent)
	local w = widget(kind, parent)
	if name then _G[name] = w end
	return w
end
UIParent = widget("Frame")
GameTooltip = widget("GameTooltip")
MailFrame = widget("Frame")
SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox = widget("EditBox"), widget("EditBox"), widget("EditBox")
ChatFontNormal = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}
YES, NO = "Yes", "No"
tinsert = table.insert
date = os.date
time = function() return clock end
local popups = 0
function StaticPopup_Show(which, _, _, data) popups = popups + 1; StaticPopupDialogs[which].OnAccept(nil, data) end
function InCombatLockdown() return false end
function GetNormalizedRealmName() return "Stormrage" end
function GetRealmName() return "Stormrage" end
function UnitName(unit) if unit == "player" then return "Seller" elseif unit == "NPC" then return "Buyer" end return "Targ" end
function UnitIsPlayer() return true end
function GetZoneText() return "City" end
function IsInGroup() return false end
function IsInGuild() return true end
function GetChannelList()
	return 1, "General - City", false, 2, "Trade (Services) - City", false, 3, "Trade - City", false, 4, "Tradeskill Chat", false
end
function SendChatMessage(text, chatType, lang, channel) sent[#sent + 1] = { text = text, type = chatType, channel = channel } end
function GetBuildInfo() return "1.60.1", "70938", "Nov 1 2026", 16001 end
function issecretvalue(v) return v == SECRET end
C_Timer = { After = function(_, f) f() end }
function hooksecurefunc(a, b, c)
	local tbl, name, fn = _G, a, b
	if type(a) == "table" then tbl, name, fn = a, b, c end
	local orig = tbl[name]
	tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
function ChatEdit_InsertLink() return false end
ChatFrameUtil = { InsertLink = function() return false end }
local tradeLink
C_TradeSkillUI = { GetTradeSkillListLink = function() return tradeLink end }
function GetTime() return clock end
local tells = {}
function ChatFrame_SendTell(name) tells[#tells + 1] = name end
function MailFrameTab_OnClick() end
function SendMail() end
codAmount = 70000
function GetSendMailCOD() return codAmount end
function GetSendMailItem(i) if i == 1 then return "Runed Rod", 1, nil, 2 end end
function GetSendMailItemLink(i) if i == 1 then return "|cffffffff|Hitem:1::::::::|h[Runed Rod]|h|r" end end
LE_GAME_ERR_TRADE_COMPLETE = 77
-- what the next trade window holds: { name, count } on each side, and gold coming in
local tGive, tGet, tGold = nil, nil, 0
local function link(name) return "|cffffffff|Hitem:2::::::::|h[" .. name .. "]|h|r" end
function GetTargetTradeMoney() return tGold end
function GetPlayerTradeMoney() return 0 end
function GetTradePlayerItemLink(i) if i == 1 and tGive then return link(tGive[1]) end end
function GetTradePlayerItemInfo(i) if i == 1 and tGive then return tGive[1], nil, tGive[2] end end
function GetTradeTargetItemLink(i) if i == 1 and tGet then return link(tGet[1]) end end
function GetTradeTargetItemInfo(i) if i == 1 and tGet then return tGet[1], nil, tGet[2] end end
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 250 end, GetAuctionPriceByItemID = function() return 250 end } } }
function UnitGUID() return "Player-1" end
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "Bag" }, { leftText = id == 14046 and "14 Slot Bag" or "Binds when equipped" } } } end }
local opened = {}
function ChatFrame_OpenChat(text) opened[#opened + 1] = text end
function GetItemCount(id) return id == 14048 and 12 or 0 end
function PlaySound() end
MastercraftDB = { recipes = { ["Player-1"] = {
	Tailoring = { list = {
		{ id = 1, name = "Runecloth Bag", category = "Bags", learned = true, output = 14046, outputQty = 1, reagents = { { itemID = 14048, qty = 5 } } },
		{ id = 2, name = "Silk Reagent Bag", category = "Specialty Bags", learned = false, output = 500, reagents = { { itemID = 900, qty = 1 } } },
	} },
	Alchemy = { list = { { id = 3, name = "Blue Dye", category = "Dyes", learned = false, output = 900, reagents = {} } } },
} } }

-- ---------------------------------------------------------------- load the add-on in TOC order
local ns, files = {}, {}
for line in TOC_TEXT:gmatch("[^\r\n]+") do
	line = line:gsub("%s+$", "")
	if line ~= "" and not line:match("^#") then files[#files + 1] = line end
end
assert(#files == 10, "TOC should list 10 files, found " .. #files)
local globalsBefore = { codAmount = true }
for k in pairs(_G) do globalsBefore[k] = true end
for _, f in ipairs(files) do assert(loadfile(f))("WoWCRM", ns) end
local U, DB, M, UI = ns.Util, ns.DB, ns.Model, ns.UI

-- ---------------------------------------------------------------- test helpers
local count = 0
local function eq(got, want, what)
	count = count + 1
	if got ~= want then error(("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)), 2) end
end
local function fire(event, ...) ns.eventFrame._scripts.OnEvent(ns.eventFrame, event, ...) end
local function inside(w, root)
	while w do if w == root then return true end w = w._parent end
	return false
end
local function find(text, root)
	for _, w in ipairs(widgets) do
		if w._text == text and w._scripts.OnClick and (not root or inside(w, root)) then return w end
	end
end
local function click(text, root)
	local w = find(text, root)
	if not w then error("no button \"" .. text .. "\"", 2) end
	if not w._enabled then error("button \"" .. text .. "\" is disabled", 2) end
	w._scripts.OnClick(w)
end
local function kind(k, root)
	local out = {}
	for _, w in ipairs(widgets) do if w._kind == k and inside(w, root) then out[#out + 1] = w end end
	return out
end
local function tick(frame) frame._scripts.OnUpdate(frame, 2) end
local function message() return WoWCRMFrame.msg._text end

-- ---------------------------------------------------------------- the session
fire("PLAYER_LOGIN")
eq(ns.ready, true, "ready after login")
eq(type(WoWCRMDB), "table", "saved table created")
eq(WoWCRMSaveButton._shown, false, "save button hidden with nothing to save")

SlashCmdList.WOWCRM("")
eq(WoWCRMFrame._shown, true, "window opens")
for name in pairs(UI.tabs) do UI.Show(name) end

-- write a post
UI.Show("Posts")
local posts = UI.tabs.Posts.panel
local edits, checks = kind("EditBox", posts), kind("CheckButton", posts)
eq(#edits, 2, "post editor has a name and a message box")
eq(#checks, 6, "six channel boxes")
click("Save post", posts)
eq(#DB.R.posts, 0, "empty post refused")
edits[1]:SetText("Enchants")
edits[2]:SetText("WTS enchants in {zone}, whisper {me}")
checks[1]:SetChecked(true) -- Say
checks[4]:SetChecked(true) -- Trade
checks[5]:SetChecked(true) -- Party
click("Save post", posts)
eq(#DB.R.posts, 1, "post saved")
eq(ns.unsaved, 1, "change counted as unsaved")
eq(WoWCRMSaveButton._shown, true, "save button appears")
eq(WoWCRMSaveButton._text, "WoW CRM: save 1 change", "save button text")

-- links: both of the game's insert routes reach the message box, once per click
local PROF = "|cffffd000|Htrade:Player-1:3908:197|h[Tailoring]|h|r"
local base = edits[2]._text
ChatEdit_InsertLink("[early]")
eq(edits[2]._text, base, "no insert while the message box is not focused")
edits[2]:SetFocus()
ChatFrameUtil.InsertLink("[item]")
ChatEdit_InsertLink(PROF)
ChatFrameUtil.InsertLink(PROF) -- same click arriving through the other route
eq(edits[2]._text, base .. "[item]" .. PROF, "item and profession links inserted once each")
edits[2]:SetText(base)
click("Link my profession", posts)
eq(message():find("Open your profession window") ~= nil, true, "explains when no profession window is open")
tradeLink = PROF
click("Link my profession", posts)
eq(edits[2]._text, base .. PROF, "profession link button inserts the link")
edits[2]:SetText(base)
edits[2]:ClearFocus()

-- one click, one message, one channel
tick(posts)
click("Post to Say", posts)
eq(#sent, 1, "one click sends one message")
eq(sent[1].type, "SAY", "to say")
eq(sent[1].text, "WTS enchants in City, whisper Seller", "tokens filled in")
tick(posts)
click("Post to Trade", posts)
eq(#sent, 2, "second click sends the second message")
eq(sent[2].type, "CHANNEL", "trade is a numbered channel")
eq(sent[2].channel, 3, "the real Trade channel, not the services one")
tick(posts)
eq(find("Post next", posts)._enabled, false, "nothing left: party unavailable, others inside their gap")
eq(find("Say", posts)._enabled, false, "say button greyed during its gap")
clock = clock + 61
tick(posts)
eq(find("Post to Say", posts) ~= nil, true, "say available again after the gap")

-- tracking and whispers
fire("CHAT_MSG_WHISPER", "too early", "Early-Stormrage")
eq(#DB.R.leads, 0, "no capture while tracking is off")
click("Turn on contact tracking")
eq(find("Tracking ON - click to stop") ~= nil, true, "tracking button flips")
click("Post to Say", posts)
fire("CHAT_MSG_WHISPER", "how much for a weapon enchant?", "Ann-Stormrage")
fire("CHAT_MSG_WHISPER", SECRET, "Bob")
fire("CHAT_MSG_WHISPER", "hidden sender", SECRET)
eq(#DB.R.leads, 2, "two leads captured, hidden sender skipped")
eq(M.GetContact("Ann-Stormrage").status, "lead", "whisperer becomes a contact")
eq(DB.R.leads[2].text, "(hidden during combat)", "hidden text handled")
eq(M.GetContact("Bob-Stormrage") ~= nil, true, "realm added to bare names")

-- lead -> order
UI.Show("Leads")
local leads = UI.tabs.Leads.panel
for _, w in ipairs(widgets) do
	if w.item == DB.R.leads[1] and inside(w, leads) then w._scripts.OnClick(w) end
end
click("Whisper back", leads)
eq(tells[1], "Ann", "whisper back opens a tell")
click("New order", leads)
local orders = UI.tabs.Orders.panel
local oe = kind("EditBox", orders) -- contact, gold, title, notes, sold qty, sold name, received qty, name, value
eq(#oe, 9, "order form fields")
eq(oe[1]._text, "Ann", "contact carried over from the lead")
click("Mark paid", orders)
eq(#DB.R.orders, 0, "empty order refused")
oe[6]:SetText("Weapon enchant")
click("Add", orders)
oe[2]:SetText("banana")
click("Mark paid", orders)
eq(#DB.R.orders, 0, "bad gold amount refused")
oe[2]:SetText("12g 50s")
click("Mark paid", orders)
eq(#DB.R.orders, 1, "order saved")
eq(DB.R.orders[1].items[1].name, "Weapon enchant", "sold item kept as its own line")
eq(M.LTV("Ann-Stormrage"), 125000, "lifetime value from the paid order")
eq(DB.R.leads[1].status, "won", "lead closed by the order")
eq(M.GetContact("Ann-Stormrage").status, "customer", "lead promoted to customer")

-- a tip in goods: typed value, then flipped to materials and back out of income
oe[7]:SetText("20")
oe[8]:SetText("Silk Cloth")
oe[9]:SetText("5s")
click("Add payment", orders)
click("Save order", orders)
eq(M.LTV("Ann-Stormrage"), 135000, "goods received as payment add to lifetime value")
for _, w in ipairs(widgets) do
	if type(w.item) == "table" and w.item.line and w.item.line.kind and inside(w, orders) and w._shown then w._scripts.OnClick(w) end
end
click("Flip kind", orders)
click("Save order", orders)
eq(DB.R.orders[1].received[1].kind, "mats", "line flipped to materials")
eq(M.LTV("Ann-Stormrage"), 125000, "materials for the job are not income")

-- contact with a referrer
UI.Show("Contacts", "Bob-Stormrage")
local contacts = UI.tabs.Contacts.panel
local ce = kind("EditBox", contacts)
ce[3]:SetText("ann")
click("Save contact", contacts)
eq(M.GetContact("Bob-Stormrage").referredBy, "Ann-Stormrage", "referrer saved from typed name")
ce[3]:SetText("nobody")
click("Save contact", contacts)
eq(message():find("not a contact yet") ~= nil, true, "unknown referrer explained")
ce[1]:SetText("carl")
click("Add", contacts)
eq(M.GetContact("Carl-Stormrage") ~= nil, true, "contact added by name")

-- one job across three trades: materials in, bags out, tip afterwards
local before = #DB.R.orders
local function doTrade(give, get, gold)
	tGive, tGet, tGold = give, get, gold
	fire("TRADE_SHOW")
	fire("TRADE_ACCEPT_UPDATE", 1, 1)
	fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, "Trade complete.")
end
doTrade(nil, { "Silk Cloth", 20 }, 0)
eq(#DB.R.orders, before + 1, "materials trade starts an order")
local o = DB.R.orders[#DB.R.orders]
eq(o.contact, "Buyer-Stormrage", "trade partner")
eq(o.status, "in progress", "materials received, nothing delivered yet")
eq(o.received[1].kind, "mats", "goods before delivery are materials")
eq(o.received[1].value, 250, "valued from the auction add-on")
doTrade({ "Silk Bag", 2 }, nil, 0)
eq(#DB.R.orders, before + 1, "follow-up trade joins the same order")
eq(o.status, "delivered", "free job is delivered, not paid")
eq(M.OrderTitle(o), "2x Silk Bag", "items described")
doTrade(nil, { "Mageweave Cloth", 5 }, 50000)
eq(#DB.R.orders, before + 1, "tip trade joins the same order")
eq(o.status, "paid", "tip makes it paid")
eq(o.received[2].kind, "payment", "goods after delivery are payment")
local og, ogoods, omats = M.OrderValue(o)
eq(og, 50000, "gold on the order")
eq(ogoods, 1250, "goods value on the order")
eq(omats, 5000, "materials value on the order")
eq(o.trades, 3, "three trades on one order")
fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, "Trade complete.")
eq(o.trades, 3, "the same trade is not recorded twice")

-- the contact page lists the orders and opens one on click
UI.Show("Contacts", "Ann-Stormrage")
for _, w in ipairs(widgets) do
	if w.item == DB.R.orders[1] and inside(w, contacts) and w._shown then w._scripts.OnClick(w) end
end
eq(kind("EditBox", orders)[2]._text, "12g 50s", "clicking an order on the contact page opens it")

-- mail
UI.Show("Mail", "Ann-Stormrage")
local mail = UI.tabs.Mail.panel
eq(find("Fill in letter", mail)._enabled, false, "no letter away from a mailbox")
fire("MAIL_SHOW")
click("Fill in letter", mail)
eq(SendMailNameEditBox._text, "Ann", "recipient filled in")
eq(SendMailSubjectEditBox._text, "Your order is ready", "subject filled in")
eq(SendMailBodyEditBox._text:find("Weapon enchant", 1, true) ~= nil, true, "body mentions the order")
eq(SendMailBodyEditBox._text:find("12g 50s", 1, true) ~= nil, true, "body mentions the total")
before = #DB.R.orders
SendMail("Ann", "Your order is ready", "body")
fire("MAIL_SEND_SUCCESS")
eq(#DB.R.mailLog, 1, "sent mail logged against the contact")
eq(M.GetContact("Ann-Stormrage").outreach, 1, "sending the filled-in letter counts as one follow-up")
eq(#DB.R.orders, before + 1, "cash-on-delivery mail recorded after confirming")
eq(DB.R.orders[#DB.R.orders].status, "delivered", "COD is delivered, not yet paid")
eq(DB.R.orders[#DB.R.orders].items[1].qty, 2, "COD attachments become item lines")
eq(DB.R.orders[#DB.R.orders].contact, "Ann-Stormrage", "COD order on the right contact")
codAmount = 0
SendMail("Ann", "something else", "body")
fire("MAIL_SEND_SUCCESS")
eq(M.GetContact("Ann-Stormrage").outreach, 1, "a letter the add-on did not fill in is not counted")
-- pick the next person from the follow-up list
local picked
for _, w in ipairs(widgets) do
	if type(w.item) == "table" and w.item.key == "Carl-Stormrage" and w.item.count and inside(w, mail) and w._shown then picked = w end
end
eq(picked ~= nil, true, "leads appear in the follow-up list")
picked._scripts.OnClick(picked)
click("Fill in letter", mail)
eq(SendMailNameEditBox._text, "Carl", "clicking a lead addresses the letter to them")
SendMail("Carl", "s", "b")
fire("MAIL_SEND_SUCCESS")
eq(M.GetContact("Carl-Stormrage").outreach, 1, "follow-up to the lead counted")
eq(M.GetContact("Carl-Stormrage").lastTemplate, "Order ready", "template used is remembered")
fire("MAIL_CLOSED")

-- dashboard, bar, probe
UI.Show("Dashboard")
local dash = UI.tabs.Dashboard.panel
click("Export", dash)
local exported = false
for _, w in ipairs(kind("EditBox", dash)) do if w._text:sub(1, 7) == "WOWCRM2" then exported = true end end
eq(exported, true, "export produced")
UI.Show("Options")
local opts = UI.tabs.Options.panel
kind("EditBox", opts)[1]:SetText("5")
click("Apply options", opts)
eq(DB.settings.minGap, 30, "option below the minimum is raised to it")

-- a campaign: start, post when due, wait out the gap, finish
UI.Show("Campaigns")
local camp = UI.tabs.Campaigns.panel
local cedits = kind("EditBox", camp) -- name, minutes, wait
eq(cedits[2]._text, "60", "campaign length comes from the options")
eq(cedits[3]._text, "5", "wait between posts comes from the options")
cedits[1]:SetText("Evening bags")
cedits[2]:SetText("30")
clock = clock + 600
M.cursor = {} -- start this post's channel rotation from the top
click("Start campaign", camp)
local running = M.ActiveCampaign(clock)
eq(running ~= nil, true, "campaign started")
eq(#running.posts, 1, "ticked posts are in the campaign")
eq(find("Start campaign", camp)._enabled, false, "cannot start a second campaign while one runs")
local alerts = 0
local function countAlerts() local n = 0; for _, m in ipairs(printed) do if m:find("time to post", 1, true) then n = n + 1 end end return n end
UI.CampaignTick()
eq(countAlerts(), 1, "one alert when a post is due")
UI.CampaignTick()
eq(countAlerts(), 1, "the alert is not repeated every second")
local nsent = #sent
click("Enchants > Say")
eq(#sent, nsent + 1, "campaign bar click sends one message")
click("Enchants > Trade")
eq(#sent, nsent + 2, "next click sends to the next channel")
eq(find("Next post in 5:00") ~= nil, true, "then the bar counts down the campaign wait")
clock = clock + 120
UI.CampaignTick()
eq(find("Next post in 3:00") ~= nil, true, "countdown follows the clock")
eq(#sent, nsent + 2, "nothing is posted without a click")
fire("CHAT_MSG_WHISPER", "do you make bags?", "Dora-Stormrage")
eq(DB.R.leads[#DB.R.leads].campaign, running.id, "whisper during a campaign is tied to it")
clock = clock + 181
UI.CampaignTick()
eq(countAlerts(), 2, "alert again when the wait is over")
eq(find("Enchants > Say") ~= nil, true, "post offered again after the wait")
local crep = M.CampaignReport(running.id)
eq(crep.sends, 2, "campaign counted its posts")
eq(crep.leads, 1, "campaign counted its lead")
clock = clock + 1800
UI.CampaignTick()
eq(running.status, "ended", "campaign ends when its time is up")
eq(find("Start one on the Campaigns tab") ~= nil, true, "bar says no campaign is running")

-- products: read from the recipe scan, with prices and cross-profession materials
UI.Show("Products")
local prod = UI.tabs.Products.panel
click("Alchemy", prod)
local function row(name)
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item.name == name and w.item.reagents and inside(w, prod) and w._shown then return w end
	end
end
eq(row("Runecloth Bag") ~= nil, true, "recipes listed for the chosen profession")
eq(row("Runecloth Bag").item.canMake, 2, "12 cloth in bags at 5 each makes 2")
local boxes = kind("CheckButton", prod) -- learned, craftable, my products
boxes[2]:SetChecked(true)
boxes[2]._scripts.OnClick(boxes[2])
eq(row("Silk Reagent Bag"), nil, "Craftable now hides what you lack materials for")
eq(row("Runecloth Bag") ~= nil, true, "and keeps what you can make")
boxes[2]:SetChecked(false)
boxes[2]._scripts.OnClick(boxes[2])
row("Runecloth Bag")._scripts.OnClick(row("Runecloth Bag"))
click("Add to my products", prod)
eq(DB.R.products["Tailoring|Runecloth Bag"] ~= nil, true, "recipe marked as my product")
eq(find("Remove from my products", prod) ~= nil, true, "button flips once it is a product")
row("Silk Reagent Bag")._scripts.OnClick(row("Silk Reagent Bag"))
eq(row("Runecloth Bag").item.slots, 14, "bag size read from the tooltip")
local headers = 0
for _, w in ipairs(widgets) do if type(w.item) == "table" and w.item.header and inside(w, prod) and w._shown then headers = headers + 1 end end
eq(headers, 2, "recipes are laid out under a heading per category")
row("Runecloth Bag")._scripts.OnClick(row("Runecloth Bag"))
local pe = kind("EditBox", prod) -- search, my price
pe[2]:SetText("2g")
click("Set", prod)
eq(DB.R.products["Tailoring|Runecloth Bag"].price, 20000, "your price saved")
click("Quote", prod)
eq(opened[#opened], "/r Runecloth Bag (14 slot) 2g", "quote placed in chat as a reply")
click("Quote list", prod)
eq(opened[#opened]:find("Runecloth Bag (14 slot) 2g", 1, true) ~= nil, true, "price list placed in chat as a reply")
row("Silk Reagent Bag")._scripts.OnClick(row("Silk Reagent Bag"))
local flagged = false
for _, w in ipairs(widgets) do if w._kind == "FontString" and w._text:find("made by Alchemy", 1, true) then flagged = true end end
eq(flagged, true, "material made by another profession is flagged")
SlashCmdList.WOWCRM("bar")
eq(DB.settings.barShown, true, "quick-post bar shown")
clock = clock + 120
local n = #sent
local barButton
for _, w in ipairs(widgets) do
	if w._text:find("^Enchants > ") and w._scripts.OnClick then barButton = w end
end
eq(barButton ~= nil, true, "bar has a button for the post")
barButton._scripts.OnClick(barButton)
eq(#sent, n + 1, "bar click sends one message")

SlashCmdList.WOWCRM("probe")
click("1. Say from a click")
eq(DB.db.probe.say_click, "sent", "probe records the click result")
eq(DB.db.probe.targets.TRADE, "ok", "probe records channel availability")
eq(DB.db.probe.targets.PARTY, "not in a party", "probe records why a channel is unavailable")

-- a reload keeps everything
M.SetTracking(true, clock) -- the long campaign above let tracking time out, as it should
local saved = WoWCRMDB
DB.Init(saved, "Stormrage")
eq(#DB.R.posts, 1, "posts survive a reload")
eq(DB.R.tracking.on, true, "tracking survives a reload")

-- the add-on must not leak names into the game's shared global space
local allowed = {
	WoWCRMDB = true, WoWCRMFrame = true, WoWCRMSaveButton = true, WoWCRM_OnCompartmentClick = true,
	SLASH_WOWCRM1 = true, SLASH_WOWCRM2 = true,
	WoWCRMScanTooltip = true, -- hidden tooltip used to read bag sizes
}
for k in pairs(_G) do
	if not globalsBefore[k] and not allowed[k] then error("unexpected global: " .. tostring(k)) end
end
count = count + 1

print(("test_smoke: %d checks passed (%d confirmation prompts)"):format(count, popups))
