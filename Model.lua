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

function M.SavePost(id, name, text, targets)
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
		post = { id = M.NewId(), created = U.Now() }
		table.insert(R().posts, post)
	end
	post.name, post.text, post.targets = name, text, t
	return post
end

function M.DeletePost(id)
	local _, i = M.GetPost(id)
	if i then table.remove(R().posts, i) end
end

function M.GapRemaining(target, now)
	local last = R().lastSent[target]
	if not last then return 0 end
	local gap = ns.PUBLIC_TARGET[target] and DB.settings.minGap or 2
	local left = gap - (now - last)
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
	r.lastSent[target] = now
	M.cursor[post.id] = U.Contains(ns.TARGETS, target) or 0
	r.lastPost = { id = post.id, time = now }
	local log = r.postLog
	log[#log + 1] = { post = post.id, target = target, time = now, zone = zone }
	while #log > 500 do table.remove(log, 1) end
	if r.tracking.on then
		r.tracking.post, r.tracking.postTime = post.id, now
	end
end

-- ---------------------------------------------------------------- tracking

function M.SetTracking(on, now)
	local r = R()
	r.tracking = { on = on and true or false, since = on and now or nil }
	-- A post made just before switching on still counts.
	if on and r.lastPost and now - r.lastPost.time <= 300 and M.GetPost(r.lastPost.id) then
		r.tracking.post, r.tracking.postTime = r.lastPost.id, r.lastPost.time
	end
end

-- Returns: on, capturing, minutesLeft
function M.TrackingState(now)
	local t = R().tracking
	if not t.on then return false, false end
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
	local lead = { id = M.NewId(), contact = key, post = t.post, text = text, time = now, status = "open", count = 1 }
	table.insert(R().leads, lead)
	return lead, isNew
end

function M.GetLead(id) return findById(R().leads, id) end

function M.SetLeadStatus(id, status)
	local lead = M.GetLead(id)
	if lead then lead.status = status end
end

-- ---------------------------------------------------------------- orders

function M.GetOrder(id) return findById(R().orders, id) end

local function paidCount(key)
	local n = 0
	for _, o in ipairs(R().orders) do
		if o.contact == key and o.status == "paid" then n = n + 1 end
	end
	return n
end

local function autoStatus(key)
	local c = M.GetContact(key)
	if not c then return end
	local n = paidCount(key)
	if c.status == "lead" and n >= 1 then c.status = "customer" end
	if c.status == "customer" and n >= 2 then c.status = "repeat" end
end

-- f: contact (key), type, desc, link, qty, price (copper), status, notes
function M.SaveOrder(id, f, now)
	if not f.contact or f.contact == "" then return nil, "Choose a contact." end
	local desc = U.Trim(f.desc)
	if desc == "" then return nil, "Describe what was sold." end
	local price = tonumber(f.price)
	if not price or price < 0 then return nil, "The price is not a valid amount." end
	local qty = math.floor(tonumber(f.qty) or 1)
	if qty < 1 then return nil, "Quantity must be at least 1." end
	local status = f.status or "quoted"
	if not U.Contains(ns.ORDER_STATUS, status) then return nil, "Unknown order status." end
	local otype = f.type or "crafted"
	if not U.Contains(ns.ORDER_TYPE, otype) then return nil, "Unknown order type." end

	M.EnsureContact(f.contact, now)
	local o = id and M.GetOrder(id)
	if not o then
		o = { id = M.NewId(), created = now }
		table.insert(R().orders, o)
	end
	local oldContact = o.contact
	o.contact, o.type, o.desc, o.link = f.contact, otype, desc, f.link or o.link
	o.qty, o.price, o.notes = qty, math.floor(price + 0.5), f.notes or ""
	if status == "paid" and o.status ~= "paid" then o.paidAt = now end
	if status ~= "paid" then o.paidAt = nil end
	o.status = status

	for _, lead in ipairs(R().leads) do
		if lead.contact == o.contact and lead.status == "open" then lead.status = "won" end
	end
	autoStatus(o.contact)
	if oldContact and oldContact ~= o.contact then autoStatus(oldContact) end
	return o
end

function M.DeleteOrder(id)
	local _, i = M.GetOrder(id)
	if i then table.remove(R().orders, i) end
end

-- Lifetime value: the sum of paid orders. Returns copper, paid count, total count.
function M.LTV(key)
	local sum, paid, all = 0, 0, 0
	for _, o in ipairs(R().orders) do
		if o.contact == key then
			all = all + 1
			if o.status == "paid" then sum = sum + o.price; paid = paid + 1 end
		end
	end
	return sum, paid, all
end

-- Returns number of people this contact referred, and what those people have paid.
function M.Referrals(key)
	local n, revenue = 0, 0
	for k, c in pairs(R().contacts) do
		if c.referredBy == key then
			n = n + 1
			revenue = revenue + M.LTV(k)
		end
	end
	return n, revenue
end

function M.Stats()
	local r = R()
	local s = { revenue = 0, paidOrders = 0, openOrders = 0, contacts = 0, customers = 0, openLeads = 0, top = {}, referrers = {}, posts = {} }
	local byPost = {}
	for _, p in ipairs(r.posts) do
		byPost[p.id] = { name = p.name, sends = 0, leads = 0, revenue = 0 }
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
		if o.status == "paid" then
			s.revenue = s.revenue + o.price
			s.paidOrders = s.paidOrders + 1
		elseif o.status ~= "cancelled" then
			s.openOrders = s.openOrders + 1
		end
	end
	for k, c in pairs(r.contacts) do
		s.contacts = s.contacts + 1
		local ltv, paid = M.LTV(k)
		if paid > 0 then
			s.customers = s.customers + 1
			s.top[#s.top + 1] = { key = k, value = ltv }
			if byPost[c.sourcePost] then byPost[c.sourcePost].revenue = byPost[c.sourcePost].revenue + ltv end
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

-- ---------------------------------------------------------------- export / import

local HEADER = "WOWCRM1"

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
		line("P", p.name, p.text, table.concat(t, ","))
	end
	local keys = {}
	for k in pairs(r.contacts) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local c = r.contacts[k]
		local src = c.sourcePost and M.GetPost(c.sourcePost)
		line("C", k, c.status, c.tags, c.notes, c.firstSeen, c.lastContact, c.referredBy, src and src.name)
	end
	for _, o in ipairs(r.orders) do
		line("O", o.contact, o.type, o.desc, o.qty, o.price, o.status, o.created, o.paidAt, o.notes, o.link)
	end
	return table.concat(out, "\n")
end

-- Merges exported text into the current realm. Returns counts table, or nil and an error.
function M.Import(text, now)
	local r = R()
	local lines = {}
	for l in tostring(text or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = l end
	if U.Trim(lines[1]) ~= HEADER then return nil, "This is not WoW CRM export text." end
	local added = { posts = 0, contacts = 0, orders = 0 }
	local postByName, referrers = {}, {}
	for _, p in ipairs(r.posts) do postByName[p.name] = p end
	local function blank(v) if v == "" then return nil end return v end

	for i = 2, #lines do
		local f = U.SplitTabs(lines[i])
		local kind = f[1]
		if kind == "P" and f[2] and not postByName[f[2]] then
			local targets = {}
			for k in (f[4] or ""):gmatch("[^,]+") do targets[k] = true end
			local p = M.SavePost(nil, f[2], f[3], targets)
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
		elseif kind == "O" and f[2] and f[2] ~= "" then
			local created = tonumber(f[8]) or now
			local dup = false
			for _, o in ipairs(r.orders) do
				if o.contact == f[2] and o.created == created and o.desc == f[4] then dup = true; break end
			end
			if not dup then
				local o = M.SaveOrder(nil, {
					contact = f[2], type = f[3], desc = f[4], qty = f[5], price = f[6],
					status = f[7], notes = f[10], link = blank(f[11]),
				}, created)
				if o then
					o.paidAt = tonumber(f[9]) or o.paidAt
					added.orders = added.orders + 1
				end
			end
		end
	end
	for key, ref in pairs(referrers) do M.SetReferrer(key, ref) end
	return added
end
