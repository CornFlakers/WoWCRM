-- The window: Posts, Leads, Contacts, Orders, Mail, Dashboard; plus the quick-post bar.
local _, ns = ...
local U, DB, M, Chat, Mail, Price = ns.Util, ns.DB, ns.Model, ns.Chat, ns.Mail, ns.Price
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

-- Shift-clicked links go to whichever registered box has the cursor in it.
-- The game inserts links through two different functions depending on what was clicked
-- (items and recipes use one, the profession link button the other), so listen to both
-- and ignore the second call when one click reaches both.
local linkEdits = {}
do
	local lastLink, lastAt
	local function insertLink(link)
		if type(link) ~= "string" or link == "" then return end
		local now = GetTime()
		if link == lastLink and now == lastAt then return end
		for _, e in ipairs(linkEdits) do
			if e:IsVisible() and e:HasFocus() then
				lastLink, lastAt = link, now
				e:Insert(link)
				return
			end
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
	if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
end

local function AddTab(name, build)
	tabs[name] = { name = name, build = build }
	tabOrder[#tabOrder + 1] = name
end

-- ---------------------------------------------------------------- Posts

AddTab("Posts", function(p, tab)
	local sel
	local list = At(List(p, 250, 340, function(item) tab.Select(item.id) end), p, 0, 0)
	local X = 264
	local ownerSel

	local function ownerText(key)
		if key == M.ANY then return "any character" end
		if key == nil then return "nobody yet" end
		return U.Display(key, DB.realm)
	end

	At(Label(p, "Name"), p, X, -4)
	local name = At(Edit(p, 200), p, X + 70, 0)
	-- Who posts this: the character whose voice it is written in, or any character.
	local ownerBtn = At(Button(p, "", 210), p, X + 280, 1)
	ownerBtn:SetScript("OnClick", function()
		local post = sel and M.GetPost(sel)
		local options = {}
		if post and post.owner and post.owner ~= M.ANY and post.owner ~= M.me then options[#options + 1] = post.owner end
		options[#options + 1] = M.me
		options[#options + 1] = M.ANY
		local i = U.Contains(options, ownerSel) or 0
		ownerSel = options[i % #options + 1]
		ownerBtn:SetText("Posted by: " .. U.Shorten(ownerText(ownerSel), 20))
		UI.Msg("Press Save post to keep who posts it.")
	end)
	local assign = At(Button(p, "", 250, function()
		local n = M.AssignPosts(M.me)
		UI.Msg(("%d post%s now belong to %s."):format(n, n == 1 and "" or "s", ownerText(M.me)))
		ns.Changed()
	end), p, 0, -346)
	At(Button(p, "Copy this post for me", 250, function()
		local post, err = M.CopyPost(sel)
		if not post then UI.Msg(err, true) return end
		UI.Msg("Copied as " .. post.name .. ". Change the wording to your own voice, then Save post.")
		ns.Changed()
		tab.Select(post.id)
	end), p, 0, -372)
	At(Label(p, "Message"), p, X, -30)
	local counter = At(Label(p, "", "GameFontHighlightSmall"), p, X + 70, -31)
	local text = At(MultiEdit(p, 500, 84), p, X, -48)
	At(Label(p, "Tokens: {me} your name, {zone} current zone. Shift-click an item to link it.", "GameFontDisableSmall"), p, X, -136)

	local checks = {}
	for i, t in ipairs(ns.TARGETS) do
		checks[t] = At(Check(p, ns.TARGET_LABEL[t]), p, X + (i - 1) * 82, -152)
	end

	local function updateCounter()
		local n = U.ByteLen(U.Fill(text.edit:GetText(), { me = ns.MyName() or "", zone = GetZoneText() or "" }))
		counter:SetText(("%d / %d bytes"):format(n, ns.MAX_CHAT_BYTES))
		if n > ns.MAX_CHAT_BYTES then counter:SetTextColor(1, 0.3, 0.3) else counter:SetTextColor(1, 1, 1) end
	end
	text.edit:SetScript("OnTextChanged", updateCounter)

	linkEdits[#linkEdits + 1] = text.edit

	-- A direct route that does not depend on the game's own link button.
	local function professionLink()
		local get = (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillListLink) or GetTradeSkillListLink
		if not get then return nil end
		local ok, link = pcall(get)
		if ok and type(link) == "string" and link ~= "" then return link end
	end

	local function load(post)
		sel = post and post.id or nil
		ownerSel = post and post.owner or (not post and M.me) or nil
		ownerBtn:SetText("Posted by: " .. U.Shorten(ownerText(ownerSel), 20))
		SetEdit(name, post and post.name)
		text.edit:SetText(post and post.text or "")
		for _, t in ipairs(ns.TARGETS) do checks[t]:SetChecked(post and post.targets[t] and true or false) end
		updateCounter()
	end

	At(Button(p, "Save post", 100, function()
		local targets = {}
		for _, t in ipairs(ns.TARGETS) do targets[t] = checks[t]:GetChecked() and true or false end
		local post, err = M.SavePost(sel, name:GetText(), text.edit:GetText(), targets, ownerSel)
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
	At(Button(p, "Link my profession", 160, function()
		local link = professionLink()
		if not link then
			UI.Msg("Open your profession window first, then press this again. (Some professions cannot be linked.)", true)
			return
		end
		text.edit:SetFocus()
		text.edit:Insert(link)
		UI.Msg("Profession link added. Save the post to keep it.")
	end), p, X + 340, -180)

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

	-- Send this post privately: to a named player, or straight back to whoever whispered last.
	At(Label(p, "Whisper this post to"), p, X, -384)
	local whisperTo = At(Edit(p, 150), p, X + 134, -380)
	At(Button(p, "Whisper", 76, function()
		local post = sel and M.GetPost(sel)
		if not post then UI.Msg("Save the post first.", true) return end
		local ok, res = Chat.WhisperPost(post, whisperTo:GetText())
		UI.Msg(ok and ("Whispered to " .. res .. ".") or res, not ok)
	end), p, X + 290, -381)
	local replyBtn = At(Button(p, "Reply to last whisper", 230, function()
		local post = sel and M.GetPost(sel)
		if not post then UI.Msg("Save the post first.", true) return end
		if not ns.lastWhisperFrom then UI.Msg("Nobody has whispered you this session.", true) return end
		local ok, res = Chat.WhisperPost(post, Name(ns.lastWhisperFrom))
		UI.Msg(ok and ("Whispered to " .. res .. ".") or res, not ok)
	end), p, X, -406)
	At(Label(p, "A whisper is private: it is not counted as a post and has no waiting time.", "GameFontDisableSmall", 500), p, X, -434)

	local function updateButtons()
		local post = sel and M.GetPost(sel)
		local now = U.Now()
		replyBtn:SetText(ns.lastWhisperFrom and ("Reply to " .. U.Shorten(Name(ns.lastWhisperFrom), 20)) or "Reply to last whisper")
		if ns.lastWhisperFrom and post then replyBtn:Enable() else replyBtn:Disable() end
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
		local problem = M.OwnerProblem(post)
		if problem then
			for _, t in ipairs(ns.TARGETS) do targetBtns[t]:Disable() end
			replyBtn:Disable()
			nextBtn:SetText("Post next")
			nextBtn:Disable()
			hint:SetText(problem)
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

	-- Select a post id, or pass { to = contactKey } to aim the whisper box at someone.
	function tab.Select(arg)
		if type(arg) == "table" then
			SetEdit(whisperTo, arg.to and Name(arg.to) or "")
			if not sel and DB.R.posts[1] then load(DB.R.posts[1]) end
		else
			load(M.GetPost(arg))
		end
		tab.Refresh()
	end
	function tab.Refresh()
		if sel and not M.GetPost(sel) then load(nil) end
		list:Set(DB.R.posts, function(post)
			local who
			if post.owner == M.me then who = "mine"
			elseif post.owner == M.ANY then who = "any"
			elseif post.owner == nil then who = "|cffff9060not given|r"
			else who = "|cff888888" .. U.Shorten((U.SplitKey(post.owner)), 12) .. "|r" end
			return (M.CanPost(post) and "" or "|cff888888") .. post.name, who
		end, sel)
		local unassigned = M.UnassignedPosts()
		if unassigned > 0 then
			assign:SetText(("Give %d unassigned post%s to me"):format(unassigned, unassigned == 1 and "" or "s"))
			assign:Show()
		else
			assign:Hide()
		end
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
		At(Button(p, "Reply with a post", 140, function()
			local l = lead()
			if l then UI.Show("Posts", { to = l.contact }) end
		end), p, X + 268, -316),
		At(Button(p, "Follow up when online", 190, function()
			local l = lead()
			if not l then return end
			M.SetFollowUp(l.contact, U.Shorten(l.text, 80), U.Now())
			UI.WatchFollowUps()
			UI.Msg("You will be alerted when " .. Name(l.contact) .. " is online. The list is under /crm follow.")
			ns.Changed()
		end), p, X, -342),
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
		local n, second = UnitName("target")
		if not n or not UnitIsPlayer("target") then UI.Msg("Target a player first.", true) return end
		local key = M.JoinName(n, second)
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
	At(Label(p, "Orders  (click one to open it)"), p, X, -292)
	local orders = At(List(p, 500, 112, function(item) UI.Show("Orders", item.id) end), p, X, -308)

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
		end), p, X, -428),
		At(Button(p, "New order", 90, function() if sel then UI.Show("Orders", { contact = sel }) end end), p, X + 114, -428),
		At(Button(p, "Mail", 60, function() if sel then UI.Show("Mail", sel) end end), p, X + 208, -428),
		At(Button(p, "Whisper", 76, function() if sel then Chat.Whisper(sel) end end), p, X + 272, -428),
		At(Button(p, "Delete", 70, function()
			if not sel then return end
			local key = sel
			ns.Confirm("Delete " .. Name(key) .. " and all of their leads and orders?", function()
				M.DeleteContact(key)
				sel = nil
				load()
				ns.Changed()
			end)
		end), p, X + 352, -428),
		At(Button(p, "Follow up", 84, function()
			local c = sel and M.GetContact(sel)
			if not c then return end
			if c.followUp then
				M.ClearFollowUp(c.key)
				UI.Msg("No longer following up with " .. Name(c.key) .. ".")
			else
				M.SetFollowUp(c.key, c.notes:match("[^\n]*") or "", U.Now())
				UI.Msg("You will be alerted when " .. Name(c.key) .. " is online. The list is under /crm follow.")
			end
			UI.WatchFollowUps()
			ns.Changed()
		end), p, X + 426, -428),
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
		buttons[#buttons]:SetText(c and c.followUp and "Stop follow-up" or "Follow up")
		if not c then
			orders:Set({}, function() end)
			stats:SetText("Type a name and press Add, or target a player and press Target.")
			return
		end
		orders:Set(M.OrdersFor(c.key), function(o)
			local gold, goods = M.OrderValue(o)
			local worth = U.FormatMoney(gold) .. (goods > 0 and (" + " .. U.FormatMoney(goods) .. " goods") or "")
			return When(o.created) .. "   " .. M.OrderTitle(o, 44), worth .. "   " .. o.status
		end)
		local ltv, paid, all, ltvGold, ltvGoods = M.LTV(c.key)
		local n, rev = M.Referrals(c.key)
		local src = c.sourcePost and M.GetPost(c.sourcePost)
		stats:SetText(("Lifetime value: |cffffd100%s|r   (%s gold + %s in goods, %d paid of %d orders)\nReferrals made: %d   Revenue from referrals: %s\nFirst seen: %s   Last contact: %s\nCame from post: %s     Follow-ups sent: %d, last %s%s"):format(
			U.FormatMoney(ltv), U.FormatMoney(ltvGold), U.FormatMoney(ltvGoods), paid, all, n, U.FormatMoney(rev), When(c.firstSeen), When(c.lastContact), src and src.name or "-", c.outreach or 0, M.Ago(c.lastOutreach, U.Now()),
			c.followUp and ("\n|cffffd100Following up|r since " .. M.Ago(c.followUp.since, U.Now()) .. ((c.followUp.note or "") ~= "" and (": " .. c.followUp.note) or "")) or ""))
	end
end)

-- ---------------------------------------------------------------- Orders

local function copyLines(lines)
	local out = {}
	for i, l in ipairs(lines or {}) do
		out[i] = { name = l.name, link = l.link, qty = l.qty, value = l.value, kind = l.kind, source = l.source }
	end
	return out
end

-- Reads "qty / name-or-link / value" boxes into a line. Returns nil when the name is empty.
local function readLine(qtyBox, nameBox, valueBox)
	local raw = U.Trim(nameBox:GetText())
	if raw == "" then return nil end
	local line = { qty = math.max(1, math.floor(tonumber(qtyBox:GetText()) or 1)) }
	if raw:find("|H", 1, true) then
		line.link = raw
		line.name = raw:match("%[(.-)%]") or raw
	else
		line.name = raw
	end
	if valueBox then
		local typed = U.Trim(valueBox:GetText())
		if typed ~= "" then
			line.value = U.ParseMoney(typed)
			if not line.value then return nil, "Value not understood. Use a form like 2g 50s." end
			line.source = "typed"
		else
			line.value, line.source = Price.Get(line.link)
		end
	end
	return line
end

AddTab("Orders", function(p, tab)
	local sel
	local sold, recv = {}, {} -- working copies of the order's lines; kept when Save order is pressed
	local selSold, selRecv
	local list = At(List(p, 290, 430, function(item) tab.Select(item.id) end), p, 0, 0)
	local X = 304

	At(Label(p, "Contact"), p, X, -4)
	local contact = At(Edit(p, 170), p, X + 62, 0)
	At(Label(p, "Gold"), p, X + 250, -4)
	local price = At(Edit(p, 120), p, X + 290, 0)
	At(Label(p, "Type"), p, X, -30)
	local otype = At(Cycle(p, ns.ORDER_TYPE, 100), p, X + 58, -26)
	At(Label(p, "Status"), p, X + 180, -30)
	local status = At(Cycle(p, ns.ORDER_STATUS, 120), p, X + 230, -26)
	At(Label(p, "Title"), p, X, -56)
	local desc = At(Edit(p, 400), p, X + 62, -52)
	At(Label(p, "Notes"), p, X, -80)
	local notes = At(Edit(p, 400), p, X + 62, -76)

	At(Label(p, "I gave them"), p, X, -106)
	local soldList = At(List(p, 472, 70, function(item) selSold = item.id; tab.Refresh() end), p, X, -122)
	local sQty = At(Edit(p, 34), p, X + 8, -196)
	local sName = At(Edit(p, 240), p, X + 56, -196)

	At(Label(p, "They gave me"), p, X, -224)
	At(Label(p, "materials for the job are not income; payment and tips are", "GameFontDisableSmall"), p, X + 100, -226)
	local recvList = At(List(p, 472, 88, function(item)
		selRecv = item.id
		local l = recv[item.id]
		if l then
			SetEdit(tab.rQty, tostring(l.qty))
			SetEdit(tab.rName, l.link or l.name)
			SetEdit(tab.rValue, U.FormatMoney(l.value or 0))
		end
		tab.Refresh()
	end), p, X, -240)
	local rQty = At(Edit(p, 34), p, X + 8, -332)
	local rName = At(Edit(p, 180), p, X + 56, -332)
	local rValue = At(Edit(p, 80), p, X + 250, -332)
	tab.rQty, tab.rName, tab.rValue = rQty, rName, rValue
	At(Label(p, "each (blank = look up)", "GameFontDisableSmall"), p, X + 336, -336)
	linkEdits[#linkEdits + 1] = sName
	linkEdits[#linkEdits + 1] = rName

	local summary = At(Label(p, "", "GameFontHighlightSmall", 472), p, X, -386)

	local function touched()
		UI.Msg("Press Save order to keep these changes.")
		tab.Refresh()
	end

	At(Button(p, "Add", 60, function()
		local line = readLine(sQty, sName)
		if not line then UI.Msg("Type an item name, or shift-click an item into the box.", true) return end
		sold[#sold + 1] = line
		SetEdit(sQty, "1"); SetEdit(sName, "")
		touched()
	end), p, X + 306, -197)
	At(Button(p, "Remove", 80, function()
		if selSold and sold[selSold] then table.remove(sold, selSold); selSold = nil; touched() end
	end), p, X + 370, -197)

	local function addReceived(kind)
		local line, err = readLine(rQty, rName, rValue)
		if not line then UI.Msg(err or "Type an item name, or shift-click an item into the box.", true) return end
		line.kind = kind
		recv[#recv + 1] = line
		SetEdit(rQty, "1"); SetEdit(rName, ""); SetEdit(rValue, "")
		selRecv = nil
		touched()
	end
	At(Button(p, "Add payment", 96, function() addReceived("payment") end), p, X, -358)
	At(Button(p, "Add materials", 104, function() addReceived("mats") end), p, X + 100, -358)
	At(Button(p, "Update", 66, function()
		local old = selRecv and recv[selRecv]
		if not old then UI.Msg("Click a line in the list first.", true) return end
		local line, err = readLine(rQty, rName, rValue)
		if not line then UI.Msg(err or "The name is empty.", true) return end
		line.kind = old.kind
		recv[selRecv] = line
		touched()
	end), p, X + 208, -358)
	At(Button(p, "Flip kind", 90, function()
		local l = selRecv and recv[selRecv]
		if not l then UI.Msg("Click a line in the list first.", true) return end
		l.kind = l.kind == "mats" and "payment" or "mats"
		touched()
	end), p, X + 278, -358)
	At(Button(p, "Remove", 76, function()
		if selRecv and recv[selRecv] then table.remove(recv, selRecv); selRecv = nil; touched() end
	end), p, X + 372, -358)

	local function load(o, draft)
		sel = o and o.id or nil
		draft = draft or {}
		sold, recv, selSold, selRecv = copyLines(o and o.items), copyLines(o and o.received), nil, nil
		SetEdit(contact, o and Name(o.contact) or (draft.contact and Name(draft.contact)))
		otype:Set(o and o.type)
		SetEdit(desc, o and o.desc)
		SetEdit(price, o and U.FormatMoney(o.price))
		status:Set(o and o.status)
		SetEdit(notes, o and o.notes)
		SetEdit(sQty, "1"); SetEdit(sName, "")
		SetEdit(rQty, "1"); SetEdit(rName, ""); SetEdit(rValue, "")
	end

	local function save(forceStatus)
		local ctext = contact:GetText()
		local c = M.FindContact(ctext)
		local key = c and c.key or U.NormName(ctext, DB.realm, true)
		local copper = U.ParseMoney(price:GetText())
		if not copper then UI.Msg("Gold amount not understood. Use a form like 12g 50s.", true) return end
		local o, err = M.SaveOrder(sel, {
			contact = key, type = otype.value, desc = desc:GetText(), items = sold, received = recv,
			price = copper, status = forceStatus or status.value, notes = notes:GetText(),
		}, U.Now())
		if not o then UI.Msg(err, true) return end
		load(o)
		UI.Msg("Order saved.")
		ns.Changed()
	end

	At(Button(p, "Save order", 100, function() save() end), p, X, -428)
	At(Button(p, "Mark paid", 90, function() save("paid") end), p, X + 104, -428)
	At(Button(p, "New order", 90, function() load(nil); contact:SetFocus(); tab.Refresh() end), p, X + 198, -428)
	At(Button(p, "Delete", 70, function()
		local o = sel and M.GetOrder(sel)
		if not o then return end
		ns.Confirm("Delete this order?", function() M.DeleteOrder(o.id); load(nil); ns.Changed() end)
	end), p, X + 292, -428)

	-- Select an order id, or pass { contact = key } to start a new order for that contact.
	function tab.Select(arg)
		if type(arg) == "table" then load(nil, arg); sName:SetFocus() else load(M.GetOrder(arg)) end
		tab.Refresh()
	end
	function tab.Refresh()
		if sel and not M.GetOrder(sel) then load(nil) end
		local items = {}
		for _, o in ipairs(DB.R.orders) do items[#items + 1] = o end
		table.sort(items, function(a, b) if a.created ~= b.created then return a.created > b.created end return a.id > b.id end)
		list:Set(items, function(o)
			local gold, goods = M.OrderValue(o)
			return Name(o.contact) .. ": " .. M.OrderTitle(o, 30), U.FormatMoney(gold + goods) .. "  " .. o.status
		end, sel)

		local rows = {}
		for i, l in ipairs(sold) do rows[i] = { id = i, line = l } end
		soldList:Set(rows, function(r) return r.line.qty .. "x " .. (r.line.link or r.line.name) end, selSold)
		rows = {}
		local goods, mats = 0, 0
		for i, l in ipairs(recv) do
			rows[i] = { id = i, line = l }
			local v = (l.value or 0) * l.qty
			if l.kind == "mats" then mats = mats + v else goods = goods + v end
		end
		recvList:Set(rows, function(r)
			local l = r.line
			return ("%dx %s  |cff%s[%s]|r"):format(l.qty, l.link or l.name, l.kind == "mats" and "aaaaaa" or "40ff40", l.kind == "mats" and "materials" or "payment"),
				U.FormatMoney((l.value or 0) * l.qty)
		end, selRecv)

		local gold = U.ParseMoney(price:GetText()) or 0
		local o = sel and M.GetOrder(sel)
		summary:SetText(("Income: |cffffd100%s|r gold + |cffffd100%s|r in goods = |cffffd100%s|r      Materials supplied: %s\n%s"):format(
			U.FormatMoney(gold), U.FormatMoney(goods), U.FormatMoney(gold + goods), U.FormatMoney(mats),
			o and ("Created " .. When(o.created) .. "    Paid " .. When(o.paidAt) .. "    Trades recorded: " .. (o.trades or 0)
				.. "    Counts towards lifetime value only when paid.")
			or "New order. Completed trades offer to fill this in for you."))
	end
	load(nil)
end)

-- ---------------------------------------------------------------- Mail

AddTab("Mail", function(p, tab)
	local sel
	At(Label(p, "Templates"), p, 2, -2)
	local list = At(List(p, 220, 150, function(item) tab.SelectTemplate(item.id) end), p, 0, -18)
	At(Label(p, "Who to write to"), p, 2, -178)
	local filter = At(Cycle(p, ns.FOLLOW_FILTERS, 110), p, 108, -173)
	local follow = At(List(p, 220, 268, function(item) tab.Select(item.key) end), p, 0, -198)
	local toKey
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
	local history = At(Label(p, "", "GameFontHighlightSmall", 530), p, X, -346)
	At(Label(p, "Pick a person on the left and a template, press Fill in letter, read it over, then press Send in the\nmail window. Sending is what counts it. People you wrote to recently drop to the bottom of the list.", "GameFontDisableSmall", 520), p, X, -420)
	filter:HookScript("OnClick", function() tab.Refresh() end)
	to:SetScript("OnTextChanged", function() if tab.Refresh and p:IsShown() then tab.Refresh() end end)

	function tab.SelectTemplate(id) load(M.GetTemplate(id)); tab.Refresh() end
	-- Select a contact key to address the letter to.
	function tab.Select(key) toKey = key; SetEdit(to, Name(key)); tab.Refresh() end
	function tab.Refresh()
		if sel and not M.GetTemplate(sel) then load(nil) end
		if not sel and not tab.started and DB.R.mailTemplates[1] then load(DB.R.mailTemplates[1]) end
		tab.started = true
		list:Set(DB.R.mailTemplates, function(t) return t.name end, sel)
		local now = U.Now()
		local typed = M.FindContact(to:GetText())
		toKey = typed and typed.key or nil
		follow:Set(M.FollowUps(filter.value, now), function(f)
			local bought = M.PurchaseSummary(f.key).done > 0
			local wrote = f.count == 0 and "not written" or ("wrote " .. M.Ago(f.last, now):gsub(" days? ago", "d"))
			return (f.recent and "|cff888888" or "") .. Name(f.key), (bought and "|cff40ff40bought|r, " or "") .. wrote
		end, toKey)
		if typed then
			local ps = M.PurchaseSummary(typed.key)
			local L = { ("|cffffd100%s|r  (%s)"):format(Name(typed.key), typed.status) }
			if ps.done > 0 then
				local o = ps.latest
				L[#L + 1] = ("|cff40ff40Has bought from you:|r %d order%s, %s paid in total. Latest: %s on %s (%s)."):format(
					ps.done, ps.done == 1 and "" or "s", U.FormatMoney(ps.value), M.OrderTitle(o, 50), date("%b %d", o.created), o.status)
				L[#L + 1] = "Suggested: a past-customer letter, such as \"Follow-up: past customer\"."
			elseif ps.orders > 0 then
				L[#L + 1] = ("Has an order that is not finished yet: %s (%s)."):format(M.OrderTitle(ps.latest, 50), ps.latest.status)
				L[#L + 1] = "Suggested: let them know where their order stands."
			else
				L[#L + 1] = "|cffff9060Has not bought anything yet.|r Suggested: a \"still available\" letter."
			end
			L[#L + 1] = ("Follow-up letters sent: %d    Last: %s%s"):format(typed.outreach or 0, M.Ago(typed.lastOutreach, now),
				typed.lastTemplate and ("  with \"" .. typed.lastTemplate .. "\"") or "")
			history:SetText(table.concat(L, "\n"))
		else
			history:SetText("")
		end
		if Mail.open then
			fill:Enable()
			hint:SetText("Mailbox open. The add-on fills in the letter; you press Send.")
		else
			fill:Disable()
			hint:SetText("Open a mailbox to write a letter. Letters are sent one at a time, by you.")
		end
	end
end)

-- ---------------------------------------------------------------- Campaigns

-- A cycle button whose choices can change (professions, categories).
local function DynCycle(parent, w, onChange)
	local b = Button(parent, "-", w)
	b.list = {}
	function b:SetList(list)
		self.list = list
		if not U.Contains(list, self.value) then self.value = list[1] end
		self:SetText(self.value or "-")
	end
	b:SetScript("OnClick", function(self)
		if #self.list == 0 then return end
		local i = U.Contains(self.list, self.value) or 0
		self.value = self.list[i % #self.list + 1]
		self:SetText(self.value)
		if onChange then onChange() end
	end)
	return b
end

local function campaignText(rep, now)
	local c = rep.campaign
	local L = {}
	if c.status == "running" and now < c.ends then
		L[#L + 1] = ("|cffffd100%s|r  -  |cff40ff40running|r, %s left, posts at least %d min apart per channel"):format(c.name, M.Clock(c.ends - now), c.interval)
		if c.character then L[#L] = L[#L] .. ", posted by " .. U.Display(c.character, DB.realm) end
	else
		L[#L + 1] = ("|cffffd100%s|r  -  ran %s to %s"):format(c.name, When(c.started), When(c.endedAt or c.ends))
	end
	L[#L + 1] = ("Posted %d times    Leads: %d    Orders: %d    Income: %s gold + %s in goods"):format(
		rep.sends, rep.leads, rep.orders, U.FormatMoney(rep.gold), U.FormatMoney(rep.goods))
	L[#L + 1] = ("Leads per post: %s    Leads who ordered: %s"):format(M.Rate(rep.leads, rep.sends), M.Rate(rep.orders, rep.leads, true))
	L[#L + 1] = ""
	L[#L + 1] = "|cffffd100By post|r  (times posted / leads / orders / gold + goods)"
	for _, row in ipairs(rep.posts) do
		L[#L + 1] = ("  %s:  %d / %d / %d / %s + %s    |cff888888%s leads per post, %s ordered|r"):format(U.Shorten(row.name, 24), row.sends, row.leads, row.orders,
			U.FormatMoney(row.gold), U.FormatMoney(row.goods), M.Rate(row.leads, row.sends), M.Rate(row.orders, row.leads, true))
		if #row.sold > 0 then L[#L + 1] = "      sold: " .. M.Summary(row.sold, 70) end
	end
	return table.concat(L, "\n")
end

AddTab("Campaigns", function(p, tab)
	local sel
	local chosen, known, primed = {}, {}, false
	local list = At(List(p, 250, 430, function(item) sel = item.id; tab.Refresh() end), p, 0, 0)
	local X = 264

	At(Label(p, "Name"), p, X, -4)
	local name = At(Edit(p, 240), p, X + 60, 0)
	At(Label(p, "Run for"), p, X, -30)
	local minutes = At(Edit(p, 46), p, X + 60, -26)
	At(Label(p, "minutes", "GameFontHighlightSmall"), p, X + 112, -31)
	At(Label(p, "Wait"), p, X + 180, -30)
	local wait = At(Edit(p, 46), p, X + 222, -26)
	At(Label(p, "minutes between posts to one channel", "GameFontHighlightSmall"), p, X + 274, -31)
	At(Label(p, "Posts in this campaign (click to include or leave out)"), p, X, -58)
	local postList = At(List(p, 500, 96, function(item)
		chosen[item.id] = (not chosen[item.id]) or nil
		tab.Refresh()
	end), p, X, -74)

	local start = At(Button(p, "Start campaign", 140, function()
		local ids = {}
		for _, post in ipairs(M.PostsFor()) do
			if chosen[post.id] then ids[#ids + 1] = post.id end
		end
		local c, err = M.StartCampaign(name:GetText(), ids, minutes:GetText(), wait:GetText(), U.Now())
		if not c then UI.Msg(err, true) return end
		sel = c.id
		UI.Msg("Campaign started. Contact tracking is on. Use the campaign bar to post.")
		UI.ShowCampaignBar()
		ns.Changed()
	end), p, X, -176)
	local stop = At(Button(p, "End campaign", 120, function()
		local c = M.EndCampaign(U.Now())
		if c then UI.Msg("Campaign ended.") end
		ns.Changed()
	end), p, X + 146, -176)
	At(Button(p, "Show / hide campaign bar", 190, function() UI.ToggleCampaignBar() end), p, X + 272, -176)
	local report = At(Label(p, "", "GameFontHighlight", 500), p, X, -208)

	function tab.Refresh()
		local now = U.Now()
		if not primed then
			primed = true
			SetEdit(minutes, tostring(DB.settings.campaignMinutes))
			SetEdit(wait, tostring(DB.settings.postInterval))
		end
		-- Posts are ticked by default, including ones written after this tab was first opened.
		for _, post in ipairs(M.PostsFor()) do
			if not known[post.id] then known[post.id] = true; chosen[post.id] = true end
		end
		local active = M.ActiveCampaign(now)
		local items = {}
		for i = #DB.R.campaigns, 1, -1 do items[#items + 1] = DB.R.campaigns[i] end
		list:Set(items, function(c)
			return c.name, (active and c.id == active.id) and "|cff40ff40running|r" or When(c.started)
		end, sel or (active and active.id))
		postList:Set(M.PostsFor(), function(post)
			return (chosen[post.id] and "|cff40ff40[x]|r  " or "[  ]  ") .. post.name, U.Shorten(post.text, 40)
		end)
		if active then start:Disable(); stop:Enable() else start:Enable(); stop:Disable() end

		local rep = M.CampaignReport(sel or (active and active.id))
		if rep then
			report:SetText(campaignText(rep, now))
		elseif #M.PostsFor() == 0 then
			report:SetText("Write a post on the Posts tab first. A campaign is a selling session built from your posts.")
		else
			report:SetText("A campaign is a selling session.\n\n1. Tick the posts to use, set how long to run and how long to wait between posts.\n2. Press Start campaign. Contact tracking switches on.\n3. A small campaign bar tells you when the next post is due. One click sends it.\n\nThe add-on never posts on its own: the game only allows posts that come from your click.\nWhispers, orders and income are then counted against the post that brought them.")
		end
	end
end)

-- ---------------------------------------------------------------- Products
-- Recipes come from Mastercraft's own scan of your professions; prices from TradeSkillMaster,
-- Auctionator or the vendor. This tab only reads that data.

AddTab("Products", function(p, tab)
	local sel
	local prof = At(DynCycle(p, 130, function() sel = nil; tab.Refresh() end), p, 0, 0)
	local cat = At(DynCycle(p, 170, function() tab.Refresh() end), p, 134, 0)
	At(Label(p, "Sort by", "GameFontHighlightSmall"), p, 314, -6)
	local sort = At(Cycle(p, ns.Catalog.SORTS, 110), p, 358, 0)
	sort:HookScript("OnClick", function() tab.Refresh() end)
	At(Label(p, "Find", "GameFontHighlightSmall"), p, 480, -6)
	local search = At(Edit(p, 130), p, 514, -1)
	search:SetScript("OnTextChanged", function() if p:IsShown() and tab.Refresh then tab.Refresh() end end)
	local learned = At(Check(p, "Learned only"), p, 0, -24)
	local craftable = At(Check(p, "Have the mats"), p, 130, -24)
	local mine = At(Check(p, "My products only"), p, 270, -24)
	craftable:SetScript("OnClick", function() tab.Refresh() end)
	learned:SetScript("OnClick", function() tab.Refresh() end)
	mine:SetScript("OnClick", function() tab.Refresh() end)
	local list = At(List(p, 776, 258, function(item)
		if item.header then return end
		sel = item.id
		tab.Refresh()
	end), p, 0, -72)
	-- Which places count towards "have the mats". Remembered between sessions.
	At(Label(p, "Count mats in:", "GameFontHighlightSmall"), p, 4, -52)
	local sourceChecks = {}
	for i, src in ipairs(ns.Inventory.SOURCES) do
		local cb = At(Check(p, ns.Inventory.LABEL[src]), p, 96 + (i - 1) * 118, -46)
		cb:SetScript("OnClick", function(self)
			DB.settings.invSources[src] = self:GetChecked() and true or false
			tab.Refresh()
		end)
		sourceChecks[src] = cb
	end
	local heldFree = At(Check(p, "Mats I hold cost nothing"), p, 404, -24)
	heldFree:SetScript("OnClick", function(self)
		DB.settings.heldFree = self:GetChecked() and true or false
		tab.Refresh()
	end)
	local detail = At(Label(p, "", "GameFontHighlightSmall", 770), p, 4, -338)
	local current

	local toggle = At(Button(p, "Add to products", 150, function()
		if not current then return end
		local key = ns.Catalog.Key(current.profession, current.name)
		if DB.R.products[key] then
			DB.R.products[key] = nil
		else
			DB.R.products[key] = { name = current.name, profession = current.profession, output = current.output }
		end
		ns.Changed()
	end), p, 0, -446)
	At(Button(p, "Refresh", 80, function() Price.Reset(); tab.Refresh() end), p, 154, -446)
	local count = At(Label(p, "", "GameFontDisableSmall", 180), p, 600, -29)
	local shownRows, allRows, loadedFor = {}, {}, nil

	-- Your own asking price for the selected recipe, and quick replies built from it.
	At(Label(p, "My price", "GameFontHighlightSmall"), p, 240, -451)
	local myPrice = At(Edit(p, 76), p, 292, -447)
	At(Button(p, "Set", 40, function()
		if not current then return end
		local v = U.ParseMoney(myPrice:GetText())
		if not v then UI.Msg("Price not understood. Use a form like 2g 50s.", true) return end
		local key = ns.Catalog.Key(current.profession, current.name)
		local entry = DB.R.products[key] or { name = current.name, profession = current.profession, output = current.output }
		entry.price = v > 0 and v or nil
		DB.R.products[key] = entry
		UI.Msg(v > 0 and ("Your price for " .. current.name .. " is " .. U.FormatMoney(v) .. ".") or "Your price cleared; the auction price is used.")
		ns.Changed()
	end), p, 374, -446)
	At(Button(p, "Quote", 60, function()
		if not current then UI.Msg("Click a recipe first.", true) return end
		local who = ns.lastWhisperFrom
		local alt = DB.settings.quoteSmaller and ns.Catalog.SmallerOption(allRows, current) or nil
		local opts = {
			template = DB.settings.quoteText, altTemplate = DB.settings.quoteAlt,
			name = who and (U.SplitKey(who)) or "there",
			label = current.output and Price.ItemLink(current.output),
			altLabel = alt and alt.output and Price.ItemLink(alt.output),
		}
		local text = ns.Catalog.QuoteText(current, alt, opts)
		if text and U.ByteLen(text) > ns.MAX_CHAT_BYTES then
			opts.label, opts.altLabel = nil, nil -- item links are long; use plain names instead
			text = ns.Catalog.QuoteText(current, alt, opts)
		end
		if text and U.ByteLen(text) > ns.MAX_CHAT_BYTES then text = ns.Catalog.QuoteText(current, nil, opts) end
		if not text then UI.Msg("No price yet. Type one in My price and press Set.", true) return end
		Chat.Reply(text, who)
		UI.Msg((who and ("Quote for " .. Name(who)) or "Quote") .. " placed in the chat box. Check it, add anything, then press Enter.")
	end), p, 418, -446)
	At(Button(p, "Quote list", 80, function()
		local text, n = ns.Catalog.QuoteList(shownRows, ns.MAX_CHAT_BYTES - 3)
		if n == 0 then UI.Msg("Nothing in this list has a price yet.", true) return end
		Chat.Reply(text, ns.lastWhisperFrom)
		UI.Msg(("Price list of %d items placed in the chat box. Press Enter to send."):format(n))
	end), p, 482, -446)
	At(Button(p, "Codex", 80, function()
		local slash = SlashCmdList and SlashCmdList["MASTERCRAFT"]
		local toggle = rawget(_G, "Mastercraft_Toggle")
		if type(slash) == "function" then
			slash("codex")
		elseif type(toggle) == "function" then
			toggle()
		else
			UI.Msg("Mastercraft is not installed or not enabled.", true)
			return
		end
		UI.Msg(current and ("Mastercraft's Codex is open: choose Recipes and search for " .. current.name .. ". Its pin button sets the waypoint.")
			or "Mastercraft's Codex is open: choose Recipes. A recipe's pin button sets the waypoint.")
	end), p, 566, -446)
	At(Button(p, "Wowhead", 90, function()
		if not current then UI.Msg("Click a recipe first.", true) return end
		UI.ShowLink("Wowhead page for " .. current.name, ns.Catalog.WowheadURL(current))
		UI.Msg("Copy the address into your web browser. The page lists the pattern and where it comes from.")
	end), p, 650, -446)

	local function source()
		local db = rawget(_G, "MastercraftDB")
		local guid = UnitGUID and UnitGUID("player")
		local mine = type(db) == "table" and type(db.recipes) == "table" and guid and db.recipes[guid]
		return type(mine) == "table" and mine or nil
	end

	local function money(v) return v > 0 and U.FormatMoney(v) or "?" end

	-- What the game itself knows about this character: bags now, and the bank as last seen.
	local function inBags(itemID)
		local get = (C_Item and C_Item.GetItemCount) or GetItemCount
		if not get then return 0 end
		local ok, n = pcall(get, itemID)
		return ok and tonumber(n) or 0
	end
	local function inBank(itemID)
		local get = (C_Item and C_Item.GetItemCount) or GetItemCount
		if not get then return 0 end
		local ok, n = pcall(get, itemID, true)
		return math.max(0, (ok and tonumber(n) or 0) - inBags(itemID))
	end
	local partsOf = function() return "none" end

	-- Item id -> the profession that makes it, across every character Mastercraft has scanned.
	local function craftedBy()
		local out = {}
		local db = rawget(_G, "MastercraftDB")
		for _, profs in pairs(type(db) == "table" and type(db.recipes) == "table" and db.recipes or {}) do
			for profName, data in pairs(type(profs) == "table" and profs or {}) do
				for _, r in ipairs(type(data) == "table" and type(data.list) == "table" and data.list or {}) do
					if r.output and not out[r.output] then out[r.output] = profName end
				end
			end
		end
		return out
	end

	function tab.Refresh()
		current = nil
		local src = source()
		local profs = {}
		for k, v in pairs(src or {}) do
			if type(v) == "table" and type(v.list) == "table" then profs[#profs + 1] = k end
		end
		table.sort(profs)
		prof:SetList(profs)
		if #profs == 0 then
			cat:SetList({ "All" })
			list:Set({}, function() end)
			toggle:Disable()
			count:SetText("")
			detail:SetText("No recipe list found for this character.\n\nThis tab reads the recipes that the Mastercraft add-on scans. Install and enable Mastercraft, open your\nprofession window once so it can scan, then come back here.")
			return
		end

		local mc, enabled = rawget(_G, "MastercraftDB"), DB.settings.invSources
		for name, cb in pairs(sourceChecks) do cb:SetChecked(enabled[name] and true or false) end
		local held = ns.Inventory.Collect({
			mastercraft = type(mc) == "table" and mc.inv or nil, guid = UnitGUID and UnitGUID("player"),
			brother = rawget(_G, "BrotherBags"), name = UnitName("player"),
		})
		local countOf
		countOf, partsOf = ns.Inventory.Counter(held, enabled, inBags, inBank)
		local rows = ns.Catalog.Build(src[prof.value].list, prof.value, function(id) return (Price.GetByID(id)) end,
			M.SoldCounts(), DB.R.products, countOf, Price.BagSlots, DB.settings.heldFree)
		heldFree:SetChecked(DB.settings.heldFree and true or false)
		local costWord = DB.settings.heldFree and "to buy" or "mats"
		allRows = rows
		cat:SetList(ns.Catalog.Categories(rows))
		local filtered = ns.Catalog.Filter(rows, {
			category = cat.value, learnedOnly = learned:GetChecked(), craftableOnly = craftable:GetChecked(),
			productsOnly = mine:GetChecked(), search = search:GetText(),
		})
		local shown = ns.Catalog.Group(filtered, sort.value)
		shownRows = shown
		list:Set(shown, function(r)
			if r.header then return "|cffffd100" .. r.name .. "|r  |cff888888(" .. r.count .. ")|r", "" end
			return "   " .. (r.product and "|cffffd100*|r " or "") .. r.name .. (r.slots and ("  |cff80c0ff" .. r.slots .. " slot|r") or "")
					.. (r.learned and "" or "  |cff888888not learned|r"),
				(r.canMake > 0 and ("|cff40ff40can make " .. r.canMake .. "|r    ") or "") .. ("%s %s    AH %s%s    margin %s    sold %d"):format(costWord, (r.cost == 0 and r.mats > 0) and "0" or money(r.cost), money(r.sale),
					r.myPrice and ("    |cffffd100yours " .. U.FormatMoney(r.myPrice) .. "|r") or "",
					r.price > 0 and ((r.margin < 0 and "-" or "") .. U.FormatMoney(math.abs(r.margin))) or "?", r.sold)
		end, sel)
		count:SetText(("%d of %d recipes   * = my products"):format(#filtered, #rows))

		for _, r in ipairs(shown) do if not r.header and r.id == sel then current = r end end
		if loadedFor ~= sel then
			loadedFor = sel
			SetEdit(myPrice, current and current.myPrice and U.FormatMoney(current.myPrice) or "")
		end
		if not current then
			toggle:Disable()
			detail:SetText("Click a recipe to see its materials. Mark the things you sell as your products to find them quickly.")
			return
		end
		toggle:Enable()
		toggle:SetText(current.product and "Remove product" or "Add to products")
		local L = { ("|cffffd100%s|r  -  %s, %s%s    %s"):format(current.name, current.category, current.learned and "learned" or "not learned",
			current.outputQty > 1 and (", makes " .. current.outputQty) or "",
			current.canMake > 0 and ("|cff40ff40You hold the materials for " .. current.canMake .. "|r") or "You do not hold all the materials in the places ticked above") }
		if not current.learned then
			local how = type(current.id) == "number" and Price.RecipeSource(current.id)
			L[#L + 1] = how and ("|cffffd100How to get this pattern:|r " .. how)
				or "|cffffd100How to get this pattern:|r not known yet. Open your profession window and click it again, or use Codex or Wowhead below."
		end
		local makers = craftedBy()
		for _, g in ipairs(current.reagents) do
			L[#L + 1] = ("   %dx %s    |cff%s(have %d: %s)|r    %s each    %s%s"):format(g.qty, Price.ItemName(g.itemID),
				g.have >= g.qty and "40ff40" or "ff6060", g.have, partsOf(g.itemID), money(g.each),
				g.short == 0 and "|cff40ff40nothing to buy|r" or ("buy " .. g.short .. " = " .. money(g.each * g.short)),
				makers[g.itemID] and ("    |cffffd100made by " .. makers[g.itemID] .. "|r") or "")
		end
		L[#L + 1] = ("All mats at today's price %s%s    |cffffd100Still to buy %s|r    Auction price %s    Your price %s    Margin %s (%s)    Sold: %d"):format(money(current.mats),
			current.unpriced > 0 and (" (" .. current.unpriced .. " without a price)") or "",
			current.buy == 0 and (current.unpricedBuy > 0 and "?" or "nothing") or U.FormatMoney(current.buy), money(current.sale),
			current.myPrice and U.FormatMoney(current.myPrice) or "not set",
			current.price > 0 and ((current.margin < 0 and "-" or "") .. U.FormatMoney(math.abs(current.margin))) or "?",
			DB.settings.heldFree and "after what you hold" or "at full mats price", current.sold)
		detail:SetText(table.concat(L, "\n"))
	end
end)

-- ---------------------------------------------------------------- Dashboard

AddTab("Dashboard", function(p, tab)
	local stats = At(Label(p, "", "GameFontHighlight", 400), p, 4, -4)
	local X = 420
	At(Label(p, "Backup"), p, X, -4)
	local box = At(MultiEdit(p, 350, 110), p, X, -22)
	At(Button(p, "Export", 80, function()
		box.edit:SetText(M.Export())
		box.edit:SetFocus()
		box.edit:HighlightText()
		UI.Msg("Press Ctrl+C to copy, then paste it somewhere safe.")
	end), p, X, -138)
	At(Button(p, "Import", 80, function()
		local textIn = box.edit:GetText()
		ns.Confirm("Merge the pasted export into your CRM data?", function()
			local added, err = M.Import(textIn, U.Now())
			if not added then UI.Msg(err, true) return end
			UI.Msg(("Imported %d posts, %d contacts, %d orders."):format(added.posts, added.contacts, added.orders))
			ns.Changed()
		end)
	end), p, X + 84, -138)
	At(Button(p, "Save now", 80, function() ns.SaveNow() end), p, X + 168, -138)
	At(Button(p, "Delete all data", 110, function()
		ns.Confirm("Delete ALL WoW CRM data for this realm? This cannot be undone.", function()
			DB.WipeRealm()
			UI.Msg("All data for this realm deleted.")
			ns.Changed()
		end)
	end), p, X + 240, -138)
	At(Label(p, "Data is written to disk when you log out or press a Save button (it reloads the interface).", "GameFontDisableSmall", 350), p, X, -166)
	local hours = At(Label(p, "", "GameFontHighlightSmall", 350), p, X, -200)

	function tab.Refresh()
		local H = { "|cffffd100By hour of day|r  (posts / leads / orders / income from posts made in that hour)" }
		local hourRows = M.HourReport()
		for _, r in ipairs(hourRows) do
			H[#H + 1] = ("  %02d:00    %d / %d / %d / %s    |cff888888%s leads per post|r"):format(r.hour, r.sends, r.leads, r.orders,
				U.FormatMoney(r.income), M.Rate(r.leads, r.sends))
		end
		if #hourRows == 0 then H[#H + 1] = "  nothing yet - this fills in as you post" end
		hours:SetText(table.concat(H, "\n"))
		local s = M.Stats()
		local L = {
			("|cffffd100Income (paid orders):|r %s"):format(U.FormatMoney(s.revenue)),
			("  %s in gold + %s in goods received as payment"):format(U.FormatMoney(s.gold), U.FormatMoney(s.goods)),
			("  Materials customers supplied (not income): %s"):format(U.FormatMoney(s.mats)),
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
		L[#L + 1] = "|cffffd100Posts, all time|r  (times posted / leads / gold + goods)"
		for i = 1, math.min(6, #s.posts) do
			local ps = s.posts[i]
			L[#L + 1] = ("  %s:  %d / %d / %s + %s   |cff888888%s leads per post|r"):format(U.Shorten(ps.name, 20), ps.sends, ps.leads,
				U.FormatMoney(ps.gold), U.FormatMoney(ps.goods), M.Rate(ps.leads, ps.sends))
			if #ps.sold > 0 then L[#L + 1] = "      sold: " .. M.Summary(ps.sold, 54) end
		end
		if #s.posts == 0 then L[#L + 1] = "  none yet" end
		stats:SetText(table.concat(L, "\n"))
	end
end)

-- ---------------------------------------------------------------- Options

AddTab("Options", function(outer, tab)
	local sf = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 0, 0)
	sf:SetPoint("BOTTOMRIGHT", -26, 30)
	local p = CreateFrame("Frame", nil, sf)
	p:SetSize(740, 720)
	sf:SetScrollChild(p)

	local fields, y = {}, 0
	local function header(text)
		At(Label(p, text), p, 0, y - 4)
		y = y - 24
	end
	local function number(key, text, min, max)
		At(Label(p, text, "GameFontHighlightSmall"), p, 12, y - 4)
		fields[#fields + 1] = { key = key, min = min, max = max, edit = At(Edit(p, 60), p, 600, y) }
		y = y - 24
	end
	local function word(key, text)
		At(Label(p, text, "GameFontHighlightSmall"), p, 12, y - 4)
		fields[#fields + 1] = { key = key, text = true, edit = At(Edit(p, 120), p, 600, y) }
		y = y - 24
	end
	local function wide(key, text)
		At(Label(p, text, "GameFontHighlightSmall"), p, 12, y - 4)
		y = y - 18
		fields[#fields + 1] = { key = key, text = true, edit = At(Edit(p, 690), p, 20, y) }
		y = y - 28
	end
	local function check(key, text)
		fields[#fields + 1] = { key = key, check = At(Check(p, text), p, 8, y) }
		y = y - 24
	end

	header("Posting")
	number("minGap", "Seconds between posts to the same public channel when no campaign is running (minimum " .. DB.MIN_GAP_FLOOR .. ")", DB.MIN_GAP_FLOOR)
	number("publicSpacing", "Minutes between any two posts to Say, Yell, General or Trade, from every button (0 = off)", 0)
	word("generalName", "Name of the General channel")
	word("tradeName", "Name of the Trade channel")
	header("Campaigns")
	number("campaignMinutes", "Usual length of a campaign, in minutes", 1)
	number("postInterval", "Usual wait between posts to the same channel during a campaign, in minutes", 1)
	check("campaignSound", "Play a sound when the next campaign post is due")
	header("Leads and orders")
	number("trackAutoOff", "Contact tracking turns off this many minutes after your last post (0 = never)", 0)
	number("orderWindow", "A follow-up trade joins the same order for this many minutes", 1)
	check("promptStrangers", "Offer to record sales to people who are not contacts yet")
	header("Price quotes")
	check("quoteSmaller", "Also offer the next smaller, cheaper bag of the same kind")
	wide("quoteText", "Quote wording.  {name} = who asked,  {item} = the item and its size,  {price} = your price")
	wide("quoteAlt", "Cheaper option wording, added after the quote.  {alt} = the smaller bag and its size,  {altprice} = its price")
	header("Follow-up letters")
	number("outreachGap", "Days before someone you wrote to returns to the top of the follow-up list", 0)
	header("Window")
	number("windowScale", "Window size, percent (60 to 150). You can also drag the window's bottom-right corner.", 60, 150)
	check("showMinimap", "Show the minimap button (click: window, right-click: quick-post bar)")
	header("Backups  (logging out always saves; this only guards against a crash)")
	check("saveReminder", "Offer a backup at quiet moments (standing still or resting, never in combat or while trading)")
	number("saveAfterChanges", "...once this many changes are waiting", 1)
	number("saveAfterMinutes", "...or once the oldest waiting change is this many minutes old", 1)
	p:SetHeight(-y + 20)

	local function load()
		for _, f in ipairs(fields) do
			local v = DB.settings[f.key]
			if f.check then f.check:SetChecked(v and true or false) else SetEdit(f.edit, tostring(v)) end
		end
	end

	local apply = Button(outer, "Apply options", 130, function()
		local s = DB.settings
		for _, f in ipairs(fields) do
			if f.check then
				s[f.key] = f.check:GetChecked() and true or false
			elseif f.text then
				local v = U.Trim(f.edit:GetText())
				if v ~= "" then s[f.key] = v end
			else
				local v = tonumber(f.edit:GetText())
				if v then
					v = math.max(f.min or 0, math.floor(v))
					if f.max then v = math.min(f.max, v) end
					s[f.key] = v
				end
			end
		end
		load()
		UI.ApplyScale()
		UI.UpdateMinimap()
		UI.Msg("Options applied.")
		ns.Changed()
	end)
	apply:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 0, 2)
	At(Label(outer, "Scroll for more options.", "GameFontDisableSmall"), outer, 140, -447)

	function tab.Refresh()
		if not tab.loaded then tab.loaded = true; load() end
	end
end)

-- ---------------------------------------------------------------- campaign bar
-- Shows what is due next in the running campaign. The button is the only thing that posts.

local cbar
local wasDue, lastCampaign = false, nil

local function alertDue(post, target)
	if DB.settings.campaignSound and PlaySound then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
	end
	ns.Print(("campaign: time to post |cffffff00%s|r to %s. Click the campaign bar."):format(post.name, ns.TARGET_LABEL[target]))
end

local function buildCampaignBar()
	cbar = Box(UIParent, 270, 78, 0.9)
	local pos = DB.settings.campaignBarPos
	if pos then cbar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else cbar:SetPoint("TOP", 0, -180) end
	cbar:SetFrameStrata("MEDIUM")
	cbar:EnableMouse(true)
	cbar:SetMovable(true)
	cbar:SetClampedToScreen(true)
	cbar:RegisterForDrag("LeftButton")
	cbar:SetScript("OnDragStart", function(self) self:StartMoving() end)
	cbar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		DB.settings.campaignBarPos = { point, rel, x, y }
	end)
	cbar.title = At(Label(cbar, "", "GameFontNormalSmall", 230), cbar, 10, -9)
	local close = CreateFrame("Button", nil, cbar, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() cbar:Hide() end)
	cbar.post = At(Button(cbar, "", 250, function()
		local ok, res = Chat.CampaignPost()
		if not ok then ns.Print(res) end
		UI.CampaignTick()
	end), cbar, 10, -28)
	cbar.post:SetHeight(30)
	cbar.info = At(Label(cbar, "", "GameFontDisableSmall", 250), cbar, 10, -62)
	cbar:Hide()
end

-- Runs once a second: closes a campaign whose time is up, sounds the "due" alert once,
-- and keeps the bar's text current.
function UI.CampaignTick()
	if not ns.ready then return end
	local now = U.Now()
	local c, finished = M.ActiveCampaign(now)
	if finished then
		local rep = M.CampaignReport(finished.id)
		ns.Print(("campaign \"%s\" finished: posted %d times, %d leads, %d orders, %s gold + %s in goods so far."):format(
			finished.name, rep.sends, rep.leads, rep.orders, U.FormatMoney(rep.gold), U.FormatMoney(rep.goods)))
		wasDue = false
		ns.OfferSave()
		ns.Changed(true)
	end
	if not c then
		if cbar and cbar:IsShown() then
			cbar.title:SetText("No campaign running")
			cbar.post:SetText("Start one on the Campaigns tab")
			cbar.post:Disable()
			cbar.info:SetText("")
		end
		lastCampaign = nil
		return
	end
	if lastCampaign ~= c.id then lastCampaign, wasDue = c.id, false end

	local post, target, wait = M.CampaignNext(c, Chat.Available, now)
	local due = post ~= nil
	if due and not wasDue then alertDue(post, target) end
	wasDue = due

	if not cbar or not cbar:IsShown() then return end
	cbar.title:SetText(("%s  -  %s left"):format(U.Shorten(c.name, 22), M.Clock(c.ends - now)))
	if due then
		cbar.post:SetText(U.Shorten(post.name, 20) .. " > " .. ns.TARGET_LABEL[target])
		cbar.post:Enable()
		cbar.post:LockHighlight()
		cbar.info:SetText("Due now. One click sends this one message.")
	else
		cbar.post:SetText(wait and ("Next post in " .. M.Clock(wait)) or "No channel available here")
		cbar.post:Disable()
		cbar.post:UnlockHighlight()
		cbar.info:SetText(wait and "Waiting out the gap so you are not spamming." or "Join General or Trade, or move to a city.")
	end
end

function UI.ShowCampaignBar()
	if not ns.ready then return end
	if not cbar then buildCampaignBar() end
	cbar:Show()
	UI.CampaignTick()
end

function UI.ToggleCampaignBar()
	if cbar and cbar:IsShown() then cbar:Hide() else UI.ShowCampaignBar() end
end

do
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then elapsed = 0; UI.CampaignTick() end
	end)
	UI.campaignTicker = ticker
end

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
		main.save:SetText(("Back up now (%d)"):format(ns.unsaved))
		main.save:Enable()
	else
		main.save:SetText("Nothing to back up")
		main.save:Disable()
	end
end

local function build()
	main = Box(UIParent, 800, 600, 0.92)
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
	main.msg = Label(main, "", "GameFontHighlightSmall", 740)
	main.msg:SetPoint("BOTTOMLEFT", 14, 10)

	-- Drag the bottom-right corner to make the whole window bigger or smaller.
	local grip = CreateFrame("Button", nil, main)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		local rel = main:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local left, top = main:GetLeft() * rel, main:GetTop() * rel
		grip:SetScript("OnUpdate", function()
			local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
			local scale = math.min(1.5, math.max(0.6, (cx - left) / 800))
			main:SetScale(scale)
			main:ClearAllPoints()
			main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		grip:SetScript("OnUpdate", nil)
		DB.settings.windowScale = math.floor(main:GetScale() * 100 + 0.5)
	end)

	for i, name in ipairs(tabOrder) do
		local tab = tabs[name]
		tab.button = At(Button(main, name, 84, function() UI.Show(name) end), main, 12 + (i - 1) * 86, -66)
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
	UI.ApplyScale()
end

function UI.ApplyScale()
	if main then main:SetScale(math.min(1.5, math.max(0.6, (DB.settings.windowScale or 100) / 100))) end
end

function UI.Refresh()
	if not main or not main:IsShown() then return end
	refreshHeader()
	if current then tabs[current].Refresh() end
end

function UI.Show(name, selection)
	if not ns.ready then return end
	if not main then build() end
	name = name or current or "Campaigns"
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
local BAR_TOP = 124 -- where the single-post buttons start

local function refreshBar()
	if not bar or not bar:IsShown() then return end
	local posts, now = M.PostsFor(), U.Now()

	bar.title:SetText("WoW CRM posts for " .. U.Shorten((U.SplitKey(M.me or "")), 18))

	-- The one-button cycle.
	local chans = DB.settings.cycleChannels
	for t, cb in pairs(bar.chanChecks) do cb:SetChecked(chans[t] and true or false) end
	local post, target, wait, why = M.CycleNext(chans, Chat.Available, now)
	if post then
		bar.cycle:SetText("Next: " .. U.Shorten(post.name, 18) .. " > " .. ns.TARGET_LABEL[target])
		bar.cycle:Enable()
		local sp = DB.settings.publicSpacing or 0
		bar.cycleInfo:SetText(sp > 0 and ("One tap sends one message, then a " .. sp .. " minute pause.") or "One tap sends one message.")
	else
		bar.cycle:SetText(wait and ("Next post in " .. M.Clock(wait)) or "Nothing to post")
		bar.cycle:Disable()
		bar.cycleInfo:SetText(why or "Pausing so the channels are not flooded.")
	end

	-- One button per post.
	local shown = math.min(#posts, BAR_MAX)
	for i = 1, BAR_MAX do
		local b = bar.buttons[i]
		local p = posts[i]
		if p then
			b.post = p.id
			local t, whyNot = M.NextTarget(p, Chat.Available, now)
			b:SetText(U.Shorten(p.name, 18) .. " > " .. (t and ns.TARGET_LABEL[t] or U.Shorten(whyNot or "-", 18)))
			if t then b:Enable() else b:Disable() end
			b:Show()
		else
			b:Hide()
		end
	end
	bar.empty:SetText(shown == 0 and "No posts for this character yet. Write one on the Posts tab, or set a post to any character." or "")
	bar:SetHeight(BAR_TOP + 10 + math.max(1, shown) * 24)
end

local function buildBar()
	bar = Box(UIParent, 280, 160, 0.85)
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
	bar.title = At(Label(bar, "WoW CRM posts", "GameFontNormalSmall", 230), bar, 10, -8)
	local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() UI.ToggleBar() end)

	bar.cycle = At(Button(bar, "", 260, function()
		local ok, res = Chat.CycleSend(DB.settings.cycleChannels)
		if not ok then ns.Print(res) end
		refreshBar()
	end), bar, 10, -26)
	bar.cycle:SetHeight(30)
	bar.cycleInfo = At(Label(bar, "", "GameFontDisableSmall", 260), bar, 10, -60)
	bar.chanChecks = {}
	for i, t in ipairs(ns.CYCLE_CHANNELS) do
		local cb = At(Check(bar, ns.TARGET_LABEL[t]), bar, 8 + (i - 1) * 86, -74)
		cb:SetScript("OnClick", function(self)
			DB.settings.cycleChannels[t] = self:GetChecked() and true or false
			refreshBar()
		end)
		bar.chanChecks[t] = cb
	end
	At(Label(bar, "Or send one post now:", "GameFontDisableSmall"), bar, 10, -104)

	bar.empty = At(Label(bar, "", "GameFontHighlightSmall", 260), bar, 10, -BAR_TOP)
	bar.buttons = {}
	for i = 1, BAR_MAX do
		local b = At(Button(bar, "", 260), bar, 10, -BAR_TOP - (i - 1) * 24)
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

-- ---------------------------------------------------------------- minimap button

local mm

local function placeMinimap()
	local angle = math.rad(DB.settings.minimapAngle or 200)
	local r = ((Minimap:GetWidth() or 140) / 2) + 6
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function UI.UpdateMinimap()
	if not mm then return end
	if DB.settings.showMinimap then mm:Show() else mm:Hide() end
end

local function buildMinimap()
	if mm or not Minimap then return end
	mm = CreateFrame("Button", "WoWCRMMinimapButton", Minimap)
	mm:SetSize(31, 31)
	mm:SetFrameStrata("MEDIUM")
	mm:SetFrameLevel(8)
	mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mm:RegisterForDrag("LeftButton")
	mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = mm:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = mm:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = mm:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	mm:SetScript("OnClick", function(_, button)
		if button == "RightButton" then UI.ToggleBar() else UI.Toggle() end
	end)
	mm:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("WoW CRM")
		GameTooltip:AddLine("Click: open the window\nRight-click: quick-post bar\nDrag: move this button", 1, 1, 1)
		GameTooltip:Show()
	end)
	mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
	mm:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			local atan2 = math.atan2 or math.atan
			DB.settings.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
			placeMinimap()
		end)
	end)
	mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	placeMinimap()
	UI.UpdateMinimap()
end

-- ---------------------------------------------------------------- the game's AddOns settings list

local function registerSettings()
	local panel = CreateFrame("Frame")
	panel.name = "WoW CRM"
	At(Label(panel, "WoW CRM", "GameFontNormalLarge"), panel, 16, -16)
	At(Label(panel, "Customers, posts, campaigns and orders. Most settings are on the Options tab of the WoW CRM window.", "GameFontHighlight", 580), panel, 16, -46)
	local function openThen(fn)
		return function()
			if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
			fn()
		end
	end
	At(Button(panel, "Open WoW CRM", 160, openThen(function() UI.Show() end)), panel, 16, -84)
	At(Button(panel, "Open the Options tab", 160, openThen(function() UI.Show("Options") end)), panel, 182, -84)
	At(Button(panel, "Quick-post bar", 160, openThen(function() UI.ToggleBar() end)), panel, 348, -84)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "WoW CRM")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

-- ---------------------------------------------------------------- follow-ups: online alerts
-- The game tells an add-on when someone on your friends list logs in or out, so contacts you
-- follow up with are added to the friends list of the character you are playing (the other
-- player is not told). They are also noticed when they speak in a channel or near you.

local friendOnline = {} -- contact key -> online, as last reported by the friends list
local fwin
local FW_MAX = 10

local function friendsList()
	local out = {}
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and info.name then out[#out + 1] = { name = info.name, online = info.connected and true or false } end
		end
	elseif GetNumFriends and GetFriendInfo then
		for i = 1, GetNumFriends() or 0 do
			local name, _, _, _, connected = GetFriendInfo(i)
			if name then out[#out + 1] = { name = name, online = connected and true or false } end
		end
	end
	return out
end

local function friendKeys()
	local keys = {}
	for _, f in ipairs(friendsList()) do
		local key = U.NormName(f.name, DB.realm)
		if key then keys[key] = f end
	end
	return keys
end

-- Follow-ups not yet on this character's friends list.
function UI.UnwatchedFollowUps()
	local watching, friends, n = M.Watching(), friendKeys(), 0
	for _, c in ipairs(M.OnlineFollowUps()) do
		if not watching[c.key] and not friends[c.key] then n = n + 1 end
	end
	return n
end

-- Puts this character's friends list in step with the follow-ups: adds new ones, and removes the
-- entries WoW CRM added for people no longer followed up. Real friends are never touched.
-- Runs from a click or a typed command.
function UI.WatchFollowUps(verbose)
	local add = (C_FriendList and C_FriendList.AddFriend) or AddFriend
	local remove = (C_FriendList and C_FriendList.RemoveFriend) or RemoveFriend
	if not add then return end
	local watching, friends, wanted = M.Watching(), friendKeys(), {}
	local added, removed = 0, 0
	for _, c in ipairs(M.OnlineFollowUps()) do
		wanted[c.key] = true
		if not watching[c.key] and not friends[c.key] then
			add(Name(c.key), "WoW CRM follow-up")
			watching[c.key] = true
			added = added + 1
		end
	end
	for key in pairs(watching) do
		if not wanted[key] then
			if remove then remove(Name(key)) end
			watching[key] = nil
			removed = removed + 1
		end
	end
	if verbose then
		ns.Print(("follow-ups on this character's friends list: %d added, %d removed."):format(added, removed))
	end
	UI.RefreshFollowUps()
end

local function alert(c, how)
	local who = Name(c.key)
	local note = (c.followUp.note or "") ~= "" and ("  You noted: " .. c.followUp.note) or ""
	ns.Print(("|cffffff00%s is online|r (%s). Time to follow up.%s"):format(who, how, note))
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, "WoW CRM: " .. who .. " is online - follow up!",
			(ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.8, b = 0 })
	end
	if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
	UI.ShowFollowUps()
	ns.Changed(true)
end

ns.On("FRIENDLIST_UPDATE", function()
	if not ns.ready then return end
	local now = U.Now()
	for key, f in pairs(friendKeys()) do
		local c = M.GetContact(key)
		if c then
			local was = friendOnline[key]
			friendOnline[key] = f.online
			if f.online and was ~= true and c.followUp then
				if M.SeenOnline(key, now, was == nil and "online" or "came online") then
					alert(c, was == nil and "already online" or "just logged in")
				end
			end
		end
	end
	UI.RefreshFollowUps()
end)

local function sighted(how)
	return function(_, sender)
		if not ns.ready or type(sender) ~= "string" or (issecretvalue and issecretvalue(sender)) then return end
		local key = U.NormName(sender, DB.realm)
		local c = key and M.GetContact(key)
		if c and M.SeenOnline(key, U.Now(), how) then alert(c, how) end
	end
end
ns.On("CHAT_MSG_CHANNEL", sighted("talking in a channel"))
ns.On("CHAT_MSG_SAY", sighted("near you"))
ns.On("CHAT_MSG_YELL", sighted("near you"))
ns.On("CHAT_MSG_WHISPER", sighted("whispering you"))

function UI.RefreshFollowUps()
	if not fwin or not fwin:IsShown() then return end
	local list, now = M.OnlineFollowUps(), U.Now()
	for i = 1, FW_MAX do
		local row, c = fwin.rows[i], list[i]
		if c then
			row.key = c.key
			local status
			if friendOnline[c.key] then status = "|cff40ff40online|r"
			elseif c.lastSeen and now - c.lastSeen < 600 then status = "|cff40ff40seen " .. M.Ago(c.lastSeen, now) .. "|r"
			elseif friendOnline[c.key] == false then status = "|cff888888offline|r"
			else status = "|cff888888not watched|r" end
			row.name:SetText(U.Shorten(Name(c.key), 18) .. "  " .. status)
			row.note:SetText(U.Shorten(((c.followUp.note or "") ~= "" and c.followUp.note or "no note") .. "  (since " .. M.Ago(c.followUp.since, now) .. ")", 60))
			row.name:Show(); row.note:Show(); row.whisper:Show(); row.done:Show()
		else
			row.name:Hide(); row.note:Hide(); row.whisper:Hide(); row.done:Hide()
		end
	end
	local n = #list
	local unwatched = UI.UnwatchedFollowUps()
	fwin.info:SetText(n == 0 and "Nobody to follow up with. Use Follow up on the Leads or Contacts tab."
		or (unwatched > 0 and ("|cffff9060" .. unwatched .. " not on this character's friends list yet:|r press Watch so you are told when they log in.")
		or "You will be alerted here when any of them is online."))
	fwin:SetHeight(92 + math.max(1, math.min(n, FW_MAX)) * 36)
end

local function buildFollowUps()
	fwin = Box(UIParent, 330, 140, 0.92)
	fwin:SetPoint("RIGHT", -120, 60)
	fwin:SetFrameStrata("MEDIUM")
	fwin:EnableMouse(true)
	fwin:SetMovable(true)
	fwin:SetClampedToScreen(true)
	fwin:RegisterForDrag("LeftButton")
	fwin:SetScript("OnDragStart", function(self) self:StartMoving() end)
	fwin:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	At(Label(fwin, "Follow-ups", "GameFontNormal"), fwin, 12, -10)
	local close = CreateFrame("Button", nil, fwin, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	At(Button(fwin, "Watch", 70, function() UI.WatchFollowUps(true) end), fwin, 240, -30)
	fwin.info = At(Label(fwin, "", "GameFontHighlightSmall", 220), fwin, 12, -32)
	fwin.rows = {}
	for i = 1, FW_MAX do
		local y = -76 - (i - 1) * 36
		local row = {}
		row.name = At(Button(fwin, "", 180, function(self)
			if row.key then UI.Show("Contacts", row.key) end
		end), fwin, 10, y)
		row.whisper = At(Button(fwin, "Whisper", 66, function() if row.key then Chat.Whisper(row.key) end end), fwin, 192, y)
		row.done = At(Button(fwin, "Done", 56, function()
			if not row.key then return end
			M.ClearFollowUp(row.key)
			UI.WatchFollowUps()
			ns.Changed()
		end), fwin, 262, y)
		row.note = At(Label(fwin, "", "GameFontDisableSmall", 300), fwin, 14, y - 22)
		fwin.rows[i] = row
	end
	fwin:Hide()
end

function UI.ShowFollowUps()
	if not ns.ready then return end
	if not fwin then buildFollowUps() end
	fwin:Show()
	UI.RefreshFollowUps()
end

function UI.ToggleFollowUps()
	if fwin and fwin:IsShown() then fwin:Hide() else UI.ShowFollowUps() end
end

-- ---------------------------------------------------------------- copyable link
-- Add-ons cannot open a web browser, so web addresses are shown ready to copy.

local linkBox

function UI.ShowLink(title, url)
	if not linkBox then
		linkBox = Box(UIParent, 440, 112, 0.95)
		linkBox:SetPoint("CENTER", 0, 160)
		linkBox:SetFrameStrata("DIALOG")
		linkBox:EnableMouse(true)
		linkBox.title = At(Label(linkBox, "", "GameFontNormal", 410), linkBox, 14, -12)
		At(Label(linkBox, "Press Ctrl+C to copy, then paste it into your web browser.", "GameFontHighlightSmall", 410), linkBox, 14, -32)
		linkBox.edit = At(Edit(linkBox, 404), linkBox, 20, -52)
		linkBox.edit:SetScript("OnEscapePressed", function() linkBox:Hide() end)
		At(Button(linkBox, "Close", 80, function() linkBox:Hide() end), linkBox, 346, -80)
	end
	linkBox.title:SetText(title)
	linkBox.edit:SetText(url)
	linkBox:Show()
	linkBox.edit:SetFocus()
	linkBox.edit:HighlightText()
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

-- The tabs follow the funnel: campaign, post, lead, contact, order, follow-up, then the tools.
do
	local order = { "Campaigns", "Posts", "Leads", "Contacts", "Orders", "Mail", "Products", "Dashboard", "Options" }
	for i = #tabOrder, 1, -1 do tabOrder[i] = nil end
	for i, n in ipairs(order) do tabOrder[i] = n end
end


table.insert(ns.listeners, function()
	UI.Refresh()
	refreshBar()
end)

-- Keep "craftable now" current as your bags change.
ns.On("BAG_UPDATE_DELAYED", function()
	if ns.ready and current == "Products" then UI.Refresh() end
end)

ns.On("PLAYER_LOGIN", function()
	buildMinimap()
	registerSettings()
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
	local unwatched = UI.UnwatchedFollowUps()
	if unwatched > 0 then
		ns.Print(("%d follow-up%s %s not on this character's friends list, so you would not be told when they log in. Type |cffffff00/crm watch|r to add them."):format(
			unwatched, unwatched == 1 and "" or "s", unwatched == 1 and "is" or "are"))
	end
	if M.ActiveCampaign(U.Now()) then UI.ShowCampaignBar() end
	if DB.settings and DB.settings.barShown then
		buildBar()
		refreshBar()
	end
end)
