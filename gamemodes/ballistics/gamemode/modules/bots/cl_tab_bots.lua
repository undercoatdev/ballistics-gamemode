-- Test Bots admin tab. Buttons ask the server; the count is the local bot list.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Admin = BALLISTICS.Admin or {}

local GOOD = BALLISTICS.TEAM_GOOD or TEAM_GOOD or 1
local BAD = BALLISTICS.TEAM_BAD or TEAM_BAD or 2

local function countBots()
	if player and type(player.GetBots) == "function" then
		local bots = player.GetBots()
		if type(bots) == "table" then return #bots end
	end
	if not player or type(player.GetAll) ~= "function" then return 0 end
	local all = player.GetAll()
	if type(all) ~= "table" then return 0 end
	local n = 0
	for i = 1, #all do
		local ply = all[i]
		if ply and type(ply.IsBot) == "function" and ply:IsBot() == true then
			n = n + 1
		end
	end
	return n
end

local function send(action, team)
	if not net or not net.Start then return end
	local name = "bal_bots"
	if BALLISTICS.Bots and type(BALLISTICS.Bots.Message) == "function" then
		name = BALLISTICS.Bots.Message()
	end
	net.Start(name)
	net.WriteString(action)
	net.WriteUInt(team or 0, 8)
	net.SendToServer()
end

function BALLISTICS.Admin.BuildBots(parent)
	if not IsValid(parent) then return end
	parent:Clear()

	local count = vgui.Create("DLabel", parent)
	count:Dock(TOP)
	count:SetTall(24)
	count:SetText("Bots: " .. tostring(countBots()))
	if count.SetTextColor then count:SetTextColor(Color(230, 230, 230)) end

	local hint = vgui.Create("DLabel", parent)
	hint:Dock(TOP)
	hint:SetTall(36)
	hint:SetWrap(true)
	hint:SetText("Bots stand still. They spawn with everyone else at the next buy.")
	if hint.SetTextColor then hint:SetTextColor(Color(180, 180, 180)) end

	local sp = game and type(game.SinglePlayer) == "function" and game.SinglePlayer() == true
	if sp then
		hint:SetText("Bots need a multiplayer game (11+ slots).")
		if hint.SetTextColor then hint:SetTextColor(Color(255, 170, 90)) end
	end

	local function button(text, action, team)
		local btn = vgui.Create("DButton", parent)
		if sp and btn.SetEnabled then btn:SetEnabled(false) end
		btn:Dock(TOP)
		btn:DockMargin(0, 8, 0, 0)
		btn:SetTall(32)
		btn:SetText(text)
		btn.DoClick = function()
			send(action, team)
		end
	end

	button("Add bot to Good", "add", GOOD)
	button("Add bot to Bad", "add", BAD)
	button("Fill all empty slots", "fill", 0)
	button("Remove all bots", "remove", 0)

	if not (hook and hook.Add) then return end
	local id = "Ballistics_BotTab_" .. tostring(parent)
	local nextAt = 0
	hook.Add("Think", id, function()
		if IsValid and not IsValid(parent) then
			hook.Remove("Think", id)
			return
		end
		local now = (CurTime and CurTime()) or 0
		if now < nextAt then return end
		nextAt = now + 0.25
		if IsValid(count) then
			count:SetText("Bots: " .. tostring(countBots()))
		end
	end)
end

if BALLISTICS.Admin.Register then
	BALLISTICS.Admin.Register("bots", function(parent)
		BALLISTICS.Admin.BuildBots(parent)
	end)
end
