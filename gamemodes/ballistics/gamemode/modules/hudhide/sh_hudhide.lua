-- Which HUDPaint hooks to hide while TacRP's customize (C) menu is open.
-- No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.HudHide = BALLISTICS.HudHide or {}
local H = BALLISTICS.HudHide

local PREFIXES = { "PlayerBallistics_", "BodyDamage_", "Ballistics_" }
-- Kept on screen: round/game banner and the firing squad FROZEN countdown.
local KEEP = { Ballistics_Banner = true, Ballistics_SquadFreeze = true, Ballistics_HudHideWrap = true }

function H.ShouldHide(name)
	if type(name) ~= "string" or KEEP[name] then return false end
	for i = 1, #PREFIXES do
		if name:sub(1, #PREFIXES[i]) == PREFIXES[i] then return true end
	end
	return false
end

-- wep: active weapon (table or userdata). True when TacRP customize is open.
function H.Customizing(wep)
	if wep == nil then return false end
	local ok, tac = pcall(function() return wep.ArcticTacRP end)
	if not ok or not tac then return false end
	local ok2, on = pcall(function() return wep:GetCustomize() end)
	return ok2 and on == true
end
