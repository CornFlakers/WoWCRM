-- Saved data: shape, defaults and migrations. No game API in this file.
local _, ns = ...
local DB = {}
ns.DB = DB

DB.VERSION = 1

local DEFAULTS = {
	minGap = 60,          -- seconds between two sends to the same public channel
	trackAutoOff = 30,    -- minutes after the last post before tracking switches itself off (0 = never)
	saveReminder = true,  -- show the "Save changes" button
	promptStrangers = true, -- offer to record a sale to someone who is not yet a contact
	generalName = "General",
	tradeName = "Trade",
}
DB.MIN_GAP_FLOOR = 30

-- MIGRATIONS[n] upgrades data from version n to n + 1.
local MIGRATIONS = {}

local LISTS = { "posts", "leads", "orders", "postLog", "mailLog", "mailTemplates" }

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
	if saved.settings.minGap < DB.MIN_GAP_FLOOR then saved.settings.minGap = DB.MIN_GAP_FLOOR end

	saved.realms = saved.realms or {}
	local R = saved.realms[realm] or {}
	saved.realms[realm] = R
	for _, k in ipairs(LISTS) do R[k] = R[k] or {} end
	R.contacts = R.contacts or {}
	R.lastSent = R.lastSent or {}
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

	DB.db, DB.R, DB.realm, DB.settings = saved, R, realm, saved.settings
	return saved
end

function DB.WipeRealm()
	DB.db.realms[DB.realm] = nil
	return DB.Init(DB.db, DB.realm)
end
