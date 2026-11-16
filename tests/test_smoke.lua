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
function methods:HasFocus() return false end
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
local tells = {}
function ChatFrame_SendTell(name) tells[#tells + 1] = name end
function MailFrameTab_OnClick() end
function SendMail() end
function GetSendMailCOD() return 70000 end
function GetSendMailItem(i) if i == 1 then return "Runed Rod", 1, nil, 2 end end
function GetSendMailItemLink(i) if i == 1 then return "|cffffffff|Hitem:1::::::::|h[Runed Rod]|h|r" end end
LE_GAME_ERR_TRADE_COMPLETE = 77
function GetTargetTradeMoney() return 50000 end
function GetTradePlayerItemLink(i) if i == 1 then return "|cffffffff|Hitem:2::::::::|h[Mana Oil]|h|r" end end
function GetTradePlayerItemInfo(i) if i == 1 then return "Mana Oil", nil, 3 end end

-- ---------------------------------------------------------------- load the add-on in TOC order
local ns, files = {}, {}
for line in TOC_TEXT:gmatch("[^\r\n]+") do
	line = line:gsub("%s+$", "")
	if line ~= "" and not line:match("^#") then files[#files + 1] = line end
end
assert(#files == 8, "TOC should list 8 files, found " .. #files)
local globalsBefore = {}
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
local oe = kind("EditBox", orders)
eq(#oe, 5, "order form fields")
eq(oe[1]._text, "Ann", "contact carried over from the lead")
oe[2]:SetText("Weapon enchant")
oe[4]:SetText("banana")
click("Mark paid", orders)
eq(#DB.R.orders, 0, "bad price refused")
oe[4]:SetText("12g 50s")
click("Mark paid", orders)
eq(#DB.R.orders, 1, "order saved")
eq(M.LTV("Ann-Stormrage"), 125000, "lifetime value from the paid order")
eq(DB.R.leads[1].status, "won", "lead closed by the order")
eq(M.GetContact("Ann-Stormrage").status, "customer", "lead promoted to customer")

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

-- a completed trade offers an order
local before = #DB.R.orders
fire("TRADE_SHOW")
fire("TRADE_ACCEPT_UPDATE", 1, 1)
fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, "Trade complete.")
eq(#DB.R.orders, before + 1, "trade recorded after confirming")
local o = DB.R.orders[#DB.R.orders]
eq(o.contact, "Buyer-Stormrage", "trade partner")
eq(o.desc, "3x Mana Oil", "items described")
eq(o.price, 50000, "gold received")
eq(o.status, "paid", "trade with gold is paid")
fire("UI_INFO_MESSAGE", LE_GAME_ERR_TRADE_COMPLETE, "Trade complete.")
eq(#DB.R.orders, before + 1, "the same trade is not recorded twice")

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
eq(#DB.R.orders, before + 1, "cash-on-delivery mail recorded after confirming")
eq(DB.R.orders[#DB.R.orders].status, "delivered", "COD is delivered, not yet paid")
eq(DB.R.orders[#DB.R.orders].contact, "Ann-Stormrage", "COD order on the right contact")
fire("MAIL_CLOSED")

-- dashboard, bar, probe
UI.Show("Dashboard")
local dash = UI.tabs.Dashboard.panel
click("Export", dash)
eq(kind("EditBox", dash)[5]._text:sub(1, 7), "WOWCRM1", "export produced")
click("Apply settings", dash)
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
local saved = WoWCRMDB
DB.Init(saved, "Stormrage")
eq(#DB.R.posts, 1, "posts survive a reload")
eq(DB.R.tracking.on, true, "tracking survives a reload")

-- the add-on must not leak names into the game's shared global space
local allowed = {
	WoWCRMDB = true, WoWCRMFrame = true, WoWCRMSaveButton = true, WoWCRM_OnCompartmentClick = true,
	SLASH_WOWCRM1 = true, SLASH_WOWCRM2 = true,
}
for k in pairs(_G) do
	if not globalsBefore[k] and not allowed[k] then error("unexpected global: " .. tostring(k)) end
end
count = count + 1

print(("test_smoke: %d checks passed (%d confirmation prompts)"):format(count, popups))
