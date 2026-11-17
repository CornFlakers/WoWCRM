-- Tests for the files that hold no game API: Util, DB, Model.
local ns = {}
for _, f in ipairs({ "Util.lua", "DB.lua", "Model.lua", "Catalog.lua" }) do
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

-- settings floor and data surviving a reload
local saved = DB.Init({ settings = { minGap = 1 } }, "R")
eq(saved.settings.minGap, DB.MIN_GAP_FLOOR, "gap floor enforced")
M.SavePost(nil, "Keep", "me", { SAY = true })
M.SetTracking(true, T)
DB.Init(saved, "R")
eq(#DB.R.posts, 1, "data kept across re-init")
eq(DB.R.tracking.on, true, "tracking kept across a reload")

print(("test_logic: %d checks passed"):format(count))
