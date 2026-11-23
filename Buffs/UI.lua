-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- On screen: the reminder strip (missing buffs, in your face, clickable where the game allows)
-- and the WoW CRM's buff reminders window (/crm buffs) with every buff, the shopping list and settings.
--
-- The reminder buttons are the game's secure action buttons: the game itself uses the item or
-- casts the spell when you click one. This add-on never uses anything for you. Secure buttons
-- cannot be changed during combat, so the strip hides when combat starts and comes back after.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local B, G, Stock, D, H = ns.Buffs, ns.Game, ns.Stock, ns.Data, ns.Howto
local UI = {}
ns.UI = UI

local MAX_ROWS = 8
local ROW_H = 40
local MAX_GET = 6
local GET_H = 22
local COLORS = {
	active = "|cff33ff33", covered = "|cff88dd88", ready = "|cffffd100", elsewhere = "|cffff9933", get = "|cffff4444", muted = "|cff888888",
}
local STATUS = { active = "active", covered = "covered", ready = "missing", elsewhere = "missing", get = "missing", muted = "muted" }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function icon(r)
	local p = r.pick and r.pick.option or r.get or r.group.options[1]
	if p and p.spell then return G.SpellIcon(p.spell, p.id) or QUESTION end
	return (p and G.ItemIcon(p.item)) or QUESTION
end

-- "Mithril Head Trout (+20 Attack Power)"
local function itemName(o) return B.OptionName(o) end

-- ---------------------------------------------------------------- tooltips: what it is and how to get it
local TIP = { head = { 1, 0.82, 0 }, good = { 0.3, 1, 0.3 }, warn = { 1, 0.6, 0.2 }, info = { 1, 1, 1 }, dim = { 0.6, 0.6, 0.6 } }
local index, indexAt = nil, -1000

-- Your characters' recipe scans, read again at most once a minute.
local function recipeIndex()
	local now = G.try(G.fn("GetTime")) or 0
	if not index or now - indexAt > 60 then
		index, indexAt = H.Index(rawget(_G, "MastercraftDB")), now
	end
	return index
end

