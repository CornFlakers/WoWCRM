-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- Startup, saved settings, events and slash commands.
local ADDON, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local D, Stock, B, G = ns.Data, ns.Stock, ns.Buffs, ns.Game

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoW CRM buffs:|r " .. tostring(msg))
end

local DEFAULTS = { strip = true, stripGet = true, getCollapsed = false, stripCamp = true, style = "auto", extras = true, locked = false }

function ns.InitDB(db)
	db = type(db) == "table" and db or {}
	db.settings = type(db.settings) == "table" and db.settings or {}
	for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
	db.muted = type(db.muted) == "table" and db.muted or {}
	db.bank = type(db.bank) == "table" and db.bank or {}
	db.bankSeen = type(db.bankSeen) == "table" and db.bankSeen or {}
	return db
end

-- ---------------------------------------------------------------- the buff check
local bankOpen = false

local function snapshotBank()
	if not bankOpen then return end
	local me, snap = G.MyName(), {}
	for _, id in ipairs(D.AllItems()) do
		local n = G.BankCount(id)
		if n > 0 then snap[id] = n end
	end
	ns.db.bank[me] = snap
	ns.db.bankSeen[me] = time and time() or 0
end

function ns.State()
	local me = G.MyName()
	local stock = Stock.Collect({
		me = me,
		guid = G.try(G.fn("UnitGUID"), "player"),
		bags = G.BagCount,
		bank = G.BankCount,
		savedBank = ns.db.bank[me],
		mastercraft = rawget(_G, "MastercraftDB"),
		brother = rawget(_G, "BrotherBags"),
	})
	local auras, auraIds = G.Auras()
	local override = ns.Camp.STYLE_ORDER[ns.db.settings.style] and ns.db.settings.style or nil
	local talents = G.TalentPoints()
	return {
		me = me,
		class = G.Class(),
		level = G.Level(),
		auras = auras,
		auraIds = auraIds,
		extraFoods = G.BagFoods(),
		talents = talents,
		styleOverride = override,
		weapons = G.Weapons(),
		tracking = G.Tracking(),
		known = G.Known,
		itemLevel = G.ItemLevel,
		itemSpell = G.ItemSpell,
		stock = stock,
		muted = ns.db.muted,
		extras = ns.db.settings.extras,
		maxLevel = G.MaxLevel(),
		style = override or ns.Camp.StyleFromTalents(G.Class(), talents),
		styleAuto = override == nil,
	}
end

-- ---------------------------------------------------------------- errors
-- The game hides Lua errors unless "Display Lua errors" is on, so WoW CRM's buff reminders catches its own:
-- it says so once in chat, and keeps the message and where it happened in its saved data
-- (WoWCRMBuffsDB.errors) so it can be read after a /reload. /crm buffs errors shows them.
local said = {}
local unpack = table.unpack or unpack
local function stackText()
	local ds = rawget(_G, "debugstack")
	if type(ds) == "function" then local ok, s = pcall(ds, 3, 10, 0); if ok then return s end end
	if debug and debug.traceback then return debug.traceback("", 3) end
	return ""
end

function ns.Report(where, err, stack)
	local msg = tostring(err)
	ns.lastError = where .. ": " .. msg
	if ns.db then
		ns.db.errors = type(ns.db.errors) == "table" and ns.db.errors or {}
		local list, dup = ns.db.errors, false
		for _, e in ipairs(list) do if e.msg == msg then dup = true; e.count = (e.count or 1) + 1 end end
		if not dup and #list < 10 then
			list[#list + 1] = { when = time and time() or 0, where = where, msg = msg, stack = stack or "", version = ns.VERSION }
		end
	end
	if not said[msg] then
		said[msg] = true
		ns.Print("|cffff4444something went wrong (" .. where .. "): " .. msg .. "|r  (/crm buffs errors shows it again)")
	end
end

-- Run f(...) and report any error instead of stopping.
function ns.Safe(where, f, ...)
	local args, n = { ... }, select("#", ...)
	local stack
	local ok, err = xpcall(function() return f(unpack(args, 1, n)) end, function(e) stack = stackText(); return e end)
	if not ok then ns.Report(where, err, stack) end
	return ok
end

local function refresh()
	if not ns.ready then return end
	if G.InCombat() then return end -- secure buttons cannot change in combat; the strip is hidden then
	ns.state = ns.State()
	ns.results = B.Evaluate(ns.state)
	ns.camp = ns.Camp.Evaluate(ns.state)
	if ns.UI then ns.UI.Update(ns.results, ns.state) end
end
function ns.Refresh() ns.Safe("refresh", refresh) end

local dirty, sinceDirty, sinceFull = false, 0, 0
function ns.Dirty() dirty = true; sinceDirty = 0 end

-- ---------------------------------------------------------------- events
local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}
local function on(event, f)
	handlers[event] = f
	-- unknown event names raise an error on newer clients; skip the ones this client lacks
	pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local f = handlers[event]
	if f and (ns.ready or event == "PLAYER_LOGIN") then ns.Safe(event, f, ...) end
