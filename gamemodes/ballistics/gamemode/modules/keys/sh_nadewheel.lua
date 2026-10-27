-- TacRP's grenade base sets SWEP.CanQuickNade = false, and DrawGrenadeHUD /
-- PrimeGrenade bail on IsQuickNadeAllowed(), so with a grenade pulled out
-- (wheel middle-click) the throwables wheel is locked out. Turn it back on
-- per weapon instance, both realms. TacRP files are not edited.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Keys = BALLISTICS.Keys or {}
local K = BALLISTICS.Keys

-- A TacRP grenade weapon that blocks the quick-nade wheel.
function K.NeedsNadeUnlock(wep)
	if type(wep) ~= "table" and type(wep) ~= "userdata" then return false end
	if wep.ArcticTacRP ~= true then return false end
	if wep.BallisticsNadeUnlocked == true then return false end
	if wep.CanQuickNade ~= false then return false end
	return wep.SubCatType == "9Throwable" or wep.PrimaryGrenade ~= nil
end

function K.UnlockNade(wep)
	if not K.NeedsNadeUnlock(wep) then return false end
	wep.CanQuickNade = true
	wep.BallisticsNadeUnlocked = true
	return true
end

if hook and hook.Add then
	local nextAt = 0
	hook.Add("Think", "Ballistics_NadeWheelUnlock", function()
		local now = (CurTime and CurTime()) or 0
		if now < nextAt then return end
		nextAt = now + 0.1
		local list = {}
		if CLIENT and LocalPlayer then
			list = { LocalPlayer() }
		elseif player and player.GetAll then
			list = player.GetAll()
		end
		for _, ply in ipairs(list) do
			if IsValid(ply) and type(ply.GetActiveWeapon) == "function" then
				local wep = ply:GetActiveWeapon()
				if IsValid(wep) then K.UnlockNade(wep) end
			end
		end
	end)
end
