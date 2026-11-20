-- Adds two things to the game's own profession window:
--   * Double-click a material. If a recipe in this window makes it, that recipe opens and a
--     Back button returns you to the item you were looking at. Otherwise a panel says where
--     the material comes from.
--   * When the chosen recipe needs parts you can make here but do not hold, it says what to
--     craft first.
-- Nothing here crafts or clicks for you: the game's Create button stays yours.
--
-- Two kinds of window are handled behind one set of functions (an "adapter" each):
--   modern  - ProfessionsFrame (Blizzard_Professions), what the Forever client uses
--   trade / craft - the older TradeSkillFrame and CraftFrame
local _, ns = ...
local U, S = ns.Util, ns.Sources
local R = {}
ns.Reagents = R

local DOUBLE_CLICK = 0.4 -- seconds between two clicks that count as a double-click

local function G(name) return rawget(_G, name) end
local function pass(ok, ...) if ok then return ... end end
local function call(name, ...)
	local f = G(name)
	if type(f) ~= "function" then return nil end
	return pass(pcall(f, ...))
end
local function api(name, ...)
	local t = G("C_TradeSkillUI")
	local f = type(t) == "table" and t[name]
	if type(f) ~= "function" then return nil end
	return pass(pcall(f, ...))
end
-- Values the game hides from add-ons (in combat, on newer clients) are treated as unknown.
local function plain(v)
	local secret = G("issecretvalue")
	if secret and secret(v) then return nil end
	return v
end
local function now() local t = G("GetTime"); return t and t() or U.Now() end

local function owned(itemID)
	local get = (C_Item and C_Item.GetItemCount) or G("GetItemCount")
	if not get or not itemID then return 0 end
	local ok, n = pcall(get, itemID, true)
	return ok and tonumber(plain(n)) or 0
end

local function itemName(itemID)
	local byID = C_Item and C_Item.GetItemNameByID
	local n = byID and pass(pcall(byID, itemID))
	if not n and ns.Price and ns.Price.ItemName then n = ns.Price.ItemName(itemID) end
	return n
end

local function itemLink(itemID)
	return ns.Price and ns.Price.ItemLink and ns.Price.ItemLink(itemID) or nil
end

local function enabled() return not (ns.DB.settings and ns.DB.settings.reagentHelp == false) end

-- ================================================================ adapters
-- Each adapter answers:
--   current()            -> key of the recipe on show, and its name
--   reagents(key)        -> { { name, itemID, qty, link } } the recipe needs
--   maker(itemID, name)  -> key of a recipe in this window that makes the item, or nil
--   open(entry)          -> show the recipe { key, name } again
--   made(key)            -> how many one craft makes

-- ---------------------------------------------------------------- modern: ProfessionsFrame

local modern = { key = "modern", addon = "Blizzard_Professions", frame = "ProfessionsFrame" }

local function form()
	local f = G("ProfessionsFrame")
	local page = f and f.CraftingPage
	return page and page.SchematicForm
end

local function schematic(recipeID)
	local s = api("GetRecipeSchematic", recipeID, false)
	return type(s) == "table" and s or nil
end

local function recipeName(recipeID, s)
	local info = api("GetRecipeInfo", recipeID)
	return (type(info) == "table" and info.name) or (s and s.name) or ("recipe " .. tostring(recipeID))
end

function modern.current()
	local fm = form()
	if not fm or not fm.GetRecipeInfo then return nil end
	local ok, info = pcall(fm.GetRecipeInfo, fm)
	if ok and type(info) == "table" and plain(info.recipeID) then return info.recipeID, info.name end
end

-- The materials a reagent slot asks for: { itemID, qty }, or nil for optional slots.
local function slotReagent(slotSchematic)
	if type(slotSchematic) ~= "table" or slotSchematic.required == false then return nil end
	local r = type(slotSchematic.reagents) == "table" and slotSchematic.reagents[1]
	local id = r and plain(r.itemID)
	if not id then return nil end
	return id, tonumber(plain(slotSchematic.quantityRequired)) or 1
end