end)

frame:SetScript("OnUpdate", function(_, dt)
	if not ns.ready then return end
	sinceDirty, sinceFull = sinceDirty + dt, sinceFull + dt
	-- temporary weapon buffs run out without telling anyone, so look again every few seconds
	if (dirty and sinceDirty > 0.3) or sinceFull > 5 then
		dirty, sinceFull = false, 0
		ns.Refresh()
	end
end)

-- Each file sets its part of ns when it loads; a file the game could not read leaves a gap.
local PARTS = { { "Data", "Data.lua" }, { "Stock", "Stock.lua" }, { "Howto", "Howto.lua" }, { "Spec", "Spec.lua" },
	{ "Buffs", "Buffs.lua" }, { "Camp", "Camp.lua" }, { "Game", "Game.lua" }, { "UI", "UI.lua" } }

function ns.Start()
	if ns.ready then return end
	WoWCRMBuffsDB = ns.InitDB(rawget(_G, "WoWCRMBuffsDB"))
	ns.db = WoWCRMBuffsDB
	ns.db.errors = nil -- a fresh list for this session
	local missing = {}
	for _, p in ipairs(PARTS) do if not ns[p[1]] then missing[#missing + 1] = p[2] end end
	if #missing > 0 then ns.Report("load", "the game could not load " .. table.concat(missing, ", ")) end
	ns.ready = true
	if ns.UI then ns.Safe("startup", ns.UI.Init) end
	ns.Refresh()
end
on("PLAYER_LOGIN", function() if ns.crm.BuffToolEnabled() then ns.Start() end end)

local function aura(unit) if unit == "player" then ns.Dirty() end end
on("UNIT_AURA", aura)
on("UNIT_INVENTORY_CHANGED", aura)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "MINIMAP_UPDATE_TRACKING",
	"PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA", "GET_ITEM_INFO_RECEIVED", "UPDATE_EXHAUSTION" }) do
	on(e, ns.Dirty)
end
on("BAG_UPDATE", function() snapshotBank(); ns.Dirty() end)
on("SPELLS_CHANGED", function() G.ForgetSpellbook(); ns.Dirty() end)
on("LEARNED_SPELL_IN_TAB", function() G.ForgetSpellbook(); ns.Dirty() end)
on("BANKFRAME_OPENED", function() bankOpen = true; snapshotBank(); ns.Dirty() end)
on("PLAYERBANKSLOTS_CHANGED", function() snapshotBank(); ns.Dirty() end)
on("BANKFRAME_CLOSED", function() snapshotBank(); bankOpen = false; ns.Dirty() end)
on("PLAYER_REGEN_DISABLED", function()
	-- this handler runs just before combat lockdown starts: the last moment to hide secure buttons
	if ns.UI then ns.UI.EnterCombat() end
end)
on("PLAYER_REGEN_ENABLED", function()
	if ns.UI then ns.UI.LeaveCombat() end
	ns.Refresh()
end)

