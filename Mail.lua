-- Fills in the Send Mail window from a template. The player reviews it and presses Send.
local _, ns = ...
local U, DB, M = ns.Util, ns.DB, ns.Model
local Mail = {}
ns.Mail = Mail

Mail.open = false
ns.On("MAIL_SHOW", function() Mail.open = true; ns.Notify() end)
ns.On("MAIL_CLOSED", function() Mail.open = false; Mail.filled = nil; ns.Notify() end)

local function bodyBox()
	if SendMailBodyEditBox then return SendMailBodyEditBox end
	if MailEditBox then
		if MailEditBox.GetEditBox then return MailEditBox:GetEditBox() end
		if MailEditBox.ScrollBox and MailEditBox.ScrollBox.EditBox then return MailEditBox.ScrollBox.EditBox end
	end
end

-- Values for {name} {item} {total} {me}, taken from the contact's most recent order.
function Mail.Vars(key)
	local vars = { name = (U.SplitKey(key)), me = ns.MyName(), item = "order", total = U.FormatMoney(0) }
	local latest
	for _, o in ipairs(DB.R.orders) do
		if o.contact == key and (not latest or o.created >= latest.created) then latest = o end
	end
	if latest then
		vars.item = M.OrderTitle(latest, 60)
		vars.total = U.FormatMoney((latest.price or 0) > 0 and latest.price or latest.quote or 0)
	end
	return vars
end

function Mail.Compose(key, templateId)
	if not Mail.open or not MailFrame or not MailFrame:IsShown() then
		return false, "Open a mailbox first."
	end
	local t = M.GetTemplate(templateId)
	if not t then return false, "Pick a mail template." end
	if not (SendMailNameEditBox and SendMailSubjectEditBox) then
		return false, "This client's mail window was not recognised. Run /crm probe and report the result."
	end
	if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
	local vars = Mail.Vars(key)
	SendMailNameEditBox:SetText(U.Display(key, DB.realm))
	SendMailSubjectEditBox:SetText(U.Fill(t.subject, vars):sub(1, 64))
	local body = bodyBox()
	if body then body:SetText(U.Fill(t.body, vars):sub(1, 500)) end
	-- When this letter is actually sent, it is counted as outreach to this contact.
	Mail.filled = { key = key, template = t.name }
	return true
end