function modern.reagents(recipeID)
	local out, s = {}, schematic(recipeID)
	for _, slot in ipairs(s and s.reagentSlotSchematics or {}) do
		local id, qty = slotReagent(slot)
		if id then out[#out + 1] = { itemID = id, qty = qty, name = itemName(id) or ("item " .. id), link = itemLink(id) } end
	end
	return out
end

function modern.made(recipeID)
	local s = schematic(recipeID)
	return s and tonumber(plain(s.quantityMin)) or 1
end

-- Item made -> recipe, for the profession that is open. Learned recipes win over unlearned ones.
-- Rebuilt when the game says the list changed.
local makers
function modern.maker(itemID)
	if not itemID then return nil end
	if not makers then
		makers = { learned = {}, any = {} }
		for _, id in ipairs(api("GetAllRecipeIDs") or {}) do
			local s = schematic(id)
			local out = s and plain(s.outputItemID)
			if out then
				local info = api("GetRecipeInfo", id)
				if type(info) == "table" and info.learned then
					makers.learned[out] = makers.learned[out] or id
				end
				makers.any[out] = makers.any[out] or id
			end
		end
	end
	return makers.learned[itemID] or makers.any[itemID]
end
function modern.forget() makers = nil end

function modern.open(entry)
	local id = entry.key
	-- Pick it in the open window first. OpenRecipe is the game's own route (it can reopen the
	-- window, which would clear the trail), so it is only the fallback.
	local f = G("ProfessionsFrame")
	local page = f and f.CraftingPage
	local info = api("GetRecipeInfo", id)
	if page and page.SelectRecipe and type(info) == "table" then pcall(page.SelectRecipe, page, info) end
	if modern.current() ~= id then api("OpenRecipe", id) end
end

-- ---------------------------------------------------------------- older: TradeSkillFrame / CraftFrame

