-- Startup, events, slash commands, and the "save changes" button.
local ADDON, ns = ...
local U, DB, M = ns.Util, ns.DB, ns.Model

ns.unsaved = 0
ns.listeners = {}

-- Your own name. Two-part names may come back split in two, like a trade partner's.
function ns.MyName()
	local n, second = UnitName("player")
	if type(second) == "string" and second ~= "" and ns.ready and not M.KnownRealms()[(second:gsub("[%s%-]", ""))] then
		return n .. " " .. second
	end
	return n
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoW CRM:|r " .. tostring(msg))
end

-- Called after any change the user would not want to lose.
function ns.Changed(silent)
	if not silent then
		if ns.unsaved == 0 then ns.firstUnsaved = U.Now() end
		ns.unsaved = ns.unsaved + 1
	end
	ns.Notify()
end

-- Redraw anything that is on screen.
function ns.Notify()
	for _, fn in ipairs(ns.listeners) do fn() end
end

function ns.Confirm(text, onYes)
	StaticPopup_Show("WOWCRM_CONFIRM", text, nil, onYes)
end

StaticPopupDialogs["WOWCRM_CONFIRM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data) if data then data() end end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Three-way question used for follow-up trades: add to the current order, start a new one, or ignore.
function ns.Choose(text, onAdd, onNew)
	StaticPopup_Show("WOWCRM_TRADE", text, nil, { add = onAdd, new = onNew })
end

StaticPopupDialogs["WOWCRM_TRADE"] = {
	text = "%s",
	button1 = "Add to order",
	button2 = "Ignore",
	button3 = "New order",
	OnAccept = function(_, data) if data and data.add then data.add() end end,
	OnAlt = function(_, data) if data and data.new then data.new() end end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Posts from before posts had owners: offer them to the character logging in. Saying no on a
-- character means it is not asked again there.
StaticPopupDialogs["WOWCRM_ASSIGN"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data) if data and data.yes then data.yes() end end,
	OnCancel = function(_, data) if data and data.no then data.no() end end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.OfferAssignPosts(force)
	local n = M.UnassignedPosts()
	if n == 0 or not M.me then return end
	DB.R.assignDeclined = DB.R.assignDeclined or {}
	if DB.R.assignDeclined[M.me] and not force then return end
	local who = U.Display(M.me, DB.realm)
	StaticPopup_Show("WOWCRM_ASSIGN", ("WoW CRM\n\nPosts now belong to the character whose voice they are written in.\n\nYou have %d post%s not given to anyone yet. Are they written as |cffffff00%s|r?\n\nChoose No on any other character."):format(
		n, n == 1 and "" or "s", who), nil, {
		yes = function()
			M.AssignPosts(M.me)
			ns.Print(("%d post%s now belong to %s."):format(n, n == 1 and "" or "s", who))
			ns.Changed()
		end,
		no = function()
			DB.R.assignDeclined[M.me] = true
			ns.Print("not asked again on this character. You can still give posts to it on the Posts tab.")
		end,
	})
end

-- ---------------------------------------------------------------- saving
-- The game writes add-on data to disk when the interface shuts down: logging out, leaving
-- the game or reloading. A normal logout therefore saves everything. The only way to lose
-- changes is the game dying mid-session (a crash or a power cut), so a backup is offered
-- now and then, at a quiet moment, as insurance. It reloads the interface, which must come
-- from a real click.

local function reload()
	if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end
ns.SaveNow = reload

local saveButton = CreateFrame("Button", "WoWCRMSaveButton", UIParent, "UIPanelButtonTemplate")
saveButton:SetSize(240, 26)
saveButton:SetPoint("TOP", UIParent, "TOP", 0, -140)
saveButton:SetFrameStrata("HIGH")
saveButton:Hide()
saveButton:SetScript("OnClick", reload)
saveButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("WoW CRM backup")
	GameTooltip:AddLine("Logging out saves everything on its own. This is only insurance against a crash:\nit reloads the interface (about two seconds), which writes your CRM data now.", 1, 1, 1, true)
	GameTooltip:Show()
end)
saveButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local lastMoved, offerUntil = 0, 0
local QUIET_SECONDS = 10

-- Called at a natural stopping point (a campaign finishing): offer the backup for a few minutes
-- even if not many changes are waiting.
function ns.OfferSave()
	offerUntil = U.Now() + 300
end

-- Is this a moment when a two-second reload costs nothing?
local function quietMoment(now)
	if InCombatLockdown() then return false end
	if (TradeFrame and TradeFrame:IsShown()) or (MailFrame and MailFrame:IsShown()) then return false end
	if IsResting and IsResting() then return true end
	return now - lastMoved >= QUIET_SECONDS
end

local function updateSaveButton()
	if not DB.settings then return end
	local s, now = DB.settings, U.Now()
	local enough = ns.unsaved >= (s.saveAfterChanges or 25)
		or (ns.firstUnsaved and now - ns.firstUnsaved >= (s.saveAfterMinutes or 30) * 60)
		or now < offerUntil
	if s.saveReminder and ns.unsaved > 0 and enough and quietMoment(now) then
		saveButton:SetText(("WoW CRM: back up %d change%s"):format(ns.unsaved, ns.unsaved == 1 and "" or "s"))
		saveButton:Show()
	else
		saveButton:Hide()
	end
end
ns.UpdateSaveButton = updateSaveButton
table.insert(ns.listeners, updateSaveButton)

-- ---------------------------------------------------------------- events

local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}
ns.handlers = handlers

