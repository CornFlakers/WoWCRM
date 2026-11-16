-- Startup, events, slash commands, and the "save changes" button.
local ADDON, ns = ...
local U, DB, M = ns.Util, ns.DB, ns.Model

ns.unsaved = 0
ns.listeners = {}

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoW CRM:|r " .. tostring(msg))
end

-- Called after any change the user would not want to lose.
function ns.Changed(silent)
	if not silent then ns.unsaved = ns.unsaved + 1 end
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

-- ---------------------------------------------------------------- saving
-- The game writes add-on data to disk only on logout or interface reload.
-- A reload has to come from a real click, so we offer a button for it.

local function reload()
	if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end
ns.SaveNow = reload

local saveButton = CreateFrame("Button", "WoWCRMSaveButton", UIParent, "UIPanelButtonTemplate")
saveButton:SetSize(220, 26)
saveButton:SetPoint("TOP", UIParent, "TOP", 0, -140)
saveButton:SetFrameStrata("HIGH")
saveButton:Hide()
saveButton:SetScript("OnClick", reload)
saveButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("WoW CRM")
	GameTooltip:AddLine("Reloads the interface, which writes your CRM data to disk.\nIt also saves when you log out normally.", 1, 1, 1, true)
	GameTooltip:Show()
end)
saveButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function updateSaveButton()
	if not DB.settings then return end
	local show = ns.unsaved > 0 and DB.settings.saveReminder and not InCombatLockdown()
	if show then
		saveButton:SetText(("WoW CRM: save %d change%s"):format(ns.unsaved, ns.unsaved == 1 and "" or "s"))
		saveButton:Show()
	else
		saveButton:Hide()
	end
end
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

ns.On("PLAYER_LOGIN", function()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or "Unknown"):gsub("[%s%-]", "")
	WoWCRMDB = DB.Init(WoWCRMDB, realm)
	ns.ready = true
	local on = M.TrackingState(U.Now())
	if on then ns.Print("contact tracking is still ON.") end
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
	elseif cmd == "save" then
		ns.Print("click the Save button (a reload must come from a click).")
		ns.unsaved = math.max(ns.unsaved, 1)
		ns.Notify()
	elseif cmd == "probe" then
		ns.Chat.Probe()
	else
		ns.Print("commands: /crm, /crm add Name, /crm track [on|off], /crm bar, /crm probe")
	end
end

function WoWCRM_OnCompartmentClick()
	if ns.ready then ns.UI.Toggle() end
end
