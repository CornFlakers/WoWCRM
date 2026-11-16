-- Tests for the files that hold no game API: Util, DB, Model.
local ns = {}
for _, f in ipairs({ "Util.lua", "DB.lua", "Model.lua" }) do
	assert(loadfile(f))("WoWCRM", ns)
end
local U, DB, M = ns.Util, ns.DB, ns.Model

local count = 0
local function eq(got, want, what)
	count = count + 1
	if got ~= want then
		error(("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)), 2)
	end
end
local function fresh() DB.Init({}, "Stormrage"); M.cursor = {} end
local ALL = function() return true end

-- names
eq(U.NormName("bob", "Stormrage", true), "Bob-Stormrage", "tidy plain name")
eq(U.NormName("Bob-Area 52", "Stormrage"), "Bob-Area52", "realm spaces removed")
eq(U.NormName("  ", "Stormrage"), nil, "empty name")
eq(U.NormName("\195\137lise", "Stormrage", true), "\195\137lise-Stormrage", "accented name left alone")
eq(U.Display("Bob-Stormrage", "Stormrage"), "Bob", "same realm display")
eq(U.Display("Bob-Area52", "Stormrage"), "Bob-Area52", "other realm display")

-- bytes, not letters
eq(U.ByteLen(("a"):rep(255)), 255, "ascii bytes")
eq(U.ByteLen(("\195\169"):rep(128)), 256, "128 accented letters are 256 bytes")

-- money
eq(U.ParseMoney("12g 50s"), 125000, "12g 50s")
eq(U.ParseMoney("12.5g"), 125000, "12.5g")
eq(U.ParseMoney("1,200g"), 12000000, "thousands separator")
eq(U.ParseMoney("30s 5c"), 3005, "30s 5c")
eq(U.ParseMoney("15"), 150000, "bare number is gold")
eq(U.ParseMoney(""), 0, "empty is zero")
eq(U.ParseMoney("lots"), nil, "nonsense rejected")
eq(U.ParseMoney("12g banana"), nil, "trailing junk rejected")
eq(U.FormatMoney(125003), "12g 50s 3c", "format")
eq(U.FormatMoney(0), "0c", "format zero")
eq(U.Fill("Hi {name}, {unknown}", { name = "Bob" }), "Hi Bob, {unknown}", "tokens")

-- export escaping
local nasty = "a\tb\nc\\d"
eq(U.SplitTabs(U.Escape(nasty) .. "\t\tend")[1], nasty, "escape round trip")
eq(#U.SplitTabs("a\t\tc"), 3, "empty fields kept")

-- posts
fresh()
eq(DB.settings.minGap, 60, "default gap")
eq(#DB.R.mailTemplates, 2, "seeded templates")
local _, err = M.SavePost(nil, "", "x", { SAY = true })
eq(err ~= nil, true, "name required")
_, err = M.SavePost(nil, "Long", ("a"):rep(256), { SAY = true })
eq(err ~= nil, true, "256 bytes rejected")
_, err = M.SavePost(nil, "Accents", ("\195\169"):rep(128), { SAY = true })
eq(err ~= nil, true, "128 two-byte letters rejected")
_, err = M.SavePost(nil, "None", "hi", {})
eq(err ~= nil, true, "needs a channel")
local post = M.SavePost(nil, "Enchants", ("a"):rep(255), { SAY = true, TRADE = true, GUILD = true })
eq(post ~= nil, true, "255 bytes accepted")
eq(M.SavePost(post.id, "Enchants v2", "WTS enchants", { SAY = true, TRADE = true, GUILD = true }).id, post.id, "edit keeps id")
eq(#DB.R.posts, 1, "edit does not duplicate")

-- rotation and gaps
local T = 1000
eq(M.NextTarget(post, ALL, T), "SAY", "first target")
M.RecordSend(post, "SAY", T, "City")
eq(M.NextTarget(post, ALL, T), "TRADE", "second target")
M.RecordSend(post, "TRADE", T, "City")
eq(M.NextTarget(post, ALL, T), "GUILD", "third target")
M.RecordSend(post, "GUILD", T, "City")
local nxt, why = M.NextTarget(post, ALL, T + 10)
eq(nxt, "GUILD", "guild has only a short gap")
M.RecordSend(post, "GUILD", T + 10, "City")
nxt, why = M.NextTarget(post, ALL, T + 10)
eq(nxt, nil, "everything inside its gap")
eq(why ~= nil, true, "reason given")
eq(M.GapRemaining("SAY", T + 20), 40, "gap countdown")
eq(M.NextTarget(post, ALL, T + 61), "SAY", "say free after gap")
eq(M.NextTarget(post, function(t) return t ~= "SAY", "nope" end, T + 61), "TRADE", "skips unavailable")
eq(#DB.R.postLog, 4, "sends logged")

-- tracking and leads
fresh()
post = M.SavePost(nil, "Enchants", "WTS enchants", { SAY = true })
eq(M.OnWhisper("Ann-Stormrage", "how much?", T), nil, "tracking off: nothing captured")
M.SetTracking(true, T)
local on, capturing = M.TrackingState(T)
eq(on, true, "tracking on")
eq(capturing, false, "not capturing before a post")
eq(M.OnWhisper("Ann-Stormrage", "how much?", T), nil, "on but no post yet: nothing captured")
M.RecordSend(post, "SAY", T + 5, "City")
local lead, isNew = M.OnWhisper("Ann-Stormrage", "how much?", T + 10)
eq(lead ~= nil and isNew, true, "whisper after post makes contact and lead")
eq(lead.post, post.id, "lead attributed to post")
eq(M.GetContact("Ann-Stormrage").sourcePost, post.id, "contact source post")
local lead2, isNew2 = M.OnWhisper("Ann-Stormrage", "still there?", T + 20)
eq(lead2.id, lead.id, "second whisper joins the open lead")
eq(lead2.count, 2, "message count")
eq(isNew2, false, "not a new contact twice")
eq(#DB.R.leads, 1, "one lead")

-- lead for an existing contact
M.EnsureContact("Old-Stormrage", T - 500).status = "customer"
local lead3, isNew3 = M.OnWhisper("Old-Stormrage", "another one please", T + 30)
eq(lead3 ~= nil and not isNew3, true, "existing contact gets a lead, not a new contact")
eq(M.GetContact("Old-Stormrage").status, "customer", "existing status kept")

-- ignored players
M.GetContact("Old-Stormrage").status = "ignored"
M.SetLeadStatus(lead3.id, "dismissed")
eq(M.OnWhisper("Old-Stormrage", "hello?", T + 40), nil, "ignored player not captured")

-- auto off
on = M.TrackingState(T + 5 + 31 * 60)
eq(on, false, "tracking turns itself off")
eq(M.OnWhisper("Late-Stormrage", "hi", T + 5 + 31 * 60), nil, "nothing captured after auto off")

-- switching on right after a post still attributes
fresh()
post = M.SavePost(nil, "P", "hello", { SAY = true })
M.RecordSend(post, "SAY", T, "City")
M.SetTracking(true, T + 60)
eq(select(2, M.TrackingState(T + 60)), true, "recent post adopted when switching on")
M.SetTracking(false, T + 70)
eq(M.OnWhisper("Ann-Stormrage", "hi", T + 80), nil, "off means off")

-- orders, lifetime value, automatic status
fresh()
post = M.SavePost(nil, "P", "hello", { SAY = true })
M.SetTracking(true, T)
M.RecordSend(post, "SAY", T, "City")
lead = M.OnWhisper("Ann-Stormrage", "one please", T + 1)
_, err = M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "", price = 1 }, T)
eq(err ~= nil, true, "description required")
_, err = M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "x", price = -5 }, T)
eq(err ~= nil, true, "negative price rejected")
local o1 = M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "Enchant", price = 500000, status = "quoted" }, T + 2)
eq(lead.status, "won", "order closes the open lead")
eq(M.LTV("Ann-Stormrage"), 0, "quoted order has no value yet")
eq(M.GetContact("Ann-Stormrage").status, "lead", "still a lead until paid")
M.SaveOrder(o1.id, { contact = "Ann-Stormrage", desc = "Enchant", price = 500000, status = "paid" }, T + 3)
eq(M.LTV("Ann-Stormrage"), 500000, "paid order counts")
eq(o1.paidAt, T + 3, "paid time recorded")
eq(M.GetContact("Ann-Stormrage").status, "customer", "lead becomes customer")
M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "Bag", price = 250000, status = "paid", type = "goods" }, T + 4)
eq(M.LTV("Ann-Stormrage"), 750000, "values add up")
eq(M.GetContact("Ann-Stormrage").status, "repeat", "customer becomes repeat")
M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "Cancelled thing", price = 990000, status = "cancelled" }, T + 5)
eq(M.LTV("Ann-Stormrage"), 750000, "cancelled order ignored")
M.GetContact("Ann-Stormrage").status = "vip"
M.SaveOrder(nil, { contact = "Ann-Stormrage", desc = "More", price = 1, status = "paid" }, T + 6)
eq(M.GetContact("Ann-Stormrage").status, "vip", "hand-set status is not overwritten")

