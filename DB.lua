-- Saved data: shape, defaults and migrations. No game API in this file.
local _, ns = ...
local DB = {}
ns.DB = DB

DB.VERSION = 2

local DEFAULTS = {
	minGap = 60,          -- seconds between two sends to the same public channel
	trackAutoOff = 30,    -- minutes after the last post before tracking switches itself off (0 = never)
	autoTrack = true,     -- posting from WoW CRM switches contact tracking on
	heldFree = true,      -- materials already held count as costing nothing
	barChannel = "TRADE", -- the channel picked on the quick-post bar
	publicSpacing = 2,    -- minutes between any two posts to Say, Yell, General or Trade (0 = off)
	quoteSmaller = true,  -- offer the next smaller, cheaper bag in a quote
	quoteText = "Hi {name}! {item} is {price} with my mats.",
	quoteAlt = "I can also do {alt} for {altprice}.",
	windowScale = 100,    -- size of the main window, percent
	showMinimap = true,
	minimapAngle = 200,
	saveReminder = true,  -- offer a backup at quiet moments
	saveAfterChanges = 25, -- ...once this many changes are waiting
	saveAfterMinutes = 30, -- ...or the oldest waiting change is this old
	promptStrangers = true, -- offer to record a sale to someone who is not yet a contact
	campaignMinutes = 60, -- usual length of a campaign
	postInterval = 5,     -- usual minutes between posts to the same channel during a campaign
	campaignSound = true, -- sound when the next campaign post is due
	outreachGap = 3,      -- days before someone you already wrote to comes back to the top of the follow-up list
	orderWindow = 60,     -- minutes during which a follow-up trade is offered as part of the same order
	generalName = "General",
	tradeName = "Trade",
	reagentHelp = true,   -- double-click a material in the profession window: its recipe, or where to get it
	productsView = "catalog", -- the Products tab shows the full recipe list ("catalog") or the bag offers ("offers")
	offerText = "",       -- the bag offer line; empty uses the built-in wording (ns.Offers.DEFAULT_TEXT)
	offerTip = 20,        -- percent added on top of thread and dye in a bag offer
}
DB.MIN_GAP_FLOOR = 30

-- MIGRATIONS[n] upgrades data from version n to n + 1.
local MIGRATIONS = {}

-- 1 -> 2: an order's single description becomes a list of items given and a list of things received.
MIGRATIONS[1] = function(saved)
	for _, R in pairs(saved.realms or {}) do
		for _, o in ipairs(R.orders or {}) do
			if not o.items then
				o.items = { { name = o.desc or "item", link = o.link, qty = o.qty or 1 } }
				o.received = {}
				o.desc, o.qty, o.link = "", nil, nil
			end
		end
	end
end

local LISTS = { "posts", "leads", "orders", "postLog", "mailLog", "mailTemplates", "campaigns" }

