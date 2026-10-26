-- Rules editors for Costs, Gains, and General.
-- Each edit is one bal_config_set. The server checks admin and clamps.
-- Reset to defaults is the button on the admin shell.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Admin = BALLISTICS.Admin or {}

local function messageName()
	local name = "bal_config_set"
	if BALLISTICS.LobbyView and BALLISTICS.LobbyView.Messages then
		local messages = BALLISTICS.LobbyView.Messages()
		if type(messages.config) == "string" and messages.config ~= "" then
			name = messages.config
		end
	end
	return name
end

local function send(view, payload)
	if not view or type(view.PayloadFor) ~= "function" then
		view = BALLISTICS.RulesView
	end
	if not view or type(view.PayloadFor) ~= "function" then return end
	local admin = BALLISTICS.ClientIsAdmin and BALLISTICS.ClientIsAdmin()
	local clean = view.PayloadFor(admin, payload)
	if not clean then return end
	if not (net and net.Start and net.WriteTable and net.SendToServer) then return end
	net.Start(messageName())
	net.WriteTable(clean)
	net.SendToServer()
end

local function findRow(view, sectionId, path)
	if not view or type(view.Rows) ~= "function" then return nil end
	local rows = view.Rows(sectionId)
	for i = 1, #rows do
		if rows[i].path == path then return rows[i] end
	end
	return nil
end

local function paintLine(w, h)
	if not surface or not surface.SetDrawColor or not surface.DrawRect then return end
	surface.SetDrawColor(32, 34, 40, 255)
	surface.DrawRect(0, 0, w, h)
end

