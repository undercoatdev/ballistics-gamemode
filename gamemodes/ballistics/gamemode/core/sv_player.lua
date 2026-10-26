-- Join does not spawn you. Round spawns (BUY) strip to the flip knife, force the
-- Combine model, and freeze. Death wipes weapons, ammo, and meds; nothing drops.
-- Dead players spectate a living teammate and do not respawn until the next BUY.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Player = BALLISTICS.Player or {}

local function isPlayer(ply)
	if BALLISTICS.IsPlayer then return BALLISTICS.IsPlayer(ply) end
	return type(ply) == "table"
end

local KNIFE = "tacrp_knife"
local MOVE_NONE = 0
local MOVE_WALK = 2
local SPEC = TEAM_SPEC or 1002
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local tracked = {}

local function moveNone()
	return MOVETYPE_NONE or MOVE_NONE
end

local function moveWalk()
	return MOVETYPE_WALK or MOVE_WALK
end

local function chaseMode()
	return OBS_MODE_CHASE or 5
end

local function roamMode()
	return OBS_MODE_ROAMING or 6
end

local function freezeInBuy()
	local cfg = BALLISTICS.Config
	if not cfg then return true end
	return cfg.FreezeInBuy ~= false
end

local function playingTeam(teamId)
	return teamId == GOOD or teamId == BAD
end

function BALLISTICS.Player.Track(ply)
	if isPlayer(ply) then tracked[ply] = true end
end

function BALLISTICS.Player.Each(fn)
	local seen = {}
	local function one(ply)
		if not isPlayer(ply) or seen[ply] then return end
		if type(ply.IsValid) == "function" and ply:IsValid() ~= true then return end
		seen[ply] = true
		fn(ply)
	end
	for ply in pairs(tracked) do
		one(ply)
	end
	if BALLISTICS.Slots and BALLISTICS.Slots.EachPlayer then
		BALLISTICS.Slots.EachPlayer(function(ply)
			one(ply)
		end)
	end
	if player and player.GetAll then
		local all = player.GetAll()
		if type(all) == "table" then
			for i = 1, #all do
				one(all[i])
			end
		end
	end
end

function BALLISTICS.Player.ModelFor(teamId)
	local cfg = BALLISTICS.Config or {}
	if teamId == GOOD then
		return cfg.ModelGood or "models/player/combine_soldier.mdl"
	end
	if teamId == BAD then
		return cfg.ModelBad or "models/player/combine_super_soldier.mdl"
	end
	return nil
end

function BALLISTICS.Player.SetFrozen(ply, on)
	if not isPlayer(ply) then return end
	on = on and true or false
	ply.balFrozen = on
	if ply.Freeze then ply:Freeze(on) end
	if ply.SetMoveType then ply:SetMoveType(on and moveNone() or moveWalk()) end
end

function BALLISTICS.Player.Wipe(ply)
	if not isPlayer(ply) then return end
	if ply.StripWeapons then ply:StripWeapons() end
	if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
	if ply.StripAmmo then ply:StripAmmo() end
	local ids = { 1, 2, 3, 4 }
	if BALLISTICS.Catalog and BALLISTICS.Catalog.Meds then
		local meds = BALLISTICS.Catalog.Meds()
		if type(meds) == "table" and #meds > 0 then
			ids = {}
			for i = 1, #meds do
				if meds[i].id ~= nil then ids[#ids + 1] = meds[i].id end
			end
		end
	end
	if BALLISTICS.GiveMed then
		for i = 1, #ids do
			BALLISTICS.GiveMed(ply, ids[i], -99)
		end
	end
end

function BALLISTICS.Player.ApplyLoadout(ply)
	if not isPlayer(ply) then return end
	if ply.StripWeapons then ply:StripWeapons() end
	if ply.StripAmmo then ply:StripAmmo() end
	if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
	if ply.SetArmor then ply:SetArmor(0) end
	if ply.SetHealth then
		local max = 100
		if ply.GetMaxHealth then
			local got = ply:GetMaxHealth()
			if type(got) == "number" and got > 0 then max = got end
		end
		ply:SetHealth(max)
	end
	if ply.Give then ply:Give(KNIFE) end
	if ply.SelectWeapon then ply:SelectWeapon(KNIFE) end
	if GM and GM.PlayerSetModel then GM:PlayerSetModel(ply) end
end

function BALLISTICS.Player.MakeSpectator(ply)
	if not isPlayer(ply) then return end
	ply.balNextSpawn = false
	local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply)
	local slotted = nil
	if id and BALLISTICS.Slots and BALLISTICS.Slots.TeamOf then
		slotted = BALLISTICS.Slots.TeamOf(id)
	end
	-- Keep a slotted player's team so the lobby still shows their side.
	if not slotted and ply.SetTeam then ply:SetTeam(SPEC) end
	BALLISTICS.Player.Wipe(ply)
	if ply.Alive and ply:Alive() and ply.KillSilent then ply:KillSilent() end
	if ply.Spectate then ply:Spectate(roamMode()) end
	ply.specTarget = nil
	if ply.SetNoTarget then ply:SetNoTarget(true) end