function ns.On(event, fn)
	local old = handlers[event]
	if old then
		handlers[event] = function(...) old(...); fn(...) end
	else
		handlers[event] = fn
		frame:RegisterEvent(event)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if h then h(...) end
end)

-- Every couple of seconds: note whether the player is on the move, and show or hide the backup offer.
do
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 2 then return end
		elapsed = 0
		if not ns.ready then return end
		if GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0 then lastMoved = U.Now() end
		updateSaveButton()
	end)
end

ns.On("PLAYER_LOGIN", function()
	local function ask(f, ...) if type(f) == "function" then local ok, a, b = pcall(f, ...); if ok then return a, b end end end
	local _, fullRealm = ask(rawget(_G, "UnitFullName"), "player")
	local realm = DB.ResolveRealm(WoWCRMDB, ask(rawget(_G, "GetNormalizedRealmName")), ask(rawget(_G, "GetRealmName")), fullRealm)
	WoWCRMDB = DB.Init(WoWCRMDB, realm)
	ns.ready = true
	if DB.setAside then
		ns.Print("the game gave a blank realm name for a while; what was saved in that time is kept aside as \"" .. DB.setAside .. "\" in your saved data.")
	end
	M.me = U.NormName(ns.MyName(), DB.realm)
	local names, items = M.RepairSplitNames(), M.RepairJoinedItems()
	local leads = M.MergeDuplicateLeads()
	M.RefreshStatuses()
	if names + items > 0 then
		ns.Print(("tidied up %d contact%s saved under half a name and %d old order%s."):format(
			names, names == 1 and "" or "s", items, items == 1 and "" or "s"))
		ns.Changed()
	end
	if leads > 0 then
		ns.Print(("folded %d duplicate lead%s into one lead per person."):format(leads, leads == 1 and "" or "s"))
		ns.Changed()
	end
	local on = M.TrackingState(U.Now())
	if on then ns.Print("contact tracking is still ON.") end
	ns.OfferAssignPosts()
	ns.Notify()
end)

ns.On("PLAYER_REGEN_DISABLED", updateSaveButton)
ns.On("PLAYER_REGEN_ENABLED", updateSaveButton)

local function blocked(addon, func)
	if addon == ADDON then
		ns.lastBlocked = func
		ns.Print("the game blocked |cffffff00" .. tostring(func) .. "|r. Posts to Say, Yell, General and Trade must come straight from a click.")
	end
end
ns.On("ADDON_ACTION_FORBIDDEN", blocked)
ns.On("ADDON_ACTION_BLOCKED", blocked)

-- ---------------------------------------------------------------- tracking toggle (shared by UI and slash)

function ns.SetTracking(on)
	M.SetTracking(on, U.Now())
	if on then
		local _, capturing = M.TrackingState(U.Now())
		ns.Print("contact tracking ON. " .. (capturing and "Whispers are being captured." or "Whispers are captured once you make a post."))
	else
		ns.Print("contact tracking OFF.")
	end
	ns.Changed(true)
end

-- ---------------------------------------------------------------- slash commands

SLASH_WOWCRM1 = "/crm"
SLASH_WOWCRM2 = "/wowcrm"
SlashCmdList["WOWCRM"] = function(msg)
	if not ns.ready then return end
	local cmd, rest = U.Trim(msg):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "add" then
		local key = U.NormName(rest, DB.realm, true)
		if not key then ns.Print("usage: /crm add Name") return end
		local _, isNew = M.EnsureContact(key, U.Now())
		ns.Print(isNew and ("added " .. key .. ".") or (key .. " is already a contact."))
		if isNew then ns.Changed() end
	elseif cmd == "track" then
		local on = M.TrackingState(U.Now())
		if rest == "on" then on = false elseif rest == "off" then on = true end
		ns.SetTracking(not on)
	elseif cmd == "bar" then
		ns.UI.ToggleBar()
	elseif cmd == "campaign" then
		ns.UI.ToggleCampaignBar()
	elseif cmd == "save" then
		ns.Print("click the Save button (a reload must come from a click).")
		ns.unsaved = math.max(ns.unsaved, 1)
		ns.Notify()
	elseif cmd == "probe" then
		ns.Chat.Probe()
	elseif cmd == "follow" then
		ns.UI.ToggleFollowUps()
	elseif cmd == "watch" then
		ns.UI.WatchFollowUps(true)
	elseif cmd == "reagents" and rest == "check" then
		ns.Reagents.HookAll()
		ns.Print("profession window help is " .. (DB.settings.reagentHelp and "ON" or "OFF") .. ".")
		for _, line in ipairs(ns.Reagents.Status()) do ns.Print(line) end
	elseif cmd == "reagents" then
		DB.settings.reagentHelp = not DB.settings.reagentHelp
		ns.Print("double-click help in the profession window is " .. (DB.settings.reagentHelp and "ON." or "OFF."))
	else
		ns.Print("commands: /crm, /crm follow, /crm watch, /crm campaign, /crm bar, /crm track [on|off], /crm add Name, /crm reagents [check], /crm probe")
	end
end

function WoWCRM_OnCompartmentClick()
	if ns.ready then ns.UI.Toggle() end
end
