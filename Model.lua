-- Business rules: posts, tracking, leads, contacts, orders, value, referrals.
-- No game API in this file; time is passed in so tests can control it.
local _, ns = ...
local U, DB = ns.Util, ns.DB
local M = {}
ns.Model = M

M.cursor = {} -- per-post position in the channel rotation (session only)

local function R() return DB.R end

function M.NewId()
	local id = R().nextId
	R().nextId = id + 1
	return id
end

local function findById(list, id)
	for i, v in ipairs(list) do
		if v.id == id then return v, i end
	end
end

-- ---------------------------------------------------------------- posts

function M.GetPost(id) return findById(R().posts, id) end

-- ---------------------------------------------------------------- who posts what
-- Posts are written in one character's voice, so each belongs to a character (its key) or to
-- "*" (any character may post it). A post with no owner yet is not posted by anyone until it is
-- given one. M.me is the character playing now; it is set at login.

M.ANY = "*"

function M.CanPost(post)
	return post ~= nil and post.owner ~= nil and (post.owner == M.ANY or post.owner == M.me)
end

-- The posts this character may send, in list order.
function M.PostsFor()
	local out = {}
	for _, p in ipairs(R().posts) do
		if M.CanPost(p) then out[#out + 1] = p end
	end
	return out
end

-- A copy of any post (another character's, say) that belongs to the character playing now.
function M.CopyPost(id)
	local src = M.GetPost(id)
	if not src then return nil, "Pick a post to copy." end
	local targets = {}
	for k in pairs(src.targets) do targets[k] = true end
	return M.SavePost(nil, src.name .. " (" .. (U.SplitKey(M.me or "me")) .. ")", src.text, targets, M.me)
end

function M.UnassignedPosts()
	local n = 0
	for _, p in ipairs(R().posts) do if p.owner == nil then n = n + 1 end end
	return n
end

function M.AssignPosts(owner)
	local n = 0
	for _, p in ipairs(R().posts) do
		if p.owner == nil then p.owner = owner; n = n + 1 end
	end
	return n
end

-- Why this character cannot send this post, in words; nil when it can.
function M.OwnerProblem(post)
	if M.CanPost(post) then return nil end
	if not post or post.owner == nil then
		return "This post is not given to a character yet. Choose who posts it on the Posts tab."
	end
	return "This post is written for " .. U.Display(post.owner, DB.realm) .. ". Log in as them, or set it to any character on the Posts tab."
end

-- owner: a character key or M.ANY. Left out, a new post belongs to the character writing it.
function M.SavePost(id, name, text, targets, owner)
	name, text = U.Trim(name), U.Trim(text)
	if name == "" then return nil, "Give the post a name." end
	if text == "" then return nil, "The message is empty." end
	if U.ByteLen(text) > ns.MAX_CHAT_BYTES then
		return nil, ("The message is %d bytes; chat allows %d."):format(U.ByteLen(text), ns.MAX_CHAT_BYTES)
	end
	local t, any = {}, false
	for _, k in ipairs(ns.TARGETS) do
		if targets and targets[k] then t[k] = true; any = true end
	end
	if not any then return nil, "Pick at least one channel." end

	local post = id and M.GetPost(id)
	if not post then
		post = { id = M.NewId(), created = U.Now(), owner = M.me }
		table.insert(R().posts, post)
	end
	post.name, post.text, post.targets = name, text, t
	if owner ~= nil then post.owner = owner end
	return post
end

function M.DeletePost(id)
	local _, i = M.GetPost(id)
	if i then table.remove(R().posts, i) end
end

-- Seconds before this channel can be posted to again. Public channels wait for two things:
-- their own gap since they were last used, and a pause after any public post at all, so that
-- one advert never lands in Yell, General and Trade within seconds of each other.
function M.GapRemaining(target, now)
	local r = R()
	local left = 0
	local last = r.lastSent[target]
	if last then
		local gap = 2
		if ns.PUBLIC_TARGET[target] then
			gap = DB.settings.minGap
			local c = M.RunningCampaign(now)
			if c then gap = math.max(gap, c.interval * 60) end
		end
		left = gap - (now - last)
	end
	if ns.PUBLIC_TARGET[target] and r.lastPublic then
		left = math.max(left, (DB.settings.publicSpacing or 0) * 60 - (now - r.lastPublic))
	end
	return left > 0 and math.ceil(left) or 0
end

-- Which channel the next click on this post would use.
-- avail(target) -> ok, reason
function M.NextTarget(post, avail, now)
	local n = #ns.TARGETS
	local start = M.cursor[post.id] or 0
	local firstReason
	for i = 1, n do
		local idx = ((start + i - 1) % n) + 1
		local t = ns.TARGETS[idx]
		if post.targets[t] then
			local ok, why = avail(t)
			if ok then
				local gap = M.GapRemaining(t, now)
				if gap > 0 then ok, why = false, ("wait %ds"):format(gap) end
			end
			if ok then return t end
			firstReason = firstReason or (ns.TARGET_LABEL[t] .. ": " .. (why or "unavailable"))
		end
	end
	return nil, firstReason or "No channels selected."
end

function M.RecordSend(post, target, now, zone)
	local r = R()
	local c = M.ActiveCampaign(now)
	local cid = (c and U.Contains(c.posts, post.id)) and c.id or nil
	r.lastSent[target] = now
	if ns.PUBLIC_TARGET[target] then r.lastPublic = now end
	M.cursor[post.id] = U.Contains(ns.TARGETS, target) or 0
	r.lastPost = { id = post.id, time = now, campaign = cid }
	local log = r.postLog
	log[#log + 1] = { post = post.id, target = target, time = now, zone = zone, campaign = cid, character = M.me }
	while #log > 500 do table.remove(log, 1) end
	local hour = U.Hour(now)
	r.sendHours[hour] = (r.sendHours[hour] or 0) + 1
	if cid then c.sendsByPost[post.id] = (c.sendsByPost[post.id] or 0) + 1 end
	if r.tracking.on then
		r.tracking.post, r.tracking.postTime, r.tracking.campaign = post.id, now, cid
	end
end

-- ---------------------------------------------------------------- one-button cycle
-- The quick-post bar's big button: each tap sends the next post to the next channel in turn
-- (General, Trade, and Yell when ticked), skipping channels you are not in, and respecting the
-- pause between public posts. Where it is in the turn is kept for this session only.

M.cycleState = { post = 0, chan = 0 }

-- Posts meant for public channels. Posts ticked only for Guild or Party stay out of the cycle.
function M.CyclePosts()
	local out = {}
	for _, p in ipairs(R().posts) do
		local t = p.targets
		if M.CanPost(p) and (t.SAY or t.YELL or t.GENERAL or t.TRADE) then out[#out + 1] = p end
	end
	return out
end

-- enabled: channel -> true.  avail(channel) -> ok.
-- Returns post, channel, channel's place in the turn; or nil, nil, seconds to wait, reason.
function M.CycleNext(enabled, avail, now)
	local posts = M.CyclePosts()
	if #posts == 0 then return nil, nil, nil, "No posts for Say, Yell, General or Trade yet." end
	local st, n = M.cycleState, #ns.CYCLE_CHANNELS
	local wait
	for i = 1, n do
		local idx = ((st.chan + i - 1) % n) + 1
		local t = ns.CYCLE_CHANNELS[idx]
		if enabled[t] and avail(t) then
			local g = M.GapRemaining(t, now)
			if g == 0 then return posts[(st.post % #posts) + 1], t, idx end
			if not wait or g < wait then wait = g end
		end
	end
	if wait then return nil, nil, wait end
	return nil, nil, nil, "None of the ticked channels is available here."
end

function M.CycleAdvance(post, chanIdx)
	for i, p in ipairs(M.CyclePosts()) do
		if p.id == post.id then M.cycleState.post = i end
	end
	M.cycleState.chan = chanIdx or M.cycleState.chan
end

-- ---------------------------------------------------------------- tracking

function M.SetTracking(on, now)
	local r = R()
	r.tracking = { on = on and true or false, since = on and now or nil }
	-- A post made just before switching on still counts.
	if on and r.lastPost and now - r.lastPost.time <= 300 and M.GetPost(r.lastPost.id) then
		r.tracking.post, r.tracking.postTime, r.tracking.campaign = r.lastPost.id, r.lastPost.time, r.lastPost.campaign
	end
end

-- Returns: on, capturing, minutesLeft
-- While a campaign is running, tracking stays on. Otherwise it switches itself off some
-- time after the last post, so late replies to a finished campaign are still caught.
function M.TrackingState(now)
	local t = R().tracking
	if not t.on then return false, false end
	local c = M.ActiveCampaign(now)
	if c then return true, t.post ~= nil, math.ceil((c.ends - now) / 60) end
	local limit = DB.settings.trackAutoOff or 0
	if limit > 0 then
		local ref = t.postTime or t.since or now
		if now - ref > limit * 60 then
			R().tracking = { on = false }
			return false, false
		end
		return true, t.post ~= nil, math.ceil((limit * 60 - (now - ref)) / 60)
	end
	return true, t.post ~= nil
end

-- ---------------------------------------------------------------- contacts

function M.GetContact(key) return key and R().contacts[key] or nil end

function M.EnsureContact(key, now, sourcePost)
	local c = R().contacts[key]
	if c then return c, false end
	c = { key = key, status = "lead", tags = "", notes = "", firstSeen = now, lastContact = now, sourcePost = sourcePost }
	R().contacts[key] = c
	return c, true
end

-- Finds a contact from typed text: exact key, then name without realm, ignoring case.
function M.FindContact(text)
	text = U.Trim(text)
	if text == "" then return nil end
	local key = U.NormName(text, DB.realm)
	if R().contacts[key] then return R().contacts[key] end
	local low = text:lower()
	for k, c in pairs(R().contacts) do
		if k:lower() == low or U.SplitKey(k):lower() == low then return c end
	end
end

function M.SetReferrer(key, refKey)
	local c = M.GetContact(key)
	if not c then return nil, "Unknown contact." end
	if not refKey or refKey == "" then c.referredBy = nil; return true end
	if refKey == key then return nil, "A contact cannot refer themselves." end
	if not M.GetContact(refKey) then return nil, "The referrer is not a contact yet." end
	local seen, cur = {}, refKey
	while cur and not seen[cur] do
		if cur == key then return nil, "That would make a referral loop." end
		seen[cur] = true
		cur = R().contacts[cur] and R().contacts[cur].referredBy
	end
	c.referredBy = refKey
	return true
end

function M.DeleteContact(key)
	local r = R()
	r.contacts[key] = nil
	for i = #r.leads, 1, -1 do if r.leads[i].contact == key then table.remove(r.leads, i) end end
	for i = #r.orders, 1, -1 do if r.orders[i].contact == key then table.remove(r.orders, i) end end
	for _, c in pairs(r.contacts) do if c.referredBy == key then c.referredBy = nil end end
end

-- ---------------------------------------------------------------- two-part names
-- On this client characters have a first and a last name ("Rosa Vell"). Whispers give the
-- whole name, but when the game is asked for a unit's name (a trade partner, your target) it can
-- hand the last name back where a realm would normally be. These helpers put the name together.

-- Realms known to be real: ours, every realm we have data for, and the realm part of any contact
-- whose name has a space (those keys came whole from a whisper).
function M.KnownRealms()
	local known = { [DB.realm] = true }
	for k in pairs(DB.db and DB.db.realms or {}) do known[k] = true end
	for key in pairs(R().contacts) do
		local n, r = U.SplitKey(key)
		if r and n:find(" ", 1, true) then known[r] = true end
	end
	return known
end

-- name and second as the game returned them -> contact key.
function M.JoinName(name, second, known)
	if type(second) ~= "string" or second == "" then return U.NormName(name, DB.realm) end
	known = known or M.KnownRealms()
	if known[(second:gsub("[%s%-]", ""))] then return U.NormName(name .. "-" .. second, DB.realm) end
	return U.NormName(name .. " " .. second, DB.realm)
end

local STATUS_RANK = { lead = 1, customer = 2, ["repeat"] = 3, vip = 4, ["do not contact"] = 5, ignored = 6 }

-- Contacts saved under a split name ("Rosa-Vell") are moved to the whole name
-- ("Rosa Vell-<realm>"), merging with the contact from the whisper when there is one.
-- Returns how many were repaired.
function M.RepairSplitNames()
	local r, known, moves = R(), M.KnownRealms(), {}
	for key in pairs(r.contacts) do
		local n, realm = U.SplitKey(key)
		if realm and not known[realm] and not n:find(" ", 1, true) then
			moves[key] = U.NormName(n .. " " .. realm, DB.realm)
		end
	end
	local fixed = 0
	for old, new in pairs(moves) do
		local from, to = r.contacts[old], r.contacts[new]
		if to then
			if (STATUS_RANK[from.status] or 0) > (STATUS_RANK[to.status] or 0) then to.status = from.status end
			to.firstSeen = math.min(to.firstSeen or from.firstSeen or 0, from.firstSeen or to.firstSeen or 0)
			to.lastContact = math.max(to.lastContact or 0, from.lastContact or 0)
			if (from.outreach or 0) > 0 then to.outreach = (to.outreach or 0) + from.outreach end
			if (from.lastOutreach or 0) > (to.lastOutreach or 0) then to.lastOutreach, to.lastTemplate = from.lastOutreach, from.lastTemplate end
			if (from.notes or "") ~= "" then to.notes = ((to.notes or "") ~= "" and (to.notes .. "\n") or "") .. from.notes end
			if (to.tags or "") == "" then to.tags = from.tags end
			to.referredBy = to.referredBy or from.referredBy
			to.sourcePost = to.sourcePost or from.sourcePost
		else
			from.key = new
			r.contacts[new] = from
		end
		r.contacts[old] = nil
		for _, o in ipairs(r.orders) do if o.contact == old then o.contact = new end end
		for _, l in ipairs(r.leads) do if l.contact == old then l.contact = new end end
		for _, m in ipairs(r.mailLog) do if m.contact == old then m.contact = new end end
		for _, c in pairs(r.contacts) do if c.referredBy == old then c.referredBy = new end end
		fixed = fixed + 1
	end
	return fixed
end

-- Orders saved by the very first version listed several items as one line
-- ("Red Mageweave Bag, Red Mageweave Bag"). Splits them into one line per item.
function M.RepairJoinedItems()
	local fixed = 0
	for _, o in ipairs(R().orders) do
		local out, changed = {}, false
		for _, l in ipairs(o.items or {}) do
			if not l.name:find("|H", 1, true) and l.name:find(", ", 1, true) then
				changed = true
				local byName, order = {}, {}
				for part in (l.name .. ", "):gmatch("(.-), ") do
					local q, rest = part:match("^(%d+)x (.+)$")
					local name, qty = rest or part, tonumber(q) or 1
					if not byName[name] then
						local linkName = l.link and l.link:match("%[(.-)%]")
						byName[name] = { name = name, qty = 0, link = (linkName == name) and l.link or nil }
						order[#order + 1] = byName[name]
					end
					byName[name].qty = byName[name].qty + qty * (l.qty or 1)
				end
				for _, line in ipairs(order) do out[#out + 1] = line end
			else
				out[#out + 1] = l
			end
		end
		if changed then o.items = out; fixed = fixed + 1 end
	end
	return fixed
end

-- What a contact has bought: orders, paid orders, lifetime value, and the latest order.
function M.PurchaseSummary(key)
	local orders = M.OrdersFor(key)
	local ltv, paid = M.LTV(key)
	local done = 0
	for _, o in ipairs(orders) do
		if o.status == "paid" or o.status == "delivered" then done = done + 1 end
	end
	return { orders = #orders, done = done, paid = paid, value = ltv, latest = orders[1] }
end

-- ---------------------------------------------------------------- leads

-- An incoming whisper. Returns lead, isNewContact; or nil when it is not captured.
function M.OnWhisper(key, text, now)
	local on, capturing = M.TrackingState(now)
	if not on or not capturing then return nil end
	local t = R().tracking
	local existing = R().contacts[key]
	if existing and existing.status == "ignored" then return nil end

	local c, isNew = M.EnsureContact(key, now, t.post)
	c.lastContact = now
	for _, lead in ipairs(R().leads) do
		if lead.contact == key and lead.status == "open" and lead.post == t.post then
			lead.count = lead.count + 1
			lead.time = now
			if #lead.text < 500 then lead.text = lead.text .. " | " .. text end
			return lead, false
		end
	end
	local lead = { id = M.NewId(), contact = key, post = t.post, campaign = t.campaign, sentAt = t.postTime,
		text = text, time = now, status = "open", count = 1 }
	table.insert(R().leads, lead)
	return lead, isNew
end

function M.GetLead(id) return findById(R().leads, id) end

function M.SetLeadStatus(id, status)
	local lead = M.GetLead(id)
	if lead then lead.status = status end
end

-- ---------------------------------------------------------------- orders
-- An order holds:
--   items    what I gave the customer            { name, link, qty }
--   received what the customer gave me in goods  { name, link, qty, value (copper each), kind }
--            kind "mats"    = materials supplied for the job (not income)
--            kind "payment" = goods given as payment or a tip (income, at their value)
--   price    gold received (or quoted)

function M.GetOrder(id) return findById(R().orders, id) end

-- A new order belongs to the post (and campaign) behind the customer's most recent lead.
local function attribute(o)
	local best
	for _, l in ipairs(R().leads) do
		if l.contact == o.contact and (not best or l.time >= best.time) then best = l end
	end
	if best then
		o.post, o.campaign, o.sentAt = best.post, best.campaign, best.sentAt
	else
		local c = M.GetContact(o.contact)
		o.post = c and c.sourcePost or nil
	end
end

local function cleanLines(lines, received)
	local out = {}
	for _, l in ipairs(lines or {}) do
		local name = U.Trim(l.name)
		if name ~= "" then
			local line = { name = name, link = l.link, qty = math.max(1, math.floor(tonumber(l.qty) or 1)) }
			if received then
				line.value = math.max(0, math.floor((tonumber(l.value) or 0) + 0.5))
				line.kind = l.kind == "mats" and "mats" or "payment"
				line.source = l.source
			end
			out[#out + 1] = line
		end
	end
	return out
end

-- "2x Silk Bag, Mageweave Bag"
function M.Summary(lines, max)
	local parts = {}
	for _, l in ipairs(lines or {}) do
		parts[#parts + 1] = (l.qty > 1 and (l.qty .. "x ") or "") .. l.name
	end
	return U.Shorten(table.concat(parts, ", "), max or 120)
end

function M.OrderTitle(o, max)
	if o.desc and o.desc ~= "" then return U.Shorten(o.desc, max or 120) end
	if #o.items > 0 then return M.Summary(o.items, max) end
	return "Job in progress"
end

-- Returns gold, value of goods received as payment, value of materials supplied.
function M.OrderValue(o)
	local goods, mats = 0, 0
	for _, l in ipairs(o.received) do
		local v = (l.value or 0) * l.qty
		if l.kind == "mats" then mats = mats + v else goods = goods + v end
	end
	return o.price, goods, mats
end

local function doneCount(key)
	local done = 0
	for _, o in ipairs(R().orders) do
		if o.contact == key and (o.status == "paid" or o.status == "delivered") then done = done + 1 end
	end
	return done
end

-- A lead becomes a customer once something has been delivered or paid for (free jobs count).
local function autoStatus(key)
	local c = M.GetContact(key)
	if not c then return end
	local done = doneCount(key)
	if c.status == "lead" and done >= 1 then c.status = "customer" end
	if c.status == "customer" and done >= 2 then c.status = "repeat" end
end

-- Brings every contact's status up to date with their orders.
function M.RefreshStatuses()
	for key in pairs(R().contacts) do autoStatus(key) end
end

local function closeLeads(key)
	for _, lead in ipairs(R().leads) do
		if lead.contact == key and lead.status == "open" then lead.status = "won" end
	end
end

local function setStatus(o, status, now)
	if status == "paid" and o.status ~= "paid" then o.paidAt = now end
	if status ~= "paid" then o.paidAt = nil end
	o.status = status
end

-- f: contact (key), type, desc (optional title), items, received, price (copper), status, notes
function M.SaveOrder(id, f, now)
	if not f.contact or f.contact == "" then return nil, "Choose a contact." end
	local price = tonumber(f.price)
	if not price or price < 0 then return nil, "The gold amount is not valid." end
	local status = f.status or "quoted"
	if not U.Contains(ns.ORDER_STATUS, status) then return nil, "Unknown order status." end
	local otype = f.type or "crafted"
	if not U.Contains(ns.ORDER_TYPE, otype) then return nil, "Unknown order type." end

	local o = id and M.GetOrder(id)
	local items = f.items and cleanLines(f.items) or (o and o.items) or {}
	local received = f.received and cleanLines(f.received, true) or (o and o.received) or {}
	local desc = U.Trim(f.desc)
	if desc == "" and #items == 0 and #received == 0 then
		return nil, "Add at least one item, or give the order a title."
	end

	M.EnsureContact(f.contact, now)
	local isNew = not o
	if isNew then
		o = { id = M.NewId(), created = now }
		table.insert(R().orders, o)
	end
	local oldContact = o.contact
	o.contact, o.type, o.desc = f.contact, otype, desc
	if isNew then attribute(o) end
	o.items, o.received = items, received
	o.price, o.notes, o.updated = math.floor(price + 0.5), f.notes or "", now
	setStatus(o, status, now)

	closeLeads(o.contact)
	autoStatus(o.contact)
	if oldContact and oldContact ~= o.contact then autoStatus(oldContact) end
	return o
end

function M.DeleteOrder(id)
	local _, i = M.GetOrder(id)
	if i then table.remove(R().orders, i) end
end

function M.OrdersFor(key)
	local out = {}
	for _, o in ipairs(R().orders) do
		if o.contact == key then out[#out + 1] = o end
	end
	table.sort(out, function(a, b) if a.created ~= b.created then return a.created > b.created end return a.id > b.id end)
	return out
end

-- The order a follow-up trade most likely belongs to: the contact's most recently
-- touched order that is not cancelled and was touched within the order window.
function M.CurrentOrder(key, now)
	local window = (DB.settings.orderWindow or 60) * 60
	local best
	for _, o in ipairs(R().orders) do
		if o.contact == key and o.status ~= "cancelled" and now - (o.updated or o.created) <= window then
			if not best or (o.updated or o.created) >= (best.updated or best.created) then best = o end
		end
	end
	return best
end

local function mergeLine(list, line)
	for _, l in ipairs(list) do
		if l.name == line.name and l.kind == line.kind and (l.value or 0) == (line.value or 0) then
			l.qty = l.qty + line.qty
			return
		end
	end
	list[#list + 1] = line
end

-- Adds one completed trade to an order (or starts a new order when id is nil).
-- trade: given = items I handed over, received = items they handed over (with value), gold = net gold received.
-- Goods received before anything has been delivered are taken as materials for the job;
-- goods received with or after the delivery are taken as payment. Either can be flipped later.
function M.AddTrade(id, key, trade, now)
	local given = cleanLines(trade.given)
	local received = cleanLines(trade.received, true)
	local gold = math.max(0, math.floor((tonumber(trade.gold) or 0) + 0.5))
	local o = id and M.GetOrder(id)
	local isNew = not o
	M.EnsureContact(key, now)
	if not o then
		o = { id = M.NewId(), created = now, contact = key, type = "crafted", desc = "", items = {}, received = {}, price = 0, notes = "", trades = 0 }
		table.insert(R().orders, o)
		attribute(o)
	end
	local asPayment = #o.items > 0 or #given > 0
	for _, l in ipairs(received) do
		l.kind = asPayment and "payment" or "mats"
		mergeLine(o.received, l)
	end
	for _, l in ipairs(given) do mergeLine(o.items, l) end
	o.price = o.price + gold
	o.trades = (o.trades or 0) + 1
	o.updated = now

	if isNew then
		if #given == 0 and #received == 0 then
			o.type, o.desc = "service", "Service"
		elseif #received == 0 then
			o.type = "goods"
		end
	end

	local _, goods = M.OrderValue(o)
	if o.status ~= "paid" then
		if #o.items > 0 or o.type == "service" then
			setStatus(o, (o.price + goods) > 0 and "paid" or "delivered", now)
		else
			setStatus(o, "in progress", now)
		end
	end
	closeLeads(key)
	autoStatus(key)
	return o
end

-- Lifetime value: gold plus the value of goods received as payment, on paid orders.
-- Returns total, paid count, total count, gold part, goods part.
function M.LTV(key)
	local gold, goods, paid, all = 0, 0, 0, 0
	for _, o in ipairs(R().orders) do
		if o.contact == key then
			all = all + 1
			if o.status == "paid" then
				local g, v = M.OrderValue(o)
				gold, goods, paid = gold + g, goods + v, paid + 1
			end
		end
	end
	return gold + goods, paid, all, gold, goods
end

-- Returns number of people this contact referred, and what those people have paid.
function M.Referrals(key)
	local n, revenue = 0, 0
	for k, c in pairs(R().contacts) do
		if c.referredBy == key then
			n = n + 1
			revenue = revenue + (M.LTV(k))
		end
	end
	return n, revenue
end

function M.Stats()
	local r = R()
	local s = { revenue = 0, gold = 0, goods = 0, mats = 0, paidOrders = 0, openOrders = 0, contacts = 0, customers = 0, openLeads = 0, top = {}, referrers = {}, posts = {} }
	local byPost = {}
	for _, p in ipairs(r.posts) do
		byPost[p.id] = { name = p.name, sends = 0, leads = 0, revenue = 0, gold = 0, goods = 0, sold = {}, soldNames = {} }
		s.posts[#s.posts + 1] = byPost[p.id]
	end
	for _, e in ipairs(r.postLog) do
		if byPost[e.post] then byPost[e.post].sends = byPost[e.post].sends + 1 end
	end
	for _, l in ipairs(r.leads) do
		if l.status == "open" then s.openLeads = s.openLeads + 1 end
		if byPost[l.post] then byPost[l.post].leads = byPost[l.post].leads + 1 end
	end
	for _, o in ipairs(r.orders) do
		local c = r.contacts[o.contact]
		local ps = byPost[o.post] or (c and byPost[c.sourcePost])
		local gold, goods, mats = M.OrderValue(o)
		if o.status == "paid" then
			s.gold, s.goods, s.mats = s.gold + gold, s.goods + goods, s.mats + mats
			s.paidOrders = s.paidOrders + 1
			if ps then ps.gold, ps.goods = ps.gold + gold, ps.goods + goods end
		elseif o.status ~= "cancelled" then
			s.openOrders = s.openOrders + 1
		end
		-- what each post ended up selling (anything actually handed over)
		if ps and o.status ~= "cancelled" and o.status ~= "quoted" then
			for _, l in ipairs(o.items) do
				if not ps.soldNames[l.name] then
					ps.soldNames[l.name] = { name = l.name, qty = 0 }
					ps.sold[#ps.sold + 1] = ps.soldNames[l.name]
				end
				ps.soldNames[l.name].qty = ps.soldNames[l.name].qty + l.qty
			end
		end
	end
	s.revenue = s.gold + s.goods
	for _, ps in ipairs(s.posts) do
		ps.revenue, ps.soldNames = ps.gold + ps.goods, nil
		table.sort(ps.sold, function(a, b) if a.qty ~= b.qty then return a.qty > b.qty end return a.name < b.name end)
	end
	for k in pairs(r.contacts) do
		s.contacts = s.contacts + 1
		local ltv, paid = M.LTV(k)
		if paid > 0 then
			s.customers = s.customers + 1
			s.top[#s.top + 1] = { key = k, value = ltv }
		end
		local n, rev = M.Referrals(k)
		if n > 0 then s.referrers[#s.referrers + 1] = { key = k, count = n, value = rev } end
	end
	table.sort(s.top, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.key < b.key end)
	table.sort(s.referrers, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.key < b.key end)
	return s
end

-- ---------------------------------------------------------------- mail templates

function M.GetTemplate(id) return findById(R().mailTemplates, id) end

function M.SaveTemplate(id, name, subject, body)
	name = U.Trim(name)
	if name == "" then return nil, "Give the template a name." end
	if U.Trim(subject) == "" then return nil, "The subject is empty." end
	local t = id and M.GetTemplate(id)
	if not t then
		t = { id = M.NewId() }
		table.insert(R().mailTemplates, t)
	end
	t.name, t.subject, t.body = name, U.Trim(subject), body or ""
	return t
end

function M.DeleteTemplate(id)
	local _, i = M.GetTemplate(id)
	if i then table.remove(R().mailTemplates, i) end
end

function M.LogMail(key, subject, now)
	local c = M.GetContact(key)
	if not c then return false end
	c.lastContact = now
	local log = R().mailLog
	log[#log + 1] = { contact = key, subject = subject, time = now }
	while #log > 500 do table.remove(log, 1) end
	return true
end

-- ---------------------------------------------------------------- campaigns
-- A campaign is a selling session: a set of posts, a time window, and a minimum wait
-- between posts to the same public channel. The add-on never posts by itself; a campaign
-- works out what is due next and the player clicks to send it.

function M.GetCampaign(id) return id and findById(R().campaigns, id) or nil end

-- The running campaign, without changing anything.
function M.RunningCampaign(now)
	local c = M.GetCampaign(R().activeCampaign)
	if c and c.status == "running" and now < c.ends then return c end
end

function M.EndCampaign(now)
	local c = M.GetCampaign(R().activeCampaign)
	R().activeCampaign = nil
	if c and c.status == "running" then
		c.status = "ended"
		c.endedAt = math.min(now, c.ends)
	end
	return c
end

-- The running campaign; closes it when its time is up. The second value is a campaign
-- that has just finished on this call.
function M.ActiveCampaign(now)
	local c = M.GetCampaign(R().activeCampaign)
	if not c or c.status ~= "running" then return nil end
	if now >= c.ends then
		M.EndCampaign(now)
		return nil, c
	end
	return c
end

function M.StartCampaign(name, postIds, minutes, interval, now)
	minutes = math.floor(tonumber(minutes) or 0)
	interval = math.floor(tonumber(interval) or 0)
	if minutes < 1 then return nil, "Set how many minutes the campaign runs for." end
	if interval < 1 then return nil, "The wait between posts must be at least 1 minute." end
	local posts = {}
	for _, id in ipairs(postIds or {}) do
		if M.CanPost(M.GetPost(id)) then posts[#posts + 1] = id end
	end
	if #posts == 0 then return nil, "Pick at least one post for the campaign." end
	name = U.Trim(name)
	if name == "" then name = "Campaign" end

	M.EndCampaign(now)
	local c = {
		id = M.NewId(), name = name, started = now, ends = now + minutes * 60, minutes = minutes,
		interval = interval, posts = posts, turn = 1, status = "running", sendsByPost = {}, character = M.me,
	}
	table.insert(R().campaigns, c)
	R().activeCampaign = c.id
	M.SetTracking(true, now)
	return c
end

-- What to post next: post, channel. When nothing is due: nil, nil, seconds until something is.
function M.CampaignNext(c, avail, now)
	local n, wait = #c.posts, nil
	for i = 0, n - 1 do
		local idx = ((c.turn - 1 + i) % n) + 1
		local post = M.GetPost(c.posts[idx])
		if M.CanPost(post) then
			local target = M.NextTarget(post, avail, now)
			if target then return post, target, 0 end
			for _, t in ipairs(ns.TARGETS) do
				if post.targets[t] and avail(t) then
					local g = M.GapRemaining(t, now)
					if g > 0 and (not wait or g < wait) then wait = g end
				end
			end
		end
	end
	return nil, nil, wait
end

-- After a send: once a post has nothing more it can send right now, the next post gets its turn.
function M.CampaignAdvance(c, post, avail, now)
	if not M.NextTarget(post, avail, now) then
		local idx = U.Contains(c.posts, post.id) or c.turn
		c.turn = (idx % #c.posts) + 1
	end
end

-- The funnel for one campaign: per post, how often it was posted, the leads it brought,
-- the orders those leads placed, and what they paid in gold and in goods.
function M.CampaignReport(id)
	local c = M.GetCampaign(id)
	if not c then return nil end
	local rep = { campaign = c, sends = 0, leads = 0, orders = 0, gold = 0, goods = 0, posts = {} }
	local byPost = {}
	for _, pid in ipairs(c.posts) do
		local post = M.GetPost(pid)
		local row = { name = post and post.name or "(deleted post)", sends = (c.sendsByPost[pid] or 0),
			leads = 0, orders = 0, gold = 0, goods = 0, sold = {}, soldNames = {} }
		byPost[pid] = row
		rep.posts[#rep.posts + 1] = row
		rep.sends = rep.sends + row.sends
	end
	for _, l in ipairs(R().leads) do
		if l.campaign == id then
			rep.leads = rep.leads + 1
			if byPost[l.post] then byPost[l.post].leads = byPost[l.post].leads + 1 end
		end
	end
	for _, o in ipairs(R().orders) do
		if o.campaign == id and o.status ~= "cancelled" then
			local row = byPost[o.post]
			rep.orders = rep.orders + 1
			if row then row.orders = row.orders + 1 end
			if o.status == "paid" then
				local gold, goods = M.OrderValue(o)
				rep.gold, rep.goods = rep.gold + gold, rep.goods + goods
				if row then row.gold, row.goods = row.gold + gold, row.goods + goods end
			end
			if row and o.status ~= "quoted" then
				for _, l in ipairs(o.items) do
					if not row.soldNames[l.name] then
						row.soldNames[l.name] = { name = l.name, qty = 0 }
						row.sold[#row.sold + 1] = row.soldNames[l.name]
					end
					row.soldNames[l.name].qty = row.soldNames[l.name].qty + l.qty
				end
			end
		end
	end
	for _, row in ipairs(rep.posts) do row.soldNames = nil end
	return rep
end

-- How many of each item has been handed over, across all orders: item name -> quantity.
function M.SoldCounts()
	local out = {}
	for _, o in ipairs(R().orders) do
		if o.status ~= "cancelled" and o.status ~= "quoted" then
			for _, l in ipairs(o.items) do out[l.name] = (out[l.name] or 0) + l.qty end
		end
	end
	return out
end

-- "3:05" or "1:02:00"
function M.Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end

-- Activity by hour of the day: posts sent, and the leads, orders and income that came from
-- posts sent in that hour. Only hours with something to show are returned.
function M.HourReport()
	local rows = {}
	local function row(h)
		rows[h] = rows[h] or { hour = h, sends = 0, leads = 0, orders = 0, income = 0 }
		return rows[h]
	end
	for h, n in pairs(R().sendHours) do row(tonumber(h)).sends = n end
	for _, l in ipairs(R().leads) do
		local r = row(U.Hour(l.sentAt or l.time))
		r.leads = r.leads + 1
	end
	for _, o in ipairs(R().orders) do
		if o.status ~= "cancelled" then
			local r = row(U.Hour(o.sentAt or o.created))
			r.orders = r.orders + 1
			if o.status == "paid" then
				local gold, goods = M.OrderValue(o)
				r.income = r.income + gold + goods
			end
		end
	end
	local out = {}
	for h = 0, 23 do if rows[h] then out[#out + 1] = rows[h] end end
	return out
end

-- "1.5 per post", "40%": plain-language rates for the funnel.
function M.Rate(part, whole, percent)
	if not whole or whole == 0 then return "-" end
	if percent then return ("%d%%"):format(math.floor(part / whole * 100 + 0.5)) end
	return ("%.1f"):format(part / whole)
end

-- ---------------------------------------------------------------- follow-ups when online
-- A contact you promised to get back to. When they are seen online (their friends-list entry
-- shows them logging in, or they speak in chat near you or in a channel), you are alerted, at
-- most once every half hour per person, so you can switch to the right character and close.

M.ALERT_EVERY = 30 * 60

function M.SetFollowUp(key, note, now)
	local c = M.GetContact(key)
	if not c then return nil end
	c.followUp = { since = now, note = U.Trim(note), by = M.me }
	return c.followUp
end

function M.ClearFollowUp(key)
	local c = M.GetContact(key)
	if c then c.followUp = nil end
end

-- Oldest promise first.
function M.OnlineFollowUps()
	local out = {}
	for _, c in pairs(R().contacts) do
		if c.followUp then out[#out + 1] = c end
	end
	table.sort(out, function(a, b)
		if a.followUp.since ~= b.followUp.since then return a.followUp.since < b.followUp.since end
		return a.key < b.key
	end)
	return out
end

-- Contacts this character added to its friends list for follow-ups: key -> true.
function M.Watching(char)
	local r = R()
	char = char or M.me or "?"
	r.watching = r.watching or {}
	r.watching[char] = r.watching[char] or {}
	return r.watching[char]
end

-- A contact was seen online. Returns true when it is time to alert about a follow-up.
function M.SeenOnline(key, now, how)
	local c = M.GetContact(key)
	if not c then return false end
	c.lastSeen, c.lastSeenHow = now, how
	if not c.followUp then return false end
	if c.followUp.alertedAt and now - c.followUp.alertedAt < M.ALERT_EVERY then return false end
	c.followUp.alertedAt = now
	return true
end

-- ---------------------------------------------------------------- follow-up outreach

ns.FOLLOW_FILTERS = { "leads", "customers", "everyone" }

-- A follow-up letter was sent to this contact.
function M.RecordOutreach(key, templateName, now)
	local c = M.GetContact(key)
	if not c then return false end
	c.outreach = (c.outreach or 0) + 1
	c.lastOutreach = now
	c.lastTemplate = templateName
	c.lastContact = now
	return true
end

-- Who to write to next. People never written to come first, then the longest-waiting.
-- Anyone written to within the outreach gap is kept at the bottom and flagged recent.
-- "do not contact" and "ignored" contacts are never listed.
function M.FollowUps(filter, now)
	local gap = (DB.settings.outreachGap or 3) * 86400
	local out = {}
	for k, c in pairs(R().contacts) do
		local isLead = c.status == "lead"
		local isCustomer = c.status == "customer" or c.status == "repeat" or c.status == "vip"
		local wanted = (filter == "leads" and isLead) or (filter == "customers" and isCustomer)
			or (filter == "everyone" and (isLead or isCustomer))
		if wanted then
			out[#out + 1] = { key = k, contact = c, count = c.outreach or 0, last = c.lastOutreach,
				recent = c.lastOutreach ~= nil and now - c.lastOutreach < gap }
		end
	end
	table.sort(out, function(a, b)
		if a.recent ~= b.recent then return not a.recent end
		if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) < (b.last or 0) end
		return a.key < b.key
	end)
	return out
end

-- "never", "today", "3 days ago"
function M.Ago(t, now)
	if not t then return "never" end
	local days = math.floor((now - t) / 86400)
	if days <= 0 then return "today" end
	return days .. (days == 1 and " day ago" or " days ago")
end

-- ---------------------------------------------------------------- export / import

local HEADER, OLD_HEADER = "WOWCRM2", "WOWCRM1"

function M.Export()
	local r, out = R(), { HEADER }
	local function line(...)
		local f = { ... }
		for i = 1, select("#", ...) do f[i] = U.Escape(f[i]) end
		out[#out + 1] = table.concat(f, "\t")
	end
	for _, p in ipairs(r.posts) do
		local t = {}
		for _, k in ipairs(ns.TARGETS) do if p.targets[k] then t[#t + 1] = k end end
		line("P", p.name, p.text, table.concat(t, ","), p.owner)
	end
	local keys = {}
	for k in pairs(r.contacts) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local c = r.contacts[k]
		local src = c.sourcePost and M.GetPost(c.sourcePost)
		line("C", k, c.status, c.tags, c.notes, c.firstSeen, c.lastContact, c.referredBy, src and src.name, c.outreach, c.lastOutreach)
	end
	for _, o in ipairs(r.orders) do
		line("O", o.contact, o.type, o.desc, o.price, o.status, o.created, o.paidAt, o.notes)
		for _, l in ipairs(o.items) do line("S", l.name, l.qty, l.link) end
		for _, l in ipairs(o.received) do line("R", l.name, l.qty, l.value, l.kind, l.link) end
	end
	return table.concat(out, "\n")
end

-- Merges exported text into the current realm. Returns counts table, or nil and an error.
-- Reads the current format and the older one-line-per-order format.
function M.Import(text, now)
	local r = R()
	local lines = {}
	for l in tostring(text or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = l end
	local header = U.Trim(lines[1])
	if header ~= HEADER and header ~= OLD_HEADER then return nil, "This is not WoW CRM export text." end
	local old = header == OLD_HEADER
	local added = { posts = 0, contacts = 0, orders = 0 }
	local postByName, referrers = {}, {}
	for _, p in ipairs(r.posts) do postByName[p.name] = p end
	local function blank(v) if v == "" then return nil end return v end
	local pending -- the order whose S and R lines are still arriving

	local function flush()
		local p = pending
		pending = nil
		if not p then return end
		for _, o in ipairs(r.orders) do
			if o.contact == p.contact and o.created == p.created then return end
		end
		local o = M.SaveOrder(nil, p, p.created)
		if o then
			o.paidAt = p.paidAt or o.paidAt
			added.orders = added.orders + 1
		end
	end

	for i = 2, #lines do
		local f = U.SplitTabs(lines[i])
		local kind = f[1]
		if kind ~= "S" and kind ~= "R" then flush() end
		if kind == "P" and f[2] and not postByName[f[2]] then
			local targets = {}
			for k in (f[4] or ""):gmatch("[^,]+") do targets[k] = true end
			local p = M.SavePost(nil, f[2], f[3], targets, (f[5] and f[5] ~= "") and f[5] or nil)
			if p then postByName[p.name] = p; added.posts = added.posts + 1 end
		elseif kind == "C" and f[2] and f[2] ~= "" then
			local c, isNew = M.EnsureContact(f[2], tonumber(f[6]) or now)
			if isNew then added.contacts = added.contacts + 1 end
			if U.Contains(ns.CONTACT_STATUS, f[3]) then c.status = f[3] end
			c.tags, c.notes = f[4] or "", f[5] or ""
			c.firstSeen = tonumber(f[6]) or c.firstSeen
			c.lastContact = tonumber(f[7]) or c.lastContact
			referrers[f[2]] = blank(f[8])
			local src = postByName[f[9] or ""]
			if src then c.sourcePost = src.id end
			if tonumber(f[10]) then c.outreach = tonumber(f[10]) end
			if tonumber(f[11]) then c.lastOutreach = tonumber(f[11]) end
		elseif kind == "O" and f[2] and f[2] ~= "" then
			if old then
				pending = {
					contact = f[2], type = f[3], desc = "", price = f[6], status = f[7],
					created = tonumber(f[8]) or now, paidAt = tonumber(f[9]), notes = f[10],
					items = { { name = f[4], qty = f[5], link = blank(f[11]) } }, received = {},
				}
			else
				pending = {
					contact = f[2], type = f[3], desc = f[4], price = f[5], status = f[6],
					created = tonumber(f[7]) or now, paidAt = tonumber(f[8]), notes = f[9],
					items = {}, received = {},
				}
			end
		elseif kind == "S" and pending then
			pending.items[#pending.items + 1] = { name = f[2], qty = f[3], link = blank(f[4]) }
		elseif kind == "R" and pending then
			pending.received[#pending.received + 1] = { name = f[2], qty = f[3], value = f[4], kind = f[5], link = blank(f[6]) }
		end
	end
	flush()
	for key, ref in pairs(referrers) do M.SetReferrer(key, ref) end
	return added
end