end

function BALLISTICS.Player.SpectateTeammates(ply)
	if not isPlayer(ply) or not ply.Spectate then return end
	local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply)
	local teamId = nil
	if id and BALLISTICS.Slots and BALLISTICS.Slots.TeamOf then
		teamId = BALLISTICS.Slots.TeamOf(id)
	end
	local target = nil
	if teamId and BALLISTICS.Slots.Members and BALLISTICS.Slots.Player then
		local members = BALLISTICS.Slots.Members(teamId)
		for i = 1, #members do
			if members[i] ~= id then
				local mate = BALLISTICS.Slots.Player(members[i])
				if mate and mate ~= ply and mate.Alive and mate:Alive() then
					target = mate
					break
				end
			end
		end
	end
	if target then
		ply:Spectate(chaseMode())
		if ply.SpectateEntity then ply:SpectateEntity(target) end
		ply.specTarget = target
	else
		ply:Spectate(roamMode())
		ply.specTarget = nil
	end
end

function BALLISTICS.Player.RetargetSpectators(dead)
	if not dead then return end
	BALLISTICS.Player.Each(function(ply)
		if ply == dead then return end
		local watching = ply.specTarget == dead
		if not watching and ply.GetObserverTarget and ply:GetObserverTarget() == dead then
			watching = true
		end
		if watching then BALLISTICS.Player.SpectateTeammates(ply) end
	end)
end

function BALLISTICS.Player.SpawnInRound(ply)
	if not isPlayer(ply) then return false, "player" end
	local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply)
	local teamId, slot = nil, nil
	if id and BALLISTICS.Slots and BALLISTICS.Slots.TeamOf then
		teamId, slot = BALLISTICS.Slots.TeamOf(id)
	end
	if not playingTeam(teamId) then return false, "slot" end
	BALLISTICS.Player.Track(ply)
	ply.balNextSpawn = true
	if ply.SetTeam then ply:SetTeam(teamId) end
	if ply.UnSpectate then ply:UnSpectate() end
	if ply.SetNoTarget then ply:SetNoTarget(false) end
	if ply.Spawn then
		ply:Spawn()
	else
		if GM and GM.PlayerSpawn then GM:PlayerSpawn(ply) end
	end
	-- Spawn() runs every PlayerSpawn hook. Re-apply afterwards so the knife,
	-- model, and freeze are the last word.
	BALLISTICS.Player.ApplyLoadout(ply)
	if BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() == "buy" and freezeInBuy() then
		BALLISTICS.Player.SetFrozen(ply, true)
	end
	local pos, ang
	if BALLISTICS.Round and BALLISTICS.Round.SpawnTransform then
		pos, ang = BALLISTICS.Round.SpawnTransform(teamId, slot)
	end
	if pos and ply.SetPos then ply:SetPos(pos) end
	if ang and ply.SetEyeAngles then ply:SetEyeAngles(ang) end
	return true
end

function GM:PlayerInitialSpawn(ply)
	if not isPlayer(ply) then return end
	ply.balNextSpawn = false
	if ply.SetTeam then ply:SetTeam(SPEC) end
	BALLISTICS.Player.Track(ply)
