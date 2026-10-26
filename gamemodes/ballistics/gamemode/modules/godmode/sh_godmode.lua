-- Buy phase god mode: every player takes no damage of any kind while BUY runs.
-- No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.GodMode = BALLISTICS.GodMode or {}

function BALLISTICS.GodMode.Active(phase)
	return phase == "buy"
end

-- ent is protected when the phase is buy and it is a player.
function BALLISTICS.GodMode.Protects(phase, isPlayer)
	return BALLISTICS.GodMode.Active(phase) and isPlayer == true
end