-- referrals
M.SaveOrder(nil, { contact = "Ben-Stormrage", desc = "Carry", price = 1000000, status = "paid", type = "service" }, T + 7)
eq(M.GetContact("Ben-Stormrage") ~= nil, true, "order creates the contact")
eq(M.SetReferrer("Ben-Stormrage", "Ann-Stormrage"), true, "referrer set")
local n, rev = M.Referrals("Ann-Stormrage")
eq(n, 1, "referral count")
eq(rev, 1000000, "referral revenue")
_, err = M.SetReferrer("Ann-Stormrage", "Ann-Stormrage")
eq(err ~= nil, true, "no self referral")
_, err = M.SetReferrer("Ann-Stormrage", "Ben-Stormrage")
eq(err ~= nil, true, "no referral loop")
_, err = M.SetReferrer("Ann-Stormrage", "Nobody-Stormrage")
eq(err ~= nil, true, "referrer must exist")
eq(M.FindContact("ann").key, "Ann-Stormrage", "find by name ignoring case")

-- stats
local s = M.Stats()
eq(s.revenue, 1750001, "total revenue")
eq(s.customers, 2, "customers")
eq(s.top[1].key, "Ben-Stormrage", "top customer")
eq(s.referrers[1].key, "Ann-Stormrage", "top referrer")
eq(s.posts[1].leads, 1, "leads per post")
eq(s.posts[1].revenue, 750001, "revenue per post")

