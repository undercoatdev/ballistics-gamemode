-- Lobby panel: Good and Bad columns, click to take or switch, admin Start.
-- No countdown. Non-admins see "Waiting for admin". F2 (ShowTeam) reopens it.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Lobby = BALLISTICS.Lobby or {}

local GOOD = BALLISTICS.TEAM_GOOD or 1
local BAD = BALLISTICS.TEAM_BAD or 2
local TITLE = 24

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsSlot", { font = "Roboto", size = 18, weight = 600, antialias = true })
	surface.CreateFont("BallisticsHeader", { font = "Roboto", size = 20, weight = 700, antialias = true })
	surface.CreateFont("BallisticsSmall", { font = "Roboto", size = 15, weight = 500, antialias = true })
end

local state = {
	perTeam = 5,
	synced = false,
	sides = { [GOOD] = {}, [BAD] = {} },
	queue = {},
	phase = "lobby",
}

local frame
local widgets
local current
local listeners = {}
local statusText = ""
local statusUntil = 0
local builtPer = 0

local function clampPer(n)
	n = math.floor(tonumber(n) or 5)
	if n < 1 then n = 1 end
	if n > 16 then n = 16 end
	return n
end

local function configNumber(key, fallback)
	local cfg = BALLISTICS.Config
	local n = cfg and cfg[key]
	if type(n) ~= "number" then return fallback end
	return n
end

local function displayPer()
	if state.synced then return clampPer(state.perTeam) end
	return clampPer(configNumber("SlotsPerTeam", state.perTeam))
end

local function localPly()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if IsValid and not IsValid(ply) then return nil end
	return ply
end

local function localId()
	local ply = localPly()
	if not ply or not BALLISTICS.PlayerId then return nil end
	return BALLISTICS.PlayerId(ply)
end

local function localAlive()
	local ply = localPly()
	if not ply or not ply.Alive then return false end
	return ply:Alive() == true
end

