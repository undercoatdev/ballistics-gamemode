-- Admin button, top-right, admins only. Frame with Spawns / Teams / Rules.
-- Every tab and sub-tab has Reset to defaults. Placeholders leave it disabled.
-- Teams is filled in by cl_tab_teams.lua via BALLISTICS.Admin.Register.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Admin = BALLISTICS.Admin or {}
BALLISTICS.Admin.Builders = BALLISTICS.Admin.Builders or {}

function BALLISTICS.Admin.Register(id, builder)
	if type(id) ~= "string" or type(builder) ~= "function" then return end
	BALLISTICS.Admin.Builders[id] = builder
end

function BALLISTICS.ClientIsAdmin()
	if not LocalPlayer then return false end
	local ply = LocalPlayer()
	if ply == nil then return false end
	if IsValid and not IsValid(ply) then return false end
	return BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply) == true
end

local function adminNow()
	if BALLISTICS.AdminTabs and BALLISTICS.AdminTabs.ButtonVisible then
		return BALLISTICS.AdminTabs.ButtonVisible(BALLISTICS.ClientIsAdmin())
	end
	return BALLISTICS.ClientIsAdmin()
end

local button
local frame
local nextGate = 0

local function syncCursor()
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then
		BALLISTICS.UI.SyncCursor()
	end
end

BALLISTICS.UI = BALLISTICS.UI or {}
local openPanels = {}

function BALLISTICS.UI.Mark(id, pnl)
	openPanels[id] = pnl
end

function BALLISTICS.UI.SyncCursor()
	if not gui or not gui.EnableScreenClicker then return end
	local on = false
	for _, pnl in pairs(openPanels) do
		if IsValid(pnl) and pnl:IsVisible() then
			on = true
			break
		end
	end
	gui.EnableScreenClicker(on)
end

function BALLISTICS.Admin.ConfirmReset(node)
	if not (BALLISTICS.AdminTabs and BALLISTICS.AdminTabs.ResetRequest) then return end
	local req = BALLISTICS.AdminTabs.ResetRequest(node)
	if not req then return end
	if not Derma_Query or not net or not net.Start then return end
	local title = (type(node) == "table" and node.title) or req.section
	local msgName = "bal_config_set"
	if BALLISTICS.LobbyView and BALLISTICS.LobbyView.Messages then
		msgName = BALLISTICS.LobbyView.Messages().config or msgName
	end
	Derma_Query(
		"Reset " .. title .. " to the shipped defaults?",
		"Reset to defaults",
		"Reset",
		function()
			net.Start(msgName)
			net.WriteTable(req)
			net.SendToServer()
		end,
		"Cancel",
		function() end
	)
end

local function placeholder(parent, node)
	local lab = vgui.Create("DLabel", parent)
	lab:Dock(FILL)
	lab:SetContentAlignment(5)
	lab:SetText((node.title or "This tab") .. " is not available yet.")
	if lab.SetTextColor then lab:SetTextColor(Color(210, 210, 210)) end
end

local function addNodes(sheet, nodes)
	for i = 1, #nodes do
		local node = nodes[i]
		local page = vgui.Create("DPanel")
		page.balTabId = node.id
		page:DockPadding(6, 6, 6, 6)
		page.Paint = function() end

		local bar = vgui.Create("DPanel", page)
		bar:Dock(BOTTOM)
		bar:SetTall(36)
		bar:DockPadding(0, 4, 0, 0)
		bar.Paint = function() end

		local reset = vgui.Create("DButton", bar)
		reset:Dock(RIGHT)
		reset:SetWide(170)
		reset:SetText("Reset to defaults")
		local spec = node.reset or {}
		if spec.enabled and spec.section then
			reset.DoClick = function()
				BALLISTICS.Admin.ConfirmReset(node)
			end
		else
			reset:SetEnabled(false)
		end

		local body = vgui.Create("DPanel", page)
		body:Dock(FILL)
		body.Paint = function() end

		local builder = BALLISTICS.Admin.Builders[node.id]
		if node.children and #node.children > 0 then
			local child = vgui.Create("DPropertySheet", body)
			child:Dock(FILL)
			addNodes(child, node.children)
		elseif builder then
			builder(body)
		else
			placeholder(body, node)
		end

		sheet:AddSheet(node.title or node.id, page)
	end
