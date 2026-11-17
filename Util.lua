-- Pure helpers. No game API in this file, so it runs under plain Lua for tests.
local _, ns = ...
local U = {}
ns.Util = U

ns.MAX_CHAT_BYTES = 255
ns.TARGETS = { "SAY", "YELL", "GENERAL", "TRADE", "PARTY", "GUILD" }
ns.TARGET_LABEL = {
	SAY = "Say", YELL = "Yell", GENERAL = "General",
	TRADE = "Trade", PARTY = "Party", GUILD = "Guild",
}
ns.PUBLIC_TARGET = { SAY = true, YELL = true, GENERAL = true, TRADE = true }
ns.CONTACT_STATUS = { "lead", "customer", "repeat", "vip", "do not contact", "ignored" }
ns.ORDER_STATUS = { "quoted", "in progress", "delivered", "paid", "cancelled" }
ns.ORDER_TYPE = { "crafted", "goods", "service" }

function U.Now()
	local f = rawget(_G, "time") or os.time
	return f()
end

-- Hour of the day (0-23) on the player's own clock.
function U.Hour(t)
	local d = rawget(_G, "date") or os.date
	return tonumber(d("%H", t)) or 0
end

function U.Trim(s)
	s = tostring(s or "")
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	return s
end

-- Chat limits are in bytes, not letters: accented letters and item links cost more than they look.
function U.ByteLen(s)
	return #(s or "")
end

function U.Contains(list, value)
	for i = 1, #list do
		if list[i] == value then return i end
	end
	return nil
end

-- "name" or "name-realm" -> "Name-Realm". Returns nil for an empty name.
-- tidy=true fixes capitalisation of hand-typed plain ASCII names.
function U.NormName(name, myRealm, tidy)
	name = U.Trim(name)
	if name == "" then return nil end
	local n, r = name:match("^([^%-]+)%-(.+)$")
	if not n then n, r = name, myRealm end
	r = (r or ""):gsub("[%s%-]", "")
	if r == "" then r = "Unknown" end
	if tidy and not n:find("[\128-\255]") then
		n = n:sub(1, 1):upper() .. n:sub(2):lower()
	end
	return n .. "-" .. r
end

function U.SplitKey(key)
	local n, r = tostring(key):match("^([^%-]+)%-(.+)$")
	return n or key, r
end

-- Short form for display and for whisper/mail targets on the same realm.
function U.Display(key, myRealm)
	local n, r = U.SplitKey(key)
	if not r or r == myRealm then return n end
	return key
end

function U.Fill(template, vars)
	return (tostring(template or ""):gsub("{(%w+)}", function(k)
		local v = vars and vars[k]
		if v ~= nil then return tostring(v) end
	end))
end

function U.FormatMoney(copper)
	copper = math.floor((tonumber(copper) or 0) + 0.5)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- "12g 50s", "12.5g", "30s" or a bare number (taken as gold). Returns copper, or nil if unreadable.
function U.ParseMoney(s)
	s = U.Trim(s):lower():gsub(",", "")
	if s == "" then return 0 end
	local plain = tonumber(s)
	if plain then
		if plain < 0 then return nil end
		return math.floor(plain * 10000 + 0.5)
	end
	local total, found = 0, false
	for num, unit in s:gmatch("([%d%.]+)%s*([gsc])") do
		local n = tonumber(num)
		if not n then return nil end
		found = true
		total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
	end
	local rest = s:gsub("[%d%.]+%s*[gsc]", "")
	if not found or rest:find("%S") then return nil end
	return math.floor(total + 0.5)
end

function U.Escape(s)
	s = tostring(s == nil and "" or s)
	s = s:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", ""):gsub("\n", "\\n")
	return s
end

function U.Unescape(s)
	return (s:gsub("\\(.)", function(c)
		if c == "t" then return "\t" elseif c == "n" then return "\n" end
		return c
	end))
end

function U.SplitTabs(line)
	local out = {}
	for field in (line .. "\t"):gmatch("(.-)\t") do
		out[#out + 1] = U.Unescape(field)
	end
	return out
end

function U.Shorten(s, n)
	s = tostring(s or ""):gsub("[\r\n]+", " ")
	if #s <= n then return s end
	return s:sub(1, n - 3) .. "..."
end
