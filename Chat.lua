-- Channel lookup, click-driven posting, whisper capture, and the in-game probe.
local _, ns = ...
local U, DB, M = ns.Util, ns.DB, ns.Model
local Chat = {}
ns.Chat = Chat

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function sendChat(text, chatType, channel)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	send(text, chatType, nil, channel)
end

-- Finds a joined channel whose name starts with the given word ("General", "Trade").
-- Names look like "Trade - City"; anything with brackets (e.g. a services channel) is skipped.
function Chat.FindChannel(prefix)
	prefix = U.Trim(prefix):lower()
	if prefix == "" then return nil end
	local list = { GetChannelList() }
	for i = 1, #list, 3 do
		local id, name, disabled = list[i], list[i + 1], list[i + 2]
		if type(name) == "string" and not disabled then
			local low = name:lower()
			if low:sub(1, #prefix) == prefix and not low:find("%(") then
				local nextChar = low:sub(#prefix + 1, #prefix + 1)
				if nextChar == "" or nextChar == " " then return id, name end
			end
		end
	end
end

-- Returns ok, reason, channelId
function Chat.Available(target)
	if target == "SAY" or target == "YELL" then
		return true
	elseif target == "PARTY" then
		if IsInGroup() then return true end
		return false, "not in a party"
	elseif target == "GUILD" then
		if IsInGuild() then return true end
		return false, "not in a guild"
	elseif target == "GENERAL" or target == "TRADE" then
		local name = target == "GENERAL" and DB.settings.generalName or DB.settings.tradeName
		local id = Chat.FindChannel(name)
		if id then return true, nil, id end
		return false, "not in that channel here"
	end
	return false, "unknown channel"
end

function Chat.Render(post)
	return U.Fill(post.text, { me = UnitName("player"), zone = GetZoneText() })
end

-- Sends one message to one channel. MUST be called directly from a click or key press.
function Chat.Send(post, target)
	local ok, why, channelId = Chat.Available(target)
	if not ok then return false, ns.TARGET_LABEL[target] .. ": " .. why end
	local now = U.Now()
	local gap = M.GapRemaining(target, now)
	if gap > 0 then return false, ("%s: wait %ds"):format(ns.TARGET_LABEL[target], gap) end
	local text = Chat.Render(post)
	if U.ByteLen(text) > ns.MAX_CHAT_BYTES then
		return false, ("Message is %d bytes after filling in tokens; the limit is %d."):format(U.ByteLen(text), ns.MAX_CHAT_BYTES)
	end
	if channelId then
		sendChat(text, "CHANNEL", channelId)
	else
		sendChat(text, target)
	end
	M.RecordSend(post, target, now, GetZoneText())
	ns.Changed(true)
	return true
end

-- One click: send to the next channel in this post's rotation.
function Chat.SendNext(post)
	local target, why = M.NextTarget(post, Chat.Available, U.Now())
	if not target then return false, why end
	local ok, err = Chat.Send(post, target)
	if ok then return true, ns.TARGET_LABEL[target] end
	return false, err
end

-- Whispers a saved post to one player. This is a private message, so it is not counted as a
-- post, has no waiting time, and does not move the post's channel rotation.
function Chat.WhisperPost(post, who)
	who = U.Trim(who)
	if who == "" then return false, "Type who to whisper." end
	local contact = M.FindContact(who)
	local name = contact and U.Display(contact.key, DB.realm) or who
	local text = Chat.Render(post)
	if U.ByteLen(text) > ns.MAX_CHAT_BYTES then
		return false, ("Message is %d bytes after filling in tokens; the limit is %d."):format(U.ByteLen(text), ns.MAX_CHAT_BYTES)
	end
	sendChat(text, "WHISPER", name)
	return true, name
end

-- One click during a campaign: send whatever the campaign says is due.
function Chat.CampaignPost()
	local now = U.Now()
	local c = M.ActiveCampaign(now)
	if not c then return false, "No campaign is running." end
	local post, target, wait = M.CampaignNext(c, Chat.Available, now)
	if not post then
		return false, wait and ("Next post in " .. M.Clock(wait) .. ".") or "None of this campaign's channels are available here."
	end
	local ok, err = Chat.Send(post, target)
	if not ok then return false, err end
	M.CampaignAdvance(c, post, Chat.Available, U.Now())
	return true, post.name .. " > " .. ns.TARGET_LABEL[target]
end

-- ---------------------------------------------------------------- whispers

ns.On("CHAT_MSG_WHISPER", function(text, sender)
	if not ns.ready or isSecret(sender) or type(sender) ~= "string" then return end
	if isSecret(text) then text = "(hidden during combat)" end
	local key = U.NormName(sender, DB.realm)
	if not key then return end
	ns.lastWhisperFrom = key
	local lead, isNew = M.OnWhisper(key, tostring(text or ""), U.Now())
	if lead then
		ns.Print((isNew and "new contact and lead: " or "lead from ") .. U.Display(key, DB.realm))
		ns.Changed()
	end
end)

ns.On("CHAT_MSG_WHISPER_INFORM", function(_, target)
	if not ns.ready or isSecret(target) or type(target) ~= "string" then return end
	local c = M.GetContact(U.NormName(target, DB.realm))
	if c then c.lastContact = U.Now() end
end)

-- Opens the chat box with a reply to the last person who whispered, ready to read and send.
function Chat.Reply(text)
	local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
	if not open then return false end
	open("/r " .. text)
	return true
end

function Chat.Whisper(key)
	local name = U.Display(key, DB.realm)
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	end
end

-- ---------------------------------------------------------------- probe
-- Checks the assumptions this add-on makes about the client and records the answers
-- in the saved data, so they can be read back after a reload.

function Chat.Probe()
	local version, build, _, toc = GetBuildInfo()
	local p = {
		time = U.Now(), version = version, build = build, toc = toc,
		hasCChatInfoSend = (C_ChatInfo and C_ChatInfo.SendChatMessage) and true or false,
		hasSecretValues = issecretvalue ~= nil,
		hasCUIReload = (C_UI and C_UI.Reload) and true or false,
		mailName = SendMailNameEditBox ~= nil,
		mailSubject = SendMailSubjectEditBox ~= nil,
		mailBodyClassic = SendMailBodyEditBox ~= nil,
		mailBodyModern = MailEditBox ~= nil,
		channels = {},
		targets = {},
	}
	local list = { GetChannelList() }
	for i = 1, #list, 3 do
		p.channels[#p.channels + 1] = tostring(list[i]) .. "=" .. tostring(list[i + 1]) .. (list[i + 2] and " (disabled)" or "")
	end
	for _, t in ipairs(ns.TARGETS) do
		local ok, why = Chat.Available(t)
		p.targets[t] = ok and "ok" or why
	end
	DB.db.probe = p
	ns.Print(("client %s build %s interface %s"):format(tostring(version), tostring(build), tostring(toc)))
	ns.Print("channels: " .. (#p.channels > 0 and table.concat(p.channels, ", ") or "none"))
	for _, t in ipairs(ns.TARGETS) do ns.Print(("  %s: %s"):format(ns.TARGET_LABEL[t], p.targets[t])) end
	ns.UI.ShowProbe()
end

-- Called by the probe window. mode "click" sends straight from the click; mode "timer"
-- sends a moment later, which the game should refuse if the click rule applies here.
function Chat.ProbeSay(mode, text)
	local p = DB.db.probe or {}
	DB.db.probe = p
	ns.lastBlocked = nil
	local function go()
		local ok, err = pcall(sendChat, text, "SAY")
		C_Timer.After(1, function()
			p["say_" .. mode] = (not ok and ("error: " .. tostring(err))) or (ns.lastBlocked and ("blocked: " .. ns.lastBlocked)) or "sent"
			ns.Print(("probe %s-send: %s"):format(mode, p["say_" .. mode]))
			ns.Changed()
		end)
	end
	if mode == "timer" then C_Timer.After(0.5, go) else go() end
end
