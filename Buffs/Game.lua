-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.
-- Reads what the buff manager needs from the game. Every call is guarded: this client mixes
-- old and new APIs, so each question tries the modern call first and the old one after.
local _, crm = ...
local ns = crm.BuffTool or { crm = crm }
crm.BuffTool = ns
local G = {}
ns.Game = G

local function fn(path)
	local t = _G
	for part in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = rawget(t, part)
	end
	return type(t) == "function" and t or nil
end
G.fn = fn

local unpack = table.unpack or unpack
local function pack(...) return { n = select("#", ...), ... } end
local function try(f, ...)
	if not f then return nil end
	local r = pack(pcall(f, ...))
	if not r[1] then return nil end
	-- a game call that returns nothing at all (an empty bag slot) still gives one nil, so
	-- tonumber(try(...)) and the like never see "no value"
	if r.n < 2 then return nil end
	return unpack(r, 2, r.n)
end
G.try = try

local function secret(v)
	local f = fn("issecretvalue")
	return f and f(v) or false
end

-- ---------------------------------------------------------------- you
function G.Class()
	local _, file = try(fn("UnitClass"), "player")
	return file or "WARRIOR"
end

function G.Level() return tonumber(try(fn("UnitLevel"), "player")) or 1 end

function G.MaxLevel()
	return tonumber(try(fn("GetMaxPlayerLevel"))) or tonumber(rawget(_G, "MAX_PLAYER_LEVEL")) or 60
end

-- Points spent in each talent tree: { [tab] = points }. Old clients return
-- name, icon, points; newer ones id, name, description, icon, points.
function G.TalentPoints()
	local out = {}
	local num, info = fn("GetNumTalentTabs"), fn("GetTalentTabInfo")
	if not (num and info) then return out end
	for tab = 1, (tonumber(try(num)) or 0) do
		local a, _, c, _, e = try(info, tab)
		out[tab] = tonumber(type(a) == "number" and e or c) or 0
	end
	return out
end

-- Your name. A name with a space in it ("Claire Paige") comes back from UnitName in two parts.
function G.MyName()
	local n, second = try(fn("UnitName"), "player")
	if type(second) == "string" and second ~= "" then return n .. " " .. second end
	return n or "?"
end

-- ---------------------------------------------------------------- buffs on you
-- Your buffs by name, and by spell id as a second table.
function G.Auras()
	local out, ids = {}, {}
	local byIndex = fn("C_UnitAuras.GetAuraDataByIndex")
	local unitBuff = fn("UnitBuff")
	for i = 1, 40 do
		local name, id
		if byIndex then
			local a = try(byIndex, "player", i, "HELPFUL")
			if not a then break end
			name, id = a.name, a.spellId
		elseif unitBuff then
			local r = { try(unitBuff, "player", i) }
			name = r[1]
			if not name then break end
			id = r[10]
		else
			break
		end
		if type(name) == "string" and not secret(name) then out[name] = true end
		if type(id) == "number" and not secret(id) then ids[id] = true end
	end
	return out, ids
end

-- ---------------------------------------------------------------- weapons
local function weaponInfo(slot, enchanted)
	local id = try(fn("GetInventoryItemID"), "player", slot)
	if not id then return nil end
	local subclass
	local instant = fn("C_Item.GetItemInfoInstant") or fn("GetItemInfoInstant")
	if instant then
		local _, _, _, _, _, classID, subclassID = try(instant, id)
		if classID == 2 then subclass = subclassID
		elseif classID ~= nil then return nil end -- a shield or an off-hand book: no weapon buff
	else
		local equipLoc = select(9, try(fn("GetItemInfo"), id))
		if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return nil end
	end
	return { id = id, subclass = subclass, enchanted = enchanted and true or false }
end

function G.Weapons()
	local hasMain, _, _, _, hasOff = try(fn("GetWeaponEnchantInfo"))
	return { [16] = weaponInfo(16, hasMain), [17] = weaponInfo(17, hasOff) }
end

-- ---------------------------------------------------------------- spells
local book
function G.ForgetSpellbook() book = nil end

local function scanBook()
	local out = {}
	-- modern spellbook
	local lines, lineInfo, itemName = fn("C_SpellBook.GetNumSpellBookSkillLines"), fn("C_SpellBook.GetSpellBookSkillLineInfo"), fn("C_SpellBook.GetSpellBookItemName")
	if lines and lineInfo and itemName then
		for l = 1, (tonumber(try(lines)) or 0) do
			local info = try(lineInfo, l)
			if type(info) == "table" then
				local first, n = info.itemIndexOffset or 0, info.numSpellBookItems or 0
				for i = first + 1, first + n do
					local name = try(itemName, i, 0) -- Enum.SpellBookSpellBank.Player
					if type(name) == "string" then out[name] = true end
				end
			end
		end
	end
	-- old spellbook
	local tabs, tabInfo = fn("GetNumSpellTabs"), fn("GetSpellTabInfo")
	local oldName = fn("GetSpellBookItemName") or fn("GetSpellName")
	if tabs and tabInfo and oldName then
		for t = 1, (tonumber(try(tabs)) or 0) do
			local _, _, offset, n = try(tabInfo, t)
			for i = (offset or 0) + 1, (offset or 0) + (n or 0) do
				local name = try(oldName, i, "spell")
				if type(name) == "string" then out[name] = true end
			end
		end
	end
	return out
end

function G.Known(name, id)
	if id then
		if try(fn("IsPlayerSpell"), id) then return true end
		if try(fn("IsSpellKnown"), id) then return true end
		local cs = fn("C_SpellBook.IsSpellKnown")
		if cs and try(cs, id) then return true end
	end
	if name then
		book = book or scanBook()
		if book[name] then return true end
	end
	return false
