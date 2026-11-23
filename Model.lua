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
-- What a post is for; posts saved before purposes existed are for selling.
function M.PostKind(post)
	return (post and ns.KIND_LABEL[post.kind]) and post.kind or "sell"
end

function M.SavePost(id, name, text, targets, owner, kind)
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
	if kind ~= nil then post.kind = ns.KIND_LABEL[kind] and kind or "sell" end
	post.kind = M.PostKind(post)
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
	-- Posting switches tracking on (unless turned off in Options), so replies are never missed.
	if not r.tracking.on and DB.settings.autoTrack ~= false then
		r.tracking = { on = true, since = now }
	end
	if r.tracking.on then
		r.tracking.post, r.tracking.postTime, r.tracking.campaign = post.id, now, cid
		r.tracking.offer = nil
	end
end

-- A bag offer placed in the chat box. You press Enter yourself, so it is not logged as a post,
-- but it counts as one for contact tracking: whispers after it become leads tagged with the bag.
-- Returns false when tracking is off and posting is set not to switch it on.
function M.RecordOffer(name, now)
	local r = R()
	if not r.tracking.on then
		if DB.settings.autoTrack == false then return false end
		r.tracking = { on = true, since = now }
	end
	r.tracking.post, r.tracking.campaign = nil, nil
	r.tracking.offer, r.tracking.postTime = name, now
	return true
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

-- Returns: on, capturing, minutesLeft, secondsLeft
-- While a campaign is running, tracking stays on. Otherwise it switches itself off some
-- time after the last post, so late replies to a finished campaign are still caught.
function M.TrackingState(now)
	local t = R().tracking
	if not t.on then return false, false end
	local c = M.ActiveCampaign(now)
	local capturing = t.post ~= nil or t.offer ~= nil
	if c then return true, capturing, math.ceil((c.ends - now) / 60), math.max(0, c.ends - now) end
	local limit = DB.settings.trackAutoOff or 0
	if limit > 0 then
		local ref = t.postTime or t.since or now
		if now - ref > limit * 60 then
			R().tracking = { on = false }
			return false, false
		end
		local secs = limit * 60 - (now - ref)
		return true, capturing, math.ceil(secs / 60), secs
	end
	return true, capturing
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
	for i = #r.opportunities, 1, -1 do if r.opportunities[i].contact == key then table.remove(r.opportunities, i) end end
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