local function legacy(def)
	local k = def
	local function index()
		local byID, byName = {}, {}
		for i = 1, tonumber(call(k.count)) or 0 do
			local name, kind = k.info(i)
			if name and kind ~= "header" then
				local id = S.ItemID(call(k.link, i))
				if id and not byID[id] then byID[id] = i end
				if not byName[name:lower()] then byName[name:lower()] = i end
			end
		end
		return byID, byName
	end
	local function find(itemID, name, expand)
		local byID, byName = index()
		local i = (itemID and byID[itemID]) or (name and byName[name:lower()])
		if not i and expand then
			call(k.expand, 0)
			byID, byName = index()
			i = (itemID and byID[itemID]) or (name and byName[name:lower()])
		end
		return i
	end

	function k.current()
		local sel = tonumber(call(k.selected))
		if sel and sel > 0 then return sel, (k.info(sel)) end
	end
	function k.reagents(i)
		local out = {}
		for r = 1, tonumber(call(k.numReagents, i)) or 0 do
			local name, _, need = call(k.rInfo, i, r)
			local link = call(k.rLink, i, r)
			if name then out[#out + 1] = { name = name, itemID = S.ItemID(link), qty = tonumber(need) or 1, link = link } end
		end
		return out
	end
	function k.maker(itemID, name, expand)
		local i = find(itemID, name, expand)
		local cur = k.current()
		-- Indexes shift when headings open, so compare by name, not number.
		if i and cur and k.info(i) == k.info(cur) then return nil end
		return i
	end
	function k.open(entry)
		local i = find(nil, entry.name, true)
		if not i then return end
		call(k.select, i)
		local sf, shown = G(k.scroll), tonumber(G(k.shown)) or 8
		local offset = sf and call("FauxScrollFrame_GetOffset", sf) or 0
		if sf and (i <= offset or i > offset + shown) then
			local top = math.max(0, i - 1)
			call("FauxScrollFrame_SetOffset", sf, top)
			local bar = G((sf.GetName and sf:GetName() or k.scroll) .. "ScrollBar")
			if bar and bar.SetValue then pcall(bar.SetValue, bar, top * 16) end
		end
		call(k.update)
	end
	function k.forget() end
	return k
end

local trade = legacy({
	key = "trade", addon = "Blizzard_TradeSkillUI", frame = "TradeSkillFrame", button = "TradeSkillReagent",
	selected = "GetTradeSkillSelectionIndex", count = "GetNumTradeSkills", link = "GetTradeSkillItemLink",
	numReagents = "GetTradeSkillNumReagents", rInfo = "GetTradeSkillReagentInfo", rLink = "GetTradeSkillReagentItemLink",
	select = "TradeSkillFrame_SetSelection", update = "TradeSkillFrame_Update", expand = "ExpandTradeSkillSubClass",
	scroll = "TradeSkillListScrollFrame", shown = "TRADE_SKILLS_DISPLAYED", line = "GetTradeSkillLine",
	info = function(i) local name, kind = call("GetTradeSkillInfo", i) return name, kind end,
	made = function(i) return tonumber((call("GetTradeSkillNumMade", i))) or 1 end,
})
local craft = legacy({
	key = "craft", addon = "Blizzard_CraftUI", frame = "CraftFrame", button = "CraftReagent",
	selected = "GetCraftSelectionIndex", count = "GetNumCrafts", link = "GetCraftItemLink",
	numReagents = "GetCraftNumReagents", rInfo = "GetCraftReagentInfo", rLink = "GetCraftReagentItemLink",
	select = "CraftFrame_SetSelection", update = "CraftFrame_Update", expand = "ExpandCraftSkillLine",
	scroll = "CraftListScrollFrame", shown = "CRAFTS_DISPLAYED", line = "GetCraftDisplaySkillLine",
	info = function(i) local name, _, kind = call("GetCraftInfo", i) return name, kind end,
	made = function() return 1 end,
})

local KINDS = { modern, trade, craft }
local state = {} -- per window: { trail = {}, dock, panel, hooked }
for _, k in ipairs(KINDS) do state[k.key] = { trail = {} } end

-- ================================================================ what else knows about an item

-- Questie's database, when installed, names the creatures, nodes and vendors.
local function questie(itemID)
	local loader = G("QuestieLoader")
	if not itemID or type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return {} end
	local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
	if not ok or type(db) ~= "table" or type(db.QueryItemSingle) ~= "function" then return {} end
	local function q(fn, id, key)
		if type(db[fn]) ~= "function" then return nil end
		local okQ, v = pcall(db[fn], id, key)
		return okQ and v or nil
	end
	local function names(ids, fn, withLevel)
		local out, seen = {}, {}
		for _, id in ipairs(type(ids) == "table" and ids or {}) do
			local n = q(fn, id, "name")
			if type(n) == "string" and not seen[n] then
				seen[n] = true
				local lo, hi = withLevel and q(fn, id, "minLevel"), withLevel and q(fn, id, "maxLevel")
				out[#out + 1] = n .. ((lo and hi and lo ~= hi) and (" (" .. lo .. "-" .. hi .. ")") or (lo and (" (" .. lo .. ")") or ""))
			end
		end
		return out
	end
	return {
		drops = names(q("QueryItemSingle", itemID, "npcDrops"), "QueryNPCSingle", true),
		objects = names(q("QueryItemSingle", itemID, "objectDrops"), "QueryObjectSingle"),
		vendors = names(q("QueryItemSingle", itemID, "vendors"), "QueryNPCSingle"),
	}
end

-- The profession that makes the item, from any character the Mastercraft add-on has scanned.
local function madeElsewhere(itemID)
	local db = G("MastercraftDB")
	if not itemID or type(db) ~= "table" or type(db.recipes) ~= "table" then return nil end
	for _, profs in pairs(db.recipes) do
		for profName, data in pairs(type(profs) == "table" and profs or {}) do
			for _, r in ipairs(type(data) == "table" and type(data.list) == "table" and data.list or {}) do
				if r.output == itemID then return profName, r.name end
			end
		end
	end
end

local function listLine(label, list, max)
	if #list == 0 then return nil end
	local shown = {}
	for i = 1, math.min(#list, max) do shown[i] = list[i] end
	local more = #list > max and (" and " .. (#list - max) .. " more") or ""
	return "|cffffd100" .. label .. ":|r " .. table.concat(shown, ", ") .. more
end

-- The lines of the "where to get it" panel. Exposed for the tests.
function R.SourceLines(name, itemID)
	local L = {}
	local have = owned(itemID)
	L[#L + 1] = have > 0 and ("|cff40ff40You have " .. have .. " (bags and bank).|r") or "You have none in your bags or bank."
	local prof, recipe = madeElsewhere(itemID)
	if prof then L[#L + 1] = "|cffffd100You can make it:|r " .. tostring(recipe or name) .. " (" .. prof .. "). Open that profession and double-click it there." end
	for _, n in ipairs(S.Notes(name) or {}) do L[#L + 1] = "- " .. n end
	local qd = questie(itemID)
	L[#L + 1] = listLine("Dropped by", qd.drops or {}, 10)
	L[#L + 1] = listLine("Gathered from", qd.objects or {}, 6)
	L[#L + 1] = listLine("Sold by", qd.vendors or {}, 6)
	local compact = {}
	for i = 1, #L do if L[i] then compact[#compact + 1] = L[i] end end
	if #compact == 1 then
		compact[#compact + 1] = "No notes for this item yet. The Wowhead page lists every creature, node and vendor it comes from."
	end
	return compact
end

-- ================================================================ panels beside the window

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local WIDTH = 250

local function box(parent)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(WIDTH, 60)
	if b.SetBackdrop then
		b:SetBackdrop(BACKDROP)
		b:SetBackdropColor(0, 0, 0, 0.9)
		b:SetBackdropBorderColor(0.5, 0.5, 0.5)
	end
	b:EnableMouse(true)
	return b
end

local function text(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWidth(WIDTH - 20)
	return fs
end

local function button(parent, label, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- Where the panels go: just outside the window's right edge. The old windows have a see-through
-- strip on the right, so they tuck in a little.
local function anchor(k, f)
	local x = (k == modern) and 2 or -34
	f:SetPoint("TOPLEFT", G(k.frame), "TOPRIGHT", x, -14)
end

local function dock(k)
	local st = state[k.key]
	if st.dock then return st.dock end
	local d = box(G(k.frame))
	anchor(k, d)
	d.back = button(d, "Back", WIDTH - 20, function() R.Back(k) end)
	d.back:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -10)
	d.plan = text(d)
	d:Hide()
	st.dock = d
	return d
end

local function panel(k)
	local st = state[k.key]
	if st.panel then return st.panel end
	local p = box(G(k.frame))
	p.title = text(p, "GameFontNormal")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
	p.body = text(p)
	p.body:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -6)
	p.wowhead = button(p, "Wowhead", 90, function()
		if ns.UI and ns.UI.ShowLink then ns.UI.ShowLink("Wowhead page for " .. tostring(p.name), S.WowheadURL(p.itemID, p.name)) end
	end)
	p.close = button(p, "Close", 70, function() p:Hide(); R.Layout(k) end)
	p:Hide()
	st.panel = p
	return p
end

-- Stack the dock and the panel down the right-hand side of the window.
function R.Layout(k)
	local st = state[k.key]
	local d, p = st.dock, st.panel
	if p then
		p:ClearAllPoints()
		if d and d:IsShown() then p:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -4) else anchor(k, p) end
	end
end

function R.ShowSources(k, g)
	local p = panel(k)
	p.name, p.itemID = g.name, g.itemID
	p.title:SetText(g.link or g.name or "?")
	p.body:SetText(table.concat(R.SourceLines(g.name, g.itemID), "\n"))
	local h = (p.title:GetStringHeight() or 12) + (p.body:GetStringHeight() or 12)
	p:SetHeight(h + 56)
	p.wowhead:ClearAllPoints()
	p.wowhead:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 10, 8)
	p.close:ClearAllPoints()
	p.close:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -10, 8)
	p:Show()
	R.Layout(k)
end

-- What to craft first for the recipe on show, from recipes in this window.
local function planFor(k, key)
	local function recipeOf(x)
		local r = (x == key) and key or k.maker(x, nil, false)
		if not r then return nil end
		local list = {}
		for _, g in ipairs(k.reagents(r)) do list[#list + 1] = { key = g.itemID or g.name, name = g.name, qty = g.qty } end
		return { name = (x == key) and select(2, k.current()) or nil, made = k.made(r), reagents = list }
	end
	-- The planner names a step after the material when the recipe has no name of its own.
	local steps, missing = S.Plan(key, recipeOf, function(x) return type(x) == "number" and owned(x) or 0 end)
	for _, s in ipairs(steps) do s.name = s.name or s.makes end
	return steps, missing
end

-- Show or hide the Back button and the craft-first advice for the chosen recipe.
function R.Refresh(k)
	local st = state[k.key]
	if not G(k.frame) then return end
	local d = dock(k)
	local top = st.trail[#st.trail]
	local lines = {}

	if top then
		local ready = top.needID and top.needQty and owned(top.needID) >= top.needQty
		d.back:SetText("Back to " .. U.Shorten(top.name, 26) .. (ready and "  |cff40ff40(ready)|r" or ""))
		d.back:Show()
	else
		d.back:Hide()
	end

	local key = enabled() and k.current()
	if key then
		local steps, missing = planFor(k, key)
		local planText = S.PlanText(steps)
		if planText then
			lines[#lines + 1] = "|cffffd100" .. planText .. ".|r Double-click a material to open its recipe."
			local short = {}
			for _, m in ipairs(missing) do short[#short + 1] = m.qty .. "x " .. m.name end
			if #short > 0 then lines[#lines + 1] = "Still to get: " .. table.concat(short, ", ") end
		end
	end

	d.plan:SetText(table.concat(lines, "\n"))
	d.plan:ClearAllPoints()
	if top then d.plan:SetPoint("TOPLEFT", d.back, "BOTTOMLEFT", 0, -6)
	else d.plan:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -10) end
	if top or #lines > 0 then
		d:SetHeight((top and 30 or 0) + (#lines > 0 and ((d.plan:GetStringHeight() or 12) + 6) or 0) + 14)
		d:Show()
	else
		d:Hide()
	end
	R.Layout(k)
end

-- ================================================================ double-click

-- The material g ({ name, itemID, qty, link }) of the recipe on show: open its recipe here,
-- or say where it comes from. Returns "recipe" or "sources" (for the tests and /crm reagents).
function R.Open(k, g)
	if not g or not (g.name or g.itemID) then return end
	g.name = g.name or itemName(g.itemID) or ("item " .. tostring(g.itemID))
	local st = state[k.key]
	local here, hereName = k.current()
	if not here then return end
	local i = k.maker(g.itemID, g.name, true)
	if i and i ~= here then
		S.Push(st.trail, { key = here, name = hereName or "the last recipe", needID = g.itemID, needQty = g.qty })
		if st.panel then st.panel:Hide() end
		k.open({ key = i, name = g.name })
		R.Refresh(k)
		return "recipe"
	end
	R.ShowSources(k, g)
	return "sources"
end

function R.Back(k)
	local top = S.Pop(state[k.key].trail)
	if top then k.open(top) end
	R.Refresh(k)
end

local function hint(k, g)
	if not enabled() or not g or not GameTooltip or not GameTooltip.AddLine then return end
	local i, here = k.maker(g.itemID, g.name, false), k.current()
	GameTooltip:AddLine((i and i ~= here) and "Double-click: open its recipe (WoW CRM)" or "Double-click: where to get it (WoW CRM)", 0.4, 0.8, 1)
	GameTooltip:Show()
end

-- Two presses on the same material within DOUBLE_CLICK seconds.
local lastPress = { at = 0, on = nil }
local function pressed(k, on, what)
	if not enabled() then return end
	if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then
		lastPress.on = nil
		return
	end
	local t = now()
	if lastPress.on == on and t - lastPress.at <= DOUBLE_CLICK then
		lastPress.on = nil
		R.Open(k, what())
	else
		lastPress.on, lastPress.at = on, t
	end
end

-- Hook a button's script, and hook it again if the game has since replaced the script: the
-- Professions window sets fresh handlers on its material buttons each time a recipe is picked,
-- which throws away hooks made earlier.
local seen = setmetatable({}, { __mode = "k" })
local function hookScript(b, script, fn)
	if not b or not b.HookScript then return end
	local mine = seen[b] or {}
	seen[b] = mine
	local cur = b.GetScript and b:GetScript(script) or false
	if mine[script] ~= nil and mine[script] == cur then return end
	b:HookScript(script, fn)
	mine[script] = b.GetScript and b:GetScript(script) or false
end

-- Watch one material button. what() says which material it shows right now (buttons are reused
-- from recipe to recipe, so it is asked at click time).
local function watch(k, b, what, script, clicks)
	if clicks ~= false then
		hookScript(b, script, function(_, mouse)
			if mouse and mouse ~= "LeftButton" then return end
			pressed(k, b, what)
		end)
	end
	hookScript(b, "OnEnter", function() hint(k, what()) end)
end

-- ---------------------------------------------------------------- hooking each kind of window

local function modernSlots()
	local fm = form()
	if not fm or not fm.GetSlots then return {} end
	local ok, slots = pcall(fm.GetSlots, fm)
	return ok and type(slots) == "table" and slots or {}
end

local function slotMaterial(slot)
	return function()
		local s = (slot.GetReagentSlotSchematic and pass(pcall(slot.GetReagentSlotSchematic, slot))) or slot.reagentSlotSchematic
		local id, qty = slotReagent(s)
		if id then return { itemID = id, qty = qty, name = itemName(id), link = itemLink(id) } end
	end
end

-- Clicks in the Professions window are caught from the game's "a mouse button went down
-- anywhere" event, so nothing the window does to its buttons can switch this off. Clients
-- without that event fall back to hooking the buttons.
local mouse = CreateFrame("Frame")
R.mouseFrame = mouse
R.globalClicks = mouse.RegisterEvent and pcall(mouse.RegisterEvent, mouse, "GLOBAL_MOUSE_DOWN") or false
mouse:SetScript("OnEvent", function(_, _, which)
	if which ~= "LeftButton" or not enabled() then return end
	local f = G("ProfessionsFrame")
	if not (f and f.IsVisible and f:IsVisible()) then return end
	for _, slot in ipairs(modernSlots()) do
		local b = slot.Button
		if b and b.IsMouseOver and slot.IsVisible and slot:IsVisible() and b:IsMouseOver() then
			pressed(modern, b, slotMaterial(slot))
			return
		end
	end
end)

local function hookModern()
	local st, fm = state.modern, form()
	if not fm then return end
	local function hookSlots()
		for _, slot in ipairs(modernSlots()) do
			watch(modern, slot.Button, slotMaterial(slot), "OnMouseDown", not R.globalClicks)
		end
	end
	if not st.hooked then
		st.hooked = true
		-- The game lays out the slots when a recipe is picked; hook any new ones, then refresh.
		if hooksecurefunc and fm.Init then
			hooksecurefunc(fm, "Init", function()
				local after = C_Timer and C_Timer.After
				local function go() hookSlots(); if enabled() then R.Refresh(modern) end end
				if after then after(0, go) else go() end
			end)
		end
		local f = G("ProfessionsFrame")
		if f and f.HookScript then
			f:HookScript("OnHide", function()
				st.trail = {}
				modern.forget()
				if st.panel then st.panel:Hide() end
				if st.dock then st.dock:Hide() end
			end)
		end
	end
	hookSlots()
end

local function hookLegacy(k)
	local st = state[k.key]
	local frame = G(k.frame)
	if st.hooked or not frame then return end
	st.hooked = true
	for r = 1, 8 do
		watch(k, G(k.button .. r), function()
			local cur = k.current()
			return cur and k.reagents(cur)[r]
		end, "OnClick")
	end
	-- A different profession, or the window closing, starts a fresh trail.
	if type(G(k.select)) == "function" and hooksecurefunc then
		hooksecurefunc(k.select, function()
			local p = call(k.line)
			if p ~= st.profession then st.profession = p; st.trail = {} end
			st.dirty = true
		end)
	end
	if type(G(k.update)) == "function" and hooksecurefunc then
		hooksecurefunc(k.update, function()
			if st.dirty and enabled() then st.dirty = false; R.Refresh(k) end
		end)
	end
	if frame.HookScript then
		frame:HookScript("OnHide", function()
			st.trail = {}
			if st.panel then st.panel:Hide() end
			if st.dock then st.dock:Hide() end
		end)
	end
end

function R.HookAll()
	hookModern()
	hookLegacy(trade)
	hookLegacy(craft)
end

-- What /crm reagents check prints: which window this client has and whether it is hooked.
function R.Status()
	local out = {}
	for _, k in ipairs(KINDS) do
		local f = G(k.frame)
		out[#out + 1] = ("%s: %s%s"):format(k.frame, f and "present" or "not loaded", f and (state[k.key].hooked and ", hooked" or ", NOT hooked") or "")
	end
	local fm = form()
	if fm then
		out[#out + 1] = ("recipe on show: %s, material slots: %d, clicks read %s"):format(tostring(select(2, modern.current()) or "none"),
			#modernSlots(), R.globalClicks and "from the game's mouse event" or "from the buttons")
	end
	return out
end

R.KINDS = KINDS
R.state = state
R.modern, R.trade = modern, trade

-- The windows are loaded only when first opened.
ns.On("ADDON_LOADED", function(name)
	for _, k in ipairs(KINDS) do if name == k.addon then R.HookAll() end end
end)
ns.On("PLAYER_LOGIN", R.HookAll)
ns.On("TRADE_SKILL_SHOW", R.HookAll)
ns.On("CRAFT_SHOW", R.HookAll)
ns.On("TRADE_SKILL_LIST_UPDATE", function() modern.forget() end)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() modern.forget(); state.modern.trail = {} end)
ns.On("BAG_UPDATE_DELAYED", function()
	for _, k in ipairs(KINDS) do
		local f = G(k.frame)
		if f and f.IsShown and f:IsShown() and enabled() then R.Refresh(k) end
	end
end)
