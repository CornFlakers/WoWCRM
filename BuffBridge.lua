-- Buff reminders, bundled from the WoW Utils add-on (the files in Buffs/, see tools/sync_buffs.py).
-- This file decides whether they run, tells people once that they are there and can be switched
-- off, and connects them to WoW CRM's Options tab and /crm buffs.
local _, ns = ...
local DB = ns.DB
local BT = ns.BuffTool

local function loaded(name)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
	if type(f) ~= "function" then return false end
	local ok, yes = pcall(f, name)
	return ok and yes and true or false
end

-- The standalone WoW Utils add-on does the same job; when it is on, this copy stays quiet so
-- reminders do not show twice.
function ns.StandaloneBuffTool() return loaded("WoWUtils") end

-- On unless switched off in Options. Read from the saved data directly: this is asked at login,
-- possibly before WoW CRM has set up its own settings.
function ns.BuffToolEnabled()
	if not BT or ns.StandaloneBuffTool() then return false end
	local db = rawget(_G, "WoWCRMDB")
	local s = type(db) == "table" and db.settings
	return not (type(s) == "table" and s.buffTool == false)
end

local function hideAll()
	for _, n in ipairs({ "WoWCRMBuffsReminders", "WoWCRMBuffsFrame" }) do
		local f = rawget(_G, n)
		if f and f.Hide then f:Hide() end
	end
end

local pendingStop = false

-- Starts or stops the reminders to match the setting.
function ns.BuffToolApply()
	if not BT then return end
	if ns.BuffToolEnabled() then
		pendingStop = false
		if BT.ready then BT.Refresh() else BT.Start() end
		return
	end
	if not BT.ready then return end
	BT.ready = false
	if InCombatLockdown and InCombatLockdown() then
		pendingStop = true -- the reminder buttons cannot be hidden in combat
		ns.Print("buff reminders switch off when you leave combat.")
	else
		hideAll()
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingStop then pendingStop = false; hideAll() end
end)

-- /crm buffs [what]: the buff tool's own commands.
function ns.BuffToolSlash(rest)
	if not BT then ns.Print("the buff reminders are not part of this copy of WoW CRM.") return end
	if ns.StandaloneBuffTool() then ns.Print("the WoW Utils add-on is on, so use /wu there. Its reminders and these are the same.") return end
	if not ns.BuffToolEnabled() then
		ns.Print("buff reminders are off. Switch them on in WoW CRM > Options > Buff reminders.")
		return
	end
	if not BT.ready then BT.Start() end
	BT.Safe("/crm buffs", BT.Slash, rest or "")
end

StaticPopupDialogs["WOWCRM_BUFFTOOL"] = {
	text = "%s",
	button1 = "Keep it on",
	button2 = "Turn it off",
	OnAccept = function() end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then
			DB.settings.buffTool = false
			ns.BuffToolApply()
			ns.Print("buff reminders off. Options > Buff reminders switches them back on.")
			ns.Changed()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = false,
	preferredIndex = 3,
}

-- Once per account: say what the reminders are and that they can be switched off.
ns.On("PLAYER_LOGIN", function()
	if not BT or not DB.settings or DB.settings.buffToolAsked then return end
	if ns.StandaloneBuffTool() then return end
	DB.settings.buffToolAsked = true
	local function ask()
		StaticPopup_Show("WOWCRM_BUFFTOOL",
			"WoW CRM - new: buff reminders\n\n"
			.. "This is a tool the creator of WoW CRM found helpful: it reminds you of a missing weapon stone, food, "
			.. "tracking, elixirs and camp buffs, and says where to find them in your bags, bank or on your other characters.\n\n"
			.. "There are surely other add-ons that do this. You can switch it on or off any time under "
			.. "Options > Buff reminders. No big deal either way.")
	end
	if C_Timer and C_Timer.After then C_Timer.After(6, ask) else ask() end
end)