function BALLISTICS.Admin.BuildRules(parent, sectionId, view)
	if parent == nil then return end
	if IsValid and not IsValid(parent) then return end
	if parent.Clear then parent:Clear() end
	if not vgui or not vgui.Create then return end

	if not view or type(view.Rows) ~= "function" then
		view = BALLISTICS.RulesView
	end
	if not view or type(view.Rows) ~= "function" then return end

	local scroll = vgui.Create("DScrollPanel", parent)
	if not IsValid or not IsValid(scroll) then return end
	scroll:Dock(FILL)
	scroll.Paint = function() end

	local widgets = {}
	local lastSent = {}
	local mute = false

	local function commit(path, display)
		if mute then return end
		local row = findRow(view, sectionId, path)
		if not row then return end
		if view.Same and view.Same(row.display, display) then return end
		if view.Same and view.Same(lastSent[path], display) then return end
		local payload = nil
		if type(view.Commit) == "function" then
			payload = view.Commit(row, display)
		end
		if not payload then return end
		lastSent[path] = display
		send(view, payload)
	end

	local function hover(panel, row)
		if panel == nil or type(row) ~= "table" then return end
		if type(row.blurb) ~= "string" or row.blurb == "" then return end
		if panel.SetTooltip then panel:SetTooltip(row.blurb) end
	end

	local function addLabel(line, text)
		local lab = vgui.Create("DLabel", line)
		lab:Dock(FILL)
		lab:DockMargin(8, 0, 8, 0)
		lab:SetText(text or "")
		if lab.SetTextColor then lab:SetTextColor(Color(230, 230, 230)) end
	end

	local function addNumber(row)
		local line = vgui.Create("DPanel", scroll)
		line:Dock(TOP)
		line:SetTall(28)
		line:DockMargin(0, 0, 0, 4)
		line.Paint = function(_, w, h) paintLine(w, h) end
		hover(line, row)

		local wang = vgui.Create("DNumberWang", line)
		hover(wang, row)
		wang:Dock(RIGHT)
		wang:SetWide(110)
		wang:DockMargin(0, 2, 4, 2)
		if wang.SetMin then wang:SetMin(row.min or 0) end
		if wang.SetMax then wang:SetMax(row.max or 1000000) end
		if wang.SetDecimals then wang:SetDecimals(row.decimals or 0) end
		mute = true
		if wang.SetValue then wang:SetValue(tonumber(row.display) or 0) end
		mute = false
		addLabel(line, row.label)

		local function push()
			if mute then return end
			local val = nil
			if wang.GetValue then val = wang:GetValue() end
			commit(row.path, val)
		end
		wang.OnValueChanged = function()
			push()
		end
		wang.OnEnter = function()
			push()
		end
		local base = wang.OnLoseFocus
		wang.OnLoseFocus = function(self)
			if base then base(self) end
			push()
		end
		widgets[row.path] = {
			apply = function(live)
				if wang.HasFocus and wang:HasFocus() then return end
				mute = true
				if wang.SetValue then wang:SetValue(tonumber(live.display) or 0) end
				mute = false
				lastSent[row.path] = nil
			end,
		}
	end

	local function addBool(row)
		local line = vgui.Create("DPanel", scroll)
		line:Dock(TOP)
		line:SetTall(28)
		line:DockMargin(0, 0, 0, 4)
		line.Paint = function(_, w, h) paintLine(w, h) end
		hover(line, row)

		local box = vgui.Create("DCheckBoxLabel", line)
		hover(box, row)
		box:Dock(FILL)
		box:DockMargin(8, 4, 8, 4)
		box:SetText(row.label or "")
		if box.SetTextColor then box:SetTextColor(Color(230, 230, 230)) end
		mute = true
		if box.SetValue then box:SetValue(row.display == true) end
		mute = false
		box.OnChange = function(_, val)
			if mute then return end
			commit(row.path, val)
		end
		widgets[row.path] = {
			apply = function(live)
				mute = true
				if box.SetValue then box:SetValue(live.display == true) end
				mute = false
				lastSent[row.path] = nil
			end,
		}
	end

	local function addString(row)
		local line = vgui.Create("DPanel", scroll)
		line:Dock(TOP)
		line:SetTall(28)
		line:DockMargin(0, 0, 0, 4)
		line.Paint = function(_, w, h) paintLine(w, h) end
		hover(line, row)

		local entry = vgui.Create("DTextEntry", line)
		hover(entry, row)
		entry:Dock(RIGHT)
		entry:SetWide(180)
		entry:DockMargin(0, 2, 4, 2)
		mute = true
		if entry.SetText then entry:SetText(tostring(row.display or "")) end
		mute = false
		addLabel(line, row.label)

		local function push()
			if mute then return end
			local val = ""
			if entry.GetValue then
				val = entry:GetValue()
			elseif entry.GetText then
				val = entry:GetText()
			end
			commit(row.path, val)
		end
		entry.OnEnter = function()
			push()
		end
		local base = entry.OnLoseFocus
		entry.OnLoseFocus = function(self)
			if base then base(self) end
			push()
		end
		widgets[row.path] = {
			apply = function(live)
				if entry.HasFocus and entry:HasFocus() then return end
				mute = true
				if entry.SetText then entry:SetText(tostring(live.display or "")) end
				mute = false
				lastSent[row.path] = nil
			end,
		}
	end

	local function paintMode(btn, on)
		local label = btn.balLabel or ""
		btn.Paint = function(_, w, h)
			if not surface or not surface.DrawRect then return end
			if on then
				surface.SetDrawColor(46, 110, 64, 255)
			else
				surface.SetDrawColor(48, 48, 56, 255)
			end
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(200, 200, 200, 255)
			if surface.DrawOutlinedRect then surface.DrawOutlinedRect(0, 0, w, h) end
			if draw and draw.SimpleText then
				draw.SimpleText(label, "DermaDefault", w / 2, h / 2, Color(240, 240, 240), TEXT_ALIGN_CENTER or 1, TEXT_ALIGN_CENTER or 1)
			end
		end
		btn:SetText("")
	end

	local function addEnum(row)
		local line = vgui.Create("DPanel", scroll)
		line:Dock(TOP)
		line:SetTall(32)
		line:DockMargin(0, 0, 0, 4)
		line.Paint = function(_, w, h) paintLine(w, h) end
		hover(line, row)

		local buttons = {}
		local values = row.values or {}
		for i = #values, 1, -1 do
			local entry = values[i]
			local btn = vgui.Create("DButton", line)
			btn:Dock(RIGHT)
			btn:SetWide(110)
			btn:DockMargin(0, 3, 4, 3)
			btn.balLabel = entry.label or entry.id
			btn.balId = entry.id
			hover(btn, row)
			btn.DoClick = function()
				commit(row.path, entry.id)
			end
			buttons[#buttons + 1] = btn
		end
		addLabel(line, row.label)

		local function style(current)
			for i = 1, #buttons do
				paintMode(buttons[i], buttons[i].balId == current)
			end
		end
		style(row.display)
		widgets[row.path] = {
			apply = function(live)
				style(live.display)
				lastSent[row.path] = nil
			end,
		}
	end

	local rows = view.Rows(sectionId)
	if #rows == 0 then
		local empty = vgui.Create("DLabel", scroll)
		empty:Dock(TOP)
		empty:SetTall(24)
		empty:SetText("Nothing to edit here.")
		if empty.SetTextColor then empty:SetTextColor(Color(200, 200, 200)) end
		return
	end

	for i = 1, #rows do
		local row = rows[i]
		if row.kind == "bool" then
			addBool(row)
		elseif row.kind == "enum" then
			addEnum(row)
		elseif row.kind == "string" then
			addString(row)
		else
			addNumber(row)
		end
	end

	if not (hook and hook.Add and hook.Remove) then return end
	local hookId = "Ballistics_RulesRefresh_" .. tostring(sectionId)
	local nextRefresh = 0
	hook.Add("Think", hookId, function()
		if IsValid and not IsValid(parent) then
			hook.Remove("Think", hookId)
			return
		end
		local now = (CurTime and CurTime()) or 0
		if now < nextRefresh then return end
		nextRefresh = now + 0.25
		local live = view.Rows(sectionId)
		for n = 1, #live do
			local slot = widgets[live[n].path]
			if slot and slot.apply then slot.apply(live[n]) end
		end
	end)
end

local LEAVES = { "weapons", "throwables", "meds", "attachments", "gains", "general" }

if BALLISTICS.Admin.Register then
	for i = 1, #LEAVES do
		local id = LEAVES[i]
		BALLISTICS.Admin.Register(id, function(parent)
			BALLISTICS.Admin.BuildRules(parent, id)
		end)
	end
end