local STATUS_RANK = { lead = 1, customer = 2, ["repeat"] = 3, vip = 4, ["my character"] = 5, ["do not contact"] = 6, ignored = 7 }

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
			if from.chat then
				to.chat = to.chat or {}
				for _, m in ipairs(from.chat) do to.chat[#to.chat + 1] = m end
				table.sort(to.chat, function(a, b) return a.t < b.t end)
			end
		else
			from.key = new
			r.contacts[new] = from
		end
		r.contacts[old] = nil
		for _, o in ipairs(r.orders) do if o.contact == old then o.contact = new end end
		for _, l in ipairs(r.leads) do if l.contact == old then l.contact = new end end
		for _, o in ipairs(r.opportunities) do if o.contact == old then o.contact = new end end
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

-- One conversation is one lead. A whisper joins the contact's open lead whatever post it was
-- about, or their most recent lead when it was active within this many hours (so "on my way"
-- after an order is made does not start a second lead).
M.LEAD_GAP_HOURS = 12
M.CHAT_KEEP = 200 -- whispers kept per contact

-- Keeps a whisper in the contact's conversation. mine = true for whispers I sent.
function M.LogChat(key, mine, text, now)
	local c = M.GetContact(key)
	if not c then return end
	c.chat = c.chat or {}
	c.chat[#c.chat + 1] = { t = now, me = mine or nil, text = U.Shorten(tostring(text or ""), 255), char = mine and M.me or nil }
	while #c.chat > M.CHAT_KEEP do table.remove(c.chat, 1) end
	c.lastContact = now
end

-- The whispers belonging to a lead: from just before it started until the next lead began.
function M.LeadChat(lead)
	local c = M.GetContact(lead.contact)
	if not c or not c.chat then return {} end
	local from = (lead.started or lead.time) - 1800
	local upto
	for _, l in ipairs(R().leads) do
		local s = l.started or l.time
		if l.contact == lead.contact and l ~= lead and s > (lead.started or lead.time) and (not upto or s < upto) then upto = s end
	end
	local out = {}
	for _, m in ipairs(c.chat) do
		if m.t >= from and (not upto or m.t < upto) then out[#out + 1] = m end
	end
	return out
end

local function conversationLead(key, now)
	local open, recent
	for _, l in ipairs(R().leads) do
		if l.contact == key then
			if l.status == "open" and (not open or l.time > open.time) then open = l end
			if not recent or l.time > recent.time then recent = l end
		end
	end
	if open then return open end
	if recent and now - recent.time <= M.LEAD_GAP_HOURS * 3600 then return recent end
end

-- Adds a word to a contact's tags unless it is already there.
function M.AddTag(contact, word)
	if not contact or not word or word == "" then return end
	local tags = contact.tags or ""
	for w in tags:gmatch("[^,%s]+") do if w:lower() == word:lower() then return end end
	contact.tags = U.Trim(tags) == "" and word or (U.Trim(tags) .. ", " .. word)
end

-- What a lead answered: its purpose, and the post or offer by name.
function M.LeadKind(lead)
	if not lead then return "sell" end
	if ns.KIND_LABEL[lead.kind] then return lead.kind end
	local post = lead.post and M.GetPost(lead.post)
	return post and M.PostKind(post) or "sell"
end

function M.LeadSource(lead)
	if not lead then return nil end
	local post = lead.post and M.GetPost(lead.post)
	return (post and post.name) or lead.source or (lead.offer and (lead.offer .. " offer")) or nil
end

-- An incoming whisper. Returns lead, isNew (a new lead), isNewContact; or nil when it is not captured.
-- Whispers from people already in your contacts are always kept in their conversation.
function M.OnWhisper(key, text, now)
	local existing = R().contacts[key]
	if existing and existing.status == "ignored" then return nil end
	local lead = conversationLead(key, now)
	if lead then
		M.LogChat(key, false, text, now)
		lead.count = (lead.count or 0) + 1
		lead.time = now
		return lead, false, false
	end
	local on, capturing = M.TrackingState(now)
	if not on or not capturing then
		if existing then M.LogChat(key, false, text, now) end
		return nil
	end
	local t = R().tracking
	local contact, isNewContact = M.EnsureContact(key, now, t.post)
	M.LogChat(key, false, text, now)
	-- The post's name and purpose are copied onto the lead, so they survive the post being deleted.
	local post = t.post and M.GetPost(t.post)
	local kind = post and M.PostKind(post) or "sell"
	lead = { id = M.NewId(), contact = key, post = t.post, offer = t.offer, campaign = t.campaign, sentAt = t.postTime,
		kind = kind, source = post and post.name or (t.offer and (t.offer .. " offer")) or nil,
		text = U.Shorten(text, 255), time = now, started = now, status = "open", count = 1 }
	M.AddTag(contact, kind)
	table.insert(R().leads, lead)
	return lead, true, isNewContact
end

-- A whisper I sent. Kept only for people already in my contacts.
function M.OnWhisperSent(key, text, now)
	if not M.GetContact(key) then return false end
	M.LogChat(key, true, text, now)
	return true
end

-- Earlier versions started a new lead for every post a person answered. Folds each person's
-- open leads into their first one. Returns how many leads were folded away.
function M.MergeDuplicateLeads()
	local r, keep, folded = R(), {}, 0
	for i = 1, #r.leads do
		local l = r.leads[i]
		if l.status == "open" then
			local k = keep[l.contact]
			if not k or l.id < k.id then keep[l.contact] = l end
		end
	end
	for i = #r.leads, 1, -1 do
		local l = r.leads[i]
		local k = keep[l.contact]
		if l.status == "open" and k and k ~= l then
			k.count = (k.count or 1) + (l.count or 1)
			k.time = math.max(k.time, l.time)
			k.started = math.min(k.started or k.time, l.started or l.time)
			table.remove(r.leads, i)
			folded = folded + 1
		end
	end
	return folded
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
--   price    gold received
--   quote    the agreed price, for an order started from a lead (optional)
-- An item line marked planned = true is still to be handed over; a trade that hands it over
-- turns it into a delivered line instead of adding a second one.

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
			if not received and l.planned then line.planned = true end
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

-- Item lines handed over, and item lines still to hand over.
function M.ItemCounts(o)
	local done, planned = 0, 0
	for _, l in ipairs(o.items or {}) do
		if l.planned then planned = planned + 1 else done = done + 1 end
	end
	return done, planned
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

-- f: contact (key), type, desc (optional title), items, received, price (copper), status, notes, quote
function M.SaveOrder(id, f, now)
	if not f.contact or f.contact == "" then return nil, "Choose a contact." end
	local price = tonumber(f.price)
	if not price or price < 0 then return nil, "The gold amount is not valid." end
	local quote = tonumber(f.quote)
	if quote and quote <= 0 then quote = nil end
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
	if f.quote ~= nil then o.quote = quote and math.floor(quote + 0.5) or nil end
	-- Marked paid with no gold entered: the agreed price is what was paid.
	if status == "paid" and price == 0 and o.quote then price = o.quote end
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

-- The order a trade most likely belongs to: the contact's newest order that is still open
-- (quoted or in progress), however old; otherwise their most recently touched order that is
-- not cancelled and was touched within the order window.
function M.CurrentOrder(key, now)
	local window = (DB.settings.orderWindow or 60) * 60
	local best
	for _, o in ipairs(R().orders) do
		if o.contact == key and (o.status == "quoted" or o.status == "in progress") then
			if not best or (o.updated or o.created) >= (best.updated or best.created) then best = o end
		end
	end
	if best then return best end
	for _, o in ipairs(R().orders) do
		if o.contact == key and o.status ~= "cancelled" and now - (o.updated or o.created) <= window then
			if not best or (o.updated or o.created) >= (best.updated or best.created) then best = o end
		end
	end
	return best
end

local function mergeLine(list, line)
	for _, l in ipairs(list) do
		if l.name == line.name and l.kind == line.kind and (l.value or 0) == (line.value or 0) and not l.planned == not line.planned then
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
	local asPayment = M.ItemCounts(o) > 0 or #given > 0
	for _, l in ipairs(received) do
		l.kind = asPayment and "payment" or "mats"
		mergeLine(o.received, l)
	end
	for _, l in ipairs(given) do
		-- Handing over a planned item delivers it rather than adding another.
		for i = #o.items, 1, -1 do
			local p = o.items[i]
			if p.planned and p.name == l.name then
				local n = math.min(p.qty, l.qty)
				p.qty = p.qty - n
				if p.qty <= 0 then table.remove(o.items, i) end
				break
			end
		end
		mergeLine(o.items, l)
	end
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
	local done, planned = M.ItemCounts(o)
	if o.status ~= "paid" then
		if planned > 0 then
			setStatus(o, "in progress", now)
		elseif done > 0 or o.type == "service" then
			setStatus(o, (o.price + goods) > 0 and "paid" or "delivered", now)
		else
			setStatus(o, "in progress", now)
		end
	end
	closeLeads(key)
	autoStatus(key)
	return o
end

-- Products marked on the Products tab, with the price a customer is quoted: my price if set,
-- otherwise priceOf(itemID) (the auction or vendor price). Sorted by name.
function M.ProductChoices(priceOf)
	local out = {}
	for key, p in pairs(R().products) do
		if type(p) == "table" and p.name then
			local price = tonumber(p.price) or (priceOf and p.output and priceOf(p.output)) or 0
			out[#out + 1] = { key = key, name = p.name, output = p.output, price = price, mine = p.price ~= nil }
		end
	end
	for _, s in ipairs(R().services) do
		out[#out + 1] = { key = "service:" .. s.name, name = s.name, price = s.price or 0, mine = s.price ~= nil, service = true }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- Turns a lead into an order shell: the item still to hand over, at the agreed price.
-- product: { name, link, price } or nil for an empty order. Returns the order.
function M.LeadToOrder(leadId, product, qty, now)
	local lead = M.GetLead(leadId)
	if not lead then return nil, "That lead no longer exists." end
	qty = math.max(1, math.floor(tonumber(qty) or 1))
	M.EnsureContact(lead.contact, now)
	local o = { id = M.NewId(), created = now, updated = now, contact = lead.contact, type = "crafted", desc = "",
		items = {}, received = {}, price = 0, notes = "", trades = 0, status = "quoted",
		post = lead.post, campaign = lead.campaign, sentAt = lead.sentAt, lead = lead.id }
	if product then
		o.items[1] = { name = product.name, link = product.link, qty = qty, planned = true }
		if (product.price or 0) > 0 then o.quote = product.price * qty end
	end
	table.insert(R().orders, o)
	lead.status, lead.order = "won", o.id
	return o
end

-- ---------------------------------------------------------------- opportunities
-- Something a person needs, written down before there is an order: "Skotor Ironmark needs
-- 5 silver", "Rosa Vell wants a Red Mageweave Bag next week". It is worked (next step, follow-up
-- date, a quote) until it is won, which can turn it into an order, or lost.
--   dir      "theirs" = they need it (from you), "mine" = you need it from them
--   stage    new, working, quoted, won, lost
--   quote    the price you have offered (copper, optional)
--   due      when to follow up next (time, optional); nextStep says what to do then
-- The person can be one of your own characters: the address book is yours, so requests to and
-- from your alts sit next to everyone else's.

local OPEN_STAGE = { new = true, working = true, quoted = true }

function M.IsOpenOpportunity(o) return o ~= nil and OPEN_STAGE[o.stage] == true end

function M.GetOpportunity(id) return findById(R().opportunities, id) end

-- The price as typed: gold ("2g 50s") or anything else ("their mats + 50s tip").
-- Returns the text, and the copper amount when the text is a plain gold amount.
function M.ReadPrice(text)
	text = U.Trim(text)
	if text == "" then return nil, nil end
	local copper = U.ParseMoney(text)
	return text, (copper and copper > 0) and copper or nil
end

-- f: contact (key), need (the request, any number of lines), dir, stage, price (text) or
--    quote (copper), nextStep, due (time), notes, lead
function M.SaveOpportunity(id, f, now)
	local key = f.contact and U.Trim(f.contact) or ""
	if key == "" then return nil, "Who is it for? Type a name." end
	local need = U.Trim(f.need)
	local existing = id and M.GetOpportunity(id)
	local lead = f.lead or (existing and existing.lead)
	if need == "" and not lead then return nil, "Write the request." end
	local stage = f.stage or "new"
	if not U.Contains(ns.OPP_STAGES, stage) then return nil, "Unknown stage." end
	local priceText, quote
	if f.price ~= nil then
		priceText, quote = M.ReadPrice(f.price)
	else
		quote = tonumber(f.quote)
		if quote and quote <= 0 then quote = nil end
		priceText = quote and U.FormatMoney(quote) or nil
	end
	M.EnsureContact(key, now)
	local o = id and M.GetOpportunity(id)
	if not o then
		o = { id = M.NewId(), created = now, by = M.me }
		table.insert(R().opportunities, o)
	end
	local wasOpen = M.IsOpenOpportunity(o) or o.stage == nil
	o.contact, o.need, o.notes = key, need, f.notes or o.notes or ""
	o.dir = f.dir == "mine" and "mine" or "theirs"
	o.stage, o.quote, o.priceText = stage, quote, priceText
	o.nextStep = U.Trim(f.nextStep or o.nextStep or "")
	o.due = tonumber(f.due) or nil
	o.lead = lead
	o.updated = now
	if wasOpen and not OPEN_STAGE[stage] then o.closedAt = now end
	if OPEN_STAGE[stage] then o.closedAt = nil end
	return o
end

function M.DeleteOpportunity(id)
	local _, i = M.GetOpportunity(id)
	if i then table.remove(R().opportunities, i) end
end

-- A one-line name for lists: the request's first line, or what the lead said.
function M.OpportunityTitle(o, max)
	local first = U.Trim(((o.need or ""):match("[^\n]*")) or "")
	if first == "" then
		local lead = o.lead and M.GetLead(o.lead)
		first = lead and ("\"" .. (lead.text or "") .. "\"") or "(no request written yet)"
	end
	return U.Shorten(first, max or 60)
end

-- Open ones first, the most overdue at the top; then the rest, newest first.
-- filter: "open", "won", "lost" or "all"; key: only this person's (optional).
function M.Opportunities(filter, key)
	local out = {}
	for _, o in ipairs(R().opportunities) do
		local open = M.IsOpenOpportunity(o)
		local ok = filter == "all" or (filter == "open" and open) or (filter == o.stage)
		if ok and (not key or o.contact == key) then out[#out + 1] = o end
	end
	table.sort(out, function(a, b)
		local ao, bo = M.IsOpenOpportunity(a), M.IsOpenOpportunity(b)
		if ao ~= bo then return ao end
		if ao then
			local ad, bd = a.due or math.huge, b.due or math.huge
			if ad ~= bd then return ad < bd end
		end
		if (a.updated or 0) ~= (b.updated or 0) then return (a.updated or 0) > (b.updated or 0) end
		return a.id > b.id
	end)
	return out
end

-- Open opportunities whose follow-up date has come.
function M.DueOpportunities(now)
	local n = 0
	for _, o in ipairs(R().opportunities) do
		if M.IsOpenOpportunity(o) and o.due and o.due <= now then n = n + 1 end
	end
	return n
end

-- A lead becomes an opportunity for the same person. The request starts empty: the whole
-- conversation is shown beside it, so write down what they actually want.
function M.LeadToOpportunity(leadId, now)
	local lead = M.GetLead(leadId)
	if not lead then return nil, "That lead no longer exists." end
	for _, o in ipairs(R().opportunities) do
		if o.lead == lead.id and M.IsOpenOpportunity(o) then return o, nil, true end
	end
	return M.SaveOpportunity(nil, {
		contact = lead.contact, need = "", lead = lead.id,
		dir = M.LeadKind(lead) == "buy" and "mine" or "theirs", stage = "new",
	}, now)
end

-- The open opportunity a trade with this person most likely belongs to: something they need
-- from you, most recently worked on.
function M.OpenOpportunityFor(key)
	local best
	for _, o in ipairs(R().opportunities) do
		if o.contact == key and o.dir ~= "mine" and M.IsOpenOpportunity(o) and not (o.order and M.GetOrder(o.order)) then
			if not best or (o.updated or 0) > (best.updated or 0) then best = o end
		end
	end
	return best
end

-- What the job is: one of your products and how many. product: { key, name, output } or nil.
function M.SetOpportunityItem(id, product, qty, now)
	local o = M.GetOpportunity(id)
	if not o then return nil end
	o.product = product and { key = product.key, name = product.name, output = product.output } or nil
	o.qty = math.max(1, math.floor(tonumber(qty) or 1))
	o.updated = now
	return o
end

-- Materials the customer handed over for this job, before it is delivered.
-- lines: { name, link, qty, value (copper each, today's price) }
-- gold: any gold they paid in the same trade, kept until the order is logged.
function M.AddOpportunityMats(id, lines, now, gold)
	local o = M.GetOpportunity(id)
	if not o then return nil end
	o.mats = o.mats or {}
	o.paid = (o.paid or 0) + math.max(0, math.floor(tonumber(gold) or 0))
	for _, l in ipairs(lines or {}) do
		local name = U.Trim(l.name)
		if name ~= "" then
			local id2 = type(l.link) == "string" and tonumber(l.link:match("item:(%d+)")) or l.itemID
			local found
			for _, m in ipairs(o.mats) do if m.name == name then found = m end end
			if found then
				found.qty = found.qty + math.max(1, math.floor(tonumber(l.qty) or 1))
			else
				o.mats[#o.mats + 1] = { name = name, link = l.link, itemID = id2, qty = math.max(1, math.floor(tonumber(l.qty) or 1)),
					value = math.max(0, math.floor((tonumber(l.value) or 0) + 0.5)) }
			end
		end
	end
	if o.stage == "new" then o.stage = "working" end
	o.updated = now
	return o
end

-- The job sheet: what the whole job costs, what the customer brought, and what is left for them
-- to pay. No game API: the recipe, an index of recipes that make its parts, and prices are given.
--   recipe   { reagents = { { itemID, qty } } } (parts you make, such as bolts, are broken down)
--   priceOf(itemID, name) -> copper for one, at today's price
--   each     your price for one (optional); without it the job is priced at its materials
-- Returns { lines = { { itemID, name, need, brought, each } }, matsCost, broughtValue, base, total }
function M.OpportunitySheet(o, recipe, index, priceOf, nameOf, each)
	local qty = math.max(1, tonumber(o.qty) or 1)
	local brought = {}
	for _, m in ipairs(o.mats or {}) do
		local k = m.itemID or m.name
		brought[k] = (brought[k] or 0) + m.qty
		if m.itemID then brought[m.name] = (brought[m.name] or 0) + m.qty end
	end
	local sheet = { lines = {}, matsCost = 0, broughtValue = 0 }
	local raw = recipe and ns.Offers.RawMats(recipe, index) or {}
	for _, g in ipairs(raw) do
		local name = nameOf and nameOf(g.itemID) or ("item " .. g.itemID)
		local need = g.qty * qty
		local have = math.min(need, brought[g.itemID] or brought[name] or 0)
		local price = math.max(0, tonumber(priceOf and priceOf(g.itemID, name)) or 0)
		sheet.lines[#sheet.lines + 1] = { itemID = g.itemID, name = name, need = need, brought = have, each = price }
		sheet.matsCost = sheet.matsCost + need * price
		sheet.broughtValue = sheet.broughtValue + have * price
	end
	sheet.each = tonumber(each)
	sheet.base = (sheet.each and sheet.each > 0) and (sheet.each * qty) or sheet.matsCost
	sheet.total = math.max(0, sheet.base - sheet.broughtValue)
	return sheet
end

-- Won: an order to fill in, with what they need still to hand over at the quoted price.
-- Only for what they need from you; something you need from them is simply marked won.
function M.OpportunityToOrder(id, now)
	local o = M.GetOpportunity(id)
	if not o then return nil, "That opportunity no longer exists." end
	if o.order and M.GetOrder(o.order) then return M.GetOrder(o.order) end
	if o.dir == "mine" then return nil, "This is something you need from them, so there is no order to make. Mark it won instead." end
	local lead = o.lead and M.GetLead(o.lead)
	local notes = {}
	if U.Trim(o.need) ~= "" then notes[#notes + 1] = U.Trim(o.need) end
	if o.priceText and not o.quote then notes[#notes + 1] = "Agreed: " .. o.priceText end
	if U.Trim(o.notes) ~= "" then notes[#notes + 1] = U.Trim(o.notes) end
	-- The item still to hand over: the product when one is set (so handing it over in a trade
	-- delivers it), else the request's first line.
	local item = o.product and { name = o.product.name, qty = math.max(1, tonumber(o.qty) or 1), planned = true }
		or { name = M.OpportunityTitle(o, 60), qty = 1, planned = true }
	-- What they already handed over for the job counts as materials supplied.
	local received = {}
	for _, m in ipairs(o.mats or {}) do
		received[#received + 1] = { name = m.name, link = m.link, qty = m.qty, value = m.value or 0, kind = "mats" }
	end
	local ord = { id = M.NewId(), created = now, updated = now, contact = o.contact, type = "crafted", desc = "",
		items = { item }, received = received, price = o.paid or 0,
		notes = table.concat(notes, "\n"), trades = 0, status = "quoted", quote = o.quote,
		lead = lead and lead.id or nil, opportunity = o.id }
	if lead then
		ord.post, ord.campaign, ord.sentAt = lead.post, lead.campaign, lead.sentAt
		lead.status, lead.order = "won", ord.id
	else
		attribute(ord)
	end
	table.insert(R().orders, ord)
	o.stage, o.order, o.updated, o.closedAt = "won", ord.id, now, now
	return ord
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
				if not l.planned and not ps.soldNames[l.name] then
					ps.soldNames[l.name] = { name = l.name, qty = 0 }
					ps.sold[#ps.sold + 1] = ps.soldNames[l.name]
				end
				if not l.planned then ps.soldNames[l.name].qty = ps.soldNames[l.name].qty + l.qty end
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
					if not l.planned and not row.soldNames[l.name] then
						row.soldNames[l.name] = { name = l.name, qty = 0 }
						row.sold[#row.sold + 1] = row.soldNames[l.name]
					end
					if not l.planned then row.soldNames[l.name].qty = row.soldNames[l.name].qty + l.qty end
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
			for _, l in ipairs(o.items) do
				if not l.planned then out[l.name] = (out[l.name] or 0) + l.qty end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- services
-- Things you do for people rather than make: portals, summons, lockpicking, enchants. A
-- service has a name and a usual price. Service orders are named after what was done
-- ("Lockpicking: Iron Lockbox", "Portal: Orgrimmar"); a service counts every order whose name
-- starts with its own name.

M.SERVICE_LOG_KEEP = 200

function M.Services() return R().services end

function M.GetService(name)
	for i, s in ipairs(R().services) do if s.name == name then return s, i end end
end

function M.SaveService(oldName, name, price)
	name = U.Trim(name)
	if name == "" then return nil, "Give the service a name, for example Lockpicking or Portal: Orgrimmar." end
	local clash = M.GetService(name)
	local s = oldName and M.GetService(oldName)
	if clash and clash ~= s then return nil, name .. " is already on the list." end
	if not s then
		s = {}
		table.insert(R().services, s)
	end
	s.name = name
	s.price = (tonumber(price) or 0) > 0 and math.floor(tonumber(price)) or nil
	table.sort(R().services, function(a, b) return a.name < b.name end)
	return s
end

function M.DeleteService(name)
	local _, i = M.GetService(name)
	if i then table.remove(R().services, i) end
end

-- The services a class usually sells, as a starting point.
M.CLASS_SERVICES = {
	MAGE = { "Portal" },
	WARLOCK = { "Summon" },
	ROGUE = { "Lockpicking" },
}

-- What a spell cast during a trade, or just before one, was as a service. Returns the service
-- name for the order ("Lockpicking", "Enchant Bracer - Minor Stamina", "Portal: Orgrimmar",
-- "Summon"), and whether it is done through the trade window's "Will not be traded" slot.
function M.ServiceForSpell(spell)
	if type(spell) ~= "string" or spell == "" then return nil end
	if spell == "Pick Lock" then return "Lockpicking", true end
	if spell:find("^Enchant ") then return spell, true end
	if spell:find("^Portal: ") then return spell, false end
	if spell == "Ritual of Summoning" then return "Summon", false end
	return nil
end

-- A portal or summon was cast: kept so a payment trade soon after can be tied to it.
function M.LogServiceCast(name, now, target)
	local log = R().serviceLog
	log[#log + 1] = { name = name, time = now, target = target, by = M.me }
	while #log > M.SERVICE_LOG_KEEP do table.remove(log, 1) end
	return log[#log]
end

-- The portal or summon cast in the last `within` seconds, most recent first, if any.
function M.RecentServiceCast(now, within)
	local log = R().serviceLog
	local last = log[#log]
	if last and now - last.time <= (within or 600) then return last end
end

-- Records a service done for someone. trade: { received = items they handed over (materials,
-- e.g. for an enchant), gold = gold they paid }. item: what it was done on ("Iron Lockbox").
-- note: extra words for the order's notes. Fills in their open Opty for this service, if any.
function M.RecordService(key, service, item, trade, now, note)
	M.EnsureContact(key, now)
	trade = trade or {}
	local gold = math.max(0, math.floor((tonumber(trade.gold) or 0) + 0.5))
	local desc = item and (service .. ": " .. item) or service
	local received = cleanLines(trade.received or {}, true)
	for _, l in ipairs(received) do l.kind = "mats" end
	local o = { id = M.NewId(), created = now, updated = now, contact = key, type = "service", desc = desc,
		items = {}, received = received, price = gold, notes = note or "", trades = 1,
		status = gold > 0 and "paid" or "delivered", service = service }
	if gold > 0 then o.paidAt = now end
	attribute(o)
	-- An open Opty for this service is won by it.
	for _, opp in ipairs(R().opportunities) do
		if opp.contact == key and M.IsOpenOpportunity(opp) and opp.product and opp.product.name
			and desc:sub(1, #opp.product.name) == opp.product.name then
			opp.stage, opp.order, opp.updated, opp.closedAt = "won", o.id, now, now
			o.opportunity = opp.id
			o.price = o.price + (opp.paid or 0)
			break
		end
	end
	table.insert(R().orders, o)
	closeLeads(key)
	autoStatus(key)
	return o
end

-- How often a service was sold, and for how much (gold plus goods paid with), from its orders.
function M.ServiceStats(name)
	local n, earned = 0, 0
	for _, o in ipairs(R().orders) do
		if o.type == "service" and o.status ~= "cancelled" and type(o.desc) == "string" and o.desc:sub(1, #name) == name then
			n = n + 1
			local g, goods = M.OrderValue(o)
			earned = earned + g + goods
		end
	end
	return n, earned
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
		line("P", p.name, p.text, table.concat(t, ","), p.owner or "", M.PostKind(p))
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
		line("O", o.contact, o.type, o.desc, o.price, o.status, o.created, o.paidAt, o.notes, o.quote)
		for _, l in ipairs(o.items) do line("S", l.name, l.qty, l.link, l.planned and "planned" or nil) end
		for _, l in ipairs(o.received) do line("R", l.name, l.qty, l.value, l.kind, l.link) end
	end
	for _, o in ipairs(r.opportunities) do
		line("Y", o.contact, U.Trim(o.need) ~= "" and o.need or M.OpportunityTitle(o, 200), o.dir, o.stage, o.quote, o.due, o.nextStep, o.notes, o.created, o.priceText,
			o.product and o.product.name, o.product and o.product.output, o.qty)
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
	local added = { posts = 0, contacts = 0, orders = 0, opportunities = 0 }
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
			local p = M.SavePost(nil, f[2], f[3], targets, (f[5] and f[5] ~= "") and f[5] or nil, f[6])
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
					created = tonumber(f[7]) or now, paidAt = tonumber(f[8]), notes = f[9], quote = tonumber(f[10]),
					items = {}, received = {},
				}
			end
		elseif kind == "Y" and f[2] and f[2] ~= "" and f[3] and (f[3] ~= "" or (f[11] or "") ~= "") then
			local created = tonumber(f[10]) or now
			local dupe = false
			for _, o in ipairs(r.opportunities) do
				if o.contact == f[2] and o.need == f[3] and o.created == created then dupe = true end
			end
			if not dupe then
				local o = M.SaveOpportunity(nil, { contact = f[2], need = f[3] ~= "" and f[3] or "(request)", dir = f[4],
					stage = U.Contains(ns.OPP_STAGES, f[5]) and f[5] or "new", price = blank(f[11] or "") or (tonumber(f[6]) and U.FormatMoney(tonumber(f[6]))) or "",
					due = tonumber(f[7]), nextStep = f[8], notes = f[9] }, created)
				if o then
					o.created = created
					if blank(f[12] or "") then
						local key = nil
						for k, p in pairs(r.products) do if type(p) == "table" and p.name == f[12] then key = k end end
						o.product = { key = key, name = f[12], output = tonumber(f[13]) }
						o.qty = math.max(1, tonumber(f[14]) or 1)
					end
					added.opportunities = added.opportunities + 1
				end
			end
		elseif kind == "S" and pending then
			pending.items[#pending.items + 1] = { name = f[2], qty = f[3], link = blank(f[4]), planned = f[5] == "planned" or nil }
		elseif kind == "R" and pending then
			pending.received[#pending.received + 1] = { name = f[2], qty = f[3], value = f[4], kind = f[5], link = blank(f[6]) }
		end
	end
	flush()
	for key, ref in pairs(referrers) do M.SetReferrer(key, ref) end
	return added
end