end

local function selectTeams(sheet)
	local items = sheet.Items
	if not items then return end
	for i = 1, #items do
		local item = items[i]
		if item.Panel and item.Panel.balTabId == "teams" and item.Tab and sheet.SetActiveTab then
			sheet:SetActiveTab(item.Tab)
			return
		end
	end
end

local function ensureFrame()
	if IsValid(frame) then return frame end
	if not vgui or not vgui.Create then return nil end
	frame = vgui.Create("DFrame")
	frame:SetVisible(false)
	frame:SetTitle("Admin")
	frame:SetSize(760, 580)
	frame:Center()
	frame:SetDeleteOnClose(false)
	frame:SetSizable(false)
	frame:DockPadding(8, 28, 8, 8)
	function frame:OnClose()
		BALLISTICS.UI.Mark("admin", frame)
		syncCursor()
	end

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:Dock(FILL)
	local tree = {}
	if BALLISTICS.AdminTabs and BALLISTICS.AdminTabs.Tree then
		tree = BALLISTICS.AdminTabs.Tree()
	end
	addNodes(sheet, tree)
	selectTeams(sheet)
	BALLISTICS.UI.Mark("admin", frame)
	return frame
end

function BALLISTICS.Admin.IsOpen()
	return IsValid(frame) and frame:IsVisible()
end

function BALLISTICS.Admin.Close()
	if IsValid(frame) then frame:Close() end
end

function BALLISTICS.Admin.Open()
	if not adminNow() then
		BALLISTICS.Admin.Close()
		return
	end
	local pnl = ensureFrame()
	if not IsValid(pnl) then return end
	if pnl.InvalidateLayout then pnl:InvalidateLayout(true) end
	pnl:SetVisible(true)
	pnl:MakePopup()
	BALLISTICS.UI.Mark("admin", pnl)
	syncCursor()
end

function BALLISTICS.Admin.Toggle()
	if not adminNow() then
		BALLISTICS.Admin.Close()
		return
	end
	if BALLISTICS.Admin.IsOpen() then
		BALLISTICS.Admin.Close()
	else
		BALLISTICS.Admin.Open()
	end
end

local function placeButton()
	if not IsValid(button) then return end
	local w, h = 84, 26
	button:SetSize(w, h)
	local sw = (ScrW and ScrW()) or 0
	button:SetPos(math.max(0, sw - w - 10), 10)
end

local function refreshButton()
	if not vgui or not vgui.Create then return end
	if not IsValid(button) then
		button = vgui.Create("DButton")
		button:SetText("ADMIN")
		button:SetZPos(32767)
		button.DoClick = function()
			BALLISTICS.Admin.Toggle()
		end
		button.Paint = function(self, w, h)
			surface.SetDrawColor(28, 28, 32, 230)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(220, 170, 60, 255)
			surface.DrawOutlinedRect(0, 0, w, h)
			draw.SimpleText("ADMIN", "DermaDefaultBold", w / 2, h / 2, Color(240, 220, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		button:SetText("")
	end
	placeButton()
	local show = adminNow()
	button:SetVisible(show)
	if show then button:MoveToFront() end
	if not show then BALLISTICS.Admin.Close() end
end

hook.Add("InitPostEntity", "Ballistics_AdminButton", function()
	refreshButton()
end)

hook.Add("OnScreenSizeChanged", "Ballistics_AdminButton", function()
	placeButton()
end)

hook.Add("Think", "Ballistics_AdminGate", function()
	local now = (CurTime and CurTime()) or 0
	if now < nextGate then return end
	nextGate = now + 0.5
	refreshButton()
end)

if LocalPlayer and IsValid(LocalPlayer()) then
	timer.Simple(0, refreshButton)
end
