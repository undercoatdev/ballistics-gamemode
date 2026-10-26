-- Reserve ammo after a gun is given. TacRP's EquipAmmo adds its own magazines
-- (tacrp_defaultammo, default 2) on top of whatever the buyer grants. The
-- reserve we want ignores that injection: it is the pre-give count plus
-- BuyAmmoMags clips of this weapon. No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Ammo = BALLISTICS.Ammo or {}

local function whole(n)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge or n < 0 then return 0 end
	return math.floor(n)
end

function BALLISTICS.Ammo.ReserveTarget(before, clipSize, mags)
	local extra = 0
	if BALLISTICS.Buy and type(BALLISTICS.Buy.AmmoRounds) == "function" then
		extra = BALLISTICS.Buy.AmmoRounds(clipSize, mags) or 0
	end
	extra = whole(extra)
	return whole(before) + extra
end

-- `after` is the count Give left behind, including TacRP's default magazines.
-- It is not used.
function BALLISTICS.Ammo.ReserveAfterGive(before, after, clipSize, mags)
	return BALLISTICS.Ammo.ReserveTarget(before, clipSize, mags)
end

function BALLISTICS.Ammo.ForcedValue()
	return "0"
end