end

function GM:PlayerSpawn(ply)
	if not isPlayer(ply) then return end
	if not ply.balNextSpawn then
		-- A deferred join-spectator must not undo a round spawn in the same frame.
		local token = ply.balSpawnToken or 0
		local function sendOff()
			if type(ply.IsValid) == "function" and ply:IsValid() ~= true then return end
			if ply.balNextSpawn then return end
			if (ply.balSpawnToken or 0) ~= token then return end
			BALLISTICS.Player.MakeSpectator(ply)
		end
		if timer and timer.Simple then
			timer.Simple(0, sendOff)
		else
			sendOff()
		end
		return
	end
	ply.balNextSpawn = false
	ply.balSpawnToken = (ply.balSpawnToken or 0) + 1
	if self.BaseClass and self.BaseClass.PlayerSpawn then
		self.BaseClass.PlayerSpawn(self, ply)
	end
	BALLISTICS.Player.ApplyLoadout(ply)
	if BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() == "buy" and freezeInBuy() then
		BALLISTICS.Player.SetFrozen(ply, true)
	end
end

-- cl_playermodel is ignored for the two playing teams.
function GM:PlayerSetModel(ply)
	if not isPlayer(ply) then return end
	local teamId = ply.Team and ply:Team() or nil
	local model = BALLISTICS.Player.ModelFor(teamId)
	if model and ply.SetModel then
		ply:SetModel(model)
		return
	end
	if self.BaseClass and self.BaseClass.PlayerSetModel then
		return self.BaseClass.PlayerSetModel(self, ply)
	end
end

function GM:PlayerLoadout(ply)
	BALLISTICS.Player.ApplyLoadout(ply)
end

function GM:DoPlayerDeath(ply, attacker, dmg)
	BALLISTICS.Player.Wipe(ply)
	if self.BaseClass and self.BaseClass.DoPlayerDeath then
		return self.BaseClass.DoPlayerDeath(self, ply, attacker, dmg)
	end
end

function GM:PlayerDeath(ply)
	local function follow()
		if not isPlayer(ply) then return end
		if type(ply.IsValid) == "function" and ply:IsValid() ~= true then return end
		BALLISTICS.Player.SpectateTeammates(ply)
		BALLISTICS.Player.RetargetSpectators(ply)
	end
	if timer and timer.Simple then
		timer.Simple(0, follow)
	else
		follow()
	end
end

-- Death never drops a weapon. A deliberate TacRP drop uses DropWeapon and
-- does not consult this hook, so a dropped gun can still be picked up.
function GM:ShouldDropWeapon()
	return false
end

function GM:PlayerCanPickupWeapon(ply)
	if not isPlayer(ply) then return false end
	if ply.Alive and ply:Alive() == false then return false end
	return true
end

-- Respawn only happens through SpawnInRound at the next BUY.
function GM:PlayerDeathThink()
	return false
end

if hook and hook.Add then
	hook.Add("PlayerDisconnected", "Ballistics_PlayerTrack", function(ply)
		tracked[ply] = nil
	end)

	local function holdStill(ply, mv, cmd)
		if not freezeInBuy() then return end
		if not (BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() == "buy") then return end
		if not isPlayer(ply) then return end
		local teamId = BALLISTICS.Slots and BALLISTICS.Slots.TeamOf and BALLISTICS.Slots.TeamOf(ply)
		if not playingTeam(teamId) then return end
		if ply.Alive and ply:Alive() == false then return end
		if cmd and cmd.ClearMovement then cmd:ClearMovement() end
		if mv then
			if mv.SetMaxClientSpeed then mv:SetMaxClientSpeed(0) end
			if mv.SetMaxSpeed then mv:SetMaxSpeed(0) end
		end
		if ply.SetMoveType then ply:SetMoveType(moveNone()) end
	end

	hook.Add("SetupMove", "Ballistics_BuyFreeze", holdStill)
	hook.Add("StartCommand", "Ballistics_BuyFreeze", function(ply, cmd)
		holdStill(ply, nil, cmd)
	end)
end