end

function G.SpellIcon(name, id)
	local tex = fn("C_Spell.GetSpellTexture")
	local v = tex and (try(tex, id or name) or (name and try(tex, name)))
	if v then return v end
	tex = fn("GetSpellTexture")
	return tex and (try(tex, id or name) or (name and try(tex, name))) or nil
end

-- ---------------------------------------------------------------- tracking
function G.Tracking()
	local out = {}
	local num, info = fn("C_Minimap.GetNumTrackingTypes"), fn("C_Minimap.GetTrackingInfo")
	if not (num and info) then num, info = fn("GetNumTrackingTypes"), fn("GetTrackingInfo") end
	if num and info then
		for i = 1, (tonumber(try(num)) or 0) do
			local a, _, active = try(info, i)
			if type(a) == "table" then
				if a.active and a.name then out[a.name] = true end
			elseif a and active then
				out[a] = true
			end
		end
	end
	-- the original game showed one tracking icon on the minimap: match it to the spell's icon
	local current = try(fn("GetTrackingTexture"))
	if current then
		for _, o in ipairs(ns.Data.Group("tracking").options) do
			local icon = G.SpellIcon(o.spell, o.id)
			if icon and (icon == current or tostring(icon):lower() == tostring(current):lower()) then out[o.spell] = true end
		end
	end
	return out
end

-- ---------------------------------------------------------------- items
local function itemInfo(id)
	return try(fn("C_Item.GetItemInfo") or fn("GetItemInfo"), id)
end

function G.ItemName(id)
	local name = itemInfo(id)
	return name
end

function G.ItemLevel(id)
	local name, _, _, _, minLevel = itemInfo(id)
	if name then return tonumber(minLevel) end
	local req = fn("C_Item.RequestLoadItemDataByID")
	if req then try(req, id) end
	return nil
end

function G.ItemSpell(id)
	local name = try(fn("C_Item.GetItemSpell") or fn("GetItemSpell"), id)
	return name
end

-- The text of an item's tooltip, from the game's tooltip data (newer clients) or a hidden tooltip.
local scanTip
local function tooltipText(id)
	local byId = fn("C_TooltipInfo.GetItemByID")
	if byId then
		local data = try(byId, id)
		if type(data) == "table" and type(data.lines) == "table" then
			local out = {}
			for _, l in ipairs(data.lines) do
				if type(l.leftText) == "string" and not secret(l.leftText) then out[#out + 1] = l.leftText end
			end
			return table.concat(out, "\n")
		end
	end
	local create = fn("CreateFrame")
	if not create then return nil end
	if not scanTip then
		scanTip = try(create, "GameTooltip", "WoWCRMBuffsScanTip", nil, "GameTooltipTemplate")
		if not scanTip then return nil end
		pcall(scanTip.SetOwner, scanTip, rawget(_G, "WorldFrame") or rawget(_G, "UIParent"), "ANCHOR_NONE")
	end
	pcall(scanTip.ClearLines, scanTip)
	if not pcall(scanTip.SetItemByID, scanTip, id) then return nil end
	local out = {}
	for i = 1, (tonumber(try(scanTip.NumLines, scanTip)) or 0) do
		local fs = rawget(_G, "WoWCRMBuffsScanTipTextLeft" .. i)
		local t = fs and try(fs.GetText, fs)
		if type(t) == "string" then out[#out + 1] = t end
	end
	return table.concat(out, "\n")
end
G.TooltipText = tooltipText

-- Well Fed foods in your bags that the catalog may not know, read from their tooltips:
-- { { item, name, level, stats, source }, ... }. Each item is read once per session.
local foodCache = {}
function G.BagFoods()
	local out, seen = {}, {}
	local slots = fn("C_Container.GetContainerNumSlots") or fn("GetContainerNumSlots")
	local itemId = fn("C_Container.GetContainerItemID") or fn("GetContainerItemID")
	if not (slots and itemId) then return out end
	for bag = 0, 4 do
		for slot = 1, (tonumber(try(slots, bag)) or 0) do
			local id = tonumber(try(itemId, bag, slot))
			if id and not seen[id] then
				seen[id] = true
				local f = foodCache[id]
				if f == nil then
					local text = tooltipText(id)
					local stats = text and ns.Spec.ParseWellFed(text)
					if stats then
						f = { item = id, name = G.ItemName(id) or ("item " .. id), level = G.ItemLevel(id) or 1, stats = stats,
							source = ns.Data.COOK, fromBags = true }
					end
					-- not known yet (item data still loading): try again next time
					if text and G.ItemName(id) then foodCache[id] = f or false end
				end
				if f then out[#out + 1] = f end
			end
		end
	end
	return out
end

function G.ItemIcon(id)
	return try(fn("C_Item.GetItemIconByID") or fn("GetItemIcon"), id)
end

local function count(id, bank)
	return tonumber(try(fn("C_Item.GetItemCount") or fn("GetItemCount"), id, bank)) or 0
end

function G.BagCount(id) return count(id, false) end

-- What the game knows about your bank right now (zero unless it has seen it this session).
function G.BankCount(id) return math.max(0, count(id, true) - count(id, false)) end

-- ---------------------------------------------------------------- places
function G.Resting() return try(fn("IsResting")) and true or false end

function G.RestedXP()
	local xp, max = tonumber(try(fn("GetXPExhaustion"))), tonumber(try(fn("UnitXPMax"), "player"))
	return xp or 0, max or 0
end

function G.InCombat() return try(fn("InCombatLockdown")) and true or false end
