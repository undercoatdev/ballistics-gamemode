-- Left click next teammate, right click previous, while dead in a round.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spectate = BALLISTICS.Spectate or {}
local S = BALLISTICS.Spectate

local function phase()
	return BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase()
end

if hook and hook.Add then
	hook.Add("KeyPress", "Ballistics_Spectate", function(ply, key)
		local slotted = BALLISTICS.Slots and BALLISTICS.Slots.TeamOf and BALLISTICS.Slots.TeamOf(ply)
		if not S.ShouldFollow(phase(), slotted ~= nil) then return end
		if not ply or type(ply.Alive) ~= "function" or ply:Alive() then return end
		local dir = nil
		if key == (IN_ATTACK or 1) then dir = 1 elseif key == (IN_ATTACK2 or 2048) then dir = -1 end
		if not dir then return end
		if BALLISTICS.Player and BALLISTICS.Player.SpectateTeammates then
			BALLISTICS.Player.SpectateTeammates(ply, dir)
		end
	end)
end
