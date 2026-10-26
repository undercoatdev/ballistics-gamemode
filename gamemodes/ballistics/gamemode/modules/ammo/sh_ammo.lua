-- Reserve ammo after a gun is given. TacRP's EquipAmmo adds its own magazines
-- (tacrp_defaultammo, default 2) on top of whatever the buyer grants. The
-- reserve we want ignores that injection: it is the pre-give count plus
-- BuyAmmoMags clips of this weapon. 0 magazines means infinite ammo: the
-- convar stays on and nothing writes a finite reserve. No GMod calls.

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

function BALLISTICS.Ammo.WantInfinite(mags)
	mags = tonumber(mags)
	if mags == nil or mags ~= mags or mags == math.huge or mags == -math.huge then return true end
	return math.floor(mags) <= 0
end

function BALLISTICS.Ammo.WritesReserve(mags)
	return not BALLISTICS.Ammo.WantInfinite(mags)
end

-- Squad uses the firing-squad magazine count. Every other phase uses buy mags.
function BALLISTICS.Ammo.ActiveMags(cfg, phase)
	cfg = type(cfg) == "table" and cfg or {}
	local raw = cfg.BuyAmmoMags
	if phase == "squad" then raw = cfg.FiringSquadMags end
	raw = tonumber(raw)
	if raw == nil or raw ~= raw or raw == math.huge or raw == -math.huge then return 0 end
	raw = math.floor(raw)
	if raw < 0 then return 0 end
	if raw > 30 then return 30 end
	return raw
end

function BALLISTICS.Ammo.ForcedValue(mags)
	if mags == nil then
		local phase = "live"
		if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
			phase = BALLISTICS.Round.Phase() or phase
		end
		mags = BALLISTICS.Ammo.ActiveMags(BALLISTICS.Config, phase)
	end
	if BALLISTICS.Ammo.WantInfinite(mags) then return "1" end
	return "0"
end