-- The game's own tooltip for the item or spell, then: where yours are, who makes it, the
-- materials and where the recipe comes from. extra: lines to put first, { text, kind }.
function UI.ShowHow(owner, o, extra)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local shown = false
	if o.item and GameTooltip.SetItemByID then
		shown = pcall(GameTooltip.SetItemByID, GameTooltip, o.item)
	elseif o.spell and o.id and G.Known(o.spell, o.id) and GameTooltip.SetSpellByID then
		shown = pcall(GameTooltip.SetSpellByID, GameTooltip, o.id)
	end
	if not shown then GameTooltip:SetText(itemName(o)) end
	GameTooltip:AddLine(" ")
	local state = ns.state or {}
	local list = {}
	for _, l in ipairs(extra or {}) do list[#list + 1] = l end
	local spec = state.spec
	if o.stats and spec and state.weights then
		list[#list + 1] = { ("Worth %d to a %s (ranked by what it gives you). %s recommend %s."):format(
			math.floor(ns.Spec.Score(o.stats, state.weights) + 0.5), spec.label, spec.guide, spec.food), "dim" }
		if o.fromBags then list[#list + 1] = { "Found in your bags: its tooltip says it makes you Well Fed.", "dim" } end
	end
	for _, l in ipairs(H.Lines(o, { stock = state.stock, index = recipeIndex(), itemName = G.ItemName, known = G.Known, level = state.level })) do
		list[#list + 1] = l
	end
	for _, l in ipairs(list) do
		local c = TIP[l[2]] or TIP.info
		GameTooltip:AddLine(l[1], c[1], c[2], c[3], true)
	end
	GameTooltip:Show()
end

local function hideTip() GameTooltip:Hide() end

-- The line on the strip and in the window for something worth getting.
local function getText(r)
	local o = r.get
	local verb = o.spell and "Train" or (r.status == "get" and "Get" or "Better")
	return ("|cffff9933%s:|r %s |cffaaaaaa- %s|r"):format(verb, itemName(o), r.group.label)
end

-- ---------------------------------------------------------------- camp buffs
local CAMP_KIND = { active = "good", covered = "good", ready = "warn", elsewhere = "warn", get = "dim" }
local CAMP_WORD = { active = "on", covered = "covered", ready = "missing", elsewhere = "missing", get = "missing" }

-- The whole camp picture in one tooltip: the best set for how you play, best first.
function UI.ShowCamp(owner)
	local camp = ns.camp
	if not camp then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText("Best camp buffs for you: " .. camp.label)
	if camp.note then GameTooltip:AddLine(camp.note, 1, 0.82, 0, true) end
	for i, r in ipairs(camp.list) do
		local c = TIP[CAMP_KIND[r.status]] or TIP.info
		GameTooltip:AddLine(("%d. %s - %s"):format(i, CAMP_WORD[r.status], ns.Camp.Describe(r, camp.level)), c[1], c[2], c[3], true)
	end
	GameTooltip:AddLine("A Basic Campfire holds 3; the top three you can use are the ones the strip names.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine("Ranking from " .. (camp.source or "?") .. ", November 2026.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine(" ")
	if #camp.campfire > 0 then
		GameTooltip:AddLine("Campfire kits: " .. Stock.Describe(camp.campfire, 2), 0.3, 1, 0.3, true)
	else
		GameTooltip:AddLine("No campfire kit: Cooking trainers teach the Basic Campfire and sell its Simple Wood and Flint and Tinder.", 1, 0.6, 0.2, true)
	end
	GameTooltip:AddLine("Place camp objects by a campfire, then sit or craft nearby for a minute to get their buffs. You can place one object an hour yourself; friends can add theirs. Not indoors or in instances.", 1, 1, 1, true)
	GameTooltip:AddLine("Open /crm buffs and hover a camp object for how to make it. Wrong spec? /crm buffs style tank, melee, ranged, caster or healer.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function campExtra(r)
	local f = r.feature
	local level = ns.camp and ns.camp.level
	local out = { { f.name .. ": " .. ns.Camp.BuffText(f, level), "head" }, { "Why: " .. (r.why or ""), "info" } }
	if ns.camp then
		out[#out + 1] = { ("Ranked %d of %d for %s, from %s."):format(r.rank, #ns.camp.list, ns.camp.label, ns.camp.source or "?"), "dim" }
	end
	if f.exclusive then out[#out + 1] = { "Does not stack with " .. f.exclusive[1] .. ".", "dim" } end
	if #f.names > 1 then out[#out + 1] = { "Higher tiers keep this buff: " .. table.concat(f.names, ", ", 2), "dim" } end
	out[#out + 1] = { "Needs a campfire nearby; sit or craft by it for a minute.", "dim" }
	return out
end

-- ---------------------------------------------------------------- reminder strip
local strip, rows, getHead, getRows, campRow

local function savePoint()
	local p, _, rp, x, y = strip:GetPoint()
	ns.db.settings.point = { p, rp, x, y }
end

function UI.Place()
	if not strip or G.InCombat() then return end
	strip:ClearAllPoints()
	local pt = ns.db and ns.db.settings.point
	if pt then strip:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	else strip:SetPoint("TOP", UIParent, "TOP", 0, -110) end
end

local function buildStrip()
	strip = CreateFrame("Frame", "WoWCRMBuffsReminders", UIParent)
	strip:SetSize(380, 30)
	strip:SetFrameStrata("HIGH")
	strip:SetMovable(true)
	strip:SetClampedToScreen(true)
	local bg = strip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0, 0, 0.75)

	local head = CreateFrame("Button", "WoWCRMBuffsRemindersHead", strip)
	head:SetPoint("TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", -70, 0)
	head:SetHeight(24)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() if not ns.db.settings.locked and not G.InCombat() then strip:StartMoving() end end)
	head:SetScript("OnDragStop", function() strip:StopMovingOrSizing(); savePoint() end)
	head:SetScript("OnClick", function() UI.Toggle() end)
	strip.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	strip.title:SetPoint("LEFT", 8, 0)
	strip.title:SetText("Missing buffs")

	local snooze = CreateFrame("Button", "WoWCRMBuffsSnooze", strip, "UIPanelButtonTemplate")
	snooze:SetSize(66, 20)
	snooze:SetPoint("TOPRIGHT", -4, -2)
	snooze:SetText("Later")
	snooze:SetScript("OnClick", function()
		ns.snoozeUntil = (G.try(G.fn("GetTime")) or 0) + 600
		ns.Print("buff reminders hidden for 10 minutes. /crm buffs shows the full list.")
		UI.Update(ns.results or {}, ns.state)
	end)
	snooze:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Hide these reminders for 10 minutes")
		GameTooltip:Show()
	end)
	snooze:SetScript("OnLeave", function() GameTooltip:Hide() end)

	rows = {}
	for i = 1, MAX_ROWS do
		local b = CreateFrame("Button", "WoWCRMBuffsReminder" .. i, strip, "SecureActionButtonTemplate")
		b:SetSize(ROW_H - 4, ROW_H - 4)
		b:SetPoint("TOPLEFT", 6, -26 - (i - 1) * ROW_H)
		-- both up and down: the template itself picks the one that matches the "cast on key down" option
		b:RegisterForClicks("AnyUp", "AnyDown")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b.label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
		b.label:SetWidth(320)
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnEnter", function(self)
			local r = self.result
			if not r then return end
			UI.ShowHow(self, r.pick.option, {
				{ B.Describe(r), "info" },
				self.macro and { "Click to " .. (r.pick.spell and "cast it." or "use it."), "good" } or { "Fetch it first: it is not in your bags.", "warn" },
			})
		end)
		b:SetScript("OnLeave", hideTip)
		b:Hide()
		rows[i] = b
	end

	-- camp buffs: one plain line
	campRow = CreateFrame("Button", "WoWCRMBuffsCampRow", strip)
	campRow:SetSize(370, 26)
	campRow.icon = campRow:CreateTexture(nil, "ARTWORK")
	campRow.icon:SetSize(22, 22)
	campRow.icon:SetPoint("LEFT", 8, 0)
	campRow.label = campRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	campRow.label:SetPoint("LEFT", campRow.icon, "RIGHT", 6, 0)
	campRow.label:SetWidth(330)
	campRow.label:SetJustifyH("LEFT")
	campRow:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	campRow:SetScript("OnEnter", function(self) UI.ShowCamp(self) end)
	campRow:SetScript("OnLeave", hideTip)
	campRow:SetScript("OnClick", function() UI.Toggle() end)
	campRow:Hide()

	-- what to go and get: plain buttons, hover one for how
	getHead = CreateFrame("Button", "WoWCRMBuffsGetHead", strip)
	getHead:SetSize(370, 20)
	getHead.text = getHead:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	getHead.text:SetPoint("LEFT", 6, 0)
	getHead:SetScript("OnClick", function()
		ns.db.settings.getCollapsed = not ns.db.settings.getCollapsed
		UI.Update(ns.results or {}, ns.state)
	end)
	getHead:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Worth getting")
		GameTooltip:AddLine("Consumables and spells that would help you now and that you have on no character. Hover one to see what it is, how it is made and where to find it. Click here to fold the list.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	getHead:SetScript("OnLeave", hideTip)
	getRows = {}
	for i = 1, MAX_GET do
		local g = CreateFrame("Button", "WoWCRMBuffsGet" .. i, strip)
		g:SetSize(370, GET_H)
		g.icon = g:CreateTexture(nil, "ARTWORK")
		g.icon:SetSize(18, 18)
		g.icon:SetPoint("LEFT", 10, 0)
		g.label = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		g.label:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
		g.label:SetWidth(330)
		g.label:SetJustifyH("LEFT")
		g:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		g:SetScript("OnEnter", function(self)
			if self.result then UI.ShowHow(self, self.result.get, { { "Worth getting for: " .. self.result.group.label, "info" } }) end
		end)
		g:SetScript("OnLeave", hideTip)
		g:Hide()
		getRows[i] = g
	end
	UI.Place()
	strip:Hide()
end

local function rowText(r)
	local o, color = r.pick.option, COLORS[r.status]
	if r.status == "ready" then
		local where = r.pick.spell and "" or (" |cffaaaaaa(" .. Stock.Describe(r.pick.where, 1) .. ")|r")
		return color .. r.group.label .. "|r\n" .. (r.pick.spell and "Click to cast " or "Click to use ") .. itemName(o) .. where
	end
	return color .. r.group.label .. "|r\n" .. itemName(o) .. " is in " .. Stock.Describe(r.pick.where, 2)
end

local function updateStrip(results)
	if not strip then return end
	local show = ns.db.settings.strip and not ((ns.snoozeUntil or 0) > (G.try(G.fn("GetTime")) or 0))
	local list = show and B.Reminders(results) or {}
	for i, b in ipairs(rows) do
		local r = list[i]
		b.result = r
		if r then
			b.macro = B.Macro(r)
			if b.macro then
				b:SetAttribute("type", "macro")
				b:SetAttribute("macrotext", b.macro)
			else
				b:SetAttribute("type", nil)
				b:SetAttribute("macrotext", nil)
			end
			b.icon:SetTexture(icon(r))
			b.icon:SetDesaturated(b.macro == nil)
			b.label:SetText(rowText(r))
			b:Show()
			b.label:Show()
		else
			b.macro = nil
			b:SetAttribute("type", nil)
			b:SetAttribute("macrotext", nil)
			b:Hide()
			b.label:Hide()
		end
	end
	local n = math.min(#list, MAX_ROWS)
	strip.count = n

	-- under the missing buffs: what is worth going to get
	local gets = (show and ns.db.settings.stripGet) and B.Shopping(results) or {}
	local folded = ns.db.settings.getCollapsed
	local y = -26 - n * ROW_H

	-- camp buffs: one line, hover for the best set for how you play
	local camp = ns.camp
	local campMissing = (show and ns.db.settings.stripCamp and camp) and ns.Camp.MissingTop(camp) or {}
	if #campMissing > 0 then
		campRow:ClearAllPoints()
		campRow:SetPoint("TOPLEFT", 0, y - 2)
		campRow.icon:SetTexture(G.ItemIcon(ns.Camp.CAMPFIRE[1]) or QUESTION)
		campRow.label:SetText(("|cffff9933Camp buffs|r |cffaaaaaa(%s)|r: missing %s"):format(camp.label, table.concat(campMissing, ", ")))
		campRow:Show()
		y = y - 28
	else
		campRow:Hide()
	end
	strip.campMissing = #campMissing
	if #gets > 0 then
		getHead:ClearAllPoints()
		getHead:SetPoint("TOPLEFT", 4, y - 2)
		getHead.text:SetText(("Worth getting (%d)%s"):format(#gets, folded and " - click to show" or " - hover for how"))
		getHead:Show()
		y = y - 24
	else
		getHead:Hide()
	end
	for i, g in ipairs(getRows) do
		local r = (not folded) and gets[i] or nil
		g.result = r
		if r then
			g:ClearAllPoints()
			g:SetPoint("TOPLEFT", 0, y)
			local o = r.get
			g.icon:SetTexture(o.spell and (G.SpellIcon(o.spell, o.id) or QUESTION) or G.ItemIcon(o.item) or QUESTION)
			g.label:SetText(getText(r))
			g:Show()
			y = y - GET_H
		else
			g:Hide()
		end
	end
	strip.gets = #gets

	if n > 0 or #gets > 0 or #campMissing > 0 then
		strip.title:SetText(n == 0 and "No buffs missing" or (n == 1 and "1 buff missing" or (n .. " buffs missing")))
		strip:SetHeight(-y + 6)
		strip:Show()
	else
		strip:Hide()
	end
	strip:EnableMouse(not ns.db.settings.locked)
end

function UI.EnterCombat()
	if strip then strip:Hide() end
end

function UI.LeaveCombat() end

-- ---------------------------------------------------------------- the window
local win, content, lines = nil, nil, {}

local function line(i)
	local l = lines[i]
	if l then return l end
	l = CreateFrame("Frame", nil, content)
	l:SetSize(520, 22)
	l:EnableMouse(true)
	l:SetScript("OnEnter", function(self)
		if self.option then UI.ShowHow(self, self.option, self.extra) end
	end)
	l:SetScript("OnLeave", hideTip)
	l.icon = l:CreateTexture(nil, "ARTWORK")
	l.icon:SetSize(18, 18)
	l.icon:SetPoint("LEFT", 2, 0)
	l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
	l.text:SetWidth(430)
	l.text:SetJustifyH("LEFT")
	l.mute = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
	l.mute:SetSize(64, 18)
	l.mute:SetPoint("RIGHT", -4, 0)
	l.mute:SetScript("OnClick", function(self)
		local key = self.key
		ns.db.muted[key] = (not ns.db.muted[key]) or nil
		ns.Refresh()
	end)
	lines[i] = l
	return l
end

local function check(label, key, y, after)
	local c = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
	c:SetSize(22, 22)
	c:SetPoint("BOTTOMLEFT", 12 + (after or 0), y)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.text:SetText(label)
	c.key = key
	c:SetScript("OnClick", function(self)
		ns.db.settings[key] = self:GetChecked() and true or false
		ns.Refresh()
	end)
	return c
end

local function buildWindow()
	win = CreateFrame("Frame", "WoWCRMBuffsFrame", UIParent)
	win:SetSize(580, 520)
	win:SetPoint("CENTER")
	win:SetFrameStrata("DIALOG")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	local bg = win:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("WoW CRM's buff reminders - Buff manager")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	win.place = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.place:SetPoint("TOPLEFT", 14, -36)
	win.place:SetWidth(550)
	win.place:SetJustifyH("LEFT")

	local scroll = CreateFrame("ScrollFrame", "WoWCRMBuffsScroll", win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -56)
	scroll:SetPoint("BOTTOMRIGHT", -30, 44)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(530, 10)
	scroll:SetScrollChild(content)

	win.checks = {
		check("Show reminders", "strip", 12),
		check("Worth getting on the strip", "stripGet", 12, 120),
		check("Elixirs and scrolls", "extras", 12, 300),
		check("Lock in place", "locked", 12, 440),
	}
	tinsert(UISpecialFrames, "WoWCRMBuffsFrame")
	win:Hide()
end

local function header(i, text, y)
	local l = line(i)
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", 0, y)
	l.icon:Hide()
	l.mute:Hide()
	l.option, l.extra = nil, nil
	l.text:SetText("|cffffd100" .. text .. "|r")
	l:Show()
	return i + 1, y - 24
end

local function placeText(state)
	if not state then return "" end
	local bits = {}
	if G.Resting() then bits[#bits + 1] = "|cff33ff33Resting|r (inn, city or camp): you are earning rested XP" end
	local xp, max = G.RestedXP()
	if xp > 0 and max > 0 then bits[#bits + 1] = ("rested XP %d (%d%% of a level)"):format(xp, math.floor(xp * 100 / max)) end
	for _, n in ipairs(D.PLACE_AURAS) do
		if state.auras[n] then bits[#bits + 1] = "zone bonus: |cff33ff33" .. n .. "|r" end
	end
	if #bits == 0 then return "|cffaaaaaaNot resting: no rested XP being earned here.|r" end
	return table.concat(bits, "; ")
end

local function updateWindow(results, state)
	if not win or not win:IsShown() then return end
	win.place:SetText(placeText(state))
	for _, c in ipairs(win.checks) do c:SetChecked(ns.db.settings[c.key]) end
	for _, l in ipairs(lines) do l:Hide() end
	local i, y = 1, 0
	i, y = header(i, "Your buffs", y)
	for _, r in ipairs(results) do
		local l = line(i)
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, y)
		l.icon:SetTexture(icon(r))
		l.icon:Show()
		local text = COLORS[r.status] .. STATUS[r.status] .. "|r  " .. B.Describe(r)
		l.text:SetText(text)
		l.option = (r.pick and r.pick.option) or r.get
		l.extra = { { B.Describe(r), "info" } }
		l.mute.key = r.group.key
		l.mute:SetText(ns.db.muted[r.group.key] and "Unmute" or "Mute")
		l.mute:Show()
		l:Show()
		i, y = i + 1, y - 22
	end
	local camp = ns.camp
	if camp then
		y = y - 8
		i, y = header(i, ("Camp buffs, best first for %s (hover one for how to get it)"):format(camp.label), y)
		local src = line(i)
		src:ClearAllPoints(); src:SetPoint("TOPLEFT", 0, y); src.icon:Hide(); src.mute:Hide(); src.option = nil
		src.text:SetText("|cffaaaaaaRanking from " .. (camp.source or "?") .. " (Nov 2026). Hover the strip's camp line for its advice.|r")
		src:Show()
		i, y = i + 1, y - 22
		for n, r in ipairs(camp.list) do
			local l = line(i)
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", 0, y)
			l.icon:SetTexture(G.ItemIcon(r.feature.items[1]) or QUESTION)
			l.icon:Show()
			l.mute:Hide()
			local color = (r.status == "active" or r.status == "covered") and COLORS.active or (r.top and COLORS.elsewhere or COLORS.muted)
			l.text:SetText(("%s%d. %s|r  %s"):format(color, n, CAMP_WORD[r.status], ns.Camp.Describe(r, camp.level)))
			l.option, l.extra = { item = r.feature.items[1], name = r.feature.name }, campExtra(r)
			l:Show()
			i, y = i + 1, y - 22
		end
	end
	local shop = B.Shopping(results)
	y = y - 8
	i, y = header(i, "What to go and get (hover one for what it is and how to get it)", y)
	if #shop == 0 then
		local l = line(i)
		l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, y); l.icon:Hide(); l.mute:Hide(); l.option = nil
		l.text:SetText("|cffaaaaaaNothing: you have the best you can use for your level.|r")
		l:Show()
		i, y = i + 1, y - 22
	end
	for _, r in ipairs(shop) do
		local l = line(i)
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, y)
		local o = r.get
		l.icon:SetTexture(o.spell and (G.SpellIcon(o.spell, o.id) or QUESTION) or G.ItemIcon(o.item) or QUESTION)
		l.icon:Show()
		l.mute:Hide()
		l.option, l.extra = o, { { "Worth getting for: " .. r.group.label, "info" } }
		l.text:SetText(getText(r))
		l:Show()
		i, y = i + 1, y - 22
	end
	content:SetHeight(-y + 10)
	win.shown = i - 1
end

-- ---------------------------------------------------------------- shared
function UI.Init()
	if not strip then buildStrip() end
	if not win then buildWindow() end
end

function UI.Update(results, state)
	if G.InCombat() then return end
	updateStrip(results)
	updateWindow(results, state)
end

function UI.Toggle()
	UI.Init()
	if win:IsShown() then win:Hide() else win:Show(); ns.Refresh() end
end

-- Hover tooltips report their errors instead of stopping (see ns.Safe in Core.lua).
local showHow, showCamp = UI.ShowHow, UI.ShowCamp
function UI.ShowHow(...) ns.Safe("tooltip", showHow, ...) end
function UI.ShowCamp(...) ns.Safe("tooltip", showCamp, ...) end
