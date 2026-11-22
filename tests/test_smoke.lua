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
function methods:GetFrameLevel() return 1 end
function methods:GetStringHeight() return 12 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetScript(n) return self._scripts[n] end
function methods:HookScript(n, f)
	local old = self._scripts[n]
	self._scripts[n] = old and function(...) old(...); f(...) end or f
end

-- ---------------------------------------------------------------- stand-in game API
function CreateFrame(kind, name, parent)
	local w = widget(kind, parent)
	if name then _G[name] = w end
	return w
end
UIParent = widget("Frame")
Minimap = widget("Frame")
GameTooltip = widget("GameTooltip")
MailFrame = widget("Frame")
MailFrame:Hide() -- closed until the test walks up to a mailbox
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
local inCombat, speed, resting = false, 0, false
function InCombatLockdown() return inCombat end
function GetUnitSpeed() return speed end
function IsResting() return resting end
function GetNormalizedRealmName() return "Stormrage" end
function GetRealmName() return "Stormrage" end
local npcName, npcSecond = "Buyer", nil
function UnitName(unit) if unit == "player" then return "Seller" elseif unit == "NPC" then return npcName, npcSecond end return "Targ" end
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
local sourceReady = false
C_TradeSkillUI = {
	GetTradeSkillListLink = function() return tradeLink end,
	GetRecipeSourceText = function(id) if sourceReady and id == 2 then return "Vendor: |cffffffffBorya|r\nOrgrimmar" end end,
}
local mcOpened = 0
function Mastercraft_Toggle() mcOpened = mcOpened + 1 end
-- a stand-in for the game's Blacksmithing window
local BS = {
	{ name = "Armor", kind = "header" },
	{ name = "Patterned Bronze Bracers", kind = "optimal", out = 2672, reagents = { { "Bronze Bar", 2841, 5 }, { "Coarse Grinding Stone", 3478, 2 } } },
	{ name = "Coarse Grinding Stone", kind = "easy", out = 3478, reagents = { { "Coarse Stone", 2836, 2 } } },
}
local bsSel = 2
local function ilink(id, name) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end
function GetNumTradeSkills() return #BS end
function GetTradeSkillInfo(i) local r = BS[i]; if r then return r.name, r.kind, 0, true end end
function GetTradeSkillItemLink(i) local r = BS[i]; if r and r.out then return ilink(r.out, r.name) end end
function GetTradeSkillNumMade() return 1, 1 end
function GetTradeSkillNumReagents(i) return BS[i] and BS[i].reagents and #BS[i].reagents or 0 end
function GetTradeSkillReagentInfo(i, r) local g = BS[i] and BS[i].reagents and BS[i].reagents[r]; if g then return g[1], nil, g[3], 0 end end
function GetTradeSkillReagentItemLink(i, r) local g = BS[i] and BS[i].reagents and BS[i].reagents[r]; if g then return ilink(g[2], g[1]) end end
function GetTradeSkillSelectionIndex() return bsSel end
function GetTradeSkillLine() return "Blacksmithing", 100, 300 end
function TradeSkillFrame_SetSelection(i) bsSel = i end
function TradeSkillFrame_Update() end
function ExpandTradeSkillSubClass() end
function IsModifiedClick() return false end
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
local SLOTS = { [14046] = "14 Slot Bag", [4238] = "6 Slot Bag" }
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "Bag" }, { leftText = SLOTS[id] or "Binds when equipped" } } } end }
local opened = {}
function ChatFrame_OpenChat(text) opened[#opened + 1] = text end
function GetItemCount(id, withBank) return id == 14048 and (withBank and 20 or 12) or 0 end
BrotherBags = { forever = { ["Bag Makers*"] = { { items = { "14048;25" } } } } }
function PlaySound() end
local friends, raidWarnings = {}, {}
C_FriendList = {
	AddFriend = function(name, note) friends[#friends + 1] = { name = name, note = note, connected = false } end,
	RemoveFriend = function(name) for i = #friends, 1, -1 do if friends[i].name == name then table.remove(friends, i) end end end,
	GetNumFriends = function() return #friends end,
	GetFriendInfoByIndex = function(i) return friends[i] end,
}
RaidWarningFrame = {}
function RaidNotice_AddMessage(_, text) raidWarnings[#raidWarnings + 1] = text end
MastercraftDB = { inv = { ["Player-1"] = { bags = {}, bank = { [14048] = 8 } }, ["Player-2"] = { bags = { [14048] = 5 }, bank = { [14048] = 10 } } }, recipes = { ["Player-1"] = {
	Tailoring = { list = {
		{ id = 1, name = "Runecloth Bag", category = "Bags", learned = true, output = 14046, outputQty = 1, reagents = { { itemID = 14048, qty = 5 } } },
		{ id = 2, name = "Silk Reagent Bag", category = "Specialty Bags", learned = false, output = 500, reagents = { { itemID = 900, qty = 1 } } },
		{ id = 4, name = "Linen Bag", category = "Bags", learned = true, output = 4238, reagents = { { itemID = 2996, qty = 3 } } },
	} },
	Alchemy = { list = { { id = 3, name = "Blue Dye", category = "Dyes", learned = false, output = 900, reagents = {} } } },
} } }

-- ---------------------------------------------------------------- load the add-on in TOC order
local ns, files = {}, {}
for line in TOC_TEXT:gmatch("[^\r\n]+") do
	line = line:gsub("%s+$", "")
	if line ~= "" and not line:match("^#") then files[#files + 1] = line end
end
assert(#files == 14, "TOC should list 14 files, found " .. #files)
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
eq(DB.settings.publicSpacing, 2, "two minutes between public posts by default")
eq(ns.MyName(), "Seller", "own name")
eq(M.me, "Seller-Stormrage", "who is playing")
DB.settings.publicSpacing = 0 -- the steps below post back to back; the pause has its own steps near the end
eq(type(WoWCRMDB), "table", "saved table created")
eq(WoWCRMSaveButton._shown, false, "save button hidden with nothing to save")

SlashCmdList.WOWCRM("")
eq(WoWCRMFrame._shown, true, "window opens")
for name in pairs(UI.tabs) do UI.Show(name) end

-- write a post
UI.Show("Posts")
local posts = UI.tabs.Posts.panel
local edits, checks = kind("EditBox", posts), kind("CheckButton", posts)
eq(#edits, 3, "post editor has a name, a message box and a whisper box")
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
eq(WoWCRMSaveButton._shown, false, "one change does not bring up the backup offer")
local function saveTick() ns.eventFrame._scripts.OnUpdate(ns.eventFrame, 3) end
local realUnsaved = ns.unsaved
ns.unsaved = 25
saveTick()
eq(WoWCRMSaveButton._shown, true, "offer appears once enough changes are waiting and you are standing still")
eq(WoWCRMSaveButton._text, "WoW CRM: back up 25 changes", "backup button text")
speed = 7
saveTick()
eq(WoWCRMSaveButton._shown, false, "no offer while you are on the move")
speed = 0
saveTick()
eq(WoWCRMSaveButton._shown, false, "nor in the first seconds after stopping")
resting = true
saveTick()
eq(WoWCRMSaveButton._shown, true, "resting counts as a quiet moment straight away")
inCombat = true
saveTick()
eq(WoWCRMSaveButton._shown, false, "never in combat")
inCombat, resting = false, false
clock = clock + 15
saveTick()
eq(WoWCRMSaveButton._shown, true, "offer returns after standing still for a while")
ns.unsaved = realUnsaved
saveTick()
eq(WoWCRMSaveButton._shown, false, "back below the threshold, no offer")
ns.firstUnsaved = clock - 31 * 60
saveTick()
eq(WoWCRMSaveButton._shown, true, "a change that has waited half an hour is offered too")
ns.firstUnsaved = clock
saveTick()

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

-- posts belong to a character
eq(DB.R.posts[1].owner, "Seller-Stormrage", "a post written here belongs to this character")
local alien = M.SavePost(nil, "Main's post", "WTS from the main", { SAY = true }, "Main Char-Stormrage")
local alienSent = #sent
local ok, why = ns.Chat.Send(alien, "SAY")
eq(ok, false, "another character's post is never sent")
eq(why:find("Main Char", 1, true) ~= nil, true, "and it says whose post it is")
eq(#sent, alienSent, "nothing went to chat")
local legacy = M.SavePost(nil, "Old post", "from before owners", { SAY = true })
legacy.owner = nil
ns.OfferAssignPosts()
eq(legacy.owner, "Seller-Stormrage", "posts with no owner are offered to the character logging in")
M.DeletePost(alien.id); M.DeletePost(legacy.id)
UI.Show("Posts")

-- whisper a post to someone
local pe2 = kind("EditBox", posts) -- name, message, whisper to
eq(#pe2, 3, "post editor has a whisper box")
eq(find("Reply to last whisper", posts)._enabled, false, "no reply button until someone whispers")
pe2[3]:SetText("Zed")
local beforeWhisper, logBefore = #sent, #DB.R.postLog
click("Whisper", posts)
eq(#sent, beforeWhisper + 1, "whisper sent")
eq(sent[#sent].type, "WHISPER", "as a whisper")
eq(sent[#sent].channel, "Zed", "to the named player")
eq(sent[#sent].text, "WTS enchants in City, whisper Seller", "with the post's text")
eq(#DB.R.postLog, logBefore, "a whisper is not counted as a post")

-- tracking and whispers
eq(M.TrackingState(clock), true, "posting earlier switched tracking on by itself")
ns.SetTracking(false)
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
tick(posts)
click("Reply to Bob", posts)
eq(sent[#sent].type, "WHISPER", "reply goes out as a whisper")
eq(sent[#sent].channel, "Bob", "to whoever whispered last")

-- lead -> order
UI.Show("Leads")
local leads = UI.tabs.Leads.panel
for _, w in ipairs(widgets) do
	if w.item == DB.R.leads[1] and inside(w, leads) then w._scripts.OnClick(w) end
end
click("Whisper back", leads)
eq(tells[1], "Ann", "whisper back opens a tell")
-- the conversation so far: my reply goes into the thread
fire("CHAT_MSG_WHISPER_INFORM", "20g with your mats", "Ann")
eq(#M.GetContact("Ann-Stormrage").chat, 2, "their whisper and my reply are both kept")
eq(M.GetContact("Ann-Stormrage").chat[2].me, true, "my reply is marked as mine")
eq(#M.LeadChat(DB.R.leads[1]), 2, "the lead shows the whole conversation")
-- a second post while we are still talking does not start a second lead
clock = clock + 200
eq(ns.Chat.Send(M.GetPost(DB.R.tracking.post), "SAY"), true, "another post goes out")
fire("CHAT_MSG_WHISPER", "still keen on that enchant", "Ann")
eq(#DB.R.leads, 2, "same conversation, same lead")
eq(DB.R.leads[1].count, 2, "the lead counts both whispers")
UI.Show("Leads")
click("Make it an order", leads)
click("Empty order", leads)
local orders = UI.tabs.Orders.panel
local oe = kind("EditBox", orders) -- contact, gold, title, agreed, notes, sold qty, sold name, received qty, name, value
eq(#oe, 10, "order form fields")
eq(#DB.R.orders, 1, "the lead became an order")
eq(DB.R.leads[1].status, "won", "lead closed by the order")
eq(DB.R.leads[1].order, DB.R.orders[1].id, "lead remembers its order")
eq(oe[1]._text, "Ann", "contact carried over from the lead")
oe[7]:SetText("Weapon enchant")
click("Add", orders)
oe[2]:SetText("banana")
click("Mark paid", orders)
eq(DB.R.orders[1].status, "quoted", "bad gold amount refused")
oe[2]:SetText("12g 50s")
click("Mark paid", orders)
eq(#DB.R.orders, 1, "order saved")
eq(DB.R.orders[1].items[1].name, "Weapon enchant", "sold item kept as its own line")
eq(M.LTV("Ann-Stormrage"), 125000, "lifetime value from the paid order")
eq(M.GetContact("Ann-Stormrage").status, "customer", "lead promoted to customer")

-- a tip in goods: typed value, then flipped to materials and back out of income
oe[8]:SetText("20")
oe[9]:SetText("Silk Cloth")
oe[10]:SetText("5s")
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

-- a trade with someone whose two-part name the game hands back split in two
fire("CHAT_MSG_WHISPER", "can you make 4?", "Rosa Vell-Stormrage")
npcName, npcSecond = "Rosa", "Vell"
local rosaOrders = #DB.R.orders
doTrade({ "Silk Bag", 4 }, nil, 40000)
npcName, npcSecond = "Buyer", nil
eq(#DB.R.orders, rosaOrders + 1, "trade recorded")
eq(DB.R.orders[#DB.R.orders].contact, "Rosa Vell-Stormrage", "on the whisperer's whole name, not a half name")
eq(M.GetContact("Rosa-Vell"), nil, "no half-name contact made")
eq(M.GetContact("Rosa Vell-Stormrage").status, "customer", "the lead became a customer")

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
MailFrame:Show()
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
local function mailSays(text)
	for _, w in ipairs(widgets) do if w._kind == "FontString" and inside(w, mail) and w._text:find(text, 1, true) then return true end end
	return false
end
eq(mailSays("Has not bought anything yet"), true, "someone with no orders is flagged as not having bought")
UI.Show("Mail", "Rosa Vell-Stormrage")
eq(mailSays("Has bought from you:|r 1 order, 4g paid in total"), true, "a buyer's orders are shown when picked")
eq(mailSays("past-customer letter"), true, "and a past-customer letter is suggested")
UI.Show("Mail", "Carl-Stormrage")
SendMail("Carl", "s", "b")
fire("MAIL_SEND_SUCCESS")
eq(M.GetContact("Carl-Stormrage").outreach, 1, "follow-up to the lead counted")
eq(M.GetContact("Carl-Stormrage").lastTemplate, "Order ready", "template used is remembered")
MailFrame:Hide()
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
clock = clock + 15
ns.eventFrame._scripts.OnUpdate(ns.eventFrame, 3)
eq(WoWCRMSaveButton._shown, true, "a finished campaign is a natural moment to offer a backup")

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
local boxes = kind("CheckButton", prod) -- learned, have the mats, my products, then the five places to count
eq(#boxes, 9, "three filters, five places to count, and held-mats-are-free")
eq(DB.settings.heldFree, true, "held mats count as free unless switched off")
eq(row("Runecloth Bag").item.cost, 0, "12 cloth in bags covers the 5 needed: nothing to buy")
boxes[9]:SetChecked(false)
boxes[9]._scripts.OnClick(boxes[9])
eq(row("Runecloth Bag").item.cost, 1250, "switched off: all 5 cloth at today's price")
boxes[9]:SetChecked(true)
boxes[9]._scripts.OnClick(boxes[9])
local function tick(i, on) boxes[i]:SetChecked(on); boxes[i]._scripts.OnClick(boxes[i]) end
tick(5, true)
eq(row("Runecloth Bag").item.canMake, 4, "adding my bank: 20 cloth makes 4")
tick(6, true)
eq(row("Runecloth Bag").item.canMake, 5, "adding other characters' bags")
tick(7, true)
eq(row("Runecloth Bag").item.canMake, 7, "adding other characters' banks")
tick(8, true)
eq(row("Runecloth Bag").item.canMake, 12, "adding the guild bank")
eq(DB.settings.invSources.guild, true, "the choice is remembered")
tick(5, false); tick(6, false); tick(7, false); tick(8, false)
eq(row("Runecloth Bag").item.canMake, 2, "back to bags only")
boxes[2]:SetChecked(true)
boxes[2]._scripts.OnClick(boxes[2])
eq(row("Silk Reagent Bag"), nil, "Craftable now hides what you lack materials for")
eq(row("Runecloth Bag") ~= nil, true, "and keeps what you can make")
boxes[2]:SetChecked(false)
boxes[2]._scripts.OnClick(boxes[2])
row("Runecloth Bag")._scripts.OnClick(row("Runecloth Bag"))
click("Add to products", prod)
eq(DB.R.products["Tailoring|Runecloth Bag"] ~= nil, true, "recipe marked as my product")
eq(find("Remove product", prod) ~= nil, true, "button flips once it is a product")
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
eq(opened[#opened], "/w Dora Hi Dora! Runecloth Bag (14 slot) is 2g with my mats. I can also do Linen Bag (6 slot) for 2s 50c.",
	"personal quote to whoever asked, with the next smaller bag")
click("Quote list", prod)
eq(opened[#opened]:find("Runecloth Bag (14 slot) 2g", 1, true) ~= nil, true, "price list placed in chat as a reply")
row("Silk Reagent Bag")._scripts.OnClick(row("Silk Reagent Bag"))
local function detailHas(text)
	for _, w in ipairs(widgets) do if w._kind == "FontString" and w._text:find(text, 1, true) then return true end end
	return false
end
eq(detailHas("How to get this pattern:|r not known yet"), true, "unlearned recipe says the source is not known yet")
sourceReady = true -- the profession window is now open, so the game answers
row("Silk Reagent Bag")._scripts.OnClick(row("Silk Reagent Bag"))
eq(detailHas("How to get this pattern:|r Vendor: Borya / Orgrimmar"), true, "source shown once the game provides it")
sourceReady = false
row("Silk Reagent Bag")._scripts.OnClick(row("Silk Reagent Bag"))
eq(detailHas("Vendor: Borya / Orgrimmar"), true, "source is remembered after the window closes")
click("Codex", prod)
eq(mcOpened, 1, "without its slash command, Mastercraft simply opens")
local mcArg
SlashCmdList.MASTERCRAFT = function(a) mcArg = a end
click("Codex", prod)
eq(mcArg, "codex", "Codex button opens Mastercraft on its Codex")
SlashCmdList.MASTERCRAFT = nil
click("Wowhead", prod)
local linkShown = false
for _, w in ipairs(widgets) do if w._kind == "EditBox" and w._text == "https://www.wowhead.com/forever/spell=2" then linkShown = true end end
eq(linkShown, true, "Wowhead address shown ready to copy")
local flagged = false
for _, w in ipairs(widgets) do if w._kind == "FontString" and w._text:find("made by Alchemy", 1, true) then flagged = true end end
eq(flagged, true, "material made by another profession is flagged")
SlashCmdList.WOWCRM("bar")
eq(DB.settings.barShown, true, "quick-post bar shown")
clock = clock + 120
local barRoot
for _, w in ipairs(widgets) do
	if w._kind == "FontString" and w._text:find("^WoW CRM posts for Seller") then barRoot = w._parent end
end
eq(barRoot ~= nil, true, "the bar says which character it posts as")
eq(DB.settings.barChannel, "TRADE", "Trade is picked to start with")
local n = #sent
local barButton = find("Enchants", barRoot)
eq(barButton ~= nil, true, "bar has a button for the post")
barButton._scripts.OnClick(barButton)
eq(#sent, n + 1, "bar click sends one message")
eq(sent[#sent].channel, 3, "to the picked channel: Trade")
click("Guild", barRoot)
eq(DB.settings.barChannel, "GUILD", "another channel picked")
barButton._scripts.OnClick(barButton)
eq(sent[#sent].type, "GUILD", "the same post goes to Guild, though it is not ticked for Guild")
click("Party", barRoot)
eq(barButton._enabled, false, "not in a party: the post buttons wait")
click("Say", barRoot)
barButton._scripts.OnClick(barButton)
eq(sent[#sent].type, "SAY", "and to Say")
eq(#sent, n + 3, "one message per click, nothing else")

-- the bar's one button: next post, next channel, strict pause between posts
DB.settings.publicSpacing = 2
clock = clock + 300
UI.ToggleBar(); UI.ToggleBar() -- hide and show to redraw
local cyc
for _, w in ipairs(widgets) do if w._scripts.OnClick and w._text:find("^Next: ") then cyc = w end end
eq(cyc ~= nil, true, "the quick-post bar has a one-button cycle")
eq(cyc._text, "Next: Enchants > General", "it starts with General")
local before = #sent
cyc._scripts.OnClick(cyc)
eq(#sent, before + 1, "one tap, one message")
eq(sent[#sent].channel, 1, "to General")
eq(cyc._text, "Next post in 2:00", "then a two-minute pause")
eq(cyc._enabled, false, "the button cannot be pressed during the pause")
eq(barButton._enabled, false, "the single-post buttons wait too")
clock = clock + 120
UI.ToggleBar(); UI.ToggleBar()
eq(cyc._text, "Next: Enchants > Trade", "then Trade")
cyc._scripts.OnClick(cyc)
eq(sent[#sent].channel, 3, "to the Trade channel")
local fullChannels = GetChannelList
GetChannelList = function() return 1, "General - Field", false end
clock = clock + 120
UI.ToggleBar(); UI.ToggleBar()
eq(cyc._text, "Next: Enchants > General", "outside a city it goes to General")
local bc = kind("CheckButton", cyc._parent)
eq(#bc, 3, "General, Trade and Yell boxes")
eq(bc[3]:GetChecked(), false, "yell is left out unless ticked")
bc[3]:SetChecked(true); bc[3]._scripts.OnClick(bc[3])
eq(DB.settings.cycleChannels.YELL, true, "the yell choice is remembered")
eq(cyc._text, "Next: Enchants > Yell", "yell takes its turn when ticked")
bc[3]:SetChecked(false); bc[3]._scripts.OnClick(bc[3])
GetChannelList = fullChannels
DB.settings.publicSpacing = 0

-- copy a post for this character
UI.Show("Posts")
local before = #DB.R.posts
local theirPost = M.SavePost(nil, "Main's pitch", "WTS from the main", { SAY = true }, "Main Char-Stormrage")
UI.tabs.Posts.Select(theirPost.id)
click("Copy this post for me", UI.tabs.Posts.panel)
eq(#DB.R.posts, before + 2, "copied")
eq(DB.R.posts[#DB.R.posts].owner, "Seller-Stormrage", "the copy is this character's")
M.DeletePost(theirPost.id); M.DeletePost(DB.R.posts[#DB.R.posts].id)

-- follow-ups: told when someone you owe a reply comes online
M.EnsureContact("Wren Kettle-Stormrage", clock)
UI.Show("Contacts", "Wren Kettle-Stormrage")
local cpanel = UI.tabs.Contacts.panel
click("Follow up", cpanel)
eq(M.GetContact("Wren Kettle-Stormrage").followUp ~= nil, true, "marked for follow-up")
eq(#friends, 1, "added to this character's friends list")
eq(friends[1].name, "Wren Kettle", "by the name you whisper them by")
eq(friends[1].note, "WoW CRM follow-up", "with a note saying why")
eq(find("Stop follow-up", cpanel) ~= nil, true, "the button flips")
local warned = #raidWarnings
fire("FRIENDLIST_UPDATE")
eq(#raidWarnings, warned, "no alert while they are offline")
friends[1].connected = true
fire("FRIENDLIST_UPDATE")
eq(#raidWarnings, warned + 1, "alert when they log in")
eq(raidWarnings[#raidWarnings]:find("Wren Kettle", 1, true) ~= nil, true, "naming them")
fire("FRIENDLIST_UPDATE")
eq(#raidWarnings, warned + 1, "only once")
M.SetFollowUp("Carl-Stormrage", "wants a bag", clock + 1)
fire("CHAT_MSG_CHANNEL", "LFG RFD", "Carl-Stormrage")
eq(#raidWarnings, warned + 2, "alert when someone you follow up with speaks in a channel")
fire("CHAT_MSG_CHANNEL", "anyone?", "Carl-Stormrage")
eq(#raidWarnings, warned + 2, "not on every line they say")
local fwRows = {}
for _, w in ipairs(widgets) do if w._text == "Done" and w._scripts.OnClick and w._shown then fwRows[#fwRows + 1] = w end end
eq(#fwRows, 2, "the follow-up window lists both")
fwRows[1]._scripts.OnClick(fwRows[1])
eq(M.GetContact("Wren Kettle-Stormrage").followUp, nil, "Done ends the follow-up")
local wrenListed = false
for _, f in ipairs(friends) do if f.name == "Wren Kettle" then wrenListed = true end end
eq(wrenListed, false, "and takes them off the friends list WoW CRM put them on")
eq(friends[1] and friends[1].name, "Carl", "while the remaining follow-up is now watched too")
M.ClearFollowUp("Carl-Stormrage")

-- minimap button
eq(WoWCRMMinimapButton ~= nil, true, "minimap button made at login")
WoWCRMFrame:Hide()
WoWCRMMinimapButton._scripts.OnClick(WoWCRMMinimapButton, "LeftButton")
eq(WoWCRMFrame._shown, true, "clicking it opens the window")
DB.settings.showMinimap = false
UI.UpdateMinimap()
eq(WoWCRMMinimapButton._shown, false, "it can be hidden")

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

-- double-clicking materials in the profession window
TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame")
for i = 1, 8 do CreateFrame("Button", "TradeSkillReagent" .. i, TradeSkillFrame) end
fire("ADDON_LOADED", "Blizzard_TradeSkillUI")
local function dbl(i) local b = _G["TradeSkillReagent" .. i]; b._scripts.OnClick(b); clock = clock + 0.2; b._scripts.OnClick(b) end
local RS = ns.Reagents.state.trade
TradeSkillFrame_SetSelection(2); TradeSkillFrame_Update()
eq(RS.dock._shown, true, "bracers need a grinding stone you do not hold: advice shown")
eq(RS.dock.plan._text:find("Craft first: 2x Coarse Grinding Stone", 1, true) ~= nil, true, "it says what to craft first")
clock = clock + 5
TradeSkillReagent2._scripts.OnClick(TradeSkillReagent2)
clock = clock + 5
TradeSkillReagent2._scripts.OnClick(TradeSkillReagent2)
eq(bsSel, 2, "two slow clicks are not a double-click")
dbl(2)
eq(bsSel, 3, "double-clicking the grinding stone opens its recipe")
eq(RS.dock.back._text:find("Back to Patterned Bronze Bracers", 1, true) ~= nil, true, "with a way back")
dbl(1)
eq(bsSel, 3, "coarse stone has no recipe here: the recipe stays")
eq(RS.panel._shown, true, "and the where-to-get-it panel opens")
eq(RS.panel.body._text:find("Tin Veins", 1, true) ~= nil, true, "saying it is mined from tin veins")
click("Wowhead", RS.panel)
click("Back to Patterned Bronze Bracers", RS.dock)
eq(bsSel, 2, "back returns to the bracers")
eq(#RS.trail, 0, "and the trail is empty again")
DB.settings.reagentHelp = false
dbl(2)
eq(bsSel, 2, "switched off, double-click does nothing")
DB.settings.reagentHelp = true

-- the same in the modern profession window (the Forever client's)
do
	local NAMES = { [2672] = "Patterned Bronze Bracers", [2841] = "Bronze Bar", [3478] = "Coarse Grinding Stone", [2836] = "Coarse Stone" }
	C_Item = { GetItemNameByID = function(id) return NAMES[id] end }
	local RECIPES = {
		[101] = { name = "Patterned Bronze Bracers", out = 2672, slots = { { 2841, 5 }, { 3478, 2 } } },
		[102] = { name = "Coarse Grinding Stone", out = 3478, slots = { { 2836, 2 } } },
	}
	local function schem(id)
		local r = RECIPES[id]
		if not r then return nil end
		local list = {}
		for i, sl in ipairs(r.slots) do list[i] = { required = true, quantityRequired = sl[2], reagents = { { itemID = sl[1] } } } end
		return { name = r.name, outputItemID = r.out, quantityMin = 1, reagentSlotSchematics = list }
	end
	C_TradeSkillUI.GetAllRecipeIDs = function() return { 101, 102 } end
	C_TradeSkillUI.GetRecipeSchematic = function(id) return schem(id) end
	C_TradeSkillUI.GetRecipeInfo = function(id) return RECIPES[id] and { recipeID = id, name = RECIPES[id].name, learned = true } end
	local cur = 101
	C_TradeSkillUI.OpenRecipe = function(id) cur = id end
	ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
	local page = CreateFrame("Frame", nil, ProfessionsFrame)
	ProfessionsFrame.CraftingPage = page
	local fm = CreateFrame("Frame", nil, page)
	page.SchematicForm = fm
	local selected = 0
	page.SelectRecipe = function(_, info) selected = selected + 1; cur = info.recipeID; fm:Init() end
	local slots = {}
	local resets = 0
	-- like the game: each time a recipe is laid out, the material buttons get fresh handlers
	fm.Init = function()
		for _, slot in ipairs(slots) do
			resets = resets + 1
			slot.Button:SetScript("OnMouseDown", function() end)
			slot.Button:SetScript("OnEnter", function() end)
		end
	end
	fm.GetRecipeInfo = function() return C_TradeSkillUI.GetRecipeInfo(cur) end
	local mouseOn
	for i = 1, 2 do
		local slot = CreateFrame("Frame", nil, fm)
		slot.Button = CreateFrame("Button", nil, slot)
		slot.Button.IsMouseOver = function(b) return mouseOn == b end
		slot.GetReagentSlotSchematic = function() local sc = schem(cur); return sc and sc.reagentSlotSchematics[i] end
		slots[i] = slot
	end
	fm.GetSlots = function() return slots end
	fire("ADDON_LOADED", "Blizzard_Professions")
	local MS = ns.Reagents.state.modern
	eq(MS.hooked, true, "modern profession window hooked when it loads")
	fm:Init()
	eq(MS.dock._shown, true, "modern: craft-first advice shown")
	eq(MS.dock.plan._text:find("Craft first: 2x Coarse Grinding Stone", 1, true) ~= nil, true, "modern: grinding stone first")
	local MF = ns.Reagents.mouseFrame
	eq(ns.Reagents.globalClicks, true, "clicks come from the game's mouse event")
	local function press(i, which)
		mouseOn = slots[i].Button
		MF._scripts.OnEvent(MF, "GLOBAL_MOUSE_DOWN", which or "LeftButton")
		mouseOn = nil
	end
	local function mdbl(i) press(i); clock = clock + 0.2; press(i) end
	clock = clock + 5
	press(2, "RightButton"); clock = clock + 0.1; press(2, "RightButton")
	eq(cur, 101, "modern: right clicks do nothing")
	mdbl(2)
	eq(cur, 102, "modern: double-clicking the grinding stone opens its recipe")
	eq(selected, 1, "picked in the open window, not by reopening it")
	eq(MS.dock.back._text:find("Back to Patterned Bronze Bracers", 1, true) ~= nil, true, "modern: with a way back")
	clock = clock + 5
	mdbl(1)
	eq(cur, 102, "modern: coarse stone has no recipe, so the recipe stays")
	eq(MS.panel._shown, true, "modern: where-to-get-it panel opens")
	eq(MS.panel.body._text:find("Tin Veins", 1, true) ~= nil, true, "modern: mined from tin veins")
	click("Back to Patterned Bronze Bracers", MS.dock)
	eq(cur, 101, "modern: back returns to the bracers")
	-- again and again, as you move between recipes (the bug: it only worked the first time)
	eq(resets > 0, true, "the stand-in window reset its button handlers")
	for round = 1, 3 do
		clock = clock + 5
		mdbl(2)
		eq(cur, 102, "round " .. round .. ": grinding stone recipe opens")
		clock = clock + 5
		click("Back to Patterned Bronze Bracers", MS.dock)
		eq(cur, 101, "round " .. round .. ": back to the bracers")
	end
	press(1); clock = clock + 5; press(1)
	eq(cur, 101, "two presses far apart are not a double-click")
	press(1); clock = clock + 0.1; mouseOn = slots[2].Button; MF._scripts.OnEvent(MF, "GLOBAL_MOUSE_DOWN", "LeftButton"); mouseOn = nil
	eq(cur, 101, "one press on each of two materials is not a double-click")
	ProfessionsFrame:Hide()
	clock = clock + 5
	mdbl(2)
	eq(cur, 101, "nothing happens while the window is closed")
	ProfessionsFrame:Show()

	-- the fallback for clients without the mouse event: hooks are made again after a reset
	ns.Reagents.globalClicks = false
	fm:Init()
	clock = clock + 5
	local b = slots[2].Button
	b._scripts.OnMouseDown(b, "LeftButton"); clock = clock + 0.2; b._scripts.OnMouseDown(b, "LeftButton")
	eq(cur, 102, "fallback: hooked again after the game replaced the handler")
	click("Back to Patterned Bronze Bracers", MS.dock)
	fm:Init()
	clock = clock + 5
	b._scripts.OnMouseDown(b, "LeftButton"); clock = clock + 0.2; b._scripts.OnMouseDown(b, "LeftButton")
	eq(cur, 102, "fallback: and again after the next reset")
	click("Back to Patterned Bronze Bracers", MS.dock)
	ns.Reagents.globalClicks = true

	local status = table.concat(ns.Reagents.Status(), " | ")
	eq(status:find("ProfessionsFrame: present, hooked", 1, true) ~= nil, true, "/crm reagents check reports the hook")
	C_Item = nil
end

-- bag offers: from the quick-post bar straight to a bag, then into the chat box unsent
do
	local list = MastercraftDB.recipes["Player-1"].Tailoring.list
	local n0 = #list
	list[#list + 1] = { id = 6686, name = "Red Linen Bag", category = "Bags", learned = true, output = 5762, outputQty = 1,
		reagents = { { itemID = 2996, qty = 4 }, { itemID = 2320, qty = 1 }, { itemID = 2604, qty = 1 } } }
	list[#list + 1] = { id = 2963, name = "Bolt of Linen Cloth", category = "Materials", learned = true, output = 2996, outputQty = 1,
		reagents = { { itemID = 2589, qty = 2 } } }
	local NAMES = { [5762] = "Red Linen Bag", [2996] = "Bolt of Linen Cloth", [2320] = "Coarse Thread", [2604] = "Red Dye", [2589] = "Linen Cloth" }
	local SELL = { [2320] = 2, [2604] = 12 }
	function GetItemInfo(id)
		local nm = NAMES[id]
		if nm then return nm, ilink(id, nm), 1, 1, 1, "", "", 1, "", 1, SELL[id] or 0 end
	end
	-- a vendor window: what it charges for Coarse Thread is remembered
	function GetMerchantNumItems() return 1 end
	function GetMerchantItemLink() return ilink(2320, "Coarse Thread") end
	function GetMerchantItemInfo() return "Coarse Thread", nil, 10, 1 end
	fire("MERCHANT_SHOW")
	eq(DB.db.vendorPrices[2320], 10, "vendor price remembered")
	function UnitExists() return true end
	function UnitLevel() return 12 end

	if not DB.settings.barShown then UI.ToggleBar() end
	DB.settings.productsView = "catalog"
	UI.Show("Dashboard")
	click("Products", barRoot)
	eq(DB.settings.productsView, "offers", "the bar's Products button opens the bag offers")
	local prod = UI.tabs.Products.panel
	local offer
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item.name == "Red Linen Bag" and w.item.bring and inside(w, prod) and w._shown then offer = w end
	end
	eq(offer ~= nil, true, "Red Linen Bag offered")
	eq(offer.item.bring[1].qty, 8, "4 bolts asked for as 8 Linen Cloth")
	eq(offer.item.vendorCost, 58, "10c thread as seen at the vendor, dye estimated at 4 x 12c")
	eq(offer.item.fee, 100, "58c and a 20% tip, rounded up to 1s")
	eq(offer.item.fits, true, "suits the level 12 player targeted")
	local before, sentBefore = #opened, #sent
	offer._scripts.OnClick(offer)
	click("Post to chat box", prod)
	eq(#opened, before + 1, "the offer is placed in the chat box")
	local line = opened[#opened]
	eq(line:sub(1, 1) ~= "/", true, "no channel forced: it goes where the chat box is set")
	eq(line:find("8 Linen Cloth", 1, true) ~= nil, true, "asks for the raw cloth")
	eq(line:find("|Hitem:5762", 1, true) ~= nil, true, "links the bag")
	eq(#sent, sentBefore, "nothing sent by the add-on")
	eq(DB.R.tracking.offer, "Red Linen Bag", "tracking knows what was offered")
	fire("CHAT_MSG_WHISPER", "ooh how much for the bag", "Questy")
	local got
	for _, l in ipairs(DB.R.leads) do if l.contact == "Questy-Stormrage" then got = l end end
	eq(got and got.offer, "Red Linen Bag", "the reply is a lead tagged with the bag")

	WoWCRMFrame:Hide()
	click("Open WoW CRM", barRoot)
	eq(WoWCRMFrame._shown, true, "the bar opens the window")
	eq(UI.tabs.Products.panel._shown, true, "on the page last open")
	click("All recipes", prod)
	eq(DB.settings.productsView, "catalog", "back to the full recipe list")

	for i = #list, n0 + 1, -1 do list[i] = nil end
	GetItemInfo, GetMerchantNumItems, GetMerchantItemLink, GetMerchantItemInfo, UnitExists, UnitLevel = nil, nil, nil, nil, nil, nil
end

-- the Leads tab sorts leads by what the post was for
do
	clock = math.floor(clock) + 1
	local post = M.SavePost(nil, "LFG tank", "Tank LFG, whisper me", { SAY = true }, M.me, "group")
	M.RecordSend(post, "SAY", U.Now(), "Barrens")
	fire("CHAT_MSG_WHISPER", "need a tank for SFK?", "Groupy")
	UI.Show("Leads")
	local leadsPanel = UI.tabs.Leads.panel
	local function btn(prefix)
		for _, w in ipairs(widgets) do
			if w._scripts.OnClick and w._text:sub(1, #prefix) == prefix and inside(w, leadsPanel) then return w end
		end
	end
	eq(btn("Group (") ~= nil, true, "a filter button per purpose, with a count")
	btn("Group (")._scripts.OnClick(btn("Group ("))
	local shown = {}
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item.contact and w._shown and inside(w, leadsPanel) then shown[#shown + 1] = w.item end
	end
	eq(#shown, 1, "only the group lead is listed")
	eq(shown[1].contact, "Groupy-Stormrage", "the player who answered the group post")
	btn("All (")._scripts.OnClick(btn("All ("))
	local all = 0
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item.contact and w._shown and inside(w, leadsPanel) then all = all + 1 end
	end
	eq(all > 1, true, "All lists every open lead again")
end

-- Opty: write down what someone needs (an alt too), work it, win it into an order
do
	UI.Show("Opty")
	local pipe = UI.tabs.Opty.panel
	local edits = kind("EditBox", pipe) -- for, qty, price, days, next step, request
	click("Me", pipe)
	eq(edits[1]:GetText(), "Seller", "Me fills in the character you are playing")
	edits[1]:SetText("skotor ironmark")
	edits[3]:SetText("50s")
	edits[4]:SetText("2")
	edits[6]:SetText("5 silver\nfor the repair bill")
	click("Save", pipe)
	local opp
	for _, o in ipairs(DB.R.opportunities) do if (o.need or ""):find("^5 silver") then opp = o end end
	eq(opp ~= nil, true, "opportunity saved")
	eq(opp.contact, "Skotor Ironmark-Stormrage", "a typed name becomes a contact")
	eq(opp.quote, 5000, "quote saved")
	eq(opp.due ~= nil and opp.due > clock, true, "follow-up date set")
	local row
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item == opp and w._shown and inside(w, pipe) then row = w end
	end
	eq(row ~= nil, true, "listed under Open")
	click("Won: make it an order", pipe)
	eq(opp.stage, "won", "won")
	local ord = M.GetOrder(opp.order)
	eq(ord and ord.quote, 5000, "order started at the quote")
	eq(UI.tabs.Orders.panel._shown, true, "and opened on the Orders tab")

	-- from the Leads tab
	UI.Show("Leads")
	local leadsPanel = UI.tabs.Leads.panel
	local leadRow
	for _, w in ipairs(widgets) do
		if type(w.item) == "table" and w.item.contact and w.item.status == "open" and w._shown and inside(w, leadsPanel) then leadRow = w end
	end
	leadRow._scripts.OnClick(leadRow)
	click("Opportunity", leadsPanel)
	eq(UI.tabs.Opty.panel._shown, true, "a lead opens as an opportunity")
	local fromLead
	for _, o in ipairs(DB.R.opportunities) do if o.lead == leadRow.item.id then fromLead = o end end
	eq(fromLead ~= nil, true, "with the lead remembered")
	local convoShown = false
	for _, w in ipairs(widgets) do
		if w._kind == "FontString" and inside(w, UI.tabs.Opty.panel) and w._text:find(leadRow.item.text or "~none~", 1, true) then convoShown = true end
	end
	eq(convoShown, true, "the lead's whispers are shown on the Opty")

	-- from a contact
	UI.Show("Contacts", "Skotor Ironmark-Stormrage")
	click("+ Opportunity", UI.tabs.Contacts.panel)
	eq(kind("EditBox", UI.tabs.Opty.panel)[1]:GetText(), "Skotor Ironmark", "a contact starts an opportunity for them")
end

-- trades and an open Opty: their mats are logged on it, handing over the bag logs the order
do
	npcName, npcSecond = "Mia", nil
	local opp = M.SaveOpportunity(nil, { contact = "Mia-Stormrage", need = "Red Mageweave Bag" }, clock)
	M.SetOpportunityItem(opp.id, { name = "Red Mageweave Bag" }, 1, clock)
	local orders = #DB.R.orders
	doTrade(nil, { "Mageweave Cloth", 5 }, 0)
	eq(#DB.R.orders, orders, "a trade of mats for the Opty is not an order yet")
	eq(opp.mats and opp.mats[1].qty, 5, "the mats are logged on the Opty")
	eq(opp.stage, "working", "and it is under way")
	doTrade({ "Red Mageweave Bag", 1 }, nil, 8900)
	eq(#DB.R.orders, orders + 1, "handing over the bag logs the order")
	local ord = DB.R.orders[#DB.R.orders]
	eq(ord.opportunity, opp.id, "from the Opty")
	eq(ord.received[1].name, "Mageweave Cloth", "with their mats as supplied")
	eq(ord.received[1].kind, "mats", "as materials, not payment")
	eq(ord.price, 8900, "and the gold they paid")
	eq(ord.status, "paid", "delivered and paid")
	local _, planned = M.ItemCounts(ord)
	eq(planned, 0, "the bag is handed over")
	eq(opp.stage, "won", "the Opty is won")
	npcName, npcSecond = "Buyer", nil
end

-- the job sheet on the Opty screen
do
	local opp = M.SaveOpportunity(nil, { contact = "Buyer-Stormrage", need = "two bags" }, clock)
	M.SetOpportunityItem(opp.id, { key = "Tailoring|Runecloth Bag", name = "Runecloth Bag", output = 14046 }, 2, clock)
	UI.Show("Opty", opp.id)
	local sheet
	for _, w in ipairs(widgets) do
		if w._kind == "FontString" and inside(w, UI.tabs.Opty.panel) and w._text:find("Their price now", 1, true) then sheet = w._text end
	end
	eq(sheet ~= nil, true, "the job sheet is shown")
	eq(sheet:find("2x Runecloth Bag", 1, true) ~= nil, true, "for two bags")
	eq(sheet:find("10 item 14048", 1, true) ~= nil or sheet:find("10 ", 1, true) ~= nil, true, "with the mats for two")
	click("Use this price", UI.tabs.Opty.panel)
	eq(kind("EditBox", UI.tabs.Opty.panel)[3]:GetText() ~= "", true, "Use this price fills in the price")
	M.DeleteOpportunity(opp.id)
end

-- values the game hides from add-ons, and events this client does not have, cause no errors
do
	speed = SECRET
	clock = clock + 5
	local ok, err = pcall(ns.eventFrame._scripts.OnUpdate, ns.eventFrame, 3)
	eq(ok, true, "a hidden movement speed is ignored, not compared: " .. tostring(err))
	speed = 0
	eq(U.Plain(SECRET), nil, "a hidden value reads as unknown")
	eq(U.Plain(12), 12, "a plain number reads as itself")
	local real = ns.eventFrame.RegisterEvent
	ns.eventFrame.RegisterEvent = function(_, e) if e == "NOT_ON_THIS_CLIENT" then error("Attempt to register unknown event") end end
	ok = pcall(ns.On, "NOT_ON_THIS_CLIENT", function() end)
	ns.eventFrame.RegisterEvent = real
	eq(ok, true, "an event this client does not have is skipped")
end

-- the add-on must not leak names into the game's shared global space
local allowed = {
	WoWCRMDB = true, WoWCRMFrame = true, WoWCRMSaveButton = true, WoWCRM_OnCompartmentClick = true,
	SLASH_WOWCRM1 = true, SLASH_WOWCRM2 = true,
	WoWCRMScanTooltip = true, -- hidden tooltip used to read bag sizes
	WoWCRMMinimapButton = true,
	TradeSkillFrame = true, ProfessionsFrame = true, -- the stand-in profession windows made by this test
}
for i = 1, 8 do allowed["TradeSkillReagent" .. i] = true end
for k in pairs(_G) do
	if not globalsBefore[k] and not allowed[k] then error("unexpected global: " .. tostring(k)) end
end
count = count + 1

print(("test_smoke: %d checks passed (%d confirmation prompts)"):format(count, popups))
