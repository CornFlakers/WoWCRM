-- Tests for the files that hold no game API: Util, DB, Model.
local ns = {}
for _, f in ipairs({ "Util.lua", "DB.lua", "Model.lua", "Catalog.lua", "Offers.lua", "Inventory.lua", "Sources.lua" }) do
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
-- The pause between any two public posts is switched off here; it has its own tests below.
M.me = "Me-Stormrage"
local function fresh() DB.Init({}, "Stormrage"); M.cursor = {}; DB.settings.publicSpacing = 0 end
local ALL = function() return true end

-- names
eq(U.NormName("bob", "Stormrage", true), "Bob-Stormrage", "tidy plain name")
eq(U.NormName("rosa vell", "Stormrage", true), "Rosa Vell-Stormrage", "every word of a typed name gets a capital")
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
eq(#DB.R.mailTemplates, 5, "seeded templates, including three follow-ups")
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
local lead3, newLead3, isNew3 = M.OnWhisper("Old-Stormrage", "another one please", T + 30)
eq(lead3 ~= nil and newLead3 and not isNew3, true, "existing contact gets a lead, not a new contact")
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

-- one job across three trades: materials in, bags out, tip afterwards
fresh()
post = M.SavePost(nil, "Bags", "LF mats, making bags", { SAY = true })
M.SetTracking(true, T)
M.RecordSend(post, "SAY", T, "City")
M.OnWhisper("Cat-Stormrage", "can you make bags?", T + 1)
local CAT = "Cat-Stormrage"
local job = M.AddTrade(nil, CAT, { received = { { name = "Silk Cloth", qty = 20, value = 500 } } }, T + 10)
eq(job.status, "in progress", "materials only: job in progress")
eq(job.received[1].kind, "mats", "goods before delivery are materials")
eq(M.OrderTitle(job), "Job in progress", "title before anything is delivered")
eq(M.GetContact(CAT).status, "lead", "still a lead before delivery")
eq(M.CurrentOrder(CAT, T + 20).id, job.id, "follow-up trade finds the order")
M.AddTrade(job.id, CAT, { given = { { name = "Silk Bag", qty = 2 } } }, T + 30)
eq(job.status, "delivered", "free job is delivered")
eq(M.GetContact(CAT).status, "customer", "a free job still makes a customer")
eq(M.LTV(CAT), 0, "free job has no value yet")
M.AddTrade(job.id, CAT, { received = { { name = "Mageweave Cloth", qty = 10, value = 4000 } }, gold = 10000 }, T + 40)
eq(job.status, "paid", "tip makes the job paid")
eq(job.received[2].kind, "payment", "goods after delivery are payment")
local total, npaid, nall, lgold, lgoods = M.LTV(CAT)
eq(total, 50000, "lifetime value is gold plus goods")
eq(lgold, 10000, "gold part")
eq(lgoods, 40000, "goods part")
local _, _, jmats = M.OrderValue(job)
eq(jmats, 10000, "materials valued but not counted as income")
eq(job.trades, 3, "three trades, one order")
eq(M.OrderTitle(job), "2x Silk Bag", "title from the items")
M.AddTrade(job.id, CAT, { given = { { name = "Silk Bag", qty = 1 } } }, T + 50)
eq(#job.items, 1, "same item merges into one line")
eq(job.items[1].qty, 3, "quantities add up")
eq(M.CurrentOrder(CAT, T + 50 + 61 * 60), nil, "after the window a trade starts a new order")

-- goods and payment in a single trade; gold on its own
local swap = M.AddTrade(nil, "Dan-Stormrage", { given = { { name = "Mageweave Bag", qty = 1 } }, received = { { name = "Rugged Leather", qty = 5, value = 1000 } } }, T)
eq(swap.status, "paid", "item swapped for goods is paid")
eq(swap.received[1].kind, "payment", "goods in the delivery trade are payment")
eq(M.LTV("Dan-Stormrage"), 5000, "paid in goods only")
local tip = M.AddTrade(nil, "Eve-Stormrage", { gold = 20000 }, T)
eq(tip.type, "service", "gold alone is a service")
eq(tip.status, "paid", "gold alone is paid")

-- what a post earned, split into gold and goods, and what it sold
s = M.Stats()
eq(s.gold, 30000, "gold income")
eq(s.goods, 45000, "goods income")
eq(s.mats, 10000, "materials supplied")
eq(s.revenue, 75000, "total income")
eq(s.posts[1].gold, 10000, "gold per post")
eq(s.posts[1].goods, 40000, "goods per post")
eq(s.posts[1].sold[1].name, "Silk Bag", "items sold per post")
eq(s.posts[1].sold[1].qty, 3, "quantity sold per post")

-- item lines survive export and import
dump = M.Export()
DB.Init({}, "Other2")
added = M.Import(dump, T + 100)
eq(added.orders, 3, "orders with lines imported")
total, npaid, nall, lgold, lgoods = M.LTV(CAT)
eq(lgold, 10000, "gold survives the round trip")
eq(lgoods, 40000, "goods survive the round trip")
eq(M.OrdersFor(CAT)[1].received[1].kind, "mats", "materials line survives the round trip")
eq(M.OrdersFor(CAT)[1].items[1].qty, 3, "item quantity survives the round trip")

-- text exported by the first version still imports
DB.Init({}, "Other3")
added = M.Import("WOWCRM1\nO\tZed-R\tgoods\tOld thing\t2\t30000\tpaid\t1000\t1000\t\t", T)
eq(added.orders, 1, "old export format accepted")
eq(M.OrdersFor("Zed-R")[1].items[1].name, "Old thing", "old description becomes an item")
eq(M.OrdersFor("Zed-R")[1].items[1].qty, 2, "old quantity kept")
eq(M.LTV("Zed-R"), 30000, "old price kept")

-- data saved by the first version is upgraded
local v1 = { version = 1, settings = {}, realms = { R1 = {
	orders = { { id = 1, contact = "A-R1", desc = "3x Mana Oil", qty = 1, price = 50000, status = "paid", created = T, type = "goods", notes = "" } },
	contacts = { ["A-R1"] = { key = "A-R1", status = "customer", tags = "", notes = "" } },
} } }
DB.Init(v1, "R1")
eq(v1.version, 2, "saved data upgraded")
eq(DB.R.orders[1].items[1].name, "3x Mana Oil", "old order keeps what was sold")
eq(M.LTV("A-R1"), 50000, "old order keeps its value")
eq(M.OrderTitle(DB.R.orders[1]), "3x Mana Oil", "old order still has a title")

-- follow-up outreach: who is next, how often, and when
fresh()
local DAY = 86400
M.EnsureContact("Lead1-Stormrage", T)
M.EnsureContact("Lead2-Stormrage", T)
M.EnsureContact("Cust-Stormrage", T).status = "customer"
M.EnsureContact("Quiet-Stormrage", T).status = "do not contact"
M.EnsureContact("Spam-Stormrage", T).status = "ignored"
eq(#M.FollowUps("leads", T), 2, "leads listed")
eq(#M.FollowUps("customers", T), 1, "customers listed")
eq(#M.FollowUps("everyone", T), 3, "do-not-contact and ignored people are never listed")
eq(M.RecordOutreach("Lead1-Stormrage", "Follow-up: still available", T + DAY), true, "outreach recorded")
local l1 = M.GetContact("Lead1-Stormrage")
eq(l1.outreach, 1, "outreach counted")
eq(l1.lastOutreach, T + DAY, "last outreach time kept")
eq(l1.lastTemplate, "Follow-up: still available", "template remembered")
local f = M.FollowUps("leads", T + DAY)
eq(f[1].key, "Lead2-Stormrage", "never-contacted lead comes first")
eq(f[2].recent, true, "just-contacted lead is flagged recent")
M.RecordOutreach("Lead2-Stormrage", "x", T + 2 * DAY)
M.RecordOutreach("Lead1-Stormrage", "x", T + 2 * DAY)
eq(l1.outreach, 2, "second outreach counted")
f = M.FollowUps("leads", T + 10 * DAY)
eq(f[1].recent, false, "after the gap they are due again")
eq(M.Ago(nil, T), "never", "never contacted")
eq(M.Ago(T, T + 100), "today", "contacted today")
eq(M.Ago(T, T + 3 * DAY + 5), "3 days ago", "days since outreach")
eq(M.RecordOutreach("Nobody-Stormrage", "x", T), false, "unknown contact not counted")
dump = M.Export()
DB.Init({}, "Other4")
M.Import(dump, T)
eq(M.GetContact("Lead1-Stormrage").outreach, 2, "outreach count survives export and import")

-- data from before follow-up templates existed gains them once, without duplicates
local older = DB.Init({}, "Old")
older.realms.Old.seededFollowUps = nil
older.realms.Old.mailTemplates = { older.realms.Old.mailTemplates[1] }
DB.Init(older, "Old")
eq(#DB.R.mailTemplates, 4, "follow-up templates added to existing data")
DB.Init(older, "Old")
eq(#DB.R.mailTemplates, 4, "and only once")

-- campaigns: rotation, the wait between posts, and the funnel per post
fresh()
local pA = M.SavePost(nil, "A", "post a", { TRADE = true })
local pB = M.SavePost(nil, "B", "post b", { TRADE = true, SAY = true })
_, err = M.StartCampaign("x", {}, 60, 5, T)
eq(err ~= nil, true, "campaign needs a post")
_, err = M.StartCampaign("x", { pA.id }, 0, 5, T)
eq(err ~= nil, true, "campaign needs a length")
_, err = M.StartCampaign("x", { pA.id }, 60, 0, T)
eq(err ~= nil, true, "campaign needs a wait of at least a minute")
local camp = M.StartCampaign("Evening", { pA.id, pB.id }, 60, 5, T)
eq(camp.status, "running", "campaign running")
eq(DB.R.tracking.on, true, "starting a campaign turns tracking on")
local np, nt = M.CampaignNext(camp, ALL, T)
eq(np.id, pA.id, "first post goes first")
eq(nt, "TRADE", "to its channel")
M.RecordSend(pA, "TRADE", T, "City")
M.CampaignAdvance(camp, pA, ALL, T)
eq(camp.turn, 2, "next post gets its turn")
np, nt = M.CampaignNext(camp, ALL, T)
eq(np.id, pB.id, "second post is next")
eq(nt, "SAY", "to a channel that is not waiting")
M.RecordSend(pB, "SAY", T, "City")
M.CampaignAdvance(camp, pB, ALL, T)
local nwait
np, nt, nwait = M.CampaignNext(camp, ALL, T + 60)
eq(np, nil, "nothing due while channels wait")
eq(nwait, 240, "the campaign's 5 minute wait applies, not the 60 second one")
eq(M.GapRemaining("TRADE", T + 60), 240, "channel gap follows the campaign")
np, nt = M.CampaignNext(camp, ALL, T + 300)
eq(np.id, pA.id, "after the wait the rotation continues")
local cl = M.OnWhisper("Zed-Stormrage", "bags?", T + 10)
eq(cl.campaign, camp.id, "lead belongs to the campaign")
eq(cl.post, pB.id, "and to the post that was last sent")
local co = M.AddTrade(nil, "Zed-Stormrage", { given = { { name = "Bag", qty = 1 } }, gold = 10000 }, T + 20)
eq(co.campaign, camp.id, "order belongs to the campaign")
eq(co.post, pB.id, "and to the post that brought the lead")
local rp = M.CampaignReport(camp.id)
eq(rp.sends, 2, "campaign sends")
eq(rp.leads, 1, "campaign leads")
eq(rp.orders, 1, "campaign orders")
eq(rp.gold, 10000, "campaign gold")
eq(rp.posts[1].sends, 1, "sends per post")
eq(rp.posts[1].leads, 0, "a post with no leads shows none")
eq(rp.posts[2].leads, 1, "leads per post")
eq(rp.posts[2].sold[1].name, "Bag", "items sold per post")
eq(M.TrackingState(T + 40 * 60), true, "tracking stays on for the whole campaign")
eq(M.SoldCounts().Bag, 1, "sold counts by item")
local hr
for _, r in ipairs(M.HourReport()) do if r.hour == U.Hour(T) then hr = r end end
eq(hr.sends, 2, "posts counted in their hour")
eq(hr.leads, 1, "leads counted in the hour of the post")
eq(hr.orders, 1, "orders counted in the hour of the post")
eq(hr.income, 10000, "income counted in the hour of the post")
local live, done = M.ActiveCampaign(T + 3600)
eq(live, nil, "campaign stops when its time is up")
eq(done.id, camp.id, "and reports that it just finished")
eq(camp.status, "ended", "campaign marked ended")
eq(M.GapRemaining("TRADE", T + 3600 + 30), 0, "normal gap applies again afterwards")
eq(M.Rate(1, 2), "0.5", "leads per post")
eq(M.Rate(1, 2, true), "50%", "share who ordered")
eq(M.Rate(1, 0), "-", "no rate without posts")
eq(M.Clock(185), "3:05", "countdown")
eq(M.Clock(3725), "1:02:05", "long countdown")

-- product list: costs, margins, filters and sorting
local Cat = ns.Catalog
local cost = { [1] = 100, [2] = 0, [10] = 1000, [11] = 300 }
local prows = Cat.Build({
	{ id = 1, name = "Silk Bag", category = "Bags", learned = true, output = 10, outputQty = 1, reagents = { { itemID = 1, qty = 4 } } },
	{ id = 2, name = "Reagent Bag", category = "Specialty Bags", learned = false, output = 11, reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } },
	{ id = 3, name = "Bolt", category = "", learned = true, reagents = {} },
}, "Tailoring", function(i) return cost[i] or 0 end, { ["Silk Bag"] = 3 }, { ["Tailoring|Silk Bag"] = true },
	function(i) return ({ [1] = 9, [2] = 0 })[i] or 0 end, function(i) return ({ [10] = 10, [11] = 20 })[i] end)
eq(#prows, 3, "rows built")
eq(prows[1].mats, 400, "materials cost")
eq(prows[1].sale, 1000, "sale value")
eq(prows[1].margin, 600, "margin")
eq(prows[1].sold, 3, "times sold")
eq(prows[1].product, true, "marked as my product")
eq(prows[2].unpriced, 1, "material without a price is counted")
eq(prows[3].category, "Other", "missing category")
eq(prows[1].canMake, 2, "9 cloth at 4 each makes 2")
eq(prows[1].buy, 0, "holding every material leaves nothing to buy")
eq(prows[1].cost, 400, "cost stays at full price unless held mats are treated as free")
eq(prows[2].buy, 0, "priced materials are held; the missing one has no price")
eq(prows[2].unpricedBuy, 1, "a missing material without a price is flagged")
local function build(have, free)
	return Cat.Build({ { id = 1, name = "Silk Bag", category = "Bags", learned = true, output = 10, reagents = { { itemID = 1, qty = 4 }, { itemID = 11, qty = 1 } } } },
		"Tailoring", function(i) return cost[i] or 0 end, {}, {}, function(i) return have[i] or 0 end, nil, free)[1]
end
local b = build({ [1] = 3 }, true)
eq(b.mats, 700, "every material at today's price")
eq(b.buy, 400, "only the shortfall is bought: 1 cloth and the 1 thread")
eq(b.cost, 400, "held mats free: cost is what is still to buy")
eq(b.margin, 600, "margin after what you hold")
eq(b.reagents[1].short, 1, "one cloth short")
b = build({ [1] = 3 }, false)
eq(b.cost, 700, "full price view: cost is every material")
eq(b.margin, 300, "margin at full materials price")
b = build({ [1] = 40, [11] = 5 }, true)
eq(b.cost, 0, "everything held: nothing to buy")
eq(b.margin, 1000, "the whole price is margin")
local two = Cat.Build({
	{ id = 1, name = "Dear", category = "Bags", learned = true, output = 10, reagents = { { itemID = 1, qty = 4 } } },
	{ id = 2, name = "Cheap", category = "Bags", learned = true, output = 10, reagents = { { itemID = 11, qty = 1 } } },
}, "Tailoring", function(i) return cost[i] or 0 end, {}, {}, function(i) return i == 1 and 4 or 0 end, nil, true)
eq(Cat.Sort(two, "mats cost")[1].name, "Dear", "sorting by cost puts what you can make from held mats first")
eq(prows[2].canMake, 0, "one missing material means none can be made")
eq(prows[3].canMake, 0, "a recipe with no materials listed is not counted as craftable")
eq(#Cat.Filter(prows, { craftableOnly = true }), 1, "craftable now")
eq(#Cat.Filter(prows, { craftableOnly = true, learnedOnly = true }), 1, "craftable and learned together")
eq(Cat.Sort(Cat.Filter(prows, {}), "can make")[1].name, "Silk Bag", "sort by how many you can make")
eq(table.concat(Cat.Categories(prows), ","), "All,All bags,Bags,Other,Specialty Bags", "categories, with every kind of bag together")
eq(#Cat.Filter(prows, { category = Cat.ALL_BAGS }), 2, "All bags covers bags and specialty bags")
eq(prows[1].slots, 10, "bag size read")
eq(prows[3].slots, nil, "non-bags have no size")
eq(Cat.Sort(Cat.Filter(prows, {}), "bag size")[1].name, "Reagent Bag", "biggest bag first")
eq(#Cat.Filter(prows, { learnedOnly = true }), 2, "learned only")
eq(#Cat.Filter(prows, { category = "Specialty Bags" }), 1, "by category")
eq(#Cat.Filter(prows, { search = "BAG" }), 2, "search ignores case")
eq(#Cat.Filter(prows, { productsOnly = true }), 1, "my products only")
eq(Cat.Sort(Cat.Filter(prows, {}), "margin")[1].name, "Silk Bag", "sort by margin")
eq(Cat.Sort(Cat.Filter(prows, {}), "mats cost")[1].name, "Bolt", "sort by materials cost, cheapest first")
eq(Cat.Sort(Cat.Filter(prows, {}), "sale value")[1].name, "Silk Bag", "sort by sale value")
eq(Cat.Sort(Cat.Filter(prows, {}), "name")[1].name, "Bolt", "sort by name")
local grouped = Cat.Group(Cat.Filter(prows, { category = Cat.ALL_BAGS }), "margin")
eq(#grouped, 4, "two headings and two recipes")
eq(grouped[1].header, true, "heading first")
eq(grouped[1].name, "Bags", "headings in order")
eq(grouped[2].name, "Silk Bag", "recipes under their heading")
eq(grouped[3].name, "Specialty Bags", "second heading")
eq(#Cat.Group(Cat.Filter(prows, { category = "Bags" }), "name"), 1, "one category needs no heading")
eq(Cat.Quote(prows[1]), "Silk Bag (10 slot) 10s", "quote from the auction price")
eq(Cat.Quote(prows[3]), nil, "no quote without a price")
local priced = Cat.Build({
	{ id = 1, name = "Silk Bag", category = "Bags", learned = true, output = 10, reagents = { { itemID = 1, qty = 4 } } },
	{ id = 2, name = "Big Bag", category = "Bags", learned = true, output = 11, reagents = { { itemID = 1, qty = 9 } } },
}, "Tailoring", function(i) return cost[i] or 0 end, {}, { ["Tailoring|Silk Bag"] = { price = 2500 } }, nil, function(i) return ({ [10] = 10, [11] = 14 })[i] end)
eq(priced[1].price, 2500, "your own price is what gets quoted")
eq(priced[1].margin, 2100, "margin uses your own price")
eq(Cat.Quote(priced[1]), "Silk Bag (10 slot) 25s", "quote from your price")
local qtext, qn = Cat.QuoteList(Cat.Group(priced, "bag size"), 252)
eq(qtext, "Big Bag (14 slot) 3s, Silk Bag (10 slot) 25s", "price list, biggest first")
eq(qn, 2, "both items quoted")
qtext, qn = Cat.QuoteList(priced, 30)
eq(qn, 1, "price list stops before it would be too long for chat")

-- inventory across bags, bank, other characters and guild banks
local Inv = ns.Inventory
local pid, pn = Inv.ParseItem("4306;20")
eq(pid, 4306, "item id from a stored stack")
eq(pn, 20, "stack size from a stored stack")
pid, pn = Inv.ParseItem("16084::::::::25:1491::14:::::::")
eq(pid, 16084, "item id from a stored item with details")
eq(pn, 1, "a single item counts as one")
eq(Inv.ParseItem("WARRIOR"), nil, "other stored text is not an item")
local held = Inv.Collect({
	guid = "Me", name = "Me Name",
	mastercraft = {
		Me = { bags = { [1] = 99 }, bank = { [1] = 8 } },
		Alt1 = { bags = { [1] = 5 }, bank = { [1] = 10, [2] = 3 } },
		Alt2 = { bags = { [1] = 1 } },
	},
	brother = { forever = {
		["Me Name"] = { { items = { "1;50" } } },
		["Guild One*"] = { { items = { "1;25", "2" } }, { name = "Tab 2", items = { "1;5" } } },
	} },
})
eq(held.myBank[1], 8, "own bank from the recorded snapshot")
eq(held.altBags[1], 6, "other characters' bags added together")
eq(held.altBank[1], 10, "other characters' banks")
eq(held.guild[1], 30, "guild bank tabs added together")
eq(held.guild[2], 1, "single guild bank item")
eq(held.found.alts, true, "other characters found")
eq(held.found.guild, true, "guild bank found")
local function bagsFn(id) return id == 1 and 4 or 0 end
local function bankFn(id) return id == 1 and 6 or 0 end
local cnt, parts = Inv.Counter(held, { bags = true }, bagsFn, bankFn)
eq(cnt(1), 4, "bags only")
cnt, parts = Inv.Counter(held, { bags = true, bank = true }, bagsFn, bankFn)
eq(cnt(1), 12, "bags plus bank, using the larger of the two bank figures")
eq(parts(1), "bags 4, bank 8", "breakdown by place")
cnt, parts = Inv.Counter(held, { bags = true, bank = true, altBags = true, altBank = true, guild = true }, bagsFn, bankFn)
eq(cnt(1), 58, "everything ticked")
eq(cnt(2), 4, "an item held only by an alt and the guild")
eq(parts(3), "none", "nothing anywhere")
cnt = Inv.Counter(held, { guild = true }, bagsFn, bankFn)
eq(cnt(1), 30, "guild bank alone")
held = Inv.Collect({ name = "Me Name", brother = { forever = {
	["Me Name"] = { { items = { "1;50" } } },
	["Other Char"] = { { items = { "1;7" } }, { bankType = 0, items = { "1;9" } } },
} } })
eq(held.altBags[1], 7, "without Mastercraft, other characters' bags come from Bagnon")
eq(held.altBank[1], 9, "and their banks too")
eq(held.guild[1], nil, "no guild bank stored")
eq(DB.Init({}, "Inv").settings.invSources.bags, true, "bags counted by default")

-- a strict pause between any two public posts, and the one-button cycle
fresh()
eq(DB.Init({}, "Spacing").settings.publicSpacing, 2, "two minutes between public posts by default")
fresh()
DB.settings.publicSpacing = 2
M.cycleState = { post = 0, chan = 0 }
local cp1 = M.SavePost(nil, "One", "one", { TRADE = true })
local cp2 = M.SavePost(nil, "Two", "two", { GENERAL = true })
M.SavePost(nil, "Guild only", "g", { GUILD = true })
eq(#M.CyclePosts(), 2, "posts for Guild or Party only stay out of the cycle")
local cyc = { GENERAL = true, TRADE = true }
local cpost, ctgt, cidx = M.CycleNext(cyc, ALL, T)
eq(cpost.id, cp1.id, "the cycle starts with the first post")
eq(ctgt, "GENERAL", "and with General")
M.RecordSend(cpost, ctgt, T, "City"); M.CycleAdvance(cpost, cidx)
local _, _, cwait = M.CycleNext(cyc, ALL, T + 30)
eq(cwait, 90, "then waits two minutes before any public post")
eq(M.GapRemaining("TRADE", T + 30), 90, "the pause holds back other public channels too")
eq(M.GapRemaining("GUILD", T + 30), 0, "guild is not held back")
cpost, ctgt, cidx = M.CycleNext(cyc, ALL, T + 120)
eq(cpost.id, cp2.id, "next tap, next post")
eq(ctgt, "TRADE", "next tap, next channel")
M.RecordSend(cpost, ctgt, T + 120, "City"); M.CycleAdvance(cpost, cidx)
local noTrade = function(t) return t ~= "TRADE" end
cpost, ctgt, cidx = M.CycleNext(cyc, noTrade, T + 240)
eq(ctgt, "GENERAL", "outside a city it goes to General")
eq(cpost.id, cp1.id, "posts take turns")
M.RecordSend(cpost, ctgt, T + 240, "Field"); M.CycleAdvance(cpost, cidx)
cpost, ctgt = M.CycleNext({ GENERAL = true, TRADE = true, YELL = true }, noTrade, T + 360)
eq(ctgt, "YELL", "yell takes its turn when ticked")
local _, _, _, cwhy = M.CycleNext({ TRADE = true }, noTrade, T + 480)
eq(cwhy ~= nil, true, "explains when no ticked channel is available")
DB.settings.publicSpacing = 0
eq(M.GapRemaining("TRADE", T + 361), 0, "the pause can be switched off")

-- personal quotes, with the next smaller and cheaper bag
local bq = Cat.Build({
	{ id = 11, name = "Big Bag", category = "Bags", learned = true, output = 30, reagents = {} },
	{ id = 12, name = "Mid Bag", category = "Bags", learned = true, output = 31, reagents = {} },
	{ id = 13, name = "Small Bag", category = "Bags", learned = true, output = 32, reagents = {} },
	{ id = 14, name = "Unknown Bag", category = "Bags", learned = false, output = 33, reagents = {} },
	{ id = 15, name = "Herb Bag", category = "Specialty Bags", learned = true, output = 34, reagents = {} },
}, "Tailoring", function(i) return ({ [30] = 40000, [31] = 15000, [32] = 5000, [33] = 9000, [34] = 3000 })[i] or 0 end, {}, {}, nil,
	function(i) return ({ [30] = 16, [31] = 12, [32] = 8, [33] = 14, [34] = 12 })[i] end)
local alt = Cat.SmallerOption(bq, bq[1])
eq(alt.name, "Mid Bag", "the next size down that you have learned, of the same kind")
eq(Cat.SmallerOption(bq, bq[3]), nil, "nothing smaller than the smallest")
eq(Cat.SmallerOption(bq, bq[5]), nil, "a specialty bag is not offered a plain bag")
local qo = { template = "Hi {name}! {item} is {price} with my mats.", altTemplate = "I can also do {alt} for {altprice}.", name = "Ann" }
eq(Cat.QuoteText(bq[1], alt, qo), "Hi Ann! Big Bag (16 slot) is 4g with my mats. I can also do Mid Bag (12 slot) for 1g 50s.", "personal quote with a cheaper option")
eq(Cat.QuoteText(bq[3], nil, qo), "Hi Ann! Small Bag (8 slot) is 50s with my mats.", "quote without an option")
qo.altTemplate = ""
eq(Cat.QuoteText(bq[1], alt, qo), "Hi Ann! Big Bag (16 slot) is 4g with my mats.", "the option can be left out")
eq(Cat.WowheadURL(bq[1]), "https://www.wowhead.com/forever/spell=11", "Wowhead page for the recipe")
eq(Cat.WowheadURL({ name = "Black Silk Pack" }), "https://www.wowhead.com/forever/search?q=Black+Silk+Pack", "Wowhead search when the recipe id is unknown")

-- two-part names: joined when the game splits them, and repaired in saved data
fresh()
eq(M.JoinName("Rosa", "Vell"), "Rosa Vell-Stormrage", "a last name in the realm slot is joined to the first name")
eq(M.JoinName("Ann", nil), "Ann-Stormrage", "a plain name")
eq(M.JoinName("Ann", "Stormrage"), "Ann-Stormrage", "our own realm is still read as a realm")
M.EnsureContact("Zed Ward-Faraway", T)
eq(M.JoinName("Zed", "Faraway"), "Zed-Faraway", "a realm seen in a whispered name is read as a realm")
M.EnsureContact("Brin Ashby-Stormrage", T)
M.GetContact("Brin Ashby-Stormrage").sourcePost = 5
local split = M.EnsureContact("Brin-Ashby", T + 50)
split.notes = "paid fast"
M.SaveOrder(nil, { contact = "Brin-Ashby", items = { { name = "Silk Bag", qty = 1 } }, price = 10000, status = "paid" }, T + 50)
M.EnsureContact("Tam-Holloway", T)
M.SaveOrder(nil, { contact = "Tam-Holloway", items = { { name = "Red Mageweave Bag, Red Mageweave Bag, 2x Linen Bag", qty = 1, link = "|Hitem:1|h[Red Mageweave Bag]|h" } }, price = 5, status = "paid" }, T)
eq(M.RepairSplitNames(), 2, "two contacts saved under half a name")
eq(M.GetContact("Brin-Ashby"), nil, "the half-name contact is gone")
eq(M.LTV("Brin Ashby-Stormrage"), 10000, "its order now belongs to the whole name")
eq(M.GetContact("Brin Ashby-Stormrage").notes, "paid fast", "notes carried over")
eq(M.GetContact("Brin Ashby-Stormrage").sourcePost, 5, "the lead's post is kept")
eq(M.GetContact("Tam Holloway-Stormrage") ~= nil, true, "a half name with no whisper contact is renamed")
eq(M.GetContact("Zed Ward-Faraway") ~= nil, true, "whole names are left alone")
M.RefreshStatuses()
eq(M.GetContact("Brin Ashby-Stormrage").status, "customer", "the merged contact counts as a customer")
eq(M.RepairSplitNames(), 0, "nothing left to repair the second time")
eq(M.RepairJoinedItems(), 1, "one old order with items joined into one line")
local vo = M.OrdersFor("Tam Holloway-Stormrage")[1]
eq(#vo.items, 2, "split into one line per item")
eq(vo.items[1].qty, 2, "Red Mageweave Bag twice")
eq(vo.items[1].link ~= nil, true, "the link stays with its own item")
eq(vo.items[2].name, "Linen Bag", "second item")
eq(vo.items[2].qty, 2, "with its quantity")
eq(M.RepairJoinedItems(), 0, "nothing left to split the second time")
local ps = M.PurchaseSummary("Brin Ashby-Stormrage")
eq(ps.done, 1, "one finished order")
eq(ps.value, 10000, "what they have paid")
eq(M.PurchaseSummary("Zed Ward-Faraway").orders, 0, "someone who has bought nothing")

-- posts belong to the character whose voice they are written in
fresh()
local mine = M.SavePost(nil, "Mine", "mine", { TRADE = true })
eq(mine.owner, "Me-Stormrage", "a new post belongs to the character writing it")
local shared = M.SavePost(nil, "Shared", "shared", { TRADE = true }, M.ANY)
local main = M.SavePost(nil, "Main", "main", { TRADE = true }, "Main Char-Stormrage")
local old = M.SavePost(nil, "Old", "old", { TRADE = true })
old.owner = nil -- written before posts had owners
eq(M.CanPost(mine), true, "own post")
eq(M.CanPost(shared), true, "a post for any character")
eq(M.CanPost(main), false, "another character's post")
eq(M.CanPost(old), false, "a post given to nobody yet")
eq(#M.PostsFor(), 2, "only own and shared posts are offered")
eq(#M.CyclePosts(), 2, "the cycle uses only own and shared posts")
eq(M.OwnerProblem(main):find("Main Char", 1, true) ~= nil, true, "says whose post it is")
eq(M.OwnerProblem(mine), nil, "no problem with your own post")
eq(M.SavePost(main.id, "Main", "main edited", { TRADE = true }).owner, "Main Char-Stormrage", "editing keeps the owner")
local oc = M.StartCampaign("Mixed", { mine.id, main.id, shared.id }, 30, 5, T)
eq(#oc.posts, 2, "a campaign leaves out other characters' posts")
eq(oc.character, "Me-Stormrage", "the campaign records who ran it")
M.EndCampaign(T)
eq(M.UnassignedPosts(), 1, "one post given to nobody")
eq(M.AssignPosts("Me-Stormrage"), 1, "given to this character")
eq(M.CanPost(old), true, "and now postable")
M.me = "Alt-Stormrage"
eq(#M.PostsFor(), 1, "on another character, only the shared post is offered")
M.me = "Me-Stormrage"
local dumpOwners = M.Export()
DB.Init({}, "OwnerCopy")
M.Import(dumpOwners, T)
local owners = {}
for _, ip in ipairs(DB.R.posts) do owners[ip.name] = ip.owner end
eq(owners.Main, "Main Char-Stormrage", "owner survives export and import")
eq(owners.Shared, M.ANY, "shared survives export and import")

-- copying a post for this character, and follow-ups when online
fresh()
local theirs = M.SavePost(nil, "Main pitch", "WTS bags", { TRADE = true }, "Main Char-Stormrage")
local copy = M.CopyPost(theirs.id)
eq(copy.owner, "Me-Stormrage", "the copy belongs to this character")
eq(copy.text, "WTS bags", "with the same words")
eq(copy.name, "Main pitch (Me)", "named after this character")
eq(theirs.owner, "Main Char-Stormrage", "the original is untouched")
eq(M.CopyPost(nil) == nil, true, "nothing to copy")
M.EnsureContact("Wren Kettle-Stormrage", T)
M.EnsureContact("Ann-Stormrage", T)
eq(#M.OnlineFollowUps(), 0, "no follow-ups yet")
M.SetFollowUp("Wren Kettle-Stormrage", "  wants 4 bags  ", T)
M.SetFollowUp("Ann-Stormrage", "", T + 10)
eq(#M.OnlineFollowUps(), 2, "two follow-ups")
eq(M.OnlineFollowUps()[1].key, "Wren Kettle-Stormrage", "oldest promise first")
eq(M.GetContact("Wren Kettle-Stormrage").followUp.note, "wants 4 bags", "note kept, trimmed")
eq(M.GetContact("Wren Kettle-Stormrage").followUp.by, "Me-Stormrage", "who promised it")
eq(M.SeenOnline("Wren Kettle-Stormrage", T + 100, "came online"), true, "alert when seen online")
eq(M.SeenOnline("Wren Kettle-Stormrage", T + 200, "chat"), false, "not again within half an hour")
eq(M.SeenOnline("Wren Kettle-Stormrage", T + 100 + 31 * 60, "chat"), true, "again after half an hour")
eq(M.GetContact("Wren Kettle-Stormrage").lastSeen, T + 100 + 31 * 60, "last seen time kept")
M.EnsureContact("Bo-Stormrage", T)
eq(M.SeenOnline("Bo-Stormrage", T, "chat"), false, "no alert for someone not followed up")
eq(M.GetContact("Bo-Stormrage").lastSeen, T, "but when they were seen is noted")
M.ClearFollowUp("Ann-Stormrage")
eq(#M.OnlineFollowUps(), 1, "follow-up done")
M.Watching()["Wren Kettle-Stormrage"] = true
eq(M.Watching("Other-Stormrage")["Wren Kettle-Stormrage"], nil, "each character keeps its own friends-list entries")

-- settings floor and data surviving a reload
local saved = DB.Init({ settings = { minGap = 1 } }, "R")
eq(saved.settings.minGap, DB.MIN_GAP_FLOOR, "gap floor enforced")
M.SavePost(nil, "Keep", "me", { SAY = true })
M.SetTracking(true, T)
DB.Init(saved, "R")
eq(#DB.R.posts, 1, "data kept across re-init")
eq(DB.R.tracking.on, true, "tracking kept across a reload")

-- posting switches tracking on by itself, unless that is turned off
fresh()
post = M.SavePost(nil, "Bags", "WTS bags", { SAY = true })
M.RecordSend(post, "SAY", T, "City")
eq(select(2, M.TrackingState(T + 1)), true, "a post switches tracking on and starts capturing")
local _, _, mins, secs = M.TrackingState(T + 60)
eq(secs, 29 * 60, "seconds left for the bar's countdown")
fresh()
DB.settings.autoTrack = false
post = M.SavePost(nil, "Bags", "WTS bags", { SAY = true })
M.RecordSend(post, "SAY", T, "City")
eq(M.TrackingState(T + 1), false, "with the option off, posting leaves tracking off")

-- one conversation is one lead, whatever post it was about
fresh()
local p1 = M.SavePost(nil, "Bags", "WTS bags", { SAY = true })
local p2 = M.SavePost(nil, "Robes", "WTS robes", { SAY = true })
M.RecordSend(p1, "SAY", T, "City")
local la = M.OnWhisper("Dee-Stormrage", "how much for a bag?", T + 10)
eq(M.OnWhisperSent("Dee-Stormrage", "1g 90s with my mats", T + 20), true, "my reply is kept")
eq(M.OnWhisperSent("Stranger-Stormrage", "hi", T + 21), false, "whispers to non-contacts are not kept")
M.RecordSend(p2, "SAY", T + 200, "City")
local lb, newB = M.OnWhisper("Dee-Stormrage", "and is the robe ready?", T + 210)
eq(lb.id, la.id, "a whisper after another post joins the same lead")
eq(newB, false, "no new lead")
eq(la.post, p1.id, "the lead keeps the post that started it")
eq(#DB.R.leads, 1, "still one lead")
local chat = M.LeadChat(la)
eq(#chat, 3, "conversation: their whisper, my reply, their next whisper")
eq(chat[2].me, true, "my reply in order")
eq(chat[3].text, "and is the robe ready?", "latest whisper last")

-- turning the lead into an order shell at the product price
DB.R.products["Tailoring|Red Mageweave Bag"] = { name = "Red Mageweave Bag", profession = "Tailoring", output = 10051, price = 19000 }
DB.R.products["Tailoring|Bolt of Silk"] = { name = "Bolt of Silk", profession = "Tailoring", output = 4305 }
local choices = M.ProductChoices(function(id) return id == 4305 and 1200 or nil end)
eq(#choices, 2, "marked products offered")
eq(choices[1].name, "Bolt of Silk", "sorted by name")
eq(choices[1].price, 1200, "no price of my own: market price")
eq(choices[2].price, 19000, "my price used")
local shell = M.LeadToOrder(la.id, { name = "Red Mageweave Bag", price = 19000 }, 1, T + 300)
eq(shell.status, "quoted", "shell order is quoted")
eq(shell.quote, 19000, "agreed price from the Products tab")
eq(shell.price, 0, "no gold received yet")
eq(shell.items[1].planned, true, "the bag is still to hand over")
eq(la.status, "won", "lead closed")
eq(la.order, shell.id, "lead points at its order")
eq(shell.post, p1.id, "order credited to the post that brought the lead")
eq(M.SoldCounts()["Red Mageweave Bag"], nil, "a planned bag is not counted as sold")

-- chatting on after the order does not start a new lead
local lc, newC = M.OnWhisper("Dee-Stormrage", "on my way", T + 400)
eq(lc.id, la.id, "whisper after the order joins the same lead")
eq(newC, false, "no new lead after the order")
eq(M.OnWhisper("Dee-Stormrage", "thanks again!", T + 13 * 3600) ~= la, true, "a day later it is a new conversation")
eq(#DB.R.leads, 1, "but only while tracking is capturing (it is off by then)")

-- the trade fills in the shell instead of making a second order
eq(M.CurrentOrder("Dee-Stormrage", T + 5 * 3600).id, shell.id, "an open order is found however old")
M.AddTrade(shell.id, "Dee-Stormrage", { given = {}, received = { { name = "Mageweave Cloth", qty = 12, value = 500 } }, gold = 0 }, T + 5 * 3600)
eq(shell.status, "in progress", "materials in, bag not handed over yet")
eq(shell.received[1].kind, "mats", "cloth before delivery is materials")
M.AddTrade(shell.id, "Dee-Stormrage", { given = { { name = "Red Mageweave Bag", qty = 1 } }, received = {}, gold = 19000 }, T + 6 * 3600)
eq(#shell.items, 1, "the planned bag became the delivered bag, not a second line")
eq(shell.items[1].planned, nil, "handed over")
eq(shell.items[1].qty, 1, "still one bag")
eq(shell.price, 19000, "gold is what was received, not the quote plus the gold")
eq(shell.status, "paid", "paid on delivery with gold")
eq(#DB.R.orders, 1, "one order for the job")
eq(M.LTV("Dee-Stormrage"), 19000, "lifetime value counted once")
eq(M.SoldCounts()["Red Mageweave Bag"], 1, "sold once")

-- marking a quoted order paid with no gold typed uses the agreed price
local l2 = M.OnWhisper("Eve-Stormrage", "bag please", T + 6 * 3600 + 10)
M.SetTracking(true, T + 6 * 3600)
M.RecordSend(p1, "SAY", T + 6 * 3600 + 20, "City")
l2 = M.OnWhisper("Eve-Stormrage", "bag please", T + 6 * 3600 + 30)
local o2 = M.LeadToOrder(l2.id, { name = "Red Mageweave Bag", price = 19000 }, 2, T + 6 * 3600 + 40)
eq(o2.quote, 38000, "agreed price times quantity")
M.SaveOrder(o2.id, { contact = "Eve-Stormrage", items = o2.items, price = 0, status = "paid", quote = o2.quote }, T + 6 * 3600 + 50)
eq(o2.price, 38000, "paid at the agreed price")
eq(o2.items[1].planned, true, "planned flag survives a save")

-- export keeps the agreed price and what is still to hand over
local text = M.Export()
fresh()
M.Import(text, T)
local back
for _, o in ipairs(DB.R.orders) do if o.contact == "Eve-Stormrage" then back = o end end
eq(back.quote, 38000, "agreed price exported")
eq(back.items[1].planned, true, "planned items exported")

-- earlier duplicate leads are folded into one per person
fresh()
DB.R.leads = {
	{ id = 1, contact = "Fay-Stormrage", status = "open", time = 100, count = 2, text = "first" },
	{ id = 2, contact = "Fay-Stormrage", status = "open", time = 300, count = 1, text = "second" },
	{ id = 3, contact = "Fay-Stormrage", status = "dismissed", time = 50, count = 1, text = "old" },
	{ id = 4, contact = "Gus-Stormrage", status = "open", time = 200, count = 1, text = "only" },
}
eq(M.MergeDuplicateLeads(), 1, "one duplicate folded")
eq(#DB.R.leads, 3, "dismissed and other people's leads kept")
eq(DB.R.leads[1].count, 3, "messages added together")
eq(DB.R.leads[1].time, 300, "latest message time kept")
eq(M.MergeDuplicateLeads(), 0, "nothing to fold the second time")

-- the conversation is capped
fresh()
M.EnsureContact("Hal-Stormrage", T)
for i = 1, M.CHAT_KEEP + 5 do M.LogChat("Hal-Stormrage", i % 2 == 0, "m" .. i, T + i) end
eq(#M.GetContact("Hal-Stormrage").chat, M.CHAT_KEEP, "oldest whispers dropped past the limit")
eq(M.GetContact("Hal-Stormrage").chat[1].text, "m6", "the newest are kept")

-- where materials come from, and what to craft first
do
	local S = ns.Sources
	eq(S.ItemID("|cffffffff|Hitem:2838::::::::|h[Heavy Stone]|h|r"), 2838, "item id from a link")
	eq(S.ItemID(nil), nil, "no link, no id")
	eq(S.Notes("Heavy Stone")[1]:find("Iron Deposits", 1, true) ~= nil, true, "heavy stone comes from iron")
	eq(S.Notes("nothing like this"), nil, "unknown item has no notes")
	eq(S.WowheadURL(2838), "https://www.wowhead.com/forever/item=2838", "wowhead item page")

	-- Patterned Bronze Bracers need Bronze Bars and a Coarse Grinding Stone; the stone is made from Coarse Stone.
	local book = {
		[1] = { name = "Patterned Bronze Bracers", reagents = { { key = 2841, name = "Bronze Bar", qty = 5 }, { key = 3478, name = "Coarse Grinding Stone", qty = 2 } } },
		[3478] = { name = "Coarse Grinding Stone", made = 1, reagents = { { key = 2836, name = "Coarse Stone", qty = 2 } } },
	}
	local held = { [2841] = 5, [2836] = 1 }
	local steps, missing = S.Plan(1, function(k) return book[k] end, function(k) return held[k] or 0 end)
	eq(#steps, 1, "one thing to craft first")
	eq(steps[1].name .. " x" .. steps[1].crafts, "Coarse Grinding Stone x2", "two grinding stones")
	eq(#missing, 1, "short of one material")
	eq(missing[1].name .. " " .. missing[1].qty, "Coarse Stone 3", "three more coarse stone (four needed, one held)")
	eq(S.PlanText(steps), "Craft first: 2x Coarse Grinding Stone", "plan text")

	held[3478] = 2
	steps = S.Plan(1, function(k) return book[k] end, function(k) return held[k] or 0 end)
	eq(#steps, 0, "nothing to craft once you hold the stones")
	eq(S.PlanText(steps), nil, "and no advice")

	-- a recipe that makes two at a time, used twice down the tree, and a loop that must not hang
	book[1].reagents[3] = { key = 50, name = "Part", qty = 1 }
	book[3478].reagents[2] = { key = 50, name = "Part", qty = 1 }
	book[50] = { name = "Part", made = 2, reagents = { { key = 1, name = "Patterned Bronze Bracers", qty = 1 } } }
	held = {}
	steps = S.Plan(1, function(k) return book[k] end, function() return 0 end)
	local crafts = {}
	for _, st in ipairs(steps) do crafts[st.name] = st.crafts end
	eq(crafts.Part, 2, "three parts needed, two per craft")
	eq(crafts["Coarse Grinding Stone"], 2, "grinding stones still planned")
	eq(steps[#steps].name, "Coarse Grinding Stone", "parts come before the stones that use them")

	local trail = {}
	S.Push(trail, { name = "A" }); S.Push(trail, { name = "A" }); S.Push(trail, { name = "B" })
	eq(#trail, 2, "the same recipe twice in a row is remembered once")
	eq(S.Pop(trail).name, "B", "back goes to the last one")
	eq(S.Pop(trail).name, "A", "then the one before")
	eq(S.Pop(trail), nil, "then nothing")
end

-- bag offers: raw cloth to bring, vendor mats plus a tip as the fee, and the line for the chat box
do
	local O = ns.Offers
	local NAMES = { [20] = "Bolt of Linen Cloth", [21] = "Linen Cloth", [22] = "Bolt of Silk Cloth", [23] = "Silk Cloth",
		[30] = "Coarse Thread", [31] = "Red Dye" }
	local PRICE = { [30] = 10, [31] = 50 }
	local list = {
		{ id = 1, name = "Red Linen Bag", learned = true, output = 10, reagents = { { itemID = 20, qty = 4 }, { itemID = 30, qty = 1 }, { itemID = 31, qty = 1 } } },
		{ id = 2, name = "Bolt of Linen Cloth", learned = true, output = 20, outputQty = 1, reagents = { { itemID = 21, qty = 2 } } },
		{ id = 3, name = "Black Silk Pack", learned = false, output = 11, reagents = { { itemID = 22, qty = 5 }, { itemID = 31, qty = 1 } } },
		{ id = 4, name = "Bolt of Silk Cloth", learned = true, output = 22, reagents = { { itemID = 23, qty = 4 } } },
		{ id = 5, name = "Big Bag", output = 12, reagents = { { itemID = 21, qty = 3 } } },
	}
	local opts = { nameOf = function(id) return NAMES[id] end, vendorPrice = function(id) return PRICE[id], id == 31 end,
		tip = 20, level = 30, extra = { ["Big Bag"] = true, ["Not There"] = true } }
	local rows, missing = O.Build(list, opts)
	eq(#rows, 3, "two of the usual bags, plus a bag marked as a product")
	eq(rows[1].name, "Red Linen Bag", "linen first")
	eq(#rows[1].bring, 1, "only the cloth is brought")
	eq(rows[1].bring[1].name, "Linen Cloth", "bolts are broken down into cloth")
	eq(rows[1].bring[1].qty, 8, "4 bolts at 2 cloth each are 8 cloth")
	eq(#rows[1].vendor, 2, "thread and dye come from the vendor")
	eq(rows[1].vendorCost, 60, "10c thread + 50c dye")
	eq(rows[1].fee, 100, "60c and a 20% tip is 72c, rounded up to 1s")
	eq(rows[1].estimated, true, "the dye price is only an estimate")
	eq(rows[1].fits, false, "level 30 has moved past linen")
	eq(rows[2].fits, true, "silk suits level 30")
	eq(rows[2].learned, false, "not learned is shown, not hidden")
	eq(rows[2].bring[1].qty, 20, "5 bolts of silk are 20 silk cloth")
	eq(rows[3].name, "Big Bag", "products come after the usual bags")
	eq(rows[3].min, nil, "a product has no level range")
	eq(#missing, 6, "bags not in the recipe list are named")
	eq(O.Fee(0, 20), 0, "no vendor mats, no fee")
	eq(O.Fee(1000, 20), 1200, "10s and 20% is 12s")
	eq(O.Fee(1001, 0), 1100, "rounded up to a whole silver")

	-- a part made two at a time: 3 needed is two crafts
	local two = O.RawMats({ reagents = { { itemID = 20, qty = 3 } } }, { [20] = { outputQty = 2, reagents = { { itemID = 21, qty = 5 } } } })
	eq(two[1].qty, 10, "two crafts of 5 cloth")
	-- recipes that make each other do not loop forever
	local loop = { { id = 1, name = "Red Linen Bag", output = 10, reagents = { { itemID = 20, qty = 1 } } },
		{ id = 2, name = "X", output = 20, reagents = { { itemID = 10, qty = 1 } } } }
	eq(#O.Build(loop, opts), 1, "a loop between recipes still ends")

	eq(O.MatsText({ { qty = 1, name = "A" }, { qty = 2, name = "B" }, { qty = 3, name = "C" } }), "1 A, 2 B and 3 C", "list wording")
	eq(O.Text(rows[1], { profession = "Tailoring", itemLink = "[LINK]" }),
		"Tailoring: Red Linen Bag makes [LINK]. Bring 8 Linen Cloth + 1s for Coarse Thread and Red Dye and a tip, and I'll make it right here!",
		"the offer line")
	local t = O.Text(rows[1], { recipeLink = ("x"):rep(200), itemLink = "[LINK]" })
	eq(t:find("xxx", 1, true), nil, "a recipe link that does not fit is swapped for its name")
	eq(t:find("[LINK]", 1, true) ~= nil, true, "the item link is kept when it fits")
	eq(O.Text(rows[1], { template = "{item} {size}!", itemLink = "I" }), "I !", "own wording; no size when unknown")
	local none, why = O.Text(rows[1], { template = ("z"):rep(300) })
	eq(none, nil, "too long for chat")
	eq(why ~= nil, true, "and says why")

	-- an offer placed in the chat box switches tracking on, and replies become leads about that bag
	fresh()
	eq(M.RecordOffer("Red Linen Bag", 5000), true, "tracking switched on")
	local on, capturing = M.TrackingState(5000)
	eq(on and capturing, true, "whispers are captured after an offer")
	local lead = M.OnWhisper("Newbie-Stormrage", "how much for the bag?", 5010)
	eq(lead.offer, "Red Linen Bag", "the lead remembers the bag offered")
	eq(lead.post, nil, "an offer is not a saved post")
	local p2 = M.SavePost(nil, "Ad", "WTS bags", { SAY = true })
	M.RecordSend(p2, "SAY", 5020, "Barrens")
	eq(DB.R.tracking.offer, nil, "a post afterwards takes over")
	DB.settings.autoTrack = false
	DB.R.tracking = { on = false }
	eq(M.RecordOffer("Red Linen Bag", 5030), false, "tracking stays off when posting is set not to switch it on")
end

print(("test_logic: %d checks passed"):format(count))