local function connectedPlayers()
	local list = {}
	local names = {}
	if not player or not player.GetAll then return list, names end
	local all = player.GetAll()
	if type(all) ~= "table" then return list, names end
	for i = 1, #all do
		local ply = all[i]
		if IsValid(ply) then
			local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply) or nil
			if type(id) == "string" and id ~= "" then
				local name = id
				if ply.Nick then
					local nick = ply:Nick()
					if type(nick) == "string" and nick ~= "" then name = nick end
				end
				list[#list + 1] = { id = id, name = name }
				names[id] = name
			end
		end
	end
	return list, names
end

function BALLISTICS.Lobby.Listen(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function emit()
	for i = 1, #listeners do
		listeners[i]()
	end
end

function BALLISTICS.Lobby.Current()
	return current
end

function BALLISTICS.Lobby.TeamColor(teamId)
	local col = BALLISTICS.TeamColor and BALLISTICS.TeamColor[teamId]
	if not col then return 180, 180, 180 end
	return col.r or 255, col.g or 255, col.b or 255
end

function BALLISTICS.Lobby.View()
	local players, names = connectedPlayers()
	local per = displayPer()
	for teamId = 1, 2 do
		local column = state.sides[teamId] or {}
		for slot = 1, per do
			local entry = column[slot]
			if type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "" then
				if not names[entry.id] and type(entry.name) == "string" and entry.name ~= "" then
					names[entry.id] = entry.name
				end
			end
		end
	end
	local isAdmin = false
	if BALLISTICS.ClientIsAdmin then isAdmin = BALLISTICS.ClientIsAdmin() end
	local flags, box
	local snap = BALLISTICS.Spawns and BALLISTICS.Spawns.Snapshot and BALLISTICS.Spawns.Snapshot()
	local data = BALLISTICS.SpawnData
	if type(snap) == "table" and type(snap.map) == "string" and snap.map ~= "" and type(data) == "table" then
		if type(data.hasBoth) == "function" then flags = data.hasBoth(snap) == true end
		if type(data.hasBox) == "function" then box = data.hasBox(snap) == true end
	end
	current = BALLISTICS.LobbyView.Build({
		perTeam = per,
		sides = state.sides,
		queue = state.queue,
		localId = localId(),
		phase = state.phase,
		isAdmin = isAdmin,
		minPerTeam = configNumber("MinPerTeam", 1),
		alive = localAlive(),
		players = players,
		names = names,
		flags = flags,
		box = box,
	})
	return current
end

local function msg(key, fallback)
	if BALLISTICS.LobbyView and BALLISTICS.LobbyView.Messages then
		local name = BALLISTICS.LobbyView.Messages()[key]
		if type(name) == "string" and name ~= "" then return name end
	end
	return fallback
end

local function sendReady()
	if not net or not net.Start then return end
	net.Start(msg("ready", "bal_lobby_ready"))
	net.SendToServer()
end

function BALLISTICS.Lobby.RequestSlot(teamId, slot)
	local view = BALLISTICS.Lobby.View()
	local decision = BALLISTICS.LobbyView.Click(view, teamId, slot, {
		phase = state.phase,
		alive = localAlive(),
	})
	if (decision.action == "take" or decision.action == "queue") and net and net.Start then
		net.Start(msg("take", "bal_slot_take"))
		net.WriteUInt(decision.team, 8)
		net.WriteUInt(decision.slot, 8)
		net.SendToServer()
	end
	return decision
end

function BALLISTICS.Lobby.RequestStart()
	local view = BALLISTICS.Lobby.View()
	if not view.start.visible or not view.start.enabled then return view.start end
	if net and net.Start then
		net.Start(msg("start", "bal_match_start"))
		net.SendToServer()
	end
	return view.start
end

function BALLISTICS.Lobby.RequestAssign(id, teamId, slot)
	local view = BALLISTICS.Lobby.View()
	local decision = BALLISTICS.LobbyView.Assign(id, teamId, slot, view.perTeam)
	if (decision.action == "assign" or decision.action == "kick") and net and net.Start then
		net.Start(msg("assign", "bal_admin_assign"))
		net.WriteString(decision.id)
		net.WriteUInt(decision.team, 8)
		net.WriteUInt(decision.slot, 8)
		net.SendToServer()
	end
	return decision
end

-- Mirrors sv_slots.lua bal_slots_sync write order.
local function readSlots()
	local per = net.ReadUInt(8)
	local sides = { [GOOD] = {}, [BAD] = {} }
	for teamId = 1, 2 do
		for slot = 1, per do
			if net.ReadBool() then
				sides[teamId][slot] = { id = net.ReadString(), name = net.ReadString() }
			end
		end
	end
	local count = net.ReadUInt(8)
	local queue = {}
	for i = 1, count do
		queue[i] = {
			id = net.ReadString(),
			team = net.ReadUInt(8),
			slot = net.ReadUInt(8),
		}
	end
	return { perTeam = per, sides = sides, queue = queue }
end

-- Mirrors sv_round.lua bal_round_sync. The lobby never draws a countdown.
-- The clock is kept for the round HUD.
local function readRound()
	return {
		phase = net.ReadString(),
		round = net.ReadUInt(16),
		endsAt = net.ReadFloat(),
		enteredAt = net.ReadFloat(),
		scoreGood = net.ReadUInt(16),
		scoreBad = net.ReadUInt(16),
		winner = net.ReadString(),
		reason = net.ReadString(),
		matchWinner = net.ReadString(),
	}
end

local PHASES = { lobby = true, buy = true, live = true, post = true, squad = true }

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register(msg("slots", "bal_slots_sync"), function(payload)
		if type(payload) ~= "table" then return end
		state.synced = true
		state.perTeam = clampPer(payload.perTeam)
		state.sides = payload.sides or { [GOOD] = {}, [BAD] = {} }
		state.queue = payload.queue or {}
		if BALLISTICS.Lobby.Refresh then BALLISTICS.Lobby.Refresh() end
		emit()
	end, { read = readSlots })

	BALLISTICS.Net.Register(msg("round", "bal_round_sync"), function(payload)
		if type(payload) ~= "table" then return end
		if BALLISTICS.RoundHud and BALLISTICS.RoundHud.Apply then
			BALLISTICS.RoundHud.Apply(payload)
		end
		local prev = state.phase
		if PHASES[payload.phase] then state.phase = payload.phase end
		-- The match started: get the lobby popup out of the way of the buy phase.
		if prev == "lobby" and state.phase ~= "lobby" and BALLISTICS.Lobby.Close then
			BALLISTICS.Lobby.Close()
		end
		if BALLISTICS.Lobby.Refresh then BALLISTICS.Lobby.Refresh() end
		emit()
	end, { read = readRound })
end

local function setStatus(text, hold)
	statusText = text or ""
	if hold == false then
		statusUntil = 0
	else
		statusUntil = ((CurTime and CurTime()) or 0) + 4
	end
	if widgets and IsValid(widgets.status) then widgets.status:SetText(statusText) end
end

local function noteDecision(decision)
	if not decision then return end
	if decision.action == "take" then
		setStatus("", false)
		return
	end
	local reason = decision.reason
	if decision.action == "queue" then reason = "queued" end
	local text = BALLISTICS.LobbyView.ReasonText(reason, configNumber("MinPerTeam", 1))
	if text ~= "" then setStatus(text) end
end

function BALLISTICS.Lobby.PaintSlot(w, h, info)
	info = info or {}
	local r, g, b = BALLISTICS.Lobby.TeamColor(info.team)
	local alpha = 50
	if not info.empty then alpha = info.mine and 220 or 160 end
	surface.SetDrawColor(r, g, b, alpha)
	surface.DrawRect(0, 0, w, h)
	if info.mine then
		surface.SetDrawColor(255, 255, 255, 230)
	else
		surface.SetDrawColor(r, g, b, 255)
	end
	surface.DrawOutlinedRect(0, 0, w, h)
	local textCol = Color(245, 245, 245)
	if info.empty and not info.queued then textCol = Color(220, 220, 220) end
	draw.SimpleText(info.label or "", "BallisticsSlot", 12, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function slotInfo(teamId, slot)
	local view = current
	if not view then return nil, nil end
	local columns = view.columns or {}
	for i = 1, #columns do
		if columns[i].team == teamId then
			return columns[i].slots[slot], columns[i]
		end
	end
	return nil, nil
end

local function syncCursor()
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then BALLISTICS.UI.SyncCursor() end
end

local function applyLayout()
	if not IsValid(frame) or not widgets then return end
	local view = current or BALLISTICS.Lobby.View()
	local _, preferredH = BALLISTICS.LobbyView.PreferredSize(view.perTeam)
	local wide = frame:GetWide()
	if wide < 200 then wide = 680 end
	local layout = BALLISTICS.LobbyView.Layout({
		width = wide,
		height = math.max(frame:GetTall() - TITLE, preferredH),
		perTeam = view.perTeam,
	})
	for i = 1, #layout.columns do
		local col = layout.columns[i]
		local header = widgets.headers[col.team]
		if IsValid(header) then
			header:SetPos(col.x, col.y + TITLE)
			header:SetSize(col.w, col.h)
			local count = 0
			local title = col.title or ""
			local infoCol = nil
			for c = 1, #view.columns do
				if view.columns[c].team == col.team then infoCol = view.columns[c] end
			end
			if infoCol then
				count = infoCol.count or 0
				title = infoCol.title or title
			end
			header.balText = string.upper(title) .. "  " .. tostring(count) .. "/" .. tostring(view.perTeam)
		end
		for s = 1, #col.slots do
			local rect = col.slots[s]
			local btn = widgets.slots[col.team] and widgets.slots[col.team][s]
			if IsValid(btn) then
				btn:SetPos(rect.x, rect.y + TITLE)
				btn:SetSize(rect.w, rect.h)
				btn:SetVisible(true)
			end
		end
	end
	local start = layout.start
	if start then
		if IsValid(widgets.start) then
			widgets.start:SetPos(start.x, start.y + TITLE)
			widgets.start:SetSize(start.w, start.h)
			widgets.start:SetVisible(view.start.visible == true)
			widgets.start:SetEnabled(view.start.enabled == true)
		end
		if IsValid(widgets.waiting) then
			widgets.waiting:SetPos(start.x, start.y + TITLE)
			widgets.waiting:SetSize(start.w, start.h)
			widgets.waiting:SetText("Waiting for admin")
			widgets.waiting:SetVisible(view.start.waiting == true)
		end
	end
	if IsValid(widgets.status) and layout.status then
		local rect = layout.status
		widgets.status:SetPos(rect.x, rect.y + TITLE)
		widgets.status:SetSize(rect.w, rect.h)
		local now = (CurTime and CurTime()) or 0
		local text = ""
		if now < statusUntil then
			text = statusText
		elseif view.moveNotice then
			text = view.moveNotice
		elseif view.start.visible and not view.start.enabled then
			text = BALLISTICS.LobbyView.ReasonText(view.start.reason, view.minPerTeam)
		end
		widgets.status:SetText(text)
	end
end

local function ensureSlots(per)
	widgets.slots[GOOD] = widgets.slots[GOOD] or {}
	widgets.slots[BAD] = widgets.slots[BAD] or {}
	for _, teamId in ipairs({ GOOD, BAD }) do
		local col = widgets.slots[teamId]
		for slot = 1, per do
			if not IsValid(col[slot]) then
				local btn = vgui.Create("DButton", frame)
				btn:SetText("")
				btn.DoClick = function()
					noteDecision(BALLISTICS.Lobby.RequestSlot(teamId, slot))
				end
				btn.Paint = function(_, w, h)
					local info = slotInfo(teamId, slot) or { team = teamId, slot = slot, empty = true, label = "Empty" }
					BALLISTICS.Lobby.PaintSlot(w, h, info)
				end
				col[slot] = btn
			end
		end
		for slot = per + 1, 16 do
			if IsValid(col[slot]) then
				col[slot]:SetVisible(false)
				col[slot]:Remove()
			end
			col[slot] = nil
		end
	end
	builtPer = per
end

local function ensureFrame()
	if IsValid(frame) then return frame end
	if not vgui or not vgui.Create then return nil end
	local per = displayPer()
	local wide, tall = BALLISTICS.LobbyView.PreferredSize(per)
	frame = vgui.Create("DFrame")
	frame:SetVisible(false)
	frame:SetTitle("Lobby")
	frame:SetSize(wide, tall + TITLE)
	frame:Center()
	frame:SetDeleteOnClose(false)
	frame:SetSizable(false)
	function frame:OnClose()
		if BALLISTICS.UI then BALLISTICS.UI.Mark("lobby", frame) end
		syncCursor()
	end
	function frame:OnSizeChanged()
		if self.balSizing then return end
		applyLayout()
	end

	widgets = {
		headers = {},
		slots = {},
		start = nil,
		waiting = nil,
		status = nil,
	}
	for _, teamId in ipairs({ GOOD, BAD }) do
		local header = vgui.Create("DPanel", frame)
		header.team = teamId
		header.balText = ""
		header.Paint = function(self, w, h)
			local r, g, b = BALLISTICS.Lobby.TeamColor(self.team)
			surface.SetDrawColor(r, g, b, 255)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(self.balText or "", "BallisticsHeader", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		widgets.headers[teamId] = header
	end
	ensureSlots(per)

	local start = vgui.Create("DButton", frame)
	start:SetText("")
	start.DoClick = function()
		BALLISTICS.Lobby.RequestStart()
	end
	start.Paint = function(self, w, h)
		if self:IsEnabled() then
			surface.SetDrawColor(36, 130, 72, 255)
		else
			surface.SetDrawColor(55, 55, 58, 255)
		end
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("Start", "BallisticsHeader", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	widgets.start = start

	local waiting = vgui.Create("DLabel", frame)
	waiting:SetFont("BallisticsHeader")
	waiting:SetText("Waiting for admin")
	waiting:SetContentAlignment(5)
	if waiting.SetTextColor then waiting:SetTextColor(Color(230, 230, 230)) end
	widgets.waiting = waiting

	local status = vgui.Create("DLabel", frame)
	status:SetFont("BallisticsSmall")
	status:SetText("")
	status:SetContentAlignment(5)
	if status.SetTextColor then status:SetTextColor(Color(230, 220, 170)) end
	widgets.status = status

	if BALLISTICS.UI then BALLISTICS.UI.Mark("lobby", frame) end
	return frame
end

function BALLISTICS.Lobby.Refresh()
	if not IsValid(frame) then
		BALLISTICS.Lobby.View()
		return
	end
	local view = BALLISTICS.Lobby.View()
	if view.perTeam ~= builtPer then
		local wide, tall = BALLISTICS.LobbyView.PreferredSize(view.perTeam)
		frame.balSizing = true
		frame:SetSize(wide, tall + TITLE)
		frame.balSizing = false
		frame:Center()
		ensureSlots(view.perTeam)
	end
	applyLayout()
end

function BALLISTICS.Lobby.IsOpen()
	return IsValid(frame) and frame:IsVisible()
end

function BALLISTICS.Lobby.Open()
	local pnl = ensureFrame()
	if not IsValid(pnl) then return end
	BALLISTICS.Lobby.Refresh()
	pnl:SetVisible(true)
	pnl:MakePopup()
	if BALLISTICS.UI then BALLISTICS.UI.Mark("lobby", pnl) end
	sendReady()
	syncCursor()
end

function BALLISTICS.Lobby.Close()
	if IsValid(frame) then frame:Close() end
end

function BALLISTICS.Lobby.Phase()
	return state.phase
end

function BALLISTICS.Lobby.Toggle()
	if BALLISTICS.Lobby.IsOpen() then
		BALLISTICS.Lobby.Close()
	elseif BALLISTICS.LobbyView.TeamsButtonVisible(state.phase) then
		BALLISTICS.Lobby.Open()
	end
end

-- Console fallback: `bal_teams` toggles the team select (F2 also opens it).
if concommand and concommand.Add then
	concommand.Add("bal_teams", function()
		BALLISTICS.Lobby.Toggle()
	end)
end

-- TEAMS button, top right left of ADMIN, every player, lobby phase only.
-- Without it a closed lobby frame could only come back through F2.
local teamsButton
local function refreshTeamsButton()
	if not vgui or not vgui.Create then return end
	if not IsValid(teamsButton) then
		teamsButton = vgui.Create("DButton")
		teamsButton:SetZPos(32767)
		teamsButton:SetText("")
		teamsButton.DoClick = function()
			BALLISTICS.Lobby.Toggle()
		end
		teamsButton.Paint = function(_, w, h)
			surface.SetDrawColor(28, 28, 32, 230)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(90, 150, 255, 255)
			surface.DrawOutlinedRect(0, 0, w, h)
			draw.SimpleText("TEAMS", "DermaDefaultBold", w / 2, h / 2, Color(190, 215, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	local V = BALLISTICS.LobbyView
	local adminShown = BALLISTICS.ClientIsAdmin and BALLISTICS.ClientIsAdmin() == true
	teamsButton:SetSize(V.TEAMS_W, V.TEAMS_H)
	teamsButton:SetPos(V.TeamsButtonX((ScrW and ScrW()) or 0, adminShown), 10)
	local show = V.TeamsButtonVisible(state.phase)
	teamsButton:SetVisible(show)
	if show then teamsButton:MoveToFront() end
end

timer.Create("Ballistics_TeamsButton", 0.25, 0, refreshTeamsButton)

-- F2 runs GM:ShowTeam on the SERVER only; sv_lobby.lua forwards it here.
if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_lobby_open", function()
		BALLISTICS.Lobby.Open()
	end)
end

local opened = false
local function autoOpen()
	if opened then return end
	opened = true
	BALLISTICS.Lobby.Open()
end

hook.Add("InitPostEntity", "Ballistics_LobbyOpen", function()
	timer.Simple(0, autoOpen)
end)

if localPly() then timer.Simple(0, autoOpen) end

timer.Create("Ballistics_LobbyNames", 0.5, 0, function()
	local lobbyOn = BALLISTICS.Lobby.IsOpen()
	local adminOn = BALLISTICS.Admin and BALLISTICS.Admin.IsOpen and BALLISTICS.Admin.IsOpen()
	if not lobbyOn and not adminOn then return end
	if lobbyOn then BALLISTICS.Lobby.Refresh() end
	emit()
end)
