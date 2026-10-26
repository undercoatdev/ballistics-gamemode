-- Who keeps weapons, ammo, attachments, and meds into the next buy spawn.
-- Every survivor on either team keeps (win, loss or draw). A death or a new match resets.
-- No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Gear = BALLISTICS.Gear or {}

function BALLISTICS.Gear.Side(team)
	if team == "good" or team == 1 then return "good" end
	if team == "bad" or team == 2 then return "bad" end
	if TEAM_GOOD ~= nil and team == TEAM_GOOD then return "good" end
	if TEAM_BAD ~= nil and team == TEAM_BAD then return "bad" end
	return nil
end

function BALLISTICS.Gear.Keeps(ctx)
	ctx = ctx or {}
	if ctx.matchStart == true then return false end
	if ctx.alive ~= true then return false end
	return BALLISTICS.Gear.Side(ctx.team) ~= nil
end
