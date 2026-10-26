-- Admin test bots. They take real slots and then stand still.
-- A bot has no client, so this file never opens the buy wheel or the lobby.
-- Idle input is cleared here; the forced-open buy menu stays a client concern.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Bots = BALLISTICS.Bots or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local function phaseNow()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		local phase = BALLISTICS.Round.Phase()
		if type(phase) == "string" and phase ~= "" then return phase end
	end
	return "lobby"
end

local function limit()
	if BALLISTICS.Slots and type(BALLISTICS.Slots.Limit) == "function" then
		return BALLISTICS.Slots.Limit()
	end
	local n = BALLISTICS.Config and BALLISTICS.Config.SlotsPerTeam
	return BALLISTICS.Bots.Limit(n)
end

local function playerCount()
	if player and type(player.GetCount) == "function" then
		local n = tonumber(player.GetCount())
		if n and n >= 0 then return math.floor(n) end
	end
	if player and type(player.GetAll) == "function" then
		local all = player.GetAll()
		if type(all) == "table" then return #all end
	end
	return 0
end

-- Singleplayer reports maxplayers 1, and CreateNextBot still joins there.
-- A dedicated server with a lower cap is honored. The gamemode ceiling stays 10.
local function playerCap()
	local cap = BALLISTICS.Bots.MaxPlayers()
	if game and type(game.SinglePlayer) == "function" and game.SinglePlayer() then
		return cap
	end
	if game and type(game.MaxPlayers) == "function" then
		local n = tonumber(game.MaxPlayers())
		if n and n >= 2 and n < cap then return math.floor(n) end
	end
	return cap
end

local function occupancy()
	local per = limit()
	local sides = { [GOOD] = {}, [BAD] = {} }
	if not (BALLISTICS.Slots and type(BALLISTICS.Slots.Members) == "function") then
		return sides, per
	end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local members = BALLISTICS.Slots.Members(teamId) or {}
		for i = 1, #members do
			local id = members[i]
			local slot = BALLISTICS.Slots.SlotOf and BALLISTICS.Slots.SlotOf(id)
			if slot then sides[teamId][slot] = id end
		end
	end
	if type(BALLISTICS.Slots.NetPayload) == "function" then
		local payload = BALLISTICS.Slots.NetPayload()
		local queue = payload and payload.queue or {}
		for i = 1, #queue do
			local q = queue[i]
			local teamId = tonumber(q.team)
			local slot = tonumber(q.slot)
			if sides[teamId] and slot and sides[teamId][slot] == nil then
				sides[teamId][slot] = q.id or true
			end
		end
	end
	return sides, per
end

local function context(team)
	local sides, per = occupancy()
	local taken = nil
	if type(sides) == "table" then taken = sides[tonumber(team)] end
	return {
		team = team,
		sides = sides,
		taken = taken,
		limit = per,
		playerCount = playerCount(),
		maxPlayers = playerCap(),
	}
end

local function tell(ply, text)
	if ply ~= nil and type(ply.ChatPrint) == "function" then
		ply:ChatPrint(text)
	end
end