-- export and import into an empty realm
M.GetContact("Ann-Stormrage").notes = "likes\ttabs\nand newlines"
local dump = M.Export()
DB.Init({}, "Other")
local added, ierr = M.Import(dump, T + 100)
eq(ierr, nil, "import ok")
eq(added.contacts, 2, "contacts imported")
eq(added.orders, 5, "orders imported")
eq(added.posts, 1, "posts imported")
eq(M.LTV("Ann-Stormrage"), 750001, "value survives the round trip")
eq(M.GetContact("Ann-Stormrage").notes, "likes\ttabs\nand newlines", "notes survive the round trip")
eq(M.GetContact("Ann-Stormrage").status, "vip", "status survives the round trip")
eq(M.GetContact("Ben-Stormrage").referredBy, "Ann-Stormrage", "referral survives the round trip")
added = M.Import(dump, T + 200)
eq(added.orders, 0, "importing twice does not duplicate orders")
eq(added.contacts, 0, "importing twice does not duplicate contacts")
eq(M.Import("garbage", T) == nil, true, "bad import refused")

-- deleting a contact
M.DeleteContact("Ann-Stormrage")
eq(M.GetContact("Ben-Stormrage").referredBy, nil, "referral cleared on delete")
eq(M.LTV("Ann-Stormrage"), 0, "orders removed with contact")

-- settings floor and data surviving a reload
local saved = DB.Init({ settings = { minGap = 1 } }, "R")
eq(saved.settings.minGap, DB.MIN_GAP_FLOOR, "gap floor enforced")
M.SavePost(nil, "Keep", "me", { SAY = true })
M.SetTracking(true, T)
DB.Init(saved, "R")
eq(#DB.R.posts, 1, "data kept across re-init")
eq(DB.R.tracking.on, true, "tracking kept across a reload")

print(("test_logic: %d checks passed"):format(count))