-- Which realm's data to use. The game can give a blank realm name (it did after a client
-- update), and a blank name would open an empty book. So: the first name given that is not
-- blank, else the realm used last time, else the only realm on file, else "Unknown".
function DB.ResolveRealm(saved, ...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" then
			v = v:gsub("[%s%-]", "")
			if v ~= "" then return v end
		end
	end
	if type(saved) == "table" then
		if type(saved.lastRealm) == "string" and saved.lastRealm ~= "" then return saved.lastRealm end
		local only, n = nil, 0
		for k in pairs(type(saved.realms) == "table" and saved.realms or {}) do
			if k ~= "" then only, n = k, n + 1 end
		end
		if n == 1 then return only end
	end
	return "Unknown"
end

-- Anything a person made: posts, contacts, leads, orders or campaigns.
function DB.HasUserData(R)
	if type(R) ~= "table" then return false end
	for _, k in ipairs({ "posts", "leads", "orders", "campaigns" }) do
		if type(R[k]) == "table" and #R[k] > 0 then return true end
	end
	return type(R.contacts) == "table" and next(R.contacts) ~= nil
end

function DB.Init(saved, realm)
	saved = type(saved) == "table" and saved or {}
	saved.version = saved.version or DB.VERSION
	while saved.version < DB.VERSION do
		local step = MIGRATIONS[saved.version]
		if step then step(saved) end
		saved.version = saved.version + 1
	end

	saved.settings = saved.settings or {}
	for k, v in pairs(DEFAULTS) do
		if saved.settings[k] == nil then saved.settings[k] = v end
	end
	if type(saved.settings.invSources) ~= "table" then saved.settings.invSources = { bags = true } end
	if type(saved.settings.cycleChannels) ~= "table" then saved.settings.cycleChannels = { GENERAL = true, TRADE = true } end
	if saved.settings.minGap < DB.MIN_GAP_FLOOR then saved.settings.minGap = DB.MIN_GAP_FLOOR end

	-- What vendors charge for things (thread, dye), learned whenever a vendor window is open.
	-- Kept for the whole account: vendor prices are the same on every realm.
	if type(saved.vendorPrices) ~= "table" then saved.vendorPrices = {} end

	saved.realms = saved.realms or {}
	-- A book opened under a blank realm name: dropped when empty, set aside when not, so it
	-- never hides the real one again.
	DB.setAside = nil
	if realm ~= "" and saved.realms[""] then
		if DB.HasUserData(saved.realms[""]) then
			local key = "Recovered (blank realm name)"
			saved.realms[key] = saved.realms[key] or saved.realms[""]
			DB.setAside = key
		end
		saved.realms[""] = nil
	end
	if realm ~= "" and realm ~= "Unknown" then saved.lastRealm = realm end
	local R = saved.realms[realm] or {}
	saved.realms[realm] = R
	for _, k in ipairs(LISTS) do R[k] = R[k] or {} end
	R.contacts = R.contacts or {}
	R.lastSent = R.lastSent or {}
	R.products = R.products or {}
	R.recipeSources = R.recipeSources or {}
	R.sendHours = R.sendHours or {}
	R.tracking = R.tracking or { on = false }
	R.nextId = R.nextId or 1

	if not R.seeded then
		R.seeded = true
		R.mailTemplates[#R.mailTemplates + 1] = {
			id = R.nextId, name = "Order ready",
			subject = "Your order is ready",
			body = "Hi {name},\n\nYour {item} is ready. Total: {total}.\n\nThanks!\n{me}",
		}
		R.mailTemplates[#R.mailTemplates + 1] = {
			id = R.nextId + 1, name = "Thank you",
			subject = "Thanks for your order",
			body = "Hi {name},\n\nThanks for buying from me. Whisper me any time you need more.\n\n{me}",
		}
		R.nextId = R.nextId + 2
	end

	-- Follow-up letters, written to remind and invite rather than to chase.
	if not R.seededFollowUps then
		R.seededFollowUps = true
		local function add(name, subject, body)
			R.mailTemplates[#R.mailTemplates + 1] = { id = R.nextId, name = name, subject = subject, body = body }
			R.nextId = R.nextId + 1
		end
		add("Follow-up: still available", "Still crafting if you need anything",
			"Hi {name},\n\nYou asked me about some crafting a little while ago. No rush at all - I just wanted you to know I'm still around and happy to make whatever you need. Bring your own materials or I can supply them.\n\nWhisper me whenever you see me on, or reply to this letter.\n\n{me}")
		add("Follow-up: taking orders", "Taking orders this week",
			"Hi {name},\n\nI have time for a few more crafting orders this week. If there is something you have been meaning to get made, reply to this letter with what you need and I will have it ready for you.\n\n{me}")
		add("Follow-up: past customer", "Thanks again",
			"Hi {name},\n\nThanks again for the {item} order. If you or a friend need anything else made, I'm always glad to help - just whisper me or reply here.\n\n{me}")
	end

	DB.db, DB.R, DB.realm, DB.settings = saved, R, realm, saved.settings
	return saved
end

function DB.WipeRealm()
	DB.db.realms[DB.realm] = nil
	return DB.Init(DB.db, DB.realm)
end
