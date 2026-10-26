-- Lobby requests that must run on the server. Start is admin-only and rate
-- limited by BALLISTICS.Net.Register before StartMatch sees the player.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}

local function message(key, fallback)
	local view = BALLISTICS.LobbyView
	if view and view.Messages then
		local name = view.Messages()[key]
		if type(name) == "string" and name ~= "" then return name end
	end
	return fallback
end

local function tell(ply, text)
	if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return end
	if ply.ChatPrint then ply:ChatPrint(text) end
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register(message("start", "bal_match_start"), function(ply)
		if not BALLISTICS.StartMatch then return end
		local ok, err = BALLISTICS.StartMatch(ply)
		if ok then
			tell(ply, "Ballistics: match started")
		else
			local text = tostring(err)
			local view = BALLISTICS.LobbyView
			local minPer = BALLISTICS.Config and BALLISTICS.Config.MinPerTeam
			if view and type(view.ReasonText) == "function" then
				local nice = view.ReasonText(err, minPer)
				if type(nice) == "string" and nice ~= "" then text = nice end
			end
			tell(ply, "Ballistics: cannot start (" .. text .. ")")
		end
	end, { admin = true, rate = 4 })

	-- Client says the lobby is open. Push slots, phase, and config in case the
	-- PlayerInitialSpawn sync raced the client's net.Receive.
	BALLISTICS.Net.Register(message("ready", "bal_lobby_ready"), function(ply)
		if BALLISTICS.Slots and BALLISTICS.Slots.Broadcast then
			BALLISTICS.Slots.Broadcast(ply)
		end
		if BALLISTICS.Round and BALLISTICS.Round.Broadcast then
			BALLISTICS.Round.Broadcast(ply)
		end
		if BALLISTICS.BroadcastConfig then BALLISTICS.BroadcastConfig(ply) end
		if BALLISTICS.Spawns and BALLISTICS.Spawns.Sync then
			BALLISTICS.Spawns.Sync(ply)
		end
	end, { rate = 2 })

	-- F2 (gm_showteam) calls GM:ShowTeam server-side; tell that client to open the lobby.
	BALLISTICS.Net.Register("bal_lobby_open")
	function GM:ShowTeam(ply)
		BALLISTICS.Net.Send("bal_lobby_open", ply)
	end
end