local function eachBot(fn)
	local list = {}
	if player and type(player.GetBots) == "function" then
		local bots = player.GetBots()
		if type(bots) == "table" then list = bots end
	elseif player and type(player.GetAll) == "function" then
		local all = player.GetAll() or {}
		for i = 1, #all do
			local ply = all[i]
			if ply and type(ply.IsBot) == "function" and ply:IsBot() == true then
				list[#list + 1] = ply
			end
		end
	end
	for i = 1, #list do
		local ply = list[i]
		if ply and (type(ply.IsBot) ~= "function" or ply:IsBot() == true) then
			fn(ply)
		end
	end
end

function BALLISTICS.Bots.Count()
	local n = 0
	eachBot(function()
		n = n + 1
	end)
	return n
end

local function spectate(bot)
	if BALLISTICS.Player and type(BALLISTICS.Player.MakeSpectator) == "function" then
		BALLISTICS.Player.MakeSpectator(bot)
		return
	end
	if type(bot.Alive) == "function" and bot:Alive() and type(bot.KillSilent) == "function" then
		bot:KillSilent()
	end
end

local function create(name)
	if not (player and type(player.CreateNextBot) == "function") then return nil end
	local bot = player.CreateNextBot(name)
	if bot == nil then return nil end
	return bot
end

-- Drop a bot we could not slot so it does not sit in the player list.
local function discard(bot)
	if bot and type(bot.Kick) == "function" then bot:Kick("Ballistics: test bot removed") end
end

local function place(bot, teamId, slot)
	local phase = phaseNow()
	-- Killing a bot we are about to round-spawn queues a death follow that
	-- would spectate them again. Buy spawns through the slot request instead.
	if not BALLISTICS.Bots.SpawnNow(phase) then
		spectate(bot)
	end
	if not (BALLISTICS.Slots and type(BALLISTICS.Slots.Request) == "function") then
		return false, "slots"
	end
	return BALLISTICS.Slots.Request(bot, teamId, slot)
end

local function addOne(row)
	local bot = create(row.name)
	if bot == nil then return false, "create" end
	local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(bot)
	if not id then
		discard(bot)
		return false, "player"
	end
	local ok, err = place(bot, row.team, row.slot)
	if not ok then
		discard(bot)
		return false, err
	end
	return true, { action = "add", team = row.team, slot = row.slot, queued = err == "queued", id = id }
end

local function removeAll()
	local doomed = {}
	eachBot(function(ply)
		doomed[#doomed + 1] = ply
	end)
	for i = 1, #doomed do
		local ply = doomed[i]
		if BALLISTICS.Slots and type(BALLISTICS.Slots.Leave) == "function" then
			BALLISTICS.Slots.Leave(ply)
		end
		if type(ply.Kick) == "function" then
			ply:Kick("Ballistics: test bot removed")
		end
	end
	return #doomed
end

function BALLISTICS.Bots.Handle(ply, payload)
	payload = type(payload) == "table" and payload or {}
	local isAdmin = BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply) == true
	local decision, err = BALLISTICS.Bots.Admit(isAdmin, payload.action, context(payload.team))
	if not decision then
		if err == "admin" then
			tell(ply, "Ballistics: admin only")
		elseif err == "team" then
			tell(ply, "Ballistics: that team is not available.")
		elseif err == "full" then
			tell(ply, "Ballistics: that team is full.")
		elseif err == "players" then
			tell(ply, "Ballistics: the server is full.")
		end
		return false, err
	end
	if decision.action == "remove" then
		local n = removeAll()
		tell(ply, "Ballistics: removed " .. tostring(n) .. " bots.")
		return true, { action = "remove", removed = n }
	end
	if decision.action == "fill" then
		local n = 0
		local plan = decision.plan or {}
		for i = 1, #plan do
			local ok = addOne(plan[i])
			if ok then n = n + 1 end
		end
		tell(ply, "Ballistics: added " .. tostring(n) .. " bots.")
		return true, { action = "fill", added = n }
	end
	local ok, detail = addOne(decision)
	if not ok then
		if detail == "full" then
			tell(ply, "Ballistics: that team is full.")
		elseif detail == "players" then
			tell(ply, "Ballistics: the server is full.")
		end
		return false, detail
	end
	tell(ply, "Ballistics: added " .. decision.name .. ".")
	return true, detail
end

local function idle(ply, cmd, mv)
	if ply == nil or type(ply.IsBot) ~= "function" or ply:IsBot() ~= true then return end
	if cmd ~= nil then
		if type(cmd.ClearButtons) == "function" then cmd:ClearButtons() end
		if type(cmd.ClearMovement) == "function" then cmd:ClearMovement() end
		if type(cmd.SetViewAngles) == "function" and type(ply.EyeAngles) == "function" then
			local ang = ply:EyeAngles()
			if ang ~= nil then cmd:SetViewAngles(ang) end
		end
	end
	if mv ~= nil then
		if type(mv.SetForwardSpeed) == "function" then mv:SetForwardSpeed(0) end
		if type(mv.SetSideSpeed) == "function" then mv:SetSideSpeed(0) end
		if type(mv.SetUpSpeed) == "function" then mv:SetUpSpeed(0) end
		if type(mv.SetButtons) == "function" then mv:SetButtons(0) end
		if type(mv.SetMaxClientSpeed) == "function" then mv:SetMaxClientSpeed(0) end
		if type(mv.SetMaxSpeed) == "function" then mv:SetMaxSpeed(0) end
	end
end

if hook and hook.Add then
	hook.Add("StartCommand", "Ballistics_BotIdle", function(ply, cmd)
		idle(ply, cmd, nil)
	end)
	hook.Add("SetupMove", "Ballistics_BotIdle", function(ply, mv, cmd)
		idle(ply, cmd, mv)
	end)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	-- string action ("add", "fill", "remove"), uint8 team (Good or Bad for add).
	BALLISTICS.Net.Register(BALLISTICS.Bots.Message(), function(ply, payload)
		BALLISTICS.Bots.Handle(ply, payload)
	end, {
		admin = true,
		rate = 5,
		read = function()
			return { action = net.ReadString(), team = net.ReadUInt(8) }
		end,
	})
end