-- ---------------------------------------------------------------- slash commands
local function check()
	local s = ns.State()
	local bits = {}
	for n in pairs(s.tracking) do bits[#bits + 1] = n end
	ns.Print(("%s, %s level %d. Interface %s."):format(s.me, s.class, s.level, tostring(select(4, G.try(G.fn("GetBuildInfo"))))))
	ns.Print("tracking on: " .. (#bits > 0 and table.concat(bits, ", ") or "none the game reports"))
	local buffs = {}
	for n in pairs(s.auras) do buffs[#buffs + 1] = n end
	table.sort(buffs)
	ns.Print("your buffs: " .. (#buffs > 0 and table.concat(buffs, ", ") or "none"))
	local plan = ns.Camp.Plan(s)
	ns.Print(("camp buffs ranked for: %s%s, from %s"):format(plan.label, s.styleAuto and " (from your talents)" or " (set with /crm buffs style)", plan.source))
	local w = s.weapons[16]
	ns.Print("main hand: " .. (w and (("item %d, kind %s, buffed: %s"):format(w.id, tostring(w.subclass), w.enchanted and "yes" or "no")) or "none"))
	local api = {}
	for _, name in ipairs({ "C_UnitAuras.GetAuraDataByIndex", "UnitBuff", "GetWeaponEnchantInfo", "C_Minimap.GetTrackingInfo",
		"GetTrackingTexture", "C_SpellBook.GetSpellBookItemName", "GetSpellBookItemName", "C_Item.GetItemCount" }) do
		api[#api + 1] = name .. (G.fn(name) and " yes" or " no")
	end
	ns.Print("game calls: " .. table.concat(api, "; "))
	ns.Print(("other characters' bags: Mastercraft %s, BagBrother %s"):format(
		rawget(_G, "MastercraftDB") and "found" or "not found", rawget(_G, "BrotherBags") and "found" or "not found"))
end

local function groupKeys()
	local keys = {}
	for _, g in ipairs(D.GROUPS) do keys[#keys + 1] = g.key end
	return table.concat(keys, ", ")
end

function ns.Slash(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	if not ns.ready then ns.Print("still loading."); return end
	if not ns.UI and cmd ~= "errors" and cmd ~= "check" then
		ns.Print("the window part of WoW CRM's buff reminders did not load. /crm buffs errors shows why.")
		return
	end
	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "buffs" or cmd == "strip" then
		ns.db.settings.strip = not ns.db.settings.strip
		ns.Print("buff reminders " .. (ns.db.settings.strip and "on." or "off."))
		ns.Refresh()
	elseif cmd == "get" or cmd == "shop" then
		ns.db.settings.stripGet = not ns.db.settings.stripGet
		ns.Print("\"Worth getting\" on the reminder strip " .. (ns.db.settings.stripGet and "on." or "off."))
		ns.Refresh()
	elseif cmd == "extras" then
		ns.db.settings.extras = not ns.db.settings.extras
		ns.Print("elixirs and scrolls " .. (ns.db.settings.extras and "included." or "left out."))
		ns.Refresh()
	elseif cmd == "mute" or cmd == "unmute" then
		local g = D.Group(arg)
		if not g then ns.Print("which one? " .. groupKeys()); return end
		ns.db.muted[g.key] = (cmd == "mute") or nil
		ns.Print(g.label .. (cmd == "mute" and " muted." or " unmuted."))
		ns.Refresh()
	elseif cmd == "camp" then
		ns.db.settings.stripCamp = not ns.db.settings.stripCamp
		ns.Print("camp buffs on the reminder strip " .. (ns.db.settings.stripCamp and "on." or "off."))
		ns.Refresh()
	elseif cmd == "style" then
		if arg == "auto" or ns.Camp.STYLE_ORDER[arg] then
			ns.db.settings.style = arg
			ns.Refresh()
			ns.Print("camp buffs ranked for: " .. ns.camp.label .. (arg == "auto" and " (from your talents)" or "") .. ".")
		else
			ns.Print("/crm buffs style auto, tank, melee, ranged, caster or healer")
		end
	elseif cmd == "lock" then
		ns.db.settings.locked = not ns.db.settings.locked
		ns.Print("reminders " .. (ns.db.settings.locked and "locked in place." or "can be dragged."))
		ns.Refresh()
	elseif cmd == "reset" then
		ns.db.settings.point = nil
		ns.UI.Place()
		ns.Print("reminders moved back to the top of the screen.")
	elseif cmd == "check" then
		check()
	elseif cmd == "errors" then
		local list = ns.db.errors or {}
		if #list == 0 then ns.Print("no errors this session.") end
		for i, e in ipairs(list) do
			ns.Print(("%d. (%s%s) %s"):format(i, e.where, (e.count or 1) > 1 and (", " .. e.count .. " times") or "", e.msg))
		end
	else
		ns.Print("/crm buffs - open the window; /crm buffs buffs - reminders on/off; /crm buffs get - \"worth getting\" on the strip on/off;")
		ns.Print("/crm buffs extras - elixirs and scrolls on/off; /crm buffs camp - camp buffs on the strip on/off;")
		ns.Print("/crm buffs style auto|tank|melee|ranged|caster|healer - how you play, for the best camp buffs;")
		ns.Print("/crm buffs mute <name> or unmute <name>; /crm buffs lock; /crm buffs reset; /crm buffs check. Names: " .. groupKeys())
	end
end

