-- Kill reward decision. No GMod calls.
-- A kill pays only when a player on the other team gets the kill during LIVE.
-- Teamkills, suicides, world deaths, and deaths outside LIVE pay nothing.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Gains = BALLISTICS.Gains or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local function playing(teamId)
	return teamId == GOOD or teamId == BAD
end

-- ctx.phase is the round phase.
-- ctx.suicide is true when the attacker is the victim.
-- ctx.attackerIsPlayer is attacker:IsPlayer().
-- ctx.victimTeam and ctx.attackerTeam are slot teams, or nil.
-- Returns "kill", or nil when nothing is paid.
function BALLISTICS.Gains.KillReward(ctx)
	if type(ctx) ~= "table" then return nil end
	if ctx.phase ~= "live" then return nil end
	if ctx.attackerIsPlayer ~= true then return nil end
	if ctx.suicide == true then return nil end
	if not playing(ctx.victimTeam) or not playing(ctx.attackerTeam) then return nil end
	if ctx.victimTeam == ctx.attackerTeam then return nil end
	return "kill"
end
