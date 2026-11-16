-- The window: Posts, Leads, Contacts, Orders, Mail, Dashboard; plus the quick-post bar.
local _, ns = ...
local U, DB, M, Chat, Mail = ns.Util, ns.DB, ns.Model, ns.Chat, ns.Mail
local UI = {}
ns.UI = UI

local main, bar, probe
local tabs, tabOrder, current = {}, {}, nil
UI.tabs = tabs

-- ---------------------------------------------------------------- widgets

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Box(parent, w, h, alpha)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(w, h)
	b:SetBackdrop(BACKDROP)
	b:SetBackdropColor(0, 0, 0, alpha or 0.5)
	b:SetBackdropBorderColor(0.5, 0.5, 0.5)
	return b
end

local function At(widget, parent, x, y)
	widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	return widget
end

local function Label(parent, text, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if width then fs:SetWidth(width) end
	fs:SetText(text or "")
	return fs
end

local function Button(parent, text, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

local function Edit(parent, w)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(w, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end

local function SetEdit(e, text)
	e:SetText(text or "")
	e:SetCursorPosition(0)
end

local function MultiEdit(parent, w, h)
	local box = Box(parent, w, h, 0.7)
	local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 6, -6)
	sf:SetPoint("BOTTOMRIGHT", -28, 6)
	local e = CreateFrame("EditBox", nil, sf)
	e:SetMultiLine(true)
	e:SetFontObject(ChatFontNormal)
	e:SetWidth(w - 40)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sf:SetScrollChild(e)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() e:SetFocus() end)
	box.edit = e
	return box
end

local function Check(parent, text)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	local fs = Label(parent, text, "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 0, 1)
	return cb
end

local function Cycle(parent, list, w)
	local b = Button(parent, list[1], w)
	b.value = list[1]
	function b:Set(v)
		self.value = U.Contains(list, v) and v or list[1]
		self:SetText(self.value)
	end
	b:SetScript("OnClick", function(self)
		local i = U.Contains(list, self.value) or 0
		self:Set(list[i % #list + 1])
	end)
	return b
end

local ROW = 18
local function List(parent, w, h, onSelect)
	local box = Box(parent, w, h)
	local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 5, -5)
	sf:SetPoint("BOTTOMRIGHT", -27, 5)
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(w - 34, 1)
	sf:SetScrollChild(content)
	local rows = {}
	function box:Set(items, render, selected)
		for i, item in ipairs(items) do
			local row = rows[i]
			if not row then
				row = CreateFrame("Button", nil, content)
				row:SetSize(w - 34, ROW)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
				local hl = row:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(1, 1, 1, 0.12)
				row.sel = row:CreateTexture(nil, "BACKGROUND")
				row.sel:SetAllPoints()
				row.sel:SetColorTexture(0.2, 0.5, 0.9, 0.35)
				row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				row.right:SetPoint("RIGHT", -3, 0)
				row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.left:SetPoint("LEFT", 3, 0)
				row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
				row.left:SetJustifyH("LEFT")
				row.left:SetWordWrap(false)
				row:SetScript("OnClick", function(self) onSelect(self.item) end)
				rows[i] = row
			end
			row.item = item
			local l, r = render(item)
			row.right:SetText(r or "")
			row.left:SetText(l or "")
			if (item.id or item.key) == selected then row.sel:Show() else row.sel:Hide() end
			row:Show()
		end
		for i = #items + 1, #rows do rows[i]:Hide() end
		content:SetHeight(math.max(1, #items * ROW))
	end
	return box
end

local function When(t)
	return t and date("%b %d %H:%M", t) or "-"
end

local function Name(key)
	return U.Display(key, DB.realm)
end

function UI.Msg(text, isError)
	if main then
		main.msg:SetText(text or "")
		if isError then main.msg:SetTextColor(1, 0.3, 0.3) else main.msg:SetTextColor(0.6, 1, 0.6) end
	elseif text and text ~= "" then
		ns.Print(text)
	end
end

local function AddTab(name, build)
	tabs[name] = { name = name, build = build }
	tabOrder[#tabOrder + 1] = name
end

-- ---------------------------------------------------------------- Posts

AddTab("Posts", function(p, tab)
	local sel
	local list = At(List(p, 250, 372, function(item) tab.Select(item.id) end), p, 0, 0)
	local X = 264

	At(Label(p, "Name"), p, X, -4)
	local name = At(Edit(p, 300), p, X + 70, 0)
	At(Label(p, "Message"), p, X, -30)
	local counter = At(Label(p, "", "GameFontHighlightSmall"), p, X + 70, -31)
	local text = At(MultiEdit(p, 500, 84), p, X, -48)
	At(Label(p, "Tokens: {me} your name, {zone} current zone. Shift-click an item to link it.", "GameFontDisableSmall"), p, X, -136)

	local checks = {}
	for i, t in ipairs(ns.TARGETS) do
		checks[t] = At(Check(p, ns.TARGET_LABEL[t]), p, X + (i - 1) * 82, -152)
	end

	local function updateCounter()
		local n = U.ByteLen(U.Fill(text.edit:GetText(), { me = UnitName("player") or "", zone = GetZoneText() or "" }))
		counter:SetText(("%d / %d bytes"):format(n, ns.MAX_CHAT_BYTES))
		if n > ns.MAX_CHAT_BYTES then counter:SetTextColor(1, 0.3, 0.3) else counter:SetTextColor(1, 1, 1) end
	end
	text.edit:SetScript("OnTextChanged", updateCounter)

	local function insertLink(link)
		if type(link) == "string" and text.edit:IsVisible() and text.edit:HasFocus() then text.edit:Insert(link) end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertLink)
	end

	local function load(post)
		sel = post and post.id or nil
		SetEdit(name, post and post.name)
		text.edit:SetText(post and post.text or "")
		for _, t in ipairs(ns.TARGETS) do checks[t]:SetChecked(post and post.targets[t] and true or false) end
		updateCounter()
	end

	At(Button(p, "Save post", 100, function()
		local targets = {}
		for _, t in ipairs(ns.TARGETS) do targets[t] = checks[t]:GetChecked() and true or false end
		local post, err = M.SavePost(sel, name:GetText(), text.edit:GetText(), targets)
		if not post then UI.Msg(err, true) return end
		sel = post.id
		UI.Msg("Post saved.")
		ns.Changed()
	end), p, X, -180)
	At(Button(p, "New post", 100, function() load(nil); name:SetFocus(); tab.Refresh() end), p, X + 106, -180)
	At(Button(p, "Delete", 80, function()
		local post = sel and M.GetPost(sel)
		if not post then return end
		ns.Confirm("Delete the post \"" .. post.name .. "\"?", function()
			M.DeletePost(post.id)
			load(nil)
			ns.Changed()
		end)
	end), p, X + 212, -180)

	At(Label(p, "Post to chat. Each click sends one message to one channel."), p, X, -222)
	local nextBtn = At(Button(p, "Post next", 240), p, X, -242)
	nextBtn:SetHeight(30)
	local hint = At(Label(p, "", "GameFontHighlightSmall", 250), p, X + 250, -246)
	local targetBtns = {}
	for i, t in ipairs(ns.TARGETS) do
		targetBtns[t] = At(Button(p, ns.TARGET_LABEL[t], 80, function()
			local post = sel and M.GetPost(sel)
			if not post then return end
			local ok, err = Chat.Send(post, t)
			UI.Msg(ok and ("Posted to " .. ns.TARGET_LABEL[t] .. ".") or err, not ok)
		end), p, X + (i - 1) * 83, -282)
	end
	nextBtn:SetScript("OnClick", function()
		local post = sel and M.GetPost(sel)
		if not post then UI.Msg("Save the post first.", true) return end
		local ok, res = Chat.SendNext(post)
		UI.Msg(ok and ("Posted to " .. res .. ".") or res, not ok)
	end)
	At(Label(p, "Posting uses the saved version of the post. A channel is greyed out when you are\nnot in it, or while its gap between posts is still running.", "GameFontDisableSmall"), p, X, -312)
	At(Button(p, "Show / hide quick-post bar", 200, function() UI.ToggleBar() end), p, X, -346)

	local function updateButtons()
		local post = sel and M.GetPost(sel)
		local now = U.Now()
		for _, t in ipairs(ns.TARGETS) do
			local ok = post and post.targets[t] and Chat.Available(t) and M.GapRemaining(t, now) == 0
			if ok then targetBtns[t]:Enable() else targetBtns[t]:Disable() end
		end
		if not post then
			nextBtn:SetText("Post next")
			nextBtn:Disable()
			hint:SetText("Select or save a post.")
			return
		end
		local target, why = M.NextTarget(post, Chat.Available, now)
		if target then
			nextBtn:SetText("Post to " .. ns.TARGET_LABEL[target])
			nextBtn:Enable()
			hint:SetText("")
		else
			nextBtn:SetText("Post next")
			nextBtn:Disable()
			hint:SetText(why or "")
		end
	end

	local elapsed = 0
	p:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.5 then elapsed = 0; updateButtons() end
	end)

	function tab.Select(id)
		load(M.GetPost(id))
		tab.Refresh()
	end
	function tab.Refresh()
		if sel and not M.GetPost(sel) then load(nil) end
		list:Set(DB.R.posts, function(post)
			local n = 0
			for _ in pairs(post.targets) do n = n + 1 end
			return post.name, n .. " ch"
		end, sel)
		updateButtons()
	end
	load(nil)
end)

-- ---------------------------------------------------------------- Leads

AddTab("Leads", function(p, tab)
	local sel, showClosed = nil, false
	local list = At(List(p, 340, 346, function(item) sel = item.id; tab.Refresh() end), p, 0, 0)
	local toggle = At(Button(p, "Show closed leads", 160), p, 0, -352)
	local X = 354
	local detail = At(Label(p, "", "GameFontHighlight", 410), p, X, -4)

	local function lead() return sel and M.GetLead(sel) end
	local buttons = {
		At(Button(p, "Whisper back", 110, function() local l = lead(); if l then Chat.Whisper(l.contact) end end), p, X, -290),
		At(Button(p, "Open contact", 110, function() local l = lead(); if l then UI.Show("Contacts", l.contact) end end), p, X + 114, -290),
		At(Button(p, "New order", 110, function() local l = lead(); if l then UI.Show("Orders", { contact = l.contact }) end end), p, X + 228, -290),
		At(Button(p, "Dismiss", 110, function()
			local l = lead()
			if l then M.SetLeadStatus(l.id, "dismissed"); sel = nil; ns.Changed() end
		end), p, X, -316),
		At(Button(p, "Ignore this player", 150, function()
			local l = lead()
			if not l then return end
			ns.Confirm("Stop capturing whispers from " .. Name(l.contact) .. "?", function()
				local c = M.GetContact(l.contact)
				if c then c.status = "ignored" end
				M.SetLeadStatus(l.id, "dismissed")
				sel = nil
				ns.Changed()
			end)
		end), p, X + 114, -316),
	}
	toggle:SetScript("OnClick", function()
		showClosed = not showClosed
		toggle:SetText(showClosed and "Hide closed leads" or "Show closed leads")
		tab.Refresh()
	end)

	function tab.Select(id) sel = id; tab.Refresh() end
	function tab.Refresh()
		local items = {}
		for i = #DB.R.leads, 1, -1 do
			local l = DB.R.leads[i]
			if showClosed or l.status == "open" then items[#items + 1] = l end
		end
		table.sort(items, function(a, b) return a.time > b.time end)
		list:Set(items, function(l)
			local mark = l.status == "open" and "" or ("[" .. l.status .. "] ")
			return mark .. Name(l.contact) .. ": " .. U.Shorten(l.text, 60), When(l.time)
		end, sel)
		local l = lead()
		for _, b in ipairs(buttons) do if l then b:Enable() else b:Disable() end end
		if not l then
			local on, capturing = M.TrackingState(U.Now())
			detail:SetText(#items > 0 and "Select a lead." or (on and capturing) and "Tracking is on. Whispers will appear here."
				or on and "Tracking is on. Make a post and whispers will appear here."
				or "No leads yet.\n\nTurn on contact tracking (top of this window), then make a post.\nAnyone who whispers you is captured here and added to your contacts.")
			return
		end
		local c = M.GetContact(l.contact)
		local post = l.post and M.GetPost(l.post)
		detail:SetText(("|cffffd100%s|r  (%s)\nPost: %s\nLast message: %s   Messages: %d\nLead status: %s\n\n%s"):format(
			Name(l.contact), c and c.status or "?", post and post.name or "(deleted post)", When(l.time), l.count, l.status, l.text))
	end
end)

-- ---------------------------------------------------------------- Contacts

AddTab("Contacts", function(p, tab)
	local sel
	local search = At(Edit(p, 120), p, 6, 0)
	local list = At(List(p, 250, 346, function(item) tab.Select(item.key) end), p, 0, -26)
	At(Button(p, "Add", 50, function()
		local key = U.NormName(search:GetText(), DB.realm, true)
		if not key then UI.Msg("Type a character name in the box, then press Add.", true) return end
		local _, isNew = M.EnsureContact(key, U.Now())
		search:SetText("")
		if isNew then ns.Changed() end
		tab.Select(key)
	end), p, 132, 1)
	At(Button(p, "Target", 62, function()
		local n, r = UnitName("target")
		if not n or not UnitIsPlayer("target") then UI.Msg("Target a player first.", true) return end
		local key = U.NormName((r and r ~= "") and (n .. "-" .. r) or n, DB.realm)
		local _, isNew = M.EnsureContact(key, U.Now())
		if isNew then ns.Changed() end
		tab.Select(key)
	end), p, 186, 1)
	search:SetScript("OnTextChanged", function() tab.Refresh() end)

	local X = 264
	local header = At(Label(p, "", "GameFontNormalLarge"), p, X, -2)
	At(Label(p, "Status"), p, X, -32)
	local status = At(Cycle(p, ns.CONTACT_STATUS, 130), p, X + 90, -28)
	At(Label(p, "Tags"), p, X, -58)
	local tags = At(Edit(p, 300), p, X + 94, -54)
	At(Label(p, "Referred by"), p, X, -84)
	local ref = At(Edit(p, 200), p, X + 94, -80)
	At(Label(p, "Notes"), p, X, -108)
	local notes = At(MultiEdit(p, 500, 90), p, X, -124)
	local stats = At(Label(p, "", "GameFontHighlight", 500), p, X, -222)

	local function load()
		local c = sel and M.GetContact(sel)
		header:SetText(c and c.key or "Select a contact")
		status:Set(c and c.status)
		SetEdit(tags, c and c.tags)
		SetEdit(ref, c and c.referredBy and Name(c.referredBy))
		notes.edit:SetText(c and c.notes or "")
	end

	local buttons = {
		At(Button(p, "Save contact", 110, function()
			local c = sel and M.GetContact(sel)
			if not c then return end
			c.status, c.tags, c.notes = status.value, U.Trim(tags:GetText()), notes.edit:GetText()
			local rtext = U.Trim(ref:GetText())
			local ok, err = true, nil
			if rtext == "" then
				M.SetReferrer(c.key, nil)
			else
				local r = M.FindContact(rtext)
				if r then ok, err = M.SetReferrer(c.key, r.key) else ok, err = false, rtext .. " is not a contact yet. Add them first." end
			end
			UI.Msg(ok and "Contact saved." or err, not ok)
			ns.Changed()
		end), p, X, -330),
		At(Button(p, "New order", 90, function() if sel then UI.Show("Orders", { contact = sel }) end end), p, X + 114, -330),
		At(Button(p, "Mail", 60, function() if sel then UI.Show("Mail", sel) end end), p, X + 208, -330),
		At(Button(p, "Whisper", 76, function() if sel then Chat.Whisper(sel) end end), p, X + 272, -330),
		At(Button(p, "Delete", 70, function()
			if not sel then return end
			local key = sel
			ns.Confirm("Delete " .. Name(key) .. " and all of their leads and orders?", function()
				M.DeleteContact(key)
				sel = nil
				load()
				ns.Changed()
			end)
		end), p, X + 352, -330),
	}

	function tab.Select(key) sel = key; load(); tab.Refresh() end
	function tab.Refresh()
		if sel and not M.GetContact(sel) then sel = nil; load() end
		local q = U.Trim(search:GetText()):lower()
		local items = {}
		for k, c in pairs(DB.R.contacts) do
			if q == "" or k:lower():find(q, 1, true) or c.tags:lower():find(q, 1, true) or c.notes:lower():find(q, 1, true) then
				items[#items + 1] = c
			end
		end
		table.sort(items, function(a, b)
			if a.lastContact ~= b.lastContact then return (a.lastContact or 0) > (b.lastContact or 0) end
			return a.key < b.key
		end)
		list:Set(items, function(c)
			local ltv = M.LTV(c.key)
			return Name(c.key), ltv > 0 and U.FormatMoney(ltv) or c.status
		end, sel)
		local c = sel and M.GetContact(sel)
		for _, b in ipairs(buttons) do if c then b:Enable() else b:Disable() end end
		if not c then stats:SetText("Type a name and press Add, or target a player and press Target.") return end
		local ltv, paid, all = M.LTV(c.key)
		local n, rev = M.Referrals(c.key)
		local src = c.sourcePost and M.GetPost(c.sourcePost)
		stats:SetText(("Lifetime value: |cffffd100%s|r   (%d paid of %d orders)\nReferrals made: %d   Revenue from referrals: %s\nFirst seen: %s   Last contact: %s\nCame from post: %s"):format(
			U.FormatMoney(ltv), paid, all, n, U.FormatMoney(rev), When(c.firstSeen), When(c.lastContact), src and src.name or "-"))
	end
end)

-- ---------------------------------------------------------------- Orders

AddTab("Orders", function(p, tab)
	local sel
	local list = At(List(p, 360, 372, function(item) tab.Select(item.id) end), p, 0, 0)
	local X, C = 374, 80
	At(Label(p, "Contact"), p, X, -4)
	local contact = At(Edit(p, 200), p, X + C, 0)
	At(Label(p, "Type"), p, X, -32)
	local otype = At(Cycle(p, ns.ORDER_TYPE, 110), p, X + C - 4, -28)
	At(Label(p, "Sold"), p, X, -60)
	local desc = At(Edit(p, 300), p, X + C, -56)
	At(Label(p, "Quantity"), p, X, -86)
	local qty = At(Edit(p, 60), p, X + C, -82)
	At(Label(p, "Price"), p, X, -112)
	local price = At(Edit(p, 140), p, X + C, -108)
	At(Label(p, "e.g. 12g 50s", "GameFontDisableSmall"), p, X + C + 150, -112)
	At(Label(p, "Status"), p, X, -140)
	local status = At(Cycle(p, ns.ORDER_STATUS, 110), p, X + C - 4, -136)
	At(Label(p, "Notes"), p, X, -168)
	local notes = At(Edit(p, 300), p, X + C, -164)
	local info = At(Label(p, "", "GameFontHighlightSmall", 390), p, X, -230)

	local function load(o, draft)
		sel = o and o.id or nil
		draft = draft or {}
		SetEdit(contact, o and Name(o.contact) or (draft.contact and Name(draft.contact)))
		otype:Set(o and o.type)
		SetEdit(desc, o and o.desc)
		SetEdit(qty, tostring(o and o.qty or 1))
		SetEdit(price, o and U.FormatMoney(o.price))
		status:Set(o and o.status)
		SetEdit(notes, o and o.notes)
	end

	local function save(forceStatus)
		local ctext = contact:GetText()
		local c = M.FindContact(ctext)
		local key = c and c.key or U.NormName(ctext, DB.realm, true)
		local copper = U.ParseMoney(price:GetText())
		if not copper then UI.Msg("Price not understood. Use a form like 12g 50s.", true) return end
		local o, err = M.SaveOrder(sel, {
			contact = key, type = otype.value, desc = desc:GetText(), qty = tonumber(qty:GetText()) or 0,
			price = copper, status = forceStatus or status.value, notes = notes:GetText(),
		}, U.Now())
		if not o then UI.Msg(err, true) return end
		load(o)
		UI.Msg("Order saved.")
		ns.Changed()
	end

	At(Button(p, "Save order", 100, function() save() end), p, X, -196)
	At(Button(p, "Mark paid", 90, function() save("paid") end), p, X + 104, -196)
	At(Button(p, "New order", 90, function() load(nil); contact:SetFocus(); tab.Refresh() end), p, X + 198, -196)
	At(Button(p, "Delete", 70, function()
		local o = sel and M.GetOrder(sel)
		if not o then return end
		ns.Confirm("Delete this order?", function() M.DeleteOrder(o.id); load(nil); ns.Changed() end)
	end), p, X + 292, -196)

	-- Select an order id, or pass { contact = key } to start a new order for that contact.
	function tab.Select(arg)
		if type(arg) == "table" then load(nil, arg); desc:SetFocus() else load(M.GetOrder(arg)) end
		tab.Refresh()
	end
	function tab.Refresh()
		if sel and not M.GetOrder(sel) then load(nil) end
		local items = {}
		for _, o in ipairs(DB.R.orders) do items[#items + 1] = o end
		table.sort(items, function(a, b) if a.created ~= b.created then return a.created > b.created end return a.id > b.id end)
		list:Set(items, function(o)
			return Name(o.contact) .. ": " .. U.Shorten(o.desc, 40), U.FormatMoney(o.price) .. "  " .. o.status
		end, sel)
		local o = sel and M.GetOrder(sel)
		if o then
			info:SetText(("Created: %s\nPaid: %s%s\n\nOnly orders marked |cffffd100paid|r count towards lifetime value."):format(
				When(o.created), When(o.paidAt), o.link and ("\nItem: " .. o.link) or ""))
		else
			info:SetText("New order. A contact is created automatically if the name is new.\nCompleted trades and cash-on-delivery mail offer to fill this in for you.")
		end
	end
	load(nil)
end)

-- ---------------------------------------------------------------- Mail

AddTab("Mail", function(p, tab)
	local sel
	local list = At(List(p, 220, 372, function(item) tab.SelectTemplate(item.id) end), p, 0, 0)
	local X = 234
	At(Label(p, "Template"), p, X, -4)
	local name = At(Edit(p, 240), p, X + 80, 0)
	At(Label(p, "Subject"), p, X, -30)
	local subject = At(Edit(p, 400), p, X + 80, -26)
	local body = At(MultiEdit(p, 530, 150), p, X, -52)
	At(Label(p, "Tokens: {name} customer, {item} and {total} from their latest order, {me} your name.", "GameFontDisableSmall"), p, X, -206)

	local function load(t)
		sel = t and t.id or nil
		SetEdit(name, t and t.name)
		SetEdit(subject, t and t.subject)
		body.edit:SetText(t and t.body or "")
	end

	At(Button(p, "Save template", 120, function()
		local t, err = M.SaveTemplate(sel, name:GetText(), subject:GetText(), body.edit:GetText())
		if not t then UI.Msg(err, true) return end
		sel = t.id
		UI.Msg("Template saved.")
		ns.Changed()
	end), p, X, -224)
	At(Button(p, "New", 60, function() load(nil); name:SetFocus(); tab.Refresh() end), p, X + 124, -224)
	At(Button(p, "Delete", 70, function()
		local t = sel and M.GetTemplate(sel)
		if not t then return end
		ns.Confirm("Delete the template \"" .. t.name .. "\"?", function() M.DeleteTemplate(t.id); load(nil); ns.Changed() end)
	end), p, X + 188, -224)

	At(Label(p, "Write a letter"), p, X, -270)
	At(Label(p, "To"), p, X, -294)
	local to = At(Edit(p, 200), p, X + 80, -290)
	local fill = At(Button(p, "Fill in letter", 130, function()
		local c = M.FindContact(to:GetText())
		local key = c and c.key or U.NormName(to:GetText(), DB.realm, true)
		if not key then UI.Msg("Type who the letter is for.", true) return end
		local ok, err = Mail.Compose(key, sel)
		UI.Msg(ok and "Letter filled in. Check it, attach anything you need, then press Send in the mail window." or err, not ok)
	end), p, X + 290, -291)
	local hint = At(Label(p, "", "GameFontHighlightSmall", 520), p, X, -320)

	function tab.SelectTemplate(id) load(M.GetTemplate(id)); tab.Refresh() end
	-- Select a contact key to address the letter to.
	function tab.Select(key) SetEdit(to, Name(key)); tab.Refresh() end
	function tab.Refresh()
		if sel and not M.GetTemplate(sel) then load(nil) end
		if not sel and not tab.started and DB.R.mailTemplates[1] then load(DB.R.mailTemplates[1]) end
		tab.started = true
		list:Set(DB.R.mailTemplates, function(t) return t.name end, sel)
		if Mail.open then
			fill:Enable()
			hint:SetText("Mailbox open. The add-on fills in the letter; you press Send.")
		else
			fill:Disable()
			hint:SetText("Open a mailbox to write a letter. Letters are sent one at a time, by you.")
		end
	end
end)

-- ---------------------------------------------------------------- Dashboard

AddTab("Dashboard", function(p, tab)
	local stats = At(Label(p, "", "GameFontHighlight", 370), p, 4, -4)
	local X = 390
	At(Label(p, "Settings"), p, X, -4)
	At(Label(p, "Seconds between posts to the same public channel (min " .. DB.MIN_GAP_FLOOR .. ")", "GameFontHighlightSmall"), p, X, -28)
	local gap = At(Edit(p, 50), p, X + 330, -24)
	At(Label(p, "Tracking turns off this many minutes after your last post (0 = never)", "GameFontHighlightSmall"), p, X, -52)
	local off = At(Edit(p, 50), p, X + 330, -48)
	At(Label(p, "Channel names:  General", "GameFontHighlightSmall"), p, X, -76)
	local gen = At(Edit(p, 80), p, X + 140, -72)
	At(Label(p, "Trade", "GameFontHighlightSmall"), p, X + 232, -76)
	local trd = At(Edit(p, 80), p, X + 270, -72)
	local remind = At(Check(p, "Show the Save button after changes"), p, X, -94)
	local strangers = At(Check(p, "Offer to record sales to people who are not contacts yet"), p, X, -116)
	At(Button(p, "Apply settings", 120, function()
		local s = DB.settings
		s.minGap = math.max(DB.MIN_GAP_FLOOR, math.floor(tonumber(gap:GetText()) or s.minGap))
		s.trackAutoOff = math.max(0, math.floor(tonumber(off:GetText()) or s.trackAutoOff))
		if U.Trim(gen:GetText()) ~= "" then s.generalName = U.Trim(gen:GetText()) end
		if U.Trim(trd:GetText()) ~= "" then s.tradeName = U.Trim(trd:GetText()) end
		s.saveReminder = remind:GetChecked() and true or false
		s.promptStrangers = strangers:GetChecked() and true or false
		UI.Msg("Settings applied.")
		tab.loaded = false
		ns.Changed()
	end), p, X, -142)

	At(Label(p, "Backup"), p, X, -180)
	local box = At(MultiEdit(p, 380, 120), p, X, -198)
	At(Button(p, "Export", 80, function()
		box.edit:SetText(M.Export())
		box.edit:SetFocus()
		box.edit:HighlightText()
		UI.Msg("Press Ctrl+C to copy, then paste it somewhere safe.")
	end), p, X, -322)
	At(Button(p, "Import", 80, function()
		local textIn = box.edit:GetText()
		ns.Confirm("Merge the pasted export into your CRM data?", function()
			local added, err = M.Import(textIn, U.Now())
			if not added then UI.Msg(err, true) return end
			UI.Msg(("Imported %d posts, %d contacts, %d orders."):format(added.posts, added.contacts, added.orders))
			ns.Changed()
		end)
	end), p, X + 84, -322)
	At(Button(p, "Save now", 80, function() ns.SaveNow() end), p, X + 168, -322)
	At(Button(p, "Delete all data", 120, function()
		ns.Confirm("Delete ALL WoW CRM data for this realm? This cannot be undone.", function()
			DB.WipeRealm()
			UI.Msg("All data for this realm deleted.")
			ns.Changed()
		end)
	end), p, X + 260, -322)
	At(Label(p, "Data is written to disk when you log out or press a Save button (it reloads the interface).", "GameFontDisableSmall", 380), p, X, -350)

	function tab.Refresh()
		if not tab.loaded then
			tab.loaded = true
			local s = DB.settings
			SetEdit(gap, tostring(s.minGap))
			SetEdit(off, tostring(s.trackAutoOff))
			SetEdit(gen, s.generalName)
			SetEdit(trd, s.tradeName)
			remind:SetChecked(s.saveReminder)
			strangers:SetChecked(s.promptStrangers)
		end
		local s = M.Stats()
		local L = {
			("|cffffd100Revenue (paid orders):|r %s"):format(U.FormatMoney(s.revenue)),
			("Paid orders: %d    Open orders: %d"):format(s.paidOrders, s.openOrders),
			("Contacts: %d    Customers: %d    Open leads: %d"):format(s.contacts, s.customers, s.openLeads),
			"",
			"|cffffd100Top customers|r",
		}
		for i = 1, math.min(5, #s.top) do L[#L + 1] = ("  %d. %s  %s"):format(i, Name(s.top[i].key), U.FormatMoney(s.top[i].value)) end
		if #s.top == 0 then L[#L + 1] = "  none yet" end
		L[#L + 1] = ""
		L[#L + 1] = "|cffffd100Top referrers|r"
		for i = 1, math.min(5, #s.referrers) do
			local r = s.referrers[i]
			L[#L + 1] = ("  %d. %s  %d referred, %s"):format(i, Name(r.key), r.count, U.FormatMoney(r.value))
		end
		if #s.referrers == 0 then L[#L + 1] = "  none yet" end
		L[#L + 1] = ""
		L[#L + 1] = "|cffffd100Posts|r  (times posted / leads / revenue)"
		for i = 1, math.min(8, #s.posts) do
			local ps = s.posts[i]
			L[#L + 1] = ("  %s:  %d / %d / %s"):format(U.Shorten(ps.name, 24), ps.sends, ps.leads, U.FormatMoney(ps.revenue))
		end
		if #s.posts == 0 then L[#L + 1] = "  none yet" end
		stats:SetText(table.concat(L, "\n"))
	end
end)

-- ---------------------------------------------------------------- main window

local function refreshHeader()
	if not main then return end
	local on, capturing, left = M.TrackingState(U.Now())
	if not on then
		main.track:SetText("Turn on contact tracking")
		main.trackInfo:SetText("Tracking is off. Whispers are not being captured.")
	else
		main.track:SetText("Tracking ON - click to stop")
		local t = DB.R.tracking
		local post = t.post and M.GetPost(t.post)
		local tail = left and ("  (" .. left .. " min left)") or ""
		main.trackInfo:SetText(capturing and ("|cff40ff40Capturing whispers|r for: " .. (post and post.name or "your last post") .. tail)
			or "|cffffff00Waiting for your first post.|r Whispers are captured after you post." .. tail)
	end
	if ns.unsaved > 0 then
		main.save:SetText(("Save %d change%s"):format(ns.unsaved, ns.unsaved == 1 and "" or "s"))
		main.save:Enable()
	else
		main.save:SetText("All saved")
		main.save:Disable()
	end
end

local function build()
	main = Box(UIParent, 800, 540, 0.92)
	main:SetPoint("CENTER")
	main:SetFrameStrata("MEDIUM")
	main:SetToplevel(true)
	main:EnableMouse(true)
	main:SetMovable(true)
	main:SetClampedToScreen(true)
	main:RegisterForDrag("LeftButton")
	main:SetScript("OnDragStart", function(self) self:StartMoving() end)
	main:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	main:Hide()
	_G["WoWCRMFrame"] = main
	tinsert(UISpecialFrames, "WoWCRMFrame")

	At(Label(main, "WoW CRM", "GameFontNormalLarge"), main, 14, -12)
	local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	main.track = At(Button(main, "Turn on contact tracking", 210, function()
		local on = M.TrackingState(U.Now())
		ns.SetTracking(not on)
	end), main, 12, -36)
	main.trackInfo = At(Label(main, "", "GameFontHighlightSmall", 400), main, 230, -41)
	main.save = Button(main, "All saved", 140, function() ns.SaveNow() end)
	main.save:SetPoint("TOPRIGHT", -14, -36)
	main.msg = Label(main, "", "GameFontHighlightSmall", 770)
	main.msg:SetPoint("BOTTOMLEFT", 14, 10)

	for i, name in ipairs(tabOrder) do
		local tab = tabs[name]
		tab.button = At(Button(main, name, 100, function() UI.Show(name) end), main, 12 + (i - 1) * 104, -66)
		tab.panel = CreateFrame("Frame", nil, main)
		tab.panel:SetPoint("TOPLEFT", 12, -98)
		tab.panel:SetPoint("BOTTOMRIGHT", -12, 30)
		tab.panel:Hide()
		tab.build(tab.panel, tab)
	end

	local elapsed = 0
	main:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 5 then elapsed = 0; refreshHeader() end
	end)
end

function UI.Refresh()
	if not main or not main:IsShown() then return end
	refreshHeader()
	if current then tabs[current].Refresh() end
end

function UI.Show(name, selection)
	if not ns.ready then return end
	if not main then build() end
	name = name or current or "Posts"
	if current ~= name then UI.Msg("") end
	current = name
	for _, n in ipairs(tabOrder) do
		local tab = tabs[n]
		if n == name then
			tab.panel:Show()
			tab.button:LockHighlight()
		else
			tab.panel:Hide()
			tab.button:UnlockHighlight()
		end
	end
	main:Show()
	if selection ~= nil and tabs[name].Select then
		tabs[name].Select(selection)
	end
	UI.Refresh()
end

function UI.Toggle()
	if main and main:IsShown() then main:Hide() else UI.Show() end
end

-- ---------------------------------------------------------------- quick-post bar

local BAR_MAX = 10

local function refreshBar()
	if not bar or not bar:IsShown() then return end
	local posts, now = DB.R.posts, U.Now()
	local shown = math.min(#posts, BAR_MAX)
	for i = 1, BAR_MAX do
		local b = bar.buttons[i]
		local post = posts[i]
		if post then
			b.post = post.id
			local target, why = M.NextTarget(post, Chat.Available, now)
			b:SetText(U.Shorten(post.name, 18) .. " > " .. (target and ns.TARGET_LABEL[target] or U.Shorten(why or "-", 16)))
			if target then b:Enable() else b:Disable() end
			b:Show()
		else
			b:Hide()
		end
	end
	bar.empty:SetText(shown == 0 and "No posts yet.\n/crm to create one." or "")
	bar:SetHeight(30 + math.max(1, shown) * 24 + (shown == 0 and 10 or 0))
end

local function buildBar()
	bar = Box(UIParent, 240, 60, 0.85)
	local pos = DB.settings.barPos
	if pos then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else bar:SetPoint("CENTER", 0, -200) end
	bar:EnableMouse(true)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		DB.settings.barPos = { point, rel, x, y }
	end)
	At(Label(bar, "WoW CRM posts", "GameFontNormalSmall"), bar, 10, -8)
	local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() UI.ToggleBar() end)
	bar.empty = At(Label(bar, "", "GameFontHighlightSmall", 220), bar, 10, -26)
	bar.buttons = {}
	for i = 1, BAR_MAX do
		local b = At(Button(bar, "", 220), bar, 10, -24 - (i - 1) * 24)
		b:SetScript("OnClick", function(self)
			local post = self.post and M.GetPost(self.post)
			if not post then return end
			local ok, res = Chat.SendNext(post)
			if not ok then ns.Print(res) end
			refreshBar()
		end)
		bar.buttons[i] = b
	end
	local elapsed = 0
	bar:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 1 then elapsed = 0; refreshBar() end
	end)
end

function UI.ToggleBar()
	if not ns.ready then return end
	if not bar then buildBar(); bar:Hide() end
	if bar:IsShown() then bar:Hide() else bar:Show() end
	DB.settings.barShown = bar:IsShown() and true or false
	refreshBar()
end

-- ---------------------------------------------------------------- probe window

function UI.ShowProbe()
	if not probe then
		probe = Box(UIParent, 420, 190, 0.92)
		probe:SetPoint("CENTER", 0, 120)
		probe:SetFrameStrata("DIALOG")
		At(Label(probe, "WoW CRM client check", "GameFontNormalLarge"), probe, 14, -12)
		At(Label(probe, "Each button says one short line in /say. Click them in order, then Save.", "GameFontHighlightSmall", 390), probe, 14, -36)
		At(Button(probe, "1. Say from a click", 390, function()
			Chat.ProbeSay("click", "WoW CRM check 1")
		end), probe, 14, -60)
		At(Button(probe, "2. Say from a timer (the game should block this)", 390, function()
			Chat.ProbeSay("timer", "WoW CRM check 2")
		end), probe, 14, -86)
		At(Button(probe, "3. Length test: 256 bytes in 128 letters", 390, function()
			Chat.ProbeSay("length", ("\195\169"):rep(128))
		end), probe, 14, -112)
		At(Button(probe, "Save results (reloads the interface)", 300, function() ns.SaveNow() end), probe, 14, -150)
		At(Button(probe, "Close", 80, function() probe:Hide() end), probe, 324, -150)
	end
	probe:Show()
end

-- ---------------------------------------------------------------- wiring

table.insert(ns.listeners, function()
	UI.Refresh()
	refreshBar()
end)

ns.On("PLAYER_LOGIN", function()
	if DB.settings and DB.settings.barShown then
		buildBar()
		refreshBar()
	end
end)
