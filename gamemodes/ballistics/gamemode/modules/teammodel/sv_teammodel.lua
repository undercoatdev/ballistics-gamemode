-- Team player models win over Player Ballistics' model select.
-- Cause: PB hooks PlayerSpawn and PlayerSetModel with a timer.Simple(0) that
-- calls PLAYER_BALLISTICS.ApplyModel, which sets the player's PB choice
-- (default Combine Elite). That runs after GM:PlayerSetModel, so everyone
-- (bots included) ended up Elite. We wrap ApplyModel at runtime (PB files
-- untouched): GOOD/BAD players get the team model, anyone else (lobby,
-- unslotted) keeps PB's behaviour.
if not SERVER then return end
BALLISTICS = BALLISTICS or {}
BALLISTICS.TeamModel = BALLISTICS.TeamModel or {}
local T = BALLISTICS.TeamModel

function T.ModelFor(ply)
	if not ply or type(ply.Team) ~= "function" then return nil end
	return BALLISTICS.Player and BALLISTICS.Player.ModelFor and BALLISTICS.Player.ModelFor(ply:Team()) or nil
end

function T.Apply(ply)
	local model = T.ModelFor(ply)
	if not model or type(ply.SetModel) ~= "function" then return false end
	if type(ply.GetModel) ~= "function" or ply:GetModel() ~= model then ply:SetModel(model) end
	return true
end

function T.Wrap()
	local PB = PLAYER_BALLISTICS
	if type(PB) ~= "table" or type(PB.ApplyModel) ~= "function" or PB.BallisticsTeamWrapped then return false end
	local orig = PB.ApplyModel
	PB.ApplyModel = function(ply, ...)
		if T.Apply(ply) then return end
		return orig(ply, ...)
	end
	PB.BallisticsTeamWrapped = true
	return true
end

T.Wrap()
if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_TeamModel", function() T.Wrap() end) -- never return a value: it would stop later hooks (TacRP indexes quick nades here)
	-- Belt and braces: re-apply just after PB's own next-tick timer.
	hook.Add("PlayerSpawn", "Ballistics_TeamModel", function(ply)
		T.Wrap()
		if timer and timer.Simple then
			timer.Simple(0.05, function() if IsValid(ply) then T.Apply(ply) end end)
		end
	end)
end
